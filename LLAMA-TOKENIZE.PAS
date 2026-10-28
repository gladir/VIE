{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/vie)
  @abstract(Target: Free Pascal 3.x)

  LLAMA-TOKENIZE : clone de la commande llama-tokenize de llama.cpp.

  Tokenise un texte avec le vocabulaire (tokenizer.ggml.*) d'un modele GGUF
  et affiche les jetons obtenus (identifiant et texte), leurs seuls
  identifiants ou leur nombre. Le modele n'est pas charge en memoire : seules
  les metadonnees du fichier GGUF sont lues, un fichier ne contenant que le
  vocabulaire convient donc aussi.

  Syntaxe :
   llama-tokenize -m modele.gguf -p "Quelle est la capitale du Canada ?" --show-count
   llama-tokenize -m modele.gguf -f question.txt --ids

  Contraintes respectees :
   - un seul fichier source, aucun fichier d'inclusion;
   - la seule unite utilisee est DOS (le reste vient de l'unite System);
   - tokeniseurs pris en charge : SentencePiece (tokenizer.ggml.model =
     llama) et BPE (gpt2, avec les pre-tokeniseurs llama3, qwen2, gpt-2,
     smollm, falcon, deepseek, bloom, ...), comme LLAMA-CLI.PAS.

  Un programme Turbo Pascal 16 bits ne peut pas lire un fichier GGUF de
  plusieurs centaines de Mo : il faut un compilateur 32 ou 64 bits
  (Free Pascal) pour compiler ce programme.

  Compilation : fpc -O3 LLAMA-TOKENIZE.PAS
}

Program LLAMA_TOKENIZE;

{$IFDEF FPC}
 {$MODE OBJFPC}
 {$H+}
 {$INLINE ON}
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
 VersionStr   = '1.0 (clone Pascal de llama.cpp llama-tokenize)';

 { Types GGUF }
 GT_UINT8=0; GT_INT8=1; GT_UINT16=2; GT_INT16=3; GT_UINT32=4; GT_INT32=5;
 GT_FLOAT32=6; GT_BOOL=7; GT_STRING=8; GT_ARRAY=9; GT_UINT64=10;
 GT_INT64=11; GT_FLOAT64=12;

 { Attributs de jetons }
 TA_UNDEFINED=0; TA_UNKNOWN=1; TA_UNUSED=2; TA_NORMAL=4; TA_CONTROL=8;
 TA_USER_DEFINED=16; TA_BYTE=32;

Type
 TStrArray = Array of AnsiString;
 TIntArray = Array of LongInt;
 TSingleArray = Array of Single;
 TBoolArray = Array of Boolean;

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

