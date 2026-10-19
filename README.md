# rss.lua — an RSS / YouTube subscription browser inside mpv

A keyboard-driven RSS and Atom reader that runs **inside mpv's own on-screen
display**. Subscribe to YouTube channels, see the latest videos, press Enter,
and mpv plays the video through yt-dlp.

```
Ctrl+R  →  Subscriptions  →  Latest videos  →  Enter  →  mpv plays the video
```

No separate application, no web UI, no Electron, no Python or Node. One Lua
file and mpv.

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

---

## 1. Requirements

| | |
|---|---|
| mpv | any current build. Developed and tested against **v0.41.0** on Windows 11 |
| yt-dlp | only for YouTube playback — ordinary RSS feeds work without it |
| HTTP | `curl.exe` (ships with Windows 10 1803+) or PowerShell — whichever exists |

Nothing else. The XML parser, the JSON handling and the UI are all in `rss.lua`.

---

## 2. Install

### 2.1 Locate `%APPDATA%\mpv`

Press <kbd>Win</kbd>+<kbd>R</kbd>, type `%APPDATA%\mpv`, press Enter. That is
mpv's configuration folder, normally:

```
C:\Users\<you>\AppData\Roaming\mpv
```

If the folder does not exist, create it — mpv does not create it itself when
installed through winget.

### 2.2 Create the `scripts` folder

```
%APPDATA%\mpv\scripts
```

### 2.3 Copy `rss.lua` into it

```
%APPDATA%\mpv\scripts\rss.lua
```

That is the whole installation. From PowerShell:

```powershell
New-Item -ItemType Directory -Force "$env:APPDATA\mpv\scripts" | Out-Null
Copy-Item .\rss.lua "$env:APPDATA\mpv\scripts\rss.lua"
```

### 2.4 Optional: the options file

```powershell
New-Item -ItemType Directory -Force "$env:APPDATA\mpv\script-opts" | Out-Null
Copy-Item .\script-opts\rss.conf "$env:APPDATA\mpv\script-opts\rss.conf"
```

