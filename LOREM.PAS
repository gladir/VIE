{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2022
  @website(https://www.gladir.com/vie)
  @abstract(Target: Turbo Pascal, Free Pascal)
}

Program LOREM;

Uses Strings;

Const
 Words:Array[0..177]of PChar=(
  'lorem','ipsum','dolor','sit','amet','consectetur','adipiscing',
  'elit','curabitur','vel','hendrerit','libero','eleifend',
  'blandit','nunc','ornare','odio','ut','orci','gravida',
  'imperdiet','nullam','purus','lacinia','a','pretium','quis',
  'congue','praesent','sagittis','laoreet','auctor','mauris',
  'non','velit','eros','dictum','proin','accumsan','sapien','nec',
  'massa','volutpat','venenatis','sed','eu','molestie','lacus',
  'quisque','porttitor','ligula','dui','mollis','tempus','at',
  'magna','vestibulum','turpis','ac','diam','tincidunt','id',
  'condimentum','enim','sodales','in','hac','habitasse','platea',
  'dictumst','aenean','neque','fusce','augue','leo','eget','semper',
  'mattis','tortor','scelerisque','nulla','interdum','tellus',
  'malesuada','rhoncus','porta','sem','aliquet','et','nam',
  'suspendisse','potenti','vivamus','luctus','fringilla','erat',
  'donec','justo','vehicula','ultricies','varius','ante','primis',
  'faucibus','ultrices','posuere','cubilia','curae','etiam',
  'cursus','aliquam','quam','dapibus','nisl','feugiat','egestas',
  'class','aptent','taciti','sociosqu','ad','litora','torquent',
  'per','conubia','nostra','inceptos','himenaeos','phasellus',
  'nibh','pulvinar','vitae','urna','iaculis','lobortis','nisi',
  'viverra','arcu','morbi','pellentesque','metus','commodo',
  'ut','facilisis','felis','tristique','ullamcorper','placerat',
  'aenean','convallis','sollicitudin','integer','rutrum','duis',
  'est','etiam','bibendum','donec','pharetra','vulputate',
  'maecenas','mi','fermentum','consequat','suscipit','aliquam',
  'habitant','senectus','netus','fames','quisque','euismod',
  'curabitur','lectus','elementum','tempor','risus','cras'
 );

Function StrToCapital(S:String):String;Begin
 If Length(S)=0 Then StrToCapital:=''
                Else StrToCapital:=UpCase(S[1])+Copy(S,2,255);
End;

Function Gauss:Real;
Var
 U,V,X,Y:Real;
Begin
 X:=Random;
 Y:=Random;
 U:=Sqrt(-2*Ln(X))*Cos(2*PI*Y);
 V:=Sqrt(-2*Ln(X))*Sin(2*PI*Y);
 Gauss:=U;
End;

Function GaussMs(M,S:Real):Real;Begin
 GaussMs:=Gauss+S+M;
End;

Function GaussSentence:Integer;Begin
 GaussSentence:=Round(GaussMs(2.460,5.080));
End;

Procedure GetWords(Count:Integer;LoremIpsum:Boolean);
Var
 I,NumWord,_Index,LenSentence:Integer;
 Capital:Boolean;
 LastWord:String;
Begin
 Capital:=True;
 LenSentence:=GaussSentence;
 I:=0;NumWord:=0;
 If(LoremIpsum)Then Begin
  I:=2;
  Write('Lorem ');
  Write('Ipsum ');
  NumWord:=2;
 End;
 While(I<Count)do Begin
  _Index:=Random(High(Words));
  If LastWord=StrPas(Words[_Index])Then _Index:=Random(High(Words));
  If(Capital)Then Begin
   Write(StrToCapital(StrPas(Words[_Index])));
   Capital:=False;
  End
   Else
  Write(StrPas(Words[_Index]));
  If I+1<Count Then Begin
   If NumWord>=LenSentence Then Begin
    LenSentence:=GaussSentence;
    Case Random(2) of
     0:Write(', ');
     1:Begin
      Write('. ');
      Capital:=True;
     End;
    End;
    NumWord:=0;
   End
    Else
   Begin
    Write(' ');
    Inc(NumWord);
    Capital:=False;
   End;
  End;
  LastWord:=StrPas(Words[_Index]);
  Inc(I);
 End;
 Write('.');
End;

Var
 Len,I:Integer;
 Err:Word;


BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('LOREM : Cette commande permet de gÇnÇrer du ',
                      'texte alÇatoirement (Lorem Ipsum).');
  WriteLn;
  WriteLn('Syntaxe : LOREM longueur');
  WriteLn;
  WriteLn(' longueur  Ce parametre permet d''indiquer le nombre de mots a gÇnÇrer');
 End
  Else
 If ParamCount>0Then Begin
  For I:=1 to ParamCount do Begin
   Val(ParamStr(I),Len,Err);
   If Err>0Then Begin
    WriteLn('Valeur invalide');
    Halt;
   End;
   GetWords(Len,I=1);
   If ParamCount>1 Then Begin
    WriteLn;
    WriteLn;
   End;
  End;
 End
  Else
 WriteLn('Paramätre requis');
END.