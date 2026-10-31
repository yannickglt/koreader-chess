# Composants tiers embarqués

Ce dépôt et l'archive installable contiennent, dans `chess.koplugin/bin/`, des binaires compilés pour la cible KOReader `kobov5` (ARM 32 bits hard-float). Ils proviennent de projets libres dont les licences imposent de fournir le code source correspondant ; voici où le trouver et comment ces binaires ont été produits.

## Stockfish 16

- Fichier : `chess.koplugin/bin/stockfish` (le réseau d'évaluation NNUE `nn-5af11540bbfe.nnue` y est incorporé).
- Licence : GNU General Public License version 3 ou ultérieure (le fichier `Copying.txt` de Stockfish est le texte de la GPL v3, reproduit ici dans `LICENSE`).
- Auteurs : l'équipe Stockfish, https://stockfishchess.org (fichier `AUTHORS` du dépôt Stockfish).
- Code source correspondant : tag officiel `sf_16`, commit `68e1e9b3811e16cad014b590d7443b9063b3eb52`, **sans aucune modification** :
  https://github.com/official-stockfish/Stockfish/tree/sf_16 (archive : https://github.com/official-stockfish/Stockfish/archive/refs/tags/sf_16.tar.gz).
- Réseau NNUE : fichier officiel `nn-5af11540bbfe.nnue` téléchargé par `make net` depuis les serveurs du projet Stockfish (https://tests.stockfishchess.org/nns), incorporé tel quel.
- Compilation : `make build ARCH=armv7-neon KERNEL=Linux COMP=gcc` avec la chaîne `arm-kobov5-linux-gnueabihf` de koxtoolchain 2026.08 (GCC 14.4.0, glibc 2.35), puis `strip`. La procédure exacte est dans `scripts/build-arm.sh` et `docs/ARM.md` ; elle permet de reconstruire un binaire identique en fonction.

## Bibliothèques d'exécution GCC

- Fichiers : `chess.koplugin/bin/libstdc++.so.6`, `chess.koplugin/bin/libgcc_s.so.1`, `chess.koplugin/bin/libatomic.so.1` (symboles de débogage retirés).
- Origine : GCC 14.4.0 construit par crosstool-NG dans koxtoolchain (https://github.com/koreader/koxtoolchain, release 2026.08, chaîne `arm-kobov5-linux-gnueabihf`).
- Licence : GNU General Public License version 3 ou ultérieure, avec l'exception GCC Runtime Library Exception version 3.1 (https://www.gnu.org/licenses/gcc-exception-3.1.html).
- Code source : https://gcc.gnu.org/ (gcc-14.4.0) ; recette de la chaîne : https://github.com/koreader/koxtoolchain.

## Dépendances non redistribuées

- KOReader (https://github.com/koreader/koreader, AGPL-3.0) : le plugin s'exécute dans KOReader et utilise ses widgets, son LuaJIT et sa police FreeSerif (GNU FreeFont, GPL v3 avec exception pour les polices). Rien de KOReader n'est copié dans ce dépôt.
- Le code du plugin lui-même (`chess.koplugin/*.lua`, `tests/`, `scripts/`) est sous GPL-3.0-or-later, voir `LICENSE`.

## In English

`chess.koplugin/bin/stockfish` is an unmodified build of Stockfish 16 (tag `sf_16`, commit `68e1e9b3811e16cad014b590d7443b9063b3eb52`, GPL-3.0-or-later) with the official `nn-5af11540bbfe.nnue` network embedded, compiled with `ARCH=armv7-neon` and the koxtoolchain 2026.08 `arm-kobov5-linux-gnueabihf` toolchain (GCC 14.4.0, glibc 2.35) as described in `scripts/build-arm.sh`. The corresponding source is at https://github.com/official-stockfish/Stockfish/tree/sf_16. The three shared libraries are the GCC 14.4.0 runtime (GPL-3.0-or-later with the GCC Runtime Library Exception 3.1) taken from that toolchain. The plugin code is GPL-3.0-or-later.
