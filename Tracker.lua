local _, ns = ...

-- What changed since you logged in: gear swaps, weapon and defense skill-ups and level-ups, each
-- with what it did to your stats. A snapshot of the stats is kept and quietly refreshed (buffs
-- coming and going aren't news); a gear, skill or level event compares against it and logs the
-- difference. For this session only.
--
-- Each change: { time, icon, title, quality (items), sub (what it replaced), deltas = { { label,
-- value } }, effects = { { label, text, good } } }, newest first in ns.Changes.

local R = ns.R
local Tracker = {}
ns.Tracker = Tracker
ns.Changes = {}

local MAX = 20
local STATS = {
    { "stat1", "Str" }, { "stat2", "Agi" }, { "stat3", "Sta" }, { "stat4", "Int" }, { "stat5", "Spi" },
    { "ap", "AP" }, { "sp", "SP" }, { "armor", "Armor" }, { "hp", "Health" }, { "mana", "Mana" },
}
local SLOTS = 19

-- Everything that's readable right now; a secret value (combat) just leaves its field out.
local function Snapshot()
    local s = { links = {} }
    local function try(key, fn)
        local ok, v = pcall(fn)
        if ok and type(v) == "number" then s[key] = v end
    end
    for i = 1, 5 do
        try("stat" .. i, function() local _, v = UnitStat("player", i) return R.N(v) end)
    end
    try("armor", R.ArmorNow)
    try("hp", function() return R.N(UnitHealthMax("player")) end)
    try("mana", function() return R.N(UnitPowerMax("player", 0)) end)
    try("ap", function() return (R.MeleeAP()) end)
    try("sp", function() return (R.BestSchool(GetSpellBonusDamage)) end)
    try("dps", function() return R.PaperDPS() * R.SwingTable(0).mult end)
    try("ehp", function()
        local hp = R.N(UnitHealthMax("player"))
        return hp / (1 - R.ArmorReduction(R.ArmorNow()))
    end)
    local ok, cur, _, name = pcall(R.WeaponSkill, INVSLOT_MAINHAND or 16)
    if ok and cur then s.weapon, s.weaponName = cur, name end
    local okD, def = pcall(R.DefenseSkill)
    if okD and def then s.defense = def end
    for slot = 1, SLOTS do s.links[slot] = GetInventoryItemLink("player", slot) end
    s.level = UnitLevel("player")
    return s
end

-- Every stat that moved, as { label, value }.
local function Deltas(old, new)
    local out = {}
    for _, s in ipairs(STATS) do
        local a, b = old[s[1]], new[s[1]]
        local d = a and b and math.floor(b - a + 0.5) or 0
        if d ~= 0 then out[#out + 1] = { s[2], d } end
    end
    return out
end

-- What it adds up to: real DPS and effective health.
local function Effects(old, new)
    local out = {}
    if old.dps and new.dps and math.abs(new.dps - old.dps) >= 0.05 then
        local d = new.dps - old.dps
        out[#out + 1] = { "Real DPS", string.format("%+.1f", d), d > 0 }
    end
    if old.ehp and new.ehp and old.ehp > 0 and math.abs(new.ehp / old.ehp - 1) >= 0.005 then
        local d = (new.ehp / old.ehp - 1) * 100
        out[#out + 1] = { "Effective health", string.format("%+.0f%%", d), d > 0 }
    end
    return out
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
    while #ns.Changes > MAX do table.remove(ns.Changes) end
    if ns.Panel and ns.Panel.frame and ns.Panel.frame:IsVisible() then ns.Panel:Queue() end
end

local base
local pending = {}   -- kinds of change waiting to be logged: slots (gear), level
local timers = {}

local function After(key, delay, fn)
    if timers[key] then timers[key]:Cancel() end
    timers[key] = C_Timer.NewTimer(delay, function()
        timers[key] = nil
        fn()
    end)
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
    local function names(links)
        local list = {}
        for _, link in ipairs(links) do list[#list + 1] = (ItemInfo(link)) end
        return table.concat(list, ", ")
    end
    if #put > 0 then
        change.title, change.quality, change.icon = ItemInfo(put[1])
        if #put > 1 then change.title = names(put) end
        if #took > 0 then change.sub = "replaced " .. names(took) end
    else
        local _, quality, icon = ItemInfo(took[1])
        change.title, change.quality, change.icon = "Took off " .. names(took), quality, icon
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
                effects = { { "Misses and dodges", "-" .. R.Pct(gain), true }, { "Crits", "+" .. R.Pct(gain), true } } })
        end
        if base.defense and now.defense and now.defense > base.defense then
            local gain = (now.defense - base.defense) * 0.04
            Add({ title = string.format("Defense %d", now.defense), icon = "Interface\\Icons\\Ability_Defend",
                sub = string.format("up from %d", base.defense),
                effects = { { "Enemies hit and crit you", "-" .. R.Pct(gain), true } } })
        end
    end
    pending = {}
    base = now
end

-- "just now", "4m ago", "1h ago".
function ns.Ago(t)
    local secs = GetTime() - t
    if secs < 60 then return "just now" end
    if secs < 3600 then return string.format("%dm ago", secs / 60) end
    return string.format("%dh ago", secs / 3600)
end

local f = CreateFrame("Frame")
Tracker.frame = f -- for the test harness
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("SKILL_LINES_CHANGED")
f:RegisterUnitEvent("UNIT_STATS", "player")
f:RegisterUnitEvent("UNIT_AURA", "player")
f:RegisterUnitEvent("UNIT_RESISTANCES", "player")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        After("settle", 2, function() base = Snapshot() end)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        pending.slots = pending.slots or {}
        pending.slots[arg1] = true
        After("settle", 0.5, Settle)
    elseif event == "PLAYER_LEVEL_UP" then
        pending.level = true
        After("settle", 1.5, Settle)
    elseif event == "SKILL_LINES_CHANGED" then
        After("settle", 0.5, Settle)
    elseif not pending.slots and not pending.level then
        -- Buffs and the like: refresh the snapshot quietly once things settle.
        After("quiet", 1.5, function()
            if not pending.slots and not pending.level then base = Snapshot() end
        end)
    end
end)
