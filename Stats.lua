local _, ns = ...

-- What the panel shows: sections of cells, each a label and a getter. Combat values can be secret on
-- this client, so getters read numbers through Known(), which raises on a secret, and the panel runs
-- every getter in pcall: a cell that can't be read keeps its last readable text (dimmed).
-- Cell = { label, get(), tip(tooltip), wide }; see Panel.lua for what get() may return.

local issecret = FrogLib.issecret
local Tank = FrogLib.Tank -- the combat maths, shared with other add-ons

local function Known(value)
    if issecret(value) or value == nil then error("unreadable", 0) end
    return value
end
ns.Known = Known

local GREEN, RED, GREY, WHITE = "|cff40ff40", "|cffff4040", "|cff8c8c8c", "|cffffffff"

-- 5.43% / 5% (no trailing zeros).
local function Percent(value)
    local text = string.format("%.2f", Known(value)):gsub("0+$", ""):gsub("%.$", "")
    return text .. "%"
end

local function Number(value)
    value = Known(value)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)
end

-- 37.5 / 37 (one decimal, only when there is one).
local function OneDecimal(value)
    return (string.format("%.1f", Known(value)):gsub("%.0$", ""))
end

-- A value tinted the way Blizzard tints buffed (green) and debuffed (red) stats.
local function Tinted(text, bonus, penalty)
    if penalty and penalty < 0 then return RED .. text .. "|r" end
    if bonus and bonus > 0 then return GREEN .. text .. "|r" end
    return text
end

local function Line(tooltip, left, right)
    if right then
        tooltip:AddDoubleLine(left, right, 1, 0.82, 0, 1, 1, 1)
    else
        tooltip:AddLine(left, 1, 1, 1, true)
    end
end

------------------------------------------------------------------------------
-- General
------------------------------------------------------------------------------

local POWER_LABEL = { [0] = MANA or "Mana", [1] = RAGE or "Rage", [3] = ENERGY or "Energy" }

local function DisplayPower()
    local powerType, token = UnitPowerType("player")
    return Known(powerType), (token and _G[token]) or POWER_LABEL[powerType] or token or "Power"
end

-- Your gear's durability: the share left of all of it, and the most worn piece's share.
local function Durability()
    local now, full, worst = 0, 0, nil
    for slot = 1, 19 do
        local slotNow, slotFull = GetInventoryItemDurability(slot)
        if slotNow and slotFull and slotFull > 0 then
            now, full = now + slotNow, full + slotFull
            local share = slotNow / slotFull
            if not worst or share < worst then worst = share end
        end
    end
    if full == 0 then return nil end
    return now / full, worst
end

------------------------------------------------------------------------------
-- Gear
------------------------------------------------------------------------------

