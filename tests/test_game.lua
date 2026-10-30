package.path = "chess.koplugin/?.lua;" .. package.path
local Game = require("game")

local function eq(actual, expected)
    assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end

local game = Game.new()
local start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
eq(game.board.e2, "P") -- position initiale avant la réponse du moteur
eq(game.fen, nil)
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
repetition:update(repeated, {"e1e2"}, false) -- même pli : pas de double comptage
eq(repetition.repetitions, 5)
eq(#repetition.keys, 5)

local ep_repetition = Game.new()
ep_repetition:update("4k3/7p/8/8/4P3/8/P7/4K3 b - e3 0 1", {"e8e7"}, false)
ep_repetition:append("e8e7")
ep_repetition:update("4k3/7p/8/8/4P3/8/P7/4K3 b - - 2 2", {"e8e7"}, false)
eq(ep_repetition.repetitions, 2)
local ep_legal = Game.new()
ep_legal:update("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", {"e5d6"}, false)
ep_legal:append("e5d6")
ep_legal:update("4k3/8/8/3pP3/8/8/8/4K3 w - - 2 2", {"e5e6"}, false)
eq(ep_legal.repetitions, 1)

local fifty = Game.new()
fifty:update("4k3/7p/8/8/8/8/8/4K3 w - - 100 51", {"e1e2"}, false)
eq(fifty:can_claim_draw(), true)
fifty:update("4k3/7p/8/8/8/8/8/4K3 w - - 150 76", {"e1e2"}, false)
eq(fifty:result(), "75_coups")

local insufficient = Game.new()
insufficient:update("4k3/8/8/8/8/8/8/4K3 w - - 0 1", {"e1e2"}, false)
eq(insufficient:result(), "materiel")

-- cohérence entre la liste des coups et la position renvoyée par le moteur
local consistent = Game.new({"e2e4", "e7e5"})
eq(consistent:consistent(), true) -- pas encore de position
consistent:update("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2", {"g1f3"}, false)
eq(consistent:consistent(), true)
local skipped = Game.new({"e2e4", "e7e5", "e2e5"}) -- forme valide, coup illégal ignoré par Stockfish
eq(#skipped.moves, 3)
skipped:update("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2", {"g1f3"}, false)
eq(skipped:consistent(), false)
local shifted = Game.new({"e2e4", "e7e5", "g1f3", "b8c6"})
shifted:update("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2", {"g1f3"}, false)
eq(shifted:consistent(), false) -- trait correct mais numéro de coup décalé

-- destinations et dernier coup
local dest = Game.new()
dest:update(start, {"e2e4", "e2e3", "g1f3", "g1h3"}, false)
local d = dest:destinations("e2")
eq(d.e4, true); eq(d.e3, true); eq(d.f3, nil)
eq(dest:last_move(), nil)
dest:append("e2e4")
local from, to = dest:last_move()
eq(from, "e2"); eq(to, "e4")

-- annulation : les clés de répétition au-delà du pli sont oubliées
local undo = Game.new()
undo:update(start, {"e2e4"}, false)
undo:append("e2e4")
undo:update("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", {"e7e5"}, false)
undo:append("e7e5")
undo:update("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2", {"g1f3"}, false)
undo.claimed_draw = true
eq(#undo.keys, 3)
eq(undo:undo(2), true)
eq(#undo.moves, 0)
eq(undo.fen, nil)
eq(undo.turn, "w")
eq(undo.keys[2], nil); eq(undo.keys[3], nil)
eq(undo.keys[1] ~= nil, true)
eq(undo.claimed_draw, nil)
eq(undo:result(), nil)
eq(undo:undo(1), false)

-- reprise d'une sauvegarde : coups et clés restaurés, sauvegarde corrompue ignorée
local restored = Game.new({"e2e4", "e7e5"}, "facile", {keys = {"k1", "k2", 3}, mode = "partie"})
eq(#restored.moves, 2); eq(restored.keys[1], "k1"); eq(restored.keys[2], "k2"); eq(restored.keys[3], nil)
eq(restored.turn, "w"); eq(restored.level, "facile"); eq(restored.mode, "partie")
eq(Game.new().mode, "apprentissage"); eq(Game.new(nil, nil, {mode = "autre"}).mode, "apprentissage")
eq(Game.new(nil, nil, {mode = "deux_joueurs"}).mode, "deux_joueurs")
local corrupt = Game.new({"e2e4", "zz"}, "facile", {keys = {"a", "b"}})
eq(#corrupt.moves, 0)
eq(next(corrupt.keys), nil)
eq(corrupt.board.e2, "P")

print("game: OK")
