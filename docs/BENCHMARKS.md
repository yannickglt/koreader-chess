# Vérifications et mesures locales — 30 octobre 2026

Le code a été testé sur Mac avec LuaJIT 2.1 construit localement et Stockfish 16 compilé pour macOS ARM64. La suite couvre le modèle de partie, le protocole UCI, le transport non bloquant, l'interface tactile simulée, une partie contre le vrai moteur, roque, prise en passant, les quatre promotions, les nulles réclamables et l'arrêt pendant une recherche. Les mêmes tests ont ensuite passé dans un conteneur Linux ARM 32 bits émulé avec le LuaJIT et les déclarations POSIX extraits du paquet officiel KOReader `kobov5` 2026.07.1 et le binaire Stockfish ARM préparé ici. Les glyphes d'échecs sont présents dans FreeSerif, livré avec ce paquet.

| Environnement | Commande | Résultat |
|---|---|---:|
| Mac ARM64, Stockfish 16 | `stockfish bench 8 1 6 default depth` | 43 516 nœuds, 21 ms, 2 072 190 nœuds/s |
| Linux ARMv7 émulé, Stockfish 16 | même commande | 43 516 nœuds, 352 ms, 123 625 nœuds/s |

Le chiffre ARM provient d'une **émulation sur Mac**. Il ne mesure ni la vitesse réelle de la Tolino, ni sa mémoire, ni sa batterie. Le benchmark utilise 48 positions et une profondeur fixe de 6 ; le jeu utilise des temps de recherche de 150 à 500 ms par coup. Aucun benchmark n'a été exécuté sur la liseuse.

## 30 octobre 2026, soir

Après l'ajout des cases carrées, des marqueurs, de l'annulation, de l'indice, des niveaux Découverte et Initiation et du garde-fou moteur. Le test d'intégration joue désormais aussi un indice et un coup au hasard contre le vrai moteur.

| Environnement | Commande | Résultat |
|---|---|---|
| Mac ARM64, LuaJIT 2.1 local, Stockfish 16 macOS compilé depuis `sf_16` | `scripts/test.sh` | 8/8 |
| Mac ARM64, Stockfish 19 macOS | `scripts/test.sh` | 8/8 |
| Linux ARMv7 émulé (Docker), LuaJIT et `ffi/posix_h.lua` du paquet kobov5 2026.07.1, Stockfish ARM du dépôt | `scripts/test-arm-emulated.sh` | 8/8 |

| Environnement | Commande | Résultat |
|---|---|---:|
| Mac ARM64, Stockfish 16 | `stockfish bench 8 1 6 default depth` | 43 516 nœuds, 20 ms, 2 175 800 nœuds/s |
| Linux ARMv7 émulé, Stockfish 16 ARM | même commande | 43 516 nœuds, 335 ms, 129 898 nœuds/s |

Le chiffre ARM vient toujours d'une **émulation sur Mac** ; la Tolino n'a pas été mesurée.

Vérifications statiques des binaires ARM (`readelf` de la chaîne kobov5, exécuté dans Docker) : `stockfish` demande GLIBC_2.34 au plus, comme le `luajit` du paquet KOReader ; la `libstdc++.so.6` du plugin demande GLIBC_2.35 et fournit GLIBCXX_3.4.33, identique à celle livrée dans `koreader/libs` ; la chaîne kobov5 est construite sur glibc 2.35. `libgcc_s.so.1` a été débarrassée de ses symboles de débogage (2,9 Mo → 100 Ko) ; `scripts/build-arm.sh` le fait désormais à la reconstruction.

### Après la revue Codex (même soir)

Corrections : champ `board_dialog` (ReaderUI transmet `dialog = ReaderUI` aux plugins), relance du moteur par un toucher quel que soit le trait, fork via `ffiUtil.runInSubProcess` avec fermeture des descripteurs hérités et `LD_LIBRARY_PATH` posé avant le fork, contrôle de cohérence de la sauvegarde, marqueur de prise en passant.

