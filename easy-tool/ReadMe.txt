NVIDIA Container CPU Fix - easy tool
=====================================

Is "NVIDIA Container" always using part of your CPU (for example a
constant 12.5% or 6.25% that never goes away)? This tool checks if
your PC has the known NVIDIA driver bug that causes it, and fixes it.

HOW TO USE
----------
1. Double-click  START-HERE.bat
2. If Windows shows a security warning, click "Run" (or "More info"
   then "Run anyway"). The tool is a plain, readable script - you
   or anyone technical can open it in Notepad to see what it does.
3. Follow the buttons. If the tool finds the problem, click
   "Apply the fix" and click "Yes" when Windows asks for permission.
4. RESTART your PC when the tool tells you to. That's it.

The fix renames one NVIDIA plugin file so it no longer loads
(nothing is deleted - the "Undo the fix" button puts it back).
The only thing you lose: automatic game-profile updates delivered
between driver releases. Games, NVIDIA Control Panel, overlays and
everything else keep working normally.

NOTE: NVIDIA driver updates undo the fix. If the problem comes back
after a driver update, simply run this tool again.

Full technical explanation, evidence and source:
https://github.com/motkoning/nvidia-container-spin-fix
