# Shared by the Windows GUI and its tests. No config text is executed as code.
$script:EncoderNames = @('auto','hw','software','software_x264','libx264','libx265',
    'av1_nvenc','av1_amf','av1_qsv','hevc_nvenc','hevc_amf','hevc_qsv','hevc_videotoolbox',
    'h264_nvenc','h264_amf','h264_qsv','h264_videotoolbox')

function Get-SettingsSchema {
    @(
        @{Key='mode'; Label='Encoder'; Default='auto'; Kind='encoder'; Tip='Auto tries AV1, HEVC, then H.264 on your GPU. Software is the fallback.'}
        @{Key='target_size_mb'; Label='Size limit (MB)'; Default='19.8'; Kind='number'; Min=0.25; Max=100000; Tip='Decimal MB (1,000,000 bytes). Every completed output must fit this cap.'}
        @{Key='preset'; Label='Speed / quality'; Default='slow'; Kind='preset'; Tip='Slow favors quality; fast favors speed. Presets map to the selected GPU vendor.'}
        @{Key='output_dir'; Label='Output folder'; Default='optimized'; Kind='path'; Tip='Existing videos are never replaced. Relative paths use the application folder.'}
        @{Key='output_name'; Label='Output name (optional)'; Default=''; Kind='filename'; Tip='Blank: original_optimized.mp4. Custom: My clip.mp4. Batch templates: {name} and {index}. Existing outputs stay intact; new versions get (2), (3), etc.'}
        @{Key='normalize_audio'; Label='Normalize loudness (-16 LUFS)'; Default='false'; Kind='bool'; Tip='Two-pass loudness measurement adds processing time.'}
        @{Key='mono'; Label='Downmix to mono'; Default='false'; Kind='bool'; Tip='Useful for voice clips. Keeps more of the size budget for video.'}
        @{Key='no_audio'; Label='Remove audio'; Default='false'; Kind='bool'; Tip='Overrides normalization and mono.'}
        @{Key='audio_bitrate'; Label='Initial audio bitrate (kbps)'; Default='192'; Kind='integer'; Min=16; Max=512; Tip='Starting AAC bitrate. Any whole value in this range is accepted, including 124 or 127. 64 suits voice; 128-192 suits most clips.'}
        @{Key='min_audio_bitrate'; Label='Minimum audio bitrate (kbps)'; Default='64'; Kind='integer'; Min=16; Max=512; Tip='AAC bitrate floor during retries. Any whole value in this range is accepted. Lower values leave more room for video.'}
        @{Key='min_video_bitrate'; Label='Minimum video bitrate (kbps)'; Default='500'; Kind='integer'; Min=50; Max=50000; Tip='Bitrate floor before downscaling or splitting. Video bitrate is calculated from duration and size.'}
        @{Key='max_retries'; Label='Retries per resolution'; Default='3'; Kind='integer'; Min=1; Max=10; Tip='Maximum convergence attempts at each resolution.'}
        @{Key='crf_rescue_value'; Label='Rescue quality (CRF / CQ)'; Default='28'; Kind='quality'; Min=1; Max=51; Tip='Lower means higher quality and potentially more retries. Choose a suggested value or type an integer from 1 to 51. Quality is not a resolution. AMF/VideoToolbox rescue uses the bitrate budget.'}
        @{Key='hardware_order'; Label='GPU encoder priority'; Default='av1_amf av1_nvenc av1_qsv hevc_amf hevc_nvenc hevc_qsv hevc_videotoolbox h264_nvenc h264_amf h264_qsv h264_videotoolbox'; Kind='hardware'; Tip='Space-separated candidates. First successful test wins. Prefer H.264 for broad playback support.'}
        @{Key='software_order'; Label='Software fallback priority'; Default='libx265 libx264'; Kind='software'; Tip='Space-separated software encoders.'}
        @{Key='no_cleanup'; Label='Keep temporary files and logs'; Default='false'; Kind='bool'; Tip='Preserves the scratch directory for diagnosis.'}
    )
}

