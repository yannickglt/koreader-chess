# Échecs pour KOReader

*Offline chess plugin for [KOReader](https://koreader.rocks), written for a child playing on a Tolino Vision Color (KOReader `kobov5` target, also Kobo Libra Colour hardware). Full-screen E Ink board with partial refreshes, Stockfish 16 as the engine and the rules authority, five levels from "plays at random" to Skill Level 15, learning mode with undo and hints, two-player mode, automatic save and resume. The interface is in English by default and can be switched to French in Settings. GPL-3.0-or-later; the bundled ARM Stockfish binary and GCC runtime libraries are covered in [THIRD_PARTY.md](THIRD_PARTY.md). Install: unzip the release archive into `.adds/koreader/plugins/` on the reader, restart KOReader, open Tools → More tools → Échecs.*

Plugin d'échecs hors ligne pour KOReader, pensé pour un enfant sur une Tolino Vision Color (cible KOReader `kobov5`). Contre l'ordinateur, l'enfant choisit sa couleur : il touche une pièce, les cases possibles s'affichent, il touche la destination, et Stockfish répond. À deux joueurs, les deux couleurs se jouent à tour de rôle sur le même écran. Le moteur fournit les coups légaux et la position (`go perft 1`, `d`) ; le plugin ne réimplémente pas les règles. L'interface est en anglais par défaut et passe en français dans Réglages ; les captures et descriptions ci-dessous donnent les textes français.

## État

- Le jeu fonctionne sur la Tolino Vision Color avec KOReader 2026.07.1 (essais des 30 et 31 octobre 2026). Les mesures détaillées (nombre de flashs, temps par coup aux cinq niveaux, mémoire, veille, autonomie, calibrage des niveaux avec l'enfant) restent à relever : procédure dans `docs/VALIDATION.md`, premiers relevés dans `docs/BENCHMARKS.md`.
- Validé sur Mac (LuaJIT 2.1, Stockfish 16 macOS) et dans un conteneur Linux ARMv7 émulé avec le LuaJIT, `ffi/util` et les déclarations POSIX du paquet officiel KOReader 2026.07.1 et le Stockfish ARM du dépôt : les 8 tests passent.
- D'autres liseuses KOReader devraient fonctionner si elles exécutent un ELF ARM 32 bits hard-float avec glibc 2.35 ou plus récente (cible `kobov5`) ; rien d'autre n'a été essayé.

## Fonctions

- Échiquier plein écran dessiné directement par le plugin (`chess.koplugin/boardwidget.lua`) : cases carrées calculées d'après l'écran, pièces en glyphes Unicode (FreeSerif, livré avec KOReader), repères A–H et 1–8 sur les bords (masquables dans Réglages), en-tête sur deux lignes (à qui de jouer ; mode, niveau et dernier coup en majuscules, « Noirs : B8 → C6 »).
- Rafraîchissements E Ink partiels et sans flash après l'ouverture : seules les cases, l'en-tête ou les boutons qui changent sont redessinés.
- Aides visuelles dessinées par-dessus la case, sans déplacer la pièce : cadre épais sur la pièce choisie, point sur une case libre possible, anneau autour d'une pièce prenable, étoile dans l'angle de la case conseillée ; fond plus foncé sur les deux cases du dernier coup. L'en-tête signale l'échec.
- Coup de l'ordinateur en deux temps : la pièce qu'il va jouer est d'abord encadrée, puis déplacée après 0,8 s.
- Promotion avec choix de pièce, roque et prise en passant via les coups légaux de Stockfish.
- Nouvelle partie : choix du mode puis de la couleur (blancs ou noirs ; l'échiquier est retourné quand l'enfant joue les noirs et l'ordinateur commence). Trois modes : **Apprentissage**, avec Annuler le coup (retire la réponse de l'ordinateur et le coup de l'enfant) et Indice (Stockfish à pleine force pendant 300 ms, la pièce conseillée est encadrée et sa case marquée d'une étoile) ; **Partie**, sans aide ; **Deux joueurs**, blancs et noirs à tour de rôle sur le même écran, Stockfish ne servant qu'aux règles (annulation du dernier demi-coup possible, pas de niveau ni d'indice).
- Confirmation « Oui / Non » avant de fermer, d'annuler un coup, de réclamer la nulle ou de commencer une nouvelle partie dès qu'un coup a été joué.
- Réglages : cinq niveaux du plus faible au plus fort (tableau ci-dessous), affichage des repères, langue (anglais ou français). Ce sont des noms relatifs, pas des Elo ; ils restent à calibrer avec l'enfant.
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

## Installation sur la liseuse

1. Télécharger l'archive `chess.koplugin-<version>.zip` de la [dernière release](https://github.com/yannickglt/koreader-chess/releases) et vérifier son SHA-256 (fichier `.sha256` joint), ou la construire avec `./scripts/package.sh` (binaire ARM déjà présent dans `chess.koplugin/bin`, reconstruction décrite dans `docs/ARM.md`). Chaque tag `v*` poussé sur GitHub publie automatiquement une release avec l'archive.
2. Brancher la liseuse en USB, décompresser l'archive dans `.adds/koreader/plugins/` (le dossier `chess.koplugin` est à la racine de l'archive) ou copier le dossier avec `cp -R chess.koplugin /Volumes/eReader/.adds/koreader/plugins/`. Depuis macOS, retirer ensuite les fichiers `._*` avec `dot_clean -m`.
3. Éjecter proprement, relancer KOReader, ouvrir **Tools → More tools → Chess** (ou **Outils → Plus d'outils → Échecs** une fois le français choisi dans Réglages).
4. Pour aller plus loin (mesures, veille, autonomie) : `docs/VALIDATION.md`.

## Tests

Sur Mac ou Linux, avec LuaJIT et un Stockfish exécutable sur la machine (ici Stockfish 16 compilé pour macOS) :

    LUAJIT=/chemin/vers/luajit STOCKFISH=/chemin/vers/stockfish ./scripts/test.sh

En émulation ARMv7 avec Docker et le paquet KOReader kobov5 décompressé :

    KOREADER_PACKAGE=/chemin/vers/koreader-kobov5-v2026.07.1/koreader ./scripts/test-arm-emulated.sh

Les cinq premiers tests n'ont pas besoin de moteur ; les trois derniers (partie contre le vrai moteur avec indice et coup au hasard, règles spéciales, arrêt pendant une recherche) exigent `STOCKFISH`. Le test d'interface simule l'écran de la Tolino (1264 × 1680, facteur 2,1) et vérifie les régions rafraîchies.

## Documentation

- `docs/DESIGN.md` : choix de conception, widget plein écran, marqueurs, processus moteur, garde-fous, langue.
- `docs/ARM.md` : reconstruction du binaire Stockfish ARM avec la chaîne koxtoolchain.
- `docs/BENCHMARKS.md` : résultats des tests, mesures émulées et premiers relevés sur la liseuse.
- `docs/VALIDATION.md` : liste de contrôle sur l'appareil.
- `docs/PLAN.md` : historique des étapes.

## Contribuer

Les rapports de bogue et les propositions sont bienvenus dans les issues et pull requests du dépôt. Avant d'ouvrir une pull request, lancer `scripts/test.sh` (et si possible `scripts/test-arm-emulated.sh`) et dire sur quelle liseuse le changement a été essayé, en distinguant ce qui vient de l'émulation de ce qui a été vu sur l'appareil. Pour une autre liseuse, les éléments utiles sont le résultat de `uname -m`, la version de KOReader et les lignes `chess: …` de `crash.log`.

## Licence

Code du plugin, tests et scripts : GPL-3.0-or-later (`LICENSE`). Le binaire Stockfish 16 et les bibliothèques d'exécution GCC embarqués dans `chess.koplugin/bin/` sont des composants tiers sous GPL-3.0-or-later (avec l'exception GCC Runtime Library Exception pour les bibliothèques) : `THIRD_PARTY.md` indique leur origine exacte, le code source correspondant et la procédure de compilation. Ces deux fichiers sont aussi copiés dans `chess.koplugin/` pour accompagner l'archive installable.
