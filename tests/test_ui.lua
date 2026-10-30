package.path = "chess.koplugin/?.lua;" .. package.path
local Game = require("game")
local shown, closed, dirty, scheduled = {}, {}, {}, {}
local settings = {data = {}}
function settings:readSetting(key) return self.data[key] end
function settings:saveSetting(key, value) self.data[key] = value end
function settings:nilOrTrue(key) return self.data[key] == nil or self.data[key] == true end
function settings:flush() end

local clock = 0
local SCALE = 2.1 -- Tolino Vision Color : 1264 × 1680, 300 ppp
local function scale(px) return math.ceil(px * SCALE) end

-- Géométrie minimale, même contrat que ui/geometry de KOReader.
local Geom = {}
Geom.__index = Geom
function Geom:new(o) return setmetatable(o or {x = 0, y = 0, w = 0, h = 0}, Geom) end
function Geom:contains(g)
    return self.x <= g.x and self.y <= g.y and self.x + self.w >= g.x + (g.w or 0) and self.y + self.h >= g.y + (g.h or 0)
end
function Geom:combine(b)
    local x, y = math.min(self.x, b.x), math.min(self.y, b.y)
    return Geom:new{x = x, y = y, w = math.max(self.x + self.w, b.x + b.w) - x, h = math.max(self.y + self.h, b.y + b.h) - y}
end
local function point(x, y) return Geom:new{x = x, y = y, w = 0, h = 0} end

