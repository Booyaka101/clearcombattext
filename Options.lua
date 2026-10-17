local _, addon = ...

addon.Directions = { up = { 0, 1 }, down = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
addon.Points = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
addon.Fonts = { default = "Default", sans = "Arial Narrow" }
addon.Filters = { "periodic", "resources", "auras", "avoidance", "combat" }

function addon.Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function addon.ValidPosition(s)
    return type(s) == "table" and addon.Points[s.point] and addon.Points[s.relPoint]
        and addon.Finite(s.x) and addon.Finite(s.y)
end

local function number(value, fallback, low, high)
    if not addon.Finite(value) then return fallback end
    return math.max(low, math.min(high, value))
end

local function boolean(value, fallback)
    if type(value) == "boolean" then return value end
    return fallback
end

local function color(value, fallback)
    value = type(value) == "table" and value or fallback
    return { number(value[1], fallback[1], 0, 1), number(value[2], fallback[2], 0, 1), number(value[3], fallback[3], 0, 1) }
end

function addon.NormalizeOptions(source)
    local s = type(source) == "table" and source or {}
    local result = {
        enabled = boolean(s.enabled, true), font = addon.Fonts[s.font] and s.font or "default",
        fontScale = number(s.fontScale, 1, 0.7, 1.8), opacity = number(s.opacity, 1, 0.3, 1),
        outline = (s.outline == "" or s.outline == "OUTLINE" or s.outline == "THICKOUTLINE") and s.outline or "OUTLINE",
        shadow = boolean(s.shadow, true), critScale = number(s.critScale, 1.35, 1, 1.8),
        customColors = boolean(s.customColors, false),
        incomingColor = color(s.incomingColor, { 1, 0.35, 0.25 }), gainsColor = color(s.gainsColor, { 0.2, 1, 0.4 }),
        filters = {},
    }
    local filters = type(s.filters) == "table" and s.filters or {}
    for _, key in ipairs(addon.Filters) do result.filters[key] = boolean(filters[key], true) end
    for _, name in ipairs({ "incoming", "gains" }) do
        local area = type(s[name]) == "table" and s[name] or {}
        result[name] = {
            duration = number(area.duration, 1.9, 0.8, 4), distance = number(area.distance, 110, 40, 240),
            spacing = number(area.spacing, 6, 0, 24), maxLines = math.floor(number(area.maxLines, 8, 4, 64)),
        }
    end
    return result
end

local options
local function database()
    if type(ClearCombatTextDB) ~= "table" then ClearCombatTextDB = {} end
    return ClearCombatTextDB
end

function addon.ReloadOptions()
    local db = database()
    options = addon.NormalizeOptions(db.options)
    db.options = options
    return options
end

function addon.GetOptions()
    return options or addon.ReloadOptions()
end

local function notify(layoutChanged)
    if addon.OnSettingsChanged then addon.OnSettingsChanged(layoutChanged) end
end

function addon.SetOption(group, key, value)
    local nextOptions = addon.NormalizeOptions(addon.GetOptions())
    if group then
        if type(nextOptions[group]) ~= "table" or nextOptions[group][key] == nil then return false end
        nextOptions[group][key] = value
    else
        if nextOptions[key] == nil then return false end
        nextOptions[key] = value
    end
    database().options = nextOptions
    addon.ReloadOptions()
    notify()
    return true
end

local PRESETS = {
    readable = {},
    minimal = { fontScale = 0.9, critScale = 1.15,
        filters = { periodic = false, resources = false, auras = false, combat = false },
        incoming = { maxLines = 6 }, gains = { maxLines = 6 } },
    healer = { fontScale = 1.1, filters = { resources = false, auras = false },
        gains = { duration = 2.4, distance = 140, spacing = 10 } },
}

function addon.ApplyPreset(name)
    if not PRESETS[name] then return false end
    database().options = addon.NormalizeOptions(PRESETS[name])
    addon.ReloadOptions()
    notify()
    return true
end

local function copyLayout(source)
    source = type(source) == "table" and source or {}
    local result = {}
    for _, name in ipairs({ "incoming", "gains" }) do
        local s = source[name]
        if addon.ValidPosition(s) then
            result[name] = { point = s.point, relPoint = s.relPoint, x = s.x, y = s.y,
                direction = addon.Directions[s.direction] and s.direction or "up" }
        end
    end
    return result
end

local function profileName(name)
    if type(name) ~= "string" then return end
    name = strtrim(name)
    if #name > 0 and #name <= 32 and name:match("^[%w _%-]+$") then return name end
end

local function profiles()
    local db = database()
    if type(db.profiles) ~= "table" then db.profiles = {} end
    return db.profiles
end

function addon.ProfileNames()
    local names = {}
    for name, profile in pairs(profiles()) do
        if profileName(name) == name and type(profile) == "table" then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

function addon.SaveProfile(name)
    name = profileName(name)
    if not name then return false, "Use 1-32 letters, numbers, spaces, underscores or hyphens." end
    local saved = profiles()
    if not saved[name] and #addon.ProfileNames() >= 10 then return false, "A maximum of 10 profiles can be saved." end
    if addon.CaptureLayout then addon.CaptureLayout() end
    saved[name] = { options = addon.NormalizeOptions(addon.GetOptions()), streams = copyLayout(database().streams) }
    return true, "Saved profile: " .. name
end

function addon.LoadProfile(name)
    name = profileName(name)
    local profile = name and profiles()[name]
    if type(profile) ~= "table" then return false, "Profile not found." end
    local db = database()
    db.options, db.streams, db.anchor = addon.NormalizeOptions(profile.options), copyLayout(profile.streams), nil
    addon.ReloadOptions()
    notify(true)
    return true, "Loaded profile: " .. name
end

function addon.DeleteProfile(name)
    name = profileName(name)
    if not name or not profiles()[name] then return false, "Profile not found." end
    profiles()[name] = nil
    return true, "Deleted profile: " .. name
end
