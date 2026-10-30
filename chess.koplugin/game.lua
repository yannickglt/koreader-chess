local Game = {}
Game.__index = Game

local function parse_fen(fen)
    local placement, turn, castling, ep, halfmove = fen:match("^(%S+) (%S+) (%S+) (%S+) (%d+)")
    if not placement or (turn ~= "w" and turn ~= "b") then return nil, "FEN invalide" end
    local board = {}
    local rank = 8
    for row in (placement .. "/"):gmatch("(.-)/") do
        if rank < 1 then return nil, "Trop de rangées" end
        local file = 1
        for char in row:gmatch(".") do
            local empty = tonumber(char)
            if empty then
                file = file + empty
            elseif char:match("^[prnbqkPRNBQK]$") then
                if file > 8 then return nil, "Rangée trop longue" end
                board[string.char(96 + file) .. rank] = char
                file = file + 1
            else
                return nil, "Pièce inconnue"
            end
        end
        if file ~= 9 then return nil, "Rangée incomplète" end
        rank = rank - 1
    end
    if rank ~= 0 then return nil, "Nombre de rangées invalide" end
    return {board = board, turn = turn, halfmove = tonumber(halfmove), key = table.concat({placement, turn, castling, ep}, " ")}
end

function Game.new(moves, level, history)
    history = history or {}
    return setmetatable({moves = moves or {}, level = level or 1, seen = history.seen or {}, last_counted_ply = history.last_counted_ply, legal = {}, board = {}, turn = "w"}, Game)
end

function Game:append(move)
    assert(type(move) == "string" and move:match("^[a-h][1-8][a-h][1-8][qrbn]?$"), "Coup UCI invalide")
    self.moves[#self.moves + 1] = move
end

function Game:update(fen, legal, in_check)
    local state, err = parse_fen(fen)
    if not state then return nil, err end
    self.fen, self.board, self.turn, self.halfmove = fen, state.board, state.turn, state.halfmove
    self.legal, self.in_check = legal, in_check
    if self.last_counted_ply ~= #self.moves then
        self.seen[state.key] = (self.seen[state.key] or 0) + 1
        self.last_counted_ply = #self.moves
    end
    self.repetitions = self.seen[state.key]
    return true
end

function Game:promotions(from, to)
    local result = {}
    for _, move in ipairs(self.legal or {}) do
        if move:sub(1, 4) == from .. to and #move == 5 then result[#result + 1] = move end
    end
    return result
end

function Game:move_for(from, to)
    local wanted = from .. to
    for _, move in ipairs(self.legal or {}) do
        if move == wanted then return move end
    end
    return nil
end

local function insufficient(board)
    local minors = {}
    for square, piece in pairs(board) do
        if piece ~= "k" and piece ~= "K" then
            if piece:lower() ~= "b" and piece:lower() ~= "n" then return false end
            minors[#minors + 1] = {piece, square}
        end
    end
    if #minors <= 1 then return true end
    if #minors == 2 and minors[1][1]:lower() == "b" and minors[2][1]:lower() == "b" then
        local function color(square)
            return (string.byte(square, 1) - 97 + tonumber(square:sub(2, 2))) % 2
        end
        return color(minors[1][2]) == color(minors[2][2])
    end
    return false
end

function Game:can_claim_draw()
    return (self.repetitions or 0) >= 3 or (self.halfmove or 0) >= 100
end

function Game:result()
    if not self.fen then return nil end
    if #self.legal == 0 then return self.in_check and "mat" or "pat" end
    if insufficient(self.board) then return "materiel" end
    if self.repetitions >= 5 then return "repetition" end
    if self.halfmove >= 150 then return "75_coups" end
    return self.claimed_draw and "nulle_reclamee" or nil
end

return Game