| Environnement | Commande | Résultat |
|---|---|---|
| Mac ARM64, Stockfish 16 macOS | `scripts/test.sh` | 8/8, transport en mode `fork` |
| Linux ARMv7 émulé, LuaJIT, `ffi/posix_h.lua`, `ffi/util.lua` et `libs/libkoreader-lfs.so` du paquet kobov5 2026.07.1 | `scripts/test-arm-emulated.sh` | 8/8, transport en mode `koreader` (runInSubProcess), bench 43 516 nœuds en 346 ms |

Le mode `koreader` du transport n'a été exercé qu'en émulation ; sur la Tolino, vérifier en plus que les hooks de fork du frontend (threads, descripteurs) se comportent comme prévu.

## 30 octobre 2026, nuit : premier essai sur la Tolino et widget plein écran

Installation sur la Tolino Vision Color (KOReader v2026.07.1, identifiée `Kobo_monza`, 1264 × 1680 à 300 ppp, montage `msdos`) : 10 fichiers identiques au dépôt, SHA-256 des binaires vérifiés. **Observations sur la liseuse (qualitatives, pas de chiffres relevés)** : le plugin s'ouvre, le moteur répond et les pièces sont lisibles ; la boîte de dialogue laisse une marge autour du jeu ; trop de flashs ; les marqueurs en préfixe décalent la pièce et exigent un rafraîchissement ; le coup de l'ordinateur apparaît déjà joué ; il manque les repères et le choix de la couleur. Ces retours ont motivé le widget plein écran (`docs/DESIGN.md`). Les temps `chess: …` du journal n'ont pas encore été relevés.

Après le remplacement de la `ButtonDialog` par `boardwidget.lua` (rafraîchissements partiels, marqueurs dessinés, pause de l'ordinateur, couleur, repères) :

| Environnement | Commande | Résultat |
|---|---|---|
| Mac ARM64, LuaJIT 2.1 local, Stockfish 16 macOS | `scripts/test.sh` | 8/8, transport `fork` |
| Linux ARMv7 émulé (Docker), LuaJIT, `ffi/posix_h.lua`, `ffi/util.lua` du paquet kobov5 2026.07.1, Stockfish ARM du dépôt | `scripts/test-arm-emulated.sh` | 8/8, transport `koreader`, bench 43 516 nœuds en 314 ms (138 585 nœuds/s) |

Le test d'interface vérifie, sur la géométrie simulée de la Tolino (cases de 147 px, échiquier de 1176 px, bande de 42 px), qu'une sélection ne rafraîchit que la boîte englobante des cases touchées, qu'un coup ne provoque aucun rendu avant la confirmation du moteur, et que l'ouverture est le seul rafraîchissement complet. Le nombre réel de flashs, la lisibilité des marqueurs dessinés et la durée des mises à jour partielles sur Kaleido restent **à mesurer sur la Tolino**.

### Premiers temps relevés sur la Tolino (journal `crash.log`, 30 octobre 2026, 22 h 41 – 22 h 44)

Mesures **réelles**, première version (ButtonDialog), niveau avec coups au hasard (Découverte ou Initiation, temps demandé 100 à 150 ms par recherche) :

| Ligne du journal | Valeur |
|---|---:|
| `chess: moteur prêt` (lancement de Stockfish et chargement du réseau NNUE) | 848 ms puis 796 ms |
| `chess: coup de l'ordinateur … (search)` : sept recherches | 902 à 1 047 ms |
| `chess: coup de l'ordinateur … (random)` : trois coups | 0 ms |

Le temps de recherche mesuré par le plugin (de l'envoi de `go movetime` à la lecture de `bestmove`) est six à dix fois supérieur au temps demandé. Il inclut l'attente du sondage (50 ms) et surtout le temps pendant lequel la boucle d'interface KOReader est occupée : avec la ButtonDialog, la reconstruction et le rafraîchissement complet de la boîte suivaient immédiatement le coup de l'enfant, pendant la recherche, et Stockfish tourne en `SCHED_BATCH` à priorité réduite. À remesurer avec le widget plein écran (rafraîchissement partiel de deux cases et de l'en-tête) avant d'incriminer le processeur. Aucune erreur ni trace du plugin dans le journal.
