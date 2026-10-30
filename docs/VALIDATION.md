# Validation sur la Tolino Vision Color

Aucune étape ci-dessous ne doit être exécutée sans accord explicite : elles modifient la liseuse ou exigent d'y ouvrir un terminal. Les résultats des tests Mac et de l'émulation ARM (`docs/BENCHMARKS.md`) ne remplacent aucune de ces mesures.

Appareil : Tolino Vision Color, firmware 5.10.225420, KOReader kobov5 2026.07.1. KOReader l'identifie par le nom de code `monzaTolino` et lui applique le profil de la Kobo Libra Colour : écran 1264 × 1680, 300 ppp, couleur Kaleido, boutons physiques, capteur d'orientation, batterie exposée dans `/sys/class/power_supply/bd71827_bat`.

## 1. Contrôles préalables

Sur le Mac, sans toucher à la liseuse :

- `file chess.koplugin/bin/stockfish` : ELF ARM 32 bits, interpréteur `/lib/ld-linux-armhf.so.3`.
- `du -sh chess.koplugin` : environ 42 Mo, dont 40 Mo pour Stockfish et son réseau NNUE.

Sur la liseuse, depuis le plugin Terminal de KOReader ou SSH (à activer seulement avec accord) :

- `uname -m` : attendu `armv7l`.
- `ls -l /lib/ld-linux-armhf.so.3` et `/lib/libc.so.6` (affiche la version, attendue ≥ 2.35, comme la chaîne kobov5).
- `free -m` et `df -h /mnt/onboard` : mémoire disponible et place pour 42 Mo.

## 2. Copie

1. Brancher la liseuse, vérifier le volume : `ls /Volumes/eReader/.adds/koreader/plugins`.
2. `cp -R chess.koplugin /Volumes/eReader/.adds/koreader/plugins/` puis `diff -r chess.koplugin /Volumes/eReader/.adds/koreader/plugins/chess.koplugin`.
3. `diskutil eject /Volumes/eReader`, puis redémarrer KOReader.
4. L'entrée se trouve dans **Outils → Plus d'outils → Échecs**.

## 3. Premier lancement

- L'échiquier apparaît-il ? Les glyphes sont-ils rendus (FreeSerif) et lisibles ? Les cases sont-elles carrées, la boîte entière sans défilement, en portrait puis en paysage ?
- Relever dans `/mnt/onboard/.adds/koreader/crash.log` les lignes `chess: moteur prêt en N ms` (lancement et chargement du réseau NNUE), `chess: coup de l'ordinateur … N ms`, `chess: conseil … N ms`.
- Si le moteur ne démarre pas : message à l'écran et erreur `Transport` ou `Stockfish` dans crash.log. Vérifier alors l'interpréteur ELF, la glibc, et que le dossier `bin` du plugin est bien ajouté à `LD_LIBRARY_PATH` par le plugin.

## 4. Jeu

- Dix coups à chaque niveau ; noter le temps ressenti par coup, le flash à chaque coup (acceptable ou non), la lisibilité des marqueurs `•`, `○`, `×`, `★` et du surlignage du dernier coup.
- Essayer roque, prise en passant, promotion, annulation, indice, réclamation de nulle, nouvelle partie, changement de niveau en cours de partie.
- Mémoire pendant une partie : `grep VmRSS /proc/$(pidof stockfish)/status`.

## 5. Veille et fermeture

- Mettre en veille pendant la réflexion de l'ordinateur, puis pendant le tour de l'enfant : au réveil la partie reprend ; pendant la veille `pidof stockfish` ne renvoie rien.
- Fermer la partie, quitter KOReader : aucun processus `stockfish` ne survit.
- Laisser la mise en veille automatique de KOReader se déclencher avec l'échiquier ouvert.

## 6. Autonomie

Deux séances de même durée et même éclairage, lecture seule puis jeu au niveau Facile. Relever `cat /sys/class/power_supply/bd71827_bat/capacity` avant et après chaque séance.

## 7. Avec l'enfant

Une partie en Découverte puis une en Initiation : gagne-t-il parfois ? Les coups de l'ordinateur paraissent-ils absurdes ou frustrants ? Les marqueurs aident-ils ? Ajuster ensuite `random`, `skill` et `movetime` dans `chess.koplugin/main.lua`.

Consigner chaque résultat dans `docs/BENCHMARKS.md`, en séparant ce qui vient de la Tolino de ce qui vient du Mac ou de l'émulation.
