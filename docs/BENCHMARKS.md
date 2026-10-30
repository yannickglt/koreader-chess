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
