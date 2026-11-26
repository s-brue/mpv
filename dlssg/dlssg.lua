-- DLSS Frame Generation controls for the dlssg_vulkan filter.
--
--   k    rotate: off -> 2x -> 3x -> 4x -> 5x -> 6x -> off
--
-- Factors the display cannot show are skipped.
--
-- Like any other mpv binding, these can be changed in input.conf:
--   k    script-binding dlssg/cycle
--
-- Also available, with no key by default:
--   script-binding dlssg/toggle   on/off, at the last factor used (at first,
--                                 the highest possible)
--   script-binding dlssg/off
--
-- The factor in use (0 = off) is published in user-data/dlssg/factor, which the
-- DLSS-G button of the ModernZ interface shows.

local mp = require "mp"

local MAX_FACTOR = 6
local target = nil      -- requested factor, nil = off
local last = nil        -- factor the toggle comes back to
local saved_hwdec = nil -- set while the filter is in use
local pending = nil     -- timer waiting for the Vulkan decoder

local function active()
    for _, f in ipairs(mp.get_property_native("vf") or {}) do
        if f.label == "dlssg" then return true end
    end
    return false
end

local function publish()
    mp.set_property_native("user-data/dlssg/factor", target or 0)
end

-- Adding or removing the filter reconfigures the video output, and mpv would
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
    if saved_hwdec or active() then keep_window_size() end
    if pending then pending:kill(); pending = nil end
    if active() then mp.commandv("vf", "remove", "@dlssg") end
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

local function add_filter()
    local source = mp.get_property_number("container-fps") or 0
    if active() then mp.commandv("vf", "remove", "@dlssg") end
    local factor = target
    if mp.commandv("vf", "add", "@dlssg:dlssg_vulkan=factor=" .. factor) then
        mp.osd_message(string.format("DLSS-G %dx (%.2f fps)", factor, source * factor), 3)
    else
        off()
        mp.osd_message("DLSS-G not available (see the log)", 4)
    end
end

local function apply(factor)
    target, last = factor, factor
    publish()
    keep_window_size()
    mp.osd_message(string.format("DLSS-G %dx", factor), 3)

    -- Still waiting for the decoder: the timer picks up the new target.
    if pending then return end
    if saved_hwdec then
        add_filter()
        return
    end

    -- Do not stack it on top of another interpolator.
    local others, found = {}, false
    for _, f in ipairs(mp.get_property_native("vf") or {}) do
        if f.name == "vapoursynth" then found = true else others[#others + 1] = f end
    end
    if found then mp.set_property_native("vf", others) end

    -- The filter needs Vulkan frames.
    saved_hwdec = mp.get_property("hwdec")
    mp.set_property("hwdec", "vulkan")
    pending = mp.add_timeout(0.5, function() -- let the decoder restart
        pending = nil
        if mp.get_property("hwdec-current") ~= "vulkan" then
            off()
            mp.osd_message("DLSS-G: no Vulkan decoding for this video", 3)
            return
        end
        add_filter()
    end)
end

-- Returns the highest usable factor, or nil after explaining why there is none.
local function usable()
    local max, source = limit()
    if not max then
        mp.osd_message("DLSS-G: no video, or unknown frame rate")
    elseif max < 2 then
        mp.osd_message(string.format("DLSS-G: the video already runs at %.0f fps", source))
    else
        return max
    end
end

local function cycle()
    local max = usable()
    if not max then return end
    local next_factor = target and target + 1 or 2
    if next_factor > max then
        off()
        mp.osd_message("DLSS-G off")
    else
        apply(next_factor)
    end
end

local function toggle()
    if target then
        off()
        mp.osd_message("DLSS-G off")
        return
    end
    local max = usable()
    if max then apply(math.min(last or max, max)) end
end

-- mpv disables a filter that fails to initialise: go back and say so.
mp.enable_messages("error")
mp.register_event("log-message", function(e)
    if e.text:find("Disabling filter dlssg", 1, true) then
        off()
        mp.osd_message("DLSS-G failed to start (see the log)", 4)
    end
end)

-- The filter may be removed by someone else (another script, "vf" commands).
mp.observe_property("vf", "native", function()
    if target and not pending and not active() then off() end
end)

publish()
mp.add_key_binding("k", "cycle", cycle)
mp.add_key_binding(nil, "toggle", toggle)
mp.add_key_binding(nil, "off", off)
