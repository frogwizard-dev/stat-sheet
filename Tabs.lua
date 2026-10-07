local _, ns = ...

-- The tabs and what's on each: blocks the panel lays out top to bottom.
--   { kind = "tiles", tiles = { ... } }   big numbers in a row; each tile's get() returns the
--                                          number, false, and a small line under it
--   { kind = "section", section = ... }   a header and a grid of cells (Stats.lua)
--   { kind = "bars", ... }                 stacked bars with a legend (where swings go)
--   { kind = "worth" }                     what +10 of each stat gets you, melee or caster
--   { kind = "chips", ... }                 short labelled values that wrap
--   { kind = "changes", ... }               what changed since you logged in, one card each
--   { kind = "entries", ... }               icon rows with a number on the right (casts per spell)
--   { kind = "role" }                       the Melee / Caster switch
-- A tab's blocks can also be a function, for tabs that change with the switch.
-- Everything reads through ns.R (Stats.lua), so secret values in combat keep the last reading.

local R, S = ns.R, ns.S
local N, Num, Pct, Dec, Line = R.N, R.Num, R.Pct, R.Dec, R.Line

local CASTERS = { MAGE = true, PRIEST = true, WARLOCK = true }
local function IsCaster() return CASTERS[R.Class()] end

local function EHP()
    local hp, r = N(UnitHealthMax("player")), R.ArmorReduction(R.ArmorNow())
    return hp / (1 - r), hp, r
end

local function ManaRate()
    local measured = ns.Regen and ns.Regen:Rate("rest")
    if measured then return measured, true end
    return N((GetManaRegen())), false
end

local function Seconds(secs)
    if secs >= 120 then return string.format("%.1f min", secs / 60) end
    return string.format("%ds", secs + 0.5)
end

------------------------------------------------------------------------------
-- Tiles
------------------------------------------------------------------------------

-- Showing things as a caster: the Melee / Caster switch, for anyone with mana.
local function Caster() return ns.WorthRole() == "caster" and R.UsesMana() end

local damageTile = {
    caption = function() return Caster() and "SPELL POWER" or "REAL DPS" end, colorKey = "Attack",
    get = function()
        if Caster() then
            return "+" .. Num((R.BestSchool(GetSpellBonusDamage))), false,
                Pct((R.BestSchool(GetSpellCritChance))) .. " spell crit"
        end
        local paper = R.PaperDPS()
        return string.format("%.1f", paper * R.SwingTable(0).mult), false, string.format("%.1f on paper", paper)
    end,
    tip = function(tt)
        if Caster() then
            Line(tt, "Bonus damage and healing on your spells. Switch to Melee to see your real DPS.")
            return
        end
        Line(tt, "What your auto-attacks really do to an enemy of your level, after misses, dodges, "
            .. "glancing blows and crits. The Offense tab shows the split.")
    end,
}

local ehpTile = {
    caption = "EFFECTIVE HP", colorKey = "Defense",
    get = function()
        local ehp, hp, r = EHP()
        return Num(math.floor(ehp + 0.5)), false, string.format("%s HP · %.1f%% armor", Num(hp), r * 100)
    end,
    tip = function(tt)
        Line(tt, "The physical damage it takes to bring you down from full health, once armor has "
            .. "taken its share, against an enemy of your level.")
    end,
}

local powerTile = {
    caption = function()
        if R.UsesMana() then return "MANA" end
        return string.upper(select(2, R.DisplayPower()))
    end, colorKey = "Secondary Stats",
    get = function()
        if R.UsesMana() then
            local max = N(UnitPowerMax("player", 0))
            local rate = ManaRate()
            return Num(max), false, rate > 0 and ("full in " .. Seconds(max / rate)) or "no regen"
        end
        local pType = R.DisplayPower()
        local sub
        if GetPowerRegen then
            local regen = N((GetPowerRegen()))
            if regen > 0 then sub = Dec(regen) .. " per second" end
        end
        return Num(UnitPowerMax("player", pType)), false, sub
    end,
    tip = function(tt)
        if not R.UsesMana() then return end
        local _, measured = ManaRate()
        Line(tt, "Time to fill your mana from empty while not casting (without drinking)"
            .. (measured and ", from your measured regen." or "."))
    end,
}

------------------------------------------------------------------------------
-- What +10 of each gets you
------------------------------------------------------------------------------

-- What it takes to know: base values once, then each stat's gain worked out with the client's
-- own conversion functions where it has them.
local function StatValue(i)
    local _, stat = UnitStat("player", i)
    return N(stat)
end

local function Fraction(fn, i, stat)
    local v = R.Call(fn, i, stat)
    return v and v * 100 or 0
end

local function MeleeWorth()
    local rows = {}
    local paper = R.PaperDPS()
    local sw = R.SwingTable(0)
    local real = paper * sw.mult
    local _, offSpeed = UnitAttackSpeed("player")
    local hands = offSpeed and 1.5 or 1 -- an off hand gets half the attack power bonus
    local function dpsFromAP(ap) return ap / R.AP_PER_DPS * hands * sw.mult end

    local str = StatValue(1)
    local strAP = (R.StatAP(1, str + 10) or 0) - (R.StatAP(1, str) or 0)
    local strDPS = dpsFromAP(strAP)
    rows[#rows + 1] = { stat = "+10 Strength", headline = string.format("+%.1f DPS", strDPS), colorKey = "Attack",
        gain = strDPS / real, detail = string.format("+%d attack power · %d%% more damage", strAP, strDPS / real * 100 + 0.5) }

    local _, hp = EHP()
    local per = R.Call(UnitHPPerStamina, "player") or 10
    rows[#rows + 1] = { stat = "+10 Stamina", headline = string.format("+%d HP", per * 10), colorKey = "Defense",
        gain = per * 10 / hp, detail = string.format("%d%% more effective health", per * 10 / hp * 100 + 0.5) }

    local agi = StatValue(2)
    local crit = Fraction(GetCritChanceFromStat, 2, agi + 10) - Fraction(GetCritChanceFromStat, 2, agi)
    local agiAP = (R.StatAP(2, agi + 10) or 0) - (R.StatAP(2, agi) or 0)
    local agiDPS = paper * crit / 100 + dpsFromAP(agiAP)
    local dodge = (R.Call(GetDodgeChanceFromAttribute) or 0) * 100 / math.max(1, agi) * 10
    rows[#rows + 1] = { stat = "+10 Agility", headline = string.format("+%.2f DPS", agiDPS), colorKey = "Attack",
        gain = agiDPS / real, detail = string.format("+%.1f%% crit · +%.1f%% dodge · +20 armor%s", crit, dodge,
            agiAP > 0 and string.format(" · +%d AP", agiAP) or "") }

    if sw.miss > 0 then
        local hitDPS = paper * math.min(1, sw.miss) / 100
        rows[#rows + 1] = { stat = "+1% Hit", headline = string.format("+%.2f DPS", hitDPS), colorKey = "Attack",
            gain = hitDPS / real, detail = "1 fewer miss in every 100 swings" }
    end
    return rows
