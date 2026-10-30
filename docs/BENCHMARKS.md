# Vérifications et mesures locales — 30 octobre 2026

Le code a été testé sur Mac avec LuaJIT 2.1 construit localement et Stockfish 16 compilé pour macOS ARM64. La suite couvre le modèle de partie, le protocole UCI, le transport non bloquant, l'interface tactile simulée, une partie contre le vrai moteur, roque, prise en passant, les quatre promotions, les nulles réclamables et l'arrêt pendant une recherche. Les mêmes tests ont ensuite passé dans un conteneur Linux ARM 32 bits émulé avec le LuaJIT et les déclarations POSIX extraits du paquet officiel KOReader `kobov5` 2026.07.1 et le binaire Stockfish ARM préparé ici. Les glyphes d'échecs sont présents dans FreeSerif, livré avec ce paquet.

| Environnement | Commande | Résultat |
|---|---|---:|
| Mac ARM64, Stockfish 16 | `stockfish bench 8 1 6 default depth` | 43 516 nœuds, 21 ms, 2 072 190 nœuds/s |
| Linux ARMv7 émulé, Stockfish 16 | même commande | 43 516 nœuds, 352 ms, 123 625 nœuds/s |

Le chiffre ARM provient d'une **émulation sur Mac**. Il ne mesure ni la vitesse réelle de la Tolino, ni sa mémoire, ni sa batterie. Le benchmark utilise 48 positions et une profondeur fixe de 6 ; le jeu utilise des temps de recherche de 150 à 500 ms par coup. Aucun benchmark n'a été exécuté sur la liseuse.
