# Dependencies

`rss.lua` is one Lua file and needs **mpv** plus a way to make HTTP requests.
Everything else is optional and degrades on purpose: a missing piece turns one
feature off and leaves the rest working.

| | Needed for | Without it |
|---|---|---|
| **mpv** | everything | there is nothing to run the script in |
| **curl** *or* **wget** | fetching feeds | every feed shows `curl could not be run — is it installed?` |
| **yt-dlp** | playing YouTube items | `RSS: yt-dlp not available`; plain RSS and podcast feeds still play |
| **ffmpeg** | thumbnails and podcast artwork | the preview pane is absent, the list is unchanged |
| **a Nerd Font** | the icon set | a complete ASCII icon set is used instead |
| **fontconfig** (`fc-list`) | finding that font automatically, outside Windows | icons stay ASCII until you set `icons=nerd` and `font=` yourself. macOS has a second route (`system_profiler`), so this is only really needed on Linux and the BSDs |
| **nvim + a terminal** | <kbd>Alt</kbd>+<kbd>A</kbd>, editing the feed list in place | the feed file opens in the registered GUI editor instead (`open -t`, `xdg-open`) |

On Windows **curl is already there** — it ships with Windows 10 1803 and later
as `curl.exe` — and PowerShell is the fallback if it is ever missing. macOS
ships curl too. So on those two platforms the HTTP row needs no action.

Installing the script itself is a file copy, covered in
[README §2](README.md#2-install).

---

## Windows — winget

```bat
winget install --exact --id mpv-player.mpv-CI.MSVC
winget install --exact --id yt-dlp.yt-dlp
winget install --exact --id Gyan.FFmpeg
winget install --exact --id DEVCOM.JetBrainsMonoNerdFont
```

Or run **`install-deps.bat`** from this repo, which does exactly that, skips
anything already present, and prints what it did. Double-clicking it is fine;
`install-deps.bat /core` installs only mpv and yt-dlp, and `/q` skips the
closing prompt.

- `mpv-player.mpv-CI.MSVC` is mpv's own CI build. `shinchiro.mpv` is the usual
  alternative and brings a real installer with file associations — either works,
  do not install both.
- The font installs machine-wide, so Windows may raise a UAC prompt for that one
  package. Declining it costs you the icons, nothing else.
- **winget puts new programs on your `PATH`, but only for shells started
  afterwards.** Close the terminal and open a new one before checking, or mpv
  will still be "not found" in the window you installed from.

## macOS — Homebrew

```sh
brew install mpv yt-dlp ffmpeg
brew install --cask font-jetbrains-mono-nerd-font
```

- `brew install mpv` is the mpv binary this script needs. IINA is a different
  player; installing it does not give you `mpv` on the command line.
- `brew install fontconfig` is optional. Without it the script falls back to
  `system_profiler` to find the font, which works but takes a few seconds at
  startup — the interface is up and drawing ASCII icons in the meantime, and
  switches to the Nerd Font when the answer arrives.
- curl is part of macOS; there is nothing to install for HTTP.

## Arch — pacman

```sh
sudo pacman -S --needed mpv yt-dlp ffmpeg curl fontconfig ttf-jetbrains-mono-nerd
```

- `wget` is worth adding only if you want to force `http_backend=wget`; curl is
  what the script picks on its own.
- Any Nerd Font works. `ttf-jetbrains-mono-nerd`, `ttf-firacode-nerd`,
  `ttf-hack-nerd` and `ttf-nerd-fonts-symbols` are all recognised.

## Other distributions

```sh
sudo apt install mpv yt-dlp ffmpeg curl fontconfig fonts-jetbrains-mono   # Debian, Ubuntu
sudo dnf install mpv yt-dlp ffmpeg curl fontconfig jetbrains-mono-fonts   # Fedora
```

The distribution packages are the plain JetBrains Mono, **not** the Nerd Font
patch, so the icons stay ASCII with those. For the patched font, take the
release archive from [nerdfonts.com](https://www.nerdfonts.com/font-downloads),
unzip it into `~/.local/share/fonts/`, and run `fc-cache -f`.

---

## Check what you have

```sh
mpv --version
curl --version      # or: wget --version
yt-dlp --version
ffmpeg -version
fc-list | grep -i nerd          # Linux, macOS, BSD
```

On Windows, in PowerShell:

```powershell
mpv --version; curl.exe --version; yt-dlp --version; ffmpeg -version
```

And the script's own answer — start mpv and read the log:

```
mpv --idle=yes --force-window=immediate --msg-level=rss=v
```

It reports which HTTP backend it settled on, whether it found a Nerd Font and
which family name it is using, and whether yt-dlp and ffmpeg are on `PATH`:

```
[rss] http backend: curl
[rss] using Nerd Font: JetBrainsMono NF
[rss] found yt-dlp 2026.08.19
```

A line saying `ffmpeg not found on PATH; thumbnails disabled` or
`no Nerd Font installed; using ASCII icons` tells you exactly which optional
piece is absent.

## Which program the script actually calls

Useful if you are packaging this, or auditing what it runs. Every one of these
is a subprocess; nothing is linked in and nothing is downloaded on your behalf
except the feeds and the images beside them.

| | Windows | Linux, BSD | macOS |
|---|---|---|---|
| feeds, images, episodes | `curl.exe`, else `powershell.exe` | `curl`, else `wget` | `curl`, else `wget` |
| YouTube | `yt-dlp` (`yt-dlp.exe`, `youtube-dl`) | `yt-dlp` (`yt-dlp_linux`, `youtube-dl`) | `yt-dlp` (`yt-dlp_macos`, `youtube-dl`) |
| thumbnails | `ffmpeg` | `ffmpeg` | `ffmpeg` |
| font list | `powershell.exe` | `fc-list` | `fc-list`, then `system_profiler` |
| <kbd>Alt</kbd>+<kbd>A</kbd> | `wt.exe`, else `cmd.exe /c start` | a terminal emulator, else `xdg-open` | `open -t` |
