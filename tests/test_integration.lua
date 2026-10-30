package.path = "chess.koplugin/?.lua;" .. package.path
local Engine = require("engine")
local Game = require("game")
local Transport = require("transport")

local binary = assert(os.getenv("STOCKFISH"), "STOCKFISH doit pointer vers un binaire Mac")
local transport = assert(Transport.new(binary))
local game = Game.new()
local states, reply = 0, nil
local engine = Engine.new(transport, function(fen, legal, check)
    assert(game:update(fen, legal, check))
    states = states + 1
end, function(move) reply = move end)
engine:start({skill = 0, movetime = 150})

local function wait_for(predicate)
    for _ = 1, 600 do
        for _, line in ipairs(transport:poll()) do engine:line(line) end
        if predicate() then return true end
        if transport.error then error(transport.error) end
        os.execute("sleep 0.01")
    end
    error("Réponse Stockfish absente")
end

wait_for(function() return states == 1 end)
assert(game.fen:match("^rnbqkbnr/pppppppp"))
assert(#game.legal == 20)
assert(game:move_for("e2", "e4") == "e2e4")
game:append("e2e4")
engine:play(game.moves)
wait_for(function() return states == 2 end)
assert(game.turn == "b")
wait_for(function() return reply ~= nil end)
assert(reply:match("^[a-h][1-8][a-h][1-8][qrbn]?$"))
game:append(reply)
engine:play(game.moves)
wait_for(function() return states == 3 end)
assert(game.turn == "w")
transport:close()
print("integration: OK; Stockfish played " .. reply)
