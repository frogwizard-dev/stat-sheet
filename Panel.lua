local _, ns = ...

-- The panel: a row of tabs (Tabs.lua), and the chosen tab's blocks laid out top to bottom.
-- "replace" puts it over Blizzard's stats list (CharacterStatsPaneScrollBox), which goes
-- invisible but stays in place, so the panel follows that list's own tab switching (the pet
-- view and the other right-pane tabs hide it with the list). "beside" hangs it off the right
-- edge of the character window instead and leaves the list alone.
--
-- Two looks, following the sheet: EllesmereUI's (dark, Expressway, coloured headers between thin
-- lines) and Blizzard's Forever one (its bronze header bars and shaded rows from
-- Camelot/CharacterFrame.xml, Friz Quadrata names, Arial Narrow details).
local Panel = {}
ns.Panel = Panel

local PAD = 10          -- left and right margin inside the panel
local GAP = 12          -- between the two columns of a section
local TILE_GAP = 6
local BLOCK_GAP = 8

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
    local c = (type(custom) == "table" and custom.r and custom) or DEFAULT_COLORS[key] or DEFAULT_COLORS.General
    return c.r, c.g, c.b
end

local LOOKS = {
    ellesmere = {
        text = { 0.90, 0.91, 0.92 }, label = { 0.65, 0.69, 0.72 }, note = { 0.50, 0.54, 0.57 },
        caption = { 0.55, 0.58, 0.62 }, colourValues = true, headerLines = true,
        cardBg = { 0.086, 0.106, 0.125, 1 }, cardEdge = { 0.137, 0.165, 0.192, 1 },
        track = { 0.137, 0.165, 0.192, 1 }, tabIdle = { 0.55, 0.58, 0.62 },
        sizes = { body = 1, note = 0, caption = -1, number = 9, header = 2, tab = 1 },
    },
    blizzard = {
        text = { 1, 1, 1 }, label = { 1, 0.82, 0 }, note = { 0.66, 0.60, 0.50 },
        caption = { 1, 0.82, 0 }, value = { 1, 1, 1 },
        headerAtlas = "UI-Character-Info-Title", rowAtlas = "UI-Character-Info-Line-Bounce",
        border = "common-insideframe", bar = { 0.79, 0.60, 0.18 },
        cardBg = { 0, 0, 0, 0.45 }, cardEdge = { 0.42, 0.32, 0.19, 1 },
        track = { 0, 0, 0, 0.5 }, tabIdle = { 0.79, 0.66, 0.42 },
        sizes = { body = 0, note = 0, caption = -1, number = 7, header = 1, tab = 0 },
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
-- Forever's: the game's own, read from its font objects (Friz Quadrata for words, Arial Narrow
-- for the small print).
local EXPRESSWAY = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local EXPRESSWAY_BOLD = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway Bold.ttf"

local function FontOf(object, fallback)
    local fo = _G[object]
    local path = fo and fo.GetFont and fo:GetFont()
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

local function SetFont(fs, path, size)
    -- Only when it changes (FrogLib's Media notes the font it set on the text).
    if fs.frogFont ~= path .. "|" .. size .. "|" then ns.Media:SetFont(fs, path, size, "") end
end

-- One screen pixel in the frame's units, for hairlines.
local function OnePixel(frame)
    local ok, px = pcall(FrogLib.Pixel, frame)
    return (ok and px and px > 0) and px or 1
end

local function SetColor(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end

------------------------------------------------------------------------------
-- Reading values
------------------------------------------------------------------------------

-- Per cell or tile: text, label, zero flag, note and bar last read, and stale (couldn't be read
-- this time: secret in combat, so the last readable values stay, dimmed).
local state = {}

local function Read(item, labelKey)
    local st = state[item]
    if not st then
        st = {}
        state[item] = st
    end
    local ok, text, zero, note, bar = pcall(item.get)
    if ok then
        st.stale = false
        if text then
            st.text, st.zero, st.note, st.bar = text, zero, note, bar
        else
            st.text = nil
        end
    else
        st.stale = true
    end
    local label = item[labelKey or "label"]
    if type(label) == "function" then
        local okL, l = pcall(label)
        if okL and l then st.label = l end
    else
        st.label = label
    end
    return st
end

-- A block's computed rows (bars, chips, worth): the last good result when it can't be read now.
local cache = {}
local function Rows(key, fn)
    local ok, rows = pcall(fn)
    if ok and type(rows) == "table" then
        cache[key] = rows
        return rows, false
    end
    return cache[key], true
end

local sectionShown = {}
local function SectionShown(sec)
    if ns.db.sections[sec.key] == false then return false end
    if not sec.show then return true end
    local ok, shown = pcall(sec.show)
    if ok then sectionShown[sec] = shown and true or false end
    return sectionShown[sec] ~= false
end

------------------------------------------------------------------------------
-- Widgets (pooled; each layout reuses them in order)
------------------------------------------------------------------------------

local function ShowTip(b)
    local item = b.item
    if not (item and item.tip) then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    local st = state[item]
    GameTooltip:AddDoubleLine(st and st.label or "", st and st.text or "", 1, 1, 1, 1, 1, 1)
    pcall(item.tip, GameTooltip)
    if st and st.stale then
        GameTooltip:AddLine("Last value read; it can't be read in combat.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function HideTip() GameTooltip:Hide() end

local function Text(parent, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetWordWrap(false)
    return fs
end

local function Edges(f, c, px)
    if not f.edges then
        f.edges = {}
        for i = 1, 4 do f.edges[i] = f:CreateTexture(nil, "BORDER") end
    end
    local e = f.edges
    for i = 1, 4 do
        e[i]:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        e[i]:ClearAllPoints()
    end
    e[1]:SetPoint("TOPLEFT") e[1]:SetPoint("TOPRIGHT") e[1]:SetHeight(px)
    e[2]:SetPoint("BOTTOMLEFT") e[2]:SetPoint("BOTTOMRIGHT") e[2]:SetHeight(px)
    e[3]:SetPoint("TOPLEFT") e[3]:SetPoint("BOTTOMLEFT") e[3]:SetWidth(px)
    e[4]:SetPoint("TOPRIGHT") e[4]:SetPoint("BOTTOMRIGHT") e[4]:SetWidth(px)
end

local MAKERS = {}

function MAKERS.cell(self)
    local b = CreateFrame("Button", nil, self.content)
    b.shade = b:CreateTexture(nil, "BACKGROUND")
    b.label = Text(b)
    b.label:SetPoint("TOPLEFT", 0, 0)
    b.label:SetJustifyH("LEFT")
    b.value = Text(b)
    b.value:SetPoint("TOPRIGHT", 0, 0)
    b.value:SetJustifyH("RIGHT")
    b.note = Text(b)
    b.note:SetJustifyH("LEFT")
    b.barBg = b:CreateTexture(nil, "ARTWORK")
    b.barFill = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.barFill:SetPoint("TOPLEFT", b.barBg, "TOPLEFT")
    b.barFill:SetPoint("BOTTOMLEFT", b.barBg, "BOTTOMLEFT")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", -4, 0)
    hl:SetPoint("BOTTOMRIGHT", 4, 0)
    hl:SetColorTexture(1, 1, 1, 0.05)
    b:SetScript("OnEnter", ShowTip)
    b:SetScript("OnLeave", HideTip)
    return b
end

-- Block headers fold their block away when clicked (remembered per block).
function MAKERS.header(self)
    local h = CreateFrame("Button", nil, self.content)
    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetAllPoints()
    h.title = Text(h)
    h.left = h:CreateTexture(nil, "ARTWORK")
    h.right = h:CreateTexture(nil, "ARTWORK")
    h.fold = Text(h)
    h.fold:SetPoint("RIGHT", -2, 0)
    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.04)
    h:SetScript("OnClick", function(btn)
        local collapsed = ns.db.collapsed
        collapsed[btn.key] = not collapsed[btn.key] or nil
        Panel:Layout()
    end)
    return h
end

function MAKERS.tile(self)
    local t = CreateFrame("Button", nil, self.content)
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    t.caption = Text(t)
    t.caption:SetPoint("TOPLEFT", 8, -8)
    t.caption:SetPoint("TOPRIGHT", -6, -8)
    t.caption:SetJustifyH("LEFT")
    t.value = Text(t)
    t.value:SetJustifyH("LEFT")
    t.sub = Text(t)
    t.sub:SetJustifyH("LEFT")
    t:SetScript("OnEnter", ShowTip)
    t:SetScript("OnLeave", HideTip)
    return t
end

-- One stacked bar row: an optional line of label and right-hand text, the bar, a legend.
function MAKERS.barRow(self)
    local r = CreateFrame("Frame", nil, self.content)
    r.label = Text(r)
    r.label:SetPoint("TOPLEFT", 0, 0)
    r.right = Text(r)
    r.right:SetPoint("TOPRIGHT", 0, 0)
    r.track = r:CreateTexture(nil, "BACKGROUND")
    r.segs, r.keys = {}, {}
    r.foot = Text(r)
    r.foot:SetJustifyH("LEFT")
    return r
end

function MAKERS.card(self)
    local c = CreateFrame("Frame", nil, self.content)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.title = Text(c)
    c.title:SetPoint("TOPLEFT", 10, -10)
    c.toggles = {}
    for i, role in ipairs({ "melee", "caster" }) do
        local b = CreateFrame("Button", nil, c)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.text = Text(b)
        b.text:SetPoint("CENTER")
        b.role = role
        b:SetScript("OnClick", function(btn)
            ns.db.role = btn.role
            Panel:Layout()
        end)
        c.toggles[i] = b
    end
    c.rows = {}
    return c
end

function MAKERS.chip(self)
    local c = CreateFrame("Frame", nil, self.content)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.text = Text(c)
    c.text:SetPoint("CENTER")
    return c
end

-- A small card: icon, title, a number on the right, and lines under the title.
function MAKERS.entry(self)
    local e = CreateFrame("Frame", nil, self.content)
    e.bg = e:CreateTexture(nil, "BACKGROUND")
    e.bg:SetAllPoints()
    e.icon = e:CreateTexture(nil, "ARTWORK")
    e.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    e.title = Text(e)
    e.title:SetJustifyH("LEFT")
    e.right = Text(e)
    e.right:SetJustifyH("RIGHT")
    e.lines = {}
    return e
end

-- The Melee / Caster switch on its own line.
function MAKERS.roleBar(self)
    local r = CreateFrame("Frame", nil, self.content)
    r.label = Text(r)
    r.label:SetPoint("LEFT", 0, 0)
    r.buttons = {}
    for i, role in ipairs({ "melee", "caster" }) do
        local b = CreateFrame("Button", nil, r)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.text = Text(b)
        b.text:SetPoint("CENTER")
        b.role = role
        b:SetScript("OnClick", function(btn)
            ns.db.role = btn.role
            Panel:Layout()
        end)
        r.buttons[i] = b
    end
    return r
end

function MAKERS.foot(self)
    local fs = self.content:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("LEFT")
    return fs
end

function Panel:Get(kind)
    local pool, used = self.pools[kind], self.used
    used[kind] = (used[kind] or 0) + 1
    local w = pool[used[kind]]
    if not w then
        w = MAKERS[kind](self)
        pool[used[kind]] = w
    end
    w:ClearAllPoints()
    w:Show()
    return w
end

------------------------------------------------------------------------------
-- The frame
------------------------------------------------------------------------------

function Panel:Create()
    if self.frame then return end
    local f = CreateFrame("Frame", "StatSheetPanel", UIParent, "BackdropTemplate")
    f:EnableMouse(true)
    f:Hide()
    self.frame = f

    -- Blizzard's inner frame edge, which the hidden list would otherwise have drawn.
    f.border = f:CreateTexture(nil, "BORDER")
    f.border:SetPoint("TOPLEFT", 1, 1)
    f.border:SetPoint("BOTTOMRIGHT", -4, 2)

    -- Tabs along the top.
    self.tabs = {}
    for i, tab in ipairs(ns.Tabs) do
        local b = CreateFrame("Button", nil, f)
        b.text = Text(b)
        b.text:SetPoint("CENTER", 0, 1)
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetPoint("BOTTOMLEFT", 4, 0)
        b.line:SetPoint("BOTTOMRIGHT", -4, 0)
        b.line:SetHeight(2)
        b.key = tab.key
        b:SetScript("OnClick", function(btn)
            ns.db.tab = btn.key
            Panel.scroll:SetVerticalScroll(0)
            Panel:Layout()
        end)
        self.tabs[i] = b
    end
    f.tabRule = f:CreateTexture(nil, "ARTWORK")

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("BOTTOMRIGHT", 0, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    self.scroll, self.content = scroll, content
    scroll:SetScript("OnSizeChanged", function()
        if f:IsVisible() then Panel:Layout() end
    end)

    -- A thin bar that only shows when there's more than fits.
    local thumb = f:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(1, 1, 1, 0.25)
    thumb:SetWidth(2)
    self.thumb = thumb

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        local range = scroll:GetVerticalScrollRange()
        local v = math.max(0, math.min(range, scroll:GetVerticalScroll() - delta * 40))
        scroll:SetVerticalScroll(v)
        Panel:PlaceThumb()
    end)

    self.pools, self.used = {}, {}
    for kind in pairs(MAKERS) do self.pools[kind] = {} end
    f:SetScript("OnShow", function() Panel:OnShow() end)
    f:SetScript("OnHide", function() Panel:OnHide() end)
    f:SetScript("OnEvent", function() Panel:Queue() end)
end

function Panel:PlaceThumb()
    local scroll, thumb = self.scroll, self.thumb
    local range = scroll:GetVerticalScrollRange()
    if range <= 0.5 then
        thumb:Hide()
        scroll:SetVerticalScroll(0)
        return
    end
    local h = scroll:GetHeight()
    local size = math.max(20, h * h / (h + range))
    local offset = (h - size) * (scroll:GetVerticalScroll() / range)
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
function Panel:LayTabs(ctx)
    local f, look = self.frame, ctx.look
    local current = CurrentTab()
    local _, class = UnitClass("player")
    local cr, cg, cb = FrogLib.Color.Class(class)
    local cc = cr and { r = cr, g = cg, b = cb } or { r = 1, g = 0.82, b = 0 }
    local h = ctx.size + 14
    local x, w = PAD - 4, 0
    for i, b in ipairs(self.tabs) do
        local tab = ns.Tabs[i]
        SetFont(b.text, tab == current and ctx.fonts.bold or ctx.fonts.body, ctx.size + look.sizes.tab)
        b.text:SetText(tab.title)
        w = b.text:GetStringWidth() + 14
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -4)
        b:SetSize(w, h)
        x = x + w
        if tab == current then
            if look.headerAtlas then
                b.text:SetTextColor(1, 0.82, 0)
                b.line:SetColorTexture(1, 0.82, 0, 0.9)
            else
                SetColor(b.text, look.text)
                b.line:SetColorTexture(cc.r, cc.g, cc.b, 1)
            end
            b.line:Show()
        else
            SetColor(b.text, look.tabIdle)
            b.line:Hide()
        end
    end
    f.tabRule:ClearAllPoints()
    f.tabRule:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, -(4 + h))
    f.tabRule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD - 4), -(4 + h))
    f.tabRule:SetHeight(ctx.px)
    f.tabRule:SetColorTexture(1, 1, 1, 0.08)
    return h + 6
end

------------------------------------------------------------------------------
-- Blocks
------------------------------------------------------------------------------

local LAY = {}

-- A block's header; returns the y under it and whether the block is folded away.
function Panel:Header(ctx, y, key, title, colorKey)
    local look = ctx.look
    local r, g, b = SectionColor(colorKey)
    local collapsed = ns.db.collapsed[key]
    local hd = self:Get("header")
    hd.key = key
    local h = look.headerAtlas and ctx.size + 14 or ctx.size + 10
    hd:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, y)
    hd:SetSize(ctx.inner, h)
    SetFont(hd.title, ctx.fonts.bold, ctx.size + look.sizes.header)
    SetFont(hd.fold, ctx.fonts.bold, ctx.size + look.sizes.header)
    hd.title:SetText(title)
    hd.fold:SetText(collapsed and "+" or "-")
    hd.title:ClearAllPoints()
    if look.headerAtlas then
        hd.title:SetPoint("CENTER", 0, 1)
        hd.bg:SetAtlas(look.headerAtlas)
        hd.bg:Show()
        hd.left:Hide()
        hd.right:Hide()
        hd.title:SetTextColor(1, 1, 1)
        hd.fold:SetTextColor(1, 0.82, 0)
    else
        -- EllesmereUI: the title on the left, a thin line in its colour running to the right.
        hd.title:SetPoint("LEFT", 0, 0)
        hd.bg:Hide()
        hd.left:Hide()
        hd.title:SetTextColor(r, g, b)
        hd.fold:SetTextColor(r, g, b, 0.8)
        hd.right:ClearAllPoints()
        hd.right:SetPoint("LEFT", hd.title, "RIGHT", 8, 0)
        hd.right:SetPoint("RIGHT", hd, "RIGHT", -16, 0)
        hd.right:SetColorTexture(r, g, b, 0.25)
        hd.right:SetHeight(ctx.px)
        hd.right:Show()
    end
    return y - h - 4, collapsed
