local _, ns = ...

-- The four tabs and what's on each: blocks the panel lays out top to bottom.
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
            { kind = "section", section = S.melee },
        }
    end
    local blocks = {
        { kind = "tiles", tiles = meleeTiles },
        { kind = "section", section = S.melee },
        { kind = "section", section = S.ranged },
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
            { kind = "changes", key = "changes", title = "Since you logged in", colorKey = "Attributes", limit = 8 },
            { kind = "section", section = S.general },
        },
    },
}
