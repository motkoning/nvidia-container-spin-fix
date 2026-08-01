# NVIDIA Container permanently using one full CPU core

`NVDisplay.Container.exe` (the "NVIDIA Display Container LS" service) can get stuck burning exactly one CPU core from the moment Windows boots. The cause is a plugin inside the display driver — `nvprofileupdaterplugin.dll`, the game-profile auto-updater — which busy-loops while running and deadlocks the container's shutdown. Renaming that one file so the driver can't load it fixes the problem completely and is easy to undo.

Verified on an RTX 5070 Ti, driver 610.88, Windows 11 (build 26200). Other configurations are likely affected too; the diagnostic below tells you whether it applies to your machine. Either way, an issue with your GPU and driver version helps map the affected range.

## Download

Easiest way, no technical skills needed: [NVIDIA-Container-Fix-EasyTool.zip](https://github.com/motkoning/nvidia-container-spin-fix/releases/latest/download/NVIDIA-Container-Fix-EasyTool.zip). Extract it anywhere and double-click `START-HERE.bat`. A window checks the PC, explains in plain English whether it has this bug, and applies the fix with one button (there is also an undo button). If Windows shows a security warning, choose Run — everything is a plain readable script you can open in Notepad.

Command-line version: [Fix-NvContainerSpin.ps1](https://github.com/motkoning/nvidia-container-spin-fix/releases/latest/download/Fix-NvContainerSpin.ps1). Windows blocks downloaded scripts by default, so either unblock it (right-click → Properties → Unblock) or run it as:

```powershell
powershell -ExecutionPolicy Bypass -File .\Fix-NvContainerSpin.ps1
```

## Symptoms

- Task Manager shows "NVIDIA Container" at a constant, suspiciously round CPU percentage that never changes: 12.5% on an 8-thread CPU, 6.25% on 16 threads, 3.1% on 32 threads. That is one core pinned at 100%.
- It starts within seconds of boot and never stops, whether the GPU is idle or under load.
- The spinning process is `NVDisplay.Container.exe`, not the NVIDIA App or GeForce Experience.
- The usual advice does not work, and some of it actively backfires:
  - DDU and clean driver installs bring the spin right back — every driver install restores the buggy plugin.
  - A full Windows reset doesn't help, for the same reason.
  - Restarting the "NVIDIA Display Container LS" service makes things worse: the old container survives as an unkillable leftover process (see below) and can block the service from working until you reboot.
  - `taskkill /F` on the stuck process fails with "There is no running instance of the task" while the process keeps burning CPU.

## Is this my problem?

Run the read-only diagnostic (no admin rights needed):

```powershell
.\Fix-NvContainerSpin.ps1
```

It measures the container's per-process CPU, checks the plugin's state on disk, and looks for the bug's signature in NVIDIA's own container logs (`C:\ProgramData\NVIDIA\DisplaySessionContainer*.log`):

```
<NvcSelfCheckTime> Self-check timer event. The thread NNNN in process NNNNN is considered deadlocked. Aborting...
```

That line is the container's watchdog catching the profile-updater plugin deadlocking. The abort it announces also fails, because the stuck thread is wedged in a kernel call.

An in-place driver reinstall can leave both the stock `.dll` and the `.off` file present. The tool reports this conflict and declines to guess which file to keep.

## Root cause

`NVDisplay.Container.exe` is a generic plugin host. The driver runs a service-level instance and a session instance; the session instance loads these plugins:

| Plugin | Purpose |
|---|---|
| `nvprofileupdaterplugin.dll` | game-profile auto-updates between driver releases — the culprit |
| `nvxdsyncplugin.dll` | display sync |
| `wksServicePlugin.dll` | workstation features |
| `_NvGSTPlugin.dll` | game-session telemetry |

The profile updater has two separate defects on affected systems. First, a busy-wait loop that pins one core from the moment it loads. Second, a shutdown deadlock: any attempt to stop the container (service stop, logoff, plugin reconfiguration) hangs while stopping `NvProfileUpdaterPlugin`. The container's self-check watchdog detects this and calls abort, the abort fails (the thread is stuck in kernel mode), and the process is left half-terminated: no tool can kill it, and it blocks a replacement session container from spawning. Only a reboot clears it.

The second defect is what makes this problem so persistent. Every remedy that involves stopping or restarting anything leaves the system in a worse state, and every driver reinstall restores the plugin.

## The fix

Rename the plugin so the container never loads it, then reboot:

```powershell
.\Fix-NvContainerSpin.ps1 -Mode Fix
```

The script self-elevates, asks for confirmation, and deliberately does not restart the NVIDIA service — on affected machines that is exactly what creates the unkillable leftover processes. The reboot applies the change.

Manual equivalent, in an elevated PowerShell:

```powershell
$dir = (Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' -Directory -Filter 'nv_dispi.inf_amd64_*' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName + '\Display.NvContainer\plugins\Session'
takeown /f $dir; icacls $dir /grant '*S-1-5-32-544:F'
takeown /f "$dir\nvprofileupdaterplugin.dll"; icacls "$dir\nvprofileupdaterplugin.dll" /grant '*S-1-5-32-544:F'
Rename-Item "$dir\nvprofileupdaterplugin.dll" 'nvprofileupdaterplugin.dll.off'
# reboot
```

The SID form works on every Windows language; localized group names such as `Administratoren` can break the old group-name form.

The `takeown`/`icacls` on the folder matters: DriverStore contents belong to TrustedInstaller, and a rename needs write access to the parent directory, not just the file.

What you lose: automatic per-game profile updates delivered between driver releases. Profiles still ship with every driver, and the control panel, game profiles, overlays and G-SYNC keep working.

To verify, after the reboot:

```powershell
$cores = [Environment]::ProcessorCount
$clock = [Diagnostics.Stopwatch]::StartNew()
$before = @{}
$badTimes = $false
$first = @(Get-CimInstance Win32_Process -Filter "Name = 'NVDisplay.Container.exe'")
$t0 = $clock.Elapsed.TotalSeconds
foreach ($process in $first) {
    if ($null -eq $process.KernelModeTime -or $null -eq $process.UserModeTime) {
        $badTimes = $true
    } else {
        $before[[int]$process.ProcessId] = ([double]$process.KernelModeTime + [double]$process.UserModeTime)
    }
}
Start-Sleep -Seconds 3
$after = @{}
$second = @(Get-CimInstance Win32_Process -Filter "Name = 'NVDisplay.Container.exe'")
$t1 = $clock.Elapsed.TotalSeconds
foreach ($process in $second) {
    if ($null -eq $process.KernelModeTime -or $null -eq $process.UserModeTime) {
        $badTimes = $true
    } else {
        $after[[int]$process.ProcessId] = ([double]$process.KernelModeTime + [double]$process.UserModeTime)
    }
}
if ($first.Count -eq 0) {
    Write-Host 'NVIDIA Container is not running - nothing to measure.'
} elseif ($badTimes) {
    Write-Host 'Could not read CPU times for NVIDIA Container.'
} else {
    foreach ($id in $before.Keys) {
        if ($after.ContainsKey($id)) {
            $cpuSeconds = ($after[$id] - $before[$id]) / 10000000.0
            '{0} (PID {1}): {2:n1}%' -f 'NVDisplay.Container', $id, ($cpuSeconds / ($t1 - $t0) / $cores * 100)
        }
    }
}
```

All instances should read about 0%.

To revert:

```powershell
.\Fix-NvContainerSpin.ps1 -Mode Revert
```

then reboot. Note that every NVIDIA driver install or update restores the plugin. If the spin comes back after a driver update, apply the fix again — and check first whether the new driver fixed the underlying bug, in which case you can leave it stock.

## Notes for anyone debugging this themselves

Renaming the plugin to something like `DISABLED_nvprofileupdaterplugin.dll` does not disable it. The container loads every `*.dll` in the folder regardless of filename, and its directory watcher re-registers the "disabled" file under its new name — the logs will show entries like `Unload plugin 'NvXDSyncPlugin' - ...\DISABLED_nvxdsyncplugin.dll`. The extension has to change, or the file has to leave the folder.

You also cannot A/B-test plugins in a live session on an affected machine. Removing a mandatory plugin makes the container exit, the exit deadlocks, and the wedged process blocks its replacement. One experiment per reboot is the only reliable protocol.

## Evidence

Log excerpts from the diagnosis are in [evidence.md](evidence.md): the deadlock caught by NVIDIA's self-check, the stop sequence in which every plugin stops cleanly except the profile updater, the unkillable process, and before/after CPU measurements.

## Disclaimer

This modifies a file inside the Windows DriverStore. It is a rename, it is reversible, and a driver reinstall rebuilds the folder from the driver package, but you do it at your own risk. Not affiliated with NVIDIA. If this bug bites you, consider also reporting it on the [GeForce forums](https://www.nvidia.com/en-us/geforce/forums/) so it gets fixed at the source.

MIT licensed — see [LICENSE](LICENSE).
