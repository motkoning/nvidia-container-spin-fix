<#
    NVIDIA Container CPU Fix - easy GUI tool
    Part of https://github.com/motkoning/nvidia-container-spin-fix
    Fixes: NVDisplay.Container.exe permanently using one full CPU core
    (busy-spin + shutdown deadlock in nvprofileupdaterplugin.dll).
    MIT licensed. Not affiliated with NVIDIA.

    Normal use: double-click START-HERE.bat (runs this GUI).
    Internal:   -Worker Fix|Revert is used by the GUI to perform the file
                change in a hidden elevated helper process.
#>
[CmdletBinding()]
param(
    [ValidateSet('Fix', 'Revert')]
    [string]$Worker,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$PluginName = 'nvprofileupdaterplugin.dll'
$ResultFile = Join-Path $env:TEMP 'NvidiaFixTool-worker-result.txt'

# ------------------------------------------------------------ shared helpers
function Get-NvSessionPluginDir {
    $repo = Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' -Directory -Filter 'nv_dispi.inf_amd64_*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $repo) { return $null }
    $dir = Join-Path $repo.FullName 'Display.NvContainer\plugins\Session'
    if (Test-Path $dir) { return $dir }
    return $null
}

function Get-PluginState {
    $dir = Get-NvSessionPluginDir
    if (-not $dir) { return 'nodriver' }
    if (Test-Path (Join-Path $dir "$PluginName.off")) { return 'fixed' }
    if (Test-Path (Join-Path $dir $PluginName))       { return 'active' }
    return 'missing'
}

function Get-MaxContainerCpu {
    # Max per-instance CPU as % of total CPU over one 3s sample. -1 = no process.
    $cores = [Environment]::ProcessorCount
    try {
        $s = (Get-Counter '\Process(nvdisplay.container*)\% Processor Time' -SampleInterval 3 -MaxSamples 1 -ErrorAction Stop).CounterSamples |
            Where-Object { $_.InstanceName -ne '_total' }
    } catch { return -1 }
    if (-not $s) { return -1 }
    return (($s | ForEach-Object { $_.CookedValue / $cores }) | Measure-Object -Maximum).Maximum
}

# ------------------------------------------------------------- worker mode --
if ($Worker) {
    try {
        $dir = Get-NvSessionPluginDir
        if (-not $dir) { throw 'NVIDIA driver folder not found.' }
        $stock = Join-Path $dir $PluginName
        $off = "$stock.off"
        if ($Worker -eq 'Fix') {
            if (Test-Path $off) { Set-Content $ResultFile 'OK|Already fixed.'; exit 0 }
            if (-not (Test-Path $stock)) { throw "$PluginName not found - unexpected driver layout." }
            foreach ($p in @($dir, $stock)) {
                takeown.exe /f "$p" | Out-Null
                icacls.exe "$p" /grant 'Administrators:F' | Out-Null
            }
            Rename-Item -LiteralPath $stock -NewName "$PluginName.off"
            Set-Content $ResultFile 'OK|Fix applied.'
        } else {
            if (-not (Test-Path $off)) { Set-Content $ResultFile 'OK|Nothing to undo.'; exit 0 }
            Rename-Item -LiteralPath $off -NewName $PluginName
            Set-Content $ResultFile 'OK|Fix removed (back to original).'
        }
        exit 0
    } catch {
        Set-Content $ResultFile ("ERR|" + $_.Exception.Message)
        exit 1
    }
}

# ---------------------------------------------------------------- GUI mode --
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'NVIDIA Container CPU Fix'
$form.Size = New-Object System.Drawing.Size(600, 520)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$header = New-Object System.Windows.Forms.Label
$header.Text = 'NVIDIA Container CPU Fix'
$header.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$header.AutoSize = $true
$header.Location = New-Object System.Drawing.Point(20, 15)
$form.Controls.Add($header)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = 'Fixes the bug where "NVIDIA Container" permanently uses one full CPU core.'
$sub.AutoSize = $true
$sub.Location = New-Object System.Drawing.Point(22, 52)
$form.Controls.Add($sub)

