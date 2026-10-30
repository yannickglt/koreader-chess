local Blitbuffer = require("ffi/blitbuffer")
local Board = require("board")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Engine = require("engine")
local Game = require("game")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local Size = require("ui/size")
local Transport = require("transport")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local time = require("ui/time")
local Screen = Device.screen

-- `random` : probabilité qu'un coup de l'ordinateur soit tiré au hasard parmi les coups légaux.
-- `skill` : Skill Level Stockfish (0 = le plus faible). `movetime` en millisecondes.
local levels = {
    {id = "decouverte", name = "Découverte", blurb = "joue souvent au hasard", skill = 0, movetime = 100, random = 0.6},
    {id = "initiation", name = "Initiation", blurb = "se trompe parfois", skill = 0, movetime = 150, random = 0.3},
    {id = "facile", name = "Facile", skill = 3, movetime = 250},
    {id = "intermediaire", name = "Intermédiaire", skill = 8, movetime = 350},
    {id = "difficile", name = "Difficile", skill = 15, movetime = 500},
}
local HINT_MOVETIME = 300
local POLL_INTERVAL = 0.05
local ENGINE_TIMEOUT = 20 -- secondes sans réponse du moteur avant de l'arrêter

local function level_for(id)
    for _, level in ipairs(levels) do
        if level.id == id then return level end
    end
    return levels[1]
end

local Chess = WidgetContainer:extend{name = "chess", is_doc_only = false}

function Chess:init()
    math.randomseed(os.time())
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/chess.lua")
    local saved = self.settings:readSetting("game") or {}
    self.game = Game.new(saved.moves, level_for(saved.level).id, {keys = saved.keys, mode = saved.mode})
    if #self.game.moves > 0 and saved.claimed_draw then self.game.claimed_draw = true end
    self.ui.menu:registerToMainMenu(self)
end

function Chess:addToMainMenu(menu_items)
    menu_items.chess = {
        text = "Échecs",
        sorting_hint = "more_tools",
        callback = function() self:openBoard() end,
    }
end

function Chess:level()
    return level_for(self.game.level)
end

-- Mode choisi à la création de la partie : seul le mode Apprentissage offre l'indice ; à deux
-- joueurs, les deux couleurs se jouent sur l'écran et Stockfish ne sert qu'aux règles.
local mode_names = {apprentissage = "Apprentissage", partie = "Partie", deux_joueurs = "Deux joueurs"}

function Chess:learning()
    return self.game.mode == "apprentissage"
end

function Chess:twoPlayers()
    return self.game.mode == "deux_joueurs"
end

function Chess:save()
    self.settings:saveSetting("game", {
        moves = self.game.moves,
        level = self.game.level,
        mode = self.game.mode,
        keys = self.game.keys,
        claimed_draw = self.game.claimed_draw,
    })
    self.settings:flush()
end

-- Moteur -------------------------------------------------------------------

function Chess:schedulePoll()
    UIManager:unschedule(Chess.poll)
    UIManager:scheduleIn(POLL_INTERVAL, Chess.poll, self)
end

function Chess:setWaiting(waiting)
    self.waiting = waiting
    self.wait_started = waiting and time.now() or nil
    if waiting then self:schedulePoll() end
end

function Chess:stopEngine()
    UIManager:unschedule(Chess.poll)
    if self.transport then self.transport:close(); self.transport = nil end
    self.engine = nil
    self.hinting = false
end

function Chess:startEngine()
    self:stopEngine()
    local path = ffiUtil.realpath(self.path .. "/bin/stockfish")
    if not path or not ffiUtil.isExecutable(path) then
        UIManager:show(InfoMessage:new{text = "Stockfish absent ou non exécutable dans chess.koplugin/bin/."})
        return false
    end
    local transport, err = Transport.new(path)
    if not transport then
        UIManager:show(InfoMessage:new{text = "Impossible de lancer Stockfish : " .. err})
        return false
    end
    self.transport = transport
    self.engine = Engine.new(transport,
        function(fen, legal, in_check) return self:acceptPosition(fen, legal, in_check) end,
        function(move) self:engineMoved(move) end,
        function(move) self:showHint(move) end)
    self.engine.clock = time.now
    self.engine:start(self:level(), self.game.moves)
    self:setWaiting(true)
    return true
