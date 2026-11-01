local function expect(condition, message)
    if not condition then error("ASSERT FAILED: " .. message, 0) end
end
local main, updater
for _, frame in ipairs(FRAMES) do
    if frame.events and frame.events.PLAYER_LOGIN then main = frame; frame.scripts.OnEvent(frame, "PLAYER_LOGIN") end
    if frame.scripts and frame.scripts.OnUpdate then updater = frame end
end

local function visible(frame)
    while frame do
        if not frame:IsShown() then return false end
        frame = frame.parent
    end
    return true
end
local function button(text)
    for _, frame in ipairs(FRAMES) do
        if frame.kind == "Button" and frame.text == text and visible(frame) then return frame end
    end
    error("visible button not found: " .. text)
end
local function click(text)
    local b = button(text)
    b.scripts.OnClick(b)
end
local function editors()
    local list = {}
    for _, frame in ipairs(FRAMES) do
        if frame.kind == "EditBox" and visible(frame) then list[#list + 1] = frame end
    end
    return list
end

UIParent:SetSize(640, 480)
ADDON.ToggleConfig()
local panel = _G.ClearCombatTextConfig
expect(panel and panel:IsShown(), "named settings panel not registered")
local function fits()
    local scale = panel.scale or 1
    expect(panel.height * scale <= UIParent:GetHeight() - 32 + 0.0001, "settings panel taller than the usable screen")
    expect(panel.width * scale <= UIParent:GetWidth() - 32 + 0.0001, "settings panel wider than the usable screen")
end
fits()
UIParent:SetSize(800, 450)
expect(panel.events.DISPLAY_SIZE_CHANGED and panel.events.UI_SCALE_CHANGED, "panel does not handle display changes")
panel.scripts.OnEvent(panel, "DISPLAY_SIZE_CHANGED")
fits()

-- Editing a hex value must survive unrelated refreshes and tab switches.
local color = editors()[1]
color:SetFocus()
color:SetText("ABC123")
color.scripts.OnTextChanged(color, true)
click("Default")
expect(color:GetText() == "ABC123", "font refresh discarded a focused color edit")
click("Gains")
color:ClearFocus()
click("Appearance")
expect(color:GetText() == "ABC123", "tab switch discarded a focused color edit")
click("Apply")
expect(not color:HasFocus(), "color apply did not release focus")
expect(ADDON.GetOptions().incomingColor[1] == 171/255, "typed color was not applied")
color:SetText("000000")
color.scripts.OnTextChanged(color, true)
color.scripts.OnEscapePressed(color)
expect(color:GetText() == "ABC123", "Escape did not discard the uncommitted color draft")

-- Profile destructive actions require a second click for the same action/name.
click("Profiles")
local name = editors()[1]
name:SetText("Careful")
click("Save")
local profile = ClearCombatTextDB.profiles.Careful
expect(profile, "new profile save failed")
ADDON.SetOption(nil, "fontScale", 1.5)
click("Save")
expect(ClearCombatTextDB.profiles.Careful == profile, "overwrite happened without confirmation")
click("Save")
expect(ClearCombatTextDB.profiles.Careful.options.fontScale == 1.5, "confirmed overwrite failed")
click("Delete")
expect(ClearCombatTextDB.profiles.Careful, "profile deleted without confirmation")
name:SetText("Other")
name:SetText("Careful")
click("Delete")
expect(ClearCombatTextDB.profiles.Careful, "editing a name did not cancel deletion confirmation")
panel:Hide()
ADDON.ToggleConfig()
click("Delete")
expect(ClearCombatTextDB.profiles.Careful, "closing settings did not cancel deletion confirmation")
click("Delete")
expect(not ClearCombatTextDB.profiles.Careful, "confirmed deletion failed")

-- Reopen refreshes controls through the native OnShow path, not a direct test call.
ADDON.ToggleConfig()
ADDON.SetOption(nil, "font", "default")
ADDON.ToggleConfig()
click("Appearance")
expect(button("Default"), "reopened panel retained stale controls")

-- Closing settings stops its demo but leaves live combat text alone.
ADDON.Preview(true)
EVENTS[1] = { data = 123 }
main.hooks.OnEvent(main, "COMBAT_TEXT_UPDATE", "SPELL_DAMAGE")
panel:Hide()
CLOCK = CLOCK + 0.5
updater.scripts.OnUpdate(updater, 0.5)
local real
for _, fs in ipairs(FONTSTRINGS) do
    local point = fs.points[#fs.points]
    if fs:IsShown() and point and (point[2] == _G.ClearCombatTextIncomingAnchor or point[2] == _G.ClearCombatTextGainsAnchor) then
        expect(not fs.text:find("[Preview]", 1, true), "closing settings left a demo active")
        if fs.text == "123" then real = true end
    end
end
expect(real, "closing settings removed live combat text")
io.write("UI REVIEW PASSED\n")
