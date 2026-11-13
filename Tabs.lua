local _, ns = ...

-- The tabs and what's on each: blocks the panel lays out top to bottom (tiles, a section of cells,
-- stacked bars, "what +10 gets you", chips, change cards, icon entries, the Melee / Ranged / Caster
-- switch). A tab's blocks can be a function, for tabs that change with the switch. Everything reads
-- through ns.Stats (Stats.lua), so secret values in combat keep the last reading.

local Stats, Section = ns.Stats, ns.SectionByKey
local Known, Number, Percent, OneDecimal, Line = Stats.Known, Stats.Number, Stats.Percent, Stats.OneDecimal, Stats.Line

local CASTERS = { MAGE = true, PRIEST = true, WARLOCK = true }

local function EHP()
    local health, reduction = Known(UnitHealthMax("player")), Stats.ArmorReduction(Stats.ArmorNow())
    return health / (1 - reduction), health, reduction
end

local function ManaRate()
    local measured = ns.Regen and ns.Regen:Rate("rest")
    if measured then return measured, true end
    return Known((GetManaRegen())), false
end

local function Seconds(seconds)
    if seconds >= 120 then return string.format("%.1f min", seconds / 60) end
    return string.format("%ds", seconds + 0.5)
end

------------------------------------------------------------------------------
-- Tiles
------------------------------------------------------------------------------

-- Showing things as a caster: the switch's Caster, for anyone with mana.
local function Caster() return ns.WorthRole() == "caster" and Stats.UsesMana() end

-- As ranged: the switch's Ranged (hunters), with something to shoot. Stats.lua's Caps rows ask too.
function ns.Ranged() return ns.WorthRole() == "ranged" and Stats.HasRangedWeapon() end
local Ranged = ns.Ranged

local damageTile = {
    caption = function() return Caster() and "SPELL POWER" or "REAL DPS" end, colorKey = "Attack",
    get = function()
        if Caster() then
            return "+" .. Number((Stats.BestSchool(GetSpellBonusDamage))), false,
                Percent((Stats.BestSchool(GetSpellCritChance))) .. " crit"
        end
        local paper, share
        if Ranged() then
            paper, share = Stats.RangedPaperDPS(), Stats.ShotTable(0).mult
        else
            paper, share = Stats.PaperDPS(), Stats.SwingTable(0).mult
        end
        return string.format("%.1f", paper * share), false, string.format("%.1f on paper", paper)
    end,
    tip = function(tooltip)
        if Caster() then
            Line(tooltip, "Bonus damage and healing on your spells. Switch to Melee to see your real DPS.")
        elseif Ranged() then
            Line(tooltip, "What your ranged auto-attacks really do to an enemy of your level, after misses "
                .. "and crits. The Offense tab shows the split.")
        else
            Line(tooltip, "What your auto-attacks really do to an enemy of your level, after misses, dodges, "
                .. "glancing blows and crits. The Offense tab shows the split.")
        end
    end,
}

local ehpTile = {
    caption = "EFFECTIVE HP", colorKey = "Defense",
    get = function()
        local ehp, health, reduction = EHP()
        return Number(math.floor(ehp + 0.5)), false, string.format("%s HP, armor %.0f%%", Number(health), reduction * 100)
    end,
    tip = function(tooltip)
        Line(tooltip, "The physical damage it takes to bring you down from full health, once armor has "
            .. "taken its share, against an enemy of your level.")
    end,
}

local powerTile = {
    caption = function()
        if Stats.UsesMana() then return "MANA" end
        return string.upper(select(2, Stats.DisplayPower()))
    end, colorKey = "Secondary Stats",
    get = function()
        if Stats.UsesMana() then
            local maxMana = Known(UnitPowerMax("player", 0))
            local rate = ManaRate()
            return Number(maxMana), false, rate > 0 and ("full in " .. Seconds(maxMana / rate)) or "no regen"
        end
        local powerType = Stats.DisplayPower()
        local note
        if GetPowerRegen then
            local regen = Known((GetPowerRegen()))
            if regen > 0 then note = OneDecimal(regen) .. " per second" end
        end
        return Number(UnitPowerMax("player", powerType)), false, note
    end,
    tip = function(tooltip)
        if not Stats.UsesMana() then return end
        local _, measured = ManaRate()
        Line(tooltip, "Time to fill your mana from empty while not casting (without drinking)"
            .. (measured and ", from your measured regen." or "."))
    end,
}

------------------------------------------------------------------------------
-- What +10 of each gets you
------------------------------------------------------------------------------

-- What it takes to know: base values once, then each stat's gain worked out with the client's
-- own conversion functions where it has them.
local function StatValue(statIndex)
    local _, stat = UnitStat("player", statIndex)
    return Known(stat)
end

local function Fraction(Convert, statIndex, stat)
    local share = Stats.Call(Convert, statIndex, stat)
    return share and share * 100 or 0
end

local function StaminaRow()
    local _, health = EHP()
    local perPoint = Stats.Call(UnitHPPerStamina, "player") or 10
    return { stat = "+10 Stamina", headline = string.format("+%d HP", perPoint * 10), colorKey = "Defense",
        gain = perPoint * 10 / health, detail = string.format("%d%% more effective health", perPoint * 10 / health * 100 + 0.5) }
end

