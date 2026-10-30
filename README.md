# Échecs pour KOReader (MVP local)

Plugin d'échecs hors ligne pour KOReader, destiné à une Tolino Vision Color. Le joueur joue les blancs, touche une pièce puis sa destination, et Stockfish répond. Le moteur fournit les coups légaux et les positions via ses commandes `go perft 1` et `d` ; le plugin n'essaie pas de reproduire les règles de déplacement.

## État

Ce dépôt est un MVP **à valider sur appareil**. Le dossier local `chess.koplugin/bin` contient un binaire Stockfish 16 Linux ARM 32 bits et ses trois bibliothèques de support. Ils ont passé les tests dans un conteneur ARM émulé avec le LuaJIT du paquet KOReader 2026.07.1, mais leur lancement et leurs performances sur le firmware 5.10.225420 restent à vérifier. Les binaires sont ignorés par Git : après un clonage du dépôt, les reconstruire avec `scripts/build-arm.sh`. Aucun fichier n'a été copié vers la liseuse.

## Fonctions

- Échiquier tactile à deux touches, promotions avec choix de pièce, roque et prise en passant par les coups légaux de Stockfish.
- Quatre niveaux, avec `Skill Level` et un temps de recherche borné. Ce sont des niveaux relatifs, **pas des Elo certifiés** ; le mode débutant reste à calibrer avec un enfant.
- Sauvegarde automatique dans le répertoire de réglages KOReader, reprise après redémarrage.
- Un seul thread, 8 Mo de hash, aucune réflexion pendant le tour humain ; processus arrêté à la fermeture du jeu et à la mise en veille.
- Fin de partie : mat, pat, matériel insuffisant, cinq répétitions ou 75 coups automatiquement ; bouton pour réclamer la nulle à trois répétitions ou 50 coups.

## Installation sur Mac (après validation de la version ARM)

1. Vérifier que le candidat est présent dans `chess.koplugin/bin` ; après un clonage, le reconstruire selon `docs/ARM.md`.
2. Exécuter les tests Mac avec un **Stockfish Mac** : `LUAJIT=/chemin/vers/luajit STOCKFISH=/chemin/vers/stockfish-mac ./scripts/test.sh`. La validation ARM émulée est décrite dans `docs/BENCHMARKS.md`.
3. Après accord explicite pour toucher à la liseuse, brancher celle-ci et vérifier que le volume est `/Volumes/eReader`.
4. Copier le dossier entier, bibliothèques comprises : `cp -R chess.koplugin /Volumes/eReader/.adds/koreader/plugins/`.
5. Éjecter proprement le volume, relancer KOReader, puis ouvrir **Outils → Échecs**.

Le chemin indiqué est celui demandé ; KOReader doit déjà être présent. Il faut valider la présence de l'entrée « Échecs », chaque niveau, les règles spéciales et la mise en veille sur l'appareil avant de considérer ce plugin comme prêt pour l'enfant.

## Licence

Code du plugin : GPL-3.0-or-later. Stockfish est sous GPL-3.0 ; si un binaire est distribué, fournir son code source correspondant, sa licence et les réseaux NNUE nécessaires.
