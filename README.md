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
     <td>Cette commande permet de charger un modèle GGUF et génère du texte ou converse.</td>
  </tr>
  <tr>
     <td><b>LLAMA-TOKENIZE.PAS</b></td>
     <td>Cette commande permet de tokeniser un texte (<code>-p</code>, <code>-f</code> ou <code>--stdin</code>) avec le vocabulaire d'un modèle GGUF et affiche les jetons, leurs identifiants (<code>--ids</code>) ou leur nombre (<code>--show-count</code>).</td>
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
     <td><b>OPTIMUM-CLI.PAS</b></td>
     <td>Cette commande permet de convertir un modèle LLaMA (config.json + safetensors) au format OpenVINO IR et de compresser ses poids (<code>export openvino --weight-format fp32|fp16|int8|int4|nf4</code>), à la manière de <code>optimum-cli export openvino</code>.</td>
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
     <td>Cette commande permet de changer ou d'essayer des vêtements sur une photo à l'aide d'un réseau de neurones SegFormer (fichier .safetensors), avec une demande en langage naturel, à instructions multiples.</td>
  </tr>
</table>

<h2>Remarque</h2>

<ul>
	<li>ATTENTION ! Certaines commandes comme LLAMA-CLI peuvent nécessité du GPU très puissant pour des performances acceptables, car le CPU a lui seul ne fournit pas des resultats très rapide :</li>
    <img width="1243" height="517" alt="image" src="https://github.com/user-attachments/assets/c28b8e9f-ce4a-449f-8c66-efe707521362" />
</ul>

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
