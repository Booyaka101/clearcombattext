-- ClearCombatText.lua — scrolling combat text that stays readable under the secret-value API.
--
-- C_CombatText provides incoming combat text for the selected unit. This addon
-- separates damage taken from heals and gains; it does not reconstruct outgoing
-- per-spell damage from the combat log or bypass secret-value restrictions.
--
-- Combat payloads go straight to display unless the client can prove them public.

-- ---------------------------------------------------------------------------
-- event info access

local function cleanNum(value)
    -- Older beta clients have no detector. Display their payloads without math;
    -- never probe secrecy by deliberately throwing from a per-event closure.
    if not issecretvalue or issecretvalue(value) then return nil end
    if type(value) ~= "number" and type(value) ~= "string" then return nil end
    local n = tonumber(value)
    if n and n == n and math.abs(n) < math.huge then return n end
end

local pending = {}
local boundUnit
local function bindUnit(unit)
    local setActiveUnit = C_CombatText and C_CombatText.SetActiveUnit
    if type(setActiveUnit) ~= "function" then return false end
    local ok = pcall(setActiveUnit, unit)
    if ok and boundUnit ~= unit then
        pending = {}
        boundUnit = unit
    end
    return ok
end

-- ---------------------------------------------------------------------------
-- message classification
-- Colors follow the MSBT conventions players have read for fifteen years.

local TYPES = {
    SPELL_DAMAGE        = { color = { 1.00, 0.95, 0.55 }, size = 20 },
    SPELL_DAMAGE_CRIT   = { color = { 1.00, 0.62, 0.00 }, size = 28, crit = true },
    SPELL_SPLIT_DAMAGE  = { color = { 1.00, 0.95, 0.55 }, size = 18 },
    DAMAGE              = { color = { 1.00, 1.00, 1.00 }, size = 18 },
    DAMAGE_CRIT         = { color = { 1.00, 0.82, 0.00 }, size = 26, crit = true },
    PERIODICAURA_DAMAGE = { color = { 0.80, 0.60, 1.00 }, size = 15, dim = true },
    SPELL_DAMAGE_SHIELD = { color = { 0.70, 0.80, 1.00 }, size = 16 },
    HEAL                = { color = { 0.10, 0.95, 0.10 }, size = 17 },
    HEAL_CRIT           = { color = { 0.10, 1.00, 0.40 }, size = 24, crit = true },
    PERIODICHEAL        = { color = { 0.10, 0.75, 0.10 }, size = 14, dim = true },
    ABSORB              = { color = { 0.55, 0.75, 1.00 }, size = 15 },
    RESIST              = { color = { 0.60, 0.60, 0.90 }, size = 14, dim = true },
    BLOCK               = { color = { 0.60, 0.60, 0.90 }, size = 14, dim = true },
    MISS                = { color = { 0.85, 0.85, 0.85 }, size = 15, text = true },
    DODGE               = { color = { 0.85, 0.85, 0.85 }, size = 15, text = true },
    PARRY               = { color = { 0.85, 0.85, 0.85 }, size = 15, text = true },
    EVADE               = { color = { 0.85, 0.85, 0.85 }, size = 15, text = true },
    IMMUNE              = { color = { 0.85, 0.85, 0.85 }, size = 15, text = true },
    HEALTH_LOW          = { color = { 1.00, 0.15, 0.15 }, size = 20, text = true },
    MANA_LOW            = { color = { 0.30, 0.55, 1.00 }, size = 20, text = true },
    MANA                = { color = { 0.30, 0.55, 1.00 }, size = 14, dim = true },
    ENERGY              = { color = { 1.00, 0.85, 0.10 }, size = 14, dim = true },
    RAGE                = { color = { 1.00, 0.35, 0.10 }, size = 14, dim = true },
    FOCUS               = { color = { 1.00, 0.60, 0.20 }, size = 14, dim = true },
    RUNE                = { color = { 0.60, 0.85, 1.00 }, size = 14 },
    COMBO_POINTS        = { color = { 1.00, 0.75, 0.20 }, size = 16 },
    HONOR_GAINED        = { color = { 0.65, 0.35, 1.00 }, size = 16 },
    AURA_START          = { color = { 0.35, 1.00, 0.60 }, size = 15, text = true },
    AURA_END            = { color = { 0.55, 0.75, 0.60 }, size = 14, text = true, dim = true },
    AURA_START_HARMFUL  = { color = { 1.00, 0.40, 0.30 }, size = 15, text = true },
    AURA_END_HARMFUL    = { color = { 0.90, 0.55, 0.50 }, size = 14, text = true, dim = true },
    SPELL_AURA_START    = { color = { 0.35, 1.00, 0.60 }, size = 15, text = true },
    SPELL_AURA_END      = { color = { 0.55, 0.75, 0.60 }, size = 14, text = true, dim = true },
    ENTERING_COMBAT     = { color = { 1.00, 0.55, 0.00 }, size = 16, text = true },
    LEAVING_COMBAT      = { color = { 0.60, 0.60, 0.60 }, size = 16, text = true, dim = true },
    EXPERIENCE_GAINED   = { color = { 0.60, 0.40, 1.00 }, size = 15 },
    MONEY               = { color = { 1.00, 0.85, 0.00 }, size = 14 },
    SPELL_CAST          = { color = { 1.00, 0.95, 0.55 }, size = 15, text = true },
    DISPELFAILED        = { color = { 0.85, 0.50, 0.50 }, size = 14, text = true, dim = true },
    SPELL_REFLECT       = { color = { 0.70, 0.80, 1.00 }, size = 16 },
}

