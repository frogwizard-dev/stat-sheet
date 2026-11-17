local _, ns = ...

-- What enemies' swings have done to you: the game's combat feedback (UNIT_COMBAT) for your own
-- unit, physical only, the last few hundred this session. The Defense tab's "Measured in your
-- fights" reads it. Since Forever 1.60.1.70938 the game hides every hit's size, everywhere: a hit
-- still counts, only without its number.

local issecret = FrogLib.issecret
local KEEP = 300

-- The last KEEP swings, oldest overwritten first; `at` is where the newest went.
local Incoming = { list = {}, at = 0 }
ns.Incoming = Incoming

local AVOIDED = { DODGE = "dodge", PARRY = "parry", MISS = "miss", BLOCK = "block", DEFLECT = "miss" }

-- Bleeds tick as physical damage, which the combat feedback can't tell from a swing. While one is
-- on you nothing is recorded (hits and misses alike, so the shares stay fair). Known by name, read
-- from these spells so it works in any language: Rend, Deep Wound, Garrote, Rupture, Rake, Rip,
-- Pounce Bleed, and the creature bleeds that share those names.
local BLEED_SPELLS = { 772, 12721, 703, 1943, 1822, 1079, 9007 }
local bleedNames
local bleeding = false

local function CheckBleeds()
    if not bleedNames then
        bleedNames = {}
        for _, id in ipairs(BLEED_SPELLS) do
            local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
            if name then bleedNames[name] = true end
        end
    end
    local found = false
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if get then
        for i = 1, 40 do
            local ok, aura = pcall(get, "player", i, "HARMFUL")
            if not ok or not aura then break end
            local name = aura.name
            if not issecret(name) and bleedNames[name] then
                found = true
                break
            end
        end
    end
    bleeding = found
end

local function Add(swing)
    Incoming.at = Incoming.at % KEEP + 1
    Incoming.list[Incoming.at] = swing
end

local events = CreateFrame("Frame")
pcall(events.RegisterUnitEvent, events, "UNIT_COMBAT", "player")
pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
events:SetScript("OnEvent", function(_, event, _, action, flags, amount, school)
    if event == "UNIT_AURA" then
        pcall(CheckBleeds)
        return
    end
    if not UnitAffectingCombat("player") then return end -- not falls, lava and the like
    if bleeding then return end
    if issecret(action) or issecret(school) or issecret(flags) then return end
    if school ~= nil and school ~= 1 then return end -- physical only
    local avoided = AVOIDED[action]
    if avoided then
        Add({ kind = avoided })
    elseif action == "WOUND" then
        local known = not issecret(amount) and type(amount) == "number"
        if flags == "BLOCK" and not (known and amount > 0) then
            -- All of it blocked (the game shows "Block" for it too), not a hit.
            Add({ kind = "block" })
            return
        end
        if known and amount <= 0 then return end
        local kind = "hit"
        if flags == "CRITICAL" then kind = "crit" elseif flags == "CRUSHING" then kind = "crush" end
        Add({ kind = kind, amount = known and amount or nil, blocked = flags == "BLOCK_REDUCED" })
    end
end)

-- How many swings (count) and how many of each kind, the average plain hit and the largest hit,
-- and how many hits came without their size (unsized).
function Incoming:Summary()
    local summary = { count = 0, hit = 0, crit = 0, crush = 0, dodge = 0, parry = 0, miss = 0, block = 0,
        largest = 0, unsized = 0 }
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
        elseif swing.kind == "hit" or swing.kind == "crit" or swing.kind == "crush" then
            summary.unsized = summary.unsized + 1
        end
    end
    summary.averageHit = plainCount > 0 and plainTotal / plainCount or nil
    return summary
end

function Incoming:Clear()
    wipe(self.list)
    self.at = 0
end
