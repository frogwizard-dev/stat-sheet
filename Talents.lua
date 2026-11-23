local _, ns = ...

-- Talents, forms and buffs the game's live numbers already count, but that change what a stat on an
-- item is worth, for the what-if sums (item tooltips, "What +10 of each gets you"): a stat raised by
-- a share (Divine Strength: +10 Strength on an item is +11 on you), Intellect or Spirit counted as
-- attack power, spell power or armor (Mental Dexterity, Spiritual Guidance, Arcane Resilience), and
-- item armor, health or mana raised by a share (Toughness, Bear Form, Survivalist, Fel Vitality).
-- The talents are the ones on Forever's own talent trees (TraitDefinition, TraitNode: _tools/casc.py).
-- Forever reuses a few Season of Discovery spells as talents (Mental Dexterity); other runes left in
-- its data are on no tree and so never count.
--
-- Forever's talents are a talent tree (C_Traits), each talent one spell whose numbers grow with its
-- rank, so the numbers come from the talent's description at your rank, read once and again after a
-- talent change. A talent whose numbers can't be read counts as not taken.

local Talents = {}
ns.Talents = Talents

local issecret = FrogLib.issecret

-- spell: the talent's spell (its trait definition's). Each other field names which number with a %
-- in its description, in order, is the share: stats = { [stat index] = n } always, bear / cat = the
-- same in that form; spiritDamage / spiritHeal, intDamage / intHeal = that share of Spirit /
-- Intellect as spell damage / healing; intAP / intRAP = that share of Intellect as melee / ranged
-- attack power; intArmor = that share of Intellect as armor; itemArmor, health, mana = armor from
-- items, maximum health, maximum mana up by that share; heal, healPeriodic, healInstant = all your
-- healing, healing over time, instant heals up by that share; healCrit = that much more crit on heals;
-- spellHeal / spellCrit = the same for the heals in `on` (their first ranks' spells, matched by name);
-- critBonus = a heal's crit bonus (half as much again) up by that share.
local TALENTS = {
    PALADIN = {
        { spell = 20262, stats = { [1] = 1 } },                -- Divine Strength
        { spell = 20257, stats = { [4] = 1 } },                -- Divine Intellect
        { spell = 20143, itemArmor = 1 },                      -- Toughness
        { spell = 1311084, intDamage = 1 },                    -- Champion of the Light
        -- Healing Light: Holy Light, Flash of Light, Holy Shock.
        { spell = 20237, spellHeal = 1, on = { 635, 19750, 20473 } },
        { spell = 5923, critBonus = 1 },                       -- Holy Power
    },
    DRUID = {
        -- Heart of the Wild: Intellect; Stamina in Bear Form, Strength in Cat Form.
        { spell = 17003, stats = { [4] = 1 }, bear = { [3] = 2 }, cat = { [1] = 3 } },
        { spell = 1309631, stats = { [5] = 1 } },              -- Living Spirit
        { spell = 1223242, intHeal = 2 },                      -- Natural Instinct (melee crit first)
        { spell = 17104, heal = 1 },                           -- Gift of Nature
        { spell = 1223081, healPeriodic = 1 },                 -- Genesis
        { spell = 17111, spellHeal = 1, on = { 774 } },        -- Improved Rejuvenation
        { spell = 17074, spellCrit = 1, on = { 8936 } },       -- Improved Regrowth
    },
    HUNTER = {
        { spell = 19168, stats = { [2] = 1 } },                -- Lightning Reflexes
        { spell = 19255, health = 1 },                         -- Survivalist
        { spell = 1223984, intAP = 1, intRAP = 1 },            -- Careful Aim
    },
    MAGE = {
        { spell = 11232, stats = { [4] = 1 } },                -- Arcane Mind
        { spell = 28574, intArmor = 1 },                       -- Arcane Resilience
    },
    PRIEST = {
        { spell = 18551, stats = { [4] = 1 } },                -- Mental Strength
        { spell = 14901, spiritHeal = 1, spiritDamage = 2 },   -- Spiritual Guidance
        { spell = 1225132, healInstant = 1 },                  -- Twin Disciplines
        { spell = 14898, heal = 1 },                           -- Spiritual Healing
        { spell = 14889, healCrit = 1 },                       -- Holy Specialization (every priest heal is Holy)
        { spell = 14908, spellHeal = 1, on = { 139 } },        -- Improved Renew
    },
    SHAMAN = {
        { spell = 16252, stats = { [3] = 1 } },                -- Toughness
        { spell = 17485, stats = { [4] = 1 } },                -- Ancestral Knowledge
        { spell = 16184, health = 1 },                         -- Improved Reincarnation
        { spell = 415140, intAP = 1 },                         -- Mental Dexterity
        { spell = 30812, intDamage = 1, intHeal = 1 },         -- Mental Quickness
        { spell = 16178, heal = 1 },                           -- Purification
        { spell = 16194, healCrit = 1 },                       -- Tidal Mastery
        { spell = 29206, spellHeal = 1, on = { 331 } },        -- Healing Way (Healing Wave)
    },
    WARLOCK = {
        { spell = 18697, stats = { [3] = 1 } },                -- Demonic Embrace
        { spell = 18731, mana = 2 },                           -- Fel Vitality (pets first)
    },
}

-- Druid forms that raise armor from items, by their spell (also the form's aura): which % number in
-- its description is the share.
local FORM_ARMOR = { [5487] = 1, [9634] = 1, [24858] = 2 } -- Bear Form, Dire Bear Form, Moonkin Form

-- Buffs that raise every stat by a share: Blessing of Kings, Greater Blessing of Kings (10%), Spirit
-- of Zandalar (15%, two spells).
local ALL_STAT_BUFFS = { [20217] = 10, [25898] = 10, [24425] = 15, [355365] = 15 }

local function Text(value)
    if issecret(value) or type(value) ~= "string" or value == "" then return nil end
    return value
end

local function Number(value)
    if issecret(value) or type(value) ~= "number" then return nil end
    return value
end

local function Ask(Read, ...)
    if type(Read) ~= "function" then return nil end
    local ok, value = pcall(Read, ...)
    if ok and not issecret(value) then return value end
end

-- The numbers followed by a % in a text, in order ("by 6%" ... "by 10%" -> { 6, 10 }), or nil. Also
-- "10 %" and "1,5 %" (French and German write them so; \194\160 is a no-break space).
local function Percents(text)
    if not text then return nil end
    local found = {}
    for number in text:gmatch("(%d+[%.,]?%d*)[ \194\160]*%%") do
        found[#found + 1] = tonumber((number:gsub(",", ".")))
    end
    return #found > 0 and found or nil
end

local function SpellDescription(spellID)
    return Text(Ask(C_Spell and C_Spell.GetSpellDescription, spellID))
end

------------------------------------------------------------------------------
-- Your talents
------------------------------------------------------------------------------

-- The active talent config, as Forever's talent frame finds it.
local function ConfigID()
    local configID = C_ClassTalents and Number(Ask(C_ClassTalents.GetActiveConfigID))
    if configID then return configID end
    local info = C_SpecializationInfo
    local group = info and Number(Ask(info.GetActiveSpecGroup))
    return group and Number(Ask(info.GetCombatConfigIDForSpecGroup, group)) or nil
end

-- The nodes of your tree that hold one of `mine`: { [nodeID] = { entry, entryID } }, worked out
-- once per config (a node's talents don't change); kept only once every node has answered, so a
-- tree still loading is read again.
local nodesFor, nodesConfig
local function Nodes(mine, configID)
    if nodesFor and nodesConfig == configID then return nodesFor end
    local traits = C_Traits
    local config = traits and Ask(traits.GetConfigInfo, configID)
    local treeID = type(config) == "table" and type(config.treeIDs) == "table" and config.treeIDs[1]
    local nodeIDs = treeID and Ask(traits.GetTreeNodes, treeID)
    if type(nodeIDs) ~= "table" or #nodeIDs == 0 then return nil end
    local bySpell = {}
    for _, entry in ipairs(mine) do bySpell[entry.spell] = entry end
    local found, complete = {}, true
    for _, nodeID in ipairs(nodeIDs) do
        local node = Ask(traits.GetNodeInfo, configID, nodeID)
        local entryIDs = type(node) == "table" and type(node.entryIDs) == "table" and node.entryIDs
        if not entryIDs then complete = false end
        for _, entryID in ipairs(entryIDs or {}) do
            local info = Ask(traits.GetEntryInfo, configID, entryID)
            local definitionID = type(info) == "table" and Number(info.definitionID)
            local definition = definitionID and Ask(traits.GetDefinitionInfo, definitionID)
            if type(definition) ~= "table" then
                -- A subtree choice has no definition; anything else not answering is still loading.
                if not (type(info) == "table" and info.subTreeID) then complete = false end
            else
                local entry = bySpell[Number(definition.spellID) or 0]
                if entry then found[nodeID] = { entry = entry, entryID = entryID } end
            end
        end
    end
    if complete then nodesFor, nodesConfig = found, configID end
    return found, complete
end

-- Your rank's shares for a talent: its description at that rank. A one-rank talent can fall back on
-- its spell's description (which has rank 1's numbers, so only right for one rank).
local function Shares(entry, entryID, rank, maxRanks)
    local text = C_Traits and Text(Ask(C_Traits.GetTraitDescription, entryID, rank))
    if not text and maxRanks == 1 then text = SpellDescription(entry.spell) end
    return Percents(text)
end

-- { [entry] = { rank, shares } } for the talents you have, read once and again after a change. A
-- talent that can't be read this time (still loading, or hidden) keeps its last reading at the same
-- rank, and the read is tried again a few seconds later rather than on every tooltip.
local RETRY = 5
local taken, retryAt, previous = nil, nil, {}

local function Taken()
    if taken and not (retryAt and GetTime() >= retryAt) then return taken end
    local found = {}
    local mine = TALENTS[select(2, UnitClass("player"))]
    local configID = mine and ConfigID()
    local nodes, complete = nil, not mine
    if configID then nodes, complete = Nodes(mine, configID) end
    if nodes and complete == nil then complete = true end -- from the cache
    for nodeID, held in pairs(nodes or {}) do
        local node = Ask(C_Traits.GetNodeInfo, configID, nodeID)
        local rank = type(node) == "table" and Number(node.activeRank or node.ranksPurchased) or 0
        local active = rank > 0 and type(node.activeEntry) == "table" and Number(node.activeEntry.entryID)
        -- On a choice node, only when this talent is the one chosen.
        local entry = held.entry
        if active == held.entryID and rank > (found[entry] and found[entry].rank or 0) then
            local shares = Shares(entry, active, rank, Number(node.maxRanks))
            local last = previous[entry]
            if shares then
                found[entry] = { rank = rank, shares = shares }
            elseif last and last.rank == rank then
                found[entry] = last
            else
                complete = false
            end
        end
    end
    taken, previous, retryAt = found, found, not complete and GetTime() + RETRY or nil
    return found
end

------------------------------------------------------------------------------
-- Buffs and forms
------------------------------------------------------------------------------

-- If you have an aura: true, false, or nil when the game would keep it secret (a secret aura
-- reads as missing, so it has to be asked first).
local function HasAura(spellID)
    local Hidden = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
    if Hidden then
        local ok, hidden = pcall(Hidden, spellID)
        if ok and (issecret(hidden) or hidden == true) then return nil end
    end
    local Lookup = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not Lookup then return false end
    local ok, aura = pcall(Lookup, spellID)
    if not ok or issecret(aura) then return nil end
    return aura ~= nil
end

-- Kings and the like, and the druid form that raises item armor (its spell, or false): read again
-- after your auras change, and kept from the last reading while the game hides them (in combat).
local auraDirty, buffScale, armorForm = true, 1, false
local formShares = {} -- [form spell] = its shares

local function ReadAuras()
    if not auraDirty then return end
    local scale, form = 1, false
    for spellID, share in pairs(ALL_STAT_BUFFS) do
        local has = HasAura(spellID)
        if has == nil then return end
        if has then scale = scale * (1 + share / 100) end
    end
    if select(2, UnitClass("player")) == "DRUID" then
        for spellID in pairs(FORM_ARMOR) do
            local has = HasAura(spellID)
            if has == nil then return end
            if has then form = spellID end
        end
    end
    buffScale, armorForm, auraDirty = scale, form, false
end

------------------------------------------------------------------------------
-- Events: talent changes read the talents again (a new config, the tree too); aura changes and the
-- end of the game's restrictions read the auras again.
------------------------------------------------------------------------------

local CONFIG_EVENTS = { TRAIT_CONFIG_UPDATED = true, TRAIT_CONFIG_LIST_UPDATED = true, ACTIVE_TALENT_GROUP_CHANGED = true,
    ACTIVE_COMBAT_CONFIG_CHANGED = true }
local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED",
    "ACTIVE_COMBAT_CONFIG_CHANGED", "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "ADDON_RESTRICTION_STATE_CHANGED",
    "PLAYER_REGEN_ENABLED" }) do
    pcall(events.RegisterEvent, events, event)