-- Item stats as C_Item.GetItemStats names them, with short labels, in display order. Enchants
-- aren't in these (the game reports an item's own stats only).
local GEAR_STATS = {
    { "ITEM_MOD_STRENGTH_SHORT", "Str" }, { "ITEM_MOD_AGILITY_SHORT", "Agi" },
    { "ITEM_MOD_STAMINA_SHORT", "Sta" }, { "ITEM_MOD_INTELLECT_SHORT", "Int" },
    { "ITEM_MOD_SPIRIT_SHORT", "Spi" }, { "ITEM_MOD_ATTACK_POWER_SHORT", "AP" },
    { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", "RAP" }, { "ITEM_MOD_SPELL_POWER_SHORT", "SP" },
    { "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "Spell Dmg" }, { "ITEM_MOD_SPELL_HEALING_DONE_SHORT", "Healing" },
    { "ITEM_MOD_CRIT_RATING_SHORT", "Crit" }, { "ITEM_MOD_HIT_RATING_SHORT", "Hit" },
    { "ITEM_MOD_MANA_REGENERATION_SHORT", "MP5" }, { "ITEM_MOD_POWER_REGEN0_SHORT", "MP5" },
    { "ITEM_MOD_HEALTH_REGEN_SHORT", "HP5" }, { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", "Def" },
    { "ITEM_MOD_DODGE_RATING_SHORT", "Dodge" }, { "ITEM_MOD_PARRY_RATING_SHORT", "Parry" },
    { "ITEM_MOD_BLOCK_RATING_SHORT", "Block" }, { "RESISTANCE0_NAME", "Armor" },
}

local function GearTotals()
    local totals, items = {}, 0
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            items = items + 1
            local stats = C_Item.GetItemStats(link)
            for stat, amount in pairs(stats or {}) do
                if type(amount) == "number" then totals[stat] = (totals[stat] or 0) + amount end
            end
        end
    end
    return totals, items
end

-- "+1 Str  +2 Agi  +10 SP  258 Armor", in GEAR_STATS order, with like labels added together.
local function GearSummary(totals)
    local sums, order = {}, {}
    for _, stat in ipairs(GEAR_STATS) do
        local amount = totals[stat[1]]
        if amount and amount ~= 0 then
            if not sums[stat[2]] then order[#order + 1] = stat[2] end
            sums[stat[2]] = (sums[stat[2]] or 0) + amount
        end
    end
    local parts = {}
    for _, label in ipairs(order) do
        local amount = sums[label]
        parts[#parts + 1] = label == "Armor" and string.format("%d Armor", amount) or string.format("%+d %s", amount, label)
    end
    return parts
end

local general = {
    key = "general", title = "General", colorKey = "General",
    cells = {
        -- Rage or energy while it's the bar in use (a druid in bear or cat form).
        { label = function() return select(2, DisplayPower()) end, get = function()
            local powerType = DisplayPower()
            if powerType == 0 then return false end
            return Number(UnitPowerMax("player", powerType))
        end },
        -- Energy per second while energy is the bar in use (cat form, rogues).
        { label = function() return STAT_ENERGY_REGEN or "Energy Regen" end, get = function()
            local _, token = UnitPowerType("player")
            if token ~= "ENERGY" or not GetPowerRegen then return false end
            return OneDecimal(GetPowerRegen()) .. "/s"
        end },
        { label = "Speed", get = function()
            local _, run = GetUnitSpeed("player")
            return string.format("%d%%", Known(run) / (BASE_MOVEMENT_SPEED or 7) * 100 + 0.5)
        end, tip = function(tooltip)
            local _, run, _, swim = GetUnitSpeed("player")
            local base = BASE_MOVEMENT_SPEED or 7
            Line(tooltip, "Run", string.format("%d%%", Known(run) / base * 100 + 0.5))
            Line(tooltip, "Swim", string.format("%d%%", Known(swim) / base * 100 + 0.5))
        end },
    },
}

------------------------------------------------------------------------------
-- Attributes
------------------------------------------------------------------------------

local STAT_NAMES = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }

-- Fallbacks for attack power from a stat, for when the client's GetAttackPowerForStat can't
-- answer (Classic's per-class rates).
local STR_AP = { WARRIOR = 2, PALADIN = 2, SHAMAN = 2, DRUID = 2, DEATHKNIGHT = 2 } -- others 1
local AGI_AP = { ROGUE = 1, HUNTER = 1 }
local AGI_RAP = { HUNTER = 2, ROGUE = 1, WARRIOR = 1 }

local function Class() return select(2, UnitClass("player")) end

-- Attack power from a stat (the client's sum) and stat functions' numbers: FrogLib.Tank.
local StatAP, Call = Tank.StatAP, Tank.Call

-- Ranged attack power from a stat: the client's sum, else the class's rate.
local function StatRAP(statIndex, stat)
    local fromClient = Call(GetRangedAttackPowerForStat, statIndex, stat)
    if fromClient then return fromClient end
    local rate = statIndex == 2 and AGI_RAP[Class()]
    return rate and stat * rate or 0
end

-- The same as Forever's own attribute tooltips (Camelot/PaperDollFrameStats.lua,
-- PaperDollFrame_SetStatTooltip2), with the client's functions it uses.
local function Gives(statIndex, stat)
    local class, gives = Class(), {}
    local function Add(template, value) gives[#gives + 1] = string.format(template, value) end
    if statIndex == 1 then
        Add("+%d AP", StatAP(1, stat) or stat * (STR_AP[class] or 1))
        -- Each 20 Strength adds 1 to a shield's block value.
        if (Call(GetBlockChance) or 0) > 0 then Add("+%d block value", math.floor(stat / 20)) end
    elseif statIndex == 2 then
        local crit = Call(GetCritChanceFromStat, 2, stat) -- a fraction
        if crit and crit > 0 then Add("+%.1f%% crit", crit * 100) end
        local attackPower = StatAP(2, stat)
        if attackPower and attackPower > 0 then
            Add("+%d AP", attackPower)
        elseif AGI_AP[class] then
            Add("+%d AP", stat * AGI_AP[class])
        end
        if class == "DRUID" then Add("+%d cat AP", stat) end
        if AGI_RAP[class] then Add("+%d RAP", StatRAP(2, stat)) end
        local dodge = Call(GetDodgeChanceFromAttribute) -- a fraction
        if dodge and dodge > 0 then Add("+%.1f%% dodge", dodge * 100) end
        Add("+%d armor", stat * 2)
    elseif statIndex == 3 then
        local first = STAMINA_BREAK or 20
        local perPoint = Call(UnitHPPerStamina, "player") or 10
        Add("+%d HP", math.min(first, stat) + math.max(0, stat - first) * perPoint)
    elseif statIndex == 4 then
        if (UnitPowerMax("player", 0) or 0) > 0 then
            local first = INTELLECT_BREAK or 20
            Add("+%d mana", math.min(first, stat) + math.max(0, stat - first) * (MANA_PER_INTELLECT or 15))
        end
        local crit = Call(GetSpellCritChanceFromStat, 4, stat) -- a fraction
        if crit and crit > 0 then Add("+%.1f%% spell crit", crit * 100) end
    elseif statIndex == 5 then
        -- Per second; health from Spirit is a quarter lower standing than sitting.
        local health = Call(GetHealthRegenFromSpirit)
        if health and health > 0 then Add("+%d hp5", health * 0.75 * 5) end
        local mana = (UnitPowerMax("player", 0) or 0) > 0 and Call(GetManaRegenFromSpirit)
        if mana and mana > 0 then Add("+%d mp5", mana * 5) end
    end
    return gives
end

local function StatCell(statIndex)
    local name = _G["SPELL_STAT" .. statIndex .. "_NAME"] or STAT_NAMES[statIndex]
    return {
        label = name,
        -- A whole row with what the stat gives, or half a row with only the number.
        wide = function() return ns.db.attrEffects end,
        get = function()
            local _, stat, bonus, penalty = UnitStat("player", statIndex)
            local text = Tinted(Number(stat), Known(bonus), Known(penalty))
            if not ns.db.attrEffects then return text end
            return text, false, table.concat(Gives(statIndex, Known(stat)), "  ")
        end,
        tip = function(tooltip)
            local base, stat, bonus, penalty = UnitStat("player", statIndex)
            Line(tooltip, "Total", Number(stat))
            Line(tooltip, "Base", Number(base))
            if Known(bonus) > 0 then Line(tooltip, "Bonus", GREEN .. "+" .. Number(bonus) .. "|r") end
            if Known(penalty) < 0 then Line(tooltip, "Penalty", RED .. Number(penalty) .. "|r") end
            local gives = Gives(statIndex, Known(stat))
            if #gives > 0 then
                Line(tooltip, " ")
                for _, give in ipairs(gives) do Line(tooltip, give) end
            end
        end,
    }
end

local attributes = {
    key = "attributes", title = "Attributes", colorKey = "Attributes",
    cells = { StatCell(1), StatCell(2), StatCell(3), StatCell(4), StatCell(5) },
}

------------------------------------------------------------------------------
-- Melee and ranged
------------------------------------------------------------------------------

-- Each 14 attack power adds 1 damage per second to a weapon (Classic's rule).
local AP_PER_DPS = Tank.AP_PER_DPS

-- Weapon and defense skill, the way Forever's sheet finds them: FrogLib.Tank.
local SKILL_PER_LEVEL = Tank.SKILL_PER_LEVEL
local WeaponSkill, DefenseSkill = Tank.WeaponSkill, Tank.DefenseSkill

-- Forever's weapon skill rules (Camelot/SkillsFrame.lua): each point short of the enemy's defense (its
-- level x 5) costs 0.04% chance to hit and to crit, and against raid bosses some hits glance for less.
local function SkillGap(over, skill)
    return (UnitLevel("player") + over) * SKILL_PER_LEVEL - skill
end

-- The released game works glancing blows out itself (GetGlancingBlowChance/Penalty, from your skill
-- and the enemy's defense, as fractions); the formulas below are the beta's, for clients without them.
local function EnemyDefense(over)
    return (UnitLevel("player") + over) * SKILL_PER_LEVEL
end

local function GlancingChance(over, skill)
    if GetGlancingBlowChance then
        local ok, chance = pcall(GetGlancingBlowChance, skill, EnemyDefense(over))
        chance = ok and Known(chance)
        if chance then return math.max(0, math.min(100, chance * 100)) end
    end
    skill = math.min(UnitLevel("player") * SKILL_PER_LEVEL, skill)
    return math.max(-100, math.min(100, (0.02 * SkillGap(over, skill) + 0.1) * 100))
end

local function GlancingPenalty(over, skill)
    if GetGlancingBlowPenalty then
        local ok, penalty = pcall(GetGlancingBlowPenalty, skill, EnemyDefense(over))
        penalty = ok and Known(penalty)
        if penalty then return math.max(0, math.min(100, penalty * 100)) end
    end
    local gap = SkillGap(over, skill)
    local low = 1.30 - 0.05 * gap
    local high = 1.20 - 0.03 * gap
    if gap > 10 then
        low, high = low + 0.1, high + 0.1
    end
    low = math.max(0.01, math.min(0.91, low))
    high = math.max(0.20, math.min(0.99, high))
    return 100 - math.max(0, math.min(1, (low + high) / 2)) * 100
end

-- An enemy `over` levels up attacking you: its misses, crits and crushing blows (FrogLib.Tank,
-- from Camelot/PaperDollFrameStats.lua).
local EnemyMissChance, EnemyCritChance, EnemyCrushChance = Tank.EnemyMissChance, Tank.EnemyCritChance, Tank.EnemyCrushChance

-- "40/45", yellow while it's below the cap.
local function SkillText(current, maximum)
    local text = current .. "/" .. maximum
    if current < maximum then return "|cffffd040" .. text .. "|r" end
    return text
end

local function WeaponText(low, high, speed)
    low, high, speed = Known(low), Known(high), Known(speed)
    if speed <= 0 then return false end
    local dps = (low + high) / 2 / speed
    return string.format("%d-%d  %s%.2fs|r  %s%.1f|r dps",
        math.max(1, math.floor(low)), math.max(1, math.ceil(high)), GREY, speed, WHITE, dps)
end

local function WeaponTip(tooltip, low, high, speed, attackPower)
    low, high, speed = Known(low), Known(high), Known(speed)
    Line(tooltip, "Damage", string.format("%d - %d", math.max(1, math.floor(low)), math.max(1, math.ceil(high))))
    Line(tooltip, "Average hit", string.format("%.1f", (low + high) / 2))
    Line(tooltip, "Speed", string.format("%.2f s", speed))
    Line(tooltip, "Damage per second", string.format("%.1f", (low + high) / 2 / speed))
    Line(tooltip, " ")
    if attackPower then
        Line(tooltip, string.format("Includes %.1f dps from attack power.", Known(attackPower) / AP_PER_DPS))
    end
    Line(tooltip, "|cff8c8c8cWorked out from the exact damage. The game's own sheet rounds the damage "
        .. "first, so its DPS can read a little lower.|r")
end

local function MeleeAP()
    local base, bonus, penalty = UnitAttackPower("player")
    return Known(base) + Known(bonus) + Known(penalty), Known(bonus), Known(penalty)
end

local function RangedAP()
    local base, bonus, penalty = UnitRangedAttackPower("player")
    return Known(base) + Known(bonus) + Known(penalty), Known(bonus), Known(penalty)
end

local function APText(total, bonus, penalty)
    return Tinted(Number(total), bonus, penalty), false, string.format("+%.1f dps", total / AP_PER_DPS)
end

local function Haste(value) return Percent(value), Known(value) == 0 end

local melee = {
    key = "melee", title = "Melee", colorKey = "Attack",
    cells = {
        { label = "Main Hand", wide = true, get = function()
            local low, high = UnitDamage("player")
            return WeaponText(low, high, (UnitAttackSpeed("player")))
        end, tip = function(tooltip)
            local low, high = UnitDamage("player")
            WeaponTip(tooltip, low, high, (UnitAttackSpeed("player")), (MeleeAP()))
        end },
        { label = "Off Hand", wide = true, get = function()
            local _, offSpeed = UnitAttackSpeed("player")
            if not offSpeed then return false end
            local _, _, low, high = UnitDamage("player")
            return WeaponText(low, high, offSpeed)
        end, tip = function(tooltip)
            local _, offSpeed = UnitAttackSpeed("player")
            local _, _, low, high = UnitDamage("player")
            WeaponTip(tooltip, low, high, offSpeed, (MeleeAP()))
        end },
        { label = "Attack Power", wide = true, get = function() return APText(MeleeAP()) end,
          tip = function(tooltip)
            local total = MeleeAP()
            Line(tooltip, string.format("Adds %.1f damage per second to your melee weapons.", total / AP_PER_DPS))
        end },
        { label = "Crit", get = function() return Percent(GetCritChance()) end },
        { label = "Hit", get = function()
            if not GetHitModifier then return false end
            local hit = GetHitModifier() or 0
            return "+" .. Percent(hit), Known(hit) == 0
        end },
        { label = "Haste", get = function()
            if not GetMeleeHaste then return false end
            return Haste(GetMeleeHaste())
        end },
    },
}

-- Something that shoots in the ranged slot (not a relic, idol, totem or libram).
local function HasRangedWeapon()
    local id = GetInventoryItemID("player", INVSLOT_RANGED or 18)
    if not id then return false end
    local classID = select(6, C_Item.GetItemInfoInstant(id))
    return classID == Enum.ItemClass.Weapon
end

local function RangedHaste()
    local haste, quiver = GetRangedHaste()
    return Known(haste) + Known(quiver or 0)
end

local function RangedHit()
    if not GetRangedHitModifier then return Tank.MeleeHit() end
    return Known(GetRangedHitModifier() or 0)
end

local ranged = {
    key = "ranged", title = "Ranged", colorKey = "Attack",
    show = HasRangedWeapon,
    cells = {
        { label = function()
            local id = GetInventoryItemID("player", INVSLOT_RANGED or 18)
            local subclass = id and select(7, C_Item.GetItemInfoInstant(id))
            return subclass == Enum.ItemWeaponSubclass.Wand and "Wand" or "Ranged"
        end, wide = true, get = function()
            local speed, low, high = UnitRangedDamage("player")
            return WeaponText(low, high, speed)
        end, tip = function(tooltip)
            local speed, low, high = UnitRangedDamage("player")
            WeaponTip(tooltip, low, high, speed, (RangedAP()))
        end },
        { label = "Attack Power", wide = true, get = function() return APText(RangedAP()) end },
        { label = "Crit", get = function() return Percent(GetRangedCritChance()) end },
        { label = "Hit", get = function()
            local hit = RangedHit()
            return "+" .. Percent(hit), hit == 0
        end },
        { label = "Haste", get = function()
            if not GetRangedHaste then return false end
            return Haste(RangedHaste())
        end },
    },
}

------------------------------------------------------------------------------
-- Spells
------------------------------------------------------------------------------

local SCHOOLS = {
    { 2, "Holy", "ffe680" }, { 3, "Fire", "ff8040" }, { 4, "Nature", "4cff4c" },
    { 5, "Frost", "80d0ff" }, { 6, "Shadow", "b080ff" }, { 7, "Arcane", "ff80ff" },
}

-- The best school and whether all schools agree (then there's no point listing them).
local function BestSchool(SchoolValue)
    local best, same, first = nil, true, nil
    for _, school in ipairs(SCHOOLS) do
        local value = Known(SchoolValue(school[1]))
        if first == nil then first = value elseif value ~= first then same = false end
        if not best or value > best then best = value end
    end
    return best, same
end

local function SchoolTip(tooltip, SchoolValue, Format)
    local _, same = BestSchool(SchoolValue)
    if same then return end
    for _, school in ipairs(SCHOOLS) do
        Line(tooltip, "|cff" .. school[3] .. school[2] .. "|r", Format(SchoolValue(school[1])))
    end
end

local function UsesMana() return (UnitPowerMax("player", 0) or 0) > 0 end

local spell = {
    key = "spell", title = "Spells", colorKey = "Secondary Stats",
    show = function()
        local ok, mana = pcall(UsesMana)
        return not ok or mana
    end,
    cells = {
        { label = "Damage", get = function()
            local best = BestSchool(GetSpellBonusDamage)
            return "+" .. Number(best), best == 0
        end, tip = function(tooltip)
            Line(tooltip, "Bonus damage to your spells.")
            SchoolTip(tooltip, GetSpellBonusDamage, function(value) return "+" .. Number(value) end)
        end },
        { label = "Healing", get = function()
            if not GetSpellBonusHealing then return false end
            local healing = Known(GetSpellBonusHealing())
            return "+" .. Number(healing), healing == 0
        end },
        { label = "Crit", get = function() return Percent((BestSchool(GetSpellCritChance))) end,
          tip = function(tooltip) SchoolTip(tooltip, GetSpellCritChance, Percent) end },
        { label = "Hit", get = function()
            if not GetSpellHitModifier then return false end
            local hit = GetSpellHitModifier() or 0
            return "+" .. Percent(hit), Known(hit) == 0
        end },
        { label = "Haste", get = function()
            if not UnitSpellHaste then return false end
            return Haste(UnitSpellHaste("player"))
        end },
        -- GetManaRegen gives mana per second: out of combat-casting, and while casting.
        { label = "Mana Regen", wide = true, get = function()
            if not GetManaRegen then return false end
            local base, casting = GetManaRegen()
            base = Known(base)
            local text = string.format("%s %smp5|r   %s %swhile casting|r",
                OneDecimal(base * 5), GREY, OneDecimal(Known(casting) * 5), GREY)
            -- A tick when the regen meter (Regen.lua) agrees within 10%, else what it measured.
            local measured = ns.Regen and ns.Regen:Rate("rest")
            if measured and base > 0 then
                if math.abs(measured - base) <= base * 0.1 then
                    text = text .. " |TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
                else
                    text = string.format("%s |cffffd040(%s measured)|r", text, OneDecimal(measured * 5))
                end
            end
            return text
        end, tip = function(tooltip)
            Line(tooltip, "Mana every 5 seconds: the first after 5 seconds without casting, "
                .. "the second while you keep casting.")
            Line(tooltip, "|cff8c8c8cThe game's own sheet rounds this down (37.5 shows as 37).|r")
            Line(tooltip, " ")
            local rate, ticks, seconds = ns.Regen:Rate("rest")
            if rate then
                Line(tooltip, "Measured", string.format("%.1f mp5 (%d ticks, %ds)", rate * 5, ticks, seconds))
            else
                Line(tooltip, "Not measured yet: spend some mana, then wait without casting until it's "
                    .. "back up. A tick means the game's number checked out.")
            end
            local castingRate, castingTicks, castingSeconds = ns.Regen:Rate("casting")
            if castingRate then
                Line(tooltip, "Measured while casting", string.format("%.1f mp5 (%d ticks, %ds)",
                    castingRate * 5, castingTicks, castingSeconds))
            elseif ns.Regen:NoneWhileCasting() then
                Line(tooltip, "Measured while casting", "none")
            end
        end },
    },
}

------------------------------------------------------------------------------
-- Defense
------------------------------------------------------------------------------

-- The share of a physical hit armor takes off, against an enemy of your level (plus `over`): FrogLib.Tank.
local ArmorReduction = Tank.ArmorReduction

local RESISTS = { { 2, "Fire", "ff8040" }, { 3, "Nat", "4cff4c" }, { 4, "Frost", "80d0ff" },
    { 5, "Shad", "b080ff" }, { 6, "Arc", "ff80ff" } }

local defense = {
    key = "defense", title = "Defense", colorKey = "Defense",
    cells = {
        { label = ARMOR or "Armor", wide = true, get = function()
            local _, effective, _, bonus, penalty = UnitArmor("player")
            effective = Known(effective)
            return Tinted(Number(effective), bonus and Known(bonus), penalty and Known(penalty)), false,
                string.format("%.1f%% damage reduction", ArmorReduction(effective) * 100)
        end, tip = function(tooltip)
            local _, effective = UnitArmor("player")
            effective = Known(effective)
            Line(tooltip, "Physical damage taken off, by enemy level:")
            local level = UnitLevel("player")
            for over = 0, 3 do
                Line(tooltip, "Level " .. (level + over), string.format("%.2f%%", ArmorReduction(effective, over) * 100))
            end
            Line(tooltip, "|cff8c8c8cArmor can't take off more than 75%.|r")
        end },
        { label = "Dodge", get = function() return Percent(GetDodgeChance()) end },
        { label = "Parry", get = function()
            local parry = Known(GetParryChance())
            return Percent(parry), parry == 0
        end },
        { label = "Block", get = function()
            local block = Known(GetBlockChance())
            return Percent(block), block == 0
        end },
        { label = "Resist", wide = true, get = function()
            local parts, any = {}, false
            for _, resist in ipairs(RESISTS) do
                local _, total = UnitResistance("player", resist[1])
                total = Known(total)
                if total ~= 0 then any = true end
                parts[#parts + 1] = string.format("|cff%s%s|r %d", resist[3], resist[2], total)
            end
            return table.concat(parts, "  "), not any
        end },
    },
}

------------------------------------------------------------------------------
-- What the numbers add up to, by the rules in Forever's own interface code
-- (Camelot/PaperDollFrameStats.lua and Camelot/SkillsFrame.lua).
------------------------------------------------------------------------------

local ArmorNow, MeleeHit = Tank.ArmorNow, Tank.MeleeHit

-- Your main hand's paper DPS, plus the off hand's when dual wielding.
local function PaperDPS()
    local low, high, offLow, offHigh = UnitDamage("player")
    local speed, offSpeed = UnitAttackSpeed("player")
    local dps = (Known(low) + Known(high)) / 2 / Known(speed)
    if offSpeed then dps = dps + (Known(offLow) + Known(offHigh)) / 2 / Known(offSpeed) end
    return dps
end

-- Forever's table for an enemy 0-3 levels up, for a capped weapon skill: its chance to dodge you.
-- (Your chance to miss it, and the hit that means never missing: FrogLib.Tank.)
local ENEMY_DODGE = { [0] = 5.0, 5.5, 6.0, 6.5 }
local SkillShort, HitNeeded = Tank.SkillShort, Tank.HitNeeded

-- Hands out shares of 100% in the game's order, none more than what's left: Take(share), Left().
local function Shares()
    local left = 100
    local function Take(share)
        share = math.max(0, math.min(left, share))
        left = left - share
        return share
    end
    return Take, function() return left end
end

-- Where your auto-attacks go against an enemy `over` levels up, in the game's order (misses, dodges,
-- glancing blows, crits, hits), as percentages, and `mult`: the share of paper DPS they add up to.
local function SwingTable(over)
    local level = UnitLevel("player")
    local skill = WeaponSkill(INVSLOT_MAINHAND or 16) or level * SKILL_PER_LEVEL
    local Take, Left = Shares()
    local swings = {}
    swings.miss = Take(HitNeeded(over) - MeleeHit())
    swings.dodge = Take(ENEMY_DODGE[over] + SkillShort(skill) * 0.04)
    swings.glance = Take(GlancingChance(over, skill))
    swings.glancePenalty = GlancingPenalty(over, skill)
    -- Crit lost to weapon skill short of the enemy's defense.
    swings.critPenalty = math.max(0, SkillGap(over, skill) * 0.04)
    swings.crit = Take(Known(GetCritChance()) - swings.critPenalty)
    swings.hit = Left()
    swings.mult = (swings.hit + swings.crit * 2 + swings.glance * (1 - swings.glancePenalty / 100)) / 100
    return swings
end

-- Your ranged weapon's paper DPS.
local function RangedPaperDPS()
    local speed, low, high = UnitRangedDamage("player")
    return (Known(low) + Known(high)) / 2 / Known(speed)
end

local function RangedSkill()
    return WeaponSkill(INVSLOT_RANGED or 18) or UnitLevel("player") * SKILL_PER_LEVEL
end

-- The hit that means your shots never miss an enemy `over` levels up (dual wielding's penalty is
-- melee's alone).
local function ShotHitNeeded(over)
    return HitNeeded(over, { skill = RangedSkill(), dualWield = false })
end

-- Where your ranged auto-attacks go, like SwingTable. Forever's own weapon skill tooltip gives
-- shots only a chance to hit and to crit: they aren't dodged, parried or glancing.
local function ShotTable(over)
    local Take, Left = Shares()
    local shots = {}
    shots.miss = Take(ShotHitNeeded(over) - RangedHit())
    shots.critPenalty = math.max(0, SkillGap(over, RangedSkill()) * 0.04)
    shots.crit = Take(Known(GetRangedCritChance()) - shots.critPenalty)
    shots.hit = Left()
    shots.mult = (shots.hit + shots.crit * 2) / 100
    return shots
end

-- What happens to an enemy's swing at you, `over` levels up: FrogLib.Tank.
local IncomingTable = Tank.IncomingTable

-- Spells miss an enemy 0-3 levels up 4 / 5 / 6 / 17% of the time, less your spell hit.
local SPELL_MISS = { [0] = 4, 5, 6, 17 }
local function SpellMiss(over)
    local hit = GetSpellHitModifier and Known(GetSpellHitModifier() or 0) or 0
    return math.max(0, SPELL_MISS[over] - hit)
end

------------------------------------------------------------------------------
-- Caps: the things with a ceiling worth reaching.
------------------------------------------------------------------------------

local function Signed(value) return string.format("%+.2f%%", value == 0 and 0 or value) end

-- The weapon the rows below are about: the ranged one while the panel shows you as ranged (the
-- switch, Tabs.lua), else the main hand.
local function CapsSlot()
    return ns.Ranged() and (INVSLOT_RANGED or 18) or (INVSLOT_MAINHAND or 16)
end

local caps = {
    key = "caps", title = "Caps", colorKey = "Insights",
    cells = {
        -- Weapon skill, named for the weapon ("Two-Handed Maces 41/45"), with what being short
        -- of the cap costs.
        { label = function()
            local _, _, name = WeaponSkill(CapsSlot())
            return name or "Weapon Skill"
        end, wide = true, get = function()
            local current, maximum = WeaponSkill(CapsSlot())
            if not current then return false end
            local gap = SkillGap(0, current)
            local note = gap > 0 and string.format("%d short: -%s hit and crit, rises as you fight", gap, Percent(gap * 0.04)) or nil
            return SkillText(current, maximum), false, note, current / maximum
        end, tip = function(tooltip)
            local ranged = ns.Ranged()
            local current, _, name = WeaponSkill(CapsSlot())
            if not current then return end
            if not ranged then
                local offCurrent, offMax, offName = WeaponSkill(INVSLOT_OFFHAND or 17)
                if offCurrent and offName ~= name then Line(tooltip, offName, offCurrent .. " / " .. offMax) end
            end
            -- Shots can only miss; swings can also be dodged, parried and glance.
            local hitLabel = ranged and "Hit" or "Hit, and not dodged or parried"
            Line(tooltip, " ")
            Line(tooltip, "|cffffffffAgainst an enemy of your level|r")
            Line(tooltip, hitLabel, Signed(-SkillGap(0, current) * 0.04))
            Line(tooltip, "Critical hits", Signed(-SkillGap(0, current) * 0.04))
            Line(tooltip, " ")
            Line(tooltip, "|cffffffffAgainst raid bosses|r")
            Line(tooltip, hitLabel, Signed(-SkillGap(3, current) * 0.04))
            Line(tooltip, "Critical hits", Signed(-SkillGap(3, current) * 0.04))
            if not ranged then
                Line(tooltip, "Glancing blows", string.format("%.0f%% of hits, for %.0f%% less",
                    GlancingChance(3, current), GlancingPenalty(3, current)))
            end
            Line(tooltip, " ")
            Line(tooltip, "|cff8c8c8cRises as you fight with this kind of weapon. Forever's own rules: "
                .. "0.04% per point short of the enemy's defense (its level x 5).|r")
        end },
        -- Defense skill, out of your level x 5. Short of that, enemies of your level hit and crit
        -- you a little more; above it (gear), Forever adds 0.04% avoidance per point.
        { label = DEFENSE or "Defense", wide = true, get = function()
            local current, maximum = DefenseSkill()
            if not current then return false end
            local note
            if current < maximum then
                note = string.format("%d short: enemies hit and crit you %s more", maximum - current,
                    Percent((maximum - current) * 0.04))
            elseif current > maximum then
                note = string.format("+%s avoidance, %s fewer crits taken", Percent((current - maximum) * 0.04),
                    Percent((current - maximum) * 0.04))
            end
            return SkillText(current, maximum), false, note, math.min(1, current / maximum)
        end, tip = function(tooltip)
            local current = DefenseSkill()
            Line(tooltip, "By enemy level:")
            local level = UnitLevel("player")
            for over = 0, 3 do
                local crush = EnemyCrushChance(over, current)
                Line(tooltip, string.format("Level %d%s", level + over, over == 3 and " (raid boss)" or ""),
                    string.format("misses %.1f%%  crits %.1f%%%s", EnemyMissChance(over, current),
                        EnemyCritChance(over, current), crush > 0 and string.format("  crushes %.0f%%", crush) or ""))
            end
            Line(tooltip, " ")
            Line(tooltip, "|cff8c8c8cCritical hits from creatures deal double damage; crushing blows deal 150%. "
                .. "Rises as you take hits.|r")
        end },
        -- Hit against the hit that means never missing a same-level enemy (shots' as ranged).
        { label = "Hit Chance", wide = true, get = function()
            local ranged = ns.Ranged()
            local hit = ranged and RangedHit() or MeleeHit()
            local need = (ranged and ShotHitNeeded or HitNeeded)(0)
            return string.format("%s of %s", Percent(hit), Percent(need)), false,
                string.format("%s means %s a level %d enemy", Percent(need),
                    ranged and "shots never miss" or "melee never misses", UnitLevel("player")),
                math.min(1, hit / need)
        end, tip = function(tooltip)
            local ranged = ns.Ranged()
            local Need = ranged and ShotHitNeeded or HitNeeded
            Line(tooltip, ranged and "Hit needed for shots to never miss:" or "Hit needed to never miss with melee:")
            local level = UnitLevel("player")
            for over = 0, 3 do
                Line(tooltip, string.format("Level %d%s", level + over, over == 3 and " (raid boss)" or ""), Percent(Need(over)))
            end
            Line(tooltip, " ")
            Line(tooltip, "|cff8c8c8cIncludes your weapon skill. Forever's own hit tooltip rounds the raid boss figure to 8%.|r")
        end },
    },
}

------------------------------------------------------------------------------
-- For Tabs.lua, Tracker.lua and Compare.lua.
------------------------------------------------------------------------------

ns.Stats = {
    Known = Known, Number = Number, Percent = Percent, OneDecimal = OneDecimal, Tinted = Tinted, Line = Line,
    Class = Class, UsesMana = UsesMana, DisplayPower = DisplayPower, Durability = Durability,
    GearTotals = GearTotals, GearSummary = GearSummary, GEAR_STATS = GEAR_STATS,
    StatAP = StatAP, Call = Call, BestSchool = BestSchool, ArmorReduction = ArmorReduction,
    ArmorNow = ArmorNow, WeaponSkill = WeaponSkill, DefenseSkill = DefenseSkill,
    MeleeAP = MeleeAP, MeleeHit = MeleeHit, PaperDPS = PaperDPS, SwingTable = SwingTable,
    HasRangedWeapon = HasRangedWeapon, StatRAP = StatRAP, RangedPaperDPS = RangedPaperDPS, ShotTable = ShotTable,
    IncomingTable = IncomingTable, SpellMiss = SpellMiss, HitNeeded = HitNeeded,
    AP_PER_DPS = AP_PER_DPS, SKILL_PER_LEVEL = SKILL_PER_LEVEL,
}

-- Better and worse, for changes (the change cards, item tooltips): a muted green and red that sit
-- well on EllesmereUI's dark and Forever's bronze alike.
ns.GOOD, ns.BAD = { 0.45, 0.80, 0.47 }, { 0.87, 0.42, 0.38 }
ns.GOOD_HEX, ns.BAD_HEX = "|cff73cc78", "|cffde6b61"

ns.SectionByKey = {
    attributes = attributes, caps = caps, melee = melee, ranged = ranged, spell = spell,
    defense = defense, general = general,
}

-- Every section, for the audit.
ns.Sections = { attributes, caps, melee, ranged, spell, defense, general }

-- Events that can change something the panel shows. Unit events are for you and your pet.
ns.UnitEvents = {
    "UNIT_STATS", "UNIT_ATTACK_SPEED", "UNIT_DAMAGE", "UNIT_RANGEDDAMAGE", "UNIT_ATTACK_POWER",
    "UNIT_RANGED_ATTACK_POWER", "UNIT_RESISTANCES", "UNIT_AURA", "UNIT_MAXHEALTH", "UNIT_MAXPOWER",
    "UNIT_DISPLAYPOWER", "UNIT_INVENTORY_CHANGED", "UNIT_DEFENSE", "UNIT_LEVEL", "UNIT_HAPPINESS",
}
ns.Events = {
    "PLAYER_EQUIPMENT_CHANGED", "COMBAT_RATING_UPDATE", "SPELL_POWER_CHANGED",
    "PLAYER_DAMAGE_DONE_MODS", "UPDATE_INVENTORY_DURABILITY", "UPDATE_SHAPESHIFT_FORM",
    "SKILL_LINES_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_TALENT_UPDATE",
    "CHARACTER_POINTS_CHANGED", "UNIT_PET", "PET_UI_UPDATE", "GROUP_ROSTER_UPDATE", "BAG_UPDATE_DELAYED",
    "PET_STATS_UPDATE", "UNIT_PET_EXPERIENCE",
}
