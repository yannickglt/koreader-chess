package.path = "chess.koplugin/?.lua;" .. package.path
local Transport = require("transport")
local binary = assert(os.getenv("STOCKFISH"))
local transport = assert(Transport.new(binary))
local function legal(fen)
    assert(transport:send("position fen " .. fen .. "\ngo perft 1\n"))
    local moves = {}
    for _ = 1, 500 do
        for _, line in ipairs(transport:poll()) do
            local move = line:match("^([a-h][1-8][a-h][1-8][qrbn]?): 1$")
            if move then moves[move] = true end
            if line:match("^Nodes searched: ") then return moves end
        end
        if transport.error then error(transport.error) end
        os.execute("sleep 0.01")
    end
    error("perft sans réponse")
end

local castle = legal("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
assert(castle.e1g1 and castle.e1c1)
local en_passant = legal("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
assert(en_passant.e5d6)
local promotion = legal("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
assert(promotion.a7a8q and promotion.a7a8r and promotion.a7a8b and promotion.a7a8n)
local mate = legal("7k/6Q1/5K2/8/8/8/8/8 b - - 0 1")
assert(next(mate) == nil)
transport:close()
print("rules: OK")
