package.path = "chess.koplugin/?.lua;" .. package.path
local Game = require("game")

local function eq(actual, expected)
    assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end

local game = Game.new()
local start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
game:update(start, { "e2e4", "g1f3" }, false)
eq(game.board.e2, "P")
eq(game.board.e4, nil)
eq(game.turn, "w")
eq(game:move_for("e2", "e4"), "e2e4")
eq(game:move_for("e2", "e5"), nil)

game:append("e2e4")
eq(game.moves[1], "e2e4")
game:update("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", {"e7e5"}, false)
eq(game.board.e4, "P")
eq(game.turn, "b")

game:update("4k3/P7/8/8/8/8/8/4K3 w - - 0 1", {"a7a8q", "a7a8r", "a7a8b", "a7a8n"}, false)
local promotion = game:promotions("a7", "a8")
eq(#promotion, 4)
eq(promotion[1], "a7a8q")

local mate = Game.new()
mate:update("7k/6Q1/5K2/8/8/8/8/8 b - - 0 1", {}, true)
eq(mate:result(), "mat")
local stalemate = Game.new()
stalemate:update("7k/5K2/6Q1/8/8/8/8/8 b - - 0 1", {}, false)
eq(stalemate:result(), "pat")

local repetition = Game.new()
local repeated = "4k3/7p/8/8/8/8/P7/4K3 w - - 8 5"
for i = 1, 5 do
    if i > 1 then repetition:append("e1e2") end
    repetition:update(repeated, {"e1e2"}, false)
end
eq(repetition:can_claim_draw(), true)
eq(repetition:result(), "repetition")
repetition:update(repeated, {"e1e2"}, false)
eq(repetition.repetitions, 5)

local fifty = Game.new()
fifty:update("4k3/7p/8/8/8/8/8/4K3 w - - 100 51", {"e1e2"}, false)
eq(fifty:can_claim_draw(), true)
fifty:update("4k3/7p/8/8/8/8/8/4K3 w - - 150 76", {"e1e2"}, false)
eq(fifty:result(), "75_coups")

local insufficient = Game.new()
insufficient:update("4k3/8/8/8/8/8/8/4K3 w - - 0 1", {"e1e2"}, false)
eq(insufficient:result(), "materiel")

print("game: OK")
