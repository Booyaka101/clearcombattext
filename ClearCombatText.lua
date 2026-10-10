-- ClearCombatText.lua — scrolling combat text that stays readable under the secret-value API.
--
-- The Midnight and Forever clients restrict the combat log, which is why the classic
-- battle text addons either died or misattribute damage to whoever happened to stand
-- nearby. Blizzard's answer is C_CombatText: you point it at one unit and it hands you
-- that unit's combat text events, already attributed. Nothing here reads the combat log
-- or works around a restriction; it renders what the sanctioned API provides, the way
-- Mik's Scrolling Battle Text used to make readable: separated streams, consolidated
-- repeats, crits you can actually see.
--
-- Every C_CombatText call is pcall-wrapped: the Forever beta moves, and a signature
-- change must degrade to silence, never to an error mid-fight.

-- ---------------------------------------------------------------------------
-- event info access

local function currentEvent()
    local ok, data, a2, a3 = pcall(C_CombatText.GetCurrentEventInfo)
    if ok then return data, a2, a3 end
    return nil
end

local function bindUnit(unit)
    local ok = pcall(C_CombatText.SetActiveUnit, unit)
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

-- ---------------------------------------------------------------------------
-- consolidation: the first hit renders immediately; repeats inside the window
-- update that same line in place ("340" grows into "1020 x3") and refresh its
-- lifetime, so a burst reads as one living number instead of a queue delay.
-- (defined after render, which it calls)

local WINDOW = 0.45
local pending
local render -- forward-declared: consolidate calls it, defined below

local function consolidate(now, mtype, amount)
    local p = pending[mtype]
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
        local entry = render(now, mtype, BreakUpLargeNumbers(amount))
        if entry and entry.fs then
            pending[mtype] = { t = now, n = 1, sum = amount, entry = entry }
        end
    end
end

-- ---------------------------------------------------------------------------
-- rendering: a pool of rising, fading font strings in two streams

local pool = {}
local active = {}
local poolSize = 0

local anchor = CreateFrame("Frame", "ClearCombatTextAnchor", UIParent)
anchor:SetSize(260, 40)
anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
anchor:SetMovable(true)
anchor:EnableMouse(false)
anchor:SetClampedToScreen(true)
anchor:Hide()

ClearCombatTextDB = ClearCombatTextDB or {}

local function saveAnchor()
    local point, rel, relPoint, x, y = anchor:GetPoint()
    if point then
        ClearCombatTextDB.anchor = { point = point, relPoint = relPoint, x = x, y = y }
    end
end

-- drag handling stays attached for the session; the anchor is merely hidden when
-- locked, so StopMovingOrSizing always fires and the position is always saved
anchor:RegisterForDrag("LeftButton")
anchor:SetScript("OnDragStart", anchor.StartMoving)
anchor:SetScript("OnDragStop", function()
    anchor.StopMovingOrSizing(anchor)
    saveAnchor()
end)

local function restoreAnchor()
    local s = ClearCombatTextDB and ClearCombatTextDB.anchor
    if s and s.point then
        anchor:ClearAllPoints()
        anchor:SetPoint(s.point, UIParent, s.relPoint, s.x, s.y)
    end
end

local anchorTex = anchor:CreateTexture(nil, "BACKGROUND")
anchorTex:SetAllPoints()
anchorTex:SetColorTexture(0, 0.8, 0.9, 0.25)

local anchorText = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
anchorText:SetAllPoints()
anchorText:SetText("ClearCombatText")
anchorText:SetJustifyH("CENTER")

