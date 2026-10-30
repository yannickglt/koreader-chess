# Conception du MVP — 30 octobre 2026

Le joueur est un enfant qui doit pouvoir jouer seul, hors ligne et sans contrainte de notation. La liseuse reste utilisable pour la lecture et doit pouvoir se mettre en veille normalement.

## Choix

Le plugin Lua s'intègre au menu KOReader. Il lance un processus Stockfish séparé et lui parle par tubes POSIX non bloquants. Une recherche n'a lieu que pour le coup de l'ordinateur. Stockfish sert aussi d'autorité pour les coups légaux (`go perft 1`) et le FEN (`d`), ce qui couvre notamment roque, promotion, prise en passant et l'interdiction de laisser son roi en échec. Le plugin suit les conditions de nulle à partir du FEN.

Autres approches examinées : réécrire les règles en Lua (doublon fragile) ; bloquer l'interface avec `io.popen`/`os.execute` (mauvaise réactivité et risque à la veille). Les commandes `perft` et `d` sont des extensions Stockfish et l'intégration est donc volontairement liée à une version Stockfish vérifiée.

## Limites à mesurer

L'ARM Cortex-A53 du Tolino ne révèle pas à lui seul l'ABI du firmware. Ne pas choisir un binaire ARM64 sans vérification de `uname -m`, du chargeur ELF et de la libc sur l'appareil. Le temps par coup et la force perçue seront mesurés sur la Tolino. Le Mac ne peut prouver ni la qualité de l'affichage E Ink, ni l'autonomie, ni la réaction réelle à la veille.
