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

Faite une première fois le 30 octobre 2026 au soir (volume `/Volumes/eReader`, montage `msdos`, KOReader v2026.07.1, 26 Go libres) ; à refaire pour chaque nouvelle version.

1. Brancher la liseuse, vérifier le volume : `ls /Volumes/eReader/.adds/koreader/plugins`.
2. `cp -R chess.koplugin /Volumes/eReader/.adds/koreader/plugins/` puis `diff -r chess.koplugin /Volumes/eReader/.adds/koreader/plugins/chess.koplugin` ; macOS ajoute des fichiers `._*` sur un volume FAT, à retirer avec `dot_clean -m /Volumes/eReader/.adds/koreader/plugins/chess.koplugin`.
3. `diskutil eject /Volumes/eReader`, puis redémarrer KOReader.
4. L'entrée se trouve dans **Outils → Plus d'outils → Échecs**.

## 3. Premier lancement

- Ouvrir Échecs depuis le gestionnaire de fichiers, puis depuis un livre ouvert : dans les deux cas, fermer l'échiquier puis fermer le livre doit laisser KOReader intact (le plugin reçoit `dialog = ReaderUI` depuis un livre).
- L'échiquier apparaît-il, plein écran, sans marge de boîte de dialogue ? Les glyphes sont-ils rendus (FreeSerif) et lisibles ? Les cases sont-elles carrées, les repères A–H et 1–8 lisibles, l'en-tête sur deux lignes, en portrait puis en paysage (rotation pendant que l'échiquier est ouvert) ?
- Compter les flashs : un seul à l'ouverture, un à la fermeture ; aucun pendant une sélection, un coup de l'enfant, un coup de l'ordinateur. Noter la durée visible des mises à jour partielles (cases, en-tête) sur l'écran Kaleido et les images fantômes éventuelles après une dizaine de coups.
- Relever dans `/mnt/onboard/.adds/koreader/crash.log` les lignes `chess: moteur prêt en N ms` (lancement et chargement du réseau NNUE), `chess: coup de l'ordinateur … N ms`, `chess: conseil … N ms`.
- Si le moteur ne démarre pas ou cesse de répondre : message à l'écran, titre « Moteur arrêté · touchez l'échiquier », erreur `Transport` ou `Stockfish` dans crash.log ; un toucher sur l'échiquier doit le relancer, quel que soit le trait.
- `ls -l /proc/$(pidof stockfish)/fd` : seuls 0, 1 (la socket) et 2 doivent être ouverts, aucun descripteur d'écran, de tactile ni de fichier KOReader. Vérifier alors l'interpréteur ELF, la glibc, et que le dossier `bin` du plugin est bien ajouté à `LD_LIBRARY_PATH` par le plugin.

## 4. Jeu

- Dix coups à chaque niveau ; noter le temps ressenti par coup, la lisibilité des marqueurs dessinés (cadre, point, anneau, étoile) et du surlignage du dernier coup, et si la pause de 0,8 s entre la pièce encadrée par l'ordinateur et son déplacement convient à l'enfant (`COMPUTER_PAUSE` dans `main.lua`).
- Jouer une partie avec les noirs : l'ordinateur ouvre, l'échiquier est retourné (repères 1 en haut, H à gauche), les touchers tombent sur la bonne case. Stockfish tourne en `SCHED_BATCH` à priorité réduite (héritage de `runInSubProcess`) : comparer les temps du journal (`chess: coup de l'ordinateur … N ms`) au temps demandé (100 à 500 ms selon le niveau), en particulier pendant un rafraîchissement d'écran.
- Essayer roque, prise en passant, promotion, annulation, indice, réclamation de nulle, nouvelle partie (mode puis couleur), changement de niveau et masquage des repères dans Réglages en cours de partie.
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