end

function Chess:engineMoved(move)
    local engine = self.engine
    if not engine then return end
    logger.info(string.format("chess: coup de l'ordinateur %s (%s, %d ms)", move, engine.last_choice or "?",
        time.to_ms(engine.search_time or 0)))
    self.game:append(move)
    self:save()
    engine:play(self.game.moves)
end

function Chess:acceptPosition(fen, legal, in_check)
    local ok, update_err = self.game:update(fen, legal, in_check)
    if not ok then
        self:stopEngine()
        self.waiting = false
        UIManager:show(InfoMessage:new{text = update_err})
        return false
    end
    if self.engine and self.engine.ready_time and not self.engine.ready_logged then
        self.engine.ready_logged = true
        logger.info(string.format("chess: moteur prêt en %d ms", time.to_ms(self.engine.ready_time)))
    end
    local result = self.game:result()
    local computer_turn = self.game.turn == "b" and not self:twoPlayers()
    self.pending_draw_decision = not result and computer_turn and self.game:can_claim_draw()
    local waiting = not result and computer_turn and not self.pending_draw_decision
    if waiting then self:setWaiting(true) else self.waiting, self.wait_started = false, nil end
    self.selected, self.destinations, self.hint = nil, nil, nil
    self:save()
    self:render()
    if result then self:stopEngine() end
    return waiting
end

function Chess:poll()
    if not self.opened or not self.transport then return end
    local lines = self.transport:poll()
    for _, line in ipairs(lines) do
        if self.engine then self.engine:line(line) end
    end
    if self.transport and self.transport.error then
        local err = self.transport.error
        self:stopEngine()
        self.waiting = false
        UIManager:show(InfoMessage:new{text = err})
        self:render()
        return
    end
    if not self.waiting then return end
    if self.wait_started and time.since(self.wait_started) > time.s(ENGINE_TIMEOUT) then
        logger.warn("chess: Stockfish ne répond pas, arrêt du moteur")
        self:stopEngine()
        self.waiting = false
        UIManager:show(InfoMessage:new{text = "Stockfish ne répond pas. Touchez l'échiquier pour le relancer."})
        self:render()
        return
    end
    UIManager:scheduleIn(POLL_INTERVAL, Chess.poll, self)
end

-- Plateau ------------------------------------------------------------------

function Chess:openBoard()
    if self.opened then return end
    self.opened = true
    self.waiting = true
    self:render()
    self:startEngine()
end

function Chess:closeDialogs()
    for _, name in ipairs({"dialog", "promotion_dialog", "level_dialog", "mode_dialog"}) do
        if self[name] then UIManager:close(self[name]); self[name] = nil end
    end
end

function Chess:closeBoard()
    self.opened = false
    self:stopEngine()
    self:closeDialogs()
    self.render_signature = nil
    self:save()
end

local result_text = {
    pat = "Pat · partie nulle", materiel = "Matériel insuffisant · partie nulle",
    repetition = "Cinq répétitions · partie nulle", ["75_coups"] = "75 coups · partie nulle",
    nulle_reclamee = "Partie nulle",
}

function Chess:statusText()
    local result = self.game:result()
    local two = self:twoPlayers()
    if result == "mat" then
        if two then
            return self.game.turn == "b" and "Échec et mat · les blancs gagnent" or "Échec et mat · les noirs gagnent"
        end
        return self.game.turn == "b" and "Échec et mat · tu as gagné !" or "Échec et mat · l'ordinateur a gagné"
    elseif result then
        return result_text[result]
    elseif self.pending_draw_decision then
        return "Nulle possible · choisir"
    elseif self.hinting then
        return "Je cherche un conseil…"
    elseif self.waiting then
        return (not two and self.game.fen and self.game.turn == "b") and "L'ordinateur réfléchit…" or "Un instant…"
    end
    local text
    if two then
        text = self.game.turn == "w" and "Aux blancs de jouer" or "Aux noirs de jouer"
    else
        text = "À vous de jouer"
    end
    if self.game.in_check then text = "Échec ! " .. text end
    local from, to = self.game:last_move()
    if from and two then
        text = text .. " · dernier coup : " .. from .. " → " .. to
    elseif from and self.game.turn == "w" then
        text = text .. " · noirs : " .. from .. " → " .. to
    end
    return text