local TEXT_LABELS = {
    MISS = MISS, DODGE = DODGE, PARRY = PARRY, EVADE = EVADE, IMMUNE = IMMUNE,
    HEALTH_LOW = LOW_HEALTH, MANA_LOW = LOW_MANA,
    ENTERING_COMBAT = ENTERING_COMBAT, LEAVING_COMBAT = LEAVING_COMBAT,
}

-- Incoming damage types (things that hit you) render on the left stream.
local INCOMING = {
    DAMAGE = true, DAMAGE_CRIT = true, SPELL_DAMAGE = true, SPELL_DAMAGE_CRIT = true,
    SPELL_SPLIT_DAMAGE = true, PERIODICAURA_DAMAGE = true, MISS = true, DODGE = true,
    PARRY = true, EVADE = true, IMMUNE = true, AURA_START_HARMFUL = true,
}

-- Canonical names from Blizzard_CombatText/Shared/CombatText.lua. Keep the old
-- beta names above as aliases, but select payload fields before testing secrecy.
local ALIASES = {
    SPLIT_DAMAGE = "SPELL_SPLIT_DAMAGE", DAMAGE_SHIELD = "SPELL_DAMAGE_SHIELD",
    PERIODIC_HEAL = "PERIODICHEAL", PERIODIC_HEAL_CRIT = "HEAL_CRIT",
    HEAL_ABSORB = "HEAL", HEAL_CRIT_ABSORB = "HEAL_CRIT",
    PERIODIC_HEAL_ABSORB = "PERIODICHEAL", ABSORB_ADDED = "ABSORB",
    SPELL_AURA_START_HARMFUL = "AURA_START_HARMFUL", SPELL_AURA_END_HARMFUL = "AURA_END_HARMFUL",
    SPELL_MISS = "MISS", SPELL_DODGE = "DODGE", SPELL_PARRY = "PARRY",
    SPELL_EVADE = "EVADE", SPELL_IMMUNE = "IMMUNE",
    SPELL_BLOCK = "BLOCK", SPELL_ABSORB = "ABSORB", SPELL_RESIST = "RESIST",
}
for name, alias in pairs(ALIASES) do
    TYPES[name] = TYPES[alias]
    TEXT_LABELS[name] = TEXT_LABELS[alias]
    INCOMING[name] = INCOMING[alias]
