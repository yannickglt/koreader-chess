-- SPDX-License-Identifier: GPL-3.0-or-later
-- Interface en anglais par défaut ; les traductions sont indexées par la chaîne anglaise.
-- La langue est un réglage du plugin, indépendant de celui de KOReader.
local I18n = {language = "en"}

local catalogs = {
    fr = {
        ["Chess"] = "Échecs",
        -- niveaux
        ["Discovery"] = "Découverte", ["often plays at random"] = "joue souvent au hasard",
        ["Beginner"] = "Initiation", ["sometimes slips"] = "se trompe parfois",
        ["Easy"] = "Facile", ["Intermediate"] = "Intermédiaire", ["Hard"] = "Difficile",
        -- modes
        ["Learning"] = "Apprentissage", ["Game"] = "Partie", ["Two players"] = "Deux joueurs",
        -- messages
        ["Stockfish is missing or not executable in chess.koplugin/bin/."] = "Stockfish absent ou non exécutable dans chess.koplugin/bin/.",
        ["Could not start Stockfish: %s"] = "Impossible de lancer Stockfish : %s",
        ["The saved game is unreadable: starting a new game."] = "La partie sauvegardée est illisible : nouvelle partie.",
        ["Stockfish is not responding. Tap the board to restart it."] = "Stockfish ne répond pas. Touchez l'échiquier pour le relancer.",
        -- en-tête
        ["Stalemate · draw"] = "Pat · partie nulle",
        ["Insufficient material · draw"] = "Matériel insuffisant · partie nulle",
        ["Fivefold repetition · draw"] = "Cinq répétitions · partie nulle",
        ["75-move rule · draw"] = "75 coups · partie nulle",
        ["Draw"] = "Partie nulle",
        ["Checkmate · White wins"] = "Échec et mat · les blancs gagnent",
        ["Checkmate · Black wins"] = "Échec et mat · les noirs gagnent",
        ["Checkmate · you win!"] = "Échec et mat · tu as gagné !",
        ["Checkmate · the computer wins"] = "Échec et mat · l'ordinateur a gagné",
        ["Draw available · choose"] = "Nulle possible · choisir",
        ["Looking for a hint…"] = "Je cherche un conseil…",
        ["The computer is thinking…"] = "L'ordinateur réfléchit…",
        ["One moment…"] = "Un instant…",
        ["Engine stopped · tap the board"] = "Moteur arrêté · touchez l'échiquier",
        ["White to move"] = "Aux blancs de jouer", ["Black to move"] = "Aux noirs de jouer",
        ["Your move"] = "À vous de jouer",
        ["Check! %s"] = "Échec ! %s",
        ["White: %s"] = "Blancs : %s", ["Black: %s"] = "Noirs : %s",
        ["queen"] = "dame", ["rook"] = "tour", ["bishop"] = "fou", ["knight"] = "cavalier",
        -- boutons
        ["New game"] = "Nouvelle partie", ["Settings"] = "Réglages", ["Close"] = "Fermer",
        ["Undo move"] = "Annuler le coup", ["Hint"] = "Indice", ["Continue"] = "Continuer",
        ["Claim a draw"] = "Réclamer la nulle",
        -- confirmations
        ["Yes"] = "Oui", ["No"] = "Non",
        ["Close the chess game? The game is kept for next time."] = "Fermer le jeu d'échecs ? La partie est gardée pour la prochaine fois.",
        ["Undo the last move?"] = "Annuler le dernier coup ?",
        ["Undo your last move and the computer's reply?"] = "Annuler ton dernier coup et la réponse de l'ordinateur ?",
        ["Claim a draw? The game ends without a winner."] = "Réclamer la nulle ? La partie s'arrête sans gagnant.",
        ["Start a new game?"] = "Commencer une nouvelle partie ?",
        ["Start a new game? The current game will be erased."] = "Commencer une nouvelle partie ? La partie en cours sera effacée.",
        -- promotion
        ["Promotion"] = "Promotion",
        ["Queen"] = "Dame", ["Rook"] = "Tour", ["Bishop"] = "Fou", ["Knight"] = "Cavalier",
        -- nouvelle partie
        ["Learning · hints and undo"] = "Apprentissage · indices et retour en arrière",
        ["Game · no help"] = "Partie · sans aide",
        ["Two players · taking turns on the screen"] = "Deux joueurs · à tour de rôle sur l'écran",
        ["Back"] = "Retour",
        ["Your pieces"] = "Vos pièces",
        ["White · I start"] = "Blancs · je commence",
        ["Black · the computer starts"] = "Noirs · l'ordinateur commence",
        -- réglages
        ["Settings · computer level"] = "Réglages · niveau de l'ordinateur",
        ["Hide coordinates (A–H, 1–8)"] = "Masquer les repères (A–H, 1–8)",
        ["Show coordinates (A–H, 1–8)"] = "Afficher les repères (A–H, 1–8)",
        ["Language: French · switch to English"] = "Langue : français · passer en anglais",
    },
}

I18n.languages = {"en", "fr"}

function I18n.set(language)
    I18n.language = catalogs[language] and language or "en"
    return I18n.language
end

function I18n.translate(text)
    local catalog = catalogs[I18n.language]
    return catalog and catalog[text] or text
end

return I18n
