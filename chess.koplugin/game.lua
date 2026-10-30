local Game = {}
Game.__index = Game

local MOVE = "^[a-h][1-8][a-h][1-8][qrbn]?$"
local START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

local function parse_fen(fen)
    local placement, turn, castling, ep, halfmove, fullmove = fen:match("^(%S+) (%S+) (%S+) (%S+) (%d+)%s*(%d*)")
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
    return {board = board, turn = turn, halfmove = tonumber(halfmove), fullmove = tonumber(fullmove),
        placement = placement, castling = castling, ep = ep}
end

-- `moves` : liste de coups UCI déjà joués ; `options.keys[i]` : clé de répétition de la
-- position après i-1 coups ; `options.mode` : "apprentissage" (annulation et indice), "partie"
-- (sans aide) ou "deux_joueurs" (les deux couleurs sur l'écran). Une sauvegarde corrompue repart
-- d'une partie vide.
local MODES = {apprentissage = true, partie = true, deux_joueurs = true}

function Game.new(moves, level, options)
    options = options or {}
    local game = setmetatable({
        moves = {}, level = level, keys = {}, legal = {}, board = {}, turn = "w",
        mode = MODES[options.mode] and options.mode or "apprentissage",
    }, Game)
    if type(moves) == "table" then
        for _, move in ipairs(moves) do
            if type(move) ~= "string" or not move:match(MOVE) then
                game.moves = {}
                break
            end
            game.moves[#game.moves + 1] = move
        end
    end
    if type(options.keys) == "table" then
        for i = 1, #game.moves do
            local key = options.keys[i]
            if type(key) ~= "string" then break end
            game.keys[i] = key
        end
    end
    game.turn = #game.moves % 2 == 0 and "w" or "b"
    -- Position initiale affichée avant la première réponse du moteur.
    if #game.moves == 0 then game.board = parse_fen(START).board end
    return game
end

function Game:append(move)
    assert(type(move) == "string" and move:match(MOVE), "Coup UCI invalide")
    self.moves[#self.moves + 1] = move
end

local function forget_keys_after(keys, ply)
    for i in pairs(keys) do
        if i > ply then keys[i] = nil end
    end
end

function Game:update(fen, legal, in_check)
    local state, err = parse_fen(fen)
    if not state then return nil, err end
    self.fen, self.board, self.turn, self.halfmove = fen, state.board, state.turn, state.halfmove
    self.fullmove = state.fullmove
    self.legal, self.in_check = legal, in_check
    local ep = state.ep
    if ep ~= "-" then
        local pawn = state.turn == "w" and "P" or "p"
        local can_capture = false
        for _, move in ipairs(legal) do
            local from = move:sub(1, 2)
            if move:sub(3, 4) == ep and from:sub(1, 1) ~= ep:sub(1, 1) and state.board[from] == pawn then
                can_capture = true
                break
            end
        end
        if not can_capture then ep = "-" end
    end
    local key = table.concat({state.placement, state.turn, state.castling, ep}, " ")
    local ply = #self.moves + 1
    self.keys[ply] = key
    forget_keys_after(self.keys, ply)
    local count = 0
    for i = 1, ply do
        if self.keys[i] == key then count = count + 1 end
    end
    self.repetitions = count
    return true
end

-- Retire les `count` derniers coups. La position doit ensuite être redemandée au moteur.
function Game:undo(count)
    count = math.min(count or 1, #self.moves)
    if count < 1 then return false end
    for _ = 1, count do table.remove(self.moves) end
    forget_keys_after(self.keys, #self.moves + 1)
    self.fen, self.legal, self.in_check, self.claimed_draw = nil, {}, false, nil
    self.repetitions, self.halfmove = 0, 0
    self.turn = #self.moves % 2 == 0 and "w" or "b"
    return true
end

-- Vrai si la position reçue du moteur correspond à la liste des coups : Stockfish ignore en
-- silence un coup illégal dans `position startpos moves …`, ce qui décale trait et numéro de coup.
function Game:consistent()
    if not self.fen then return true end
    local expected_turn = #self.moves % 2 == 0 and "w" or "b"
    local expected_fullmove = math.floor(#self.moves / 2) + 1
    return self.turn == expected_turn and (self.fullmove == nil or self.fullmove == expected_fullmove)
end

function Game:last_move()
    local move = self.moves[#self.moves]
    if not move then return nil end
    return move:sub(1, 2), move:sub(3, 4)
end

function Game:destinations(from)
    local result = {}
    for _, move in ipairs(self.legal or {}) do
        if move:sub(1, 2) == from then result[move:sub(3, 4)] = true end
    end
    return result
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
