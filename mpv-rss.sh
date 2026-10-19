#!/bin/sh
# ---------------------------------------------------------------------------
#  mpv-rss.sh -- start mpv with the RSS browser open (Linux, macOS, BSD).
#  The Windows equivalent is mpv-rss.cmd.
#
#  Plain "mpv" with no file exits immediately, so this adds:
#    --idle=yes               keep running with no file loaded
#    --force-window=immediate create the window right away, to draw the OSD in
#    --script-opts=rss-auto_open=yes   open the browser on startup
#    --save-position-on-quit  remember playback positions (also written when
#                             the RSS browser swaps to another video)
#
#  Any arguments you pass are forwarded to mpv.
# ---------------------------------------------------------------------------
set -eu

if ! command -v mpv >/dev/null 2>&1; then
    echo "mpv was not found on your PATH. Install it with your package manager:" >&2
    echo "  Debian/Ubuntu  sudo apt install mpv" >&2
    echo "  Fedora         sudo dnf install mpv" >&2
    echo "  Arch           sudo pacman -S mpv" >&2
    echo "  macOS          brew install mpv" >&2
    exit 1
fi

exec mpv --idle=yes --force-window=immediate --save-position-on-quit \
    --script-opts=rss-auto_open=yes "$@"
