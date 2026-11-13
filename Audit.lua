local _, ns = ...

-- /statsheet audit: saves what the client reports about your stats (raw API returns, the panel's
-- cells and tooltips, gear, skills, auras, stat-like globals; with "full", Blizzard's own list and
-- its tooltips) into StatSheetDB.audits[form], to check the panel against the game's own numbers.
-- The game writes saved variables on /reload or logout.

local Audit = {}
ns.Audit = Audit

local issecret = FrogLib.issecret
local PLAYER = "player"

-- A copy the game can save, `depth` tables deep: secrets, NaN, functions, frames and the like as "<...>".
local function Clean(value, depth, seen)
    if issecret(value) then return "<secret>" end
    local kind = type(value)
    if kind == "number" then
        if value ~= value then return "<nan>" end
        if value == math.huge or value == -math.huge then return "<inf>" end
        return value
    end
    if kind == "string" or kind == "boolean" or kind == "nil" then return value end
    if kind == "function" then return "<function>" end
    if kind ~= "table" then return "<" .. kind .. ">" end
    if depth <= 0 then return "<table>" end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    if value.GetObjectType then
        local okType, objectType = pcall(value.GetObjectType, value)
        local okName, name = pcall(value.GetName, value)
        return "<" .. (okType and objectType or "frame") .. " " .. tostring(okName and name or "") .. ">"
    end
    local copy = {}
    for key, item in pairs(value) do
        if type(key) == "string" or type(key) == "number" then copy[key] = Clean(item, depth - 1, seen) end
    end
    return copy
end

-- "C_PaperDollInfo.GetArmorEffectiveness" to the function it names.
local function Resolve(name)
    local found = _G
    for part in name:gmatch("[^%.]+") do
        if type(found) ~= "table" then return nil end
        found = found[part]
    end
    return found
end

local function Pack(...) return { n = select("#", ...), ... } end

-- Every return, nils included ("<nil>"), so positions line up with the documentation.
local function Call(name, ...)
    local func = Resolve(name)
    if type(func) ~= "function" then return "<missing>" end
    local returns = Pack(pcall(func, ...))
    if not returns[1] then return "<error> " .. tostring(returns[2]) end
    if returns.n < 2 then return "<nothing>" end
    local out = {}
    for i = 2, returns.n do
        local value = Clean(returns[i], 2)
        if value == nil then value = "<nil>" end
        out[i - 1] = value
    end
    return out
end