end

function Panel:Foot(ctx, y, text, x)
    local fs = self:Get("foot")
    SetFont(fs, ctx.fonts.note, ctx.size + ctx.look.sizes.note - 1)
    SetColor(fs, ctx.look.note)
    fs:SetWidth(ctx.inner)
    fs:SetWordWrap(true)
    fs:SetText(text)
    fs:SetPoint("TOPLEFT", self.content, "TOPLEFT", x or PAD, y)
    return y - fs:GetStringHeight() - 4
end

function LAY.tiles(self, block, y, ctx)
    local look = ctx.look
    local items = {}
    for _, tile in ipairs(block.tiles) do
        local st = Read(tile, "caption")
        if st.text then items[#items + 1] = tile end
    end
    if #items == 0 then return y end
    local w = (ctx.inner - TILE_GAP * (#items - 1)) / #items
    local capSize = ctx.size + look.sizes.caption
    local numSize = ctx.size + look.sizes.number
    local subSize = ctx.size + look.sizes.note - 1
    local h = 8 + capSize + 4 + numSize + 4 + subSize + 8
    for i, tile in ipairs(items) do
        local st = state[tile]
        local t = self:Get("tile")
        t.item = tile
        t:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD + (i - 1) * (w + TILE_GAP), y)
        t:SetSize(w, h)
        t.bg:SetColorTexture(unpack(look.cardBg))
        Edges(t, look.cardEdge, ctx.px)
        SetFont(t.caption, ctx.fonts.bold, capSize)
        SetFont(t.value, ctx.fonts.number, numSize)
        SetFont(t.sub, ctx.fonts.note, subSize)
        t.caption:SetText(st.label or "")
        SetColor(t.caption, look.caption)
        t.value:ClearAllPoints()
        t.value:SetPoint("TOPLEFT", t.caption, "BOTTOMLEFT", 0, -4)
        t.value:SetPoint("RIGHT", t, "RIGHT", -4, 0)
        t.value:SetText(st.text)
        if look.colourValues then
            local r, g, b = SectionColor(tile.colorKey)
            t.value:SetTextColor(r, g, b, st.stale and 0.45 or 1)
        else
            SetColor(t.value, look.value, st.stale and 0.45 or 1)
        end
        t.sub:ClearAllPoints()
        t.sub:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -4)
        t.sub:SetPoint("RIGHT", t, "RIGHT", -4, 0)
        t.sub:SetText(st.note or "")
        SetColor(t.sub, look.note)
        t:EnableMouse(tile.tip ~= nil)
    end
    return y - h - BLOCK_GAP
end

-- Fills one cell and returns its height: the name and value line, then a bar and a note when it
-- has them (whole-row cells only; half a row keeps to one line). A note that fits goes right
-- after the name instead.
function Panel:FillCell(c, st, ctx, w, wide, r, g, b)
    local look, rowH = ctx.look, ctx.rowH
    SetFont(c.label, ctx.fonts.body, ctx.size + look.sizes.body)
    SetFont(c.value, ctx.fonts.bold, ctx.size + look.sizes.body)
    SetFont(c.note, ctx.fonts.note, ctx.size + look.sizes.note - 1)
    c.label:SetHeight(rowH)
    c.value:SetHeight(rowH)
    c.label:SetText(st.label)
    SetColor(c.label, look.label)
    c.value:SetText(st.text)
    if look.colourValues then
        c.value:SetTextColor(r, g, b, st.stale and 0.45 or 1)
    else
        SetColor(c.value, look.value, st.stale and 0.45 or 1)
    end

    local h = rowH
    c.barBg:Hide()
    c.barFill:Hide()
    if wide and type(st.bar) == "number" then
        c.barBg:ClearAllPoints()
        c.barBg:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -(h - 1))
        c.barBg:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, -(h - 1))
        c.barBg:SetHeight(4)
        c.barBg:SetColorTexture(unpack(look.track))
        c.barFill:SetWidth(math.max(1, w * math.max(0, math.min(1, st.bar))))
        local bc = look.bar
        if bc then c.barFill:SetColorTexture(bc[1], bc[2], bc[3], 1) else c.barFill:SetColorTexture(r, g, b, 1) end
        c.barBg:Show()
        c.barFill:Show()
        h = h + 6
    end

    local note = c.note
    note:ClearAllPoints()
    if not (wide and st.note and st.note ~= "") then
        note:Hide()
        return h
    end
    note:SetText(st.note)
    SetColor(note, look.note, st.stale and 0.45 or 1)
    note:Show()
    note:SetWordWrap(false)
    note:SetWidth(0)
    local room = w - c.label:GetStringWidth() - c.value:GetStringWidth() - 20
    if h == rowH and note:GetStringWidth() <= room then
        note:SetJustifyV("MIDDLE")
        note:SetHeight(rowH)
        note:SetPoint("TOPLEFT", c.label, "TOPRIGHT", 6, 0)
        return h
    end
    note:SetJustifyV("TOP")
    note:SetWordWrap(true)
    note:SetWidth(w)
    note:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -h)
    note:SetHeight(note:GetStringHeight())
    return h + note:GetStringHeight() + 3
