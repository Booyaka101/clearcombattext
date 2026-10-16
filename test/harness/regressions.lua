local function expect(cond, msg)
    if not cond then error("ASSERT FAILED: " .. msg, 0) end
end

local main, updater, incoming, gains
for _, frame in ipairs(FRAMES) do
    if frame.events and frame.events.PLAYER_LOGIN then main = frame end
    if frame.scripts and frame.scripts.OnUpdate then updater = frame end
    if frame.name == "ClearCombatTextIncomingAnchor" then incoming = frame end
    if frame.name == "ClearCombatTextGainsAnchor" then gains = frame end
end
main.scripts.OnEvent(main, "PLAYER_LOGIN")
expect(not updater:IsShown(), "idle updater is running")

local function expire()
    CLOCK = CLOCK + 3
    updater.scripts.OnUpdate(updater, 3)
    expect(not updater:IsShown(), "empty updater did not sleep")
end

local function fire(kind, data, a2, a3)
    EVENTS[1] = { data = data, a2 = a2, a3 = a3 }
    main.scripts.OnEvent(main, "COMBAT_TEXT_UPDATE", kind)
    main.hooks.OnEvent(main, "COMBAT_TEXT_UPDATE", kind)
end

local function lastShown()
    for _, fs in ipairs(FONTSTRINGS) do
        if fs:IsShown() then return fs end
    end
    error("no shown font string")
end

