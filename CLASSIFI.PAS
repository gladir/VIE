{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2022
  @website(https://www.gladir.com/vie)
  @abstract(Target: Turbo Pascal, Free Pascal)
}

Program CLASSIFI;

Uses Strings;

Type
 Classification=Record
  Category:PChar;
  KeywordMax:Word;
  KeywordList:Pointer;
 End;

 ArrayPChar=Array[0..1000] of PChar;

Const
 EducationList:Array[0..9]of PChar=(
  'CEGEP','‚cole','enseignant','enseignante','maternelle',
  'pr‚scolaire','prof','professeur','scolaire','universit‚'
 );

 IAList:Array[0..24]of PChar=(
  'Agent conversationnel','Amazon Lex','Amazon  Polly',
  'Amazon Rekognition','Amazon SageMaker','ANN',
  'apprentissage automatique','apprentissage profond',
  'Bot Framework SDK','classification','deep learning',
  'IBM Watson Studio','ia','intelligence artificielle',
  'Intelligent Robot','machine learning','ML',
  'natural language processing','NLP',
  'Oracle Digital Assistant','RASA',
  'reconnaissance faciale','r‚seau neuronal',
  'spaCy','vision par ordinateur'
 );

 InformatiqueList:Array[0..7]of PChar=(
  'AI','computer','IA','IBM','intelligence artificielle',
  'Microsoft','ordinateur','Windows'
 );

 JusticeList:Array[0..4]of PChar=(
  'avocat','juge','jur‚','jury','tribunal'
 );

 PolitiqueList:Array[0..2]of PChar=(
  '‚tat','ministre','pr‚sident'
 );

 MedecineList:Array[0..2]of PChar=(
  'docteur','h“pital','m‚decin'
 );

 SportList:Array[0..3]of PChar=(
  'badminton',
  'hockey',
  'olympique',
  'prolongation'
 );

 TourismeList:Array[0..5]of PChar=(
  'Eiffel','parc','pyramide','voyage','vacance','vacances'
 );

 Classifications:Array[0..7]of Classification=(
  (Category:'Education';
   KeywordMax:High(EducationList);
   KeywordList:@EducationList),
  (Category:'Intelligence Artificielle';
   KeywordMax:High(IAList);
   KeywordList:@IAList),
  (Category:'Informatique';
   KeywordMax:High(InformatiqueList);
   KeywordList:@InformatiqueList),
  (Category:'Justice';
   KeywordMax:High(JusticeList);
   KeywordList:@JusticeList),
  (Category:'M‚decine';
   KeywordMax:High(MedecineList);
   KeywordList:@MedecineList),
  (Category:'Politique';
   KeywordMax:High(PolitiqueList);
   KeywordList:@PolitiqueList),
  (Category:'Sport';
   KeywordMax:High(SportList);
   KeywordList:@SportList),
  (Category:'Tourisme';
   KeywordMax:High(TourismeList);
   KeywordList:@TourismeList)
 );

Var
 I:Integer;
 BeginWord,J:Integer;
 FoundMultiWord:Boolean;
 SourceFile:Text;
 FileName,CurrLine,CurrWord:String;
 ClassificationCount:Array[0..High(Classifications)]of LongInt;

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
 I,J:Integer;
 P:^ArrayPChar;
Begin
 For I:=Low(Classifications) to High(Classifications) do Begin
  P:=Classifications[I].KeywordList;
  For J:=0 to Classifications[I].KeywordMax do Begin
   If StrToUpper(StrPas(P^[J]))=StrToUpper(CurrWord)Then Begin
    Inc(ClassificationCount[I]);
   End;
  End;
 End;
End;

Procedure ParseLineDetectClassification;
Var
 I,J,K:Integer;
 P:^ArrayPChar;
Begin
 CurrWord:='';
 BeginWord:=1;
 For I:=1 to Length(CurrLine)do Begin
  If(IsLetter(CurrLine[I]))Then CurrWord:=CurrWord+CurrLine[I]
   Else
  Begin
   FoundMultiWord:=False;
   For J:=Low(Classifications) to High(Classifications) do Begin
    P:=Classifications[J].KeywordList;
    For K:=0 to Classifications[J].KeywordMax do Begin
     If(StrLen(P^[K])>Length(CurrWord))and
      (StrToUpper(StrPas(P^[K]))=
      StrToUpper(Copy(CurrLine,BeginWord,StrLen(P^[K]))))Then Begin
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
  WriteLn('CLASSIFI : Cette commande permet de demander une ',
                      'classification d''un texte.');
  WriteLn;
  WriteLn('Syntaxe : CLASSIFI "message"');
  WriteLn('          CLASSIFI /FILE:fichier');
  WriteLn;
 End
  Else
 Begin
  For I:=0 to High(ClassificationCount)do Begin
   ClassificationCount[I]:=0;
  End;
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
    ParseLineDetectClassification;
   End;
   Close(SourceFile);
  End
   Else
  ParseLineDetectClassification;
  For I:=0 to High(ClassificationCount)do Begin
   If ClassificationCount[I]>0 Then WriteLn(StrPas(Classifications[I].Category));
  End;
 End;
END.