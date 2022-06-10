{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2022
  @website(https://www.gladir.com/vie)
  @abstract(Target: Turbo Pascal, Free Pascal)
}

Program DetecSen;

Uses Strings;

Const
 PositiveList:Array[0..17]of PChar=(
  'adore','beau','beaucoup','bien','bienvenue','bien merci','blanc',
  'bon','bonne','bonne journ‚e','excellente journ‚e',
  'heureux','mieux','moins pire',
  'tellement mieux','tres','trŠs','trop'
 );

 NegativeList:Array[0..14]of PChar=(
  'balles de frais',
  'honte',
  'infecte',
  'je comprends mˆme pas',
  'je suis r‚volt‚',
  'mal','mauvais',
  'maladroit','malpropre',
  'merde','moins','noir','pas',
  'sombre',
  'vrai honte'
 );

 NeutralList:Array[0..2]of PChar=(
  'je pr‚fŠre ne pas me prononcer','moyen','passable'
 );

Var
 PositiveWord,NegativeWord,NeutralWord:LongInt;
 BeginWord,I,J:Integer;
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

Procedure CompileWord;
Var
 I:Integer;
Begin
 For I:=Low(PositiveList) to High(PositiveList) do Begin
  If StrToUpper(StrPas(PositiveList[I]))=StrToUpper(CurrWord)Then Begin
   Inc(PositiveWord);
   Exit;
  End;
 End;
 For I:=Low(NegativeList) to High(NegativeList) do Begin
  If StrToUpper(StrPas(NegativeList[I]))=StrToUpper(CurrWord)Then Begin
   Inc(NegativeWord);
   Exit;
  End;
 End;
 For I:=Low(NeutralList) to High(NeutralList) do Begin
  If StrToUpper(StrPas(NeutralList[I]))=StrToUpper(CurrWord)Then Begin
   Inc(NeutralWord);
   Exit;
  End;
 End;
End;

Procedure ParseLineDetectSentiment;
Var
 J:Integer;
Begin
 CurrWord:='';
 BeginWord:=1;
 For I:=1 to Length(CurrLine)do Begin
  If(IsLetter(CurrLine[I]))Then CurrWord:=CurrWord+CurrLine[I]
   Else
  Begin
   FoundMultiWord:=False;
   For J:=Low(PositiveList) to High(PositiveList) do Begin
    If(StrLen(PositiveList[J])>Length(CurrWord))and
      (StrToUpper(StrPas(PositiveList[J]))=
      StrToUpper(Copy(CurrLine,BeginWord,StrLen(PositiveList[J]))))Then Begin
     FoundMultiWord:=True;
     Break;
    End;
   End;
   If Not(FoundMultiWord)Then Begin
    For J:=Low(NegativeList) to High(NegativeList) do Begin
     If(StrLen(NegativeList[J])>Length(CurrWord))and
       (StrToUpper(StrPas(NegativeList[J]))=
       StrToUpper(Copy(CurrLine,BeginWord,StrLen(NegativeList[J]))))Then Begin
      FoundMultiWord:=True;
      Break;
     End;
    End;
   End;
   If Not(FoundMultiWord)Then Begin
    For J:=Low(NeutralList) to High(NeutralList) do Begin
     If(StrLen(NeutralList[J])>Length(CurrWord))and
       (StrToUpper(StrPas(NeutralList[J]))=
       StrToUpper(Copy(CurrLine,BeginWord,StrLen(NeutralList[J]))))Then Begin
      FoundMultiWord:=True;
      Break;
     End;
    End;
   End;
   If(FoundMultiWord)Then Begin
    CurrWord:=CurrWord+CurrLine[I]
   End
    Else
   Begin
    CompileWord;
    CurrWord:='';
    BeginWord:=I+1;
   End;
  End;
 End;
 CompileWord;
End;

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('DETECSEN : Cette commande permet de detecter les sentiments ',
                      'dans un texte.');
  WriteLn;
  WriteLn('Syntaxe : DETECSEN "message"');
  WriteLn('          DETECSEN /FILE:fichier');
  WriteLn;
 End
  Else
 Begin
  PositiveWord:=0;
  NegativeWord:=0;
  NeutralWord:=0;
  FileName:='';
  CurrLine:='';
  For I:=1 to ParamCount do Begin
   If StrToUpper(Copy(ParamStr(I),1,6))='/FILE:'Then Begin
    FileName:=Copy(ParamStr(I),7,255);
   End
    Else
   Begin
    If CurrLine=''Then CurrLine:=ParamStr(I)
                  Else CurrLine:=CurrLine+' '+ParamStr(I);
   End;
  End;
  If FileName<>''Then Begin
    Assign(SourceFile,FileName);
    Reset(SourceFile);
    While Not EOF(SourceFile)do Begin
     ReadLn(SourceFile,CurrLine);
     ParseLineDetectSentiment;
    End;
    Close(SourceFile);
   End
    Else
   ParseLineDetectSentiment;
   WriteLn('Pointage positif : ',PositiveWord);
   WriteLn('Pointage negatif : ',NegativeWord);
   WriteLn('Pointage neutre : ',NeutralWord);
 End;
END.