local update_timer = nil
local write_status_enabled = mp.get_opt("write_status") == "yes"

local function status_file_path()
    local home = os.getenv("TMPDIR") or os.getenv("HOME") or "/data/data/com.termux/files/home"
    return home .. "/mpv_pause_status"
end

local function escape(s)
    return s:gsub('\\', '\\\\'):gsub('"', '\\"')
end

local function fmt_time(s)
    local m = math.floor(s / 60)
    local sec = math.floor(s % 60)
    return string.format("%d:%02d", m, sec)
end

local function write_status()
    if not write_status_enabled then return end
    local paused = mp.get_property_bool("pause")
    local title = mp.get_property("media-title") or mp.get_property("filename") or "Unknown"
    local artist = mp.get_property("metadata/by-key/artist") or mp.get_property("metadata/by-key/uploader") or ""
    local vol = math.floor(mp.get_property_number("volume", 0))
    local duration = mp.get_property_number("duration") or 0
    local position = mp.get_property_number("playback-time") or 0

    local f = io.open(status_file_path(), "w")
    if f then
        f:write(string.format(
            '{"paused":%s,"title":"%s","artist":"%s","volume":%d,"position":"%s","duration":"%s"}',
            paused and "true" or "false",
            escape(title),
            escape(artist),
            vol,
            fmt_time(position),
            fmt_time(duration)
        ))
        f:close()
    end
end

local function show_notification()
    local paused = mp.get_property_bool("pause")
    local title = mp.get_property("media-title") or mp.get_property("filename") or "Unknown"
    local artist = mp.get_property("metadata/by-key/artist") or mp.get_property("metadata/by-key/uploader") or "Music"
    local vol = math.floor(mp.get_property_number("volume", 0))

    local function tmux(key)
        return ("tmux send-keys -t music '%s'"):format(key)
    end

    local b1_icon = paused and "⏮️ " or "➖ "
    local b2_icon = paused and " ▶️ " or " ⏸️ "
    local b3_icon = paused and " ⏭️ " or " ➕ "
    local title_text = "V: " .. vol .. "% |" .. string.rep("\u{00A0}", 1) .. artist

    mp.command_native_async({
        name = "subprocess",
        playback_only = false,
        args = {
            "termux-notification",
            "--id", "MPV",
            "--title", title_text,
            "--content", title,
            "--ongoing",
            "--priority", "high",
            "--alert-once",
            "--icon", "play_arrow",
            "--action", tmux("Q"),
            "--button1", b1_icon,
            "--button1-action", tmux(paused and "<" or "9"),
            "--button2", b2_icon,
            "--button2-action", tmux("p"),
            "--button3", b3_icon,
            "--button3-action", tmux(paused and ">" or "0")
        }
    })
end

local function save_to_library()
    local title = mp.get_property("media-title") or mp.get_property("filename") or "Unknown"
    local url = mp.get_property("path") or ""
    if url == "" then return end
    mp.command_native_async({
        name = "subprocess",
        playback_only = false,
        args = {"python3", os.getenv("HOME") .. "/projects/mpl/mpl.py", "add", title, url}
    })
    mp.osd_message("Saved: " .. title)
end

mp.add_key_binding("s", "save_to_library", save_to_library)

local function on_change(immediate)
    write_status()
    if update_timer then update_timer:kill() end
    if immediate then
        show_notification()
    else
        update_timer = mp.add_timeout(0.15, show_notification)
    end
end

mp.observe_property("pause",       "bool",   function() on_change(true)  end)
mp.observe_property("media-title", "string", function() on_change(false) end)
mp.observe_property("metadata",    "native", function() on_change(false) end)
mp.observe_property("volume",      "number", function() on_change(false) end)

mp.register_event("shutdown", function()
    os.execute("termux-notification-remove MPV")
end)

write_status()
