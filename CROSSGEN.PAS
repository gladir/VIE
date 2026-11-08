{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @version: 1.00
  @website(https://www.gladir.com/vie)
  @abstract(Target: Turbo Pascal 7, Free Pascal)
  @description: Crossword Generator - generateur de mots croises

  Programme en ligne de commande qui lit une liste de mots (fichier texte,
  un mot par ligne, avec un indice facultatif : MOT;indice) et construit
  une grille de mots croises.

   - Plusieurs essais aleatoires : la meilleure grille est conservee
   - Accents supprimes automatiquement (UTF-8, Latin-1 ou CP437)
   - Sorties : texte (ASCII ou caracteres graphiques DOS), HTML ou CSV
   - Grille a remplir, grille solution, liste des definitions
     (horizontalement / verticalement), mots non places
   - Beaucoup d'options : taille, longueur des mots, ordre, graine, etc.
     (voir CROSSGEN /?)
   - Langue : francais par defaut, LANGUAGE=EN (anglais), LANGUAGE=GR
     (allemand), LANGUAGE=SP (espagnol) ou LANGUAGE=IT (italien)

  Tout le code est contenu dans ce seul fichier : aucune programmation
  objet, aucun $I d'inclusion, aucune unite autre que DOS.
}

Program CROSSGEN;

{$IFDEF FPC}
 {$Q-}
 {$R-}
 {$B-}
 {$NOTES OFF}
 {$HINTS OFF}
 {$WARNINGS OFF}
{$ELSE}
 {$R-,Q-,S-,B-}
 {$M 16384,0,655360}
{$ENDIF}

Uses DOS;

Const
 VersionStr='1.00';

 MaxW=60;          { Largeur maximale de la grille }
 MaxH=60;          { Hauteur maximale de la grille }
 MaxWords=250;     { Nombre maximal de mots }
 WordMax=30;       { Longueur maximale d'un mot }
 ClueMax=79;       { Longueur maximale d'un indice }
 MaxInline=60;     { Mots passes par /E ou en parametre }

 DirAcross=1;      { Horizontal (bit 0 du masque) }
 DirDown=2;        { Vertical (bit 1 du masque) }

 BuiltInCount=24;

Type
 TWordRec=Record
  Txt:String[WordMax];
  Clue:String[ClueMax];
  X,Y,Dir,Num:Integer;
  Placed:Boolean;
 End;

 TDict=Record
  Count,Skipped:Integer;
  Items:Array[1..MaxWords]of TWordRec;
 End;

 TGrid=Record
  W,H,Used:Integer;
  Cells:Array[1..MaxH,1..MaxW]of Char;
  Mask:Array[1..MaxH,1..MaxW]of Byte;
 End;

 TSol=Record
  Valid:Boolean;
  Placed,Cross,Area:Integer;
  X,Y,Dir:Array[1..MaxWords]of Integer;
 End;

 TView=Record
  X0,Y0,X1,Y1:Integer;
 End;

 TCand=Record
  X,Y,Dir,Cross,Ties:Integer;
 End;

 TOrder=Array[1..MaxWords]of Integer;

 TCfg=Record
  FileName,OutName:String;
  InlineN:Integer;
  Inlines:Array[1..MaxInline]of String[70];
  W,H,MaxPlace,LenMin,LenMax,Tries,MinCross:Integer;
  Seed:LongInt;
  HasSeed:Boolean;
  Order,Fmt:Char;
  Full,ShowSol,SolOnly,NoClue,NoGrid,Graphic:Boolean;
  Lower,Quiet,Verbose,NeedAll,CP437,BlockSet:Boolean;
  BlockCh,EmptyCh:Char;
  SeenUtf8:Boolean;
 End;

Var
 Lang:Integer;     { 0=FR, 1=EN, 2=GR, 3=SP, 4=IT }
 Cfg:TCfg;
 Dict:TDict;
 Grid:TGrid;
 Best:TSol;
 View:TView;
 OutF:Text;
 MaxNum:Integer;
 Dot:Integer;

{ ---------------------------------------------------------------------- }
{ Mots integres (utilises quand aucun fichier ni mot n'est fourni)        }
{ ---------------------------------------------------------------------- }

Const
 BuiltFR:Array[1..BuiltInCount]of String[70]=(
  'SOLEIL;Etoile au centre du systeme solaire',
  'LUNE;Satellite naturel de la Terre',
  'OCEAN;Vaste etendue d''eau salee',
  'MONTAGNE;Grande elevation de terrain',
  'RIVIERE;Cours d''eau qui se jette dans un fleuve',
  'FORET;Grande etendue couverte d''arbres',
  'DESERT;Region aride et sablonneuse',
  'NUAGE;Amas de gouttelettes dans le ciel',
  'PLUIE;Eau qui tombe des nuages',
  'VENT;Air en mouvement',
  'NEIGE;Flocons blancs de l''hiver',
  'ETOILE;Astre brillant dans la nuit',
  'PLANETE;Corps celeste qui tourne autour du soleil',
  'ARBRE;Grand vegetal a tronc',
  'FLEUR;Partie coloree d''une plante',
  'OISEAU;Animal a plumes qui vole',
  'POISSON;Animal qui vit dans l''eau',
  'CHEVAL;Animal que l''on monte',
  'TERRE;Notre planete',
  'ILE;Terre entouree d''eau',
  'LAC;Etendue d''eau entouree de terre',
  'VOLCAN;Montagne qui crache de la lave',
  'ORAGE;Tempete avec eclairs et tonnerre',
  'PRAIRIE;Vaste etendue d''herbe');

 BuiltEN:Array[1..BuiltInCount]of String[70]=(
  'SUN;Star at the center of our solar system',
  'MOON;Natural satellite of the Earth',
  'OCEAN;Vast body of salt water',
  'MOUNTAIN;Large natural elevation of land',
  'RIVER;Flowing body of water',
  'FOREST;Large area covered with trees',
  'DESERT;Dry sandy region',
  'CLOUD;Mass of water droplets in the sky',
  'RAIN;Water falling from clouds',
  'WIND;Moving air',
  'SNOW;White flakes of winter',
  'STAR;Bright point in the night sky',
  'PLANET;Body orbiting the sun',
  'TREE;Tall plant with a trunk',
  'FLOWER;Colorful part of a plant',
  'BIRD;Feathered animal that flies',
  'FISH;Animal that lives in water',
  'HORSE;Animal you can ride',
  'EARTH;Our planet',
  'ISLAND;Land surrounded by water',
  'LAKE;Inland body of water',
  'VOLCANO;Mountain that spews lava',
  'STORM;Thunder and lightning weather',
  'MEADOW;Field of grass');

 BuiltGR:Array[1..BuiltInCount]of String[70]=(
  'SONNE;Stern im Zentrum unseres Sonnensystems',
  'MOND;Natuerlicher Satellit der Erde',
  'OZEAN;Riesige Salzwasserflaeche',
  'BERG;Grosse Erhebung im Gelaende',
  'FLUSS;Fliessendes Gewaesser',
  'WALD;Grosse mit Baeumen bedeckte Flaeche',
  'WUESTE;Trockene Sandlandschaft',
  'WOLKE;Wassertropfen am Himmel',
  'REGEN;Wasser, das aus den Wolken faellt',
  'WIND;Bewegte Luft',
  'SCHNEE;Weisse Flocken im Winter',
  'STERN;Leuchtender Punkt am Nachthimmel',
  'PLANET;Himmelskoerper, der die Sonne umkreist',
  'BAUM;Hohe Pflanze mit Stamm',
  'BLUME;Bunter Teil einer Pflanze',
  'VOGEL;Tier mit Federn, das fliegt',
  'FISCH;Tier, das im Wasser lebt',
  'PFERD;Tier, auf dem man reitet',
  'ERDE;Unser Planet',
  'INSEL;Von Wasser umgebenes Land',
  'SEE;Von Land umgebenes Gewaesser',
  'VULKAN;Berg, der Lava speit',
  'GEWITTER;Sturm mit Blitz und Donner',
  'WIESE;Grasbewachsene Flaeche');

 BuiltSP:Array[1..BuiltInCount]of String[70]=(
  'SOL;Estrella en el centro del sistema solar',
  'LUNA;Satelite natural de la Tierra',
  'OCEANO;Gran extension de agua salada',
  'MONTANA;Gran elevacion natural del terreno',
  'RIO;Corriente de agua que desemboca en el mar',
  'BOSQUE;Terreno cubierto de arboles',
  'DESIERTO;Region arida y arenosa',
  'NUBE;Masa de gotas de agua en el cielo',
  'LLUVIA;Agua que cae de las nubes',
  'VIENTO;Aire en movimiento',
  'NIEVE;Copos blancos del invierno',
  'ESTRELLA;Punto brillante en el cielo nocturno',
  'PLANETA;Cuerpo que gira alrededor del sol',
  'ARBOL;Planta alta con tronco',
  'FLOR;Parte colorida de una planta',
  'PAJARO;Animal con plumas que vuela',
  'PEZ;Animal que vive en el agua',
  'CABALLO;Animal que se monta',
  'TIERRA;Nuestro planeta',
  'ISLA;Tierra rodeada de agua',
  'LAGO;Agua rodeada de tierra',
  'VOLCAN;Montana que escupe lava',
  'TORMENTA;Tiempo con rayos y truenos',
  'PRADO;Terreno cubierto de hierba');

 BuiltIT:Array[1..BuiltInCount]of String[70]=(
  'SOLE;Stella al centro del sistema solare',
  'LUNA;Satellite naturale della Terra',
  'OCEANO;Vasta distesa di acqua salata',
  'MONTAGNA;Grande rilievo del terreno',
  'FIUME;Corso d''acqua che sfocia nel mare',
  'FORESTA;Grande area coperta di alberi',
  'DESERTO;Regione arida e sabbiosa',
  'NUVOLA;Massa di goccioline nel cielo',
  'PIOGGIA;Acqua che cade dalle nuvole',
  'VENTO;Aria in movimento',
  'NEVE;Fiocchi bianchi dell''inverno',
  'STELLA;Punto luminoso nel cielo notturno',
  'PIANETA;Corpo che orbita attorno al sole',
  'ALBERO;Pianta alta con tronco',
  'FIORE;Parte colorata di una pianta',
  'UCCELLO;Animale con le piume che vola',
  'PESCE;Animale che vive nell''acqua',
  'CAVALLO;Animale che si cavalca',
  'TERRA;Il nostro pianeta',
  'ISOLA;Terra circondata dall''acqua',
  'LAGO;Acqua circondata dalla terra',
  'VULCANO;Montagna che sputa lava',
  'TEMPORALE;Maltempo con lampi e tuoni',
  'PRATO;Distesa di erba');

 { Table de conversion Latin-1 (192..223) vers lettre simple ; '*' = ignore }
 Lat1Map:String[32]='AAAAAAACEEEEIIIIDNOOOOO*OUUUUY*S';
 { Table de conversion CP437 (128..165) }
 Cp437Map:String[38]='CUEAAAACEEEIIIAAEAAOOOUUYOU*****AIOUNN';

{ ---------------------------------------------------------------------- }
{ Utilitaires generaux                                                    }
{ ---------------------------------------------------------------------- }

Function UpStr(S:String):String;
Var
 I:Integer;
Begin
 For I:=1 to Length(S)do Begin
  If S[I]in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
 End;
 UpStr:=S;
End;

Function IntStr(N:LongInt):String;
Var
 S:String;
Begin
 Str(N,S);
 IntStr:=S;
End;

Function PadR(S:String;N:Integer):String;
Begin
 While Length(S)<N do S:=S+' ';
 PadR:=S;
End;

Function PadL(S:String;N:Integer):String;
Begin
 While Length(S)<N do S:=' '+S;
 PadL:=S;
End;

Function TrimStr(S:String):String;
Begin
 While(Length(S)>0)and(S[Length(S)]in[' ',#9,#13,#10])do Dec(S[0]);
 While(Length(S)>0)and(S[1]in[' ',#9])do Delete(S,1,1);
 TrimStr:=S;
End;

Function Max2(A,B:Integer):Integer;Begin
 If A>B Then Max2:=A
        Else Max2:=B;
End;

{ ---------------------------------------------------------------------- }
{ Langue : francais par defaut, LANGUAGE=EN / GR / SP / IT                }
{ ---------------------------------------------------------------------- }

Procedure SetLang(S:String);Begin
 S:=UpStr(S);
 Lang:=0;
 If Copy(S,1,2)='EN'Then Lang:=1 Else
 If(Copy(S,1,2)='GR')or(Copy(S,1,2)='DE')Then Lang:=2 Else
 If(Copy(S,1,2)='SP')or(Copy(S,1,2)='ES')Then Lang:=3 Else
 If Copy(S,1,2)='IT'Then Lang:=4;
End;

{ Choisit la chaine selon la langue : francais, anglais, allemand,
  espagnol, italien }
Function L5(Const F,E,D,S,I:String):String;Begin
 Case Lang of
  1:L5:=E;
  2:L5:=D;
  3:L5:=S;
  4:L5:=I;
  Else L5:=F;
 End;
End;

Function Msg(N:Integer):String;Begin
 Msg:='';
 Case N of
  1:Msg:=L5('Option inconnue : ','Unknown option: ',
            'Unbekannte Option: ','Opcion desconocida: ',
            'Opzione sconosciuta: ');
  2:Msg:=L5('Valeur manquante pour l''option ',
            'Missing value for option ',
            'Fehlender Wert fuer Option ',
            'Falta el valor de la opcion ',
            'Valore mancante per l''opzione ');
  3:Msg:=L5('Valeur invalide pour ','Invalid value for ',
            'Ungueltiger Wert fuer ','Valor invalido para ',
            'Valore non valido per ');
  4:Msg:=L5('Fichier introuvable : ','File not found: ',
            'Datei nicht gefunden: ','Archivo no encontrado: ',
            'File non trovato: ');
  5:Msg:=L5('Aucun mot utilisable.','No usable word.',
            'Kein verwendbares Wort.','Ninguna palabra utilizable.',
            'Nessuna parola utilizzabile.');
  6:Msg:=L5('Impossible de creer le fichier : ',
            'Unable to create the file: ',
            'Datei kann nicht erstellt werden: ',
            'No se puede crear el archivo: ',
            'Impossibile creare il file: ');
  7:Msg:=L5('Mots croises','Crossword','Kreuzwortraetsel',
            'Crucigrama','Cruciverba');
  8:Msg:=L5('Horizontalement','Across','Waagerecht',
            'Horizontales','Orizzontali');
  9:Msg:=L5('Verticalement','Down','Senkrecht',
            'Verticales','Verticali');
  10:Msg:=L5('Mot de ','Word of ','Wort mit ','Palabra de ','Parola di ');
  11:Msg:=L5(' lettres',' letters',' Buchstaben',' letras',' lettere');
  12:Msg:=L5('Mots places : ','Words placed: ','Platzierte Woerter: ',
             'Palabras colocadas: ','Parole inserite: ');
  13:Msg:=L5(' (ignores : ',' (skipped: ',' (uebersprungen: ',
             ' (omitidas: ',' (ignorate: ');
  14:Msg:=L5('Grille : ','Grid: ','Gitter: ','Cuadricula: ','Griglia: ');
  15:Msg:=L5(' - croisements : ',' - crossings: ',' - Kreuzungen: ',
             ' - cruces: ',' - incroci: ');
  16:Msg:=L5(' - densite : ',' - density: ',' - Dichte: ',
             ' - densidad: ',' - densita: ');
  17:Msg:=L5('Graine (/S:n pour reproduire) : ',
             'Seed (/S:n to reproduce): ',
             'Startwert (/S:n zum Wiederholen): ',
             'Semilla (/S:n para reproducir): ',
             'Seme (/S:n per riprodurre): ');
  18:Msg:=L5('Mots non places : ','Words not placed: ',
             'Nicht platzierte Woerter: ','Palabras no colocadas: ',
             'Parole non inserite: ');
  19:Msg:=L5('Essai ','Attempt ','Versuch ','Intento ','Tentativo ');
  20:Msg:=L5('Solution','Solution','Loesung','Solucion','Soluzione');
  21:Msg:=L5(' mots, ',' words, ',' Woerter, ',' palabras, ',' parole, ');
  22:Msg:=L5(' croisements',' crossings',' Kreuzungen',' cruces',' incroci');
  23:Msg:=L5('Une valeur est requise pour la taille (LxH).',
             'A value is required for the size (WxH).',
             'Fuer die Groesse (BxH) ist ein Wert erforderlich.',
             'Se requiere un valor para el tamano (AxH).',
             'Serve un valore per la dimensione (LxA).');
 End;
End;

{ Message d'erreur (sortie d'erreur sous Free Pascal) }
Procedure MsgLn(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,S);
 {$ELSE}
 WriteLn(S);
 {$ENDIF}
End;

Procedure Fatal(Code:Integer;Const S:String);Begin
 MsgLn(S);
 Halt(Code);
End;

{ ---------------------------------------------------------------------- }
{ Aide en ligne                                                           }
{ ---------------------------------------------------------------------- }

Procedure H(Const S:String);Begin
 WriteLn(S);
End;

Procedure HelpFR;Begin
 H('CROSSGEN - Generateur de mots croises (v'+VersionStr+')');
 H('');
 H('Syntaxe : CROSSGEN [fichier [mot ...]] [options]');
 H('');
 H(' fichier       Fichier de mots : un mot par ligne, indice facultatif');
 H('               (MOT;indice). Les autres mots donnes sont ajoutes.');
 H(' /F:fichier    Idem (- = entree standard)');
 H(' /E:m1,m2=ind  Mots supplementaires (MOT ou MOT=indice, virgules)');
 H(' /W:n          Largeur de la grille, 5 a 60 (defaut 15)');
 H(' /HEIGHT:n     Hauteur de la grille, 5 a 60 (defaut 15)');
 H(' /SIZE:LxH     Largeur et hauteur ensemble (ex. : /SIZE:20x12)');
 H(' /N:n          Nombre maximal de mots a placer');
 H(' /MIN:n        Longueur minimale d''un mot (defaut 3)');
 H(' /MAX:n        Longueur maximale d''un mot (defaut 30)');
 H(' /T:n          Nombre d''essais, la meilleure grille est gardee');
 H('               (defaut 30)');
 H(' /S:n          Graine aleatoire (meme graine = meme grille)');
 H(' /ORDER:x      Ordre des mots : L=longs d''abord (defaut),');
 H('               S=courts d''abord, R=aleatoire, A=ordre du fichier');
 H(' /I:n          Croisements minimum par mot (defaut 1, 0 = mots');
 H('               isoles permis)');
 H(' /FULL         Garde toute la grille (sans rogner les bords vides)');
 H(' /A            Affiche aussi la grille solution');
 H(' /SOLONLY      Affiche seulement la grille solution');
 H(' /NOGRID       N''affiche pas la grille (definitions seulement)');
 H(' /NOCLUE       N''affiche pas la liste des definitions');
 H(' /FMT:x        Format de sortie : TXT (defaut), HTML ou CSV');
 H(' /OUT:fichier  Ecrit le resultat dans un fichier (aussi /O:fichier)');
 H(' /G            Trace la grille avec les caracteres graphiques DOS');
 H(' /BLOCK:c      Caractere des cases noires (defaut #)');
 H(' /EMPTY:c      Caractere des cases a remplir (defaut : espace)');
 H(' /LC           Lettres en minuscules');
 H(' /CP437        Fichier de mots en CP437 (defaut : UTF-8 ou Latin-1)');
 H(' /ALL          Code de sortie 4 si des mots n''ont pu etre places');
 H(' /LANG:xx      Langue : FR, EN, GR, SP ou IT (defaut : LANGUAGE)');
 H(' /V            Mode bavard (detail des essais)');
 H(' /Q            Mode silencieux (pas de resume)');
 H(' /VERSION      Affiche la version');
 H(' /? /H --help  Affiche cette aide');
 H('');
 H('Les options peuvent commencer par / ou - (ex. : -W:20 ou --w=20).');
 H('Sans fichier ni /E, une petite liste de mots integree est utilisee.');
 H('Variable d''environnement : LANGUAGE=EN, GR, SP ou IT (defaut : FR).');
 H('Codes de sortie : 0 ok, 1 option, 2 fichier, 3 aucun mot,');
 H('4 mots non places (avec /ALL).');
End;

Procedure HelpEN;Begin
 H('CROSSGEN - Crossword Generator (v'+VersionStr+')');
 H('');
 H('Usage: CROSSGEN [file [word ...]] [options]');
 H('');
 H(' file          Word file: one word per line, optional clue');
 H('               (WORD;clue). Other words given are added.');
 H(' /F:file       Same as above (- = standard input)');
 H(' /E:w1,w2=c    Extra words (WORD or WORD=clue, comma separated)');
 H(' /W:n          Grid width, 5 to 60 (default 15)');
 H(' /HEIGHT:n     Grid height, 5 to 60 (default 15)');
 H(' /SIZE:WxH     Width and height together (e.g. /SIZE:20x12)');
 H(' /N:n          Maximum number of words to place');
 H(' /MIN:n        Minimum word length (default 3)');
 H(' /MAX:n        Maximum word length (default 30)');
 H(' /T:n          Number of attempts, the best grid is kept');
 H('               (default 30)');
 H(' /S:n          Random seed (same seed = same grid)');
 H(' /ORDER:x      Word order: L=longest first (default),');
 H('               S=shortest first, R=random, A=file order');
 H(' /I:n          Minimum crossings per word (default 1, 0 = isolated');
 H('               words allowed)');
 H(' /FULL         Keep the whole grid (do not crop empty borders)');
 H(' /A            Also show the solution grid');
 H(' /SOLONLY      Show only the solution grid');
 H(' /NOGRID       Do not show the grid (clues only)');
 H(' /NOCLUE       Do not show the clue list');
 H(' /FMT:x        Output format: TXT (default), HTML or CSV');
 H(' /OUT:file     Write the result to a file (also /O:file)');
 H(' /G            Draw the grid with DOS line characters');
 H(' /BLOCK:c      Character for black squares (default #)');
 H(' /EMPTY:c      Character for squares to fill (default: space)');
 H(' /LC           Lowercase letters');
 H(' /CP437        Word file is CP437 (default: UTF-8 or Latin-1)');
 H(' /ALL          Exit code 4 if some words could not be placed');
 H(' /LANG:xx      Language: FR, EN, GR, SP or IT (default: LANGUAGE)');
 H(' /V            Verbose (attempt details)');
 H(' /Q            Quiet (no summary)');
 H(' /VERSION      Show the version');
 H(' /? /H --help  Show this help');
 H('');
 H('Options may start with / or - (e.g. -W:20 or --w=20).');
 H('Without file or /E, a small built-in word list is used.');
 H('Environment: LANGUAGE=EN, GR, SP or IT (default: French).');
 H('Exit codes: 0 ok, 1 option, 2 file, 3 no word,');
 H('4 words not placed (with /ALL).');
End;

Procedure HelpGR;Begin
 H('CROSSGEN - Kreuzwortraetsel-Generator (v'+VersionStr+')');
 H('');
 H('Syntax: CROSSGEN [Datei [Wort ...]] [Optionen]');
 H('');
 H(' Datei         Wortdatei: ein Wort pro Zeile, Hinweis optional');
 H('               (WORT;Hinweis). Weitere Woerter werden hinzugefuegt.');
 H(' /F:Datei      Wie oben (- = Standardeingabe)');
 H(' /E:w1,w2=h    Zusatzwoerter (WORT oder WORT=Hinweis, mit Komma)');
 H(' /W:n          Gitterbreite, 5 bis 60 (Standard 15)');
 H(' /HEIGHT:n     Gitterhoehe, 5 bis 60 (Standard 15)');
 H(' /SIZE:BxH     Breite und Hoehe zusammen (z.B. /SIZE:20x12)');
 H(' /N:n          Hoechstzahl der zu platzierenden Woerter');
 H(' /MIN:n        Minimale Wortlaenge (Standard 3)');
 H(' /MAX:n        Maximale Wortlaenge (Standard 30)');
 H(' /T:n          Anzahl Versuche, das beste Gitter bleibt');
 H('               (Standard 30)');
 H(' /S:n          Zufallswert (gleicher Wert = gleiches Gitter)');
 H(' /ORDER:x      Reihenfolge: L=lange zuerst (Standard),');
 H('               S=kurze zuerst, R=zufaellig, A=Dateireihenfolge');
 H(' /I:n          Mindestkreuzungen je Wort (Standard 1, 0 = einzelne');
 H('               Woerter erlaubt)');
 H(' /FULL         Ganzes Gitter behalten (leere Raender nicht kuerzen)');
 H(' /A            Zeigt auch das Loesungsgitter');
 H(' /SOLONLY      Zeigt nur das Loesungsgitter');
 H(' /NOGRID       Kein Gitter anzeigen (nur Hinweise)');
 H(' /NOCLUE       Keine Hinweisliste anzeigen');
 H(' /FMT:x        Ausgabeformat: TXT (Standard), HTML oder CSV');
 H(' /OUT:Datei    Ergebnis in eine Datei schreiben (auch /O:Datei)');
 H(' /G            Gitter mit DOS-Liniensymbolen zeichnen');
 H(' /BLOCK:c      Zeichen fuer schwarze Felder (Standard #)');
 H(' /EMPTY:c      Zeichen fuer auszufuellende Felder (Standard: Leerz.)');
 H(' /LC           Kleinbuchstaben');
 H(' /CP437        Wortdatei ist CP437 (Standard: UTF-8 oder Latin-1)');
 H(' /ALL          Exitcode 4, wenn Woerter nicht platziert wurden');
 H(' /LANG:xx      Sprache: FR, EN, GR, SP oder IT (Standard: LANGUAGE)');
 H(' /V            Ausfuehrlich (Details der Versuche)');
 H(' /Q            Still (keine Zusammenfassung)');
 H(' /VERSION      Zeigt die Version');
 H(' /? /H --help  Zeigt diese Hilfe');
 H('');
 H('Optionen koennen mit / oder - beginnen (z.B. -W:20 oder --w=20).');
 H('Ohne Datei oder /E wird eine kleine eingebaute Liste benutzt.');
 H('Umgebung: LANGUAGE=EN, GR, SP oder IT (Standard: Franzoesisch).');
 H('Exitcodes: 0 ok, 1 Option, 2 Datei, 3 kein Wort,');
 H('4 Woerter nicht platziert (mit /ALL).');
End;

Procedure HelpSP;Begin
 H('CROSSGEN - Generador de crucigramas (v'+VersionStr+')');
 H('');
 H('Sintaxis: CROSSGEN [archivo [palabra ...]] [opciones]');
 H('');
 H(' archivo       Archivo de palabras: una por linea, pista opcional');
 H('               (PALABRA;pista). Las otras palabras se anaden.');
 H(' /F:archivo    Igual que arriba (- = entrada estandar)');
 H(' /E:p1,p2=pi   Palabras extra (PALABRA o PALABRA=pista, con comas)');
 H(' /W:n          Ancho de la cuadricula, 5 a 60 (por defecto 15)');
 H(' /HEIGHT:n     Alto de la cuadricula, 5 a 60 (por defecto 15)');
 H(' /SIZE:AxH     Ancho y alto juntos (ej.: /SIZE:20x12)');
 H(' /N:n          Numero maximo de palabras a colocar');
 H(' /MIN:n        Longitud minima de una palabra (por defecto 3)');
 H(' /MAX:n        Longitud maxima de una palabra (por defecto 30)');
 H(' /T:n          Numero de intentos, se guarda la mejor cuadricula');
 H('               (por defecto 30)');
 H(' /S:n          Semilla aleatoria (misma semilla = misma cuadricula)');
 H(' /ORDER:x      Orden: L=largas primero (por defecto),');
 H('               S=cortas primero, R=aleatorio, A=orden del archivo');
 H(' /I:n          Cruces minimos por palabra (por defecto 1, 0 =');
 H('               palabras aisladas permitidas)');
 H(' /FULL         Conserva toda la cuadricula (sin recortar bordes)');
 H(' /A            Muestra tambien la cuadricula solucion');
 H(' /SOLONLY      Muestra solo la cuadricula solucion');
 H(' /NOGRID       No muestra la cuadricula (solo las pistas)');
 H(' /NOCLUE       No muestra la lista de pistas');
 H(' /FMT:x        Formato de salida: TXT (por defecto), HTML o CSV');
 H(' /OUT:archivo  Escribe el resultado en un archivo (tambien /O:)');
 H(' /G            Dibuja la cuadricula con caracteres graficos DOS');
 H(' /BLOCK:c      Caracter de las casillas negras (por defecto #)');
 H(' /EMPTY:c      Caracter de las casillas a rellenar (def.: espacio)');
 H(' /LC           Letras en minusculas');
 H(' /CP437        Archivo en CP437 (por defecto: UTF-8 o Latin-1)');
 H(' /ALL          Codigo de salida 4 si hay palabras sin colocar');
 H(' /LANG:xx      Idioma: FR, EN, GR, SP o IT (por defecto: LANGUAGE)');
 H(' /V            Modo detallado (detalle de los intentos)');
 H(' /Q            Modo silencioso (sin resumen)');
 H(' /VERSION      Muestra la version');
 H(' /? /H --help  Muestra esta ayuda');
 H('');
 H('Las opciones pueden empezar por / o - (ej.: -W:20 o --w=20).');
 H('Sin archivo ni /E se usa una pequena lista de palabras integrada.');
 H('Entorno: LANGUAGE=EN, GR, SP o IT (por defecto: frances).');
 H('Codigos de salida: 0 ok, 1 opcion, 2 archivo, 3 sin palabras,');
 H('4 palabras sin colocar (con /ALL).');
End;

Procedure HelpIT;Begin
 H('CROSSGEN - Generatore di cruciverba (v'+VersionStr+')');
 H('');
 H('Sintassi: CROSSGEN [file [parola ...]] [opzioni]');
 H('');
 H(' file          File di parole: una per riga, definizione facoltativa');
 H('               (PAROLA;definizione). Le altre parole sono aggiunte.');
 H(' /F:file       Come sopra (- = input standard)');
 H(' /E:p1,p2=d    Parole extra (PAROLA o PAROLA=definizione, virgole)');
 H(' /W:n          Larghezza della griglia, da 5 a 60 (predefinito 15)');
 H(' /HEIGHT:n     Altezza della griglia, da 5 a 60 (predefinito 15)');
 H(' /SIZE:LxA     Larghezza e altezza insieme (es.: /SIZE:20x12)');
 H(' /N:n          Numero massimo di parole da inserire');
 H(' /MIN:n        Lunghezza minima di una parola (predefinito 3)');
 H(' /MAX:n        Lunghezza massima di una parola (predefinito 30)');
 H(' /T:n          Numero di tentativi, si tiene la griglia migliore');
 H('               (predefinito 30)');
 H(' /S:n          Seme casuale (stesso seme = stessa griglia)');
 H(' /ORDER:x      Ordine: L=lunghe prima (predefinito),');
 H('               S=corte prima, R=casuale, A=ordine del file');
 H(' /I:n          Incroci minimi per parola (predefinito 1, 0 =');
 H('               parole isolate ammesse)');
 H(' /FULL         Tiene tutta la griglia (senza tagliare i bordi)');
 H(' /A            Mostra anche la griglia soluzione');
 H(' /SOLONLY      Mostra solo la griglia soluzione');
 H(' /NOGRID       Non mostra la griglia (solo le definizioni)');
 H(' /NOCLUE       Non mostra l''elenco delle definizioni');
 H(' /FMT:x        Formato di uscita: TXT (predefinito), HTML o CSV');
 H(' /OUT:file     Scrive il risultato in un file (anche /O:file)');
 H(' /G            Disegna la griglia con i caratteri grafici DOS');
 H(' /BLOCK:c      Carattere delle caselle nere (predefinito #)');
 H(' /EMPTY:c      Carattere delle caselle da riempire (pred.: spazio)');
 H(' /LC           Lettere minuscole');
 H(' /CP437        File di parole in CP437 (predefinito: UTF-8/Latin-1)');
 H(' /ALL          Codice di uscita 4 se alcune parole non sono inserite');
 H(' /LANG:xx      Lingua: FR, EN, GR, SP o IT (predefinito: LANGUAGE)');
 H(' /V            Modo dettagliato (dettaglio dei tentativi)');
 H(' /Q            Modo silenzioso (nessun riepilogo)');
 H(' /VERSION      Mostra la versione');
 H(' /? /H --help  Mostra questa guida');
 H('');
 H('Le opzioni possono iniziare con / o - (es.: -W:20 o --w=20).');
 H('Senza file ne /E si usa una piccola lista di parole integrata.');
 H('Ambiente: LANGUAGE=EN, GR, SP o IT (predefinito: francese).');
 H('Codici di uscita: 0 ok, 1 opzione, 2 file, 3 nessuna parola,');
 H('4 parole non inserite (con /ALL).');
End;

Procedure ShowHelp;Begin
 Case Lang of
  1:HelpEN;
  2:HelpGR;
  3:HelpSP;
  4:HelpIT;
  Else HelpFR;
 End;
End;

{ ---------------------------------------------------------------------- }
{ Normalisation des mots : majuscules sans accents                        }
{ ---------------------------------------------------------------------- }

Procedure AddCh(Var D:String;Ch:Char);Begin
 If Length(D)<255 Then D:=D+Ch;
End;

{ Ajoute la lettre correspondant au code Latin-1 C }
Procedure MapLatin1(Var D:String;C:Integer);
Var
 Ch:Char;
Begin
 If(C=198)or(C=230)Then Begin
  AddCh(D,'A');
  AddCh(D,'E');
 End
  Else
 If(C=140)or(C=156)Then Begin
  AddCh(D,'O');
  AddCh(D,'E');
 End
  Else
 If C=223 Then Begin
  AddCh(D,'S');
  AddCh(D,'S');
 End
  Else
 If C=255 Then AddCh(D,'Y')
  Else
 If(C>=192)and(C<=255)Then Begin
  Ch:=Lat1Map[((C-192)and 31)+1];
  If Ch<>'*'Then AddCh(D,Ch);
 End;
End;

{ Ajoute la lettre correspondant au code CP437 C }
Procedure MapCp437(Var D:String;C:Integer);
Var
 Ch:Char;
Begin
 If(C=145)or(C=146)Then Begin
  AddCh(D,'A');
  AddCh(D,'E');
 End
  Else
 If C=225 Then Begin
  AddCh(D,'S');
  AddCh(D,'S');
 End
  Else
 If(C>=128)and(C<=165)Then Begin
  Ch:=Cp437Map[C-127];
  If Ch<>'*'Then AddCh(D,Ch);
 End;
End;

{ Y a-t-il une sequence UTF-8 de deux octets ou plus dans S ? }
Function HasUtf8(Const S:String):Boolean;
Var
 I:Integer;
Begin
 HasUtf8:=False;
 For I:=1 to Length(S)-1 do Begin
  If(Ord(S[I])>=$C2)and(Ord(S[I])<=$F4)and
    (Ord(S[I+1])>=$80)and(Ord(S[I+1])<=$BF)Then Begin
   HasUtf8:=True;
   Exit;
  End;
 End;
End;

{ Convertit Src en majuscules A-Z et 0-9 (sans accent) dans Dst.
  Enc : 0=UTF-8 ou Latin-1 (detection automatique), 1=CP437 }
Procedure NormalizeStr(Const Src:String;Enc:Integer;Var Dst:String);
Var
 I,C,N:Integer;
 Utf:Boolean;
 Ch:Char;
Begin
 Dst:='';
 Utf:=False;
 If Enc=0 Then Utf:=HasUtf8(Src);
 I:=1;
 While I<=Length(Src)do Begin
  C:=Ord(Src[I]);
  If C<128 Then Begin
   Ch:=UpCase(Src[I]);
   If Ch in['A'..'Z','0'..'9']Then AddCh(Dst,Ch);
  End
   Else
  If Utf Then Begin
   If(C>=$C2)and(C<=$DF)Then Begin
    If I<Length(Src)Then Begin
     N:=Ord(Src[I+1]);
     If C=$C3 Then MapLatin1(Dst,N+64) Else
     If(C=$C5)and((N=$92)or(N=$93))Then Begin
      AddCh(Dst,'O');
      AddCh(Dst,'E');
     End;
     Inc(I);
    End;
   End
    Else
   If(C>=$E0)and(C<=$EF)Then Inc(I,2) Else
   If(C>=$F0)and(C<=$F4)Then Inc(I,3);
  End
   Else
  If Enc=1 Then MapCp437(Dst,C)
           Else MapLatin1(Dst,C);
  Inc(I);
 End;
End;

{ ---------------------------------------------------------------------- }
{ Dictionnaire de mots                                                    }
{ ---------------------------------------------------------------------- }

Procedure DictAdd(Var D:TDict;Var C:TCfg;Const RawWord,ClueTxt:String);
Var
 T:String;
 I,Enc:Integer;
Begin
 If C.CP437 Then Enc:=1
            Else Enc:=0;
 NormalizeStr(RawWord,Enc,T);
 If T=''Then Exit;
 If HasUtf8(ClueTxt)or HasUtf8(RawWord)Then C.SeenUtf8:=True;
 If(Length(T)<C.LenMin)or(Length(T)>C.LenMax)or
   (Length(T)>WordMax)or(Length(T)>Max2(C.W,C.H))Then Begin
  Inc(D.Skipped);
  Exit;
 End;
 For I:=1 to D.Count do If D.Items[I].Txt=T Then Exit;
 If D.Count>=MaxWords Then Begin
  Inc(D.Skipped);
  Exit;
 End;
 Inc(D.Count);
 With D.Items[D.Count]do Begin
  Txt:=T;
  Clue:=Copy(TrimStr(ClueTxt),1,ClueMax);
  X:=0;Y:=0;Dir:=0;Num:=0;
  Placed:=False;
 End;
End;

{ Ajoute une ligne "MOT;indice" ou "MOT<TAB>indice" }
Procedure DictAddLine(Var D:TDict;Var C:TCfg;Const Line:String);
Var
 P,P2:Integer;
Begin
 P:=Pos(';',Line);
 P2:=Pos(#9,Line);
 If(P2>0)and((P=0)or(P2<P))Then P:=P2;
 If P>0 Then DictAdd(D,C,Copy(Line,1,P-1),Copy(Line,P+1,255))
        Else DictAdd(D,C,Line,'');
End;

{ Charge un fichier de mots ('-' = entree standard) }
Function LoadFile(Var D:TDict;Var C:TCfg;Const Name:String):Boolean;
Var
 F:Text;
 Line:String;
Begin
 LoadFile:=False;
 If Name='-'Then Assign(F,'')
            Else Assign(F,Name);
 {$I-}Reset(F);{$I+}
 If IOResult<>0 Then Exit;
 While Not EOF(F)do Begin
  ReadLn(F,Line);
  Line:=TrimStr(Line);
  If(Line<>'')and(Line[1]<>';')and(Line[1]<>'#')Then DictAddLine(D,C,Line);
 End;
 Close(F);
 LoadFile:=True;
End;

{ Mots integres selon la langue }
Procedure LoadBuiltIn(Var D:TDict;Var C:TCfg);
Var
 I:Integer;
 S:String;
Begin
 For I:=1 to BuiltInCount do Begin
  Case Lang of
   1:S:=BuiltEN[I];
   2:S:=BuiltGR[I];
   3:S:=BuiltSP[I];
   4:S:=BuiltIT[I];
   Else S:=BuiltFR[I];
  End;
  DictAddLine(D,C,S);
 End;
End;

{ Memorise les mots donnes par /E (separes par des virgules) }
Procedure AddInline(Var C:TCfg;S:String);
Var
 P:Integer;
 T:String;
Begin
 While S<>''do Begin
  P:=Pos(',',S);
  If P=0 Then Begin
   T:=S;
   S:='';
  End
   Else
  Begin
   T:=Copy(S,1,P-1);
   S:=Copy(S,P+1,255);
  End;
  T:=TrimStr(T);
  If(T<>'')and(C.InlineN<MaxInline)Then Begin
   Inc(C.InlineN);
   C.Inlines[C.InlineN]:=Copy(T,1,70);
  End;
 End;
End;

Procedure LoadInline(Var D:TDict;Var C:TCfg);
Var
 I,P:Integer;
 T:String;
Begin
 For I:=1 to C.InlineN do Begin
  T:=C.Inlines[I];
  P:=Pos('=',T);
  If P>0 Then DictAdd(D,C,Copy(T,1,P-1),Copy(T,P+1,255))
         Else DictAdd(D,C,T,'');
 End;
End;

{ ---------------------------------------------------------------------- }
{ Analyse de la ligne de commande                                         }
{ ---------------------------------------------------------------------- }

Procedure InitDefaults(Var C:TCfg);Begin
 C.FileName:='';
 C.OutName:='';
 C.InlineN:=0;
 C.W:=15;
 C.H:=15;
 C.MaxPlace:=MaxWords;
 C.LenMin:=3;
 C.LenMax:=WordMax;
 C.Tries:=30;
 C.MinCross:=1;
 C.Seed:=0;
 C.HasSeed:=False;
 C.Order:='L';
 C.Fmt:='T';
 C.Full:=False;
 C.ShowSol:=False;
 C.SolOnly:=False;
 C.NoClue:=False;
 C.NoGrid:=False;
 C.Graphic:=False;
 C.Lower:=False;
 C.Quiet:=False;
 C.Verbose:=False;
 C.NeedAll:=False;
 C.CP437:=False;
 C.BlockSet:=False;
 C.BlockCh:='#';
 C.EmptyCh:=' ';
 C.SeenUtf8:=False;
End;

Function ParseInt(Const Name,S:String;Lo,Hi:LongInt):LongInt;
Var
 N:LongInt;
 Err:Integer;
Begin
 Val(S,N,Err);
 If(Err<>0)or(N<Lo)or(N>Hi)Then Begin
  Fatal(1,Msg(3)+Name+' ('+IntStr(Lo)+'..'+IntStr(Hi)+')');
 End;
 ParseInt:=N;
End;

{ Prend la valeur de l'option : apres ':' ou '=', sinon le parametre suivant }
Procedure NeedValue(Const Name:String;Var S:String;Var HasVal:Boolean;
                    Var I:Integer);Begin
 If Not HasVal Then Begin
  If I<ParamCount Then Begin
   Inc(I);
   S:=ParamStr(I);
   HasVal:=True;
  End
   Else
  Fatal(1,Msg(2)+Name);
 End;
End;

Procedure ApplyOption(Var C:TCfg;Const Name:String;S:String;HasVal:Boolean;
                      Var I:Integer);
Var
 P:Integer;
Begin
 If(Name='?')or(Name='H')or(Name='HELP')Then Begin
  ShowHelp;
  Halt(0);
 End
  Else
 If Name='VERSION'Then Begin
  WriteLn('CROSSGEN ',VersionStr);
  Halt(0);
 End
  Else
 If Name='F'Then Begin
  NeedValue(Name,S,HasVal,I);
  C.FileName:=S;
 End
  Else
 If Name='E'Then Begin
  NeedValue(Name,S,HasVal,I);
  AddInline(C,S);
 End
  Else
 If Name='W'Then Begin
  NeedValue(Name,S,HasVal,I);
  C.W:=ParseInt(Name,S,5,MaxW);
 End
  Else
 If(Name='HEIGHT')or(Name='HT')Then Begin
  NeedValue(Name,S,HasVal,I);
  C.H:=ParseInt(Name,S,5,MaxH);
 End
  Else
 If Name='SIZE'Then Begin
  NeedValue(Name,S,HasVal,I);
  P:=Pos('X',UpStr(S));
  If P=0 Then P:=Pos(',',S);
  If P=0 Then Fatal(1,Msg(23));
  C.W:=ParseInt(Name,Copy(S,1,P-1),5,MaxW);
  C.H:=ParseInt(Name,Copy(S,P+1,255),5,MaxH);
 End
  Else
 If Name='N'Then Begin
  NeedValue(Name,S,HasVal,I);
  C.MaxPlace:=ParseInt(Name,S,1,MaxWords);
 End
  Else
 If Name='MIN'Then Begin
  NeedValue(Name,S,HasVal,I);
  C.LenMin:=ParseInt(Name,S,1,WordMax);
 End
  Else
 If Name='MAX'Then Begin
  NeedValue(Name,S,HasVal,I);
  C.LenMax:=ParseInt(Name,S,1,WordMax);
 End
  Else
 If Name='T'Then Begin
  NeedValue(Name,S,HasVal,I);
  C.Tries:=ParseInt(Name,S,1,10000);
 End
  Else
 If Name='S'Then Begin
  NeedValue(Name,S,HasVal,I);
  C.Seed:=ParseInt(Name,S,0,2147483647);
  C.HasSeed:=True;
 End
  Else
 If Name='I'Then Begin
  NeedValue(Name,S,HasVal,I);
  C.MinCross:=ParseInt(Name,S,0,4);
 End
  Else
 If Name='ORDER'Then Begin
  NeedValue(Name,S,HasVal,I);
  S:=UpStr(S);
  If(S='')or Not(S[1]in['L','S','R','A'])Then Fatal(1,Msg(3)+Name);
  C.Order:=S[1];
 End
  Else
 If Name='FMT'Then Begin
  NeedValue(Name,S,HasVal,I);
  S:=UpStr(S);
  If(S='TXT')or(S='T')or(S='TEXT')Then C.Fmt:='T' Else
  If(S='HTML')or(S='HTM')Then C.Fmt:='H' Else
  If S='CSV'Then C.Fmt:='C'
            Else Fatal(1,Msg(3)+Name);
 End
  Else
 If(Name='OUT')or(Name='O')Then Begin
  NeedValue(Name,S,HasVal,I);
  C.OutName:=S;
 End
  Else
 If Name='BLOCK'Then Begin
  NeedValue(Name,S,HasVal,I);
  If S=''Then Fatal(1,Msg(3)+Name);
  C.BlockCh:=S[1];
  C.BlockSet:=True;
 End
  Else
 If Name='EMPTY'Then Begin
  NeedValue(Name,S,HasVal,I);
  If(S='')or(UpStr(S)='SPACE')Then C.EmptyCh:=' '
                              Else C.EmptyCh:=S[1];
 End
  Else
 If Name='LANG'Then Begin
  NeedValue(Name,S,HasVal,I);
  SetLang(S);
 End
  Else
 If Name='FULL'Then C.Full:=True Else
 If Name='A'Then C.ShowSol:=True Else
 If Name='SOLONLY'Then C.SolOnly:=True Else
 If Name='NOGRID'Then C.NoGrid:=True Else
 If Name='NOCLUE'Then C.NoClue:=True Else
 If Name='G'Then C.Graphic:=True Else
 If Name='LC'Then C.Lower:=True Else
 If Name='CP437'Then C.CP437:=True Else
 If Name='ALL'Then C.NeedAll:=True Else
 If Name='V'Then C.Verbose:=True Else
 If Name='Q'Then C.Quiet:=True
            Else Fatal(1,Msg(1)+Name);
End;

Function IsOptName(Const S:String):Boolean;
Var
 I:Integer;
Begin
 IsOptName:=False;
 If S=''Then Exit;
 For I:=1 to Length(S)do Begin
  If Not(S[I]in['A'..'Z','a'..'z','0'..'9','?'])Then Exit;
 End;
 IsOptName:=True;
End;

Procedure ParseArgs(Var C:TCfg);
Var
 I,K,P:Integer;
 Arg,Name,S:String;
 HasVal,IsOpt:Boolean;
Begin
 I:=1;
 While I<=ParamCount do Begin
  Arg:=ParamStr(I);
  IsOpt:=False;
  If(Length(Arg)>1)and(Arg[1]in['/','-'])Then Begin
   K:=1;
   While(K<=Length(Arg))and(Arg[K]in['/','-'])do Inc(K);
   P:=K;
   While(P<=Length(Arg))and Not(Arg[P]in[':','='])do Inc(P);
   Name:=Copy(Arg,K,P-K);
   HasVal:=P<=Length(Arg);
   S:=Copy(Arg,P+1,255);
   IsOpt:=IsOptName(Name);
  End;
  If IsOpt Then ApplyOption(C,UpStr(Name),S,HasVal,I)
   Else
  If C.FileName=''Then C.FileName:=Arg
                  Else AddInline(C,Arg);
  Inc(I);
 End;
End;

{ ---------------------------------------------------------------------- }
{ Grille : placement des mots                                             }
{ ---------------------------------------------------------------------- }

Procedure GridInit(Var G:TGrid;W,H:Integer);Begin
 FillChar(G.Cells,SizeOf(G.Cells),Ord(' '));
 FillChar(G.Mask,SizeOf(G.Mask),0);
 G.W:=W;
 G.H:=H;
 G.Used:=0;
End;

{ Peut-on placer le mot T en (X,Y) dans la direction Dir ?
  Cross retourne le nombre de lettres communes avec les mots deja places. }
Function CanPlace(Var G:TGrid;Const T:String;X,Y,Dir:Integer;
                  Var Cross:Integer):Boolean;
Var
 L,DX,DY,I,CX,CY:Integer;
 C:Char;
Begin
 CanPlace:=False;
 Cross:=0;
 L:=Length(T);
 If Dir=DirAcross Then Begin
  DX:=1;
  DY:=0;
 End
  Else
 Begin
  DX:=0;
  DY:=1;
 End;
 If(X<1)or(Y<1)or(X+DX*(L-1)>G.W)or(Y+DY*(L-1)>G.H)Then Exit;
 { La case avant et la case apres le mot doivent etre vides }
 CX:=X-DX;
 CY:=Y-DY;
 If(CX>=1)and(CY>=1)Then If G.Cells[CY,CX]<>' 'Then Exit;
 CX:=X+DX*L;
 CY:=Y+DY*L;
 If(CX<=G.W)and(CY<=G.H)Then If G.Cells[CY,CX]<>' 'Then Exit;
 For I:=0 to L-1 do Begin
  CX:=X+DX*I;
  CY:=Y+DY*I;
  C:=G.Cells[CY,CX];
  If C=' 'Then Begin
   { Case libre : pas de lettre voisine de chaque cote du mot }
   If Dir=DirAcross Then Begin
    If CY>1 Then If G.Cells[CY-1,CX]<>' 'Then Exit;
    If CY<G.H Then If G.Cells[CY+1,CX]<>' 'Then Exit;
   End
    Else
   Begin
    If CX>1 Then If G.Cells[CY,CX-1]<>' 'Then Exit;
    If CX<G.W Then If G.Cells[CY,CX+1]<>' 'Then Exit;
   End;
  End
   Else
  Begin
   { Croisement : meme lettre, et pas de mot de meme sens }
   If C<>T[I+1]Then Exit;
   If(G.Mask[CY,CX]and Dir)<>0 Then Exit;
   Inc(Cross);
  End;
 End;
 If Cross>=L Then Exit;
 CanPlace:=True;
End;

Procedure PlaceWord(Var G:TGrid;Const T:String;X,Y,Dir:Integer);
Var
 I,CX,CY:Integer;
Begin
 CX:=X;
 CY:=Y;
 For I:=1 to Length(T)do Begin
  If G.Cells[CY,CX]=' 'Then Inc(G.Used);
  G.Cells[CY,CX]:=T[I];
  G.Mask[CY,CX]:=G.Mask[CY,CX]or Dir;
  If Dir=DirAcross Then Inc(CX)
                   Else Inc(CY);
 End;
End;

{ Retient la position si elle est meilleure (ou egale, tirage au sort) }
Procedure Consider(Var K:TCand;X,Y,Dir,C:Integer);Begin
 If C>K.Cross Then Begin
  K.Cross:=C;
  K.Ties:=1;
  K.X:=X;
  K.Y:=Y;
  K.Dir:=Dir;
 End
  Else
 If C=K.Cross Then Begin
  Inc(K.Ties);
  If Random(K.Ties)=0 Then Begin
   K.X:=X;
   K.Y:=Y;
   K.Dir:=Dir;
  End;
 End;
End;

{ Cherche la meilleure position du mot Idx. Retourne False si aucune. }
Function FindBest(Var G:TGrid;Var D:TDict;MinCross,Idx:Integer;
                  Var K:TCand):Boolean;
Var
 L,I,Dir,CX,CY,X,Y,C,Try:Integer;
 T:String;
Begin
 T:=D.Items[Idx].Txt;
 L:=Length(T);
 K.Cross:=-1;
 K.Ties:=0;
 K.X:=0;
 K.Y:=0;
 K.Dir:=0;
 If G.Used=0 Then Begin
  { Premier mot : au centre, avec un leger decalage aleatoire }
  If L<=G.W Then Dir:=DirAcross
            Else Dir:=DirDown;
  For Try:=1 to 6 do Begin
   If Dir=DirAcross Then Begin
    X:=(G.W-L)div 2+1;
    Y:=(G.H+1)div 2;
   End
    Else
   Begin
    X:=(G.W+1)div 2;
    Y:=(G.H-L)div 2+1;
   End;
   If Try<6 Then Begin
    X:=X+Random(3)-1;
    Y:=Y+Random(3)-1;
   End;
   If CanPlace(G,T,X,Y,Dir,C)Then Begin
    Consider(K,X,Y,Dir,0);
    Break;
   End;
  End;
 End
  Else
 If MinCross>0 Then Begin
  { Parcourt les lettres de la grille et les lettres identiques du mot }
  For CY:=1 to G.H do Begin
   For CX:=1 to G.W do Begin
    If G.Cells[CY,CX]<>' 'Then Begin
     For I:=1 to L do Begin
      If T[I]=G.Cells[CY,CX]Then Begin
       For Dir:=DirAcross to DirDown do Begin
        If(G.Mask[CY,CX]and Dir)=0 Then Begin
         If Dir=DirAcross Then Begin
          X:=CX-(I-1);
          Y:=CY;
         End
          Else
         Begin
          X:=CX;
          Y:=CY-(I-1);
         End;
         If CanPlace(G,T,X,Y,Dir,C)Then Begin
          If C>=MinCross Then Consider(K,X,Y,Dir,C);
         End;
        End;
       End;
      End;
     End;
    End;
   End;
  End;
 End
  Else
 Begin
  { Mots isoles permis : toutes les positions sont examinees }
  For Dir:=DirAcross to DirDown do Begin
   For Y:=1 to G.H do Begin
    For X:=1 to G.W do Begin
     If CanPlace(G,T,X,Y,Dir,C)Then Consider(K,X,Y,Dir,C);
    End;
   End;
  End;
 End;
 FindBest:=K.Dir>0;
End;

{ Construit l'ordre de traitement des mots }
Procedure BuildOrder(Var C:TCfg;Var D:TDict;TryNo:Integer;Var Seq:TOrder);
Var
 I,J,K,Tmp:Integer;
 Swap:Boolean;
Begin
 For I:=1 to D.Count do Seq[I]:=I;
 If C.Order<>'A'Then Begin
  For I:=D.Count downto 2 do Begin
   J:=Random(I)+1;
   Tmp:=Seq[I];
   Seq[I]:=Seq[J];
   Seq[J]:=Tmp;
  End;
 End;
 If C.Order in['L','S']Then Begin
  { Tri par insertion stable sur la longueur }
  For I:=2 to D.Count do Begin
   K:=Seq[I];
   J:=I-1;
   Swap:=True;
   While(J>=1)and Swap do Begin
    If C.Order='L'Then
     Swap:=Length(D.Items[Seq[J]].Txt)<Length(D.Items[K].Txt)
    Else
     Swap:=Length(D.Items[Seq[J]].Txt)>Length(D.Items[K].Txt);
    If Swap Then Begin
     Seq[J+1]:=Seq[J];
     Dec(J);
    End;
   End;
   Seq[J+1]:=K;
  End;
  { Apres le premier essai, on perturbe un peu l'ordre }
  If TryNo>1 Then Begin
   For I:=2 to D.Count-1 do Begin
    If Random(4)=0 Then Begin
     Tmp:=Seq[I];
     Seq[I]:=Seq[I+1];
     Seq[I+1]:=Tmp;
    End;
   End;
  End;
 End;
End;

{ Un essai complet de construction de grille }
Procedure RunTry(Var C:TCfg;Var D:TDict;Var G:TGrid;Var Seq:TOrder;
                 Var Sol:TSol);
Var
 K,I,J,Cnt,Crs:Integer;
 Prog:Boolean;
 Cand:TCand;
 X0,Y0,X1,Y1,EX,EY:Integer;
Begin
 GridInit(G,C.W,C.H);
 For I:=1 to D.Count do Begin
  D.Items[I].Placed:=False;
  D.Items[I].Dir:=0;
 End;
 Cnt:=0;
 Crs:=0;
 Repeat
  Prog:=False;
  For K:=1 to D.Count do Begin
   I:=Seq[K];
   If(Not D.Items[I].Placed)and(Cnt<C.MaxPlace)Then Begin
    If FindBest(G,D,C.MinCross,I,Cand)Then Begin
     PlaceWord(G,D.Items[I].Txt,Cand.X,Cand.Y,Cand.Dir);
     With D.Items[I]do Begin
      Placed:=True;
      X:=Cand.X;
      Y:=Cand.Y;
      Dir:=Cand.Dir;
     End;
     Inc(Cnt);
     If Cand.Cross>0 Then Inc(Crs,Cand.Cross);
     Prog:=True;
    End;
   End;
  End;
 Until(Not Prog)or(Cnt>=C.MaxPlace);
 { Resume de l'essai }
 X0:=MaxW+1;Y0:=MaxH+1;X1:=0;Y1:=0;
 For I:=1 to D.Count do Begin
  Sol.X[I]:=D.Items[I].X;
  Sol.Y[I]:=D.Items[I].Y;
  Sol.Dir[I]:=D.Items[I].Dir;
  If D.Items[I].Placed Then Begin
   J:=Length(D.Items[I].Txt)-1;
   EX:=D.Items[I].X;
   EY:=D.Items[I].Y;
   If D.Items[I].Dir=DirAcross Then Inc(EX,J)
                               Else Inc(EY,J);
   If D.Items[I].X<X0 Then X0:=D.Items[I].X;
   If D.Items[I].Y<Y0 Then Y0:=D.Items[I].Y;
   If EX>X1 Then X1:=EX;
   If EY>Y1 Then Y1:=EY;
  End;
 End;
 Sol.Placed:=Cnt;
 Sol.Cross:=Crs;
 If Cnt>0 Then Sol.Area:=(X1-X0+1)*(Y1-Y0+1)
          Else Sol.Area:=0;
 Sol.Valid:=True;
End;

{ La solution A est-elle meilleure que B ? }
Function Better(Var A,B:TSol):Boolean;Begin
 If Not B.Valid Then Better:=True Else
 If A.Placed<>B.Placed Then Better:=A.Placed>B.Placed Else
 If A.Cross<>B.Cross Then Better:=A.Cross>B.Cross
                     Else Better:=A.Area<B.Area;
End;

Procedure Generate(Var C:TCfg;Var D:TDict;Var G:TGrid;Var BestSol:TSol);
Var
 T,I:Integer;
 Seq:TOrder;
 Cur:TSol;
Begin
 BestSol.Valid:=False;
 For T:=1 to C.Tries do Begin
  BuildOrder(C,D,T,Seq);
  RunTry(C,D,G,Seq,Cur);
  If C.Verbose Then Begin
   MsgLn(Msg(19)+IntStr(T)+'/'+IntStr(C.Tries)+' : '+IntStr(Cur.Placed)+
         Msg(21)+IntStr(Cur.Cross)+Msg(22));
  End;
  If Better(Cur,BestSol)Then BestSol:=Cur;
 End;
 { Reconstruit la meilleure grille }
 GridInit(G,C.W,C.H);
 For I:=1 to D.Count do Begin
  With D.Items[I]do Begin
   Placed:=BestSol.Dir[I]>0;
   X:=BestSol.X[I];
   Y:=BestSol.Y[I];
   Dir:=BestSol.Dir[I];
   Num:=0;
   If Placed Then PlaceWord(G,Txt,X,Y,Dir);
  End;
 End;
End;

{ Numerote les mots (ordre de lecture) ; retourne le dernier numero }
Function NumberWords(Var G:TGrid;Var D:TDict):Integer;
Var
 X,Y,I,N:Integer;
 Started:Boolean;
Begin
 N:=0;
 For Y:=1 to G.H do Begin
  For X:=1 to G.W do Begin
   If G.Cells[Y,X]<>' 'Then Begin
    Started:=False;
    For I:=1 to D.Count do Begin
     If(D.Items[I].Placed)and(D.Items[I].X=X)and(D.Items[I].Y=Y)Then Begin
      If Not Started Then Begin
       Inc(N);
       Started:=True;
      End;
      D.Items[I].Num:=N;
     End;
    End;
   End;
  End;
 End;
 NumberWords:=N;
End;

{ Numero de la case (X,Y), 0 si aucune definition ne commence ici }
Function CellNum(Var D:TDict;CX,CY:Integer):Integer;
Var
 I:Integer;
Begin
 CellNum:=0;
 For I:=1 to D.Count do Begin
  If(D.Items[I].Placed)and(D.Items[I].X=CX)and(D.Items[I].Y=CY)Then Begin
   CellNum:=D.Items[I].Num;
   Exit;
  End;
 End;
End;

{ Zone de la grille a afficher (rognee ou complete) }
Procedure ComputeView(Var G:TGrid;Var C:TCfg;Var V:TView);
Var
 X,Y:Integer;
Begin
 V.X0:=1;
 V.Y0:=1;
 V.X1:=G.W;
 V.Y1:=G.H;
 If(Not C.Full)and(G.Used>0)Then Begin
  V.X0:=G.W;V.Y0:=G.H;V.X1:=1;V.Y1:=1;
  For Y:=1 to G.H do Begin
   For X:=1 to G.W do Begin
    If G.Cells[Y,X]<>' 'Then Begin
     If X<V.X0 Then V.X0:=X;
     If X>V.X1 Then V.X1:=X;
     If Y<V.Y0 Then V.Y0:=Y;
     If Y>V.Y1 Then V.Y1:=Y;
    End;
   End;
  End;
 End;
End;

{ ---------------------------------------------------------------------- }
{ Sortie texte                                                            }
{ ---------------------------------------------------------------------- }

Function LetterCh(Var C:TCfg;Ch:Char):Char;Begin
 If(C.Lower)and(Ch in['A'..'Z'])Then LetterCh:=Chr(Ord(Ch)+32)
                                Else LetterCh:=Ch;
End;

Function BlockChar(Var C:TCfg):Char;Begin
 If(C.Graphic)and Not C.BlockSet Then BlockChar:=Chr(178)
                                 Else BlockChar:=C.BlockCh;
End;

{ Ligne de separation : Kind 0=haut, 1=milieu, 2=bas }
Procedure PrintBorder(Var F:Text;Var C:TCfg;Var V:TView;Kind:Integer);
Var
 X,I:Integer;
 HCh,Left,Mid,Right:Char;
Begin
 If C.Graphic Then Begin
  HCh:=Chr(196);
  Case Kind of
   0:Begin Left:=Chr(218);Mid:=Chr(194);Right:=Chr(191);End;
   1:Begin Left:=Chr(195);Mid:=Chr(197);Right:=Chr(180);End;
   Else Begin Left:=Chr(192);Mid:=Chr(193);Right:=Chr(217);End;
  End;
 End
  Else
 Begin
  HCh:='-';
  Left:='+';
  Mid:='+';
  Right:='+';
 End;
 Write(F,Left);
 For X:=V.X0 to V.X1 do Begin
  For I:=1 to 4 do Write(F,HCh);
  If X<V.X1 Then Write(F,Mid)
            Else Write(F,Right);
 End;
 WriteLn(F);
End;

{ Dessine la grille (a remplir ou solution) }
Procedure PrintGrid(Var F:Text;Var C:TCfg;Var G:TGrid;Var D:TDict;
                    Var V:TView;Solution:Boolean);
Var
 X,Y,Line,N:Integer;
 VCh,BCh,Ch:Char;
Begin
 If C.Graphic Then VCh:=Chr(179)
              Else VCh:='|';
 BCh:=BlockChar(C);
 For Y:=V.Y0 to V.Y1 do Begin
  If Y=V.Y0 Then PrintBorder(F,C,V,0)
            Else PrintBorder(F,C,V,1);
  For Line:=1 to 2 do Begin
   Write(F,VCh);
   For X:=V.X0 to V.X1 do Begin
    If G.Cells[Y,X]=' 'Then Begin
     Write(F,BCh,BCh,BCh,BCh);
    End
     Else
    Begin
     If Line=1 Then Begin
      N:=CellNum(D,X,Y);
      If N>0 Then Write(F,PadR(IntStr(N),4))
             Else Write(F,'    ');
     End
      Else
     Begin
      If Solution Then Ch:=LetterCh(C,G.Cells[Y,X])
                  Else Ch:=C.EmptyCh;
      Write(F,' ',Ch,'  ');
     End;
    End;
    Write(F,VCh);
   End;
   WriteLn(F);
  End;
 End;
 PrintBorder(F,C,V,2);
End;

Function ClueText(Var D:TDict;I:Integer):String;
Var
 S:String;
Begin
 With D.Items[I]do Begin
  If Clue=''Then
   S:=Msg(10)+IntStr(Length(Txt))+Msg(11)
  Else
   S:=Clue+' ('+IntStr(Length(Txt))+')';
 End;
 ClueText:=S;
End;

Procedure PrintClues(Var F:Text;Var D:TDict;Dir,Last:Integer);
Var
 N,I:Integer;
Begin
 If Dir=DirAcross Then WriteLn(F,Msg(8))
                  Else WriteLn(F,Msg(9));
 For N:=1 to Last do Begin
  For I:=1 to D.Count do Begin
   If(D.Items[I].Placed)and(D.Items[I].Dir=Dir)and(D.Items[I].Num=N)Then Begin
    WriteLn(F,PadL(IntStr(N),4),'. ',ClueText(D,I));
   End;
  End;
 End;
 WriteLn(F);
End;

Procedure WriteText(Var F:Text;Var C:TCfg;Var G:TGrid;Var D:TDict;
                    Var V:TView;Last:Integer);
Var
 Title:String;
Begin
 Title:=Msg(7)+' ('+IntStr(V.X1-V.X0+1)+' x '+IntStr(V.Y1-V.Y0+1)+')';
 If Not C.SolOnly Then Begin
  WriteLn(F,Title);
  WriteLn(F);
  If Not C.NoGrid Then Begin
   PrintGrid(F,C,G,D,V,False);
   WriteLn(F);
  End;
  If Not C.NoClue Then Begin
   PrintClues(F,D,DirAcross,Last);
   PrintClues(F,D,DirDown,Last);
  End;
 End;
 If(C.ShowSol)or(C.SolOnly)Then Begin
  WriteLn(F,Title,' - ',Msg(20));
  WriteLn(F);
  PrintGrid(F,C,G,D,V,True);
  WriteLn(F);
 End;
End;

{ ---------------------------------------------------------------------- }
{ Sortie HTML                                                             }
{ ---------------------------------------------------------------------- }

Function HtmlEsc(Const S:String):String;
Var
 I:Integer;
 R:String;
Begin
 R:='';
 For I:=1 to Length(S)do Begin
  Case S[I]of
   '&':R:=R+'&amp;';
   '<':R:=R+'&lt;';
   '>':R:=R+'&gt;';
   '"':R:=R+'&quot;';
   Else R:=R+S[I];
  End;
 End;
 HtmlEsc:=R;
End;

Procedure HtmlTable(Var F:Text;Var C:TCfg;Var G:TGrid;Var D:TDict;
                    Var V:TView;Solution:Boolean);
Var
 X,Y,N:Integer;
Begin
 WriteLn(F,'<table class="cw">');
 For Y:=V.Y0 to V.Y1 do Begin
  Write(F,'<tr>');
  For X:=V.X0 to V.X1 do Begin
   If G.Cells[Y,X]=' 'Then Write(F,'<td class="b"></td>')
    Else
   Begin
    Write(F,'<td>');
    N:=CellNum(D,X,Y);
    If N>0 Then Write(F,'<span class="n">',N,'</span>');
    If Solution Then Write(F,LetterCh(C,G.Cells[Y,X]));
    Write(F,'</td>');
   End;
  End;
  WriteLn(F,'</tr>');
 End;
 WriteLn(F,'</table>');
End;

Procedure HtmlClues(Var F:Text;Var D:TDict;Dir,Last:Integer);
Var
 N,I:Integer;
Begin
 If Dir=DirAcross Then WriteLn(F,'<h2>',HtmlEsc(Msg(8)),'</h2>')
                  Else WriteLn(F,'<h2>',HtmlEsc(Msg(9)),'</h2>');
 WriteLn(F,'<ul class="cl">');
 For N:=1 to Last do Begin
  For I:=1 to D.Count do Begin
   If(D.Items[I].Placed)and(D.Items[I].Dir=Dir)and(D.Items[I].Num=N)Then Begin
    WriteLn(F,'<li><b>',N,'.</b> ',HtmlEsc(ClueText(D,I)),'</li>');
   End;
  End;
 End;
 WriteLn(F,'</ul>');
End;

Procedure WriteHtml(Var F:Text;Var C:TCfg;Var G:TGrid;Var D:TDict;
                    Var V:TView;Last:Integer);
Begin
 WriteLn(F,'<!DOCTYPE html>');
 WriteLn(F,'<html><head>');
 If C.SeenUtf8 Then WriteLn(F,'<meta charset="utf-8">')
  Else
 If C.CP437 Then WriteLn(F,'<meta charset="ibm437">')
             Else WriteLn(F,'<meta charset="iso-8859-1">');
 WriteLn(F,'<title>',HtmlEsc(Msg(7)),'</title>');
 WriteLn(F,'<style>');
 WriteLn(F,'body{font-family:sans-serif;margin:20px}');
 WriteLn(F,'table.cw{border-collapse:collapse;margin:10px 0}');
 WriteLn(F,'table.cw td{width:34px;height:34px;border:1px solid #000;');
 WriteLn(F,' position:relative;text-align:center;font:bold 18px monospace}');
 WriteLn(F,'td.b{background:#000}');
 WriteLn(F,'span.n{position:absolute;top:1px;left:2px;font:9px sans-serif}');
 WriteLn(F,'ul.cl{list-style:none;padding:0}');
 WriteLn(F,'</style></head><body>');
 WriteLn(F,'<h1>',HtmlEsc(Msg(7)),'</h1>');
 If Not C.SolOnly Then Begin
  If Not C.NoGrid Then HtmlTable(F,C,G,D,V,False);
  If Not C.NoClue Then Begin
   HtmlClues(F,D,DirAcross,Last);
   HtmlClues(F,D,DirDown,Last);
  End;
 End;
 If(C.ShowSol)or(C.SolOnly)Then Begin
  WriteLn(F,'<h2>',HtmlEsc(Msg(20)),'</h2>');
  HtmlTable(F,C,G,D,V,True);
 End;
 WriteLn(F,'</body></html>');
End;

{ ---------------------------------------------------------------------- }
{ Sortie CSV : numero;sens (H/V);x;y;mot;indice                           }
{ ---------------------------------------------------------------------- }

Procedure WriteCsv(Var F:Text;Var C:TCfg;Var D:TDict;Var V:TView;Last:Integer);
Var
 N,I,P:Integer;
 Dir:Integer;
 S,Cl,Ch:String;
Begin
 WriteLn(F,'NUM;DIR;X;Y;WORD;CLUE');
 For N:=1 to Last do Begin
  For Dir:=DirAcross to DirDown do Begin
   For I:=1 to D.Count do Begin
    If(D.Items[I].Placed)and(D.Items[I].Dir=Dir)and(D.Items[I].Num=N)Then Begin
     Cl:=D.Items[I].Clue;
     For P:=1 to Length(Cl)do If Cl[P]=';'Then Cl[P]:=',';
     If Dir=DirAcross Then Ch:='H'
                      Else Ch:='V';
     S:=D.Items[I].Txt;
     For P:=1 to Length(S)do S[P]:=LetterCh(C,S[P]);
     WriteLn(F,N,';',Ch,';',D.Items[I].X-V.X0+1,';',D.Items[I].Y-V.Y0+1,
             ';',S,';',Cl);
    End;
   End;
  End;
 End;
End;

{ ---------------------------------------------------------------------- }
{ Resume                                                                  }
{ ---------------------------------------------------------------------- }

Procedure ShowStats(Var C:TCfg;Var D:TDict;Var G:TGrid;Var V:TView;
                    Var Sol:TSol);
Var
 I,Area,Dens:Integer;
 S:String;
 First:Boolean;
Begin
 Area:=(V.X1-V.X0+1)*(V.Y1-V.Y0+1);
 If Area>0 Then Dens:=(G.Used*100)div Area
           Else Dens:=0;
 S:=Msg(12)+IntStr(Sol.Placed)+'/'+IntStr(D.Count);
 If D.Skipped>0 Then S:=S+Msg(13)+IntStr(D.Skipped)+')';
 MsgLn(S);
 MsgLn(Msg(14)+IntStr(V.X1-V.X0+1)+' x '+IntStr(V.Y1-V.Y0+1)+Msg(15)+
       IntStr(Sol.Cross)+Msg(16)+IntStr(Dens)+' %');
 MsgLn(Msg(17)+IntStr(C.Seed));
 If Sol.Placed<D.Count Then Begin
  S:=Msg(18);
  First:=True;
  For I:=1 to D.Count do Begin
   If Not D.Items[I].Placed Then Begin
    If Not First Then S:=S+', ';
    S:=S+D.Items[I].Txt;
    First:=False;
   End;
  End;
  MsgLn(S);
 End;
End;

{ ---------------------------------------------------------------------- }
{ Programme principal                                                     }
{ ---------------------------------------------------------------------- }

BEGIN
 InitDefaults(Cfg);
 SetLang(GetEnv('LANGUAGE'));
 ParseArgs(Cfg);
 If Cfg.LenMax>WordMax Then Cfg.LenMax:=WordMax;
 If Cfg.LenMin>Cfg.LenMax Then Fatal(1,Msg(3)+'MIN/MAX');
 Dict.Count:=0;
 Dict.Skipped:=0;
 If Cfg.FileName<>''Then Begin
  If Not LoadFile(Dict,Cfg,Cfg.FileName)Then Begin
   Fatal(2,Msg(4)+Cfg.FileName);
  End;
 End;
 LoadInline(Dict,Cfg);
 If(Cfg.FileName='')and(Cfg.InlineN=0)Then LoadBuiltIn(Dict,Cfg);
 If Dict.Count=0 Then Fatal(3,Msg(5));
 If Cfg.HasSeed Then RandSeed:=Cfg.Seed
  Else
 Begin
  Randomize;
  Cfg.Seed:=RandSeed;
 End;
 Generate(Cfg,Dict,Grid,Best);
 MaxNum:=NumberWords(Grid,Dict);
 ComputeView(Grid,Cfg,View);
 Assign(OutF,Cfg.OutName);
 {$I-}Rewrite(OutF);{$I+}
 If IOResult<>0 Then Fatal(2,Msg(6)+Cfg.OutName);
 Case Cfg.Fmt of
  'H':WriteHtml(OutF,Cfg,Grid,Dict,View,MaxNum);
  'C':WriteCsv(OutF,Cfg,Dict,View,MaxNum);
  Else WriteText(OutF,Cfg,Grid,Dict,View,MaxNum);
 End;
 Close(OutF);
 If Not Cfg.Quiet Then ShowStats(Cfg,Dict,Grid,View,Best);
 If(Cfg.NeedAll)and(Best.Placed<Dict.Count)Then Halt(4);
END.
