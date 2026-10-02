local _, ns = ...

-- /statsheet audit: writes everything the client knows about your stats into the saved
-- variables (StatSheetDB.audits[form]), to compare the panel against the game's own numbers:
--   api       every stat function's raw returns (and which ones this client has)
--   blizzard  Blizzard's own stats list: each row's data, its text and its tooltip lines
--   ours      the panel's cells and tooltip lines
--   gear      each equipped item's stats and the totals across them
--   skills    the skill lines (weapon skills, defense) when the client has them
--   found     global functions, C_ namespaces and strings that look stat-related
-- The game writes saved variables on /reload or logout.

local Audit = {}
ns.Audit = Audit

local issecret = issecretvalue or function() return false end

local function Clean(v, depth, seen)
    if issecret(v) then return "<secret>" end
    local t = type(v)
    if t == "number" then
        if v ~= v then return "<nan>" end
        if v == math.huge or v == -math.huge then return "<inf>" end
        return v
    end
    if t == "string" or t == "boolean" or t == "nil" then return v end
    if t == "function" then return "<function>" end
    if t ~= "table" then return "<" .. t .. ">" end
    if depth <= 0 then return "<table>" end
    seen = seen or {}
    if seen[v] then return "<cycle>" end
    seen[v] = true
    if v.GetObjectType then
        local ok, kind = pcall(v.GetObjectType, v)
        local okN, name = pcall(v.GetName, v)
        return "<" .. (ok and kind or "frame") .. " " .. tostring(okN and name or "") .. ">"
    end
    local out = {}
    for k, x in pairs(v) do
        if type(k) == "string" or type(k) == "number" then out[k] = Clean(x, depth - 1, seen) end
    end
    return out
end

local function Resolve(name)
    local fn = _G
    for part in name:gmatch("[^%.]+") do
        if type(fn) ~= "table" then return nil end
        fn = fn[part]
    end
    return fn
end

local function Pack(...) return { n = select("#", ...), ... } end

-- Every return, nils included ("<nil>"), so positions line up with the documentation.
local function Call(name, ...)
    local fn = Resolve(name)
    if type(fn) ~= "function" then return "<missing>" end
    local r = Pack(pcall(fn, ...))
    if not r[1] then return "<error> " .. tostring(r[2]) end
    if r.n < 2 then return "<nothing>" end
    local out = {}
    for i = 2, r.n do
        local v = Clean(r[i], 2)
        if v == nil then v = "<nil>" end
        out[i - 1] = v
    end
    return out
end

local function ApiDump()
    local api = {}
    local function put(key, name, ...) api[key] = Call(name, ...) end
    local P = "player"
    for i = 1, 5 do put("UnitStat(" .. i .. ")", "UnitStat", P, i) end
    for i = 0, 6 do put("UnitResistance(" .. i .. ")", "UnitResistance", P, i) end
    for i = 1, 7 do
        put("GetSpellBonusDamage(" .. i .. ")", "GetSpellBonusDamage", i)
        put("GetSpellCritChance(" .. i .. ")", "GetSpellCritChance", i)
    end
    for i = 1, 32 do
        put("GetCombatRating(" .. i .. ")", "GetCombatRating", i)
        put("GetCombatRatingBonus(" .. i .. ")", "GetCombatRatingBonus", i)
    end
    for _, name in ipairs({ "UnitDamage", "UnitAttackSpeed", "UnitAttackPower", "UnitRangedAttackPower",
        "UnitRangedDamage", "UnitAttackBothHands", "UnitDefense", "UnitArmor", "UnitSpellHaste",
        "UnitHealthMax", "UnitPowerMax", "UnitPowerType", "UnitLevel", "UnitClass", "UnitRace",
        "UnitEffectiveLevel", "GetUnitSpeed", "UnitRangedAttack", "UnitStatPercent" }) do
        put(name, name, P)
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
        put(name, name)
    end
    put("GetUnitHealthRegenRateFromSpirit(player)", "GetUnitHealthRegenRateFromSpirit", P)
    put("GetUnitManaRegenRateFromSpirit(player)", "GetUnitManaRegenRateFromSpirit", P)
    put("GetCritChanceFromAgility(player)", "GetCritChanceFromAgility", P)
    put("GetSpellCritChanceFromIntellect(player)", "GetSpellCritChanceFromIntellect", P)
    put("GetPowerRegenForPowerType(0)", "GetPowerRegenForPowerType", 0)
    put("GetPowerRegenForPowerType(3)", "GetPowerRegenForPowerType", 3)
    for i = 1, 5 do
        local _, stat = UnitStat(P, i)
        put("GetAttackPowerForStat(" .. i .. ")", "GetAttackPowerForStat", i, stat)
    end
    local _, armor = UnitArmor(P)
    local level = UnitLevel(P)
    put("GetArmorEffectiveness(lv)", "C_PaperDollInfo.GetArmorEffectiveness", armor, level)
    put("GetArmorEffectiveness(lv+3)", "C_PaperDollInfo.GetArmorEffectiveness", armor, level + 3)
    put("GetArmorEffectivenessAgainstTarget", "C_PaperDollInfo.GetArmorEffectivenessAgainstTarget", armor)
    put("GetStaggerPercentage", "C_PaperDollInfo.GetStaggerPercentage", P)
    put("GetMinItemLevel", "C_PaperDollInfo.GetMinItemLevel")
    return api
