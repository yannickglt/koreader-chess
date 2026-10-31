-- SPDX-License-Identifier: GPL-3.0-or-later
local Board = require("board")
local BoardWidget = require("boardwidget")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Engine = require("engine")
local Game = require("game")
local I18n = require("i18n")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local Transport = require("transport")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local time = require("ui/time")
local T = I18n.translate

-- `random` : probabilité qu'un coup de l'ordinateur soit tiré au hasard parmi les coups légaux.
-- `skill` : Skill Level Stockfish (0 = le plus faible). `movetime` en millisecondes.
-- Les noms et descriptions sont les chaînes anglaises traduites à l'affichage.
local levels = {
    {id = "decouverte", name = "Discovery", blurb = "often plays at random", skill = 0, movetime = 100, random = 0.6},
    {id = "initiation", name = "Beginner", blurb = "sometimes slips", skill = 0, movetime = 150, random = 0.3},
    {id = "facile", name = "Easy", skill = 3, movetime = 250},
    {id = "intermediaire", name = "Intermediate", skill = 8, movetime = 350},
    {id = "difficile", name = "Hard", skill = 15, movetime = 500},
}
local POLL_INTERVAL = 0.05
local ENGINE_TIMEOUT = 20 -- secondes sans réponse du moteur avant de l'arrêter
local COMPUTER_PAUSE = 0.8 -- secondes entre la pièce encadrée par l'ordinateur et son déplacement

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
    I18n.set(self.settings:readSetting("language") or "en")
    local saved = self.settings:readSetting("game") or {}
    self.game = Game.new(saved.moves, level_for(saved.level).id, {keys = saved.keys, mode = saved.mode, color = saved.color})
    if #self.game.moves > 0 and saved.claimed_draw then self.game.claimed_draw = true end
    self.ui.menu:registerToMainMenu(self)
end

function Chess:addToMainMenu(menu_items)
    menu_items.chess = {
        text = T("Chess"),
        sorting_hint = "more_tools",
        callback = function() self:openBoard() end,
    }
end

function Chess:level()
    return level_for(self.game.level)
end

-- Mode choisi à la création de la partie : seul le mode Apprentissage offre l'indice ; à deux
-- joueurs, les deux couleurs se jouent sur l'écran et Stockfish ne sert qu'aux règles.
local mode_names = {apprentissage = "Learning", partie = "Game", deux_joueurs = "Two players"}

function Chess:learning()
    return self.game.mode == "apprentissage"
end

function Chess:twoPlayers()
    return self.game.mode == "deux_joueurs"
end

-- Contre l'ordinateur, l'enfant choisit sa couleur à la création de la partie ; l'échiquier est
-- retourné quand il joue les noirs.
function Chess:computerTurn()
    return not self:twoPlayers() and self.game.turn ~= self.game.color
end

function Chess:flipped()
    return not self:twoPlayers() and self.game.color == "b"
end

function Chess:showCoords()
    return self.settings:nilOrTrue("coords")
end

