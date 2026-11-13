local _, ns = ...

-- What enemies' swings have done to you: the game's combat feedback (UNIT_COMBAT) for your own
-- unit, physical only, the last few hundred this session. The Defense tab's "Measured in your
-- fights" reads it. Amounts the game hides (in some instances) are left out.

local issecret = FrogLib.issecret
local KEEP = 300

-- The last KEEP swings, oldest overwritten first; `at` is where the newest went.
local Incoming = { list = {}, at = 0 }
ns.Incoming = Incoming

local AVOIDED = { DODGE = "dodge", PARRY = "parry", MISS = "miss", BLOCK = "block", DEFLECT = "miss" }

local function Add(swing)
    Incoming.at = Incoming.at % KEEP + 1
    Incoming.list[Incoming.at] = swing
end

local events = CreateFrame("Frame")
pcall(events.RegisterUnitEvent, events, "UNIT_COMBAT", "player")
events:SetScript("OnEvent", function(_, _, _, action, flags, amount, school)
    if not UnitAffectingCombat("player") then return end -- not falls, lava and the like
    if issecret(action) or issecret(school) or issecret(flags) then return end
    if school ~= nil and school ~= 1 then return end -- physical only
    local avoided = AVOIDED[action]
    if avoided then
        Add({ kind = avoided })
    elseif action == "WOUND" then
        if issecret(amount) or type(amount) ~= "number" or amount <= 0 then return end
        local kind = "hit"
        if flags == "CRITICAL" then kind = "crit" elseif flags == "CRUSHING" then kind = "crush" end
        Add({ kind = kind, amount = amount, blocked = flags == "BLOCK_REDUCED" })
    end
end)

-- How many swings (count) and how many of each kind, the average plain hit and the largest hit.
function Incoming:Summary()
    local summary = { count = 0, hit = 0, crit = 0, crush = 0, dodge = 0, parry = 0, miss = 0, block = 0,
        largest = 0 }
    local plainTotal, plainCount = 0, 0
    for _, swing in pairs(self.list) do
        summary.count = summary.count + 1
        summary[swing.kind] = summary[swing.kind] + 1
        if swing.blocked then summary.block = summary.block + 1 end
        if swing.amount then
            if swing.kind == "hit" and not swing.blocked then
                plainTotal = plainTotal + swing.amount
                plainCount = plainCount + 1
            end
            summary.largest = math.max(summary.largest, swing.amount)
        end
    end
    summary.averageHit = plainCount > 0 and plainTotal / plainCount or nil
    return summary
end

function Incoming:Clear()
    wipe(self.list)
    self.at = 0
end
