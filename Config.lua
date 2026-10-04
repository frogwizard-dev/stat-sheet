local ADDON, ns = ...
local UI = ns.UI

ns.defaults = {
    mode = "replace",   -- "replace" the stats list, or sit "beside" the character window
    width = 250,        -- beside only
    extraWidth = 110,   -- replace only: how much wider the character window and its stats pane get
    font = "auto",      -- "auto" matches the character sheet (EllesmereUI's font when it's there)
    size = 10,
    rowGap = 2,
    hideZero = true,
    attrEffects = true, -- each attribute on its own row with what it gives (+56 AP, +160 HP...)
    theme = "auto",     -- "auto" follows the sheet (EllesmereUI's skin or Blizzard's), or pick one
    tab = "overview",   -- the tab open last
    role = "auto",      -- "+10 of each" as melee or caster; "auto" goes by class and form
    compare = true,     -- add what an item would change to its tooltip
    collapsed = {},     -- blocks folded away by clicking their header
    sections = { general = true, attributes = true, caps = true, melee = true, ranged = true, spell = true,
        defense = true, armorLevels = true },
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

------------------------------------------------------------------------------
-- Settings window
------------------------------------------------------------------------------

local MODES = UI.Options("replace", "Replace the stats list", "beside", "Beside the window")
local THEMES = UI.Options("auto", "Follow the sheet", "ellesmere", "EllesmereUI (dark)", "blizzard", "Blizzard (Forever)")

local function Fonts()
    local groups = { { items = { { name = "Match the character sheet", path = "auto" } } } }
    for _, g in ipairs(ns.Media:List("font")) do groups[#groups + 1] = g end
    return groups
end

local function BuildLayout(p)
    local db = ns.db
    local place = UI.Placer()
    place(UI.Dropdown(p, "Placement", MODES, function() return db.mode end,
        function(v) db.mode = v end), 30)
    place(UI.Stepper(p, "Extra width", 0, 240, 10, function() return db.extraWidth end,
        function(v) db.extraWidth = v end), 26)
    place(UI.Stepper(p, "Width (beside)", 180, 420, 10, function() return db.width end,
        function(v) db.width = v end), 32)
    place(UI.Dropdown(p, "Look", THEMES, function() return db.theme end, function(v) db.theme = v end), 30)
    place(UI.Dropdown(p, "Font", Fonts, function() return db.font end, function(v) db.font = v end), 30)
    place(UI.Stepper(p, "Text size", 8, 16, 1, function() return db.size end, function(v) db.size = v end), 26)
    place(UI.Stepper(p, "Row spacing", 0, 10, 1, function() return db.rowGap end,
        function(v) db.rowGap = v end), 34)
    place(UI.Checkbox(p, "Hide stats that are zero (parry, block, hit, resistances...)",
        function() return db.hideZero end, function(v) db.hideZero = v end), 28)
    place(UI.Checkbox(p, "Show what each attribute gives (+56 AP, +160 HP...)",
        function() return db.attrEffects end, function(v) db.attrEffects = v end), 28)
    place(UI.Checkbox(p, "On item tooltips, show what wearing it would change",
        function() return db.compare end, function(v) db.compare = v end), 34)
    place(UI.Help(p, "Hover a stat for the details behind it, and click a header to fold its block "
        .. "away. In combat the game can hide some values; those keep their last reading, "
        .. "dimmed, until combat ends.", 400), 40, 4)
end

local SECTION_LABELS = {
    { "attributes", "Attributes (Overview)" },
    { "caps", "Caps: weapon skill, defense, hit (Overview)" },
    { "melee", "Melee (Offense)" },
    { "ranged", "Ranged, with a ranged weapon or wand (Offense)" },
    { "spell", "Spells, for classes with mana (Offense)" },
    { "armorLevels", "Armor by enemy level (Defense)" },
    { "defense", "Defense: armor, dodge, resistances (Defense)" },
    { "general", "General: speed, rage or energy (Gear)" },
}

local function BuildSections(p)
    local db = ns.db
    local place = UI.Placer()
    for _, s in ipairs(SECTION_LABELS) do
        local key = s[1]
        place(UI.Checkbox(p, s[2], function() return db.sections[key] end,
            function(v) db.sections[key] = v end), 28)
    end
end

function ns.ToggleConfig()
    if not ns.window then
        ns.window = UI.Window("StatSheetConfig", "StatSheet", 460, 500, {
            { "layout", "Layout", BuildLayout },
            { "sections", "Sections", BuildSections },
        })
        return
    end
    ns.window:SetShown(not ns.window:IsShown())
end

------------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------------

function ns.Refresh()
    if ns.Panel.frame then ns.Panel:Apply() end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        StatSheetDB = StatSheetDB or {}
        CopyDefaults(ns.defaults, StatSheetDB)
        ns.db = StatSheetDB
    elseif event == "PLAYER_LOGIN" then
        if _G.CharacterFrame then ns.Panel:Apply() end
    end
end)

SLASH_STATSHEET1 = "/statsheet"
SlashCmdList.STATSHEET = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "audit" or cmd == "audit full" then
        ns.Audit:Run(cmd == "audit full")
    else
        ns.ToggleConfig()
    end
end
function StatSheet_OnCompartmentClick() ns.ToggleConfig() end

-- Its entry in the game's Options > AddOns list (Options.lua).
FrogLib.Options.Add("StatSheet", ns, {
    open = function()
        if not (ns.window and ns.window:IsShown()) then ns.ToggleConfig() end
    end,
    commands = {
        { "/statsheet", "open or close the settings" },
        { "/statsheet audit", "save every stat the game reports, to check the panel against" },
    },
})