end

function LAY.section(self, block, y, ctx)
    local sec = block.section
    if not SectionShown(sec) then return y end
    local visible = {}
    for _, cell in ipairs(sec.cells) do
        local st = Read(cell)
        if st.text and not (ns.db.hideZero and st.zero) then visible[#visible + 1] = cell end
    end
    if #visible == 0 then return y end
    local r, g, b = SectionColor(sec.colorKey)
    local collapsed
    y, collapsed = self:Header(ctx, y, sec.key, sec.title, sec.colorKey)
    if collapsed then return y - BLOCK_GAP end

    local look, rowH = ctx.look, ctx.rowH
    local col, rowIndex = 0, 0
    for _, cell in ipairs(visible) do
        local st = state[cell]
        local c = self:Get("cell")
        c.item = cell
        local wide = cell.wide
        if type(wide) == "function" then wide = wide() end
        local x, w
        if wide then
            if col == 1 then
                y, col = y - rowH, 0
            end
            x, w = PAD, ctx.inner
        else
            x, w = PAD + col * (ctx.half + GAP), ctx.half
        end
        if col == 0 then rowIndex = rowIndex + 1 end
        c:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, y)
        c:SetWidth(w)
        local h = self:FillCell(c, st, ctx, w, wide, r, g, b)
        c:SetHeight(h)
        -- Blizzard's list shades every other line.
        if look.rowAtlas and rowIndex % 2 == 1 and (wide or col == 0) then
            c.shade:SetAtlas(look.rowAtlas)
            c.shade:ClearAllPoints()
            c.shade:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD - 6, y)
            c.shade:SetPoint("BOTTOMRIGHT", c, "BOTTOMLEFT", ctx.inner + 6, 0)
            c.shade:Show()
        else
            c.shade:Hide()
        end
        c:EnableMouse(cell.tip ~= nil)
        if wide then
            y = y - h
        elseif col == 1 then
            y, col = y - rowH, 0
        else
            col = 1
        end
    end
    if col == 1 then y = y - rowH end
    return y - BLOCK_GAP