local function ApiDump()
    local api = {}
    local function Put(key, name, ...) api[key] = Call(name, ...) end
    for i = 1, 5 do Put("UnitStat(" .. i .. ")", "UnitStat", PLAYER, i) end
    for i = 0, 6 do Put("UnitResistance(" .. i .. ")", "UnitResistance", PLAYER, i) end
    for i = 1, 7 do
        Put("GetSpellBonusDamage(" .. i .. ")", "GetSpellBonusDamage", i)
        Put("GetSpellCritChance(" .. i .. ")", "GetSpellCritChance", i)
    end
    for i = 1, 32 do
        Put("GetCombatRating(" .. i .. ")", "GetCombatRating", i)
        Put("GetCombatRatingBonus(" .. i .. ")", "GetCombatRatingBonus", i)
    end
    for _, name in ipairs({ "UnitDamage", "UnitAttackSpeed", "UnitAttackPower", "UnitRangedAttackPower",
        "UnitRangedDamage", "UnitAttackBothHands", "UnitDefense", "UnitArmor", "UnitSpellHaste",
        "UnitHealthMax", "UnitPowerMax", "UnitPowerType", "UnitLevel", "UnitClass", "UnitRace",
        "UnitEffectiveLevel", "GetUnitSpeed", "UnitRangedAttack", "UnitStatPercent" }) do
        Put(name, name, PLAYER)
    end
    for _, name in ipairs({ "GetCritChance", "GetRangedCritChance", "GetSpellBonusHealing",
        "GetHitModifier", "GetSpellHitModifier", "GetMeleeHaste", "GetRangedHaste", "GetHaste",
        "GetDodgeChance", "GetParryChance", "GetBlockChance", "GetShieldBlock", "GetManaRegen",
        "GetPowerRegen", "GetExpertise", "GetMastery", "GetMasteryEffect", "GetSpellPenetration",
        "GetArmorPenetration", "GetLifesteal", "GetAvoidance", "GetSpeed", "GetAverageItemLevel",
        "GetCritChanceProvidesParryEffect", "GetDodgeChanceFromAttribute", "GetParryChanceFromAttribute",
        "GetShapeshiftForm", "GetShapeshiftFormID", "GetVersatilityBonus", "GetModResilienceDamageReduction",
        "GetAttackPowerForStat", "GetCritChanceFromAgility", "GetSpellCritChanceFromIntellect",
        "GetUnitHealthRegenRateFromSpirit", "GetUnitManaRegenRateFromSpirit", "GetXPExhaustion" }) do
        Put(name, name)
    end
    Put("GetUnitHealthRegenRateFromSpirit(player)", "GetUnitHealthRegenRateFromSpirit", PLAYER)
    Put("GetUnitManaRegenRateFromSpirit(player)", "GetUnitManaRegenRateFromSpirit", PLAYER)
    Put("GetCritChanceFromAgility(player)", "GetCritChanceFromAgility", PLAYER)
    Put("GetSpellCritChanceFromIntellect(player)", "GetSpellCritChanceFromIntellect", PLAYER)
    Put("GetPowerRegenForPowerType(0)", "GetPowerRegenForPowerType", 0)
    Put("GetPowerRegenForPowerType(3)", "GetPowerRegenForPowerType", 3)
    for i = 1, 5 do
        local _, stat = UnitStat(PLAYER, i)
        Put("GetAttackPowerForStat(" .. i .. ")", "GetAttackPowerForStat", i, stat)
    end
    local _, armor = UnitArmor(PLAYER)
    local level = UnitLevel(PLAYER)
    Put("GetArmorEffectiveness(lv)", "C_PaperDollInfo.GetArmorEffectiveness", armor, level)
    Put("GetArmorEffectiveness(lv+3)", "C_PaperDollInfo.GetArmorEffectiveness", armor, level + 3)
    Put("GetArmorEffectivenessAgainstTarget", "C_PaperDollInfo.GetArmorEffectivenessAgainstTarget", armor)
    Put("GetStaggerPercentage", "C_PaperDollInfo.GetStaggerPercentage", PLAYER)
    Put("GetMinItemLevel", "C_PaperDollInfo.GetMinItemLevel")
    return api
end

local function GearDump()
    local items, totals = {}, {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink(PLAYER, slot)
        if link then
            local stats = C_Item.GetItemStats(link) or {}
            items[slot] = { link = link, stats = Clean(stats, 1) }
            for stat, amount in pairs(stats) do
                if type(amount) == "number" then totals[stat] = (totals[stat] or 0) + amount end
            end
        end
    end
    return { items = items, totals = totals }
end

local function SkillDump()
    if not (GetNumSkillLines and GetSkillLineInfo) then return "<missing>" end
    local skills = {}
    for i = 1, GetNumSkillLines() do skills[i] = Clean({ GetSkillLineInfo(i) }, 1) end
    return skills
end

local function AuraDump()
    local auras = {}
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return auras end
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, PLAYER, i, "HELPFUL")
        if not ok or not aura then break end
        auras[i] = Clean({ name = aura.name, spellId = aura.spellId, points = aura.points }, 2)
    end
    return auras
end

local WORDS = { "STAT", "PAPERDOLL", "ARMOR", "DEFENSE", "DODGE", "PARRY", "BLOCK", "CRIT", "HIT_",
    "HASTE", "REGEN", "ATTACK_POWER", "SPELL_BONUS", "SPELLPOWER", "SPELL_POWER", "RESIST", "WEAPON_SKILL",
    "MELEE", "RANGED", "EXPERTISE", "SPIRIT", "STAMINA", "INTELLECT", "AGILITY", "STRENGTH", "MANA_",
    "DAMAGE_PER_SECOND", "ATTACK_SPEED", "PENETRATION", "COMBAT_RATING", "CR_" }
