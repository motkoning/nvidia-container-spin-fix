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

    $stock = Test-Path (Join-Path $dir $PluginName)
    $off = Test-Path (Join-Path $dir "$PluginName.off")

    if ($stock -and $off) { return 'conflict' }
    if ($off)             { return 'fixed' }
    if ($stock)           { return 'active' }
    return 'missing'
}

function Get-MaxContainerCpu {
    # Two CIM snapshots produce one 3-second CPU window per matching process ID.
    # Returns measured/no-process/failed; Maximum remains unrounded for verdicts.
    $cores = [Environment]::ProcessorCount
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $snapshots = @()

    try {
        for ($sampleIndex = 0; $sampleIndex -lt 2; $sampleIndex++) {
            if ($sampleIndex -gt 0) {
                Start-Sleep -Seconds 3
            }

            $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'NVDisplay.Container.exe'" -ErrorAction Stop)
            $snapshotTime = $clock.Elapsed.TotalSeconds
            $processTimes = @{}

            foreach ($process in $processes) {
                $kernelTime = $process.KernelModeTime
                $userTime = $process.UserModeTime
                if ($null -eq $kernelTime -or $null -eq $userTime) {
                    return [pscustomobject]@{
                        Status = 'Failed'
                        Maximum = $null
                    }
                }

                $processTimes[[int]$process.ProcessId] = ([double]$kernelTime + [double]$userTime)
            }

            $snapshots += [pscustomobject]@{
                Time = $snapshotTime
                ProcessTimes = $processTimes
            }
        }
    } catch {
        return [pscustomobject]@{
            Status = 'Failed'
            Maximum = $null
        }
    } finally {
        $clock.Stop()
    }

    $processSeen = $false
    foreach ($snapshot in $snapshots) {
        if ($snapshot.ProcessTimes.Count -gt 0) {
            $processSeen = $true
        }
    }

    if (-not $processSeen) {
        return [pscustomobject]@{
            Status = 'NoProcess'
            Maximum = $null
        }
    }

    $start = $snapshots[0]
    $end = $snapshots[1]
    $elapsedSeconds = $end.Time - $start.Time

    if ($elapsedSeconds -le 0) {
        return [pscustomobject]@{
            Status = 'Failed'
            Maximum = $null
        }
    }

    $values = @()
    foreach ($processId in $start.ProcessTimes.Keys) {
        if ($end.ProcessTimes.ContainsKey($processId)) {
            $cpuTime100ns = $end.ProcessTimes[$processId] - $start.ProcessTimes[$processId]
            if ($cpuTime100ns -ge 0) {
                $cpuSeconds = $cpuTime100ns / 10000000.0
                $values += ($cpuSeconds / $elapsedSeconds / $cores * 100)
            }
        }
    }

    if ($values.Count -eq 0) {
        return [pscustomobject]@{
            Status = 'Failed'
            Maximum = $null
        }
    }

    return [pscustomobject]@{
        Status = 'Measured'
        Maximum = ($values | Measure-Object -Maximum).Maximum
    }
}

