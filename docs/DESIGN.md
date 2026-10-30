# Conception du MVP — 30 octobre 2026

Le joueur est un enfant qui doit pouvoir jouer seul, hors ligne et sans contrainte de notation. La liseuse reste utilisable pour la lecture et doit pouvoir se mettre en veille normalement.

## Choix

Le plugin Lua s'intègre au menu KOReader. Il lance un processus Stockfish séparé et lui parle par tubes POSIX non bloquants. Une recherche n'a lieu que pour le coup de l'ordinateur. Stockfish sert aussi d'autorité pour les coups légaux (`go perft 1`) et le FEN (`d`), ce qui couvre notamment roque, promotion, prise en passant et l'interdiction de laisser son roi en échec. Le plugin suit les conditions de nulle à partir du FEN.

Autres approches examinées : réécrire les règles en Lua (doublon fragile) ; bloquer l'interface avec `io.popen`/`os.execute` (mauvaise réactivité et risque à la veille). Les commandes `perft` et `d` sont des extensions Stockfish et l'intégration est donc volontairement liée à une version Stockfish vérifiée.

## Limites à mesurer

L'ARM Cortex-A53 du Tolino ne révèle pas à lui seul l'ABI du firmware. Ne pas choisir un binaire ARM64 sans vérification de `uname -m`, du chargeur ELF et de la libc sur l'appareil. Le temps par coup et la force perçue seront mesurés sur la Tolino. Le Mac ne peut prouver ni la qualité de l'affichage E Ink, ni l'autonomie, ni la réaction réelle à la veille.

## Évolutions du 30 octobre 2026, soir

### Interface

L'échiquier reste une `ButtonDialog` KOReader : 64 boutons identifiés par leur case et deux rangées de commandes. Les cases sont carrées : leur côté est déduit de la largeur (96 % de l'écran) ou de la hauteur (moins la place du titre et des deux rangées), ce qui garde la boîte entière sans défilement en portrait comme en paysage. La taille des glyphes suit la case (0,57 × côté, convertie en points KOReader).

Les marqueurs de sélection, de cases possibles et de conseil sont des préfixes de texte (`•`, `○`, `×`, `★`) posés par `setText` puis `refresh` sur les seuls boutons concernés : rafraîchissement partiel, sans reconstruire la boîte. Le dernier coup est surligné par le fond `COLOR_GRAY_9`, appliqué lors de la reconstruction qui suit chaque coup. Une signature de ce qui s'affiche évite de reconstruire la boîte quand rien ne change (reprise après veille, changement de niveau au tour de l'enfant), et le coup de l'enfant n'est rendu qu'une fois la position confirmée par le moteur : un seul rafraîchissement complet par demi-coup. Fermer puis rouvrir une `ButtonDialog` provoque un rafraîchissement avec flash sur sa zone ; c'est le comportement standard de KOReader contre les images fantômes, à juger sur l'appareil.

### Niveaux

Stockfish 16 ne descend pas sous Skill Level 0, trop fort pour un enfant qui découvre le jeu. Les niveaux « Découverte » et « Initiation » tirent donc un coup légal au hasard avec une probabilité fixée (60 % et 30 %) et jouent sinon le coup du moteur à Skill Level 0. Un coup tiré au hasard ne coûte aucune recherche. Les autres niveaux n'utilisent que Skill Level et un temps borné. L'indice pose temporairement Skill Level 20, cherche 300 ms, puis revient au niveau courant.

### Répétitions et annulation

L'historique de répétition est une liste de clés indexée par demi-coup (`keys[i]` est la position après `i − 1` coups). Mettre à jour deux fois le même demi-coup n'augmente pas le compte, et annuler se résume à tronquer la liste. Le format sauvegardé est `{moves, level, mode, keys, claimed_draw}` ; une liste de coups invalide repart d'une partie vide.

### Modes

Une nouvelle partie commence par le choix entre « Apprentissage » (Annuler le coup et Indice disponibles), « Partie » (aucune aide ; la deuxième rangée ne garde que la réclamation de nulle) et « Deux joueurs » (blancs et noirs sur le même écran, échiquier fixe avec les blancs en bas). Le mode est fixé pour toute la partie, sauvegardé avec elle et rappelé en tête du titre. L'annulation est un retour en arrière, pas une désélection : c'est une aide d'apprentissage, donc absente du mode Partie ; à deux joueurs elle retire un seul demi-coup, d'un commun accord.

À deux joueurs, Stockfish reste lancé pour fournir les coups légaux et la position, mais ne cherche jamais : `acceptPosition` refuse la recherche quel que soit le trait, le processus reste inactif entre les coups. Le bouton de niveau disparaît, le titre indique à qui de jouer et le dernier coup, et la fin de partie nomme la couleur gagnante.

### Confirmations

Fermer, Annuler le coup, Réclamer la nulle et Nouvelle partie (dès qu'un coup a été joué) passent par une `ConfirmBox` avec les réponses « Oui » et « Non », pour qu'un tapotement maladroit ne fasse rien perdre. Le choix du niveau et l'indice n'en ont pas : ils ne perdent rien. L'échiquier à sa position de départ démarre une nouvelle partie sans question.

### Processus moteur

Dans KOReader, Stockfish est lancé par `ffiUtil.runInSubProcess`, qui exécute les hooks du frontend avant et après `fork()` (arrêt des threads susceptibles de tenir un verrou malloc) et place le fils à basse priorité ; hors KOReader, fork direct. Entre fork et exec, le fils relie la socket à stdin/stdout et ferme tous les autres descripteurs hérités (écran, tactile, fichiers, réseau). `LD_LIBRARY_PATH` est posé dans le parent juste avant le fork et restauré aussitôt après, pour que le fils n'alloue rien avant `execv`. Le plugin garde un champ `board_dialog` et non `dialog` : depuis un livre, ReaderUI transmet `dialog = ReaderUI` aux plugins, et le fermer fermerait le lecteur.

### Garde-fous

Le sondage du moteur (50 ms) ne tourne que quand une réponse est attendue ; au-delà de 20 s sans réponse, le processus est arrêté et un message invite à toucher l'échiquier pour le relancer, quel que soit le trait. À la reprise d'une sauvegarde, la première position reçue est comparée à la liste des coups (trait et numéro de coup) : Stockfish ignore en silence un coup illégal, et une liste incohérente repart sur une nouvelle partie avec un message. Les clés de répétition sauvegardées sont reprises telles quelles ; si elles manquent, le compte repart de la position courante. Les temps de démarrage, de recherche et de conseil sont écrits dans le journal KOReader (lignes `chess: …`) pour les mesures sur l'appareil.

### Maquette

Maquette Claude Design des écrans de jeu, de choix du niveau et de fin de partie, plus le composant échiquier : https://claude.ai/artifact/RKhQNPGaBK5HzpK1a4LCLm (lien privé). Elle reprend la boîte KOReader en niveaux de gris à la résolution de l'écran ; elle ne remplace pas l'essai sur E Ink.
