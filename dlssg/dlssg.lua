-- DLSS Frame Generation controls for the dlssg_vulkan filter.
--
--   F7         toggle, at the highest factor the display can show
--   Shift+F7   cycle the factor (2x .. 6x)
--
-- Bindings in input.conf take precedence; the script bindings are named
-- dlssg/toggle and dlssg/cycle.

local mp = require "mp"

local MAX_FACTOR = 6
local factor_choice = nil -- picked with Shift+F7; nil = highest possible
local saved_hwdec = nil
local pending = nil

local function active()
    for _, f in ipairs(mp.get_property_native("vf") or {}) do
        if f.label == "dlssg" then return true end
    end
    return false
end

local function off()
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

local function add(factor, source)
    if mp.commandv("vf", "add", "@dlssg:dlssg_vulkan=factor=" .. factor) then
        mp.osd_message(string.format("DLSS-G %dx (%.2f fps)", factor, source * factor), 3)
    else
        off()
        mp.osd_message("DLSS-G not available (see the log)", 4)
    end
end

local function on(factor)
    local max, source = limit()
    if not max then
        mp.osd_message("DLSS-G: no video, or unknown frame rate")
        return
    end
    if max < 2 then
        mp.osd_message(string.format("DLSS-G: the video already runs at %.0f fps", source))
        return
    end
    factor = math.min(factor or max, max)

    -- Do not stack it on top of another interpolator.
    for _, f in ipairs(mp.get_property_native("vf") or {}) do
        if f.name == "vapoursynth" then mp.commandv("vf", "remove", "@" .. (f.label or "vapoursynth")) end
    end

    if active() then
        mp.commandv("vf", "remove", "@dlssg")
        add(factor, source)
        return
    end

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
        add(factor, source)
    end)
end

-- mpv disables a filter that fails to initialise: go back and say so.
mp.enable_messages("error")
mp.register_event("log-message", function(e)
    if e.text:find("Disabling filter dlssg", 1, true) then
        off()
        mp.osd_message("DLSS-G failed to start (see the log)", 4)
    end
end)

mp.add_key_binding("F7", "toggle", function()
    if active() or pending then
        off()
        mp.osd_message("DLSS-G off")
    else
        on(factor_choice)
    end
end)

mp.add_key_binding("Shift+F7", "cycle", function()
    local max = limit()
    if not max or max < 2 then
        on(nil)
        return
    end
    local current = factor_choice and math.min(factor_choice, max) or max
    if active() or pending then
        current = current >= max and 2 or current + 1
        if pending then off() end
    end
    factor_choice = current
    on(current)
end)