# ------------------------------------------------------------- worker mode --
if ($Worker) {
    try {
        $dir = Get-NvSessionPluginDir
        $stock = $null
        $off = $null

        if (-not $dir) {
            $state = 'nodriver'
        } else {
            $stock = Join-Path $dir $PluginName
            $off = "$stock.off"
            $stockExists = Test-Path $stock
            $offExists = Test-Path $off

            if ($stockExists -and $offExists) {
                $state = 'conflict'
            } elseif ($offExists) {
                $state = 'fixed'
            } elseif ($stockExists) {
                $state = 'active'
            } else {
                $state = 'missing'
            }
        }

        if ($state -eq 'nodriver') {
            exit 4
        }
        if ($state -eq 'conflict') {
            exit 6
        }
        if ($state -eq 'missing') {
            exit 5
        }

        if ($Worker -eq 'Fix') {
            if ($state -eq 'fixed') {
                exit 2
            }

            foreach ($p in @($dir, $stock)) {
                takeown.exe /f "$p" | Out-Null
                icacls.exe "$p" /grant '*S-1-5-32-544:F' | Out-Null
            }
            Rename-Item -LiteralPath $stock -NewName "$PluginName.off"
            exit 0
        }

        if ($state -eq 'active') {
            exit 3
        }

        Rename-Item -LiteralPath $off -NewName $PluginName
        exit 0
    } catch {
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

    if ($script:pluginState -eq 'conflict') {
        Set-Verdict 'Could not continue safely - conflicting plugin files were found.' ([System.Drawing.Color]::DarkOrange)
        Add-Log 'A driver reinstall likely left a stale disabled copy next to a fresh active one.'
        Add-Log "The tool won't guess which file to keep, so it will not apply or undo the fix."
        Add-Log 'See the GitHub page below for guidance.'
        return
    }

    Add-Log 'Measuring NVIDIA Container CPU usage (3 seconds)...'
    $measurement = Get-MaxContainerCpu
    $cores = [Environment]::ProcessorCount
    $oneCore = 100.0 / $cores

    if ($measurement.Status -eq 'NoProcess') {
        Add-Log 'NVIDIA Container is not currently running (service stopped?).'
        Set-Verdict 'Could not check - NVIDIA Container is not running.' ([System.Drawing.Color]::DarkOrange)
        return
    }

    if ($measurement.Status -eq 'Failed') {
        Add-Log "NVIDIA Container CPU usage couldn't be measured."
        Set-Verdict "Could not check - NVIDIA Container CPU usage couldn't be measured." ([System.Drawing.Color]::DarkOrange)
        return
    }

    $cpu = $measurement.Maximum
    $spin = ($cpu -ge ($oneCore * 0.7))
    Add-Log ("NVIDIA Container CPU right now: {0:n1}% of total CPU (one stuck core would show as ~{1:n1}%)." -f $cpu, $oneCore)

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
        Add-Log 'Your NVIDIA Container is behaving normally, so there is nothing to fix.'
        Add-Log 'If Task Manager sometimes shows the constant one-core usage anyway,'
        Add-Log 'click "Check again" while it is happening.'
    } else {
        Set-Verdict 'Could not determine the state - see details below.' ([System.Drawing.Color]::DarkOrange)
        Add-Log 'Ask for help by opening an issue on the GitHub page (link below).'
    }
}

function Invoke-Worker([string]$action) {
    try {
        $p = Start-Process powershell.exe -Verb RunAs -PassThru -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Worker', $action)
    } catch {
        Add-Log 'Permission was declined or the helper could not start - nothing was changed.'
        return $null
    }

    try {
        $p.WaitForExit()
        $exitCode = $p.ExitCode
    } catch {
        Add-Log "The tool couldn't confirm what happened - restart your PC, then run this tool again to check."
        return $null
    }

    if ($null -eq $exitCode) {
        Add-Log "The tool couldn't confirm what happened - restart your PC, then run this tool again to check."
        return $null
    }

    switch ($exitCode) {
        0 {
            if ($action -eq 'Fix') {
                Add-Log 'Fix applied.'
            } else {
                Add-Log 'Fix removed (back to original).'
            }
            return 0
        }
        1 {
            Add-Log 'The helper reported an unexpected error. Restart your PC, then run this tool again to check.'
            return 1
        }
        2 {
            Add-Log 'The fix is already applied.'
            return 2
        }
        3 {
            Add-Log 'There is nothing to undo.'
            return 3
        }
        4 {
            Add-Log 'The NVIDIA driver folder was not found - nothing was changed.'
            return 4
        }
        5 {
            Add-Log 'The NVIDIA plugin file was not found - nothing was changed.'
            return 5
        }
        6 {
            Add-Log 'Both the active plugin and a disabled copy are present, probably after a driver reinstall.'
            Add-Log "Nothing was changed because the tool won't guess which file to keep. See the GitHub page for guidance."
            return 6
        }
        default {
            Add-Log "The tool couldn't confirm what happened - restart your PC, then run this tool again to check."
            return $null
        }
    }
}