end

local function CasterWorth()
    local rows = {}
    local maxMana = N(UnitPowerMax("player", 0))
    local int = StatValue(4)
    local mana = (int + 10 <= (INTELLECT_BREAK or 20)) and 10 or 10 * (MANA_PER_INTELLECT or 15)
    local crit = Fraction(GetSpellCritChanceFromStat, 4, int + 10) - Fraction(GetSpellCritChanceFromStat, 4, int)
    rows[#rows + 1] = { stat = "+10 Intellect", headline = string.format("+%d mana", mana), colorKey = "Secondary Stats",
        gain = mana / maxMana, detail = string.format("%d%% more mana", mana / maxMana * 100 + 0.5)
            .. (crit >= 0.05 and string.format(" · +%.1f%% spell crit", crit) or "") }

    local spi = StatValue(5)
    local fromSpirit = R.Call(GetManaRegenFromSpirit)
    local regen = N((GetManaRegen()))
    if fromSpirit and spi > 0 and regen > 0 then
        local mp5 = fromSpirit * 5 / spi * 10
        local hp5 = (R.Call(GetHealthRegenFromSpirit) or 0) * 0.75 * 5 / spi * 10
        rows[#rows + 1] = { stat = "+10 Spirit", headline = string.format("+%s mp5", Dec(mp5)), colorKey = "Secondary Stats",
            gain = mp5 / (regen * 5), detail = string.format("%d%% faster mana regen · +%s health per 5s",
                mp5 / (regen * 5) * 100 + 0.5, Dec(hp5)) }
    end

    local _, hp = EHP()
    local per = R.Call(UnitHPPerStamina, "player") or 10
    rows[#rows + 1] = { stat = "+10 Stamina", headline = string.format("+%d HP", per * 10), colorKey = "Defense",
        gain = per * 10 / hp, detail = string.format("%d%% more effective health", per * 10 / hp * 100 + 0.5) }

    rows[#rows + 1] = { stat = "+10 Spell Power", headline = "+10 per spell", colorKey = "Secondary Stats",
        detail = "damage and healing, scaled by each spell's cast time" }
    return rows
end

-- Which list to show: the one picked on the card, else what suits the class and form (a druid in
-- caster form is a caster).
function ns.WorthRole()
    local role = ns.db.role
    if role == "melee" or role == "caster" then return role end
    if IsCaster() then return "caster" end
    local class = R.Class()
    if (class == "DRUID" and (GetShapeshiftForm() or 0) == 0) or class == "PRIEST" then return "caster" end
    return "melee"
end

function ns.Worth()
    if ns.WorthRole() == "caster" and R.UsesMana() then return CasterWorth() end
    return MeleeWorth()
end

------------------------------------------------------------------------------
-- Stacked bars
------------------------------------------------------------------------------

-- Segment colours, the same in both looks.
local C = {
    hit = { 0.42, 0.48, 0.55 }, crit = { 1, 0.78, 0.25 }, miss = { 0.9, 0.33, 0.29 },
    dodge = { 0.66, 0.70, 0.74 }, glance = { 0.62, 0.48, 0.28 },
    safe = { 0.31, 0.89, 0.42 }, yours = { 0.35, 0.70, 1 }, parry = { 0.10, 0.82, 0.63 },
    block = { 0.55, 0.62, 0.80 }, crush = { 0.9, 0.33, 0.29 },
    weapon = { 0.72, 0.40, 0.18 }, ap = { 1, 0.70, 0.42 },
}

local function Seg(pct, color, name)
    return { pct = pct, color = color, text = string.format("%s %s", name, Pct(pct)) }
end

local function SwingRow(over, label)
    local t = R.SwingTable(over)
    local paper = R.PaperDPS()
    local segs = {
        Seg(t.hit, C.hit, "Hit"), Seg(t.glance, C.glance, "Glancing"), Seg(t.crit, C.crit, "Crit"),
        Seg(t.miss, C.miss, "Miss"), Seg(t.dodge, C.dodge, "Dodge"),
    }
    local foot = t.glance > 0 and string.format("glancing blows deal %d%% less", t.glancePenalty + 0.5) or nil
    return { label = label, right = string.format("%.1f real DPS", paper * t.mult), segs = segs, foot = foot }
end

local function IncomingRow(over, label)
    local t = R.IncomingTable(over)
    local segs = {
        Seg(t.hit, C.hit, "Hit"), Seg(t.crush, C.crush, "Crushing"), Seg(t.crit, C.crit, "Crit"),
        Seg(t.miss, C.safe, "Miss"), Seg(t.dodge, C.yours, "Dodge"), Seg(t.parry, C.parry, "Parry"),
        Seg(t.block, C.block, "Block"),
    }
    return { label = label, right = "avoid " .. Pct(t.miss + t.dodge + t.parry), segs = segs,
        foot = t.crush > 0 and "crushing blows deal 150%" or nil }
end

local function BossLabel() return string.format("Raid boss (level %d)", UnitLevel("player") + 3) end
local function SameLabel() return string.format("Level %d enemy", UnitLevel("player")) end

------------------------------------------------------------------------------
-- Extra cells for the tabs
------------------------------------------------------------------------------

table.insert(S.spell.cells, 5, { label = "Resisted", get = function()
    return Pct(R.SpellMiss(0)) .. " · " .. Pct(R.SpellMiss(3)) .. " boss"
end, tip = function(tt)
    Line(tt, "Your spells' chance to be resisted outright by an enemy:")
    local level = UnitLevel("player")
    for over = 0, 3 do
        Line(tt, string.format("Level %d%s", level + over, over == 3 and " (raid boss)" or ""), Pct(R.SpellMiss(over)))
    end
end, wide = true })

table.insert(S.defense.cells, { label = "Health Regen", wide = true, get = function()
    local fromSpirit = R.Call(GetHealthRegenFromSpirit)
    if not fromSpirit then return false end
    local standing = fromSpirit * 0.75 * 5
    return string.format("%d per 5s", standing), false, string.format("%d sitting · out of combat", fromSpirit * 5)
end })

