# rss.lua — an RSS / YouTube subscription browser inside mpv

A keyboard-driven RSS and Atom reader that runs **inside mpv's own on-screen
display**. Subscribe to YouTube channels, see the latest videos, press Enter,
and mpv plays the video through yt-dlp.

```
Ctrl+R  →  Subscriptions  →  Latest videos  →  Enter  →  mpv plays the video
```

No separate application, no web UI, no Electron, no Python or Node. One Lua
file and mpv, on Windows, Linux, macOS and the BSDs.

```
┌──────────────────────────────────────────────────────────────┬─────────┐
│ 1 ALL        2 VIDEOS        3 PODCASTS                      │ preview │
│ 󰀄 Historia Civilis · Oct 17 · 24:00                          │  image  │
│ The Assassination of Julius Caesar (44 B.C.E.)               └─────────┤
│ ◐ started · resume 12:34 of 24:00 (41%)                                │
│ ───────────────────────────────────────────────────────────────────────│
│ ▶ ● Oct 17 | The Assassination of Julius Caesar (44 B.C.E.)            │
│   ◐ Oct 10 | Rome's Social War                                         │
│   ✓ Sep 23 | Battle of Pharsalus                                       │
│   ● Oct 18 | Why No One Has Measured The Speed Of Light                │
└────────────────────────────────────────────────────────────────────────┘
```

The header is a **card about the row you are on** — channel, date, duration,
title, and where you left off — so the list itself needs only one line per
item and twice as many fit on screen.

