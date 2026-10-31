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

Une maquette Claude Design (privée, non publiée) des écrans de jeu, des réglages, du choix du mode et de la couleur, de la partie avec les noirs, du mode deux joueurs, de la fin de partie et des confirmations, plus le composant échiquier, a servi à fixer la disposition. Elle reprend la boîte KOReader en niveaux de gris à la résolution de l'écran ; elle ne remplace pas l'essai sur E Ink.

## Retours de la Tolino, 30 octobre 2026, nuit

Première version essayée sur la liseuse : le plugin s'ouvre et joue, mais la `ButtonDialog` laisse une marge autour de l'échiquier, chaque demi-coup provoque un flash (fermeture de la boîte en `flashui`, clignotement des boutons au toucher), les marqueurs en préfixe de texte décalent la pièce, le coup de l'ordinateur apparaît déjà joué, et il manque les repères, le choix de la couleur et des cases en majuscules dans l'en-tête. La section « Interface » ci-dessus décrit donc l'ancienne approche ; voici la nouvelle.

### Widget plein écran

`boardwidget.lua` est un `InputContainer` qui couvre tout l'écran (`covers_fullscreen`) et dessine lui-même, dans le tampon d'écran : un en-tête de deux lignes (`tfont` 24 pt pour « À vous de jouer », `cfont` 17 pt pour « Apprentissage · Facile · Noirs : B8 → C6 »), l'échiquier aux cases carrées entouré d'une bande de 20 pt pour les repères, et deux rangées de boutons tracés par le widget (cadre arrondi, texte grisé quand inactif), sans le clignotement du `Button` KOReader. Les pièces sont des `TextWidget` en FreeSerif, mis en cache par glyphe. Les touchers sont résolus par géométrie : case ou bouton. La disposition est recalculée si la taille d'écran change (rotation).

Le plugin ne manipule plus de boutons : `Chess:view()` produit un état (lignes d'en-tête, 64 cases avec pièce, marqueur, dernier coup, étoile, orientation, repères, boutons) et `BoardWidget:setView` compare cet état au précédent. Il ne demande que des rafraîchissements partiels en mode « ui » (sans flash) : l'en-tête, la boîte englobante des cases modifiées, la zone des boutons ; tout l'écran si l'orientation ou les repères changent ; rien si rien ne change. Seuls l'ouverture (« full ») et la fermeture (« flashui », contre les images fantômes) flashent. Sur l'écran Kaleido, KOReader n'applique les formes d'onde couleur qu'aux mises à jour tramées ; nos « ui » restent des mises à jour partielles en niveaux de gris.

### Marqueurs

Dessinés par-dessus la case, la pièce ne bouge pas : cadre épais noir (côté/16) pour la pièce choisie, point plein (rayon côté/8) pour une case libre, anneau (rayon côté/2) autour d'une pièce prenable, y compris en passant, petite étoile dans l'angle supérieur droit de la case conseillée (la pièce conseillée est encadrée). Les deux cases du dernier coup gardent le fond `COLOR_GRAY_9`.

### Coup de l'ordinateur en deux temps

`engineMoved` encadre d'abord la pièce que l'ordinateur va jouer (rafraîchissement d'une case) et programme `applyPendingMove` 0,8 s plus tard ; le coup n'est ajouté à la partie et envoyé au moteur qu'à ce moment. Fermer, mettre en veille ou arrêter le moteur pendant la pause oublie le coup en attente : la partie reste cohérente et l'ordinateur rejouera au réveil. Le moteur ne décide plus de chercher d'après le trait du FEN : `on_position` renvoie vrai quand c'est à l'ordinateur de jouer (couleur de l'enfant, pas de nulle à trancher).

### Couleur, repères, en-tête

Nouvelle partie : mode, puis « Vos pièces » (blancs ou noirs) sauf à deux joueurs. `game.color` est sauvegardé ; l'échiquier est retourné quand l'enfant a les noirs (repères inversés, touchers résolus dans l'orientation affichée) et l'ordinateur ouvre la partie. Les repères A–H et 1–8 se masquent dans Réglages (réglage `coords`, hors de la partie) ; Réglages regroupe aussi les niveaux. L'en-tête écrit les cases en majuscules et nomme la couleur qui vient de jouer ; une promotion précise la pièce.


### Langue

L'interface est en anglais par défaut et passe en français depuis Réglages (réglage `language` du plugin, indépendant de la langue de KOReader). `i18n.lua` garde les chaînes anglaises comme clés et un catalogue français ; `main.lua` passe chaque texte affiché par `T()`, les textes à paramètre étant formatés après traduction. Les identifiants internes (niveaux, modes, clés de sauvegarde) ne changent pas avec la langue. L'entrée de menu KOReader est construite au démarrage : elle change de langue au lancement suivant. La maquette montre les textes français.
