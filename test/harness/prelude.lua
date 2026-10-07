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
BreakUpLargeNumbers = function(n) return tostring(n) end
GetTime = function() return CLOCK end
CLOCK = 0

-- combat text event pump
EVENTS = {}
C_CombatText = {
    activeUnit = nil,
    SetActiveUnit = function(_, unit) C_CombatText.activeUnit = unit; return true end,
    GetCurrentEventInfo = function()
        local e = EVENTS[#EVENTS]
        if not e then return nil end
        return e.data, e.a2, e.a3
    end,
}

local UNIT_FRAMES = {}
UnitHasVehicleUI = function() return false end

-- minimal frame/fontstring stubs that record what got shown
SHOWN = {}
local Frame = {}
Frame.__index = Frame
function Frame:RegisterEvent(ev) self.events = self.events or {}; self.events[ev] = true end
function Frame:HookScript(name, fn) self.hooks = self.hooks or {}; self.hooks[name] = fn end
function Frame:SetScript(name, fn) self.scripts = self.scripts or {}; self.scripts[name] = fn end
function Frame:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = {...} end
function Frame:GetPoint() local p = self.points and self.points[#self.points]; return p and p[1], p and p[2], p and p[3], p and p[4], p and p[5] end
function Frame:Show() SHOWN[#SHOWN + 1] = self.text or "frame" end
function Frame:Hide() end
function Frame:IsShown() return false end
function Frame:SetSize() end
function Frame:EnableMouse() end
function Frame:RegisterForDrag() end
function Frame:SetMovable() end
function Frame:SetClampedToScreen() end
function Frame:CreateTexture() return setmetatable({ points = {} }, Frame) end
function Frame:SetAllPoints() end
function Frame:SetColorTexture() end
function Frame:CreateFontString()
    local fs = setmetatable({ points = {} }, Frame)
    fs.SetText = function(self2, t) self2.text = t end
    fs.SetTextColor = function() end
    fs.SetFont = function(self2, f, size) self2.size = size end
    fs.GetFont = function() return "GameFont.ttf", 16, "" end
    fs.SetFontObject = function() end
    fs.SetAlpha = function(self2, a) self2.alpha = a end
    fs.SetJustifyH = function() end
    fs.Show = function() SHOWN[#SHOWN + 1] = fs.text end
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

SlashCmdList = {}