end

-- Cases carrées : la largeur de la boîte est déduite de la taille de case, elle-même bornée
-- par la largeur et par la hauteur de l'écran (titre et deux rangées de boutons réservés).
function Chess:geometry()
    local sep = Size.line.medium
    local chrome = 2 * (Size.border.window + Size.padding.button)
    local limit = math.min(math.floor(Screen:getWidth() * 0.96), Screen:getHeight() - Screen:scaleBySize(140))
    local square = math.floor((limit - chrome - 7 * sep) / 8)
    local scale = Screen:scaleBySize(100) / 100
    return {
        square = square,
        width = 8 * square + 7 * sep + chrome,
        button_height = square - 2 * Size.padding.buttontable,
        font_size = math.floor(square * 0.57 / scale),
    }
end

function Chess:label(square)
    local piece = Board.piece(self.game.board[square])
    if self.selected == square then return "•" .. piece end
    if self.hint and self.selected == self.hint:sub(1, 2) and self.hint:sub(3, 4) == square then return "★" .. piece end
    if self.destinations and self.destinations[square] then
        return (self.game.board[square] and "×" or "○") .. piece
    end
    return piece
end

function Chess:humanTurn()
    return self.game.fen ~= nil and not self.waiting and not self.pending_draw_decision
        and (self.game.turn == "w" or self:twoPlayers()) and not self.game:result()
end

-- Contre l'ordinateur, annuler retire la paire de demi-coups ; à deux joueurs, le dernier seulement.
function Chess:undoCount()
    return self:twoPlayers() and 1 or 2
end

function Chess:canUndo()
    if self.game.fen == nil or self.waiting or self.pending_draw_decision then return false end
    if self:twoPlayers() then return #self.game.moves >= 1 end
    return self:learning() and self.game.turn == "w" and #self.game.moves >= 2
end