local function acquire()
    local fs = table.remove(pool)
    if not fs then
        poolSize = poolSize + 1
        fs = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        fs:SetFontObject("GameFontNormalHuge")
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
    opts = opts or TYPES[mtype] or { color = { 1, 1, 1 }, size = 18 }
    local incoming = INCOMING[mtype]
    local fs = acquire()
    if not fs then return nil end -- guard: stub layer may fail under injection
    fs:SetText(text)
    fs:SetAlpha(1) -- pooled strings carry the tail of their last fade
    fs:SetTextColor(opts.color[1], opts.color[2], opts.color[3], opts.dim and 0.75 or 1)
    local font, _, flags = fs:GetFont()
    if font then fs:SetFont(font, opts.size, flags) end
    local x = incoming and -180 or 180
    local stagger = math.random(-45, 45)
    fs:SetPoint("CENTER", anchor, "CENTER", x + stagger, 0)
    fs:Show()
    local entry = { fs = fs, born = now, size = opts.size, crit = opts.crit, done = false }
    active[#active + 1] = entry
    return entry
end

pending = {}

local updater = CreateFrame("Frame")
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
            local y = k * RISE
            local point, rel, relPoint, x, y0 = a.fs:GetPoint()
            if point then a.fs:SetPoint(point, rel, relPoint, x, y) end
            a.fs:SetAlpha((1 - k) ^ 1.4)
            if a.crit then
                local pop = 1 + 0.35 * math.max(0, 1 - age * 8)
                local font, _, flags = a.fs:GetFont()
                if font then a.fs:SetFont(font, math.floor(a.size * pop), flags) end
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
end)

-- ---------------------------------------------------------------------------
-- the event

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UNIT_EXITING_VEHICLE")
f:RegisterEvent("UNIT_PET")
f:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        restoreAnchor() -- position restores even on clients without C_CombatText
        if C_CombatText == nil then return end
        bindUnit("player")
        print("ClearCombatText loaded. |cff888888/cct test|r to preview, |cff888888/cct anchor|r to move.|r")
        -- warn once if Blizzard's own floating combat text is on (they will overlap)
        if GetCVarBool("enableCombatText") then
            print("|cffffd200ClearCombatText: Blizzard's floating combat text is ON. Turn it off in Interface > Combat to avoid double numbers.|r")
        end
        return
    end
    -- keep the stream bound to the player across loading screens, vehicles and pets
    if C_CombatText == nil then return end
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
    if event ~= "COMBAT_TEXT_UPDATE" or C_CombatText == nil then return end
    local data, a2, a3 = currentEvent()
    local opts = TYPES[mtype]
    if opts == nil then
        -- unknown type: show it rather than drop it, styled as unknown
        if type(data) == "number" then
            consolidate(GetTime(), mtype, data)
        elseif type(data) == "string" and #data > 0 then
            render(GetTime(), mtype, data .. " (?)", { color = { 0.7, 0.7, 0.7 }, size = 14, dim = true })
        end
        return
    end
    if opts.text then
        local label = data or TEXT_LABELS[mtype] or mtype
        render(GetTime(), mtype, tostring(label), opts)
        return
    end
    -- the amount is usually in data; absorbs and partial resists carry it in a2/a3
    -- (Blizzard's own code reads arg3 for absorb trailers)
    local amount = tonumber(data) or tonumber(a2) or tonumber(a3)
    if amount then
        consolidate(GetTime(), mtype, amount)
    end
end)

-- ---------------------------------------------------------------------------
-- slash commands

SLASH_CLEARCOMBATTEXT1 = "/cct"
SlashCmdList.CLEARCOMBATTEXT = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "anchor" then
        if anchor:IsShown() then
            anchor:Hide()
            anchor:EnableMouse(false)
            saveAnchor()
        else
            anchor:Show()
            anchor:EnableMouse(true)
            print("ClearCombatText: drag the box, then |cff888888/cct anchor|r to lock.")
        end
    elseif msg == "reset" then
        ClearCombatTextDB.anchor = nil
        anchor:ClearAllPoints()
        anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        print("ClearCombatText: position reset.")
    elseif msg == "test" then
        local now = GetTime()
        render(now, "SPELL_DAMAGE_CRIT", "4,912")
        render(now, "HEAL_CRIT", "1,208")
        render(now, "SPELL_DAMAGE", "385 x6")
        render(now, "HEALTH_LOW", LOW_HEALTH or "Low health!")
        render(now, "AURA_START", "Clearcasting")
    elseif msg == "blizz" then
        -- toggle Blizzard's own floating combat text
        local on = GetCVarBool("enableCombatText")
        SetCVar("enableCombatText", not on)
        print("ClearCombatText: Blizzard floating combat text " .. (on and "OFF." or "ON."))
    else
        print("ClearCombatText: |cff888888/cct test|r preview, |cff888888/cct anchor|r move, |cff888888/cct blizz|r toggle Blizzard's, active: " .. #active)
    end
end
