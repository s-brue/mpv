-- Frame generation controls: DLSS Frame Generation (dlssg_vulkan filter) and
-- NVIDIA Video Frame Generation (nvvfg_cuda filter). One at a time.
--
--   k    DLSS-G, rotate: off -> 2x -> 3x -> 4x -> 5x -> 6x -> off
--   h    NVIDIA video, rotate: off -> medium 2x -> high 2x -> medium 4x
--        -> high 4x -> medium 6x -> off (high is too slow for 6x)
--   a    NVIDIA Super Resolution up to the screen size, rotate: off -> for good
--        quality sources -> for compressed sources -> off
--
-- Super Resolution works together with NVIDIA video frame generation, not with
-- DLSS-G (they need different frames).
--
-- Factors the display cannot show are skipped.
--
-- Only what the graphics card supports can be used: at startup every filter is
-- tried on a few frames with the ffmpeg of mpv-dlssg (set MPVDLSSG_FFMPEG to use
-- another one). The keys of what is not supported do nothing, and its button is
-- dimmed. Without that ffmpeg nothing is checked. Sharpening works on any card.
--
-- Like any other mpv binding, these can be changed in input.conf:
--   k    script-binding dlssg/cycle
--   h    script-binding dlssg/nv
--   a    script-binding dlssg/sr
--
-- Also available, with no key by default:
--   script-binding dlssg/toggle   DLSS-G on/off, at the last factor used (at
--                                 first, the highest possible)
--   script-binding dlssg/off      frame generation off
--   script-binding dlssg/sr-off
--
-- For the buttons of the ModernZ interface, user-data/dlssg/factor holds the
-- DLSS-G factor (0 = off) and user-data/dlssg/nv the NVIDIA video one ("" = off,
-- else like "M2" or "H4") and user-data/dlssg/sr Super Resolution ("" = off,
-- "HQ" or "U"). user-data/dlssg/supported tells which of "fg", "nv" and "sr"
-- the graphics card can do.

local mp = require "mp"
local utils = require "mp.utils"

local MAX_FACTOR = 6
local NV_LEVELS = {
    {factor = 2, mode = "medium"}, {factor = 2, mode = "high"},
    {factor = 4, mode = "medium"}, {factor = 4, mode = "high"},
    {factor = 6, mode = "medium"},
}
-- what runs: nil, {kind = "fg", factor = n} or {kind = "nv", factor = n, mode, level}
local target = nil
local last = nil        -- DLSS-G factor the toggle comes back to
local saved_hwdec = nil -- set while a filter is in use
local pending = nil     -- timer waiting for the decoder

local SR_LEVELS = {
    {quality = "highbitrate_ultra", short = "HQ", name = "good quality source"},
    {quality = "ultra", short = "U", name = "compressed source"},
}
local sr = nil -- nil, or {level = n, width, height}

local LABELS = {fg = "dlssg", nv = "nvfg"}
local SR_LABEL = "nvsr"
-- copies software decoded frames to the GPU
local UPLOAD_LABEL = "dlssg-upload"
local upload = nil -- nil, or the sample format to upload

-- What the graphics card can do: fg is the highest DLSS-G factor (0 = none), nv
-- and sr are booleans. An entry is nil until it has been checked.
local caps = {}

local function publish_caps()
    mp.set_property_native("user-data/dlssg/supported",
                           {fg = (caps.fg or 0) > 0, nv = caps.nv == true, sr = caps.sr == true})
end

-- ffmpeg.exe beside mpv.exe on Windows, else ../../bin/ffmpeg from this script
local function find_ffmpeg()
    local given = os.getenv("MPVDLSSG_FFMPEG")
    if given and given ~= "" then return given end
    local path
    if mp.get_property("platform") == "windows" then
        path = mp.command_native({"expand-path", "~~exe_dir/ffmpeg.exe"})
    else
        local dir = debug.getinfo(1, "S").source:match("^@(.*)/") or "."
        path = dir .. "/../../bin/ffmpeg"
    end
    if utils.file_info(path) then return path end
end

