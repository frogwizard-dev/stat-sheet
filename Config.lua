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
    role = "auto",      -- "+10 of each" as melee, ranged or caster; "auto" goes by class and form
    compare = true,     -- add what an item would change to its tooltip
    compareBoth = true, -- a ring or trinket: compare with both you wear (false: the weaker only)
    collapsed = {},     -- blocks folded away by clicking their header
    pins = {},          -- rows shift-clicked into "Pinned" on the Overview, as "<section>:<label>"
    sections = { general = true, attributes = true, caps = true, melee = true, ranged = true, spell = true,
        defense = true, armorLevels = true, tanking = true, rage = true, supplies = true,
        ready = true, pet = true, measured = true, professions = true },
}

local CopyDefaults = FrogLib.Util.CopyDefaults

------------------------------------------------------------------------------
-- Settings window
------------------------------------------------------------------------------

local MODES = UI.Options("replace", "Replace the stats list", "beside", "Beside the window")
local THEMES = UI.Options("auto", "Follow the sheet", "ellesmere", "EllesmereUI (dark)", "blizzard", "Blizzard (Forever)")

local function Fonts()
    local groups = { { items = { { name = "Match the character sheet", path = "auto" } } } }
    for _, group in ipairs(ns.Media:List("font")) do groups[#groups + 1] = group end
    return groups
end

local function BuildLayout(page)
    local db = ns.db
    local place = UI.Placer()
    place(UI.Dropdown(page, "Placement", MODES, function() return db.mode end,
        function(value) db.mode = value end), 30)
    place(UI.Stepper(page, "Extra width", 0, 240, 10, function() return db.extraWidth end,
        function(value) db.extraWidth = value end), 26)
    place(UI.Stepper(page, "Width (beside)", 180, 420, 10, function() return db.width end,
        function(value) db.width = value end), 32)
    place(UI.Dropdown(page, "Look", THEMES, function() return db.theme end,
        function(value) db.theme = value end), 30)
    place(UI.Dropdown(page, "Font", Fonts, function() return db.font end,
        function(value) db.font = value end), 30)
    place(UI.Stepper(page, "Text size", 8, 16, 1, function() return db.size end,
        function(value) db.size = value end), 26)
    place(UI.Stepper(page, "Row spacing", 0, 10, 1, function() return db.rowGap end,
        function(value) db.rowGap = value end), 34)
    place(UI.Checkbox(page, "Hide stats that are zero (parry, block, hit, resistances...)",
        function() return db.hideZero end, function(value) db.hideZero = value end), 28)
    place(UI.Checkbox(page, "Show what each attribute gives (+56 AP, +160 HP...)",
        function() return db.attrEffects end, function(value) db.attrEffects = value end), 28)
    place(UI.Checkbox(page, "On item tooltips, show what wearing it would change",
        function() return db.compare end, function(value) db.compare = value end), 28)
    place(UI.Checkbox(page, "Compare a ring or trinket with both you wear (not just the weaker)",
        function() return db.compareBoth end, function(value) db.compareBoth = value end), 34)
    place(UI.Help(page, "Hover a stat for the details behind it, shift-click it to pin it to the top of "
        .. "the Overview, and click a header to fold its block away. In combat the game can hide some values; those keep their last reading, "
        .. "dimmed, until combat ends.", 400), 52, 4)
end

local SECTION_LABELS = {
    { "attributes", "Attributes (Overview)" },
    { "ready", "Ready to go: missing buffs, bag space (Overview)" },
    { "caps", "Caps: weapon skill, defense, hit (Overview)" },
    { "melee", "Melee (Offense)" },
    { "ranged", "Ranged, with a ranged weapon or wand (Offense)" },
    { "spell", "Spells, for classes with mana (Offense)" },
    { "pet", "Your pet (Offense)" },
    { "rage", "Rage: what swings and hits taken give (Offense)" },
    { "tanking", "Tanking a raid boss: threat, crushing blows, crits, block value (Defense)" },
    { "measured", "Measured in your fights: what enemies' swings really did (Defense)" },
    { "armorLevels", "Armor by enemy level (Defense)" },
    { "defense", "Defense: armor, dodge, resistances (Defense)" },
    { "supplies", "Ammo, weapon buffs & enchants (Gear)" },
    { "professions", "Professions (Gear)" },
    { "general", "General: speed, rage or energy (Gear)" },
}

local function BuildSections(page)
    local db = ns.db
    local place = UI.Placer()
    for _, section in ipairs(SECTION_LABELS) do
        local key = section[1]
        place(UI.Checkbox(page, section[2], function() return db.sections[key] end,
            function(value) db.sections[key] = value end), 28)
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
loader:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON then
        StatSheetDB = StatSheetDB or {}
        CopyDefaults(ns.defaults, StatSheetDB)
        ns.db = StatSheetDB
    elseif event == "PLAYER_LOGIN" then
        if _G.CharacterFrame then ns.Panel:Apply() end
    end
end)

SLASH_STATSHEET1 = "/statsheet"
SlashCmdList.STATSHEET = function(text)
    local command = strtrim(text or ""):lower()
    if command == "audit" or command == "audit full" then
        ns.Audit:Run(command == "audit full")
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
