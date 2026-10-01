param([string]$Artifacts = (Join-Path $PSScriptRoot '../test-artifacts'))
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $root 'gui-support.psm1')
New-Item -ItemType Directory -Path $Artifacts -Force | Out-Null
$Artifacts = (Resolve-Path -LiteralPath $Artifacts).Path
$ffmpeg = Join-Path $root 'ffmpeg.exe'
$ffprobe = Join-Path $root 'ffprobe.exe'
$powershell = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Probe([string]$Path) {
    $json = & $ffprobe -v error -show_streams -show_format -of json $Path
    Assert ($LASTEXITCODE -eq 0) "Unplayable output: $Path"
    return ($json | ConvertFrom-Json)
}
function Run-Compression {
    param([string]$Name, [string[]]$Inputs, [hashtable]$Changes=@{}, [int]$ExpectedExit=0)
    $settings = Read-Preferences ''
    $settings.mode='libx264'; $settings.preset='fast'; $settings.target_size_mb='1.4'
    $settings.output_dir=Join-Path $Artifacts $Name
    foreach ($key in $Changes.Keys) { $settings[$key]=$Changes[$key] }
    $conf=Join-Path $Artifacts "$Name.conf"
    Save-Preferences $conf $settings
    $stdout=Join-Path $Artifacts "$Name.stdout.log"
    $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'shrinkwrap.ps1'),'-NonInteractive','-ConfigPath',$conf) + $Inputs
    $ErrorActionPreference='Continue'
    & $powershell @arguments 2>&1 | ForEach-Object { "$_" } | Out-File -LiteralPath $stdout -Encoding UTF8
    $code=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    Assert ($code -eq $ExpectedExit) "Unexpected exit $code for $Name. See $stdout"
    if ($ExpectedExit -eq 0) {
        $outputs=@(Get-ChildItem -LiteralPath $settings.output_dir -Filter '*_optimized.mp4')
        Assert ($outputs.Count -gt 0) "No outputs for $Name"
        foreach ($output in $outputs) {
            Assert ($output.Length -le ([double]$settings.target_size_mb * 1000000)) "Output exceeds exact cap: $output"
            Assert ($output.Length -gt 0) "Empty output: $output"
            $info=Probe $output.FullName
            Assert (@($info.streams | Where-Object codec_type -eq 'video').Count -eq 1) 'Output must contain video.'
        }
        Assert (@(Get-ChildItem -LiteralPath $settings.output_dir -Directory -Force -Filter '.shrinkwrap-*').Count -eq 0) 'Scratch directory was not cleaned.'
    }
    return $settings.output_dir
}

# Parser verification uses the Windows PowerShell 5.1 parser, not only PowerShell 7.
$tokens=$null; $errors=$null
foreach ($script in (Get-ChildItem -LiteralPath $root -File | Where-Object Extension -in '.ps1','.psm1')) {
    [Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors) | Out-Null
    Assert ($errors.Count -eq 0) "Syntax errors in $($script.Name): $errors"
}
$clip=Join-Path $Artifacts 'clip [one] ! &.mp4'
& $ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc2=size=640x360:rate=30:duration=12 -f lavfi -i sine=frequency=400:duration=12 -c:v libx264 -preset ultrafast -crf 16 -g 30 -c:a aac -shortest -y $clip
Assert ($LASTEXITCODE -eq 0) 'Fixture generation failed.'
$inputHash=(Get-FileHash -LiteralPath $clip).Hash
$null=Run-Compression 'x264' @($clip)
$null=Run-Compression 'x265' @($clip) @{mode='software'}
$null=Run-Compression 'gpu-auto' @($clip) @{mode='auto'}
$null=Run-Compression 'nvenc-h264' @($clip) @{mode='h264_nvenc'}
$null=Run-Compression 'nvenc-hevc' @($clip) @{mode='hevc_nvenc'}
$audioDir=Run-Compression 'audio-controls' @($clip) @{target_size_mb='8';normalize_audio='true';mono='true'}
$info=Probe (Get-ChildItem -LiteralPath $audioDir -Filter '*.mp4' | Select-Object -First 1).FullName
Assert (@($info.streams | Where-Object codec_type -eq 'audio')[0].channels -eq 1) 'Mono ignored on under-cap input.'
$silentDir=Run-Compression 'strip-audio' @($clip) @{target_size_mb='8';no_audio='true'}
$info=Probe (Get-ChildItem -LiteralPath $silentDir -Filter '*.mp4' | Select-Object -First 1).FullName
Assert (@($info.streams | Where-Object codec_type -eq 'audio').Count -eq 0) 'Remove audio ignored.'
$mkv=Join-Path $Artifacts 'remux.mkv'
& $ffmpeg -hide_banner -loglevel error -i $clip -c copy -y $mkv
$null=Run-Compression 'remux' @($mkv) @{target_size_mb='8'}
$odd=Join-Path $Artifacts 'odd-width.mp4'
& $ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc=size=641x359:rate=24:duration=2 -c:v libx264 -pix_fmt yuv444p -y $odd
Assert ($LASTEXITCODE -eq 0) 'Odd-width fixture failed.'
$oddDir=Run-Compression 'odd-width' @($odd) @{mono='true'}
$info=Probe (Get-ChildItem -LiteralPath $oddDir -Filter '*.mp4' | Select-Object -First 1).FullName
$video=@($info.streams | Where-Object codec_type -eq 'video')[0]
Assert ($video.width % 2 -eq 0 -and $video.height % 2 -eq 0 -and $video.pix_fmt -eq 'yuv420p') 'Odd dimensions are not encoder-safe.'
$splitDir=Run-Compression 'split' @($clip) @{target_size_mb='0.45';min_video_bitrate='1000';max_retries='1'}
Assert (@(Get-ChildItem -LiteralPath $splitDir -Filter '*_PART_*_optimized.mp4').Count -ge 2) 'Split fallback was not exercised.'
$bad=Join-Path $Artifacts 'corrupt.mp4'
[IO.File]::WriteAllText($bad,'not a video')
$null=Run-Compression 'invalid-input' @($bad) @{} 1

