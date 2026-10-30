# Échecs pour KOReader

Plugin d'échecs hors ligne pour KOReader, pensé pour un enfant sur une Tolino Vision Color (cible KOReader `kobov5`). Contre l'ordinateur, l'enfant choisit sa couleur : il touche une pièce, les cases possibles s'affichent, il touche la destination, et Stockfish répond. À deux joueurs, les deux couleurs se jouent à tour de rôle sur le même écran. Le moteur fournit les coups légaux et la position (`go perft 1`, `d`) ; le plugin ne réimplémente pas les règles.

## État au 30 octobre 2026, nuit

- Validé sur Mac (LuaJIT 2.1, Stockfish 16 macOS) et dans un conteneur Linux ARMv7 émulé avec le LuaJIT, `ffi/util` et les déclarations POSIX du paquet officiel KOReader 2026.07.1 et le Stockfish ARM du dépôt : les 8 tests passent (`docs/BENCHMARKS.md`).
- Première version installée et lancée sur la Tolino le 30 octobre au soir : le plugin s'ouvre, le moteur répond, les pièces sont lisibles. Les défauts relevés (boîte de dialogue qui ne remplit pas l'écran, flashs trop nombreux, marqueurs qui décalent la pièce, coup de l'ordinateur sans temps de pause, pas de repères ni de choix de couleur) ont conduit à la version actuelle, **pas encore essayée sur la liseuse** : procédure dans `docs/VALIDATION.md`.
- Maquette de l'interface (Claude Design, lien privé) : https://claude.ai/artifact/RKhQNPGaBK5HzpK1a4LCLm

## Fonctions

- Échiquier plein écran dessiné directement par le plugin (`chess.koplugin/boardwidget.lua`) : cases carrées calculées d'après l'écran, pièces en glyphes Unicode (FreeSerif, livré avec KOReader), repères A–H et 1–8 sur les bords (masquables dans Réglages), en-tête sur deux lignes (à qui de jouer ; mode, niveau et dernier coup en majuscules, « Noirs : B8 → C6 »).
- Rafraîchissements E Ink partiels et sans flash après l'ouverture : seules les cases, l'en-tête ou les boutons qui changent sont redessinés.
- Aides visuelles dessinées par-dessus la case, sans déplacer la pièce : cadre épais sur la pièce choisie, point sur une case libre possible, anneau autour d'une pièce prenable, étoile dans l'angle de la case conseillée ; fond plus foncé sur les deux cases du dernier coup. L'en-tête signale l'échec.
- Coup de l'ordinateur en deux temps : la pièce qu'il va jouer est d'abord encadrée, puis déplacée après 0,8 s.
- Promotion avec choix de pièce, roque et prise en passant via les coups légaux de Stockfish.
- Nouvelle partie : choix du mode puis de la couleur (blancs ou noirs ; l'échiquier est retourné quand l'enfant joue les noirs et l'ordinateur commence). Trois modes : **Apprentissage**, avec Annuler le coup (retire la réponse de l'ordinateur et le coup de l'enfant) et Indice (Stockfish à pleine force pendant 300 ms, la pièce conseillée est encadrée et sa case marquée d'une étoile) ; **Partie**, sans aide ; **Deux joueurs**, blancs et noirs à tour de rôle sur le même écran, Stockfish ne servant qu'aux règles (annulation du dernier demi-coup possible, pas de niveau ni d'indice).
- Confirmation « Oui / Non » avant de fermer, d'annuler un coup, de réclamer la nulle ou de commencer une nouvelle partie dès qu'un coup a été joué.
- Cinq niveaux, du plus faible au plus fort (tableau ci-dessous), dans Réglages. Ce sont des noms relatifs, pas des Elo ; ils restent à calibrer avec l'enfant.
- Sauvegarde automatique (coups, niveau, mode, couleur, historique de répétitions) dans les réglages KOReader à chaque coup et à la fermeture ; la partie reprend à l'ouverture suivante, y compris après un redémarrage. Une sauvegarde corrompue est ignorée.
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

Les cinq premiers tests n'ont pas besoin de moteur ; les trois derniers (partie contre le vrai moteur avec indice et coup au hasard, règles spéciales, arrêt pendant une recherche) exigent `STOCKFISH`. Le test d'interface simule l'écran de la Tolino (1264 × 1680, facteur 2,1) et vérifie les régions rafraîchies.

## Installation sur la liseuse

1. Vérifier le binaire ARM dans `chess.koplugin/bin` (reconstruction : `docs/ARM.md`).
2. Construire l'archive : `./scripts/package.sh` produit `dist/chess.koplugin-<date>-<commit>.zip` et son SHA-256, à décompresser dans `.adds/koreader/plugins/` (le dossier `chess.koplugin` est à la racine de l'archive).
3. Suivre `docs/VALIDATION.md` : contrôles préalables, copie, essais et mesures.
4. En résumé : brancher la liseuse, vérifier que le volume est `/Volumes/eReader`, décompresser l'archive ou copier avec `cp -R chess.koplugin /Volumes/eReader/.adds/koreader/plugins/`, supprimer les fichiers `._*` créés par macOS (`dot_clean -m`), éjecter proprement, relancer KOReader, ouvrir **Outils → Plus d'outils → Échecs**.

## Licence

Code du plugin : GPL-3.0-or-later. Stockfish est sous GPL-3.0 ; si un binaire est distribué, fournir son code source correspondant, sa licence et le réseau NNUE.
