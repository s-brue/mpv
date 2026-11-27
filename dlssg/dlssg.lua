-- Frame generation controls: DLSS Frame Generation (dlssg_vulkan filter) and
-- NVIDIA Video Frame Generation (nvvfg_cuda filter). One at a time.
--
--   k    DLSS-G, rotate: off -> 2x -> 3x -> 4x -> 5x -> 6x -> off
--   h    NVIDIA video, rotate: off -> medium 2x -> high 2x -> medium 4x
--        -> high 4x -> medium 6x -> off (high is too slow for 6x)
--
-- Factors the display cannot show are skipped.
--
-- Like any other mpv binding, these can be changed in input.conf:
--   k    script-binding dlssg/cycle
--   h    script-binding dlssg/nv
--
-- Also available, with no key by default:
--   script-binding dlssg/toggle   DLSS-G on/off, at the last factor used (at
--                                 first, the highest possible)
--   script-binding dlssg/off      either of them off
--
-- For the buttons of the ModernZ interface, user-data/dlssg/factor holds the
-- DLSS-G factor (0 = off) and user-data/dlssg/nv the NVIDIA video one ("" = off,
-- else like "M2" or "H4").

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

local LABELS = {fg = "dlssg", nv = "nvfg"}
-- the frames each filter works on
local HWDEC = {fg = "vulkan", nv = "nvdec"}

local function active(label)
    for _, f in ipairs(mp.get_property_native("vf") or {}) do
        if f.label == label then return true end
    end
    return false
end

local function remove_filters()
    for _, label in pairs(LABELS) do
        if active(label) then mp.commandv("vf", "remove", "@" .. label) end
    end
end

local function publish()
    mp.set_property_native("user-data/dlssg/factor", target and target.kind == "fg" and target.factor or 0)
    local nv = ""
    if target and target.kind == "nv" then nv = target.mode:sub(1, 1):upper() .. target.factor end
    mp.set_property_native("user-data/dlssg/nv", nv)
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

local function off()
    target = nil
    publish()
    if saved_hwdec or active(LABELS.fg) or active(LABELS.nv) then keep_window_size() end
    if pending then pending:kill(); pending = nil end
    remove_filters()
    if saved_hwdec then
        mp.set_property("hwdec", saved_hwdec)
        saved_hwdec = nil
    end
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

local function name()
    if target.kind == "fg" then return string.format("DLSS-G %dx", target.factor) end
    return string.format("NVIDIA video FG %s %dx", target.mode, target.factor)
end

local function add_filter()
    local source = mp.get_property_number("container-fps") or 0
    remove_filters()
    local filter
    if target.kind == "fg" then
        filter = "@dlssg:dlssg_vulkan=factor=" .. target.factor
    else
        filter = "@nvfg:nvvfg_cuda=factor=" .. target.factor .. ":mode=" .. target.mode
    end
    if mp.commandv("vf", "add", filter) then
        mp.osd_message(string.format("%s (%.2f fps)", name(), source * target.factor), 3)
    else
        local what = name()
        off()
        mp.osd_message(what .. " not available (see the log)", 4)
    end
end

local function apply(spec)
    target = spec
    if spec.kind == "fg" then last = spec.factor end
    publish()
    keep_window_size()
    mp.osd_message(name(), 3)
    if pending then pending:kill(); pending = nil end

    local wanted = HWDEC[spec.kind]
    if saved_hwdec and mp.get_property("hwdec") == wanted and mp.get_property("hwdec-current") == wanted then
        add_filter()
        return
    end
    remove_filters()

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
        if mp.get_property("hwdec-current") ~= wanted then
            local what = name()
            off()
            mp.osd_message(what .. ": no " .. wanted .. " decoding for this video", 3)
            return
        end
        add_filter()
    end)
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
    local max = usable()
    if not max then return end
    local next_factor = target and target.kind == "fg" and target.factor + 1 or 2
    if next_factor > max then
        off()
        mp.osd_message("DLSS-G off")
    else
        apply({kind = "fg", factor = next_factor})
    end
end

local function cycle_nv()
    local max = usable()
    if not max then return end
    -- the filter reads 8 and 10 bit 4:2:0
    local format = mp.get_property("video-params/hw-pixelformat") or mp.get_property("video-params/pixelformat") or ""
    if format:find("p012") or format:find("p016") or format:find("12") and format ~= "nv12" or format:find("444") then
        mp.osd_message("NVIDIA video FG: 4:2:0 of 8 or 10 bits only (use DLSS-G, key k)", 4)
        return
    end
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

local function toggle()
    if target and target.kind == "fg" then
        off()
        mp.osd_message("DLSS-G off")
        return
    end
    local max = usable()
    if max then apply({kind = "fg", factor = math.min(last or max, max)}) end
end

-- mpv disables a filter that fails to initialise: go back and say so.
mp.enable_messages("error")
mp.register_event("log-message", function(e)
    if target and e.text:find("Disabling filter " .. LABELS[target.kind], 1, true) then
        local what = name()
        off()
        mp.osd_message(what .. " failed to start (see the log)", 4)
    end
end)

-- The filter may be removed by someone else (another script, "vf" commands).
mp.observe_property("vf", "native", function()
    if target and not pending and not active(LABELS[target.kind]) then off() end
end)

publish()
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
mp.add_key_binding(nil, "toggle", toggle)
mp.add_key_binding(nil, "off", off)