# A second run must refuse to replace a completed video or remove unrelated logs.
$protected=Join-Path $Artifacts 'x264/clip [one] ! &_optimized.mp4'
$before=(Get-FileHash -LiteralPath $protected).Hash
$logFile=Join-Path $Artifacts 'x264/my-important.log'
[IO.File]::WriteAllText($logFile,'keep me')
$null=Run-Compression 'x264' @($clip) @{} 1
Assert ((Get-FileHash -LiteralPath $protected).Hash -eq $before) 'Existing output changed.'
Assert ([IO.File]::ReadAllText($logFile) -eq 'keep me') 'Unrelated log deleted.'
Assert ((Get-FileHash -LiteralPath $clip).Hash -eq $inputHash) 'Input video changed.'

$defaults=Read-Preferences ''
$defaults.target_size_mb='NaN'
$rejected=$false
try { Test-Preferences $defaults } catch { $rejected=$true }
Assert $rejected 'NaN target accepted.'
$defaults=Read-Preferences ''
$prefs=Join-Path $Artifacts 'roundtrip.conf'
Save-Preferences $prefs $defaults
$loaded=Read-Preferences $prefs
Assert ($loaded.hardware_order -eq $defaults.hardware_order -and $loaded.mode -eq 'auto') 'Preference round-trip failed.'

# GUI construction and drawing run offscreen; no interactive session is required.
$form=& (Join-Path $root 'compressor-gui.ps1') -TestMode
$form.ShowInTaskbar=$false; $form.StartPosition='Manual'; $form.Location=New-Object Drawing.Point(-30000,-30000)
$form.Show(); $form.PerformLayout(); [Windows.Forms.Application]::DoEvents()
$bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)))
$bitmap.Save((Join-Path $Artifacts 'gui.png')); $bitmap.Dispose(); $form.Dispose()

# Exercise the actual GUI worker: JSON file paths, log streaming, and Job supervision.
$defaults.output_dir=Join-Path $Artifacts 'gui-worker'
$defaults.target_size_mb='1.4'; $defaults.preset='fast'
$run=Start-CompressorWorker $root @($clip) $defaults
try {
    Assert ($run.Worker.Process.WaitForExit(60000)) 'GUI worker timed out.'
    $run.Worker.Process.WaitForExit()
    Assert ($run.Worker.Process.ExitCode -eq 0) 'GUI worker failed.'
    Assert ($run.Worker.Lines.Count -gt 10) 'GUI live log is empty.'
} finally { Close-CompressorWorker $run }
$defaults.mode='libx265'; $defaults.preset='veryslow'; $defaults.output_dir=Join-Path $Artifacts 'gui-cancel'
$run=Start-CompressorWorker $root @($clip) $defaults
try {
    $deadline=[DateTime]::UtcNow.AddSeconds(15)
    $children=@()
    while ($children.Count -eq 0 -and [DateTime]::UtcNow -lt $deadline) {
        $children=@(Get-CimInstance Win32_Process -Filter "ParentProcessId = $($run.Worker.Process.Id)" | Where-Object Name -eq 'ffmpeg.exe')
        Start-Sleep -Milliseconds 100
    }
    Assert ($children.Count -gt 0) 'Cancellation fixture did not start FFmpeg.'
    $run.Worker.Cancel()
    Assert ($run.Worker.Process.WaitForExit(5000)) 'Cancellation did not stop worker.'
    Start-Sleep -Milliseconds 200
    foreach ($child in $children) { Assert ($null -eq (Get-Process -Id $child.ProcessId -ErrorAction SilentlyContinue)) 'Orphan FFmpeg after cancellation.' }
} finally { Close-CompressorWorker $run }
# Inject a runtime GPU failure, then verify the retry produces an actual software video.
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'shrinkwrap.ps1'),[ref]$tokens,[ref]$errors)
$needed=@('Get-PresetInfo','Get-HwPreset','Test-PresetNative','Resolve-PresetToken','Test-EncoderAvailable','Get-SoftwareEncoder','Invoke-FFmpegEncode')
foreach ($node in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] },$false)) {
    if ($node.Name -in $needed) { . ([scriptblock]::Create($node.Extent.Text)) }
}
function Invoke-HwEncode { return 1 }
$Script:FFmpeg=$ffmpeg; $Script:SoftwareOrder=@('libx264'); $Script:CodecFamily='nvenc'
$Script:VideoCodec='h264_nvenc'; $Script:Preset='p3'; $Script:VsyncFlag='-fps_mode cfr'
$Script:OUTPUT_DIR=$Artifacts; $Script:AudioChannels=2; $NoAudio=$false
$retry=Join-Path $Artifacts 'runtime-fallback.mp4'
$result=Invoke-FFmpegEncode -InputFile $clip -OutputFile $retry -VideoParams @{Bitrate=700;Preset='p3'} -AudioParams @{Bitrate=96} -PassLogFile (Join-Path $Artifacts 'runtime-pass') -Pass 2
Assert ($result -eq 0 -and $Script:CodecFamily -eq 'software') 'Runtime GPU fallback did not succeed.'
$info=Probe $retry
Assert (@($info.streams | Where-Object codec_type -eq 'video')[0].codec_name -eq 'h264') 'Runtime fallback did not produce H.264.'
Write-Host 'PASS: Windows encoders, exact caps, audio, remux, split, corrupt input, output protection, preferences, GUI and cancellation.'
