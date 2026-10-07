local _, ns = ...

-- What enemies' swings have really done to you: the game's combat feedback (UNIT_COMBAT) for your
-- own unit, physical only, the last few hundred this session. The Defense tab's "Measured in
-- your fights" reads it. Amounts the game hides (in some instances) are left out.

local issecret = FrogLib.issecret
local KEEP = 300

local Incoming = { list = {}, at = 0 }
ns.Incoming = Incoming

local AVOIDED = { DODGE = "dodge", PARRY = "parry", MISS = "miss", BLOCK = "block", DEFLECT = "miss" }

local function Add(e)
    Incoming.at = Incoming.at % KEEP + 1
    Incoming.list[Incoming.at] = e
end

local f = CreateFrame("Frame")
pcall(f.RegisterUnitEvent, f, "UNIT_COMBAT", "player")
f:SetScript("OnEvent", function(_, _, unit, action, flags, amount, school)
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

-- Counts and averages: n, and per kind; the average plain hit and the largest hit.
function Incoming:Summary()
    local s = { n = 0, hit = 0, crit = 0, crush = 0, dodge = 0, parry = 0, miss = 0, block = 0,
        plainSum = 0, plainN = 0, largest = 0 }
    for _, e in pairs(self.list) do
        s.n = s.n + 1
        s[e.kind] = s[e.kind] + 1
        if e.blocked then s.block = s.block + 1 end
        if e.amount then
            if e.kind == "hit" and not e.blocked then
                s.plainSum = s.plainSum + e.amount
                s.plainN = s.plainN + 1
            end
            s.largest = math.max(s.largest, e.amount)
        end
    end
    s.avgHit = s.plainN > 0 and s.plainSum / s.plainN or nil
    return s
end

function Incoming:Clear()
    wipe(self.list)
    self.at = 0
end