It also browses **folders on your own disk** — Videos, Music, Audiobooks — in
the same panel, with the same keys, and remembers where you got to in a file
exactly as it does for a feed. See [§6](#6-local-folders--videos-music-audiobooks).

---

## 1. Requirements

| | |
|---|---|
| mpv | any current build. Developed and tested against **v0.41.0** |
| yt-dlp | only for YouTube playback — ordinary RSS feeds work without it |
| HTTP | `curl` — it ships with Windows 10 1803+, with every current Linux, and with macOS. Where it is missing: PowerShell on Windows, `wget` elsewhere |
| ffmpeg | thumbnails only. Without it they are simply off and nothing else changes |
| fontconfig | icon auto-detection outside Windows (`fc-list`). Optional, and macOS has a second route; without either the icons stay ASCII unless you set `icons=nerd` |

Nothing else. The XML parser, the JSON handling and the UI are all in `rss.lua`.

Install commands per package manager — winget, Homebrew, pacman, apt, dnf — and
what exactly stops working if you skip an optional one, are in
**[DEPENDENCIES.md](DEPENDENCIES.md)**. On Windows, **`install-deps.bat`** does
the winget half for you and skips whatever is already there.

### Which platforms

| | |
|---|---|
| **Windows** 10 / 11 | supported |
| **Linux**, **FreeBSD**, **OpenBSD** | supported |
| **macOS** | supported |
| **Android** | untested. Whether an mpv-android build exposes Lua scripts and `subprocess` varies; where it does, the Linux behaviour applies |
| **iOS / iPadOS** | not possible — see below |

The script asks mpv for its `platform` at startup and everything that is not
pure Lua — the scratch directory, the HTTP command, the font list, the editor —
follows from that one answer. There is no separate Windows and Unix version.

Day-to-day development happens on Windows 11. The Linux and macOS branches were
checked by forcing the platform and reading back every command the script then
builds — `curl`, `wget --timeout=… -O /tmp/…`, `fc-list : family`,
`system_profiler`, `yt-dlp` — so the commands and paths are verified, but the
full interface has not yet been driven on a Linux or macOS desktop. Bug reports
from one are welcome.

> **iOS cannot run this, and no change to this script would fix that.** The
> iOS players built on mpv are libmpv behind their own native UI: they draw no
> mpv OSD for a script to render into, and their libmpv is generally built
> without Lua. More fundamentally, iOS does not let an app launch another
> executable, and every network fetch here is a `curl`/`wget` subprocess, as is
> every YouTube resolve (`yt-dlp`) and every thumbnail (`ffmpeg`). A feed
> browser for iOS would have to be a native app that used libmpv for playback
> only — a different program, not a port of this one.

---

## 2. Install

### 2.1 mpv's config directory

`rss.lua` goes in `scripts/` inside it. Where that is:

| | |
|---|---|
| Windows | `%APPDATA%\mpv` — normally `C:\Users\<you>\AppData\Roaming\mpv` |
| Linux, BSD | `~/.config/mpv` (or `$XDG_CONFIG_HOME/mpv`) |
| macOS | `~/.config/mpv` — mpv.app also reads `~/Library/Application Support/mpv` |

If it does not exist, create it: mpv does not create it itself. On Windows,
<kbd>Win</kbd>+<kbd>R</kbd> → `%APPDATA%\mpv` → Enter gets you there.

### 2.2 Copy the script in

Windows, from PowerShell:

```powershell
New-Item -ItemType Directory -Force "$env:APPDATA\mpv\scripts" | Out-Null
Copy-Item .\rss.lua "$env:APPDATA\mpv\scripts\rss.lua"
```

Linux, macOS, BSD:

```sh
mkdir -p ~/.config/mpv/scripts
cp rss.lua ~/.config/mpv/scripts/
```

That is the whole installation.

### 2.3 Optional: the options file

```powershell
New-Item -ItemType Directory -Force "$env:APPDATA\mpv\script-opts" | Out-Null
Copy-Item .\script-opts\rss.conf "$env:APPDATA\mpv\script-opts\rss.conf"
```

```sh
mkdir -p ~/.config/mpv/script-opts
cp script-opts/rss.conf ~/.config/mpv/script-opts/
```

Everything in it is commented out, so it changes nothing until you edit it.
See [§9](#9-configuration).

### 2.4 Install yt-dlp

Needed only to play YouTube videos. On Windows, `install-deps.bat` covers this
step and the next one.

| | |
|---|---|
| Windows | `winget install yt-dlp.yt-dlp` (`scoop` and `choco` work too) |
| Debian, Ubuntu | `sudo apt install yt-dlp` |
| Fedora | `sudo dnf install yt-dlp` |
| Arch | `sudo pacman -S yt-dlp` |
| macOS | `brew install yt-dlp` |
| any | `pipx install yt-dlp`, or the standalone binary from the release page |

It must be on your `PATH` — check with `yt-dlp --version`. mpv finds it by
itself; there is nothing to configure. The script checks for it at startup and
tells you if it is missing when you try to play a YouTube item.

### 2.5 Optional: ffmpeg, for thumbnails

`winget install Gyan.FFmpeg`, `sudo apt install ffmpeg`, `brew install ffmpeg`
— any build on `PATH`. Without it the preview pane is simply absent.

---

## 3. Starting it

Plain `mpv` with no file **exits immediately**, so there has to be a window
to draw in. Two ways:

### Option A — the launcher (recommended, changes nothing globally)

Two launchers ship with the script and do the same thing: **`mpv-rss.cmd`** for
Windows, **`mpv-rss.sh`** for Linux, macOS and the BSDs (`chmod +x mpv-rss.sh`
if your copy lost the bit). Put one anywhere you like — `%APPDATA%\mpv` or
`~/.local/bin` are tidy spots. On Windows, right-click → *Send to* → *Desktop
(create shortcut)* if you want an icon. Either one runs:

```
mpv --idle=yes --force-window=immediate --save-position-on-quit
    --script-opts=rss-auto_open=yes
```

so mpv opens with an empty window and the RSS browser already on screen. Your
normal `mpv video.mkv` behaviour is untouched.

> **One caveat about `--save-position-on-quit`:** mpv's default
> `watch-later-options` includes `volume` and `mute`, so it restores those per
> video too — if you mute something and quit, that video starts muted next
> time. If you would rather it only remembered the position, add this to the
> launcher line:
>
> ```
> --watch-later-options-remove=volume,mute
> ```

### Option B — make it mpv's default

Create `mpv.conf` in the config directory from [§2.1](#21-mpvs-config-directory)
containing:

```
idle=yes
force-window=immediate
save-position-on-quit=yes
```

Now bare `mpv` opens an idle window and <kbd>Ctrl</kbd>+<kbd>R</kbd> works.
Note the side effect: with `idle=yes`, **mpv no longer quits when a video
ends** — it returns to the idle window instead.

### During playback

While any video is playing, <kbd>Ctrl</kbd>+<kbd>R</kbd> opens the browser over
it. Nothing else is needed.

---

## 4. Keys

| Key | Action |
|---|---|
| <kbd>Ctrl</kbd>+<kbd>R</kbd> | open / close the browser |
| <kbd>Tab</kbd> / <kbd>Shift</kbd>+<kbd>Tab</kbd> | next / previous section: Alles / Videos / Podcasts, plus Music / Audiobooks when you have those folders |
| <kbd>1</kbd> … <kbd>5</kbd> | go straight to one section |
| <kbd>↑</kbd> <kbd>↓</kbd> or <kbd>k</kbd> <kbd>j</kbd> | navigate |
| <kbd>PgUp</kbd> <kbd>PgDn</kbd> <kbd>Home</kbd> <kbd>End</kbd> | page / jump |
| <kbd>Enter</kbd> or <kbd>→</kbd> | open feed or folder / play video now |
| <kbd>p</kbd> | **add to the playlist** (at the end) — like "add to queue". On a folder: everything in it, in order |
| <kbd>n</kbd> | **play next** — insert right after the current video. On a folder: the whole folder next |
| <kbd>i</kbd> | show the **playlist**, numbered |
| <kbd>Esc</kbd> <kbd>←</kbd> <kbd>Backspace</kbd> | back (videos → feeds → close; in a folder, one level up) |
| <kbd>q</kbd> | close the browser — **does not quit mpv** |
| <kbd>r</kbd> | refresh (the selected feed, or all from the feed list; in a library, re-read the disk) |
| <kbd>R</kbd> | refresh everything |
| <kbd>m</kbd> | toggle seen / unseen |
| <kbd>v</kbd> | hide / show watched items |
| <kbd>a</kbd> | add the feed URL on the clipboard |
| <kbd>d</kbd> then <kbd>y</kbd> | remove the selected feed |
| <kbd>/</kbd> | filter the current list — in a library, search everything under the folder you are in |
| <kbd>e</kbd> | show the full error of a failed feed |
| <kbd>?</kbd> | keyboard shortcuts, on screen |

<kbd>?</kbd> shows all of this inside mpv, grouped by Navigate / Play /
Folders / Feeds / Other, so you never need this table while using it. In a
window too small to hold the whole list it scrolls, with the same keys as a
list — <kbd>↑</kbd> <kbd>↓</kbd> or <kbd>k</kbd> <kbd>j</kbd>, <kbd>PgUp</kbd>
<kbd>PgDn</kbd>, <kbd>Home</kbd> <kbd>End</kbd> — and says how many lines are
above and below.

Because of that there is **no permanent hint bar** along the bottom — the panel
shows content and nothing else. The bottom row still appears when it has
something to say: what you are typing into the filter, a delete confirmation,
a status message, or the error view's retry hint. Set `footer_hints=yes` to get
the old always-visible bar back.

`p` and `n` never interrupt what is playing, and the browser stays open, so you
can queue several videos in a row. Queued items are tagged `queued`, and the
one playing is tagged `now playing`. The footer shows the playlist length.

### The playlist view

<kbd>i</kbd> shows the queue itself, numbered in play order:

```
PLAYLIST  (4)

▶  1. ▶  Sailor food. They didn't call sailors old salts for nothing!
   2.  ● Drake circumnavigates the globe. Clip from full episode…
   3.  ◐ A pirate raid gone wrong. Clip from full episode…
   4.  ✓ What is a buccaneer?

[4 in playlist]
↑/↓ j/k  navigate      Enter  play this one      d  remove
i / Esc  back      q  close
```

| Key | |
|---|---|
| <kbd>Enter</kbd> | jump straight to that entry |
| <kbd>d</kbd> | remove it from the queue |
| <kbd>i</kbd> or <kbd>Esc</kbd> | back to the list you came from |

Titles are resolved from the feed cache, so queued videos read properly instead
of showing a URL, and each row carries its watch-state marker. The list is read
from mpv itself, so anything queued or removed outside the browser shows up too.

### Do these override mpv's own keys?

**No — not permanently.** Every key above is bound when the browser opens and
unbound when it closes, so outside the browser mpv behaves exactly as it always
did. The only permanent binding is <kbd>Ctrl</kbd>+<kbd>R</kbd>, which no mpv
default uses.

While the browser *is* open, a few of them shadow an mpv default:

| Key | mpv default | Still available as |
|---|---|---|
| `p` | pause | <kbd>Space</kbd> (also pauses, not bound by the browser) |
| `i` | stats | <kbd>Shift</kbd>+<kbd>I</kbd> (stats toggle) |
| `m` | mute | close the browser first, or use the volume keys |
| `1` `2` `3` | contrast / brightness | close the browser first |
| `n` | *nothing* | — no conflict at all |

If you would rather have no collision at all, any of them can be moved in
`rss.conf`:

```ini
key_queue=ctrl+p
key_play_next=ctrl+n
key_index=ctrl+i
```

### Tabs

The first line is a tab bar with live totals, numbered like newsraft's
sections, the active one underlined in blue:

```
1 󰋜 ALL   󰀄 5 / 145   New 145    2 󰕧 VIDEOS   󰀄 3 / 45   New 45    3  PODCASTS …
                                 ────────────────────────
```

Each tab shows an author icon with **sources / items**, and how many are still
unplayed as **New n** in purple. The count drops as you watch things. The
number in front is the key that goes straight there: <kbd>1</kbd>, <kbd>2</kbd>,
<kbd>3</kbd>.

The preview image for the highlighted row is docked in the panel's **top-right
corner**, level with the tab bar, and costs the rest of the interface only its
own width — the tabs, the heading and the titles all run up to it, so the list
is as wide as the panel allows. The slot is held open whenever thumbnails are
available, so nothing shifts as you scroll past an item without artwork.

Its height is not a setting: the preview is exactly as tall as the header band,
so it **sits on the rule** that closes the header, which runs the full width of
the panel underneath it. To make it bigger, raise `font_size` — a taller card
gives a taller band gives a bigger preview. `thumbnail_aspect` (1.78 = 16:9)
decides the shape; squarer artwork is scaled to cover and centre-cropped, so
the frame is always full.

**Watched items are hidden by default** — the heading reads *unwatched only*,
and <kbd>v</kbd> shows them again. Part-watched items stay visible, since those
are precisely the ones you have not finished. Set `hide_watched=no` to start
with everything visible.

The subscription list is topped by two virtual entries, and every row is one
line with **new / total** on the right:

```
● New                                                             130
󰋜 All items               ← everything in the tab, newest first  130 / 145
󰕧 Historia Civilis                                                15 / 15
```

<kbd>m</kbd> on a **feed** — or on **New** / **All items** — marks that whole
set watched in one go, reporting *"Historia Civilis · feed watched (15 items)"*,
and the New counters drop immediately. Press it again on a fully watched feed
to make the whole thing new again.

<kbd>Tab</kbd> cycles Alles → Videos → Podcasts (<kbd>Shift</kbd>+<kbd>Tab</kbd>
goes back), and <kbd>1</kbd> <kbd>2</kbd> <kbd>3</kbd> jump straight to one.
Neither Tab key is bound by mpv itself; the digits are, so they are taken over
only while the browser is open.

**The tab bar is as long as your sources make it.** A local Music folder adds a
**MUSIC** tab and an Audiobooks folder an **AUDIOBOOKS** tab — <kbd>4</kbd> and
<kbd>5</kbd> — while a local video folder joins **VIDEOS**, next to the
channels. Tabs with nothing behind them never appear, so a machine without
those folders shows the same three sections it always did. The columns share
the width evenly, and the per-tab counts are dropped when the columns get too
narrow for them; the number, the label and the New badge always survive.
[§6](#6-local-folders--videos-music-audiobooks) covers the folders themselves.

A feed's type is detected from its own entries: YouTube items or a video
enclosure make it a **video** feed, an audio enclosure or Podcasting 2.0 markup
make it a **podcast**. Anything else (a plain blog feed) appears under **Alles**
only. Each tab's first row merges just that tab's feeds, newest first.

### Small windows

Every size in the panel is in *virtual canvas units*, so the interface does not
reflow when mpv is resized — it is simply scaled. In a window that is a fraction
of the screen that is worse than cramped: three tab columns, an artwork column
and two-line rows all survive, each shrunk to a few dozen real pixels.

So below a threshold the browser switches to a **single-column layout**: one
section at a time with its place in the cycle, the counts on the right, one line
per item with its date, a smaller preview image, and larger text.

```
1/3  󰋜 ALL   New 8                                                  󰀄 4 / 8
────────────────────────────────────────────────────────────────────────────
▶ ● New                                                                    8
  󰋜 All items                                                           8 / 8
  󰕧 Historia Civilis                                                    3 / 3
   PODCAST The Rest Is History                                          2 / 2
```

<kbd>Tab</kbd> cycles the sections and <kbd>1</kbd> <kbd>2</kbd> <kbd>3</kbd>
pick one outright — the bar can only show the one you are in, so a brief
*2/3 VIDEOS* confirms where you landed.

It switches over when the window is **960 px wide or less**, *or* **narrower
than 60 % of the display** mpv is on — the second rule is what catches a window
that is only small relative to a big screen. Fullscreen is therefore always the
wide layout. All of it is tunable, and can be forced either way:

```ini
narrow_layout=auto     # auto | always | never
narrow_width=960       # px; 0 disables this rule
narrow_ratio=0.6       # fraction of the display; 0 disables this rule
narrow_scale=1.2       # how much larger the text gets
```

### Colours — Tokyo Night Storm

Everything is coloured by **state**, so the list can be read at a glance.

| Shown as | Meaning | Palette |
|---|---|---|
| `●` white | never played | `fg` `#c0caf5` |
| `◐` light blue, with `resume 1:23` | started, not finished | `cyan` `#7dcfff` |
| `✓` grey | watched to the end | `comment` `#565f89` |
| orange row | the selection | `orange` `#ff9e64` |
| green meta `now playing` | playing right now | `green` `#9ece6a` |
| teal meta `queued` | waiting in the playlist | `teal` `#73daca` |
| red warning badge | that feed failed to refresh | `red` `#f7768e` |
| blue tab | the active tab | `blue` `#7aa2f7` |
| grey-blue metadata | dates, channel, key hints | `dark5` `#737aa2` |

**Red is reserved for genuine errors.** A status line about playback is orange,
queueing is teal, and a feed that was added or removed reports in green — so a
red line always means something actually went wrong.

Every colour lives in one `THEME` table at the top of the rendering section of
`rss.lua`, as plain hex. No other line of rendering code contains a colour.

### Icons

The interface uses Nerd Font glyphs when one is installed and falls back to a
complete ASCII set when none is (`icons = auto | nerd | ascii`).

> **The family name matters, and it is not the same on every platform.** The
> Windows installer registers JetBrains Mono Nerd Font as **`JetBrainsMono
> NF`**; fontconfig on Linux and macOS reports it as **`JetBrainsMono Nerd
> Font`**. The wrong one renders every icon as an empty box. Leave `font=`
> empty and the script finds an installed Nerd Font by itself — it knows both
> spellings and asks the OS which it has: PowerShell on Windows, `fc-list` on
> Linux and the BSDs, `fc-list` then `system_profiler` on macOS. If none of
> those can answer (a macOS without fontconfig, say) the icons stay ASCII until
> you set `icons=nerd` and `font=` yourself.

### Failed feeds

A feed that will not load shows a short `Unable to refresh` with a warning badge
— never a raw `curl: (7) …` line in the middle of your subscriptions. Press
<kbd>e</kbd> (or <kbd>Enter</kbd>, when the feed has nothing cached) for the
error view with the full technical message, the feed URL, and <kbd>r</kbd> to
retry. Other feeds keep working throughout.

### Title card

When a feed item starts playing, its title, channel and duration appear briefly
at the top left and fade out after 2.5 s — set `title_overlay=no` to turn it off,
or `title_overlay_seconds` to change how long it stays.

### While you are browsing, the picture stays

If a video reaches its end while the browser is open, mpv would normally unload
it and drop to an empty window — the picture disappearing from behind the panel
while you are still reading. So for as long as the browser is on screen the
script borrows mpv's own `keep-open`, which holds the last frame instead, and
restores whatever you had set the moment you close the browser. Playing
something new from the browser starts normally. Turn it off with
`keep_open_in_menu=no`.

### The panel and mpv's controls

The panel stops short of the bottom of the window so it never covers mpv's own
on-screen controller. It asks the OSC how much room it reserves and keeps at
least `osc_reserve` (10% by default) free regardless, because the OSC reports
nothing while it is hidden. The RSS browser does not replace mpv's playback
controls — those stay exactly as they are.

Progress is sampled while a video plays and stored under the video's ID, so it
survives restarts — including for videos that reached the player through the
playlist rather than through <kbd>Enter</kbd>. Pressing <kbd>Enter</kbd> on a
partially watched item **resumes it** at the saved position. Anything under 15
seconds does not count as started, and <kbd>m</kbd> overrides the state by hand.

---

## 5. Adding a YouTube channel

### The easy way

Copy a channel or podcast URL to the clipboard and press <kbd>a</kbd>. That
opens a one-line field with the clipboard already pasted into it, so you can see
and correct what it picked up before committing:

```
󰀄 Add feed: https://www.youtube.com/feeds/videos.xml?channel_id=UCXuqS…_
  Enter  confirm     Esc  cancel     Ctrl+V  paste     Ctrl+U  clear
```

<kbd>Enter</kbd> adds it, <kbd>Esc</kbd> cancels, <kbd>Ctrl</kbd>+<kbd>V</kbd>
pastes again (handy if you copied the URL after opening the field), and
<kbd>Ctrl</kbd>+<kbd>U</kbd> clears the line. Several URLs separated by spaces
or newlines are all added in one go, so a list pasted out of a text file works.

All of these forms are understood:

```
https://www.youtube.com/channel/UCv_vLHiWVBh_FR9vbeuiY-A
https://www.youtube.com/@HistoriaCivilis
https://www.youtube.com/feeds/videos.xml?channel_id=UCv_vLHiWVBh_FR9vbeuiY-A
https://www.youtube.com/playlist?list=PLxxxxxxxxxxxx
UCv_vLHiWVBh_FR9vbeuiY-A
```

plus any ordinary RSS or Atom feed URL, including **podcast feeds**. The name is
taken from the feed itself, so you do not have to type one.

If you paste a *website* rather than a feed, the page is fetched and its
autodiscovery link (`<link rel="alternate" type="application/rss+xml">`) is
followed. Plenty of sites publish no such link — `noagendashow.net` is one — and
you then get told to paste the feed URL itself (for that show:
`https://feed.nashownotes.com/rss.xml`).

### Podcasts

Audio podcasts work the same as video. An episode's `<enclosure>` is what gets
played — not the episode's web page — and the list shows the episode length from
`<itunes:duration>`. yt-dlp is not involved; mpv streams the audio directly.

Podcasting 2.0 feeds are recognised (the feed list marks them `podcast 2.0`),
and episodes carrying `<podcast:chapters>` are tagged `chapters`.

> **If an episode will not play:** a few servers refuse a TLS handshake with
> mpv's bundled ffmpeg even though everything else connects fine
> (bitsoffreedom.nl is one). The browser notices, fetches that episode once
> with curl, and plays it from disk — you see *"this server blocks streaming —
> downloading episode…"*. The temporary file is deleted when mpv exits. Turn it
> off with `download_fallback=no`.
>
> This applies to episodes you **queue** with `p` or `n` as well as ones you
> start with Enter, and the downloads run one at a time: a feed on such a
> server fails every queued episode within a second or two, and fetching 50 MB
> apiece in parallel would help nobody. `http_timeout` is deliberately not
> applied to them — it is a per-feed budget for a few kilobytes of XML, and an
> episode that ran past it was being killed partway with nothing to play.

**No YouTube API key is needed, ever.** A `channel/UC…` URL contains the channel
ID already. For an `@handle`, the script fetches that public page once and reads
the channel ID out of it — if YouTube ever changes that page, the fallback is to
use the `channel/UC…` or `channel_id=UC…` form, which needs no network lookup at
all.

### Finding a channel ID by hand

Open the channel in a browser, *View Source*, and search for `channelId`. Or
open any video of the channel and click the channel name — the URL may already
be `.../channel/UC…`.

The feed URL is always:

```
https://www.youtube.com/feeds/videos.xml?channel_id=UCxxxxxxxxxxxxxxxxxxxxxx
```

YouTube serves the 15 most recent videos there.

### Shorts

That channel feed lists Shorts alongside real uploads, and with only 15 slots a
channel that posts clips daily can push every actual video out of it. So by
default (`skip_shorts=yes`) the script does not fetch the channel feed at all:
it fetches the channel's **long-form uploads playlist**, which is the channel ID
with `UC` replaced by `UULF` —

```
https://www.youtube.com/feeds/videos.xml?playlist_id=UULFxxxxxxxxxxxxxxxxxxxxxx
```

— the same 15-item list, built by YouTube with the Shorts already left out. On
top of that, any entry that still looks like a Short (a `/shorts/` link, or
`#shorts` in the title) is dropped, which covers playlist feeds that cannot be
redirected this way.

`rss-feeds.json` keeps the URL you added, so this is reversible: set
`skip_shorts=no` and the feed is fetched exactly as listed. A channel with no
long-form playlist (a Shorts-only channel) falls back to its channel feed. The
`UUSH` / `UULV` / `UUPS` playlist feeds — Shorts, live, podcasts — are never
redirected, so subscribing to one of those on purpose still works.

### Live streams

The long-form playlist leaves out more than Shorts: it holds no **streams** at
all. On its own it therefore hides everything a channel that mostly goes live
has posted — a channel whose last 15 uploads are all streams comes back as 15
older videos instead, and nothing recent ever appears.

So `include_live=yes` (the default) fetches the channel's stream playlist too —
the channel ID with `UC` replaced by `UULV` —

```
https://www.youtube.com/feeds/videos.xml?playlist_id=UULVxxxxxxxxxxxxxxxxxxxxxx
```

— and merges it into the long-form list, newest first, dropping duplicates.
That playlist holds finished streams as well as whatever is live now, so past
broadcasts come back in date order alongside ordinary uploads. A channel that
has never streamed has an empty one, which costs a request and adds nothing.
Set `include_live=no` to go back to the long-form playlist alone.

A stream that is **live right now** is also kept out of the resume bookkeeping.
Its duration grows as it arrives and the playback position trails just behind,
so the ratio between them drifts past `watched_threshold` after about half a
minute — a programme you dipped into for a moment would otherwise be marked
fully watched, and with `hide_watched` on it would then disappear. Nothing is
recorded for a broadcast while it runs; "where you left off" in one is only
ever the live edge. If the broadcast ends while you are watching it, that does
count as having watched it.

### In an editor

<kbd>Alt</kbd>+<kbd>A</kbd> opens `rss-feeds.json` in an editor. With the
default `editor=auto` that means, per platform:

| | |
|---|---|
| Windows | nvim inside Windows Terminal, falling back to nvim in a console window |
| macOS | `open -t` — whichever plain-text editor is registered |
| Linux, BSD | `$VISUAL` or `$EDITOR` — or, with neither set, the first of nvim, vim, nano, vi that is actually installed — inside the first terminal emulator that is: `x-terminal-emulator`, kitty, alacritty, wezterm, foot, gnome-terminal, konsole, xterm. And `xdg-open` if there is no terminal at all |

Set `editor=` to any command instead. The file path is appended, or substituted
for a `{}` if you put one in: `editor=code -w`, `editor=notepad`,
`editor=kitty nvim`, `editor=x-terminal-emulator -e vim`.

You do not have to close the editor afterwards: the file is watched, and the
moment you `:w` the browser reloads the list, reports *"rss-feeds.json
reloaded"* and fetches anything new. A hand edit **replaces** the list, so
renames and deletions you make in the file win — unlike <kbd>a</kbd>, which
merges.

### By editing the file

`<config>/rss-feeds.json` — `%APPDATA%\mpv` on Windows, `~/.config/mpv`
elsewhere:

```json
{
  "feeds": [
    {
      "name": "Historia Civilis",
      "url": "https://www.youtube.com/feeds/videos.xml?channel_id=UCv_vLHiWVBh_FR9vbeuiY-A",
      "enabled": true
    },
    {
      "name": "Some Blog",
      "url": "https://example.com/feed.xml",
      "enabled": true
    }
  ]
}
```

`name` is a label only — change it to whatever you like. `enabled: false` keeps
a feed in the list but skips it on refresh. Save the file as **UTF-8**; a BOM is
tolerated. Restart mpv to pick up hand-made changes.

---

## 6. Local folders — Videos, Music, Audiobooks

Subscriptions are not the only thing worth a tab. A **library** is a folder on
your own disk, browsed as a tree in the same panel, with the same keys, and
with the same memory of where you stopped in a file.

```
┌───────────────────────────────────────────────────────────────┬────────┐
│ 1 ALL      2 VIDEOS      3 PODCASTS      4 MUSIC      5 AUDIOBOOKS     │
│                                                 ──────────────┤ cover  │
│ 󰉋 Audiobooks / Ancient_Recitations · 2026-09-21 · 24 MB       │ image  │
│ 01 The prologue of Gilgamesh                                  └────────┤
│ ◐ started · resume 04:12 of 21:40 (19%)                                │
│ ───────────────────────────────────────────────────────────────────────│
│ ▶ ● Sep 21 | 01 The prologue of Gilgamesh                              │
│   ✓ Sep 21 | 02 Gilgamesh and Enkidu                                   │
│   ● Sep 21 | 03 The journey to the cedar forest                        │
└────────────────────────────────────────────────────────────────────────┘
```

Nothing is fetched and nothing is scanned up front: a folder is read when you
walk into it, so pointing this at a disk with 50 000 files costs nothing until
you look inside.

### 6.1 Declaring them

They live in `rss-feeds.json`, beside the feeds, under a `libraries` key:

```jsonc
{
  "feeds": [
    {"name": "Historia Civilis", "url": "https://www.youtube.com/feeds/videos.xml?channel_id=UCv_vLHiWVBh_FR9vbeuiY-A"}
  ],
  "libraries": [
    {"name": "Videos",     "path": "C:/Users/Luke/Videos",     "kind": "videos"},
    {"name": "Music",      "path": "C:/Users/Luke/Music",      "kind": "music"},
    {"name": "Audiobooks", "path": "C:/Users/Luke/Audiobooks", "kind": "audiobooks"}
  ]
}
```

<kbd>Alt</kbd>+<kbd>A</kbd> opens that file in an editor and reloads it the
moment you save — the same route as editing feeds.

**You do not have to write it yourself.** On first run — or the first run after
updating a script that predates libraries — the three standard folders for your
platform are written into the file for you:

| Platform | Folders offered |
|---|---|
| Windows | `%USERPROFILE%\Videos`, `\Music`, `\Audiobooks` |
| Linux, macOS, BSD | `~/Videos`, `~/Music`, `~/Audiobooks` |

Whatever exists shows up; whatever does not is ignored. On a typical Windows
machine that means Videos and Music work immediately and Audiobooks starts
working the day you create the folder.

Each entry takes:

| Field | Meaning |
|---|---|
| `path` | the folder. Forward or backward slashes, `~/` understood, UNC paths (`//nas/media`) fine. **Required** |
| `name` | what the row is called. Defaults to the last part of the path |
| `kind` | `videos`, `music` or `audiobooks` — which tab it lands in. Guessed from the name when left out |
| `enabled` | `false` switches it off without deleting it |
| `sort` | `name`, `date` or `size`, for this library only. Defaults to `library_sort` |

A bare string is shorthand for `{"path": "…"}`:

```jsonc
"libraries": ["D:/Films", "//nas/media/Music"]
```

`kind` is guessed from the name and the path when you leave it out: anything
that looks like music or an audiobook — in English, Dutch or German — lands in
that tab, and everything else is treated as video.

### 6.2 Switching one off

Three ways, and a library is left out silently by all of them:

```jsonc
"libraries": [
  {"name": "Music", "path": "C:/Users/Luke/Music", "kind": "music"},
  {"name": "Films", "path": "D:/Films", "enabled": false},   // switched off
  // {"name": "NAS", "path": "//nas/media"},                 // commented out
  {"name": "Work laptop only", "path": "E:/Media"}           // E: is not here
]
```

1. `"enabled": false`.
2. **A comment.** `rss-feeds.json` is read as JSON *with comments* — `//` to
   end of line, `/* … */`, and a comma left dangling in front of a `}` or `]`
   once you have commented out the last entry. Strict JSON allows none of
   that, and mpv's parser rejects a file outright for it, so this is handled
   before the file is parsed. `https://` and `//nas/share` are safe: text
   inside quotes is never treated as a comment.
3. **The folder is not on this machine.** No error, no empty tab — which is
   what makes one `rss-feeds.json` carryable between a desktop and a laptop
   that do not have the same disks.

A name that starts with `//`, `#`, `;` or `--` counts as commented out too, for
switching one off without restructuring the file.

> **Comments do not survive a rewrite.** Adding a feed with <kbd>a</kbd> or
> removing one with <kbd>d</kbd> rewrites the file from what was parsed, and a
> parser does not keep comments. Everything else survives exactly as it was —
> including entries that are disabled and entries for folders this machine does
> not have — so prefer `"enabled": false` for anything you want to keep.

A file that is there but **does not parse** is now left strictly alone: the
feeds and libraries already loaded stay loaded, nothing is written over it, and
the error says so. Before, one stray comma cost you the file.

### 6.3 Browsing

A library is a row in its tab, under the feeds. <kbd>Enter</kbd> walks in,
<kbd>Esc</kbd> walks back out one level at a time, and coming out of a folder
puts the cursor back on it rather than at the top of the list.

* Folders sort by name, and **numerically where the name is numbered** — `Track 2`
  before `Track 10`, which is the whole reason a music folder is named that way.
* Files sort by `library_sort`: `name` (default), `date` or `size`.
* Only playable files get a row. The built-in list covers the usual video and
  audio extensions, `m4b` included; `library_extensions=…` adds more.
* `Wim_Hof_Method_[abc123].mp4` is shown as **Wim Hof Method** — underscores
  become spaces and the id yt-dlp appends is dropped. `library_clean_names=no`
  leaves filenames exactly as they are.
* Hidden files, dotfiles and Windows' `desktop.ini` are skipped unless
  `library_hidden=yes`.

**Watch state works exactly as it does for a feed.** A file you have started is
marked `◐` and resumes where you left it; one you have finished is `✓`. The
state is keyed on the path, so moving a file loses its place — nothing else
does.

The preview works too, with no network involved: ffmpeg lifts the **cover art**
out of an album track and the **first frame** out of a video.

### 6.4 The index

While you browse, each library is walked in the background — a handful of
directories per tick, so a slow disk cannot stall mpv — to build a flat list of
everything under it. That index is what gives you:

* **<kbd>/</kbd> searches the whole library**, not the folder you happen to be
  standing in. Results show the path they were found at. It matches folder
  names as well as filenames, so searching for a performer finds their folder.
* **Counts**: `0 / 244` on the library row, and the totals in the tab bar.
* **<kbd>p</kbd> and <kbd>n</kbd> on a folder** reaching into its subfolders.

`library_max` caps it (20 000 files) and `library_depth` limits how deep it
goes (8 levels). A capped library says *index full* in the header card and
still browses normally. `library_index=no` turns the walk off altogether:
browsing still works folder by folder, and <kbd>/</kbd> then filters just the
listing in front of you.

<kbd>r</kbd> re-reads a library from the disk — both the listings and the index
— which is how a file copied in while mpv was running shows up.

### 6.5 Queueing a whole folder

<kbd>p</kbd> on a folder or on a library queues **everything under it, in
order**. <kbd>n</kbd> does the same as *play next*, inserted so that the first
file is the one that plays next — an audiobook in chapters, an album with its
discs in subfolders, a season of something, all with one key. The browser stays
open and the footer reports what went in:

```
RSS: queued · 14 files from Wim_Hof   [playlist: 15]
```

<kbd>m</kbd> on a folder marks everything under it watched, or unwatched again
if it already was.

### 6.6 What a library deliberately does not do

**It does not feed New or All items.** Those two rows answer *what has arrived
since I last looked*, which is a question about a feed. A folder of 4 000 songs
has no answer to it and would drown the one the feeds gave, so a library-only
tab (MUSIC, AUDIOBOOKS) skips both rows and lists its folders instead, and the
`New` badge in the tab bar stays about feeds.

**It does not hide watched files.** `hide_watched` is off in a library however
it is set elsewhere: a file browser that hides files you have played would be
lying about what is in the folder. The markers still tell you which is which.

**It never writes to your media folders.** Libraries are read-only; the only
thing on disk that changes is `rss-state.json`, which remembers positions.

### 6.7 Options

| Option | Default | |
|---|---|---|
| `libraries` | `yes` | `no` ignores the `libraries` key entirely |
| `library_sort` | `name` | `name`, `date` or `size`. Folders are always by name |
| `library_index` | `yes` | the background walk. `no` = browse only, no search, no counts |
| `library_depth` | `8` | how deep that walk goes |
| `library_max` | `20000` | and how many files it keeps |
| `library_hidden` | `no` | include dotfiles and hidden folders |
| `library_clean_names` | `yes` | `Wim_Hof_[abc].mp4` → `Wim Hof` |
| `library_extensions` | *(empty)* | extra playable extensions, comma separated, no dots |

---

## 7. Playing, refreshing, removing

**Play** — select a video, press <kbd>Enter</kbd>. The URL is handed to mpv
(`loadfile`), which resolves it with yt-dlp. Nothing is downloaded to disk
first. The browser closes so you see the video, and playback progress is
recorded as you watch.

**Queue** — <kbd>p</kbd> adds the selected video to the end of the playlist,
<kbd>n</kbd> inserts it as the next one to play. Neither stops the current
video, and the browser stays open so you can queue up several. Use mpv's own
<kbd>&gt;</kbd> / <kbd>&lt;</kbd> to move through the playlist.

**Refresh** — <kbd>r</kbd>. From the feed list it refreshes everything; with a
single feed selected, just that one. `Refreshing… (2/5)` appears in the panel
header while it runs; the UI stays usable. Feeds are also refreshed when you
open the browser if they are older than 30 minutes (configurable). There is no
background polling — YouTube is only contacted when you ask.

**Remove** — select a feed, press <kbd>d</kbd>, confirm with <kbd>y</kbd>. Any
other key cancels. This also drops that feed's cached entries.

**Filter** — <kbd>/</kbd>, type, <kbd>Enter</kbd> to apply or <kbd>Esc</kbd> to
clear. Case-insensitive, matches title and channel, runs entirely against
already-downloaded entries — no network, no YouTube search.

---

## 8. Files it writes

All inside your mpv config folder; nothing is ever written to the mpv
installation directory.

Paths below are written as `<config>/`, which is `%APPDATA%\mpv\` on Windows
and `~/.config/mpv/` elsewhere ([§2.1](#21-mpvs-config-directory)).

| File | Contents |
|---|---|
| `<config>/rss-feeds.json` | your subscriptions, and your local folders ([§6](#6-local-folders--videos-music-audiobooks)) |
| `<config>/rss-cache.json` | downloaded entries, so navigation needs no network |
| `<config>/rss-state.json` | watch state and resume positions, by video ID |

Thumbnails and the pictures they are made from are cached outside the config
directory, in the system scratch space: `%TEMP%` on Windows, `$TMPDIR` or
`/tmp` elsewhere. Deleting them costs one re-download each.

They are created automatically on first run. Watch state is keyed on the
YouTube video ID (or the feed item's `guid`), not the title, so a renamed video
stays watched. Deleting any of these files is safe.

**Nothing is lost if mpv goes away unexpectedly.** Playback progress is
committed to disk every `autosave_interval` seconds (60 by default) while
something is playing, on top of the writes when a file ends and when mpv shuts
down. Verified by killing mpv mid-playback: the resume position was still there.

**Editing `rss-feeds.json` by hand is safe while mpv is running.** The file is
re-read and merged before every write, and again when you open the browser or
press <kbd>R</kbd>, so a feed you add in the file is adopted — reported as
*"picked up N new feeds"* — instead of being overwritten by the copy in memory.
Your cache and watch state are untouched by this; adding a feed never costs you
anything you had already. Feeds you remove with <kbd>d</kbd> stay removed and
are not resurrected by the merge. A library added, renamed or commented out in
the file is picked up on the next open as well.

It is **written back indented**, one feed or library per line, because it is a
file people open. It takes `//` and `/* … */` comments and a trailing comma
(see [§6.2](#62-switching-one-off)), and a file that does not parse is left
alone rather than replaced.

---

## 9. Configuration

`<config>/script-opts/rss.conf`, one `key=value` per line. The shipped
file lists every option with its default, all commented out. The ones you are
most likely to touch:

```ini
key_open=ctrl+r          # any mpv key name
refresh_interval=1800    # seconds; 30 minutes
max_entries_per_feed=50
max_total_entries=300    # size of the merged "All Videos" list
skip_shorts=yes          # leave YouTube Shorts out of channel feeds
include_live=yes         # fetch a channel's streams too (skip_shorts leaves them out)
visible_rows=20          # upper bound on items per page
ui_width=0.86            # fraction of the window
font_size=16             # 16 fits ~15 items, 12 fits ~21
list_size=1.2            # list rows, as a fraction of font_size
date_format=short        # "Aug 06" | relative | absolute
osd_height=720           # virtual canvas; the UI scales to any window size
narrow_layout=auto       # single-column layout in a small window (see §4)
narrow_width=960         # ...at or below this window width in px
narrow_ratio=0.6         # ...or this fraction of the display width
libraries=yes            # local folders (see §6); no = ignore them
library_sort=name        # name | date | size, inside a library
library_index=yes        # background walk: / searches it all, and the counts
library_depth=8          # how deep that walk goes
library_max=20000        # and how many files it keeps
library_clean_names=yes  # "Wim_Hof_[abc].mp4" -> "Wim Hof"
feeds_file=              # empty = <mpv config dir>\rss-feeds.json
cache_file=
state_file=
```

**To see more videos at once**, lower `font_size` — every row is already a
single line, and the panel always fits itself to the window, so `visible_rows`
alone cannot push more items on screen than physically fit.

Options also work on the command line:

```
mpv --script-opts=rss-font_size=12,rss-date_format=relative
```

---

## 10. Troubleshooting

**Nothing happens when I run `mpv`** — mpv with no file exits immediately.
Use `mpv-rss.cmd` / `mpv-rss.sh`, or add `idle=yes` and `force-window=immediate`
to `mpv.conf` ([§3](#3-starting-it)).

**<kbd>Ctrl</kbd>+<kbd>R</kbd> does nothing** — check the script actually
loaded:

```
mpv --msg-level=rss=debug --idle=yes --force-window=immediate
```

You should see `Loading lua script …/rss.lua` and `rss ready (feeds=… cache=…
state=…)`. If another script already uses `ctrl+r`, change `key_open`.

**A feed shows a red error line** — the message comes from whichever HTTP
backend ran, shown next to the feed name: `curl: (22) … error: 404` for a wrong
URL, `Could not connect` for a dead host, or `curl could not be run — is it
installed?` when the program itself is missing. Other feeds keep loading
regardless. The browser never takes mpv down over a bad feed.

**`RSS: Invalid XML`** — the URL returned something that is not a feed, usually
an HTML error page. Open the URL in a browser to check.

**`RSS: yt-dlp not available`** — install it ([§2.4](#24-install-yt-dlp)) and make sure `yt-dlp
--version` works in the same shell you start mpv from.

**A video does not play** — try the URL directly:

```
mpv "https://www.youtube.com/watch?v=VIDEOID"
```

If that fails too, it is mpv/yt-dlp, not this script. `yt-dlp -U` fixes most
YouTube breakage.

**Inspect what the parser sees from a feed:**

```
mpv --idle=yes --msg-level=rss=debug --script-opts=rss-debug_parse=https://www.youtube.com/feeds/videos.xml?channel_id=UC...
```

It prints the entry count and the first five entries with their id, date, title
and URL. A local file path works too.

**Force a particular HTTP backend** (if curl is blocked by policy, say):

```
mpv --script-opts=rss-http_backend=powershell   # Windows
mpv --script-opts=rss-http_backend=wget         # Linux, macOS, BSD
```

**No icons on Linux or macOS** — install `fontconfig` so `fc-list` can answer,
or name the family yourself: `--script-opts=rss-icons=nerd,rss-font=JetBrainsMono Nerd Font`.

**Start over** — delete `rss-cache.json` and `rss-state.json` from the config
directory. They are rebuilt on the next refresh.

---

## 11. Notes on behaviour

**Security.** Feed content is treated as untrusted: nothing from a feed is ever
executed or evaluated, URLs are validated as `http(s)` before being handed to
mpv or to a subprocess, and feed text is escaped before it reaches the ASS
renderer so a crafted title cannot take over the display. Only the item you
press <kbd>Enter</kbd> on is ever loaded, and nothing is downloaded on its own.

**Feed formats.** RSS 2.0 and Atom, including CDATA, XML entities, and the
YouTube-specific `yt:videoId` / `yt:channelId` / `media:*` elements. Dates are
read from `published`, `pubDate`, `updated` or `dc:date` in both ISO-8601 and
RFC-822 form. A feed that is malformed, truncated or empty produces a message,
not a crash — a truncated feed still yields the entries that were intact.

**Thumbnails and podcast artwork.** The highlighted item's image is drawn beside
the list: a YouTube video thumbnail (`media:thumbnail`), a per-episode podcast
image (`itunes:image`, `podcast:images`, `podcast:artwork`), or failing that the
show artwork of the feed. mpv's Lua cannot decode PNG or JPEG and ASS cannot
embed a bitmap, so the image is converted to raw BGRA with **ffmpeg** and put on
screen with mpv's `overlay-add`. Converted images are cached on disk, so each
one is fetched only once. Without ffmpeg on `PATH` thumbnails are simply off and
everything else works unchanged; `thumbnails=no` disables them explicitly.