function Chess:render()
    if not self.opened then return end
    local status = self:statusText()
    local human_turn = self:humanTurn()
    local can_undo = self:canUndo()
    local can_claim = human_turn and self.game:can_claim_draw()
    local last_from, last_to = self.game:last_move()
    -- La boîte n'est reconstruite (rafraîchissement complet sur E Ink) que si ce qui s'affiche change.
    local labels = {}
    for row = 1, 8 do
        for column = 1, 8 do labels[#labels + 1] = self:label(Board.square(row, column)) end
    end
    local signature = table.concat({table.concat(labels), last_from or "", last_to or "", status,
        tostring(self.game.level), tostring(self.game.mode), tostring(human_turn), tostring(can_undo),
        tostring(can_claim), tostring(self.pending_draw_decision)}, "|")
    if self.dialog and self.render_signature == signature then return end
    local geometry = self:geometry()
    local buttons = {}
    for row = 1, 8 do
        buttons[row] = {}
        for column = 1, 8 do
            local square = Board.square(row, column)
            local background
            if square == last_from or square == last_to then
                background = Blitbuffer.COLOR_GRAY_9
            else
                background = (row + column) % 2 == 0 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_LIGHT_GRAY
            end
            buttons[row][column] = {
                id = square,
                text = labels[(row - 1) * 8 + column],
                background = background,
                font_size = geometry.font_size,
                width = geometry.square,
                height = geometry.button_height,
                callback = function() self:tapSquare(square) end,
            }
        end
    end
    buttons[9] = {{text = "Nouvelle partie", callback = function() self:confirmNewGame() end}}
    if not self:twoPlayers() then
        buttons[9][2] = {text = self:level().name, callback = function() self:chooseLevel() end}
    end
    buttons[9][#buttons[9] + 1] = {text = "Fermer", callback = function() self:confirmClose() end}
    local row = {}
    if self:learning() or self:twoPlayers() then
        row[1] = {text = "Annuler le coup", enabled = can_undo, callback = function() self:confirmUndo() end}
    end
    if self:learning() then
        row[#row + 1] = {text = "Indice", enabled = human_turn, callback = function() self:requestHint() end}
    end
    if self.pending_draw_decision then
        row[#row + 1] = {text = "Continuer", callback = function() self:continueAfterClaim() end}
        row[#row + 1] = {text = "Réclamer la nulle", callback = function() self:confirmClaimDraw() end}
    else
        row[#row + 1] = {text = "Réclamer la nulle", enabled = can_claim, callback = function() self:confirmClaimDraw() end}
    end
    buttons[10] = row
    local new_dialog = ButtonDialog:new{
        title = (mode_names[self.game.mode] or "Échecs") .. " · " .. status,
        buttons = buttons, dismissable = false, width = geometry.width,
    }
    if self.dialog then UIManager:close(self.dialog) end
    self.dialog = new_dialog
    self.render_signature = signature
    UIManager:show(new_dialog)
end

-- Confirmations ------------------------------------------------------------------

-- Les boutons qui font perdre quelque chose (partie en cours, dernier coup, fin de partie)
-- ou qui quittent le jeu demandent une confirmation « Oui / Non », lisible par un enfant.
function Chess:confirm(text, callback)
    UIManager:show(ConfirmBox:new{
        text = text, ok_text = "Oui", cancel_text = "Non",
        ok_callback = callback,
    })
end

function Chess:confirmClose()
    self:confirm("Fermer le jeu d'échecs ? La partie est gardée pour la prochaine fois.", function() self:closeBoard() end)
end

function Chess:confirmUndo()
    if not self:canUndo() then return end
    local text = self:twoPlayers() and "Annuler le dernier coup ?" or "Annuler ton dernier coup et la réponse de l'ordinateur ?"
    self:confirm(text, function() self:undo() end)
end

function Chess:confirmClaimDraw()
    if not self.game:can_claim_draw() or self.game:result() then return end
    self:confirm("Réclamer la nulle ? La partie s'arrête sans gagnant.", function() self:claimDraw() end)
end

-- Interactions ----------------------------------------------------------------

function Chess:setSelection(square)
    local touched = {}
    if self.selected then touched[self.selected] = true end
    for destination in pairs(self.destinations or {}) do touched[destination] = true end
    self.selected = square
    self.destinations = square and self.game:destinations(square) or nil
    if square then touched[square] = true end
    for destination in pairs(self.destinations or {}) do touched[destination] = true end
    if not self.dialog then return end
    for current in pairs(touched) do
        local button = self.dialog.buttontable:getButtonById(current)
        if button then
            button:setText(self:label(current), button.width)
            button:refresh()
        end
    end
end

function Chess:tapSquare(square)
    if not self:humanTurn() then return end
    if not self.engine then self:startEngine(); return end
    local piece = self.game.board[square]
    local own = piece ~= nil and piece:match(self.game.turn == "w" and "%u" or "%l") ~= nil
    if not self.selected then
        if own then self:setSelection(square) end
        return
    end
    local from = self.selected
    if from == square then self:setSelection(nil); return end
    local move = self.game:move_for(from, square)
    if move then
        self:setSelection(nil)
        self:makeMove(move)
        return
    end
    local promotions = self.game:promotions(from, square)
    if #promotions > 0 then
        self:setSelection(nil)
        local choices = {}
        local names = {q = "Dame", r = "Tour", b = "Fou", n = "Cavalier"}
        for _, promotion in ipairs(promotions) do
            local chosen = promotion
            choices[#choices + 1] = {{text = names[chosen:sub(5)], callback = function()
                UIManager:close(self.promotion_dialog)
                self.promotion_dialog = nil
                self:makeMove(chosen)
            end}}
        end
        self.promotion_dialog = ButtonDialog:new{title = "Promotion", buttons = choices, dismissable = false}
        UIManager:show(self.promotion_dialog)
        return
    end
    self:setSelection(own and square or nil)
end

-- Pas de rendu ici : la position confirmée par le moteur arrive au prochain sondage et
-- déclenche un seul rafraîchissement avec la pièce déplacée et le statut.
function Chess:makeMove(move)
    self.game:append(move)
    self.hint = nil
    self:save()
    self:setWaiting(true)
    self.engine:play(self.game.moves)
end

function Chess:undo()
    if not self:canUndo() then return end
    self.game:undo(self:undoCount())
    self.selected, self.destinations, self.hint = nil, nil, nil
    self.pending_draw_decision = false
    self:save()
    self:setWaiting(true)
    if self.engine then self.engine:play(self.game.moves) else self:startEngine() end
end

function Chess:requestHint()
    if not self:learning() or not self:humanTurn() or self.hinting then return end
    if not self.engine then self:startEngine(); return end
    self:setSelection(nil)
    self.hint = nil
    self.hinting = true
    self:setWaiting(true)
    self:render()
    if not self.engine:hint() then
        self.hinting, self.waiting, self.wait_started = false, false, nil
        self:render()
    end
end

function Chess:showHint(move)
    if self.engine then
        logger.info(string.format("chess: conseil %s (%d ms)", move, time.to_ms(self.engine.search_time or 0)))
    end
    self.hinting = false
    self.waiting, self.wait_started = false, nil
    self.hint = move
    self.selected = move:sub(1, 2)
    self.destinations = self.game:destinations(self.selected)
    self:render()
end

function Chess:claimDraw()
    if not self.game:can_claim_draw() or self.game:result() then return end
    self.game.claimed_draw = true
    self.pending_draw_decision = false
    self.waiting, self.wait_started = false, nil
    self:stopEngine()
    self:save()
    self:render()
end

function Chess:continueAfterClaim()
    if not self.pending_draw_decision then return end
    if not self.engine then self:startEngine(); return end
    self.pending_draw_decision = false
    self:setWaiting(true)
    self:render()
    self.engine:think()
end

function Chess:newGame(mode)
    self:closeModeDialog()
    self.game = Game.new(nil, self.game.level, {mode = mode})
    self.selected, self.destinations, self.hint = nil, nil, nil
    self.pending_draw_decision = false
    self:save()
    self:startEngine()
    self:render()
end

-- Une nouvelle partie commence par le choix du mode ; la confirmation ne s'affiche que si des
-- coups ont été joués.
function Chess:chooseMode()
    if self.mode_dialog then return end
    self.mode_dialog = ButtonDialog:new{
        title = "Nouvelle partie",
        buttons = {
            {{text = "Apprentissage · indices et retour en arrière", callback = function() self:newGame("apprentissage") end}},
            {{text = "Partie · sans aide", callback = function() self:newGame("partie") end}},
            {{text = "Deux joueurs · à tour de rôle sur l'écran", callback = function() self:newGame("deux_joueurs") end}},
            {{text = "Retour", callback = function() self:closeModeDialog() end}},
        },
        tap_close_callback = function() self.mode_dialog = nil end,
    }
    UIManager:show(self.mode_dialog)
end

function Chess:closeModeDialog()
    if self.mode_dialog then UIManager:close(self.mode_dialog); self.mode_dialog = nil end
end

function Chess:confirmNewGame()
    if #self.game.moves == 0 then self:chooseMode(); return end
    local text = self.game:result() and "Commencer une nouvelle partie ?"
        or "Commencer une nouvelle partie ? La partie en cours sera effacée."
    self:confirm(text, function() self:chooseMode() end)
end

function Chess:chooseLevel()
    if self.level_dialog then return end
    local buttons = {}
    for _, level in ipairs(levels) do
        local text = level.name .. (level.blurb and (" · " .. level.blurb) or "")
        if level.id == self.game.level then text = "✓ " .. text end
        local id = level.id
        buttons[#buttons + 1] = {{text = text, callback = function() self:setLevel(id) end}}
    end
    buttons[#buttons + 1] = {{text = "Retour", callback = function() self:closeLevelDialog() end}}
    self.level_dialog = ButtonDialog:new{
        title = "Niveau de l'ordinateur", buttons = buttons,
        tap_close_callback = function() self.level_dialog = nil end,
    }
    UIManager:show(self.level_dialog)
end

function Chess:closeLevelDialog()
    if self.level_dialog then UIManager:close(self.level_dialog); self.level_dialog = nil end
end

function Chess:setLevel(id)
    self:closeLevelDialog()
    if id == self.game.level then return end
    self.game.level = id
    self:save()
    self:render()
    if self.engine and not self.game:result() then self:startEngine() end
end

-- Veille et fermeture ----------------------------------------------------------

function Chess:onSuspend()
    if self.opened then
        self:stopEngine()
        self.waiting = not self.game:result()
        self.wait_started = nil
        self:save()
    end
end

function Chess:onResume()
    if self.opened and not self.game:result() then self:startEngine() end
end

function Chess:onCloseWidget()
    self:closeBoard()
end

return Chess
