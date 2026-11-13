local _, ns = ...

-- What changed since you logged in: gear swaps, weapon and defense skill-ups and level-ups, each with
-- what it did to your stats, for this session only. A snapshot of the stats is quietly refreshed (buffs
-- coming and going aren't news); a gear, skill or level event compares against it and logs the difference.
-- Change = { time, icon, title, quality, sub, deltas = { { label, value } }, effects = { { label, text, good } } }.

local Stats = ns.Stats
local Tracker = {}
ns.Tracker = Tracker
ns.Changes = {} -- newest first

local MAX_CHANGES = 20
local TRACKED = {
    { "stat1", "Str" }, { "stat2", "Agi" }, { "stat3", "Sta" }, { "stat4", "Int" }, { "stat5", "Spi" },
    { "ap", "AP" }, { "sp", "SP" }, { "armor", "Armor" }, { "hp", "Health" }, { "mana", "Mana" },
}
local SLOTS = 19

-- Everything that's readable right now; a secret value (combat) leaves its field out.
local function Snapshot()
    local snapshot = { links = {} }
    local function Try(key, Read)
        local ok, value = pcall(Read)
        if ok and type(value) == "number" then snapshot[key] = value end
    end
    for i = 1, 5 do
        Try("stat" .. i, function() local _, stat = UnitStat("player", i) return Stats.Known(stat) end)
    end
    Try("armor", Stats.ArmorNow)
    Try("hp", function() return Stats.Known(UnitHealthMax("player")) end)
    Try("mana", function() return Stats.Known(UnitPowerMax("player", 0)) end)
    Try("ap", function() return (Stats.MeleeAP()) end)
    Try("sp", function() return (Stats.BestSchool(GetSpellBonusDamage)) end)
    Try("dps", function() return Stats.PaperDPS() * Stats.SwingTable(0).mult end)
    Try("ehp", function()
        local health = Stats.Known(UnitHealthMax("player"))
        return health / (1 - Stats.ArmorReduction(Stats.ArmorNow()))
    end)
    local ok, current, _, name = pcall(Stats.WeaponSkill, INVSLOT_MAINHAND or 16)
    if ok and current then snapshot.weapon, snapshot.weaponName = current, name end
    local okDefense, defense = pcall(Stats.DefenseSkill)
    if okDefense and defense then snapshot.defense = defense end
    for slot = 1, SLOTS do snapshot.links[slot] = GetInventoryItemLink("player", slot) end
    snapshot.level = UnitLevel("player")
    return snapshot
end

-- Every stat that moved, as { label, value }.
local function Deltas(old, new)
    local deltas = {}
    for _, stat in ipairs(TRACKED) do
        local before, after = old[stat[1]], new[stat[1]]
        local change = before and after and math.floor(after - before + 0.5) or 0
        if change ~= 0 then deltas[#deltas + 1] = { stat[2], change } end
    end
    return deltas
end

-- What it adds up to: real DPS and effective health.
local function Effects(old, new)
    local effects = {}
    if old.dps and new.dps and math.abs(new.dps - old.dps) >= 0.05 then
        local change = new.dps - old.dps
        effects[#effects + 1] = { "Real DPS", string.format("%+.1f", change), change > 0 }
    end
    if old.ehp and new.ehp and old.ehp > 0 and math.abs(new.ehp / old.ehp - 1) >= 0.005 then
        local change = (new.ehp / old.ehp - 1) * 100
        effects[#effects + 1] = { "Effective health", string.format("%+.0f%%", change), change > 0 }
    end
    return effects
end

local function ItemInfo(link)
    if not link then return nil end
    local name, _, quality = C_Item.GetItemInfo(link)
    local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(link)
    return name or link:match("%[(.-)%]") or "an item", quality, icon
end

local function Add(change)
    change.time = GetTime()
    table.insert(ns.Changes, 1, change)
    while #ns.Changes > MAX_CHANGES do table.remove(ns.Changes) end
    if ns.Panel and ns.Panel.frame and ns.Panel.frame:IsVisible() then ns.Panel:Queue() end
end

local base
local pending = {}   -- kinds of change waiting to be logged: slots (gear), level
local timers = {}

local function After(key, delay, Then)
    if timers[key] then timers[key]:Cancel() end
    timers[key] = C_Timer.NewTimer(delay, function()
        timers[key] = nil
        Then()
    end)
end

local function Names(links)
    local list = {}
    for _, link in ipairs(links) do list[#list + 1] = (ItemInfo(link)) end
    return table.concat(list, ", ")
end

-- A gear change: what went on (or came off), what it replaced, and what it did.
local function GearChange(now)
    local put, took = {}, {}
    for slot in pairs(pending.slots) do
        local new, old = now.links[slot], base.links and base.links[slot]
        if new and new ~= old then put[#put + 1] = new end
        if old and old ~= new then took[#took + 1] = old end
    end
    if #put == 0 and #took == 0 then return nil end
    local change = { deltas = Deltas(base, now), effects = Effects(base, now) }
    if #put > 0 then
        change.title, change.quality, change.icon = ItemInfo(put[1])
        if #put > 1 then change.title = Names(put) end
        if #took > 0 then change.sub = "replaced " .. Names(took) end
    else
        local _, quality, icon = ItemInfo(took[1])
        change.title, change.quality, change.icon = "Took off " .. Names(took), quality, icon
    end
    return change
end

-- Logs what's pending against the snapshot, then takes a new one.
local function Settle()
    local now = Snapshot()
    if base then
        if pending.level then
            Add({ title = "Reached level " .. now.level, icon = "Interface\\Icons\\Spell_ChargePositive",
                deltas = Deltas(base, now), effects = Effects(base, now) })
        elseif pending.slots then
            local change = GearChange(now)
            if change then Add(change) end
        end
        if base.weapon and now.weapon and base.weaponName == now.weaponName and now.weapon > base.weapon then
            local gain = (now.weapon - base.weapon) * 0.04
            Add({ title = string.format("%s %d", now.weaponName, now.weapon),
                icon = GetInventoryItemTexture("player", INVSLOT_MAINHAND or 16),
                sub = string.format("up from %d", base.weapon),
                effects = { { "Misses and dodges", "-" .. Stats.Percent(gain), true }, { "Crits", "+" .. Stats.Percent(gain), true } } })
        end
        if base.defense and now.defense and now.defense > base.defense then
            local gain = (now.defense - base.defense) * 0.04
            Add({ title = string.format("Defense %d", now.defense), icon = "Interface\\Icons\\Ability_Defend",
                sub = string.format("up from %d", base.defense),
                effects = { { "Enemies hit and crit you", "-" .. Stats.Percent(gain), true } } })
        end
    end
    pending = {}
    base = now
end

-- "just now", "4m ago", "1h ago".
function ns.Ago(when)
    local seconds = GetTime() - when
    if seconds < 60 then return "just now" end
    if seconds < 3600 then return string.format("%dm ago", seconds / 60) end
    return string.format("%dh ago", seconds / 3600)
end

local events = CreateFrame("Frame")
Tracker.frame = events -- for the test harness
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterUnitEvent("UNIT_STATS", "player")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:RegisterUnitEvent("UNIT_RESISTANCES", "player")
events:RegisterEvent("PLAYER_REGEN_ENABLED")

-- Buffs and the like: refresh the snapshot quietly once things settle. Not in combat, where
-- some numbers are hidden; one is taken when combat ends instead.
local quietPending = false
local function Quiet()
    if quietPending or InCombatLockdown() then return end
    quietPending = true
    C_Timer.After(1.5, function()
        quietPending = false
        if InCombatLockdown() then return end
        if not pending.slots and not pending.level then base = Snapshot() end
    end)
end

events:SetScript("OnEvent", function(_, event, slot)
    if event == "PLAYER_LOGIN" then
        After("settle", 2, function() base = Snapshot() end)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        pending.slots = pending.slots or {}
        pending.slots[slot] = true
        After("settle", 0.5, Settle)
    elseif event == "PLAYER_LEVEL_UP" then
        pending.level = true
        After("settle", 1.5, Settle)
    elseif event == "SKILL_LINES_CHANGED" then
        After("settle", 0.5, Settle)
    elseif not pending.slots and not pending.level then
        Quiet()
    end
end)
