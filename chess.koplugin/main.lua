local Blitbuffer = require("ffi/blitbuffer")
local Board = require("board")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Engine = require("engine")
local Game = require("game")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local Transport = require("transport")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")

local levels = {
    {name = "Initiation", skill = 0, movetime = 150},
    {name = "Facile", skill = 3, movetime = 250},
    {name = "Intermédiaire", skill = 8, movetime = 350},
    {name = "Difficile", skill = 15, movetime = 500},
}

local Chess = WidgetContainer:extend{name = "chess", is_doc_only = false}

function Chess:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/chess.lua")
    local saved = self.settings:readSetting("game") or {}
    local level = type(saved.level) == "number" and math.floor(saved.level) or 1
    if level < 1 or level > #levels then level = 1 end
    self.game = Game.new(saved.moves, level, {seen = saved.seen, last_counted_ply = saved.last_counted_ply})
    self.game.claimed_draw = saved.claimed_draw
    self.ui.menu:registerToMainMenu(self)
end

function Chess:addToMainMenu(menu_items)
    menu_items.chess = {
        text = "Échecs",
        sorting_hint = "more_tools",
        callback = function() self:openBoard() end,
    }
end

function Chess:save()
    self.settings:saveSetting("game", {
        moves = self.game.moves,
        level = self.game.level,
        seen = self.game.seen,
        last_counted_ply = self.game.last_counted_ply,
        claimed_draw = self.game.claimed_draw,
    })
    self.settings:flush()
end

function Chess:stopEngine()
    UIManager:unschedule(Chess.poll)
    if self.transport then self.transport:close(); self.transport = nil end
    self.engine = nil
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
    self.waiting = true
    self.engine = Engine.new(transport,
        function(fen, legal, in_check)
            return self:acceptPosition(fen, legal, in_check)
        end,
        function(move)
            self.game:append(move)
            self:save()
            self.engine:play(self.game.moves)
        end)
    self.engine:start(levels[self.game.level] or levels[1], self.game.moves)
    UIManager:scheduleIn(0.05, Chess.poll, self)
    return true
end

function Chess:acceptPosition(fen, legal, in_check)
    local ok, update_err = self.game:update(fen, legal, in_check)
    if not ok then
        self:stopEngine()
        UIManager:show(InfoMessage:new{text = update_err})
        return false
    end
    local result = self.game:result()
    self.pending_draw_decision = not result and self.game.turn == "b" and self.game:can_claim_draw()
    self.waiting = not result and self.game.turn == "b" and not self.pending_draw_decision
    self:save()
    self:render()
    if result then self:stopEngine() end
    return self.waiting
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
        return
    end
    if self.waiting then UIManager:scheduleIn(0.05, Chess.poll, self) end
end

function Chess:openBoard()
    if self.opened then return end
    self.opened = true
    self.waiting = true
    self:render()
    self:startEngine()
end

function Chess:closeBoard()
    self.opened = false
    self:stopEngine()
    if self.dialog then UIManager:close(self.dialog); self.dialog = nil end
    self:save()
end

local result_text = {
    mat = "Échec et mat", pat = "Pat · partie nulle", materiel = "Matériel insuffisant · partie nulle",
    repetition = "Cinq répétitions · partie nulle", ["75_coups"] = "75 coups · partie nulle",
    nulle_reclamee = "Partie nulle",
}

function Chess:render()
    if not self.opened then return end
    local result = self.game:result()
    local status = result and result_text[result] or (self.pending_draw_decision and "Nulle possible · choisir" or (self.waiting and "L'ordinateur réfléchit…" or "À vous de jouer"))
    local buttons = {}
    for row = 1, 8 do
        buttons[row] = {}
        for column = 1, 8 do
            local square = Board.square(row, column)
            local piece = self.game.board[square]
            local marker = self.selected == square and "•" or ""
            buttons[row][column] = {
                id = square,
                text = marker .. Board.piece(piece),
                background = (row + column) % 2 == 0 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_LIGHT_GRAY,
                font_size = 36,
                callback = function() self:tapSquare(square) end,
            }
        end
    end
    buttons[9] = {
        {text = "Nouvelle partie", callback = function() self:confirmNewGame() end},
        {text = levels[self.game.level].name, callback = function() self:nextLevel() end},
        {text = "Fermer", callback = function() self:closeBoard() end},
    }
    if self.game:can_claim_draw() and not result then
        buttons[10] = {{text = "Réclamer la nulle", callback = function() self:claimDraw() end}}
        if self.pending_draw_decision then
            buttons[10][2] = {text = "Continuer", callback = function() self:continueAfterClaim() end}
        end
    end
    local new_dialog = ButtonDialog:new{title = "Échecs · " .. status, buttons = buttons, dismissable = false, width_factor = 0.96}
    if self.dialog then UIManager:close(self.dialog) end
    self.dialog = new_dialog
    UIManager:show(new_dialog)
end

function Chess:claimDraw()
    if not self.game:can_claim_draw() or self.game:result() then return end
    self.game.claimed_draw = true
    self.pending_draw_decision = false
    self.waiting = false
    self:stopEngine()
    self:save()
    self:render()
end

function Chess:continueAfterClaim()
    if not self.pending_draw_decision then return end
    if not self.engine then self:startEngine(); return end
    self.pending_draw_decision = false
    self.waiting = true
    self:render()
    self.engine:send("go movetime " .. levels[self.game.level].movetime)
    UIManager:scheduleIn(0.05, Chess.poll, self)
end

function Chess:setSelection(square)
    local old = self.selected
    self.selected = square
    if not self.dialog then return end
    local function refresh_square(current)
        if current then
            local button = self.dialog.buttontable:getButtonById(current)
            if button then
                button:setText((self.selected == current and "•" or "") .. Board.piece(self.game.board[current]), button.width)
                button:refresh()
            end
        end
    end
    refresh_square(old)
    if square ~= old then refresh_square(square) end
end

function Chess:tapSquare(square)
    if not self.game.fen or self.waiting or self.game.turn ~= "w" or self.game:result() then return end
    if not self.engine then self:startEngine(); return end
    local piece = self.game.board[square]
    if not self.selected then
        if piece and piece:match("[A-Z]") then self:setSelection(square) end
        return
    end
    local from = self.selected
    self:setSelection(nil)
    if from == square then return end
    local move = self.game:move_for(from, square)
    if move then self:makeMove(move); return end
    local promotions = self.game:promotions(from, square)
    if #promotions > 0 then
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
    if piece and piece:match("[A-Z]") then self:setSelection(square) end
end

function Chess:makeMove(move)
    self.game:append(move)
    self:save()
    self.waiting = true
    self:render()
    self.engine:play(self.game.moves)
    UIManager:scheduleIn(0.05, Chess.poll, self)
end

function Chess:confirmNewGame()
    UIManager:show(ConfirmBox:new{
        text = "Commencer une nouvelle partie ?",
        ok_callback = function()
            local level = self.game.level
            self.game = Game.new(nil, level)
            self.selected = nil
            self.pending_draw_decision = false
            self:save()
            self.waiting = true
            self:render()
            self:startEngine()
        end,
    })
end

function Chess:nextLevel()
    self.game.level = self.game.level % #levels + 1
    self:save()
    self:render()
    self:startEngine()
end

function Chess:onSuspend()
    if self.opened then self:stopEngine(); self.waiting = true; self:save() end
end

function Chess:onResume()
    if self.opened and not self.game:result() then self:startEngine() end
end

function Chess:onCloseWidget()
    self:closeBoard()
end

return Chess
