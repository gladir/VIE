{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2022
  @website(https://www.gladir.com/vie)
  @abstract(Target: Turbo Pascal, Free Pascal)
}

Program SKILLS;

Uses Strings;

Type
 Classification=Record
  Category:PChar;
  KeywordMax:Word;
  KeywordList:Pointer;
 End;

 ArrayPChar=Array[0..1000] of PChar;

Const
 CloudList:Array[0..6]of PChar=(
  'Alibaba Cloud',
  'AWS',
  'Azure',
  'GCP',
  'Heroku',
  'IBM Cloud',
  'Oracle Cloud'
 );

 DataBaseList:Array[0..10]of PChar=(
  'DB2',
  'dBASE',
  'BigQuery',
  'MariaDB',
  'MySQL',
  'Oracle',
  'PL/SQL',
  'PostgreSQL',
  'SQL',
  'SQL Server',
  'TSQL'
 );

 IntegrationList:Array[0..6]of PChar=(
  'Boostrap',
  'CSS',
  'Flash',
  'HTML',
  'Smarty',
  'SASS',
  'SVG'
 );

 LanguageList:Array[0..5]of PChar=(
  'Allemand','Anglais','Espagnol','Fran‡ais','Italien','Portugais'
 );

 ProgrammingList:Array[0..11]of PChar=(
  'Assembler',
  'Assembleur',
  'BASIC',
  'C++',
  'C#',
  'COBOL',
  'Java',
  'Pascal',
  'Perl',
  'Python',
  'Ruby',
  'VB'
 );

 SysAdminList:Array[0..4]of PChar=(
  'AIX',
  'Linux',
  'PowerShell',
  'Tomcat',
  'UNIX'
 );

 Classifications:Array[0..5]of Classification=(
  (Category:'Base de donn‚es';
   KeywordMax:High(DatabaseList);
   KeywordList:@DatabaseList),
  (Category:'Infonuagiques';
   KeywordMax:High(CloudList);
   KeywordList:@CloudList),
  (Category:'Int‚gration';
   KeywordMax:High(IntegrationList);
   KeywordList:@IntegrationList),
  (Category:'Linguistique';
   KeywordMax:High(LanguageList);
   KeywordList:@LanguageList),
  (Category:'Programmation';
   KeywordMax:High(ProgrammingList);
   KeywordList:@ProgrammingList),
  (Category:'Administrateur systŠme';
   KeywordMax:High(SysAdminList);
   KeywordList:@SysAdminList)
 );

Var
 I:Integer;
 BeginWord,J:Integer;
 FoundMultiWord:Boolean;
 SourceFile:Text;
 FileName,CurrLine,CurrWord:String;
 ClassificationCount:Array[0..High(Classifications)]of LongInt;
 ClassificationSkill:Array[0..High(Classifications)]of String;

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
    If ClassificationSkill[I]=''Then ClassificationSkill[I]:=CurrWord
    Else ClassificationSkill[I]:=ClassificationSkill[I]+', '+CurrWord;
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
  WriteLn('SKILLS : Cette commande permet de rechercher les ',
                      'competence contenu dans un CV de format texte.');
  WriteLn;
  WriteLn('Syntaxe : SKILLS "message"');
  WriteLn('          SKILLS /FILE:fichier');
  WriteLn;
 End
  Else
 Begin
  For I:=0 to High(ClassificationCount)do Begin
   ClassificationCount[I]:=0;
   ClassificationSkill[I]:='';
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
   If ClassificationCount[I]>0 Then Begin
    WriteLn(StrPas(Classifications[I].Category),' : ',ClassificationSkill[I]);
   End;
  End;
 End;
END.
