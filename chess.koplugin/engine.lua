local Engine = {}
Engine.__index = Engine

function Engine.new(transport, on_position, on_bestmove)
    return setmetatable({transport = transport, on_position = on_position, on_bestmove = on_bestmove}, Engine)
end

function Engine:send(line)
    self.transport:send(line .. "\n")
end

function Engine:start(options, saved_moves)
    self.options = options
    self.moves = saved_moves or {}
    self:send("uci")
end

function Engine:play(moves)
    self.moves = moves
    self.fen, self.checkers, self.legal = nil, false, {}
    local suffix = #moves > 0 and (" moves " .. table.concat(moves, " ")) or ""
    self:send("position startpos" .. suffix)
    self:send("d")
    self:send("go perft 1")
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
        self:play(self.moves)
    elseif line:sub(1, 5) == "Fen: " then
        self.fen = line:sub(6)
    elseif line:sub(1, 10) == "Checkers: " or line == "Checkers:" then
        self.checkers = line:match("^Checkers:%s*(.-)%s*$") ~= ""
    elseif line:match("^[a-h][1-8][a-h][1-8][qrbn]?: %d+$") then
        self.legal[#self.legal + 1] = line:match("^(%S+):")
    elseif line:match("^Nodes searched: %d+") then
        if self.fen then
            local continue = self.on_position(self.fen, self.legal, self.checkers)
            if continue ~= false and self.fen:match("^%S+ b ") and #self.legal > 0 then
                self:send("go movetime " .. self.options.movetime)
            end
        end
    else
        local move = line:match("^bestmove ([a-h][1-8][a-h][1-8][qrbn]?)")
        if move then
            self.bestmove = move
            if self.on_bestmove then self.on_bestmove(move) end
        end
    end
end

return Engine