package.preload["ffi/blitbuffer"] = function() return {
    COLOR_WHITE = "white", COLOR_LIGHT_GRAY = "light", COLOR_GRAY_9 = "last", COLOR_BLACK = "black", COLOR_GRAY = "gray",
} end
package.preload["ui/geometry"] = function() return Geom end
package.preload["ui/gesturerange"] = function() return {new = function(_, o) return o end} end
package.preload["ui/font"] = function() return {getFace = function(_, name, size) return {name = name, size = scale(size)} end} end
package.preload["ui/widget/textwidget"] = function() return {new = function(_, args)
    args.getSize = function(self) return {w = math.floor(#self.text * self.face.size / 2), h = self.face.size} end
    args.paintTo = function(self, bb, x, y) bb.calls[#bb.calls + 1] = {"text", self.text, x, y, self.fgcolor} end
    args.free = function(self) self.freed = true end
    return args
end} end
package.preload["ui/widget/container/inputcontainer"] = function()
    local InputContainer = {}
    InputContainer.__index = InputContainer
    function InputContainer:extend(o) o = o or {}; setmetatable(o, self); self.__index = self; return o end
    function InputContainer:new(o)
        o = self:extend(o)
        o.key_events, o.ges_events = o.key_events or {}, o.ges_events or {}
        if o.init then o:init() end
        return o
    end
    return InputContainer
end
package.preload["ui/widget/buttondialog"] = function() return {new = function(_, args) args.button_dialog = true; return args end} end
package.preload["ui/widget/confirmbox"] = function() return {new = function(_, args) args.confirm = true; return args end} end
package.preload["datastorage"] = function() return {getSettingsDir = function() return "/tmp" end} end
package.preload["ui/widget/infomessage"] = function() return {new = function(_, args) args.info = true; return args end} end
package.preload["luasettings"] = function() return {open = function() return settings end} end
package.preload["ui/uimanager"] = function() return {
    show = function(_, dialog) shown[#shown + 1] = dialog; if dialog.onShow then dialog:onShow() end end,
    close = function(_, dialog) closed[#closed + 1] = dialog; if dialog.onCloseWidget then dialog:onCloseWidget() end end,
    setDirty = function(_, widget, refresh)
        local mode, region = refresh, nil
        if type(refresh) == "function" then mode, region = refresh() end
        dirty[#dirty + 1] = {widget = widget, mode = mode, region = region}
    end,
    unschedule = function() end,
    scheduleIn = function(_, delay, action, ...) scheduled[#scheduled + 1] = {delay = delay, action = action, args = {...}} end,
} end
package.preload["ui/widget/container/widgetcontainer"] = function() return {
    extend = function(_, values) values.__index = values; return values end,
} end
package.preload["ffi/util"] = function() return {} end
package.preload["device"] = function() return {
    screen = {getWidth = function() return 1264 end, getHeight = function() return 1680 end, scaleBySize = function(_, px) return scale(px) end},
    hasKeys = function() return true end, isTouchDevice = function() return true end,
    input = {group = {Back = {"Back"}}},
} end
package.preload["ui/time"] = function() return {
    now = function() return clock end, s = function(seconds) return seconds end,
    since = function(start) return clock - start end,
    to_ms = function(value) return math.floor(value * 1000 + 0.5) end,
} end
package.preload["logger"] = function() return {
    dbg = function() end, info = function() end, warn = function() end, err = function() end,
} end

local function fake_bb()
    local bb = {calls = {}}
    function bb:paintRect(x, y, w, h, color) self.calls[#self.calls + 1] = {"rect", x, y, w, h, color} end
    function bb:paintBorder(x, y, w, h, bw, color, radius) self.calls[#self.calls + 1] = {"border", x, y, w, h, bw, color, radius} end
    function bb:paintCircle(cx, cy, r, color, w) self.calls[#self.calls + 1] = {"circle", cx, cy, r, color, w} end
    return bb
end

local function find(bb, kind, x, y)
    for _, call in ipairs(bb.calls) do
        if call[1] == kind and call[2] == x and call[3] == y then return call end
    end
    return nil
end

local Chess = dofile("chess.koplugin/main.lua")
local registered
-- Depuis un livre, ReaderUI transmet `dialog = ReaderUI` au plugin : ce champ ne doit jamais être fermé.
local reader = {name = "readerui"}
local chess = setmetatable({ui = {menu = {registerToMainMenu = function(_, plugin) registered = plugin end}}, dialog = reader}, Chess)
chess:init()
assert(registered == chess)
assert(chess.game.level == "decouverte" and chess.game.color == "w")
local menu = {}
chess:addToMainMenu(menu)
assert(menu.chess.text == "Échecs")

local function view() return chess.board_widget.view end
local function cell(square) return view().squares[square] end
local function button(id)
    for _, row in ipairs(view().buttons) do
        for _, entry in ipairs(row) do if entry.id == id then return entry end end
    end
    return nil
end

local started = 0
local before
chess.startEngine = function(self) started = started + 1; self.engine = self.engine or {play = function() end}; return true end
chess:openBoard()
assert(started == 1 and chess.opened)
local widget = chess.board_widget
assert(shown[1] == widget and widget.shown and dirty[1].mode == "full") -- un seul rafraîchissement complet à l'ouverture
assert(cell("e2").piece == "P" and view().status == "Un instant…") -- position initiale affichée avant la réponse du moteur
assert(view().coords == true and not view().flipped)

-- géométrie plein écran sur 1264 × 1680 : cases de 147 px, échiquier de 1176 px centré, bande de 42 px
local board = widget.board
assert(widget.square == 147 and board.w == 1176 and board.x == 44 and board.y == 200, widget.square .. " " .. board.x .. " " .. board.y)
assert(widget.band == 42 and widget.header.h == 126 and #widget.button_rects == 6)
assert(widget.button_rects[1].id == "new" and widget.button_rects[3].id == "close" and widget.button_rects[6].id == "claim")
assert(widget.button_rects[6].rect.y + widget.button_rects[6].rect.h <= 1680 - 17)

local function tap(column, row) -- colonne et rangée à l'écran, 1 = gauche / haut
    widget:onTap(nil, {pos = point(board.x + (column - 1) * 147 + 10, board.y + (row - 1) * 147 + 10)})
end

local start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
local played
chess.engine = {play = function(_, moves) played = moves[#moves] end, think = function() end, hint = function() return true end}
chess:acceptPosition(start, {"e2e4", "e2e3", "g1f3", "g1h3"}, false)
assert(not chess.waiting)
assert(chess.dialog == reader and chess.board_widget ~= reader)
assert(view().status == "À vous de jouer" and view().detail == "Apprentissage · Découverte", view().detail)
assert(button("undo").enabled == false and button("hint").enabled == true and button("claim").enabled == false)
assert(#widget.refreshed == 2) -- en-tête et boutons : rien sur l'échiquier

-- sélection : marqueurs dessinés sans déplacer la pièce, une seule région rafraîchie
tap(5, 2) -- e7, pièce adverse : rien
assert(chess.selected == nil)
tap(5, 7) -- e2
assert(chess.selected == "e2" and cell("e2").mark == "selected" and cell("e2").piece == "P")
assert(cell("e4").mark == "dot" and cell("e3").mark == "dot" and cell("f3").mark == nil)
assert(#widget.refreshed == 1 and widget.refreshed[1].mode == nil)
local box = widget.refreshed[1]
assert(box.x == board.x + 4 * 147 and box.y == board.y + 4 * 147 and box.w == 147 and box.h == 3 * 147, box.y .. " " .. box.h)
assert(dirty[#dirty].mode == "ui" and dirty[#dirty].region == box)
local bb = fake_bb()
widget:paintTo(bb, 0, 0)
local frame = find(bb, "border", board.x + 4 * 147, board.y + 6 * 147)
assert(frame and frame[6] == 9 and frame[7] == "black", "cadre de sélection sur e2")
local dot = find(bb, "circle", board.x + 4 * 147 + 73, board.y + 4 * 147 + 73)
assert(dot and dot[4] == 18 and dot[6] == nil, "point plein sur e4")
assert(find(bb, "rect", board.x, board.y)[6] == "white" and find(bb, "rect", board.x + 147, board.y)[6] == "light") -- a8 claire, b8 foncée
local coords = 0
for _, call in ipairs(bb.calls) do
    if call[1] == "text" and (call[2] == "A" or call[2] == "8") then coords = coords + 1 end
end
assert(coords == 2, coords)
tap(7, 8) -- g1 : autre pièce à soi, on change de sélection
assert(chess.selected == "g1" and cell("e2").mark == nil and cell("e4").mark == nil and cell("f3").mark == "dot")
tap(7, 8) -- même case : désélection
assert(chess.selected == nil and cell("f3").mark == nil and cell("g1").piece == "N")
local refreshes = #dirty
tap(5, 7); tap(5, 5) -- e2e4
assert(played == "e2e4" and chess.waiting and chess.selected == nil)
assert(settings.data.game.moves[1] == "e2e4" and settings.data.game.color == "w")
assert(#dirty == refreshes + 1) -- la sélection seulement : pas de rendu avant la confirmation du moteur
chess:acceptPosition("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", {"e7e5"}, false)
assert(chess.waiting and view().status == "L'ordinateur réfléchit…")
assert(view().detail == "Apprentissage · Découverte · Blancs : E2 → E4", view().detail)
assert(cell("e4").piece == "P" and cell("e2").piece == nil and cell("e2").last and cell("e4").last)

-- réponse de l'ordinateur : la pièce est encadrée, le coup n'est appliqué qu'après la pause
chess:engineMoved("e7e5")
assert(chess.pending_move == "e7e5" and #chess.game.moves == 1 and cell("e7").mark == "selected" and cell("e7").piece == "p")
assert(scheduled[#scheduled].delay == 0.8 and scheduled[#scheduled].action == Chess.applyPendingMove)
assert(#widget.refreshed == 1 and widget.refreshed[1].h == 147) -- une seule case
assert(view().status == "L'ordinateur réfléchit…")
chess:applyPendingMove()
assert(#chess.game.moves == 2 and played == "e7e5" and chess.pending_move == nil)
chess:acceptPosition("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2", {"g1f3", "d2d4"}, false)
assert(view().status == "À vous de jouer" and view().detail == "Apprentissage · Découverte · Noirs : E7 → E5", view().detail)
assert(cell("e7").last and cell("e5").last and not cell("e2").last and cell("e7").mark == nil)
assert(settings.data.game.keys[3] ~= nil)
-- fermeture pendant la pause : le coup en attente est oublié avec le moteur
chess.pending_move = "d2d4"
chess:stopEngine()
assert(chess.pending_move == nil)
chess:applyPendingMove()
assert(#chess.game.moves == 2)
chess.engine = {play = function(_, moves) played = moves[#moves] end, think = function() end, hint = function() return true end}

-- prise en passant : case d'arrivée vide mais marquée comme une prise (anneau)
chess.game = Game.new({"e2e4", "a7a6", "e4e5", "d7d5"}, "facile")
chess:acceptPosition("rnbqkbnr/1pp1pppp/p7/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3", {"e5d6", "e5e6", "e1e2"}, false)
chess:tapSquare("e5")
assert(cell("d6").mark == "ring" and cell("e6").mark == "dot", tostring(cell("d6").mark))
bb = fake_bb()
widget:paintTo(bb, 0, 0)
local ring = find(bb, "circle", board.x + 3 * 147 + 73, board.y + 2 * 147 + 73)
assert(ring and ring[6] == 9 and ring[4] == 73 - 9, "anneau sur d6")
chess:tapSquare("e5")

-- sauvegarde incohérente (coup illégal ignoré par Stockfish) : nouvelle partie au premier contrôle
chess.game = Game.new({"e2e4", "e7e5", "e2e5"}, "facile", {mode = "partie", color = "b"})
chess.validate_save = true
played = "?"
local before_shown = #shown
local go_on = chess:acceptPosition("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2", {"g1f3"}, false)
assert(go_on == false and #chess.game.moves == 0 and chess.game.mode == "partie" and chess.game.color == "b" and played == nil)
assert(shown[before_shown + 1].info and not chess.validate_save)
assert(chess:acceptPosition(start, {"e2e4"}, false) == true) -- l'enfant a les noirs : l'ordinateur commence
assert(view().status == "L'ordinateur réfléchit…" and view().detail == "Partie · Facile" and view().flipped)

-- moteur arrêté pendant le tour de l'ordinateur (délai dépassé) : un toucher le relance malgré le trait
chess.game = Game.new({"e2e4"}, "facile")
chess:acceptPosition("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", {"e7e5"}, false)
chess.engine, chess.waiting = nil, false
before = started
chess:tapSquare("e7")
assert(started == before + 1 and chess.selected == nil)
chess.engine = {play = function(_, moves) played = moves[#moves] end, think = function() end, hint = function() return true end}
chess.game = Game.new({"e2e4", "e7e5"}, "facile")
chess:acceptPosition("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2", {"g1f3", "d2d4"}, false)

-- un rendu identique ne demande aucun rafraîchissement
refreshes = #dirty
chess:render()
assert(#dirty == refreshes and #widget.refreshed == 0)

-- annulation : confirmation, puis deux demi-coups retirés et position redemandée au moteur
assert(chess:canUndo() and button("undo").enabled == true)
chess:onButton("undo")
local confirm = shown[#shown]
assert(confirm.confirm and confirm.ok_text == "Oui" and confirm.cancel_text == "Non")
assert(#chess.game.moves == 2) -- rien avant la confirmation
confirm.ok_callback()
assert(#chess.game.moves == 0 and chess.waiting and played == nil)
chess:acceptPosition(start, {"e2e4", "g1f3"}, false)
assert(not chess:canUndo())

-- indice : sélection automatique de la pièce et étoile sur la case conseillée
local hint_requests = 0
chess.engine.hint = function() hint_requests = hint_requests + 1; return true end
chess:onButton("hint")
assert(hint_requests == 1 and chess.waiting and chess.hinting)
assert(view().status == "Je cherche un conseil…")
chess:showHint("g1f3")
assert(not chess.waiting and chess.selected == "g1" and chess.hint == "g1f3")
assert(cell("f3").star and cell("f3").mark == "dot" and cell("g1").mark == "selected" and not cell("h3").star)
chess:tapSquare("f3")
assert(played == "g1f3" and chess.hint == nil)

-- nulle réclamable après le coup de l'enfant : l'ordinateur attend la décision
local searches = 0
chess.engine = {play = function() end, think = function() searches = searches + 1 end, hint = function() return true end}
local should_search = chess:acceptPosition("4k3/7p/8/8/8/8/P7/4K3 b - - 100 51", {"e8e7"}, false)
assert(should_search == false and chess.pending_draw_decision and searches == 0)
assert(view().status == "Nulle possible · choisir")
assert(button("continue") and button("claim").enabled ~= false)
chess:onButton("claim") -- réclamer : confirmation d'abord
assert(shown[#shown].confirm and chess.pending_draw_decision)
chess:onButton("continue")
assert(searches == 1 and chess.waiting and not chess.pending_draw_decision)
chess:claimDraw()
assert(chess.game:result() == "nulle_reclamee" and not chess.waiting and chess.engine == nil)
assert(view().status == "Partie nulle")

-- mat donné par l'enfant : message de victoire, moteur arrêté, nouvelle partie sans confirmation
chess.engine = {play = function() end}
chess.game = Game.new(nil, "facile")
chess:acceptPosition("7k/6Q1/5K2/8/8/8/8/8 b - - 0 1", {}, true)
assert(view().status == "Échec et mat · tu as gagné !", view().status)
assert(chess.engine == nil)
before = started
chess:onButton("new") -- échiquier sans coup joué : pas de confirmation, choix du mode direct
assert(started == before and chess.mode_dialog and not shown[#shown].confirm)
assert(#chess.mode_dialog.buttons == 4 and chess.mode_dialog.buttons[2][1].text == "Partie · sans aide")
assert(chess.mode_dialog.buttons[3][1].text == "Deux joueurs · à tour de rôle sur l'écran")
chess.mode_dialog.buttons[2][1].callback() -- Partie : puis choix de la couleur
assert(chess.mode_dialog == nil and chess.color_dialog and started == before)
assert(chess.color_dialog.title == "Vos pièces" and chess.color_dialog.buttons[2][1].text == "Noirs · l'ordinateur commence")
chess.color_dialog.buttons[2][1].callback()
assert(started == before + 1 and #chess.game.moves == 0 and chess.game.mode == "partie" and chess.game.color == "b")
assert(chess.color_dialog == nil and settings.data.game.mode == "partie" and settings.data.game.color == "b")
chess.engine = {play = function(_, moves) played = moves[#moves] end, think = function() end, hint = function() return true end}
assert(view().flipped)
-- échiquier retourné : la case en haut à gauche est h1, les repères suivent
tap(1, 1)
assert(chess.selected == nil) -- pas encore de position
assert(widget:squareAt(1, 1) == "h1" and widget:squareAt(8, 8) == "a8")
bb = fake_bb()
widget:paintTo(bb, 0, 0)
local first_rank, first_file
for _, call in ipairs(bb.calls) do
    if call[1] == "text" and call[2] == "1" and not first_rank then first_rank = call end
    if call[1] == "text" and call[2] == "H" and not first_file then first_file = call end
end
assert(first_rank and first_rank[4] < board.y + 147 and first_file and first_file[3] < board.x + 147)
assert(chess:acceptPosition(start, {"e2e4"}, false) == true and chess.waiting)
assert(view().status == "L'ordinateur réfléchit…")
chess:engineMoved("e2e4"); chess:applyPendingMove()
chess:acceptPosition("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", {"e7e5", "g8f6"}, false)
assert(view().status == "À vous de jouer" and view().detail == "Partie · Facile · Blancs : E2 → E4", view().detail)
tap(4, 7) -- rangée 7 à l'écran = rangée 7 réelle, colonne 4 à l'écran = colonne e
assert(chess.selected == "e7", tostring(chess.selected))
chess:tapSquare("e5")
assert(played == "e7e5")
-- mat subi par l'enfant qui joue les noirs
chess.game = Game.new(nil, "facile", {color = "b"})
chess:acceptPosition("7k/6Q1/5K2/8/8/8/8/8 b - - 0 1", {}, true)
assert(view().status == "Échec et mat · l'ordinateur a gagné", view().status)

-- mode Partie : ni annulation ni indice, deuxième rangée réduite à la nulle
chess.game = Game.new({"e2e4", "e7e5"}, "facile", {mode = "partie"})
chess.engine = {play = function() end, hint = function() error("pas d'indice en mode Partie") end}
chess:acceptPosition("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2", {"g1f3"}, false)
assert(view().detail == "Partie · Facile · Noirs : E7 → E5", view().detail)
assert(#view().buttons[2] == 1 and view().buttons[2][1].id == "claim" and not button("undo") and not button("hint"))
assert(not chess:canUndo())
chess:requestHint()
assert(not chess.hinting and not chess.waiting)
chess:onButton("new") -- nouvelle partie : confirmation, puis choix du mode
assert(shown[#shown].confirm and shown[#shown].text:find("effacée", 1, true) and #chess.game.moves == 2)
shown[#shown].ok_callback()
assert(chess.mode_dialog and #chess.game.moves == 2)
before = started
chess.mode_dialog.buttons[1][1].callback() -- Apprentissage
chess.color_dialog.buttons[1][1].callback() -- Blancs
assert(started == before + 1 and #chess.game.moves == 0 and chess.game.mode == "apprentissage" and chess.game.color == "w")
chess.game = Game.new({"f2f3", "e7e5", "g2g4", "d8h4"}, "facile")
chess:acceptPosition("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3", {}, true)
chess:onButton("new") -- partie finie mais coups joués : confirmation aussi
assert(shown[#shown].confirm and not shown[#shown].text:find("effacée", 1, true))
assert(view().detail == "Apprentissage · Facile · Noirs : D8 → H4")
-- promotion décrite dans l'en-tête
chess.game = Game.new({"e2e4", "e7e5", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e5e4", "e4e5", "e7e8q"}, "facile")
chess:acceptPosition("4Q3/8/8/8/8/8/8/4K2k b - - 0 26", {"h1h2"}, false)
assert(view().detail == "Apprentissage · Facile · Noirs : E7 → E8 (dame)", view().detail)

-- mode Deux joueurs : les deux couleurs jouent sur l'écran, le moteur ne cherche jamais
before = started
chess:confirmNewGame()
shown[#shown].ok_callback()
chess.mode_dialog.buttons[3][1].callback() -- pas de choix de couleur
assert(started == before + 1 and chess.game.mode == "deux_joueurs" and chess.color_dialog == nil and chess.mode_dialog == nil)
chess.engine = {play = function(_, moves) played = moves[#moves] end,
    think = function() error("pas de recherche à deux joueurs") end, hint = function() error("pas d'indice") end}
local should = chess:acceptPosition(start, {"e2e4"}, false)
assert(should == false and not chess.waiting and not view().flipped)
assert(view().status == "Aux blancs de jouer" and view().detail == "Deux joueurs", view().detail)
assert(#view().buttons[1] == 3 and #view().buttons[2] == 2 and button("undo").enabled == false and button("claim"))
chess:tapSquare("e7") -- pièce noire alors que c'est aux blancs
assert(chess.selected == nil)
chess:tapSquare("e2"); chess:tapSquare("e4")
assert(played == "e2e4" and chess.waiting)
should = chess:acceptPosition("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", {"e7e5", "e7e6"}, false)
assert(should == false and not chess.waiting and not chess.pending_draw_decision)
assert(view().status == "Aux noirs de jouer" and view().detail == "Deux joueurs · Blancs : E2 → E4", view().detail)
chess:tapSquare("e2") -- pièce blanche alors que c'est aux noirs
assert(chess.selected == nil)
chess:tapSquare("e7")
assert(chess.selected == "e7" and cell("e7").mark == "selected" and cell("e5").mark == "dot" and cell("e6").mark == "dot")
chess:tapSquare("e5")
assert(played == "e7e5")
chess:acceptPosition("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2", {"g1f3"}, false)
assert(chess:canUndo() and button("undo").enabled == true)
chess:onButton("undo")
assert(shown[#shown].confirm and shown[#shown].text == "Annuler le dernier coup ?")
shown[#shown].ok_callback()
assert(#chess.game.moves == 1 and chess.game.moves[1] == "e2e4" and chess.waiting) -- un seul demi-coup retiré
chess.game = Game.new({"f2f3", "e7e5", "g2g4", "d8h4"}, "facile", {mode = "deux_joueurs"})
chess:acceptPosition("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3", {}, true)
assert(view().status == "Échec et mat · les noirs gagnent", view().status)
assert(chess.engine == nil)
-- réglages à deux joueurs : pas de niveau, seulement les repères
chess:onButton("settings")
assert(chess.settings_dialog and #chess.settings_dialog.buttons == 2 and chess.settings_dialog.title == "Réglages")
assert(chess.settings_dialog.buttons[1][1].text == "Masquer les repères (A–H, 1–8)")
chess:closeSettings()

chess.game = Game.new(nil, "facile")
chess:acceptPosition("7k/5K2/8/8/8/8/8/7Q w - - 0 1", {}, true)
assert(view().status == "Échec et mat · l'ordinateur a gagné", view().status)

-- réglages : niveau et repères
chess:onButton("settings")
assert(chess.settings_dialog and #chess.settings_dialog.buttons == 7)
assert(chess.settings_dialog.buttons[3][1].text == "✓ Facile", chess.settings_dialog.buttons[3][1].text)
assert(chess.settings_dialog.buttons[1][1].text == "Découverte · joue souvent au hasard")
assert(chess.settings_dialog.buttons[7][1].text == "Retour")
chess:setLevel("difficile")
assert(chess.game.level == "difficile" and chess.settings_dialog == nil)
assert(settings.data.game.level == "difficile" and view().detail == "Apprentissage · Difficile")
chess:onButton("settings")
chess.settings_dialog.buttons[6][1].callback() -- masquer les repères
assert(chess.settings_dialog == nil and settings.data.coords == false and view().coords == false)
assert(#widget.refreshed == 1 and widget.refreshed[1] == widget.dimen) -- tout l'écran, en mode « ui »
bb = fake_bb()
widget:paintTo(bb, 0, 0)
for _, call in ipairs(bb.calls) do assert(not (call[1] == "text" and call[2] == "A"), "repères encore dessinés") end
chess:onButton("settings")
assert(chess.settings_dialog.buttons[6][1].text == "Afficher les repères (A–H, 1–8)")
chess.settings_dialog.buttons[6][1].callback()
assert(settings.data.coords == true and view().coords == true)

-- garde-fou : moteur muet pendant plus de 20 s au trait de l'ordinateur
clock = 100
chess.engine = {play = function() end, think = function() end}
chess.game = Game.new({"e2e4"}, "facile")
chess:acceptPosition("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", {"e7e5"}, false)
assert(chess.waiting and view().status == "L'ordinateur réfléchit…", view().status)
chess.transport = {poll = function() return {} end, close = function() end}
clock = 119
chess:poll()
assert(chess.engine ~= nil and chess.waiting) -- 19 s : on attend encore
clock = 121
chess:poll()
assert(chess.engine == nil and not chess.waiting)
assert(shown[#shown].info and view().status == "Moteur arrêté · touchez l'échiquier", view().status)

-- veille : moteur arrêté, partie sauvegardée, reprise au réveil
local stopped = false
chess.transport = {close = function() stopped = true end}
chess.engine = {}
chess.game = Game.new({"e2e4"}, "facile")
chess:onSuspend()
assert(stopped and chess.transport == nil and chess.engine == nil and chess.waiting)
before = started
chess:onResume()
assert(started == before + 1)
chess:render()
-- touche Retour ou bouton Fermer : confirmation, puis fermeture de l'échiquier avec un flash final
widget:onClose()
assert(shown[#shown].confirm and chess.opened)
shown[#shown].ok_callback()
assert(not chess.opened and chess.board_widget == nil and closed[#closed] == widget and not widget.shown)
assert(dirty[#dirty].mode == "flashui")
for _, dialog in ipairs(closed) do assert(dialog ~= reader, "le plugin a fermé ReaderUI") end

-- reprise : la partie sauvegardée à la fermeture (coups, mode, couleur, niveau) est rechargée à l'ouverture suivante
assert(settings.data.game.moves[1] == "e2e4" and settings.data.game.level == "facile")
local again = setmetatable({ui = {menu = {registerToMainMenu = function() end}}}, Chess)
again:init()
assert(#again.game.moves == 1 and again.game.moves[1] == "e2e4" and again.game.level == "facile")
assert(again.game.mode == settings.data.game.mode and again.game.color == settings.data.game.color)
again.startEngine = function(self) self.engine = {play = function() end}; return true end
again:openBoard()
assert(again.board_widget.view.squares.e4.piece == nil) -- position affichée seulement après la réponse du moteur
assert(again.board_widget.view.detail:find("Blancs : E2 → E4", 1, true), again.board_widget.view.detail)
print("ui: OK")
