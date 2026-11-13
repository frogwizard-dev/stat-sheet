local _, ns = ...

-- The panel: a row of tabs (Tabs.lua) and the chosen tab's blocks laid out top to bottom. "replace" puts it
-- over Blizzard's stats list, invisible but in place so the panel follows its tab switching; "beside" hangs
-- it off the character window. Two looks, following the sheet: EllesmereUI's (dark, Expressway, coloured
-- header lines) and Forever's (its bronze header bars and shaded rows, Friz Quadrata and Arial Narrow).
local Panel = {}
ns.Panel = Panel

local PAD = 10          -- left and right margin inside the panel
local GAP = 12          -- between the two columns of a section
local TILE_GAP = 6
local BLOCK_GAP = 8
local NARROW = 280      -- inner widths below this get the narrow layout

-- EllesmereUI's character sheet colours, and the overrides from its options page when it's
-- installed, so the panel matches the rest of the sheet.
local DEFAULT_COLORS = {
    General             = { r = 0.30,  g = 0.80,  b = 0.95 },
    Attributes          = { r = 0.047, g = 0.824, b = 0.616 },
    Attack              = { r = 1,     g = 0.48,  b = 0.24 },
    ["Secondary Stats"] = { r = 0.65,  g = 0.52,  b = 0.96 },
    Defense             = { r = 0.35,  g = 0.70,  b = 1 },
    Insights            = { r = 1,     g = 0.78,  b = 0.25 },
    Gear                = { r = 0.75,  g = 0.78,  b = 0.80 },
}

local function SectionColor(key)
    local db = _G.EllesmereUIDB
    local custom = db and db.statCategoryUseColor and db.statCategoryUseColor[key]
        and db.statCategoryColors and db.statCategoryColors[key]
    local color = (type(custom) == "table" and custom.r and custom) or DEFAULT_COLORS[key] or DEFAULT_COLORS.General
    return color.r, color.g, color.b
end

local LOOKS = {
    ellesmere = {
        text = { 0.90, 0.91, 0.92 }, label = { 0.65, 0.69, 0.72 }, note = { 0.60, 0.64, 0.67 },
        caption = { 0.55, 0.58, 0.62 }, colourValues = true, headerLines = true,
        cardBg = { 0.086, 0.106, 0.125, 1 }, cardEdge = { 0.137, 0.165, 0.192, 1 },
        track = { 0.137, 0.165, 0.192, 1 }, tabIdle = { 0.55, 0.58, 0.62 },
        sizes = { body = 1, note = 0, caption = -1, number = 9, header = 2, tab = 1 },
        fade = { 0.035, 0.043, 0.051, 0.85 },
    },
    blizzard = {
        text = { 1, 1, 1 }, label = { 1, 0.82, 0 }, note = { 0.80, 0.75, 0.64 },
        caption = { 1, 0.82, 0 }, value = { 1, 1, 1 },
        headerAtlas = "UI-Character-Info-Title", rowAtlas = "UI-Character-Info-Line-Bounce",
        border = "common-insideframe", bar = { 0.79, 0.60, 0.18 },
        cardBg = { 0, 0, 0, 0.45 }, cardEdge = { 0.42, 0.32, 0.19, 1 },
        track = { 0, 0, 0, 0.5 }, tabIdle = { 0.79, 0.66, 0.42 },
        sizes = { body = 0, note = 0, caption = -1, number = 7, header = 1, tab = 0 },
        fade = { 0, 0, 0, 0.6 },
    },
}

-- Which look the sheet has. EllesmereUI's skin fades the stone backdrop behind the stats; with
-- that faded, the sheet is EllesmereUI's.
function ns.Theme()
    local choice = ns.db.theme
    if choice == "ellesmere" or choice == "blizzard" then return choice end
    local host = _G.CharacterFrame and _G.CharacterFrame.RightPaneHost
    local stone = host and host.StoneBg
    if _G.EllesmereUI and stone and stone:GetAlpha() < 0.05 then return "ellesmere" end
    return "blizzard"
end

-- The fonts for each role. EllesmereUI's look: Expressway (bold for numbers and headers).
-- Forever's: the game's own, read from its font objects (Friz Quadrata, and Arial Narrow small print).
local EXPRESSWAY = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local EXPRESSWAY_BOLD = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway Bold.ttf"

local function FontOf(objectName, fallback)
    local fontObject = _G[objectName]
    local path = fontObject and fontObject.GetFont and fontObject:GetFont()
    return path or fallback
end

function ns.Fonts(theme)
    local font = ns.db.font
    if font and font ~= "auto" then
        return { body = font, bold = font, number = font, note = font }
    end
    if theme == "ellesmere" then
        return { body = EXPRESSWAY, bold = EXPRESSWAY_BOLD, number = EXPRESSWAY_BOLD, note = EXPRESSWAY }
    end
    local friz = FontOf("GameFontNormal", STANDARD_TEXT_FONT)
    return { body = friz, bold = friz, number = friz, note = FontOf("NumberFontNormal", "Fonts\\ARIALN.TTF") }
end

