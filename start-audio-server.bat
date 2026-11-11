@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "PORT=8787"
set "PY="
where py >nul 2>&1
if not errorlevel 1 set "PY=py"
if not defined PY (
  where python >nul 2>&1
  if not errorlevel 1 set "PY=python"
)
if not defined PY (
  echo Python is not installed. Install it from https://www.python.org/downloads/ ^(tick "Add Python to PATH"^) then run this file again.
  pause
  exit /b 1
)
echo Installing / updating yt-dlp ...
%PY% -m pip install -U yt-dlp
if errorlevel 1 (
  echo Could not install yt-dlp. Check your internet connection.
  pause
  exit /b 1
)
where cloudflared >nul 2>&1
if errorlevel 1 (
  echo.
  echo [optional] To listen from your phone through this PC, install cloudflared:  winget install Cloudflare.cloudflared
) else (
  echo Starting a public HTTPS tunnel in a new window - copy the https://....trycloudflare.com address from it into the app settings.
  start "Masari tunnel" cmd /k cloudflared tunnel --url http://localhost:%PORT%
)
echo.
echo Starting the audio server. Keep this window open while you listen.
%PY% server.py %PORT%
pause
