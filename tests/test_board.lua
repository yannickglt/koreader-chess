package.path = "chess.koplugin/?.lua;" .. package.path
local Board = require("board")
assert(Board.square(1, 1) == "a8")
assert(Board.square(8, 8) == "h1")
assert(Board.piece("K") == "♔")
assert(Board.piece("p") == "♟")
assert(Board.piece(nil) == " ")
print("board: OK")
