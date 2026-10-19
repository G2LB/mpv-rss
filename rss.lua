-- rss.lua -- RSS/Atom + YouTube subscription browser inside mpv's own OSD.
--
-- Install:  %APPDATA%\mpv\scripts\rss.lua
-- Options:  %APPDATA%\mpv\script-opts\rss.conf   (see README.md)
-- Data:     %APPDATA%\mpv\rss-feeds.json / rss-state.json / rss-cache.json
--
-- Dependencies: none beyond mpv itself. HTTP goes through curl.exe (shipped with
-- Windows 10 1803+) with a PowerShell fallback; YouTube playback is handled by
-- mpv's built-in ytdl_hook + yt-dlp.
--
-- Default key: ctrl+r opens the browser.

local mp      = require("mp")
local msg     = require("mp.msg")
local utils   = require("mp.utils")
local options = require("mp.options")

--==========================================================================
-- 1. CONFIGURATION
--==========================================================================

local opts = {
    -- key that opens/closes the browser (any mpv key name, e.g. ctrl+r, F9, i)
    key_open = "ctrl+r",
    -- open the browser automatically when mpv starts idle (used by mpv-rss.cmd)
    auto_open = false,

    -- In-menu keys. These are bound only while the browser is open and removed
    -- when it closes, so they never permanently override an mpv default.
    key_queue     = "p",  -- add to the end of the playlist  (mpv default: pause)
    key_play_next = "n",  -- insert as the next item         (mpv default: none)
    key_index     = "i",  -- show the playlist               (mpv default: stats)
    key_edit      = "alt+a", -- open rss-feeds.json in an editor

    -- Command used by key_edit. "auto" opens nvim in Windows Terminal and falls
    -- back to a plain console window. Give a full command to override, e.g.
    --   editor=code
    editor = "auto",

    -- refresh
    refresh_interval     = 1800, -- seconds; feeds older than this refresh on open
    refresh_on_open      = true, -- refresh stale feeds when the browser opens
    max_entries_per_feed = 50,
    max_total_entries    = 300,  -- cap for the merged "All Videos" list
    max_parallel          = 4,   -- concurrent feed downloads

    -- Leave YouTube Shorts out. A channel feed mixes Shorts in with real
    -- uploads and only ever holds 15 items, so a channel that posts clips can
    -- push every actual video out of it. With this on, channel feeds are
    -- fetched through the channel's long-form uploads playlist instead, which
    -- YouTube builds without Shorts, and anything that still looks like a
    -- Short (a /shorts/ link, a #shorts title) is dropped.
    skip_shorts = true,

    -- Fetch a YouTube channel's live streams as well. Only matters with
    -- skip_shorts on: the Shorts-free playlist that enables leaves streams
    -- out, so without this a channel that mostly streams looks empty. Costs
    -- one extra request per channel feed.
    include_live = true,

    -- UI
    -- visible_rows is an upper bound: the panel never draws more items than
    -- actually fit in the window, so lowering font_size shows more of them.
    visible_rows  = 20,     -- items per page (15-30 is sensible)
    ui_width      = 0.86,   -- fraction of the window width
    osd_height    = 720,    -- virtual ASS canvas height; higher = smaller text
    font_size     = 18,     -- body text, in canvas units; everything else
                            -- (heading, icons, metadata, hints) scales from it
    font          = "",     -- empty = auto-detect a Nerd Font, else mpv's OSD font
    icons         = "auto", -- auto | nerd | ascii
    osc_reserve   = 0.10,   -- fraction of height kept clear for mpv's OSC

    -- brief title card, top-left, when a feed item starts playing
    title_overlay         = true,
    title_overlay_seconds = 2.5,

    -- While the browser is open, hold the last frame when a video ends instead
    -- of unloading it, so the picture does not drop out from under you while
    -- you are still browsing. Your own keep-open setting is restored on close.
    keep_open_in_menu = true,

    -- Write playback progress to disk every so many seconds while something is
    -- playing, so a crash or a kill costs at most this much. 0 disables it;
    -- progress is still written when a file ends and when mpv shuts down.
    autosave_interval = 60,
    unread_marker  = "●",   -- never played
    partial_marker = "◐",   -- started but not finished
    seen_marker    = "✓",   -- watched to the end
    show_index     = false, -- number the rows (toggle in the menu with i)
    -- The permanent key-hint bar at the bottom. Off by default: "?" shows the
    -- full list on demand, so the row is mostly wasted space. Filter input,
    -- the delete confirmation and status messages still appear there.
    footer_hints   = false,
    -- Size of the list rows, as a fraction of font_size. The header card
    -- carries the detail, so a row is one line and can afford to be bigger
    -- than the rest of the interface.
    list_size      = 1.2,
    -- How a date is written in the list and in the header card.
    --   short    "Aug 06"             -- fixed width, so the titles line up
    --   relative "3 days ago"
    --   absolute "2026-09-29 14:03"
    date_format    = "short",
    -- Superseded by date_format; still honoured when that is left at "short",
    -- so an older rss.conf saying relative_dates=no still gets absolute dates.
    relative_dates = true,
    -- One truncated description line in the header card (not on every row).
    show_descriptions = false,

    -- Small-window layout. Every size in this script is in virtual canvas
    -- units, so a quarter-screen window does not get a cramped panel -- it
    -- gets the same panel in miniature, which is worse: three tab columns and
    -- an artwork column leave the titles a couple of hundred real pixels.
    -- Below the thresholds the browser shows one section at a time instead
    -- ("2/3  VIDEOS", cycled with Tab or picked with 1-3), drops the artwork
    -- column, puts each item on one line and enlarges the text.
    narrow_layout = "auto", -- auto | always | never
    narrow_width  = 960,    -- window width in px at or below which it kicks in (0 = off)
    narrow_ratio  = 0.6,    -- ...or this fraction of the display width (0 = off)
    narrow_scale  = 1.2,    -- how much larger the text is in that layout

    -- Some servers refuse a TLS handshake with mpv's bundled ffmpeg even though
    -- curl connects fine. When direct playback of a podcast enclosure fails for
    -- that reason, fetch the file once and play it locally instead.
    download_fallback = true,

    -- watched / partially-watched tracking
    -- Playback progress decides the three states. Set mark_watched_on_play=yes
    -- for the old behaviour, where pressing Enter marks an item seen at once.
    mark_watched_on_play = false,
    -- Start with finished items hidden; v toggles it per session.
    hide_watched         = true,
    watched_threshold    = 0.9, -- fraction of the duration that counts as seen
    min_progress_seconds = 15,  -- shorter than this does not count as started

    -- thumbnails / podcast artwork (needs ffmpeg on PATH; silently off without it)
    thumbnails     = true,
    -- Shape of the preview, width / height. 1.78 is 16:9, which a YouTube
    -- thumbnail fills exactly; squarer artwork is cropped to fill it.
    -- There is no size setting: the preview is exactly as tall as the header
    -- band, so that it sits on the rule that closes it. To make it bigger,
    -- raise font_size -- a taller card gives a taller band.
    thumbnail_aspect = 1.78,

    -- http
    http_backend = "auto",  -- auto | curl | powershell
    http_timeout = 20,      -- seconds per feed

    -- paths (empty = <mpv config dir>/rss-*.json)
    feeds_file = "",
    cache_file = "",
    state_file = "",

    -- troubleshooting: parse this file/URL at startup and log the result
    debug_parse = "",
}
options.read_options(opts, "rss")

local SCRIPT_NAME = "rss"
local UA = "mpv-rss/1.0"

--==========================================================================
-- 2. SMALL UTILITIES
--==========================================================================

local function trim(s)
    if type(s) ~= "string" then return s end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

-- Escape a literal string for use inside a Lua pattern.
local function escape_pat(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- 32-bit FNV-1a, only used as a last-resort stable id for entries that carry
-- neither a guid nor a link. Written without the bitwise operators of Lua 5.3,
-- because mpv may be built against LuaJIT / Lua 5.1.
local function fnv1a(s)
    local hash = 2166136261
    for i = 1, #s do
        -- xor of the low byte only, by hand
        local x, b, r, bit = hash, s:byte(i), 0, 1
        for _ = 1, 8 do
            local hb, bb = x % 2, b % 2
            if hb ~= bb then r = r + bit end
            x = (x - hb) / 2
            b = (b - bb) / 2
            bit = bit * 2
        end
        hash = (math.floor(x) * 256 + r) * 16777619 % 4294967296
    end
    return string.format("%08.0f", hash)
end

-- Count of UTF-8 characters (bytes that are not continuation bytes).
local function utf8_len(s)
    local n = 0
    for _ in s:gmatch("[^\128-\191]") do n = n + 1 end
    return n
end

-- Truncate to n UTF-8 characters without cutting a multi-byte sequence.
local function utf8_truncate(s, n)
    if type(s) ~= "string" then s = tostring(s) end
    n = math.max(4, math.floor(n or 4))
    if utf8_len(s) <= n then return s end
    local count, idx = 0, 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 128 or b >= 192 then -- start of a character
            count = count + 1
            if count > n - 1 then
                idx = i - 1
                break
            end
        end
    end
    if idx <= 0 then idx = n end
    return s:sub(1, idx) .. "…"
end

local function file_read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

-- Write via a temp file and rename. On Windows os.rename() fails if the target
-- exists, so the target is removed first; a direct write is the fallback.
local function file_write(path, data)
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "wb")
    if not f then return false, tostring(err) end
    local ok, werr = pcall(function() f:write(data) end)
    f:close()
    if not ok then return false, tostring(werr) end
    os.remove(path)
    if os.rename(tmp, path) then return true end
    local g = io.open(path, "wb")
    if not g then return false, "rename and direct write both failed" end
    g:write(data)
    g:close()
    os.remove(tmp)
    return true
end

local function config_path(name)
    local dir = mp.command_native({ "expand-path", "~~/" })
    if type(dir) ~= "string" or dir == "" then dir = "." end
    return utils.join_path(dir, name)
end

local function resolve_path(configured, default_name)
    if configured and configured ~= "" then
        local p = mp.command_native({ "expand-path", configured })
        if type(p) == "string" and p ~= "" then return p end
        return configured
    end
    return config_path(default_name)
end

local PATHS = {
    feeds = resolve_path(opts.feeds_file, "rss-feeds.json"),
    cache = resolve_path(opts.cache_file, "rss-cache.json"),
    state = resolve_path(opts.state_file, "rss-state.json"),
}

local function read_json(path, fallback)
    local data = file_read(path)
    if not data or trim(data) == "" then return fallback end
    -- Editors on Windows (Notepad, PowerShell's Set-Content -Encoding utf8)
    -- happily add a UTF-8 BOM, which the JSON parser rejects.
    data = data:gsub("^\239\187\191", "")
    local parsed = utils.parse_json(data)
    if type(parsed) ~= "table" then
        msg.warn("could not parse JSON: " .. path)
        return fallback
    end
    return parsed
end

local function write_json(path, tbl)
    local data = utils.format_json(tbl)
    if type(data) ~= "string" then return false, "could not serialise JSON" end
    return file_write(path, data)
end

local function temp_path(suffix)
    local dir = os.getenv("TEMP") or os.getenv("TMP") or "."
    local name = string.format("mpv-rss-%d-%d%s",
        os.time(), math.random(100000, 999999), suffix)
    return utils.join_path(dir, name)
end

-- Only http/https, no whitespace or control characters. Everything that is
-- handed to a subprocess or to loadfile goes through this first.
local function is_valid_url(url)
    if type(url) ~= "string" then return false end
    if #url < 10 or #url > 2000 then return false end
    if not url:match("^https?://[^%s]+$") then return false end
    if url:find("[%c]") then return false end
    return true
end

local function is_youtube_url(url)
    return url:find("youtube%.com") ~= nil or url:find("youtu%.be") ~= nil
end

-- A YouTube channel feed (?channel_id=UC...) lists Shorts alongside real
-- uploads. YouTube also auto-builds a per-channel "long-form videos" playlist
-- -- the channel id with UC swapped for UULF -- and its feed holds the same
-- uploads with the Shorts left out. Map a channel (or plain uploads, UU...)
-- feed URL onto that playlist; return nil for anything else.
-- Shared by the two rewrites below. tag is the auto-playlist prefix YouTube
-- builds per channel: UULF long-form, UULV live, UUSH Shorts, UUPS podcasts.
local function channel_playlist_url(url, tag)
    if type(url) ~= "string" or not url:find("/feeds/videos%.xml") then return nil end
    local cid = url:match("[%?&]channel_id=UC([%w_%-]+)")
    if not cid then
        -- The plain uploads playlist (UU + the 22-character channel id) is the
        -- channel feed under another name, so redirect that too. The tagged
        -- playlists carry two extra characters and are left exactly as the
        -- user asked for them.
        local pl = url:match("[%?&]playlist_id=UU([%w_%-]+)")
        if pl and #pl <= 22 then cid = pl end
    end
    if not cid then return nil end
    return "https://www.youtube.com/feeds/videos.xml?playlist_id=" .. tag .. cid
end

local function longform_feed_url(url)
    return channel_playlist_url(url, "UULF")
end

-- The long-form playlist holds no streams at all, so on its own it hides
-- everything a channel that mostly goes live has posted. Streams -- live now
-- and finished alike -- sit in their own playlist, fetched alongside it.
local function live_feed_url(url)
    return channel_playlist_url(url, "UULV")
end

-- Backstop for Shorts that arrive through a feed we cannot redirect (a
-- playlist feed, or a channel with no long-form playlist). The feed XML has
-- no Shorts flag, so this goes on the two marks that do show up: the player
-- URL and the hashtag creators put in the title.
local function looks_like_short(e)
    local url = e.url or ""
    if url:find("/shorts/", 1, true) then return true end
    if not is_youtube_url(url) then return false end
    -- the hashtag has to stand on its own: #shortstory is not a Short
    for tag in (e.title or ""):lower():gmatch("#(%a+)") do
        if tag == "short" or tag == "shorts" then return true end
    end
    return false
end

--==========================================================================
-- 3. HTTP FETCHING
--==========================================================================
-- mpv has no Lua HTTP API, so feeds are downloaded with a subprocess.
--
-- IMPORTANT: subprocess defaults to playback_only=true, which aborts the child
-- process whenever playback is not active -- i.e. exactly the idle state this
-- browser normally runs in. Every call below must pass playback_only=false.

local http_backend = nil        -- "curl" | "powershell", resolved once
local http_pending = {}         -- requests queued until the probe finishes

local function run_async(args, cb)
    mp.command_native_async({
        name = "subprocess",
        args = args,
        playback_only = false,  -- see note above
        capture_stdout = true,
        capture_stderr = true,
    }, cb)
end

local function first_line(s)
    if type(s) ~= "string" then return nil end
    local line = trim(s:gsub("\r", ""):match("^[^\n]*") or "")
    if line == "" then return nil end
    return line
end

-- media: a podcast episode rather than a feed or an image. http_timeout is a
-- budget for a few kilobytes of XML; an episode is tens of megabytes, so an
-- overall deadline just kills the transfer partway on any connection slower
-- than the guess. Cap the handshake instead, and give up only once the
-- transfer has actually stalled.
local function curl_args(url, outfile, media)
    local args = { "curl.exe", "-sS", "-L", "--fail" }
    local function add(...) for _, a in ipairs({ ... }) do args[#args + 1] = a end end
    if media then
        add("--connect-timeout", "30", "--speed-time", "30", "--speed-limit", "1024")
    else
        add("--max-time", tostring(math.floor(opts.http_timeout)))
    end
    add("-A", UA, "-o", outfile, "--", url)
    return args
end

-- The URL is written to a file we control and read back inside the command, so
-- untrusted feed/clipboard text never becomes part of a command line.
local function powershell_args(url, outfile, urlfile, media)
    local function q(p) return "'" .. p:gsub("'", "''") .. "'" end
    local script = table.concat({
        "$ErrorActionPreference='Stop';",
        "try { [Net.ServicePointManager]::SecurityProtocol =",
        "[Net.SecurityProtocolType]::Tls12 } catch {};",
        "$u = (Get-Content -Raw -LiteralPath " .. q(urlfile) .. ").Trim();",
        "Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile " .. q(outfile),
        -- see curl_args: an episode needs far longer than a feed
        "-TimeoutSec " .. tostring(media and 3600 or math.floor(opts.http_timeout)),
        "-UserAgent " .. q(UA) .. ";",
    }, " ")
    return {
        "powershell.exe", "-NoProfile", "-NonInteractive",
        "-ExecutionPolicy", "Bypass", "-Command", script,
    }
end

-- download(url, outfile, cb, media) -> cb(ok, errmsg); the file is left on
-- disk. Set media for a podcast episode, so it is not held to the per-feed
-- timeout -- see curl_args.
local function download(url, outfile, cb, media)
    if not is_valid_url(url) then
        cb(false, "invalid URL")
        return
    end
    if http_backend == nil then
        http_pending[#http_pending + 1] =
            { url = url, outfile = outfile, cb = cb, media = media }
        return
    end
    local urlfile = nil
    local args
    if http_backend == "curl" then
        args = curl_args(url, outfile, media)
    else
        urlfile = temp_path(".url")
        local ok, err = file_write(urlfile, url)
        if not ok then cb(false, "could not write temp file: " .. tostring(err)) return end
        args = powershell_args(url, outfile, urlfile, media)
    end
    run_async(args, function(success, res, err)
        if urlfile then os.remove(urlfile) end
        if not success then
            cb(false, "could not run " .. http_backend .. ": " .. tostring(err))
            return
        end
        local status = res and res.status or -1
        if status ~= 0 then
            cb(false, first_line(res and res.stderr) or ("exit code " .. tostring(status)))
            return
        end
        cb(true, nil)
    end)
end

-- fetch(url, cb) -> cb(body_or_nil, errmsg)
local function fetch(url, cb)
    if not is_valid_url(url) then
        cb(nil, "invalid URL")
        return
    end
    if http_backend == nil then
        http_pending[#http_pending + 1] = { url = url, cb = cb }
        return
    end

    local outfile = temp_path(".xml")
    local urlfile = nil
    local args
    if http_backend == "curl" then
        args = curl_args(url, outfile)
    else
        urlfile = temp_path(".url")
        local ok, err = file_write(urlfile, url)
        if not ok then cb(nil, "could not write temp file: " .. tostring(err)) return end
        args = powershell_args(url, outfile, urlfile)
    end

    run_async(args, function(success, res, err)
        local body = file_read(outfile)
        os.remove(outfile)
        if urlfile then os.remove(urlfile) end

        if not success then
            cb(nil, "could not run " .. http_backend .. ": " .. tostring(err))
            return
        end
        local status = res and res.status or -1
        if status ~= 0 then
            local detail = first_line(res and res.stderr) or ("exit code " .. tostring(status))
            cb(nil, detail)
            return
        end
        if not body or #body == 0 then
            cb(nil, "empty response")
            return
        end
        cb(body, nil)
    end)
end

local function probe_http_backend()
    local function settle(which)
        http_backend = which
        msg.verbose("http backend: " .. which)
        local queued = http_pending
        http_pending = {}
        for _, req in ipairs(queued) do
            if req.outfile then download(req.url, req.outfile, req.cb, req.media)
            else fetch(req.url, req.cb) end
        end
    end

    if opts.http_backend == "curl" or opts.http_backend == "powershell" then
        settle(opts.http_backend)
        return
    end
    run_async({ "curl.exe", "--version" }, function(success, res)
        if success and res and res.status == 0 then settle("curl") else settle("powershell") end
    end)
end

--==========================================================================
-- 4. XML PARSING  (deliberately minimal: entities, CDATA, the tags we need)
--==========================================================================

local NAMED_ENTITIES = {
    lt = "<", gt = ">", quot = '"', apos = "'", amp = "&",
    nbsp = " ", ndash = "–", mdash = "—", hellip = "…",
    rsquo = "’", lsquo = "‘", ldquo = "“", rdquo = "”",
    eacute = "é", egrave = "è", uuml = "ü", ouml = "ö", auml = "ä", szlig = "ß",
}

local function utf8_char(cp)
    if type(cp) ~= "number" or cp < 0 or cp > 0x10FFFF then return "" end
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
                           0x80 + math.floor(cp / 0x40) % 0x40,
                           0x80 + cp % 0x40)
    end
    return string.char(0xF0 + math.floor(cp / 0x40000),
                       0x80 + math.floor(cp / 0x1000) % 0x40,
                       0x80 + math.floor(cp / 0x40) % 0x40,
                       0x80 + cp % 0x40)
end

-- Single pass, so "&amp;lt;" correctly decodes to "&lt;" and not to "<".
local function unescape(s)
    if not s or s == "" then return s end
    if not s:find("&", 1, true) then return s end
    s = s:gsub("&#[xX](%x+);", function(h) return utf8_char(tonumber(h, 16)) end)
    s = s:gsub("&#(%d+);", function(d) return utf8_char(tonumber(d, 10)) end)
    s = s:gsub("&(%a+);", function(name)
        return NAMED_ENTITIES[name:lower()] -- returning nil keeps the original
    end)
    return s
end

-- CDATA content is literal; only the surrounding text gets entity decoding.
local function decode_text(raw)
    if not raw then return nil end
    if not raw:find("<![CDATA[", 1, true) then return unescape(raw) end
    local out, pos = {}, 1
    while true do
        local s, e = raw:find("<![CDATA[", pos, true)
        if not s then
            out[#out + 1] = unescape(raw:sub(pos))
            break
        end
        out[#out + 1] = unescape(raw:sub(pos, s - 1))
        local ce, cee = raw:find("]]>", e + 1, true)
        if not ce then
            out[#out + 1] = raw:sub(e + 1)
            break
        end
        out[#out + 1] = raw:sub(e + 1, ce - 1)
        pos = cee + 1
    end
    return table.concat(out)
end

-- Return the raw inner XML of <name ...>...</name>, or "" for a self-closing
-- tag, or nil when absent.
--
-- The character after the tag name is checked explicitly, so a request for
-- "title" cannot match "<media:title>" -- YouTube entries contain both, and a
-- naive pattern picks the wrong one.
local function tag_raw(block, name)
    local n = escape_pat(name)
    local init = 1
    while true do
        local s, e = block:find("<" .. n, init)
        if not s then return nil end
        local nextch = block:sub(e + 1, e + 1)
        if nextch == ">" or nextch == "/" or nextch == " " or nextch == "\t"
            or nextch == "\n" or nextch == "\r" then
            local close = block:find(">", e, true)
            if not close then return nil end
            if block:sub(close - 1, close - 1) == "/" then return "" end
            local ts = block:find("</" .. n .. "%s*>", close + 1)
            if not ts then return nil end
            return block:sub(close + 1, ts - 1)
        end
        init = e + 1
    end
end

local function tag_text(block, name)
    local raw = tag_raw(block, name)
    if not raw or raw == "" then return nil end
    local t = trim(decode_text(raw))
    if t == "" then return nil end
    return t
end

-- Value of an attribute on the first matching opening tag.
local function tag_attr(block, name, attr)
    local n = escape_pat(name)
    local open = block:match("<" .. n .. "[%s][^>]*>")
    if not open then return nil end
    local v = open:match(escape_pat(attr) .. '%s*=%s*"([^"]*)"')
        or open:match(escape_pat(attr) .. "%s*=%s*'([^']*)'")
    if not v then return nil end
    return trim(decode_text(v))
end

-- Atom: prefer <link rel="alternate" href="...">, else the first href.
local function atom_link(block)
    local fallback
    for tag in block:gmatch("<link[%s][^>]*>") do
        local href = tag:match('href%s*=%s*"([^"]*)"') or tag:match("href%s*=%s*'([^']*)'")
        if href then
            href = trim(decode_text(href))
            local rel = tag:match('rel%s*=%s*"([^"]*)"') or tag:match("rel%s*=%s*'([^']*)'")
            if rel == nil or rel == "alternate" then return href end
            fallback = fallback or href
        end
    end
    return fallback
end

local function strip_html(s)
    if not s then return nil end
    s = s:gsub("<br%s*/?>", " "):gsub("</p>", " ")
    s = s:gsub("<[^>]->", "")
    s = unescape(s)
    s = s:gsub("%s+", " ")
    return trim(s)
end

--==========================================================================
-- 5. DATES
--==========================================================================

local MONTHS = {
    jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6,
    jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12,
}
local NAMED_ZONES = {
    gmt = 0, ut = 0, utc = 0, z = 0,
    est = -5 * 3600, edt = -4 * 3600, cst = -6 * 3600, cdt = -5 * 3600,
    mst = -7 * 3600, mdt = -6 * 3600, pst = -8 * 3600, pdt = -7 * 3600,
    cet = 1 * 3600, cest = 2 * 3600,
}

-- Seconds the local zone is ahead of UTC. Computed once for "now", so a feed
-- date in the other half of the DST year can be an hour off -- irrelevant for
-- sorting and for "3 days ago" output.
local LOCAL_OFFSET = (function()
    local now = os.time()
    local utc = os.date("!*t", now)
    utc.isdst = false
    local as_local = os.time(utc)
    if not as_local then return 0 end
    return os.difftime(now, as_local)
end)()

-- Interpret a broken-down time as UTC and return the epoch.
local function utc_to_epoch(t)
    t.isdst = false
    local e = os.time(t)
    if not e then return nil end
    return e + LOCAL_OFFSET
end

-- "00:54:11", "54:11" or plain seconds (itunes:duration)
local function parse_duration(s)
    if type(s) ~= "string" then return nil end
    s = trim(s)
    local h, m, sec = s:match("^(%d+):(%d+):(%d+)$")
    if h then return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec) end
    local m2, s2 = s:match("^(%d+):(%d+)$")
    if m2 then return tonumber(m2) * 60 + tonumber(s2) end
    local n = tonumber(s)
    if n and n > 0 then return math.floor(n) end
    return nil
end

local function parse_date(s)
    if type(s) ~= "string" then return nil end
    s = trim(s)
    if s == "" then return nil end

    -- ISO 8601 / RFC 3339 (Atom <published>, <updated>)
    local Y, M, D, h, mi, sec = s:match("^(%d%d%d%d)-(%d%d)-(%d%d)[Tt ](%d%d):(%d%d):?(%d*)")
    if Y then
        local e = utc_to_epoch({
            year = tonumber(Y), month = tonumber(M), day = tonumber(D),
            hour = tonumber(h), min = tonumber(mi), sec = tonumber(sec) or 0,
        })
        if not e then return nil end
        local sign, oh, om = s:match("([%+%-])(%d%d):?(%d%d)%s*$")
        if sign then
            local off = tonumber(oh) * 3600 + tonumber(om) * 60
            if sign == "+" then e = e - off else e = e + off end
        end
        return e
    end

    -- RFC 822 / RFC 2822 (RSS <pubDate>): Wed, 01 Oct 2026 16:59:42 GMT
    local D2, Mon, Y2, h2, mi2, s2 = s:match("(%d%d?)%s+(%a%a%a)%a*%s+(%d%d%d%d)%s+(%d%d):(%d%d):?(%d*)")
    if D2 then
        local mon = MONTHS[Mon:lower()]
        if mon then
            local e = utc_to_epoch({
                year = tonumber(Y2), month = mon, day = tonumber(D2),
                hour = tonumber(h2), min = tonumber(mi2), sec = tonumber(s2) or 0,
            })
            if not e then return nil end
            local sign, oh, om = s:match("([%+%-])(%d%d)(%d%d)%s*$")
            if sign then
                local off = tonumber(oh) * 3600 + tonumber(om) * 60
                if sign == "+" then e = e - off else e = e + off end
            else
                local zone = s:match("(%a+)%s*$")
                local zoff = zone and NAMED_ZONES[zone:lower()]
                if zoff then e = e - zoff end
            end
            return e
        end
    end

    -- bare date
    local Y3, M3, D3 = s:match("^(%d%d%d%d)-(%d%d)-(%d%d)")
    if Y3 then
        return utc_to_epoch({ year = tonumber(Y3), month = tonumber(M3), day = tonumber(D3),
                              hour = 12, min = 0, sec = 0 })
    end
    return nil
end

-- style: nil takes it from the options; "long" is the card's variant of
-- "short", which spells out a year that is not this one.
local function format_date(epoch, style)
    if not epoch or epoch <= 0 then return "unknown date" end
    style = style or opts.date_format
    -- relative_dates=no predates date_format and still means "spell it out"
    if opts.relative_dates == false and style ~= "relative" then style = "absolute" end
    if style == "short" or style == "long" then
        if style == "long" and os.date("%Y", epoch) ~= os.date("%Y") then
            return os.date("%b %d %Y", epoch)
        end
        return os.date("%b %d", epoch)
    end
    if style == "absolute" then
        return os.date("%Y-%m-%d %H:%M", epoch)
    end
    local d = os.difftime(os.time(), epoch)
    if d < 0 then return os.date("%Y-%m-%d %H:%M", epoch) end
    if d < 120 then return "just now" end
    if d < 3600 then return string.format("%d min ago", math.floor(d / 60)) end
    if d < 7200 then return "1 hour ago" end
    if d < 86400 then return string.format("%d hours ago", math.floor(d / 3600)) end
    if d < 172800 then return "yesterday" end
    if d < 604800 then return string.format("%d days ago", math.floor(d / 86400)) end
    if d < 2592000 then
        local w = math.floor(d / 604800)
        return w <= 1 and "1 week ago" or string.format("%d weeks ago", w)
    end
    return os.date("%Y-%m-%d", epoch)
end

--==========================================================================
-- 6. FEED NORMALISATION
--==========================================================================

local YT_ID_PAT = "^[%w_%-]+$"

local function valid_video_id(id)
    return type(id) == "string" and #id > 0 and #id <= 24 and id:match(YT_ID_PAT) ~= nil
end

local function parse_entry(block, kind, feed_author)
    local e = {}

    e.title = tag_text(block, "title") or "(untitled)"

    local vid = tag_text(block, "yt:videoId")
    if valid_video_id(vid) then e.video_id = vid end
    local cid = tag_text(block, "yt:channelId")
    if cid and cid:match(YT_ID_PAT) then e.channel_id = cid end

    -- author: <author><name>..</name></author> (Atom) / <dc:creator> / <author>
    local author_block = tag_raw(block, "author")
    local author = author_block and author_block ~= "" and tag_text(author_block, "name") or nil
    if not author then author = tag_text(block, "dc:creator") end
    if not author then
        local a = tag_text(block, "author")
        if a and not a:find("<", 1, true) then author = a end
    end
    e.author = author or feed_author

    -- podcast enclosure: for an episode this, not <link>, is what you play
    local enc = block:match("<enclosure[%s][^>]*>")
    if enc then
        local u = enc:match('url%s*=%s*"([^"]*)"') or enc:match("url%s*=%s*'([^']*)'")
        if u then
            u = trim(decode_text(u))
            if is_valid_url(u) then
                e.media_url = u
                e.media_type = enc:match('type%s*=%s*"([^"]*)"') or ""
            end
        end
    end

    -- url
    local link
    if kind == "atom" then
        link = atom_link(block)
    else
        link = tag_text(block, "link")
        if not link then
            local guid = tag_text(block, "guid")
            if guid and guid:match("^https?://") then link = guid end
        end
        if not link then link = atom_link(block) end
    end

    if e.video_id then
        e.url = "https://www.youtube.com/watch?v=" .. e.video_id
    elseif e.media_url and (e.media_type:find("^audio") or e.media_type:find("^video")
        or not link) then
        e.url = e.media_url      -- podcast episode
        e.page = link            -- the episode's web page, kept for reference
    else
        e.url = link
    end
    if e.url and not is_valid_url(e.url) then e.url = nil end

    -- podcast metadata
    e.duration = parse_duration(tag_text(block, "itunes:duration"))
    e.episode = tag_text(block, "itunes:episode")
    e.chapters = tag_attr(block, "podcast:chapters", "url") ~= nil or nil

    -- date
    e.date = parse_date(tag_text(block, "published"))
        or parse_date(tag_text(block, "pubDate"))
        or parse_date(tag_text(block, "updated"))
        or parse_date(tag_text(block, "dc:date"))
        or parse_date(tag_text(block, "date"))
        or 0

    -- description (truncated before it is ever cached)
    local desc = tag_text(block, "media:description")
        or tag_text(block, "description")
        or tag_text(block, "summary")
        or tag_text(block, "itunes:summary")
        or tag_text(block, "itunes:subtitle")
        or tag_text(block, "content:encoded")
        or tag_text(block, "content")
    desc = strip_html(desc)
    if desc and #desc > 300 then desc = utf8_truncate(desc, 300) end
    e.desc = desc

    -- per-item artwork: YouTube, iTunes podcasts, and the Podcasting 2.0 tags
    e.thumb = tag_attr(block, "media:thumbnail", "url")
        or tag_attr(block, "itunes:image", "href")
        or tag_attr(block, "podcast:artwork", "url")
    if not e.thumb then
        -- <podcast:images srcset="small.jpg 1x, big.jpg 2x">
        local srcset = tag_attr(block, "podcast:images", "srcset")
        if srcset then e.thumb = trim(srcset:match("^%s*([^%s,]+)") or "") end
    end
    if e.thumb and not is_valid_url(e.thumb) then e.thumb = nil end

    -- stable id
    if e.video_id then
        e.id = "yt:" .. e.video_id
    else
        e.id = tag_text(block, "guid")
            or (kind == "atom" and tag_text(block, "id"))
            or e.url
            or ("h:" .. fnv1a(e.title .. tostring(e.date)))
    end

    return e
end

-- parse_feed(xml) -> { title=, author=, entries={...} } | nil, errmsg
local function parse_feed(xml)
    if type(xml) ~= "string" or trim(xml) == "" then return nil, "empty response" end
    xml = xml:gsub("^\239\187\191", "")          -- UTF-8 BOM
    xml = xml:gsub("<!%-%-.-%-%->", "")          -- comments

    local kind, blocks = nil, {}
    for b in xml:gmatch("<item[%s>].-</item>") do blocks[#blocks + 1] = b end
    if #blocks > 0 then
        kind = "rss"
    else
        for b in xml:gmatch("<entry[%s>].-</entry>") do blocks[#blocks + 1] = b end
        if #blocks > 0 then kind = "atom" end
    end

    if not kind then
        local looks_like_feed = xml:find("<rss", 1, true) or xml:find("<feed", 1, true)
            or xml:find("<channel", 1, true)
        if looks_like_feed then return nil, "no entries found" end
        return nil, "invalid XML"
    end

    -- feed-level metadata lives before the first item/entry
    local first = xml:find("<item[%s>]") or xml:find("<entry[%s>]") or (#xml + 1)
    local head = xml:sub(1, first - 1)
    local feed_title = tag_text(head, "title")
    local head_author_block = tag_raw(head, "author")
    local feed_author = (head_author_block and head_author_block ~= ""
        and tag_text(head_author_block, "name")) or feed_title

    -- show artwork: <itunes:image href> or RSS <image><url>
    local feed_image = tag_attr(head, "itunes:image", "href")
    if not feed_image then
        local img = tag_raw(head, "image")
        if img and img ~= "" then feed_image = tag_text(img, "url") end
    end
    if feed_image and not is_valid_url(feed_image) then feed_image = nil end

    -- Podcasting 2.0: detect the tags themselves rather than the namespace URI,
    -- which differs between feeds (podcastindex.org/namespace/1.0 vs. the
    -- GitHub docs URL both occur in the wild).
    local podcast20 = xml:find("<podcast:") ~= nil

    local entries = {}
    for _, block in ipairs(blocks) do
        local ok, entry = pcall(parse_entry, block, kind, feed_author)
        if ok and entry and entry.url then
            entries[#entries + 1] = entry
        elseif not ok then
            msg.warn("entry parse failed: " .. tostring(entry))
        end
    end

    if #entries == 0 then return nil, "no entries found" end

    table.sort(entries, function(a, b) return (a.date or 0) > (b.date or 0) end)
    return {
        title = feed_title, author = feed_author, kind = kind,
        image = feed_image, podcast20 = podcast20, entries = entries,
    }
end

--==========================================================================
-- 7. PERSISTENCE: feeds / cache / watched state
--==========================================================================

local feeds = {}    -- { {name=, url=, enabled=}, ... }
local cache = {}    -- url -> { name=, title=, fetched_at=, entries={} }
local state = { watched = {}, last_refresh = 0 }
local feed_errors = {}  -- url -> last error string

local function load_feeds()
    local data = read_json(PATHS.feeds, nil)
    feeds = {}
    if type(data) == "table" and type(data.feeds) == "table" then
        for _, f in ipairs(data.feeds) do
            if type(f) == "table" and type(f.url) == "string" and is_valid_url(f.url) then
                feeds[#feeds + 1] = {
                    name = (type(f.name) == "string" and f.name ~= "") and f.name or f.url,
                    url = f.url,
                    enabled = f.enabled ~= false,
                }
            end
        end
    end
    if not data then
        -- create the file so the user has something to edit
        write_json(PATHS.feeds, { feeds = {} })
    end
end

-- Feeds removed in this session. Needed so a merge cannot resurrect them from
-- the copy still on disk.
local removed_urls = {}

-- Read the feeds file and adopt anything in it we do not already have: a feed
-- added by hand, or by another mpv instance, appears without a restart and
-- without touching the cache or the watch state. Returns how many were added.
local function reload_feeds()
    local data = read_json(PATHS.feeds, nil)
    if type(data) ~= "table" or type(data.feeds) ~= "table" then return 0 end
    local have = {}
    for _, f in ipairs(feeds) do have[f.url] = true end
    local added = 0
    for _, f in ipairs(data.feeds) do
        if type(f) == "table" and type(f.url) == "string" and is_valid_url(f.url)
            and not have[f.url] and not removed_urls[f.url] then
            feeds[#feeds + 1] = {
                name = (type(f.name) == "string" and f.name ~= "") and f.name or f.url,
                url = f.url,
                enabled = f.enabled ~= false,
            }
            have[f.url] = true
            added = added + 1
        end
    end
    return added
end

-- Writing merges with what is on disk first, so a feed added to the file while
-- mpv was running is never silently overwritten by our in-memory copy.
local function save_feeds()
    reload_feeds()
    local out = {}
    for _, f in ipairs(feeds) do
        if not removed_urls[f.url] then
            out[#out + 1] = { name = f.name, url = f.url, enabled = f.enabled ~= false }
        end
    end
    local ok, err = write_json(PATHS.feeds, { feeds = out })
    if not ok then msg.error("could not save feeds: " .. tostring(err)) end
    return ok
end

local function load_cache()
    local data = read_json(PATHS.cache, nil)
    cache = {}
    if type(data) == "table" and type(data.feeds) == "table" then
        for url, c in pairs(data.feeds) do
            if type(c) == "table" and type(c.entries) == "table" then
                cache[url] = {
                    name = c.name, title = c.title,
                    image = c.image, podcast20 = c.podcast20, kind = c.kind,
                    fetched_at = tonumber(c.fetched_at) or 0,
                    entries = c.entries,
                }
                -- drop Shorts cached before the option was turned on, so they
                -- are gone on this start rather than at the next refresh
                if opts.skip_shorts then
                    local kept = {}
                    for _, e in ipairs(c.entries) do
                        if type(e) == "table" and not looks_like_short(e) then
                            kept[#kept + 1] = e
                        end
                    end
                    cache[url].entries = kept
                end
            end
        end
    end
end

local function save_cache()
    local out = {}
    for url, c in pairs(cache) do
        local entries = {}
        for i = 1, math.min(#c.entries, math.floor(opts.max_entries_per_feed)) do
            entries[i] = c.entries[i]
        end
        out[url] = {
            name = c.name, title = c.title, image = c.image, kind = c.kind,
            podcast20 = c.podcast20, fetched_at = c.fetched_at, entries = entries,
        }
    end
    local ok, err = write_json(PATHS.cache, { version = 1, feeds = out })
    if not ok then msg.warn("could not save cache: " .. tostring(err)) end
end

local MAX_WATCHED = 5000

local function load_state()
    local data = read_json(PATHS.state, nil)
    state = { watched = {}, progress = {}, last_refresh = 0 }
    if type(data) == "table" then
        if type(data.watched) == "table" then
            for id, ts in pairs(data.watched) do
                if type(id) == "string" then state.watched[id] = tonumber(ts) or 1 end
            end
        end
        if type(data.progress) == "table" then
            for id, p in pairs(data.progress) do
                if type(id) == "string" and type(p) == "table" then
                    state.progress[id] = {
                        pos = tonumber(p.pos) or 0,
                        dur = tonumber(p.dur),
                        done = p.done == true,
                        ts = tonumber(p.ts) or 0,
                    }
                end
            end
        end
        state.last_refresh = tonumber(data.last_refresh) or 0
    end
end

local function save_state()
    -- keep the newest MAX_WATCHED ids so the file cannot grow without bound
    local list = {}
    for id, ts in pairs(state.watched) do list[#list + 1] = { id = id, ts = ts } end
    if #list > MAX_WATCHED then
        table.sort(list, function(a, b) return a.ts > b.ts end)
        local kept = {}
        for i = 1, MAX_WATCHED do kept[list[i].id] = list[i].ts end
        state.watched = kept
    end
    local plist = {}
    for id, p in pairs(state.progress) do plist[#plist + 1] = { id = id, ts = p.ts or 0 } end
    if #plist > MAX_WATCHED then
        table.sort(plist, function(a, b) return a.ts > b.ts end)
        local kept = {}
        for i = 1, MAX_WATCHED do kept[plist[i].id] = state.progress[plist[i].id] end
        state.progress = kept
    end
    local ok, err = write_json(PATHS.state, {
        version = 2,
        watched = state.watched,
        progress = state.progress,
        last_refresh = state.last_refresh,
    })
    if not ok then msg.warn("could not save state: " .. tostring(err)) end
end

-- Three display states: "unseen" / "partial" / "seen".
local function item_state(id)
    if not id then return "unseen" end
    local p = state.progress[id]
    if p then
        if p.done then return "seen" end
        if (p.pos or 0) >= opts.min_progress_seconds then return "partial" end
    end
    if state.watched[id] then return "seen" end
    return "unseen"
end

local function is_watched(id) return item_state(id) == "seen" end

-- Resume position in seconds, or nil.
local function resume_pos(id)
    local p = id and state.progress[id]
    if p and not p.done and (p.pos or 0) >= opts.min_progress_seconds then return p.pos end
    return nil
end

local function set_watched(id, watched)
    if not id then return end
    if watched then
        state.watched[id] = os.time()
        state.progress[id] = { pos = 0, dur = state.progress[id] and state.progress[id].dur,
                               done = true, ts = os.time() }
    else
        state.watched[id] = nil
        state.progress[id] = nil
    end
end

local function format_clock(sec)
    sec = math.floor(tonumber(sec) or 0)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

--==========================================================================
-- 8. ENTRY LISTS
--==========================================================================

local function feed_by_url(url)
    for _, f in ipairs(feeds) do if f.url == url then return f end end
    return nil
end

local function entries_for_feed(url)
    local c = cache[url]
    if not c then return {} end
    local out = {}
    for i, e in ipairs(c.entries) do
        if i > opts.max_entries_per_feed then break end
        e.feed_url = url          -- so artwork can fall back to the show image
        out[#out + 1] = e
    end
    return out
end

-- Artwork for an item: its own image, else the feed's show artwork.
local function artwork_url(e)
    if not e then return nil end
    if e.thumb then return e.thumb end
    local c = e.feed_url and cache[e.feed_url]
    return c and c.image or nil
end

-- "video" (YouTube or a video enclosure), "podcast" (audio enclosure or
-- Podcasting 2.0), or "other" (a plain blog feed, which shows only under Alles).
local function feed_kind(url)
    local c = cache[url]
    return (c and c.kind) or "other"
end

local function feed_in_tab(url, tab)
    if tab == "all" then return true end
    local k = feed_kind(url)
    return (tab == "videos" and k == "video") or (tab == "podcasts" and k == "podcast")
end

local function entries_for_tab(tab)
    local seen, out = {}, {}
    for _, f in ipairs(feeds) do
        if f.enabled ~= false and feed_in_tab(f.url, tab) then
            for _, e in ipairs(entries_for_feed(f.url)) do
                if e.id and not seen[e.id] then
                    seen[e.id] = true
                    out[#out + 1] = e
                end
            end
        end
    end
    table.sort(out, function(a, b) return (a.date or 0) > (b.date or 0) end)
    while #out > opts.max_total_entries do table.remove(out) end
    return out
end

local function entries_all() return entries_for_tab("all") end

-- Totals shown in the tab bar.
local function tab_counts()
    local c = { all = 0, videos = 0, podcasts = 0,
                afeeds = 0, vfeeds = 0, pfeeds = 0,
                new_all = 0, new_videos = 0, new_podcasts = 0 }
    for _, f in ipairs(feeds) do
        if f.enabled ~= false then
            local list = entries_for_feed(f.url)
            local n = #list
            -- "new" is strictly never played, not merely unfinished
            local fresh = 0
            for _, e in ipairs(list) do
                if item_state(e.id) == "unseen" then fresh = fresh + 1 end
            end
            local k = feed_kind(f.url)
            c.afeeds = c.afeeds + 1
            c.all = c.all + n
            c.new_all = c.new_all + fresh
            if k == "video" then
                c.vfeeds = c.vfeeds + 1
                c.videos = c.videos + n
                c.new_videos = c.new_videos + fresh
            elseif k == "podcast" then
                c.pfeeds = c.pfeeds + 1
                c.podcasts = c.podcasts + n
                c.new_podcasts = c.new_podcasts + fresh
            end
        end
    end
    return c
end

-- Find the feed entry a playing/queued URL came from, so the playlist view and
-- progress tracking can show real titles and watch state.
local function entry_by_url(url)
    if not url then return nil end
    for _, c in pairs(cache) do
        for _, e in ipairs(c.entries) do
            if e.url == url then return e end
        end
    end
    return nil
end

-- strictly never played, matching the "New n" counters in the tab bar
local function new_count(list)
    local n = 0
    for _, e in ipairs(list) do
        if item_state(e.id) == "unseen" then n = n + 1 end
    end
    return n
end

local function unread_count(list)
    local n = 0
    for _, e in ipairs(list) do if not is_watched(e.id) then n = n + 1 end end
    return n
end

--==========================================================================
-- 9. UI STATE
--==========================================================================

local ui = {
    active = false,
    tab = "all",            -- "all" | "videos" | "podcasts"
    narrow = false,         -- small-window layout; recomputed by layout()
    view = "feeds",         -- "feeds" | "entries" | "playlist"
    sel = 1,
    scroll = 0,
    feed_url = nil,         -- nil in entries view == All Videos
    feed_label = "",
    entries = {},           -- unfiltered list for the current view
    rows = {},              -- what is actually drawn (after filtering)
    filter = "",
    hide_seen = nil,        -- set from opts at init; v toggles it
    filter_editing = false, -- true while the one-line input is open
    input = { label = "", icon = nil, buf = "" },
    confirm_delete = nil,
    status = nil,
    status_until = 0,
}

local refresh_state = { active = false, total = 0, done = 0, queue = {}, inflight = 0 }

local overlay = mp.create_osd_overlay("ass-events")
local render                    -- forward declaration
local rebuild_rows              -- forward declaration

-- tone is a THEME colour name. Red is reserved for genuine errors; playback
-- actions are orange, queueing uses the same teal as a queued row.
local function status(text, seconds, tone)
    ui.status = text
    ui.status_tone = tone or "fg"
    ui.status_until = os.time() + (seconds or 5)
    if ui.active then render() else mp.osd_message(text, seconds or 4) end
end

--==========================================================================
-- 10. REFRESH
--==========================================================================

-- Decide from the entries themselves what sort of feed this is.
local function detect_kind(parsed)
    local audio, video = 0, 0
    for _, e in ipairs(parsed.entries) do
        if e.video_id then
            video = video + 1
        elseif type(e.media_type) == "string" then
            if e.media_type:find("^audio") then audio = audio + 1
            elseif e.media_type:find("^video") then video = video + 1 end
        end
    end
    if audio > video then return "podcast" end
    if video > 0 then return "video" end
    if parsed.podcast20 then return "podcast" end
    return "other"
end

local function store_feed_result(feed, parsed)
    local kept = parsed.entries
    if opts.skip_shorts then
        kept = {}
        for _, e in ipairs(parsed.entries) do
            if not looks_like_short(e) then kept[#kept + 1] = e end
        end
    end
    local entries = {}
    for i = 1, math.min(#kept, math.floor(opts.max_entries_per_feed)) do
        entries[i] = kept[i]
    end
    cache[feed.url] = {
        name = feed.name,
        title = parsed.title or feed.name,
        image = parsed.image,
        podcast20 = parsed.podcast20,
        kind = detect_kind(parsed),
        fetched_at = os.time(),
        entries = entries,
    }
    -- adopt the feed's own title the first time, when the user never named it
    if (feed.name == feed.url or feed.name == "" or feed.name == nil) and parsed.title then
        feed.name = parsed.title
        save_feeds()
    end
end

local pump_refresh   -- forward declaration

local function finish_refresh()
    refresh_state.active = false
    state.last_refresh = os.time()
    save_state()
    save_cache()
    if ui.active then rebuild_rows() render() end
end

-- A fetched body -> parsed feed, or nil plus the string to show as the feed's
-- error. Shared by the two attempts fetch_one can make.
local function parse_body(feed, body, err)
    if not body then return nil, err or "could not fetch feed" end
    local ok, parsed, perr = pcall(parse_feed, body)
    if not ok then
        msg.error("parse crashed for " .. feed.url .. ": " .. tostring(parsed))
        return nil, "parser error"
    end
    if not parsed then return nil, perr or "invalid XML" end
    return parsed
end

-- Fold a second playlist's entries into the first, newest first, dropping
-- anything already in there. Both lists arrive sorted; the join has to be
-- re-sorted because the two interleave by date.
local function merge_entries(into, extra)
    local seen = {}
    for _, e in ipairs(into.entries) do
        if e.id then seen[e.id] = true end
    end
    for _, e in ipairs(extra.entries) do
        if e.id and not seen[e.id] then
            seen[e.id] = true
            into.entries[#into.entries + 1] = e
        end
    end
    table.sort(into.entries, function(a, b) return (a.date or 0) > (b.date or 0) end)
end

local function fetch_one(feed)
    refresh_state.inflight = refresh_state.inflight + 1

    local function finish(parsed, err)
        refresh_state.inflight = refresh_state.inflight - 1
        refresh_state.done = refresh_state.done + 1
        if parsed then
            feed_errors[feed.url] = nil
            store_feed_result(feed, parsed)
        else
            feed_errors[feed.url] = err
            msg.warn(feed.name .. ": " .. tostring(err))
        end
        if ui.active then rebuild_rows() render() end
        pump_refresh()
    end

    local function fetch_as_listed()
        fetch(feed.url, function(body, err)
            finish(parse_body(feed, body, err))
        end)
    end

    -- Prefer the Shorts-free long-form playlist for YouTube channel feeds. The
    -- cache stays keyed by feed.url, so rss-feeds.json is untouched and turning
    -- skip_shorts off goes straight back to the feed as written.
    local alt = opts.skip_shorts and longform_feed_url(feed.url) or nil
    if not alt then
        fetch_as_listed()
        return
    end
    local live_url = opts.include_live and live_feed_url(feed.url) or nil

    fetch(alt, function(body, err)
        local parsed = parse_body(feed, body, err)
        if not parsed then
            -- no long-form playlist (a Shorts-only channel, or YouTube just
            -- refusing it): fall back to the feed as the user listed it
            msg.verbose("no long-form feed for " .. feed.url .. ", using it as listed")
            fetch_as_listed()
            return
        end
        -- the playlist feed is titled "Videos"; the channel name is the
        -- author, and that is what the channel feed would have given us
        parsed.title = parsed.author or parsed.title
        if not live_url then
            finish(parsed)
            return
        end
        -- A channel that has never streamed has an empty live playlist, and an
        -- empty feed parses as an error. That is not a failure here: there is
        -- simply nothing to add, so the long-form result stands on its own.
        fetch(live_url, function(lbody, lerr)
            local live = parse_body(feed, lbody, lerr)
            if live then
                merge_entries(parsed, live)
            else
                msg.verbose("no live streams for " .. feed.url)
            end
            finish(parsed)
        end)
    end)
end

pump_refresh = function()
    while refresh_state.inflight < math.max(1, math.floor(opts.max_parallel))
        and #refresh_state.queue > 0 do
        local feed = table.remove(refresh_state.queue, 1)
        fetch_one(feed)
    end
    if refresh_state.inflight == 0 and #refresh_state.queue == 0 and refresh_state.active then
        finish_refresh()
    end
end

local function refresh_feeds(list)
    if refresh_state.active then
        status("RSS: already refreshing")
        return
    end
    if #list == 0 then
        status("RSS: no feeds to refresh")
        return
    end
    refresh_state = { active = true, total = #list, done = 0, queue = {}, inflight = 0 }
    for _, f in ipairs(list) do refresh_state.queue[#refresh_state.queue + 1] = f end
    if ui.active then render() end
    pump_refresh()
end

local function enabled_feeds()
    local out = {}
    for _, f in ipairs(feeds) do if f.enabled ~= false then out[#out + 1] = f end end
    return out
end

local function refresh_all()
    -- pick up anything added to rss-feeds.json since we started
    local added = reload_feeds()
    if added > 0 then
        status(string.format("RSS: picked up %d new feed%s from rss-feeds.json",
            added, added == 1 and "" or "s"), 5, "green")
    end
    refresh_feeds(enabled_feeds())
end

local function refresh_stale()
    local now = os.time()
    local stale = {}
    for _, f in ipairs(enabled_feeds()) do
        local c = cache[f.url]
        if not c or (now - (c.fetched_at or 0)) > opts.refresh_interval then
            stale[#stale + 1] = f
        end
    end
    if #stale > 0 then refresh_feeds(stale) end
end

--==========================================================================
-- 11. OSD RENDERING
--==========================================================================

-- Escape text so untrusted titles cannot inject ASS override tags.
-- Same approach as mpv's own console.lua.
local function ass_escape(s)
    if type(s) ~= "string" then s = tostring(s) end
    s = s:gsub("\\", "\\\239\187\191")
    s = s:gsub("{", "\\{"):gsub("}", "\\}")
    s = s:gsub("[\n\r\t]", " ")
    -- a leading space would be trimmed by libass
    s = s:gsub("^ ", "\\h")
    return s
end

--==========================================================================
-- THEME -- every colour in the interface is declared here, as plain hex.
-- No other line of rendering code contains a colour literal.
--==========================================================================

local THEME = {
    bg      = "#1f2335",   -- panel background           bg_dark
    border  = "#3b4261",   -- panel outline              fg_gutter
    fg      = "#c0caf5",   -- titles, never played
    blue    = "#7aa2f7",   -- active tab
    cyan    = "#7dcfff",   -- started, not finished
    green   = "#9ece6a",   -- currently playing
    teal    = "#73daca",   -- queued in the playlist
    orange  = "#ff9e64",   -- the selection
    red     = "#f7768e",   -- errors
    comment = "#565f89",   -- watched to the end
    dark5   = "#737aa2",   -- metadata, key hints, inactive tabs
    purple  = "#bb9af7",   -- the "New n" counter
}

-- "#rrggbb" -> ASS "&HBBGGRR&" (ASS stores colours blue-green-red)
local function ass_colour(hex)
    local r, g, b = tostring(hex):match("^#(%x%x)(%x%x)(%x%x)$")
    if not r then return "&HFFFFFF&" end
    return "&H" .. b:lower() .. g:lower() .. r:lower() .. "&"
end

-- col() is a complete override block and must stand on its own. To put a colour
-- INSIDE an existing {...} block use colr(), which has no braces -- nesting
-- braces breaks the block and libass prints the rest as literal text.
local function col(name, bold)
    return "{\\1c" .. ass_colour(THEME[name] or THEME.fg) .. (bold and "\\b1" or "") .. "}"
end

local function colr(name)
    return "\\1c" .. ass_colour(THEME[name] or THEME.fg)
end

--==========================================================================
-- ICONS
--==========================================================================
-- Each glyph was verified by rendering it in JetBrainsMono NF. Two glyphs the
-- design spec supplied are not in this font and came out blank, so they were
-- replaced with codepoints that do render: podcast U+F2CE, and queued U+F03A
-- (the spec's queue glyph turned out to be an "undo" arrow, which reads wrong
-- for a playlist). Without a Nerd Font every glyph would be a tofu box, so a
-- complete ASCII set exists and is selected automatically.

local ICON_SETS = {
    nerd = {
        all = "󰋜", video = "󰕧", podcast = utf8_char(0xF2CE),
        heading = "󰲸", playing = "󰐊", queued = utf8_char(0xF03A),
        refresh = "󰑐", search = "󰍉", err = "󰀪",
        author = utf8_char(0xF0004),
        unseen = "●", resume = "◐", done = "✓", select = "▶",
    },
    ascii = {
        all = "*", video = "[V]", podcast = "[P]",
        heading = "", playing = ">", queued = "+",
        refresh = "r", search = "/", err = "!",
        author = "@",
        unseen = "●", resume = "◐", done = "✓", select = "▶",
    },
}
local ICON = ICON_SETS.ascii      -- upgraded by probe_font() if one is present
local UI_FONT = ""                -- resolved font family, "" = mpv OSD default

local NERD_CANDIDATES = {
    "JetBrainsMono NF", "JetBrainsMono NFM", "FiraCode NF",
    "CaskaydiaCove NF", "Hack NF", "Symbols Nerd Font",
}

-- mpv cannot enumerate fonts, so ask Windows once at startup. Async, and the
-- interface renders with ASCII icons until the answer arrives.
local function probe_font()
    if opts.icons == "ascii" then return end
    if opts.icons == "nerd" then
        ICON = ICON_SETS.nerd
        UI_FONT = (opts.font ~= "") and opts.font or NERD_CANDIDATES[1]
        return
    end
    run_async({ "powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
        "Add-Type -AssemblyName System.Drawing; "
        .. "(New-Object System.Drawing.Text.InstalledFontCollection).Families"
        .. " | ForEach-Object { $_.Name }" },
        function(ok, res)
            local out = (ok and res and res.status == 0) and res.stdout or nil
            if type(out) ~= "string" then
                msg.verbose("could not enumerate fonts; keeping ASCII icons")
                return
            end
            for _, want in ipairs(NERD_CANDIDATES) do
                if out:find(want, 1, true) then
                    ICON = ICON_SETS.nerd
                    UI_FONT = (opts.font ~= "") and opts.font or want
                    msg.verbose("using Nerd Font: " .. want)
                    return
                end
            end
            msg.verbose("no Nerd Font installed; using ASCII icons")
        end)
end

--==========================================================================
-- TYPE SCALE AND PANEL GEOMETRY
--==========================================================================
-- Sizes are in virtual canvas units and derive from one body size, so the
-- whole interface scales with the window instead of assuming a resolution.

local function sizes()
    local base = math.max(10, math.floor(opts.font_size))
    return {
        heading = math.floor(base * 1.18),
        body    = base,
        icon    = math.floor(base * 1.12),
        meta    = math.floor(base * 0.82),
        hint    = math.floor(base * 0.78),
        -- the list itself: one line per item leaves room to spare, so the
        -- titles you are actually reading get their own, larger size
        list    = math.max(8, math.floor(base * clamp(opts.list_size, 0.7, 2.0))),
        -- space between the tab row and the header card. layout() reserves it
        -- and render() draws at exactly this offset, so it lives in one place.
        card_gap = math.floor(base * 0.72),
    }
end

-- URLs currently in mpv's playlist, so queued items can be marked as such.
-- Read from mpv rather than tracked locally, so manual playlist edits show up.
local function playlist_urls()
    local set = {}
    local pl = mp.get_property_native("playlist")
    if type(pl) == "table" then
        for _, item in ipairs(pl) do
            if type(item) == "table" and item.filename then
                set[item.filename] = item.current and "current" or "queued"
            end
        end
    end
    return set
end

local function canvas()
    local dim = mp.get_property_native("osd-dimensions")
    local w = (type(dim) == "table" and tonumber(dim.w)) or 0
    local wh = (type(dim) == "table" and tonumber(dim.h)) or 0
    local aspect = (w > 0 and wh > 0) and (w / wh) or (16 / 9)

    -- Is the window small enough to want the single-column layout? Small in
    -- absolute pixels, or small beside the display it is on -- 1280 wide is
    -- roomy on a laptop and a stamp on a 4K panel. The answer is parked on ui
    -- because row_height() and render() both need it, and every one of them
    -- runs layout(), which starts here.
    local narrow = (opts.narrow_layout == "always")
    if opts.narrow_layout == "auto" and w > 0 then
        local dw = mp.get_property_number("display-width") or 0
        narrow = (opts.narrow_width > 0 and w <= opts.narrow_width)
            or (dw > 0 and opts.narrow_ratio > 0
                and w <= dw * clamp(opts.narrow_ratio, 0, 1))
    end
    ui.narrow = narrow and true or false

    local h = math.max(240, math.floor(opts.osd_height))
    -- A shorter virtual canvas means the same font_size covers more of the
    -- window, so the text stays legible when the window itself is small.
    if ui.narrow then
        h = math.max(160, math.floor(h / clamp(opts.narrow_scale, 1.0, 2.0)))
    end
    return math.floor(h * aspect), h
end

-- Height of one list row. One line, always: everything a row used to repeat on
-- a second line -- channel, duration, resume position -- is in the header card
-- for the row you are actually on, which is the only one it matters for.
local function row_height(s)
    return s.list + math.floor(s.list * 0.35)
end

-- Declared up here because layout() has to know whether there will be a
-- preview at all before it can decide how tall the header is; the rest of the
-- thumbnail machinery is further down.
local THUMB_OVERLAY_ID = 7
-- box is {w, h}: the slot render() wants for the current layout, fixed by the
-- panel rather than by the picture, so the header never changes height as the
-- selection moves. shown_box is what is actually on screen, so a layout change
-- can be told apart from a row change. Both are in window pixels.
local thumbs = { ffmpeg = nil, shown = nil, shown_box = nil, box = nil,
                 pending = nil, timer = nil, want = nil, geom = nil }

-- The panel: header band, content band, footer band. The bottom stops clear of
-- mpv's own on-screen controller -- the OSC publishes what it reserves, but
-- reports zero while hidden, so a floor from the options is applied too.
local function layout()
    local res_x, res_y = canvas()   -- also refreshes ui.narrow
    local s = sizes()
    local pad = math.floor(s.body * 1.1)

    local m = mp.get_property_native("user-data/osc/margins")
    local osc_b = (type(m) == "table" and tonumber(m.b)) or 0
    local reserve = math.floor(res_y * math.max(osc_b, clamp(opts.osc_reserve, 0, 0.4)))

    local w = math.floor(res_x * clamp(opts.ui_width, 0.3, 1.0))
    local x = math.floor((res_x - w) / 2)
    local y = math.floor(res_y * 0.05)
    local h = math.max(s.body * 8, res_y - reserve - y)

    -- The header band: the tab row, then the card describing the selected row
    -- (byline, title, state, and the description when that is switched on).
    -- band_h is the distance from the top of the band down to the rule that
    -- closes it, and the preview is exactly that tall, so the two line up.
    local tabline = ui.narrow and s.heading or s.body
    local card_h = s.meta + s.body + s.meta
        + (opts.show_descriptions and s.meta or 0) + math.floor(s.body * 0.5)
    local band_h = tabline + s.card_gap + card_h + math.floor(s.body * 0.3)
    local header_h = band_h + math.floor(s.body * 0.55)

    -- The preview is sized from the band rather than from a pixel setting, so
    -- its bottom edge always lands on that rule. In canvas units here; the
    -- pixel sizes go to ffmpeg. Zero when there will be no preview at all.
    local dim = mp.get_property_native("osd-dimensions")
    local scale = (type(dim) == "table" and dim.w and dim.w > 0) and (dim.w / res_x) or 1
    local tw, th, tpx, thpx = 0, 0, 0, 0
    if opts.thumbnails and thumbs.ffmpeg ~= false then
        th = band_h
        -- a tall card must not eat the list: past this the box keeps its
        -- height and crops the picture harder instead of growing wider
        tw = math.min(math.floor(th * clamp(opts.thumbnail_aspect, 0.5, 3.0)),
                      math.floor((w - pad * 2) * 0.35))
        tpx = math.max(16, math.floor(tw * scale + 0.5))
        thpx = math.max(16, math.floor(th * scale + 0.5))
    end

    -- the footer only takes space when it has something to say
    local flines = 0
    if ui.filter_editing or ui.confirm_delete then flines = flines + 2 end
    if ui.status and os.time() <= ui.status_until then flines = flines + 1 end
    if (opts.footer_hints or ui.view == "error")
        and not (ui.filter_editing or ui.confirm_delete) then
        flines = flines + 1
    end
    local footer_h = (flines > 0)
        and (flines * s.body + math.floor(s.body * 0.6)) or 0

    return {
        res_x = res_x, res_y = res_y, s = s, pad = pad, narrow = ui.narrow,
        x = x, y = y, w = w, h = h,
        header_h = header_h, footer_h = footer_h, band_h = band_h,
        -- canvas units for drawing, window pixels for the converter
        thumb_w = tw, thumb_h = th, thumb_px = tpx, thumb_hpx = thpx,
        content_y = y + pad + header_h,
        content_h = h - pad * 2 - header_h - footer_h,
    }
end

local function page_size()
    local g = layout()
    -- two hint lines are reserved for the "N above" / "N more" markers, so a
    -- scrolled list cannot push its last row onto the footer
    local rows = math.floor((g.content_h - g.s.hint * 2) / row_height(g.s))
    return clamp(rows, 3, math.max(3, math.floor(opts.visible_rows)))
end

-- Thumbnails / podcast artwork --------------------------------------------
-- Lua in mpv cannot decode PNG or JPEG, and ASS cannot embed a bitmap. So the
-- image is converted to raw BGRA with ffmpeg (optional; thumbnails are simply
-- off without it) and pushed to the OSD with overlay-add, which does take raw
-- pixels. Converted images are cached on disk, keyed by URL and size.

-- Keyed by both dimensions: a file converted for a different slot is a
-- different file, and this retires earlier generations of the cache for free.
local function thumb_cache_file(url, w, h)
    return utils.join_path(os.getenv("TEMP") or ".",
        -- the "c" marks the cropped-to-fill generation, so files padded by an
        -- earlier version are never picked up: they are the same size in bytes
        string.format("mpv-rss-th-%s-%dx%dc.bgra", fnv1a(url), w, h))
end

local function file_size(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local n = f:seek("end")
    f:close()
    return n
end

local function hide_thumb()
    if thumbs.shown then
        mp.commandv("overlay-remove", tostring(THUMB_OVERLAY_ID))
        thumbs.shown, thumbs.shown_box = nil, nil
    end
end

local function probe_ffmpeg()
    if not opts.thumbnails then thumbs.ffmpeg = false return end
    run_async({ "ffmpeg", "-version" }, function(ok, res)
        thumbs.ffmpeg = (ok and res and res.status == 0) or false
        if not thumbs.ffmpeg then
            msg.verbose("ffmpeg not found on PATH; thumbnails disabled")
        end
    end)
end

-- overlay-add takes window pixels, while the panel is laid out in ASS canvas
-- units, so the panel geometry is scaled across here.
-- geom carries the image's top-left in canvas units (ax, ay); this converts it
-- to the window pixels overlay-add wants.
--
-- osd-dimensions w/h is the WINDOW, and ml/mt are the margins from the window
-- to the video inside it. The ASS overlay is laid over the window too, so the
-- picture must be placed against the window and those margins left out of it.
-- Adding them only looked right while the video filled the window, which is
-- every 16:9 case; snapping mpv to half a 21:9 screen letterboxes the video
-- and dropped the picture a few hundred pixels below its own frame.
local function draw_thumb(path, w, h, url)
    local g = thumbs.geom
    if not g then return end
    local dim = mp.get_property_native("osd-dimensions")
    if type(dim) ~= "table" or not dim.w or dim.w <= 0 then return end
    local scale = dim.w / g.res_x
    local x = math.floor(g.ax * scale)
    local y = math.floor(g.ay * scale)
    -- A conversion that finished after the window was resized is for the old
    -- slot: drawing it would put a picture of the wrong size inside the frame.
    -- prepare_thumb() asks again for the size that is wanted now.
    local b = thumbs.box
    if b and (b[1] ~= w or b[2] ~= h) then return end
    mp.commandv("overlay-add", tostring(THUMB_OVERLAY_ID),
        tostring(math.max(0, x)), tostring(math.max(0, y)),
        path, "0", "bgra", tostring(w), tostring(h), tostring(w * 4))
    thumbs.shown, thumbs.shown_box = url, w * 10000 + h
end

local function prepare_thumb(url)
    -- render() decides the slot for the current layout; the picture is fitted
    -- into it and padded out to fill it, so the file is always this many bytes
    local box = thumbs.box or {}
    local w = math.max(16, math.floor(box[1] or 160))
    local h = math.max(16, math.floor(box[2] or w))
    local path = thumb_cache_file(url, w, h)
    local want_bytes = w * h * 4
    if file_size(path) == want_bytes then
        draw_thumb(path, w, h, url)
        return
    end
    if thumbs.pending then return end
    thumbs.pending = url

    -- Finishing clears the way for the next request, and asks for one when the
    -- slot moved on while this was running -- a resize changes the pixel size,
    -- and without this the new size would simply never be requested.
    local function done()
        thumbs.pending = nil
        local b = thumbs.box
        local stale = b and (b[1] ~= w or b[2] ~= h)
        if ui.active and thumbs.want and (stale or thumbs.shown ~= thumbs.want) then
            if thumbs.timer then thumbs.timer:kill() end
            thumbs.timer = mp.add_timeout(0.05, function()
                if thumbs.want and ui.active then prepare_thumb(thumbs.want) end
            end)
        end
    end

    local function convert(img)
        run_async({ "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", img,
            -- Cover the slot and crop the overflow from the centre, so the
            -- frame is always full: a 16:9 thumbnail lands on all four edges
            -- untouched, a square cover gives up its top and bottom. Either
            -- way the file comes out exactly one known size.
            "-vf", string.format("scale=%d:%d:force_original_aspect_ratio=increase,"
                .. "crop=%d:%d", w, h, w, h),
            "-frames:v", "1", "-pix_fmt", "bgra", "-f", "rawvideo", path },
            function(success, res)
                if not (success and res and res.status == 0
                        and file_size(path) == want_bytes) then
                    msg.verbose("thumbnail conversion failed for " .. tostring(url))
                    os.remove(path)
                    done()
                    return
                end
                if ui.active and thumbs.want == url then draw_thumb(path, w, h, url) end
                done()
            end)
    end

    -- The downloaded picture is kept, not just the converted one: resizing the
    -- window asks for a new pixel size, and re-fetching the image over the
    -- network for every size the drag passes through would be absurd.
    local src = utils.join_path(os.getenv("TEMP") or ".",
        string.format("mpv-rss-img-%s", fnv1a(url)))
    if (file_size(src) or 0) > 0 then
        convert(src)
    else
        download(url, src, function(ok, err)
            if not ok then
                os.remove(src)
                msg.verbose("thumbnail download failed: " .. tostring(err))
                done()
                return
            end
            convert(src)
        end)
    end
end

-- Debounced, so scrolling quickly through a list does not start a download per row.
local function update_thumb(url, geom)
    thumbs.geom = geom
    if not opts.thumbnails or thumbs.ffmpeg == false or not ui.active or not url then
        thumbs.want = nil
        hide_thumb()
        return
    end
    -- the slot matters as much as the URL: resizing the window into or out of
    -- the narrow layout keeps the same image but needs it drawn at a new size
    local want = thumbs.box and (thumbs.box[1] * 10000 + thumbs.box[2]) or nil
    if url == thumbs.shown and thumbs.shown_box == want then return end
    thumbs.want = url
    hide_thumb()
    if thumbs.timer then thumbs.timer:kill() end
    thumbs.timer = mp.add_timeout(0.15, function()
        if thumbs.want == url and ui.active then prepare_thumb(url) end
    end)
end

-- A rounded panel: translucent fill plus a thin outline, rather than a heavy
-- opaque card, so the video stays visible behind it.
local function draw_panel(x0, y0, x1, y1, radius)
    local function rect(r)
        local f = math.floor
        return string.format(
            "m %d %d l %d %d b %d %d %d %d %d %d l %d %d b %d %d %d %d %d %d "
            .. "l %d %d b %d %d %d %d %d %d l %d %d b %d %d %d %d %d %d",
            f(x0 + r), f(y0), f(x1 - r), f(y0),
            f(x1), f(y0), f(x1), f(y0), f(x1), f(y0 + r),
            f(x1), f(y1 - r),
            f(x1), f(y1), f(x1), f(y1), f(x1 - r), f(y1),
            f(x0 + r), f(y1),
            f(x0), f(y1), f(x0), f(y1), f(x0), f(y1 - r),
            f(x0), f(y0 + r),
            f(x0), f(y0), f(x0), f(y0), f(x0 + r), f(y0))
    end
    local fill = string.format(
        "{\\an7\\pos(0,0)\\bord0\\shad0\\1c%s\\1a&H30&\\p1}%s{\\p0}",
        ass_colour(THEME.bg), rect(radius))
    local outline = string.format(
        "{\\an7\\pos(0,0)\\bord1\\shad0\\1a&HFF&\\3c%s\\3a&H60&\\p1}%s{\\p0}",
        ass_colour(THEME.border), rect(radius))
    return fill .. "\n" .. outline
end

--------------------------------------------------------------------------
-- Line box: the panel is built as a list of lines, each with its own size,
-- colour and alignment, and emitted as one positioned ASS event per line.
-- A single event could only ever carry one font size, which is why headings,
-- body text and metadata could not differ before.
--------------------------------------------------------------------------

local Box = {}
Box.__index = Box

local function new_box()
    return setmetatable({ items = {}, h = 0 }, Box)
end

-- spec: { text, size, colour, indent, align ("left"/"right"), gap, bold }
function Box:add(spec)
    spec.size = spec.size or 12
    spec.gap = spec.gap or 0
    self.items[#self.items + 1] = spec
    self.h = self.h + spec.size + spec.gap
    return self
end

function Box:gap(h)
    self.items[#self.items + 1] = { spacer = true, size = 0, gap = h }
    self.h = self.h + h
end

function Box:render(x, y, w, font, clip)
    local out, cy = {}, y
    local fn = (font ~= "" and font ~= nil) and ("\\fn" .. font) or ""
    local function emit(an, px, py, size, bold, colour, text)
        out[#out + 1] = string.format(
            "{\\an%d\\pos(%d,%d)\\fs%d\\bord1\\shad0\\q2%s%s%s%s}%s",
            an, math.floor(px), math.floor(py), size, fn, clip,
            bold and "\\b1" or "", colour or "", text or "")
    end
    for _, it in ipairs(self.items) do
        cy = cy + it.gap
        if not it.spacer then
            emit(7, x + (it.indent or 0), cy, it.size, it.bold, it.colour, it.text)
            -- an optional badge pinned to the right edge of the same line
            if it.right then
                emit(9, x + w, cy, it.size, false, it.right_colour, it.right)
            end
            cy = cy + it.size
        end
    end
    return table.concat(out, "\n")
end

-- Build the list of drawable rows for the current view, applying the filter.
rebuild_rows = function()
    local rows = {}
    -- these two draw their own content and have no selectable rows
    if ui.view == "help" or ui.view == "error" then
        ui.rows, ui.sel, ui.scroll = rows, 1, 0
        return
    end
    if ui.view == "playlist" then
        -- read mpv's real playlist, so items queued or removed elsewhere show up
        local pl = mp.get_property_native("playlist")
        if type(pl) == "table" then
            for idx, item in ipairs(pl) do
                if type(item) == "table" then
                    local url = item.filename
                    local e = entry_by_url(url)
                    rows[#rows + 1] = {
                        kind = "pl",
                        index = idx - 1,   -- mpv's playlist commands are 0-based
                        url = url,
                        entry = e,
                        current = item.current == true,
                        label = (e and e.title) or item.title or url or "(unknown)",
                    }
                end
            end
        end
    elseif ui.view == "feeds" then
        local all = entries_for_tab(ui.tab)
        local fresh = new_count(all)
        -- everything you have not started, across this tab, on top
        -- count is the one-line form of detail, for the narrow layout, which
        -- has no second line to put it on: new / total, newsraft style
        rows[#rows + 1] = {
            kind = "new",
            label = "New",
            detail = (fresh > 0)
                and string.format("%d unplayed item%s", fresh, fresh == 1 and "" or "s")
                or "nothing new",
            count = tostring(fresh),
        }
        rows[#rows + 1] = {
            kind = "all",
            label = (ui.tab == "videos" and "All videos")
                or (ui.tab == "podcasts" and "All episodes")
                or "All items",
            detail = string.format("%d items  ·  %d new", #all, new_count(all)),
            count = string.format("%d / %d", fresh, #all),
        }
        for _, f in ipairs(feeds) do
          if feed_in_tab(f.url, ui.tab) then
            local list = entries_for_feed(f.url)
            local detail, count
            if feed_errors[f.url] then
                -- the technical text belongs in the error view, not the list
                detail, count = "Unable to refresh", "error"
            elseif f.enabled == false then
                detail, count = "disabled", "off"
            elseif cache[f.url] then
                detail = string.format("%d items  ·  %d new", #list, new_count(list))
                if cache[f.url].podcast20 then detail = detail .. "  ·  podcast 2.0" end
                count = string.format("%d / %d", new_count(list), #list)
            else
                detail, count = "not fetched yet", "–"
            end
            rows[#rows + 1] = {
                kind = "feed", feed = f, label = f.name, detail = detail,
                count = count, error = feed_errors[f.url] ~= nil,
            }
          end
        end
    else
        local list = ui.entries
        local filter = ui.filter ~= "" and ui.filter:lower() or nil
        for _, e in ipairs(list) do
            local hit = true
            if filter then
                local hay = ((e.title or "") .. " " .. (e.author or "")):lower()
                hit = hay:find(filter, 1, true) ~= nil
            end
            -- "watched" hides only finished items; a part-watched one is still
            -- something you have not got to the end of
            if hit and ui.hide_seen and item_state(e.id) == "seen" then hit = false end
            if hit then
                rows[#rows + 1] = { kind = "entry", entry = e }
            end
        end
    end
    ui.rows = rows
    ui.sel = clamp(ui.sel, 1, math.max(1, #rows))
    local page = page_size()
    if ui.sel <= ui.scroll then ui.scroll = ui.sel - 1 end
    if ui.sel > ui.scroll + page then ui.scroll = ui.sel - page end
    ui.scroll = clamp(ui.scroll, 0, math.max(0, #rows - page))
end

render = function()
    if not ui.active then
        overlay:remove()
        return
    end

    local g = layout()
    local s = g.s
    local narrow = g.narrow

    -- Artwork for the highlighted row; the text makes room for it. A YouTube
    -- channel feed carries no image of its own -- only podcasts tend to -- so
    -- a feed row, and the New / All rows above it, borrow the newest item's
    -- thumbnail rather than leaving the dock empty on the screen you land on.
    local sel_row = ui.rows[ui.sel]
    local art = nil
    if sel_row then
        if sel_row.entry then
            art = artwork_url(sel_row.entry)
        elseif sel_row.feed then
            local c = cache[sel_row.feed.url]
            art = (c and c.image)
                or artwork_url(entries_for_feed(sel_row.feed.url)[1])
        elseif sel_row.kind == "new" or sel_row.kind == "all" then
            art = artwork_url(entries_for_tab(ui.tab)[1])
        end
    end
    -- layout() sized the slot, so the header could make room for it. It is
    -- reserved whenever thumbnails are available at all, not only when the
    -- highlighted row happens to have one: the tab columns and the titles are
    -- measured against it and would jump as you scrolled past a row without.
    local thumb_w, thumb_h = g.thumb_w, g.thumb_h
    local thumb_slot = thumb_w > 0
    if thumb_slot then thumbs.box = { g.thumb_px, g.thumb_hpx } end

    -- The preview is docked in the panel's top-right corner and costs the rest
    -- of the interface only its own width: everything else -- tab columns,
    -- heading, titles -- is laid out in what is left, which is as wide as it
    -- can be. (It used to take a whole third of the panel.)
    local inner_w = g.w - g.pad * 2 - (thumb_slot and (thumb_w + g.pad) or 0)
    local col_w = math.floor(inner_w / 3)
    -- glyph widths are unknown to the script, so this is an estimate; the
    -- clip below is the hard guarantee that nothing escapes the panel
    local cols = math.max(16, math.floor(inner_w / (s.body * 0.5)))
    local clip = string.format("\\clip(%d,%d,%d,%d)",
        g.x, g.y, g.x + g.w, g.y + g.h)

    -- The list runs the full width of the panel: the preview only occupies the
    -- header band, so reserving its column all the way down would strand a
    -- third of every title. Only the card beside it stops short.
    local full_w = g.w - g.pad * 2

    -- size and width: the text is measured against the column budget for the
    -- size it will be drawn at, and the width it will be drawn in, rather than
    -- the body text in the card's column
    local function fit(text, extra, size, width)
        local c = cols
        if size or width then
            c = math.max(16, math.floor((width or inner_w) / ((size or s.body) * 0.5)))
        end
        return ass_escape(utf8_truncate(text or "", c - (extra or 0)))
    end

    ----------------------------------------------------------------- header
    -- Tab bar. Each tab gets its own column and its own ASS event, so the
    -- active one can be underlined at a known x -- with one shared text line
    -- the x of a tab is unknowable (the font is proportional).
    local tc = tab_counts()
    local tabs = {
        { "all", ICON.all, "ALL", tc.afeeds, tc.all, tc.new_all },
        { "videos", ICON.video, "VIDEOS", tc.vfeeds, tc.videos, tc.new_videos },
        { "podcasts", ICON.podcast, "PODCASTS", tc.pfeeds, tc.podcasts, tc.new_podcasts },
    }
    local fn = (UI_FONT ~= "") and ("\\fn" .. UI_FONT) or ""
    local tabx, taby = g.x + g.pad, g.y + g.pad
    local colw = col_w
    local tab_out, underline = {}, nil
    local active_i = 1
    for i, t in ipairs(tabs) do if ui.tab == t[1] then active_i = i end end

    local function line(an, px, py, size, text)
        return string.format(
            "{\\an%d\\pos(%d,%d)\\fs%d\\bord1\\shad0\\q2%s%s}%s",
            an, math.floor(px), math.floor(py), size, fn, clip, text)
    end
    local function rule(px, py, pw, ph, tone)
        return string.format(
            "{\\an7\\pos(0,0)\\bord0\\shad0\\1c%s\\p1}m %d %d l %d %d l %d %d l %d %d{\\p0}",
            ass_colour(THEME[tone] or THEME.blue),
            px, py, px + pw, py, px + pw, py + ph, px, py + ph)
    end

    if narrow then
        -- One section at a time, with its place in the cycle. There is no room
        -- for three columns of counts, and the number doubles as the key that
        -- jumps straight to that section. It stays on screen in every view --
        -- it is the only thing that says which section you are in.
        local t = tabs[active_i]
        local text = col("blue", true)
            .. string.format("%d/%d", active_i, #tabs)
            .. col("fg", true) .. "  " .. t[2] .. "  " .. t[3]
        if t[6] > 0 then
            text = text .. col("purple") .. "   New " .. t[6]
        end
        tab_out[#tab_out + 1] = line(7, tabx, taby, s.heading, text)
        tab_out[#tab_out + 1] = line(9, tabx + inner_w,
            taby + math.floor((s.heading - s.meta) / 2), s.meta,
            col("dark5") .. string.format("%s %d / %d", ICON.author, t[4], t[5]))
    else
        for i, t in ipairs(tabs) do
            local active = (i == active_i)
            local tx = tabx + (i - 1) * colw
            -- the number is both a label and the key that selects the section
            local text = (active and col("blue", true) or col("dark5"))
                .. i .. "  " .. t[2] .. " " .. t[3]
                .. "   " .. (active and col("fg") or col("dark5"))
                .. ICON.author .. " " .. t[4] .. " / " .. t[5]
            if t[6] > 0 then
                text = text .. "   " .. col("purple") .. "New " .. t[6]
            end
            tab_out[#tab_out + 1] = line(7, tx, taby, s.body, text)
            if active then
                local uy = taby + s.body + math.floor(s.body * 0.22)
                local uh = math.max(2, math.floor(s.body * 0.12))
                underline = rule(tx, uy, math.floor(colw * 0.80), uh, "blue")
            end
        end
    end

    -- The card: three lines about the row you are on -- byline, title, state --
    -- which is why the rows themselves need only one line each. What it
    -- describes depends on what is selected: an item, a feed, or a plain view
    -- with no selection at all (help, error, an empty list).
    local head = new_box()
    local pl_urls = (ui.view == "entries" or ui.view == "playlist")
        and playlist_urls() or {}
    -- kept as plain text as well, so the byline beside it gives up exactly as
    -- many columns as the badge needs and no more
    local badge_text, badge_col
    if refresh_state.active then
        badge_text = string.format("%s  %d/%d", ICON.refresh,
            refresh_state.done, refresh_state.total)
        badge_col = "blue"
    elseif ui.hide_seen then
        badge_text = narrow and "unwatched" or "unwatched only"
        badge_col = "cyan"
    end
    local badge = badge_text and (col(badge_col) .. ass_escape(badge_text)) or nil

    -- Each line is raw text plus a colour name: fit() escapes what it is given,
    -- so a colour tag mixed into the text would be printed rather than obeyed.
    local l1, l2, l3            -- byline, title, state
    local c1, c2, c3 = "dark5", "fg", "fg"
    local tail, ctail           -- an optional second colour on the state line
    local sel_e = sel_row and sel_row.entry or nil
    if sel_e then
        local bits = {}
        if sel_e.author and sel_e.author ~= "" then
            bits[#bits + 1] = ICON.author .. " " .. sel_e.author
        elseif sel_row.kind == "pl" then
            bits[#bits + 1] = ICON.queued .. " playlist"
        end
        bits[#bits + 1] = format_date(sel_e.date, "long")
        if sel_e.duration then bits[#bits + 1] = format_clock(sel_e.duration) end
        l1 = table.concat(bits, "  ·  ")
        l2 = sel_e.title or "(untitled)"

        -- state, in the same colours the row markers use
        local st = item_state(sel_e.id)
        local pos = resume_pos(sel_e.id)
        local p = sel_e.id and state.progress[sel_e.id] or nil
        if pos then
            local dur = (p and p.dur) or sel_e.duration
            l3 = ICON.resume .. " started  ·  resume " .. format_clock(pos)
            if dur and dur > 0 then
                l3 = l3 .. " of " .. format_clock(dur)
                    .. string.format("  (%d%%)", math.floor(pos / dur * 100 + 0.5))
            end
            c3 = "cyan"
        elseif st == "seen" then
            local when = state.watched[sel_e.id] or (p and p.ts)
            l3 = ICON.done .. " watched"
                .. (when and ("  ·  " .. format_date(when, "long")) or "")
            c3 = "comment"
        else
            l3 = ICON.unseen .. " new"
        end
        local q = pl_urls[sel_e.url] or (sel_row.current and "current") or nil
        if q == "current" then tail, ctail = "  ·  now playing", "green"
        elseif q == "queued" then tail, ctail = "  ·  queued", "teal" end

    elseif sel_row and sel_row.feed then
        local f = sel_row.feed
        local c = cache[f.url]
        local list = entries_for_feed(f.url)
        local bits = {}
        local k = feed_kind(f.url)
        bits[#bits + 1] = (k == "podcast" and ICON.podcast)
            or (k == "video" and ICON.video) or ICON.all
        bits[#bits + 1] = string.format("%d items  ·  %d new", #list, new_count(list))
        if c and c.fetched_at and c.fetched_at > 0 then
            bits[#bits + 1] = "refreshed " .. format_date(c.fetched_at, "relative")
        end
        l1 = table.concat(bits, "  ")
        l2 = f.name
        c3 = "dark5"
        if feed_errors[f.url] then
            l3, c3 = ICON.err .. " " .. tostring(feed_errors[f.url]), "red"
        elseif f.enabled == false then
            l3 = "disabled"
        elseif list[1] then
            l3 = "newest: " .. (list[1].title or "")
        else
            l3 = "nothing fetched yet"
        end

    elseif sel_row and (sel_row.kind == "new" or sel_row.kind == "all") then
        -- the two virtual rows describe themselves; rebuild_rows() already
        -- worked out the counts for them
        local newest = entries_for_tab(ui.tab)[1]
        l1 = sel_row.detail or ""
        l2 = sel_row.label or ""
        c3 = "dark5"
        l3 = newest and ("newest: " .. (newest.title or "")) or "nothing fetched yet"

    else
        -- no selection to describe: fall back to naming the view
        local title, ticon
        if ui.view == "feeds" then
            title, ticon = "RSS SUBSCRIPTIONS", ICON.heading
        elseif ui.view == "playlist" then
            title, ticon = string.format("PLAYLIST  (%d)", #ui.rows), ICON.queued
        elseif ui.view == "help" then
            title, ticon = "KEYBOARD SHORTCUTS", ICON.search
        elseif ui.view == "error" then
            title, ticon = "FEED ERROR", ICON.err
        else
            title, ticon = ui.feed_label or "", ICON.heading
        end
        -- a queued item with no feed entry behind it still has its own title
        if sel_row and sel_row.kind == "pl" then
            l1 = ICON.queued .. " playlist"
            l2 = sel_row.label or title
        else
            l1 = narrow and ui.tab:upper() or ""
            l2 = ticon .. "  " .. title
        end
    end

    head:add({ text = col(c1) .. fit(l1 or "", badge_text
                   and (utf8_len(badge_text) + 3) or 2), size = s.meta,
               right = badge, right_colour = "" })
    head:add({ text = col(c2, true) .. fit(l2 or "", 2), size = s.body, bold = true,
               gap = math.floor(s.body * 0.18) })
    if l3 then
        head:add({
            text = col(c3) .. fit(l3, tail and 14 or 2)
                .. (tail and (col(ctail) .. ass_escape(tail)) or ""),
            size = s.meta, gap = math.floor(s.body * 0.18),
        })
    end
    if opts.show_descriptions and sel_e and sel_e.desc and sel_e.desc ~= "" then
        head:add({ text = col("dark5") .. fit(sel_e.desc, 2), size = s.meta })
    end

    ---------------------------------------------------------------- content
    local body = new_box()
    local page = page_size()
    local ind1 = math.floor(s.body * 0.4)                   -- marker column
    local ind2 = ind1 + math.floor(s.body * 1.6)            -- icon column
    local ind3 = ind2 + math.floor(s.body * 2.0)            -- text column

    if ui.view == "help" then
        local groups = {
            { "Navigate", {
                { "↑ ↓   j k", "move" },
                { "PgUp PgDn", "page" },
                { "Home End", "first / last" },
                { "Tab  Shift+Tab", "next / previous section" },
                { "1  2  3", "go straight to a section" },
                { "Enter  →", "open / play" },
                { "Esc  ←  Backspace", "back" },
            } },
            { "Play", {
                { "Enter", "play now" },
                { opts.key_queue, "add to end of playlist" },
                { opts.key_play_next, "play next" },
                { opts.key_index, "show the playlist" },
                { "m", "toggle seen / unseen" },
                { "v", "hide / show watched items" },
            } },
            { "Feeds", {
                { "r", "refresh this feed" },
                { "R", "refresh everything" },
                { "a", "paste a feed URL (clipboard pre-filled)" },
                { opts.key_edit, "edit rss-feeds.json in an editor" },
                { "d  then  y", "remove the selected feed" },
                { "e", "show the full error of a failed feed" },
            } },
            { "Other", {
                { "/", "filter the list" },
                { "?", "this screen" },
                { opts.key_open, "open / close the browser" },
                { "q", "close the browser (mpv keeps playing)" },
            } },
        }
        for gi, grp in ipairs(groups) do
            body:add({ text = col("blue", true) .. grp[1], size = s.meta,
                       indent = ind2, gap = gi > 1 and math.floor(s.body * 0.6) or 0 })
            for _, k in ipairs(grp[2]) do
                body:add({
                    text = col("fg") .. k[1], size = s.meta, indent = ind3,
                    right = col("dark5") .. k[2],
                })
            end
        end

    elseif ui.view == "error" then
        local f = ui.error_feed
        local msgtext = f and feed_errors[f.url] or "no error recorded"
        body:add({ text = col("fg", true) .. fit(f and f.name or "", 6),
                   size = s.body, indent = ind2 })
        body:add({ text = col("dark5") .. fit(f and f.url or "", 6),
                   size = s.meta, indent = ind2, gap = math.floor(s.body * 0.2) })
        body:add({ text = col("red") .. ICON.err .. "  " .. fit(tostring(msgtext), 8),
                   size = s.meta, indent = ind2, gap = math.floor(s.body * 0.8) })
        body:add({ text = col("dark5")
                       .. "The feed stays in your list; other feeds are unaffected.",
                   size = s.meta, indent = ind2, gap = math.floor(s.body * 0.8) })

    elseif #ui.rows == 0 then
        local m1, m2
        if ui.view == "playlist" then
            m1 = "The playlist is empty."
            m2 = string.format("Queue with  %s  (to the end)  or  %s  (play next).",
                opts.key_queue, opts.key_play_next)
        elseif ui.view == "feeds" then
            m1 = "No feeds yet."
            m2 = "Copy a channel or podcast URL to the clipboard, then press  a"
        elseif ui.filter ~= "" then
            m1, m2 = "Nothing matches the filter.", ""
        elseif ui.hide_seen and #ui.entries > 0 then
            -- the list is not empty, it is entirely watched
            m1 = string.format("All %d item%s here are watched.",
                #ui.entries, #ui.entries == 1 and "" or "s")
            m2 = "Press  v  to show them again."
        else
            m1, m2 = "No items.", "Press  r  to refresh."
        end
        body:add({ text = col("dark5") .. fit(m1), size = s.body, indent = ind2 })
        if m2 ~= "" then
            body:add({ text = col("dark5") .. fit(m2), size = s.meta, indent = ind2,
                       gap = math.floor(s.body * 0.3) })
        end
    else
        if ui.scroll > 0 then
            body:add({ text = col("dark5") .. string.format("▲ %d above", ui.scroll),
                       size = s.hint, indent = ind2 })
        end
        local last = math.min(#ui.rows, ui.scroll + page)
        for i = ui.scroll + 1, last do
            local row = ui.rows[i]
            local selected = (i == ui.sel)
            local gap = math.floor(s.body * 0.30)

            if row.kind == "entry" or row.kind == "pl" then
                local e = row.entry
                local st = e and item_state(e.id) or "unseen"
                local q = (e and pl_urls[e.url]) or (row.current and "current") or nil

                -- visual priority: selection, then playing, then queued,
                -- then the watch state itself (§21)
                local icon, tone
                if q == "current" then icon, tone = ICON.playing, "green"
                elseif q == "queued" then icon, tone = ICON.queued, "teal"
                elseif st == "partial" then icon, tone = ICON.resume, "cyan"
                elseif st == "seen" then icon, tone = ICON.done, "comment"
                else icon, tone = ICON.unseen, "fg" end
                if selected then tone = "orange" end

                local label = (row.kind == "pl") and row.label
                    or (e and e.title) or "(untitled)"
                local num = ""
                if row.kind == "pl" then
                    num = string.format("%d. ", row.index + 1)
                elseif opts.show_index then
                    num = string.format("%d. ", i)
                end

                -- "Aug 06 | <title>": the date leads, in a fixed-width form, so
                -- the titles line up down the list. Everything else about the
                -- item is in the header card for the row you are on.
                local when = ""
                if row.kind ~= "pl" and e then
                    when = col("dark5") .. format_date(e.date) .. " | " .. col(tone)
                end

                -- One event per line: never use {\r} here, it resets the style
                -- and would discard both \fn and \fs for the rest of the line.
                body:add({
                    text = (selected and (col("orange") .. ICON.select .. " ") or "   ")
                        .. col(tone) .. icon .. "  "
                        .. (num ~= "" and (col("dark5") .. num .. col(tone)) or "")
                        .. when .. fit(label, when ~= "" and 18 or 8, s.list, full_w),
                    size = s.list, indent = ind1, gap = gap,
                })
            else
                -- a feed row
                local kind = row.feed and feed_kind(row.feed.url) or "other"
                local icon = (row.kind == "new" and ICON.unseen)
                    or (kind == "podcast" and ICON.podcast)
                    or (kind == "video" and ICON.video) or ICON.all
                local tone = selected and "orange"
                    or (row.kind == "new" and "purple") or "fg"
                -- one line, with new / total on the right; the full detail is
                -- in the header card for whichever feed you are on
                body:add({
                    text = (selected and (col("orange") .. ICON.select .. " ") or "   ")
                        .. col(tone) .. icon .. "  " .. fit(row.label, 20, s.list, full_w),
                    size = s.list, indent = ind1, gap = gap,
                    right = (row.count
                            and (col(row.error and "red" or "dark5") .. row.count))
                        or (row.error and (col("red") .. ICON.err))
                        or nil,
                })
            end
        end
        if last < #ui.rows then
            body:add({ text = col("dark5") .. string.format("▼ %d more", #ui.rows - last),
                       size = s.hint, indent = ind2, gap = math.floor(s.body * 0.3) })
        end
    end

    ----------------------------------------------------------------- footer
    local foot = new_box()
    local hint
    if ui.filter_editing then
        local inp = ui.input
        foot:add({ text = col("fg", true) .. (inp.icon or ICON.search) .. "  "
            .. ass_escape(inp.label) .. ": " .. ass_escape(inp.buf) .. "_",
            size = s.body })
        -- modal states keep their guidance even with the hint bar switched off
        foot:add({ text = col("dark5")
            .. "Enter  confirm     Esc  cancel     Ctrl+V  paste     Ctrl+U  clear",
            size = s.hint })
    elseif ui.confirm_delete then
        foot:add({ text = col("red") .. ICON.err .. "  Remove feed: "
            .. fit(ui.confirm_delete.name, 24), size = s.body })
        foot:add({ text = col("dark5") .. "y  confirm      any other key  cancel",
                   size = s.hint })
    elseif ui.view == "help" then
        hint = "Esc / ?  Back      q  Close"
    elseif ui.view == "error" then
        hint = "r  Retry this feed      Esc  Back      q  Close"
    elseif ui.view == "playlist" then
        hint = narrow
            and string.format("↑↓ Move   Enter Play   d Remove   %s Back", opts.key_index)
            or string.format("↑↓ Navigate     Enter Play     d Remove     %s/Esc Back     q Close",
                opts.key_index)
    elseif ui.view == "feeds" then
        hint = narrow
            and "1-3 / Tab Section   ↑↓ Move   Enter Open   a Add   q Close"
            or string.format("%s Refresh     1-3 / Tab Section     ↑↓ Navigate     Enter Open     a Add     q Close",
                ICON.refresh)
    else
        hint = narrow
            and string.format("↑↓ Move   Enter Play   %s Queue   Esc Back", opts.key_queue)
            or string.format("%s Refresh   %s Filter   ↑↓ Navigate   Enter Play   %s Queue   %s Playlist   Esc Back",
                ICON.refresh, ICON.search, opts.key_queue, opts.key_index)
    end
    -- the error view keeps its line: "r retry" is the whole point of the screen
    if hint and (opts.footer_hints or ui.view == "error") then
        foot:add({ text = col("dark5") .. hint, size = s.hint })
    end
    if ui.status and os.time() <= ui.status_until then
        foot:add({ text = col(ui.status_tone or "fg") .. ass_escape(ui.status),
                   size = s.hint, gap = math.floor(s.hint * 0.3) })
    end

    ---------------------------------------------------------------- assemble
    -- The rule that closes the header band runs the full inner width, under
    -- the card and under the preview, which sits on it: the box is exactly as
    -- tall as the band, so its bottom edge and this line are the same line.
    local hr = math.max(1, math.floor(s.body * 0.08))
    local rule_y = taby + g.band_h
    local header_rule = rule(g.x + g.pad, rule_y, g.w - g.pad * 2, hr, "border")

    -- The frame around the preview is therefore three-sided -- top, left,
    -- right -- with the rule as its fourth. Drawn whenever the selected row
    -- has artwork, before the conversion finishes: the picture is fitted into
    -- the box, so the box does not have to wait to know its own size.
    local frame = ""
    if art and thumb_slot then
        local fx = g.x + g.w - g.pad - thumb_w
        frame = table.concat({
            rule(fx - hr, taby - hr, thumb_w + hr * 2, hr, "border"),
            rule(fx - hr, taby, hr, thumb_h, "border"),
            rule(fx + thumb_w, taby, hr, thumb_h, "border"),
        }, "\n")
    end

    local radius = math.floor(s.body * 0.7)
    local parts_out = {
        draw_panel(g.x, g.y, g.x + g.w, g.y + g.h, radius),
        table.concat(tab_out, "\n"),
        underline or "",
        header_rule,
        frame,
        -- the card sits under the tab row, and its width is the list's, so the
        -- badge on the right stops short of the preview
        head:render(g.x + g.pad,
            taby + (narrow and s.heading or s.body) + s.card_gap,
            inner_w, UI_FONT, clip),
        -- the help screen's right column is pinned to the panel edge, which
        -- reads as a stretched gap on a wide window, so narrow it
        body:render(g.x + g.pad, g.content_y,
            (ui.view == "help") and math.floor(full_w * 0.5) or full_w, UI_FONT, clip),
        foot:render(g.x + g.pad, g.y + g.h - g.pad - foot.h, g.w - g.pad * 2, UI_FONT, clip),
    }

    overlay.res_x = g.res_x
    overlay.res_y = g.res_y
    overlay.data = table.concat(parts_out, "\n")
    overlay:update()

    -- docked in the panel's top-right corner, level with the tab bar
    update_thumb(art, { res_x = g.res_x, res_y = g.res_y,
                        ax = g.x + g.w - g.pad - thumb_w, ay = taby })
end

--==========================================================================
-- 12. PLAYBACK
--==========================================================================

local ytdl_available = nil   -- nil = unknown, false = missing, string = program
local last_played = nil

local function probe_ytdl()
    local candidates = { "yt-dlp", "yt-dlp.exe", "youtube-dl" }
    local function try(i)
        if i > #candidates then
            ytdl_available = false
            msg.warn("yt-dlp not found on PATH; YouTube playback will not work")
            return
        end
        run_async({ candidates[i], "--version" }, function(success, res)
            if success and res and res.status == 0 then
                ytdl_available = candidates[i]
                msg.verbose("found " .. candidates[i] .. " " .. tostring(first_line(res.stdout)))
            else
                try(i + 1)
            end
        end)
    end
    try(1)
end

local close_menu   -- forward declaration

-- Progress tracking ------------------------------------------------------
-- A 5 s sampler is used rather than observing time-pos, which fires on every
-- frame. Completion does not depend on the sample: end-file reports the reason
-- "eof" when a file genuinely played to the end.

-- live: a broadcast rather than a recording. Its duration grows as it is
-- received and the position trails just behind, so neither number measures
-- how much of the programme you have seen. See sample_progress below.
local track = { id = nil, pos = 0, dur = nil, title = nil, live = false }

local last_autosave = 0

local function sample_progress()
    if not track.id then return end
    local pos = mp.get_property_number("time-pos")
    local dur = mp.get_property_number("duration")
    if pos then track.pos = pos end
    if dur and dur > 0 then
        -- A recording's duration is fixed. One that grows between samples is
        -- still being broadcast, which catches the streams that do report
        -- themselves as seekable (YouTube serves a DVR window for those).
        if track.dur and dur > track.dur + 1 then track.live = true end
        track.dur = dur
    end

    if track.live then return end

    -- periodically commit the position, so an abrupt exit costs at most
    -- autosave_interval seconds of progress rather than the whole session
    local iv = tonumber(opts.autosave_interval) or 0
    if iv > 0 and os.time() - last_autosave >= iv
        and track.pos >= opts.min_progress_seconds then
        last_autosave = os.time()
        local p = state.progress[track.id] or {}
        if not p.done then
            p.pos, p.dur, p.ts = track.pos, track.dur or p.dur, os.time()
            state.progress[track.id] = p
            save_state()
            msg.verbose(string.format("autosaved progress %s at %ds",
                tostring(track.id), math.floor(track.pos)))
        end
    end
end

local function finish_tracking(completed)
    if not track.id then return end
    sample_progress()
    if track.live then
        -- The position sits at a fixed lag behind a duration that keeps
        -- growing, so the ratio drifts past watched_threshold after half a
        -- minute and would mark a programme you dipped into as fully seen.
        -- Nothing here is worth remembering: "where you left off" in a
        -- broadcast is just the live edge. Only the broadcast actually ending
        -- while you watched it counts as having watched it.
        local p = state.progress[track.id]
        if completed then
            state.progress[track.id] = { pos = 0, dur = nil, done = true, ts = os.time() }
            state.watched[track.id] = os.time()
        elseif p and not p.done then
            state.progress[track.id] = nil
        end
        save_state()
        track.id, track.pos, track.dur, track.title, track.live = nil, 0, nil, nil, false
        if ui.active then rebuild_rows() render() end
        return
    end
    local p = state.progress[track.id] or {}
    p.dur = track.dur or p.dur
    p.ts = os.time()
    if completed or (p.dur and p.dur > 0 and track.pos >= p.dur * opts.watched_threshold) then
        p.done = true
        p.pos = 0
        state.watched[track.id] = os.time()
    else
        p.done = false
        p.pos = (track.pos >= opts.min_progress_seconds) and track.pos or 0
    end
    state.progress[track.id] = p
    save_state()
    track.id, track.pos, track.dur, track.title = nil, 0, nil, nil
    if ui.active then rebuild_rows() render() end
end

local function start_tracking(entry)
    if track.id and entry and track.id == entry.id then return end
    if track.id then finish_tracking(false) end
    track.id = entry and entry.id or nil
    track.pos, track.dur, track.live = 0, nil, false
    track.title = entry and entry.title or nil
end

-- Fallback bookkeeping for servers mpv cannot stream from. Declared before the
-- file-loaded handler below, which reads fallback.entry.
-- Kept in one table rather than six locals: this is a top-level chunk and Lua
-- allows only 200 of those.
local fallback = {
    tried  = {},     -- url -> already attempted, so it is retried only once
    files  = {},     -- temp files, removed on shutdown
    entry  = {},     -- local path -> feed entry, so progress still tracks
    queue  = {},     -- entries waiting to be fetched
    busy   = false,  -- one download at a time, see pump_fallback
    opened = nil,    -- what start-file last announced, for end-file to blame
}

-- §15: a short title card, top-left, when playback of a feed item starts.
local title_ov = mp.create_osd_overlay("ass-events")
local title_timer = nil

local function hide_title_card()
    if title_timer then title_timer:kill() title_timer = nil end
    title_ov:remove()
end

local function show_title_card(e)
    if not e or not opts.title_overlay then return end
    local _, res_y = canvas()
    local s = sizes()
    local pad = math.floor(s.body * 1.6)
    local fn = (UI_FONT ~= "") and ("\\fn" .. UI_FONT) or ""

    local meta = {}
    if e.author and e.author ~= "" then meta[#meta + 1] = e.author end
    if e.duration then meta[#meta + 1] = format_clock(e.duration) end

    local lines = {
        string.format("{\\an7\\pos(%d,%d)\\fs%d\\bord2\\shad0\\q2%s%s\\b1}%s  %s",
            pad, pad, s.heading, fn, colr("green"), ICON.playing,
            ass_escape(utf8_truncate(e.title or "", 64))),
    }
    if #meta > 0 then
        lines[#lines + 1] = string.format(
            "{\\an7\\pos(%d,%d)\\fs%d\\bord2\\shad0\\q2%s%s}%s",
            pad, pad + math.floor(s.heading * 1.35), s.meta, fn, colr("dark5"),
            ass_escape(table.concat(meta, "  ·  ")))
    end

    title_ov.res_x, title_ov.res_y = math.floor(res_y * 16 / 9), res_y
    title_ov.data = table.concat(lines, "\n")
    title_ov:update()

    if title_timer then title_timer:kill() end
    title_timer = mp.add_timeout(opts.title_overlay_seconds, hide_title_card)
end

-- Attribute progress to whatever is playing, including items that reached the
-- player through the playlist rather than through Enter.
mp.register_event("file-loaded", function()
    local path = mp.get_property("path")
    local e = entry_by_url(path) or (path and fallback.entry[path])
    start_tracking(e)
    -- An unseekable network stream has no end to measure against, so it is a
    -- broadcast. Streams that do allow seeking are caught by the duration
    -- growth check in sample_progress instead.
    if mp.get_property_bool("demuxer-via-network")
        and mp.get_property_bool("seekable") == false then
        track.live = true
    end
    if e then show_title_card(e) end
end)

-- Fallback for servers mpv cannot stream from (see download_fallback above).
local pump_fallback   -- forward declaration, the worker recurses through the queue

local function play_downloaded(e)
    local url = e.url
    local ext = url:match("%.(%w%w%w%w?)%f[%W]") or "mp3"
    local out = temp_path("." .. ext)
    fallback.tried[url] = true
    mp.osd_message("RSS: this server blocks streaming — downloading episode…", 8)
    msg.info("direct playback failed, downloading " .. url)
    download(url, out, function(ok, err)
        if not ok then
            os.remove(out)
            mp.osd_message("RSS: download failed — " .. tostring(err), 6)
            fallback.busy = false
            pump_fallback()
            return
        end
        fallback.files[#fallback.files + 1] = out
        fallback.entry[out] = e
        mp.osd_message("RSS: playing  " .. (e.title or ""), 4)
        -- named arguments: a title containing a comma would corrupt the
        -- positional key/value list form
        local o = { ["force-media-title"] = e.title or "" }
        local pos = resume_pos(e.id)
        if pos then o["start"] = string.format("%d", math.floor(pos)) end
        -- Replacing the playlist is right for the single episode Enter failed
        -- on, but it would throw away the rest of a queue whose every item is
        -- failing the same way, so anything beyond that is appended instead.
        local count = mp.get_property_number("playlist-count") or 0
        local flag
        if not mp.get_property_bool("idle-active") then flag = "append"
        elseif count > 1 then flag = "append-play"
        else flag = "replace" end
        mp.command_native({ name = "loadfile", url = out, flags = flag, options = o })
        fallback.busy = false
        pump_fallback()
    end, true)
end

-- A feed whose server refuses mpv fails every queued episode at once, within a
-- couple of seconds. Fetching them all in parallel would saturate the link
-- with tens of megabytes apiece, so they go through one at a time.
pump_fallback = function()
    if fallback.busy then return end
    local e = table.remove(fallback.queue, 1)
    if not e then return end
    fallback.busy = true
    play_downloaded(e)
end

mp.register_event("end-file", function(ev)
    local reason = ev and ev.reason
    -- Blame whatever mpv actually had open. last_played only ever covers the
    -- item Enter started, so keying off it alone left every queued episode
    -- unhandled: a feed whose server refuses mpv failed its whole queue in
    -- silence, with no message and no fallback.
    local failed = last_played
        or (fallback.opened and (entry_by_url(fallback.opened) or fallback.entry[fallback.opened]))
    local title = (failed and failed.title) or track.title
    if reason == "error" and title then
        mp.osd_message("RSS: playback failed — " .. title, 5)
    end
    if track.id then finish_tracking(reason == "eof") end
    last_played = nil

    -- a media enclosure that would not open directly: fetch it and retry once
    if reason == "error" and opts.download_fallback and failed and failed.url
        and failed.media_url == failed.url and not fallback.tried[failed.url] then
        fallback.queue[#fallback.queue + 1] = failed
        pump_fallback()
    end
end)

mp.register_event("shutdown", function()
    for _, f in ipairs(fallback.files) do os.remove(f) end
end)

-- keep-open parks the player paused on the last frame instead of closing the
-- file, and that is an ordinary pause: it outlives the loadfile that follows,
-- so the next video would sit frozen on frame 0. Remember the park and clear
-- it when something new starts. Only mpv's own end-of-file pause is cleared --
-- a pause you set yourself is left alone.
local parked_at_eof = false

mp.observe_property("eof-reached", "bool", function(_, v)
    if v then parked_at_eof = true end
end)

-- Playing something new from the browser should start it, not hold a frame
-- from the file that just ended.
mp.register_event("start-file", function()
    fallback.opened = mp.get_property("path")
    if parked_at_eof then
        parked_at_eof = false
        mp.set_property_bool("pause", false)
    end
    if ui.active then mp.set_property("keep-open", "yes") end
end)

mp.register_event("shutdown", function()
    if track.id then finish_tracking(false) end
end)

-- Playback ---------------------------------------------------------------

local function playable(e)
    if not e then return false end
    if not e.url or not is_valid_url(e.url) then
        status("RSS: item has no usable URL", 5, "red")
        return false
    end
    if is_youtube_url(e.url) and ytdl_available == false then
        status("RSS: yt-dlp not available — install it with:  winget install yt-dlp.yt-dlp", 8, "red")
        return false
    end
    return true
end

local function play_entry(e)
    if not playable(e) then return end

    if opts.mark_watched_on_play then
        set_watched(e.id, true)
        save_state()
    end
    last_played = e
    close_menu()

    -- mpv's own ytdl_hook resolves YouTube URLs; nothing is downloaded here.
    local pos = resume_pos(e.id)
    if pos then
        mp.osd_message(string.format("RSS: loading  %s   (resuming at %s)",
            e.title or e.url, format_clock(pos)), 4)
        -- loadfile: url, flags, index, options
        mp.commandv("loadfile", e.url, "replace", "0",
            "start=" .. string.format("%d", math.floor(pos)))
    else
        mp.osd_message("RSS: loading  " .. (e.title or e.url), 4)
        mp.commandv("loadfile", e.url, "replace")
    end
end

-- Spotify-style queueing: "queue" appends to the end of the playlist,
-- "next" inserts directly after the current item. Neither interrupts what is
-- playing, and the browser stays open so several items can be added in a row.
local function queue_entry(e, mode)
    if not playable(e) then return end
    local idle = mp.get_property_bool("idle-active")
    -- Sitting on the last frame is not the same as idle-active: the finished
    -- file is still loaded, so mpv does not consider itself idle.
    local parked = not idle and (mp.get_property_bool("eof-reached") or false)
    local flag
    if mode == "next" then
        flag = idle and "insert-next-play" or "insert-next"
    else
        flag = idle and "append-play" or "append"
    end
    mp.commandv("loadfile", e.url, flag)
    -- Parked on the last frame, mpv still counts the finished video as the
    -- current playlist entry, so the -play flags decline to start anything and
    -- the item would wait behind a video that never advances. Step off it by
    -- hand; what was just added is what comes next. (start-file lifts the
    -- end-of-file pause that goes with the park.)
    if parked then mp.commandv("playlist-next") end
    local n = mp.get_property_number("playlist-count") or 0
    -- playing next is a playback action (orange); adding to the queue uses the
    -- same teal a queued row does
    status(string.format("RSS: %s · %s   [playlist: %d]",
        mode == "next" and "plays next" or "queued",
        utf8_truncate(e.title or "", 44), n), 4,
        mode == "next" and "orange" or "teal")
    rebuild_rows()
    render()
end

--==========================================================================
-- 13. FEED MANAGEMENT (add / remove)
--==========================================================================

local function youtube_feed_url(channel_id)
    return "https://www.youtube.com/feeds/videos.xml?channel_id=" .. channel_id
end

local function add_feed(url, name)
    if not is_valid_url(url) then
        status("RSS: not a usable http(s) URL", 5, "red")
        return
    end
    if feed_by_url(url) then
        status("RSS: feed already in the list")
        return
    end
    local feed = { name = name or url, url = url, enabled = true }
    feeds[#feeds + 1] = feed
    save_feeds()
    status("RSS: added " .. feed.name, 5, "green")
    refresh_feeds({ feed })
end

-- Turn whatever the user pasted into a feed URL. Channel IDs need no API key;
-- @handles are resolved by scraping the channel page (still no API key).
local function add_from_input(input)
    input = trim(tostring(input or ""))
    input = input:gsub('^["\']', ""):gsub('["\']$', "")
    if input == "" then
        status("RSS: clipboard is empty")
        return
    end

    -- Lua patterns have no {n,m} quantifier, so a bare channel id is length
    -- checked instead of being matched with a repetition count.
    local bare = input:match("^(UC[%w_%-]+)$")
    if bare and (#bare < 20 or #bare > 26) then bare = nil end

    local cid = input:match("[%?&]channel_id=(UC[%w_%-]+)")
        or input:match("youtube%.com/channel/(UC[%w_%-]+)")
        or bare
    if cid then
        add_feed(youtube_feed_url(cid))
        return
    end

    local list_id = input:match("[%?&]list=([%w_%-]+)")
    if list_id and input:find("youtube%.com") then
        add_feed("https://www.youtube.com/feeds/videos.xml?playlist_id=" .. list_id)
        return
    end

    -- @handle / /c/name / /user/name: fetch the page and read the channel id
    local is_handle = input:find("youtube%.com/@") or input:find("youtube%.com/c/")
        or input:find("youtube%.com/user/")
    if is_handle then
        if not is_valid_url(input) then
            status("RSS: handle URL looks malformed", 5, "red")
            return
        end
        status("RSS: resolving channel ID…", 10)
        fetch(input, function(body, err)
            if not body then
                status("RSS: could not resolve handle (" .. tostring(err)
                    .. ") — use the channel_id feed URL instead", 8, "red")
                return
            end
            local id = body:match('"channelId"%s*:%s*"(UC[%w_%-]+)"')
                or body:match("channel/(UC[%w_%-]+)")
                or body:match("channel_id=(UC[%w_%-]+)")
            if id then
                add_feed(youtube_feed_url(id))
            else
                status("RSS: no channel ID on that page — use .../feeds/videos.xml?channel_id=UC…", 8, "red")
            end
        end)
        return
    end

    if not is_valid_url(input) then
        status("RSS: not a usable URL", 5, "red")
        return
    end

    -- A plain site URL may be a feed, or an HTML page that points at one.
    -- Fetch it once: if it parses as a feed, use it; otherwise look for an
    -- autodiscovery <link rel="alternate" type="application/rss+xml" href="…">.
    status("RSS: checking feed…", 10)
    fetch(input, function(body, err)
        if not body then
            status("RSS: could not fetch — " .. tostring(err), 8, "red")
            return
        end
        if parse_feed(body) then
            add_feed(input)
            return
        end
        local href
        for tag in body:gmatch("<link[%s][^>]*>") do
            local t = tag:lower()
            if t:find('rel%s*=%s*"?alternate') and
                (t:find("application/rss%+xml") or t:find("application/atom%+xml")) then
                href = tag:match('href%s*=%s*"([^"]*)"') or tag:match("href%s*=%s*'([^']*)'")
                if href then break end
            end
        end
        if not href then
            status("RSS: that page is not a feed and advertises none — "
                .. "paste the feed URL itself", 9, "red")
            return
        end
        href = trim(decode_text(href))
        if href:match("^//") then
            href = (input:match("^(https?:)") or "https:") .. href
        elseif href:match("^/") then
            href = (input:match("^(https?://[^/]+)") or input) .. href
        elseif not href:match("^https?://") then
            href = input:gsub("/[^/]*$", "/") .. href
        end
        if is_valid_url(href) then
            add_feed(href)
        else
            status("RSS: found a feed link but could not read it", 8, "red")
        end
    end)
end

local function clipboard_text()
    local ok, text = pcall(mp.get_property, "clipboard/text")
    if not ok or type(text) ~= "string" then return nil end
    -- a pasted URL often arrives with a trailing newline
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Accepts several URLs at once, whitespace or newline separated, so a list
-- copied out of a text file can go in with one paste.
local function add_feeds_from_text(text)
    local urls = {}
    for tok in tostring(text or ""):gmatch("%S+") do urls[#urls + 1] = tok end
    if #urls == 0 then
        status("RSS: nothing to add", 4, "red")
        return
    end
    if #urls > 1 then
        status(string.format("RSS: adding %d feeds…", #urls), 8)
    end
    for _, u in ipairs(urls) do add_from_input(u) end
end

--------------------------------------------------------------------------
-- Editing rss-feeds.json in a real editor
--------------------------------------------------------------------------

-- A deliberate hand edit replaces the list outright, unlike the merge used
-- elsewhere: renames and deletions in the file have to win.
local function reload_feeds_full()
    removed_urls = {}
    load_feeds()
    rebuild_rows()
    render()
end

local editor_watch = nil

local function stop_editor_watch()
    if editor_watch then
        editor_watch:kill()
        editor_watch = nil
    end
end

-- The editor runs in its own window, so there is no reliable moment to "wait"
-- for it. Watch the file instead: the moment it is written, pick it up.
local function watch_feeds_file()
    stop_editor_watch()
    local before = file_read(PATHS.feeds)
    local deadline = os.time() + 900
    editor_watch = mp.add_periodic_timer(2, function()
        local current = file_read(PATHS.feeds)
        if current and current ~= before then
            stop_editor_watch()
            reload_feeds_full()
            status("RSS: rss-feeds.json reloaded", 5, "green")
            refresh_all()
        elseif os.time() > deadline then
            stop_editor_watch()
        end
    end)
end

local function open_feeds_in_editor()
    local path = PATHS.feeds
    if not file_read(path) then write_json(path, { feeds = {} }) end

    local function launch(args, on_fail)
        mp.command_native_async({
            name = "subprocess", args = args,
            playback_only = false,          -- must outlive an idle player
            capture_stdout = true, capture_stderr = true,
        }, function(success, res)
            if (not success or (res and res.status ~= 0)) and on_fail then on_fail() end
        end)
    end

    if opts.editor ~= "" and opts.editor ~= "auto" then
        launch({ opts.editor, path })
    else
        -- Windows Terminal first; if it is not there, a plain console window
        launch({ "wt.exe", "nvim", path }, function()
            msg.verbose("wt.exe unavailable, falling back to a console window")
            launch({ "cmd.exe", "/c", "start", "", "nvim", path })
        end)
    end
    status("RSS: editing rss-feeds.json — save in the editor and it reloads here", 8)
    watch_feeds_file()
    render()
end

local function remove_feed(feed)
    removed_urls[feed.url] = true   -- so the merge cannot bring it back
    for i, f in ipairs(feeds) do
        if f.url == feed.url then
            table.remove(feeds, i)
            break
        end
    end
    cache[feed.url] = nil
    feed_errors[feed.url] = nil
    save_feeds()
    save_cache()
    status("RSS: removed " .. feed.name, 5, "green")
end

--==========================================================================
-- 14. NAVIGATION
--==========================================================================

local function current_row() return ui.rows[ui.sel] end

local function move(delta)
    if #ui.rows == 0 then return end
    ui.sel = clamp(ui.sel + delta, 1, #ui.rows)
    rebuild_rows()
    render()
end

-- Full technical error for one feed (§8 keeps it out of the list itself).
local function open_error_view(feed)
    if not feed then return end
    ui.prev_view = { view = ui.view, sel = ui.sel, scroll = ui.scroll }
    ui.view = "error"
    ui.error_feed = feed
    ui.sel, ui.scroll = 1, 0
    rebuild_rows()
    render()
end

-- Every binding, grouped, so the keys are discoverable without the README.
local function open_help_view()
    ui.prev_view = { view = ui.view, sel = ui.sel, scroll = ui.scroll }
    ui.view = "help"
    ui.sel, ui.scroll = 1, 0
    rebuild_rows()
    render()
end

local TABS = { "all", "videos", "podcasts" }

-- A number cycles (Tab / Shift+Tab); a tab name goes straight there (keys 1-3).
local function switch_tab(delta)
    local i = 1
    for n, t in ipairs(TABS) do if t == ui.tab then i = n break end end
    if type(delta) == "string" then
        for n, t in ipairs(TABS) do if t == delta then i = n break end end
    else
        i = ((i - 1 + delta) % #TABS) + 1
    end
    ui.tab = TABS[i]
    ui.view = "feeds"          -- a tab switch always lands on its feed list
    ui.sel, ui.scroll, ui.filter = 1, 0, ""
    ui.prev_view = nil
    rebuild_rows()
    -- the narrow layout shows one section at a time, so name the one you
    -- just landed on -- the tab bar cannot
    if ui.narrow then
        status(string.format("%d/%d  %s", i, #TABS, ui.tab:upper()), 2, "blue")
    end
    render()
end

-- The "New" row: only items never started, across the whole tab.
local function open_new_view()
    local out = {}
    for _, e in ipairs(entries_for_tab(ui.tab)) do
        if item_state(e.id) == "unseen" then out[#out + 1] = e end
    end
    ui.feed_url, ui.only_new = nil, true
    ui.feed_label = "NEW"
    ui.entries = out
    ui.view = "entries"
    ui.sel, ui.scroll, ui.filter = 1, 0, ""
    rebuild_rows()
    render()
end

local function open_feed_view(feed)
    ui.only_new = false
    if feed then
        ui.feed_url = feed.url
        ui.feed_label = feed.name
        ui.entries = entries_for_feed(feed.url)
    else
        ui.feed_url = nil
        ui.feed_label = (ui.tab == "videos" and "ALL VIDEOS")
            or (ui.tab == "podcasts" and "ALL EPISODES")
            or "ALL ITEMS"
        ui.entries = entries_for_tab(ui.tab)
    end
    ui.view = "entries"
    ui.sel, ui.scroll, ui.filter = 1, 0, ""
    rebuild_rows()
    render()
end

-- The playlist view is a side panel on top of whatever view you were in.
local function open_playlist_view()
    local count = mp.get_property_number("playlist-count") or 0
    if count == 0 then
        status(string.format("RSS: playlist is empty — queue videos with %s or %s",
            opts.key_queue, opts.key_play_next), 5)
        return
    end
    ui.prev_view = { view = ui.view, sel = ui.sel, scroll = ui.scroll }
    ui.view = "playlist"
    ui.sel, ui.scroll = 1, 0
    rebuild_rows()
    -- start on the item that is playing
    for i, row in ipairs(ui.rows) do
        if row.current then ui.sel = i break end
    end
    rebuild_rows()
    render()
end

local function leave_playlist_view()
    local prev = ui.prev_view or { view = "feeds", sel = 1, scroll = 0 }
    ui.prev_view = nil
    ui.view = prev.view
    ui.sel, ui.scroll = prev.sel or 1, prev.scroll or 0
    rebuild_rows()
    render()
end

local function remove_playlist_item()
    local row = current_row()
    if ui.view ~= "playlist" or not row or row.kind ~= "pl" then return end
    mp.commandv("playlist-remove", tostring(row.index))
    rebuild_rows()
    ui.sel = clamp(ui.sel, 1, math.max(1, #ui.rows))
    if #ui.rows == 0 then
        status("RSS: playlist cleared")
        leave_playlist_view()
        return
    end
    rebuild_rows()
    render()
end

local function activate()
    local row = current_row()
    if not row then return end
    if row.kind == "pl" then
        mp.commandv("playlist-play-index", tostring(row.index))
        close_menu()
        mp.osd_message("RSS: playing  " .. (row.label or ""), 3)
        return
    end
    if row.kind == "new" then
        open_new_view()
    elseif row.kind == "all" then
        open_feed_view(nil)
    elseif row.kind == "feed" then
        -- a feed that failed and has nothing cached has no list to show, so
        -- open the error instead of an empty page
        if feed_errors[row.feed.url] and not cache[row.feed.url] then
            open_error_view(row.feed)
            return
        end
        if not cache[row.feed.url] and not refresh_state.active then
            refresh_feeds({ row.feed })
        end
        open_feed_view(row.feed)
    elseif row.kind == "entry" then
        play_entry(row.entry)
    end
end

local function back()
    if ui.filter_editing then
        ui.filter_editing = false
        ui.filter = ""
        rebuild_rows()
        render()
        return
    end
    if ui.view == "playlist" or ui.view == "help" or ui.view == "error" then
        leave_playlist_view()      -- restores whatever view we came from
        return
    end
    if ui.view == "entries" then
        if ui.filter ~= "" then
            ui.filter = ""
            rebuild_rows()
            render()
            return
        end
        ui.view = "feeds"
        ui.sel, ui.scroll = 1, 0
        rebuild_rows()
        render()
    else
        close_menu()
    end
end

--==========================================================================
-- 15. KEY BINDINGS
--==========================================================================
-- Menu keys are forced bindings that exist only while the browser is open, so
-- q / Esc / r / j / k behave exactly like stock mpv the rest of the time.

local menu_binding_names = {}
local filter_binding_names = {}

local function bind(list, key, name, fn, flags)
    local full = "rss-" .. name
    mp.add_forced_key_binding(key, full, fn, flags)
    list[#list + 1] = full
end

local function unbind(list)
    for _, name in ipairs(list) do mp.remove_key_binding(name) end
    for i = #list, 1, -1 do list[i] = nil end
end

-- m marks one item, or -- on a feed or on the "all" row -- the whole lot.
-- Pressing it again on a fully watched feed makes it new again.
local function toggle_watched()
    local row = current_row()
    if not row then return end

    if row.kind == "entry" or row.kind == "pl" then
        local e = row.entry
        if not e then return end
        set_watched(e.id, not is_watched(e.id))
        save_state()
        rebuild_rows()
        render()
        return
    end

    local list, label
    if row.kind == "feed" then
        list, label = entries_for_feed(row.feed.url), row.feed.name
    elseif row.kind == "all" or row.kind == "new" then
        list, label = entries_for_tab(ui.tab), row.label
    else
        return
    end
    if #list == 0 then
        status("RSS: nothing cached for this feed yet", 3)
        return
    end

    local mark = new_count(list) > 0   -- anything still new -> mark the lot watched
    for _, e in ipairs(list) do set_watched(e.id, mark) end
    save_state()
    status(string.format("%s · %s  (%d items)", label,
        mark and "feed watched" or "new", #list), 4,
        mark and "comment" or "purple")
    rebuild_rows()
    render()
end

local function refresh_current()
    if ui.view == "error" then
        if ui.error_feed then refresh_feeds({ ui.error_feed }) end
        return
    end
    if ui.view == "feeds" then
        local row = current_row()
        if row and row.kind == "feed" then refresh_feeds({ row.feed }) else refresh_all() end
    else
        if ui.feed_url then
            local f = feed_by_url(ui.feed_url)
            if f then refresh_feeds({ f }) end
        else
            refresh_all()
        end
    end
end

local function delete_current()
    local row = current_row()
    if ui.view ~= "feeds" or not row or row.kind ~= "feed" then
        status("RSS: select a feed to remove")
        return
    end
    ui.confirm_delete = row.feed
    render()
end

local function handle_confirm(yes)
    local feed = ui.confirm_delete
    ui.confirm_delete = nil
    if yes and feed then
        remove_feed(feed)
        rebuild_rows()
    end
    render()
end

--------------------------------------------------------------------------
-- One-line text input, used both for the filter and for pasting feed URLs.
-- While it is open the menu keys are unbound, so every printable key is text.
--------------------------------------------------------------------------

local input = ui.input    -- lives on ui so render() can see it
local register_input_bindings, unregister_input_bindings
local register_menu_bindings

local function start_input(spec)
    input.label = spec.label or ""
    input.icon = spec.icon
    input.buf = spec.initial or ""
    input.on_change = spec.on_change
    input.on_commit = spec.on_commit
    ui.filter_editing = true          -- the flag layout and render look at
    unbind(menu_binding_names)
    register_input_bindings()
    rebuild_rows()
    render()
end

local function stop_input(commit)
    local buf, fn = input.buf, input.on_commit
    ui.filter_editing = false
    input.on_change, input.on_commit = nil, nil
    unregister_input_bindings()
    register_menu_bindings()
    if commit and fn then fn(buf) end
    rebuild_rows()
    render()
end

local function input_changed()
    if input.on_change then input.on_change(input.buf) end
    rebuild_rows()
    render()
end

register_input_bindings = function()
    -- "any_unicode" delivers printable keys as event.key_text; the specific
    -- bindings below take precedence over it.
    bind(filter_binding_names, "any_unicode", "input-type", function(ev)
        if not ev or ev.event == "up" then return end
        local t = ev.key_text
        if type(t) ~= "string" or t == "" then return end
        if t:byte(1) < 32 then return end
        input.buf = input.buf .. t
        input_changed()
    end, { complex = true, repeatable = true })

    bind(filter_binding_names, "bs", "input-bs", function()
        local s = input.buf          -- drop one UTF-8 character, not one byte
        while #s > 0 do
            local b = s:byte(#s)
            s = s:sub(1, #s - 1)
            if b < 128 or b >= 192 then break end
        end
        input.buf = s
        input_changed()
    end, { repeatable = true })

    -- paste, for when the clipboard changed after the field was opened
    bind(filter_binding_names, "ctrl+v", "input-paste", function()
        local t = clipboard_text()
        if t and t ~= "" then
            input.buf = (input.buf ~= "" and (input.buf .. " ") or "") .. t
            input_changed()
        else
            status("RSS: clipboard is empty", 3)
            render()
        end
    end)
    bind(filter_binding_names, "ctrl+u", "input-clear", function()
        input.buf = ""
        input_changed()
    end)

    bind(filter_binding_names, "enter", "input-enter", function() stop_input(true) end)
    bind(filter_binding_names, "kp_enter", "input-kpenter", function() stop_input(true) end)
    bind(filter_binding_names, "esc", "input-esc", function() stop_input(false) end)
end

unregister_input_bindings = function()
    unbind(filter_binding_names)
end

local function start_filter()
    if ui.view ~= "entries" then return end
    start_input({
        label = "Filter", icon = ICON.search, initial = ui.filter,
        on_change = function(s) ui.filter = s end,
    })
end

local function start_add_feed()
    local clip = clipboard_text()
    start_input({
        label = "Add feed", icon = ICON.author,
        initial = clip or "",
        on_commit = add_feeds_from_text,
    })
    if not clip or clip == "" then
        status("RSS: clipboard empty — type or paste a URL, Ctrl+V pastes", 6)
        render()
    end
end

register_menu_bindings = function()
    local function guarded(fn)
        -- while a delete confirmation is up, any key other than y cancels it
        return function(...)
            if ui.confirm_delete then handle_confirm(false) return end
            fn(...)
        end
    end

    -- TAB / Shift+TAB switch tabs; neither is bound by mpv by default
    bind(menu_binding_names, "tab", "tab", guarded(function() switch_tab(1) end))
    bind(menu_binding_names, "shift+tab", "shifttab", guarded(function() switch_tab(-1) end))
    -- 1-3 pick a section outright. mpv binds the digits to contrast/brightness;
    -- these are forced bindings and are removed again when the browser closes.
    for i = 1, #TABS do
        local name = TABS[i]
        bind(menu_binding_names, tostring(i), "tab" .. i,
            guarded(function() switch_tab(name) end))
    end

    bind(menu_binding_names, "up", "up", guarded(function() move(-1) end), { repeatable = true })
    bind(menu_binding_names, "down", "down", guarded(function() move(1) end), { repeatable = true })
    bind(menu_binding_names, "k", "k", guarded(function() move(-1) end), { repeatable = true })
    bind(menu_binding_names, "j", "j", guarded(function() move(1) end), { repeatable = true })
    bind(menu_binding_names, "pgup", "pgup", guarded(function() move(-page_size()) end), { repeatable = true })
    bind(menu_binding_names, "pgdwn", "pgdwn", guarded(function() move(page_size()) end), { repeatable = true })
    bind(menu_binding_names, "home", "home", guarded(function() ui.sel = 1 rebuild_rows() render() end))
    bind(menu_binding_names, "end", "end", guarded(function() ui.sel = #ui.rows rebuild_rows() render() end))

    bind(menu_binding_names, "enter", "enter", guarded(activate))
    bind(menu_binding_names, "kp_enter", "kpenter", guarded(activate))
    bind(menu_binding_names, "right", "right", guarded(activate))

    bind(menu_binding_names, "esc", "esc", guarded(back))
    bind(menu_binding_names, "left", "left", guarded(back))
    bind(menu_binding_names, "bs", "bs", guarded(back))

    bind(menu_binding_names, "q", "q", guarded(function() close_menu() end))
    bind(menu_binding_names, "r", "r", guarded(refresh_current))
    bind(menu_binding_names, "R", "R", guarded(refresh_all))
    bind(menu_binding_names, "m", "m", guarded(toggle_watched))
    bind(menu_binding_names, "a", "a", guarded(start_add_feed))
    bind(menu_binding_names, opts.key_edit, "editfeeds", guarded(open_feeds_in_editor))

    -- Spotify-style queueing, plus index numbers.
    local function on_entry(fn, complaint)
        return guarded(function()
            local row = current_row()
            if row and row.kind == "entry" then fn(row.entry) else status(complaint) end
        end)
    end
    bind(menu_binding_names, opts.key_queue, "queue",
        on_entry(function(e) queue_entry(e, "append") end, "RSS: select a video to queue"))
    bind(menu_binding_names, opts.key_play_next, "playnext",
        on_entry(function(e) queue_entry(e, "next") end, "RSS: select a video to play next"))
    -- the playlist/queue view, numbered
    bind(menu_binding_names, opts.key_index, "index", guarded(function()
        if ui.view == "playlist" then leave_playlist_view() else open_playlist_view() end
    end))
    bind(menu_binding_names, "/", "slash", guarded(start_filter))
    bind(menu_binding_names, "v", "hideseen", guarded(function()
        ui.hide_seen = not ui.hide_seen
        ui.sel, ui.scroll = 1, 0
        rebuild_rows()
        status(ui.hide_seen and "RSS: watched items hidden"
            or "RSS: showing everything", 3, ui.hide_seen and "cyan" or "fg")
        render()
    end))
    bind(menu_binding_names, "?", "help", guarded(function()
        if ui.view == "help" then leave_playlist_view() else open_help_view() end
    end))
    bind(menu_binding_names, "e", "errorview", guarded(function()
        local row = current_row()
        if row and row.kind == "feed" and feed_errors[row.feed.url] then
            open_error_view(row.feed)
        else
            status("RSS: no error on this feed")
        end
    end))
    bind(menu_binding_names, "d", "d", function()
        if ui.confirm_delete then handle_confirm(true)
        elseif ui.view == "playlist" then remove_playlist_item()
        else delete_current() end
    end)
    bind(menu_binding_names, "y", "y", function()
        if ui.confirm_delete then handle_confirm(true) end
    end)
end

--==========================================================================
-- 16. OPEN / CLOSE
--==========================================================================

local function on_osd_dimensions()
    if ui.active then render() end
end

-- mpv's own keep-open, borrowed for as long as the browser is on screen.
local saved_keep_open = nil

local function hold_last_frame(enable)
    if not opts.keep_open_in_menu then return end
    if enable then
        if saved_keep_open == nil then
            saved_keep_open = mp.get_property("keep-open") or "no"
        end
        mp.set_property("keep-open", "yes")
    elseif saved_keep_open ~= nil then
        mp.set_property("keep-open", saved_keep_open)
        saved_keep_open = nil
    end
end

local function open_menu()
    if ui.active then return end
    ui.active = true
    hold_last_frame(true)
    ui.view = "feeds"
    ui.sel, ui.scroll = 1, 0
    ui.filter, ui.filter_editing, ui.confirm_delete = "", false, nil
    register_menu_bindings()
    -- keep the panel undistorted when the window is resized
    mp.observe_property("osd-dimensions", "native", on_osd_dimensions)
    reload_feeds()   -- adopt feeds added to the file while mpv was running
    rebuild_rows()
    render()
    if opts.refresh_on_open then refresh_stale() end
end

close_menu = function()
    if not ui.active then return end
    ui.active = false
    hold_last_frame(false)
    ui.filter_editing = false
    ui.confirm_delete = nil
    ui.prev_view = nil
    unbind(menu_binding_names)
    unbind(filter_binding_names)
    mp.unobserve_property(on_osd_dimensions)
    thumbs.want = nil
    hide_thumb()
    overlay:remove()
end

local function toggle_menu()
    if ui.active then close_menu() else open_menu() end
end

--==========================================================================
-- 17. TROUBLESHOOTING HELPER
--==========================================================================
-- --script-opts=rss-debug_parse=<file-or-url> parses one feed at startup and
-- logs what the parser saw. Also available as: script-message rss-debug-parse

local function debug_parse(target)
    local function report(body, err)
        if not body then
            msg.error("debug_parse: fetch failed: " .. tostring(err))
            return
        end
        msg.info(string.format("debug_parse: %d bytes from %s", #body, target))
        local ok, parsed, perr = pcall(parse_feed, body)
        if not ok then
            msg.error("debug_parse: parser crashed: " .. tostring(parsed))
            return
        end
        if not parsed then
            msg.info("debug_parse: no feed -- " .. tostring(perr))
            return
        end
        msg.info(string.format("debug_parse: kind=%s title=%q entries=%d",
            parsed.kind, tostring(parsed.title), #parsed.entries))
        for i, e in ipairs(parsed.entries) do
            if i > 5 then
                msg.info(string.format("debug_parse: ... %d more", #parsed.entries - 5))
                break
            end
            msg.info(string.format("debug_parse: [%d] id=%s date=%d (%s)\n  title=%s\n  url=%s\n  desc=%s",
                i, tostring(e.id), e.date or 0, format_date(e.date),
                tostring(e.title), tostring(e.url),
                tostring(e.desc and utf8_truncate(e.desc, 60) or "-")))
        end
    end

    target = trim(target or "")
    if target == "" then return end
    if target:match("^https?://") then
        fetch(target, report)
    else
        local path = target:gsub("^file:///", ""):gsub("^file://", "")
        local body = file_read(path)
        if not body then
            msg.error("debug_parse: cannot read " .. path)
            return
        end
        report(body, nil)
    end
end

--==========================================================================
-- 18. INIT
--==========================================================================

math.randomseed(os.time())

ui.hide_seen = opts.hide_watched ~= false

load_feeds()
load_cache()
load_state()
-- create the data files on first run so they exist and are easy to inspect
if not file_read(PATHS.cache) then save_cache() end
if not file_read(PATHS.state) then save_state() end
probe_http_backend()
probe_ytdl()
probe_ffmpeg()
probe_font()

mp.add_key_binding(opts.key_open ~= "" and opts.key_open or nil, "toggle", toggle_menu)

-- samples playback position for the partially-watched state; no-ops when
-- nothing from a feed is playing
mp.add_periodic_timer(5, sample_progress)

mp.register_script_message("rss-open", function() if not ui.active then open_menu() end end)
mp.register_script_message("rss-close", close_menu)
mp.register_script_message("rss-toggle", toggle_menu)
mp.register_script_message("rss-refresh", refresh_all)
mp.register_script_message("rss-add-feed", function(url) add_from_input(url) end)
mp.register_script_message("rss-debug-parse", function(t) debug_parse(t) end)

if opts.debug_parse ~= "" then
    debug_parse(opts.debug_parse)
end

if opts.auto_open then
    -- wait for the window/OSD to exist before drawing
    mp.add_timeout(0.4, function()
        if not ui.active then open_menu() end
    end)
end

msg.verbose(string.format("%s ready (feeds=%s cache=%s state=%s)",
    SCRIPT_NAME, PATHS.feeds, PATHS.cache, PATHS.state))