Everything in it is commented out, so it changes nothing until you edit it.
See [§8](#8-configuration).

### 2.5 Install yt-dlp

Needed only to play YouTube videos.

```powershell
winget install yt-dlp.yt-dlp
```

(`scoop install yt-dlp` or `choco install yt-dlp` work too.) It must be on your
`PATH` — check with:

```powershell
yt-dlp --version
```

mpv finds it by itself; there is nothing to configure. The script checks for it
at startup and tells you if it is missing when you try to play a YouTube item.

---

## 3. Starting it

Plain `mpv.exe` with no file **exits immediately**, so there has to be a window
to draw in. Two ways:

### Option A — the launcher (recommended, changes nothing globally)

Copy `mpv-rss.cmd` anywhere you like (`%APPDATA%\mpv` is a tidy spot) and run
it. Right-click → *Send to* → *Desktop (create shortcut)* if you want an icon.
It runs:

```
mpv.exe --idle=yes --force-window=immediate --save-position-on-quit
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

Create `%APPDATA%\mpv\mpv.conf` containing:

```
idle=yes
force-window=immediate
save-position-on-quit=yes
```

Now bare `mpv.exe` opens an idle window and <kbd>Ctrl</kbd>+<kbd>R</kbd> works.
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
| <kbd>Tab</kbd> / <kbd>Shift</kbd>+<kbd>Tab</kbd> | next / previous section: Alles / Videos / Podcasts |
| <kbd>1</kbd> <kbd>2</kbd> <kbd>3</kbd> | go straight to Alles / Videos / Podcasts |
| <kbd>↑</kbd> <kbd>↓</kbd> or <kbd>k</kbd> <kbd>j</kbd> | navigate |
| <kbd>PgUp</kbd> <kbd>PgDn</kbd> <kbd>Home</kbd> <kbd>End</kbd> | page / jump |
| <kbd>Enter</kbd> or <kbd>→</kbd> | open feed / play video now |
| <kbd>p</kbd> | **add to the playlist** (at the end) — like "add to queue" |
| <kbd>n</kbd> | **play next** — insert right after the current video |
| <kbd>i</kbd> | show the **playlist**, numbered |
| <kbd>Esc</kbd> <kbd>←</kbd> <kbd>Backspace</kbd> | back (videos → feeds → close) |
| <kbd>q</kbd> | close the browser — **does not quit mpv** |
| <kbd>r</kbd> | refresh (the selected feed, or all from the feed list) |
| <kbd>R</kbd> | refresh everything |
| <kbd>m</kbd> | toggle seen / unseen |
| <kbd>v</kbd> | hide / show watched items |
| <kbd>a</kbd> | add the feed URL on the clipboard |
| <kbd>d</kbd> then <kbd>y</kbd> | remove the selected feed |
| <kbd>/</kbd> | filter the current list |
| <kbd>e</kbd> | show the full error of a failed feed |
| <kbd>?</kbd> | keyboard shortcuts, on screen |

<kbd>?</kbd> shows all of this inside mpv, grouped by Navigate / Play / Feeds /
Other, so you never need this table while using it.

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

> **The family name matters.** Windows registers JetBrains Mono Nerd Font as
> **`JetBrainsMono NF`**, *not* "JetBrainsMono Nerd Font". Setting the latter
> renders every icon as an empty box. Leave `font=` empty and the script finds
> an installed Nerd Font by itself.

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

<kbd>Alt</kbd>+<kbd>A</kbd> opens `rss-feeds.json` in **nvim inside Windows
Terminal** (falling back to a plain console window if `wt.exe` is missing; set
`editor=` to use something else, e.g. `code` or `notepad`).

You do not have to close the editor afterwards: the file is watched, and the
moment you `:w` the browser reloads the list, reports *"rss-feeds.json
reloaded"* and fetches anything new. A hand edit **replaces** the list, so
renames and deletions you make in the file win — unlike <kbd>a</kbd>, which
merges.

### By editing the file

`%APPDATA%\mpv\rss-feeds.json`:

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

## 6. Playing, refreshing, removing

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

## 7. Files it writes

All inside your mpv config folder; nothing is ever written to the mpv
installation directory.

| File | Contents |
|---|---|
| `%APPDATA%\mpv\rss-feeds.json` | your subscriptions |
| `%APPDATA%\mpv\rss-cache.json` | downloaded entries, so navigation needs no network |
| `%APPDATA%\mpv\rss-state.json` | watch state and resume positions, by video ID |

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
are not resurrected by the merge.

---

## 8. Configuration

`%APPDATA%\mpv\script-opts\rss.conf`, one `key=value` per line. The shipped
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
feeds_file=              # empty = <mpv config dir>\rss-feeds.json
cache_file=
state_file=
```

**To see more videos at once**, lower `font_size` — every row is already a
single line, and the panel always fits itself to the window, so `visible_rows`
alone cannot push more items on screen than physically fit.

Options also work on the command line:

```powershell
mpv --script-opts=rss-font_size=12,rss-date_format=relative
```

---

## 9. Troubleshooting

**Nothing happens when I run `mpv.exe`** — mpv with no file exits immediately.
Use `mpv-rss.cmd`, or add `idle=yes` and `force-window=immediate` to
`mpv.conf` ([§3](#3-starting-it)).

**<kbd>Ctrl</kbd>+<kbd>R</kbd> does nothing** — check the script actually
loaded:

```powershell
mpv --msg-level=rss=debug --idle=yes --force-window=immediate
```

You should see `Loading lua script …\rss.lua` and `rss ready (feeds=… cache=…
state=…)`. If another script already uses `ctrl+r`, change `key_open`.

**A feed shows a red error line** — the message is curl's or PowerShell's,
shown next to the feed name, e.g. `curl: (22) … error: 404` for a wrong URL or
`Could not connect` for a dead host. Other feeds keep loading regardless. The
browser never takes mpv down over a bad feed.

**`RSS: Invalid XML`** — the URL returned something that is not a feed, usually
an HTML error page. Open the URL in a browser to check.

**`RSS: yt-dlp not available`** — install it (§2.5) and make sure `yt-dlp
--version` works in the same shell you start mpv from.

**A video does not play** — try the URL directly:

```powershell
mpv "https://www.youtube.com/watch?v=VIDEOID"
```

If that fails too, it is mpv/yt-dlp, not this script. `yt-dlp -U` fixes most
YouTube breakage.

**Inspect what the parser sees from a feed:**

```powershell
mpv --idle=yes --msg-level=rss=debug --script-opts=rss-debug_parse=https://www.youtube.com/feeds/videos.xml?channel_id=UC...
```

It prints the entry count and the first five entries with their id, date, title
and URL. A local file path works too.

**Force the other HTTP backend** (if curl is blocked by policy, say):

```powershell
mpv --script-opts=rss-http_backend=powershell
```

**Start over** — delete `rss-cache.json` and `rss-state.json` from
`%APPDATA%\mpv`. They are rebuilt on the next refresh.

---

## 10. Notes on behaviour

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
