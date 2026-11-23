local _, ns = ...

-- What healers look at: your heals with your bonus healing in (each spell's tooltip, read with
-- HealData.lua's patterns and coefficients by FrogLib.SpellPower), what they cost, how fast and how
-- far your mana takes them, and your crit on heals. Healing talents count (Talents.lua): Gift of
-- Nature, Purification and Spiritual Healing on every heal, Healing Light and the like on theirs,
-- Genesis on healing over time, Twin Disciplines on instant heals; the game's tooltips leave talents
-- out. Crits aren't in the averages. The tooltips are read in English (HealData's patterns are).

local Healing = {}
ns.Healing = Healing

local issecret = FrogLib.issecret
local Known = ns.Known
local SpellPower = FrogLib.SpellPower

-- The school your heals are: Holy for priests and paladins, Nature for druids and shamans.
local SCHOOL = { PRIEST = 2, PALADIN = 2, DRUID = 4, SHAMAN = 4 }
local GCD = 1.5

local function Class() return select(2, UnitClass("player")) end

function Healing.Heals() return SCHOOL[Class()] ~= nil end

-- If heals can be read on this client (their tooltips are matched in English).
function Healing.Readable()
    local locale = GetLocale and GetLocale()
    return locale == nil or locale == "enUS" or locale == "enGB"
end

function Healing.Bonus()
    return Known(GetSpellBonusHealing())
end

-- Crit chance on heals, in percent: the heal school's spell crit plus talents for heals (Tidal Mastery,
-- Holy Specialization; Improved Regrowth for the heal named `name`).
function Healing.Crit(name)
    return Known(GetSpellCritChance(SCHOOL[Class()] or 2)) + ns.Talents.HealCrit(name)
end

-- Mana a second: resting (5 s after your last cast) and while casting, and the share kept.
function Healing.Regen()
    local resting, casting = GetManaRegen()
    resting, casting = Known(resting), Known(casting)
    return resting, casting, resting > 0 and casting / resting or 0
end

-- The share of Spirit's regen you keep while casting (Meditation and the like), from the game's own
-- split of it; 0 when it can't say.
function Healing.SpiritKept()
    if not GetManaRegenFromSpirit then return 0 end
    local resting, casting = GetManaRegenFromSpirit()
    if casting == nil then return 0 end -- a client that doesn't split it
    resting, casting = Known(resting), Known(casting)
    if resting <= 0 then return 0 end
    return math.max(0, math.min(1, casting / resting))
end

------------------------------------------------------------------------------
-- Your heals
------------------------------------------------------------------------------

-- The heals you know, by name: { name = { spell IDs } }, found once and again when your spells change.
local known
local parsed = {} -- [spell ID] = FrogLib.SpellPower.Parse's answer, with group and jumps (false: nothing to read)
local list, listKey -- the last List and what it was worked out from

local function KnownHeals()
    if known then return known end
    known = {}
    for spellID in pairs(ns.HEALS or {}) do
        if FrogLib.Util.Knows(spellID) and not (C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(spellID)) then
            local name = C_Spell.GetSpellName(spellID)
            if name and not issecret(name) then
                known[name] = known[name] or {}
                table.insert(known[name], spellID)
            end
        end
    end
    return known
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function()
    known, list = nil, nil
    wipe(parsed)
end)

local function ManaCost(spellID)
    for _, cost in ipairs(C_Spell.GetSpellPowerCost(spellID) or {}) do
        if cost.type == 0 then return cost.cost or 0 end
    end
    return 0
end

-- A spell's tooltip, read once (the costly part): FrogLib.SpellPower's answer with group (it heals
-- your party too) and jumps (it jumps on to others: Chain Heal).
local function Parsed(spellID)
    local entry = parsed[spellID]
    if entry ~= nil then return entry end
    entry = SpellPower.Parse(spellID, ns.HEALS[spellID])
    if entry == nil then return nil end
    if entry then
        local text = C_Spell.GetSpellDescription(spellID)
        text = type(text) == "string" and not issecret(text) and text or ""
        entry.group = text:find("their party") ~= nil or text:find("all party members") ~= nil
        entry.jumps = text:find("jumps") ~= nil
    end
    parsed[spellID] = entry
    return entry
