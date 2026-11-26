local _, ns = ...

-- The tabs and what's on each: blocks the panel lays out top to bottom (tiles, a section of cells,
-- stacked bars, "what +10 gets you", chips, change cards, icon entries, the Tank / Melee / Ranged /
-- Caster / Healer switch). A tab's blocks can be a function, for tabs that change with the switch. Everything reads
-- through ns.Stats (Stats.lua), so secret values in combat keep the last reading.

local Stats, Section = ns.Stats, ns.SectionByKey
local Talents = ns.Talents -- what talents and buffs make a stat on an item worth
local Known, Number, Percent, OneDecimal, Line = Stats.Known, Stats.Number, Stats.Percent, Stats.OneDecimal, Stats.Line

-- Spells known, buffs on you, and your threat multiplier with its parts.
local KnowsRank, HasBuff, Threat = FrogLib.Tank.KnowsRank, FrogLib.Tank.HasBuff, FrogLib.Tank.Threat

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

-- As a healer: the switch's Healer (priests, druids, paladins and shamans), with mana.
local Healing = ns.Healing
local function Healer() return ns.WorthRole() == "healer" and Stats.UsesMana() and Healing.Heals() end
ns.Healer = Healer

-- As a tank: the switch's Tank (warriors, druids and paladins).
local TANKS = { WARRIOR = true, DRUID = true, PALADIN = true }
local function TankRole() return ns.WorthRole() == "tank" and TANKS[Stats.Class()] == true end
ns.TankRole = TankRole

-- What a boss three levels up's swings do: the share that misses or is dodged or parried, and blocked.
local function BossAvoid()
    local incoming = Stats.IncomingTable(3)
    return incoming.miss + incoming.dodge + incoming.parry, incoming.block, incoming
end

