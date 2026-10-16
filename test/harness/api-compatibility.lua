local function expect(value, message)
    if not value then error(message) end
end

local main
for _, frame in ipairs(FRAMES) do
    if frame.events and frame.events.COMBAT_TEXT_UPDATE then main = frame end
end
expect(main, "combat event frame missing")

-- Exercise the helper directly so caller guards cannot conceal an unsafe lookup.
local bindUnit
for i = 1, 20 do
    local name, value = debug.getupvalue(main.scripts.OnEvent, i)
    if not name then break end
    if name == "bindUnit" then bindUnit = value; break end
end
expect(bindUnit, "binding helper missing")
-- Invalid API members must be rejected before pcall, not probed by calling them.
local originalPcall = pcall
pcall = function(fn, ...)
    expect(type(fn) == "function", "non-function API member passed to pcall")
    return originalPcall(fn, ...)
end
local canBind = C_CombatText and type(C_CombatText.SetActiveUnit) == "function" or false
local canRead = C_CombatText and type(C_CombatText.GetCurrentEventInfo) == "function" or false
expect(bindUnit("player") == canBind, "binding result did not match API availability")

for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "UNIT_ENTERED_VEHICLE", "UNIT_EXITING_VEHICLE", "UNIT_PET" }) do
    main.scripts.OnEvent(main, event, "player", true)
end
local count = #SHOWN
EVENTS[#EVENTS + 1] = { data = 123 }
main.hooks.OnEvent(main, "COMBAT_TEXT_UPDATE", "SPELL_DAMAGE")
expect(#SHOWN == count + (canRead and 1 or 0), "payload rendering did not match API availability")
if canRead then expect(SHOWN[#SHOWN] == "123", "available payload API returned wrong text") end
count = #SHOWN

-- APIs becoming available after addon load must not stay cached as nil.
C_CombatText = originalCombatText
local restoredUnit
C_CombatText.SetActiveUnit = function(unit) restoredUnit = unit end
expect(bindUnit("player"), "restored binding API was not resolved")
expect(restoredUnit == "player", "restored API did not bind player")
CLOCK = 1
EVENTS[#EVENTS + 1] = { data = 321 }
main.hooks.OnEvent(main, "COMBAT_TEXT_UPDATE", "SPELL_DAMAGE")
expect(#SHOWN == count + 1 and SHOWN[#SHOWN] == "321", "restored payload API did not render")

-- Losing the namespace after initialization must also be safe.
C_CombatText = nil
expect(bindUnit("vehicle") == false, "removed binding API should return false")
main.hooks.OnEvent(main, "COMBAT_TEXT_UPDATE", "SPELL_DAMAGE")
expect(#SHOWN == count + 1, "removed payload API rendered a combat event")