end
local SECOND_AMOUNT = {
    HEAL = true, HEAL_CRIT = true, PERIODICHEAL = true, PERIODIC_HEAL = true,
    PERIODIC_HEAL_CRIT = true, HEAL_ABSORB = true, HEAL_CRIT_ABSORB = true,
    PERIODIC_HEAL_ABSORB = true, ABSORB_ADDED = true,
}
local MITIGATION = {
    BLOCK = "blocked", SPELL_BLOCK = "blocked", ABSORB = "absorbed",
    SPELL_ABSORB = "absorbed", RESIST = "resisted", SPELL_RESIST = "resisted",
}
for name in pairs(MITIGATION) do
    INCOMING[name] = true
    local label = name:gsub("SPELL_", "")
    TEXT_LABELS[name] = _G["COMBAT_TEXT_" .. label] or label
end
INCOMING.DAMAGE_SHIELD, INCOMING.SPELL_DAMAGE_SHIELD = true, true
INCOMING.AURA_END_HARMFUL, INCOMING.SPELL_AURA_END_HARMFUL = true, true
for _, name in ipairs({ "DEFLECT", "REFLECT", "SPELL_DEFLECT", "SPELL_REFLECT", "SPELL_MISFIRE" }) do
    TYPES[name] = TYPES.MISS
    INCOMING[name] = true
    TEXT_LABELS[name] = _G["COMBAT_TEXT_" .. name:gsub("SPELL_", "")] or name:gsub("SPELL_", "")
end
local UNKNOWN = { color = { 0.7, 0.7, 0.7 }, size = 14, dim = true }
local DEFAULT = { color = { 1, 1, 1 }, size = 18 }
local RESOURCE_TYPES = {
    MANA = TYPES.MANA, ENERGY = TYPES.ENERGY, RAGE = TYPES.RAGE, FOCUS = TYPES.FOCUS,
    RUNIC_POWER = TYPES.RUNE, COMBO_POINTS = TYPES.COMBO_POINTS,
    HOLY_POWER = DEFAULT, SOUL_SHARDS = DEFAULT, CHI = DEFAULT, ARCANE_CHARGES = DEFAULT,
}
TYPES.ENERGIZE, TYPES.PERIODIC_ENERGIZE = DEFAULT, DEFAULT

-- ---------------------------------------------------------------------------
-- consolidation: the first hit renders immediately; repeats inside the window
-- update that same line in place ("340" grows into "1020 x3") and refresh its
-- lifetime, so a burst reads as one living number instead of a queue delay.
-- (defined after render, which it calls)

local WINDOW = 0.45
local render -- forward-declared: consolidate calls it, defined below

local function consolidate(now, mtype, amount, opts, key)
    key = key or mtype
    local p = pending[key]
    if p and p.entry and p.entry.fs and not p.entry.done and (now - p.t) <= WINDOW and amount then
        p.n = p.n + 1
        p.sum = p.sum + amount
        p.t = now
        local text = BreakUpLargeNumbers(p.sum) .. " x" .. p.n
        p.entry.fs:SetText(text)
        p.entry.born = now
        return
    end
    if amount then
        local entry = render(now, mtype, BreakUpLargeNumbers(amount), opts)
        if entry and entry.fs then
            pending[key] = { t = now, n = 1, sum = amount, entry = entry }
        end
    end
end

-- ---------------------------------------------------------------------------
-- rendering: a pool of rising, fading font strings in two streams

local pool = {}
local active = {}
local MAX_ACTIVE = 128
local updater = CreateFrame("Frame")
updater:Hide()