local function SetFont(text, path, size)
    -- Only when it changes (FrogLib's Media notes the font it set on the text).
    if text.frogFont ~= path .. "|" .. size .. "|" then ns.Media:SetFont(text, path, size, "") end
end

-- One screen pixel in the frame's units, for hairlines.
local function OnePixel(frame)
    local ok, pixel = pcall(FrogLib.Pixel, frame)
    return (ok and pixel and pixel > 0) and pixel or 1
end

local function SetColor(text, color, alpha) text:SetTextColor(color[1], color[2], color[3], alpha or 1) end

------------------------------------------------------------------------------
-- Reading values
------------------------------------------------------------------------------

-- Per cell or tile: text, label, zero flag, note and bar last read, and stale (couldn't be read
-- this time: secret in combat, so the last readable values stay, dimmed).
local readings = {}

-- A cell's get() returns its text (false: leave it out), whether it's a zero "Hide zeros" may drop,
-- a note (whole-row cells) and a bar's fill (0-1).
local function Read(item, labelKey)
    local reading = readings[item]
    if not reading then
        reading = {}
        readings[item] = reading
    end
    local ok, text, zero, note, bar = pcall(item.get)
    if ok then
        reading.stale = false
        if text then
            reading.text, reading.zero, reading.note, reading.bar = text, zero, note, bar
        else
            reading.text = nil
        end
    else
        reading.stale = true
    end
    local label = item[labelKey or "label"]
    if type(label) == "function" then
        local okLabel, worked = pcall(label)
        if okLabel and worked then reading.label = worked end
    else
        reading.label = label
    end
    return reading
end

-- A block's computed rows (bars, chips, worth): the last good result when it can't be read now.
local cache = {}
local function Rows(key, Compute)
    local ok, rows = pcall(Compute)
    if ok and type(rows) == "table" then
        cache[key] = rows
        return rows, false
    end
    return cache[key], true
end

local sectionShown = {}
local function SectionShown(section)
    if ns.db.sections[section.key] == false then return false end
    if not section.show then return true end
    local ok, shown = pcall(section.show)
    if ok then sectionShown[section] = shown and true or false end
    return sectionShown[section] ~= false
end

------------------------------------------------------------------------------
-- Pins: shift-clicking a stat row puts it in "Pinned" at the top of the Overview. Saved as
-- "<section key>:<label>" in db.pins, in the order they were pinned.
------------------------------------------------------------------------------

-- Where each pinned key's row is: filled in as rows are laid out, and by one look through every
-- section (ns.PinSections, Tabs.lua) for keys not seen yet.
local pinIndex, pinSourceOf = {}, {}
local pinScanned = false

local function Pins()
    if type(ns.db.pins) ~= "table" then ns.db.pins = {} end
    return ns.db.pins
end

local function IsPinned(key)
    if not key then return false end
    for _, pinned in ipairs(Pins()) do
        if pinned == key then return true end
    end
    return false
end

local function TogglePin(key)
    if not key then return end
    local pins = Pins()
    for i, pinned in ipairs(pins) do
        if pinned == key then
            table.remove(pins, i)
            return
        end
    end
    pins[#pins + 1] = key
    pinScanned = false
end

-- A row's key: its section's and its name (the name it showed, for names that are worked out).
local function PinKey(section, cell, reading)
    if cell.pinKey then return cell.pinKey end
    local label = cell.label
    if type(label) ~= "string" then label = reading and reading.label end
    if type(label) ~= "string" or label == "" or FrogLib.issecret(label) then return nil end
    return section.key .. ":" .. label
end

local function ShowTip(button)
    local item = button.item
    if not item then return end
    local reading = readings[item]
    if not (item.tip or button.pinKey) then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddDoubleLine(reading and reading.label or "", reading and reading.text or "", 1, 1, 1, 1, 1, 1)
    if item.tip then pcall(item.tip, GameTooltip) end
    if reading and reading.stale then
        GameTooltip:AddLine("Last value read; it can't be read in combat.", 0.6, 0.6, 0.6, true)
    end
    if button.pinKey then
        GameTooltip:AddLine(IsPinned(button.pinKey) and "Shift-click to unpin" or "Shift-click to pin to the Overview",
            0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

local function HideTip() GameTooltip:Hide() end

local function CellClick(button)
    if not (button.pinKey and IsShiftKeyDown()) then return end
    TogglePin(button.pinKey)
    Panel:Layout()
    if GameTooltip:IsOwned(button) then ShowTip(button) end
end

local function Text(parent, layer)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    text:SetWordWrap(false)
    return text
end

local function Edges(frame, color, pixel)
    if not frame.edges then
        frame.edges = {}
        for i = 1, 4 do frame.edges[i] = frame:CreateTexture(nil, "BORDER") end
    end
    local edges = frame.edges
    for i = 1, 4 do
        edges[i]:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        edges[i]:ClearAllPoints()
    end
    edges[1]:SetPoint("TOPLEFT") edges[1]:SetPoint("TOPRIGHT") edges[1]:SetHeight(pixel)
    edges[2]:SetPoint("BOTTOMLEFT") edges[2]:SetPoint("BOTTOMRIGHT") edges[2]:SetHeight(pixel)
    edges[3]:SetPoint("TOPLEFT") edges[3]:SetPoint("BOTTOMLEFT") edges[3]:SetWidth(pixel)
    edges[4]:SetPoint("TOPRIGHT") edges[4]:SetPoint("BOTTOMRIGHT") edges[4]:SetWidth(pixel)
end

------------------------------------------------------------------------------
-- Widgets (pooled; each layout reuses them in order)
------------------------------------------------------------------------------

local MAKERS = {}

-- The switch's names. Which three you get is ns.Roles, and what Auto picks is ns.WorthRole (Tabs.lua).
local ROLE_NAMES = { auto = "Auto", melee = "Melee", ranged = "Ranged", caster = "Caster" }
local ROLE_BUTTONS = 3

-- One switch button: the choice lit, and under Auto what it picked lit faintly.
local function PaintRole(button, look, gold)
    local choice = ns.RoleChoice()
    if button.role == choice then
        button.bg:SetColorTexture(gold[1], gold[2], gold[3], 1)
        button.text:SetTextColor(0.06, 0.07, 0.08)
    elseif choice == "auto" and button.role == ns.WorthRole() then
        button.bg:SetColorTexture(gold[1], gold[2], gold[3], 0.28)
        SetColor(button.text, look.text)
    else
        button.bg:SetColorTexture(0, 0, 0, 0.35)
        SetColor(button.text, look.tabIdle)
    end
end

-- A row of switch buttons on `parent`; each layout gives them their roles.
local function RoleButtons(parent)
    local buttons = {}
    for i = 1, ROLE_BUTTONS do
        local button = CreateFrame("Button", nil, parent)
        button.bg = button:CreateTexture(nil, "BACKGROUND")
        button.bg:SetAllPoints()
        button.text = Text(button)
        button.text:SetPoint("CENTER")
        button:SetScript("OnClick", function(self)
            ns.db.role = self.role
            Panel:Layout()
        end)
        buttons[i] = button
    end
    return buttons
end

function MAKERS.cell(self)
    local cell = CreateFrame("Button", nil, self.content)
    cell.shade = cell:CreateTexture(nil, "BACKGROUND")
    cell.label = Text(cell)
    cell.label:SetPoint("TOPLEFT", 0, 0)
    cell.label:SetJustifyH("LEFT")
    cell.value = Text(cell)
    cell.value:SetPoint("TOPRIGHT", 0, 0)
    cell.value:SetJustifyH("RIGHT")
    cell.note = Text(cell)
    cell.note:SetJustifyH("LEFT")
    cell.barBg = cell:CreateTexture(nil, "ARTWORK")
    cell.barFill = cell:CreateTexture(nil, "ARTWORK", nil, 1)
    cell.barFill:SetPoint("TOPLEFT", cell.barBg, "TOPLEFT")
    cell.barFill:SetPoint("BOTTOMLEFT", cell.barBg, "BOTTOMLEFT")
    local highlight = cell:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", -4, 0)
    highlight:SetPoint("BOTTOMRIGHT", 4, 0)
    highlight:SetColorTexture(1, 1, 1, 0.05)
    cell:SetScript("OnEnter", ShowTip)
    cell:SetScript("OnLeave", HideTip)
    cell:SetScript("OnClick", CellClick)
    return cell
end

-- Block headers fold their block away when clicked anywhere on the row (remembered per block).
-- An arrow before the name shows which way it is: right folded, down open.
local FOLD_ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

function MAKERS.header(self)
    local header = CreateFrame("Button", nil, self.content)
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.title = Text(header)
    header.left = header:CreateTexture(nil, "ARTWORK")
    header.right = header:CreateTexture(nil, "ARTWORK")
    header.arrow = header:CreateTexture(nil, "OVERLAY")
    header.arrow:SetTexture(FOLD_ARROW)
    local highlight = header:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.07)
    header:SetScript("OnClick", function(self)
        local collapsed = ns.db.collapsed
        collapsed[self.key] = not collapsed[self.key] or nil
        Panel:Layout()
    end)
    return header
end

function MAKERS.tile(self)
    local tile = CreateFrame("Button", nil, self.content)
    tile.bg = tile:CreateTexture(nil, "BACKGROUND")
    tile.bg:SetAllPoints()
    tile.caption = Text(tile)
    tile.caption:SetPoint("TOPLEFT", 8, -8)
    tile.caption:SetPoint("TOPRIGHT", -6, -8)
    tile.caption:SetJustifyH("LEFT")
    tile.value = Text(tile)
    tile.value:SetJustifyH("LEFT")
    tile.sub = Text(tile)
    tile.sub:SetJustifyH("LEFT")
    tile.sub:SetJustifyV("TOP")
    tile.sub:SetWordWrap(true)
    if tile.sub.SetMaxLines then tile.sub:SetMaxLines(2) end
    tile:SetScript("OnEnter", ShowTip)
    tile:SetScript("OnLeave", HideTip)
    return tile
end

-- One stacked bar row: an optional line of label and right-hand text, the bar, a legend.
function MAKERS.barRow(self)
    local row = CreateFrame("Frame", nil, self.content)
    row.label = Text(row)
    row.label:SetPoint("TOPLEFT", 0, 0)
    row.right = Text(row)
    row.right:SetPoint("TOPRIGHT", 0, 0)
    row.track = row:CreateTexture(nil, "BACKGROUND")
    row.segs, row.keys = {}, {}
    row.foot = Text(row)
    row.foot:SetJustifyH("LEFT")
    return row
end

function MAKERS.card(self)
    local card = CreateFrame("Frame", nil, self.content)
    card.bg = card:CreateTexture(nil, "BACKGROUND")
    card.bg:SetAllPoints()
    card.title = Text(card)
    card.title:SetPoint("TOPLEFT", 10, -10)
    card.toggles = RoleButtons(card)
    card.rows = {}
    return card
end

function MAKERS.chip(self)
    local chip = CreateFrame("Frame", nil, self.content)
    chip.bg = chip:CreateTexture(nil, "BACKGROUND")
    chip.bg:SetAllPoints()
    chip.text = Text(chip)
    chip.text:SetPoint("CENTER")
    return chip
end

-- A small card: icon, title, a number on the right, and lines under the title.
function MAKERS.entry(self)
    local entry = CreateFrame("Frame", nil, self.content)
    entry.bg = entry:CreateTexture(nil, "BACKGROUND")
    entry.bg:SetAllPoints()
    entry.icon = entry:CreateTexture(nil, "ARTWORK")
    entry.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    entry.title = Text(entry)
    entry.title:SetJustifyH("LEFT")
    entry.right = Text(entry)
    entry.right:SetJustifyH("RIGHT")
    entry.lines = {}
    return entry
end

-- The switch on its own line.
function MAKERS.roleBar(self)
    local bar = CreateFrame("Frame", nil, self.content)
    bar.label = Text(bar)
    bar.label:SetPoint("LEFT", 0, 0)
    bar.buttons = RoleButtons(bar)
    return bar
end

function MAKERS.foot(self)
    local text = self.content:CreateFontString(nil, "OVERLAY")
    text:SetJustifyH("LEFT")
    return text
end

function Panel:Get(kind)
    local pool, used = self.pools[kind], self.used
    used[kind] = (used[kind] or 0) + 1
    local widget = pool[used[kind]]
    if not widget then
        widget = MAKERS[kind](self)
        pool[used[kind]] = widget
    end
    widget:ClearAllPoints()
    widget:Show()
    return widget
end

------------------------------------------------------------------------------
-- The frame
------------------------------------------------------------------------------

function Panel:Create()
    if self.frame then return end
    local frame = CreateFrame("Frame", "StatSheetPanel", UIParent, "BackdropTemplate")
    frame:EnableMouse(true)
    frame:Hide()
    self.frame = frame

    -- Blizzard's inner frame edge, which the hidden list would otherwise have drawn.
    frame.border = frame:CreateTexture(nil, "BORDER")
    frame.border:SetPoint("TOPLEFT", 1, 1)
    frame.border:SetPoint("BOTTOMRIGHT", -4, 2)

    -- Tabs along the top.
    self.tabs = {}
    for i, tab in ipairs(ns.Tabs) do
        local button = CreateFrame("Button", nil, frame)
        button.text = Text(button)
        button.text:SetPoint("CENTER", 0, 1)
        button.line = button:CreateTexture(nil, "ARTWORK")
        button.line:SetPoint("BOTTOMLEFT", 4, 0)
        button.line:SetPoint("BOTTOMRIGHT", -4, 0)
        button.line:SetHeight(2)
        button.key = tab.key
        button:SetScript("OnClick", function(self)
            ns.db.tab = self.key
            Panel.scroll:SetVerticalScroll(0)
            Panel:Layout()
        end)
        self.tabs[i] = button
    end
    frame.tabRule = frame:CreateTexture(nil, "ARTWORK")

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("BOTTOMRIGHT", 0, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    self.scroll, self.content = scroll, content
    scroll:SetScript("OnSizeChanged", function()
        if frame:IsVisible() then Panel:Layout() end
    end)

    -- A thin bar that only shows when there's more than fits.
    local thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(1, 1, 1, 0.25)
    thumb:SetWidth(2)
    self.thumb = thumb

    -- Fades at the top and bottom of the scroll area while there's more that way. On a frame of
    -- their own above the content (a parent's textures draw under its children); no mouse.
    local over = CreateFrame("Frame", nil, frame)
    over:SetAllPoints(scroll)
    self.over = over
    self.fadeTop = over:CreateTexture(nil, "OVERLAY")
    self.fadeTop:SetPoint("TOPLEFT")
    self.fadeTop:SetPoint("TOPRIGHT")
    self.fadeTop:SetHeight(16)
    self.fadeBottom = over:CreateTexture(nil, "OVERLAY")
    self.fadeBottom:SetPoint("BOTTOMLEFT")
    self.fadeBottom:SetPoint("BOTTOMRIGHT")
    self.fadeBottom:SetHeight(22)
    self.fadeTop:Hide()
    self.fadeBottom:Hide()

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local range = scroll:GetVerticalScrollRange()
        local position = math.max(0, math.min(range, scroll:GetVerticalScroll() - delta * 40))
        scroll:SetVerticalScroll(position)
        Panel:PlaceThumb()
    end)

    self.pools, self.used = {}, {}
    for kind in pairs(MAKERS) do self.pools[kind] = {} end
    frame:SetScript("OnShow", function() Panel:OnShow() end)
    frame:SetScript("OnHide", function() Panel:OnHide() end)
    frame:SetScript("OnEvent", function(_, event) Panel:OnEvent(event) end)
end

-- The fades in the look's background colour: solid at the edge, clear toward the middle.
-- 12.x's SetGradient takes colour objects; VERTICAL runs from the bottom (first) to the top.
function Panel:PaintFades(look)
    if self.fadeLook == look then return end
    self.fadeLook = look
    local fade = look.fade
    local solid, clear = CreateColor(fade[1], fade[2], fade[3], fade[4]), CreateColor(fade[1], fade[2], fade[3], 0)
    for _, texture in ipairs({ self.fadeTop, self.fadeBottom }) do texture:SetColorTexture(1, 1, 1, 1) end
    self.fadeTop:SetGradient("VERTICAL", clear, solid)
    self.fadeBottom:SetGradient("VERTICAL", solid, clear)
end

function Panel:PlaceThumb()
    local scroll, thumb = self.scroll, self.thumb
    local range = scroll:GetVerticalScrollRange()
    if range <= 0.5 then
        thumb:Hide()
        scroll:SetVerticalScroll(0)
        self.fadeTop:Hide()
        self.fadeBottom:Hide()
        return
    end
    local position = scroll:GetVerticalScroll()
    self.fadeTop:SetShown(position > 1)
    self.fadeBottom:SetShown(position < range - 1)
    local height = scroll:GetHeight()
    local size = math.max(20, height * height / (height + range))
    local offset = (height - size) * (position / range)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -2, -offset)
    thumb:SetHeight(size)
    thumb:Show()
end

local function CurrentTab()
    for _, tab in ipairs(ns.Tabs) do
        if tab.key == ns.db.tab then return tab end
    end
    return ns.Tabs[1]
end

-- The tab row; returns its height.
function Panel:LayTabs(context)
    local frame, look = self.frame, context.look
    local current = CurrentTab()
    local _, class = UnitClass("player")
    local classR, classG, classB = FrogLib.Color.Class(class)
    if not classR then classR, classG, classB = 1, 0.82, 0 end
    local height = context.size + 14
    local x = PAD - 4
    for i, button in ipairs(self.tabs) do
        local tab = ns.Tabs[i]
        SetFont(button.text, tab == current and context.fonts.bold or context.fonts.body, context.size + look.sizes.tab)
        button.text:SetText(tab.title)
        local width = button.text:GetStringWidth() + 14
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -4)
        button:SetSize(width, height)
        x = x + width
        if tab == current then
            if look.headerAtlas then
                button.text:SetTextColor(1, 0.82, 0)
                button.line:SetColorTexture(1, 0.82, 0, 0.9)
            else
                SetColor(button.text, look.text)
                button.line:SetColorTexture(classR, classG, classB, 1)
            end
            button.line:Show()
        else
            SetColor(button.text, look.tabIdle)
            button.line:Hide()
        end
    end
    frame.tabRule:ClearAllPoints()
    frame.tabRule:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD - 4, -(4 + height))
    frame.tabRule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(PAD - 4), -(4 + height))
    frame.tabRule:SetHeight(context.pixel)
    frame.tabRule:SetColorTexture(1, 1, 1, 0.08)
    return height + 6
