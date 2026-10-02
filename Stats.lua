local _, ns = ...

-- What the panel shows: sections of cells, each cell a label and a getter.
--   get() returns the value text, or false to leave the cell out (nothing to show, e.g. no
--   off-hand weapon). A second return of true marks a zero the "Hide zeros" setting may drop.
--   tip(tt) adds lines to GameTooltip when the cell is hovered (optional).
--   wide = true takes a whole row; other cells pair up two to a row.
-- Combat values can be secret on this client. Getters read numbers through N(), which raises on
-- a secret, and the panel runs every getter in pcall: a cell that can't be read keeps its last
-- readable text (dimmed) instead of breaking.

local issecret = issecretvalue or function() return false end

local function N(v)
    if v == nil or issecret(v) then error("unreadable", 0) end
    return v
end
ns.N = N

local GREEN, RED, GREY, WHITE = "|cff40ff40", "|cffff4040", "|cff8c8c8c", "|cffffffff"

-- 5.43% / 5% (no trailing zeros).
local function Pct(v)
    local s = string.format("%.2f", N(v)):gsub("0+$", ""):gsub("%.$", "")
    return s .. "%"
end

local function Num(v)
    v = N(v)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(v) or tostring(v)
end

-- 37.5 / 37 (one decimal, only when there is one).
local function Dec(v)
    return (string.format("%.1f", N(v)):gsub("%.0$", ""))
end

-- A value tinted the way Blizzard tints buffed (green) and debuffed (red) stats.
local function Tinted(text, pos, neg)
    if neg and neg < 0 then return RED .. text .. "|r" end
    if pos and pos > 0 then return GREEN .. text .. "|r" end
    return text
end

local function Line(tt, left, right)
    if right then
        tt:AddDoubleLine(left, right, 1, 0.82, 0, 1, 1, 1)
    else
        tt:AddLine(left, 1, 1, 1, true)
    end
end

------------------------------------------------------------------------------
-- General
------------------------------------------------------------------------------

local POWER_LABEL = { [0] = MANA or "Mana", [1] = RAGE or "Rage", [3] = ENERGY or "Energy" }

local function DisplayPower()
    local pType, token = UnitPowerType("player")
    return N(pType), (token and _G[token]) or POWER_LABEL[pType] or token or "Power"
end

local function Durability()
    local cur, max, low = 0, 0, nil
    for slot = 1, 19 do
        local c, m = GetInventoryItemDurability(slot)
        if c and m and m > 0 then
            cur, max = cur + c, max + m
            local p = c / m
            if not low or p < low then low = p end
        end
    end
    if max == 0 then return nil end
    return cur / max, low
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
            for k, v in pairs(stats or {}) do
                if type(v) == "number" then totals[k] = (totals[k] or 0) + v end
            end
        end
    end
    return totals, items
end

