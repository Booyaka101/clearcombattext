-- WoW client stubs for ClearCombatText: enough surface to execute the addon.
local OUT = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    OUT[#OUT + 1] = table.concat(parts, " ")
end

strlower = string.lower
strtrim = function(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end
MISS, DODGE, PARRY, EVADE, IMMUNE = "Miss", "Dodge", "Parry", "Evade", "Immune"
LOW_HEALTH, LOW_MANA = "Low health!", "Low mana!"
ENTERING_COMBAT, LEAVING_COMBAT = "Entering combat", "Leaving combat"
COMBAT_TEXT_BLOCK, COMBAT_TEXT_ABSORB, COMBAT_TEXT_RESIST = "Block", "Absorb", "Resist"
BreakUpLargeNumbers = function(n) return tostring(n) end
GetTime = function() return CLOCK end
CLOCK = 0
issecretvalue = function(value) return type(value) == "table" and value.secret == true end

-- combat text event pump
EVENTS = {}
C_CombatText = {
    activeUnit = nil,
    SetActiveUnit = function(unit) C_CombatText.activeUnit = unit; return true end,
    GetCurrentEventInfo = function()
        local e = EVENTS[#EVENTS]
        if not e then return nil end
        return e.data, e.a2, e.a3
    end,
}

local UNIT_FRAMES = {}
UnitHasVehicleUI = function() return VEHICLE_UI == true end

-- minimal frame/fontstring stubs that record what got shown
SHOWN = {}
FONTSTRINGS = {}
local Frame = {}
Frame.__index = Frame
function Frame:RegisterEvent(ev) self.events = self.events or {}; self.events[ev] = true end
function Frame:HookScript(name, fn) self.hooks = self.hooks or {}; self.hooks[name] = fn end
function Frame:SetScript(name, fn) self.scripts = self.scripts or {}; self.scripts[name] = fn end
function Frame:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = {...} end
function Frame:GetPoint()
    if self.secretText then error("getter on secret text widget") end
    local p = self.points and self.points[#self.points]
    return p and p[1], p and p[2], p and p[3], p and p[4], p and p[5]
end
function Frame:Show() self.shown = true end
function Frame:SetShown(show) if show then self:Show() else self:Hide() end end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown == true end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:SetWidth(width) self.width = width end
function Frame:SetText(text) self.text = text end
function Frame:GetText() return self.text or "" end
function Frame:SetChecked(checked) self.checked = checked end
function Frame:GetChecked() return self.checked end
function Frame:SetAutoFocus() end
function Frame:SetMaxLetters() end
function Frame:ClearFocus() end
function Frame:SetFrameStrata() end
function Frame:SetMinMaxValues(low, high) self.low, self.high = low, high end
function Frame:SetValueStep(step) self.step = step end
function Frame:SetObeyStepOnDrag() end
function Frame:SetValue(v)
    self.value = v
    if self.scripts and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
end
function Frame:SetShadowColor(...) self.shadowColor = {...} end
function Frame:SetShadowOffset(...) self.shadowOffset = {...} end
function Frame:EnableMouse(enabled) self.mouseEnabled = enabled end
function Frame:RegisterForDrag() end
function Frame:SetMovable() end
function Frame:SetClampedToScreen() end
function Frame:CreateTexture() return setmetatable({ points = {} }, Frame) end
function Frame:SetAllPoints() end
function Frame:SetColorTexture() end
function Frame:CreateFontString()
    local fs = setmetatable({ points = {} }, Frame)
    fs.SetText = function(self2, t)
        self2.text = t
        if t == "secret display" then self2.secretText = true end
    end
    fs.SetTextColor = function(self2, ...) self2.color = {...} end
    fs.SetFont = function(self2, f, size, flags)
        self2.font, self2.flags = f, flags
        self2.size = size
        self2.fontCalls = (self2.fontCalls or 0) + 1
    end
    fs.GetFont = function(self2)
        if self2.secretText then error("font getter on secret text widget") end
        return "GameFont.ttf", 16, ""
    end
    fs.SetFontObject = function() end
    fs.SetAlpha = function(self2, a) self2.alpha = a end
    fs.SetJustifyH = function() end
    fs.SetFormattedText = function(self2, format, ...)
        self2:SetText(string.format(format, ...))
    end
    fs.Show = function() fs.shown = true; SHOWN[#SHOWN + 1] = fs.text end
    FONTSTRINGS[#FONTSTRINGS + 1] = fs
    return fs
end
function Frame:ClearAllPoints() self.points = {} end
function Frame:StartMoving() end
function Frame:StopMovingOrSizing() end

local REAL_CREATE = CreateFrame
CREATE_CALLS = 0
FRAMES = {}
CreateFrame = function(kind, name, parent)
    CREATE_CALLS = CREATE_CALLS + 1
    local fr = setmetatable({ kind = kind, name = name }, Frame)
    FRAMES[#FRAMES + 1] = fr
    return fr
end

UIParent = CreateFrame("Frame", "UIParent")
math.random = function(a, b) return 0 end -- deterministic stagger

GetCVarBool = GetCVarBool or function() return false end
SetCVar = SetCVar or function() end

SlashCmdList = {}
UISpecialFrames = {}
