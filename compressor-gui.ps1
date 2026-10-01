<#
.SYNOPSIS
    Native Windows GUI for Discord Video Compressor - Hardware Encoding.
#>
[CmdletBinding()]
param([switch]$TestMode)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module (Join-Path $PSScriptRoot 'gui-support.psm1') -Force
[Windows.Forms.Application]::EnableVisualStyles()

$script:Run = $null
$script:Fields = @{}
$script:PreferencePath = Get-PreferencePath $PSScriptRoot
$settings = Read-Preferences $script:PreferencePath
$schema = @(Get-SettingsSchema)
$form = New-Object Windows.Forms.Form
$form.Text = 'Discord Video Compressor | Hardware Encoding'
$form.Size = New-Object Drawing.Size(980, 860)
$form.MinimumSize = New-Object Drawing.Size(820, 740)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
$form.AutoScaleMode = 'Dpi'
$form.BackColor = [Drawing.Color]::FromArgb(245,247,251)
$tip = New-Object Windows.Forms.ToolTip
$tip.AutoPopDelay = 15000

$layout = New-Object Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.Padding = New-Object Windows.Forms.Padding(20)
$layout.ColumnCount = 1
$layout.RowCount = 7
foreach ($height in @(62,150,40,310,44,0,35)) {
    $style = New-Object Windows.Forms.RowStyle
    if ($height -eq 0) { $style.SizeType='Percent'; $style.Height=100 } else { $style.SizeType='Absolute'; $style.Height=$height }
    $layout.RowStyles.Add($style) | Out-Null
}
$form.Controls.Add($layout)
$header = New-Object Windows.Forms.Label
$header.Text = "Discord Video Compressor`nGPU first. Fit your clips to the upload limit."
$header.Font = New-Object Drawing.Font('Segoe UI', 14, [Drawing.FontStyle]::Bold)
$header.Dock = 'Fill'
$layout.Controls.Add($header,0,0)

$files = New-Object Windows.Forms.ListBox
$files.Dock='Fill'; $files.HorizontalScrollbar=$true
$files.SelectionMode='MultiExtended'; $files.AllowDrop=$true
$layout.Controls.Add($files,0,1)
function Add-InputPaths {
    param([string[]]$Paths)
    foreach ($path in $Paths) {
        if (Test-Path -LiteralPath $path -PathType Container) {
            Add-InputPaths @(Get-ChildItem -LiteralPath $path -File -Recurse |
                Where-Object { $_.Extension.ToLowerInvariant() -in '.mp4','.mkv','.mov','.avi','.webm','.m4v','.flv' -and $_.Name -notmatch '_optimized\.mp4$' } |
                Select-Object -ExpandProperty FullName)
        } elseif ((Test-Path -LiteralPath $path -PathType Leaf) -and [IO.Path]::GetExtension($path).ToLowerInvariant() -in '.mp4','.mkv','.mov','.avi','.webm','.m4v','.flv') {
            $full = [IO.Path]::GetFullPath($path)
            if (-not $files.Items.Contains($full)) { $files.Items.Add($full) | Out-Null }
        }
    }
}
$files.Add_DragEnter({ if (-not $script:Run -and $_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect='Copy' } })
$files.Add_DragDrop({ if (-not $script:Run) { Add-InputPaths @($_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)) } })
$fileButtons = New-Object Windows.Forms.FlowLayoutPanel
$fileButtons.Dock='Fill'
$layout.Controls.Add($fileButtons,0,2)
function New-Button {
    param([string]$Text, [Windows.Forms.Control]$Parent)
    $button = New-Object Windows.Forms.Button
    $button.Text=$Text; $button.AutoSize=$true; $button.Height=32
    $Parent.Controls.Add($button)
    return $button
}
$add = New-Button 'Add videos...' $fileButtons
$folder = New-Button 'Add folder...' $fileButtons
$remove = New-Button 'Remove selected' $fileButtons
$clear = New-Button 'Clear' $fileButtons
$add.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Multiselect=$true; $dialog.Filter='Videos|*.mp4;*.mkv;*.mov;*.avi;*.webm;*.m4v;*.flv'
    if ($dialog.ShowDialog() -eq 'OK') { Add-InputPaths $dialog.FileNames }
    $dialog.Dispose()
})
$folder.Add_Click({
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq 'OK') { Add-InputPaths @($dialog.SelectedPath) }
    $dialog.Dispose()
})
$remove.Add_Click({ foreach ($item in @($files.SelectedItems)) { $files.Items.Remove($item) } })
$clear.Add_Click({ $files.Items.Clear() })

