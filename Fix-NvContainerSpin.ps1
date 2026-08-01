<#
.SYNOPSIS
    Diagnoses and fixes the "NVIDIA Container uses one full CPU core forever" bug
    caused by the NvProfileUpdater plugin inside NVIDIA's display driver.

.DESCRIPTION
    On affected systems, NVDisplay.Container.exe (service: "NVIDIA Display
    Container LS") busy-spins one full CPU core from the moment Windows boots
    (e.g. a steady 12.5% total CPU on an 8-thread machine, 6.25% on a 16-thread
    machine). The same buggy plugin also deadlocks the container's shutdown,
    which is why service restarts appear to make things worse (unkillable
    leftover processes) and why DDU / driver reinstalls / even a Windows reset
    do not help - every driver install puts the same plugin back.

    Modes:
      -Mode Diagnose   (default) Read-only. Measures per-process CPU, inspects
                       plugin files and container logs, and tells you whether
                       this fix applies to your machine.
      -Mode Fix        Renames nvprofileupdaterplugin.dll to .dll.off in the
                       driver store so the container never loads it again.
                       REBOOT REQUIRED afterward (the running container cannot
                       be safely restarted - see README).
      -Mode Revert     Renames the file back to stock. Reboot to re-enable.

    What you lose while the plugin is disabled: automatic per-game profile
    updates delivered between driver releases. Profiles still ship with every
    driver update. Control panel, game profiles, overlays etc. keep working.

    NOTE: Installing/updating an NVIDIA driver restores the plugin. If the spin
    returns after a driver update, run -Mode Fix again.

.NOTES
    Observed on: RTX 5070 Ti, driver 610.88, Windows 11. May apply to other
    configurations - run Diagnose first.
    Use at your own risk. Not affiliated with NVIDIA. MIT licensed.
#>
[CmdletBinding()]
param(
    [ValidateSet('Diagnose', 'Fix', 'Revert')]
    [string]$Mode = 'Diagnose'
)

$ErrorActionPreference = 'Stop'
$PluginName = 'nvprofileupdaterplugin.dll'

function Get-NvSessionPluginDir {
    $repo = Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' -Directory -Filter 'nv_dispi.inf_amd64_*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $repo) { return $null }
    $dir = Join-Path $repo.FullName 'Display.NvContainer\plugins\Session'
    if (Test-Path $dir) { return $dir }
    return $null
}