end

local function GearDump()
    local items, totals = {}, {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local stats = C_Item.GetItemStats(link) or {}
            items[slot] = { link = link, stats = Clean(stats, 1) }
            for k, v in pairs(stats) do
                if type(v) == "number" then totals[k] = (totals[k] or 0) + v end
            end
        end
    end
    return { items = items, totals = totals }
end

local function SkillDump()
    if not (GetNumSkillLines and GetSkillLineInfo) then return "<missing>" end
    local out = {}
    for i = 1, GetNumSkillLines() do out[i] = Clean({ GetSkillLineInfo(i) }, 1) end
    return out
end

local function AuraDump()
    local out = {}
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return out end
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not a then break end
        out[i] = Clean({ name = a.name, spellId = a.spellId, points = a.points }, 2)
    end
    return out
end

local WORDS = { "STAT", "PAPERDOLL", "ARMOR", "DEFENSE", "DODGE", "PARRY", "BLOCK", "CRIT", "HIT_",
    "HASTE", "REGEN", "ATTACK_POWER", "SPELL_BONUS", "SPELLPOWER", "SPELL_POWER", "RESIST", "WEAPON_SKILL",
    "MELEE", "RANGED", "EXPERTISE", "SPIRIT", "STAMINA", "INTELLECT", "AGILITY", "STRENGTH", "MANA_",
    "DAMAGE_PER_SECOND", "ATTACK_SPEED", "PENETRATION", "COMBAT_RATING", "CR_" }
local FN_WORDS = { "Chance", "Rating", "Regen", "Haste", "Skill", "Stat", "Defense", "Armor", "Resist",
    "Crit", "Hit", "Expertise", "Penetration", "Block", "Dodge", "Parry", "SpellBonus", "AttackPower",
    "Damage", "AttackSpeed", "PaperDoll", "Mastery", "Versatility", "Avoidance", "Lifesteal" }

local function Matches(key, words)
    for _, w in ipairs(words) do
        if key:find(w, 1, true) then return true end
    end
end

local function FoundDump()
    local fns, strings, tables, namespaces = {}, {}, {}, {}
    for k, v in pairs(_G) do
        if type(k) == "string" then
            local t = type(v)
            if t == "function" and Matches(k, FN_WORDS) then
                fns[#fns + 1] = k
            elseif t == "string" and #v < 500 and Matches(k, WORDS) then
                strings[k] = v
            elseif t == "table" and k:match("^C_") then
                local list = {}
                for name, f in pairs(v) do
                    if type(f) == "function" and type(name) == "string" and Matches(name, FN_WORDS) then
                        list[#list + 1] = name
                    end
                end
                if #list > 0 then
                    table.sort(list)
                    namespaces[k] = list
                end
            elseif t == "table" and (k:find("PAPERDOLL", 1, true) or k:find("STAT_CATEG", 1, true)) then
                tables[k] = Clean(v, 4)
            end
        end
    end
    table.sort(fns)
    return { functions = fns, strings = strings, tables = tables, namespaces = namespaces }
end

-- A stand-in for GameTooltip that keeps the lines, for the panel's own tooltips.
local function Collector()
    local c = { lines = {} }
    function c:AddLine(text) self.lines[#self.lines + 1] = Clean(text, 0) end
    function c:AddDoubleLine(l, r) self.lines[#self.lines + 1] = Clean(l, 0) .. "  =  " .. Clean(r, 0) end
    return c
end

local function OursDump()
    local out = {}
    for _, sec in ipairs(ns.Sections) do
        for _, cell in ipairs(sec.cells) do
            local label = type(cell.label) == "function" and select(2, pcall(cell.label)) or cell.label
            local ok, text, zero = pcall(cell.get)
            local row = { section = sec.key, label = Clean(label, 0), text = ok and Clean(text, 0) or ("<error> " .. tostring(text)), zero = zero }
            if cell.tip then
                local c = Collector()
                local okT, err = pcall(cell.tip, c)
                row.tip = okT and c.lines or ("<error> " .. tostring(err))
            end
            out[#out + 1] = row
        end
    end
    return out
end

local function TooltipLines()
    local lines = {}
    for i = 1, GameTooltip:NumLines() do
        local l = _G["GameTooltipTextLeft" .. i]
        local r = _G["GameTooltipTextRight" .. i]
        local lt = l and l:GetText()
        local rt = r and r:IsShown() and r:GetText()
        lt, rt = Clean(lt, 0), Clean(rt, 0)
        lines[#lines + 1] = rt and rt ~= "" and (tostring(lt) .. "  =  " .. tostring(rt)) or lt
    end
    return lines
end

-- Steps through Blizzard's list one row at a time: scrolls the row into view, runs its own
-- OnEnter and copies the tooltip it builds.
local function BlizzardDump(done)
    local box = _G.CharacterStatsPaneScrollBox
    local sb = box and box.ScrollBox
    if not (sb and sb.GetDataProvider and sb:GetDataProvider()) then
        done("<no stats list>")
        return
    end
    local rows = {}
    local list = {}
    sb:GetDataProvider():ForEach(function(data) list[#list + 1] = data end)
    local i = 0
    local function step()
        i = i + 1
        local data = list[i]
        if not data then
            GameTooltip:Hide()
            done(rows)
            return
        end
        local row = { data = Clean(data, 3) }
        rows[i] = row
        pcall(sb.ScrollToElementData, sb, data)
        C_Timer.After(0.05, function()
            local frame = sb.FindFrame and sb:FindFrame(data)
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
            step()
        end)
    end
    step()
end

-- The whole audit as one JSON string: a string always saves, where a table holding something
-- the game can't write (a NaN, say) can be dropped from the file without a word.
local function Json(v, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "{"
        local first = true
        for k, x in pairs(v) do
            if not first then out[#out + 1] = "," end
            first = false
            Json(tostring(k), out)
            out[#out + 1] = ":"
            Json(x, out)
        end
        out[#out + 1] = "}"
    elseif t == "string" then
        out[#out + 1] = '"' .. (v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end)) .. '"'
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            out[#out + 1] = '"' .. tostring(v) .. '"'
        else
            out[#out + 1] = string.format("%.10g", v)
        end
    elseif t == "boolean" then
        out[#out + 1] = tostring(v)
    else
        out[#out + 1] = "null"
    end
end

local function FormKey()
    local id = GetShapeshiftFormID and GetShapeshiftFormID()
    if not id or issecret(id) then return "normal" end
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
    local function save(rows)
        result.blizzard = rows
        local out = {}
        Json(result, out)
        ns.db.audits = ns.db.audits or {}
        ns.db.audits[key] = { time = result.time, json = table.concat(out) }
        print(("|cff40c0ffStatSheet|r: audit saved (%s). Type |cffffd100/reload|r to write it to disk.")
            :format(key))
    end
    -- Stepping through Blizzard's list (its rows and tooltips) only with "/statsheet audit full".
    if full then BlizzardDump(save) else save("<skipped>") end
end
