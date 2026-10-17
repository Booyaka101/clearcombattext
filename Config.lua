local _, addon = ...

local panel, status, selectedPage
local pages, refreshers = {}, {}
local syncing = false
local sliderCount = 0

local function label(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function button(parent, text, x, y, width, action)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", action)
    return b
end

local function refresh()
    syncing = true
    for _, fn in ipairs(refreshers) do fn() end
    syncing = false
end

local function changed(group, key, value)
    if syncing then return end
    addon.SetOption(group, key, value)
    refresh()
    addon.Preview()
end

local function value(group, key)
    local options = addon.GetOptions()
    if group then return options[group][key] end
    return options[key]
end

local function check(parent, text, y, group, key)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(26, 26)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    label(parent, text, 42, y - 6)
    c:SetScript("OnClick", function(self) changed(group, key, self:GetChecked()) end)
    refreshers[#refreshers + 1] = function() c:SetChecked(value(group, key)) end
end

local function slider(parent, text, y, group, key, low, high, step)
    sliderCount = sliderCount + 1
    local s = CreateFrame("Slider", "ClearCombatTextSlider" .. sliderCount, parent, "OptionsSliderTemplate")
    s:SetSize(250, 16)
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", 230, y - 4)
    s:SetMinMaxValues(low, high)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    local title = label(parent, text, 12, y)
    s:SetScript("OnValueChanged", function(_, v)
        if not syncing then changed(group, key, math.floor(v / step + 0.5) * step) end
    end)
    refreshers[#refreshers + 1] = function()
        local v = value(group, key)
        s:SetValue(v)
        title:SetText(string.format("%s: %.2f", text, v))
    end
end

local function cycle(parent, text, y, keys, labels, get, set)
    label(parent, text, 12, y - 5)
    local b
    b = button(parent, "", 230, y, 250, function()
        local current = get()
        for i, key in ipairs(keys) do
            if current == key then set(keys[i % #keys + 1]); break end
        end
        refresh()
    end)
    refreshers[#refreshers + 1] = function() b:SetText(labels[get()] or get()) end
end

local function edit(parent, x, y, width)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 24)
    e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    e:SetAutoFocus(false)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end

local function colorEditor(parent, text, y, key)
    label(parent, text .. " (RRGGBB)", 12, y - 5)
    local e = edit(parent, 235, y, 110)
    e:SetMaxLetters(6)
    local function apply()
        local hex = e:GetText()
        if not hex:match("^%x%x%x%x%x%x$") then status:SetText("Use exactly six hexadecimal digits, for example FF5533."); return end
        changed(nil, key, { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 })
        e:ClearFocus()
        status:SetText("Color saved. Enable custom area colors to use it.")
    end
    e:SetScript("OnEnterPressed", apply)
    button(parent, "Apply", 365, y, 115, apply)
    refreshers[#refreshers + 1] = function()
        local c = value(nil, key)
        e:SetText(string.format("%02X%02X%02X", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)))
    end
end

local function selectPage(name)
    selectedPage = name
    for key, page in pairs(pages) do page:SetShown(key == name) end
    refresh()
end

local function createPanel()
    panel = CreateFrame("Frame", "ClearCombatTextConfig", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(560, 610)
    panel:SetPoint("CENTER")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetFrameStrata("DIALOG")
    label(panel, "ClearCombatText", 16, -7)
    UISpecialFrames[#UISpecialFrames + 1] = "ClearCombatTextConfig"

    local names = { "Appearance", "Incoming", "Gains", "Filters", "Profiles" }
    for i, name in ipairs(names) do
        local page = CreateFrame("Frame", nil, panel)
        page:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -72)
        page:SetSize(520, 420)
        pages[name] = page
        button(panel, name, 18 + (i - 1) * 105, -36, 100, function() selectPage(name) end)
    end
    local appearance = pages.Appearance
    check(appearance, "Enable combat text", -2, nil, "enabled")
    cycle(appearance, "Font", -40, { "default", "sans" }, addon.Fonts,
        function() return value(nil, "font") end, function(v) changed(nil, "font", v) end)
    cycle(appearance, "Outline", -76, { "", "OUTLINE", "THICKOUTLINE" }, { [""] = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick outline" },
        function() return value(nil, "outline") end, function(v) changed(nil, "outline", v) end)
    slider(appearance, "Font scale", -118, nil, "fontScale", 0.7, 1.8, 0.05)
    slider(appearance, "Opacity", -165, nil, "opacity", 0.3, 1, 0.05)
    slider(appearance, "Critical pop scale", -212, nil, "critScale", 1, 1.8, 0.05)
    check(appearance, "Text shadow", -252, nil, "shadow")
    check(appearance, "Custom area colors (overrides event colors)", -286, nil, "customColors")
    colorEditor(appearance, "Incoming", -330, "incomingColor")
    colorEditor(appearance, "Gains", -370, "gainsColor")

    for _, name in ipairs({ "incoming", "gains" }) do
        local page = pages[name == "incoming" and "Incoming" or "Gains"]
        cycle(page, "Direction", -10, { "up", "down", "left", "right" }, { up = "Up", down = "Down", left = "Left", right = "Right" },
            function()
                local s = ClearCombatTextDB.streams and ClearCombatTextDB.streams[name]
                return type(s) == "table" and addon.Directions[s.direction] and s.direction or "up"
            end, function(v) addon.SetDirection(name, v); addon.Preview() end)
        slider(page, "Duration (seconds)", -65, name, "duration", 0.8, 4, 0.1)
        slider(page, "Travel (pixels)", -120, name, "distance", 40, 240, 5)
        slider(page, "Row spacing", -175, name, "spacing", 0, 24, 1)
        slider(page, "Maximum lines", -230, name, "maxLines", 4, 64, 1)
        label(page, "Older vertical lines move ahead of newer lines.\nHorizontal lines use separate rows.\n\nAt capacity, important public event types can replace\nlower-priority lines. Equal-priority overflow is skipped.", 12, -295)
        button(page, "Reset both positions", 12, -390, 200, function() addon.ResetPositions(); refresh(); addon.Preview() end)
    end

    local filters = pages.Filters
    label(filters, "Show these event categories:", 12, -10)
    local labels = { periodic = "Periodic damage and healing", resources = "Resource gains", auras = "Aura notifications",
        avoidance = "Misses and avoidance", combat = "Combat entry and exit" }
    for i, key in ipairs(addon.Filters) do check(filters, labels[key], -40 - (i - 1) * 42, "filters", key) end
    label(filters, "Filters use public event types, never secret amounts.\n\nThere are no secret-value thresholds or inferred spell icons.\nBlizzard floating text changes only with /cct blizz.", 12, -280)

    local profiles = pages.Profiles
    label(profiles, "Presets change appearance and filters, not your positions.", 12, -10)
    for i, name in ipairs({ "readable", "minimal", "healer" }) do
        button(profiles, name, 12 + (i - 1) * 160, -42, 150, function()
            addon.ApplyPreset(name)
            refresh()
            addon.Preview()
            status:SetText("Applied " .. name .. "; positions retained.")
        end)
    end
    label(profiles, "Named profiles include appearance, filters and both positions.", 12, -100)
    local profileName = edit(profiles, 18, -137, 290)
    profileName:SetMaxLetters(32)
    label(profiles, "Name (case-sensitive)", 330, -142)
    local methods = { Save = addon.SaveProfile, Load = addon.LoadProfile, Delete = addon.DeleteProfile }
    for i, action in ipairs({ "Save", "Load", "Delete" }) do
        button(profiles, action, 12 + (i - 1) * 160, -182, 150, function()
            local _, message = methods[action](profileName:GetText())
            profileName:ClearFocus()
            refresh()
            status:SetText(message)
        end)
    end
    local saved = label(profiles, "", 12, -236)
    saved:SetWidth(490)
    saved:SetJustifyH("LEFT")
    refreshers[#refreshers + 1] = function() saved:SetText("Saved profiles (maximum 10):\n" .. table.concat(addon.ProfileNames(), ", ")) end
    label(profiles, "Save overwrites a profile with the same name.\nDelete removes only the named profile, not current settings.", 12, -350)

    button(panel, "Preview", 20, -510, 115, function() addon.Preview() end)
    button(panel, "5-second burst", 150, -510, 125, function() addon.Preview(true) end)
    button(panel, "Unlock areas", 290, -510, 115, function() addon.SetAnchorsUnlocked(true) end)
    button(panel, "Lock areas", 420, -510, 115, function() addon.SetAnchorsUnlocked(false) end)
    status = label(panel, "Changes save immediately. Preview also works while disabled.", 20, -555)
    status:SetWidth(515)
    status:SetJustifyH("LEFT")
    panel:SetScript("OnShow", function() selectPage(selectedPage or "Appearance") end)
    selectPage("Appearance")
end

function addon.ToggleConfig()
    if not panel then createPanel(); panel:Show()
    elseif panel:IsShown() then panel:Hide()
    else panel:Show() end
end