end

-- Stacked bars: each row's segments side by side, with a legend of coloured keys under it.
function LAY.bars(self, block, y, ctx)
    local rows, stale = Rows(block.key, block.rows)
    if not rows or #rows == 0 then return y end
    local collapsed
    y, collapsed = self:Header(ctx, y, block.key, block.title, block.colorKey)
    if collapsed then return y - BLOCK_GAP end
    local look = ctx.look
    local textSize = ctx.size + look.sizes.body
    local keySize = ctx.size + look.sizes.note - 1
    for _, row in ipairs(rows) do
        local r = self:Get("barRow")
        r:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, y)
        r:SetWidth(ctx.inner)
        local h = 0
        if row.label then
            SetFont(r.label, ctx.fonts.body, textSize)
            SetFont(r.right, ctx.fonts.bold, textSize)
            r.label:SetText(row.label)
            r.right:SetText(row.right or "")
            SetColor(r.label, look.label)
            SetColor(r.right, look.text, stale and 0.45 or 1)
            r.label:Show()
            r.right:Show()
            h = textSize + 5
        else
            r.label:Hide()
            r.right:Hide()
        end
        -- The bar.
        local barH = 10
        r.track:ClearAllPoints()
        r.track:SetPoint("TOPLEFT", 0, -h)
        r.track:SetSize(ctx.inner, barH)
        r.track:SetColorTexture(unpack(look.track))
        local x, used = 0, 0
        local shown = {}
        for _, seg in ipairs(row.segs) do
            if seg.pct >= 0.05 then shown[#shown + 1] = seg end
        end
        for i, seg in ipairs(shown) do
            used = used + 1
            local tex = r.segs[used]
            if not tex then
                tex = r:CreateTexture(nil, "ARTWORK")
                r.segs[used] = tex
            end
            local segW = ctx.inner * seg.pct / 100
            if i == #shown then segW = ctx.inner - x end
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", x, -h)
            tex:SetSize(math.max(ctx.px, segW - (i < #shown and ctx.px or 0)), barH)
            tex:SetColorTexture(seg.color[1], seg.color[2], seg.color[3], stale and 0.5 or 1)
            tex:Show()
            x = x + segW
        end
        for i = used + 1, #r.segs do r.segs[i]:Hide() end
        h = h + barH + 5
        -- The legend: a swatch and its text per segment, in as many columns as the widest text
        -- allows, so the keys never run into each other.
        local widest = 0
        for i, seg in ipairs(shown) do
            local key = r.keys[i]
            if not key then
                key = { swatch = r:CreateTexture(nil, "ARTWORK"), text = Text(r) }
                r.keys[i] = key
            end
            SetFont(key.text, ctx.fonts.note, keySize)
            key.text:SetText(seg.text)
            widest = math.max(widest, key.text:GetStringWidth())
        end
        local fit = math.max(1, math.floor(ctx.inner / (widest + 22)))
        local cols = math.max(1, math.min(row.cols or 4, fit, #shown))
        local colW = ctx.inner / cols
        local lineH = keySize + 4
        for i, seg in ipairs(shown) do
            local key = r.keys[i]
            local cx = ((i - 1) % cols) * colW
            local cy = h + math.floor((i - 1) / cols) * lineH
            key.swatch:ClearAllPoints()
            key.swatch:SetPoint("TOPLEFT", cx, -(cy + 3))
            key.swatch:SetSize(7, 7)
            key.swatch:SetColorTexture(seg.color[1], seg.color[2], seg.color[3], 1)
            SetFont(key.text, ctx.fonts.note, keySize)
            SetColor(key.text, look.note)
            key.text:ClearAllPoints()
            key.text:SetPoint("TOPLEFT", cx + 11, -cy)
            key.text:SetText(seg.text)
            key.swatch:Show()
            key.text:Show()
        end
        for i = #shown + 1, #r.keys do
            r.keys[i].swatch:Hide()
            r.keys[i].text:Hide()
        end
        h = h + math.ceil(#shown / cols) * lineH
        if row.foot then
            SetFont(r.foot, ctx.fonts.note, keySize)
            SetColor(r.foot, look.note)
            r.foot:ClearAllPoints()
            r.foot:SetPoint("TOPLEFT", 0, -h)
            r.foot:SetText(row.foot)
            r.foot:Show()
            h = h + lineH
        else
            r.foot:Hide()
        end
        r:SetHeight(h)
        y = y - h - 8
    end
    return y - BLOCK_GAP + 4
end

-- What +10 of each stat gets you, in a card, with a melee / caster switch for anyone with mana.
function LAY.worth(self, block, y, ctx)
    local rows, stale = Rows("worth", ns.Worth)
    if not rows or #rows == 0 then return y end
    local look = ctx.look
    local card = self:Get("card")
    card:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, y)
    card:SetWidth(ctx.inner)
    card.bg:SetColorTexture(unpack(look.cardBg))
    Edges(card, look.cardEdge, ctx.px)
    local gold = { SectionColor("Insights") }
    local titleSize = ctx.size + look.sizes.header
    SetFont(card.title, ctx.fonts.bold, titleSize)
    card.title:SetText("What +10 of each gets you")
    card.title:SetTextColor(gold[1], gold[2], gold[3])

    -- The switch.
    local role = ns.WorthRole()
    local x = -8
    for i = #card.toggles, 1, -1 do
        local b = card.toggles[i]
        if ns.R.UsesMana() then
            SetFont(b.text, ctx.fonts.bold, ctx.size + look.sizes.note - 1)
            b.text:SetText(b.role == "melee" and "Melee" or "Caster")
            local w = b.text:GetStringWidth() + 12
            b:SetSize(w, titleSize + 4)
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", card, "TOPRIGHT", x, -8)
            x = x - w - 2
            if b.role == role then
                b.bg:SetColorTexture(gold[1], gold[2], gold[3], 1)
                b.text:SetTextColor(0.06, 0.07, 0.08)
            else
                b.bg:SetColorTexture(0, 0, 0, 0.35)
                SetColor(b.text, look.tabIdle)
            end
            b:Show()
        else
            b:Hide()
        end
    end

    local inner = ctx.inner - 20
    local cy = 10 + titleSize + 10
    local textSize = ctx.size + look.sizes.body
    local noteSize = ctx.size + look.sizes.note - 1
    for i, row in ipairs(rows) do
        local rw = card.rows[i]
        if not rw then
            rw = { stat = Text(card), head = Text(card), track = card:CreateTexture(nil, "ARTWORK"),
                fill = card:CreateTexture(nil, "ARTWORK", nil, 1), detail = Text(card) }
            card.rows[i] = rw
        end
        SetFont(rw.stat, ctx.fonts.bold, textSize)
        SetFont(rw.head, ctx.fonts.bold, textSize)
        SetFont(rw.detail, ctx.fonts.note, noteSize)
        rw.stat:ClearAllPoints()
        rw.stat:SetPoint("TOPLEFT", 10, -cy)
        rw.stat:SetText(row.stat)
        SetColor(rw.stat, look.text)
        rw.head:ClearAllPoints()
        rw.head:SetPoint("TOPRIGHT", -10, -cy)
        rw.head:SetText(row.headline)
        local r, g, b = SectionColor(row.colorKey)
        rw.head:SetTextColor(r, g, b, stale and 0.45 or 1)
        cy = cy + textSize + 4
        rw.track:ClearAllPoints()
        rw.track:SetPoint("TOPLEFT", 10, -cy)
        rw.track:SetSize(inner, 3)
        rw.track:SetColorTexture(unpack(look.track))
        -- Full at a 40% gain, so the bars compare across the different kinds of gain.
        local frac = row.gain and math.max(0, math.min(1, row.gain / 0.4)) or 0
        rw.fill:ClearAllPoints()
        rw.fill:SetPoint("TOPLEFT", rw.track, "TOPLEFT")
        rw.fill:SetSize(math.max(ctx.px, inner * frac), 3)
        rw.fill:SetColorTexture(r, g, b, 1)
        rw.fill:SetShown(frac > 0)
        cy = cy + 6
        rw.detail:ClearAllPoints()
        rw.detail:SetPoint("TOPLEFT", 10, -cy)
        rw.detail:SetWidth(inner)
        rw.detail:SetWordWrap(true)
        rw.detail:SetJustifyH("LEFT")
        rw.detail:SetText(row.detail)
        SetColor(rw.detail, look.note)
        cy = cy + rw.detail:GetStringHeight() + 8
        for _, part in pairs(rw) do part:Show() end
        rw.fill:SetShown(frac > 0)
    end
    for i = #rows + 1, #card.rows do
        for _, part in pairs(card.rows[i]) do part:Hide() end
    end
    card:SetHeight(cy + 2)
    return y - cy - 2 - BLOCK_GAP - 4
end

-- Short labelled values that wrap onto new lines.
function LAY.chips(self, block, y, ctx)
    local chips = Rows(block.key, block.chips)
    if not chips or #chips == 0 then return y end
    local collapsed
    y, collapsed = self:Header(ctx, y, block.key, block.title, block.colorKey)
    if collapsed then return y - BLOCK_GAP end
    local look = ctx.look
    local size = ctx.size + look.sizes.body
    local h = size + 8
    local x = 0
    for _, text in ipairs(chips) do
        local c = self:Get("chip")
        SetFont(c.text, ctx.fonts.bold, size)
        c.text:SetText(text)
        SetColor(c.text, look.text)
        local w = c.text:GetStringWidth() + 14
        if x > 0 and x + w > ctx.inner then
            x, y = 0, y - h - 5
        end
        c:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD + x, y)
        c:SetSize(w, h)
        c.bg:SetColorTexture(unpack(look.cardBg))
        Edges(c, look.cardEdge, ctx.px)
        x = x + w + 5
    end
    y = y - h - 5
    if block.foot then y = self:Foot(ctx, y, block.foot) end
    return y - BLOCK_GAP
end

-- One small card: icon, title (in its colour), a number on the right, and lines underneath
-- ({ text, dim }). Returns the y under it.
function Panel:Entry(ctx, y, data)
    local look = ctx.look
    local e = self:Get("entry")
    e:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, y)
    e:SetWidth(ctx.inner)
    e.bg:SetColorTexture(unpack(look.cardBg))
    Edges(e, look.cardEdge, ctx.px)
    local pad = 7
    local titleSize = ctx.size + look.sizes.body
    local lineSize = ctx.size + look.sizes.note - 1
    local iconSize = titleSize + 12
    local textX = pad
    if data.icon then
        e.icon:SetTexture(data.icon)
        e.icon:ClearAllPoints()
        e.icon:SetPoint("TOPLEFT", pad, -pad)
        e.icon:SetSize(iconSize, iconSize)
        e.icon:Show()
        textX = pad + iconSize + 8
    else
        e.icon:Hide()
    end
    SetFont(e.right, ctx.fonts.note, lineSize)
    e.right:SetText(data.right or "")
    if data.rightColor then SetColor(e.right, data.rightColor) else SetColor(e.right, look.note) end
    e.right:ClearAllPoints()
    e.right:SetPoint("TOPRIGHT", -pad, -pad - 1)
    SetFont(e.title, ctx.fonts.bold, titleSize)
    e.title:SetText(data.title or "")
    if data.color then SetColor(e.title, data.color) else SetColor(e.title, look.text) end
    e.title:ClearAllPoints()
    e.title:SetPoint("TOPLEFT", textX, -pad)
    e.title:SetWidth(math.max(20, ctx.inner - textX - pad - e.right:GetStringWidth() - 8))
    local cy = pad + titleSize + 4
    local lines = data.lines or {}
    for i, line in ipairs(lines) do
        local fs = e.lines[i]
        if not fs then
            fs = e:CreateFontString(nil, "OVERLAY")
            fs:SetJustifyH("LEFT")
            e.lines[i] = fs
        end
        SetFont(fs, line.bold and ctx.fonts.bold or ctx.fonts.note, line.bold and lineSize + 1 or lineSize)
        fs:SetWordWrap(true)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", textX, -cy)
        fs:SetWidth(ctx.inner - textX - pad)
        fs:SetText(line.text)
        if line.dim then SetColor(fs, look.note) else SetColor(fs, look.text) end
        fs:Show()
        cy = cy + fs:GetStringHeight() + 3
    end
    for i = #lines + 1, #e.lines do e.lines[i]:Hide() end
    local h = math.max(cy, pad + iconSize) + pad
    e:SetHeight(h)
    return y - h - 5
end

local GOOD, BAD = "|cff4ee36b", "|cffe5534b"

-- One change from the tracker, as a card: what it was, what it replaced, the stats that moved
-- ("+1 Agi  -1 Sta  +6 Armor") and what they add up to ("Real DPS +0.1   Effective health -3%").
local function ChangeCard(change)
    local lines = {}
    if change.sub then lines[#lines + 1] = { text = change.sub, dim = true } end
    if change.deltas and #change.deltas > 0 then
        local parts = {}
        for _, d in ipairs(change.deltas) do
            parts[#parts + 1] = string.format("%s%+d|r %s", d[2] > 0 and GOOD or BAD, d[2], d[1])
        end
        lines[#lines + 1] = { text = table.concat(parts, "    ") }
    end
    if change.effects and #change.effects > 0 then
        local parts = {}
        for _, fx in ipairs(change.effects) do
            parts[#parts + 1] = string.format("%s %s%s|r", fx[1], fx[3] and GOOD or BAD, fx[2])
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
function LAY.changes(self, block, y, ctx)
    local items = ns.Changes or {}
    if #items == 0 and block.hideEmpty then return y end
    local collapsed
    y, collapsed = self:Header(ctx, y, block.key, block.title, block.colorKey)
    if collapsed then return y - BLOCK_GAP end
    if #items == 0 then
        return self:Foot(ctx, y, "Nothing yet. Gear swaps, skill-ups and level-ups show up here, with what they changed.") - BLOCK_GAP
    end
    for i = 1, math.min(#items, block.limit or #items) do
        y = self:Entry(ctx, y, ChangeCard(items[i]))
    end
    return y - BLOCK_GAP + 5
end

-- Rows of small cards from a block's items() (casts from full mana per spell).
function LAY.entries(self, block, y, ctx)
    local items = Rows(block.key, block.items)
    local collapsed
    y, collapsed = self:Header(ctx, y, block.key, block.title, block.colorKey)
    if collapsed then return y - BLOCK_GAP end
    if not items or #items == 0 then
        return self:Foot(ctx, y, block.empty or "Nothing to show.") - BLOCK_GAP
    end
    local r, g, b = SectionColor(block.colorKey)
    for _, item in ipairs(items) do
        local data = {}
        for k, v in pairs(item) do data[k] = v end
        data.rightColor = data.rightColor or { r, g, b }
        y = self:Entry(ctx, y, data)
    end
    return y - BLOCK_GAP + 5
end

-- The Melee / Caster switch on a line of its own, for anyone with mana.
function LAY.role(self, block, y, ctx)
    if not ns.R.UsesMana() then return y end
    local look = ctx.look
    local bar = self:Get("roleBar")
    local size = ctx.size + look.sizes.body
    local h = size + 8
    bar:SetPoint("TOPLEFT", self.content, "TOPLEFT", PAD, y)
    bar:SetSize(ctx.inner, h)
    SetFont(bar.label, ctx.fonts.body, size)
    bar.label:SetText("Show as")
    SetColor(bar.label, look.label)
    local gold = { SectionColor("Insights") }
    local role = ns.WorthRole()
    local x = 0
    for i = #bar.buttons, 1, -1 do
        local b = bar.buttons[i]
        SetFont(b.text, ctx.fonts.bold, size - 1)
        b.text:SetText(b.role == "melee" and "Melee" or "Caster")
        local w = b.text:GetStringWidth() + 18
        b:SetSize(w, h)
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", bar, "TOPRIGHT", x, 0)
        x = x - w - 2
        if b.role == role then
            b.bg:SetColorTexture(gold[1], gold[2], gold[3], 1)
            b.text:SetTextColor(0.06, 0.07, 0.08)
        else
            b.bg:SetColorTexture(0, 0, 0, 0.35)
            SetColor(b.text, look.tabIdle)
        end
    end
    return y - h - BLOCK_GAP
end

------------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------------

function Panel:Layout()
    local db, content = ns.db, self.content
    local theme = ns.Theme()
    local look = LOOKS[theme]
    local size = db.size
    local ctx = {
        look = look, fonts = ns.Fonts(theme), size = size, px = OnePixel(content),
        rowH = size + look.sizes.body + 4 + db.rowGap,
    }

    local tabH = self:LayTabs(ctx)
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", 0, -(4 + tabH))
    self.scroll:SetPoint("BOTTOMRIGHT", 0, 4)

    local width = self.scroll:GetWidth()
    if not width or width < 50 then return end
    content:SetWidth(width)
    ctx.inner = width - 2 * PAD
    ctx.half = (ctx.inner - GAP) / 2

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
        y = LAY[block.kind](self, block, y, ctx)
    end
    for kind, pool in pairs(self.pools) do
        for i = (self.used[kind] or 0) + 1, #pool do pool[i]:Hide() end
    end

    content:SetHeight(math.max(1, -y))
    self.scroll:UpdateScrollChildRect()
    self:PlaceThumb()
end

------------------------------------------------------------------------------
-- Updates: events only while the panel is on screen, gathered into one redraw.
------------------------------------------------------------------------------

function Panel:Queue()
    if self.queued then return end
    self.queued = true
    C_Timer.After(0.05, function()
        self.queued = false
        if self.frame:IsVisible() then self:Layout() end
    end)
end

-- An event this client doesn't have raises an error when registered, so each is tried alone.
function Panel:OnShow()
    local f = self.frame
    for _, e in ipairs(ns.UnitEvents) do pcall(f.RegisterUnitEvent, f, e, "player", "pet") end
    for _, e in ipairs(ns.Events) do pcall(f.RegisterEvent, f, e) end
    if self.mode == "replace" then self:HideList() end
    self:Layout()
end

function Panel:OnHide()
    self.frame:UnregisterAllEvents()
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

-- Room to breathe: the character window and its stats pane grow by db.extraWidth. Forever sizes
-- the window in CharacterFrame:UpdateSize (Camelot/CharacterFrame.lua: 631 wide, the stats pane a
-- fixed 233 beside a 398 model pane), so the extra goes on after each of its own resizes. The
-- frame border and EllesmereUI's shell stretch with the window; Blizzard's pane art is widened
-- to match.
local PANE_WIDTH = 233
local PANE_ART = { ["UI-Character-Info-Stat-BG"] = true, ["UI-Character-Info-Stat-StoneBG"] = true }

function Panel:Widen()
    local cf = _G.CharacterFrame
    if not (cf and cf.RightPaneHost and cf.UpdateSize) then return end
    if not self.sizeHooked then
        self.sizeHooked = true
        hooksecurefunc(cf, "UpdateSize", function() Panel:Widen() end)
    end
    if InCombatLockdown() and cf:IsProtected() then return end
    local collapsed = cf.IsRightPaneCollapsed and cf:IsRightPaneCollapsed()
    local extra = (not collapsed and ns.db.mode == "replace") and (ns.db.extraWidth or 0) or 0
    -- The window's width counts FrogUI's extra too (FrogLib's Sheet.lua): set on its own, the
    -- last addon to set it would leave the other's pane hanging over the window's edge.
    FrogLib.Sheet.SetExtra("StatSheet", "right", ns.db.mode == "replace" and (ns.db.extraWidth or 0) or 0)
    cf:SetWidth(FrogLib.Sheet.Width())
    cf.RightPaneHost:SetWidth(PANE_WIDTH + extra)
    for _, region in ipairs({ cf.RightPaneHost:GetRegions() }) do
        local atlas = region.GetAtlas and region:GetAtlas()
        if atlas and PANE_ART[atlas] then region:SetWidth(PANE_WIDTH + extra) end
    end
end

function Panel:Apply()
    self:Create()
    pcall(self.Widen, self)
    local f, db = self.frame, ns.db
    local box = StatsList()
    local mode = db.mode
    if mode == "replace" and not box then mode = "beside" end
    self.mode = mode

    f:ClearAllPoints()
    if mode == "replace" then
        f:SetParent(box)
        f:SetIgnoreParentAlpha(true)
        f:SetAllPoints(box)
        f:SetFrameLevel(box:GetFrameLevel() + 20)
        f:SetBackdrop(nil)
        self:HideList()
    else
        if box then
            self.settingAlpha = true
            box:SetAlpha(1)
            self.settingAlpha = false
        end
        local sheet = _G.CharacterFrame
        f:SetParent(_G.PaperDollFrame or sheet)
        f:SetIgnoreParentAlpha(false)
        f:SetPoint("TOPLEFT", sheet, "TOPRIGHT", 2, 0)
        f:SetPoint("BOTTOMLEFT", sheet, "BOTTOMRIGHT", 2, 0)
        f:SetWidth(db.width)
        f:SetFrameStrata(sheet:GetFrameStrata())
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
        f:SetBackdropBorderColor(0, 0, 0, 1)
    end
    f:Show()
    if f:IsVisible() then self:Layout() end
end