local function MeleeWorth()
    local rows = {}
    local paper = Stats.PaperDPS()
    local swings = Stats.SwingTable(0)
    local real = paper * swings.mult
    local _, offSpeed = UnitAttackSpeed("player")
    local hands = offSpeed and 1.5 or 1 -- an off hand gets half the attack power bonus
    local function DPSFromAP(attackPower) return attackPower / Stats.AP_PER_DPS * hands * swings.mult end

    local strength = StatValue(1)
    local strengthAP = (Stats.StatAP(1, strength + 10) or 0) - (Stats.StatAP(1, strength) or 0)
    local strengthDPS = DPSFromAP(strengthAP)
    rows[#rows + 1] = { stat = "+10 Strength", headline = string.format("+%.1f DPS", strengthDPS), colorKey = "Attack",
        gain = strengthDPS / real,
        detail = string.format("+%d attack power · %d%% more damage", strengthAP, strengthDPS / real * 100 + 0.5) }

    rows[#rows + 1] = StaminaRow()

    local agility = StatValue(2)
    local crit = Fraction(GetCritChanceFromStat, 2, agility + 10) - Fraction(GetCritChanceFromStat, 2, agility)
    local agilityAP = (Stats.StatAP(2, agility + 10) or 0) - (Stats.StatAP(2, agility) or 0)
    local agilityDPS = paper * crit / 100 + DPSFromAP(agilityAP)
    local dodge = (Stats.Call(GetDodgeChanceFromAttribute) or 0) * 100 / math.max(1, agility) * 10
    rows[#rows + 1] = { stat = "+10 Agility", headline = string.format("+%.2f DPS", agilityDPS), colorKey = "Attack",
        gain = agilityDPS / real, detail = string.format("+%.1f%% crit · +%.1f%% dodge · +20 armor%s", crit, dodge,
            agilityAP > 0 and string.format(" · +%d AP", agilityAP) or "") }

    if swings.miss > 0 then
        local hitDPS = paper * math.min(1, swings.miss) / 100
        rows[#rows + 1] = { stat = "+1% Hit", headline = string.format("+%.2f DPS", hitDPS), colorKey = "Attack",
            gain = hitDPS / real, detail = "1 fewer miss in every 100 swings" }
    end
    return rows
end

local function IntellectRow()
    local maxMana = Known(UnitPowerMax("player", 0))
    local intellect = StatValue(4)
    local mana = (intellect + 10 <= (INTELLECT_BREAK or 20)) and 10 or 10 * (MANA_PER_INTELLECT or 15)
    local crit = Fraction(GetSpellCritChanceFromStat, 4, intellect + 10) - Fraction(GetSpellCritChanceFromStat, 4, intellect)
    return { stat = "+10 Intellect", headline = string.format("+%d mana", mana), colorKey = "Secondary Stats",
        gain = mana / maxMana, detail = string.format("%d%% more mana", mana / maxMana * 100 + 0.5)
            .. (crit >= 0.05 and string.format(" · +%.1f%% spell crit", crit) or "") }
end

-- A hunter's shots: Strength gives them no ranged attack power, so it isn't here.
local function RangedWorth()
    local rows = {}
    local paper = Stats.RangedPaperDPS()
    local shots = Stats.ShotTable(0)
    local real = paper * shots.mult

    local agility = StatValue(2)
    local crit = Fraction(GetCritChanceFromStat, 2, agility + 10) - Fraction(GetCritChanceFromStat, 2, agility)
    local agilityAP = Stats.StatRAP(2, agility + 10) - Stats.StatRAP(2, agility)
    local agilityDPS = paper * crit / 100 + agilityAP / Stats.AP_PER_DPS * shots.mult
    rows[#rows + 1] = { stat = "+10 Agility", headline = string.format("+%.2f DPS", agilityDPS), colorKey = "Attack",
        gain = agilityDPS / real,
        detail = string.format("+%d ranged attack power · +%.1f%% crit", agilityAP, crit) }

    rows[#rows + 1] = StaminaRow()
    rows[#rows + 1] = IntellectRow()

    if shots.miss > 0 then
        local hitDPS = paper * math.min(1, shots.miss) / 100
        rows[#rows + 1] = { stat = "+1% Hit", headline = string.format("+%.2f DPS", hitDPS), colorKey = "Attack",
            gain = hitDPS / real, detail = "1 fewer miss in every 100 shots" }
    end
    return rows
end

local function CasterWorth()
    local rows = { IntellectRow() }

    local spirit = StatValue(5)
    local fromSpirit = Stats.Call(GetManaRegenFromSpirit)
    local regen = Known((GetManaRegen()))
    if fromSpirit and spirit > 0 and regen > 0 then
        local mp5 = fromSpirit * 5 / spirit * 10
        local hp5 = (Stats.Call(GetHealthRegenFromSpirit) or 0) * 0.75 * 5 / spirit * 10
        rows[#rows + 1] = { stat = "+10 Spirit", headline = string.format("+%s mp5", OneDecimal(mp5)), colorKey = "Secondary Stats",
            gain = mp5 / (regen * 5), detail = string.format("%d%% faster mana regen · +%s health per 5s",
                mp5 / (regen * 5) * 100 + 0.5, OneDecimal(hp5)) }
    end

    rows[#rows + 1] = StaminaRow()

    rows[#rows + 1] = { stat = "+10 Spell Power", headline = "+10 per spell", colorKey = "Secondary Stats",
        detail = "damage and healing, scaled by each spell's cast time" }
    return rows
end

-- Auto: mages, priests and warlocks cast, hunters shoot, warriors and rogues melee, a druid melees in
-- cat or bear form, and a shaman or paladin casts once their best school's bonus passes half their AP.
local CAT_BEAR = { [1] = true, [5] = true, [8] = true }
local lastAuto

local function AutoRole()
    local class = Stats.Class()
    if CASTERS[class] then return "caster" end
    if class == "HUNTER" then return Stats.HasRangedWeapon() and "ranged" or "melee" end
    if class == "DRUID" then
        local id = GetShapeshiftFormID and GetShapeshiftFormID()
        if id == nil and GetShapeshiftFormID then return "caster" end
        if id ~= nil then return CAT_BEAR[Known(id)] and "melee" or "caster" end
        return (GetShapeshiftForm() or 0) == 0 and "caster" or "melee"
    end
    if class == "SHAMAN" or class == "PALADIN" then
        local spellPower = Stats.BestSchool(GetSpellBonusDamage)
        return spellPower > Stats.MeleeAP() / 2 and "caster" or "melee"
    end
    return "melee"
end

-- The switch's choices: Ranged for hunters, Caster for anyone else with mana, none for the rest.
local HUNTER_ROLES, CASTER_ROLES = { "auto", "melee", "ranged" }, { "auto", "melee", "caster" }

function ns.Roles()
    if Stats.Class() == "HUNTER" then return HUNTER_ROLES end
    if Stats.UsesMana() then return CASTER_ROLES end
end

-- What's picked on the switch: one of your choices (the setting is shared by your characters),
-- else Auto.
function ns.RoleChoice()
    for _, role in ipairs(ns.Roles() or {}) do
        if role ~= "auto" and role == ns.db.role then return role end
    end
    return "auto"
end

-- Which list to show: the switch's pick, else Auto's (its last answer while it can't be read, in
-- combat).
function ns.WorthRole()
    local choice = ns.RoleChoice()
    if choice ~= "auto" then return choice end
    local ok, auto = pcall(AutoRole)
    if ok and auto then lastAuto = auto end
    return lastAuto or "melee"
end

function ns.Worth()
    if Caster() then return CasterWorth() end
    if Ranged() then return RangedWorth() end
    return MeleeWorth()
end

------------------------------------------------------------------------------
-- Stacked bars
------------------------------------------------------------------------------

-- Segment colours, the same in both looks.
local COLORS = {
    hit = { 0.42, 0.48, 0.55 }, crit = { 1, 0.78, 0.25 }, miss = { 0.9, 0.33, 0.29 },
    dodge = { 0.66, 0.70, 0.74 }, glance = { 0.62, 0.48, 0.28 },
    safe = { 0.31, 0.89, 0.42 }, yours = { 0.35, 0.70, 1 }, parry = { 0.10, 0.82, 0.63 },
    block = { 0.55, 0.62, 0.80 }, crush = { 0.9, 0.33, 0.29 },
    weapon = { 0.72, 0.40, 0.18 }, ap = { 1, 0.70, 0.42 },
}

local function Segment(share, color, name)
    return { pct = share, color = color, text = string.format("%s %s", name, Percent(share)) }
end

local function SwingRow(over, label)
    local swings = Stats.SwingTable(over)
    local paper = Stats.PaperDPS()
    local segments = {
        Segment(swings.hit, COLORS.hit, "Hit"), Segment(swings.glance, COLORS.glance, "Glancing"),
        Segment(swings.crit, COLORS.crit, "Crit"), Segment(swings.miss, COLORS.miss, "Miss"),
        Segment(swings.dodge, COLORS.dodge, "Dodge"),
    }
    local foot = swings.glance > 0 and string.format("glancing blows deal %d%% less", swings.glancePenalty + 0.5) or nil
    return { label = label, right = string.format("%.1f real DPS", paper * swings.mult), segs = segments, foot = foot }
end

local function IncomingRow(over, label)
    local incoming = Stats.IncomingTable(over)
    local segments = {
        Segment(incoming.hit, COLORS.hit, "Hit"), Segment(incoming.crush, COLORS.crush, "Crushing"),
        Segment(incoming.crit, COLORS.crit, "Crit"), Segment(incoming.miss, COLORS.safe, "Miss"),
        Segment(incoming.dodge, COLORS.yours, "Dodge"), Segment(incoming.parry, COLORS.parry, "Parry"),
        Segment(incoming.block, COLORS.block, "Block"),
    }
    return { label = label, right = "avoid " .. Percent(incoming.miss + incoming.dodge + incoming.parry), segs = segments,
        foot = incoming.crush > 0 and "crushing blows deal 150%" or nil }
end

local function ShotRow(over, label)
    local shots = Stats.ShotTable(over)
    local segments = {
        Segment(shots.hit, COLORS.hit, "Hit"), Segment(shots.crit, COLORS.crit, "Crit"),
        Segment(shots.miss, COLORS.miss, "Miss"),
    }
    return { label = label, right = string.format("%.1f real DPS", Stats.RangedPaperDPS() * shots.mult), segs = segments }
end

local function BossLabel() return string.format("Raid boss (level %d)", UnitLevel("player") + 3) end
local function SameLabel() return string.format("Level %d enemy", UnitLevel("player")) end

------------------------------------------------------------------------------
-- Extra cells for the tabs
------------------------------------------------------------------------------

table.insert(Section.spell.cells, 5, { label = "Resisted", get = function()
    return Percent(Stats.SpellMiss(0)) .. " · " .. Percent(Stats.SpellMiss(3)) .. " boss"
end, tip = function(tooltip)
    Line(tooltip, "Your spells' chance to be resisted outright by an enemy:")
    local level = UnitLevel("player")
    for over = 0, 3 do
        Line(tooltip, string.format("Level %d%s", level + over, over == 3 and " (raid boss)" or ""), Percent(Stats.SpellMiss(over)))
    end
end, wide = true })

table.insert(Section.defense.cells, { label = "Health Regen", wide = true, get = function()
    local fromSpirit = Stats.Call(GetHealthRegenFromSpirit)
    if not fromSpirit then return false end
    local standing = fromSpirit * 0.75 * 5
    return string.format("%d per 5s", standing), false, string.format("%d sitting · out of combat", fromSpirit * 5)
end })

-- The most crit your white swings can use against a boss, hitting it from behind: what's left
-- once its misses, dodges and glancing blows have their share.
table.insert(Section.caps.cells, { label = "Crit cap (boss)", wide = true, get = function()
    if Caster() or Ranged() then return false end
    local swings = Stats.SwingTable(3)
    -- In the sheet's own terms: the boss also takes some crit off for weapon skill short of its
    -- defense, so the sheet's crit chance can go that much higher.
    local cap = 100 - swings.miss - swings.dodge - swings.glance + swings.critPenalty
    local crit = Known(GetCritChance())
    local note = crit >= cap and "past it: more crit is wasted on white hits"
        or string.format("%s more crit before white hits stop gaining", Percent(cap - crit))
    return string.format("%s of %s", Percent(crit), Percent(cap)), false, note, math.min(1, crit / cap)
end, tip = function(tooltip)
    local swings = Stats.SwingTable(3)
    Line(tooltip, "A boss's misses, dodges and glancing blows come first; crits only land on what's left. "
        .. "Past that, extra crit chance does nothing for auto-attacks (special attacks still crit).")
    Line(tooltip, " ")
    Line(tooltip, "Miss", Percent(swings.miss))
    Line(tooltip, "Dodge", Percent(swings.dodge))
    Line(tooltip, "Glancing", Percent(swings.glance))
    if swings.critPenalty > 0 then Line(tooltip, "Crit lost to weapon skill", Percent(swings.critPenalty)) end
    Line(tooltip, "|cff8c8c8cFrom behind, so parries aren't counted. In the character sheet's own crit chance.|r")
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
            local reduction = Stats.ArmorReduction(Stats.ArmorNow(), over)
            return string.format("%.1f%%", reduction * 100), false, nil, reduction / 0.75
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
    if Stats.Class() ~= "DRUID" then return false end
    return Stats.DisplayPower() == 1
end

-- Who these lines are for: shield users and druids in bear form, and warriors and paladins.
local function Tanky()
    local class = Stats.Class()
    return HasShield() or InBear() or class == "WARRIOR" or class == "PALADIN"
end

-- A block ability that adds to your chance while it's up: warriors' Shield Block (75% for 5
-- seconds), paladins' Holy Shield (30% for 10 seconds). Only with a shield, once you know it.
local function BlockAbility()
    if not HasShield() then return nil end
    local class = Stats.Class()
    local IsKnown = IsPlayerSpell or IsSpellKnown
    local function Knows(...)
        for _, id in ipairs({ ... }) do
            if IsKnown and IsKnown(id) then return true end
        end
        return false
    end
    if class == "WARRIOR" and Knows(2565) then return "Shield Block", 75 end
    if class == "PALADIN" and Knows(20925, 20927, 20928) then return "Holy Shield", 30 end
    return nil
end

-- An enemy's swing goes down the table in order: miss, dodge, parry, block, crit, crushing blow,
-- then a plain hit. Crushing blows fall off the end once everything before them fills 100%: how far short.
local function CrushShort(incoming)
    return incoming.crush + incoming.hit
end

local tanking = {
    key = "tanking", title = "Tanking a raid boss", colorKey = "Defense",
    show = Tanky,
    cells = {
        { label = "Crushing blows", wide = true, get = function()
            if not Tanky() then return false end
            local incoming = Stats.IncomingTable(3)
            if InBear() then
                return Percent(incoming.crush), false, "bears can't block or parry, so these can't be pushed off; armor and health instead"
            end
            local short = CrushShort(incoming)
            if short <= 0 then
                return "None", false, "miss, dodge, parry and block fill the table: a boss can't crush you", 1
            end
            local name, bonus = BlockAbility()
            local note
            if name and bonus >= short then
                note = string.format("%s short, covered while %s is up", Percent(short), name)
            elseif name then
                note = string.format("%s short; %s covers %s of it", Percent(short), name, Percent(bonus))
            else
                note = string.format("%s more miss, dodge, parry or block pushes them off", Percent(short))
            end
            return Percent(incoming.crush) .. " of swings", false, note, math.max(0, 1 - short / 100)
        end, tip = function(tooltip)
            local incoming = Stats.IncomingTable(3)
            Line(tooltip, "A boss three levels up swings at you down this table, in order:")
            Line(tooltip, "Miss", Percent(incoming.miss))
            Line(tooltip, "Dodge", Percent(incoming.dodge))
            Line(tooltip, "Parry", Percent(incoming.parry))
            Line(tooltip, "Block", Percent(incoming.block))
            Line(tooltip, "Crit", Percent(incoming.crit))
            Line(tooltip, "Crushing blow (150% damage)", Percent(incoming.crush))
            Line(tooltip, "Plain hit", Percent(incoming.hit))
            Line(tooltip, " ")
            Line(tooltip, "|cff8c8c8cOnce everything above a crushing blow adds up to 100%, there's no room left "
                .. "for one. Defense past your cap doesn't lower the crushing chance itself, but its extra "
                .. "miss and dodge push it off.|r")
        end },
        { label = "Crits from a boss", wide = true, get = function()
            if not Tanky() then return false end
            local defense = Stats.DefenseSkill()
            if not defense then return false end
            local level = UnitLevel("player")
            -- Each point of defense takes 0.04% off: 5% plus the boss's skill over your defense.
            local need = (level + 3) * Stats.SKILL_PER_LEVEL + 125
            local incoming = Stats.IncomingTable(3)
            if defense >= need then return "None", false, "enough defense that a boss can't crit you", 1 end
            return Percent(incoming.crit), false, string.format("%d defense stops them (you have %d: %d more)",
                need, defense, need - defense), defense / need
        end, tip = function(tooltip)
            local level = UnitLevel("player")
            Line(tooltip, "A boss three levels up crits for double damage. Each point of defense takes 0.04% off "
                .. "its crit chance (5%, plus 0.04% per point of its weapon skill over your defense).")
            Line(tooltip, " ")
            Line(tooltip, "Defense to be crit by nothing:")
            for over = 0, 3 do
                Line(tooltip, string.format("Level %d%s", level + over, over == 3 and " (raid boss)" or ""),
                    tostring((level + over) * Stats.SKILL_PER_LEVEL + 125))
            end
            Line(tooltip, "|cff8c8c8cA long way off at most levels: a goal for gear later on.|r")
        end },
        { label = "Block value", wide = true, get = function()
            local chance = Known(GetBlockChance())
            if chance <= 0 or not GetShieldBlock then return false end
            local value = Known(GetShieldBlock())
            return Number(value), false, string.format("each block takes %s off the hit · %s of swings", Number(value), Percent(chance))
        end, tip = function(tooltip)
            Line(tooltip, "How much damage a blocked swing loses: your shield's block value plus what your "
                .. "strength adds. A block that soaks the whole hit leaves nothing.")
            local name, bonus = BlockAbility()
            if name then
                Line(tooltip, " ")
                Line(tooltip, string.format("%s adds %d%% to your block chance while it's up.", name, bonus))
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

local function UsesRage() return Stats.DisplayPower() == 1 end

local rage = {
    key = "rage", title = "Rage", colorKey = "Attack",
    show = UsesRage,
    cells = {
        { label = "Per hit you land", wide = true, get = function()
            if not UsesRage() then return false end
            local low, high = UnitDamage("player")
            local average = (Known(low) + Known(high)) / 2
            local perHit = 7.5 * average / RageConversion()
            local speed = Known((UnitAttackSpeed("player")))
            local swings = Stats.SwingTable(0)
            -- Misses and dodges give none; crits twice the damage, glancing blows less.
            local perMinute = perHit * swings.mult * 60 / speed
            return string.format("%.1f rage", perHit), false,
                string.format("crits %.1f · about %d a minute from your swings", perHit * 2, perMinute + 0.5)
        end, tip = function(tooltip)
            Line(tooltip, "Rage from your main hand's white hits against an enemy of your level: 7.5 x the "
                .. "damage, divided by your level's rage conversion. Misses and dodges give none.")
            Line(tooltip, " ")
            Line(tooltip, "|cff8c8c8cClassic's formula: an estimate if Forever's differs. Abilities that deal damage "
                .. "don't make rage; white hits do.|r")
        end },
        { label = "Per 100 damage taken", wide = true, get = function()
            if not UsesRage() then return false end
            local perHundred = 2.5 * 100 / RageConversion()
            return string.format("%.1f rage", perHundred), false, "not counting what's blocked or absorbed"
        end, tip = function(tooltip)
            Line(tooltip, "Rage from damage you take: 2.5 x the damage, divided by your level's rage conversion. "
                .. "Blocked and absorbed damage doesn't count.")
        end },
    },
}

------------------------------------------------------------------------------
-- Ammo and weapon buffs (poisons, imbues, oils and stones)
------------------------------------------------------------------------------

local AMMO_SLOT = INVSLOT_AMMO or 0

local function TimeLeft(milliseconds)
    local seconds = milliseconds / 1000
    if seconds >= 60 then return string.format("%d min", seconds / 60 + 0.5) end
    return string.format("%ds", seconds + 0.5)
end

-- A weapon buff's cell value: its time left (yellow under five minutes) and charges.
local function WeaponBuff(has, milliseconds, charges)
    if not has then return false end
    local text = TimeLeft(Known(milliseconds))
    if Known(milliseconds) < 300000 then text = "|cffffd040" .. text .. "|r" end
    return text, false, (charges and Known(charges) > 0) and string.format("%d charges left", charges) or nil
end

local supplies = {
    key = "supplies", title = "Ammo & weapon buffs", colorKey = "Gear",
    cells = {
        { label = "Ammo", wide = true, get = function()
            local count = GetInventoryItemCount("player", AMMO_SLOT)
            count = count and Known(count) or 0
            local hunter = Stats.Class() == "HUNTER"
            if count <= 0 then
                if hunter then return "|cffff4040None|r", false, "your ranged weapon has nothing to shoot" end
                return false
            end
            local speed = Known((UnitRangedDamage("player")))
            local note
            if speed and speed > 0 then
                note = string.format("about %d minutes of shooting", count * speed / 60 + 0.5)
            end
            local text = Number(count)
            if hunter and count < 200 then text = "|cffffd040" .. text .. "|r" end
            return text, false, note
        end, tip = function(tooltip)
            Line(tooltip, "The arrows or bullets in your ammo slot, and how long they last at your ranged speed "
                .. "if every shot is an auto shot.")
        end },
        { label = "Main hand buff", wide = true, get = function()
            local has, milliseconds, charges = GetWeaponEnchantInfo()
            return WeaponBuff(has, milliseconds, charges)
        end, tip = function(tooltip)
            Line(tooltip, "What's on your main-hand weapon (a poison, a shaman's imbue, a sharpening stone or oil): "
                .. "time left. Yellow under five minutes.")
        end },
        { label = "Off hand buff", wide = true, get = function()
            local _, _, _, _, has, milliseconds, charges = GetWeaponEnchantInfo()
            return WeaponBuff(has, milliseconds, charges)
        end },
    },
}

------------------------------------------------------------------------------
-- Threat: your multiplier from stance or form, talents and Salvation
------------------------------------------------------------------------------

-- Spells known, buffs on you, and your threat multiplier with its parts: FrogLib.Tank.
local KnowsRank, HasBuff, Threat = FrogLib.Tank.KnowsRank, FrogLib.Tank.HasBuff, FrogLib.Tank.Threat

local function ThreatCell()
    return { label = "Threat", wide = true, get = function()
        local multiplier, parts = Threat()
        if #parts == 0 then return false end
        local names = {}
        for _, part in ipairs(parts) do names[#names + 1] = part[1] end
        return string.format("x%.2f", multiplier), false, table.concat(names, ", ")
    end, tip = function(tooltip)
        local multiplier, parts = Threat()
        Line(tooltip, "How much threat what you do makes, against the same damage or healing with nothing changing it:")
        for _, part in ipairs(parts) do Line(tooltip, part[1], string.format("x%.2f", part[2])) end
        Line(tooltip, "Together", string.format("x%.2f", multiplier))
        Line(tooltip, " ")
        Line(tooltip, "|cff8c8c8cClassic's numbers: abilities with extra threat of their own (Sunder Armor, "
            .. "Revenge) are multiplied too.|r")
    end }
end

table.insert(tanking.cells, 1, ThreatCell())
-- Everyone else sees it with the general stats when something's changing it (Salvation, rogues).
local otherThreat = ThreatCell()
local TankGet = otherThreat.get
otherThreat.get = function()
    if Tanky() then return false end
    return TankGet()
end
table.insert(Section.general.cells, otherThreat)

------------------------------------------------------------------------------
-- Measured in your fights (Incoming.lua)
------------------------------------------------------------------------------

local measured = {
    key = "measured", title = "Measured in your fights", colorKey = "Defense",
    cells = {
        { label = "Swings at you", wide = true, get = function()
            local summary = ns.Incoming:Summary()
            if summary.count < 10 then return false end
            return Number(summary.count), false, "this session, physical only (the last 300)"
        end, tip = function(tooltip)
            Line(tooltip, "What really happened when enemies swung at you, from the game's own combat feedback, "
                .. "rather than worked out. Abilities that deal physical damage count too.")
        end },
        { label = "Avoided", get = function()
            local summary = ns.Incoming:Summary()
            if summary.count < 10 then return false end
            return Percent((summary.dodge + summary.parry + summary.miss) / summary.count * 100)
        end, tip = function(tooltip)
            local summary = ns.Incoming:Summary()
            Line(tooltip, "Dodged", Percent(summary.dodge / math.max(1, summary.count) * 100))
            Line(tooltip, "Parried", Percent(summary.parry / math.max(1, summary.count) * 100))
            Line(tooltip, "Missed you", Percent(summary.miss / math.max(1, summary.count) * 100))
        end },
        { label = "Blocked", get = function()
            local summary = ns.Incoming:Summary()
            if summary.count < 10 or summary.block == 0 then return false end
            return Percent(summary.block / summary.count * 100)
        end },
        { label = "Crits taken", get = function()
            local summary = ns.Incoming:Summary()
            if summary.count < 10 then return false end
            return Percent(summary.crit / summary.count * 100), summary.crit == 0
        end },
        { label = "Crushing", get = function()
            local summary = ns.Incoming:Summary()
            if summary.count < 10 then return false end
            return Percent(summary.crush / summary.count * 100), summary.crush == 0
        end },
        { label = "Average hit", wide = true, get = function()
            local summary = ns.Incoming:Summary()
            if not summary.averageHit then return false end
            return Number(math.floor(summary.averageHit + 0.5)), false, string.format("largest %s", Number(summary.largest))
        end, tip = function(tooltip)
            Line(tooltip, "The average plain hit you took (not crits, crushing blows or blocked ones), after "
                .. "your armor.")
        end },
    },
}

------------------------------------------------------------------------------
-- Resistances against a boss, school by school
------------------------------------------------------------------------------

local SCHOOL_COLORS = { { 2, "Fire", "ff8040" }, { 3, "Nat", "4cff4c" }, { 4, "Frost", "80d0ff" },
    { 5, "Shadow", "b080ff" }, { 6, "Arcane", "ffffff" } }

-- The average share of a spell resisted, at `resistance` against a caster `level`.
local function AverageResist(resistance, level)
    return math.max(0, math.min(0.75, 0.75 * resistance / (5 * level)))
end

table.insert(Section.defense.cells, { label = "Resisted (boss)", wide = true, get = function()
    local level, parts, any = UnitLevel("player") + 3, {}, false
    for _, school in ipairs(SCHOOL_COLORS) do
        local _, total = UnitResistance("player", school[1])
        local average = AverageResist(Known(total), level)
        if average > 0 then any = true end
        parts[#parts + 1] = string.format("|cff%s%s|r %d%%", school[3], school[2], average * 100 + 0.5)
    end
    return table.concat(parts, "  "), not any
end, tip = function(tooltip)
    local level = UnitLevel("player")
    Line(tooltip, "On average, how much of a spell you resist, school by school:")
    for _, school in ipairs(SCHOOL_COLORS) do
        local _, total = UnitResistance("player", school[1])
        total = Known(total)
        Line(tooltip, string.format("|cff%s%s|r (%d)", school[3], school[2], total),
            string.format("%d%% · boss %d%%", AverageResist(total, level) * 100 + 0.5,
                AverageResist(total, level + 3) * 100 + 0.5))
    end
    Line(tooltip, "|cff8c8c8c75% at most. A spell is resisted in quarters (0, 25, 50, 75 or 100%), averaging out to this.|r")
end })

------------------------------------------------------------------------------
-- Dual wield: the lower hit target special attacks need
------------------------------------------------------------------------------

for _, cell in ipairs(Section.caps.cells) do
    if cell.label == "Hit Chance" then
        local Get = cell.get
        cell.get = function()
            local text, zero, note, bar = Get()
            local _, offSpeed = UnitAttackSpeed("player")
            if offSpeed then
                note = string.format("white hits, dual wielding; special attacks need %s", Percent(Stats.HitNeeded(0) - 19))
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
            return Number(UnitHealthMax("pet")) .. " HP", false, string.format("level %d", Known(UnitLevel("pet")))
        end },
        { label = "Happiness", wide = true, get = function()
            if not HasPet() then return false end
            -- FrogLib.Unit: Forever's C_PetInfo.
            local happiness, damage = FrogLib.Unit.PetHappiness()
            if not happiness then return false end
            return HAPPINESS[happiness] or tostring(happiness), false,
                damage and string.format("deals %d%% damage", damage) or nil
        end, tip = function(tooltip)
            Line(tooltip, "A happy pet deals 125% damage, a content one 100% and an unhappy one 75%; unhappy for too "
                .. "long, it runs away. Feeding it food it likes keeps it happy.")
            local loyalty = FrogLib.Unit.PetLoyalty()
            if loyalty then Line(tooltip, " ") Line(tooltip, "Loyalty", loyalty) end
            local total, used = FrogLib.Unit.PetTraining()
            if total then Line(tooltip, "Training points", string.format("%d free of %d", total - used, total)) end
            local foods = FrogLib.Unit.PetFood()
            if foods then Line(tooltip, "Eats", table.concat(foods, ", ")) end
        end },
        { label = "Damage", get = function()
            if not HasPet() then return false end
            local low, high = UnitDamage("pet")
            local speed = Known((UnitAttackSpeed("pet")))
            return string.format("%.1f DPS", (Known(low) + Known(high)) / 2 / speed)
        end, tip = function(tooltip)
            local low, high = UnitDamage("pet")
            Line(tooltip, "Hits", string.format("%d-%d", Known(low), Known(high)))
            Line(tooltip, "Speed", string.format("%.2fs", Known((UnitAttackSpeed("pet")))))
        end },
        { label = "Attack Power", get = function()
            if not HasPet() then return false end
            local base, bonus, penalty = UnitAttackPower("pet")
            return Number(Known(base) + Known(bonus) + Known(penalty))
        end },
        { label = "Armor", get = function()
            if not HasPet() then return false end
            local _, effective = UnitArmor("pet")
            return Number(Known(effective))
        end },
        { label = "Experience", get = function()
            if not (HasPet() and GetPetExperience) then return false end
            local current, needed = GetPetExperience()
            if not (current and needed and needed > 0) then return false end
            return string.format("%d%%", current / needed * 100)
        end },
        { label = "Resist", wide = true, get = function()
            if not HasPet() then return false end
            local parts, any = {}, false
            for _, school in ipairs(SCHOOL_COLORS) do
                local _, total = UnitResistance("pet", school[1])
                total = Known(total)
                if total ~= 0 then any = true end
                parts[#parts + 1] = string.format("|cff%s%s|r %d", school[3], school[2], total)
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
    local ByName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    for _, id in ipairs(ids) do
        local name = C_Spell.GetSpellName(id)
        if name and ByName then
            local aura = ByName("player", name, "HELPFUL")
            if FrogLib.issecret(aura) then error("unreadable", 0) end
            if aura then return true end
        elseif HasBuff(id) then
            return true
        end
    end
    return false
end

local function GroupClasses()
    local classes = { [Stats.Class()] = true }
    local members = GetNumGroupMembers and GetNumGroupMembers() or 0
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, members do
        local _, class = UnitClass(prefix .. i)
        if class and not FrogLib.issecret(class) then classes[class] = true end
    end
    return classes
end

local function MissingBuffs()
    local missing = {}
    for class in pairs(GroupClasses()) do
        local buff = GROUP_BUFFS[class]
        if buff and not (buff[3] and not Stats.UsesMana()) and not HasBuffNamed(buff[1]) then
            missing[#missing + 1] = buff[2]
        end
    end
    local own = OWN_BUFFS[Stats.Class()]
    if own and KnowsRank(own[1]) > 0 and not HasBuffNamed(own[2]) then missing[#missing + 1] = own[3] end
    table.sort(missing)
    return missing
end

local function BagSpace()
    local free, total = 0, 0
    local Container = C_Container
    for bag = 0, 4 do
        local slots = Container and Container.GetContainerNumSlots and Container.GetContainerNumSlots(bag) or 0
        total = total + slots
        if slots > 0 then free = free + (Container.GetContainerNumFreeSlots(bag) or 0) end
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
        end, tip = function(tooltip)
            Line(tooltip, "Buffs the classes in your group (you included) can give, that you haven't got, and "
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
    for _, slot in ipairs(ENCHANT_SLOTS) do
        local id = GetInventoryItemID("player", slot[1])
        local link = id and GetInventoryItemLink("player", slot[1])
        if link and Enchantable(slot[1], id) then
            count = count + 1
            local enchant = link:match("item:%d+:(%d*)")
            if not enchant or enchant == "" or enchant == "0" then missing[#missing + 1] = slot[2] end
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
end, tip = function(tooltip)
    Line(tooltip, "Gear that could carry an enchant (or a scope, or an arcanum on the head and legs) but doesn't.")
end })

-- Professions and secondary skills, by the game's skill line IDs.
local PROFESSIONS = { 171, 164, 333, 202, 182, 165, 186, 393, 197, 185, 129, 356, 633 }

local function ProfessionCell(id)
    return { label = function()
        local ok, skill = pcall(C_SkillInfo.GetSkillLineInfoByID, id)
        return ok and type(skill) == "table" and skill.name or "?"
    end, wide = true, get = function()
        if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then return false end
        local ok, skill = pcall(C_SkillInfo.GetSkillLineInfoByID, id)
        if not ok or type(skill) ~= "table" or type(skill.rank) ~= "number" or skill.rank <= 0 then return false end
        local rank, maxRank = skill.rank + (skill.modifier or 0), skill.maxRank or 0
        local note
        if maxRank > 0 and maxRank < 300 and skill.rank >= maxRank - 25 then
            note = "near its cap: a trainer can raise it"
        end
        return string.format("%d / %d", rank, maxRank), false, note, maxRank > 0 and rank / maxRank or nil
    end }
end

local professions = { key = "professions", title = "Professions", colorKey = "Gear", cells = {} }
for _, id in ipairs(PROFESSIONS) do professions.cells[#professions.cells + 1] = ProfessionCell(id) end

------------------------------------------------------------------------------
-- The List tab: every stat the game's own sheet can show, one per line (FrogLib's StatList, the
-- same list FrogUI puts in the stats pane), with the game's own tooltips.
------------------------------------------------------------------------------

local LIST_COLORS = { "General", "Attributes", "Attack", "Attack", "Secondary Stats", "Defense", "Defense" }

local PET_LIST_COLORS = { "General", "Attributes", "Insights", "Defense" }

-- One section per category: each stat a whole row, read for `unit` ("player" or "pet").
local function ListSection(key, title, colorKey, entries, unit)
    local section = { key = key, title = title, colorKey = colorKey, cells = {} }
    if unit ~= "player" then section.show = function() return UnitExists(unit) and true or false end end
    for _, entry in ipairs(entries) do
        local last = {}
        section.cells[#section.cells + 1] = {
            wide = true,
            -- Read after get, which fills it in.
            label = function() return last.label end,
            get = function()
                if unit ~= "player" and not UnitExists(unit) then return false end
                local label, value, tips = FrogLib.StatList.Read(entry, unit)
                if label == nil then return false end
                label, value = Known(label), Known(value) -- hidden by the game: the last reading stays
                last.label = (label:gsub(":%s*$", ""))
                last.tips = tips
                return value
            end,
            -- The game's own tooltip lines (its first is the name and value, shown already).
            tip = function(tooltip)
                for index, tipLine in ipairs(last.tips or {}) do
                    if index > 1 and not FrogLib.issecret(tipLine) then Line(tooltip, tipLine) end
                end
            end,
        }
    end
    return { kind = "section", section = section }
end

-- Yours, then your pet's (while it's out), each category its own section.
local function ListBlocks()
    local StatList = FrogLib.StatList
    local blocks = {}
    for i, category in ipairs(StatList.CATEGORIES) do
        blocks[#blocks + 1] = ListSection("list" .. i, category[1], LIST_COLORS[i] or "General", category[2], "player")
    end
    for i, category in ipairs(StatList.PET_CATEGORIES or {}) do
        blocks[#blocks + 1] = ListSection("petlist" .. i, (PET or "Pet") .. ": " .. category[1],
            PET_LIST_COLORS[i] or "General", category[2], "pet")
    end
    return blocks
end

------------------------------------------------------------------------------
-- Spells: where they go, and how far a full mana bar gets you
------------------------------------------------------------------------------

-- Your spells against an enemy `over` levels up: resisted outright, crits (on what lands), hits.
local function SpellRow(over, label)
    local miss = Stats.SpellMiss(over)
    local crit = Known((Stats.BestSchool(GetSpellCritChance))) * (100 - miss) / 100
    local segments = { Segment(100 - miss - crit, COLORS.hit, "Hit"), Segment(crit, COLORS.crit, "Crit"),
        Segment(miss, COLORS.miss, "Resisted") }
    return { label = label, right = "lands " .. Percent(100 - miss), segs = segments }
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
            for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local bookItem = book.GetSpellBookItemInfo(slot, bank)
                if bookItem and bookItem.spellID and not bookItem.isPassive
                    and (not spellType or bookItem.itemType == spellType) then
                    for _, cost in ipairs(C_Spell.GetSpellPowerCost(bookItem.spellID) or {}) do
                        if cost.type == 0 and (cost.cost or 0) > 0 then
                            local known = found[bookItem.name]
                            if not known or known.cost < cost.cost then
                                local spell = C_Spell.GetSpellInfo(bookItem.spellID)
                                found[bookItem.name] = { name = bookItem.name, icon = bookItem.iconID, cost = cost.cost,
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
    table.sort(list, function(first, second) return first.cost > second.cost end)
    return list
end

local function SpellEntries()
    local maxMana = Known(UnitPowerMax("player", 0))
    local entries = {}
    for _, spell in ipairs(ManaSpells()) do
        local casts = math.floor(maxMana / spell.cost)
        entries[#entries + 1] = {
            icon = spell.icon, title = spell.name,
            right = casts == 1 and "1 cast" or string.format("%d casts", casts),
            lines = { { text = string.format("%d mana · %s", spell.cost,
                spell.cast > 0 and string.format("%.1fs cast", spell.cast) or "instant"), dim = true } },
        }
        if #entries == 8 then break end
    end
    return entries
end

local casterTiles = {
    damageTile,
    { caption = "SPELL CRIT", colorKey = "Secondary Stats", get = function()
        return Percent((Stats.BestSchool(GetSpellCritChance))), false, "crits 50% stronger"
    end },
    { caption = "MANA REGEN", colorKey = "Secondary Stats", get = function()
        local rate, wasMeasured = ManaRate()
        return OneDecimal(rate * 5), false, wasMeasured and "mp5, measured" or "mp5 resting"
    end },
}

-- The Main Hand row's tooltip, for the Swing tile that stands in for it.
local function CellTip(section, label)
    for _, cell in ipairs(section.cells) do
        if cell.label == label then return cell.tip end
    end
end

local meleeTiles = {
    { caption = "PAPER DPS", colorKey = "Attack", get = function()
        return string.format("%.1f", Stats.PaperDPS()), false, "on the sheet"
    end },
    { caption = "SWING", colorKey = "Attack", get = function()
        local low, high = UnitDamage("player")
        return string.format("%.2fs", Known((UnitAttackSpeed("player")))), false,
            string.format("%d-%d damage", math.floor(Known(low)), math.ceil(Known(high)))
    end, tip = CellTip(Section.melee, "Main Hand") },
    damageTile,
}

local dpsSource = { kind = "bars", key = "dpsSource", title = "Where your damage comes from", colorKey = "Attack", rows = function()
    local paper = Stats.PaperDPS()
    local attackPower = Stats.MeleeAP()
    local fromAP = attackPower / Stats.AP_PER_DPS
    local weapon = math.max(0, paper - fromAP)
    return { {
        segs = {
            { pct = weapon / paper * 100, color = COLORS.weapon, text = string.format("%.1f from the weapon", weapon) },
            { pct = fromAP / paper * 100, color = COLORS.ap, text = string.format("%.1f from %d attack power", fromAP, attackPower) },
        },
        cols = 2,
    } }
end }

local swingsGo = { kind = "bars", key = "swings", title = "Where your swings go", colorKey = "Attack", rows = function()
    return { SwingRow(0, SameLabel()), SwingRow(3, BossLabel()) }
end }

-- The ranged weapon's row (its label is Wand or Ranged), for the Shot tile that stands in for it.
local rangedWeapon = Section.ranged.cells[1]

local rangedTiles = {
    { caption = "PAPER DPS", colorKey = "Attack", get = function()
        return string.format("%.1f", Stats.RangedPaperDPS()), false, "on the sheet"
    end },
    { caption = "SHOT", colorKey = "Attack", get = function()
        local speed, low, high = UnitRangedDamage("player")
        return string.format("%.2fs", Known(speed)), false,
            string.format("%d-%d damage", math.floor(Known(low)), math.ceil(Known(high)))
    end, tip = rangedWeapon.tip },
    damageTile,
}

local shotsGo = { kind = "bars", key = "shots", title = "Where your shots go", colorKey = "Attack", rows = function()
    return { ShotRow(0, SameLabel()), ShotRow(3, BossLabel()) }
end }

local spellsGo = { kind = "bars", key = "spellsGo", title = "Where your spells go", colorKey = "Secondary Stats", rows = function()
    return { SpellRow(0, SameLabel()), SpellRow(3, BossLabel()) }
end }

local castsFromFull = { kind = "entries", key = "casts", title = "Casts from full mana", colorKey = "Secondary Stats",
    items = SpellEntries, empty = "No spells that cost mana yet." }

local roleSwitch = { kind = "role" }

-- Offense follows the switch: spells first as a caster, the ranged weapon first as ranged, the
-- melee weapon first otherwise.
local function OffenseBlocks()
    if Caster() then
        return {
            roleSwitch,
            { kind = "tiles", tiles = casterTiles },
            -- The tiles show spell power, spell crit and mana regen.
            { kind = "section", section = Section.spell, skip = { Damage = true, Crit = true, ["Mana Regen"] = true } },
            spellsGo,
            castsFromFull,
            { kind = "section", section = pet },
            { kind = "section", section = Section.melee },
        }
    end
    if Ranged() then
        return {
            roleSwitch,
            { kind = "tiles", tiles = rangedTiles },
            -- The Shot and Paper DPS tiles show the weapon's row.
            { kind = "section", section = Section.ranged, skip = { [rangedWeapon] = true } },
            shotsGo,
            { kind = "section", section = pet },
            { kind = "section", section = Section.melee },
            { kind = "section", section = Section.spell },
        }
    end
    local blocks = {
        { kind = "tiles", tiles = meleeTiles },
        -- The Swing and Paper DPS tiles show the main hand's line.
        { kind = "section", section = Section.melee, skip = { ["Main Hand"] = true } },
        { kind = "section", section = rage },
        { kind = "section", section = Section.ranged },
        { kind = "section", section = pet },
        { kind = "section", section = Section.spell },
        dpsSource,
        swingsGo,
    }
    if ns.Roles() then table.insert(blocks, 1, roleSwitch) end
    return blocks
end

------------------------------------------------------------------------------
-- The tabs
------------------------------------------------------------------------------

ns.Tabs = {
    {
        key = "overview", title = "Overview",
        blocks = {
            { kind = "pinned" },
            { kind = "tiles", tiles = { damageTile, ehpTile, powerTile } },
            { kind = "section", section = Section.attributes },
            { kind = "worth" },
            { kind = "section", section = ready },
            { kind = "section", section = Section.caps },
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
                        best = math.max(best, Known(total))
                    end
                    local health = Known(UnitHealthMax("player"))
                    if best == 0 then return Number(health), false, "no resistances yet" end
                    local average = math.min(0.75, 0.75 * best / (level * 5))
                    return Number(math.floor(health / (1 - average) + 0.5)), false,
                        string.format("best school %d%%", average * 100 + 0.5)
                end },
                { caption = "AVOID", colorKey = "Defense", get = function()
                    local incoming = Stats.IncomingTable(0)
                    return Percent(incoming.miss + incoming.dodge + incoming.parry), false, "of melee swings"
                end },
            } },
            { kind = "bars", key = "incoming", title = "When you're swung at", colorKey = "Defense", rows = function()
                return { IncomingRow(0, SameLabel()), IncomingRow(3, BossLabel()) }
            end },
            { kind = "section", section = tanking },
            { kind = "section", section = measured },
            { kind = "section", section = armorByLevel },
            { kind = "section", section = Section.defense },
        },
    },
    {
        key = "gear", title = "Gear",
        blocks = {
            { kind = "tiles", tiles = {
                { caption = "ITEM LEVEL", colorKey = "Gear", get = function()
                    local average, equipped = GetAverageItemLevel()
                    return string.format("%.1f", Known(equipped or average)), false, "equipped"
                end },
                { caption = "DURABILITY", colorKey = "Gear", get = function()
                    local average, worst = Stats.Durability()
                    if not average then return "-", false, "nothing to wear out" end
                    local text = string.format("%d%%", average * 100 + 0.5)
                    if worst < 0.25 then
                        text = "|cffff4040" .. text .. "|r"
                    elseif worst < 0.5 then
                        text = "|cffffd040" .. text .. "|r"
                    end
                    return text, false, worst < 0.995 and string.format("most worn %d%%", worst * 100 + 0.5) or "nothing worn"
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
                return Stats.GearSummary((Stats.GearTotals()))
            end },
            { kind = "section", section = supplies },
            { kind = "section", section = professions },
            { kind = "changes", key = "changes", title = "Since you logged in", colorKey = "Attributes", limit = 8 },
            { kind = "section", section = Section.general },
        },
    },
    {
        key = "list", title = "List",
        blocks = ListBlocks(),
    },
}

-- Every section a row can be pinned from, for finding pinned rows (Panel.lua) before their tab
-- has been opened.
function ns.PinSections()
    local sections, seen = {}, {}
    local function Add(section)
        if section and not seen[section] then
            seen[section] = true
            sections[#sections + 1] = section
        end
    end
    for _, tab in ipairs(ns.Tabs) do
        if type(tab.blocks) == "table" then
            for _, block in ipairs(tab.blocks) do
                if block.kind == "section" then Add(block.section) end
            end
        end
    end
    for _, section in ipairs({ Section.spell, Section.melee, rage, Section.ranged, pet }) do Add(section) end
    return sections
end