$verdict = New-Object System.Windows.Forms.Label
$verdict.Text = 'Checking your PC...'
$verdict.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$verdict.AutoSize = $false
$verdict.Size = New-Object System.Drawing.Size(545, 55)
$verdict.Location = New-Object System.Drawing.Point(22, 85)
$form.Controls.Add($verdict)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = 'Vertical'
$logBox.Size = New-Object System.Drawing.Size(545, 210)
$logBox.Location = New-Object System.Drawing.Point(22, 150)
$logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($logBox)

$actionBtn = New-Object System.Windows.Forms.Button
$actionBtn.Size = New-Object System.Drawing.Size(240, 45)
$actionBtn.Location = New-Object System.Drawing.Point(22, 375)
$actionBtn.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$actionBtn.Visible = $false
$form.Controls.Add($actionBtn)

$recheckBtn = New-Object System.Windows.Forms.Button
$recheckBtn.Text = 'Check again'
$recheckBtn.Size = New-Object System.Drawing.Size(130, 45)
$recheckBtn.Location = New-Object System.Drawing.Point(275, 375)
$form.Controls.Add($recheckBtn)

$undoBtn = New-Object System.Windows.Forms.Button
$undoBtn.Text = 'Undo the fix'
$undoBtn.Size = New-Object System.Drawing.Size(130, 45)
$undoBtn.Location = New-Object System.Drawing.Point(418, 375)
$undoBtn.Visible = $false
$form.Controls.Add($undoBtn)

$link = New-Object System.Windows.Forms.LinkLabel
$link.Text = 'What does this do? Full explanation on GitHub'
$link.AutoSize = $true
$link.Location = New-Object System.Drawing.Point(22, 440)
$link.Add_LinkClicked({ Start-Process 'https://github.com/motkoning/nvidia-container-spin-fix' })
$form.Controls.Add($link)

