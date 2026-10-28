{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/vie)
  @abstract(Target: Free Pascal 3.x)

  VTON : essayage virtuel de vetements (Virtual Try-ON) pilote par IA.

  Syntaxe :
    VTON personne.jpg vetement.jpg -o resultat.png -type haut
    VTON personne.jpg -prompt "Change le chandail rouge en bleu" -o resultat.png

  Principe : un reseau de neurones de transformeurs (SegFormer, fichier
  .safetensors fourni par -model) analyse la photo et separe chaque pixel en
  classes (haut, pantalon, jupe, robe, chaussures, chapeau, cheveux, peau...).
  Cette analyse permet ensuite de recolorer, de motiver (rayures, carreaux,
  pois), de retirer un accessoire ou de remplacer un vetement par celui
  d'une seconde photo (recalage geometrique, ombrage, remplissage). Le
  parametre -prompt est interprete en langage naturel (francais et anglais).

  Contraintes respectees :
   - un seul fichier source, aucun fichier d'inclusion;
   - la seule unite utilisee est DOS (le reste vient de l'unite System);
   - decodeurs JPEG (de base et progressif), PNG, BMP, PPM et encodeurs
     PNG, JPEG, BMP, PPM ecrits en Pascal;
   - le telechargement du modele (-model URL ou nom connu) n'existe que sous
     Windows (WinInet);
   - GPU (Windows seulement, optionnel) : shaders de calcul Direct3D 11
     (HLSL compile a l'execution, aucune bibliotheque tierce) pour les
     produits matriciels du reseau; le resultat est verifie au demarrage
     contre le calcul CPU, sinon le calcul reste sur le processeur;
   - se compile en 32 bits sous Windows comme en 64 bits.

  Compilation : fpc -O3 VTON.PAS
                (en 32 bits, ajouter -CfSSE2 pour accelerer le calcul)
}

Program VTON;

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
 VersionStr   = '1.0 (clone Pascal de VTON, essayage virtuel par IA)';
 MaxLabels    = 64;

Type
 PSingleArr = PSingle;
 TSingleArr = Array[0..0]of Single;
 PIntArr = PLongInt;
 TIntArr = Array[0..0]of LongInt;
 PWordArr = PWord;
 TWordArr = Array[0..0]of Word;
 PSmallArr = PSmallInt;
 TSmallArr = Array[0..0]of SmallInt;
 PByteArr = PByte;
 TByteArr = Array[0..0]of Byte;
 TStrArray = Array of AnsiString;
 TIntArray = Array of LongInt;
 TSingleArray = Array of Single;
 TByteArray = Array of Byte;

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

Function TrimS(Const S:AnsiString):AnsiString;
Var
 A,B:LongInt;
Begin
 A:=1;B:=Length(S);
 While(A<=B)and(S[A]in[' ',#9,#13,#10])do Inc(A);
 While(B>=A)and(S[B]in[' ',#9,#13,#10])do Dec(B);
 TrimS:=Copy(S,A,B-A+1);
End;

Procedure AddStr(Var A:TStrArray;Const S:AnsiString);
Begin
 SetLength(A,Length(A)+1);
 A[High(A)]:=S;
End;

{ decoupe S selon le caractere Sep }
Function SplitStr(Const S:AnsiString;Sep:Char):TStrArray;
Var
 I,P:LongInt;
Begin
 SetLength(SplitStr,0);
 P:=1;
 For I:=1 to Length(S)do If S[I]=Sep Then Begin
  AddStr(SplitStr,Copy(S,P,I-P));
  P:=I+1;
 End;
 AddStr(SplitStr,Copy(S,P,Length(S)-P+1));
End;

Function ParseInt(Const S:AnsiString;Var V:Int64):Boolean;
Var
 Code:LongInt;
 T:AnsiString;
Begin
 T:=TrimS(S);
 ParseInt:=False;
 If T='' Then Exit;
 Val(T,V,Code);
 ParseInt:=Code=0;
End;

Function ParseFloat(Const S:AnsiString;Var V:Double):Boolean;
Var
 Code:LongInt;
 T:AnsiString;
 I:LongInt;
Begin
 T:=TrimS(S);
 ParseFloat:=False;
 If T='' Then Exit;
 For I:=1 to Length(T)do If T[I]=',' Then T[I]:='.';
 Val(T,V,Code);
 ParseFloat:=Code=0;
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

Function PadRight(S:AnsiString;W:Integer):AnsiString;
Begin
 While Length(S)<W do S:=S+' ';
 PadRight:=S;
End;

Function HumanBytes(N:Int64):AnsiString;
Begin
 If N<1024 Then HumanBytes:=IStr(N)+' o'
 Else If N<1048576 Then HumanBytes:=FStr(N/1024.0,1)+' Kio'
 Else If N<1073741824 Then HumanBytes:=FStr(N/1048576.0,1)+' Mio'
 Else HumanBytes:=FStr(N/1073741824.0,2)+' Gio';
End;

{ ------------------------------------------------------------------ }
{ Temps, hasard et mathematiques                                      }
{ ------------------------------------------------------------------ }

Var
 LastHs:Int64;
 DayOfs:Int64;
 StartMs:Double;

{$IFDEF WINDOWS}
Function QueryPerformanceCounter(Var C:Int64):LongInt;stdcall;external
  'kernel32.dll' name 'QueryPerformanceCounter';
Function QueryPerformanceFrequency(Var F:Int64):LongInt;stdcall;external
  'kernel32.dll' name 'QueryPerformanceFrequency';
{$ELSE}
 {$IFDEF UNIX}
Type
 TTimeSpec=Record
  Sec:PtrInt;
  NSec:PtrInt;
 End;
Function clock_gettime(Id:LongInt;Var T:TTimeSpec):LongInt;cdecl;external 'c'
  name 'clock_gettime';
 {$ENDIF}
{$ENDIF}

{ temps ecoule en millisecondes }
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

Function MakeSeed:LongWord;
Var
 H,M,S,S100,Y,Mo,D,Dw:Word;
Begin
 GetTime(H,M,S,S100);
 GetDate(Y,Mo,D,Dw);
 MakeSeed:=LongWord(((((Int64(H)*60+M)*60+S)*100+S100)xor(Int64(D)
   *2654435761)xor
   (Int64(Mo)*40503)xor(Int64(Y)*65599))and $7FFFFFFF);
End;

Var
 RngState:LongWord=2463534242;

Procedure RngSeed(Seed:LongWord);
Begin
 RngState:=Seed xor $9E3779B9;
 If RngState=0 Then RngState:=2463534242;
End;

Function RngNext:LongWord;
Begin
 RngState:=RngState xor(RngState shl 13);
 RngState:=RngState xor(RngState shr 17);
 RngState:=RngState xor(RngState shl 5);
 RngNext:=RngState;
End;

{ nombre pseudo-aleatoire dans [0,1[ }
Function RngF:Single;
Begin
 RngF:=(RngNext shr 8)/16777216.0;
End;

{ nombre pseudo-aleatoire approximativement gaussien (moyenne 0, ecart-type 1) }
Function RngGauss:Single;
Begin
 RngGauss:=(RngF+RngF+RngF+RngF-2.0)*1.7320508;
End;

{ decalage arithmetique a droite (shr est logique : faux pour un nombre negatif)
  }
Function Sar(V,N:LongInt):LongInt;
Begin
 If V>=0 Then Sar:=V shr N Else Sar:=not((not V)shr N);
End;

Function FMin(A,B:Double):Double;Begin If A<B Then FMin:=A Else FMin:=B;End;
Function FMax(A,B:Double):Double;Begin If A>B Then FMax:=A Else FMax:=B;End;
Function IMin(A,B:Int64):Int64;Begin If A<B Then IMin:=A Else IMin:=B;End;
Function IMax(A,B:Int64):Int64;Begin If A>B Then IMax:=A Else IMax:=B;End;

Function Clamp(X,A,B:Double):Double;
Begin
 If X<A Then Clamp:=A Else If X>B Then Clamp:=B Else Clamp:=X;
End;

Function ClampI(X,A,B:LongInt):LongInt;
Begin
 If X<A Then ClampI:=A Else If X>B Then ClampI:=B Else ClampI:=X;
End;

Function FPow(X,Y:Double):Double;
Begin
 If Y=0 Then FPow:=1.0
 Else If X<=0 Then FPow:=0.0
 Else FPow:=Exp(Y*Ln(X));
End;

Function FloorI(X:Double):LongInt;
Begin
 FloorI:=Trunc(X);
 If X<FloorI Then FloorI:=FloorI-1;
End;

Function SmoothStep(A,B,X:Double):Double;
Var
 T:Double;
Begin
 If B=A Then Begin
  If X>=A Then SmoothStep:=1 Else SmoothStep:=0;
  Exit;
 End;
 T:=(X-A)/(B-A);
 If T<0 Then T:=0 Else If T>1 Then T:=1;
 SmoothStep:=T*T*(3-2*T);
End;

{ erf(x), erreur absolue < 1,2e-7 (Numerical Recipes, erfc de Chebyshev) }
Function FErf(X:Double):Double;
Var
 T,Z,R:Double;
Begin
 Z:=Abs(X);
 T:=1.0/(1.0+0.5*Z);
 R:=T*Exp(-Z*Z-1.26551223+T*(1.00002368+T*(0.37409196+T*(0.09678418+
    T*(-0.18628806+T*(0.27886807+T*(-1.13520398+T*(1.48851587+
    T*(-0.82215223+T*0.17087277)))))))));
 If X>=0 Then FErf:=1.0-R Else FErf:=R-1.0;
End;

{ ------------------------------------------------------------------ }
{ Sorties : les textes du programme sont ecrits en CP437 (#130, #138,   }
{ ...) ; la console est en UTF-8 : chaque Write/WriteLn est converti a   }
{ la volee de CP437 en UTF-8.                                           }
{ ------------------------------------------------------------------ }

Const
 Cp437Tab:Array[128..255]of Word=(
  $00C7,$00FC,$00E9,$00E2,$00E4,$00E0,$00E5,$00E7,
  $00EA,$00EB,$00E8,$00EF,$00EE,$00EC,$00C4,$00C5,
  $00C9,$00E6,$00C6,$00F4,$00F6,$00F2,$00FB,$00F9,
  $00FF,$00D6,$00DC,$00A2,$00A3,$00A5,$20A7,$0192,
  $00E1,$00ED,$00F3,$00FA,$00F1,$00D1,$00AA,$00BA,
  $00BF,$2310,$00AC,$00BD,$00BC,$00A1,$00AB,$00BB,
  $2591,$2592,$2593,$2502,$2524,$2561,$2562,$2556,
  $2555,$2563,$2551,$2557,$255D,$255C,$255B,$2510,
  $2514,$2534,$252C,$251C,$2500,$253C,$255E,$255F,
  $255A,$2554,$2569,$2566,$2560,$2550,$256C,$2567,
  $2568,$2564,$2565,$2559,$2558,$2552,$2553,$256B,
  $256A,$2518,$250C,$2588,$2584,$258C,$2590,$2580,
  $03B1,$00DF,$0393,$03C0,$03A3,$03C3,$00B5,$03C4,
  $03A6,$0398,$03A9,$03B4,$221E,$03C6,$03B5,$2229,
  $2261,$00B1,$2265,$2264,$2320,$2321,$00F7,$2248,
  $00B0,$2219,$00B7,$221A,$207F,$00B2,$25A0,$00A0
 );

Type
 TTextFn=Function(Var F:TextRec):LongInt;

Var
 OrigOutFn,OrigErrFn:TTextFn;

Function Cp437ToUtf8(Const S:AnsiString):AnsiString;
Var
 I,J,N,W:LongInt;
 R:AnsiString;
Begin
 N:=Length(S);
 SetLength(R,N*3);
 J:=0;
 For I:=1 to N do Begin
  W:=Ord(S[I]);
  If W<128 Then Begin
   Inc(J);R[J]:=S[I];
  End
   Else Begin
    W:=Cp437Tab[W];
    If W<$800 Then Begin
     Inc(J);R[J]:=Chr($C0 or(W shr 6));
     Inc(J);R[J]:=Chr($80 or(W and $3F));
    End
     Else Begin
      Inc(J);R[J]:=Chr($E0 or(W shr 12));
      Inc(J);R[J]:=Chr($80 or((W shr 6)and $3F));
      Inc(J);R[J]:=Chr($80 or(W and $3F));
     End;
   End;
 End;
 SetLength(R,J);
 Cp437ToUtf8:=R;
End;

Function ConvOutput(Var F:TextRec;Orig:TTextFn):LongInt;
Var
 Raw,Conv:AnsiString;
 P,L:LongInt;
Begin
 ConvOutput:=0;
 SetLength(Raw,F.BufPos);
 If F.BufPos>0 Then Move(F.BufPtr^,Raw[1],F.BufPos);
 Conv:=Cp437ToUtf8(Raw);
 If Conv='' Then Begin F.BufPos:=0;Exit;End;
 P:=1;
 While P<=Length(Conv)do Begin
  L:=Length(Conv)-P+1;
  If L>F.BufSize Then L:=F.BufSize;
  Move(Conv[P],F.BufPtr^,L);
  F.BufPos:=L;
  ConvOutput:=Orig(F);
  Inc(P,L);
 End;
End;

Function OutFn(Var F:TextRec):LongInt;
Begin
 OutFn:=ConvOutput(F,OrigOutFn);
End;

Function ErrFn(Var F:TextRec):LongInt;
Begin
 ErrFn:=ConvOutput(F,OrigErrFn);
End;

Procedure InstallUtf8Output;
Begin
 SetTextCodePage(Output,DefaultSystemCodePage);
 SetTextCodePage(StdErr,DefaultSystemCodePage);
 OrigOutFn:=TTextFn(TextRec(Output).InOutFunc);
 TextRec(Output).InOutFunc:=@OutFn;
 TextRec(Output).FlushFunc:=@OutFn;
 OrigErrFn:=TTextFn(TextRec(StdErr).InOutFunc);
 TextRec(StdErr).InOutFunc:=@ErrFn;
 TextRec(StdErr).FlushFunc:=@ErrFn;
End;

Var
 Verbose:Boolean=False;
 Quiet:Boolean=False;

{ message d'information (toujours affiche sauf avec -quiet) }
Procedure Info(Const S:AnsiString);
Begin
 If Quiet Then Exit;
 WriteLn(S);
 Flush(Output);
End;

{ detail du traitement (seulement avec -verbose) }
Procedure Detail(Const S:AnsiString);
Begin
 If not Verbose Then Exit;
 WriteLn('  ',S);
 Flush(Output);
End;

Procedure Warn(Const S:AnsiString);
Begin
 Write(StdErr,'attention : ',S,#10);
 Flush(StdErr);
End;

Procedure Fatal(Const S:AnsiString);
Begin
 Write(StdErr,'erreur : ',S,#10);
 Flush(StdErr);
 Halt(1);
End;

{ ------------------------------------------------------------------ }
{ Memoire et fichiers                                                 }
{ ------------------------------------------------------------------ }

Function AllocBytes(N:Int64):Pointer;
Var
 P:Pointer;
Begin
 If N<=0 Then N:=1;
 If N>=2000000000 Then Fatal('m'#130'moire insuffisante (demande de '+
   HumanBytes(N)+')');
 P:=Nil;
 GetMem(P,N);
 If P=Nil Then Fatal('m'#130'moire insuffisante (demande de '+HumanBytes(N)+
   ')');
 FillChar(P^,N,0);
 AllocBytes:=P;
End;

Function AllocF(N:Int64):PSingle;
Begin
 AllocF:=PSingle(AllocBytes(N*4));
End;

Procedure FreeP(Var P:Pointer);
Begin
 If P<>Nil Then FreeMem(P);
 P:=Nil;
End;

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

{ charge un fichier entier en memoire }
Function ReadFileBytes(Const Name:AnsiString;Var P:PByte;Var N:LongInt):Boolean;
Var
 F:File;
 Sz,Done:Int64;
 Got,Chunk:LongInt;
Begin
 ReadFileBytes:=False;
 P:=Nil;N:=0;
 Sz:=FileSizeP(Name);
 If Sz<0 Then Exit;
 Assign(F,Name);
 Reset(F,1);
 If IOResult<>0 Then Exit;
 P:=PByte(AllocBytes(Sz+8));
 Done:=0;
 While Done<Sz do Begin
  Chunk:=1048576;
  If Sz-Done<Chunk Then Chunk:=Sz-Done;
  BlockRead(F,(P+Done)^,Chunk,Got);
  If Got<=0 Then Break;
  Inc(Done,Got);
 End;
 Close(F);
 If IOResult<>0 Then;
 N:=Done;
 ReadFileBytes:=Done=Sz;
End;

Function WriteFileBytes(Const Name:AnsiString;P:PByte;N:LongInt):Boolean;
Var
 F:File;
 Done:LongInt;
 Chunk,Put:LongInt;
Begin
 WriteFileBytes:=False;
 Assign(F,Name);
 Rewrite(F,1);
 If IOResult<>0 Then Exit;
 Done:=0;
 While Done<N do Begin
  Chunk:=1048576;
  If N-Done<Chunk Then Chunk:=N-Done;
  BlockWrite(F,(P+Done)^,Chunk,Put);
  If Put<=0 Then Break;
  Inc(Done,Put);
 End;
 Close(F);
 If IOResult<>0 Then;
 WriteFileBytes:=Done=N;
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

Function PathExt(Const P:AnsiString):AnsiString;
Var
 I:LongInt;
 N:AnsiString;
Begin
 N:=PathLastPart(P);
 I:=Length(N);
 While(I>=1)and(N[I]<>'.')do Dec(I);
 If I<1 Then PathExt:='' Else PathExt:=LoStr(Copy(N,I,Length(N)-I+1));
End;

Function PathNoExt(Const P:AnsiString):AnsiString;
Var
 E:AnsiString;
Begin
 E:=PathExt(P);
 PathNoExt:=Copy(P,1,Length(P)-Length(E));
End;

Function PathSep:AnsiString;
Begin
 {$IFDEF UNIX}
 PathSep:='/';
 {$ELSE}
 PathSep:='\';
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
  If(Path[I]in['/','\'])and(Cur<>'')and not(Cur[Length(Cur)]in[':','/',
    '\'])Then Begin
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

{ ------------------------------------------------------------------ }
{ Images : structure, inflate/deflate, PNG, BMP, PPM                  }
{ ------------------------------------------------------------------ }

Type
 { image RGB entrelacee (3 octets par pixel), canal alpha optionnel }
 TImage=Record
  W,H:LongInt;
  Px:PByte;
  Alpha:PByte;
 End;

Procedure ImgAlloc(Var I:TImage;W,H:LongInt;WithAlpha:Boolean);
Begin
 I.W:=W;I.H:=H;
 I.Px:=PByte(AllocBytes(Int64(W)*H*3));
 I.Alpha:=Nil;
 If WithAlpha Then I.Alpha:=PByte(AllocBytes(Int64(W)*H));
End;

Procedure ImgFree(Var I:TImage);
Begin
 If I.Px<>Nil Then FreeMem(I.Px);
 If I.Alpha<>Nil Then FreeMem(I.Alpha);
 I.Px:=Nil;I.Alpha:=Nil;I.W:=0;I.H:=0;
End;

{ ---- CRC32 et Adler32 ---- }

Var
 CrcTab:Array[0..255]of LongWord;
 CrcReady:Boolean=False;

Procedure CrcInit;
Var
 N,K:LongInt;
 C:LongWord;
Begin
 If CrcReady Then Exit;
 For N:=0 to 255 do Begin
  C:=N;
  For K:=0 to 7 do If(C and 1)<>0 Then C:=$EDB88320 xor(C shr 1)Else C:=C shr 1;
  CrcTab[N]:=C;
 End;
 CrcReady:=True;
End;

Function Crc32Update(Crc:LongWord;P:PByte;N:LongInt):LongWord;
Var
 I:LongInt;
Begin
 CrcInit;
 Crc:=Crc xor $FFFFFFFF;
 For I:=0 to N-1 do Crc:=CrcTab[(Crc xor P[I])and $FF]xor(Crc shr 8);
 Crc32Update:=Crc xor $FFFFFFFF;
End;

Function Adler32(P:PByte;N:LongInt):LongWord;
Var
 A,B:LongWord;
 I,K:LongInt;
Begin
 A:=1;B:=0;
 I:=0;
 While I<N do Begin
  K:=N-I;
  If K>5000 Then K:=5000;
  While K>0 do Begin
   A:=A+P[I];B:=B+A;
   Inc(I);Dec(K);
  End;
  A:=A mod 65521;B:=B mod 65521;
 End;
 Adler32:=(B shl 16)or A;
End;

{ ---- inflate (RFC 1951) ---- }

Type
 THuf=Record
  Count:Array[0..15]of Word;
  Sym:Array[0..319]of Word;
  Fast:Array[0..511]of Word;
 End;
 TInfl=Record
  Src:PByte;
  SrcLen,SrcPos:LongInt;
  BitBuf:LongWord;
  BitCnt:LongInt;
  Dst:PByte;
  DstCap,DstPos:LongInt;
  Err:Boolean;
 End;

Const
 LenBase:Array[0..28]of Word=(3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,
   51,59,67,83,99,115,131,163,195,227,258);
 LenExtra:Array[0..28]of Byte=(0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,
   5,5,5,5,0);
 DistBase:Array[0..29]of Word=(1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,
   385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577);
 DistExtra:Array[0..29]of Byte=(0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,
   10,11,11,12,12,13,13);
 ClOrder:Array[0..18]of Byte=(16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15);

Procedure IFill(Var S:TInfl);
Begin
 While S.BitCnt<=24 do Begin
  If S.SrcPos<S.SrcLen Then S.BitBuf:=S.BitBuf or(LongWord(S.Src[S.SrcPos])shl
    S.BitCnt);
  Inc(S.SrcPos);
  Inc(S.BitCnt,8);
 End;
End;

Function IBits(Var S:TInfl;N:LongInt):LongInt;
Begin
 If N=0 Then Begin IBits:=0;Exit;End;
 If S.BitCnt<N Then IFill(S);
 IBits:=S.BitBuf and((LongWord(1)shl N)-1);
 S.BitBuf:=S.BitBuf shr N;
 Dec(S.BitCnt,N);
End;

Function BuildHuf(Var H:THuf;Lens:PByte;N:LongInt):Boolean;
Var
 Offs:Array[0..15]of Word;
 NextCode:Array[0..16]of LongWord;
 I,L,K,Left:LongInt;
 Code:LongWord;
 Rev:LongWord;
 J:LongInt;
Begin
 BuildHuf:=True;
 FillChar(H,SizeOf(H),0);
 For I:=0 to N-1 do Inc(H.Count[Lens[I]]);
 H.Count[0]:=0;
 Left:=1;
 For L:=1 to 15 do Begin
  Left:=Left*2-H.Count[L];
  If Left<0 Then BuildHuf:=False;
 End;
 Offs[1]:=0;
 For L:=1 to 14 do Offs[L+1]:=Offs[L]+H.Count[L];
 For I:=0 to N-1 do If Lens[I]<>0 Then Begin
  H.Sym[Offs[Lens[I]]]:=I;
  Inc(Offs[Lens[I]]);
 End;
 { table rapide pour les codes de 9 bits ou moins }
 Code:=0;
 For L:=1 to 15 do Begin
  If L>1 Then Code:=(Code+H.Count[L-1])shl 1 Else Code:=0;
  NextCode[L]:=Code;
 End;
 For I:=0 to N-1 do Begin
  L:=Lens[I];
  If L=0 Then Continue;
  Code:=NextCode[L];
  Inc(NextCode[L]);
  If L<=9 Then Begin
   Rev:=0;
   For K:=0 to L-1 do If(Code and(LongWord(1)shl K))<>0 Then Rev:=Rev or(
     LongWord(1)shl(L-1-K));
   J:=Rev;
   While J<512 do Begin
    H.Fast[J]:=(L shl 9)or I;
    Inc(J,1 shl L);
   End;
  End;
 End;
End;

Function IDecode(Var S:TInfl;Var H:THuf):LongInt;
Var
 E:Word;
 L,Code,First,Index,Cnt:LongInt;
Begin
 If S.BitCnt<16 Then IFill(S);
 E:=H.Fast[S.BitBuf and 511];
 If E<>0 Then Begin
  L:=E shr 9;
  S.BitBuf:=S.BitBuf shr L;
  Dec(S.BitCnt,L);
  IDecode:=E and 511;
  Exit;
 End;
 Code:=0;First:=0;Index:=0;
 For L:=1 to 15 do Begin
  Code:=Code or LongInt(S.BitBuf and 1);
  S.BitBuf:=S.BitBuf shr 1;
  Dec(S.BitCnt);
  Cnt:=H.Count[L];
  If Code-Cnt<First Then Begin
   IDecode:=H.Sym[Index+(Code-First)];
   Exit;
  End;
  Inc(Index,Cnt);
  Inc(First,Cnt);
  First:=First shl 1;
  Code:=Code shl 1;
 End;
 IDecode:=-1;
End;

Function InflateCodes(Var S:TInfl;Var Lit,Dist:THuf):Boolean;
Var
 Sym,Len,D,I:LongInt;
Begin
 InflateCodes:=False;
 While True do Begin
  Sym:=IDecode(S,Lit);
  If Sym<0 Then Exit;
  If Sym<256 Then Begin
   If S.DstPos>=S.DstCap Then Begin InflateCodes:=True;S.Err:=True;Exit;End;
   S.Dst[S.DstPos]:=Sym;
   Inc(S.DstPos);
  End
   Else If Sym=256 Then Begin
    InflateCodes:=True;
    Exit;
   End
    Else Begin
     Dec(Sym,257);
     If Sym>=29 Then Exit;
     Len:=LenBase[Sym]+IBits(S,LenExtra[Sym]);
     Sym:=IDecode(S,Dist);
     If(Sym<0)or(Sym>=30)Then Exit;
     D:=DistBase[Sym]+IBits(S,DistExtra[Sym]);
     If D>S.DstPos Then Exit;
     If S.DstPos+Len>S.DstCap Then Begin
      Len:=S.DstCap-S.DstPos;
      S.Err:=True;
     End;
     For I:=0 to Len-1 do Begin
      S.Dst[S.DstPos]:=S.Dst[S.DstPos-D];
      Inc(S.DstPos);
     End;
     If S.Err Then Begin InflateCodes:=True;Exit;End;
    End;
  If S.SrcPos>S.SrcLen+8 Then Exit;
 End;
End;

{ decompresse un flux deflate brut vers un tampon de taille connue }
Function InflateRaw(Src:PByte;SrcLen:LongInt;Dst:PByte;DstCap:LongInt;Var
  OutLen:LongInt):Boolean;
Var
 S:TInfl;
 Lit,Dist,Cl:THuf;
 Lens:Array[0..319]of Byte;
 Last,BType,I,N,Len,NLen,HLit,HDist,HClen,Sym,Rep,Prev:LongInt;
Begin
 InflateRaw:=False;
 FillChar(S,SizeOf(S),0);
 S.Src:=Src;S.SrcLen:=SrcLen;S.Dst:=Dst;S.DstCap:=DstCap;
 Repeat
  Last:=IBits(S,1);
  BType:=IBits(S,2);
  If BType=0 Then Begin
   I:=S.BitCnt and 7;
   IBits(S,I);
   Len:=IBits(S,16);
   NLen:=IBits(S,16);
   If(Len xor $FFFF)<>NLen Then Exit;
   For I:=1 to Len do Begin
    If S.DstPos>=S.DstCap Then Begin S.Err:=True;Break;End;
    S.Dst[S.DstPos]:=IBits(S,8);
    Inc(S.DstPos);
   End;
  End
   Else If BType=1 Then Begin
    For I:=0 to 143 do Lens[I]:=8;
    For I:=144 to 255 do Lens[I]:=9;
    For I:=256 to 279 do Lens[I]:=7;
    For I:=280 to 287 do Lens[I]:=8;
    BuildHuf(Lit,@Lens[0],288);
    For I:=0 to 29 do Lens[I]:=5;
    BuildHuf(Dist,@Lens[0],30);
    If not InflateCodes(S,Lit,Dist)Then Exit;
   End
    Else If BType=2 Then Begin
     HLit:=IBits(S,5)+257;
     HDist:=IBits(S,5)+1;
     HClen:=IBits(S,4)+4;
     If(HLit>286)or(HDist>30)Then Exit;
     FillChar(Lens,SizeOf(Lens),0);
     For I:=0 to HClen-1 do Lens[ClOrder[I]]:=IBits(S,3);
     If not BuildHuf(Cl,@Lens[0],19)Then Exit;
     N:=0;
     Prev:=0;
     FillChar(Lens,SizeOf(Lens),0);
     While N<HLit+HDist do Begin
      Sym:=IDecode(S,Cl);
      If Sym<0 Then Exit;
      If Sym<16 Then Begin
       Lens[N]:=Sym;Prev:=Sym;Inc(N);
      End
       Else Begin
        If Sym=16 Then Begin
         If N=0 Then Exit;
         Rep:=3+IBits(S,2);
        End
         Else If Sym=17 Then Begin Rep:=3+IBits(S,3);Prev:=0;End
         Else Begin Rep:=11+IBits(S,7);Prev:=0;End;
        If N+Rep>HLit+HDist Then Exit;
        While Rep>0 do Begin
         Lens[N]:=Prev;Inc(N);Dec(Rep);
        End;
       End;
     End;
     If not BuildHuf(Lit,@Lens[0],HLit)Then Exit;
     If not BuildHuf(Dist,@Lens[HLit],HDist)Then Exit;
     If not InflateCodes(S,Lit,Dist)Then Exit;
    End
     Else Exit;
  If S.Err Then Break;
  If S.SrcPos>S.SrcLen+8 Then Exit;
 Until Last<>0;
 OutLen:=S.DstPos;
 InflateRaw:=True;
End;

{ ---- deflate (LZ77 + codes de Huffman fixes) ---- }

Type
 TDefl=Record
  Dst:PByte;
  Pos:LongInt;
  Buf:LongWord;
  Cnt:LongInt;
 End;

Procedure DPutBits(Var D:TDefl;V:LongWord;N:LongInt);
Begin
 D.Buf:=D.Buf or(V shl D.Cnt);
 Inc(D.Cnt,N);
 While D.Cnt>=8 do Begin
  D.Dst[D.Pos]:=D.Buf and $FF;
  Inc(D.Pos);
  D.Buf:=D.Buf shr 8;
  Dec(D.Cnt,8);
 End;
End;

Function RevBits(V:LongWord;N:LongInt):LongWord;
Var
 I:LongInt;
 R:LongWord;
Begin
 R:=0;
 For I:=1 to N do Begin
  R:=(R shl 1)or(V and 1);
  V:=V shr 1;
 End;
 RevBits:=R;
End;

Procedure DPutLit(Var D:TDefl;Sym:LongInt);
Begin
 If Sym<144 Then DPutBits(D,RevBits($30+Sym,8),8)
 Else If Sym<256 Then DPutBits(D,RevBits($190+(Sym-144),9),9)
 Else If Sym<280 Then DPutBits(D,RevBits(Sym-256,7),7)
 Else DPutBits(D,RevBits($C0+(Sym-280),8),8);
End;

Var
 LenSym:Array[3..258]of Byte;
 DistSymTab:Array[0..511]of Byte;
 DeflReady:Boolean=False;

Procedure DeflInit;
Var
 I,S:LongInt;
Begin
 If DeflReady Then Exit;
 DeflReady:=True;
 For S:=0 to 28 do
  For I:=LenBase[S]to LenBase[S]+(1 shl LenExtra[S])-1 do
   If(I>=3)and(I<=258)Then LenSym[I]:=S;
 LenSym[258]:=28;
 For S:=0 to 29 do
  For I:=DistBase[S]to DistBase[S]+(1 shl DistExtra[S])-1 do
   If I<=256 Then DistSymTab[I]:=S;
End;

Function DistSym(D:LongInt):LongInt;
Var
 S:LongInt;
Begin
 If D<=256 Then DistSym:=DistSymTab[D]
 Else Begin
  S:=0;
  While(S<29)and(DistBase[S+1]<=D)do Inc(S);
  DistSym:=S;
 End;
End;

Procedure DPutMatch(Var D:TDefl;Len,Dist:LongInt);
Var
 S:LongInt;
Begin
 S:=LenSym[Len];
 DPutLit(D,257+S);
 If LenExtra[S]>0 Then DPutBits(D,Len-LenBase[S],LenExtra[S]);
 S:=DistSym(Dist);
 DPutBits(D,RevBits(S,5),5);
 If DistExtra[S]>0 Then DPutBits(D,Dist-DistBase[S],DistExtra[S]);
End;

{ compresse N octets ; Level 1..9 regle la profondeur de recherche }
Function DeflateRaw(Src:PByte;N:LongInt;Level:LongInt;Var OutLen:LongInt):PByte;
Const
 HashBits=15;
 HashSize=1 shl HashBits;
 Window=32768;
Var
 D:TDefl;
 Head:PIntArr;
 Prev:PIntArr;
 I,Pos,H,Cand,Chain,MaxChain,BestLen,BestDist,L,MaxLen,Lim:LongInt;
 NextLen,NextDist,K:LongInt;

 Function Hash3(P:LongInt):LongInt;
 Begin
  Hash3:=((Src[P]shl 10)xor(Src[P+1]shl 5)xor Src[P+2])and(HashSize-1);
 End;

 Procedure Insert(P:LongInt);
 Var
  HH:LongInt;
 Begin
  If P+2>=N Then Exit;
  HH:=Hash3(P);
  Prev[P and(Window-1)]:=Head[HH];
  Head[HH]:=P;
 End;

 Procedure FindMatch(P:LongInt;Var BL,BD:LongInt);
 Var
  C,Ch,LL,ML:LongInt;
 Begin
  BL:=0;BD:=0;
  If P+2>=N Then Exit;
  C:=Head[Hash3(P)];
  Ch:=MaxChain;
  ML:=N-P;
  If ML>258 Then ML:=258;
  While(C>=0)and(P-C<=Window-1)and(Ch>0)do Begin
   If(Src[C+BL]=Src[P+BL])or(BL=0)Then Begin
    LL:=0;
    While(LL<ML)and(Src[C+LL]=Src[P+LL])do Inc(LL);
    If LL>BL Then Begin
     BL:=LL;BD:=P-C;
     If LL>=ML Then Break;
    End;
   End;
   C:=Prev[C and(Window-1)];
   Dec(Ch);
  End;
  If BL<3 Then Begin BL:=0;BD:=0;End;
 End;

Begin
 DeflInit;
 Lim:=N+N div 4+1024;
 D.Dst:=PByte(AllocBytes(Lim));
 D.Pos:=0;D.Buf:=0;D.Cnt:=0;
 Head:=PIntArr(AllocBytes(Int64(HashSize)*4));
 Prev:=PIntArr(AllocBytes(Int64(Window)*4));
 For I:=0 to HashSize-1 do Head[I]:=-1;
 MaxChain:=4;
 If Level>=3 Then MaxChain:=16;
 If Level>=6 Then MaxChain:=64;
 If Level>=9 Then MaxChain:=256;
 DPutBits(D,1,1);
 DPutBits(D,1,2);
 Pos:=0;
 While Pos<N do Begin
  FindMatch(Pos,BestLen,BestDist);
  If(BestLen>=3)and(Level>=3)and(Pos+1<N)and(BestLen<32)Then Begin
   { evaluation differee : une meilleure correspondance en Pos+1 ? }
   Insert(Pos);
   FindMatch(Pos+1,NextLen,NextDist);
   If NextLen>BestLen+1 Then Begin
    DPutLit(D,Src[Pos]);
    Inc(Pos);
    Continue;
   End;
   DPutMatch(D,BestLen,BestDist);
   For K:=1 to BestLen-1 do Insert(Pos+K);
   Inc(Pos,BestLen);
   Continue;
  End;
  If BestLen>=3 Then Begin
   DPutMatch(D,BestLen,BestDist);
   For K:=0 to BestLen-1 do Insert(Pos+K);
   Inc(Pos,BestLen);
  End
   Else Begin
    DPutLit(D,Src[Pos]);
    Insert(Pos);
    Inc(Pos);
   End;
 End;
 DPutLit(D,256);
 If D.Cnt>0 Then DPutBits(D,0,8-D.Cnt);
 FreeMem(Head);
 FreeMem(Prev);
 OutLen:=D.Pos;
 DeflateRaw:=D.Dst;
End;

{ ---- PNG ---- }

Function BE32(P:PByte):LongWord;
Begin
 BE32:=(LongWord(P[0])shl 24)or(LongWord(P[1])shl 16)or(LongWord(P[2])shl 8)or
   P[3];
End;

Function PaethPred(A,B,C:LongInt):LongInt;
Var
 P,PA,PB,PC:LongInt;
Begin
 P:=A+B-C;
 PA:=Abs(P-A);PB:=Abs(P-B);PC:=Abs(P-C);
 If(PA<=PB)and(PA<=PC)Then PaethPred:=A
 Else If PB<=PC Then PaethPred:=B
 Else PaethPred:=C;
End;

{ defiltre un bloc de lignes (Raw : H*(1+Stride) octets) en place }
Function PngUnfilter(Raw:PByte;W,H,Bpp,Stride:LongInt):Boolean;
Var
 Y,X,F,A,B,C:LongInt;
 Cur,Up:PByte;
Begin
 PngUnfilter:=False;
 For Y:=0 to H-1 do Begin
  Cur:=Raw+Int64(Y)*(Stride+1);
  F:=Cur[0];
  Inc(Cur);
  If Y>0 Then Up:=Raw+Int64(Y-1)*(Stride+1)+1 Else Up:=Nil;
  Case F of
   0:;
   1:For X:=Bpp to Stride-1 do Cur[X]:=(Cur[X]+Cur[X-Bpp])and $FF;
   2:If Up<>Nil Then For X:=0 to Stride-1 do Cur[X]:=(Cur[X]+Up[X])and $FF;
   3:For X:=0 to Stride-1 do Begin
      If X>=Bpp Then A:=Cur[X-Bpp]Else A:=0;
      If Up<>Nil Then B:=Up[X]Else B:=0;
      Cur[X]:=(Cur[X]+((A+B)shr 1))and $FF;
     End;
   4:For X:=0 to Stride-1 do Begin
      If X>=Bpp Then A:=Cur[X-Bpp]Else A:=0;
      If Up<>Nil Then B:=Up[X]Else B:=0;
      If(Up<>Nil)and(X>=Bpp)Then C:=Up[X-Bpp]Else C:=0;
      Cur[X]:=(Cur[X]+PaethPred(A,B,C))and $FF;
     End;
   Else Exit;
  End;
 End;
 PngUnfilter:=True;
End;

Function PngDecode(Buf:PByte;N:LongInt;Var Img:TImage;Var Err:AnsiString)
  :Boolean;
Const
 Sig:Array[0..7]of Byte=(137,80,78,71,13,10,26,10);
 AdamX0:Array[0..6]of Byte=(0,4,0,2,0,1,0);
 AdamY0:Array[0..6]of Byte=(0,0,4,0,2,0,1);
 AdamDX:Array[0..6]of Byte=(8,8,4,4,2,2,1);
 AdamDY:Array[0..6]of Byte=(8,8,8,4,4,2,2);
Var
 Pos,Len,I,Depth,CType,Interlace,Chans,Bpp,Stride,W,H:LongInt;
 Kind:Array[0..3]of Char;
 IData:PByte;
 ILen,ICap:LongInt;
 Pal:Array[0..255]of Array[0..3]of Byte;
 NPal:LongInt;
 HasTrns:Boolean;
 TrnsKey:Array[0..2]of LongInt;
 Raw,Unz:PByte;
 RawSize:Int64;
 OutLen:LongInt;
 Pass,PW,PH,PStride,X,Y,OX,OY,Off,K,V,Shift:LongInt;
 Src:PByte;
 R,G,B,Al:LongInt;
 Pad:Int64;
 HaveAlpha:Boolean;

 Function Sample(Row:PByte;X,Ch:LongInt):LongInt;
 Var
  Bit,By:LongInt;
 Begin
  Case Depth of
   8:Sample:=Row[X*Chans+Ch];
   16:Sample:=(Row[(X*Chans+Ch)*2]shl 8)or Row[(X*Chans+Ch)*2+1];
   Else Begin
    Bit:=X*Depth;
    By:=Row[Bit shr 3];
    Sample:=(By shr(8-Depth-(Bit and 7)))and((1 shl Depth)-1);
   End;
  End;
 End;

 Procedure PutPixel(Row:PByte;X,DX,DY:LongInt);
 Var
  PIdx,Mx:LongInt;
  Po:Int64;
 Begin
  Mx:=(1 shl Depth)-1;
  Al:=255;
  Case CType of
   0:Begin
      V:=Sample(Row,X,0);
      R:=V;
      If Depth=16 Then R:=V shr 8
      Else If Depth<8 Then R:=V*255 div Mx;
      G:=R;B:=R;
      If HasTrns and(V=TrnsKey[0])Then Al:=0;
     End;
   2:Begin
      R:=Sample(Row,X,0);G:=Sample(Row,X,1);B:=Sample(Row,X,2);
      If HasTrns and(R=TrnsKey[0])and(G=TrnsKey[1])and(B=TrnsKey[2])Then Al:=0;
      If Depth=16 Then Begin R:=R shr 8;G:=G shr 8;B:=B shr 8;End;
     End;
   3:Begin
      PIdx:=Sample(Row,X,0);
      R:=Pal[PIdx][0];G:=Pal[PIdx][1];B:=Pal[PIdx][2];Al:=Pal[PIdx][3];
     End;
   4:Begin
      R:=Sample(Row,X,0);Al:=Sample(Row,X,1);
      If Depth=16 Then Begin R:=R shr 8;Al:=Al shr 8;End;
      G:=R;B:=R;
     End;
   6:Begin
      R:=Sample(Row,X,0);G:=Sample(Row,X,1);B:=Sample(Row,X,2);
      Al:=Sample(Row,X,3);
      If Depth=16 Then Begin R:=R shr 8;G:=G shr 8;B:=B shr 8;Al:=Al shr 8;End;
     End;
  End;
  Po:=Int64(DY)*W+DX;
  Img.Px[Po*3]:=R;Img.Px[Po*3+1]:=G;Img.Px[Po*3+2]:=B;
  If Img.Alpha<>Nil Then Img.Alpha[Po]:=Al;
 End;

Begin
 PngDecode:=False;
 Err:='';
 Img.Px:=Nil;Img.Alpha:=Nil;
 IData:=Nil;
 For I:=0 to 7 do If(N<8)or(Buf[I]<>Sig[I])Then Begin
   Err:='signature PNG invalide';Exit;End;
 Pos:=8;
 W:=0;H:=0;Depth:=0;CType:=0;Interlace:=0;NPal:=0;HasTrns:=False;
 ILen:=0;ICap:=0;
 FillChar(Pal,SizeOf(Pal),0);
 For I:=0 to 255 do Pal[I][3]:=255;
 TrnsKey[0]:=0;TrnsKey[1]:=0;TrnsKey[2]:=0;
 While Pos+8<=N do Begin
  Len:=BE32(Buf+Pos);
  Kind[0]:=Chr(Buf[Pos+4]);Kind[1]:=Chr(Buf[Pos+5]);Kind[2]:=Chr(Buf[Pos+6]);
  Kind[3]:=Chr(Buf[Pos+7]);
  If(Len<0)or(Int64(Pos)+12+Len>N)Then Begin
   If Kind='IDAT' Then Len:=N-Pos-12 Else Break;
   If Len<0 Then Break;
  End;
  Inc(Pos,8);
  If Kind='IHDR' Then Begin
   W:=BE32(Buf+Pos);H:=BE32(Buf+Pos+4);
   Depth:=Buf[Pos+8];CType:=Buf[Pos+9];Interlace:=Buf[Pos+12];
  End
   Else If Kind='PLTE' Then Begin
    NPal:=Len div 3;
    If NPal>256 Then NPal:=256;
    For I:=0 to NPal-1 do Begin
     Pal[I][0]:=Buf[Pos+I*3];Pal[I][1]:=Buf[Pos+I*3+1];Pal[I][2]:=Buf[Pos+I*3+
       2];
    End;
   End
    Else If Kind='tRNS' Then Begin
     If CType=3 Then Begin
      For I:=0 to Len-1 do If I<256 Then Pal[I][3]:=Buf[Pos+I];
      HasTrns:=True;
     End
      Else If(CType=0)and(Len>=2)Then Begin
       TrnsKey[0]:=(Buf[Pos]shl 8)or Buf[Pos+1];
       HasTrns:=True;
      End
       Else If(CType=2)and(Len>=6)Then Begin
        TrnsKey[0]:=(Buf[Pos]shl 8)or Buf[Pos+1];
        TrnsKey[1]:=(Buf[Pos+2]shl 8)or Buf[Pos+3];
        TrnsKey[2]:=(Buf[Pos+4]shl 8)or Buf[Pos+5];
        HasTrns:=True;
       End;
    End
     Else If Kind='IDAT' Then Begin
      If ILen+Len>ICap Then Begin
       ICap:=(ILen+Len)*2;
       If IData=Nil Then IData:=PByte(AllocBytes(ICap))
       Else Begin
        ReallocMem(IData,ICap);
       End;
      End;
      Move(Buf[Pos],IData[ILen],Len);
      Inc(ILen,Len);
     End
      Else If Kind='IEND' Then Begin
       Break;
      End;
  Inc(Pos,Len+4);
 End;
 If(W<=0)or(H<=0)or(Int64(W)*H>400000000)Then Begin
   Err:='dimensions PNG invalides';
  If IData<>Nil Then FreeMem(IData);Exit;End;
 If IData=Nil Then Begin Err:='aucune donn'#130'es image dans le PNG';Exit;End;
 Case CType of
  0:Chans:=1;
  2:Chans:=3;
  3:Chans:=1;
  4:Chans:=2;
  6:Chans:=4;
  Else Begin Err:='type de couleur PNG inconnu';FreeMem(IData);Exit;End;
 End;
 If not(Depth in[1,2,4,8,16])Then Begin Err:='profondeur PNG inconnue';
   FreeMem(IData);Exit;End;
 Bpp:=(Chans*Depth+7)div 8;
 HaveAlpha:=(CType=4)or(CType=6)or HasTrns;
 ImgAlloc(Img,W,H,HaveAlpha);
 If Interlace=0 Then RawSize:=Int64(H)*(1+(Int64(W)*Chans*Depth+7)div 8)
 Else Begin
  RawSize:=0;
  For Pass:=0 to 6 do Begin
   PW:=(W-AdamX0[Pass]+AdamDX[Pass]-1)div AdamDX[Pass];
   PH:=(H-AdamY0[Pass]+AdamDY[Pass]-1)div AdamDY[Pass];
   If(PW>0)and(PH>0)Then Inc(RawSize,Int64(PH)*(1+(Int64(PW)*Chans*Depth+7)div
     8));
  End;
 End;
 Raw:=PByte(AllocBytes(RawSize+16));
 If(ILen<6)or not InflateRaw(IData+2,ILen-2,Raw,RawSize,OutLen)Then Begin
  Err:='flux zlib invalide dans le PNG';
  FreeMem(IData);FreeMem(Raw);ImgFree(Img);Exit;
 End;
 FreeMem(IData);
 Unz:=Raw;
 If Interlace=0 Then Begin
  Stride:=(W*Chans*Depth+7)div 8;
  If not PngUnfilter(Raw,W,H,Bpp,Stride)Then Begin
   Err:='filtre PNG invalide';FreeMem(Raw);ImgFree(Img);Exit;
  End;
  For Y:=0 to H-1 do Begin
   Src:=Raw+Int64(Y)*(Stride+1)+1;
   For X:=0 to W-1 do PutPixel(Src,X,X,Y);
  End;
 End
  Else Begin
   Off:=0;
   For Pass:=0 to 6 do Begin
    PW:=(W-AdamX0[Pass]+AdamDX[Pass]-1)div AdamDX[Pass];
    PH:=(H-AdamY0[Pass]+AdamDY[Pass]-1)div AdamDY[Pass];
    If(PW<=0)or(PH<=0)Then Continue;
    PStride:=(PW*Chans*Depth+7)div 8;
    If not PngUnfilter(Raw+Off,PW,PH,Bpp,PStride)Then Begin
     Err:='filtre PNG invalide';FreeMem(Raw);ImgFree(Img);Exit;
    End;
    For Y:=0 to PH-1 do Begin
     Src:=Raw+Off+Int64(Y)*(PStride+1)+1;
     For X:=0 to PW-1 do Begin
      OX:=AdamX0[Pass]+X*AdamDX[Pass];
      OY:=AdamY0[Pass]+Y*AdamDY[Pass];
      PutPixel(Src,X,OX,OY);
     End;
    End;
    Inc(Off,PH*(1+PStride));
   End;
  End;
 FreeMem(Raw);
 PngDecode:=True;
End;

Procedure PutBE32(P:PByte;V:LongWord);
Begin
 P[0]:=V shr 24;P[1]:=(V shr 16)and $FF;P[2]:=(V shr 8)and $FF;P[3]:=V and $FF;
End;

{ ecrit un fichier PNG RGB 8 bits (Level 1..9 : effort de compression) }
Function PngEncode(Const Name:AnsiString;Const Img:TImage;Level:LongInt)
  :Boolean;
Var
 Stride,Y,X,F,FLo,FHi,BestF,A,B,C,P,V,I:LongInt;
 Raw,Cur,Prv,Z,Out_,Tmp:PByte;
 Best,Sum:Int64;
 Cand:Array[0..4]of PByte;
 ZLen,Pos:LongInt;
 Ad:LongWord;
 Hdr:Array[0..12]of Byte;
 Bpp:LongInt;
 Src,Rgba:PByte;

 Procedure Chunk(Const Kind:AnsiString;Data:PByte;Len:LongInt);
 Var
  Cr:LongWord;
  H8:Array[0..7]of Byte;
 Begin
  PutBE32(@H8[0],Len);
  H8[4]:=Ord(Kind[1]);H8[5]:=Ord(Kind[2]);H8[6]:=Ord(Kind[3]);
    H8[7]:=Ord(Kind[4]);
  Move(H8[0],Out_[Pos],8);Inc(Pos,8);
  Cr:=Crc32Update(0,@H8[4],4);
  If Len>0 Then Begin
   Move(Data^,Out_[Pos],Len);
   Cr:=Crc32Update(Cr,Data,Len);
   Inc(Pos,Len);
  End;
  PutBE32(Out_+Pos,Cr);
  Inc(Pos,4);
 End;

Begin
 PngEncode:=False;
 Bpp:=3;Src:=Img.Px;Rgba:=Nil;
 If Img.Alpha<>Nil Then Begin
  { avec transparence : RVBA 8 bits }
  Bpp:=4;
  Rgba:=PByte(AllocBytes(Int64(Img.W)*Img.H*4));
  For I:=0 to Img.W*Img.H-1 do Begin
   Rgba[I*4]:=Img.Px[I*3];Rgba[I*4+1]:=Img.Px[I*3+1];Rgba[I*4+2]:=Img.Px[I*3+
     2];Rgba[I*4+3]:=Img.Alpha[I];
  End;
  Src:=Rgba;
 End;
 Stride:=Img.W*Bpp;
 Raw:=PByte(AllocBytes(Int64(Img.H)*(Stride+1)));
 For I:=0 to 4 do Cand[I]:=PByte(AllocBytes(Stride+1));
 FLo:=0;FHi:=4;
 If Level<=2 Then Begin FLo:=1;FHi:=1;End;
 For Y:=0 to Img.H-1 do Begin
  Cur:=Src+Int64(Y)*Stride;
  If Y>0 Then Prv:=Src+Int64(Y-1)*Stride Else Prv:=Nil;
  Best:=-1;BestF:=FLo;
  For F:=FLo to FHi do Begin
   Sum:=0;
   For X:=0 to Stride-1 do Begin
    If X>=Bpp Then A:=Cur[X-Bpp]Else A:=0;
    If Prv<>Nil Then B:=Prv[X]Else B:=0;
    If(Prv<>Nil)and(X>=Bpp)Then C:=Prv[X-Bpp]Else C:=0;
    Case F of
     0:P:=0;
     1:P:=A;
     2:P:=B;
     3:P:=(A+B)shr 1;
     Else P:=PaethPred(A,B,C);
    End;
    V:=(Cur[X]-P)and $FF;
    Cand[F][X+1]:=V;
    If V>=128 Then Sum:=Sum+(256-V)Else Sum:=Sum+V;
   End;
   If(Best<0)or(Sum<Best)Then Begin Best:=Sum;BestF:=F;End;
  End;
  Cand[BestF][0]:=BestF;
  Move(Cand[BestF]^,(Raw+Int64(Y)*(Stride+1))^,Stride+1);
 End;
 For I:=0 to 4 do FreeMem(Cand[I]);
 Z:=DeflateRaw(Raw,Img.H*(Stride+1),Level,ZLen);
 Ad:=Adler32(Raw,Img.H*(Stride+1));
 FreeMem(Raw);
 If Rgba<>Nil Then FreeMem(Rgba);
 Out_:=PByte(AllocBytes(Int64(ZLen)+1024));
 Out_[0]:=137;Out_[1]:=80;Out_[2]:=78;Out_[3]:=71;Out_[4]:=13;Out_[5]:=10;
 Out_[6]:=26;Out_[7]:=10;
 Pos:=8;
 PutBE32(@Hdr[0],Img.W);PutBE32(@Hdr[4],Img.H);
 Hdr[8]:=8;If Bpp=4 Then Hdr[9]:=6 Else Hdr[9]:=2;Hdr[10]:=0;Hdr[11]:=0;
   Hdr[12]:=0;
 Chunk('IHDR',@Hdr[0],13);
 { IDAT : en-tete zlib + flux deflate + Adler32 }
 Tmp:=PByte(AllocBytes(Int64(ZLen)+16));
 Tmp[0]:=$78;Tmp[1]:=$9C;
 Move(Z^,Tmp[2],ZLen);
 PutBE32(Tmp+2+ZLen,Ad);
 FreeMem(Z);
 Chunk('IDAT',Tmp,ZLen+6);
 FreeMem(Tmp);
 Chunk('IEND',Nil,0);
 PngEncode:=WriteFileBytes(Name,Out_,Pos);
 FreeMem(Out_);
End;

{ ---- BMP ---- }

Function LE16(P:PByte):LongInt;
Begin
 LE16:=P[0]or(P[1]shl 8);
End;

Function LE32(P:PByte):LongInt;
Begin
 LE32:=LongInt(LongWord(P[0])or(LongWord(P[1])shl 8)or(LongWord(P[2])shl 16)or
   (LongWord(P[3])shl 24));
End;

Function BmpDecode(Buf:PByte;N:LongInt;Var Img:TImage;Var Err:AnsiString)
  :Boolean;
Var
 Off,HSize,W,H,Planes,Bits,Comp,NColors,Stride,X,Y,I,PIdx:LongInt;
 TopDown:Boolean;
 Pal:Array[0..255]of LongWord;
 Row:PByte;
 V:LongWord;
 Po:Int64;
 MR,MG,MB,MA:LongWord;

 Function Shift(Mask,V:LongWord):LongInt;
 Var
  S,Bits_:LongInt;
 Begin
  If Mask=0 Then Begin Shift:=0;Exit;End;
  S:=0;
  While(Mask and 1)=0 do Begin Mask:=Mask shr 1;Inc(S);End;
  Bits_:=0;
  While(Mask and 1)<>0 do Begin Mask:=Mask shr 1;Inc(Bits_);End;
  V:=V shr S;
  If Bits_>=8 Then Shift:=V shr(Bits_-8)Else Shift:=(V*255)div((1 shl Bits_)-1);
 End;

Begin
 BmpDecode:=False;
 Err:='';
 If(N<26)or(Buf[0]<>Ord('B'))or(Buf[1]<>Ord('M'))Then Begin
   Err:='BMP invalide';Exit;End;
 Off:=LE32(Buf+10);
 HSize:=LE32(Buf+14);
 If HSize<40 Then Begin Err:='ancien format BMP non g'#130'r'#130;Exit;End;
 W:=LE32(Buf+18);H:=LE32(Buf+22);
 Planes:=LE16(Buf+26);Bits:=LE16(Buf+28);Comp:=LE32(Buf+30);
 NColors:=LE32(Buf+46);
 TopDown:=H<0;
 If TopDown Then H:=-H;
 If(W<=0)or(H<=0)or(Int64(W)*H>400000000)Then Begin
   Err:='dimensions BMP invalides';Exit;End;
 If not(Comp in[0,3])Then Begin Err:='BMP compress'#130' non g'#130'r'#130;
   Exit;End;
 If not(Bits in[1,4,8,24,32])Then Begin
   Err:='profondeur BMP non g'#130'r'#130'e';Exit;End;
 FillChar(Pal,SizeOf(Pal),0);
 If Bits<=8 Then Begin
  If NColors=0 Then NColors:=1 shl Bits;
  If NColors>256 Then NColors:=256;
  For I:=0 to NColors-1 do Pal[I]:=LongWord(LE32(Buf+14+HSize+I*4));
 End;
 MR:=$FF0000;MG:=$FF00;MB:=$FF;MA:=0;
 If(Comp=3)and(HSize>=52)Then Begin
  MR:=LongWord(LE32(Buf+54));MG:=LongWord(LE32(Buf+58));MB:=LongWord(LE32(Buf+
    62));
 End;
 Stride:=((W*Bits+31)div 32)*4;
 If Int64(Off)+Int64(Stride)*H>N Then Begin Err:='BMP tronqu'#130;Exit;End;
 ImgAlloc(Img,W,H,False);
 For Y:=0 to H-1 do Begin
  If TopDown Then Row:=Buf+Off+Int64(Y)*Stride Else Row:=Buf+Off+Int64(H-1-Y)
    *Stride;
  For X:=0 to W-1 do Begin
   Po:=(Int64(Y)*W+X)*3;
   Case Bits of
    24:Begin Img.Px[Po]:=Row[X*3+2];Img.Px[Po+1]:=Row[X*3+1];Img.Px[Po+
      2]:=Row[X*3];End;
    32:Begin
        V:=LongWord(LE32(Row+X*4));
        If Comp=3 Then Begin
         Img.Px[Po]:=Shift(MR,V);Img.Px[Po+1]:=Shift(MG,V);Img.Px[Po+
           2]:=Shift(MB,V);
        End
         Else Begin
          Img.Px[Po]:=Row[X*4+2];Img.Px[Po+1]:=Row[X*4+1];Img.Px[Po+
            2]:=Row[X*4];
         End;
       End;
    8:Begin V:=Pal[Row[X]];Img.Px[Po]:=(V shr 16)and $FF;Img.Px[Po+1]:=(V shr
      8)and $FF;Img.Px[Po+2]:=V and $FF;End;
    4:Begin
       If(X and 1)=0 Then PIdx:=Row[X shr 1]shr 4 Else PIdx:=Row[X shr 1]and 15;
       V:=Pal[PIdx];Img.Px[Po]:=(V shr 16)and $FF;Img.Px[Po+1]:=(V shr 8)and
         $FF;Img.Px[Po+2]:=V and $FF;
      End;
    1:Begin
       PIdx:=(Row[X shr 3]shr(7-(X and 7)))and 1;
       V:=Pal[PIdx];Img.Px[Po]:=(V shr 16)and $FF;Img.Px[Po+1]:=(V shr 8)and
         $FF;Img.Px[Po+2]:=V and $FF;
      End;
   End;
  End;
 End;
 BmpDecode:=True;
End;

Function BmpEncode(Const Name:AnsiString;Const Img:TImage):Boolean;
Var
 Stride,Y,X:LongInt;
 Sz:Int64;
 B:PByte;
 Row:PByte;
 Po:Int64;
Begin
 Stride:=((Img.W*3+3)div 4)*4;
 Sz:=54+Int64(Stride)*Img.H;
 B:=PByte(AllocBytes(Sz));
 B[0]:=Ord('B');B[1]:=Ord('M');
 B[2]:=Sz and $FF;B[3]:=(Sz shr 8)and $FF;B[4]:=(Sz shr 16)and $FF;B[5]:=(Sz shr
   24)and $FF;
 B[10]:=54;B[14]:=40;
 B[18]:=Img.W and $FF;B[19]:=(Img.W shr 8)and $FF;B[20]:=(Img.W shr 16)and $FF;
 B[22]:=Img.H and $FF;B[23]:=(Img.H shr 8)and $FF;B[24]:=(Img.H shr 16)and $FF;
 B[26]:=1;B[28]:=24;
 For Y:=0 to Img.H-1 do Begin
  Row:=B+54+Int64(Img.H-1-Y)*Stride;
  For X:=0 to Img.W-1 do Begin
   Po:=(Int64(Y)*Img.W+X)*3;
   Row[X*3]:=Img.Px[Po+2];Row[X*3+1]:=Img.Px[Po+1];Row[X*3+2]:=Img.Px[Po];
  End;
 End;
 BmpEncode:=WriteFileBytes(Name,B,Sz);
 FreeMem(B);
End;

{ ---- PPM / PGM binaires (P5, P6) ---- }

Function PpmDecode(Buf:PByte;N:LongInt;Var Img:TImage;Var Err:AnsiString)
  :Boolean;
Var
 Pos:LongInt;
 Kind:Char;
 W,H,Mx,I:LongInt;
 Gray:Boolean;

 Function NextInt:LongInt;
 Var
  V:LongInt;
 Begin
  V:=0;
  While Pos<N do Begin
   If Buf[Pos]=Ord('#')Then Begin
    While(Pos<N)and(Buf[Pos]<>10)do Inc(Pos);
   End
    Else If Buf[Pos]in[32,9,10,13]Then Inc(Pos)
    Else Break;
  End;
  While(Pos<N)and(Buf[Pos]>=48)and(Buf[Pos]<=57)do Begin
   V:=V*10+Buf[Pos]-48;
   Inc(Pos);
  End;
  NextInt:=V;
 End;

Begin
 PpmDecode:=False;
 Err:='';
 If(N<3)or(Buf[0]<>Ord('P'))Then Begin Err:='PPM invalide';Exit;End;
 Kind:=Chr(Buf[1]);
 If not(Kind in['5','6'])Then Begin
   Err:='seuls P5 et P6 sont g'#130'r'#130's';Exit;End;
 Gray:=Kind='5';
 Pos:=2;
 W:=NextInt;H:=NextInt;Mx:=NextInt;
 Inc(Pos);
 If(W<=0)or(H<=0)or(Mx<=0)or(Mx>255)Then Begin
   Err:='PPM invalide (8 bits seulement)';Exit;End;
 If Gray Then I:=W*H Else I:=W*H*3;
 If Pos+I>N Then Begin Err:='PPM tronqu'#130;Exit;End;
 ImgAlloc(Img,W,H,False);
 If Gray Then Begin
  For I:=0 to W*H-1 do Begin
   Img.Px[I*3]:=Buf[Pos+I];Img.Px[I*3+1]:=Buf[Pos+I];Img.Px[I*3+2]:=Buf[Pos+I];
  End;
 End
  Else Move(Buf[Pos],Img.Px^,W*H*3);
 PpmDecode:=True;
End;

Function PpmEncode(Const Name:AnsiString;Const Img:TImage):Boolean;
Var
 Hd:AnsiString;
 F:File;
Begin
 PpmEncode:=False;
 Hd:='P6'#10+IStr(Img.W)+' '+IStr(Img.H)+#10'255'#10;
 Assign(F,Name);
 Rewrite(F,1);
 If IOResult<>0 Then Exit;
 BlockWrite(F,Hd[1],Length(Hd));
 BlockWrite(F,Img.Px^,Int64(Img.W)*Img.H*3);
 Close(F);
 PpmEncode:=IOResult=0;
End;

{ ------------------------------------------------------------------ }
{ JPEG : decodeur (de base et progressif) et encodeur (de base)        }
{ ------------------------------------------------------------------ }

Const
 JZig:Array[0..79]of Byte=(
  0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,12,19,26,33,40,48,41,34,27,20,13,6,
  7,14,21,28,35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,58,59,52,45,38,
  31,39,46,53,60,61,54,47,55,62,63,
  63,63,63,63,63,63,63,63,63,63,63,63,63,63,63,63);

Const
 JStdQ0:Array[0..63]of Byte=(
  16,11,12,14,12,10,16,14,13,14,18,17,16,19,24,40,
  26,24,22,22,24,49,35,37,29,40,58,51,61,60,57,51,
  56,55,64,72,92,78,64,68,87,69,55,56,80,109,81,87,
  95,98,103,104,103,62,77,113,121,112,100,120,92,101,103,99
 );
 JStdQ1:Array[0..63]of Byte=(
  17,18,18,24,21,24,47,26,26,47,99,66,56,66,99,99,
  99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,
  99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,
  99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99
 );
 JBitsDcLum:Array[0..15]of Byte=(
  0,1,5,1,1,1,1,1,1,0,0,0,0,0,0,0
 );
 JValsDcLum:Array[0..11]of Byte=(
  0,1,2,3,4,5,6,7,8,9,10,11
 );
 JBitsDcChr:Array[0..15]of Byte=(
  0,3,1,1,1,1,1,1,1,1,1,0,0,0,0,0
 );
 JValsDcChr:Array[0..11]of Byte=(
  0,1,2,3,4,5,6,7,8,9,10,11
 );
 JBitsAcLum:Array[0..15]of Byte=(
  0,2,1,3,3,2,4,3,5,5,4,4,0,0,1,125
 );
 JValsAcLum:Array[0..161]of Byte=(
  1,2,3,0,4,17,5,18,33,49,65,6,19,81,97,7,
  34,113,20,50,129,145,161,8,35,66,177,193,21,82,209,240,
  36,51,98,114,130,9,10,22,23,24,25,26,37,38,39,40,
  41,42,52,53,54,55,56,57,58,67,68,69,70,71,72,73,
  74,83,84,85,86,87,88,89,90,99,100,101,102,103,104,105,
  106,115,116,117,118,119,120,121,122,131,132,133,134,135,136,137,
  138,146,147,148,149,150,151,152,153,154,162,163,164,165,166,167,
  168,169,170,178,179,180,181,182,183,184,185,186,194,195,196,197,
  198,199,200,201,202,210,211,212,213,214,215,216,217,218,225,226,
  227,228,229,230,231,232,233,234,241,242,243,244,245,246,247,248,
  249,250
 );
 JBitsAcChr:Array[0..15]of Byte=(
  0,2,1,2,4,4,3,4,7,5,4,4,0,1,2,119
 );
 JValsAcChr:Array[0..161]of Byte=(
  0,1,2,3,17,4,5,33,49,6,18,65,81,7,97,113,
  19,34,50,129,8,20,66,145,161,177,193,9,35,51,82,240,
  21,98,114,209,10,22,36,52,225,37,241,23,24,25,26,38,
  39,40,41,42,53,54,55,56,57,58,67,68,69,70,71,72,
  73,74,83,84,85,86,87,88,89,90,99,100,101,102,103,104,
  105,106,115,116,117,118,119,120,121,122,130,131,132,133,134,135,
  136,137,138,146,147,148,149,150,151,152,153,154,162,163,164,165,
  166,167,168,169,170,178,179,180,181,182,183,184,185,186,194,195,
  196,197,198,199,200,201,202,210,211,212,213,214,215,216,217,218,
  226,227,228,229,230,231,232,233,234,242,243,244,245,246,247,248,
  249,250
 );


Type
 TJHuff=Record
  MinCode,MaxCode,ValPtr:Array[0..17]of LongInt;
  Vals:Array[0..255]of Byte;
  Fast:Array[0..511]of Word;
  Valid:Boolean;
 End;
 TJComp=Record
  Id,H,V,Tq,Td,Ta:LongInt;
  BlocksW,BlocksH:LongInt;
  NeedBW,NeedBH:LongInt;
  Coef:PSmallInt;
  Pred:LongInt;
  PxW,PxH:LongInt;
  Plane:PByte;
  Stride:LongInt;
 End;

Var
 JD:PByte;
 JN,JP:LongInt;
 JBuf:LongWord;
 JCnt:LongInt;
 JHit:Boolean;
 JW,JH,JNC:LongInt;
 JProg:Boolean;
 JC:Array[0..3]of TJComp;
 JQ:Array[0..3]of Array[0..63]of Word;
 JDC,JAC:Array[0..3]of TJHuff;
 JHmax,JVmax,JMcuX,JMcuY,JRst:LongInt;
 JEob:LongInt;
 JAdobe:LongInt;
 JOrient:LongInt;
 JErr:AnsiString;
 JFrame:Boolean;

Procedure JFill;
Var
 B,C:LongInt;
Begin
 While JCnt<=24 do Begin
  B:=0;
  If not JHit Then Begin
   If JP>=JN Then JHit:=True
   Else Begin
    B:=JD[JP];
    Inc(JP);
    If B=$FF Then Begin
     If JP<JN Then C:=JD[JP]Else C:=$D9;
     If C=0 Then Inc(JP)
     Else Begin
      Dec(JP);
      JHit:=True;
      B:=0;
     End;
    End;
   End;
  End;
  JBuf:=JBuf or(LongWord(B)shl(24-JCnt));
  Inc(JCnt,8);
 End;
End;

Function JGetBits(N:LongInt):LongInt;
Begin
 If N=0 Then Begin JGetBits:=0;Exit;End;
 If JCnt<N Then JFill;
 JGetBits:=LongInt(JBuf shr(32-N));
 JBuf:=JBuf shl N;
 Dec(JCnt,N);
End;

Function JGetBit:LongInt;
Begin
 If JCnt<1 Then JFill;
 JGetBit:=LongInt(JBuf shr 31);
 JBuf:=JBuf shl 1;
 Dec(JCnt);
End;

Function JHuffDec(Var T:TJHuff):LongInt;
Var
 F:Word;
 L,Code:LongInt;
Begin
 If JCnt<16 Then JFill;
 F:=T.Fast[JBuf shr 23];
 If F<>0 Then Begin
  L:=F shr 8;
  JBuf:=JBuf shl L;
  Dec(JCnt,L);
  JHuffDec:=F and 255;
  Exit;
 End;
 For L:=10 to 16 do Begin
  Code:=LongInt(JBuf shr(32-L));
  If Code<=T.MaxCode[L]Then Begin
   JBuf:=JBuf shl L;
   Dec(JCnt,L);
   JHuffDec:=T.Vals[(T.ValPtr[L]+Code-T.MinCode[L])and 255];
   Exit;
  End;
 End;
 JHuffDec:=-1;
 JBuf:=JBuf shl 16;
 Dec(JCnt,16);
End;

Function JExtend(V,T:LongInt):LongInt;
Begin
 If V<(1 shl(T-1))Then JExtend:=V+(-1 shl T)+1 Else JExtend:=V;
End;

Procedure JBuildHuff(Var T:TJHuff;Const Cnt:Array of LongInt;Vals:PByte;
  NV:LongInt);
Var
 L,I,K,Code,Sh:LongInt;
Begin
 FillChar(T,SizeOf(T),0);
 Code:=0;K:=0;
 For L:=1 to 16 do Begin
  T.ValPtr[L]:=K;
  T.MinCode[L]:=Code;
  Inc(K,Cnt[L-1]);
  Inc(Code,Cnt[L-1]);
  If Cnt[L-1]>0 Then T.MaxCode[L]:=Code-1 Else T.MaxCode[L]:=-1;
  Code:=Code shl 1;
 End;
 T.MaxCode[17]:=$7FFFFFFF;
 For I:=0 to NV-1 do T.Vals[I]:=Vals[I];
 For L:=1 to 9 do
  For I:=0 to Cnt[L-1]-1 do Begin
   Code:=T.MinCode[L]+I;
   Sh:=9-L;
   For K:=(Code shl Sh)to((Code shl Sh)+(1 shl Sh)-1)do
    If K<512 Then T.Fast[K]:=(L shl 8)or T.Vals[T.ValPtr[L]+I];
  End;
 T.Valid:=True;
End;

{ bloc de base (sequentiel) }
Procedure JBaseBlock(Var C:TJComp;Blk:PSmallInt);
Var
 T,K,RS,S,R,Diff:LongInt;
Begin
 T:=JHuffDec(JDC[C.Td]);
 If T<0 Then T:=0;
 If T>15 Then T:=15;
 If T>0 Then Diff:=JExtend(JGetBits(T),T)Else Diff:=0;
 Inc(C.Pred,Diff);
 Blk[0]:=C.Pred;
 K:=1;
 While K<64 do Begin
  RS:=JHuffDec(JAC[C.Ta]);
  If RS<0 Then Break;
  S:=RS and 15;
  R:=RS shr 4;
  If S=0 Then Begin
   If R<>15 Then Break;
   Inc(K,16);
  End
   Else Begin
    Inc(K,R);
    If K>63 Then Break;
    Blk[JZig[K]]:=JExtend(JGetBits(S),S);
    Inc(K);
   End;
 End;
End;

Procedure JProgDCFirst(Var C:TJComp;Blk:PSmallInt;Al:LongInt);
Var
 T,Diff:LongInt;
Begin
 T:=JHuffDec(JDC[C.Td]);
 If T<0 Then T:=0;
 If T>15 Then T:=15;
 If T>0 Then Diff:=JExtend(JGetBits(T),T)Else Diff:=0;
 Inc(C.Pred,Diff);
 Blk[0]:=C.Pred*(1 shl Al);
End;

Procedure JProgDCRefine(Blk:PSmallInt;Al:LongInt);
Begin
 If JGetBit<>0 Then Blk[0]:=Blk[0]or(1 shl Al);
End;

Procedure JProgACFirst(Var C:TJComp;Blk:PSmallInt;Ss,Se,Al:LongInt);
Var
 K,RS,S,R:LongInt;
Begin
 If JEob>0 Then Begin Dec(JEob);Exit;End;
 K:=Ss;
 Repeat
  RS:=JHuffDec(JAC[C.Ta]);
  If RS<0 Then Exit;
  S:=RS and 15;
  R:=RS shr 4;
  If S=0 Then Begin
   If R<15 Then Begin
    JEob:=1 shl R;
    If R>0 Then Inc(JEob,JGetBits(R));
    Dec(JEob);
    Break;
   End;
   Inc(K,16);
  End
   Else Begin
    Inc(K,R);
    If K>63 Then Exit;
    Blk[JZig[K]]:=JExtend(JGetBits(S),S)*(1 shl Al);
    Inc(K);
   End;
 Until K>Se;
End;

Procedure JProgACRefine(Var C:TJComp;Blk:PSmallInt;Ss,Se,Al:LongInt);
Var
 K,RS,S,R,Bit:LongInt;
 P:PSmallInt;
Begin
 Bit:=1 shl Al;
 If JEob>0 Then Begin
  Dec(JEob);
  For K:=Ss to Se do Begin
   P:=@Blk[JZig[K]];
   If P^<>0 Then
    If JGetBit<>0 Then
     If(P^ and Bit)=0 Then Begin
      If P^>0 Then P^:=P^+Bit Else P^:=P^-Bit;
     End;
  End;
  Exit;
 End;
 K:=Ss;
 Repeat
  RS:=JHuffDec(JAC[C.Ta]);
  If RS<0 Then Exit;
  S:=RS and 15;
  R:=RS shr 4;
  If S=0 Then Begin
   If R<15 Then Begin
    JEob:=1 shl R;
    If R>0 Then Inc(JEob,JGetBits(R));
    Dec(JEob);
    R:=64;
   End;
  End
   Else Begin
    If JGetBit<>0 Then S:=Bit Else S:=-Bit;
   End;
  While K<=Se do Begin
   P:=@Blk[JZig[K]];
   Inc(K);
   If P^<>0 Then Begin
    If JGetBit<>0 Then
     If(P^ and Bit)=0 Then Begin
      If P^>0 Then P^:=P^+Bit Else P^:=P^-Bit;
     End;
   End
    Else Begin
     If R=0 Then Begin
      P^:=S;
      Break;
     End;
     Dec(R);
    End;
  End;
 Until K>Se;
End;

Procedure JDecodeOne(Var C:TJComp;Blk:PSmallInt;Ss,Se,Ah,Al:LongInt);
Begin
 If not JProg Then JBaseBlock(C,Blk)
 Else If Ss=0 Then Begin
  If Ah=0 Then JProgDCFirst(C,Blk,Al)Else JProgDCRefine(Blk,Al);
 End
  Else Begin
   If Ah=0 Then JProgACFirst(C,Blk,Ss,Se,Al)Else JProgACRefine(C,Blk,Ss,Se,Al);
  End;
End;

{ saute jusqu'au marqueur de redemarrage suivant }
Procedure JRestart;
Var
 I:LongInt;
Begin
 JBuf:=0;JCnt:=0;
 While JP<JN-1 do Begin
  If(JD[JP]=$FF)and(JD[JP+1]>=$D0)and(JD[JP+1]<=$D7)Then Begin
   Inc(JP,2);Break;
  End;
  If(JD[JP]=$FF)and(JD[JP+1]<>0)and(JD[JP+1]<>$FF)Then Break;
  Inc(JP);
 End;
 JHit:=False;
 JEob:=0;
 For I:=0 to JNC-1 do JC[I].Pred:=0;
End;

Function JDecodeScan(Ns:LongInt;Const Sel:Array of LongInt;Ss,Se,Ah,Al:LongInt)
  :Boolean;
Var
 I,MX,MY,BX,BY,V,H,CI,Cnt:LongInt;
 C:^TJComp;
 Blk:PSmallInt;
Begin
 JDecodeScan:=False;
 JBuf:=0;JCnt:=0;JHit:=False;JEob:=0;
 For I:=0 to JNC-1 do JC[I].Pred:=0;
 Cnt:=0;
 If Ns=1 Then Begin
  C:=@JC[Sel[0]];
  For BY:=0 to C^.NeedBH-1 do
   For BX:=0 to C^.NeedBW-1 do Begin
    If(JRst>0)and(Cnt=JRst)Then Begin JRestart;Cnt:=0;End;
    Blk:=C^.Coef+(Int64(BY)*C^.BlocksW+BX)*64;
    JDecodeOne(C^,Blk,Ss,Se,Ah,Al);
    Inc(Cnt);
   End;
 End
  Else Begin
   For MY:=0 to JMcuY-1 do
    For MX:=0 to JMcuX-1 do Begin
     If(JRst>0)and(Cnt=JRst)Then Begin JRestart;Cnt:=0;End;
     For I:=0 to Ns-1 do Begin
      CI:=Sel[I];
      C:=@JC[CI];
      For V:=0 to C^.V-1 do
       For H:=0 to C^.H-1 do Begin
        Blk:=C^.Coef+(Int64(MY*C^.V+V)*C^.BlocksW+MX*C^.H+H)*64;
        JDecodeOne(C^,Blk,Ss,Se,Ah,Al);
       End;
     End;
     Inc(Cnt);
    End;
  End;
 { avance jusqu'au marqueur suivant }
 JBuf:=0;JCnt:=0;
 While JP<JN-1 do Begin
  If(JD[JP]=$FF)and(JD[JP+1]<>0)and(JD[JP+1]<>$FF)and not((JD[JP+1]>=$D0)
    and(JD[JP+1]<=$D7))Then Break;
  Inc(JP);
 End;
 JDecodeScan:=True;
End;

Var
 IdctC:Array[0..7,0..7]of Single;
 IdctReady:Boolean=False;

Procedure IdctInit;
Var
 X,U:LongInt;
 C:Double;
Begin
 If IdctReady Then Exit;
 IdctReady:=True;
 For X:=0 to 7 do
  For U:=0 to 7 do Begin
   If U=0 Then C:=0.35355339059327373 Else C:=0.5;
   IdctC[X,U]:=C*Cos((2*X+1)*U*Pi/16.0);
  End;
End;

Procedure JIdctComp(Var C:TJComp;Const Q:Array of Word);
Var
 BX,BY,I,X,Y,U,Sh:LongInt;
 Blk:PSmallInt;
 InB,Tmp:Array[0..63]of Single;
 S:Single;
 Out_:PByte;
 AcZero:Boolean;
 DcV:LongInt;
Begin
 IdctInit;
 C.Stride:=C.BlocksW*8;
 C.Plane:=PByte(AllocBytes(Int64(C.Stride)*C.BlocksH*8));
 For BY:=0 to C.BlocksH-1 do
  For BX:=0 to C.BlocksW-1 do Begin
   Blk:=C.Coef+(Int64(BY)*C.BlocksW+BX)*64;
   Out_:=C.Plane+Int64(BY)*8*C.Stride+BX*8;
   AcZero:=True;
   For I:=1 to 63 do If Blk[I]<>0 Then Begin AcZero:=False;Break;End;
   If AcZero Then Begin
    DcV:=Round(Blk[0]*Q[0]/8.0)+128;
    If DcV<0 Then DcV:=0 Else If DcV>255 Then DcV:=255;
    For Y:=0 to 7 do FillChar((Out_+Y*C.Stride)^,8,DcV);
    Continue;
   End;
   For I:=0 to 63 do InB[I]:=Blk[I]*Q[I];
   For Y:=0 to 7 do
    For X:=0 to 7 do Begin
     S:=0;
     For U:=0 to 7 do S:=S+IdctC[X,U]*InB[Y*8+U];
     Tmp[Y*8+X]:=S;
    End;
   For X:=0 to 7 do
    For Y:=0 to 7 do Begin
     S:=0;
     For U:=0 to 7 do S:=S+IdctC[Y,U]*Tmp[U*8+X];
     Sh:=Round(S)+128;
     If Sh<0 Then Sh:=0 Else If Sh>255 Then Sh:=255;
     Out_[Y*C.Stride+X]:=Sh;
    End;
  End;
End;

{ plan de composante reechantillonne a la taille de l'image (bilineaire) }
Function JFullPlane(Var C:TJComp):PByte;
Var
 R:PByte;
 X,Y,X0,X1,Y0,Y1:LongInt;
 FX,FY,WX,WY,A,B:Single;
 IX0,IX1:PIntArr;
 WXs:PSingleArr;
 Row0,Row1:PByte;
Begin
 R:=PByte(AllocBytes(Int64(JW)*JH));
 If(C.PxW=JW)and(C.PxH=JH)Then Begin
  For Y:=0 to JH-1 do Move((C.Plane+Int64(Y)*C.Stride)^,(R+Int64(Y)*JW)^,JW);
  JFullPlane:=R;
  Exit;
 End;
 IX0:=PIntArr(AllocBytes(Int64(JW)*4));
 IX1:=PIntArr(AllocBytes(Int64(JW)*4));
 WXs:=PSingleArr(AllocBytes(Int64(JW)*4));
 For X:=0 to JW-1 do Begin
  FX:=(X+0.5)*C.PxW/JW-0.5;
  If FX<0 Then FX:=0;
  X0:=Trunc(FX);
  If X0>C.PxW-1 Then X0:=C.PxW-1;
  X1:=X0+1;
  If X1>C.PxW-1 Then X1:=C.PxW-1;
  IX0[X]:=X0;IX1[X]:=X1;WXs[X]:=FX-X0;
 End;
 For Y:=0 to JH-1 do Begin
  FY:=(Y+0.5)*C.PxH/JH-0.5;
  If FY<0 Then FY:=0;
  Y0:=Trunc(FY);
  If Y0>C.PxH-1 Then Y0:=C.PxH-1;
  Y1:=Y0+1;
  If Y1>C.PxH-1 Then Y1:=C.PxH-1;
  WY:=FY-Y0;
  Row0:=C.Plane+Int64(Y0)*C.Stride;
  Row1:=C.Plane+Int64(Y1)*C.Stride;
  For X:=0 to JW-1 do Begin
   WX:=WXs[X];
   A:=Row0[IX0[X]]*(1-WX)+Row0[IX1[X]]*WX;
   B:=Row1[IX0[X]]*(1-WX)+Row1[IX1[X]]*WX;
   R[Int64(Y)*JW+X]:=Trunc(A*(1-WY)+B*WY+0.5);
  End;
 End;
 FreeMem(IX0);FreeMem(IX1);FreeMem(WXs);
 JFullPlane:=R;
End;

Function JClamp(V:LongInt):LongInt;
Begin
 If V<0 Then JClamp:=0 Else If V>255 Then JClamp:=255 Else JClamp:=V;
End;

{ applique l'orientation EXIF (1..8) }
Procedure ImgOrient(Var I:TImage;O:LongInt);
Var
 N:TImage;
 DX,DY,SX,SY,NW,NH:LongInt;
 Sp,Dp:Int64;
Begin
 If(O<2)or(O>8)Then Exit;
 If O>=5 Then Begin NW:=I.H;NH:=I.W;End Else Begin NW:=I.W;NH:=I.H;End;
 ImgAlloc(N,NW,NH,I.Alpha<>Nil);
 For DY:=0 to NH-1 do
  For DX:=0 to NW-1 do Begin
   Case O of
    2:Begin SX:=I.W-1-DX;SY:=DY;End;
    3:Begin SX:=I.W-1-DX;SY:=I.H-1-DY;End;
    4:Begin SX:=DX;SY:=I.H-1-DY;End;
    5:Begin SX:=DY;SY:=DX;End;
    6:Begin SX:=DY;SY:=I.H-1-DX;End;
    7:Begin SX:=I.W-1-DY;SY:=I.H-1-DX;End;
    Else Begin SX:=I.W-1-DY;SY:=DX;End;
   End;
   Sp:=Int64(SY)*I.W+SX;
   Dp:=Int64(DY)*NW+DX;
   N.Px[Dp*3]:=I.Px[Sp*3];N.Px[Dp*3+1]:=I.Px[Sp*3+1];N.Px[Dp*3+2]:=I.Px[Sp*3+2];
   If I.Alpha<>Nil Then N.Alpha[Dp]:=I.Alpha[Sp];
  End;
 ImgFree(I);
 I:=N;
End;

Procedure JParseExif(P:PByte;Len:LongInt);
Var
 Big:Boolean;
 Off,N,I,Tag:LongInt;

 Function R16(O:LongInt):LongInt;
 Begin
  If(O<0)or(O+2>Len)Then Begin R16:=0;Exit;End;
  If Big Then R16:=(P[O]shl 8)or P[O+1]Else R16:=P[O]or(P[O+1]shl 8);
 End;

 Function R32(O:LongInt):LongInt;
 Begin
  If(O<0)or(O+4>Len)Then Begin R32:=0;Exit;End;
  If Big Then R32:=(P[O]shl 24)or(P[O+1]shl 16)or(P[O+2]shl 8)or P[O+3]
  Else R32:=P[O]or(P[O+1]shl 8)or(P[O+2]shl 16)or(P[O+3]shl 24);
 End;

Begin
 If Len<14 Then Exit;
 If(P[0]<>Ord('E'))or(P[1]<>Ord('x'))or(P[2]<>Ord('i'))or(P[3]<>Ord('f'))
   Then Exit;
 P:=P+6;Dec(Len,6);
 If(P[0]=Ord('M'))and(P[1]=Ord('M'))Then Big:=True
 Else If(P[0]=Ord('I'))and(P[1]=Ord('I'))Then Big:=False
 Else Exit;
 Off:=R32(4);
 N:=R16(Off);
 If N>200 Then Exit;
 For I:=0 to N-1 do Begin
  Tag:=R16(Off+2+I*12);
  If Tag=$0112 Then Begin
   JOrient:=R16(Off+2+I*12+8);
   Exit;
  End;
 End;
End;

Function JpegDecode(Buf:PByte;N:LongInt;Var Img:TImage;Var Err:AnsiString)
  :Boolean;
Var
 M,L,I,J,K,Seg,Pq,Tq,Tc,Th,Ns,Ss,Se,Ah,Al,Id:LongInt;
 Cnt:Array[0..15]of LongInt;
 Sel:Array[0..3]of LongInt;
 Total:LongInt;
 Pl:Array[0..3]of PByte;
 X,Y:LongInt;
 Po:Int64;
 Yy,Cb,Cr,Kk:LongInt;
 RGBMode:Boolean;
Begin
 JpegDecode:=False;
 Err:='';
 JD:=Buf;JN:=N;JP:=0;JProg:=False;JRst:=0;JAdobe:=-1;JOrient:=1;JFrame:=False;
 JW:=0;JH:=0;JNC:=0;
 FillChar(JC,SizeOf(JC),0);
 FillChar(JQ,SizeOf(JQ),0);
 FillChar(JDC,SizeOf(JDC),0);
 FillChar(JAC,SizeOf(JAC),0);
 If(N<4)or(Buf[0]<>$FF)or(Buf[1]<>$D8)Then Begin Err:='JPEG invalide';Exit;End;
 JP:=2;
 While JP<JN do Begin
  If JD[JP]<>$FF Then Begin Inc(JP);Continue;End;
  While(JP<JN)and(JD[JP]=$FF)do Inc(JP);
  If JP>=JN Then Break;
  M:=JD[JP];
  Inc(JP);
  If(M=0)or(M=$D8)or((M>=$D0)and(M<=$D7))or(M=1)Then Continue;
  If M=$D9 Then Break;
  If JP+2>JN Then Break;
  L:=(JD[JP]shl 8)or JD[JP+1];
  If(L<2)or(JP+L>JN)Then Begin
   If M=$DA Then Begin Err:='JPEG tronqu'#130;End;
   Break;
  End;
  Seg:=JP+2;
  Case M of
   $C0,$C1,$C2:Begin
     If JD[Seg]<>8 Then Begin
       Err:='JPEG: seule la pr'#130'cision 8 bits est g'#130'r'#130'e';Exit;End;
     JProg:=M=$C2;
     JH:=(JD[Seg+1]shl 8)or JD[Seg+2];
     JW:=(JD[Seg+3]shl 8)or JD[Seg+4];
     JNC:=JD[Seg+5];
     If(JW<=0)or(JH<=0)or(Int64(JW)*JH>150000000)Then Begin
       Err:='dimensions JPEG invalides';Exit;End;
     If not(JNC in[1,3,4])Then Begin
       Err:='JPEG: nombre de composantes non g'#130'r'#130;Exit;End;
     JHmax:=1;JVmax:=1;
     For I:=0 to JNC-1 do Begin
      JC[I].Id:=JD[Seg+6+I*3];
      JC[I].H:=JD[Seg+7+I*3]shr 4;
      JC[I].V:=JD[Seg+7+I*3]and 15;
      JC[I].Tq:=JD[Seg+8+I*3]and 3;
      If(JC[I].H<1)or(JC[I].H>4)or(JC[I].V<1)or(JC[I].V>4)Then Begin
        Err:='JPEG: facteurs d'#130'chantillonnage invalides';Exit;End;
      If JC[I].H>JHmax Then JHmax:=JC[I].H;
      If JC[I].V>JVmax Then JVmax:=JC[I].V;
     End;
     JMcuX:=(JW+8*JHmax-1)div(8*JHmax);
     JMcuY:=(JH+8*JVmax-1)div(8*JVmax);
     For I:=0 to JNC-1 do Begin
      JC[I].BlocksW:=JMcuX*JC[I].H;
      JC[I].BlocksH:=JMcuY*JC[I].V;
      JC[I].PxW:=(JW*JC[I].H+JHmax-1)div JHmax;
      JC[I].PxH:=(JH*JC[I].V+JVmax-1)div JVmax;
      JC[I].NeedBW:=(JC[I].PxW+7)div 8;
      JC[I].NeedBH:=(JC[I].PxH+7)div 8;
      JC[I].Coef:=PSmallInt(AllocBytes(Int64(JC[I].BlocksW)*JC[I].BlocksH*128));
     End;
     JFrame:=True;
    End;
   $C3,$C5,$C6,$C7,$C9,$CA,$CB,$CD,$CE,$CF:Begin
     Err:='JPEG: mode non g'#130'r'#130' (sans perte, hi'#130'rarchique ou '+
       'arithm'#130'tique)';Exit;
    End;
   $C4:Begin
     I:=Seg;
     While I<JP+L do Begin
      Tc:=JD[I]shr 4;Th:=JD[I]and 15;
      Inc(I);
      Total:=0;
      For J:=0 to 15 do Begin Cnt[J]:=JD[I+J];Inc(Total,Cnt[J]);End;
      Inc(I,16);
      If(Total>256)or(Th>3)or(I+Total>JP+L)Then Begin
        Err:='table de Huffman JPEG invalide';Exit;End;
      If Tc=0 Then JBuildHuff(JDC[Th],Cnt,JD+I,Total)
      Else JBuildHuff(JAC[Th],Cnt,JD+I,Total);
      Inc(I,Total);
     End;
    End;
   $DB:Begin
     I:=Seg;
     While I<JP+L do Begin
      Pq:=JD[I]shr 4;Tq:=JD[I]and 3;
      Inc(I);
      For K:=0 to 63 do Begin
       If Pq=0 Then JQ[Tq][JZig[K]]:=JD[I+K]
       Else JQ[Tq][JZig[K]]:=(JD[I+K*2]shl 8)or JD[I+K*2+1];
      End;
      Inc(I,64*(Pq+1));
     End;
    End;
   $DD:JRst:=(JD[Seg]shl 8)or JD[Seg+1];
   $E1:JParseExif(JD+Seg,L-2);
   $EE:If(L>=14)and(JD[Seg]=Ord('A'))and(JD[Seg+1]=Ord('d'))and(JD[Seg+
     2]=Ord('o'))Then
        JAdobe:=JD[Seg+11];
   $DA:Begin
     If not JFrame Then Begin Err:='JPEG: SOS avant SOF';Exit;End;
     Ns:=JD[Seg];
     If(Ns<1)or(Ns>4)Then Begin Err:='JPEG: scan invalide';Exit;End;
     For I:=0 to Ns-1 do Begin
      Id:=JD[Seg+1+I*2];
      Sel[I]:=-1;
      For J:=0 to JNC-1 do If JC[J].Id=Id Then Sel[I]:=J;
      If Sel[I]<0 Then Begin Err:='JPEG: composante de scan inconnue';Exit;End;
      JC[Sel[I]].Td:=JD[Seg+2+I*2]shr 4;
      JC[Sel[I]].Ta:=JD[Seg+2+I*2]and 15;
      If(JC[Sel[I]].Td>3)or(JC[Sel[I]].Ta>3)Then Begin
        Err:='JPEG: table invalide';Exit;End;
     End;
     Ss:=JD[Seg+1+Ns*2];Se:=JD[Seg+2+Ns*2];
     Ah:=JD[Seg+3+Ns*2]shr 4;Al:=JD[Seg+3+Ns*2]and 15;
     If not JProg Then Begin Ss:=0;Se:=63;Ah:=0;Al:=0;End;
     If Se>63 Then Se:=63;
     JP:=JP+L;
     If not JDecodeScan(Ns,Sel,Ss,Se,Ah,Al)Then Begin
       Err:='JPEG: erreur de d'#130'codage';Exit;End;
     Continue;
    End;
  End;
  JP:=JP+L;
 End;
 If not JFrame Then Begin Err:='JPEG: aucune image';Exit;End;
 { IDCT de chaque composante }
 For I:=0 to JNC-1 do Begin
  JIdctComp(JC[I],JQ[JC[I].Tq]);
  FreeMem(JC[I].Coef);JC[I].Coef:=Nil;
 End;
 For I:=0 to JNC-1 do Pl[I]:=JFullPlane(JC[I]);
 For I:=0 to JNC-1 do Begin FreeMem(JC[I].Plane);JC[I].Plane:=Nil;End;
 ImgAlloc(Img,JW,JH,False);
 RGBMode:=False;
 If(JNC=3)and(JAdobe=0)Then RGBMode:=True;
 If(JNC=3)and(JAdobe<0)and(JC[0].Id=Ord('R'))and(JC[1].Id=Ord('G'))
   and(JC[2].Id=Ord('B'))Then RGBMode:=True;
 For Y:=0 to JH-1 do
  For X:=0 to JW-1 do Begin
   Po:=Int64(Y)*JW+X;
   If JNC=1 Then Begin
    Img.Px[Po*3]:=Pl[0][Po];Img.Px[Po*3+1]:=Pl[0][Po];Img.Px[Po*3+2]:=Pl[0][Po];
   End
    Else Begin
     Yy:=Pl[0][Po];Cb:=Pl[1][Po];Cr:=Pl[2][Po];
     If RGBMode Then Begin
      Img.Px[Po*3]:=Yy;Img.Px[Po*3+1]:=Cb;Img.Px[Po*3+2]:=Cr;
     End
      Else Begin
       I:=JClamp(Yy+Sar(91881*(Cr-128)+32768,16));
       J:=JClamp(Yy-Sar(22554*(Cb-128)+46802*(Cr-128)+32768,16));
       K:=JClamp(Yy+Sar(116130*(Cb-128)+32768,16));
       If JNC=4 Then Begin
        Kk:=Pl[3][Po];
        If JAdobe<0 Then Begin
         I:=(255-I)*(255-Kk)div 255;J:=(255-J)*(255-Kk)div 255;K:=(255-K)
           *(255-Kk)div 255;
        End
         Else Begin
          I:=I*Kk div 255;J:=J*Kk div 255;K:=K*Kk div 255;
         End;
       End;
       Img.Px[Po*3]:=I;Img.Px[Po*3+1]:=J;Img.Px[Po*3+2]:=K;
      End;
    End;
  End;
 For I:=0 to JNC-1 do FreeMem(Pl[I]);
 ImgOrient(Img,JOrient);
 JpegDecode:=True;
End;

{ ---- encodeur JPEG de base (4:4:4) ---- }

Type
 TJEnc=Record
  Buf:PByte;
  Cap,Pos:LongInt;
  Acc:LongWord;
  Cnt:LongInt;
 End;
 TJCodes=Record
  Code:Array[0..255]of Word;
  Size:Array[0..255]of Byte;
 End;

Procedure JEPutByte(Var E:TJEnc;B:LongInt);
Begin
 If E.Pos>=E.Cap Then Begin
  E.Cap:=E.Cap*2;
  ReallocMem(E.Buf,E.Cap);
 End;
 E.Buf[E.Pos]:=B;
 Inc(E.Pos);
End;

Procedure JEPutBits(Var E:TJEnc;V,N:LongInt);
Var
 B:LongInt;
Begin
 If N=0 Then Exit;
 E.Acc:=(E.Acc shl N)or(LongWord(V)and((LongWord(1)shl N)-1));
 Inc(E.Cnt,N);
 While E.Cnt>=8 do Begin
  B:=(E.Acc shr(E.Cnt-8))and $FF;
  JEPutByte(E,B);
  If B=$FF Then JEPutByte(E,0);
  Dec(E.Cnt,8);
 End;
End;

Procedure JEMakeCodes(Var T:TJCodes;Const Bits:Array of Byte;Const Vals:Array of
  Byte);
Var
 L,I,K:LongInt;
 Code:LongInt;
Begin
 FillChar(T,SizeOf(T),0);
 Code:=0;K:=0;
 For L:=1 to 16 do Begin
  For I:=1 to Bits[L-1]do Begin
   T.Code[Vals[K]]:=Code;
   T.Size[Vals[K]]:=L;
   Inc(Code);Inc(K);
  End;
  Code:=Code shl 1;
 End;
End;

Procedure JEPutMarker(Var E:TJEnc;M:LongInt);
Begin
 JEPutByte(E,$FF);JEPutByte(E,M);
End;

Procedure JEPutWord(Var E:TJEnc;V:LongInt);
Begin
 JEPutByte(E,V shr 8);JEPutByte(E,V and $FF);
End;

Function JpegEncode(Const Name:AnsiString;Const Img:TImage;Quality:LongInt)
  :Boolean;
Var
 E:TJEnc;
 QZ:Array[0..1]of Array[0..63]of Byte;
 QN:Array[0..1]of Array[0..63]of Single;
 DcT,AcT:Array[0..1]of TJCodes;
 FC:Array[0..7,0..7]of Single;
 Scale,I,J,K,T,BX,BY,X,Y,Comp,U,V,PX,PY,NbX,NbY:LongInt;
 Pred:Array[0..2]of LongInt;
 Blk:Array[0..63]of Single;
 Tmp:Array[0..63]of Single;
 Qv:Array[0..63]of LongInt;
 S:Single;
 R,G,B:LongInt;
 Po:Int64;
 Yv,Cbv,Crv:Single;
 Samples:Array[0..2]of Array[0..63]of Single;

 Procedure PutHuff(Const Tb:TJCodes;Sym:LongInt);
 Begin
  JEPutBits(E,Tb.Code[Sym],Tb.Size[Sym]);
 End;

 Procedure EncodeBlock(Ci:LongInt);
 Var
  Idx,Z,Diff,Cat,Run,A,V_,X,Y,U:LongInt;
  S:Single;
 Begin
  { FDCT separable }
  For Y:=0 to 7 do
   For U:=0 to 7 do Begin
    S:=0;
    For X:=0 to 7 do S:=S+FC[U,X]*Samples[Ci][Y*8+X];
    Tmp[Y*8+U]:=S;
   End;
  For U:=0 to 7 do
   For V_:=0 to 7 do Begin
    S:=0;
    For Y:=0 to 7 do S:=S+FC[V_,Y]*Tmp[Y*8+U];
    Blk[V_*8+U]:=S;
   End;
  Idx:=0;
  If Ci>0 Then Idx:=1;
  For Z:=0 to 63 do Begin
   V_:=JZig[Z];
   S:=Blk[V_]*QN[Idx][V_];
   If S>=0 Then Qv[Z]:=Trunc(S+0.5)Else Qv[Z]:=-Trunc(-S+0.5);
  End;
  Diff:=Qv[0]-Pred[Ci];
  Pred[Ci]:=Qv[0];
  A:=Abs(Diff);
  Cat:=0;
  While A>0 do Begin Inc(Cat);A:=A shr 1;End;
  PutHuff(DcT[Idx],Cat);
  If Cat>0 Then Begin
   If Diff<0 Then Diff:=Diff-1;
   JEPutBits(E,Diff,Cat);
  End;
  Run:=0;
  For Z:=1 to 63 do Begin
   If Qv[Z]=0 Then Inc(Run)
   Else Begin
    While Run>15 do Begin PutHuff(AcT[Idx],$F0);Dec(Run,16);End;
    A:=Abs(Qv[Z]);
    Cat:=0;
    While A>0 do Begin Inc(Cat);A:=A shr 1;End;
    PutHuff(AcT[Idx],(Run shl 4)or Cat);
    Diff:=Qv[Z];
    If Diff<0 Then Diff:=Diff-1;
    JEPutBits(E,Diff,Cat);
    Run:=0;
   End;
  End;
  If Run>0 Then PutHuff(AcT[Idx],0);
 End;

Begin
 JpegEncode:=False;
 If Quality<1 Then Quality:=1;
 If Quality>100 Then Quality:=100;
 If Quality<50 Then Scale:=5000 div Quality Else Scale:=200-Quality*2;
 For I:=0 to 63 do Begin
  T:=(JStdQ0[I]*Scale+50)div 100;
  If T<1 Then T:=1;If T>255 Then T:=255;
  QZ[0][I]:=T;
  T:=(JStdQ1[I]*Scale+50)div 100;
  If T<1 Then T:=1;If T>255 Then T:=255;
  QZ[1][I]:=T;
 End;
 For I:=0 to 63 do Begin
  QN[0][JZig[I]]:=1.0/QZ[0][I];
  QN[1][JZig[I]]:=1.0/QZ[1][I];
 End;
 JEMakeCodes(DcT[0],JBitsDcLum,JValsDcLum);
 JEMakeCodes(DcT[1],JBitsDcChr,JValsDcChr);
 JEMakeCodes(AcT[0],JBitsAcLum,JValsAcLum);
 JEMakeCodes(AcT[1],JBitsAcChr,JValsAcChr);
 For U:=0 to 7 do
  For X:=0 to 7 do Begin
   If U=0 Then S:=0.35355339059327373 Else S:=0.5;
   FC[U,X]:=S*Cos((2*X+1)*U*Pi/16.0);
  End;
 E.Cap:=Img.W*Img.H+65536;
 E.Buf:=PByte(AllocBytes(E.Cap));
 E.Pos:=0;E.Acc:=0;E.Cnt:=0;
 JEPutMarker(E,$D8);
 JEPutMarker(E,$E0);JEPutWord(E,16);
 JEPutByte(E,Ord('J'));JEPutByte(E,Ord('F'));JEPutByte(E,Ord('I'));
   JEPutByte(E,Ord('F'));JEPutByte(E,0);
 JEPutByte(E,1);JEPutByte(E,1);JEPutByte(E,0);
 JEPutWord(E,1);JEPutWord(E,1);JEPutByte(E,0);JEPutByte(E,0);
 For I:=0 to 1 do Begin
  JEPutMarker(E,$DB);JEPutWord(E,67);JEPutByte(E,I);
  For K:=0 to 63 do JEPutByte(E,QZ[I][K]);
 End;
 JEPutMarker(E,$C0);JEPutWord(E,17);JEPutByte(E,8);
 JEPutWord(E,Img.H);JEPutWord(E,Img.W);JEPutByte(E,3);
 JEPutByte(E,1);JEPutByte(E,$11);JEPutByte(E,0);
 JEPutByte(E,2);JEPutByte(E,$11);JEPutByte(E,1);
 JEPutByte(E,3);JEPutByte(E,$11);JEPutByte(E,1);
 For I:=0 to 3 do Begin
  JEPutMarker(E,$C4);
  Case I of
   0:Begin JEPutWord(E,19+12);JEPutByte(E,$00);For K:=0 to 15 do
     JEPutByte(E,JBitsDcLum[K]);For K:=0 to 11 do JEPutByte(E,JValsDcLum[K]);
     End;
   1:Begin JEPutWord(E,19+162);JEPutByte(E,$10);For K:=0 to 15 do
     JEPutByte(E,JBitsAcLum[K]);For K:=0 to 161 do JEPutByte(E,JValsAcLum[K])
     ;End;
   2:Begin JEPutWord(E,19+12);JEPutByte(E,$01);For K:=0 to 15 do
     JEPutByte(E,JBitsDcChr[K]);For K:=0 to 11 do JEPutByte(E,JValsDcChr[K]);
     End;
   Else Begin JEPutWord(E,19+162);JEPutByte(E,$11);For K:=0 to 15 do
     JEPutByte(E,JBitsAcChr[K]);For K:=0 to 161 do JEPutByte(E,JValsAcChr[K])
     ;End;
  End;
 End;
 JEPutMarker(E,$DA);JEPutWord(E,12);JEPutByte(E,3);
 JEPutByte(E,1);JEPutByte(E,$00);
 JEPutByte(E,2);JEPutByte(E,$11);
 JEPutByte(E,3);JEPutByte(E,$11);
 JEPutByte(E,0);JEPutByte(E,63);JEPutByte(E,0);
 Pred[0]:=0;Pred[1]:=0;Pred[2]:=0;
 NbX:=(Img.W+7)div 8;NbY:=(Img.H+7)div 8;
 For BY:=0 to NbY-1 do
  For BX:=0 to NbX-1 do Begin
   For Y:=0 to 7 do
    For X:=0 to 7 do Begin
     PX:=BX*8+X;PY:=BY*8+Y;
     If PX>=Img.W Then PX:=Img.W-1;
     If PY>=Img.H Then PY:=Img.H-1;
     Po:=(Int64(PY)*Img.W+PX)*3;
     R:=Img.Px[Po];G:=Img.Px[Po+1];B:=Img.Px[Po+2];
     Yv:=0.299*R+0.587*G+0.114*B;
     Cbv:=-0.168736*R-0.331264*G+0.5*B;
     Crv:=0.5*R-0.418688*G-0.081312*B;
     Samples[0][Y*8+X]:=Yv-128;
     Samples[1][Y*8+X]:=Cbv;
     Samples[2][Y*8+X]:=Crv;
    End;
   For Comp:=0 to 2 do EncodeBlock(Comp);
  End;
 If E.Cnt>0 Then JEPutBits(E,$7F,8-E.Cnt);
 JEPutMarker(E,$D9);
 JpegEncode:=WriteFileBytes(Name,E.Buf,E.Pos);
 FreeMem(E.Buf);
End;

{ ---- chargement et enregistrement selon le format ---- }

Function ImgLoad(Const Name:AnsiString;Var Img:TImage;Var Err:AnsiString)
  :Boolean;
Var
 Buf:PByte;
 N:LongInt;
Begin
 ImgLoad:=False;
 Img.Px:=Nil;Img.Alpha:=Nil;Img.W:=0;Img.H:=0;
 If not FileExistsP(Name)Then Begin Err:='fichier introuvable : '+Name;Exit;End;
 If not ReadFileBytes(Name,Buf,N)Then Begin Err:='lecture impossible : '+
   Name;Exit;End;
 If(N>=2)and(Buf[0]=$FF)and(Buf[1]=$D8)Then ImgLoad:=JpegDecode(Buf,N,Img,Err)
 Else If(N>=8)and(Buf[0]=137)and(Buf[1]=80)Then ImgLoad:=PngDecode(Buf,N,Img,
   Err)
 Else If(N>=2)and(Buf[0]=Ord('B'))and(Buf[1]=Ord('M'))Then
   ImgLoad:=BmpDecode(Buf,N,Img,Err)
 Else If(N>=2)and(Buf[0]=Ord('P'))and(Buf[1]in[Ord('5'),Ord('6')])Then
   ImgLoad:=PpmDecode(Buf,N,Img,Err)
 Else If(N>=12)and(Buf[0]=Ord('R'))and(Buf[8]=Ord('W'))and(Buf[9]=Ord('E'))Then
  Err:='le format WebP n''est pas g'#130'r'#130' (utilisez JPEG, PNG, BMP ou '+
    'PPM)'
 Else If(N>=3)and(Buf[0]=Ord('G'))and(Buf[1]=Ord('I'))and(Buf[2]=Ord('F'))Then
  Err:='le format GIF n''est pas g'#130'r'#130' (utilisez JPEG, PNG, BMP ou '+
    'PPM)'
 Else Err:='format d''image inconnu : '+Name;
 FreeMem(Buf);
 If(Err<>'')Then ImgLoad:=False;
End;

Function ImgSave(Const Name:AnsiString;Const Img:TImage;Quality:LongInt)
  :Boolean;
Var
 E:AnsiString;
Begin
 E:=PathExt(Name);
 If(E='.jpg')or(E='.jpeg')Then ImgSave:=JpegEncode(Name,Img,Quality)
 Else If E='.bmp' Then ImgSave:=BmpEncode(Name,Img)
 Else If(E='.ppm')Then ImgSave:=PpmEncode(Name,Img)
 Else Begin
  If Quality>=90 Then ImgSave:=PngEncode(Name,Img,6)
  Else ImgSave:=PngEncode(Name,Img,3);
 End;
End;

{ ------------------------------------------------------------------ }
{ Fils d'execution (Windows : CreateThread, Unix : pthread)           }
{ ------------------------------------------------------------------ }

{$IFDEF WINDOWS}
Function
  CreateThread(Attr:Pointer;Stack:PtrUInt;Start:Pointer;Param:Pointer;
    Flags:LongWord;Var Tid:LongWord):PtrUInt;
 stdcall;external 'kernel32.dll' name 'CreateThread';
Function WaitForSingleObject(H:PtrUInt;Ms:LongWord):LongWord;stdcall;external
  'kernel32.dll' name 'WaitForSingleObject';
Function CloseHandle(H:PtrUInt):LongInt;stdcall;external 'kernel32.dll' name
  'CloseHandle';
{$ELSE}
 {$IFDEF UNIX}
Function pthread_create(Var
  Th:PtrUInt;Attr:Pointer;Start:Pointer;Arg:Pointer):LongInt;cdecl;
 external 'pthread' name 'pthread_create';
Function pthread_join(Th:PtrUInt;Ret:Pointer):LongInt;cdecl;external 'pthread'
  name 'pthread_join';
Function sysconf(Name:LongInt):PtrInt;cdecl;external 'c' name 'sysconf';
 {$ENDIF}
{$ENDIF}

Const
 MaxThreads=32;

Type
 { traitement d'une plage [Lo,Hi[ par le fil Tid }
 TParProc=Procedure(Ctx:Pointer;Lo,Hi,Tid:LongInt);

Var
 GNThreads:LongInt=1;
 ParProc:TParProc;
 ParCtx:Pointer;
 ParCount,ParChunk,ParNext:LongInt;

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
 If CpuCount>MaxThreads Then CpuCount:=MaxThreads;
End;

Procedure ParWorker(Tid:LongInt);
Var
 C,Lo,Hi:LongInt;
Begin
 While True do Begin
  C:=InterLockedIncrement(ParNext)-1;
  Lo:=C*ParChunk;
  If Lo>=ParCount Then Break;
  Hi:=Lo+ParChunk;
  If Hi>ParCount Then Hi:=ParCount;
  ParProc(ParCtx,Lo,Hi,Tid);
 End;
End;

{$IFDEF WINDOWS}
Function ParThreadEntry(P:Pointer):LongWord;stdcall;
Begin
 ParWorker(PtrInt(P));
 ParThreadEntry:=0;
End;
{$ELSE}
 {$IFDEF UNIX}
Function ParThreadEntry(P:Pointer):Pointer;cdecl;
Begin
 ParWorker(PtrInt(P));
 ParThreadEntry:=Nil;
End;
 {$ENDIF}
{$ENDIF}

{ execute Proc sur [0,Count[ en parallele, par paquets de Chunk elements ;
  Proc ne doit utiliser que de la memoire deja allouee (pas de tas, pas d'E/S) }
Procedure ParFor(Count,Chunk:LongInt;Proc:TParProc;Ctx:Pointer);
Var
 I,Created,NT:LongInt;
 {$IFDEF WINDOWS}
 Hs:Array[0..MaxThreads-1]of PtrUInt;
 Tid:LongWord;
 {$ELSE}
 Ths:Array[0..MaxThreads-1]of PtrUInt;
 Okay:Array[0..MaxThreads-1]of Boolean;
 {$ENDIF}
Begin
 If Count<=0 Then Exit;
 If Chunk<1 Then Chunk:=1;
 NT:=GNThreads;
 If NT>(Count+Chunk-1)div Chunk Then NT:=(Count+Chunk-1)div Chunk;
 If NT<=1 Then Begin
  Proc(Ctx,0,Count,0);
  Exit;
 End;
 ParProc:=Proc;ParCtx:=Ctx;ParCount:=Count;ParChunk:=Chunk;ParNext:=0;
 Created:=0;
 {$IFDEF WINDOWS}
 For I:=1 to NT-1 do Begin
  Hs[I]:=CreateThread(Nil,0,@ParThreadEntry,Pointer(PtrInt(I)),0,Tid);
  If Hs[I]<>0 Then Inc(Created);
 End;
 ParWorker(0);
 For I:=1 to NT-1 do If Hs[I]<>0 Then Begin
  WaitForSingleObject(Hs[I],$FFFFFFFF);
  CloseHandle(Hs[I]);
 End;
 {$ELSE}
  {$IFDEF UNIX}
 For I:=1 to NT-1 do Begin
  Ths[I]:=0;
  Okay[I]:=pthread_create(Ths[I],Nil,@ParThreadEntry,Pointer(PtrInt(I)))=0;
  If Okay[I]Then Inc(Created);
 End;
 ParWorker(0);
 For I:=1 to NT-1 do If Okay[I]Then pthread_join(Ths[I],Nil);
  {$ELSE}
 ParWorker(0);
  {$ENDIF}
 {$ENDIF}
End;

{ ------------------------------------------------------------------ }
{ Produit matriciel (CPU, multi-fils)                                 }
{   Y[n*M+m] = somme_k X[n*K+k] * W[m*K+k] (+ Bias[m])                 }
{ ------------------------------------------------------------------ }

Type
 TGemmCtx=Record
  X,W,B,Y:PSingle;
  N,K,M:LongInt;
 End;
 PGemmCtx=^TGemmCtx;

Procedure GemmBlock(X,W,B,Y:PSingle;K,M,N0,N1:LongInt);
Var
 N,Mm,J:LongInt;
 X0,X1,W0,W1,W2,W3:PSingle;
 S00,S01,S02,S03,S10,S11,S12,S13,A0,A1:Single;
 Bv:Single;
Begin
 N:=N0;
 While N+1<N1 do Begin
  X0:=X+Int64(N)*K;
  X1:=X0+K;
  Mm:=0;
  While Mm+3<M do Begin
   W0:=W+Int64(Mm)*K;
   W1:=W0+K;W2:=W1+K;W3:=W2+K;
   S00:=0;S01:=0;S02:=0;S03:=0;S10:=0;S11:=0;S12:=0;S13:=0;
   For J:=0 to K-1 do Begin
    A0:=X0[J];A1:=X1[J];
    S00:=S00+A0*W0[J];S01:=S01+A0*W1[J];S02:=S02+A0*W2[J];S03:=S03+A0*W3[J];
    S10:=S10+A1*W0[J];S11:=S11+A1*W1[J];S12:=S12+A1*W2[J];S13:=S13+A1*W3[J];
   End;
   If B<>Nil Then Begin
    S00:=S00+B[Mm];S01:=S01+B[Mm+1];S02:=S02+B[Mm+2];S03:=S03+B[Mm+3];
    S10:=S10+B[Mm];S11:=S11+B[Mm+1];S12:=S12+B[Mm+2];S13:=S13+B[Mm+3];
   End;
   Y[Int64(N)*M+Mm]:=S00;Y[Int64(N)*M+Mm+1]:=S01;Y[Int64(N)*M+Mm+2]:=S02;
   Y[Int64(N)*M+Mm+3]:=S03;
   Y[Int64(N+1)*M+Mm]:=S10;Y[Int64(N+1)*M+Mm+1]:=S11;Y[Int64(N+1)*M+Mm+2]:=S12;
   Y[Int64(N+1)*M+Mm+3]:=S13;
   Inc(Mm,4);
  End;
  While Mm<M do Begin
   W0:=W+Int64(Mm)*K;
   S00:=0;S10:=0;
   For J:=0 to K-1 do Begin
    S00:=S00+X0[J]*W0[J];
    S10:=S10+X1[J]*W0[J];
   End;
   If B<>Nil Then Bv:=B[Mm]Else Bv:=0;
   Y[Int64(N)*M+Mm]:=S00+Bv;
   Y[Int64(N+1)*M+Mm]:=S10+Bv;
   Inc(Mm);
  End;
  Inc(N,2);
 End;
 If N<N1 Then Begin
  X0:=X+Int64(N)*K;
  Mm:=0;
  While Mm+3<M do Begin
   W0:=W+Int64(Mm)*K;
   W1:=W0+K;W2:=W1+K;W3:=W2+K;
   S00:=0;S01:=0;S02:=0;S03:=0;
   For J:=0 to K-1 do Begin
    A0:=X0[J];
    S00:=S00+A0*W0[J];S01:=S01+A0*W1[J];S02:=S02+A0*W2[J];S03:=S03+A0*W3[J];
   End;
   If B<>Nil Then Begin
    S00:=S00+B[Mm];S01:=S01+B[Mm+1];S02:=S02+B[Mm+2];S03:=S03+B[Mm+3];
   End;
   Y[Int64(N)*M+Mm]:=S00;Y[Int64(N)*M+Mm+1]:=S01;Y[Int64(N)*M+Mm+2]:=S02;
   Y[Int64(N)*M+Mm+3]:=S03;
   Inc(Mm,4);
  End;
  While Mm<M do Begin
   W0:=W+Int64(Mm)*K;
   S00:=0;
   For J:=0 to K-1 do S00:=S00+X0[J]*W0[J];
   If B<>Nil Then S00:=S00+B[Mm];
   Y[Int64(N)*M+Mm]:=S00;
   Inc(Mm);
  End;
 End;
End;

Procedure GemmProc(Ctx:Pointer;Lo,Hi,Tid:LongInt);
Begin
 With PGemmCtx(Ctx)^ do GemmBlock(X,W,B,Y,K,M,Lo,Hi);
End;

Procedure GemmCPU(X,W,B,Y:PSingle;N,K,M:LongInt);
Var
 C:TGemmCtx;
Begin
 C.X:=X;C.W:=W;C.B:=B;C.Y:=Y;C.N:=N;C.K:=K;C.M:=M;
 ParFor(N,8,@GemmProc,@C);
End;

{ ------------------------------------------------------------------ }
{ GPU : shader de calcul Direct3D 11 (HLSL compile a l'execution).     }
{ Windows seulement ; sans GPU le calcul reste sur le microprocesseur.  }
{ Le resultat du GPU est verifie au demarrage contre le calcul CPU.    }
{ ------------------------------------------------------------------ }

Type
 TGpuDev=Record
  Name:AnsiString;
  Adapter:Pointer;
  Vendor:LongWord;
  VRam,Free:Int64;
 End;

Var
 GpuDevs:Array of TGpuDev;
 GpuEnumDone:Boolean=False;
 GpuOn:Boolean=False;
 GpuName:AnsiString='';
 GpuCalls:LongInt=0;
 GpuBytes:Int64=0;

{$IFDEF WINDOWS}
Const
 GpuMaxIO=67108864;
 GpuMinWork=262144;

Type
 TGuid4=Record
  D1:LongWord;D2,D3:Word;D4:Array[0..7]of Byte;
 End;
 TVTab=Array[0..255]of Pointer;
 PVTab=^TVTab;
 TAdapterDesc=Record
  Descr:Array[0..127]of Word;
  Vendor,Device,SubSys,Rev:LongWord;
  DedVid,DedSys,Shared:PtrUInt;
  LuidLo:LongWord;LuidHi:LongInt;
  Pad:Array[0..7]of LongWord;
 End;
 TVideoMemInfo=Record
  Budget,CurrentUsage,AvailRes,CurrentRes:QWord;
 End;
 TMapped=Record
  Data:Pointer;
  RowPitch,DepthPitch:LongWord;
 End;
 TBufDesc=Record
  ByteWidth,Usage,BindFlags,CPUAccess,Misc,Stride:LongWord;
 End;
 TViewDesc=Record
  Format,Dim,First,Num,Flags:LongWord;
  Pad:Array[0..11]of LongWord;
 End;
 TSubData=Record
  Mem:Pointer;
  Pitch,Slice:LongWord;
 End;
 TBox=Record
  Left,Top,Front,Right,Bottom,Back:LongWord;
 End;
 TCBData=Record
  K,M,N,Pad:LongWord;
 End;
 TGpuWeight=Record
  Ptr:Pointer;
  Srv:Pointer;
  Buf:Pointer;
  Bytes:Int64;
 End;

 TFnCreateDev=Function(Adapter:Pointer;DrvType:LongWord;Soft:PtrUInt;
   Flags:LongWord;FL:Pointer;NFL:LongWord;
  Sdk:LongWord;Var Dev:Pointer;Var FLOut:LongWord;Var
    Ctx:Pointer):LongInt;stdcall;
 TFnCompile=Function(Src:Pointer;SrcLen:PtrUInt;Name:PChar;Defs,
   Inc:Pointer;Entry,Target:PChar;F1,F2:LongWord;
  Var Code:Pointer;Var Err:Pointer):LongInt;stdcall;
 TFnFactory=Function(Iid:Pointer;Var F:Pointer):LongInt;stdcall;
 TMQuery=Function(Self,Iid:Pointer;Var Obj:Pointer):LongInt;stdcall;
 TMRelease=Function(Self:Pointer):LongWord;stdcall;
 TMEnumAdapters=Function(Self:Pointer;Idx:LongWord;Var
   Ad:Pointer):LongInt;stdcall;
 TMGetDesc=Function(Self:Pointer;Var D:TAdapterDesc):LongInt;stdcall;
 TMQueryMem=Function(Self:Pointer;Node,Seg:LongWord;Var
   Info:TVideoMemInfo):LongInt;stdcall;
 TMCreateBuffer=Function(Self,Desc,Init:Pointer;Var
   Buf:Pointer):LongInt;stdcall;
 TMCreateView=Function(Self,Res,Desc:Pointer;Var V:Pointer):LongInt;stdcall;
 TMCreateCS=Function(Self,Code:Pointer;Len:PtrUInt;Link:Pointer;Var
   Sh:Pointer):LongInt;stdcall;
 TMMap=Function(Self,Res:Pointer;Sub,MType,MFlags:LongWord;Var
   Mapped:TMapped):LongInt;stdcall;
 TMUnmap=Procedure(Self,Res:Pointer;Sub:LongWord);stdcall;
 TMDispatch=Procedure(Self:Pointer;X,Y,Z:LongWord);stdcall;
 TMCopyRegion=Procedure(Self,Dst:Pointer;DstSub,DX,DY,DZ:LongWord;Src:Pointer;
   SrcSub:LongWord;Box:Pointer);stdcall;
 TMUpdate=Procedure(Self,Dst:Pointer;Sub:LongWord;Box,Data:Pointer;RP,
   DP:LongWord);stdcall;
 TMSetSRV=Procedure(Self:Pointer;Start,Num:LongWord;Views:Pointer);stdcall;
 TMSetUAV=Procedure(Self:Pointer;Start,Num:LongWord;Views,
   Counts:Pointer);stdcall;
 TMSetShader=Procedure(Self,Sh,Inst:Pointer;N:LongWord);stdcall;
 TMSetCB=Procedure(Self:Pointer;Start,Num:LongWord;Bufs:Pointer);stdcall;
 TMBlobPtr=Function(Self:Pointer):Pointer;stdcall;
 TMBlobSize=Function(Self:Pointer):PtrUInt;stdcall;

Function LoadLibraryA(Name:PChar):PtrUInt;stdcall;external 'kernel32.dll' name
  'LoadLibraryA';
Function GetProcAddress(H:PtrUInt;Name:PChar):Pointer;stdcall;external
  'kernel32.dll' name 'GetProcAddress';

Var
 GFactory:Pointer=Nil;
 GDev,GCtx:Pointer;
 GShGemm:Pointer;
 GCB,GXBuf,GXSrv,GYBuf,GYUav,GYStage:Pointer;
 GXCap,GYCap:LongInt;
 GWeights:Array of TGpuWeight;
 GNW:LongInt=0;
 GWBytes:Int64=0;

Function VTab(Obj:Pointer;I:LongInt):Pointer;
Begin
 VTab:=PVTab(PPointer(Obj)^)^[I];
End;

Procedure ComRelease(Obj:Pointer);
Begin
 If Obj<>Nil Then TMRelease(VTab(Obj,2))(Obj);
End;

Procedure GpuEnumDevices;
Const
 IID_Factory:TGuid4=(D1:$7b7166ec;D2:$21c7;D3:$44ae;D4:($b2,$1a,$c9,$ae,$32,$1a,
   $e3,$69));
 IID_Adapter3:TGuid4=(D1:$645967A4;D2:$1392;D3:$4310;D4:($A7,$98,$80,$53,$CE,
   $3E,$93,$FD));
Var
 H:PtrUInt;
 Fn:TFnFactory;
 Ad,Ad3:Pointer;
 I:LongInt;
 D:TAdapterDesc;
 Info:TVideoMemInfo;
 N:LongInt;
 S:AnsiString;
 J:LongInt;
Begin
 If GpuEnumDone Then Exit;
 GpuEnumDone:=True;
 SetLength(GpuDevs,0);
 H:=LoadLibraryA('dxgi.dll');
 If H=0 Then Exit;
 Fn:=TFnFactory(GetProcAddress(H,'CreateDXGIFactory'));
 If not Assigned(Fn)Then Exit;
 If Fn(@IID_Factory,GFactory)<0 Then Exit;
 I:=0;
 While TMEnumAdapters(VTab(GFactory,7))(GFactory,I,Ad)>=0 do Begin
  FillChar(D,SizeOf(D),0);
  If TMGetDesc(VTab(Ad,8))(Ad,D)>=0 Then Begin
   If D.Vendor<>$1414 Then Begin
    N:=Length(GpuDevs);
    SetLength(GpuDevs,N+1);
    S:='';
    For J:=0 to 127 do Begin
     If D.Descr[J]=0 Then Break;
     If D.Descr[J]<128 Then S:=S+Chr(D.Descr[J])Else S:=S+'?';
    End;
    GpuDevs[N].Name:=S;
    GpuDevs[N].Adapter:=Ad;
    GpuDevs[N].Vendor:=D.Vendor;
    GpuDevs[N].VRam:=D.DedVid;
    GpuDevs[N].Free:=D.DedVid;
    Ad3:=Nil;
    If TMQuery(VTab(Ad,0))(Ad,@IID_Adapter3,Ad3)>=0 Then Begin
     FillChar(Info,SizeOf(Info),0);
     If TMQueryMem(VTab(Ad3,14))(Ad3,0,0,Info)>=0 Then Begin
      GpuDevs[N].Free:=Int64(Info.Budget)-Int64(Info.CurrentUsage);
      If GpuDevs[N].Free<0 Then GpuDevs[N].Free:=0;
      If Int64(Info.Budget)>GpuDevs[N].VRam Then GpuDevs[N].VRam:=Info.Budget;
     End;
     ComRelease(Ad3);
    End;
   End;
  End;
  Inc(I);
 End;
End;

Function GpuMakeBuffer(ByteWidth,Usage,Bind,CPU,Misc:LongWord;Init:Pointer;Var
  Buf:Pointer):Boolean;
Var
 D:TBufDesc;
 SD:TSubData;
 P:Pointer;
Begin
 D.ByteWidth:=ByteWidth;D.Usage:=Usage;D.BindFlags:=Bind;D.CPUAccess:=CPU;
   D.Misc:=Misc;D.Stride:=0;
 P:=Nil;
 If Init<>Nil Then Begin
  SD.Mem:=Init;SD.Pitch:=0;SD.Slice:=0;
  P:=@SD;
 End;
 Buf:=Nil;
 GpuMakeBuffer:=TMCreateBuffer(VTab(GDev,3))(GDev,@D,P,Buf)>=0;
End;

Function GpuMakeSRV(Buf:Pointer;NumDwords:LongWord;Var V:Pointer):Boolean;
Var
 D:TViewDesc;
Begin
 FillChar(D,SizeOf(D),0);
 D.Format:=39;D.Dim:=11;D.First:=0;D.Num:=NumDwords;D.Flags:=1;
 V:=Nil;
 GpuMakeSRV:=TMCreateView(VTab(GDev,7))(GDev,Buf,@D,V)>=0;
End;

Function GpuMakeUAV(Buf:Pointer;NumDwords:LongWord;Var V:Pointer):Boolean;
Var
 D:TViewDesc;
Begin
 FillChar(D,SizeOf(D),0);
 D.Format:=39;D.Dim:=1;D.First:=0;D.Num:=NumDwords;D.Flags:=1;
 V:=Nil;
 GpuMakeUAV:=TMCreateView(VTab(GDev,8))(GDev,Buf,@D,V)>=0;
End;

Function GpuCompile(Const Src,Entry:AnsiString;Var Sh:Pointer;Var
  Err:AnsiString):Boolean;
Var
 H:PtrUInt;
 Fn:TFnCompile;
 Code,EMsg:Pointer;
 R:LongInt;
Begin
 GpuCompile:=False;
 Sh:=Nil;
 H:=LoadLibraryA('d3dcompiler_47.dll');
 If H=0 Then Begin Err:='d3dcompiler_47.dll introuvable';Exit;End;
 Fn:=TFnCompile(GetProcAddress(H,'D3DCompile'));
 If not Assigned(Fn)Then Begin Err:='D3DCompile introuvable';Exit;End;
 Code:=Nil;EMsg:=Nil;
 R:=Fn(PChar(Src),Length(Src),'vton',Nil,Nil,PChar(Entry),'cs_5_0',1 shl 15,0,
   Code,EMsg);
 If R<0 Then Begin
  Err:='compilation du shader '+Entry+' impossible';
  If EMsg<>Nil Then Err:=Err+' : '+PChar(TMBlobPtr(VTab(EMsg,3))(EMsg));
  Exit;
 End;
 R:=TMCreateCS(VTab(GDev,18))(GDev,TMBlobPtr(VTab(Code,3))(Code),
   TMBlobSize(VTab(Code,4))(Code),Nil,Sh);
 ComRelease(Code);
 If R<0 Then Begin Err:='cr'#130'ation du shader '+Entry+' impossible';Exit;End;
 GpuCompile:=True;
End;

{ Y[n][m] = somme_k X[n][k] * W[m][k] ; tuiles de 16 x 16 }
Const
 GpuShaderSrc=
  'cbuffer C : register(b0) { uint K; uint M; uint N; uint Pad; };'#10
+  'ByteAddressBuffer W : register(t0);'#10
+  'ByteAddressBuffer X : register(t1);'#10
+  'RWByteAddressBuffer Y : register(u0);'#10
+  'groupshared float As[16][16];'#10
+  'groupshared float Bs[16][16];'#10
+  '[numthreads(16, 16, 1)]'#10
+  'void CSGemm(uint3 gid : SV_GroupID, uint3 tid : SV_GroupThreadID)'#10
+  '{'#10
+  '  uint col = gid.x * 16 + tid.x;'#10
+  '  uint row = gid.y * 16 + tid.y;'#10
+  '  uint wr = gid.x * 16 + tid.y;'#10
+  '  float acc = 0.0f;'#10
+  '  for (uint k0 = 0; k0 < K; k0 += 16)'#10
+  '  {'#10
+  '    uint ka = k0 + tid.x;'#10
+  '    float av = 0.0f;'#10
+  '    float bv = 0.0f;'#10
+  '    if (row < N && ka < K) av = asfloat(X.Load((row * K + ka) * 4));'#10
+  '    if (wr < M && ka < K) bv = asfloat(W.Load((wr * K + ka) * 4));'#10
+  '    As[tid.y][tid.x] = av;'#10
+  '    Bs[tid.y][tid.x] = bv;'#10
+  '    GroupMemoryBarrierWithGroupSync();'#10
+  '    [unroll] for (uint kk = 0; kk < 16; kk++)'#10
+  '      acc += As[tid.y][kk] * Bs[tid.x][kk];'#10
+  '    GroupMemoryBarrierWithGroupSync();'#10
+  '  }'#10
+  '  if (row < N && col < M) Y.Store((row * M + col) * 4, asuint(acc));'#10
+  '}'#10;

Function GpuInitDevice(Idx:LongInt;Var Err:AnsiString):Boolean;
Var
 H:PtrUInt;
 Fn:TFnCreateDev;
 FLv:LongWord;
 FLs:LongWord;
Begin
 GpuInitDevice:=False;
 H:=LoadLibraryA('d3d11.dll');
 If H=0 Then Begin Err:='d3d11.dll introuvable';Exit;End;
 Fn:=TFnCreateDev(GetProcAddress(H,'D3D11CreateDevice'));
 If not Assigned(Fn)Then Begin Err:='D3D11CreateDevice introuvable';Exit;End;
 FLv:=$B000;   { D3D_FEATURE_LEVEL_11_0 }
 GDev:=Nil;GCtx:=Nil;
 If Fn(GpuDevs[Idx].Adapter,0,0,0,@FLv,1,7,GDev,FLs,GCtx)<0 Then Begin
  Err:='cr'#130'ation du p'#130'riph'#130'rique Direct3D 11 impossible';Exit;
 End;
 If not GpuCompile(GpuShaderSrc,'CSGemm',GShGemm,Err)Then Exit;
 If not GpuMakeBuffer(16,0,4,0,0,Nil,GCB)Then Begin
   Err:='cr'#130'ation du tampon constant impossible';Exit;End;
 GXCap:=0;GYCap:=0;
 GpuInitDevice:=True;
End;

Function GpuEnsureIO(XBytes,YBytes:LongInt):Boolean;
Begin
 GpuEnsureIO:=False;
 If XBytes>GXCap Then Begin
  ComRelease(GXSrv);ComRelease(GXBuf);GXSrv:=Nil;GXBuf:=Nil;GXCap:=0;
  XBytes:=(XBytes+65535)and(not 65535);
  If not GpuMakeBuffer(XBytes,0,8,0,$20,Nil,GXBuf)Then Exit;
  If not GpuMakeSRV(GXBuf,XBytes div 4,GXSrv)Then Exit;
  GXCap:=XBytes;
 End;
 If YBytes>GYCap Then Begin
  ComRelease(GYUav);ComRelease(GYBuf);ComRelease(GYStage);GYUav:=Nil;
    GYBuf:=Nil;GYStage:=Nil;GYCap:=0;
  YBytes:=(YBytes+65535)and(not 65535);
  If not GpuMakeBuffer(YBytes,0,$80,0,$20,Nil,GYBuf)Then Exit;
  If not GpuMakeUAV(GYBuf,YBytes div 4,GYUav)Then Exit;
  If not GpuMakeBuffer(YBytes,3,0,$20000,0,Nil,GYStage)Then Exit;
  GYCap:=YBytes;
 End;
 GpuEnsureIO:=True;
End;

{ cherche (ou envoie en memoire video) la matrice de poids W (M lignes de K) }
Function GpuFindWeight(W:PSingle;Bytes:Int64;Var Srv:Pointer):Boolean;
Var
 I:LongInt;
 Buf,V:Pointer;
Begin
 GpuFindWeight:=False;
 For I:=0 to GNW-1 do If GWeights[I].Ptr=Pointer(W)Then Begin
  Srv:=GWeights[I].Srv;
  GpuFindWeight:=True;
  Exit;
 End;
 If Bytes>=GpuMaxIO*2 Then Exit;
 If GWBytes+Bytes>1500000000 Then Exit;
 If not GpuMakeBuffer(Bytes,0,8,0,$20,W,Buf)Then Exit;
 If not GpuMakeSRV(Buf,Bytes div 4,V)Then Begin ComRelease(Buf);Exit;End;
 If GNW>High(GWeights)Then SetLength(GWeights,GNW+64);
 GWeights[GNW].Ptr:=Pointer(W);
 GWeights[GNW].Srv:=V;
 GWeights[GNW].Buf:=Buf;
 GWeights[GNW].Bytes:=Bytes;
 Inc(GNW);
 Inc(GWBytes,Bytes);
 Srv:=V;
 GpuFindWeight:=True;
End;

Function GpuGemmRun(X,W,B,Y:PSingle;N,K,M:LongInt;Force:Boolean):Boolean;
Var
 R0,Rows,MaxRows,I,J:LongInt;
 CB:TCBData;
 Box:TBox;
 WSrv,Views,UA,Cbuf:Pointer;
 Mp:TMapped;
 Src,Dst:PSingle;
Begin
 GpuGemmRun:=False;
 If not GpuOn Then Exit;
 If(not Force)and(Int64(N)*K*M<GpuMinWork*16)Then Exit;
 If(K<=0)or(M<=0)or(N<=0)Then Exit;
 If not GpuFindWeight(W,Int64(M)*K*4,WSrv)Then Exit;
 MaxRows:=GpuMaxIO div(4*IMax(K,M));
 If MaxRows<1 Then Exit;
 If MaxRows>65535*16 Then MaxRows:=65535*16;
 R0:=0;
 While R0<N do Begin
  Rows:=N-R0;
  If Rows>MaxRows Then Rows:=MaxRows;
  If not GpuEnsureIO(Rows*K*4,Rows*M*4)Then Begin GpuOn:=False;Exit;End;
  CB.K:=K;CB.M:=M;CB.N:=Rows;CB.Pad:=0;
  TMUpdate(VTab(GCtx,48))(GCtx,GCB,0,Nil,@CB,0,0);
  FillChar(Box,SizeOf(Box),0);
  Box.Right:=Rows*K*4;Box.Bottom:=1;Box.Back:=1;
  TMUpdate(VTab(GCtx,48))(GCtx,GXBuf,0,@Box,X+Int64(R0)*K,0,0);
  TMSetShader(VTab(GCtx,69))(GCtx,GShGemm,Nil,0);
  Cbuf:=GCB;
  TMSetCB(VTab(GCtx,71))(GCtx,0,1,@Cbuf);
  Views:=WSrv;
  TMSetSRV(VTab(GCtx,67))(GCtx,0,1,@Views);
  Views:=GXSrv;
  TMSetSRV(VTab(GCtx,67))(GCtx,1,1,@Views);
  UA:=GYUav;
  TMSetUAV(VTab(GCtx,68))(GCtx,0,1,@UA,Nil);
  TMDispatch(VTab(GCtx,41))(GCtx,(M+15)div 16,(Rows+15)div 16,1);
  Box.Right:=Rows*M*4;
  TMCopyRegion(VTab(GCtx,46))(GCtx,GYStage,0,0,0,0,GYBuf,0,@Box);
  If TMMap(VTab(GCtx,14))(GCtx,GYStage,0,1,0,Mp)<0 Then Begin
   GpuOn:=False;
   Exit;
  End;
  Src:=PSingle(Mp.Data);
  Dst:=Y+Int64(R0)*M;
  If B<>Nil Then Begin
   For I:=0 to Rows-1 do
    For J:=0 to M-1 do Dst[Int64(I)*M+J]:=Src[Int64(I)*M+J]+B[J];
  End
   Else Move(Src^,Dst^,Int64(Rows)*M*4);
  TMUnmap(VTab(GCtx,15))(GCtx,GYStage,0);
  Inc(R0,Rows);
 End;
 Inc(GpuCalls);
 Inc(GpuBytes,Int64(N)*(K+M)*4);
 GpuGemmRun:=True;
End;

Function GpuGemm(X,W,B,Y:PSingle;N,K,M:LongInt):Boolean;
Begin
 GpuGemm:=GpuGemmRun(X,W,B,Y,N,K,M,False);
End;

{ compare le GPU au CPU sur un petit produit matriciel (tailles non multiples de
  16) }
Function GpuSelfTest:Boolean;
Const
 TN=45;TK=70;TM=37;
Var
 X,W,B,Yc,Yg:PSingle;
 I:LongInt;
 Mx,D:Double;
Begin
 GpuSelfTest:=False;
 X:=AllocF(TN*TK);W:=AllocF(TM*TK);B:=AllocF(TM);
 Yc:=AllocF(TN*TM);Yg:=AllocF(TN*TM);
 For I:=0 to TN*TK-1 do X[I]:=((I*7919)mod 2003)/1001.5-1.0;
 For I:=0 to TM*TK-1 do W[I]:=((I*104729)mod 3001)/1500.5-1.0;
 For I:=0 to TM-1 do B[I]:=I/37.0-0.5;
 GemmCPU(X,W,B,Yc,TN,TK,TM);
 If GpuGemmRun(X,W,B,Yg,TN,TK,TM,True)Then Begin
  Mx:=0;
  For I:=0 to TN*TM-1 do Begin
   D:=Abs(Yc[I]-Yg[I]);
   If D>Mx Then Mx:=D;
  End;
  GpuSelfTest:=Mx<0.001;
  If Mx>=0.001 Then Warn(
    'le test du GPU '#133' donn'#130' un r'#130'sultat incorrect (erreur '+
    FStr(Mx,5)+')');
 End;
 FreeMem(X);FreeMem(W);FreeMem(B);FreeMem(Yc);FreeMem(Yg);
 GpuCalls:=0;GpuBytes:=0;
End;

{ DevIdx : -1 = automatique (le plus de memoire video) }
Function GpuSetup(DevIdx:LongInt;Var Err:AnsiString):Boolean;
Var
 I,Best:LongInt;
Begin
 GpuSetup:=False;
 GpuOn:=False;
 GpuEnumDevices;
 If Length(GpuDevs)=0 Then Begin
   Err:='aucun p'#130'riph'#130'rique Direct3D 11 d'#130'tect'#130;Exit;End;
 If(DevIdx>=0)and(DevIdx<Length(GpuDevs))Then Best:=DevIdx
 Else Begin
  Best:=0;
  For I:=1 to High(GpuDevs)do If GpuDevs[I].VRam>GpuDevs[Best].VRam Then
    Best:=I;
 End;
 If not GpuInitDevice(Best,Err)Then Exit;
 GpuOn:=True;
 GpuName:=GpuDevs[Best].Name;
 If not GpuSelfTest Then Begin
  GpuOn:=False;
  Err:='le test de validation du GPU a '#130'chou'#130;
  Exit;
 End;
 GpuSetup:=True;
End;

Procedure GpuPrintDevices;
Var
 I:LongInt;
Begin
 GpuEnumDevices;
 WriteLn('P'#130'riph'#130'riques Direct3D 11 :');
 If Length(GpuDevs)=0 Then WriteLn('  (aucun)');
 For I:=0 to High(GpuDevs)do
  WriteLn('  ',I,' : ',GpuDevs[I].Name,' (',GpuDevs[I].VRam shr 20,' Mio, ',
    GpuDevs[I].Free shr 20,' Mio libres)');
End;
{$ELSE}
Function GpuGemm(X,W,B,Y:PSingle;N,K,M:LongInt):Boolean;
Begin
 GpuGemm:=False;
End;

Function GpuSetup(DevIdx:LongInt;Var Err:AnsiString):Boolean;
Begin
 GpuOn:=False;
 Err:='Direct3D 11 n''est disponible que sous Windows';
 GpuSetup:=False;
End;

Procedure GpuPrintDevices;
Begin
 WriteLn('P'#130'riph'#130'riques Direct3D 11 :');
 WriteLn('  (Direct3D 11 n''est disponible que sous Windows)');
End;
{$ENDIF}

{ produit matriciel : GPU si actif et assez gros, sinon CPU }
Procedure Gemm(X,W,B,Y:PSingle;N,K,M:LongInt);
Begin
 If GpuOn Then
  If GpuGemm(X,W,B,Y,N,K,M)Then Exit;
 GemmCPU(X,W,B,Y,N,K,M);
End;

{ ------------------------------------------------------------------ }
{ Fichiers .safetensors                                               }
{ ------------------------------------------------------------------ }

Type
 TTensor=Record
  Name:AnsiString;
  DType:AnsiString;
  NDim:LongInt;
  Dims:Array[0..5]of LongInt;
  Off0,Off1:Int64;
  Data:PSingle;
  Count:Int64;
 End;

Var
 StT:Array of TTensor;
 StN:LongInt=0;

Function HalfToSingle(H:Word):Single;
Var
 S,M:LongWord;
 E:LongInt;
 R:LongWord;
 F:Single;
Begin
 S:=(H shr 15)and 1;
 E:=(H shr 10)and 31;
 M:=H and 1023;
 If E=0 Then Begin
  If M=0 Then R:=S shl 31
  Else Begin
   E:=1;
   While(M and 1024)=0 do Begin M:=M shl 1;Dec(E);End;
   M:=M and 1023;
   R:=(S shl 31)or(LongWord(E+112)shl 23)or(M shl 13);
  End;
 End
  Else If E=31 Then R:=(S shl 31)or($FF shl 23)or(M shl 13)
  Else R:=(S shl 31)or(LongWord(E+112)shl 23)or(M shl 13);
 Move(R,F,4);
 HalfToSingle:=F;
End;

Function StFind(Const Name:AnsiString):LongInt;
Var
 I:LongInt;
Begin
 StFind:=-1;
 For I:=0 to StN-1 do If StT[I].Name=Name Then Begin StFind:=I;Exit;End;
End;

{ analyse de l'en-tete JSON : { "nom":
  {"dtype":..,"shape":[..],"data_offsets":[a,b]}, ... } }
Function StParseHeader(Const H:AnsiString;Var Err:AnsiString):Boolean;
Var
 P:LongInt;

 Procedure Ws;
 Begin
  While(P<=Length(H))and(H[P]in[' ',#9,#10,#13])do Inc(P);
 End;

 Function ReadStr:AnsiString;
 Var
  R:AnsiString;
 Begin
  R:='';
  If(P<=Length(H))and(H[P]='"')Then Inc(P);
  While(P<=Length(H))and(H[P]<>'"')do Begin
   If H[P]='\' Then Begin
    Inc(P);
    If(P<=Length(H))and(H[P]='u')Then Begin R:=R+'?';Inc(P,4);End
    Else If P<=Length(H)Then R:=R+H[P];
   End
    Else R:=R+H[P];
   Inc(P);
  End;
  Inc(P);
  ReadStr:=R;
 End;

 Function ReadNum:Int64;
 Var
  V:Int64;
 Begin
  V:=0;
  While(P<=Length(H))and(H[P]in['0'..'9'])do Begin
   V:=V*10+Ord(H[P])-48;
   Inc(P);
  End;
  ReadNum:=V;
 End;

 Procedure SkipValue;
 Var
  Depth:LongInt;
 Begin
  Ws;
  If P>Length(H)Then Exit;
  If H[P]='"' Then Begin ReadStr;Exit;End;
  If H[P]in['{','[']Then Begin
   Depth:=0;
   Repeat
    If H[P]='"' Then ReadStr
    Else Begin
     If H[P]in['{','[']Then Inc(Depth)
     Else If H[P]in['}',']']Then Dec(Depth);
     Inc(P);
    End;
   Until(Depth=0)or(P>Length(H));
   Exit;
  End;
  While(P<=Length(H))and not(H[P]in[',','}',']'])do Inc(P);
 End;

 Procedure ParseTensor(Const Nm:AnsiString);
 Var
  Key:AnsiString;
  T:TTensor;
 Begin
  FillChar(T.Dims,SizeOf(T.Dims),0);
  T.Name:=Nm;T.DType:='';T.NDim:=0;T.Off0:=0;T.Off1:=0;T.Data:=Nil;T.Count:=1;
  Ws;
  If H[P]<>'{' Then Begin SkipValue;Exit;End;
  Inc(P);
  While P<=Length(H)do Begin
   Ws;
   If H[P]='}' Then Begin Inc(P);Break;End;
   If H[P]=',' Then Begin Inc(P);Continue;End;
   Key:=ReadStr;
   Ws;Inc(P);Ws;
   If Key='dtype' Then T.DType:=ReadStr
   Else If Key='shape' Then Begin
    Inc(P);
    While(P<=Length(H))and(H[P]<>']')do Begin
     Ws;
     If H[P]=',' Then Inc(P)
     Else If H[P]in['0'..'9']Then Begin
      If T.NDim<6 Then Begin T.Dims[T.NDim]:=ReadNum;
        T.Count:=T.Count*T.Dims[T.NDim];Inc(T.NDim);End Else ReadNum;
     End
      Else Inc(P);
    End;
    Inc(P);
   End
    Else If Key='data_offsets' Then Begin
     Inc(P);Ws;T.Off0:=ReadNum;Ws;If H[P]=',' Then Inc(P);Ws;T.Off1:=ReadNum;Ws;
     If H[P]=']' Then Inc(P);
    End
     Else SkipValue;
  End;
  If StN>High(StT)Then SetLength(StT,StN+256);
  StT[StN]:=T;
  Inc(StN);
 End;

Var
 Key:AnsiString;
Begin
 StParseHeader:=False;
 P:=1;
 Ws;
 If(P>Length(H))or(H[P]<>'{')Then Begin
   Err:='en-t'#136'te safetensors invalide';Exit;End;
 Inc(P);
 While P<=Length(H)do Begin
  Ws;
  If H[P]='}' Then Break;
  If H[P]=',' Then Begin Inc(P);Continue;End;
  Key:=ReadStr;
  Ws;
  If(P<=Length(H))and(H[P]=':')Then Inc(P);
  If Key='__metadata__' Then SkipValue Else ParseTensor(Key);
 End;
 StParseHeader:=StN>0;
 If StN=0 Then Err:='aucun tenseur dans le fichier safetensors';
End;

{ charge tous les tenseurs flottants (F32, F16, BF16) en F32 }
Function StLoad(Const Path:AnsiString;Var Err:AnsiString):Boolean;
Var
 F:File;
 Hdr:Array[0..7]of Byte;
 HLen:Int64;
 H:AnsiString;
 Got:LongInt;
 I:LongInt;
 Base,Remain:Int64;
 Tmp:PWord;
 N,Chunk,J:LongInt;
 T:^TTensor;
 W:Word;
 Sf:Single;
 Bits:LongWord;
Begin
 StLoad:=False;
 Err:='';
 StN:=0;SetLength(StT,0);
 Assign(F,Path);
 Reset(F,1);
 If IOResult<>0 Then Begin Err:='impossible d''ouvrir '+Path;Exit;End;
 BlockRead(F,Hdr[0],8,Got);
 If Got<>8 Then Begin Err:='fichier safetensors trop court';Close(F);Exit;End;
 HLen:=Int64(LE32(@Hdr[0]))+(Int64(LE32(@Hdr[4]))shl 32);
 If(HLen<2)or(HLen>100000000)Then Begin
   Err:='en-t'#136'te safetensors invalide';Close(F);Exit;End;
 SetLength(H,HLen);
 BlockRead(F,H[1],HLen,Got);
 If Got<>HLen Then Begin Err:='en-t'#136'te safetensors tronqu'#130;Close(F)
   ;Exit;End;
 If not StParseHeader(H,Err)Then Begin Close(F);Exit;End;
 Base:=8+HLen;
 Tmp:=PWord(AllocBytes(2*1048576));
 For I:=0 to StN-1 do Begin
  T:=@StT[I];
  If(T^.DType<>'F32')and(T^.DType<>'F16')and(T^.DType<>'BF16')Then Continue;
  If T^.Count<=0 Then Continue;
  T^.Data:=AllocF(T^.Count);
  Seek(F,Base+T^.Off0);
  If T^.DType='F32' Then Begin
   Remain:=T^.Count*4;
   N:=0;
   While Remain>0 do Begin
    Chunk:=1048576;
    If Remain<Chunk Then Chunk:=Remain;
    BlockRead(F,(PByte(T^.Data)+N)^,Chunk,Got);
    If Got<=0 Then Begin Err:='fichier safetensors tronqu'#130;Close(F);Exit;
      End;
    Inc(N,Got);Dec(Remain,Got);
   End;
  End
   Else Begin
    Remain:=T^.Count;
    N:=0;
    While Remain>0 do Begin
     Chunk:=1048576;
     If Remain<Chunk Then Chunk:=Remain;
     BlockRead(F,Tmp^,Chunk*2,Got);
     If Got<>Chunk*2 Then Begin Err:='fichier safetensors tronqu'#130;Close(F)
       ;Exit;End;
     If T^.DType='F16' Then
      For J:=0 to Chunk-1 do T^.Data[N+J]:=HalfToSingle(Tmp[J])
     Else
      For J:=0 to Chunk-1 do Begin
       Bits:=LongWord(Tmp[J])shl 16;
       Move(Bits,Sf,4);
       T^.Data[N+J]:=Sf;
      End;
     Inc(N,Chunk);Dec(Remain,Chunk);
    End;
   End;
 End;
 FreeMem(Tmp);
 Close(F);
 StLoad:=True;
End;

{ ------------------------------------------------------------------ }
{ Libelles des classes et categories de vetements                      }
{ ------------------------------------------------------------------ }

Const
 cBg=0;cHat=1;cHair=2;cGlasses=3;cTop=4;cSkirt=5;cPants=6;cDress=7;cBelt=8;
 cShoes=9;cFace=10;cLegs=11;cArms=12;cBag=13;cScarf=14;cSkin=15;cOther=16;
 NumCat=17;
 CatNames:Array[0..NumCat-1]of AnsiString=('arri'#138're-plan',
   'chapeau','cheveux',
   'lunettes','haut','jupe','pantalon','robe','ceinture','chaussures','visage',
   'jambes','bras','sac',#130'charpe','peau','autre');
 { noms des 18 classes du modele segformer_b2_clothes }
 DefaultLabels:Array[0..17]of AnsiString=('Background','Hat','Hair',
   'Sunglasses',
   'Upper-clothes','Skirt','Pants','Dress','Belt','Left-shoe',
     'Right-shoe','Face',
   'Left-leg','Right-leg','Left-arm','Right-arm','Bag','Scarf');

Var
 LabelNames:Array of AnsiString;
 LabelCat:Array of LongInt;

Function HasWord(Const S,W:AnsiString):Boolean;
Begin
 HasWord:=Pos(W,S)>0;
End;

{ categorie d'un libelle de classe }
Function CategoryOfLabel(Const Name:AnsiString):LongInt;
Var
 S:AnsiString;
Begin
 S:=LoStr(Name);
 If HasWord(S,'background')or(S='bg')or HasWord(S,'backgr')Then
   CategoryOfLabel:=cBg
 Else If HasWord(S,'sunglass')or HasWord(S,'glasses')or(S='eyeglasses')
   Then CategoryOfLabel:=cGlasses
 Else If HasWord(S,'hat')or HasWord(S,'cap')or HasWord(S,'helmet')
   Then CategoryOfLabel:=cHat
 Else If HasWord(S,'hair')Then CategoryOfLabel:=cHair
 Else If HasWord(S,'upper')or HasWord(S,'coat')or HasWord(S,'jacket')or
   HasWord(S,'shirt')or(S='top')Then CategoryOfLabel:=cTop
 Else If HasWord(S,'skirt')Then CategoryOfLabel:=cSkirt
 Else If HasWord(S,'pant')or HasWord(S,'trouser')or HasWord(S,'jean')or
   HasWord(S,'short')or HasWord(S,'lower')Then CategoryOfLabel:=cPants
 Else If HasWord(S,'dress')or HasWord(S,'jumpsuit')or HasWord(S,'romper')
   Then CategoryOfLabel:=cDress
 Else If HasWord(S,'belt')Then CategoryOfLabel:=cBelt
 Else If HasWord(S,'shoe')or HasWord(S,'boot')or HasWord(S,'sneaker')or
   HasWord(S,'footwear')Then CategoryOfLabel:=cShoes
 Else If HasWord(S,'face')or HasWord(S,'head')Then CategoryOfLabel:=cFace
 Else If HasWord(S,'leg')Then CategoryOfLabel:=cLegs
 Else If HasWord(S,'arm')or HasWord(S,'hand')Then CategoryOfLabel:=cArms
 Else If HasWord(S,'bag')or HasWord(S,'purse')Then CategoryOfLabel:=cBag
 Else If HasWord(S,'scarf')or HasWord(S,'tie')Then CategoryOfLabel:=cScarf
 Else If HasWord(S,'skin')or HasWord(S,'neck')or HasWord(S,'torso')
   Then CategoryOfLabel:=cSkin
 Else CategoryOfLabel:=cOther;
End;

{ lit id2label dans un config.json (HuggingFace) ; faux si absent }
Function LoadLabelsFromConfig(Const Path:AnsiString;L:LongInt):Boolean;
Var
 P:PByte;
 N,I,J,Id,Code:LongInt;
 S,Num,Nm:AnsiString;
 Q:LongInt;
Begin
 LoadLabelsFromConfig:=False;
 If not ReadFileBytes(Path,P,N)Then Exit;
 SetLength(S,N);
 If N>0 Then Move(P^,S[1],N);
 FreeMem(P);
 Q:=Pos('"id2label"',S);
 If Q=0 Then Exit;
 I:=Q+10;
 While(I<=N)and(S[I]<>'{')do Inc(I);
 Inc(I);
 SetLength(LabelNames,L);
 For J:=0 to L-1 do LabelNames[J]:='';
 While I<=N do Begin
  While(I<=N)and(S[I]<>'"')and(S[I]<>'}')do Inc(I);
  If(I>N)or(S[I]='}')Then Break;
  Inc(I);
  Num:='';
  While(I<=N)and(S[I]<>'"')do Begin Num:=Num+S[I];Inc(I);End;
  Inc(I);
  While(I<=N)and(S[I]<>'"')do Inc(I);
  Inc(I);
  Nm:='';
  While(I<=N)and(S[I]<>'"')do Begin Nm:=Nm+S[I];Inc(I);End;
  Inc(I);
  Val(Num,Id,Code);
  If(Code=0)and(Id>=0)and(Id<L)Then LabelNames[Id]:=Nm;
 End;
 For J:=0 to L-1 do If LabelNames[J]='' Then Exit;
 LoadLabelsFromConfig:=True;
End;

Procedure SetupLabels(L:LongInt;Const ConfigPath:AnsiString);
Var
 I:LongInt;
 Ok:Boolean;
Begin
 Ok:=False;
 If(ConfigPath<>'')and FileExistsP(ConfigPath)Then
   Ok:=LoadLabelsFromConfig(ConfigPath,L);
 If not Ok Then Begin
  SetLength(LabelNames,L);
  For I:=0 to L-1 do
   If I<=High(DefaultLabels)Then LabelNames[I]:=DefaultLabels[I]
   Else LabelNames[I]:='class'+IStr(I);
 End;
 SetLength(LabelCat,L);
 For I:=0 to L-1 do LabelCat[I]:=CategoryOfLabel(LabelNames[I]);
End;

{ ------------------------------------------------------------------ }
{ SegFormer : encodeur hierarchique de transformeurs + decodeur MLP    }
{ ------------------------------------------------------------------ }

Type
 TSegBlock=Record
  LN1W,LN1B,LN2W,LN2B:PSingle;
  QW,QB,KW,KB,VW,VB,OW,OB:PSingle;
  SRW,SRB,SRNW,SRNB:PSingle;
  D1W,D1B,DWT,DWB,D2W,D2B:PSingle;   { DWT : noyau 3x3 transpose [9][4C] }
 End;
 TSegStage=Record
  C,Cin,Depth,Heads,SR,Mlp:LongInt;
  PK,PS,PP:LongInt;                  { noyau, pas et marge du plongement de
    patchs }
  PEW,PEB,PENW,PENB,NW,NB:PSingle;
  Blocks:Array of TSegBlock;
 End;
 TSegModel=Record
  Stage:Array[0..3]of TSegStage;
  Dec,NumLabels:LongInt;
  Comp:Array[0..3]of PSingle;        { (Fuse_i x LinC_i) : [Dec][C_i] }
  BnScale,BnShift:PSingle;
  ClsW,ClsB:PSingle;
  Name:AnsiString;
 End;

Const
 SegHeads:Array[0..3]of LongInt=(1,2,5,8);
 SegSR:Array[0..3]of LongInt=(8,4,2,1);

Var
 SegErr:AnsiString;

Function SegNeed(Const Name:AnsiString;Count:Int64):PSingle;
Var
 I:LongInt;
Begin
 SegNeed:=Nil;
 I:=StFind(Name);
 If I<0 Then Begin
  If SegErr='' Then SegErr:='tenseur absent du mod'#138'le : '+Name;
  Exit;
 End;
 If(StT[I].Data=Nil)or(StT[I].Count<>Count)Then Begin
  If SegErr='' Then SegErr:='tenseur de taille inattendue : '+Name;
  Exit;
 End;
 SegNeed:=StT[I].Data;
End;

{ charge le modele depuis les tenseurs deja lus ; deduit la configuration des
  formes }
Function SegBuild(Var M:TSegModel;Const ConfigPath:AnsiString):Boolean;
Var
 Pfx,Nm,Bp:AnsiString;
 I,J,K,Ix,L,C,D,Mlp:LongInt;
 S:^TSegStage;
 B:^TSegBlock;
 Fuse,LinW,LinB,Ct,Blk,Cm,G,Bt,Mn,Vr,Tw,Src:PSingle;
 BSum:PSingle;
 Sc:Single;
 T,Tmp:PSingle;
Begin
 SegBuild:=False;
 SegErr:='';
 FillChar(M,SizeOf(M),0);
 Pfx:='segformer.';
 If StFind(Pfx+'encoder.patch_embeddings.0.proj.weight')<0 Then Begin
  Pfx:='';
  If StFind(Pfx+'encoder.patch_embeddings.0.proj.weight')<0 Then Begin
   SegErr:='mod'#138'le non reconnu : un SegFormer au format HuggingFace '+
     '(.safetensors) est attendu';
   Exit;
  End;
 End;
 For I:=0 to 3 do Begin
  S:=@M.Stage[I];
  Ix:=StFind(Pfx+'encoder.patch_embeddings.'+IStr(I)+'.proj.weight');
  If Ix<0 Then Begin
    SegErr:='mod'#138'le incomplet : plongement de patchs '+IStr(I);Exit;End;
  If StT[Ix].NDim<>4 Then Begin
    SegErr:='forme inattendue du plongement de patchs';Exit;End;
  S^.C:=StT[Ix].Dims[0];S^.Cin:=StT[Ix].Dims[1];S^.PK:=StT[Ix].Dims[2];
  S^.PP:=S^.PK div 2;
  If I=0 Then S^.PS:=4 Else S^.PS:=2;
  S^.Heads:=SegHeads[I];S^.SR:=SegSR[I];
  If(S^.C mod S^.Heads)<>0 Then Begin
    SegErr:='nombre de t'#136'tes d''attention incompatible';Exit;End;
  S^.Depth:=0;
  While StFind(Pfx+'encoder.block.'+IStr(I)+'.'+IStr(S^.Depth)
    +'.layer_norm_1.weight')>=0 do Inc(S^.Depth);
  If S^.Depth=0 Then Begin
    SegErr:='mod'#138'le incomplet : aucun bloc dans l''.'#130'tage '+IStr(I)
    ;Exit;End;
  C:=S^.C;
  Nm:=Pfx+'encoder.patch_embeddings.'+IStr(I)+'.';
  S^.PEW:=SegNeed(Nm+'proj.weight',Int64(C)*S^.Cin*S^.PK*S^.PK);
  S^.PEB:=SegNeed(Nm+'proj.bias',C);
  S^.PENW:=SegNeed(Nm+'layer_norm.weight',C);
  S^.PENB:=SegNeed(Nm+'layer_norm.bias',C);
  S^.NW:=SegNeed(Pfx+'encoder.layer_norm.'+IStr(I)+'.weight',C);
  S^.NB:=SegNeed(Pfx+'encoder.layer_norm.'+IStr(I)+'.bias',C);
  Ix:=StFind(Pfx+'encoder.block.'+IStr(I)+'.0.mlp.dense1.weight');
  If Ix<0 Then Begin SegErr:='mod'#138'le incomplet : mlp.dense1';Exit;End;
  S^.Mlp:=StT[Ix].Dims[0];
  Mlp:=S^.Mlp;
  SetLength(S^.Blocks,S^.Depth);
  For J:=0 to S^.Depth-1 do Begin
   B:=@S^.Blocks[J];
   Bp:=Pfx+'encoder.block.'+IStr(I)+'.'+IStr(J)+'.';
   B^.LN1W:=SegNeed(Bp+'layer_norm_1.weight',C);
     B^.LN1B:=SegNeed(Bp+'layer_norm_1.bias',C);
   B^.LN2W:=SegNeed(Bp+'layer_norm_2.weight',C);
     B^.LN2B:=SegNeed(Bp+'layer_norm_2.bias',C);
   B^.QW:=SegNeed(Bp+'attention.self.query.weight',Int64(C)*C);
     B^.QB:=SegNeed(Bp+'attention.self.query.bias',C);
   B^.KW:=SegNeed(Bp+'attention.self.key.weight',Int64(C)*C);
     B^.KB:=SegNeed(Bp+'attention.self.key.bias',C);
   B^.VW:=SegNeed(Bp+'attention.self.value.weight',Int64(C)*C);
     B^.VB:=SegNeed(Bp+'attention.self.value.bias',C);
   B^.OW:=SegNeed(Bp+'attention.output.dense.weight',Int64(C)*C);
     B^.OB:=SegNeed(Bp+'attention.output.dense.bias',C);
   If S^.SR>1 Then Begin
    B^.SRW:=SegNeed(Bp+'attention.self.sr.weight',Int64(C)*C*S^.SR*S^.SR);
    B^.SRB:=SegNeed(Bp+'attention.self.sr.bias',C);
    B^.SRNW:=SegNeed(Bp+'attention.self.layer_norm.weight',C);
    B^.SRNB:=SegNeed(Bp+'attention.self.layer_norm.bias',C);
   End;
   B^.D1W:=SegNeed(Bp+'mlp.dense1.weight',Int64(Mlp)*C);
     B^.D1B:=SegNeed(Bp+'mlp.dense1.bias',Mlp);
   B^.D2W:=SegNeed(Bp+'mlp.dense2.weight',Int64(C)*Mlp);
     B^.D2B:=SegNeed(Bp+'mlp.dense2.bias',C);
   Tw:=SegNeed(Bp+'mlp.dwconv.dwconv.weight',Int64(Mlp)*9);
   B^.DWB:=SegNeed(Bp+'mlp.dwconv.dwconv.bias',Mlp);
   If Tw<>Nil Then Begin
    B^.DWT:=AllocF(Int64(Mlp)*9);
    For K:=0 to Mlp-1 do
     For L:=0 to 8 do B^.DWT[L*Mlp+K]:=Tw[K*9+L];
   End;
   If SegErr<>'' Then Begin Exit;End;
  End;
  If SegErr<>'' Then Exit;
 End;
 { decodeur }
 Ix:=StFind('decode_head.classifier.weight');
 If Ix<0 Then Begin
   SegErr:='mod'#138'le incomplet : decode_head.classifier';Exit;End;
 M.NumLabels:=StT[Ix].Dims[0];
 D:=StT[Ix].Dims[1];
 M.Dec:=D;
 Fuse:=SegNeed('decode_head.linear_fuse.weight',Int64(D)*4*D);
 G:=SegNeed('decode_head.batch_norm.weight',D);
 Bt:=SegNeed('decode_head.batch_norm.bias',D);
 Mn:=SegNeed('decode_head.batch_norm.running_mean',D);
 Vr:=SegNeed('decode_head.batch_norm.running_var',D);
 M.ClsW:=SegNeed('decode_head.classifier.weight',Int64(M.NumLabels)*D);
 M.ClsB:=SegNeed('decode_head.classifier.bias',M.NumLabels);
 If SegErr<>'' Then Exit;
 { fusion algebrique : linear_fuse(cat(up(linear_c_i(F_i)))) = somme_i
   up((Fuse_i x LinC_i) F_i) + biais }
 BSum:=AllocF(D);
 T:=AllocF(Int64(D)*D);
 Tmp:=AllocF(Int64(D)*D);
 For I:=0 to 3 do Begin
  C:=M.Stage[I].C;
  LinW:=SegNeed('decode_head.linear_c.'+IStr(I)+'.proj.weight',Int64(D)*C);
  LinB:=SegNeed('decode_head.linear_c.'+IStr(I)+'.proj.bias',D);
  If SegErr<>'' Then Begin Exit;End;
  K:=3-I;
  { bloc de colonnes K de linear_fuse, rendu contigu : T[d][e] }
  For J:=0 to D-1 do Move((Fuse+Int64(J)*4*D+K*D)^,(T+Int64(J)*D)^,D*4);
  { LinC transpose : Tmp[c][e] = LinW[e][c] }
  For J:=0 to D-1 do
   For L:=0 to C-1 do Tmp[Int64(L)*D+J]:=LinW[Int64(J)*C+L];
  M.Comp[I]:=AllocF(Int64(D)*C);
  GemmCPU(T,Tmp,Nil,M.Comp[I],D,D,C);
  { M.Comp[I] est [D][C] : lignes d (n), colonnes c (m) }
  For J:=0 to D-1 do Begin
   Sc:=0;
   For L:=0 to D-1 do Sc:=Sc+T[Int64(J)*D+L]*LinB[L];
   BSum[J]:=BSum[J]+Sc;
  End;
 End;
 M.BnScale:=AllocF(D);M.BnShift:=AllocF(D);
 For J:=0 to D-1 do Begin
  Sc:=G[J]/Sqrt(Vr[J]+1.0e-5);
  M.BnScale[J]:=Sc;
  M.BnShift[J]:=Bt[J]-Mn[J]*Sc+Sc*BSum[J];
 End;
 FreeMem(BSum);FreeMem(T);FreeMem(Tmp);
 SetupLabels(M.NumLabels,ConfigPath);
 SegBuild:=True;
End;

{ ---- operateurs ---- }

Type
 TLnCtx=Record
  X,W,B,Y:PSingle;
  C:LongInt;
  Eps:Single;
 End;
 PLnCtx=^TLnCtx;

Procedure LnProc(Ctx:Pointer;Lo,Hi,Tid:LongInt);
Var
 R,I:LongInt;
 Xp,Yp:PSingle;
 Mean,V,D,Inv:Single;
Begin
 With PLnCtx(Ctx)^ do
  For R:=Lo to Hi-1 do Begin
   Xp:=X+Int64(R)*C;Yp:=Y+Int64(R)*C;
   Mean:=0;
   For I:=0 to C-1 do Mean:=Mean+Xp[I];
   Mean:=Mean/C;
   V:=0;
   For I:=0 to C-1 do Begin D:=Xp[I]-Mean;V:=V+D*D;End;
   Inv:=1.0/Sqrt(V/C+Eps);
   For I:=0 to C-1 do Yp[I]:=(Xp[I]-Mean)*Inv*W[I]+B[I];
  End;
End;

{ normalisation de couche sur N lignes de C elements (X et Y peuvent etre
  identiques) }
Procedure LayerNorm(X,W,B,Y:PSingle;N,C:LongInt);
Var
 Cx:TLnCtx;
Begin
 Cx.X:=X;Cx.W:=W;Cx.B:=B;Cx.Y:=Y;Cx.C:=C;Cx.Eps:=1.0e-6;
 ParFor(N,32,@LnProc,@Cx);
End;

Type
 TGeluCtx=Record
  X:PSingle;
 End;
 PGeluCtx=^TGeluCtx;

Procedure GeluProc(Ctx:Pointer;Lo,Hi,Tid:LongInt);
Var
 I:LongInt;
 V:Single;
 X:PSingle;
Begin
 X:=PGeluCtx(Ctx)^.X;
 For I:=Lo to Hi-1 do Begin
  V:=X[I];
  X[I]:=0.5*V*(1.0+FErf(V*0.70710678118654752));
 End;
End;

Procedure Gelu(X:PSingle;N:Int64);
Var
 Cx:TGeluCtx;
Begin
 Cx.X:=X;
 ParFor(N,65536,@GeluProc,@Cx);
End;

Type
 TIm2Ctx=Record
  Src,Dst:PSingle;
  SH,SW,Cin,K,S,P,OH,OW:LongInt;
 End;
 PIm2Ctx=^TIm2Ctx;

{ Src : disposition (y, x, canal) ; Dst : [OH*OW][Cin*K*K] dans l'ordre (canal,
  ky, kx) }
Procedure Im2ColProc(Ctx:Pointer;Lo,Hi,Tid:LongInt);
Var
 Oy,Ox,C,Ky,Kx,Y,X:LongInt;
 Row:PSingle;
Begin
 With PIm2Ctx(Ctx)^ do
  For Oy:=Lo to Hi-1 do
   For Ox:=0 to OW-1 do Begin
    Row:=Dst+(Int64(Oy)*OW+Ox)*Cin*K*K;
    For C:=0 to Cin-1 do
     For Ky:=0 to K-1 do Begin
      Y:=Oy*S+Ky-P;
      For Kx:=0 to K-1 do Begin
       X:=Ox*S+Kx-P;
       If(Y>=0)and(Y<SH)and(X>=0)and(X<SW)Then
        Row[(C*K+Ky)*K+Kx]:=Src[(Int64(Y)*SW+X)*Cin+C]
       Else Row[(C*K+Ky)*K+Kx]:=0;
      End;
     End;
   End;
End;

Procedure Im2Col(Src,Dst:PSingle;SH,SW,Cin,K,S,P,OH,OW:LongInt);
Var
 Cx:TIm2Ctx;
Begin
 Cx.Src:=Src;Cx.Dst:=Dst;Cx.SH:=SH;Cx.SW:=SW;Cx.Cin:=Cin;Cx.K:=K;Cx.S:=S;
   Cx.P:=P;Cx.OH:=OH;Cx.OW:=OW;
 ParFor(OH,4,@Im2ColProc,@Cx);
End;


Type
 TDwCtx=Record
  X,W,B,Y:PSingle;
  H,Wd,C:LongInt;
 End;
 PDwCtx=^TDwCtx;

{ convolution 3x3 par canal (marge 1) ; W est transpose : [9][C] }
Procedure DwProc(Ctx:Pointer;Lo,Hi,Tid:LongInt);
Var
 Cx:PDwCtx;
 Y,X,Ky,Kx,Yy,Xx,I,C:LongInt;
 Dp,Sp,Wp:PSingle;
Begin
 Cx:=PDwCtx(Ctx);
 C:=Cx^.C;
 For Y:=Lo to Hi-1 do
  For X:=0 to Cx^.Wd-1 do Begin
   Dp:=Cx^.Y+(Int64(Y)*Cx^.Wd+X)*C;
   For I:=0 to C-1 do Dp[I]:=Cx^.B[I];
   For Ky:=0 to 2 do Begin
    Yy:=Y+Ky-1;
    If(Yy<0)or(Yy>=Cx^.H)Then Continue;
    For Kx:=0 to 2 do Begin
     Xx:=X+Kx-1;
     If(Xx<0)or(Xx>=Cx^.Wd)Then Continue;
     Sp:=Cx^.X+(Int64(Yy)*Cx^.Wd+Xx)*C;
     Wp:=Cx^.W+(Ky*3+Kx)*C;
     For I:=0 to C-1 do Dp[I]:=Dp[I]+Sp[I]*Wp[I];
    End;
   End;
  End;
End;

Procedure DwConv(X,WT,B,Y:PSingle;H,W,C:LongInt);
Var
 Cx:TDwCtx;
Begin
 Cx.X:=X;Cx.W:=WT;Cx.B:=B;Cx.Y:=Y;Cx.H:=H;Cx.Wd:=W;Cx.C:=C;
 ParFor(H,2,@DwProc,@Cx);
End;

Type
 TAttCtx=Record
  Q,K,V,O,Scratch:PSingle;
  N2,C,Heads:LongInt;
  Scale:Single;
 End;
 PAttCtx=^TAttCtx;

{ attention multi-tetes : O = softmax(Q K^T * Scale) V }
Procedure AttProc(Ctx:Pointer;Lo,Hi,Tid:LongInt);
Var
 Cx:PAttCtx;
 R,Hd,M,I,D,C,N2:LongInt;
 S,Qp,Kp,Vp,Op:PSingle;
 Mx,Sum,T,P:Single;
Begin
 Cx:=PAttCtx(Ctx);
 C:=Cx^.C;N2:=Cx^.N2;
 D:=C div Cx^.Heads;
 S:=Cx^.Scratch+Int64(Tid)*N2;
 For R:=Lo to Hi-1 do
  For Hd:=0 to Cx^.Heads-1 do Begin
   Qp:=Cx^.Q+Int64(R)*C+Hd*D;
   Mx:=-1.0e30;
   For M:=0 to N2-1 do Begin
    Kp:=Cx^.K+Int64(M)*C+Hd*D;
    T:=0;
    For I:=0 to D-1 do T:=T+Qp[I]*Kp[I];
    T:=T*Cx^.Scale;
    S[M]:=T;
    If T>Mx Then Mx:=T;
   End;
   Sum:=0;
   For M:=0 to N2-1 do Begin
    T:=Exp(S[M]-Mx);
    S[M]:=T;
    Sum:=Sum+T;
   End;
   Sum:=1.0/Sum;
   Op:=Cx^.O+Int64(R)*C+Hd*D;
   For I:=0 to D-1 do Op[I]:=0;
   For M:=0 to N2-1 do Begin
    P:=S[M]*Sum;
    Vp:=Cx^.V+Int64(M)*C+Hd*D;
    For I:=0 to D-1 do Op[I]:=Op[I]+P*Vp[I];
   End;
  End;
End;

Procedure Attention(Q,K,V,O:PSingle;N,N2,C,Heads:LongInt);
Var
 Cx:TAttCtx;
 Sc:PSingle;
Begin
 Sc:=AllocF(Int64(GNThreads)*N2+16);
 Cx.Q:=Q;Cx.K:=K;Cx.V:=V;Cx.O:=O;Cx.Scratch:=Sc;Cx.N2:=N2;Cx.C:=C;
   Cx.Heads:=Heads;
 Cx.Scale:=1.0/Sqrt(C/Heads);
 ParFor(N,8,@AttProc,@Cx);
 FreeMem(Sc);
End;

Procedure AddInPlace(X,Y:PSingle;N:Int64);
Var
 I:LongInt;
Begin
 For I:=0 to N-1 do X[I]:=X[I]+Y[I];
End;

Type
 TUpCtx=Record
  Dst,Src:PSingle;
  H1,W1,Hj,Wj,D:LongInt;
 End;
 PUpCtx=^TUpCtx;

{ Dst += agrandissement bilineaire (align_corners=False) de Src }
Procedure UpAddProc(Ctx:Pointer;Lo,Hi,Tid:LongInt);
Var
 Cx:PUpCtx;
 Oy,Ox,Y0,Y1,X0,X1,I,D:LongInt;
 Sy,Sx,Ly,Lx,W00,W01,W10,W11:Single;
 Dp,P00,P01,P10,P11:PSingle;
Begin
 Cx:=PUpCtx(Ctx);
 D:=Cx^.D;
 For Oy:=Lo to Hi-1 do Begin
  Sy:=(Oy+0.5)*Cx^.Hj/Cx^.H1-0.5;
  If Sy<0 Then Sy:=0;
  Y0:=Trunc(Sy);
  If Y0>Cx^.Hj-1 Then Y0:=Cx^.Hj-1;
  Y1:=Y0+1;
  If Y1>Cx^.Hj-1 Then Y1:=Cx^.Hj-1;
  Ly:=Sy-Y0;
  For Ox:=0 to Cx^.W1-1 do Begin
   Sx:=(Ox+0.5)*Cx^.Wj/Cx^.W1-0.5;
   If Sx<0 Then Sx:=0;
   X0:=Trunc(Sx);
   If X0>Cx^.Wj-1 Then X0:=Cx^.Wj-1;
   X1:=X0+1;
   If X1>Cx^.Wj-1 Then X1:=Cx^.Wj-1;
   Lx:=Sx-X0;
   W00:=(1-Ly)*(1-Lx);W01:=(1-Ly)*Lx;W10:=Ly*(1-Lx);W11:=Ly*Lx;
   Dp:=Cx^.Dst+(Int64(Oy)*Cx^.W1+Ox)*D;
   P00:=Cx^.Src+(Int64(Y0)*Cx^.Wj+X0)*D;
   P01:=Cx^.Src+(Int64(Y0)*Cx^.Wj+X1)*D;
   P10:=Cx^.Src+(Int64(Y1)*Cx^.Wj+X0)*D;
   P11:=Cx^.Src+(Int64(Y1)*Cx^.Wj+X1)*D;
   For I:=0 to D-1 do
    Dp[I]:=Dp[I]+W00*P00[I]+W01*P01[I]+W10*P10[I]+W11*P11[I];
  End;
 End;
End;

Procedure UpAdd(Dst,Src:PSingle;H1,W1,Hj,Wj,D:LongInt);
Var
 Cx:TUpCtx;
Begin
 Cx.Dst:=Dst;Cx.Src:=Src;Cx.H1:=H1;Cx.W1:=W1;Cx.Hj:=Hj;Cx.Wj:=Wj;Cx.D:=D;
 ParFor(H1,2,@UpAddProc,@Cx);
End;

Type
 TBnCtx=Record
  X,Sc,Sh:PSingle;
  D:LongInt;
 End;
 PBnCtx=^TBnCtx;

Procedure BnReluProc(Ctx:Pointer;Lo,Hi,Tid:LongInt);
Var
 Cx:PBnCtx;
 R,I,D:LongInt;
 Xp:PSingle;
 V:Single;
Begin
 Cx:=PBnCtx(Ctx);
 D:=Cx^.D;
 For R:=Lo to Hi-1 do Begin
  Xp:=Cx^.X+Int64(R)*D;
  For I:=0 to D-1 do Begin
   V:=Xp[I]*Cx^.Sc[I]+Cx^.Sh[I];
   If V<0 Then V:=0;
   Xp[I]:=V;
  End;
 End;
End;

{ ---- passe avant ---- }

Var
 SegT0:Double;

Procedure SegStep(Const S:AnsiString);
Begin
 If Verbose Then Detail(S+' ('+FStr((NowMsF-SegT0)/1000.0,1)+' s)');
End;

{ Img : pixels normalises (y, x, RVB) de H x W (H et W multiples de 32
  conseilles) ;
  renvoie les logits [OH*OW][NumLabels] (resolution 1/4) }
Function SegForward(Var M:TSegModel;Img:PSingle;H,W:LongInt;Var OH,OW:LongInt)
  :PSingle;
Var
 I,J,N,N2,Hn,Wn,H2,W2,C,Mlp,Kc,D,L:LongInt;
 S:^TSegStage;
 B:^TSegBlock;
 Feat:Array[0..3]of PSingle;
 FH,FW:Array[0..3]of LongInt;
 Cur:PSingle;
 CurH,CurW,CurC:LongInt;
 X,T,Q,A,Tm,Col,KB,VB,R,Hid,Hid2,Kin:PSingle;
 ColSize:Int64;
 Z:Array[0..3]of PSingle;
 Cx:TBnCtx;
 Lg:PSingle;
Begin
 SegT0:=NowMsF;
 Cur:=Img;CurH:=H;CurW:=W;CurC:=3;
 For I:=0 to 3 do Begin
  S:=@M.Stage[I];
  C:=S^.C;Mlp:=S^.Mlp;
  If CurC<>S^.Cin Then Fatal(
    'mod'#138'le incoh'#130'rent : canaux d''entr'#130'e de l''.'#130'tage '+
    IStr(I));
  Hn:=(CurH+2*S^.PP-S^.PK)div S^.PS+1;
  Wn:=(CurW+2*S^.PP-S^.PK)div S^.PS+1;
  N:=Hn*Wn;
  N2:=N;H2:=Hn;W2:=Wn;
  If S^.SR>1 Then Begin
   H2:=Hn div S^.SR;W2:=Wn div S^.SR;
   If(H2<1)or(W2<1)Then Fatal('image trop petite pour le r'#130'seau');
   N2:=H2*W2;
  End;
  ColSize:=Int64(N)*S^.Cin*S^.PK*S^.PK;
  If S^.SR>1 Then If Int64(N2)*C*S^.SR*S^.SR>ColSize Then ColSize:=Int64(N2)
    *C*S^.SR*S^.SR;
  Col:=AllocF(ColSize);
  X:=AllocF(Int64(N)*C);T:=AllocF(Int64(N)*C);Q:=AllocF(Int64(N)*C);
  A:=AllocF(Int64(N)*C);Tm:=AllocF(Int64(N)*C);
  KB:=AllocF(Int64(N2)*C);VB:=AllocF(Int64(N2)*C);R:=AllocF(Int64(N2)*C);
  Hid:=AllocF(Int64(N)*Mlp);Hid2:=AllocF(Int64(N)*Mlp);
  { plongement de patchs : convolution + normalisation }
  Im2Col(Cur,Col,CurH,CurW,S^.Cin,S^.PK,S^.PS,S^.PP,Hn,Wn);
  Gemm(Col,S^.PEW,S^.PEB,X,N,S^.Cin*S^.PK*S^.PK,C);
  LayerNorm(X,S^.PENW,S^.PENB,X,N,C);
  For J:=0 to S^.Depth-1 do Begin
   B:=@S^.Blocks[J];
   LayerNorm(X,B^.LN1W,B^.LN1B,T,N,C);
   Gemm(T,B^.QW,B^.QB,Q,N,C,C);
   If S^.SR>1 Then Begin
    Im2Col(T,Col,Hn,Wn,C,S^.SR,S^.SR,0,H2,W2);
    Gemm(Col,B^.SRW,B^.SRB,R,N2,C*S^.SR*S^.SR,C);
    LayerNorm(R,B^.SRNW,B^.SRNB,R,N2,C);
    Kin:=R;
   End
    Else Kin:=T;
   Gemm(Kin,B^.KW,B^.KB,KB,N2,C,C);
   Gemm(Kin,B^.VW,B^.VB,VB,N2,C,C);
   Attention(Q,KB,VB,A,N,N2,C,S^.Heads);
   Gemm(A,B^.OW,B^.OB,Tm,N,C,C);
   AddInPlace(X,Tm,Int64(N)*C);
   LayerNorm(X,B^.LN2W,B^.LN2B,T,N,C);
   Gemm(T,B^.D1W,B^.D1B,Hid,N,C,Mlp);
   DwConv(Hid,B^.DWT,B^.DWB,Hid2,Hn,Wn,Mlp);
   Gelu(Hid2,Int64(N)*Mlp);
   Gemm(Hid2,B^.D2W,B^.D2B,Tm,N,Mlp,C);
   AddInPlace(X,Tm,Int64(N)*C);
  End;
  Feat[I]:=AllocF(Int64(N)*C);
  LayerNorm(X,S^.NW,S^.NB,Feat[I],N,C);
  FH[I]:=Hn;FW[I]:=Wn;
  FreeMem(Col);FreeMem(X);FreeMem(T);FreeMem(Q);FreeMem(A);FreeMem(Tm);
  FreeMem(KB);FreeMem(VB);FreeMem(R);FreeMem(Hid);FreeMem(Hid2);
  Cur:=Feat[I];CurH:=Hn;CurW:=Wn;CurC:=C;
  SegStep('r'#130'seau : '#130'tage '+IStr(I+1)+'/4 ('+IStr(Wn)+'x'+IStr(Hn)
    +', '+IStr(C)+' canaux)');
 End;
 { decodeur MLP : produit au plus bas niveau puis agrandissement, somme, BN,
   ReLU }
 D:=M.Dec;L:=M.NumLabels;
 For I:=0 to 3 do Begin
  Z[I]:=AllocF(Int64(FH[I])*FW[I]*D);
  Gemm(Feat[I],M.Comp[I],Nil,Z[I],FH[I]*FW[I],M.Stage[I].C,D);
  FreeMem(Feat[I]);
 End;
 OH:=FH[0];OW:=FW[0];
 For I:=1 to 3 do Begin
  UpAdd(Z[0],Z[I],OH,OW,FH[I],FW[I],D);
  FreeMem(Z[I]);
 End;
 Cx.X:=Z[0];Cx.Sc:=M.BnScale;Cx.Sh:=M.BnShift;Cx.D:=D;
 ParFor(OH*OW,64,@BnReluProc,@Cx);
 Lg:=AllocF(Int64(OH)*OW*L);
 Gemm(Z[0],M.ClsW,M.ClsB,Lg,OH*OW,D,L);
 FreeMem(Z[0]);
 SegStep('r'#130'seau : d'#130'codeur');
 SegForward:=Lg;
End;

{ ------------------------------------------------------------------ }
{ Operations sur les images : couleurs, filtres, redimensionnement,    }
{ composantes connexes, remplissage                                    }
{ ------------------------------------------------------------------ }

Const
 LinSize=16384;
 LabSize=4096;

Var
 SrgbLin:Array[0..4095]of Single;       { sRGB (0..255 par pas de 1/16) ->
   lineaire }
 LinSrgb:Array[0..LinSize]of Single;    { lineaire (0..1) -> sRGB 0..255 }
 LabF:Array[0..LabSize]of Single;       { f(t) de CIE Lab pour t dans [0,1,2] }
 ColReady:Boolean=False;

Procedure ColorInit;
Var
 I:LongInt;
 V,T:Double;
Begin
 If ColReady Then Exit;
 ColReady:=True;
 For I:=0 to 4095 do Begin
  V:=I/16.0/255.0;
  If V<=0.04045 Then T:=V/12.92 Else T:=Exp(2.4*Ln((V+0.055)/1.055));
  SrgbLin[I]:=T;
 End;
 For I:=0 to LinSize do Begin
  V:=I/LinSize;
  If V<=0.0031308 Then T:=V*12.92 Else T:=1.055*Exp(Ln(V)/2.4)-0.055;
  LinSrgb[I]:=T*255.0;
 End;
 For I:=0 to LabSize do Begin
  V:=I/LabSize*2.0;
  If V>0.008856 Then T:=Exp(Ln(V)/3.0) Else T:=7.787*V+16.0/116.0;
  LabF[I]:=T;
 End;
End;

Function ToLin(V:Single):Single;
Var
 I:LongInt;
Begin
 I:=Trunc(V*16.0+0.5);
 If I<0 Then I:=0 Else If I>4095 Then I:=4095;
 ToLin:=SrgbLin[I];
End;

Function FromLin(V:Single):Single;
Var
 F:Single;
 I:LongInt;
Begin
 If V<=0 Then Begin FromLin:=0;Exit;End;
 If V>=1 Then Begin FromLin:=255;Exit;End;
 F:=V*LinSize;
 I:=Trunc(F);
 FromLin:=LinSrgb[I]+(LinSrgb[I+1]-LinSrgb[I])*(F-I);
End;

Function LabFn(T:Single):Single;
Var
 F:Single;
 I:LongInt;
Begin
 If T<=0 Then Begin LabFn:=16.0/116.0;Exit;End;
 If T>=2 Then T:=1.999;
 F:=T/2.0*LabSize;
 I:=Trunc(F);
 LabFn:=LabF[I]+(LabF[I+1]-LabF[I])*(F-I);
End;

Function LabInv(F:Single):Single;
Var
 C:Single;
Begin
 C:=F*F*F;
 If C>0.008856 Then LabInv:=C Else LabInv:=(F-16.0/116.0)/7.787;
End;

{ sRGB 0..255 vers CIE Lab (D65) }
Procedure RgbToLab(R,G,B:Single;Var L,A,Bb:Single);
Var
 Rl,Gl,Bl,X,Y,Z,Fx,Fy,Fz:Single;
Begin
 Rl:=ToLin(R);Gl:=ToLin(G);Bl:=ToLin(B);
 X:=(0.4124564*Rl+0.3575761*Gl+0.1804375*Bl)/0.95047;
 Y:=0.2126729*Rl+0.7151522*Gl+0.0721750*Bl;
 Z:=(0.0193339*Rl+0.1191920*Gl+0.9503041*Bl)/1.08883;
 Fx:=LabFn(X);Fy:=LabFn(Y);Fz:=LabFn(Z);
 L:=116.0*Fy-16.0;
 A:=500.0*(Fx-Fy);
 Bb:=200.0*(Fy-Fz);
End;

Procedure LabToRgb(L,A,Bb:Single;Var R,G,B:Single);
Var
 Fx,Fy,Fz,X,Y,Z,Rl,Gl,Bl:Single;
Begin
 Fy:=(L+16.0)/116.0;
 Fx:=Fy+A/500.0;
 Fz:=Fy-Bb/200.0;
 X:=LabInv(Fx)*0.95047;Y:=LabInv(Fy);Z:=LabInv(Fz)*1.08883;
 Rl:=3.2404542*X-1.5371385*Y-0.4985314*Z;
 Gl:=-0.9692660*X+1.8760108*Y+0.0415560*Z;
 Bl:=0.0556434*X-0.2040259*Y+1.0572252*Z;
 R:=FromLin(Rl);G:=FromLin(Gl);B:=FromLin(Bl);
End;

Function Luma(R,G,B:Single):Single;
Begin
 Luma:=0.299*R+0.587*G+0.114*B;
End;

{ ---- filtres sur plans flottants (W x H) ---- }

{ moyenne sur une fenetre carree de rayon R ; Src et Dst peuvent etre identiques
  }
Procedure BoxBlur(Src,Dst:PSingle;W,H,R:LongInt);
Var
 X,Y,A,B,Y0,Y1:LongInt;
 Pre:Array of Double;
 Col:Array of Double;
 Tmp:PSingle;
 Cnt:Double;
Begin
 If R<=0 Then Begin
  If Src<>Dst Then Move(Src^,Dst^,Int64(W)*H*4);
  Exit;
 End;
 SetLength(Pre,W+1);
 SetLength(Col,W);
 Tmp:=AllocF(Int64(W)*H);
 For Y:=0 to H-1 do Begin
  Pre[0]:=0;
  For X:=0 to W-1 do Pre[X+1]:=Pre[X]+Src[Int64(Y)*W+X];
  For X:=0 to W-1 do Begin
   A:=X-R;If A<0 Then A:=0;
   B:=X+R;If B>W-1 Then B:=W-1;
   Tmp[Int64(Y)*W+X]:=(Pre[B+1]-Pre[A])/(B-A+1);
  End;
 End;
 For X:=0 to W-1 do Col[X]:=0;
 Y1:=-1;
 For Y:=0 to H-1 do Begin
  A:=Y-R;If A<0 Then A:=0;
  B:=Y+R;If B>H-1 Then B:=H-1;
  While Y1<B do Begin
   Inc(Y1);
   For X:=0 to W-1 do Col[X]:=Col[X]+Tmp[Int64(Y1)*W+X];
  End;
  If Y-R-1>=0 Then Begin
   Y0:=Y-R-1;
   For X:=0 to W-1 do Col[X]:=Col[X]-Tmp[Int64(Y0)*W+X];
  End;
  Cnt:=B-A+1;
  For X:=0 to W-1 do Dst[Int64(Y)*W+X]:=Col[X]/Cnt;
 End;
 FreeMem(Tmp);
End;

{ flou approximativement gaussien (3 passes de boite) }
Procedure BlurPlane(P:PSingle;W,H:LongInt;Sigma:Single);
Var
 R:LongInt;
Begin
 R:=Round(Sigma*0.9);
 If R<1 Then R:=1;
 BoxBlur(P,P,W,H,R);
 BoxBlur(P,P,W,H,R);
 BoxBlur(P,P,W,H,R);
End;

Type
 TGuide=Record
  W,H:LongInt;
  I,MeanI,VarI:PSingle;
  R:LongInt;
  Eps:Single;
 End;

{ filtre guide (He et al.) : lisse un masque P en suivant les contours de
  l'image guide I (0..1) }
Procedure GuideInit(Var G:TGuide;Pix:PSingle;W,H,R:LongInt;Eps:Single);
Var
 N:int64;K:LongInt;
 Ii:PSingle;
Begin
 G.W:=W;G.H:=H;G.R:=R;G.Eps:=Eps;
 N:=Int64(W)*H;
 G.I:=AllocF(N);G.MeanI:=AllocF(N);G.VarI:=AllocF(N);
 For K:=0 to N-1 do G.I[K]:=Luma(Pix[K*3],Pix[K*3+1],Pix[K*3+2])/255.0;
 BoxBlur(G.I,G.MeanI,W,H,R);
 Ii:=AllocF(N);
 For K:=0 to N-1 do Ii[K]:=G.I[K]*G.I[K];
 BoxBlur(Ii,G.VarI,W,H,R);
 For K:=0 to N-1 do G.VarI[K]:=G.VarI[K]-G.MeanI[K]*G.MeanI[K];
 FreeMem(Ii);
End;

Procedure GuideFree(Var G:TGuide);
Begin
 FreeMem(G.I);FreeMem(G.MeanI);FreeMem(G.VarI);
End;

Procedure GuideApply(Var G:TGuide;P,Q:PSingle);
Var
 N:int64;K:LongInt;
 MeanP,Ip,A,B:PSingle;
 Cov:Single;
Begin
 N:=Int64(G.W)*G.H;
 MeanP:=AllocF(N);Ip:=AllocF(N);A:=AllocF(N);B:=AllocF(N);
 BoxBlur(P,MeanP,G.W,G.H,G.R);
 For K:=0 to N-1 do Ip[K]:=G.I[K]*P[K];
 BoxBlur(Ip,Ip,G.W,G.H,G.R);
 For K:=0 to N-1 do Begin
  Cov:=Ip[K]-G.MeanI[K]*MeanP[K];
  A[K]:=Cov/(G.VarI[K]+G.Eps);
  B[K]:=MeanP[K]-A[K]*G.MeanI[K];
 End;
 BoxBlur(A,A,G.W,G.H,G.R);
 BoxBlur(B,B,G.W,G.H,G.R);
 For K:=0 to N-1 do Begin
  Cov:=A[K]*G.I[K]+B[K];
  If Cov<0 Then Cov:=0 Else If Cov>1 Then Cov:=1;
  Q[K]:=Cov;
 End;
 FreeMem(MeanP);FreeMem(Ip);FreeMem(A);FreeMem(B);
End;

{ ---- redimensionnement (filtre triangulaire adapte a l'echelle) ---- }

Type
 TTaps=Record
  First,Count:LongInt;
  Off:LongInt;
 End;

Procedure MakeTaps(SrcN,DstN:LongInt;Var Taps:Array of TTaps;Var Wt:PSingle);
Var
 X,I,F,L,K,Tot:LongInt;
 Scale,Sup,C,W,Sum:Double;
 Tmp:Array of Single;
Begin
 Scale:=SrcN/DstN;
 Sup:=Scale;
 If Sup<1 Then Sup:=1;
 Tot:=0;
 For X:=0 to DstN-1 do Begin
  C:=(X+0.5)*Scale;
  F:=Trunc(C-Sup);If F<0 Then F:=0;
  L:=Trunc(C+Sup)+1;If L>SrcN-1 Then L:=SrcN-1;
  Taps[X].First:=F;Taps[X].Count:=L-F+1;Taps[X].Off:=Tot;
  Inc(Tot,Taps[X].Count);
 End;
 Wt:=AllocF(Tot+1);
 For X:=0 to DstN-1 do Begin
  C:=(X+0.5)*Scale;
  Sum:=0;
  For K:=0 to Taps[X].Count-1 do Begin
   I:=Taps[X].First+K;
   W:=1.0-Abs(I+0.5-C)/Sup;
   If W<0 Then W:=0;
   Wt[Taps[X].Off+K]:=W;
   Sum:=Sum+W;
  End;
  If Sum<=0 Then Begin Wt[Taps[X].Off]:=1;Sum:=1;End;
  For K:=0 to Taps[X].Count-1 do Wt[Taps[X].Off+K]:=Wt[Taps[X].Off+K]/Sum;
 End;
End;

{ Src : SW x SH x Ch flottants ; Dst : DW x DH x Ch }
Procedure ResizeF(Src:PSingle;SW,SH:LongInt;Dst:PSingle;DW,DH,Ch:LongInt);
Var
 TX,TY:Array of TTaps;
 WX,WY,Tmp:PSingle;
 X,Y,K,C:LongInt;
 Acc:Single;
 Base:Int64;
Begin
 If(SW=DW)and(SH=DH)Then Begin
  Move(Src^,Dst^,Int64(SW)*SH*Ch*4);
  Exit;
 End;
 SetLength(TX,DW);SetLength(TY,DH);
 MakeTaps(SW,DW,TX,WX);
 MakeTaps(SH,DH,TY,WY);
 Tmp:=AllocF(Int64(DW)*SH*Ch);
 For Y:=0 to SH-1 do
  For X:=0 to DW-1 do
   For C:=0 to Ch-1 do Begin
    Acc:=0;
    For K:=0 to TX[X].Count-1 do
     Acc:=Acc+WX[TX[X].Off+K]*Src[(Int64(Y)*SW+TX[X].First+K)*Ch+C];
    Tmp[(Int64(Y)*DW+X)*Ch+C]:=Acc;
   End;
 For Y:=0 to DH-1 do
  For X:=0 to DW-1 do
   For C:=0 to Ch-1 do Begin
    Acc:=0;
    For K:=0 to TY[Y].Count-1 do Begin
     Base:=(Int64(TY[Y].First+K)*DW+X)*Ch+C;
     Acc:=Acc+WY[TY[Y].Off+K]*Tmp[Base];
    End;
    Dst[(Int64(Y)*DW+X)*Ch+C]:=Acc;
   End;
 FreeMem(WX);FreeMem(WY);FreeMem(Tmp);
End;

{ echantillonnage bilineaire d'un plan a Ch canaux (coordonnees de pixels,
  centres a +0,5) }
Procedure SampleBilinear(Src:PSingle;W,H,Ch:LongInt;X,Y:Single;Dst:PSingle);
Var
 X0,Y0,X1,Y1,C:LongInt;
 Fx,Fy:Single;
Begin
 X:=X-0.5;Y:=Y-0.5;
 If X<0 Then X:=0;
 If Y<0 Then Y:=0;
 If X>W-1 Then X:=W-1;
 If Y>H-1 Then Y:=H-1;
 X0:=Trunc(X);Y0:=Trunc(Y);
 X1:=X0+1;If X1>W-1 Then X1:=W-1;
 Y1:=Y0+1;If Y1>H-1 Then Y1:=H-1;
 Fx:=X-X0;Fy:=Y-Y0;
 For C:=0 to Ch-1 do
  Dst[C]:=(Src[(Int64(Y0)*W+X0)*Ch+C]*(1-Fx)+Src[(Int64(Y0)*W+X1)*Ch+C]*Fx)
    *(1-Fy)+
          (Src[(Int64(Y1)*W+X0)*Ch+C]*(1-Fx)+Src[(Int64(Y1)*W+X1)*Ch+C]*Fx)*Fy;
End;

{ ---- masques binaires (octets 0/255) ---- }

{ dilatation (ou erosion si Erode) par un carre de rayon R }
Procedure MorphMask(M:PByte;W,H,R:LongInt;Erode:Boolean);
Var
 X,Y,K,A,B:LongInt;
 Tmp:PByte;
 V:Byte;
Begin
 If R<=0 Then Exit;
 Tmp:=PByte(AllocBytes(Int64(W)*H));
 For Y:=0 to H-1 do
  For X:=0 to W-1 do Begin
   A:=X-R;If A<0 Then A:=0;
   B:=X+R;If B>W-1 Then B:=W-1;
   If Erode Then V:=255 Else V:=0;
   For K:=A to B do
    If Erode Then Begin If M[Int64(Y)*W+K]<V Then V:=M[Int64(Y)*W+K];End
    Else Begin If M[Int64(Y)*W+K]>V Then V:=M[Int64(Y)*W+K];End;
   Tmp[Int64(Y)*W+X]:=V;
  End;
 For Y:=0 to H-1 do Begin
  A:=Y-R;If A<0 Then A:=0;
  B:=Y+R;If B>H-1 Then B:=H-1;
  For X:=0 to W-1 do Begin
   If Erode Then V:=255 Else V:=0;
   For K:=A to B do
    If Erode Then Begin If Tmp[Int64(K)*W+X]<V Then V:=Tmp[Int64(K)*W+X];End
    Else Begin If Tmp[Int64(K)*W+X]>V Then V:=Tmp[Int64(K)*W+X];End;
   M[Int64(Y)*W+X]:=V;
  End;
 End;
 FreeMem(Tmp);
End;

{ etiquette les composantes connexes (4 voisins) des pixels > 0 ;
  Lab recoit l'etiquette (1..N) ; renvoie N ; Areas[1..N] }
Function Components(M:PByte;W,H:LongInt;Lab:PIntArr;Var Areas:TIntArray)
  :LongInt;
Var
 Stack:PIntArr;
 Sp,N,P,Q,X,Y,Cnt:LongInt;
 Tot:Int64;
Begin
 Tot:=Int64(W)*H;
 Stack:=PIntArr(AllocBytes(Tot*4));
 FillChar(Lab^,Tot*4,0);
 SetLength(Areas,1);
 Areas[0]:=0;
 N:=0;
 For P:=0 to Tot-1 do Begin
  If(M[P]=0)or(Lab[P]<>0)Then Continue;
  Inc(N);
  SetLength(Areas,N+1);
  Cnt:=0;
  Sp:=0;
  Stack[Sp]:=P;Inc(Sp);
  Lab[P]:=N;
  While Sp>0 do Begin
   Dec(Sp);
   Q:=Stack[Sp];
   Inc(Cnt);
   X:=Q mod W;Y:=Q div W;
   If(X>0)and(M[Q-1]<>0)and(Lab[Q-1]=0)Then Begin Lab[Q-1]:=N;Stack[Sp]:=Q-1;
     Inc(Sp);End;
   If(X<W-1)and(M[Q+1]<>0)and(Lab[Q+1]=0)Then Begin Lab[Q+1]:=N;Stack[Sp]:=Q+
     1;Inc(Sp);End;
   If(Y>0)and(M[Q-W]<>0)and(Lab[Q-W]=0)Then Begin Lab[Q-W]:=N;Stack[Sp]:=Q-W;
     Inc(Sp);End;
   If(Y<H-1)and(M[Q+W]<>0)and(Lab[Q+W]=0)Then Begin Lab[Q+W]:=N;Stack[Sp]:=Q+
     W;Inc(Sp);End;
  End;
  Areas[N]:=Cnt;
 End;
 FreeMem(Stack);
 Components:=N;
End;

{ ---- remplissage par propagation multi-echelle (pull-push) ----
  Pix : RVB flottant W x H ; Known : poids 0..1 (1 = pixel fiable) }
Procedure PushPullFill(Pix:PSingle;Known:PSingle;W,H:LongInt);
Const
 MaxLev=14;
Var
 LW,LH:Array[0..MaxLev]of LongInt;
 Col:Array[0..MaxLev]of PSingle;
 Wt:Array[0..MaxLev]of PSingle;
 NL,L,X,Y,C,Dx,Dy,X2,Y2,X0,X1,Y0,Y1:LongInt;
 Sw,Sum:Single;
 Fx,Fy,Sx,Sy,V00,V01,V10,V11,Up:Single;
 N:LongInt;
 Any:Boolean;
Begin
 NL:=0;
 LW[0]:=W;LH[0]:=H;
 N:=Int64(W)*H;
 Col[0]:=AllocF(N*3);Wt[0]:=AllocF(N);
 Any:=False;
 For N:=0 to Int64(W)*H-1 do Begin
  Wt[0][N]:=Known[N];
  If Known[N]>0 Then Any:=True;
  For C:=0 to 2 do Col[0][N*3+C]:=Pix[N*3+C];
 End;
 If not Any Then Begin
  FreeMem(Col[0]);FreeMem(Wt[0]);
  Exit;
 End;
 While(LW[NL]>1)or(LH[NL]>1)do Begin
  If NL>=MaxLev Then Break;
  LW[NL+1]:=(LW[NL]+1)div 2;LH[NL+1]:=(LH[NL]+1)div 2;
  Col[NL+1]:=AllocF(Int64(LW[NL+1])*LH[NL+1]*3);
  Wt[NL+1]:=AllocF(Int64(LW[NL+1])*LH[NL+1]);
  For Y:=0 to LH[NL+1]-1 do
   For X:=0 to LW[NL+1]-1 do Begin
    Sw:=0;
    Sx:=0;Sy:=0;V00:=0;
    For Dy:=0 to 1 do
     For Dx:=0 to 1 do Begin
      X2:=X*2+Dx;Y2:=Y*2+Dy;
      If(X2<LW[NL])and(Y2<LH[NL])Then Begin
       Sum:=Wt[NL][Int64(Y2)*LW[NL]+X2];
       Sw:=Sw+Sum;
       Sx:=Sx+Sum*Col[NL][(Int64(Y2)*LW[NL]+X2)*3];
       Sy:=Sy+Sum*Col[NL][(Int64(Y2)*LW[NL]+X2)*3+1];
       V00:=V00+Sum*Col[NL][(Int64(Y2)*LW[NL]+X2)*3+2];
      End;
     End;
    N:=Int64(Y)*LW[NL+1]+X;
    If Sw>0 Then Begin
     Col[NL+1][N*3]:=Sx/Sw;Col[NL+1][N*3+1]:=Sy/Sw;Col[NL+1][N*3+2]:=V00/Sw;
    End;
    If Sw>1 Then Sw:=1;
    Wt[NL+1][N]:=Sw;
   End;
  Inc(NL);
 End;
 { poussee : du niveau le plus grossier vers le plus fin }
 For L:=NL-1 downto 0 do
  For Y:=0 to LH[L]-1 do
   For X:=0 to LW[L]-1 do Begin
    N:=Int64(Y)*LW[L]+X;
    If Wt[L][N]>=1 Then Continue;
    Sx:=(X+0.5)/2-0.5;Sy:=(Y+0.5)/2-0.5;
    If Sx<0 Then Sx:=0;
    If Sy<0 Then Sy:=0;
    X0:=Trunc(Sx);Y0:=Trunc(Sy);
    X1:=X0+1;If X1>LW[L+1]-1 Then X1:=LW[L+1]-1;
    Y1:=Y0+1;If Y1>LH[L+1]-1 Then Y1:=LH[L+1]-1;
    If X0>LW[L+1]-1 Then X0:=LW[L+1]-1;
    If Y0>LH[L+1]-1 Then Y0:=LH[L+1]-1;
    Fx:=Sx-X0;Fy:=Sy-Y0;
    For C:=0 to 2 do Begin
     V00:=Col[L+1][(Int64(Y0)*LW[L+1]+X0)*3+C];
     V01:=Col[L+1][(Int64(Y0)*LW[L+1]+X1)*3+C];
     V10:=Col[L+1][(Int64(Y1)*LW[L+1]+X0)*3+C];
     V11:=Col[L+1][(Int64(Y1)*LW[L+1]+X1)*3+C];
     Up:=(V00*(1-Fx)+V01*Fx)*(1-Fy)+(V10*(1-Fx)+V11*Fx)*Fy;
     Col[L][N*3+C]:=Col[L][N*3+C]*Wt[L][N]+Up*(1-Wt[L][N]);
    End;
    Wt[L][N]:=1;
   End;
 For N:=0 to Int64(W)*H-1 do
  For C:=0 to 2 do Pix[N*3+C]:=Pix[N*3+C]*Known[N]+Col[0][N*3+C]*(1-Known[N]);
 For L:=0 to NL do Begin FreeMem(Col[L]);FreeMem(Wt[L]);End;
End;

{ ------------------------------------------------------------------ }
{ Scene : image de travail et cartes de categories (analyse IA)       }
{ ------------------------------------------------------------------ }

Type
 TScene=Record
  W,H:LongInt;
  Pix:PSingle;                          { RVB 0..255 }
  Cat:Array[0..NumCat-1]of PByte;       { opacite 0..255 de chaque categorie }
 End;

Const
 { ensembles de categories (masques de bits) }
 msTop=1 shl cTop;
 msSkirt=1 shl cSkirt;
 msPants=1 shl cPants;
 msDress=1 shl cDress;
 msBelt=1 shl cBelt;
 msShoes=1 shl cShoes;
 msHat=1 shl cHat;
 msGlasses=1 shl cGlasses;
 msBag=1 shl cBag;
 msScarf=1 shl cScarf;
 msFace=1 shl cFace;
 msHair=1 shl cHair;
 msArms=1 shl cArms;
 msLegs=1 shl cLegs;
 msSkin=(1 shl cFace)or(1 shl cLegs)or(1 shl cArms)or(1 shl cSkin);
 msClothes=(1 shl cTop)or(1 shl cSkirt)or(1 shl cPants)or(1 shl cDress);

Procedure SceneFree(Var S:TScene);
Var
 C:LongInt;
Begin
 If S.Pix<>Nil Then FreeMem(S.Pix);
 S.Pix:=Nil;
 For C:=0 to NumCat-1 do Begin
  If S.Cat[C]<>Nil Then FreeMem(S.Cat[C]);
  S.Cat[C]:=Nil;
 End;
End;

{ reduit une image d'octets par moyenne de blocs K x K }
Procedure ImgBlockReduce(Var I:TImage;K:LongInt);
Var
 N:TImage;
 X,Y,Dx,Dy,C,NW,NH:LongInt;
 Sum:LongInt;
Begin
 NW:=I.W div K;NH:=I.H div K;
 If(NW<1)or(NH<1)Then Exit;
 ImgAlloc(N,NW,NH,False);
 For Y:=0 to NH-1 do
  For X:=0 to NW-1 do
   For C:=0 to 2 do Begin
    Sum:=0;
    For Dy:=0 to K-1 do
     For Dx:=0 to K-1 do Inc(Sum,I.Px[(Int64(Y*K+Dy)*I.W+X*K+Dx)*3+C]);
    N.Px[(Int64(Y)*NW+X)*3+C]:=(Sum+(K*K)div 2)div(K*K);
   End;
 ImgFree(I);
 I:=N;
End;

{ cree la scene a partir d'une image ; la grande dimension est limitee a MaxSide
  }
Procedure SceneFromImage(Var Img:TImage;MaxSide:LongInt;Var S:TScene);
Var
 Side,NW,NH,K,C:LongInt;
 Src:PSingle;
 N:Int64;
 Sc:Double;
Begin
 FillChar(S,SizeOf(S),0);
 ColorInit;
 Side:=Img.W;If Img.H>Side Then Side:=Img.H;
 If(MaxSide>0)and(Side>MaxSide)Then Begin
  K:=Side div MaxSide;
  If K>=2 Then ImgBlockReduce(Img,K);
  Side:=Img.W;If Img.H>Side Then Side:=Img.H;
 End;
 NW:=Img.W;NH:=Img.H;
 If(MaxSide>0)and(Side>MaxSide)Then Begin
  Sc:=MaxSide/Side;
  NW:=Round(Img.W*Sc);NH:=Round(Img.H*Sc);
  If NW<1 Then NW:=1;
  If NH<1 Then NH:=1;
 End;
 N:=Int64(Img.W)*Img.H*3;
 Src:=AllocF(N);
 For K:=0 to N-1 do Src[K]:=Img.Px[K];
 S.W:=NW;S.H:=NH;
 S.Pix:=AllocF(Int64(NW)*NH*3);
 ResizeF(Src,Img.W,Img.H,S.Pix,NW,NH,3);
 FreeMem(Src);
 For C:=0 to NumCat-1 do S.Cat[C]:=PByte(AllocBytes(Int64(NW)*NH));
 FillChar(S.Cat[cBg]^,Int64(NW)*NH,255);
End;

{ convertit la scene en image 8 bits }
Procedure SceneToImage(Const S:TScene;Var Img:TImage);
Var
 N:int64;K:LongInt;
 V:Single;
Begin
 ImgAlloc(Img,S.W,S.H,False);
 N:=Int64(S.W)*S.H*3;
 For K:=0 to N-1 do Begin
  V:=S.Pix[K];
  If V<0 Then V:=0 Else If V>255 Then V:=255;
  Img.Px[K]:=Trunc(V+0.5);
 End;
End;

{ ---- analyse avec le reseau ---- }

Function ChooseNetSize(W,H,Side:LongInt;Var NW,NH:LongInt):Boolean;
Var
 Sc:Double;
Begin
 Sc:=Side/IMax(W,H);
 NW:=Round(W*Sc/32.0)*32;
 NH:=Round(H*Sc/32.0)*32;
 If NW<64 Then NW:=64;
 If NH<64 Then NH:=64;
 ChooseNetSize:=True;
End;

Const
 ImgMean:Array[0..2]of Single=(0.485,0.456,0.406);
 ImgStd:Array[0..2]of Single=(0.229,0.224,0.225);

{ prepare l'entree du reseau (redimensionnee et normalisee) }
Function NetInput(Const S:TScene;NW,NH:LongInt):PSingle;
Var
 Tmp:PSingle;
 N:int64;K:LongInt;
 C:LongInt;
Begin
 Tmp:=AllocF(Int64(NW)*NH*3);
 ResizeF(S.Pix,S.W,S.H,Tmp,NW,NH,3);
 For K:=0 to Int64(NW)*NH-1 do
  For C:=0 to 2 do Tmp[K*3+C]:=(Tmp[K*3+C]/255.0-ImgMean[C])/ImgStd[C];
 NetInput:=Tmp;
End;

{ carte d'une categorie a la resolution du reseau -> plan 0..255 de la scene }
Procedure UpsampleCat(Map:PSingle;MW,MH:LongInt;Dst:PSingle;W,H:LongInt);
Var
 X,Y,X0,X1,Y0,Y1:LongInt;
 Sx,Sy,Fx,Fy:Single;
Begin
 For Y:=0 to H-1 do Begin
  Sy:=(Y+0.5)*MH/H-0.5;
  If Sy<0 Then Sy:=0;
  Y0:=Trunc(Sy);If Y0>MH-1 Then Y0:=MH-1;
  Y1:=Y0+1;If Y1>MH-1 Then Y1:=MH-1;
  Fy:=Sy-Y0;
  For X:=0 to W-1 do Begin
   Sx:=(X+0.5)*MW/W-0.5;
   If Sx<0 Then Sx:=0;
   X0:=Trunc(Sx);If X0>MW-1 Then X0:=MW-1;
   X1:=X0+1;If X1>MW-1 Then X1:=MW-1;
   Fx:=Sx-X0;
   Dst[Int64(Y)*W+X]:=(Map[Int64(Y0)*MW+X0]*(1-Fx)+Map[Int64(Y0)*MW+X1]*Fx)
     *(1-Fy)+
                      (Map[Int64(Y1)*MW+X0]*(1-Fx)+Map[Int64(Y1)*MW+X1]*Fx)*Fy;
  End;
 End;
End;

{ renormalise les categories pour que leur somme vaille 255 en chaque pixel }
Procedure SceneNormalize(Var S:TScene);
Var
 N:int64;K:LongInt;
 C:LongInt;
 T:LongInt;
 Q:Single;
Begin
 N:=Int64(S.W)*S.H;
 For K:=0 to N-1 do Begin
  T:=0;
  For C:=0 to NumCat-1 do Inc(T,S.Cat[C][K]);
  If T=0 Then S.Cat[cBg][K]:=255
  Else If T<>255 Then Begin
   Q:=255.0/T;
   For C:=0 to NumCat-1 do S.Cat[C][K]:=Trunc(S.Cat[C][K]*Q+0.5);
  End;
 End;
End;

Var
 DumpPath:AnsiString='';

{ ecrit les logits bruts (OH, OW, puis OH*OW*L flottants) pour la mise au point
  }
Procedure DumpLogits(Lg:PSingle;OH,OW,L:LongInt);
Var
 F:File;
 Hd:Array[0..1]of LongInt;
Begin
 Assign(F,DumpPath);
 Rewrite(F,1);
 If IOResult<>0 Then Exit;
 Hd[0]:=OH;Hd[1]:=OW;
 BlockWrite(F,Hd[0],8);
 BlockWrite(F,Lg^,Int64(OH)*OW*L*4);
 Close(F);
End;

{ analyse la scene avec le reseau ; Side : taille de la grande dimension de
  l'entree }
Procedure ParseWithNet(Var S:TScene;Var Net:TSegModel;Side:LongInt;
  Refine:Boolean);
Var
 NW,NH,OH,OW,L,I,C,Rad:LongInt;
 Inp,Lg:PSingle;
 Maps:Array[0..NumCat-1]of PSingle;
 Mx,Sum,E:Single;
 NCell:int64;K:LongInt;
 Plane,Q:PSingle;
 G:TGuide;
 Used:Array[0..NumCat-1]of Boolean;
 N:Int64;
 V:Single;
Begin
 ChooseNetSize(S.W,S.H,Side,NW,NH);
 Detail('entr'#130'e du r'#130'seau : '+IStr(NW)+'x'+IStr(NH));
 Inp:=NetInput(S,NW,NH);
 Lg:=SegForward(Net,Inp,NH,NW,OH,OW);
 FreeMem(Inp);
 L:=Net.NumLabels;
 If DumpPath<>'' Then DumpLogits(Lg,OH,OW,L);
 NCell:=Int64(OH)*OW;
 For C:=0 to NumCat-1 do Begin Maps[C]:=AllocF(NCell);Used[C]:=False;End;
 For K:=0 to NCell-1 do Begin
  Mx:=Lg[K*L];
  For I:=1 to L-1 do If Lg[K*L+I]>Mx Then Mx:=Lg[K*L+I];
  Sum:=0;
  For I:=0 to L-1 do Begin
   E:=Exp(Lg[K*L+I]-Mx);
   Lg[K*L+I]:=E;
   Sum:=Sum+E;
  End;
  For I:=0 to L-1 do Begin
   Maps[LabelCat[I]][K]:=Maps[LabelCat[I]][K]+Lg[K*L+I]/Sum;
   Used[LabelCat[I]]:=True;
  End;
 End;
 FreeMem(Lg);
 N:=Int64(S.W)*S.H;
 Plane:=AllocF(N);
 Q:=AllocF(N);
 If Refine Then Begin
  Rad:=Round(IMin(S.W,S.H)/180.0);
  If Rad<2 Then Rad:=2;
  GuideInit(G,S.Pix,S.W,S.H,Rad,0.004);
 End;
 For C:=0 to NumCat-1 do Begin
  If not Used[C]Then Continue;
  UpsampleCat(Maps[C],OW,OH,Plane,S.W,S.H);
  { categories absentes : inutile de filtrer }
  Mx:=0;
  For K:=0 to N-1 do If Plane[K]>Mx Then Mx:=Plane[K];
  If Mx<0.02 Then Begin
   FillChar(S.Cat[C]^,N,0);
   Continue;
  End;
  If Refine Then Begin
   GuideApply(G,Plane,Q);
   For K:=0 to N-1 do Begin
    V:=Q[K];
    S.Cat[C][K]:=Trunc(V*255.0+0.5);
   End;
  End
   Else For K:=0 to N-1 do S.Cat[C][K]:=Trunc(Plane[K]*255.0+0.5);
 End;
 If Refine Then GuideFree(G);
 FreeMem(Plane);FreeMem(Q);
 For C:=0 to NumCat-1 do FreeMem(Maps[C]);
 SceneNormalize(S);
End;

{ analyse issue d'une image d'etiquettes (valeur du pixel = numero de classe) }
Function ParseFromLabels(Var S:TScene;Const FileName:AnsiString;Var
  Err:AnsiString):Boolean;
Var
 Im:TImage;
 X,Y,SX,SY,Id,C:LongInt;
 N:Int64;
Begin
 ParseFromLabels:=False;
 If not ImgLoad(FileName,Im,Err)Then Exit;
 SetupLabels(Length(DefaultLabels),'');
 N:=Int64(S.W)*S.H;
 For C:=0 to NumCat-1 do FillChar(S.Cat[C]^,N,0);
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   SX:=X*Im.W div S.W;SY:=Y*Im.H div S.H;
   Id:=Im.Px[(Int64(SY)*Im.W+SX)*3];
   If Id>=Length(LabelCat)Then C:=cOther Else C:=LabelCat[Id];
   S.Cat[C][Int64(Y)*S.W+X]:=255;
  End;
 { adoucit legerement les bords des masques durs }
 Detail('analyse lue depuis '+FileName);
 ImgFree(Im);
 ParseFromLabels:=True;
End;

{ adoucit les masques durs en suivant les contours de l'image (filtre guide) }
Procedure SceneRefine(Var S:TScene);
Var
 N:int64;K:LongInt;
 C,Rad:LongInt;
 G:TGuide;
 P,Q:PSingle;
 Any:Boolean;
Begin
 N:=Int64(S.W)*S.H;
 Rad:=Round(IMin(S.W,S.H)/180.0);
 If Rad<2 Then Rad:=2;
 GuideInit(G,S.Pix,S.W,S.H,Rad,0.004);
 P:=AllocF(N);Q:=AllocF(N);
 For C:=0 to NumCat-1 do Begin
  Any:=False;
  For K:=0 to N-1 do Begin
   P[K]:=S.Cat[C][K]/255.0;
   If S.Cat[C][K]<>0 Then Any:=True;
  End;
  If not Any Then Continue;
  BoxBlur(P,P,S.W,S.H,1);
  GuideApply(G,P,Q);
  For K:=0 to N-1 do S.Cat[C][K]:=Trunc(Q[K]*255.0+0.5);
 End;
 GuideFree(G);
 FreeMem(P);FreeMem(Q);
 SceneNormalize(S);
End;

{ ---- requetes sur les categories ---- }

{ opacite cumulee (0..1) des categories de l'ensemble }
Procedure CatMask(Const S:TScene;Mask:LongWord;Dst:PSingle);
Var
 N:int64;K:LongInt;
 C:LongInt;
 T:LongInt;
Begin
 N:=Int64(S.W)*S.H;
 For K:=0 to N-1 do Begin
  T:=0;
  For C:=0 to NumCat-1 do If(Mask and(LongWord(1)shl C))<>0 Then Inc(T,
    S.Cat[C][K]);
  If T>255 Then T:=255;
  Dst[K]:=T/255.0;
 End;
End;

Function CatArea(Const S:TScene;Mask:LongWord):Int64;
Var
 N,A:int64;K:LongInt;
 C:LongInt;
 T:LongInt;
Begin
 N:=Int64(S.W)*S.H;
 A:=0;
 For K:=0 to N-1 do Begin
  T:=0;
  For C:=0 to NumCat-1 do If(Mask and(LongWord(1)shl C))<>0 Then Inc(T,
    S.Cat[C][K]);
  If T>=128 Then Inc(A);
 End;
 CatArea:=A;
End;

{ boite englobante des pixels de l'ensemble (opacite >= 128) ; faux si vide }
Function CatBBox(Const S:TScene;Mask:LongWord;Var X0,Y0,X1,Y1:LongInt):Boolean;
Var
 X,Y,C:LongInt;
 T:LongInt;
 P:Int64;
Begin
 X0:=S.W;Y0:=S.H;X1:=-1;Y1:=-1;
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   P:=Int64(Y)*S.W+X;
   T:=0;
   For C:=0 to NumCat-1 do If(Mask and(LongWord(1)shl C))<>0 Then Inc(T,
     S.Cat[C][P]);
   If T>=128 Then Begin
    If X<X0 Then X0:=X;
    If X>X1 Then X1:=X;
    If Y<Y0 Then Y0:=Y;
    If Y>Y1 Then Y1:=Y;
   End;
  End;
 CatBBox:=X1>=X0;
End;

{ nom lisible d'un ensemble de categories }
Function MaskName(Mask:LongWord):AnsiString;
Var
 C:LongInt;
 R:AnsiString;
Begin
 R:='';
 For C:=0 to NumCat-1 do If(Mask and(LongWord(1)shl C))<>0 Then Begin
  If R<>'' Then R:=R+'+';
  R:=R+CatNames[C];
 End;
 MaskName:=R;
End;

{ colore l'analyse en fausses couleurs (pour -save-parsing) }
Procedure ParsingToImage(Const S:TScene;Var Img:TImage);
Const
 Pal:Array[0..NumCat-1]of LongWord=($000000,$FF9500,$7B3F00,$00C8FF,
   $FF0000,$00B050,
   $0000FF,$FF00FF,$FFFF00,$800080,$FFC8A0,$C8A06E,$E6B478,$00FFFF,
     $FF8080,$A0A0A0,
   $606060);
Var
 N:int64;K:LongInt;
 C,Best,V:LongInt;
Begin
 ImgAlloc(Img,S.W,S.H,False);
 N:=Int64(S.W)*S.H;
 For K:=0 to N-1 do Begin
  Best:=0;V:=-1;
  For C:=0 to NumCat-1 do If S.Cat[C][K]>V Then Begin V:=S.Cat[C][K];Best:=C;
    End;
  Img.Px[K*3]:=(Pal[Best]shr 16)and $FF;
  Img.Px[K*3+1]:=(Pal[Best]shr 8)and $FF;
  Img.Px[K*3+2]:=Pal[Best]and $FF;
 End;
End;

{ ------------------------------------------------------------------ }
{ Langage naturel (francais / anglais) : demande -> liste de retouches   }
{ ------------------------------------------------------------------ }

Const
 { genres de vetement }
 gkNone=0;gkTop=1;gkBottom=2;gkDress=3;gkFull=4;gkShoes=5;gkHat=6;gkGlasses=7;
 gkBag=8;gkScarf=9;gkBelt=10;gkSkirt=11;gkAll=12;gkHair=13;gkEyes=14;
   gkArms=15;gkBody=16;
 { natures de mots du lexique }
 lkGarment=1;lkColor=2;lkMod=3;lkPattern=4;lkVRecolor=5;lkVRemove=6;lkVTryOn=7;
 lkPrepDst=8;lkAll=9;lkVResult=10;lkSplit=11;lkVLight=12;lkSrcPrep=13;lkVAdd=14;
 lkHairStyle=15;lkJewel=16;lkJewelMod=17;lkStyle=18;lkExpr=19;
   lkMaterial=20;lkScene=21;lkPose2=22;
 lkSkin=23;lkYears=24;lkNumber=25;lkSpecial=26;lkSkinW=27;lkImgW=28;
   lkBgW=29;lkImgOp=30;lkBgKind=31;
 { modificateurs }
 mdDark=1;mdLight=2;mdVivid=3;mdPale=4;mdDull=5;
 { motifs }
 pkNone=0;pkStripes=1;pkChecks=2;pkDots=3;pkPlain=4;
 { actions }
 eaNone=0;eaRecolor=1;eaRemove=2;eaTryOn=3;eaAdd=4;eaHair=5;eaStyle=6;
   eaFace=7;eaPose=8;eaMaterial=9;eaScene=10;eaPose2=11;eaSkin=12;
   eaImage=13;eaBg=14;
 { poses et situations }
 pcCross=1;pcPeace=2;pcPoint=3;pcFloat=4;pcJump=5;pcArmsOut=6;
   pcLie=7;pcHeadStraight=8;pcLost=9;
 pcSerious=10;pcSad=11;pcHalo=12;pcSleep=13;pcSit=14;pcKneel=15;pcBike=16;
   pcLean=17;pcStairs=18;
 pcDoghouse=19;pcTightrope=20;pcBed=21;
 { poses qui montrent la personne en pied }
 FeetPoses=(1 shl pcFloat)or(1 shl pcJump)or(1 shl pcLie)or(1 shl pcBed)or(1 shl
   pcTightrope)or(1 shl pcDoghouse)or(1 shl pcStairs)or(1 shl pcSleep);
 { peau, age, teintes speciales }
 soSmooth=1;soGrain=2;soBaby=3;soSoft=4;soAge=5;soSalt=6;
 { image entiere et arriere-plan }
 ioSmooth=1;ioBlur=2;ioSharp=3;
 boSolid=1;boTransparent=2;boStars=3;boSunny=4;boSunset=5;boBlur=6;
 boTropical=7;boAmazon=8;boQuebec=9;boCanada=10;boConifer=11;boForest=12;
 { matieres et scenes }
 mtNone=0;mtMetal=1;mtRobot=2;mtStatue=3;mtChain=4;
 scNone=0;scCarousel=1;
 { coiffures }
 hsNone=0;hsLonger=1;hsShorter=2;hsCurly=3;hsBald=4;hsStraight=5;
 { bijoux (indicateurs) }
 jwNecklace=1;jwEarrings=2;jwBracelet=4;jwWatch=8;jwRing=16;
 { styles d'image }
 stNone=0;stComic=1;stCartoon=2;stSketch=3;stReal=4;

Const
 msEyes=LongWord(1)shl 30;

Type
 TLex=Record
  W:String[24];
  Kind:LongInt;
  V1:LongInt;
  V2:LongWord;
 End;
 TEdit=Record
  Action:LongInt;
  Target:LongWord;          { ensemble de categories visees (0 = non precise) }
  Kind:LongInt;             { genre du vetement vise }
  HasSrc,HasDst:Boolean;
  SrcRGB,DstRGB:LongWord;
  SrcName,DstName:AnsiString;
  LGain,CGain:Single;       { 1 = inchange }
  Pattern:LongInt;
  HasColor2:Boolean;
  Color2RGB:LongWord;
  Color2Name:AnsiString;
  DstGarment:LongInt;       { genre de vetement cite comme resultat }
  Noun:AnsiString;          { mot designant le vetement vise }
  HairStyle,Jewel,Style,Expr:LongInt;
  Pose:Boolean;
  Material,Scene:LongInt;
  Poses:LongWord;
  ImgOp,BgOp:LongInt;       { operation sur l'image entiere / sur l'arriere-plan
    }
  SkinOp,Years:LongInt;     { peau / age (annees, negatif = rajeunir) / teinte
    speciale }
  Diamond,Apple:Boolean;
  Put:Boolean;              { ? mets un chapeau ? : ajout si l'objet est absent
    }
  Text:AnsiString;
 End;
 TEditArray=Array of TEdit;

Var
 Lex:Array[0..1023]of TLex;
 NLex:LongInt=0;
 Phrase:Array[0..127]of TLex;
 NPhrase:LongInt=0;
 LexReady:Boolean=False;

Procedure AddLex(Const Words:AnsiString;Kind,V1:LongInt;V2:LongWord);
Var
 I,P:LongInt;
 W:AnsiString;
Begin
 P:=1;
 For I:=1 to Length(Words)+1 do
  If(I>Length(Words))or(Words[I]=' ')Then Begin
   W:=Copy(Words,P,I-P);
   P:=I+1;
   If W<>'' Then Begin
    Lex[NLex].W:=W;Lex[NLex].Kind:=Kind;Lex[NLex].V1:=V1;Lex[NLex].V2:=V2;
    Inc(NLex);
   End;
  End;
End;

Procedure AddPhrase(Const Words:AnsiString;RGB:LongWord);
Begin
 Phrase[NPhrase].W:=Words;
 Phrase[NPhrase].Kind:=lkColor;
 Phrase[NPhrase].V1:=0;
 Phrase[NPhrase].V2:=RGB;
 Inc(NPhrase);
End;

Function RgbOf(R,G,B:LongWord):LongWord;
Begin
 RgbOf:=(R shl 16)or(G shl 8)or B;
End;

Procedure LexInit;
Begin
 If LexReady Then Exit;
 LexReady:=True;
 { vetements : genre, ensemble de categories }
 AddLex('chandail pull tricot chemise chemisier tshirt polo veste blouson '+
   'manteau parka veston blazer cardigan gilet sweat sweatshirt hoodie '+
   'camisole debardeur top maillot jersey doudoune imper trench tunique '+
   'shirt sweater jumper jacket coat blouse tank vest turtleneck haut',
   lkGarment,gkTop,msTop);
 AddLex('pantalon jean short bermuda legging pants trousers slacks chinos '+
   'jogging',lkGarment,gkBottom,msPants);
 AddLex('jupe skirt',lkGarment,gkSkirt,msSkirt);
 AddLex('robe dress combinaison jumpsuit',lkGarment,gkDress,msDress);
 AddLex('chaussure soulier botte basket espadrille sandale escarpin sneaker '+
   'shoe boot sandal tennis pied pieds feet foot',lkGarment,gkShoes,msShoes);
 AddLex('chapeau casquette tuque bonnet beret hat cap beanie',lkGarment,
   gkHat,msHat);
 AddLex('lunette lunettes glasses sunglasses eyeglasses',lkGarment,
   gkGlasses,msGlasses);
 AddLex('sac sacoche bag handbag purse backpack',lkGarment,gkBag,msBag);
 AddLex('foulard echarpe cravate scarf tie shawl chale',lkGarment,
   gkScarf,msScarf);
 AddLex('ceinture belt',lkGarment,gkBelt,msBelt);
 AddLex('vetement habit tenue outfit clothes clothing ensemble costume',
   lkGarment,gkAll,msClothes);
 AddLex('tout tous toute toutes everything all',lkAll,0,0);
 { poses et situations }
 AddLex('croise croises croisee croisees',lkPose2,pcCross,0);
 AddLex('peace paix victoire',lkPose2,pcPeace,0);
 AddLex('pointe pointer pointant doigt',lkPose2,pcPoint,0);
 AddLex('flotte flotter flottant flottante levite levitation float floating',
   lkPose2,pcFloat,0);
 AddLex('saute sauter saut jump jumping',lkPose2,pcJump,0);
 AddLex('couche coucher couchee couches',lkPose2,pcLie,0);
 AddLex('tete head',lkPose2,pcHeadStraight,0);
 AddLex('perdu perdue lost',lkPose2,pcLost,0);
 AddLex('serieux serieuse serious',lkPose2,pcSerious,0);
 AddLex('triste tristes sad',lkPose2,pcSad,0);
 AddLex('aureole halo',lkPose2,pcHalo,0);
 AddLex('somnambule somnambules sleepwalker sleepwalking',lkPose2,pcSleep,0);
 AddLex('assis assise assises assoit asseoir seated sitting sit',lkPose2,pcSit,
   0);
 AddLex('genou genoux kneeling kneel',lkPose2,pcKneel,0);
 AddLex('bicyclette velo bike bicycle cycling',lkPose2,pcBike,0);
 AddLex('appuie appuye appuyer appuyee appuyant meuble meubles lean leaning',
   lkPose2,pcLean,0);
 AddLex('escalier escaliers stairs staircase monte monter',lkPose2,pcStairs,0);
 AddLex('niche doghouse',lkPose2,pcDoghouse,0);
 AddLex('fer funambule tightrope',lkPose2,pcTightrope,0);
 AddLex('lit bed',lkPose2,pcBed,0);
 { corps, matieres, scenes }
 AddLex('corps body',lkGarment,gkBody,msSkin);
 AddLex('metallique metallic metal chrome chromee chromes',lkMaterial,mtMetal,
   0);
 AddLex('robot robots robotique robotiques robotic cyborg android',
   lkMaterial,mtRobot,0);
 AddLex('statue statues marbre marble pierre stone',lkMaterial,mtStatue,0);
 AddLex('maille mailles chainmail',lkMaterial,mtChain,0);
 AddLex('carrousel carroussel carousel manege merry',lkScene,scCarousel,0);
 AddLex('bronze',lkColor,0,RgbOf(176,112,52));
 AddLex('cuivre copper',lkColor,0,RgbOf(184,115,51));
 { yeux, bras, expressions }
 AddLex('oeil yeux eye eyes iris',lkGarment,gkEyes,msEyes);
 AddLex('bras arm arms',lkGarment,gkArms,msArms);
 AddLex(
   'sourit sourire sourires souriant souriante souriants souriantes smile '+
   'smiling smiley',lkExpr,1,0);
 { peau, age, teintes speciales }
 AddLex('peau peaux skin complexion teint',lkSkinW,0,0);
 AddLex('lisse lisses lisser smooth smoother smoothing',lkSkin,soSmooth,0);
 AddLex(
   'granuleux granuleuse granuleuses grain grains grainy rugueux rugueuse '+
   'rough texturee textured',lkSkin,soGrain,0);
 AddLex('bebe baby',lkSkin,soBaby,0);
 AddLex('douce douces doux soft softer',lkSkin,soSoft,0);
 AddLex('rajeunis rajeunir rajeunie rajeunissez rajeunit jeune jeunes younger '+
   'rejuvenate',lkYears,-1,0);
 AddLex(
   'vieillis vieillir vieillie vieillissez vieillit vieux vieille vieilles '+
   'older',lkYears,1,0);
 AddLex('cinq five',lkNumber,5,0);
 AddLex('dix ten',lkNumber,10,0);
 AddLex('quinze fifteen',lkNumber,15,0);
 AddLex('vingt twenty',lkNumber,20,0);
 AddLex('trente thirty',lkNumber,30,0);
 AddLex('poivresel',lkSpecial,1,0);
 { image entiere et arriere-plan }
 AddLex('image images picture pictures photo photos photographie',lkImgW,0,0);
 AddLex('fond arriere background backdrop decor',lkBgW,0,0);
 AddLex('lisse lisses lisser smooth smoother',lkImgOp,ioSmooth,0);
 AddLex('flou floue floues floux flouter floute blur blurry blurred blurrier',
   lkImgOp,ioBlur,0);
 AddLex('net nette nets nettes nettete sharp sharper sharpen',lkImgOp,ioSharp,
   0);
 AddLex('transparent transparente transparents transparentes transparence '+
   'transparency',lkBgKind,boTransparent,0);
 AddLex('etoile etoilee etoilees etoiles star stars starry',lkBgKind,boStars,0);
 AddLex('ensoleille ensoleillee ensoleilles soleil sunny sun sunshine',
   lkBgKind,boSunny,0);
 AddLex('sunset crepuscule',lkBgKind,boSunset,0);
 AddLex('foret forets forest forests jungle',lkBgW,0,0);
 AddLex('foret forets forest forests',lkBgKind,boForest,0);
 AddLex('tropicale tropicales tropical jungle',lkBgKind,boTropical,0);
 AddLex('amazonienne amazoniennes amazonien amazoniens amazonie amazonian '+
   'amazon amazone',lkBgKind,boAmazon,0);
 AddLex('quebecoise quebecoises quebecois quebec erable erables maple',
   lkBgKind,boQuebec,0);
 AddLex('canadienne canadiennes canadien canadiens canada canadian boreale '+
   'boreal',lkBgKind,boCanada,0);
 AddLex('conifere coniferes conifer conifers sapin sapins epinette epinettes '+
   'pin pins pine pines spruce fir taiga',lkBgKind,boConifer,0);
 { cheveux et coiffures }
 AddLex('cheveu cheveux chevelure coiffure hair hairstyle',lkGarment,
   gkHair,msHair);
 AddLex(
   'allonge allonger allongez rallonge rallonger long longs longue longues '+
   'lengthen longer',lkHairStyle,hsLonger,0);
 AddLex(
   'court courts courte courtes raccourcis raccourcir raccourcit raccourci '+
   'coupe couper coupez shorter shorten',lkHairStyle,hsShorter,0);
 AddLex('frise frises frisee frisees friser curly curls wavy ondule ondules '+
   'ondulee ondulees boucle boucles bouclee bouclees curl',lkHairStyle,hsCurly,
   0);
 AddLex('chauve bald',lkHairStyle,hsBald,0);
 AddLex('raide raides lisse lisses straight',lkHairStyle,hsStraight,0);
 { bijoux }
 AddLex('bijou bijoux jewelry jewellery jewel jewels parure',lkJewel,
   jwNecklace+jwEarrings+jwBracelet,0);
 AddLex('collier colliers necklace pendentif pendant chaine chain',
   lkJewel,jwNecklace,0);
 AddLex('oreille oreilles earring earrings',lkJewel,jwEarrings,0);
 AddLex('bracelet bracelets bangle bangles',lkJewel,jwBracelet,0);
 AddLex('montre montres watch watches',lkJewel,jwWatch,0);
 AddLex('bague bagues ring rings',lkJewel,jwRing,0);
 AddLex('diamant diamants diamond diamonds brillant brillants',lkJewelMod,1,0);
 AddLex('apple',lkJewelMod,2,0);
 { styles d'image }
 AddLex('bd bande dessinee dessinees comic comics',lkStyle,stComic,0);
 AddLex('cartoon cartoons dessin dessins anime animation animee',
   lkStyle,stCartoon,0);
 AddLex('croquis sketch crayon',lkStyle,stSketch,0);
 AddLex(
   'reel reelle reels realiste realistes realistic real photo photographie '+
   'photorealiste photorealistic',lkStyle,stReal,0);
 { couleurs }
 AddLex('rouge red',lkColor,0,RgbOf(200,30,40));
 AddLex('bleu bleue blue',lkColor,0,RgbOf(30,70,200));
 AddLex('vert verte green',lkColor,0,RgbOf(40,150,70));
 AddLex('jaune yellow',lkColor,0,RgbOf(240,210,40));
 AddLex('orange',lkColor,0,RgbOf(240,130,30));
 AddLex('rose pink',lkColor,0,RgbOf(245,150,180));
 AddLex('violet violette purple mauve pourpre',lkColor,0,RgbOf(130,60,170));
 AddLex('marron brun brune brown',lkColor,0,RgbOf(110,70,40));
 AddLex('beige tan',lkColor,0,RgbOf(225,205,170));
 AddLex('noir noire black',lkColor,0,RgbOf(22,22,25));
 AddLex('blanc blanche white',lkColor,0,RgbOf(245,245,245));
 AddLex('blond blonde blondes blonds',lkColor,0,RgbOf(222,185,105));
 AddLex('roux rousse rousses auburn',lkColor,0,RgbOf(168,70,28));
 AddLex('chatain chatains chataine',lkColor,0,RgbOf(98,64,40));
 AddLex('platine platinum',lkColor,0,RgbOf(232,228,210));
 AddLex('gris grise gray grey',lkColor,0,RgbOf(128,128,128));
 AddLex('turquoise teal',lkColor,0,RgbOf(40,185,185));
 AddLex('cyan',lkColor,0,RgbOf(0,190,230));
 AddLex('magenta',lkColor,0,RgbOf(210,30,150));
 AddLex('fuchsia',lkColor,0,RgbOf(230,40,160));
 AddLex('bordeaux burgundy maroon grenat',lkColor,0,RgbOf(110,20,40));
 AddLex('kaki khaki',lkColor,0,RgbOf(130,130,70));
 AddLex('marine navy',lkColor,0,RgbOf(20,35,90));
 AddLex('or dore gold golden',lkColor,0,RgbOf(212,175,55));
 AddLex('argent argente silver',lkColor,0,RgbOf(190,190,195));
 AddLex('lavande lavender lilas lilac',lkColor,0,RgbOf(185,160,220));
 AddLex('saumon salmon',lkColor,0,RgbOf(250,130,110));
 AddLex('corail coral',lkColor,0,RgbOf(255,110,90));
 AddLex('moutarde mustard',lkColor,0,RgbOf(210,170,40));
 AddLex('olive',lkColor,0,RgbOf(110,120,40));
 AddLex('creme cream ivoire ivory',lkColor,0,RgbOf(255,248,220));
 AddLex('camel',lkColor,0,RgbOf(190,140,80));
 AddLex('indigo',lkColor,0,RgbOf(50,40,130));
 AddLex('menthe mint',lkColor,0,RgbOf(150,225,180));
 AddLex('emeraude emerald',lkColor,0,RgbOf(20,140,90));
 AddLex('denim',lkColor,0,RgbOf(60,90,140));
 AddLex('anthracite charcoal',lkColor,0,RgbOf(55,58,64));
 AddLex('ciel',lkColor,0,RgbOf(130,190,235));
 AddLex('paille straw osier wicker',lkColor,0,RgbOf(222,190,110));
 AddPhrase('bleu marine',RgbOf(20,35,90));
 AddPhrase('bleu ciel',RgbOf(130,190,235));
 AddPhrase('bleu roi',RgbOf(40,70,210));
 AddPhrase('bleu royal',RgbOf(40,70,210));
 AddPhrase('royal blue',RgbOf(40,70,210));
 AddPhrase('bleu nuit',RgbOf(15,20,70));
 AddPhrase('bleu turquoise',RgbOf(40,185,185));
 AddPhrase('sky blue',RgbOf(130,190,235));
 AddPhrase('navy blue',RgbOf(20,35,90));
 AddPhrase('vert pomme',RgbOf(130,200,50));
 AddPhrase('vert bouteille',RgbOf(10,70,40));
 AddPhrase('vert olive',RgbOf(110,120,40));
 AddPhrase('vert menthe',RgbOf(150,225,180));
 AddPhrase('vert emeraude',RgbOf(20,140,90));
 AddPhrase('vert sapin',RgbOf(20,80,50));
 AddPhrase('lime green',RgbOf(130,200,50));
 AddPhrase('forest green',RgbOf(25,90,45));
 AddPhrase('hot pink',RgbOf(240,60,150));
 AddPhrase('rose bonbon',RgbOf(240,100,170));
 AddPhrase('rose pale',RgbOf(250,205,215));
 AddPhrase('rouge vif',RgbOf(230,20,30));
 AddPhrase('jaune moutarde',RgbOf(210,170,40));
 AddPhrase('gris anthracite',RgbOf(55,58,64));
 AddPhrase('gris perle',RgbOf(200,200,205));
 AddPhrase('gris souris',RgbOf(120,120,125));
 { modificateurs de teinte }
 AddLex('fonce foncee sombre dark deep',lkMod,mdDark,0);
 AddLex('clair claire light lighter pale pales pastel',lkMod,mdLight,0);
 AddLex('vif vive vives vifs vivid bright saturated sature saturee',
   lkMod,mdVivid,0);
 AddLex('terne ternes dull muted delave delavee faded desature',lkMod,mdDull,0);
 AddLex('eclaircis eclaircir lighten brighten',lkVLight,mdLight,0);
 AddLex('assombris assombrir darken fonce',lkVLight,mdDark,0);
 { motifs }
 AddLex('rayure rayures raye raye rayee rayees stripe stripes striped',
   lkPattern,pkStripes,0);
 AddLex('carreau carreaux carre carres plaid tartan ecossais ecossaise '+
   'checkered checked gingham vichy',lkPattern,pkChecks,0);
 AddLex('pois polka dots dotted',lkPattern,pkDots,0);
 AddLex('uni unie unis unies solid plain',lkPattern,pkPlain,0);
 { verbes }
 AddLex('change changer changez modifie modifier modifiez transforme '+
   'transformer colorie colorier colorer teinte teindre peins peindre '+
   'repeins repeindre recolor recolorer convertis convertir change switch '+
   'swap remplace remplacer replace',lkVRecolor,0,0);
 AddLex('rends rendre mets met mettre passe passer make turn paint dye color '+
   'colour',lkVResult,0,0);
 AddLex('enleve enlever enlevez retire retirer retirez supprime supprimer '+
   'supprimez efface effacer effacez ote oter remove delete erase sans '+
   'without',lkVRemove,0,0);
 AddLex('essaie essaye essayer essayez porte porter habille habiller try wear',
   lkVTryOn,0,0);
 AddLex(
   'ajoute ajouter ajoutez rajoute rajouter add append equipe equiper give '+
   'donne donner voir montre montrer montrez show see display',lkVAdd,0,0);
 { prepositions de destination }
 AddLex('en in into to par by as vers pour for',lkPrepDst,0,0);
 AddLex('de from',lkSrcPrep,0,0);
 AddLex('et and puis then ensuite afterwards also aussi',lkSplit,0,0);
End;

{ ---- normalisation du texte : UTF-8 -> minuscules ASCII ---- }

{ remplace toutes les occurrences }
Function StrReplace(Const S,A,B:AnsiString):AnsiString;
Var
 R:AnsiString;
 P:LongInt;
Begin
 R:=S;
 P:=Pos(A,R);
 While P>0 do Begin
  R:=Copy(R,1,P-1)+B+Copy(R,P+Length(A),Length(R));
  P:=Pos(A,R);
 End;
 StrReplace:=R;
End;

Function FoldText(Const S:AnsiString):AnsiString;
Var
 R:AnsiString;
 I,N,B,B2,B3,Code:LongInt;
 C:Char;
 Function Fold1(Code:LongInt):AnsiString;
 Begin
  Fold1:=' ';
  Case Code of
   192..197,224..229:Fold1:='a';
   199,231:Fold1:='c';
   200..203,232..235:Fold1:='e';
   204..207,236..239:Fold1:='i';
   209,241:Fold1:='n';
   210..214,242..246:Fold1:='o';
   217..220,249..252:Fold1:='u';
   221,253,255:Fold1:='y';
   338,339:Fold1:='oe';
   198,230:Fold1:='ae';
   8217,8216,180,96:Fold1:=' ';
  End;
 End;
Begin
 R:='';
 N:=Length(S);
 I:=1;
 While I<=N do Begin
  B:=Ord(S[I]);
  Code:=B;
  If B<$80 Then Inc(I)
  Else If(B and $E0)=$C0 Then Begin
   If I+1<=N Then Code:=((B and $1F)shl 6)or(Ord(S[I+1])and $3F);
   Inc(I,2);
  End
   Else If(B and $F0)=$E0 Then Begin
    If I+2<=N Then Code:=((B and $0F)shl 12)or((Ord(S[I+1])and $3F)shl 6)
      or(Ord(S[I+2])and $3F);
    Inc(I,3);
   End
    Else If(B and $F8)=$F0 Then Begin Code:=0;Inc(I,4);End
    Else Begin
     { octet isole : page ANSI (Latin-1) }
     Inc(I);
    End;
  If Code<128 Then Begin
   C:=Chr(Code);
   If C in['A'..'Z']Then C:=Chr(Ord(C)+32);
   If C in['a'..'z','0'..'9','#',',',';','.','-']Then R:=R+C
   Else If C in['!','?']Then R:=R+'.'
   Else R:=R+' ';
  End
   Else R:=R+Fold1(Code);
 End;
 { t-shirt et consorts }
 B:=Pos('t-shirt',R);
 While B>0 do Begin Delete(R,B+1,1);B:=Pos('t-shirt',R);End;
 B:=Pos('tee-shirt',R);
 While B>0 do Begin Delete(R,B+3,1);B:=Pos('tee-shirt',R);End;
 B:=Pos('tee shirt',R);
 While B>0 do Begin Delete(R,B+3,1);B:=Pos('tee shirt',R);End;
 B:=Pos('teeshirt',R);
 While B>0 do Begin Delete(R,B,3);B:=Pos('teeshirt',R);End;
 For I:=1 to Length(R)do If R[I]='-' Then R[I]:=' ';
 { poivre et sel : un seul mot (sinon ? et ? couperait la demande) }
 R:=' '+R+' ';
 R:=StrReplace(R,' poivre et sel ',' poivresel ');
 R:=StrReplace(R,' poivre sel ',' poivresel ');
 R:=StrReplace(R,' sel et poivre ',' poivresel ');
 R:=StrReplace(R,' sel poivre ',' poivresel ');
 R:=StrReplace(R,' salt and pepper ',' poivresel ');
 R:=StrReplace(R,' salt pepper ',' poivresel ');
 R:=StrReplace(R,' coucher de soleil ',' sunset ');
 R:=StrReplace(R,' coucher du soleil ',' sunset ');
 R:=StrReplace(R,' coucher de soliel ',' sunset ');
 FoldText:=TrimS(R);
End;

{ decoupe en mots ; ',', ';' et '.' deviennent des mots a part }
Procedure Tokenize(Const S:AnsiString;Var T:TStrArray);
Var
 I:LongInt;
 Cur:AnsiString;
Begin
 SetLength(T,0);
 Cur:='';
 For I:=1 to Length(S)do Begin
  If S[I]in[',',';','.']Then Begin
   If Cur<>'' Then AddStr(T,Cur);
   Cur:='';
   AddStr(T,S[I]);
  End
   Else If S[I]=' ' Then Begin
    If Cur<>'' Then AddStr(T,Cur);
    Cur:='';
   End
   Else Cur:=Cur+S[I];
 End;
 If Cur<>'' Then AddStr(T,Cur);
End;

{ cherche un mot du lexique (avec variantes de pluriel) ; renvoie l'indice ou -1
  }
Function LexFind(Const W:AnsiString;Kind:LongInt):LongInt;
Var
 I,L:LongInt;
 V1,V2,V3:AnsiString;
Begin
 LexFind:=-1;
 L:=Length(W);
 V1:=W;V2:='';V3:='';
 If(L>3)and(W[L]='s')Then V2:=Copy(W,1,L-1);
 If(L>4)and(Copy(W,L-1,2)='es')Then V3:=Copy(W,1,L-2);
 If(L>3)and(W[L]='x')Then V3:=Copy(W,1,L-1);
 For I:=0 to NLex-1 do
  If(Lex[I].Kind=Kind)or(Kind=0)Then
   If(Lex[I].W=V1)or((V2<>'')and(Lex[I].W=V2))or((V3<>'')and(Lex[I].W=V3))
     Then Begin
    LexFind:=I;Exit;
   End;
End;

Function IsHexColor(Const W:AnsiString;Var RGB:LongWord):Boolean;
Var
 I,V:LongInt;
 D:Array[0..5]of LongInt;
Begin
 IsHexColor:=False;
 If(Length(W)<>4)and(Length(W)<>7)Then Exit;
 If W[1]<>'#' Then Exit;
 For I:=2 to Length(W)do If HexVal(W[I])<0 Then Exit;
 If Length(W)=4 Then Begin
  For I:=0 to 2 do D[I*2]:=HexVal(W[I+2])*17;
  RGB:=(D[0]shl 16)or(D[2]shl 8)or D[4];
 End
  Else Begin
   V:=0;
   For I:=2 to 7 do V:=V*16+HexVal(W[I]);
   RGB:=V;
  End;
 IsHexColor:=True;
End;

{ lit une couleur a la position I (mots composes, modificateurs adjacents) ;
  Used : nombre de mots consommes ; renvoie faux si ce n'est pas une couleur }
Function ReadColor(Const T:TStrArray;I:LongInt;Var RGB:LongWord;Var
  Name:AnsiString;
  Var Used:LongInt;Var Mod_:LongInt):Boolean;
Var
 K,X:LongInt;
 J:LongInt;
Begin
 ReadColor:=False;
 Mod_:=0;Used:=1;
 If IsHexColor(T[I],RGB)Then Begin Name:=T[I];ReadColor:=True;Exit;End;
 If I+1<=High(T)Then
  For K:=0 to NPhrase-1 do If Phrase[K].W=T[I]+' '+T[I+1]Then Begin
   RGB:=Phrase[K].V2;Name:=T[I]+' '+T[I+1];Used:=2;ReadColor:=True;Exit;
  End;
 K:=LexFind(T[I],lkColor);
 If K<0 Then Exit;
 RGB:=Lex[K].V2;Name:=T[I];
 { modificateur juste apres : ? bleu fonce ? }
 If I+1<=High(T)Then Begin
  X:=LexFind(T[I+1],lkMod);
  If X>=0 Then Begin Mod_:=Lex[X].V1;Used:=2;Name:=Name+' '+T[I+1];End;
 End;
 { modificateur juste avant : ? dark blue ? (deja consomme par l'appelant) }
 ReadColor:=True;
End;

{ applique un modificateur de teinte a une couleur RVB }
Function ApplyShade(RGB:LongWord;Md:LongInt):LongWord;
Var
 R,G,B,L,A,Bb:Single;
 Cc:Single;
Begin
 ColorInit;
 If Md=0 Then Begin ApplyShade:=RGB;Exit;End;
 R:=(RGB shr 16)and $FF;G:=(RGB shr 8)and $FF;B:=RGB and $FF;
 RgbToLab(R,G,B,L,A,Bb);
 Case Md of
  mdDark:Begin L:=L*0.62;A:=A*0.95;Bb:=Bb*0.95;End;
  mdLight:Begin L:=L+(100-L)*0.45;A:=A*0.7;Bb:=Bb*0.7;End;
  mdVivid:Begin A:=A*1.3;Bb:=Bb*1.3;End;
  mdPale:Begin L:=L+(100-L)*0.35;A:=A*0.5;Bb:=Bb*0.5;End;
  mdDull:Begin A:=A*0.5;Bb:=Bb*0.5;End;
 End;
 LabToRgb(L,A,Bb,R,G,B);
 ApplyShade:=(Round(R)shl 16)or(Round(G)shl 8)or Round(B);
End;

Procedure ClearEdit(Var E:TEdit);
Begin
 FillChar(E,SizeOf(E),0);
 E.LGain:=1;E.CGain:=1;
 E.SrcName:='';E.DstName:='';E.Color2Name:='';E.Text:='';E.Noun:='';
End;

{ interprete une clause (mots T[A..B]) ; faux si elle ne contient rien
  d'exploitable }
Function ParseClause(Const T:TStrArray;A,B:LongInt;Var E:TEdit;Var
  HasChange:Boolean;
  Var HasVerb:Boolean):Boolean;
Var
 I,K,X,Used,Md,NCol,PrepPos,NTargets:LongInt;
 RGB:LongWord;
 Nm:AnsiString;
 Cols:Array[0..7]of LongWord;
 ColNames:Array[0..7]of AnsiString;
 ColPos:Array[0..7]of LongInt;
 ColMd:Array[0..7]of LongInt;
 Consumed:Array of Boolean;
 Remove,Result_,Recolor,TryOn,AllWord,AddV:Boolean;
 GarmNoun:Array[0..7]of AnsiString;
 FirstPrep:LongInt;
 SrcIdx,DstIdx,J:LongInt;
 GarmPos:Array[0..7]of LongInt;
 GarmKind:Array[0..7]of LongInt;
 GarmMask:Array[0..7]of LongWord;
 NG:LongInt;
 MdWord:LongInt;
 Gx:LongInt;
 HasPat:Boolean;
 HStyle,Jw,Sty:LongInt;
 HStrong,HairNoun,Dia,App,PoseWord,ChainCtx,MetalCol:Boolean;
 Expr,Mat,Scn:LongInt;
 Pz:LongWord;
 SkinW:Boolean;
 SkOp,Yrs,Num,Spec,Nv:LongInt;
 ImgW,BgW,ImgOpPresent,Demo:Boolean;
 IOp,BOp:LongInt;
Begin
 ParseClause:=False;
 ClearEdit(E);
 HasChange:=False;HasVerb:=False;
 SetLength(Consumed,High(T)+2);
 NCol:=0;NG:=0;
 Remove:=False;Result_:=False;Recolor:=False;TryOn:=False;AllWord:=False;
   AddV:=False;
 FirstPrep:=-1;
 HasPat:=False;
 HStyle:=0;Jw:=0;Sty:=0;HStrong:=False;Dia:=False;App:=False;
 HairNoun:=False;PoseWord:=False;Expr:=0;Mat:=0;Scn:=0;ChainCtx:=False;
   MetalCol:=False;Pz:=0;
 SkinW:=False;SkOp:=0;Yrs:=0;Num:=0;Spec:=0;
 ImgW:=False;BgW:=False;ImgOpPresent:=False;Demo:=False;IOp:=0;BOp:=0;
 For I:=A to B do Begin
  If LexFind(T[I],lkImgW)>=0 Then ImgW:=True;
  If LexFind(T[I],lkBgW)>=0 Then BgW:=True;
  If LexFind(T[I],lkImgOp)>=0 Then ImgOpPresent:=True;
  { ? cette tenue ?, ? ce chandail ? : le vetement de l'image fournie }
  If(T[I]='cette')or(T[I]='ce')or(T[I]='ces')or(T[I]='this')or(T[I]='these')
    or(T[I]='celle')or(T[I]='celui')or(T[I]='ceux')Then Demo:=True;
 End;
 For I:=A to B do If LexFind(T[I],lkSkinW)>=0 Then SkinW:=True;
 { ? vetement de chaine d'or ? : chaine + vetement = cotte de mailles, pas un
   collier }
 For I:=A to B do If LexFind(T[I],lkGarment)>=0 Then
  If Lex[LexFind(T[I],lkGarment)].V1 in[gkTop,gkBottom,gkDress,gkSkirt,
    gkAll,gkFull]Then ChainCtx:=True;
 For I:=A to B do If(T[I]='aligne')or(T[I]='aligner')or(T[I]='alignes')
   or(T[I]='alignee')or(T[I]='alignees')or
   (T[I]='alignez')or(T[I]='baisse')or(T[I]='baisser')or(T[I]='baissez')
     or(T[I]='cote')or(T[I]='cotes')or
   (T[I]='long')or(T[I]='droit')or(T[I]='droits')or(T[I]='droite')
     or(T[I]='droites')or(T[I]='descend')or
   (T[I]='descendre')or(T[I]='straight')or(T[I]='down')Then PoseWord:=True;
 For I:=A to B do If LexFind(T[I],lkGarment)>=0 Then
  If Lex[LexFind(T[I],lkGarment)].V1=gkHair Then HairNoun:=True;
 For I:=A to B do Begin
  If Consumed[I]Then Continue;
  { verbes }
  If LexFind(T[I],lkVRemove)>=0 Then Begin Remove:=True;HasVerb:=True;
    Continue;End;
  If(LexFind(T[I],lkVAdd)>=0)and not((I>A)and((T[I]='montre')or(T[I]='montres')
    ))Then Begin AddV:=True;HasVerb:=True;Continue;End;
  If LexFind(T[I],lkVTryOn)>=0 Then Begin TryOn:=True;HasVerb:=True;Continue;
    End;
  If LexFind(T[I],lkVResult)>=0 Then Begin Result_:=True;HasVerb:=True;
    Continue;End;
  If LexFind(T[I],lkAll)>=0 Then Begin AllWord:=True;Continue;End;
  { couleur (avec modificateur precedent eventuel) }
  Md:=0;
  If ReadColor(T,I,RGB,Nm,Used,Md)Then Begin
   If(Md=0)and(I>A)Then Begin
    X:=LexFind(T[I-1],lkMod);
    If(X>=0)and not Consumed[I-1]Then Begin Md:=Lex[X].V1;Consumed[I-1]:=True;
      Nm:=T[I-1]+' '+Nm;End;
   End;
   If NCol<8 Then Begin
    Cols[NCol]:=ApplyShade(RGB,Md);ColNames[NCol]:=Nm;ColPos[NCol]:=I;
      ColMd[NCol]:=Md;
    Inc(NCol);
   End;
   For K:=1 to Used-1 do Consumed[I+K]:=True;
   Continue;
  End;
  { image entiere et arriere-plan }
  If BgW Then Begin
   K:=LexFind(T[I],lkBgKind);
   If K>=0 Then Begin
    { ? foret ? seul ne remplace pas un type de foret deja precise }
    If Lex[K].V1=boForest Then Begin If BOp=0 Then BOp:=boForest;End Else
      BOp:=Lex[K].V1;
    Continue;
   End;
   K:=LexFind(T[I],lkImgOp);
   If(K>=0)and(Lex[K].V1=ioBlur)Then Begin BOp:=boBlur;Continue;End;
  End
  Else If ImgW Then Begin
   K:=LexFind(T[I],lkImgOp);
   If K>=0 Then Begin IOp:=Lex[K].V1;Continue;End;
   If ImgOpPresent and((T[I]='photo')or(T[I]='photos')or(T[I]='photographie')
     )Then Continue;
  End;
  { nombres (annees), peau, age, teintes speciales }
  If(T[I]<>'')and(T[I][1]in['0'..'9'])Then Begin
   Nv:=0;
   For K:=1 to Length(T[I])do If T[I][K]in['0'..'9']Then Nv:=Nv*10+Ord(T[I][K])
     -48;
   If Nv>0 Then Num:=Nv;
   Continue;
  End;
  K:=LexFind(T[I],lkNumber);
  If K>=0 Then Begin Num:=Lex[K].V1;Continue;End;
  K:=LexFind(T[I],lkYears);
  If K>=0 Then Begin Yrs:=Lex[K].V1;HasVerb:=True;Continue;End;
  K:=LexFind(T[I],lkSpecial);
  If K>=0 Then Begin Spec:=Lex[K].V1;Continue;End;
  If SkinW Then Begin
   K:=LexFind(T[I],lkSkin);
   If K>=0 Then Begin SkOp:=Lex[K].V1;Continue;End;
  End;
  { bijoux, styles d'image, coiffures }
  K:=LexFind(T[I],lkPose2);
  If K>=0 Then Begin
   { ? tete ? compte seulement dans ? tete droite ? }
   If(Lex[K].V1<>pcHeadStraight)or PoseWord Then Pz:=Pz or(LongWord(1)shl
     Lex[K].V1);
   Continue;
  End;
  K:=LexFind(T[I],lkMaterial);
  If K>=0 Then Begin Mat:=Lex[K].V1;Continue;End;
  K:=LexFind(T[I],lkScene);
  If K>=0 Then Begin Scn:=Lex[K].V1;Continue;End;
  K:=LexFind(T[I],lkJewel);
  If K>=0 Then Begin
   If ChainCtx and((T[I]='chaine')or(T[I]='chaines')or(T[I]='chain'))Then
     Mat:=mtChain
   Else Jw:=Jw or Lex[K].V1;
   Continue;
  End;
  K:=LexFind(T[I],lkJewelMod);
  If K>=0 Then Begin If Lex[K].V1=1 Then Dia:=True Else App:=True;Continue;End;
  K:=LexFind(T[I],lkStyle);
  If K>=0 Then Begin Sty:=Lex[K].V1;Continue;End;
  K:=LexFind(T[I],lkExpr);
  If K>=0 Then Begin Expr:=Lex[K].V1;Continue;End;
  If HairNoun and(T[I]='short')Then Begin HStyle:=hsShorter;Continue;End;
  K:=LexFind(T[I],lkHairStyle);
  If K>=0 Then Begin
   { ? boucles ? seul est ambigu (boucles d'oreilles) : il faut le mot cheveux }
   If(Lex[K].V1<>hsCurly)or HairNoun or(Pos('boucle',T[I])=0)Then Begin
    HStyle:=Lex[K].V1;
    If HairNoun Then HStrong:=True Else If Lex[K].V1 in[hsBald,
      hsLonger,hsShorter]Then HStrong:=True;
   End;
   Continue;
  End;
  { motifs }
  K:=LexFind(T[I],lkPattern);
  If K>=0 Then Begin E.Pattern:=Lex[K].V1;HasPat:=True;Continue;End;
  { vetements }
  K:=LexFind(T[I],lkGarment);
  If K>=0 Then Begin
   If NG<8 Then Begin GarmPos[NG]:=I;GarmKind[NG]:=Lex[K].V1;
     GarmMask[NG]:=Lex[K].V2;GarmNoun[NG]:=T[I];Inc(NG);End;
   Continue;
  End;
  { clair/fonce hors d'une couleur : reglage de luminosite }
  K:=LexFind(T[I],lkMod);
  If K<0 Then Begin
   K:=LexFind(T[I],lkVLight);
   If K>=0 Then Begin MdWord:=Lex[K].V1;HasVerb:=True;End Else MdWord:=0;
  End
   Else MdWord:=Lex[K].V1;
  If MdWord<>0 Then Begin
   Case MdWord of
    mdDark:E.LGain:=E.LGain*0.62;
    mdLight:Begin E.LGain:=E.LGain*1.3;E.CGain:=E.CGain*0.85;End;
    mdVivid:E.CGain:=E.CGain*1.4;
    mdPale,mdDull:E.CGain:=E.CGain*0.6;
   End;
   Continue;
  End;
  If(FirstPrep<0)and(LexFind(T[I],lkPrepDst)>=0)Then FirstPrep:=I;
  If LexFind(T[I],lkVRecolor)>=0 Then Begin Recolor:=True;HasVerb:=True;End;
 End;
 { vetements cibles : ceux situes avant la preposition de destination, sinon
   tous }
 NTargets:=0;
 E.Target:=0;E.Kind:=gkNone;
 For I:=0 to NG-1 do
  If(FirstPrep<0)or(GarmPos[I]<FirstPrep)Then Begin
   E.Target:=E.Target or GarmMask[I];
   If E.Kind=gkNone Then Begin E.Kind:=GarmKind[I];E.Noun:=GarmNoun[I];End;
   Inc(NTargets);
  End;
 If(NTargets=0)and(NG>0)Then Begin
  { ? en chemise bleue ? sans cible : la cible reste a determiner, le genre est
    un resultat }
  E.DstGarment:=GarmKind[0];
 End
  Else If(FirstPrep>=0)Then
   For I:=0 to NG-1 do If GarmPos[I]>FirstPrep Then Begin
     E.DstGarment:=GarmKind[I];Break;End;
 If AllWord and(E.Target=0)Then Begin E.Target:=msClothes;E.Kind:=gkAll;End;
 { couleurs : source / destination }
 SrcIdx:=-1;DstIdx:=-1;
 If NCol>0 Then Begin
  If FirstPrep>=0 Then Begin
   For I:=0 to NCol-1 do
    If ColPos[I]>FirstPrep Then Begin
     If DstIdx<0 Then DstIdx:=I
     Else If(E.Pattern<>pkNone)and not E.HasColor2 Then Begin
      E.HasColor2:=True;E.Color2RGB:=Cols[I];E.Color2Name:=ColNames[I];
     End;
    End
    Else If SrcIdx<0 Then SrcIdx:=I;
   If DstIdx<0 Then Begin
    { ? change le rouge en motif... ? ou couleur avant la preposition seule }
    If SrcIdx>=0 Then Begin
     If NCol=1 Then Begin DstIdx:=SrcIdx;SrcIdx:=-1;End;
    End;
   End;
  End
   Else Begin
    If NCol>=2 Then Begin
     If E.Pattern<>pkNone Then Begin
      DstIdx:=0;E.HasColor2:=True;E.Color2RGB:=Cols[1];
        E.Color2Name:=ColNames[1];
     End
      Else Begin
       { sans preposition : ? change le rouge bleu ? ou ? rends le pull rouge et
         noir ? }
       If Recolor and not Result_ Then Begin SrcIdx:=0;DstIdx:=1;End
       Else Begin DstIdx:=0;E.HasColor2:=True;E.Color2RGB:=Cols[1];
         E.Color2Name:=ColNames[1];End;
      End;
    End
     Else DstIdx:=0;
   End;
 End;
 If SrcIdx>=0 Then Begin E.HasSrc:=True;E.SrcRGB:=Cols[SrcIdx];
   E.SrcName:=ColNames[SrcIdx];End;
 If DstIdx>=0 Then Begin E.HasDst:=True;E.DstRGB:=Cols[DstIdx];
   E.DstName:=ColNames[DstIdx];End;
 { le motif sans couleur de fond : second ton blanc (ou noir sur couleur claire)
   }
 If(E.Pattern in[pkStripes,pkChecks,pkDots])and E.HasDst and not
   E.HasColor2 Then Begin
  E.HasColor2:=True;E.Color2Name:='';
  If Luma((E.DstRGB shr 16)and $FF,(E.DstRGB shr 8)and $FF,E.DstRGB and $FF)>150
    Then Begin E.Color2RGB:=RgbOf(30,30,35);E.Color2Name:='noir';End
  Else Begin E.Color2RGB:=RgbOf(245,245,245);E.Color2Name:='blanc';End;
 End;
 { action }
 E.Put:=Result_ or TryOn;
 { coiffure : valable avec le mot cheveux, ou sans autre vetement cite }
 If(HStyle<>0)and(HairNoun or(NG=0))Then Begin
  E.HairStyle:=HStyle;E.Target:=E.Target or msHair;E.Kind:=gkHair;
 End;
 If Sty<>0 Then E.Style:=Sty;
 E.Material:=Mat;E.Scene:=Scn;E.Poses:=Pz;
 If Yrs<>0 Then Begin
  If Num<=0 Then Num:=10;
  If Num>40 Then Num:=40;
  E.SkinOp:=soAge;E.Years:=Yrs*Num;
 End
 Else If SkOp<>0 Then E.SkinOp:=SkOp
 Else If(Spec<>0)and(HairNoun or(NG=0))Then Begin E.SkinOp:=soSalt;
   E.Target:=E.Target or msHair;E.Kind:=gkHair;End;
 E.Expr:=Expr;
 If((E.Target and msArms)<>0)and PoseWord and not E.HasDst Then E.Pose:=True;
 If Dia and(Jw=0)and(NG=0)Then Jw:=jwNecklace+jwEarrings+jwBracelet;
 E.Jewel:=Jw;E.Diamond:=Dia;E.Apple:=App;
 If App and(Jw=0)Then E.Jewel:=jwWatch;
 If Remove Then E.Action:=eaRemove
 Else If E.Poses<>0 Then E.Action:=eaPose2
 Else If E.SkinOp<>0 Then E.Action:=eaSkin
 Else If BgW and((BOp<>0)or E.HasDst)Then Begin
  If BOp=0 Then BOp:=boSolid;
  E.BgOp:=BOp;E.Action:=eaBg;
 End
 Else If IOp<>0 Then Begin E.ImgOp:=IOp;E.Action:=eaImage;End
 Else If(E.Jewel<>0)and(AddV or Result_ or TryOn)Then E.Action:=eaAdd
 Else If E.Pose Then E.Action:=eaPose
 Else If E.Scene<>0 Then E.Action:=eaScene
 Else If E.Material<>0 Then E.Action:=eaMaterial
 Else If E.HairStyle<>0 Then E.Action:=eaHair
 Else If E.Expr<>0 Then E.Action:=eaFace
 Else If E.Style<>0 Then E.Action:=eaStyle
 Else If AddV Then E.Action:=eaAdd
 Else If Result_ and Demo and(NG>0)and not E.HasDst and(E.Pattern=pkNone)Then
   E.Action:=eaTryOn
 Else If E.HasDst or(E.Pattern<>pkNone)or(Abs(E.LGain-1)>0.01)or(Abs(E.CGain-1)
   >0.01)Then E.Action:=eaRecolor
 Else If TryOn Then E.Action:=eaTryOn;
 { couleur metallique (or, argent, bronze, cuivre) sur un vetement ou le corps :
   rendu metal }
 If(E.Action=eaRecolor)and E.HasDst and(E.Target<>0)and(E.Jewel=0)
   and((E.Target and(msHair or msEyes))=0)Then Begin
  Nm:=LoStr(E.DstName);
  If(Pos('or',Nm)=1)and((Length(Nm)=2)or(Pos(' ',Nm)=3))or(Pos('dore',Nm)>0)
    or(Pos('gold',Nm)>0)or(Pos('argent',Nm)>0)or
    (Pos('silver',Nm)>0)or(Pos('bronze',Nm)>0)or(Pos('cuivre',Nm)>0)
      or(Pos('copper',Nm)>0)or(Pos('platine',Nm)>0)Then Begin
   E.Material:=mtMetal;E.Action:=eaMaterial;
  End;
 End;
 HasChange:=E.Action in[eaRecolor,eaRemove,eaAdd,eaHair,eaStyle,eaFace,
   eaPose,eaMaterial,eaScene,eaPose2,eaSkin,eaImage,eaBg];
 ParseClause:=(E.Action<>eaNone)or(E.Target<>0)or(NG>0)or(E.Jewel<>0);
End;

{ interprete la demande complete ; renvoie la liste des retouches }
Function Interpret(Const Prompt:AnsiString;Var Edits:TEditArray;Var
  Err:AnsiString):Boolean;
Var
 T:TStrArray;
 Bounds:Array of LongInt;
 S0,I,J,K,A,B,N:LongInt;
 E:TEdit;
 HasChange,HasVerb:Boolean;
 Pending:LongWord;
 PendKind:LongInt;
 Segs:Array of LongInt;
 NSeg:LongInt;
 HasG:Boolean;
 Cut:Boolean;
Begin
 Interpret:=False;
 Err:='';
 SetLength(Edits,0);
 LexInit;
 Tokenize(FoldText(Prompt),T);
 If Length(T)=0 Then Begin Err:='la demande est vide';Exit;End;
 { decoupage en clauses : separateurs durs, puis ? et ? devant un nouveau
   vetement }
 SetLength(Segs,0);
 S0:=0;
 For I:=0 to High(T)do Begin
  Cut:=False;
  If(T[I]=',')or(T[I]=';')or(T[I]='.')Then Cut:=True
  Else If LexFind(T[I],lkSplit)>=0 Then Begin
   { ? et ? coupe seulement s'il introduit un autre vetement ou un autre verbe }
   HasG:=False;
   For J:=I+1 to High(T)do Begin
    If(T[J]=',')or(T[J]=';')or(T[J]='.')or(LexFind(T[J],lkSplit)>=0)Then Break;
    If(LexFind(T[J],lkGarment)>=0)or(LexFind(T[J],lkVRemove)>=0)
      or(LexFind(T[J],lkVRecolor)>=0)or
      (LexFind(T[J],lkVResult)>=0)or(LexFind(T[J],lkExpr)>=0)
        or(LexFind(T[J],lkStyle)>=0)or(LexFind(T[J],lkPose2)>=0)
        or(LexFind(T[J],lkYears)>=0)or(LexFind(T[J],lkSkinW)>=0)
        or(LexFind(T[J],lkImgW)>=0)or(LexFind(T[J],lkBgW)>=0)Then HasG:=True;
   End;
   Cut:=HasG;
  End;
  If Cut Then Begin
   SetLength(Segs,Length(Segs)+2);
   Segs[High(Segs)-1]:=S0;Segs[High(Segs)]:=I-1;
   S0:=I+1;
  End;
 End;
 SetLength(Segs,Length(Segs)+2);
 Segs[High(Segs)-1]:=S0;Segs[High(Segs)]:=High(T);
 Pending:=0;PendKind:=gkNone;
 K:=0;
 While K<Length(Segs)do Begin
  A:=Segs[K];B:=Segs[K+1];
  Inc(K,2);
  If A>B Then Continue;
  If not ParseClause(T,A,B,E,HasChange,HasVerb)Then Continue;
  { clause sans changement mais avec un vetement : cible reportee sur la clause
    suivante }
  If(not HasChange)and(E.Jewel<>0)and(E.Action=eaNone)and(not HasVerb)
    and(Length(Edits)>0)and
    (Edits[High(Edits)].Action=eaAdd)and(Edits[High(Edits)].Jewel<>0)Then Begin
   { ? ajoute un collier et un bracelet ? }
   SetLength(Edits,Length(Edits)+1);
   Edits[High(Edits)]:=Edits[High(Edits)-1];
   Edits[High(Edits)].Jewel:=E.Jewel;
   If E.Diamond Then Edits[High(Edits)].Diamond:=True;
   If E.Apple Then Edits[High(Edits)].Apple:=True;
   Continue;
  End;
  If(not HasChange)and(E.Jewel=0)and(E.Target<>0)and(E.Action=eaNone)Then Begin
   { ? enleve le chapeau et les lunettes ? : la retouche precedente s'applique
     aussi }
   If(not HasVerb)and(Length(Edits)>0)and(Edits[High(Edits)].Action
     in[eaRemove,eaAdd])Then Begin
    SetLength(Edits,Length(Edits)+1);
    Edits[High(Edits)]:=Edits[High(Edits)-1];
    Edits[High(Edits)].Target:=E.Target;
    Edits[High(Edits)].Kind:=E.Kind;
    Edits[High(Edits)].Noun:=E.Noun;
    Continue;
   End;
   Pending:=Pending or E.Target;
   If PendKind=gkNone Then PendKind:=E.Kind;
   Continue;
  End;
  { ? ajoute un bonnet bleu et un foulard a rayures ? : le second objet est
    aussi ajoute }
  If(E.Action=eaRecolor)and(not HasVerb)and(E.Target<>0)and(Length(Edits)>0)and
    (Edits[High(Edits)].Action=eaAdd)Then E.Action:=eaAdd;
  If HasChange or(E.Action=eaTryOn)Then Begin
   If Pending<>0 Then Begin
    E.Target:=E.Target or Pending;
    If E.Kind=gkNone Then E.Kind:=PendKind;
    Pending:=0;PendKind:=gkNone;
   End;
   E.Text:='';
   For I:=A to B do E.Text:=E.Text+T[I]+' ';
   SetLength(Edits,Length(Edits)+1);
   Edits[High(Edits)]:=E;
  End;
 End;
 If Length(Edits)=0 Then Begin
  Err:='je n''ai pas compris la demande (exemple : "Change le chandail rouge '+
    'en bleu")';
  Exit;
 End;
 Interpret:=True;
End;

Function ColorHex(RGB:LongWord):AnsiString;
Const
 Hx:AnsiString='0123456789abcdef';
Var
 I:LongInt;
 R:AnsiString;
Begin
 R:='#';
 For I:=5 downto 0 do R:=R+Hx[((RGB shr(I*4))and 15)+1];
 ColorHex:=R;
End;

Function GarmentKindName(K:LongInt):AnsiString;
Begin
 Case K of
  gkTop:GarmentKindName:='haut';
  gkBottom:GarmentKindName:='pantalon';
  gkSkirt:GarmentKindName:='jupe';
  gkDress:GarmentKindName:='robe';
  gkFull:GarmentKindName:='tenue compl'#138'te';
  gkShoes:GarmentKindName:='chaussures';
  gkHat:GarmentKindName:='chapeau';
  gkGlasses:GarmentKindName:='lunettes';
  gkBag:GarmentKindName:='sac';
  gkScarf:GarmentKindName:=#130'charpe';
  gkBelt:GarmentKindName:='ceinture';
  gkAll:GarmentKindName:='v'#136'tements';
  Else GarmentKindName:='?';
 End;
End;

{ noms des poses d'un ensemble (pour -verbose) }
Function PoseNames(P:LongWord):AnsiString;
Const
 Names:Array[1..21]of AnsiString=('bras crois'#130's',
   'main V (peace & love)','doigt point'#130,'flotte','saute',
  'bras '#130'cart'#130's','couch'#130,'t'#136'te droite',
    'regard perdu','s'#130'rieux','triste','aur'#130'ole','somnambule','assis',
  #133' genoux','v'#130'lo','appuy'#130' sur un meuble',
    'escalier','toit de niche','fil de fer','dans un lit');
Var
 I:LongInt;
 R:AnsiString;
Begin
 R:='';
 For I:=1 to 21 do
  If(P and(LongWord(1)shl I))<>0 Then Begin
   If R<>'' Then R:=R+' + ';
   R:=R+Names[I];
  End;
 PoseNames:=R;
End;

{ decrit une retouche pour -verbose }
Function DescribeEdit(Const E:TEdit):AnsiString;
Var
 R:AnsiString;
Begin
 Case E.Action of
  eaRecolor:R:='recolorer';
  eaRemove:R:='retirer';
  eaAdd:R:='ajouter';
  eaHair:R:='coiffure';
  eaFace:R:='expression du visage';
  eaMaterial:R:='mati'#138're '+IStr(E.Material);
  eaScene:R:='sc'#138'ne';
  eaPose2:R:='pose : '+PoseNames(E.Poses);
  eaImage:R:='image enti'#138're '+IStr(E.ImgOp);
  eaBg:R:='arri'#138're-plan '+IStr(E.BgOp)+' '+ColorHex(E.DstRGB);
  eaSkin:R:='peau/'#131'ge/teinte sp'#130'ciale '+IStr(E.SkinOp)+' ('+
    IStr(E.Years)+' ans)';
  eaPose:R:='bras le long du corps';
  eaStyle:R:='style de l''image';
  eaTryOn:R:='essayer';
  Else R:='?';
 End;
 If(E.Target<>0)and(E.Action<>eaPose2)Then R:=R+' '+MaskName(E.Target)
 Else If(E.Jewel=0)and(E.Style=0)and(E.Action<>eaPose2)and(E.Action<>eaSkin)
   and(E.Action<>eaImage)and(E.Action<>eaBg)Then
   R:=R+' (cible '#133' d'#130'terminer)';
 If E.HasSrc Then R:=R+', de '+E.SrcName;
 If E.HasDst Then R:=R+', vers '+E.DstName+' '+ColorHex(E.DstRGB);
 Case E.Pattern of
  pkStripes:R:=R+', motif rayures';
  pkChecks:R:=R+', motif carreaux';
  pkDots:R:=R+', motif pois';
  pkPlain:R:=R+', uni';
 End;
 If E.HasColor2 Then R:=R+' + '+E.Color2Name;
 If E.HairStyle<>0 Then R:=R+', coiffure '+IStr(E.HairStyle);
 If E.Jewel<>0 Then R:=R+', bijoux '+IStr(E.Jewel);
 If E.Style<>0 Then R:=R+', style '+IStr(E.Style);
 If E.Expr<>0 Then R:=R+', sourire';
 If Abs(E.LGain-1)>0.01 Then R:=R+', luminosit'#130' x'+FStr(E.LGain,2);
 If Abs(E.CGain-1)>0.01 Then R:=R+', saturation x'+FStr(E.CGain,2);
 DescribeEdit:=R;
End;

{ ------------------------------------------------------------------ }
{ Retouches : recoloration, motifs, retrait d'accessoires              }
{ ------------------------------------------------------------------ }

Type
 TRecolor=Record
  HasDst:Boolean;
  DstL,DstA,DstB:Single;
  Pattern:LongInt;
  C2L,C2A,C2B:Single;
  LGain,CGain:Single;
  Vertical:Boolean;
  BX0,BY0,BW,BH:Single;
 End;

Procedure RgbIntToLab(RGB:LongWord;Var L,A,B:Single);
Begin
 ColorInit;
 RgbToLab((RGB shr 16)and $FF,(RGB shr 8)and $FF,RGB and $FF,L,A,B);
End;

{ onde triangulaire douce : 0 au centre d'une bande, 1 a la frontiere }
Function BandWave(T,U:Single):Single;
Var
 F,Wv,E:Single;
Begin
 F:=T/(2*U);
 F:=F-Trunc(F);
 If F<0 Then F:=F+1;
 Wv:=Abs(F*2-1);
 E:=0.7/U;
 BandWave:=SmoothStep(0.5-E,0.5+E,Wv);
End;

{ 0 = couleur 1, 1 = couleur 2 }
Function PatternMix(Const P:TRecolor;X,Y:Single):Single;
Var
 U,T,Gx,Gy,Fx,Fy,D,R,Px,Py,Pitch:Single;
 Row:LongInt;
Begin
 U:=FMax(5,FMax(P.BW,P.BH)/13.0);
 X:=X-P.BX0;Y:=Y-P.BY0;
 Case P.Pattern of
  pkStripes:Begin
    If P.Vertical Then T:=X Else T:=Y;
    PatternMix:=BandWave(T,U);
   End;
  pkChecks:Begin
    Px:=BandWave(X,U);Py:=BandWave(Y,U);
    PatternMix:=(Px+Py)*0.5;
   End;
  pkDots:Begin
    Pitch:=2*U;
    Gy:=Y/Pitch;
    Row:=FloorI(Gy);
    Gx:=X/Pitch;
    If Odd(Row)Then Gx:=Gx+0.5;
    Fx:=Gx-FloorI(Gx)-0.5;
    Fy:=Gy-Row-0.5;
    D:=Sqrt(Fx*Fx+Fy*Fy)*Pitch;
    R:=0.27*Pitch;
    PatternMix:=1-SmoothStep(R-0.8,R+0.8,D);
   End;
  Else PatternMix:=0;
 End;
End;

{ recolore les pixels de l'opacite Alpha (0..1) en conservant l'ombrage et la
  texture ;
  renvoie faux si la region est trop petite }
Function RecolorRegion(Pix:PSingle;W,H:LongInt;Alpha:PSingle;Const P:TRecolor)
  :Boolean;
Var
 N:int64;K:LongInt;
 X,Y:LongInt;
 SumL,SumW,Lm:Double;
 L,A,B,Lt,At,Bt,Mx,L2,A2,B2,Mix,F,Wgt,R,G,Bl,Q:Single;
Begin
 RecolorRegion:=False;
 ColorInit;
 N:=Int64(W)*H;
 SumL:=0;SumW:=0;
 For K:=0 to N-1 do If Alpha[K]>0.5 Then Begin
  RgbToLab(Pix[K*3],Pix[K*3+1],Pix[K*3+2],L,A,B);
  SumL:=SumL+L;SumW:=SumW+1;
 End;
 If SumW<30 Then Exit;
 Lm:=SumL/SumW;
 If Lm<3 Then Lm:=3;
 If Lm>97 Then Lm:=97;
 For Y:=0 to H-1 do
  For X:=0 to W-1 do Begin
   K:=Int64(Y)*W+X;
   Wgt:=Alpha[K];
   If Wgt<=0.004 Then Continue;
   RgbToLab(Pix[K*3],Pix[K*3+1],Pix[K*3+2],L,A,B);
   If P.HasDst Then Begin
    Lt:=P.DstL;At:=P.DstA;Bt:=P.DstB;
    If P.Pattern<>pkNone Then Begin
     Mix:=PatternMix(P,X+0.5,Y+0.5);
     Lt:=Lt+(P.C2L-Lt)*Mix;At:=At+(P.C2A-At)*Mix;Bt:=Bt+(P.C2B-Bt)*Mix;
    End;
    { courbe de tons : moyenne de la region -> luminosite cible, 0 et 100 fixes
      }
    If L<=Lm Then L2:=L*Lt/Lm
    Else L2:=Lt+(L-Lm)*(100-Lt)/(100-Lm);
    If L2<0 Then L2:=0 Else If L2>100 Then L2:=100;
    If P.LGain>1 Then L2:=L2+(100-L2)*(1-1/P.LGain)
    Else L2:=L2*P.LGain;
    { la chroma decroit vers le noir et le blanc }
    F:=1;
    If(L2<Lt)and(Lt>1)Then F:=Sqrt(L2/Lt)
    Else If(L2>Lt)and(Lt<99)Then F:=Sqrt((100-L2)/(100-Lt));
    If F<0 Then F:=0 Else If F>1 Then F:=1;
    A2:=At*F*P.CGain;B2:=Bt*F*P.CGain;
   End
    Else Begin
     L2:=L;
     If P.LGain>1 Then L2:=L+(100-L)*(1-1/P.LGain)Else L2:=L*P.LGain;
     A2:=A*P.CGain;B2:=B*P.CGain;
    End;
   LabToRgb(L2,A2,B2,R,G,Bl);
   If Wgt>1 Then Wgt:=1;
   Pix[K*3]:=Pix[K*3]+(R-Pix[K*3])*Wgt;
   Pix[K*3+1]:=Pix[K*3+1]+(G-Pix[K*3+1])*Wgt;
   Pix[K*3+2]:=Pix[K*3+2]+(Bl-Pix[K*3+2])*Wgt;
  End;
 RecolorRegion:=True;
End;

{ durcit un masque flou : supprime les halos de faible opacite }
Procedure SharpenAlpha(M:PSingle;N:Int64);
Var
 K:LongInt;
Begin
 For K:=0 to N-1 do M[K]:=SmoothStep(0.25,0.75,M[K]);
End;

{ couleur moyenne (Lab) d'un ensemble ; faux si trop petit }
Function MeanLabOf(Const S:TScene;Mask:LongWord;Var L,A,B:Single;Var
  Area:Int64):Boolean;
Var
 M:PSingle;
 N:int64;K:LongInt;
 SL,SA,SB:Double;
 Cnt:Int64;
 Ll,Aa,Bb:Single;
Begin
 ColorInit;
 N:=Int64(S.W)*S.H;
 M:=AllocF(N);
 CatMask(S,Mask,M);
 SL:=0;SA:=0;SB:=0;Cnt:=0;
 For K:=0 to N-1 do If M[K]>=0.5 Then Begin
  RgbToLab(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2],Ll,Aa,Bb);
  SL:=SL+Ll;SA:=SA+Aa;SB:=SB+Bb;Inc(Cnt);
 End;
 FreeMem(M);
 Area:=Cnt;
 MeanLabOf:=Cnt>0;
 If Cnt>0 Then Begin L:=SL/Cnt;A:=SA/Cnt;B:=SB/Cnt;End;
End;

{ ecart de couleur (distance euclidienne dans Lab) }
Function DeltaE(L1,A1,B1,L2,A2,B2:Single):Single;
Begin
 DeltaE:=Sqrt((L1-L2)*(L1-L2)+(A1-A2)*(A1-A2)+(B1-B2)*(B1-B2));
End;

{ choisit, parmi les vetements visibles, la categorie dont la couleur moyenne
  est la plus proche de SrcRGB ; 0 si aucune }
Function FindRegionByColor(Const S:TScene;SrcRGB:LongWord;Var Dist:Single)
  :LongWord;
Const
 Cands:Array[0..7]of LongInt=(cTop,cPants,cSkirt,cDress,cShoes,cHat,cBag,
   cScarf);
Var
 I:LongInt;
 L,A,B,Ls,As_,Bs,D,Best:Single;
 Area:Int64;
 BestMask:LongWord;
Begin
 RgbIntToLab(SrcRGB,Ls,As_,Bs);
 Best:=1.0e9;BestMask:=0;
 For I:=0 to 7 do
  If MeanLabOf(S,LongWord(1)shl Cands[I],L,A,B,Area)Then
   If Area>=Int64(S.W)*S.H div 800 Then Begin
    D:=DeltaE(L,A,B,Ls,As_,Bs);
    If D<Best Then Begin Best:=D;BestMask:=LongWord(1)shl Cands[I];End;
   End;
 Dist:=Best;
 FindRegionByColor:=BestMask;
End;

{ remplit les parties marquees par propagation multi-echelle, avec un grain }
Procedure InpaintHoles(Var S:TScene;Hole:PSingle);
Var
 N:int64;K:LongInt;
 Known:PSingle;
 Sigma:Single;
 C:LongInt;
Begin
 N:=Int64(S.W)*S.H;
 Known:=AllocF(N);
 For K:=0 to N-1 do Known[K]:=1-Hole[K];
 PushPullFill(S.Pix,Known,S.W,S.H);
 Sigma:=1.6;
 For K:=0 to N-1 do If Hole[K]>0.05 Then
  For C:=0 to 2 do
   S.Pix[K*3+C]:=S.Pix[K*3+C]+RngGauss*Sigma*Hole[K];
 FreeMem(Known);
End;

{ retire un accessoire : le masque est dilate puis rempli ; renvoie le nombre de
  pixels }
Function RemoveCategory(Var S:TScene;Mask:LongWord):Int64;
Var
 N:int64;K:LongInt;
 M:PSingle;
 B:PByte;
 C,R:LongInt;
 Cnt:Int64;
 Mv:LongInt;
Begin
 N:=Int64(S.W)*S.H;
 M:=AllocF(N);
 CatMask(S,Mask,M);
 B:=PByte(AllocBytes(N));
 Cnt:=0;
 For K:=0 to N-1 do If M[K]>=0.3 Then Begin B[K]:=255;Inc(Cnt);End;
 If Cnt=0 Then Begin FreeMem(M);FreeMem(B);RemoveCategory:=0;Exit;End;
 R:=IMax(2,IMin(S.W,S.H)div 250);
 MorphMask(B,S.W,S.H,R,False);
 For K:=0 to N-1 do M[K]:=B[K]/255.0;
 BoxBlur(M,M,S.W,S.H,1);
 For K:=0 to N-1 do If B[K]<>0 Then If M[K]<0.99 Then M[K]:=0.99;
 InpaintHoles(S,M);
 { les categories retirees deviennent de l'arriere-plan }
 For K:=0 to N-1 do If M[K]>0.5 Then Begin
  For C:=0 to NumCat-1 do If C<>cBg Then
   If(Mask and(LongWord(1)shl C))<>0 Then Begin
    Mv:=S.Cat[C][K];
    S.Cat[C][K]:=0;
    Mv:=Mv+S.Cat[cBg][K];
    If Mv>255 Then Mv:=255;
    S.Cat[cBg][K]:=Mv;
   End;
 End;
 FreeMem(M);FreeMem(B);
 RemoveCategory:=Cnt;
End;

{ remplit les parametres de recoloration d'une retouche ; la boite du motif
  vient de Mask }
Procedure BuildRecolor(Const E:TEdit;Var P:TRecolor;BX0,BY0,BW,
  BH:Single;Vertical:Boolean);
Begin
 FillChar(P,SizeOf(P),0);
 P.LGain:=E.LGain;P.CGain:=E.CGain;
 P.Pattern:=E.Pattern;
 If P.Pattern=pkPlain Then P.Pattern:=pkNone;
 P.HasDst:=E.HasDst;
 If E.HasDst Then RgbIntToLab(E.DstRGB,P.DstL,P.DstA,P.DstB)
 Else If E.Pattern in[pkStripes,pkChecks,pkDots]Then Begin
  { motif sans couleur : ton neutre sombre sur fond clair }
  P.HasDst:=True;
  RgbIntToLab(RgbOf(40,60,140),P.DstL,P.DstA,P.DstB);
 End;
 If E.HasColor2 Then RgbIntToLab(E.Color2RGB,P.C2L,P.C2A,P.C2B)
 Else RgbIntToLab(RgbOf(245,245,245),P.C2L,P.C2A,P.C2B);
 P.BX0:=BX0;P.BY0:=BY0;P.BW:=BW;P.BH:=BH;
 P.Vertical:=Vertical;
End;

Function ApplyHair(Var S:TScene;Style:LongInt;Const E:TEdit;Var Msg:AnsiString)
  :Boolean;forward;
Function ApplyEyes(Var S:TScene;Const E:TEdit;Var Msg:AnsiString)
  :Boolean;forward;

{ applique une retouche de recoloration / de retrait sur la scene }
Function ApplyEdit(Var S:TScene;Const E:TEdit;Var Msg:AnsiString):Boolean;
Var
 Mask:LongWord;
 D:Single;
 N,K:Int64;
 M:PSingle;
 X0,Y0,X1,Y1:LongInt;
 P:TRecolor;
 L,A,B:Single;
 Area:Int64;
 Vert:Boolean;
 Cnt:Int64;
Begin
 ApplyEdit:=False;
 Msg:='';
 Mask:=E.Target;
 If(Mask and msEyes)<>0 Then Begin
  ApplyEdit:=ApplyEyes(S,E,Msg);
  Exit;
 End;
 If Mask=0 Then Begin
  If E.HasSrc Then Begin
   Mask:=FindRegionByColor(S,E.SrcRGB,D);
   If Mask=0 Then Begin Msg:='aucun v'#136'tement de couleur '+
     E.SrcName+' trouv'#130;Exit;End;
   Detail('cible d'#130'duite de la couleur '+E.SrcName+' : '+MaskName(Mask)
     +' ('#130'cart '+FStr(D,0)+')');
  End
   Else Begin
     Msg:='la demande ne pr'#130'cise pas quel v'#136'tement modifier';Exit;End;
 End;
 If E.Action=eaRemove Then Begin
  If(Mask and msHair)<>0 Then Begin
   ApplyEdit:=ApplyHair(S,hsBald,E,Msg);
   If Msg='' Then Info('  cheveux retir'#130's');
   Exit;
  End;
  If(Mask and(msTop or msPants or msSkirt or msDress))<>0 Then Begin
   Msg:='le retrait d''un v'#136'tement principal ('+MaskName(Mask)+
     ') n''est pas pris en charge : indiquez plut'#147't un v'#136'tement '+
     #133' essayer';
   Exit;
  End;
  If(Mask and msShoes)<>0 Then Begin
   Msg:='le retrait des chaussures n''est pas pris en charge';
   Exit;
  End;
  Cnt:=RemoveCategory(S,Mask);
  If Cnt=0 Then Begin Msg:='aucun '+MaskName(Mask)
    +' d'#130'tect'#130' sur la photo';Exit;End;
  Info('  '+MaskName(Mask)+' retir'#130+' ('+IStr(Cnt)+' pixels remplis)');
  ApplyEdit:=True;
  Exit;
 End;
 { recoloration : plusieurs categories visees se traitent ensemble }
 N:=Int64(S.W)*S.H;
 M:=AllocF(N);
 CatMask(S,Mask,M);
 SharpenAlpha(M,N);
 If not CatBBox(S,Mask,X0,Y0,X1,Y1)Then Begin
  FreeMem(M);
  Msg:='aucun '+MaskName(Mask)+' d'#130'tect'#130' sur la photo';
  Exit;
 End;
 If E.HasSrc and(E.Target<>0)Then
  If MeanLabOf(S,Mask,L,A,B,Area)Then Begin
   RgbIntToLab(E.SrcRGB,P.DstL,P.DstA,P.DstB);
   D:=DeltaE(L,A,B,P.DstL,P.DstA,P.DstB);
   If D>48 Then Warn('la couleur '+E.SrcName+
     ' ne correspond pas bien au '+MaskName(Mask)
     +' d'#130'tect'#130' ('#130'cart '+FStr(D,0)+')');
  End;
 Vert:=(Mask and(msPants or msSkirt))<>0;
 BuildRecolor(E,P,X0,Y0,X1-X0+1,Y1-Y0+1,Vert);
 If RecolorRegion(S.Pix,S.W,S.H,M,P)Then Begin
  ApplyEdit:=True;
  Info('  '+MaskName(Mask)+' recolor'#130);
 End
  Else Msg:='la r'#130'gion '+MaskName(Mask)
    +' est trop petite pour '#136'tre retouch'#130'e';
 FreeMem(M);
End;

{ ------------------------------------------------------------------ }
{ Essayage : extraction du vetement et pose sur la personne           }
{ ------------------------------------------------------------------ }

Type
 TGarment=Record
  W,H:LongInt;
  Rgb:PSingle;       { RVB 0..255, W x H }
  Mask:PSingle;      { opacite 0..1, W x H }
  Skin:PSingle;      { peau d'un mannequin (0..1) ; Nil si aucun mannequin }
  PlasticL:Single;   { luminosite moyenne de la peau du mannequin }
  Note:AnsiString;
 End;

Var
 NoMannequin:Boolean=False;

{ defini plus loin (poses) : agrandit l'image en prolongeant le fond }
Procedure GrowEdges(Var S:TScene;L,T,R,B:LongInt);forward;

Procedure GarmentFree(Var G:TGarment);
Begin
 If G.Rgb<>Nil Then FreeMem(G.Rgb);
 If G.Mask<>Nil Then FreeMem(G.Mask);
 If G.Skin<>Nil Then FreeMem(G.Skin);
 G.Rgb:=Nil;G.Mask:=Nil;G.Skin:=Nil;
End;

{ seuil d'Otsu d'un histogramme de 256 classes }
Function OtsuThreshold(Const Hist:Array of Int64):LongInt;
Var
 I,T,Best:LongInt;
 Tot,SumAll,SumB,WB,WF:Double;
 MB,MF,Between,BestV:Double;
Begin
 Tot:=0;SumAll:=0;
 For I:=0 to 255 do Begin Tot:=Tot+Hist[I];SumAll:=SumAll+I*Hist[I];End;
 SumB:=0;WB:=0;BestV:=-1;Best:=20;
 For T:=0 to 255 do Begin
  WB:=WB+Hist[T];
  If WB=0 Then Continue;
  WF:=Tot-WB;
  If WF=0 Then Break;
  SumB:=SumB+T*Hist[T];
  MB:=SumB/WB;MF:=(SumAll-SumB)/WF;
  Between:=WB*WF*(MB-MF)*(MB-MF);
  If Between>BestV Then Begin BestV:=Between;Best:=T;End;
 End;
 OtsuThreshold:=Best;
End;

{ vrai si la couleur ne saute pas entre deux pixels voisins }
Function BgStep(Rgb:PSingle;A,B:LongInt):Boolean;
Var
 D:Single;
Begin
 D:=Abs(Rgb[Int64(A)*3]-Rgb[Int64(B)*3]);
 If Abs(Rgb[Int64(A)*3+1]-Rgb[Int64(B)*3+1])>D Then D:=Abs(Rgb[Int64(A)*3+
   1]-Rgb[Int64(B)*3+1]);
 If Abs(Rgb[Int64(A)*3+2]-Rgb[Int64(B)*3+2])>D Then D:=Abs(Rgb[Int64(A)*3+
   2]-Rgb[Int64(B)*3+2]);
 BgStep:=D<=7;
End;

{ vetement photographie sur un mannequin : la peau du mannequin (plastique
  clair, peu colore) est reperee
  pour etre remplacee par la peau de la personne ; le tissu garde ses couleurs }
Function DetectMannequin(Var G:TGarment):Boolean;
Var
 W,H,X,NC,J:LongInt;
 N,Area,PArea:int64;K:LongInt;
 Seed,Weak,M,Cand,Tmp:PByte;
 Lab:PIntArr;
 Areas:TIntArray;
 HasSeed,Keep:Array of Boolean;
 L,A,B,C,Cx,Wd:Single;
 X0,X1:LongInt;
 Sw:PSingle;
 SumL:Double;
Begin
 DetectMannequin:=False;
 G.Skin:=Nil;
 W:=G.W;H:=G.H;N:=Int64(W)*H;
 X0:=W;X1:=-1;Area:=0;
 For K:=0 to N-1 do If G.Mask[K]>=0.5 Then Begin
  X:=K mod W;
  If X<X0 Then X0:=X;
  If X>X1 Then X1:=X;
  Inc(Area);
 End;
 If Area<500 Then Exit;
 Cx:=(X0+X1+1)/2;Wd:=X1-X0+1;
 Seed:=PByte(AllocBytes(N));Weak:=PByte(AllocBytes(N));
 For K:=0 to N-1 do Begin
  If G.Mask[K]<0.5 Then Continue;
  X:=K mod W;
  If Abs(X+0.5-Cx)>0.33*Wd Then Continue;
  RgbToLab(G.Rgb[K*3],G.Rgb[K*3+1],G.Rgb[K*3+2],L,A,B);
  C:=Sqrt(A*A+B*B);
  If(L>70)and(C<10.5)Then Seed[K]:=255;
  If(L>58)and(C<15)Then Weak[K]:=255;
 End;
 MorphMask(Seed,W,H,1,True);MorphMask(Seed,W,H,1,False);
 Lab:=PIntArr(AllocBytes(N*4));
 NC:=Components(Weak,W,H,Lab,Areas);
 SetLength(HasSeed,NC+1);
 For K:=0 to N-1 do If(Seed[K]<>0)and(Lab[K]>0)Then HasSeed[Lab[K]]:=True;
 M:=PByte(AllocBytes(N));
 For K:=0 to N-1 do If(Lab[K]>0)and HasSeed[Lab[K]]Then M[K]:=255;
 FreeMem(Lab);FreeMem(Seed);FreeMem(Weak);
 MorphMask(M,W,H,2,False);MorphMask(M,W,H,2,True);
 MorphMask(M,W,H,1,True);MorphMask(M,W,H,1,False);
 { la peau ombree ou en bordure : croissance de quelques pixels dans les zones
   claires peu colorees }
 Cand:=PByte(AllocBytes(N));
 For K:=0 to N-1 do Begin
  If G.Mask[K]<0.5 Then Continue;
  RgbToLab(G.Rgb[K*3],G.Rgb[K*3+1],G.Rgb[K*3+2],L,A,B);
  If(L>46)and(Sqrt(A*A+B*B)<20)and(Abs((K mod W)+0.5-Cx)<=0.36*Wd)Then
    Cand[K]:=255;
 End;
 Tmp:=PByte(AllocBytes(N));
 For J:=1 to 10 do Begin
  Move(M^,Tmp^,N);
  MorphMask(Tmp,W,H,1,False);
  For K:=0 to N-1 do If(Tmp[K]<>0)and(Cand[K]<>0)Then M[K]:=255;
 End;
 { fermeture : les zones ombrees ou sous la gaze, entourees de peau, sont
   ajoutees ; les pieces dorees
   (bracelets, collier) restent du tissu car trop colorees }
 Move(M^,Tmp^,N);
 MorphMask(Tmp,W,H,7,False);MorphMask(Tmp,W,H,7,True);
 For K:=0 to N-1 do Begin
  If(Tmp[K]=0)or(M[K]<>0)or(G.Mask[K]<0.5)Then Continue;
  If Abs((K mod W)+0.5-Cx)>0.36*Wd Then Continue;
  RgbToLab(G.Rgb[K*3],G.Rgb[K*3+1],G.Rgb[K*3+2],L,A,B);
  If(L>38)and(Sqrt(A*A+B*B)<17)and(B<16)Then M[K]:=255;
 End;
 FreeMem(Tmp);FreeMem(Cand);
 Lab:=PIntArr(AllocBytes(N*4));
 NC:=Components(M,W,H,Lab,Areas);
 SetLength(Keep,NC+1);
 For J:=1 to NC do Keep[J]:=Areas[J]>=IMax(60,Area div 400);
 PArea:=0;
 For K:=0 to N-1 do If(Lab[K]>0)and Keep[Lab[K]]Then Inc(PArea);
 { trop peu : pas de mannequin ; trop : vetement blanc ou clair, qui n'est pas
   de la peau }
 If(PArea<Area*12 div 1000)or(PArea>Area*45 div 100)Then Begin
  FreeMem(Lab);FreeMem(M);
  Exit;
 End;
 Sw:=AllocF(N);
 SumL:=0;
 For K:=0 to N-1 do If(Lab[K]>0)and Keep[Lab[K]]Then Begin
  Sw[K]:=1;
  SumL:=SumL+Luma(G.Rgb[K*3],G.Rgb[K*3+1],G.Rgb[K*3+2]);
 End;
 FreeMem(Lab);FreeMem(M);
 BoxBlur(Sw,Sw,W,H,1);
 For K:=0 to N-1 do Sw[K]:=Sw[K]*G.Mask[K];
 G.Skin:=Sw;
 G.PlasticL:=FMax(40,SumL/PArea);
 G.Note:=G.Note+', mannequin d'#130'tect'#130' ('+FStr(100.0*PArea/Area,0)+
   ' % du v'#136'tement) : sa peau est remplac'#130'e par celle de la '+
   'personne';
 DetectMannequin:=True;
End;

{ extrait le vetement d'une photo (canal alpha, sinon suppression du fond uni) }
Function GarmentFromImage(Var Img:TImage;Var G:TGarment;Var Err:AnsiString)
  :Boolean;
Var
 W,H,K0,X,Y,I,C,Side,NW,NH:LongInt;
 N:int64;K:LongInt;
 Src:PSingle;
 Hist:Array[0..2]of Array[0..255]of LongInt;
 Bg:Array[0..2]of Single;
 Cnt,Close_:Int64;
 Cum,Half:Int64;
 D:PSingle;
 Dh:Array[0..255]of Int64;
 Thr,Dv:LongInt;
 Fg,Seen:PByte;
 Stack:PIntArr;
 Sp,Q:LongInt;
 UseAlpha:Boolean;
 NLow:Int64;
 Lab:PIntArr;
 Areas:TIntArray;
 NC,Mx,J:LongInt;
 Keep:Array of Boolean;
 X0,Y0,X1,Y1:LongInt;
 Area:Int64;
 M2,Rg2:PSingle;
 Sc:Double;
Begin
 GarmentFromImage:=False;
 Err:='';
 FillChar(G,SizeOf(G),0);
 ColorInit;
 W:=Img.W;H:=Img.H;
 { reduction prealable des tres grandes photos }
 Side:=IMax(W,H);
 If Side>1400 Then Begin
  Sc:=1400/Side;
  NW:=Round(W*Sc);NH:=Round(H*Sc);
 End
  Else Begin NW:=W;NH:=H;End;
 N:=Int64(W)*H;
 Src:=AllocF(N*3);
 For K:=0 to N*3-1 do Src[K]:=Img.Px[K];
 G.Rgb:=AllocF(Int64(NW)*NH*3);
 ResizeF(Src,W,H,G.Rgb,NW,NH,3);
 FreeMem(Src);
 G.Mask:=AllocF(Int64(NW)*NH);
 UseAlpha:=False;
 If Img.Alpha<>Nil Then Begin
  NLow:=0;
  For K:=0 to N-1 do If Img.Alpha[K]<250 Then Inc(NLow);
  If NLow>N div 200 Then UseAlpha:=True;
 End;
 W:=NW;H:=NH;
 N:=Int64(W)*H;
 If UseAlpha Then Begin
  Src:=AllocF(Int64(Img.W)*Img.H);
  For K:=0 to Int64(Img.W)*Img.H-1 do Src[K]:=Img.Alpha[K]/255.0;
  ResizeF(Src,Img.W,Img.H,G.Mask,W,H,1);
  FreeMem(Src);
  G.Note:='canal alpha de l''image utilis'#130;
 End
  Else Begin
   { couleur du fond : mediane des bords }
   FillChar(Hist,SizeOf(Hist),0);
   Cnt:=0;
   For Y:=0 to H-1 do
    For X:=0 to W-1 do
     If(X<3)or(Y<3)or(X>=W-3)or(Y>=H-3)Then Begin
      For C:=0 to 2 do Inc(Hist[C][ClampI(Trunc(G.Rgb[(Int64(Y)*W+X)*3+C]+0.5),
        0,255)]);
      Inc(Cnt);
     End;
   For C:=0 to 2 do Begin
    Cum:=0;Half:=Cnt div 2;
    Bg[C]:=0;
    For I:=0 to 255 do Begin
     Inc(Cum,Hist[C][I]);
     If Cum>Half Then Begin Bg[C]:=I;Break;End;
    End;
   End;
   D:=AllocF(N);
   FillChar(Dh,SizeOf(Dh),0);
   Close_:=0;
   For K:=0 to N-1 do Begin
    D[K]:=FMax(Abs(G.Rgb[K*3]-Bg[0]),FMax(Abs(G.Rgb[K*3+1]-Bg[1]),
      Abs(G.Rgb[K*3+2]-Bg[2])));
    Inc(Dh[ClampI(Trunc(D[K]),0,255)]);
   End;
   For Y:=0 to H-1 do
    For X:=0 to W-1 do
     If(X<3)or(Y<3)or(X>=W-3)or(Y>=H-3)Then
      If D[Int64(Y)*W+X]<=28 Then Inc(Close_);
   If Close_<Cnt*6 div 10 Then Begin
    For K:=0 to N-1 do G.Mask[K]:=1;
    G.Note:='fond non uniforme : toute l''image est utilis'#130'e comme v'#136+
      'tement';
    FreeMem(D);
   End
    Else Begin
     { propagation depuis les bords : on avance tant que la couleur reste proche
       du fond
       ET qu'elle ne saute pas d'un pixel a l'autre (un vetement blanc sur fond
         blanc
       garde ainsi son contour) }
     Thr:=Round(OtsuThreshold(Dh)*0.8);
     If Thr<22 Then Thr:=22;
     If Thr>70 Then Thr:=70;
     Seen:=PByte(AllocBytes(N));
     Fg:=PByte(AllocBytes(N));
     Stack:=PIntArr(AllocBytes(N*4));
     Sp:=0;
     For Y:=0 to H-1 do
      For X:=0 to W-1 do
       If(X=0)or(Y=0)or(X=W-1)or(Y=H-1)Then Begin
        K:=Int64(Y)*W+X;
        If(Seen[K]=0)and(D[K]<Thr)Then Begin Seen[K]:=1;Stack[Sp]:=K;Inc(Sp);
          End;
       End;
     While Sp>0 do Begin
      Dec(Sp);
      Q:=Stack[Sp];
      X:=Q mod W;Y:=Q div W;
      If(X>0)and(Seen[Q-1]=0)and(D[Q-1]<Thr)and BgStep(G.Rgb,Q,Q-1)Then
        Begin Seen[Q-1]:=1;Stack[Sp]:=Q-1;Inc(Sp);End;
      If(X<W-1)and(Seen[Q+1]=0)and(D[Q+1]<Thr)and BgStep(G.Rgb,Q,Q+1)Then
        Begin Seen[Q+1]:=1;Stack[Sp]:=Q+1;Inc(Sp);End;
      If(Y>0)and(Seen[Q-W]=0)and(D[Q-W]<Thr)and BgStep(G.Rgb,Q,Q-W)Then
        Begin Seen[Q-W]:=1;Stack[Sp]:=Q-W;Inc(Sp);End;
      If(Y<H-1)and(Seen[Q+W]=0)and(D[Q+W]<Thr)and BgStep(G.Rgb,Q,Q+W)Then
        Begin Seen[Q+W]:=1;Stack[Sp]:=Q+W;Inc(Sp);End;
     End;
     FreeMem(Stack);FreeMem(D);
     For K:=0 to N-1 do If Seen[K]=0 Then Fg[K]:=255;
     FreeMem(Seen);
     { ouverture legere puis suppression des petits ilots }
     MorphMask(Fg,W,H,1,True);
     Lab:=PIntArr(AllocBytes(N*4));
     NC:=Components(Fg,W,H,Lab,Areas);
     Mx:=0;
     For J:=1 to NC do If Areas[J]>Mx Then Mx:=Areas[J];
     SetLength(Keep,NC+1);
     For J:=1 to NC do Keep[J]:=Areas[J]*100>=Int64(Mx)*8;
     For K:=0 to N-1 do
      If(Lab[K]>0)and Keep[Lab[K]]Then Fg[K]:=255 Else Fg[K]:=0;
     FreeMem(Lab);
     MorphMask(Fg,W,H,1,False);
     For K:=0 to N-1 do G.Mask[K]:=Fg[K]/255.0;
     BlurPlane(G.Mask,W,H,1.0);
     For K:=0 to N-1 do G.Mask[K]:=SmoothStep(0.3,0.8,G.Mask[K]);
     FreeMem(Fg);
     G.Note:='fond supprim'#130' (seuil '+IStr(Thr)+')';
    End;
  End;
 G.W:=W;G.H:=H;
 { rognage sur la boite du vetement }
 X0:=W;Y0:=H;X1:=-1;Y1:=-1;Area:=0;
 For Y:=0 to H-1 do
  For X:=0 to W-1 do If G.Mask[Int64(Y)*W+X]>=0.5 Then Begin
   If X<X0 Then X0:=X;
   If X>X1 Then X1:=X;
   If Y<Y0 Then Y0:=Y;
   If Y>Y1 Then Y1:=Y;
   Inc(Area);
  End;
 If(X1<X0)or(Area<N div 40)Then Begin
  Err:='impossible de trouver le v'#136'tement dans l''image (fond trop '+
    'complexe ?)';
  GarmentFree(G);
  Exit;
 End;
 NW:=X1-X0+1;NH:=Y1-Y0+1;
 M2:=AllocF(Int64(NW)*NH);Rg2:=AllocF(Int64(NW)*NH*3);
 For Y:=0 to NH-1 do Begin
  Move(G.Mask[Int64(Y+Y0)*W+X0],M2[Int64(Y)*NW],NW*4);
  Move(G.Rgb[(Int64(Y+Y0)*W+X0)*3],Rg2[Int64(Y)*NW*3],NW*12);
 End;
 FreeMem(G.Mask);FreeMem(G.Rgb);
 G.Mask:=M2;G.Rgb:=Rg2;G.W:=NW;G.H:=NH;
 { decontamination des bords : les couleurs proches du contour (melangees au
   fond)
   sont remplacees par celles de l'interieur du tissu }
 Fg:=PByte(AllocBytes(Int64(NW)*NH));
 For K:=0 to Int64(NW)*NH-1 do If G.Mask[K]>=0.5 Then Fg[K]:=255;
 MorphMask(Fg,NW,NH,IMax(1,IMin(NW,NH)div 250),True);
 M2:=AllocF(Int64(NW)*NH);
 For K:=0 to Int64(NW)*NH-1 do If Fg[K]<>0 Then M2[K]:=1;
 PushPullFill(G.Rgb,M2,NW,NH);
 FreeMem(M2);FreeMem(Fg);
 GarmentFromImage:=True;
 If not NoMannequin Then DetectMannequin(G);
End;

{ extremites gauche/droite (premier/dernier pixel > 0,5) de chaque rangee ; -1
  si vide }
Procedure RowExtents(M:PSingle;W,H:LongInt;L,R:PSingle);
Var
 X,Y,A,B:LongInt;
Begin
 For Y:=0 to H-1 do Begin
  A:=-1;B:=-1;
  For X:=0 to W-1 do If M[Int64(Y)*W+X]>=0.5 Then Begin
   If A<0 Then A:=X;
   B:=X;
  End;
  If A<0 Then Begin L[Y]:=-1;R[Y]:=-1;End
  Else Begin L[Y]:=A;R[Y]:=B+1;End;
 End;
End;

{ comble les rangees vides par la plus proche et lisse sur une fenetre de rayon
  Rad }
Procedure FillSmoothExtents(L,R:PSingle;H,Rad:LongInt);
Var
 Y,K,Last:LongInt;
 TmpL,TmpR:PSingle;
 SL,SR_:Double;
 Cnt:LongInt;
Begin
 Last:=-1;
 For Y:=0 to H-1 do Begin
  If L[Y]>=0 Then Last:=Y
  Else If Last>=0 Then Begin L[Y]:=L[Last];R[Y]:=R[Last];End;
 End;
 Last:=-1;
 For Y:=H-1 downto 0 do Begin
  If(L[Y]>=0)and(Y<H)Then Last:=Y
  Else If(Last>=0)and(L[Y]<0)Then Begin L[Y]:=L[Last];R[Y]:=R[Last];End;
 End;
 TmpL:=AllocF(H);TmpR:=AllocF(H);
 For Y:=0 to H-1 do Begin
  SL:=0;SR_:=0;Cnt:=0;
  For K:=Y-Rad to Y+Rad do If(K>=0)and(K<H)Then Begin SL:=SL+L[K];SR_:=SR_+
    R[K];Inc(Cnt);End;
  TmpL[Y]:=SL/Cnt;TmpR[Y]:=SR_/Cnt;
 End;
 Move(TmpL^,L^,H*4);Move(TmpR^,R^,H*4);
 FreeMem(TmpL);FreeMem(TmpR);
End;

{ comble les trous entre les manches et le corps d'un vetement photographie a
  plat
  (a partir de la rangee FromRow), le tissu manquant etant prolonge par
    propagation }
Procedure CloseRowGaps(Var G:TGarment;FromRow:LongInt);
Var
 X,Y,A,B:LongInt;
 Known,Fill:PSingle;
 N:int64;K:LongInt;
 Any:Boolean;
Begin
 N:=Int64(G.W)*G.H;
 Known:=AllocF(N);Fill:=AllocF(N);
 Any:=False;
 For K:=0 to N-1 do If G.Mask[K]>=0.5 Then Known[K]:=1;
 For Y:=FromRow to G.H-1 do Begin
  A:=-1;B:=-1;
  For X:=0 to G.W-1 do If Known[Int64(Y)*G.W+X]>0 Then Begin
   If A<0 Then A:=X;
   B:=X;
  End;
  If A>=0 Then
   For X:=A to B do If Known[Int64(Y)*G.W+X]=0 Then Begin Fill[Int64(Y)*G.W+
     X]:=1;Any:=True;End;
 End;
 If Any Then Begin
  PushPullFill(G.Rgb,Known,G.W,G.H);
  For K:=0 to N-1 do If Fill[K]>0 Then G.Mask[K]:=1;
 End;
 FreeMem(Known);FreeMem(Fill);
End;

{ categories remplacees / protegees selon le genre de vetement }
Procedure KindSets(Kind:LongInt;Var Repl,Alt,Prot:LongWord);
Const
 Always=msFace or msHair or msHat or msGlasses;
Begin
 Alt:=0;
 Case Kind of
  gkTop:Begin Repl:=msTop;Alt:=msDress;Prot:=Always or msScarf or msBag
    or msBelt or msPants or msSkirt or msShoes or msLegs;End;
  gkBottom,gkSkirt:Begin Repl:=msPants or msSkirt;Prot:=Always or msTop or msBag
    or msBelt or msShoes or msScarf;End;
  gkDress:Begin Repl:=msDress or msTop or msSkirt or msPants;Prot:=Always
    or msShoes or msBag or msScarf;End;
  gkFull:Begin Repl:=msDress or msTop or msSkirt or msPants or msBelt;
    Prot:=Always or msShoes or msBag or msScarf;End;
  gkShoes:Begin Repl:=msShoes;Prot:=Always or msTop or msPants or msSkirt
    or msDress or msBag;End;
  gkHat:Begin Repl:=msHat;Prot:=msFace or msGlasses;End;
  gkGlasses:Begin Repl:=msGlasses;Prot:=msHair or msHat;End;
  gkBag:Begin Repl:=msBag;Prot:=Always;End;
  gkScarf:Begin Repl:=msScarf;Prot:=Always;End;
  gkBelt:Begin Repl:=msBelt;Prot:=Always;End;
  Else Begin Repl:=msTop;Prot:=Always;End;
 End;
End;

Function KindCategory(Kind:LongInt):LongInt;
Begin
 Case Kind of
  gkTop:KindCategory:=cTop;
  gkBottom:KindCategory:=cPants;
  gkSkirt:KindCategory:=cSkirt;
  gkDress,gkFull:KindCategory:=cDress;
  gkShoes:KindCategory:=cShoes;
  gkHat:KindCategory:=cHat;
  gkGlasses:KindCategory:=cGlasses;
  gkBag:KindCategory:=cBag;
  gkScarf:KindCategory:=cScarf;
  gkBelt:KindCategory:=cBelt;
  Else KindCategory:=cTop;
 End;
End;

Var
 GAnkleY:Single=-1;
 GHemY:Single=-1;

{ rangee la plus basse ou l'ensemble de categories apparait entre les colonnes
  X0 et X1 ; -1 si absent }
Function CatBottomIn(Const S:TScene;Mask:LongWord;X0,X1:LongInt):LongInt;
Var
 X,Y,C,T:LongInt;
 P:Int64;
Begin
 CatBottomIn:=-1;
 If X0<0 Then X0:=0;
 If X1>=S.W Then X1:=S.W-1;
 For Y:=S.H-1 downto 0 do
  For X:=X0 to X1 do Begin
   P:=Int64(Y)*S.W+X;
   T:=0;
   For C:=0 to NumCat-1 do If(Mask and(LongWord(1)shl C))<>0 Then Inc(T,
     S.Cat[C][P]);
   If T>=128 Then Begin CatBottomIn:=Y;Exit;End;
  End;
End;

{ boite cible deduite du visage lorsque la personne ne porte pas ce genre de
  vetement }
Function LandmarkBox(Const S:TScene;Kind:LongInt;Var Bx0,By0,Bx1,By1:Single)
  :Boolean;
Var
 Fx0,Fy0,Fx1,Fy1,Lx0,Ly0,Lx1,Ly1,Tx0,Ty0,Tx1,Ty1,Hx0,Hy0,Hx1,Hy1:LongInt;
 Fw,Fh,Cx,U:Single;
Begin
 LandmarkBox:=False;
 If not CatBBox(S,msFace,Fx0,Fy0,Fx1,Fy1)Then Exit;
 Fw:=Fx1-Fx0+1;Fh:=Fy1-Fy0+1;
 Cx:=(Fx0+Fx1+1)/2;
 Case Kind of
  gkTop,gkDress,gkFull:Begin
    Bx0:=Cx-1.4*Fw;Bx1:=Cx+1.4*Fw;By0:=Fy1+0.25*Fh;
    Case Kind of
     gkTop:By1:=By0+2.5*Fh;
     gkDress:By1:=By0+5.0*Fh;
     Else By1:=By0+6.2*Fh;
    End;
    LandmarkBox:=True;
   End;
  gkHat:Begin Bx0:=Fx0-0.2*Fw;Bx1:=Fx1+0.2*Fw;By1:=Fy0+0.25*Fh;
    By0:=By1-0.9*Fh;LandmarkBox:=True;End;
  gkGlasses:Begin Bx0:=Fx0-0.05*Fw;Bx1:=Fx1+0.05*Fw;By0:=Fy0+0.30*Fh;
    By1:=Fy0+0.57*Fh;LandmarkBox:=True;End;
  gkScarf:Begin Bx0:=Cx-0.62*Fw;Bx1:=Cx+0.62*Fw;By0:=Fy1-0.12*Fh;By1:=By0+
    0.9*Fh;LandmarkBox:=True;End;
  gkBelt:
   If CatBBox(S,msPants or msSkirt,Lx0,Ly0,Lx1,Ly1)and CatBBox(S,msTop
     or msDress,Tx0,Ty0,Tx1,Ty1)Then Begin
    Bx0:=Lx0;Bx1:=Lx1;
    By1:=Ty1-0.02*(Ty1-Ty0);By0:=By1-0.07*(Ly1-Ty0);
    LandmarkBox:=True;
   End;
  gkBottom,gkSkirt,gkShoes:Begin
    If CatBBox(S,msFace or msHair or msHat,Hx0,Hy0,Hx1,Hy1)Then U:=Fy1+
      1-Hy0 Else U:=Fh*1.3;
    If CatBBox(S,msLegs or msShoes,Lx0,Ly0,Lx1,Ly1)Then Begin
     If Kind=gkShoes Then Begin
      Bx0:=Lx0-0.12*U;Bx1:=Lx1+0.12*U;By1:=Ly1+0.1*U;By0:=By1-0.55*U;
      LandmarkBox:=True;
     End
      Else If CatBBox(S,msTop or msDress,Tx0,Ty0,Tx1,Ty1)Then Begin
       Bx0:=Lx0-0.01*U;Bx1:=Lx1+0.01*U;
       If GHemY>0 Then By0:=GHemY-0.12*U
       Else Begin
        Ly0:=CatBottomIn(S,msTop or msDress,Lx0,Lx1);
        If Ly0>=0 Then By0:=Ly0-0.15*U Else By0:=Ty1-0.15*U;
       End;
       If Kind=gkBottom Then Begin
        If GAnkleY>0 Then By1:=GAnkleY Else By1:=Ly1+1;
       End
        Else By1:=By0+2.0*U;
       LandmarkBox:=True;
      End;
    End;
   End;
 End;
End;

{ couleur de peau moyenne (RVB) : jambes, sinon bras, sinon visage }
Function SkinColor(Const S:TScene;ArmsFirst:Boolean;Var R,G,B:Single):Boolean;
Const
 SetsLow:Array[0..2]of LongWord=(msLegs,msArms,msFace);
 SetsTop:Array[0..2]of LongWord=(msArms,msFace,msLegs);
Var
 I:LongInt;
 Sets:Array[0..2]of LongWord;
 N,Cnt:int64;K:LongInt;
 M:PSingle;
 Sr,Sg,Sb:Double;
Begin
 SkinColor:=False;
 For I:=0 to 2 do If ArmsFirst Then Sets[I]:=SetsTop[I]Else Sets[I]:=SetsLow[I];
 N:=Int64(S.W)*S.H;
 M:=AllocF(N);
 For I:=0 to 2 do Begin
  CatMask(S,Sets[I],M);
  Sr:=0;Sg:=0;Sb:=0;Cnt:=0;
  For K:=0 to N-1 do If M[K]>=0.8 Then Begin
   Sr:=Sr+S.Pix[K*3];Sg:=Sg+S.Pix[K*3+1];Sb:=Sb+S.Pix[K*3+2];Inc(Cnt);
  End;
  If Cnt>=N div 3000 Then Begin
   R:=Sr/Cnt;G:=Sg/Cnt;B:=Sb/Cnt;
   SkinColor:=True;
   Break;
  End;
 End;
 FreeMem(M);
End;

{ mesures robustes du visage : si le cou ou la poitrine sont classes dans le
  visage, la boite
  englobante est trop grande. La largeur du visage est celle de son premier
    maximum (joues) ;
  le menton est la premiere ligne dont la largeur tombe sous 62 % de ce maximum,
    ou qui
  s'elargit de nouveau (epaules) apres avoir diminue }
Procedure FaceMetrics(Const S:TScene;Var Fx0,Fy0,Fx1,Fy1:LongInt);
Var
 X,Y,A,B,Wd,MaxW,YMax,Xa,Xb,Y1,Chin,MinW:LongInt;
 Function RowW(R:LongInt;Var Ra,Rb:LongInt):LongInt;
 Var
  Xx:LongInt;
 Begin
  Ra:=-1;Rb:=-1;
  For Xx:=Fx0 to Fx1 do If S.Cat[cFace][Int64(R)*S.W+Xx]>=128 Then Begin
   If Ra<0 Then Ra:=Xx;
   Rb:=Xx;
  End;
  If Ra<0 Then RowW:=0 Else RowW:=Rb-Ra+1;
 End;
Begin
 MaxW:=0;YMax:=Fy0;Xa:=Fx0;Xb:=Fx1;Y1:=Fy1;
 For Y:=Fy0 to Fy1 do Begin
  Wd:=RowW(Y,A,B);
  If Wd>MaxW Then Begin MaxW:=Wd;YMax:=Y;Xa:=A;Xb:=B;End
  Else If(MaxW>=8)and(Wd<0.80*MaxW)Then Begin Y1:=Y;Break;End;
 End;
 If MaxW<8 Then Exit;
 Chin:=Fy1;
 MinW:=MaxW;
 For Y:=Y1 to Fy1 do Begin
  Wd:=RowW(Y,A,B);
  If Wd<MinW Then MinW:=Wd;
  If(Wd<0.62*MaxW)or((MinW<0.90*MaxW)and(Wd>1.12*MinW+2))Then Begin
   Chin:=Y;
   Break;
  End;
 End;
 Fx0:=Xa;Fx1:=Xb;Fy1:=Chin;
 If Fy1<YMax Then Fy1:=YMax;
End;

{ ligne des epaules du mannequin : sous le menton, ou a la hauteur des epaules
  de l'ancien haut
  quand celui-ci est plus haut }
Function ShoulderY(Const S:TScene;Fy0,Fy1:LongInt):Single;
Var
 Tx0,Ty0,Tx1,Ty1:LongInt;
 Fh,V:Single;
Begin
 Fh:=Fy1-Fy0+1;
 V:=Fy1+1+0.25*Fh;
 If CatBBox(S,msTop or msDress,Tx0,Ty0,Tx1,Ty1)Then
  If(Ty0>Fy0+0.5*Fh)and(Ty0+0.12*Fh<V)Then V:=Ty0+0.12*Fh;
 ShoulderY:=V;
End;

{ marges a ajouter (gauche, droite, bas) pour voir la tenue sur mannequin en
  entier, jusqu'aux pieds ; 0 si inutile }
Procedure MannequinNeed(Const S:TScene;Const G:TGarment;Kind:LongInt;Var NL,
  NR,NB:LongInt);
Var
 GL,GRr:PSingle;
 Fx0,Fy0,Fx1,Fy1,Y,Ysh:LongInt;
 Wg,Sc,Ty0,Bottom,Cx,Gcx,Le,Re:Single;
Begin
 NL:=0;NR:=0;NB:=0;
 If(G.Skin=Nil)or not(Kind in[gkDress,gkFull])Then Exit;
 If not CatBBox(S,msFace,Fx0,Fy0,Fx1,Fy1)Then Exit;
 FaceMetrics(S,Fx0,Fy0,Fx1,Fy1);
 GL:=AllocF(G.H);GRr:=AllocF(G.H);
 RowExtents(G.Mask,G.W,G.H,GL,GRr);
 FillSmoothExtents(GL,GRr,G.H,IMax(1,G.H div 50));
 Wg:=0;
 For Y:=(G.H*5)div 100 to(G.H*13)div 100 do If GRr[Y]-GL[Y]>Wg Then
   Wg:=GRr[Y]-GL[Y];
 Ysh:=0;
 For Y:=0 to G.H-1 do If GRr[Y]-GL[Y]>=0.75*Wg Then Begin Ysh:=Y;Break;End;
 Gcx:=(GL[Ysh]+GRr[Ysh])/2;
 FreeMem(GL);FreeMem(GRr);
 If Wg<8 Then Exit;
 Sc:=2.55*(Fx1-Fx0+1)/Wg;
 Cx:=(Fx0+Fx1+1)/2;
 Ty0:=ShoulderY(S,Fy0,Fy1)-Sc*Ysh;
 Bottom:=Ty0+Sc*G.H;
 If Bottom>S.H Then NB:=Trunc(Bottom-S.H)+2;
 Le:=Cx+(0-Gcx)*Sc;
 Re:=Cx+(G.W-Gcx)*Sc;
 If Le<0 Then NL:=Trunc(-Le)+Trunc(0.02*G.W*Sc)+2;
 If Re>S.W Then NR:=Trunc(Re-S.W)+Trunc(0.02*G.W*Sc)+2;
End;

{ pose le vetement sur la personne }
Function TryOnGarment(Var S:TScene;Var G:TGarment;Kind,Quality:LongInt;Var
  Msg:AnsiString):Boolean;
Var
 Repl,Alt,Prot:LongWord;
 W,H,X,Y,C,R0,GR:LongInt;
 N:int64;K:LongInt;
 Ro,Prot_,Cov,Left,Lrw,Lr:PSingle;
 GRgb,GA:PSingle;
 X0,Y0,X1,Y1:LongInt;
 Have:Boolean;
 Tx0,Ty0,Tx1,Ty1,Cx,Gcx,Sx,Sy,SyFit,Lam:Single;
 UsedLandmarks:Boolean;
 GL,GRr,SL,SR_:PSingle;
 Gx0,Gx1:LongInt;
 Lt,Rt,Ls,Rs,Lf,Rf,Gy,U,Gxx,Sc:Single;
 Tmp:Array[0..3]of Single;
 Yb,Ye:LongInt;
 UniformScale:Boolean;
 Area:Int64;
 MeanL:Double;
 CntL:Int64;
 Rad:LongInt;
 F,Cvg,Lef:Double;
 Bw,Bh:Single;
 MaxCat:LongInt;
 Mv:LongInt;
 AnchorBottom:Boolean;
 ArmMask:PSingle;
 M_:Single;
 RoArea:Double;
 SA,SB:PSingle;
 SkR,SkG,SkB,Sv:Single;
 Sleeveless:Boolean;
 RowL,RowR:PSingle;
 LeftSkin:PSingle;
 Sum1,Sum2:Double;
 N1,N2:LongInt;
 GS,GSh,SkE,Fb,Bl:PSingle;
 Gw,Gain,Sig,Shd:Single;
 LgSum,LsSum,Sd:Double;
 Cg,Cs:Int64;
 Mc:LongInt;
 SkinBase,MannequinFit:Boolean;
 YshRow,NeckX0,NeckX1,NeckY1:Single;
 RemoveOld,NeckHas:Boolean;
 Rm,Kn2,Fl2:PSingle;
 Mk2:PByte;
 Fx0,Fy0,Fx1,Fy1,Ysh,Cnt1,Cnt2:LongInt;
 Wg:Single;

 Procedure FillSkin(Wt:PSingle);
 Var
  Kk:LongInt;
  Cc,CntOld,RadS:LongInt;
  Nn:Int64;
  V,Sh2:Single;
  MeanOld:Double;
  Lb,Wb:PSingle;
 Begin
  { seules les variations lentes de lumiere de l'ancien vetement (forme du bras,
    ombres) servent
    de relief ; ses plis et ses bords ne sont pas repris }
  Nn:=Int64(S.W)*S.H;
  Lb:=AllocF(Nn);Wb:=AllocF(Nn);
  MeanOld:=0;CntOld:=0;
  For Kk:=0 to Nn-1 do If Wt[Kk]>0.02 Then Begin
   Lb[Kk]:=Wt[Kk]*Luma(S.Pix[Kk*3],S.Pix[Kk*3+1],S.Pix[Kk*3+2]);Wb[Kk]:=Wt[Kk];
   If Wt[Kk]>0.5 Then Begin MeanOld:=MeanOld+Luma(S.Pix[Kk*3],S.Pix[Kk*3+1],
     S.Pix[Kk*3+2]);Inc(CntOld);End;
  End;
  If CntOld>0 Then MeanOld:=MeanOld/CntOld;
  If MeanOld<20 Then MeanOld:=20;
  RadS:=IMax(3,S.W div 40);
  BoxBlur(Lb,Lb,S.W,S.H,RadS);BoxBlur(Lb,Lb,S.W,S.H,RadS);
  BoxBlur(Wb,Wb,S.W,S.H,RadS);BoxBlur(Wb,Wb,S.W,S.H,RadS);
  For Kk:=0 to Nn-1 do If Wt[Kk]>0.02 Then Begin
   If Wb[Kk]>0.001 Then Sh2:=Lb[Kk]/Wb[Kk]/MeanOld Else Sh2:=1;
   Sh2:=Clamp(Exp(0.8*Ln(Clamp(Sh2,0.5,1.35))),0.72,1.18);
   { bords de la zone plus sombres : volume arrondi d'un membre }
   Sh2:=Sh2*(0.74+0.30*SmoothStep(0.30,0.95,Wb[Kk]));
   For Cc:=0 to 2 do Begin
    V:=SkR;
    If Cc=1 Then V:=SkG Else If Cc=2 Then V:=SkB;
    S.Pix[Kk*3+Cc]:=S.Pix[Kk*3+Cc]*(1-Wt[Kk])+(V*Sh2+RngGauss*1.6)*Wt[Kk];
   End;
  End;
  FreeMem(Lb);FreeMem(Wb);
 End;

Begin
 TryOnGarment:=False;
 Msg:='';
 W:=S.W;H:=S.H;N:=Int64(W)*H;
 KindSets(Kind,Repl,Alt,Prot);
 Ro:=AllocF(N);
 CatMask(S,Repl,Ro);
 Have:=CatBBox(S,Repl,X0,Y0,X1,Y1);
 If Have Then Begin
  Area:=CatArea(S,Repl);
  If Area<N div 600 Then Have:=False;
 End;
 If(not Have)and(Alt<>0)Then Begin
  CatMask(S,Alt,Ro);
  Have:=CatBBox(S,Alt,X0,Y0,X1,Y1);
  If Have Then Repl:=Alt;
 End;
 UsedLandmarks:=False;
 If Have Then Begin
  Tx0:=X0;Tx1:=X1+1;Ty0:=Y0;Ty1:=Y1+1;
  { robe / tenue : la longueur depend du genre, pas de l'ancien vetement }
  If(Kind=gkDress)or(Kind=gkFull)Then Begin
   Ye:=Y1;
   If CatBBox(S,msPants or msSkirt or msDress or msLegs,X0,R0,X1,Ye)Then Begin
    If Kind=gkDress Then Ty1:=Ty0+0.62*(Ye-Ty0+1)Else Ty1:=Ye+1;
   End;
   If Ty1<Y1+1 Then Ty1:=Y1+1;
  End;
 End
  Else Begin
   FillChar(Ro^,N*4,0);
   If not LandmarkBox(S,Kind,Tx0,Ty0,Tx1,Ty1)Then Begin
    Msg:='impossible de situer o'#151' poser ce v'#136'tement sur la personne '+
      '(aucun visage ni '+
         'v'#136'tement de ce type d'#130'tect'#130')';
    FreeMem(Ro);
    Exit;
   End;
   UsedLandmarks:=True;
   Detail('position estim'#130'e '#133' partir du visage : '+IStr(Trunc(Tx0))
     +','+IStr(Trunc(Ty0))+' - '+IStr(Trunc(Tx1))+','+IStr(Trunc(Ty1)));
  End;
 If Tx0<0 Then Tx0:=0;If Ty0<0 Then Ty0:=0;
 If Tx1>W Then Tx1:=W;If Ty1>H Then Ty1:=H;
 Bw:=Tx1-Tx0;Bh:=Ty1-Ty0;
 If(Bw<8)or(Bh<8)Then Begin Msg:='zone cible trop petite';FreeMem(Ro);Exit;End;
 { echelle : largeur ajustee, hauteur bornee pour limiter la deformation }
 Sx:=Bw/G.W;
 SyFit:=Bh/G.H;
 UniformScale:=Kind in[gkShoes,gkHat,gkGlasses,gkBag,gkScarf,gkBelt];
 If UniformScale Then Sy:=Sx
 Else If(Kind=gkTop)and Have and not UsedLandmarks Then Sy:=Clamp(SyFit,
   0.6*Sx,3.0*Sx)
 Else If UsedLandmarks and(Kind in[gkBottom,gkSkirt])Then Sy:=Clamp(SyFit,
   0.5*Sx,3.4*Sx)
 Else Sy:=Clamp(SyFit,0.8*Sx,1.25*Sx);
 AnchorBottom:=Kind in[gkShoes,gkHat];
 If AnchorBottom Then Ty0:=Ty1-Sy*G.H
 Else If UniformScale and(Kind<>gkScarf)Then Ty0:=(Ty0+Ty1)/2-Sy*G.H/2;
 Cx:=(Tx0+Tx1)/2;
 Gcx:=G.W/2;
 Lam:=0;
 If(Kind=gkTop)and Have and not UsedLandmarks Then Lam:=0.8;
 If Kind=gkTop Then CloseRowGaps(G,G.H div 4);
 { etendues du vetement et de l'ancien vetement, rangee par rangee }
 GL:=AllocF(G.H);GRr:=AllocF(G.H);
 RowExtents(G.Mask,G.W,G.H,GL,GRr);
 FillSmoothExtents(GL,GRr,G.H,IMax(1,G.H div 50));
 Sleeveless:=False;
 If Kind=gkTop Then Begin
  { vetement sans manches : largeur maximale en haut comparable a celle du corps
    }
  Sum1:=0;N1:=0;Sum2:=0;N2:=0;
  For Y:=0 to G.H-1 do Begin
   If(Y>=G.H*55 div 100)and(Y<=G.H*90 div 100)Then Begin Sum1:=Sum1+
     (GRr[Y]-GL[Y]);Inc(N1);End;
   If(Y>=G.H*12 div 100)and(Y<=G.H*50 div 100)Then If GRr[Y]-GL[Y]>Sum2
     Then Sum2:=GRr[Y]-GL[Y];
  End;
  If(N1>0)and(Sum1>0)Then Sleeveless:=Sum2/(Sum1/N1)<1.2;
  If Sleeveless Then Begin
   Lam:=0.1;
   Detail('v'#136'tement sans manches d'#130'tect'#130);
  End;
 End;

 { vetement photographie sur un mannequin : l'echelle vient de la tete de la
   personne
   (largeur des epaules d'environ 2,55 fois la largeur du visage), le corps
     n'est pas ecrase
   pour tenir dans l'ancienne zone ; ce qui depasse du cadre est simplement
     coupe }
 MannequinFit:=False;YshRow:=0;RemoveOld:=False;NeckHas:=False;
 If(G.Skin<>Nil)and(Kind in[gkTop,gkDress,gkFull])and CatBBox(S,msFace,Fx0,
   Fy0,Fx1,Fy1)Then Begin
  FaceMetrics(S,Fx0,Fy0,Fx1,Fy1);
  Wg:=0;
  For Y:=(G.H*5)div 100 to(G.H*13)div 100 do If GRr[Y]-GL[Y]>Wg Then
    Wg:=GRr[Y]-GL[Y];
  Ysh:=0;
  For Y:=0 to G.H-1 do If GRr[Y]-GL[Y]>=0.75*Wg Then Begin Ysh:=Y;Break;End;
  If Wg>=8 Then Begin
   Sc:=2.55*(Fx1-Fx0+1)/Wg;
   Sx:=Sc;Sy:=Sc;
   Gcx:=(GL[Ysh]+GRr[Ysh])/2;
   Cx:=(Fx0+Fx1+1)/2;
   Ty0:=ShoulderY(S,Fy0,Fy1)-Sc*Ysh;
   Lam:=0;
   MannequinFit:=True;
   YshRow:=Ysh;
   { cou de la personne : conserve s'il est visible (le mannequin garde sinon le
     sien) }
   NeckX0:=Cx-0.60*(Fx1-Fx0+1);NeckX1:=Cx+0.60*(Fx1-Fx0+1);NeckY1:=Fy1+1+
     0.30*(Fy1-Fy0+1);
   Cnt1:=0;Cnt2:=0;
   For Y:=Fy1+1 to Trunc(NeckY1)do
    For X:=Trunc(NeckX0)to Trunc(NeckX1)do
     If(X>=0)and(X<W)and(Y>=0)and(Y<H)Then Begin
      Inc(Cnt2);
      If(S.Cat[cArms][Int64(Y)*W+X]+S.Cat[cSkin][Int64(Y)*W+X]+
        S.Cat[cFace][Int64(Y)*W+X])>=128 Then Inc(Cnt1);
     End;
   NeckHas:=(Cnt2>0)and(Cnt1*4>=Cnt2);
   If not NeckHas Then YshRow:=0;
   RemoveOld:=Kind in[gkDress,gkFull];
   Detail('mannequin : '#130'chelle d'#130'duite de la t'#136'te (x'+FStr(Sc,2)
     +'), le corps garde ses proportions');
  End;
 End;
 SL:=AllocF(H);SR_:=AllocF(H);
 For Y:=0 to H-1 do Begin SL[Y]:=-1;SR_[Y]:=-1;End;
 If Lam>0 Then Begin
  Cov:=AllocF(N);
  For K:=0 to N-1 do If Ro[K]>=0.5 Then Cov[K]:=1;
  RowExtents(Cov,W,H,SL,SR_);
  FreeMem(Cov);
  FillSmoothExtents(SL,SR_,H,IMax(2,H div 120));
 End;
 GRgb:=AllocF(N*3);GA:=AllocF(N);
 GS:=AllocF(N);GSh:=AllocF(N);
 RowL:=AllocF(H);RowR:=AllocF(H);
 For Y:=0 to H-1 do Begin RowL[Y]:=-1000;RowR[Y]:=-1000;End;
 RoArea:=0;
 For K:=0 to N-1 do If Ro[K]>=0.5 Then RoArea:=RoArea+1;
 Yb:=Trunc(Ty0);If Yb<0 Then Yb:=0;
 Ye:=Trunc(Ty0+Sy*G.H)+1;If Ye>H-1 Then Ye:=H-1;
 For Y:=Yb to Ye do Begin
  Gy:=(Y+0.5-Ty0)/Sy;
  If(Gy<0)or(Gy>=G.H)Then Continue;
  GR:=Trunc(Gy);
  If GR>G.H-1 Then GR:=G.H-1;
  Ls:=Cx+(GL[GR]-Gcx)*Sx;
  Rs:=Cx+(GRr[GR]-Gcx)*Sx;
  Lf:=Ls;Rf:=Rs;
  If(Lam>0)and(SL[Y]>=0)Then Begin
   Lf:=(1-Lam)*Ls+Lam*SL[Y];
   Rf:=(1-Lam)*Rs+Lam*SR_[Y];
  End;
  If Rf-Lf<2 Then Continue;
  RowL[Y]:=Lf;RowR[Y]:=Rf;
  For X:=Trunc(Lf)-1 to Trunc(Rf)+1 do Begin
   If(X<0)or(X>=W)Then Continue;
   U:=(X+0.5-Lf)/(Rf-Lf);
   If(U<-0.02)or(U>1.02)Then Continue;
   Gxx:=GL[GR]+U*(GRr[GR]-GL[GR]);
   SampleBilinear(G.Mask,G.W,G.H,1,Gxx,Gy,@Tmp[0]);
   If Tmp[0]<=0.003 Then Continue;
   K:=Int64(Y)*W+X;
   GA[K]:=Tmp[0];
   SampleBilinear(G.Rgb,G.W,G.H,3,Gxx,Gy,@GRgb[K*3]);
   If G.Skin<>Nil Then SampleBilinear(G.Skin,G.W,G.H,1,Gxx,Gy,@GS[K]);
   GSh[K]:=Luma(GRgb[K*3],GRgb[K*3+1],GRgb[K*3+2]);
  End;
 End;
 FreeMem(GL);FreeMem(GRr);
 { ombrage : variations lentes de la luminosite de l'ancien vetement }
 If(Quality>=2)and Have and not UsedLandmarks Then Begin
  Lrw:=AllocF(N);Lr:=AllocF(N);
  MeanL:=0;CntL:=0;
  For K:=0 to N-1 do Begin
   Lrw[K]:=Ro[K];
   Lr[K]:=Ro[K]*Luma(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2]);
   If Ro[K]>=0.5 Then Begin MeanL:=MeanL+Luma(S.Pix[K*3],S.Pix[K*3+1],
     S.Pix[K*3+2]);Inc(CntL);End;
  End;
  If CntL>0 Then Begin
   MeanL:=MeanL/CntL;
   If MeanL<20 Then MeanL:=20;
   Rad:=IMax(3,Trunc(Bw/14));
   BoxBlur(Lrw,Lrw,W,H,Rad);BoxBlur(Lrw,Lrw,W,H,Rad);
   BoxBlur(Lr,Lr,W,H,Rad);BoxBlur(Lr,Lr,W,H,Rad);
   For K:=0 to N-1 do Begin
    If Lrw[K]>0.05 Then Begin
     F:=(Lr[K]/Lrw[K])/MeanL;
     If F<0.7 Then F:=0.7 Else If F>1.3 Then F:=1.3;
     F:=Exp(0.65*Ln(F));
    End
     Else F:=1;
    If GA[K]>0 Then Begin
     GRgb[K*3]:=GRgb[K*3]*F;GRgb[K*3+1]:=GRgb[K*3+1]*F;GRgb[K*3+2]:=GRgb[K*3+
       2]*F;
    End;
   End;
  End;
  FreeMem(Lrw);FreeMem(Lr);
 End;

 { mannequin : peau de la personne avec l'ombrage du plastique }
 SkE:=Nil;
 If G.Skin<>Nil Then Begin
  If not SkinColor(S,True,SkR,SkG,SkB)Then Begin SkR:=214;SkG:=168;SkB:=140;End;
  SkE:=AllocF(N);
  CatMask(S,msSkin,SkE);
  For K:=0 to N-1 do If(GA[K]>0)and(GS[K]>0.01)Then Begin
   Shd:=Clamp(GSh[K]/G.PlasticL,0.55,1.25);
   Shd:=Exp(1.15*Ln(Shd));
   Gw:=GS[K];
   GRgb[K*3]:=GRgb[K*3]*(1-Gw)+(SkR*Shd+RngGauss*1.5)*Gw;
   GRgb[K*3+1]:=GRgb[K*3+1]*(1-Gw)+(SkG*Shd+RngGauss*1.5)*Gw;
   GRgb[K*3+2]:=GRgb[K*3+2]*(1-Gw)+(SkB*Shd+RngGauss*1.5)*Gw;
  End;
  Detail('peau du mannequin remplac'#130'e par celle de la personne');
 End;
 { exposition et grain du tissu accordes a la photo }
 LgSum:=0;LsSum:=0;Cg:=0;Cs:=0;
 For K:=0 to N-1 do Begin
  If(GA[K]>0.5)and(GS[K]<0.3)Then Begin LgSum:=LgSum+Luma(GRgb[K*3],GRgb[K*3+
    1],GRgb[K*3+2]);Inc(Cg);End;
  If S.Cat[cBg][K]<128 Then Begin LsSum:=LsSum+Luma(S.Pix[K*3],S.Pix[K*3+1],
    S.Pix[K*3+2]);Inc(Cs);End;
 End;
 Gain:=1;Sig:=0;
 If(Cg>0)and(Cs>0)and(LgSum>0)and(LsSum>0)Then
   Gain:=Clamp(Exp(0.35*Ln((LsSum/Cs)/(LgSum/Cg))),0.82,1.12);
 If Cs>0 Then Begin
  { bruit de la photo : ecart moyen a la version floue, sur les zones peu
    contrastees }
  Bl:=AllocF(N);
  For K:=0 to N-1 do Bl[K]:=Luma(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2]);
  Fb:=AllocF(N);
  Move(Bl^,Fb^,N*4);
  BoxBlur(Bl,Bl,W,H,2);
  Sd:=0;Cg:=0;
  For K:=0 to N-1 do If S.Cat[cBg][K]<128 Then Begin
   Shd:=Abs(Fb[K]-Bl[K]);
   If Shd<10 Then Begin Sd:=Sd+Shd;Inc(Cg);End;
  End;
  If Cg>0 Then Sig:=Clamp(1.25*Sd/Cg,0,2.5);
  FreeMem(Bl);FreeMem(Fb);
 End;
 For K:=0 to N-1 do If(GA[K]>0)and(GS[K]<0.3)Then Begin
  Gw:=RngGauss*Sig*0.7;
  GRgb[K*3]:=GRgb[K*3]*Gain+Gw;GRgb[K*3+1]:=GRgb[K*3+1]*Gain+Gw;GRgb[K*3+
    2]:=GRgb[K*3+2]*Gain+Gw;
 End;
 If Abs(Gain-1)>0.02 Then
   Detail('exposition du v'#136'tement ajust'#130'e (x'+FStr(Gain,2)+
   '), grain '+FStr(Sig,1));
 { objets au premier plan qui ne doivent pas etre recouverts }
 Prot_:=AllocF(N);
 CatMask(S,Prot,Prot_);
 If Kind=gkTop Then Begin
  ArmMask:=AllocF(N);
  CatMask(S,msArms,ArmMask);
  If Have Then Begin
   Cov:=AllocF(N);
   For K:=0 to N-1 do If Ro[K]>=0.5 Then Cov[K]:=1;
   SA:=AllocF(H);SB:=AllocF(H);
   RowExtents(Cov,W,H,SA,SB);
   FreeMem(Cov);
   For Y:=0 to H-1 do If SA[Y]>=0 Then Begin
    M_:=(SB[Y]-SA[Y])*0.08;
    For X:=Trunc(SA[Y]+M_) to Trunc(SB[Y]-M_) do
     If(X>=0)and(X<W)Then Begin
      K:=Int64(Y)*W+X;
      If ArmMask[K]>Prot_[K]Then Prot_[K]:=ArmMask[K];
     End;
   End;
   FreeMem(SA);FreeMem(SB);
  End;
  FreeMem(ArmMask);
 End;
 { composition }
 { mannequin : tout ce qui est sous la tete de la personne (corps, bras, ancien
   vetement) est supprime
   et remplace par le fond ; le corps du mannequin le remplace }
 If MannequinFit and RemoveOld Then Begin
  Rm:=AllocF(N);Kn2:=AllocF(N);Fl2:=AllocF(N*3);
  For K:=0 to N-1 do Begin
   Rm[K]:=(1-S.Cat[cBg][K]/255.0)*(1-SmoothStep(0.15,0.85,Prot_[K]));
   If NeckHas Then Begin
    Y:=K div W;X:=K mod W;
    If(X>=NeckX0)and(X<=NeckX1)and(Y<=NeckY1)and((S.Cat[cArms][K]+
      S.Cat[cSkin][K]+S.Cat[cFace][K])>=128)Then Rm[K]:=0;
   End;
  End;
  { le fond connu exclut le bord de l'ancien corps (pixels melanges) }
  Mk2:=PByte(AllocBytes(N));
  For K:=0 to N-1 do If Rm[K]>0.02 Then Mk2[K]:=255;
  MorphMask(Mk2,W,H,4,False);
  For K:=0 to N-1 do If(S.Cat[cBg][K]>=250)and(Prot_[K]<0.05)and(Mk2[K]=0)
    Then Kn2[K]:=1;
  FreeMem(Mk2);
  Move(S.Pix^,Fl2^,N*12);
  PushPullFill(Fl2,Kn2,W,H);
  For K:=0 to N-1 do If Rm[K]>0.02 Then Begin
   For C:=0 to 2 do S.Pix[K*3+C]:=S.Pix[K*3+C]*(1-Rm[K])+Fl2[K*3+C]*Rm[K];
   If Rm[K]>0.5 Then Begin
    For C:=0 to NumCat-1 do S.Cat[C][K]:=0;
    S.Cat[cBg][K]:=255;
   End;
  End;
  FreeMem(Rm);FreeMem(Kn2);FreeMem(Fl2);
  FillChar(Ro^,N*4,0);
  Detail(
    'ancien corps supprim'#130' sous la t'#136'te : le corps du mannequin '+
    'le remplace');
 End;
 { peau encore visible apres la suppression : seule celle-la est conservee ; le
   cou du mannequin n'est retire que la }
 If SkE<>Nil Then Begin
  CatMask(S,msSkin,SkE);
  If MannequinFit and(YshRow>0)Then
   For K:=0 to N-1 do If(GA[K]>0)and(GS[K]>0.3)and(((K div W)+0.5-Ty0)
     /Sy<YshRow)and(SkE[K]>=0.5)Then GA[K]:=0;
 End;
 { robe, tenue, bas : l'ancien vetement est d'abord remplace par de la peau (le
   tissu leger ou fendu la laisse voir) }
 SkinBase:=False;
 If Have and not(MannequinFit and RemoveOld)and(Kind in[gkDress,gkFull,
   gkBottom,gkSkirt])and SkinColor(S,False,SkR,SkG,SkB)Then Begin
  Fb:=AllocF(N);
  For K:=0 to N-1 do If Ro[K]>0.02 Then Fb[K]:=Ro[K]*(1-SmoothStep(0.15,
    0.85,Prot_[K]));
  FillSkin(Fb);
  FreeMem(Fb);
  SkinBase:=True;
  Detail('ancien v'#136'tement remplac'#130' par de la peau avant la pose');
 End;
 Cov:=AllocF(N);
 Cvg:=0;
 For K:=0 to N-1 do Begin
  Cov[K]:=GA[K]*(1-SmoothStep(0.15,0.85,Prot_[K]));
  { la vraie peau de la personne est conservee la ou le mannequin montrait la
    sienne }
  If(SkE<>Nil)and(GS[K]>0.02)Then Cov[K]:=Cov[K]*(1-GS[K]*SmoothStep(0.3,0.9,
    SkE[K]));
  Cvg:=Cvg+Cov[K];
 End;
 Left:=AllocF(N);
 Lef:=0;
 If Have Then Begin
  For K:=0 to N-1 do If Ro[K]>=0.5 Then Begin
   Left[K]:=1-Cov[K];
   If Left[K]<0.3 Then Left[K]:=0;
   Lef:=Lef+Left[K];
  End;
 End;
 For K:=0 to N-1 do If Cov[K]>0 Then
  For C:=0 to 2 do
   S.Pix[K*3+C]:=S.Pix[K*3+C]*(1-Cov[K])+GRgb[K*3+C]*Cov[K];
 { ombre de contact du tissu sur la peau voisine }
 If G.Skin<>Nil Then Begin
  Fb:=AllocF(N);
  For K:=0 to N-1 do Fb[K]:=Cov[K]*(1-GS[K]);
  BoxBlur(Fb,Fb,W,H,IMax(2,Trunc(Bw*0.02)));
  For K:=0 to N-1 do If(GS[K]>0.2)and(Cov[K]>0.3)Then Begin
   Shd:=Clamp(Fb[K]*1.7-0.15,0,0.6)*0.30*GS[K];
   S.Pix[K*3]:=S.Pix[K*3]*(1-Shd);S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-Shd);S.Pix[K*3+
     2]:=S.Pix[K*3+2]*(1-Shd);
  End;
  FreeMem(Fb);
 End;
 If Lef>0 Then Begin
  BoxBlur(Left,Left,W,H,1);
  For K:=0 to N-1 do If Left[K]>0.02 Then Begin
   Left[K]:=Left[K]*2;If Left[K]>1 Then Left[K]:=1;
   If Cov[K]>0.9 Then Left[K]:=0;
  End;
  If SkinBase Then
    Detail('zone d'#130'couverte d'#130'j'#133' remplie avec la peau')
   Else Begin
    If Sleeveless and SkinColor(S,True,SkR,SkG,SkB)Then Begin
     { bras nus : ce qui depasse sur les cotes du vetement sans manches }
     LeftSkin:=AllocF(N);
     For K:=0 to N-1 do If Left[K]>0.02 Then Begin
      Y:=K div W;X:=K mod W;
      If(RowL[Y]>-999)and((X<RowL[Y]-1)or(X>RowR[Y]+1))Then Begin
        LeftSkin[K]:=Left[K];Left[K]:=0;End;
     End;
     FillSkin(LeftSkin);
     FreeMem(LeftSkin);
     Detail('bras d'#130'couverts remplis avec la couleur de la peau');
    End;
    InpaintHoles(S,Left);
   End;
 End;
 { mise a jour des categories }
 MaxCat:=KindCategory(Kind);
 For K:=0 to N-1 do Begin
  If Cov[K]>0.004 Then Begin
   Mv:=Trunc(Cov[K]*255+0.5);
   Mc:=MaxCat;
   If GS[K]>0.5 Then Mc:=cSkin;
   For C:=0 to NumCat-1 do
    S.Cat[C][K]:=Trunc(S.Cat[C][K]*(1-Cov[K])+0.5);
   Mv:=Mv+S.Cat[Mc][K];
   If Mv>255 Then Mv:=255;
   S.Cat[Mc][K]:=Mv;
  End;
  If Left[K]>0.5 Then
   For C:=0 to NumCat-1 do If SkinBase and((Repl and(LongWord(1)shl C))<>0)
     Then Begin
    Mv:=S.Cat[C][K]+S.Cat[cSkin][K];
    If Mv>255 Then Mv:=255;
    S.Cat[cSkin][K]:=Mv;
    S.Cat[C][K]:=0;
   End
   Else If(Repl and(LongWord(1)shl C))<>0 Then Begin
    Mv:=S.Cat[C][K]+S.Cat[cBg][K];
    If Mv>255 Then Mv:=255;
    S.Cat[cBg][K]:=Mv;
    S.Cat[C][K]:=0;
   End;
 End;
 Msg:='v'#136'tement pos'#130;
 If RoArea>0 Then Msg:=Msg+' ('+FStr(100.0*FMin(1,Cvg/RoArea),0)
   +' % de l''ancienne zone couverts)';
 If Lef>N*0.0005 Then Msg:=Msg+', '+IStr(Trunc(Lef))
   +' pixels de l''ancien v'#136'tement remplis par interpolation';
 FreeMem(Ro);FreeMem(Prot_);FreeMem(Cov);FreeMem(Left);FreeMem(GRgb);
   FreeMem(GA);
 FreeMem(GS);FreeMem(GSh);If SkE<>Nil Then FreeMem(SkE);
 FreeMem(SL);FreeMem(SR_);FreeMem(RowL);FreeMem(RowR);
 TryOnGarment:=True;
End;

{ ------------------------------------------------------------------ }
{ Accessoires generes (foulard, chapeau, lunettes, ceinture) :        }
{ dessines par le programme, puis poses comme un vetement            }
{ ------------------------------------------------------------------ }

Function CoverD(D:Single):Single;
Begin
 If D<=-0.5 Then CoverD:=1
 Else If D>=0.5 Then CoverD:=0
 Else CoverD:=0.5-D;
End;

{ distance signee d'un rectangle arrondi centre en (Cx,Cy) }
Function RoundRectD(X,Y,Cx,Cy,Hw,Hh,R:Single):Single;
Var
 Qx,Qy,Ox,Oy:Single;
Begin
 Qx:=Abs(X-Cx)-Hw+R;Qy:=Abs(Y-Cy)-Hh+R;
 If Qx>0 Then Ox:=Qx Else Ox:=0;
 If Qy>0 Then Oy:=Qy Else Oy:=0;
 If Qx>Qy Then RoundRectD:=Sqrt(Ox*Ox+Oy*Oy)+FMin(0,Qx)-R+0*Qy
 Else RoundRectD:=Sqrt(Ox*Ox+Oy*Oy)+FMin(0,Qy)-R;
End;

Function EllipseD(X,Y,Cx,Cy,Rx,Ry:Single):Single;
Var
 Nx,Ny,L:Single;
Begin
 Nx:=(X-Cx)/Rx;Ny:=(Y-Cy)/Ry;
 L:=Sqrt(Nx*Nx+Ny*Ny);
 EllipseD:=(L-1)*FMin(Rx,Ry);
End;

Procedure MixRgb(A,B:LongWord;T:Single;Var R,G,Bl:Single);
Begin
 R:=((A shr 16)and $FF)*(1-T)+((B shr 16)and $FF)*T;
 G:=((A shr 8)and $FF)*(1-T)+((B shr 8)and $FF)*T;
 Bl:=(A and $FF)*(1-T)+(B and $FF)*T;
End;

{ couleur du tissu au point (X,Y) : couleur de base, motif eventuel, grain }
Procedure FabricColor(Const E:TEdit;Base:LongWord;X,Y,W,H:Single;Var R,G,
  B:Single);
Var
 P:TRecolor;
 T:Single;
 C1,C2:LongWord;
Begin
 C1:=Base;
 If E.HasDst Then C1:=E.DstRGB;
 C2:=RgbOf(245,245,245);
 If E.HasColor2 Then C2:=E.Color2RGB;
 If(E.Pattern in[pkStripes,pkChecks,pkDots])Then Begin
  FillChar(P,SizeOf(P),0);
  P.Pattern:=E.Pattern;P.BX0:=0;P.BY0:=0;P.BW:=W;P.BH:=H;
  T:=PatternMix(P,X,Y);
  MixRgb(C1,C2,T,R,G,B);
 End
  Else MixRgb(C1,C1,0,R,G,B);
End;

Procedure AccAlloc(Var G:TGarment;W,H:LongInt);
Begin
 FillChar(G,SizeOf(G),0);
 G.W:=W;G.H:=H;
 G.Rgb:=AllocF(Int64(W)*H*3);
 G.Mask:=AllocF(Int64(W)*H);
End;

Procedure AccPut(Var G:TGarment;X,Y:LongInt;Cov,R,Gc,B,Shade:Single);
Var
 K:Int64;
Begin
 K:=Int64(Y)*G.W+X;
 If Cov>G.Mask[K]Then Begin
  G.Mask[K]:=Cov;
  G.Rgb[K*3]:=Clamp(R*Shade+RngGauss*1.5,0,255);
  G.Rgb[K*3+1]:=Clamp(Gc*Shade+RngGauss*1.5,0,255);
  G.Rgb[K*3+2]:=Clamp(B*Shade+RngGauss*1.5,0,255);
 End;
End;

{ foulard : bande autour du cou, noeud et pan qui pend }
Procedure MakeScarf(Var G:TGarment;Const E:TEdit);
Var
 X,Y:LongInt;
 U,YT,Th,YB,Dd,Cb,Ct,Hw,Xc,Dk,Cov,R,Gc,B,Sh,T:Single;
Begin
 AccAlloc(G,480,300);
 For Y:=0 to 299 do
  For X:=0 to 479 do Begin
   U:=(X-240)/230.0;
   Cov:=0;Sh:=1;
   If Abs(U)<=1 Then Begin
    YT:=70-55*U*U;Th:=85-25*U*U;YB:=YT+Th;
    Dd:=FMax(YT-Y,Y-YB);
    Cb:=CoverD(Dd);
    If Cb>0 Then Begin
     T:=(Y-YT)/Th;
     Cov:=Cb;
     Sh:=0.72+0.34*Sin(Pi*Clamp(T,0,1))*(0.88+0.12*(1-U*U))+0.03*Sin(X*0.9);
    End;
   End;
   { pan }
   Xc:=300+12*Sin((Y-90)/40.0);
   Hw:=38-0.06*(Y-90);
   Dd:=FMax(Abs(X-Xc)-Hw,FMax(Y-(290+(X-300)*0.15),80-Y));
   Ct:=CoverD(Dd);
   If Ct>Cov Then Begin
    Cov:=Ct;
    Dk:=Clamp((Y-100)/22.0,0,1);
    Sh:=(0.62+0.3*Dk)*(0.9+0.1*Cos((X-Xc)/Hw*1.3))+0.03*Sin(X*0.9);
   End;
   { noeud }
   Dd:=EllipseD(X,Y,300,100,42,38);
   Ct:=CoverD(Dd);
   If Ct>0 Then Begin
    Cov:=FMax(Cov,Ct);
    Sh:=0.95+0.12*Cos((Y-100)/38.0*1.4)-0.1*Sin((X-300)/42.0);
   End;
   If Cov>0 Then Begin
    FabricColor(E,RgbOf(170,35,50),X,Y,480,300,R,Gc,B);
    AccPut(G,X,Y,Cov,R,Gc,B,Sh);
   End;
  End;
End;

{ forme : 0 = chapeau a bord, 1 = bonnet, 2 = casquette }
Procedure MakeHat(Var G:TGarment;Const E:TEdit;Shape:LongInt;Straw:Boolean);
Var
 X,Y:LongInt;
 Cov,Dd,R,Gc,B,Sh,Wv,Dist:Single;
 Base:LongWord;
Begin
 AccAlloc(G,480,300);
 If Straw Then Base:=RgbOf(222,190,110)Else Base:=RgbOf(70,70,82);
 For Y:=0 to 299 do
  For X:=0 to 479 do Begin
   Cov:=0;Sh:=1;
   Case Shape of
    1:Begin
      { bonnet : dome tricote et revers cotele }
      Dd:=FMax(EllipseD(X,Y,240,150,200,135),Y-235);
      Cov:=CoverD(Dd);
      Sh:=0.7+0.4*(1-Clamp(Sqrt(Sqr((X-210)/200.0)+Sqr((Y-110)/140.0)),0,1.3))
        +0.05*Sin(X*0.5+Y*0.2);
      Dd:=RoundRectD(X,Y,240,245,215,40,26);
      If CoverD(Dd)>Cov Then Begin
       Cov:=CoverD(Dd);
       Sh:=0.82+0.18*Sin(X*0.75)+0.1*Sin(Pi*Clamp((Y-205)/80.0,0,1));
      End;
     End;
    2:Begin
      { casquette : dome et visiere }
      Dd:=FMax(EllipseD(X,Y,200,150,165,125),Y-228);
      Cov:=CoverD(Dd);
      Sh:=0.68+0.45*(1-Clamp(Sqrt(Sqr((X-170)/170.0)+Sqr((Y-110)/130.0)),0,1.3)
        );
      Dd:=EllipseD(X,Y,335,238,140,30);
      If CoverD(Dd)>Cov Then Begin
       Cov:=CoverD(Dd);
       Sh:=0.55+0.3*Sin(Pi*Clamp((Y-208)/60.0,0,1));
      End;
     End;
    Else Begin
      { chapeau a large bord }
      Dd:=EllipseD(X,Y,240,222,228,48);
      Cov:=CoverD(Dd);
      Sh:=0.72+0.3*Clamp(1-Abs(Y-222)/48.0,0,1)+0.08*Sin(X*0.12);
      Dd:=FMax(FMin(EllipseD(X,Y,240,110,118,92),RoundRectD(X,Y,240,160,118,
        50,10)),Y-215);
      If CoverD(Dd)>Cov Then Begin
       Cov:=CoverD(Dd);
       Sh:=0.78+0.32*(1-Clamp(Abs(X-240)/118.0,0,1))*(1-Clamp((Y-60)/160.0,0,1)
         *0.4);
       If(Y>165)and(Y<200)Then Sh:=Sh*0.62;
      End;
     End;
   End;
   If Cov>0 Then Begin
    FabricColor(E,Base,X,Y,480,300,R,Gc,B);
    If Straw Then Begin
     { tressage de la paille }
     Wv:=0.5+0.5*Sin(X*0.55+Sin(Y*0.35)*1.8);
     Dist:=0.5+0.5*Sin(Y*0.9+Sin(X*0.2)*1.2);
     Sh:=Sh*(0.84+0.16*(Wv*0.6+Dist*0.4));
    End;
    AccPut(G,X,Y,Cov,R,Gc,B,Sh);
   End;
  End;
End;

Procedure MakeGlasses(Var G:TGarment;Const E:TEdit;Sun:Boolean);
Var
 X,Y:LongInt;
 Cov,Dl,Dr,Df,Br,Fr,Lens:Single;
 R,Gc,B:Single;
 Base:LongWord;
Begin
 AccAlloc(G,480,170);
 Base:=RgbOf(25,25,28);
 For Y:=0 to 169 do
  For X:=0 to 479 do Begin
   Dl:=RoundRectD(X,Y,125,85,95,60,44);
   Dr:=RoundRectD(X,Y,355,85,95,60,44);
   Df:=FMin(Dl,Dr);
   Fr:=CoverD(Abs(Df+5.5)-5.5);
   Br:=0;
   If Abs(X-240)<=40 Then Br:=CoverD(Abs(Y-(52+28*Sqr((X-240)/40.0)))-4.5);
   Cov:=FMax(Fr,Br);
   If(X<24)and(Abs(Y-60)<6)Then Cov:=FMax(Cov,0.9);
   If(X>455)and(Abs(Y-60)<6)Then Cov:=FMax(Cov,0.9);
   If Cov>0 Then Begin
    FabricColor(E,Base,X,Y,480,170,R,Gc,B);
    AccPut(G,X,Y,Cov,R,Gc,B,0.85+0.25*Clamp(1-Y/170.0,0,1));
   End;
   { verres }
   If(Df<-5.5)and(Cov<0.5)Then Begin
    If Sun Then Lens:=0.88 Else Lens:=0.10;
    If Sun Then Begin R:=22;Gc:=24;B:=32;End Else Begin R:=200;Gc:=220;
      B:=240;End;
    AccPut(G,X,Y,Lens,R,Gc,B,0.9+0.2*Clamp(1-Y/170.0,0,1));
   End;
  End;
End;

Procedure MakeBelt(Var G:TGarment;Const E:TEdit);
Var
 X,Y:LongInt;
 Cov,Dd,Df,R,Gc,B,Sh:Single;
Begin
 AccAlloc(G,560,90);
 For Y:=0 to 89 do
  For X:=0 to 559 do Begin
   Dd:=RoundRectD(X,Y,280,45,280,27,6);
   Cov:=CoverD(Dd);
   Sh:=0.8+0.3*Sin(Pi*Clamp((Y-18)/54.0,0,1));
   If Cov>0 Then Begin
    FabricColor(E,RgbOf(70,45,30),X,Y,560,90,R,Gc,B);
    If(Abs(Y-24)<1.2)or(Abs(Y-66)<1.2)Then Sh:=Sh*0.75;
    AccPut(G,X,Y,Cov,R,Gc,B,Sh);
   End;
   Df:=RoundRectD(X,Y,280,45,42,38,6);
   If CoverD(Abs(Df+5)-5)>0 Then AccPut(G,X,Y,CoverD(Abs(Df+5)-5),212,175,55,
     0.8+0.35*Sin(Pi*Clamp((Y-8)/76.0,0,1)));
  End;
End;

{ pantalon : deux jambes, ceinture, braguette, plis }
Procedure MakePants(Var G:TGarment;Const E:TEdit);
Var
 X,Y:LongInt;
 Xl,Xr,Dl,Dr,Cov,Xm,Hw,Cc,Ux,R,Gc,B,Sh,Gp,Wb:Single;
 Side:LongInt;
Begin
 AccAlloc(G,480,720);
 For Y:=0 to 719 do
  For X:=0 to 479 do Begin
   Cov:=0;Sh:=1;
   Xm:=X;
   Side:=0;
   If X>240 Then Begin Xm:=479-X;Side:=1;End;
   Xl:=0+16*(Y/720.0);
   If Y<260 Then Gp:=0 Else Gp:=8+14*Sqrt((Y-260)/460.0);
   Xr:=240-Gp;
   Dl:=FMax(Xl-Xm,FMax(Xm-Xr,Y-717.5));
   Cov:=CoverD(Dl);
   If Y<38 Then Begin
    Wb:=CoverD(FMax(0-X,FMax(X-479,Y-37.5)));
    If Wb>Cov Then Cov:=Wb;
   End;
   If Cov>0 Then Begin
    Cc:=(Xl+Xr)/2;Hw:=(Xr-Xl)/2;
    If Hw<1 Then Hw:=1;
    Ux:=Clamp((Xm-Cc)/Hw,-1,1);
    Sh:=0.7+0.32*Sqrt(1-Ux*Ux)+0.04*Sin(Y*0.11+Xm*0.05)*Clamp((Y-300)/200.0,0,
      1);
    If Y<38 Then Sh:=Sh*0.88;
    If(Abs(X-240)<1.3)and(Y>38)and(Y<170)Then Sh:=Sh*0.7;
    If(Y>690)and(Y<696)Then Sh:=Sh*0.78;
    FabricColor(E,RgbOf(45,60,95),X,Y,480,720,R,Gc,B);
    AccPut(G,X,Y,Cov,R,Gc,B,Sh);
   End;
  End;
End;

{ jupe evasee avec ceinture et plis }
Procedure MakeSkirt(Var G:TGarment;const E:TEdit);
Var
 X,Y:LongInt;
 Xl,Xr,Yb,Cov,R,Gc,B,Sh,T:Single;
Begin
 AccAlloc(G,480,360);
 For Y:=0 to 359 do
  For X:=0 to 479 do Begin
   T:=Y/360.0;
   Xl:=100-92*T;Xr:=380+92*T;
   Yb:=355+4*Sin(X*0.05);
   Cov:=CoverD(FMax(Xl-X,FMax(X-Xr,Y-Yb)));
   If Cov>0 Then Begin
    Sh:=0.8+0.2*Sin((X-240)*0.09*(1+T))+0.08*(1-T);
    If Y<28 Then Sh:=0.82;
    If(Y>=28)and(Y<32)Then Sh:=Sh*0.7;
    Sh:=Sh*(1-0.18*Clamp((Abs(X-240)/(140+92*T)),0,1));
    FabricColor(E,RgbOf(60,60,78),X,Y,480,360,R,Gc,B);
    AccPut(G,X,Y,Cov,R,Gc,B,Sh);
   End;
  End;
End;

{ paire de souliers vue de face ; baskets = semelle blanche epaisse }
Procedure MakeShoes(Var G:TGarment;Const E:TEdit;Sneaker:Boolean);
Var
 X,Y,I:LongInt;
 Cx,Cov,Du,Ds,R,Gc,B,Sh:Single;
Begin
 AccAlloc(G,520,150);
 For Y:=0 to 149 do
  For X:=0 to 519 do
   For I:=0 to 1 do Begin
    If I=0 Then Cx:=135 Else Cx:=385;
    Ds:=EllipseD(X,Y,Cx,95,102,50);
    Cov:=CoverD(Ds);
    If Cov>0 Then Begin
     If Sneaker Then AccPut(G,X,Y,Cov,235,232,225,0.8+0.2*Clamp(1-(Y-60)/80.0,
       0,1))
     Else AccPut(G,X,Y,Cov,28,22,20,1);
    End;
    Du:=EllipseD(X,Y,Cx,70,92,52);
    Cov:=CoverD(Du);
    If Cov>0 Then Begin
     Sh:=0.62+0.5*Clamp(1-Abs(Y-45)/60.0,0,1)*(1-0.4*Abs(X-Cx)/92.0);
     FabricColor(E,RgbOf(60,42,32),X,Y,520,150,R,Gc,B);
     If(Y>28)and(Y<60)and(Abs(X-Cx)<30)and((Y-X)mod 14<3)Then Begin R:=235;
       Gc:=235;B:=235;End;
     AccPut(G,X,Y,Cov,R,Gc,B,Sh);
    End;
   End;
End;

{ ajoute un accessoire dessine par le programme }
Function AddAccessory(Var S:TScene;Const E:TEdit;Quality:LongInt;Var
  Msg:AnsiString):Boolean;
Var
 G:TGarment;
 Kind:LongInt;
 T:AnsiString;
 Shape:LongInt;
Begin
 AddAccessory:=False;
 Msg:='';
 If(E.Target and msScarf)<>0 Then Kind:=gkScarf
 Else If(E.Target and msHat)<>0 Then Kind:=gkHat
 Else If(E.Target and msGlasses)<>0 Then Kind:=gkGlasses
 Else If(E.Target and msBelt)<>0 Then Kind:=gkBelt
 Else If(E.Target and msPants)<>0 Then Kind:=gkBottom
 Else If(E.Target and msSkirt)<>0 Then Kind:=gkSkirt
 Else If(E.Target and msShoes)<>0 Then Kind:=gkShoes
 Else Begin
  Msg:='je ne sais ajouter que foulard, chapeau, bonnet, casquette, lunettes, '+
    'ceinture, pantalon, jupe et souliers ; '+
       'pour un autre v'#136'tement, fournissez sa photo : VTON '+
         'personne.jpg vetement.jpg -type TYPE';
  Exit;
 End;
 T:=E.Noun+' '+E.Text;
 FillChar(G,SizeOf(G),0);
 Case Kind of
  gkScarf:MakeScarf(G,E);
  gkHat:Begin
    Shape:=0;
    If(Pos('bonnet',T)>0)or(Pos('tuque',T)>0)or(Pos('beanie',T)>0)Then Shape:=1
    Else If(Pos('casquette',T)>0)or(Pos('cap',E.Noun)>0)Then Shape:=2;
    MakeHat(G,E,Shape,Pos('paille',T)+Pos('straw',T)>0);
   End;
  gkGlasses:MakeGlasses(G,E,(Pos('soleil',T)>0)or(Pos('sun',T)>0));
  gkBelt:MakeBelt(G,E);
  gkBottom:MakePants(G,E);
  gkSkirt:MakeSkirt(G,E);
  gkShoes:MakeShoes(G,E,(Pos('basket',T)>0)or(Pos('sneaker',T)>0)
    or(Pos('tennis',T)>0));
 End;
 AddAccessory:=TryOnGarment(S,G,Kind,Quality,Msg);
 GarmentFree(G);
End;

{ ------------------------------------------------------------------ }
{ Prolongement de l'image vers le bas (corps coupe par le cadre)      }
{ Les proportions viennent de la hauteur de la tete (environ 7,5 tetes }
{ de la tete aux pieds) ; le fond est prolonge, le torse et les bras    }
{ continuent, des jambes et des pieds sont ajoutes.                    }
{ ------------------------------------------------------------------ }

Function ExtendBody(Var S:TScene;NeedFeet,NeedPants,NeedSkirt:Boolean;Var
  Msg:AnsiString):Boolean;
Var
 Fx0,Fy0,Fx1,Fy1,Hx0,Hy0,Hx1,Hy1,Tx0,Ty0,Tx1,Ty1:LongInt;
 U,Ytop,Yneed,Cx,HipW,EW,YE,Ex0,Ex1:Single;
 H1,H2,W,Band,X,Y,K0,C,Src,Dom,Best,Sd,M:LongInt;
 N1,N2,Ks,Kr:int64;K:LongInt;
 Pix2,Fill,Known:PSingle;
 S2:TScene;
 Drop:PByte;
 SkR,SkG,SkB,T,Hw,Xc,D,Cov,Ux,Sh,Yleg0,Yank,Yfeet:Single;
 Side:LongInt;
 Dl,Df:Single;
Begin
 ExtendBody:=False;
 Msg:='';
 W:=S.W;H1:=S.H;
 If not CatBBox(S,msFace,Fx0,Fy0,Fx1,Fy1)Then Begin
  Msg:='aucun visage d'#130'tect'#130' : impossible d''estimer les '+
    'proportions du corps pour prolonger l''image';
  Exit;
 End;
 If not CatBBox(S,msFace or msHair or msHat,Hx0,Hy0,Hx1,Hy1)Then Begin
   Hy0:=Fy0;End;
 Ytop:=Hy0;
 U:=Fy1+1-Ytop;
 If U<10 Then Begin
   Msg:='la t'#136'te est trop petite pour prolonger l''image';Exit;End;
 If not CatBBox(S,msTop or msDress or msSkirt or msPants or msLegs,Tx0,Ty0,
   Tx1,Ty1)Then Begin
  Msg:='aucun haut ni corps d'#130'tect'#130' sous le visage : impossible de '+
    'prolonger l''image';
  Exit;
 End;
 If NeedFeet Then Yneed:=Ytop+7.75*U
 Else If NeedPants Then Yneed:=Ytop+7.45*U
 Else If NeedSkirt Then Yneed:=Ytop+6.2*U
 Else Begin ExtendBody:=True;Exit;End;
 H2:=Trunc(Yneed)+1;
 If H2<=H1+4 Then Begin ExtendBody:=True;Exit;End;
 { le corps doit toucher le bas du cadre (sinon il est entier : rien a
   prolonger) }
 EW:=0;
 For Y:=IMax(0,H1-IMax(2,H1 div 50))to H1-1 do
  For X:=0 to W-1 do If S.Cat[cBg][Int64(Y)*W+X]<128 Then EW:=EW+1;
 If EW<W*0.02 Then Begin ExtendBody:=True;Exit;End;
 If(H2>4*H1)or(H2>8000)or(Int64(W)*H2>20000000)Then Begin
  Msg:='l''image est trop petite ou le corps trop cadr'#130' pour '#136'tre '+
    'prolong'#130' ('+IStr(H2)
    +' pixels de haut n'#130'cessaires) ; essayez -maxsize';
  Exit;
 End;
 { axe du corps et largeur des hanches }
 If CatBBox(S,msTop or msDress,Tx0,Ty0,Tx1,Ty1)Then Cx:=(Tx0+Tx1+1)/2 Else
   Cx:=(Fx0+Fx1+1)/2;
 Ex0:=W;Ex1:=-1;
 For Y:=IMax(0,H1-4)to H1-1 do
  For X:=0 to W-1 do Begin
   K:=Int64(Y)*W+X;
   If(S.Cat[cTop][K]+S.Cat[cDress][K])>=128 Then Begin
    If X<Ex0 Then Ex0:=X;
    If X>Ex1 Then Ex1:=X;
   End;
  End;
 If Ex1>=Ex0 Then EW:=Ex1-Ex0+1 Else EW:=2.0*U;
 HipW:=Clamp(0.8*EW,1.2*U,1.75*U);
 N1:=Int64(W)*H1;N2:=Int64(W)*H2;
 Pix2:=AllocF(N2*3);
 FillChar(S2,SizeOf(S2),0);
 For C:=0 to NumCat-1 do S2.Cat[C]:=PByte(AllocBytes(N2));
 Move(S.Pix^,Pix2^,N1*12);
 For C:=0 to NumCat-1 do Move(S.Cat[C]^,S2.Cat[C]^,N1);
 Drop:=PByte(AllocBytes(N2));
 { nouvelles rangees : reflet de la bande du bas, coupe selon les proportions }
 Band:=IMax(6,IMin(40,H1 div 12));
 For Y:=H1 to H2-1 do Begin
  M:=(Y-H1)mod(2*Band);
  If M<Band Then Src:=H1-1-M Else Src:=H1-Band+(M-Band);
  For X:=0 to W-1 do Begin
   K:=Int64(Y)*W+X;
   { dominante de la derniere rangee de la colonne }
   Dom:=cBg;
   If S.Cat[cBg][Int64(H1-1)*W+X]<252 Then Begin
    { pixel de bord compris : la colonne est prolongee comme le corps voisin }
    Best:=-1;
    For C:=0 to NumCat-1 do If C<>cBg Then
     If S.Cat[C][Int64(H1-1)*W+X]>Best Then Begin Best:=S.Cat[C][Int64(H1-1)*W+
       X];Dom:=C;End;
   End;
   If Dom=cBg Then Begin
    { colonne de fond : remplie plus bas par propagation (evite les motifs en
      miroir) }
    Drop[K]:=1;
    Continue;
   End;
   { colonne de corps : la derniere rangee est prolongee vers le bas }
   Ks:=Int64(H1-1)*W+X;
   { texture : pixel reflete s'il est de la meme classe, sinon derniere rangee }
   Kr:=Int64(Src)*W+X;
   Best:=-1;Sd:=0;
   For C:=0 to NumCat-1 do If C<>cBg Then If S.Cat[C][Kr]>Best Then Begin
     Best:=S.Cat[C][Kr];Sd:=C;End;
   If(Sd=Dom)and(S.Cat[cBg][Kr]<252)Then Begin
    Pix2[K*3]:=Pix2[Kr*3];Pix2[K*3+1]:=Pix2[Kr*3+1];Pix2[K*3+2]:=Pix2[Kr*3+2];
   End
    Else Begin
     Pix2[K*3]:=Pix2[Ks*3]+RngGauss*1.4;Pix2[K*3+1]:=Pix2[Ks*3+1]+
       RngGauss*1.4;Pix2[K*3+2]:=Pix2[Ks*3+2]+RngGauss*1.4;
    End;
   For C:=0 to NumCat-1 do S2.Cat[C][K]:=S.Cat[C][Ks];
   Case Dom of
    cTop:If Abs(X-Cx)<=HipW/2+0.12*U Then YE:=Ytop+3.45*U Else YE:=Ytop+4.4*U;
    cDress:If Abs(X-Cx)<=HipW/2+0.12*U Then YE:=Ytop+5.4*U Else YE:=Ytop+4.4*U;
    cSkirt:YE:=Ytop+5.4*U;
    cPants,cLegs:YE:=Ytop+7.2*U;
    cShoes:YE:=Ytop+7.7*U;
    cArms:YE:=Ytop+4.5*U;
    cBelt:YE:=Ytop+3.5*U;
    cBag,cScarf,cOther,cSkin:YE:=Ytop+4.0*U;
    Else YE:=0;
   End;
   If Y>YE Then Drop[K]:=1;
  End;
 End;
 { fond : prolonge par propagation depuis les pixels d'arriere-plan surs }
 Known:=AllocF(N2);
 Fill:=AllocF(N2*3);
 Move(Pix2^,Fill^,N2*12);
 For K:=0 to N2-1 do
  If(Drop[K]=0)and(S2.Cat[cBg][K]>=252)Then Known[K]:=1;
 PushPullFill(Fill,Known,W,H2);
 For K:=Int64(H1)*W to N2-1 do If Drop[K]<>0 Then Begin
  For C:=0 to 2 do Pix2[K*3+C]:=Fill[K*3+C]+RngGauss*1.6;
  For C:=0 to NumCat-1 do S2.Cat[C][K]:=0;
  S2.Cat[cBg][K]:=255;
 End;
 FreeMem(Known);FreeMem(Fill);FreeMem(Drop);
 { jambes (peau) et pieds : reperes pour poser pantalon, jupe ou souliers }
 S2.W:=W;S2.H:=H2;S2.Pix:=Pix2;
 If not SkinColor(S2,False,SkR,SkG,SkB)Then Begin SkR:=224;SkG:=172;SkB:=140;
   End;
 Yleg0:=Ytop+3.3*U;Yank:=Ytop+7.15*U;Yfeet:=Ytop+7.7*U;
 For Y:=H1 to H2-1 do Begin
  If Y<Yleg0 Then Continue;
  T:=Clamp((Y-Yleg0)/(Yank-Yleg0),0,1);
  If T>0 Then Hw:=HipW*0.235-(HipW*0.235-0.15*U)*Exp(0.8*Ln(T))Else
    Hw:=HipW*0.235;
  For X:=0 to W-1 do Begin
   K:=Int64(Y)*W+X;
   If S2.Cat[cBg][K]<128 Then Continue;
   Cov:=0;Ux:=0;
   For Side:=-1 to 1 do Begin
    If Side=0 Then Continue;
    Xc:=Cx+Side*HipW*0.25;
    If Y<=Yank+0.05*U Then Begin
     D:=Abs(X-Xc)-Hw;
     If CoverD(D)>Cov Then Begin Cov:=CoverD(D);Ux:=(X-Xc)/Hw;End;
    End;
    If NeedFeet and(Y>Yank-0.05*U)Then Begin
     Df:=EllipseD(X,Y,Xc,Yank+0.1*U,0.2*U,0.2*U);
     If CoverD(Df)>Cov Then Begin Cov:=CoverD(Df);Ux:=(X-Xc)/(0.2*U);End;
    End;
   End;
   If Cov>0 Then Begin
    Ux:=Clamp(Ux,-1,1);
    Sh:=0.78+0.3*Sqrt(1-Ux*Ux);
    Pix2[K*3]:=Pix2[K*3]*(1-Cov)+(SkR*Sh+RngGauss*1.5)*Cov;
    Pix2[K*3+1]:=Pix2[K*3+1]*(1-Cov)+(SkG*Sh+RngGauss*1.5)*Cov;
    Pix2[K*3+2]:=Pix2[K*3+2]*(1-Cov)+(SkB*Sh+RngGauss*1.5)*Cov;
    M:=Trunc(Cov*255+0.5);
    S2.Cat[cLegs][K]:=M;
    S2.Cat[cBg][K]:=255-M;
   End;
  End;
 End;
 GAnkleY:=Yank;
 GHemY:=Ytop+3.45*U;
 { remplace la scene }
 FreeMem(S.Pix);
 For C:=0 to NumCat-1 do FreeMem(S.Cat[C]);
 S:=S2;
 Msg:='image prolong'#130'e de '+IStr(H1)+' '#133' '+IStr(H2)
   +' pixels de haut (proportions d'#130'duites de la t'#136'te)';
 ExtendBody:=True;
End;

{ ------------------------------------------------------------------ }
{ Cheveux : couleur, longueur, boucles, calvitie                      }
{ ------------------------------------------------------------------ }

Function Hash2(X,Y:LongInt):Single;
Var
 H:Int64;
Begin
 H:=(Int64(X)*374761393+Int64(Y)*668265263)and $FFFFFFFF;
 H:=((H xor(H shr 13))*1274126177)and $FFFFFFFF;
 H:=H xor(H shr 16);
 Hash2:=(H and $FFFFFF)/16777216.0;
End;

{ bruit de valeur lisse dans [0,1] }
Function VNoise(X,Y:Single):Single;
Var
 X0,Y0:LongInt;
 Fx,Fy,A,B,C,D:Single;
Begin
 X0:=FloorI(X);Y0:=FloorI(Y);
 Fx:=X-X0;Fy:=Y-Y0;
 Fx:=Fx*Fx*(3-2*Fx);Fy:=Fy*Fy*(3-2*Fy);
 A:=Hash2(X0,Y0);B:=Hash2(X0+1,Y0);C:=Hash2(X0,Y0+1);D:=Hash2(X0+1,Y0+1);
 VNoise:=(A*(1-Fx)+B*Fx)*(1-Fy)+(C*(1-Fx)+D*Fx)*Fy;
End;

Type
 THeadInfo=Record
  Fx0,Fy0,Fx1,Fy1:LongInt;
  Cx,Fw,Fh:Single;
  HairR,HairG,HairB:Single;
  HasHair:Boolean;
 End;

{ visage et couleur moyenne des cheveux }
Function HeadInfo(Const S:TScene;Var H:THeadInfo):Boolean;
Var
 N,Cnt:int64;K:LongInt;
 M:PSingle;
 Sr,Sg,Sb:Double;
Begin
 HeadInfo:=False;
 If not CatBBox(S,msFace,H.Fx0,H.Fy0,H.Fx1,H.Fy1)Then Exit;
 H.Fw:=H.Fx1-H.Fx0+1;H.Fh:=H.Fy1-H.Fy0+1;
 H.Cx:=(H.Fx0+H.Fx1+1)/2;
 N:=Int64(S.W)*S.H;
 M:=AllocF(N);
 CatMask(S,msHair,M);
 Sr:=0;Sg:=0;Sb:=0;Cnt:=0;
 For K:=0 to N-1 do If M[K]>=0.8 Then Begin
  Sr:=Sr+S.Pix[K*3];Sg:=Sg+S.Pix[K*3+1];Sb:=Sb+S.Pix[K*3+2];Inc(Cnt);
 End;
 FreeMem(M);
 H.HasHair:=Cnt>=N div 4000;
 If H.HasHair Then Begin H.HairR:=Sr/Cnt;H.HairG:=Sg/Cnt;H.HairB:=Sb/Cnt;End
 Else Begin H.HairR:=60;H.HairG:=40;H.HairB:=30;End;
 HeadInfo:=True;
End;

{ remplace les pixels ponderes par Rm (retrait) : la partie SkinW devient de la
  peau
  (prolongement du visage), le reste du fond (propagation) }
Procedure FillRemoved(Var S:TScene;Rm,SkinW:PSingle;Const H:THeadInfo);
Var
 N:int64;K:LongInt;
 Known1,Known2,F:PSingle;
 T1,T2:PSingle;
 W1,W2:Single;
 C,Mv:LongInt;
Begin
 N:=Int64(S.W)*S.H;
 Known1:=AllocF(N);Known2:=AllocF(N);F:=AllocF(N);
 T1:=AllocF(N*3);T2:=AllocF(N*3);
 Move(S.Pix^,T1^,N*12);Move(S.Pix^,T2^,N*12);
 CatMask(S,msFace,F);
 For K:=0 to N-1 do Begin
  Known1[K]:=1-Rm[K];
  If(F[K]>=0.9)and(Rm[K]<0.1)Then Known2[K]:=1;
 End;
 PushPullFill(T1,Known1,S.W,S.H);
 PushPullFill(T2,Known2,S.W,S.H);
 For K:=0 to N-1 do If Rm[K]>0.02 Then Begin
  W2:=Rm[K]*SkinW[K];
  W1:=Rm[K]-W2;
  For C:=0 to 2 do
   S.Pix[K*3+C]:=S.Pix[K*3+C]*(1-Rm[K])+(T1[K*3+C]+RngGauss*1.5)*W1+(T2[K*3+
     C]+RngGauss*1.2)*W2;
  If Rm[K]>0.5 Then Begin
   For C:=0 to NumCat-1 do S.Cat[C][K]:=0;
   If SkinW[K]>=0.5 Then S.Cat[cFace][K]:=255 Else S.Cat[cBg][K]:=255;
  End;
 End;
 FreeMem(Known1);FreeMem(Known2);FreeMem(F);FreeMem(T1);FreeMem(T2);
 { le reste du visage n'a pas change }
End;

{ crane : ellipse au-dessus du visage }
Function DomeCover(Const H:THeadInfo;X,Y:Single;Scale:Single):Single;
Var
 Cy,Rx,Ry:Single;
Begin
 Cy:=H.Fy0+0.25*H.Fh;
 Rx:=0.5*H.Fw*Scale;
 Ry:=Cy-(H.Fy0-0.33*H.Fh);
 DomeCover:=CoverD(EllipseD(X,Y,H.Cx,Cy,Rx,Ry*Scale));
End;

Function HairBald(Var S:TScene;Const H:THeadInfo;Var Msg:AnsiString):Boolean;
Var
 N:int64;K:LongInt;
 Rm,Sk,Hm:PSingle;
 B:PByte;
 X,Y:LongInt;
 Cnt:Int64;
Begin
 HairBald:=False;
 N:=Int64(S.W)*S.H;
 Hm:=AllocF(N);Rm:=AllocF(N);Sk:=AllocF(N);
 CatMask(S,msHair,Hm);
 B:=PByte(AllocBytes(N));
 Cnt:=0;
 For K:=0 to N-1 do If Hm[K]>=0.3 Then Begin B[K]:=255;Inc(Cnt);End;
 If Cnt=0 Then Begin
  Msg:='aucun cheveu d'#130'tect'#130' sur la photo';
  FreeMem(Hm);FreeMem(Rm);FreeMem(Sk);FreeMem(B);Exit;
 End;
 MorphMask(B,S.W,S.H,2,False);
 For K:=0 to N-1 do Rm[K]:=B[K]/255.0;
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   If Rm[K]>0 Then Sk[K]:=DomeCover(H,X+0.5,Y+0.5,1.0);
  End;
 FillRemoved(S,Rm,Sk,H);
 FreeMem(Hm);FreeMem(Rm);FreeMem(Sk);FreeMem(B);
 HairBald:=True;
End;

Function HairShorter(Var S:TScene;Const H:THeadInfo;Var Msg:AnsiString):Boolean;
Var
 N,K:Int64;
 Hm,Rm,Sk:PSingle;
 X,Y:LongInt;
 Keep,D,Cy,Rx,Ry,YEar,NeckW:Single;
 Cnt:Int64;
 Hy0,Hy1,Hx0,Hx1:LongInt;
Begin
 HairShorter:=False;
 N:=Int64(S.W)*S.H;
 If not CatBBox(S,msHair,Hx0,Hy0,Hx1,Hy1)Then Begin
   Msg:='aucun cheveu d'#130'tect'#130' sur la photo';Exit;End;
 Hm:=AllocF(N);Rm:=AllocF(N);Sk:=AllocF(N);
 CatMask(S,msHair,Hm);
 Cy:=H.Fy0+0.2*H.Fh;
 Rx:=0.5*H.Fw*1.22;
 Ry:=FMin(Cy-Hy0+1,0.8*H.Fh);
 YEar:=H.Fy0+0.6*H.Fh;
 NeckW:=0.36*H.Fw;
 Cnt:=0;
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   If Hm[K]<0.05 Then Continue;
   { zone conservee : dome elargi + cotes jusqu'aux oreilles }
   Keep:=CoverD(EllipseD(X+0.5,Y+0.5,H.Cx,Cy,Rx,Ry));
   If(Y<=YEar)and(X>=H.Fx0-0.16*H.Fw)and(X<=H.Fx1+0.16*H.Fw)Then Begin
    D:=CoverD(Y-YEar);
    If D>Keep Then Keep:=D;
   End;
   Rm[K]:=Hm[K]*(1-Keep);
   If Rm[K]>0.3 Then Inc(Cnt);
   { le cou apparait sous le menton a la place des cheveux retires }
   If(Abs(X-H.Cx)<NeckW)and(Y>=H.Fy1-0.05*H.Fh)and(Y<=H.Fy1+0.9*H.Fh)Then
     Sk[K]:=1;
  End;
 If Cnt<20 Then Begin
  Msg:='les cheveux sont d'#130'j'#133' courts';
  FreeMem(Hm);FreeMem(Rm);FreeMem(Sk);Exit;
 End;
 FillRemoved(S,Rm,Sk,H);
 FreeMem(Hm);FreeMem(Rm);FreeMem(Sk);
 HairShorter:=True;
End;

Function HairLonger(Var S:TScene;Const H:THeadInfo;Var Msg:AnsiString):Boolean;
Var
 N,K:Int64;
 Hm,Fm:PSingle;
 X,Y,Side,Hx0,Hy0,Hx1,Hy1,C:LongInt;
 YEar,YEnd,T,Xin,Xout,Wd,Cov,D,Cyf,Ex,Strand,Shade,Tip,Edge,Cs,Mid,Hw:Single;
 YbSide,XbaseL,XbaseR,Xb:Single;
 Sg:Array[0..1]of Single;
 R,G,B,V,V2,Sx:Single;
 Mv:LongInt;
Begin
 HairLonger:=False;
 If not H.HasHair Then Begin
   Msg:='aucun cheveu d'#130'tect'#130' sur la photo';Exit;End;
 N:=Int64(S.W)*S.H;
 Hm:=AllocF(N);Fm:=AllocF(N);
 CatMask(S,msHair,Hm);CatMask(S,msFace,Fm);
 CatBBox(S,msHair,Hx0,Hy0,Hx1,Hy1);
 YEar:=H.Fy0+0.55*H.Fh;
 Cyf:=(H.Fy0+H.Fy1)/2;
 { rangee la plus basse des cheveux de chaque cote }
 Sg[0]:=YEar;Sg[1]:=YEar;
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do If Hm[Int64(Y)*S.W+X]>=0.5 Then Begin
   If X<H.Cx Then Begin If Y>Sg[0]Then Sg[0]:=Y;End
   Else Begin If Y>Sg[1]Then Sg[1]:=Y;End;
  End;
 For Side:=0 to 1 do Begin
  YbSide:=Sg[Side];
  YEnd:=FMax(YbSide,H.Fy1+0.2*H.Fh)+0.9*H.Fh;
  If YEnd>S.H-2 Then YEnd:=S.H-2;
  { bord exterieur des cheveux existants a hauteur des oreilles }
  XbaseL:=H.Fx0-0.22*H.Fw;XbaseR:=H.Fx1+0.22*H.Fw;
  Xb:=-1;
  For Y:=Trunc(YEar-0.1*H.Fh)to Trunc(YEar+0.1*H.Fh)do
   For X:=0 to S.W-1 do If Hm[Int64(Y)*S.W+X]>=0.5 Then Begin
    If(Side=0)and(X<H.Cx)and((Xb<0)or(X<Xb))Then Xb:=X;
    If(Side=1)and(X>H.Cx)and(X>Xb)Then Xb:=X;
   End;
  If Xb>=0 Then Begin
   If Side=0 Then XbaseL:=FMin(Xb,H.Fx0-0.05*H.Fw)Else XbaseR:=FMax(Xb,
     H.Fx1+0.05*H.Fw);
  End;
  For Y:=Trunc(YEar-0.25*H.Fh)to Trunc(YEnd)do Begin
   T:=(Y-YEar)/(YEnd-YEar);
   If T<0 Then T:=0;
   If Y<H.Fy1 Then Begin
    Ex:=(Y-Cyf)/(H.Fh/2);
    If Abs(Ex)>1 Then Ex:=1;
    Xin:=0.5*H.Fw*Sqrt(1-Ex*Ex)-0.02*H.Fw;
   End
    Else Xin:=0.34*H.Fw;
   Wd:=0.12*H.Fw*SmoothStep(0.0,0.8,T);
   For X:=0 to S.W-1 do Begin
    If Side=0 Then Begin
     Xout:=XbaseL-Wd;Cs:=H.Cx-Xin;
     D:=FMax(Xout-X,X-Cs);
    End
     Else Begin
      Xout:=XbaseR+Wd;Cs:=H.Cx+Xin;
      D:=FMax(Cs-X,X-Xout);
     End;
    Cov:=CoverD(D);
    If Cov<=0 Then Continue;
    K:=Int64(Y)*S.W+X;
    { l'ensemble s'effile en bas : bord interieur rabattu vers l'exterieur }
    Tip:=1-SmoothStep(0.78+0.14*VNoise(X*0.35,3.0),1.0,T);
    Cov:=Cov*Tip;
    If Y<YEar Then Cov:=Cov*SmoothStep(YEar-0.25*H.Fh,YEar,Y);
    Cov:=Cov*(1-SmoothStep(0.2,0.8,Fm[K]));
    If Cov<=0.01 Then Continue;
    Mid:=(Xout+Cs)/2;Hw:=Abs(Xout-Cs)/2+0.001;
    Edge:=(X-Mid)/Hw;
    Strand:=0.78+0.44*VNoise(X*0.75,Y*0.045+Side*7);
    Shade:=(0.78+0.3*(1-Edge*Edge))*(1-0.22*T);
    V:=Strand*Shade;
    R:=H.HairR*V;G:=H.HairG*V;B:=H.HairB*V;
    S.Pix[K*3]:=S.Pix[K*3]*(1-Cov)+R*Cov;
    S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-Cov)+G*Cov;
    S.Pix[K*3+2]:=S.Pix[K*3+2]*(1-Cov)+B*Cov;
    Mv:=Trunc(Cov*255+0.5);
    For C:=0 to NumCat-1 do S.Cat[C][K]:=Trunc(S.Cat[C][K]*(1-Cov)+0.5);
    Mv:=Mv+S.Cat[cHair][K];
    If Mv>255 Then Mv:=255;
    S.Cat[cHair][K]:=Mv;
   End;
  End;
 End;
 FreeMem(Hm);FreeMem(Fm);
 HairLonger:=True;
End;

Function HairCurly(Var S:TScene;Const H:THeadInfo;Var Msg:AnsiString):Boolean;
Var
 N,K:Int64;
 Hm,Bl,Fm:PSingle;
 X,Y,C,Mv:LongInt;
 Rr,Nz,Ex,Cov,Kk,Tx,F,V:Single;
 R,G,B,Pr,Pg,Pb:Single;
Begin
 HairCurly:=False;
 If not H.HasHair Then Begin
   Msg:='aucun cheveu d'#130'tect'#130' sur la photo';Exit;End;
 N:=Int64(S.W)*S.H;
 Hm:=AllocF(N);Bl:=AllocF(N);Fm:=AllocF(N);
 CatMask(S,msHair,Hm);CatMask(S,msFace,Fm);
 Move(Hm^,Bl^,N*4);
 Rr:=0.16*H.Fw;
 BlurPlane(Bl,S.W,S.H,Rr);
 Kk:=2*Pi/(0.13*H.Fw);
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   If(Bl[K]<0.02)and(Hm[K]<0.02)Then Continue;
   { silhouette gonflee et festonnee }
   Nz:=VNoise(X/(0.10*H.Fw),Y/(0.10*H.Fw))*1.3+VNoise(X/(0.05*H.Fw)+9,
     Y/(0.05*H.Fw)+4)*0.7-1.0;
   Ex:=SmoothStep(0.24,0.32,Bl[K]+0.16*Nz);
   Cov:=FMax(Hm[K],Ex);
   Cov:=Cov*(1-SmoothStep(0.2,0.8,Fm[K]));
   If Cov<=0.01 Then Continue;
   { boucles : anneaux de lumiere et d'ombre }
   Tx:=0.5+0.5*Sin(Kk*(X+2.4*Sin(Kk*Y*0.7)))*Cos(Kk*(Y+2.4*Sin(Kk*X*0.7)));
   F:=0.62+0.62*Tx;
   If Hm[K]>=0.5 Then Begin
    S.Pix[K*3]:=S.Pix[K*3]*(0.45+0.55*F)*1.04;
    S.Pix[K*3+1]:=S.Pix[K*3+1]*(0.45+0.55*F)*1.04;
    S.Pix[K*3+2]:=S.Pix[K*3+2]*(0.45+0.55*F)*1.04;
   End
    Else Begin
     V:=F*(0.85+0.3*VNoise(X*0.5,Y*0.5));
     R:=H.HairR*V;G:=H.HairG*V;B:=H.HairB*V;
     S.Pix[K*3]:=S.Pix[K*3]*(1-Cov)+R*Cov;
     S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-Cov)+G*Cov;
     S.Pix[K*3+2]:=S.Pix[K*3+2]*(1-Cov)+B*Cov;
     If Cov>0.3 Then Begin
      Mv:=Trunc(Cov*255+0.5);
      For C:=0 to NumCat-1 do S.Cat[C][K]:=Trunc(S.Cat[C][K]*(1-Cov)+0.5);
      Mv:=Mv+S.Cat[cHair][K];
      If Mv>255 Then Mv:=255;
      S.Cat[cHair][K]:=Mv;
     End;
    End;
  End;
 FreeMem(Hm);FreeMem(Bl);FreeMem(Fm);
 HairCurly:=True;
End;

{ applique une retouche de coiffure (et la couleur eventuelle) }
Function ApplyHair(Var S:TScene;Style:LongInt;Const E:TEdit;Var Msg:AnsiString)
  :Boolean;
Var
 H:THeadInfo;
 Ok:Boolean;
 M:PSingle;
 P:TRecolor;
 X0,Y0,X1,Y1:LongInt;
 N:Int64;
Begin
 ApplyHair:=False;
 Msg:='';
 If not HeadInfo(S,H)Then Begin
  Msg:='aucun visage d'#130'tect'#130' : impossible de modifier la coiffure';
  Exit;
 End;
 Ok:=True;
 Case Style of
  hsBald:Ok:=HairBald(S,H,Msg);
  hsShorter:Ok:=HairShorter(S,H,Msg);
  hsLonger:Ok:=HairLonger(S,H,Msg);
  hsCurly:Ok:=HairCurly(S,H,Msg);
  hsStraight:Begin Msg:='les cheveux lisses ne sont pas pris en charge';
    Ok:=False;End;
 End;
 If not Ok Then Exit;
 { couleur demandee en plus du style }
 If(E.HasDst or(E.Pattern<>pkNone))and(Style<>hsBald)Then Begin
  N:=Int64(S.W)*S.H;
  M:=AllocF(N);
  CatMask(S,msHair,M);
  SharpenAlpha(M,N);
  If CatBBox(S,msHair,X0,Y0,X1,Y1)Then Begin
   BuildRecolor(E,P,X0,Y0,X1-X0+1,Y1-Y0+1,False);
   RecolorRegion(S.Pix,S.W,S.H,M,P);
  End;
  FreeMem(M);
 End;
 ApplyHair:=True;
End;

{ ------------------------------------------------------------------ }
{ Bijoux : collier, boucles d'oreilles, bracelet, montre, diamants      }
{ (dessines par le programme, poses selon le visage et les poignets)    }
{ ------------------------------------------------------------------ }

Function ATan2F(Y,X:Single):Single;
Begin
 If X>0 Then ATan2F:=ArcTan(Y/X)
 Else If X<0 Then Begin
  If Y>=0 Then ATan2F:=ArcTan(Y/X)+Pi Else ATan2F:=ArcTan(Y/X)-Pi;
 End
  Else Begin
   If Y>0 Then ATan2F:=Pi/2 Else If Y<0 Then ATan2F:=-Pi/2 Else ATan2F:=0;
  End;
End;

{ ombrage d'un metal : T de 0 a 1 en travers de la piece }
Function MetalV(T:Single):Single;
Var
 A,B:Single;
Begin
 A:=(T-0.30)/0.16;B:=(T-0.78)/0.09;
 MetalV:=0.52+0.62*Exp(-A*A)+0.32*Exp(-B*B)+0.10*Sin(T*Pi);
End;

Procedure PutJewel(Var S:TScene;X,Y:LongInt;Cov,R,G,B:Single;Prot:PSingle);
Var
 K:Int64;
 P:Single;
Begin
 If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Exit;
 K:=Int64(Y)*S.W+X;
 If Prot<>Nil Then Begin
  P:=Prot[K];
  If P>0.15 Then Cov:=Cov*(1-SmoothStep(0.15,0.85,P));
 End;
 If Cov<=0.004 Then Exit;
 If R>255 Then R:=255;If G>255 Then G:=255;If B>255 Then B:=255;
 S.Pix[K*3]:=S.Pix[K*3]*(1-Cov)+R*Cov;
 S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-Cov)+G*Cov;
 S.Pix[K*3+2]:=S.Pix[K*3+2]*(1-Cov)+B*Cov;
End;

{ pierre taillee en brillant : facettes, table et eclats }
Procedure DrawGem(Var S:TScene;Cx,Cy,R:Single;Metal:LongWord;Tint:LongWord;
  Prot:PSingle);
Var
 X,Y,X0,X1,Y0,Y1,Sec:LongInt;
 Dx,Dy,Dp,A,Rr,Cov,V,Br,Sp,Mr,Mg,Mb,Rd,Gr,Bl,Ring:Single;
Begin
 If R<1.2 Then R:=1.2;
 X0:=Trunc(Cx-R*2.4);X1:=Trunc(Cx+R*2.4)+1;Y0:=Trunc(Cy-R*2.4);Y1:=Trunc(Cy+
   R*2.4)+1;
 Mr:=(Metal shr 16)and $FF;Mg:=(Metal shr 8)and $FF;Mb:=Metal and $FF;
 For Y:=Y0 to Y1 do
  For X:=X0 to X1 do Begin
   Dx:=X+0.5-Cx;Dy:=Y+0.5-Cy;
   Dp:=FMax(Abs(Dx),FMax(Abs(Dy),(Abs(Dx)+Abs(Dy))*0.7071));
   { monture }
   Ring:=CoverD(Dp-1.22*R);
   If Ring>0 Then Begin
    V:=MetalV(Clamp(0.5+(Dy/(2.4*R)),0,1));
    PutJewel(S,X,Y,Ring,Mr*V,Mg*V,Mb*V,Prot);
   End;
   Cov:=CoverD(Dp-0.93*R);
   If Cov>0 Then Begin
    A:=ATan2F(Dy,Dx);
    Sec:=FloorI((A+Pi)/(Pi/4));
    Rr:=Sqrt(Dx*Dx+Dy*Dy)/R;
    If Rr<0.46 Then Br:=0.97
    Else Br:=0.58+0.42*(((Sec*3+Ord(Rr>0.75))mod 4)/3.0);
    Br:=Br*(0.9+0.1*Cos(A*2-0.6));
    Rd:=((Tint shr 16)and $FF)*Br;Gr:=((Tint shr 8)and $FF)*Br;Bl:=(Tint and
      $FF)*Br;
    PutJewel(S,X,Y,Cov,Rd,Gr,Bl,Prot);
   End;
   { eclat en croix }
   Sp:=Exp(-Abs(Dx)/(0.10*R+0.3))*Exp(-Abs(Dy)/(1.9*R))+Exp(-Abs(Dy)/(0.10*R+
     0.3))*Exp(-Abs(Dx)/(1.9*R));
   Sp:=Sp*0.55;
   If Sp>0.03 Then PutJewel(S,X,Y,FMin(Sp,0.8),255,255,255,Prot);
  End;
End;

Procedure DrawNecklace(Var S:TScene;Const H:THeadInfo;Metal,
  Tint:LongWord;Diamond:Boolean;Prot:PSingle);
Var
 X,Y,X0,X1,Y0,Y1:LongInt;
 YA,YB,Half,Wc,T,Yc,Slope,D,Cov,V,Lk,Mr,Mg,Mb,Rg:Single;
Begin
 YA:=H.Fy1+0.02*H.Fh;
 YB:=H.Fy1+0.72*H.Fh;
 Half:=0.30*H.Fw;
 Wc:=FMax(1.7,0.032*H.Fw);
 Mr:=(Metal shr 16)and $FF;Mg:=(Metal shr 8)and $FF;Mb:=Metal and $FF;
 X0:=Trunc(H.Cx-Half)-2;X1:=Trunc(H.Cx+Half)+2;
 Y0:=Trunc(YA)-3;Y1:=Trunc(YB)+3;
 For Y:=Y0 to Y1 do
  For X:=X0 to X1 do Begin
   T:=(X+0.5-H.Cx)/Half;
   If Abs(T)>1.04 Then Continue;
   Yc:=YA+(YB-YA)*(1-T*T);
   Slope:=-2*T*(YB-YA)/Half;
   D:=Abs(Y+0.5-Yc)/Sqrt(1+Slope*Slope);
   Cov:=CoverD(D-Wc/2);
   If Cov>0 Then Begin
    Lk:=0.72+0.28*Sin((X+0.5)*Sqrt(1+Slope*Slope)*2*Pi/(1.8*Wc));
    V:=MetalV(Clamp(0.5+(Y+0.5-Yc)/Wc/1.3,0,1))*Lk;
    PutJewel(S,X,Y,Cov,Mr*V,Mg*V,Mb*V,Prot);
   End;
  End;
 { pendentif }
 Rg:=0.062*H.Fw;
 If Diamond Then DrawGem(S,H.Cx,YB+Rg*1.7,Rg,Metal,RgbOf(232,242,255),Prot)
 Else DrawGem(S,H.Cx,YB+Rg*1.6,Rg*0.8,Metal,Metal,Prot);
End;

Procedure DrawEarrings(Var S:TScene;Const H:THeadInfo;Metal:LongWord;
  Diamond:Boolean;Prot:PSingle);
Var
 Side:LongInt;
 Ex,Ey,Rg,Y:Single;
 X,YY:LongInt;
 Cov,V,Mr,Mg,Mb:Single;
Begin
 Mr:=(Metal shr 16)and $FF;Mg:=(Metal shr 8)and $FF;Mb:=Metal and $FF;
 Rg:=0.040*H.Fw;
 For Side:=-1 to 1 do Begin
  If Side=0 Then Continue;
  If Side<0 Then Ex:=H.Fx0-0.035*H.Fw Else Ex:=H.Fx1+0.035*H.Fw;
  Ey:=H.Fy0+0.62*H.Fh;
  { petite tige et pierre qui pend }
  For YY:=Trunc(Ey)to Trunc(Ey+0.14*H.Fh)do
   For X:=Trunc(Ex)-2 to Trunc(Ex)+2 do Begin
    Cov:=CoverD(Abs(X+0.5-Ex)-0.7);
    If Cov>0 Then PutJewel(S,X,YY,Cov,Mr*0.9,Mg*0.9,Mb*0.9,Nil);
   End;
  If Diamond Then DrawGem(S,Ex,Ey+0.14*H.Fh+Rg*1.3,Rg,Metal,RgbOf(232,242,255)
    ,Nil)
  Else DrawGem(S,Ex,Ey+0.14*H.Fh+Rg*1.2,Rg*0.85,Metal,Metal,Nil);
 End;
End;

Type
 TWrist=Record
  X,Y,Ax,Ay,W:Single;     { centre, direction vers la main, largeur du poignet }
 End;

{ poignets : composantes connexes de la categorie bras, extremite cote main }
Function FindWrists(Const S:TScene;Var Wr:Array of TWrist):LongInt;
Var
 N:Int64;
 B:PByte;
 Lab:PIntArr;
 Areas:TIntArray;
 NC,I,J,Cnt,X,Y,Best:LongInt;
 P:LongInt;
 Mx,My,Sxx,Sxy,Syy,Cs,Sn,Th,Ax,Ay,Pj,Pmin,Pmax,Vend,Pw,Uc,Umin,Umax,Sx,Sy,Cn,
   L,Px,Py:Double;
 Take:Boolean;
Begin
 FindWrists:=0;
 N:=Int64(S.W)*S.H;
 B:=PByte(AllocBytes(N));
 For P:=0 to N-1 do If S.Cat[cArms][P]>=128 Then B[P]:=255;
 Lab:=PIntArr(AllocBytes(N*4));
 NC:=Components(B,S.W,S.H,Lab,Areas);
 Cnt:=0;
 For I:=1 to NC do Begin
  If(Areas[I]<N div 7000)or(Cnt>High(Wr))Then Continue;
  { axe principal }
  Mx:=0;My:=0;
  For Y:=0 to S.H-1 do For X:=0 to S.W-1 do If Lab[Int64(Y)*S.W+X]=I Then
    Begin Mx:=Mx+X;My:=My+Y;End;
  Mx:=Mx/Areas[I];My:=My/Areas[I];
  Sxx:=0;Sxy:=0;Syy:=0;
  For Y:=0 to S.H-1 do For X:=0 to S.W-1 do If Lab[Int64(Y)*S.W+X]=I Then Begin
   Sxx:=Sxx+(X-Mx)*(X-Mx);Sxy:=Sxy+(X-Mx)*(Y-My);Syy:=Syy+(Y-My)*(Y-My);
  End;
  Th:=0.5*ATan2F(2*Sxy,Sxx-Syy);
  Ax:=Cos(Th);Ay:=Sin(Th);
  If Ay<0 Then Begin Ax:=-Ax;Ay:=-Ay;End;     { vers le bas : cote main }
  Pmin:=1.0e9;Pmax:=-1.0e9;
  For Y:=0 to S.H-1 do For X:=0 to S.W-1 do If Lab[Int64(Y)*S.W+X]=I Then Begin
   Pj:=(X-Mx)*Ax+(Y-My)*Ay;
   If Pj<Pmin Then Pmin:=Pj;
   If Pj>Pmax Then Pmax:=Pj;
  End;
  L:=Pmax-Pmin;
  If L<12 Then Continue;
  Pw:=Pmax-0.22*L;
  { largeur et centre du poignet }
  Umin:=1.0e9;Umax:=-1.0e9;Sx:=0;Sy:=0;Cn:=0;
  For Y:=0 to S.H-1 do For X:=0 to S.W-1 do If Lab[Int64(Y)*S.W+X]=I Then Begin
   Pj:=(X-Mx)*Ax+(Y-My)*Ay;
   If Abs(Pj-Pw)<=1.6 Then Begin
    Uc:=-(X-Mx)*Ay+(Y-My)*Ax;
    If Uc<Umin Then Umin:=Uc;
    If Uc>Umax Then Umax:=Uc;
    Sx:=Sx+X;Sy:=Sy+Y;Cn:=Cn+1;
   End;
  End;
  If(Cn<2)or(Umax-Umin<5)Then Continue;
  Wr[Cnt].X:=Sx/Cn+0.5;Wr[Cnt].Y:=Sy/Cn+0.5;
  Wr[Cnt].Ax:=Ax;Wr[Cnt].Ay:=Ay;Wr[Cnt].W:=Umax-Umin+1;
  Inc(Cnt);
 End;
 FreeMem(B);FreeMem(Lab);
 FindWrists:=Cnt;
End;

{ bracelet ou bracelet de montre autour d'un poignet }
Procedure DrawBand(Var S:TScene;Const Wr:TWrist;Thick:Single;
  Colr:LongWord;Metallic,Diamond:Boolean;Prot:PSingle);
Var
 X,Y,X0,X1,Y0,Y1,I:LongInt;
 Dx,Dy,V,U,Vc,Hw,Hl,D,Cov,Sh,Mr,Mg,Mb,Gc:Single;
Begin
 Hw:=0.60*Wr.W;Hl:=Thick*Wr.W/2;
 X0:=Trunc(Wr.X-Wr.W*1.6);X1:=Trunc(Wr.X+Wr.W*1.6);Y0:=Trunc(Wr.Y-Wr.W*1.6);
   Y1:=Trunc(Wr.Y+Wr.W*1.6);
 Mr:=(Colr shr 16)and $FF;Mg:=(Colr shr 8)and $FF;Mb:=Colr and $FF;
 For Y:=Y0 to Y1 do
  For X:=X0 to X1 do Begin
   Dx:=X+0.5-Wr.X;Dy:=Y+0.5-Wr.Y;
   V:=Dx*Wr.Ax+Dy*Wr.Ay;
   U:=-Dx*Wr.Ay+Dy*Wr.Ax;
   Vc:=V-0.10*Wr.W*Sqr(U/Hw);
   D:=RoundRectD(U,Vc,0,0,Hw,Hl,Hl*0.9);
   Cov:=CoverD(D);
   If Cov>0 Then Begin
    If Metallic Then Sh:=MetalV(Clamp(0.5+Vc/(2*Hl),0,1))*(1-0.25*Sqr(U/Hw))
    Else Sh:=0.7+0.3*Sin(Pi*Clamp(0.5+Vc/(2*Hl),0,1))-0.15*Sqr(U/Hw);
    PutJewel(S,X,Y,Cov,Mr*Sh,Mg*Sh,Mb*Sh,Prot);
   End;
  End;
 If Diamond Then
  For I:=-2 to 2 do Begin
   Gc:=I*0.22*Wr.W;
   DrawGem(S,Wr.X-Gc*Wr.Ay+(0.10*Wr.W*Sqr(Gc/Hw))*Wr.Ax,Wr.Y+Gc*Wr.Ax+
     (0.10*Wr.W*Sqr(Gc/Hw))*Wr.Ay,0.075*Wr.W,Colr,RgbOf(232,242,255),Prot);
  End;
End;

Procedure DrawWatch(Var S:TScene;Const Wr:TWrist;Const E:TEdit;
  Metal:LongWord;Prot:PSingle);
Var
 X,Y,X0,X1,Y0,Y1:LongInt;
 Dx,Dy,V,U,Cov,Cu,Cv,R,G,B,Rr,Ang,Hh,Mm,D1,D2,Ln:Single;
 BandC:LongWord;
 Hw,Hh2:Single;
Begin
 If E.HasDst Then BandC:=E.DstRGB Else BandC:=RgbOf(28,28,32);
 DrawBand(S,Wr,0.50,BandC,False,False,Prot);
 X0:=Trunc(Wr.X-Wr.W);X1:=Trunc(Wr.X+Wr.W);Y0:=Trunc(Wr.Y-Wr.W);
   Y1:=Trunc(Wr.Y+Wr.W);
 For Y:=Y0 to Y1 do
  For X:=X0 to X1 do Begin
   Dx:=X+0.5-Wr.X;Dy:=Y+0.5-Wr.Y;
   V:=Dx*Wr.Ax+Dy*Wr.Ay;
   U:=-Dx*Wr.Ay+Dy*Wr.Ax;
   If E.Apple Then Begin
    { boitier carre arrondi, ecran noir, anneaux d'activite, couronne }
    Hw:=0.40*Wr.W;Hh2:=0.46*Wr.W;
    Cov:=CoverD(RoundRectD(U,V,0,0,Hw,Hh2,0.17*Wr.W));
    If Cov>0 Then Begin
     R:=185;G:=186;B:=192;
     Rr:=MetalV(Clamp(0.5+V/(2*Hh2),0,1));R:=R*Rr;G:=G*Rr;B:=B*Rr;
     PutJewel(S,X,Y,Cov,R,G,B,Prot);
    End;
    Cov:=CoverD(RoundRectD(U,V,0,0,Hw*0.88,Hh2*0.88,0.14*Wr.W));
    If Cov>0 Then Begin
     R:=6;G:=6;B:=9;
     Rr:=Sqrt(U*U+V*V)/Wr.W;
     { trois anneaux concentriques }
     Ang:=ATan2F(V,U);
     If(Abs(Rr-0.24)<0.032)and(Ang>-2.2)Then Begin R:=255;G:=45;B:=85;End;
     If(Abs(Rr-0.17)<0.032)and(Ang>-1.5)Then Begin R:=165;G:=255;B:=0;End;
     If(Abs(Rr-0.10)<0.032)and(Ang>-0.8)Then Begin R:=0;G:=225;B:=255;End;
     { reflet de la vitre }
     Rr:=Clamp((U+V)/(2*Wr.W)+0.1,-0.5,0.5);
     If Rr>0 Then Begin R:=R+30*Rr;G:=G+30*Rr;B:=B+34*Rr;End;
     PutJewel(S,X,Y,Cov,R,G,B,Prot);
    End;
    Cov:=CoverD(RoundRectD(U-Hw-0.03*Wr.W,V+0.12*Wr.W,0,0,0.05*Wr.W,
      0.12*Wr.W,0.03*Wr.W));
    If Cov>0 Then PutJewel(S,X,Y,Cov,175,176,182,Prot);
   End
    Else Begin
     { montre ronde : boitier metal, cadran clair, aiguilles }
     Rr:=Sqrt(U*U+V*V);
     Cov:=CoverD(Rr-0.43*Wr.W);
     If Cov>0 Then Begin
      Cu:=((Metal shr 16)and $FF)*MetalV(Clamp(0.5+V/(0.86*Wr.W),0,1));
      Cv:=((Metal shr 8)and $FF)*MetalV(Clamp(0.5+V/(0.86*Wr.W),0,1));
      R:=((Metal and $FF))*MetalV(Clamp(0.5+V/(0.86*Wr.W),0,1));
      PutJewel(S,X,Y,Cov,Cu,Cv,R,Prot);
     End;
     Cov:=CoverD(Rr-0.36*Wr.W);
     If Cov>0 Then Begin
      R:=242;G:=240;B:=232;
      Ang:=ATan2F(V,U);
      Mm:=Abs(Sin(Ang*6));
      If(Rr>0.30*Wr.W)and(Mm>0.97)Then Begin R:=40;G:=40;B:=44;End;
      { aiguilles : 10 h 10 }
      D1:=Abs(-U*Cos(-1.0)+V*Sin(-1.0));Ln:=U*Sin(-1.0)*(-1)+V*Cos(-1.0);
      If(D1<0.012*Wr.W+0.4)and(U*Cos(-1.0)+V*Sin(-1.0)>0)and(Rr<0.22*Wr.W)
        Then Begin R:=30;G:=30;B:=34;End;
      D2:=Abs(-U*Cos(-2.2)+V*Sin(-2.2));
      If(D2<0.010*Wr.W+0.4)and(U*Cos(-2.2)+V*Sin(-2.2)>0)and(Rr<0.30*Wr.W)
        Then Begin R:=30;G:=30;B:=34;End;
      If Rr<0.025*Wr.W Then Begin R:=30;G:=30;B:=34;End;
      PutJewel(S,X,Y,Cov,R,G,B,Prot);
     End;
    End;
  End;
End;

{ ajoute les bijoux demandes ; renvoie faux si rien n'a pu etre pose }
Function AddJewelry(Var S:TScene;Const E:TEdit;Var Msg:AnsiString):Boolean;
Var
 H:THeadInfo;
 Metal,Tint:LongWord;
 Prot,Fm,Hm,Am:PSingle;
 N:Int64;
 Wr:Array[0..3]of TWrist;
 NW,I,WatchIdx:LongInt;
 Done:Boolean;
 Note:AnsiString;
 B:PByte;
 K:LongInt;
Begin
 AddJewelry:=False;
 Msg:='';Note:='';
 Done:=False;
 N:=Int64(S.W)*S.H;
 If E.HasDst Then Metal:=E.DstRGB
 Else If E.Diamond Then Metal:=RgbOf(196,196,205)
 Else Metal:=RgbOf(212,175,55);
 Tint:=RgbOf(232,242,255);
 Fm:=AllocF(N);Hm:=AllocF(N);Prot:=AllocF(N);
 CatMask(S,msFace,Fm);CatMask(S,msHair,Hm);
 For K:=0 to N-1 do Prot[K]:=FMax(Fm[K],Hm[K]);
 If(E.Jewel and(jwNecklace or jwEarrings))<>0 Then Begin
  If HeadInfo(S,H)Then Begin
   If(E.Jewel and jwNecklace)<>0 Then Begin DrawNecklace(S,H,Metal,Tint,
     E.Diamond,Prot);Done:=True;End;
   If(E.Jewel and jwEarrings)<>0 Then Begin DrawEarrings(S,H,Metal,E.Diamond,
     Fm);Done:=True;End;
  End
   Else Note:=
     'aucun visage d'#130'tect'#130' : collier et boucles d''oreilles non '+
     'ajout'#130's';
 End;
 If(E.Jewel and(jwBracelet or jwWatch))<>0 Then Begin
  NW:=FindWrists(S,Wr);
  If NW=0 Then Begin
   If Note<>'' Then Note:=Note+' ; ';
   Note:=Note+'aucun poignet visible : bracelet et montre non ajout'#130's';
  End
   Else Begin
    { masque des bras legerement dilate : le bijou ne deborde pas sur le fond }
    B:=PByte(AllocBytes(N));
    For K:=0 to N-1 do If S.Cat[cArms][K]>=64 Then B[K]:=255;
    MorphMask(B,S.W,S.H,2,False);
    Am:=AllocF(N);
    For K:=0 to N-1 do Am[K]:=1-B[K]/255.0;
    FreeMem(B);
    { montre sur le poignet le plus a droite de l'image (poignet gauche de la
      personne) }
    WatchIdx:=0;
    For I:=1 to NW-1 do If Wr[I].X>Wr[WatchIdx].X Then WatchIdx:=I;
    For I:=0 to NW-1 do Begin
     If((E.Jewel and jwWatch)<>0)and(I=WatchIdx)Then Begin DrawWatch(S,Wr[I],
       E,Metal,Am);Done:=True;End
     Else If(E.Jewel and jwBracelet)<>0 Then Begin DrawBand(S,Wr[I],0.28,
       Metal,True,E.Diamond,Am);Done:=True;End;
    End;
    FreeMem(Am);
   End;
 End;
 If(E.Jewel and jwRing)<>0 Then Begin
  If Note<>'' Then Note:=Note+' ; ';
  Note:=Note+'les bagues ne sont pas prises en charge (doigts trop petits)';
 End;
 FreeMem(Fm);FreeMem(Hm);FreeMem(Prot);
 If Note<>'' Then Begin
  If Done Then Warn(Note) Else Msg:=Note;
 End;
 AddJewelry:=Done;
 If Done Then Info('  bijoux ajout'#130's');
End;
{ ------------------------------------------------------------------ }
{ ? Plus reel ? sur une vraie photo : amelioration legere            }
{ ------------------------------------------------------------------ }

{ une photo utilise beaucoup de couleurs differentes ; un dessin, tres peu }
Function LooksLikePhoto(Const S:TScene):Boolean;
Var
 Seen:PByte;
 N,K,Step,Cnt:Int64;
 Idx:LongInt;
Begin
 N:=Int64(S.W)*S.H;
 Seen:=PByte(AllocBytes(32768));
 Step:=N div 400000;
 If Step<1 Then Step:=1;
 Cnt:=0;
 K:=0;
 While K<N do Begin
  Idx:=(ClampI(Trunc(S.Pix[K*3]),0,255)shr 3)shl 10 or
   ((ClampI(Trunc(S.Pix[K*3+1]),0,255)shr 3)shl 5)or
   (ClampI(Trunc(S.Pix[K*3+2]),0,255)shr 3);
  If Seen[Idx]=0 Then Begin Seen[Idx]:=1;Inc(Cnt);End;
  Inc(K,Step);
 End;
 FreeMem(Seen);
 LooksLikePhoto:=Cnt>=2500;
End;

{ nettete locale, saturation, grain fin et vignettage leger }
Procedure PhotoEnhance(Var S:TScene);
Var
 N:int64;K:LongInt;
 P:Array[0..2]of PSingle;
 X,Y,C,R:LongInt;
 V,L,Vig,Nz:Single;
Begin
 N:=Int64(S.W)*S.H;
 R:=IMax(1,IMax(S.W,S.H)div 500);
 For C:=0 to 2 do Begin
  P[C]:=AllocF(N);
  For K:=0 to N-1 do P[C][K]:=S.Pix[K*3+C];
  BoxBlur(P[C],P[C],S.W,S.H,R);
 End;
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   L:=Luma(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2]);
   Vig:=1-0.10*Sqr(Sqrt(Sqr(X/S.W-0.5)+Sqr(Y/S.H-0.5))*1.4);
   Nz:=RngGauss*1.6;
   For C:=0 to 2 do Begin
    V:=S.Pix[K*3+C]+(S.Pix[K*3+C]-P[C][K])*0.55;
    V:=L+(V-L)*1.07;
    S.Pix[K*3+C]:=(V*Vig)+Nz;
   End;
  End;
 For C:=0 to 2 do FreeMem(P[C]);
End;


{ ------------------------------------------------------------------ }
{ Styles d'image : photo -> BD / dessin anime / croquis,              }
{ et dessin -> rendu ? realiste ? approximatif                         }
{ ------------------------------------------------------------------ }

{ lisse l'image en gardant les contours (filtre guide applique a chaque canal) }
Procedure EdgeSmooth(Pix:PSingle;W,H,Rad:LongInt;Eps:Single);
Var
 G:TGuide;
 P,Q:PSingle;
 N:int64;K:LongInt;
 C:LongInt;
Begin
 N:=Int64(W)*H;
 GuideInit(G,Pix,W,H,Rad,Eps);
 P:=AllocF(N);Q:=AllocF(N);
 For C:=0 to 2 do Begin
  For K:=0 to N-1 do P[K]:=Pix[K*3+C]/255.0;
  GuideApply(G,P,Q);
  For K:=0 to N-1 do Pix[K*3+C]:=Q[K]*255.0;
 End;
 GuideFree(G);
 FreeMem(P);FreeMem(Q);
End;

{ categorie dominante de chaque pixel }
Procedure DominantMap(Const S:TScene;D:PByte);
Var
 K:LongInt;
 C,Best,Bv:LongInt;
Begin
 For K:=0 to Int64(S.W)*S.H-1 do Begin
  Best:=0;Bv:=-1;
  For C:=0 to NumCat-1 do If S.Cat[C][K]>Bv Then Begin Bv:=S.Cat[C][K];
    Best:=C;End;
  D[K]:=Best;
 End;
End;

{ contours : gradient de luminosite et frontieres entre categories ; renvoie un
  plan 0..1 }
Procedure InkLines(Const S:TScene;Lines:PSingle;Strong:Single;Width:LongInt);
Var
 N:int64;K:LongInt;
 X,Y:LongInt;
 Yl:PSingle;
 Dom,Bd:PByte;
 Gx,Gy,Gm,T0,T1:Single;
Begin
 N:=Int64(S.W)*S.H;
 Yl:=AllocF(N);
 For K:=0 to N-1 do Yl[K]:=Luma(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2])/255.0;
 BlurPlane(Yl,S.W,S.H,1.1);
 T0:=0.05/Strong;T1:=0.20/Strong;
 For Y:=1 to S.H-2 do
  For X:=1 to S.W-2 do Begin
   K:=Int64(Y)*S.W+X;
   Gx:=(Yl[K+1]-Yl[K-1])*2+(Yl[K+1-S.W]-Yl[K-1-S.W])+(Yl[K+1+S.W]-Yl[K-1+S.W]);
   Gy:=(Yl[K+S.W]-Yl[K-S.W])*2+(Yl[K+S.W-1]-Yl[K-S.W-1])+(Yl[K+S.W+1]-Yl[K-S.W+
     1]);
   Gm:=Sqrt(Gx*Gx+Gy*Gy)/4.0;
   If S.Cat[cFace][K]>=128 Then Lines[K]:=0.75*SmoothStep(T0*1.0,T1*1.25,Gm)
   Else Lines[K]:=SmoothStep(T0,T1,Gm);
  End;
 FreeMem(Yl);
 { frontieres entre categories }
 Dom:=PByte(AllocBytes(N));Bd:=PByte(AllocBytes(N));
 DominantMap(S,Dom);
 For Y:=0 to S.H-2 do
  For X:=0 to S.W-2 do Begin
   K:=Int64(Y)*S.W+X;
   If(Dom[K]<>Dom[K+1])or(Dom[K]<>Dom[K+S.W])Then Bd[K]:=255;
  End;
 If Width>1 Then MorphMask(Bd,S.W,S.H,Width-1,False);
 For K:=0 to N-1 do If Bd[K]<>0 Then Lines[K]:=1;
 FreeMem(Dom);FreeMem(Bd);
 BlurPlane(Lines,S.W,S.H,0.9);
 For K:=0 to N-1 do Begin
  Lines[K]:=Lines[K]*1.7;
  If Lines[K]>1 Then Lines[K]:=1;
 End;
End;

{ BD (Comic=True : encre epaisse et trames) ou dessin anime }
Procedure StyleCartoon(Var S:TScene;Comic:Boolean);
Var
 N:int64;K:LongInt;
 X,Y:LongInt;
 Md,Lv,Wd:LongInt;
 L,A,B,Step,T,F,Lq,R,G,Bl,Ln,Pitch,Rd,Dx,Dy,U,V,Dist:Single;
 Lines,FaceKeep,Fm:PSingle;
 C:LongInt;
Begin
 ColorInit;
 N:=Int64(S.W)*S.H;
 Md:=IMin(S.W,S.H);
 Lines:=AllocF(N);
 { contours calcules sur l'image d'origine (legerement lissee) }
 If Comic Then Begin Wd:=IMax(2,Md div 380);InkLines(S,Lines,0.8,Wd);End
 Else Begin Wd:=IMax(1,Md div 600);InkLines(S,Lines,1.15,Wd);End;
 { aplats : lissage fort puis quantification de la luminosite }
 FaceKeep:=AllocF(N*3);
 Move(S.Pix^,FaceKeep^,N*12);
 EdgeSmooth(FaceKeep,S.W,S.H,IMax(2,Md div 300),0.004);
 EdgeSmooth(S.Pix,S.W,S.H,IMax(3,Md div 110),0.03);
 EdgeSmooth(S.Pix,S.W,S.H,IMax(2,Md div 220),0.015);
 Fm:=AllocF(N);
 CatMask(S,msFace,Fm);
 BlurPlane(Fm,S.W,S.H,2.0);
 For K:=0 to N-1 do If Fm[K]>0.01 Then
  For C:=0 to 2 do S.Pix[K*3+C]:=S.Pix[K*3+C]*(1-Fm[K])+FaceKeep[K*3+C]*Fm[K];
 FreeMem(FaceKeep);FreeMem(Fm);
 If Comic Then Lv:=5 Else Lv:=7;
 Step:=100.0/Lv;
 Pitch:=FMax(4,Md/170.0);
 For K:=0 to N-1 do Begin
  RgbToLab(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2],L,A,B);
  T:=L/Step;
  F:=T-Trunc(T);
  Lq:=(Trunc(T)+SmoothStep(0.40,0.60,F))*Step;
  If Comic Then Lq:=Lq*0.96;
  A:=A*1.22;B:=B*1.22;
  LabToRgb(Lq,A,B,R,G,Bl);
  { trame de points dans les ombres (BD) }
  If Comic and(L<34)Then Begin
   Y:=K div S.W;X:=K mod S.W;
   U:=(X+Y)/1.4142;V:=(X-Y)/1.4142;
   Dx:=U-Trunc(U/Pitch)*Pitch-Pitch/2;
   Dy:=V-Trunc(V/Pitch)*Pitch-Pitch/2;
   Dist:=Sqrt(Dx*Dx+Dy*Dy);
   Rd:=0.5*Pitch*Sqrt(Clamp((34-L)/34.0,0,1));
   If Dist<Rd Then Begin R:=R*0.62;G:=G*0.62;Bl:=Bl*0.62;End;
  End;
  Ln:=Lines[K];
  S.Pix[K*3]:=R*(1-Ln)+18*Ln;
  S.Pix[K*3+1]:=G*(1-Ln)+16*Ln;
  S.Pix[K*3+2]:=Bl*(1-Ln)+22*Ln;
 End;
 FreeMem(Lines);
End;

{ croquis au crayon }
Procedure StyleSketch(Var S:TScene);
Var
 N:int64;K:LongInt;
 Gray,Inv:PSingle;
 Md:LongInt;
 V,Pp:Single;
Begin
 N:=Int64(S.W)*S.H;
 Md:=IMin(S.W,S.H);
 Gray:=AllocF(N);Inv:=AllocF(N);
 For K:=0 to N-1 do Begin
  Gray[K]:=Luma(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2]);
  Inv[K]:=255-Gray[K];
 End;
 BlurPlane(Inv,S.W,S.H,FMax(3,Md/90.0));
 For K:=0 to N-1 do Begin
  V:=Gray[K]*255.0/(255.0-Inv[K]+4.0);
  If V>255 Then V:=255;
  V:=255*FPow(V/255.0,1.7);
  { grain du papier }
  Pp:=VNoise((K mod S.W)*0.8,(K div S.W)*0.8)*10-5+RngGauss*1.3;
  V:=Clamp(V*0.97+Pp+5,0,255);
  S.Pix[K*3]:=V;S.Pix[K*3+1]:=V*0.995;S.Pix[K*3+2]:=V*0.97;
 End;
 FreeMem(Gray);FreeMem(Inv);
End;

{ dessin -> rendu realiste (approximation : suppression de l'encre, lumiere,
  textures de peau, de tissu et de cheveux, grain) ; ce n'est pas une photo }
Procedure StyleReal(Var S:TScene);
Var
 N:int64;K:LongInt;
 X,Y,C,R0:LongInt;
 Yl,Dk,Op,Known:PSingle;
 Bd,Bo:PByte;
 Md:LongInt;
 L,A,B,Gr,Sk,Fb,Hr,Bg,Light,Vig,Tex,Nz,Dx,Dy,Wv:Single;
 Gm,Mn:Single;
Begin
 ColorInit;
 N:=Int64(S.W)*S.H;
 Md:=IMin(S.W,S.H);
 { 1. encre : pixels sombres et fins, retires puis remplis par propagation }
 Yl:=AllocF(N);Known:=AllocF(N);
 Bd:=PByte(AllocBytes(N));Bo:=PByte(AllocBytes(N));
 For K:=0 to N-1 do Begin
  Yl[K]:=Luma(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2]);
  If Yl[K]<75 Then Begin Bd[K]:=255;Bo[K]:=255;End;
 End;
 R0:=IMax(1,Md div 300);
 MorphMask(Bo,S.W,S.H,R0,True);
 MorphMask(Bo,S.W,S.H,R0,False);
 For K:=0 to N-1 do Begin
  If(Bd[K]<>0)and(Bo[K]=0)Then Bd[K]:=255 Else Bd[K]:=0;
 End;
 MorphMask(Bd,S.W,S.H,1,False);
 For K:=0 to N-1 do If Bd[K]=0 Then Known[K]:=1;
 PushPullFill(S.Pix,Known,S.W,S.H);
 FreeMem(Yl);FreeMem(Known);FreeMem(Bd);FreeMem(Bo);
 { 2. aplats -> degrades doux }
 EdgeSmooth(S.Pix,S.W,S.H,IMax(2,Md div 160),0.004);
 { 3. lumiere, textures par region, grain }
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   Sk:=(S.Cat[cFace][K]+S.Cat[cArms][K]+S.Cat[cLegs][K]+S.Cat[cSkin][K])/255.0;
   Hr:=S.Cat[cHair][K]/255.0;
   Bg:=S.Cat[cBg][K]/255.0;
   Fb:=1-Sk-Hr-Bg;
   If Fb<0 Then Fb:=0;
   RgbToLab(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2],L,A,B);
   { eclairage doux venant du haut a gauche et vignettage }
   Dx:=X/S.W-0.35;Dy:=Y/S.H-0.25;
   Light:=1.06-0.16*Sqrt(Dx*Dx+Dy*Dy);
   Vig:=1-0.20*Sqr(Sqrt(Sqr(X/S.W-0.5)+Sqr(Y/S.H-0.5))*1.4);
   L:=L*Light*Vig;
   { desaturation naturelle }
   A:=A*0.84;B:=B*0.84;
   { peau : pores, rougeurs, leger eclat }
   If Sk>0.02 Then Begin
    Nz:=VNoise(X*1.15,Y*1.15)-0.5;
    L:=L+Sk*(Nz*7.0+(VNoise(X/(0.02*S.W+1),Y/(0.02*S.W+1))-0.5)*3.0);
    A:=A+Sk*(VNoise(X/(0.035*S.W+1),Y/(0.035*S.W+1))-0.5)*5.0;
   End;
   { cheveux : meches fines }
   If Hr>0.02 Then Begin
    Nz:=VNoise(X*0.9,Y*0.06)-0.5;
    L:=L+Hr*(Nz*22.0+(VNoise(X*0.3,Y*0.02)-0.5)*10.0);
   End;
   { tissu : trame }
   If Fb>0.02 Then Begin
    Wv:=Sin(X*1.7)*Sin(Y*1.7);
    L:=L+Fb*(Wv*2.2+(VNoise(X*0.45,Y*0.45)-0.5)*5.0);
   End;
   { fond : flou de profondeur simule par un leger bruit }
   If Bg>0.02 Then L:=L+Bg*(VNoise(X*0.05,Y*0.05)-0.5)*5.0;
   L:=L+RngGauss*1.7;
   If L<0 Then L:=0 Else If L>100 Then L:=100;
   LabToRgb(L,A,B,Gm,Mn,Light);
   S.Pix[K*3]:=Gm;S.Pix[K*3+1]:=Mn;S.Pix[K*3+2]:=Light;
  End;
 { 4. adoucit legerement les aretes vectorielles }
 EdgeSmooth(S.Pix,S.W,S.H,1,0.002);
End;

{ applique un changement de style sur toute l'image }
Function ApplyStyle(Var S:TScene;Style:LongInt;Var Msg:AnsiString):Boolean;
Begin
 ApplyStyle:=True;
 Msg:='';
 Case Style of
  stComic:Begin StyleCartoon(S,True);Info('  style BD appliqu'#130);End;
  stCartoon:Begin StyleCartoon(S,False);
    Info('  style dessin anim'#130' appliqu'#130);End;
  stSketch:Begin StyleSketch(S);Info('  style croquis appliqu'#130);End;
  stReal:If LooksLikePhoto(S)Then Begin
    PhotoEnhance(S);
    Info('  l''image est d'#130'j'#133' une photo : r'#130'alisme renforc'#130+
      ' l'#130'g'#138'rement (nettet'#130', saturation, grain, vignettage)');
   End
   Else Begin
    StyleReal(S);
    Info('  rendu r'#130'aliste approximatif appliqu'#130' (ce n''est pas une '+
      'photo : un vrai passage dessin -> photo demande un mod'#138'le g'#130+
      'n'#130'ratif)');
   End;
  Else Begin Msg:='style inconnu';ApplyStyle:=False;End;
 End;
End;

{ ------------------------------------------------------------------ }
{ Visage et posture : couleur des yeux, sourire, bras le long du corps }
{ ------------------------------------------------------------------ }

{ ---- couleur des yeux ---- }

{ cherche l'iris d'un oeil dans une fenetre : disque sombre entoure d'un anneau
  plus clair }
Function FindIris(Const S:TScene;Yl:PSingle;Ex,Ey,Wx,Wy,R:Single;Var Cx,Cy,
  Score:Single):Boolean;
Var
 X,Y,Dx,Dy,Ri:LongInt;
 Sd,Sr,Dd,Rr:Double;
 Nd,Nr:LongInt;
 D2:Single;
 Best:Single;
Begin
 FindIris:=False;
 Best:=-1;
 Ri:=Trunc(R*1.95)+1;
 For Y:=Trunc(Ey-Wy)to Trunc(Ey+Wy)do
  For X:=Trunc(Ex-Wx)to Trunc(Ex+Wx)do Begin
   Sd:=0;Sr:=0;Nd:=0;Nr:=0;
   For Dy:=-Ri to Ri do
    For Dx:=-Ri to Ri do Begin
     If(X+Dx<0)or(X+Dx>=S.W)or(Y+Dy<0)or(Y+Dy>=S.H)Then Continue;
     D2:=Sqrt(Dx*Dx+Dy*Dy);
     If D2<=R*0.9 Then Begin Sd:=Sd+Yl[Int64(Y+Dy)*S.W+X+Dx];Inc(Nd);End
     Else If(D2>=R*1.3)and(D2<=R*1.95)Then Begin Sr:=Sr+Yl[Int64(Y+Dy)*S.W+X+
       Dx];Inc(Nr);End;
    End;
   If(Nd<4)or(Nr<8)Then Continue;
   Dd:=Sd/Nd;Rr:=Sr/Nr;
   If Rr-Dd>Best Then Begin Best:=Rr-Dd;Cx:=X+0.5;Cy:=Y+0.5;End;
  End;
 Score:=Best;
 FindIris:=Best>0;
End;

Function ApplyEyes(Var S:TScene;Const E:TEdit;Var Msg:AnsiString):Boolean;
Var
 H:THeadInfo;
 N:int64;K:LongInt;
 Yl,Al:PSingle;
 Side,X,Y,Found:LongInt;
 Ex,Ey,R,Cx,Cy,Sc,Lskin,Dd,W1,Lcur,Sum,Cnt:Single;
 SkinSum:Double;
 SkinCnt:Int64;
 P:TRecolor;
 Fm:PSingle;
 L,A,B:Single;
Begin
 ApplyEyes:=False;
 Msg:='';
 If not HeadInfo(S,H)Then Begin Msg:=
   'aucun visage d'#130'tect'#130' : impossible de changer la couleur des '+
   'yeux';Exit;End;
 If H.Fw<40 Then Begin Msg:=
   'le visage est trop petit pour modifier les yeux (40 pixels de large '+
   'minimum)';Exit;End;
 If(not E.HasDst)Then Begin
   Msg:='indiquez la couleur des yeux (par exemple : yeux verts)';Exit;End;
 ColorInit;
 N:=Int64(S.W)*S.H;
 Yl:=AllocF(N);Al:=AllocF(N);Fm:=AllocF(N);
 CatMask(S,msFace,Fm);
 SkinSum:=0;SkinCnt:=0;
 For K:=0 to N-1 do Begin
  Yl[K]:=Luma(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2]);
  If Fm[K]>=0.9 Then Begin SkinSum:=SkinSum+Yl[K];Inc(SkinCnt);End;
 End;
 If SkinCnt=0 Then Lskin:=150 Else Lskin:=SkinSum/SkinCnt;
 R:=FMax(2.5,0.046*H.Fw);
 Found:=0;
 For Side:=-1 to 1 do Begin
  If Side=0 Then Continue;
  Ex:=H.Cx+Side*0.225*H.Fw;
  Ey:=H.Fy0+0.42*H.Fh;
  If FindIris(S,Yl,Ex,Ey,0.12*H.Fw,0.17*H.Fh,R,Cx,Cy,Sc)and(Sc>=9)Then Begin
   Inc(Found);
   { poids : anneau de l'iris sans la pupille, sans paupiere ni reflet }
   For Y:=Trunc(Cy-R*1.2)to Trunc(Cy+R*1.2)do
    For X:=Trunc(Cx-R*1.2)to Trunc(Cx+R*1.2)do Begin
     If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Continue;
     Dd:=Sqrt(Sqr(X+0.5-Cx)+Sqr(Y+0.5-Cy));
     W1:=SmoothStep(0.26*R,0.40*R,Dd)*(1-SmoothStep(0.92*R,1.08*R,Dd));
     K:=Int64(Y)*S.W+X;
     { pixels clairs : paupiere, sclerotique ou reflet }
     W1:=W1*(1-SmoothStep(0.78*Lskin,1.0*Lskin,Yl[K]));
     If W1>Al[K]Then Al[K]:=W1;
    End;
  End;
 End;
 If Found=0 Then Begin
  Msg:='yeux non d'#130'tect'#130's (photo trop petite, trop sombre ou yeux '+
    'ferm'#130's)';
  FreeMem(Yl);FreeMem(Al);FreeMem(Fm);Exit;
 End;
 BuildRecolor(E,P,0,0,1,1,False);
 P.Pattern:=pkNone;P.LGain:=1;P.CGain:=0.8;
 ApplyEyes:=RecolorRegion(S.Pix,S.W,S.H,Al,P);
 If not ApplyEyes Then
   Msg:='les yeux sont trop petits pour '#136'tre recolor'#130's'
 Else Info('  yeux recolor'#130's ('+IStr(Found)+' sur 2 d'#130'tect'#130's)');
 FreeMem(Yl);FreeMem(Al);FreeMem(Fm);
End;

{ ---- sourire : les coins de la bouche remontent ---- }

Function MouthWarp(Var S:TScene;AmpF:Single;Close:Boolean;Const
  What:AnsiString;Var Msg:AnsiString):Boolean;
Var
 H:THeadInfo;
 N,K:Int64;
 Orig:PSingle;
 X,Y,X0,X1,Y0,Y1,Cnt,Rx0,Rx1:LongInt;
 L,A,B,SumA,SumA2,Mean,Sd,Thr,Mx,My,Sx,Sy,Cn,Hw,Hy,U,V,D,Sy2,Amp:Single;
 Reds:Array of Single;
 Ex0,Ex1:Single;
 Lr,Lg,Lb,Lw,Cr,Wt:Single;
 Fm:PSingle;
 C:LongInt;
 Px:Array[0..2]of Single;
Begin
 MouthWarp:=False;
 Msg:='';
 If not HeadInfo(S,H)Then Begin Msg:=
   'aucun visage d'#130'tect'#130' : impossible de modifier l''expression';
   Exit;End;
 If H.Fw<40 Then Begin Msg:=
   'le visage est trop petit pour modifier l''expression (40 pixels de '+
   'large minimum)';Exit;End;
 ColorInit;
 N:=Int64(S.W)*S.H;
 Fm:=AllocF(N);
 CatMask(S,msFace,Fm);
 { levres : pixels les plus rouges (a* de Lab) dans la zone attendue de la
   bouche }
 X0:=Trunc(H.Cx-0.32*H.Fw);X1:=Trunc(H.Cx+0.32*H.Fw);
 Y0:=Trunc(H.Fy0+0.60*H.Fh);Y1:=Trunc(H.Fy0+0.96*H.Fh);
 SumA:=0;SumA2:=0;Cnt:=0;
 For Y:=Y0 to Y1 do
  For X:=X0 to X1 do Begin
   If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Continue;
   K:=Int64(Y)*S.W+X;
   If Fm[K]<0.8 Then Continue;
   RgbToLab(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2],L,A,B);
   SumA:=SumA+A;SumA2:=SumA2+A*A;Inc(Cnt);
  End;
 If Cnt<30 Then Begin Msg:='bouche non d'#130'tect'#130'e';FreeMem(Fm);Exit;End;
 Mean:=SumA/Cnt;Sd:=Sqrt(FMax(0,SumA2/Cnt-Mean*Mean));
 Thr:=Mean+1.1*Sd;
 Sx:=0;Sy:=0;Cn:=0;Rx0:=S.W;Rx1:=-1;Lr:=0;Lg:=0;Lb:=0;
 For Y:=Y0 to Y1 do
  For X:=X0 to X1 do Begin
   If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Continue;
   K:=Int64(Y)*S.W+X;
   If Fm[K]<0.8 Then Continue;
   RgbToLab(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2],L,A,B);
   If A>=Thr Then Begin
    Sx:=Sx+X;Sy:=Sy+Y;Cn:=Cn+1;
    Lr:=Lr+S.Pix[K*3];Lg:=Lg+S.Pix[K*3+1];Lb:=Lb+S.Pix[K*3+2];
    If X<Rx0 Then Rx0:=X;
    If X>Rx1 Then Rx1:=X;
   End;
  End;
 If(Cn>=12)and(Rx1-Rx0>=0.15*H.Fw)Then Begin
  Mx:=Sx/Cn+0.5;My:=Sy/Cn+0.5;Hw:=(Rx1-Rx0+1)/2;
  Mx:=(Rx0+Rx1+1)/2;
 End
  Else Begin
   Mx:=H.Cx;My:=H.Fy0+0.78*H.Fh;Hw:=0.19*H.Fw;
   Detail('bouche estim'#130'e (l'#138'vres non distingu'#130'es)');
  End;
 If Hw<0.12*H.Fw Then Hw:=0.12*H.Fw;
 If Hw>0.28*H.Fw Then Hw:=0.28*H.Fw;
 Hy:=0.11*H.Fh;
 Amp:=AmpF*H.Fh;
 If Close Then Begin
  { bouche fermee : dents (clair, peu colore) repeintes de la couleur des
    levres, trait de fermeture }
  If Cn>=12 Then Begin Lr:=Lr/Cn;Lg:=Lg/Cn;Lb:=Lb/Cn;End
  Else Begin Lr:=175;Lg:=95;Lb:=95;End;
  Ex0:=0;Ex1:=0;
  For Y:=Trunc(My-0.13*H.Fh)to Trunc(My+0.09*H.Fh)do
   For X:=Trunc(Mx-1.25*Hw)to Trunc(Mx+1.25*Hw)do Begin
    If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Continue;
    K:=Int64(Y)*S.W+X;
    If Fm[K]<0.5 Then Continue;
    RgbToLab(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2],L,A,B);
    Cr:=Sqrt(A*A+B*B);
    Wt:=SmoothStep(40,58,L)*(1-SmoothStep(7,15,Cr));
    Wt:=FMax(Wt,1-SmoothStep(20,36,L));
    Wt:=Wt*(1-SmoothStep(1.0,1.25,Abs(X+0.5-Mx)/Hw));
    If Wt<=0.01 Then Continue;
    Ex0:=Ex0+Wt*(Y+0.5);Ex1:=Ex1+Wt;
    S.Pix[K*3]:=S.Pix[K*3]*(1-Wt)+Lr*0.96*Wt;
    S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-Wt)+Lg*0.96*Wt;
    S.Pix[K*3+2]:=S.Pix[K*3+2]*(1-Wt)+Lb*0.96*Wt;
   End;
  If Ex1>=20 Then My:=Ex0/Ex1;
  For Y:=Trunc(My-3)to Trunc(My+3)do
   For X:=Trunc(Mx-1.1*Hw)to Trunc(Mx+1.1*Hw)do Begin
    If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Continue;
    K:=Int64(Y)*S.W+X;
    If Fm[K]<0.5 Then Continue;
    Lw:=CoverD(Abs(Y+0.5-My)-FMax(0.6,0.012*H.Fh))*(1-SmoothStep(0.6,1.0,
      Abs(X+0.5-Mx)/(1.1*Hw)));
    If Lw<=0.01 Then Continue;
    S.Pix[K*3]:=S.Pix[K*3]*(1-Lw)+Lr*0.45*Lw;
    S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-Lw)+Lg*0.40*Lw;
    S.Pix[K*3+2]:=S.Pix[K*3+2]*(1-Lw)+Lb*0.42*Lw;
   End;
 End;
 { deplacement : le contenu des coins monte, le centre reste en place }
 Orig:=AllocF(N*3);
 Move(S.Pix^,Orig^,N*12);
 For Y:=Trunc(My-0.5*H.Fh)to Trunc(My+0.5*H.Fh)do
  For X:=Trunc(Mx-2.2*Hw)to Trunc(Mx+2.2*Hw)do Begin
   If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Continue;
   K:=Int64(Y)*S.W+X;
   If Fm[K]<0.5 Then Continue;
   U:=(X+0.5-Mx)/Hw;V:=(Y+0.5-My)/Hy;
   D:=Amp*U*U*Exp(-U*U/2.4)*Exp(-V*V/2.0);
   If Abs(D)<0.05 Then Continue;
   SampleBilinear(Orig,S.W,S.H,3,X+0.5,Y+0.5+D,@Px[0]);
   For C:=0 to 2 do S.Pix[K*3+C]:=Px[C];
  End;
 FreeMem(Orig);FreeMem(Fm);
 MouthWarp:=True;
 Info('  '+What);
End;

Function ApplySmile(Var S:TScene;Var Msg:AnsiString):Boolean;
Begin
 ApplySmile:=MouthWarp(S,0.065,False,'sourire ajout'#130,Msg);
End;

{ ---- bras le long du corps ---- }

Function ArmsDown(Var S:TScene;Var Msg:AnsiString):Boolean;
Var
 N:int64;K:LongInt;
 Tx0,Ty0,Tx1,Ty1,Side,X,Y,Done,Skipped,Ix,Iy,C,Mv,Tl,Tr:LongInt;
 Tp,Ppx,Ppy,Ext:Double;
 Cnt:Int64;
 Cx,Mx,My,Sxx,Sxy,Syy,Th,Ax,Ay,Pj,Pmin,Pmax,L,Hw,Uc,Pvx,Pvy,Delta,Cd,Sd,Rx,Ry,
   Sx,Sy,TorsoHalf:Double;
 Cap,Known:PSingle;
 Orig:PSingle;
 Mk,CapCat:PByte;
 Wc:Single;
 Px:Array[0..2]of Single;
Begin
 ArmsDown:=False;
 Msg:='';
 N:=Int64(S.W)*S.H;
 If not CatBBox(S,msTop or msDress,Tx0,Ty0,Tx1,Ty1)Then Begin
   Msg:='aucun haut d'#130'tect'#130' : impossible de situer le corps';Exit;End;
 Cx:=(Tx0+Tx1+1)/2;
 TorsoHalf:=(Tx1-Tx0+1)/2;
 { largeur du torse mesuree en bas (sous les manches) }
 Y:=Ty0+((Ty1-Ty0)*80)div 100;
 Tl:=S.W;Tr:=-1;
 For X:=0 to S.W-1 do If(S.Cat[cTop][Int64(Y)*S.W+X]+S.Cat[cDress][Int64(Y)
   *S.W+X])>=128 Then Begin
  If X<Tl Then Tl:=X;
  If X>Tr Then Tr:=X;
 End;
 If Tr>Tl Then Begin Cx:=(Tl+Tr+1)/2;TorsoHalf:=(Tr-Tl+1)/2;End;
 Orig:=AllocF(N*3);
 Mk:=PByte(AllocBytes(N));CapCat:=PByte(AllocBytes(N));
 Cap:=AllocF(N);
 Done:=0;Skipped:=0;
 For Side:=0 to 1 do Begin
  Mx:=0;My:=0;Cnt:=0;
  For Y:=0 to S.H-1 do For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   If(S.Cat[cArms][K]>=128)and((X<Cx)=(Side=0))Then Begin Mx:=Mx+X;My:=My+Y;
     Inc(Cnt);End;
  End;
  If Cnt<N div 9000 Then Continue;
  Mx:=Mx/Cnt;My:=My/Cnt;
  Sxx:=0;Sxy:=0;Syy:=0;
  For Y:=0 to S.H-1 do For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   If(S.Cat[cArms][K]>=128)and((X<Cx)=(Side=0))Then Begin
    Sxx:=Sxx+(X-Mx)*(X-Mx);Sxy:=Sxy+(X-Mx)*(Y-My);Syy:=Syy+(Y-My)*(Y-My);
   End;
  End;
  Th:=0.5*ATan2F(2*Sxy,Sxx-Syy);
  Ax:=Cos(Th);Ay:=Sin(Th);
  If Ay<0 Then Begin Ax:=-Ax;Ay:=-Ay;End;
  If Abs(ATan2F(Ax,Ay))*180/Pi<5 Then Begin
    Detail('bras d'#130'j'#133' align'#130's');Continue;End;
  If Abs(Mx-Cx)<0.45*TorsoHalf Then Begin Inc(Skipped);Continue;End;
  Pmin:=1.0e9;Pmax:=-1.0e9;Hw:=0;
  For Y:=0 to S.H-1 do For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   If(S.Cat[cArms][K]>=128)and((X<Cx)=(Side=0))Then Begin
    Pj:=(X-Mx)*Ax+(Y-My)*Ay;
    Uc:=Abs(-(X-Mx)*Ay+(Y-My)*Ax);
    If Pj<Pmin Then Pmin:=Pj;
    If Pj>Pmax Then Pmax:=Pj;
    If Uc>Hw Then Hw:=Uc;
   End;
  End;
  L:=Pmax-Pmin;
  If L<10 Then Continue;
  { epaule : point de l'axe, en amont, ou il entre dans la colonne du torse }
  Ext:=0.30*L;
  Tp:=0;
  While Tp<=2.5*L do Begin
   Ppx:=Mx+Ax*(Pmin-Tp);Ppy:=My+Ay*(Pmin-Tp);
   If Abs(Ppx-Cx)<=TorsoHalf*1.02 Then Begin Ext:=Tp;Break;End;
   Tp:=Tp+1;
  End;
  Pvx:=Mx+Ax*(Pmin-Ext);Pvy:=My+Ay*(Pmin-Ext);
  { capsule du bras : peau visible et manche attenante }
  FillChar(Mk^,N,0);FillChar(Cap^,N*4,0);FillChar(CapCat^,N,0);
  For Y:=0 to S.H-1 do For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   Pj:=(X+0.5-Mx)*Ax+(Y+0.5-My)*Ay;
   Uc:=Abs(-(X+0.5-Mx)*Ay+(Y+0.5-My)*Ax);
   If(Pj<Pmin-Ext-2)or(Pj>Pmax+2)or(Uc>Hw*2.4+4)Then Continue;
   If(S.Cat[cArms][K]>=128)and(Uc<=Hw*1.3+2)Then Begin Mk[K]:=255;
     Cap[K]:=1;CapCat[K]:=cArms;End
   Else If(S.Cat[cTop][K]>=128)and(Pj<Pmin+0.10*L)and(Abs(X+0.5-Cx)
     >TorsoHalf*0.98)Then Begin Mk[K]:=255;Cap[K]:=1;CapCat[K]:=cTop;End;
  End;
  BoxBlur(Cap,Cap,S.W,S.H,1);
  Move(S.Pix^,Orig^,N*12);
  { zone liberee : remplie par propagation depuis ce qui l'entoure }
  MorphMask(Mk,S.W,S.H,2,False);
  Known:=AllocF(N);
  For K:=0 to N-1 do If Mk[K]=0 Then Known[K]:=1;
  PushPullFill(S.Pix,Known,S.W,S.H);
  FreeMem(Known);
  For K:=0 to N-1 do If Mk[K]<>0 Then Begin
   For C:=0 to NumCat-1 do S.Cat[C][K]:=0;
   S.Cat[cBg][K]:=255;
  End;
  { rotation autour de l'epaule : le bras pend a la verticale }
  Delta:=Pi/2-ATan2F(Ay,Ax);
  Cd:=Cos(-Delta);Sd:=Sin(-Delta);
  For Y:=0 to S.H-1 do For X:=0 to S.W-1 do Begin
   Rx:=X+0.5-Pvx;Ry:=Y+0.5-Pvy;
   Sx:=Pvx+Rx*Cd-Ry*Sd;Sy:=Pvy+Rx*Sd+Ry*Cd;
   If(Sx<0)or(Sy<0)or(Sx>=S.W)or(Sy>=S.H)Then Continue;
   Ix:=Trunc(Sx);Iy:=Trunc(Sy);
   Wc:=Cap[Int64(Iy)*S.W+Ix];
   If Wc<=0.02 Then Continue;
   K:=Int64(Y)*S.W+X;
   SampleBilinear(Orig,S.W,S.H,3,Sx,Sy,@Px[0]);
   For C:=0 to 2 do S.Pix[K*3+C]:=S.Pix[K*3+C]*(1-Wc)+Px[C]*Wc;
   For C:=0 to NumCat-1 do S.Cat[C][K]:=Trunc(S.Cat[C][K]*(1-Wc)+0.5);
   C:=CapCat[Int64(Iy)*S.W+Ix];
   If C=0 Then C:=cArms;
   Mv:=S.Cat[C][K]+Trunc(Wc*255+0.5);
   If Mv>255 Then Mv:=255;
   S.Cat[C][K]:=Mv;
  End;
  Inc(Done);
 End;
 FreeMem(Orig);FreeMem(Mk);FreeMem(CapCat);FreeMem(Cap);
 If Skipped>0 Then
   Warn('bras crois'#130's devant le corps : non modifi'#130's');
 If Done=0 Then Begin
  Msg:='aucun bras '#133' redresser (d'#130'j'#133' le long du corps, non '+
    'visibles ou crois'#130's)';
  Exit;
 End;
 ArmsDown:=True;
 Info('  bras redress'#130's ('+IStr(Done)+')');
End;

{ ------------------------------------------------------------------ }
{ Matieres : metal (or, argent, bronze...), cotte de mailles, robot,    }
{ statue. L'ombrage de la photo est conserve pour garder le volume.    }
{ ------------------------------------------------------------------ }

{ rampe de couleur d'un metal : V de 0 (ombre) a 1 (reflet eclatant) }
Procedure MetalRamp(Base:LongWord;V:Single;Var R,G,B:Single);
Var
 Br,Bg,Bb,T:Single;
 Function Lr(A,Bv,Tt:Single):Single;
 Begin
  Lr:=A+(Bv-A)*Tt;
 End;
Begin
 Br:=(Base shr 16)and $FF;Bg:=(Base shr 8)and $FF;Bb:=Base and $FF;
 If V<0 Then V:=0 Else If V>1 Then V:=1;
 If V<0.30 Then Begin
  T:=V/0.30;
  R:=Lr(Br*0.12,Br*0.42,T);G:=Lr(Bg*0.12,Bg*0.42,T);B:=Lr(Bb*0.14,Bb*0.45,T);
 End
  Else If V<0.58 Then Begin
   T:=(V-0.30)/0.28;
   R:=Lr(Br*0.42,Br*0.95,T);G:=Lr(Bg*0.42,Bg*0.95,T);B:=Lr(Bb*0.45,Bb*0.92,T);
  End
   Else If V<0.84 Then Begin
    T:=(V-0.58)/0.26;
    R:=Lr(Br*0.95,Br+(255-Br)*0.62,T);G:=Lr(Bg*0.95,Bg+(255-Bg)*0.62,T);
      B:=Lr(Bb*0.92,Bb+(255-Bb)*0.62,T);
   End
    Else Begin
     T:=(V-0.84)/0.16;
     R:=Lr(Br+(255-Br)*0.62,255,T);G:=Lr(Bg+(255-Bg)*0.62,255,T);B:=Lr(Bb+
       (255-Bb)*0.62,252,T);
    End;
End;

{ valeur de reflexion d'un metal a partir de l'ombrage de la photo }
Function MetalValue(L,Lsm,Lbig:Single):Single;
Var
 V0,Bnd,V:Single;
Begin
 V0:=0.45*L+0.32*Lsm+0.23*Lbig;
 Bnd:=0.5+0.5*Cos(2*Pi*(V0*2.1+0.05));
 V:=0.30*V0+0.70*Bnd;
 If V0>0.82 Then V:=V+0.30*(V0-0.82)/0.18;
 If V0<0.12 Then V:=V*(0.5+4*V0);
 MetalValue:=Clamp(V,0,1);
End;

{ bruit cellulaire : distance aux deux points les plus proches, indice du plus
  proche }
Procedure Worley(X,Y,Cs:Single;Var D1,D2:Single;Var Id:LongInt;Var Fx,
  Fy:Single);
Var
 Ix,Iy,Dx,Dy,Cx,Cy:LongInt;
 Px,Py,D:Single;
Begin
 Ix:=FloorI(X/Cs);Iy:=FloorI(Y/Cs);
 D1:=1.0e9;D2:=1.0e9;Id:=0;Fx:=0;Fy:=0;
 For Dy:=-1 to 1 do
  For Dx:=-1 to 1 do Begin
   Cx:=Ix+Dx;Cy:=Iy+Dy;
   Px:=(Cx+0.15+0.7*Hash2(Cx,Cy))*Cs;
   Py:=(Cy+0.15+0.7*Hash2(Cx+57,Cy+91))*Cs;
   D:=Sqrt(Sqr(X-Px)+Sqr(Y-Py));
   If D<D1 Then Begin
    D2:=D1;D1:=D;Id:=(Cx and $FFFF)*65536+(Cy and $FFFF);Fx:=Px;Fy:=Py;
   End
    Else If D<D2 Then D2:=D;
  End;
End;

{ anneaux entrelaces de la cotte de mailles : hauteur 0..1 et eclairage }
Procedure ChainRing(X,Y,P:Single;Var H,Light:Single);
Var
 Dx,Dy,Ro,Wd,Off,Cx,Cy,D,T,Hh,Ln:Single;
 J0,J,I,I0:LongInt;
Begin
 Dx:=0.62*P;Dy:=0.45*P;
 Ro:=0.50*P;Wd:=0.095*P;
 H:=0;Light:=0.5;
 J0:=FloorI(Y/Dy);
 For J:=J0-2 to J0+2 do Begin
  If Odd(J)Then Off:=0.5*Dx Else Off:=0;
  I0:=FloorI((X-Off)/Dx+0.5);
  For I:=I0-1 to I0+1 do Begin
   Cx:=Off+I*Dx;Cy:=(J+0.5)*Dy;
   D:=Sqrt(Sqr(X-Cx)+Sqr(Y-Cy));
   T:=(D-Ro)/Wd;
   If Abs(T)<1 Then Begin
    Hh:=Sqrt(1-T*T);
    If Hh>H Then Begin
     H:=Hh;
     If D>0.001 Then Ln:=((X-Cx)*(-0.55)+(Y-Cy)*(-0.83))/D Else Ln:=0;
     Light:=0.5+0.5*Ln*T;
    End;
   End;
  End;
 End;
End;

{ lueur d'un disque (yeux de robot) }
Procedure GlowDisc(Var S:TScene;Cx,Cy,R:Single;Cr,Cg,Cb:Single);
Var
 X,Y:LongInt;
 D,Core,Halo,A:Single;
 K:Int64;
Begin
 For Y:=Trunc(Cy-R*3.5)to Trunc(Cy+R*3.5)do
  For X:=Trunc(Cx-R*3.5)to Trunc(Cx+R*3.5)do Begin
   If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Continue;
   D:=Sqrt(Sqr(X+0.5-Cx)+Sqr(Y+0.5-Cy));
   Core:=1-SmoothStep(R*0.8,R*1.15,D);
   Halo:=Exp(-Sqr(D/(R*1.9)))*0.7;
   K:=Int64(Y)*S.W+X;
   A:=FMax(Core,Halo*0.6);
   S.Pix[K*3]:=S.Pix[K*3]*(1-A)+(Cr+(255-Cr)*Core*0.8)*A+Halo*0.15*Cr;
   S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-A)+(Cg+(255-Cg)*Core*0.8)*A+Halo*0.15*Cg;
   S.Pix[K*3+2]:=S.Pix[K*3+2]*(1-A)+(Cb+(255-Cb)*Core*0.8)*A+Halo*0.15*Cb;
  End;
End;

{ applique une matiere aux pixels d'opacite Al }
Function ApplyMaterial(Var S:TScene;Const E:TEdit;Var Msg:AnsiString):Boolean;
Var
 N:int64;K:LongInt;
 X,Y,Md,Side,Id,C:LongInt;
 Mt:LongInt;
 Mask:LongWord;
 L01,Lsm,Lbig,Al,Yl:PSingle;
 Base:LongWord;
 R,G,B,V,Lm,Pp,Cs,D1,D2,Fx,Fy,Edge,Sw,Dk,Glow,H,Lg,Q,Sd,Vein:Single;
 Cnt:Int64;
 Hd:THeadInfo;
 Ex,Ey,Rr,Cx,Cy,Sc,Lskin:Single;
 SkinSum:Double;
 SkinCnt:Int64;
 Fm:PSingle;
 Mn:Single;
Begin
 ApplyMaterial:=False;
 Msg:='';
 ColorInit;
 Mt:=E.Material;
 N:=Int64(S.W)*S.H;
 Md:=IMin(S.W,S.H);
 Al:=AllocF(N);
 Case Mt of
  mtStatue:For K:=0 to N-1 do Al[K]:=1-S.Cat[cBg][K]/255.0;
  mtRobot:CatMask(S,msSkin or msHair,Al);
  mtChain:Begin
    Mask:=E.Target;
    If(Mask=0)or((Mask and msClothes)=0)Then Mask:=msClothes;
    CatMask(S,Mask,Al);
   End;
  Else Begin
    Mask:=E.Target;
    If Mask=0 Then Mask:=msSkin;
    CatMask(S,Mask and(not msEyes),Al);
   End;
 End;
 Cnt:=0;
 For K:=0 to N-1 do If Al[K]>=0.5 Then Inc(Cnt);
 If Cnt<N div 3000 Then Begin
  Msg:='aucune zone '#133' transformer d'#130'tect'#130'e pour cette mati'#138+
    're';
  FreeMem(Al);Exit;
 End;
 SharpenAlpha(Al,N);
 { couleur du metal }
 If E.HasDst Then Base:=E.DstRGB
 Else Case Mt of
  mtChain:Base:=RgbOf(224,182,64);
  mtRobot:Base:=RgbOf(168,176,190);
  mtStatue:Base:=RgbOf(238,235,228);
  Else Base:=RgbOf(204,209,220);
 End;
 L01:=AllocF(N);Lsm:=AllocF(N);Lbig:=AllocF(N);Yl:=AllocF(N);
 For K:=0 to N-1 do Begin
  L01[K]:=Luma(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2])/255.0;
  Yl[K]:=L01[K]*255;
 End;
 Move(L01^,Lsm^,N*4);Move(L01^,Lbig^,N*4);
 BlurPlane(Lsm,S.W,S.H,FMax(1.5,Md/300.0));
 BlurPlane(Lbig,S.W,S.H,FMax(4,Md/80.0));
 { moyenne de luminosite de la region : normalise l'ombrage }
 Lm:=0;
 For K:=0 to N-1 do If Al[K]>=0.5 Then Lm:=Lm+Lsm[K];
 Lm:=Lm/Cnt;
 If Lm<0.05 Then Lm:=0.05;
 Cs:=FMax(14,Md/15.0);
 Pp:=Clamp(Md/30.0,12,26);
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   If Al[K]<=0.004 Then Continue;
   { l'ombrage relatif : le visage sombre et la peau claire donnent le meme
     volume }
   Q:=Clamp(0.5+(L01[K]-Lm)*2.1,0,1);
   Mn:=Clamp(0.5+(Lsm[K]-Lm)*2.1,0,1);
   Lg:=Clamp(0.5+(Lbig[K]-Lm)*2.1,0,1);
   Case Mt of
    mtChain:Begin
      ChainRing(X+0.5,Y+0.5,Pp,H,Lg);
      V:=0.04+0.96*Clamp(H*(0.10+1.05*Lg),0,1);
      V:=V*(0.40+1.3*Mn)+0.10*(Q-Mn);
      MetalRamp(Base,Clamp(V,0,1),R,G,B);
     End;
    mtRobot:Begin
      V:=MetalValue(Q,Mn,Lg);
      Worley(X+0.5,Y+0.5,Cs,D1,D2,Id,Fx,Fy);
      Edge:=D2-D1;Sw:=0.05*Cs;
      Dk:=1-SmoothStep(0,Sw,Edge);
      V:=V*(1-0.82*Dk);
      If(Edge>Sw)and(Edge<2.2*Sw)Then V:=V*1.10+0.04;
      MetalRamp(Base,Clamp(V,0,1),R,G,B);
      { rivets }
      If D1<0.075*Cs Then Begin
       Glow:=1-SmoothStep(0.04*Cs,0.075*Cs,D1);
       R:=R*(1-Glow)+255*Glow*0.9;G:=G*(1-Glow)+255*Glow*0.9;B:=B*(1-Glow)+
         255*Glow*0.95;
      End;
      { quelques joints lumineux }
      If(Hash2(Id and $FFFF,Id shr 16)<0.14)Then Begin
       Glow:=Dk*0.9;
       R:=R*(1-Glow)+30*Glow;G:=G*(1-Glow)+(215)*Glow;B:=B*(1-Glow)+255*Glow;
      End;
     End;
    mtStatue:Begin
      If E.HasDst Then Begin
       V:=MetalValue(Q,Mn,Lg);
       MetalRamp(Base,V,R,G,B);
      End
       Else Begin
        V:=Clamp(0.56+1.7*(L01[K]-Lbig[K])+0.9*(Lbig[K]-Lm),0,1);
        R:=108+(250-108)*V;G:=104+(248-104)*V;B:=100+(242-100)*V;
        { veines du marbre }
        Sd:=VNoise(X/(Md/9.0),Y/(Md/9.0))*2+VNoise(X/(Md/24.0)+5,Y/(Md/24.0)+3);
        Vein:=1-SmoothStep(0.025,0.10,Abs(Sin(Sd*5.5)));
        Vein:=Vein*(0.10+0.32*VNoise(X/(Md/40.0),Y/(Md/40.0)));
        R:=R*(1-Vein)+96*Vein;G:=G*(1-Vein)+102*Vein;B:=B*(1-Vein)+114*Vein;
        R:=R+RngGauss*1.2;G:=G+RngGauss*1.2;B:=B+RngGauss*1.2;
       End;
     End;
    Else Begin
      V:=MetalValue(Q,Mn,Lg);
      MetalRamp(Base,V,R,G,B);
     End;
   End;
   S.Pix[K*3]:=S.Pix[K*3]*(1-Al[K])+R*Al[K];
   S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-Al[K])+G*Al[K];
   S.Pix[K*3+2]:=S.Pix[K*3+2]*(1-Al[K])+B*Al[K];
  End;
 { yeux : lumiere bleue pour le robot, orbites vides pour la statue }
 If(Mt=mtRobot)or(Mt=mtStatue)Then Begin
  If HeadInfo(S,Hd)and(Hd.Fw>=40)Then Begin
   Rr:=FMax(2.5,0.046*Hd.Fw);
   For Side:=-1 to 1 do Begin
    If Side=0 Then Continue;
    Ex:=Hd.Cx+Side*0.225*Hd.Fw;Ey:=Hd.Fy0+0.42*Hd.Fh;
    If FindIris(S,Yl,Ex,Ey,0.12*Hd.Fw,0.17*Hd.Fh,Rr,Cx,Cy,Sc)and(Sc>=9)
      Then Begin
     If Mt=mtRobot Then GlowDisc(S,Cx,Cy,Rr*0.85,40,215,255)
     Else GlowDisc(S,Cx,Cy,Rr*0.85,225,222,215);
    End;
   End;
  End;
 End;
 FreeMem(L01);FreeMem(Lsm);FreeMem(Lbig);FreeMem(Yl);FreeMem(Al);
 ApplyMaterial:=True;
 Case Mt of
  mtChain:Info('  cotte de mailles appliqu'#130'e');
  mtRobot:Info('  corps de robot appliqu'#130);
  mtStatue:Info('  style statue appliqu'#130);
  Else Info('  rendu m'#130'tallique appliqu'#130);
 End;
End;

{ ------------------------------------------------------------------ }
{ Scenes : decor genere autour de la personne (carrousel)            }
{ ------------------------------------------------------------------ }

{ agrandit l'image vers le bas (lignes d'arriere-plan) }
Procedure GrowCanvas(Var S:TScene;Extra:LongInt);
Var
 H2,Y,X,C:LongInt;
 P2:PSingle;
 Cat2:Array[0..NumCat-1]of PByte;
 N1,N2:Int64;
Begin
 H2:=S.H+Extra;
 N1:=Int64(S.W)*S.H;N2:=Int64(S.W)*H2;
 P2:=AllocF(N2*3);
 Move(S.Pix^,P2^,N1*12);
 For Y:=S.H to H2-1 do Move((S.Pix+Int64(S.H-1)*S.W*3)^,(P2+Int64(Y)*S.W*3)^,
   S.W*12);
 For C:=0 to NumCat-1 do Begin
  Cat2[C]:=PByte(AllocBytes(N2));
  Move(S.Cat[C]^,Cat2[C]^,N1);
  FreeMem(S.Cat[C]);
  S.Cat[C]:=Cat2[C];
 End;
 FillChar((S.Cat[cBg]+N1)^,N2-N1,255);
 FreeMem(S.Pix);
 S.Pix:=P2;
 S.H:=H2;
End;

Procedure PutBg(Bg:PSingle;W,H,X,Y:LongInt;Cov,R,G,B:Single);
Var
 K:Int64;
Begin
 If(X<0)or(Y<0)or(X>=W)or(Y>=H)Then Exit;
 If Cov<=0.003 Then Exit;
 If Cov>1 Then Cov:=1;
 K:=Int64(Y)*W+X;
 Bg[K*3]:=Bg[K*3]*(1-Cov)+R*Cov;
 Bg[K*3+1]:=Bg[K*3+1]*(1-Cov)+G*Cov;
 Bg[K*3+2]:=Bg[K*3+2]*(1-Cov)+B*Cov;
End;

{ poteau de laiton vertical }
Procedure BrassPole(Bg:PSingle;W,H:LongInt;Px,Y0,Y1,Pw:Single);
Var
 X,Y:LongInt;
 U,V,Cov:Single;
 R,G,B:Single;
Begin
 For Y:=Trunc(Y0)to Trunc(Y1)do
  For X:=Trunc(Px-Pw-2)to Trunc(Px+Pw+2)do Begin
   U:=(X+0.5-Px)/Pw;
   Cov:=CoverD(Abs(U)*Pw-Pw);
   If Cov<=0 Then Continue;
   V:=MetalV(Clamp(0.5+U*0.5,0,1));
   MetalRamp(RgbOf(224,176,70),V*0.95,R,G,B);
   PutBg(Bg,W,H,X,Y,Cov,R,G,B);
  End;
End;

Procedure Bulb(Bg:PSingle;W,H:LongInt;Cx,Cy,R:Single);
Var
 X,Y:LongInt;
 D,Core,Halo:Single;
Begin
 For Y:=Trunc(Cy-R*4)to Trunc(Cy+R*4)do
  For X:=Trunc(Cx-R*4)to Trunc(Cx+R*4)do Begin
   D:=Sqrt(Sqr(X+0.5-Cx)+Sqr(Y+0.5-Cy));
   Core:=1-SmoothStep(R*0.7,R*1.1,D);
   Halo:=Exp(-Sqr(D/(R*2.2)))*0.55;
   If Core>0.01 Then PutBg(Bg,W,H,X,Y,Core,255,246,200);
   If Halo>0.01 Then PutBg(Bg,W,H,X,Y,Halo*0.6,255,214,130);
  End;
End;

Function ApplyCarousel(Var S:TScene;Var Msg:AnsiString):Boolean;
Var
 N:int64;K:LongInt;
 X,Y,I,X0,Y0,X1,Y1,Cnt,Rows,Side:LongInt;
 Bg,Al,Sh:PSingle;
 YFeet,Xc,BodyW,BodyH,Rx,Ry,Thick,Sw,Hc,YPl,E,U,Cov,V,R,G,B,Sx,Sy,Dd,T,Px,
   Rr:Single;
 YLast:Array[0..0]of LongInt;
 Fx0,Fx1,Fx2:LongInt;
 Sumx:Double;
 Nx:Int64;
Begin
 ApplyCarousel:=False;
 Msg:='';
 ColorInit;
 { silhouette de la personne }
 X0:=S.W;Y0:=S.H;X1:=-1;Y1:=-1;Cnt:=0;
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do If S.Cat[cBg][Int64(Y)*S.W+X]<128 Then Begin
   If X<X0 Then X0:=X;If X>X1 Then X1:=X;
   If Y<Y0 Then Y0:=Y;If Y>Y1 Then Y1:=Y;
   Inc(Cnt);
  End;
 If Cnt<Int64(S.W)*S.H div 100 Then Begin Msg:=
   'aucune personne d'#130'tect'#130'e : impossible de la placer sur un '+
   'carrousel';Exit;End;
 YFeet:=Y1+1;BodyH:=Y1-Y0+1;BodyW:=X1-X0+1;
 { centre horizontal des pieds : bas de la silhouette }
 Sumx:=0;Nx:=0;
 For Y:=IMax(Y0,Y1-IMax(3,Y1-Y0 div 12))to Y1 do
  For X:=0 to S.W-1 do If S.Cat[cBg][Int64(Y)*S.W+X]<128 Then Begin Sumx:=Sumx+
    X;Inc(Nx);End;
 If Nx>0 Then Xc:=Sumx/Nx+0.5 Else Xc:=(X0+X1+1)/2;
 { place pour la plateforme sous les pieds }
 Rows:=Trunc(0.11*FMax(0.55*S.W,1.55*BodyW)+0.055*S.H)-(S.H-Y1-1);
 If Rows>0 Then GrowCanvas(S,Rows);
 N:=Int64(S.W)*S.H;
 Bg:=AllocF(N*3);
 { ciel nocturne de fete }
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   T:=Y/S.H;
   Dd:=Sqrt(Sqr(X/S.W-0.5)*1.2+Sqr(T-0.45)*0.9);
   R:=(28+110*SmoothStep(0.0,0.9,T)+20*Exp(-Dd*4))*(1-0.35*Dd);
   G:=(16+46*SmoothStep(0.0,0.9,T)+10*Exp(-Dd*4))*(1-0.35*Dd);
   B:=(56+44*SmoothStep(0.0,0.7,T)-10*T)*(1-0.30*Dd);
   Bg[K*3]:=R;Bg[K*3+1]:=G;Bg[K*3+2]:=B;
  End;
 { lumieres floues du fond }
 For I:=1 to 46 do Begin
  Sx:=RngF*S.W;Sy:=RngF*S.H*0.72+0.10*S.H;
  Rr:=(0.012+0.03*RngF)*S.H;
  T:=RngF;
  If T<0.5 Then Begin R:=255;G:=190;B:=110;End
  Else If T<0.8 Then Begin R:=255;G:=120;B:=150;End
  Else Begin R:=140;G:=190;B:=255;End;
  For Y:=Trunc(Sy-Rr)to Trunc(Sy+Rr)do
   For X:=Trunc(Sx-Rr)to Trunc(Sx+Rr)do Begin
    Dd:=Sqrt(Sqr(X+0.5-Sx)+Sqr(Y+0.5-Sy))/Rr;
    PutBg(Bg,S.W,S.H,X,Y,(0.10+0.16*RngF*0)*(1-SmoothStep(0.78,1.0,Dd))+
      0.16*Exp(-Dd*Dd*2.5)*0.3,R,G,B);
   End;
 End;
 { plateforme tournante : bois, rebord de laiton, flanc rouge }
 Rx:=FMax(0.55*S.W,1.55*BodyW);
 If Rx>0.92*S.W Then Rx:=0.92*S.W;
 Ry:=0.11*Rx;
 YPl:=YFeet-0.012*S.H;
 Thick:=0.04*S.H;
 Hc:=0.17*S.H;
 { poteaux derriere la personne }
 For I:=0 to 6 do Begin
  Px:=S.W*(I+0.5)/7;
  BrassPole(Bg,S.W,S.H,Px,Hc,YPl+Ry*Sqrt(FMax(0,1-Sqr((Px-Xc)/Rx))),0.0075*S.W);
 End;
 { dessus de la plateforme }
 For Y:=Trunc(YPl-Ry-2)to Trunc(YPl+Ry+Thick+2)do
  For X:=Trunc(Xc-Rx-2)to Trunc(Xc+Rx+2)do Begin
   U:=(X+0.5-Xc)/Rx;
   Dd:=(Y+0.5-YPl)/Ry;
   E:=Sqrt(U*U+Dd*Dd);
   { dessus }
   Cov:=CoverD((E-1.0)*Ry*0.9);
   If Cov>0 Then Begin
    V:=0.55+0.30*Cos(E*Pi*5.0)*0.5+0.12*(0.5-Dd*0.5);
    If Frac(E*7.0)<0.5 Then V:=V*0.86;
    V:=V*(0.8+0.25*(1-E));
    R:=176*V+RngGauss*1.2;G:=118*V+RngGauss*1.2;B:=68*V+RngGauss*1.2;
    PutBg(Bg,S.W,S.H,X,Y,Cov,R,G,B);
   End;
   { rebord de laiton }
   Cov:=CoverD(Abs(E-1.035)*Ry*0.9-0.018*Ry*3);
   If Cov>0 Then Begin
    MetalRamp(RgbOf(226,178,72),MetalV(Clamp(0.5+(Dd-U*0)*0.25,0,1))*0.95,R,G,
      B);
    PutBg(Bg,S.W,S.H,X,Y,Cov,R,G,B);
   End;
   { flanc avant }
   If(Dd>0)and(Abs(U)<1.0)Then Begin
    Sy:=Ry*Sqrt(FMax(0,1-U*U));
    Cov:=CoverD(FMax(YPl+Sy-(Y+0.5),(Y+0.5)-(YPl+Sy+Thick)));
    If Cov>0 Then Begin
     V:=0.55+0.45*Sqrt(FMax(0,1-U*U));
     R:=128*V;G:=26*V;B:=38*V;
     If Abs((Y+0.5)-(YPl+Sy+Thick*0.5))<0.04*Thick Then Begin R:=226*V;
       G:=178*V;B:=72*V;End;
     PutBg(Bg,S.W,S.H,X,Y,Cov,R,G,B);
    End;
   End;
  End;
 { ampoules sur le rebord avant }
 For I:=0 to 24 do Begin
  U:=-0.96+I*0.08;
  Bulb(Bg,S.W,S.H,Xc+U*Rx,YPl+Ry*Sqrt(FMax(0,1-U*U))+0.003*S.H,0.0045*S.H);
 End;
 { ombre portee aux pieds }
 For Y:=Trunc(YFeet-0.05*BodyW)to Trunc(YFeet+0.07*BodyW)do
  For X:=Trunc(Xc-0.7*BodyW)to Trunc(Xc+0.7*BodyW)do Begin
   Dd:=Sqrt(Sqr((X+0.5-Xc)/(0.6*BodyW))+Sqr((Y+0.5-YFeet-0.01*BodyW)
     /(0.045*BodyW)));
   PutBg(Bg,S.W,S.H,X,Y,0.55*Exp(-Dd*Dd*1.6),10,6,14);
  End;
 { dessous de la plateforme : sol sombre }
 For Y:=Trunc(YPl+Ry+Thick)to S.H-1 do
  For X:=0 to S.W-1 do PutBg(Bg,S.W,S.H,X,Y,1,16,10,22);
 { toit raye a festons }
 Sw:=S.W/12.0;
 For Y:=0 to Trunc(Hc+Sw)do
  For X:=0 to S.W-1 do Begin
   Px:=Frac(X/Sw);
   Dd:=Hc+Sqrt(FMax(0,Sqr(Sw/2)-Sqr((Px-0.5)*Sw)))*0.9;
   Cov:=CoverD(Y+0.5-Dd);
   If Cov<=0 Then Continue;
   If Odd(Trunc(X/Sw))Then Begin R:=196;G:=32;B:=44;End Else Begin R:=242;
     G:=232;B:=212;End;
   V:=0.55+0.30*Cos((Px-0.5)*Pi)+0.15*(1-Y/Hc*0.5);
   V:=V*(0.75+0.25*(1-Y/(Hc+Sw)));
   PutBg(Bg,S.W,S.H,X,Y,Cov,R*V,G*V,B*V);
   { galon dore en bas des festons }
   If Abs(Y+0.5-Dd)<0.006*S.H Then PutBg(Bg,S.W,S.H,X,Y,0.9,230,182,76);
  End;
 For I:=0 to 11 do Bulb(Bg,S.W,S.H,(I+0.5)*Sw,Hc+Sw*0.45*0.9+0.004*S.H,
   0.0055*S.H);
 { poteaux de premier plan, aux bords }
 BrassPole(Bg,S.W,S.H,0.035*S.W,Hc,YPl+Ry*0.3,0.012*S.W);
 BrassPole(Bg,S.W,S.H,0.965*S.W,Hc,YPl+Ry*0.3,0.012*S.W);
 { personne par-dessus le decor }
 Al:=AllocF(N);
 For K:=0 to N-1 do Begin
  Al[K]:=1-S.Cat[cBg][K]/255.0;
  Al[K]:=SmoothStep(0.30,0.85,Al[K]);
 End;
 For K:=0 to N-1 do Begin
  { lumiere chaude du manege sur la personne }
  For I:=0 to 2 do Begin
   V:=S.Pix[K*3+I];
   If I=0 Then V:=V*1.04 Else If I=2 Then V:=V*0.94;
   Bg[K*3+I]:=Bg[K*3+I]*(1-Al[K])+V*Al[K];
  End;
 End;
 Move(Bg^,S.Pix^,N*12);
 FreeMem(Bg);FreeMem(Al);
 ApplyCarousel:=True;
 Info('  sc'#138'ne de carrousel g'#130'n'#130'r'#130'e');
End;
{ ------------------------------------------------------------------ }
{ Poses et expressions : humeur, regard, yeux fermes, tete droite,   }
{ aureole (le tout dessine ou deforme par le programme)              }
{ ------------------------------------------------------------------ }

Type
 TIris=Record
  Ok:Boolean;
  Cx,Cy,R:Single;
 End;

{ agrandit l'image sur les quatre cotes : le fond est prolonge par propagation }
Procedure GrowEdges(Var S:TScene;L,T,R,B:LongInt);
Var
 W2,H2,X,Y,C,Sx,Sy:LongInt;
 N2,K,K1:Int64;
 P2,Kn,Tmp:PSingle;
 Cat2:Array[0..NumCat-1]of PByte;
 Inside:Boolean;
Begin
 If L<0 Then L:=0;If T<0 Then T:=0;If R<0 Then R:=0;If B<0 Then B:=0;
 If(L=0)and(T=0)and(R=0)and(B=0)Then Exit;
 W2:=S.W+L+R;H2:=S.H+T+B;
 N2:=Int64(W2)*H2;
 P2:=AllocF(N2*3);Kn:=AllocF(N2);
 For C:=0 to NumCat-1 do Cat2[C]:=PByte(AllocBytes(N2));
 For Y:=0 to H2-1 do
  For X:=0 to W2-1 do Begin
   Sx:=ClampI(X-L,0,S.W-1);Sy:=ClampI(Y-T,0,S.H-1);
   K:=Int64(Y)*W2+X;K1:=Int64(Sy)*S.W+Sx;
   Inside:=(X>=L)and(X<L+S.W)and(Y>=T)and(Y<T+S.H);
   For C:=0 to 2 do P2[K*3+C]:=S.Pix[K1*3+C];
   If Inside Then Begin
    For C:=0 to NumCat-1 do Cat2[C][K]:=S.Cat[C][K1];
    If S.Cat[cBg][K1]>=200 Then Kn[K]:=1;
   End
    Else Cat2[cBg][K]:=255;
  End;
 Tmp:=AllocF(N2*3);
 Move(P2^,Tmp^,N2*12);
 PushPullFill(Tmp,Kn,W2,H2);
 For Y:=0 to H2-1 do
  For X:=0 to W2-1 do
   If(X<L)or(X>=L+S.W)or(Y<T)or(Y>=T+S.H)Then Begin
    K:=Int64(Y)*W2+X;
    For C:=0 to 2 do P2[K*3+C]:=Tmp[K*3+C];
   End;
 FreeMem(Tmp);FreeMem(Kn);
 FreeMem(S.Pix);S.Pix:=P2;
 For C:=0 to NumCat-1 do Begin
  FreeMem(S.Cat[C]);
  S.Cat[C]:=Cat2[C];
 End;
 S.W:=W2;S.H:=H2;
End;

{ plan de luminance }
Function LumaPlane(Const S:TScene):PSingle;
Var
 N:int64;K:LongInt;
 Yl:PSingle;
Begin
 N:=Int64(S.W)*S.H;
 Yl:=AllocF(N);
 For K:=0 to N-1 do Yl[K]:=Luma(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2]);
 LumaPlane:=Yl;
End;

{ couleur moyenne du visage (joues et nez) }
Procedure FaceSkin(Const S:TScene;Const H:THeadInfo;Var R,G,B:Single);
Var
 X,Y,Cnt:LongInt;
 K:Int64;
 Sr,Sg,Sb:Double;
Begin
 Sr:=0;Sg:=0;Sb:=0;Cnt:=0;
 For Y:=Trunc(H.Fy0+0.50*H.Fh)to Trunc(H.Fy0+0.64*H.Fh)do
  For X:=Trunc(H.Cx-0.30*H.Fw)to Trunc(H.Cx+0.30*H.Fw)do Begin
   If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Continue;
   K:=Int64(Y)*S.W+X;
   If S.Cat[cFace][K]<200 Then Continue;
   Sr:=Sr+S.Pix[K*3];Sg:=Sg+S.Pix[K*3+1];Sb:=Sb+S.Pix[K*3+2];Inc(Cnt);
  End;
 If Cnt>0 Then Begin R:=Sr/Cnt;G:=Sg/Cnt;B:=Sb/Cnt;End
 Else Begin R:=205;G:=160;B:=135;End;
End;

{ les deux iris (0 = a gauche de l'image, 1 = a droite) }
Function FindIrises(Const S:TScene;Const H:THeadInfo;Yl:PSingle;Var Ir:Array
  of TIris;Var Lskin:Single):LongInt;
Var
 N:int64;K:LongInt;
 Side,Cnt:LongInt;
 Sd:Double;
 R,Ex,Ey,Cx,Cy,Sc:Single;
Begin
 Sd:=0;Cnt:=0;
 N:=Int64(S.W)*S.H;
 For K:=0 to N-1 do If S.Cat[cFace][K]>=230 Then Begin Sd:=Sd+Yl[K];Inc(Cnt);
   End;
 If Cnt>0 Then Lskin:=Sd/Cnt Else Lskin:=150;
 R:=FMax(2.5,0.046*H.Fw);
 FindIrises:=0;
 Cnt:=0;
 For Side:=0 to 1 do Begin
  Ir[Side].Ok:=False;
  Ex:=H.Cx+(Side*2-1)*0.225*H.Fw;
  Ey:=H.Fy0+0.42*H.Fh;
  If FindIris(S,Yl,Ex,Ey,0.12*H.Fw,0.17*H.Fh,R,Cx,Cy,Sc)and(Sc>=9)Then Begin
   Ir[Side].Ok:=True;Ir[Side].Cx:=Cx;Ir[Side].Cy:=Cy;Ir[Side].R:=R;
   Inc(Cnt);
  End;
 End;
 FindIrises:=Cnt;
End;

{ expression : serieuse ou triste (les coins de la bouche descendent) }
Function ApplyMood(Var S:TScene;Sad:Boolean;Var Msg:AnsiString):Boolean;
Begin
 If Sad Then ApplyMood:=MouthWarp(S,-0.115,
   True,'expression triste (coins de la bouche abaiss'#130's)',Msg)
 Else ApplyMood:=MouthWarp(S,-0.06,
   True,'expression s'#130'rieuse (bouche neutre)',Msg);
End;

{ poids de l'iris (pixels sombres du disque) }
Function IrisW(L,Lskin,D,R:Single):Single;
Begin
 IrisW:=(1-SmoothStep(0.62*Lskin,0.86*Lskin,L))*(1-SmoothStep(1.0*R,1.18*R,D));
End;

{ regard : les iris glissent vers (Dx,Dy) dans l'ouverture de l'oeil }
Function ApplyGaze(Var S:TScene;Dx,Dy:Single;Var Msg:AnsiString):Boolean;
Var
 H:THeadInfo;
 N,K:Int64;
 Yl,Orig:PSingle;
 Ir:Array[0..1]of TIris;
 Side,X,Y,C,Cnt,Found:LongInt;
 Lskin,Cx,Cy,R,Sx,Sy,Sr,Sg,Sb,Mean,Open,Wi,D,Lm:Single;
 Sam:Array of Single;
 SamC:Array of Single;
 Ns:LongInt;
 Px:Array[0..2]of Single;
 Sc:Array[0..2]of Single;
Begin
 ApplyGaze:=False;
 Msg:='';
 If not HeadInfo(S,H)Then Begin Msg:=
   'aucun visage d'#130'tect'#130' : impossible de d'#130'placer le regard';
   Exit;End;
 If H.Fw<60 Then Begin Msg:=
   'le visage est trop petit pour modifier le regard (60 pixels de large '+
   'minimum)';Exit;End;
 ColorInit;
 N:=Int64(S.W)*S.H;
 Yl:=LumaPlane(S);
 Found:=FindIrises(S,H,Yl,Ir,Lskin);
 If Found=0 Then Begin
  Msg:='yeux non d'#130'tect'#130's (photo trop petite, trop sombre ou yeux '+
    'ferm'#130's)';
  FreeMem(Yl);Exit;
 End;
 Orig:=AllocF(N*3);
 Move(S.Pix^,Orig^,N*12);
 For Side:=0 to 1 do Begin
  If not Ir[Side].Ok Then Continue;
  Cx:=Ir[Side].Cx;Cy:=Ir[Side].Cy;R:=Ir[Side].R;
  { couleur de la sclerotique : pixels clairs de part et d'autre de l'iris }
  SetLength(Sam,0);
  For Y:=Trunc(Cy-0.5*R)to Trunc(Cy+0.5*R)do
   For X:=Trunc(Cx-2.1*R)to Trunc(Cx+2.1*R)do Begin
    If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Continue;
    If Abs(X+0.5-Cx)<1.3*R Then Continue;
    Ns:=Length(Sam);SetLength(Sam,Ns+1);
    Sam[Ns]:=Int64(Y)*S.W+X;
   End;
  Mean:=0;
  For Ns:=0 to High(Sam)do Mean:=Mean+Yl[Trunc(Sam[Ns])];
  If Length(Sam)>0 Then Mean:=Mean/Length(Sam);
  Sr:=0;Sg:=0;Sb:=0;Cnt:=0;
  For Ns:=0 to High(Sam)do Begin
   K:=Trunc(Sam[Ns]);
   If Yl[K]>=Mean Then Begin Sr:=Sr+S.Pix[K*3];Sg:=Sg+S.Pix[K*3+1];Sb:=Sb+
     S.Pix[K*3+2];Inc(Cnt);End;
  End;
  If Cnt>0 Then Begin Sc[0]:=Sr/Cnt;Sc[1]:=Sg/Cnt;Sc[2]:=Sb/Cnt;End
  Else Begin Sc[0]:=225;Sc[1]:=222;Sc[2]:=218;End;
  Sx:=Dx*0.72*R;Sy:=Dy*0.30*R;
  { l'ancien iris est efface }
  For Y:=Trunc(Cy-1.3*R)to Trunc(Cy+1.3*R)do
   For X:=Trunc(Cx-1.3*R)to Trunc(Cx+1.3*R)do Begin
    If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Continue;
    K:=Int64(Y)*S.W+X;
    D:=Sqrt(Sqr(X+0.5-Cx)+Sqr(Y+0.5-Cy));
    Open:=CoverD(EllipseD(X+0.5,Y+0.5,Cx,Cy,1.95*R,1.0*R));
    Wi:=IrisW(Yl[K],Lskin,D,R)*Open;
    If Wi<=0.003 Then Continue;
    For C:=0 to 2 do S.Pix[K*3+C]:=S.Pix[K*3+C]*(1-Wi)+Sc[C]*Wi;
   End;
  { et repeint plus loin, rogne par les paupieres }
  For Y:=Trunc(Cy+Sy-1.3*R)to Trunc(Cy+Sy+1.3*R)do
   For X:=Trunc(Cx+Sx-1.3*R)to Trunc(Cx+Sx+1.3*R)do Begin
    If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Continue;
    K:=Int64(Y)*S.W+X;
    Open:=CoverD(EllipseD(X+0.5,Y+0.5,Cx,Cy,1.95*R,1.0*R));
    If Open<=0 Then Continue;
    SampleBilinear(Orig,S.W,S.H,3,X+0.5-Sx,Y+0.5-Sy,@Px[0]);
    Lm:=Luma(Px[0],Px[1],Px[2]);
    D:=Sqrt(Sqr(X+0.5-Sx-Cx)+Sqr(Y+0.5-Sy-Cy));
    Wi:=IrisW(Lm,Lskin,D,R)*Open;
    If Wi<=0.003 Then Continue;
    For C:=0 to 2 do S.Pix[K*3+C]:=S.Pix[K*3+C]*(1-Wi)+Px[C]*Wi;
   End;
 End;
 FreeMem(Yl);FreeMem(Orig);
 ApplyGaze:=True;
 Info('  regard d'#130'plac'#130' ('+IStr(Found)+' oeil(s))');
End;

{ yeux fermes : paupiere de la couleur de la peau et ligne des cils }
Function CloseEyes(Var S:TScene;Var Msg:AnsiString):Boolean;
Var
 H:THeadInfo;
 Yl:PSingle;
 Ir:Array[0..1]of TIris;
 Side,X,Y,C,Found:LongInt;
 K:Int64;
 Lskin,Cx,Cy,R,Sr,Sg,Sb,Nd,Wf,Dxn,Yl2,Cov,Shade,Th:Single;
Begin
 CloseEyes:=False;
 Msg:='';
 If not HeadInfo(S,H)Then Begin
   Msg:='aucun visage d'#130'tect'#130' : impossible de fermer les yeux';
   Exit;End;
 If H.Fw<60 Then Begin Msg:=
   'le visage est trop petit pour fermer les yeux (60 pixels de large '+
   'minimum)';Exit;End;
 ColorInit;
 Yl:=LumaPlane(S);
 Found:=FindIrises(S,H,Yl,Ir,Lskin);
 FreeMem(Yl);
 If Found=0 Then Begin Msg:=
   'yeux non d'#130'tect'#130's (d'#130'j'#133' ferm'#130's ou photo trop '+
   'sombre)';Exit;End;
 FaceSkin(S,H,Sr,Sg,Sb);
 For Side:=0 to 1 do Begin
  If not Ir[Side].Ok Then Continue;
  Cx:=Ir[Side].Cx;Cy:=Ir[Side].Cy;R:=Ir[Side].R;
  For Y:=Trunc(Cy-1.8*R)to Trunc(Cy+1.8*R)do
   For X:=Trunc(Cx-2.6*R)to Trunc(Cx+2.6*R)do Begin
    If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Continue;
    K:=Int64(Y)*S.W+X;
    Nd:=Sqrt(Sqr((X+0.5-Cx)/(2.25*R))+Sqr((Y+0.5-Cy+0.05*R)/(1.35*R)));
    Wf:=1-SmoothStep(0.72,1.05,Nd);
    If Wf>0.003 Then Begin
     Shade:=1-0.05*(Y+0.5-Cy)/(1.35*R);
     S.Pix[K*3]:=S.Pix[K*3]*(1-Wf)+Sr*Shade*Wf;
     S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-Wf)+Sg*Shade*Wf;
     S.Pix[K*3+2]:=S.Pix[K*3+2]*(1-Wf)+Sb*Shade*Wf;
    End;
    { ligne des cils : arc qui descend au centre }
    Dxn:=(X+0.5-Cx)/(2.05*R);
    If Abs(Dxn)<1 Then Begin
     Yl2:=Cy+0.12*R+0.42*R*(1-Dxn*Dxn);
     Th:=FMax(0.10*R,0.8);
     Cov:=CoverD(Abs(Y+0.5-Yl2)-Th)*(1-SmoothStep(0.80,1.0,Abs(Dxn)));
     If Cov>0.003 Then Begin
      S.Pix[K*3]:=S.Pix[K*3]*(1-Cov)+(0.30*Sr)*Cov;
      S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-Cov)+(0.22*Sg)*Cov;
      S.Pix[K*3+2]:=S.Pix[K*3+2]*(1-Cov)+(0.20*Sb)*Cov;
     End;
     { ombre de la paupiere au-dessus de la ligne }
     Cov:=0.30*Exp(-Sqr((Y+0.5-(Yl2-0.55*R))/(0.55*R)))*(1-SmoothStep(0.55,
       1.0,Abs(Dxn)));
     If(Cov>0.003)and(Y+0.5<Yl2)Then Begin
      S.Pix[K*3]:=S.Pix[K*3]*(1-Cov)+(0.74*Sr)*Cov;
      S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-Cov)+(0.70*Sg)*Cov;
      S.Pix[K*3+2]:=S.Pix[K*3+2]*(1-Cov)+(0.70*Sb)*Cov;
     End;
    End;
   End;
 End;
 CloseEyes:=True;
 Info('  yeux ferm'#130's ('+IStr(Found)+' sur 2 d'#130'tect'#130's)');
End;

{ tete droite : la ligne des yeux est remise a l'horizontale (rotation autour du
  cou) }
Function HeadStraight(Var S:TScene;Var Msg:AnsiString):Boolean;
Var
 H:THeadInfo;
 N:int64;K:LongInt;
 Yl,Wm,Known,Orig:PSingle;
 Ir:Array[0..1]of TIris;
 Mk:PByte;
 CatO:Array[0..NumCat-1]of PByte;
 X,Y,C,Ix,Iy,Mv:LongInt;
 Th,Cd,Sd,Pvx,Pvy,Rx,Ry,Sx,Sy,Wc,Wv:Double;
 Lskin:Single;
 Px:Array[0..2]of Single;
 HeadSet:LongWord;
Begin
 HeadStraight:=False;
 Msg:='';
 If not HeadInfo(S,H)Then Begin Msg:=
   'aucun visage d'#130'tect'#130' : impossible de redresser la t'#136'te';
   Exit;End;
 If H.Fw<60 Then Begin Msg:=
   'le visage est trop petit pour redresser la t'#136'te (60 pixels de '+
   'large minimum)';Exit;End;
 ColorInit;
 Yl:=LumaPlane(S);
 FindIrises(S,H,Yl,Ir,Lskin);
 FreeMem(Yl);
 If not(Ir[0].Ok and Ir[1].Ok)Then Begin Msg:=
   'les deux yeux sont n'#130'cessaires pour mesurer l''inclinaison de la t'+
   #136'te';Exit;End;
 Th:=ATan2F(Ir[1].Cy-Ir[0].Cy,Ir[1].Cx-Ir[0].Cx);
 If Abs(Th)*180/Pi<1.5 Then Begin Msg:=
   'la t'#136'te est d'#130'j'#133' droite (inclinaison de moins de 1,5 '+
   'degr'#130's)';Exit;End;
 If Abs(Th)*180/Pi>35 Then Begin
   Msg:='inclinaison de la t'#136'te trop forte pour '#136'tre corrig'#130'e';
   Exit;End;
 N:=Int64(S.W)*S.H;
 HeadSet:=msFace or msHair or msHat or msGlasses;
 Pvx:=H.Cx;Pvy:=H.Fy1+0.05*H.Fh;
 Wm:=AllocF(N);
 CatMask(S,HeadSet,Wm);
 For Y:=0 to S.H-1 do Begin
  Wv:=1-SmoothStep(Pvy-0.18*H.Fh,Pvy+0.05*H.Fh,Y+0.5);
  For X:=0 to S.W-1 do Wm[Int64(Y)*S.W+X]:=Wm[Int64(Y)*S.W+X]*Wv;
 End;
 Orig:=AllocF(N*3);
 Move(S.Pix^,Orig^,N*12);
 For C:=0 to NumCat-1 do Begin
  CatO[C]:=PByte(AllocBytes(N));
  Move(S.Cat[C]^,CatO[C]^,N);
 End;
 { la tete est retiree, la zone liberee est comblee par propagation }
 Mk:=PByte(AllocBytes(N));Known:=AllocF(N);
 For K:=0 to N-1 do If Wm[K]>0.3 Then Mk[K]:=255;
 MorphMask(Mk,S.W,S.H,2,False);
 For K:=0 to N-1 do If Mk[K]=0 Then Known[K]:=1;
 PushPullFill(S.Pix,Known,S.W,S.H);
 For K:=0 to N-1 do If Mk[K]<>0 Then Begin
  For C:=0 to NumCat-1 do S.Cat[C][K]:=0;
  S.Cat[cBg][K]:=255;
 End;
 FreeMem(Known);FreeMem(Mk);
 { la tete tourne autour du cou }
 Cd:=Cos(Th);Sd:=Sin(Th);
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   Rx:=X+0.5-Pvx;Ry:=Y+0.5-Pvy;
   Sx:=Pvx+Rx*Cd-Ry*Sd;Sy:=Pvy+Rx*Sd+Ry*Cd;
   If(Sx<0)or(Sy<0)or(Sx>=S.W)or(Sy>=S.H)Then Continue;
   Ix:=Trunc(Sx);Iy:=Trunc(Sy);
   Wc:=Wm[Int64(Iy)*S.W+Ix];
   If Wc<=0.02 Then Continue;
   K:=Int64(Y)*S.W+X;
   SampleBilinear(Orig,S.W,S.H,3,Sx,Sy,@Px[0]);
   For C:=0 to 2 do S.Pix[K*3+C]:=S.Pix[K*3+C]*(1-Wc)+Px[C]*Wc;
   For C:=0 to NumCat-1 do Begin
    Mv:=Trunc(S.Cat[C][K]*(1-Wc)+0.5);
    If(HeadSet and(LongWord(1)shl C))<>0 Then
     Mv:=Mv+Trunc(CatO[C][Int64(Iy)*S.W+Ix]*(1-SmoothStep(Pvy-0.18*H.Fh,Pvy+
       0.05*H.Fh,Sy))+0.5);
    If Mv>255 Then Mv:=255;
    S.Cat[C][K]:=Mv;
   End;
  End;
 FreeMem(Orig);FreeMem(Wm);
 For C:=0 to NumCat-1 do FreeMem(CatO[C]);
 HeadStraight:=True;
 Info('  t'#136'te redress'#130'e ('+FStr(Th*180/Pi,1)+' degr'#130's)');
End;

{ aureole : anneau dore lumineux au-dessus de la tete }
Function ApplyHalo(Var S:TScene;Var Msg:AnsiString):Boolean;
Var
 H:THeadInfo;
 X,Y,C,Ytop,Need,X0,X1,Y0,Y1:LongInt;
 K:Int64;
 Cx,Cy,Rx,Ry,Th,E,Ed,V,Cov,Glow,R,G,B,Al:Single;
Begin
 ApplyHalo:=False;
 Msg:='';
 If not HeadInfo(S,H)Then Begin Msg:=
   'aucun visage d'#130'tect'#130' : impossible de placer une aur'#130'ole';
   Exit;End;
 If not CatBBox(S,msFace or msHair or msHat,X0,Y0,X1,Y1)Then Begin
   Msg:='t'#136'te non d'#130'tect'#130'e';Exit;End;
 ColorInit;
 Ytop:=Y0;
 Rx:=0.60*FMax(H.Fw,0.6*(X1-X0+1));
 Ry:=0.22*Rx;
 Th:=FMax(0.060*Rx,1.8);
 Cx:=H.Cx;
 Cy:=Ytop-0.30*Ry-0.02*H.Fh;
 Need:=Trunc(Ry+Th*2+0.45*Rx+4-Cy);
 If Need>0 Then Begin
  GrowEdges(S,0,Need,0,0);
  Cy:=Cy+Need;
 End;
 ColorInit;
 Ed:=0;
 For Y:=Trunc(Cy-Ry-0.75*Rx)to Trunc(Cy+Ry+0.75*Rx)do
  For X:=Trunc(Cx-Rx-0.75*Rx)to Trunc(Cx+Rx+0.75*Rx)do Begin
   If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Continue;
   K:=Int64(Y)*S.W+X;
   { distance au contour de l'ellipse (approx.) }
   E:=Sqrt(Sqr((X+0.5-Cx)/Rx)+Sqr((Y+0.5-Cy)/Ry));
   Ed:=Abs(E-1)*Ry;
   { lueur autour de l'anneau }
   Glow:=0.85*Exp(-Sqr(Ed/(0.17*Rx)));
   If Glow>0.01 Then Begin
    S.Pix[K*3]:=S.Pix[K*3]+(255-S.Pix[K*3])*Glow*0.75;
    S.Pix[K*3+1]:=S.Pix[K*3+1]+(236-S.Pix[K*3+1])*Glow*0.75;
    S.Pix[K*3+2]:=S.Pix[K*3+2]+(150-S.Pix[K*3+2])*Glow*0.55;
   End;
   { anneau : le dessus est cache par la tete, le devant ne l'est pas }
   Cov:=CoverD(Ed-Th);
   If Cov>0.003 Then Begin
    V:=MetalV(Clamp(0.5+(Y+0.5-Cy)/(2*Ry)*0.8+(X+0.5-Cx)/Rx*0.12,0,1));
    MetalRamp(RgbOf(255,214,96),Clamp(V*0.95+0.12,0,1),R,G,B);
    Al:=1-S.Cat[cBg][K]/255.0;
    If Y+0.5<Cy Then Cov:=Cov*(1-SmoothStep(0.15,0.85,Al));
    S.Pix[K*3]:=S.Pix[K*3]*(1-Cov)+R*Cov;
    S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-Cov)+G*Cov;
    S.Pix[K*3+2]:=S.Pix[K*3+2]*(1-Cov)+B*Cov;
    For C:=0 to NumCat-1 do S.Cat[C][K]:=Trunc(S.Cat[C][K]*(1-Cov)+0.5);
    S.Cat[cOther][K]:=ClampI(S.Cat[cOther][K]+Trunc(Cov*255+0.5),0,255);
   End;
  End;
 ApplyHalo:=True;
 Info('  aur'#130'ole ajout'#130'e');
End;
{ ------------------------------------------------------------------ }
{ Bras et mains dessines par le programme : croises, main en V,       }
{ doigt pointe, bras ecartes ou leves, bras tendus                    }
{ ------------------------------------------------------------------ }

Const
 hkFist=0;hkPeace=1;hkPoint=2;hkOpen=3;hkFlat=4;
 apCross=1;apPeace=2;apPoint=3;apOut=4;apUp=5;apForward=6;apLean=7;

Type
 TBody=Record
  Cx,Half,Sy,Hem,U,Sho:Single;
  Ty0,Ty1:LongInt;
  HasFace:Boolean;
  Hd:THeadInfo;
  Sk,Sl:Array[0..2]of Single;
  SleeveEnd:Single;
 End;
 TPaint=Record
  Sk,Sl:Array[0..2]of Single;
  SEnd,T0,T1:Single;
 End;
 TArm=Record
  Used,Keep:Boolean;               { Keep : le haut du bras d'origine est
    conserve }
  Sg:LongInt;
  Sx,Sy,Ex,Ey,Wx,Wy:Single;
  Hand:LongInt;
  Hdx,Hdy,Hsz:Single;
  R0,R1,R2:Single;                 { rayons : epaule, coude, poignet }
  PadX:Single;                     { place supplementaire a prevoir du cote Sg }
 End;
 TArmSet=Array[0..1]of TArm;

{ situe le corps : axe, epaules, unite de longueur (hauteur du visage), couleurs
  }
Function GetBody(Var S:TScene;Var B:TBody;Var Msg:AnsiString):Boolean;
Var
 Tx0,Ty0,Tx1,Ty1,X,Y,Tl,Tr,Cn:LongInt;
 N,Na,Ns:int64;K:LongInt;
 Sr,Sg,Sb:Double;
 Fr,Fg,Fb:Single;
 Ys:LongInt;
 Hy:Array of LongInt;
Begin
 GetBody:=False;
 Msg:='';
 ColorInit;
 N:=Int64(S.W)*S.H;
 B.HasFace:=HeadInfo(S,B.Hd)and(B.Hd.Fw>=24);
 If CatBBox(S,msTop or msDress,Tx0,Ty0,Tx1,Ty1)Then Begin
  B.Cx:=(Tx0+Tx1+1)/2;B.Half:=(Tx1-Tx0+1)/2;
  Y:=Ty0+((Ty1-Ty0)*80)div 100;
  Tl:=S.W;Tr:=-1;
  For X:=0 to S.W-1 do If(S.Cat[cTop][Int64(Y)*S.W+X]+S.Cat[cDress][Int64(Y)
    *S.W+X])>=128 Then Begin
   If X<Tl Then Tl:=X;
   If X>Tr Then Tr:=X;
  End;
  If Tr>Tl Then Begin B.Cx:=(Tl+Tr+1)/2;B.Half:=(Tr-Tl+1)/2;End;
 End
  Else If B.HasFace Then Begin
   B.Cx:=B.Hd.Cx;B.Half:=1.15*B.Hd.Fh;
   Ty0:=Trunc(B.Hd.Fy1+0.40*B.Hd.Fh);Ty1:=Ty0+Trunc(3.0*B.Hd.Fh);
  End
   Else Begin Msg:=
     'aucun haut ni visage d'#130'tect'#130' : impossible de situer le '+
     'corps';Exit;End;
 If B.HasFace Then Begin
  B.U:=B.Hd.Fh;
  If(B.Half<0.7*B.U)or(B.Half>2.2*B.U)Then B.U:=B.Half/1.15;
 End
  Else B.U:=B.Half/1.15;
 { l'axe du visage est plus fiable que celui du bas du haut (objets devant le
   torse) }
 If B.HasFace and((Abs(B.Hd.Cx-B.Cx)>0.45*B.U)or(B.Half<0.7*B.U))Then Begin
  If(B.Hd.Cx>Tx0)and(B.Hd.Cx<Tx1)Then Begin
   B.Cx:=B.Hd.Cx;
   B.Half:=0.80*FMin(B.Cx-Tx0,Tx1-B.Cx);
   If B.Half<0.9*B.U Then B.Half:=0.9*B.U;
   If B.Half>1.5*B.U Then B.Half:=1.5*B.U;
  End;
 End;
 If B.U<12 Then Begin Msg:=
   'personne trop petite pour dessiner les bras (visage de moins de 12 '+
   'pixels)';Exit;End;
 B.Ty0:=Ty0;B.Ty1:=Ty1;
 B.Sy:=Ty0+0.45*B.U;
 If B.HasFace Then B.Sy:=FMax(B.Sy,B.Hd.Fy1+0.65*B.U);
 B.Hem:=Ty1;
 B.Sho:=Clamp(B.Half*0.88,0.85*B.U,1.25*B.U);
 { couleurs : peau (bras, sinon visage) et manche (haut hors du torse) }
 If SkinColor(S,True,Fr,Fg,Fb)Then Begin B.Sk[0]:=Fr;B.Sk[1]:=Fg;B.Sk[2]:=Fb;End
 Else If B.HasFace Then FaceSkin(S,B.Hd,B.Sk[0],B.Sk[1],B.Sk[2])
 Else Begin B.Sk[0]:=205;B.Sk[1]:=160;B.Sk[2]:=135;End;
 Sr:=0;Sg:=0;Sb:=0;Cn:=0;Ns:=0;
 For Y:=Ty0 to Ty1 do
  For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   If(S.Cat[cTop][K]+S.Cat[cDress][K])<200 Then Continue;
   If Abs(X+0.5-B.Cx)>0.8*B.Half Then Begin Sr:=Sr+S.Pix[K*3];Sg:=Sg+S.Pix[K*3+
     1];Sb:=Sb+S.Pix[K*3+2];Inc(Cn);End;
  End;
 If Cn<30 Then Begin
  Cn:=0;Sr:=0;Sg:=0;Sb:=0;
  For K:=0 to N-1 do If(S.Cat[cTop][K]+S.Cat[cDress][K])>=200 Then Begin
    Sr:=Sr+S.Pix[K*3];Sg:=Sg+S.Pix[K*3+1];Sb:=Sb+S.Pix[K*3+2];Inc(Cn);End;
 End;
 If Cn>=30 Then Begin B.Sl[0]:=Sr/Cn;B.Sl[1]:=Sg/Cn;B.Sl[2]:=Sb/Cn;End
 Else Begin B.Sl[0]:=B.Sk[0];B.Sl[1]:=B.Sk[1];B.Sl[2]:=B.Sk[2];End;
 { longueur des manches : la peau des bras commence plus ou moins bas (hors cou
   et torse) }
 Na:=0;Ns:=0;
 SetLength(Hy,S.H);
 For Y:=0 to S.H-1 do Hy[Y]:=0;
 For Y:=Trunc(B.Sy+0.3*B.U)to S.H-1 do
  For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   If(S.Cat[cArms][K]>=128)and(Abs(X+0.5-B.Cx)>0.55*B.Half)Then Begin
     Inc(Hy[Y]);Inc(Na);End
   Else If(S.Cat[cTop][K]>=128)and(Abs(X+0.5-B.Cx)>B.Half*1.0)Then Inc(Ns);
  End;
 If Na<Trunc(B.U*B.U*0.15)Then Begin
  { aucune peau de bras visible : manches longues, ou bras hors cadre }
  B.SleeveEnd:=0.92;
 End
  Else Begin
   Ns:=0;Ys:=0;
   For Y:=0 to S.H-1 do Begin
    Ns:=Ns+Hy[Y];
    If Ns>=Na*4 div 100 Then Begin Ys:=Y;Break;End;
   End;
   B.SleeveEnd:=Clamp((Ys-B.Sy)/(3.1*B.U),0,0.95);
  End;
 Detail('  corps : axe '+FStr(B.Cx,0)+', demi-largeur '+FStr(B.Half,0)
   +', unit'#130' '+FStr(B.U,0)+', '#130'paules y='+FStr(B.Sy,0)+
   ', manches '+FStr(B.SleeveEnd,2));
 GetBody:=True;
End;

{ ---- dessin ---- }

Procedure PaintPix(Var S:TScene;X,Y:LongInt;Cov,R,G,B:Single;CatIdx:LongInt);
Var
 K:Int64;
 C,Mv:LongInt;
Begin
 If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Exit;
 If Cov<=0.003 Then Exit;
 If Cov>1 Then Cov:=1;
 K:=Int64(Y)*S.W+X;
 If R>255 Then R:=255;If G>255 Then G:=255;If B>255 Then B:=255;
 S.Pix[K*3]:=S.Pix[K*3]*(1-Cov)+R*Cov;
 S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-Cov)+G*Cov;
 S.Pix[K*3+2]:=S.Pix[K*3+2]*(1-Cov)+B*Cov;
 If CatIdx>=0 Then Begin
  For C:=0 to NumCat-1 do S.Cat[C][K]:=Trunc(S.Cat[C][K]*(1-Cov)+0.5);
  Mv:=S.Cat[CatIdx][K]+Trunc(Cov*255+0.5);
  If Mv>255 Then Mv:=255;
  S.Cat[CatIdx][K]:=Mv;
 End;
End;

{ membre en forme de capsule, eclaire en haut a gauche ; manche puis peau selon
  le parametre T }
Procedure DrawCapsule(Var S:TScene;X0,Y0,X1,Y1,R0,R1:Single;Const P:TPaint);
Var
 X,Y,Xa,Xb,Ya,Yb,CatIdx:LongInt;
 Dx,Dy,L,Nx,Ny,Vx,Vy,T,Qx,Qy,D,Rr,Cov,U,Nz,Dt,Sh,Tt,Mixs,R,G,B,Cuff:Single;
Begin
 Dx:=X1-X0;Dy:=Y1-Y0;
 L:=Sqrt(Dx*Dx+Dy*Dy);
 If L<0.001 Then Begin Dx:=0;Dy:=1;L:=0.001;End Else Begin Dx:=Dx/L;Dy:=Dy/L;
   End;
 Nx:=-Dy;Ny:=Dx;
 Rr:=FMax(R0,R1);
 Xa:=Trunc(FMin(X0,X1)-Rr-2);Xb:=Trunc(FMax(X0,X1)+Rr+2);
 Ya:=Trunc(FMin(Y0,Y1)-Rr-2);Yb:=Trunc(FMax(Y0,Y1)+Rr+2);
 For Y:=Ya to Yb do
  For X:=Xa to Xb do Begin
   Vx:=X+0.5-X0;Vy:=Y+0.5-Y0;
   T:=Vx*Dx+Vy*Dy;
   If L>0.002 Then T:=T/L Else T:=0;
   If T<0 Then T:=0 Else If T>1 Then T:=1;
   Qx:=X0+Dx*L*T;Qy:=Y0+Dy*L*T;
   Rr:=R0+(R1-R0)*T;
   D:=Sqrt(Sqr(X+0.5-Qx)+Sqr(Y+0.5-Qy));
   Cov:=CoverD(D-Rr);
   If Cov<=0.003 Then Continue;
   U:=((X+0.5-Qx)*Nx+(Y+0.5-Qy)*Ny)/Rr;
   If U>1 Then U:=1 Else If U<-1 Then U:=-1;
   Nz:=Sqrt(1-U*U);
   { normale (U*N, Nz) ; lumiere (-0,5 ; -0,6 ; 0,62) }
   Dt:=-0.5*U*Nx-0.6*U*Ny+0.62*Nz;
   If Dt<0 Then Dt:=0;
   Sh:=(0.50+0.62*Dt)/0.90;
   Tt:=P.T0+(P.T1-P.T0)*T;
   Mixs:=SmoothStep(P.SEnd-0.015,P.SEnd+0.015,Tt);
   Sh:=Sh*(1+0.045*(VNoise(X*0.45,Y*0.45)-0.5)*(1-Mixs)+0.02*(VNoise(X*0.9+9,
     Y*0.9)-0.5));
   R:=(P.Sl[0]*(1-Mixs)+P.Sk[0]*Mixs)*Sh;
   G:=(P.Sl[1]*(1-Mixs)+P.Sk[1]*Mixs)*Sh;
   B:=(P.Sl[2]*(1-Mixs)+P.Sk[2]*Mixs)*Sh;
   { poignet de manche : leger trait sombre }
   If(P.SEnd>0.02)and(P.SEnd<0.99)Then Begin
    Cuff:=0.22*Exp(-Sqr((Tt-P.SEnd)/0.018));
    R:=R*(1-Cuff);G:=G*(1-Cuff);B:=B*(1-Cuff);
   End;
   If Mixs<0.5 Then CatIdx:=cTop Else CatIdx:=cArms;
   PaintPix(S,X,Y,Cov,R,G,B,CatIdx);
  End;
End;

{ main : le poignet est en (Hx,Hy), les doigts vont dans la direction (Dx,Dy),
  Sz = longueur de la main }
Procedure DrawHand(Var S:TScene;Kind:LongInt;Hx,Hy,Dx,Dy,Sz:Single;Const
  Base:TPaint);
Var
 P:TPaint;
 Px,Py:Single;
 Procedure Seg(A0,B0,A1,B1,R0,R1:Single);
 Var
  X0,Y0,X1,Y1:Single;
 Begin
  X0:=Hx+A0*Sz*Dx-B0*Sz*Dy;Y0:=Hy+A0*Sz*Dy+B0*Sz*Dx;
  X1:=Hx+A1*Sz*Dx-B1*Sz*Dy;Y1:=Hy+A1*Sz*Dy+B1*Sz*Dx;
  DrawCapsule(S,X0,Y0,X1,Y1,R0*Sz,R1*Sz,P);
 End;
Begin
 P:=Base;P.SEnd:=0;P.T0:=0;P.T1:=1;
 Px:=0;Py:=0;
 Case Kind of
  hkFist:Begin
   Seg(0.04,0,0.38,0,0.20,0.23);
   Seg(0.40,-0.15,0.50,-0.15,0.075,0.075);
   Seg(0.42,-0.05,0.53,-0.05,0.075,0.075);
   Seg(0.42,0.05,0.53,0.05,0.075,0.075);
   Seg(0.40,0.15,0.49,0.15,0.07,0.07);
   Seg(0.20,-0.20,0.46,-0.12,0.07,0.07);
  End;
  hkPeace:Begin
   Seg(0.04,0,0.36,0,0.21,0.23);
   Seg(0.38,0.15,0.46,0.15,0.07,0.07);
   Seg(0.37,0.23,0.43,0.23,0.06,0.06);
   Seg(0.36,-0.07,0.70,-0.19,0.066,0.060);
   Seg(0.36,0.07,0.70,0.19,0.066,0.060);
   Seg(0.14,-0.22,0.38,0.10,0.07,0.065);
  End;
  hkPoint:Begin
   Seg(0.04,0,0.36,0,0.20,0.22);
   Seg(0.38,0.00,0.52,0.00,0.07,0.07);
   Seg(0.38,0.10,0.48,0.10,0.07,0.07);
   Seg(0.37,0.19,0.46,0.19,0.06,0.06);
   Seg(0.36,-0.09,0.96,-0.09,0.068,0.058);
   Seg(0.16,-0.20,0.42,-0.14,0.07,0.065);
  End;
  hkOpen:Begin
   Seg(0.04,0,0.38,0,0.21,0.23);
   Seg(0.38,-0.15,0.70,-0.26,0.063,0.055);
   Seg(0.40,-0.05,0.80,-0.09,0.066,0.056);
   Seg(0.40,0.05,0.82,0.09,0.066,0.056);
   Seg(0.38,0.14,0.70,0.26,0.060,0.052);
   Seg(0.10,-0.21,0.40,-0.48,0.075,0.062);
  End;
  Else Begin
   { main vue de face, a plat : plus large, les doigts serres }
   Seg(0.04,0,0.42,0,0.26,0.28);
   Seg(0.44,-0.17,0.64,-0.17,0.075,0.07);
   Seg(0.45,-0.06,0.68,-0.06,0.078,0.072);
   Seg(0.45,0.06,0.68,0.06,0.078,0.072);
   Seg(0.44,0.17,0.62,0.17,0.07,0.065);
   Seg(0.16,-0.27,0.40,-0.30,0.08,0.07);
  End;
 End;
End;

{ ---- retrait des bras d'origine ---- }

{ le bras du cote Side (-1 gauche de l'image, 1 droite, 0 les deux) est efface
  sous la ligne YKeep }
Procedure RemoveArm(Var S:TScene;Const B:TBody;Side:LongInt;YKeep:Single);
Var
 N:int64;K:LongInt;
 X,Y,C,Sd:LongInt;
 Mk:PByte;
 Kn,Pt,Kt:PSingle;
 Inb:Boolean;
Begin
 N:=Int64(S.W)*S.H;
 Mk:=PByte(AllocBytes(N));Kn:=AllocF(N);
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   If Y+0.5<=YKeep Then Continue;
   If Y+0.5<B.Sy-0.30*B.U Then Continue;
   If X+0.5<B.Cx Then Sd:=-1 Else Sd:=1;
   If(Side<>0)and(Sd<>Side)Then Continue;
   K:=Int64(Y)*S.W+X;
   If(S.Cat[cArms][K]>=128)or((S.Cat[cTop][K]>=128)and(Abs(X+0.5-B.Cx)
     >B.Half*0.98))Then Mk[K]:=255;
  End;
 MorphMask(Mk,S.W,S.H,2,False);
 For K:=0 to N-1 do If Mk[K]=0 Then Kn[K]:=1;
 { la zone du torse est comblee avec la matiere du haut, le reste avec le fond }
 Pt:=AllocF(N*3);Kt:=AllocF(N);
 Move(S.Pix^,Pt^,N*12);
 For K:=0 to N-1 do If(Mk[K]=0)and((S.Cat[cTop][K]+S.Cat[cDress][K])>=200)
   Then Kt[K]:=1;
 PushPullFill(S.Pix,Kn,S.W,S.H);
 PushPullFill(Pt,Kt,S.W,S.H);
 For Y:=Trunc(B.Ty0)to IMin(S.H-1,B.Ty1)do
  For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   If(Mk[K]<>0)and(Abs(X+0.5-B.Cx)<=B.Half)Then For C:=0 to 2 do S.Pix[K*3+
     C]:=Pt[K*3+C];
  End;
 FreeMem(Pt);FreeMem(Kt);
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   If Mk[K]=0 Then Continue;
   Inb:=(Abs(X+0.5-B.Cx)<=B.Half)and(Y>=B.Ty0)and(Y<=B.Ty1);
   For C:=0 to NumCat-1 do S.Cat[C][K]:=0;
   If Inb Then S.Cat[cTop][K]:=255 Else S.Cat[cBg][K]:=255;
  End;
 FreeMem(Mk);FreeMem(Kn);
End;

{ les bras pendent-ils le long du corps (cote Side) ? axe moyen presque
  vertical, hors du torse }
Function ArmHangs(Const S:TScene;Const B:TBody;Side:LongInt):Boolean;
Var
 X,Y:LongInt;
 K,Cnt:Int64;
 Mx,My,Sxx,Sxy,Syy,Th:Double;
Begin
 ArmHangs:=False;
 Mx:=0;My:=0;Cnt:=0;
 For Y:=Trunc(B.Sy)to S.H-1 do
  For X:=0 to S.W-1 do Begin
   If(X+0.5<B.Cx)<>(Side<0)Then Continue;
   K:=Int64(Y)*S.W+X;
   If(S.Cat[cArms][K]>=128)or((S.Cat[cTop][K]>=128)and(Abs(X+0.5-B.Cx)
     >B.Half*0.98))Then Begin Mx:=Mx+X;My:=My+Y;Inc(Cnt);End;
  End;
 If Cnt<Trunc(B.U*B.U*0.8)Then Exit;
 Mx:=Mx/Cnt;My:=My/Cnt;
 Sxx:=0;Sxy:=0;Syy:=0;
 For Y:=Trunc(B.Sy)to S.H-1 do
  For X:=0 to S.W-1 do Begin
   If(X+0.5<B.Cx)<>(Side<0)Then Continue;
   K:=Int64(Y)*S.W+X;
   If(S.Cat[cArms][K]>=128)or((S.Cat[cTop][K]>=128)and(Abs(X+0.5-B.Cx)
     >B.Half*0.98))Then Begin
    Sxx:=Sxx+(X-Mx)*(X-Mx);Sxy:=Sxy+(X-Mx)*(Y-My);Syy:=Syy+(Y-My)*(Y-My);
   End;
  End;
 Th:=0.5*ATan2F(2*Sxy,Sxx-Syy);
 ArmHangs:=(Abs(Abs(Th)-Pi/2)*180/Pi<22)and(Abs(Mx-B.Cx)>0.6*B.Half);
End;

{ ---- plans de bras ---- }

Procedure SetArm(Var A:TArm;Const B:TBody;Sg:LongInt;Ex,Ey,Wx,Wy:Single;
  Hand:LongInt;Hsz:Single);
Var
 L:Single;
Begin
 A.Used:=True;A.Keep:=False;A.Sg:=Sg;A.PadX:=0;
 A.Sx:=B.Cx+Sg*B.Sho;A.Sy:=B.Sy;
 A.Ex:=Ex;A.Ey:=Ey;A.Wx:=Wx;A.Wy:=Wy;
 A.Hand:=Hand;
 L:=Sqrt(Sqr(Wx-Ex)+Sqr(Wy-Ey));
 If L<0.001 Then Begin A.Hdx:=0;A.Hdy:=-1;End Else Begin A.Hdx:=(Wx-Ex)/L;
   A.Hdy:=(Wy-Ey)/L;End;
 A.Hsz:=Hsz;
 A.R0:=0.23*B.U;A.R1:=0.19*B.U;A.R2:=0.135*B.U;
End;

{ ajoute (Ang) degres au vecteur (Vx,Vy) }
Procedure PolarDir(Sg:LongInt;AngDeg:Single;Var Dx,Dy:Single);
Begin
 Dx:=Sg*Cos(AngDeg*Pi/180);
 Dy:=-Sin(AngDeg*Pi/180);
End;

Procedure PlanArms(Pose:LongInt;Const B:TBody;Side:LongInt;Var P:TArmSet);
Var
 I,Sg:LongInt;
 U,Dx,Dy,Ex,Ey,Wx,Wy,Tx,Ty,Vl,Vx,Vy:Single;
Begin
 U:=B.U;
 P[0].Used:=False;P[1].Used:=False;
 Case Pose of
  apCross:
   For I:=0 to 1 do Begin
    Sg:=I*2-1;
    Ex:=B.Cx+Sg*(B.Sho+0.05*U);Ey:=B.Sy+1.65*U-0.10*U*(1-I);
    { le poignet se rapproche du cote oppose : la main s'arrete au bord du torse
      }
    Tx:=B.Cx-Sg*0.78*B.Half;Ty:=Ey-0.50*U;
    Vx:=Tx-Ex;Vy:=Ty-Ey;Vl:=Sqrt(Vx*Vx+Vy*Vy);
    Wx:=Tx-Vx/Vl*0.55*U;Wy:=Ty-Vy/Vl*0.55*U;
    SetArm(P[I],B,Sg,Ex,Ey,Wx,Wy,hkFist,0.95*U);
    P[I].Keep:=True;
   End;
  apPeace:Begin
   Sg:=Side;
   Ex:=B.Cx+Sg*(B.Sho+0.80*U);Ey:=B.Sy+1.42*U;
   Wx:=Ex+Sg*0.25*U;Wy:=Ey-1.42*U;
   SetArm(P[0],B,Sg,Ex,Ey,Wx,Wy,hkPeace,1.0*U);
  End;
  apPoint:Begin
   Sg:=Side;
   PolarDir(Sg,16,Dx,Dy);
   Ex:=B.Cx+Sg*B.Sho+Dx*1.65*U;Ey:=B.Sy+Dy*1.65*U;
   PolarDir(Sg,10,Dx,Dy);
   Wx:=Ex+Dx*1.45*U;Wy:=Ey+Dy*1.45*U;
   SetArm(P[0],B,Sg,Ex,Ey,Wx,Wy,hkPoint,1.0*U);
  End;
  apOut:
   For I:=0 to 1 do Begin
    Sg:=I*2-1;
    PolarDir(Sg,-6,Dx,Dy);
    Ex:=B.Cx+Sg*B.Sho+Dx*1.65*U;Ey:=B.Sy+Dy*1.65*U;
    PolarDir(Sg,-9,Dx,Dy);
    Wx:=Ex+Dx*1.45*U;Wy:=Ey+Dy*1.45*U;
    SetArm(P[I],B,Sg,Ex,Ey,Wx,Wy,hkFist,0.95*U);
   End;
  apUp:
   For I:=0 to 1 do Begin
    Sg:=I*2-1;
    PolarDir(Sg,62,Dx,Dy);
    Ex:=B.Cx+Sg*B.Sho+Dx*1.65*U;Ey:=B.Sy+Dy*1.65*U;
    PolarDir(Sg,72,Dx,Dy);
    Wx:=Ex+Dx*1.45*U;Wy:=Ey+Dy*1.45*U;
    SetArm(P[I],B,Sg,Ex,Ey,Wx,Wy,hkOpen,1.0*U);
   End;
  apForward:
   For I:=0 to 1 do Begin
    Sg:=I*2-1;
    Ex:=B.Cx+Sg*(B.Sho+0.12*U);Ey:=B.Sy+1.05*U;
    Wx:=B.Cx+Sg*0.52*B.Sho;Wy:=B.Sy+0.95*U;
    SetArm(P[I],B,Sg,Ex,Ey,Wx,Wy,hkFlat,1.05*U);
    P[I].R0:=0.23*U;P[I].R1:=0.23*U;P[I].R2:=0.21*U;
    P[I].Hdx:=-Sg*0.35;P[I].Hdy:=-0.94;
   End;
  Else Begin
   { appui sur un meuble : le coude repose sur le meuble, la main pres du menton
     }
   Sg:=Side;
   Ex:=B.Cx+Sg*(B.Sho+1.25*U);Ey:=B.Sy+1.30*U;
   Wx:=B.Cx+Sg*0.62*U;Wy:=B.Sy-0.55*U;
   If B.HasFace Then Begin Wx:=B.Cx+Sg*0.46*B.Hd.Fw;Wy:=B.Hd.Fy1+
     0.05*B.Hd.Fh+0.15*U;End;
   SetArm(P[0],B,Sg,Ex,Ey,Wx,Wy,hkFist,0.85*U);
   P[0].PadX:=2.1*U;
  End;
 End;
End;

{ marges necessaires pour contenir les bras et mains (par rapport a l'image) }
Procedure ArmMargins(Const S:TScene;Const B:TBody;Const P:TArmSet;Var L,T,R,
  Bt:LongInt);
Var
 I:LongInt;
 X0,X1,Y0,Y1,Pad:Single;
Begin
 L:=0;T:=0;R:=0;Bt:=0;
 Pad:=0.40*B.U;
 For I:=0 to 1 do If P[I].Used Then Begin
  X0:=FMin(P[I].Ex,P[I].Wx)-Pad;X1:=FMax(P[I].Ex,P[I].Wx)+Pad;
  Y0:=FMin(P[I].Ey,P[I].Wy)-Pad;Y1:=FMax(P[I].Ey,P[I].Wy)+Pad;
  X0:=FMin(X0,P[I].Wx+P[I].Hdx*P[I].Hsz*0.98-Pad);X1:=FMax(X1,P[I].Wx+
    P[I].Hdx*P[I].Hsz*0.98+Pad);
  Y0:=FMin(Y0,P[I].Wy+P[I].Hdy*P[I].Hsz*0.98-Pad);Y1:=FMax(Y1,P[I].Wy+
    P[I].Hdy*P[I].Hsz*0.98+Pad);
  If P[I].Sg>0 Then X1:=FMax(X1,P[I].Ex+P[I].PadX) Else If P[I].PadX>0 Then
    X0:=FMin(X0,P[I].Ex-P[I].PadX);
  If-X0>L Then L:=Trunc(-X0)+1;
  If X1-S.W>R Then R:=Trunc(X1-S.W)+1;
  If-Y0>T Then T:=Trunc(-Y0)+1;
  Bt:=0;
 End;
End;

{ dessine un bras du plan (haut du bras, avant-bras, main) }
Procedure DrawArm(Var S:TScene;Const B:TBody;Const A:TArm);
Var
 Pt:TPaint;
 Lu,Lf,Tm:Single;
Begin
 Pt.Sk:=B.Sk;Pt.Sl:=B.Sl;Pt.SEnd:=B.SleeveEnd;
 Lu:=Sqrt(Sqr(A.Ex-A.Sx)+Sqr(A.Ey-A.Sy));
 Lf:=Sqrt(Sqr(A.Wx-A.Ex)+Sqr(A.Wy-A.Ey));
 If Lu+Lf<1 Then Exit;
 Tm:=Lu/(Lu+Lf);
 If not A.Keep Then Begin
  Pt.T0:=0;Pt.T1:=Tm;
  DrawCapsule(S,A.Sx,A.Sy,A.Ex,A.Ey,A.R0,A.R1,Pt);
 End;
 Pt.T0:=Tm;Pt.T1:=1;
 DrawCapsule(S,A.Ex,A.Ey,A.Wx,A.Wy,A.R1,A.R2,Pt);
 If A.Hand>=0 Then DrawHand(S,A.Hand,A.Wx,A.Wy,A.Hdx,A.Hdy,A.Hsz,Pt);
End;

Var
 LastB:TBody;
 LastP:TArmSet;

{ pose des bras ; Pose = ap... ; Side = cote de l'unique bras (-1 gauche de
  l'image, 1 droite) }
Function ArmPose(Var S:TScene;Pose,Side:LongInt;Const What:AnsiString;Var
  Msg:AnsiString):Boolean;
Var
 B:TBody;
 P:TArmSet;
 L,T,R,Bt,I,Gr:LongInt;
 L2,T2,R2,B2:LongInt;
 Bm:Boolean;
 YK:Single;
Begin
 ArmPose:=False;
 If not GetBody(S,B,Msg)Then Exit;
 PlanArms(Pose,B,Side,P);
 { image trop etroite d'un cote : le fond est prolonge }
 ArmMargins(S,B,P,L,T,R,Bt);
 If(L>0)or(T>0)or(R>0)or(Bt>0)Then Begin
  If(L>S.W)or(R>S.W)or(T>S.H)or(Bt>S.H)Then Begin
   Msg:='image trop petite par rapport '#133' la pose demand'#130'e';
   Exit;
  End;
  GrowEdges(S,L,T,R,Bt);
  If not GetBody(S,B,Msg)Then Exit;
  PlanArms(Pose,B,Side,P);
  Detail('  image agrandie ('+IStr(L)+' g, '+IStr(R)+' d, '+IStr(T)+' h, '+
    IStr(Bt)+' b)');
 End;
 { l'ordre de dessin : le bras de droite (image) d'abord }
 For I:=1 downto 0 do If P[I].Used Then Begin
  If P[I].Keep Then Begin
   If ArmHangs(S,B,P[I].Sg)Then YK:=P[I].Ey Else Begin P[I].Keep:=False;
     YK:=-1;End;
  End
   Else YK:=-1;
  RemoveArm(S,B,P[I].Sg,YK);
 End;
 For I:=1 downto 0 do If P[I].Used Then DrawArm(S,B,P[I]);
 LastB:=B;LastP:=P;
 ArmPose:=True;
 Info('  '+What);
End;
{ ------------------------------------------------------------------ }
{ Situations : decors dessines par le programme autour de la personne }
{ (levitation, saut, couchee, dans un lit, assise a une table...)    }
{ ------------------------------------------------------------------ }

{ silhouette de la personne (arriere-plan < 128) ; faux si trop petite }
Function PersonBounds(Const S:TScene;Var X0,Y0,X1,Y1:LongInt):Boolean;
Var
 X,Y:LongInt;
 Cnt:Int64;
Begin
 X0:=S.W;Y0:=S.H;X1:=-1;Y1:=-1;Cnt:=0;
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do If S.Cat[cBg][Int64(Y)*S.W+X]<128 Then Begin
   If X<X0 Then X0:=X;If X>X1 Then X1:=X;
   If Y<Y0 Then Y0:=Y;If Y>Y1 Then Y1:=Y;
   Inc(Cnt);
  End;
 PersonBounds:=Cnt>=Int64(S.W)*S.H div 100;
End;

{ centre horizontal des pieds (bas de la silhouette) }
Function FeetCenter(Const S:TScene;Y1,X0,X1:LongInt):Single;
Var
 X,Y:LongInt;
 Sx:Double;
 Nx:Int64;
Begin
 Sx:=0;Nx:=0;
 For Y:=IMax(0,Y1-IMax(3,(Y1+1)div 40))to Y1 do
  For X:=0 to S.W-1 do If S.Cat[cBg][Int64(Y)*S.W+X]<128 Then Begin Sx:=Sx+X;
    Inc(Nx);End;
 If Nx>0 Then FeetCenter:=Sx/Nx+0.5 Else FeetCenter:=(X0+X1+1)/2;
End;

{ echantillon d'un plan d'octets, interpolation bilineaire (pixels centres en
  +0,5) }
Function ByteBilinear(P:PByte;W,H:LongInt;X,Y:Single):Single;
Var
 X0,Y0,X1,Y1:LongInt;
 Fx,Fy:Single;
Begin
 X:=X-0.5;Y:=Y-0.5;
 If X<0 Then X:=0;If Y<0 Then Y:=0;
 If X>W-1 Then X:=W-1;If Y>H-1 Then Y:=H-1;
 X0:=Trunc(X);Y0:=Trunc(Y);
 X1:=X0+1;If X1>W-1 Then X1:=W-1;
 Y1:=Y0+1;If Y1>H-1 Then Y1:=H-1;
 Fx:=X-X0;Fy:=Y-Y0;
 ByteBilinear:=(P[Int64(Y0)*W+X0]*(1-Fx)+P[Int64(Y0)*W+X1]*Fx)*(1-Fy)+
   (P[Int64(Y1)*W+X0]*(1-Fx)+P[Int64(Y1)*W+X1]*Fx)*Fy;
End;

{ nouvelle image NW x NH : la personne est mise a l'echelle Sc, tournee (Rot=1 :
  90 degres a gauche)
  et placee (Ox,Oy) ; le reste est de l'arriere-plan (couleur noire, a remplacer
    par CompositeBg) }
Procedure TransformScene(Var S:TScene;NW,NH:LongInt;Sc:Double;Rot:LongInt;Ox,
  Oy:Double);
Var
 N2:Int64;
 NP:PSingle;
 NC:Array[0..NumCat-1]of PByte;
 X,Y,C,A,B,Ss,Cnt:LongInt;
 K:Int64;
 U,V,Sx,Sy,Al,AlSum,Wn:Double;
 Px:Array[0..2]of Single;
 Col:Array[0..2]of Double;
 Cs:Array[0..NumCat-1]of Double;
Begin
 N2:=Int64(NW)*NH;
 NP:=AllocF(N2*3);
 For C:=0 to NumCat-1 do NC[C]:=PByte(AllocBytes(N2));
 If Sc<0.8 Then Ss:=2 Else Ss:=1;
 Wn:=1.0/(Ss*Ss);
 For Y:=0 to NH-1 do
  For X:=0 to NW-1 do Begin
   K:=Int64(Y)*NW+X;
   AlSum:=0;Cnt:=0;
   Col[0]:=0;Col[1]:=0;Col[2]:=0;
   For C:=0 to NumCat-1 do Cs[C]:=0;
   For A:=0 to Ss-1 do
    For B:=0 to Ss-1 do Begin
     U:=X+(A+0.5)/Ss;V:=Y+(B+0.5)/Ss;
     If Rot=0 Then Begin Sx:=(U-Ox)/Sc;Sy:=(V-Oy)/Sc;End
     Else Begin Sy:=(U-Ox)/Sc;Sx:=S.W-(V-Oy)/Sc;End;
     If(Sx<0)or(Sy<0)or(Sx>=S.W)or(Sy>=S.H)Then Continue;
     Al:=1-ByteBilinear(S.Cat[cBg],S.W,S.H,Sx,Sy)/255.0;
     If Al<=0.004 Then Continue;
     SampleBilinear(S.Pix,S.W,S.H,3,Sx,Sy,@Px[0]);
     For C:=0 to 2 do Col[C]:=Col[C]+Px[C]*Al;
     AlSum:=AlSum+Al;
     For C:=1 to NumCat-1 do Cs[C]:=Cs[C]+ByteBilinear(S.Cat[C],S.W,S.H,Sx,Sy);
     Inc(Cnt);
    End;
   If AlSum>0.004 Then Begin
    For C:=0 to 2 do NP[K*3+C]:=Col[C]/AlSum;
    For C:=1 to NumCat-1 do NC[C][K]:=Trunc(Clamp(Cs[C]*Wn+0.5,0,255));
    NC[cBg][K]:=255-Trunc(Clamp(AlSum*Wn*255+0.5,0,255));
   End
    Else NC[cBg][K]:=255;
  End;
 SceneFree(S);
 S.Pix:=NP;
 For C:=0 to NumCat-1 do S.Cat[C]:=NC[C];
 S.W:=NW;S.H:=NH;
End;

{ la personne est posee sur Bg (meme taille) d'apres la carte d'arriere-plan }
Procedure CompositeBg(Var S:TScene;Bg:PSingle);
Var
 N:int64;K:LongInt;
 C:LongInt;
 A:Single;
Begin
 N:=Int64(S.W)*S.H;
 For K:=0 to N-1 do Begin
  A:=SmoothStep(0.18,0.92,1-S.Cat[cBg][K]/255.0);
  For C:=0 to 2 do S.Pix[K*3+C]:=Bg[K*3+C]*(1-A)+S.Pix[K*3+C]*A;
 End;
 FreeMem(Bg);
End;

{ opacite de la personne }
Function PersonAlpha(Const S:TScene):PSingle;
Var
 N:int64;K:LongInt;
 P:PSingle;
Begin
 N:=Int64(S.W)*S.H;
 P:=AllocF(N);
 For K:=0 to N-1 do P[K]:=1-S.Cat[cBg][K]/255.0;
 PersonAlpha:=P;
End;

{ ombre portee douce de la personne sur le decor }
Procedure CastShadow(Const S:TScene;Bg:PSingle;Dx,Dy,Blur,Dark:Single);
Var
 N,K:Int64;
 Al,Bl:PSingle;
 X,Y,Sx,Sy,C:LongInt;
 Sh,A:Single;
Begin
 N:=Int64(S.W)*S.H;
 Al:=PersonAlpha(S);
 Bl:=AllocF(N);
 BoxBlur(Al,Bl,S.W,S.H,IMax(1,Trunc(Blur)));
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   Sx:=X-Trunc(Dx);Sy:=Y-Trunc(Dy);
   If(Sx<0)or(Sy<0)or(Sx>=S.W)or(Sy>=S.H)Then Continue;
   Sh:=Bl[Int64(Sy)*S.W+Sx]*Dark;
   A:=Al[Int64(Y)*S.W+X];
   Sh:=Sh*(1-A);
   If Sh<=0.003 Then Continue;
   K:=Int64(Y)*S.W+X;
   For C:=0 to 2 do Bg[K*3+C]:=Bg[K*3+C]*(1-Sh);
  End;
 FreeMem(Al);FreeMem(Bl);
End;

{ bruit a plusieurs echelles, de 0 a 1 }
Function FBm(X,Y:Single):Single;
Begin
 FBm:=0.55*VNoise(X,Y)+0.30*VNoise(X*2.1+17,Y*2.1+5)+0.15*VNoise(X*4.3+3,
   Y*4.3+29);
End;

{ parquet : lames horizontales (ou verticales) avec joints et fil du bois }
Procedure WoodFloor(Bg:PSingle;W,H,X0,Y0,X1,Y1:LongInt;Plank,Len:Single;
  Base:LongWord);
Var
 X,Y,Idx:LongInt;
 K:Int64;
 Br,Bgn,Bb,Tone,Gr,Edge,Fy,Jx,V,Off:Single;
Begin
 Br:=(Base shr 16)and $FF;Bgn:=(Base shr 8)and $FF;Bb:=Base and $FF;
 For Y:=Y0 to Y1 do
  For X:=X0 to X1 do Begin
   If(X<0)or(Y<0)or(X>=W)or(Y>=H)Then Continue;
   K:=Int64(Y)*W+X;
   Idx:=Trunc((Y+0.5)/Plank);
   Fy:=(Y+0.5)/Plank-Idx;
   Tone:=0.80+0.34*Hash2(Idx,7);
   Off:=Hash2(Idx,3)*Len;
   Jx:=Frac((X+Off)/Len);
   { joint de bout }
   Edge:=0;
   If(Jx*Len<1.6)Then Edge:=0.5;
   If Fy<0.045 Then Edge:=FMax(Edge,0.6);
   If Fy>0.965 Then Edge:=FMax(Edge,0.18);
   Gr:=0.5+0.5*Sin((FBm((X+Off)*0.012,Idx*11.0+Fy*3.0)*9.0+Fy*3.0)*Pi*2);
   V:=Tone*(0.92+0.10*Gr)*(0.94+0.12*FBm((X+Off)*0.05,Y*0.25))*(1-Edge*0.55);
   Bg[K*3]:=Br*V;Bg[K*3+1]:=Bgn*V;Bg[K*3+2]:=Bb*V;
  End;
End;

{ ---- levitation et saut : le sol et l'ombre restent plus bas que les pieds
  ---- }

Function SceneLift(Var S:TScene;LiftF:Single;Const What:AnsiString;Var
  Msg:AnsiString):Boolean;
Var
 X0,Y0,X1,Y1,X,Y,Need,C:LongInt;
 N,K:Int64;
 BodyH,BodyW,Lift,YFeet,Xc,Yg,Yh,Rx,Ry,Fl,Sh,A,Dd:Single;
 Sr,Sg,Sb:Double;
 Cnt:LongInt;
 Fr,Fg,Fb:Single;
 Fv:Array[0..2]of Single;
Begin
 SceneLift:=False;
 Msg:='';
 If not PersonBounds(S,X0,Y0,X1,Y1)Then Begin
   Msg:='aucune personne d'#130'tect'#130'e';Exit;End;
 BodyH:=Y1-Y0+1;BodyW:=X1-X0+1;
 Lift:=LiftF*BodyH;
 YFeet:=Y1+1;
 Yg:=YFeet+Lift;
 Need:=Trunc(Yg+0.09*BodyH+4)-S.H;
 If Need>0 Then GrowEdges(S,0,0,0,Need);
 Xc:=FeetCenter(S,Y1,X0,X1);
 N:=Int64(S.W)*S.H;
 Yh:=YFeet-0.02*BodyH;
 { couleur du sol : le fond au-dessus de l'horizon, assombri }
 Sr:=0;Sg:=0;Sb:=0;Cnt:=0;
 For Y:=IMax(0,Trunc(Yh)-8)to IMax(0,Trunc(Yh)-2)do
  For X:=0 to S.W-1 do If S.Cat[cBg][Int64(Y)*S.W+X]>=240 Then Begin
   K:=Int64(Y)*S.W+X;
   Sr:=Sr+S.Pix[K*3];Sg:=Sg+S.Pix[K*3+1];Sb:=Sb+S.Pix[K*3+2];Inc(Cnt);
  End;
 If Cnt>0 Then Begin Fr:=Sr/Cnt;Fg:=Sg/Cnt;Fb:=Sb/Cnt;End Else Begin Fr:=150;
   Fg:=150;Fb:=155;End;
 Rx:=0.30*FMax(BodyW,0.30*BodyH);Ry:=0.026*BodyH+0.012*Lift;
 For Y:=IMax(0,Trunc(Yh)-6)to S.H-1 do
  For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   A:=S.Cat[cBg][K]/255.0;
   If A<=0.004 Then Continue;
   Fl:=SmoothStep(Yh-3,Yh+3,Y+0.5);
   If Fl>0.003 Then Begin
    Dd:=(1-0.18*SmoothStep(Yh,S.H,Y+0.5))*0.74;
    Fv[0]:=Fr*Dd*1.02;Fv[1]:=Fg*Dd;Fv[2]:=Fb*Dd*0.97;
    For C:=0 to 2 do S.Pix[K*3+C]:=S.Pix[K*3+C]*(1-Fl*A)+Fv[C]*Fl*A;
   End;
   { ombre sous le corps }
   Dd:=Sqr((X+0.5-Xc)/Rx)+Sqr((Y+0.5-Yg-0.01*BodyH)/Ry);
   Sh:=0.58*Exp(-Dd*1.7);
   If Sh>0.004 Then For C:=0 to 2 do S.Pix[K*3+C]:=S.Pix[K*3+C]*(1-Sh*A);
  End;
 SceneLift:=True;
 Info('  '+What);
End;

{ ---- couchee au sol, ou dans un lit (vue de dessus) ---- }

Function SceneLie(Var S:TScene;Bed:Boolean;Const What:AnsiString;Var
  Msg:AnsiString):Boolean;
Var
 X0,Y0,X1,Y1,NW,NH,X,Y,C,I:LongInt;
 N,K:Int64;
 Bw,Bh,Sc,Lh,Lw,Mh,Xl,Yt,Yc,Ox,Oy,Fx0,Fx1,Fy0,Fy1,Mx0,Mx1,Hx0,Hx1,Xb,V,Cov,Dd,
   Lg,Bump,Sdx,Sdy:Single;
 Bg,Al,Bl:PSingle;
 R,G,B,Cn:Single;
 Fr,Fg,Fb:Single;
Begin
 SceneLie:=False;
 Msg:='';
 If not PersonBounds(S,X0,Y0,X1,Y1)Then Begin
   Msg:='aucune personne d'#130'tect'#130'e';Exit;End;
 ColorInit;
 Bw:=X1-X0+1;Bh:=Y1-Y0+1;
 If Bh<0.9*Bw Then Begin Msg:=
   'la personne doit '#136'tre debout et enti'#138're pour '#136'tre couch'+
   #130'e';Exit;End;
 Sc:=1;
 Mh:=FMax(2.0*Bw,0.50*Bh);
 If Bed Then Begin NW:=Trunc(Bh*1.36);NH:=Trunc(Mh*1.30);End
 Else Begin NW:=Trunc(Bh*1.30);NH:=Trunc(FMax(Bw*2.0,Bh*0.55));End;
 If FMax(NW,NH)>2600 Then Begin Sc:=2600/FMax(NW,NH);NW:=Trunc(NW*Sc);
   NH:=Trunc(NH*Sc);End;
 Lh:=Bh*Sc;Lw:=Bw*Sc;Mh:=Mh*Sc;
 Xl:=(NW-Lh)*0.5;
 Yt:=(NH-Lw)*0.5;
 Ox:=Xl-Y0*Sc;
 Oy:=Yt-(S.W-X1-1)*Sc;
 TransformScene(S,NW,NH,Sc,1,Ox,Oy);
 N:=Int64(S.W)*S.H;
 Yc:=NH*0.5;
 Bg:=AllocF(N*3);
 If not Bed Then Begin
  WoodFloor(Bg,NW,NH,0,0,NW-1,NH-1,0.075*NH,0.55*NW,RgbOf(168,118,74));
  { vignette }
  For Y:=0 to NH-1 do
   For X:=0 to NW-1 do Begin
    K:=Int64(Y)*NW+X;
    Dd:=Sqrt(Sqr((X+0.5)/NW-0.5)*0.9+Sqr((Y+0.5)/NH-0.5)*1.2);
    V:=1-0.45*SmoothStep(0.25,0.75,Dd);
    For C:=0 to 2 do Bg[K*3+C]:=Bg[K*3+C]*V;
   End;
  CastShadow(S,Bg,0.012*Lw,0.025*Lw,0.03*Lw,0.55);
  CompositeBg(S,Bg);
  SceneLie:=True;
  Info('  '+What);
  Exit;
 End;
 { sol }
 WoodFloor(Bg,NW,NH,0,0,NW-1,NH-1,0.06*NH,0.45*NW,RgbOf(150,104,66));
 { cadre de lit }
 Fx0:=Xl-0.115*Lh;Fx1:=Xl+Lh+0.075*Lh;
 Fy0:=Yc-Mh*0.5-0.045*Mh;Fy1:=Yc+Mh*0.5+0.045*Mh;
 Mx0:=Xl-0.085*Lh;Mx1:=Xl+Lh+0.055*Lh;
 { ombre du lit sur le sol }
 For Y:=Trunc(Fy0-0.08*Mh)to Trunc(Fy1+0.10*Mh)do
  For X:=Trunc(Fx0-0.08*Lh)to Trunc(Fx1+0.08*Lh)do Begin
   If(X<0)or(Y<0)or(X>=NW)or(Y>=NH)Then Continue;
   Cov:=0.55*(1-SmoothStep(0,0.07*Mh,RoundRectD(X+0.5,Y+0.5-0.025*Mh,(Fx0+Fx1)
     /2,(Fy0+Fy1)/2,(Fx1-Fx0)/2,(Fy1-Fy0)/2,0.03*Mh)));
   PutBg(Bg,NW,NH,X,Y,Cov,6,4,3);
  End;
 For Y:=Trunc(Fy0)-1 to Trunc(Fy1)+1 do
  For X:=Trunc(Fx0)-1 to Trunc(Fx1)+1 do Begin
   Cov:=CoverD(RoundRectD(X+0.5,Y+0.5,(Fx0+Fx1)/2,(Fy0+Fy1)/2,(Fx1-Fx0)/2,
     (Fy1-Fy0)/2,0.03*Mh));
   If Cov<=0 Then Continue;
   V:=0.78+0.30*FBm(X*0.02,Y*0.2)+0.12*(1-SmoothStep(0,0.05*Mh,-RoundRectD(X+
     0.5,Y+0.5,(Fx0+Fx1)/2,(Fy0+Fy1)/2,(Fx1-Fx0)/2,(Fy1-Fy0)/2,0.03*Mh)));
   PutBg(Bg,NW,NH,X,Y,Cov,98*V,60*V,38*V);
  End;
 { tete de lit }
 Hx0:=Xl-0.165*Lh;Hx1:=Xl-0.105*Lh;
 For Y:=Trunc(Fy0-0.05*Mh)to Trunc(Fy1+0.05*Mh)do
  For X:=Trunc(Hx0)-1 to Trunc(Hx1)+1 do Begin
   Cov:=CoverD(RoundRectD(X+0.5,Y+0.5,(Hx0+Hx1)/2,(Fy0+Fy1)/2,(Hx1-Hx0)/2,
     (Fy1-Fy0)/2+0.05*Mh,0.35*(Hx1-Hx0)));
   If Cov<=0 Then Continue;
   V:=0.62+0.55*Sin((X+0.5-Hx0)/(Hx1-Hx0)*Pi)*0.6+0.18*FBm(X*0.04,Y*0.15);
   PutBg(Bg,NW,NH,X,Y,Cov,92*V,56*V,34*V);
  End;
 { matelas }
 For Y:=Trunc(Yc-Mh*0.5)-2 to Trunc(Yc+Mh*0.5)+2 do
  For X:=Trunc(Mx0)-2 to Trunc(Mx1)+2 do Begin
   Dd:=RoundRectD(X+0.5,Y+0.5,(Mx0+Mx1)/2,Yc,(Mx1-Mx0)/2,Mh*0.5,0.025*Mh);
   Cov:=CoverD(Dd);
   If Cov<=0 Then Continue;
   V:=0.93+0.07*FBm(X*0.03,Y*0.03)-0.16*Exp(Dd/(0.04*Mh));
   PutBg(Bg,NW,NH,X,Y,Cov,242*V,238*V,230*V);
  End;
 { oreiller sous la tete }
 Fx0:=Xl-0.06*Lh;Fx1:=Xl+0.21*Lh;
 For Y:=Trunc(Yc-0.33*Mh)-6 to Trunc(Yc+0.33*Mh)+6 do
  For X:=Trunc(Fx0)-8 to Trunc(Fx1)+8 do Begin
   Dd:=RoundRectD(X+0.5,Y+0.5,(Fx0+Fx1)/2,Yc,(Fx1-Fx0)/2,0.31*Mh,0.10*Mh);
   Cov:=0.30*(1-SmoothStep(0,0.035*Mh,RoundRectD(X+0.5,Y+0.5-0.012*Mh,(Fx0+Fx1)
     /2,Yc,(Fx1-Fx0)/2,0.31*Mh,0.10*Mh)));
   PutBg(Bg,NW,NH,X,Y,Cov,40,36,32);
   Cov:=CoverD(Dd);
   If Cov<=0 Then Continue;
   V:=0.97-0.20*Exp(Dd/(0.05*Mh))+0.06*FBm(X*0.05,Y*0.05)+0.05*Cos((X-Fx0)
     /(Fx1-Fx0)*Pi*2);
   PutBg(Bg,NW,NH,X,Y,Cov,248*V,246*V,240*V);
  End;
 CastShadow(S,Bg,0.006*Lw,0.012*Lw,0.015*Lw,0.40);
 CompositeBg(S,Bg);
 { couverture par-dessus le bas du corps, avec le relief du corps dessous }
 Al:=PersonAlpha(S);
 Bl:=AllocF(N);
 BoxBlur(Al,Bl,NW,NH,IMax(2,Trunc(0.05*Lw)));
 Xb:=Xl+0.37*Lh;
 Sdx:=0.03*Lw;Sdy:=0.03*Lw;
 For Y:=Trunc(Yc-Mh*0.5-0.02*Mh)to Trunc(Yc+Mh*0.5+0.02*Mh)do
  For X:=Trunc(Xb-0.05*Lh)to Trunc(Mx1+0.01*Lh)do Begin
   If(X<0)or(Y<0)or(X>=NW)or(Y>=NH)Then Continue;
   K:=Int64(Y)*NW+X;
   { bord de la couverture : leger debordement sur les cotes }
   Dd:=RoundRectD(X+0.5,Y+0.5,(Xb-0.05*Lh+Mx1+0.01*Lh)/2,Yc,(Mx1+0.01*Lh-Xb+
     0.05*Lh)/2,Mh*0.5+0.02*Mh,0.02*Mh);
   Cov:=CoverD(Dd);
   If Cov<=0 Then Continue;
   If X+0.5<Xb Then Begin
    { drap replie : bande claire }
    V:=0.88+0.12*Cos((X+0.5-(Xb-0.05*Lh))/(0.05*Lh)*Pi)*0.5+0.04*FBm(X*0.04,
      Y*0.04);
    If X+0.5>Xb-0.012*Lh Then V:=V*0.80;
    R:=248*V;G:=244*V;B:=236*V;
   End
    Else Begin
     Bump:=Bl[K];
     If(X+Trunc(Sdx)>=0)and(Y+Trunc(Sdy)>=0)and(X+Trunc(Sdx)<NW)and(Y+
       Trunc(Sdy)<NH)and(X-Trunc(Sdx)>=0)and(Y-Trunc(Sdy)>=0)Then
      Lg:=Bl[Int64(Y+Trunc(Sdy))*NW+X+Trunc(Sdx)]-Bl[Int64(Y-Trunc(Sdy))*NW+
        X-Trunc(Sdx)]
     Else Lg:=0;
     V:=Clamp(0.94+0.08*FBm(X*0.02,Y*0.02)-0.55*Lg+0.05*Bump,0.72,1.10);
     V:=V*(0.94+0.06*Sin(X*0.35+FBm(X*0.03,Y*0.03)*5)*Sin(Y*0.35));
     R:=70*V;G:=102*V;B:=158*V;
     { ombre portee par le drap replie }
     V:=1-0.30*Exp(-Sqr((X+0.5-Xb)/(0.03*Lh)));
     R:=R*V;G:=G*V;B:=B*V;
    End;
   V:=1-0.22*Exp(Dd/(0.05*Mh));
   PutBg(S.Pix,NW,NH,X,Y,Cov,R*V,G*V,B*V);
   For C:=0 to NumCat-1 do S.Cat[C][K]:=0;
   S.Cat[cOther][K]:=255;
  End;
 FreeMem(Al);FreeMem(Bl);
 SceneLie:=True;
 Info('  '+What);
End;
{ ------------------------------------------------------------------ }
{ Situations (suite) : assise a une table, funambule, toit de niche, }
{ escalier, somnambule, appuyee sur un meuble                         }
{ ------------------------------------------------------------------ }

{ degrade vertical dans un rectangle du decor }
Procedure VGradient(Bg:PSingle;W,H,Y0,Y1:LongInt;R0,G0,B0,R1,G1,B1:Single);
Var
 X,Y:LongInt;
 K:Int64;
 T:Single;
Begin
 For Y:=Y0 to Y1 do Begin
  If(Y<0)or(Y>=H)Then Continue;
  If Y1>Y0 Then T:=(Y-Y0)/(Y1-Y0) Else T:=0;
  For X:=0 to W-1 do Begin
   K:=Int64(Y)*W+X;
   Bg[K*3]:=R0+(R1-R0)*T;Bg[K*3+1]:=G0+(G1-G0)*T;Bg[K*3+2]:=B0+(B1-B0)*T;
  End;
 End;
End;

{ nuages doux sur une zone de ciel }
Procedure Clouds(Bg:PSingle;W,H,Y0,Y1:LongInt;Scale,Amount:Single);
Var
 X,Y:LongInt;
 V,T:Single;
Begin
 For Y:=IMax(0,Y0)to IMin(H-1,Y1)do
  For X:=0 to W-1 do Begin
   V:=FBm(X*Scale,Y*Scale*1.8+50);
   T:=SmoothStep(0.52,0.78,V)*Amount*(1-0.5*(Y-Y0)/FMax(1,Y1-Y0));
   PutBg(Bg,W,H,X,Y,T,255,255,255);
  End;
End;

{ ---- assise : a une table, les jambes cachees ---- }

Function SceneSit(Var S:TScene;Const What:AnsiString;Var Msg:AnsiString)
  :Boolean;
Var
 B:TBody;
 X0,Y0,X1,Y1,X,Y,Need,C,Side:LongInt;
 N,K:Int64;
 BodyH,Yt,Tb,U,Cx,V,Cov,A,Px,Ytop,Wp,Sd:Single;
 Bg:PSingle;
 Feet:Boolean;
Begin
 SceneSit:=False;
 Msg:='';
 If not PersonBounds(S,X0,Y0,X1,Y1)Then Begin
   Msg:='aucune personne d'#130'tect'#130'e';Exit;End;
 If not GetBody(S,B,Msg)Then Exit;
 Msg:='';
 U:=B.U;Cx:=B.Cx;
 BodyH:=Y1-Y0+1;
 Feet:=CatArea(S,msShoes)>=Int64(S.W)*S.H div 2000;
 If Feet Then Yt:=Y0+0.52*BodyH Else Yt:=Y0+0.66*BodyH;
 { la table doit commencer sous les epaules }
 If Yt<B.Sy+1.1*U Then Yt:=B.Sy+1.1*U;
 Tb:=0.05*FMax(BodyH,6*U);
 Need:=Trunc(Yt+Tb+0.20*U)-S.H;
 If Need>0 Then GrowEdges(S,0,0,0,Need);
 N:=Int64(S.W)*S.H;
 Bg:=AllocF(N*3);
 Move(S.Pix^,Bg^,N*12);
 { dossier de la chaise, derriere les epaules }
 Ytop:=B.Sy-0.35*U;
 For Side:=-1 to 1 do Begin
  If Side=0 Then Continue;
  Px:=Cx+Side*(B.Half+0.55*U);
  For Y:=Trunc(Ytop)to Trunc(Yt)do
   For X:=Trunc(Px-0.12*U)-2 to Trunc(Px+0.12*U)+2 do Begin
    Cov:=CoverD(Abs(X+0.5-Px)-0.085*U);
    If Y<Ytop+0.085*U Then Cov:=Cov*CoverD(Sqrt(Sqr(X+0.5-Px)+Sqr(Y+
      0.5-Ytop-0.085*U))-0.085*U)*0+Cov;
    If Cov<=0 Then Continue;
    V:=0.55+0.55*Sin((X+0.5-Px+0.085*U)/(0.17*U)*Pi);
    PutBg(Bg,S.W,S.H,X,Y,Cov,112*V,70*V,42*V);
   End;
 End;
 For Y:=Trunc(Ytop)to Trunc(Ytop+0.30*U)do
  For X:=Trunc(Cx-B.Half-0.65*U)to Trunc(Cx+B.Half+0.65*U)do Begin
   Cov:=CoverD(RoundRectD(X+0.5,Y+0.5,Cx,Ytop+0.15*U,B.Half+0.60*U,0.15*U,
     0.10*U));
   If Cov<=0 Then Continue;
   V:=0.60+0.60*Sin((Y+0.5-Ytop)/(0.30*U)*Pi);
   PutBg(Bg,S.W,S.H,X,Y,Cov,118*V,74*V,44*V);
  End;
 CompositeBg(S,Bg);
 { table : plateau clair avec reflet, tablier sombre ; tout ce qui est dessous
   est cache }
 For Y:=Trunc(Yt)-6 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   If Y+0.5<Yt Then Begin
    { ombre du corps sur le plateau, juste au-dessus }
    Sd:=0.22*Exp(-Sqr((Y+0.5-Yt)/(0.05*U)))*S.Cat[cBg][K]/255.0*0;
    Continue;
   End;
   If Y+0.5<Yt+Tb Then Begin
    A:=(Y+0.5-Yt)/Tb;
    V:=0.88+0.22*(1-A)+0.12*FBm(X*0.02,Y*0.4)-0.06*Sin(X*0.05+FBm(X*0.01,Y*0.1)
      *6);
    If A>0.90 Then V:=V*0.78;
    If A<0.06 Then V:=V*1.18;
    S.Pix[K*3]:=170*V;S.Pix[K*3+1]:=112*V;S.Pix[K*3+2]:=70*V;
   End
    Else Begin
     V:=0.46+0.10*FBm(X*0.015,Y*0.3)*(1-0.4*(Y-Yt-Tb)/FMax(1,S.H-Yt-Tb));
     S.Pix[K*3]:=118*V;S.Pix[K*3+1]:=74*V;S.Pix[K*3+2]:=46*V;
    End;
   For C:=0 to NumCat-1 do S.Cat[C][K]:=0;
   S.Cat[cBg][K]:=255;
  End;
 SceneSit:=True;
 Info('  '+What);
End;

{ ---- funambule : decor de ciel, rope tendue, balancier dans les mains ---- }

Function SceneTightrope(Var S:TScene;Var Msg:AnsiString):Boolean;
Var
 X0,Y0,X1,Y1,X,Y,I,Need,C:LongInt;
 N,K:Int64;
 BodyH,YFeet,Xc,U,Yr,Ry,T,V,Cov,Rr,Ux,Pyl,Pyr,Pxl,Pxr,Hx,Hy,Dd,Sx,Sh,Hb,Bx,By,
   Bw:Single;
 Bg:PSingle;
 Tmp:Single;
 Hxs:Array[0..1]of Single;
 Hys:Array[0..1]of Single;
 Haz:Boolean;
Begin
 SceneTightrope:=False;
 Msg:='';
 If not PersonBounds(S,X0,Y0,X1,Y1)Then Begin
   Msg:='aucune personne d'#130'tect'#130'e';Exit;End;
 BodyH:=Y1-Y0+1;YFeet:=Y1+1;
 Need:=Trunc(YFeet+0.22*BodyH)-S.H;
 If Need>0 Then GrowEdges(S,0,0,0,Need);
 Xc:=FeetCenter(S,Y1,X0,X1);
 N:=Int64(S.W)*S.H;
 Bg:=AllocF(N*3);
 { ciel du matin et nuages }
 VGradient(Bg,S.W,S.H,0,S.H-1,70,124,200,222,232,244);
 Clouds(Bg,S.W,S.H,0,S.H-1,0.5/FMax(40,0.12*S.W),0.85);
 { ville lointaine dans la brume, sous la corde }
 For I:=0 to 2 do Begin
  Yr:=YFeet+0.04*BodyH+I*0.045*BodyH;
  For X:=0 to S.W-1 do Begin
   Ux:=X/(0.035*S.W+I*7);
   Hb:=Yr-(0.02+0.05*Hash2(Trunc(Ux)+I*31,5))*BodyH*(1.0+0.4*Hash2(Trunc(Ux),9)
     );
   For Y:=Trunc(Hb)to S.H-1 do Begin
    T:=0.62+I*0.13;
    PutBg(Bg,S.W,S.H,X,Y,1,150*T+60*(1-T)*0+I*18,165*T+I*14,190*T+I*10);
   End;
  End;
 End;
 For Y:=Trunc(YFeet+0.04*BodyH)to S.H-1 do
  For X:=0 to S.W-1 do PutBg(Bg,S.W,S.H,X,Y,0.35*SmoothStep(YFeet,S.H,Y),210,
    220,235);
 { mats d'ancrage de part et d'autre }
 For I:=0 to 1 do Begin
  Bx:=I*(S.W-1)*1.0;
  If I=0 Then Bx:=0.035*S.W Else Bx:=0.965*S.W;
  Bw:=0.012*S.W;
  For Y:=Trunc(YFeet-0.30*BodyH)to S.H-1 do
   For X:=Trunc(Bx-Bw-2)to Trunc(Bx+Bw+2)do Begin
    Cov:=CoverD(Abs(X+0.5-Bx)-Bw);
    V:=0.55+0.45*Sin((X+0.5-Bx+Bw)/(2*Bw)*Pi);
    PutBg(Bg,S.W,S.H,X,Y,Cov,58*V,62*V,72*V);
   End;
 End;
 { corde : plus haute aux ancrages qu'au centre }
 For X:=0 to S.W-1 do Begin
  Ux:=(X+0.5-Xc)/FMax(Xc,S.W-Xc);
  Ry:=YFeet-0.045*BodyH*Ux*Ux+0.004*BodyH;
  For Y:=Trunc(Ry-4)to Trunc(Ry+6)do Begin
   Cov:=CoverD(Abs(Y+0.5-Ry)-FMax(0.8,0.006*BodyH));
   PutBg(Bg,S.W,S.H,X,Y,Cov,36,30,28);
   Cov:=0.30*CoverD(Abs(Y+0.5-(Ry-0.004*BodyH))-0.4);
   PutBg(Bg,S.W,S.H,X,Y,Cov,150,140,128);
  End;
 End;
 { balancier : barre horizontale qui passe par les poings }
 Haz:=LastP[0].Used and LastP[1].Used;
 If Haz Then Begin
  For I:=0 to 1 do Begin
   Hxs[I]:=LastP[I].Wx+LastP[I].Hdx*LastP[I].Hsz*0.22;
   Hys[I]:=LastP[I].Wy+LastP[I].Hdy*LastP[I].Hsz*0.22;
  End;
  Pxl:=FMin(Hxs[0],Hxs[1])-0.9*LastB.U;Pxr:=FMax(Hxs[0],Hxs[1])+0.9*LastB.U;
  Hy:=(Hys[0]+Hys[1])/2;
  Rr:=FMax(1.2,0.055*LastB.U);
  For X:=Trunc(Pxl)to Trunc(Pxr)do Begin
   T:=(X+0.5-(Pxl+Pxr)/2)/((Pxr-Pxl)/2);
   Sh:=Hy+0.02*(Pxr-Pxl)*T*T*0.5;
   For Y:=Trunc(Sh-Rr-3)to Trunc(Sh+Rr+3)do Begin
    Cov:=CoverD(Abs(Y+0.5-Sh)-Rr);
    V:=0.55+0.55*Sin(Clamp((Y+0.5-Sh+Rr)/(2*Rr),0,1)*Pi);
    PutBg(Bg,S.W,S.H,X,Y,Cov,150*V,150*V,158*V);
   End;
  End;
  { poids aux extremites }
  For I:=0 to 1 do Begin
   If I=0 Then Sx:=Pxl Else Sx:=Pxr;
   Tmp:=Hy+0.02*(Pxr-Pxl)*0.5;
   For Y:=Trunc(Tmp-0.25*LastB.U)to Trunc(Tmp+0.25*LastB.U)do
    For X:=Trunc(Sx-0.14*LastB.U)-1 to Trunc(Sx+0.14*LastB.U)+1 do
     PutBg(Bg,S.W,S.H,X,Y,CoverD(RoundRectD(X+0.5,Y+0.5,Sx,Tmp,0.12*LastB.U,
       0.22*LastB.U,0.05*LastB.U)),70,72,80);
  End;
 End;
 CompositeBg(S,Bg);
 SceneTightrope:=True;
 Info('  funambule sur un fil (balancier tenu par les deux mains)');
End;

{ ---- sur le toit d'une niche a chien ---- }

Function SceneDoghouse(Var S:TScene;Var Msg:AnsiString):Boolean;
Var
 X0,Y0,X1,Y1,NW,NH,X,Y,I:LongInt;
 N,K:Int64;
 BodyH,BodyW,Sc,Ph,Xc,Yr,Dw,Dx0,Dx1,Ry,Wh,Dd,Cov,V,T,Rx,Ax,Px,Rh,Y2,Y3,Fy,
   Door0,Door1,Dh,Dr,Ox,Oy,Rw,L0,L1,Rowh:Single;
 Bg:PSingle;
 Row,Col:LongInt;
Begin
 SceneDoghouse:=False;
 Msg:='';
 If not PersonBounds(S,X0,Y0,X1,Y1)Then Begin
   Msg:='aucune personne d'#130'tect'#130'e';Exit;End;
 ColorInit;
 BodyH:=Y1-Y0+1;BodyW:=X1-X0+1;
 Xc:=FeetCenter(S,Y1,X0,X1);
 Sc:=0.62;
 If 1.58*BodyH*Sc>2300 Then Sc:=2300/(1.58*BodyH);
 Ph:=BodyH*Sc;
 NW:=Trunc(FMax(1.18*Ph,1.30*BodyW*Sc));NH:=Trunc(1.58*Ph);
 Yr:=NH-0.52*Ph;
 Ox:=NW*0.5-Xc*Sc;
 Oy:=Yr-(Y1+1)*Sc+0.004*Ph;
 TransformScene(S,NW,NH,Sc,0,Ox,Oy);
 N:=Int64(S.W)*S.H;
 Bg:=AllocF(N*3);
 VGradient(Bg,NW,NH,0,NH-1,96,158,226,214,232,246);
 Clouds(Bg,NW,NH,0,Trunc(Yr),0.8/FMax(40,0.15*NW),0.9);
 { haie et pelouse }
 Rh:=NH-0.075*Ph;
 For Y:=Trunc(Rh-0.05*Ph)to NH-1 do
  For X:=0 to NW-1 do Begin
   T:=FBm(X*0.05,Y*0.05);
   If Y<Rh Then PutBg(Bg,NW,NH,X,Y,1,52+30*T,100+34*T,48+20*T)
   Else PutBg(Bg,NW,NH,X,Y,1,(78+30*T)*(1-0.25*(Y-Rh)/(NH-Rh)),(142+40*T)
     *(1-0.25*(Y-Rh)/(NH-Rh)),(58+22*T)*(1-0.25*(Y-Rh)/(NH-Rh)));
  End;
 Dw:=0.94*NW;Dx0:=(NW-Dw)/2;Dx1:=Dx0+Dw;
 Rh:=0.15*Ph;            { hauteur du toit visible }
 Wh:=0.30*Ph;            { hauteur du mur }
 Y2:=Yr+Rh;Y3:=Y2+Wh;
 { mur : planches verticales bleu-vert }
 For Y:=Trunc(Y2)to Trunc(Y3)do
  For X:=Trunc(Dx0+0.02*Dw)to Trunc(Dx1-0.02*Dw)do Begin
   Col:=Trunc((X-Dx0)/(0.06*Dw));
   Fy:=Frac((X-Dx0)/(0.06*Dw));
   V:=0.78+0.28*Hash2(Col,11)+0.08*FBm(X*0.02,Y*0.2);
   If Fy<0.05 Then V:=V*0.45;
   PutBg(Bg,NW,NH,X,Y,1,74*V,126*V,150*V);
  End;
 { ombre de l'avant-toit sur le mur }
 For Y:=Trunc(Y2)to Trunc(Y2+0.07*Ph)do
  For X:=Trunc(Dx0+0.02*Dw)to Trunc(Dx1-0.02*Dw)do PutBg(Bg,NW,NH,X,Y,
    0.55*(1-(Y-Y2)/(0.07*Ph)),10,18,26);
 { porte en arche }
 Door0:=NW/2-0.15*Dw;Door1:=NW/2+0.15*Dw;Dh:=0.62*Wh;
 For Y:=Trunc(Y3-Dh)-2 to Trunc(Y3)do
  For X:=Trunc(Door0)-6 to Trunc(Door1)+6 do Begin
   Rx:=Door1-Door0;
   If Y+0.5<Y3-Dh+Rx/2 Then Dd:=Sqrt(Sqr(X+0.5-NW/2)+Sqr(Y+0.5-(Y3-Dh+Rx/2)))
     -Rx/2
   Else Dd:=Abs(X+0.5-NW/2)-Rx/2;
   If Y+0.5>Y3 Then Continue;
   Cov:=CoverD(Dd);
   If Cov>0 Then Begin
    V:=0.10+0.12*(1-(Y+0.5-(Y3-Dh))/Dh);
    PutBg(Bg,NW,NH,X,Y,Cov,34*V*3,26*V*3,22*V*3);
   End;
   Cov:=CoverD(Abs(Dd-0.022*Dw)-0.018*Dw)*(1-CoverD(Dd));
   If Cov>0 Then PutBg(Bg,NW,NH,X,Y,Cov,226,214,190);
  End;
 { gamelle devant la porte }
 For Y:=Trunc(Y3-0.045*Ph)to Trunc(Y3+0.02*Ph)do
  For X:=Trunc(Door1+0.03*Dw)to Trunc(Door1+0.14*Dw)do Begin
   Cov:=CoverD(EllipseD(X+0.5,Y+0.5,Door1+0.085*Dw,Y3-0.012*Ph,0.055*Dw,
     0.032*Ph));
   V:=0.7+0.5*Sin(Clamp((Y+0.5-(Y3-0.044*Ph))/(0.065*Ph),0,1)*Pi);
   PutBg(Bg,NW,NH,X,Y,Cov,200*V,60*V,52*V);
  End;
 { ombre au sol sous la niche }
 For Y:=Trunc(Y3-0.01*Ph)to Trunc(Y3+0.04*Ph)do
  For X:=Trunc(Dx0)to Trunc(Dx1)do PutBg(Bg,NW,NH,X,Y,0.5*(1-SmoothStep(0,
    0.04*Ph,Y-Y3))*0+0.45*Exp(-Sqr((Y-Y3)/(0.018*Ph))),12,28,12);
 { toit : trapeze de bardeaux rouges, faitage en haut }
 L0:=Dx0+0.12*Dw;L1:=Dx1-0.12*Dw;
 For Y:=Trunc(Yr)to Trunc(Y2)+1 do Begin
  T:=(Y+0.5-Yr)/Rh;
  Ax:=L0+(Dx0-0.015*Dw-L0)*T;
  Rw:=L1+(Dx1+0.015*Dw-L1)*T;
  For X:=Trunc(Ax)-1 to Trunc(Rw)+1 do Begin
   Cov:=CoverD(Ax-(X+0.5))*0+1;
   If(X+0.5<Ax-0.5)or(X+0.5>Rw+0.5)Then Continue;
   Rowh:=0.032*Ph;
   Row:=Trunc((Y+0.5-Yr)/Rowh);
   Fy:=Frac((Y+0.5-Yr)/Rowh);
   Col:=Trunc((X+0.5+Row*0.5*0.07*Dw)/(0.07*Dw));
   V:=0.70+0.45*Hash2(Col,Row+13)+0.10*FBm(X*0.03,Y*0.15)+0.20*(1-T);
   If Fy>0.85 Then V:=V*0.55;
   If Frac((X+0.5+Row*0.5*0.07*Dw)/(0.07*Dw))<0.03 Then V:=V*0.6;
   PutBg(Bg,NW,NH,X,Y,1,164*V,62*V,44*V);
  End;
 End;
 { faitage }
 For Y:=Trunc(Yr-0.012*Ph)to Trunc(Yr+0.012*Ph)do
  For X:=Trunc(L0)-2 to Trunc(L1)+2 do
   PutBg(Bg,NW,NH,X,Y,CoverD(RoundRectD(X+0.5,Y+0.5,(L0+L1)/2,Yr,(L1-L0)/2,
     0.012*Ph,0.012*Ph)),110,36,28);
 { ombre de la personne sur le toit }
 For Y:=Trunc(Yr-0.01*Ph)to Trunc(Yr+0.05*Ph)do
  For X:=Trunc(NW/2-0.25*Ph)to Trunc(NW/2+0.25*Ph)do
   PutBg(Bg,NW,NH,X,Y,0.55*Exp(-Sqr((X+0.5-NW/2)/(0.14*Ph))-Sqr((Y+
     0.5-Yr-0.012*Ph)/(0.022*Ph))),20,8,6);
 CompositeBg(S,Bg);
 SceneDoghouse:=True;
 Info('  personne debout sur le toit d''une niche (r'#130'duite pour para'#140+
   'tre sur le toit)');
End;
{ ------------------------------------------------------------------ }
{ Situations (fin) : escalier, chambre de somnambule, meuble         }
{ ------------------------------------------------------------------ }

{ ---- sur un escalier : les marches montent derriere la personne ---- }

Function SceneStairs(Var S:TScene;Var Msg:AnsiString):Boolean;
Var
 X0,Y0,X1,Y1,X,Y,J,Need:LongInt;
 N,K:Int64;
 BodyH,YFeet,Xc,P,Yn,Wj,Xa,Xb,V,T,Fy,Sh,Cov,Up,Rx,Dd:Single;
 Bg:PSingle;
Begin
 SceneStairs:=False;
 Msg:='';
 If not PersonBounds(S,X0,Y0,X1,Y1)Then Begin
   Msg:='aucune personne d'#130'tect'#130'e';Exit;End;
 BodyH:=Y1-Y0+1;YFeet:=Y1+1;
 Need:=Trunc(YFeet+0.30*BodyH)-S.H;
 If Need>0 Then GrowEdges(S,0,0,0,Need);
 Xc:=FeetCenter(S,Y1,X0,X1);
 N:=Int64(S.W)*S.H;
 Bg:=AllocF(N*3);
 P:=0.085*BodyH;
 { murs : crepi sombre degrade }
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   T:=Y/S.H;
   V:=(0.62-0.30*T)*(0.92+0.16*FBm(X*0.01,Y*0.01))*(1-0.35*Sqr((X+0.5)/S.W-0.5)
     *2);
   Bg[K*3]:=150*V;Bg[K*3+1]:=138*V;Bg[K*3+2]:=124*V;
  End;
 { marches : numerotees de J=0 (sous les pieds) ; J<0 = plus haut (plus
   etroites) }
 For J:=-Trunc(YFeet/P)-2 to Trunc((S.H-YFeet)/P)+2 do Begin
  Yn:=YFeet+0.25*P+J*P;                    { arete de la marche }
  Wj:=0.99-0.030*(-J);                     { largeur relative : decroit en
    montant }
  If J>=0 Then Wj:=0.99+0.01*J;
  If Wj<0.42 Then Wj:=0.42;
  If Wj>1.5 Then Wj:=1.5;
  Xa:=S.W*0.5-S.W*Wj*0.5;Xb:=S.W*0.5+S.W*Wj*0.5;
  Up:=Clamp((YFeet-Yn)/FMax(YFeet,1),0,1);
  For Y:=Trunc(Yn-0.45*P)-1 to Trunc(Yn+0.55*P)+1 do Begin
   If(Y<0)or(Y>=S.H)Then Continue;
   For X:=Trunc(Xa)to Trunc(Xb)do Begin
    If(X<0)or(X>=S.W)Then Continue;
    If Y+0.5<Yn-0.45*P Then Continue;
    If Y+0.5<Yn Then Begin
     { dessus de la marche }
     Fy:=(Y+0.5-(Yn-0.45*P))/(0.45*P);
     V:=(0.98-0.20*Up)*(0.93+0.12*FBm(X*0.03,Y*0.03))*(0.93+0.07*Fy);
     If Fy<0.08 Then V:=V*0.78;
     PutBg(Bg,S.W,S.H,X,Y,1,186*V,178*V,164*V);
    End
     Else Begin
      { contremarche }
      Fy:=(Y+0.5-Yn)/(0.55*P);
      V:=(0.64-0.18*Up)*(0.93+0.12*FBm(X*0.03,Y*0.05))*(1-0.30*Fy);
      If Fy<0.07 Then V:=V*1.35;
      PutBg(Bg,S.W,S.H,X,Y,1,172*V,160*V,146*V);
     End;
    { cotes : ombre le long des murs }
    Rx:=FMin(X-Xa,Xb-X)/FMax(1,S.W*0.05);
    If Rx<1 Then PutBg(Bg,S.W,S.H,X,Y,0.45*(1-Rx),10,8,8);
   End;
  End;
 End;
 { ombre sous les pieds }
 For Y:=Trunc(YFeet-0.03*BodyH)to Trunc(YFeet+0.05*BodyH)do
  For X:=Trunc(Xc-0.35*BodyH*0.45)to Trunc(Xc+0.35*BodyH*0.45)do Begin
   Dd:=Sqr((X+0.5-Xc)/(0.26*FMax(X1-X0+1,0.25*BodyH)))+Sqr((Y+0.5-YFeet)
     /(0.02*BodyH));
   PutBg(Bg,S.W,S.H,X,Y,0.55*Exp(-Dd*1.5),8,6,6);
  End;
 CompositeBg(S,Bg);
 SceneStairs:=True;
 Info('  personne debout sur un escalier (jambes non pli'#130'es : la mont'#130+
   'e n''est pas anim'#130'e)');
End;

{ ---- somnambule : chambre la nuit, clair de lune, teinte nocturne ---- }

Function SceneNight(Var S:TScene;Var Msg:AnsiString):Boolean;
Var
 X0,Y0,X1,Y1,X,Y,I,Need,C:LongInt;
 N:int64;K:LongInt;
 BodyH,YFeet,Xc,Yh,V,T,Cov,Wx0,Wx1,Wy0,Wy1,Mx,My,Mr,D,A,Fw:Single;
 Bg:PSingle;
Begin
 SceneNight:=False;
 Msg:='';
 If not PersonBounds(S,X0,Y0,X1,Y1)Then Begin
   Msg:='aucune personne d'#130'tect'#130'e';Exit;End;
 BodyH:=Y1-Y0+1;YFeet:=Y1+1;
 Need:=Trunc(YFeet+0.10*BodyH)-S.H;
 If Need>0 Then GrowEdges(S,0,0,0,Need);
 Xc:=FeetCenter(S,Y1,X0,X1);
 N:=Int64(S.W)*S.H;
 Bg:=AllocF(N*3);
 Yh:=YFeet-0.10*BodyH;
 { mur }
 VGradient(Bg,S.W,S.H,0,Trunc(Yh),22,28,62,40,48,92);
 For Y:=0 to Trunc(Yh)do
  For X:=0 to S.W-1 do PutBg(Bg,S.W,S.H,X,Y,0.10*FBm(X*0.015,Y*0.015),120,
    130,190);
 { fenetre cote oppose a la personne }
 If Xc>S.W*0.5 Then Wx0:=0.07*S.W Else Wx0:=0.60*S.W;
 Wx1:=Wx0+0.33*S.W;
 Wy0:=0.10*Yh;Wy1:=0.78*Yh;
 For Y:=Trunc(Wy0)-3 to Trunc(Wy1)+3 do
  For X:=Trunc(Wx0)-3 to Trunc(Wx1)+3 do Begin
   Cov:=CoverD(RoundRectD(X+0.5,Y+0.5,(Wx0+Wx1)/2,(Wy0+Wy1)/2,(Wx1-Wx0)/2+
     0.012*S.W,(Wy1-Wy0)/2+0.012*S.W,0.01*S.W));
   If Cov>0 Then PutBg(Bg,S.W,S.H,X,Y,Cov,200,205,225);
   Cov:=CoverD(RoundRectD(X+0.5,Y+0.5,(Wx0+Wx1)/2,(Wy0+Wy1)/2,(Wx1-Wx0)/2,
     (Wy1-Wy0)/2,0.004*S.W));
   If Cov<=0 Then Continue;
   T:=(Y+0.5-Wy0)/(Wy1-Wy0);
   V:=1-0.45*T;
   PutBg(Bg,S.W,S.H,X,Y,Cov,14*V+10,26*V+14,64*V+22);
   { etoiles }
   A:=Hash2(Trunc((X+0.5)/2.5)+11,Trunc((Y+0.5)/2.5)+5);
   If A>0.992 Then PutBg(Bg,S.W,S.H,X,Y,Cov*(A-0.99)*90,255,255,240);
  End;
 { lune et halo }
 Mx:=Wx0+0.68*(Wx1-Wx0);My:=Wy0+0.30*(Wy1-Wy0);Mr:=0.09*(Wx1-Wx0)*1.4;
 For Y:=Trunc(Wy0)to Trunc(Wy1)do
  For X:=Trunc(Wx0)to Trunc(Wx1)do Begin
   D:=Sqrt(Sqr(X+0.5-Mx)+Sqr(Y+0.5-My));
   Cov:=0.35*Exp(-Sqr(D/(Mr*2.6)));
   PutBg(Bg,S.W,S.H,X,Y,Cov,170,190,255);
   Cov:=CoverD(D-Mr);
   If Cov>0 Then PutBg(Bg,S.W,S.H,X,Y,Cov,(244-14*FBm(X*0.08,Y*0.08)),
     (242-16*FBm(X*0.08,Y*0.08)),(222-10*FBm(X*0.08,Y*0.08)));
  End;
 { croisillons }
 Fw:=0.007*S.W;
 For Y:=Trunc(Wy0)to Trunc(Wy1)do
  For X:=Trunc(Wx0)to Trunc(Wx1)do Begin
   Cov:=FMax(CoverD(Abs(X+0.5-(Wx0+Wx1)/2)-Fw/2),CoverD(Abs(Y+0.5-((Wy0+Wy1)
     /2-0.06*(Wy1-Wy0)))-Fw/2));
   PutBg(Bg,S.W,S.H,X,Y,Cov,190,196,215);
  End;
 { rideaux }
 For Y:=Trunc(Wy0)-4 to Trunc(Wy1)+10 do
  For X:=Trunc(Wx0-0.06*S.W)to Trunc(Wx1+0.06*S.W)do Begin
   If(X+0.5>Wx0+0.03*S.W)and(X+0.5<Wx1-0.03*S.W)Then Continue;
   If(X<0)or(X>=S.W)Then Continue;
   If(Y+0.5<Wy0-0.02*S.H)or(Y+0.5>Yh)Then Continue;
   V:=0.55+0.45*Sin(X*0.22+FBm(X*0.02,Y*0.01)*4);
   PutBg(Bg,S.W,S.H,X,Y,0.92,40*V,48*V,92*V);
  End;
 { plancher bleute, plinthe, tache de lune }
 WoodFloor(Bg,S.W,S.H,0,Trunc(Yh),S.W-1,S.H-1,0.05*S.H,0.5*S.W,RgbOf(92,70,66));
 For Y:=Trunc(Yh)to S.H-1 do
  For X:=0 to S.W-1 do Begin
   K:=Int64(Y)*S.W+X;
   Bg[K*3]:=Bg[K*3]*0.46;Bg[K*3+1]:=Bg[K*3+1]*0.56;Bg[K*3+2]:=Bg[K*3+2]*0.88;
   T:=(Y-Yh)/FMax(1,S.H-Yh);
   Cov:=0.30*Exp(-Sqr((X+0.5-(Wx0+Wx1)/2-0.15*(X-Wx0))/(0.22*S.W)))*(1-T)
     *SmoothStep(Yh,Yh+0.02*S.H,Y);
   PutBg(Bg,S.W,S.H,X,Y,Cov,150,170,235);
  End;
 For Y:=Trunc(Yh)-Trunc(0.025*BodyH)to Trunc(Yh)do
  For X:=0 to S.W-1 do PutBg(Bg,S.W,S.H,X,Y,1,70,76,112);
 { ombre au sol }
 For Y:=Trunc(YFeet-0.02*BodyH)to Trunc(YFeet+0.06*BodyH)do
  For X:=0 to S.W-1 do Begin
   D:=Sqr((X+0.5-Xc)/(0.20*FMax(X1-X0+1,0.30*BodyH)))+Sqr((Y+
     0.5-YFeet-0.01*BodyH)/(0.025*BodyH));
   PutBg(Bg,S.W,S.H,X,Y,0.55*Exp(-D*1.6),4,4,10);
  End;
 { la personne recoit la teinte de la nuit }
 N:=Int64(S.W)*S.H;
 For K:=0 to N-1 do Begin
  S.Pix[K*3]:=S.Pix[K*3]*0.66;S.Pix[K*3+1]:=S.Pix[K*3+1]*0.74;S.Pix[K*3+
    2]:=S.Pix[K*3+2]*0.98+8;
 End;
 CompositeBg(S,Bg);
 SceneNight:=True;
 Info('  chambre de nuit, teinte de clair de lune');
End;

{ ---- appuyee sur un meuble (commode) : le coude repose dessus ---- }

Function SceneLean(Var S:TScene;Var Msg:AnsiString):Boolean;
Var
 N,K:Int64;
 X,Y,Sg,I,J,Row:LongInt;
 Xa,Xb,Yt,U,Ex,Th,V,Cov,Dd,Dx,Dy,Cxm,Lh,Wd,T:Single;
 Bg:PSingle;
Begin
 SceneLean:=False;
 Msg:='';
 If not LastP[0].Used Then Begin Msg:='la position du bras est inconnue';
   Exit;End;
 Sg:=LastP[0].Sg;U:=LastB.U;
 Ex:=LastP[0].Ex;
 N:=Int64(S.W)*S.H;
 Bg:=AllocF(N*3);
 Move(S.Pix^,Bg^,N*12);
 Yt:=LastP[0].Ey+0.17*U;
 Th:=0.16*U;
 If Sg>0 Then Begin Xa:=Ex-0.55*U;Xb:=S.W-1+0.0;End
 Else Begin Xb:=Ex+0.55*U;Xa:=0;End;
 If Yt+0.6*U>S.H Then Begin Msg:='le meuble sortirait du cadre';FreeMem(Bg);
   Exit;End;
 { dessus du meuble }
 For Y:=Trunc(Yt-0.02*U)to Trunc(Yt+Th)+1 do
  For X:=Trunc(Xa)to Trunc(Xb)do Begin
   Cov:=CoverD(RoundRectD(X+0.5,Y+0.5,(Xa+Xb)/2,Yt+Th/2-0.01*U,(Xb-Xa)/2+
     0.2*U,Th/2,0.03*U));
   If Cov<=0 Then Continue;
   V:=0.78+0.40*(1-(Y+0.5-Yt)/Th)+0.10*FBm(X*0.03,Y*0.4);
   If(Y+0.5-Yt)<0.1*Th Then V:=V*1.25;
   PutBg(Bg,S.W,S.H,X,Y,Cov,150*V,98*V,62*V);
  End;
 { corps : tiroirs }
 Lh:=S.H-(Yt+Th);
 For Y:=Trunc(Yt+Th)to S.H-1 do
  For X:=Trunc(Xa+0.05*U*0)to Trunc(Xb)do Begin
   V:=0.52+0.10*FBm(X*0.02,Y*0.3);
   PutBg(Bg,S.W,S.H,X,Y,1,112*V,70*V,44*V);
   Dx:=Frac((X-Xa)/(1.05*U));
   Row:=Trunc((Y-(Yt+Th))/(0.62*U));
   Dy:=Frac((Y-(Yt+Th))/(0.62*U));
   If(Dx>0.04)and(Dx<0.96)and(Dy>0.07)and(Dy<0.93)Then Begin
    V:=0.58+0.10*FBm(X*0.02,Y*0.3);
    If(Dx<0.07)or(Dx>0.93)or(Dy<0.10)or(Dy>0.90)Then V:=V*0.78;
    PutBg(Bg,S.W,S.H,X,Y,1,128*V,80*V,50*V);
   End;
  End;
 { poignees }
 I:=0;
 For J:=0 to Trunc((Xb-Xa)/(1.05*U)) do
  For Row:=0 to Trunc(Lh/(0.62*U)) do Begin
   Cxm:=Xa+(J+0.5)*1.05*U;
   Dy:=Yt+Th+(Row+0.5)*0.62*U;
   If(Dy>S.H)or(Cxm>Xb+0.2*U)Then Continue;
   For Y:=Trunc(Dy-0.06*U)to Trunc(Dy+0.06*U)do
    For X:=Trunc(Cxm-0.14*U)to Trunc(Cxm+0.14*U)do
     PutBg(Bg,S.W,S.H,X,Y,CoverD(RoundRectD(X+0.5,Y+0.5,Cxm,Dy,0.13*U,
       0.035*U,0.03*U)),214,176,96);
  End;
 { lampe de chevet a l'extremite }
 If Sg>0 Then Cxm:=Xb-0.60*U Else Cxm:=Xa+0.60*U;
 If(Cxm>0.3*U)and(Cxm<S.W-0.3*U)Then Begin
  For Y:=Trunc(Yt-1.4*U)to Trunc(Yt)do
   For X:=Trunc(Cxm-0.7*U)to Trunc(Cxm+0.7*U)do Begin
    Dx:=Abs(X+0.5-Cxm);
    Dd:=Sqrt(Sqr(X+0.5-Cxm)+Sqr(Y+0.5-(Yt-0.95*U)));
    PutBg(Bg,S.W,S.H,X,Y,0.30*Exp(-Sqr(Dd/(0.55*U))),255,226,160);
    { pied }
    PutBg(Bg,S.W,S.H,X,Y,CoverD(RoundRectD(X+0.5,Y+0.5,Cxm,Yt-0.30*U,
      0.035*U,0.30*U,0.02*U)),196,160,90);
    PutBg(Bg,S.W,S.H,X,Y,CoverD(EllipseD(X+0.5,Y+0.5,Cxm,Yt-0.02*U,0.20*U,
      0.05*U)),196,160,90);
    { abat-jour }
    If(Y+0.5>Yt-1.22*U)and(Y+0.5<Yt-0.68*U)Then Begin
     T:=(Y+0.5-(Yt-1.22*U))/(0.54*U);
     Wd:=(0.18+0.20*T)*U;
     PutBg(Bg,S.W,S.H,X,Y,CoverD(Dx-Wd),255*(0.8+0.2*T),228*(0.8+0.2*T),
       170*(0.8+0.2*T));
    End;
   End;
 End;
 CompositeBg(S,Bg);
 SceneLean:=True;
 Info('  appuy'#130'e sur un meuble (commode)');
End;
{ ------------------------------------------------------------------ }
{ Repartiteur des poses et situations (? assis ?, ? bras croises ?...) }
{ ------------------------------------------------------------------ }

{ cote (image) qui offre le plus de place pour un bras tendu }
Function BestSide(Var S:TScene):LongInt;
Var
 B:TBody;
 Msg:AnsiString;
Begin
 BestSide:=1;
 If GetBody(S,B,Msg)Then
  If(B.Cx-B.Sho)>(S.W-(B.Cx+B.Sho))Then BestSide:=-1;
End;

{ Phase 0 : visage, bras, aureole (avant les autres retouches) ; Phase 1 :
  decors et situations }
Procedure ApplyPoses(Var S:TScene;Poses:LongWord;Phase:LongInt;Var NOk,
  NFail:LongInt);
Var
 Msg:AnsiString;
 Procedure Run(Ok:Boolean);
 Begin
  If Ok Then Inc(NOk)
  Else Begin
   If Msg<>'' Then Warn(Msg);
   Inc(NFail);
  End;
  Msg:='';
 End;
 Function Has(Code:LongInt):Boolean;
 Begin
  Has:=(Poses and(LongWord(1)shl Code))<>0;
 End;
Begin
 Msg:='';
 If Phase=0 Then Begin
 LastP[0].Used:=False;LastP[1].Used:=False;
 { visage }
 If Has(pcHeadStraight)Then Run(HeadStraight(S,Msg));
 If Has(pcSerious)Then Run(ApplyMood(S,False,Msg));
 If Has(pcSad)Then Run(ApplyMood(S,True,Msg));
 If Has(pcLost)Then Run(ApplyGaze(S,-1,-1,Msg));
 If Has(pcSleep)Then Run(CloseEyes(S,Msg));
 { bras }
 If Has(pcCross)Then Run(ArmPose(S,apCross,0,'bras crois'#130's',Msg));
 If Has(pcPeace)Then Run(ArmPose(S,apPeace,BestSide(S)
   ,'main lev'#130'e en V (peace & love)',Msg));
 If Has(pcPoint)Then Run(ArmPose(S,apPoint,BestSide(S)
   ,'bras tendu, doigt point'#130,Msg));
 If Has(pcJump)Then Run(ArmPose(S,apUp,0,'bras lev'#130's',Msg));
 If Has(pcTightrope)Then Run(ArmPose(S,apOut,0,'bras '#130'cart'#130's',Msg));
 If Has(pcSleep)Then Run(ArmPose(S,apForward,0,'bras tendus devant',Msg));
 If Has(pcLean)Then Run(ArmPose(S,apLean,BestSide(S)
   ,'coude pos'#130' sur le meuble',Msg));
 { aureole : dessinee avec la personne pour suivre ses deplacements }
 If Has(pcHalo)Then Run(ApplyHalo(S,Msg));
 End
 Else Begin
 { situations }
 If Has(pcFloat)Then Run(SceneLift(S,
   0.13,'personne en l'#130'vitation (ombre au sol)',Msg));
 If Has(pcJump)Then Run(SceneLift(S,
   0.07,'saut (jambes non pli'#130'es, ombre au sol)',Msg));
 If Has(pcLie)or Has(pcBed)Then Begin
  If Has(pcBed)Then Run(SceneLie(S,
    True,'personne couch'#130'e dans un lit (vue de dessus)',Msg))
  Else Run(SceneLie(S,False,'personne couch'#130'e au sol (vue de dessus)',Msg)
    );
 End;
 If Has(pcSit)Then
   Run(SceneSit(S,
   'assise '#133' une table (jambes cach'#130'es par la table)',Msg));
 If Has(pcTightrope)Then Run(SceneTightrope(S,Msg));
 If Has(pcDoghouse)Then Run(SceneDoghouse(S,Msg));
 If Has(pcStairs)Then Run(SceneStairs(S,Msg));
 If Has(pcSleep)Then Run(SceneNight(S,Msg));
 If Has(pcLean)Then Run(SceneLean(S,Msg));
 End;
 If(Phase=0)and Has(pcKneel)Then Begin
  Warn('"'#133' genoux" n''est pas pris en charge : les jambes devraient '#136+
    'tre repli'#130'es, ce qu''une retouche de l''image ne peut pas '+
    'inventer');
  Inc(NFail);
 End;
 If(Phase=0)and Has(pcBike)Then Begin
  Warn('"v'#130'lo" n''est pas pris en charge : il faudrait redessiner les '+
    'jambes sur les p'#130'dales et un v'#130'lo complet');
  Inc(NFail);
 End;
End;
{ ------------------------------------------------------------------ }
{ Peau, age et teintes speciales : lissage, grain, peau de bebe,      }
{ rajeunir / vieillir (rides, cernes, taches, cheveux gris),          }
{ cheveux poivre et sel                                              }
{ ------------------------------------------------------------------ }

Type
 TBilCtx=Record
  W,H,R:LongInt;
  Src,Dst,M:PSingle;
  Sw:Array[0..224]of Single;      { poids spatial (fenetre 15 x 15 au plus) }
  Rw:Array[0..255]of Single;      { poids de la difference de couleur }
 End;
 PBilCtx=^TBilCtx;

{ filtre bilateral limite aux pixels de peau (le contraste fort est conserve) }
Procedure BilProc(Ctx:Pointer;Lo,Hi,Tid:LongInt);
Var
 C:PBilCtx;
 X,Y,Dx,Dy,Nx,Ny,Ch,Wd:LongInt;
 K,Kn:Int64;
 Acc:Array[0..2]of Single;
 Sum,Wt,D:Single;
Begin
 C:=PBilCtx(Ctx);
 Wd:=2*C^.R+1;
 For Y:=Lo to Hi-1 do
  For X:=0 to C^.W-1 do Begin
   K:=Int64(Y)*C^.W+X;
   If C^.M[K]<0.02 Then Begin
    For Ch:=0 to 2 do C^.Dst[K*3+Ch]:=C^.Src[K*3+Ch];
    Continue;
   End;
   Acc[0]:=0;Acc[1]:=0;Acc[2]:=0;Sum:=0;
   For Dy:=-C^.R to C^.R do Begin
    Ny:=Y+Dy;
    If(Ny<0)or(Ny>=C^.H)Then Continue;
    For Dx:=-C^.R to C^.R do Begin
     Nx:=X+Dx;
     If(Nx<0)or(Nx>=C^.W)Then Continue;
     Kn:=Int64(Ny)*C^.W+Nx;
     If C^.M[Kn]<0.5 Then Continue;
     D:=(Abs(C^.Src[Kn*3]-C^.Src[K*3])+Abs(C^.Src[Kn*3+1]-C^.Src[K*3+1])+
       Abs(C^.Src[Kn*3+2]-C^.Src[K*3+2]))*0.3333;
     If D>255 Then D:=255;
     Wt:=C^.Sw[(Dy+C^.R)*Wd+Dx+C^.R]*C^.Rw[Trunc(D)];
     Acc[0]:=Acc[0]+Wt*C^.Src[Kn*3];Acc[1]:=Acc[1]+Wt*C^.Src[Kn*3+1];
       Acc[2]:=Acc[2]+Wt*C^.Src[Kn*3+2];
     Sum:=Sum+Wt;
    End;
   End;
   If Sum<=0 Then Sum:=1;
   For Ch:=0 to 2 do C^.Dst[K*3+Ch]:=Acc[Ch]/Sum;
  End;
End;

{ version lissee de la peau : fond (Base) pour la separation frequentielle }
Procedure SkinBase(Const S:TScene;M:PSingle;R:LongInt;Sigma:Single;
  Base:PSingle);
Var
 C:TBilCtx;
 Dx,Dy,I:LongInt;
Begin
 If R<1 Then R:=1;
 If R>7 Then R:=7;
 C.W:=S.W;C.H:=S.H;C.R:=R;C.Src:=S.Pix;C.Dst:=Base;C.M:=M;
 For Dy:=-R to R do
  For Dx:=-R to R do C.Sw[(Dy+R)*(2*R+1)+Dx+R]:=Exp(-(Dx*Dx+Dy*Dy)
    /(2.0*Sqr(R*0.55+0.5)));
 For I:=0 to 255 do C.Rw[I]:=Exp(-I*I/(2.0*Sigma*Sigma));
 ParFor(S.H,8,@BilProc,@C);
End;

{ masque de la peau (visage, bras, jambes) ; faux si trop petit }
Function SkinMaskOf(Const S:TScene;Var M:PSingle):Boolean;
Var
 N:int64;K:LongInt;
Begin
 N:=Int64(S.W)*S.H;
 M:=AllocF(N);
 CatMask(S,msSkin,M);
 For K:=0 to N-1 do M[K]:=SmoothStep(0.25,0.8,M[K]);
 SkinMaskOf:=CatArea(S,msSkin)>=N div 4000;
End;

{ rayon du filtre : proportionnel au visage (ou a l'image si aucun visage) }
Function SkinRadius(Const S:TScene):LongInt;
Var
 H:THeadInfo;
Begin
 If HeadInfo(S,H)Then SkinRadius:=ClampI(Round(0.014*H.Fw),2,7)
 Else SkinRadius:=ClampI(Round(0.004*S.W),2,7);
End;

{ lissage de la peau : K = part de detail conservee (1 = aucun lissage) ;
  Bright = eclaircissement, Blush = rose (bebe) }
Function SkinSmooth(Var S:TScene;K:Single;Sigma,Bright,Blush:Single;Const
  What:AnsiString;Var Msg:AnsiString):Boolean;
Var
 M,Base:PSingle;
 N:int64;I:LongInt;
 C:LongInt;
 Dl,Keep,V,Mw,Dt:Single;
 H:THeadInfo;
 X,Y:LongInt;
 Ch:Array[0..2]of Single;
 Cheek:Single;
Begin
 SkinSmooth:=False;
 Msg:='';
 ColorInit;
 If not SkinMaskOf(S,M)Then Begin FreeMem(M);
   Msg:='aucune peau d'#130'tect'#130'e';Exit;End;
 N:=Int64(S.W)*S.H;
 Base:=AllocF(N*3);
 SkinBase(S,M,SkinRadius(S),Sigma,Base);
 For I:=0 to N-1 do Begin
  Mw:=M[I];
  If Mw<0.02 Then Continue;
  Dl:=(Abs(S.Pix[I*3]-Base[I*3])+Abs(S.Pix[I*3+1]-Base[I*3+1])+Abs(S.Pix[I*3+
    2]-Base[I*3+2]))*0.3333;
  { les traits marques (yeux, sourcils, levres) gardent leur detail }
  Keep:=K+(1-K)*SmoothStep(9,26,Dl);
  For C:=0 to 2 do Begin
   V:=Base[I*3+C]+(S.Pix[I*3+C]-Base[I*3+C])*Keep;
   V:=V*(1+Bright);
   S.Pix[I*3+C]:=S.Pix[I*3+C]*(1-Mw)+V*Mw;
  End;
 End;
 { peau de bebe : joues roses }
 If Blush>0 Then Begin
  If HeadInfo(S,H)Then Begin
   For Y:=Trunc(H.Fy0)to Trunc(H.Fy1)do
    For X:=Trunc(H.Fx0)to Trunc(H.Fx1)do Begin
     I:=Int64(Y)*S.W+X;
     If M[I]<0.02 Then Continue;
     Cheek:=Exp(-Sqr((Abs(X+0.5-H.Cx)-0.24*H.Fw)/(0.10*H.Fw))-Sqr((Y+
       0.5-(H.Fy0+0.62*H.Fh))/(0.10*H.Fh)));
     Dt:=(0.05+0.16*Cheek)*Blush*M[I];
     S.Pix[I*3]:=S.Pix[I*3]+(255-S.Pix[I*3])*Dt*0.55;
     S.Pix[I*3+1]:=S.Pix[I*3+1]+(150-S.Pix[I*3+1])*Dt*0.40;
     S.Pix[I*3+2]:=S.Pix[I*3+2]+(160-S.Pix[I*3+2])*Dt*0.40;
    End;
  End
   Else For I:=0 to N-1 do If M[I]>=0.02 Then Begin
    Dt:=0.05*Blush*M[I];
    S.Pix[I*3]:=S.Pix[I*3]+(255-S.Pix[I*3])*Dt*0.55;
    S.Pix[I*3+1]:=S.Pix[I*3+1]+(150-S.Pix[I*3+1])*Dt*0.40;
    S.Pix[I*3+2]:=S.Pix[I*3+2]+(160-S.Pix[I*3+2])*Dt*0.40;
   End;
 End;
 FreeMem(M);FreeMem(Base);
 SkinSmooth:=True;
 Info('  '+What);
End;

{ grain de peau : contraste des pores accentue et bruit fin }
Procedure SkinGrainPass(Var S:TScene;M:PSingle;Amount:Single;Boost:Single);
Var
 Base:PSingle;
 N,I:Int64;
 X,Y,C:LongInt;
 Nz,Mw,Pore:Single;
Begin
 N:=Int64(S.W)*S.H;
 Base:=AllocF(N*3);
 SkinBase(S,M,2,30,Base);
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   I:=Int64(Y)*S.W+X;
   Mw:=M[I];
   If Mw<0.02 Then Continue;
   Nz:=(RngGauss*0.55+(VNoise(X*0.8,Y*0.8)-0.5)*1.7)*Amount*6.5;
   Pore:=0;
   If Hash2(X,Y)>0.94 Then Pore:=-Amount*9*(0.5+0.5*Hash2(Y,X));
   For C:=0 to 2 do
    S.Pix[I*3+C]:=S.Pix[I*3+C]+Mw*((S.Pix[I*3+C]-Base[I*3+C])*Boost+Nz*(0.8+
      0.2*C*0.5)+Pore);
  End;
 FreeMem(Base);
End;

Function SkinGrain(Var S:TScene;Var Msg:AnsiString):Boolean;
Var
 M:PSingle;
Begin
 SkinGrain:=False;
 Msg:='';
 ColorInit;
 If not SkinMaskOf(S,M)Then Begin FreeMem(M);
   Msg:='aucune peau d'#130'tect'#130'e';Exit;End;
 SkinGrainPass(S,M,0.8,0.9);
 FreeMem(M);
 SkinGrain:=True;
 Info('  peau granuleuse (pores accentu'#130's, grain ajout'#130')');
End;

{ ---- cheveux : poivre et sel, ou gris partiel ---- }

Function HairSalt(Var S:TScene;Fraction:Single;SaltPepper:Boolean;Var
  Msg:AnsiString):Boolean;
Var
 M:PSingle;
 N:int64;I:LongInt;
 X,Y:LongInt;
 Lm,Sum,Rel,Nn,G,Salt,Pep,L:Single;
 Cnt:Int64;
 R,Gc,B,Mw:Single;
Begin
 HairSalt:=False;
 Msg:='';
 N:=Int64(S.W)*S.H;
 M:=AllocF(N);
 CatMask(S,msHair,M);
 SharpenAlpha(M,N);
 Sum:=0;Cnt:=0;
 For I:=0 to N-1 do If M[I]>=0.8 Then Begin Sum:=Sum+Luma(S.Pix[I*3],S.Pix[I*3+
   1],S.Pix[I*3+2]);Inc(Cnt);End;
 If Cnt<N div 4000 Then Begin FreeMem(M);
   Msg:='aucun cheveu d'#130'tect'#130' : impossible de les teindre';Exit;End;
 Lm:=Sum/Cnt;
 If Lm<1 Then Lm:=1;
 For Y:=0 to S.H-1 do
  For X:=0 to S.W-1 do Begin
   I:=Int64(Y)*S.W+X;
   Mw:=M[I];
   If Mw<0.02 Then Continue;
   L:=Luma(S.Pix[I*3],S.Pix[I*3+1],S.Pix[I*3+2]);
   Rel:=Clamp(L/Lm,0.35,1.6);
   Nn:=0.50*VNoise(X*0.70,Y*0.16)+0.30*VNoise(X*1.5+11,Y*0.35+5)+
     0.20*VNoise(X*0.25,Y*0.08+9);
   Nn:=Clamp((Nn-0.5)*2.4+0.5+0.30*(Rel-1),0,1);
   G:=SmoothStep(1-Fraction-0.16,1-Fraction+0.16,Nn);
   Salt:=Clamp(Rel*150+30,100,225);
   If SaltPepper Then Begin
    Pep:=22+48*Clamp(Rel,0,1.3);
    L:=Pep*(1-G)+Salt*G;
    R:=L*0.99;Gc:=L;B:=L*1.03;
   End
    Else Begin
     { gris partiel : les meches grises remplacent la couleur d'origine, le
       reste est a peine eteint }
     R:=S.Pix[I*3];Gc:=S.Pix[I*3+1];B:=S.Pix[I*3+2];
     L:=Luma(R,Gc,B);
     R:=L+(R-L)*0.88;Gc:=L+(Gc-L)*0.88;B:=L+(B-L)*0.88;
     G:=G*0.8;
     Salt:=L+(Salt-L)*0.75;
     R:=R*(1-G)+Salt*0.99*G;Gc:=Gc*(1-G)+Salt*G;B:=B*(1-G)+Salt*1.03*G;
    End;
   S.Pix[I*3]:=S.Pix[I*3]*(1-Mw)+R*Mw;
   S.Pix[I*3+1]:=S.Pix[I*3+1]*(1-Mw)+Gc*Mw;
   S.Pix[I*3+2]:=S.Pix[I*3+2]*(1-Mw)+B*Mw;
  End;
 FreeMem(M);
 HairSalt:=True;
 If SaltPepper Then Info('  cheveux poivre et sel')
 Else Info('  cheveux grisonnants ('+IStr(Round(Fraction*100))
   +' % de m'#138'ches grises)');
End;

{ ---- vieillissement : rides, cernes, taches, cheveux gris ---- }

{ ride : courbe douce de (X0,Y0) a (X1,Y1), Bend = fleche perpendiculaire }
Procedure Crease(Wr:PSingle;W,H:LongInt;X0,Y0,X1,Y1,Bend,Wd,Amp:Single;
  Seed:LongInt);
Var
 Len,Nx,Ny,T,Px,Py,A,D2,R:Single;
 I,Steps,X,Y,Rr:LongInt;
 K:Int64;
Begin
 Len:=Sqrt(Sqr(X1-X0)+Sqr(Y1-Y0));
 If Len<2 Then Exit;
 Nx:=-(Y1-Y0)/Len;Ny:=(X1-X0)/Len;
 Steps:=Trunc(Len*1.5)+2;
 Rr:=Trunc(2.6*Wd)+1;
 For I:=0 to Steps do Begin
  T:=I/Steps;
  Px:=X0+(X1-X0)*T+Nx*Bend*4*T*(1-T);
  Py:=Y0+(Y1-Y0)*T+Ny*Bend*4*T*(1-T);
  A:=Amp*Exp(0.6*Ln(FMax(Sin(Pi*T),0.001)))*(0.55+0.45*VNoise(T*Len*0.08+
    Seed*3.7,Seed*1.3));
  For Y:=Trunc(Py)-Rr to Trunc(Py)+Rr do
   For X:=Trunc(Px)-Rr to Trunc(Px)+Rr do Begin
    If(X<0)or(Y<0)or(X>=W)or(Y>=H)Then Continue;
    D2:=Sqr(X+0.5-Px)+Sqr(Y+0.5-Py);
    R:=A*Exp(-D2/(2*Wd*Wd));
    K:=Int64(Y)*W+X;
    If R>Wr[K]Then Wr[K]:=R;
   End;
 End;
End;

Function SkinAge(Var S:TScene;Years:LongInt;Var Msg:AnsiString):Boolean;
Var
 H:THeadInfo;
 M,Wr,Bag,Fm,Yl:PSingle;
 Ir:Array[0..1]of TIris;
 N:int64;K:LongInt;
 I,Side,Found,X,Y,Sp:LongInt;
 Sc,Fw,Fh,Cx,Fy0,Wd,Amp,Ex,Ey,Ox,Mw,Lskin,V,Sx,Sy,Rs,D,Dk:Single;
 Done:Boolean;
 Sg:LongInt;
Begin
 SkinAge:=False;
 Msg:='';
 ColorInit;
 Sc:=Years/10.0;
 If not SkinMaskOf(S,M)Then Begin FreeMem(M);
   Msg:='aucune peau d'#130'tect'#130'e';Exit;End;
 N:=Int64(S.W)*S.H;
 Done:=False;
 { peau plus terne et plus granuleuse }
 SkinGrainPass(S,M,0.30*Sc,0.30*Sc);
 For K:=0 to N-1 do If M[K]>=0.02 Then Begin
  Mw:=M[K]*0.07*Sc;
  V:=Luma(S.Pix[K*3],S.Pix[K*3+1],S.Pix[K*3+2]);
  For I:=0 to 2 do S.Pix[K*3+I]:=(S.Pix[K*3+I]+(V-S.Pix[K*3+I])*Mw)
    *(1-0.02*Sc*M[K]);
 End;
 If HeadInfo(S,H)and(H.Fw>=60)Then Begin
  Fw:=H.Fw;Fh:=H.Fh;Cx:=H.Cx;Fy0:=H.Fy0;
  Fm:=AllocF(N);
  CatMask(S,msFace,Fm);
  Yl:=LumaPlane(S);
  Found:=FindIrises(S,H,Yl,Ir,Lskin);
  FreeMem(Yl);
  Wr:=AllocF(N);Bag:=AllocF(N);
  Wd:=FMax(1.0,0.0065*Fh);
  Amp:=Clamp(0.75*Sc,0.30,1.0);
  { front : lignes horizontales }
  For I:=0 to 3 do
   Crease(Wr,S.W,S.H,Cx-0.30*Fw,Fy0+(0.08+0.050*I)*Fh,Cx+0.30*Fw,Fy0+(0.08+
     0.050*I)*Fh,(RngF-0.5)*0.03*Fh,Wd,Amp*(1-0.12*I),I+1);
  { entre les sourcils }
  If Sc>=0.9 Then Begin
   Crease(Wr,S.W,S.H,Cx-0.035*Fw,Fy0+0.29*Fh,Cx-0.030*Fw,Fy0+0.38*Fh,0.004*Fh,
     Wd,Amp*0.8,7);
   Crease(Wr,S.W,S.H,Cx+0.035*Fw,Fy0+0.29*Fh,Cx+0.030*Fw,Fy0+0.38*Fh,
     -0.004*Fh,Wd,Amp*0.8,8);
  End;
  For Side:=0 to 1 do Begin
   Sg:=Side*2-1;
   If Ir[Side].Ok Then Begin Ex:=Ir[Side].Cx;Ey:=Ir[Side].Cy;End
   Else Begin Ex:=Cx+Sg*0.225*Fw;Ey:=Fy0+0.42*Fh;End;
   Ox:=Ex+Sg*0.13*Fw;
   { pattes d'oie }
   Crease(Wr,S.W,S.H,Ox,Ey-0.01*Fh,Ox+Sg*0.095*Fw,Ey-0.055*Fh,Sg*0.006*Fh,
     Wd*0.9,Amp*0.9,10+Side);
   Crease(Wr,S.W,S.H,Ox,Ey+0.01*Fh,Ox+Sg*0.105*Fw,Ey+0.005*Fh,Sg*0.004*Fh,
     Wd*0.9,Amp,12+Side);
   Crease(Wr,S.W,S.H,Ox,Ey+0.03*Fh,Ox+Sg*0.095*Fw,Ey+0.060*Fh,-Sg*0.006*Fh,
     Wd*0.9,Amp*0.9,14+Side);
   { sillon nasogenien }
   Crease(Wr,S.W,S.H,Cx+Sg*0.15*Fw,Fy0+0.57*Fh,Cx+Sg*0.235*Fw,Fy0+0.81*Fh,
     Sg*0.025*Fw,Wd*1.3,Amp*0.55,20+Side);
   { cerne sous l'oeil : croissant sombre et flou }
   For Y:=Trunc(Ey+0.01*Fh)to Trunc(Ey+0.13*Fh)do
    For X:=Trunc(Ex-0.14*Fw)to Trunc(Ex+0.14*Fw)do Begin
     If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Continue;
     D:=Sqr((X+0.5-Ex)/(0.10*Fw))+Sqr((Y+0.5-(Ey+0.075*Fh))/(0.032*Fh));
     K:=Int64(Y)*S.W+X;
     Dk:=Exp(-D)*0.34*Clamp(Sc,0.4,1.1);
     If Dk>Bag[K]Then Bag[K]:=Dk;
    End;
  End;
  BoxBlur(Wr,Wr,S.W,S.H,1);
  For K:=0 to N-1 do Begin
   Mw:=Fm[K];
   If Mw<0.1 Then Continue;
   V:=Wr[K];If V>1 Then V:=1;
   S.Pix[K*3]:=S.Pix[K*3]*(1-0.48*V*Mw);
   S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-0.60*V*Mw);
   S.Pix[K*3+2]:=S.Pix[K*3+2]*(1-0.60*V*Mw);
   V:=Bag[K];
   S.Pix[K*3]:=S.Pix[K*3]*(1-0.55*V*Mw);
   S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-0.80*V*Mw);
   S.Pix[K*3+2]:=S.Pix[K*3+2]*(1-0.70*V*Mw);
  End;
  { taches de vieillesse sur le front et les joues }
  For Sp:=1 to Trunc(7*Sc)+1 do Begin
   Sx:=Cx+(RngF-0.5)*0.62*Fw;Sy:=Fy0+(0.10+RngF*0.62)*Fh;
   Rs:=(0.010+0.012*RngF)*Fw;
   For Y:=Trunc(Sy-2*Rs)to Trunc(Sy+2*Rs)do
    For X:=Trunc(Sx-2*Rs)to Trunc(Sx+2*Rs)do Begin
     If(X<0)or(Y<0)or(X>=S.W)or(Y>=S.H)Then Continue;
     K:=Int64(Y)*S.W+X;
     If Fm[K]<0.9 Then Continue;
     V:=0.32*Clamp(Sc,0.3,1.3)*Exp(-(Sqr(X+0.5-Sx)+Sqr(Y+0.5-Sy))/(2*Rs*Rs));
     S.Pix[K*3]:=S.Pix[K*3]*(1-0.22*V);
     S.Pix[K*3+1]:=S.Pix[K*3+1]*(1-0.42*V);
     S.Pix[K*3+2]:=S.Pix[K*3+2]*(1-0.62*V);
    End;
  End;
  FreeMem(Wr);FreeMem(Bag);FreeMem(Fm);
  Done:=True;
  Info('  rides, cernes et taches dessin'#130's (+'+IStr(Years)+' ans)');
 End
  Else Warn(
    'visage non d'#130'tect'#130' ou trop petit : rides non dessin'#130'es '+
    '(texture seulement)');
 FreeMem(M);
 { cheveux : meches grises }
 If HairSalt(S,Clamp(0.22*Sc,0.05,0.6),False,Msg)Then Done:=True;
 Msg:='';
 SkinAge:=True;
End;

{ ---- repartiteur ---- }

Function ApplySkin(Var S:TScene;Const E:TEdit;Var Msg:AnsiString):Boolean;
Var
 N:LongInt;
Begin
 Msg:='';
 ApplySkin:=False;
 Case E.SkinOp of
  soSmooth:ApplySkin:=SkinSmooth(S,0.28,18,0.0,0.0,'peau liss'#130'e',Msg);
  soSoft:ApplySkin:=SkinSmooth(S,0.45,22,0.02,0.2,'peau plus douce',Msg);
  soBaby:ApplySkin:=SkinSmooth(S,0.08,26,0.05,
    1.0,'peau de b'#130'b'#130' (liss'#130'e, claire, joues ros'#130'es)',Msg);
  soGrain:ApplySkin:=SkinGrain(S,Msg);
  soAge:Begin
   N:=Abs(E.Years);
   If E.Years<0 Then
    ApplySkin:=SkinSmooth(S,Clamp(1-0.065*N,0.15,0.95),20,0.004*N,
      0.1*N/10.0,'rajeunissement de '+IStr(N)
      +' ans (peau liss'#130'e et plus claire)',Msg)
   Else ApplySkin:=SkinAge(S,N,Msg);
  End;
  soSalt:ApplySkin:=HairSalt(S,0.5,True,Msg);
 End;
End;
{ ------------------------------------------------------------------ }
{ Forets dessinees par le programme : tropicale, amazonienne,        }
{ quebecoise (automne), canadienne, de coniferes                       }
{ ------------------------------------------------------------------ }

Type
 TRgb=Array[0..2]of Single;
 TFPal=Record
  SkyT,SkyB,Fog,Trunk,Ground,Ground2,Light:TRgb;
  Leaf:Array[0..2]of TRgb;
  Conif:Array[0..1]of TRgb;
  Lit:Array[0..1]of TRgb;
  Mist,Shafts,Fr,Fb,Fp:Single;
  Giant,Lianas,Flowers,Mount:Boolean;
 End;

Var
 FogC:TRgb;
 FogAmt:Single=0;

Procedure C3(Var C:TRgb;R,G,B:Single);
Begin
 C[0]:=R;C[1]:=G;C[2]:=B;
End;

{ pose un pixel avec la brume de la profondeur courante }
Procedure PutF(Bg:PSingle;W,H,X,Y:LongInt;Cov,R,G,B:Single);
Begin
 If FogAmt>0 Then Begin
  R:=R*(1-FogAmt)+FogC[0]*FogAmt;
  G:=G*(1-FogAmt)+FogC[1]*FogAmt;
  B:=B*(1-FogAmt)+FogC[2]*FogAmt;
 End;
 PutBg(Bg,W,H,X,Y,Cov,R,G,B);
End;

{ masse de feuillage : disque ebouriffe, eclaire en haut a gauche, texture de
  feuilles }
Procedure Blob(Bg:PSingle;W,H:LongInt;Cx,Cy,R:Single;Const C:TRgb;Leaf:Single);
Var
 X,Y:LongInt;
 D,Cov,Nx,Ny,Lt,Tx,V,Rr:Single;
Begin
 For Y:=Trunc(Cy-R*1.2)to Trunc(Cy+R*1.2)do
  For X:=Trunc(Cx-R*1.2)to Trunc(Cx+R*1.2)do Begin
   If(X<0)or(Y<0)or(X>=W)or(Y>=H)Then Continue;
   Rr:=R*(1+0.20*(VNoise(X*Leaf*0.7,Y*Leaf*0.7)-0.5));
   D:=Sqrt(Sqr(X+0.5-Cx)+Sqr(Y+0.5-Cy))-Rr;
   Cov:=CoverD(D);
   If Cov<=0 Then Continue;
   Nx:=(X+0.5-Cx)/R;Ny:=(Y+0.5-Cy)/R;
   Lt:=Clamp(0.78+0.50*(-0.45*Nx-0.70*Ny),0.35,1.3);
   Tx:=FBm(X*Leaf,Y*Leaf);
   V:=Lt*(0.66+0.70*Tx);
   PutF(Bg,W,H,X,Y,Cov,C[0]*V,C[1]*V,C[2]*V);
  End;
End;

Procedure Crown(Bg:PSingle;W,H:LongInt;X,Y,R:Single;Const P:TFPal;
  Autumn:Boolean);
Var
 I,K:LongInt;
 A,Rr,Lf:Single;
Begin
 Lf:=0.55/FMax(1,R/22);
 For I:=0 to 8 do Begin
  A:=RngF*2*Pi;Rr:=R*0.55*RngF;
  K:=Trunc(RngF*2.99);
  Blob(Bg,W,H,X+Cos(A)*Rr*1.15,Y+Sin(A)*Rr*0.8,R*(0.42+0.26*RngF),P.Leaf[K],Lf);
 End;
 For I:=0 to 24 do Begin
  A:=RngF*2*Pi;Rr:=R*(0.55+0.35*RngF);
  K:=Trunc(RngF*2.99);
  Blob(Bg,W,H,X+Cos(A)*Rr*1.1,Y+Sin(A)*Rr*0.78,R*0.14,P.Leaf[K],Lf*1.8);
 End;
End;

{ tronc effile, eclaire a gauche, ecorce en stries verticales ; Birch : tronc
  blanc marque de noir }
Procedure Trunk(Bg:PSingle;W,H:LongInt;X,YTop,YBot,W0,W1,Lean:Single;Const
  C:TRgb;Seed:LongInt;Birch:Boolean);
Var
 Y,Xi:LongInt;
 T,Wd,Xc,U,Sh,Bk,Cov,V:Single;
 Mark:Boolean;
Begin
 For Y:=Trunc(YTop)to Trunc(YBot)do Begin
  If(Y<0)or(Y>=H)Then Continue;
  T:=(Y+0.5-YTop)/FMax(1,YBot-YTop);
  Wd:=W0+(W1-W0)*T;
  If T>0.93 Then Wd:=Wd*(1+0.9*(T-0.93)/0.07);
  Xc:=X+Lean*(1-T);
  Mark:=Birch and(Hash2(Trunc((Y+0.5)/FMax(2,H*0.005)),Seed)>0.88);
  For Xi:=Trunc(Xc-Wd)-1 to Trunc(Xc+Wd)+1 do Begin
   If(Xi<0)or(Xi>=W)Then Continue;
   U:=(Xi+0.5-Xc)/Wd;
   Cov:=CoverD(Abs(Xi+0.5-Xc)-Wd);
   If Cov<=0 Then Continue;
   If U>1 Then U:=1 Else If U<-1 Then U:=-1;
   Sh:=0.42+0.62*(Sqrt(1-U*U)*0.7+0.3*(-U)*0.6+0.25);
   Bk:=0.72+0.55*VNoise(Xi*0.9+Seed*3.1,Y*0.045);
   V:=Sh*Bk;
   If Mark and(Abs(U)<0.80)Then V:=V*0.40;
   PutF(Bg,W,H,Xi,Y,Cov,C[0]*V,C[1]*V,C[2]*V);
  End;
 End;
End;

{ conifere : etages de branches en dents de scie, plus sombres dessous }
Procedure Conifer(Bg:PSingle;W,H:LongInt;X,YBase,Ht,Wd:Single;Const P:TFPal;
  Seed:LongInt);
Var
 I,N,Y,Xi,K:LongInt;
 Y0,Th,Hw,T,Hy,Cov,V,U,Sh:Single;
Begin
 Trunk(Bg,W,H,X,YBase-Ht*0.25,YBase,Wd*0.045,Wd*0.06,0,P.Conif[1],Seed,False);
 N:=8+Trunc(Ht/H*6);
 For I:=0 to N-1 do Begin
  Y0:=YBase-Ht+I*(Ht*0.80/N);
  Th:=Ht*0.30;
  Hw:=Wd/2*(0.22+0.78*I/(N-1));
  K:=I and 1;
  For Y:=Trunc(Y0)to Trunc(Y0+Th)do Begin
   If(Y<0)or(Y>=H)Then Continue;
   T:=(Y+0.5-Y0)/Th;
   Hy:=Hw*Exp(0.85*Ln(FMax(T,0.001)))*(1+0.16*Sin(Y*1.1+I*2.3)+
     0.14*(VNoise(Y*0.9+Seed,I*5.0)-0.5));
   For Xi:=Trunc(X-Hy)-1 to Trunc(X+Hy)+1 do Begin
    If(Xi<0)or(Xi>=W)Then Continue;
    Cov:=CoverD(Abs(Xi+0.5-X)-Hy);
    If Cov<=0 Then Continue;
    U:=(Xi+0.5-X)/FMax(Hy,1);
    Sh:=0.50+0.62*(1-T*0.65)+0.22*(-U);
    V:=Sh*(0.70+0.62*FBm(Xi*0.45+Seed,Y*0.60));
    PutF(Bg,W,H,Xi,Y,Cov,P.Conif[K][0]*V,P.Conif[K][1]*V,P.Conif[K][2]*V);
   End;
  End;
 End;
End;

{ palme : fronde arquee aux folioles dentelees }
Procedure Frond(Bg:PSingle;W,H:LongInt;X0,Y0,Ang,Len,Droop,Wd:Single;Const
  C:TRgb);
Var
 I,Steps,X,Y,Rr:LongInt;
 T,Px,Py,R,Cov,V,D:Single;
Begin
 Steps:=Trunc(Len/1.1)+4;
 For I:=0 to Steps do Begin
  T:=I/Steps;
  Px:=X0+Cos(Ang)*Len*T;
  Py:=Y0+Sin(Ang)*Len*T+Droop*Len*T*T;
  R:=Wd*(0.30+0.70*Sin(Pi*FMin(1,T*1.05+0.02)))*(0.70+0.30*Sin(T*Len*0.42));
  If R<0.6 Then R:=0.6;
  V:=0.55+0.55*(1-T)*0.6+0.28*Sin(T*Len*0.42+1)*0.5+0.25;
  Rr:=Trunc(R)+1;
  For Y:=Trunc(Py)-Rr to Trunc(Py)+Rr do
   For X:=Trunc(Px)-Rr to Trunc(Px)+Rr do Begin
    If(X<0)or(Y<0)or(X>=W)or(Y>=H)Then Continue;
    D:=Sqrt(Sqr(X+0.5-Px)+Sqr(Y+0.5-Py));
    Cov:=CoverD(D-R);
    If Cov<=0 Then Continue;
    PutF(Bg,W,H,X,Y,Cov,C[0]*V,C[1]*V,C[2]*V);
   End;
 End;
End;

Procedure Palm(Bg:PSingle;W,H:LongInt;X,YBase,Ht:Single;Const P:TFPal;
  Seed:LongInt);
Var
 I:LongInt;
 Lean,A,Xt,Yt:Single;
Begin
 Lean:=(RngF-0.5)*Ht*0.35;
 Xt:=X+Lean;Yt:=YBase-Ht*0.88;
 Trunk(Bg,W,H,X,Yt,YBase,Ht*0.020,Ht*0.032,Lean,P.Trunk,Seed,False);
 For I:=0 to 10 do Begin
  A:=-Pi*(0.08+0.84*I/10)+(RngF-0.5)*0.15;
  Frond(Bg,W,H,Xt,Yt,A,Ht*(0.30+0.12*RngF),0.55,Ht*0.030,P.Leaf[I mod 3]);
 End;
End;

{ grande feuille (monstera, bananier) : ellipse inclinee, nervure claire }
Procedure BigLeaf(Bg:PSingle;W,H:LongInt;Cx,Cy,Rx,Ry,Ang:Single;Const C:TRgb);
Var
 X,Y:LongInt;
 Dx,Dy,Uu,Vv,L,Cov,V,Vein:Single;
 R:Single;
Begin
 R:=FMax(Rx,Ry);
 For Y:=Trunc(Cy-R)-1 to Trunc(Cy+R)+1 do
  For X:=Trunc(Cx-R)-1 to Trunc(Cx+R)+1 do Begin
   If(X<0)or(Y<0)or(X>=W)or(Y>=H)Then Continue;
   Dx:=X+0.5-Cx;Dy:=Y+0.5-Cy;
   Uu:=Dx*Cos(Ang)+Dy*Sin(Ang);Vv:=-Dx*Sin(Ang)+Dy*Cos(Ang);
   { forme de feuille : pointue aux deux bouts }
   L:=Sqrt(Sqr(Uu/Rx)+Sqr(Vv/(Ry*FMax(0.15,1-0.55*Sqr(Uu/Rx)))));
   Cov:=CoverD((L-1)*FMin(Rx,Ry));
   If Cov<=0 Then Continue;
   Vein:=Exp(-Sqr(Vv/(0.04*Ry+0.5)))*0.55+0.14*Exp(-Sqr(Frac(Uu/(0.22*Rx)+
     Abs(Vv)/(0.5*Ry)*0.6)-0.5)*40);
   V:=(0.62+0.42*(1-L)+0.20*FBm(X*0.04,Y*0.04))*(0.9+0.2*(-Vv/Ry));
   PutF(Bg,W,H,X,Y,Cov,C[0]*V+Vein*70,C[1]*V+Vein*80,C[2]*V+Vein*40);
  End;
End;

{ lianes pendantes }
Procedure Lianas(Bg:PSingle;W,H:LongInt;X0,Y1,Len:Single;Const C:TRgb;
  Seed:LongInt);
Var
 Y,Xi:LongInt;
 Px,T,Cov,V:Single;
Begin
 For Y:=0 to Trunc(Y1+Len)do Begin
  If Y>=H Then Break;
  T:=Y/FMax(1,Y1+Len);
  Px:=X0+Sin(Y*0.012+Seed)*H*0.006+Sin(Y*0.05+Seed*2)*H*0.0015;
  For Xi:=Trunc(Px)-2 to Trunc(Px)+2 do Begin
   If(Xi<0)or(Xi>=W)Then Continue;
   Cov:=CoverD(Abs(Xi+0.5-Px)-FMax(0.8,H*0.0025));
   V:=0.7+0.5*VNoise(Y*0.3,Seed*1.7);
   PutF(Bg,W,H,Xi,Y,Cov,C[0]*V,C[1]*V,C[2]*V);
  End;
 End;
End;

{ fougere au sol }
Procedure Fern(Bg:PSingle;W,H:LongInt;X,Y,Sz:Single;Const C:TRgb);
Var
 I:LongInt;
Begin
 For I:=0 to 7 do
  Frond(Bg,W,H,X,Y,-Pi*(0.10+0.80*I/7),Sz*(0.7+0.4*RngF),0.55,Sz*0.07,C);
End;

Procedure ForestPalette(Kind:LongInt;Var P:TFPal);
Begin
 P.Giant:=False;P.Lianas:=False;P.Flowers:=False;P.Mount:=False;
 P.Fr:=0;P.Fb:=0;P.Fp:=0;P.Mist:=0.3;P.Shafts:=0.7;
 C3(P.Lit[0],150,92,48);C3(P.Lit[1],110,70,38);
 C3(P.Conif[0],26,72,54);C3(P.Conif[1],18,56,46);
 Case Kind of
  boTropical:Begin
   C3(P.SkyT,120,190,232);C3(P.SkyB,214,238,228);C3(P.Fog,190,226,206);
   C3(P.Trunk,128,100,76);C3(P.Ground,50,92,36);C3(P.Ground2,20,46,24);
     C3(P.Light,255,246,196);
   C3(P.Leaf[0],36,138,44);C3(P.Leaf[1],84,184,60);C3(P.Leaf[2],22,104,52);
   P.Fp:=0.40;P.Lianas:=True;P.Flowers:=True;P.Mist:=0.35;P.Shafts:=0.85;
  End;
  boAmazon:Begin
   C3(P.SkyT,150,184,186);C3(P.SkyB,186,212,202);C3(P.Fog,150,186,170);
   C3(P.Trunk,108,86,68);C3(P.Ground,36,60,30);C3(P.Ground2,12,28,18);
     C3(P.Light,236,240,190);
   C3(P.Leaf[0],22,92,46);C3(P.Leaf[1],36,120,60);C3(P.Leaf[2],12,66,42);
   P.Fp:=0.25;P.Giant:=True;P.Lianas:=True;P.Mist:=0.65;P.Shafts:=0.75;
  End;
  boConifer:Begin
   C3(P.SkyT,126,158,186);C3(P.SkyB,198,216,224);C3(P.Fog,176,198,208);
   C3(P.Trunk,92,70,56);C3(P.Ground,92,64,38);C3(P.Ground2,42,34,26);
     C3(P.Light,242,242,222);
   C3(P.Leaf[0],34,86,56);C3(P.Leaf[1],26,70,50);C3(P.Leaf[2],40,100,64);
   C3(P.Conif[0],24,76,60);C3(P.Conif[1],14,54,46);
   P.Fr:=1.0;P.Mist:=0.5;P.Shafts:=0.6;
  End;
  boCanada:Begin
   C3(P.SkyT,92,148,216);C3(P.SkyB,204,226,242);C3(P.Fog,192,212,228);
   C3(P.Trunk,100,78,62);C3(P.Ground,66,96,44);C3(P.Ground2,32,54,30);
     C3(P.Light,255,244,208);
   C3(P.Leaf[0],56,128,42);C3(P.Leaf[1],92,160,54);C3(P.Leaf[2],36,98,42);
   P.Fr:=0.5;P.Fb:=0.15;P.Mount:=True;P.Mist:=0.3;P.Shafts:=0.55;
   C3(P.Lit[0],130,150,70);C3(P.Lit[1],100,80,44);
  End;
  Else Begin
   { foret quebecoise : erables d'automne, bouleaux, quelques sapins }
   C3(P.SkyT,150,184,218);C3(P.SkyB,238,226,204);C3(P.Fog,230,212,190);
   C3(P.Trunk,104,82,64);C3(P.Ground,128,78,34);C3(P.Ground2,72,46,26);
     C3(P.Light,255,228,162);
   C3(P.Leaf[0],200,58,28);C3(P.Leaf[1],236,136,32);C3(P.Leaf[2],240,194,50);
   P.Fr:=0.20;P.Fb:=0.25;P.Mist:=0.25;P.Shafts:=0.7;
   C3(P.Lit[0],216,100,30);C3(P.Lit[1],238,178,52);
  End;
 End;
End;

Procedure SkyForest(Bg:PSingle;W,H:LongInt;Kind:LongInt;Hor:Single);
Const
 Scl:Array[0..4]of Single=(0.30,0.45,0.65,0.90,1.25);
 OffY:Array[0..4]of Single=(0.0,0.012,0.035,0.075,0.13);
 FogK:Array[0..4]of Single=(0.72,0.52,0.33,0.15,0.0);
 NTree:Array[0..4]of LongInt=(10,8,6,4,2);
Var
 P:TFPal;
 X,Y,D,I,N,Seed:LongInt;
 T,Sc,Yb,Ht,Xt,R,Tw,V,Gx,Gt,Nz,Dist,Fade,Al,S0,Px,Ang,Ln:Single;
 K:LongInt;
 KK:Int64;
 BirchC:TRgb;
 Autumn:Boolean;
Begin
 C3(BirchC,228,226,216);
 If Kind=boForest Then Kind:=boQuebec;
 ForestPalette(Kind,P);
 Autumn:=Kind=boQuebec;
 FogAmt:=0;
 { ciel }
 VGradient(Bg,W,H,0,H-1,P.SkyT[0],P.SkyT[1],P.SkyT[2],P.SkyB[0],P.SkyB[1],
   P.SkyB[2]);
 Clouds(Bg,W,H,0,Trunc(Hor),0.8/FMax(40,0.16*W),0.55);
 { montagnes lointaines (Canada) }
 If P.Mount Then
  For X:=0 to W-1 do Begin
   Yb:=Hor-H*(0.10+0.16*FBm(X*2.2/W,5.0)+0.08*Sin(X*3.0/W));
   For Y:=Trunc(Yb)to Trunc(Hor)do Begin
    V:=1-0.35*(Y-Yb)/FMax(1,Hor-Yb);
    PutBg(Bg,W,H,X,Y,1,(112+30*(Y-Yb)/H*3)*V,(134+20*(Y-Yb)/H*3)*V,(168+
      10*(Y-Yb)/H*3)*V);
    If Y-Yb<H*0.02 Then PutBg(Bg,W,H,X,Y,0.7*(1-(Y-Yb)/(H*0.02)),238,242,248);
   End;
  End;
 { sol : degrade, feuilles mortes ou sous-bois }
 For Y:=Trunc(Hor)to H-1 do Begin
  T:=(Y-Hor)/FMax(1,H-Hor);
  For X:=0 to W-1 do Begin
   Nz:=FBm(X*7.0/W,Y*7.0/W*1.8);
   V:=0.55+0.55*Nz;
   Bg[(Int64(Y)*W+X)*3]:=(P.Ground2[0]*(1-T)+P.Ground[0]*T)*V;
   Bg[(Int64(Y)*W+X)*3+1]:=(P.Ground2[1]*(1-T)+P.Ground[1]*T)*V;
   Bg[(Int64(Y)*W+X)*3+2]:=(P.Ground2[2]*(1-T)+P.Ground[2]*T)*V;
   { feuilles mortes, aiguilles }
   If(Hash2(X div 3,Y div 2)>0.90-0.04*T)and(Kind<>boTropical)
     and(Kind<>boAmazon)Then Begin
    K:=Trunc(Hash2(X div 3+9,Y div 2+4)*1.99);
    PutBg(Bg,W,H,X,Y,0.65,P.Lit[K][0]*(0.7+0.5*Nz),P.Lit[K][1]*(0.7+0.5*Nz),
      P.Lit[K][2]*(0.7+0.5*Nz));
   End;
  End;
 End;
 { couches d'arbres, du lointain au premier plan }
 For D:=0 to 4 do Begin
  FogAmt:=Clamp(FogK[D]*(0.55+P.Mist*1.2),0,0.92);
  FogC:=P.Fog;
  Sc:=Scl[D];
  Yb:=Hor+OffY[D]*H;
  N:=NTree[D];
  If P.Giant and(D>=2)Then N:=N+1;
  For I:=0 to N-1 do Begin
   Seed:=D*37+I*11+Kind;
   If D=4 Then Begin
    If I=0 Then Xt:=W*(0.03+0.07*RngF) Else Xt:=W*(0.90+0.07*RngF);
   End
   Else Xt:=W*(-0.04+1.08*(I+RngF)/N);
   Ht:=H*(0.50+0.12*RngF)*Sc*(1.0+0.1*Kind*0);
   Tw:=W*0.012*Sc*(0.8+0.5*RngF);
   T:=RngF;
   If P.Giant and(D>=2)Then Begin
    { fut immense dont la couronne depasse du cadre, lianes }
    Trunk(Bg,W,H,Xt,-0.2*H,Yb,W*0.012*Sc*(1.0+0.6*RngF),W*0.022*Sc*(1.0+
      0.6*RngF),(RngF-0.5)*W*0.03,P.Trunk,Seed,False);
    If P.Lianas Then Lianas(Bg,W,H,Xt+(RngF-0.5)*W*0.05*Sc,0,H*(0.35+0.4*RngF)
      *Sc,P.Leaf[1],Seed);
   End
   Else If T<P.Fr Then Conifer(Bg,W,H,Xt,Yb,Ht*1.05*(1+0.2*Ord(P.Fr>=1)),
     Ht*0.45,P,Seed)
   Else If T<P.Fr+P.Fb Then Begin
    Trunk(Bg,W,H,Xt,Yb-Ht*0.80,Yb,Tw*0.8,Tw*1.05,(RngF-0.5)*Ht*0.06,BirchC,
      Seed,True);
    Crown(Bg,W,H,Xt,Yb-Ht*0.86,Ht*0.15,P,Autumn);
   End
   Else If T<P.Fr+P.Fb+P.Fp Then Palm(Bg,W,H,Xt,Yb,Ht,P,Seed)
   Else Begin
    Trunk(Bg,W,H,Xt,Yb-Ht*0.62,Yb,Tw,Tw*1.35,(RngF-0.5)*Ht*0.08,P.Trunk,
      Seed,False);
    Crown(Bg,W,H,Xt+(RngF-0.5)*Ht*0.06,Yb-Ht*0.72,Ht*0.30,P,Autumn);
    If P.Lianas and(D>=3)Then Lianas(Bg,W,H,Xt+Tw*3,Yb-Ht*0.6,Ht*0.4,
      P.Leaf[2],Seed);
   End;
  End;
 End;
 FogAmt:=0;
 { premier plan : grandes feuilles, fougeres, fleurs, branches de coniferes }
 If(Kind=boTropical)or(Kind=boAmazon)Then Begin
  For I:=0 to 5 do Begin
   If I<3 Then Px:=W*(0.01+0.12*RngF) Else Px:=W*(0.87+0.12*RngF);
   R:=H*(0.10+0.07*RngF);
   BigLeaf(Bg,W,H,Px,H*(0.80+0.18*RngF),R*1.5,R*0.62,-Pi*(0.15+0.7*RngF),
     P.Leaf[I mod 3]);
  End;
  For I:=0 to 9 do Fern(Bg,W,H,W*RngF,H*(0.80+0.18*RngF),H*0.11,P.Leaf[I mod
    3]);
  If P.Flowers Then
   For I:=0 to 16 do Begin
    Px:=W*RngF;Gx:=H*(0.68+0.30*RngF);R:=H*(0.006+0.006*RngF);
    For Y:=Trunc(Gx-R*2)to Trunc(Gx+R*2)do
     For X:=Trunc(Px-R*2)to Trunc(Px+R*2)do Begin
      Dist:=Sqrt(Sqr(X+0.5-Px)+Sqr(Y+0.5-Gx));
      If Dist<R*2 Then Begin
       Ang:=ATan2F(Y+0.5-Gx,X+0.5-Px);
       Al:=CoverD(Dist-R*(1.0+0.5*Cos(Ang*5)));
       PutBg(Bg,W,H,X,Y,Al,236,(50+60*Hash2(I,3)),(40+40*Hash2(I,7)));
       PutBg(Bg,W,H,X,Y,CoverD(Dist-R*0.35),255,214,70);
      End;
     End;
   End;
 End
 Else If Kind=boConifer Then Begin
  For I:=0 to 6 do Begin
   If I<3 Then Px:=W*(0.0+0.15*RngF) Else Px:=W*(0.85+0.15*RngF);
   Ang:=Pi*(0.20+0.35*RngF);
   If Px>W*0.5 Then Ang:=Pi-Ang;
   Frond(Bg,W,H,Px,-H*0.02,Ang,H*(0.28+0.14*RngF),0.0,H*0.030,P.Conif[I and 1]);
  End;
 End
 Else Begin
  { feuillage flou en haut des coins }
  For I:=0 to 7 do Begin
   Px:=W*(0.05+0.9*RngF);
   If(Px>W*0.25)and(Px<W*0.75)Then Px:=Px+W*0.4*(1-2*Ord(Px<W*0.5));
   Blob(Bg,W,H,Px,-H*0.01+H*0.05*RngF,H*(0.06+0.05*RngF),P.Leaf[I mod 3],0.2);
  End;
 End;
 { rayons de lumiere dans la brume }
 For K:=0 to 5 do Begin
  S0:=W*(0.05+0.9*(K+RngF*0.6)/6);
  Ang:=0.30+0.1*RngF;
  Gt:=0.025*W*(0.7+0.8*RngF);
  For Y:=0 to H-1 do Begin
   Fade:=(1-0.8*Y/H);
   For X:=0 to W-1 do Begin
    Dist:=(X+0.5-S0-Y*Ang)*Cos(Ang*0.9);
    Al:=Exp(-Sqr(Dist/Gt))*Fade*P.Shafts*0.22*(0.55+0.45*FBm(X*0.004,Y*0.012+
      K*3));
    If Al>0.004 Then PutBg(Bg,W,H,X,Y,Al,P.Light[0],P.Light[1],P.Light[2]);
   End;
  End;
 End;
 { brume au sol, vignettage }
 For Y:=0 to H-1 do
  For X:=0 to W-1 do Begin
   Al:=P.Mist*0.55*Exp(-Sqr((Y-Hor)/(0.09*H)));
   If Al>0.004 Then PutBg(Bg,W,H,X,Y,Al,P.Fog[0],P.Fog[1],P.Fog[2]);
   V:=1-0.30*Sqr(Sqrt(Sqr(X/W-0.5)+Sqr(Y/H-0.5))*1.35);
   KK:=(Int64(Y)*W+X)*3;
   Bg[KK]:=Bg[KK]*V;Bg[KK+1]:=Bg[KK+1]*V;Bg[KK+2]:=Bg[KK+2]*V;
  End;
End;
{ ------------------------------------------------------------------ }
{ Image entiere (lisse, floue, nette) et arriere-plan (uni, ciel       }
{ etoile, ciel ensoleille, coucher de soleil, flou, transparent)        }
{ ------------------------------------------------------------------ }

Var
 OutAlpha:PByte=Nil;          { transparence a ecrire dans le PNG (fond
   transparent) }
 OutAlphaN:Int64=0;

{ flou gaussien approximatif de la photo entiere }
Procedure BlurRgb(Pix:PSingle;W,H:LongInt;Sigma:Single);
Var
 P:PSingle;
 N:int64;K:LongInt;
 C:LongInt;
Begin
 N:=Int64(W)*H;
 P:=AllocF(N);
 For C:=0 to 2 do Begin
  For K:=0 to N-1 do P[K]:=Pix[K*3+C];
  BlurPlane(P,W,H,Sigma);
  For K:=0 to N-1 do Pix[K*3+C]:=P[K];
 End;
 FreeMem(P);
End;

Function ImageSmooth(Var S:TScene;Var Msg:AnsiString):Boolean;
Var
 M,Base:PSingle;
 N:int64;K:LongInt;
 C,R:LongInt;
 Dl,Keep:Single;
Begin
 Msg:='';
 N:=Int64(S.W)*S.H;
 M:=AllocF(N);
 For K:=0 to N-1 do M[K]:=1;
 Base:=AllocF(N*3);
 R:=ClampI(Round(0.004*IMax(S.W,S.H)),2,7);
 SkinBase(S,M,R,20,Base);
 For K:=0 to N-1 do Begin
  Dl:=(Abs(S.Pix[K*3]-Base[K*3])+Abs(S.Pix[K*3+1]-Base[K*3+1])+Abs(S.Pix[K*3+
    2]-Base[K*3+2]))*0.3333;
  Keep:=0.22+0.78*SmoothStep(10,28,Dl);
  For C:=0 to 2 do S.Pix[K*3+C]:=Base[K*3+C]+(S.Pix[K*3+C]-Base[K*3+C])*Keep;
 End;
 FreeMem(M);FreeMem(Base);
 Info('  image liss'#130'e (grain et textures fines att'#130'nu'#130's, '+
   'contours conserv'#130's)');
 ImageSmooth:=True;
End;

Function ImageBlur(Var S:TScene;Var Msg:AnsiString):Boolean;
Begin
 Msg:='';
 BlurRgb(S.Pix,S.W,S.H,FMax(1.5,0.008*IMax(S.W,S.H)));
 Info('  image floue');
 ImageBlur:=True;
End;

Function ImageSharpen(Var S:TScene;Var Msg:AnsiString):Boolean;
Var
 B:PSingle;
 N:int64;K:LongInt;
 Sg:Single;
Begin
 Msg:='';
 N:=Int64(S.W)*S.H*3;
 B:=AllocF(N);
 Move(S.Pix^,B^,N*4);
 Sg:=FMax(1.0,0.0025*IMax(S.W,S.H));
 BlurRgb(B,S.W,S.H,Sg);
 For K:=0 to N-1 do S.Pix[K]:=S.Pix[K]+(S.Pix[K]-B[K])*0.9;
 FreeMem(B);
 Info('  image plus nette');
 ImageSharpen:=True;
End;

{ ---- arriere-plan ---- }

{ opacite de la personne (0..1), bords adoucis }
Procedure MatteAlpha(Const S:TScene;A:PSingle);
Var
 N:int64;K:LongInt;
Begin
 N:=Int64(S.W)*S.H;
 For K:=0 to N-1 do A[K]:=SmoothStep(0.15,0.90,1-S.Cat[cBg][K]/255.0);
End;

{ retire la couleur de l'ancien fond sur les bords : la couleur de la personne y
  est propagee depuis l'interieur }
Procedure Decontam(Var S:TScene;A:PSingle);
Var
 N:int64;K:LongInt;
 C:LongInt;
 Fg,Kn:PSingle;
 Ap:Single;
Begin
 N:=Int64(S.W)*S.H;
 Fg:=AllocF(N*3);Kn:=AllocF(N);
 Move(S.Pix^,Fg^,N*12);
 For K:=0 to N-1 do If A[K]>=0.92 Then Kn[K]:=1;
 PushPullFill(Fg,Kn,S.W,S.H);
 For K:=0 to N-1 do If(A[K]>0.003)and(A[K]<0.92)Then Begin
  Ap:=SmoothStep(0.55,0.95,A[K]);
  For C:=0 to 2 do S.Pix[K*3+C]:=Fg[K*3+C]*(1-Ap)+S.Pix[K*3+C]*Ap;
 End;
 FreeMem(Fg);FreeMem(Kn);
End;

{ ciel etoile : voie lactee en diagonale, etoiles de tailles et de teintes
  variees }
Procedure SkyStars(Bg:PSingle;W,H:LongInt);
Var
 X,Y,Cs,Cx,Cy:LongInt;
 K:Int64;
 T,Dist,Haze,V,Px,Py,D2,B,Rr,Tint,Th:Single;
 R,G,Bl:Single;
Begin
 Cs:=IMax(3,IMax(W,H)div 170);
 For Y:=0 to H-1 do
  For X:=0 to W-1 do Begin
   K:=Int64(Y)*W+X;
   T:=Y/H;
   R:=3+22*T*T;G:=6+22*T*T;Bl:=22+46*T;
   Dist:=(X/W+Y/H-1.0);
   Haze:=Exp(-Sqr(Dist/0.17))*(0.30+0.70*FBm(X*8.0/IMax(W,H),Y*8.0/IMax(W,H)));
   R:=R+Haze*70;G:=G+Haze*78;Bl:=Bl+Haze*128;
   Haze:=Exp(-Sqr((Dist-0.05)/0.05))*FBm(X*22.0/IMax(W,H)+9,Y*22.0/IMax(W,H));
   R:=R-Haze*14;G:=G-Haze*16;Bl:=Bl-Haze*20;
   { etoile de la cellule }
   Cx:=X div Cs;Cy:=Y div Cs;
   Th:=0.80-0.10*Exp(-Sqr(Dist/0.2));
   If Hash2(Cx,Cy)>Th Then Begin
    Px:=(Cx+0.2+0.6*Hash2(Cx+7,Cy+3))*Cs;
    Py:=(Cy+0.2+0.6*Hash2(Cx+13,Cy+9))*Cs;
    B:=Hash2(Cx+3,Cy+29);B:=B*B*B;
    Rr:=0.45+0.25*Cs*0.18*(1+2.2*B);
    If Hash2(Cx+5,Cy+41)>0.97 Then Begin Rr:=Rr*2.0;B:=0.6+0.4*B;End;
    D2:=Sqr(X+0.5-Px)+Sqr(Y+0.5-Py);
    V:=(0.25+0.75*B)*Exp(-D2/(2*Rr*Rr))*1.5;
    Tint:=Hash2(Cx+17,Cy+23);
    R:=R+V*(205+50*Tint);G:=G+V*(215+20*Tint);Bl:=Bl+V*(255-45*Tint);
   End;
   Bg[K*3]:=R;Bg[K*3+1]:=G;Bg[K*3+2]:=Bl;
  End;
End;

{ ciel ensoleille : degrade bleu, soleil et halo, nuages }
Procedure SkyClear(Bg:PSingle;W,H:LongInt);
Var
 X,Y:LongInt;
 K:Int64;
 T,D,Rs,Sx,Sy,Gl,Hz:Single;
Begin
 Rs:=0.045*IMax(W,H);
 Sx:=0.78*W;Sy:=0.17*H;
 VGradient(Bg,W,H,0,H-1,44,112,214,168,212,248);
 Clouds(Bg,W,H,0,H-1,0.9/FMax(40,0.16*W),0.95);
 For Y:=0 to H-1 do
  For X:=0 to W-1 do Begin
   D:=Sqrt(Sqr(X+0.5-Sx)+Sqr(Y+0.5-Sy));
   Gl:=0.55*Exp(-Sqr(D/(Rs*5.5)))+0.35*Exp(-Sqr(D/(Rs*1.9)));
   PutBg(Bg,W,H,X,Y,Gl,255,248,214);
   PutBg(Bg,W,H,X,Y,CoverD(D-Rs),255,252,236);
  End;
End;

{ coucher de soleil : degrade violet - orange, soleil bas, nuages colores }
Procedure SkySunset(Bg:PSingle;W,H:LongInt);
Var
 X,Y:LongInt;
 K:Int64;
 T,D,Rs,Sx,Sy,Gl,Cl:Single;
 R,G,B:Single;
Begin
 Rs:=0.06*IMax(W,H);
 Sx:=0.5*W;Sy:=0.78*H;
 For Y:=0 to H-1 do Begin
  T:=Y/H;
  If T<0.45 Then Begin
   R:=28+(120-28)*T/0.45;G:=36+(62-36)*T/0.45;B:=92+(120-92)*T/0.45;
  End
  Else If T<0.75 Then Begin
   R:=120+(238-120)*(T-0.45)/0.30;G:=62+(112-62)*(T-0.45)/0.30;B:=120+(84-120)
     *(T-0.45)/0.30;
  End
  Else Begin
   R:=238+(255-238)*(T-0.75)/0.25;G:=112+(196-112)*(T-0.75)/0.25;B:=84+(112-84)
     *(T-0.75)/0.25;
  End;
  For X:=0 to W-1 do Begin
   K:=Int64(Y)*W+X;
   Bg[K*3]:=R;Bg[K*3+1]:=G;Bg[K*3+2]:=B;
  End;
 End;
 For Y:=0 to H-1 do
  For X:=0 to W-1 do Begin
   Cl:=SmoothStep(0.55,0.80,FBm(X*5.0/IMax(W,H),Y*11.0/IMax(W,H)+3))
     *0.55*(1-SmoothStep(0.55,0.9,Y/H));
   PutBg(Bg,W,H,X,Y,Cl,250,150,130);
   D:=Sqrt(Sqr(X+0.5-Sx)+Sqr(Y+0.5-Sy));
   Gl:=0.60*Exp(-Sqr(D/(Rs*4.5)))+0.40*Exp(-Sqr(D/(Rs*1.6)));
   PutBg(Bg,W,H,X,Y,Gl,255,214,140);
   PutBg(Bg,W,H,X,Y,CoverD(D-Rs),255,240,200);
  End;
End;

Function ApplyBackground(Var S:TScene;Const E:TEdit;Var Msg:AnsiString):Boolean;
Var
 N:int64;K:LongInt;
 A,Bg,Kn:PSingle;
 C,Cnt:LongInt;
 R,G,B:Single;
 Rgb:LongWord;
 X0,Y0,X1,Y1:LongInt;
 Hor:Single;
Begin
 ApplyBackground:=False;
 Msg:='';
 ColorInit;
 N:=Int64(S.W)*S.H;
 A:=AllocF(N);
 MatteAlpha(S,A);
 Cnt:=0;
 For K:=0 to N-1 do If A[K]>0.5 Then Inc(Cnt);
 If Cnt<N div 100 Then Begin FreeMem(A);Msg:=
   'aucune personne d'#130'tect'#130'e : impossible de s'#130'parer l''arri'+
   #138're-plan';Exit;End;
 Decontam(S,A);
 If E.BgOp=boTransparent Then Begin
  If OutAlpha<>Nil Then FreeMem(OutAlpha);
  OutAlpha:=PByte(AllocBytes(N));OutAlphaN:=N;
  For K:=0 to N-1 do OutAlpha[K]:=Trunc(A[K]*255+0.5);
  FreeMem(A);
  Info('  arri'#138're-plan transparent (fichier PNG avec canal alpha)');
  ApplyBackground:=True;
  Exit;
 End;
 Bg:=AllocF(N*3);
 Case E.BgOp of
  boSolid:Begin
   Rgb:=E.DstRGB;
   R:=(Rgb shr 16)and $FF;G:=(Rgb shr 8)and $FF;B:=Rgb and $FF;
   { noir et blanc du lexique : noir et blanc purs }
   If(R<=34)and(G<=34)and(B<=34)Then Begin R:=0;G:=0;B:=0;End;
   If(R>=240)and(G>=240)and(B>=240)Then Begin R:=255;G:=255;B:=255;End;
   For K:=0 to N-1 do Begin Bg[K*3]:=R;Bg[K*3+1]:=G;Bg[K*3+2]:=B;End;
   Info('  arri'#138're-plan uni '+E.DstName);
  End;
  boStars:Begin SkyStars(Bg,S.W,S.H);
    Info('  arri'#138're-plan : ciel '#130'toil'#130);End;
  boSunny:Begin SkyClear(Bg,S.W,S.H);
    Info('  arri'#138're-plan : ciel ensoleill'#130);End;
  boSunset:Begin
   SkySunset(Bg,S.W,S.H);
   For K:=0 to N-1 do If A[K]>0 Then Begin S.Pix[K*3]:=S.Pix[K*3]*1.04;
     S.Pix[K*3+2]:=S.Pix[K*3+2]*0.92;End;
   Info('  arri'#138're-plan : coucher de soleil');
  End;
  boTropical,boAmazon,boQuebec,boCanada,boConifer,boForest:Begin
   If PersonBounds(S,X0,Y0,X1,Y1)and(Y1<0.95*S.H)Then Hor:=Clamp(Y1+
     1-0.07*(Y1-Y0+1),0.5*S.H,0.8*S.H)
   Else Hor:=0.62*S.H;
   SkyForest(Bg,S.W,S.H,E.BgOp,Hor);
   For K:=0 to N-1 do If A[K]>0 Then Begin S.Pix[K*3]:=S.Pix[K*3]*1.02;
     S.Pix[K*3+2]:=S.Pix[K*3+2]*0.96;End;
   Case E.BgOp of
    boTropical:Info('  arri'#138're-plan : for'#136't tropicale');
    boAmazon:Info('  arri'#138're-plan : for'#136't amazonienne');
    boCanada:Info('  arri'#138're-plan : for'#136't canadienne');
    boConifer:Info('  arri'#138're-plan : for'#136't de conif'#138'res');
    Else
      Info('  arri'#138're-plan : for'#136't qu'#130'b'#130'coise (automne)');
   End;
  End;
  boBlur:Begin
   { le fond est reconstitue sous la personne, puis floute }
   Move(S.Pix^,Bg^,N*12);
   Kn:=AllocF(N);
   For K:=0 to N-1 do If A[K]<0.04 Then Kn[K]:=1;
   PushPullFill(Bg,Kn,S.W,S.H);
   FreeMem(Kn);
   BlurRgb(Bg,S.W,S.H,FMax(2.0,0.016*IMax(S.W,S.H)));
   Info('  arri'#138're-plan flou (effet portrait)');
  End;
  Else Begin FreeMem(A);FreeMem(Bg);
    Msg:='arri'#138're-plan non pris en charge';Exit;End;
 End;
 If E.BgOp=boSunny Then
  For K:=0 to N-1 do If A[K]>0 Then Begin S.Pix[K*3]:=S.Pix[K*3]*1.02;
    S.Pix[K*3+2]:=S.Pix[K*3+2]*0.97;End;
 For K:=0 to N-1 do
  For C:=0 to 2 do S.Pix[K*3+C]:=Bg[K*3+C]*(1-A[K])+S.Pix[K*3+C]*A[K];
 FreeMem(A);FreeMem(Bg);
 ApplyBackground:=True;
End;

Function ApplyImageOp(Var S:TScene;Const E:TEdit;Var Msg:AnsiString):Boolean;
Begin
 Msg:='';
 Case E.ImgOp of
  ioSmooth:ApplyImageOp:=ImageSmooth(S,Msg);
  ioBlur:ApplyImageOp:=ImageBlur(S,Msg);
  ioSharp:ApplyImageOp:=ImageSharpen(S,Msg);
  Else Begin Msg:='op'#130'ration sur l''image non reconnue';
    ApplyImageOp:=False;End;
 End;
End;

{ ------------------------------------------------------------------ }
{ Couche systeme : console, repertoires, telechargement (Windows)      }
{ ------------------------------------------------------------------ }

{$IFDEF WINDOWS}
Function GetConsoleOutputCP:LongWord;stdcall;external 'kernel32.dll' name
  'GetConsoleOutputCP';
Function GetConsoleCP:LongWord;stdcall;external 'kernel32.dll' name
  'GetConsoleCP';
Function SetConsoleOutputCP(CP:LongWord):LongInt;stdcall;external
  'kernel32.dll' name 'SetConsoleOutputCP';
Function SetConsoleCP(CP:LongWord):LongInt;stdcall;external 'kernel32.dll' name
  'SetConsoleCP';
Function MultiByteToWideChar(CP,
  Flags:LongWord;S:PChar;N:LongInt;W:PWideChar;WN:LongInt):LongInt;
 stdcall;external 'kernel32.dll' name 'MultiByteToWideChar';
Function WideCharToMultiByte(CP,
  Flags:LongWord;W:PWideChar;WN:LongInt;S:PChar;N:LongInt;Def:PChar;
    Used:Pointer):LongInt;
 stdcall;external 'kernel32.dll' name 'WideCharToMultiByte';
Procedure WinSleep(Ms:LongWord);stdcall;external 'kernel32.dll' name 'Sleep';

Function InternetOpenA(Agent:PChar;AccessType:LongWord;Proxy,
  Bypass:PChar;Flags:LongWord):Pointer;
 stdcall;external 'wininet.dll' name 'InternetOpenA';
Function InternetOpenUrlA(H:Pointer;Url,
  Headers:PChar;HeadersLen:LongWord;Flags:LongWord;Ctx:PtrUInt):Pointer;
 stdcall;external 'wininet.dll' name 'InternetOpenUrlA';
Function InternetReadFile(H:Pointer;Buf:Pointer;ToRead:LongWord;Var
  Got:LongWord):LongInt;
 stdcall;external 'wininet.dll' name 'InternetReadFile';
Function InternetCloseHandle(H:Pointer):LongInt;stdcall;external 'wininet.dll'
  name 'InternetCloseHandle';
Function HttpQueryInfoA(H:Pointer;InfoLevel:LongWord;Buf:Pointer;Var
  BufLen:LongWord;Index:Pointer):LongInt;
 stdcall;external 'wininet.dll' name 'HttpQueryInfoA';
Function
  InternetSetOptionA(H:Pointer;Opt:LongWord;Buf:Pointer;BufLen:LongWord)
    :LongInt;
 stdcall;external 'wininet.dll' name 'InternetSetOptionA';

Var
 SavedOutCP,SavedInCP:LongWord;
 OldExitProc:Pointer;

{ remet la page de codes d'origine de la console a la fin du programme }
Procedure RestoreConsole;
Begin
 ExitProc:=OldExitProc;
 SetConsoleOutputCP(SavedOutCP);
 SetConsoleCP(SavedInCP);
End;

Function IsValidUtf8(Const S:AnsiString):Boolean;
Var
 I,N,C,Need,K:LongInt;
Begin
 IsValidUtf8:=False;
 I:=1;N:=Length(S);
 While I<=N do Begin
  C:=Ord(S[I]);
  Need:=0;
  If C>=$80 Then Begin
   If(C>=$C2)and(C<=$DF)Then Need:=1
    Else If(C>=$E0)and(C<=$EF)Then Need:=2
    Else If(C>=$F0)and(C<=$F4)Then Need:=3
    Else Exit;
   If I+Need>N Then Exit;
   For K:=1 to Need do If(Ord(S[I+K])and $C0)<>$80 Then Exit;
  End;
  Inc(I,Need+1);
 End;
 IsValidUtf8:=True;
End;

{ argument de la ligne de commande en UTF-8 (Windows le fournit en page ANSI) }
Function ArgStr(I:LongInt):AnsiString;
Var
 S:AnsiString;
 W:Array of Word;
 N,M:LongInt;
Begin
 S:=ParamStr(I);
 ArgStr:=S;
 If IsValidUtf8(S)Then Exit;
 SetLength(W,Length(S)+1);
 N:=MultiByteToWideChar(0,0,PChar(S),Length(S),PWideChar(@W[0]),Length(S)+1);
 If N<=0 Then Exit;
 M:=WideCharToMultiByte(65001,0,PWideChar(@W[0]),N,Nil,0,Nil,Nil);
 If M<=0 Then Exit;
 SetLength(S,M);
 WideCharToMultiByte(65001,0,PWideChar(@W[0]),N,PChar(S),M,Nil,Nil);
 ArgStr:=S;
End;

Procedure InitConsole;
Begin
 SavedOutCP:=GetConsoleOutputCP;
 SavedInCP:=GetConsoleCP;
 SetConsoleOutputCP(65001);
 SetConsoleCP(65001);
 OldExitProc:=ExitProc;
 ExitProc:=@RestoreConsole;
 InstallUtf8Output;
End;
{$ELSE}
Function ArgStr(I:LongInt):AnsiString;
Begin
 ArgStr:=ParamStr(I);
End;

Procedure InitConsole;
Begin
 InstallUtf8Output;
End;
{$ENDIF}

Function HomeDir:AnsiString;
Begin
 HomeDir:=GetEnv('HOME');
 If HomeDir='' Then HomeDir:=GetEnv('USERPROFILE');
End;

{ repertoire ou sont ranges les modeles telecharges }
Function CacheDir:AnsiString;
Var
 D:AnsiString;
Begin
 D:=GetEnv('VTON_CACHE');
 If D='' Then Begin
  {$IFDEF WINDOWS}
  D:=GetEnv('LOCALAPPDATA');
  If D='' Then D:='.';
  D:=D+'\vton';
  {$ELSE}
  D:=GetEnv('XDG_CACHE_HOME');
  If D='' Then Begin
   D:=HomeDir;
   If D='' Then D:='.';
   D:=D+'/.cache';
  End;
  D:=D+'/vton';
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

Function HttpDownload(Const Url,Dest:AnsiString;Var Err:AnsiString):Boolean;
{$IFDEF WINDOWS}
Const
 MaxTries=3;
Var
 Sess,H:Pointer;
 Flags,Tmo,L,Buf:LongWord;
 Status,Code,Try_,Pc,LastPc:LongInt;
 Cl,Done:Int64;
 SBuf:Array[0..63]of AnsiChar;
 Got:LongWord;
 Chunk:Array[0..65535]of Byte;
 F:File;
 Tmp:AnsiString;
 Fin:Boolean;
Begin
 HttpDownload:=False;
 Err:='';
 MakeDirs(PathDir(Dest));
 Tmp:=Dest+'.part';
 Fin:=False;
 Try_:=0;
 While(not Fin)and(Try_<MaxTries)do Begin
  Inc(Try_);
  If Try_>1 Then Begin
   Write(StdErr,'nouvelle tentative ',Try_,'/',MaxTries,' (',Err,')',#10);
   WinSleep(3000);
  End;
  Err:='';
  Sess:=InternetOpenA('vton',0,Nil,Nil,0);
  If Sess=Nil Then Begin Err:='InternetOpen a '#130'chou'#130;Continue;End;
  Tmo:=30000;
  InternetSetOptionA(Sess,2,@Tmo,4);
  InternetSetOptionA(Sess,6,@Tmo,4);
  Flags:=$80000000 or $04000000;
  If Copy(LoStr(Url),1,8)='https://' Then Flags:=Flags or $00800000;
  H:=InternetOpenUrlA(Sess,PChar(Url),PChar('Accept: */*'#13#10),11,Flags,0);
  If H=Nil Then Begin InternetCloseHandle(Sess);
    Err:='connexion impossible '#133' '+Url;Continue;End;
  Status:=0;L:=4;Buf:=0;
  If HttpQueryInfoA(H,19 or $20000000,@Buf,L,Nil)<>0 Then Status:=Buf;
  Cl:=-1;
  FillChar(SBuf,SizeOf(SBuf),0);
  L:=SizeOf(SBuf)-1;
  If HttpQueryInfoA(H,5,@SBuf[0],L,Nil)<>0 Then Val(AnsiString(PChar(@SBuf[0]))
    ,Cl,Code);
  If(Status<200)or(Status>=300)Then Begin
   Err:='le serveur a r'#130'pondu HTTP '+IStr(Status);
   InternetCloseHandle(H);InternetCloseHandle(Sess);
   If(Status>=400)and(Status<500)Then Break;
   Continue;
  End;
  Assign(F,Tmp);
  Rewrite(F,1);
  If IOResult<>0 Then Begin Err:='impossible de cr'#130'er '+
    Tmp;InternetCloseHandle(H);InternetCloseHandle(Sess);Break;End;
  Done:=0;LastPc:=-1;
  Repeat
   Got:=0;
   If InternetReadFile(H,@Chunk[0],SizeOf(Chunk),Got)=0 Then Begin
     Err:='erreur de lecture r'#130'seau';Break;End;
   If Got>0 Then Begin
    BlockWrite(F,Chunk[0],Got);
    Inc(Done,Got);
    If Cl>0 Then Begin
     Pc:=(Done*100)div Cl;
     If Pc<>LastPc Then Begin
      LastPc:=Pc;
      Write(StdErr,#13'T'#130'l'#130'chargement de ',PathLastPart(Dest),' : ',
        Pc,'% (',HumanBytes(Done),')');
      Flush(StdErr);
     End;
    End;
   End;
  Until Got=0;
  Close(F);
  If IOResult<>0 Then;
  InternetCloseHandle(H);InternetCloseHandle(Sess);
  Write(StdErr,#10);
  If Err='' Then Begin
   If(Cl>0)and(Done<>Cl)Then Err:='t'#130'l'#130'chargement incomplet' Else
     Fin:=True;
  End;
 End;
 If not Fin Then Begin
  If Err='' Then Err:=#130'chec du t'#130'l'#130'chargement';
  Exit;
 End;
 If FileExistsP(Dest)Then Begin Assign(F,Dest);Erase(F);If IOResult<>0 Then;End;
 Assign(F,Tmp);
 Rename(F,Dest);
 If IOResult<>0 Then Begin
   Err:='impossible de renommer le fichier t'#130'l'#130'charg'#130;Exit;End;
 HttpDownload:=True;
End;
{$ELSE}
Begin
 Err:='le t'#130'l'#130'chargement n''est disponible que sous Windows';
 HttpDownload:=False;
End;
{$ENDIF}

{ ------------------------------------------------------------------ }
{ Resolution du modele                                                 }
{ ------------------------------------------------------------------ }

Const
 DefaultModelName='segformer_b2_clothes';
 DefaultModelUrl=
   'https://huggingface.co/mattmdjaga/segformer_b2_clothes/resolve/main/';

Function SafeName(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
 R:AnsiString;
Begin
 R:=S;
 For I:=1 to Length(R)do If R[I]in['/','\',':','*','?','"','<','>','|']Then
   R[I]:='_';
 SafeName:=R;
End;

{ cherche le modele dans les emplacements habituels }
Function FindDefaultModel(Const Name:AnsiString;Var Path,Config:AnsiString)
  :Boolean;
Var
 Dirs:TStrArray;
 I:LongInt;
 D,Exe:AnsiString;
 Procedure Try_(Const P:AnsiString;Const Cfg:AnsiString);
 Begin
  If(not FindDefaultModel)and FileExistsP(P)Then Begin
   Path:=P;Config:='';
   If FileExistsP(Cfg)Then Config:=Cfg;
   FindDefaultModel:=True;
  End;
 End;
Begin
 FindDefaultModel:=False;
 SetLength(Dirs,0);
 AddStr(Dirs,'');
 Exe:=PathDir(ParamStr(0));
 If Exe<>'' Then Begin AddStr(Dirs,Exe);AddStr(Dirs,Exe+'models'+PathSep);End;
 AddStr(Dirs,'models'+PathSep);
 AddStr(Dirs,CacheDir+PathSep);
 For I:=0 to High(Dirs)do Begin
  D:=Dirs[I];
  Try_(D+Name+'.safetensors',D+Name+'.json');
  Try_(D+Name+PathSep+'model.safetensors',D+Name+PathSep+'config.json');
 End;
End;

Function ResolveModel(Const Spec:AnsiString;Var Path,Config,Err:AnsiString)
  :Boolean;
Var
 S,L,Name,Dir,BaseUrl,E2:AnsiString;
 Repo:AnsiString;
Begin
 ResolveModel:=False;
 Err:='';Path:='';Config:='';
 S:=Spec;
 L:=LoStr(S);
 If(S='')or(L='default')or(L='segformer-clothes')or(L='clothes')
   or(L=DefaultModelName)Then Begin
  If FindDefaultModel(DefaultModelName,Path,Config)Then Begin
    ResolveModel:=True;Exit;End;
  Dir:=CacheDir+PathSep+DefaultModelName;
  BaseUrl:=DefaultModelUrl;
  Name:=DefaultModelName;
 End
  Else If StartsWith(L,'hf:')Then Begin
   Repo:=Copy(S,4,Length(S));
   If Pos('/',Repo)=0 Then Begin
     Err:='-model hf: doit '#136'tre de la forme hf:utilisateur/mod'#138'le';
     Exit;End;
   Dir:=CacheDir+PathSep+SafeName(Repo);
   BaseUrl:='https://huggingface.co/'+Repo+'/resolve/main/';
   Name:=Repo;
  End
  Else If StartsWith(L,'http://')or StartsWith(L,'https://')Then Begin
   Path:=CacheDir+PathSep+SafeName(PathLastPart(S));
   If FileExistsP(Path)Then Begin ResolveModel:=True;Exit;End;
   If not NetSupported Then Begin
    Err:='le t'#130'l'#130'chargement n''est disponible que sous Windows ; t'+
      #130'l'#130'chargez '+S+' puis utilisez -model FICHIER';
    Exit;
   End;
   Info('t'#130'l'#130'chargement du mod'#138'le depuis '+S);
   If not HttpDownload(S,Path,E2)Then Begin Err:=E2;Exit;End;
   ResolveModel:=True;
   Exit;
  End
  Else Begin
   If DirExistsP(S)Then Begin
    Path:=S+PathSep+'model.safetensors';
    Config:=S+PathSep+'config.json';
    If not FileExistsP(Path)Then Begin
      Err:='model.safetensors introuvable dans '+S;Exit;End;
    If not FileExistsP(Config)Then Config:='';
    ResolveModel:=True;
    Exit;
   End;
   If not FileExistsP(S)Then Begin Err:='mod'#138'le introuvable : '+S;Exit;End;
   Path:=S;
   Config:=PathNoExt(S)+'.json';
   If not FileExistsP(Config)Then Config:=PathDir(S)+'config.json';
   If not FileExistsP(Config)Then Config:='';
   ResolveModel:=True;
   Exit;
  End;
 { telechargement du modele par defaut ou d'un depot Hugging Face }
 Path:=Dir+PathSep+'model.safetensors';
 Config:=Dir+PathSep+'config.json';
 If FileExistsP(Path)Then Begin
  If not FileExistsP(Config)Then Config:='';
  ResolveModel:=True;
  Exit;
 End;
 If not NetSupported Then Begin
  Err:='mod'#138'le "'+Name+
    '" absent. T'#130'l'#130'chargez-le (110 Mio) puis indiquez-le avec '+
    '-model :'#10+
      '  '+BaseUrl+'model.safetensors'#10+
      '  '+BaseUrl+'config.json  (facultatif : noms des classes)';
  Exit;
 End;
 Info('mod'#138'le "'+Name+'" absent : t'#130'l'#130'chargement vers '+Dir);
 If not HttpDownload(BaseUrl+'model.safetensors',Path,E2)Then Begin Err:=E2;
   Exit;End;
 If not HttpDownload(BaseUrl+'config.json',Config,E2)Then Config:='';
 ResolveModel:=True;
End;

{ ------------------------------------------------------------------ }
{ Ligne de commande                                                    }
{ ------------------------------------------------------------------ }

Procedure PrintHelp;
Begin
 WriteLn('VTON '+VersionStr);
 WriteLn;
 WriteLn('Essayage virtuel de v'#136'tements par intelligence artificielle.');
 WriteLn;
 WriteLn('Syntaxe :');
 WriteLn('  VTON personne.jpg vetement.jpg -o resultat.png -type haut');
 WriteLn('  VTON personne.jpg -prompt "Change le chandail rouge en bleu" -o '+
   'resultat.png');
 WriteLn('  VTON personne.jpg vetement.jpg -prompt "mets-le en vert" -type haut'
   );
 WriteLn;
 WriteLn('Param'#138'tres :');
 WriteLn('  -o FICHIER        Fichier image de sortie (.png, .jpg, .bmp, .ppm)')
   ;
 WriteLn('  -type TYPE        Type de v'#136'tement : haut, bas, jupe, robe, '+
   'tout, chaussures,');
 WriteLn(
   '                    chapeau, lunettes, sac, '#130'charpe, ceinture (ou '+
   'top, bottom, ...)');
 WriteLn(
   '  -model MODELE     Mod'#138'le IA : fichier .safetensors SegFormer, '+
   'dossier, hf:util/mod'#138'le');
 WriteLn(
   '                    ou URL (par d'#130'faut segformer_b2_clothes, voir '+
   'ci-dessous)');
 WriteLn('  -cpu              Ex'#130'cuter les calculs sur le processeur');
 WriteLn('  -gpu              Utiliser l''acc'#130'l'#130'ration graphique '+
   '(Direct3D 11, Windows)');
 WriteLn(
   '  -quality NIVEAU   Qualit'#130' du traitement : 1/rapide, 2/normal, 3/'+
   #130'lev'#130' (d'#130'faut), 4/maximal');
 WriteLn('  -seed N           Valeur de d'#130'part al'#130'atoire (grain, '+
   'motifs) ; identique = r'#130'sultat identique');
 WriteLn('  -verbose          Afficher les d'#130'tails du traitement');
 WriteLn('  -prompt TEXTE     Demande en langage naturel (fran'#135'ais ou '+
   'anglais)');
 WriteLn;
 WriteLn('Autres options :');
 WriteLn(
   '  -threads N        Nombre de fils de calcul (d'#130'faut : tous les '+
   'processeurs)');
 WriteLn(
   '  -device N         P'#130'riph'#130'rique Direct3D 11 '#133' utiliser '+
   '(voir -list-devices)');
 WriteLn('  -list-devices     Lister les p'#130'riph'#130'riques Direct3D 11 '+
   'puis quitter');
 WriteLn('  -parsing FICHIER  Image d''analyse fournie (gris 8 bits, valeur = '+
   'classe) au lieu du mod'#138'le');
 WriteLn(
   '  -save-parsing F   Enregistrer l''analyse du corps en fausses couleurs');
 WriteLn('  -maxsize N        Taille maximale du grand c'#147't'#130' (d'#130+
   'faut 2048)');
 WriteLn('  -nomannequin      Ne pas remplacer la peau d''un mannequin '+
   'photographi'#130' avec le v'#136'tement');
 WriteLn('  -quiet            N''afficher que les erreurs');
 WriteLn('  -h, --help, /?    Cette aide        --version   Num'#130'ro de '+
   'version');
 WriteLn;
 WriteLn('Exemples de demandes :');
 WriteLn(
   '  "Change le chandail rouge en bleu"      "Rends la robe plus fonc'#130+
   'e"');
 WriteLn('  "Mets le pantalon en noir et la veste en vert"');
 WriteLn(
   '  "Make the shirt striped blue and white" "Enl'#138've le chapeau et '+
   'les lunettes"');
 WriteLn(
   '  "Change le chandail rouge en bleu, ajouter un foulard"   "mettre un '+
   'chapeau de paille"');
 WriteLn('  "cheveux longs et blonds"  "cheveux fris'#130's"  "cheveux plus '+
   'courts"  "enl'#138've les cheveux"');
 WriteLn(
   '  "ajoute un collier en or"  "ajoute des diamants"  "ajoute une montre '+
   'apple"  "ajoute un bracelet"');
 WriteLn(
   '  "changer la couleur des yeux pour vert" (rouge, blanc, noir, bleu, '+
   'marron...)  "souriante"');
 WriteLn('  "bras bien aligner de chaque c'#147't'#130' du corps"');
 WriteLn('  "corps d''or"  "corps m'#130'tallique"  "corps robot"  "style '+
   'statue"  "v'#136'tement de cha'#140'ne d''or"');
 WriteLn('  "debout sur un carrousel"');
 WriteLn(
   '  "rend la peau plus lisse" (granuleuse, douce, comme une peau de b'#130+
   'b'#130')  "rajeunis-la de 10 ans"  "vieillis-la de 5 ans"');
 WriteLn(
   '  "teinte ses cheveux en noir" (brun, blond, roux, blanc, rose, bleu, '+
   'vert, poivre et sel)');
 WriteLn(
   '  "rend l''image plus lisse" (floue, nette, plus r'#130'elle)  "rend '+
   'le fond noir" (blanc, bleu...)  "rend le fond transparent" (PNG)');
 WriteLn('  "rend le fond de l''image dans un ciel '#130'toil'#130'" (ciel '+
   'ensoleill'#130', coucher de soleil, fond flou)');
 WriteLn(
   '  VTON personne.jpg tenue.jpg -prompt "Mets-lui cette tenue"  (tenue '+
   'photographi'#130'e sur mannequin : taille d'#130'duite de la t'#136'te)');
 WriteLn(
   '  "change le fond pour une for'#136't tropicale" (amazonienne, qu'#130+
   'b'#130'coise, canadienne, de conif'#138'res)');
 WriteLn('  "bras crois'#130's"  "montre une main peace & love"  "pointe du '+
   'doigt"  "t'#136'te droite"  "aur'#130'ole"');
 WriteLn(
   '  "s'#130'rieuse"  "triste"  "regarde perdu"  "somnambule"  "saute"  '+
   '"flotte"  "assis"  "appuy'#130' sur un meuble"');
 WriteLn('  "couch'#130'"  "couch'#130' dans un lit"  "monte les escaliers"  '+
   '"sur le toit de la niche '#133' chien"');
 WriteLn(
   '  "marche sur un fil de fer"  (poses dessin'#130'es par le programme ; '+
   '"'#133' genoux" et "v'#130'lo" : non pris en charge)');
 WriteLn('  "transforme cette personne en BD" (ou dessin anim'#130', croquis)');
 WriteLn('  "transforme ce personnage de BD en r'#130'el" (approximatif : ce '+
   'n''est pas une photo)');
 WriteLn('  (plusieurs instructions possibles, s'#130'par'#130'es par des '+
   'virgules ou "et" ;');
 WriteLn('   ajouts support'#130's sans photo : foulard, chapeau, bonnet, '+
   'casquette, lunettes, ceinture,');
 WriteLn(
   '   pantalon, jupe, souliers ; si le corps est coup'#130' par le cadre, '+
   'l''image est prolong'#130'e vers le bas :');
 WriteLn('   "rajoute un pantalon"  "rajoute des souliers"  "je veux voir des '+
   'pieds")');
 WriteLn;
 WriteLn('Mod'#138'le : ');
 WriteLn('  '+DefaultModelUrl+'model.safetensors');
 WriteLn(
   '  (Windows : t'#130'l'#130'charg'#130' automatiquement ; sinon placez '+
   'le fichier '#133' c'#147't'#130' de VTON');
 WriteLn('   sous le nom segformer_b2_clothes.safetensors, ou utilisez -model.)'
   );
End;

Var
 OptOut,OptType,OptModel,OptPrompt,OptParsing,OptSaveParsing,OptDump:AnsiString;
 OptCpu,OptGpu,OptHelp,OptList:Boolean;
 OptQuality:LongInt=3;
 OptSeed:Int64=-1;
 OptThreads:LongInt=0;
 OptDevice:LongInt=-1;
 OptMaxSize:LongInt=2048;
 OptSize:LongInt=0;
 Pos_:TStrArray;

Function ParseQuality(Const S:AnsiString;Var Q:LongInt):Boolean;
Var
 L:AnsiString;
 V:Int64;
Begin
 ParseQuality:=True;
 L:=FoldText(S);
 L:=TrimS(L);
 If ParseInt(L,V)and(V>=1)and(V<=4)Then Begin Q:=V;Exit;End;
 If(L='low')or(L='rapide')or(L='fast')or(L='draft')or(L='faible')or(L='bas')Then
   Q:=1
 Else If(L='medium')or(L='moyen')or(L='normal')or(L='standard')Then Q:=2
 Else If(L='high')or(L='eleve')or(L='haute')or(L='haut')or(L='best')Then Q:=3
 Else If(L='ultra')or(L='max')or(L='maximal')or(L='maximum')Then Q:=4
 Else ParseQuality:=False;
End;

{ genre de vetement demande par -type }
Function ParseKind(Const S:AnsiString):LongInt;
Var
 L:AnsiString;
 K:LongInt;
Begin
 LexInit;
 L:=TrimS(FoldText(S));
 ParseKind:=-1;
 If(L='')or(L='auto')Then Begin ParseKind:=gkNone;Exit;End;
 If(L='bas')or(L='bottom')or(L='bottoms')or(L='lower')Then Begin
   ParseKind:=gkBottom;Exit;End;
 If(L='tout')or(L='full')or(L='complet')or(L='ensemble')or(L='outfit')
   or(L='fullbody')or(L='body')Then Begin ParseKind:=gkFull;Exit;End;
 K:=LexFind(L,lkGarment);
 If K>=0 Then Begin
  If Lex[K].V1=gkAll Then ParseKind:=gkFull Else ParseKind:=Lex[K].V1;
 End;
End;

Function IsImageName(Const S:AnsiString):Boolean;
Var
 E:AnsiString;
Begin
 E:=PathExt(S);
 IsImageName:=(E='.jpg')or(E='.jpeg')or(E='.png')or(E='.bmp')or(E='.ppm')
   or(E='.pgm')or(E='.gif')or(E='.webp');
End;

Function ParseCommandLine:Boolean;
Var
 I,N:LongInt;
 A,Key,Val_:AnsiString;
 V:Int64;
 HasEq:Boolean;
 P:LongInt;

 Function NeedVal:Boolean;
 Begin
  NeedVal:=True;
  If HasEq Then Exit;
  If I<N Then Begin Inc(I);Val_:=ArgStr(I);End
  Else Begin
   WriteLn(StdErr,'erreur : l''option -'+Key+' attend une valeur');
   NeedVal:=False;
  End;
 End;

Begin
 ParseCommandLine:=False;
 N:=ParamCount;
 I:=1;
 SetLength(Pos_,0);
 While I<=N do Begin
  A:=ArgStr(I);
  If(A='/?')or(LoStr(A)='/h')or(LoStr(A)='/help')Then OptHelp:=True
  Else If(Length(A)>1)and(A[1]='-')Then Begin
   Key:=A;
   While(Key<>'')and(Key[1]='-')do Delete(Key,1,1);
   HasEq:=False;Val_:='';
   P:=Pos('=',Key);
   If P>0 Then Begin HasEq:=True;Val_:=Copy(Key,P+1,Length(Key));Key:=Copy(Key,
     1,P-1);End;
   Key:=LoStr(Key);
   If(Key='h')or(Key='help')or(Key='?')Then OptHelp:=True
   Else If Key='version' Then Begin WriteLn('VTON ',VersionStr);Halt(0);End
   Else If Key='cpu' Then OptCpu:=True
   Else If Key='gpu' Then OptGpu:=True
   Else If(Key='verbose')or(Key='v')Then Verbose:=True
   Else If(Key='quiet')or(Key='q')Then Quiet:=True
   Else If Key='nomannequin' Then NoMannequin:=True
   Else If Key='list-devices' Then OptList:=True
   Else If Key='o' Then Begin If not NeedVal Then Exit;OptOut:=Val_;End
   Else If Key='type' Then Begin If not NeedVal Then Exit;OptType:=Val_;End
   Else If Key='model' Then Begin If not NeedVal Then Exit;OptModel:=Val_;End
   Else If(Key='prompt')or(Key='p')Then Begin If not NeedVal Then Exit;
     OptPrompt:=Val_;End
   Else If Key='parsing' Then Begin If not NeedVal Then Exit;
     OptParsing:=Val_;End
   Else If Key='save-parsing' Then Begin If not NeedVal Then Exit;
     OptSaveParsing:=Val_;End
   Else If Key='dumplogits' Then Begin If not NeedVal Then Exit;
     OptDump:=Val_;End
   Else If Key='quality' Then Begin
    If not NeedVal Then Exit;
    If not ParseQuality(Val_,OptQuality)Then Begin
     WriteLn(StdErr,'erreur : niveau de qualit'#130' inconnu : ',
       Val_,' (1 '#133' 4, rapide, normal, '#130'lev'#130', maximal)');
     Exit;
    End;
   End
   Else If Key='seed' Then Begin
    If not NeedVal Then Exit;
    If not ParseInt(Val_,V)Then Begin
      WriteLn(StdErr,'erreur : valeur de -seed invalide : ',Val_);Exit;End;
    OptSeed:=V;
   End
   Else If(Key='threads')or(Key='t')Then Begin
    If not NeedVal Then Exit;
    If not ParseInt(Val_,V)or(V<1)Then Begin
      WriteLn(StdErr,'erreur : valeur de -threads invalide : ',Val_);Exit;End;
    OptThreads:=V;
   End
   Else If Key='device' Then Begin
    If not NeedVal Then Exit;
    If not ParseInt(Val_,V)or(V<0)Then Begin
      WriteLn(StdErr,'erreur : valeur de -device invalide : ',Val_);Exit;End;
    OptDevice:=V;
   End
   Else If Key='maxsize' Then Begin
    If not NeedVal Then Exit;
    If not ParseInt(Val_,V)or(V<64)Then Begin
      WriteLn(StdErr,'erreur : valeur de -maxsize invalide : ',Val_);Exit;End;
    OptMaxSize:=V;
   End
   Else If Key='size' Then Begin
    If not NeedVal Then Exit;
    If not ParseInt(Val_,V)or(V<64)Then Begin
      WriteLn(StdErr,'erreur : valeur de -size invalide : ',Val_);Exit;End;
    OptSize:=V;
   End
   Else Begin
    WriteLn(StdErr,'erreur : option inconnue : ',A,' (voir VTON -h)');
    Exit;
   End;
  End
   Else AddStr(Pos_,A);
  Inc(I);
 End;
 ParseCommandLine:=True;
End;

{ ------------------------------------------------------------------ }
{ Programme principal                                                  }
{ ------------------------------------------------------------------ }

Var
 Person,GarmentFile,PromptText:AnsiString;
 Garment:Boolean;
 Scene:TScene;
 Net:TSegModel;
 Img,GImg:TImage;
 Err,ModelPath,ConfigPath,Msg:AnsiString;
 Edits:TEditArray;
 GarmentEdits:Array of LongInt;
 GKind,I,J,JpegQ,NOk,NFail,Side:LongInt;
 T0,T1:Double;
 G:TGarment;
 P:TRecolor;
 Kind:LongInt;
 Ed:^TEdit;
 Tmp:PSingle;
 OutName:AnsiString;
 KindMask:LongWord;
 ToG:Boolean;
 Parsed:Boolean;
 N:LongInt;
 Used:Boolean;
 Dummy:LongWord;
 NeedFeet,NeedPants,NeedSkirt:Boolean;
 Cnt0,NeedL,NeedR,NeedB:LongInt;

Procedure Die(Const S:AnsiString);
Begin
 Fatal(S);
End;

Begin
 InitConsole;
 ReturnNilIfGrowHeapFails:=True;
 StartMs:=NowMsF;
 OptCpu:=False;OptGpu:=False;OptHelp:=False;OptList:=False;
 OptOut:='';OptType:='';OptModel:='';OptPrompt:='';OptParsing:='';
   OptSaveParsing:='';OptDump:='';
 If ParamCount=0 Then Begin PrintHelp;Halt(1);End;
 If not ParseCommandLine Then Halt(1);
 If OptHelp Then Begin PrintHelp;Halt(0);End;
 If OptList Then Begin GpuPrintDevices;Halt(0);End;
 If Length(Pos_)=0 Then
   Die('aucune photo de personne indiqu'#130'e (voir VTON -h)');
 If OptCpu and OptGpu Then Die('-cpu et -gpu sont incompatibles');
 Person:=Pos_[0];
 GarmentFile:='';Garment:=False;
 PromptText:=OptPrompt;
 I:=1;
 If(Length(Pos_)>1)Then Begin
  If FileExistsP(Pos_[1])or(IsImageName(Pos_[1])and(Pos(' ',Pos_[1])=0))
    Then Begin
   GarmentFile:=Pos_[1];Garment:=True;I:=2;
  End;
 End;
 { les mots restants forment la demande en langage naturel }
 If PromptText='' Then Begin
  For J:=I to High(Pos_)do Begin
   If PromptText<>'' Then PromptText:=PromptText+' ';
   PromptText:=PromptText+Pos_[J];
  End;
 End;
 If(not Garment)and(PromptText='')Then
   Die('indiquez une image de v'#136'tement ou une demande avec -prompt');
 GKind:=ParseKind(OptType);
 If GKind<0 Then Die('type de v'#136'tement inconnu : '+OptType+
   ' (haut, bas, jupe, robe, tout, chaussures, chapeau, lunettes, sac, '#130+
   'charpe, ceinture)');
 If OptSeed<0 Then OptSeed:=MakeSeed and $7FFFFFFF;
 RngSeed(LongWord(OptSeed));
 OutName:=OptOut;
 If OutName='' Then OutName:=PathNoExt(Person)+'_vton.png';
 Case OptQuality of
  1:JpegQ:=80;
  2:JpegQ:=88;
  3:JpegQ:=92;
  Else JpegQ:=96;
 End;
 GNThreads:=CpuCount;
 If OptThreads>0 Then GNThreads:=OptThreads;
 If GNThreads>MaxThreads Then GNThreads:=MaxThreads;
 If Verbose Then Begin
  Detail('VTON '+VersionStr);
  Detail('personne : '+Person);
  If Garment Then Detail('v'#136'tement : '+GarmentFile);
  If PromptText<>'' Then Detail('demande : '+PromptText);
  Detail('qualit'#130' '+IStr(OptQuality)+', graine '+IStr(OptSeed)
    +', fils de calcul '+IStr(GNThreads));
 End;
 { demande en langage naturel }
 SetLength(Edits,0);
 If PromptText<>'' Then Begin
  If not Interpret(PromptText,Edits,Err)Then Die(Err);
  For I:=0 to High(Edits)do Detail('interpr'#130'tation : '+
    DescribeEdit(Edits[I]));
 End;
 { photo de la personne }
 If not ImgLoad(Person,Img,Err)Then Die(Err);
 Detail('photo '+IStr(Img.W)+'x'+IStr(Img.H));
 SceneFromImage(Img,OptMaxSize,Scene);
 ImgFree(Img);
 If (Scene.W<64)or(Scene.H<64)Then
   Die('la photo est trop petite (64 pixels minimum)');
 If Verbose Then Detail('image de travail '+IStr(Scene.W)+'x'+IStr(Scene.H));
 { GPU }
 If not OptCpu Then Begin
  Err:='';
  If GpuSetup(OptDevice,Err)Then Info('GPU : '+GpuName+' (Direct3D 11)')
  Else Begin
   If OptGpu Then Warn('GPU indisponible ('+Err+') : calcul sur le processeur');
   If(not OptGpu)and Verbose Then Detail('GPU non utilis'#130' : '+Err);
  End;
 End;
 { analyse de la personne }
 T0:=NowMsF;
 If OptParsing<>'' Then Begin
  If not ParseFromLabels(Scene,OptParsing,Err)Then Die(Err);
  If OptQuality>=2 Then SceneRefine(Scene);
 End
  Else Begin
   If not ResolveModel(OptModel,ModelPath,ConfigPath,Err)Then Die(Err);
   Info('Chargement du mod'#138'le '+PathLastPart(ModelPath)+' ...');
   If not StLoad(ModelPath,Err)Then Die(Err);
   If not SegBuild(Net,ConfigPath)Then Die(SegErr);
   Detail(IStr(StN)+' tenseurs, '+IStr(Net.NumLabels)+
     ' classes, d'#130'codeur '+IStr(Net.Dec));
   Case OptQuality of
    1:Side:=256;
    2:Side:=384;
    3:Side:=512;
    Else Side:=768;
   End;
   If OptSize>0 Then Side:=OptSize;
   DumpPath:=OptDump;
   Info('Analyse de la personne ...');
   ParseWithNet(Scene,Net,Side,OptQuality>=2);
    End;
 Detail('analyse termin'#130'e en '+FStr((NowMsF-T0)/1000.0,1)+' s');
 For I:=0 to NumCat-1 do Begin
  N:=CatArea(Scene,LongWord(1)shl I);
  If(N>0)and Verbose and(I<>cBg)Then Detail('  '+PadRight(CatNames[I],12)+
    FStr(100.0*N/(Int64(Scene.W)*Scene.H),1)+' %');
 End;
 If OptSaveParsing<>'' Then Begin
  ParsingToImage(Scene,Img);
  If not ImgSave(OptSaveParsing,Img,90)Then
    Warn('impossible d''enregistrer '+OptSaveParsing);
  ImgFree(Img);
 End;
 { scene : le corps coupe doit montrer ses pieds pour se tenir sur la plateforme
   }
 For I:=0 to High(Edits)do If(Edits[I].Action=eaScene)
   or((Edits[I].Action=eaPose2)and((Edits[I].Poses and FeetPoses)<>0))Then Begin
  Cnt0:=0;
  For J:=0 to Scene.W-1 do If Scene.Cat[cBg][Int64(Scene.H-1)*Scene.W+
    J]<128 Then Inc(Cnt0);
  If(Cnt0>=Scene.W div 50)and(CatArea(Scene,msShoes)<Int64(Scene.W)*Scene.H
    div 2000)Then Begin
   SetLength(Edits,Length(Edits)+1);
   For J:=High(Edits)downto 1 do Edits[J]:=Edits[J-1];
   ClearEdit(Edits[0]);
   Edits[0].Action:=eaAdd;Edits[0].Target:=msShoes;Edits[0].Kind:=gkShoes;
     Edits[0].Noun:='souliers';
   Info('corps coup'#130' : pantalon et souliers ajout'#130's pour poser la '+
     'personne sur la plateforme');
  End;
  Break;
 End;
 { bas du corps : prolongement de l'image si le corps est coupe par le cadre }
 NeedFeet:=False;NeedPants:=False;NeedSkirt:=False;
 For I:=0 to High(Edits)do Begin
  If(Edits[I].Action=eaRecolor)and Edits[I].Put and((Edits[I].Target and(msPants
    or msSkirt or msShoes))<>0)and
    (CatArea(Scene,Edits[I].Target)<Int64(Scene.W)*Scene.H div 2000)Then
      Edits[I].Action:=eaAdd;
  If Edits[I].Action=eaAdd Then Begin
   If(Edits[I].Target and msShoes)<>0 Then NeedFeet:=True;
   If(Edits[I].Target and msPants)<>0 Then NeedPants:=True;
   If(Edits[I].Target and msSkirt)<>0 Then NeedSkirt:=True;
  End;
 End;
 If NeedFeet or NeedPants or NeedSkirt Then Begin
  { des souliers sans pantalon ni jupe : un pantalon neutre est ajoute }
  If NeedFeet and not NeedPants and not NeedSkirt and
    (CatArea(Scene,msPants or msSkirt or msDress)<Int64(Scene.W)*Scene.H
      div 2000)Then Begin
   SetLength(Edits,Length(Edits)+1);
   For J:=High(Edits)downto 1 do Edits[J]:=Edits[J-1];
   ClearEdit(Edits[0]);
   Edits[0].Action:=eaAdd;Edits[0].Target:=msPants;Edits[0].Kind:=gkBottom;
     Edits[0].Noun:='pantalon';
   NeedPants:=True;
   Info('pantalon neutre ajout'#130' pour accompagner les chaussures');
  End;
  If ExtendBody(Scene,NeedFeet,NeedPants,NeedSkirt,Msg)Then Begin
   If Msg<>'' Then Info(Msg);
  End
   Else Begin
    Warn(Msg);
    For I:=0 to High(Edits)do
     If(Edits[I].Action=eaAdd)and((Edits[I].Target and(msPants or msSkirt
       or msShoes))<>0)Then Edits[I].Action:=eaNone;
   End;
 End;
 NOk:=0;NFail:=0;
 SetLength(GarmentEdits,Length(Edits));
 For I:=0 to High(Edits)do Begin
  GarmentEdits[I]:=0;
  If Garment and(Edits[I].Action=eaTryOn)Then GarmentEdits[I]:=1;
  { -type designe la cible quand la demande ne la precise pas }
  If(not Garment)and(GKind<>gkNone)and(Edits[I].Target=0)and(not
    Edits[I].HasSrc)Then Begin
   KindSets(GKind,KindMask,Dummy,Dummy);
   Edits[I].Target:=KindMask;Edits[I].Kind:=GKind;
  End;
 End;
 { essayage d'un vetement fourni }
 If Garment Then Begin
  Kind:=GKind;
  If Kind=gkNone Then
   For I:=0 to High(Edits)do
    If(Kind=gkNone)and(Edits[I].Kind in[gkTop,gkBottom,gkSkirt,gkDress,
      gkShoes,gkHat,gkGlasses,gkBag,gkScarf,gkBelt,gkFull])Then
      Kind:=Edits[I].Kind
    Else If(Kind=gkNone)and(Edits[I].Kind=gkAll)Then Kind:=gkFull;
  If not ImgLoad(GarmentFile,GImg,Err)Then Die(Err);
  If not GarmentFromImage(GImg,G,Err)Then Die(Err);
  ImgFree(GImg);
  If Kind=gkNone Then Begin
   If G.H>1.25*G.W Then Begin
    Kind:=gkFull;
    Info('type de v'#136'tement d'#130'duit de la forme : tenue compl'#138'te '+
      '(utilisez -type pour pr'#130'ciser)');
   End
    Else Begin
     Kind:=gkTop;
     Info('type de v'#136'tement non pr'#130'cis'#130' : "haut" suppos'#130' '+
       '(utilisez -type)');
    End;
  End;
  Detail('v'#136'tement '+IStr(G.W)+'x'+IStr(G.H)+' : '+G.Note);
  { retouches de la demande qui concernent le vetement lui-meme }
  KindSets(Kind,KindMask,Dummy,Dummy);
  For I:=0 to High(Edits)do Begin
   Ed:=@Edits[I];
   ToG:=(Ed^.Action=eaRecolor)and((Ed^.Target=0)or((Ed^.Target and KindMask)
     <>0)or(Ed^.Kind=Kind));
   If ToG Then Begin
    GarmentEdits[I]:=1;
    BuildRecolor(Ed^,P,0,0,G.W,G.H,Kind in[gkBottom,gkSkirt]);
    Tmp:=AllocF(Int64(G.W)*G.H);
    For N:=0 to Int64(G.W)*G.H-1 do Tmp[N]:=SmoothStep(0.25,0.75,G.Mask[N]);
    If RecolorRegion(G.Rgb,G.W,G.H,Tmp,P)Then
      Info('  v'#136'tement recolor'#130+' ('+Ed^.DstName+')')
    Else Warn('v'#136'tement trop petit pour '#136'tre recolor'#130);
    FreeMem(Tmp);
   End;
  End;
  { mannequin : l'image est agrandie (cotes et bas) pour montrer toute la tenue,
    jusqu'aux pieds }
  MannequinNeed(Scene,G,Kind,NeedL,NeedR,NeedB);
  If NeedL>3*Scene.W Then NeedL:=3*Scene.W;
  If NeedR>3*Scene.W Then NeedR:=3*Scene.W;
  If NeedB>3*Scene.H Then NeedB:=3*Scene.H;
  If(NeedL>0)or(NeedR>0)or(NeedB>0)Then Begin
   GrowEdges(Scene,NeedL,0,NeedR,NeedB);
   Info('image agrandie ('+IStr(NeedL)+' px '#133' gauche, '+IStr(NeedR)
     +' '#133' droite, '+IStr(NeedB)+' en bas) pour voir la tenue en entier');
  End;
  Info('Pose du v'#136'tement ('+GarmentKindName(Kind)+') ...');
  If TryOnGarment(Scene,G,Kind,OptQuality,Msg)Then Begin
   Info('  '+Msg);
   Inc(NOk);
  End
   Else Begin
    Warn(Msg);
    Inc(NFail);
   End;
  GarmentFree(G);
 End;
 { poses et situations (expression, bras, decor) }
 For I:=0 to High(Edits)do
  If Edits[I].Action=eaPose2 Then Begin
   Info('Pose : '+DescribeEdit(Edits[I]));
   ApplyPoses(Scene,Edits[I].Poses,0,NOk,NFail);
  End;
 { retouches sur la scene }
 For I:=0 to High(Edits)do Begin
  If GarmentEdits[I]<>0 Then Continue;
  If Edits[I].Action=eaNone Then Begin Inc(NFail);Continue;End;
  If Edits[I].Action=eaTryOn Then Begin
   Warn('"essayer" demande une image de v'#136'tement (deuxi'#138'me argument)')
     ;
   Inc(NFail);
   Continue;
  End;
  { ? mettre un chapeau ? alors qu'il n'y en a pas : on l'ajoute }
  If(Edits[I].Action=eaRecolor)and Edits[I].Put and((Edits[I].Target
    and(msHat or msScarf or msGlasses or msBelt))<>0)and
    (CatArea(Scene,Edits[I].Target)<Int64(Scene.W)*Scene.H div 2000)Then
      Edits[I].Action:=eaAdd;
  If(Edits[I].Action=eaPose2)or(Edits[I].Action=eaImage)
    or(Edits[I].Action=eaBg)Then Continue;
  Info('Retouche : '+DescribeEdit(Edits[I]));
  If(Edits[I].Action=eaRemove)and(Edits[I].Jewel<>0)Then Begin
   Warn('le retrait de bijoux n''est pas pris en charge');Inc(NFail);Continue;
  End;
  If(Edits[I].Action=eaAdd)and(Edits[I].Jewel<>0)Then Begin
   Info('Ajout de bijoux ...');
   If AddJewelry(Scene,Edits[I],Msg)Then Inc(NOk)Else Begin Warn(Msg);
     Inc(NFail);End;
   Continue;
  End;
  If Edits[I].Action=eaStyle Then Continue;
  If Edits[I].Action=eaScene Then Continue;
  If Edits[I].Action=eaMaterial Then Begin
   Info('Mati'#138're : '+DescribeEdit(Edits[I]));
   If ApplyMaterial(Scene,Edits[I],Msg)Then Inc(NOk)Else Begin Warn(Msg);
     Inc(NFail);End;
   Continue;
  End;
  If Edits[I].Action=eaSkin Then Begin
   Info('Peau : '+DescribeEdit(Edits[I]));
   If ApplySkin(Scene,Edits[I],Msg)Then Inc(NOk)Else Begin Warn(Msg);Inc(NFail)
     ;End;
   Continue;
  End;
  { sourire demande (seul ou avec d'autres retouches dans la meme clause) }
  If Edits[I].Expr<>0 Then Begin
   If ApplySmile(Scene,Msg)Then Inc(NOk)Else Begin Warn(Msg);Inc(NFail);End;
   If Edits[I].Action=eaFace Then Continue;
  End;
  If Edits[I].Action=eaPose Then Begin
   If ArmsDown(Scene,Msg)Then Inc(NOk)Else Begin Warn(Msg);Inc(NFail);End;
   Continue;
  End;
  If Edits[I].Action=eaHair Then Begin
   If ApplyHair(Scene,Edits[I].HairStyle,Edits[I],Msg)Then Begin
     Info('  coiffure modifi'#130'e');Inc(NOk);End
   Else Begin Warn(Msg);Inc(NFail);End;
  End
  Else If Edits[I].Action=eaAdd Then Begin
   If AddAccessory(Scene,Edits[I],OptQuality,Msg)Then Begin Info('  '+Msg);
     Inc(NOk);End
   Else Begin Warn(Msg);Inc(NFail);End;
  End
  Else If ApplyEdit(Scene,Edits[I],Msg)Then Inc(NOk)
  Else Begin Warn(Msg);Inc(NFail);End;
 End;
 { situations : decors dessines autour de la personne }
 For I:=0 to High(Edits)do
  If Edits[I].Action=eaPose2 Then ApplyPoses(Scene,Edits[I].Poses,1,NOk,NFail);
 { scene : decor genere autour de la personne }
 For I:=0 to High(Edits)do
  If Edits[I].Action=eaScene Then Begin
   Info('Sc'#138'ne : carrousel');
   If ApplyCarousel(Scene,Msg)Then Inc(NOk)Else Begin Warn(Msg);Inc(NFail);End;
  End;
 { image entiere et arriere-plan, dans l'ordre de la demande }
 For I:=0 to High(Edits)do Begin
  If Edits[I].Action=eaBg Then Begin
   Info('Arri'#138're-plan : '+DescribeEdit(Edits[I]));
   If ApplyBackground(Scene,Edits[I],Msg)Then Inc(NOk)Else Begin Warn(Msg);
     Inc(NFail);End;
  End
  Else If Edits[I].Action=eaImage Then Begin
   Info('Image : '+DescribeEdit(Edits[I]));
   If ApplyImageOp(Scene,Edits[I],Msg)Then Inc(NOk)Else Begin Warn(Msg);
     Inc(NFail);End;
  End;
 End;
 { le style de l'image s'applique en dernier, sur le resultat des autres
   retouches }
 For I:=0 to High(Edits)do
  If Edits[I].Action=eaStyle Then Begin
   Info('Style : '+DescribeEdit(Edits[I]));
   If ApplyStyle(Scene,Edits[I].Style,Msg)Then Inc(NOk)Else Begin Warn(Msg);
     Inc(NFail);End;
  End;
 If NOk=0 Then Begin
  Write(StdErr,
    'erreur : aucune retouche n''a pu '#136'tre appliqu'#130'e, aucun '+
    'fichier '#130'crit',#10);
  Halt(2);
 End;
 SceneToImage(Scene,Img);
 If OutAlpha<>Nil Then Begin
  If OutAlphaN=Int64(Scene.W)*Scene.H Then Begin
   Img.Alpha:=PByte(AllocBytes(OutAlphaN));
   Move(OutAlpha^,Img.Alpha^,OutAlphaN);
   If PathExt(OutName)<>'.png' Then Begin
    Warn('la transparence demande un fichier PNG : '+OutName+
      ' devient '+PathNoExt(OutName)+'.png');
    OutName:=PathNoExt(OutName)+'.png';
   End;
  End;
  FreeMem(OutAlpha);OutAlpha:=Nil;
 End;
 If not ImgSave(OutName,Img,JpegQ)Then Die('impossible d''enregistrer '+
   OutName);
 ImgFree(Img);
 Info('R'#130'sultat : '+OutName+' ('+IStr(Scene.W)+'x'+IStr(Scene.H)+', '+
   FStr((NowMsF-StartMs)/1000.0,1)+' s)');
 If Verbose and(GpuCalls>0)Then Detail('GPU : '+IStr(GpuCalls)
   +' produits matriciels, '+HumanBytes(GpuBytes)+' transf'#130'r'#130's');
 If NFail>0 Then Halt(3);
End.
