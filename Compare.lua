local _, ns = ...

-- Before you equip: on an item's tooltip, what wearing it instead of what's in that slot would do
-- to your real DPS, effective health, spell power, mana and regen, by the same rules as the sheet.
-- The items' own stats only (C_Item.GetItemStats): enchants on what you wear now are ignored.

local R = ns.R

-- Reading an item's stats and where it would go: FrogLib.Tank (shared with other add-ons).
local T = FrogLib.Tank

local function StatAfter(i, delta)
    local _, v = UnitStat("player", i)
    return R.N(v), R.N(v) + delta
end

-- The changes, as { label, text, good } lines.
-- `old` is one link or { [slot] = link } for everything it replaces (a two-hander: both hands).
local function Changes(newLink, old, slot)
    -- d.dps: weapon DPS per hand; the off hand hits for half (as the game's own numbers do).
    local d = T.Diff(newLink, old, slot)
    local lines = {}
    local function add(label, value, fmt, suffix)
        if math.abs(value) < 0.05 then return end
        lines[#lines + 1] = { label, string.format(fmt, value) .. (suffix or ""), value > 0 }
    end

    -- Real DPS: weapon damage, attack power (items and Strength/Agility), crit from Agility.
    local paper = R.PaperDPS()
    local sw = R.SwingTable(0)
    local strNow, strNew = StatAfter(1, d.str)
    local agiNow, agiNew = StatAfter(2, d.agi)
    local dAP = d.ap + ((R.StatAP(1, strNew) or 0) - (R.StatAP(1, strNow) or 0))
        + ((R.StatAP(2, agiNew) or 0) - (R.StatAP(2, agiNow) or 0))
    local critNow = R.Call(GetCritChanceFromStat, 2, agiNow) or 0
    local critNew = R.Call(GetCritChanceFromStat, 2, agiNew) or 0
    local dPaper = d.dps + dAP / R.AP_PER_DPS
    local dReal = dPaper * sw.mult + (paper + dPaper) * (critNew - critNow)
    add("Real DPS", dReal, "%+.1f")

    -- Effective health: Stamina, armor (items and Agility).
    local hp = R.N(UnitHealthMax("player"))
    local armor = R.ArmorNow()
    local staNow, staNew = StatAfter(3, d.sta)
    local per = R.Call(UnitHPPerStamina, "player") or 10
    local dHP = (staNew - staNow) * per
    local newArmor = armor + d.armor + d.agi * 2
    local ehpNow = hp / (1 - R.ArmorReduction(armor))
    local ehpNew = (hp + dHP) / (1 - R.ArmorReduction(newArmor))
    if ehpNow > 0 then add("Effective health", ehpNew - ehpNow, "%+d", string.format(" (%+.0f%%)", (ehpNew / ehpNow - 1) * 100)) end

    add("Spell power", d.sp, "%+d")
    if d.heal > d.sp then add("Healing", d.heal, "%+d") end
    if R.UsesMana() then
        local intNow, intNew = StatAfter(4, d.int)
        local first = INTELLECT_BREAK or 20
        local function mana(v) return math.min(first, v) + math.max(0, v - first) * (MANA_PER_INTELLECT or 15) end
        add("Mana", mana(intNew) - mana(intNow), "%+d")
        local spiNow = select(2, UnitStat("player", 5))
        local fromSpirit = R.Call(GetManaRegenFromSpirit)
        local dRegen = d.mp5
        if fromSpirit and R.N(spiNow) > 0 then dRegen = dRegen + fromSpirit * 5 / R.N(spiNow) * d.spi end
        add("Mana regen", dRegen, "%+.1f", " mp5")
    end
    return lines
end

local function OnTooltip(tooltip)
    if not (ns.db and ns.db.compare) then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local ok = pcall(function()
        local _, link = tooltip:GetItem()
        if not link or C_Item.IsEquippedItem(link) then return end
        local each
        if ns.db.compareBoth == false then
            local slot, old, names = T.Replaced(link)
            each = slot and { { slot = slot, old = old, names = names } } or {}
        else
            -- A ring or trinket with both worn: a block for each.
            each = T.ReplacedEach(link)
        end
        if #each == 0 then return end
        -- The same item in both slots: say which is which.
        local same = #each > 1 and each[1].names[1] == each[2].names[1]
        for i, e in ipairs(each) do
            local lines = Changes(link, e.old, e.slot)
            local oldName = #e.names > 0 and table.concat(e.names, " + ") or nil
            if oldName and same then oldName = oldName .. (i == 1 and " (first)" or " (second)") end
            tooltip:AddLine(" ")
            tooltip:AddLine(oldName and ("StatSheet: instead of " .. oldName) or "StatSheet: in an empty slot", 1, 0.78, 0.25)
            if #lines == 0 then
                tooltip:AddLine("No change to your stats", 0.6, 0.6, 0.6)
            end
            for _, l in ipairs(lines) do
                local c = l[3] and ns.GOOD or ns.BAD
                local r, g, b = c[1], c[2], c[3]
                tooltip:AddDoubleLine(l[1], l[2], 0.75, 0.75, 0.75, r, g, b)
            end
        end
    end)
    if ok then tooltip:Show() end
end

ns.CompareChanges = Changes -- for the test harness

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltip)
end