end
pcall(events.RegisterUnitEvent, events, "UNIT_AURA", "player")
events:SetScript("OnEvent", function(_, event)
    if event == "UNIT_AURA" or event == "ADDON_RESTRICTION_STATE_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
        auraDirty = true
        return
    end
    taken, retryAt = nil, nil
    if CONFIG_EVENTS[event] then nodesFor = nil end
end)

------------------------------------------------------------------------------
-- What the sums ask
------------------------------------------------------------------------------

-- A share (a percent) from a list of numbers, or 0. Above 1000% would be a misread.
local function Share(shares, position)
    local value = position and shares and shares[position]
    if not value or value < 0 or value > 1000 then return 0 end
    return value
end

-- The product of (1 + share) over your talents with `field`.
local function Product(field)
    local scale = 1
    for entry, state in pairs(Taken()) do
        if entry[field] then scale = scale * (1 + Share(state.shares, entry[field]) / 100) end
    end
    return scale
end

-- The sum of the shares (fractions) over your talents with `field`.
local function Sum(field)
    local sum = 0
    for entry, state in pairs(Taken()) do
        if entry[field] then sum = sum + Share(state.shares, entry[field]) / 100 end
    end
    return sum
end

local function Form()
    if select(2, UnitClass("player")) ~= "DRUID" then return nil end
    local powerType = UnitPowerType("player")
    if issecret(powerType) then return nil end
    return powerType == 1 and "bear" or powerType == 3 and "cat" or nil
