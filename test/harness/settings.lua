local function expect(condition, message)
    if not condition then error("ASSERT FAILED: " .. message, 0) end
end

local main, updater, incoming, gains
for _, frame in ipairs(FRAMES) do
    if frame.events and frame.events.PLAYER_LOGIN then main = frame end
    if frame.scripts and frame.scripts.OnUpdate then updater = frame end
    if frame.name == "ClearCombatTextIncomingAnchor" then incoming = frame end
    if frame.name == "ClearCombatTextGainsAnchor" then gains = frame end
end
main.scripts.OnEvent(main, "PLAYER_LOGIN")
local function tick(seconds)
    CLOCK = CLOCK + seconds
    updater.scripts.OnUpdate(updater, seconds)
end
local function fire(kind, data, a2)
    EVENTS[1] = { data = data, a2 = a2 }
    main.hooks.OnEvent(main, "COMBAT_TEXT_UPDATE", kind)
end
local function visible(anchor)
    local list = {}
    for _, fs in ipairs(FONTSTRINGS) do
        local p = fs.points[#fs.points]
        if fs:IsShown() and p and (p[2] == incoming or p[2] == gains) and (not anchor or p[2] == anchor) then
            list[#list + 1] = fs
        end
    end
    return list
end
local function position(fs)
    local p = fs.points[#fs.points]
    return p[4], p[5]
end
local secret = setmetatable({ secret = true }, { __tostring = function() return "secret display" end })

-- Schema validation and ownership: nested arrays must never alias presets/profiles.
local bad = ADDON.NormalizeOptions({ enabled = "bad", fontScale = 0/0, opacity = math.huge,
    incoming = { duration = -100, maxLines = 999 }, filters = { periodic = false }, incomingColor = { -1, 2, "bad" } })
expect(bad.enabled and bad.fontScale == 1 and bad.opacity == 1, "invalid options not defaulted")
expect(bad.incoming.duration == 0.8 and bad.incoming.maxLines == 64, "option limits not clamped")
expect(bad.filters.periodic == false and bad.filters.auras == true, "filter defaults lost")
expect(bad.incomingColor[1] == 0 and bad.incomingColor[2] == 1 and bad.incomingColor[3] == 0.25, "color validation failed")

-- Default burst capacity is independent per stream, even for uninspectable values.
for i = 1, 20 do fire("SPELL_DAMAGE", secret) end
expect(#visible(incoming) == 8, "default incoming capacity wrong")
fire("HEAL", "Healer", secret)
expect(#visible(gains) == 1, "incoming burst starved gains")
local damage = visible(incoming)[8]
local _, before = position(damage)
fire("SPELL_DAMAGE_CRIT", secret)
expect(#visible(incoming) == 8, "priority replacement exceeded capacity")
local crit
for _, fs in ipairs(visible(incoming)) do if fs.size == 28 then crit = fs end end
expect(crit, "crit could not replace ordinary damage")
fire("HEALTH_LOW")
local warning
for _, fs in ipairs(visible(incoming)) do if fs.text == LOW_HEALTH then warning = fs end end
expect(warning and crit:IsShown(), "warning missing or displaced crit instead of ordinary damage")
tick(0.1)
local _, after = position(damage)
if damage:IsShown() then expect(after >= before, "vertical text moved backwards") end

-- The deterministic layout separates mixed sizes in every direction without getters.
for _, direction in ipairs({ "up", "down", "left", "right" }) do
    ADDON.SetDirection("incoming", direction)
    for _, kind in ipairs({ "SPELL_DAMAGE", "SPELL_DAMAGE_CRIT", "PERIODICAURA_DAMAGE", "SPELL_DAMAGE" }) do fire(kind, secret) end
    tick(0.05)
    local rows = {}
    for _, fs in ipairs(visible(incoming)) do
        local x, y = position(fs)
        expect((direction == "left" and x < 0) or (direction == "right" and x > 0) or x == 0, "wrong animation axis")
        rows[#rows + 1] = y
    end
    table.sort(rows)
    for i = 2, #rows do expect(rows[i] - rows[i - 1] >= 44 - 0.0001, "mixed-size rows overlap: " .. direction) end
end

-- Consolidation must not rewind text or keep it alive indefinitely.
ADDON.SetDirection("incoming", "up")
fire("SPELL_DAMAGE", 100)
local merged = visible(incoming)[1]
tick(0.3)
local _, oldY = position(merged)
fire("SPELL_DAMAGE", 100)
expect(merged.text == "200 x2", "public consolidation broke")
tick(0.01)
local _, newY = position(merged)
expect(newY >= oldY, "consolidation rewound animation")
for i = 1, 7 do tick(0.3); fire("SPELL_DAMAGE", 100) end
expect(merged.text ~= "900 x9", "consolidation kept an expired entry alive")

-- Category filters reject events before fetching their combat payload.
local payload = C_CombatText.GetCurrentEventInfo
C_CombatText.GetCurrentEventInfo = function() error("filtered event fetched payload") end
local categories = {
    periodic = { "PERIODICAURA_DAMAGE", "PERIODIC_HEAL", "PERIODIC_HEAL_CRIT", "PERIODIC_HEAL_ABSORB" },
    resources = { "ENERGIZE", "PERIODIC_ENERGIZE", "MANA", "RUNE" },
    auras = { "AURA_START", "SPELL_AURA_END", "SPELL_AURA_START_HARMFUL" },
    avoidance = { "MISS", "SPELL_REFLECT", "DODGE" },
}
for category, kinds in pairs(categories) do
    ADDON.SetOption("filters", category, false)
    for _, kind in ipairs(kinds) do fire(kind, secret) end
    expect(#visible() == 0, "filtered event rendered: " .. category)
end
ADDON.SetOption("filters", "combat", false)
main.scripts.OnEvent(main, "PLAYER_REGEN_DISABLED")
expect(#visible() == 0, "combat filter ignored")
ADDON.SetOption(nil, "enabled", false)
fire("SPELL_DAMAGE", secret)
main.scripts.OnEvent(main, "PLAYER_REGEN_ENABLED")
expect(not updater:IsShown(), "disabled addon did not sleep")
C_CombatText.GetCurrentEventInfo = payload
ADDON.Preview(true)
expect(#visible() > 0, "disabled addon cannot preview")
for i = 1, 60 do tick(0.15) end
expect(not updater:IsShown(), "burst preview never stopped")

-- Presets preserve placement; named profiles restore independent snapshots.
incoming:ClearAllPoints()
incoming:SetPoint("CENTER", UIParent, "CENTER", 123, 456)
ADDON.SetDirection("incoming", "down")
expect(ADDON.ApplyPreset("healer"), "preset missing")
local _, _, _, x = incoming:GetPoint()
expect(x == 123, "preset changed position")
expect(ADDON.SaveProfile("My Raid Setup"), "profile save failed")
ADDON.GetOptions().incomingColor[1] = 0.4
expect(ClearCombatTextDB.profiles["My Raid Setup"].options.incomingColor[1] == 1, "saving aliased profile colors")
ADDON.SetOption(nil, "fontScale", 1.8)
ADDON.ResetPositions()
SlashCmdList.CLEARCOMBATTEXT("PROFILE LOAD My Raid Setup")
local _, _, _, loadedX = incoming:GetPoint()
expect(loadedX == 123 and ClearCombatTextDB.streams.incoming.direction == "down", "profile layout not restored")
expect(ADDON.GetOptions().fontScale == 1.1, "profile options aliased active options or slash changed case")
ADDON.GetOptions().incomingColor[1] = 0
expect(ClearCombatTextDB.profiles["My Raid Setup"].options.incomingColor[1] == 1, "profile color aliased")
expect(not ADDON.SaveProfile("bad/name"), "invalid profile name accepted")
for i = 1, 9 do expect(ADDON.SaveProfile("Profile " .. i), "profile limit too low") end
expect(not ADDON.SaveProfile("Overflow"), "profile limit exceeded")
expect(ADDON.DeleteProfile("My Raid Setup") and not ADDON.LoadProfile("My Raid Setup"), "profile deletion failed")

-- Exercise the actual lazy options UI, including its slider re-entry guard.
local function findButton(text)
    for _, frame in ipairs(FRAMES) do if frame.kind == "Button" and frame.text == text then return frame end end
    error("button not found: " .. text)
end
local function click(text)
    local b = findButton(text)
    b.scripts.OnClick(b)
end
SlashCmdList.CLEARCOMBATTEXT("config")
local config
for _, frame in ipairs(FRAMES) do if frame.name == "ClearCombatTextConfig" then config = frame end end
expect(config and config:IsShown(), "settings panel did not open")
expect(UISpecialFrames[1] == "ClearCombatTextConfig", "Escape cannot close settings")
for _, name in ipairs({ "Incoming", "Gains", "Filters", "Profiles", "Appearance" }) do click(name) end
local firstSlider
for _, frame in ipairs(FRAMES) do if frame.kind == "Slider" then firstSlider = frame; break end end
firstSlider:SetValue(1.25)
expect(ADDON.GetOptions().fontScale == 1.25 and #visible() > 0, "slider did not save and preview")
click("Default")
expect(ADDON.GetOptions().font == "sans", "font cycle failed")
for _, fs in ipairs(visible()) do expect(fs.font == "Fonts\\ARIALN.TTF", "preview font not applied") end
local enabledCheck
for _, frame in ipairs(FRAMES) do if frame.kind == "CheckButton" then enabledCheck = frame; break end end
enabledCheck:SetChecked(false)
enabledCheck.scripts.OnClick(enabledCheck)
expect(ADDON.GetOptions().enabled == false, "enable checkbox ignored false")
enabledCheck:SetChecked(true)
enabledCheck.scripts.OnClick(enabledCheck)
expect(ADDON.GetOptions().enabled == true, "enable checkbox failed to re-enable")
local editors, checks = {}, {}
for _, frame in ipairs(FRAMES) do
    if frame.kind == "EditBox" then editors[#editors + 1] = frame end
    if frame.kind == "CheckButton" then checks[#checks + 1] = frame end
end
editors[1]:SetText("FF00AA")
click("Apply")
checks[3]:SetChecked(true)
checks[3].scripts.OnClick(checks[3])
for _, fs in ipairs(visible(incoming)) do
    expect(fs.color[1] == 1 and fs.color[2] == 0 and fs.color[3] == 170/255, "custom preview color not applied")
end
editors[1]:SetText("invalid")
click("Apply")
expect(ADDON.GetOptions().incomingColor[2] == 0, "invalid color changed settings")
click("Profiles")
editors[3]:SetText("UI Profile")
click("Save")
expect(ClearCombatTextDB.profiles["UI Profile"], "UI profile save failed")
click("minimal")
expect(ADDON.GetOptions().incoming.maxLines == 6 and not ADDON.GetOptions().filters.periodic, "UI preset failed")
click("Load")
expect(ADDON.GetOptions().fontScale == 1.25 and ADDON.GetOptions().customColors, "UI profile load failed")
click("Delete")
expect(not ClearCombatTextDB.profiles["UI Profile"], "UI profile delete failed")
click("Unlock areas")
expect(incoming:IsShown() and gains:IsShown() and incoming.mouseEnabled, "UI unlock failed")
click("Lock areas")
expect(not incoming:IsShown() and not gains:IsShown() and not incoming.mouseEnabled, "UI lock failed")
click("Reset both positions")
local _, _, _, resetX = incoming:GetPoint()
expect(resetX == -180, "UI reset failed")
click("5-second burst")
for i = 1, 60 do tick(0.15) end
expect(not updater:IsShown(), "UI preview failed to sleep")
SlashCmdList.CLEARCOMBATTEXT("config")
expect(not config:IsShown(), "settings toggle did not close")
io.write("SETTINGS AND LAYOUT PASSED\n")