-- "+1 Str  +2 Agi  +10 SP  258 Armor", in GEAR_STATS order, with like labels added together.
local function GearSummary(totals)
    local sums, order = {}, {}
    for _, s in ipairs(GEAR_STATS) do
        local v = totals[s[1]]
        if v and v ~= 0 then
            if not sums[s[2]] then order[#order + 1] = s[2] end
            sums[s[2]] = (sums[s[2]] or 0) + v
        end
    end
    local parts = {}
    for _, label in ipairs(order) do
        local v = sums[label]
        parts[#parts + 1] = label == "Armor" and string.format("%d Armor", v) or string.format("%+d %s", v, label)
    end
    return parts
end

local general = {
    key = "general", title = "General", colorKey = "General",
    cells = {
        -- Rage or energy while it's the bar in use (a druid in bear or cat form).
        { label = function() return select(2, DisplayPower()) end, get = function()
            local pType = DisplayPower()
            if pType == 0 then return false end
            return Num(UnitPowerMax("player", pType))
        end },
        -- Energy per second while energy is the bar in use (cat form, rogues).
        { label = function() return STAT_ENERGY_REGEN or "Energy Regen" end, get = function()
            local _, token = UnitPowerType("player")
            if token ~= "ENERGY" or not GetPowerRegen then return false end
            return Dec(GetPowerRegen()) .. "/s"
        end },
        { label = "Speed", get = function()
            local _, run = GetUnitSpeed("player")
            return string.format("%d%%", N(run) / (BASE_MOVEMENT_SPEED or 7) * 100 + 0.5)
        end, tip = function(tt)
            local _, run, flight, swim = GetUnitSpeed("player")
            local base = BASE_MOVEMENT_SPEED or 7
            Line(tt, "Run", string.format("%d%%", N(run) / base * 100 + 0.5))
            Line(tt, "Swim", string.format("%d%%", N(swim) / base * 100 + 0.5))
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

-- Attack power from a stat, as the client works it out (GetAttackPowerForStat(1, 28) = 56).
local function StatAP(i, stat)
    if not GetAttackPowerForStat then return nil end
    local ok, v = pcall(GetAttackPowerForStat, i, stat)
    if ok and type(v) == "number" and not issecret(v) then return v end
end

-- A number from one of Forever's stat functions, or nil if it's missing, fails or is secret.
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok and type(v) == "number" and not issecret(v) then return v end
end

-- The same as Forever's own attribute tooltips (Camelot/PaperDollFrameStats.lua,
-- PaperDollFrame_SetStatTooltip2), with the client's functions it uses.
local function Gives(i, stat)
    local class, out = Class(), {}
    local function add(fmt, v) out[#out + 1] = string.format(fmt, v) end
    if i == 1 then
        add("+%d AP", StatAP(1, stat) or stat * (STR_AP[class] or 1))
        -- Each 20 Strength adds 1 to a shield's block value.
        if (Call(GetBlockChance) or 0) > 0 then add("+%d block value", math.floor(stat / 20)) end
    elseif i == 2 then
        local crit = Call(GetCritChanceFromStat, 2, stat) -- a fraction
        if crit and crit > 0 then add("+%.1f%% crit", crit * 100) end
        local ap = StatAP(2, stat)
        if ap and ap > 0 then
            add("+%d AP", ap)
        elseif AGI_AP[class] then
            add("+%d AP", stat * AGI_AP[class])
        end
        if class == "DRUID" then add("+%d cat AP", stat) end
        if AGI_RAP[class] then
            add("+%d RAP", Call(GetRangedAttackPowerForStat, 2, stat) or stat * AGI_RAP[class])
        end
        local dodge = Call(GetDodgeChanceFromAttribute) -- a fraction
        if dodge and dodge > 0 then add("+%.1f%% dodge", dodge * 100) end
        add("+%d armor", stat * 2)
    elseif i == 3 then
        local first = STAMINA_BREAK or 20
        local per = Call(UnitHPPerStamina, "player") or 10
        add("+%d HP", math.min(first, stat) + math.max(0, stat - first) * per)
    elseif i == 4 then
        if (UnitPowerMax("player", 0) or 0) > 0 then
            local first = INTELLECT_BREAK or 20
            add("+%d mana", math.min(first, stat) + math.max(0, stat - first) * (MANA_PER_INTELLECT or 15))
        end
        local crit = Call(GetSpellCritChanceFromStat, 4, stat) -- a fraction
        if crit and crit > 0 then add("+%.1f%% spell crit", crit * 100) end
    elseif i == 5 then
        -- Per second; health from Spirit is a quarter lower standing than sitting.
        local hp = Call(GetHealthRegenFromSpirit)
        if hp and hp > 0 then add("+%d hp5", hp * 0.75 * 5) end
        local mana = (UnitPowerMax("player", 0) or 0) > 0 and Call(GetManaRegenFromSpirit)
        if mana and mana > 0 then add("+%d mp5", mana * 5) end
    end
    return out
end

local function StatCell(i)
    local name = _G["SPELL_STAT" .. i .. "_NAME"] or STAT_NAMES[i]
    return {
        label = name,
        -- A whole row with what the stat gives, or half a row with just the number.
        wide = function() return ns.db.attrEffects end,
        get = function()
            local _, stat, pos, neg = UnitStat("player", i)
            local text = Tinted(Num(stat), N(pos), N(neg))
            if not ns.db.attrEffects then return text end
            return text, false, table.concat(Gives(i, N(stat)), "  ")
        end,
        tip = function(tt)
            local base, stat, pos, neg = UnitStat("player", i)
            Line(tt, "Total", Num(stat))
            Line(tt, "Base", Num(base))
            if N(pos) > 0 then Line(tt, "Bonus", GREEN .. "+" .. Num(pos) .. "|r") end
            if N(neg) < 0 then Line(tt, "Penalty", RED .. Num(neg) .. "|r") end
            local gives = Gives(i, N(stat))
            if #gives > 0 then
                Line(tt, " ")
                for _, g in ipairs(gives) do Line(tt, g) end
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
local AP_PER_DPS = 14

-- Weapon skills, the way Forever's sheet finds them (Camelot/PaperDollFrameStats.lua): the
-- weapon's subclass names a skill line, a druid in a form uses Feral Combat, and an empty main
-- hand is Unarmed.
local S = Enum.ItemWeaponSubclass
local WEAPON_SKILL_ID = {
    [S.Sword1H] = 43, [S.Axe1H] = 44, [S.Bows] = 45, [S.Guns] = 46, [S.Mace1H] = 54,
    [S.Sword2H] = 55, [S.Staff] = 136, [S.Mace2H] = 160, [S.Axe2H] = 172, [S.Dagger] = 173,
    [S.Thrown] = 176, [S.Crossbow] = 226, [S.Wand] = 228, [S.Polearm] = 229, [S.Unarmed] = 162,
}
local FERAL_SKILL, UNARMED_SKILL = 3014, 162
local SKILL_PER_LEVEL = 5

local function WeaponSkillID(slot)
    if Class() == "DRUID" and (GetShapeshiftForm() or 0) ~= 0 then return FERAL_SKILL end
    local id = GetInventoryItemID("player", slot)
    if not id then
        return slot == (INVSLOT_MAINHAND or 16) and UNARMED_SKILL or nil
    end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
    if classID ~= Enum.ItemClass.Weapon then return nil end
    return WEAPON_SKILL_ID[subclassID]
end

-- Your skill with the weapon in a slot (rank plus bonuses), its cap and its name.
local function WeaponSkill(slot)
    local skillID = WeaponSkillID(slot)
    local get = skillID and C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
    if not get then return nil end
    local ok, info = pcall(get, skillID)
    if not ok or type(info) ~= "table" or type(info.rank) ~= "number" or issecret(info.rank) then return nil end
    return info.rank + (info.modifier or 0), info.maxRank, info.name
end

-- Defense skill (base plus bonuses) and its cap, your level x 5.
local function DefenseSkill()
    if not UnitDefenseSkill then return nil end
    local base, mod = UnitDefenseSkill("player")
    return math.max(0, N(base) + N(mod)), UnitLevel("player") * SKILL_PER_LEVEL
end

-- Forever's weapon skill rules (Camelot/SkillsFrame.lua): each point of weapon skill short of
-- the enemy's defense (its level x 5) costs 0.04% chance to hit and to crit, and against raid
-- bosses (3 levels up) a share of hits glance for less.
local function SkillGap(over, skill)
    return (UnitLevel("player") + over) * SKILL_PER_LEVEL - skill
end

local function GlancingChance(over, skill)
    skill = math.min(UnitLevel("player") * SKILL_PER_LEVEL, skill)
    return math.max(-100, math.min(100, (0.02 * SkillGap(over, skill) + 0.1) * 100))
end

local function GlancingPenalty(over, skill)
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

-- An enemy `over` levels up attacking you (Camelot/PaperDollFrameStats.lua): its weapon skill
-- is its level x 5, and each point of that over your defense moves 0.04% from its misses to its
-- crits; 15 or more points over, it can land crushing blows.
local function EnemyGap(over, defense)
    return (UnitLevel("player") + over) * SKILL_PER_LEVEL - defense
end

local function EnemyMissChance(over, defense)
    return math.max(0, math.min(100, 5 - EnemyGap(over, defense) * 0.04))
end

local function EnemyCritChance(over, defense)
    return math.max(0, math.min(100, 5 + EnemyGap(over, defense) * 0.04))
end

local function EnemyCrushChance(over, defense)
    local gap = EnemyGap(over, math.min(defense, UnitLevel("player") * SKILL_PER_LEVEL))
    if gap < 15 then return 0 end
    return math.max(0, math.min(100, gap * 2 - 15))
end

-- "40/45", yellow while it's below the cap.
local function SkillText(cur, max)
    local text = cur .. "/" .. max
    if cur < max then return "|cffffd040" .. text .. "|r" end
    return text
end

local function WeaponText(min, max, speed)
    min, max, speed = N(min), N(max), N(speed)
    if speed <= 0 then return false end
    local dps = (min + max) / 2 / speed
    return string.format("%d-%d  %s%.2fs|r  %s%.1f|r dps",
        math.max(1, math.floor(min)), math.max(1, math.ceil(max)), GREY, speed, WHITE, dps)
end

local function WeaponTip(tt, min, max, speed, ap)
    min, max, speed = N(min), N(max), N(speed)
    Line(tt, "Damage", string.format("%d - %d", math.max(1, math.floor(min)), math.max(1, math.ceil(max))))
    Line(tt, "Average hit", string.format("%.1f", (min + max) / 2))
    Line(tt, "Speed", string.format("%.2f s", speed))
    Line(tt, "Damage per second", string.format("%.1f", (min + max) / 2 / speed))
    Line(tt, " ")
    if ap then
        Line(tt, string.format("Includes %.1f dps from attack power.", N(ap) / AP_PER_DPS))
    end
    Line(tt, "|cff8c8c8cWorked out from the exact damage. The game's own sheet rounds the damage "
        .. "first, so its DPS can read a little lower.|r")
end

local function MeleeAP()
    local base, pos, neg = UnitAttackPower("player")
    return N(base) + N(pos) + N(neg), N(pos), N(neg)
end

local function RangedAP()
    local base, pos, neg = UnitRangedAttackPower("player")
    return N(base) + N(pos) + N(neg), N(pos), N(neg)
end

local function APText(total, pos, neg)
    return Tinted(Num(total), pos, neg), false, string.format("+%.1f dps", total / AP_PER_DPS)
end

local function Haste(v) return Pct(v), N(v) == 0 end

local melee = {
    key = "melee", title = "Melee", colorKey = "Attack",
    cells = {
        { label = "Main Hand", wide = true, get = function()
            local min, max = UnitDamage("player")
            return WeaponText(min, max, (UnitAttackSpeed("player")))
        end, tip = function(tt)
            local min, max = UnitDamage("player")
            WeaponTip(tt, min, max, (UnitAttackSpeed("player")), (MeleeAP()))
        end },
        { label = "Off Hand", wide = true, get = function()
            local _, offSpeed = UnitAttackSpeed("player")
            if not offSpeed then return false end
            local _, _, min, max = UnitDamage("player")
            return WeaponText(min, max, offSpeed)
        end, tip = function(tt)
            local _, offSpeed = UnitAttackSpeed("player")
            local _, _, min, max = UnitDamage("player")
            WeaponTip(tt, min, max, offSpeed, (MeleeAP()))
        end },
        { label = "Attack Power", wide = true, get = function() return APText(MeleeAP()) end,
          tip = function(tt)
            local total = MeleeAP()
            Line(tt, string.format("Adds %.1f damage per second to your melee weapons.", total / AP_PER_DPS))
        end },
        { label = "Crit", get = function() return Pct(GetCritChance()) end },
        { label = "Hit", get = function()
            if not GetHitModifier then return false end
            local v = GetHitModifier() or 0
            return "+" .. Pct(v), N(v) == 0
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
    return N(haste) + N(quiver or 0)
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
            local speed, min, max = UnitRangedDamage("player")
            return WeaponText(min, max, speed)
        end, tip = function(tt)
            local speed, min, max = UnitRangedDamage("player")
            WeaponTip(tt, min, max, speed, (RangedAP()))
        end },
        { label = "Attack Power", wide = true, get = function() return APText(RangedAP()) end },
        { label = "Crit", get = function() return Pct(GetRangedCritChance()) end },
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
local function BestSchool(fn)
    local best, same, first = nil, true, nil
    for _, s in ipairs(SCHOOLS) do
        local v = N(fn(s[1]))
        if first == nil then first = v elseif v ~= first then same = false end
        if not best or v > best then best = v end
    end
    return best, same
end

local function SchoolTip(tt, fn, fmt)
    local _, same = BestSchool(fn)
    if same then return end
    for _, s in ipairs(SCHOOLS) do
        Line(tt, "|cff" .. s[3] .. s[2] .. "|r", fmt(fn(s[1])))
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
            return "+" .. Num(best), best == 0
        end, tip = function(tt)
            Line(tt, "Bonus damage to your spells.")
            SchoolTip(tt, GetSpellBonusDamage, function(v) return "+" .. Num(v) end)
        end },
        { label = "Healing", get = function()
            if not GetSpellBonusHealing then return false end
            local v = N(GetSpellBonusHealing())
            return "+" .. Num(v), v == 0
        end },
        { label = "Crit", get = function() return Pct((BestSchool(GetSpellCritChance))) end,
          tip = function(tt) SchoolTip(tt, GetSpellCritChance, Pct) end },
        { label = "Hit", get = function()
            if not GetSpellHitModifier then return false end
            local v = GetSpellHitModifier() or 0
            return "+" .. Pct(v), N(v) == 0
        end },
        { label = "Haste", get = function()
            if not UnitSpellHaste then return false end
            return Haste(UnitSpellHaste("player"))
        end },
        -- GetManaRegen gives mana per second: out of combat-casting, and while casting.
        { label = "Mana Regen", wide = true, get = function()
            if not GetManaRegen then return false end
            local base, casting = GetManaRegen()
            base = N(base)
            local text = string.format("%s %smp5|r   %s %swhile casting|r",
                Dec(base * 5), GREY, Dec(N(casting) * 5), GREY)
            -- A tick when the regen meter (Regen.lua) agrees within 10%, else what it measured.
            local measured = ns.Regen and ns.Regen:Rate("rest")
            if measured and base > 0 then
                if math.abs(measured - base) <= base * 0.1 then
                    text = text .. " |TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
                else
                    text = string.format("%s |cffffd040(%s measured)|r", text, Dec(measured * 5))
                end
            end
            return text
        end, tip = function(tt)
            Line(tt, "Mana every 5 seconds: the first after 5 seconds without casting, "
                .. "the second while you keep casting.")
            Line(tt, "|cff8c8c8cThe game's own sheet rounds this down (37.5 shows as 37).|r")
            Line(tt, " ")
            local rate, ticks, secs = ns.Regen:Rate("rest")
            if rate then
                Line(tt, "Measured", string.format("%.1f mp5 (%d ticks, %ds)", rate * 5, ticks, secs))
            else
                Line(tt, "Not measured yet: spend some mana, then wait without casting until it's "
                    .. "back up. A tick means the game's number checked out.")
            end
            local cRate, cTicks, cSecs = ns.Regen:Rate("casting")
            if cRate then
                Line(tt, "Measured while casting", string.format("%.1f mp5 (%d ticks, %ds)", cRate * 5, cTicks, cSecs))
            elseif ns.Regen:NoneWhileCasting() then
                Line(tt, "Measured while casting", "none")
            end
        end },
    },
}

------------------------------------------------------------------------------
-- Defense
------------------------------------------------------------------------------

-- The share of a physical hit armor takes off, against an enemy of your level (plus `over`).
-- Forever's client works it out (C_PaperDollInfo.GetArmorEffectiveness gave 24.20% for 372 armor
-- at level 9, as its own sheet says); Classic's rule, which it matches, is the fallback.
local function ArmorReduction(armor, over)
    local level = UnitLevel("player") + (over or 0)
    local api = C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectiveness
    if api then
        local ok, r = pcall(api, armor, level)
        if ok and type(r) == "number" and not issecret(r) then return r end
    end
    local r = armor / (armor + 400 + 85 * level)
    return math.min(0.75, math.max(0, r))
end

local RESISTS = { { 2, "Fire", "ff8040" }, { 3, "Nat", "4cff4c" }, { 4, "Frost", "80d0ff" },
    { 5, "Shad", "b080ff" }, { 6, "Arc", "ff80ff" } }

local defense = {
    key = "defense", title = "Defense", colorKey = "Defense",
    cells = {
        { label = ARMOR or "Armor", wide = true, get = function()
            local _, effective, _, pos, neg = UnitArmor("player")
            effective = N(effective)
            return Tinted(Num(effective), pos and N(pos), neg and N(neg)), false,
                string.format("%.1f%% damage reduction", ArmorReduction(effective) * 100)
        end, tip = function(tt)
            local _, effective = UnitArmor("player")
            effective = N(effective)
            Line(tt, "Physical damage taken off, by enemy level:")
            local level = UnitLevel("player")
            for over = 0, 3 do
                Line(tt, "Level " .. (level + over), string.format("%.2f%%", ArmorReduction(effective, over) * 100))
            end
            Line(tt, "|cff8c8c8cArmor can't take off more than 75%.|r")
        end },
        { label = "Dodge", get = function() return Pct(GetDodgeChance()) end },
        { label = "Parry", get = function()
            local v = N(GetParryChance())
            return Pct(v), v == 0
        end },
        { label = "Block", get = function()
            local v = N(GetBlockChance())
            return Pct(v), v == 0
        end },
        { label = "Resist", wide = true, get = function()
            local parts, any = {}, false
            for _, r in ipairs(RESISTS) do
                local _, total = UnitResistance("player", r[1])
                total = N(total)
                if total ~= 0 then any = true end
                parts[#parts + 1] = string.format("|cff%s%s|r %d", r[3], r[2], total)
            end
            return table.concat(parts, "  "), not any
        end },
    },
}

------------------------------------------------------------------------------
-- What the numbers add up to, by the rules in Forever's own interface code
-- (Camelot/PaperDollFrameStats.lua and Camelot/SkillsFrame.lua).
------------------------------------------------------------------------------

local function ArmorNow()
    local _, effective = UnitArmor("player")
    return N(effective)
end

local function MeleeHit()
    return GetHitModifier and N(GetHitModifier() or 0) or 0
end

-- Your main hand's paper DPS, plus the off hand's when dual wielding.
local function PaperDPS()
    local min, max, offMin, offMax = UnitDamage("player")
    local speed, offSpeed = UnitAttackSpeed("player")
    local dps = (N(min) + N(max)) / 2 / N(speed)
    if offSpeed then dps = dps + (N(offMin) + N(offMax)) / 2 / N(offSpeed) end
    return dps
end

-- Forever's tables for an enemy 0-3 levels up, for a capped weapon skill: your chance to miss
-- it, and its chance to dodge you.
local MELEE_MISS = { [0] = 5.0, 5.2, 5.4, 9.0 }
local ENEMY_DODGE = { [0] = 5.0, 5.5, 6.0, 6.5 }

local function SkillShort(skill)
    return math.max(0, UnitLevel("player") * SKILL_PER_LEVEL - skill)
end

-- The hit chance that means never missing an enemy `over` levels up.
local function HitNeeded(over)
    local level = UnitLevel("player")
    local skill = WeaponSkill(INVSLOT_MAINHAND or 16) or level * SKILL_PER_LEVEL
    local _, offSpeed = UnitAttackSpeed("player")
    return MELEE_MISS[over] + SkillShort(skill) * 0.04 + (offSpeed and 19 or 0)
end

-- Where your auto-attacks go against an enemy `over` levels up, in the game's order: misses,
-- dodges, glancing blows, crits, and ordinary hits from what's left. Percentages, plus `mult`:
-- the share of paper DPS they add up to (glancing blows land for less, crits for double).
local function SwingTable(over)
    local level = UnitLevel("player")
    local skill = WeaponSkill(INVSLOT_MAINHAND or 16) or level * SKILL_PER_LEVEL
    local left = 100
    local function take(v)
        v = math.max(0, math.min(left, v))
        left = left - v
        return v
    end
    local t = {}
    t.miss = take(HitNeeded(over) - MeleeHit())
    t.dodge = take(ENEMY_DODGE[over] + SkillShort(skill) * 0.04)
    t.glance = take(GlancingChance(over, skill))
    t.glancePenalty = GlancingPenalty(over, skill)
    t.crit = take(N(GetCritChance()) - SkillGap(over, skill) * 0.04)
    t.hit = left
    t.mult = (t.hit + t.crit * 2 + t.glance * (1 - t.glancePenalty / 100)) / 100
    return t
end

-- What happens to an enemy's swing at you, `over` levels up: misses, your dodges, parries and
-- blocks (each level up takes 0.2% off those), its crits and crushing blows, and plain hits.
local function IncomingTable(over)
    local def = DefenseSkill() or UnitLevel("player") * SKILL_PER_LEVEL
    local drop = over * SKILL_PER_LEVEL * 0.04
    local left = 100
    local function take(v)
        v = math.max(0, math.min(left, v))
        left = left - v
        return v
    end
    local parry, block = N(GetParryChance()), N(GetBlockChance())
    local t = {}
    t.miss = take(EnemyMissChance(over, def))
    t.dodge = take(N(GetDodgeChance()) - drop)
    t.parry = take(parry > 0 and parry - drop or 0)
    t.block = take(block > 0 and block - drop or 0)
    t.crit = take(EnemyCritChance(over, def))
    t.crush = take(EnemyCrushChance(over, def))
    t.hit = left
    return t
end

-- Spells miss an enemy 0-3 levels up 4 / 5 / 6 / 17% of the time, less your spell hit.
local SPELL_MISS = { [0] = 4, 5, 6, 17 }
local function SpellMiss(over)
    local hit = GetSpellHitModifier and N(GetSpellHitModifier() or 0) or 0
    return math.max(0, SPELL_MISS[over] - hit)
end

------------------------------------------------------------------------------
-- Caps: the things with a ceiling worth reaching.
------------------------------------------------------------------------------

local caps = {
    key = "caps", title = "Caps", colorKey = "Insights",
    cells = {
        -- Weapon skill, named for the weapon ("Two-Handed Maces 41/45"), with what being short
        -- of the cap costs.
        { label = function()
            local _, _, name = WeaponSkill(INVSLOT_MAINHAND or 16)
            return name or "Weapon Skill"
        end, wide = true, get = function()
            local cur, max = WeaponSkill(INVSLOT_MAINHAND or 16)
            if not cur then return false end
            local gap = SkillGap(0, cur)
            local note = gap > 0 and string.format("%d short: -%s hit and crit, rises as you fight", gap, Pct(gap * 0.04)) or nil
            return SkillText(cur, max), false, note, cur / max
        end, tip = function(tt)
            local cur, max, name = WeaponSkill(INVSLOT_MAINHAND or 16)
            if not cur then return end
            local oc, om, oname = WeaponSkill(INVSLOT_OFFHAND or 17)
            if oc and oname ~= name then Line(tt, oname, oc .. " / " .. om) end
            local function signed(v) return string.format("%+.2f%%", v == 0 and 0 or v) end
            Line(tt, " ")
            Line(tt, "|cffffffffAgainst an enemy of your level|r")
            Line(tt, "Hit, and not dodged or parried", signed(-SkillGap(0, cur) * 0.04))
            Line(tt, "Critical hits", signed(-SkillGap(0, cur) * 0.04))
            Line(tt, " ")
            Line(tt, "|cffffffffAgainst raid bosses|r")
            Line(tt, "Hit, and not dodged or parried", signed(-SkillGap(3, cur) * 0.04))
            Line(tt, "Critical hits", signed(-SkillGap(3, cur) * 0.04))
            Line(tt, "Glancing blows", string.format("%.0f%% of hits, for %.0f%% less",
                GlancingChance(3, cur), GlancingPenalty(3, cur)))
            Line(tt, " ")
            Line(tt, "|cff8c8c8cRises as you fight with this kind of weapon. Forever's own rules: "
                .. "0.04% per point short of the enemy's defense (its level x 5).|r")
        end },
        -- Defense skill, out of your level x 5. Short of that, enemies of your level hit and crit
        -- you a little more; above it (gear), Forever adds 0.04% avoidance per point.
        { label = DEFENSE or "Defense", wide = true, get = function()
            local cur, max = DefenseSkill()
            if not cur then return false end
            local note
            if cur < max then
                note = string.format("%d short: enemies hit and crit you %s more", max - cur, Pct((max - cur) * 0.04))
            elseif cur > max then
                note = string.format("+%s avoidance, %s fewer crits taken", Pct((cur - max) * 0.04), Pct((cur - max) * 0.04))
            end
            return SkillText(cur, max), false, note, math.min(1, cur / max)
        end, tip = function(tt)
            local cur = DefenseSkill()
            Line(tt, "By enemy level:")
            local level = UnitLevel("player")
            for over = 0, 3 do
                local crush = EnemyCrushChance(over, cur)
                Line(tt, string.format("Level %d%s", level + over, over == 3 and " (raid boss)" or ""),
                    string.format("misses %.1f%%  crits %.1f%%%s", EnemyMissChance(over, cur),
                        EnemyCritChance(over, cur), crush > 0 and string.format("  crushes %.0f%%", crush) or ""))
            end
            Line(tt, " ")
            Line(tt, "|cff8c8c8cCritical hits from creatures deal double damage; crushing blows deal 150%. "
                .. "Rises as you take hits.|r")
        end },
        -- Melee hit against the hit that means never missing a same-level enemy.
        { label = "Hit Chance", wide = true, get = function()
            local hit, need = MeleeHit(), HitNeeded(0)
            return string.format("%s of %s", Pct(hit), Pct(need)), false,
                string.format("%s means melee never misses a level %d enemy", Pct(need), UnitLevel("player")),
                math.min(1, hit / need)
        end, tip = function(tt)
            Line(tt, "Hit needed to never miss with melee:")
            local level = UnitLevel("player")
            for over = 0, 3 do
                Line(tt, string.format("Level %d%s", level + over, over == 3 and " (raid boss)" or ""), Pct(HitNeeded(over)))
            end
            Line(tt, " ")
            Line(tt, "|cff8c8c8cIncludes your weapon skill. Forever's own hit tooltip rounds the raid boss figure to 8%.|r")
        end },
    },
}

------------------------------------------------------------------------------
-- For Tabs.lua, Tracker.lua and Compare.lua.
------------------------------------------------------------------------------

ns.R = {
    N = N, Num = Num, Pct = Pct, Dec = Dec, Tinted = Tinted, Line = Line, Class = Class,
    UsesMana = UsesMana, DisplayPower = DisplayPower, Durability = Durability,
    GearTotals = GearTotals, GearSummary = GearSummary, GEAR_STATS = GEAR_STATS,
    StatAP = StatAP, Call = Call, BestSchool = BestSchool, ArmorReduction = ArmorReduction,
    ArmorNow = ArmorNow, WeaponSkill = WeaponSkill, DefenseSkill = DefenseSkill,
    MeleeAP = MeleeAP, MeleeHit = MeleeHit, PaperDPS = PaperDPS, SwingTable = SwingTable,
    IncomingTable = IncomingTable, SpellMiss = SpellMiss, HitNeeded = HitNeeded,
    AP_PER_DPS = AP_PER_DPS, SKILL_PER_LEVEL = SKILL_PER_LEVEL,
}

ns.S = {
    attributes = attributes, caps = caps, melee = melee, ranged = ranged, spell = spell,
    defense = defense, general = general,
}

-- Every section, for the audit.
ns.Sections = { attributes, caps, melee, ranged, spell, defense, general }

-- Events that can change something the panel shows. Unit events are for the player only.
ns.UnitEvents = {
    "UNIT_STATS", "UNIT_ATTACK_SPEED", "UNIT_DAMAGE", "UNIT_RANGEDDAMAGE", "UNIT_ATTACK_POWER",
    "UNIT_RANGED_ATTACK_POWER", "UNIT_RESISTANCES", "UNIT_AURA", "UNIT_MAXHEALTH", "UNIT_MAXPOWER",
    "UNIT_DISPLAYPOWER", "UNIT_INVENTORY_CHANGED", "UNIT_DEFENSE", "UNIT_LEVEL",
}
ns.Events = {
    "PLAYER_EQUIPMENT_CHANGED", "COMBAT_RATING_UPDATE", "SPELL_POWER_CHANGED",
    "PLAYER_DAMAGE_DONE_MODS", "UPDATE_INVENTORY_DURABILITY", "UPDATE_SHAPESHIFT_FORM",
    "SKILL_LINES_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_TALENT_UPDATE",
    "CHARACTER_POINTS_CHANGED",
}
