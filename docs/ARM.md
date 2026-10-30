# Binaire ARM pour Tolino Vision Color

La fiche officielle du Tolino Vision Color indique un MediaTek MTK8113T à deux cœurs ARM A53. La cible KOReader `kobov5` utilise la chaîne officielle `arm-kobov5-linux-gnueabihf`, donc un exécutable **ELF ARM 32 bits hard-float** est le meilleur candidat. Un processeur A53 peut aussi exécuter du 64 bits, mais cela ne prouve pas que ce firmware fournisse un chargeur et des bibliothèques 64 bits. La version du chargeur ELF et de la libc doit encore être vérifiée sur l'appareil avant installation.

## Version retenue

Stockfish 16, tag officiel `sf_16`, commit `68e1e9b3811e16cad014b590d7443b9063b3eb52`, réseau officiel `nn-5af11540bbfe.nnue` (environ 39 Mio). La version 19 compilée sur Mac embarquait environ 109 Mio de réseau, ce qui augmente sensiblement la mémoire nécessaire. Stockfish 16 conserve `Skill Level`, `go perft 1`, `d` et les coups UCI requis. Le moteur reste très fort au réglage minimal ; les noms des quatre niveaux décrivent une progression relative et exigent un essai réel avec l'enfant. Le candidat compilé utilise `/lib/ld-linux-armhf.so.3`, comme le LuaJIT du paquet officiel KOReader 2026.07.1. Le plugin fournit `libatomic.so.1`, `libstdc++.so.6` et `libgcc_s.so.1` dans son propre dossier ; elles ne remplacent pas les bibliothèques de KOReader.

## Reconstruction sur Mac

1. Télécharger les sources officielles : `git clone --branch sf_16 --depth 1 https://github.com/official-stockfish/Stockfish.git stockfish-sf16`.
2. Dans `stockfish-sf16/src`, lancer `make net` pour obtenir et vérifier `nn-5af11540bbfe.nnue`.
3. Télécharger `kobov5.tar.zst` depuis la [release 2026.08 de koxtoolchain](https://github.com/koreader/koxtoolchain/releases/tag/2026.08), puis l'extraire. Le dossier attendu est `x-tools/arm-kobov5-linux-gnueabihf`.
4. Depuis la racine de ce dépôt, lancer `STOCKFISH_SOURCE=/chemin/absolu/stockfish-sf16 KOBOV5_TOOLCHAIN=/chemin/absolu/x-tools/arm-kobov5-linux-gnueabihf ./scripts/build-arm.sh`.
5. Vérifier avec `file chess.koplugin/bin/stockfish` que le résultat est bien un ELF ARM. Le script affiche aussi son SHA-256.

Le binaire Mac, même ARM64, ne fonctionne pas sur la liseuse. Avant la copie autorisée, contrôler sur l'appareil `uname -m`, `file`/`readelf -l` du binaire et la présence de l'interpréteur ELF indiqué. Si un lancement échoue, lire le journal KOReader et ajuster la compilation ; ne pas remplacer la libc du firmware.

## Mesures à faire sur la Tolino, après autorisation

- Exécuter `STOCKFISH=/chemin/vers/stockfish ./scripts/benchmark.sh` dans un shell adapté (ou directement `stockfish bench 8 1 6 default depth`) ; conserver durée et nœuds par seconde.
- Jouer dix coups à chacun des quatre niveaux, relever le temps visible de réponse et la mémoire maximale du processus (`/proc/<pid>/status`, ligne `VmRSS`).
- Mettre en veille pendant une recherche puis pendant le tour de l'enfant ; vérifier que le processus Stockfish a disparu, que KOReader se suspend et que la partie reprend.
- Comparer la batterie sur une séance de lecture seule et une séance de jeu de même durée, avec éclairage identique. Une mesure sur Mac ne prédit pas la consommation de l'appareil.

Sources : [KOReader kobov5](https://github.com/koreader/koreader-base/blob/master/README.md), [chaîne de compilation](https://github.com/koreader/koxtoolchain/blob/master/refs/x-compile.sh), [Stockfish 16](https://github.com/official-stockfish/Stockfish/tree/sf_16), [fiche Tolino Vision Color](https://mytolino.com/wp-content/uploads/2026/01/ENG-2026_01-Datasheet-tolino-vision-color.pdf).
