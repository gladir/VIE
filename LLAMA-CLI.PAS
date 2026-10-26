{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/vie)
  @abstract(Target: Free Pascal 3.x)

  LLAMA-CLI : clone de la commande llama-cli de llama.cpp.

  Contraintes respectees :
   - un seul fichier source, aucun fichier d'inclusion;
   - la seule unite utilisee est DOS (le reste vient de l'unite System);
   - les appels reseau (-hf, -mu) n'existent que sous Windows (WinInet),
     ils sont absents sous DOS et Linux;
   - aucun support GPU : les options -ngl, -dev, etc. sont acceptees
     mais ignorees;
   - le calcul est fait sur un seul fil d'execution (les options -t et -tb
     sont acceptees mais ne changent pas le comportement).

  Un programme Turbo Pascal 16 bits ne peut evidemment pas charger un
  modele GGUF de plusieurs centaines de Mo : il faut un compilateur 32 ou
  64 bits (Free Pascal) pour compiler ce programme.

  Compilation : fpc -O3 LLAMA-CLI.PAS
}

Program LLAMA_CLI;

{$IFDEF FPC}
 {$MODE OBJFPC}
 {$H+}
 {$INLINE ON}
 {$IFDEF WIN32}
  {$SETPEFLAGS $20}
 {$ENDIF}
 {$R-}
 {$Q-}
 {$IOCHECKS OFF}
 {$MACRO ON}
 {$POINTERMATH ON}
 {$NOTES OFF}
 {$HINTS OFF}
 {$WARNINGS OFF}
{$ENDIF}

Uses DOS;

Const
 VersionStr   = '1.0 (clone Pascal de llama.cpp llama-cli)';
 BuildNumber  = 1;
 NegInf       = -1.0e30;     { remplace -INFINITY }
 TokenNull    = -1;

 { Types GGUF }
 GT_UINT8=0; GT_INT8=1; GT_UINT16=2; GT_INT16=3; GT_UINT32=4; GT_INT32=5;
 GT_FLOAT32=6; GT_BOOL=7; GT_STRING=8; GT_ARRAY=9; GT_UINT64=10;
 GT_INT64=11; GT_FLOAT64=12;

 { Types de tenseurs GGML }
 TY_F32=0; TY_F16=1; TY_Q4_0=2; TY_Q4_1=3; TY_Q5_0=6; TY_Q5_1=7;
 TY_Q8_0=8; TY_Q8_1=9; TY_Q2_K=10; TY_Q3_K=11; TY_Q4_K=12; TY_Q5_K=13;
 TY_Q6_K=14; TY_Q8_K=15; TY_IQ4_NL=20; TY_IQ4_XS=23; TY_I8=24; TY_I16=25;
 TY_I32=26; TY_I64=27; TY_F64=28; TY_BF16=30;

 { Attributs de jetons }
 TA_UNDEFINED=0; TA_UNKNOWN=1; TA_UNUSED=2; TA_NORMAL=4; TA_CONTROL=8;
 TA_USER_DEFINED=16; TA_BYTE=32;

Type
 PSingleArr = ^TSingleArr;
 TSingleArr = Array[0..0]of Single;
 PIntArr = ^TIntArr;
 TIntArr = Array[0..0]of LongInt;
 PWordArr = ^TWordArr;
 TWordArr = Array[0..0]of Word;
 TStrArray = Array of AnsiString;
 TIntArray = Array of LongInt;
 TSingleArray = Array of Single;
 TByteArray = Array of Byte;
 TBoolArray = Array of Boolean;
 TQuad = Int64;

Var
 F16Tab:Array[0..65535]of Single;
 StartTick:Int64;

{ ------------------------------------------------------------------ }
{ Utilitaires de chaines                                              }
{ ------------------------------------------------------------------ }

Function IStr(N:Int64):AnsiString;
Var
 S:AnsiString;
Begin
 Str(N,S);
 IStr:=S;
End;

Function FStr(X:Double;Dec:Integer):AnsiString;
Var
 S:AnsiString;
Begin
 Str(X:0:Dec,S);
 FStr:=S;
End;

Function FStrW(X:Double;W,Dec:Integer):AnsiString;
Var
 S:AnsiString;
Begin
 Str(X:W:Dec,S);
 FStrW:=S;
End;

Function PadLeft(S:AnsiString;W:Integer):AnsiString;
Begin
 While Length(S)<W do S:=' '+S;
 PadLeft:=S;
End;

Function PadRight(S:AnsiString;W:Integer):AnsiString;
Begin
 While Length(S)<W do S:=S+' ';
 PadRight:=S;
End;

Function LoStr(S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 For I:=1 to Length(S)do If S[I]in['A'..'Z']Then S[I]:=Chr(Ord(S[I])+32);
 LoStr:=S;
End;

Function UpStr(S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 For I:=1 to Length(S)do If S[I]in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
 UpStr:=S;
End;

Function StartsWith(Const S,Prefix:AnsiString):Boolean;
Begin
 StartsWith:=(Length(S)>=Length(Prefix))and(Copy(S,1,Length(Prefix))=Prefix);
End;

Function EndsWith(Const S,Suffix:AnsiString):Boolean;
Begin
 EndsWith:=(Length(S)>=Length(Suffix))and
           (Copy(S,Length(S)-Length(Suffix)+1,Length(Suffix))=Suffix);
End;

Function Contains(Const S,Sub:AnsiString):Boolean;
Begin
 Contains:=(Sub<>'')and(Pos(Sub,S)>0);
End;

Function PosFrom(Const Sub,S:AnsiString;From:LongInt):LongInt;
Var
 I,L,M:LongInt;
 Ch:Char;
Begin
 PosFrom:=0;
 L:=Length(S);M:=Length(Sub);
 If M=0 Then Exit;
 If From<1 Then From:=1;
 Ch:=Sub[1];
 I:=From;
 While I<=L-M+1 do Begin
  If S[I]=Ch Then Begin
   If(M=1)or(CompareByte(S[I],Sub[1],M)=0)Then Begin
    PosFrom:=I;Exit;
   End;
  End;
  Inc(I);
 End;
End;

Function ReplaceAll(Const S,FromS,ToS:AnsiString):AnsiString;
Var
 R:AnsiString;
 P,Q:LongInt;
Begin
 If FromS='' Then Begin ReplaceAll:=S;Exit;End;
 R:='';
 P:=1;
 While True do Begin
  Q:=PosFrom(FromS,S,P);
  If Q=0 Then Begin
   R:=R+Copy(S,P,Length(S)-P+1);
   Break;
  End;
  R:=R+Copy(S,P,Q-P)+ToS;
  P:=Q+Length(FromS);
 End;
 ReplaceAll:=R;
End;

Function IsSpaceCh(C:Char):Boolean;
Begin
 IsSpaceCh:=C in[' ',#9,#10,#11,#12,#13];
End;

Function TrimS(Const S:AnsiString):AnsiString;
Var
 A,B:LongInt;
Begin
 A:=1;B:=Length(S);
 While(A<=B)and IsSpaceCh(S[A])do Inc(A);
 While(B>=A)and IsSpaceCh(S[B])do Dec(B);
 TrimS:=Copy(S,A,B-A+1);
End;

Function RTrimS(Const S:AnsiString):AnsiString;
Var
 B:LongInt;
Begin
 B:=Length(S);
 While(B>=1)and IsSpaceCh(S[B])do Dec(B);
 RTrimS:=Copy(S,1,B);
End;

Function LTrimS(Const S:AnsiString):AnsiString;
Var
 A:LongInt;
Begin
 A:=1;
 While(A<=Length(S))and IsSpaceCh(S[A])do Inc(A);
 LTrimS:=Copy(S,A,Length(S)-A+1);
End;

Procedure AddStr(Var A:TStrArray;Const S:AnsiString);
Var
 N:LongInt;
Begin
 N:=Length(A);
 SetLength(A,N+1);
 A[N]:=S;
End;

Procedure AddInt(Var A:TIntArray;V:LongInt);
Var
 N:LongInt;
Begin
 N:=Length(A);
 SetLength(A,N+1);
 A[N]:=V;
End;

Function SplitStr(Const S:AnsiString;Sep:Char):TStrArray;
Var
 R:TStrArray;
 P,Q:LongInt;
Begin
 SetLength(R,0);
 P:=1;
 While True do Begin
  Q:=P;
  While(Q<=Length(S))and(S[Q]<>Sep)do Inc(Q);
  AddStr(R,Copy(S,P,Q-P));
  If Q>Length(S)Then Break;
  P:=Q+1;
 End;
 SplitStr:=R;
End;

Function ParseInt(Const S:AnsiString;Var V:Int64):Boolean;
Var
 Code:LongInt;
 T:AnsiString;
Begin
 T:=TrimS(S);
 If(T<>'')and(T[1]='+')Then Delete(T,1,1);
 If T='' Then Begin ParseInt:=False;Exit;End;
 Val(T,V,Code);
 ParseInt:=Code=0;
End;

Function ParseFloat(Const S:AnsiString;Var V:Double):Boolean;
Var
 Code:LongInt;
 T:AnsiString;
 Neg:Boolean;
Begin
 T:=TrimS(S);
 Neg:=False;
 If(T<>'')and(T[1]='+')Then Delete(T,1,1);
 If(T<>'')and(T[1]='-')Then Begin Neg:=True;Delete(T,1,1);End;
 If T='' Then Begin ParseFloat:=False;Exit;End;
 If T[1]='.' Then T:='0'+T;
 If LoStr(T)='inf' Then Begin V:=3.0e38;If Neg Then V:=-V;ParseFloat:=True;Exit;End;
 If LoStr(T)='infinity' Then Begin V:=3.0e38;If Neg Then V:=-V;ParseFloat:=True;Exit;End;
 Val(T,V,Code);
 If Neg Then V:=-V;
 ParseFloat:=Code=0;
End;

Function StrToIntDef(Const S:AnsiString;Def:Int64):Int64;
Var
 V:Int64;
Begin
 If ParseInt(S,V)Then StrToIntDef:=V Else StrToIntDef:=Def;
End;

Function StrToFloatDef(Const S:AnsiString;Def:Double):Double;
Var
 V:Double;
Begin
 If ParseFloat(S,V)Then StrToFloatDef:=V Else StrToFloatDef:=Def;
End;

Function HexStr2(B:Byte):AnsiString;
Const
 Hx:AnsiString='0123456789ABCDEF';
Begin
 HexStr2:=Hx[(B shr 4)+1]+Hx[(B and 15)+1];
End;

Function HexVal(C:Char):LongInt;
Begin
 Case C of
  '0'..'9':HexVal:=Ord(C)-48;
  'a'..'f':HexVal:=Ord(C)-87;
  'A'..'F':HexVal:=Ord(C)-55;
  Else HexVal:=-1;
 End;
End;

{ Encode un point de code Unicode en UTF-8 }
Function CpToUtf8(Cp:LongWord):AnsiString;
Begin
 If Cp<$80 Then CpToUtf8:=Chr(Cp)
 Else If Cp<$800 Then CpToUtf8:=Chr($C0 or(Cp shr 6))+Chr($80 or(Cp and $3F))
 Else If Cp<$10000 Then CpToUtf8:=Chr($E0 or(Cp shr 12))+Chr($80 or((Cp shr 6)and $3F))+
                                   Chr($80 or(Cp and $3F))
 Else CpToUtf8:=Chr($F0 or(Cp shr 18))+Chr($80 or((Cp shr 12)and $3F))+
                Chr($80 or((Cp shr 6)and $3F))+Chr($80 or(Cp and $3F));
End;

Function Utf8Len(C:Byte):LongInt;
Begin
 If C<$80 Then Utf8Len:=1
 Else If C<$C0 Then Utf8Len:=1
 Else If C<$E0 Then Utf8Len:=2
 Else If C<$F0 Then Utf8Len:=3
 Else Utf8Len:=4;
End;

{ Decode la chaine UTF-8 en points de code }
Procedure Utf8ToCps(Const S:AnsiString;Var Cps:TIntArray;Var Offs:TIntArray);
Var
 I,N,L,K:LongInt;
 C:LongWord;
 B:Byte;
Begin
 SetLength(Cps,Length(S));
 SetLength(Offs,Length(S)+1);
 N:=0;I:=1;
 While I<=Length(S)do Begin
  B:=Ord(S[I]);
  L:=Utf8Len(B);
  If I+L-1>Length(S)Then L:=1;
  If L=1 Then C:=B
  Else Begin
   Case L of
    2:C:=B and $1F;
    3:C:=B and $0F;
    Else C:=B and $07;
   End;
   For K:=1 to L-1 do C:=(C shl 6)or(Ord(S[I+K])and $3F);
  End;
  Cps[N]:=LongInt(C);
  Offs[N]:=I-1;
  Inc(N);
  Inc(I,L);
 End;
 Offs[N]:=Length(S);
 SetLength(Cps,N);
 SetLength(Offs,N+1);
End;

{ ------------------------------------------------------------------ }
{ Temps et hasard                                                     }
{ ------------------------------------------------------------------ }

Var
 LastHs:Int64;
 DayOfs:Int64;

{$IFDEF WINDOWS}
Function QueryPerformanceCounter(Var C:Int64):LongInt;stdcall;external 'kernel32.dll' name 'QueryPerformanceCounter';
Function QueryPerformanceFrequency(Var F:Int64):LongInt;stdcall;external 'kernel32.dll' name 'QueryPerformanceFrequency';
{$ELSE}
 {$IFDEF UNIX}
Type
 TTimeSpec=Record
  Sec:PtrInt;
  NSec:PtrInt;
 End;
Function clock_gettime(Id:LongInt;Var T:TTimeSpec):LongInt;cdecl;external 'c' name 'clock_gettime';
 {$ENDIF}
{$ENDIF}

{ temps ecoule en millisecondes (resolution fine quand le systeme le permet) }
Function NowMsF:Double;
{$IFDEF WINDOWS}
Var
 C,F:Int64;
Begin
 QueryPerformanceFrequency(F);
 QueryPerformanceCounter(C);
 If F<=0 Then NowMsF:=0 Else NowMsF:=C*1000.0/F;
End;
{$ELSE}
 {$IFDEF UNIX}
Var
 T:TTimeSpec;
Begin
 clock_gettime(1,T);
 NowMsF:=T.Sec*1000.0+T.NSec/1000000.0;
End;
 {$ELSE}
Var
 H,M,S,S100:Word;
 T:Int64;
Begin
 GetTime(H,M,S,S100);
 T:=((Int64(H)*60+M)*60+S)*100+S100;
 If T<LastHs-1000 Then Inc(DayOfs,8640000);
 LastHs:=T;
 NowMsF:=(T+DayOfs)*10.0;
End;
 {$ENDIF}
{$ENDIF}

Function NowMs:Int64;
Begin
 NowMs:=Trunc(NowMsF);
End;

Type
 TMT=Record
  S:Array[0..623]of LongWord;
  I:LongInt;
 End;

Procedure MTSeed(Var M:TMT;Seed:LongWord);
Var
 I:LongInt;
Begin
 M.S[0]:=Seed;
 For I:=1 to 623 do
  M.S[I]:=LongWord(Int64(1812433253)*(M.S[I-1]xor(M.S[I-1]shr 30))+I);
 M.I:=624;
End;

Procedure MTTwist(Var M:TMT);
Var
 I:LongInt;
 Y:LongWord;
Begin
 For I:=0 to 623 do Begin
  Y:=(M.S[I]and $80000000)or(M.S[(I+1)mod 624]and $7FFFFFFF);
  M.S[I]:=M.S[(I+397)mod 624]xor(Y shr 1);
  If(Y and 1)<>0 Then M.S[I]:=M.S[I]xor $9908B0DF;
 End;
 M.I:=0;
End;

Function MTNext(Var M:TMT):LongWord;
Var
 Y:LongWord;
Begin
 If M.I>=624 Then MTTwist(M);
 Y:=M.S[M.I];Inc(M.I);
 Y:=Y xor(Y shr 11);
 Y:=Y xor((Y shl 7)and $9D2C5680);
 Y:=Y xor((Y shl 15)and $EFC60000);
 Y:=Y xor(Y shr 18);
 MTNext:=Y;
End;

{ equivalent de std::uniform_real_distribution<double>(0,1) de libstdc++ }
Function MTUniform(Var M:TMT):Double;
Var
 A,B:Double;
 R:Double;
Begin
 A:=MTNext(M);
 B:=MTNext(M);
 R:=(A+B*4294967296.0)/18446744073709551616.0;
 If R>=1.0 Then R:=1.0-1.0e-16;
 MTUniform:=R;
End;

{ equivalent de std::uniform_real_distribution<float>(0,1) }
Function MTUniformF(Var M:TMT):Single;
Var
 A:Double;
 R:Single;
Begin
 A:=MTNext(M);
 R:=A/4294967296.0;
 If R>=1.0 Then R:=0.99999994;
 MTUniformF:=R;
End;

Function MakeSeed:LongWord;
Var
 H,M,S,S100,Y,Mo,D,Dw:Word;
Begin
 GetTime(H,M,S,S100);
 GetDate(Y,Mo,D,Dw);
 MakeSeed:=LongWord(((Int64(H)*60+M)*60+S)*100+S100)xor(LongWord(D)*2654435761)xor
           (LongWord(Mo)*40503)xor(LongWord(Y)*65599);
End;

{ ------------------------------------------------------------------ }
{ Fonctions mathematiques                                             }
{ ------------------------------------------------------------------ }

Function FPow(X,Y:Double):Double;
Begin
 If Y=0 Then FPow:=1.0
 Else If X=0 Then FPow:=0.0
 Else If X>0 Then FPow:=Exp(Y*Ln(X))
 Else Begin
  { base negative : valide seulement pour exposant entier }
  If Frac(Y)=0 Then Begin
   If Odd(Trunc(Y))Then FPow:=-Exp(Y*Ln(-X))Else FPow:=Exp(Y*Ln(-X));
  End
   Else FPow:=0.0;
 End;
End;

Function FTanh(X:Double):Double;
Var
 E:Double;
Begin
 If X>20 Then FTanh:=1.0
 Else If X<-20 Then FTanh:=-1.0
 Else Begin
  E:=Exp(2.0*X);
  FTanh:=(E-1.0)/(E+1.0);
 End;
End;

Function FLog2(X:Double):Double;
Begin
 FLog2:=Ln(X)/0.693147180559945309;
End;

Function FMin(A,B:Double):Double;Begin If A<B Then FMin:=A Else FMin:=B;End;
Function FMax(A,B:Double):Double;Begin If A>B Then FMax:=A Else FMax:=B;End;
Function IMin(A,B:Int64):Int64;Begin If A<B Then IMin:=A Else IMin:=B;End;
Function IMax(A,B:Int64):Int64;Begin If A>B Then IMax:=A Else IMax:=B;End;

{ ------------------------------------------------------------------ }
{ Demi-precision                                                      }
{ ------------------------------------------------------------------ }

Function HalfToFloatSlow(H:Word):Single;
Var
 Sg,Ex,Mn:LongWord;
 Bits:LongWord;
 R:Single;
Begin
 Sg:=(H shr 15)and 1;
 Ex:=(H shr 10)and $1F;
 Mn:=H and $3FF;
 If Ex=0 Then Begin
  If Mn=0 Then Bits:=Sg shl 31
  Else Begin
   Ex:=1;
   While(Mn and $400)=0 do Begin
    Mn:=Mn shl 1;
    Dec(Ex);
   End;
   Mn:=Mn and $3FF;
   Bits:=(Sg shl 31)or((Ex+112)shl 23)or(Mn shl 13);
  End;
 End
  Else If Ex=31 Then Bits:=(Sg shl 31)or($FF shl 23)or(Mn shl 13)
  Else Bits:=(Sg shl 31)or((Ex+112)shl 23)or(Mn shl 13);
 PLongWord(@R)^:=Bits;
 HalfToFloatSlow:=R;
End;

Procedure InitHalfTable;
Var
 I:LongInt;
Begin
 For I:=0 to 65535 do F16Tab[I]:=HalfToFloatSlow(I);
End;

Function BF16ToFloat(H:Word):Single;
Var
 R:Single;
Begin
 PLongWord(@R)^:=LongWord(H)shl 16;
 BF16ToFloat:=R;
End;

Function FloatToHalf(F:Single):Word;
Var
 B:LongWord;
 Sg,Ex,Mn:LongInt;
Begin
 B:=PLongWord(@F)^;
 Sg:=(B shr 16)and $8000;
 Ex:=LongInt((B shr 23)and $FF)-127+15;
 Mn:=B and $7FFFFF;
 If((B shr 23)and $FF)=$FF Then Begin
  If Mn<>0 Then FloatToHalf:=Word(Sg or $7E00)Else FloatToHalf:=Word(Sg or $7C00);
  Exit;
 End;
 If Ex>=31 Then FloatToHalf:=Word(Sg or $7C00)
 Else If Ex<=0 Then Begin
  If Ex<-10 Then FloatToHalf:=Word(Sg)
  Else Begin
   Mn:=(Mn or $800000)shr(1-Ex);
   If(Mn and $1000)<>0 Then Mn:=Mn+$2000;
   FloatToHalf:=Word(Sg or(Mn shr 13));
  End;
 End
  Else Begin
   If(Mn and $1000)<>0 Then Begin
    Mn:=Mn+$2000;
    If(Mn and $800000)<>0 Then Begin Mn:=0;Inc(Ex);End;
   End;
   If Ex>=31 Then FloatToHalf:=Word(Sg or $7C00)
              Else FloatToHalf:=Word(Sg or(Ex shl 10)or(Mn shr 13));
  End;
End;

{ ------------------------------------------------------------------ }
{ Journalisation et sorties                                           }
{ ------------------------------------------------------------------ }

Var
 LogLevel:LongInt;        { 0 = rien, 1 = erreurs, 2 = avertissements, 3 = infos, 4+ = debug }
 LogDisabled:Boolean;
 LogFileOn:Boolean;
 LogFile:Text;
 UseColor:Boolean;
 SimpleIO:Boolean;

Procedure LogOut(Level:LongInt;Const S:AnsiString);
Begin
 If LogDisabled Then Exit;
 If Level>LogLevel Then Exit;
 Write(StdErr,S);
 Flush(StdErr);
 If LogFileOn Then Begin Write(LogFile,S);Flush(LogFile);End;
End;

Procedure LogErr(Const S:AnsiString);Begin LogOut(1,S);End;
Procedure LogWrn(Const S:AnsiString);Begin LogOut(2,S);End;
Procedure LogInf(Const S:AnsiString);Begin LogOut(3,S);End;
Procedure LogDbg(Const S:AnsiString);Begin LogOut(5,S);End;

Procedure Fatal(Const S:AnsiString);
Begin
 Write(StdErr,'erreur : ',S,#10);
 Flush(StdErr);
 Halt(1);
End;

Procedure OutS(Const S:AnsiString);
Begin
 Write(S);
End;

Procedure OutFlush;
Begin
 Flush(Output);
End;

{ ------------------------------------------------------------------ }
{ Fichiers                                                            }
{ ------------------------------------------------------------------ }

Function FileExistsP(Const Name:AnsiString):Boolean;
Var
 SR:SearchRec;
Begin
 FindFirst(Name,AnyFile,SR);
 FileExistsP:=(DosError=0)and((SR.Attr and Directory)=0);
 FindClose(SR);
End;

Function FileSizeP(Const Name:AnsiString):Int64;
Var
 SR:SearchRec;
Begin
 FindFirst(Name,AnyFile,SR);
 If DosError=0 Then FileSizeP:=SR.Size Else FileSizeP:=-1;
 FindClose(SR);
End;

Function ReadWholeFile(Const Name:AnsiString;Var Content:AnsiString):Boolean;
Var
 F:File;
 Sz:Int64;
 Got:LongInt;
 Done:Int64;
 Chunk:LongInt;
Begin
 ReadWholeFile:=False;
 Content:='';
 Assign(F,Name);
 Reset(F,1);
 If IOResult<>0 Then Exit;
 Sz:=FileSize(F);
 SetLength(Content,Sz);
 Done:=0;
 While Done<Sz do Begin
  Chunk:=1048576;
  If Sz-Done<Chunk Then Chunk:=Sz-Done;
  BlockRead(F,Content[Done+1],Chunk,Got);
  If Got<=0 Then Break;
  Inc(Done,Got);
 End;
 Close(F);
 If IOResult<>0 Then;
 ReadWholeFile:=Done=Sz;
End;

Function WriteWholeFile(Const Name,Content:AnsiString):Boolean;
Var
 F:File;
Begin
 WriteWholeFile:=False;
 Assign(F,Name);
 Rewrite(F,1);
 If IOResult<>0 Then Exit;
 If Length(Content)>0 Then BlockWrite(F,Content[1],Length(Content));
 Close(F);
 WriteWholeFile:=IOResult=0;
End;

Function PathLastPart(Const P:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 I:=Length(P);
 While(I>=1)and not(P[I]in['/','\',':'])do Dec(I);
 PathLastPart:=Copy(P,I+1,Length(P)-I);
End;

Function PathDir(Const P:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 I:=Length(P);
 While(I>=1)and not(P[I]in['/','\',':'])do Dec(I);
 PathDir:=Copy(P,1,I);
End;

Function PathSep:AnsiString;
Begin
 {$IFDEF WINDOWS}
 PathSep:='\';
 {$ELSE}
  {$IFDEF UNIX}
  PathSep:='/';
  {$ELSE}
  PathSep:='\';
  {$ENDIF}
 {$ENDIF}
End;

Function DirExistsP(Const Name:AnsiString):Boolean;
Var
 SR:SearchRec;
 N:AnsiString;
Begin
 N:=Name;
 While(Length(N)>1)and(N[Length(N)]in['/','\'])do Delete(N,Length(N),1);
 FindFirst(N,Directory or AnyFile,SR);
 DirExistsP:=(DosError=0)and((SR.Attr and Directory)<>0);
 FindClose(SR);
End;

Procedure MakeDirs(Const Path:AnsiString);
Var
 I:LongInt;
 Cur:AnsiString;
Begin
 Cur:='';
 For I:=1 to Length(Path)do Begin
  If(Path[I]in['/','\'])and(Cur<>'')and not(Cur[Length(Cur)]in[':','/','\'])Then Begin
   If not DirExistsP(Cur)Then Begin
    MkDir(Cur);
    If IOResult<>0 Then;
   End;
  End;
  Cur:=Cur+Path[I];
 End;
 If(Cur<>'')and not DirExistsP(Cur)Then Begin
  MkDir(Cur);
  If IOResult<>0 Then;
 End;
End;

{ Format d'octets lisible }
Function HumanBytes(N:Double):AnsiString;
Begin
 If N<1024 Then HumanBytes:=FStr(N,0)+' B'
 Else If N<1048576.0 Then HumanBytes:=FStr(N/1024.0,2)+' KiB'
 Else If N<1073741824.0 Then HumanBytes:=FStr(N/1048576.0,2)+' MiB'
 Else HumanBytes:=FStr(N/1073741824.0,2)+' GiB';
End;


{ ------------------------------------------------------------------ }
{ Lecteur GGUF                                                        }
{ ------------------------------------------------------------------ }

Type
 TGKV=Record
  Key:AnsiString;
  Typ:LongInt;           { type GGUF (scalaire) ou GT_ARRAY }
  ArrTyp:LongInt;
  N:Int64;               { longueur du tableau }
  I:Int64;
  F:Double;
  S:AnsiString;
  SA:Array of AnsiString;
  IA:Array of LongInt;
  FA:Array of Single;
 End;

 TTensorInfo=Record
  Name:AnsiString;
  Typ:LongInt;
  NDims:LongInt;
  Ne:Array[0..3]of Int64;
  Ofs:Int64;
  FileIdx:LongInt;
  NBytes:Int64;
  Data:PByte;
 End;

 TGGUF=Record
  Version:LongInt;
  KV:Array of TGKV;
  T:Array of TTensorInfo;
  Align:Int64;
  Files:TStrArray;
  DataOfs:Array of Int64;
  NTotalBytes:Int64;
 End;

Var
 RF:File;
 RBuf:PByte;
 RPos,RLen:LongInt;
 RFileOfs:Int64;
 RName:AnsiString;
Const
 RBufSize=1048576;

Procedure RFill;
Var
 Got:LongInt;
Begin
 Inc(RFileOfs,RLen);
 BlockRead(RF,RBuf^,RBufSize,Got);
 If IOResult<>0 Then Got:=0;
 RLen:=Got;
 RPos:=0;
End;

Procedure ROpen(Const Name:AnsiString);
Begin
 RName:=Name;
 Assign(RF,Name);
 Reset(RF,1);
 If IOResult<>0 Then Fatal('impossible d''ouvrir le fichier modèle : '+Name);
 If RBuf=Nil Then GetMem(RBuf,RBufSize);
 RFileOfs:=0;RLen:=0;RPos:=0;
 RFill;
End;

Procedure RClose;
Begin
 Close(RF);
 If IOResult<>0 Then;
End;

Function RTell:Int64;
Begin
 RTell:=RFileOfs+RPos;
End;

Procedure RGet(Dst:Pointer;N:Int64);
Var
 C:Int64;
Begin
 While N>0 do Begin
  If RPos>=RLen Then Begin
   RFill;
   If RLen=0 Then Fatal('fin de fichier inattendue dans '+RName);
  End;
  C:=RLen-RPos;
  If C>N Then C:=N;
  Move(RBuf[RPos],Dst^,C);
  Inc(RPos,C);
  Dst:=Pointer(PtrUInt(Dst)+PtrUInt(C));
  Dec(N,C);
 End;
End;

Procedure RSkip(N:Int64);
Var
 C:Int64;
Begin
 While N>0 do Begin
  If RPos>=RLen Then Begin
   RFill;
   If RLen=0 Then Fatal('fin de fichier inattendue dans '+RName);
  End;
  C:=RLen-RPos;
  If C>N Then C:=N;
  Inc(RPos,C);
  Dec(N,C);
 End;
End;

Function RU8:Byte;Var V:Byte;Begin RGet(@V,1);RU8:=V;End;
Function RU16:Word;Var V:Word;Begin RGet(@V,2);RU16:=V;End;
Function RU32:LongWord;Var V:LongWord;Begin RGet(@V,4);RU32:=V;End;
Function RU64:QWord;Var V:QWord;Begin RGet(@V,8);RU64:=V;End;
Function RF32:Single;Var V:Single;Begin RGet(@V,4);RF32:=V;End;
Function RF64:Double;Var V:Double;Begin RGet(@V,8);RF64:=V;End;

Function RStr:AnsiString;
Var
 L:QWord;
 S:AnsiString;
Begin
 L:=RU64;
 If L>(1 shl 30)Then Fatal('chaîne GGUF invalide (longueur '+IStr(L)+')');
 SetLength(S,L);
 If L>0 Then RGet(@S[1],L);
 RStr:=S;
End;

Function GGUFTypeSize(T:LongInt):LongInt;
Begin
 Case T of
  GT_UINT8,GT_INT8,GT_BOOL:GGUFTypeSize:=1;
  GT_UINT16,GT_INT16:GGUFTypeSize:=2;
  GT_UINT32,GT_INT32,GT_FLOAT32:GGUFTypeSize:=4;
  GT_UINT64,GT_INT64,GT_FLOAT64:GGUFTypeSize:=8;
  Else GGUFTypeSize:=0;
 End;
End;

Procedure ReadScalar(Typ:LongInt;Var KV:TGKV);
Begin
 Case Typ of
  GT_UINT8:KV.I:=RU8;
  GT_INT8:KV.I:=ShortInt(RU8);
  GT_UINT16:KV.I:=RU16;
  GT_INT16:KV.I:=SmallInt(RU16);
  GT_UINT32:KV.I:=RU32;
  GT_INT32:KV.I:=LongInt(RU32);
  GT_BOOL:KV.I:=RU8;
  GT_UINT64:KV.I:=Int64(RU64);
  GT_INT64:KV.I:=Int64(RU64);
  GT_FLOAT32:KV.F:=RF32;
  GT_FLOAT64:KV.F:=RF64;
  GT_STRING:KV.S:=RStr;
  Else Fatal('type de valeur GGUF inconnu : '+IStr(Typ));
 End;
 If Typ in[GT_UINT8,GT_INT8,GT_UINT16,GT_INT16,GT_UINT32,GT_INT32,GT_BOOL,GT_UINT64,GT_INT64]Then
  KV.F:=KV.I
 Else If Typ in[GT_FLOAT32,GT_FLOAT64]Then KV.I:=Trunc(KV.F);
End;

Procedure ReadKV(Var KV:TGKV;Keep:Boolean);
Var
 I:LongInt;
 Tmp:TGKV;
 ET:LongInt;
Begin
 KV.Key:=RStr;
 KV.Typ:=LongInt(RU32);
 KV.I:=0;KV.F:=0;KV.S:='';KV.N:=0;KV.ArrTyp:=0;
 If KV.Typ=GT_ARRAY Then Begin
  ET:=LongInt(RU32);
  KV.ArrTyp:=ET;
  KV.N:=Int64(RU64);
  If not Keep Then Begin
   { on saute les valeurs }
   If ET=GT_STRING Then Begin
    For I:=1 to LongInt(KV.N)do RSkip(RU64);
   End
    Else If GGUFTypeSize(ET)>0 Then RSkip(KV.N*GGUFTypeSize(ET))
    Else Fatal('tableau GGUF imbriqué non supporté');
   Exit;
  End;
  Case ET of
   GT_STRING:Begin
    SetLength(KV.SA,KV.N);
    For I:=0 to LongInt(KV.N)-1 do KV.SA[I]:=RStr;
   End;
   GT_FLOAT32:Begin
    SetLength(KV.FA,KV.N);
    If KV.N>0 Then RGet(@KV.FA[0],KV.N*4);
   End;
   GT_FLOAT64:Begin
    SetLength(KV.FA,KV.N);
    For I:=0 to LongInt(KV.N)-1 do KV.FA[I]:=RF64;
   End;
   GT_UINT8,GT_INT8,GT_UINT16,GT_INT16,GT_UINT32,GT_INT32,GT_BOOL,GT_UINT64,GT_INT64:Begin
    SetLength(KV.IA,KV.N);
    For I:=0 to LongInt(KV.N)-1 do Begin
     Tmp.I:=0;Tmp.F:=0;Tmp.S:='';
     ReadScalar(ET,Tmp);
     KV.IA[I]:=LongInt(Tmp.I);
    End;
   End;
   Else Fatal('tableau GGUF imbriqué non supporté');
  End;
 End
  Else ReadScalar(KV.Typ,KV);
End;

{ Lit l'en-tete d'un fichier GGUF (ou d'une partie) }
Procedure ParseGGUFHeader(Const Name:AnsiString;FileIdx:LongInt;Var G:TGGUF;KeepKV:Boolean);
Var
 Magic:LongWord;
 NT,NK:Int64;
 I,J:LongInt;
 K0:Int64;
 KV:TGKV;
 TI:TTensorInfo;
 Pos0,Al,Ofs0:Int64;
 Nel:Int64;
Begin
 ROpen(Name);
 Magic:=RU32;
 If Magic<>$46554747 Then Fatal(Name+' n''est pas un fichier GGUF valide (signature absente)');
 G.Version:=LongInt(RU32);
 If(G.Version<2)or(G.Version>3)Then
  Fatal('version GGUF non supportée : '+IStr(G.Version));
 NT:=Int64(RU64);
 NK:=Int64(RU64);
 If(NT<0)or(NT>1000000)or(NK<0)or(NK>1000000)Then Fatal('en-tête GGUF corrompu');
 K0:=Length(G.KV);
 For I:=0 to LongInt(NK)-1 do Begin
  ReadKV(KV,KeepKV);
  If KeepKV Then Begin
   SetLength(G.KV,K0+I+1);
   G.KV[K0+I]:=KV;
  End;
  KV.SA:=Nil;KV.IA:=Nil;KV.FA:=Nil;
 End;
 If KeepKV Then Begin
  G.Align:=32;
  For I:=0 to High(G.KV)do
   If G.KV[I].Key='general.alignment' Then G.Align:=G.KV[I].I;
 End;
 If G.Align<=0 Then G.Align:=32;
 K0:=Length(G.T);
 SetLength(G.T,K0+NT);
 For I:=0 to LongInt(NT)-1 do Begin
  TI.Name:=RStr;
  TI.NDims:=LongInt(RU32);
  If(TI.NDims<1)or(TI.NDims>4)Then Fatal('tenseur '+TI.Name+' : nombre de dimensions invalide');
  For J:=0 to 3 do TI.Ne[J]:=1;
  For J:=0 to TI.NDims-1 do TI.Ne[J]:=Int64(RU64);
  TI.Typ:=LongInt(RU32);
  TI.Ofs:=Int64(RU64);
  TI.FileIdx:=FileIdx;
  TI.Data:=Nil;
  TI.NBytes:=0;
  G.T[K0+I]:=TI;
 End;
 Pos0:=RTell;
 Al:=G.Align;
 Ofs0:=((Pos0+Al-1)div Al)*Al;
 If Length(G.DataOfs)<=FileIdx Then SetLength(G.DataOfs,FileIdx+1);
 G.DataOfs[FileIdx]:=Ofs0;
 RClose;
End;

Function KVFind(Const G:TGGUF;Const Key:AnsiString):LongInt;
Var
 I:LongInt;
Begin
 KVFind:=-1;
 For I:=0 to High(G.KV)do
  If G.KV[I].Key=Key Then Begin KVFind:=I;Exit;End;
End;

Function KVInt(Const G:TGGUF;Const Key:AnsiString;Def:Int64):Int64;
Var
 I:LongInt;
Begin
 I:=KVFind(G,Key);
 If(I<0)or(G.KV[I].Typ=GT_ARRAY)or(G.KV[I].Typ=GT_STRING)Then KVInt:=Def
                                                         Else KVInt:=G.KV[I].I;
End;

Function KVHas(Const G:TGGUF;Const Key:AnsiString):Boolean;
Begin
 KVHas:=KVFind(G,Key)>=0;
End;

Function KVFloat(Const G:TGGUF;Const Key:AnsiString;Def:Double):Double;
Var
 I:LongInt;
Begin
 I:=KVFind(G,Key);
 If(I<0)or(G.KV[I].Typ=GT_ARRAY)or(G.KV[I].Typ=GT_STRING)Then KVFloat:=Def
                                                         Else KVFloat:=G.KV[I].F;
End;

Function KVStr(Const G:TGGUF;Const Key:AnsiString;Const Def:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 I:=KVFind(G,Key);
 If(I<0)or(G.KV[I].Typ<>GT_STRING)Then KVStr:=Def Else KVStr:=G.KV[I].S;
End;

{ Valeur d'un tableau d'entiers, ou scalaire repete }
Function KVIntAt(Const G:TGGUF;Const Key:AnsiString;Idx:LongInt;Def:Int64):Int64;
Var
 I:LongInt;
Begin
 I:=KVFind(G,Key);
 If I<0 Then Begin KVIntAt:=Def;Exit;End;
 If G.KV[I].Typ=GT_ARRAY Then Begin
  If(Idx>=0)and(Idx<Length(G.KV[I].IA))Then KVIntAt:=G.KV[I].IA[Idx]
  Else If(Idx>=0)and(Idx<Length(G.KV[I].FA))Then KVIntAt:=Trunc(G.KV[I].FA[Idx])
  Else KVIntAt:=Def;
 End
  Else If G.KV[I].Typ=GT_STRING Then KVIntAt:=Def
  Else KVIntAt:=G.KV[I].I;
End;

Function FindTensor(Const G:TGGUF;Const Name:AnsiString):LongInt;
Var
 I:LongInt;
Begin
 FindTensor:=-1;
 For I:=0 to High(G.T)do
  If G.T[I].Name=Name Then Begin FindTensor:=I;Exit;End;
End;

{ ------------------------------------------------------------------ }
{ Types de quantification                                             }
{ ------------------------------------------------------------------ }

Function TypeBlockSize(T:LongInt):LongInt;
Begin
 Case T of
  TY_F32,TY_F16,TY_BF16,TY_F64,TY_I8,TY_I16,TY_I32,TY_I64:TypeBlockSize:=1;
  TY_Q4_0,TY_Q4_1,TY_Q5_0,TY_Q5_1,TY_Q8_0,TY_Q8_1,TY_IQ4_NL:TypeBlockSize:=32;
  TY_Q2_K,TY_Q3_K,TY_Q4_K,TY_Q5_K,TY_Q6_K,TY_Q8_K,TY_IQ4_XS:TypeBlockSize:=256;
  Else TypeBlockSize:=0;
 End;
End;

Function TypeByteSize(T:LongInt):LongInt;
Begin
 Case T of
  TY_F32:TypeByteSize:=4;
  TY_F16,TY_BF16:TypeByteSize:=2;
  TY_F64:TypeByteSize:=8;
  TY_I8:TypeByteSize:=1;
  TY_I16:TypeByteSize:=2;
  TY_I32:TypeByteSize:=4;
  TY_I64:TypeByteSize:=8;
  TY_Q4_0:TypeByteSize:=18;
  TY_Q4_1:TypeByteSize:=20;
  TY_Q5_0:TypeByteSize:=22;
  TY_Q5_1:TypeByteSize:=24;
  TY_Q8_0:TypeByteSize:=34;
  TY_Q8_1:TypeByteSize:=36;
  TY_IQ4_NL:TypeByteSize:=18;
  TY_Q2_K:TypeByteSize:=84;
  TY_Q3_K:TypeByteSize:=110;
  TY_Q4_K:TypeByteSize:=144;
  TY_Q5_K:TypeByteSize:=176;
  TY_Q6_K:TypeByteSize:=210;
  TY_Q8_K:TypeByteSize:=292;
  TY_IQ4_XS:TypeByteSize:=136;
  Else TypeByteSize:=0;
 End;
End;

Function TypeName(T:LongInt):AnsiString;
Begin
 Case T of
  TY_F32:TypeName:='F32';
  TY_F16:TypeName:='F16';
  TY_BF16:TypeName:='BF16';
  TY_F64:TypeName:='F64';
  TY_Q4_0:TypeName:='Q4_0';
  TY_Q4_1:TypeName:='Q4_1';
  TY_Q5_0:TypeName:='Q5_0';
  TY_Q5_1:TypeName:='Q5_1';
  TY_Q8_0:TypeName:='Q8_0';
  TY_Q8_1:TypeName:='Q8_1';
  TY_Q2_K:TypeName:='Q2_K';
  TY_Q3_K:TypeName:='Q3_K';
  TY_Q4_K:TypeName:='Q4_K';
  TY_Q5_K:TypeName:='Q5_K';
  TY_Q6_K:TypeName:='Q6_K';
  TY_Q8_K:TypeName:='Q8_K';
  TY_IQ4_NL:TypeName:='IQ4_NL';
  TY_IQ4_XS:TypeName:='IQ4_XS';
  TY_I8:TypeName:='I8';
  TY_I16:TypeName:='I16';
  TY_I32:TypeName:='I32';
  TY_I64:TypeName:='I64';
  Else TypeName:='type'+IStr(T);
 End;
End;

Function RowBytes(T:LongInt;N:Int64):Int64;
Var
 B:LongInt;
Begin
 B:=TypeBlockSize(T);
 If B=0 Then RowBytes:=0 Else RowBytes:=(N div B)*TypeByteSize(T);
End;

Function TensorElems(Const T:TTensorInfo):Int64;
Begin
 TensorElems:=T.Ne[0]*T.Ne[1]*T.Ne[2]*T.Ne[3];
End;

Const
 KValuesIQ4NL:Array[0..15]of ShortInt=
  (-127,-104,-83,-65,-49,-35,-22,-10,1,13,25,38,53,69,89,113);

Procedure DeqQ4_0(Src:PByte;Dst:PSingle;N:LongInt);
Var
 NB,I,J:LongInt;
 D:Single;
 Q:PByte;
Begin
 NB:=N shr 5;
 For I:=0 to NB-1 do Begin
  D:=F16Tab[PWord(Src)^];
  Q:=Src+2;
  For J:=0 to 15 do Begin
   Dst[J]:=((Q[J]and $F)-8)*D;
   Dst[J+16]:=((Q[J]shr 4)-8)*D;
  End;
  Inc(Src,18);Inc(Dst,32);
 End;
End;

Procedure DeqQ4_1(Src:PByte;Dst:PSingle;N:LongInt);
Var
 NB,I,J:LongInt;
 D,M:Single;
 Q:PByte;
Begin
 NB:=N shr 5;
 For I:=0 to NB-1 do Begin
  D:=F16Tab[PWord(Src)^];
  M:=F16Tab[PWord(Src+2)^];
  Q:=Src+4;
  For J:=0 to 15 do Begin
   Dst[J]:=(Q[J]and $F)*D+M;
   Dst[J+16]:=(Q[J]shr 4)*D+M;
  End;
  Inc(Src,20);Inc(Dst,32);
 End;
End;

Procedure DeqQ5_0(Src:PByte;Dst:PSingle;N:LongInt);
Var
 NB,I,J:LongInt;
 D:Single;
 Q:PByte;
 QH:LongWord;
 X0,X1:LongInt;
Begin
 NB:=N shr 5;
 For I:=0 to NB-1 do Begin
  D:=F16Tab[PWord(Src)^];
  QH:=PLongWord(Src+2)^;
  Q:=Src+6;
  For J:=0 to 15 do Begin
   X0:=(Q[J]and $F)or(((QH shr J)shl 4)and $10);
   X1:=(Q[J]shr 4)or((QH shr(J+12))and $10);
   Dst[J]:=(X0-16)*D;
   Dst[J+16]:=(X1-16)*D;
  End;
  Inc(Src,22);Inc(Dst,32);
 End;
End;

Procedure DeqQ5_1(Src:PByte;Dst:PSingle;N:LongInt);
Var
 NB,I,J:LongInt;
 D,M:Single;
 Q:PByte;
 QH:LongWord;
 X0,X1:LongInt;
Begin
 NB:=N shr 5;
 For I:=0 to NB-1 do Begin
  D:=F16Tab[PWord(Src)^];
  M:=F16Tab[PWord(Src+2)^];
  QH:=PLongWord(Src+4)^;
  Q:=Src+8;
  For J:=0 to 15 do Begin
   X0:=(Q[J]and $F)or(((QH shr J)shl 4)and $10);
   X1:=(Q[J]shr 4)or((QH shr(J+12))and $10);
   Dst[J]:=X0*D+M;
   Dst[J+16]:=X1*D+M;
  End;
  Inc(Src,24);Inc(Dst,32);
 End;
End;

Procedure DeqQ8_0(Src:PByte;Dst:PSingle;N:LongInt);
Var
 NB,I,J:LongInt;
 D:Single;
 Q:PShortInt;
Begin
 NB:=N shr 5;
 For I:=0 to NB-1 do Begin
  D:=F16Tab[PWord(Src)^];
  Q:=PShortInt(Src+2);
  For J:=0 to 31 do Dst[J]:=Q[J]*D;
  Inc(Src,34);Inc(Dst,32);
 End;
End;

Procedure DeqIQ4NL(Src:PByte;Dst:PSingle;N:LongInt);
Var
 NB,I,J:LongInt;
 D:Single;
 Q:PByte;
Begin
 NB:=N shr 5;
 For I:=0 to NB-1 do Begin
  D:=F16Tab[PWord(Src)^];
  Q:=Src+2;
  For J:=0 to 15 do Begin
   Dst[J]:=D*KValuesIQ4NL[Q[J]and $F];
   Dst[J+16]:=D*KValuesIQ4NL[Q[J]shr 4];
  End;
  Inc(Src,18);Inc(Dst,32);
 End;
End;

Procedure DeqIQ4XS(Src:PByte;Dst:PSingle;N:LongInt);
Var
 NB,I,IB,J:LongInt;
 D,DL:Single;
 Q:PByte;
 SH:Word;
 LS:LongInt;
Begin
 NB:=N shr 8;
 For I:=0 to NB-1 do Begin
  D:=F16Tab[PWord(Src)^];
  SH:=PWord(Src+2)^;
  Q:=Src+8;
  For IB:=0 to 7 do Begin
   LS:=((Src[4+(IB shr 1)]shr(4*(IB and 1)))and $F)or(((SH shr(2*IB))and 3)shl 4);
   DL:=D*(LS-32);
   For J:=0 to 15 do Begin
    Dst[J]:=DL*KValuesIQ4NL[Q[J]and $F];
    Dst[J+16]:=DL*KValuesIQ4NL[Q[J]shr 4];
   End;
   Inc(Dst,32);Inc(Q,16);
  End;
  Inc(Src,136);
 End;
End;

Procedure DeqQ2K(Src:PByte;Dst:PSingle;N:LongInt);
Var
 NB,I,NN,J,L,Shift,IS_:LongInt;
 D,Mn,DL,ML:Single;
 Q,Sc:PByte;
 SCv:Byte;
Begin
 NB:=N shr 8;
 For I:=0 to NB-1 do Begin
  Sc:=Src;
  Q:=Src+16;
  D:=F16Tab[PWord(Src+80)^];
  Mn:=F16Tab[PWord(Src+82)^];
  IS_:=0;
  NN:=0;
  While NN<256 do Begin
   Shift:=0;
   For J:=0 to 3 do Begin
    SCv:=Sc[IS_];Inc(IS_);
    DL:=D*(SCv and $F);ML:=Mn*(SCv shr 4);
    For L:=0 to 15 do Dst[L]:=DL*((Q[L]shr Shift)and 3)-ML;
    Inc(Dst,16);
    SCv:=Sc[IS_];Inc(IS_);
    DL:=D*(SCv and $F);ML:=Mn*(SCv shr 4);
    For L:=0 to 15 do Dst[L]:=DL*((Q[L+16]shr Shift)and 3)-ML;
    Inc(Dst,16);
    Inc(Shift,2);
   End;
   Inc(Q,32);
   Inc(NN,128);
  End;
  Inc(Src,84);
 End;
End;

Procedure DeqQ3K(Src:PByte;Dst:PSingle;N:LongInt);
Var
 NB,I,NN,J,L,Shift,IS_:LongInt;
 DAll,DL:Single;
 Q,HM:PByte;
 M:Byte;
 Aux:Array[0..3]of LongWord;
 Tmp:LongWord;
 Sc:Array[0..15]of ShortInt;
 V:LongInt;
Begin
 NB:=N shr 8;
 For I:=0 to NB-1 do Begin
  HM:=Src;
  Q:=Src+32;
  DAll:=F16Tab[PWord(Src+108)^];
  Move(Src[96],Aux[0],12);
  Tmp:=Aux[2];
  Aux[2]:=((Aux[0]shr 4)and $0F0F0F0F)or(((Tmp shr 4)and $03030303)shl 4);
  Aux[3]:=((Aux[1]shr 4)and $0F0F0F0F)or(((Tmp shr 6)and $03030303)shl 4);
  Aux[0]:=(Aux[0]and $0F0F0F0F)or(((Tmp shr 0)and $03030303)shl 4);
  Aux[1]:=(Aux[1]and $0F0F0F0F)or(((Tmp shr 2)and $03030303)shl 4);
  Move(Aux[0],Sc[0],16);
  M:=1;
  IS_:=0;
  NN:=0;
  While NN<256 do Begin
   Shift:=0;
   For J:=0 to 3 do Begin
    DL:=DAll*(Sc[IS_]-32);Inc(IS_);
    For L:=0 to 15 do Begin
     V:=(Q[L]shr Shift)and 3;
     If(HM[L]and M)=0 Then V:=V-4;
     Dst[L]:=DL*V;
    End;
    Inc(Dst,16);
    DL:=DAll*(Sc[IS_]-32);Inc(IS_);
    For L:=0 to 15 do Begin
     V:=(Q[L+16]shr Shift)and 3;
     If(HM[L+16]and M)=0 Then V:=V-4;
     Dst[L]:=DL*V;
    End;
    Inc(Dst,16);
    Inc(Shift,2);
    M:=M shl 1;
   End;
   Inc(Q,32);
   Inc(NN,128);
  End;
  Inc(Src,110);
 End;
End;

Procedure ScaleMinK4(J:LongInt;Q:PByte;Var D,M:Byte);
Begin
 If J<4 Then Begin
  D:=Q[J]and 63;M:=Q[J+4]and 63;
 End
  Else Begin
   D:=(Q[J+4]and $F)or((Q[J-4]shr 6)shl 4);
   M:=(Q[J+4]shr 4)or((Q[J]shr 6)shl 4);
  End;
End;

Procedure DeqQ4K(Src:PByte;Dst:PSingle;N:LongInt);
Var
 NB,I,J,L,IS_:LongInt;
 D,Mn,D1,D2,M1,M2:Single;
 Q:PByte;
 Sc,M:Byte;
Begin
 NB:=N shr 8;
 For I:=0 to NB-1 do Begin
  D:=F16Tab[PWord(Src)^];
  Mn:=F16Tab[PWord(Src+2)^];
  Q:=Src+16;
  IS_:=0;
  J:=0;
  While J<256 do Begin
   ScaleMinK4(IS_,Src+4,Sc,M);
   D1:=D*Sc;M1:=Mn*M;
   ScaleMinK4(IS_+1,Src+4,Sc,M);
   D2:=D*Sc;M2:=Mn*M;
   For L:=0 to 31 do Dst[L]:=D1*(Q[L]and $F)-M1;
   For L:=0 to 31 do Dst[L+32]:=D2*(Q[L]shr 4)-M2;
   Inc(Dst,64);
   Inc(Q,32);
   Inc(IS_,2);
   Inc(J,64);
  End;
  Inc(Src,144);
 End;
End;

Procedure DeqQ5K(Src:PByte;Dst:PSingle;N:LongInt);
Var
 NB,I,J,L,IS_:LongInt;
 D,Mn,D1,D2,M1,M2:Single;
 QL,QH:PByte;
 Sc,M,U1,U2:Byte;
 V1,V2:LongInt;
Begin
 NB:=N shr 8;
 For I:=0 to NB-1 do Begin
  D:=F16Tab[PWord(Src)^];
  Mn:=F16Tab[PWord(Src+2)^];
  QH:=Src+16;
  QL:=Src+48;
  IS_:=0;
  U1:=1;U2:=2;
  J:=0;
  While J<256 do Begin
   ScaleMinK4(IS_,Src+4,Sc,M);
   D1:=D*Sc;M1:=Mn*M;
   ScaleMinK4(IS_+1,Src+4,Sc,M);
   D2:=D*Sc;M2:=Mn*M;
   For L:=0 to 31 do Begin
    V1:=(QL[L]and $F);
    If(QH[L]and U1)<>0 Then Inc(V1,16);
    Dst[L]:=D1*V1-M1;
   End;
   For L:=0 to 31 do Begin
    V2:=(QL[L]shr 4);
    If(QH[L]and U2)<>0 Then Inc(V2,16);
    Dst[L+32]:=D2*V2-M2;
   End;
   Inc(Dst,64);
   Inc(QL,32);
   Inc(IS_,2);
   U1:=U1 shl 2;U2:=U2 shl 2;
   Inc(J,64);
  End;
  Inc(Src,176);
 End;
End;

Procedure DeqQ6K(Src:PByte;Dst:PSingle;N:LongInt);
Var
 NB,I,NN,L,IS_:LongInt;
 D:Single;
 QL,QH:PByte;
 Sc:PShortInt;
 Q1,Q2,Q3,Q4:LongInt;
Begin
 NB:=N shr 8;
 For I:=0 to NB-1 do Begin
  D:=F16Tab[PWord(Src+208)^];
  QL:=Src;
  QH:=Src+128;
  Sc:=PShortInt(Src+192);
  NN:=0;
  While NN<256 do Begin
   For L:=0 to 31 do Begin
    IS_:=L shr 4;
    Q1:=LongInt((QL[L]and $F)or(((QH[L]shr 0)and 3)shl 4))-32;
    Q2:=LongInt((QL[L+32]and $F)or(((QH[L]shr 2)and 3)shl 4))-32;
    Q3:=LongInt((QL[L]shr 4)or(((QH[L]shr 4)and 3)shl 4))-32;
    Q4:=LongInt((QL[L+32]shr 4)or(((QH[L]shr 6)and 3)shl 4))-32;
    Dst[L]:=D*Sc[IS_]*Q1;
    Dst[L+32]:=D*Sc[IS_+2]*Q2;
    Dst[L+64]:=D*Sc[IS_+4]*Q3;
    Dst[L+96]:=D*Sc[IS_+6]*Q4;
   End;
   Inc(Dst,128);
   Inc(QL,64);
   Inc(QH,32);
   Inc(Sc,8);
   Inc(NN,128);
  End;
  Inc(Src,210);
 End;
End;

{ appele depuis un fil de calcul : evite toute chaine temporaire (cadre d'exception) dans DequantRow }
Procedure BadQuantType(T:LongInt);
Begin
 Fatal('type de quantification non supporté : '+TypeName(T));
End;

{ Deplie une ligne de N elements du type T vers des flottants }
Procedure DequantRow(T:LongInt;Src:PByte;Dst:PSingle;N:LongInt);
Var
 I:LongInt;
Begin
 Case T of
  TY_F32:Move(Src^,Dst^,N*4);
  TY_F16:For I:=0 to N-1 do Dst[I]:=F16Tab[PWord(Src)[I]];
  TY_BF16:For I:=0 to N-1 do Dst[I]:=BF16ToFloat(PWord(Src)[I]);
  TY_F64:For I:=0 to N-1 do Dst[I]:=PDouble(Src)[I];
  TY_Q4_0:DeqQ4_0(Src,Dst,N);
  TY_Q4_1:DeqQ4_1(Src,Dst,N);
  TY_Q5_0:DeqQ5_0(Src,Dst,N);
  TY_Q5_1:DeqQ5_1(Src,Dst,N);
  TY_Q8_0:DeqQ8_0(Src,Dst,N);
  TY_IQ4_NL:DeqIQ4NL(Src,Dst,N);
  TY_IQ4_XS:DeqIQ4XS(Src,Dst,N);
  TY_Q2_K:DeqQ2K(Src,Dst,N);
  TY_Q3_K:DeqQ3K(Src,Dst,N);
  TY_Q4_K:DeqQ4K(Src,Dst,N);
  TY_Q5_K:DeqQ5K(Src,Dst,N);
  TY_Q6_K:DeqQ6K(Src,Dst,N);
  Else BadQuantType(T);
 End;
End;

Function TypeSupported(T:LongInt):Boolean;
Begin
 TypeSupported:=T in[TY_F32,TY_F16,TY_BF16,TY_F64,TY_Q4_0,TY_Q4_1,TY_Q5_0,TY_Q5_1,
                     TY_Q8_0,TY_IQ4_NL,TY_IQ4_XS,TY_Q2_K,TY_Q3_K,TY_Q4_K,TY_Q5_K,TY_Q6_K];
End;

{ Charge toutes les donnees de tenseurs en memoire }
Procedure LoadTensorData(Var G:TGGUF;Verbose:Boolean);
Var
 I,Cur:LongInt;
 F:File;
 Tot,Done:Int64;
 Remaining,Chunk:Int64;
 Got:LongInt;
 P:PByte;
 Last:LongInt;
 NEl:Int64;
 Name:AnsiString;
Begin
 Tot:=0;
 For I:=0 to High(G.T)do Begin
  If not TypeSupported(G.T[I].Typ)Then Begin
   G.T[I].NBytes:=0;
   Continue;
  End;
  NEl:=TensorElems(G.T[I]);
  If(TypeBlockSize(G.T[I].Typ)>0)and((G.T[I].Ne[0]mod TypeBlockSize(G.T[I].Typ))<>0)Then
   Fatal('le tenseur '+G.T[I].Name+' a une taille de ligne incompatible avec son type');
  G.T[I].NBytes:=RowBytes(G.T[I].Typ,G.T[I].Ne[0])*G.T[I].Ne[1]*G.T[I].Ne[2]*G.T[I].Ne[3];
  Inc(Tot,G.T[I].NBytes);
 End;
 G.NTotalBytes:=Tot;
 Done:=0;
 For Cur:=0 to High(G.Files)do Begin
  Assign(F,G.Files[Cur]);
  Reset(F,1);
  If IOResult<>0 Then Fatal('impossible d''ouvrir '+G.Files[Cur]);
  Last:=0;
  For I:=0 to High(G.T)do Begin
   If(G.T[I].FileIdx<>Cur)or(G.T[I].NBytes=0)Then Continue;
   GetMem(G.T[I].Data,G.T[I].NBytes+64);
   Seek(F,G.DataOfs[Cur]+G.T[I].Ofs);
   If IOResult<>0 Then Fatal('positionnement impossible dans '+G.Files[Cur]);
   P:=G.T[I].Data;
   Remaining:=G.T[I].NBytes;
   While Remaining>0 do Begin
    Chunk:=67108864;
    If Remaining<Chunk Then Chunk:=Remaining;
    BlockRead(F,P^,Chunk,Got);
    If(IOResult<>0)or(Got<>Chunk)Then
     Fatal('lecture tronquée du tenseur '+G.T[I].Name+' (fichier incomplet ?)');
    Inc(P,Chunk);
    Dec(Remaining,Chunk);
   End;
   Inc(Done,G.T[I].NBytes);
   If Verbose Then Begin
    If(Done*50 div(Tot+1))>Last Then Begin
     Last:=Done*50 div(Tot+1);
     Write(StdErr,'.');Flush(StdErr);
    End;
   End;
  End;
  Close(F);
  If IOResult<>0 Then;
 End;
 If Verbose Then Begin Write(StdErr,#10);Flush(StdErr);End;
End;


{ ------------------------------------------------------------------ }
{ Table de hachage chaine -> entier                                   }
{ ------------------------------------------------------------------ }

Type
 THash=Record
  Keys:TStrArray;
  Vals:TIntArray;
  Used:TBoolArray;
  Mask:LongInt;
  Count:LongInt;
 End;

Function HashStr(Const S:AnsiString):LongWord;
Var
 H:LongWord;
 I:LongInt;
Begin
 H:=2166136261;
 For I:=1 to Length(S)do Begin
  H:=H xor Ord(S[I]);
  H:=H*16777619;
 End;
 HashStr:=H;
End;

Procedure HInit(Var H:THash;N:LongInt);
Var
 Cap:LongInt;
Begin
 Cap:=1024;
 While Cap<N*2+16 do Cap:=Cap*2;
 SetLength(H.Keys,Cap);
 SetLength(H.Vals,Cap);
 SetLength(H.Used,Cap);
 FillChar(H.Used[0],Cap,0);
 H.Mask:=Cap-1;
 H.Count:=0;
End;

Procedure HGrow(Var H:THash);Forward;

Function HFind(Const H:THash;Const K:AnsiString):LongInt;
Var
 I:LongInt;
Begin
 HFind:=-1;
 If H.Mask=0 Then Exit;
 I:=HashStr(K)and H.Mask;
 While H.Used[I]do Begin
  If H.Keys[I]=K Then Begin HFind:=H.Vals[I];Exit;End;
  I:=(I+1)and H.Mask;
 End;
End;

Procedure HPutRaw(Var H:THash;Const K:AnsiString;V:LongInt);
Var
 I:LongInt;
Begin
 I:=HashStr(K)and H.Mask;
 While H.Used[I]do Begin
  If H.Keys[I]=K Then Begin H.Vals[I]:=V;Exit;End;
  I:=(I+1)and H.Mask;
 End;
 H.Used[I]:=True;
 H.Keys[I]:=K;
 H.Vals[I]:=V;
 Inc(H.Count);
End;

Procedure HGrow(Var H:THash);
Var
 Old:THash;
 I:LongInt;
Begin
 Old:=H;
 HInit(H,(Old.Mask+1));
 For I:=0 to Old.Mask do
  If Old.Used[I]Then HPutRaw(H,Old.Keys[I],Old.Vals[I]);
End;

Procedure HPut(Var H:THash;Const K:AnsiString;V:LongInt);
Begin
 If(H.Count+1)*2>H.Mask Then HGrow(H);
 HPutRaw(H,K,V);
End;

{ ------------------------------------------------------------------ }
{ Classification Unicode (approximation sans tables)                  }
{ ------------------------------------------------------------------ }

Function CpIsSpace(C:LongInt):Boolean;
Begin
 CpIsSpace:=((C>=9)and(C<=13))or(C=32)or(C=$85)or(C=$A0)or(C=$1680)or
            ((C>=$2000)and(C<=$200A))or(C=$2028)or(C=$2029)or(C=$202F)or
            (C=$205F)or(C=$3000);
End;

Function CpIsNumber(C:LongInt):Boolean;
Begin
 If C<128 Then CpIsNumber:=(C>=48)and(C<=57)
 Else CpIsNumber:=(C=$B2)or(C=$B3)or(C=$B9)or((C>=$BC)and(C<=$BE))or
   ((C>=$660)and(C<=$669))or((C>=$6F0)and(C<=$6F9))or((C>=$966)and(C<=$96F))or
   ((C>=$9E6)and(C<=$9EF))or((C>=$E50)and(C<=$E59))or((C>=$2070)and(C<=$2079))or
   ((C>=$2080)and(C<=$2089))or((C>=$2150)and(C<=$2189))or((C>=$2460)and(C<=$249B))or
   ((C>=$FF10)and(C<=$FF19))or((C>=$1D7CE)and(C<=$1D7FF));
End;

Function CpIsMark(C:LongInt):Boolean;
Begin
 CpIsMark:=((C>=$300)and(C<=$36F))or((C>=$483)and(C<=$489))or((C>=$591)and(C<=$5BD))or
           ((C>=$610)and(C<=$61A))or((C>=$64B)and(C<=$65F))or((C>=$900)and(C<=$903))or
           ((C>=$93A)and(C<=$94F))or((C>=$1AB0)and(C<=$1AFF))or((C>=$1DC0)and(C<=$1DFF))or
           ((C>=$20D0)and(C<=$20FF))or((C>=$FE00)and(C<=$FE0F))or((C>=$FE20)and(C<=$FE2F));
End;

Function CpIsLetter(C:LongInt):Boolean;
Begin
 If C<128 Then Begin
  CpIsLetter:=((C>=65)and(C<=90))or((C>=97)and(C<=122));
  Exit;
 End;
 If C<$C0 Then Begin
  CpIsLetter:=(C=$AA)or(C=$B5)or(C=$BA);
  Exit;
 End;
 If C<$370 Then Begin
  CpIsLetter:=(C<>$D7)and(C<>$F7)and not((C>=$2C2)and(C<=$2C5))and not((C>=$2D2)and(C<=$2DF))
              and not((C>=$300)and(C<=$36F));
  Exit;
 End;
 If CpIsMark(C)or CpIsNumber(C)Then Begin CpIsLetter:=False;Exit;End;
 If(C>=$2000)and(C<=$2BFF)Then Begin CpIsLetter:=False;Exit;End;
 If(C>=$2E00)and(C<=$2E7F)Then Begin CpIsLetter:=False;Exit;End;
 If(C>=$3000)and(C<=$3004)Then Begin CpIsLetter:=False;Exit;End;
 If(C>=$3008)and(C<=$3020)Then Begin CpIsLetter:=False;Exit;End;
 If(C>=$3030)and(C<=$3040)Then Begin CpIsLetter:=False;Exit;End;
 If(C>=$FE30)and(C<=$FE6F)Then Begin CpIsLetter:=False;Exit;End;
 If(C>=$FF00)and(C<=$FF0F)Then Begin CpIsLetter:=False;Exit;End;
 If(C>=$FF1A)and(C<=$FF20)Then Begin CpIsLetter:=False;Exit;End;
 If(C>=$FF3B)and(C<=$FF40)Then Begin CpIsLetter:=False;Exit;End;
 If(C>=$FF5B)and(C<=$FF65)Then Begin CpIsLetter:=False;Exit;End;
 If(C>=$FFF0)and(C<=$FFFF)Then Begin CpIsLetter:=False;Exit;End;
 If(C>=$E000)and(C<=$F8FF)Then Begin CpIsLetter:=False;Exit;End;
 If(C>=$1F000)and(C<=$1FAFF)Then Begin CpIsLetter:=False;Exit;End;
 If(C>=$E0000)Then Begin CpIsLetter:=False;Exit;End;
 If(C>=$37E)and(C<=$385)Then Begin CpIsLetter:=C=$386;Exit;End;
 CpIsLetter:=True;
End;

Function CpIsPunct(C:LongInt):Boolean;
Begin
 If C<128 Then
  CpIsPunct:=(C in[33..35,37..42,44..47,58,59,63,64,91..93,95,123,125])
 Else CpIsPunct:=(C=$A1)or(C=$A7)or(C=$AB)or(C=$B6)or(C=$B7)or(C=$BB)or(C=$BF)or
   ((C>=$2010)and(C<=$2027))or((C>=$2030)and(C<=$205E))or((C>=$3001)and(C<=$3003))or
   ((C>=$3008)and(C<=$3011))or((C>=$FF01)and(C<=$FF03))or((C>=$FF05)and(C<=$FF0A))or
   ((C>=$FF0C)and(C<=$FF0F))or(C=$FF1A)or(C=$FF1B)or(C=$FF1F)or(C=$FF20);
End;

Function CpToLower(C:LongInt):LongInt;
Begin
 If(C>=65)and(C<=90)Then CpToLower:=C+32 Else CpToLower:=C;
End;

{ ------------------------------------------------------------------ }
{ Vocabulaire et tokeniseur                                           }
{ ------------------------------------------------------------------ }

Const
 VT_NONE=0;
 VT_SPM=1;
 VT_BPE=2;

 PRE_DEFAULT=0; PRE_LLAMA3=1; PRE_QWEN2=2; PRE_QWEN35=3; PRE_GPT2=4;
 PRE_SMOLLM=5; PRE_FALCON=6; PRE_DEEPSEEK_LLM=7; PRE_DEEPSEEK_CODER=8; PRE_BLOOM=9;
 PRE_VIKING=10;

Type
 TVocab=Record
  Model:AnsiString;
  PreName:AnsiString;
  VType:LongInt;
  PreType:LongInt;
  NTokens:LongInt;
  Text:TStrArray;
  Score:TSingleArray;
  Attr:TIntArray;
  TokHash:THash;
  MergeHash:THash;
  BOS,EOS,EOT,EOM,UNK,SEP,PAD,MASK,NL:LongInt;
  FimPre,FimSuf,FimMid,FimPad,FimRep,FimSep:LongInt;
  AddBOS,AddEOS,AddSep,AddSpacePrefix,RemoveExtraWs,EscapeWs,CleanSpaces,IgnoreMerges:Boolean;
  EOG:TBoolArray;
  Specials:TIntArray;
  ByteTok:Array[0..255]of LongInt;
  ChatTemplate:AnsiString;
  MaxTokLen:LongInt;
 End;

Var
 ByteToUniCp:Array[0..255]of LongInt;
 ByteToUniStr:Array[0..255]of AnsiString;
 UniToByteTab:Array[0..511]of LongInt;

Procedure InitByteUnicode;
Var
 B,N:LongInt;
Begin
 For B:=0 to 511 do UniToByteTab[B]:=-1;
 N:=0;
 For B:=0 to 255 do Begin
  If((B>=33)and(B<=126))or((B>=161)and(B<=172))or((B>=174)and(B<=255))Then
   ByteToUniCp[B]:=B
  Else Begin
   ByteToUniCp[B]:=256+N;
   Inc(N);
  End;
  ByteToUniStr[B]:=CpToUtf8(ByteToUniCp[B]);
  UniToByteTab[ByteToUniCp[B]]:=B;
 End;
End;

Function VocabTextToToken(Const V:TVocab;Const S:AnsiString):LongInt;
Begin
 VocabTextToToken:=HFind(V.TokHash,S);
End;

Function VocabByteToToken(Const V:TVocab;B:Byte):LongInt;
Var
 R:LongInt;
Begin
 R:=HFind(V.TokHash,'<0x'+HexStr2(B)+'>');
 If R<0 Then R:=HFind(V.TokHash,Chr(B));
 If R<0 Then R:=V.UNK;
 VocabByteToToken:=R;
End;

Function VocabIsEOG(Const V:TVocab;Tok:LongInt):Boolean;
Begin
 If(Tok<0)or(Tok>=V.NTokens)Then VocabIsEOG:=False
 Else VocabIsEOG:=V.EOG[Tok];
End;

Function VocabIsControl(Const V:TVocab;Tok:LongInt):Boolean;
Begin
 If(Tok<0)or(Tok>=V.NTokens)Then VocabIsControl:=False
 Else VocabIsControl:=(V.Attr[Tok]and TA_CONTROL)<>0;
End;

{ Convertit le texte d'un jeton BPE (octets encodes en unicode) vers les octets reels }
Function DecodeBpeText(Const S:AnsiString):AnsiString;
Var
 Cps,Offs:TIntArray;
 I,B:LongInt;
 R:AnsiString;
Begin
 Utf8ToCps(S,Cps,Offs);
 R:='';
 For I:=0 to High(Cps)do Begin
  If(Cps[I]>=0)and(Cps[I]<512)and(UniToByteTab[Cps[I]]>=0)Then
   R:=R+Chr(UniToByteTab[Cps[I]])
  Else Begin
   R:=R+'[UNK_BYTE_0x';
   For B:=Offs[I]+1 to Offs[I+1]do R:=R+LoStr(HexStr2(Ord(S[B])));
   R:=R+S+']';
  End;
 End;
 DecodeBpeText:=R;
End;

{ Equivalent de llama_token_to_piece }
Function TokenToPiece(Const V:TVocab;Tok:LongInt;Special:Boolean;LStrip:LongInt):AnsiString;
Var
 A:LongInt;
 R:AnsiString;
Begin
 TokenToPiece:='';
 If(Tok<0)or(Tok>=V.NTokens)Then Exit;
 A:=V.Attr[Tok];
 If(not Special)and((A and(TA_UNKNOWN or TA_CONTROL))<>0)Then Exit;
 R:='';
 If V.VType=VT_NONE Then Exit;
 If(A and(TA_UNKNOWN or TA_CONTROL or TA_USER_DEFINED))<>0 Then R:=V.Text[Tok]
 Else If(A and TA_NORMAL)<>0 Then Begin
  If(V.VType=VT_SPM)or V.EscapeWs Then R:=ReplaceAll(V.Text[Tok],#$E2#$96#$81,' ')
  Else R:=DecodeBpeText(V.Text[Tok]);
 End
  Else If(A and TA_BYTE)<>0 Then Begin
   R:=V.Text[Tok];
   If(Length(R)=6)and(Copy(R,1,3)='<0x')and(R[6]='>')Then
    R:=Chr(HexVal(R[4])*16+HexVal(R[5]))
   Else R:='';
  End
  Else R:='';
 While(LStrip>0)and(R<>'')and(R[1]=' ')do Begin
  Delete(R,1,1);
  Dec(LStrip);
 End;
 TokenToPiece:=R;
End;

Function DetokenizeTokens(Const V:TVocab;Const Toks:TIntArray;Count:LongInt;Special:Boolean;
                          RemoveSpecial:Boolean):AnsiString;
Var
 I,Start,Fin:LongInt;
 R:AnsiString;
 RemoveSpace:Boolean;
Begin
 R:='';
 Start:=0;Fin:=Count;
 RemoveSpace:=V.AddSpacePrefix;
 If RemoveSpecial and V.AddBOS Then Begin
  If(Fin>0)and(Toks[0]=V.BOS)Then Begin RemoveSpace:=False;Inc(Start);End;
 End;
 If RemoveSpecial and V.AddEOS Then Begin
  If(Fin>Start)and(Toks[Fin-1]=V.EOS)Then Dec(Fin);
 End;
 For I:=Start to Fin-1 do Begin
  If RemoveSpace Then R:=R+TokenToPiece(V,Toks[I],Special,1)
                 Else R:=R+TokenToPiece(V,Toks[I],Special,0);
  RemoveSpace:=False;
 End;
 DetokenizeTokens:=R;
End;

{ --- pre-tokeniseur : decoupage en mots (portage de unicode_regex_split_custom_*) --- }

Type
 TWordList=Array of LongInt;   { longueurs successives en points de code }

Procedure WLAdd(Var W:TWordList;N:LongInt);
Var
 L:LongInt;
Begin
 If N<=0 Then Exit;
 L:=Length(W);
 SetLength(W,L+1);
 W[L]:=N;
End;

{ Applique le decoupeur `Kind` a chaque segment (liste des longueurs) }
Const
 SPL_GPT2=1; SPL_LLAMA3=2; SPL_QWEN2=3; SPL_QWEN35=4; SPL_DIGIT1=5; SPL_PUNCT=6;
 SPL_NUMS=7; SPL_DIG3=8; SPL_NL=9; SPL_SPL=10; SPL_SPP=11; SPL_CJK=12; SPL_ENDWS=13;
 SPL_DSPUNCT=14; SPL_BLOOM=15;

Function CpAt(Const Cps:TIntArray;Pos,Ini,Fin:LongInt):LongInt;
Begin
 If(Pos>=Ini)and(Pos<Fin)Then CpAt:=Cps[Pos]Else CpAt:=-1;
End;

Function IsDsP(C:LongInt):Boolean;
Begin
 IsDsP:=((C>=33)and(C<=47))or((C>=58)and(C<=126))or((C>=$FF01)and(C<=$FF0F))or
        ((C>=$FF1A)and(C<=$FF5E))or((C>=$2018)and(C<=$201F))or((C>=$3000)and(C<=$3002));
End;

Function IsBloomCh(C:LongInt):Boolean;
Begin
 IsBloomCh:=not(CpIsSpace(C)or(C=40)or(C=41)or(C=124)or(C=46)or(C=44)or(C=33)or(C=63)or
                (C=$2026)or(C=$3002)or(C=$FF0C)or(C=$3001)or(C=$964)or(C=$6D4)or(C=$60C));
End;

Function SplitSegment(Const Cps:TIntArray;Ini,Fin:LongInt;Kind:LongInt;Var Out:TWordList):LongInt;
Var
 Pos,PrevEnd,C,C2,CN,CNN,Ini2,NumWs,LastRN,T:LongInt;
 Skip:Boolean;
 Flags2Space,Flags2Letter,Flags2Num:Boolean;
 Q:LongInt;

 Procedure AddTok(E:LongInt);
 Begin
  If E>PrevEnd Then WLAdd(Out,E-PrevEnd);
  PrevEnd:=E;
 End;

 Function IsL(P:LongInt):Boolean;
 Var
  X:LongInt;
 Begin
  X:=CpAt(Cps,P,Ini,Fin);
  If X<0 Then IsL:=False
  Else If Kind=SPL_QWEN35 Then IsL:=CpIsLetter(X)or CpIsMark(X)
  Else IsL:=CpIsLetter(X);
 End;
 Function IsN(P:LongInt):Boolean;
 Var
  X:LongInt;
 Begin
  X:=CpAt(Cps,P,Ini,Fin);
  IsN:=(X>=0)and CpIsNumber(X);
 End;
 Function IsS(P:LongInt):Boolean;
 Var
  X:LongInt;
 Begin
  X:=CpAt(Cps,P,Ini,Fin);
  IsS:=(X>=0)and CpIsSpace(X);
 End;
 Function IsPunctLike(P:LongInt):Boolean;
 Var
  X:LongInt;
 Begin
  X:=CpAt(Cps,P,Ini,Fin);
  IsPunctLike:=(X>=0)and(CpIsPunct(X)or(X=36)or(X=43)or(X=60)or(X=61)or(X=62)or(X=94)or(X=124)or(X=126));
 End;
 Function IsOther(P:LongInt):Boolean;  { [^\s\p{L}\p{N}] avec drapeaux non nuls }
 Begin
  IsOther:=(CpAt(Cps,P,Ini,Fin)>=0)and not IsS(P)and not IsL(P)and not IsN(P);
 End;

Begin
 PrevEnd:=Ini;
 Pos:=Ini;
 SplitSegment:=0;
 If Kind in[SPL_NL,SPL_SPL,SPL_SPP,SPL_CJK,SPL_ENDWS,SPL_DSPUNCT,SPL_BLOOM]Then Begin
  While Pos<Fin do Begin
   Q:=0;
   Case Kind of
    SPL_NL:If(Cps[Pos]=10)or(Cps[Pos]=13)Then Q:=1;
    SPL_SPL:Begin
     If IsL(Pos)Then T:=Pos
     Else If IsS(Pos)and IsL(Pos+1)Then T:=Pos+1
     Else T:=-1;
     If T>=0 Then Begin
      Q:=T;
      While IsL(Q)do Inc(Q);
      Q:=Q-Pos;
     End;
    End;
    SPL_SPP:Begin
     If CpIsPunct(Cps[Pos])Then T:=Pos
     Else If IsS(Pos)and(Pos+1<Fin)and CpIsPunct(Cps[Pos+1])Then T:=Pos+1
     Else T:=-1;
     If T>=0 Then Begin
      Q:=T;
      While(Q<Fin)and CpIsPunct(Cps[Q])do Inc(Q);
      Q:=Q-Pos;
     End;
    End;
    SPL_CJK:Begin
     If((Cps[Pos]>=$4E00)and(Cps[Pos]<=$9FA5))or((Cps[Pos]>=$800)and(Cps[Pos]<=$4E00))or
        ((Cps[Pos]>=$AC00)and(Cps[Pos]<=$D7FF))Then Begin
      Q:=Pos;
      While(Q<Fin)and(((Cps[Q]>=$4E00)and(Cps[Q]<=$9FA5))or((Cps[Q]>=$800)and(Cps[Q]<=$4E00))or
        ((Cps[Q]>=$AC00)and(Cps[Q]<=$D7FF)))do Inc(Q);
      Q:=Q-Pos;
     End;
    End;
    SPL_ENDWS:Begin
     If IsS(Pos)Then Begin
      Q:=Pos;
      While IsS(Q)do Inc(Q);
      If Q=Fin Then Q:=Q-Pos Else Q:=0;
     End;
    End;
    SPL_DSPUNCT:Begin
     { \s?[!-/:-~！-／：-～‘-‟　-。]+ }
     If IsDsP(Cps[Pos])Then T:=Pos
     Else If IsS(Pos)and(Pos+1<Fin)and IsDsP(Cps[Pos+1])Then T:=Pos+1
     Else T:=-1;
     If T>=0 Then Begin
      Q:=T;
      While(Q<Fin)and IsDsP(Cps[Q])do Inc(Q);
      Q:=Q-Pos;
     End;
    End;
    SPL_BLOOM:Begin
     { ' ?[^(\s|.,!?…。，、।۔،)]+' }
     If Cps[Pos]=32 Then T:=Pos+1 Else T:=Pos;
     If(T<Fin)and IsBloomCh(Cps[T])Then Begin
      Q:=T;
      While(Q<Fin)and IsBloomCh(Cps[Q])do Inc(Q);
      Q:=Q-Pos;
     End;
    End;
   End;
   If Q>0 Then Begin
    AddTok(Pos);Inc(Pos,Q);AddTok(Pos);
   End
    Else Inc(Pos);
  End;
  AddTok(Fin);
  Exit;
 End;
 Case Kind of
  SPL_DIGIT1:Begin
   While Pos<Fin do Begin
    If CpIsNumber(Cps[Pos])Then Begin
     AddTok(Pos);Inc(Pos);AddTok(Pos);
    End
     Else Inc(Pos);
   End;
   AddTok(Fin);
   Exit;
  End;
  SPL_NUMS:Begin
   While Pos<Fin do Begin
    If CpIsNumber(Cps[Pos])Then Begin
     AddTok(Pos);
     While(Pos<Fin)and CpIsNumber(Cps[Pos])do Inc(Pos);
     AddTok(Pos);
    End
     Else Inc(Pos);
   End;
   AddTok(Fin);
   Exit;
  End;
  SPL_PUNCT:Begin
   While Pos<Fin do Begin
    If IsPunctLike(Pos)Then Begin
     AddTok(Pos);
     While(Pos<Fin)and IsPunctLike(Pos)do Inc(Pos);
     AddTok(Pos);
    End
     Else Inc(Pos);
   End;
   AddTok(Fin);
   Exit;
  End;
  SPL_DIG3:Begin
   While Pos<Fin do Begin
    If(Pos+2<Fin)and(Cps[Pos]>=48)and(Cps[Pos]<=57)and(Cps[Pos+1]>=48)and(Cps[Pos+1]<=57)and
      (Cps[Pos+2]>=48)and(Cps[Pos+2]<=57)Then Begin
     AddTok(Pos);Inc(Pos,3);AddTok(Pos);
    End
     Else Inc(Pos);
   End;
   AddTok(Fin);
   Exit;
  End;
 End;
 { GPT2, LLAMA3, QWEN2, QWEN35 }
 While Pos<Fin do Begin
  C:=Cps[Pos];
  { contractions }
  If(C=39)and(Pos+1<Fin)Then Begin
   If Kind=SPL_GPT2 Then CN:=CpAt(Cps,Pos+1,Ini,Fin)Else CN:=CpToLower(CpAt(Cps,Pos+1,Ini,Fin));
   If(CN=Ord('s'))or(CN=Ord('t'))or(CN=Ord('m'))or(CN=Ord('d'))Then Begin
    AddTok(Pos+2);Pos:=PrevEnd;Continue;
   End;
   If Pos+2<Fin Then Begin
    If Kind=SPL_GPT2 Then CNN:=CpAt(Cps,Pos+2,Ini,Fin)Else CNN:=CpToLower(CpAt(Cps,Pos+2,Ini,Fin));
    If((CN=Ord('r'))and(CNN=Ord('e')))or((CN=Ord('v'))and(CNN=Ord('e')))or
       ((CN=Ord('l'))and(CNN=Ord('l')))Then Begin
     AddTok(Pos+3);Pos:=PrevEnd;Continue;
    End;
   End;
  End;
  If Kind=SPL_GPT2 Then Begin
   { <espace>?\p{L}+ }
   If C=32 Then Q:=Pos+1 Else Q:=Pos;
   If IsL(Q)Then Begin
    Pos:=Q;
    While IsL(Pos)do Inc(Pos);
    AddTok(Pos);Continue;
   End;
   If IsN(Q)Then Begin
    Pos:=Q;
    While IsN(Pos)do Inc(Pos);
    AddTok(Pos);Continue;
   End;
   If IsOther(Q)Then Begin
    Pos:=Q;
    While IsOther(Pos)do Inc(Pos);
    AddTok(Pos);Continue;
   End;
   NumWs:=0;
   While IsS(Pos+NumWs)do Inc(NumWs);
   If(NumWs>1)and(CpAt(Cps,Pos+NumWs,Ini,Fin)>=0)Then Begin
    Pos:=Pos+NumWs-1;AddTok(Pos);Continue;
   End;
   If NumWs>0 Then Begin
    Pos:=Pos+NumWs;AddTok(Pos);Continue;
   End;
   Inc(Pos);AddTok(Pos);
  End
  Else Begin
   { LLAMA3, QWEN2, QWEN35 : [^\r\n\p{L}\p{N}]?\p{L}+ }
   If not((C=13)or(C=10)or CpIsNumber(C))Then Begin
    If IsL(Pos)or IsL(Pos+1)Then Begin
     Inc(Pos);
     While IsL(Pos)do Inc(Pos);
     AddTok(Pos);Continue;
    End;
   End;
   If CpIsNumber(C)Then Begin
    If Kind=SPL_LLAMA3 Then Begin
     Ini2:=Pos;
     While IsN(Pos)do Begin
      Inc(Pos);
      If Pos-Ini2>=3 Then Begin AddTok(Pos);Ini2:=Pos;End;
     End;
     AddTok(Pos);
    End
     Else Begin
      Inc(Pos);AddTok(Pos);
     End;
    Continue;
   End;
   { <espace>?[^\s\p{L}\p{N}]+[\r\n]* }
   If C=32 Then Q:=Pos+1 Else Q:=Pos;
   If IsOther(Q)and not((Kind<>SPL_QWEN35)and False)Then Begin
    Pos:=Q;
    While IsOther(Pos)and(not((Kind=SPL_QWEN35)and CpIsMark(Cps[Pos])))do Inc(Pos);
    C2:=CpAt(Cps,Pos,Ini,Fin);
    While(C2=13)or(C2=10)do Begin Inc(Pos);C2:=CpAt(Cps,Pos,Ini,Fin);End;
    AddTok(Pos);Continue;
   End;
   NumWs:=0;LastRN:=0;
   While IsS(Pos+NumWs)do Begin
    C2:=CpAt(Cps,Pos+NumWs,Ini,Fin);
    If(C2=13)or(C2=10)Then LastRN:=Pos+NumWs+1;
    Inc(NumWs);
   End;
   If LastRN>0 Then Begin
    Pos:=LastRN;AddTok(Pos);Continue;
   End;
   If(NumWs>1)and(CpAt(Cps,Pos+NumWs,Ini,Fin)>=0)Then Begin
    Pos:=Pos+NumWs-1;AddTok(Pos);Continue;
   End;
   If NumWs>0 Then Begin
    Pos:=Pos+NumWs;AddTok(Pos);Continue;
   End;
   Inc(Pos);AddTok(Pos);
  End;
 End;
 AddTok(Fin);
End;

{ Decoupe le texte en mots selon la liste de decoupeurs }
Procedure PreTokenize(Const Text:AnsiString;Const Kinds:TIntArray;Var Words:TStrArray);
Var
 Cps,Offs:TIntArray;
 Cur,Nxt:TWordList;
 K,I,J,Start:LongInt;
Begin
 SetLength(Words,0);
 Utf8ToCps(Text,Cps,Offs);
 SetLength(Cur,1);
 Cur[0]:=Length(Cps);
 If Length(Cps)=0 Then Exit;
 For K:=0 to High(Kinds)do Begin
  SetLength(Nxt,0);
  Start:=0;
  For I:=0 to High(Cur)do Begin
   SplitSegment(Cps,Start,Start+Cur[I],Kinds[K],Nxt);
   Inc(Start,Cur[I]);
  End;
  Cur:=Nxt;
 End;
 Start:=0;
 For I:=0 to High(Cur)do Begin
  AddStr(Words,Copy(Text,Offs[Start]+1,Offs[Start+Cur[I]]-Offs[Start]));
  Inc(Start,Cur[I]);
 End;
End;

{ --- file de priorite binaire pour les fusions --- }

Type
 TBigram=Record
  Key:Double;       { plus petit = prioritaire }
  Left,Right:LongInt;
  Size:LongInt;
 End;
 TBigramHeap=Record
  A:Array of TBigram;
  N:LongInt;
 End;

Function BigramLess(Const X,Y:TBigram):Boolean;
Begin
 BigramLess:=(X.Key<Y.Key)or((X.Key=Y.Key)and(X.Left<Y.Left));
End;

Procedure HeapPush(Var H:TBigramHeap;Const B:TBigram);
Var
 I,P:LongInt;
Begin
 If H.N>=Length(H.A)Then SetLength(H.A,Length(H.A)*2+16);
 I:=H.N;Inc(H.N);
 H.A[I]:=B;
 While I>0 do Begin
  P:=(I-1)shr 1;
  If BigramLess(H.A[I],H.A[P])Then Begin
   H.A[I]:=H.A[P];H.A[P]:=B;
   I:=P;
  End
   Else Break;
 End;
End;

Function HeapPop(Var H:TBigramHeap):TBigram;
Var
 I,C:LongInt;
 Last:TBigram;
Begin
 HeapPop:=H.A[0];
 Dec(H.N);
 If H.N>0 Then Begin
  Last:=H.A[H.N];
  I:=0;
  While True do Begin
   C:=2*I+1;
   If C>=H.N Then Break;
   If(C+1<H.N)and BigramLess(H.A[C+1],H.A[C])Then Inc(C);
   If BigramLess(H.A[C],Last)Then Begin
    H.A[I]:=H.A[C];I:=C;
   End
    Else Break;
  End;
  H.A[I]:=Last;
 End;
End;

Type
 TSym=Record
  Off:LongInt;   { decalage 1-base dans le texte }
  N:LongInt;
  Prev,Next:LongInt;
 End;

{ Tokenisation SPM (identique a llm_tokenizer_spm_session) }
Procedure TokenizeSPM(Const V:TVocab;Const Text:AnsiString;Var Output:TIntArray);
Var
 Sym:Array of TSym;
 NS,Offs,Len,I:LongInt;
 Heap:TBigramHeap;
 B:TBigram;

 Procedure TryAdd(L,R:LongInt);
 Var
  Tk:LongInt;
  S:AnsiString;
  Bg:TBigram;
 Begin
  If(L<0)or(R<0)Then Exit;
  S:=Copy(Text,Sym[L].Off,Sym[L].N+Sym[R].N);
  Tk:=HFind(V.TokHash,S);
  If(Tk<0)or(Tk>=V.NTokens)Then Exit;
  Bg.Key:=-V.Score[Tk];
  Bg.Left:=L;Bg.Right:=R;Bg.Size:=Sym[L].N+Sym[R].N;
  HeapPush(Heap,Bg);
 End;

 Procedure Reseg(Const Sy:TSym);
 Var
  S:AnsiString;
  Tk,J:LongInt;
 Begin
  S:=Copy(Text,Sy.Off,Sy.N);
  Tk:=HFind(V.TokHash,S);
  If Tk>=0 Then Begin AddInt(Output,Tk);Exit;End;
  For J:=1 to Sy.N do AddInt(Output,VocabByteToToken(V,Ord(S[J])));
 End;

Begin
 NS:=0;
 SetLength(Sym,Length(Text)+1);
 Offs:=1;
 While Offs<=Length(Text)do Begin
  Len:=Utf8Len(Ord(Text[Offs]));
  If Offs+Len-1>Length(Text)Then Len:=Length(Text)-Offs+1;
  Sym[NS].Off:=Offs;Sym[NS].N:=Len;
  Sym[NS].Prev:=NS-1;
  Inc(Offs,Len);
  If Offs>Length(Text)Then Sym[NS].Next:=-1 Else Sym[NS].Next:=NS+1;
  Inc(NS);
 End;
 Heap.N:=0;SetLength(Heap.A,64);
 For I:=1 to NS-1 do TryAdd(I-1,I);
 While Heap.N>0 do Begin
  B:=HeapPop(Heap);
  If(Sym[B.Left].N=0)or(Sym[B.Right].N=0)or(Sym[B.Left].N+Sym[B.Right].N<>B.Size)Then Continue;
  Inc(Sym[B.Left].N,Sym[B.Right].N);
  Sym[B.Right].N:=0;
  Sym[B.Left].Next:=Sym[B.Right].Next;
  If Sym[B.Right].Next>=0 Then Sym[Sym[B.Right].Next].Prev:=B.Left;
  TryAdd(Sym[B.Left].Prev,B.Left);
  TryAdd(B.Left,Sym[B.Left].Next);
 End;
 If NS>0 Then Begin
  I:=0;
  While I<>-1 do Begin
   Reseg(Sym[I]);
   I:=Sym[I].Next;
  End;
 End;
End;

{ Tokenisation BPE d'un mot deja decoupe (octets -> unicode puis fusions) }
Procedure TokenizeBPEWord(Const V:TVocab;Const WordRaw:AnsiString;ByteEncode:Boolean;Var Output:TIntArray);
Var
 Word,S,Key:AnsiString;
 I,Tk,J,NS,Offs,Len,R:LongInt;
 Sym:Array of TSym;
 Heap:TBigramHeap;
 B:TBigram;

 Procedure TryAdd(L,Rg:LongInt);
 Var
  Rk:LongInt;
  Bg:TBigram;
 Begin
  If(L<0)or(Rg<0)Then Exit;
  Key:=Copy(Word,Sym[L].Off,Sym[L].N)+#1+Copy(Word,Sym[Rg].Off,Sym[Rg].N);
  Rk:=HFind(V.MergeHash,Key);
  If Rk<0 Then Exit;
  Bg.Key:=Rk;Bg.Left:=L;Bg.Right:=Rg;Bg.Size:=Sym[L].N+Sym[Rg].N;
  HeapPush(Heap,Bg);
 End;

Begin
 If ByteEncode Then Begin
  Word:='';
  For I:=1 to Length(WordRaw)do Word:=Word+ByteToUniStr[Ord(WordRaw[I])];
 End
  Else Word:=WordRaw;
 If Word='' Then Exit;
 If V.IgnoreMerges Then Begin
  Tk:=HFind(V.TokHash,Word);
  If Tk>=0 Then Begin AddInt(Output,Tk);Exit;End;
 End;
 NS:=0;
 SetLength(Sym,Length(Word)+1);
 Offs:=1;
 While Offs<=Length(Word)do Begin
  Len:=Utf8Len(Ord(Word[Offs]));
  If Offs+Len-1>Length(Word)Then Len:=Length(Word)-Offs+1;
  Sym[NS].Off:=Offs;Sym[NS].N:=Len;
  Sym[NS].Prev:=NS-1;
  Inc(Offs,Len);
  If Offs>Length(Word)Then Sym[NS].Next:=-1 Else Sym[NS].Next:=NS+1;
  Inc(NS);
 End;
 Heap.N:=0;SetLength(Heap.A,64);
 For I:=1 to NS-1 do TryAdd(I-1,I);
 While Heap.N>0 do Begin
  B:=HeapPop(Heap);
  If(Sym[B.Left].N=0)or(Sym[B.Right].N=0)or(Sym[B.Left].N+Sym[B.Right].N<>B.Size)Then Continue;
  Inc(Sym[B.Left].N,Sym[B.Right].N);
  Sym[B.Right].N:=0;
  Sym[B.Left].Next:=Sym[B.Right].Next;
  If Sym[B.Right].Next>=0 Then Sym[Sym[B.Right].Next].Prev:=B.Left;
  TryAdd(Sym[B.Left].Prev,B.Left);
  TryAdd(B.Left,Sym[B.Left].Next);
 End;
 I:=0;
 While I<>-1 do Begin
  If Sym[I].N>0 Then Begin
   S:=Copy(Word,Sym[I].Off,Sym[I].N);
   Tk:=HFind(V.TokHash,S);
   If Tk<0 Then Begin
    For J:=1 to Length(S)do Begin
     If ByteEncode Then R:=HFind(V.TokHash,Chr(Ord(S[J])))
     Else R:=HFind(V.TokHash,'<0x'+HexStr2(Ord(S[J]))+'>');
     If R>=0 Then AddInt(Output,R);
    End;
   End
    Else AddInt(Output,Tk);
  End;
  I:=Sym[I].Next;
 End;
End;

Type
 TFrag=Record
  IsTok:Boolean;
  Tok:LongInt;
  Txt:AnsiString;
 End;
 TFragArr=Array of TFrag;

Procedure FragAdd(Var A:TFragArr;Var N:LongInt;IsTok:Boolean;Tok:LongInt;Const Txt:AnsiString);
Begin
 If N>=Length(A)Then SetLength(A,Length(A)*2+8);
 A[N].IsTok:=IsTok;A[N].Tok:=Tok;A[N].Txt:=Txt;
 Inc(N);
End;

Var
 PreKinds:TIntArray;

{ Equivalent de llama_vocab::tokenize }
Function VocabTokenize(Const V:TVocab;Const Raw:AnsiString;AddSpecial,ParseSpecial:Boolean):TIntArray;
Var
 Out:TIntArray;
 Frags,NewF:TFragArr;
 NF,NN,I,J,K,P,Q:LongInt;
 Sp:LongInt;
 SpT:AnsiString;
 Txt:AnsiString;
 IsPrevSpecial:Boolean;
 Words:TStrArray;
 Kinds:TIntArray;
Begin
 SetLength(Out,0);
 NF:=0;
 SetLength(Frags,0);
 If Raw<>'' Then Begin
  FragAdd(Frags,NF,False,0,Raw);
  For K:=0 to High(V.Specials)do Begin
   Sp:=V.Specials[K];
   If(not ParseSpecial)and((V.Attr[Sp]and(TA_CONTROL or TA_UNKNOWN))<>0)Then Continue;
   SpT:=V.Text[Sp];
   If SpT='' Then Continue;
   NN:=0;
   SetLength(NewF,0);
   For I:=0 to NF-1 do Begin
    If Frags[I].IsTok Then Begin
     FragAdd(NewF,NN,True,Frags[I].Tok,'');
     Continue;
    End;
    Txt:=Frags[I].Txt;
    P:=1;
    While True do Begin
     Q:=PosFrom(SpT,Txt,P);
     If Q=0 Then Begin
      If P<=Length(Txt)Then FragAdd(NewF,NN,False,0,Copy(Txt,P,Length(Txt)-P+1));
      Break;
     End;
     If Q>P Then FragAdd(NewF,NN,False,0,Copy(Txt,P,Q-P));
     FragAdd(NewF,NN,True,Sp,'');
     P:=Q+Length(SpT);
    End;
   End;
   Frags:=NewF;NF:=NN;
  End;
 End;
 Case V.VType of
  VT_SPM:Begin
   IsPrevSpecial:=True;
   If AddSpecial and V.AddBOS and(V.BOS>=0)Then Begin
    AddInt(Out,V.BOS);IsPrevSpecial:=True;
   End;
   For I:=0 to NF-1 do Begin
    If not Frags[I].IsTok Then Begin
     Txt:=Frags[I].Txt;
     If V.AddSpacePrefix and IsPrevSpecial Then Txt:=' '+Txt;
     Txt:=ReplaceAll(Txt,' ',#$E2#$96#$81);
     TokenizeSPM(V,Txt,Out);
     IsPrevSpecial:=False;
    End
     Else Begin
      AddInt(Out,Frags[I].Tok);
      IsPrevSpecial:=True;
     End;
   End;
   If AddSpecial and V.AddEOS and(V.EOS>=0)Then AddInt(Out,V.EOS);
  End;
  VT_BPE:Begin
   If AddSpecial and V.AddBOS and(V.BOS>=0)Then AddInt(Out,V.BOS);
   For I:=0 to NF-1 do Begin
    If not Frags[I].IsTok Then Begin
     Txt:=Frags[I].Txt;
     If V.EscapeWs Then Txt:=ReplaceAll(Txt,' ',#$E2#$96#$81);
     PreTokenize(Txt,PreKinds,Words);
     For J:=0 to High(Words)do TokenizeBPEWord(V,Words[J],True,Out);
    End
     Else AddInt(Out,Frags[I].Tok);
   End;
   If AddSpecial and V.AddEOS and(V.EOS>=0)Then AddInt(Out,V.EOS);
  End;
 End;
 VocabTokenize:=Out;
End;

Procedure SetPreKinds(PreType:LongInt);
Begin
 SetLength(PreKinds,0);
 Case PreType of
  PRE_LLAMA3:AddInt(PreKinds,SPL_LLAMA3);
  PRE_QWEN2:AddInt(PreKinds,SPL_QWEN2);
  PRE_QWEN35:AddInt(PreKinds,SPL_QWEN35);
  PRE_GPT2:AddInt(PreKinds,SPL_GPT2);
  PRE_SMOLLM:Begin AddInt(PreKinds,SPL_DIGIT1);AddInt(PreKinds,SPL_GPT2);End;
  PRE_FALCON:Begin AddInt(PreKinds,SPL_PUNCT);AddInt(PreKinds,SPL_GPT2);AddInt(PreKinds,SPL_DIG3);End;
  PRE_DEEPSEEK_LLM:Begin
   AddInt(PreKinds,SPL_NL);AddInt(PreKinds,SPL_SPL);AddInt(PreKinds,SPL_DSPUNCT);
   AddInt(PreKinds,SPL_ENDWS);AddInt(PreKinds,SPL_CJK);AddInt(PreKinds,SPL_NUMS);
  End;
  PRE_DEEPSEEK_CODER:Begin
   AddInt(PreKinds,SPL_NL);AddInt(PreKinds,SPL_SPL);AddInt(PreKinds,SPL_SPP);
   AddInt(PreKinds,SPL_CJK);AddInt(PreKinds,SPL_DIGIT1);
  End;
  PRE_BLOOM:AddInt(PreKinds,SPL_BLOOM);
  PRE_VIKING:Begin AddInt(PreKinds,SPL_BLOOM);AddInt(PreKinds,SPL_DIGIT1);End;
  Else Begin
   AddInt(PreKinds,SPL_PUNCT);AddInt(PreKinds,SPL_GPT2);AddInt(PreKinds,SPL_NUMS);AddInt(PreKinds,SPL_DIG3);
  End;
 End;
End;

Function PreTypeFromName(Const N:AnsiString;Var Known:Boolean):LongInt;
Begin
 Known:=True;
 If(N='')or(N='default')Then PreTypeFromName:=PRE_DEFAULT
 Else If(N='llama3')or(N='llama-v3')or(N='llama-bpe')or(N='falcon3')or(N='falcon-h1')or(N='pixtral')or
    (N='midm-2.0')or(N='lfm2')or(N='jina-v5-nano')or(N='dbrx')or(N='smaug-bpe')or(N='chatglm-bpe')or
    (N='glm4')or(N='glm5')Then PreTypeFromName:=PRE_LLAMA3
 Else If(N='qwen2')or(N='deepseek-r1-qwen')or(N='kormo')or(N='f2llmv2')or(N='stablelm2')or(N='hunyuan')or
    (N='solar-open')or(N='megrez')Then PreTypeFromName:=PRE_QWEN2
 Else If N='qwen35' Then PreTypeFromName:=PRE_QWEN35
 Else If(N='gpt-2')or(N='phi-2')or(N='jina-es')or(N='jina-de')or(N='gigachat')or(N='jina-v2-es')or
    (N='jina-v2-de')or(N='a.x-4.0')or(N='mellum')or(N='modern-bert')or(N='mpt')or(N='olmo')or(N='jais')or
    (N='trillion')or(N='granite-docling')or(N='exaone4')or(N='jina-v1-en')or(N='jina-v2-code')or
    (N='roberta-bpe')Then PreTypeFromName:=PRE_GPT2
 Else If(N='starcoder')or(N='refact')or(N='command-r')or(N='smollm')or(N='codeshell')or(N='exaone')or
    (N='minerva-7b')or(N='mellum2')Then PreTypeFromName:=PRE_SMOLLM
 Else If N='falcon' Then PreTypeFromName:=PRE_FALCON
 Else If(N='deepseek-llm')Then PreTypeFromName:=PRE_DEEPSEEK_LLM
 Else If(N='deepseek-coder')Then PreTypeFromName:=PRE_DEEPSEEK_CODER
 Else If(N='poro-chat')or(N='bloom')or(N='gpt3-finnish')Then PreTypeFromName:=PRE_BLOOM
 Else If N='viking' Then PreTypeFromName:=PRE_VIKING
 Else If(N='gpt-4o')or(N='llama4')or(N='kanana2')or(N='talkie')or(N='tekken')Then PreTypeFromName:=PRE_LLAMA3
 Else Begin
  Known:=False;
  PreTypeFromName:=PRE_DEFAULT;
 End;
End;

Procedure LoadVocab(Var V:TVocab;Const G:TGGUF);
Var
 TI,SI,YI,MI,I,J,K,P:LongInt;
 Known:Boolean;
 T:AnsiString;
 Tmp:TIntArray;
 N:LongInt;
 Cnt:LongInt;
 SpSet:TBoolArray;

 Function GetId(Const Key:AnsiString;Def:LongInt):LongInt;
 Var
  X:Int64;
 Begin
  X:=KVInt(G,Key,Def);
  If(X<0)or(X>=V.NTokens)Then Begin
   If KVHas(G,Key)and(X>=V.NTokens)Then
    LogWrn('avertissement : '+Key+' = '+IStr(X)+' hors vocabulaire, ignoré'+#10);
   If X>=V.NTokens Then GetId:=-1 Else GetId:=Def;
  End
   Else GetId:=X;
 End;

 Procedure MarkEog(Id:LongInt);
 Begin
  If(Id>=0)and(Id<V.NTokens)Then V.EOG[Id]:=True;
 End;

Begin
 V.Model:=KVStr(G,'tokenizer.ggml.model','');
 V.PreName:=KVStr(G,'tokenizer.ggml.pre','');
 V.ChatTemplate:=KVStr(G,'tokenizer.chat_template','');
 V.VType:=VT_NONE;
 V.BOS:=-1;V.EOS:=-1;V.EOT:=-1;V.EOM:=-1;V.UNK:=-1;V.SEP:=-1;V.PAD:=-1;V.MASK:=-1;V.NL:=-1;
 V.FimPre:=-1;V.FimSuf:=-1;V.FimMid:=-1;V.FimPad:=-1;V.FimRep:=-1;V.FimSep:=-1;
 V.AddBOS:=False;V.AddEOS:=False;V.AddSep:=False;V.AddSpacePrefix:=False;
 V.RemoveExtraWs:=False;V.EscapeWs:=True;V.CleanSpaces:=False;V.IgnoreMerges:=False;
 V.PreType:=PRE_DEFAULT;
 V.NTokens:=0;
 If(V.Model='no_vocab')or(V.Model='none')or(V.Model='')Then Begin
  Fatal('le modèle ne contient pas de vocabulaire (tokenizer.ggml.model absent)');
 End;
 TI:=KVFind(G,'tokenizer.ggml.tokens');
 If(TI<0)or(G.KV[TI].Typ<>GT_ARRAY)or(G.KV[TI].ArrTyp<>GT_STRING)Then
  Fatal('vocabulaire introuvable dans le fichier modèle (tokenizer.ggml.tokens)');
 V.NTokens:=Length(G.KV[TI].SA);
 If V.Model='llama' Then Begin
  V.VType:=VT_SPM;
  V.BOS:=1;V.EOS:=2;V.UNK:=0;
  V.AddSpacePrefix:=True;V.AddBOS:=True;V.AddEOS:=False;V.EscapeWs:=True;
 End
  Else If(V.Model='gpt2')Then Begin
   V.VType:=VT_BPE;
   V.BOS:=11;V.EOS:=11;
   V.AddSpacePrefix:=False;V.EscapeWs:=False;V.CleanSpaces:=True;
   V.PreType:=PreTypeFromName(V.PreName,Known);
   If V.PreName='' Then LogWrn('avertissement : pré-tokeniseur absent, utilisation de ''default'''+#10)
   Else If not Known Then
    LogWrn('avertissement : pré-tokeniseur inconnu ('+V.PreName+'), approximation utilisée'+#10);
   If(V.PreName='llama-bpe')or(V.PreName='llama3')Then V.IgnoreMerges:=True;
   If(V.PreName='tekken')or(V.PreName='gpt-4o')Then V.IgnoreMerges:=True;
   If(V.PreName='qwen2')Then V.IgnoreMerges:=False;
   MI:=KVFind(G,'tokenizer.ggml.merges');
   If MI<0 Then Fatal('fusions BPE introuvables dans le fichier modèle (tokenizer.ggml.merges)');
   HInit(V.MergeHash,Length(G.KV[MI].SA));
   For I:=0 to High(G.KV[MI].SA)do Begin
    T:=G.KV[MI].SA[I];
    P:=PosFrom(' ',T,2);
    If P>0 Then Begin
     HPut(V.MergeHash,Copy(T,1,P-1)+#1+Copy(T,P+1,Length(T)-P),I);
    End;
   End;
  End
  Else Fatal('type de tokeniseur non supporté : '+V.Model);
 V.IgnoreMerges:=KVInt(G,'tokenizer.ggml.ignore_merges',Ord(V.IgnoreMerges))<>0;
 SetPreKinds(V.PreType);
 { options }
 If KVHas(G,'tokenizer.ggml.add_space_prefix')Then
  V.AddSpacePrefix:=KVInt(G,'tokenizer.ggml.add_space_prefix',0)<>0;
 If KVHas(G,'tokenizer.ggml.remove_extra_whitespaces')Then
  V.RemoveExtraWs:=KVInt(G,'tokenizer.ggml.remove_extra_whitespaces',0)<>0;
 { jetons }
 SetLength(V.Text,V.NTokens);
 SetLength(V.Score,V.NTokens);
 SetLength(V.Attr,V.NTokens);
 SetLength(V.EOG,V.NTokens);
 FillChar(V.EOG[0],V.NTokens,0);
 HInit(V.TokHash,V.NTokens);
 SI:=KVFind(G,'tokenizer.ggml.scores');
 YI:=KVFind(G,'tokenizer.ggml.token_type');
 For I:=0 to V.NTokens-1 do Begin
  T:=G.KV[TI].SA[I];
  If T='' Then T:='[EMPTY_'+IStr(I)+']';
  V.Text[I]:=T;
  HPut(V.TokHash,T,I);
  If Length(T)>V.MaxTokLen Then V.MaxTokLen:=Length(T);
  If(SI>=0)and(I<Length(G.KV[SI].FA))Then V.Score[I]:=G.KV[SI].FA[I]
  Else If(SI>=0)and(I<Length(G.KV[SI].IA))Then V.Score[I]:=G.KV[SI].IA[I]
  Else V.Score[I]:=0;
  V.Attr[I]:=TA_NORMAL;
  If(YI>=0)and(I<Length(G.KV[YI].IA))Then Begin
   Case G.KV[YI].IA[I]of
    1:V.Attr[I]:=TA_NORMAL;
    2:V.Attr[I]:=TA_UNKNOWN;
    3:V.Attr[I]:=TA_CONTROL;
    4:V.Attr[I]:=TA_USER_DEFINED;
    5:V.Attr[I]:=TA_UNUSED;
    6:V.Attr[I]:=TA_BYTE;
    Else V.Attr[I]:=TA_UNDEFINED;
   End;
  End;
 End;
 { jetons octets }
 For I:=0 to 255 do V.ByteTok[I]:=-1;
 For I:=0 to 255 do Begin
  J:=HFind(V.TokHash,'<0x'+HexStr2(I)+'>');
  If J>=0 Then V.ByteTok[I]:=J;
 End;
 { identifiants speciaux }
 V.BOS:=GetId('tokenizer.ggml.bos_token_id',V.BOS);
 V.EOS:=GetId('tokenizer.ggml.eos_token_id',V.EOS);
 V.EOT:=GetId('tokenizer.ggml.eot_token_id',-1);
 V.EOM:=GetId('tokenizer.ggml.eom_token_id',-1);
 V.UNK:=GetId('tokenizer.ggml.unknown_token_id',V.UNK);
 V.SEP:=GetId('tokenizer.ggml.seperator_token_id',-1);
 V.PAD:=GetId('tokenizer.ggml.padding_token_id',-1);
 V.MASK:=GetId('tokenizer.ggml.mask_token_id',-1);
 V.FimPre:=GetId('tokenizer.ggml.fim_pre_token_id',-1);
 V.FimSuf:=GetId('tokenizer.ggml.fim_suf_token_id',-1);
 V.FimMid:=GetId('tokenizer.ggml.fim_mid_token_id',-1);
 V.FimPad:=GetId('tokenizer.ggml.fim_pad_token_id',-1);
 V.FimRep:=GetId('tokenizer.ggml.fim_rep_token_id',-1);
 V.FimSep:=GetId('tokenizer.ggml.fim_sep_token_id',-1);
 If KVHas(G,'tokenizer.ggml.add_bos_token')Then V.AddBOS:=KVInt(G,'tokenizer.ggml.add_bos_token',0)<>0;
 If KVHas(G,'tokenizer.ggml.add_eos_token')Then V.AddEOS:=KVInt(G,'tokenizer.ggml.add_eos_token',0)<>0;
 If KVHas(G,'tokenizer.ggml.add_sep_token')Then V.AddSep:=KVInt(G,'tokenizer.ggml.add_sep_token',0)<>0;
 { jetons de fin de generation (EOG) }
 For I:=0 to V.NTokens-1 do Begin
  T:=V.Text[I];
  If(T='<|eot_id|>')or(T='<|im_end|>')or(T='<|end|>')or(T='<|return|>')or(T='<|call|>')or
    (T='<|flush|>')or(T='<|calls|>')or(T='<end_of_turn>')or(T='<|endoftext|>')or(T='</s>')or
    (T='<|eom_id|>')or(T='<EOT>')or(T='_<EOT>')or(T='[EOT]')or(T='[EOS]')or(T='<|end_of_text|>')or
    (T='<end_of_utterance>')or(T='<eos>')or(T='<turn|>')or(T='<|tool_response>')or
    (T='<｜end▁of▁sentence｜>')or(T='[e~[')Then Begin
   V.EOG[I]:=True;
   V.Attr[I]:=V.Attr[I]or TA_CONTROL;
  End;
  If V.EOT<0 Then Begin
   If(T='<|eot_id|>')or(T='<|im_end|>')or(T='<|end|>')or(T='<end_of_turn>')or(T='<|endoftext|>')or
     (T='<|end_of_text|>')or(T='<EOT>')or(T='_<EOT>')or(T='[EOT]')or(T='<end_of_utterance>')Then
    V.EOT:=I;
  End;
  If V.FimPre<0 Then
   If(T='<|fim_prefix|>')or(T='<fim-prefix>')or(T='<fim_prefix>')or(T='<PRE>')or(T='▁<PRE>')Then V.FimPre:=I;
  If V.FimSuf<0 Then
   If(T='<|fim_suffix|>')or(T='<fim-suffix>')or(T='<fim_suffix>')or(T='<SUF>')or(T='▁<SUF>')Then V.FimSuf:=I;
  If V.FimMid<0 Then
   If(T='<|fim_middle|>')or(T='<fim-middle>')or(T='<fim_middle>')or(T='<MID>')or(T='▁<MID>')Then V.FimMid:=I;
 End;
 MarkEog(V.EOS);MarkEog(V.EOT);MarkEog(V.EOM);
 MarkEog(V.FimPad);MarkEog(V.FimRep);MarkEog(V.FimSep);
 { jetons speciaux tries par longueur decroissante (tri par comptage) }
 Cnt:=0;
 For I:=0 to V.NTokens-1 do
  If(V.Attr[I]and(TA_CONTROL or TA_USER_DEFINED or TA_UNKNOWN))<>0 Then Inc(Cnt);
 SetLength(V.Specials,Cnt);
 SetLength(Tmp,V.MaxTokLen+2);
 For I:=0 to V.MaxTokLen+1 do Tmp[I]:=0;
 For I:=0 to V.NTokens-1 do
  If(V.Attr[I]and(TA_CONTROL or TA_USER_DEFINED or TA_UNKNOWN))<>0 Then
   Inc(Tmp[Length(V.Text[I])]);
 { positions de depart : longueurs les plus grandes d'abord }
 P:=0;
 For K:=V.MaxTokLen downto 0 do Begin
  J:=Tmp[K];Tmp[K]:=P;Inc(P,J);
 End;
 For I:=0 to V.NTokens-1 do
  If(V.Attr[I]and(TA_CONTROL or TA_USER_DEFINED or TA_UNKNOWN))<>0 Then Begin
   K:=Length(V.Text[I]);
   V.Specials[Tmp[K]]:=I;
   Inc(Tmp[K]);
  End;
 { jeton de saut de ligne }
 If V.VType=VT_SPM Then Begin
  V.NL:=V.ByteTok[10];
  If V.NL<0 Then V.NL:=V.PAD;
 End
  Else Begin
   Tmp:=VocabTokenize(V,#10,False,False);
   If Length(Tmp)>0 Then V.NL:=Tmp[0]Else V.NL:=V.PAD;
  End;
End;

{ ------------------------------------------------------------------ }
{ Modele : hyperparametres, tenseurs                                  }
{ ------------------------------------------------------------------ }

Const
 AR_LLAMA=1; AR_QWEN2=2; AR_QWEN3=3; AR_PHI3=4; AR_GEMMA=5; AR_GEMMA2=6;
 AR_GEMMA3=7; AR_GRANITE=8; AR_QWEN3MOE=9; AR_QWEN2MOE=10;

 RS_NONE=0; RS_LINEAR=1; RS_YARN=2; RS_LONGROPE=3;

Type
 TLayer=Record
  AttnNorm,FfnNorm,QNorm,KNorm,PostAttnNorm,PostFfnNorm:TSingleArray;
  Bq,Bk,Bv,Bo:TSingleArray;
  Wq,Wk,Wv,Wo,Wqkv,FfnGate,FfnUp,FfnDown:LongInt;   { index dans G.T, -1 si absent }
  GateInp,GateExps,UpExps,DownExps:LongInt;
  GateInpShexp,GateShexp,UpShexp,DownShexp:LongInt;
  IsSWA:Boolean;
 End;

 TModel=Record
  G:TGGUF;
  V:TVocab;
  Arch:AnsiString;
  ArchId:LongInt;
  Name:AnsiString;
  NEmbd,NLayer,NHead,NHeadKV,NFF,HeadK,HeadV,NRot,NCtxTrain,NVocab:LongInt;
  NExpert,NExpertUsed,NFFExp,NFFShexp:LongInt;
  ExpertWScale:Single;
  NormEps:Single;
  RopeNeox:Boolean;
  RopeBase,RopeBaseSWA:Single;
  RopeScaleTrain,RopeScaleSWA:Single;
  RopeScalingType:LongInt;
  NCtxOrigYarn:LongInt;
  RopeAttnFactor:Single;
  YarnLogMul:Single;
  YarnExtFactor,YarnBetaFast,YarnBetaSlow:Single;
  EmbScale,ResidualScale,LogitScale,AttnScale:Single;
  AttnSoftCap,FinalSoftCap:Single;
  NSwa:LongInt;
  GeluFFN:Boolean;
  UseQKNorm:Boolean;
  TokEmbd,Output,OutputIdx:LongInt;
  OutputNorm:TSingleArray;
  OutputBias:TSingleArray;
  RopeFreqs,RopeLong,RopeShort:TSingleArray;
  Layers:Array of TLayer;
  FileType:AnsiString;
  NElements:Int64;
  NBytes:Int64;
 End;

Type
 TOverride=Record
  Key,Typ,Val:AnsiString;
 End;

Var
 KVOverrides:Array of TOverride;

Function LayerTensor(Const G:TGGUF;L:LongInt;Const Part:AnsiString):LongInt;
Begin
 LayerTensor:=FindTensor(G,'blk.'+IStr(L)+'.'+Part);
End;

Procedure LoadVec(Const G:TGGUF;Idx:LongInt;Var Dst:TSingleArray);
Var
 N:Int64;
Begin
 SetLength(Dst,0);
 If Idx<0 Then Exit;
 N:=TensorElems(G.T[Idx]);
 SetLength(Dst,N);
 If N>0 Then DequantRow(G.T[Idx].Typ,G.T[Idx].Data,@Dst[0],N);
End;

Function ArchIdFromName(Const A:AnsiString):LongInt;
Begin
 If A='llama' Then ArchIdFromName:=AR_LLAMA
 Else If A='qwen2' Then ArchIdFromName:=AR_QWEN2
 Else If A='qwen3' Then ArchIdFromName:=AR_QWEN3
 Else If A='qwen3moe' Then ArchIdFromName:=AR_QWEN3MOE
 Else If A='phi3' Then ArchIdFromName:=AR_PHI3
 Else If A='gemma' Then ArchIdFromName:=AR_GEMMA
 Else If A='gemma2' Then ArchIdFromName:=AR_GEMMA2
 Else If A='gemma3' Then ArchIdFromName:=AR_GEMMA3
 Else If A='granite' Then ArchIdFromName:=AR_GRANITE
 Else ArchIdFromName:=0;
End;

Function FileTypeName(Ft:LongInt):AnsiString;
Begin
 Case Ft of
  0:FileTypeName:='all F32';
  1:FileTypeName:='F16';
  2:FileTypeName:='Q4_0';
  3:FileTypeName:='Q4_1';
  7:FileTypeName:='Q8_0';
  8:FileTypeName:='Q5_0';
  9:FileTypeName:='Q5_1';
  10:FileTypeName:='Q2_K - Medium';
  11:FileTypeName:='Q3_K - Small';
  12:FileTypeName:='Q3_K - Medium';
  13:FileTypeName:='Q3_K - Large';
  14:FileTypeName:='Q4_K - Small';
  15:FileTypeName:='Q4_K - Medium';
  16:FileTypeName:='Q5_K - Small';
  17:FileTypeName:='Q5_K - Medium';
  18:FileTypeName:='Q6_K';
  25:FileTypeName:='IQ4_NL';
  30:FileTypeName:='IQ4_XS';
  32:FileTypeName:='BF16';
  Else FileTypeName:='inconnu';
 End;
End;

{ Detecte un nom de fichier de la forme xxx-00001-of-00003.gguf }
Function SplitFileNames(Const Path:AnsiString;Var Names:TStrArray):Boolean;
Var
 P,N,I:LongInt;
 Base,Pre:AnsiString;
 NumS:AnsiString;
 Cnt,Cur:Int64;
Begin
 SetLength(Names,1);
 Names[0]:=Path;
 SplitFileNames:=False;
 If not EndsWith(Path,'.gguf')Then Exit;
 Base:=Copy(Path,1,Length(Path)-5);
 P:=Length(Base)-12;     { -00001-of-00003 }
 If P<1 Then Exit;
 If(Copy(Base,P,1)<>'-')or(Copy(Base,P+6,4)<>'-of-')Then Exit;
 If not ParseInt(Copy(Base,P+1,5),Cur)Then Exit;
 If not ParseInt(Copy(Base,P+10,5),Cnt)Then Exit;
 If(Cnt<2)or(Cnt>9999)Then Exit;
 Pre:=Copy(Base,1,P-1);
 SetLength(Names,Cnt);
 For I:=1 to Cnt do Begin
  NumS:=IStr(I);
  While Length(NumS)<5 do NumS:='0'+NumS;
  Names[I-1]:=Pre+'-'+NumS+'-of-'+Copy(Base,P+10,5)+'.gguf';
 End;
 SplitFileNames:=True;
End;

Procedure LoadModelMeta(Const Path:AnsiString;Var M:TModel);
Var
 Names:TStrArray;
 I:LongInt;
Begin
 SetLength(M.G.KV,0);SetLength(M.G.T,0);
 SplitFileNames(Path,Names);
 M.G.Files:=Names;
 If not FileExistsP(Names[0])Then Fatal('le fichier modèle est introuvable : '+Names[0]);
 For I:=0 to High(Names)do Begin
  If not FileExistsP(Names[I])Then Fatal('fichier du modèle fractionné introuvable : '+Names[I]);
  ParseGGUFHeader(Names[I],I,M.G,I=0);
 End;
End;

Procedure LoadHParams(Var M:TModel);
Var
 A:AnsiString;
 G:^TGGUF;
 I:LongInt;
 Pat:Int64;
 ScaleT:AnsiString;
 RopeFactor:Double;
 TmpIdx:LongInt;
 Known:Boolean;
Begin
 G:=@M.G;
 M.Arch:=KVStr(G^,'general.architecture','');
 M.Name:=KVStr(G^,'general.name','');
 M.ArchId:=ArchIdFromName(M.Arch);
 If M.ArchId=0 Then
  Fatal('architecture de modèle non supportée : '''+M.Arch+''' (supportées : llama, qwen2, qwen3, '+
        'qwen3moe, phi3, gemma, gemma2, gemma3, granite)');
 A:=M.Arch+'.';
 M.NCtxTrain:=KVInt(G^,A+'context_length',0);
 M.NEmbd:=KVInt(G^,A+'embedding_length',0);
 M.NLayer:=KVInt(G^,A+'block_count',0);
 If(M.NEmbd<=0)or(M.NLayer<=0)Then Fatal('métadonnées du modèle invalides (embedding_length/block_count)');
 M.NFF:=KVIntAt(G^,A+'feed_forward_length',0,0);
 M.NHead:=KVIntAt(G^,A+'attention.head_count',0,0);
 If M.NHead<=0 Then Fatal('métadonnée '+A+'attention.head_count absente');
 M.NHeadKV:=KVIntAt(G^,A+'attention.head_count_kv',0,M.NHead);
 If M.NHeadKV<=0 Then M.NHeadKV:=M.NHead;
 M.NormEps:=KVFloat(G^,A+'attention.layer_norm_rms_epsilon',1e-6);
 M.HeadK:=KVInt(G^,A+'attention.key_length',M.NEmbd div M.NHead);
 M.HeadV:=KVInt(G^,A+'attention.value_length',M.HeadK);
 M.NRot:=KVInt(G^,A+'rope.dimension_count',M.HeadK);
 M.NExpert:=KVInt(G^,A+'expert_count',0);
 M.NExpertUsed:=KVInt(G^,A+'expert_used_count',0);
 M.NFFExp:=KVInt(G^,A+'expert_feed_forward_length',M.NFF);
 M.NFFShexp:=KVInt(G^,A+'expert_shared_feed_forward_length',0);
 M.ExpertWScale:=KVFloat(G^,A+'expert_weights_scale',0);
 M.RopeBase:=KVFloat(G^,A+'rope.freq_base',10000.0);
 M.RopeBaseSWA:=KVFloat(G^,A+'rope.freq_base_swa',10000.0);
 M.NCtxOrigYarn:=KVInt(G^,A+'rope.scaling.original_context_length',M.NCtxTrain);
 ScaleT:=KVStr(G^,A+'rope.scaling.type','linear');
 If ScaleT='none' Then M.RopeScalingType:=RS_NONE
 Else If ScaleT='yarn' Then M.RopeScalingType:=RS_YARN
 Else If ScaleT='longrope' Then M.RopeScalingType:=RS_LONGROPE
 Else M.RopeScalingType:=RS_LINEAR;
 RopeFactor:=KVFloat(G^,A+'rope.scaling.factor',0);
 If RopeFactor=0 Then RopeFactor:=KVFloat(G^,A+'rope.scale_linear',0);
 If RopeFactor=0 Then M.RopeScaleTrain:=1.0 Else M.RopeScaleTrain:=1.0/RopeFactor;
 M.RopeScaleSWA:=1.0;
 M.RopeAttnFactor:=KVFloat(G^,A+'rope.scaling.attn_factor',1.0);
 M.YarnLogMul:=KVFloat(G^,A+'rope.scaling.yarn_log_multiplier',0);
 M.YarnExtFactor:=-1;
 M.YarnBetaFast:=32;M.YarnBetaSlow:=1;
 M.EmbScale:=1;M.ResidualScale:=1;M.LogitScale:=0;M.AttnScale:=0;
 M.AttnSoftCap:=0;M.FinalSoftCap:=0;
 M.NSwa:=0;
 M.GeluFFN:=False;
 M.UseQKNorm:=False;
 M.RopeNeox:=True;
 Case M.ArchId of
  AR_LLAMA:M.RopeNeox:=False;
  AR_GRANITE:Begin
   M.RopeNeox:=False;
   M.EmbScale:=KVFloat(G^,A+'embedding_scale',0);
   If M.EmbScale=0 Then M.EmbScale:=1;
   M.ResidualScale:=KVFloat(G^,A+'residual_scale',0);
   If M.ResidualScale=0 Then M.ResidualScale:=1;
   M.LogitScale:=KVFloat(G^,A+'logit_scale',0);
   M.AttnScale:=KVFloat(G^,A+'attention.scale',0);
  End;
  AR_QWEN3,AR_QWEN3MOE:M.UseQKNorm:=True;
  AR_GEMMA,AR_GEMMA2,AR_GEMMA3:Begin
   M.GeluFFN:=True;
   M.EmbScale:=Sqrt(M.NEmbd);
  End;
 End;
 If M.ArchId in[AR_GEMMA2,AR_GEMMA3]Then Begin
  M.NSwa:=KVInt(G^,A+'attention.sliding_window',0);
  If M.ArchId=AR_GEMMA2 Then Begin
   If M.NSwa=0 Then M.NSwa:=4096;
   M.AttnSoftCap:=KVFloat(G^,A+'attn_logit_softcapping',0);
   M.FinalSoftCap:=KVFloat(G^,A+'final_logit_softcapping',0);
   Pat:=2;
  End
   Else Begin
    M.FinalSoftCap:=KVFloat(G^,A+'final_logit_softcapping',0);
    Pat:=6;
    M.UseQKNorm:=True;
   End;
  Pat:=KVInt(G^,A+'attention.sliding_window_pattern',Pat);
  SetLength(M.Layers,M.NLayer);
  For I:=0 to M.NLayer-1 do Begin
   If M.NSwa>0 Then Begin
    If Pat=0 Then M.Layers[I].IsSWA:=True
    Else M.Layers[I].IsSWA:=(I mod Pat)<(Pat-1);
   End
    Else M.Layers[I].IsSWA:=False;
  End;
  { echelle d'attention }
  If((M.ArchId=AR_GEMMA2)and(M.NLayer=46))or((M.ArchId=AR_GEMMA3)and(M.NLayer=62))Then
   M.AttnScale:=1.0/Sqrt(M.NEmbd div M.NHead)
  Else M.AttnScale:=1.0/Sqrt(M.HeadK);
 End
  Else Begin
   SetLength(M.Layers,M.NLayer);
   For I:=0 to M.NLayer-1 do M.Layers[I].IsSWA:=False;
  End;
 If(M.ArchId=AR_PHI3)and(M.NSwa>0)Then M.NSwa:=0;
End;

{ Associe les tenseurs de chaque couche }
Procedure BindTensors(Var M:TModel);
Var
 I:LongInt;
 G:^TGGUF;
 Idx:LongInt;
 NV:LongInt;

 Procedure Need(Idx:LongInt;Const Name:AnsiString);
 Begin
  If Idx<0 Then Fatal('tenseur manquant dans le modèle : '+Name);
  If not TypeSupported(G^.T[Idx].Typ)Then
   Fatal('le tenseur '+Name+' utilise un type de quantification non supporté ('+TypeName(G^.T[Idx].Typ)+')');
 End;

 Function Pref(L:LongInt;Const Part:AnsiString):LongInt;
 Begin
  Pref:=LayerTensor(G^,L,Part);
 End;

Begin
 G:=@M.G;
 M.TokEmbd:=FindTensor(G^,'token_embd.weight');
 Need(M.TokEmbd,'token_embd.weight');
 M.Output:=FindTensor(G^,'output.weight');
 If M.Output<0 Then M.Output:=M.TokEmbd;
 Idx:=FindTensor(G^,'output_norm.weight');
 Need(Idx,'output_norm.weight');
 LoadVec(G^,Idx,M.OutputNorm);
 LoadVec(G^,FindTensor(G^,'output.bias'),M.OutputBias);
 LoadVec(G^,FindTensor(G^,'rope_freqs.weight'),M.RopeFreqs);
 LoadVec(G^,FindTensor(G^,'rope_factors_long.weight'),M.RopeLong);
 LoadVec(G^,FindTensor(G^,'rope_factors_short.weight'),M.RopeShort);
 M.NVocab:=G^.T[M.TokEmbd].Ne[1];
 If M.V.NTokens<>M.NVocab Then Begin
  LogWrn('avertissement : taille du vocabulaire ('+IStr(M.V.NTokens)+') différente de token_embd ('+
         IStr(M.NVocab)+')'+#10);
  If M.NVocab>M.V.NTokens Then M.NVocab:=M.V.NTokens;
 End;
 For I:=0 to M.NLayer-1 do Begin
  With M.Layers[I]do Begin
   Idx:=Pref(I,'attn_norm.weight');Need(Idx,'blk.'+IStr(I)+'.attn_norm.weight');
   LoadVec(G^,Idx,AttnNorm);
   Idx:=Pref(I,'ffn_norm.weight');
   LoadVec(G^,Idx,FfnNorm);
   LoadVec(G^,Pref(I,'attn_q_norm.weight'),QNorm);
   LoadVec(G^,Pref(I,'attn_k_norm.weight'),KNorm);
   LoadVec(G^,Pref(I,'post_attention_norm.weight'),PostAttnNorm);
   LoadVec(G^,Pref(I,'post_ffw_norm.weight'),PostFfnNorm);
   LoadVec(G^,Pref(I,'attn_q.bias'),Bq);
   LoadVec(G^,Pref(I,'attn_k.bias'),Bk);
   LoadVec(G^,Pref(I,'attn_v.bias'),Bv);
   LoadVec(G^,Pref(I,'attn_output.bias'),Bo);
   Wqkv:=Pref(I,'attn_qkv.weight');
   Wq:=Pref(I,'attn_q.weight');
   Wk:=Pref(I,'attn_k.weight');
   Wv:=Pref(I,'attn_v.weight');
   If Wqkv<0 Then Begin
    Need(Wq,'blk.'+IStr(I)+'.attn_q.weight');
    Need(Wk,'blk.'+IStr(I)+'.attn_k.weight');
    Need(Wv,'blk.'+IStr(I)+'.attn_v.weight');
   End
    Else Need(Wqkv,'blk.'+IStr(I)+'.attn_qkv.weight');
   Wo:=Pref(I,'attn_output.weight');Need(Wo,'blk.'+IStr(I)+'.attn_output.weight');
   If Length(FfnNorm)=0 Then Fatal('tenseur manquant dans le modèle : blk.'+IStr(I)+'.ffn_norm.weight');
   FfnGate:=Pref(I,'ffn_gate.weight');
   FfnUp:=Pref(I,'ffn_up.weight');
   FfnDown:=Pref(I,'ffn_down.weight');
   GateInp:=Pref(I,'ffn_gate_inp.weight');
   GateExps:=Pref(I,'ffn_gate_exps.weight');
   UpExps:=Pref(I,'ffn_up_exps.weight');
   DownExps:=Pref(I,'ffn_down_exps.weight');
   GateInpShexp:=Pref(I,'ffn_gate_inp_shexp.weight');
   GateShexp:=Pref(I,'ffn_gate_shexp.weight');
   UpShexp:=Pref(I,'ffn_up_shexp.weight');
   DownShexp:=Pref(I,'ffn_down_shexp.weight');
   If GateInp>=0 Then Begin
    Need(UpExps,'blk.'+IStr(I)+'.ffn_up_exps.weight');
    Need(DownExps,'blk.'+IStr(I)+'.ffn_down_exps.weight');
    Need(GateExps,'blk.'+IStr(I)+'.ffn_gate_exps.weight');
    If M.NExpert=0 Then M.NExpert:=G^.T[GateInp].Ne[1];
    If M.NExpertUsed=0 Then M.NExpertUsed:=2;
    If M.NFFExp=0 Then M.NFFExp:=G^.T[GateExps].Ne[1];
   End
    Else Begin
     Need(FfnUp,'blk.'+IStr(I)+'.ffn_up.weight');
     Need(FfnDown,'blk.'+IStr(I)+'.ffn_down.weight');
     If FfnGate<0 Then Begin
      { gate+up fusionnes (phi3) }
     End
      Else Need(FfnGate,'blk.'+IStr(I)+'.ffn_gate.weight');
     If M.NFF=0 Then M.NFF:=G^.T[FfnDown].Ne[0];
    End;
  End;
 End;
End;

Procedure ModelCountSize(Var M:TModel);
Var
 I:LongInt;
Begin
 M.NElements:=0;M.NBytes:=0;
 For I:=0 to High(M.G.T)do Begin
  Inc(M.NElements,TensorElems(M.G.T[I]));
  Inc(M.NBytes,M.G.T[I].NBytes);
 End;
End;

Function ModelDominantType(Const M:TModel):AnsiString;
Var
 Cnt:Array[0..63]of Int64;
 I,Best:LongInt;
Begin
 For I:=0 to 63 do Cnt[I]:=0;
 For I:=0 to High(M.G.T)do
  If(M.G.T[I].Typ>=0)and(M.G.T[I].Typ<64)and(M.G.T[I].NDims>=2)Then Inc(Cnt[M.G.T[I].Typ]);
 Best:=0;
 For I:=0 to 63 do If Cnt[I]>Cnt[Best]Then Best:=I;
 ModelDominantType:=TypeName(Best);
End;

Function ModelHasChatTemplate(Const M:TModel):Boolean;
Begin
 ModelHasChatTemplate:=M.V.ChatTemplate<>'';
End;

Procedure PrintModelInfo(Const M:TModel);
Var
 I:LongInt;
Begin
 LogOut(4,'print_info: arch             = '+M.Arch+#10);
 LogOut(4,'print_info: n_ctx_train      = '+IStr(M.NCtxTrain)+#10);
 LogOut(4,'print_info: n_embd           = '+IStr(M.NEmbd)+#10);
 LogOut(4,'print_info: n_layer          = '+IStr(M.NLayer)+#10);
 LogOut(4,'print_info: n_head           = '+IStr(M.NHead)+#10);
 LogOut(4,'print_info: n_head_kv        = '+IStr(M.NHeadKV)+#10);
 LogOut(4,'print_info: n_rot            = '+IStr(M.NRot)+#10);
 LogOut(4,'print_info: n_embd_head_k    = '+IStr(M.HeadK)+#10);
 LogOut(4,'print_info: n_embd_head_v    = '+IStr(M.HeadV)+#10);
 LogOut(4,'print_info: n_ff             = '+IStr(M.NFF)+#10);
 If M.NExpert>0 Then Begin
  LogOut(4,'print_info: n_expert         = '+IStr(M.NExpert)+#10);
  LogOut(4,'print_info: n_expert_used    = '+IStr(M.NExpertUsed)+#10);
 End;
 LogOut(4,'print_info: f_norm_rms_eps   = '+FStr(M.NormEps*1.0e5,3)+'e-05'+#10);
 LogOut(4,'print_info: freq_base_train  = '+FStr(M.RopeBase,1)+#10);
 LogOut(4,'print_info: freq_scale_train = '+FStr(M.RopeScaleTrain,3)+#10);
 LogOut(4,'print_info: n_vocab          = '+IStr(M.V.NTokens)+#10);
 LogOut(4,'print_info: file format      = GGUF V'+IStr(M.G.Version)+#10);
 LogOut(4,'print_info: file type        = '+ModelDominantType(M)+#10);
 LogOut(4,'print_info: file size        = '+HumanBytes(M.NBytes)+' ('+FStr(M.NBytes*8.0/(M.NElements+1),2)+' BPW)'+#10);
 LogOut(4,'print_info: general.name     = '+M.Name+#10);
 If M.V.BOS>=0 Then LogOut(4,'print_info: BOS token        = '+IStr(M.V.BOS)+' '''+M.V.Text[M.V.BOS]+''''+#10);
 If M.V.EOS>=0 Then LogOut(4,'print_info: EOS token        = '+IStr(M.V.EOS)+' '''+M.V.Text[M.V.EOS]+''''+#10);
 If M.V.EOT>=0 Then LogOut(4,'print_info: EOT token        = '+IStr(M.V.EOT)+' '''+M.V.Text[M.V.EOT]+''''+#10);
 If M.V.UNK>=0 Then LogOut(4,'print_info: UNK token        = '+IStr(M.V.UNK)+' '''+M.V.Text[M.V.UNK]+''''+#10);
 If M.V.PAD>=0 Then LogOut(4,'print_info: PAD token        = '+IStr(M.V.PAD)+' '''+M.V.Text[M.V.PAD]+''''+#10);
 If M.V.NL>=0 Then LogOut(4,'print_info: LF token         = '+IStr(M.V.NL)+#10);
 For I:=0 to M.V.NTokens-1 do
  If M.V.EOG[I]Then LogOut(4,'print_info: EOG token        = '+IStr(I)+' '''+M.V.Text[I]+''''+#10);
End;

Procedure ApplyKVOverrides(Var G:TGGUF);
Var
 I,K:LongInt;
 V:Int64;
 F:Double;
Begin
 For I:=0 to High(KVOverrides)do Begin
  K:=KVFind(G,KVOverrides[I].Key);
  If K<0 Then Begin
   K:=Length(G.KV);
   SetLength(G.KV,K+1);
   G.KV[K].Key:=KVOverrides[I].Key;
   G.KV[K].N:=0;G.KV[K].ArrTyp:=0;
  End;
  G.KV[K].SA:=Nil;G.KV[K].IA:=Nil;G.KV[K].FA:=Nil;
  G.KV[K].I:=0;G.KV[K].F:=0;G.KV[K].S:='';
  If KVOverrides[I].Typ='int' Then Begin
   G.KV[K].Typ:=GT_INT64;
   If ParseInt(KVOverrides[I].Val,V)Then G.KV[K].I:=V;
   G.KV[K].F:=G.KV[K].I;
  End
   Else If KVOverrides[I].Typ='float' Then Begin
    G.KV[K].Typ:=GT_FLOAT64;
    If ParseFloat(KVOverrides[I].Val,F)Then G.KV[K].F:=F;
    G.KV[K].I:=Trunc(G.KV[K].F);
   End
   Else If KVOverrides[I].Typ='bool' Then Begin
    G.KV[K].Typ:=GT_BOOL;
    If(LoStr(KVOverrides[I].Val)='true')or(KVOverrides[I].Val='1')Then G.KV[K].I:=1;
    G.KV[K].F:=G.KV[K].I;
   End
   Else Begin
    G.KV[K].Typ:=GT_STRING;
    G.KV[K].S:=KVOverrides[I].Val;
   End;
 End;
End;

Procedure LoadModel(Const Path:AnsiString;Var M:TModel;Verbose:Boolean);
Var
 T0:Int64;
Begin
 T0:=NowMs;
 LoadModelMeta(Path,M);
 ApplyKVOverrides(M.G);
 LoadHParams(M);
 LoadVocab(M.V,M.G);
 LogOut(4,'llama_model_loader: chargement de '+IStr(Length(M.G.T))+' tenseurs depuis '+Path+#10);
 LoadTensorData(M.G,Verbose);
 ModelCountSize(M);
 BindTensors(M);
 If M.NCtxTrain<=0 Then M.NCtxTrain:=4096;
 PrintModelInfo(M);
 LogOut(4,'load_tensors: modèle chargé en '+IStr(NowMs-T0)+' ms'+#10);
End;

{ ------------------------------------------------------------------ }
{ Noyaux de calcul                                                    }
{ ------------------------------------------------------------------ }

Type
 TCtx=Record
  NCtx,NBatch:LongInt;
  KC,VC:Array of PSingle;
  NPast:LongInt;
  X,XN,Q,Kb,Vb,AO,OB,FG,FU,QKV,Logits,Scores,W4,Hid,Acc,RL,RopeCs,RopeCsS,Tmp:PSingle;
  QD,KD,VD,AOD,MaxFF:LongInt;
  FreqBase,FreqScale,ExtFactor,AttnFactor,BetaFast,BetaSlow:Single;
  CorrLo,CorrHi:Single;
  Factors:PSingle;
  NCtxOrig:LongInt;
  ScalingType:LongInt;
  UseSWA:Boolean;
  NThreads:LongInt;
  KVBytes:Int64;
 End;

 TRopeOpts=Record
  Base,Scale:Single;           { 0 = valeur du modele }
  ScalingType:LongInt;         { -1 = valeur du modele }
  OrigCtx:LongInt;
  ExtFactor,AttnFactor,BetaFast,BetaSlow:Single;   { <0 = valeur du modele }
 End;

Procedure Dot4(W0,W1,W2,W3,X:PSingle;K:LongInt;R:PSingle);
Var
 I:LongInt;
 A0,A1,A2,A3,B0,B1,B2,B3,X0,X1:Single;
Begin
 A0:=0;A1:=0;A2:=0;A3:=0;B0:=0;B1:=0;B2:=0;B3:=0;
 I:=0;
 While I<K-1 do Begin
  X0:=X[I];X1:=X[I+1];
  A0:=A0+W0[I]*X0;B0:=B0+W0[I+1]*X1;
  A1:=A1+W1[I]*X0;B1:=B1+W1[I+1]*X1;
  A2:=A2+W2[I]*X0;B2:=B2+W2[I+1]*X1;
  A3:=A3+W3[I]*X0;B3:=B3+W3[I+1]*X1;
  Inc(I,2);
 End;
 If I<K Then Begin
  X0:=X[I];
  A0:=A0+W0[I]*X0;A1:=A1+W1[I]*X0;A2:=A2+W2[I]*X0;A3:=A3+W3[I]*X0;
 End;
 R[0]:=A0+B0;R[1]:=A1+B1;R[2]:=A2+B2;R[3]:=A3+B3;
End;

Function Dot1(W,X:PSingle;K:LongInt):Single;
Var
 I:LongInt;
 A,B,C,D:Single;
Begin
 A:=0;B:=0;C:=0;D:=0;
 I:=0;
 While I<K-3 do Begin
  A:=A+W[I]*X[I];B:=B+W[I+1]*X[I+1];C:=C+W[I+2]*X[I+2];D:=D+W[I+3]*X[I+3];
  Inc(I,4);
 End;
 While I<K do Begin A:=A+W[I]*X[I];Inc(I);End;
 Dot1:=(A+B)+(C+D);
End;

{ ------------------------------------------------------------------ }
{ Produits scalaires entiers (activations quantifiees Q8_0 / Q8_K,    }
{ comme ggml_vec_dot_*_q8_*)                                          }
{ ------------------------------------------------------------------ }

Const
 XQ0Stride=36;     { Single d + 32 x Int8 }
 XQKStride=292;    { Single d + 256 x Int8 + 16 x Int16 (bsums) }

Var
 NoIntDot:Boolean=False;
 XQBuf:PByte=Nil;
 XQBufSize:Int64=0;

Function XQRowBytes(IT,K:LongInt):Int64;
Begin
 If IT=1 Then XQRowBytes:=Int64(K shr 5)*XQ0Stride
  Else XQRowBytes:=Int64(K shr 8)*XQKStride;
End;

Function IntDotType(T:LongInt;K:LongInt):LongInt;   { 0 = non, 1 = Q8_0, 2 = Q8_K }
Begin
 IntDotType:=0;
 If NoIntDot Then Exit;
 Case T of
  TY_Q4_0,TY_Q5_0,TY_Q8_0:If(K and 31)=0 Then IntDotType:=1;
  TY_Q4_K,TY_Q5_K,TY_Q6_K:If(K and 255)=0 Then IntDotType:=2;
 End;
End;

Procedure QuantRowQ8_0(X:PSingle;Dst:PByte;K:LongInt);
Var
 NB,I,J:LongInt;
 AMax,V,D,ID:Single;
 Q:PShortInt;
Begin
 NB:=K shr 5;
 For I:=0 to NB-1 do Begin
  AMax:=0;
  For J:=0 to 31 do Begin
   V:=Abs(X[J]);
   If V>AMax Then AMax:=V;
  End;
  D:=AMax/127.0;
  If D<>0 Then ID:=1.0/D Else ID:=0;
  PSingle(Dst)^:=D;
  Q:=PShortInt(Dst+4);
  For J:=0 to 31 do Q[J]:=Round(X[J]*ID);
  Inc(X,32);Inc(Dst,XQ0Stride);
 End;
End;

Procedure QuantRowQ8_K(X:PSingle;Dst:PByte;K:LongInt);
Var
 NB,I,J:LongInt;
 AMax,Mx,V,ISc:Single;
 Q:PShortInt;
 BS:PSmallInt;
 S,C:LongInt;
Begin
 NB:=K shr 8;
 For I:=0 to NB-1 do Begin
  AMax:=0;Mx:=0;
  For J:=0 to 255 do Begin
   V:=Abs(X[J]);
   If V>AMax Then Begin AMax:=V;Mx:=X[J];End;
  End;
  Q:=PShortInt(Dst+4);
  BS:=PSmallInt(Dst+260);
  If AMax=0 Then Begin
   PSingle(Dst)^:=0;
   FillChar(Dst[4],288,0);
  End
   Else Begin
    ISc:=-127.0/Mx;
    For J:=0 to 255 do Begin
     C:=Round(ISc*X[J]);
     If C>127 Then C:=127;
     If C<-128 Then C:=-128;
     Q[J]:=C;
    End;
    For J:=0 to 15 do Begin
     S:=0;
     For C:=0 to 15 do Inc(S,Q[J*16+C]);
     BS[J]:=S;
    End;
    PSingle(Dst)^:=1.0/ISc;
   End;
  Inc(X,256);Inc(Dst,XQKStride);
 End;
End;

Function DotQ4_0Q8(W,Y:PByte;NB:LongInt):Single;
Var
 I,J,S0,S1:LongInt;
 Q:PByte;
 YQ:PShortInt;
 SumF:Single;
Begin
 SumF:=0;
 For I:=0 to NB-1 do Begin
  Q:=W+2;
  YQ:=PShortInt(Y+4);
  S0:=0;S1:=0;
  For J:=0 to 15 do Begin
   Inc(S0,((Q[J]and $F)-8)*YQ[J]);
   Inc(S1,((Q[J]shr 4)-8)*YQ[J+16]);
  End;
  SumF:=SumF+(S0+S1)*F16Tab[PWord(W)^]*PSingle(Y)^;
  Inc(W,18);Inc(Y,XQ0Stride);
 End;
 DotQ4_0Q8:=SumF;
End;

Function DotQ5_0Q8(W,Y:PByte;NB:LongInt):Single;
Var
 I,J,S0,S1,X0,X1:LongInt;
 QH:LongWord;
 Q:PByte;
 YQ:PShortInt;
 SumF:Single;
Begin
 SumF:=0;
 For I:=0 to NB-1 do Begin
  QH:=PLongWord(W+2)^;
  Q:=W+6;
  YQ:=PShortInt(Y+4);
  S0:=0;S1:=0;
  For J:=0 to 15 do Begin
   X0:=((Q[J]and $F)or(((QH shr J)and 1)shl 4))-16;
   X1:=((Q[J]shr 4)or(((QH shr(J+12))and $10)))-16;
   Inc(S0,X0*YQ[J]);
   Inc(S1,X1*YQ[J+16]);
  End;
  SumF:=SumF+(S0+S1)*F16Tab[PWord(W)^]*PSingle(Y)^;
  Inc(W,22);Inc(Y,XQ0Stride);
 End;
 DotQ5_0Q8:=SumF;
End;

Function DotQ8_0Q8(W,Y:PByte;NB:LongInt):Single;
Var
 I,J,S:LongInt;
 Q,YQ:PShortInt;
 SumF:Single;
Begin
 SumF:=0;
 For I:=0 to NB-1 do Begin
  Q:=PShortInt(W+2);
  YQ:=PShortInt(Y+4);
  S:=0;
  For J:=0 to 31 do Inc(S,Q[J]*YQ[J]);
  SumF:=SumF+S*F16Tab[PWord(W)^]*PSingle(Y)^;
  Inc(W,34);Inc(Y,XQ0Stride);
 End;
 DotQ8_0Q8:=SumF;
End;

Function DotQ4_KQ8(W,Y:PByte;NB:LongInt):Single;
Var
 I,G,L,S0,S1,SumI,SumM,T:LongInt;
 Sc,M:Byte;
 Q:PByte;
 YQ:PShortInt;
 BS:PSmallInt;
 Mins:Array[0..7]of LongInt;
 Scl:Array[0..7]of LongInt;
 YD,SumF:Single;
Begin
 SumF:=0;
 For I:=0 to NB-1 do Begin
  YD:=PSingle(Y)^;
  YQ:=PShortInt(Y+4);
  BS:=PSmallInt(Y+260);
  For T:=0 to 7 do Begin
   ScaleMinK4(T,W+4,Sc,M);
   Scl[T]:=Sc;Mins[T]:=M;
  End;
  SumM:=0;
  For T:=0 to 15 do Inc(SumM,BS[T]*Mins[T shr 1]);
  Q:=W+16;
  SumI:=0;
  For G:=0 to 3 do Begin
   S0:=0;S1:=0;
   For L:=0 to 31 do Begin
    Inc(S0,(Q[L]and $F)*YQ[L]);
    Inc(S1,(Q[L]shr 4)*YQ[L+32]);
   End;
   Inc(SumI,Scl[2*G]*S0+Scl[2*G+1]*S1);
   Inc(Q,32);Inc(YQ,64);
  End;
  SumF:=SumF+F16Tab[PWord(W)^]*YD*SumI-F16Tab[PWord(W+2)^]*YD*SumM;
  Inc(W,144);Inc(Y,XQKStride);
 End;
 DotQ4_KQ8:=SumF;
End;

Function DotQ5_KQ8(W,Y:PByte;NB:LongInt):Single;
Var
 I,G,L,S0,S1,SumI,SumM,T,Mk:LongInt;
 Sc,M:Byte;
 Q,HM:PByte;
 YQ:PShortInt;
 BS:PSmallInt;
 Mins:Array[0..7]of LongInt;
 Scl:Array[0..7]of LongInt;
 YD,SumF:Single;
Begin
 SumF:=0;
 For I:=0 to NB-1 do Begin
  YD:=PSingle(Y)^;
  YQ:=PShortInt(Y+4);
  BS:=PSmallInt(Y+260);
  For T:=0 to 7 do Begin
   ScaleMinK4(T,W+4,Sc,M);
   Scl[T]:=Sc;Mins[T]:=M;
  End;
  SumM:=0;
  For T:=0 to 15 do Inc(SumM,BS[T]*Mins[T shr 1]);
  HM:=W+16;
  Q:=W+48;
  SumI:=0;
  Mk:=0;
  For G:=0 to 3 do Begin
   S0:=0;S1:=0;
   For L:=0 to 31 do Begin
    Inc(S0,((Q[L]and $F)or(((HM[L]shr Mk)and 1)shl 4))*YQ[L]);
    Inc(S1,((Q[L]shr 4)or(((HM[L]shr(Mk+1))and 1)shl 4))*YQ[L+32]);
   End;
   Inc(SumI,Scl[2*G]*S0+Scl[2*G+1]*S1);
   Inc(Q,32);Inc(YQ,64);Inc(Mk,2);
  End;
  SumF:=SumF+F16Tab[PWord(W)^]*YD*SumI-F16Tab[PWord(W+2)^]*YD*SumM;
  Inc(W,176);Inc(Y,XQKStride);
 End;
 DotQ5_KQ8:=SumF;
End;

Function DotQ6_KQ8(W,Y:PByte;NB:LongInt):Single;
Var
 I,CH,L,SumI,IS_:LongInt;
 QL,QH:PByte;
 SC:PShortInt;
 YQ:PShortInt;
 A0,A1,A2,A3,S0,S1,S2,S3:LongInt;
 SumF:Single;
Begin
 SumF:=0;
 For I:=0 to NB-1 do Begin
  YQ:=PShortInt(Y+4);
  QL:=W;QH:=W+128;SC:=PShortInt(W+192);
  SumI:=0;
  For CH:=0 to 1 do Begin
   For IS_:=0 to 1 do Begin
    S0:=0;S1:=0;S2:=0;S3:=0;
    For L:=IS_*16 to IS_*16+15 do Begin
     A0:=LongInt((QL[L]and $F)or(((QH[L])and 3)shl 4))-32;
     A1:=LongInt((QL[L+32]and $F)or(((QH[L]shr 2)and 3)shl 4))-32;
     A2:=LongInt((QL[L]shr 4)or(((QH[L]shr 4)and 3)shl 4))-32;
     A3:=LongInt((QL[L+32]shr 4)or(((QH[L]shr 6)and 3)shl 4))-32;
     Inc(S0,A0*YQ[L]);
     Inc(S1,A1*YQ[L+32]);
     Inc(S2,A2*YQ[L+64]);
     Inc(S3,A3*YQ[L+96]);
    End;
    Inc(SumI,SC[IS_]*S0+SC[IS_+2]*S1+SC[IS_+4]*S2+SC[IS_+6]*S3);
   End;
   Inc(QL,64);Inc(QH,32);Inc(SC,8);Inc(YQ,128);
  End;
  SumF:=SumF+F16Tab[PWord(W+208)^]*PSingle(Y)^*SumI;
  Inc(W,210);Inc(Y,XQKStride);
 End;
 DotQ6_KQ8:=SumF;
End;

Function DotInt(T:LongInt;W,Y:PByte;K:LongInt):Single;
Begin
 Case T of
  TY_Q4_0:DotInt:=DotQ4_0Q8(W,Y,K shr 5);
  TY_Q5_0:DotInt:=DotQ5_0Q8(W,Y,K shr 5);
  TY_Q8_0:DotInt:=DotQ8_0Q8(W,Y,K shr 5);
  TY_Q4_K:DotInt:=DotQ4_KQ8(W,Y,K shr 8);
  TY_Q5_K:DotInt:=DotQ5_KQ8(W,Y,K shr 8);
  Else DotInt:=DotQ6_KQ8(W,Y,K shr 8);
 End;
End;

{ ------------------------------------------------------------------ }
{ Fils d'execution (Windows : CreateThread, Unix : pthread)           }
{ ------------------------------------------------------------------ }

{$IFDEF WINDOWS}
Function CreateThread(Attr:Pointer;Stack:PtrUInt;Start:Pointer;Param:Pointer;Flags:LongWord;Var Tid:LongWord):PtrUInt;
 stdcall;external 'kernel32.dll' name 'CreateThread';
Procedure WinSleep(Ms:LongWord);stdcall;external 'kernel32.dll' name 'Sleep';
{$ELSE}
 {$IFDEF UNIX}
Function pthread_create(Var Th:PtrUInt;Attr:Pointer;Start:Pointer;Arg:Pointer):LongInt;cdecl;
 external 'pthread' name 'pthread_create';
Function usleep(Us:LongWord):LongInt;cdecl;external 'c' name 'usleep';
Function sysconf(Name:LongInt):PtrInt;cdecl;external 'c' name 'sysconf';
 {$ENDIF}
{$ENDIF}

Const
 MaxThreads=32;
 ChunkRows=16;

Type
 TMMJob=Record
  Typ:LongInt;
  Data:PByte;
  K,M:LongInt;
  X,Y:PSingle;
  NTok:LongInt;
  XQ:PByte;
  IT:LongInt;
 End;

Var
 GNThreads:LongInt=0;
 PoolN:LongInt=1;
 PoolGen:LongInt=0;
 PoolDone:LongInt=0;
 PoolNext:LongInt=0;
 PoolQuit:LongInt=0;
 PoolJob:TMMJob;
 PoolScratch:Array[0..MaxThreads-1]of PSingle;
 PoolScratchSize:Int64=0;
 PoolReady:Boolean=False;

Procedure PoolSleepUs(Us:LongWord);
Begin
 {$IFDEF WINDOWS}
 WinSleep(1);
 {$ELSE}
  {$IFDEF UNIX}
 usleep(Us);
  {$ENDIF}
 {$ENDIF}
End;

Function CpuCount:LongInt;
Var
 N:Int64;
Begin
 CpuCount:=1;
 {$IFDEF WINDOWS}
 If ParseInt(GetEnv('NUMBER_OF_PROCESSORS'),N)Then CpuCount:=N;
 {$ELSE}
  {$IFDEF UNIX}
 N:=sysconf(84);
 If N>0 Then CpuCount:=N;
  {$ENDIF}
 {$ENDIF}
 If CpuCount<1 Then CpuCount:=1;
End;

{ multiplication d'un paquet de lignes [R0,R1) }
Procedure MatMulRows(Const J:TMMJob;R0,R1:LongInt;Scratch:PSingle);
Var
 R,JJ,NR,T,K,M:LongInt;
 RB,XS:Int64;
 Wp:Array[0..3]of PSingle;
 Xp:PSingle;
 Tmp4:Array[0..3]of Single;
Begin
 K:=J.K;M:=J.M;
 RB:=RowBytes(J.Typ,K);
 If J.IT<>0 Then Begin
  XS:=XQRowBytes(J.IT,K);
  For R:=R0 to R1-1 do
   For T:=0 to J.NTok-1 do
    J.Y[T*M+R]:=DotInt(J.Typ,J.Data+R*RB,J.XQ+T*XS,K);
  Exit;
 End;
 R:=R0;
 While R<R1 do Begin
  NR:=R1-R;
  If NR>4 Then NR:=4;
  For JJ:=0 to NR-1 do Begin
   If J.Typ=TY_F32 Then Wp[JJ]:=PSingle(J.Data+(R+JJ)*RB)
   Else Begin
    DequantRow(J.Typ,J.Data+(R+JJ)*RB,Scratch+JJ*K,K);
    Wp[JJ]:=Scratch+JJ*K;
   End;
  End;
  If NR=4 Then Begin
   For T:=0 to J.NTok-1 do Begin
    Xp:=J.X+T*K;
    Dot4(Wp[0],Wp[1],Wp[2],Wp[3],Xp,K,@Tmp4[0]);
    J.Y[T*M+R]:=Tmp4[0];J.Y[T*M+R+1]:=Tmp4[1];J.Y[T*M+R+2]:=Tmp4[2];J.Y[T*M+R+3]:=Tmp4[3];
   End;
  End
   Else Begin
    For T:=0 to J.NTok-1 do Begin
     Xp:=J.X+T*K;
     For JJ:=0 to NR-1 do J.Y[T*M+R+JJ]:=Dot1(Wp[JJ],Xp,K);
    End;
   End;
  Inc(R,NR);
 End;
End;

Procedure PoolRunChunks(Tid:LongInt);
Var
 C,R0,R1:LongInt;
Begin
 While True do Begin
  C:=InterLockedIncrement(PoolNext)-1;
  R0:=C*ChunkRows;
  If R0>=PoolJob.M Then Break;
  R1:=R0+ChunkRows;
  If R1>PoolJob.M Then R1:=PoolJob.M;
  MatMulRows(PoolJob,R0,R1,PoolScratch[Tid]);
 End;
End;

Procedure PoolWorkerLoop(Tid:LongInt);
Var
 Seen,G:LongInt;
 IdleStart,Now_:Double;
Begin
 Seen:=0;
 IdleStart:=NowMsF;
 While InterLockedCompareExchange(PoolQuit,0,0)=0 do Begin
  G:=InterLockedCompareExchange(PoolGen,0,0);
  If G<>Seen Then Begin
   Seen:=G;
   PoolRunChunks(Tid);
   InterLockedIncrement(PoolDone);
   IdleStart:=NowMsF;
  End
   Else Begin
    Now_:=NowMsF;
    If Now_-IdleStart>3.0 Then PoolSleepUs(200);
   End;
 End;
End;

Var
 PoolTidCounter:LongInt=0;

{$IFDEF WINDOWS}
Function PoolThreadEntry(P:Pointer):LongWord;stdcall;
Begin
 PoolWorkerLoop(PtrInt(P));
 PoolThreadEntry:=0;
End;
{$ELSE}
 {$IFDEF UNIX}
Function PoolThreadEntry(P:Pointer):Pointer;cdecl;
Begin
 PoolWorkerLoop(PtrInt(P));
 PoolThreadEntry:=Nil;
End;
 {$ENDIF}
{$ENDIF}

{ cree le groupe de fils (appele une fois, avec la taille maximale de ligne) }
Procedure PoolInit(NThreads:LongInt;MaxK:LongInt);
Var
 I:LongInt;
 Created:LongInt;
 {$IFDEF WINDOWS}
 Tid:LongWord;
 H:PtrUInt;
 {$ELSE}
 Th:PtrUInt;
 {$ENDIF}
Begin
 If PoolReady Then Exit;
 PoolReady:=True;
 If NThreads<1 Then NThreads:=1;
 If NThreads>MaxThreads Then NThreads:=MaxThreads;
 PoolScratchSize:=Int64(MaxK)*4*4+256;
 For I:=0 to NThreads-1 do Begin
  GetMem(PoolScratch[I],PoolScratchSize);
  FillChar(PoolScratch[I]^,PoolScratchSize,0);
 End;
 Created:=1;
 {$IFDEF WINDOWS}
 For I:=1 to NThreads-1 do Begin
  H:=CreateThread(Nil,0,@PoolThreadEntry,Pointer(PtrInt(I)),0,Tid);
  If H=0 Then Break;
  Inc(Created);
 End;
 {$ELSE}
  {$IFDEF UNIX}
 For I:=1 to NThreads-1 do Begin
  If pthread_create(Th,Nil,@PoolThreadEntry,Pointer(PtrInt(I)))<>0 Then Break;
  Inc(Created);
 End;
  {$ENDIF}
 {$ENDIF}
 PoolN:=Created;
 { les fils crees portent les numeros 1..Created-1 : les numeros inutilises restent libres }
End;

Procedure PoolStop;
Begin
 InterLockedExchange(PoolQuit,1);
End;

{ Y[t*M+r] = somme_k W[r][k] * X[t*K+k] ; W : M lignes de K elements (type Typ) }
Procedure MatMulPtr(Typ:LongInt;Data:PByte;K,M:LongInt;X,Y:PSingle;NTok:LongInt;Scratch:PSingle);
Var
 J:TMMJob;
 Expect,T:LongInt;
 XS:Int64;
Begin
 J.Typ:=Typ;J.Data:=Data;J.K:=K;J.M:=M;J.X:=X;J.Y:=Y;J.NTok:=NTok;
 J.IT:=IntDotType(Typ,K);J.XQ:=Nil;
 If NTok>=8 Then J.IT:=0;   { prefill : deq. une fois + flottants }
 If J.IT<>0 Then Begin
  XS:=XQRowBytes(J.IT,K);
  If XS*NTok>XQBufSize Then Begin
   If XQBuf<>Nil Then FreeMem(XQBuf);
   XQBufSize:=XS*NTok;
   GetMem(XQBuf,XQBufSize);
  End;
  J.XQ:=XQBuf;
  For T:=0 to NTok-1 do
   If J.IT=1 Then QuantRowQ8_0(X+T*K,XQBuf+T*XS,K) Else QuantRowQ8_K(X+T*K,XQBuf+T*XS,K);
 End;
 If(PoolN<=1)or(M<4*ChunkRows)or(Int64(M)*K*NTok<200000)Then Begin
  MatMulRows(J,0,M,Scratch);
  Exit;
 End;
 PoolJob:=J;
 InterLockedExchange(PoolNext,0);
 InterLockedExchange(PoolDone,0);
 InterLockedIncrement(PoolGen);
 PoolRunChunks(0);
 Expect:=PoolN-1;
 While InterLockedCompareExchange(PoolDone,0,0)<Expect do;
End;

Procedure RMSNorm(X,W,Dst:PSingle;N:LongInt;Eps:Single);
Var
 I:LongInt;
 SS:Double;
 Sc:Single;
Begin
 SS:=0;
 For I:=0 to N-1 do SS:=SS+Double(X[I])*X[I];
 Sc:=1.0/Sqrt(SS/N+Eps);
 If W<>Nil Then Begin
  For I:=0 to N-1 do Dst[I]:=X[I]*Sc*W[I];
 End
  Else For I:=0 to N-1 do Dst[I]:=X[I]*Sc;
End;

Function YarnRamp(Lo,Hi:Single;I0:LongInt):Single;
Var
 Y:Single;
Begin
 Y:=((I0 div 2)-Lo)/FMax(0.001,Hi-Lo);
 If Y<0 Then Y:=0;
 If Y>1 Then Y:=1;
 YarnRamp:=1.0-Y;
End;

Function FFloor(X:Double):Double;
Begin
 If Frac(X)<0 Then FFloor:=Int(X)-1 Else FFloor:=Int(X);
End;

Function FCeil(X:Double):Double;
Begin
 If Frac(X)>0 Then FCeil:=Int(X)+1 Else FCeil:=Int(X);
End;

Function GetMscaleF(Scale,Ms:Double):Double;
Begin
 If Scale<=1.0 Then GetMscaleF:=1.0 Else GetMscaleF:=0.1*Ms*Ln(Scale)+1.0;
End;

Function CorrDim(NDims,NCtxOrig:LongInt;NRot,Base:Single):Single;
Begin
 CorrDim:=NDims*Ln(NCtxOrig/(NRot*2*Pi))/(2*Ln(Base));
End;

{ cos/sin pour une position ; Dst = [cos0,sin0,cos1,sin1,...] }
Procedure RopeCacheInit(Var C:TCtx;Dst:PSingle;Pos:LongInt;FreqBase,FreqScale:Single;NRot:LongInt;
                        Ext,Attn:Single;Fact:PSingle);
Var
 IC:LongInt;
 TE,TI,Th,Ramp,Ms:Double;
Begin
 For IC:=0 to NRot div 2-1 do Begin
  TE:=Pos*FPow(FreqBase,-2.0*IC/NRot);
  If Fact<>Nil Then TE:=TE/Fact[IC];
  TI:=FreqScale*TE;
  Th:=TI;
  Ms:=Attn;
  If Ext<>0 Then Begin
   Ramp:=YarnRamp(C.CorrLo,C.CorrHi,2*IC)*Ext;
   Th:=TI*(1-Ramp)+TE*Ramp;
   Ms:=Ms*(1.0+0.1*Ln(1.0/FreqScale));
  End;
  Dst[2*IC]:=Cos(Th)*Ms;
  Dst[2*IC+1]:=Sin(Th)*Ms;
 End;
End;

Procedure ApplyRope(V:PSingle;NHeads,HeadDim:LongInt;Cs:PSingle;NRot:LongInt;Neox:Boolean);
Var
 H,IC,Half:LongInt;
 P:PSingle;
 X0,X1,Cc,Ss:Single;
Begin
 Half:=NRot div 2;
 For H:=0 to NHeads-1 do Begin
  P:=V+H*HeadDim;
  If Neox Then Begin
   For IC:=0 to Half-1 do Begin
    X0:=P[IC];X1:=P[IC+Half];Cc:=Cs[2*IC];Ss:=Cs[2*IC+1];
    P[IC]:=X0*Cc-X1*Ss;
    P[IC+Half]:=X0*Ss+X1*Cc;
   End;
  End
   Else Begin
    For IC:=0 to Half-1 do Begin
     X0:=P[2*IC];X1:=P[2*IC+1];Cc:=Cs[2*IC];Ss:=Cs[2*IC+1];
     P[2*IC]:=X0*Cc-X1*Ss;
     P[2*IC+1]:=X0*Ss+X1*Cc;
    End;
   End;
 End;
End;

Function ActSilu(X:Single):Single;
Begin
 ActSilu:=X/(1.0+Exp(-X));
End;

Function ActGelu(X:Single):Single;
Begin
 ActGelu:=0.5*X*(1.0+FTanh(0.79788456080286535588*(X+0.044715*X*X*X)));
End;

{ ------------------------------------------------------------------ }
{ Contexte (cache KV, tampons)                                        }
{ ------------------------------------------------------------------ }

Function KVBytesFor(Const M:TModel;NCtx:LongInt):Int64;
Begin
 KVBytesFor:=Int64(NCtx)*M.NLayer*(Int64(M.NHeadKV)*M.HeadK+Int64(M.NHeadKV)*M.HeadV)*4;
End;

Function AllocF(N:Int64):PSingle;
Var
 P:Pointer;
Begin
 GetMem(P,N*4+64);
 FillChar(P^,N*4+64,0);
 AllocF:=PSingle(P);
End;

Procedure CtxInit(Const M:TModel;Var C:TCtx;NCtx,NBatch:LongInt;Const RO:TRopeOpts);
Var
 I,MaxF,Wmax:LongInt;
 Fac,CD0,CD1:Double;
Begin
 C.NCtx:=NCtx;
 C.NBatch:=NBatch;
 C.NPast:=0;
 C.QD:=M.NHead*M.HeadK;
 C.KD:=M.NHeadKV*M.HeadK;
 C.VD:=M.NHeadKV*M.HeadV;
 C.AOD:=M.NHead*M.HeadV;
 SetLength(C.KC,M.NLayer);
 SetLength(C.VC,M.NLayer);
 For I:=0 to M.NLayer-1 do Begin
  C.KC[I]:=AllocF(Int64(NCtx)*C.KD);
  C.VC[I]:=AllocF(Int64(NCtx)*C.VD);
 End;
 C.KVBytes:=KVBytesFor(M,NCtx);
 { dimension maximale des couches FFN }
 MaxF:=M.NFF;
 If M.NFFExp>MaxF Then MaxF:=M.NFFExp;
 If M.NFFShexp>MaxF Then MaxF:=M.NFFShexp;
 For I:=0 to M.NLayer-1 do Begin
  If M.Layers[I].FfnUp>=0 Then If M.G.T[M.Layers[I].FfnUp].Ne[1]>MaxF Then MaxF:=M.G.T[M.Layers[I].FfnUp].Ne[1];
 End;
 C.MaxFF:=MaxF;
 Wmax:=M.NEmbd;
 If C.QD>Wmax Then Wmax:=C.QD;
 If C.AOD>Wmax Then Wmax:=C.AOD;
 If MaxF>Wmax Then Wmax:=MaxF;
 If GNThreads<=0 Then GNThreads:=CpuCount;
 If GNThreads>16 Then GNThreads:=16;
 NoIntDot:=GetEnv('LLAMA_NO_INTDOT')<>'';
 PoolInit(GNThreads,Wmax+M.NEmbd);
 C.NThreads:=PoolN;
 C.X:=AllocF(Int64(NBatch)*M.NEmbd);
 C.XN:=AllocF(Int64(NBatch)*M.NEmbd);
 C.OB:=AllocF(Int64(NBatch)*M.NEmbd);
 C.Q:=AllocF(Int64(NBatch)*C.QD);
 C.Kb:=AllocF(Int64(NBatch)*C.KD);
 C.Vb:=AllocF(Int64(NBatch)*C.VD);
 C.QKV:=AllocF(Int64(NBatch)*(C.QD+C.KD+C.VD));
 C.AO:=AllocF(Int64(NBatch)*C.AOD);
 C.FG:=AllocF(Int64(NBatch)*MaxF);
 C.FU:=AllocF(Int64(NBatch)*MaxF*2);
 C.Hid:=AllocF(Int64(NBatch)*MaxF);
 C.Acc:=AllocF(Int64(M.NEmbd)*2);
 C.Tmp:=AllocF(Int64(MaxF)*2+M.NEmbd);
 C.RL:=AllocF(Int64(NBatch)*(M.NExpert+1));
 If M.G.T[M.Output].Ne[1]>M.NVocab Then C.Logits:=AllocF(M.G.T[M.Output].Ne[1]+16)
 Else C.Logits:=AllocF(M.NVocab+16);
 C.Scores:=AllocF(NCtx+16);
 C.W4:=AllocF(Int64(Wmax+M.NEmbd)*4*2);
 C.RopeCs:=AllocF(Int64(NBatch)*(M.NRot+2));
 C.RopeCsS:=AllocF(Int64(NBatch)*(M.NRot+2));
 { parametres de rope }
 C.ScalingType:=M.RopeScalingType;
 If RO.ScalingType>=0 Then C.ScalingType:=RO.ScalingType;
 C.FreqBase:=M.RopeBase;
 If RO.Base<>0 Then C.FreqBase:=RO.Base;
 C.FreqScale:=M.RopeScaleTrain;
 If RO.Scale<>0 Then C.FreqScale:=RO.Scale;
 If C.ScalingType=RS_NONE Then C.FreqScale:=1.0;
 If RO.OrigCtx<>0 Then C.NCtxOrig:=RO.OrigCtx Else C.NCtxOrig:=M.NCtxOrigYarn;
 If C.NCtxOrig=0 Then C.NCtxOrig:=M.NCtxTrain;
 C.ExtFactor:=-1;
 If RO.ExtFactor>=0 Then C.ExtFactor:=RO.ExtFactor;
 C.AttnFactor:=1.0;
 If RO.AttnFactor>=0 Then C.AttnFactor:=RO.AttnFactor;
 C.BetaFast:=32;If RO.BetaFast>=0 Then C.BetaFast:=RO.BetaFast;
 C.BetaSlow:=1;If RO.BetaSlow>=0 Then C.BetaSlow:=RO.BetaSlow;
 If C.ExtFactor<0 Then Begin
  If C.ScalingType=RS_YARN Then C.ExtFactor:=1.0 Else C.ExtFactor:=0.0;
 End;
 If C.ExtFactor<>0 Then Begin
  Fac:=1.0/C.FreqScale;
  If M.YarnLogMul<>0 Then
   C.AttnFactor:=GetMscaleF(Fac,1.0)/GetMscaleF(Fac,M.YarnLogMul)
  Else C.AttnFactor:=GetMscaleF(Fac,1.0);
  C.AttnFactor:=C.AttnFactor*(1.0/(1.0+0.1*Ln(Fac)));
 End;
 C.AttnFactor:=C.AttnFactor*M.RopeAttnFactor;
 CD0:=CorrDim(M.NRot,C.NCtxOrig,C.BetaFast,C.FreqBase);
 CD1:=CorrDim(M.NRot,C.NCtxOrig,C.BetaSlow,C.FreqBase);
 C.CorrLo:=FFloor(CD0);
 If C.CorrLo<0 Then C.CorrLo:=0;
 C.CorrHi:=FCeil(CD1);
 If C.CorrHi>M.NRot-1 Then C.CorrHi:=M.NRot-1;
 { facteurs de frequences }
 C.Factors:=Nil;
 If Length(M.RopeFreqs)>0 Then C.Factors:=@M.RopeFreqs[0]
 Else If(NCtx>C.NCtxOrig)and(Length(M.RopeLong)>0)Then C.Factors:=@M.RopeLong[0]
 Else If Length(M.RopeShort)>0 Then C.Factors:=@M.RopeShort[0];
 C.UseSWA:=False;
 For I:=0 to M.NLayer-1 do If M.Layers[I].IsSWA Then C.UseSWA:=True;
End;

Procedure CtxClear(Var C:TCtx);
Begin
 C.NPast:=0;
End;

{ Decale le cache KV : supprime NDiscard positions apres NKeep }
Procedure CtxShift(Const M:TModel;Var C:TCtx;NKeep,NDiscard:LongInt);
Var
 L,J,NMove:LongInt;
 FB,FS:Single;
Begin
 If NDiscard<=0 Then Exit;
 NMove:=C.NPast-NKeep-NDiscard;
 If NMove<0 Then NMove:=0;
 For L:=0 to M.NLayer-1 do Begin
  If NMove>0 Then Begin
   Move((C.KC[L]+(Int64(NKeep+NDiscard)*C.KD))^,(C.KC[L]+Int64(NKeep)*C.KD)^,Int64(NMove)*C.KD*4);
   Move((C.VC[L]+(Int64(NKeep+NDiscard)*C.VD))^,(C.VC[L]+Int64(NKeep)*C.VD)^,Int64(NMove)*C.VD*4);
  End;
  If M.Layers[L].IsSWA Then Begin FB:=M.RopeBaseSWA;FS:=M.RopeScaleSWA;End
                       Else Begin FB:=C.FreqBase;FS:=C.FreqScale;End;
  RopeCacheInit(C,C.RopeCs,-NDiscard,FB,FS,M.NRot,0,1.0,C.Factors);
  For J:=0 to NMove-1 do
   ApplyRope(C.KC[L]+Int64(NKeep+J)*C.KD,M.NHeadKV,M.HeadK,C.RopeCs,M.NRot,M.RopeNeox);
 End;
 Dec(C.NPast,NDiscard);
End;

{ Retire les positions >= P du cache }
Procedure CtxTruncate(Var C:TCtx;P:LongInt);
Begin
 If P<C.NPast Then C.NPast:=P;
End;

Procedure MatMulT(Const M:TModel;Idx:LongInt;X,Y:PSingle;NTok:LongInt;Var C:TCtx);
Begin
 MatMulPtr(M.G.T[Idx].Typ,M.G.T[Idx].Data,M.G.T[Idx].Ne[0],M.G.T[Idx].Ne[1],X,Y,NTok,C.W4);
End;

{ Produit matrice-vecteur sur un expert (tenseur 3D) }
Procedure MatMulExpert(Const M:TModel;Idx,E:LongInt;X,Y:PSingle;Var C:TCtx);
Var
 T:^TTensorInfo;
Begin
 T:=@M.G.T[Idx];
 MatMulPtr(T^.Typ,T^.Data+Int64(E)*T^.Ne[1]*RowBytes(T^.Typ,T^.Ne[0]),T^.Ne[0],T^.Ne[1],X,Y,1,C.W4);
End;

{ ------------------------------------------------------------------ }
{ Passe avant                                                         }
{ ------------------------------------------------------------------ }

Procedure AddBias(Y:PSingle;Const B:TSingleArray;N,NTok:LongInt);
Var
 T,I:LongInt;
Begin
 If Length(B)=0 Then Exit;
 For T:=0 to NTok-1 do
  For I:=0 to N-1 do Y[T*N+I]:=Y[T*N+I]+B[I];
End;

Procedure HeadNorm(V:PSingle;NHeads,HeadDim:LongInt;Const W:TSingleArray;Eps:Single);
Var
 H:LongInt;
Begin
 For H:=0 to NHeads-1 do
  RMSNorm(V+H*HeadDim,@W[0],V+H*HeadDim,HeadDim,Eps);
End;

Procedure Decode(Const M:TModel;Var C:TCtx;Toks:PLongInt;N,Pos0:LongInt);
Var
 L,T,I,J,H,G_,NRep,P,JMin,D,FF,E,Sel,K2,Q_:LongInt;
 Lay:^TLayer;
 Xt,Xn,Qv,Kv,Vv,Aov,Sc:PSingle;
 Scale,Mx,Sum,S_,Cap,Inv:Single;
 Cs:PSingle;
 EmbT:^TTensorInfo;
 Neox:Boolean;
 FB,FS:Single;
 TopW:Array[0..63]of Single;
 TopI:Array[0..63]of LongInt;
 Tot:Single;
 FuT,FgT:PSingle;
 Pr:PSingle;
 Best:LongInt;
 BV:Single;
 Used:Array[0..255]of Boolean;
 UseSw:Boolean;
Begin
 D:=M.NEmbd;
 Neox:=M.RopeNeox;
 EmbT:=@M.G.T[M.TokEmbd];
 { plongement des jetons }
 For T:=0 to N-1 do Begin
  DequantRow(EmbT^.Typ,EmbT^.Data+Int64(Toks[T])*RowBytes(EmbT^.Typ,EmbT^.Ne[0]),C.X+T*D,D);
  If M.EmbScale<>1.0 Then For I:=0 to D-1 do C.X[T*D+I]:=C.X[T*D+I]*M.EmbScale;
 End;
 { tables de rotation }
 For T:=0 to N-1 do Begin
  RopeCacheInit(C,C.RopeCs+T*M.NRot,Pos0+T,C.FreqBase,C.FreqScale,M.NRot,C.ExtFactor,C.AttnFactor,C.Factors);
  If C.UseSWA Then
   RopeCacheInit(C,C.RopeCsS+T*M.NRot,Pos0+T,M.RopeBaseSWA,M.RopeScaleSWA,M.NRot,C.ExtFactor,C.AttnFactor,C.Factors);
 End;
 Scale:=M.AttnScale;
 If Scale=0 Then Scale:=1.0/Sqrt(M.HeadK);
 NRep:=M.NHead div M.NHeadKV;
 For L:=0 to M.NLayer-1 do Begin
  Lay:=@M.Layers[L];
  UseSw:=Lay^.IsSWA and(M.NSwa>0);
  { --- attention --- }
  For T:=0 to N-1 do
   RMSNorm(C.X+T*D,@Lay^.AttnNorm[0],C.XN+T*D,D,M.NormEps);
  If Lay^.Wqkv>=0 Then Begin
   MatMulT(M,Lay^.Wqkv,C.XN,C.QKV,N,C);
   J:=C.QD+C.KD+C.VD;
   For T:=0 to N-1 do Begin
    Move(C.QKV[T*J],C.Q[T*C.QD],C.QD*4);
    Move(C.QKV[T*J+C.QD],C.Kb[T*C.KD],C.KD*4);
    Move(C.QKV[T*J+C.QD+C.KD],C.Vb[T*C.VD],C.VD*4);
   End;
  End
   Else Begin
    MatMulT(M,Lay^.Wq,C.XN,C.Q,N,C);
    MatMulT(M,Lay^.Wk,C.XN,C.Kb,N,C);
    MatMulT(M,Lay^.Wv,C.XN,C.Vb,N,C);
   End;
  AddBias(C.Q,Lay^.Bq,C.QD,N);
  AddBias(C.Kb,Lay^.Bk,C.KD,N);
  AddBias(C.Vb,Lay^.Bv,C.VD,N);
  If Lay^.IsSWA and C.UseSWA Then Cs:=C.RopeCsS Else Cs:=C.RopeCs;
  For T:=0 to N-1 do Begin
   If Length(Lay^.QNorm)>0 Then HeadNorm(C.Q+T*C.QD,M.NHead,M.HeadK,Lay^.QNorm,M.NormEps);
   If Length(Lay^.KNorm)>0 Then HeadNorm(C.Kb+T*C.KD,M.NHeadKV,M.HeadK,Lay^.KNorm,M.NormEps);
   ApplyRope(C.Q+T*C.QD,M.NHead,M.HeadK,Cs+T*M.NRot,M.NRot,Neox);
   ApplyRope(C.Kb+T*C.KD,M.NHeadKV,M.HeadK,Cs+T*M.NRot,M.NRot,Neox);
   Move(C.Kb[T*C.KD],C.KC[L][Int64(Pos0+T)*C.KD],C.KD*4);
   Move(C.Vb[T*C.VD],C.VC[L][Int64(Pos0+T)*C.VD],C.VD*4);
  End;
  { produit scalaire causal }
  For T:=0 to N-1 do Begin
   P:=Pos0+T;
   JMin:=0;
   If UseSw Then Begin
    JMin:=P-M.NSwa+1;
    If JMin<0 Then JMin:=0;
   End;
   For H:=0 to M.NHead-1 do Begin
    G_:=H div NRep;
    Qv:=C.Q+T*C.QD+H*M.HeadK;
    Sc:=C.Scores;
    Mx:=-1.0e30;
    For J:=JMin to P do Begin
     Kv:=C.KC[L]+Int64(J)*C.KD+G_*M.HeadK;
     S_:=Dot1(Qv,Kv,M.HeadK)*Scale;
     If M.AttnSoftCap>0 Then S_:=M.AttnSoftCap*FTanh(S_/M.AttnSoftCap);
     Sc[J-JMin]:=S_;
     If S_>Mx Then Mx:=S_;
    End;
    Sum:=0;
    For J:=0 to P-JMin do Begin
     S_:=Exp(Sc[J]-Mx);
     Sc[J]:=S_;
     Sum:=Sum+S_;
    End;
    Inv:=1.0/Sum;
    Aov:=C.AO+T*C.AOD+H*M.HeadV;
    For I:=0 to M.HeadV-1 do Aov[I]:=0;
    For J:=JMin to P do Begin
     S_:=Sc[J-JMin]*Inv;
     Vv:=C.VC[L]+Int64(J)*C.VD+G_*M.HeadV;
     For I:=0 to M.HeadV-1 do Aov[I]:=Aov[I]+S_*Vv[I];
    End;
   End;
  End;
  MatMulT(M,Lay^.Wo,C.AO,C.OB,N,C);
  AddBias(C.OB,Lay^.Bo,D,N);
  If Length(Lay^.PostAttnNorm)>0 Then
   For T:=0 to N-1 do RMSNorm(C.OB+T*D,@Lay^.PostAttnNorm[0],C.OB+T*D,D,M.NormEps);
  If M.ResidualScale<>1.0 Then
   For T:=0 to N*D-1 do C.OB[T]:=C.OB[T]*M.ResidualScale;
  For T:=0 to N*D-1 do C.X[T]:=C.X[T]+C.OB[T];
  { --- reseau feed-forward --- }
  For T:=0 to N-1 do
   RMSNorm(C.X+T*D,@Lay^.FfnNorm[0],C.XN+T*D,D,M.NormEps);
  If Lay^.GateInp>=0 Then Begin
   { melange d'experts }
   MatMulT(M,Lay^.GateInp,C.XN,C.RL,N,C);
   For T:=0 to N-1 do Begin
    Pr:=C.RL+T*M.NExpert;
    Mx:=Pr[0];
    For E:=1 to M.NExpert-1 do If Pr[E]>Mx Then Mx:=Pr[E];
    Sum:=0;
    For E:=0 to M.NExpert-1 do Begin Pr[E]:=Exp(Pr[E]-Mx);Sum:=Sum+Pr[E];End;
    For E:=0 to M.NExpert-1 do Pr[E]:=Pr[E]/Sum;
    FillChar(Used,SizeOf(Used),0);
    Tot:=0;
    For Sel:=0 to M.NExpertUsed-1 do Begin
     Best:=-1;BV:=-1;
     For E:=0 to M.NExpert-1 do
      If(not Used[E])and(Pr[E]>BV)Then Begin BV:=Pr[E];Best:=E;End;
     Used[Best]:=True;
     TopI[Sel]:=Best;TopW[Sel]:=BV;
     Tot:=Tot+BV;
    End;
    If Tot<6.103515625e-5 Then Tot:=6.103515625e-5;
    For Sel:=0 to M.NExpertUsed-1 do Begin
     TopW[Sel]:=TopW[Sel]/Tot;
     If(M.ExpertWScale<>0)and(M.ExpertWScale<>1.0)Then TopW[Sel]:=TopW[Sel]*M.ExpertWScale;
    End;
    For I:=0 to D-1 do C.Acc[I]:=0;
    FF:=M.G.T[Lay^.UpExps].Ne[1];
    FgT:=C.Tmp;
    FuT:=C.Tmp+FF;
    For Sel:=0 to M.NExpertUsed-1 do Begin
     E:=TopI[Sel];
     MatMulExpert(M,Lay^.GateExps,E,C.XN+T*D,FgT,C);
     MatMulExpert(M,Lay^.UpExps,E,C.XN+T*D,FuT,C);
     For I:=0 to FF-1 do FgT[I]:=ActSilu(FgT[I])*FuT[I];
     MatMulExpert(M,Lay^.DownExps,E,FgT,C.OB+T*D,C);
     For I:=0 to D-1 do C.Acc[I]:=C.Acc[I]+TopW[Sel]*C.OB[T*D+I];
    End;
    For I:=0 to D-1 do C.OB[T*D+I]:=C.Acc[I];
   End;
  End
   Else Begin
    FF:=M.G.T[Lay^.FfnDown].Ne[0];
    If Lay^.FfnGate>=0 Then Begin
     MatMulT(M,Lay^.FfnGate,C.XN,C.FG,N,C);
     MatMulT(M,Lay^.FfnUp,C.XN,C.FU,N,C);
     If M.GeluFFN Then
      For T:=0 to N*FF-1 do C.Hid[T]:=ActGelu(C.FG[T])*C.FU[T]
     Else
      For T:=0 to N*FF-1 do C.Hid[T]:=ActSilu(C.FG[T])*C.FU[T];
    End
     Else Begin
      { gate et up fusionnes dans ffn_up (2*n_ff lignes) }
      MatMulT(M,Lay^.FfnUp,C.XN,C.FU,N,C);
      For T:=0 to N-1 do
       For I:=0 to FF-1 do
        C.Hid[T*FF+I]:=ActSilu(C.FU[T*2*FF+I])*C.FU[T*2*FF+FF+I];
     End;
    MatMulT(M,Lay^.FfnDown,C.Hid,C.OB,N,C);
   End;
  If Length(Lay^.PostFfnNorm)>0 Then
   For T:=0 to N-1 do RMSNorm(C.OB+T*D,@Lay^.PostFfnNorm[0],C.OB+T*D,D,M.NormEps);
  If M.ResidualScale<>1.0 Then
   For T:=0 to N*D-1 do C.OB[T]:=C.OB[T]*M.ResidualScale;
  For T:=0 to N*D-1 do C.X[T]:=C.X[T]+C.OB[T];
 End;
 { --- sortie : dernier jeton uniquement --- }
 RMSNorm(C.X+(N-1)*D,@M.OutputNorm[0],C.XN,D,M.NormEps);
 MatMulT(M,M.Output,C.XN,C.Logits,1,C);
 If Length(M.OutputBias)>0 Then
  For I:=0 to M.NVocab-1 do C.Logits[I]:=C.Logits[I]+M.OutputBias[I];
 If M.LogitScale<>0 Then
  For I:=0 to M.NVocab-1 do C.Logits[I]:=C.Logits[I]/M.LogitScale;
 If M.FinalSoftCap>0 Then
  For I:=0 to M.NVocab-1 do C.Logits[I]:=M.FinalSoftCap*FTanh(C.Logits[I]/M.FinalSoftCap);
 If Pos0+N>C.NPast Then C.NPast:=Pos0+N;
End;

{ ------------------------------------------------------------------ }
{ JSON minimal                                                        }
{ ------------------------------------------------------------------ }

Const
 JK_NULL=0; JK_BOOL=1; JK_INT=2; JK_FLOAT=3; JK_STR=4; JK_ARR=5; JK_OBJ=6;

Type
 PJ=^TJ;
 TJ=Record
  Kind:LongInt;
  B:Boolean;
  I:Int64;
  F:Double;
  S:AnsiString;
  Items:Array of PJ;
  Keys:TStrArray;
 End;

Var
 JErr:AnsiString;

Function JNew(K:LongInt):PJ;
Var
 P:PJ;
Begin
 New(P);
 P^.Kind:=K;P^.B:=False;P^.I:=0;P^.F:=0;P^.S:='';
 SetLength(P^.Items,0);SetLength(P^.Keys,0);
 JNew:=P;
End;

Procedure JAddItem(A:PJ;V:PJ);
Var
 N:LongInt;
Begin
 N:=Length(A^.Items);
 SetLength(A^.Items,N+1);
 A^.Items[N]:=V;
End;

Procedure JAddKey(A:PJ;Const K:AnsiString;V:PJ);
Var
 N,I:LongInt;
Begin
 For I:=0 to High(A^.Keys)do
  If A^.Keys[I]=K Then Begin A^.Items[I]:=V;Exit;End;
 N:=Length(A^.Items);
 SetLength(A^.Items,N+1);
 SetLength(A^.Keys,N+1);
 A^.Items[N]:=V;
 A^.Keys[N]:=K;
End;

Function JGet(O:PJ;Const K:AnsiString):PJ;
Var
 I:LongInt;
Begin
 JGet:=Nil;
 If(O=Nil)or(O^.Kind<>JK_OBJ)Then Exit;
 For I:=0 to High(O^.Keys)do
  If O^.Keys[I]=K Then Begin JGet:=O^.Items[I];Exit;End;
End;

Function JHas(O:PJ;Const K:AnsiString):Boolean;
Begin
 JHas:=JGet(O,K)<>Nil;
End;

Var
 JSrc:AnsiString;
 JPos:LongInt;
 JFail:Boolean;

Procedure JSkipWs;
Begin
 While(JPos<=Length(JSrc))and(JSrc[JPos]in[' ',#9,#10,#13])do Inc(JPos);
End;

Function JParseValue():PJ;Forward;

Function JParseString:AnsiString;
Var
 R:AnsiString;
 C:Char;
 Cp,Lo:LongWord;
Begin
 R:='';
 Inc(JPos);
 While True do Begin
  If JPos>Length(JSrc)Then Begin JFail:=True;JErr:='chaîne non terminée';Break;End;
  C:=JSrc[JPos];
  If C='"' Then Begin Inc(JPos);Break;End;
  If C='\' Then Begin
   Inc(JPos);
   If JPos>Length(JSrc)Then Begin JFail:=True;Break;End;
   C:=JSrc[JPos];
   Case C of
    'n':R:=R+#10;
    't':R:=R+#9;
    'r':R:=R+#13;
    'b':R:=R+#8;
    'f':R:=R+#12;
    '/':R:=R+'/';
    '\':R:=R+'\';
    '"':R:=R+'"';
    'u':Begin
     If JPos+4>Length(JSrc)Then Begin JFail:=True;Break;End;
     Cp:=LongWord(HexVal(JSrc[JPos+1]))*4096+LongWord(HexVal(JSrc[JPos+2]))*256+
         LongWord(HexVal(JSrc[JPos+3]))*16+LongWord(HexVal(JSrc[JPos+4]));
     Inc(JPos,4);
     If(Cp>=$D800)and(Cp<=$DBFF)and(JPos+6<=Length(JSrc))and(JSrc[JPos+1]='\')and(JSrc[JPos+2]='u')Then Begin
      Lo:=LongWord(HexVal(JSrc[JPos+3]))*4096+LongWord(HexVal(JSrc[JPos+4]))*256+
          LongWord(HexVal(JSrc[JPos+5]))*16+LongWord(HexVal(JSrc[JPos+6]));
      If(Lo>=$DC00)and(Lo<=$DFFF)Then Begin
       Cp:=$10000+((Cp-$D800)shl 10)+(Lo-$DC00);
       Inc(JPos,6);
      End;
     End;
     R:=R+CpToUtf8(Cp);
    End;
    Else Begin JFail:=True;JErr:='échappement inconnu';End;
   End;
   Inc(JPos);
  End
   Else Begin
    R:=R+C;
    Inc(JPos);
   End;
 End;
 JParseString:=R;
End;

Function JParseValue():PJ;
Var
 V,E:PJ;
 K:AnsiString;
 St:LongInt;
 T:AnsiString;
 IsF:Boolean;
 Code:LongInt;
 D:Double;
 N:Int64;
Begin
 JParseValue:=Nil;
 JSkipWs;
 If(JPos>Length(JSrc))or JFail Then Begin JFail:=True;Exit;End;
 Case JSrc[JPos]of
  '{':Begin
   V:=JNew(JK_OBJ);
   Inc(JPos);
   JSkipWs;
   If(JPos<=Length(JSrc))and(JSrc[JPos]='}')Then Begin Inc(JPos);JParseValue:=V;Exit;End;
   While True do Begin
    JSkipWs;
    If(JPos>Length(JSrc))or(JSrc[JPos]<>'"')Then Begin JFail:=True;JErr:='clé d''objet attendue';Exit;End;
    K:=JParseString;
    JSkipWs;
    If(JPos>Length(JSrc))or(JSrc[JPos]<>':')Then Begin JFail:=True;JErr:='":" attendu';Exit;End;
    Inc(JPos);
    E:=JParseValue();
    If JFail Then Exit;
    JAddKey(V,K,E);
    JSkipWs;
    If JPos>Length(JSrc)Then Begin JFail:=True;Exit;End;
    If JSrc[JPos]=',' Then Begin Inc(JPos);Continue;End;
    If JSrc[JPos]='}' Then Begin Inc(JPos);Break;End;
    JFail:=True;JErr:='"," ou "}" attendu';Exit;
   End;
   JParseValue:=V;
  End;
  '[':Begin
   V:=JNew(JK_ARR);
   Inc(JPos);
   JSkipWs;
   If(JPos<=Length(JSrc))and(JSrc[JPos]=']')Then Begin Inc(JPos);JParseValue:=V;Exit;End;
   While True do Begin
    E:=JParseValue();
    If JFail Then Exit;
    JAddItem(V,E);
    JSkipWs;
    If JPos>Length(JSrc)Then Begin JFail:=True;Exit;End;
    If JSrc[JPos]=',' Then Begin Inc(JPos);Continue;End;
    If JSrc[JPos]=']' Then Begin Inc(JPos);Break;End;
    JFail:=True;JErr:='"," ou "]" attendu';Exit;
   End;
   JParseValue:=V;
  End;
  '"':Begin
   V:=JNew(JK_STR);
   V^.S:=JParseString;
   JParseValue:=V;
  End;
  't':Begin
   If Copy(JSrc,JPos,4)='true' Then Begin V:=JNew(JK_BOOL);V^.B:=True;Inc(JPos,4);JParseValue:=V;End
   Else JFail:=True;
  End;
  'f':Begin
   If Copy(JSrc,JPos,5)='false' Then Begin V:=JNew(JK_BOOL);Inc(JPos,5);JParseValue:=V;End
   Else JFail:=True;
  End;
  'n':Begin
   If Copy(JSrc,JPos,4)='null' Then Begin V:=JNew(JK_NULL);Inc(JPos,4);JParseValue:=V;End
   Else JFail:=True;
  End;
  Else Begin
   St:=JPos;
   IsF:=False;
   While(JPos<=Length(JSrc))and(JSrc[JPos]in['0'..'9','-','+','.','e','E'])do Begin
    If JSrc[JPos]in['.','e','E']Then IsF:=True;
    Inc(JPos);
   End;
   T:=Copy(JSrc,St,JPos-St);
   If T='' Then Begin JFail:=True;JErr:='valeur JSON inattendue';Exit;End;
   If IsF Then Begin
    Val(T,D,Code);
    If Code<>0 Then Begin JFail:=True;Exit;End;
    V:=JNew(JK_FLOAT);V^.F:=D;
   End
    Else Begin
     Val(T,N,Code);
     If Code<>0 Then Begin
      Val(T,D,Code);
      If Code<>0 Then Begin JFail:=True;Exit;End;
      V:=JNew(JK_FLOAT);V^.F:=D;
     End
      Else Begin V:=JNew(JK_INT);V^.I:=N;V^.F:=N;End;
    End;
   JParseValue:=V;
  End;
 End;
End;

Function JParse(Const S:AnsiString):PJ;
Var
 V:PJ;
Begin
 JSrc:=S;JPos:=1;JFail:=False;JErr:='';
 V:=JParseValue();
 If not JFail Then Begin
  JSkipWs;
  If JPos<=Length(JSrc)Then JFail:=True;
 End;
 If JFail Then Begin
  If JErr='' Then JErr:='JSON invalide';
  JParse:=Nil;
 End
  Else JParse:=V;
End;

Function JEscapeStr(Const S:AnsiString):AnsiString;
Var
 R:AnsiString;
 I:LongInt;
 C:Byte;
Begin
 R:='"';
 For I:=1 to Length(S)do Begin
  C:=Ord(S[I]);
  Case C of
   34:R:=R+'\"';
   92:R:=R+'\\';
   8:R:=R+'\b';
   9:R:=R+'\t';
   10:R:=R+'\n';
   12:R:=R+'\f';
   13:R:=R+'\r';
   Else If C<32 Then R:=R+'\u00'+LoStr(HexStr2(C))
        Else R:=R+Chr(C);
  End;
 End;
 JEscapeStr:=R+'"';
End;

Function JFloatStr(F:Double):AnsiString;
Var
 S:AnsiString;
 I:LongInt;
Begin
 If(Frac(F)=0)and(Abs(F)<1.0e15)Then Begin
  Str(F:0:1,S);
  JFloatStr:=S;
  Exit;
 End;
 For I:=1 to 17 do Begin
  Str(F:0:I,S);
  If Abs(StrToFloatDef(S,0)-F)<=Abs(F)*1.0e-16 Then Break;
 End;
 While(Length(S)>1)and(S[Length(S)]='0')and(Pos('.',S)>0)do Delete(S,Length(S),1);
 JFloatStr:=S;
End;

Function JDump(V:PJ):AnsiString;
Var
 R:AnsiString;
 I:LongInt;
Begin
 If V=Nil Then Begin JDump:='null';Exit;End;
 Case V^.Kind of
  JK_NULL:JDump:='null';
  JK_BOOL:If V^.B Then JDump:='true' Else JDump:='false';
  JK_INT:JDump:=IStr(V^.I);
  JK_FLOAT:JDump:=JFloatStr(V^.F);
  JK_STR:JDump:=JEscapeStr(V^.S);
  JK_ARR:Begin
   R:='[';
   For I:=0 to High(V^.Items)do Begin
    If I>0 Then R:=R+',';
    R:=R+JDump(V^.Items[I]);
   End;
   JDump:=R+']';
  End;
  Else Begin
   R:='{';
   For I:=0 to High(V^.Items)do Begin
    If I>0 Then R:=R+',';
    R:=R+JEscapeStr(V^.Keys[I])+':'+JDump(V^.Items[I]);
   End;
   JDump:=R+'}';
  End;
 End;
End;

Function JIsTrue(V:PJ):Boolean;
Begin
 JIsTrue:=(V<>Nil)and(V^.Kind=JK_BOOL)and V^.B;
End;

{ ------------------------------------------------------------------ }
{ Convertisseur JSON schema -> grammaire GBNF                         }
{ ------------------------------------------------------------------ }

Type
 TRuleKV=Record
  Name,Rule:AnsiString;
 End;

Var
 SRules:Array of TRuleKV;
 SRefsInProgress:TStrArray;
 SErrors,SWarnings:TStrArray;
 SRoot:PJ;
 SDotAll:Boolean;

Const
 NPrim=12;
 NFmt=6;

Type
 TBuiltin=Record
  Name,Content,Deps:AnsiString;
 End;

Var
 PrimRules:Array[0..NPrim-1]of TBuiltin;
 FmtRules:Array[0..NFmt-1]of TBuiltin;

Procedure SetB(Var B:TBuiltin;Const N,C,D:AnsiString);
Begin
 B.Name:=N;B.Content:=C;B.Deps:=D;
End;

Procedure InitBuiltins;
Begin
 SetB(PrimRules[0],'boolean','("true" | "false")','');
 SetB(PrimRules[1],'decimal-part','[0-9]{1,16}','');
 SetB(PrimRules[2],'integral-part','[0] | [1-9] [0-9]{0,15}','');
 SetB(PrimRules[3],'number','("-"? integral-part) ("." decimal-part)? ([eE] [-+]? integral-part)?','integral-part,decimal-part');
 SetB(PrimRules[4],'integer','("-"? integral-part)','integral-part');
 SetB(PrimRules[5],'value','object | array | string | number | boolean | null','object,array,string,number,boolean,null');
 SetB(PrimRules[6],'object','"{" space ( string ":" space value ("," space string ":" space value)* )? space "}"','string,value');
 SetB(PrimRules[7],'array','"[" space ( value ("," space value)* )? space "]"','value');
 SetB(PrimRules[8],'uuid','"\"" [0-9a-fA-F]{8} "-" [0-9a-fA-F]{4} "-" [0-9a-fA-F]{4} "-" [0-9a-fA-F]{4} "-" [0-9a-fA-F]{12} "\""','');
 SetB(PrimRules[9],'char','[^"\\\x7F\x00-\x1F] | [\\] (["\\bfnrt] | "u" [0-9a-fA-F]{4})','');
 SetB(PrimRules[10],'string','"\"" char* "\""','char');
 SetB(PrimRules[11],'null','"null"','');
 SetB(FmtRules[0],'date','[0-9]{4} "-" ( "0" [1-9] | "1" [0-2] ) "-" ( "0" [1-9] | [1-2] [0-9] | "3" [0-1] )','');
 SetB(FmtRules[1],'time','([01] [0-9] | "2" [0-3]) ":" [0-5] [0-9] ":" [0-5] [0-9] ( "." [0-9]{3} )? ( "Z" | ( "+" | "-" ) ( [01] [0-9] | "2" [0-3] ) ":" [0-5] [0-9] )','');
 SetB(FmtRules[2],'date-time','date "T" time','date,time');
 SetB(FmtRules[3],'date-string','"\"" date "\""','date');
 SetB(FmtRules[4],'time-string','"\"" time "\""','time');
 SetB(FmtRules[5],'date-time-string','"\"" date-time "\""','date-time');
End;

Function FindBuiltin(Const N:AnsiString;Var B:TBuiltin):Boolean;
Var
 I:LongInt;
Begin
 FindBuiltin:=True;
 For I:=0 to NPrim-1 do If PrimRules[I].Name=N Then Begin B:=PrimRules[I];Exit;End;
 For I:=0 to NFmt-1 do If FmtRules[I].Name=N Then Begin B:=FmtRules[I];Exit;End;
 FindBuiltin:=False;
End;

Function IsReservedName(Const N:AnsiString):Boolean;
Var
 B:TBuiltin;
Begin
 IsReservedName:=(N='root')or FindBuiltin(N,B);
End;

Function RuleIndex(Const N:AnsiString):LongInt;
Var
 I:LongInt;
Begin
 RuleIndex:=-1;
 For I:=0 to High(SRules)do If SRules[I].Name=N Then Begin RuleIndex:=I;Exit;End;
End;

Procedure SetRule(Const N,R:AnsiString);
Var
 I:LongInt;
Begin
 I:=RuleIndex(N);
 If I<0 Then Begin
  I:=Length(SRules);
  SetLength(SRules,I+1);
  SRules[I].Name:=N;
 End;
 SRules[I].Rule:=R;
End;

Function SchemaEscName(Const N:AnsiString):AnsiString;
Var
 R:AnsiString;
 I:LongInt;
 Last:Boolean;
Begin
 R:='';Last:=False;
 For I:=1 to Length(N)do Begin
  If N[I]in['a'..'z','A'..'Z','0'..'9','-']Then Begin R:=R+N[I];Last:=False;End
  Else Begin
   If not Last Then R:=R+'-';
   Last:=True;
  End;
 End;
 SchemaEscName:=R;
End;

Function AddRule(Const Name,Rule:AnsiString):AnsiString;
Var
 Esc,Key:AnsiString;
 I,K:LongInt;
Begin
 Esc:=SchemaEscName(Name);
 I:=RuleIndex(Esc);
 If(I<0)or(SRules[I].Rule=Rule)Then Begin
  SetRule(Esc,Rule);
  AddRule:=Esc;
  Exit;
 End;
 K:=0;
 While True do Begin
  Key:=Esc+IStr(K);
  I:=RuleIndex(Key);
  If(I<0)or(SRules[I].Rule=Rule)Then Break;
  Inc(K);
 End;
 SetRule(Key,Rule);
 AddRule:=Key;
End;

Function AddPrimitive(Const Name:AnsiString;Const B:TBuiltin):AnsiString;
Var
 N:AnsiString;
 Deps:TStrArray;
 I:LongInt;
 D:TBuiltin;
Begin
 N:=AddRule(Name,B.Content);
 If B.Deps<>'' Then Begin
  Deps:=SplitStr(B.Deps,',');
  For I:=0 to High(Deps)do Begin
   If not FindBuiltin(Deps[I],D)Then Begin
    AddStr(SErrors,'Rule '+Deps[I]+' not known');
    Continue;
   End;
   If RuleIndex(Deps[I])<0 Then AddPrimitive(Deps[I],D);
  End;
 End;
 AddPrimitive:=N;
End;

Function PrimRule(Const N:AnsiString):AnsiString;
Var
 B:TBuiltin;
Begin
 FindBuiltin(N,B);
 PrimRule:=AddPrimitive(N,B);
End;

Function VisitPrim(Const RuleName,TypeName:AnsiString):AnsiString;
Var
 B:TBuiltin;
Begin
 FindBuiltin(TypeName,B);
 If RuleName='root' Then VisitPrim:=AddPrimitive('root',B)
                    Else VisitPrim:=AddPrimitive(TypeName,B);
End;

Function FormatLiteral(Const S:AnsiString):AnsiString;
Var
 R:AnsiString;
 I:LongInt;
Begin
 R:='"';
 For I:=1 to Length(S)do Begin
  Case S[I]of
   #13:R:=R+'\r';
   #10:R:=R+'\n';
   '"':R:=R+'\"';
   '\':R:=R+'\\';
   Else R:=R+S[I];
  End;
 End;
 FormatLiteral:=R+'"';
End;

Function BuildRepetition(Const Item:AnsiString;MinI,MaxI:LongInt;Const Sep:AnsiString):AnsiString;
Var
 HasMax:Boolean;
 R:AnsiString;
 NM:LongInt;
Begin
 HasMax:=MaxI<>MaxLongInt;
 If MaxI=0 Then Begin BuildRepetition:='';Exit;End;
 If(MinI=0)and(MaxI=1)Then Begin BuildRepetition:=Item+'?';Exit;End;
 If Sep='' Then Begin
  If(MinI=1)and not HasMax Then Begin BuildRepetition:=Item+'+';Exit;End;
  If(MinI=0)and not HasMax Then Begin BuildRepetition:=Item+'*';Exit;End;
  If HasMax Then BuildRepetition:=Item+'{'+IStr(MinI)+','+IStr(MaxI)+'}'
            Else BuildRepetition:=Item+'{'+IStr(MinI)+',}';
  Exit;
 End;
 If MinI=0 Then NM:=0 Else NM:=MinI-1;
 If HasMax Then R:=Item+' '+BuildRepetition('('+Sep+' '+Item+')',NM,MaxI-1,'')
           Else R:=Item+' '+BuildRepetition('('+Sep+' '+Item+')',NM,MaxI,'');
 If MinI=0 Then R:='('+R+')?';
 BuildRepetition:=R;
End;

Function StrRepeat(Const S:AnsiString;N:LongInt):AnsiString;
Var
 R:AnsiString;
 I:LongInt;
Begin
 R:='';
 For I:=1 to N do R:=R+S;
 StrRepeat:=R;
End;

Const
 I64Min=Int64($8000000000000000);
 I64Max=Int64($7FFFFFFFFFFFFFFF);

Procedure BuildMinMaxInt(MinV,MaxV:Int64;Var Outp:AnsiString;DecimalsLeft:LongInt;TopLevel:Boolean);
Var
 HasMin,HasMax:Boolean;
 LessDec,MinD,MaxD,Digits:LongInt;
 MinS,MaxS:AnsiString;
 C:Char;
 Len:LongInt;
 RangeStart:Char;

 Procedure DigitRange(F,T:Char);
 Begin
  Outp:=Outp+'[';
  If F=T Then Outp:=Outp+F Else Outp:=Outp+F+'-'+T;
  Outp:=Outp+']';
 End;

 Procedure MoreDigits(MnD,MxD:LongInt);
 Begin
  Outp:=Outp+'[0-9]';
  If(MnD=MxD)and(MnD=1)Then Exit;
  Outp:=Outp+'{'+IStr(MnD);
  If MxD<>MnD Then Begin
   Outp:=Outp+',';
   If MxD<>MaxLongInt Then Outp:=Outp+IStr(MxD);
  End;
  Outp:=Outp+'}';
 End;

 Procedure UniformRange(Const From,To_:AnsiString);
 Var
  I,SubLen:LongInt;
  FromSub,ToSub,SubZeros,SubNines:AnsiString;
  ToReached:Boolean;
 Begin
  I:=0;
  While(I<Length(From))and(I<Length(To_))and(From[I+1]=To_[I+1])do Inc(I);
  If I>0 Then Outp:=Outp+'"'+Copy(From,1,I)+'"';
  If(I<Length(From))and(I<Length(To_))Then Begin
   If I>0 Then Outp:=Outp+' ';
   SubLen:=Length(From)-I-1;
   If SubLen>0 Then Begin
    FromSub:=Copy(From,I+2,Length(From));
    ToSub:=Copy(To_,I+2,Length(To_));
    SubZeros:=StrRepeat('0',SubLen);
    SubNines:=StrRepeat('9',SubLen);
    ToReached:=False;
    Outp:=Outp+'(';
    If FromSub=SubZeros Then Begin
     DigitRange(From[I+1],Chr(Ord(To_[I+1])-1));
     Outp:=Outp+' ';
     MoreDigits(SubLen,SubLen);
    End
     Else Begin
      Outp:=Outp+'['+From[I+1]+'] ';
      Outp:=Outp+'(';
      UniformRange(FromSub,SubNines);
      Outp:=Outp+')';
      If From[I+1]<Chr(Ord(To_[I+1])-1)Then Begin
       Outp:=Outp+' | ';
       If ToSub=SubNines Then Begin
        DigitRange(Chr(Ord(From[I+1])+1),To_[I+1]);
        ToReached:=True;
       End
        Else DigitRange(Chr(Ord(From[I+1])+1),Chr(Ord(To_[I+1])-1));
       Outp:=Outp+' ';
       MoreDigits(SubLen,SubLen);
      End;
     End;
    If not ToReached Then Begin
     Outp:=Outp+' | ';
     DigitRange(To_[I+1],To_[I+1]);
     Outp:=Outp+' ';
     UniformRange(SubZeros,ToSub);
    End;
    Outp:=Outp+')';
   End
    Else Outp:=Outp+'['+From[I+1]+'-'+To_[I+1]+']';
  End;
 End;

Begin
 HasMin:=MinV<>I64Min;
 HasMax:=MaxV<>I64Max;
 If HasMin and HasMax Then Begin
  If(MinV<0)and(MaxV<0)Then Begin
   Outp:=Outp+'"-" (';
   BuildMinMaxInt(-MaxV,-MinV,Outp,DecimalsLeft,True);
   Outp:=Outp+')';
   Exit;
  End;
  If MinV<0 Then Begin
   Outp:=Outp+'"-" (';
   BuildMinMaxInt(0,-MinV,Outp,DecimalsLeft,True);
   Outp:=Outp+') | ';
   MinV:=0;
  End;
  MinS:=IStr(MinV);
  MaxS:=IStr(MaxV);
  MinD:=Length(MinS);
  MaxD:=Length(MaxS);
  For Digits:=MinD to MaxD-1 do Begin
   UniformRange(MinS,StrRepeat('9',Digits));
   MinS:='1'+StrRepeat('0',Digits);
   Outp:=Outp+' | ';
  End;
  UniformRange(MinS,MaxS);
  Exit;
 End;
 LessDec:=DecimalsLeft-1;
 If LessDec<1 Then LessDec:=1;
 If HasMin Then Begin
  If MinV<0 Then Begin
   Outp:=Outp+'"-" (';
   BuildMinMaxInt(I64Min,-MinV,Outp,DecimalsLeft,False);
   Outp:=Outp+') | [0] | [1-9] ';
   MoreDigits(0,DecimalsLeft-1);
  End
   Else If MinV=0 Then Begin
    If TopLevel Then Begin
     Outp:=Outp+'[0] | [1-9] ';
     MoreDigits(0,LessDec);
    End
     Else MoreDigits(1,DecimalsLeft);
   End
   Else If MinV<=9 Then Begin
    C:=Chr(Ord('0')+MinV);
    If TopLevel Then RangeStart:='1' Else RangeStart:='0';
    If C>RangeStart Then Begin
     DigitRange(RangeStart,Chr(Ord(C)-1));
     Outp:=Outp+' ';
     MoreDigits(1,LessDec);
     Outp:=Outp+' | ';
    End;
    DigitRange(C,'9');
    Outp:=Outp+' ';
    MoreDigits(0,LessDec);
   End
   Else Begin
    MinS:=IStr(MinV);
    Len:=Length(MinS);
    C:=MinS[1];
    If C>'1' Then Begin
     If TopLevel Then DigitRange('1',Chr(Ord(C)-1))Else DigitRange('0',Chr(Ord(C)-1));
     Outp:=Outp+' ';
     MoreDigits(Len,LessDec);
     Outp:=Outp+' | ';
    End;
    DigitRange(C,C);
    Outp:=Outp+' (';
    BuildMinMaxInt(StrToIntDef(Copy(MinS,2,Length(MinS)),0),I64Max,Outp,LessDec,False);
    Outp:=Outp+')';
    If C<'9' Then Begin
     Outp:=Outp+' | ';
     DigitRange(Chr(Ord(C)+1),'9');
     Outp:=Outp+' ';
     MoreDigits(Len-1,LessDec);
    End;
   End;
  Exit;
 End;
 If HasMax Then Begin
  If MaxV>=0 Then Begin
   If TopLevel Then Begin
    Outp:=Outp+'"-" [1-9] ';
    MoreDigits(0,LessDec);
    Outp:=Outp+' | ';
   End;
   BuildMinMaxInt(0,MaxV,Outp,DecimalsLeft,True);
  End
   Else Begin
    Outp:=Outp+'"-" (';
    BuildMinMaxInt(-MaxV,I64Max,Outp,DecimalsLeft,False);
    Outp:=Outp+')';
   End;
 End;
End;

Function SchemaVisit(S:PJ;Const Name:AnsiString):AnsiString;Forward;

{ --- gestion des motifs (pattern) --- }

Function GbnfEscapeLength(Const P:AnsiString;Pos:LongInt):LongInt;
Var
 NHex,I:LongInt;
 C:Char;
Begin
 GbnfEscapeLength:=0;
 If(Pos+1>Length(P))or(P[Pos]<>'\')Then Exit;
 Case P[Pos+1]of
  'x':NHex:=2;
  'u':NHex:=4;
  'U':NHex:=8;
  't','r','n','\','"','[',']','-':Begin GbnfEscapeLength:=2;Exit;End;
  Else Exit;
 End;
 If Pos+2+NHex-1>Length(P)Then Exit;
 For I:=Pos+2 to Pos+1+NHex do Begin
  C:=P[I];
  If not(C in['0'..'9','a'..'f','A'..'F'])Then Exit;
 End;
 GbnfEscapeLength:=2+NHex;
End;

Type
 EPatternErr=Record
  Kind:LongInt;     { 0 = ok, 1 = non supporte, 2 = invalide }
  Msg:AnsiString;
 End;

Var
 PatErr:EPatternErr;
 PatSub:AnsiString;
 PatI,PatLen,PatDepth:LongInt;
 PatName:AnsiString;
 SubRuleIds:Array of TRuleKV;

Type
 TLit=Record
  S:AnsiString;
  IsLit:Boolean;
 End;
 TLitSeq=Array of TLit;

Function LitToRule(Const L:TLit):AnsiString;
Begin
 If L.IsLit Then LitToRule:='"'+L.S+'"' Else LitToRule:=L.S;
End;

Procedure PatFail(K:LongInt;Const M:AnsiString);
Begin
 If PatErr.Kind=0 Then Begin PatErr.Kind:=K;PatErr.Msg:=M;End;
End;

Function PatTransform():TLit;
Var
 Seq:TLitSeq;
 NSeq:LongInt;
 C:Char;
 Br,Lit,Nxt:AnsiString;
 Sq:AnsiString;
 EL:LongInt;
 Item:TLit;
 Nums:TStrArray;
 MinT,MaxT:Int64;
 Sub:AnsiString;
 SubLit:Boolean;
 K:LongInt;
 NonLit:Boolean;

 Procedure Push(Const S:AnsiString;IsL:Boolean);
 Begin
  SetLength(Seq,NSeq+1);
  Seq[NSeq].S:=S;Seq[NSeq].IsLit:=IsL;
  Inc(NSeq);
 End;

 Function JoinSeq:TLit;
 Var
  R,Lt:AnsiString;
  J:LongInt;
  Res:TLit;
 Begin
  R:='';Lt:='';
  For J:=0 to NSeq-1 do Begin
   If Seq[J].IsLit Then Lt:=Lt+Seq[J].S
   Else Begin
    If Lt<>'' Then Begin
     If R<>'' Then R:=R+' ';
     R:=R+'"'+Lt+'"';
     Lt:='';
    End;
    If R<>'' Then R:=R+' ';
    R:=R+Seq[J].S;
   End;
  End;
  If Lt<>'' Then Begin
   If R<>'' Then R:=R+' ';
   R:=R+'"'+Lt+'"';
  End;
  Res.S:=R;Res.IsLit:=False;
  JoinSeq:=Res;
 End;

 Function IsNonLiteral(Ch:Char):Boolean;
 Begin
  IsNonLiteral:=Ch in['|','.','(',')','[',']','{','}','*','+','?','^','$'];
 End;

Begin
 NSeq:=0;
 SetLength(Seq,0);
 While PatI<=PatLen do Begin
  If PatErr.Kind<>0 Then Break;
  C:=PatSub[PatI];
  If C='.' Then Begin
   If SDotAll Then Push(AddRule('dot','[\U00000000-\U0010FFFF]'),False)
              Else Push(AddRule('dot','[^\x0A\x0D]'),False);
   Inc(PatI);
  End
  Else If C='(' Then Begin
   Inc(PatI);
   If(PatI<=PatLen)and(PatSub[PatI]='?')Then Begin
    If(PatI+1<=PatLen)and(PatSub[PatI+1]=':')Then Inc(PatI,2)
    Else Begin PatFail(1,'unsupported group syntax');Break;End;
   End;
   Inc(PatDepth);
   If PatDepth>100 Then Begin PatFail(1,'pattern nesting too deep');Break;End;
   Item:=PatTransform();
   Push('('+LitToRule(Item)+')',False);
  End
  Else If C=')' Then Begin
   Inc(PatI);
   If PatDepth=0 Then Begin PatFail(2,'unbalanced parentheses');Break;End;
   Dec(PatDepth);
   PatTransform:=JoinSeq;
   Exit;
  End
  Else If(C='^')or(C='$')Then Begin PatFail(1,'anchor inside the pattern');Break;End
  Else If C='[' Then Begin
   Sq:='[';
   Inc(PatI);
   While(PatI<=PatLen)and(PatSub[PatI]<>']')do Begin
    If PatSub[PatI]='\' Then Begin
     EL:=GbnfEscapeLength(PatSub,PatI);
     If EL=0 Then Begin PatFail(1,'unsupported escape in character class');Break;End;
     Sq:=Sq+Copy(PatSub,PatI,EL);
     Inc(PatI,EL);
    End
     Else Begin Sq:=Sq+PatSub[PatI];Inc(PatI);End;
   End;
   If PatErr.Kind<>0 Then Break;
   If PatI>PatLen Then Begin PatFail(2,'unterminated character class');Break;End;
   Sq:=Sq+']';
   Inc(PatI);
   Push(Sq,False);
  End
  Else If C='|' Then Begin Push('|',False);Inc(PatI);End
  Else If(C='*')or(C='+')or(C='?')Then Begin
   If NSeq=0 Then Begin PatFail(2,'nothing to repeat');Break;End;
   Seq[NSeq-1].S:=LitToRule(Seq[NSeq-1])+C;
   Seq[NSeq-1].IsLit:=False;
   Inc(PatI);
  End
  Else If C='{' Then Begin
   Br:='{';
   Inc(PatI);
   While(PatI<=PatLen)and(PatSub[PatI]<>'}')do Begin Br:=Br+PatSub[PatI];Inc(PatI);End;
   If PatI>PatLen Then Begin PatFail(1,'unterminated curly brackets');Break;End;
   Br:=Br+'}';
   Inc(PatI);
   Nums:=SplitStr(Copy(Br,2,Length(Br)-2),',');
   MinT:=0;MaxT:=MaxLongInt;
   If(Length(Nums)<>1)and(Length(Nums)<>2)Then Begin PatFail(1,'wrong number of values in curly brackets');Break;End;
   If Length(Nums)=1 Then Begin
    If not ParseInt(Nums[0],MinT)Then Begin PatFail(1,'invalid number in curly brackets');Break;End;
    MaxT:=MinT;
   End
    Else Begin
     If Nums[0]<>'' Then If not ParseInt(Nums[0],MinT)Then Begin PatFail(1,'invalid number in curly brackets');Break;End;
     If Nums[1]<>'' Then If not ParseInt(Nums[1],MaxT)Then Begin PatFail(1,'invalid number in curly brackets');Break;End;
    End;
   If NSeq=0 Then Begin PatFail(2,'nothing to repeat');Break;End;
   Sub:=Seq[NSeq-1].S;
   SubLit:=Seq[NSeq-1].IsLit;
   If not SubLit Then Begin
    K:=-1;
    For EL:=0 to High(SubRuleIds)do If SubRuleIds[EL].Name=Sub Then K:=EL;
    If K<0 Then Begin
     K:=Length(SubRuleIds);
     SetLength(SubRuleIds,K+1);
     SubRuleIds[K].Name:=Sub;
     SubRuleIds[K].Rule:=AddRule(PatName+'-'+IStr(K+1),Sub);
    End;
    Sub:=SubRuleIds[K].Rule;
   End;
   If SubLit Then Seq[NSeq-1].S:=BuildRepetition('"'+Sub+'"',MinT,MaxT,'')
             Else Seq[NSeq-1].S:=BuildRepetition(Sub,MinT,MaxT,'');
   Seq[NSeq-1].IsLit:=False;
  End
  Else Begin
   Lit:='';
   While PatI<=PatLen do Begin
    If PatSub[PatI]='\' Then Begin
     If PatI=PatLen Then Begin PatFail(2,'trailing backslash');Break;End;
     Nxt:=PatSub[PatI+1];
     If Nxt[1]in['^','$','.','[',']','(',')','|','{','}','*','+','?']Then Begin
      Inc(PatI);
      Lit:=Lit+PatSub[PatI];
      Inc(PatI);
     End
      Else Begin
       EL:=GbnfEscapeLength(PatSub,PatI);
       If EL=0 Then Begin PatFail(1,'unsupported escape');Break;End;
       Lit:=Lit+Copy(PatSub,PatI,EL);
       Inc(PatI,EL);
      End;
    End
    Else If PatSub[PatI]='"' Then Begin Lit:=Lit+'\"';Inc(PatI);End
    Else Begin
     NonLit:=IsNonLiteral(PatSub[PatI]);
     If(not NonLit)and((PatI=PatLen)or(Lit='')or(PatSub[PatI+1]='.')or not IsNonLiteral(PatSub[PatI+1]))Then Begin
      Lit:=Lit+PatSub[PatI];Inc(PatI);
     End
      Else Break;
    End;
   End;
   If PatErr.Kind<>0 Then Break;
   If Lit='' Then Begin PatFail(1,'unsupported character: '+C);Break;End;
   Push(Lit,True);
  End;
 End;
 PatTransform:=JoinSeq;
End;

Function VisitPattern(Const Pattern,Name:AnsiString):AnsiString;
Var
 Snap:Array of TRuleKV;
 R:TLit;
Begin
 Snap:=Copy(SRules,0,Length(SRules));
 If(Length(Pattern)<2)or(Pattern[1]<>'^')or(Pattern[Length(Pattern)]<>'$')Then Begin
  AddStr(SWarnings,'pattern '+Pattern+' is not supported (not anchored with ''^'' and ''$''), accepting any string');
  VisitPattern:=AddRule(Name,PrimRule('string'));
  Exit;
 End;
 PatSub:=Copy(Pattern,2,Length(Pattern)-2);
 PatI:=1;PatLen:=Length(PatSub);PatDepth:=0;PatName:=Name;
 PatErr.Kind:=0;PatErr.Msg:='';
 SetLength(SubRuleIds,0);
 R:=PatTransform();
 If(PatErr.Kind=0)and(PatDepth<>0)Then PatFail(2,'unbalanced parentheses');
 If PatErr.Kind=1 Then Begin
  SRules:=Snap;
  AddStr(SWarnings,'pattern '+Pattern+' is not supported ('+PatErr.Msg+'), accepting any string');
  VisitPattern:=AddRule(Name,PrimRule('string'));
  Exit;
 End;
 If PatErr.Kind=2 Then Begin
  SRules:=Snap;
  AddStr(SErrors,'Invalid pattern '+Pattern+': '+PatErr.Msg);
  VisitPattern:='';
  Exit;
 End;
 VisitPattern:=AddRule(Name,'"\"" ('+LitToRule(R)+') "\""');
End;

{ --- chaines interdites (trie) --- }

Type
 TTrieNode=Record
  Cps:Array of LongInt;
  Kids:Array of LongInt;
  Terminal:Boolean;
 End;

Var
 TrieNodes:Array of TTrieNode;

Function TrieNewNode:LongInt;
Var
 N:LongInt;
Begin
 N:=Length(TrieNodes);
 SetLength(TrieNodes,N+1);
 SetLength(TrieNodes[N].Cps,0);
 SetLength(TrieNodes[N].Kids,0);
 TrieNodes[N].Terminal:=False;
 TrieNewNode:=N;
End;

Function NotStrings(Const Strs:TStrArray):AnsiString;
Var
 I,J,Cur,K,Found:LongInt;
 Cps,Offs:TIntArray;
 CharRule:AnsiString;
 Outp:AnsiString;

 Procedure Visit(Idx:LongInt);
 Var
  Rejects,C:AnsiString;
  First:Boolean;
  Q:LongInt;
 Begin
  Rejects:='';First:=True;
  For Q:=0 to High(TrieNodes[Idx].Cps)do Begin
   C:=CpToUtf8(TrieNodes[Idx].Cps[Q]);
   Rejects:=Rejects+C;
   If First Then First:=False Else Outp:=Outp+' | ';
   Outp:=Outp+'['+C+']';
   If Length(TrieNodes[TrieNodes[Idx].Kids[Q]].Cps)>0 Then Begin
    Outp:=Outp+' (';
    Visit(TrieNodes[Idx].Kids[Q]);
    Outp:=Outp+')';
   End
    Else Outp:=Outp+' '+CharRule+'+';
  End;
  If Length(TrieNodes[Idx].Cps)>0 Then
   Outp:=Outp+' | [^"'+Rejects+'] '+CharRule+'*';
 End;

Begin
 SetLength(TrieNodes,0);
 TrieNewNode;
 For I:=0 to High(Strs)do Begin
  Utf8ToCps(Strs[I],Cps,Offs);
  Cur:=0;
  For J:=0 to High(Cps)do Begin
   Found:=-1;
   For K:=0 to High(TrieNodes[Cur].Cps)do
    If TrieNodes[Cur].Cps[K]=Cps[J]Then Found:=TrieNodes[Cur].Kids[K];
   If Found<0 Then Begin
    Found:=TrieNewNode;
    K:=Length(TrieNodes[Cur].Cps);
    SetLength(TrieNodes[Cur].Cps,K+1);
    SetLength(TrieNodes[Cur].Kids,K+1);
    While(K>0)and(TrieNodes[Cur].Cps[K-1]>Cps[J])do Begin
     TrieNodes[Cur].Cps[K]:=TrieNodes[Cur].Cps[K-1];
     TrieNodes[Cur].Kids[K]:=TrieNodes[Cur].Kids[K-1];
     Dec(K);
    End;
    TrieNodes[Cur].Cps[K]:=Cps[J];
    TrieNodes[Cur].Kids[K]:=Found;
   End;
   Cur:=Found;
  End;
  TrieNodes[Cur].Terminal:=True;
 End;
 CharRule:=PrimRule('char');
 Outp:='["] ( ';
 Visit(0);
 Outp:=Outp+' )';
 If not TrieNodes[0].Terminal Then Outp:=Outp+'?';
 Outp:=Outp+' ["]';
 NotStrings:=Outp;
End;

Function JoinStrs(Const A:TStrArray;Const Sep:AnsiString):AnsiString;
Var
 I:LongInt;
 R:AnsiString;
Begin
 R:='';
 For I:=0 to High(A)do Begin
  If I>0 Then R:=R+Sep;
  R:=R+A[I];
 End;
 JoinStrs:=R;
End;

Function ResolveRefTarget(Const Ref:AnsiString):PJ;
Var
 Toks:TStrArray;
 I:LongInt;
 T:PJ;
 Idx:Int64;
Begin
 ResolveRefTarget:=Nil;
 Toks:=SplitStr(Copy(Ref,2,Length(Ref)-1),'/');
 T:=SRoot;
 For I:=1 to High(Toks)do Begin
  If T=Nil Then Exit;
  If(T^.Kind=JK_OBJ)and JHas(T,Toks[I])Then T:=JGet(T,Toks[I])
  Else If T^.Kind=JK_ARR Then Begin
   If not ParseInt(Toks[I],Idx)or(Idx<0)or(Idx>=Length(T^.Items))Then Exit;
   T:=T^.Items[Idx];
  End
   Else Exit;
 End;
 ResolveRefTarget:=T;
End;

Function SchemaIsRefBusy(Const Ref:AnsiString):Boolean;
Var
 I:LongInt;
Begin
 SchemaIsRefBusy:=False;
 For I:=0 to High(SRefsInProgress)do If SRefsInProgress[I]=Ref Then SchemaIsRefBusy:=True;
End;

Function ResolveRef(Const Ref:AnsiString):AnsiString;
Var
 P:LongInt;
 Frag,RefName:AnsiString;
 T:PJ;
 I:LongInt;
Begin
 P:=Pos('#',Ref);
 If P>0 Then Frag:=Copy(Ref,P+1,Length(Ref))Else Frag:=Ref;
 RefName:='ref'+SchemaEscName(Frag);
 If(RuleIndex(RefName)<0)and not SchemaIsRefBusy(Ref)Then Begin
  T:=ResolveRefTarget(Ref);
  If T=Nil Then Begin
   AddStr(SErrors,'Unresolved $ref '+Ref);
   ResolveRef:='';
   Exit;
  End;
  AddStr(SRefsInProgress,Ref);
  RefName:=SchemaVisit(T,RefName);
  I:=High(SRefsInProgress);
  SetLength(SRefsInProgress,I);
 End;
 ResolveRef:=RefName;
End;

Function BuildObjectRule(Const PropNames:TStrArray;Const PropSchemas:Array of PJ;
                         Const Required:TStrArray;Const Name:AnsiString;
                         HasAdd:Boolean;AddSchema:PJ;AddIsAny:Boolean):AnsiString;
Var
 ReqProps,OptProps:TStrArray;
 KvNames:Array of TRuleKV;
 I,J:LongInt;
 PropRuleName,Pfx,SubName,ValueRule,KeyRule,KvRule,Rule:AnsiString;
 IsReq:Boolean;

 Function KvOf(Const K:AnsiString):AnsiString;
 Var
  Q:LongInt;
 Begin
  KvOf:='';
  For Q:=0 to High(KvNames)do If KvNames[Q].Name=K Then Begin KvOf:=KvNames[Q].Rule;Exit;End;
 End;

 Procedure SetKv(Const K,V:AnsiString);
 Var
  Q:LongInt;
 Begin
  For Q:=0 to High(KvNames)do If KvNames[Q].Name=K Then Begin KvNames[Q].Rule:=V;Exit;End;
  Q:=Length(KvNames);
  SetLength(KvNames,Q+1);
  KvNames[Q].Name:=K;KvNames[Q].Rule:=V;
 End;

 Function GetRec(Const Ks:TStrArray;First:Integer;FirstIsOpt:Boolean):AnsiString;
 Var
  Res,KvName,CommaRef,K:AnsiString;
  Rest:TStrArray;
  Q:LongInt;
 Begin
  Res:='';
  If First>High(Ks)Then Begin GetRec:='';Exit;End;
  K:=Ks[First];
  KvName:=KvOf(K);
  CommaRef:='( "," space '+KvName+' )';
  If FirstIsOpt Then Begin
   If K='*' Then Res:=CommaRef+'*' Else Res:=CommaRef+'?';
  End
   Else Begin
    If K='*' Then Res:=KvName+' '+CommaRef+'*' Else Res:=KvName;
   End;
  If First<High(Ks)Then Begin
   SetLength(Rest,0);
   For Q:=First+1 to High(Ks)do AddStr(Rest,Ks[Q]);
   If Pfx='' Then
    Res:=Res+' '+AddRule(K+'-rest',GetRec(Rest,0,True))
   Else
    Res:=Res+' '+AddRule(Name+'-'+K+'-rest',GetRec(Rest,0,True));
  End;
  GetRec:=Res;
 End;

Var
 Sub:TStrArray;
 Q:LongInt;
Begin
 SetLength(ReqProps,0);SetLength(OptProps,0);SetLength(KvNames,0);
 If Name='' Then Pfx:='' Else Pfx:=Name+'-';
 For I:=0 to High(PropNames)do Begin
  PropRuleName:=SchemaVisit(PropSchemas[I],Pfx+PropNames[I]);
  SetKv(PropNames[I],AddRule(Pfx+PropNames[I]+'-kv',
        FormatLiteral(JEscapeStr(PropNames[I]))+' space ":" space '+PropRuleName));
  IsReq:=False;
  For J:=0 to High(Required)do If Required[J]=PropNames[I]Then IsReq:=True;
  If IsReq Then AddStr(ReqProps,PropNames[I])Else AddStr(OptProps,PropNames[I]);
 End;
 If HasAdd Then Begin
  SubName:=Pfx+'additional';
  If not AddIsAny Then ValueRule:=SchemaVisit(AddSchema,SubName+'-value')
                  Else ValueRule:=PrimRule('value');
  If Length(PropNames)=0 Then KeyRule:=PrimRule('string')
  Else KeyRule:=AddRule(SubName+'-k',NotStrings(PropNames));
  KvRule:=AddRule(SubName+'-kv',KeyRule+' ":" space '+ValueRule);
  SetKv('*',KvRule);
  AddStr(OptProps,'*');
 End;
 If(Length(ReqProps)=0)and(Length(OptProps)=0)Then Begin
  BuildObjectRule:='"{" space "}"';
  Exit;
 End;
 Rule:='"{" space ';
 For I:=0 to High(ReqProps)do Begin
  If I>0 Then Rule:=Rule+' "," space ';
  Rule:=Rule+KvOf(ReqProps[I]);
 End;
 If Length(OptProps)>0 Then Begin
  Rule:=Rule+' (';
  If Length(ReqProps)>0 Then Rule:=Rule+' "," space ( ';
  For I:=0 to High(OptProps)do Begin
   If I>0 Then Rule:=Rule+' | ';
   SetLength(Sub,0);
   For Q:=I to High(OptProps)do AddStr(Sub,OptProps[Q]);
   Rule:=Rule+GetRec(Sub,0,False);
  End;
  If Length(ReqProps)>0 Then Rule:=Rule+' )';
  Rule:=Rule+' )?';
 End;
 Rule:=Rule+' space "}"';
 BuildObjectRule:=Rule;
End;

Function PJStrIs(V:PJ;Const S:AnsiString):Boolean;
Begin
 PJStrIs:=(V<>Nil)and(V^.Kind=JK_STR)and(V^.S=S);
End;

Function CopyObjWithType(S:PJ;Const T:AnsiString):PJ;
Var
 R,TV:PJ;
 I:LongInt;
Begin
 R:=JNew(JK_OBJ);
 For I:=0 to High(S^.Keys)do
  If S^.Keys[I]<>'type' Then JAddKey(R,S^.Keys[I],S^.Items[I]);
 TV:=JNew(JK_STR);TV^.S:=T;
 JAddKey(R,'type',TV);
 CopyObjWithType:=R;
End;

Function SchemaIsAny(S:PJ):Boolean;
Var
 Ap:PJ;
Begin
 SchemaIsAny:=False;
 If(S=Nil)or(S^.Kind<>JK_OBJ)Then Exit;
 If JHas(S,'$ref')or JHas(S,'oneOf')or JHas(S,'anyOf')or JHas(S,'type')or JHas(S,'const')or
    JHas(S,'enum')or JHas(S,'properties')or JHas(S,'allOf')or JHas(S,'items')or JHas(S,'prefixItems')or
    JHas(S,'pattern')or JHas(S,'minLength')or JHas(S,'maxLength')or JHas(S,'format')Then Exit;
 Ap:=JGet(S,'additionalProperties');
 If(Ap<>Nil)and not JIsTrue(Ap)Then Exit;
 SchemaIsAny:=True;
End;

Function GetCount(S:PJ;Const Key:AnsiString;Def:LongInt):LongInt;
Var
 V:PJ;
Begin
 V:=JGet(S,Key);
 If V=Nil Then Begin GetCount:=Def;Exit;End;
 If(V^.Kind<>JK_INT)or(V^.I<0)Then Begin
  AddStr(SErrors,Key+' must be a non-negative integer');
  GetCount:=Def;
  Exit;
 End;
 GetCount:=V^.I;
End;

Function GetBound(S:PJ;Const Key:AnsiString;RoundUp:Boolean):Int64;
Var
 V:PJ;
Begin
 V:=JGet(S,Key);
 If V^.Kind=JK_INT Then GetBound:=V^.I
 Else If V^.Kind=JK_FLOAT Then Begin
  If RoundUp Then GetBound:=Trunc(FCeil(V^.F))Else GetBound:=Trunc(FFloor(V^.F));
 End
  Else Begin
   AddStr(SErrors,Key+' must be a number');
   GetBound:=0;
  End;
End;

Function SchemaVisit(S:PJ;Const Name:AnsiString):AnsiString;
Var
 RuleName,SubName,TypeName,Key,Rule,ItemRule,Fmt,PrimName,CharRule,Res:AnsiString;
 TV,Alts,Props,Ap,V:PJ;
 EnumKeys:TStrArray;
 EnumCnt:TIntArray;
 EnumInter:TStrArray;
 I,J,Q_,MinI,MaxI,MinL,MaxL:LongInt;
 Rules:TStrArray;
 HasProps:Boolean;
 PN:TStrArray;
 PS:Array of PJ;
 Req:TStrArray;
 MnV,MxV:Int64;
 Tmp:AnsiString;
 AllOfRes:AnsiString;

 { allOf : fusionne les proprietes }
 Procedure AddComponent(Comp:PJ;IsReq:Boolean);
 Var
  Pr:PJ;
  Q,J2,K2:LongInt;
  Tmp2:AnsiString;
 Begin
  If Comp=Nil Then Exit;
  If JHas(Comp,'$ref')Then Begin
   If JGet(Comp,'$ref')^.Kind=JK_STR Then AddComponent(ResolveRefTarget(JGet(Comp,'$ref')^.S),IsReq);
   Exit;
  End;
  If JHas(Comp,'enum')and(JGet(Comp,'enum')^.Kind=JK_ARR)Then Begin
   For Q:=0 to High(JGet(Comp,'enum')^.Items)do Begin
    Tmp2:=FormatLiteral(JDump(JGet(Comp,'enum')^.Items[Q]));
    J2:=-1;
    For K2:=0 to High(EnumKeys)do If EnumKeys[K2]=Tmp2 Then J2:=K2;
    If J2<0 Then Begin
     AddStr(EnumKeys,Tmp2);AddInt(EnumCnt,1);
    End
     Else Inc(EnumCnt[J2]);
   End;
  End;
  If JHas(Comp,'properties')Then Begin
   Pr:=JGet(Comp,'properties');
   For Q:=0 to High(Pr^.Keys)do Begin
    SetLength(PS,Length(PN)+1);
    PS[Length(PN)]:=Pr^.Items[Q];
    AddStr(PN,Pr^.Keys[Q]);
    If IsReq Then AddStr(Req,Pr^.Keys[Q]);
   End;
  End;
 End;

Begin
 Res:='';
 If IsReservedName(Name)Then RuleName:=Name+'-'
 Else If Name='' Then RuleName:='root'
 Else RuleName:=Name;
 If Name='' Then SubName:='' Else SubName:=Name+'-';
 If(S=Nil)or(S^.Kind<>JK_OBJ)Then Begin
  AddStr(SErrors,'schema must be an object');
  SchemaVisit:='';
  Exit;
 End;
 If JHas(S,'$ref')Then Begin
  If JGet(S,'$ref')^.Kind<>JK_STR Then Begin AddStr(SErrors,'$ref must be a string');SchemaVisit:='';Exit;End;
  If Copy(JGet(S,'$ref')^.S,1,2)<>'#/' Then Begin
   AddStr(SErrors,'unsupported $ref '+JGet(S,'$ref')^.S+', only references into the same document are supported');
   SchemaVisit:='';Exit;
  End;
  SchemaVisit:=AddRule(RuleName,ResolveRef(JGet(S,'$ref')^.S));
  Exit;
 End;
 If JHas(S,'oneOf')or JHas(S,'anyOf')Then Begin
  If JHas(S,'oneOf')Then Alts:=JGet(S,'oneOf')Else Alts:=JGet(S,'anyOf');
  If(Alts^.Kind<>JK_ARR)or(Length(Alts^.Items)=0)Then Begin
   AddStr(SErrors,'oneOf/anyOf must be a non-empty array of schemas');
   SchemaVisit:='';Exit;
  End;
  SetLength(Rules,0);
  For I:=0 to High(Alts^.Items)do Begin
   If Name='' Then Tmp:='alternative-' Else Tmp:=Name+'-';
   AddStr(Rules,SchemaVisit(Alts^.Items[I],Tmp+IStr(I)));
  End;
  SchemaVisit:=AddRule(RuleName,JoinStrs(Rules,' | '));
  Exit;
 End;
 TV:=JGet(S,'type');
 If(TV<>Nil)and(TV^.Kind=JK_ARR)Then Begin
  If Length(TV^.Items)=0 Then Begin AddStr(SErrors,'type must not be empty');SchemaVisit:='';Exit;End;
  SetLength(Rules,0);
  For I:=0 to High(TV^.Items)do Begin
   If TV^.Items[I]^.Kind<>JK_STR Then Begin AddStr(SErrors,'type must be a string or an array of strings');Break;End;
   If Name='' Then Tmp:='alternative-' Else Tmp:=Name+'-';
   AddStr(Rules,SchemaVisit(CopyObjWithType(S,TV^.Items[I]^.S),Tmp+IStr(I)));
  End;
  SchemaVisit:=AddRule(RuleName,JoinStrs(Rules,' | '));
  Exit;
 End;
 If JHas(S,'const')Then Begin
  SchemaVisit:=AddRule(RuleName,FormatLiteral(JDump(JGet(S,'const'))));
  Exit;
 End;
 If JHas(S,'enum')Then Begin
  Alts:=JGet(S,'enum');
  If(Alts^.Kind<>JK_ARR)or(Length(Alts^.Items)=0)Then Begin
   AddStr(SErrors,'enum must be a non-empty array');SchemaVisit:='';Exit;
  End;
  SetLength(Rules,0);
  For I:=0 to High(Alts^.Items)do AddStr(Rules,FormatLiteral(JDump(Alts^.Items[I])));
  SchemaVisit:=AddRule(RuleName,'('+JoinStrs(Rules,' | ')+')');
  Exit;
 End;
 If(TV<>Nil)and(TV^.Kind<>JK_STR)and(TV^.Kind<>JK_NULL)Then Begin
  AddStr(SErrors,'type must be a string or an array of strings');SchemaVisit:='';Exit;
 End;
 If(TV<>Nil)and(TV^.Kind=JK_STR)Then TypeName:=TV^.S Else TypeName:='';
 Ap:=JGet(S,'additionalProperties');
 HasProps:=JHas(S,'properties')or((Ap<>Nil)and not JIsTrue(Ap));
 If TypeName='' Then Begin
  If HasProps Then TypeName:='object'
  Else If JHas(S,'allOf')Then TypeName:='@allOf'
  Else If JHas(S,'items')or JHas(S,'prefixItems')Then TypeName:='array'
  Else If JHas(S,'pattern')or JHas(S,'minLength')or JHas(S,'maxLength')or JHas(S,'format')Then TypeName:='string'
  Else TypeName:='@any';
 End
  Else If((TypeName='object')and not HasProps)or(TypeName='string')Then Begin
   If JHas(S,'allOf')and((TypeName='string')or not HasProps)Then TypeName:='@allOf';
  End;
 If TypeName='@any' Then Begin
  SchemaVisit:=AddRule(RuleName,PrimRule('value'));
  Exit;
 End;
 If TypeName='@allOf' Then Begin
  Alts:=JGet(S,'allOf');
  If(Alts^.Kind<>JK_ARR)or(Length(Alts^.Items)=0)Then Begin
   AddStr(SErrors,'allOf must be a non-empty array');SchemaVisit:='';Exit;
  End;
  SetLength(PN,0);SetLength(PS,0);SetLength(Req,0);
  SetLength(EnumKeys,0);SetLength(EnumCnt,0);SetLength(EnumInter,0);
  For I:=0 to High(Alts^.Items)do Begin
   V:=Alts^.Items[I];
   If JHas(V,'anyOf')Then Begin
    For J:=0 to High(JGet(V,'anyOf')^.Items)do AddComponent(JGet(V,'anyOf')^.Items[J],False);
   End
    Else AddComponent(V,True);
  End;
  If Length(EnumKeys)>0 Then Begin
   { tri alphabetique (std::map) puis intersection }
   For I:=1 to High(EnumKeys)do Begin
    Tmp:=EnumKeys[I];J:=EnumCnt[I];
    Q_:=I-1;
    While(Q_>=0)and(EnumKeys[Q_]>Tmp)do Begin
     EnumKeys[Q_+1]:=EnumKeys[Q_];EnumCnt[Q_+1]:=EnumCnt[Q_];Dec(Q_);
    End;
    EnumKeys[Q_+1]:=Tmp;EnumCnt[Q_+1]:=J;
   End;
   For I:=0 to High(EnumKeys)do
    If EnumCnt[I]=Length(Alts^.Items)Then AddStr(EnumInter,EnumKeys[I]);
   If Length(EnumInter)>0 Then Begin
    SchemaVisit:=AddRule(RuleName,'('+JoinStrs(EnumInter,' | ')+')');
    Exit;
   End;
  End;
  SchemaVisit:=AddRule(RuleName,BuildObjectRule(PN,PS,Req,Name,False,Nil,False));
  Exit;
 End;
 If TypeName='object' Then Begin
  Props:=JGet(S,'properties');
  If(Props=Nil)and((Ap=Nil)or JIsTrue(Ap))Then Begin
   SchemaVisit:=AddRule(RuleName,PrimRule('object'));
   Exit;
  End;
  SetLength(PN,0);SetLength(PS,0);SetLength(Req,0);
  If(Props<>Nil)Then Begin
   If Props^.Kind<>JK_OBJ Then Begin AddStr(SErrors,'properties must be an object');SchemaVisit:='';Exit;End;
   For I:=0 to High(Props^.Keys)do Begin
    AddStr(PN,Props^.Keys[I]);
    SetLength(PS,Length(PN));
    PS[Length(PN)-1]:=Props^.Items[I];
   End;
  End;
  V:=JGet(S,'required');
  If(V<>Nil)and(V^.Kind=JK_ARR)Then
   For I:=0 to High(V^.Items)do If V^.Items[I]^.Kind=JK_STR Then AddStr(Req,V^.Items[I]^.S);
  If Ap<>Nil Then Begin
   If Ap^.Kind=JK_BOOL Then Begin
    If Ap^.B Then SchemaVisit:=AddRule(RuleName,BuildObjectRule(PN,PS,Req,Name,True,Nil,True))
             Else SchemaVisit:=AddRule(RuleName,BuildObjectRule(PN,PS,Req,Name,False,Nil,False));
   End
    Else If Ap^.Kind=JK_OBJ Then
     SchemaVisit:=AddRule(RuleName,BuildObjectRule(PN,PS,Req,Name,True,Ap,False))
    Else Begin
     AddStr(SErrors,'additionalProperties must be a boolean or a schema');SchemaVisit:='';
    End;
  End
   Else Begin
    If Props=Nil Then SchemaVisit:=AddRule(RuleName,BuildObjectRule(PN,PS,Req,Name,True,Nil,True))
    Else SchemaVisit:=AddRule(RuleName,BuildObjectRule(PN,PS,Req,Name,False,Nil,False));
   End;
  Exit;
 End;
 If TypeName='array' Then Begin
  V:=Nil;
  If JHas(S,'items')Then Key:='items' Else If JHas(S,'prefixItems')Then Key:='prefixItems' Else Key:='';
  If Key<>'' Then V:=JGet(S,Key);
  If SchemaIsAny(V)Then V:=Nil;
  If(V<>Nil)and(V^.Kind=JK_ARR)Then Begin
   Rule:='"[" space ';
   For I:=0 to High(V^.Items)do Begin
    If I>0 Then Rule:=Rule+' "," space ';
    Rule:=Rule+SchemaVisit(V^.Items[I],SubName+'tuple-'+IStr(I));
   End;
   Rule:=Rule+' space "]"';
   SchemaVisit:=AddRule(RuleName,Rule);
   Exit;
  End;
  MinI:=GetCount(S,'minItems',0);
  MaxI:=GetCount(S,'maxItems',-1);
  If(V=Nil)and(MinI=0)and(MaxI<0)Then Begin
   SchemaVisit:=VisitPrim(RuleName,'array');
   Exit;
  End;
  If V=Nil Then ItemRule:=AddRule(SubName+'item',PrimRule('value'))
  Else ItemRule:=SchemaVisit(V,SubName+'item');
  If MaxI<0 Then MaxI:=MaxLongInt;
  SchemaVisit:=AddRule(RuleName,'"[" space '+BuildRepetition(ItemRule,MinI,MaxI,'"," space')+' space "]"');
  Exit;
 End;
 If TypeName='string' Then Begin
  If JHas(S,'pattern')Then Begin
   If JGet(S,'pattern')^.Kind<>JK_STR Then Begin AddStr(SErrors,'pattern must be a string');SchemaVisit:='';Exit;End;
   SchemaVisit:=VisitPattern(JGet(S,'pattern')^.S,RuleName);
   Exit;
  End;
  Fmt:='';
  If JHas(S,'format')and(JGet(S,'format')^.Kind=JK_STR)Then Fmt:=JGet(S,'format')^.S;
  If(Fmt='uuid')or((Length(Fmt)=5)and(Copy(Fmt,1,4)='uuid')and(Fmt[5]in['1'..'5']))Then Begin
   SchemaVisit:=VisitPrim(RuleName,'uuid');
   Exit;
  End;
  If(Fmt='date')or(Fmt='time')or(Fmt='date-time')Then Begin
   PrimName:=Fmt+'-string';
   SchemaVisit:=AddRule(RuleName,PrimRule(PrimName));
   Exit;
  End;
  MinL:=GetCount(S,'minLength',0);
  MaxL:=GetCount(S,'maxLength',-1);
  If(MinL>0)or(MaxL>=0)Then Begin
   CharRule:=PrimRule('char');
   If MaxL<0 Then MaxL:=MaxLongInt;
   SchemaVisit:=AddRule(RuleName,'"\"" '+BuildRepetition(CharRule,MinL,MaxL,'')+' "\""');
   Exit;
  End;
  SchemaVisit:=VisitPrim(RuleName,'string');
  Exit;
 End;
 If TypeName='integer' Then Begin
  MnV:=I64Min;MxV:=I64Max;
  If JHas(S,'minimum')Then MnV:=GetBound(S,'minimum',True)
  Else If JHas(S,'exclusiveMinimum')Then MnV:=GetBound(S,'exclusiveMinimum',False)+1;
  If JHas(S,'maximum')Then MxV:=GetBound(S,'maximum',False)
  Else If JHas(S,'exclusiveMaximum')Then MxV:=GetBound(S,'exclusiveMaximum',True)-1;
  If(MnV=I64Min)and(MxV=I64Max)Then Begin
   SchemaVisit:=VisitPrim(RuleName,'integer');
   Exit;
  End;
  Tmp:='(';
  BuildMinMaxInt(MnV,MxV,Tmp,16,True);
  Tmp:=Tmp+')';
  SchemaVisit:=AddRule(RuleName,Tmp);
  Exit;
 End;
 If(TypeName='number')or(TypeName='boolean')or(TypeName='null')Then Begin
  SchemaVisit:=VisitPrim(RuleName,TypeName);
  Exit;
 End;
 AddStr(SErrors,'unrecognized type '+TypeName);
 SchemaVisit:='';
End;

{ Convertit un schema JSON en texte GBNF ; Ok=False en cas d'erreur }
Function JsonSchemaToGrammar(Const SchemaText:AnsiString;Var Ok:Boolean;Var Err:AnsiString):AnsiString;
Var
 V:PJ;
 I,J:LongInt;
 Tmp:TRuleKV;
 R:AnsiString;
Begin
 Ok:=False;Err:='';JsonSchemaToGrammar:='';
 V:=JParse(SchemaText);
 If V=Nil Then Begin Err:='JSON schema invalide : '+JErr;Exit;End;
 InitBuiltins;
 SetLength(SRules,0);SetLength(SErrors,0);SetLength(SWarnings,0);SetLength(SRefsInProgress,0);
 SRoot:=V;SDotAll:=False;
 SetRule('space','| " " | "\n"{1,2} [ \t]{0,20}');
 SchemaVisit(V,'');
 If Length(SErrors)>0 Then Begin
  Err:='JSON schema conversion failed:'+#10+JoinStrs(SErrors,#10);
  Exit;
 End;
 If Length(SWarnings)>0 Then
  LogWrn('WARNING: JSON schema conversion was incomplete: '+JoinStrs(SWarnings,'; ')+#10);
 { tri par nom (comme std::map) }
 For I:=1 to High(SRules)do Begin
  Tmp:=SRules[I];
  J:=I-1;
  While(J>=0)and(SRules[J].Name>Tmp.Name)do Begin SRules[J+1]:=SRules[J];Dec(J);End;
  SRules[J+1]:=Tmp;
 End;
 R:='';
 For I:=0 to High(SRules)do R:=R+SRules[I].Name+' ::= '+SRules[I].Rule+#10;
 JsonSchemaToGrammar:=R;
 Ok:=True;
End;

{ ------------------------------------------------------------------ }
{ Candidats d'echantillonnage                                         }
{ ------------------------------------------------------------------ }

Type
 TCand=Record
  Id:LongInt;
  Logit:Single;
  P:Single;
 End;
 TCandSet=Record
  D:Array of TCand;
  N:LongInt;
  Sorted:Boolean;
  Selected:LongInt;
 End;

{ ------------------------------------------------------------------ }
{ Grammaires GBNF                                                     }
{ ------------------------------------------------------------------ }

Const
 GRE_END=0; GRE_ALT=1; GRE_RULE_REF=2; GRE_CHAR=3; GRE_CHAR_NOT=4;
 GRE_CHAR_RNG_UPPER=5; GRE_CHAR_ALT=6; GRE_CHAR_ANY=7; GRE_TOKEN=8; GRE_TOKEN_NOT=9;
 MaxRepetitionThreshold=2000;

Type
 TGE=Record
  T:LongInt;
  V:LongWord;
 End;
 TGRule=Array of TGE;
 TGStack=Array of Int64;      { (regle shl 32) or indice d'element }
 TGStackList=Array of TGStack;
 TGCand=Record
  Index:LongInt;
  CP:LongInt;                 { decalage dans le tampon de points de code }
  PV:LongWord;
  PN:LongInt;
  Id:LongInt;
 End;
 TGCandArr=Array of TGCand;

 TGrammar=Record
  Rules:Array of TGRule;
  SymNames:TStrArray;
  SymHash:THash;
  Stacks:TGStackList;
  PartialV:LongWord;
  PartialN:LongInt;
  Root:LongInt;
  Ok:Boolean;
 End;

Var
 GErr:AnsiString;
 GSrc:AnsiString;
 GCpPool:Array of LongWord;
 GCpPoolN:LongInt;
 GVocab:^TVocab;

Function GCh(P:LongInt):Char;
Begin
 If(P>=1)and(P<=Length(GSrc))Then GCh:=GSrc[P]Else GCh:=#0;
End;

Procedure GFail(Const Msg:AnsiString);
Begin
 If GErr='' Then GErr:=Msg;
End;

Function GIsDigit(C:Char):Boolean;Begin GIsDigit:=(C>='0')and(C<='9');End;
Function GIsWord(C:Char):Boolean;Begin GIsWord:=(C in['a'..'z','A'..'Z','-'])or GIsDigit(C);End;

Function GParseSpace(P:LongInt;NewlineOk:Boolean):LongInt;
Begin
 While(GCh(P)=' ')or(GCh(P)=#9)or(GCh(P)='#')or(NewlineOk and((GCh(P)=#13)or(GCh(P)=#10)))do Begin
  If GCh(P)='#' Then Begin
   While(GCh(P)<>#0)and(GCh(P)<>#13)and(GCh(P)<>#10)do Inc(P);
  End
   Else Inc(P);
 End;
 GParseSpace:=P;
End;

Function GParseName(P:LongInt):LongInt;
Var
 Q:LongInt;
Begin
 Q:=P;
 While GIsWord(GCh(Q))do Inc(Q);
 If Q=P Then GFail('expecting name at '+Copy(GSrc,P,20));
 GParseName:=Q;
End;

Function GParseInt(P:LongInt):LongInt;
Var
 Q:LongInt;
Begin
 Q:=P;
 While GIsDigit(GCh(Q))do Inc(Q);
 If Q=P Then GFail('expecting integer at '+Copy(GSrc,P,20));
 GParseInt:=Q;
End;

Function GParseHex(P:LongInt;Size:LongInt;Var V:LongWord):LongInt;
Var
 Q,E:LongInt;
 H:LongInt;
Begin
 Q:=P;E:=P+Size;V:=0;
 While(Q<E)and(GCh(Q)<>#0)do Begin
  H:=HexVal(GCh(Q));
  If H<0 Then Break;
  V:=(V shl 4)+LongWord(H);
  Inc(Q);
 End;
 If Q<>E Then GFail('expecting '+IStr(Size)+' hex chars at '+Copy(GSrc,P,20));
 GParseHex:=Q;
End;

Function GDecodeUtf8At(P:LongInt;Var V:LongWord):LongInt;
Var
 B:Byte;
 L,K:LongInt;
Begin
 B:=Ord(GCh(P));
 If B<$80 Then L:=1
 Else If B<$C0 Then L:=1
 Else If B<$E0 Then L:=2
 Else If B<$F0 Then L:=3
 Else L:=4;
 Case L of
  1:V:=B;
  2:V:=B and $1F;
  3:V:=B and $0F;
  Else V:=B and $07;
 End;
 For K:=1 to L-1 do Begin
  If GCh(P+K)=#0 Then Begin GDecodeUtf8At:=P+K;Exit;End;
  V:=(V shl 6)+(Ord(GCh(P+K))and $3F);
 End;
 GDecodeUtf8At:=P+L;
End;

Function GParseChar(P:LongInt;Var V:LongWord):LongInt;
Begin
 V:=0;
 If GCh(P)='\' Then Begin
  Case GCh(P+1)of
   'x':GParseChar:=GParseHex(P+2,2,V);
   'u':GParseChar:=GParseHex(P+2,4,V);
   'U':GParseChar:=GParseHex(P+2,8,V);
   't':Begin V:=9;GParseChar:=P+2;End;
   'r':Begin V:=13;GParseChar:=P+2;End;
   'n':Begin V:=10;GParseChar:=P+2;End;
   '\','"','[',']','-':Begin V:=Ord(GCh(P+1));GParseChar:=P+2;End;
   Else Begin GFail('unknown escape at '+Copy(GSrc,P,20));GParseChar:=P+2;End;
  End;
 End
  Else If GCh(P)<>#0 Then GParseChar:=GDecodeUtf8At(P,V)
  Else Begin GFail('unexpected end of input');GParseChar:=P;End;
End;

Function GSymbolId(Var G:TGrammar;Const Name:AnsiString):LongInt;
Var
 R,N:LongInt;
Begin
 R:=HFind(G.SymHash,Name);
 If R>=0 Then Begin GSymbolId:=R;Exit;End;
 N:=Length(G.SymNames);
 AddStr(G.SymNames,Name);
 HPut(G.SymHash,Name,N);
 GSymbolId:=N;
End;

Function GGenSymbolId(Var G:TGrammar;Const Base:AnsiString):LongInt;
Var
 N:LongInt;
Begin
 N:=Length(G.SymNames);
 AddStr(G.SymNames,Base+'_'+IStr(N));
 HPut(G.SymHash,Base+'_'+IStr(N),N);
 GGenSymbolId:=N;
End;

Procedure GAddRule(Var G:TGrammar;Id:LongInt;Const R:TGRule);
Begin
 If Length(G.Rules)<=Id Then SetLength(G.Rules,Id+1);
 G.Rules[Id]:=R;
End;

Procedure GPush(Var R:TGRule;T:LongInt;V:LongWord);
Var
 N:LongInt;
Begin
 N:=Length(R);
 SetLength(R,N+1);
 R[N].T:=T;R[N].V:=V;
End;

Function GParseAlternates(Var G:TGrammar;P:LongInt;Const RuleName:AnsiString;RuleId:LongInt;
                          Nested:Boolean):LongInt;Forward;

Function GParseToken(P:LongInt;Var TokId:LongWord):LongInt;
Var
 Q,E:LongInt;
 Id:Int64;
 Tx:AnsiString;
 T:TIntArray;
Begin
 TokId:=0;
 If GCh(P)<>'<' Then Begin GFail('expecting ''<'' at '+Copy(GSrc,P,20));GParseToken:=P;Exit;End;
 Q:=P+1;
 If GCh(Q)='[' Then Begin
  Inc(Q);
  E:=GParseInt(Q);
  ParseInt(Copy(GSrc,Q,E-Q),Id);
  TokId:=LongWord(Id);
  Q:=E;
  If GCh(Q)<>']' Then GFail('expecting '']'' at '+Copy(GSrc,Q,20));
  Inc(Q);
  If GCh(Q)<>'>' Then GFail('expecting ''>'' at '+Copy(GSrc,Q,20));
  Inc(Q);
  GParseToken:=Q;
  Exit;
 End;
 If GVocab=Nil Then Begin GFail('no vocab to parse token at '+Copy(GSrc,P,20));GParseToken:=P;Exit;End;
 While(GCh(Q)<>#0)and(GCh(Q)<>'>')do Inc(Q);
 If GCh(Q)<>'>' Then Begin GFail('expecting ''>'' at '+Copy(GSrc,Q,20));GParseToken:=P;Exit;End;
 Inc(Q);
 Tx:=Copy(GSrc,P,Q-P);
 T:=VocabTokenize(GVocab^,Tx,False,True);
 If Length(T)<>1 Then Begin GFail('invalid token '''+Tx+'''');GParseToken:=P;Exit;End;
 TokId:=LongWord(T[0]);
 GParseToken:=Q;
End;

Function GParseSequence(Var G:TGrammar;P:LongInt;Const RuleName:AnsiString;Var Rule:TGRule;
                        Nested:Boolean):LongInt;
Var
 LastSymStart:LongInt;
 NPrevRules:Int64;
 Pos_:LongInt;
 V:LongWord;
 StartType,Typ:LongInt;
 Q,IntEnd:LongInt;
 SubRuleId,NRulesBefore,RefId:LongInt;
 MinTimes,MaxTimes:Int64;
 EndV:LongWord;
 NoMax:Boolean;
 Id:Int64;
 TokType:LongInt;
 TokId:LongWord;

 Procedure HandleRepetitions(MinT,MaxT:Int64);
 Var
  NoMax_:Boolean;
  PrevRule,RecRule:TGRule;
  TotalRules:Int64;
  I:LongInt;
  LastRecRuleId,RecRuleId:LongInt;
  NOpt:Int64;
  J:LongInt;
 Begin
  NoMax_:=MaxT=-1;
  If LastSymStart=Length(Rule)Then Begin
   GFail('expecting preceding item to */+/?/{ at '+Copy(GSrc,Pos_,20));
   Exit;
  End;
  SetLength(PrevRule,Length(Rule)-LastSymStart);
  For J:=0 to High(PrevRule)do PrevRule[J]:=Rule[LastSymStart+J];
  TotalRules:=1;
  If(not NoMax_)and(MaxT>0)Then TotalRules:=MaxT
  Else If MinT>0 Then TotalRules:=MinT;
  If NPrevRules*TotalRules>MaxRepetitionThreshold Then Begin
   GFail('number of rules that are going to be repeated multiplied by the new repetition exceeds sane defaults, please reduce the number of repetitions or rule complexity');
   Exit;
  End;
  If MinT=0 Then SetLength(Rule,LastSymStart)
  Else Begin
   For I:=1 to LongInt(MinT)-1 do
    For J:=0 to High(PrevRule)do GPush(Rule,PrevRule[J].T,PrevRule[J].V);
  End;
  LastRecRuleId:=0;
  If NoMax_ Then NOpt:=1 Else NOpt:=MaxT-MinT;
  RecRule:=Copy(PrevRule,0,Length(PrevRule));
  For I:=0 to LongInt(NOpt)-1 do Begin
   SetLength(RecRule,Length(PrevRule));
   RecRuleId:=GGenSymbolId(G,RuleName);
   If(I>0)or NoMax_ Then Begin
    If NoMax_ Then GPush(RecRule,GRE_RULE_REF,RecRuleId)
              Else GPush(RecRule,GRE_RULE_REF,LastRecRuleId);
   End;
   GPush(RecRule,GRE_ALT,0);
   GPush(RecRule,GRE_END,0);
   GAddRule(G,RecRuleId,RecRule);
   LastRecRuleId:=RecRuleId;
  End;
  If NOpt>0 Then GPush(Rule,GRE_RULE_REF,LastRecRuleId);
  NPrevRules:=NPrevRules*TotalRules;
 End;

Begin
 LastSymStart:=Length(Rule);
 Pos_:=P;
 NPrevRules:=1;
 While(GCh(Pos_)<>#0)and(GErr='')do Begin
  If GCh(Pos_)='"' Then Begin
   Inc(Pos_);
   LastSymStart:=Length(Rule);
   NPrevRules:=1;
   While(GCh(Pos_)<>'"')and(GErr='')do Begin
    If GCh(Pos_)=#0 Then Begin GFail('unexpected end of input');Break;End;
    Pos_:=GParseChar(Pos_,V);
    GPush(Rule,GRE_CHAR,V);
   End;
   If GErr='' Then Pos_:=GParseSpace(Pos_+1,Nested);
  End
  Else If GCh(Pos_)='[' Then Begin
   Inc(Pos_);
   StartType:=GRE_CHAR;
   If GCh(Pos_)='^' Then Begin Inc(Pos_);StartType:=GRE_CHAR_NOT;End;
   LastSymStart:=Length(Rule);
   NPrevRules:=1;
   While(GCh(Pos_)<>']')and(GErr='')do Begin
    If GCh(Pos_)=#0 Then Begin GFail('unexpected end of input');Break;End;
    Pos_:=GParseChar(Pos_,V);
    If LastSymStart<Length(Rule)Then Typ:=GRE_CHAR_ALT Else Typ:=StartType;
    GPush(Rule,Typ,V);
    If(GCh(Pos_)='-')and(GCh(Pos_+1)<>']')Then Begin
     If GCh(Pos_+1)=#0 Then Begin GFail('unexpected end of input');Break;End;
     Pos_:=GParseChar(Pos_+1,EndV);
     GPush(Rule,GRE_CHAR_RNG_UPPER,EndV);
    End;
   End;
   If GErr='' Then Pos_:=GParseSpace(Pos_+1,Nested);
  End
  Else If(GCh(Pos_)='<')or(GCh(Pos_)='!')Then Begin
   TokType:=GRE_TOKEN;
   If GCh(Pos_)='!' Then Begin TokType:=GRE_TOKEN_NOT;Inc(Pos_);End;
   Q:=GParseToken(Pos_,TokId);
   If GErr<>'' Then Break;
   LastSymStart:=Length(Rule);
   NPrevRules:=1;
   GPush(Rule,TokType,TokId);
   Pos_:=GParseSpace(Q,Nested);
  End
  Else If GIsWord(GCh(Pos_))Then Begin
   Q:=GParseName(Pos_);
   If GErr<>'' Then Break;
   RefId:=GSymbolId(G,Copy(GSrc,Pos_,Q-Pos_));
   Pos_:=GParseSpace(Q,Nested);
   LastSymStart:=Length(Rule);
   NPrevRules:=1;
   GPush(Rule,GRE_RULE_REF,RefId);
  End
  Else If GCh(Pos_)='(' Then Begin
   Pos_:=GParseSpace(Pos_+1,True);
   NRulesBefore:=Length(G.SymNames);
   SubRuleId:=GGenSymbolId(G,RuleName);
   Pos_:=GParseAlternates(G,Pos_,RuleName,SubRuleId,True);
   NPrevRules:=Length(G.SymNames)-NRulesBefore;
   If NPrevRules<1 Then NPrevRules:=1;
   LastSymStart:=Length(Rule);
   GPush(Rule,GRE_RULE_REF,SubRuleId);
   If GErr<>'' Then Break;
   If GCh(Pos_)<>')' Then Begin GFail('expecting '')'' at '+Copy(GSrc,Pos_,20));Break;End;
   Pos_:=GParseSpace(Pos_+1,Nested);
  End
  Else If GCh(Pos_)='.' Then Begin
   LastSymStart:=Length(Rule);
   NPrevRules:=1;
   GPush(Rule,GRE_CHAR_ANY,0);
   Pos_:=GParseSpace(Pos_+1,Nested);
  End
  Else If GCh(Pos_)='*' Then Begin
   Pos_:=GParseSpace(Pos_+1,Nested);
   HandleRepetitions(0,-1);
  End
  Else If GCh(Pos_)='+' Then Begin
   Pos_:=GParseSpace(Pos_+1,Nested);
   HandleRepetitions(1,-1);
  End
  Else If GCh(Pos_)='?' Then Begin
   Pos_:=GParseSpace(Pos_+1,Nested);
   HandleRepetitions(0,1);
  End
  Else If GCh(Pos_)='{' Then Begin
   Pos_:=GParseSpace(Pos_+1,Nested);
   If not GIsDigit(GCh(Pos_))Then Begin GFail('expecting an int at '+Copy(GSrc,Pos_,20));Break;End;
   IntEnd:=GParseInt(Pos_);
   ParseInt(Copy(GSrc,Pos_,IntEnd-Pos_),MinTimes);
   Pos_:=GParseSpace(IntEnd,Nested);
   MaxTimes:=-1;
   If GCh(Pos_)='}' Then Begin
    MaxTimes:=MinTimes;
    Pos_:=GParseSpace(Pos_+1,Nested);
   End
    Else If GCh(Pos_)=',' Then Begin
     Pos_:=GParseSpace(Pos_+1,Nested);
     If GIsDigit(GCh(Pos_))Then Begin
      IntEnd:=GParseInt(Pos_);
      ParseInt(Copy(GSrc,Pos_,IntEnd-Pos_),MaxTimes);
      Pos_:=GParseSpace(IntEnd,Nested);
     End;
     If GCh(Pos_)<>'}' Then Begin GFail('expecting ''}'' at '+Copy(GSrc,Pos_,20));Break;End;
     Pos_:=GParseSpace(Pos_+1,Nested);
    End
    Else Begin GFail('expecting '','' at '+Copy(GSrc,Pos_,20));Break;End;
   If MinTimes>MaxRepetitionThreshold Then Begin
    GFail('number of repetitions exceeds sane defaults, please reduce the number of repetitions');Break;
   End;
   If(MaxTimes<>-1)and(MaxTimes>MaxRepetitionThreshold)Then MaxTimes:=-1;
   HandleRepetitions(MinTimes,MaxTimes);
  End
  Else Break;
 End;
 GParseSequence:=Pos_;
End;

Function GParseAlternates(Var G:TGrammar;P:LongInt;Const RuleName:AnsiString;RuleId:LongInt;
                          Nested:Boolean):LongInt;
Var
 Rule:TGRule;
 Pos_:LongInt;
Begin
 SetLength(Rule,0);
 Pos_:=GParseSequence(G,P,RuleName,Rule,Nested);
 While(GCh(Pos_)='|')and(GErr='')do Begin
  GPush(Rule,GRE_ALT,0);
  Pos_:=GParseSpace(Pos_+1,True);
  Pos_:=GParseSequence(G,Pos_,RuleName,Rule,Nested);
 End;
 GPush(Rule,GRE_END,0);
 GAddRule(G,RuleId,Rule);
 GParseAlternates:=Pos_;
End;

Function GParseRule(Var G:TGrammar;P:LongInt):LongInt;
Var
 NameEnd,Pos_,RuleId:LongInt;
 Name:AnsiString;
Begin
 NameEnd:=GParseName(P);
 If GErr<>'' Then Begin GParseRule:=P;Exit;End;
 Pos_:=GParseSpace(NameEnd,False);
 Name:=Copy(GSrc,P,NameEnd-P);
 RuleId:=GSymbolId(G,Name);
 If not((GCh(Pos_)=':')and(GCh(Pos_+1)=':')and(GCh(Pos_+2)='='))Then Begin
  GFail('expecting ::= at '+Copy(GSrc,Pos_,20));
  GParseRule:=Pos_;Exit;
 End;
 Pos_:=GParseSpace(Pos_+3,True);
 Pos_:=GParseAlternates(G,Pos_,Name,RuleId,False);
 If GErr<>'' Then Begin GParseRule:=Pos_;Exit;End;
 If GCh(Pos_)=#13 Then Begin
  If GCh(Pos_+1)=#10 Then Inc(Pos_,2)Else Inc(Pos_);
 End
  Else If GCh(Pos_)=#10 Then Inc(Pos_)
  Else If GCh(Pos_)<>#0 Then GFail('expecting newline or end at '+Copy(GSrc,Pos_,20));
 GParseRule:=GParseSpace(Pos_,True);
End;

Function GIsEndOfSeq(Const R:TGRule;I:LongInt):Boolean;
Begin
 GIsEndOfSeq:=(R[I].T=GRE_END)or(R[I].T=GRE_ALT);
End;

Function GDetectLeftRec(Const G:TGrammar;RuleIdx:LongInt;Var Visited,InProgress,MayBeEmpty:TBoolArray):Boolean;
Var
 R:TGRule;
 AtStart,Recurse:Boolean;
 I:LongInt;
Begin
 If InProgress[RuleIdx]Then Begin GDetectLeftRec:=True;Exit;End;
 InProgress[RuleIdx]:=True;
 R:=G.Rules[RuleIdx];
 AtStart:=True;
 For I:=0 to High(R)do Begin
  If GIsEndOfSeq(R,I)Then Begin
   If AtStart Then Begin MayBeEmpty[RuleIdx]:=True;Break;End;
   AtStart:=True;
  End
   Else AtStart:=False;
 End;
 Recurse:=True;
 For I:=0 to High(R)do Begin
  If(R[I].T=GRE_RULE_REF)and Recurse Then Begin
   If GDetectLeftRec(G,R[I].V,Visited,InProgress,MayBeEmpty)Then Begin GDetectLeftRec:=True;Exit;End;
   If not MayBeEmpty[R[I].V]Then Recurse:=False;
  End
   Else If GIsEndOfSeq(R,I)Then Recurse:=True
   Else Recurse:=False;
 End;
 InProgress[RuleIdx]:=False;
 Visited[RuleIdx]:=True;
 GDetectLeftRec:=False;
End;

{ --- pile --- }

Function StackEq(Const A,B:TGStack):Boolean;
Var
 I:LongInt;
Begin
 StackEq:=False;
 If Length(A)<>Length(B)Then Exit;
 For I:=0 to High(A)do If A[I]<>B[I]Then Exit;
 StackEq:=True;
End;

Function StackFind(Const L:TGStackList;Const S:TGStack):Boolean;
Var
 I:LongInt;
Begin
 StackFind:=False;
 For I:=0 to High(L)do If StackEq(L[I],S)Then Begin StackFind:=True;Exit;End;
End;

Procedure StackAdd(Var L:TGStackList;Const S:TGStack);
Var
 N:LongInt;
Begin
 N:=Length(L);
 SetLength(L,N+1);
 L[N]:=S;
End;

Function StackPush(Const S:TGStack;V:Int64):TGStack;
Var
 R:TGStack;
 N:LongInt;
Begin
 N:=Length(S);
 SetLength(R,N+1);
 If N>0 Then Move(S[0],R[0],N*8);
 R[N]:=V;
 StackPush:=R;
End;

Function StackPopTop(Const S:TGStack):TGStack;
Var
 R:TGStack;
 N:LongInt;
Begin
 N:=Length(S)-1;
 SetLength(R,N);
 If N>0 Then Move(S[0],R[0],N*8);
 StackPopTop:=R;
End;

Function SRule(P:Int64):LongInt;Begin SRule:=LongInt(P shr 32);End;
Function SElem(P:Int64):LongInt;Begin SElem:=LongInt(P and $FFFFFFFF);End;
Function SMake(R,E:LongInt):Int64;Begin SMake:=(Int64(R)shl 32)or Int64(E);End;

Procedure GAdvanceStack(Const G:TGrammar;Const Stack:TGStack;Var NewStacks:TGStackList);
Var
 Todo,Seen:TGStackList;
 Cur,Nx:TGStack;
 Pos_:Int64;
 R,E,SubE:LongInt;
 NT:LongInt;
Begin
 SetLength(Todo,0);SetLength(Seen,0);
 StackAdd(Todo,Stack);
 While Length(Todo)>0 do Begin
  Cur:=Todo[High(Todo)];
  SetLength(Todo,Length(Todo)-1);
  If StackFind(Seen,Cur)Then Continue;
  StackAdd(Seen,Cur);
  If Length(Cur)=0 Then Begin
   If not StackFind(NewStacks,Cur)Then StackAdd(NewStacks,Cur);
   Continue;
  End;
  Pos_:=Cur[High(Cur)];
  R:=SRule(Pos_);E:=SElem(Pos_);
  Case G.Rules[R][E].T of
   GRE_RULE_REF:Begin
    NT:=G.Rules[R][E].V;
    SubE:=0;
    While True do Begin
     Nx:=StackPopTop(Cur);
     If not GIsEndOfSeq(G.Rules[R],E+1)Then Nx:=StackPush(Nx,SMake(R,E+1));
     If not GIsEndOfSeq(G.Rules[NT],SubE)Then Nx:=StackPush(Nx,SMake(NT,SubE));
     StackAdd(Todo,Nx);
     While not GIsEndOfSeq(G.Rules[NT],SubE)do Inc(SubE);
     If G.Rules[NT][SubE].T=GRE_ALT Then Inc(SubE)Else Break;
    End;
   End;
   GRE_CHAR,GRE_CHAR_NOT,GRE_CHAR_ANY,GRE_TOKEN,GRE_TOKEN_NOT:Begin
    If not StackFind(NewStacks,Cur)Then StackAdd(NewStacks,Cur);
   End;
   Else Begin
    { ne devrait jamais arriver }
   End;
  End;
 End;
End;

{ Teste si chr satisfait l'intervalle a la position ; renvoie la position apres }
Function GMatchChar(Const R:TGRule;E:LongInt;Chr:LongWord;Var After:LongInt):Boolean;
Var
 Found,IsPos:Boolean;
Begin
 Found:=False;
 IsPos:=(R[E].T=GRE_CHAR)or(R[E].T=GRE_CHAR_ANY);
 Repeat
  If R[E+1].T=GRE_CHAR_RNG_UPPER Then Begin
   Found:=Found or((R[E].V<=Chr)and(Chr<=R[E+1].V));
   Inc(E,2);
  End
   Else If R[E].T=GRE_CHAR_ANY Then Begin
    Found:=True;
    Inc(E);
   End
   Else Begin
    Found:=Found or(R[E].V=Chr);
    Inc(E);
   End;
 Until R[E].T<>GRE_CHAR_ALT;
 After:=E;
 GMatchChar:=(Found=IsPos);
End;

Function GMatchPartialChar(Const R:TGRule;E:LongInt;PV:LongWord;PN:LongInt):Boolean;
Var
 IsPos:Boolean;
 Low,High_:LongWord;
Begin
 IsPos:=(R[E].T=GRE_CHAR)or(R[E].T=GRE_CHAR_ANY);
 If(PN<0)or((PN=1)and(PV<2))Then Begin GMatchPartialChar:=False;Exit;End;
 Low:=PV shl(PN*6);
 High_:=Low or((LongWord(1)shl(PN*6))-1);
 If Low=0 Then Begin
  If PN=2 Then Low:=LongWord(1)shl 11
  Else If PN=3 Then Low:=LongWord(1)shl 16;
 End;
 Repeat
  If R[E+1].T=GRE_CHAR_RNG_UPPER Then Begin
   If(R[E].V<=High_)and(Low<=R[E+1].V)Then Begin GMatchPartialChar:=IsPos;Exit;End;
   Inc(E,2);
  End
   Else If R[E].T=GRE_CHAR_ANY Then Begin GMatchPartialChar:=True;Exit;End
   Else Begin
    If(Low<=R[E].V)and(R[E].V<=High_)Then Begin GMatchPartialChar:=IsPos;Exit;End;
    Inc(E);
   End;
 Until R[E].T<>GRE_CHAR_ALT;
 GMatchPartialChar:=not IsPos;
End;

Function GMatchToken(T:LongInt;V:LongWord;Tok:LongInt):Boolean;
Begin
 If T=GRE_TOKEN Then GMatchToken:=V=LongWord(Tok)
 Else GMatchToken:=V<>LongWord(Tok);
End;

Procedure GAcceptChr(Const G:TGrammar;Const Stack:TGStack;Chr:LongWord;Var NewStacks:TGStackList);
Var
 Pos_:Int64;
 R,E,After:LongInt;
 Nx:TGStack;
Begin
 If Length(Stack)=0 Then Exit;
 Pos_:=Stack[High(Stack)];
 R:=SRule(Pos_);E:=SElem(Pos_);
 If(G.Rules[R][E].T=GRE_TOKEN)or(G.Rules[R][E].T=GRE_TOKEN_NOT)Then Exit;
 If GMatchChar(G.Rules[R],E,Chr,After)Then Begin
  Nx:=StackPopTop(Stack);
  If not GIsEndOfSeq(G.Rules[R],After)Then Nx:=StackPush(Nx,SMake(R,After));
  GAdvanceStack(G,Nx,NewStacks);
 End;
End;

Procedure GAcceptCp(Var G:TGrammar;Chr:LongWord);
Var
 New_:TGStackList;
 I:LongInt;
Begin
 SetLength(New_,0);
 For I:=0 to High(G.Stacks)do GAcceptChr(G,G.Stacks[I],Chr,New_);
 G.Stacks:=New_;
End;

Function GPoolPtr(Off:LongInt):LongWord;
Begin
 GPoolPtr:=GCpPool[Off];
End;

Function GRejectCands(Const G:TGrammar;Const Stacks:TGStackList;Const Cands:TGCandArr):TGCandArr;Forward;

Function GRejectForStack(Const G:TGrammar;Const Stack:TGStack;Const Cands:TGCandArr):TGCandArr;
Var
 Rej,Next,NextRej:TGCandArr;
 NR,NN:LongInt;
 I:LongInt;
 Pos_:Int64;
 R,E,After:LongInt;
 Tk:TGCand;
 StackAfter:TGStack;
 NextStacks:TGStackList;
 Cp:LongWord;

 Procedure AddRej(Const C:TGCand);
 Begin
  If NR>=Length(Rej)Then SetLength(Rej,Length(Rej)*2+16);
  Rej[NR]:=C;Inc(NR);
 End;

Begin
 NR:=0;
 SetLength(Rej,Length(Cands)+1);
 If Length(Stack)=0 Then Begin
  For I:=0 to High(Cands)do Begin
   Tk:=Cands[I];
   If(GCpPool[Tk.CP]<>0)or(Tk.PN<>0)Then AddRej(Tk);
  End;
  SetLength(Rej,NR);
  GRejectForStack:=Rej;
  Exit;
 End;
 Pos_:=Stack[High(Stack)];
 R:=SRule(Pos_);E:=SElem(Pos_);
 If(G.Rules[R][E].T=GRE_TOKEN)or(G.Rules[R][E].T=GRE_TOKEN_NOT)Then Begin
  For I:=0 to High(Cands)do Begin
   Tk:=Cands[I];
   If GCpPool[Tk.CP]=0 Then Begin
    If Tk.PN<>0 Then AddRej(Tk);
   End
    Else If not GMatchToken(G.Rules[R][E].T,G.Rules[R][E].V,Tk.Id)Then AddRej(Tk);
  End;
  SetLength(Rej,NR);
  GRejectForStack:=Rej;
  Exit;
 End;
 NN:=0;
 SetLength(Next,Length(Cands)+1);
 For I:=0 to High(Cands)do Begin
  Tk:=Cands[I];
  Cp:=GCpPool[Tk.CP];
  If Cp=0 Then Begin
   If(Tk.PN<>0)and not GMatchPartialChar(G.Rules[R],E,Tk.PV,Tk.PN)Then AddRej(Tk);
  End
   Else If GMatchChar(G.Rules[R],E,Cp,After)Then Begin
    Next[NN]:=Tk;Inc(Next[NN].CP);Inc(NN);
   End
   Else AddRej(Tk);
 End;
 SetLength(Next,NN);
 GMatchChar(G.Rules[R],E,0,After);
 StackAfter:=StackPopTop(Stack);
 If not GIsEndOfSeq(G.Rules[R],After)Then StackAfter:=StackPush(StackAfter,SMake(R,After));
 SetLength(NextStacks,0);
 GAdvanceStack(G,StackAfter,NextStacks);
 NextRej:=GRejectCands(G,NextStacks,Next);
 For I:=0 to High(NextRej)do Begin
  Tk:=NextRej[I];
  Dec(Tk.CP);
  AddRej(Tk);
 End;
 SetLength(Rej,NR);
 GRejectForStack:=Rej;
End;

Function GRejectCands(Const G:TGrammar;Const Stacks:TGStackList;Const Cands:TGCandArr):TGCandArr;
Var
 Rej:TGCandArr;
 I:LongInt;
Begin
 If Length(Cands)=0 Then Begin SetLength(Rej,0);GRejectCands:=Rej;Exit;End;
 Rej:=GRejectForStack(G,Stacks[0],Cands);
 For I:=1 to High(Stacks)do Rej:=GRejectForStack(G,Stacks[I],Rej);
 GRejectCands:=Rej;
End;

{ decode_utf8 avec etat partiel : ajoute les points de code au tampon, termine par 0 }
Procedure GDecodeToPool(Const S:AnsiString;Var PV:LongWord;Var PN:LongInt);
Var
 I,L:LongInt;
 B:Byte;
 Value:LongWord;
 NRemain:LongInt;
 Lookup:Array[0..15]of LongInt;

 Procedure Put(V:LongWord);
 Begin
  If GCpPoolN>=Length(GCpPool)Then SetLength(GCpPool,Length(GCpPool)*2+1024);
  GCpPool[GCpPoolN]:=V;Inc(GCpPoolN);
 End;

Begin
 Lookup[0]:=1;Lookup[1]:=1;Lookup[2]:=1;Lookup[3]:=1;Lookup[4]:=1;Lookup[5]:=1;Lookup[6]:=1;Lookup[7]:=1;
 Lookup[8]:=0;Lookup[9]:=0;Lookup[10]:=0;Lookup[11]:=0;Lookup[12]:=2;Lookup[13]:=2;Lookup[14]:=3;Lookup[15]:=4;
 Value:=PV;NRemain:=PN;
 I:=1;L:=Length(S);
 While(I<=L)and(NRemain>0)do Begin
  B:=Ord(S[I]);
  If(B shr 6)<>2 Then Begin
   Put(0);
   PV:=0;PN:=-1;
   Exit;
  End;
  Value:=(Value shl 6)+(B and $3F);
  Inc(I);Dec(NRemain);
 End;
 If(PN>0)and(NRemain=0)Then Put(Value);
 While I<=L do Begin
  B:=Ord(S[I]);
  NRemain:=Lookup[B shr 4]-1;
  If NRemain<0 Then Begin
   { sequence invalide : on annule }
   Put(0);
   PV:=0;PN:=NRemain;
   Exit;
  End;
  Value:=B and((1 shl(7-NRemain))-1);
  Inc(I);
  While(I<=L)and(NRemain>0)do Begin
   Value:=(Value shl 6)+(Ord(S[I])and $3F);
   Inc(I);Dec(NRemain);
  End;
  If NRemain=0 Then Put(Value);
 End;
 Put(0);
 PV:=Value;PN:=NRemain;
End;

Function GrammarInit(Const Src,RootName:AnsiString;Var V:TVocab;Var G:TGrammar):Boolean;
Var
 Pos_,I,J,RootId,Start:LongInt;
 Visited,InProg,MayEmpty:TBoolArray;
 Stacks:TGStackList;
 St:TGStack;
 R:TGRule;
 SymName:AnsiString;
 Found:Boolean;
Begin
 GrammarInit:=False;
 GErr:='';
 GSrc:=Src;
 GVocab:=@V;
 SetLength(G.Rules,0);SetLength(G.SymNames,0);SetLength(G.Stacks,0);
 HInit(G.SymHash,64);
 G.PartialV:=0;G.PartialN:=0;
 Pos_:=GParseSpace(1,True);
 While(GCh(Pos_)<>#0)and(GErr='')do Pos_:=GParseRule(G,Pos_);
 If GErr='' Then Begin
  For I:=0 to High(G.Rules)do Begin
   If Length(G.Rules[I])=0 Then Begin GFail('Undefined rule');Break;End;
   For J:=0 to High(G.Rules[I])do
    If G.Rules[I][J].T=GRE_RULE_REF Then Begin
     If(G.Rules[I][J].V>=LongWord(Length(G.Rules)))or(Length(G.Rules[G.Rules[I][J].V])=0)Then Begin
      SymName:='?';
      If G.Rules[I][J].V<LongWord(Length(G.SymNames))Then SymName:=G.SymNames[G.Rules[I][J].V];
      GFail('Undefined rule identifier '''+SymName+'''');
     End;
    End;
   If GErr<>'' Then Break;
  End;
 End;
 If(GErr='')and(Length(G.Rules)=0)Then GFail('grammaire vide');
 If GErr<>'' Then Begin
  LogErr('GBNF : erreur d''analyse de la grammaire : '+GErr+#10+#10+Src+#10);
  Exit;
 End;
 RootId:=HFind(G.SymHash,RootName);
 If RootId<0 Then Begin
  LogErr('la grammaire ne contient pas de symbole '''+RootName+''''+#10);
  Exit;
 End;
 G.Root:=RootId;
 SetLength(Visited,Length(G.Rules));SetLength(InProg,Length(G.Rules));SetLength(MayEmpty,Length(G.Rules));
 For I:=0 to High(G.Rules)do Begin Visited[I]:=False;InProg[I]:=False;MayEmpty[I]:=False;End;
 For I:=0 to High(G.Rules)do Begin
  If Visited[I]Then Continue;
  If GDetectLeftRec(G,I,Visited,InProg,MayEmpty)Then Begin
   LogErr('grammaire non supportée : récursion à gauche détectée pour le non-terminal à l''indice '+IStr(I)+#10);
   Exit;
  End;
 End;
 { piles initiales }
 SetLength(G.Stacks,0);
 R:=G.Rules[RootId];
 Start:=0;
 Repeat
  SetLength(St,0);
  If not GIsEndOfSeq(R,Start)Then St:=StackPush(St,SMake(RootId,Start));
  GAdvanceStack(G,St,G.Stacks);
  While not GIsEndOfSeq(R,Start)do Inc(Start);
  If R[Start].T=GRE_ALT Then Begin Inc(Start);Found:=True;End Else Found:=False;
 Until not Found;
 GrammarInit:=True;
End;

Function GrammarClone(Const G:TGrammar):TGrammar;
Begin
 GrammarClone:=G;
End;

{ Applique la grammaire aux candidats : met a -inf ceux qui sont rejetes }
Procedure GrammarApply(Var G:TGrammar;Var V:TVocab;Var C:TCandSet);
Var
 AllowEog:Boolean;
 I:LongInt;
 Cands:TGCandArr;
 NC:LongInt;
 Rej:TGCandArr;
 Piece:AnsiString;
 PV:LongWord;
 PN:LongInt;
 Id:LongInt;
Begin
 AllowEog:=False;
 For I:=0 to High(G.Stacks)do If Length(G.Stacks[I])=0 Then Begin AllowEog:=True;Break;End;
 GCpPoolN:=0;
 SetLength(GCpPool,1024);
 SetLength(Cands,C.N);
 NC:=0;
 For I:=0 to C.N-1 do Begin
  Id:=C.D[I].Id;
  If VocabIsEOG(V,Id)Then Begin
   If not AllowEog Then C.D[I].Logit:=NegInf;
  End
   Else Begin
    Piece:=TokenToPiece(V,Id,True,0);
    If(Piece='')or(Piece[1]=#0)Then C.D[I].Logit:=NegInf
    Else Begin
     PV:=G.PartialV;PN:=G.PartialN;
     Cands[NC].Index:=I;
     Cands[NC].CP:=GCpPoolN;
     Cands[NC].Id:=Id;
     GDecodeToPool(Piece,PV,PN);
     Cands[NC].PV:=PV;Cands[NC].PN:=PN;
     Inc(NC);
    End;
   End;
 End;
 SetLength(Cands,NC);
 Rej:=GRejectCands(G,G.Stacks,Cands);
 For I:=0 to High(Rej)do C.D[Rej[I].Index].Logit:=NegInf;
End;

Procedure GrammarAcceptToken(Var G:TGrammar;Var V:TVocab;Tok:LongInt);
Var
 Piece:AnsiString;
 Cur,Nxt:TGStackList;
 NewS:TGStackList;
 I,K,Off:LongInt;
 PV:LongWord;
 PN:LongInt;
 Pos_:Int64;
 R,E:LongInt;
 Nx:TGStack;
 Cp:LongWord;
 Surv:TGStackList;
Begin
 Piece:=TokenToPiece(V,Tok,True,0);
 If VocabIsEOG(V,Tok)Then Begin
  For I:=0 to High(G.Stacks)do If Length(G.Stacks[I])=0 Then Exit;
  Exit;
 End;
 GCpPoolN:=0;
 SetLength(GCpPool,1024);
 PV:=G.PartialV;PN:=G.PartialN;
 Off:=0;
 GDecodeToPool(Piece,PV,PN);
 SetLength(NewS,0);
 For I:=0 to High(G.Stacks)do Begin
  If Length(G.Stacks[I])=0 Then Continue;
  Pos_:=G.Stacks[I][High(G.Stacks[I])];
  R:=SRule(Pos_);E:=SElem(Pos_);
  If(G.Rules[R][E].T=GRE_TOKEN)or(G.Rules[R][E].T=GRE_TOKEN_NOT)Then Begin
   If GMatchToken(G.Rules[R][E].T,G.Rules[R][E].V,Tok)Then Begin
    Nx:=StackPopTop(G.Stacks[I]);
    If not GIsEndOfSeq(G.Rules[R],E+1)Then Nx:=StackPush(Nx,SMake(R,E+1));
    GAdvanceStack(G,Nx,NewS);
   End;
  End
   Else Begin
    SetLength(Cur,0);
    StackAdd(Cur,G.Stacks[I]);
    K:=0;
    While GCpPool[K]<>0 do Begin
     SetLength(Nxt,0);
     Cp:=GCpPool[K];
     For E:=0 to High(Cur)do GAcceptChr(G,Cur[E],Cp,Nxt);
     Cur:=Nxt;
     If Length(Cur)=0 Then Break;
     Inc(K);
    End;
    For E:=0 to High(Cur)do
     If not StackFind(NewS,Cur[E])Then StackAdd(NewS,Cur[E]);
   End;
 End;
 G.Stacks:=NewS;
 G.PartialV:=PV;G.PartialN:=PN;
End;

Function GrammarIsComplete(Const G:TGrammar):Boolean;
Var
 I:LongInt;
Begin
 GrammarIsComplete:=False;
 For I:=0 to High(G.Stacks)do If Length(G.Stacks[I])=0 Then GrammarIsComplete:=True;
End;

{ ------------------------------------------------------------------ }
{ Echantillonnage                                                     }
{ ------------------------------------------------------------------ }

Const
 SK_PENALTIES=1; SK_DRY=2; SK_TOPNSIGMA=3; SK_TOPK=4; SK_TYPP=5; SK_TOPP=6;
 SK_MINP=7; SK_XTC=8; SK_TEMP=9; SK_INFILL=10; SK_ADAPTIVE=11;
 DefaultSeed=$FFFFFFFF;

Type
 TLogitBias=Record
  Tok:LongInt;
  Bias:Single;
 End;

 TSampParams=Record
  Seed:LongWord;
  NPrev:LongInt;
  TopK:LongInt;
  TopP,MinP,TopNSigma,XtcP,XtcT,TypP:Single;
  Temp,DynRange,DynExp:Single;
  PenaltyLastN:LongInt;
  PenaltyRepeat,PenaltyFreq,PenaltyPresent:Single;
  DryMult,DryBase:Single;
  DryAllowed,DryLastN:LongInt;
  DryBreakers:TStrArray;
  Mirostat:LongInt;
  MiroTau,MiroEta:Single;
  AdaptiveTarget,AdaptiveDecay:Single;
  MinKeep:LongInt;
  Order:TIntArray;
  Bias:Array of TLogitBias;
  Grammar:AnsiString;
  IgnoreEos:Boolean;
 End;

 TDryBreaker=Record
  Head:LongInt;
  Tail:TIntArray;
 End;

 TSampler=Record
  P:TSampParams;
  SeedCur:LongWord;
  NVocab:LongInt;
  Prev:TIntArray;
  PrevN:LongInt;
  PenRing:TIntArray;
  PenPos,PenCount:LongInt;
  PenCnt:TIntArray;
  DryLast:TIntArray;
  DryBr:Array of TDryBreaker;
  Mu:Single;
  RngDist,RngXtc,RngMiro:TMT;
  Gram:TGrammar;
  HasGrammar:Boolean;
  AdaptiveTargetCur,AdaptiveWeighted,AdaptiveTotal:Double;
  Cands:TCandSet;
  EogBias:Boolean;
 End;

Procedure SampDefaults(Var P:TSampParams);
Begin
 P.Seed:=DefaultSeed;
 P.NPrev:=64;
 P.TopK:=40;P.TopP:=0.95;P.MinP:=0.05;P.TopNSigma:=-1;
 P.XtcP:=0;P.XtcT:=0.1;P.TypP:=1.0;
 P.Temp:=0.8;P.DynRange:=0;P.DynExp:=1.0;
 P.PenaltyLastN:=64;P.PenaltyRepeat:=1.0;P.PenaltyFreq:=0;P.PenaltyPresent:=0;
 P.DryMult:=0;P.DryBase:=1.75;P.DryAllowed:=2;P.DryLastN:=64;
 SetLength(P.DryBreakers,0);
 AddStr(P.DryBreakers,#10);AddStr(P.DryBreakers,':');AddStr(P.DryBreakers,'"');AddStr(P.DryBreakers,'*');
 P.Mirostat:=0;P.MiroTau:=5.0;P.MiroEta:=0.1;
 P.AdaptiveTarget:=-1;P.AdaptiveDecay:=0.9;
 P.MinKeep:=0;
 SetLength(P.Order,0);
 AddInt(P.Order,SK_PENALTIES);AddInt(P.Order,SK_DRY);AddInt(P.Order,SK_TOPNSIGMA);
 AddInt(P.Order,SK_TOPK);AddInt(P.Order,SK_TYPP);AddInt(P.Order,SK_TOPP);
 AddInt(P.Order,SK_MINP);AddInt(P.Order,SK_XTC);AddInt(P.Order,SK_TEMP);
 SetLength(P.Bias,0);
 P.Grammar:='';
 P.IgnoreEos:=False;
End;

{ tri decroissant sur Logit (ties : identifiant croissant) }
Function CandBefore(Const A,B:TCand):Boolean;
Begin
 CandBefore:=(A.Logit>B.Logit)or((A.Logit=B.Logit)and(A.Id<B.Id));
End;

Procedure QSortCands(Var D:Array of TCand;Lo,Hi:LongInt);
Var
 I,J:LongInt;
 Piv,T:TCand;
Begin
 While Lo<Hi do Begin
  If Hi-Lo<16 Then Begin
   For I:=Lo+1 to Hi do Begin
    T:=D[I];J:=I-1;
    While(J>=Lo)and CandBefore(T,D[J])do Begin D[J+1]:=D[J];Dec(J);End;
    D[J+1]:=T;
   End;
   Exit;
  End;
  { pivot : mediane de trois }
  I:=(Lo+Hi)shr 1;
  If CandBefore(D[I],D[Lo])Then Begin T:=D[I];D[I]:=D[Lo];D[Lo]:=T;End;
  If CandBefore(D[Hi],D[Lo])Then Begin T:=D[Hi];D[Hi]:=D[Lo];D[Lo]:=T;End;
  If CandBefore(D[Hi],D[I])Then Begin T:=D[Hi];D[Hi]:=D[I];D[I]:=T;End;
  Piv:=D[I];
  I:=Lo;J:=Hi;
  Repeat
   While CandBefore(D[I],Piv)do Inc(I);
   While CandBefore(Piv,D[J])do Dec(J);
   If I<=J Then Begin
    T:=D[I];D[I]:=D[J];D[J]:=T;
    Inc(I);Dec(J);
   End;
  Until I>J;
  If J-Lo<Hi-I Then Begin
   QSortCands(D,Lo,J);
   Lo:=I;
  End
   Else Begin
    QSortCands(D,I,Hi);
    Hi:=J;
   End;
 End;
End;

{ Conserve les K meilleurs candidats tries (K <= N) }
Procedure PartialSortDesc(Var C:TCandSet;K:LongInt);
Var
 Heap:Array of TCand;
 HN,I,P,Ch:LongInt;
 T:TCand;
Begin
 If K>=C.N Then Begin
  QSortCands(C.D,0,C.N-1);
  C.Sorted:=True;
  Exit;
 End;
 If K<=0 Then Begin C.N:=0;C.Sorted:=True;Exit;End;
 { tas minimal de taille K : la racine est le plus mauvais retenu }
 SetLength(Heap,K);
 HN:=0;
 For I:=0 to C.N-1 do Begin
  If HN<K Then Begin
   Heap[HN]:=C.D[I];
   P:=HN;Inc(HN);
   While P>0 do Begin
    Ch:=(P-1)shr 1;
    If CandBefore(Heap[Ch],Heap[P])Then Begin T:=Heap[Ch];Heap[Ch]:=Heap[P];Heap[P]:=T;P:=Ch;End
    Else Break;
   End;
  End
   Else If CandBefore(C.D[I],Heap[0])Then Begin
    Heap[0]:=C.D[I];
    P:=0;
    While True do Begin
     Ch:=2*P+1;
     If Ch>=HN Then Break;
     If(Ch+1<HN)and CandBefore(Heap[Ch],Heap[Ch+1])Then Inc(Ch);
     If CandBefore(Heap[P],Heap[Ch])Then Begin T:=Heap[P];Heap[P]:=Heap[Ch];Heap[Ch]:=T;P:=Ch;End
     Else Break;
    End;
   End;
 End;
 For I:=0 to K-1 do C.D[I]:=Heap[I];
 C.N:=K;
 QSortCands(C.D,0,K-1);
 C.Sorted:=True;
End;

Procedure SoftmaxCands(Var C:TCandSet;DoSort:Boolean);
Var
 I:LongInt;
 Mx,Sum:Single;
Begin
 If C.N=0 Then Exit;
 If DoSort and not C.Sorted Then PartialSortDesc(C,C.N);
 Mx:=C.D[0].Logit;
 If not C.Sorted Then
  For I:=1 to C.N-1 do If C.D[I].Logit>Mx Then Mx:=C.D[I].Logit;
 Sum:=0;
 For I:=0 to C.N-1 do Begin
  C.D[I].P:=Exp(C.D[I].Logit-Mx);
  Sum:=Sum+C.D[I].P;
 End;
 For I:=0 to C.N-1 do C.D[I].P:=C.D[I].P/Sum;
End;

Procedure TempImpl(Var C:TCandSet;Temp:Single);
Var
 I,MaxI:LongInt;
 MaxL:Single;
Begin
 If C.N=0 Then Exit;
 If Temp<=0 Then Begin
  MaxI:=0;MaxL:=C.D[0].Logit;
  For I:=1 to C.N-1 do Begin
   If C.D[I].Logit>MaxL Then Begin
    C.D[MaxI].Logit:=NegInf;
    MaxI:=I;MaxL:=C.D[I].Logit;
   End
    Else C.D[I].Logit:=NegInf;
  End;
  Exit;
 End;
 For I:=0 to C.N-1 do C.D[I].Logit:=C.D[I].Logit/Temp;
End;

Procedure TopKImpl(Var C:TCandSet;K:LongInt);
Begin
 If K<=0 Then Exit;
 If K>C.N Then K:=C.N;
 If not C.Sorted Then PartialSortDesc(C,K)
 Else C.N:=K;
End;

Procedure ApplyTopP(Var C:TCandSet;P:Single;MinKeep:LongInt);
Var
 I,Last:LongInt;
 Cum:Single;
Begin
 If P>=1.0 Then Exit;
 SoftmaxCands(C,False);
 If not C.Sorted Then PartialSortDesc(C,C.N);
 Cum:=0;
 Last:=C.N;
 For I:=0 to C.N-1 do Begin
  Cum:=Cum+C.D[I].P;
  If(Cum>=P)and(I+1>=MinKeep)Then Begin Last:=I+1;Break;End;
 End;
 C.N:=Last;
End;

Procedure ApplyMinP(Var C:TCandSet;P:Single;MinKeep:LongInt);
Var
 I,K:LongInt;
 MaxL,MinL:Single;
 Applied:Boolean;
 Tmp:Array of TCand;
Begin
 If(P<=0)or(C.N=0)Then Exit;
 Applied:=False;
 If not C.Sorted Then Begin
  MaxL:=-3.4e38;
  For I:=0 to C.N-1 do If C.D[I].Logit>MaxL Then MaxL:=C.D[I].Logit;
  MinL:=MaxL+Ln(P);
  K:=0;
  For I:=0 to C.N-1 do If C.D[I].Logit>=MinL Then Inc(K);
  If(K>0)and(K>=MinKeep)Then Begin
   SetLength(Tmp,K);
   K:=0;
   For I:=0 to C.N-1 do If C.D[I].Logit>=MinL Then Begin Tmp[K]:=C.D[I];Inc(K);End;
   For I:=0 to K-1 do C.D[I]:=Tmp[I];
   C.N:=K;
   Applied:=True;
  End;
 End;
 If not Applied Then Begin
  If not C.Sorted Then PartialSortDesc(C,C.N);
  MinL:=C.D[0].Logit+Ln(P);
  I:=1;
  While I<C.N do Begin
   If(C.D[I].Logit<MinL)and(I>=MinKeep)Then Break;
   Inc(I);
  End;
  C.N:=I;
 End;
End;

Procedure ApplyTypical(Var C:TCandSet;P:Single;MinKeep:LongInt);
Var
 I,J,Last:LongInt;
 Entropy,Cum:Single;
 Shifted:Array of Single;
 Idx:Array of LongInt;
 T:LongInt;
 NewD:Array of TCand;
Begin
 If P>=1.0 Then Exit;
 SoftmaxCands(C,True);
 Entropy:=0;
 For I:=0 to C.N-1 do Entropy:=Entropy-C.D[I].P*Ln(C.D[I].P);
 SetLength(Shifted,C.N);SetLength(Idx,C.N);
 For I:=0 to C.N-1 do Begin
  Shifted[I]:=Abs(-Ln(C.D[I].P)-Entropy);
  Idx[I]:=I;
 End;
 { tri par insertion/fusion simplifie : tri a bulles evite -> tri par insertion sur indices (stable) }
 For I:=1 to C.N-1 do Begin
  T:=Idx[I];J:=I-1;
  While(J>=0)and(Shifted[Idx[J]]>Shifted[T])do Begin Idx[J+1]:=Idx[J];Dec(J);End;
  Idx[J+1]:=T;
 End;
 Cum:=0;Last:=C.N;
 For I:=0 to C.N-1 do Begin
  Cum:=Cum+C.D[Idx[I]].P;
  If(Cum>P)and((MinKeep=0)or(I>=MinKeep-1))Then Begin Last:=I+1;Break;End;
 End;
 SetLength(NewD,Last);
 For I:=0 to Last-1 do NewD[I]:=C.D[Idx[I]];
 For I:=0 to Last-1 do C.D[I]:=NewD[I];
 C.N:=Last;
 C.Sorted:=False;
End;

Procedure ApplyTempExt(Var C:TCandSet;Temp,Delta,Expo:Single);
Var
 I:LongInt;
 MinT,MaxT,MaxEnt,Entropy,Pr,NormEnt,Dyn:Single;
 MaxL,Sum,Pd:Double;
Begin
 If Delta>0 Then Begin
  MinT:=FMax(0,Temp-Delta);
  MaxT:=Temp+Delta;
  If C.N<=1 Then Exit;
  MaxEnt:=-Ln(1.0/C.N);
  SoftmaxCands(C,True);
  Entropy:=0;
  For I:=0 to C.N-1 do Begin
   Pr:=C.D[I].P;
   If Pr>0 Then Entropy:=Entropy-Pr*Ln(Pr);
  End;
  NormEnt:=Entropy/MaxEnt;
  Dyn:=MinT+(MaxT-MinT)*FPow(NormEnt,Expo);
  TempImpl(C,Dyn);
  MaxL:=C.D[0].Logit;
  Sum:=0;
  For I:=0 to C.N-1 do Begin
   Pd:=Exp(C.D[I].Logit-MaxL);
   C.D[I].P:=Pd;
   Sum:=Sum+Pd;
  End;
  For I:=0 to C.N-1 do C.D[I].P:=C.D[I].P/Sum;
 End
  Else TempImpl(C,Temp);
End;

Procedure ApplyXtc(Var C:TCandSet;Var S:TSampler);
Var
 Chance:Single;
 I,PosLast:LongInt;
Begin
 If(S.P.XtcP<=0)or(S.P.XtcT>0.5)or(C.N<2)Then Exit;
 Chance:=MTUniformF(S.RngXtc);
 If Chance>S.P.XtcP Then Exit;
 SoftmaxCands(C,True);
 PosLast:=0;
 For I:=0 to C.N-1 do Begin
  If C.D[I].P>=S.P.XtcT Then PosLast:=I Else Break;
 End;
 If(C.N-PosLast>=S.P.MinKeep)and(PosLast>0)Then Begin
  Move(C.D[PosLast],C.D[0],(C.N-PosLast)*SizeOf(TCand));
  Dec(C.N,PosLast);
 End;
End;

Procedure ApplyTopNSigma(Var C:TCandSet;N:Single);
Var
 I,Valid:LongInt;
 Mx,Sum,Mean,Acc,Sd:Double;
Begin
 If(N<=0)or(C.N<=1)Then Exit;
 Mx:=C.D[0].Logit;Sum:=0;Valid:=0;
 For I:=0 to C.N-1 do
  If C.D[I].Logit>NegInf/2 Then Begin
   If C.D[I].Logit>Mx Then Mx:=C.D[I].Logit;
   Sum:=Sum+C.D[I].Logit;
   Inc(Valid);
  End;
 If Valid>0 Then Mean:=Sum/Valid Else Mean:=0;
 Acc:=0;
 For I:=0 to C.N-1 do
  If C.D[I].Logit>NegInf/2 Then Acc:=Acc+Sqr(C.D[I].Logit-Mean);
 If Valid>0 Then Sd:=Sqrt(Acc/Valid)Else Sd:=0;
 For I:=0 to C.N-1 do
  If C.D[I].Logit<Mx-(N*Sd)Then C.D[I].Logit:=NegInf;
End;

Function PenaltiesDisabled(Const S:TSampler):Boolean;
Begin
 PenaltiesDisabled:=(S.P.PenaltyLastN<=0)or((S.P.PenaltyRepeat=1.0)and(S.P.PenaltyFreq=0)and(S.P.PenaltyPresent=0));
End;

Procedure ApplyPenalties(Var C:TCandSet;Var S:TSampler);
Var
 I,Cnt:LongInt;
Begin
 If PenaltiesDisabled(S)Then Exit;
 For I:=0 to C.N-1 do Begin
  Cnt:=S.PenCnt[C.D[I].Id];
  If Cnt<=0 Then Continue;
  If C.D[I].Logit<=0 Then C.D[I].Logit:=C.D[I].Logit*S.P.PenaltyRepeat
                     Else C.D[I].Logit:=C.D[I].Logit/S.P.PenaltyRepeat;
  C.D[I].Logit:=C.D[I].Logit-(Cnt*S.P.PenaltyFreq+Ord(Cnt>0)*S.P.PenaltyPresent);
 End;
 C.Sorted:=False;
End;

Function DryRat(Const S:TSampler;I:LongInt):LongInt;
Begin
 DryRat:=S.DryLast[Length(S.DryLast)-1-I];
End;

Procedure ApplyDry(Var C:TCandSet;Var S:TSampler);
Var
 LastN,RepLimit,I,J,K,Off,Best,SeqLen,LongestMatch,N,Lt,Rt,P,RightPart,Last_,RepeatLen:LongInt;
 RepCount:TIntArray;
 MaxTokRepeat:Array of LongInt;       { par identifiant de jeton, 0 = absent }
 Match:Boolean;
 Tok:LongInt;
 MaxExp:LongInt;
 ExpV:LongInt;
 Pen:Single;
 UsedToks:TIntArray;
Begin
 If(S.P.DryMult=0)or(S.P.DryBase<1.0)or(S.P.DryLastN=0)Then Exit;
 LastN:=Length(S.DryLast);
 If LastN>S.P.DryLastN Then LastN:=S.P.DryLastN;
 If LastN<=S.P.DryAllowed Then Exit;
 SetLength(RepCount,LastN);
 For I:=0 to LastN-1 do RepCount[I]:=0;
 { etape 1 : sequences de redemarrage }
 RepLimit:=LastN;
 For I:=0 to LastN-1 do Begin
  Tok:=DryRat(S,I);
  LongestMatch:=-1;
  For J:=0 to High(S.DryBr)do Begin
   If S.DryBr[J].Head<>Tok Then Continue;
   SeqLen:=Length(S.DryBr[J].Tail);
   If(SeqLen>LongestMatch)and(SeqLen<=I)Then Begin
    Match:=True;
    For Off:=0 to SeqLen-1 do
     If S.DryBr[J].Tail[Off]<>DryRat(S,I-Off-1)Then Begin Match:=False;Break;End;
    If Match Then LongestMatch:=SeqLen;
   End;
  End;
  If LongestMatch>=0 Then Begin
   RepLimit:=I-LongestMatch;
   Break;
  End;
 End;
 If RepLimit<S.P.DryAllowed Then Exit;
 { etape 2 : algorithme Z a l'envers }
 Last_:=LastN-1;
 Rt:=0;Lt:=0;
 For K:=1 to LastN-1 do Begin
  If K>Rt Then Begin
   N:=0;
   While(N+K<LastN)and(DryRat(S,N)=DryRat(S,N+K))do Inc(N);
   RepCount[Last_-K]:=IMin(N,RepLimit);
   If N>0 Then Begin Lt:=K;Rt:=K+N-1;End;
  End
   Else Begin
    P:=K-Lt;
    RightPart:=Rt-K+1;
    If RepCount[Last_-P]<RightPart Then Begin
     N:=IMin(RepCount[Last_-P],RepLimit);
     RepCount[Last_-K]:=N;
    End
     Else Begin
      I:=Rt+1;
      While(I<LastN)and(DryRat(S,I)=DryRat(S,I-K))do Inc(I);
      N:=IMin(I-K,RepLimit);
      RepCount[Last_-K]:=N;
      Lt:=K;Rt:=I-1;
     End;
   End;
 End;
 { etape 3 : longueur maximale par jeton }
 SetLength(MaxTokRepeat,S.NVocab);
 SetLength(UsedToks,0);
 For I:=0 to LastN-2 do Begin
  RepeatLen:=RepCount[I];
  If RepeatLen>=S.P.DryAllowed Then Begin
   Tok:=DryRat(S,LastN-2-I);
   If(Tok>=0)and(Tok<S.NVocab)Then Begin
    If MaxTokRepeat[Tok]=0 Then AddInt(UsedToks,Tok);
    If MaxTokRepeat[Tok]<RepeatLen Then MaxTokRepeat[Tok]:=RepeatLen;
   End;
  End;
 End;
 { etape 4 : penalites }
 MaxExp:=0;
 If S.P.DryBase>1.000001 Then MaxExp:=Trunc(88.7228391/Ln(S.P.DryBase));
 For I:=0 to C.N-1 do Begin
  Tok:=C.D[I].Id;
  If(Tok>=0)and(Tok<S.NVocab)and(MaxTokRepeat[Tok]>0)Then Begin
   ExpV:=MaxTokRepeat[Tok]-S.P.DryAllowed;
   If(MaxExp>0)and(ExpV>MaxExp)Then ExpV:=MaxExp;
   Pen:=S.P.DryMult*FPow(S.P.DryBase,ExpV);
   C.D[I].Logit:=C.D[I].Logit-Pen;
  End;
 End;
 C.Sorted:=False;
End;

Function DistSample(Var C:TCandSet;Var R:TMT):LongInt;
Var
 I:LongInt;
 Mx:Single;
 SumCum,Rnd,SumRun,SumTgt:Double;
 Found:Boolean;
Begin
 If C.N=0 Then Begin DistSample:=-1;Exit;End;
 If C.N=1 Then Begin
  MTUniform(R);
  C.D[0].P:=1.0;
  DistSample:=0;
  Exit;
 End;
 Mx:=C.D[0].Logit;
 If not C.Sorted Then
  For I:=1 to C.N-1 do If C.D[I].Logit>Mx Then Mx:=C.D[I].Logit;
 SumCum:=0;
 For I:=0 to C.N-1 do Begin
  C.D[I].P:=Exp(C.D[I].Logit-Mx);
  SumCum:=SumCum+C.D[I].P;
 End;
 Rnd:=MTUniform(R);
 SumRun:=0;SumTgt:=SumCum*Rnd;
 Found:=False;
 DistSample:=C.N-1;
 For I:=0 to C.N-1 do Begin
  If not Found Then Begin
   SumRun:=SumRun+C.D[I].P;
   If SumRun>=SumTgt Then Begin DistSample:=I;Found:=True;End;
  End;
  C.D[I].P:=C.D[I].P/SumCum;
 End;
End;

Function ApplyMirostat(Var C:TCandSet;Var S:TSampler):LongInt;
Var
 I,Idx,M_:LongInt;
 SHat,SumTiBi,SumTiSq,Ti,Bi,Eps,K,Surprise,E:Single;
Begin
 M_:=100;
 SoftmaxCands(C,True);
 SHat:=0;SumTiBi:=0;SumTiSq:=0;
 I:=0;
 While(I<M_-1)and(I<C.N-1)do Begin
  Ti:=Ln((I+2)/(I+1));
  Bi:=Ln(C.D[I].P/C.D[I+1].P);
  SumTiBi:=SumTiBi+Ti*Bi;
  SumTiSq:=SumTiSq+Ti*Ti;
  Inc(I);
 End;
 SHat:=SumTiBi/SumTiSq;
 Eps:=SHat-1;
 K:=FPow((Eps*FPow(2,S.Mu))/(1-FPow(S.NVocab,-Eps)),1/SHat);
 TopKImpl(C,IMax(Trunc(K),1));
 SoftmaxCands(C,True);
 Idx:=DistSample(C,S.RngMiro);
 Surprise:=-FLog2(C.D[Idx].P);
 E:=Surprise-S.P.MiroTau;
 S.Mu:=S.Mu-S.P.MiroEta*E;
 ApplyMirostat:=Idx;
End;

Function ApplyMirostatV2(Var C:TCandSet;Var S:TSampler):LongInt;
Var
 I,Idx:LongInt;
 Surprise,E:Single;
Begin
 SoftmaxCands(C,True);
 I:=0;
 While I<C.N do Begin
  If -FLog2(C.D[I].P)>S.Mu Then Break;
  Inc(I);
 End;
 C.N:=I;
 If C.N=0 Then C.N:=1;
 SoftmaxCands(C,True);
 Idx:=DistSample(C,S.RngMiro);
 Surprise:=-FLog2(C.D[Idx].P);
 E:=Surprise-S.P.MiroTau;
 S.Mu:=S.Mu-S.P.MiroEta*E;
 ApplyMirostatV2:=Idx;
End;

{ ---- initialisation des sequences de rupture DRY ---- }
Procedure DryInitBreakers(Var S:TSampler;Var V:TVocab);
Var
 I,T,P,L,M_,J,K:LongInt;
 Word_,Brk:AnsiString;
 Toks:TIntArray;
 Found:Boolean;
 Match:Boolean;
 N:LongInt;
Begin
 SetLength(S.DryBr,0);
 If(S.P.DryMult=0)or(S.P.DryBase<1.0)or(S.P.DryLastN=0)Then Exit;
 For I:=0 to High(S.P.DryBreakers)do Begin
  Brk:=S.P.DryBreakers[I];
  If Brk='' Then Continue;
  If Length(Brk)>40 Then Brk:=Copy(Brk,1,40);
  For T:=0 to V.NTokens-1 do Begin
   SetLength(Toks,1);Toks[0]:=T;
   Word_:=DetokenizeTokens(V,Toks,1,True,False);
   If Pos(Brk,Word_)>0 Then Begin
    N:=Length(S.DryBr);
    SetLength(S.DryBr,N+1);
    S.DryBr[N].Head:=T;
    SetLength(S.DryBr[N].Tail,0);
   End
    Else Begin
     L:=Length(Word_);
     P:=0;
     While True do Begin
      P:=PosFrom(Brk[1],Word_,P+1);
      If P=0 Then Break;
      { P est 1-base ; comparer Word_[P..] avec Brk }
      Match:=True;
      K:=1;
      While(K<Length(Brk))and(P+K<=L)do Begin
       If Word_[P+K]<>Brk[K+1]Then Begin Match:=False;Break;End;
       Inc(K);
      End;
      If Match Then Begin
       Toks:=VocabTokenize(V,Copy(Brk,K+1,Length(Brk)),False,False);
       If Length(Toks)>20 Then SetLength(Toks,20);
       Found:=False;
       For J:=0 to High(S.DryBr)do
        If(S.DryBr[J].Head=T)and(Length(S.DryBr[J].Tail)=Length(Toks))Then Begin
         Found:=True;
         For M_:=0 to High(Toks)do If S.DryBr[J].Tail[M_]<>Toks[M_]Then Found:=False;
         If Found Then Break;
        End;
       If not Found Then Begin
        N:=Length(S.DryBr);
        SetLength(S.DryBr,N+1);
        S.DryBr[N].Head:=T;
        S.DryBr[N].Tail:=Copy(Toks,0,Length(Toks));
       End;
      End;
     End;
    End;
  End;
 End;
End;

Procedure SamplerReset(Var S:TSampler);
Var
 I:LongInt;
Begin
 S.PrevN:=0;
 S.PenPos:=0;S.PenCount:=0;
 For I:=0 to High(S.PenCnt)do S.PenCnt[I]:=0;
 SetLength(S.DryLast,0);
 S.Mu:=2.0*S.P.MiroTau;
 If S.P.Seed=DefaultSeed Then S.SeedCur:=MakeSeed Else S.SeedCur:=S.P.Seed;
 MTSeed(S.RngDist,S.SeedCur);
 MTSeed(S.RngXtc,S.SeedCur);
 MTSeed(S.RngMiro,S.SeedCur);
 S.AdaptiveTargetCur:=S.P.AdaptiveTarget;
End;

Function SamplerInit(Var S:TSampler;Var V:TVocab;Const P:TSampParams;NVocab:LongInt):Boolean;
Var
 I:LongInt;
Begin
 S.P:=P;
 S.NVocab:=NVocab;
 If(S.P.PenaltyRepeat<=0)Then Begin
  LogErr('erreur : penalty_repeat doit être > 0'+#10);
  SamplerInit:=False;Exit;
 End;
 SetLength(S.PenCnt,NVocab);
 If S.P.PenaltyLastN<0 Then S.P.PenaltyLastN:=0;
 SetLength(S.PenRing,S.P.PenaltyLastN+1);
 SetLength(S.Cands.D,NVocab);
 SamplerReset(S);
 DryInitBreakers(S,V);
 S.HasGrammar:=False;
 If S.P.Grammar<>'' Then Begin
  If not GrammarInit(S.P.Grammar,'root',V,S.Gram)Then Begin
   LogErr('erreur : échec de l''analyse de la grammaire'+#10);
   SamplerInit:=False;Exit;
  End;
  S.HasGrammar:=True;
 End;
 SamplerInit:=True;
End;

Procedure SamplerAccept(Var S:TSampler;Var V:TVocab;Tok:LongInt;AcceptGrammar:Boolean);
Var
 Old,N:LongInt;
Begin
 If AcceptGrammar and S.HasGrammar Then GrammarAcceptToken(S.Gram,V,Tok);
 { penalites : fenetre glissante }
 If not PenaltiesDisabled(S)Then Begin
  If S.PenCount>=S.P.PenaltyLastN Then Begin
   Old:=S.PenRing[S.PenPos];
   If(Old>=0)and(Old<S.NVocab)Then Dec(S.PenCnt[Old]);
   S.PenRing[S.PenPos]:=Tok;
   S.PenPos:=(S.PenPos+1)mod S.P.PenaltyLastN;
  End
   Else Begin
    S.PenRing[(S.PenPos+S.PenCount)mod S.P.PenaltyLastN]:=Tok;
    Inc(S.PenCount);
   End;
  If(Tok>=0)and(Tok<S.NVocab)Then Inc(S.PenCnt[Tok]);
 End;
 { DRY }
 If(S.P.DryMult<>0)and(S.P.DryBase>=1.0)and(S.P.DryLastN<>0)Then Begin
  N:=Length(S.DryLast);
  If N>=S.P.DryLastN Then Begin
   Move(S.DryLast[1],S.DryLast[0],(N-1)*4);
   S.DryLast[N-1]:=Tok;
  End
   Else Begin
    SetLength(S.DryLast,N+1);
    S.DryLast[N]:=Tok;
   End;
 End;
End;

{ remplit les candidats depuis les logits }
Procedure SamplerSetCands(Var S:TSampler;Logits:PSingle);
Var
 I:LongInt;
Begin
 S.Cands.N:=S.NVocab;
 For I:=0 to S.NVocab-1 do Begin
  S.Cands.D[I].Id:=I;
  S.Cands.D[I].Logit:=Logits[I];
  S.Cands.D[I].P:=0;
 End;
 S.Cands.Sorted:=False;
 S.Cands.Selected:=-1;
End;

Procedure SamplerRunChain(Var S:TSampler);
Var
 K,I:LongInt;
 Sel:LongInt;
 Done:Boolean;
Begin
 If S.P.Mirostat=0 Then Begin
  For K:=0 to High(S.P.Order)do Begin
   If S.Cands.N=0 Then Break;
   Case S.P.Order[K]of
    SK_PENALTIES:ApplyPenalties(S.Cands,S);
    SK_DRY:ApplyDry(S.Cands,S);
    SK_TOPNSIGMA:ApplyTopNSigma(S.Cands,S.P.TopNSigma);
    SK_TOPK:TopKImpl(S.Cands,S.P.TopK);
    SK_TYPP:ApplyTypical(S.Cands,S.P.TypP,S.P.MinKeep);
    SK_TOPP:ApplyTopP(S.Cands,S.P.TopP,S.P.MinKeep);
    SK_MINP:ApplyMinP(S.Cands,S.P.MinP,S.P.MinKeep);
    SK_XTC:ApplyXtc(S.Cands,S);
    SK_TEMP:ApplyTempExt(S.Cands,S.P.Temp,S.P.DynRange,S.P.DynExp);
   End;
  End;
  S.Cands.Selected:=DistSample(S.Cands,S.RngDist);
 End
  Else Begin
   TempImpl(S.Cands,S.P.Temp);
   If S.P.Mirostat=1 Then S.Cands.Selected:=ApplyMirostat(S.Cands,S)
                     Else S.Cands.Selected:=ApplyMirostatV2(S.Cands,S);
  End;
End;

{ Echantillonne un jeton a partir des logits ; renvoie -1 si impossible }
Function SamplerSample(Var S:TSampler;Var V:TVocab;Logits:PSingle):LongInt;
Var
 I:LongInt;
 Id:LongInt;
 One:TCandSet;
 Valid:Boolean;
Begin
 For I:=0 to High(S.P.Bias)do
  If(S.P.Bias[I].Tok>=0)and(S.P.Bias[I].Tok<S.NVocab)Then
   Logits[S.P.Bias[I].Tok]:=Logits[S.P.Bias[I].Tok]+S.P.Bias[I].Bias;
 SamplerSetCands(S,Logits);
 SamplerRunChain(S);
 If S.Cands.Selected<0 Then Begin SamplerSample:=-1;Exit;End;
 Id:=S.Cands.D[S.Cands.Selected].Id;
 If not S.HasGrammar Then Begin SamplerSample:=Id;Exit;End;
 { verifie que le jeton respecte la grammaire }
 SetLength(One.D,1);
 One.N:=1;One.Sorted:=False;One.Selected:=0;
 One.D[0].Id:=Id;One.D[0].Logit:=1.0;One.D[0].P:=1.0;
 GrammarApply(S.Gram,V,One);
 Valid:=One.D[0].Logit>NegInf/2;
 If Valid Then Begin SamplerSample:=Id;Exit;End;
 { rejet : on recommence avec la grammaire en premier }
 SamplerSetCands(S,Logits);
 GrammarApply(S.Gram,V,S.Cands);
 Valid:=False;
 For I:=0 to S.Cands.N-1 do If S.Cands.D[I].Logit>NegInf/2 Then Begin Valid:=True;Break;End;
 If not Valid Then Begin SamplerSample:=-1;Exit;End;
 SamplerRunChain(S);
 If S.Cands.Selected<0 Then Begin SamplerSample:=-1;Exit;End;
 SamplerSample:=S.Cands.D[S.Cands.Selected].Id;
End;

{ ------------------------------------------------------------------ }
{ Modeles de conversation (equivalent de llama-chat.cpp)              }
{ ------------------------------------------------------------------ }

Type
 TChatMsg=Record
  Role,Content:AnsiString;
 End;
 TChatMsgs=Array of TChatMsg;

Const
 NBuiltinTpl=49;
 BuiltinTplNames:Array[0..NBuiltinTpl-1]of AnsiString=(
  'bailing','bailing-think','bailing2','chatglm3','chatglm4','chatml','command-r','deepseek','deepseek-ocr',
  'deepseek2','deepseek3','exaone-moe','exaone3','exaone4','falcon3','gemma','gigachat','glmedge','gpt-oss',
  'granite','granite-4.0','granite-4.1','grok-2','hunyuan-dense','hunyuan-moe','hunyuan-vl','kimi-k2','llama2',
  'llama2-sys','llama2-sys-bos','llama2-sys-strip','llama3','llama4','megrez','minicpm','mistral-v1','mistral-v3',
  'mistral-v3-tekken','mistral-v7','mistral-v7-tekken','monarch','openchat','orion','pangu-embedded','phi3','phi4',
  'rwkv-world','seed_oss','smolvlm');

Function IsBuiltinTemplate(Const N:AnsiString):Boolean;
Var
 I:LongInt;
Begin
 IsBuiltinTemplate:=False;
 For I:=0 to NBuiltinTpl-1 do If BuiltinTplNames[I]=N Then IsBuiltinTemplate:=True;
 If(N='vicuna')or(N='vicuna-orca')or(N='zephyr')or(N='yandex')or(N='solar-open')Then IsBuiltinTemplate:=True;
End;

Function ChatTemplateList:AnsiString;
Var
 L:TStrArray;
 I,J:LongInt;
 T:AnsiString;
Begin
 SetLength(L,0);
 For I:=0 to NBuiltinTpl-1 do AddStr(L,BuiltinTplNames[I]);
 AddStr(L,'solar-open');AddStr(L,'vicuna');AddStr(L,'vicuna-orca');AddStr(L,'yandex');AddStr(L,'zephyr');
 For I:=1 to High(L)do Begin
  T:=L[I];J:=I-1;
  While(J>=0)and(L[J]>T)do Begin L[J+1]:=L[J];Dec(J);End;
  L[J+1]:=T;
 End;
 ChatTemplateList:=JoinStrs(L,', ');
End;

Function ChatTemplateDetect(Const T:AnsiString):AnsiString;
 Function C(Const S:AnsiString):Boolean;
 Begin
  C:=Pos(S,T)>0;
 End;
Begin
 If IsBuiltinTemplate(T)Then Begin ChatTemplateDetect:=T;Exit;End;
 ChatTemplateDetect:='';
 If C('<|im_start|>')Then Begin
  If C('<|im_sep|>')Then ChatTemplateDetect:='phi4'
  Else If C('<end_of_utterance>')Then ChatTemplateDetect:='smolvlm'
  Else ChatTemplateDetect:='chatml';
 End
 Else If(Copy(T,1,7)='mistral')or C('[INST]')Then Begin
  If C('[SYSTEM_PROMPT]')Then ChatTemplateDetect:='mistral-v7'
  Else If C(''' [INST] '' + system_message')or C('[AVAILABLE_TOOLS]')Then Begin
   If C(' [INST]')Then ChatTemplateDetect:='mistral-v1'
   Else If C('"[INST]"')Then ChatTemplateDetect:='mistral-v3-tekken'
   Else ChatTemplateDetect:='mistral-v3';
  End
  Else Begin
   If C('content.strip()')Then ChatTemplateDetect:='llama2-sys-strip'
   Else If C('bos_token + ''[INST]')Then ChatTemplateDetect:='llama2-sys-bos'
   Else If C('<<SYS>>')Then ChatTemplateDetect:='llama2-sys'
   Else ChatTemplateDetect:='llama2';
  End;
 End
 Else If C('<|assistant|>')and C('<|end|>')Then ChatTemplateDetect:='phi3'
 Else If C('[gMASK]<sop>')Then ChatTemplateDetect:='chatglm4'
 Else If C('<|assistant|>')and C('<|user|>')Then Begin
  If C('<|tool_declare|>')Then ChatTemplateDetect:='exaone-moe'
  Else If C('</s>')Then ChatTemplateDetect:='falcon3'
  Else ChatTemplateDetect:='glmedge';
 End
 Else If C('<|{{ item[''role''] }}|>')and C('<|begin_of_image|>')Then ChatTemplateDetect:='glmedge'
 Else If C('<|user|>')and C('<|endoftext|>')Then ChatTemplateDetect:='zephyr'
 Else If C('bos_token + message[''role'']')Then ChatTemplateDetect:='monarch'
 Else If C('<start_of_turn>')Then ChatTemplateDetect:='gemma'
 Else If C('''\n\nAssistant: '' + eos_token')Then ChatTemplateDetect:='orion'
 Else If C('GPT4 Correct ')Then ChatTemplateDetect:='openchat'
 Else If C('USER: ')and C('ASSISTANT: ')Then Begin
  If C('SYSTEM: ')Then ChatTemplateDetect:='vicuna-orca' Else ChatTemplateDetect:='vicuna';
 End
 Else If C('### Instruction:')and C('<|EOT|>')Then ChatTemplateDetect:='deepseek'
 Else If C('<|START_OF_TURN_TOKEN|>')and C('<|USER_TOKEN|>')Then ChatTemplateDetect:='command-r'
 Else If C('<|start_header_id|>')and C('<|end_header_id|>')Then ChatTemplateDetect:='llama3'
 Else If C('[gMASK]sop')Then ChatTemplateDetect:='chatglm3'
 Else If C('<用户>')Then ChatTemplateDetect:='minicpm'
 Else If C('''Assistant: '' + message[''content''] + eos_token')Then ChatTemplateDetect:='deepseek2'
 Else If C('<｜Assistant｜>')and C('<｜User｜>')and C('<｜end▁of▁sentence｜>')Then ChatTemplateDetect:='deepseek3'
 Else If C('[|system|]')and C('[|assistant|]')and C('[|endofturn|]')Then Begin
  If C('[|tool|]')Then ChatTemplateDetect:='exaone4' Else ChatTemplateDetect:='exaone3';
 End
 Else If C('rwkv-world')or C('{{- ''User: '' + message[''content'']|trim + ''\n\n'' -}}')Then ChatTemplateDetect:='rwkv-world'
 Else If C('<|start_of_role|>')Then Begin
  If C('<tool_call>')or C('<tools>')Then Begin
   If C('g4_default_system_message')Then ChatTemplateDetect:='granite-4.0' Else ChatTemplateDetect:='granite-4.1';
  End
   Else ChatTemplateDetect:='granite';
 End
 Else If C('message[''role''] + additional_special_tokens[0] + message[''content''] + additional_special_tokens[1]')Then
  ChatTemplateDetect:='gigachat'
 Else If C('<|role_start|>')Then ChatTemplateDetect:='megrez'
 Else If C(' Ассистент:')Then ChatTemplateDetect:='yandex'
 Else If C('<role>ASSISTANT</role>')and C('''HUMAN''')Then ChatTemplateDetect:='bailing'
 Else If C('<role>ASSISTANT</role>')and C('"HUMAN"')and C('<think>')Then ChatTemplateDetect:='bailing-think'
 Else If C('<role>ASSISTANT</role>')and C('<role>HUMAN</role>')and C('<|role_end|>')Then ChatTemplateDetect:='bailing2'
 Else If C('<|header_start|>')and C('<|header_end|>')Then ChatTemplateDetect:='llama4'
 Else If C('<|endofuserprompt|>')Then ChatTemplateDetect:='dots1'
 Else If C('<|extra_0|>')and C('<|extra_4|>')Then ChatTemplateDetect:='hunyuan-moe'
 Else If C('<|start|>')and C('<|channel|>')Then ChatTemplateDetect:='gpt-oss'
 Else If C('<｜hy_Assistant｜>')and C('<｜hy_begin▁of▁sentence｜>')Then ChatTemplateDetect:='hunyuan-vl'
 Else If C('<｜hy_Assistant｜>')and C('<｜hy_place▁holder▁no▁3｜>')Then ChatTemplateDetect:='hunyuan-dense'
 Else If C('<|im_assistant|>assistant<|im_middle|>')Then ChatTemplateDetect:='kimi-k2'
 Else If C('<seed:bos>')Then ChatTemplateDetect:='seed_oss'
 Else If C('''Assistant: ''  + message[''content''] + ''<|separator|>')Then ChatTemplateDetect:='grok-2'
 Else If C('[unused9]系统：[unused10]')Then ChatTemplateDetect:='pangu-embedded'
 Else If C('<|begin|>')and C('<|end|>')and C('<|content|>')Then ChatTemplateDetect:='solar-open';
End;

Function UpFirst(Const S:AnsiString):AnsiString;
Begin
 If S='' Then UpFirst:=S Else UpFirst:=UpStr(Copy(S,1,1))+Copy(S,2,Length(S));
End;

Function ChatTemplateApply(Const Tpl:AnsiString;Const Chat:TChatMsgs;AddAss:Boolean;Var Dest:AnsiString):Boolean;
Var
 SS:AnsiString;
 I:LongInt;
 Role,Content,SysPrompt,Lead,Trail:AnsiString;
 Inside:Boolean;
 SupportSys,BosInside,StripMsg,TrimAsst:Boolean;
 HasSys:Boolean;
Begin
 SS:='';
 ChatTemplateApply:=True;
 If Tpl='chatml' Then Begin
  For I:=0 to High(Chat)do SS:=SS+'<|im_start|>'+Chat[I].Role+#10+Chat[I].Content+'<|im_end|>'#10;
  If AddAss Then SS:=SS+'<|im_start|>assistant'#10;
 End
 Else If(Tpl='mistral-v7')or(Tpl='mistral-v7-tekken')Then Begin
  If Tpl='mistral-v7' Then Trail:=' ' Else Trail:='';
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;Content:=Chat[I].Content;
   If Role='system' Then SS:=SS+'[SYSTEM_PROMPT]'+Trail+Content+'[/SYSTEM_PROMPT]'
   Else If Role='user' Then SS:=SS+'[INST]'+Trail+Content+'[/INST]'
   Else SS:=SS+Trail+Content+'</s>';
  End;
 End
 Else If(Tpl='mistral-v1')or(Tpl='mistral-v3')or(Tpl='mistral-v3-tekken')Then Begin
  If Tpl='mistral-v1' Then Lead:=' ' Else Lead:='';
  If Tpl='mistral-v3-tekken' Then Trail:='' Else Trail:=' ';
  TrimAsst:=Tpl='mistral-v3';
  Inside:=False;
  For I:=0 to High(Chat)do Begin
   If not Inside Then Begin SS:=SS+Lead+'[INST]'+Trail;Inside:=True;End;
   Role:=Chat[I].Role;Content:=Chat[I].Content;
   If Role='system' Then SS:=SS+Content+#10#10
   Else If Role='user' Then SS:=SS+Content+Lead+'[/INST]'
   Else Begin
    If TrimAsst Then SS:=SS+Trail+TrimS(Content)+'</s>' Else SS:=SS+Trail+Content+'</s>';
    Inside:=False;
   End;
  End;
 End
 Else If(Tpl='llama2')or(Tpl='llama2-sys')or(Tpl='llama2-sys-bos')or(Tpl='llama2-sys-strip')Then Begin
  SupportSys:=Tpl<>'llama2';
  BosInside:=Tpl='llama2-sys-bos';
  StripMsg:=Tpl='llama2-sys-strip';
  Inside:=True;
  SS:='[INST] ';
  For I:=0 to High(Chat)do Begin
   If StripMsg Then Content:=TrimS(Chat[I].Content)Else Content:=Chat[I].Content;
   Role:=Chat[I].Role;
   If not Inside Then Begin
    Inside:=True;
    If BosInside Then SS:=SS+'<s>[INST] ' Else SS:=SS+'[INST] ';
   End;
   If Role='system' Then Begin
    If SupportSys Then SS:=SS+'<<SYS>>'#10+Content+#10'<</SYS>>'#10#10
                  Else SS:=SS+Content+#10;
   End
   Else If Role='user' Then SS:=SS+Content+' [/INST]'
   Else Begin SS:=SS+Content+'</s>';Inside:=False;End;
  End;
 End
 Else If Tpl='phi3' Then Begin
  For I:=0 to High(Chat)do SS:=SS+'<|'+Chat[I].Role+'|>'#10+Chat[I].Content+'<|end|>'#10;
  If AddAss Then SS:=SS+'<|assistant|>'#10;
 End
 Else If Tpl='phi4' Then Begin
  For I:=0 to High(Chat)do SS:=SS+'<|im_start|>'+Chat[I].Role+'<|im_sep|>'+Chat[I].Content+'<|im_end|>';
  If AddAss Then SS:=SS+'<|im_start|>assistant<|im_sep|>';
 End
 Else If Tpl='falcon3' Then Begin
  For I:=0 to High(Chat)do SS:=SS+'<|'+Chat[I].Role+'|>'#10+Chat[I].Content+#10;
  If AddAss Then SS:=SS+'<|assistant|>'#10;
 End
 Else If Tpl='zephyr' Then Begin
  For I:=0 to High(Chat)do SS:=SS+'<|'+Chat[I].Role+'|>'#10+Chat[I].Content+'<|endoftext|>'#10;
  If AddAss Then SS:=SS+'<|assistant|>'#10;
 End
 Else If Tpl='monarch' Then Begin
  For I:=0 to High(Chat)do Begin
   If I=0 Then Lead:='' Else Lead:='<s>';
   SS:=SS+Lead+Chat[I].Role+#10+Chat[I].Content+'</s>'#10;
  End;
  If AddAss Then SS:=SS+'<s>assistant'#10;
 End
 Else If Tpl='gemma' Then Begin
  SysPrompt:='';
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='system' Then Begin SysPrompt:=SysPrompt+TrimS(Chat[I].Content);Continue;End;
   If Role='assistant' Then Role:='model';
   SS:=SS+'<start_of_turn>'+Role+#10;
   If(SysPrompt<>'')and(Role<>'model')Then Begin SS:=SS+SysPrompt+#10#10;SysPrompt:='';End;
   SS:=SS+TrimS(Chat[I].Content)+'<end_of_turn>'#10;
  End;
  If AddAss Then SS:=SS+'<start_of_turn>model'#10;
 End
 Else If Tpl='orion' Then Begin
  SysPrompt:='';
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='system' Then Begin SysPrompt:=SysPrompt+Chat[I].Content;Continue;End
   Else If Role='user' Then Begin
    SS:=SS+'Human: ';
    If SysPrompt<>'' Then Begin SS:=SS+SysPrompt+#10#10;SysPrompt:='';End;
    SS:=SS+Chat[I].Content+#10#10'Assistant: </s>';
   End
   Else SS:=SS+Chat[I].Content+'</s>';
  End;
 End
 Else If Tpl='openchat' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='system' Then SS:=SS+Chat[I].Content+'<|end_of_turn|>'
   Else SS:=SS+'GPT4 Correct '+UpFirst(Role)+': '+Chat[I].Content+'<|end_of_turn|>';
  End;
  If AddAss Then SS:=SS+'GPT4 Correct Assistant:';
 End
 Else If(Tpl='vicuna')or(Tpl='vicuna-orca')Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='system' Then Begin
    If Tpl='vicuna-orca' Then SS:=SS+'SYSTEM: '+Chat[I].Content+#10
                         Else SS:=SS+Chat[I].Content+#10#10;
   End
   Else If Role='user' Then SS:=SS+'USER: '+Chat[I].Content+#10
   Else If Role='assistant' Then SS:=SS+'ASSISTANT: '+Chat[I].Content+'</s>'#10;
  End;
  If AddAss Then SS:=SS+'ASSISTANT:';
 End
 Else If Tpl='deepseek' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='system' Then SS:=SS+Chat[I].Content
   Else If Role='user' Then SS:=SS+'### Instruction:'#10+Chat[I].Content+#10
   Else If Role='assistant' Then SS:=SS+'### Response:'#10+Chat[I].Content+#10'<|EOT|>'#10;
  End;
  If AddAss Then SS:=SS+'### Response:'#10;
 End
 Else If Tpl='command-r' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='system' Then SS:=SS+'<|START_OF_TURN_TOKEN|><|SYSTEM_TOKEN|>'+TrimS(Chat[I].Content)+'<|END_OF_TURN_TOKEN|>'
   Else If Role='user' Then SS:=SS+'<|START_OF_TURN_TOKEN|><|USER_TOKEN|>'+TrimS(Chat[I].Content)+'<|END_OF_TURN_TOKEN|>'
   Else If Role='assistant' Then SS:=SS+'<|START_OF_TURN_TOKEN|><|CHATBOT_TOKEN|>'+TrimS(Chat[I].Content)+'<|END_OF_TURN_TOKEN|>';
  End;
  If AddAss Then SS:=SS+'<|START_OF_TURN_TOKEN|><|CHATBOT_TOKEN|>';
 End
 Else If Tpl='llama3' Then Begin
  For I:=0 to High(Chat)do
   SS:=SS+'<|start_header_id|>'+Chat[I].Role+'<|end_header_id|>'#10#10+TrimS(Chat[I].Content)+'<|eot_id|>';
  If AddAss Then SS:=SS+'<|start_header_id|>assistant<|end_header_id|>'#10#10;
 End
 Else If Tpl='chatglm3' Then Begin
  SS:='[gMASK]sop';
  For I:=0 to High(Chat)do SS:=SS+'<|'+Chat[I].Role+'|>'#10' '+Chat[I].Content;
  If AddAss Then SS:=SS+'<|assistant|>';
 End
 Else If Tpl='chatglm4' Then Begin
  SS:='[gMASK]<sop>';
  For I:=0 to High(Chat)do SS:=SS+'<|'+Chat[I].Role+'|>'#10+Chat[I].Content;
  If AddAss Then SS:=SS+'<|assistant|>'#10;
 End
 Else If Tpl='glmedge' Then Begin
  For I:=0 to High(Chat)do SS:=SS+'<|'+Chat[I].Role+'|>'#10+Chat[I].Content;
  If AddAss Then SS:=SS+'<|assistant|>';
 End
 Else If Tpl='minicpm' Then Begin
  For I:=0 to High(Chat)do Begin
   If Chat[I].Role='user' Then SS:=SS+'<用户>'+TrimS(Chat[I].Content)+'<AI>'
   Else SS:=SS+TrimS(Chat[I].Content);
  End;
 End
 Else If Tpl='deepseek2' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='system' Then SS:=SS+Chat[I].Content+#10#10
   Else If Role='user' Then SS:=SS+'User: '+Chat[I].Content+#10#10
   Else If Role='assistant' Then SS:=SS+'Assistant: '+Chat[I].Content+'<｜end▁of▁sentence｜>';
  End;
  If AddAss Then SS:=SS+'Assistant:';
 End
 Else If Tpl='deepseek3' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='system' Then SS:=SS+Chat[I].Content+#10#10
   Else If Role='user' Then SS:=SS+'<｜User｜>'+Chat[I].Content
   Else If Role='assistant' Then SS:=SS+'<｜Assistant｜>'+Chat[I].Content+'<｜end▁of▁sentence｜>';
  End;
  If AddAss Then SS:=SS+'<｜Assistant｜>';
 End
 Else If Tpl='deepseek-ocr' Then Begin
  For I:=0 to High(Chat)do SS:=SS+Chat[I].Content;
 End
 Else If(Tpl='exaone3')or(Tpl='exaone4')Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='system' Then SS:=SS+'[|system|]'+TrimS(Chat[I].Content)+'[|endofturn|]'#10
   Else If Role='user' Then SS:=SS+'[|user|]'+TrimS(Chat[I].Content)+#10
   Else If Role='assistant' Then SS:=SS+'[|assistant|]'+TrimS(Chat[I].Content)+'[|endofturn|]'#10
   Else If(Role='tool')and(Tpl='exaone4')Then SS:=SS+'[|tool|]'+TrimS(Chat[I].Content)+'[|endofturn|]'#10;
  End;
  If AddAss Then SS:=SS+'[|assistant|]';
 End
 Else If Tpl='exaone-moe' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If(Role='system')or(Role='user')or(Role='assistant')or(Role='tool')Then
    SS:=SS+'<|'+Role+'|>'#10+TrimS(Chat[I].Content)+'<|endofturn|>'#10;
  End;
  If AddAss Then SS:=SS+'<|assistant|>'#10;
 End
 Else If Tpl='rwkv-world' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='system' Then SS:=SS+'System: '+TrimS(Chat[I].Content)+#10#10
   Else If Role='user' Then Begin
    SS:=SS+'User: '+TrimS(Chat[I].Content)+#10#10;
    If I=High(Chat)Then SS:=SS+'Assistant:';
   End
   Else If Role='assistant' Then SS:=SS+'Assistant: '+TrimS(Chat[I].Content)+#10#10;
  End;
 End
 Else If(Tpl='granite')or(Tpl='granite-4.0')or(Tpl='granite-4.1')Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Tpl='granite' Then Begin
    SS:=SS+'<|start_of_role|>'+Role+'<|end_of_role|>';
    If Role='assistant_tool_call' Then SS:=SS+'<|tool_call|>';
   End
    Else Begin
     If Role='assistant_tool_call' Then SS:=SS+'<|start_of_role|>assistant<|end_of_role|><|tool_call|>'
     Else SS:=SS+'<|start_of_role|>'+Role+'<|end_of_role|>';
    End;
   SS:=SS+Chat[I].Content+'<|end_of_text|>'#10;
  End;
  If AddAss Then SS:=SS+'<|start_of_role|>assistant<|end_of_role|>';
 End
 Else If Tpl='gigachat' Then Begin
  HasSys:=(Length(Chat)>0)and(Chat[0].Role='system');
  If HasSys Then SS:='<s>'+Chat[0].Content+'<|message_sep|>' Else SS:='<s>';
  For I:=Ord(HasSys)to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='user' Then SS:=SS+'user<|role_sep|>'+Chat[I].Content+'<|message_sep|>available functions<|role_sep|>[]<|message_sep|>'
   Else If Role='assistant' Then SS:=SS+'assistant<|role_sep|>'+Chat[I].Content+'<|message_sep|>';
  End;
  If AddAss Then SS:=SS+'assistant<|role_sep|>';
 End
 Else If Tpl='megrez' Then Begin
  For I:=0 to High(Chat)do SS:=SS+'<|role_start|>'+Chat[I].Role+'<|role_end|>'+Chat[I].Content+'<|turn_end|>';
  If AddAss Then SS:=SS+'<|role_start|>assistant<|role_end|>';
 End
 Else If Tpl='yandex' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='user' Then SS:=SS+' Пользователь: '+Chat[I].Content+#10#10
   Else If Role='assistant' Then SS:=SS+' Ассистент: '+Chat[I].Content+#10#10;
  End;
  If AddAss Then SS:=SS+' Ассистент:[SEP]';
 End
 Else If(Tpl='bailing')or(Tpl='bailing-think')Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='user' Then Role:='HUMAN' Else Role:=UpStr(Role);
   SS:=SS+'<role>'+Role+'</role>'+Chat[I].Content;
  End;
  If AddAss Then Begin
   SS:=SS+'<role>ASSISTANT</role>';
   If Tpl='bailing-think' Then SS:=SS+'<think>';
  End;
 End
 Else If Tpl='bailing2' Then Begin
  HasSys:=(Length(Chat)>0)and(Chat[0].Role='system');
  If not HasSys Then SS:='<role>SYSTEM</role>detailed thinking off<|role_end|>';
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='user' Then Role:='HUMAN' Else Role:=UpStr(Role);
   SS:=SS+'<role>'+Role+'</role>'+Chat[I].Content+'<|role_end|>';
  End;
  If AddAss Then SS:=SS+'<role>ASSISTANT</role>';
 End
 Else If Tpl='llama4' Then Begin
  For I:=0 to High(Chat)do
   SS:=SS+'<|header_start|>'+Chat[I].Role+'<|header_end|>'#10#10+TrimS(Chat[I].Content)+'<|eot|>';
  If AddAss Then SS:=SS+'<|header_start|>assistant<|header_end|>'#10#10;
 End
 Else If Tpl='smolvlm' Then Begin
  SS:='<|im_start|>';
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='system' Then SS:=SS+Chat[I].Content+#10#10
   Else If Role='user' Then SS:=SS+'User: '+Chat[I].Content+'<end_of_utterance>'#10
   Else SS:=SS+'Assistant: '+Chat[I].Content+'<end_of_utterance>'#10;
  End;
  If AddAss Then SS:=SS+'Assistant:';
 End
 Else If Tpl='dots1' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='system' Then SS:=SS+'<|system|>'+Chat[I].Content+'<|endofsystem|>'
   Else If Role='user' Then SS:=SS+'<|userprompt|>'+Chat[I].Content+'<|endofuserprompt|>'
   Else SS:=SS+'<|response|>'+Chat[I].Content+'<|endofresponse|>';
  End;
  If AddAss Then SS:=SS+'<|response|>';
 End
 Else If Tpl='hunyuan-moe' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='system' Then SS:=SS+'<|startoftext|>'+Chat[I].Content+'<|extra_4|>'
   Else If Role='assistant' Then SS:=SS+Chat[I].Content+'<|eos|>'
   Else SS:=SS+'<|startoftext|>'+Chat[I].Content+'<|extra_0|>';
  End;
 End
 Else If Tpl='gpt-oss' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   SS:=SS+'<|start|>'+Role+'<|message|>'+Chat[I].Content;
   If Role='assistant' Then SS:=SS+'<|return|>' Else SS:=SS+'<|end|>';
  End;
  If AddAss Then SS:=SS+'<|start|>assistant';
 End
 Else If Tpl='hunyuan-dense' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If(I=0)and(Role='system')Then SS:=SS+Chat[I].Content+'<｜hy_place▁holder▁no▁3｜>';
   If Role='assistant' Then SS:=SS+'<｜hy_Assistant｜>'+Chat[I].Content+'<｜hy_place▁holder▁no▁2｜>'
   Else If Role='user' Then SS:=SS+'<｜hy_User｜>'+Chat[I].Content+'<｜hy_Assistant｜>';
  End;
 End
 Else If Tpl='hunyuan-vl' Then Begin
  SS:='<｜hy_begin▁of▁sentence｜>';
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If(I=0)and(Role='system')Then Begin SS:=SS+Chat[I].Content+'<｜hy_place▁holder▁no▁3｜>';Continue;End;
   If Role='user' Then SS:=SS+Chat[I].Content+'<｜hy_User｜>'
   Else If Role='assistant' Then SS:=SS+Chat[I].Content+'<｜hy_Assistant｜>';
  End;
 End
 Else If Tpl='kimi-k2' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='system' Then SS:=SS+'<|im_system|>system<|im_middle|>'
   Else If Role='user' Then SS:=SS+'<|im_user|>user<|im_middle|>'
   Else If Role='assistant' Then SS:=SS+'<|im_assistant|>assistant<|im_middle|>'
   Else If Role='tool' Then SS:=SS+'<|im_system|>tool<|im_middle|>';
   SS:=SS+Chat[I].Content+'<|im_end|>';
  End;
  If AddAss Then SS:=SS+'<|im_assistant|>assistant<|im_middle|>';
 End
 Else If Tpl='seed_oss' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='assistant' Then SS:=SS+'<seed:bos>'+Role+#10+TrimS(Chat[I].Content)+'<seed:eos>'
   Else SS:=SS+'<seed:bos>'+Role+#10+Chat[I].Content+'<seed:eos>';
  End;
  If AddAss Then SS:=SS+'<seed:bos>assistant'#10;
 End
 Else If Tpl='grok-2' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;
   If Role='system' Then SS:=SS+'System: '+TrimS(Chat[I].Content)+'<|separator|>'#10#10
   Else If Role='user' Then SS:=SS+'Human: '+TrimS(Chat[I].Content)+'<|separator|>'#10#10
   Else If Role='assistant' Then SS:=SS+'Assistant: '+Chat[I].Content+'<|separator|>'#10#10;
  End;
  If AddAss Then SS:=SS+'Assistant:';
 End
 Else If Tpl='pangu-embedded' Then Begin
  For I:=0 to High(Chat)do Begin
   Role:=Chat[I].Role;Content:=Chat[I].Content;
   If(I=0)and(Role<>'system')Then SS:=SS+'[unused9]系统：[unused10]';
   If Role='system' Then SS:=SS+'[unused9]系统：'+Content+'[unused10]'
   Else If Role='user' Then SS:=SS+'[unused9]用户：'+Content+'[unused10]'
   Else If Role='assistant' Then SS:=SS+'[unused9]助手：'+Content+'[unused10]'
   Else If Role='tool' Then SS:=SS+'[unused9]工具：'+Content+'[unused10]'
   Else If Role='function' Then SS:=SS+'[unused9]方法：'+Content+'[unused10]';
  End;
  If AddAss Then SS:=SS+'[unused9]助手：';
 End
 Else If Tpl='solar-open' Then Begin
  For I:=0 to High(Chat)do SS:=SS+'<|begin|>'+Chat[I].Role+'<|content|>'+Chat[I].Content+'<|end|>';
  If AddAss Then SS:=SS+'<|begin|>assistant';
 End
 Else ChatTemplateApply:=False;
 Dest:=SS;
End;

{ ------------------------------------------------------------------ }
{ Couche systeme : terminal, repertoires, reseau (Windows seulement)  }
{ ------------------------------------------------------------------ }

{$IFDEF WINDOWS}
Function GetStdHandle(nStdHandle:LongWord):PtrUInt;stdcall;external 'kernel32.dll' name 'GetStdHandle';
Function GetConsoleMode(hConsole:PtrUInt;Var Mode:LongWord):LongInt;stdcall;external 'kernel32.dll' name 'GetConsoleMode';
Function SetConsoleMode(hConsole:PtrUInt;Mode:LongWord):LongInt;stdcall;external 'kernel32.dll' name 'SetConsoleMode';
Function SetConsoleOutputCP(CP:LongWord):LongInt;stdcall;external 'kernel32.dll' name 'SetConsoleOutputCP';
Function SetConsoleCP(CP:LongWord):LongInt;stdcall;external 'kernel32.dll' name 'SetConsoleCP';
Function GetFileType(hFile:PtrUInt):LongWord;stdcall;external 'kernel32.dll' name 'GetFileType';

Function InternetOpenA(Agent:PChar;AccessType:LongWord;Proxy,Bypass:PChar;Flags:LongWord):Pointer;
 stdcall;external 'wininet.dll' name 'InternetOpenA';
Function InternetOpenUrlA(H:Pointer;Url,Headers:PChar;HeadersLen:LongWord;Flags:LongWord;Ctx:PtrUInt):Pointer;
 stdcall;external 'wininet.dll' name 'InternetOpenUrlA';
Function InternetReadFile(H:Pointer;Buf:Pointer;ToRead:LongWord;Var Got:LongWord):LongInt;
 stdcall;external 'wininet.dll' name 'InternetReadFile';
Function InternetCloseHandle(H:Pointer):LongInt;stdcall;external 'wininet.dll' name 'InternetCloseHandle';
Function HttpQueryInfoA(H:Pointer;InfoLevel:LongWord;Buf:Pointer;Var BufLen:LongWord;Index:Pointer):LongInt;
 stdcall;external 'wininet.dll' name 'HttpQueryInfoA';
Function InternetSetOptionA(H:Pointer;Opt:LongWord;Buf:Pointer;BufLen:LongWord):LongInt;
 stdcall;external 'wininet.dll' name 'InternetSetOptionA';
{$ELSE}
 {$IFDEF UNIX}
Function c_isatty(Fd:LongInt):LongInt;cdecl;external 'c' name 'isatty';
 {$ENDIF}
{$ENDIF}

Function StdoutIsTerminal:Boolean;
{$IFDEF WINDOWS}
Begin
 StdoutIsTerminal:=GetFileType(GetStdHandle(LongWord(-11)))=2;
End;
{$ELSE}
 {$IFDEF UNIX}
Begin
 StdoutIsTerminal:=c_isatty(1)<>0;
End;
 {$ELSE}
Begin
 StdoutIsTerminal:=True;
End;
 {$ENDIF}
{$ENDIF}

Function StdinIsTerminal:Boolean;
{$IFDEF WINDOWS}
Begin
 StdinIsTerminal:=GetFileType(GetStdHandle(LongWord(-10)))=2;
End;
{$ELSE}
 {$IFDEF UNIX}
Begin
 StdinIsTerminal:=c_isatty(0)<>0;
End;
 {$ELSE}
Begin
 StdinIsTerminal:=True;
End;
 {$ENDIF}
{$ENDIF}

Procedure InitConsole;
{$IFDEF WINDOWS}
Var
 H:PtrUInt;
 Mode:LongWord;
Begin
 SetConsoleOutputCP(65001);
 SetConsoleCP(65001);
 H:=GetStdHandle(LongWord(-11));
 If GetConsoleMode(H,Mode)<>0 Then SetConsoleMode(H,Mode or 4);
End;
{$ELSE}
Begin
End;
{$ENDIF}

Function HomeDir:AnsiString;
Begin
 Result:=GetEnv('HOME');
 If Result='' Then Result:=GetEnv('USERPROFILE');
End;

Function CacheDir:AnsiString;
Var
 D:AnsiString;
Begin
 D:=GetEnv('LLAMA_CACHE');
 If D='' Then Begin
  {$IFDEF WINDOWS}
  D:=GetEnv('LOCALAPPDATA');
  If D='' Then D:='.';
  D:=D+'\llama.cpp';
  {$ELSE}
  D:=GetEnv('XDG_CACHE_HOME');
  If D='' Then Begin
   D:=HomeDir;
   If D='' Then D:='.';
   D:=D+'/.cache';
  End;
  D:=D+'/llama.cpp';
  {$ENDIF}
 End;
 While(Length(D)>1)and(D[Length(D)]in['/','\'])do Delete(D,Length(D),1);
 CacheDir:=D;
End;

Function NetSupported:Boolean;
Begin
 {$IFDEF WINDOWS}
 NetSupported:=True;
 {$ELSE}
 NetSupported:=False;
 {$ENDIF}
End;

{$IFDEF WINDOWS}
Function HttpOpen(Const Url,Token:AnsiString;From:Int64;Var Status:LongInt;Var ContentLen:Int64;Var Sess:Pointer):Pointer;
Var
 Hdr:AnsiString;
 Flags:LongWord;
 H:Pointer;
 Buf:LongWord;
 L,Tmo:LongWord;
 SBuf:Array[0..63]of AnsiChar;
 Code:LongInt;
Begin
 HttpOpen:=Nil;
 Status:=0;ContentLen:=-1;
 Sess:=InternetOpenA('llama-cpp',0,Nil,Nil,0);
 If Sess=Nil Then Exit;
 Tmo:=30000;
 InternetSetOptionA(Sess,2,@Tmo,4);
 InternetSetOptionA(Sess,6,@Tmo,4);
 Flags:=$80000000 or $04000000;
 If Copy(LoStr(Url),1,8)='https://' Then Flags:=Flags or $00800000;
 Hdr:='Accept: */*'#13#10;
 If Token<>'' Then Hdr:=Hdr+'Authorization: Bearer '+Token+#13#10;
 If From>0 Then Hdr:=Hdr+'Range: bytes='+IStr(From)+'-'#13#10;
 H:=InternetOpenUrlA(Sess,PChar(Url),PChar(Hdr),LongWord(Length(Hdr)),Flags,0);
 If H=Nil Then Begin InternetCloseHandle(Sess);Sess:=Nil;Exit;End;
 L:=4;Buf:=0;
 If HttpQueryInfoA(H,19 or $20000000,@Buf,L,Nil)<>0 Then Status:=Buf;
 FillChar(SBuf,SizeOf(SBuf),0);
 L:=SizeOf(SBuf)-1;
 If HttpQueryInfoA(H,5,@SBuf[0],L,Nil)<>0 Then Val(AnsiString(PChar(@SBuf[0])),ContentLen,Code);
 HttpOpen:=H;
End;
{$ENDIF}

Function HttpGetString(Const Url,Token:AnsiString;Var Body:AnsiString;Var Status:LongInt):Boolean;
{$IFDEF WINDOWS}
Var
 H,Sess:Pointer;
 Cl:Int64;
 Got:LongWord;
 Buf:Array[0..65535]of Byte;
 N:LongInt;
Begin
 HttpGetString:=False;
 Body:='';
 H:=HttpOpen(Url,Token,0,Status,Cl,Sess);
 If H=Nil Then Exit;
 Repeat
  Got:=0;
  If InternetReadFile(H,@Buf[0],SizeOf(Buf),Got)=0 Then Break;
  If Got>0 Then Begin
   N:=Length(Body);
   SetLength(Body,N+Got);
   Move(Buf[0],Body[N+1],Got);
  End;
 Until Got=0;
 InternetCloseHandle(H);
 InternetCloseHandle(Sess);
 HttpGetString:=(Status>=200)and(Status<300);
End;
{$ELSE}
Begin
 Body:='';Status:=0;
 HttpGetString:=False;
End;
{$ENDIF}

Function HttpDownload(Const Url,Token,Dest:AnsiString;Var Err:AnsiString):Boolean;
{$IFDEF WINDOWS}
Const
 MaxTries=10;
Var
 H,Sess:Pointer;
 Status:LongInt;
 Cl,Done,Total:Int64;
 Got:LongWord;
 Buf:Array[0..65535]of Byte;
 F:File;
 Tmp:AnsiString;
 LastPc,Pc,Try_,Wait:LongInt;
 Fin,Fatal:Boolean;
Begin
 HttpDownload:=False;
 Err:='';
 MakeDirs(PathDir(Dest));
 Tmp:=Dest+'.downloadInProgress';
 Done:=0;Total:=-1;
 { reprise d'un telechargement interrompu }
 Assign(F,Tmp);
 {$I-}Reset(F,1);{$I+}
 If IOResult=0 Then Begin
  Done:=FileSize(F);
  Close(F);
  If Done>0 Then Write(StdErr,'reprise du t'+#130+'l'+#130+'chargement '+#133+' '+HumanBytes(Done)+#10);
 End;
 Fin:=False;Fatal:=False;Try_:=0;
 While(not Fin)and(not Fatal)and(Try_<MaxTries)do Begin
  Inc(Try_);
  If Try_>1 Then Begin
   Wait:=Try_*2;
   if Wait>20 Then Wait:=20;
   Write(StdErr,#10'nouvelle tentative '+IStr(Try_)+'/'+IStr(MaxTries)+' dans '+IStr(Wait)+' s ('+Err+')'#10);
   Flush(StdErr);
   WinSleep(LongWord(Wait)*1000);
  End;
  Err:='';
  H:=HttpOpen(Url,Token,Done,Status,Cl,Sess);
  If H=Nil Then Begin Err:=#144+'chec de la connexion '+#133+' '+Url;Continue;End;
  If Status=416 Then Begin
   { le fichier partiel est deja complet ou invalide }
   InternetCloseHandle(H);InternetCloseHandle(Sess);
   If Total>0 Then Fin:=(Done=Total) Else Begin Done:=0;Assign(F,Tmp);Erase(F);If IOResult<>0 Then;End;
   If not Fin Then Err:='plage refus'+#130+'e par le serveur, red'+#130+'marrage';
   Continue;
  End;
  If(Status<200)or(Status>=300)Then Begin
   Err:='le serveur a r'+#130+'pondu avec le code HTTP '+IStr(Status)+' pour '+Url;
   InternetCloseHandle(H);InternetCloseHandle(Sess);
   { les erreurs 4xx (hors 408/429) ne se corrigent pas en reessayant }
   If(Status>=400)and(Status<500)and(Status<>408)and(Status<>429)Then Fatal:=True;
   Continue;
  End;
  Assign(F,Tmp);
  If(Status=206)and(Done>0)Then Begin
   {$I-}Reset(F,1);{$I+}
   If IOResult=0 Then Seek(F,Done);
   If Cl>0 Then Total:=Done+Cl;
  End Else Begin
   { le serveur renvoie tout le fichier : on repart de zero }
   Done:=0;
   Total:=Cl;
   {$I-}Rewrite(F,1);{$I+}
  End;
  If IOResult<>0 Then Begin
   Err:='impossible de cr'+#130+'er '+Tmp;
   InternetCloseHandle(H);InternetCloseHandle(Sess);
   Fatal:=True;
   Continue;
  End;
  LastPc:=-1;
  Repeat
   Got:=0;
   If InternetReadFile(H,@Buf[0],SizeOf(Buf),Got)=0 Then Begin Err:='erreur de lecture réseau';Break;End;
   If Got>0 Then Begin
    BlockWrite(F,Buf[0],Got);
    Inc(Done,Got);
    If Total>0 Then Begin
     Pc:=(Done*100)div Total;
     If Pc<>LastPc Then Begin
      LastPc:=Pc;
      Write(StdErr,#13'T'+#130+'l'+#130+'chargement de '+PathLastPart(Dest)+' : '+IStr(Pc)+'% ('+HumanBytes(Done)+')');
      Flush(StdErr);
     End;
    End;
   End;
  Until Got=0;
  Close(F);
  If IOResult<>0 Then;
  InternetCloseHandle(H);InternetCloseHandle(Sess);
  If Err='' Then Begin
   If(Total>0)and(Done<>Total)Then Err:='t'+#130+'l'+#130+'chargement incomplet'
   Else Fin:=True;
  End;
 End;
 Write(StdErr,#10);
 If not Fin Then Begin
  If Err='' Then Err:=#144+'chec du t'+#130+'l'+#130+'chargement';
  Err:=Err+' ; relancez la m'+#136+'me commande pour reprendre '+#133+' '+HumanBytes(Done);
  Exit;
 End;
 If FileExistsP(Dest)Then Begin Assign(F,Dest);Erase(F);If IOResult<>0 Then;End;
 Assign(F,Tmp);
 Rename(F,Dest);
 If IOResult<>0 Then Begin Err:='impossible de renommer le fichier t'+#130+'l'+#130+'charg'+#130;Exit;End;
 HttpDownload:=True;
End;
{$ELSE}
Begin
 Err:='les fonctions r'+#130+'seau ne sont disponibles que sous Windows';
 HttpDownload:=False;
End;
{$ENDIF}

{ ------------------------------------------------------------------ }
{ Telechargement de modeles (Hugging Face / URL)                      }
{ ------------------------------------------------------------------ }

Function SafeCacheName(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
 R:AnsiString;
Begin
 R:=S;
 For I:=1 to Length(R)do If R[I]in['/','\',':','*','?','"','<','>','|']Then R[I]:='_';
 SafeCacheName:=R;
End;

Function UrlFileName(Const Url:AnsiString):AnsiString;
Var
 U:AnsiString;
 P:LongInt;
Begin
 U:=Url;
 P:=Pos('?',U);
 If P>0 Then U:=Copy(U,1,P-1);
 UrlFileName:=PathLastPart(U);
 P:=Length(U);
 While(P>0)and(U[P]<>'/')do Dec(P);
 UrlFileName:=Copy(U,P+1,Length(U));
End;

{ Telecharge (si necessaire) un modele depuis une URL ; renvoie le chemin local }
Function ResolveModelUrl(Const Url,Token:AnsiString;Offline:Boolean;Var Local:AnsiString):Boolean;
Var
 Err:AnsiString;
Begin
 ResolveModelUrl:=False;
 Local:=CacheDir+PathSep+SafeCacheName(UrlFileName(Url));
 If FileExistsP(Local)Then Begin ResolveModelUrl:=True;Exit;End;
 If Offline Then Begin LogErr('erreur : mode hors ligne et modèle absent du cache : '+Local+#10);Exit;End;
 If not NetSupported Then Begin
  LogErr('erreur : le téléchargement (-mu / -hf) n''est disponible que sous Windows.'+#10);
  LogErr('        Téléchargez le fichier GGUF manuellement puis utilisez -m FICHIER.'+#10);
  Exit;
 End;
 LogInf('téléchargement de '+Url+' vers '+Local+#10);
 If not HttpDownload(Url,Token,Local,Err)Then Begin
  LogErr('erreur : '+Err+#10);
  Exit;
 End;
 ResolveModelUrl:=True;
End;

Function ResolveModelHF(Const RepoSpec,FileOverride,Token:AnsiString;Offline:Boolean;Var Local:AnsiString):Boolean;
Var
 Repo,Quant,Body,Err,FName,Url,Cand,UQ:AnsiString;
 P,I,Status:LongInt;
 Tree,E:PJ;
 Files:TStrArray;
 Best:LongInt;
 SR:SearchRec;
 Pat:AnsiString;
Begin
 ResolveModelHF:=False;
 Repo:=RepoSpec;Quant:='';
 P:=Pos(':',Repo);
 If P>0 Then Begin Quant:=Copy(Repo,P+1,Length(Repo));Repo:=Copy(Repo,1,P-1);End;
 If(Pos('/',Repo)=0)Then Begin
  LogErr('erreur : le dépôt Hugging Face doit être de la forme <utilisateur>/<modèle>[:quant]'+#10);
  Exit;
 End;
 FName:=FileOverride;
 { cache : un fichier correspondant existe-t-il deja ? }
 If FName<>'' Then Begin
  Local:=CacheDir+PathSep+SafeCacheName(Repo+'_'+FName);
  If FileExistsP(Local)Then Begin ResolveModelHF:=True;Exit;End;
 End
  Else Begin
   If Quant='' Then UQ:='Q4_K_M' Else UQ:=UpStr(Quant);
   Pat:=CacheDir+PathSep+SafeCacheName(Repo)+'_*';
   FindFirst(Pat,AnyFile,SR);
   While DosError=0 do Begin
    If EndsWith(LoStr(SR.Name),'.gguf')and(Pos(UQ,UpStr(SR.Name))>0)and(Pos('mmproj',LoStr(SR.Name))=0)Then Begin
     Local:=CacheDir+PathSep+SR.Name;
     FindClose(SR);
     ResolveModelHF:=True;
     Exit;
    End;
    FindNext(SR);
   End;
   FindClose(SR);
  End;
 If Offline Then Begin LogErr('erreur : mode hors ligne et modèle absent du cache'+#10);Exit;End;
 If not NetSupported Then Begin
  LogErr('erreur : l''option -hf n''est disponible que sous Windows (appels réseau).'+#10);
  LogErr('        Téléchargez le fichier GGUF manuellement puis utilisez -m FICHIER.'+#10);
  Exit;
 End;
 If FName='' Then Begin
  Url:='https://huggingface.co/api/models/'+Repo+'/tree/main?recursive=true';
  If not HttpGetString(Url,Token,Body,Status)Then Begin
   LogErr('erreur : impossible de lister les fichiers du dépôt '+Repo+' (HTTP '+IStr(Status)+')'+#10);
   Exit;
  End;
  Tree:=JParse(Body);
  If(Tree=Nil)or(Tree^.Kind<>JK_ARR)Then Begin LogErr('erreur : réponse invalide de Hugging Face'+#10);Exit;End;
  SetLength(Files,0);
  For I:=0 to High(Tree^.Items)do Begin
   E:=JGet(Tree^.Items[I],'path');
   If(E<>Nil)and(E^.Kind=JK_STR)and EndsWith(LoStr(E^.S),'.gguf')and(Pos('mmproj',LoStr(E^.S))=0)Then
    AddStr(Files,E^.S);
  End;
  If Length(Files)=0 Then Begin LogErr('erreur : aucun fichier GGUF dans le dépôt '+Repo+#10);Exit;End;
  If Quant='' Then UQ:='Q4_K_M' Else UQ:=UpStr(Quant);
  Best:=-1;
  For I:=0 to High(Files)do
   If(Pos(UQ,UpStr(Files[I]))>0)and((Best<0)or(Pos('-00001-of-',Files[I])>0))Then Best:=I;
  If Best<0 Then Begin
   If Quant<>'' Then Begin
    LogErr('erreur : aucun fichier GGUF correspondant à la quantification '+Quant+' dans '+Repo+#10);
    Exit;
   End;
   Best:=0;
  End;
  FName:=Files[Best];
 End;
 Local:=CacheDir+PathSep+SafeCacheName(Repo+'_'+FName);
 If FileExistsP(Local)Then Begin ResolveModelHF:=True;Exit;End;
 Url:='https://huggingface.co/'+Repo+'/resolve/main/'+FName;
 LogInf('téléchargement de '+Url+#10);
 If not HttpDownload(Url,Token,Local,Err)Then Begin LogErr('erreur : '+Err+#10);Exit;End;
 { parties supplementaires d'un modele fractionne }
 P:=Pos('-00001-of-',FName);
 If P>0 Then Begin
  I:=2;
  While True do Begin
   Cand:=Copy(FName,1,P-1)+'-'+Copy('00000'+IStr(I),Length(IStr(I))+1,5)+Copy(FName,P+6,Length(FName));
   If I>StrToIntDef(Copy(FName,P+10,5),1)Then Break;
   Url:='https://huggingface.co/'+Repo+'/resolve/main/'+Cand;
   If not HttpDownload(Url,Token,CacheDir+PathSep+SafeCacheName(Repo+'_'+Cand),Err)Then Begin
    LogErr('erreur : '+Err+#10);Exit;
   End;
   Inc(I);
  End;
 End;
 ResolveModelHF:=True;
End;

Procedure PrintCacheList;
Var
 SR:SearchRec;
 N:LongInt;
Begin
 WriteLn('model cache directory: ',CacheDir);
 N:=0;
 FindFirst(CacheDir+PathSep+'*.gguf',AnyFile,SR);
 While DosError=0 do Begin
  If(SR.Attr and Directory)=0 Then Inc(N);
  FindNext(SR);
 End;
 FindClose(SR);
 WriteLn('number of models in cache: ',N);
 N:=0;
 FindFirst(CacheDir+PathSep+'*.gguf',AnyFile,SR);
 While DosError=0 do Begin
  If(SR.Attr and Directory)=0 Then Begin
   Inc(N);
   WriteLn(PadLeft(IStr(N),4),'. ',SR.Name);
  End;
  FindNext(SR);
 End;
 FindClose(SR);
End;

{ ------------------------------------------------------------------ }
{ Table des options de la ligne de commande                           }
{ ------------------------------------------------------------------ }

Type
 TOpt=Record
  Names:TStrArray;
  Hint,Hint2,Env:AnsiString;
  Id,Sec:LongInt;
  Help:AnsiString;
 End;

Var
 Opts:Array of TOpt;

Procedure Opt(Const NamesS,Hint,Hint2,Env:AnsiString;Id,Sec:LongInt;Const Help:AnsiString);
Var
 N:LongInt;
Begin
 N:=Length(Opts);
 SetLength(Opts,N+1);
 Opts[N].Names:=SplitStr(NamesS,'|');
 Opts[N].Hint:=Hint;Opts[N].Hint2:=Hint2;Opts[N].Env:=Env;
 Opts[N].Id:=Id;Opts[N].Sec:=Sec;Opts[N].Help:=Help;
End;

Const
 O_HELP=1; O_VERSION=2; O_CACHELIST=3; O_THREADS=4; O_THREADSB=5; O_CPUMASK=6; O_CPURANGE=7;
 O_CPUSTRICT=8; O_PRIO=9; O_POLL=10; O_CPUMASKB=11; O_CPURANGEB=12; O_CPUSTRICTB=13; O_PRIOB=14;
 O_POLLB=15; O_CTX=16; O_PREDICT=17; O_BATCH=18; O_UBATCH=19; O_KEEP=20; O_SWAFULL=21; O_FA=22;
 O_PROMPT=23; O_PERF=24; O_NOPERF=25; O_FILE=26; O_BINFILE=27; O_ESCAPE=28; O_NOESCAPE=29;
 O_ROPESCALING=30; O_ROPESCALE=31; O_ROPEBASE=32; O_ROPEFSCALE=33; O_YARNORIG=34; O_YARNEXT=35;
 O_YARNATTN=36; O_YARNSLOW=37; O_YARNFAST=38; O_KVOFFLOAD=39; O_NOKVOFFLOAD=40; O_REPACK=41;
 O_NOREPACK=42; O_NOHOST=43; O_CTK=44; O_CTV=45; O_DEFRAG=46; O_PARALLEL=47; O_RPC=48; O_LOADMODE=49;
 O_LAZYMODE=50; O_NUMA=51; O_DEVICE=52; O_LISTDEVICES=53; O_OVERRIDETENSOR=54; O_CPUMOE=55;
 O_NCPUMOE=56; O_NCPUFFN=57; O_NGL=58; O_SM=59; O_TS=60; O_MG=61; O_FIT=62; O_FITT=63; O_FITC=64;
 O_CHECKTENSORS=65; O_OVERRIDEKV=66; O_OPOFFLOAD=67; O_NOOPOFFLOAD=68; O_LORA=69; O_LORASCALED=70;
 O_CVEC=71; O_CVECSCALED=72; O_CVECRANGE=73; O_MODEL=74; O_MODELURL=75; O_DOCKER=76; O_HFREPO=77;
 O_HFFILE=78; O_HFTOKEN=79; O_LOGDISABLE=80; O_LOGFILE=81; O_LOGJSONL=82; O_NOLOGJSONL=83;
 O_LOGCOLORS=84; O_VERBOSE=85; O_OFFLINE=86; O_VERBOSITY=87; O_LOGPREFIX=88; O_NOLOGPREFIX=89;
 O_LOGTS=90; O_NOLOGTS=91; O_SAMPLERS=92; O_SEED=93; O_SAMPLERSEQ=94; O_IGNOREEOS=95; O_TEMP=96;
 O_TOPK=97; O_TOPP=98; O_MINP=99; O_TOPNSIGMA=100; O_XTCP=101; O_XTCT=102; O_TYPICAL=103;
 O_REPEATLASTN=104; O_REPEATPEN=105; O_PRESENCEPEN=106; O_FREQPEN=107; O_DRYMULT=108; O_DRYBASE=109;
 O_DRYALLOWED=110; O_DRYLASTN=111; O_DRYBREAK=112; O_ADAPTTARGET=113; O_ADAPTDECAY=114;
 O_DYNRANGE=115; O_DYNEXP=116; O_MIROSTAT=117; O_MIROLR=118; O_MIROENT=119; O_LOGITBIAS=120;
 O_GRAMMAR=121; O_GRAMMARFILE=122; O_JSONSCHEMA=123; O_JSONSCHEMAFILE=124; O_BACKENDSAMPLING=125;
 O_SERVERBASE=126; O_VERBOSEPROMPT=127; O_DISPLAYPROMPT=128; O_NODISPLAYPROMPT=129; O_COLOR=130;
 O_CTXCP=131; O_CRAM=132; O_CONTEXTSHIFT=133; O_NOCONTEXTSHIFT=134; O_SYSPROMPT=135;
 O_SHOWTIMINGS=136; O_NOSHOWTIMINGS=137; O_SYSFILE=138; O_INFILE=139; O_PTC=140; O_PROMPTCACHE=141;
 O_PROMPTCACHEALL=142; O_PROMPTCACHERO=143; O_REVERSE=144; O_SPECIAL=145; O_CNV=146; O_NOCNV=147;
 O_SINGLETURN=148; O_INTERACTIVE=149; O_INTERACTIVEFIRST=150; O_MULTILINE=151; O_INPREFIXBOS=152;
 O_INPREFIX=153; O_INSUFFIX=154; O_WARMUP=155; O_NOWARMUP=156; O_MMPROJ=157; O_MMPROJURL=158;
 O_NOMMPROJ=159; O_IMAGE=160; O_OUTPUT=161; O_CHATKWARGS=162; O_JINJA=163; O_NOJINJA=164;
 O_REASONINGFMT=165; O_REASONING=166; O_REASONINGEFFORT=167; O_REASONINGBUDGET=168;
 O_REASONINGBUDGETMSG=169; O_REASONINGPRESERVE=170; O_NOREASONINGPRESERVE=171; O_CHATTEMPLATE=172;
 O_CHATTEMPLATEFILE=173; O_SKIPCHATPARSING=174; O_NOSKIPCHATPARSING=175; O_SIMPLEIO=176;
 O_LOGPROMPTSDIR=177; O_MODELDRAFT=178;

Procedure RegisterOptions;
Begin
 Opt('-h|--help|--usage|/?','','','',O_HELP,0,'affiche l''aide et quitte');
 Opt('--version','','','',O_VERSION,0,'affiche la version et les informations de compilation');
 Opt('-cl|--cache-list','','','',O_CACHELIST,0,'affiche la liste des modèles présents dans le cache');
 Opt('-t|--threads','N','','LLAMA_ARG_THREADS',O_THREADS,0,'nombre de threads CPU pour la génération (défaut : -1) ; ce clone calcule sur un seul fil');
 Opt('-tb|--threads-batch','N','','',O_THREADSB,0,'nombre de threads pour le traitement des lots et du prompt (défaut : identique à --threads)');
 Opt('-C|--cpu-mask','M','','',O_CPUMASK,0,'masque d''affinité CPU : hexadécimal de longueur arbitraire (ignoré)');
 Opt('-Cr|--cpu-range','lo-hi','','',O_CPURANGE,0,'plage de processeurs pour l''affinité (ignoré)');
 Opt('--cpu-strict','<0|1>','','',O_CPUSTRICT,0,'placement strict des threads (défaut : 0, ignoré)');
 Opt('--prio','N','','',O_PRIO,0,'priorité du processus/thread : bas(-1), normal(0), moyen(1), haut(2), temps réel(3) (ignoré)');
 Opt('--poll','<0...100>','','',O_POLL,0,'niveau d''attente active (défaut : 50, ignoré)');
 Opt('-Cb|--cpu-mask-batch','M','','',O_CPUMASKB,0,'masque d''affinité CPU pour le traitement par lots (ignoré)');
 Opt('-Crb|--cpu-range-batch','lo-hi','','',O_CPURANGEB,0,'plage de CPU pour le traitement par lots (ignoré)');
 Opt('--cpu-strict-batch','<0|1>','','',O_CPUSTRICTB,0,'placement strict pour le traitement par lots (ignoré)');
 Opt('--prio-batch','N','','',O_PRIOB,0,'priorité pour le traitement par lots (ignoré)');
 Opt('--poll-batch','<0|1>','','',O_POLLB,0,'attente active pour le traitement par lots (ignoré)');
 Opt('-c|--ctx-size','N','','LLAMA_ARG_CTX_SIZE',O_CTX,0,'taille du contexte du prompt (défaut : 0 = valeur du modèle, plafonnée selon la mémoire)');
 Opt('-n|--predict|--n-predict','N','','LLAMA_ARG_N_PREDICT',O_PREDICT,0,'nombre de jetons à générer (défaut : -1 = infini, -2 = jusqu''à remplir le contexte)');
 Opt('-b|--batch-size','N','','LLAMA_ARG_BATCH',O_BATCH,0,'taille logique maximale d''un lot (défaut : 2048)');
 Opt('-ub|--ubatch-size','N','','LLAMA_ARG_UBATCH',O_UBATCH,0,'taille physique maximale d''un lot (défaut : 512)');
 Opt('--keep','N','','',O_KEEP,0,'nombre de jetons à conserver du prompt initial (défaut : 0, -1 = tous)');
 Opt('--swa-full','','','',O_SWAFULL,0,'utilise un cache SWA de taille complète (ignoré)');
 Opt('-fa|--flash-attn','[on|off|auto]','','LLAMA_ARG_FLASH_ATTN',O_FA,0,'active Flash Attention (ignoré)');
 Opt('-p|--prompt','PROMPT','','',O_PROMPT,0,'prompt de départ pour la génération ; pour un message système, utiliser -sys');
 Opt('--perf','','','',O_PERF,0,'active les mesures de performance internes (défaut : désactivé)');
 Opt('--no-perf','','','',O_NOPERF,0,'désactive les mesures de performance internes');
 Opt('-f|--file','FNAME','','',O_FILE,0,'fichier contenant le prompt (défaut : aucun)');
 Opt('-bf|--binary-file','FNAME','','',O_BINFILE,0,'fichier binaire contenant le prompt (défaut : aucun)');
 Opt('-e|--escape','','','',O_ESCAPE,0,'traite les séquences d''échappement (\n, \r, \t, \'', \", \\) (défaut : activé)');
 Opt('--no-escape','','','',O_NOESCAPE,0,'ne traite pas les séquences d''échappement');
 Opt('--rope-scaling','{none,linear,yarn}','','LLAMA_ARG_ROPE_SCALING_TYPE',O_ROPESCALING,0,'méthode de mise à l''échelle des fréquences RoPE (défaut : valeur du modèle)');
 Opt('--rope-scale','N','','LLAMA_ARG_ROPE_SCALE',O_ROPESCALE,0,'facteur d''extension du contexte RoPE : étend le contexte d''un facteur N');
 Opt('--rope-freq-base','N','','LLAMA_ARG_ROPE_FREQ_BASE',O_ROPEBASE,0,'fréquence de base RoPE, utilisée par la mise à l''échelle NTK (défaut : valeur du modèle)');
 Opt('--rope-freq-scale','N','','LLAMA_ARG_ROPE_FREQ_SCALE',O_ROPEFSCALE,0,'facteur de fréquence RoPE : étend le contexte d''un facteur 1/N');
 Opt('--yarn-orig-ctx','N','','LLAMA_ARG_YARN_ORIG_CTX',O_YARNORIG,0,'YaRN : taille de contexte d''origine du modèle (défaut : 0 = contexte d''entraînement)');
 Opt('--yarn-ext-factor','N','','LLAMA_ARG_YARN_EXT_FACTOR',O_YARNEXT,0,'YaRN : facteur de mélange d''extrapolation (défaut : -1,00 ; 0,0 = interpolation complète)');
 Opt('--yarn-attn-factor','N','','LLAMA_ARG_YARN_ATTN_FACTOR',O_YARNATTN,0,'YaRN : échelle sqrt(t) ou amplitude de l''attention (défaut : -1,00)');
 Opt('--yarn-beta-slow','N','','LLAMA_ARG_YARN_BETA_SLOW',O_YARNSLOW,0,'YaRN : dimension de correction haute ou alpha (défaut : -1,00)');
 Opt('--yarn-beta-fast','N','','LLAMA_ARG_YARN_BETA_FAST',O_YARNFAST,0,'YaRN : dimension de correction basse ou bêta (défaut : -1,00)');
 Opt('-kvo|--kv-offload','','','',O_KVOFFLOAD,0,'déport du cache KV (sans effet : pas de GPU)');
 Opt('-nkvo|--no-kv-offload','','','',O_NOKVOFFLOAD,0,'désactive le déport du cache KV (sans effet)');
 Opt('--repack','','','',O_REPACK,0,'réorganisation des poids (sans effet)');
 Opt('-nr|--no-repack','','','',O_NOREPACK,0,'désactive la réorganisation des poids (sans effet)');
 Opt('--no-host','','','',O_NOHOST,0,'évite les tampons mémoire de l''hôte (sans effet)');
 Opt('-ctk|--cache-type-k','TYPE','','LLAMA_ARG_CACHE_TYPE_K',O_CTK,0,'type de données du cache KV pour K : f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1 (ce clone stocke toujours en f32)');
 Opt('-ctv|--cache-type-v','TYPE','','LLAMA_ARG_CACHE_TYPE_V',O_CTV,0,'type de données du cache KV pour V (ce clone stocke toujours en f32)');
 Opt('-dt|--defrag-thold','N','','',O_DEFRAG,0,'seuil de défragmentation du cache KV (obsolète, ignoré)');
 Opt('-np|--parallel','N','','LLAMA_ARG_N_PARALLEL',O_PARALLEL,0,'nombre de séquences décodées en parallèle (défaut : 1)');
 Opt('--rpc','SERVERS','','LLAMA_ARG_RPC',O_RPC,0,'liste de serveurs RPC séparés par des virgules (non supporté)');
 Opt('-lm|--load-mode','MODE','','LLAMA_ARG_LOAD_MODE',O_LOADMODE,0,'mode de chargement du modèle : auto, none, mmap, mlock, mmap+mlock, dio (ce clone charge toujours en mémoire)');
 Opt('-lzm|--lazy-mode','MODE','','LLAMA_ARG_LAZY_MODE',O_LAZYMODE,0,'lecture à la demande de certains tenseurs (ignoré)');
 Opt('--numa','TYPE','','LLAMA_ARG_NUMA',O_NUMA,0,'optimisations NUMA : distribute, isolate, numactl (ignoré)');
 Opt('-dev|--device','<dev1,dev2,..>','','LLAMA_ARG_DEVICE',O_DEVICE,0,'liste de périphériques de déport (aucun GPU : ignoré)');
 Opt('--list-devices','','','',O_LISTDEVICES,0,'affiche la liste des périphériques disponibles et quitte');
 Opt('-ot|--override-tensor','<motif>=<tampon>,...','','LLAMA_ARG_OVERRIDE_TENSOR',O_OVERRIDETENSOR,0,'remplace le type de tampon d''un tenseur (ignoré)');
 Opt('-cmoe|--cpu-moe','','','',O_CPUMOE,0,'garde tous les poids MoE sur le CPU (toujours le cas ici)');
 Opt('-ncmoe|--n-cpu-moe','N','','',O_NCPUMOE,0,'garde les poids MoE des N premières couches sur le CPU (toujours le cas ici)');
 Opt('-ncffn|--n-cpu-ffn','N','','',O_NCPUFFN,0,'garde les poids FFN denses des N premières couches sur le CPU (toujours le cas ici)');
 Opt('-ngl|--gpu-layers|--n-gpu-layers','N','','LLAMA_ARG_N_GPU_LAYERS',O_NGL,0,'nombre de couches à placer en VRAM (aucun GPU : ignoré)');
 Opt('-sm|--split-mode','{none,layer,row,tensor}','','LLAMA_ARG_SPLIT_MODE',O_SM,0,'répartition du modèle sur plusieurs GPU (ignoré)');
 Opt('-ts|--tensor-split','N0,N1,N2,...','','LLAMA_ARG_TENSOR_SPLIT',O_TS,0,'fraction du modèle à placer sur chaque GPU (ignoré)');
 Opt('-mg|--main-gpu','INDEX','','LLAMA_ARG_MAIN_GPU',O_MG,0,'GPU principal (ignoré)');
 Opt('-fit|--fit','[on|off]','','LLAMA_ARG_FIT',O_FIT,0,'ajuste les arguments non définis à la mémoire disponible (ignoré)');
 Opt('-fitt|--fit-target','MiB0,MiB1,...','','LLAMA_ARG_FIT_TARGET',O_FITT,0,'marge cible par périphérique pour --fit (ignoré)');
 Opt('-fitc|--fit-ctx','N','','LLAMA_ARG_FIT_CTX',O_FITC,0,'taille de contexte minimale pour --fit (ignoré)');
 Opt('--check-tensors','','','',O_CHECKTENSORS,0,'vérifie la validité des données des tenseurs');
 Opt('--override-kv','CLÉ=TYPE:VALEUR,...','','',O_OVERRIDEKV,0,'remplace des métadonnées du modèle ; types : int, float, bool, str');
 Opt('--op-offload','','','',O_OPOFFLOAD,0,'déport des opérations vers un périphérique (sans effet)');
 Opt('--no-op-offload','','','',O_NOOPOFFLOAD,0,'désactive le déport des opérations (sans effet)');
 Opt('--lora','FNAME','','',O_LORA,0,'adaptateur LoRA (non supporté, ignoré avec un avertissement)');
 Opt('--lora-scaled','FNAME:ÉCHELLE,...','','',O_LORASCALED,0,'adaptateur LoRA avec échelle (non supporté, ignoré)');
 Opt('--control-vector','FNAME','','',O_CVEC,0,'vecteur de contrôle (non supporté, ignoré)');
 Opt('--control-vector-scaled','FNAME:ÉCHELLE,...','','',O_CVECSCALED,0,'vecteur de contrôle avec échelle (non supporté, ignoré)');
 Opt('--control-vector-layer-range','DÉBUT','FIN','',O_CVECRANGE,0,'plage de couches du vecteur de contrôle (ignoré)');
 Opt('-m|--model','FNAME','','LLAMA_ARG_MODEL',O_MODEL,0,'chemin du modèle GGUF à charger');
 Opt('-mu|--model-url','URL_MODÈLE','','LLAMA_ARG_MODEL_URL',O_MODELURL,0,'URL de téléchargement du modèle (Windows uniquement)');
 Opt('-dr|--docker-repo','[<dépôt>/]<modèle>[:quant]','','LLAMA_ARG_DOCKER_REPO',O_DOCKER,0,'dépôt Docker Hub (non supporté)');
 Opt('-hf|-hfr|--hf-repo','<utilisateur>/<modèle>[:quant]','','LLAMA_ARG_HF_REPO',O_HFREPO,0,'dépôt Hugging Face ; la quantification est facultative (défaut : Q4_K_M, sinon premier fichier) ; téléchargement disponible sous Windows uniquement');
 Opt('-hff|--hf-file','FILE','','LLAMA_ARG_HF_FILE',O_HFFILE,0,'fichier du dépôt Hugging Face ; remplace la quantification de --hf-repo');
 Opt('-hft|--hf-token','TOKEN','','HF_TOKEN',O_HFTOKEN,0,'jeton d''accès Hugging Face (défaut : variable d''environnement HF_TOKEN)');
 Opt('--log-disable','','','',O_LOGDISABLE,0,'désactive les journaux');
 Opt('--log-file','FNAME','','LLAMA_ARG_LOG_FILE',O_LOGFILE,0,'écrit aussi les journaux dans un fichier');
 Opt('--log-jsonl','','','',O_LOGJSONL,0,'journaux au format JSONL (ignoré)');
 Opt('--no-log-jsonl','','','',O_NOLOGJSONL,0,'journaux au format texte (défaut)');
 Opt('--log-colors','[on|off|auto]','','LLAMA_ARG_LOG_COLORS',O_LOGCOLORS,0,'couleurs dans les journaux (défaut : auto)');
 Opt('-v|--verbose|--log-verbose','','','',O_VERBOSE,0,'niveau de verbosité maximal (tous les messages, utile pour le débogage)');
 Opt('--offline','','','',O_OFFLINE,0,'mode hors ligne : force l''utilisation du cache et interdit l''accès réseau');
 Opt('-lv|--verbosity|--log-verbosity','N','','LLAMA_ARG_LOG_VERBOSITY',O_VERBOSITY,0,'seuil de verbosité : 0 générique, 1 erreur, 2 avertissement, 3 info, 4 trace, 5 débogage (défaut : 3)');
 Opt('--log-prefix','','','',O_LOGPREFIX,0,'préfixe dans les messages de journal');
 Opt('--no-log-prefix','','','',O_NOLOGPREFIX,0,'pas de préfixe dans les messages de journal');
 Opt('--log-timestamps','','','',O_LOGTS,0,'horodatage dans les messages de journal');
 Opt('--no-log-timestamps','','','',O_NOLOGTS,0,'pas d''horodatage dans les messages de journal');
 Opt('--samplers','ÉCHANTILLONNEURS','','',O_SAMPLERS,1,'échantillonneurs utilisés, dans l''ordre, séparés par « ; » (défaut : penalties;dry;top_n_sigma;top_k;typ_p;top_p;min_p;xtc;temperature)');
 Opt('-s|--seed','GRAINE','','',O_SEED,1,'graine du générateur aléatoire (défaut : -1 = graine aléatoire)');
 Opt('--sampler-seq|--sampling-seq','SÉQUENCE','','',O_SAMPLERSEQ,1,'séquence simplifiée d''échantillonneurs (défaut : edskypmxt)');
 Opt('--ignore-eos','','','',O_IGNOREEOS,1,'ignore le jeton de fin de séquence et continue la génération (revient à --logit-bias EOS-inf)');
 Opt('--temp|--temperature','N','','LLAMA_ARG_TEMPERATURE',O_TEMP,1,'température (défaut : 0,80)');
 Opt('--top-k','N','','LLAMA_ARG_TOP_K',O_TOPK,1,'échantillonnage top-k (défaut : 40, 0 = désactivé)');
 Opt('--top-p','N','','LLAMA_ARG_TOP_P',O_TOPP,1,'échantillonnage top-p (défaut : 0,95, 1,0 = désactivé)');
 Opt('--min-p','N','','LLAMA_ARG_MIN_P',O_MINP,1,'échantillonnage min-p (défaut : 0,05, 0,0 = désactivé)');
 Opt('--top-nsigma|--top-n-sigma','N','','',O_TOPNSIGMA,1,'échantillonnage top-n-sigma (défaut : -1,00, -1,0 = désactivé)');
 Opt('--xtc-probability','N','','',O_XTCP,1,'probabilité XTC (défaut : 0,00, 0,0 = désactivé)');
 Opt('--xtc-threshold','N','','',O_XTCT,1,'seuil XTC (défaut : 0,10, 1,0 = désactivé)');
 Opt('--typical|--typical-p','N','','',O_TYPICAL,1,'échantillonnage typique localement, paramètre p (défaut : 1,00, 1,0 = désactivé)');
 Opt('--repeat-last-n','N','','',O_REPEATLASTN,1,'nombre de derniers jetons pris en compte pour la pénalité (défaut : 64, 0 = désactivé, -1 = taille du contexte)');
 Opt('--repeat-penalty','N','','LLAMA_ARG_REPEAT_PENALTY',O_REPEATPEN,1,'pénalise les séquences répétées de jetons (défaut : 1,00, 1,0 = désactivé)');
 Opt('--presence-penalty','N','','LLAMA_ARG_PRESENCE_PENALTY',O_PRESENCEPEN,1,'pénalité de présence (défaut : 0,00, 0,0 = désactivé)');
 Opt('--frequency-penalty','N','','LLAMA_ARG_FREQUENCY_PENALTY',O_FREQPEN,1,'pénalité de fréquence (défaut : 0,00, 0,0 = désactivé)');
 Opt('--dry-multiplier','N','','',O_DRYMULT,1,'multiplicateur de l''échantillonnage DRY (défaut : 0,00, 0,0 = désactivé)');
 Opt('--dry-base','N','','',O_DRYBASE,1,'valeur de base de l''échantillonnage DRY (défaut : 1,75)');
 Opt('--dry-allowed-length','N','','',O_DRYALLOWED,1,'longueur autorisée pour DRY (défaut : 2)');
 Opt('--dry-penalty-last-n','N','','',O_DRYLASTN,1,'pénalité DRY sur les N derniers jetons (défaut : 64, 0 = désactivé, -1 = taille du contexte)');
 Opt('--dry-sequence-breaker','CHAÎNE','','',O_DRYBREAK,1,'ajoute une séquence de rupture pour DRY et supprime celles par défaut (\n, :, ", *) ; « none » désactive les séquences de rupture');
 Opt('--adaptive-target','N','','',O_ADAPTTARGET,1,'adaptive-p : probabilité cible des jetons choisis (0,0 à 1,0 ; négatif = désactivé) (défaut : -1,00)');
 Opt('--adaptive-decay','N','','',O_ADAPTDECAY,1,'adaptive-p : taux de décroissance de l''adaptation de la cible (0,0 à 0,99) (défaut : 0,90)');
 Opt('--dynatemp-range','N','','',O_DYNRANGE,1,'plage de température dynamique (défaut : 0,00, 0,0 = désactivé)');
 Opt('--dynatemp-exp','N','','',O_DYNEXP,1,'exposant de température dynamique (défaut : 1,00)');
 Opt('--mirostat','N','','',O_MIROSTAT,1,'utilise l''échantillonnage Mirostat (défaut : 0, 0 = désactivé, 1 = Mirostat, 2 = Mirostat 2.0) ; top-k, nucleus et typical sont alors ignorés');
 Opt('--mirostat-lr','N','','',O_MIROLR,1,'taux d''apprentissage de Mirostat, paramètre eta (défaut : 0,10)');
 Opt('--mirostat-ent','N','','',O_MIROENT,1,'entropie cible de Mirostat, paramètre tau (défaut : 5,00)');
 Opt('-l|--logit-bias','JETON_ID(+/-)BIAIS','','',O_LOGITBIAS,1,'modifie la probabilité d''apparition d''un jeton, par ex. --logit-bias 15043+1 ou --logit-bias 15043-1');
 Opt('--grammar','GRAMMAIRE','','',O_GRAMMAR,1,'grammaire de type BNF (GBNF) pour contraindre la génération');
 Opt('--grammar-file','FNAME','','',O_GRAMMARFILE,1,'fichier contenant la grammaire');
 Opt('-j|--json-schema','SCHÉMA','','',O_JSONSCHEMA,1,'schéma JSON pour contraindre la génération (https://json-schema.org/), par ex. {"type": "object"}');
 Opt('-jf|--json-schema-file','FICHIER','','',O_JSONSCHEMAFILE,1,'fichier contenant un schéma JSON pour contraindre la génération');
 Opt('-bs|--backend-sampling','','','',O_BACKENDSAMPLING,1,'échantillonnage sur le backend (ignoré)');
 Opt('--server-base','URL','','',O_SERVERBASE,2,'se connecte à un serveur existant (non supporté dans ce clone)');
 Opt('--verbose-prompt','','','',O_VERBOSEPROMPT,2,'affiche un prompt détaillé avant la génération (défaut : désactivé)');
 Opt('--display-prompt','','','',O_DISPLAYPROMPT,2,'affiche le prompt pendant la génération (défaut : activé)');
 Opt('--no-display-prompt','','','',O_NODISPLAYPROMPT,2,'n''affiche pas le prompt pendant la génération');
 Opt('-co|--color','[on|off|auto]','','',O_COLOR,2,'colore la sortie pour distinguer le prompt et la saisie de la génération (défaut : auto)');
 Opt('-ctxcp|--ctx-checkpoints|--swa-checkpoints','N','','LLAMA_ARG_CTX_CHECKPOINTS',O_CTXCP,2,'nombre maximal de points de contrôle de contexte (ignoré)');
 Opt('-cram|--cache-ram','N','','LLAMA_ARG_CACHE_RAM',O_CRAM,2,'taille maximale du cache en Mio (ignoré)');
 Opt('--context-shift','','','',O_CONTEXTSHIFT,2,'décale le contexte lors d''une génération infinie (défaut : désactivé)');
 Opt('--no-context-shift','','','',O_NOCONTEXTSHIFT,2,'ne décale pas le contexte (le programme s''arrête quand le contexte est plein)');
 Opt('-sys|--system-prompt','PROMPT','','',O_SYSPROMPT,2,'prompt système à utiliser avec le modèle (si le modèle de conversation le permet)');
 Opt('--show-timings','','','',O_SHOWTIMINGS,2,'affiche les temps après chaque réponse (défaut : activé)');
 Opt('--no-show-timings','','','',O_NOSHOWTIMINGS,2,'n''affiche pas les temps d''exécution');
 Opt('-sysf|--system-prompt-file','FNAME','','',O_SYSFILE,2,'fichier contenant le prompt système (défaut : aucun)');
 Opt('--in-file','FNAME','','',O_INFILE,2,'fichier(s) d''entrée (ignoré)');
 Opt('-ptc|--print-token-count','N','','',O_PTC,2,'affiche le nombre de jetons tous les N jetons (défaut : -1)');
 Opt('--prompt-cache','FNAME','','',O_PROMPTCACHE,2,'fichier de cache du prompt (non supporté, ignoré)');
 Opt('--prompt-cache-all','','','',O_PROMPTCACHEALL,2,'sauvegarde aussi les entrées et sorties dans le cache (non supporté)');
 Opt('--prompt-cache-ro','','','',O_PROMPTCACHERO,2,'cache du prompt en lecture seule (non supporté)');
 Opt('-r|--reverse-prompt','PROMPT','','',O_REVERSE,2,'arrête la génération à ce texte et rend la main en mode interactif');
 Opt('-sp|--special','','','',O_SPECIAL,2,'affiche les jetons spéciaux (défaut : désactivé)');
 Opt('-cnv|--conversation','','','',O_CNV,2,'mode conversation (activé automatiquement si le modèle contient un modèle de conversation)');
 Opt('-no-cnv|--no-conversation','','','',O_NOCNV,2,'désactive le mode conversation');
 Opt('-st|--single-turn','','','',O_SINGLETURN,2,'une seule tour de conversation puis quitte ; non interactif si le premier tour est fourni par --prompt');
 Opt('-i|--interactive','','','',O_INTERACTIVE,2,'mode interactif');
 Opt('-if|--interactive-first','','','',O_INTERACTIVEFIRST,2,'mode interactif, en attendant d''abord la saisie de l''utilisateur');
 Opt('-mli|--multiline-input','','','',O_MULTILINE,2,'permet d''écrire ou de coller plusieurs lignes sans terminer chacune par « \ »');
 Opt('--in-prefix-bos','','','',O_INPREFIXBOS,2,'ajoute le jeton BOS avant le préfixe de saisie');
 Opt('--in-prefix','CHAÎNE','','',O_INPREFIX,2,'préfixe ajouté devant chaque saisie de l''utilisateur');
 Opt('--in-suffix','CHAÎNE','','',O_INSUFFIX,2,'suffixe ajouté après chaque saisie de l''utilisateur');
 Opt('--warmup','','','',O_WARMUP,2,'effectue un préchauffage avec un passage à vide (défaut : activé)');
 Opt('--no-warmup','','','',O_NOWARMUP,2,'désactive le préchauffage');
 Opt('-mm|--mmproj','FILE','','LLAMA_ARG_MMPROJ',O_MMPROJ,2,'projecteur multimodal (non supporté, ignoré)');
 Opt('-mmu|--mmproj-url','URL','','LLAMA_ARG_MMPROJ_URL',O_MMPROJURL,2,'URL d''un projecteur multimodal (non supporté, ignoré)');
 Opt('--no-mmproj|--no-mmproj-auto','','','',O_NOMMPROJ,2,'désactive le projecteur multimodal');
 Opt('--image|--audio|--video','FILE','','',O_IMAGE,2,'fichier image, audio ou vidéo (non supporté, ignoré)');
 Opt('-o|--output|--output-file','FNAME','','',O_OUTPUT,2,'fichier de sortie : journal de la conversation (défaut : aucun)');
 Opt('--chat-template-kwargs','CHAÎNE','','LLAMA_ARG_CHAT_TEMPLATE_KWARGS',O_CHATKWARGS,2,'paramètres supplémentaires pour le modèle de conversation (objet JSON), par ex. {"enable_thinking":false}');
 Opt('--jinja','','','',O_JINJA,2,'utilise le moteur de modèles Jinja pour la conversation (défaut : activé)');
 Opt('--no-jinja','','','',O_NOJINJA,2,'n''utilise pas Jinja : modèles intégrés uniquement');
 Opt('--reasoning-format','FORMAT','','LLAMA_ARG_THINK',O_REASONINGFMT,2,'contrôle l''extraction des balises de réflexion : none, deepseek, deepseek-legacy (défaut : auto)');
 Opt('-rea|--reasoning','[on|off|auto]','','LLAMA_ARG_REASONING',O_REASONING,2,'utilise le raisonnement dans la conversation (défaut : auto, détecté depuis le modèle)');
 Opt('--reasoning-effort','NIVEAU','','LLAMA_ARG_REASONING_EFFORT',O_REASONINGEFFORT,2,'niveau d''effort de raisonnement transmis au modèle de conversation (défaut : default)');
 Opt('--reasoning-budget','N','','LLAMA_ARG_THINK_BUDGET',O_REASONINGBUDGET,2,'budget de jetons de réflexion : -1 illimité, 0 arrêt immédiat, N>0 budget (défaut : -1)');
 Opt('--reasoning-budget-message','MESSAGE','','LLAMA_ARG_THINK_BUDGET_MESSAGE',O_REASONINGBUDGETMSG,2,'message injecté avant la balise de fin de réflexion quand le budget est épuisé');
 Opt('--reasoning-preserve','','','',O_REASONINGPRESERVE,2,'conserve les traces de raisonnement dans l''historique (défaut : activé)');
 Opt('--no-reasoning-preserve','','','',O_NOREASONINGPRESERVE,2,'ne conserve pas les traces de raisonnement dans l''historique');
 Opt('--chat-template','MODÈLE_JINJA','','LLAMA_ARG_CHAT_TEMPLATE',O_CHATTEMPLATE,2,'modèle de conversation personnalisé (défaut : celui des métadonnées du modèle) ; modèles intégrés : @TEMPLATES@');
 Opt('--chat-template-file','FICHIER_MODÈLE_JINJA','','LLAMA_ARG_CHAT_TEMPLATE_FILE',O_CHATTEMPLATEFILE,2,'fichier contenant un modèle de conversation personnalisé');
 Opt('--skip-chat-parsing','','','',O_SKIPCHATPARSING,2,'force un analyseur de contenu simple (ignoré)');
 Opt('--no-skip-chat-parsing','','','',O_NOSKIPCHATPARSING,2,'analyse structurée des réponses (défaut)');
 Opt('--simple-io','','','',O_SIMPLEIO,2,'entrées/sorties simplifiées pour une meilleure compatibilité (sous-processus, consoles limitées)');
 Opt('--log-prompts-dir','CHEMIN','','',O_LOGPROMPTSDIR,2,'journalise les prompts dans un répertoire (débogage)');
 Opt('-md|--model-draft|--spec-draft-model','FNAME','','',O_MODELDRAFT,2,'modèle auxiliaire pour le décodage spéculatif (non supporté, ignoré)');
End;

Function FindOpt(Const Arg:AnsiString):LongInt;
Var
 I,J:LongInt;
Begin
 FindOpt:=-1;
 For I:=0 to High(Opts)do
  For J:=0 to High(Opts[I].Names)do
   If Opts[I].Names[J]=Arg Then Begin FindOpt:=I;Exit;End;
End;

{ coupe un texte en lignes de N caracteres au plus }
Function BreakLines(Const S:AnsiString;MaxLen:LongInt):TStrArray;
Var
 R:TStrArray;
 Line,Word_:AnsiString;
 I:LongInt;
 C:Char;
Begin
 SetLength(R,0);
 Line:='';Word_:='';
 For I:=1 to Length(S)+1 do Begin
  If I>Length(S)Then C:=' ' Else C:=S[I];
  If C in[' ',#10]Then Begin
   If Word_<>'' Then Begin
    If(Line<>'')and(Length(Line)+1+Length(Word_)>MaxLen)Then Begin
     AddStr(R,Line);Line:=Word_;
    End
     Else If Line='' Then Line:=Word_
     Else Line:=Line+' '+Word_;
    Word_:='';
   End;
   If C=#10 Then Begin AddStr(R,Line);Line:='';End;
  End
   Else Word_:=Word_+C;
 End;
 If Line<>'' Then AddStr(R,Line);
 If Length(R)=0 Then AddStr(R,'');
 BreakLines:=R;
End;

Function Utf8Length(Const S:AnsiString):LongInt;
Var
 I,N:LongInt;
Begin
 N:=0;
 For I:=1 to Length(S)do If(Ord(S[I])and $C0)<>$80 Then Inc(N);
 Utf8Length:=N;
End;

Function HelpToCP437(Const S:AnsiString):AnsiString;
Var
 I,Code:LongInt;
 C1,C2:Byte;
 R:RawByteString;
Begin
 R:='';I:=1;
 While I<=Length(S)do Begin
  Code:=0;
  If I<Length(S)Then Begin
   C1:=Ord(S[I]);C2:=Ord(S[I+1]);
   If C1=$C3 Then Case C2 Of
    $80:Code:=183; $82:Code:=182; $87:Code:=128; $88:Code:=212;
    $89:Code:=144; $8A:Code:=210; $8B:Code:=211; $8E:Code:=215;
    $8F:Code:=216; $94:Code:=226; $99:Code:=235; $9B:Code:=234;
    $9C:Code:=154; $A0:Code:=133; $A2:Code:=131; $A7:Code:=135;
    $A8:Code:=138; $A9:Code:=130; $AA:Code:=136; $AB:Code:=137;
    $AE:Code:=140; $AF:Code:=139; $B4:Code:=147; $B9:Code:=151;
    $BB:Code:=150; $BC:Code:=129;
   End
    Else If(C1=$C2)and(C2=$AB)Then Code:=174
    Else If(C1=$C2)and(C2=$BB)Then Code:=175;
   If Code<>0 Then Begin
    R:=R+Chr(Code);Inc(I,2);Continue;
   End;
  End;
  Case Ord(S[I])Of
   $80:Code:=128; $81:Code:=129; $82:Code:=130; $83:Code:=131;
   $84:Code:=132; $85:Code:=133; $87:Code:=135; $88:Code:=136;
   $89:Code:=137; $8A:Code:=138; $8B:Code:=139; $8C:Code:=140;
   $8E:Code:=142; $8F:Code:=143; $91:Code:=145; $92:Code:=146;
   $93:Code:=147; $94:Code:=148; $96:Code:=150; $97:Code:=151;
   $AB:Code:=174; $BB:Code:=175;
   $C0:Code:=183; $C2:Code:=182; $C7:Code:=128; $C8:Code:=212;
   $C9:Code:=144; $CA:Code:=210; $CB:Code:=211; $CE:Code:=215;
   $CF:Code:=216; $D4:Code:=226; $D9:Code:=235; $DB:Code:=234;
   $DC:Code:=154; $E0:Code:=133; $E2:Code:=131; $E7:Code:=135;
   $E8:Code:=138; $E9:Code:=130; $EA:Code:=136; $EB:Code:=137;
   $EE:Code:=140; $EF:Code:=139; $F4:Code:=147; $F9:Code:=151;
   $FB:Code:=150; $FC:Code:=129;
  Else Code:=0;
  End;
  If Code<>0 Then Begin R:=R+Chr(Code);Inc(I);Continue;End;
  R:=R+S[I];Inc(I);
 End;
 {$IFDEF FPC}
 SetCodePage(R,437,False);
 {$ENDIF}
 HelpToCP437:=R;
End;

Function OptToString(Const O:TOpt):AnsiString;
Var
 SS:AnsiString;
 I:LongInt;
 Tmp:AnsiString;
 Lines:TStrArray;
 Help:AnsiString;
Begin
 SS:='';
 For I:=0 to High(O.Names)do Begin
  If I=0 Then Begin
   If Length(O.Names)=1 Then SS:=SS+O.Names[0]
   Else Begin
    Tmp:=O.Names[0]+',';
    While Length(Tmp)<7 do Tmp:=Tmp+' ';
    SS:=SS+Tmp;
   End;
  End
   Else Begin
    SS:=SS+O.Names[I];
    If I<>High(O.Names)Then SS:=SS+', ';
   End;
 End;
 If O.Hint<>'' Then SS:=SS+' '+O.Hint;
 If O.Hint2<>'' Then SS:=SS+' '+O.Hint2;
 If Utf8Length(SS)>37 Then SS:=SS+#10+StrRepeat(' ',40)
 Else SS:=SS+StrRepeat(' ',40-Utf8Length(SS));
 Help:=ReplaceAll(O.Help,'@TEMPLATES@',ChatTemplateList);
 If O.Env<>'' Then Help:=Help+#10+'(env : '+O.Env+')';
 Lines:=BreakLines(Help,80);
 For I:=0 to High(Lines)do Begin
  If I>0 Then SS:=SS+StrRepeat(' ',40);
  SS:=SS+Lines[I]+#10;
 End;
 OptToString:=HelpToCP437(SS);
End;

Procedure PrintUsage;
Var
 Sec,I:LongInt;
 Titles:Array[0..2]of AnsiString;
Begin
 Titles[0]:='----- param'+#138+'tres communs -----';
 Titles[1]:='----- param'+#138+'tres d'''+#130+'chantillonnage -----';
 Titles[2]:='----- param'+#138+'tres sp'+#130+'cifiques '+#133+' llama-cli -----';
 WriteLn(HelpToCP437('LLAMA-CLI : Cette commande permet de lancer un chargement de mod'+#138+'le GGUF et de g'+#130+'n'+#130+'rer du texte ou de converser.'));
 WriteLn('Syntaxe: llama-cli [options]');
 WriteLn;
 WriteLn('exemple : llama-cli -m modele.gguf -p "Explique-moi la gravitation" -n 512');
 WriteLn;
 For Sec:=0 to 2 do Begin
  WriteLn(HelpToCP437(Titles[Sec]));
  WriteLn;
  For I:=0 to High(Opts)do
   If Opts[I].Sec=Sec Then Write(OptToString(Opts[I]));
  WriteLn;
 End;
End;

{ ------------------------------------------------------------------ }
{ Parametres                                                          }
{ ------------------------------------------------------------------ }

Type
 TParams=Record
  ModelPath,ModelUrl,HfRepo,HfFile,HfToken:AnsiString;
  Prompt,PromptFile,SysPrompt,SysFile:AnsiString;
  PromptSet:Boolean;
  NPredict,NCtx,NBatch,NUBatch,NKeep,NThreads,NPrint:LongInt;
  Samp:TSampParams;
  SamplerNames:AnsiString;
  Antiprompt:TStrArray;
  Interactive,InteractiveFirst:Boolean;
  ConvMode:LongInt;
  SingleTurn,Multiline,Special,VerbosePrompt,DisplayPrompt,CtxShift,Warmup,ShowTimings,Perf,Escape:Boolean;
  InPrefix,InSuffix:AnsiString;
  InPrefixBos:Boolean;
  ColorMode:LongInt;
  ChatTemplate,ChatTemplateFile,ChatKwargs:AnsiString;
  UseJinja:Boolean;
  Reasoning:LongInt;           { -1 off, 0 auto, 1 on }
  ReasoningBudget:LongInt;
  OutputFile:AnsiString;
  Rope:TRopeOpts;
  Overrides:Array of TOverride;
  Offline:Boolean;
  HelpReq,VersionReq,CacheListReq,ListDevicesReq:Boolean;
  BinaryPrompt:Boolean;
  RepeatLastNSet,DryLastNSet:Boolean;
 End;

Var
 Prm:TParams;
 DryBreakersDefault:Boolean=True;
 Prm_Ok:Boolean;

Procedure ParamsDefaults(Var P:TParams);
Begin
 FillChar(P.Rope,SizeOf(P.Rope),0);
 P.Rope.ScalingType:=-1;P.Rope.ExtFactor:=-1;P.Rope.AttnFactor:=-1;P.Rope.BetaFast:=-1;P.Rope.BetaSlow:=-1;
 P.ModelPath:='';P.ModelUrl:='';P.HfRepo:='';P.HfFile:='';P.HfToken:=GetEnv('HF_TOKEN');
 P.Prompt:='';P.PromptFile:='';P.SysPrompt:='';P.SysFile:='';P.PromptSet:=False;
 P.NPredict:=-1;P.NCtx:=0;P.NBatch:=2048;P.NUBatch:=512;P.NKeep:=0;P.NThreads:=-1;P.NPrint:=-1;
 SampDefaults(P.Samp);
 P.SamplerNames:='';
 SetLength(P.Antiprompt,0);
 P.Interactive:=False;P.InteractiveFirst:=False;P.ConvMode:=0;
 P.SingleTurn:=False;P.Multiline:=False;P.Special:=False;P.VerbosePrompt:=False;
 P.DisplayPrompt:=True;P.CtxShift:=False;P.Warmup:=True;P.ShowTimings:=True;P.Perf:=False;P.Escape:=True;
 P.InPrefix:='';P.InSuffix:='';P.InPrefixBos:=False;
 P.ColorMode:=0;
 P.ChatTemplate:='';P.ChatTemplateFile:='';P.ChatKwargs:='';
 P.UseJinja:=True;P.Reasoning:=0;P.ReasoningBudget:=-1;
 P.OutputFile:='';
 SetLength(P.Overrides,0);
 P.Offline:=False;
 P.HelpReq:=False;P.VersionReq:=False;P.CacheListReq:=False;P.ListDevicesReq:=False;
 P.BinaryPrompt:=False;P.RepeatLastNSet:=False;P.DryLastNSet:=False;
End;

Procedure ArgError(Const Msg:AnsiString);
Begin
 Write(StdErr,'erreur : ',Msg,#10);
 Write(StdErr,'(utilisez --help pour afficher la liste des options)'#10);
 Flush(StdErr);
 Halt(1);
End;

{ traitement des sequences d'echappement }
Function ProcessEscapes(Const S:AnsiString):AnsiString;
Var
 R:AnsiString;
 I:LongInt;
 C:Char;
Begin
 R:='';
 I:=1;
 While I<=Length(S)do Begin
  C:=S[I];
  If(C='\')and(I<Length(S))Then Begin
   Case S[I+1]of
    'n':Begin R:=R+#10;Inc(I,2);End;
    'r':Begin R:=R+#13;Inc(I,2);End;
    't':Begin R:=R+#9;Inc(I,2);End;
    '''':Begin R:=R+'''';Inc(I,2);End;
    '"':Begin R:=R+'"';Inc(I,2);End;
    '\':Begin R:=R+'\';Inc(I,2);End;
    'x':Begin
     If(I+3<=Length(S))and(HexVal(S[I+2])>=0)and(HexVal(S[I+3])>=0)Then Begin
      R:=R+Chr(HexVal(S[I+2])*16+HexVal(S[I+3]));
      Inc(I,4);
     End
      Else Begin R:=R+'\';Inc(I);End;
    End;
    Else Begin R:=R+'\';Inc(I);End;
   End;
  End
   Else Begin R:=R+C;Inc(I);End;
 End;
 ProcessEscapes:=R;
End;

Function ArgInt(Const Arg,V:AnsiString):Int64;
Var
 N:Int64;
Begin
 If not ParseInt(V,N)Then ArgError('valeur entière invalide pour '+Arg+' : '+V);
 ArgInt:=N;
End;

Function ArgFloat(Const Arg,V:AnsiString):Double;
Var
 D:Double;
 T:AnsiString;
Begin
 T:=ReplaceAll(V,',','.');
 If not ParseFloat(T,D)Then ArgError('valeur numérique invalide pour '+Arg+' : '+V);
 ArgFloat:=D;
End;

Function SamplerKindByName(Const N:AnsiString):LongInt;
Var
 L:AnsiString;
Begin
 L:=LoStr(N);
 SamplerKindByName:=0;
 If L='dry' Then SamplerKindByName:=SK_DRY
 Else If(L='top_k')or(L='top-k')or(L='topk')Then SamplerKindByName:=SK_TOPK
 Else If(L='top_p')or(L='top-p')or(L='topp')or(L='nucleus')Then SamplerKindByName:=SK_TOPP
 Else If(L='top_n_sigma')or(L='top-n-sigma')or(L='topnsigma')Then SamplerKindByName:=SK_TOPNSIGMA
 Else If(L='typ_p')or(L='typ-p')or(L='typp')or(L='typ')Then SamplerKindByName:=SK_TYPP
 Else If(L='min_p')or(L='min-p')or(L='minp')Then SamplerKindByName:=SK_MINP
 Else If(L='temperature')or(L='temp')Then SamplerKindByName:=SK_TEMP
 Else If L='xtc' Then SamplerKindByName:=SK_XTC
 Else If L='infill' Then SamplerKindByName:=SK_INFILL
 Else If L='penalties' Then SamplerKindByName:=SK_PENALTIES
 Else If(L='adaptive_p')or(L='adaptive-p')or(L='adaptivep')Then SamplerKindByName:=SK_ADAPTIVE;
End;

Function SamplerKindByChar(C:Char):LongInt;
Begin
 Case C of
  'd':SamplerKindByChar:=SK_DRY;
  'k':SamplerKindByChar:=SK_TOPK;
  'y':SamplerKindByChar:=SK_TYPP;
  'p':SamplerKindByChar:=SK_TOPP;
  's':SamplerKindByChar:=SK_TOPNSIGMA;
  'm':SamplerKindByChar:=SK_MINP;
  't':SamplerKindByChar:=SK_TEMP;
  'x':SamplerKindByChar:=SK_XTC;
  'i':SamplerKindByChar:=SK_INFILL;
  'e':SamplerKindByChar:=SK_PENALTIES;
  'a':SamplerKindByChar:=SK_ADAPTIVE;
  Else SamplerKindByChar:=0;
 End;
End;

Function ParseOnOffAuto(Const Arg,V:AnsiString):LongInt;
Var
 L:AnsiString;
Begin
 L:=LoStr(V);
 If(L='on')or(L='1')or(L='true')or(L='yes')or(L='enabled')Then ParseOnOffAuto:=1
 Else If(L='off')or(L='0')or(L='false')or(L='no')or(L='disabled')Then ParseOnOffAuto:=-1
 Else If L='auto' Then ParseOnOffAuto:=0
 Else Begin
  ArgError('valeur invalide pour '+Arg+' : '+V+' (attendu : on, off ou auto)');
  ParseOnOffAuto:=0;
 End;
End;

Procedure ReadFileOrDie(Const Name:AnsiString;Var Content:AnsiString);
Begin
 If not ReadWholeFile(Name,Content)Then Begin
  Write(StdErr,'erreur : impossible de lire le fichier ',Name,#10);
  Halt(1);
 End;
End;

Procedure ApplyOpt(Const Arg:AnsiString;Id:LongInt;Const V1,V2:AnsiString);
Var
 I,N:LongInt;
 S,T:AnsiString;
 Parts:TStrArray;
 Q:LongInt;
 Sg:Char;
 BI:LongInt;
 D:Double;
Begin
 Case Id of
  O_HELP:Prm.HelpReq:=True;
  O_VERSION:Prm.VersionReq:=True;
  O_CACHELIST:Prm.CacheListReq:=True;
  O_THREADS:Begin Prm.NThreads:=ArgInt(Arg,V1);End;
  O_THREADSB,O_CPUMASK,O_CPURANGE,O_CPUSTRICT,O_PRIO,O_POLL,O_CPUMASKB,O_CPURANGEB,O_CPUSTRICTB,
  O_PRIOB,O_POLLB,O_SWAFULL,O_FA,O_KVOFFLOAD,O_NOKVOFFLOAD,O_REPACK,O_NOREPACK,O_NOHOST,O_DEFRAG,
  O_LOADMODE,O_LAZYMODE,O_NUMA,O_DEVICE,O_OVERRIDETENSOR,O_CPUMOE,O_NCPUMOE,O_NCPUFFN,O_NGL,O_SM,O_TS,
  O_MG,O_FIT,O_FITT,O_FITC,O_CHECKTENSORS,O_OPOFFLOAD,O_NOOPOFFLOAD,O_BACKENDSAMPLING,O_CTXCP,O_CRAM,
  O_INFILE,O_LOGJSONL,O_NOLOGJSONL,O_LOGPREFIX,O_NOLOGPREFIX,O_LOGTS,O_NOLOGTS,O_SKIPCHATPARSING,
  O_NOSKIPCHATPARSING,O_REASONINGFMT,O_REASONINGEFFORT,O_REASONINGBUDGETMSG,O_REASONINGPRESERVE,
  O_NOREASONINGPRESERVE,O_LOGPROMPTSDIR,O_CVECRANGE:Begin
   { options acceptees mais sans effet dans ce clone }
  End;
  O_PARALLEL:Begin
   If ArgInt(Arg,V1)>1 Then LogWrn('avertissement : -np > 1 non supporté, une seule séquence est utilisée'+#10);
  End;
  O_RPC:LogWrn('avertissement : --rpc non supporté, ignoré'+#10);
  O_LISTDEVICES:Prm.ListDevicesReq:=True;
  O_CTK,O_CTV:Begin
   T:=LoStr(V1);
   If not((T='f32')or(T='f16')or(T='bf16')or(T='q8_0')or(T='q4_0')or(T='q4_1')or(T='iq4_nl')or(T='q5_0')or(T='q5_1'))Then
    ArgError('type de cache KV non supporté : '+V1);
   If(T<>'f32')and(T<>'f16')Then
    LogWrn('avertissement : le cache KV quantifié n''est pas supporté, f32 est utilisé'+#10);
  End;
  O_LORA,O_LORASCALED,O_CVEC,O_CVECSCALED:LogWrn('avertissement : '+Arg+' non supporté, ignoré'+#10);
  O_MMPROJ,O_MMPROJURL,O_IMAGE,O_MODELDRAFT,O_PROMPTCACHE,O_PROMPTCACHEALL,O_PROMPTCACHERO:
   LogWrn('avertissement : '+Arg+' non supporté, ignoré'+#10);
  O_NOMMPROJ:;
  O_SERVERBASE:ArgError('--server-base n''est pas supporté dans ce clone');
  O_DOCKER:ArgError('-dr / --docker-repo n''est pas supporté dans ce clone');
  O_CTX:Prm.NCtx:=ArgInt(Arg,V1);
  O_PREDICT:Prm.NPredict:=ArgInt(Arg,V1);
  O_BATCH:Prm.NBatch:=ArgInt(Arg,V1);
  O_UBATCH:Prm.NUBatch:=ArgInt(Arg,V1);
  O_KEEP:Prm.NKeep:=ArgInt(Arg,V1);
  O_PROMPT:Begin Prm.Prompt:=V1;Prm.PromptSet:=True;End;
  O_PERF:Prm.Perf:=True;
  O_NOPERF:Prm.Perf:=False;
  O_FILE:Begin
   ReadFileOrDie(V1,Prm.Prompt);
   If(Length(Prm.Prompt)>0)and(Prm.Prompt[Length(Prm.Prompt)]=#10)Then Delete(Prm.Prompt,Length(Prm.Prompt),1);
   Prm.PromptSet:=True;
  End;
  O_BINFILE:Begin ReadFileOrDie(V1,Prm.Prompt);Prm.BinaryPrompt:=True;Prm.PromptSet:=True;End;
  O_ESCAPE:Prm.Escape:=True;
  O_NOESCAPE:Prm.Escape:=False;
  O_ROPESCALING:Begin
   T:=LoStr(V1);
   If T='none' Then Prm.Rope.ScalingType:=RS_NONE
   Else If T='linear' Then Prm.Rope.ScalingType:=RS_LINEAR
   Else If T='yarn' Then Prm.Rope.ScalingType:=RS_YARN
   Else ArgError('--rope-scaling : valeur invalide '+V1+' (none, linear, yarn)');
  End;
  O_ROPESCALE:Begin D:=ArgFloat(Arg,V1);If D<>0 Then Prm.Rope.Scale:=1.0/D;End;
  O_ROPEBASE:Prm.Rope.Base:=ArgFloat(Arg,V1);
  O_ROPEFSCALE:Prm.Rope.Scale:=ArgFloat(Arg,V1);
  O_YARNORIG:Prm.Rope.OrigCtx:=ArgInt(Arg,V1);
  O_YARNEXT:Prm.Rope.ExtFactor:=ArgFloat(Arg,V1);
  O_YARNATTN:Prm.Rope.AttnFactor:=ArgFloat(Arg,V1);
  O_YARNSLOW:Prm.Rope.BetaSlow:=ArgFloat(Arg,V1);
  O_YARNFAST:Prm.Rope.BetaFast:=ArgFloat(Arg,V1);
  O_OVERRIDEKV:Begin
   Parts:=SplitStr(V1,',');
   For I:=0 to High(Parts)do Begin
    S:=Parts[I];
    If S='' Then Continue;
    Q:=Pos('=',S);
    If Q=0 Then ArgError('format invalide pour --override-kv : '+S);
    N:=Length(Prm.Overrides);
    SetLength(Prm.Overrides,N+1);
    Prm.Overrides[N].Key:=Copy(S,1,Q-1);
    T:=Copy(S,Q+1,Length(S));
    Q:=Pos(':',T);
    If Q=0 Then ArgError('format invalide pour --override-kv : '+S);
    Prm.Overrides[N].Typ:=LoStr(Copy(T,1,Q-1));
    Prm.Overrides[N].Val:=Copy(T,Q+1,Length(T));
    If not((Prm.Overrides[N].Typ='int')or(Prm.Overrides[N].Typ='float')or(Prm.Overrides[N].Typ='bool')or
           (Prm.Overrides[N].Typ='str'))Then ArgError('type invalide pour --override-kv : '+Prm.Overrides[N].Typ);
   End;
  End;
  O_MODEL:Prm.ModelPath:=V1;
  O_MODELURL:Prm.ModelUrl:=V1;
  O_HFREPO:Prm.HfRepo:=V1;
  O_HFFILE:Prm.HfFile:=V1;
  O_HFTOKEN:Prm.HfToken:=V1;
  O_LOGDISABLE:LogDisabled:=True;
  O_LOGFILE:Begin
   Assign(LogFile,V1);
   Rewrite(LogFile);
   If IOResult<>0 Then ArgError('impossible d''ouvrir le fichier de journal '+V1);
   LogFileOn:=True;
  End;
  O_LOGCOLORS:ParseOnOffAuto(Arg,V1);
  O_VERBOSE:LogLevel:=5;
  O_OFFLINE:Prm.Offline:=True;
  O_VERBOSITY:LogLevel:=ArgInt(Arg,V1);
  { --- echantillonnage --- }
  O_SAMPLERS:Begin
   SetLength(Prm.Samp.Order,0);
   Parts:=SplitStr(V1,';');
   For I:=0 to High(Parts)do Begin
    N:=SamplerKindByName(Parts[I]);
    If N=0 Then LogWrn('avertissement : échantillonneur inconnu : '+Parts[I]+#10)
    Else AddInt(Prm.Samp.Order,N);
   End;
  End;
  O_SEED:Begin
   N:=ArgInt(Arg,V1);
   If N<0 Then Prm.Samp.Seed:=DefaultSeed Else Prm.Samp.Seed:=LongWord(N);
  End;
  O_SAMPLERSEQ:Begin
   SetLength(Prm.Samp.Order,0);
   For I:=1 to Length(V1)do Begin
    N:=SamplerKindByChar(V1[I]);
    If N=0 Then LogWrn('avertissement : lettre d''échantillonneur inconnue : '+V1[I]+#10)
    Else AddInt(Prm.Samp.Order,N);
   End;
  End;
  O_IGNOREEOS:Prm.Samp.IgnoreEos:=True;
  O_TEMP:Begin Prm.Samp.Temp:=ArgFloat(Arg,V1);If Prm.Samp.Temp<0 Then Prm.Samp.Temp:=0;End;
  O_TOPK:Prm.Samp.TopK:=ArgInt(Arg,V1);
  O_TOPP:Prm.Samp.TopP:=ArgFloat(Arg,V1);
  O_MINP:Prm.Samp.MinP:=ArgFloat(Arg,V1);
  O_TOPNSIGMA:Prm.Samp.TopNSigma:=ArgFloat(Arg,V1);
  O_XTCP:Prm.Samp.XtcP:=ArgFloat(Arg,V1);
  O_XTCT:Prm.Samp.XtcT:=ArgFloat(Arg,V1);
  O_TYPICAL:Prm.Samp.TypP:=ArgFloat(Arg,V1);
  O_REPEATLASTN:Begin
   Prm.Samp.PenaltyLastN:=ArgInt(Arg,V1);
   If Prm.Samp.PenaltyLastN<-1 Then ArgError('--repeat-last-n doit être >= -1');
   Prm.RepeatLastNSet:=True;
  End;
  O_REPEATPEN:Prm.Samp.PenaltyRepeat:=ArgFloat(Arg,V1);
  O_PRESENCEPEN:Prm.Samp.PenaltyPresent:=ArgFloat(Arg,V1);
  O_FREQPEN:Prm.Samp.PenaltyFreq:=ArgFloat(Arg,V1);
  O_DRYMULT:Prm.Samp.DryMult:=ArgFloat(Arg,V1);
  O_DRYBASE:Begin
   Prm.Samp.DryBase:=ArgFloat(Arg,V1);
   If Prm.Samp.DryBase<1.0 Then Prm.Samp.DryBase:=1.75;
  End;
  O_DRYALLOWED:Prm.Samp.DryAllowed:=ArgInt(Arg,V1);
  O_DRYLASTN:Begin Prm.Samp.DryLastN:=ArgInt(Arg,V1);Prm.DryLastNSet:=True;End;
  O_DRYBREAK:Begin
   If DryBreakersDefault Then Begin SetLength(Prm.Samp.DryBreakers,0);DryBreakersDefault:=False;End;
   If LoStr(V1)<>'none' Then AddStr(Prm.Samp.DryBreakers,V1);
  End;
  O_ADAPTTARGET:Prm.Samp.AdaptiveTarget:=ArgFloat(Arg,V1);
  O_ADAPTDECAY:Prm.Samp.AdaptiveDecay:=ArgFloat(Arg,V1);
  O_DYNRANGE:Prm.Samp.DynRange:=ArgFloat(Arg,V1);
  O_DYNEXP:Prm.Samp.DynExp:=ArgFloat(Arg,V1);
  O_MIROSTAT:Prm.Samp.Mirostat:=ArgInt(Arg,V1);
  O_MIROLR:Prm.Samp.MiroEta:=ArgFloat(Arg,V1);
  O_MIROENT:Prm.Samp.MiroTau:=ArgFloat(Arg,V1);
  O_LOGITBIAS:Begin
   Q:=1;
   While(Q<=Length(V1))and(V1[Q]in['0'..'9'])do Inc(Q);
   If(Q>1)and(Q<=Length(V1))and(V1[Q]in['+','-'])Then Begin
    Sg:=V1[Q];
    N:=Length(Prm.Samp.Bias);
    SetLength(Prm.Samp.Bias,N+1);
    Prm.Samp.Bias[N].Tok:=ArgInt(Arg,Copy(V1,1,Q-1));
    D:=ArgFloat(Arg,Copy(V1,Q+1,Length(V1)));
    If Sg='-' Then D:=-D;
    Prm.Samp.Bias[N].Bias:=D;
   End
    Else ArgError('format invalide pour --logit-bias : '+V1+' (attendu : JETON_ID(+/-)BIAIS)');
  End;
  O_GRAMMAR:Prm.Samp.Grammar:=V1;
  O_GRAMMARFILE:ReadFileOrDie(V1,Prm.Samp.Grammar);
  O_JSONSCHEMA,O_JSONSCHEMAFILE:Begin
   If Id=O_JSONSCHEMAFILE Then ReadFileOrDie(V1,S)Else S:=V1;
   Prm.Samp.Grammar:=JsonSchemaToGrammar(S,Prm_Ok,T);
   If not Prm_Ok Then ArgError('conversion du schéma JSON impossible : '+T);
  End;
  { --- options specifiques --- }
  O_VERBOSEPROMPT:Prm.VerbosePrompt:=True;
  O_DISPLAYPROMPT:Prm.DisplayPrompt:=True;
  O_NODISPLAYPROMPT:Prm.DisplayPrompt:=False;
  O_COLOR:Prm.ColorMode:=ParseOnOffAuto(Arg,V1);
  O_CONTEXTSHIFT:Prm.CtxShift:=True;
  O_NOCONTEXTSHIFT:Prm.CtxShift:=False;
  O_SYSPROMPT:Prm.SysPrompt:=V1;
  O_SHOWTIMINGS:Prm.ShowTimings:=True;
  O_NOSHOWTIMINGS:Prm.ShowTimings:=False;
  O_SYSFILE:Begin
   ReadFileOrDie(V1,Prm.SysPrompt);
   While(Length(Prm.SysPrompt)>0)and(Prm.SysPrompt[Length(Prm.SysPrompt)]in[#10,#13])do
    Delete(Prm.SysPrompt,Length(Prm.SysPrompt),1);
  End;
  O_PTC:Prm.NPrint:=ArgInt(Arg,V1);
  O_REVERSE:AddStr(Prm.Antiprompt,V1);
  O_SPECIAL:Prm.Special:=True;
  O_CNV:Prm.ConvMode:=1;
  O_NOCNV:Prm.ConvMode:=-1;
  O_SINGLETURN:Prm.SingleTurn:=True;
  O_INTERACTIVE:Prm.Interactive:=True;
  O_INTERACTIVEFIRST:Prm.InteractiveFirst:=True;
  O_MULTILINE:Prm.Multiline:=True;
  O_INPREFIXBOS:Prm.InPrefixBos:=True;
  O_INPREFIX:Prm.InPrefix:=V1;
  O_INSUFFIX:Prm.InSuffix:=V1;
  O_WARMUP:Prm.Warmup:=True;
  O_NOWARMUP:Prm.Warmup:=False;
  O_OUTPUT:Prm.OutputFile:=V1;
  O_CHATKWARGS:Prm.ChatKwargs:=V1;
  O_JINJA:Prm.UseJinja:=True;
  O_NOJINJA:Prm.UseJinja:=False;
  O_REASONING:Prm.Reasoning:=ParseOnOffAuto(Arg,V1);
  O_REASONINGBUDGET:Prm.ReasoningBudget:=ArgInt(Arg,V1);
  O_CHATTEMPLATE:Prm.ChatTemplate:=V1;
  O_CHATTEMPLATEFILE:ReadFileOrDie(V1,Prm.ChatTemplate);
  O_SIMPLEIO:SimpleIO:=True;
 Else ArgError('option non gérée : '+Arg);
 End;
End;

Function OptTakesValue(Const O:TOpt):LongInt;
Begin
 If O.Hint2<>'' Then OptTakesValue:=2
 Else If O.Hint<>'' Then OptTakesValue:=1
 Else OptTakesValue:=0;
End;

Procedure ParseCommandLine;
Var
 I,K,Oi,NV:LongInt;
 A,V1,V2,E:AnsiString;
 Skip:Boolean;
Begin
 { variables d'environnement }
 For K:=0 to High(Opts)do Begin
  If Opts[K].Env='' Then Continue;
  E:=GetEnv(Opts[K].Env);
  If E='' Then Continue;
  If OptTakesValue(Opts[K])>0 Then ApplyOpt(Opts[K].Names[0],Opts[K].Id,E,'')
  Else If(E<>'0')and(LoStr(E)<>'false')Then ApplyOpt(Opts[K].Names[0],Opts[K].Id,'','');
 End;
 I:=1;
 While I<=ParamCount do Begin
  A:=ParamStr(I);
  Oi:=FindOpt(A);
  If Oi<0 Then Begin
   { forme --option=valeur }
   K:=Pos('=',A);
   If(Copy(A,1,2)='--')and(K>0)Then Begin
    Oi:=FindOpt(Copy(A,1,K-1));
    If Oi>=0 Then Begin
     V1:=Copy(A,K+1,Length(A));
     ApplyOpt(Copy(A,1,K-1),Opts[Oi].Id,V1,'');
     Inc(I);
     Continue;
    End;
   End;
   ArgError('argument invalide : '+A);
  End;
  NV:=OptTakesValue(Opts[Oi]);
  V1:='';V2:='';
  If NV>=1 Then Begin
   If(I+1>ParamCount)Then Begin
    If Opts[Oi].Id=O_COLOR Then Begin V1:='on';NV:=0;End
    Else ArgError('l''argument '+A+' attend une valeur');
   End
    Else Begin
     V1:=ParamStr(I+1);
     If(Opts[Oi].Id=O_COLOR)and(LoStr(V1)<>'on')and(LoStr(V1)<>'off')and(LoStr(V1)<>'auto')Then Begin
      V1:='on';NV:=0;
     End;
    End;
  End;
  If(NV>=2)Then Begin
   If I+2>ParamCount Then ArgError('l''argument '+A+' attend deux valeurs');
   V2:=ParamStr(I+2);
  End;
  ApplyOpt(A,Opts[Oi].Id,V1,V2);
  Inc(I,1+NV);
 End;
End;

{ ------------------------------------------------------------------ }
{ Programme principal                                                 }
{ ------------------------------------------------------------------ }

Const
 ColYellow=#27'[33m';
 ColBoldGreen=#27'[1m'#27'[32m';
 ColReset=#27'[0m';
 ColRed=#27'[31m';
 DT_PROMPT=0; DT_USER=1; DT_RESET=2; DT_ERROR=3;

Var
 Mdl:TModel;
 Cx:TCtx;
 Smp:TSampler;
 TplName:AnsiString;
 TplSource:AnsiString;
 HasTemplate:Boolean;
 ChatMsgs:TChatMsgs;
 UseColorOut:Boolean;
 TLoadMs,TPEvalMs,TEvalMs,TSampMs,TStartMs:Double;
 NPEval,NEvalRuns,NSampled:LongInt;
 OutFileOn:Boolean;
 OutFile:Text;
 UBatchSize:LongInt;

Procedure SetDisplay(T:LongInt);
Begin
 If not UseColorOut Then Exit;
 Case T of
  DT_PROMPT:Write(ColYellow);
  DT_USER:Write(ColBoldGreen);
  DT_RESET:Write(ColReset);
  DT_ERROR:Write(ColRed);
 End;
End;

Procedure ClearIO;
Begin
 If IOResult<>0 Then;
End;

Function PerfPerTok(T:Double;N:LongInt):Double;
Begin
 If N=0 Then PerfPerTok:=0 Else PerfPerTok:=T/N;
End;

Function PerfTps(T:Double;N:LongInt):Double;
Begin
 If T=0 Then PerfTps:=0 Else PerfTps:=1000.0/T*N;
End;

Procedure PrintPerf;
Var
 TTotal,TUnacc:Double;
Begin
 TTotal:=NowMsF-TStartMs;
 TUnacc:=TTotal-(TSampMs+TPEvalMs+TEvalMs);
 LogInf('common_perf_print:    sampling time = '+FStrW(TSampMs,10,2)+' ms'+#10);
 LogInf('common_perf_print:    samplers time = '+FStrW(TSampMs,10,2)+' ms / '+PadLeft(IStr(NSampled),5)+' tokens'+#10);
 LogInf('common_perf_print:        load time = '+FStrW(TLoadMs,10,2)+' ms'+#10);
 LogInf('common_perf_print: prompt eval time = '+FStrW(TPEvalMs,10,2)+' ms / '+PadLeft(IStr(NPEval),5)+' tokens ('+
        FStrW(PerfPerTok(TPEvalMs,NPEval),8,2)+' ms per token, '+FStrW(PerfTps(TPEvalMs,NPEval),8,2)+' tokens per second)'+#10);
 LogInf('common_perf_print:        eval time = '+FStrW(TEvalMs,10,2)+' ms / '+PadLeft(IStr(NEvalRuns),5)+' runs   ('+
        FStrW(PerfPerTok(TEvalMs,NEvalRuns),8,2)+' ms per token, '+FStrW(PerfTps(TEvalMs,NEvalRuns),8,2)+' tokens per second)'+#10);
 LogInf('common_perf_print:       total time = '+FStrW(TTotal,10,2)+' ms / '+PadLeft(IStr(NPEval+NEvalRuns),5)+' tokens'+#10);
 If TTotal>0 Then
  LogInf('common_perf_print: unaccounted time = '+FStrW(TUnacc,10,2)+' ms / '+FStrW(100.0*TUnacc/TTotal,5,1)+
         ' %      (total - sampling - prompt eval - eval) / (total)'+#10);
End;

{ ---- conversation : formatage des messages ---- }

Function RenderChat(Const Msgs:TChatMsgs;AddAss:Boolean):AnsiString;
Var
 R:AnsiString;
Begin
 R:='';
 If not ChatTemplateApply(TplName,Msgs,AddAss,R)Then R:='';
 RenderChat:=R;
End;

{ equivalent de common_chat_format_single + ajout du message a l'historique }
Function ChatAddAndFormat(Const Role,Content:AnsiString):AnsiString;
Var
 Past,All:TChatMsgs;
 FmtPast,Full,SS:AnsiString;
 N:LongInt;
 AddAss:Boolean;
Begin
 AddAss:=Role='user';
 Past:=Copy(ChatMsgs,0,Length(ChatMsgs));
 FmtPast:='';
 If Length(Past)>0 Then FmtPast:=RenderChat(Past,False);
 N:=Length(ChatMsgs);
 SetLength(ChatMsgs,N+1);
 ChatMsgs[N].Role:=Role;ChatMsgs[N].Content:=Content;
 Full:=RenderChat(ChatMsgs,AddAss);
 SS:='';
 If AddAss and(FmtPast<>'')and(FmtPast[Length(FmtPast)]=#10)Then SS:=#10;
 SS:=SS+Copy(Full,Length(FmtPast)+1,Length(Full));
 ChatAddAndFormat:=SS;
End;

Function TokenizeText(Const Text:AnsiString;AddSpecial,ParseSpecial:Boolean):TIntArray;
Var
 Sp:Boolean;
Begin
 Sp:=AddSpecial;
 { si le texte commence deja par BOS (modele de conversation), on ne le rajoute pas }
 If Sp and(Mdl.V.BOS>=0)and(Mdl.V.Text[Mdl.V.BOS]<>'')and StartsWith(Text,Mdl.V.Text[Mdl.V.BOS])Then Sp:=False;
 TokenizeText:=VocabTokenize(Mdl.V,Text,Sp,ParseSpecial);
End;

Function Piece(Tok:LongInt;Special:Boolean):AnsiString;
Begin
 Piece:=TokenToPiece(Mdl.V,Tok,Special,0);
End;

Procedure AppendInts(Var A:TIntArray;Const B:TIntArray);
Var
 N,I:LongInt;
Begin
 N:=Length(A);
 SetLength(A,N+Length(B));
 For I:=0 to High(B)do A[N+I]:=B[I];
End;

{ lecture d'une ligne de saisie : renvoie True s'il faut continuer (autre ligne) }
Function ReadInputLine(Var Line:AnsiString;MultilineInput:Boolean):Boolean;
Var
 S:AnsiString;
 Last:Char;
Begin
 ClearIO;
 If Eof(Input)Then Begin
  Line:='';
  ReadInputLine:=False;
  ClearIO;
  Exit;
 End;
 ReadLn(S);
 ClearIO;
 If(Length(S)>0)and(S[Length(S)]=#13)Then Delete(S,Length(S),1);
 If Length(S)>0 Then Begin
  Last:=S[Length(S)];
  If Last='/' Then Begin
   S[Length(S)]:=#10;
   Line:=S;
   ReadInputLine:=False;
   Exit;
  End;
  If Last='\' Then Begin
   Delete(S,Length(S),1);
   MultilineInput:=not MultilineInput;
  End;
 End;
 Line:=S+#10;
 ReadInputLine:=MultilineInput;
End;

Function ReadUserInput(Var Buffer:AnsiString):Boolean;
Var
 Line:AnsiString;
 More,GotAny:Boolean;
Begin
 Buffer:='';
 GotAny:=False;
 Repeat
  More:=ReadInputLine(Line,Prm.Multiline);
  If Line<>'' Then GotAny:=True;
  Buffer:=Buffer+Line;
 Until not More;
 ReadUserInput:=GotAny;
End;

Procedure WriteOutFile(Const S:AnsiString);
Begin
 If OutFileOn Then Begin
  Write(OutFile,S);
  Flush(OutFile);
  ClearIO;
 End;
End;

Procedure PrintVersion;
Var
 Os_,Cpu:AnsiString;
Begin
 {$IFDEF WINDOWS}Os_:='Windows';{$ELSE}{$IFDEF LINUX}Os_:='Linux';{$ELSE}{$IFDEF DARWIN}Os_:='macOS';{$ELSE}Os_:='DOS/autre';{$ENDIF}{$ENDIF}{$ENDIF}
 {$IFDEF CPUX86_64}Cpu:='x86_64';{$ELSE}{$IFDEF CPUI386}Cpu:='i386';{$ELSE}{$IFDEF CPUAARCH64}Cpu:='aarch64';{$ELSE}Cpu:='?';{$ENDIF}{$ENDIF}{$ENDIF}
 WriteLn('version: ',BuildNumber,' (clone Pascal de llama.cpp)');
 WriteLn('built with Free Pascal ',IStr(FPC_VERSION),'.',IStr(FPC_RELEASE),'.',IStr(FPC_PATCH),' for ',Os_,' ',Cpu);
End;

Function OverlapAntiprompt(Const Last,Anti:AnsiString;Interactive:Boolean):Boolean;
Var
 Extra,Start:LongInt;
Begin
 If Interactive Then Extra:=0 Else Extra:=2;
 If Length(Last)>Length(Anti)+Extra Then Start:=Length(Last)-(Length(Anti)+Extra)+1 Else Start:=1;
 OverlapAntiprompt:=PosFrom(Anti,Last,Start)>0;
End;

Procedure RunMain;
Var
 ModelFile:AnsiString;
 NCtx,NCtxTrain,I,J,K:LongInt;
 KvMax:Double;
 SysText,PromptText:AnsiString;
 EmbdInp,Embd,Tmp,Toks:TIntArray;
 NConsumed,NRemain,NKeep,MaxEmbd,NLeft,NDiscard:LongInt;
 IsInteracting,IsAntiprompt,InputEcho,Display,WaitingFirst,ConvMode,EnableChatTemplate:Boolean;
 AddBos:Boolean;
 Prompt:AnsiString;
 AssistantSS:AnsiString;
 Hist:TIntArray;
 Id:LongInt;
 T0:Double;
 LastOut,Buffer,UserInp,Anti,TokStr:AnsiString;
 FormatChat:Boolean;
 LineIn,LinePfx,LineSfx:TIntArray;
 OrigSize:LongInt;
 AntiTok:TIntArray;
 PL:TIntArray;
 N:LongInt;
 SampParams:TSampParams;
 HaveLogits:Boolean;
 Chunk:LongInt;
 ChatMsg:AnsiString;
 NPredictLeft:LongInt;
 SchemaOk:Boolean;
 Failed:Boolean;
 Ev:LongInt;
 PendingBos:Boolean;
 GenStart:Int64;
Begin
 { --- resolution du modele --- }
 ModelFile:=Prm.ModelPath;
 If(ModelFile='')and(Prm.ModelUrl<>'')Then Begin
  If not ResolveModelUrl(Prm.ModelUrl,Prm.HfToken,Prm.Offline,ModelFile)Then Halt(1);
 End
  Else If(ModelFile='')and(Prm.HfRepo<>'')Then Begin
   If not ResolveModelHF(Prm.HfRepo,Prm.HfFile,Prm.HfToken,Prm.Offline,ModelFile)Then Halt(1);
  End;
 If ModelFile='' Then Begin
  LogErr('erreur : aucun modèle spécifié'+#10);
  LogErr('         utilisez -m <fichier.gguf> pour un modèle local, ou -hf <utilisateur>/<modèle> (Windows)'+#10);
  Halt(1);
 End;
 SetLength(KVOverrides,Length(Prm.Overrides));
 For I:=0 to High(Prm.Overrides)do KVOverrides[I]:=Prm.Overrides[I];
 { --- chargement --- }
 LogOut(4,'llama_model_load: chargement du modèle '+ModelFile+#10);
 T0:=NowMsF;
 LoadModel(ModelFile,Mdl,LogLevel>=4);
 NCtxTrain:=Mdl.NCtxTrain;
 { --- taille du contexte --- }
 NCtx:=Prm.NCtx;
 If NCtx=0 Then Begin
  NCtx:=NCtxTrain;
  If NCtx<=0 Then NCtx:=4096;
  If SizeOf(Pointer)<8 Then KvMax:=536870912.0 Else KvMax:=2147483648.0;
  If KVBytesFor(Mdl,NCtx)>KvMax Then Begin
   K:=NCtx;
   NCtx:=Trunc(KvMax/(KVBytesFor(Mdl,1)));
   NCtx:=(NCtx div 256)*256;
   If NCtx<2048 Then NCtx:=2048;
   If NCtx>K Then NCtx:=K;
   LogWrn('avertissement : taille du contexte r'+#130+'duite '+#133+' '+IStr(NCtx)+' (mod'+#138+
          'le entra'+#140+'n'+#130+' pour '+IStr(K)+
          ') pour limiter la m'+#130+'moire du cache KV ; utilisez -c pour la modifier'+#10);
  End;
 End;
 If NCtx<8 Then Begin
  LogWrn('avertissement : la taille minimale du contexte est 8, utilisation du minimum'+#10);
  NCtx:=8;
 End;
 If Prm.Rope.Base<>0 Then LogWrn('avertissement : changement de la base de fr'+#130+'quence RoPE '+#133+' '+FStr(Prm.Rope.Base,1)+#10);
 If Prm.Rope.Scale<>0 Then LogWrn('avertissement : mise '+#133+' l'''+#130+'chelle de la fr'+#130+
                                  'quence RoPE de '+FStr(Prm.Rope.Scale,4)+#10);
 If(Prm.NBatch<=0)Then Prm.NBatch:=2048;
 If(Prm.NUBatch<=0)Then Prm.NUBatch:=512;
 UBatchSize:=Prm.NUBatch;
 If UBatchSize>Prm.NBatch Then UBatchSize:=Prm.NBatch;
 If UBatchSize>NCtx Then UBatchSize:=NCtx;
 If UBatchSize<1 Then UBatchSize:=1;
 GNThreads:=Prm.NThreads;
 CtxInit(Mdl,Cx,NCtx,UBatchSize,Prm.Rope);
 LogOut(4,'llama_context: n_ctx = '+IStr(NCtx)+', n_batch = '+IStr(Prm.NBatch)+', n_ubatch = '+IStr(UBatchSize)+#10);
 LogOut(4,'llama_kv_cache: taille = '+HumanBytes(Cx.KVBytes)+#10);
 TLoadMs:=NowMsF-T0;
 TStartMs:=NowMsF;
 If NCtx>NCtxTrain Then
  LogWrn('avertissement : le mod'+#138+'le a '+#130+'t'+#130+' entra'+#140+'n'+#130+
               ' pour '+IStr(NCtxTrain)+' jetons de contexte seulement ('+IStr(NCtx)+' demand'+#130+'s)'+#10);
 { --- echantillonneur --- }
 SampParams:=Prm.Samp;
 If SampParams.PenaltyLastN<0 Then SampParams.PenaltyLastN:=NCtx;
 If SampParams.DryLastN<0 Then SampParams.DryLastN:=NCtx;
 If SampParams.IgnoreEos Then Begin
  For I:=0 to Mdl.V.NTokens-1 do
   If Mdl.V.EOG[I]Then Begin
    N:=Length(SampParams.Bias);
    SetLength(SampParams.Bias,N+1);
    SampParams.Bias[N].Tok:=I;
    SampParams.Bias[N].Bias:=NegInf;
   End;
 End;
 If not SamplerInit(Smp,Mdl.V,SampParams,Mdl.NVocab)Then Halt(1);
 LogOut(4,'sampler seed: '+IStr(Smp.SeedCur)+#10);
 { --- couleurs --- }
 UseColorOut:=(Prm.ColorMode=1)or((Prm.ColorMode=0)and StdoutIsTerminal);
 { --- modele de conversation --- }
 TplSource:='';
 If Prm.ChatTemplate<>'' Then TplSource:=Prm.ChatTemplate Else TplSource:=Mdl.V.ChatTemplate;
 HasTemplate:=TplSource<>'';
 TplName:='chatml';
 If HasTemplate Then Begin
  TplName:=ChatTemplateDetect(TplSource);
  If TplName='' Then Begin
   If Prm.ChatTemplate<>'' Then Begin
    LogErr('erreur : le mod'+#138+'le de conversation fourni n''est pas support'+#130+' ; mod'+#138+
            'les int'+#130+'gr'+#130+'s : '+ChatTemplateList+#10);
    Halt(1);
   End;
   LogWrn('avertissement : mod'+#138+'le de conversation du fichier non reconnu, utilisation de « chatml »'+#10);
   TplName:='chatml';
  End;
 End;
 EnableChatTemplate:=(Prm.InPrefix='')and(Prm.InSuffix='');
 { --- mode conversation --- }
 ConvMode:=False;
 If Prm.ConvMode=1 Then ConvMode:=True
 Else If Prm.ConvMode=0 Then ConvMode:=HasTemplate;
 If ConvMode and not HasTemplate Then
  LogWrn('avertissement : aucun mod'+#138+'le de conversation disponible ; utilisation de « chatml » ; les r'+
         #130+'ponses peuvent '+#136+'tre de moindre qualit'+#130++#10);
 If ConvMode and(Prm.ConvMode=0)Then
  LogOut(4,'main : un mod'+#138+'le de conversation est disponible, le mode conversation est activ'+#130' (d'+#130+'sactivable avec -no-cnv)'+#10);
 AddBos:=Mdl.V.AddBOS;
 { --- warmup --- }
 If Prm.Warmup Then Begin
  SetLength(Tmp,1);
  If Mdl.V.BOS>=0 Then Tmp[0]:=Mdl.V.BOS Else Tmp[0]:=0;
  Decode(Mdl,Cx,@Tmp[0],1,0);
  CtxClear(Cx);
  TStartMs:=NowMsF;
 End;
 { --- prompt initial --- }
 If Prm.Prompt<>'' Then Begin
  If Prm.Escape and not Prm.BinaryPrompt Then Prompt:=ProcessEscapes(Prm.Prompt)Else Prompt:=Prm.Prompt;
 End
  Else Prompt:='';
 If(Prm.SysPrompt<>'')and Prm.Escape Then SysText:=ProcessEscapes(Prm.SysPrompt)Else SysText:=Prm.SysPrompt;
 SetLength(ChatMsgs,0);
 WaitingFirst:=False;
 PromptText:='';
 If ConvMode and EnableChatTemplate Then Begin
  If SysText<>'' Then ChatAddAndFormat('system',SysText);
  If Prompt<>'' Then ChatAddAndFormat('user',Prompt)
  Else WaitingFirst:=True;
  If(SysText<>'')or(Prompt<>'')Then
   PromptText:=RenderChat(ChatMsgs,Prompt<>'');
  If(Prompt<>'')and(SysText='')Then LogOut(4,'main : le prompt utilisateur d'+#130+'marre la conversation'+#10);
 End
  Else PromptText:=Prompt;
 If Prm.InteractiveFirst or(PromptText<>'')Then EmbdInp:=TokenizeText(PromptText,True,True)
 Else SetLength(EmbdInp,0);
 If(not WaitingFirst)and(Length(EmbdInp)=0)Then Begin
  If AddBos and(Mdl.V.BOS>=0)Then Begin
   SetLength(EmbdInp,1);EmbdInp[0]:=Mdl.V.BOS;
   LogWrn('avertissement : le prompt était vide, BOS ajouté'+#10);
  End
   Else Begin
    LogErr('erreur : l''entrée est vide'+#10);
    Halt(1);
   End;
 End;
 If Length(EmbdInp)>NCtx-4 Then Begin
  LogErr('erreur : le prompt est trop long ('+IStr(Length(EmbdInp))+' jetons, maximum '+IStr(NCtx-4)+')'+#10);
  Halt(1);
 End;
 NKeep:=Prm.NKeep;
 If(NKeep<0)or(NKeep>Length(EmbdInp))Then NKeep:=Length(EmbdInp)
 Else NKeep:=NKeep+Ord(AddBos);
 If ConvMode Then Begin
  If Prm.SingleTurn and(Prompt<>'')Then Begin
   Prm.Interactive:=False;Prm.InteractiveFirst:=False;
  End
   Else Prm.InteractiveFirst:=True;
 End;
 If Prm.InteractiveFirst Then Prm.Interactive:=True;
 If Prm.VerbosePrompt Then Begin
  LogInf('main : prompt : '''+Prompt+''''+#10);
  LogInf('main : nombre de jetons dans le prompt = '+IStr(Length(EmbdInp))+#10);
  For I:=0 to High(EmbdInp)do LogInf(PadLeft(IStr(EmbdInp[I]),6)+' -> '''+Piece(EmbdInp[I],True)+''''+#10);
  LogInf(#10);
 End;
 If Prm.Interactive Then Begin
  LogOut(4,'main : mode interactif activé.'+#10);
  For I:=0 to High(Prm.Antiprompt)do LogInf('Invite inverse : '''+Prm.Antiprompt[I]+''''+#10);
  If Prm.InPrefixBos Then LogInf('Pr'+#130+'fixe de saisie avec BOS'+#10);
  If Prm.InPrefix<>'' Then LogInf('Pr'+#130+'fixe de saisie : '''+Prm.InPrefix+''''+#10);
  If Prm.InSuffix<>'' Then LogInf('Suffixe de saisie : '''+Prm.InSuffix+''''+#10);
 End;
 LogOut(4,'generate: n_ctx = '+IStr(NCtx)+', n_batch = '+IStr(Prm.NBatch)+', n_predict = '+IStr(Prm.NPredict)+
        ', n_keep = '+IStr(NKeep)+#10);
 If Prm.Interactive Then Begin
  LogInf('== Mode interactif. =='+#10);
  If Prm.Multiline Then Begin
   LogInf(' - Pour rendre la main à l''IA, terminez votre saisie par « \ ».'+#10);
   LogInf(' - Pour rendre la main sans commencer une nouvelle ligne, terminez votre saisie par « / ».'+#10);
  End
   Else Begin
    LogInf(' - Appuyez sur Entrée pour rendre la main à l''IA.'+#10);
    LogInf(' - Pour rendre la main sans commencer une nouvelle ligne, terminez votre saisie par « / ».'+#10);
    LogInf(' - Pour saisir une autre ligne, terminez la ligne par « \ ».'+#10);
   End;
  If ConvMode and EnableChatTemplate and(SysText='')Then
   LogInf(' - Aucun message système. Pour en définir un, utilisez -sys PROMPT'+#10);
  LogInf(#10);
  IsInteracting:=Prm.InteractiveFirst;
 End
  Else IsInteracting:=False;
 If Prm.OutputFile<>'' Then Begin
  Assign(OutFile,Prm.OutputFile);
  Rewrite(OutFile);
  If IOResult<>0 Then Begin
   LogErr('erreur : impossible d''ouvrir le fichier de sortie '+Prm.OutputFile+#10);
   Halt(1);
  End;
  OutFileOn:=True;
 End;
 { jetons d'invite inverse a un seul jeton }
 SetLength(AntiTok,0);
 For I:=0 to High(Prm.Antiprompt)do Begin
  PL:=VocabTokenize(Mdl.V,Prm.Antiprompt[I],False,True);
  If Length(PL)=1 Then AddInt(AntiTok,PL[0]);
 End;
 IsAntiprompt:=False;
 InputEcho:=True;
 NRemain:=Prm.NPredict;
 NConsumed:=0;
 SetLength(Embd,0);
 SetLength(Hist,0);
 AssistantSS:='';
 SetDisplay(DT_PROMPT);
 Display:=Prm.DisplayPrompt;
 HaveLogits:=False;
 MaxEmbd:=NCtx-4;
 Failed:=False;
 { ---------- boucle principale (portage de completion.cpp) ---------- }
 While((NRemain<>0)and not IsAntiprompt)or Prm.Interactive do Begin
  { predict }
  If Length(Embd)>0 Then Begin
   If Length(Embd)>MaxEmbd Then Begin
    N:=Length(Embd)-MaxEmbd;
    SetLength(Embd,MaxEmbd);
    SetDisplay(DT_ERROR);
    LogWrn('<<entrée trop longue : '+IStr(N)+' jeton(s) ignoré(s)>>');
    SetDisplay(DT_RESET);
   End;
   If Cx.NPast+Length(Embd)>=NCtx Then Begin
    If not Prm.CtxShift Then Begin
     LogWrn(#10#10'main : contexte plein et décalage du contexte désactivé => arrêt'+#10);
     Break;
    End;
    If Prm.NPredict=-2 Then Begin
     LogWrn(#10#10'main : contexte plein et n_predict == -2 => arrêt'+#10);
     Break;
    End;
    NLeft:=Cx.NPast-NKeep;
    NDiscard:=NLeft div 2;
    LogDbg('contexte plein : décalage, n_past = '+IStr(Cx.NPast)+', n_left = '+IStr(NLeft)+', n_discard = '+IStr(NDiscard)+#10);
    CtxShift(Mdl,Cx,NKeep,NDiscard);
   End;
   { evaluation par lots }
   I:=0;
   While I<Length(Embd)do Begin
    Chunk:=Length(Embd)-I;
    If Chunk>UBatchSize Then Chunk:=UBatchSize;
    T0:=NowMsF;
    Decode(Mdl,Cx,@Embd[I],Chunk,Cx.NPast);
    If Chunk>1 Then Begin TPEvalMs:=TPEvalMs+(NowMsF-T0);Inc(NPEval,Chunk);End
    Else Begin TEvalMs:=TEvalMs+(NowMsF-T0);Inc(NEvalRuns);End;
    Inc(I,Chunk);
   End;
   HaveLogits:=True;
  End;
  SetLength(Embd,0);
  If(Length(EmbdInp)<=NConsumed)and not IsInteracting Then Begin
   T0:=NowMsF;
   Id:=SamplerSample(Smp,Mdl.V,Cx.Logits);
   If Id<0 Then Begin
    LogErr(#10'erreur : aucun jeton ne respecte les contraintes de la grammaire'+#10);
    Failed:=True;
    Break;
   End;
   SamplerAccept(Smp,Mdl.V,Id,True);
   TSampMs:=TSampMs+(NowMsF-T0);Inc(NSampled);
   AddInt(Hist,Id);
   SetLength(Embd,1);Embd[0]:=Id;
   If ConvMode and not WaitingFirst and not VocabIsEOG(Mdl.V,Id)Then AssistantSS:=AssistantSS+Piece(Id,False);
   InputEcho:=True;
   Dec(NRemain);
  End
   Else Begin
    While Length(EmbdInp)>NConsumed do Begin
     N:=Length(Embd);
     SetLength(Embd,N+1);
     Embd[N]:=EmbdInp[NConsumed];
     SamplerAccept(Smp,Mdl.V,EmbdInp[NConsumed],False);
     AddInt(Hist,EmbdInp[NConsumed]);
     Inc(NConsumed);
     If Length(Embd)=Prm.NBatch Then Break;
    End;
   End;
  { affichage }
  If InputEcho and Display Then Begin
   For I:=0 to High(Embd)do Begin
    TokStr:=Piece(Embd[I],Prm.Special);
    Write(TokStr);
    If OutFileOn and(Length(Embd)=1)Then WriteOutFile(TokStr);
   End;
   Flush(Output);
   ClearIO;
  End;
  If InputEcho and(Length(EmbdInp)=NConsumed)Then Begin
   SetDisplay(DT_RESET);
   Display:=True;
  End;
  { generation terminee ? }
  If Length(EmbdInp)<=NConsumed Then Begin
   If Length(Prm.Antiprompt)>0 Then Begin
    LastOut:='';
    K:=Length(Hist)-32;
    If K<0 Then K:=0;
    For I:=K to High(Hist)do LastOut:=LastOut+Piece(Hist[I],True);
    IsAntiprompt:=False;
    For I:=0 to High(Prm.Antiprompt)do
     If OverlapAntiprompt(LastOut,Prm.Antiprompt[I],Prm.Interactive)Then Begin
      If Prm.Interactive Then IsInteracting:=True;
      IsAntiprompt:=True;
      Break;
     End;
    If(LastOut<>'')and(Length(Hist)>0)Then
     For I:=0 to High(AntiTok)do
      If AntiTok[I]=Hist[High(Hist)]Then Begin
       If Prm.Interactive Then IsInteracting:=True;
       IsAntiprompt:=True;
       Break;
      End;
   End;
   { fin de generation en mode interactif }
   If(not WaitingFirst)and(Length(Hist)>0)and VocabIsEOG(Mdl.V,Hist[High(Hist)])Then Begin
    If Prm.Interactive Then Begin
     If Length(Prm.Antiprompt)>0 Then Begin
      PL:=VocabTokenize(Mdl.V,Prm.Antiprompt[0],False,True);
      AppendInts(EmbdInp,PL);
      IsAntiprompt:=True;
     End;
     If EnableChatTemplate and ConvMode Then Begin
      ChatAddAndFormat('assistant',AssistantSS);
      WriteOutFile(#10);
     End;
     IsInteracting:=True;
     Write(#10);
    End;
   End;
   If ConvMode and not WaitingFirst Then Begin
    If Prompt<>'' Then Begin
     Prompt:='';
     IsInteracting:=False;
    End;
   End;
   If((Cx.NPast>0)or WaitingFirst)and IsInteracting Then Begin
    LogDbg('en attente de la saisie utilisateur'+#10);
    If ConvMode Then Begin
     If Prm.ShowTimings and(NSampled>0)and(Length(Hist)>0)and VocabIsEOG(Mdl.V,Hist[High(Hist)])Then
      WriteLn(#10'[ Prompt: ',FStr(PerfTps(TPEvalMs,NPEval),1),' t/s | Generation: ',FStr(PerfTps(TEvalMs,NEvalRuns),1),' t/s ]');
     Write(#10'> ');
    End;
    If Prm.InPrefixBos and(Mdl.V.BOS>=0)Then AddInt(EmbdInp,Mdl.V.BOS);
    If(Prm.InPrefix<>'')and not ConvMode Then Write(Prm.InPrefix);
    Flush(Output);
    SetDisplay(DT_USER);
    Display:=Prm.DisplayPrompt;
    ReadUserInput(Buffer);
    SetDisplay(DT_RESET);
    Display:=True;
    If Buffer='' Then Begin
     Write('EOF by user'#10);
     Break;
    End;
    If Buffer[Length(Buffer)]=#10 Then Delete(Buffer,Length(Buffer),1);
    If Buffer<>'' Then Begin
     If(Prm.InSuffix<>'')and not ConvMode Then Write(Prm.InSuffix);
     OrigSize:=Length(EmbdInp);
     If Prm.Escape Then Buffer:=ProcessEscapes(Buffer);
     FormatChat:=ConvMode and EnableChatTemplate;
     If FormatChat Then Begin
      WriteOutFile('Utilisateur :'#10+Buffer+#10#10);
      UserInp:=ChatAddAndFormat('user',Buffer);
     End
      Else UserInp:=Buffer;
     LinePfx:=VocabTokenize(Mdl.V,Prm.InPrefix,False,True);
     LineIn:=VocabTokenize(Mdl.V,UserInp,False,FormatChat);
     LineSfx:=VocabTokenize(Mdl.V,Prm.InSuffix,False,True);
     AppendInts(EmbdInp,LinePfx);
     AppendInts(EmbdInp,LineIn);
     AppendInts(EmbdInp,LineSfx);
     If Prm.VerbosePrompt Then Begin
      LogInf('main : nombre de jetons dans le prompt = '+IStr(Length(EmbdInp)-OrigSize)+#10);
     End;
     AssistantSS:='';
     If not ConvMode Then NRemain:=NRemain-Length(LineIn);
    End;
    InputEcho:=False;
   End;
   If(Cx.NPast>0)or WaitingFirst Then Begin
    If IsInteracting Then SamplerReset(Smp);
    IsInteracting:=False;
    If WaitingFirst and Prm.SingleTurn Then Begin
     Prm.Interactive:=False;Prm.InteractiveFirst:=False;
    End;
    WaitingFirst:=False;
   End;
  End;
  { fin de generation }
  If(Length(Embd)>0)and VocabIsEOG(Mdl.V,Embd[High(Embd)])and not Prm.Interactive Then Begin
   If not ConvMode Then Write(' [end of text]'#10);
   If ConvMode and EnableChatTemplate Then ChatAddAndFormat('assistant',AssistantSS);
   Break;
  End;
  If Prm.Interactive and(NRemain<=0)and(Prm.NPredict>=0)Then Begin
   NRemain:=Prm.NPredict;
   IsInteracting:=True;
  End;
  { grammaire terminee sans possibilite de continuer }
  If Smp.HasGrammar and(Length(Smp.Gram.Stacks)=0)Then Break;
 End;
 Write(#10#10);
 Flush(Output);
 If ConvMode and Prm.ShowTimings and not Prm.Interactive and(NSampled>0)Then
  WriteLn('[ Prompt: ',FStr(PerfTps(TPEvalMs,NPEval),1),' t/s | Generation: ',FStr(PerfTps(TEvalMs,NEvalRuns),1),' t/s ]');
 If Prm.ShowTimings or Prm.Perf Then PrintPerf;
 If OutFileOn Then Begin Close(OutFile);ClearIO;End;
 If Failed Then Halt(1);
End;

{ ------------------------------------------------------------------ }
{ Point d'entree                                                     }
{ ------------------------------------------------------------------ }

Begin
 Set8087CW($133F);
 InitHalfTable;
 InitByteUnicode;
 InitConsole;
 LogLevel:=3;
 LogDisabled:=False;
 LogFileOn:=False;
 SimpleIO:=False;
 OutFileOn:=False;
 RegisterOptions;
 ParamsDefaults(Prm);
 ParseCommandLine;
 If Prm.HelpReq Then Begin
  PrintUsage;
  Halt(0);
 End;
 If Prm.VersionReq Then Begin
  PrintVersion;
  Halt(0);
 End;
 If Prm.CacheListReq Then Begin
  PrintCacheList;
  Halt(0);
 End;
 If Prm.ListDevicesReq Then Begin
  WriteLn('Available devices:');
  WriteLn('  (aucun GPU : le calcul GPU n''est pas supporté dans ce clone)');
  Halt(0);
 End;
 RunMain;
End.
