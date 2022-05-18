{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2022
  @website(https://www.gladir.com/vie)
  @abstract(Target: Turbo Pascal, Free Pascal)
}

Program TRANSLAT;

Uses Strings;

Type
 TraductionRec=Record
  CategoryMID:(_NIL,_CAR,_INFO,_HOUSE,_AVION,_BODY,_FOOD,_MUSIC,
  _DIGIT,_CAL,_GEO,_TOUR,_GAME);
  English,French:PChar;
 End;

Const
 TraductionWord:Array[1..315]of TraductionRec=(
   (CategoryMID:_NIL;English:'a';French:'un'),
   (CategoryMID:_INFO;English:'a block statement';French:'une instruction de bloc'),
   (CategoryMID:_NIL;English:'about';French:'a propos'),
   (CategoryMID:_NIL;English:'an';French:'un'),
   (CategoryMID:_NIL;English:'and';French:'et'),
   (CategoryMID:_NIL;English:'arise';French:'relever'),
   (CategoryMID:_NIL;English:'arise';French:'surgir'),
   (CategoryMID:_NIL;English:'as a side effect of expression evaluation';
                     French:'en tant qu''effet secondaire de l''‚valuation de l''expression'),
   (CategoryMID:_NIL;English:'as already described';French:'comme d‚j… d‚crit'),
   (CategoryMID:_NIL;English:'as usual';French:'comme d''habitude'),
   (CategoryMID:_NIL;English:'ask';French:'demander'),
   (CategoryMID:_NIL;English:'assembly language';French:'langage assembleur'),
   (CategoryMID:_NIL;English:'assembly language programmers';French:'les programmeurs en langage assembleur'),
   (CategoryMID:_NIL;English:'available';French:'disponible'),
   (CategoryMID:_NIL;English:'awake';French:'‚veiller'),
   (CategoryMID:_NIL;English:'back it up';French:'sauvegardez-le'),
   (CategoryMID:_NIL;English:'be';French:'ˆtre'),
   (CategoryMID:_NIL;English:'bear';French:'porter'),
   (CategoryMID:_NIL;English:'beat';French:'battre'),
   (CategoryMID:_NIL;English:'became';French:'devenir'),
   (CategoryMID:_NIL;English:'begin';French:'commencer'),
   (CategoryMID:_NIL;English:'bend';French:'courber'),
   (CategoryMID:_NIL;English:'bend';French:'plier'),
   (CategoryMID:_NIL;English:'bet';French:'parier'),
   (CategoryMID:_NIL;English:'bid';French:'offrir'),
   (CategoryMID:_NIL;English:'bind';French:'relier'),
   (CategoryMID:_NIL;English:'bite';French:'mordre'),
   (CategoryMID:_NIL;English:'bleed';French:'saigner'),
   (CategoryMID:_NIL;English:'blow';French:'souffler'),
   (CategoryMID:_NIL;English:'break';French:'casser'),
   (CategoryMID:_NIL;English:'break';French:'briser'),
   (CategoryMID:_NIL;English:'breed';French:'‚lever'),
   (CategoryMID:_NIL;English:'bring';French:'amener'),
   (CategoryMID:_NIL;English:'bring';French:'apporter'),
   (CategoryMID:_INFO;English:'buffer';French:'tampon'),
   (CategoryMID:_NIL;English:'build';French:'bƒtir'),
   (CategoryMID:_NIL;English:'burn';French:'br–ler'),
   (CategoryMID:_NIL;English:'burst';French:'‚clater'),
   (CategoryMID:_NIL;English:'burst';French:'crever'),
   (CategoryMID:_NIL;English:'buy';French:'acheter'),
   (CategoryMID:_NIL;English:'by';French:'par'),
   (CategoryMID:_NIL;English:'can';French:'peut'),
   (CategoryMID:_NIL;English:'cast';French:'jeter'),
   (CategoryMID:_NIL;English:'cast';French:'semer'),
   (CategoryMID:_NIL;English:'cast';French:'changer'),
   (CategoryMID:_NIL;English:'catch';French:'saisir'),
   (CategoryMID:_NIL;English:'catch';French:'attraper'),
   (CategoryMID:_NIL;English:'choose';French:'choisir'),
   (CategoryMID:_NIL;English:'cling';French:'cramponner'),
   (CategoryMID:_NIL;English:'come';French:'venir'),
   (CategoryMID:_NIL;English:'computer';French:'ordinateur'),
   (CategoryMID:_NIL;English:'communications protocol';French:'protocole de communication'),
   (CategoryMID:_NIL;English:'cost';French:'co–ter'),
   (CategoryMID:_NIL;English:'could';French:'pouvoir'),
   (CategoryMID:_NIL;English:'creep';French:'ramper'),
   (CategoryMID:_NIL;English:'cut';French:'couper'),
   (CategoryMID:_NIL;English:'deal';French:'traiter'),
   (CategoryMID:_NIL;English:'device';French:'p‚riph‚rique'),
   (CategoryMID:_NIL;English:'devices';French:'p‚riph‚riques'),
   (CategoryMID:_NIL;English:'dig';French:'creuser'),
   (CategoryMID:_NIL;English:'displayed';French:'affich‚'),
   (CategoryMID:_NIL;English:'dive';French:'plonger'),
   (CategoryMID:_NIL;English:'do';French:'faire'),
   (CategoryMID:_INFO;English:'download';French:'t‚l‚chargement'),
   (CategoryMID:_NIL;English:'draw';French:'tirer'),
   (CategoryMID:_NIL;English:'dream';French:'rˆver'),
   (CategoryMID:_NIL;English:'drink';French:'boire'),
   (CategoryMID:_NIL;English:'drive';French:'conduire'),
   (CategoryMID:_NIL;English:'dwell';French:'r‚sider'),
   (CategoryMID:_NIL;English:'eat';French:'manger'),
   (CategoryMID:_NIL;English:'editor';French:'editeur'),
   (CategoryMID:_NIL;English:'editor-in-chief';French:'r‚dacteur en chef'),
   (CategoryMID:_NIL;English:'either';French:'soit'),
   (CategoryMID:_NIL;English:'exit';French:'sortie'),
   (CategoryMID:_NIL;English:'fall';French:'tomber'),
   (CategoryMID:_NIL;English:'feature';French:'fonctionnalit‚'),
   (CategoryMID:_NIL;English:'feed';French:'nourir'),
   (CategoryMID:_NIL;English:'feel';French:'sentir'),
   (CategoryMID:_NIL;English:'feel';French:'ressentir'),
   (CategoryMID:_NIL;English:'few';French:'peu'),
   (CategoryMID:_NIL;English:'fight';French:'combattre'),
   (CategoryMID:_NIL;English:'file format';French:'format de fichier'),
   (CategoryMID:_NIL;English:'find';French:'trouver'),
   (CategoryMID:_NIL;English:'flee';French:'fuir'),
   (CategoryMID:_NIL;English:'fling';French:'lancer'),
   (CategoryMID:_NIL;English:'fling';French:'jeter'),
   (CategoryMID:_NIL;English:'fly';French:'voler'),
   (CategoryMID:_NIL;English:'fly';French:'s''envoler'),
   (CategoryMID:_NIL;English:'folder';French:'dossier'),
   (CategoryMID:_NIL;English:'following';French:'suivantes'),
   (CategoryMID:_NIL;English:'for';French:'pour'),
   (CategoryMID:_NIL;English:'for over a decade';French:'depuis plus d''une d‚cennie'),
   (CategoryMID:_NIL;English:'for two years';French:'pendant deux ans'),
   (CategoryMID:_NIL;English:'forbid';French:'interdire'),
   (CategoryMID:_NIL;English:'forget';French:'oublier'),
   (CategoryMID:_NIL;English:'forgive';French:'pardonner'),
   (CategoryMID:_NIL;English:'freeze';French:'geler'),
   (CategoryMID:_NIL;English:'from';French:'… partir de'),
   (CategoryMID:_NIL;English:'functions';French:'fonctions'),
   (CategoryMID:_NIL;English:'game';French:'jeu'),
   (CategoryMID:_NIL;English:'game devices';French:'appareils de jeu'),
   (CategoryMID:_NIL;English:'get';French:'obtenir'),
   (CategoryMID:_NIL;English:'give';French:'donner'),
   (CategoryMID:_NIL;English:'go';French:'aller'),
   (CategoryMID:_NIL;English:'grind';French:'broyer'),
   (CategoryMID:_NIL;English:'grow';French:'grandir'),
   (CategoryMID:_NIL;English:'hang';French:'pendre'),
   (CategoryMID:_NIL;English:'hang';French:'accrocher'),
   (CategoryMID:_NIL;English:'have';French:'avoir'),
   (CategoryMID:_NIL;English:'he';French:'il'),
   (CategoryMID:_NIL;English:'he''s written';French:'il ‚crit'),
   (CategoryMID:_NIL;English:'hear';French:'entendre'),
   (CategoryMID:_NIL;English:'her';French:'ta'),
   (CategoryMID:_NIL;English:'hers';French:'sienne'),
   (CategoryMID:_NIL;English:'herself';French:'elle-mˆme'),
   (CategoryMID:_NIL;English:'hide';French:'cacher'),
   (CategoryMID:_NIL;English:'him';French:'ton'),
   (CategoryMID:_NIL;English:'himself';French:'lui-mˆme'),
   (CategoryMID:_NIL;English:'his';French:'son'),
   (CategoryMID:_NIL;English:'his';French:'siens'),
   (CategoryMID:_NIL;English:'hit';French:'frapper'),
   (CategoryMID:_NIL;English:'hold';French:'tenir'),
   (CategoryMID:_NIL;English:'hurt';French:'blesser'),
   (CategoryMID:_NIL;English:'I';French:'je'),
   (CategoryMID:_NIL;English:'in';French:'en'),
   (CategoryMID:_NIL;English:'in both';French:'en'),
   (CategoryMID:_NIL;English:'is';French:'est'),
   (CategoryMID:_NIL;English:'it';French:'il'),
   (CategoryMID:_NIL;English:'it';French:'ton'),
   (CategoryMID:_NIL;English:'it';French:'ta'),
   (CategoryMID:_NIL;English:'its';French:'sa'),
   (CategoryMID:_NIL;English:'itself';French:'lui-mˆme'),
   (CategoryMID:_NIL;English:'just take';French:'prenez simplement'),
   (CategoryMID:_NIL;English:'keep';French:'garder'),
   (CategoryMID:_NIL;English:'kneel';French:'s''agenouiller'),
   (CategoryMID:_NIL;English:'knit';French:'tricoter'),
   (CategoryMID:_NIL;English:'know';French:'savoir'),
   (CategoryMID:_NIL;English:'know';French:'connaitre'),
   (CategoryMID:_NIL;English:'lay';French:'‚tendre'),
   (CategoryMID:_NIL;English:'lead';French:'conduire'),
   (CategoryMID:_NIL;English:'lead';French:'mener'),
   (CategoryMID:_NIL;English:'leap';French:'sauter'),
   (CategoryMID:_NIL;English:'leap';French:'bondir'),
   (CategoryMID:_NIL;English:'learn';French:'apprendre'),
   (CategoryMID:_NIL;English:'leave';French:'laisser'),
   (CategoryMID:_NIL;English:'lend';French:'prˆter'),
   (CategoryMID:_NIL;English:'let';French:'laisser'),
   (CategoryMID:_NIL;English:'lets you change';French:'vous permet de modifier'),
   (CategoryMID:_NIL;English:'lie';French:'ˆtre couch‚'),
   (CategoryMID:_NIL;English:'light';French:'l‚ger'),
   (CategoryMID:_NIL;English:'light';French:'‚clairer'),
   (CategoryMID:_NIL;English:'lose';French:'perdre'),
   (CategoryMID:_NIL;English:'make';French:'fabriquer'),
   (CategoryMID:_NIL;English:'me';French:'moi'),
   (CategoryMID:_NIL;English:'mean';French:'signifier'),
   (CategoryMID:_NIL;English:'meet';French:'rencontrer'),
   (CategoryMID:_NIL;English:'mine';French:'miens'),
   (CategoryMID:_NIL;English:'mistake';French:'se tromper'),
   (CategoryMID:_NIL;English:'move it';French:'d‚placez-le'),
   (CategoryMID:_NIL;English:'mow';French:'tondre'),
   (CategoryMID:_NIL;English:'my';French:'mon'),
   (CategoryMID:_NIL;English:'myself';French:'moi-mˆme'),
   (CategoryMID:_NIL;English:'obtained';French:'obtenues'),
   (CategoryMID:_NIL;English:'of';French:'de'),
   (CategoryMID:_NIL;English:'or';French:'ou'),
   (CategoryMID:_NIL;English:'or higher';French:'ou sup‚rieur'),
   (CategoryMID:_NIL;English:'our';French:'notre'),
   (CategoryMID:_NIL;English:'our';French:'nos'),
   (CategoryMID:_NIL;English:'ours';French:'n“tre'),
   (CategoryMID:_NIL;English:'ours';French:'notres'),
   (CategoryMID:_NIL;English:'ourselves';French:'nous-mˆme'),
   (CategoryMID:_NIL;English:'pay';French:'payer'),
   (CategoryMID:_NIL;English:'programmers';French:'programmeurs'),
   (CategoryMID:_NIL;English:'put';French:'mettre'),
   (CategoryMID:_NIL;English:'read';French:'lire'),
   (CategoryMID:_NIL;English:'replaced';French:'replac‚'),
   (CategoryMID:_NIL;English:'retrieves';French:'r‚cupŠre'),
   (CategoryMID:_NIL;English:'returns';French:'renvoie'),
   (CategoryMID:_NIL;English:'rid';French:'d‚barrasser'),
   (CategoryMID:_NIL;English:'ride';French:'monter'),
   (CategoryMID:_NIL;English:'ring';French:'sonner'),
   (CategoryMID:_NIL;English:'rise';French:'se lever'),
   (CategoryMID:_NIL;English:'run';French:'courir'),
   (CategoryMID:_NIL;English:'run';French:'fonctionner'),
   (CategoryMID:_NIL;English:'saw';French:'scier'),
   (CategoryMID:_NIL;English:'say';French:'dire'),
   (CategoryMID:_NIL;English:'seconds';French:'secondes'),
   (CategoryMID:_NIL;English:'see';French:'voir'),
   (CategoryMID:_NIL;English:'seek';French:'chercher'),
   (CategoryMID:_NIL;English:'sell';French:'vendre'),
   (CategoryMID:_NIL;English:'send';French:'envoyer'),
   (CategoryMID:_NIL;English:'set';French:'poser'),
   (CategoryMID:_NIL;English:'set';French:'placer'),
   (CategoryMID:_NIL;English:'set';French:'fixer'),
   (CategoryMID:_NIL;English:'sew';French:'coudre'),
   (CategoryMID:_NIL;English:'shake';French:'secouer'),
   (CategoryMID:_NIL;English:'she';French:'elle'),
   (CategoryMID:_NIL;English:'shed';French:'r‚pandre'),
   (CategoryMID:_NIL;English:'shine';French:'briller'),
   (CategoryMID:_NIL;English:'shoot';French:'lancer'),
   (CategoryMID:_NIL;English:'shoot';French:'tirer'),
   (CategoryMID:_NIL;English:'should be';French:'doit ˆtre'),
   (CategoryMID:_NIL;English:'show';French:'montrer'),
   (CategoryMID:_NIL;English:'shut';French:'fermer'),
   (CategoryMID:_NIL;English:'shut';French:'‚teindre'),
   (CategoryMID:_NIL;English:'sing';French:'chanter'),
   (CategoryMID:_NIL;English:'sink';French:'enfoncer'),
   (CategoryMID:_NIL;English:'sit';French:'asseoir'),
   (CategoryMID:_NIL;English:'slay';French:'tuer'),
   (CategoryMID:_NIL;English:'sleep';French:'dormir'),
   (CategoryMID:_NIL;English:'slide';French:'glisser'),
   (CategoryMID:_NIL;English:'slit';French:'fendre'),
   (CategoryMID:_NIL;English:'slit';French:'inciser'),
   (CategoryMID:_NIL;English:'smell';French:'sentir'),
   (CategoryMID:_NIL;English:'sow';French:'semer'),
   (CategoryMID:_NIL;English:'speak';French:'parler'),
   (CategoryMID:_NIL;English:'speed';French:'acc‚l‚rer'),
   (CategoryMID:_NIL;English:'spell';French:'‚peler'),
   (CategoryMID:_NIL;English:'spend';French:'d‚penser'),
   (CategoryMID:_NIL;English:'spill';French:'renverser'),
   (CategoryMID:_NIL;English:'spin';French:'tournoyer'),
   (CategoryMID:_NIL;English:'spit';French:'cracher'),
   (CategoryMID:_NIL;English:'split';French:'fendre'),
   (CategoryMID:_NIL;English:'split';French:'partager'),
   (CategoryMID:_NIL;English:'spoil';French:'gˆter'),
   (CategoryMID:_NIL;English:'spread';French:'‚tendre'),
   (CategoryMID:_NIL;English:'spring';French:'bondir'),
   (CategoryMID:_NIL;English:'stand';French:'se tenir debout'),
   (CategoryMID:_NIL;English:'statement';French:'instruction'),
   (CategoryMID:_NIL;English:'steal';French:'voler'),
   (CategoryMID:_NIL;English:'steal';French:'d‚rober'),
   (CategoryMID:_NIL;English:'stick';French:'enfoncer'),
   (CategoryMID:_NIL;English:'stink';French:'puer'),
   (CategoryMID:_NIL;English:'strike';French:'frapper'),
   (CategoryMID:_INFO;English:'string';French:'chaine de caractŠres'),
   (CategoryMID:_NIL;English:'string';French:'ficele'),
   (CategoryMID:_NIL;English:'swear';French:'jurer'),
   (CategoryMID:_NIL;English:'sweat';French:'transpirer'),
   (CategoryMID:_NIL;English:'sweat';French:'suer'),
   (CategoryMID:_NIL;English:'sweep';French:'balayer'),
   (CategoryMID:_NIL;English:'swell';French:'gonfler'),
   (CategoryMID:_NIL;English:'swim';French:'nager'),
   (CategoryMID:_NIL;English:'swing';French:'balancer'),
   (CategoryMID:_NIL;English:'take';French:'prendre'),
   (CategoryMID:_NIL;English:'teach';French:'enseigner'),
   (CategoryMID:_NIL;English:'tear';French:'d‚chirer'),
   (CategoryMID:_NIL;English:'technology';French:'technologie'),
   (CategoryMID:_NIL;English:'tell';French:'dire'),
   (CategoryMID:_NIL;English:'tell';French:'raconter'),
   (CategoryMID:_NIL;English:'text';French:'texte'),
   (CategoryMID:_NIL;English:'text editor';French:'‚diteur de texte'),
   (CategoryMID:_NIL;English:'that';French:'que'),
   (CategoryMID:_NIL;English:'that notification';French:'que l''avertissement'),
   (CategoryMID:_NIL;English:'the';French:'le'),
   (CategoryMID:_NIL;English:'the following exit values';French:'les valeurs de sortie suivantes'),
   (CategoryMID:_NIL;English:'the mouse';French:'la souris'),
   (CategoryMID:_NIL;English:'the serial ports';French:'les ports s‚rie'),
   (CategoryMID:_NIL;English:'the state';French:'l''‚tat'),
   (CategoryMID:_NIL;English:'the time';French:'la dur‚e'),
   (CategoryMID:_NIL;English:'there are';French:'il y a'),
   (CategoryMID:_NIL;English:'their';French:'leurs'),
   (CategoryMID:_NIL;English:'theirs';French:'leurs'),
   (CategoryMID:_NIL;English:'them';French:'eux'),
   (CategoryMID:_NIL;English:'themselves';French:'eux-mˆme'),
   (CategoryMID:_NIL;English:'there are a few important differences, though';
                     French:'il y a cependant quelques diff‚rences importantes'),
   (CategoryMID:_NIL;English:'they';French:'ils'),
   (CategoryMID:_NIL;English:'they';French:'elles'),
   (CategoryMID:_NIL;English:'think';French:'penser'),
   (CategoryMID:_NIL;English:'this';French:'cet'),
   (CategoryMID:_NIL;English:'though';French:'mais'),
   (CategoryMID:_NIL;English:'throw';French:'lancer'),
   (CategoryMID:_NIL;English:'to';French:'au'),
   (CategoryMID:_NIL;English:'to another';French:'sur un autre'),
   (CategoryMID:_NIL;English:'to go through';French:'… refaire'),
   (CategoryMID:_NIL;English:'too';French:'aussi'),
   (CategoryMID:_NIL;English:'tread';French:'marcher'),
   (CategoryMID:_NIL;English:'typical';French:'typique'),
   (CategoryMID:_NIL;English:'understand';French:'comprendre'),
   (CategoryMID:_NIL;English:'undo';French:'d‚faire'),
   (CategoryMID:_INFO;English:'upload';French:'t‚l‚versement'),
   (CategoryMID:_NIL;English:'upset';French:'bouleverser'),
   (CategoryMID:_NIL;English:'us';French:'nous'),
   (CategoryMID:_NIL;English:'us';French:'notre'),
   (CategoryMID:_NIL;English:'us';French:'nos'),
   (CategoryMID:_NIL;English:'values';French:'valeurs'),
   (CategoryMID:_NIL;English:'very quickly';French:'trŠs rapidement'),
   (CategoryMID:_NIL;English:'wake';French:'r‚veiller'),
   (CategoryMID:_NIL;English:'want';French:'vouloir'),
   (CategoryMID:_NIL;English:'was';French:'a ‚t‚'),
   (CategoryMID:_NIL;English:'whatever else you named it';French:'tout autre nom que vous lui avez donn‚'),
   (CategoryMID:_NIL;English:'wear';French:'porter'),
   (CategoryMID:_NIL;English:'weave';French:'tisser'),
   (CategoryMID:_NIL;English:'weep';French:'pleurer'),
   (CategoryMID:_NIL;English:'with';French:'avec'),
   (CategoryMID:_NIL;English:'win';French:'gagner'),
   (CategoryMID:_NIL;English:'wind';French:'enrouler'),
   (CategoryMID:_NIL;English:'withdraw';French:'retirer'),
   (CategoryMID:_NIL;English:'withstand';French:'r‚sister'),
   (CategoryMID:_NIL;English:'work';French:'travailler'),
   (CategoryMID:_NIL;English:'wring';French:'tordre'),
   (CategoryMID:_NIL;English:'write';French:'‚crire'),
   (CategoryMID:_NIL;English:'you';French:'tu'),
   (CategoryMID:_NIL;English:'you';French:'vous'),
   (CategoryMID:_NIL;English:'you';French:'votre'),
   (CategoryMID:_NIL;English:'you';French:'vos'),
   (CategoryMID:_NIL;English:'you don''t have';French:'vous n''aurez pas'),
   (CategoryMID:_NIL;English:'you too';French:'toi aussi'),
   (CategoryMID:_NIL;English:'your';French:'ton'),
   (CategoryMID:_NIL;English:'your';French:'votre'),
   (CategoryMID:_NIL;English:'your';French:'vos'),
   (CategoryMID:_NIL;English:'yours';French:'tiens'),
   (CategoryMID:_NIL;English:'yours';French:'v“tre'),
   (CategoryMID:_NIL;English:'yours';French:'votres'),
   (CategoryMID:_NIL;English:'yourself';French:'toi-mˆme'),
   (CategoryMID:_NIL;English:'yourselves';French:'vous-mˆme')
 );

Var
 BeginWord,I,J:Integer;
 Mode:(_None,_French,_English);
 FoundMultiWord:Boolean;
 SourceFile:Text;
 FileName,CurrLine,CurrWord:String;

Function StrToUpper(S:String):String;
Var
 I:Byte;
Begin
 For I:=1 to Length(S)do Begin
  If S[I] in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
 End;
 StrToUpper:=S;
End;

Function IsLetter(Chr:Char):Boolean;Begin
 IsLetter:=Chr in ['A'..'Z','a'..'z','‚','ˆ','Š','…','ƒ','“','‡'];
End;

Function TranslateWord:Boolean;
Var
 FoundWord,SkipWord:Boolean;
Begin
 FoundWord:=False;
 For J:=Low(TraductionWord) to High(TraductionWord) do Begin
  If StrToUpper(StrPas(TraductionWord[J].English))=StrToUpper(CurrWord)Then Begin
   FoundWord:=True;
   If BeginWord=1 Then Begin
    Write(StrToUpper(Copy(StrPas(TraductionWord[J].French),1,1)),
                     Copy(StrPas(TraductionWord[J].French),2,255));
   End
    Else
   Write(StrPas(TraductionWord[J].French));
   Break;
  End;
 End;
 If Not(FoundWord)Then Begin
  Write(CurrWord);
 End;
 TranslateWord:=FoundWord;
End;

Procedure ParseLineEnglish;Begin
 CurrWord:='';
 BeginWord:=1;
 For I:=1 to Length(CurrLine)do Begin
  If(IsLetter(CurrLine[I]))Then CurrWord:=CurrWord+CurrLine[I]
   Else
  Begin
   FoundMultiWord:=False;
   For J:=Low(TraductionWord) to High(TraductionWord) do Begin
    If(StrLen(TraductionWord[J].English)>Length(CurrWord))and
      (StrToUpper(StrPas(TraductionWord[J].English))=
      StrToUpper(Copy(CurrLine,BeginWord,StrLen(TraductionWord[J].English))))Then Begin
     FoundMultiWord:=True;
     Break;
    End;
   End;
   If(FoundMultiWord)Then Begin
    CurrWord:=CurrWord+CurrLine[I]
   End
    Else
   Begin
    TranslateWord;
    Write(CurrLine[I]);
    CurrWord:='';
    BeginWord:=I+1;
   End;
  End;
 End;
 TranslateWord;
End;

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('TRANSLAT : Cette commande permet de traduire du texte.');
  WriteLn;
  WriteLn('Syntaxe : TRANSLAT [/ENGLISH] "message"');
  WriteLn('          TRANSLAT [/FRENCH] "message"');
  WriteLn('          TRANSLAT [/FRENCH] /FILE:fichier');
  WriteLn;
  WriteLn(' /ENGLISH  Traduit en anglais');
  WriteLn(' /FRENCH   Traduit en francais');
 End
  Else
 Begin
  FileName:='';
  CurrLine:='';
  Mode:=_French;
  For I:=1 to ParamCount do Begin
   If StrToUpper(ParamStr(I))='/FRENCH'Then Mode:=_French Else
   If StrToUpper(ParamStr(I))='/ENGLISH'Then Mode:=_English Else
   If StrToUpper(Copy(ParamStr(I),1,6))='/FILE:'Then Begin
    FileName:=Copy(ParamStr(I),7,255);
   End
    Else
   Begin
    If CurrLine=''Then CurrLine:=ParamStr(I)
                  Else CurrLine:=CurrLine+' '+ParamStr(I);
   End;
  End;
  If Mode=_None Then Begin
   WriteLn('Vous devez indiquez en quelle langue le texte doit ˆtre traduit');
   Halt;
  End
   Else
  If(Mode=_English)Then Begin
   WriteLn('Option non implementer');
   Halt;
  End
   Else
  Begin
   If FileName<>''Then Begin
    Assign(SourceFile,FileName);
    Reset(SourceFile);
    While Not EOF(SourceFile)do Begin
     ReadLn(SourceFile,CurrLine);
     ParseLineEnglish;
     WriteLn;
    End;
    Close(SourceFile);
   End
    Else
   ParseLineEnglish;
  End;
 End;
END.