$actionBtn.Add_Click({
    if ($actionBtn.Text -eq 'Restart PC now') {
        shutdown.exe /r /t 10 /c 'Restarting to finish the NVIDIA Container fix'
        Set-Verdict 'Restarting in 10 seconds... run this tool again afterwards to confirm.' ([System.Drawing.Color]::DarkOrange)
        return
    }

    $actionBtn.Enabled = $false
    $recheckBtn.Enabled = $false
    $consentMessage = @(
        'This fix renames one NVIDIA file so it stops loading.'
        'Nothing is deleted, and the "Undo the fix" button puts the file back.'
        ''
        'The only thing you lose is automatic game-profile updates between driver releases.'
        ''
        'If you continue, Windows will ask for permission next.'
        'Restart your PC afterwards to finish the job.'
        ''
        'Apply the fix?'
    ) -join [Environment]::NewLine

    $consent = [System.Windows.Forms.MessageBox]::Show(
        $form,
        $consentMessage,
        'Before applying the fix',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    if ($consent -ne [System.Windows.Forms.DialogResult]::Yes) {
        Add-Log 'Nothing was changed.'
        $actionBtn.Enabled = $true
        $recheckBtn.Enabled = $true
        return
    }

    Add-Log ''
    Add-Log 'Applying the fix (Windows will ask for permission)...'
    $exitCode = Invoke-Worker 'Fix'
    if ($exitCode -eq 0 -or $exitCode -eq 2) {
        Set-Verdict 'Fix applied. Restart your PC to finish.' ([System.Drawing.Color]::FromArgb(21, 101, 192))
        Add-Log ''
        Add-Log 'IMPORTANT: restart your PC now. The stuck process cannot be'
        Add-Log 'stopped any other way. After the restart, run this tool again'
        Add-Log 'to confirm everything is healthy.'
        $actionBtn.Text = 'Restart PC now'
        $actionBtn.BackColor = [System.Drawing.Color]::FromArgb(21, 101, 192)
    } elseif ($null -eq $exitCode) {
        Set-Verdict 'Could not confirm what happened - see details below.' ([System.Drawing.Color]::DarkOrange)
    } else {
        Set-Verdict 'The fix was not applied - see details below.' ([System.Drawing.Color]::DarkOrange)
    }
    $actionBtn.Enabled = $true
    $recheckBtn.Enabled = $true
})

$undoBtn.Add_Click({
    $undoBtn.Enabled = $false
    $actionBtn.Enabled = $false
    $recheckBtn.Enabled = $false
    Add-Log ''
    Add-Log 'Undoing the fix (Windows will ask for permission)...'
    $exitCode = Invoke-Worker 'Revert'

    if ($exitCode -eq 0) {
        Add-Log 'Restored. Restart your PC to re-enable the plugin.'
        Set-Verdict 'Undo complete - restart your PC to finish.' ([System.Drawing.Color]::FromArgb(21, 101, 192))
        $actionBtn.Text = 'Restart PC now'
        $actionBtn.BackColor = [System.Drawing.Color]::FromArgb(21, 101, 192)
        $actionBtn.ForeColor = [System.Drawing.Color]::White
        $actionBtn.Visible = $true
        $undoBtn.Visible = $false
    } elseif ($exitCode -eq 3) {
        Invoke-Diagnosis
    } elseif ($null -eq $exitCode) {
        Set-Verdict 'Could not confirm what happened - see details below.' ([System.Drawing.Color]::DarkOrange)
    } else {
        Set-Verdict 'The undo was not performed - see details below.' ([System.Drawing.Color]::DarkOrange)
    }

    $undoBtn.Enabled = $true
    $actionBtn.Enabled = $true
    $recheckBtn.Enabled = $true
})

$recheckBtn.Add_Click({ Invoke-Diagnosis })

if ($SelfTest) {
    Write-Host "SelfTest OK: GUI constructed. PluginState=$(Get-PluginState)"
    $form.Dispose()
    return
}

$form.Add_Shown({ Invoke-Diagnosis })
[void]$form.ShowDialog()