-- The most crit your white swings can use against a boss, hitting it from behind: what's left
-- once its misses, dodges and glancing blows have their share.
table.insert(S.caps.cells, { label = "Crit cap (boss)", wide = true, get = function()
    if Caster() then return false end
    local t = R.SwingTable(3)
    -- In the sheet's own terms: the boss also takes some crit off for weapon skill short of its
    -- defense, so the sheet's crit chance can go that much higher.
    local cap = 100 - t.miss - t.dodge - t.glance + t.critPenalty
    local crit = N(GetCritChance())
    local note = crit >= cap and "past it: more crit is wasted on white hits"
        or string.format("%s more crit before white hits stop gaining", Pct(cap - crit))
    return string.format("%s of %s", Pct(crit), Pct(cap)), false, note, math.min(1, crit / cap)
end, tip = function(tt)
    local t = R.SwingTable(3)
    Line(tt, "A boss's misses, dodges and glancing blows come first; crits only land on what's left. "
        .. "Past that, extra crit chance does nothing for auto-attacks (special attacks still crit).")
    Line(tt, " ")
    Line(tt, "Miss", Pct(t.miss))
    Line(tt, "Dodge", Pct(t.dodge))
    Line(tt, "Glancing", Pct(t.glance))
    if t.critPenalty > 0 then Line(tt, "Crit lost to weapon skill", Pct(t.critPenalty)) end
    Line(tt, "|cff8c8c8cFrom behind, so parries aren't counted. In the character sheet's own crit chance.|r")
end })

local armorByLevel = {
    key = "armorLevels", title = "Armor takes off", colorKey = "Defense",
    cells = {},
}
for over = 0, 3 do
    armorByLevel.cells[#armorByLevel.cells + 1] = {
        label = function() return string.format("Level %d%s", UnitLevel("player") + over, over == 3 and " (boss)" or "") end,
        wide = true,
        get = function()
            local r = R.ArmorReduction(R.ArmorNow(), over)
            return string.format("%.1f%%", r * 100), false, nil, r / 0.75
        end,
    }
end

------------------------------------------------------------------------------
-- Tanking a raid boss: crushing blows, crits, and what a block soaks
------------------------------------------------------------------------------

-- A shield on: anyone can block with one.
local function HasShield()
    local id = GetInventoryItemID("player", INVSLOT_OFFHAND or 17)
    if not id then return false end
    local classID, subclassID = select(6, C_Item.GetItemInfoInstant(id))
    local armor = (Enum.ItemClass and Enum.ItemClass.Armor) or 4
    local shield = (Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Shield) or 6
    return classID == armor and subclassID == shield
end

-- Bear form: druids tank there (no block, no parry).
local function InBear()
    if R.Class() ~= "DRUID" then return false end
    local pType = R.DisplayPower()
    return pType == 1
end

-- Who these lines are for: shield users and druids in bear form, and warriors and paladins.
local function Tanky()
    local class = R.Class()
    return HasShield() or InBear() or class == "WARRIOR" or class == "PALADIN"
end

-- A block ability that adds to your chance while it's up: warriors' Shield Block (75% for 5
-- seconds), paladins' Holy Shield (30% for 10 seconds). Only with a shield, once you know it.
local function BlockAbility()
    if not HasShield() then return nil end
    local class = R.Class()
    local known = IsPlayerSpell or IsSpellKnown
    local function knows(...)
        for _, id in ipairs({ ... }) do
            if known and known(id) then return true end
        end
        return false
    end
    if class == "WARRIOR" and knows(2565) then return "Shield Block", 75 end
    if class == "PALADIN" and knows(20925, 20927, 20928) then return "Holy Shield", 30 end
    return nil
end

-- An enemy's swing goes down the table in order: miss, dodge, parry, block, crit, crushing blow,
-- then a plain hit with whatever's left. Crushing blows only fall off the end once everything
-- before them fills all 100%: how far short that is.
local function CrushShort(t)
    return t.crush + t.hit
end

local tanking = {
    key = "tanking", title = "Tanking a raid boss", colorKey = "Defense",
    show = Tanky,
    cells = {
        { label = "Crushing blows", wide = true, get = function()
            if not Tanky() then return false end
            local t = R.IncomingTable(3)
            if InBear() then
                return Pct(t.crush), false, "bears can't block or parry, so these can't be pushed off; armor and health instead"
            end
            local short = CrushShort(t)
            if short <= 0 then
                return "None", false, "miss, dodge, parry and block fill the table: a boss can't crush you", 1
            end
            local name, bonus = BlockAbility()
            local note
            if name and bonus >= short then
                note = string.format("%s short, covered while %s is up", Pct(short), name)
            elseif name then
                note = string.format("%s short; %s covers %s of it", Pct(short), name, Pct(bonus))
            else
                note = string.format("%s more miss, dodge, parry or block pushes them off", Pct(short))
            end
            return Pct(t.crush) .. " of swings", false, note, math.max(0, 1 - short / 100)
        end, tip = function(tt)
            local t = R.IncomingTable(3)
            Line(tt, "A boss three levels up swings at you down this table, in order:")
            Line(tt, "Miss", Pct(t.miss))
            Line(tt, "Dodge", Pct(t.dodge))
            Line(tt, "Parry", Pct(t.parry))
            Line(tt, "Block", Pct(t.block))
            Line(tt, "Crit", Pct(t.crit))
            Line(tt, "Crushing blow (150% damage)", Pct(t.crush))
            Line(tt, "Plain hit", Pct(t.hit))
            Line(tt, " ")
            Line(tt, "|cff8c8c8cOnce everything above a crushing blow adds up to 100%, there's no room left "
                .. "for one. Defense past your cap doesn't lower the crushing chance itself, but its extra "
                .. "miss and dodge push it off.|r")
        end },
        { label = "Crits from a boss", wide = true, get = function()
            if not Tanky() then return false end
            local cur = R.DefenseSkill()
            if not cur then return false end
            local level = UnitLevel("player")
            -- Each point of defense takes 0.04% off: 5% plus the boss's skill over your defense.
            local need = (level + 3) * R.SKILL_PER_LEVEL + 125
            local t = R.IncomingTable(3)
            if cur >= need then return "None", false, "enough defense that a boss can't crit you", 1 end
            return Pct(t.crit), false, string.format("%d defense stops them (you have %d: %d more)",
                need, cur, need - cur), cur / need
        end, tip = function(tt)
            local level = UnitLevel("player")
            Line(tt, "A boss three levels up crits for double damage. Each point of defense takes 0.04% off "
                .. "its crit chance (5%, plus 0.04% per point of its weapon skill over your defense).")
            Line(tt, " ")
            Line(tt, "Defense to be crit by nothing:")
            for over = 0, 3 do
                Line(tt, string.format("Level %d%s", level + over, over == 3 and " (raid boss)" or ""),
                    tostring((level + over) * R.SKILL_PER_LEVEL + 125))
            end
            Line(tt, "|cff8c8c8cA long way off at most levels: a goal for gear later on.|r")
        end },
        { label = "Block value", wide = true, get = function()
            local chance = N(GetBlockChance())
            if chance <= 0 or not GetShieldBlock then return false end
            local value = N(GetShieldBlock())
            return Num(value), false, string.format("each block takes %s off the hit · %s of swings", Num(value), Pct(chance))
        end, tip = function(tt)
            Line(tt, "How much damage a blocked swing loses: your shield's block value plus what your "
                .. "strength adds. A block that soaks the whole hit leaves nothing.")
            local name, bonus = BlockAbility()
            if name then
                Line(tt, " ")
                Line(tt, string.format("%s adds %d%% to your block chance while it's up.", name, bonus))
            end
        end },
    },
}