-- Run a filter on two frames: it starts only if the card can do it.
local function try_filter(ffmpeg, device, filter, done)
    mp.command_native_async({
        name = "subprocess", playback_only = false, capture_stdout = true, capture_stderr = true,
        args = {ffmpeg, "-hide_banner", "-nostdin", "-v", "info",
                "-init_hw_device", device, "-filter_hw_device", "hw",
                "-f", "lavfi", "-i", "color=s=640x360:r=24",
                "-vf", "format=nv12,hwupload," .. filter, "-frames:v", "2", "-f", "null", "-"},
    }, function(success, result)
        local ok = success and result.status == 0
        local log = result and result.stderr or ""
        if not ok then mp.msg.verbose(filter .. " cannot be used:\n" .. log) end
        done(ok, log)
    end)
end

local function check_card()
    publish_caps()
    local ffmpeg = find_ffmpeg()
    if not ffmpeg then
        mp.msg.warn("ffmpeg of mpv-dlssg not found: not checking what the graphics card supports")
        caps = {fg = 6, nv = true, sr = true}
        publish_caps()
        return
    end
    local function found(kind, value)
        caps[kind] = value
        publish_caps()
        mp.msg.info(kind .. (value and value ~= 0 and " supported" or " not supported") ..
                    (kind == "fg" and value > 0 and " up to " .. value .. "x" or ""))
    end
    -- by name: the first Vulkan device need not be the NVIDIA one
    try_filter(ffmpeg, "vulkan=hw:NVIDIA", "dlssg_vulkan=factor=2", function(ok, log)
        found("fg", ok and (tonumber(log:match("GPU maximum (%d+)x")) or 2) or 0)
    end)
    try_filter(ffmpeg, "cuda=hw", "nvvfg_cuda=factor=2", function(ok) found("nv", ok) end)
    try_filter(ffmpeg, "cuda=hw", "nvvsr_cuda=w=1280:h=720", function(ok) found("sr", ok) end)
end

-- Whether a key may do anything.
local function supported(kind)
    if caps[kind] == nil then
        mp.osd_message("Checking what the graphics card supports...")
        return false
    end
    return caps[kind] ~= false and caps[kind] ~= 0
end

local function active(label)
    for _, f in ipairs(mp.get_property_native("vf") or {}) do
        if f.label == label then return true end
    end
    return false
end

local function remove_filters()
    for _, label in ipairs({UPLOAD_LABEL, LABELS.fg, LABELS.nv, SR_LABEL}) do
        if active(label) then mp.commandv("vf", "remove", "@" .. label) end
    end
end

local function publish()
    mp.set_property_native("user-data/dlssg/factor", target and target.kind == "fg" and target.factor or 0)
    local nv = ""
    if target and target.kind == "nv" then nv = target.mode:sub(1, 1):upper() .. target.factor end
    mp.set_property_native("user-data/dlssg/nv", nv)
    mp.set_property_native("user-data/dlssg/sr", sr and SR_LEVELS[sr.level].short or "")
end

-- Adding or removing a filter reconfigures the video output, and mpv would
-- then size the window anew: keep the size it has, however it was set.
local resize_setting, resize_timer = nil, nil
local function keep_window_size()
    if resize_timer then
        resize_timer:kill()
    else
        resize_setting = mp.get_property("auto-window-resize")
        mp.set_property("auto-window-resize", "no")
    end
    resize_timer = mp.add_timeout(3, function()
        resize_timer = nil
        mp.set_property("auto-window-resize", resize_setting)
    end)
end

-- Whether the filters take the frames of the hardware decoder as they are:
-- 4:2:0 of 8 or 10 bits.
local function readable_format()
    local format = mp.get_property("video-params/hw-pixelformat") or ""
    return format == "" or format == "nv12" or format == "p010"
end