function Measure-ContainerCpu {
    # Returns the max per-instance CPU (as % of total CPU) over two 3s samples.
    $cores = [Environment]::ProcessorCount
    try {
        $samples = (Get-Counter '\Process(nvdisplay.container*)\% Processor Time' -SampleInterval 3 -MaxSamples 2 -ErrorAction Stop).CounterSamples |
            Where-Object { $_.InstanceName -ne '_total' }
    } catch { return $null }
    if (-not $samples) { return $null }
    $vals = $samples | ForEach-Object { [math]::Round($_.CookedValue / $cores, 1) }
    Write-Host ("  NVDisplay.Container CPU samples (% of total CPU): " + ($vals -join '%, ') + '%')
    return ($vals | Measure-Object -Maximum).Maximum
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------- Diagnose --
if ($Mode -eq 'Diagnose') {
    Write-Host "== NVIDIA container spin diagnosis ==" -ForegroundColor Cyan
    $cores = [Environment]::ProcessorCount
    $oneCore = [math]::Round(100 / $cores, 1)
    Write-Host "  Logical processors: $cores (one pegged core shows as ~$oneCore% total CPU)"

    $dir = Get-NvSessionPluginDir
    if (-not $dir) {
        Write-Host "  NVIDIA display driver not found in DriverStore - this fix does not apply." -ForegroundColor Yellow
        return
    }
    Write-Host "  Plugin folder: $dir"

    $stock = Test-Path (Join-Path $dir $PluginName)
    $off   = Test-Path (Join-Path $dir "$PluginName.off")
    if ($off)       { Write-Host "  Plugin state: DISABLED (.off) - fix is already applied." -ForegroundColor Green }
    elseif ($stock) { Write-Host "  Plugin state: active (stock)" }
    else            { Write-Host "  Plugin state: not present at all (unusual driver layout)" -ForegroundColor Yellow }

    $max = Measure-ContainerCpu
    if ($null -eq $max) {
        Write-Host "  No NVDisplay.Container process running (service stopped or disabled?)." -ForegroundColor Yellow
    } elseif ($max -ge ($oneCore * 0.7)) {
        Write-Host "  SPIN DETECTED: an NVDisplay.Container process is burning ~one full core." -ForegroundColor Red
    } else {
        Write-Host "  No spin detected right now." -ForegroundColor Green
    }

    # The deadlock signature this bug leaves in the container logs:
    $sig = Select-String -Path "$env:ProgramData\NVIDIA\DisplaySessionContainer*.log*" -Pattern 'considered deadlocked' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($sig) {
        Write-Host "  Deadlock signature found in container logs (NvcSelfCheckTime abort) - strong match for this bug." -ForegroundColor Red
    }

    Write-Host ""
    if (($max -ge ($oneCore * 0.7)) -and $stock) {
        Write-Host "Verdict: this machine matches the bug. Run:  .\Fix-NvContainerSpin.ps1 -Mode Fix" -ForegroundColor Yellow
    } elseif ($off -and $null -ne $max -and $max -lt 3) {
        Write-Host "Verdict: fix applied and working." -ForegroundColor Green
    } else {
        Write-Host "Verdict: inconclusive - see README ('Is this my problem?') before applying the fix."
    }
    return
}

# ------------------------------------------------------------- Fix / Revert --
if (-not (Test-IsAdmin)) {
    Write-Host "Elevation required - relaunching as administrator (accept the UAC prompt)..."
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Mode', $Mode)
    return
}

$dir = Get-NvSessionPluginDir
if (-not $dir) { throw 'NVIDIA display driver not found in DriverStore.' }
$stockPath = Join-Path $dir $PluginName
$offPath   = "$stockPath.off"

if ($Mode -eq 'Fix') {
    if (Test-Path $offPath) { Write-Host 'Already fixed (plugin is .off). Nothing to do.' -ForegroundColor Green; return }
    if (-not (Test-Path $stockPath)) { throw "$PluginName not found in $dir - unexpected driver layout, aborting." }

    Write-Host "This will disable $PluginName (rename to .off) in:`n  $dir" -ForegroundColor Yellow
    Write-Host 'It does NOT stop any service or process. A REBOOT applies the change.'
    $answer = Read-Host 'Continue? [y/N]'
    if ($answer -notmatch '^[Yy]') { Write-Host 'Aborted.'; return }

    # DriverStore files belong to TrustedInstaller; take ownership of the
    # parent folder AND the file (a rename needs write access to both).
    foreach ($p in @($dir, $stockPath)) {
        takeown.exe /f "$p" | Out-Null
        icacls.exe "$p" /grant 'Administrators:F' | Out-Null
    }
    Rename-Item -LiteralPath $stockPath -NewName "$PluginName.off"
    Write-Host "Done: $PluginName -> $PluginName.off" -ForegroundColor Green
    Write-Host ''
    Write-Host 'REBOOT NOW to apply. Do not try to restart the NVIDIA service instead -' -ForegroundColor Yellow
    Write-Host 'on affected machines the running container deadlocks when stopped and' -ForegroundColor Yellow
    Write-Host 'becomes an unkillable leftover process until you reboot anyway.' -ForegroundColor Yellow
    return
}

if ($Mode -eq 'Revert') {
    if (-not (Test-Path $offPath)) { Write-Host 'Nothing to revert (no .off file found).' -ForegroundColor Green; return }
    Rename-Item -LiteralPath $offPath -NewName $PluginName
    Write-Host "Restored: $PluginName.off -> $PluginName  (reboot to re-enable the plugin)" -ForegroundColor Green
    return
}
