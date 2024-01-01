{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2024
  @website(https://www.gladir.com/vie)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program MAKEDATA;

Const
 HexNumber:Array[0..15]of Byte=(Ord('0'),Ord('1'),Ord('2'),Ord('3'),
                                Ord('4'),Ord('5'),Ord('6'),Ord('7'),
                                Ord('8'),Ord('9'),Ord('A'),Ord('B'),
                                Ord('C'),Ord('D'),Ord('E'),Ord('F'));
 Base64Alphabet:Array[0..63]of Byte=(
  Ord('A'),Ord('B'),Ord('C'),Ord('D'),Ord('E'),Ord('F'),Ord('G'),Ord('H'),
  Ord('I'),Ord('J'),Ord('K'),Ord('L'),Ord('M'),Ord('N'),Ord('O'),Ord('P'),
  Ord('Q'),Ord('R'),Ord('S'),Ord('T'),Ord('U'),Ord('V'),Ord('W'),Ord('X'),
  Ord('Y'),Ord('Z'),Ord('a'),Ord('b'),Ord('c'),Ord('d'),Ord('e'),Ord('f'),
  Ord('g'),Ord('h'),Ord('i'),Ord('j'),Ord('k'),Ord('l'),Ord('m'),Ord('n'),
  Ord('o'),Ord('p'),Ord('q'),Ord('r'),Ord('s'),Ord('t'),Ord('u'),Ord('v'),
  Ord('w'),Ord('x'),Ord('y'),Ord('z'),Ord('0'),Ord('1'),Ord('2'),Ord('3'),
  Ord('4'),Ord('5'),Ord('6'),Ord('7'),Ord('8'),Ord('9'),Ord('+'),Ord('/'));

Var
 DataFormat:(dfRandom,dfNULL,dfFULL,dfTEXT,dfNumber,dfHEX,dfbase64);
 DataFile:File;
 FileName:String;
 J,Size:LongInt;
 I:Integer;
 Err:Word;
 Data:Byte;
 ByteWrited:Word;

Function StrToUpper(S:String):String;
Var
 I:Byte;
Begin
 For I:=1 to Length(S)do Begin
  If S[I] in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
 End;
 StrToUpper:=S;
End;

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('MAKEDATE : Cette commande permet de g‚n‚rer un fichier de ',
                      'donn‚es al‚atoire selon la taille sp‚cifi‚.');
  WriteLn;
  WriteLn('Syntaxe : MAKEDATE fichier taille [/FORMAT:[RANDOM|NULL|FULL]]');
  WriteLn;
  WriteLn(' fichier    Ce paramŠtre permet d''indiquer le fichier recevant les r‚sultats');
  WriteLn(' taille     Ce paramŠtre permet d''indiquer la taille du fichier.');
  WriteLn(' /FORMAT:   Ce paramŠtre permet d''indiquer le format des donn‚es :');
  WriteLn('             BASE64   - Valeur al‚atoire de base64');
  WriteLn('             FULL     - Valeur toujours 255 (tous les bits fix‚ … 1)');
  WriteLn('             HEX      - Valeur al‚atoire de nombre hexad‚cimal');
  WriteLn('             NULL     - Valeur toujours 0');
  WriteLn('             NUMBER   - Valeur al‚atoire de nombre');
  WriteLn('             RANDOM   - Valeur al‚atoire');
  WriteLn('             TEXT     - Valeur al‚atoire de texte');
 End
  Else
 Begin
  Size:=-1;
  FileName:='';
  DataFormat:=dfRandom;
  For I:=1 to ParamCount do Begin
   If StrToUpper(ParamStr(I))='/FORMAT:BASE64'Then DataFormat:=dfbase64 Else
   If StrToUpper(ParamStr(I))='/FORMAT:FULL'Then DataFormat:=dfFULL Else
   If StrToUpper(ParamStr(I))='/FORMAT:HEX'Then DataFormat:=dfHEX Else
   If StrToUpper(ParamStr(I))='/FORMAT:NULL'Then DataFormat:=dfNULL Else
   If StrToUpper(ParamStr(I))='/FORMAT:NUMBER'Then DataFormat:=dfNumber Else
   If StrToUpper(ParamStr(I))='/FORMAT:RANDOM'Then DataFormat:=dfRandom Else
   If StrToUpper(ParamStr(I))='/FORMAT:TEXT'Then DataFormat:=dfTEXT Else
   If FileName=''Then FileName:=ParamStr(I)
    Else
   Begin
    Val(ParamStr(I),Size,Err);
    If Err>0 Then Begin
     WriteLn('Taille invalide !');
     Halt;
    End;
   End;
  End;
  If Size=-1 Then Size:=1048576;
  {$I-}Assign(DataFile,FileName);
  Rewrite(DataFile,1);{$I+}
  If IOResult<>0 Then Begin
   WriteLn('Impossible de cr‚er le fichier : ',FileName);
   Halt;
  End;
  For J:=1 to Size do Begin
   Case DataFormat of
    dfbase64:Data:=Base64Alphabet[Random(64)];
    dfFULL:Data:=255;
    dfHex:Data:=HexNumber[Random(16)];
    dfNULL:Data:=0;
    dfNumber:Data:=Ord('0')+Random(10);
    dfTEXT:Data:=Ord('A')+Random(26);
    Else Data:=Random(256);
   End;
   BlockWrite(DataFile,Data,1,ByteWrited);
   If ByteWrited<1 Then Begin
    WriteLn('Espace insuffisant, fichier ferm‚ plus t“t !');
    Break;
   End;
  End;
  Close(DataFile);
 End;
END.