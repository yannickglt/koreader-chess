-- SPDX-License-Identifier: GPL-3.0-or-later
local Engine = {}
Engine.__index = Engine

-- `clock` sert à mesurer les temps de réponse ; KOReader fournit une horloge monotone.
function Engine.new(transport, on_position, on_bestmove, on_hint)
    return setmetatable({
        transport = transport, on_position = on_position, on_bestmove = on_bestmove, on_hint = on_hint,
        legal = {}, clock = os.clock,
    }, Engine)
end

function Engine:send(line)
    self.transport:send(line .. "\n")
end

function Engine:start(options, saved_moves)
    self.options = options
    self.moves = saved_moves or {}
    self.started = self.clock()
    self:send("uci")
end

function Engine:play(moves)
    self.moves = moves
    self.fen, self.checkers, self.legal, self.hinting = nil, false, {}, false
    local suffix = #moves > 0 and (" moves " .. table.concat(moves, " ")) or ""
    self:send("position startpos" .. suffix)
    self:send("d")
    self:send("go perft 1")
end

function Engine:search(movetime)
    self.search_started = self.clock()
    self:send("go movetime " .. movetime)
end

-- Coup de l'ordinateur : au hasard parmi les coups légaux avec la probabilité `random`
-- du niveau, sinon recherche bornée par `movetime`.
function Engine:think()
    local random = self.options.random or 0
    if random > 0 and #self.legal > 0 and math.random() < random then
        local move = self.legal[math.random(#self.legal)]
        self.bestmove, self.last_choice, self.search_time = move, "random", 0
        if self.on_bestmove then self.on_bestmove(move) end
        return "random"
    end
    self.last_choice = "search"
    self:search(self.options.movetime)
    return "search"
end

-- Conseil pour le joueur : recherche à pleine force sur la position courante.
function Engine:hint()
    if self.hinting or not self.fen or #self.legal == 0 then return false end
    self.hinting = true
    self:send("setoption name Skill Level value 20")
    self:search(self.options.hint_movetime or 300)
    return true
end

function Engine:line(line)
    if line == "uciok" then
        self:send("setoption name Threads value 1")
        self:send("setoption name Hash value 8")
        self:send("setoption name Ponder value false")
        self:send("setoption name UCI_LimitStrength value false")
        self:send("setoption name Skill Level value " .. self.options.skill)
        self:send("isready")
    elseif line == "readyok" then
        self.ready_time = self.clock() - (self.started or self.clock())
        self:play(self.moves)
    elseif line:sub(1, 5) == "Fen: " then
        self.fen = line:sub(6)
    elseif line:sub(1, 10) == "Checkers: " or line == "Checkers:" then
        self.checkers = line:match("^Checkers:%s*(.-)%s*$") ~= ""
    elseif line:match("^[a-h][1-8][a-h][1-8][qrbn]?: %d+$") then
        self.legal[#self.legal + 1] = line:match("^(%S+):")
    elseif line:match("^Nodes searched: %d+") then
        if self.fen then
            -- Le plugin décide s'il faut chercher (trait de l'ordinateur, pas de nulle à trancher).
            local think = self.on_position(self.fen, self.legal, self.checkers)
            if think == true and #self.legal > 0 then
                self:think()
            end
        end
    else
        local move = line:match("^bestmove ([a-h][1-8][a-h][1-8][qrbn]?)")
        if move then
            self.search_time = self.clock() - (self.search_started or self.clock())
            if self.hinting then
                self.hinting = false
                self:send("setoption name Skill Level value " .. self.options.skill)
                if self.on_hint then self.on_hint(move) end
            else
                self.bestmove = move
                if self.on_bestmove then self.on_bestmove(move) end
            end
        end
    end
end

return Engine