function Get-PreferencePath {
    param([string]$Root)
    $local = Join-Path $Root 'shrinkwrap.conf'
    if (Test-Path -LiteralPath $local) { return $local }
    $user = Join-Path $env:APPDATA 'discord-video-compressor/shrinkwrap.conf'
    if (Test-Path -LiteralPath $user) { return $user }
    $legacy = Join-Path $env:APPDATA 'ffmpeg-shrinkwrap/shrinkwrap.conf'
    if (Test-Path -LiteralPath $legacy) { return $legacy }
    return $local
}

function Read-Preferences {
    param([string]$Path)
    $values = [ordered]@{}
    foreach ($item in (Get-SettingsSchema)) { $values[$item.Key] = $item.Default }
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        foreach ($raw in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
            if ($raw -match '^\s*([a-z_]+)\s*=\s*(.*?)\s*$' -and $values.Contains($Matches[1])) {
                $values[$Matches[1]] = $Matches[2]
            }
        }
    }
    if ($values.mode -eq 'hardware') { $values.mode = 'auto' }
    return $values
}

function Test-Preferences {
    param([System.Collections.IDictionary]$Values)
    $inv = [Globalization.CultureInfo]::InvariantCulture
    foreach ($item in (Get-SettingsSchema)) {
        $value = [string]$Values[$item.Key]
        if ($value.Contains("`n") -or $value.Contains("`r")) { throw "Invalid newline in $($item.Label)." }
        switch ($item.Kind) {
            { $_ -in 'number','integer','quality' } {
                $number = 0.0
                if (-not [double]::TryParse($value, [Globalization.NumberStyles]::Float, $inv, [ref]$number) -or
                    [double]::IsNaN($number) -or [double]::IsInfinity($number) -or
                    $number -lt $item.Min -or $number -gt $item.Max -or
                    ($item.Kind -in 'integer','quality' -and $number -ne [math]::Floor($number))) {
                    throw "$($item.Label) must be between $($item.Min) and $($item.Max). Use a dot for decimals."
                }
            }
            'bool' { if ($value -notin 'true','false') { throw "Invalid boolean: $($item.Label)" } }
            'encoder' { if ($value -notin $script:EncoderNames) { throw 'Unsupported encoder selection.' } }
            'hardware' {
                foreach ($name in @($value -split '\s+')) {
                    if ($name -notin $script:EncoderNames -or $name -notmatch '_(nvenc|amf|qsv|videotoolbox)$') { throw "Invalid GPU encoder: $name" }
                }
            }
            'software' {
                foreach ($name in @($value -split '\s+')) { if ($name -notin 'libx264','libx265') { throw "Invalid software encoder: $name" } }
            }
            'path' { if ([string]::IsNullOrWhiteSpace($value)) { throw 'Choose an output folder.' } }
            'filename' {
                $remaining=$value.Replace('{name}','').Replace('{index}','')
                if ($value -and ($value -match '[<>:"/\\|?*\x00-\x1f]' -or $remaining.Contains('{') -or $remaining.Contains('}') -or
                    $value -match '[. ]$' -or $value.Length -gt 200 -or
                    $value -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)')) {
                    throw 'Output name must be a filename, with optional {name} and {index} placeholders; no folders or reserved device names.'
                }
            }
            'preset' { if ($value -notmatch '^(ultrafast|superfast|veryfast|faster|fast|medium|slow|slower|veryslow|placebo|quality|balanced|speed|p[1-7])$') { throw 'Unsupported preset.' } }
        }
    }
    if ([int]$Values.audio_bitrate -lt [int]$Values.min_audio_bitrate) { throw 'Initial audio bitrate must be at least the minimum audio bitrate.' }
}

function Save-Preferences {
    param([string]$Path, [System.Collections.IDictionary]$Values)
    Test-Preferences $Values
    $lines = @('# Discord Video Compressor - Hardware Encoding preferences (MIT).')
    foreach ($item in (Get-SettingsSchema)) {
        $value = $Values[$item.Key]
        if ($item.Key -eq 'mode' -and $value -in 'auto','hw') { $value = 'hardware' }
        $lines += "$($item.Key) = $value"
    }
    [IO.File]::WriteAllText($Path, ($lines -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))
}

function Get-EncoderNames { return $script:EncoderNames }

