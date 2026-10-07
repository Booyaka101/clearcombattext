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

local ADDON = ...

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
    SPELL_SPLIT_DAMAG   = { color = { 1.00, 0.95, 0.55 }, size = 18 },
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
    SPELL_SPLIT_DAMAG = true, PERIODICAURA_DAMAGE = true, MISS = true, DODGE = true,
    PARRY = true, EVADE = true, IMMUNE = true, AURA_START_HARMFUL = true,
}

-- ---------------------------------------------------------------------------
-- consolidation: repeats of the same type merge inside the window
-- "12 × 340" instead of twelve 340s machine-gunning over each other.

local WINDOW = 0.45
local pending = {}

local function consolidate(now, mtype, amount)
    local p = pending[mtype]
    if p and (now - p.t) <= WINDOW and amount then
        p.n = p.n + 1
        p.sum = p.sum + (tonumber(amount) or 0)
        p.t = now
        return nil -- swallowed; the visible line refreshes when it flushes
    end
    if amount then
        pending[mtype] = { t = now, n = 1, sum = tonumber(amount) or 0 }
    end
    return amount
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

local function render(now, mtype, text, opts)
    opts = opts or TYPES[mtype] or { color = { 1, 1, 1 }, size = 18 }
    local incoming = INCOMING[mtype]
    local fs = acquire()
    fs:SetText(text)
    fs:SetTextColor(opts.color[1], opts.color[2], opts.color[3], opts.dim and 0.75 or 1)
    local profile = "GameFontNormalHuge"
    local font, _, flags = fs:GetFont()
    if font then fs:SetFont(font, opts.size, flags) end
    local x = incoming and -180 or 180
    local stagger = math.random(-45, 45)
    fs:SetPoint("CENTER", anchor, "CENTER", x + stagger, 0)
    fs:Show()
    active[#active + 1] = { fs = fs, born = now, size = opts.size, crit = opts.crit }
end

local updater = CreateFrame("Frame")
updater:SetScript("OnUpdate", function(self, elapsed)
    local now = GetTime()
    for i = #active, 1, -1 do
        local a = active[i]
        local age = now - a.born
        if age >= LIFETIME then
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
    -- flush consolidation windows
    for mtype, p in pairs(pending) do
        if (now - p.t) > WINDOW then
            local text
            if p.n > 1 then
                text = string.format("%s x%d", BreakUpLargeNumbers(math.floor(p.sum / p.n + 0.5)), p.n)
            else
                text = BreakUpLargeNumbers(p.sum)
            end
            render(now, mtype, text)
            pending[mtype] = nil
        end
    end
end)

-- ---------------------------------------------------------------------------
-- the event

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UNIT_EXITING_VEHICLE")
f:RegisterEvent("UNIT_PET")
f:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        if C_CombatText == nil then return end
        bindUnit("player")
        print("ClearCombatText loaded. |cff888888/cct test|r to preview, |cff888888/cct anchor|r to move.|r")
        return
    end
    -- keep the stream bound to the player across vehicle and pet changes
    if C_CombatText == nil then return end
    if unit == "player" then
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
        -- unknown type: still show the number, unstyled, rather than drop it
        if type(data) == "number" then
            consolidate(GetTime(), mtype, data)
        end
        return
    end
    if opts.text then
        local label = data or TEXT_LABELS[mtype] or mtype
        render(GetTime(), mtype, tostring(label), opts)
        return
    end
    local amount = tonumber(data)
    if amount then
        consolidate(GetTime(), mtype, amount)
    elseif a2 and tonumber(a2) then
        consolidate(GetTime(), mtype, tonumber(a2))
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
        else
            anchor:Show()
            anchor:EnableMouse(true)
            anchor:RegisterForDrag("LeftButton")
            anchor:SetScript("OnDragStart", anchor.StartMoving)
            anchor:SetScript("OnDragStop", anchor.StopMovingOrSizing)
            print("ClearCombatText: drag the box, then |cff888888/cct anchor|r to lock.")
        end
    elseif msg == "test" then
        local now = GetTime()
        render(now, "SPELL_DAMAGE_CRIT", "4,912")
        render(now, "HEAL_CRIT", "1,208")
        render(now, "SPELL_DAMAGE", "385 x6")
        render(now, "HEALTH_LOW", LOW_HEALTH or "Low health!")
        render(now, "AURA_START", "Clearcasting")
    else
        print("ClearCombatText: |cff888888/cct test|r preview, |cff888888/cct anchor|r move, active strings: " .. #active)
    end
end