end

------------------------------------------------------------------------------
-- Blocks
------------------------------------------------------------------------------

local LAYOUTS = {}

-- A block's header; returns the y under it and whether the block is folded away.
function Panel:Header(context, y, key, title, colorKey)
    local look = context.look
    local r, g, b = SectionColor(colorKey)
    local collapsed = ns.db.collapsed[key]
    local header = self:Get("header")
    header.key = key
    local height = look.headerAtlas and context.size + 14 or context.size + 10
    header:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, y)
    header:SetSize(context.inner, height)
    SetFont(header.title, context.fonts.bold, context.size + look.sizes.header)
    header.title:SetText(title)
    header.folded = collapsed and true or false
    -- The arrow: pointing right while folded, down while open.
    local arrow, arrowSize = header.arrow, math.floor(context.size + look.sizes.header + 2)
    arrow:SetSize(arrowSize, arrowSize)
    arrow:SetRotation(collapsed and 0 or -math.pi / 2)
    arrow:ClearAllPoints()
    header.title:ClearAllPoints()
    if look.headerAtlas then
        header.title:SetPoint("CENTER", arrowSize / 2, 1)
        arrow:SetPoint("RIGHT", header.title, "LEFT", -3, 0)
        arrow:SetVertexColor(1, 0.82, 0)
        header.bg:SetAtlas(look.headerAtlas)
        header.bg:Show()
        header.left:Hide()
        header.right:Hide()
        header.title:SetTextColor(1, 1, 1)
    else
        -- EllesmereUI: the title on the left, a thin line in its colour running to the right.
        arrow:SetPoint("LEFT", -3, 0)
        arrow:SetVertexColor(r, g, b, 0.9)
        header.title:SetPoint("LEFT", arrow, "RIGHT", 1, 0)
        header.bg:Hide()
        header.left:Hide()
        header.title:SetTextColor(r, g, b)
        header.right:ClearAllPoints()
        header.right:SetPoint("LEFT", header.title, "RIGHT", 8, 0)
        header.right:SetPoint("RIGHT", header, "RIGHT", 0, 0)
        header.right:SetColorTexture(r, g, b, 0.25)
        header.right:SetHeight(context.pixel)
        header.right:Show()
    end
    return y - height - 4, collapsed
