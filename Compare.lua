local _, ns = ...

-- Before you equip: on an item's tooltip, what wearing it instead of what's in that slot would do
-- to your real DPS, effective health, spell power, mana and regen, by the same rules as the sheet.
-- The items' own stats only (C_Item.GetItemStats): enchants on what you wear now are ignored.

local R = ns.R

local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local KEYS = {
    str = "ITEM_MOD_STRENGTH_SHORT", agi = "ITEM_MOD_AGILITY_SHORT", sta = "ITEM_MOD_STAMINA_SHORT",
    int = "ITEM_MOD_INTELLECT_SHORT", spi = "ITEM_MOD_SPIRIT_SHORT", ap = "ITEM_MOD_ATTACK_POWER_SHORT",
    sp = "ITEM_MOD_SPELL_POWER_SHORT", spdmg = "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT",
    heal = "ITEM_MOD_SPELL_HEALING_DONE_SHORT", armor = "RESISTANCE0_NAME",
    dps = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", mp5 = "ITEM_MOD_POWER_REGEN0_SHORT",
    mp5b = "ITEM_MOD_MANA_REGENERATION_SHORT", crit = "ITEM_MOD_CRIT_RATING_SHORT", hit = "ITEM_MOD_HIT_RATING_SHORT",
}

local function Stats(link)
    local out = {}
    local stats = link and C_Item.GetItemStats(link) or {}
    for k, key in pairs(KEYS) do out[k] = tonumber(stats[key]) or 0 end
    out.sp = math.max(out.sp, out.spdmg)
    out.mp5 = out.mp5 + out.mp5b
    return out
end

-- The slot it would go in: an empty one if there is one, else the first.
local function TargetSlot(equipLoc)
    local slots = SLOTS[equipLoc]
    if not slots then return nil end
    for _, slot in ipairs(slots) do
        if not GetInventoryItemLink("player", slot) then return slot end
    end
    return slots[1]
end

local function StatAfter(i, delta)
    local _, v = UnitStat("player", i)
    return R.N(v), R.N(v) + delta
end

-- The changes, as { label, text, good } lines.
local function Changes(newLink, oldLink, slot)
    local new, old = Stats(newLink), Stats(oldLink)
    local d = {}
    for k in pairs(new) do d[k] = new[k] - old[k] end
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
    local dWeapon = (slot == (INVSLOT_MAINHAND or 16)) and d.dps or 0
    local dPaper = dWeapon + dAP / R.AP_PER_DPS
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
        local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
        local slot = TargetSlot(equipLoc)
        if not slot then return end
        local oldLink = GetInventoryItemLink("player", slot)
        local lines = Changes(link, oldLink, slot)
        local oldName = oldLink and (C_Item.GetItemInfo(oldLink) or oldLink:match("%[(.-)%]"))
        tooltip:AddLine(" ")
        tooltip:AddLine(oldName and ("StatSheet: instead of " .. oldName) or "StatSheet: in an empty slot", 1, 0.78, 0.25)
        if #lines == 0 then
            tooltip:AddLine("No change to your stats", 0.6, 0.6, 0.6)
        end
        for _, l in ipairs(lines) do
            local r, g, b = 0.31, 0.89, 0.42
            if not l[3] then r, g, b = 0.9, 0.33, 0.29 end
            tooltip:AddDoubleLine(l[1], l[2], 0.75, 0.75, 0.75, r, g, b)
        end
    end)
    if ok then tooltip:Show() end
end

ns.CompareChanges = Changes -- for the test harness

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltip)
end