if type(ClearCombatTextDB) ~= "table" then ClearCombatTextDB = {} end
local streams = {}
local DIRECTIONS = { up = { 0, 1 }, down = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
local POINTS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function validPosition(s)
    return type(s) == "table" and POINTS[s.point] and POINTS[s.relPoint] and finite(s.x) and finite(s.y)
end

local function savedStreams()
    -- WoW restores saved variables after executing addon files, so the load-time
    -- default alone cannot validate a persisted root. Recheck at first use.
    if type(ClearCombatTextDB) ~= "table" then ClearCombatTextDB = {} end
    if type(ClearCombatTextDB.streams) ~= "table" then ClearCombatTextDB.streams = {} end
    return ClearCombatTextDB.streams
end

local function saveAnchor(stream)
    local point, _, relPoint, x, y = stream.anchor:GetPoint()
    if point then
        local saved = savedStreams()
        local s = type(saved[stream.name]) == "table" and saved[stream.name] or {}
        s.point, s.relPoint, s.x, s.y = point, relPoint, x, y
        s.direction = stream.direction
        saved[stream.name] = s
    end
end

local function createStream(name, x, label)
    local anchor = CreateFrame("Frame", "ClearCombatText" .. label .. "Anchor", UIParent)
    local stream = { name = name, anchor = anchor, defaultX = x, direction = "up" }
    streams[name] = stream
    anchor:SetSize(160, 40)
    anchor:SetPoint("CENTER", UIParent, "CENTER", x, 120)
    anchor:SetMovable(true)
    anchor:EnableMouse(false)
    anchor:SetClampedToScreen(true)
    anchor:Hide()
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", anchor.StartMoving)
    anchor:SetScript("OnDragStop", function()
        anchor:StopMovingOrSizing()
        saveAnchor(stream)
    end)
    local texture = anchor:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(0, 0.8, 0.9, 0.25)
    local text = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetAllPoints()
    text:SetText("ClearCombatText: " .. label)
    text:SetJustifyH("CENTER")
end

createStream("incoming", -180, "Incoming")
createStream("gains", 180, "Gains")

local function restoreAnchor()
    local saved = savedStreams()
    for name, stream in pairs(streams) do
        local s = saved[name]
        -- Preserve the old shared anchor's placement as two initial positions.
        local old = ClearCombatTextDB.anchor
        if not validPosition(s) and validPosition(old) then
            -- Old boxes were 260px wide; the new 160px boxes need a 50px
            -- correction to preserve their centers at edge/corner attachments.
            local correction = old.point:find("LEFT", 1, true) and 50 or (old.point:find("RIGHT", 1, true) and -50 or 0)
            s = { point = old.point, relPoint = old.relPoint, x = old.x + stream.defaultX + correction, y = old.y }
            saved[name] = s
        end
        local anchor = stream.anchor
        anchor:ClearAllPoints()
        if validPosition(s) then
            anchor:SetPoint(s.point, UIParent, s.relPoint, s.x, s.y)
        else
            anchor:SetPoint("CENTER", UIParent, "CENTER", stream.defaultX, 120)
        end
        stream.direction = type(s) == "table" and DIRECTIONS[s.direction] and s.direction or "up"
    end
    ClearCombatTextDB.anchor = nil
end

-- font cache: captured once from a fresh font string BEFORE any SetText. A widget
-- that has displayed secret text hands marked values back from its getters
-- (live-proven: GetPoint returned <secret string> after SetText(secret)), so the
-- addon never reads back from a rendered widget — it reuses this clean cache.
local baseFont, baseFlags

local function acquire()
    local fs = table.remove(pool)
    if not fs then
        fs = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        fs:SetFontObject("GameFontNormalHuge")
        local f, _, fl = fs:GetFont()
        if f and not baseFont then baseFont, baseFlags = f, fl end
    end
    return fs
end

local function release(fs)
    fs:Hide()
    table.insert(pool, fs)
end

local LIFETIME = 1.9
local RISE = 110

render = function(now, mtype, text, opts)
    -- Secret events cannot consolidate. Bound burst allocation and per-frame work.
    if #active >= MAX_ACTIVE then return nil end
    opts = opts or TYPES[mtype] or DEFAULT
    local stream = streams[INCOMING[mtype] and "incoming" or "gains"]
    local fs = acquire()
    if not fs then return nil end -- guard: stub layer may fail under injection
    fs:SetText(text)
    fs:SetAlpha(1) -- pooled strings carry the tail of their last fade
    fs:SetTextColor(opts.color[1], opts.color[2], opts.color[3], opts.dim and 0.75 or 1)
    if baseFont then fs:SetFont(baseFont, opts.size, baseFlags) end
    -- our own clean numbers only: after SetText the widget may carry the secret
    -- marker, and its getters hand back marked values (GetPoint proved it live)
    local stagger = math.random(-45, 45)
    local spawnX = stagger
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", stream.anchor, "CENTER", spawnX, 0)
    fs:Show()
    local entry = { fs = fs, born = now, size = opts.size, fontSize = opts.size, crit = opts.crit, done = false, spawnX = spawnX, stream = stream }
    active[#active + 1] = entry
    updater:Show()
    return entry
end

updater:SetScript("OnUpdate", function(self, elapsed)
    local now = GetTime()
    for i = #active, 1, -1 do
        local a = active[i]
        local age = now - a.born
        if age >= LIFETIME then
            a.done = true
            release(a.fs)
            table.remove(active, i)
        else
            local k = age / LIFETIME
            local direction = DIRECTIONS[a.stream.direction]
            -- no GetPoint read-back: the widget may carry the secret marker and
            -- its getters return marked values, which SetPoint rejects. We own
            -- spawnX; the anchor frame never displayed a secret, so it is clean.
            a.fs:SetPoint("CENTER", a.stream.anchor, "CENTER", a.spawnX + k * RISE * direction[1], k * RISE * direction[2])
            a.fs:SetAlpha((1 - k) ^ 1.4)
            if a.crit and baseFont then
                local pop = 1 + 0.35 * math.max(0, 1 - age * 8)
                local size = math.floor(a.size * pop)
                if size ~= a.fontSize then
                    a.fs:SetFont(baseFont, size, baseFlags)
                    a.fontSize = size
                end
            end
        end
    end
    -- expired consolidation windows release their claim; the line itself fades
    -- on its own refreshed lifetime
    for mtype, p in pairs(pending) do
        if (now - p.t) > WINDOW then
            pending[mtype] = nil
        end
    end
    if #active == 0 then self:Hide() end
end)

-- ---------------------------------------------------------------------------
-- the event

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UNIT_EXITING_VEHICLE")
f:RegisterEvent("UNIT_ENTERED_VEHICLE")
f:RegisterEvent("UNIT_PET")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(self, event, unit, showVehicle)
    if event == "COMBAT_TEXT_UPDATE" then return end -- handled by the payload hook
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        if C_CombatText == nil then return end
        local mtype = event == "PLAYER_REGEN_DISABLED" and "ENTERING_COMBAT" or "LEAVING_COMBAT"
        render(GetTime(), mtype, TEXT_LABELS[mtype] or mtype)
        return
    end
    if event == "PLAYER_LOGIN" then
        restoreAnchor() -- position restores even on clients without C_CombatText
        if C_CombatText == nil then return end
        bindUnit("player")
        print("ClearCombatText loaded. |cff888888/cct test|r to preview, |cff888888/cct anchor|r to move.|r")
        -- warn once if Blizzard's own floating combat text is on (they will overlap)
        if GetCVarBool("enableFloatingCombatText") then
            print("|cffffd200ClearCombatText: Blizzard's floating combat text is ON. Turn it off in Interface > Combat to avoid double numbers.|r")
        end
        return
    end
    -- keep the stream bound to the player across loading screens, vehicles and pets
    if C_CombatText == nil then return end
    if event == "UNIT_ENTERED_VEHICLE" and unit == "player" then
        bindUnit(showVehicle and "vehicle" or "player")
        return
    elseif event == "UNIT_EXITING_VEHICLE" and unit == "player" then
        bindUnit("player")
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or unit == "player" then
        if UnitHasVehicleUI("player") then
            bindUnit("vehicle")
        else
            bindUnit("player")
        end
    end
end)

f:RegisterEvent("COMBAT_TEXT_UPDATE")
f:HookScript("OnEvent", function(self, event, mtype)
    if event ~= "COMBAT_TEXT_UPDATE" then return end
    local getCurrentEventInfo = C_CombatText and C_CombatText.GetCurrentEventInfo
    if type(getCurrentEventInfo) ~= "function" then return end
    if issecretvalue and issecretvalue(mtype) then return end
    if type(mtype) ~= "string" then return end
    local data, a2, a3 = getCurrentEventInfo()
    local opts = TYPES[mtype] or UNKNOWN
    if opts.text then
        local label = TEXT_LABELS[mtype] or mtype
        if data ~= nil then label = tostring(data) end
        render(GetTime(), mtype, label, opts)
        return
    end
    if MITIGATION[mtype] then
        if a2 ~= nil and data ~= nil then
            local style = opts
            if issecretvalue and not issecretvalue(a3) and a3 == true then style = TYPES.DAMAGE_CRIT end
            -- string.format accepts secrets and preserves their marker; only
            -- the public event label is concatenated, never a combat payload.
            local text = string.format("-%s (%s " .. MITIGATION[mtype] .. ")", tostring(data), tostring(a2))
            render(GetTime(), mtype, text, style)
        else
            render(GetTime(), mtype, TEXT_LABELS[mtype], opts)
        end
        return
    end
    local value = data
    if SECOND_AMOUNT[mtype] then value = a2 end
    if value == nil then return end
    if mtype == "HEAL_ABSORB" or mtype == "HEAL_CRIT_ABSORB" or mtype == "PERIODIC_HEAL_ABSORB" then
        if a3 ~= nil then
            render(GetTime(), mtype, string.format("+%s (%s absorbed)", tostring(value), tostring(a3)), opts)
            return
        end
    end
    local key
    local resource = mtype == "ENERGIZE" or mtype == "PERIODIC_ENERGIZE"
    if resource and issecretvalue and not issecretvalue(a2) and type(a2) == "string" and RESOURCE_TYPES[a2] then
        opts = RESOURCE_TYPES[a2]
        key = mtype .. ":" .. a2
    end
    local amount = cleanNum(value)
    if resource and not key then amount = nil end
    if amount then
        consolidate(GetTime(), mtype, amount, opts, key)
    else
        render(GetTime(), mtype, tostring(value), opts)
    end
end)

-- ---------------------------------------------------------------------------
-- slash commands

SLASH_CLEARCOMBATTEXT1 = "/cct"
SlashCmdList.CLEARCOMBATTEXT = function(msg)
    savedStreams()
    msg = strlower(strtrim(msg or ""))
    local command, target, direction = msg:match("^(%S+)%s*(%S*)%s*(%S*)$")
    if command == "anchor" and direction == "" and (target == "" or streams[target]) then
        local show = target ~= "" and not streams[target].anchor:IsShown()
        if target == "" then
            show = not (streams.incoming.anchor:IsShown() and streams.gains.anchor:IsShown())
        end
        for name, stream in pairs(streams) do
            if target == "" or target == name then
                local anchor = stream.anchor
                if not show then
                    anchor:StopMovingOrSizing()
                    anchor:Hide()
                    anchor:EnableMouse(false)
                    saveAnchor(stream)
                else
                    anchor:Show()
                    anchor:EnableMouse(true)
                end
            end
        end
        print("ClearCombatText: drag each box; repeat the anchor command to lock.")
    elseif command == "direction" and streams[target] and DIRECTIONS[direction] then
        local stream = streams[target]
        stream.direction = direction
        saveAnchor(stream)
        ClearCombatTextDB.streams[target].direction = direction
        print("ClearCombatText: " .. target .. " scrolls " .. direction .. ".")
    elseif msg == "reset" then
        ClearCombatTextDB.anchor = nil
        ClearCombatTextDB.streams = {}
        restoreAnchor()
        print("ClearCombatText: positions and directions reset.")
    elseif msg == "test" then
        local now = GetTime()
        render(now, "SPELL_DAMAGE_CRIT", "4,912")
        render(now, "HEAL_CRIT", "1,208")
        render(now, "SPELL_DAMAGE", "385 x6")
        render(now, "HEALTH_LOW", LOW_HEALTH or "Low health!")
        render(now, "AURA_START", "Clearcasting")
    elseif msg == "blizz" then
        -- toggle Blizzard's own floating combat text
        local on = GetCVarBool("enableFloatingCombatText")
        SetCVar("enableFloatingCombatText", not on)
        print("ClearCombatText: Blizzard floating combat text " .. (on and "OFF." or "ON."))
    else
        print("ClearCombatText: /cct test, /cct anchor [incoming|gains], /cct direction <incoming|gains> <up|down|left|right>, /cct reset, /cct blizz. Active: " .. #active)
    end
end
