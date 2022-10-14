{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2022
  @website(https://www.gladir.com/vie)
  @abstract(Target: Turbo Pascal, Free Pascal)
}

Program CHATBOT;

Uses DOS;

Var
 SourceFile:Text;
 I:Integer;
 S:String;
 FileName,ChatbotName:String;

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

Procedure Parser(S:String);
Var
 Hour,Min,Sec,Sec100:Word;
 Question:(QNone,_Quand,_Quel,_Combien,_Ou);
 Propriete:(PNone,_Heure,_Nom);
 Negation:Integer;
 I:Byte;
 CurrWord:String;
Begin
 CurrWord:='';
 Question:=QNone;
 Propriete:=PNone;
 Negation:=0;
 S:=S+' ';
 For I:=1 to Length(S)do Begin
  If(IsLetter(S[I]))Then CurrWord:=CurrWord+S[I]
   Else
  Begin
    { Cherche une question }
   If(StrToUpper(CurrWord)='COMBIEN')Then Question:=_Combien Else
   If(StrToUpper(CurrWord)='QUEL')or(StrToUpper(CurrWord)='QUELLE')Then Question:=_Quel Else
   If(StrToUpper(CurrWord)='QUAND')Then Question:=_Quand Else

    { Cherche une propri‚t‚ }
   If(StrToUpper(CurrWord)='HEURE')Then Propriete:=_Heure Else
   If(StrToUpper(CurrWord)='NOM')Then Propriete:=_Nom Else

    { Cherche une n‚gation }
   If(StrToUpper(CurrWord)='NON')Then Dec(Negation)Else
   If(StrToUpper(CurrWord)='PAS')Then Dec(Negation);
   CurrWord:='';
  End;
 End;
 If(Question<>QNone)Then Begin
  If(Question=_Quel)and(Propriete=_Heure)Then Begin
   GetTime(Hour,Min,Sec,Sec100);
   WriteLn('Il est ',Hour,':',Min:2)
  End
   Else
  If(Question=_Quel)and(Propriete=_Nom)Then Begin
   WriteLn('Je m''appel ',ChatbotName)
  End
   Else
  WriteLn('Je ne comprends pas votre question.');
 End
  Else
 WriteLn('Je ne comprends pas votre question.');
 WriteLn;
End;

Function IsMessageExit(S:String):Boolean;Begin
 IsMessageExit:=(StrToUpper(S)='BYE')or(StrToUpper(S)='EXIT')or
                (StrToUpper(S)='QUIT')or(StrToUpper(S)='QUITTER');
End;

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')Then Begin
  WriteLn('CHATBOT : Cette commande permet de lancer le Chatbot.');
  WriteLn;
  WriteLn('Syntaxe : CHATBOT [/NAME:nom] [/FILE:fichier]');
  WriteLn;
  WriteLn('/NAME:nom      Indique le nom du Chatbot.');
  WriteLn('/FILE:fichier  Indique le fichier contenant les questions.');
 End
  Else
 Begin
  ChatbotName:='Chatbot';
  FileName:='';
  For I:=1 to ParamCount do Begin
   If StrToUpper(Copy(ParamStr(I),1,6))='/NAME:'Then Begin
    ChatbotName:=Copy(ParamStr(I),7,255);
   End
    Else
   If StrToUpper(Copy(ParamStr(I),1,6))='/FILE:'Then Begin
    FileName:=Copy(ParamStr(I),7,255);
   End
    Else
   Begin
    WriteLn('ParamŠtre invalide !');
    Halt;
   End;
  End;
  If FileName<>''Then Begin
   {$I-}Assign(SourceFile,FileName);
   Reset(SourceFile);{$I+}
   If IoResult=0 Then Begin
    While Not EOF(SourceFile)do Begin
     ReadLn(SourceFile,S);
     Parser(S);
     WriteLn;
    End;
    Close(SourceFile);
   End
    Else
   WriteLn('Fichier introuvable !');
  End
   Else
  Begin
   WriteLn('Bonjour, comment puis-je vous aidez ?');
   Repeat
    ReadLn(S);
    If Not IsMessageExit(S)Then Parser(S);
   Until IsMessageExit(S);
  End;
 End;
END.