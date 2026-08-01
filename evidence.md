# Evidence from the diagnosis session (2026-08-01)

Machine: RTX 5070 Ti, driver 610.88 (32.0.16.1088), Windows 11 build 26200, 8 logical cores.
Hostnames/usernames scrubbed. Logs are NVIDIA's own container logs from `C:\ProgramData\NVIDIA\`.

## 1. The spin: exactly one core, from boot, in the session container

Fresh boot, ~2 minutes of uptime, per-process CPU (% of total, 8 cores → one pegged core = 12.5%):

```
Instance            CPU%
--------            ----
nvdisplay.container 12.5    <- session container (child)
nvdisplay.container  0.1    <- service container
```

Reproduced identically on every boot: 12.2–12.5% on the child instance, ~0% on the service instance.

## 2. The shutdown deadlock: every plugin stops cleanly except NvProfileUpdaterPlugin

`DisplaySessionContainer1.log` when the container is asked to quit (service stop / parent death).
Note the stop sequence: WksService completes, XDSync completes, GamesessionTelemetry completes —
ProfileUpdater's stop is initiated and **never completes**. The log simply ends here; the process
lives on, burning CPU, unkillable:

```
<NvcHostWin32>     Quit event is sent, post quit message
<NvcHost>          Base host: quit event set
<NvcHost>          Stopping plugins with status 'Any'
<NvcPluginManager> Initiate transition to Stopping state for NvWksServicePlugin
<NvcPluginManager> Transition to Stopped state for NvWksServicePlugin completed
<NvcPluginManager> Initiate transition to Stopping state for NvXDSyncPlugin
<NvcPluginManager> Transition to Stopping state for NvXDSyncPlugin is in progress
<NvcPluginManager> Initiate transition to Stopping state for NvProfileUpdaterPlugin
<NvcPluginManager> Notification: plugin NvXDSyncPlugin is done
<NvcPluginManager> Transition to Stopped state for NvXDSyncPlugin completed
[log ends — NvProfileUpdaterPlugin never reaches Stopped]
```

## 3. NVIDIA's own watchdog confirms the deadlock — and its abort fails too

A later quit attempt, same log. The container's self-check declares the stop thread deadlocked
and aborts the process — yet the process survived this abort (thread wedged in a kernel call)
and remained alive and spinning until reboot:

```
<NvcPluginManager> Initiate transition to Stopping state for NvProfileUpdaterPlugin
<NvcSelfCheckTime> Self-check timer event. The thread 3080 in process 13248 is considered deadlocked. Aborting...
<NvcHost>          Plugins in state transition =>
<NvcHost>              0: NvProfileUpdaterPlugin - Active, Stopping, Mandatory
```

The abort attempt shows up in the Windows Application event log as a fail-fast crash that
nevertheless left the process running:

```
Event 1000: Faulting application name: NVDisplay.Container.exe, version: 1.48.3660.2504
            Exception code: 0xc0000409
```

## 4. The unkillable zombie

```
> taskkill /F /PID 5632
ERROR: The process with PID 5632 could not be terminated.
Reason: There is no running instance of the task.
```

…while `Win32_Process` still listed PID 5632 and performance counters showed it consuming a
full core. In this state it also blocked the NVIDIA service from starting (`Start-Service`
fails) and prevented any replacement session container from spawning. Only a reboot cleared it.

## 5. The filename-prefix trap

Renaming a plugin to `DISABLED_<name>.dll` does **not** disable it — the container loads every
`*.dll` in the folder regardless of filename, as its own log demonstrates (it unloads a plugin
*from the renamed file*):

```
<NvcPluginManager> Unload plugin 'NvXDSyncPlugin' - ...\plugins\Session/DISABLED_nvxdsyncplugin.dll
<NvcHost>          Exit due to dynamic plugin load failure
```

Only an extension change (`.dll.off`) or moving the file out of the folder actually removes it.

## 6. After the fix

`nvprofileupdaterplugin.dll` → `nvprofileupdaterplugin.dll.off`, reboot. Same measurement
window as §1 (fresh boot, ~2 min uptime):

```
Instance            CPU%
--------            ----
nvdisplay.container    0
nvdisplay.container  0.1
nvdisplay.container    0      (repeated samples, all ~0%)
```

Container log shows a normal startup with the remaining three plugins ("Container is started.
State: normal"), NVIDIA Control Panel and App fully functional, and clean shutdowns —
no more zombies, no more spin.