Function LoStr(S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 For I:=1 to Length(S)do If S[I]in['A'..'Z']Then S[I]:=Chr(Ord(S[I])+32);
 LoStr:=S;
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
 Else If Cp<$10000 Then CpToUtf8:=Chr($E0 or(Cp shr 12))+Chr($80 or((Cp shr
   6)and $3F))+
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

{ ------------------------------------------------------------------ }
{ Sorties et messages                                                 }
{ Les textes du programme sont en CP437 (#130, #138, ...) et sont     }
{ convertis en UTF-8 a l'affichage ; le texte des jetons (deja en     }
{ UTF-8) est ecrit tel quel.                                          }
{ ------------------------------------------------------------------ }

Var
 LogDisabled:Boolean;

Procedure Say(Const S:AnsiString);
Begin
 Write(Cp437ToUtf8(S));
End;

Procedure Fatal(Const S:AnsiString);
Begin
 Flush(Output);
 Write(StdErr,'erreur : ',Cp437ToUtf8(S),#10);
 Flush(StdErr);
 Halt(1);
End;

Procedure LogWrn(Const S:AnsiString);
Begin
 If LogDisabled Then Exit;
 Write(StdErr,Cp437ToUtf8(S));
 Flush(StdErr);
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


{ Lit toute l'entree standard (octets bruts) }
Function ReadStdin:AnsiString;
Var
 F:File;
 Buf:Array[0..65535]of Byte;
 S:AnsiString;
 Got,Len,Cap:LongInt;
Begin
 { fichier non type attache au descripteur de l'entree standard }
 FillChar(F,SizeOf(F),0);
 FileRec(F).Handle:=StdInputHandle;
 FileRec(F).Mode:=fmInput;
 FileRec(F).RecSize:=1;
 S:='';Len:=0;Cap:=0;
 Repeat
  BlockRead(F,Buf,SizeOf(Buf),Got);
  If Got>0 Then Begin
   If Len+Got>Cap Then Begin
    Cap:=(Len+Got)*2;
    SetLength(S,Cap);
   End;
   Move(Buf,S[Len+1],Got);
   Inc(Len,Got);
  End;
 Until Got<=0;
 SetLength(S,Len);
 If IOResult<>0 Then;
 ReadStdin:=S;
End;

{ ------------------------------------------------------------------ }
{ Lecteur GGUF (metadonnees seulement)                                }
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

 TGGUF=Record
  Version:LongInt;
  KV:Array of TGKV;
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
 If IOResult<>0 Then Fatal('impossible d''ouvrir le fichier mod'+#138+'le : '+
   Name);
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
 If L>(1 shl 30)Then Fatal('cha'+#140+'ne GGUF invalide (longueur '+IStr(L)+
   ')');
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
 If Typ in[GT_UINT8,GT_INT8,GT_UINT16,GT_INT16,GT_UINT32,GT_INT32,GT_BOOL,
   GT_UINT64,GT_INT64]Then
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
    Else Fatal('tableau GGUF imbriqu'+#130+' non support'+#130);
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
   GT_UINT8,GT_INT8,GT_UINT16,GT_INT16,GT_UINT32,GT_INT32,GT_BOOL,GT_UINT64,
     GT_INT64:Begin
    SetLength(KV.IA,KV.N);
    For I:=0 to LongInt(KV.N)-1 do Begin
     Tmp.I:=0;Tmp.F:=0;Tmp.S:='';
     ReadScalar(ET,Tmp);
     KV.IA[I]:=LongInt(Tmp.I);
    End;
   End;
   Else Fatal('tableau GGUF imbriqu'+#130+' non support'+#130);
  End;
 End
  Else ReadScalar(KV.Typ,KV);
End;


{ Lit les metadonnees d'un fichier GGUF ; les tenseurs ne sont pas lus }
Procedure ParseGGUF(Const Name:AnsiString;Var G:TGGUF);
Var
 Magic:LongWord;
 NT,NK:Int64;
 I:LongInt;
Begin
 ROpen(Name);
 Magic:=RU32;
 If Magic<>$46554747 Then Fatal(Name+
   ' n''est pas un fichier GGUF valide (signature absente)');
 G.Version:=LongInt(RU32);
 If(G.Version<2)or(G.Version>3)Then
  Fatal('version GGUF non support'+#130+'e : '+IStr(G.Version));
 NT:=Int64(RU64);
 NK:=Int64(RU64);
 If(NT<0)or(NT>1000000)or(NK<0)or(NK>1000000)Then Fatal('en-t'+#136+
   'te GGUF corrompu');
 SetLength(G.KV,NK);
 For I:=0 to LongInt(NK)-1 do ReadKV(G.KV[I],True);
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
                                                         Else
                                                           KVFloat:=G.KV[I].F;
End;

Function KVStr(Const G:TGGUF;Const Key:AnsiString;Const
  Def:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 I:=KVFind(G,Key);
 If(I<0)or(G.KV[I].Typ<>GT_STRING)Then KVStr:=Def Else KVStr:=G.KV[I].S;
End;

{ Valeur d'un tableau d'entiers, ou scalaire repete }
Function KVIntAt(Const G:TGGUF;Const
  Key:AnsiString;Idx:LongInt;Def:Int64):Int64;
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
  CpIsLetter:=(C<>$D7)and(C<>$F7)and not((C>=$2C2)and(C<=$2C5))and
    not((C>=$2D2)and(C<=$2DF))
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
 PRE_SMOLLM=5; PRE_FALCON=6; PRE_DEEPSEEK_LLM=7; PRE_DEEPSEEK_CODER=8;
   PRE_BLOOM=9;
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
  AddBOS,AddEOS,AddSep,AddSpacePrefix,RemoveExtraWs,EscapeWs,CleanSpaces,
    IgnoreMerges:Boolean;
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
Function TokenToPiece(Const
  V:TVocab;Tok:LongInt;Special:Boolean;LStrip:LongInt):AnsiString;
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
  If(V.VType=VT_SPM)or V.EscapeWs Then R:=ReplaceAll(V.Text[Tok],#$E2#$96#$81,
    ' ')
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

Function DetokenizeTokens(Const V:TVocab;Const
  Toks:TIntArray;Count:LongInt;Special:Boolean;
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
 SPL_NUMS=7; SPL_DIG3=8; SPL_NL=9; SPL_SPL=10; SPL_SPP=11; SPL_CJK=12;
   SPL_ENDWS=13;
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

Function SplitSegment(Const Cps:TIntArray;Ini,Fin:LongInt;Kind:LongInt;Var
  Out:TWordList):LongInt;
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
 Function IsOther(P:LongInt):Boolean;  { [^\s\p{L}\p{N}] avec drapeaux non nuls
   }
 Begin
  IsOther:=(CpAt(Cps,P,Ini,Fin)>=0)and not IsS(P)and not IsL(P)and not IsN(P);
 End;

Begin
 PrevEnd:=Ini;
 Pos:=Ini;
 SplitSegment:=0;
 If Kind in[SPL_NL,SPL_SPL,SPL_SPP,SPL_CJK,SPL_ENDWS,SPL_DSPUNCT,SPL_BLOOM]Then
   Begin
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
    If(Pos+2<Fin)and(Cps[Pos]>=48)and(Cps[Pos]<=57)and(Cps[Pos+
      1]>=48)and(Cps[Pos+1]<=57)and
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
   If Kind=SPL_GPT2 Then CN:=CpAt(Cps,Pos+1,Ini,Fin)Else CN:=CpToLower(CpAt(Cps,
     Pos+1,Ini,Fin));
   If(CN=Ord('s'))or(CN=Ord('t'))or(CN=Ord('m'))or(CN=Ord('d'))Then Begin
    AddTok(Pos+2);Pos:=PrevEnd;Continue;
   End;
   If Pos+2<Fin Then Begin
    If Kind=SPL_GPT2 Then CNN:=CpAt(Cps,Pos+2,Ini,Fin)Else
      CNN:=CpToLower(CpAt(Cps,Pos+2,Ini,Fin));
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
    While IsOther(Pos)and(not((Kind=SPL_QWEN35)and CpIsMark(Cps[Pos])))do
      Inc(Pos);
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
Procedure PreTokenize(Const Text:AnsiString;Const Kinds:TIntArray;Var
  Words:TStrArray);
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
Procedure TokenizeSPM(Const V:TVocab;Const Text:AnsiString;Var
  Output:TIntArray);
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
  If(Sym[B.Left].N=0)or(Sym[B.Right].N=0)or(Sym[B.Left].N+
    Sym[B.Right].N<>B.Size)Then Continue;
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
Procedure TokenizeBPEWord(Const V:TVocab;Const
  WordRaw:AnsiString;ByteEncode:Boolean;Var Output:TIntArray);
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
  If(Sym[B.Left].N=0)or(Sym[B.Right].N=0)or(Sym[B.Left].N+
    Sym[B.Right].N<>B.Size)Then Continue;
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

Procedure FragAdd(Var A:TFragArr;Var N:LongInt;IsTok:Boolean;Tok:LongInt;Const
  Txt:AnsiString);
Begin
 If N>=Length(A)Then SetLength(A,Length(A)*2+8);
 A[N].IsTok:=IsTok;A[N].Tok:=Tok;A[N].Txt:=Txt;
 Inc(N);
End;

Var
 PreKinds:TIntArray;

{ Equivalent de llama_vocab::tokenize }
Function VocabTokenize(Const V:TVocab;Const Raw:AnsiString;AddSpecial,
  ParseSpecial:Boolean):TIntArray;
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
   If(not ParseSpecial)and((V.Attr[Sp]and(TA_CONTROL or TA_UNKNOWN))<>0)Then
     Continue;
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
      If P<=Length(Txt)Then FragAdd(NewF,NN,False,0,Copy(Txt,P,Length(Txt)-P+
        1));
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
  PRE_FALCON:Begin AddInt(PreKinds,SPL_PUNCT);AddInt(PreKinds,
    SPL_GPT2);AddInt(PreKinds,SPL_DIG3);End;
  PRE_DEEPSEEK_LLM:Begin
   AddInt(PreKinds,SPL_NL);AddInt(PreKinds,SPL_SPL);AddInt(PreKinds,
     SPL_DSPUNCT);
   AddInt(PreKinds,SPL_ENDWS);AddInt(PreKinds,SPL_CJK);AddInt(PreKinds,
     SPL_NUMS);
  End;
  PRE_DEEPSEEK_CODER:Begin
   AddInt(PreKinds,SPL_NL);AddInt(PreKinds,SPL_SPL);AddInt(PreKinds,SPL_SPP);
   AddInt(PreKinds,SPL_CJK);AddInt(PreKinds,SPL_DIGIT1);
  End;
  PRE_BLOOM:AddInt(PreKinds,SPL_BLOOM);
  PRE_VIKING:Begin AddInt(PreKinds,SPL_BLOOM);AddInt(PreKinds,SPL_DIGIT1);End;
  Else Begin
   AddInt(PreKinds,SPL_PUNCT);AddInt(PreKinds,SPL_GPT2);AddInt(PreKinds,
     SPL_NUMS);AddInt(PreKinds,SPL_DIG3);
  End;
 End;
End;

Function PreTypeFromName(Const N:AnsiString;Var Known:Boolean):LongInt;
Begin
 Known:=True;
 If(N='')or(N='default')Then PreTypeFromName:=PRE_DEFAULT
 Else
   If(N='llama3')or(N='llama-v3')or(N='llama-bpe')or(N='falcon3')or(N='falcon-'+
   'h1')or(N='pixtral')or
    (N='midm-2.0')or(N='lfm2')or(N='jina-v5-nano')or(N='dbrx')or(N='smaug-bp'+
      'e')or(N='chatglm-bpe')or
    (N='glm4')or(N='glm5')Then PreTypeFromName:=PRE_LLAMA3
 Else
   If(N='qwen2')or(N='deepseek-r1-qwen')or(N='kormo')or(N='f2llmv2')or(N='stab'+
   'lelm2')or(N='hunyuan')or
    (N='solar-open')or(N='megrez')Then PreTypeFromName:=PRE_QWEN2
 Else If N='qwen35' Then PreTypeFromName:=PRE_QWEN35
 Else
   If(N='gpt-2')or(N='phi-2')or(N='jina-es')or(N='jina-de')or(N='gigacha'+
   't')or(N='jina-v2-es')or
    (N='jina-v2-de')or(N='a.x-4.0')or(N='mellum')or(N='modern-bert')or(N='mp'+
      't')or(N='olmo')or(N='jais')or
    (N='trillion')or(N='granite-docling')or(N='exaone4')or(N='jina-v1-e'+
      'n')or(N='jina-v2-code')or
    (N='roberta-bpe')Then PreTypeFromName:=PRE_GPT2
 Else
   If(N='starcoder')or(N='refact')or(N='command-r')or(N='smollm')or(N='codeshe'+
   'll')or(N='exaone')or
    (N='minerva-7b')or(N='mellum2')Then PreTypeFromName:=PRE_SMOLLM
 Else If N='falcon' Then PreTypeFromName:=PRE_FALCON
 Else If(N='deepseek-llm')Then PreTypeFromName:=PRE_DEEPSEEK_LLM
 Else If(N='deepseek-coder')Then PreTypeFromName:=PRE_DEEPSEEK_CODER
 Else If(N='poro-chat')or(N='bloom')or(N='gpt3-finnish')Then
   PreTypeFromName:=PRE_BLOOM
 Else If N='viking' Then PreTypeFromName:=PRE_VIKING
 Else
   If(N='gpt-4o')or(N='llama4')or(N='kanana2')or(N='talkie')or(N='tekken')Then
   PreTypeFromName:=PRE_LLAMA3
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
    LogWrn('avertissement : '+Key+' = '+IStr(X)+' hors vocabulaire, ignor'+#130+
      #10);
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
  Fatal('le mod'+#138+
    'le ne contient pas de vocabulaire (tokenizer.ggml.model absent)');
 End;
 TI:=KVFind(G,'tokenizer.ggml.tokens');
 If(TI<0)or(G.KV[TI].Typ<>GT_ARRAY)or(G.KV[TI].ArrTyp<>GT_STRING)Then
  Fatal('vocabulaire introuvable dans le fichier mod'+#138+
    'le (tokenizer.ggml.tokens)');
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
   If V.PreName='' Then LogWrn('avertissement : pr'+#130+
     '-tokeniseur absent, utilisation de ''default'''+#10)
   Else If not Known Then
    LogWrn('avertissement : pr'+#130+'-tokeniseur inconnu ('+V.PreName+
      '), approximation utilis'+#130+'e'+#10);
   If(V.PreName='llama-bpe')or(V.PreName='llama3')Then V.IgnoreMerges:=True;
   If(V.PreName='tekken')or(V.PreName='gpt-4o')Then V.IgnoreMerges:=True;
   If(V.PreName='qwen2')Then V.IgnoreMerges:=False;
   MI:=KVFind(G,'tokenizer.ggml.merges');
   If MI<0 Then Fatal('fusions BPE introuvables dans le fichier mod'+#138+
     'le (tokenizer.ggml.merges)');
   HInit(V.MergeHash,Length(G.KV[MI].SA));
   For I:=0 to High(G.KV[MI].SA)do Begin
    T:=G.KV[MI].SA[I];
    P:=PosFrom(' ',T,2);
    If P>0 Then Begin
     HPut(V.MergeHash,Copy(T,1,P-1)+#1+Copy(T,P+1,Length(T)-P),I);
    End;
   End;
  End
  Else Fatal('type de tokeniseur non support'+#130+' : '+V.Model);
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
 If KVHas(G,'tokenizer.ggml.add_bos_token')Then V.AddBOS:=KVInt(G,
   'tokenizer.ggml.add_bos_token',0)<>0;
 If KVHas(G,'tokenizer.ggml.add_eos_token')Then V.AddEOS:=KVInt(G,
   'tokenizer.ggml.add_eos_token',0)<>0;
 If KVHas(G,'tokenizer.ggml.add_sep_token')Then V.AddSep:=KVInt(G,
   'tokenizer.ggml.add_sep_token',0)<>0;
 { jetons de fin de generation (EOG) }
 For I:=0 to V.NTokens-1 do Begin
  T:=V.Text[I];
  If(T='<|eot_id|>')or(T='<|im_end|>')or(T='<|end|>')or(T='<|return|>')or(T='<'+
    '|call|>')or
    (T='<|flush|>')or(T='<|calls|>')or(T='<end_of_turn>')or(T='<|endoftext|'+
      '>')or(T='</s>')or
    (T='<|eom_id|>')or(T='<EOT>')or(T='_<EOT>')or(T='[EOT]')or(T='[EOS'+
      ']')or(T='<|end_of_text|>')or
    (T='<end_of_utterance>')or(T='<eos>')or(T='<turn|>')or(T='<|tool_response'+
      '>')or
    (T='<｜end▁of▁sentence｜>')or(T='[e~[')Then Begin
   V.EOG[I]:=True;
   V.Attr[I]:=V.Attr[I]or TA_CONTROL;
  End;
  If V.EOT<0 Then Begin
   If(T='<|eot_id|>')or(T='<|im_end|>')or(T='<|end|>')or(T='<end_of_turn'+
     '>')or(T='<|endoftext|>')or
     (T='<|end_of_text|>')or(T='<EOT>')or(T='_<EOT>')or(T='[EOT]')or(T='<end_o'+
       'f_utterance>')Then
    V.EOT:=I;
  End;
  If V.FimPre<0 Then
   If(T='<|fim_prefix|>')or(T='<fim-prefix>')or(T='<fim_prefix>')or(T='<PRE'+
     '>')or(T='▁<PRE>')Then V.FimPre:=I;
  If V.FimSuf<0 Then
   If(T='<|fim_suffix|>')or(T='<fim-suffix>')or(T='<fim_suffix>')or(T='<SUF'+
     '>')or(T='▁<SUF>')Then V.FimSuf:=I;
  If V.FimMid<0 Then
   If(T='<|fim_middle|>')or(T='<fim-middle>')or(T='<fim_middle>')or(T='<MID'+
     '>')or(T='▁<MID>')Then V.FimMid:=I;
 End;
 MarkEog(V.EOS);MarkEog(V.EOT);MarkEog(V.EOM);
 MarkEog(V.FimPad);MarkEog(V.FimRep);MarkEog(V.FimSep);
 { jetons speciaux tries par longueur decroissante (tri par comptage) }
 Cnt:=0;
 For I:=0 to V.NTokens-1 do
  If(V.Attr[I]and(TA_CONTROL or TA_USER_DEFINED or TA_UNKNOWN))<>0 Then
    Inc(Cnt);
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
{ Console et arguments                                                }
{ ------------------------------------------------------------------ }

{$IFDEF WINDOWS}
Function SetConsoleOutputCP(CP:LongWord):LongInt;stdcall;external
  'kernel32.dll' name 'SetConsoleOutputCP';
Function GetConsoleOutputCP:LongWord;stdcall;external 'kernel32.dll' name
  'GetConsoleOutputCP';
Function MultiByteToWideChar(CP,
  Flags:LongWord;S:PChar;N:LongInt;W:PWideChar;WN:LongInt):LongInt;
 stdcall;external 'kernel32.dll' name 'MultiByteToWideChar';
Function WideCharToMultiByte(CP,
  Flags:LongWord;W:PWideChar;WN:LongInt;S:PChar;N:LongInt;Def:PChar;Used:Pointer):LongInt;
 stdcall;external 'kernel32.dll' name 'WideCharToMultiByte';

Var
 SavedOutCP:LongWord;
 OldExitProc:Pointer;

{ remet la page de codes d'origine de la console a la fin du programme }
Procedure RestoreConsole;
Begin
 ExitProc:=OldExitProc;
 SetConsoleOutputCP(SavedOutCP);
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
{$ELSE}
Function ArgStr(I:LongInt):AnsiString;
Begin
 ArgStr:=ParamStr(I);
End;
{$ENDIF}

Procedure InitConsole;
Begin
 {$IFDEF WINDOWS}
 SavedOutCP:=GetConsoleOutputCP;
 SetConsoleOutputCP(65001);
 OldExitProc:=ExitProc;
 ExitProc:=@RestoreConsole;
 {$ENDIF}
 SetTextCodePage(Output,DefaultSystemCodePage);
 SetTextCodePage(StdErr,DefaultSystemCodePage);
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

{ ------------------------------------------------------------------ }
{ Aide                                                                }
{ ------------------------------------------------------------------ }

Procedure ShowHelp;
Begin
 Say('usage : llama-tokenize [options]'#10#10);
 Say('Tokenise un texte avec le vocabulaire d''un mod'+#138+'le GGUF et affiche les'#10);
 Say('jetons (tokens) obtenus sur la sortie standard.'#10#10);
 Say('Il faut un fichier mod'+#138+'le, un texte et, au besoin, des options qui'#10);
 Say('modifient le comportement du tokeniseur.'#10#10);
 Say('Options :'#10#10);
 Say('  -h, --help                    affiche cette aide et quitte'#10);
 Say('  -m, --model CHEMIN            chemin du mod'+#138+'le GGUF utilis'+#130+' pour la'#10);
 Say('                                tokenisation (obligatoire)'#10);
 Say('  -p, --prompt TEXTE            texte '+#133+' analyser'#10);
 Say('  -f, --file FICHIER            lit le texte depuis un fichier'#10);
 Say('      --stdin                   lit le texte depuis l''entr'+#130+'e standard'#10);
 Say('      --ids                     affiche seulement les identifiants num'+#130+'riques'#10);
 Say('                                des jetons, sous la forme [1, 2, 3]'#10);
 Say('      --show-count              affiche le nombre total de jetons'#10);
 Say('      --no-bos                  n''ajoute jamais le jeton de d'+#130+'but de s'+#130+'quence'#10);
 Say('                                (BOS), m'+#136+'me si le mod'+#138+'le en ajoute un'#10);
 Say('      --no-escape               n''interpr'+#138+'te pas les s'+#130+'quences \n, \t, \xHH...'#10);
 Say('      --no-parse-special        n''interpr'+#138+'te pas les jetons sp'+#130+'ciaux'#10);
 Say('                                (<s>, <|im_start|>, ...) : ils sont d'+#130+'coup'+#130+'s'#10);
 Say('                                comme du texte ordinaire'#10);
 Say('      --log-disable             supprime les avertissements (stderr)'#10);
 Say('      --version                 affiche la version et quitte'#10#10);
 Say('Exemples :'#10);
 Say('  llama-tokenize -m modele.gguf -p "Quelle est la capitale du Canada ?" --show-count'#10);
 Say('  llama-tokenize -m modele.gguf -f question.txt --ids'#10);
End;

Procedure ArgError(Const Msg:AnsiString);
Begin
 Write(StdErr,'erreur : ',Cp437ToUtf8(Msg),#10);
 Write(StdErr,'(utilisez --help pour afficher la liste des options)'#10);
 Flush(StdErr);
 Halt(1);
End;

{ ------------------------------------------------------------------ }
{ Programme principal                                                 }
{ ------------------------------------------------------------------ }

Var
 ModelPath,PromptArg,FileArg,Prompt,Piece:AnsiString;
 PromptSet,FileSet,StdinSet,ShowIds,ShowCount:Boolean;
 NoBos,NoEscape,NoParseSpecial:Boolean;
 G:TGGUF;
 V:TVocab;
 Toks:TIntArray;
 I,K,Eq:LongInt;
 A,OptVal:AnsiString;
 HasEq,AddBos:Boolean;

{ valeur de l'option courante : --option=valeur ou argument suivant }
Function OptValue:AnsiString;
Begin
 If HasEq Then OptValue:=OptVal
  Else Begin
   If I+1>ParamCount Then ArgError('l''argument '+A+' attend une valeur');
   Inc(I);
   OptValue:=ArgStr(I);
  End;
End;

Procedure NoValue;
Begin
 If HasEq Then ArgError('l''argument '+A+' n''accepte pas de valeur');
End;

Begin
 InitConsole;
 ModelPath:='';PromptArg:='';FileArg:='';
 PromptSet:=False;FileSet:=False;StdinSet:=False;
 ShowIds:=False;ShowCount:=False;
 NoBos:=False;NoEscape:=False;NoParseSpecial:=False;
 LogDisabled:=False;
 If ParamCount=0 Then Begin
  ShowHelp;
  Halt(0);
 End;
 I:=1;
 While I<=ParamCount do Begin
  A:=ArgStr(I);
  HasEq:=False;OptVal:='';
  If Copy(A,1,2)='--' Then Begin
   Eq:=Pos('=',A);
   If Eq>0 Then Begin
    HasEq:=True;
    OptVal:=Copy(A,Eq+1,Length(A));
    A:=Copy(A,1,Eq-1);
   End;
  End;
  If(A='-h')or(A='--help')or(A='/?')Then Begin
   ShowHelp;
   Halt(0);
  End
  Else If A='--version' Then Begin
   Say('llama-tokenize '+VersionStr+#10);
   Halt(0);
  End
  Else If(A='-m')or(A='--model')Then ModelPath:=OptValue
  Else If(A='-p')or(A='--prompt')Then Begin
   PromptArg:=OptValue;PromptSet:=True;
  End
  Else If(A='-f')or(A='--file')Then Begin
   FileArg:=OptValue;FileSet:=True;
  End
  Else If A='--stdin' Then Begin NoValue;StdinSet:=True;End
  Else If A='--ids' Then Begin NoValue;ShowIds:=True;End
  Else If A='--show-count' Then Begin NoValue;ShowCount:=True;End
  Else If A='--no-bos' Then Begin NoValue;NoBos:=True;End
  Else If A='--no-escape' Then Begin NoValue;NoEscape:=True;End
  Else If A='--no-parse-special' Then Begin NoValue;NoParseSpecial:=True;End
  Else If A='--log-disable' Then Begin NoValue;LogDisabled:=True;End
  Else ArgError('argument invalide : '+ArgStr(I));
  Inc(I);
 End;
 If ModelPath='' Then ArgError('le chemin du mod'+#138+'le est obligatoire (-m)');
 K:=0;
 If PromptSet Then Inc(K);
 If FileSet Then Inc(K);
 If StdinSet Then Inc(K);
 If K=0 Then ArgError('aucun texte '+#133+' analyser : utilisez -p, -f ou --stdin');
 If K>1 Then ArgError('les options -p, -f et --stdin sont exclusives');
 { texte a analyser }
 If PromptSet Then Prompt:=PromptArg
 Else If FileSet Then Begin
  If not FileExistsP(FileArg)Then Fatal('le fichier est introuvable : '+FileArg);
  If not ReadWholeFile(FileArg,Prompt)Then Fatal(
    'impossible de lire le fichier : '+FileArg);
 End
 Else Prompt:=ReadStdin;
 { modele }
 If not FileExistsP(ModelPath)Then Fatal('le fichier mod'+#138+
   'le est introuvable : '+ModelPath);
 ParseGGUF(ModelPath,G);
 InitByteUnicode;
 LoadVocab(V,G);
 If not NoEscape Then Prompt:=ProcessEscapes(Prompt);
 AddBos:=V.AddBOS and not NoBos;
 Toks:=VocabTokenize(V,Prompt,AddBos,not NoParseSpecial);
 { affichage }
 If ShowIds Then Begin
  Write('[');
  For I:=0 to High(Toks)do Begin
   If I>0 Then Write(', ');
   Write(Toks[I]);
  End;
  Write(']'#10);
 End
  Else Begin
   For I:=0 to High(Toks)do Begin
    Piece:=TokenToPiece(V,Toks[I],True,0);
    Write(Toks[I]:6,' -> ''',Piece,''''#10);
   End;
  End;
 If ShowCount Then Write('Total number of tokens: ',Length(Toks),#10);
 Flush(Output);
End.
