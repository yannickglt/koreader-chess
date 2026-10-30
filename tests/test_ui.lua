package.path = "chess.koplugin/?.lua;" .. package.path
local Game = require("game")
local shown, closed = {}, {}
local settings = {data = {}}
function settings:readSetting(key) return self.data[key] end
function settings:saveSetting(key, value) self.data[key] = value end
function settings:flush() end

local clock = 0
package.preload["ffi/blitbuffer"] = function() return {COLOR_WHITE = 1, COLOR_LIGHT_GRAY = 2, COLOR_GRAY_9 = 3} end
package.preload["ui/widget/buttondialog"] = function() return {new = function(_, args)
    local buttons = {}
    for _, row in ipairs(args.buttons) do
        for _, entry in ipairs(row) do
            if entry.id then
                buttons[entry.id] = {
                    text = entry.text, width = entry.width, height = entry.height,
                    background = entry.background, font_size = entry.font_size,
                    setText = function(self, value) self.text = value end,
                    refresh = function(self) self.refreshed = (self.refreshed or 0) + 1 end,
                }
            end
        end
    end
    args.buttontable = {getButtonById = function(_, id) return buttons[id] end}
    return args
end} end
package.preload["ui/widget/confirmbox"] = function() return {new = function(_, args) args.confirm = true; return args end} end
package.preload["datastorage"] = function() return {getSettingsDir = function() return "/tmp" end} end
package.preload["ui/widget/infomessage"] = function() return {new = function(_, args) args.info = true; return args end} end
package.preload["luasettings"] = function() return {open = function() return settings end} end
package.preload["ui/uimanager"] = function() return {
    show = function(_, dialog) shown[#shown + 1] = dialog end,
    close = function(_, dialog) closed[#closed + 1] = dialog end,
    unschedule = function() end, scheduleIn = function() end,
} end
package.preload["ui/widget/container/widgetcontainer"] = function() return {
    extend = function(_, values) values.__index = values; return values end,
} end
package.preload["ffi/util"] = function() return {} end
package.preload["device"] = function() return {screen = {
    getWidth = function() return 1264 end, getHeight = function() return 1680 end,
    scaleBySize = function(_, px) return math.ceil(px * 2.1) end,
}} end
package.preload["ui/size"] = function() return {
    line = {medium = 2}, border = {window = 3}, padding = {button = 4, buttontable = 8},
} end
package.preload["ui/time"] = function() return {
    now = function() return clock end, s = function(seconds) return seconds end,
    since = function(start) return clock - start end,
    to_ms = function(value) return math.floor(value * 1000 + 0.5) end,
} end
package.preload["logger"] = function() return {
    dbg = function() end, info = function() end, warn = function() end, err = function() end,
} end

local function button(id) return _G.chess.dialog.buttontable:getButtonById(id) end

local Chess = dofile("chess.koplugin/main.lua")
local registered
local chess = setmetatable({ui = {menu = {registerToMainMenu = function(_, plugin) registered = plugin end}}}, Chess)
_G.chess = chess
chess:init()
assert(registered == chess)
assert(chess.game.level == "decouverte")
local menu = {}
chess:addToMainMenu(menu)
assert(menu.chess.text == "Échecs")

local started = 0
chess.startEngine = function(self) started = started + 1; self.engine = self.engine or {play = function() end}; return true end
chess:openBoard()
assert(started == 1 and chess.opened)
assert(button("e2").text == "♙") -- position initiale affichée avant la réponse du moteur

-- géométrie sur l'écran 1264 × 1680 : cases carrées de 148 px, boîte de 1212 px, glyphes à 40 pt
local geometry = chess:geometry()
assert(geometry.square == 148, geometry.square)
assert(geometry.width == 1212, geometry.width)
assert(geometry.button_height == 132, geometry.button_height)
assert(geometry.font_size == 40, geometry.font_size)

local start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
local played
chess.engine = {play = function(_, moves) played = moves[#moves] end, think = function() end, hint = function() return true end}
chess:acceptPosition(start, {"e2e4", "e2e3", "g1f3", "g1h3"}, false)
assert(not chess.waiting)
assert(chess.game.mode == "apprentissage")
assert(chess.dialog.title == "Apprentissage · À vous de jouer", chess.dialog.title)
local e2 = button("e2")
assert(e2.width == 148 and e2.height == 132 and e2.font_size == 40 and e2.background == 1)
assert(button("e3").background == 2)
assert(chess.dialog.buttons[10][1].enabled == false and chess.dialog.buttons[10][2].enabled == true)

-- sélection : marqueurs partiels sans reconstruire la boîte
local dialog_before = chess.dialog
chess:tapSquare("e7") -- pièce adverse : rien
assert(chess.selected == nil)
chess:tapSquare("e2")
assert(chess.selected == "e2" and chess.dialog == dialog_before)
assert(e2.text == "•♙", e2.text)
assert(button("e4").text == "○ " and button("e3").text == "○ " and button("f3").text == " ")
assert(e2.refreshed == 1)
chess:tapSquare("g1") -- autre pièce à soi : on change de sélection
assert(chess.selected == "g1" and e2.text == "♙" and button("e4").text == " " and button("f3").text == "○ ")
chess:tapSquare("g1") -- même case : désélection
assert(chess.selected == nil and button("f3").text == " " and button("g1").text == "♘")
local before_move = chess.dialog
chess:tapSquare("e2"); chess:tapSquare("e4")
assert(played == "e2e4" and chess.waiting and chess.selected == nil)
assert(settings.data.game.moves[1] == "e2e4")
assert(chess.dialog == before_move) -- pas de rendu avant la confirmation du moteur
chess:acceptPosition("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", {"e7e5"}, false)
assert(chess.waiting and chess.dialog ~= before_move)
assert(chess.dialog.title == "Apprentissage · L'ordinateur réfléchit…")
assert(button("e4").text == "♙" and button("e2").text == " ")
assert(button("e2").background == 3 and button("e4").background == 3) -- dernier coup surligné

-- réponse de l'ordinateur
chess:engineMoved("e7e5")
assert(#chess.game.moves == 2 and played == "e7e5")
chess:acceptPosition("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2", {"g1f3", "d2d4"}, false)
assert(chess.dialog.title == "Apprentissage · À vous de jouer · noirs : e7 → e5", chess.dialog.title)
assert(button("e7").background == 3 and button("e5").background == 3 and button("e2").background == 1)
assert(settings.data.game.keys[3] ~= nil)

-- un rendu identique ne reconstruit pas la boîte
local same = chess.dialog
chess:render()
assert(chess.dialog == same)

-- annulation : confirmation, puis deux demi-coups retirés et position redemandée au moteur
assert(chess:canUndo() and chess.dialog.buttons[10][1].enabled == true)
chess.dialog.buttons[10][1].callback()
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
chess:requestHint()
assert(hint_requests == 1 and chess.waiting and chess.hinting)
assert(chess.dialog.title == "Apprentissage · Je cherche un conseil…")
chess:showHint("g1f3")
assert(not chess.waiting and chess.selected == "g1" and chess.hint == "g1f3")
assert(button("f3").text == "★ " and button("g1").text == "•♘")
chess:tapSquare("f3")
assert(played == "g1f3" and chess.hint == nil)

-- nulle réclamable après le coup de l'enfant : l'ordinateur attend la décision
local searches = 0
chess.engine = {play = function() end, think = function() searches = searches + 1 end, hint = function() return true end}
local should_search = chess:acceptPosition("4k3/7p/8/8/8/8/P7/4K3 b - - 100 51", {"e8e7"}, false)
assert(should_search == false and chess.pending_draw_decision and searches == 0)
assert(chess.dialog.buttons[10][3].text == "Continuer" and chess.dialog.buttons[10][4].text == "Réclamer la nulle")
chess.dialog.buttons[10][4].callback() -- réclamer : confirmation d'abord
assert(shown[#shown].confirm and chess.pending_draw_decision)
chess:continueAfterClaim()
assert(searches == 1 and chess.waiting and not chess.pending_draw_decision)
chess:claimDraw()
assert(chess.game:result() == "nulle_reclamee" and not chess.waiting and chess.engine == nil)
assert(chess.dialog.title == "Apprentissage · Partie nulle")

-- mat donné par l'enfant : message de victoire, moteur arrêté, nouvelle partie sans confirmation
chess.engine = {play = function() end}
chess.game = Game.new(nil, "facile")
chess:acceptPosition("7k/6Q1/5K2/8/8/8/8/8 b - - 0 1", {}, true)
assert(chess.dialog.title == "Apprentissage · Échec et mat · tu as gagné !", chess.dialog.title)
assert(chess.engine == nil)
local before = started
chess:confirmNewGame() -- échiquier sans coup joué : pas de confirmation, choix du mode direct
assert(started == before and chess.mode_dialog and not shown[#shown].confirm)
assert(#chess.mode_dialog.buttons == 4 and chess.mode_dialog.buttons[2][1].text == "Partie · sans aide")
assert(chess.mode_dialog.buttons[3][1].text == "Deux joueurs · à tour de rôle sur l'écran")
chess.mode_dialog.buttons[2][1].callback()
assert(started == before + 1 and #chess.game.moves == 0 and chess.game.mode == "partie" and chess.mode_dialog == nil)
assert(settings.data.game.mode == "partie")

-- mode Partie : ni annulation ni indice, deuxième rangée réduite à la nulle
chess.game = Game.new({"e2e4", "e7e5"}, "facile", {mode = "partie"})
chess.engine = {play = function() end, hint = function() error("pas d'indice en mode Partie") end}
chess:acceptPosition("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2", {"g1f3"}, false)
assert(chess.dialog.title == "Partie · À vous de jouer · noirs : e7 → e5", chess.dialog.title)
assert(#chess.dialog.buttons[10] == 1 and chess.dialog.buttons[10][1].text == "Réclamer la nulle")
assert(not chess:canUndo())
chess:requestHint()
assert(not chess.hinting and not chess.waiting)
chess.dialog.buttons[9][1].callback() -- nouvelle partie : confirmation, puis choix du mode
assert(shown[#shown].confirm and shown[#shown].text:find("effacée", 1, true) and #chess.game.moves == 2)
shown[#shown].ok_callback()
assert(chess.mode_dialog and #chess.game.moves == 2)
before = started
chess.mode_dialog.buttons[1][1].callback() -- Apprentissage
assert(started == before + 1 and #chess.game.moves == 0 and chess.game.mode == "apprentissage")
chess.game = Game.new({"f2f3", "e7e5", "g2g4", "d8h4"}, "facile")
chess:acceptPosition("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3", {}, true)
chess.dialog.buttons[9][1].callback() -- partie finie mais coups joués : confirmation aussi
assert(shown[#shown].confirm and not shown[#shown].text:find("effacée", 1, true))
-- mode Deux joueurs : les deux couleurs jouent sur l'écran, le moteur ne cherche jamais
chess.game = Game.new(nil, "facile", {mode = "deux_joueurs"})
chess.engine = {play = function(_, moves) played = moves[#moves] end,
    think = function() error("pas de recherche à deux joueurs") end, hint = function() error("pas d'indice") end}
local should = chess:acceptPosition(start, {"e2e4"}, false)
assert(should == false and not chess.waiting)
assert(chess.dialog.title == "Deux joueurs · Aux blancs de jouer", chess.dialog.title)
assert(#chess.dialog.buttons[9] == 2 and chess.dialog.buttons[9][2].text == "Fermer") -- pas de niveau
assert(#chess.dialog.buttons[10] == 2 and chess.dialog.buttons[10][1].text == "Annuler le coup")
assert(chess.dialog.buttons[10][1].enabled == false and chess.dialog.buttons[10][2].text == "Réclamer la nulle")
chess:tapSquare("e7") -- pièce noire alors que c'est aux blancs
assert(chess.selected == nil)
chess:tapSquare("e2"); chess:tapSquare("e4")
assert(played == "e2e4" and chess.waiting)
should = chess:acceptPosition("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", {"e7e5", "e7e6"}, false)
assert(should == false and not chess.waiting and not chess.pending_draw_decision)
assert(chess.dialog.title == "Deux joueurs · Aux noirs de jouer · dernier coup : e2 → e4", chess.dialog.title)
chess:tapSquare("e2") -- pièce blanche alors que c'est aux noirs
assert(chess.selected == nil)
chess:tapSquare("e7")
assert(chess.selected == "e7" and button("e7").text == "•♟" and button("e5").text == "○ " and button("e6").text == "○ ")
chess:tapSquare("e5")
assert(played == "e7e5")
chess:acceptPosition("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2", {"g1f3"}, false)
assert(chess:canUndo() and chess.dialog.buttons[10][1].enabled == true)
chess.dialog.buttons[10][1].callback()
assert(shown[#shown].confirm and shown[#shown].text == "Annuler le dernier coup ?")
shown[#shown].ok_callback()
assert(#chess.game.moves == 1 and chess.game.moves[1] == "e2e4" and chess.waiting) -- un seul demi-coup retiré
chess.game = Game.new({"f2f3", "e7e5", "g2g4", "d8h4"}, "facile", {mode = "deux_joueurs"})
chess:acceptPosition("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3", {}, true)
assert(chess.dialog.title == "Deux joueurs · Échec et mat · les noirs gagnent", chess.dialog.title)
assert(chess.engine == nil)

chess.game = Game.new(nil, "facile")
chess:acceptPosition("7k/5K2/8/8/8/8/8/7Q w - - 0 1", {}, true)
assert(chess.dialog.title == "Apprentissage · Échec et mat · l'ordinateur a gagné", chess.dialog.title)

-- choix du niveau
chess:chooseLevel()
assert(chess.level_dialog and #chess.level_dialog.buttons == 6)
assert(chess.level_dialog.buttons[3][1].text == "✓ Facile", chess.level_dialog.buttons[3][1].text)
assert(chess.level_dialog.buttons[1][1].text == "Découverte · joue souvent au hasard")
chess:setLevel("difficile")
assert(chess.game.level == "difficile" and chess.level_dialog == nil)
assert(settings.data.game.level == "difficile")
assert(chess.dialog.buttons[9][2].text == "Difficile")

-- garde-fou : moteur muet pendant plus de 20 s
chess.engine = {play = function() end}
chess.transport = {poll = function() return {} end, close = function() end}
chess:setWaiting(true)
clock = 21
chess:poll()
assert(chess.engine == nil and not chess.waiting and shown[#shown].info)

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
chess.dialog.buttons[9][3].callback() -- Fermer : confirmation
assert(shown[#shown].confirm and chess.opened)
shown[#shown].ok_callback()
assert(not chess.opened and chess.dialog == nil)
print("ui: OK")