local FUNCTION_WORDS = { "Chance", "Rating", "Regen", "Haste", "Skill", "Stat", "Defense", "Armor", "Resist",
    "Crit", "Hit", "Expertise", "Penetration", "Block", "Dodge", "Parry", "SpellBonus", "AttackPower",
    "Damage", "AttackSpeed", "PaperDoll", "Mastery", "Versatility", "Avoidance", "Lifesteal" }

local function Matches(name, words)
    for _, word in ipairs(words) do
        if name:find(word, 1, true) then return true end
    end
end

local function FoundDump()
    local functions, strings, tables, namespaces = {}, {}, {}, {}
    for name, value in pairs(_G) do
        if type(name) == "string" then
            local kind = type(value)
            if kind == "function" and Matches(name, FUNCTION_WORDS) then
                functions[#functions + 1] = name
            elseif kind == "string" and #value < 500 and Matches(name, WORDS) then
                strings[name] = value
            elseif kind == "table" and name:match("^C_") then
                local list = {}
                for member, func in pairs(value) do
                    if type(func) == "function" and type(member) == "string" and Matches(member, FUNCTION_WORDS) then
                        list[#list + 1] = member
                    end
                end
                if #list > 0 then
                    table.sort(list)
                    namespaces[name] = list
                end
            elseif kind == "table" and (name:find("PAPERDOLL", 1, true) or name:find("STAT_CATEG", 1, true)) then
                tables[name] = Clean(value, 4)
            end
        end
    end
    table.sort(functions)
    return { functions = functions, strings = strings, tables = tables, namespaces = namespaces }
end

-- A stand-in for GameTooltip that keeps the lines, for the panel's own tooltips.
local function Collector()
    local collector = { lines = {} }
    function collector:AddLine(text) self.lines[#self.lines + 1] = Clean(text, 0) end
    function collector:AddDoubleLine(left, right) self.lines[#self.lines + 1] = Clean(left, 0) .. "  =  " .. Clean(right, 0) end
    return collector
end

local function OursDump()
    local rows = {}
    for _, section in ipairs(ns.Sections) do
        for _, cell in ipairs(section.cells) do
            local label = type(cell.label) == "function" and select(2, pcall(cell.label)) or cell.label
            local ok, text, zero = pcall(cell.get)
            local row = { section = section.key, label = Clean(label, 0), text = ok and Clean(text, 0) or ("<error> " .. tostring(text)), zero = zero }
            if cell.tip then
                local collector = Collector()
                local okTip, err = pcall(cell.tip, collector)
                row.tip = okTip and collector.lines or ("<error> " .. tostring(err))
            end
            rows[#rows + 1] = row
        end
    end
    return rows
end

local function TooltipLines()
    local lines = {}
    for i = 1, GameTooltip:NumLines() do
        local left = _G["GameTooltipTextLeft" .. i]
        local right = _G["GameTooltipTextRight" .. i]
        local leftText = Clean(left and left:GetText(), 0)
        local rightText = Clean(right and right:IsShown() and right:GetText(), 0)
        lines[#lines + 1] = rightText and rightText ~= "" and (tostring(leftText) .. "  =  " .. tostring(rightText)) or leftText
    end
    return lines
end

-- Steps through Blizzard's list one row at a time: scrolls the row into view, runs its own
-- OnEnter and copies the tooltip it builds.
local function BlizzardDump(Done)
    local box = _G.CharacterStatsPaneScrollBox
    local scrollBox = box and box.ScrollBox
    if not (scrollBox and scrollBox.GetDataProvider and scrollBox:GetDataProvider()) then
        Done("<no stats list>")
        return
    end
    local rows = {}
    local list = {}
    scrollBox:GetDataProvider():ForEach(function(data) list[#list + 1] = data end)
    local index = 0
    local function Step()
        index = index + 1
        local data = list[index]
        if not data then
            GameTooltip:Hide()
            Done(rows)
            return
        end
        local row = { data = Clean(data, 3) }
        rows[index] = row
        pcall(scrollBox.ScrollToElementData, scrollBox, data)
        C_Timer.After(0.05, function()
            local frame = scrollBox.FindFrame and scrollBox:FindFrame(data)
            if frame then
                row.label = frame.Label and Clean(frame.Label:GetText(), 0)
                row.value = frame.Value and Clean(frame.Value:GetText(), 0)
                row.title = frame.Title and Clean(frame.Title:GetText(), 0)
                local enter = frame:GetScript("OnEnter")
                if enter then
                    GameTooltip:Hide()
                    local ok, err = pcall(enter, frame)
                    if not ok then row.tipError = tostring(err) end
                    if GameTooltip:IsShown() then row.tip = TooltipLines() end
                    local leave = frame:GetScript("OnLeave")
                    if leave then pcall(leave, frame) end
                end
            else
                row.frame = "<not found>"
            end
            Step()
        end)
    end
    Step()
end

-- The whole audit as one JSON string: a string always saves, where a table holding something
-- the game can't write (a NaN, say) can be dropped from the file without a word.
local function Json(value, out)
    local kind = type(value)
    if kind == "table" then
        out[#out + 1] = "{"
        local first = true
        for key, item in pairs(value) do
            if not first then out[#out + 1] = "," end
            first = false
            Json(tostring(key), out)
            out[#out + 1] = ":"
            Json(item, out)
        end
        out[#out + 1] = "}"
    elseif kind == "string" then
        out[#out + 1] = '"' .. (value:gsub('[%c"\\]', function(char) return string.format("\\u%04x", char:byte()) end)) .. '"'
    elseif kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            out[#out + 1] = '"' .. tostring(value) .. '"'
        else
            out[#out + 1] = string.format("%.10g", value)
        end
    elseif kind == "boolean" then
        out[#out + 1] = tostring(value)
    else
        out[#out + 1] = "null"
    end
end

local function FormKey()
    local id = GetShapeshiftFormID and GetShapeshiftFormID()
    if issecret(id) or not id then return "normal" end
    return "form" .. id
end

function Audit:Run(full)
    if InCombatLockdown() then
        print("|cff40c0ffStatSheet|r: run the audit out of combat.")
        return
    end
    if not (_G.CharacterFrame and _G.CharacterFrame:IsShown() and _G.CharacterStatsPaneScrollBox
        and _G.CharacterStatsPaneScrollBox:IsVisible()) then
        print("|cff40c0ffStatSheet|r: open your character sheet on the stats tab first, then run /statsheet audit again.")
        return
    end
    print("|cff40c0ffStatSheet|r: auditing... keep the character sheet open for a few seconds.")
    local key = FormKey()
    local result = {
        time = date("%Y-%m-%d %H:%M:%S"),
        client = { GetBuildInfo() },
        form = key,
        api = ApiDump(),
        ours = OursDump(),
        gear = GearDump(),
        skills = SkillDump(),
        auras = AuraDump(),
        found = FoundDump(),
        regen = ns.Regen and Clean(ns.Regen:Snapshot(), 3),
    }
    local function Save(rows)
        result.blizzard = rows
        local out = {}
        Json(result, out)
        ns.db.audits = ns.db.audits or {}
        ns.db.audits[key] = { time = result.time, json = table.concat(out) }
        print(("|cff40c0ffStatSheet|r: audit saved (%s). Type |cffffd100/reload|r to write it to disk.")
            :format(key))
    end
    -- Stepping through Blizzard's list (its rows and tooltips) only with "/statsheet audit full".
    if full then BlizzardDump(Save) else Save("<skipped>") end
end
