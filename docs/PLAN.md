# Plan d'implémentation — 30 octobre 2026

1. Vérifier les API KOReader et Stockfish ainsi que l'architecture connue du matériel ; fixer les risques de compatibilité dans `docs/ARM.md`.
2. Écrire un parseur FEN et un état de partie testés indépendamment de KOReader, incluant promotion, répétitions et nulles.
3. Écrire le transport POSIX non bloquant et le contrôleur UCI ; tester contre un vrai Stockfish sur Mac.
4. Construire l'interface tactile KOReader avec les widgets natifs, le menu, les niveaux, la sauvegarde et les événements de veille.
5. Exécuter les tests et un benchmark local, fournir une procédure de benchmark et de déploiement sur appareil sans copier sur celui-ci.

## Suite, 30 octobre 2026 soir

6. Fait et validé sur Mac et en émulation ARM : cases carrées, marqueurs, annulation, indice, niveaux Découverte et Initiation, garde-fou moteur, script `scripts/test-arm-emulated.sh`, maquette Claude Design.
7. À faire après accord : validation sur la Tolino selon `docs/VALIDATION.md` (installation, affichage, temps, mémoire, veille, autonomie, niveaux avec l'enfant).
8. Selon les mesures : ajuster hasard et temps par coup ; si le flash à chaque coup gêne, remplacer la `ButtonDialog` par un widget dédié à rafraîchissement partiel ; proposer de jouer les noirs.

## Suite, 30 octobre 2026 nuit

9. Fait : première installation sur la Tolino (plugin lancé, moteur fonctionnel) ; d'après les retours, remplacement de la `ButtonDialog` par `boardwidget.lua` (plein écran, rafraîchissements partiels, marqueurs dessinés, pause avant le coup de l'ordinateur, repères, en-tête en majuscules), choix de la couleur à la création de la partie, Réglages. Validé sur Mac et en émulation ARM.
10. À faire : réinstaller et revalider sur la Tolino (`docs/VALIDATION.md`, sections 3 et 4 : flashs, lisibilité des marqueurs, pause, repères, partie avec les noirs), relever les temps `chess: …` de `crash.log`, puis calibrer hasard et temps par coup avec l'enfant.