end

-- One rank's numbers, or nil while its tooltip can't be read: { spellID, average, overTime, seconds,
-- cast, cost, perSecond, perMana, perBonus (healing each point of bonus healing adds), group, jumps }.
local function Rank(spellID, name, bonus)
    local entry = Parsed(spellID)
    if not entry then return nil end
    local info = C_Spell.GetSpellInfo(spellID)
    local cast = info and info.castTime and info.castTime / 1000
    local scale, periodic = ns.Talents.HealScale(cast == 0, name)
    local function Amount(healing)
        local healed, _, overTime = SpellPower.Sum(entry, healing, 0)
        return ((healed - overTime) + overTime * periodic) * scale, overTime * periodic * scale
    end
    local average, overTime = Amount(bonus)
    if average <= 0 then return nil end
    cast = cast or 0
    local cost = ManaCost(spellID)
    return {
        spellID = spellID, average = average, overTime = overTime, seconds = entry.seconds,
        cast = cast, cost = cost, perSecond = average / math.max(cast, GCD),
        perMana = cost > 0 and average / cost or nil, perBonus = Amount(1) - Amount(0),
        group = entry.group, jumps = entry.jumps,
    }
end

local function RankText(spellID)
    local text = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID)
    if type(text) ~= "string" or issecret(text) then return nil end
    return text ~= "" and text or nil
end

-- Your heals, best rank of each (the biggest), biggest first: each a Rank with name, icon, rank text,
-- casts (from full mana), dry (seconds of casting it back to back until you're out, nil if never)
-- and cheaper = { rank text, perMana, average } when a lower rank heals clearly more per mana. Worked
-- out again only when your spells, bonus healing, mana, regen or talents change.
function Healing.List()
    local bonus = Healing.Bonus()
    local maxMana = Known(UnitPowerMax("player", 0))
    local _, castingRegen = Healing.Regen()
    local key = table.concat({ bonus, maxMana, castingRegen, (ns.Talents.HealScale(false)) }, ":")
    if list and listKey == key then return list end
    local fresh = {}
    local complete = true
    for name, spellIDs in pairs(KnownHeals()) do
        local best, cheapest
        for _, spellID in ipairs(spellIDs) do
            local rank = Rank(spellID, name, bonus)
            if rank then
                if not best or rank.average > best.average then best = rank end
                if rank.perMana and (not cheapest or rank.perMana > cheapest.perMana) then cheapest = rank end
            elseif parsed[spellID] == nil then
                complete = false -- its tooltip hasn't loaded: read again next time
            end
        end
        if best then
            best.name = name
            best.icon = C_Spell.GetSpellTexture(best.spellID)
            best.rank = RankText(best.spellID)
            best.crit = Healing.Crit(name)
            if best.cost > 0 then
                best.casts = math.floor(maxMana / best.cost)
                local spend = best.cost / math.max(best.cast, GCD) - castingRegen
                best.dry = spend > 0 and maxMana / spend or nil
            end
            if cheapest and cheapest ~= best and best.perMana and cheapest.perMana > best.perMana * 1.1 then
                best.cheaper = { rank = RankText(cheapest.spellID) or "A lower rank", perMana = cheapest.perMana,
                    average = cheapest.average }
            end
            fresh[#fresh + 1] = best
        end
    end
    table.sort(fresh, function(first, second) return first.average > second.average end)
    list, listKey = fresh, complete and key or nil
    return fresh
end

-- Your main heal (the biggest you know), or nil.
function Healing.Main()
    return Healing.List()[1]
end

-- What a heal's crits add on average, in healing per cast, at `critPercent` crit (heals over time
-- don't crit).
function Healing.CritShare(heal, critPercent)
    return (heal.average - heal.overTime) * critPercent / 100 * ns.Talents.CritBonus()
end