end

-- What one point of a stat on an item adds to the stat on you (Divine Strength 5/5: 1.1). Shares
-- multiply, as they do in the game.
function Talents.StatScale(statIndex)
    local scale = 1
    local form = Form()
    for entry, state in pairs(Taken()) do
        local position = entry.stats and entry.stats[statIndex]
        if form and entry[form] and entry[form][statIndex] then position = entry[form][statIndex] end
        if position then scale = scale * (1 + Share(state.shares, position) / 100) end
    end
    ReadAuras()
    return scale * buffScale
end

-- Spirit and Intellect counted as spell power: shares (fractions) as spell damage and as healing.
function Talents.SpiritToSpell() return Sum("spiritDamage"), Sum("spiritHeal") end
function Talents.IntToSpell() return Sum("intDamage"), Sum("intHeal") end

-- Intellect counted as attack power: shares (fractions) as melee and as ranged attack power.
function Talents.IntToAP() return Sum("intAP"), Sum("intRAP") end

-- The melee and ranged attack power Intellect going from `now` to `new` brings (Mental Dexterity,
-- Careful Aim): the game's own sums if it counts Intellect there, else the talents' shares.
function Talents.IntAPChange(now, new)
    local meleeShare, rangedShare = Talents.IntToAP()
    local melee, ranged = (new - now) * meleeShare, (new - now) * rangedShare
    local Tank = FrogLib.Tank
    local meleeNow = Tank.StatAP(4, now)
    if meleeNow and meleeNow > 0 then melee = (Tank.StatAP(4, new) or meleeNow) - meleeNow end
    local rangedNow = Tank.Call(GetRangedAttackPowerForStat, 4, now)
    if rangedNow and rangedNow > 0 then ranged = (Tank.Call(GetRangedAttackPowerForStat, 4, new) or rangedNow) - rangedNow end
    return melee, ranged
