# Worldbound for Windows

Extract the full download, open `Worldbound-Windows`, and run `Worldbound.exe`.
No ChatGPT account, invitation, or login is required. Share the complete ZIP.

Requires Windows 10/11 x64 and internet for the hosted game and Google Street View.
Keep all extracted files together. No Node.js installation is required to play.

- F11: fullscreen
- Ctrl+R: reconnect
- Game > Open in browser: play in your browser

The game is publicly accessible at https://worldbound-explorer.grantexec-0223.chatgpt.site.
Game updates load automatically; the bundled Electron runtime has no auto-updater.
The executable is unsigned.

To rebuild the shareable archive, run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/package-windows.ps1`.
Output: `release/Worldbound-Windows.zip`. Packaging needs the complete Electron
runtime already present beside `Worldbound.exe`.