local damageTile = {
    caption = function()
        if TankRole() then return "AVOIDANCE" end
        if Healer() then return "HEALING" end
        return Caster() and "SPELL POWER" or "REAL DPS"
    end, colorKey = "Attack",
    get = function()
        if TankRole() then
            local avoid, block = BossAvoid()
            return Percent(avoid), false, block > 0 and string.format("+%s blocked, vs a boss", Percent(block))
                or "of a boss's swings"
        end
        if Healer() then
            return "+" .. Number(Healing.Bonus()), false, string.format("+%s spell damage · %s crit",
                Number(Stats.BestSchool(GetSpellBonusDamage)), Percent(Healing.Crit()))
        end
        if Caster() then
            -- Healing joins the line under it when +healing gear takes it past spell damage (one school's
            -- gear leaves healing below that school, which is no reason to show it).
            local damage = Stats.BestSchool(GetSpellBonusDamage)
            local healing = GetSpellBonusHealing and Known(GetSpellBonusHealing()) or damage
            local crit = Percent((Stats.BestSchool(GetSpellCritChance))) .. " crit"
            if healing > damage then crit = string.format("+%s healing · %s", Number(healing), crit) end
            return "+" .. Number(damage), false, crit
        end
        local paper, share, slot
        if Ranged() then
            paper, share, slot = Stats.RangedPaperDPS(), Stats.ShotTable(0).mult, INVSLOT_RANGED or 18
        else
            paper, share, slot = Stats.PaperDPS(), Stats.SwingTable(0).mult, INVSLOT_MAINHAND or 16
        end
        local note = string.format("%.1f on paper", paper)
        -- A weapon skill well short of your level's cap says why real DPS is so far under paper: past
        -- 10 points short, most swings glance (Forever's GetGlancingBlowChance: 100% at half the cap).
        local skill, _, name = Stats.WeaponSkill(slot)
        if skill and name and skill < UnitLevel("player") * Stats.SKILL_PER_LEVEL - 10 then
            note = string.format("%s · %s %d/%d", note, name, skill, UnitLevel("player") * Stats.SKILL_PER_LEVEL)
        end
        return string.format("%.1f", paper * share), false, note
    end,
    tip = function(tooltip)
        if TankRole() then
            Line(tooltip, "The share of a raid boss's swings (three levels up) that miss you or that you dodge or "
                .. "parry, with what you block under it. The Defense tab has the whole table.")
        elseif Healer() then
            Line(tooltip, "Bonus healing on your heals, with your spell damage and crit on heals under it. "
                .. "The Healing tab shows what each of your heals comes to.")
        elseif Caster() then
            Line(tooltip, "Bonus damage on your spells, with your bonus healing under it when that's higher. "
                .. "Switch to Melee to see your real DPS.")
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

-- Mana, unless another bar is in use (rage, energy: a druid in a form shows that one).
local function ShowsMana() return Stats.UsesMana() and Stats.DisplayPower() == 0 end

local powerTile = {
    caption = function()
        if ShowsMana() then return "MANA" end
        return string.upper(select(2, Stats.DisplayPower()))
    end, colorKey = "Secondary Stats",
    get = function()
        if ShowsMana() then
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
        if not ShowsMana() then return end
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

-- What 10 of a stat on an item add to the stat on you (more with Divine Strength, Kings and the
-- like), and "+11 Strength on you · " for the row's detail when that isn't 10.
local function TenOnYou(statIndex, name)
    local points = 10 * Talents.StatScale(statIndex)
    if math.abs(points - 10) < 0.05 then return points, "" end
    return points, string.format("+%s %s on you · ", OneDecimal(points), name)
end

-- " · +3 healing, +1 spell damage" (or " · +2 spell power") for `points` of a stat counted as spell
-- damage and healing by those shares (fractions); "" for none.
local function SpellText(damageShare, healShare, points)
    if damageShare * points < 0.5 and healShare * points >= 0.5 then
        return string.format(" · +%d healing", healShare * points + 0.5)
    elseif healShare * points < 0.5 and damageShare * points >= 0.5 then
        return string.format(" · +%d spell damage", damageShare * points + 0.5)
    elseif math.abs(healShare - damageShare) * points >= 0.5 then
        return string.format(" · +%d healing, +%d spell damage", healShare * points + 0.5, damageShare * points + 0.5)
    elseif damageShare * points >= 0.5 then
        return string.format(" · +%d spell power", damageShare * points + 0.5)
    end
    return ""
end

-- What `points` of a stat give when the first 20 give 1 each and the rest `perPoint` each.
local function PastBreak(points, perPoint, first)
    first = first or 20
    return math.min(first, points) + math.max(0, points - first) * perPoint
end

local function StaminaRow()
    local _, health = EHP()
    local perPoint = Stats.Call(UnitHPPerStamina, "player") or 10
    local stamina = StatValue(3)
    local points, onYou = TenOnYou(3, "Stamina")
    local first = STAMINA_BREAK or 20
    local gain = (PastBreak(stamina + points, perPoint, first) - PastBreak(stamina, perPoint, first)) * Talents.HealthScale()
    return { stat = "+10 Stamina", headline = string.format("+%d HP", gain), colorKey = "Defense",
        gain = gain / health, detail = onYou .. string.format("%d%% more effective health", gain / health * 100 + 0.5) }
end

-- +10 Intellect: mana and spell crit, and what talents make of it (spell power, armor). With
-- `DPSFromAP` (melee or, `ranged`, shots), Intellect's attack power (Mental Dexterity, Careful Aim)
-- leads as damage a second against `real`.
local function IntellectRow(DPSFromAP, real, ranged)
    local maxMana = Known(UnitPowerMax("player", 0))
    local intellect = StatValue(4)
    local points, onYou = TenOnYou(4, "Intellect")
    local perPoint, first = MANA_PER_INTELLECT or 15, INTELLECT_BREAK or 20
    local mana = (PastBreak(intellect + points, perPoint, first) - PastBreak(intellect, perPoint, first)) * Talents.ManaScale()
    local crit = Fraction(GetSpellCritChanceFromStat, 4, intellect + points) - Fraction(GetSpellCritChanceFromStat, 4, intellect)
    local armor = points * Talents.IntToArmor() -- Arcane Resilience
    local damageShare, healShare = Talents.IntToSpell()
    local rest = (crit >= 0.05 and string.format(" · +%.1f%% spell crit", crit) or "")
        .. SpellText(damageShare, healShare, points)
        .. (armor >= 0.5 and string.format(" · +%d armor", armor + 0.5) or "")
    local attackPower = 0
    if DPSFromAP then
        local meleeAP, rangedAP = Talents.IntAPChange(intellect, intellect + points)
        attackPower = ranged and rangedAP or meleeAP
    end
    if attackPower >= 0.5 and real > 0 then
        local dps = DPSFromAP(attackPower)
        return { stat = "+10 Intellect", headline = string.format("+%.2f DPS", dps), colorKey = "Attack",
            gain = dps / real, detail = onYou .. string.format("+%d attack power · +%d mana", attackPower + 0.5, mana) .. rest }
    end
    return { stat = "+10 Intellect", headline = string.format("+%d mana", mana), colorKey = "Secondary Stats",
        gain = mana / maxMana, detail = onYou .. string.format("%d%% more mana", mana / maxMana * 100 + 0.5) .. rest }
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
    local strengthPoints, strengthOnYou = TenOnYou(1, "Strength")
    local strengthAP = (Stats.StatAP(1, strength + strengthPoints) or 0) - (Stats.StatAP(1, strength) or 0)
    local strengthDPS = DPSFromAP(strengthAP)
    rows[#rows + 1] = { stat = "+10 Strength", headline = string.format("+%.1f DPS", strengthDPS), colorKey = "Attack",
        gain = strengthDPS / real, detail = strengthOnYou
            .. string.format("+%d attack power · %d%% more damage", strengthAP, strengthDPS / real * 100 + 0.5) }

    rows[#rows + 1] = StaminaRow()

    local agility = StatValue(2)
    local agilityPoints, agilityOnYou = TenOnYou(2, "Agility")
    local crit = Fraction(GetCritChanceFromStat, 2, agility + agilityPoints) - Fraction(GetCritChanceFromStat, 2, agility)
    local agilityAP = (Stats.StatAP(2, agility + agilityPoints) or 0) - (Stats.StatAP(2, agility) or 0)
    -- Crit only helps white hits up to the crit cap (what misses, dodges and glancing blows leave).
    local room = math.max(0, 100 - swings.miss - swings.dodge - swings.glance + swings.critPenalty
        - Known(GetCritChance()))
    local agilityDPS = paper * math.min(crit, room) / 100 + DPSFromAP(agilityAP)
    local dodge = (Stats.Call(GetDodgeChanceFromAttribute) or 0) * 100 / math.max(1, agility) * agilityPoints
    rows[#rows + 1] = { stat = "+10 Agility", headline = string.format("+%.2f DPS", agilityDPS), colorKey = "Attack",
        gain = agilityDPS / real, detail = agilityOnYou .. string.format("+%.1f%% crit · +%.1f%% dodge · +%d armor%s",
            crit, dodge, agilityPoints * 2, agilityAP > 0 and string.format(" · +%d AP", agilityAP) or "") }

    if Talents.IntToAP() > 0 and Known(UnitPowerMax("player", 0)) > 0 then
        rows[#rows + 1] = IntellectRow(DPSFromAP, real, false)
    end

    if swings.miss > 0 then
        local hitDPS = paper * math.min(1, swings.miss) / 100
        rows[#rows + 1] = { stat = "+1% Hit", headline = string.format("+%.2f DPS", hitDPS), colorKey = "Attack",
            gain = hitDPS / real, detail = "1 fewer miss in every 100 swings" }
    end
    return rows
end

-- A hunter's shots: Strength gives them no ranged attack power, so it isn't here.
local function RangedWorth()
    local rows = {}
    local paper = Stats.RangedPaperDPS()
    local shots = Stats.ShotTable(0)
    local real = paper * shots.mult

    local agility = StatValue(2)
    local points, onYou = TenOnYou(2, "Agility")
    local crit = Fraction(GetCritChanceFromStat, 2, agility + points) - Fraction(GetCritChanceFromStat, 2, agility)
    local agilityAP = Stats.StatRAP(2, agility + points) - Stats.StatRAP(2, agility)
    local agilityDPS = paper * crit / 100 + agilityAP / Stats.AP_PER_DPS * shots.mult
    rows[#rows + 1] = { stat = "+10 Agility", headline = string.format("+%.2f DPS", agilityDPS), colorKey = "Attack",
        gain = agilityDPS / real,
        detail = onYou .. string.format("+%d ranged attack power · +%.1f%% crit", agilityAP, crit) }

    rows[#rows + 1] = StaminaRow()
    rows[#rows + 1] = IntellectRow(function(attackPower) return attackPower / Stats.AP_PER_DPS * shots.mult end, real, true)

    if shots.miss > 0 then
        local hitDPS = paper * math.min(1, shots.miss) / 100
        rows[#rows + 1] = { stat = "+1% Hit", headline = string.format("+%.2f DPS", hitDPS), colorKey = "Attack",
            gain = hitDPS / real, detail = "1 fewer miss in every 100 shots" }
    end
    return rows
end

local SPIRIT_QUARTER = { PRIEST = true, MAGE = true }

-- +10 Spirit, or nil with no regen. As a healer, also what it adds while casting.
local function SpiritRow(healer)
    local regen = Known((GetManaRegen()))
    if regen <= 0 then return nil end
    -- Classic's rule: each point of Spirit adds 1/4 mana a tick (every 2 s) for priests and
    -- mages, 1/5 for the rest; the regen also has a fixed part, so the average overstates it.
    local perTick = SPIRIT_QUARTER[Stats.Class()] and 0.25 or 0.2
    local points, onYou = TenOnYou(5, "Spirit")
    local mp5 = points * perTick * 5 / 2
    -- Spiritual Guidance: a share of Spirit as spell damage and healing.
    local spiritDamage, spiritHeal = Talents.SpiritToSpell()
    local spell = SpellText(spiritDamage, spiritHeal, points)
    local kept = healer and Healing.SpiritKept() or 0 -- Meditation and the like
    local casting = kept * mp5 >= 0.05 and string.format(" · +%s while casting", OneDecimal(kept * mp5)) or ""
    return { stat = "+10 Spirit", headline = string.format("+%s mp5", OneDecimal(mp5)), colorKey = "Secondary Stats",
        gain = mp5 / (regen * 5), detail = onYou .. string.format("%d%% faster mana regen while not casting",
            mp5 / (regen * 5) * 100 + 0.5) .. casting .. spell }
end

local function CasterWorth()
    local rows = { IntellectRow() }
    rows[#rows + 1] = SpiritRow(false)
    rows[#rows + 1] = StaminaRow()

    rows[#rows + 1] = { stat = "+10 Spell Power", headline = "+10 per spell", colorKey = "Secondary Stats",
        detail = "damage and healing, scaled by each spell's cast time" }
    return rows
end

-- A tank's, against a raid boss: Stamina, defense, Agility, armor, Strength and block value. Avoidance
-- rows count as the share fewer swings that land; armor and health as effective health.
local function TankWorth()
    local rows = { StaminaRow() }
    local avoid, block, incoming = BossAvoid()
    local landing = math.max(1, 100 - avoid)
    local parries, blocks = incoming.parry > 0, Known(GetBlockChance()) > 0
    local level = UnitLevel("player")

    -- Defense: 0.04% a point off misses, dodges, parries and blocks each, and off crits.
    local each = 10 * 0.04
    local defenseAvoid = each * (2 + (parries and 1 or 0) + (blocks and 1 or 0))
    local defense, need = Stats.DefenseSkill(), FrogLib.Tank.CritCapNeed(3, level)
    local cap = ""
    if defense then
        cap = defense >= need and " · boss crits gone already" or string.format(" · %d more stops boss crits", need - defense)
    end
    local fewerCrits = (defense and defense < need) and each or 0 -- a crit is a second hit's worth
    rows[#rows + 1] = { stat = "+10 Defense", headline = string.format("+%s%% avoid", OneDecimal(defenseAvoid)),
        colorKey = "Defense", gain = (defenseAvoid + fewerCrits) / landing,
        detail = string.format("+%s each of miss, dodge%s%s · %s fewer crits%s", Percent(each),
            parries and ", parry" or "", blocks and ", block" or "", Percent(each), cap) }

    -- Agility: dodge and 2 armor a point.
    local ehpNow = Stats.ArmorReduction(Stats.ArmorNow(), 3)
    local function EHPGain(extraArmor)
        local after = Stats.ArmorReduction(Stats.ArmorNow() + extraArmor, 3)
        return (1 - ehpNow) / (1 - after) - 1
    end
    local agility = StatValue(2)
    local points, onYou = TenOnYou(2, "Agility")
    local dodge = (Stats.Call(GetDodgeChanceFromAttribute) or 0) * 100 / math.max(1, agility) * points
    local agilityArmor = EHPGain(points * 2)
    rows[#rows + 1] = { stat = "+10 Agility", headline = string.format("+%s%% dodge", OneDecimal(dodge)), colorKey = "Defense",
        gain = dodge / landing + agilityArmor, detail = onYou .. string.format("+%d armor · %s%% more effective health",
            points * 2 + 0.5, OneDecimal(agilityArmor * 100)) }

    -- Armor on an item (more with Toughness or in Bear Form).
    local armor = 100 * Talents.ItemArmorScale()
    local armorGain = EHPGain(armor)
    rows[#rows + 1] = { stat = "+100 Armor", headline = string.format("+%s%% EHP", OneDecimal(armorGain * 100)),
        colorKey = "Defense", gain = armorGain,
        detail = string.format("%s armor on you · a boss's hits lose %s instead of %s", Number(math.floor(armor + 0.5)),
            Percent(Stats.ArmorReduction(Stats.ArmorNow() + armor, 3) * 100), Percent(ehpNow * 100)) }

    -- Strength: attack power for threat, and block value with a shield (1 for every 20).
    local strength = StatValue(1)
    local strengthPoints, strengthOnYou = TenOnYou(1, "Strength")
    local attackPower = (Stats.StatAP(1, strength + strengthPoints) or 0) - (Stats.StatAP(1, strength) or 0)
    local blockValue = blocks and math.floor((strength + strengthPoints) / 20) - math.floor(strength / 20) or 0
    rows[#rows + 1] = { stat = "+10 Strength", headline = string.format("+%d AP", attackPower + 0.5), colorKey = "Attack",
        detail = strengthOnYou .. "more threat from every attack" .. (blockValue > 0 and string.format(" · +%d block value",
            blockValue) or "") }

    if blocks then
        rows[#rows + 1] = { stat = "+10 Block Value", headline = "+10 off each block", colorKey = "Defense",
            detail = string.format("%s of a boss's swings are blocked", Percent(block)) }
    end
    return rows
end

-- A healer's: bonus healing and crit on your biggest heal, Intellect, Spirit (and what it gives while
-- casting), mp5 (which keeps coming while you cast) and Stamina.
local function HealerWorth()
    local rows = {}
    local main = Healing.Main()
    if main then
        local gain = main.perBonus * 10
        rows[#rows + 1] = { stat = "+10 Healing", headline = string.format("+%d a heal", gain + 0.5), colorKey = "Secondary Stats",
            gain = gain / main.average, detail = string.format("on your %s: %d%% more · +%s a second", main.name,
                gain / main.average * 100 + 0.5, OneDecimal(gain / math.max(main.cast, 1.5))) }
        local crit = Healing.CritShare(main, 1)
        if crit >= 0.5 then
            rows[#rows + 1] = { stat = "+1% Crit", headline = string.format("+%d a heal", crit + 0.5), colorKey = "Secondary Stats",
                gain = crit / main.average, detail = string.format("on your %s: 1 more crit in every 100 heals, "
                    .. "which heal %d%% more", main.name, Talents.CritBonus() * 100 + 0.5) }
        end
    end
    rows[#rows + 1] = IntellectRow()
    rows[#rows + 1] = SpiritRow(true)
    local _, casting = Healing.Regen()
    if casting > 0 then
        rows[#rows + 1] = { stat = "+10 MP5", headline = "+10 mp5", colorKey = "Secondary Stats",
            gain = 10 / (casting * 5), detail = string.format("%d%% faster mana regen while casting · +%d mana in a "
                .. "5-minute fight", 10 / (casting * 5) * 100 + 0.5, 600) }
    else
        rows[#rows + 1] = { stat = "+10 MP5", headline = "+10 mp5", colorKey = "Secondary Stats",
            detail = "keeps coming while you cast: +600 mana in a 5-minute fight" }
    end
    rows[#rows + 1] = StaminaRow()
    return rows
end

-- Auto: mages, priests and warlocks cast, hunters shoot, warriors and rogues melee, a druid melees in
-- cat form, and a shaman or paladin casts once their best school's bonus passes half their AP. A
-- priest, druid, paladin or shaman who'd cast heals once their +healing passes their spell damage. A
-- warrior in Defensive Stance, a druid in Bear Form and a paladin with Righteous Fury tank.
local CAT_BEAR = { [1] = true, [5] = true, [8] = true }
local BEAR = { [5] = true, [8] = true }
local lastAuto

-- Caster, or Healer when +healing gear takes healing past spell damage.
local function CasterOrHealer()
    local healing = GetSpellBonusHealing and Known(GetSpellBonusHealing()) or 0
    return healing > Stats.BestSchool(GetSpellBonusDamage) and "healer" or "caster"
end

-- Tanking: Defensive Stance, Righteous Fury (Bear Form below).
local DEFENSIVE_STANCE, RIGHTEOUS_FURY = 71, { 25780, 407627, 407628 }

-- If you have Righteous Fury. The game hides auras in combat, and a hidden one reads as missing, so
-- that's asked first: then this can't tell (raises), and Auto keeps its last answer.
local function HasFury()
    local Hidden = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
    for _, spellID in ipairs(RIGHTEOUS_FURY) do
        if Hidden then
            local ok, hidden = pcall(Hidden, spellID)
            if ok and (FrogLib.issecret(hidden) or hidden == true) then error("unreadable", 0) end
        end
        if HasBuff(spellID) then return true end
    end
    return false
end

local function StanceSpell()
    local form = GetShapeshiftForm and GetShapeshiftForm() or 0
    if form == 0 or not GetShapeshiftFormInfo then return nil end
    return select(4, GetShapeshiftFormInfo(form))
end

local function AutoRole()
    local class = Stats.Class()
    if class == "WARRIOR" then return StanceSpell() == DEFENSIVE_STANCE and "tank" or "melee" end
    if class == "PALADIN" and HasFury() then return "tank" end
    if class == "PRIEST" then return CasterOrHealer() end
    if CASTERS[class] then return "caster" end
    if class == "HUNTER" then return Stats.HasRangedWeapon() and "ranged" or "melee" end
    if class == "DRUID" then
        local id = GetShapeshiftFormID and GetShapeshiftFormID()
        if id == nil and GetShapeshiftFormID then return CasterOrHealer() end
        if id ~= nil then
            id = Known(id)
            if BEAR[id] then return "tank" end
            return CAT_BEAR[id] and "melee" or CasterOrHealer()
        end
        if Stats.DisplayPower() == 1 then return "tank" end
        return (GetShapeshiftForm() or 0) == 0 and CasterOrHealer() or "melee"
    end
    if class == "SHAMAN" or class == "PALADIN" then
        -- Spell damage or +healing, whichever is bigger: a healer casts too.
        local healing = GetSpellBonusHealing and Known(GetSpellBonusHealing()) or 0
        local spellPower = math.max(Stats.BestSchool(GetSpellBonusDamage), healing)
        return spellPower > Stats.MeleeAP() / 2 and CasterOrHealer() or "melee"
    end
    return "melee"
end

-- The switch's choices: Tank for warriors, druids and paladins, Ranged for hunters, Caster for anyone
-- else with mana, Healer too for the classes that heal (a priest has no use for Melee), none for rogues.
local HUNTER_ROLES, CASTER_ROLES = { "auto", "melee", "ranged" }, { "auto", "melee", "caster" }
local PRIEST_ROLES, HYBRID_ROLES = { "auto", "caster", "healer" }, { "auto", "melee", "caster", "healer" }
local WARRIOR_ROLES, TANK_HYBRID_ROLES = { "auto", "tank", "melee" }, { "auto", "tank", "melee", "caster", "healer" }

function ns.Roles()
    local class = Stats.Class()
    if class == "HUNTER" then return HUNTER_ROLES end
    if class == "WARRIOR" then return WARRIOR_ROLES end
    if class == "DRUID" or class == "PALADIN" then return TANK_HYBRID_ROLES end
    if not Stats.UsesMana() then return nil end
    if class == "PRIEST" then return PRIEST_ROLES end
    if Healing.Heals() then return HYBRID_ROLES end
    return CASTER_ROLES
end

-- What's picked on the switch: one of your choices (kept per class, so your characters of a class
-- share it; before 0.7.0 one choice for everyone, which a class without its own still goes by), else Auto.
function ns.RoleChoice()
    local picked = ns.db.roles and ns.db.roles[Stats.Class()] or ns.db.role
    for _, role in ipairs(ns.Roles() or {}) do
        if role ~= "auto" and role == picked then return role end
    end
    return "auto"
end

function ns.SetRole(role)
    ns.db.roles = ns.db.roles or {}
    ns.db.roles[Stats.Class()] = role
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
    if TankRole() then return TankWorth() end
    if Healer() then return HealerWorth() end
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

-- One decimal on a bar's legend ("Hit 61.7%"): the tooltip-grade precision is noise there.
local function Segment(share, color, name)
    local text = string.format("%.1f", Known(share)):gsub("%.0$", "")
    return { pct = share, color = color, text = string.format("%s %s%%", name, text) }
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
        pinKey = "armorLevels:" .. over, wide = true,
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
    if class == "WARRIOR" and KnowsRank({ 2565 }) > 0 then return "Shield Block", 75 end
    if class == "PALADIN" and KnowsRank({ 20925, 20927, 20928 }) > 0 then return "Holy Shield", 30 end
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
            local need = FrogLib.Tank.CritCapNeed(3, level)
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
                    tostring(FrogLib.Tank.CritCapNeed(over, level)))
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
            local low, high, offLow, offHigh = UnitDamage("player")
            local average = (Known(low) + Known(high)) / 2
            local perHit = 7.5 * average / RageConversion()
            local speed, offSpeed = UnitAttackSpeed("player")
            speed = Known(speed)
            local swings = Stats.SwingTable(0)
            -- Misses and dodges give none; crits twice the damage, glancing blows less.
            local perMinute = perHit * swings.mult * 60 / speed
            if offSpeed then
                -- The off hand's own (already halved) damage makes rage the same way.
                local offPerHit = 7.5 * (Known(offLow) + Known(offHigh)) / 2 / RageConversion()
                perMinute = perMinute + offPerHit * swings.mult * 60 / Known(offSpeed)
            end
            return string.format("%.1f rage", perHit), false,
                string.format("crits %.1f · about %d a minute from your swings", perHit * 2, perMinute + 0.5)
        end, tip = function(tooltip)
            Line(tooltip, "Rage from your main hand's white hits against an enemy of your level: 7.5 x the "
                .. "damage, divided by your level's rage conversion. Misses and dodges give none. The rage "
                .. "a minute counts both hands when you dual wield.")
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
-- Threat: your multiplier from stance or form and talents (Forever's numbers: FrogLib.Tank.Threat)
------------------------------------------------------------------------------

-- Spells known, buffs on you, and your threat multiplier with its parts: FrogLib.Tank.
-- KnowsRank, HasBuff, Threat: FrogLib.Tank (at the top of the file).

local function ThreatCell()
    return { label = "Threat", wide = true, get = function()
        local multiplier, parts = Threat()
        if #parts == 0 then return false end
        local names = {}
        for _, part in ipairs(parts) do names[#names + 1] = part[1] end
        return string.format("x%.2f", multiplier), false, table.concat(names, ", ")
    end, tip = function(tooltip)
        local multiplier, parts, holy = Threat()
        Line(tooltip, "How much threat what you do makes, against the same damage or healing with nothing changing it:")
        for _, part in ipairs(parts) do Line(tooltip, part[1], string.format("x%.2f", part[2])) end
        Line(tooltip, "Together", string.format("x%.2f", multiplier))
        if holy then Line(tooltip, "Holy spells and attacks", string.format("x%.2f", holy)) end
        Line(tooltip, " ")
        Line(tooltip, "|cff8c8c8cForever's own numbers. Abilities with extra threat of their own (Sunder Armor, "
            .. "Revenge, Maul) are multiplied too.|r")
    end }
end

table.insert(tanking.cells, 1, ThreatCell())
-- Everyone else sees it with the general stats when something's changing it (rogues).
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
            local summary = ns.Incoming:Summary()
            if summary.unsized > 0 and not summary.averageHit then
                Line(tooltip, "The game doesn't tell add-ons how hard each hit was, so there's no average hit.")
            end
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

local SCHOOL_COLORS = ns.RESISTS -- Stats.lua

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
            if offSpeed and not ns.Ranged() then
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
        { label = function() return UnitName("pet") or "Pet" end, pinKey = "pet:name", wide = true, get = function()
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
        if slots > 0 then
            local freeSlots, bagType = Container.GetContainerNumFreeSlots(bag)
            if (bagType or 0) == 0 then
                free = free + (freeSlots or 0)
            else
                total = total - slots
            end
        end
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
    for index, entry in ipairs(entries) do
        local last = {}
        section.cells[#section.cells + 1] = {
            wide = true,
            pinKey = key .. ":" .. index, -- its name is read from the game, so pinned by place
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
    local _, offSpeed = UnitAttackSpeed("player")
    local fromAP = attackPower / Stats.AP_PER_DPS * (offSpeed and 1.5 or 1)
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

------------------------------------------------------------------------------
-- Healing: as a healer, the Offense tab becomes the Healing tab
------------------------------------------------------------------------------

local function Mp5(perSecond) return OneDecimal(perSecond * 5) end

local function GearMp5()
    local gear = Stats.GearTotals()
    return (gear.ITEM_MOD_MANA_REGENERATION_SHORT or 0) + (gear.ITEM_MOD_POWER_REGEN0_SHORT or 0)
end

local healerTiles = {
    damageTile,
    { caption = "HEAL CRIT", colorKey = "Secondary Stats", get = function()
        return Percent(Healing.Crit()), false, string.format("crits heal %d%% more", Talents.CritBonus() * 100 + 0.5)
    end, tip = function(tooltip)
        Line(tooltip, "The chance your heals crit (heals over time don't). Your heal school's spell crit, plus "
            .. "talents that add crit to heals (Tidal Mastery, Holy Specialization); Holy Power makes crits bigger.")
    end },
    { caption = "WHILE CASTING", colorKey = "Secondary Stats", get = function()
        local resting, casting, kept = Healing.Regen()
        return Mp5(casting), false, string.format("mp5 · %d%% of %s resting", kept * 100 + 0.5, Mp5(resting))
    end, tip = function(tooltip)
        Line(tooltip, "The mana that keeps coming while you cast (within 5 seconds of your last spell): mp5 from gear "
            .. "and buffs, and Spirit's share that talents let you keep. Resting regen starts 5 seconds after your last cast.")
    end },
}

local healing = {
    key = "healing", title = "Healing", colorKey = "Secondary Stats",
    show = function() return Healing.Heals() and Stats.UsesMana() end,
    cells = {
        { label = "Bonus Healing", get = function()
            local bonus = Healing.Bonus()
            return "+" .. Number(bonus), bonus == 0
        end },
        { label = "Heal Crit", get = function() return Percent(Healing.Crit()) end },
        { label = "Mana", get = function() return Number(UnitPowerMax("player", 0)) end },
        { label = "MP5 from Gear", get = function()
            local mp5 = GearMp5()
            return "+" .. Number(mp5), mp5 == 0
        end, tip = function(tooltip)
            Line(tooltip, "Mana every 5 seconds from your items, which keeps coming while you cast. Enchants "
                .. "and buffs (Blessing of Wisdom, Mana Spring) aren't included.")
        end },
        { label = "Regen", wide = true, get = function()
            local resting, casting, kept = Healing.Regen()
            return string.format("%s mp5 resting · %s while casting (%d%%)", Mp5(resting), Mp5(casting), kept * 100 + 0.5)
        end },
        { label = "Talents", wide = true, get = function()
            local scale, periodic = Talents.HealScale(false)
            local instant = Talents.HealScale(true) / scale
            local parts = {}
            if scale > 1.0005 then parts[#parts + 1] = string.format("+%s%% healing", OneDecimal((scale - 1) * 100)) end
            if periodic > 1.0005 then parts[#parts + 1] = string.format("+%s%% over time", OneDecimal((periodic - 1) * 100)) end
            if instant > 1.0005 then parts[#parts + 1] = string.format("+%s%% instant", OneDecimal((instant - 1) * 100)) end
            if #parts == 0 then return false end
            return table.concat(parts, " · ")
        end, tip = function(tooltip)
            Line(tooltip, "What your talents add to all your heals (Gift of Nature, Purification, Spiritual Healing, "
                .. "Genesis, Twin Disciplines). Your heals below count them, and the ones for a single heal (Healing "
                .. "Light, Improved Renew, Healing Way); the game's own spell tooltips don't.")
        end },
    },
}
Section.healing = healing

local function Duration(seconds)
    if seconds >= 60 then return string.format("%dm %02ds", seconds / 60, seconds % 60) end
    return string.format("%ds", seconds + 0.5)
end

local PARTY = 5

-- Each heal: what it heals, and how fast and how cheaply. A heal over time's speed is its healing a
-- second while it lasts; anything else's, per second of casting (instants take the 1.5 s global
-- cooldown). A party heal's numbers are for each one it reaches, with the whole party's after.
local function HealEntries()
    local entries = {}
    for _, heal in ipairs(Healing.List()) do
        local cast = heal.cast > 0 and string.format("%.1fs cast", heal.cast) or "instant"
        local overTime = heal.seconds and heal.seconds > 0 and heal.overTime >= heal.average * 0.99
        if heal.seconds and heal.overTime > 0 then cast = cast .. string.format(", over %ds", heal.seconds) end
        local speed = overTime and string.format("%s a second for %ds", Number(math.floor(heal.average / heal.seconds + 0.5)),
            heal.seconds) or string.format("%s a second cast", Number(math.floor(heal.perSecond + 0.5)))
        local each = heal.group and " each" or ""
        local lines = {
            { text = string.format("%s%s · %d mana", heal.rank and heal.rank ~= "" and (heal.rank .. " · ") or "", cast,
                heal.cost), dim = true },
            { text = speed .. each .. (heal.perMana and string.format(" · %.2f per mana%s", heal.perMana, each) or "") },
        }
        if heal.casts then
            lines[#lines + 1] = { text = string.format("%d casts from full · %s", heal.casts,
                heal.dry and ("dry in " .. Duration(heal.dry) .. " back to back") or "never runs dry"), dim = true }
        end
        if heal.jumps then lines[#lines + 1] = { text = "the first target's: it jumps on to others for less", dim = true } end
        if heal.group then
            lines[#lines + 1] = { text = string.format("heals each one in your party: %s a cast on a full party of %d",
                Number(math.floor(heal.average * PARTY + 0.5)), PARTY), dim = true }
        end
        if heal.cheaper then
            lines[#lines + 1] = { text = string.format("%s heals more per mana: %.2f (%s a heal)", heal.cheaper.rank,
                heal.cheaper.perMana, Number(math.floor(heal.cheaper.average + 0.5))), dim = true }
        end
        entries[#entries + 1] = { icon = heal.icon, title = heal.name,
            right = Number(math.floor(heal.average + 0.5)), lines = lines }
    end
    return entries
end

local yourHeals = { kind = "entries", key = "heals", title = "Your heals", colorKey = "Secondary Stats",
    items = HealEntries, empty = Healing.Readable() and "No heals learned yet."
        or "Your heals are read from the game's English tooltips, so this client's can't be shown." }

local roleSwitch = { kind = "role" }

-- Your pet: its health, damage and happiness as tiles under the "Pet" header, the rest of its rows
-- under them (the rows the tiles show are skipped).
local petCells = pet.cells
local petTiles = { kind = "tiles", key = "pet", title = "Pet", colorKey = "Attack", tiles = {
    { caption = function() return string.upper(UnitName("pet") or "Pet") end, colorKey = "Defense", get = function()
        if not HasPet() then return false end
        return Number(UnitHealthMax("pet")), false, string.format("health · level %d", Known(UnitLevel("pet")))
    end },
    { caption = "PET DPS", colorKey = "Attack", get = function()
        if not HasPet() then return false end
        local low, high = UnitDamage("pet")
        local speed = Known((UnitAttackSpeed("pet")))
        return string.format("%.1f", (Known(low) + Known(high)) / 2 / speed), false,
            string.format("%d-%d every %.1fs", Known(low), Known(high), speed)
    end, tip = petCells[3].tip },
    { caption = "HAPPINESS", colorKey = "Insights", get = function()
        if not HasPet() then return false end
        local happiness, damage = FrogLib.Unit.PetHappiness()
        if not happiness then return false end
        return HAPPINESS[happiness] or tostring(happiness), false, damage and string.format("deals %d%% damage", damage) or nil
    end, tip = petCells[2].tip },
} }
local petRows = { kind = "section", section = pet, noHeader = true,
    skip = { [petCells[1]] = true, [petCells[2]] = true, [petCells[3]] = true } }

-- Offense follows the switch: spells first as a caster, the ranged weapon first as ranged, the
-- melee weapon first otherwise. Each leads with its own numbers, then its caps and where the
-- damage goes; the other kinds of attack come after, for reference.
local caps = { kind = "section", section = Section.caps }

-- The Caps block's Hit Chance says more than the plain Hit row, so the row steps aside for it
-- (unless Caps is turned off).
local function CapsSkip(skip)
    if ns.db.sections.caps ~= false then skip.Hit = true end
    return skip
end

local function OffenseBlocks()
    if Healer() then
        return {
            roleSwitch,
            { kind = "tiles", tiles = healerTiles },
            -- The tiles show bonus healing, crit on heals and regen while casting.
            { kind = "section", section = healing, skip = { ["Bonus Healing"] = true, ["Heal Crit"] = true } },
            yourHeals,
            { kind = "section", section = Section.spell, skip = { Healing = true, ["Mana Regen"] = true } },
            { kind = "section", section = Section.ranged },
            { kind = "section", section = Section.melee },
        }
    end
    if Caster() then
        return {
            roleSwitch,
            { kind = "tiles", tiles = casterTiles },
            -- The tiles show spell power, spell crit and mana regen.
            { kind = "section", section = Section.spell, skip = { Damage = true, Crit = true, ["Mana Regen"] = true } },
            spellsGo,
            castsFromFull,
            { kind = "section", section = Section.ranged },
            petTiles, petRows,
            { kind = "section", section = Section.melee },
        }
    end
    if Ranged() then
        return {
            roleSwitch,
            { kind = "tiles", tiles = rangedTiles },
            -- The Shot and Paper DPS tiles show the weapon's row.
            { kind = "section", section = Section.ranged, skip = CapsSkip({ [rangedWeapon] = true }) },
            caps,
            shotsGo,
            petTiles, petRows,
            { kind = "section", section = Section.melee },
            { kind = "section", section = Section.spell },
        }
    end
    return {
        roleSwitch,
        { kind = "tiles", tiles = meleeTiles },
        -- The Swing and Paper DPS tiles show the main hand's line.
        { kind = "section", section = Section.melee, skip = CapsSkip({ ["Main Hand"] = true }) },
        caps,
        swingsGo,
        dpsSource,
        { kind = "section", section = rage },
        { kind = "section", section = Section.ranged },
        { kind = "section", section = Section.spell },
        petTiles, petRows,
    }
end

------------------------------------------------------------------------------
-- Weakest pieces: your lowest item level gear (and empty slots) first, where an upgrade does most
------------------------------------------------------------------------------

local UPGRADE_SLOTS = {
    { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulders" }, { 15, "Back" }, { 5, "Chest" }, { 9, "Wrist" },
    { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" }, { 11, "Ring" }, { 12, "Ring" },
    { 13, "Trinket" }, { 14, "Trinket" }, { 16, "Main hand" }, { 17, "Off hand" }, { 18, "Ranged" },
}
local SLOT_NAMES = { [1] = "HeadSlot", [2] = "NeckSlot", [3] = "ShoulderSlot", [15] = "BackSlot", [5] = "ChestSlot",
    [9] = "WristSlot", [10] = "HandsSlot", [6] = "WaistSlot", [7] = "LegsSlot", [8] = "FeetSlot", [11] = "Finger0Slot",
    [12] = "Finger1Slot", [13] = "Trinket0Slot", [14] = "Trinket1Slot", [16] = "MainHandSlot",
    [17] = "SecondaryHandSlot", [18] = "RangedSlot" }
local QUALITY_NAMES = { [0] = "grey", [1] = "white", [2] = "green", [3] = "blue", [4] = "purple", [5] = "orange" }

local function TwoHanded()
    local link = GetInventoryItemLink("player", INVSLOT_MAINHAND or 16)
    return link and select(4, C_Item.GetItemInfoInstant(link)) == "INVTYPE_2HWEAPON"
end

-- One card for every empty slot, then your four lowest item level pieces.
local function WeakestEntries()
    local pieces, empty = {}, {}
    local emptyIcon
    local twoHand = TwoHanded()
    for _, slot in ipairs(UPGRADE_SLOTS) do
        local id = slot[1]
        if not (id == 17 and twoHand) then
            local link = GetInventoryItemLink("player", id)
            if link then
                local name, _, quality, baseLevel = C_Item.GetItemInfo(link)
                local itemLevel = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link) or baseLevel
                if name and itemLevel then
                    pieces[#pieces + 1] = { slot = slot[2], link = link, name = name, quality = quality or 1,
                        level = itemLevel, icon = GetInventoryItemTexture("player", id) }
                end
            else
                empty[#empty + 1] = slot[2]
                if not emptyIcon then emptyIcon = select(2, GetInventorySlotInfo(SLOT_NAMES[id])) end
            end
        end
    end
    -- By item level, then by quality.
    table.sort(pieces, function(first, second)
        if first.level ~= second.level then return first.level < second.level end
        return (first.quality or 0) < (second.quality or 0)
    end)
    local entries = {}
    if #empty > 0 then
        entries[1] = { icon = emptyIcon, title = #empty == 1 and "1 empty slot" or (#empty .. " empty slots"),
            color = { 1, 0.82, 0 }, right = "anything helps", lines = { { text = table.concat(empty, ", "), dim = true } } }
    end
    for i = 1, math.min(4, #pieces) do
        local piece = pieces[i]
        local color
        if C_Item.GetItemQualityColor then
            local ok, r, g, b = pcall(C_Item.GetItemQualityColor, piece.quality)
            if ok and r then color = { r, g, b } end
        end
        entries[#entries + 1] = { icon = piece.icon, title = piece.name, color = color,
            right = string.format("item level %d", piece.level),
            lines = { { text = string.format("%s · %s", piece.slot, QUALITY_NAMES[piece.quality] or ""), dim = true } } }
    end
    return entries
end

local weakest = { kind = "entries", key = "weakest", title = "Weakest pieces", colorKey = "Gear",
    items = function()
        if ns.db.sections.weakest == false then return {} end
        return WeakestEntries()
    end, empty = "Nothing to show.", hideEmpty = true }

------------------------------------------------------------------------------
-- Over time: real DPS (or ranged DPS, or spell power, by the switch) and effective health from
-- the history Tracker.lua keeps
------------------------------------------------------------------------------

local function HistorySeries()
    if ns.db.sections.history == false then return {} end
    local points = ns.Tracker.History()
    if #points < 2 then return {} end
    local key, label, format
    if Caster() then
        key, label, format = "sp", "Spell power", function(value) return value and Number(math.floor(value)) or "-" end
    elseif Ranged() then
        key, label, format = "rdps", "Ranged DPS", function(value) return value and string.format("%.1f", value) or "-" end
    else
        key, label, format = "dps", "Real DPS", function(value) return value and string.format("%.1f", value) or "-" end
    end
    local series = {}
    local function Add(seriesKey, seriesLabel, colorKey, Format)
        local values = {}
        for _, point in ipairs(points) do
            if point[seriesKey] then values[#values + 1] = point[seriesKey] end
        end
        if #values >= 2 then
            series[#series + 1] = { label = seriesLabel, colorKey = colorKey, values = values, format = Format }
        end
    end
    Add(key, label, Caster() and "Secondary Stats" or "Attack", format)
    Add("ehp", "Effective health", "Defense", function(value) return value and Number(math.floor(value + 0.5)) or "-" end)
    return series
end

local history = { kind = "graph", key = "history", title = "Over time", colorKey = "Attributes",
    series = HistorySeries, empty = "Builds up as your gear and level change: a point each time your damage or health moves.",
    foot = function()
        local points = ns.Tracker.History()
        if #points < 2 then return nil end
        local first = points[1]
        return string.format("Since level %d, %s: %d changes.", first.lv or 0,
            date("%d %b %Y", first.t or time()), #points)
    end }

------------------------------------------------------------------------------
-- The tabs
------------------------------------------------------------------------------

ns.Tabs = {
    {
        key = "overview", title = "Overview",
        blocks = {
            roleSwitch,
            { kind = "pinned" },
            { kind = "tiles", tiles = { damageTile, ehpTile, powerTile } },
            { kind = "section", section = Section.attributes },
            { kind = "worth" },
            { kind = "section", section = ready },
            -- Its rage or energy and energy regen are on the tile above already.
            { kind = "section", section = Section.general,
              skip = { [Section.general.cells[1]] = true, [Section.general.cells[2]] = true } },
            { kind = "changes", key = "lastChange", title = "Last change", colorKey = "Attributes", limit = 1, hideEmpty = true },
        },
    },
    {
        key = "offense", title = function() return Healer() and "Healing" or "Offense" end,
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
                    local average = AverageResist(best, level)
                    return Number(math.floor(health / (1 - average) + 0.5)), false,
                        string.format("best school %d%%", average * 100 + 0.5)
                end },
                { caption = "AVOID", colorKey = "Defense", get = function()
                    local incoming = Stats.IncomingTable(0)
                    return Percent(incoming.miss + incoming.dodge + incoming.parry), false, "of melee swings"
                end },
            } },
            { kind = "section", section = Section.defense },
            { kind = "bars", key = "incoming", title = "When you're swung at", colorKey = "Defense", rows = function()
                return { IncomingRow(0, SameLabel()), IncomingRow(3, BossLabel()) }
            end },
            { kind = "section", section = tanking },
            { kind = "section", section = armorByLevel },
            { kind = "section", section = measured },
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
            weakest,
            { kind = "section", section = supplies },
            { kind = "changes", key = "changes", title = "Since you logged in", colorKey = "Attributes", limit = 8 },
            history,
            { kind = "section", section = professions },
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
    for _, section in ipairs({ Section.spell, Section.melee, Section.caps, rage, Section.ranged, pet, healing }) do Add(section) end
    return sections
end