function Get-EncoderOptions {
    foreach ($name in $script:EncoderNames) {
        $description = switch ($name) {
            'auto' { 'Automatic GPU, then CPU; fast / playback varies' }
            'hw' { 'Automatic GPU, then CPU; same as auto' }
            'software' { 'CPU H.265 then H.264; efficient at small sizes / slower' }
            'software_x264' { 'CPU H.264; broad playback / less efficient than H.265' }
            'libx264' { 'CPU H.264; broad playback / less efficient than H.265' }
            'libx265' { 'CPU H.265; efficient compression / slower, playback varies' }
            default {
                $vendor = if ($name -like '*_nvenc') { 'NVIDIA GPU' } elseif ($name -like '*_amf') { 'AMD GPU' } elseif ($name -like '*_qsv') { 'Intel GPU' } else { 'macOS hardware' }
                if ($name -like 'av1_*') { "$vendor AV1; efficient / newer GPU, playback varies" }
                elseif ($name -like 'hevc_*') { "$vendor H.265; efficient / playback varies" }
                else { "$vendor H.264; broad playback / larger at equal quality" }
            }
        }
        [pscustomobject]@{Value=$name;Label="$name ($description)"}
    }
}

function Get-PresetOptions {
    foreach ($name in @('slow','medium','fast','ultrafast','superfast','veryfast','faster','slower','veryslow','placebo','quality','balanced','speed','p1','p2','p3','p4','p5','p6','p7')) {
        $description = switch -Regex ($name) {
            '^(ultrafast|superfast|veryfast|faster|fast|speed|p[1-3])$' { 'faster / lower compression quality'; break }
            '^(medium|balanced|p[4-5])$' { 'balanced speed and quality'; break }
            default { 'better compression quality / slower' }
        }
        [pscustomobject]@{Value=$name;Label="$name ($description)"}
    }
}

function Get-QualityOptions {
    @(
        [pscustomobject]@{Value='18';Label='18 (more detail / harder to fit)'}
        [pscustomobject]@{Value='23';Label='23 (balanced detail and size)'}
        [pscustomobject]@{Value='28';Label='28 (smaller / default)'}
        [pscustomobject]@{Value='32';Label='32 (lower detail / smaller)'}
        [pscustomobject]@{Value='36';Label='36 (least detail / smallest)'}
    )
}

function Get-ControlPreferences {
    param([System.Collections.IDictionary]$Fields)
    $values=[ordered]@{}
    foreach ($item in (Get-SettingsSchema)) {
        $field=$Fields[$item.Key]
        $values[$item.Key] = if ($item.Kind -eq 'bool') { $field.Checked.ToString().ToLowerInvariant() }
            elseif ($item.Kind -eq 'integer') { $field.Value.ToString([Globalization.CultureInfo]::InvariantCulture) }
            elseif ($item.Kind -in 'encoder','preset','quality' -and $field.SelectedItem -and $field.Text -eq $field.GetItemText($field.SelectedItem)) { $field.SelectedItem.Value }
            else { $field.Text.Trim() }
    }
    Test-Preferences $values
    return $values
}