function Add-Log([string]$msg) {
    $logBox.AppendText($msg + [Environment]::NewLine)
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Verdict([string]$text, [System.Drawing.Color]$color) {
    $verdict.Text = $text
    $verdict.ForeColor = $color
    [System.Windows.Forms.Application]::DoEvents()
}

$script:pluginState = 'unknown'

function Invoke-Diagnosis {
    $actionBtn.Visible = $false
    $undoBtn.Visible = $false
    $logBox.Clear()
    Set-Verdict 'Checking your PC (about 10 seconds)...' ([System.Drawing.Color]::DimGray)

    $script:pluginState = Get-PluginState
    if ($script:pluginState -eq 'nodriver') {
        Set-Verdict 'No NVIDIA graphics driver found on this PC.' ([System.Drawing.Color]::DarkOrange)
        Add-Log 'This tool only applies to PCs with an NVIDIA graphics card and driver.'
        return
    }
    Add-Log 'NVIDIA driver found.'
    switch ($script:pluginState) {
        'fixed'   { Add-Log 'The fix is already applied on this PC.' }
        'active'  { Add-Log 'The problem plugin (game-profile auto-updater) is currently enabled.' }
        'missing' { Add-Log 'Unusual driver layout: the plugin was not found at all.' }
    }

    Add-Log 'Measuring NVIDIA Container CPU usage (3 seconds)...'
    $cpu = Get-MaxContainerCpu
    $cores = [Environment]::ProcessorCount
    $oneCore = 100.0 / $cores
    $spin = ($cpu -ge ($oneCore * 0.7))
    if ($cpu -lt 0) {
        Add-Log 'NVIDIA Container is not currently running (service stopped?).'
    } else {
        Add-Log ("NVIDIA Container CPU right now: {0:n1}% of total CPU (one stuck core would show as ~{1:n1}%)." -f $cpu, $oneCore)
    }

    if ($spin -and $script:pluginState -eq 'active') {
        Set-Verdict 'Problem found - and this tool can fix it.' ([System.Drawing.Color]::Firebrick)
        Add-Log ''
        Add-Log 'Click "Apply the fix". Windows will ask for permission (click Yes).'
        Add-Log 'Afterwards you must RESTART your PC once to finish.'
        $actionBtn.Text = 'Apply the fix'
        $actionBtn.BackColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
        $actionBtn.ForeColor = [System.Drawing.Color]::White
        $actionBtn.Visible = $true
    } elseif ($spin -and $script:pluginState -eq 'fixed') {
        Set-Verdict 'Fix applied, but a restart is still needed to finish.' ([System.Drawing.Color]::DarkOrange)
        Add-Log ''
        Add-Log 'The stuck process from before can only be cleared by restarting your PC.'
        $actionBtn.Text = 'Restart PC now'
        $actionBtn.BackColor = [System.Drawing.Color]::FromArgb(21, 101, 192)
        $actionBtn.ForeColor = [System.Drawing.Color]::White
        $actionBtn.Visible = $true
        $undoBtn.Visible = $true
    } elseif (-not $spin -and $script:pluginState -eq 'fixed') {
        Set-Verdict 'All good - the fix is applied and your PC is healthy.' ([System.Drawing.Color]::ForestGreen)
        Add-Log ''
        Add-Log 'Note: NVIDIA driver updates undo this fix. If the problem ever'
        Add-Log 'comes back after a driver update, just run this tool again.'
        $undoBtn.Visible = $true
    } elseif (-not $spin -and $script:pluginState -eq 'active') {
        Set-Verdict "No problem detected right now." ([System.Drawing.Color]::ForestGreen)
        Add-Log ''
        Add-Log 'Your NVIDIA Container is behaving normally. Nothing to do!'
        Add-Log 'If Task Manager sometimes shows the constant one-core usage anyway,'
        Add-Log 'click "Check again" while it is happening.'
    } else {
        Set-Verdict 'Could not determine the state - see details below.' ([System.Drawing.Color]::DarkOrange)
        Add-Log 'Ask for help by opening an issue on the GitHub page (link below).'
    }
}

function Invoke-Worker([string]$action) {
    Remove-Item $ResultFile -ErrorAction SilentlyContinue
    try {
        $p = Start-Process powershell.exe -Verb RunAs -PassThru -Wait -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Worker', $action)
    } catch {
        Add-Log 'Permission was declined - nothing was changed.'
        return $false
    }
    if (Test-Path $ResultFile) {
        $parts = (Get-Content $ResultFile -Raw).Trim() -split '\|', 2
        Add-Log $parts[1]
        return ($parts[0] -eq 'OK')
    }
    Add-Log 'The helper did not report a result - nothing may have changed.'
    return $false
}

$actionBtn.Add_Click({
    if ($actionBtn.Text -eq 'Restart PC now') {
        shutdown.exe /r /t 10 /c 'Restarting to finish the NVIDIA Container fix'
        Set-Verdict 'Restarting in 10 seconds... run this tool again afterwards to confirm.' ([System.Drawing.Color]::DarkOrange)
        return
    }
    $actionBtn.Enabled = $false
    Add-Log ''
    Add-Log 'Applying the fix (Windows will ask for permission)...'
    $ok = Invoke-Worker 'Fix'
    $actionBtn.Enabled = $true
    if ($ok) {
        Set-Verdict 'Fix applied! Restart your PC to finish.' ([System.Drawing.Color]::FromArgb(21, 101, 192))
        Add-Log ''
        Add-Log 'IMPORTANT: restart your PC now. The stuck process cannot be'
        Add-Log 'stopped any other way. After the restart, run this tool again'
        Add-Log 'to confirm everything is healthy.'
        $actionBtn.Text = 'Restart PC now'
        $actionBtn.BackColor = [System.Drawing.Color]::FromArgb(21, 101, 192)
    }
})

$undoBtn.Add_Click({
    Add-Log ''
    Add-Log 'Undoing the fix (Windows will ask for permission)...'
    if (Invoke-Worker 'Revert') {
        Add-Log 'Restored. Restart your PC to re-enable the plugin.'
        Invoke-Diagnosis
    }
})

$recheckBtn.Add_Click({ Invoke-Diagnosis })

if ($SelfTest) {
    Write-Host "SelfTest OK: GUI constructed. PluginState=$(Get-PluginState)"
    $form.Dispose()
    return
}

$form.Add_Shown({ Invoke-Diagnosis })
[void]$form.ShowDialog()
