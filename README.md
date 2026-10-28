# VIE
Ce projet contient des commandes écrit en Pascal d'aide destiné à l'Intelligence artificielle (IA).

<h2>Liste des fichiers</h2>

Voici la liste des différents fichiers proposés dans VIE :

<table>
  <tr>
    <th>Commande</th>
    <th>Description</th>
   </tr>
  <tr>
     <td><b>CHATBOT.PAS</b></td>
     <td>Cette commande permet de lancer le Chatbot.</td>
  </tr>  
  <tr>
     <td><b>CLASSIFI.PAS</b></td>
     <td>Cette commande permet de demander une classification d'un texte.</td>
  </tr>
  <tr>
     <td><b>DETECLNG.PAS</b></td>
     <td>Cette commande permet de détecter le langage humain (français, anglais,...) dans lequel un  texte est écrit.</td>
  </tr>
  <tr>
     <td><b>DETECSEN.PAS</b></td>
     <td>Cette commande permet de détecter les sentiments dans un texte.</td>
  </tr> 
  <tr>
     <td><b>FINDANAG.PAS</b></td>
     <td>Cette commande permet de rechercher les anagrammes du mot spécifié.</td>
  </tr>
  <tr>
	<td><b>GSODOKU.PAS</b></td>
	<td>Cette commande permet de générer une matrice de nombre de 9 x 9 pour une solution possible dans une grille de jeu Sodoku.</td>
  </tr>
  <tr>
     <td><b>LLAMA-CLI.PAS</b></td>
     <td>Cette commande est un clone de llama-cli (llama.cpp) : elle charge un modèle GGUF et génère du texte ou converse (CPU seulement, Free Pascal requis, réseau Windows seulement).</td>
  </tr>
  <tr>
     <td><b>LLAMA-TOKENIZE.PAS</b></td>
     <td>Cette commande est un clone de llama-tokenize (llama.cpp) : elle tokenise un texte (<code>-p</code>, <code>-f</code> ou <code>--stdin</code>) avec le vocabulaire d'un modèle GGUF et affiche les jetons, leurs identifiants (<code>--ids</code>) ou leur nombre (<code>--show-count</code>). Seules les métadonnées du modèle sont lues (Free Pascal requis).</td>
  </tr>
  <tr>
     <td><b>LOREM.PAS</b></td>
     <td>Cette commande permet de générer du texte aléatoirement (Lorem Ipsum).</td>
  </tr>
  <tr>
     <td><b>MAKEDATA.PAS</b></td>
     <td>Cette commande permet de générer un fichier de données aléatoire selon la taille spécifié.</td>
  </tr>
  <tr>
     <td><b>MAKEMAZE.PAS</b></td>
     <td>Cette commande permet de générer un labyrinthe.</td>
  </tr>
  <tr>
     <td><b>SKILLS.PAS</b></td>
    <td>Cette commande permet de rechercher les compétences contenu dans un CV de format texte.</td>
  </tr>
  <tr>
     <td><b>SSODOKU.PAS</b></td>
     <td>Cette commande permet de lancer le Solveur Sodoku.</td>
  </tr>
  <tr>
      <td><b>TRANSLAT.PAS</b></td>
      <td>Cette commande permet de traduire du texte anglais en français.</td>
   </tr>
  <tr>
     <td><b>VTON.PAS</b></td>
     <td>Cette commande est un clone de VTON (Virtual Try-ON) : elle change ou essaie des vêtements sur une photo à l'aide d'un réseau de neurones SegFormer (fichier .safetensors), avec une demande en langage naturel, à instructions multiples (<code>-prompt "Change le chandail rouge en bleu, ajouter un foulard"</code>) : couleurs et motifs, ajout d'accessoires, de bijoux et de bas du corps (l'image est prolongée si le corps est coupé), coiffures, couleur des yeux, sourire, bras le long du corps, matières (corps d'or, métal, robot, statue, vêtement de chaîne d'or), peau (plus lisse, granuleuse, plus douce, peau de bébé), rajeunir / vieillir de N ans (rides, cernes, taches, cheveux gris), teinture des cheveux dont poivre et sel, image entière (plus lisse, plus floue, plus nette, plus réelle), arrière-plan (uni, transparent en PNG, ciel étoilé, ciel ensoleillé, coucher de soleil, flou, forêts tropicale / amazonienne / québécoise / canadienne / de conifères), scène de carrousel, poses et situations dessinées par le programme (bras croisés, main en V, doigt pointé, tête droite, auréole, sérieuse / triste, regard perdu, somnambule, saute, flotte, assis à une table, couché ou couché dans un lit, escalier, toit de niche, fil de fer, appuyé sur un meuble ; « à genoux » et « vélo » signalés comme non pris en charge), styles BD / croquis. Essayage réaliste d'une tenue photographiée sur mannequin (« Mets-lui cette tenue ») : taille déduite de la tête, peau du mannequin remplacée par celle de la personne, exposition et grain accordés. Calcul CPU multifil, GPU Direct3D 11 optionnel sous Windows, compilable en 32 bits (Free Pascal requis).</td>
  </tr>
</table>

<h2>Compilation</h2>
	
Les fichiers Pascal n'ont aucune dépendances, il suffit de télécharger le fichier désiré et de le compiler avec Free Pascal avec la syntaxe de commande  :

<pre><b>fpc</b> <i>LEFICHIER.PAS</i></pre>
	
Sinon, vous pouvez également le compiler avec le Turbo Pascal à l'aide de la syntaxe de commande suivante :	

<pre><b>tpc</b> <i>LEFICHIER.PAS</i></pre>
	
Par exemple, si vous voulez compiler TRANSLAT.PAS, vous devrez tapez la commande suivante :

<pre><b>fpc</b> TRANSLAT.PAS</pre>

<h2>Licence</h2>
<ul>
 <li>Le code source est publié sous la licence <a href="https://github.com/gladir/VIE/blob/master/LICENSE">MIT</a>.</li>
 <li>Le paquet original est publié sous la licence <a href="https://github.com/gladir/VIE/blob/master/LICENSE">MIT</a>.</li>
</ul>
