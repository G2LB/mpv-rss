@echo off
rem ---------------------------------------------------------------------------
rem  install-deps.bat -- install what rss.lua needs on Windows, using winget.
rem
rem    mpv       the player the script runs inside          (required)
rem    yt-dlp    YouTube playback                           (required for YouTube)
rem    ffmpeg    thumbnails and podcast artwork             (optional)
rem    a Nerd Font  the icon set, else ASCII icons          (optional)
rem
rem  curl is NOT installed: Windows 10 1803+ ships it, and the script falls back
rem  to PowerShell where it is absent.
rem
rem  Only what is missing gets installed, so running this twice is harmless.
rem
rem    install-deps.bat          everything above
rem    install-deps.bat /core    mpv and yt-dlp only
rem    install-deps.bat /q       no "press any key" at the end
rem
rem  Homebrew and pacman equivalents are in DEPENDENCIES.md.
rem ---------------------------------------------------------------------------
setlocal EnableDelayedExpansion

set "CORE="
set "QUIET="
for %%a in (%*) do (
  if /i "%%~a"=="/core" set "CORE=1"
  if /i "%%~a"=="/q"    set "QUIET=1"
)

set "DONE="
set "SKIPPED="
set "FAILED="

where /q winget
if %ERRORLEVEL% NEQ 0 (
  echo winget was not found.
  echo.
  echo It comes with "App Installer" from the Microsoft Store:
  echo   https://apps.microsoft.com/detail/9nblggh4nns1
  echo.
  echo Or install the four packages by hand -- see DEPENDENCIES.md.
  if not defined QUIET pause
  exit /b 1
)

echo Installing dependencies for rss.lua with winget.
echo.

call :need mpv    mpv-player.mpv-CI.MSVC "mpv"
call :need yt-dlp yt-dlp.yt-dlp          "yt-dlp"

if defined CORE (
  echo [skip] ffmpeg and the Nerd Font ^(/core^)
  set "SKIPPED=!SKIPPED! ffmpeg font"
) else (
  call :need ffmpeg Gyan.FFmpeg "ffmpeg"
  call :font
)

rem curl: report only. It is part of Windows and the script copes without it.
where /q curl
if %ERRORLEVEL% EQU 0 (
  echo [ ok ] curl is present
) else (
  echo [note] curl is missing, which is unusual on Windows 10 1803+.
  echo        The script will use PowerShell instead -- nothing to do.
)

echo.
echo ---------------------------------------------------------------------------
if defined DONE    echo   installed:          !DONE!
if defined SKIPPED echo   already there/skipped: !SKIPPED!
if defined FAILED  echo   FAILED:             !FAILED!
echo ---------------------------------------------------------------------------
echo.
if defined DONE (
  echo A program installed just now is on the PATH of NEW shells only.
  echo Close this window and open a fresh one before running mpv.
  echo.
)
if defined FAILED (
  echo Re-run after dealing with the failures above, or install those by hand:
  echo   DEPENDENCIES.md
  echo.
)
echo Next: copy the script into mpv's config folder --
echo   New-Item -ItemType Directory -Force "$env:APPDATA\mpv\scripts" ^| Out-Null
echo   Copy-Item .\rss.lua "$env:APPDATA\mpv\scripts\rss.lua"
echo Then start mpv-rss.cmd and press Ctrl+R.  ^(README.md section 2^)

if not defined QUIET pause
exit /b 0

rem --------------------------------------------------------------------------
rem  :need <command on PATH> <winget id> <label>
rem  Installs the package unless the command is already callable.
rem --------------------------------------------------------------------------
:need
where /q %~1
if %ERRORLEVEL% EQU 0 (
  echo [ ok ] %~3 is already installed
  set "SKIPPED=!SKIPPED! %~3"
  goto :eof
)
echo [....] installing %~3 ^(%~2^)
winget install --exact --id %~2 --accept-package-agreements --accept-source-agreements --disable-interactivity
if !ERRORLEVEL! NEQ 0 (
  echo [FAIL] %~3 -- winget exited with !ERRORLEVEL!
  set "FAILED=!FAILED! %~3"
) else (
  echo [ ok ] %~3 installed
  set "DONE=!DONE! %~3"
)
goto :eof

rem --------------------------------------------------------------------------
rem  :font -- any Nerd Font will do, so look for one before installing ours.
rem  Patched font files are named "...NerdFont-Regular.ttf" or "...NF-...".
rem --------------------------------------------------------------------------
rem  The patterns are written out one per line rather than looped over: a
rem  wildcard in a FOR set is expanded against the current directory, so the
rem  loop body would never run at all.
:font
if exist "%WINDIR%\Fonts\*NerdFont*"                         goto :font_present
if exist "%WINDIR%\Fonts\*Nerd Font*"                        goto :font_present
if exist "%WINDIR%\Fonts\*NF-*"                              goto :font_present
if exist "%LOCALAPPDATA%\Microsoft\Windows\Fonts\*NerdFont*"  goto :font_present
if exist "%LOCALAPPDATA%\Microsoft\Windows\Fonts\*Nerd Font*" goto :font_present
if exist "%LOCALAPPDATA%\Microsoft\Windows\Fonts\*NF-*"       goto :font_present
call :need_font
goto :eof

:font_present
echo [ ok ] a Nerd Font is already installed
set "SKIPPED=!SKIPPED! font"
goto :eof

:need_font
echo [....] installing JetBrainsMono Nerd Font ^(DEVCOM.JetBrainsMonoNerdFont^)
echo        Windows may ask for administrator rights for this one.
winget install --exact --id DEVCOM.JetBrainsMonoNerdFont --accept-package-agreements --accept-source-agreements --disable-interactivity
if !ERRORLEVEL! NEQ 0 (
  echo [FAIL] Nerd Font -- winget exited with !ERRORLEVEL!. The ASCII icons
  echo        are used instead, which changes nothing else.
  set "FAILED=!FAILED! font"
) else (
  echo [ ok ] JetBrainsMono Nerd Font installed
  set "DONE=!DONE! font"
)
goto :eof