------------------------------------------------------------------------------
-- Rage: what swings and hits taken give, by Classic's formula
------------------------------------------------------------------------------

-- Damage that makes one rage at your level (Classic's rage conversion).
local function RageConversion()
    local level = UnitLevel("player")
    return 0.0091107836 * level * level + 3.225598133 * level + 4.2652911
end

local function UsesRage() return R.DisplayPower() == 1 end

local rage = {
    key = "rage", title = "Rage", colorKey = "Attack",
    show = UsesRage,
    cells = {
        { label = "Per hit you land", wide = true, get = function()
            if not UsesRage() then return false end
            local min, max = UnitDamage("player")
            local avg = (N(min) + N(max)) / 2
            local c = RageConversion()
            local per = 7.5 * avg / c
            local speed = N((UnitAttackSpeed("player")))
            local t = R.SwingTable(0)
            -- Misses and dodges give none; crits twice the damage, glancing blows less.
            local perMinute = per * t.mult * 60 / speed
            return string.format("%.1f rage", per), false,
                string.format("crits %.1f · about %d a minute from your swings", per * 2, perMinute + 0.5)
        end, tip = function(tt)
            Line(tt, "Rage from your main hand's white hits against an enemy of your level: 7.5 x the "
                .. "damage, divided by your level's rage conversion. Misses and dodges give none.")
            Line(tt, " ")
            Line(tt, "|cff8c8c8cClassic's formula: an estimate if Forever's differs. Abilities that deal damage "
                .. "don't make rage; white hits do.|r")
        end },
        { label = "Per 100 damage taken", wide = true, get = function()
            if not UsesRage() then return false end
            local per = 2.5 * 100 / RageConversion()
            return string.format("%.1f rage", per), false, "not counting what's blocked or absorbed"
        end, tip = function(tt)
            Line(tt, "Rage from damage you take: 2.5 x the damage, divided by your level's rage conversion. "
                .. "Blocked and absorbed damage doesn't count.")
        end },
    },
}

------------------------------------------------------------------------------
-- Ammo and weapon buffs (poisons, imbues, oils and stones)
------------------------------------------------------------------------------

local AMMO_SLOT = INVSLOT_AMMO or 0

local function Minutes(ms)
    local secs = ms / 1000
    if secs >= 60 then return string.format("%d min", secs / 60 + 0.5) end
    return string.format("%ds", secs + 0.5)
end

local supplies = {
    key = "supplies", title = "Ammo & weapon buffs", colorKey = "Gear",
    cells = {
        { label = "Ammo", wide = true, get = function()
            local count = GetInventoryItemCount("player", AMMO_SLOT)
            count = count and N(count) or 0
            local hunter = R.Class() == "HUNTER"
            if count <= 0 then
                if hunter then return "|cffff4040None|r", false, "your ranged weapon has nothing to shoot" end
                return false
            end
            local speed = N((UnitRangedDamage("player")))
            local note
            if speed and speed > 0 then
                note = string.format("about %d minutes of shooting", count * speed / 60 + 0.5)
            end
            local text = Num(count)
            if hunter and count < 200 then text = "|cffffd040" .. text .. "|r" end
            return text, false, note
        end, tip = function(tt)
            Line(tt, "The arrows or bullets in your ammo slot, and how long they last at your ranged speed "
                .. "if every shot is an auto shot.")
        end },
        { label = "Main hand buff", wide = true, get = function()
            local has, ms, charges = GetWeaponEnchantInfo()
            if not has then return false end
            local text = Minutes(N(ms))
            if N(ms) < 300000 then text = "|cffffd040" .. text .. "|r" end
            return text, false, (charges and N(charges) > 0) and string.format("%d charges left", charges) or nil
        end, tip = function(tt)
            Line(tt, "What's on your main-hand weapon (a poison, a shaman's imbue, a sharpening stone or oil): "
                .. "time left. Yellow under five minutes.")
        end },
        { label = "Off hand buff", wide = true, get = function()
            local _, _, _, _, has, ms, charges = GetWeaponEnchantInfo()
            if not has then return false end
            local text = Minutes(N(ms))
            if N(ms) < 300000 then text = "|cffffd040" .. text .. "|r" end
            return text, false, (charges and N(charges) > 0) and string.format("%d charges left", charges) or nil
        end },
    },
}

------------------------------------------------------------------------------
-- Threat: your multiplier from stance or form, talents and Salvation
------------------------------------------------------------------------------

-- Any of these spells known (a talent's ranks, or a spell's).
local function KnowsRank(ids)
    local known = IsPlayerSpell or IsSpellKnown
    if not known then return 0 end
    local best = 0
    for rank, id in ipairs(ids) do
        if known(id) then best = rank end
    end
    return best
end

-- The active stance or form's spell.
local function FormSpell()
    local i = GetShapeshiftForm and GetShapeshiftForm() or 0
    if i == 0 or not GetShapeshiftFormInfo then return nil end
    local _, active, _, spellID = GetShapeshiftFormInfo(i)
    return spellID
end

local function HasBuff(...)
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not get then return false end
    for _, id in ipairs({ ... }) do
        local ok, aura = pcall(get, id)
        if ok and aura ~= nil and not FrogLib.issecret(aura) then return true end
    end
    return false
end

local WARRIOR_STANCES = { [71] = { 1.3, "Defensive Stance" }, [2457] = { 0.8, "Battle Stance" }, [2458] = { 0.8, "Berserker Stance" } }
local BEAR = { [5487] = true, [9634] = true }
local DEFIANCE = { 12303, 12788, 12789, 12791, 12792 }
local FERAL_INSTINCT = { 16947, 16948, 16949, 16950, 16951 }
local IMPROVED_FURY = { 20468, 20469, 20470 }

-- Your threat multiplier on what you do, and the parts it's made of ({ label, factor }).
local function Threat()
    local class, parts, mult = R.Class(), {}, 1
    local function add(label, factor)
        parts[#parts + 1] = { label, factor }
        mult = mult * factor
    end
    if class == "WARRIOR" then
        local stance = WARRIOR_STANCES[FormSpell() or 0]
        if stance then add(stance[2], stance[1]) end
        local rank = KnowsRank(DEFIANCE)
        if rank > 0 and stance and stance[1] > 1 then add("Defiance", 1 + 0.03 * rank) end
    elseif class == "DRUID" then
        if BEAR[FormSpell() or 0] then
            add("Bear Form", 1.3)
            local rank = KnowsRank(FERAL_INSTINCT)
            if rank > 0 then add("Feral Instinct", 1 + 0.03 * rank) end
        end
    elseif class == "ROGUE" then
        add("Rogues", 0.71)
    elseif class == "PALADIN" then
        if HasBuff(25780) then
            local rank = KnowsRank(IMPROVED_FURY)
            -- Improved Righteous Fury adds a sixth more of the bonus per rank (x1.7, x1.8, x1.9).
            add("Righteous Fury (holy spells)", 1 + 0.6 * (1 + rank / 6))
        end
    end
    if HasBuff(1038, 25895) then add("Blessing of Salvation", 0.7) end
    return mult, parts
end

local function ThreatCell()
    return { label = "Threat", wide = true, get = function()
        local mult, parts = Threat()
        if #parts == 0 then return false end
        local names = {}
        for _, p in ipairs(parts) do names[#names + 1] = p[1] end
        return string.format("x%.2f", mult), false, table.concat(names, ", ")
    end, tip = function(tt)
        local mult, parts = Threat()
        Line(tt, "How much threat what you do makes, against the same damage or healing with nothing changing it:")
        for _, p in ipairs(parts) do Line(tt, p[1], string.format("x%.2f", p[2])) end
        Line(tt, "Together", string.format("x%.2f", mult))
        Line(tt, " ")
        Line(tt, "|cff8c8c8cClassic's numbers: abilities with extra threat of their own (Sunder Armor, "
            .. "Revenge) are multiplied too.|r")
    end }
end

table.insert(tanking.cells, 1, ThreatCell())
-- Everyone else sees it with the general stats when something's changing it (Salvation, rogues).
local otherThreat = ThreatCell()
local tankGet = otherThreat.get
otherThreat.get = function()
    if Tanky() then return false end
    return tankGet()
end
table.insert(S.general.cells, otherThreat)

------------------------------------------------------------------------------
-- Measured in your fights (Incoming.lua)
------------------------------------------------------------------------------

local measured = {
    key = "measured", title = "Measured in your fights", colorKey = "Defense",
    cells = {
        { label = "Swings at you", wide = true, get = function()
            local s = ns.Incoming:Summary()
            if s.n < 10 then return false end
            return Num(s.n), false, "this session, physical only (the last 300)"
        end, tip = function(tt)
            Line(tt, "What really happened when enemies swung at you, from the game's own combat feedback, "
                .. "rather than worked out. Abilities that deal physical damage count too.")
        end },
        { label = "Avoided", get = function()
            local s = ns.Incoming:Summary()
            if s.n < 10 then return false end
            return Pct((s.dodge + s.parry + s.miss) / s.n * 100)
        end, tip = function(tt)
            local s = ns.Incoming:Summary()
            Line(tt, "Dodged", Pct(s.dodge / math.max(1, s.n) * 100))
            Line(tt, "Parried", Pct(s.parry / math.max(1, s.n) * 100))
            Line(tt, "Missed you", Pct(s.miss / math.max(1, s.n) * 100))
        end },
        { label = "Blocked", get = function()
            local s = ns.Incoming:Summary()
            if s.n < 10 or s.block == 0 then return false end
            return Pct(s.block / s.n * 100)
        end },
        { label = "Crits taken", get = function()
            local s = ns.Incoming:Summary()
            if s.n < 10 then return false end
            return Pct(s.crit / s.n * 100), s.crit == 0
        end },
        { label = "Crushing", get = function()
            local s = ns.Incoming:Summary()
            if s.n < 10 then return false end
            return Pct(s.crush / s.n * 100), s.crush == 0
        end },
        { label = "Average hit", wide = true, get = function()
            local s = ns.Incoming:Summary()
            if not s.avgHit then return false end
            return Num(math.floor(s.avgHit + 0.5)), false, string.format("largest %s", Num(s.largest))
        end, tip = function(tt)
            Line(tt, "The average plain hit you took (not crits, crushing blows or blocked ones), after "
                .. "your armor.")
        end },
    },
}

------------------------------------------------------------------------------
-- Resistances against a boss, school by school
------------------------------------------------------------------------------

local SCHOOL_COLORS = { { 2, "Fire", "ff8040" }, { 3, "Nat", "4cff4c" }, { 4, "Frost", "80d0ff" },
    { 5, "Shadow", "b080ff" }, { 6, "Arcane", "ffffff" } }

-- The average share of a spell resisted, at `res` resistance against a caster `level`.
local function AvgResist(res, level)
    return math.max(0, math.min(0.75, 0.75 * res / (5 * level)))
end

table.insert(S.defense.cells, { label = "Resisted (boss)", wide = true, get = function()
    local level, parts, any = UnitLevel("player") + 3, {}, false
    for _, sc in ipairs(SCHOOL_COLORS) do
        local _, total = UnitResistance("player", sc[1])
        local avg = AvgResist(N(total), level)
        if avg > 0 then any = true end
        parts[#parts + 1] = string.format("|cff%s%s|r %d%%", sc[3], sc[2], avg * 100 + 0.5)
    end
    return table.concat(parts, "  "), not any
end, tip = function(tt)
    local level = UnitLevel("player")
    Line(tt, "On average, how much of a spell you resist, school by school:")
    for _, sc in ipairs(SCHOOL_COLORS) do
        local _, total = UnitResistance("player", sc[1])
        total = N(total)
        Line(tt, string.format("|cff%s%s|r (%d)", sc[3], sc[2], total),
            string.format("%d%% · boss %d%%", AvgResist(total, level) * 100 + 0.5, AvgResist(total, level + 3) * 100 + 0.5))
    end
    Line(tt, "|cff8c8c8c75% at most. A spell is resisted in quarters (0, 25, 50, 75 or 100%), averaging out to this.|r")
end })

------------------------------------------------------------------------------
-- Dual wield: the lower hit target special attacks need
------------------------------------------------------------------------------

for _, cell in ipairs(S.caps.cells) do
    if cell.label == "Hit Chance" then
        local get = cell.get
        cell.get = function()
            local text, zero, note, bar = get()
            local _, offSpeed = UnitAttackSpeed("player")
            if offSpeed then
                note = string.format("white hits, dual wielding; special attacks need %s", Pct(R.HitNeeded(0) - 19))
            end
            return text, zero, note, bar
        end
    end
end

------------------------------------------------------------------------------
-- Your pet (hunters, warlocks)
------------------------------------------------------------------------------

local function HasPet() return UnitExists("pet") and true or false end

local HAPPINESS = { "|cffff4040Unhappy|r", "|cffffd040Content|r", "|cff40ff40Happy|r" }

local pet = {
    key = "pet", title = "Pet", colorKey = "Attack",
    show = HasPet,
    cells = {
        { label = function() return UnitName("pet") or "Pet" end, wide = true, get = function()
            if not HasPet() then return false end
            return Num(UnitHealthMax("pet")) .. " HP", false, string.format("level %d", N(UnitLevel("pet")))
        end },
        { label = "Happiness", wide = true, get = function()
            if not (HasPet() and GetPetHappiness) then return false end
            local happiness, damage = GetPetHappiness()
            if not happiness then return false end
            return HAPPINESS[happiness] or tostring(happiness), false,
                damage and string.format("deals %d%% damage", damage) or nil
        end, tip = function(tt)
            Line(tt, "A happy pet deals 125% damage, a content one 100% and an unhappy one 75%; unhappy for too "
                .. "long, it runs away. Feeding it food it likes keeps it happy.")
            if GetPetLoyalty then
                local ok, loyalty = pcall(GetPetLoyalty)
                if ok and loyalty then Line(tt, " ") Line(tt, "Loyalty", loyalty) end
            end
            if GetPetTrainingPoints then
                local ok, total, spent = pcall(GetPetTrainingPoints)
                if ok and total then Line(tt, "Training points", string.format("%d free of %d", total - (spent or 0), total)) end
            end
        end },
        { label = "Damage", get = function()
            if not HasPet() then return false end
            local min, max = UnitDamage("pet")
            local speed = N((UnitAttackSpeed("pet")))
            return string.format("%.1f DPS", (N(min) + N(max)) / 2 / speed)
        end, tip = function(tt)
            local min, max = UnitDamage("pet")
            Line(tt, "Hits", string.format("%d-%d", N(min), N(max)))
            Line(tt, "Speed", string.format("%.2fs", N((UnitAttackSpeed("pet")))))
        end },
        { label = "Attack Power", get = function()
            if not HasPet() then return false end
            local base, pos, neg = UnitAttackPower("pet")
            return Num(N(base) + N(pos) + N(neg))
        end },
        { label = "Armor", get = function()
            if not HasPet() then return false end
            local _, effective = UnitArmor("pet")
            return Num(N(effective))
        end },
        { label = "Experience", get = function()
            if not (HasPet() and GetPetExperience) then return false end
            local cur, max = GetPetExperience()
            if not (cur and max and max > 0) then return false end
            return string.format("%d%%", cur / max * 100)
        end },
        { label = "Resist", wide = true, get = function()
            if not HasPet() then return false end
            local parts, any = {}, false
            for _, sc in ipairs(SCHOOL_COLORS) do
                local _, total = UnitResistance("pet", sc[1])
                total = N(total)
                if total ~= 0 then any = true end
                parts[#parts + 1] = string.format("|cff%s%s|r %d", sc[3], sc[2], total)
            end
            return table.concat(parts, "  "), not any
        end },
    },
}

------------------------------------------------------------------------------
-- Ready to go: missing buffs and bag space
------------------------------------------------------------------------------

-- Buffs your group can give you, by the class that gives them: { spell IDs (any of them), name,
-- whether it's only worth it with mana }.
local GROUP_BUFFS = {
    PRIEST = { { 1243, 21562 }, "Fortitude" },
    DRUID = { { 1126, 21849 }, "Mark of the Wild" },
    MAGE = { { 1459, 23028 }, "Arcane Intellect", true },
    PALADIN = { { 19740, 19742, 20217, 1038, 19977, 20911, 25782, 25894, 25898, 25895, 25890, 25899 }, "a Blessing" },
}
-- Your own: { spells to know it by (rank 1s), spell IDs it shows as, name }.
local OWN_BUFFS = {
    WARRIOR = { { 6673 }, { 6673 }, "Battle Shout" },
    MAGE = { { 168 }, { 168, 7302, 6117 }, "an armor (Frost, Ice or Mage)" },
    WARLOCK = { { 687 }, { 687, 706 }, "Demon Skin or Demon Armor" },
    PRIEST = { { 588 }, { 588 }, "Inner Fire" },
    HUNTER = { { 13163, 13165 }, { 13165, 13163, 5118, 13159, 20043 }, "an aspect" },
}

-- Buffs are known by name, so any rank counts.
local function HasBuffNamed(ids)
    local byName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    for _, id in ipairs(ids) do
        local name = C_Spell.GetSpellName(id)
        if name and byName then
            local aura = byName("player", name, "HELPFUL")
            if FrogLib.issecret(aura) then error("unreadable", 0) end
            if aura then return true end
        elseif HasBuff(id) then
            return true
        end
    end
    return false
end

local function GroupClasses()
    local classes = { [R.Class()] = true }
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, n do
        local _, class = UnitClass(prefix .. i)
        if class and not FrogLib.issecret(class) then classes[class] = true end
    end
    return classes
end

local function MissingBuffs()
    local missing = {}
    for class in pairs(GroupClasses()) do
        local b = GROUP_BUFFS[class]
        if b and not (b[3] and not R.UsesMana()) and not HasBuffNamed(b[1]) then missing[#missing + 1] = b[2] end
    end
    local own = OWN_BUFFS[R.Class()]
    if own and KnowsRank(own[1]) > 0 and not HasBuffNamed(own[2]) then missing[#missing + 1] = own[3] end
    table.sort(missing)
    return missing
end

local function BagSpace()
    local free, total = 0, 0
    local C = C_Container
    for bag = 0, 4 do
        local slots = C and C.GetContainerNumSlots and C.GetContainerNumSlots(bag) or 0
        total = total + slots
        if slots > 0 then free = free + (C.GetContainerNumFreeSlots(bag) or 0) end
    end
    return free, total
end

local ready = {
    key = "ready", title = "Ready to go", colorKey = "Insights",
    cells = {
        { label = "Missing buffs", wide = true, get = function()
            if InCombatLockdown() then error("unreadable", 0) end
            local missing = MissingBuffs()
            if #missing == 0 then return "None", false, "everything your group can give you" end
            return "|cffffd040" .. #missing .. "|r", false, table.concat(missing, ", ")
        end, tip = function(tt)
            Line(tt, "Buffs the classes in your group (you included) can give, that you haven't got, and "
                .. "your own class's that you know but haven't put up. Checked out of combat.")
        end },
        { label = "Bag space", wide = true, get = function()
            local free, total = BagSpace()
            if total == 0 then return false end
            local text = string.format("%d free", free)
            if free == 0 then text = "|cffff4040Full|r" elseif free <= 4 then text = "|cffffd040" .. text .. "|r" end
            return text, false, string.format("of %d slots", total), 1 - free / total
        end },
    },
}

------------------------------------------------------------------------------
-- Enchants and professions
------------------------------------------------------------------------------

-- Slots that can carry an enchant: the off hand only for a shield or weapon, ranged only for a
-- bow, gun or crossbow (a scope).
local ENCHANT_SLOTS = {
    { 1, "Head" }, { 3, "Shoulders" }, { 15, "Back" }, { 5, "Chest" }, { 9, "Wrist" }, { 10, "Hands" },
    { 7, "Legs" }, { 8, "Feet" }, { 16, "Main hand" }, { 17, "Off hand" }, { 18, "Ranged" },
}

local function Enchantable(slot, id)
    if slot ~= 17 and slot ~= 18 then return true end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
    local weapon = (Enum.ItemClass and Enum.ItemClass.Weapon) or 2
    if slot == 18 then return classID == weapon and (subclassID == 2 or subclassID == 3 or subclassID == 18) end
    return classID == weapon or subclassID == ((Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Shield) or 6)
end

local function Unenchanted()
    local missing, count = {}, 0
    for _, s in ipairs(ENCHANT_SLOTS) do
        local id = GetInventoryItemID("player", s[1])
        local link = id and GetInventoryItemLink("player", s[1])
        if link and Enchantable(s[1], id) then
            count = count + 1
            local enchant = link:match("item:%d+:(%d*)")
            if not enchant or enchant == "" or enchant == "0" then missing[#missing + 1] = s[2] end
        end
    end
    return missing, count
end

table.insert(supplies.cells, { label = "Enchants", wide = true, get = function()
    local missing, count = Unenchanted()
    if count == 0 then return false end
    if #missing == 0 then return "All", false, "every piece that can carry one" end
    return string.format("%d of %d", count - #missing, count), false, "none on: " .. table.concat(missing, ", "),
        (count - #missing) / count
end, tip = function(tt)
    Line(tt, "Gear that could carry an enchant (or a scope, or an arcanum on the head and legs) but doesn't.")
end })

-- Professions and secondary skills, by the game's skill line IDs.
local PROFESSIONS = { 171, 164, 333, 202, 182, 165, 186, 393, 197, 185, 129, 356, 633 }

local function ProfessionCell(id)
    return { label = function()
        local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, id)
        return ok and type(info) == "table" and info.name or "?"
    end, wide = true, get = function()
        if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then return false end
        local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, id)
        if not ok or type(info) ~= "table" or type(info.rank) ~= "number" or info.rank <= 0 then return false end
        local rank, max = info.rank + (info.modifier or 0), info.maxRank or 0
        local note
        if max > 0 and max < 300 and info.rank >= max - 25 then
            note = "near its cap: a trainer can raise it"
        end
        return string.format("%d / %d", rank, max), false, note, max > 0 and rank / max or nil
    end }
end

local professions = { key = "professions", title = "Professions", colorKey = "Gear", cells = {} }
for _, id in ipairs(PROFESSIONS) do professions.cells[#professions.cells + 1] = ProfessionCell(id) end

------------------------------------------------------------------------------
-- The List tab: every stat the game's own sheet can show, one per line (FrogLib's StatList, the
-- same list FrogUI puts in the stats pane), with the game's own tooltips.
------------------------------------------------------------------------------

local LIST_COLORS = { "General", "Attributes", "Attack", "Attack", "Secondary Stats", "Defense", "Defense" }

local function ListBlocks()
    local StatList = FrogLib.StatList
    local blocks = {}
    for i, cat in ipairs(StatList.CATEGORIES) do
        local sec = { key = "list" .. i, title = cat[1], colorKey = LIST_COLORS[i] or "General", cells = {} }
        for _, entry in ipairs(cat[2]) do
            local last = {}
            sec.cells[#sec.cells + 1] = {
                wide = true,
                -- Read after get, which fills it in.
                label = function() return last.label end,
                get = function()
                    local label, value, tips = StatList.Read(entry)
                    if label == nil then return false end
                    label, value = N(label), N(value) -- hidden by the game: the last reading stays
                    last.label = (label:gsub(":%s*$", ""))
                    last.tips = tips
                    return value
                end,
                -- The game's own tooltip lines (its first is the name and value, shown already).
                tip = function(tt)
                    for n, t in ipairs(last.tips or {}) do
                        if n > 1 and not FrogLib.issecret(t) then Line(tt, t) end
                    end
                end,
            }
        end
        blocks[#blocks + 1] = { kind = "section", section = sec }
    end
    return blocks
end

------------------------------------------------------------------------------
-- Spells: where they go, and how far a full mana bar gets you
------------------------------------------------------------------------------

-- Your spells against an enemy `over` levels up: resisted outright, crits (on what lands), hits.
local function SpellRow(over, label)
    local miss = R.SpellMiss(over)
    local crit = N((R.BestSchool(GetSpellCritChance))) * (100 - miss) / 100
    local segs = { Seg(100 - miss - crit, C.hit, "Hit"), Seg(crit, C.crit, "Crit"), Seg(miss, C.miss, "Resisted") }
    return { label = label, right = "lands " .. Pct(100 - miss), segs = segs }
end

-- Every spell in your spellbook that costs mana, its highest rank only: name, icon, cost and
-- cast time.
local function ManaSpells()
    local found = {}
    local book = C_SpellBook
    if not (book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo and book.GetSpellBookItemInfo) then
        return {}
    end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local spellType = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    for i = 1, book.GetNumSpellBookSkillLines() do
        local line = book.GetSpellBookSkillLineInfo(i)
        if line and not line.offSpecID and not line.shouldHide then
            for j = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local info = book.GetSpellBookItemInfo(j, bank)
                if info and info.spellID and not info.isPassive and (not spellType or info.itemType == spellType) then
                    for _, cost in ipairs(C_Spell.GetSpellPowerCost(info.spellID) or {}) do
                        if cost.type == 0 and (cost.cost or 0) > 0 then
                            local known = found[info.name]
                            if not known or known.cost < cost.cost then
                                local spell = C_Spell.GetSpellInfo(info.spellID)
                                found[info.name] = { name = info.name, icon = info.iconID, cost = cost.cost,
                                    cast = spell and spell.castTime and spell.castTime / 1000 or 0 }
                            end
                        end
                    end
                end
            end
        end
    end
    local list = {}
    for _, spell in pairs(found) do list[#list + 1] = spell end
    table.sort(list, function(a, b) return a.cost > b.cost end)
    return list
end

local function SpellEntries()
    local maxMana = N(UnitPowerMax("player", 0))
    local out = {}
    for _, spell in ipairs(ManaSpells()) do
        local casts = math.floor(maxMana / spell.cost)
        out[#out + 1] = {
            icon = spell.icon, title = spell.name,
            right = casts == 1 and "1 cast" or string.format("%d casts", casts),
            lines = { { text = string.format("%d mana · %s", spell.cost,
                spell.cast > 0 and string.format("%.1fs cast", spell.cast) or "instant"), dim = true } },
        }
        if #out == 8 then break end
    end
    return out
end

local casterTiles = {
    damageTile,
    { caption = "SPELL CRIT", colorKey = "Secondary Stats", get = function()
        return Pct((R.BestSchool(GetSpellCritChance))), false, "crits 50% stronger"
    end },
    { caption = "MANA REGEN", colorKey = "Secondary Stats", get = function()
        local rate, measured = ManaRate()
        return Dec(rate * 5), false, measured and "per 5s, measured" or "per 5s resting"
    end },
}

local meleeTiles = {
    { caption = "PAPER DPS", colorKey = "Attack", get = function()
        return string.format("%.1f", R.PaperDPS()), false, "what the game shows"
    end },
    { caption = "SWING", colorKey = "Attack", get = function()
        local min, max = UnitDamage("player")
        return string.format("%.2fs", N((UnitAttackSpeed("player")))), false,
            string.format("%d-%d damage", math.floor(N(min)), math.ceil(N(max)))
    end },
    damageTile,
}

local dpsSource = { kind = "bars", key = "dpsSource", title = "Where your damage comes from", colorKey = "Attack", rows = function()
    local paper = R.PaperDPS()
    local ap = R.MeleeAP()
    local fromAP = ap / R.AP_PER_DPS
    local weapon = math.max(0, paper - fromAP)
    return { {
        segs = {
            { pct = weapon / paper * 100, color = C.weapon, text = string.format("%.1f from the weapon", weapon) },
            { pct = fromAP / paper * 100, color = C.ap, text = string.format("%.1f from %d attack power", fromAP, ap) },
        },
        cols = 2,
    } }
end }

local swings = { kind = "bars", key = "swings", title = "Where your swings go", colorKey = "Attack", rows = function()
    return { SwingRow(0, SameLabel()), SwingRow(3, BossLabel()) }
end }

local spellsGo = { kind = "bars", key = "spellsGo", title = "Where your spells go", colorKey = "Secondary Stats", rows = function()
    return { SpellRow(0, SameLabel()), SpellRow(3, BossLabel()) }
end }

local castsFromFull = { kind = "entries", key = "casts", title = "Casts from full mana", colorKey = "Secondary Stats",
    items = SpellEntries, empty = "No spells that cost mana yet." }

local roleSwitch = { kind = "role" }

-- Offense follows the Melee / Caster switch: spells first as a caster, the weapon first otherwise.
local function OffenseBlocks()
    if Caster() then
        return {
            roleSwitch,
            { kind = "tiles", tiles = casterTiles },
            { kind = "section", section = S.spell },
            spellsGo,
            castsFromFull,
            { kind = "section", section = pet },
            { kind = "section", section = S.melee },
        }
    end
    local blocks = {
        { kind = "tiles", tiles = meleeTiles },
        { kind = "section", section = S.melee },
        { kind = "section", section = rage },
        { kind = "section", section = S.ranged },
        { kind = "section", section = pet },
        { kind = "section", section = S.spell },
        dpsSource,
        swings,
    }
    if R.UsesMana() then table.insert(blocks, 1, roleSwitch) end
    return blocks
end

------------------------------------------------------------------------------
-- The tabs
------------------------------------------------------------------------------

ns.Tabs = {
    {
        key = "overview", title = "Overview",
        blocks = {
            { kind = "tiles", tiles = { damageTile, ehpTile, powerTile } },
            { kind = "section", section = S.attributes },
            { kind = "worth" },
            { kind = "section", section = ready },
            { kind = "section", section = S.caps },
            { kind = "changes", key = "lastChange", title = "Last change", colorKey = "Attributes", limit = 1, hideEmpty = true },
        },
    },
    {
        key = "offense", title = "Offense",
        blocks = OffenseBlocks,
    },
    {
        key = "defense", title = "Defense",
        blocks = {
            { kind = "tiles", tiles = {
                ehpTile,
                { caption = "VS SPELLS", colorKey = "Defense", get = function()
                    local level, best = UnitLevel("player"), 0
                    for school = 2, 6 do
                        local _, total = UnitResistance("player", school)
                        best = math.max(best, N(total))
                    end
                    local hp = N(UnitHealthMax("player"))
                    if best == 0 then return Num(hp), false, "no resistances yet" end
                    local avg = math.min(0.75, 0.75 * best / (level * 5))
                    return Num(math.floor(hp / (1 - avg) + 0.5)), false, string.format("best school, %d%% resisted", avg * 100 + 0.5)
                end },
                { caption = "AVOID", colorKey = "Defense", get = function()
                    local t = R.IncomingTable(0)
                    return Pct(t.miss + t.dodge + t.parry), false, "of melee swings"
                end },
            } },
            { kind = "bars", key = "incoming", title = "When you're swung at", colorKey = "Defense", rows = function()
                return { IncomingRow(0, SameLabel()), IncomingRow(3, BossLabel()) }
            end },
            { kind = "section", section = tanking },
            { kind = "section", section = measured },
            { kind = "section", section = armorByLevel },
            { kind = "section", section = S.defense },
        },
    },
    {
        key = "gear", title = "Gear",
        blocks = {
            { kind = "tiles", tiles = {
                { caption = "ITEM LEVEL", colorKey = "Gear", get = function()
                    local avg, equipped = GetAverageItemLevel()
                    return string.format("%.1f", N(equipped or avg)), false, "equipped"
                end },
                { caption = "DURABILITY", colorKey = "Gear", get = function()
                    local avg, low = R.Durability()
                    if not avg then return "-", false, "nothing to wear out" end
                    local text = string.format("%d%%", avg * 100 + 0.5)
                    if low < 0.25 then text = "|cffff4040" .. text .. "|r" elseif low < 0.5 then text = "|cffffd040" .. text .. "|r" end
                    return text, false, low < 0.995 and string.format("most worn %d%%", low * 100 + 0.5) or "nothing worn"
                end },
                { caption = "WEAPON", colorKey = "Attack", get = function()
                    local link = GetInventoryItemLink("player", INVSLOT_MAINHAND or 16)
                    local stats = link and C_Item.GetItemStats(link)
                    local dps = stats and stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
                    if not dps then return "-", false, "no weapon" end
                    return string.format("%.1f", dps), false, "DPS on its own"
                end },
            } },
            { kind = "chips", key = "items", title = "Your items give", colorKey = "Gear",
              foot = "Enchants and buffs aren't included.", chips = function()
                return R.GearSummary((R.GearTotals()))
            end },
            { kind = "section", section = supplies },
            { kind = "section", section = professions },
            { kind = "changes", key = "changes", title = "Since you logged in", colorKey = "Attributes", limit = 8 },
            { kind = "section", section = S.general },
        },
    },
    {
        key = "list", title = "List",
        blocks = ListBlocks(),
    },
}
