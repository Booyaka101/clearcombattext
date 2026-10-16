local function expect(cond, msg)
    if not cond then error("ASSERT FAILED [" .. CASE .. "]: " .. msg, 0) end
end

local main, incoming, gains, updater
for _, frame in ipairs(FRAMES) do
    if frame.events and frame.events.PLAYER_LOGIN then main = frame end
    if frame.name == "ClearCombatTextIncomingAnchor" then incoming = frame end
    if frame.name == "ClearCombatTextGainsAnchor" then gains = frame end
    if frame.scripts and frame.scripts.OnUpdate then updater = frame end
end
main.scripts.OnEvent(main, "PLAYER_LOGIN")
local function centerX(frame)
    local point, _, _, x = frame:GetPoint()
    -- UIParent-relative coordinates suffice to compare these same-relativePoint
    -- migration fixtures; include each frame's real attachment-to-center offset.
    return x + (point:find("LEFT") and frame.width / 2 or (point:find("RIGHT") and -frame.width / 2 or 0))
end

if CASE == "left" or CASE == "right" or CASE == "corner" then
    local oldCenter = CASE == "right" and -180 or 80
    expect(centerX(incoming) == oldCenter - 180, "legacy incoming center moved")
    expect(centerX(gains) == oldCenter + 180, "legacy gains center moved")
    expect(ClearCombatTextDB.anchor == nil, "old position was not migrated")
elseif CASE == "saved" or CASE == "partial" then
    expect(select(4, incoming:GetPoint()) == 222, "saved incoming position lost")
    expect(select(4, gains:GetPoint()) == (CASE == "partial" and 130 or 333), "other position lost")
    SlashCmdList.CLEARCOMBATTEXT("test")
    CLOCK = 0.5
    updater.scripts.OnUpdate(updater, 0.5)
    local sawIncoming, sawGains
    for _, fs in ipairs(FONTSTRINGS) do
        if fs:IsShown() then
            local _, parent, _, x, y = fs:GetPoint()
            if parent == incoming then expect(y < 0, "saved direction not restored"); sawIncoming = true end
            if parent == gains then
                if CASE == "saved" then expect(x < 0, "gains direction not restored") end
                sawGains = true
            end
        end
    end
    expect(sawIncoming and sawGains, "preview missing a stream")
else
    expect(select(4, incoming:GetPoint()) == -180, "invalid settings did not default")
    expect(select(4, gains:GetPoint()) == 180, "invalid gains did not default")
    SlashCmdList.CLEARCOMBATTEXT("direction incoming down")
    expect(ClearCombatTextDB.streams.incoming.direction == "down", "invalid settings not repairable")
end
io.write("STARTUP PASSED: " .. CASE .. "\n")
