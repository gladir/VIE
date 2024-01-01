{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2024
  @website(https://www.gladir.com/vie)
  @abstract(Target: Turbo Pascal, Free Pascal)
}

Program FINDANAG;

Uses Strings,Crt;

Const MaxAnagram=1000;

Type
 AnagramArray=Array[0..MaxAnagram] of Word;
 AnagramStr=Array[0..MaxAnagram] of Char;

Var
 TargetFileName:String;
 TargetFile:Text;
 Target:AnagramStr;
 Size:Word;
 Specimen:AnagramArray;
 I:Word;
 AnagramCount:LongInt;

Procedure Working;
Const
 CurrentCursor:Byte = 0;
 CursorArray:Array[0..3] of Char='.þúù';
Begin
 CurrentCursor:=Succ(CurrentCursor) and 3;
 Write(CursorArray[CurrentCursor],#13);
End;

Procedure OutPutAnagram(Target:AnagramStr;Var Specimen:AnagramArray;Size:Word);
Var
 I:Word;
Begin
 If TargetFileName<>''Then Begin
  For I:=0 to(Size-1)do Write(TargetFile,Target[Specimen[I]]);
  WriteLn(TargetFile);
 End
  Else
 Begin
  For I:=0 to(Size-1)do Write(Target[Specimen[I]]);
  Writeln;
 End;
End;

Function IsAnagram(Var Specimen:AnagramArray;Size:Word):Boolean;
Var
 I1,I2:Word;
 Valid:Boolean;
Begin
 Valid:=True;
 I1:=0;
 While(I1<Pred(Size))and Valid do Begin
  I2:=I1+1;
  While(I2<Size)and Valid do Begin
   If Specimen[I1]=Specimen[I2]Then Valid:=False;
   Inc(I2);
  End;
  Inc(I1);
 End;
 IsAnagram:=Valid;
End;

Procedure FindAnagrams(Target:AnagramStr;Var Specimen:AnagramArray;Size:Word);
Var
 I:Word;
 Carry:Boolean;
Begin
 Repeat
  Working;
  If IsAnagram(Specimen,Size)Then Begin
   OutputAnagram(Target,Specimen,Size);
   Inc(AnagramCount);
  End;
  I:=0;
  Repeat
   Specimen[I]:=(Specimen[I]+1)mod Size;
   Carry:=Not Boolean(Specimen[I]);
   Inc(I);
  Until (Not Carry)or(I>=Size);
 Until Carry and(I>=Size);
End;

BEGIN
 {$IFDEF FPC}
  {$IFDEF WINDOWS}
   SetUseACP(False);
  {$ENDIF}
 {$ENDIF}
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('FINDANAG : Cette commande permet de rechercher les anagrammes ',
                      'du mot sp‚cifi‚.');
  WriteLn;
  WriteLn('Syntaxe : FINDANAG anagramme fichier');
  WriteLn;
  WriteLn(' anagramme  Ce paramŠtre permet d''indiquer le mot … rechercher les anagrammes.');
  WriteLn(' fichier    Ce paramŠtre permet d''indiquer le fichier recevant les r‚sultats');
 End
  Else
 Begin
  FillChar(Target,SizeOf(Target),0);
  For I:=1 to ParamCount do Begin
   If StrLen(Target)=0Then StrPCopy(Target,ParamStr(I)) Else
   If TargetFileName=''Then TargetFileName:=ParamStr(I)
    Else
   Begin
    WriteLn('Trop de paramŠtres !');
    Halt;
   End;
  End;
  ClrScr;
  If StrLen(Target)=0Then Begin
   Write('Entrez l''anagramme destinataire : ');
   Readln(Target);
   Writeln;
  End;
  If TargetFileName<>''Then Begin
   {$I-}Assign(TargetFile,TargetFileName);
   Rewrite(TargetFile);{$I+}
  End;
  AnagramCount:=0;
  Size:=Strlen(Target);
  For I:=0 to MaxAnagram do Specimen[I]:=0;
  For I:=0 to Size-1 do Specimen[I]:=Size-I-1;
  FindAnagrams(Target,Specimen,Size);
  WriteLn;
  Write(AnagramCount,' anagrammes trouv‚ avec la source ', Target);
  If TargetFileName<>''Then Begin
   WriteLn(' ‚crit dans le fichier ®',TargetFileName,'¯');
   Close(TargetFile);
  End;
  WriteLn;
 End;
END.