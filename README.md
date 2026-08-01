# NVIDIA Container permanently using one full CPU core — root cause and fix

**TL;DR:** A plugin inside NVIDIA's display driver — `nvprofileupdaterplugin.dll`, the game-profile auto-updater — can busy-spin one full CPU core from the moment Windows boots, *and* deadlock so hard on shutdown that its host process becomes unkillable. Renaming the plugin so the driver can't load it (extension change, **not** a filename prefix — see [the trap](#the-trap-that-cost-us-hours)) fixes it completely. [`Fix-NvContainerSpin.ps1`](Fix-NvContainerSpin.ps1) automates diagnosis, fix, and revert.

Observed and verified on: **RTX 5070 Ti, driver 610.88, Windows 11 (26200)**. Likely affects other configurations — the diagnostic tells you if it's your problem. If it matches (or doesn't) on your setup, please open an issue with your GPU/driver version so others can see the affected range.

## Download

**[⬇ Fix-NvContainerSpin.ps1 (latest release)](https://github.com/motkoning/nvidia-container-spin-fix/releases/latest/download/Fix-NvContainerSpin.ps1)**

After downloading, unblock the file (right-click → Properties → **Unblock**, or `Unblock-File .\Fix-NvContainerSpin.ps1`), then run it — see below. Windows blocks internet-downloaded scripts by default; alternatively run it with `powershell -ExecutionPolicy Bypass -File .\Fix-NvContainerSpin.ps1`.

---

## Symptoms

- Task Manager shows **NVIDIA Container** at a constant, suspiciously *round* CPU percentage that never changes: **12.5% on an 8-thread CPU, 6.25% on 16 threads, 3.1% on 32 threads** — i.e. exactly one core pegged at 100%.
- It starts within seconds of boot and never stops. GPU idle or under load makes no difference.
- The spinning process is `NVDisplay.Container.exe` (service: *NVIDIA Display Container LS*), **not** the NVIDIA App / GeForce Experience.
- None of the standard advice works:
  - **DDU + clean driver install** — spin returns immediately (the reinstall restores the buggy plugin).
  - **Windows reset** — same reason.
  - **Restarting the service** — makes it *worse*: the old container process survives as an unkillable zombie (see below) and can block the service from working at all.
  - **`taskkill /F`** — fails with *"There is no running instance of the task"* while the process keeps burning CPU.
- After trying a service restart, you may find `NVDisplay.Container.exe` processes that can't be killed by anything, an NVIDIA service that won't start, or a broken NVIDIA Control Panel — until you reboot.

## Is this my problem?

Run the read-only diagnostic (no admin needed):

```powershell
.\Fix-NvContainerSpin.ps1
```

It measures the container's per-process CPU, checks the plugin's state on disk, and looks for the bug's smoking-gun signature in NVIDIA's own container logs (`C:\ProgramData\NVIDIA\DisplaySessionContainer*.log`):

```
<NvcSelfCheckTime> Self-check timer event. The thread NNNN in process NNNNN is considered deadlocked. Aborting...
```

That line is NVIDIA's container watchdog catching the profile-updater plugin deadlocking — and even that abort fails, because the stuck thread is wedged in kernel mode.

## Root cause

`NVDisplay.Container.exe` is a generic plugin host. The driver runs two instances: a service-level one and a **session** container that loads, among others:

| Plugin | Purpose |
|---|---|
| `nvprofileupdaterplugin.dll` | **← the culprit.** Auto-downloads per-game profile updates between driver releases |
| `nvxdsyncplugin.dll` | display sync |
| `wksServicePlugin.dll` | workstation features |
| `_NvGSTPlugin.dll` | game-session telemetry |

On affected systems the profile-updater plugin has **two independent bugs**:

1. **A busy-wait loop** that pegs one core from the moment it loads, forever.
2. **A shutdown deadlock**: any attempt to stop the container (service stop, logoff, plugin reconfiguration) hangs while stopping `NvProfileUpdaterPlugin`. The container's own self-check watchdog detects the deadlock and calls abort — which *also* fails, because the thread is stuck inside a kernel call. The process is then half-terminated: unkillable by Task Manager, `taskkill`, or anything else, and it blocks a replacement session container from spawning. Only a reboot clears it.

Bug #2 is why this problem is so sticky: every remedy that involves stopping or restarting anything makes the system strictly worse, and every driver reinstall reinstates the plugin.

## The fix

Rename the plugin so the container never loads it:

```powershell
.\Fix-NvContainerSpin.ps1 -Mode Fix    # self-elevates, asks for confirmation
```

then **reboot** (required — deliberately, the script does *not* restart the NVIDIA service, because on affected machines that's exactly what creates unkillable zombies).

Manual equivalent, if you'd rather not run a script — in an **elevated** PowerShell:

```powershell
$dir = (Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' -Directory -Filter 'nv_dispi.inf_amd64_*' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName + '\Display.NvContainer\plugins\Session'
takeown /f $dir; icacls $dir /grant Administrators:F
takeown /f "$dir\nvprofileupdaterplugin.dll"; icacls "$dir\nvprofileupdaterplugin.dll" /grant Administrators:F
Rename-Item "$dir\nvprofileupdaterplugin.dll" 'nvprofileupdaterplugin.dll.off'
# reboot
```

(The `takeown`/`icacls` on the *folder* matters: DriverStore contents belong to TrustedInstaller, and a rename needs write access to the parent directory, not just the file.)

### What you lose

Automatic per-game profile updates delivered *between* driver releases. That's it. Profiles still ship with every driver, and the Control Panel, game profiles, overlays, G-SYNC etc. all keep working.

### Verifying

After the reboot:

```powershell
(Get-Counter '\Process(nvdisplay.container*)\% Processor Time' -SampleInterval 3 -MaxSamples 3).CounterSamples | % { '{0}: {1:n1}%' -f $_.InstanceName, ($_.CookedValue / [Environment]::ProcessorCount) }
```

All instances should read ~0%. Or just look at Task Manager.

### Reverting

```powershell
.\Fix-NvContainerSpin.ps1 -Mode Revert   # then reboot
```

**Note:** every NVIDIA driver install/update restores the plugin. If the spin comes back after a driver update, run `-Mode Fix` again. (A future driver may fix the underlying bug — it's worth checking Task Manager after each update before reapplying.)

## The trap that cost us hours

If you try to disable the plugin by renaming it to something like `DISABLED_nvprofileupdaterplugin.dll` — **it does not work**. The container's plugin manager loads **every `*.dll` in the folder regardless of filename**, and its directory watcher happily re-registers the "disabled" file under its new name (the logs will show `Unload plugin 'NvXDSyncPlugin' - ...\DISABLED_nvxdsyncplugin.dll`). The extension must change (`.dll.off`), or the file must leave the folder.

Corollary for anyone debugging this class of issue: you also **cannot A/B-test plugins in a live session** on an affected machine. Removing a mandatory plugin makes the container exit — which triggers the shutdown deadlock — which leaves a wedged process that blocks the replacement container. One experiment per reboot is the only reliable protocol.

## Evidence

Scrubbed log excerpts from the diagnosis session are in [`evidence.md`](evidence.md): the deadlock caught by NVIDIA's self-check, the stop sequence that never completes (every plugin stops cleanly except `NvProfileUpdaterPlugin`), and the before/after CPU measurements.

## Disclaimer

This modifies a file inside the Windows DriverStore. It's a two-line rename, it's reversible, and a driver reinstall rebuilds the whole folder from the driver package — but you do it at your own risk. Not affiliated with NVIDIA. If this bug bites you, consider also reporting it on the [GeForce forums](https://www.nvidia.com/en-us/geforce/forums/) so it gets fixed at the source.

*Diagnosed the hard way, written up with the help of Claude. MIT licensed — see [LICENSE](LICENSE).*
