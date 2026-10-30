# Plan d'implémentation — 30 octobre 2026

1. Vérifier les API KOReader et Stockfish ainsi que l'architecture connue du matériel ; fixer les risques de compatibilité dans `docs/ARM.md`.
2. Écrire un parseur FEN et un état de partie testés indépendamment de KOReader, incluant promotion, répétitions et nulles.
3. Écrire le transport POSIX non bloquant et le contrôleur UCI ; tester contre un vrai Stockfish sur Mac.
4. Construire l'interface tactile KOReader avec les widgets natifs, le menu, les niveaux, la sauvegarde et les événements de veille.
5. Exécuter les tests et un benchmark local, fournir une procédure de benchmark et de déploiement sur appareil sans copier sur celui-ci.