# The events run on .NET threads, never a PowerShell scriptblock without a runspace.
# The Job object kills descendants when closed, including FFmpeg during cancellation.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
public sealed class CompressorWorker : IDisposable {
    public readonly ConcurrentQueue<string> Lines = new ConcurrentQueue<string>();
    public Process Process { get; private set; }
    IntPtr job;
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr a, string n);
    [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr j, int c, ref Limits l, int s);
    [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
    [DllImport("kernel32.dll")] static extern bool TerminateJobObject(IntPtr j, uint c);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] struct Basic { public long p,u; public uint flags; public UIntPtr min,max; public uint count; public UIntPtr affinity; public uint priority,scheduling; }
    [StructLayout(LayoutKind.Sequential)] struct IO { public ulong a,b,c,d,e,f; }
    [StructLayout(LayoutKind.Sequential)] struct Limits { public Basic basic; public IO io; public UIntPtr process,job,peakProcess,peakJob; }
    public void Start(string executable, string arguments, string root, string request, string gate) {
        job = CreateJobObject(IntPtr.Zero, null);
        var limits = new Limits(); limits.basic.flags = 0x2000;
        if (job == IntPtr.Zero || !SetInformationJobObject(job, 9, ref limits, Marshal.SizeOf(typeof(Limits)))) throw new InvalidOperationException("Cannot create process job.");
        var info = new ProcessStartInfo(executable, arguments) { UseShellExecute=false, CreateNoWindow=true, WorkingDirectory=root, RedirectStandardOutput=true, RedirectStandardError=true };
        info.StandardOutputEncoding = System.Text.Encoding.UTF8; info.StandardErrorEncoding = System.Text.Encoding.UTF8;
        info.EnvironmentVariables["SHRINKWRAP_REQUEST"] = request;
        info.EnvironmentVariables["SHRINKWRAP_GATE"] = gate;
        Process = new Process { StartInfo=info };
        Process.OutputDataReceived += (s,e) => { if (e.Data != null) Lines.Enqueue(e.Data); };
        Process.ErrorDataReceived += (s,e) => { if (e.Data != null) Lines.Enqueue(e.Data); };
        Process.Start();
        if (!AssignProcessToJobObject(job, Process.Handle)) { Process.Kill(); throw new InvalidOperationException("Cannot supervise encoder process."); }
        Process.BeginOutputReadLine(); Process.BeginErrorReadLine();
        System.IO.File.WriteAllText(gate, "ready");
    }
    public void Cancel() { if (job != IntPtr.Zero) TerminateJobObject(job, 130); }
    public void Dispose() { if (job != IntPtr.Zero) { CloseHandle(job); job=IntPtr.Zero; } if (Process != null) Process.Dispose(); }
}
'@

function Start-CompressorWorker {
    param([string]$Root, [string[]]$Files, [System.Collections.IDictionary]$Values, [switch]$InstallFFmpeg)
    Test-Preferences $Values
    $requestDir = Join-Path ([IO.Path]::GetTempPath()) ('shrinkwrap-gui-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $requestDir -ErrorAction Stop | Out-Null
    $conf = Join-Path $requestDir 'shrinkwrap.conf'
    Save-Preferences $conf $Values
    $request = Join-Path $requestDir 'request.json'
    @{ Root=$Root; Files=@($Files); ConfigPath=$conf; InstallFFmpeg=[bool]$InstallFFmpeg } | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $request -Encoding UTF8
    # All user paths/options travel as JSON data. The worker script is fixed code.
    $command = @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while (-not [IO.File]::Exists($env:SHRINKWRAP_GATE)) {
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Worker supervision timed out.' }
        Start-Sleep -Milliseconds 50
    }
    $request = Get-Content -LiteralPath $env:SHRINKWRAP_REQUEST -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($request.InstallFFmpeg) {
        & (Join-Path $request.Root 'setup-ffmpeg.ps1') -NonInteractive
    } else {
        & (Join-Path $request.Root 'shrinkwrap.ps1') -ConfigPath $request.ConfigPath -Files @($request.Files) -NonInteractive
    }
    exit $LASTEXITCODE
} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
'@
    $workerPath = Join-Path $requestDir 'worker.ps1'
    [IO.File]::WriteAllText($workerPath, $command, (New-Object Text.UTF8Encoding $false))
    $worker = New-Object CompressorWorker
    try {
        $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $workerPath + '"'
        $worker.Start((Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'), $arguments, $Root, $request, (Join-Path $requestDir 'ready'))
    } catch {
        $worker.Dispose()
        Remove-Item -LiteralPath $requestDir -Recurse -Force
        throw
    }
    return @{ Worker=$worker; RequestDir=$requestDir; Cancelled=$false }
}

function Close-CompressorWorker {
    param([hashtable]$Run)
    $Run.Worker.Dispose()
    $path = [IO.Path]::GetFullPath($Run.RequestDir)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($path.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($path).StartsWith('shrinkwrap-gui-')) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Get-SettingsSchema,Get-PreferencePath,Read-Preferences,Test-Preferences,Save-Preferences,Get-EncoderNames,Get-EncoderOptions,Get-PresetOptions,Get-QualityOptions,Get-ControlPreferences,Start-CompressorWorker,Close-CompressorWorker