$tabs = New-Object Windows.Forms.TabControl
$tabs.Dock='Fill'; $layout.Controls.Add($tabs,0,3)
function New-SettingsPage {
    param([string]$Title)
    $page = New-Object Windows.Forms.TabPage
    $page.Text=$Title; $page.Padding=New-Object Windows.Forms.Padding(12); $page.AutoScroll=$true
    $table = New-Object Windows.Forms.TableLayoutPanel
    $table.AutoSize=$true; $table.Dock='Top'; $table.ColumnCount=2
    $table.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute',270))) | Out-Null
    $table.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100))) | Out-Null
    $page.Controls.Add($table); $tabs.TabPages.Add($page)
    return $table
}
$basic = New-SettingsPage 'Compression'
$advanced = New-SettingsPage 'Advanced'
$rows = @{Compression=0;Advanced=0}
foreach ($item in $schema) {
    $isBasic = $item.Key -in 'mode','target_size_mb','preset','output_dir','normalize_audio','mono','no_audio'
    $table = if ($isBasic) { $basic } else { $advanced }
    $pageName = if ($isBasic) { 'Compression' } else { 'Advanced' }
    $row = $rows[$pageName]; $rows[$pageName]++
    $table.RowCount=$row+1
    $table.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute',36))) | Out-Null
    $label = New-Object Windows.Forms.Label
    $label.Text=$item.Label; $label.AutoSize=$true; $label.Anchor='Left'
    $table.Controls.Add($label,0,$row)
    if ($item.Kind -eq 'bool') {
        $field = New-Object Windows.Forms.CheckBox
        $field.Checked=$settings[$item.Key] -eq 'true'; $field.Anchor='Left'
    } elseif ($item.Kind -in 'encoder','preset') {
        $field = New-Object Windows.Forms.ComboBox
        $field.DropDownStyle='DropDownList'; $field.Dock='Fill'
        $choices = if ($item.Kind -eq 'encoder') { @(Get-EncoderNames) } else { @('slow','medium','fast','ultrafast','superfast','veryfast','faster','slower','veryslow','placebo','quality','balanced','speed','p1','p2','p3','p4','p5','p6','p7') }
        $field.Items.AddRange([object[]]$choices)
        $field.SelectedItem=$settings[$item.Key]
        if ($field.SelectedIndex -lt 0) { $field.SelectedIndex=0 }
    } else {
        $field = New-Object Windows.Forms.TextBox
        $field.Text=$settings[$item.Key]; $field.Dock='Fill'
    }
    $script:Fields[$item.Key]=$field
    $tip.SetToolTip($label,$item.Tip); $tip.SetToolTip($field,$item.Tip)
    $table.Controls.Add($field,1,$row)
}
$tip.SetToolTip($files,'Drop videos or a folder here. Folder selection includes subfolders.')
$actions = New-Object Windows.Forms.FlowLayoutPanel
$actions.Dock='Fill'; $layout.Controls.Add($actions,0,4)
$start = New-Button 'Compress videos' $actions
$start.BackColor=[Drawing.Color]::FromArgb(80,98,230); $start.ForeColor=[Drawing.Color]::White
$cancel = New-Button 'Cancel' $actions; $cancel.Enabled=$false
$save = New-Button 'Save defaults' $actions
$browse = New-Button 'Choose output...' $actions
$open = New-Button 'Open output' $actions
$install = New-Button 'Install FFmpeg' $actions
$tip.SetToolTip($install,'Downloads a pinned FFmpeg release, verifies SHA-256, and installs it beside the scripts.')
$log = New-Object Windows.Forms.TextBox
$log.Dock='Fill'; $log.Multiline=$true; $log.ReadOnly=$true; $log.ScrollBars='Both'
$log.WordWrap=$false; $log.Font=New-Object Drawing.Font('Consolas',9)
$log.Text="Add videos above, or drag them into the list.`r`nAuto selects the first working GPU encoder; software is the fallback.`r`nChoose H.264 for broad playback support. Hover over settings for help.`r`n"
$layout.Controls.Add($log,0,5)
$statusRow = New-Object Windows.Forms.FlowLayoutPanel
$statusRow.Dock='Fill'; $layout.Controls.Add($statusRow,0,6)
$progress = New-Object Windows.Forms.ProgressBar
$progress.Width=180; $progress.Height=20; $progress.MarqueeAnimationSpeed=0
$statusRow.Controls.Add($progress)
$status = New-Object Windows.Forms.Label
$status.AutoSize=$true; $status.Text='Ready'; $statusRow.Controls.Add($status)
$timer = New-Object Windows.Forms.Timer
$timer.Interval=150
function Get-FormSettings {
    $values = [ordered]@{}
    foreach ($item in $schema) {
        $field=$script:Fields[$item.Key]
        $values[$item.Key] = if ($item.Kind -eq 'bool') { $field.Checked.ToString().ToLowerInvariant() } else { $field.Text.Trim() }
    }
    Test-Preferences $values
    return $values
}
function Set-RunningState {
    param([bool]$Running)
    $tabs.Enabled=-not $Running; $fileButtons.Enabled=-not $Running; $files.Enabled=-not $Running
    $start.Enabled=-not $Running; $save.Enabled=-not $Running; $browse.Enabled=-not $Running
    $cancel.Enabled=$Running
    $install.Enabled=-not $Running
    $progress.Style=if ($Running) { 'Marquee' } else { 'Blocks' }
    $progress.MarqueeAnimationSpeed=if ($Running) { 25 } else { 0 }
}
function Show-Error {
    param([string]$Message)
    [Windows.Forms.MessageBox]::Show($form,$Message,'Compressor','OK','Error') | Out-Null
}
$save.Add_Click({
    try {
        $values=Get-FormSettings
        $local=Join-Path $PSScriptRoot 'shrinkwrap.conf'
        try { Save-Preferences $local $values; $script:PreferencePath=$local }
        catch {
            $userDir=Join-Path $env:APPDATA 'discord-video-compressor'
            New-Item -ItemType Directory -Path $userDir -Force | Out-Null
            $user=Join-Path $userDir 'shrinkwrap.conf'
            Save-Preferences $user $values; $script:PreferencePath=$user
        }
        $status.Text="Defaults saved: $script:PreferencePath"
    } catch { Show-Error $_.Exception.Message }
})
$browse.Add_Click({
    $dialog=New-Object Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq 'OK') { $script:Fields.output_dir.Text=$dialog.SelectedPath }
    $dialog.Dispose()
})
$open.Add_Click({
    try {
        $path=$script:Fields.output_dir.Text
        if (-not [IO.Path]::IsPathRooted($path)) { $path=Join-Path $PSScriptRoot $path }
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw 'The output folder does not exist yet.' }
        [Diagnostics.Process]::Start('explorer.exe',('"'+[IO.Path]::GetFullPath($path)+'"')) | Out-Null
    } catch { Show-Error $_.Exception.Message }
})
$start.Add_Click({
    try {
        if ($files.Items.Count -eq 0) { throw 'Add at least one video.' }
        $values=Get-FormSettings
        $script:Run=Start-CompressorWorker -Root $PSScriptRoot -Files @($files.Items) -Values $values
        $log.Clear(); $status.Text='Probing GPU encoders...'; Set-RunningState $true; $timer.Start()
    } catch { Show-Error $_.Exception.Message }
})
$install.Add_Click({
    try {
        $script:Run=Start-CompressorWorker -Root $PSScriptRoot -Values (Read-Preferences '') -InstallFFmpeg
        $script:Run.Installing=$true
        $log.Clear(); $status.Text='Installing verified FFmpeg build...'; Set-RunningState $true; $timer.Start()
    } catch { Show-Error $_.Exception.Message }
})
$cancel.Add_Click({
    if ($script:Run) { $script:Run.Cancelled=$true; $script:Run.Worker.Cancel(); $status.Text='Cancelling...'; $cancel.Enabled=$false }
})
$timer.Add_Tick({
    if (-not $script:Run) { return }
    $line=''
    while ($script:Run.Worker.Lines.TryDequeue([ref]$line)) {
        $log.AppendText($line+"`r`n")
        if ($line -match '\[\d+/\d+\]|Processing:|Hardware encoder:|No working hardware') { $status.Text=$line.Trim() }
    }
    # Keep the GUI responsive even for very large batch logs.
    if ($log.TextLength -gt 150000) { $log.Text=$log.Text.Substring($log.TextLength-100000); $log.SelectionStart=$log.TextLength }
    if ($script:Run.Worker.Process.HasExited) {
        $script:Run.Worker.Process.WaitForExit()
        while ($script:Run.Worker.Lines.TryDequeue([ref]$line)) { $log.AppendText($line+"`r`n") }
        $code=$script:Run.Worker.Process.ExitCode
        $status.Text=if ($script:Run.Cancelled) { 'Cancelled. Completed videos are kept; partial files remain in the hidden scratch folder.' } elseif ($code -eq 0 -and $script:Run.Installing) { 'FFmpeg is installed. Add videos and start compression.' } elseif ($code -eq 0) { 'Finished. Open the output folder to see your videos and summary.' } else { 'Failed or partially completed. See the log and summary for details.' }
        Close-CompressorWorker $script:Run; $script:Run=$null; $timer.Stop(); Set-RunningState $false
    }
})
$form.Add_FormClosing({
    if ($script:Run) { $script:Run.Worker.Cancel(); Close-CompressorWorker $script:Run; $script:Run=$null }
    $timer.Stop(); $timer.Dispose(); $tip.Dispose()
})
if ($TestMode) { return $form }
try { [Windows.Forms.Application]::Run($form) } finally { $form.Dispose() }
