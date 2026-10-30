package.path = "chess.koplugin/?.lua;" .. package.path
local Engine = require("engine")

local sent = {}
local states = {}
local fake_transport = { send = function(_, s) sent[#sent + 1] = s end }
-- Le moteur ne cherche que si le rappel le demande (ici : quand les noirs ont le trait).
local engine = Engine.new(fake_transport, function(fen, moves, check)
    states[#states + 1] = {fen, moves, check}
    return fen:match("^%S+ b ") ~= nil
end)
engine:start({skill = 3, movetime = 250})
assert(sent[1] == "uci\n")
engine:line("uciok")
assert(table.concat(sent):find("setoption name Threads value 1", 1, true))
assert(table.concat(sent):find("setoption name Hash value 8", 1, true))
assert(table.concat(sent):find("setoption name Ponder value false", 1, true))
engine:line("readyok")
assert(engine.ready_time ~= nil)
assert(table.concat(sent):find("position startpos", 1, true))
engine:line("Fen: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
engine:line("Checkers:")
engine:line("e2e4: 1")
engine:line("g1f3: 1")
engine:line("Nodes searched: 20")
assert(#states == 1 and #states[1][2] == 2)
assert(states[1][3] == false)
engine:play({"e2e4"})
assert(table.concat(sent):find("position startpos moves e2e4", 1, true))
engine:line("Fen: rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
engine:line("Checkers:")
engine:line("e7e5: 1")
engine:line("Nodes searched: 20")
assert(sent[#sent] == "go movetime 250\n")
assert(engine.last_choice == "search")
engine:line("bestmove e7e5 ponder g1f3")
assert(engine.bestmove == "e7e5")
assert(engine.search_time ~= nil)

-- on_position qui refuse la recherche (nulle à décider)
local no_search_sent = {}
local no_search = Engine.new({send = function(_, s) no_search_sent[#no_search_sent + 1] = s end}, function() return false end)
no_search:start({skill = 0, movetime = 150})
no_search:line("readyok")
no_search:line("Fen: 8/8/8/8/8/8/7p/4K2k b - - 150 76")
no_search:line("h2h1q: 1")
no_search:line("Nodes searched: 1")
assert(no_search_sent[#no_search_sent] ~= "go movetime 150\n")

-- niveau avec hasard : un coup légal est joué sans recherche
math.randomseed(7)
local random_sent, random_moves = {}, {}
local random_engine = Engine.new({send = function(_, s) random_sent[#random_sent + 1] = s end},
    function() return true end, function(move) random_moves[#random_moves + 1] = move end)
random_engine:start({skill = 0, movetime = 100, random = 1})
random_engine:line("readyok")
random_engine:line("Fen: rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
random_engine:line("Checkers:")
random_engine:line("e7e5: 1")
random_engine:line("g8f6: 1")
random_engine:line("Nodes searched: 2")
assert(#random_moves == 1 and (random_moves[1] == "e7e5" or random_moves[1] == "g8f6"), tostring(random_moves[1]))
assert(random_engine.last_choice == "random" and random_engine.search_time == 0)
assert(not table.concat(random_sent):find("go movetime", 1, true))
random_engine.options.random = 0
assert(random_engine:think() == "search")
assert(random_sent[#random_sent] == "go movetime 100\n")

-- conseil : recherche à pleine force puis retour au niveau courant
local hint_sent, hint_moves = {}, {}
local hint_engine = Engine.new({send = function(_, s) hint_sent[#hint_sent + 1] = s end},
    function() return true end, function() error("bestmove inattendu") end,
    function(move) hint_moves[#hint_moves + 1] = move end)
hint_engine:start({skill = 3, movetime = 250})
assert(not hint_engine:hint()) -- pas de position connue
hint_engine:line("readyok")
hint_engine:line("Fen: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
hint_engine:line("Checkers:")
hint_engine:line("e2e4: 1")
hint_engine:line("Nodes searched: 1")
assert(hint_engine:hint())
assert(hint_sent[#hint_sent] == "go movetime 300\n")
assert(hint_sent[#hint_sent - 1] == "setoption name Skill Level value 20\n")
assert(not hint_engine:hint()) -- déjà en cours
hint_engine:line("bestmove e2e4 ponder e7e5")
assert(hint_moves[1] == "e2e4")
assert(hint_sent[#hint_sent] == "setoption name Skill Level value 3\n")
assert(not hint_engine.hinting)
print("engine: OK")