local function name()
    local parts = {}
    if sr then parts[#parts + 1] = string.format("Super Resolution %dx%d (%s)", sr.width, sr.height, SR_LEVELS[sr.level].name) end
    if target and target.kind == "fg" then parts[#parts + 1] = string.format("DLSS-G %dx", target.factor) end
    if target and target.kind == "nv" then
        parts[#parts + 1] = string.format("NVIDIA video FG %s %dx", target.mode, target.factor)
    end
    return table.concat(parts, " + ")
end

-- the frames the filters in use work on
local function wanted_hwdec()
    if target and target.kind == "fg" then return "vulkan" end
    if target or sr then return "nvdec" end
end

local function everything_off()
    target, sr = nil, nil
    publish()
    if pending then pending:kill(); pending = nil end
    remove_filters()
    if saved_hwdec then
        mp.set_property("hwdec", saved_hwdec)
        saved_hwdec = nil
    end
end

local function add_filters()
    remove_filters()
    local filters = {}
    if upload then
        filters[#filters + 1] = string.format("@%s:lavfi=[format=%s,hwupload]:hwdec_interop=%s", UPLOAD_LABEL, upload,
                                              wanted_hwdec() == "vulkan" and "vulkan" or "cuda")
    end
    -- upscale first, so that only the original frames go through it
    if sr then
        filters[#filters + 1] = string.format("@%s:nvvsr_cuda=w=%d:h=%d:quality=%s", SR_LABEL, sr.width, sr.height,
                                              SR_LEVELS[sr.level].quality)
    end
    if target and target.kind == "fg" then
        filters[#filters + 1] = "@dlssg:dlssg_vulkan=factor=" .. target.factor
    elseif target then
        filters[#filters + 1] = "@nvfg:nvvfg_cuda=factor=" .. target.factor .. ":mode=" .. target.mode
    end
    for _, filter in ipairs(filters) do
        if not mp.commandv("vf", "add", filter) then
            local what = name()
            everything_off()
            mp.osd_message(what .. " not available (see the log)", 4)
            return
        end
    end
    local source = mp.get_property_number("container-fps") or 0
    local fps = target and string.format(" (%.2f fps)", source * target.factor) or ""
    mp.osd_message(name() .. fps, 3)
end

-- Make the filter chain match target and sr.
local function update()
    publish()
    keep_window_size()
    if pending then pending:kill(); pending = nil end

    local wanted = wanted_hwdec()
    if not wanted then
        everything_off()
        return
    end
    mp.osd_message(name(), 3)
    if saved_hwdec and mp.get_property("hwdec") == wanted and mp.get_property("hwdec-current") == wanted then
        add_filters()
        return
    end
    remove_filters()
    upload = nil

    -- Do not stack it on top of another interpolator.
    local others, found = {}, false
    for _, f in ipairs(mp.get_property_native("vf") or {}) do
        if f.name == "vapoursynth" then found = true else others[#others + 1] = f end
    end
    if found then mp.set_property_native("vf", others) end

    saved_hwdec = saved_hwdec or mp.get_property("hwdec")
    mp.set_property("hwdec", wanted)
    pending = mp.add_timeout(0.5, function() -- let the decoder restart
        pending = nil
        if mp.get_property("hwdec-current") == wanted and readable_format() then
            add_filters()
            return
        end
        -- No hardware decoder for this video, or one giving frames the filters
        -- cannot read: decode in software and copy the frames to the GPU.
        mp.set_property("hwdec", "no")
        pending = mp.add_timeout(0.5, function()
            pending = nil
            local format = mp.get_property("video-params/pixelformat")
            if not format then
                everything_off()
                mp.osd_message("No video to work on", 3)
                return
            end
            upload = (format:find("p1[0246]") or format:find("p01[0246]")) and "p010" or "nv12"
            add_filters()
        end)
    end)
end

local function off()
    target = nil
    update()
end

local function sr_off()
    sr = nil
    update()
end

local function apply(spec)
    target = spec
    if spec.kind == "fg" then
        last = spec.factor
        sr = nil
    end
    update()
end

-- Highest multiplier the display can show, and the source frame rate.
local function limit()
    local source = mp.get_property_number("container-fps")
    if not source or source <= 0 then return nil end
    local display = mp.get_property_number("display-fps")
    local max = MAX_FACTOR
    if display then max = math.min(max, math.floor(display / source + 0.05)) end
    return max, source
end

-- Returns the highest usable factor, or nil after explaining why there is none.
local function usable()
    local max, source = limit()
    if not max then
        mp.osd_message("Frame generation: no video, or unknown frame rate")
    elseif max < 2 then
        mp.osd_message(string.format("Frame generation: the video already runs at %.0f fps", source))
    else
        return max
    end
end

local function cycle()
    if not supported("fg") then return end
    local max = usable()
    if not max then return end
    max = math.min(max, caps.fg)
    local next_factor = target and target.kind == "fg" and target.factor + 1 or 2
    if next_factor > max then
        off()
        mp.osd_message("DLSS-G off")
    else
        apply({kind = "fg", factor = next_factor})
    end
end

local function cycle_nv()
    if not supported("nv") then return end
    local max = usable()
    if not max then return end
    local level = target and target.kind == "nv" and target.level or 0
    repeat level = level + 1 until not NV_LEVELS[level] or NV_LEVELS[level].factor <= max
    local entry = NV_LEVELS[level]
    if not entry then
        off()
        mp.osd_message("NVIDIA video FG off")
    else
        apply({kind = "nv", factor = entry.factor, mode = entry.mode, level = level})
    end
end

-- Super Resolution settings for the current video: the largest size that fits
-- the screen. nil, with a message, if there is nothing to enlarge.
local function fit_sr(level)
    local width, height = mp.get_property_number("video-params/w"), mp.get_property_number("video-params/h")
    local dw, dh = mp.get_property_number("video-params/dw"), mp.get_property_number("video-params/dh")
    local screen_w, screen_h = mp.get_property_number("display-width"), mp.get_property_number("display-height")
    if not (width and height and dw and dh and screen_w and screen_h) then
        mp.osd_message("Super Resolution: no video yet")
        return
    end
    local scale = math.min(screen_w / dw, screen_h / dh, 4)
    if scale < 1.1 then
        mp.osd_message(string.format("Super Resolution: %dx%d already fills the screen, nothing to enlarge", width, height), 4)
        return
    end
    return {level = level, width = math.floor(width * scale / 2 + 0.5) * 2,
            height = math.floor(height * scale / 2 + 0.5) * 2}
end

local function cycle_sr()
    if not supported("sr") then return end
    local level = (sr and sr.level or 0) + 1
    if not SR_LEVELS[level] then
        sr_off()
        mp.osd_message("Super Resolution off")
        return
    end
    sr = fit_sr(level)
    if not sr then return end
    if target and target.kind == "fg" then target = nil end
    update()
end

local function toggle()
    if target and target.kind == "fg" then
        off()
        mp.osd_message("DLSS-G off")
        return
    end
    if not supported("fg") then return end
    local max = usable()
    if max then
        max = math.min(max, caps.fg)
        apply({kind = "fg", factor = math.min(last or max, max)})
    end
end

-- mpv disables a filter that fails to initialise: go back and say so.
mp.enable_messages("error")
mp.register_event("log-message", function(e)
    if (target and e.text:find("Disabling filter " .. LABELS[target.kind], 1, true)) or
       (sr and e.text:find("Disabling filter " .. SR_LABEL, 1, true)) then
        local what = name()
        everything_off()
        mp.osd_message(what .. " failed to start (see the log)", 4)
    end
end)

-- The filters stay for the next file, but what they need may differ: take them
-- out while it loads and set them up again for it.
local reapply = false
mp.register_event("start-file", function()
    if not (target or sr) then return end
    reapply = true
    if pending then pending:kill(); pending = nil end
    remove_filters()
end)
mp.register_event("playback-restart", function()
    if not reapply then return end
    reapply = false
    if sr then sr = fit_sr(sr.level) end
    update()
end)

-- A filter may be removed by someone else (another script, "vf" commands).
mp.observe_property("vf", "native", function()
    if pending or reapply then return end
    local lost = false
    if target and not active(LABELS[target.kind]) then target = nil; lost = true end
    if sr and not active(SR_LABEL) then sr = nil; lost = true end
    if lost then update() end
end)

publish()
check_card()

-- Window placement. The window ends up in the middle of the screen:
--
--   Alt+1 .. Alt+4    100, 75, 50, 25 % of the video size
--   Ctrl+1            full screen
--   Ctrl+2 .. Ctrl+4  75, 50, 25 % of the screen size
--
-- The same from other scripts or input.conf:
--   script-message dlssg-window video|screen <fraction>

local centre_timer = nil

local function centre()
    if mp.get_property("platform") == "windows" or os.getenv("XDG_SESSION_TYPE") == "x11" then
        mp.set_property("geometry", "+50%+50%")
        return
    end
    -- Wayland does not let a program place its own window. KWin can centre the
    -- active one, which is only ours while it has the focus.
    if (os.getenv("XDG_CURRENT_DESKTOP") or ""):find("KDE") and mp.get_property_native("focused") then
        mp.command_native_async({
            name = "subprocess", playback_only = false, capture_stdout = true, capture_stderr = true,
            args = {"busctl", "--user", "call", "org.kde.kglobalaccel", "/component/kwin",
                    "org.kde.kglobalaccel.Component", "invokeShortcut", "s", "Window Move Center"},
        }, function() end)
    end
end

local function place_window(base, fraction)
    local function apply()
        local scale = fraction
        if base == "screen" then
            -- the video fitted in that fraction of the screen
            local width, height = mp.get_property_number("dwidth"), mp.get_property_number("dheight")
            local screen_w = mp.get_property_number("display-width")
            local screen_h = mp.get_property_number("display-height")
            if not (width and height and screen_w and screen_h) then return end
            scale = fraction * math.min(screen_w / width, screen_h / height)
        end
        -- a geometry set at startup would be applied again, over this size
        mp.set_property("geometry", "")
        mp.set_property_number("window-scale", scale)
        if centre_timer then centre_timer:kill() end
        centre_timer = mp.add_timeout(0.3, centre) -- once resized
    end
    if mp.get_property_native("fullscreen") or mp.get_property_native("window-maximized") then
        mp.set_property_native("fullscreen", false)
        mp.set_property_native("window-maximized", false)
        mp.add_timeout(0.3, apply) -- once the window has left that state
    else
        apply()
    end
end

mp.register_script_message("dlssg-window", function(base, fraction)
    fraction = tonumber(fraction)
    if (base == "video" or base == "screen") and fraction and fraction > 0 then
        place_window(base, fraction)
    end
end)

for key, fraction in ipairs({1, 0.75, 0.5, 0.25}) do
    mp.add_key_binding("Alt+" .. key, "window-video-" .. key, function() place_window("video", fraction) end)
    if key > 1 then
        mp.add_key_binding("Ctrl+" .. key, "window-screen-" .. key, function() place_window("screen", fraction) end)
    end
end
mp.add_key_binding("Ctrl+1", "window-screen-1", function() mp.set_property_native("fullscreen", true) end)

-- Sharpening (dlssg-sharpen.glsl): y rotates off, 0.25, 0.5, 0.75, 1.
local sharpness_levels = {0.25, 0.5, 0.75, 1}
local sharpness = 0 -- index into the levels, 0 = off

-- next to this script, or in the shaders directory beside the scripts one
local function find_shader()
    local dir = debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or "."
    for _, path in ipairs({dir .. "/dlssg-sharpen.glsl", dir .. "/../shaders/dlssg-sharpen.glsl"}) do
        if utils.file_info(path) then return path end
    end
end
local shader = find_shader()

local function set_sharpness(index)
    sharpness = index
    if index == 0 then
        mp.commandv("change-list", "glsl-shaders", "remove", shader)
    else
        mp.commandv("change-list", "glsl-shader-opts", "append", "MPVDLSSG_SHARPNESS=" .. sharpness_levels[index])
        mp.commandv("change-list", "glsl-shaders", "append", shader)
    end
    mp.set_property_native("user-data/dlssg/sharpness", sharpness_levels[index] or 0)
end

if shader then
    mp.set_property_native("user-data/dlssg/sharpness", 0)
    mp.add_key_binding("y", "sharpen", function()
        local index = (sharpness + 1) % (#sharpness_levels + 1)
        if index > 0 then mp.commandv("change-list", "glsl-shaders", "remove", shader) end
        set_sharpness(index)
        mp.osd_message(index == 0 and "Sharpness: off" or ("Sharpness: " .. sharpness_levels[index]))
    end)
    mp.add_key_binding(nil, "sharpen-off", function() set_sharpness(0) end)
end

mp.add_key_binding("k", "cycle", cycle)
mp.add_key_binding("h", "nv", cycle_nv)
mp.add_key_binding("a", "sr", cycle_sr)
mp.add_key_binding(nil, "sr-off", sr_off)
mp.add_key_binding(nil, "toggle", toggle)
mp.add_key_binding(nil, "off", off)