function Chess:save()
    self.settings:saveSetting("game", {
        moves = self.game.moves,
        level = self.game.level,
        mode = self.game.mode,
        color = self.game.color,
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
    UIManager:unschedule(Chess.applyPendingMove)
    self.pending_move = nil
    if self.transport then self.transport:close(); self.transport = nil end
    self.engine = nil
    self.hinting = false
end

function Chess:startEngine()
    self:stopEngine()
    local path = ffiUtil.realpath(self.path .. "/bin/stockfish")
    if not path or not ffiUtil.isExecutable(path) then
        UIManager:show(InfoMessage:new{text = T("Stockfish is missing or not executable in chess.koplugin/bin/.")})
        return false
    end
    local transport, err = Transport.new(path)
    if not transport then
        UIManager:show(InfoMessage:new{text = T("Could not start Stockfish: %s"):format(err)})
        return false
    end
    self.transport = transport
    -- Une partie reprise d'une sauvegarde est contrôlée à la première position reçue.
    self.validate_save = #self.game.moves > 0
    self.engine = Engine.new(transport,
        function(fen, legal, in_check) return self:acceptPosition(fen, legal, in_check) end,
        function(move) self:engineMoved(move) end,
        function(move) self:showHint(move) end)
    self.engine.clock = time.now
    self.engine:start(self:level(), self.game.moves)
    self:setWaiting(true)
    return true
end

-- La pièce choisie par l'ordinateur est d'abord encadrée, puis déplacée après une courte pause :
-- l'enfant voit ce qui est joué au lieu de découvrir une pièce déjà déplacée.
function Chess:engineMoved(move)
    local engine = self.engine
    if not engine then return end
    logger.info(string.format("chess: coup de l'ordinateur %s (%s, %d ms)", move, engine.last_choice or "?",
        time.to_ms(engine.search_time or 0)))
    self.pending_move = move
    self:render()
    UIManager:scheduleIn(COMPUTER_PAUSE, Chess.applyPendingMove, self)
end

function Chess:applyPendingMove()
    local move = self.pending_move
    self.pending_move = nil
    if not move or not self.opened or not self.engine then return end
    self.game:append(move)
    self:save()
    self.engine:play(self.game.moves)
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
    if self.validate_save then
        self.validate_save = false
        if not self.game:consistent() then
            -- Stockfish ignore en silence un coup illégal : la liste sauvegardée ne décrit plus la position.
            logger.warn("chess: sauvegarde incohérente, nouvelle partie")
            self.game = Game.new(nil, self.game.level, {mode = self.game.mode, color = self.game.color})
            self.selected, self.destinations, self.hint, self.pending_draw_decision = nil, nil, nil, false
            self:save()
            UIManager:show(InfoMessage:new{text = T("The saved game is unreadable: starting a new game.")})
            if self.engine then self.engine:play(self.game.moves) end
            return false
        end
    end
    local result = self.game:result()
    local computer_turn = self:computerTurn()
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
        UIManager:show(InfoMessage:new{text = T("Stockfish is not responding. Tap the board to restart it.")})
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
    self.board_widget = BoardWidget:new{
        view = self:view(),
        on_square = function(square) self:tapSquare(square) end,
        on_button = function(id) self:onButton(id) end,
        on_close = function() self:confirmClose() end,
    }
    UIManager:show(self.board_widget)
    self:startEngine()
end

function Chess:closeDialogs()
    for _, name in ipairs({"board_widget", "promotion_dialog", "settings_dialog", "mode_dialog", "color_dialog"}) do
        if self[name] then UIManager:close(self[name]); self[name] = nil end
    end
end

function Chess:closeBoard()
    self.opened = false
    self:stopEngine()
    self:closeDialogs()
    self:save()
end

local result_text = {
    pat = "Stalemate · draw", materiel = "Insufficient material · draw",
    repetition = "Fivefold repetition · draw", ["75_coups"] = "75-move rule · draw",
    nulle_reclamee = "Draw",
}

-- Première ligne de l'en-tête : à qui de jouer, ou ce que fait l'ordinateur.
function Chess:statusText()
    local result = self.game:result()
    local two = self:twoPlayers()
    if result == "mat" then
        if two then
            return self.game.turn == "b" and T("Checkmate · White wins") or T("Checkmate · Black wins")
        end
        return self.game.turn ~= self.game.color and T("Checkmate · you win!") or T("Checkmate · the computer wins")
    elseif result then
        return T(result_text[result])
    elseif self.pending_draw_decision then
        return T("Draw available · choose")
    elseif self.hinting then
        return T("Looking for a hint…")
    elseif self.waiting then
        return (self.game.fen and self:computerTurn()) and T("The computer is thinking…") or T("One moment…")
    elseif not self.engine then
        return T("Engine stopped · tap the board")
    end
    local text
    if two then
        text = self.game.turn == "w" and T("White to move") or T("Black to move")
    else
        text = T("Your move")
    end
    if self.game.in_check then text = T("Check! %s"):format(text) end
    return text
end

local piece_names = {q = "queen", r = "rook", b = "bishop", n = "knight"}

-- « E2 → E4 », « E7 → E8 (queen) » : cases en majuscules, comme les repères de l'échiquier.
local function describe(move)
    local text = move:sub(1, 2):upper() .. " → " .. move:sub(3, 4):upper()
    local promotion = move:sub(5, 5)
    if promotion ~= "" then text = text .. " (" .. T(piece_names[promotion]) .. ")" end
    return text
end

-- Seconde ligne : mode, niveau, dernier coup joué.
function Chess:detailText()
    local parts = {T(mode_names[self.game.mode] or "Chess")}
    if not self:twoPlayers() then parts[#parts + 1] = T(self:level().name) end
    local move = self.game.moves[#self.game.moves]
    if move then
        parts[#parts + 1] = T(#self.game.moves % 2 == 1 and "White: %s" or "Black: %s"):format(describe(move))
    end
    return table.concat(parts, " · ")
end

-- Prise, y compris en passant : la case d'arrivée est vide mais le pion change de colonne.
function Chess:capture(square)
    if self.game.board[square] ~= nil then return true end
    local mover = self.selected and self.game.board[self.selected]
    return mover ~= nil and mover:lower() == "p" and square:sub(1, 1) ~= self.selected:sub(1, 1)
end

function Chess:humanTurn()
    return self.game.fen ~= nil and not self.waiting and not self.pending_draw_decision
        and (self.game.turn == self.game.color or self:twoPlayers()) and not self.game:result()
end

-- Contre l'ordinateur, annuler retire la paire de demi-coups ; à deux joueurs, le dernier seulement.
function Chess:undoCount()
    return self:twoPlayers() and 1 or 2
end

function Chess:canUndo()
    if self.game.fen == nil or self.waiting or self.pending_draw_decision then return false end
    if self:twoPlayers() then return #self.game.moves >= 1 end
    return self:learning() and self.game.turn == self.game.color and #self.game.moves >= 2
end

-- État affiché par BoardWidget : en-tête, cases (pièce, marqueur, dernier coup), boutons.
function Chess:view()
    local game = self.game
    local human_turn = self:humanTurn()
    local can_undo = self:canUndo()
    local can_claim = human_turn and game:can_claim_draw()
    local last_from, last_to = game:last_move()
    local hint_to = self.hint and self.selected == self.hint:sub(1, 2) and self.hint:sub(3, 4) or nil
    local pending_from = self.pending_move and self.pending_move:sub(1, 2)
    local squares = {}
    for row = 1, 8 do
        for column = 1, 8 do
            local square = Board.square(row, column)
            local cell = {piece = game.board[square]}
            if self.selected == square or pending_from == square then
                cell.mark = "selected"
            elseif self.destinations and self.destinations[square] then
                cell.mark = self:capture(square) and "ring" or "dot"
            end
            if hint_to == square then cell.star = true end
            if square == last_from or square == last_to then cell.last = true end
            squares[square] = cell
        end
    end
    local rows = {{{id = "new", text = T("New game")}, {id = "settings", text = T("Settings")}, {id = "close", text = T("Close")}}, {}}
    local row = rows[2]
    if self:learning() or self:twoPlayers() then
        row[#row + 1] = {id = "undo", text = T("Undo move"), enabled = can_undo}
    end
    if self:learning() then
        row[#row + 1] = {id = "hint", text = T("Hint"), enabled = human_turn}
    end
    if self.pending_draw_decision then
        row[#row + 1] = {id = "continue", text = T("Continue")}
        row[#row + 1] = {id = "claim", text = T("Claim a draw")}
    else
        row[#row + 1] = {id = "claim", text = T("Claim a draw"), enabled = can_claim}
    end
    return {
        status = self:statusText(), detail = self:detailText(),
        flipped = self:flipped(), coords = self:showCoords(),
        squares = squares, buttons = rows,
    }
end

function Chess:render()
    if not self.opened or not self.board_widget then return end
    self.board_widget:setView(self:view())
end

local actions = {
    new = "confirmNewGame", settings = "openSettings", close = "confirmClose",
    undo = "confirmUndo", hint = "requestHint", continue = "continueAfterClaim", claim = "confirmClaimDraw",
}

function Chess:onButton(id)
    local action = actions[id]
    if action then self[action](self) end
end

-- Confirmations ------------------------------------------------------------------

-- Les boutons qui font perdre quelque chose (partie en cours, dernier coup, fin de partie)
-- ou qui quittent le jeu demandent une confirmation « Oui / Non », lisible par un enfant.
function Chess:confirm(text, callback)
    UIManager:show(ConfirmBox:new{
        text = text, ok_text = T("Yes"), cancel_text = T("No"),
        ok_callback = callback,
    })
end

function Chess:confirmClose()
    self:confirm(T("Close the chess game? The game is kept for next time."), function() self:closeBoard() end)
end

function Chess:confirmUndo()
    if not self:canUndo() then return end
    local text = self:twoPlayers() and T("Undo the last move?") or T("Undo your last move and the computer's reply?")
    self:confirm(text, function() self:undo() end)
end

function Chess:confirmClaimDraw()
    if not self.game:can_claim_draw() or self.game:result() then return end
    self:confirm(T("Claim a draw? The game ends without a winner."), function() self:claimDraw() end)
end

-- Interactions ----------------------------------------------------------------

function Chess:setSelection(square)
    self.selected = square
    self.destinations = square and self.game:destinations(square) or nil
    self:render()
end

function Chess:tapSquare(square)
    -- Moteur arrêté (délai dépassé, échec de lancement) : un toucher le relance, quel que soit le trait.
    if not self.engine and not self.game:result() then self:startEngine(); return end
    if not self:humanTurn() then return end
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
        self.selected, self.destinations = nil, nil
        self:makeMove(move)
        return
    end
    local promotions = self.game:promotions(from, square)
    if #promotions > 0 then
        self:setSelection(nil)
        local choices = {}
        local names = {q = "Queen", r = "Rook", b = "Bishop", n = "Knight"}
        for _, promotion in ipairs(promotions) do
            local chosen = promotion
            choices[#choices + 1] = {{text = T(names[chosen:sub(5)]), callback = function()
                UIManager:close(self.promotion_dialog)
                self.promotion_dialog = nil
                self:makeMove(chosen)
            end}}
        end
        self.promotion_dialog = ButtonDialog:new{title = T("Promotion"), buttons = choices, dismissable = false}
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
    self.selected, self.destinations, self.hint = nil, nil, nil
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

function Chess:newGame(mode, color)
    self:closeModeDialog()
    self:closeColorDialog()
    self.game = Game.new(nil, self.game.level, {mode = mode, color = color})
    self.selected, self.destinations, self.hint = nil, nil, nil
    self.pending_draw_decision = false
    self:save()
    self:startEngine()
    self:render()
end

-- Une nouvelle partie commence par le choix du mode, puis de la couleur contre l'ordinateur ;
-- la confirmation ne s'affiche que si des coups ont été joués.
function Chess:chooseMode()
    if self.mode_dialog then return end
    self.mode_dialog = ButtonDialog:new{
        title = T("New game"),
        buttons = {
            {{text = T("Learning · hints and undo"), callback = function() self:chooseColor("apprentissage") end}},
            {{text = T("Game · no help"), callback = function() self:chooseColor("partie") end}},
            {{text = T("Two players · taking turns on the screen"), callback = function() self:newGame("deux_joueurs", "w") end}},
            {{text = T("Back"), callback = function() self:closeModeDialog() end}},
        },
        tap_close_callback = function() self.mode_dialog = nil end,
    }
    UIManager:show(self.mode_dialog)
end

function Chess:closeModeDialog()
    if self.mode_dialog then UIManager:close(self.mode_dialog); self.mode_dialog = nil end
end

function Chess:chooseColor(mode)
    self:closeModeDialog()
    if self.color_dialog then return end
    self.color_dialog = ButtonDialog:new{
        title = T("Your pieces"),
        buttons = {
            {{text = T("White · I start"), callback = function() self:newGame(mode, "w") end}},
            {{text = T("Black · the computer starts"), callback = function() self:newGame(mode, "b") end}},
            {{text = T("Back"), callback = function() self:closeColorDialog(); self:chooseMode() end}},
        },
        tap_close_callback = function() self.color_dialog = nil end,
    }
    UIManager:show(self.color_dialog)
end

function Chess:closeColorDialog()
    if self.color_dialog then UIManager:close(self.color_dialog); self.color_dialog = nil end
end

function Chess:confirmNewGame()
    if #self.game.moves == 0 then self:chooseMode(); return end
    local text = self.game:result() and T("Start a new game?")
        or T("Start a new game? The current game will be erased.")
    self:confirm(text, function() self:chooseMode() end)
end

-- Réglages : niveau de l'ordinateur (sauf à deux joueurs), repères de l'échiquier, langue.
function Chess:openSettings()
    if self.settings_dialog then return end
    local buttons = {}
    if not self:twoPlayers() then
        for _, level in ipairs(levels) do
            local text = T(level.name) .. (level.blurb and (" · " .. T(level.blurb)) or "")
            if level.id == self.game.level then text = "✓ " .. text end
            local id = level.id
            buttons[#buttons + 1] = {{text = text, callback = function() self:setLevel(id) end}}
        end
    end
    buttons[#buttons + 1] = {{
        text = self:showCoords() and T("Hide coordinates (A–H, 1–8)") or T("Show coordinates (A–H, 1–8)"),
        callback = function() self:toggleCoords() end,
    }}
    buttons[#buttons + 1] = {{
        text = I18n.language == "fr" and T("Language: French · switch to English") or T("Language: English · switch to French"),
        callback = function() self:toggleLanguage() end,
    }}
    buttons[#buttons + 1] = {{text = T("Back"), callback = function() self:closeSettings() end}}
    self.settings_dialog = ButtonDialog:new{
        title = self:twoPlayers() and T("Settings") or T("Settings · computer level"), buttons = buttons,
        tap_close_callback = function() self.settings_dialog = nil end,
    }
    UIManager:show(self.settings_dialog)
end

function Chess:closeSettings()
    if self.settings_dialog then UIManager:close(self.settings_dialog); self.settings_dialog = nil end
end

function Chess:toggleCoords()
    self:closeSettings()
    self.settings:saveSetting("coords", not self:showCoords())
    self.settings:flush()
    self:render()
end

-- La langue est propre au plugin ; l'entrée du menu KOReader change au prochain démarrage.
function Chess:toggleLanguage()
    self:closeSettings()
    local language = I18n.set(I18n.language == "fr" and "en" or "fr")
    self.settings:saveSetting("language", language)
    self.settings:flush()
    self:render()
end

function Chess:setLevel(id)
    self:closeSettings()
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