end

-- Intellect counted as armor: the share of Intellect (a fraction).
function Talents.IntToArmor() return Sum("intArmor") end

-- If a talent's `on` list holds the heal named `name`.
local function On(entry, name)
    if not (entry.on and name) then return false end
    if not entry.onNames then
        entry.onNames = {}
        for _, spellID in ipairs(entry.on) do
            local onName = Text(Ask(C_Spell and C_Spell.GetSpellName, spellID))
            if onName then entry.onNames[onName] = true end
        end
    end
    return entry.onNames[name] == true
end

-- What a heal comes to with your healing talents: all of it (Gift of Nature, Purification, Spiritual
-- Healing; Healing Light and the like for the heal named `name`), its part over time (Genesis) and,
-- `instant`, an instant heal (Twin Disciplines); and the crit chance they add to heals (Tidal Mastery,
-- Holy Specialization, Improved Regrowth for its heal), in percent.
function Talents.HealScale(instant, name)
    local scale = Product("heal")
    if instant then scale = scale * Product("healInstant") end
    for entry, state in pairs(Taken()) do
        if entry.spellHeal and On(entry, name) then scale = scale * (1 + Share(state.shares, entry.spellHeal) / 100) end
    end
    return scale, Product("healPeriodic")
end

function Talents.HealCrit(name)
    local crit = Sum("healCrit")
    for entry, state in pairs(Taken()) do
        if entry.spellCrit and On(entry, name) then crit = crit + Share(state.shares, entry.spellCrit) / 100 end
    end
    return crit * 100
