local function expect(condition, message)
    if not condition then error("ASSERT FAILED: " .. message, 0) end
end

local main, updater, incoming
for _, frame in ipairs(FRAMES) do
    if frame.events and frame.events.PLAYER_LOGIN then main = frame end
    if frame.scripts and frame.scripts.OnUpdate then updater = frame end
    if frame.name == "ClearCombatTextIncomingAnchor" then incoming = frame end
end
main.scripts.OnEvent(main, "PLAYER_LOGIN")
local function fire(value)
    EVENTS[1] = { data = value }
    main.hooks.OnEvent(main, "COMBAT_TEXT_UPDATE", "SPELL_DAMAGE")
end
local function shown()
    local list = {}
    for _, fs in ipairs(FONTSTRINGS) do
        local p = fs.points[#fs.points]
        if fs:IsShown() and p and p[2] == incoming then list[#list + 1] = fs end
    end
    return list
end
local secret = setmetatable({ secret = true }, { __tostring = function() return "secret display" end })

-- WoW may deliver events before OnUpdate has reclaimed expired capacity.
for i = 1, 8 do fire(secret) end
expect(#shown() == 8, "expiry fixture did not fill stream")
CLOCK = 2
SHOWN = {}
fire(secret)
expect(#SHOWN == 1 and #shown() == 1, "expired lines blocked a fresh event before OnUpdate")

-- Group public bursts from the first hit, not from the most recent repeat.
ADDON.SetDirection("incoming", "up")
fire(10)
CLOCK = CLOCK + 0.3
updater.scripts.OnUpdate(updater, 0.3)
fire(10)
expect(#shown() == 1 and shown()[1].text == "20 x2", "short burst no longer consolidates")
CLOCK = CLOCK + 0.3
updater.scripts.OnUpdate(updater, 0.3)
SHOWN = {}
fire(10)
expect(#SHOWN == 1 and #shown() == 2, "continuous hits merged into an aging line past its burst window")

-- Demo criticals/warnings must not displace real data or block ordinary events.
ADDON.SetOption("incoming", "maxLines", 4)
ADDON.Preview()
for i = 1, 4 do fire(secret) end
local real = 0
for _, fs in ipairs(shown()) do if fs.text == "secret display" then real = real + 1 end end
expect(real == 4, "preview priority blocked real combat events")
ADDON.Preview(true)
expect(#shown() == 4, "preview exceeded the real stream capacity")
for _, fs in ipairs(shown()) do expect(fs.text == "secret display", "preview evicted real combat data") end
ADDON.StopPreview()
expect(#shown() == 4, "stopping preview removed real combat data")
ADDON.SetDirection("incoming", "up")
ADDON.Preview(true)
expect(shown()[1].text:find("[Preview]", 1, true), "demo text is indistinguishable from real warnings")
ADDON.StopPreview()
expect(#shown() == 0 and not updater:IsShown(), "stopping the demo did not sleep")

-- Exercise the largest font/pop at zero extra spacing through slot reuse.
ADDON.SetOption(nil, "fontScale", 1.8)
ADDON.SetOption(nil, "critScale", 1.8)
ADDON.SetOption("incoming", "spacing", 0)
ADDON.SetOption("incoming", "maxLines", 8)
ADDON.SetOption("incoming", "duration", 0.8)
for _, direction in ipairs({ "up", "down", "left", "right" }) do
    ADDON.SetDirection("incoming", direction)
    for step = 1, 40 do
        CLOCK = CLOCK + 0.05
        updater.scripts.OnUpdate(updater, 0.05)
        EVENTS[1] = { data = secret }
        main.hooks.OnEvent(main, "COMBAT_TEXT_UPDATE", step % 3 == 0 and "SPELL_DAMAGE_CRIT" or "SPELL_DAMAGE")
        local rows = {}
        for _, fs in ipairs(shown()) do
            local p = fs.points[#fs.points]
            rows[#rows + 1] = p[5]
        end
        table.sort(rows)
        expect(#rows <= 8, "stress test exceeded stream capacity")
        for i = 2, #rows do expect(rows[i] - rows[i - 1] >= 95 - 0.0001, "maximum-size rows collided during reuse") end
    end
end
CLOCK = CLOCK + 1
updater.scripts.OnUpdate(updater, 1)
expect(#shown() == 0 and not updater:IsShown(), "stress display did not suspend when idle")

io.write("RENDER REVIEW PASSED\n")