end

function Panel:Foot(context, y, text, x)
    local foot = self:Get("foot")
    SetFont(foot, context.fonts.note, context.size + context.look.sizes.note - 1)
    SetColor(foot, context.look.note)
    foot:SetWidth(context.inner)
    foot:SetWordWrap(true)
    foot:SetText(text)
    foot:SetPoint("TOPLEFT", self.content, "TOPLEFT", x or PAD, y)
    return y - foot:GetStringHeight() - 4
end

function LAYOUTS.tiles(self, block, y, context)
    local look = context.look
    local items = {}
    for _, tile in ipairs(block.tiles) do
        local reading = Read(tile, "caption")
        if reading.text then items[#items + 1] = tile end
    end
    if #items == 0 then return y end
    -- Narrow: two to a row (a row with one left over gives it the whole width).
    local perRow = (context.narrow and #items > 2) and 2 or #items
    local captionSize = context.size + look.sizes.caption
    local numberSize = context.size + look.sizes.number
    local noteSize = context.size + look.sizes.note - 1
    local rows = {}
    for first = 1, #items, perRow do
        local row = {}
        for index = first, math.min(#items, first + perRow - 1) do row[#row + 1] = items[index] end
        rows[#rows + 1] = row
    end
    for _, row in ipairs(rows) do
        local width = (context.inner - TILE_GAP * (#row - 1)) / #row
        -- The line under the number wraps onto a second line when it needs to; the whole row
        -- grows to the tallest.
        local frames, noteHeight = {}, noteSize
        for i, tile in ipairs(row) do
            local reading = readings[tile]
            local frame = self:Get("tile")
            frames[i] = frame
            frame.item = tile
            SetFont(frame.sub, context.fonts.note, noteSize)
            frame.sub:SetWidth(math.max(10, width - 12))
            frame.sub:SetText(reading.note or "")
            noteHeight = math.max(noteHeight, math.min(frame.sub:GetStringHeight(), noteSize * 2 + 4))
        end
        local height = 8 + captionSize + 4 + numberSize + 4 + noteHeight + 8
        for i, tile in ipairs(row) do
            local reading = readings[tile]
            local frame = frames[i]
            frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD + (i - 1) * (width + TILE_GAP), y)
            frame:SetSize(width, height)
            frame.bg:SetColorTexture(unpack(look.cardBg))
            Edges(frame, look.cardEdge, context.pixel)
            SetFont(frame.caption, context.fonts.bold, captionSize)
            SetFont(frame.value, context.fonts.number, numberSize)
            frame.caption:SetText(reading.label or "")
            SetColor(frame.caption, look.caption)
            frame.value:ClearAllPoints()
            frame.value:SetPoint("TOPLEFT", frame.caption, "BOTTOMLEFT", 0, -4)
            frame.value:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
            frame.value:SetText(reading.text)
            if look.colourValues then
                local r, g, b = SectionColor(tile.colorKey)
                frame.value:SetTextColor(r, g, b, reading.stale and 0.45 or 1)
            else
                SetColor(frame.value, look.value, reading.stale and 0.45 or 1)
            end
            frame.sub:ClearAllPoints()
            frame.sub:SetPoint("TOPLEFT", frame.value, "BOTTOMLEFT", 0, -4)
            frame.sub:SetHeight(noteHeight)
            SetColor(frame.sub, look.note)
            frame:EnableMouse(tile.tip ~= nil)
        end
        y = y - height - TILE_GAP
    end
    return y + TILE_GAP - BLOCK_GAP
end

-- Fills one cell and returns its height: the name and value line, then a bar and a note (whole-row
-- cells only; half a row keeps to one line). A note that fits goes beside the name instead.
function Panel:FillCell(cell, reading, context, width, wide, r, g, b)
    local look, rowHeight = context.look, context.rowHeight
    SetFont(cell.label, context.fonts.body, context.size + look.sizes.body)
    SetFont(cell.value, context.fonts.bold, context.size + look.sizes.body)
    SetFont(cell.note, context.fonts.note, context.size + look.sizes.note - 1)
    cell.label:SetHeight(rowHeight)
    cell.value:SetHeight(rowHeight)
    cell.label:SetText(reading.label)
    SetColor(cell.label, look.label)
    cell.value:SetText(reading.text)
    if look.colourValues then
        cell.value:SetTextColor(r, g, b, reading.stale and 0.45 or 1)
    else
        SetColor(cell.value, look.value, reading.stale and 0.45 or 1)
    end

    local height = rowHeight
    cell.barBg:Hide()
    cell.barFill:Hide()
    if wide and type(reading.bar) == "number" then
        cell.barBg:ClearAllPoints()
        cell.barBg:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, -(height - 1))
        cell.barBg:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 0, -(height - 1))
        cell.barBg:SetHeight(4)
        cell.barBg:SetColorTexture(unpack(look.track))
        cell.barFill:SetWidth(math.max(1, width * math.max(0, math.min(1, reading.bar))))
        local barColor = look.bar
        if barColor then
            cell.barFill:SetColorTexture(barColor[1], barColor[2], barColor[3], 1)
        else
            cell.barFill:SetColorTexture(r, g, b, 1)
        end
        cell.barBg:Show()
        cell.barFill:Show()
        height = height + 6
    end

    local note = cell.note
    note:ClearAllPoints()
    if not (wide and reading.note and reading.note ~= "") then
        note:Hide()
        return height
    end
    note:SetText(reading.note)
    SetColor(note, look.note, reading.stale and 0.45 or 1)
    note:Show()
    note:SetWordWrap(false)
    note:SetWidth(0)
    local room = width - cell.label:GetStringWidth() - cell.value:GetStringWidth() - 20
    if height == rowHeight and note:GetStringWidth() <= room then
        note:SetJustifyV("MIDDLE")
        note:SetHeight(rowHeight)
        note:SetPoint("TOPLEFT", cell.label, "TOPRIGHT", 6, 0)
        return height
    end
    note:SetJustifyV("TOP")
    note:SetWordWrap(true)
    note:SetWidth(width)
    note:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, -height)
    note:SetHeight(note:GetStringHeight())
    return height + note:GetStringHeight() + 3
end

function LAYOUTS.section(self, block, y, context)
    local section = block.section
    if not SectionShown(section) then return y end
    -- block.skip: rows the tab's tiles already show, by name (or the row itself, when its name changes).
    local skip = block.skip
    local visible = {}
    for _, cell in ipairs(section.cells) do
        if not (skip and (skip[cell] or skip[cell.label])) then
            local reading = Read(cell)
            if reading.text and not (ns.db.hideZero and reading.zero) then visible[#visible + 1] = cell end
        end
    end
    if #visible == 0 then return y end
    local r, g, b = SectionColor(section.colorKey)
    local collapsed
    y, collapsed = self:Header(context, y, section.key, section.title, section.colorKey)
    if collapsed then return y - BLOCK_GAP end

    local look, rowHeight = context.look, context.rowHeight
    local column, rowIndex = 0, 0
    for _, cell in ipairs(visible) do
        local reading = readings[cell]
        local frame = self:Get("cell")
        frame.item = cell
        local wide = cell.wide
        if type(wide) == "function" then wide = wide() end
        -- Narrow: rows of two stack into one column.
        if context.narrow then wide = true end
        local x, width
        if wide then
            if column == 1 then
                y, column = y - rowHeight, 0
            end
            x, width = PAD, context.inner
        else
            x, width = PAD + column * (context.half + GAP), context.half
        end
        if column == 0 then rowIndex = rowIndex + 1 end
        frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, y)
        frame:SetWidth(width)
        local height = self:FillCell(frame, reading, context, width, wide, r, g, b)
        frame:SetHeight(height)
        -- Blizzard's list shades every other line.
        if look.rowAtlas and rowIndex % 2 == 1 and (wide or column == 0) then
            frame.shade:SetAtlas(look.rowAtlas)
            frame.shade:ClearAllPoints()
            frame.shade:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD - 6, y)
            frame.shade:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", context.inner + 6, 0)
            frame.shade:Show()
        else
            frame.shade:Hide()
        end
        -- Pinned rows keep the key of where they came from.
        frame.pinKey = cell.pinKey or PinKey(block.pinSource and block.pinSource[cell] or section, cell, reading)
        frame:EnableMouse(true)
        if frame.pinKey and not block.pinSource then
            pinIndex[frame.pinKey], pinSourceOf[cell] = cell, section
        end
        if wide then
            y = y - height
        elseif column == 1 then
            y, column = y - rowHeight, 0
        else
            column = 1
        end
    end
    if column == 1 then y = y - rowHeight end
    return y - BLOCK_GAP
end

-- Pinned: the rows shift-clicked anywhere, in the order they were pinned. A pin whose row is
-- gone (or has nothing to show right now) is left out quietly.
local pinnedSection = { key = "pinned", title = "Pinned", colorKey = "Insights", cells = {} }

local function IndexSection(section)
    for _, cell in ipairs(section.cells or {}) do
        local reading = (type(cell.label) ~= "string" and not cell.pinKey) and (readings[cell] or Read(cell)) or nil
        local key = PinKey(section, cell, reading)
        if key and not pinIndex[key] then pinIndex[key], pinSourceOf[cell] = cell, section end
    end
end

function LAYOUTS.pinned(self, block, y, context)
    local pins = Pins()
    if #pins == 0 then return y end
    local missing = false
    for _, key in ipairs(pins) do
        if not pinIndex[key] then missing = true end
    end
    if missing and not pinScanned and ns.PinSections then
        pinScanned = true
        for _, section in ipairs(ns.PinSections()) do pcall(IndexSection, section) end
    end
    local cells = {}
    for _, key in ipairs(pins) do
        if pinIndex[key] then cells[#cells + 1] = pinIndex[key] end
    end
    if #cells == 0 then return y end
    pinnedSection.cells = cells
    return LAYOUTS.section(self, { section = pinnedSection, pinSource = pinSourceOf }, y, context)
end

-- Stacked bars: each row's segments side by side, with a legend of coloured keys under it.
function LAYOUTS.bars(self, block, y, context)
    local rows, stale = Rows(block.key, block.rows)
    if not rows or #rows == 0 then return y end
    local collapsed
    y, collapsed = self:Header(context, y, block.key, block.title, block.colorKey)
    if collapsed then return y - BLOCK_GAP end
    local look = context.look
    local textSize = context.size + look.sizes.body
    local keySize = context.size + look.sizes.note - 1
    for _, row in ipairs(rows) do
        local frame = self:Get("barRow")
        frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, y)
        frame:SetWidth(context.inner)
        local height = 0
        if row.label then
            SetFont(frame.label, context.fonts.body, textSize)
            SetFont(frame.right, context.fonts.bold, textSize)
            frame.label:SetText(row.label)
            frame.right:SetText(row.right or "")
            SetColor(frame.label, look.label)
            SetColor(frame.right, look.text, stale and 0.45 or 1)
            frame.label:Show()
            frame.right:Show()
            height = textSize + 5
        else
            frame.label:Hide()
            frame.right:Hide()
        end
        -- The bar.
        local barHeight = 10
        frame.track:ClearAllPoints()
        frame.track:SetPoint("TOPLEFT", 0, -height)
        frame.track:SetSize(context.inner, barHeight)
        frame.track:SetColorTexture(unpack(look.track))
        local x, used = 0, 0
        local shown = {}
        for _, segment in ipairs(row.segs) do
            if segment.pct >= 0.05 then shown[#shown + 1] = segment end
        end
        for i, segment in ipairs(shown) do
            used = used + 1
            local texture = frame.segs[used]
            if not texture then
                texture = frame:CreateTexture(nil, "ARTWORK")
                frame.segs[used] = texture
            end
            local segmentWidth = context.inner * segment.pct / 100
            if i == #shown then segmentWidth = context.inner - x end
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", x, -height)
            texture:SetSize(math.max(context.pixel, segmentWidth - (i < #shown and context.pixel or 0)), barHeight)
            texture:SetColorTexture(segment.color[1], segment.color[2], segment.color[3], stale and 0.5 or 1)
            texture:Show()
            x = x + segmentWidth
        end
        for i = used + 1, #frame.segs do frame.segs[i]:Hide() end
        height = height + barHeight + 5
        -- The legend: a swatch and its text per segment, in as many columns as the widest text
        -- allows, so the keys never run into each other.
        local widest = 0
        for i, segment in ipairs(shown) do
            local key = frame.keys[i]
            if not key then
                key = { swatch = frame:CreateTexture(nil, "ARTWORK"), text = Text(frame) }
                frame.keys[i] = key
            end
            SetFont(key.text, context.fonts.note, keySize)
            key.text:SetText(segment.text)
            widest = math.max(widest, key.text:GetStringWidth())
        end
        local fit = math.max(1, math.floor(context.inner / (widest + 22)))
        local columns = math.max(1, math.min(row.cols or 4, fit, #shown))
        local columnWidth = context.inner / columns
        local lineHeight = keySize + 4
        for i, segment in ipairs(shown) do
            local key = frame.keys[i]
            local keyX = ((i - 1) % columns) * columnWidth
            local keyY = height + math.floor((i - 1) / columns) * lineHeight
            key.swatch:ClearAllPoints()
            key.swatch:SetPoint("TOPLEFT", keyX, -(keyY + 3))
            key.swatch:SetSize(7, 7)
            key.swatch:SetColorTexture(segment.color[1], segment.color[2], segment.color[3], 1)
            SetFont(key.text, context.fonts.note, keySize)
            SetColor(key.text, look.note)
            key.text:ClearAllPoints()
            key.text:SetPoint("TOPLEFT", keyX + 11, -keyY)
            key.text:SetText(segment.text)
            key.swatch:Show()
            key.text:Show()
        end
        for i = #shown + 1, #frame.keys do
            frame.keys[i].swatch:Hide()
            frame.keys[i].text:Hide()
        end
        height = height + math.ceil(#shown / columns) * lineHeight
        if row.foot then
            SetFont(frame.foot, context.fonts.note, keySize)
            SetColor(frame.foot, look.note)
            frame.foot:ClearAllPoints()
            frame.foot:SetPoint("TOPLEFT", 0, -height)
            frame.foot:SetText(row.foot)
            frame.foot:Show()
            height = height + lineHeight
        else
            frame.foot:Hide()
        end
        frame:SetHeight(height)
        y = y - height - 8
    end
    return y - BLOCK_GAP + 4
end

-- What +10 of each stat gets you, in a card, with the switch for anyone who has a choice.
function LAYOUTS.worth(self, block, y, context)
    local rows, stale = Rows("worth", ns.Worth)
    if not rows or #rows == 0 then return y end
    local look = context.look
    local card = self:Get("card")
    card:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, y)
    card:SetWidth(context.inner)
    card.bg:SetColorTexture(unpack(look.cardBg))
    Edges(card, look.cardEdge, context.pixel)
    local gold = { SectionColor("Insights") }
    local titleSize = context.size + look.sizes.header
    SetFont(card.title, context.fonts.bold, titleSize)
    card.title:SetText("What +10 of each gets you")
    card.title:SetTextColor(gold[1], gold[2], gold[3])

    -- The switch: beside the title, or under it when there isn't room.
    local roles = ns.Roles()
    local total = 0
    for i, button in ipairs(card.toggles) do
        button.role = roles and roles[i]
        SetFont(button.text, context.fonts.bold, context.size + look.sizes.note - 1)
        button.text:SetText(ROLE_NAMES[button.role] or "")
        total = total + button.text:GetStringWidth() + 14
    end
    local below = roles and card.title:GetStringWidth() + total + 28 > context.inner
    local x, top = -8, below and -(10 + titleSize + 6) or -8
    for i = #card.toggles, 1, -1 do
        local button = card.toggles[i]
        if roles then
            local width = button.text:GetStringWidth() + 12
            button:SetSize(width, titleSize + 4)
            button:ClearAllPoints()
            button:SetPoint("TOPRIGHT", card, "TOPRIGHT", x, top)
            x = x - width - 2
            PaintRole(button, look, gold)
            button:Show()
        else
            button:Hide()
        end
    end

    local inner = context.inner - 20
    local down = 10 + titleSize + 10 + (below and titleSize + 8 or 0)
    local textSize = context.size + look.sizes.body
    local noteSize = context.size + look.sizes.note - 1
    for i, row in ipairs(rows) do
        local parts = card.rows[i]
        if not parts then
            parts = { stat = Text(card), head = Text(card), track = card:CreateTexture(nil, "ARTWORK"),
                fill = card:CreateTexture(nil, "ARTWORK", nil, 1), detail = Text(card) }
            card.rows[i] = parts
        end
        SetFont(parts.stat, context.fonts.bold, textSize)
        SetFont(parts.head, context.fonts.bold, textSize)
        SetFont(parts.detail, context.fonts.note, noteSize)
        parts.stat:ClearAllPoints()
        parts.stat:SetPoint("TOPLEFT", 10, -down)
        parts.stat:SetText(row.stat)
        SetColor(parts.stat, look.text)
        parts.head:ClearAllPoints()
        parts.head:SetPoint("TOPRIGHT", -10, -down)
        parts.head:SetText(row.headline)
        local r, g, b = SectionColor(row.colorKey)
        parts.head:SetTextColor(r, g, b, stale and 0.45 or 1)
        down = down + textSize + 4
        parts.track:ClearAllPoints()
        parts.track:SetPoint("TOPLEFT", 10, -down)
        parts.track:SetSize(inner, 3)
        parts.track:SetColorTexture(unpack(look.track))
        -- Full at a 40% gain, so the bars compare across the different kinds of gain.
        local fill = row.gain and math.max(0, math.min(1, row.gain / 0.4)) or 0
        parts.fill:ClearAllPoints()
        parts.fill:SetPoint("TOPLEFT", parts.track, "TOPLEFT")
        parts.fill:SetSize(math.max(context.pixel, inner * fill), 3)
        parts.fill:SetColorTexture(r, g, b, 1)
        parts.fill:SetShown(fill > 0)
        down = down + 6
        parts.detail:ClearAllPoints()
        parts.detail:SetPoint("TOPLEFT", 10, -down)
        parts.detail:SetWidth(inner)
        parts.detail:SetWordWrap(true)
        parts.detail:SetJustifyH("LEFT")
        parts.detail:SetText(row.detail)
        SetColor(parts.detail, look.note)
        down = down + parts.detail:GetStringHeight() + 8
        for _, part in pairs(parts) do part:Show() end
        parts.fill:SetShown(fill > 0)
    end
    for i = #rows + 1, #card.rows do
        for _, part in pairs(card.rows[i]) do part:Hide() end
    end
    card:SetHeight(down + 2)
    return y - down - 2 - BLOCK_GAP - 4
end

-- Short labelled values that wrap onto new lines.
function LAYOUTS.chips(self, block, y, context)
    local chips = Rows(block.key, block.chips)
    if not chips or #chips == 0 then return y end
    local collapsed
    y, collapsed = self:Header(context, y, block.key, block.title, block.colorKey)
    if collapsed then return y - BLOCK_GAP end
    local look = context.look
    local size = context.size + look.sizes.body
    local height = size + 8
    local x = 0
    for _, text in ipairs(chips) do
        local chip = self:Get("chip")
        SetFont(chip.text, context.fonts.bold, size)
        chip.text:SetText(text)
        SetColor(chip.text, look.text)
        local width = chip.text:GetStringWidth() + 14
        if x > 0 and x + width > context.inner then
            x, y = 0, y - height - 5
        end
        chip:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD + x, y)
        chip:SetSize(width, height)
        chip.bg:SetColorTexture(unpack(look.cardBg))
        Edges(chip, look.cardEdge, context.pixel)
        x = x + width + 5
    end
    y = y - height - 5
    if block.foot then y = self:Foot(context, y, block.foot) end
    return y - BLOCK_GAP
end

-- One small card: icon, title (in its colour), a number on the right, and lines underneath
-- ({ text, dim }). Returns the y under it.
function Panel:Entry(context, y, card)
    local look = context.look
    local entry = self:Get("entry")
    entry:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, y)
    entry:SetWidth(context.inner)
    entry.bg:SetColorTexture(unpack(look.cardBg))
    Edges(entry, look.cardEdge, context.pixel)
    local pad = 7
    local titleSize = context.size + look.sizes.body
    local lineSize = context.size + look.sizes.note - 1
    local iconSize = titleSize + 12
    local textX = pad
    if card.icon then
        entry.icon:SetTexture(card.icon)
        entry.icon:ClearAllPoints()
        entry.icon:SetPoint("TOPLEFT", pad, -pad)
        entry.icon:SetSize(iconSize, iconSize)
        entry.icon:Show()
        textX = pad + iconSize + 8
    else
        entry.icon:Hide()
    end
    SetFont(entry.right, context.fonts.note, lineSize)
    entry.right:SetText(card.right or "")
    if card.rightColor then SetColor(entry.right, card.rightColor) else SetColor(entry.right, look.note) end
    entry.right:ClearAllPoints()
    entry.right:SetPoint("TOPRIGHT", -pad, -pad - 1)
    SetFont(entry.title, context.fonts.bold, titleSize)
    entry.title:SetText(card.title or "")
    if card.color then SetColor(entry.title, card.color) else SetColor(entry.title, look.text) end
    entry.title:ClearAllPoints()
    entry.title:SetPoint("TOPLEFT", textX, -pad)
    entry.title:SetWidth(math.max(20, context.inner - textX - pad - entry.right:GetStringWidth() - 8))
    local down = pad + titleSize + 4
    local lines = card.lines or {}
    for i, line in ipairs(lines) do
        local text = entry.lines[i]
        if not text then
            text = entry:CreateFontString(nil, "OVERLAY")
            text:SetJustifyH("LEFT")
            entry.lines[i] = text
        end
        SetFont(text, line.bold and context.fonts.bold or context.fonts.note, line.bold and lineSize + 1 or lineSize)
        text:SetWordWrap(true)
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", textX, -down)
        text:SetWidth(context.inner - textX - pad)
        text:SetText(line.text)
        if line.dim then SetColor(text, look.note) else SetColor(text, look.text) end
        text:Show()
        down = down + text:GetStringHeight() + 3
    end
    for i = #lines + 1, #entry.lines do entry.lines[i]:Hide() end
    local height = math.max(down, pad + iconSize) + pad
    entry:SetHeight(height)
    return y - height - 5
end

local GOOD, BAD = ns.GOOD_HEX, ns.BAD_HEX

-- One change from the tracker, as a card: what it was, what it replaced, the stats that moved
-- ("+1 Agi  -1 Sta  +6 Armor") and what they add up to ("Real DPS +0.1   Effective health -3%").
local function ChangeCard(change)
    local lines = {}
    if change.sub then lines[#lines + 1] = { text = change.sub, dim = true } end
    if change.deltas and #change.deltas > 0 then
        local parts = {}
        for _, delta in ipairs(change.deltas) do
            parts[#parts + 1] = string.format("%s%+d|r %s", delta[2] > 0 and GOOD or BAD, delta[2], delta[1])
        end
        lines[#lines + 1] = { text = table.concat(parts, "    ") }
    end
    if change.effects and #change.effects > 0 then
        local parts = {}
        for _, effect in ipairs(change.effects) do
            parts[#parts + 1] = string.format("%s %s%s|r", effect[1], effect[3] and GOOD or BAD, effect[2])
        end
        lines[#lines + 1] = { text = table.concat(parts, "     "), bold = true }
    end
    if #lines == 0 then lines[1] = { text = "no change to your stats", dim = true } end
    local color
    if change.quality and C_Item.GetItemQualityColor then
        local ok, r, g, b = pcall(C_Item.GetItemQualityColor, change.quality)
        if ok and r then color = { r, g, b } end
    end
    return { icon = change.icon, title = change.title, color = color, right = ns.Ago(change.time), lines = lines }
end

-- What changed since you logged in, newest first.
function LAYOUTS.changes(self, block, y, context)
    local changes = ns.Changes or {}
    if #changes == 0 and block.hideEmpty then return y end
    local collapsed
    y, collapsed = self:Header(context, y, block.key, block.title, block.colorKey)
    if collapsed then return y - BLOCK_GAP end
    if #changes == 0 then
        return self:Foot(context, y, "Nothing yet. Gear swaps, skill-ups and level-ups show up here, with what they changed.") - BLOCK_GAP
    end
    for i = 1, math.min(#changes, block.limit or #changes) do
        y = self:Entry(context, y, ChangeCard(changes[i]))
    end
    return y - BLOCK_GAP + 5
end

-- Rows of small cards from a block's items() (casts from full mana per spell).
function LAYOUTS.entries(self, block, y, context)
    local items = Rows(block.key, block.items)
    local collapsed
    y, collapsed = self:Header(context, y, block.key, block.title, block.colorKey)
    if collapsed then return y - BLOCK_GAP end
    if not items or #items == 0 then
        return self:Foot(context, y, block.empty or "Nothing to show.") - BLOCK_GAP
    end
    local r, g, b = SectionColor(block.colorKey)
    for _, item in ipairs(items) do
        local card = {}
        for key, value in pairs(item) do card[key] = value end
        card.rightColor = card.rightColor or { r, g, b }
        y = self:Entry(context, y, card)
    end
    return y - BLOCK_GAP + 5
end

-- The switch on a line of its own, for anyone who has a choice.
function LAYOUTS.role(self, block, y, context)
    local roles = ns.Roles()
    if not roles then return y end
    local look = context.look
    local bar = self:Get("roleBar")
    local size = context.size + look.sizes.body
    local height = size + 8
    bar:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, y)
    bar:SetSize(context.inner, height)
    SetFont(bar.label, context.fonts.body, size)
    bar.label:SetText("Show as")
    SetColor(bar.label, look.label)
    local gold = { SectionColor("Insights") }
    local x = 0
    for i = #bar.buttons, 1, -1 do
        local button = bar.buttons[i]
        button.role = roles[i]
        SetFont(button.text, context.fonts.bold, size - 1)
        button.text:SetText(ROLE_NAMES[button.role])
        local width = button.text:GetStringWidth() + 18
        button:SetSize(width, height)
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", bar, "TOPRIGHT", x, 0)
        x = x - width - 2
        PaintRole(button, look, gold)
    end
    return y - height - BLOCK_GAP
end

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------

function Panel:Layout()
    local db, content = ns.db, self.content
    local theme = ns.Theme()
    local look = LOOKS[theme]
    local size = db.size
    local context = {
        look = look, fonts = ns.Fonts(theme), size = size, pixel = OnePixel(content),
        rowHeight = size + look.sizes.body + 4 + db.rowGap,
    }

    local tabHeight = self:LayTabs(context)
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", 0, -(4 + tabHeight))
    self.scroll:SetPoint("BOTTOMRIGHT", 0, 4)

    local width = self.scroll:GetWidth()
    if not width or width < 50 then return end
    content:SetWidth(width)
    context.inner = width - 2 * PAD
    context.half = (context.inner - GAP) / 2
    -- Narrow (little extra width, or a slim "beside" panel): tiles two to a row, stats stacked; 280 is
    -- about where three tiles' numbers and two stats side by side crowd (the default extra width gives 323).
    context.narrow = context.inner < NARROW

    self.over:SetFrameLevel(content:GetFrameLevel() + 30)
    pcall(self.PaintFades, self, look)

    if look.border and self.mode == "replace" then
        self.frame.border:SetAtlas(look.border)
        self.frame.border:Show()
    else
        self.frame.border:Hide()
    end

    self.used = {}
    local y = -4
    local blocks = CurrentTab().blocks
    if type(blocks) == "function" then blocks = blocks() end
    for _, block in ipairs(blocks) do
        y = LAYOUTS[block.kind](self, block, y, context)
    end
    for kind, pool in pairs(self.pools) do
        for i = (self.used[kind] or 0) + 1, #pool do pool[i]:Hide() end
    end

    content:SetHeight(math.max(1, -y))
    self.scroll:UpdateScrollChildRect()
    self:PlaceThumb()
    self:UpdateTicker()
end

-- The Gear tab's countdowns (weapon buffs, ammo) and "4m ago" times: redrawn each second while
-- that tab is on screen, and only then.
function Panel:UpdateTicker()
    local want = self.frame:IsVisible() and CurrentTab().key == "gear"
    if want and not self.ticker then
        self.ticker = C_Timer.NewTicker(1, function()
            if Panel.frame:IsVisible() and CurrentTab().key == "gear" then
                Panel:Queue()
            else
                Panel:UpdateTicker()
            end
        end)
    elseif not want and self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

------------------------------------------------------------------------------
-- Updates: events only while the panel is on screen, gathered into one redraw.
------------------------------------------------------------------------------

function Panel:Queue()
    if self.queued then return end
    self.queued = true
    C_Timer.After(0.25, function()
        self.queued = false
        if self.frame:IsVisible() then self:Layout() else self.dirty = true end
    end)
end

-- In combat the sheet holds still (unit events like UNIT_AURA fire constantly there) and
-- catches up once when combat ends.
function Panel:OnEvent(event)
    if event == "PLAYER_REGEN_ENABLED" then
        self.dirty = false
        self:Queue()
    elseif InCombatLockdown() then
        self.dirty = true
    else
        self:Queue()
    end
end

-- An event this client doesn't have raises an error when registered, so each is tried alone.
-- Events only come in while the panel is shown; showing it lays it out fresh.
function Panel:OnShow()
    local frame = self.frame
    for _, event in ipairs(ns.UnitEvents) do pcall(frame.RegisterUnitEvent, frame, event, "player", "pet") end
    for _, event in ipairs(ns.Events) do pcall(frame.RegisterEvent, frame, event) end
    pcall(frame.RegisterEvent, frame, "PLAYER_REGEN_ENABLED")
    if self.mode == "replace" then self:HideList() end
    self.dirty = false
    self:Layout()
end

function Panel:OnHide()
    self.frame:UnregisterAllEvents()
    self:UpdateTicker()
    HideTip()
end

------------------------------------------------------------------------------
-- Placement
------------------------------------------------------------------------------

local function StatsList() return _G.CharacterStatsPaneScrollBox end

-- The list stays where it is (it decides when the stats tab is showing) but draws nothing.
-- The client sets its alpha back on some refreshes, so that's undone as it happens.
function Panel:HideList()
    local box = StatsList()
    if not box then return end
    if not self.hooked then
        self.hooked = true
        hooksecurefunc(box, "SetAlpha", function(list, alpha)
            if Panel.mode == "replace" and alpha ~= 0 and not Panel.settingAlpha then
                Panel.settingAlpha = true
                list:SetAlpha(0)
                Panel.settingAlpha = false
            end
        end)
    end
    self.settingAlpha = true
    box:SetAlpha(0)
    self.settingAlpha = false
end

-- The character window and its stats pane grow by db.extraWidth after each of Forever's own resizes
-- (CharacterFrame:UpdateSize: 631 wide, a 233 stats pane); Blizzard's pane art is widened to match.
local PANE_WIDTH = 233
local PANE_ART = { ["UI-Character-Info-Stat-BG"] = true, ["UI-Character-Info-Stat-StoneBG"] = true }

function Panel:Widen()
    local characterFrame = _G.CharacterFrame
    if not (characterFrame and characterFrame.RightPaneHost and characterFrame.UpdateSize) then return end
    if not self.sizeHooked then
        self.sizeHooked = true
        hooksecurefunc(characterFrame, "UpdateSize", function() Panel:Widen() end)
    end
    if InCombatLockdown() and characterFrame:IsProtected() then return end
    local collapsed = characterFrame.IsRightPaneCollapsed and characterFrame:IsRightPaneCollapsed()
    local extra = (not collapsed and ns.db.mode == "replace") and (ns.db.extraWidth or 0) or 0
    -- The window's width counts FrogUI's extra too (FrogLib's Sheet.lua): set on its own, the
    -- last addon to set it would leave the other's pane hanging over the window's edge.
    FrogLib.Sheet.SetExtra("StatSheet", "right", ns.db.mode == "replace" and (ns.db.extraWidth or 0) or 0)
    characterFrame:SetWidth(FrogLib.Sheet.Width())
    characterFrame.RightPaneHost:SetWidth(PANE_WIDTH + extra)
    for _, region in ipairs({ characterFrame.RightPaneHost:GetRegions() }) do
        local atlas = region.GetAtlas and region:GetAtlas()
        if atlas and PANE_ART[atlas] then region:SetWidth(PANE_WIDTH + extra) end
    end
end

function Panel:Apply()
    self:Create()
    pcall(self.Widen, self)
    local frame, db = self.frame, ns.db
    local box = StatsList()
    local mode = db.mode
    if mode == "replace" and not box then mode = "beside" end
    self.mode = mode

    frame:ClearAllPoints()
    if mode == "replace" then
        frame:SetParent(box)
        frame:SetIgnoreParentAlpha(true)
        frame:SetAllPoints(box)
        frame:SetFrameLevel(box:GetFrameLevel() + 20)
        frame:SetBackdrop(nil)
        self:HideList()
    else
        if box then
            self.settingAlpha = true
            box:SetAlpha(1)
            self.settingAlpha = false
        end
        local sheet = _G.CharacterFrame
        frame:SetParent(_G.PaperDollFrame or sheet)
        frame:SetIgnoreParentAlpha(false)
        frame:SetPoint("TOPLEFT", sheet, "TOPRIGHT", 2, 0)
        frame:SetPoint("BOTTOMLEFT", sheet, "BOTTOMRIGHT", 2, 0)
        frame:SetWidth(db.width)
        frame:SetFrameStrata(sheet:GetFrameStrata())
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        frame:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
        frame:SetBackdropBorderColor(0, 0, 0, 1)
    end
    frame:Show()
    if frame:IsVisible() then self:Layout() end
    self:HookRetry()
end

-- The stats list may not exist yet at login, so "replace" falls back to "beside". Try again
-- each time the character window opens until the chosen mode sticks.
function Panel:HookRetry()
    local characterFrame = _G.CharacterFrame
    if self.retryHooked or not characterFrame then return end
    self.retryHooked = true
    characterFrame:HookScript("OnShow", function()
        if Panel.mode ~= ns.db.mode and not InCombatLockdown() then Panel:Apply() end
    end)
end