end

-- What a heal's crit adds: half as much again, more with Holy Power.
function Talents.CritBonus() return 0.5 * (1 + Sum("critBonus")) end

-- What one point of maximum health / mana (from Stamina / Intellect) comes to (Survivalist 5/5: 1.1).
function Talents.HealthScale() return Product("health") end
function Talents.ManaScale() return Product("mana") end

-- What one point of armor on an item comes to: Toughness, and Bear, Dire Bear or Moonkin Form.
function Talents.ItemArmorScale()
    local scale = Product("itemArmor")
    ReadAuras()
    if armorForm then
        local shares = formShares[armorForm]
        if not shares then
            shares = Percents(SpellDescription(armorForm))
            formShares[armorForm] = shares
        end
        scale = scale * (1 + Share(shares, FORM_ARMOR[armorForm]) / 100)
    end
    return scale
end

-- For the audit: { spell name = { rank, shares } }, and what they come to.
function Talents.Report()
    local report = {}
    for entry, state in pairs(Taken()) do
        local name = Text(Ask(C_Spell and C_Spell.GetSpellName, entry.spell)) or tostring(entry.spell)
        report[name] = { rank = state.rank, shares = state.shares }
    end
    local spiritDamage, spiritHeal = Talents.SpiritToSpell()
    local intDamage, intHeal = Talents.IntToSpell()
    local intAP, intRAP = Talents.IntToAP()
    report.scales = {
        strength = Talents.StatScale(1), agility = Talents.StatScale(2), stamina = Talents.StatScale(3),
        intellect = Talents.StatScale(4), spirit = Talents.StatScale(5),
        spiritDamage = spiritDamage, spiritHeal = spiritHeal, intDamage = intDamage, intHeal = intHeal,
        intAP = intAP, intRAP = intRAP, intArmor = Talents.IntToArmor(),
        itemArmor = Talents.ItemArmorScale(), health = Talents.HealthScale(), mana = Talents.ManaScale(),
        heal = Talents.HealScale(), healPeriodic = select(2, Talents.HealScale()), healCrit = Talents.HealCrit(),
    }
    return report
end
