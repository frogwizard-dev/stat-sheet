local _, ns = ...

-- Before you equip: on an item's tooltip, what wearing it instead of what's in that slot would do
-- to your real DPS, effective health, spell power, mana and regen, by the same rules as the sheet.
-- The items' own stats only (C_Item.GetItemStats): enchants on what you wear now are ignored.

local Stats = ns.Stats
local Talents = ns.Talents -- what talents and buffs make a stat on an item worth

-- Reading an item's stats and where it would go: FrogLib.Tank (shared with other add-ons).
local Tank = FrogLib.Tank

-- Who can wear what, Classic's rules: armor by its subclass, weapons by theirs. Mail and plate
-- count for the classes that learn them at 40, so they're compared before then too.
local ARMOR_CLASSES = {
    [2] = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, SHAMAN = true, DRUID = true }, -- leather
    [3] = { WARRIOR = true, PALADIN = true, HUNTER = true, SHAMAN = true },                             -- mail
    [4] = { WARRIOR = true, PALADIN = true },                                                           -- plate
    [6] = { WARRIOR = true, PALADIN = true, SHAMAN = true },                                            -- shields
    [7] = { PALADIN = true }, [8] = { DRUID = true }, [9] = { SHAMAN = true },                          -- librams, idols, totems
}
local function Set(...)
    local set = {}
    for _, value in ipairs({ ... }) do set[value] = true end
    return set
end
-- Weapon subclasses: 0/1 axes, 2 bows, 3 guns, 4/5 maces, 6 polearms, 7/8 swords, 10 staves,
-- 13 fist weapons, 15 daggers, 16 thrown, 18 crossbows, 19 wands. Others (14, 20) anyone.
local WEAPON_CLASSES = {
    WARRIOR = Set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18),
    PALADIN = Set(0, 1, 4, 5, 6, 7, 8),
    HUNTER = Set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18),
    ROGUE = Set(2, 3, 4, 7, 13, 15, 16, 18),
    PRIEST = Set(4, 10, 15, 19),
    SHAMAN = Set(0, 1, 4, 5, 10, 13, 15),
    MAGE = Set(7, 10, 15, 19),
    WARLOCK = Set(7, 10, 15, 19),
    DRUID = Set(4, 5, 10, 13, 15),
}
local ANYONE_WEAPON = { [14] = true, [20] = true }

local function CanWear(link)
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
    local class = Stats.Class()
    if classID == ((Enum.ItemClass and Enum.ItemClass.Armor) or 4) then
        local who = ARMOR_CLASSES[subclassID]
        return not who or who[class] == true
    elseif classID == ((Enum.ItemClass and Enum.ItemClass.Weapon) or 2) then
        local can = WEAPON_CLASSES[class]
        return not can or ANYONE_WEAPON[subclassID] or can[subclassID] == true
    end
    return true
end

local WAND = 19

-- The stat on you now and with the item's `change`, which talents and buffs raise by their share.
local function StatAfter(statIndex, change)
    local _, stat = UnitStat("player", statIndex)
    return Stats.Known(stat), Stats.Known(stat) + change * Talents.StatScale(statIndex)
end

-- An item's bonus healing: its +healing, or its "damage and healing" spell power, whichever the game
-- lists (some list a "damage and healing" item as both spell damage and healing, some as spell power).
local function ItemHealing(link)
    local stats = link and C_Item.GetItemStats(link) or {}
    return math.max(tonumber(stats.ITEM_MOD_SPELL_HEALING_DONE_SHORT) or 0, tonumber(stats.ITEM_MOD_SPELL_POWER_SHORT) or 0)
end

