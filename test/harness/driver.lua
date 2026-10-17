-- Driver: fires the addon through its real paths and asserts behaviour.

local function expect(cond, msg)
    if not cond then error("ASSERT FAILED: " .. msg, 0) end
end

-- find the addon's main frame (registered PLAYER_LOGIN) and fire it
local mainFrame
for _, fr in ipairs(FRAMES) do
    if fr.events and fr.events.PLAYER_LOGIN then mainFrame = fr break end
end
expect(mainFrame, "main frame never created")
mainFrame.scripts.OnEvent(mainFrame, "PLAYER_LOGIN")

-- 1. login banner + unit binding
mainFrame.scripts.OnEvent(mainFrame, "PLAYER_LOGIN")
expect(C_CombatText.activeUnit == "player", "login did not bind the player: " .. tostring(C_CombatText.activeUnit))
local banner = false
for _, l in ipairs(OUT) do if l:find("ClearCombatText loaded", 1, true) then banner = true end end
expect(banner, "login banner missing")

-- 2. full pipeline: first hit renders IMMEDIATELY, repeats update in place,
--    window expiry releases the claim without a delayed second render
SHOWN = {}
EVENTS[#EVENTS + 1] = { data = 340 }
mainFrame.scripts.OnEvent(mainFrame, "COMBAT_TEXT_UPDATE", "SPELL_DAMAGE")
mainFrame.hooks.OnEvent(mainFrame, "COMBAT_TEXT_UPDATE", "SPELL_DAMAGE")
expect(#SHOWN == 1 and SHOWN[1] == "340", "first hit did not render immediately: " .. table.concat(SHOWN, ","))

CLOCK = CLOCK + 0.1
EVENTS[#EVENTS + 1] = { data = 340 }
mainFrame.hooks.OnEvent(mainFrame, "COMBAT_TEXT_UPDATE", "SPELL_DAMAGE")
CLOCK = CLOCK + 0.1
EVENTS[#EVENTS + 1] = { data = 340 }
mainFrame.hooks.OnEvent(mainFrame, "COMBAT_TEXT_UPDATE", "SPELL_DAMAGE")
expect(#SHOWN == 1, "repeats created new strings instead of updating in place: " .. #SHOWN)
local grew = false
for _, fs in ipairs(FONTSTRINGS) do
    if fs.text == "1020 x3" then grew = true end
end
expect(grew, "in-place consolidation text never became '1020 x3'")

-- window expires: pending clears, no extra render fires
local updater
for _, fr in ipairs(FRAMES) do
    if fr.scripts and fr.scripts.OnUpdate then updater = fr end
end
expect(updater, "updater frame never created")
CLOCK = CLOCK + 0.6
SHOWN = {}
updater.scripts.OnUpdate(updater, 0.1)
expect(#SHOWN == 0, "window expiry rendered a duplicate: " .. table.concat(SHOWN, ","))

-- 4. animation branch: mid-lifetime the string rises, fades, crits pop
SHOWN = {}
local function fire(mtype, data, a2, a3)
    EVENTS[#EVENTS + 1] = { data = data, a2 = a2, a3 = a3 }
    mainFrame.hooks.OnEvent(mainFrame, "COMBAT_TEXT_UPDATE", mtype)
end
fire("SPELL_DAMAGE_CRIT", 4912)
local critFs
for _, fs2 in ipairs(FONTSTRINGS) do if fs2.text == "4912" then critFs = fs2 end end
expect(critFs, "crit string not found")
local beforeY = select(5, critFs:GetPoint()) or 0
CLOCK = CLOCK + 0.5
updater.scripts.OnUpdate(updater, 0.5)
local _, _, _, afterX, afterY = critFs:GetPoint()
expect((afterY or 0) > (beforeY or 0), "string did not rise: " .. tostring(beforeY) .. " -> " .. tostring(afterY))
expect((critFs.alpha or 1) < 1, "string did not fade, alpha=" .. tostring(critFs.alpha))
-- expired after full lifetime
CLOCK = CLOCK + 2.0
updater.scripts.OnUpdate(updater, 0.1)

-- 5. loading screen keeps the stream bound
mainFrame.scripts.OnEvent(mainFrame, "PLAYER_ENTERING_WORLD", 1412)
expect(C_CombatText.activeUnit == "player", "rebind after loading screen failed: " .. tostring(C_CombatText.activeUnit))

-- Independent anchors, migration, persistence and directions.
local anchorFrame, gainsFrame
for _, fr in ipairs(FRAMES) do
    if fr.name == "ClearCombatTextIncomingAnchor" then anchorFrame = fr end
    if fr.name == "ClearCombatTextGainsAnchor" then gainsFrame = fr end
end
expect(anchorFrame and gainsFrame, "stream anchors not found")
ClearCombatTextDB.anchor = { point = "CENTER", relPoint = "CENTER", x = -50, y = 200 }
mainFrame.scripts.OnEvent(mainFrame, "PLAYER_LOGIN")
expect(select(4, anchorFrame:GetPoint()) == -230, "incoming migration offset lost")
expect(select(4, gainsFrame:GetPoint()) == 130, "gains migration offset lost")
expect(ClearCombatTextDB.anchor == nil, "legacy anchor not migrated")
anchorFrame:SetPoint("CENTER", UIParent, "CENTER", -50, 200)
anchorFrame.scripts.OnDragStop()
expect(ClearCombatTextDB.streams.incoming.x == -50 and ClearCombatTextDB.streams.incoming.y == 200,
    "drag stop did not save position")
expect(select(4, gainsFrame:GetPoint()) == 130, "moving incoming moved gains")
-- simulate a relogin: fresh login event restores the saved point
anchorFrame:ClearAllPoints()
anchorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
mainFrame.scripts.OnEvent(mainFrame, "PLAYER_LOGIN")
local _, _, _, rx, ry = anchorFrame:GetPoint()
expect(rx == -50 and ry == 200, "restore did not apply saved position: " .. tostring(rx) .. "," .. tostring(ry))
-- reset clears both the live point and the saved one
SlashCmdList.CLEARCOMBATTEXT("reset")
expect(ClearCombatTextDB.streams.incoming == nil, "reset did not clear the saved position")
local _, _, _, nx, ny = anchorFrame:GetPoint()
expect(nx == -180 and ny == 120, "reset did not restore the default position")

SlashCmdList.CLEARCOMBATTEXT("anchor incoming")
expect(anchorFrame:IsShown() and not gainsFrame:IsShown(), "individual unlock affected other stream")
SlashCmdList.CLEARCOMBATTEXT("anchor incoming")
expect(not anchorFrame:IsShown(), "individual anchor failed to lock")
SlashCmdList.CLEARCOMBATTEXT("anchor")
expect(anchorFrame:IsShown() and gainsFrame:IsShown(), "both anchors did not unlock")
SlashCmdList.CLEARCOMBATTEXT("anchor")

for _, direction in ipairs({ "up", "down", "left", "right" }) do
    SlashCmdList.CLEARCOMBATTEXT("direction incoming " .. direction)
    mainFrame.scripts.OnEvent(mainFrame, "PLAYER_LOGIN")
    expect(ClearCombatTextDB.streams.incoming.direction == direction, "direction not saved")
    CLOCK = CLOCK + 2
    updater.scripts.OnUpdate(updater, 2)
    fire("SPELL_DAMAGE", 721)
    fire("HEAL", "Healer", 722)
    local incoming, gains
    for _, fs in ipairs(FONTSTRINGS) do
        if fs.text == "721" then incoming = fs end
        if fs.text == "722" then gains = fs end
    end
    CLOCK = CLOCK + 0.5
    updater.scripts.OnUpdate(updater, 0.5)
    local _, parent, _, x, y = incoming:GetPoint()
    expect(parent == anchorFrame, "incoming rendered against wrong anchor")
    expect((direction == "up" and y > 0) or (direction == "down" and y < 0)
        or (direction == "left" and x < 0) or (direction == "right" and x > 0), "wrong scroll direction")
    local _, gainsParent, _, _, gainsY = gains:GetPoint()
    expect(gainsParent == gainsFrame and gainsY > 0, "incoming direction changed gains")
end
SlashCmdList.CLEARCOMBATTEXT("direction incoming invalid")
expect(ClearCombatTextDB.streams.incoming.direction == "right", "invalid direction accepted")

-- 5c. anchor restores on login even without C_CombatText (Classic client)
local savedSecrets = C_CombatText
C_CombatText = nil
anchorFrame:ClearAllPoints()
anchorFrame:SetPoint("CENTER", UIParent, "CENTER", -50, 200)
anchorFrame.scripts.OnDragStop()
anchorFrame:ClearAllPoints()
anchorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
mainFrame.scripts.OnEvent(mainFrame, "PLAYER_LOGIN")
local _, _, _, cx, cy = anchorFrame:GetPoint()
expect(cx == -50 and cy == 200, "anchor did not restore on a C_CombatText-less client")
C_CombatText = savedSecrets

-- 6. /cct test renders five strings
SHOWN = {}
SlashCmdList.CLEARCOMBATTEXT("test")
expect(#SHOWN >= 5, "test render produced " .. #SHOWN .. " strings")
expect(table.concat(SHOWN, " "):find("4,912", 1, true), "crit damage missing from test render")
expect(table.concat(SHOWN, " "):find("Clearcasting", 1, true), "aura start missing from test render")

-- 4. /cct status line
OUT = {}
SlashCmdList.CLEARCOMBATTEXT("")
local sawUsage = false
for _, l in ipairs(OUT) do if l:find("/cct test", 1, true) then sawUsage = true end end
expect(sawUsage, "usage line missing")

-- Missing API functions skip safely, without a protected call per event.
local saved = C_CombatText.GetCurrentEventInfo
C_CombatText.GetCurrentEventInfo = nil
fire("SPELL_DAMAGE", 100)
C_CombatText.GetCurrentEventInfo = saved

-- Secret sentinels reject the original length bug and any numeric conversion.
-- This is not WoW taint emulation, but verifies payloads stay on display paths.
local secret = setmetatable({ secret = true }, {
    __len = function() error("length of secret") end,
    __tostring = function() return "secret display" end,
})
local originalTonumber, originalPcall = tonumber, pcall
tonumber = function(value)
    expect(value ~= secret, "secret reached tonumber")
    return originalTonumber(value)
end
pcall = function() error("protected call on combat hot path") end
CLOCK = CLOCK + 3
updater.scripts.OnUpdate(updater, 3)
SHOWN = {}
fire("SPELL_AURA_START", secret)
fire("AURA_START", secret)
fire("SPELL_DAMAGE", secret)
fire("SPELL_DAMAGE", secret)
fire("UNKNOWN_EVENT", secret)
expect(#SHOWN == 5, "secret payloads consolidated or dropped")
expect(SHOWN[1] == "secret display", "reported aura path failed")
local detector = issecretvalue
issecretvalue = nil
CLOCK = CLOCK + 3
updater.scripts.OnUpdate(updater, 3)
SHOWN = {}
fire("SPELL_DAMAGE", secret)
fire("SPELL_DAMAGE", 123)
fire("SPELL_DAMAGE", 123)
expect(#SHOWN == 3, "no-detector beta attempted consolidation")
fire("HEAL", "Healer", secret)
expect(SHOWN[4] == "secret display", "secondary secret payload was dropped")
issecretvalue = detector
mainFrame.hooks.OnEvent(mainFrame, "COMBAT_TEXT_UPDATE", secret)
mainFrame.hooks.OnEvent(mainFrame, "COMBAT_TEXT_UPDATE", nil)
CLOCK = CLOCK + 0.2
updater.scripts.OnUpdate(updater, 0.2)
CLOCK = CLOCK + 2
updater.scripts.OnUpdate(updater, 2)
fire("SPELL_DAMAGE_CRIT", secret)
CLOCK = CLOCK + 0.1
updater.scripts.OnUpdate(updater, 0.1)
issecretvalue, tonumber, pcall = detector, originalTonumber, originalPcall

io.write("ALL CHECKS PASSED\n")
io.write(table.concat(SHOWN, " | ") .. "\n")
