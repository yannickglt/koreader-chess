-- SPDX-License-Identifier: GPL-3.0-or-later
local Blitbuffer = require("ffi/blitbuffer")
local Board = require("board")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

-- Échiquier plein écran dessiné directement dans le tampon d'écran : en-tête de deux lignes,
-- échiquier bordé de ses repères, deux rangées de boutons. Après le rafraîchissement complet
-- de l'ouverture, seules les zones qui changent (cases, en-tête, boutons) sont rafraîchies,
-- en mode « ui » : partiel, sans flash. Les marqueurs sont dessinés par-dessus la case sans
-- déplacer la pièce : cadre épais (pièce choisie, ou pièce que l'ordinateur va jouer), point
-- (case libre), anneau (prise possible), étoile dans l'angle (case conseillée).
local BoardWidget = InputContainer:extend{
    name = "chess_board",
    covers_fullscreen = true,
    view = nil,      -- état affiché, voir Chess:view()
    on_square = nil, -- function(square) : toucher sur une case
    on_button = nil, -- function(id) : toucher sur un bouton actif
    on_close = nil,  -- function() : touche Retour
}

local PIECE_FONT = "freefont/FreeSerif.ttf" -- seule police de KOReader avec les pièces d'échecs
local LIGHT, DARK, LAST = Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_LIGHT_GRAY, Blitbuffer.COLOR_GRAY_9

function BoardWidget:init()
    if Device:hasKeys() then
        self.key_events = {Close = {{Device.input.group.Back}}}
    end
    if Device:isTouchDevice() then
        self.ges_events = {Tap = {GestureRange:new{ges = "tap", range = function() return self.dimen end}}}
    end
    self.text_cache = {}
    self.button_rects = {}
    self:layout()
    if self.view then self:placeButtons(self.view) end
end

-- Disposition pour la taille d'écran courante : l'en-tête et les boutons prennent ce dont ils
-- ont besoin, l'échiquier occupe le reste avec des cases carrées, entouré d'une bande pour
-- les repères.
function BoardWidget:layout()
    local width, height = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{x = 0, y = 0, w = width, h = height}
    self.laid_out = {w = width, h = height}
    self.text_cache = {}
    self.fonts = {
        status = Font:getFace("tfont", 24),
        detail = Font:getFace("cfont", 17),
        button = Font:getFace("cfont", 19),
        coord = Font:getFace("cfont", 13),
    }
    self.pad = Screen:scaleBySize(6)
    self.line = Screen:scaleBySize(2)
    local status_h = self:text("Ag", "status"):getSize().h
    local detail_h = self:text("Ag", "detail"):getSize().h
    local header_h = status_h + detail_h + 3 * self.pad
    local button_h = Screen:scaleBySize(42)
    local gap = Screen:scaleBySize(8)
    local buttons_h = 2 * button_h + 3 * gap
    local band = Screen:scaleBySize(20)
    local square = math.floor(math.min(width - 2 * band, height - header_h - buttons_h - 2 * band) / 8)
    local board_w = 8 * square
    local free = height - header_h - buttons_h - 2 * band - board_w
    self.header = Geom:new{x = 0, y = 0, w = width, h = header_h}
    self.band, self.square, self.gap = band, square, gap
    self.board = Geom:new{x = math.floor((width - board_w) / 2), y = header_h + band + math.floor(free / 2), w = board_w, h = board_w}
    local rows_y = height - buttons_h + gap
    self.button_rows = {
        Geom:new{x = band, y = rows_y, w = width - 2 * band, h = button_h},
        Geom:new{x = band, y = rows_y + button_h + gap, w = width - 2 * band, h = button_h},
    }
    self.buttons_area = Geom:new{x = 0, y = height - buttons_h, w = width, h = buttons_h}
    local scale = Screen:scaleBySize(100) / 100
    self.fonts.piece = Font:getFace(PIECE_FONT, math.floor(square * 0.62 / scale))
    self.geometry = {square = square, band = band, header = header_h, button = button_h}
end

function BoardWidget:text(str, font, max_width)
    local key = font .. "|" .. str
    local widget = self.text_cache[key]
    if not widget then
        widget = TextWidget:new{text = str, face = self.fonts[font], padding = 0, max_width = max_width}
        self.text_cache[key] = widget
    end
    return widget
end

local function center(widget, bb, x, y, w, h)
    local size = widget:getSize()
    widget:paintTo(bb, x + math.floor((w - size.w) / 2), y + math.floor((h - size.h) / 2))
end

-- Rangée 1 en haut, colonne 1 à gauche. Échiquier retourné quand l'enfant joue les noirs.
function BoardWidget:squareAt(row, column)
    if self.view and self.view.flipped then return Board.square(9 - row, 9 - column) end
    return Board.square(row, column)
end

function BoardWidget:position(square)
    local file, rank = string.byte(square, 1) - 96, tonumber(square:sub(2, 2))
    if self.view and self.view.flipped then return rank, 9 - file end
    return 9 - rank, file
end

function BoardWidget:squareRect(row, column)
    return Geom:new{x = self.board.x + (column - 1) * self.square, y = self.board.y + (row - 1) * self.square,
        w = self.square, h = self.square}
end

function BoardWidget:placeButtons(view)
    self.button_rects = {}
    for r, row in ipairs(view.buttons or {}) do
        local area = self.button_rows[r]
        if area and #row > 0 then
            local width = math.floor((area.w - (#row - 1) * self.gap) / #row)
            for i, button in ipairs(row) do
                self.button_rects[#self.button_rects + 1] = {
                    id = button.id, text = button.text, enabled = button.enabled ~= false,
                    rect = Geom:new{x = area.x + (i - 1) * (width + self.gap), y = area.y, w = width, h = area.h},
                }
            end
        end
    end
end

-- Rendu -------------------------------------------------------------------------

function BoardWidget:paintTo(bb, x, y)
    if Screen:getWidth() ~= self.laid_out.w or Screen:getHeight() ~= self.laid_out.h then
        self:layout()
        if self.view then self:placeButtons(self.view) end
    end
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    local view = self.view
    if not view then return end
    self:paintHeader(bb, x, y, view)
    self:paintBoard(bb, x, y, view)
    self:paintButtons(bb, x, y)
end

function BoardWidget:paintHeader(bb, x, y, view)
    local max_width = self.dimen.w - 2 * self.band
    local status = self:text(view.status or "", "status", max_width)
    local detail = self:text(view.detail or "", "detail", max_width)
    local status_h = status:getSize().h
    center(status, bb, x, y + self.pad, self.dimen.w, status_h)
    center(detail, bb, x, y + 2 * self.pad + status_h, self.dimen.w, detail:getSize().h)
end

function BoardWidget:paintBoard(bb, x, y, view)
    local s = self.square
    local bw = math.max(self.line, math.floor(s / 16))
    for row = 1, 8 do
        for column = 1, 8 do
            local cell = view.squares[self:squareAt(row, column)] or {}
            local rect = self:squareRect(row, column)
            local rx, ry = x + rect.x, y + rect.y
            local background = cell.last and LAST or ((row + column) % 2 == 0 and LIGHT or DARK)
            bb:paintRect(rx, ry, s, s, background)
            if cell.piece then center(self:text(Board.piece(cell.piece), "piece"), bb, rx, ry, s, s) end
            if cell.mark == "selected" then
                bb:paintBorder(rx, ry, s, s, bw, Blitbuffer.COLOR_BLACK)
            elseif cell.mark == "dot" then
                bb:paintCircle(rx + math.floor(s / 2), ry + math.floor(s / 2), math.floor(s / 8), Blitbuffer.COLOR_BLACK)
            elseif cell.mark == "ring" then
                bb:paintCircle(rx + math.floor(s / 2), ry + math.floor(s / 2), math.floor(s / 2) - bw, Blitbuffer.COLOR_BLACK, bw)
            end
            if cell.star then
                local star = self:text("★", "coord")
                star:paintTo(bb, rx + s - star:getSize().w - self.pad, ry + self.pad)
            end
        end
    end
    bb:paintBorder(x + self.board.x - self.line, y + self.board.y - self.line,
        self.board.w + 2 * self.line, self.board.h + 2 * self.line, self.line, Blitbuffer.COLOR_BLACK)
    if view.coords then
        for i = 1, 8 do
            local rank = view.flipped and i or 9 - i
            center(self:text(tostring(rank), "coord"), bb, x + self.board.x - self.band, y + self.board.y + (i - 1) * s, self.band, s)
            local file = view.flipped and 9 - i or i
            center(self:text(string.char(64 + file), "coord"), bb, x + self.board.x + (i - 1) * s, y + self.board.y + self.board.h, s, self.band)
        end
    end
end

function BoardWidget:paintButtons(bb, x, y)
    local radius = Screen:scaleBySize(6)
    for _, button in ipairs(self.button_rects) do
        local rect = button.rect
        local color = button.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY
        bb:paintBorder(x + rect.x, y + rect.y, rect.w, rect.h, self.line, color, radius)
        local label = self:text(button.text, "button", rect.w - 2 * self.pad)
        label.fgcolor = color
        center(label, bb, x + rect.x, y + rect.y, rect.w, rect.h)
    end
end

-- Mise à jour ---------------------------------------------------------------------

local function cell_key(cell)
    if not cell then return "" end
    return (cell.piece or "-") .. (cell.mark or "-") .. (cell.star and "*" or "-") .. (cell.last and "L" or "-")
end

local function buttons_key(view)
    local parts = {}
    for _, row in ipairs(view.buttons or {}) do
        for _, button in ipairs(row) do
            parts[#parts + 1] = tostring(button.id) .. ":" .. button.text .. ":" .. tostring(button.enabled ~= false)
        end
        parts[#parts + 1] = "/"
    end
    return table.concat(parts, "|")
end

-- Remplace l'état affiché et ne demande que les rafraîchissements partiels nécessaires :
-- l'en-tête, la boîte englobante des cases modifiées, la zone des boutons.
function BoardWidget:setView(view)
    local previous = self.view
    self.view = view
    self:placeButtons(view)
    self.refreshed = {}
    if not self.shown or not previous then return end
    local regions = {}
    if previous.flipped ~= view.flipped or previous.coords ~= view.coords then
        regions[1] = self.dimen
    else
        if (previous.status or "") ~= (view.status or "") or (previous.detail or "") ~= (view.detail or "") then
            regions[#regions + 1] = self.header
        end
        local box
        for square, cell in pairs(view.squares) do
            if cell_key(cell) ~= cell_key(previous.squares[square]) then
                local rect = self:squareRect(self:position(square))
                box = box and box:combine(rect) or rect
            end
        end
        if box then regions[#regions + 1] = box end
        if buttons_key(previous) ~= buttons_key(view) then regions[#regions + 1] = self.buttons_area end
    end
    for _, region in ipairs(regions) do
        UIManager:setDirty(self, function() return "ui", region end)
    end
    self.refreshed = regions
end

-- Événements ------------------------------------------------------------------------

function BoardWidget:onShow()
    self.shown = true
    UIManager:setDirty(self, function() return "full", self.dimen end)
    return true
end

function BoardWidget:onCloseWidget()
    self.shown = false
    for _, widget in pairs(self.text_cache) do widget:free() end
    self.text_cache = {}
    UIManager:setDirty(nil, function() return "flashui", self.dimen end)
end

function BoardWidget:onClose()
    if self.on_close then self.on_close() end
    return true
end

function BoardWidget:onTap(_, ges)
    local pos = ges.pos
    for _, button in ipairs(self.button_rects) do
        if button.rect:contains(pos) then
            if button.enabled and self.on_button then self.on_button(button.id) end
            return true
        end
    end
    if self.board:contains(pos) then
        local column = math.min(8, math.max(1, math.floor((pos.x - self.board.x) / self.square) + 1))
        local row = math.min(8, math.max(1, math.floor((pos.y - self.board.y) / self.square) + 1))
        if self.on_square then self.on_square(self:squareAt(row, column)) end
    end
    return true
end

return BoardWidget