-- The changes, as { label, text, good } lines.
-- `old` is one link or { [slot] = link } for everything it replaces (a two-hander: both hands).
local function Changes(newLink, old, slot)
    -- diff.dps: weapon DPS per hand; the off hand hits for half (as the game's own numbers do).
    local diff, _, _, new = Tank.Diff(newLink, old, slot)
    local lines = {}
    local class = Stats.Class()
    -- A druid in cat or bear form fights with its paws: the weapon's own damage doesn't count.
    if class == "DRUID" and Stats.DisplayPower() ~= 0 then diff.dps = 0 end
    local function Add(label, value, template, suffix)
        -- Whole numbers are rounded, so a fraction doesn't show as "+0" or 2.8 as "+2".
        if template == "%+d" then value = math.floor(value + 0.5) end
        if math.abs(value) < 0.05 then return end
        lines[#lines + 1] = { label, string.format(template, value) .. (suffix or ""), value > 0 }
    end

    -- Real DPS: weapon damage, attack power (items, Strength/Agility, Intellect with Mental
    -- Dexterity or Careful Aim), crit from Agility.
    local paper = Stats.PaperDPS()
    local swings = Stats.SwingTable(0)
    local strengthNow, strengthNew = StatAfter(1, diff.str)
    local agilityNow, agilityNew = StatAfter(2, diff.agi)
    local intellectNow, intellectNew = StatAfter(4, diff.int)
    local intellectAP, intellectRAP = Talents.IntAPChange(intellectNow, intellectNew)
    local apChange = diff.ap + ((Stats.StatAP(1, strengthNew) or 0) - (Stats.StatAP(1, strengthNow) or 0))
        + ((Stats.StatAP(2, agilityNew) or 0) - (Stats.StatAP(2, agilityNow) or 0)) + intellectAP
    local critNow = Stats.Call(GetCritChanceFromStat, 2, agilityNow) or 0
    local critNew = Stats.Call(GetCritChanceFromStat, 2, agilityNew) or 0
    local paperChange = diff.dps + apChange / Stats.AP_PER_DPS
    local realChange = paperChange * swings.mult + (paper + paperChange) * (critNew - critNow)
    Add(class == "HUNTER" and "Melee DPS" or "Real DPS", realChange, "%+.1f")

    -- The ranged slot: a wand's own damage; a hunter's shots, with ranged attack power from
    -- Agility and items, and crit.
    local oldRanged = slot == (INVSLOT_RANGED or 18) and Tank.ItemStats(type(old) == "table" and old[slot] or old) or nil
    local newSub = select(7, C_Item.GetItemInfoInstant(newLink))
    if oldRanged and newSub == WAND then
        Add("Wand DPS", new.dps - oldRanged.dps, "%+.1f")
    elseif class == "HUNTER" and Stats.HasRangedWeapon() then
        local rangedPaper = Stats.RangedPaperDPS()
        local shots = Stats.ShotTable(0)
        local weaponChange = oldRanged and (new.dps - oldRanged.dps) or 0
        local rapChange = diff.ap + (diff.rap or 0) + Stats.StatRAP(2, agilityNew) - Stats.StatRAP(2, agilityNow)
            + intellectRAP
        local rangedChange = weaponChange + rapChange / Stats.AP_PER_DPS
        Add("Ranged DPS", rangedChange * shots.mult + (rangedPaper + rangedChange) * (critNew - critNow), "%+.1f")
    end

    -- Effective health: Stamina (and talents raising health), armor (items, with Toughness or a
    -- bear's or moonkin's share; Agility; Intellect with Arcane Resilience).
    local health = Stats.Known(UnitHealthMax("player"))
    local armor = Stats.ArmorNow()
    local staminaNow, staminaNew = StatAfter(3, diff.sta)
    local perPoint = Stats.Call(UnitHPPerStamina, "player") or 10
    local healthChange = (staminaNew - staminaNow) * perPoint * Talents.HealthScale()
    local newArmor = armor + diff.armor * Talents.ItemArmorScale() + (agilityNew - agilityNow) * 2
        + (intellectNew - intellectNow) * Talents.IntToArmor()
    local ehpNow = health / (1 - Stats.ArmorReduction(armor))
    local ehpNew = (health + healthChange) / (1 - Stats.ArmorReduction(newArmor))
    if ehpNow > 0 then
        Add("Effective health", ehpNew - ehpNow, "%+d", string.format(" (%+.0f%%)", (ehpNew / ehpNow - 1) * 100))
    end

    -- Spell power and healing: the item's, and Spirit's and Intellect's shares (Spiritual Guidance,
    -- Mental Quickness, Champion of the Light, Natural Instinct).
    local spiritNow, spiritNew = StatAfter(5, diff.spi)
    local spiritChange, intellectChange = spiritNew - spiritNow, intellectNew - intellectNow
    local spiritDamage, spiritHeal = Talents.SpiritToSpell()
    local intellectDamage, intellectHeal = Talents.IntToSpell()
    local itemHealing = ItemHealing(newLink)
    for _, link in pairs(type(old) == "table" and old or { old }) do itemHealing = itemHealing - ItemHealing(link) end
    local spellChange = diff.sp + spiritChange * spiritDamage + intellectChange * intellectDamage
    local healChange = itemHealing + spiritChange * spiritHeal + intellectChange * intellectHeal
    Add("Spell power", spellChange, "%+d")
    -- Healing gets its own line when it moves differently from spell power (+healing gear).
    if math.floor(healChange + 0.5) ~= math.floor(spellChange + 0.5) then Add("Healing", healChange, "%+d") end
    if Stats.UsesMana() then
        local first = INTELLECT_BREAK or 20
        local function Mana(intellect)
            return math.min(first, intellect) + math.max(0, intellect - first) * (MANA_PER_INTELLECT or 15)
        end
        Add("Mana", (Mana(intellectNew) - Mana(intellectNow)) * Talents.ManaScale(), "%+d")
        local fromSpirit = Stats.Call(GetManaRegenFromSpirit)
        local regenChange = diff.mp5
        if fromSpirit and spiritNow > 0 then
            regenChange = regenChange + fromSpirit * 5 / spiritNow * spiritChange
        end
        Add("Mana regen", regenChange, "%+.1f", " mp5")
    end
    return lines
end

local function OnTooltip(tooltip)
    if not (ns.db and ns.db.compare) then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local added = false
    local ok = pcall(function()
        local _, link = tooltip:GetItem()
        if not link then return end
        -- Not cached yet: its stats would read as nothing, and the old item as all loss.
        if not C_Item.GetItemInfo(link) then return end
        -- Armor or a weapon your class can never use.
        if not CanWear(link) then return end
        -- Hovering one of your own slots on the character sheet.
        local owner = tooltip:GetOwner()
        local ownerName = owner and owner.GetName and owner:GetName()
        if type(ownerName) == "string" and ownerName:match("^Character.+Slot$") then return end
        local equipped = C_Item.IsEquippedItem(link)
        local replacements
        if ns.db.compareBoth == false then
            local slot, old, names = Tank.Replaced(link)
            replacements = slot and { { slot = slot, old = old, names = names } } or {}
        else
            -- A ring or trinket with both worn: a block for each.
            replacements = Tank.ReplacedEach(link)
        end
        if #replacements == 0 then return end
        -- A copy of something you wear: only worth comparing when it could go in the other ring
        -- or trinket slot instead.
        if equipped and #replacements < 2 then return end
        added = true
        -- The same item in both slots: say which is which.
        local same = #replacements > 1 and replacements[1].names[1] == replacements[2].names[1]
        for i, replacement in ipairs(replacements) do
            local lines = Changes(link, replacement.old, replacement.slot)
            local oldName = #replacement.names > 0 and table.concat(replacement.names, " + ") or nil
            if oldName and same then oldName = oldName .. (i == 1 and " (first)" or " (second)") end
            tooltip:AddLine(" ")
            tooltip:AddLine(oldName and ("StatSheet: instead of " .. oldName) or "StatSheet: in an empty slot", 1, 0.78, 0.25)
            if #lines == 0 then
                tooltip:AddLine("No change to your stats", 0.6, 0.6, 0.6)
            end
            for _, line in ipairs(lines) do
                local color = line[3] and ns.GOOD or ns.BAD
                tooltip:AddDoubleLine(line[1], line[2], 0.75, 0.75, 0.75, color[1], color[2], color[3])
            end
        end
    end)
    if ok and added then tooltip:Show() end
end

ns.CompareChanges = Changes -- for the test harness

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltip)
end
