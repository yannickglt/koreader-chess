# Échecs pour KOReader

Plugin d'échecs hors ligne pour KOReader, pensé pour un enfant sur une Tolino Vision Color (cible KOReader `kobov5`). Contre l'ordinateur, l'enfant joue les blancs : il touche une pièce, les cases possibles s'affichent, il touche la destination, et Stockfish répond. À deux joueurs, les deux couleurs se jouent à tour de rôle sur le même écran. Le moteur fournit les coups légaux et la position (`go perft 1`, `d`) ; le plugin ne réimplémente pas les règles.

## État au 30 octobre 2026

- Validé sur Mac (LuaJIT 2.1, Stockfish 16 et 19 macOS) et dans un conteneur Linux ARMv7 émulé avec le LuaJIT et les déclarations POSIX du paquet officiel KOReader 2026.07.1 et le Stockfish ARM du dépôt : les 8 tests passent (`docs/BENCHMARKS.md`).
- **Rien n'a été installé sur la liseuse.** Affichage E Ink réel, temps de réponse, mémoire, autonomie, comportement à la veille et pertinence des niveaux pour l'enfant restent à mesurer : procédure dans `docs/VALIDATION.md`, à ne lancer qu'après accord explicite.
- Maquette de l'interface (Claude Design, lien privé) : https://claude.ai/artifact/RKhQNPGaBK5HzpK1a4LCLm

## Fonctions

- Échiquier tactile en deux touches, cases carrées calculées d'après l'écran, pièces en glyphes Unicode (FreeSerif, livré avec KOReader).
- Aides visuelles : `•` pièce choisie, `○` case possible, `×` prise possible, `★` conseil ; fond plus foncé sur les deux cases du dernier coup. Le titre rappelle le dernier coup des noirs et signale l'échec.
- Promotion avec choix de pièce, roque et prise en passant via les coups légaux de Stockfish.
- Trois modes choisis à la création de la partie et rappelés en tête du titre : **Apprentissage**, avec Annuler le coup (retire la réponse de l'ordinateur et le coup de l'enfant) et Indice (Stockfish à pleine force pendant 300 ms, la pièce conseillée est sélectionnée et sa case marquée `★`) ; **Partie**, sans aide ; **Deux joueurs**, blancs et noirs à tour de rôle sur le même écran, Stockfish ne servant qu'aux règles (annulation du dernier demi-coup possible, pas de niveau ni d'indice).
- Confirmation « Oui / Non » avant de fermer, d'annuler un coup, de réclamer la nulle ou de commencer une nouvelle partie dès qu'un coup a été joué.
- Cinq niveaux, du plus faible au plus fort (tableau ci-dessous). Ce sont des noms relatifs, pas des Elo ; ils restent à calibrer avec l'enfant.
- Sauvegarde automatique (coups, niveau, mode, historique de répétitions) dans les réglages KOReader, reprise après redémarrage ; une sauvegarde corrompue est ignorée.
- Un seul thread, 8 Mo de table de hachage, aucune réflexion pendant le tour de l'enfant, sondage du moteur seulement quand il réfléchit ; processus arrêté à la fermeture, à la mise en veille, en fin de partie, et s'il ne répond plus pendant 20 s.
- Fin de partie : mat (message selon le gagnant), pat, matériel insuffisant, cinq répétitions, 75 coups ; nulle réclamable à trois répétitions ou 50 coups, l'ordinateur attendant alors la décision de l'enfant.

## Niveaux

| Niveau | Skill Level | Temps par coup | Coups au hasard |
|---|---:|---:|---:|
| Découverte | 0 | 100 ms | 60 % |
| Initiation | 0 | 150 ms | 30 % |
| Facile | 3 | 250 ms | 0 % |
| Intermédiaire | 8 | 350 ms | 0 % |
| Difficile | 15 | 500 ms | 0 % |

Le Skill Level 0 de Stockfish reste trop fort pour un débutant ; les deux premiers niveaux mélangent donc des coups légaux tirés au hasard et des coups du moteur. Les proportions se règlent en tête de `chess.koplugin/main.lua`.

## Tests

Sur Mac, avec LuaJIT et un Stockfish exécutable sur la machine (ici Stockfish 16 compilé pour macOS) :

    LUAJIT=/chemin/vers/luajit STOCKFISH=/chemin/vers/stockfish-mac ./scripts/test.sh

En émulation ARMv7 avec Docker et le paquet KOReader kobov5 décompressé :

    KOREADER_PACKAGE=/chemin/vers/koreader-kobov5-v2026.07.1/koreader ./scripts/test-arm-emulated.sh

Les cinq premiers tests n'ont pas besoin de moteur ; les trois derniers (partie contre le vrai moteur avec indice et coup au hasard, règles spéciales, arrêt pendant une recherche) exigent `STOCKFISH`.

## Installation sur la liseuse (après accord explicite)

1. Vérifier le binaire ARM dans `chess.koplugin/bin` (reconstruction : `docs/ARM.md`).
2. Suivre `docs/VALIDATION.md` : contrôles préalables, copie, essais et mesures.
3. En résumé : brancher la liseuse, vérifier que le volume est `/Volumes/eReader`, copier avec `cp -R chess.koplugin /Volumes/eReader/.adds/koreader/plugins/`, éjecter proprement, relancer KOReader, ouvrir **Outils → Plus d'outils → Échecs**.

## Licence

Code du plugin : GPL-3.0-or-later. Stockfish est sous GPL-3.0 ; si un binaire est distribué, fournir son code source correspondant, sa licence et le réseau NNUE.