local function parent(fs)
    return fs.points[#fs.points][2]
end

-- Shared toggle converges even after an individual unlock.
SlashCmdList.CLEARCOMBATTEXT("anchor incoming")
SlashCmdList.CLEARCOMBATTEXT("anchor")
expect(incoming:IsShown() and gains:IsShown(), "mixed state did not unlock both")
SlashCmdList.CLEARCOMBATTEXT("anchor")
expect(not incoming:IsShown() and not gains:IsShown(), "mixed state did not lock both")
expect(not incoming.mouseEnabled and not gains.mouseEnabled, "locked areas intercept clicks")
SlashCmdList.CLEARCOMBATTEXT("anchor incoming nonsense")
expect(not incoming:IsShown(), "anchor accepted trailing garbage")

-- Vehicle entry uses showVehicle, exit binds player even before UI state updates.
main.scripts.OnEvent(main, "UNIT_ENTERED_VEHICLE", "party1", true)
expect(C_CombatText.activeUnit == "player", "another unit changed binding")
main.scripts.OnEvent(main, "UNIT_ENTERED_VEHICLE", "player", true)
expect(C_CombatText.activeUnit == "vehicle", "vehicle entry not bound")
VEHICLE_UI = true
main.scripts.OnEvent(main, "UNIT_EXITING_VEHICLE", "player")
expect(C_CombatText.activeUnit == "player", "vehicle exit depended on stale UI")
main.scripts.OnEvent(main, "UNIT_ENTERED_VEHICLE", "player", false)
expect(C_CombatText.activeUnit == "player", "non-UI vehicle changed binding")
fire("SPELL_DAMAGE", 100)
main.scripts.OnEvent(main, "UNIT_ENTERED_VEHICLE", "player", true)
fire("SPELL_DAMAGE", 200)
for _, fs in ipairs(FONTSTRINGS) do
    expect(fs.text ~= "300 x2", "different bound units consolidated together")
end
expire()

-- The first payload is a healer name, never an alternate amount.
local secret = setmetatable({ secret = true }, { __tostring = function() return "secret display" end })
main.scripts.OnEvent(main, "COMBAT_TEXT_UPDATE", secret)
main.hooks.OnEvent(main, "COMBAT_TEXT_UPDATE", secret)
for _, detector in ipairs({ true, false }) do
    local savedDetector = issecretvalue
    if not detector then issecretvalue = nil end
    for _, kind in ipairs({ "HEAL", "HEAL_CRIT", "PERIODIC_HEAL", "PERIODIC_HEAL_CRIT", "ABSORB_ADDED" }) do
        expire()
        fire(kind, "Healer", secret)
        expect(lastShown().text == "secret display", kind .. " displayed healer rather than secret amount")
        expect(parent(lastShown()) == gains, "healing in wrong area")
    end
    expire()
    fire("HEAL", "Healer", 1200)
    expect(lastShown().text == "1200", "public heal amount wrong without detector")
    expire()
    fire("SPELL_DAMAGE", secret, 777)
    expect(lastShown().text == "secret display", "secondary value replaced secret primary")
    issecretvalue = savedDetector
end

for _, kind in ipairs({ "SPELL_MISS", "SPELL_DODGE", "SPELL_PARRY", "SPELL_EVADE", "SPELL_IMMUNE", "SPELL_REFLECT", "DEFLECT", "REFLECT" }) do
    expire()
    fire(kind)
    expect(lastShown().text ~= "", "payload-free avoidance disappeared")
    expect(parent(lastShown()) == incoming, "avoidance in wrong area")
end
for _, kind in ipairs({ "SPELL_AURA_START_HARMFUL", "SPELL_AURA_END_HARMFUL", "DAMAGE_SHIELD", "SPLIT_DAMAGE" }) do
    expire()
    fire(kind, 123)
    expect(parent(lastShown()) == incoming, kind .. " in wrong area")
end
for _, kind in ipairs({ "BLOCK", "ABSORB", "RESIST", "SPELL_BLOCK", "SPELL_ABSORB", "SPELL_RESIST" }) do
    expire()
    fire(kind, 100, 900, true)
    local fs = lastShown()
    expect(fs.text:find("100", 1, true) and fs.text:find("900", 1, true), "partial mitigation lost a field")
    expect(fs.size == 26 and parent(fs) == incoming, "mitigation style/area incorrect")
    expire()
    fire(kind)
    expect(lastShown().text ~= "", "complete mitigation disappeared")
    local label = kind:gsub("SPELL_", "")
    expect(lastShown().text == _G["COMBAT_TEXT_" .. label], "spell mitigation bypassed localized label")
    expire()
    fire(kind, secret, secret, secret)
    expect(lastShown().text:find("secret display", 1, true), "secret mitigation not formatted")
end
expire()
fire("HEAL_CRIT_ABSORB", "Healer", 123, 456)
expect(lastShown().text == "+123 (456 absorbed)", "absorbed heal lost positional amounts")

-- Distinct resource kinds must not sum together.
expire()
SHOWN = {}
fire("ENERGIZE", 10, "MANA")
fire("ENERGIZE", 20, "ENERGY")
fire("ENERGIZE", 10, "MANA")
expect(#SHOWN == 2, "resource grouping created wrong number of lines")
local mana
for _, fs in ipairs(FONTSTRINGS) do if fs:IsShown() and fs.text == "20 x2" then mana = fs end end
expect(mana, "mana did not consolidate separately")

-- The actual Blizzard CVar is checked and changed, not a similarly named alias.
GetCVarBool = function(name) expect(name == "enableFloatingCombatText", "wrong floating-text CVar"); return true end
SetCVar = function(name, value)
    expect(name == "enableFloatingCombatText" and value == false, "wrong CVar toggle")
end
SlashCmdList.CLEARCOMBATTEXT("blizz")
expire()
main.scripts.OnEvent(main, "PLAYER_REGEN_DISABLED")
expect(lastShown().text == ENTERING_COMBAT, "combat entry alert missing")
expire()
local namespace = C_CombatText
C_CombatText = nil
main.scripts.OnEvent(main, "PLAYER_REGEN_DISABLED")
expect(not updater:IsShown(), "unsupported client rendered combat event")
C_CombatText = namespace

-- Burst policy bounds widgets; expiry hides all, and reuse resets alpha and size.
expire()
issecretvalue = nil
for i = 1, 2000 do fire("SPELL_DAMAGE_CRIT", 1) end
local visible = 0
for _, fs in ipairs(FONTSTRINGS) do if fs:IsShown() then visible = visible + 1 end end
expect(visible == 128 and #FONTSTRINGS == 130, "burst allocation was not bounded")
expect(updater:IsShown(), "active updater stayed asleep")
CLOCK = CLOCK + 0.05
updater.scripts.OnUpdate(updater, 0.05)
CLOCK = CLOCK + 0.2
updater.scripts.OnUpdate(updater, 0.2)
local calls = lastShown().fontCalls
CLOCK = CLOCK + 0.2
updater.scripts.OnUpdate(updater, 0.2)
expect(lastShown().fontCalls == calls, "settled crit font rewritten each frame")
expire()
for _, fs in ipairs(FONTSTRINGS) do expect(not fs:IsShown(), "expired widget still shown") end
local allocated = #FONTSTRINGS
fire("SPELL_DAMAGE", 5)
local reused = lastShown()
expect(#FONTSTRINGS == allocated, "pool not reused")
expect(reused.size == 20 and reused.alpha == 1, "pooled widget style not reset")
expect(#reused.points == 1, "pooled widget retained previous anchors")
io.write("REGRESSIONS PASSED\n")
