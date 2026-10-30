local Board = {}
local pieces = {
    K = "♔", Q = "♕", R = "♖", B = "♗", N = "♘", P = "♙",
    k = "♚", q = "♛", r = "♜", b = "♝", n = "♞", p = "♟",
}

-- Ligne 1 = rangée 8 (les noirs en haut), colonne 1 = colonne a.
function Board.square(row, column)
    assert(row >= 1 and row <= 8 and column >= 1 and column <= 8)
    return string.char(96 + column) .. (9 - row)
end

function Board.piece(letter)
    return pieces[letter] or " "
end

return Board
