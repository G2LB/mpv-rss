@echo off
rem ---------------------------------------------------------------------------
rem  mpv-rss.cmd -- start mpv with the RSS browser open.
rem
rem  Plain "mpv.exe" with no file exits immediately, so this adds:
rem    --idle=yes               keep running with no file loaded
rem    --force-window=immediate create the window right away, to draw the OSD in
rem    --script-opts=rss-auto_open=yes   open the browser on startup
rem    --save-position-on-quit  remember playback positions (also written when
rem                             the RSS browser swaps to another video)
rem
rem  Any arguments you pass are forwarded to mpv.
rem ---------------------------------------------------------------------------

where mpv.exe >nul 2>nul
if errorlevel 1 (
  echo mpv.exe was not found on your PATH.
  echo Install it with:  winget install mpv-player.mpv-CI.MSVC
  pause
  exit /b 1
)

start "" mpv.exe --idle=yes --force-window=immediate --save-position-on-quit ^
  --script-opts=rss-auto_open=yes %*
