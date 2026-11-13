local _, ns = ...

-- Before you equip: on an item's tooltip, what wearing it instead of what's in that slot would do
-- to your real DPS, effective health, spell power, mana and regen, by the same rules as the sheet.
-- The items' own stats only (C_Item.GetItemStats): enchants on what you wear now are ignored.

local Stats = ns.Stats

-- Reading an item's stats and where it would go: FrogLib.Tank (shared with other add-ons).
local Tank = FrogLib.Tank

local function StatAfter(statIndex, change)
    local _, stat = UnitStat("player", statIndex)
    return Stats.Known(stat), Stats.Known(stat) + change
end

-- The changes, as { label, text, good } lines.
-- `old` is one link or { [slot] = link } for everything it replaces (a two-hander: both hands).
local function Changes(newLink, old, slot)
    -- diff.dps: weapon DPS per hand; the off hand hits for half (as the game's own numbers do).
    local diff = Tank.Diff(newLink, old, slot)
    local lines = {}
    local function Add(label, value, template, suffix)
        if math.abs(value) < 0.05 then return end
        lines[#lines + 1] = { label, string.format(template, value) .. (suffix or ""), value > 0 }
    end

    -- Real DPS: weapon damage, attack power (items and Strength/Agility), crit from Agility.
    local paper = Stats.PaperDPS()
    local swings = Stats.SwingTable(0)
    local strengthNow, strengthNew = StatAfter(1, diff.str)
    local agilityNow, agilityNew = StatAfter(2, diff.agi)
    local apChange = diff.ap + ((Stats.StatAP(1, strengthNew) or 0) - (Stats.StatAP(1, strengthNow) or 0))
        + ((Stats.StatAP(2, agilityNew) or 0) - (Stats.StatAP(2, agilityNow) or 0))
    local critNow = Stats.Call(GetCritChanceFromStat, 2, agilityNow) or 0
    local critNew = Stats.Call(GetCritChanceFromStat, 2, agilityNew) or 0
    local paperChange = diff.dps + apChange / Stats.AP_PER_DPS
    local realChange = paperChange * swings.mult + (paper + paperChange) * (critNew - critNow)
    Add("Real DPS", realChange, "%+.1f")

    -- Effective health: Stamina, armor (items and Agility).
    local health = Stats.Known(UnitHealthMax("player"))
    local armor = Stats.ArmorNow()
    local staminaNow, staminaNew = StatAfter(3, diff.sta)
    local perPoint = Stats.Call(UnitHPPerStamina, "player") or 10
    local healthChange = (staminaNew - staminaNow) * perPoint
    local newArmor = armor + diff.armor + diff.agi * 2
    local ehpNow = health / (1 - Stats.ArmorReduction(armor))
    local ehpNew = (health + healthChange) / (1 - Stats.ArmorReduction(newArmor))
    if ehpNow > 0 then
        Add("Effective health", ehpNew - ehpNow, "%+d", string.format(" (%+.0f%%)", (ehpNew / ehpNow - 1) * 100))
    end

    Add("Spell power", diff.sp, "%+d")
    if diff.heal > diff.sp then Add("Healing", diff.heal, "%+d") end
    if Stats.UsesMana() then
        local intellectNow, intellectNew = StatAfter(4, diff.int)
        local first = INTELLECT_BREAK or 20
        local function Mana(intellect)
            return math.min(first, intellect) + math.max(0, intellect - first) * (MANA_PER_INTELLECT or 15)
        end
        Add("Mana", Mana(intellectNew) - Mana(intellectNow), "%+d")
        local spirit = select(2, UnitStat("player", 5))
        local fromSpirit = Stats.Call(GetManaRegenFromSpirit)
        local regenChange = diff.mp5
        if fromSpirit and Stats.Known(spirit) > 0 then
            regenChange = regenChange + fromSpirit * 5 / Stats.Known(spirit) * diff.spi
        end
        Add("Mana regen", regenChange, "%+.1f", " mp5")
    end
    return lines
end

local function OnTooltip(tooltip)
    if not (ns.db and ns.db.compare) then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local ok = pcall(function()
        local _, link = tooltip:GetItem()
        if not link or C_Item.IsEquippedItem(link) then return end
        local replacements
        if ns.db.compareBoth == false then
            local slot, old, names = Tank.Replaced(link)
            replacements = slot and { { slot = slot, old = old, names = names } } or {}
        else
            -- A ring or trinket with both worn: a block for each.
            replacements = Tank.ReplacedEach(link)
        end
        if #replacements == 0 then return end
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
    if ok then tooltip:Show() end
end

ns.CompareChanges = Changes -- for the test harness

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltip)
end
