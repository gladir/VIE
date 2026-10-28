{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/vie)
  @abstract(Target: Free Pascal 3.x)

  BENCHMARK_APP : clone de la commande benchmark_app d'OpenVINO.

  Mesure les performances d'inference (latence et debit) d'un modele au
  format OpenVINO IR (fichiers .xml + .bin), par exemple celui produit par
  OPTIMUM-CLI.PAS (optimum-cli export openvino). Le modele est lu, compile
  (graphe verifie, constantes chargees) puis execute par un interprete
  de graphe ecrit en Pascal : les chiffres obtenus mesurent donc cet
  interprete sur le processeur courant, pas le plugin CPU d'OpenVINO.

  Syntaxe :
   benchmark_app -m modele.xml -d CPU
   benchmark_app -m modele.xml -d CPU -hint latency
   benchmark_app -m modele.xml -d CPU -hint throughput
   benchmark_app -m modele.xml -d CPU -t 60
   benchmark_app -m modele.xml -d CPU -hint none -nthreads 8

  Principaux parametres :
   -h, --help, /?   Affiche l'aide.
   -m               Chemin du modele (.xml, ou dossier contenant
                    openvino_model.xml).
   -d, --device     Peripherique cible (CPU, AUTO:CPU, MULTI:CPU, HETERO:CPU).
   -i               Entrees : fichiers .bin / .npy ou dossier, eventuellement
                    sous la forme nom:fichier1,fichier2.
   -hint            latency, throughput (tput), cumulative_throughput (ctput)
                    ou none.
   -niter           Nombre d'iterations de mesure.
   -t               Duree du benchmark en secondes.
   -b               Taille du lot (batch).
   -shape           Forme des entrees : "entree[1,128],autre[1,128]".
   -data_shape      Formes des donnees pour les entrees dynamiques.
   -layout          Disposition des entrees : "entree[NC]".
   -nthreads        Nombre de threads CPU.
   -nstreams        Nombre de flux d'inference.
   -nireq           Nombre de requetes d'inference.
   -api             sync ou async.
   -infer_precision Precision d'inference demandee (f32, f16, bf16).
   -cdir            Repertoire de cache.
   -report_folder   Repertoire des rapports de performance.
   -report_type     no_counters, average_counters, detailed_counters.
   -pc              Collecte des compteurs de performance par couche.
   --weight-format  Accepte pour compatibilite avec optimum-cli (sans effet :
                    la precision des poids est celle du modele).

  Sortie : le journal reprend le format du benchmark_app d'OpenVINO
  (etapes 1 a 11, "[ INFO ]", "Latency:", "Throughput:"...), de sorte
  que les scripts qui l'analysent continuent de fonctionner. Les messages
  d'aide et d'erreur sont en francais.

  Operations de graphe prises en charge : Parameter, Const, Result,
  Convert, Add, Subtract, Multiply, Divide, Power, Maximum, Minimum, Mod,
  SquaredDifference, Equal, NotEqual, Less, LessEqual, Greater,
  GreaterEqual, LogicalAnd, LogicalOr, LogicalNot, Select, Abs, Ceiling,
  Cos, Erf, Exp, Floor, Gelu, HSigmoid, HSwish, Log, Mish, Negative, Relu,
  Sigmoid, Sign, Sin, Sqrt, Swish, Tan, Tanh, Clamp, Softmax, ShapeOf,
  Gather, Range, Reshape, Squeeze, Unsqueeze, Transpose, MatMul, Concat,
  Split, VariadicSplit, Broadcast, ReduceMean, ReduceSum, ReduceMax,
  ReduceMin, ReduceProd, ScaledDotProductAttention, ReadValue, Assign.
  C'est l'ensemble produit par OPTIMUM-CLI.PAS pour les modeles de la
  famille LLaMA (poids fp32, fp16, int8, int4, nf4). Toute autre operation
  (convolutions, TensorIterator...) est signalee a la compilation.

  Particularites et limites de ce clone :
   - formats .xml/.bin (IR v10 et v11) uniquement : un fichier .onnx doit
     d'abord etre converti; aucune URL n'est lue;
   - calcul en FP32 : les types FP16/BF16 du graphe sont calcules en FP32,
     comme le fait le plugin CPU d'OpenVINO avec une precision d'inference
     f32 (-infer_precision est accepte et affiche mais ne change pas le
     calcul); les poids int8/int4/nf4 sont decompresses a chaque inference;
   - un MatMul dont la 2e entree (transposee) est une constante, brute ou
     compressee (Convert(Const), ou decompression int8/int4/nf4 avec echelle
     et zero), est fusionne : les poids sont decompresses a la volee, sans
     materialiser la matrice FP32 (memoire et temps de calcul reduits);
   - les entiers sont conserves en simple precision (exacts jusqu'a 2^24);
   - les etats (ReadValue/Assign du cache KV des modeles "stateful") sont
     remis a zero avant chaque inference, de sorte que chaque iteration
     mesure le meme travail;
   - les indices de Gather hors limites sont ramenes dans [0,N-1] : les
     entrees aleatoires (entiers de 0 a 255) restent donc utilisables;
   - une entree dynamique sans -shape/-data_shape recoit la forme par
     defaut [lot,16,...] (avertissement), alors qu'OpenVINO s'arrete;
   - un modele dynamique est accepte aussi en mode sync;
   - les images ne sont pas lues (-i accepte .bin et .npy);
   - -extensions, -c, -lfile, -load_config, -dump_config, -exec_graph_path,
     -pin, -mean_values, -scale_values, -ip, -op, -iop sont acceptes puis
     ignores (avertissement);
   - option supplementaire -dump_output <dossier> : ecrit les sorties de la
     premiere inference (un fichier .bin par sortie) pour verification;
   - le repertoire de cache (-cdir) est cree mais aucun blob n'y est
     enregistre : la compilation consiste seulement a lire le graphe.

  Contraintes respectees :
   - un seul fichier source, aucun fichier d'inclusion;
   - la seule unite utilisee est DOS (le reste vient de l'unite System);
   - sous Windows uniquement ($IFDEF WINDOWS) : horloge haute resolution
     (QueryPerformanceCounter de kernel32) et fils d'execution (BeginThread
     de l'unite System) pour les flux d'inference (-nstreams, -hint
     throughput) et le calcul parallele des multiplications de matrices.
     Ailleurs, un seul fil est utilise et l'horloge a une resolution de
     10 ms (un avertissement le rappelle). Pour essayer les fils sous Unix, definir THREADS et ajouter
     l'unite cthreads a la clause Uses.
   - compilable avec Free Pascal 32 bits pour Windows.

  Un programme Turbo Pascal 16 bits ne peut pas charger de modele de
  plusieurs Mo : il faut un compilateur 32 ou 64 bits (Free Pascal).

  Compilation : fpc -O3 BENCHMARK_APP.PAS
}

Program BENCHMARK_APP;

{$IFDEF FPC}
 {$MODE OBJFPC}
 {$H+}
 {$INLINE ON}
 {$R-}
 {$Q-}
 {$IOCHECKS OFF}
 {$POINTERMATH ON}
 {$NOTES OFF}
 {$HINTS OFF}
 {$WARNINGS OFF}
{$ENDIF}

{$IFDEF WINDOWS}
 {$DEFINE THREADS}
 {$DEFINE HIRES}
{$ENDIF}

Uses DOS;

Const
 VersionStr   = 'BENCHMARK_APP 1.0 (clone Pascal de benchmark_app)';

 { Precisions des tenseurs }
 PR_F32=0; PR_F16=1; PR_BF16=2; PR_F64=3; PR_I64=4; PR_I32=5; PR_I16=6;
 PR_I8=7; PR_U64=8; PR_U32=9; PR_U16=10; PR_U8=11; PR_U4=12; PR_I4=13;
 PR_NF4=14; PR_BOOL=15;
 PR_COUNT=16;

 PrecName:Array[0..15] of AnsiString=
  ('FP32','FP16','BF16','FP64','I64','I32','I16','I8','U64','U32','U16',
   'U8','U4','I4','NF4','BOOL');
 ElemName:Array[0..15] of AnsiString=
  ('f32','f16','bf16','f64','i64','i32','i16','i8','u64','u32','u16',
   'u8','u4','i4','nf4','boolean');
 PrecBits:Array[0..15] of LongInt=
  (32,16,16,64,64,32,16,8,64,32,16,8,4,4,4,8);

 NF4Table:Array[0..15] of Single=(
  -1.0,-0.6961928009986877,-0.5250730514526367,-0.39491748809814453,
  -0.28444138169288635,-0.18477343022823334,-0.09105003625154495,0.0,
  0.07958029955625534,0.16093020141124725,0.24611230194568634,
  0.33791524171829224,0.44070982933044434,0.5626170039176941,
  0.7229568362236023,1.0);

 { Codes des operations }
 OP_NONE=0; OP_PARAM=1; OP_CONST=2; OP_RESULT=3; OP_CONVERT=4;
 OP_ADD=10; OP_SUB=11; OP_MUL=12; OP_DIV=13; OP_POW=14; OP_MAX=15;
 OP_MIN=16; OP_MOD=17; OP_SQDIFF=18;
 OP_EQ=20; OP_NE=21; OP_LT=22; OP_LE=23; OP_GT=24; OP_GE=25;
 OP_AND=26; OP_OR=27;
 OP_NOT=30; OP_ABS=31; OP_CEIL=32; OP_COS=33; OP_ERF=34; OP_EXP=35;
 OP_FLOOR=36; OP_GELU=37; OP_HSIG=38; OP_HSWISH=39; OP_LOG=40; OP_MISH=41;
 OP_NEG=42; OP_RELU=43; OP_SIGMOID=44; OP_SIGN=45; OP_SIN=46; OP_SQRT=47;
 OP_SWISH=48; OP_TAN=49; OP_TANH=50; OP_CLAMP=51; OP_SOFTMAX=52;
 OP_SELECT=60; OP_SHAPEOF=61; OP_GATHER=62; OP_RANGE=63; OP_RESHAPE=64;
 OP_SQUEEZE=65; OP_UNSQUEEZE=66; OP_TRANSPOSE=67; OP_MATMUL=68;
 OP_CONCAT=69; OP_SPLIT=70; OP_VSPLIT=71; OP_BROADCAST=72;
 OP_RMEAN=73; OP_RSUM=74; OP_RMAX=75; OP_RMIN=76; OP_RPROD=77;
 OP_SDPA=78; OP_READVALUE=79; OP_ASSIGN=80;

 { Nombre minimal de multiplications-additions pour paralleliser }
 ParThreshold = 400000;

Type
 TIntArr = Array of LongInt;
 TSingleArr = Array of Single;
 TByteArr = Array of Byte;
 TDblArr = Array of Double;
 TStrArr = Array of AnsiString;
 PSingle = ^Single;
 PByte = ^Byte;

 TSL = Record
  Case Byte of
   0:(S:Single);
   1:(L:LongWord);
 End;

{ ------------------------------------------------------------------ }
{ Utilitaires generaux                                                }
{ ------------------------------------------------------------------ }

Function IStr(N:Int64):AnsiString;
Var
 S:AnsiString;
Begin
 Str(N,S);
 IStr:=S;
End;

Function FStr(X:Double;D:Integer):AnsiString;
Var
 S:AnsiString;
Begin
 Str(X:0:D,S);
 FStr:=S;
End;

Function LoStr(S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 For I:=1 to Length(S) do If S[I] in ['A'..'Z']Then S[I]:=Chr(Ord(S[I])+32);
 LoStr:=S;
End;

Function UpStr(S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 For I:=1 to Length(S) do If S[I] in ['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
 UpStr:=S;
End;

Function StartsWith(Const S,P:AnsiString):Boolean;
Begin
 StartsWith:=(Length(S)>=Length(P))and(Copy(S,1,Length(P))=P);
End;

Function EndsWith(Const S,P:AnsiString):Boolean;
Begin
 EndsWith:=(Length(S)>=Length(P))and(Copy(S,Length(S)-Length(P)+1,Length(P))=P);
End;

Function TrimStr(Const S:AnsiString):AnsiString;
Var
 A,B:LongInt;
Begin
 A:=1;B:=Length(S);
 While(A<=B)and(S[A] in [' ',#9,#10,#13])do Inc(A);
 While(B>=A)and(S[B] in [' ',#9,#10,#13])do Dec(B);
 TrimStr:=Copy(S,A,B-A+1);
End;

Function ReplaceAll(Const S,A,B:AnsiString):AnsiString;
Var
 R:AnsiString;
 I:LongInt;
Begin
 R:='';
 I:=1;
 While I<=Length(S) do Begin
  If(A<>'')and(Copy(S,I,Length(A))=A)Then Begin
   R:=R+B;
   Inc(I,Length(A));
  End
   Else
  Begin
   R:=R+S[I];
   Inc(I);
  End;
 End;
 ReplaceAll:=R;
End;

Function ToF(S:AnsiString;Def:Double):Double;
Var
 V:Double;
 Code:LongInt;
Begin
 Val(TrimStr(S),V,Code);
 If Code<>0 Then ToF:=Def
            Else ToF:=V;
End;

Function ToI(S:AnsiString;Def:Int64):Int64;
Var
 V:Int64;
 Code:LongInt;
Begin
 Val(TrimStr(S),V,Code);
 If Code<>0 Then ToI:=Def
            Else ToI:=V;
End;

Function IsInt(Const S:AnsiString):Boolean;
Var
 V:Int64;
 Code:LongInt;
Begin
 Val(TrimStr(S),V,Code);
 IsInt:=(Code=0)and(TrimStr(S)<>'');
End;

{ Decoupe S en morceaux separes par Sep (les vides sont conserves) }
Function SplitStr(Const S:AnsiString;Sep:Char):TStrArr;
Var
 I,N,Start:LongInt;
Begin
 SetLength(SplitStr,0);
 N:=0;
 Start:=1;
 For I:=1 to Length(S)+1 do
  If(I>Length(S))or(S[I]=Sep)Then Begin
   SetLength(SplitStr,N+1);
   SplitStr[N]:=Copy(S,Start,I-Start);
   Inc(N);
   Start:=I+1;
  End;
End;

Procedure Info(Const Msg:AnsiString);
Begin
 WriteLn('[ INFO ] ',Msg);
End;

Procedure Warn(Const Msg:AnsiString);
Begin
 WriteLn('[ WARNING ] ',Msg);
End;

Type
 TStrFunc = Function:AnsiString;

Var
 ErrHook:TStrFunc;      { complement du message d'erreur (couche en cours) }

Procedure Die(Const Msg:AnsiString);
Begin
 If Assigned(ErrHook)Then WriteLn('[ ERROR ] ',Msg,ErrHook())
                     Else WriteLn('[ ERROR ] ',Msg);
 Halt(1);
End;

Function JoinPath(Const D,F:AnsiString):AnsiString;
Begin
 If D=''Then JoinPath:=F Else
 If D[Length(D)] in ['/','\',':']Then JoinPath:=D+F
                                 Else JoinPath:=D+DirectorySeparator+F;
End;

Function FileExists(Const P:AnsiString):Boolean;
Var
 SR:SearchRec;
Begin
 FindFirst(P,AnyFile,SR);
 FileExists:=(DosError=0)and((SR.Attr and Directory)=0);
 FindClose(SR);
End;

Function DirExists(Const P:AnsiString):Boolean;
Var
 Old:String;
 E:Word;
Begin
 If P=''Then Begin
  DirExists:=False;
  Exit;
 End;
 GetDir(0,Old);
 {$I-}ChDir(P);{$I+}
 E:=IOResult;
 If E=0 Then Begin
  {$I-}ChDir(Old);{$I+}
  E:=IOResult;
  DirExists:=True;
 End
  Else
 DirExists:=False;
End;

Procedure MakeDirs(Const P:AnsiString);
Var
 I:LongInt;
 Cur:AnsiString;
 E:Word;
Begin
 Cur:='';
 For I:=1 to Length(P) do Begin
  If(P[I] in ['/','\'])and(Cur<>'')and(Cur[Length(Cur)]<>':')Then Begin
   If Not DirExists(Cur)Then Begin
    {$I-}MkDir(Cur);{$I+}
    E:=IOResult;
   End;
  End;
  Cur:=Cur+P[I];
 End;
 If(Cur<>'')and Not DirExists(Cur)Then Begin
  {$I-}MkDir(Cur);{$I+}
  E:=IOResult;
 End;
End;

Function FileExt(Const P:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 FileExt:='';
 For I:=Length(P) downto 1 do Begin
  If P[I] in ['/','\',':']Then Exit;
  If P[I]='.'Then Begin
   FileExt:=LoStr(Copy(P,I,Length(P)));
   Exit;
  End;
 End;
End;

Function ChangeExt(Const P,Ext:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 ChangeExt:=P+Ext;
 For I:=Length(P) downto 1 do Begin
  If P[I] in ['/','\',':']Then Exit;
  If P[I]='.'Then Begin
   ChangeExt:=Copy(P,1,I-1)+Ext;
   Exit;
  End;
 End;
End;

Function BaseName(Const P:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 BaseName:=P;
 For I:=Length(P) downto 1 do
  If P[I] in ['/','\',':']Then Begin
   BaseName:=Copy(P,I+1,Length(P));
   Exit;
  End;
End;

Function ReadWholeFile(Const P:AnsiString):AnsiString;
Var
 F:File;
 N:Int64;
 S:AnsiString;
Begin
 ReadWholeFile:='';
 Assign(F,P);
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0 Then Exit;
 N:=FileSize(F);
 SetLength(S,N);
 If N>0 Then Begin
  {$I-}BlockRead(F,S[1],N);{$I+}
  If IOResult<>0 Then S:='';
 End;
 {$I-}Close(F);{$I+}
 If IOResult<>0 Then ;
 ReadWholeFile:=S;
End;

{ ------------------------------------------------------------------ }
{ Horloge                                                             }
{ ------------------------------------------------------------------ }

{$IFDEF HIRES}
Function QueryPerformanceCounter(Var C:Int64):LongInt;
 stdcall; external 'kernel32' name 'QueryPerformanceCounter';
Function QueryPerformanceFrequency(Var F:Int64):LongInt;
 stdcall; external 'kernel32' name 'QueryPerformanceFrequency';
{$ENDIF}

Var
 ClockFreq:Double;
 ClockLast,ClockDay:Double;

{ Temps ecoule en millisecondes depuis un instant quelconque }
Function NowMs:Double;
{$IFDEF HIRES}
Var
 C:Int64;
Begin
 QueryPerformanceCounter(C);
 NowMs:=C*ClockFreq;
End;
{$ELSE}
Var
 H,M,S,C:Word;
 T:Double;
Begin
 GetTime(H,M,S,C);
 T:=((H*60.0+M)*60.0+S)*1000.0+C*10.0;
 If T+ClockDay<ClockLast-1000.0 Then ClockDay:=ClockDay+86400000.0;
 ClockLast:=T+ClockDay;
 NowMs:=ClockLast;
End;
{$ENDIF}

Procedure InitClock;
{$IFDEF HIRES}
Var
 F:Int64;
Begin
 QueryPerformanceFrequency(F);
 If F<=0 Then F:=1000;
 ClockFreq:=1000.0/F;
End;
{$ELSE}
Begin
 ClockFreq:=1.0;
 ClockLast:=0;
 ClockDay:=0;
End;
{$ENDIF}

{ ------------------------------------------------------------------ }
{ Flottants 16 bits                                                   }
{ ------------------------------------------------------------------ }

Function BitsToSingle(L:LongWord):Single;
Var
 R:TSL;
Begin
 R.L:=L;
 BitsToSingle:=R.S;
End;

Function SingleToBits(S:Single):LongWord;
Var
 R:TSL;
Begin
 R.S:=S;
 SingleToBits:=R.L;
End;

Function HalfToSingle(H:Word):Single;
Var
 Sg,E,M:LongWord;
 V:Single;
Begin
 Sg:=(H shr 15)and 1;
 E:=(H shr 10)and $1F;
 M:=H and $3FF;
 If E=0 Then Begin
  V:=M*5.9604644775390625E-8;
  If Sg<>0 Then V:=-V;
  HalfToSingle:=V;
 End
  Else
 If E=31 Then HalfToSingle:=BitsToSingle((Sg shl 31)or $7F800000 or(M shl 13))
         Else HalfToSingle:=BitsToSingle((Sg shl 31)or((E+112)shl 23)or(M shl 13));
End;

Function SingleToHalf(F:Single):Word;
Var
 Bits,Sg,Ex,Mant,Half,Sh,M2:LongWord;
 E:LongInt;
 Rb,Sticky:Boolean;
Begin
 Bits:=SingleToBits(F);
 Sg:=(Bits shr 16)and $8000;
 Ex:=(Bits shr 23)and $FF;
 Mant:=Bits and $7FFFFF;
 If Ex=255 Then Begin
  If Mant<>0 Then SingleToHalf:=Sg or $7E00
             Else SingleToHalf:=Sg or $7C00;
  Exit;
 End;
 E:=LongInt(Ex)-127+15;
 If E>=31 Then Begin
  SingleToHalf:=Sg or $7C00;
  Exit;
 End;
 If E<=0 Then Begin
  If E<-10 Then Begin
   SingleToHalf:=Sg;
   Exit;
  End;
  M2:=Mant or $800000;
  Sh:=14-E;
  Half:=M2 shr Sh;
  Rb:=((M2 shr(Sh-1))and 1)<>0;
  Sticky:=(M2 and((LongWord(1) shl(Sh-1))-1))<>0;
  If Rb and(Sticky or((Half and 1)<>0))Then Inc(Half);
  SingleToHalf:=Sg or Half;
  Exit;
 End;
 Half:=(LongWord(E) shl 10)or(Mant shr 13);
 Rb:=((Mant shr 12)and 1)<>0;
 Sticky:=(Mant and $FFF)<>0;
 If Rb and(Sticky or((Half and 1)<>0))Then Inc(Half);
 SingleToHalf:=Sg or Half;
End;

{ Arrondi a la precision FP16 / BF16 }
Function RoundHalf(X:Single):Single;
Begin
 RoundHalf:=HalfToSingle(SingleToHalf(X));
End;

Function RoundBF16(X:Single):Single;
Var
 B:LongWord;
Begin
 B:=SingleToBits(X);
 If((B shr 23)and $FF)=255 Then Begin
  RoundBF16:=X;
  Exit;
 End;
 B:=(B+$7FFF+((B shr 16)and 1))and $FFFF0000;
 RoundBF16:=BitsToSingle(B);
End;

{ ------------------------------------------------------------------ }
{ Tenseurs                                                           }
{ ------------------------------------------------------------------ }

Type
 TTensor = Record
  Prec:LongInt;
  Dims:TIntArr;
  D:TSingleArr;      { valeurs, si Raw est vide }
  Raw:TByteArr;      { constante compacte : octets du fichier .bin }
 End;

 TPortInfo = Record
  Id,Prec:LongInt;
  Dims:TIntArr;
  Names:AnsiString;
 End;

 TLayer = Record
  Id:LongInt;
  Name,Typ,Ver,Attrs:AnsiString;
  NIn:LongInt;
  SrcL,SrcP:TIntArr;        { entree i : indice de couche et de sortie }
  Outs:Array of TPortInfo;
  Op:LongInt;
  IA,IB:LongInt;
  FA,FB:Double;
  Live:Boolean;
  Base:LongInt;             { premier emplacement de sortie }
  Cst:TTensor;              { valeur d'une constante }
  Off,Size:Int64;           { position de la constante dans le .bin }
 End;

Function CountOf(Const D:TIntArr):LongInt;
Var
 I:LongInt;
 P:Int64;
Begin
 P:=1;
 For I:=0 to High(D) do Begin
  If D[I]<0 Then Die('forme dynamique rencontree a l''execution');
  P:=P*D[I];
  If P>$1FFFFFFF Then Die('tenseur trop grand pour ce programme');
 End;
 CountOf:=P;
End;

Function DimsToStr(Const D:TIntArr):AnsiString;
Var
 I:LongInt;
 R:AnsiString;
Begin
 R:='[';
 For I:=0 to High(D) do Begin
  If I>0 Then R:=R+',';
  If D[I]<0 Then R:=R+'?'
            Else R:=R+IStr(D[I]);
 End;
 DimsToStr:=R+']';
End;

Function SameDims(Const A,B:TIntArr):Boolean;
Var
 I:LongInt;
Begin
 SameDims:=False;
 If Length(A)<>Length(B)Then Exit;
 For I:=0 to High(A) do If A[I]<>B[I]Then Exit;
 SameDims:=True;
End;

Function CopyDims(Const D:TIntArr):TIntArr;
Var
 I:LongInt;
Begin
 SetLength(CopyDims,Length(D));
 For I:=0 to High(D) do CopyDims[I]:=D[I];
End;

Function IsIntPrec(P:LongInt):Boolean;
Begin
 IsIntPrec:=(P>=PR_I64)and(P<=PR_I4)and(P<>PR_NF4)or(P=PR_BOOL);
End;

Function PrecFromName(Const S:AnsiString):LongInt;
Var
 I:LongInt;
 L:AnsiString;
Begin
 L:=LoStr(TrimStr(S));
 PrecFromName:=-1;
 For I:=0 to PR_COUNT-1 do
  If(L=ElemName[I])or(L=LoStr(PrecName[I]))Then Begin
   PrecFromName:=I;
   Exit;
  End;
 If L='bool'Then PrecFromName:=PR_BOOL;
End;

Function NewTensor(Prec:LongInt;Const Dims:TIntArr):TTensor;
Var
 N:LongInt;
 R:TTensor;
Begin
 R.Prec:=Prec;
 R.Dims:=CopyDims(Dims);
 SetLength(R.Raw,0);
 N:=CountOf(Dims);
 SetLength(R.D,N);
 NewTensor:=R;
End;

{ Decode N valeurs a partir de l'element Start d'un tampon compact }
Procedure DecodeRaw(P:PByte;Prec,Start,N:LongInt;Dst:PSingle);
Var
 I,K:LongInt;
 B:Byte;
Begin
 Case Prec of
  PR_F32:Move((P+PtrInt(Int64(Start)*4))^,Dst^,Int64(N)*4);
  PR_F16:For I:=0 to N-1 do Dst[I]:=HalfToSingle(PWord(P+PtrInt((Int64(Start)+I)*2))^);
  PR_BF16:For I:=0 to N-1 do
           Dst[I]:=BitsToSingle(LongWord(PWord(P+PtrInt((Int64(Start)+I)*2))^)shl 16);
  PR_F64:For I:=0 to N-1 do Dst[I]:=PDouble(P+PtrInt((Int64(Start)+I)*8))^;
  PR_I64:For I:=0 to N-1 do Dst[I]:=PInt64(P+PtrInt((Int64(Start)+I)*8))^;
  PR_U64:For I:=0 to N-1 do Dst[I]:=PQWord(P+PtrInt((Int64(Start)+I)*8))^;
  PR_I32:For I:=0 to N-1 do Dst[I]:=PLongInt(P+PtrInt((Int64(Start)+I)*4))^;
  PR_U32:For I:=0 to N-1 do Dst[I]:=PLongWord(P+PtrInt((Int64(Start)+I)*4))^;
  PR_I16:For I:=0 to N-1 do Dst[I]:=PSmallInt(P+PtrInt((Int64(Start)+I)*2))^;
  PR_U16:For I:=0 to N-1 do Dst[I]:=PWord(P+PtrInt((Int64(Start)+I)*2))^;
  PR_I8:For I:=0 to N-1 do Dst[I]:=PShortInt(P+PtrInt(Int64(Start)+I))^;
  PR_U8,PR_BOOL:For I:=0 to N-1 do Dst[I]:=(P+PtrInt(Int64(Start)+I))^;
  PR_U4,PR_I4,PR_NF4:
   For I:=0 to N-1 do Begin
    K:=Start+I;
    B:=(P+(K shr 1))^;
    If(K and 1)<>0 Then B:=B shr 4
                   Else B:=B and 15;
    If Prec=PR_U4 Then Dst[I]:=B Else
    If Prec=PR_I4 Then Begin
     If B>=8 Then Dst[I]:=Integer(B)-16
             Else Dst[I]:=B;
    End
     Else Dst[I]:=NF4Table[B];
   End;
 End;
End;

{ Lit N valeurs d'un tenseur (compact ou non) }
Procedure RdElems(Const T:TTensor;Start,N:LongInt;Dst:PSingle);
Begin
 If N<=0 Then Exit;
 If Length(T.Raw)>0 Then DecodeRaw(@T.Raw[0],T.Prec,Start,N,Dst)
                    Else Move(T.D[Start],Dst^,Int64(N)*4);
End;

{ Remplace une constante compacte par ses valeurs en simple precision }
Procedure Mat(Var T:TTensor);
Var
 N:LongInt;
Begin
 If Length(T.Raw)=0 Then Exit;
 N:=CountOf(T.Dims);
 SetLength(T.D,N);
 If N>0 Then DecodeRaw(@T.Raw[0],T.Prec,0,N,@T.D[0]);
 SetLength(T.Raw,0);
End;

{ Valeur d'une precision donnee (arrondi / saturation) }
Function QuantVal(Prec:LongInt;X:Single):Single;
Var
 V:Single;
 T:Int64;
Begin
 Case Prec of
  PR_F16:QuantVal:=RoundHalf(X);
  PR_BF16:QuantVal:=RoundBF16(X);
  PR_BOOL:If X<>0 Then QuantVal:=1 Else QuantVal:=0;
  PR_I64,PR_I32,PR_I16,PR_I8,PR_U64,PR_U32,PR_U16,PR_U8,PR_U4,PR_I4:Begin
   If X<>X Then V:=0 Else V:=Int(X);
   If(V>9.0E18)or(V<-9.0E18)Then V:=0;
   Case Prec of
    PR_I32:If V>2147483647.0 Then V:=2147483647.0 Else If V<-2147483648.0 Then V:=-2147483648.0;
    PR_U64,PR_U32:If V<0 Then V:=0;
    PR_I16,PR_I8,PR_U16,PR_U8,PR_U4,PR_I4:Begin
     { conversion modulo 2^n, comme le plugin CPU d'OpenVINO }
     T:=Trunc(V);
     Case Prec of
      PR_U8:T:=T and 255;
      PR_I8:Begin
       T:=T and 255;
       If T>127 Then T:=T-256;
      End;
      PR_U16:T:=T and 65535;
      PR_I16:Begin
       T:=T and 65535;
       If T>32767 Then T:=T-65536;
      End;
      PR_U4:T:=T and 15;
      PR_I4:Begin
       T:=T and 15;
       If T>7 Then T:=T-16;
      End;
     End;
     V:=T;
    End;
   End;
   QuantVal:=V;
  End;
  Else QuantVal:=X;
 End;
End;

Procedure QuantArr(Prec:LongInt;P:PSingle;N:LongInt);
Var
 I:LongInt;
Begin
 If(Prec=PR_F32)or(Prec=PR_F64)or(Prec=PR_NF4)Then Exit;
 For I:=0 to N-1 do P[I]:=QuantVal(Prec,P[I]);
End;

{ ------------------------------------------------------------------ }
{ Lecture du modele IR (XML)                                          }
{ ------------------------------------------------------------------ }

Var
 Layers:Array of TLayer;
 NL:LongInt;
 NetName:AnsiString;
 IdMap:TIntArr;
 EFL,EFP,ETL,ETP:TIntArr;
 NE:LongInt;

Function FindStr(Const Sub,S:AnsiString;From:LongInt):LongInt;
Var
 I,L,M:LongInt;
Begin
 FindStr:=0;
 L:=Length(S);M:=Length(Sub);
 If M=0 Then Exit;
 I:=From;
 While I<=L-M+1 do Begin
  If S[I]=Sub[1]Then
   If Copy(S,I,M)=Sub Then Begin
    FindStr:=I;
    Exit;
   End;
  Inc(I);
 End;
End;

Function Unescape(Const S:AnsiString):AnsiString;
Begin
 If Pos('&',S)=0 Then Begin
  Unescape:=S;
  Exit;
 End;
 Unescape:=ReplaceAll(ReplaceAll(ReplaceAll(ReplaceAll(ReplaceAll(S,
  '&lt;','<'),'&gt;','>'),'&quot;','"'),'&apos;',''''),'&amp;','&');
End;

{ Valeur d'un attribut (la chaine d'attributs commence par une espace) }
Function GetAttr(Const A,Name:AnsiString;Var Found:Boolean):AnsiString;
Var
 P,Q:LongInt;
 Quote:Char;
Begin
 Found:=False;
 GetAttr:='';
 Quote:='"';
 P:=FindStr(' '+Name+'="',A,1);
 If P=0 Then Begin
  Quote:=#39;
  P:=FindStr(' '+Name+'='+#39,A,1);
 End;
 If P=0 Then Exit;
 P:=P+Length(Name)+3;
 Q:=P;
 While(Q<=Length(A))and(A[Q]<>Quote)do Inc(Q);
 GetAttr:=Unescape(Copy(A,P,Q-P));
 Found:=True;
End;

Function Attr(Const A,Name:AnsiString):AnsiString;
Var
 F:Boolean;
Begin
 Attr:=GetAttr(A,Name,F);
End;

Function AttrBool(Const A,Name:AnsiString;Def:Boolean):Boolean;
Var
 F:Boolean;
 V:AnsiString;
Begin
 V:=LoStr(GetAttr(A,Name,F));
 If Not F Then AttrBool:=Def
          Else AttrBool:=(V='true')or(V='1');
End;

Function AttrInt(Const A,Name:AnsiString;Def:Int64):Int64;
Var
 F:Boolean;
 V:AnsiString;
Begin
 V:=GetAttr(A,Name,F);
 If Not F Then AttrInt:=Def
          Else AttrInt:=ToI(V,Def);
End;

Function AttrFloat(Const A,Name:AnsiString;Def:Double):Double;
Var
 F:Boolean;
 V:AnsiString;
Begin
 V:=GetAttr(A,Name,F);
 If Not F Then AttrFloat:=Def
          Else AttrFloat:=ToF(V,Def);
End;

{ "1,2,?" -> [1,2,-1] }
Function ParseShapeAttr(Const S:AnsiString):TIntArr;
Var
 Parts:TStrArr;
 I:LongInt;
 T:AnsiString;
Begin
 SetLength(ParseShapeAttr,0);
 T:=TrimStr(S);
 If T='' Then Exit;
 Parts:=SplitStr(T,',');
 SetLength(ParseShapeAttr,Length(Parts));
 For I:=0 to High(Parts) do Begin
  T:=TrimStr(Parts[I]);
  If IsInt(T)Then ParseShapeAttr[I]:=ToI(T,-1)
             Else ParseShapeAttr[I]:=-1;
  If ParseShapeAttr[I]<0 Then ParseShapeAttr[I]:=-1;
 End;
End;

Function NewLayer:LongInt;
Begin
 If NL>=Length(Layers)Then Begin
  If NL=0 Then SetLength(Layers,256)
          Else SetLength(Layers,NL*2);
 End;
 Layers[NL].Id:=-1;
 Layers[NL].NIn:=0;
 Layers[NL].Op:=OP_NONE;
 Layers[NL].Live:=False;
 Layers[NL].Attrs:='';
 SetLength(Layers[NL].Outs,0);
 NewLayer:=NL;
 Inc(NL);
End;

Procedure AddEdge(FL,FP,TL,TP:LongInt);
Begin
 If NE>=Length(EFL)Then Begin
  If NE=0 Then Begin
   SetLength(EFL,1024);SetLength(EFP,1024);SetLength(ETL,1024);SetLength(ETP,1024);
  End
   Else
  Begin
   SetLength(EFL,NE*2);SetLength(EFP,NE*2);SetLength(ETL,NE*2);SetLength(ETP,NE*2);
  End;
 End;
 EFL[NE]:=FL;EFP[NE]:=FP;ETL[NE]:=TL;ETP[NE]:=TP;
 Inc(NE);
End;

Procedure ParseXml(Const S:AnsiString);
Var
 P,Len,E,After,LtPos,K:LongInt;
 Q,C:Char;
 Body,Tag,Attrs,Txt:AnsiString;
 Closing,SelfClose:Boolean;
 BodyDepth,CurL,InOut,CurPort,N:LongInt;
Begin
 Len:=Length(S);
 P:=1;CurL:=-1;InOut:=0;CurPort:=-1;BodyDepth:=0;
 While P<=Len do Begin
  While(P<=Len)and(S[P]<>'<')do Inc(P);
  If P>=Len Then Break;
  If Copy(S,P,4)='<!--'Then Begin
   E:=FindStr('-->',S,P+4);
   If E=0 Then Break;
   P:=E+3;
   Continue;
  End;
  If S[P+1] in ['?','!']Then Begin
   While(P<=Len)and(S[P]<>'>')do Inc(P);
   Inc(P);
   Continue;
  End;
  { fin de la balise, en respectant les guillemets }
  E:=P+1;
  Q:=#0;
  While E<=Len do Begin
   C:=S[E];
   If Q<>#0 Then Begin
    If C=Q Then Q:=#0;
   End
    Else
   If(C='"')or(C=#39)Then Q:=C
    Else
   If C='>' Then Break;
   Inc(E);
  End;
  Body:=Copy(S,P+1,E-P-1);
  After:=E+1;
  P:=After;
  If Body='' Then Continue;
  Closing:=Body[1]='/';
  If Closing Then Begin
   Tag:=TrimStr(Copy(Body,2,Length(Body)));
   If Tag='body'Then Begin
    If BodyDepth>0 Then Dec(BodyDepth);
   End
    Else
   If BodyDepth=0 Then Begin
    If Tag='layer'Then Begin
     CurL:=-1;InOut:=0;CurPort:=-1;
    End Else
    If(Tag='input')or(Tag='output')Then Begin
     InOut:=0;CurPort:=-1;
    End Else
    If Tag='port'Then CurPort:=-1;
   End;
   Continue;
  End;
  SelfClose:=Body[Length(Body)]='/';
  If SelfClose Then Body:=Copy(Body,1,Length(Body)-1);
  K:=1;
  While(K<=Length(Body))and Not(Body[K] in [' ',#9,#10,#13])do Inc(K);
  Tag:=Copy(Body,1,K-1);
  Attrs:=' '+ReplaceAll(ReplaceAll(ReplaceAll(Copy(Body,K,Length(Body)),#9,' '),#10,' '),#13,' ');
  If Tag='body'Then Begin
   If Not SelfClose Then Inc(BodyDepth);
   Continue;
  End;
  If BodyDepth>0 Then Continue;
  If Tag='net'Then NetName:=Attr(Attrs,'name') Else
  If Tag='layer'Then Begin
   CurL:=NewLayer;
   Layers[CurL].Id:=AttrInt(Attrs,'id',-1);
   Layers[CurL].Name:=Attr(Attrs,'name');
   Layers[CurL].Typ:=Attr(Attrs,'type');
   Layers[CurL].Ver:=Attr(Attrs,'version');
   InOut:=0;CurPort:=-1;
  End Else
  If Tag='data'Then Begin
   If CurL>=0 Then Layers[CurL].Attrs:=Attrs;
  End Else
  If Tag='input'Then InOut:=1 Else
  If Tag='output'Then InOut:=2 Else
  If Tag='port'Then Begin
   CurPort:=-1;
   If(CurL>=0)and(InOut=2)Then Begin
    N:=Length(Layers[CurL].Outs);
    SetLength(Layers[CurL].Outs,N+1);
    Layers[CurL].Outs[N].Id:=AttrInt(Attrs,'id',N);
    Layers[CurL].Outs[N].Prec:=PrecFromName(Attr(Attrs,'precision'));
    Layers[CurL].Outs[N].Names:=Attr(Attrs,'names');
    SetLength(Layers[CurL].Outs[N].Dims,0);
    If Not SelfClose Then CurPort:=N;
   End;
  End Else
  If Tag='dim'Then Begin
   If(CurL>=0)and(InOut=2)and(CurPort>=0)and Not SelfClose Then Begin
    LtPos:=After;
    While(LtPos<=Len)and(S[LtPos]<>'<')do Inc(LtPos);
    Txt:=TrimStr(Copy(S,After,LtPos-After));
    N:=Length(Layers[CurL].Outs[CurPort].Dims);
    SetLength(Layers[CurL].Outs[CurPort].Dims,N+1);
    If IsInt(Txt)and(ToI(Txt,-1)>=0)Then Layers[CurL].Outs[CurPort].Dims[N]:=ToI(Txt,-1)
                                     Else Layers[CurL].Outs[CurPort].Dims[N]:=-1;
   End;
  End Else
  If Tag='edge'Then
   AddEdge(AttrInt(Attrs,'from-layer',-1),AttrInt(Attrs,'from-port',-1),
           AttrInt(Attrs,'to-layer',-1),AttrInt(Attrs,'to-port',-1));
 End;
End;

Function OpFromType(T:AnsiString):LongInt;
Begin
 OpFromType:=OP_NONE;
 T:=LoStr(T);
 If T='parameter'Then OpFromType:=OP_PARAM Else
 If(T='const')or(T='constant')Then OpFromType:=OP_CONST Else
 If T='result'Then OpFromType:=OP_RESULT Else
 If T='convert'Then OpFromType:=OP_CONVERT Else
 If T='add'Then OpFromType:=OP_ADD Else
 If T='subtract'Then OpFromType:=OP_SUB Else
 If T='multiply'Then OpFromType:=OP_MUL Else
 If T='divide'Then OpFromType:=OP_DIV Else
 If T='power'Then OpFromType:=OP_POW Else
 If T='maximum'Then OpFromType:=OP_MAX Else
 If T='minimum'Then OpFromType:=OP_MIN Else
 If(T='mod')or(T='floormod')Then OpFromType:=OP_MOD Else
 If T='squareddifference'Then OpFromType:=OP_SQDIFF Else
 If T='equal'Then OpFromType:=OP_EQ Else
 If T='notequal'Then OpFromType:=OP_NE Else
 If T='less'Then OpFromType:=OP_LT Else
 If T='lessequal'Then OpFromType:=OP_LE Else
 If T='greater'Then OpFromType:=OP_GT Else
 If T='greaterequal'Then OpFromType:=OP_GE Else
 If T='logicaland'Then OpFromType:=OP_AND Else
 If T='logicalor'Then OpFromType:=OP_OR Else
 If T='logicalnot'Then OpFromType:=OP_NOT Else
 If T='abs'Then OpFromType:=OP_ABS Else
 If T='ceiling'Then OpFromType:=OP_CEIL Else
 If T='cos'Then OpFromType:=OP_COS Else
 If T='erf'Then OpFromType:=OP_ERF Else
 If T='exp'Then OpFromType:=OP_EXP Else
 If T='floor'Then OpFromType:=OP_FLOOR Else
 If T='gelu'Then OpFromType:=OP_GELU Else
 If T='hsigmoid'Then OpFromType:=OP_HSIG Else
 If T='hswish'Then OpFromType:=OP_HSWISH Else
 If T='log'Then OpFromType:=OP_LOG Else
 If T='mish'Then OpFromType:=OP_MISH Else
 If T='negative'Then OpFromType:=OP_NEG Else
 If T='relu'Then OpFromType:=OP_RELU Else
 If T='sigmoid'Then OpFromType:=OP_SIGMOID Else
 If T='sign'Then OpFromType:=OP_SIGN Else
 If T='sin'Then OpFromType:=OP_SIN Else
 If T='sqrt'Then OpFromType:=OP_SQRT Else
 If T='swish'Then OpFromType:=OP_SWISH Else
 If T='tan'Then OpFromType:=OP_TAN Else
 If T='tanh'Then OpFromType:=OP_TANH Else
 If T='clamp'Then OpFromType:=OP_CLAMP Else
 If T='softmax'Then OpFromType:=OP_SOFTMAX Else
 If T='select'Then OpFromType:=OP_SELECT Else
 If T='shapeof'Then OpFromType:=OP_SHAPEOF Else
 If T='gather'Then OpFromType:=OP_GATHER Else
 If T='range'Then OpFromType:=OP_RANGE Else
 If T='reshape'Then OpFromType:=OP_RESHAPE Else
 If T='squeeze'Then OpFromType:=OP_SQUEEZE Else
 If T='unsqueeze'Then OpFromType:=OP_UNSQUEEZE Else
 If T='transpose'Then OpFromType:=OP_TRANSPOSE Else
 If T='matmul'Then OpFromType:=OP_MATMUL Else
 If T='concat'Then OpFromType:=OP_CONCAT Else
 If T='split'Then OpFromType:=OP_SPLIT Else
 If T='variadicsplit'Then OpFromType:=OP_VSPLIT Else
 If T='broadcast'Then OpFromType:=OP_BROADCAST Else
 If T='reducemean'Then OpFromType:=OP_RMEAN Else
 If T='reducesum'Then OpFromType:=OP_RSUM Else
 If T='reducemax'Then OpFromType:=OP_RMAX Else
 If T='reducemin'Then OpFromType:=OP_RMIN Else
 If T='reduceprod'Then OpFromType:=OP_RPROD Else
 If T='scaleddotproductattention'Then OpFromType:=OP_SDPA Else
 If T='readvalue'Then OpFromType:=OP_READVALUE Else
 If T='assign'Then OpFromType:=OP_ASSIGN;
End;

{ Types de couche affiches par les compteurs ("layerType") }
Function IsMetaOp(Op:LongInt):Boolean;
Begin
 IsMetaOp:=(Op=OP_PARAM)or(Op=OP_CONST)or(Op=OP_RESULT);
End;

Procedure SetOpAttrs(Var L:TLayer);
Var
 F:Boolean;
 M:AnsiString;
Begin
 If(L.Op=OP_PARAM)or(L.Op=OP_RESULT)Then Exit;
 L.IA:=0;L.IB:=0;L.FA:=0;L.FB:=0;
 Case L.Op of
  OP_CONVERT:Begin
   L.IA:=PrecFromName(Attr(L.Attrs,'destination_type'));
   If L.IA<0 Then Die('type de destination inconnu pour '+L.Name);
  End;
  OP_CONCAT:L.IA:=AttrInt(L.Attrs,'axis',0);
  OP_MATMUL:Begin
   L.IA:=Ord(AttrBool(L.Attrs,'transpose_a',False));
   L.IB:=Ord(AttrBool(L.Attrs,'transpose_b',False));
  End;
  OP_GATHER:L.IA:=AttrInt(L.Attrs,'batch_dims',0);
  OP_RESHAPE:L.IA:=Ord(AttrBool(L.Attrs,'special_zero',False));
  OP_RMEAN,OP_RSUM,OP_RMAX,OP_RMIN,OP_RPROD:
   L.IA:=Ord(AttrBool(L.Attrs,'keep_dims',False));
  OP_RANGE,OP_SHAPEOF:Begin
   M:=GetAttr(L.Attrs,'output_type',F);
   If F Then L.IA:=PrecFromName(M)
        Else L.IA:=PR_I64;
   If L.IA<0 Then L.IA:=PR_I64;
  End;
  OP_BROADCAST:Begin
   M:=LoStr(Attr(L.Attrs,'mode'));
   If M='bidirectional'Then L.IA:=1 Else
   If M='explicit'Then L.IA:=2
                  Else L.IA:=0;
  End;
  OP_SDPA:L.IA:=Ord(AttrBool(L.Attrs,'causal',False));
  OP_SPLIT:L.IA:=AttrInt(L.Attrs,'num_splits',1);
  OP_SOFTMAX:L.IA:=AttrInt(L.Attrs,'axis',1);
  OP_GELU:L.IA:=Ord(UpStr(Attr(L.Attrs,'approximation_mode'))='TANH');
  OP_CLAMP:Begin
   L.FA:=AttrFloat(L.Attrs,'min',-3.4E38);
   L.FB:=AttrFloat(L.Attrs,'max',3.4E38);
  End;
 End;
End;

{ ------------------------------------------------------------------ }
{ Compilation du modele                                               }
{ ------------------------------------------------------------------ }

Var
 Order:TIntArr;          { couches utiles, dans l'ordre d'execution }
 NOrder:LongInt;
 NSlots:LongInt;
 RefInit:TIntArr;        { nombre de consommateurs par emplacement }
 InLayers:TIntArr;       { couches Parameter (entrees du modele) }
 OutLayers:TIntArr;      { couches Result (sorties du modele) }
 BinPath:AnsiString;
 StateCount:LongInt;     { nombre de ReadValue (modele "stateful") }

Procedure ResolveGraph;
Var
 I,J,Li,Fi,K,MaxId:LongInt;
Begin
 MaxId:=0;
 For I:=0 to NL-1 do
  If Layers[I].Id>MaxId Then MaxId:=Layers[I].Id;
 SetLength(IdMap,MaxId+1);
 For I:=0 to MaxId do IdMap[I]:=-1;
 For I:=0 to NL-1 do Begin
  If Layers[I].Id<0 Then Die('couche sans identifiant dans le modele');
  IdMap[Layers[I].Id]:=I;
 End;
 For I:=0 to NE-1 do Begin
  If(ETL[I]<0)or(ETL[I]>MaxId)or(IdMap[ETL[I]]<0)Then Die('arete vers une couche inconnue : '+IStr(ETL[I]));
  Li:=IdMap[ETL[I]];
  If ETP[I]+1>Layers[Li].NIn Then Layers[Li].NIn:=ETP[I]+1;
 End;
 For I:=0 to NL-1 do Begin
  SetLength(Layers[I].SrcL,Layers[I].NIn);
  SetLength(Layers[I].SrcP,Layers[I].NIn);
  For J:=0 to Layers[I].NIn-1 do Layers[I].SrcL[J]:=-1;
 End;
 For I:=0 to NE-1 do Begin
  Li:=IdMap[ETL[I]];
  If(EFL[I]<0)or(EFL[I]>MaxId)or(IdMap[EFL[I]]<0)Then Die('arete depuis une couche inconnue : '+IStr(EFL[I]));
  Fi:=IdMap[EFL[I]];
  K:=-1;
  For J:=0 to High(Layers[Fi].Outs) do
   If Layers[Fi].Outs[J].Id=EFP[I]Then K:=J;
  If K<0 Then Die('port de sortie '+IStr(EFP[I])+' introuvable sur '+Layers[Fi].Name);
  Layers[Li].SrcL[ETP[I]]:=Fi;
  Layers[Li].SrcP[ETP[I]]:=K;
 End;
 For I:=0 to NL-1 do
  For J:=0 to Layers[I].NIn-1 do
   If Layers[I].SrcL[J]<0 Then
    Die('entree '+IStr(J)+' non connectee sur '+Layers[I].Name);
End;

{ Resout les types d'operation et repere les entrees / sorties du modele }
Procedure FindModelIO;
Var
 I:LongInt;
Begin
 For I:=0 to NL-1 do Layers[I].Op:=OpFromType(Layers[I].Typ);
 SetLength(InLayers,0);SetLength(OutLayers,0);
 StateCount:=0;
 For I:=0 to NL-1 do Begin
  If Layers[I].Op=OP_PARAM Then Begin
   SetLength(InLayers,Length(InLayers)+1);
   InLayers[High(InLayers)]:=I;
   Layers[I].IA:=High(InLayers);
  End;
  If Layers[I].Op=OP_RESULT Then Begin
   SetLength(OutLayers,Length(OutLayers)+1);
   OutLayers[High(OutLayers)]:=I;
   Layers[I].IA:=High(OutLayers);
  End;
  If Layers[I].Op=OP_READVALUE Then Inc(StateCount);
 End;
End;

{ Fusion "decompression des poids + MatMul" : le MatMul lit directement les
  poids compresses (Const) et leurs echelles / zeros, sans materialiser la
  matrice decompressee. Motifs reconnus pour la 2e entree (transpose_b) :
    Const
    Convert(Const)
    [Convert]( [Reshape]( Multiply( [Convert](ConstQ) , ConstEchelle ) ) )
    [Convert]( [Reshape]( Multiply( Subtract([Convert](ConstQ),[Convert](ConstZero)),
                                    ConstEchelle ) ) )
  Le MatMul fusionne a les entrees [X, Q, echelle, zero] (FA<>0). }
Function StripConvert(L:LongInt):LongInt;
Begin
 StripConvert:=L;
 If(Layers[L].Op=OP_CONVERT)and(Layers[L].NIn=1)Then StripConvert:=Layers[L].SrcL[0];
End;

Procedure TryFuseMatMul(I:LongInt);
Var
 Cur,Q,Sc,Zp,A,B,P:LongInt;
 N,K,G,NO:LongInt;
 Dm:TIntArr;
 HasSc,HasZp:Boolean;
Begin
 If(Layers[I].Op<>OP_MATMUL)or(Layers[I].NIn<>2)Then Exit;
 If(Layers[I].IA<>0)or(Layers[I].IB=0)Then Exit;
 P:=Layers[I].SrcL[1];
 If Layers[I].SrcP[1]<>0 Then Exit;
 If(Length(Layers[P].Outs)<1)or(Length(Layers[P].Outs[0].Dims)<>2)Then Exit;
 Dm:=Layers[P].Outs[0].Dims;
 If(Dm[0]<=0)or(Dm[1]<=0)Then Exit;
 N:=Dm[0];K:=Dm[1];
 Cur:=StripConvert(P);
 Q:=-1;Sc:=-1;Zp:=-1;
 If Layers[Cur].Op=OP_RESHAPE Then Cur:=Layers[Cur].SrcL[0];
 If Layers[Cur].Op=OP_CONST Then Q:=Cur
 Else If Layers[Cur].Op=OP_MUL Then Begin
  A:=Layers[Cur].SrcL[0];B:=Layers[Cur].SrcL[1];
  If Layers[B].Op=OP_CONST Then Sc:=B Else
  If Layers[A].Op=OP_CONST Then Begin
   Sc:=A;A:=B;
  End
   Else Exit;
  If Layers[A].Op=OP_SUB Then Begin
   B:=StripConvert(Layers[A].SrcL[1]);
   A:=StripConvert(Layers[A].SrcL[0]);
   If(Layers[A].Op<>OP_CONST)or(Layers[B].Op<>OP_CONST)Then Exit;
   Q:=A;Zp:=B;
  End
   Else
  Begin
   A:=StripConvert(A);
   If Layers[A].Op<>OP_CONST Then Exit;
   Q:=A;
  End;
 End
  Else Exit;
 If Q<0 Then Exit;
 If CountOf(Layers[Q].Cst.Dims)<>N*K Then Exit;
 If Length(Layers[Q].Cst.Dims)<2 Then Exit;
 If Layers[Q].Cst.Dims[0]<>N Then Exit;
 G:=1;
 If Sc>=0 Then Begin
  NO:=CountOf(Layers[Sc].Cst.Dims);
  If(NO<=0)or((NO mod N)<>0)Then Exit;
  G:=NO div N;
  If(G<1)or((K mod G)<>0)Then Exit;
  If Zp>=0 Then
   If CountOf(Layers[Zp].Cst.Dims)<>NO Then Exit;
 End;
 HasSc:=Sc>=0;HasZp:=Zp>=0;
 NO:=2;
 If HasSc Then Inc(NO);
 If HasZp Then Inc(NO);
 SetLength(Layers[I].SrcL,NO);
 SetLength(Layers[I].SrcP,NO);
 Layers[I].SrcL[1]:=Q;Layers[I].SrcP[1]:=0;
 NO:=2;
 If HasSc Then Begin
  Layers[I].SrcL[NO]:=Sc;Layers[I].SrcP[NO]:=0;
  Inc(NO);
 End;
 If HasZp Then Begin
  Layers[I].SrcL[NO]:=Zp;Layers[I].SrcP[NO]:=0;
  Inc(NO);
 End;
 Layers[I].NIn:=NO;
 Layers[I].FA:=1;
 Layers[I].FB:=Ord(HasSc)+2*Ord(HasZp);
End;

{ Verifie les operations, calcule l'ordre d'execution et charge les constantes }
Procedure CompileModel;
Var
 I,J,K,Cur,NIns,NOuts,SlotN:LongInt;
 Stack,Deg,Queue,UHead,UNext,UCons:TIntArr;
 SP,QH,QT:LongInt;
 Bad:AnsiString;
 BinF:File;
 BinSize:Int64;
 Need:Int64;
 BinOpen:Boolean;
 Shp:AnsiString;
 F:Boolean;
 CP:LongInt;
Begin
 Bad:='';
 For I:=0 to NL-1 do Begin
  If Layers[I].Op=OP_NONE Then Begin
   If Pos(' '+Layers[I].Typ+' ',' '+Bad+' ')=0 Then Bad:=Bad+' '+Layers[I].Typ;
  End
   Else SetOpAttrs(Layers[I]);
 End;
 If Bad<>'' Then
  Die('operation(s) non prise(s) en charge :'+Bad+'. Voir l''en-tete de BENCHMARK_APP.PAS pour la liste des operations.');
 { constantes : type, forme, position dans le .bin }
 For I:=0 to NL-1 do
  If Layers[I].Op=OP_CONST Then Begin
   Shp:=Attr(Layers[I].Attrs,'shape');
   Layers[I].Cst.Dims:=ParseShapeAttr(Shp);
   Shp:=GetAttr(Layers[I].Attrs,'element_type',F);
   CP:=PrecFromName(Shp);
   If CP<0 Then
    If Length(Layers[I].Outs)>0 Then CP:=Layers[I].Outs[0].Prec;
   If CP<0 Then Die('type d''element inconnu pour la constante '+Layers[I].Name);
   Layers[I].Cst.Prec:=CP;
   Layers[I].Off:=AttrInt(Layers[I].Attrs,'offset',0);
   Layers[I].Size:=AttrInt(Layers[I].Attrs,'size',0);
   SetLength(Layers[I].Cst.D,0);
   SetLength(Layers[I].Cst.Raw,0);
   K:=CountOf(Layers[I].Cst.Dims);
   Need:=(Int64(K)*PrecBits[CP]+7)div 8;
   If Layers[I].Size<Need Then
    Die('taille de la constante '+Layers[I].Name+' incoherente ('+IStr(Layers[I].Size)+
        ' octets pour '+IStr(Need)+' attendus)');
   If Layers[I].Size>$7FFFFFFF Then Die('constante trop grande : '+Layers[I].Name);
  End;
 { fusion decompression des poids + MatMul }
 For I:=0 to NL-1 do TryFuseMatMul(I);
 { couches utiles : celles dont depend un Result ou un Assign }
 SetLength(Stack,NL+1);
 SP:=0;
 For I:=0 to NL-1 do
  If(Layers[I].Op=OP_RESULT)or(Layers[I].Op=OP_ASSIGN)or(Layers[I].Op=OP_PARAM)Then Begin
   Layers[I].Live:=True;
   Stack[SP]:=I;Inc(SP);
  End;
 While SP>0 do Begin
  Dec(SP);
  Cur:=Stack[SP];
  For J:=0 to Layers[Cur].NIn-1 do Begin
   K:=Layers[Cur].SrcL[J];
   If Not Layers[K].Live Then Begin
    Layers[K].Live:=True;
    Stack[SP]:=K;Inc(SP);
   End;
  End;
 End;
 { ordre topologique (Kahn), avec listes de consommateurs }
 SetLength(Deg,NL);
 SetLength(UHead,NL);
 For I:=0 to NL-1 do Begin
  Deg[I]:=0;UHead[I]:=-1;
 End;
 NIns:=0;
 For I:=0 to NL-1 do
  If Layers[I].Live Then Inc(NIns,Layers[I].NIn);
 SetLength(UNext,NIns+1);
 SetLength(UCons,NIns+1);
 NIns:=0;
 For I:=0 to NL-1 do
  If Layers[I].Live Then Begin
   Deg[I]:=Layers[I].NIn;
   For J:=0 to Layers[I].NIn-1 do Begin
    K:=Layers[I].SrcL[J];
    UCons[NIns]:=I;
    UNext[NIns]:=UHead[K];
    UHead[K]:=NIns;
    Inc(NIns);
   End;
  End;
 SetLength(Queue,NL);
 QH:=0;QT:=0;
 For I:=0 to NL-1 do
  If Layers[I].Live and(Deg[I]=0)Then Begin
   Queue[QT]:=I;Inc(QT);
  End;
 SetLength(Order,NL);
 NOrder:=0;
 While QH<QT do Begin
  Cur:=Queue[QH];Inc(QH);
  Order[NOrder]:=Cur;Inc(NOrder);
  K:=UHead[Cur];
  While K>=0 do Begin
   I:=UCons[K];
   Dec(Deg[I]);
   If Deg[I]=0 Then Begin
    Queue[QT]:=I;Inc(QT);
   End;
   K:=UNext[K];
  End;
 End;
 NIns:=0;
 For I:=0 to NL-1 do If Layers[I].Live Then Inc(NIns);
 If NOrder<>NIns Then Die('le graphe du modele contient un cycle');
 { emplacements de sortie et nombres de references }
 NSlots:=0;
 For I:=0 to NL-1 do
  If Layers[I].Live Then Begin
   Layers[I].Base:=NSlots;
   NOuts:=Length(Layers[I].Outs);
   If NOuts<1 Then NOuts:=1;
   Inc(NSlots,NOuts);
  End;
 SetLength(RefInit,NSlots);
 For I:=0 to NSlots-1 do RefInit[I]:=0;
 For I:=0 to NL-1 do
  If Layers[I].Live Then
   For J:=0 to Layers[I].NIn-1 do
    Inc(RefInit[Layers[Layers[I].SrcL[J]].Base+Layers[I].SrcP[J]]);
 { chargement des constantes utiles }
 BinOpen:=False;
 BinSize:=0;
 For I:=0 to NL-1 do
  If Layers[I].Live and(Layers[I].Op=OP_CONST)Then Begin
   K:=CountOf(Layers[I].Cst.Dims);
   Need:=(Int64(K)*PrecBits[Layers[I].Cst.Prec]+7)div 8;
   If Need>0 Then Begin
    If Not BinOpen Then Begin
     Assign(BinF,BinPath);
     {$I-}Reset(BinF,1);{$I+}
     If IOResult<>0 Then Die('impossible d''ouvrir le fichier des poids '+BinPath);
     BinSize:=FileSize(BinF);
     BinOpen:=True;
    End;
    If Layers[I].Off+Need>BinSize Then
     Die('fichier des poids tronque : '+BinPath);
    SetLength(Layers[I].Cst.Raw,Need);
    {$I-}Seek(BinF,Layers[I].Off);{$I+}
    If IOResult<>0 Then Die('erreur de lecture de '+BinPath);
    {$I-}BlockRead(BinF,Layers[I].Cst.Raw[0],Need);{$I+}
    If IOResult<>0 Then Die('erreur de lecture de '+BinPath);
   End;
  End;
 If BinOpen Then Begin
  {$I-}Close(BinF);{$I+}
  If IOResult<>0 Then ;
 End;
End;

{ ------------------------------------------------------------------ }
{ Parallelisme (sous Windows seulement)                              }
{ ------------------------------------------------------------------ }

Type
 TRangeProc = Procedure(Ctx:Pointer;S,E:Int64);

 TChunk = Record
  Fn:TRangeProc;
  Ctx:Pointer;
  S,E:Int64;
  Done:LongInt;
 End;
 PChunk = ^TChunk;

{$IFDEF THREADS}
Function ChunkMain(P:Pointer):PtrInt;
Begin
 PChunk(P)^.Fn(PChunk(P)^.Ctx,PChunk(P)^.S,PChunk(P)^.E);
 InterlockedIncrement(PChunk(P)^.Done);
 ChunkMain:=0;
End;
{$ENDIF}

{ Execute Fn sur [0,Total[ en le decoupant sur Threads fils si le travail
  (Work, nombre d'operations) le justifie }
Procedure ParFor(Threads:LongInt;Total,Work:Int64;Fn:TRangeProc;Ctx:Pointer);
{$IFDEF THREADS}
Var
 T,I:LongInt;
 Chunks:Array of TChunk;
 Hs:Array of TThreadID;
 Per:Int64;
Begin
 T:=Threads;
 If T>Total Then T:=Total;
 If(T>1)and(Work>=ParThreshold)Then Begin
  SetLength(Chunks,T);
  SetLength(Hs,T);
  Per:=(Total+T-1)div T;
  For I:=0 to T-1 do Begin
   Chunks[I].Fn:=Fn;
   Chunks[I].Ctx:=Ctx;
   Chunks[I].S:=I*Per;
   Chunks[I].E:=(I+1)*Per;
   If Chunks[I].E>Total Then Chunks[I].E:=Total;
   If Chunks[I].S>Total Then Chunks[I].S:=Total;
   Chunks[I].Done:=0;
  End;
  For I:=1 to T-1 do Hs[I]:=BeginThread(@ChunkMain,@Chunks[I]);
  Fn(Ctx,Chunks[0].S,Chunks[0].E);
  For I:=1 to T-1 do Begin
   WaitForThreadTerminate(Hs[I],0);
   While InterlockedExchangeAdd(Chunks[I].Done,0)=0 do ;
   CloseThread(Hs[I]);
  End;
  Exit;
 End;
 Fn(Ctx,0,Total);
End;
{$ELSE}
Begin
 Fn(Ctx,0,Total);
End;
{$ENDIF}

{ ------------------------------------------------------------------ }
{ Aides pour les formes                                               }
{ ------------------------------------------------------------------ }

Function MakeDims(Const A:Array of LongInt):TIntArr;
Var
 I:LongInt;
Begin
 SetLength(MakeDims,Length(A));
 For I:=0 to High(A) do MakeDims[I]:=A[I];
End;

{ Valeurs d'un tenseur d'entiers (formes, axes...) }
Function TensorInts(Const T0:TTensor):TIntArr;
Var
 T:TTensor;
 I:LongInt;
Begin
 T:=T0;
 Mat(T);
 SetLength(TensorInts,Length(T.D));
 For I:=0 to High(T.D) do TensorInts[I]:=Round(T.D[I]);
End;

Function HeadDims(Const D:TIntArr;N:LongInt):TIntArr;
Var
 I:LongInt;
Begin
 SetLength(HeadDims,N);
 For I:=0 to N-1 do HeadDims[I]:=D[I];
End;

Function NormAxis(Ax,Rank:LongInt):LongInt;
Begin
 If Ax<0 Then Ax:=Ax+Rank;
 If(Ax<0)or(Ax>=Rank)Then Die('axe '+IStr(Ax)+' hors limites pour un tenseur de rang '+IStr(Rank));
 NormAxis:=Ax;
End;

Function ProdRange(Const D:TIntArr;A,B:LongInt):LongInt;
Var
 I:LongInt;
 P:Int64;
Begin
 P:=1;
 For I:=A to B-1 do P:=P*D[I];
 ProdRange:=P;
End;

{ Dimensions de diffusion (style numpy) }
Function BCastDims(Const A,B:TIntArr):TIntArr;
Var
 R,I,NA,NB,DA,DB:LongInt;
Begin
 NA:=Length(A);NB:=Length(B);
 If NA>NB Then R:=NA Else R:=NB;
 SetLength(BCastDims,R);
 For I:=0 to R-1 do Begin
  If NA-R+I>=0 Then DA:=A[NA-R+I] Else DA:=1;
  If NB-R+I>=0 Then DB:=B[NB-R+I] Else DB:=1;
  If DA=DB Then BCastDims[I]:=DA Else
  If DA=1 Then BCastDims[I]:=DB Else
  If DB=1 Then BCastDims[I]:=DA
  Else Die('formes incompatibles pour la diffusion : '+DimsToStr(A)+' et '+DimsToStr(B));
 End;
End;

{ Pas (en elements) d'un tenseur de forme Dims diffuse vers Out }
Function BStrides(Const Dims,Out:TIntArr):TIntArr;
Var
 R,Off,I:LongInt;
 St:TIntArr;
 P:LongInt;
Begin
 R:=Length(Out);
 Off:=R-Length(Dims);
 SetLength(St,Length(Dims));
 P:=1;
 For I:=High(Dims) downto 0 do Begin
  St[I]:=P;
  P:=P*Dims[I];
 End;
 SetLength(BStrides,R);
 For I:=0 to R-1 do
  If(I<Off)or(Dims[I-Off]=1)Then BStrides[I]:=0
                            Else BStrides[I]:=St[I-Off];
End;

{ Copie R[i] = A[sum(idx*AStr)] pour tous les indices de OD }
Procedure StridedCopy(Const A:TTensor;Const OD,AStr:TIntArr;Var R:TTensor);
Var
 N,Rk,K,Inner,I,J:LongInt;
 Idx:TIntArr;
 Off,SI:LongInt;
 Src,Dst:PSingle;
Begin
 N:=CountOf(OD);
 If N=0 Then Exit;
 Rk:=Length(OD);
 Src:=@A.D[0];
 Dst:=@R.D[0];
 If Rk=0 Then Begin
  Dst[0]:=Src[0];
  Exit;
 End;
 Inner:=OD[Rk-1];
 SI:=AStr[Rk-1];
 SetLength(Idx,Rk);
 For K:=0 to Rk-1 do Idx[K]:=0;
 Off:=0;
 J:=0;
 While J<N do Begin
  If SI=1 Then Move(Src[Off],Dst[J],Int64(Inner)*4) Else
  If SI=0 Then Begin
   For I:=0 to Inner-1 do Dst[J+I]:=Src[Off];
  End
   Else
  Begin
   For I:=0 to Inner-1 do Dst[J+I]:=Src[Off+I*SI];
  End;
  Inc(J,Inner);
  K:=Rk-2;
  While K>=0 do Begin
   Inc(Idx[K]);
   Off:=Off+AStr[K];
   If Idx[K]<OD[K]Then Break;
   Off:=Off-AStr[K]*OD[K];
   Idx[K]:=0;
   Dec(K);
  End;
  If K<0 Then Break;
 End;
End;

{ ------------------------------------------------------------------ }
{ Operations element par element                                      }
{ ------------------------------------------------------------------ }

Function ErfF(X:Double):Double;
Var
 T,Y:Double;
Begin
 { Abramowitz et Stegun 7.1.26 }
 T:=1.0/(1.0+0.3275911*Abs(X));
 Y:=1.0-(((((1.061405429*T-1.453152027)*T)+1.421413741)*T-0.284496736)*T+0.254829592)*T*Exp(-X*X);
 If X<0 Then ErfF:=-Y
        Else ErfF:=Y;
End;

Function TanhF(X:Double):Double;
Var
 E:Double;
Begin
 If X>20 Then TanhF:=1 Else
 If X<-20 Then TanhF:=-1
 Else Begin
  E:=Exp(2*X);
  TanhF:=(E-1)/(E+1);
 End;
End;

Function SigmoidF(X:Double):Double;
Begin
 If X>40 Then SigmoidF:=1 Else
 If X<-40 Then SigmoidF:=0
 Else SigmoidF:=1.0/(1.0+Exp(-X));
End;

Function FloorF(X:Double):Double;
Begin
 If(X<0)and(Frac(X)<>0)Then FloorF:=Int(X)-1
                       Else FloorF:=Int(X);
End;

Function PowF(X,Y:Double):Double;
Var
 R:Double;
Begin
 If Y=0 Then Begin
  PowF:=1;
  Exit;
 End;
 If X=0 Then Begin
  If Y>0 Then PowF:=0
         Else PowF:=3.4E38;
  Exit;
 End;
 R:=Exp(Y*Ln(Abs(X)));
 If(X<0)and(Frac(Y/2)<>0)Then R:=-R;
 PowF:=R;
End;

Function F2(Op:LongInt;X,Y:Single):Single;
Begin
 Case Op of
  OP_ADD:F2:=X+Y;
  OP_SUB:F2:=X-Y;
  OP_MUL:F2:=X*Y;
  OP_DIV:If Y=0 Then Begin
          If X=0 Then F2:=0
          Else If X>0 Then F2:=3.4E38
          Else F2:=-3.4E38;
         End
          Else F2:=X/Y;
  OP_POW:F2:=PowF(X,Y);
  OP_MAX:If X>Y Then F2:=X Else F2:=Y;
  OP_MIN:If X<Y Then F2:=X Else F2:=Y;
  OP_MOD:If Y=0 Then F2:=0
                Else F2:=X-Y*Int(X/Y);
  OP_SQDIFF:F2:=(X-Y)*(X-Y);
  OP_EQ:If X=Y Then F2:=1 Else F2:=0;
  OP_NE:If X<>Y Then F2:=1 Else F2:=0;
  OP_LT:If X<Y Then F2:=1 Else F2:=0;
  OP_LE:If X<=Y Then F2:=1 Else F2:=0;
  OP_GT:If X>Y Then F2:=1 Else F2:=0;
  OP_GE:If X>=Y Then F2:=1 Else F2:=0;
  OP_AND:If(X<>0)and(Y<>0)Then F2:=1 Else F2:=0;
  OP_OR:If(X<>0)or(Y<>0)Then F2:=1 Else F2:=0;
  Else F2:=0;
 End;
End;

Function F1(Op:LongInt;X:Single;FA,FB:Double;IA:LongInt):Single;
Var
 V:Double;
Begin
 Case Op of
  OP_NOT:If X=0 Then F1:=1 Else F1:=0;
  OP_ABS:F1:=Abs(X);
  OP_CEIL:F1:=-FloorF(-X);
  OP_COS:F1:=Cos(X);
  OP_ERF:F1:=ErfF(X);
  OP_EXP:If X>88 Then F1:=3.4E38 Else F1:=Exp(X);
  OP_FLOOR:F1:=FloorF(X);
  OP_GELU:If IA=1 Then
           F1:=0.5*X*(1+TanhF(0.7978845608028654*(X+0.044715*X*X*X)))
          Else
           F1:=0.5*X*(1+ErfF(X*0.7071067811865476));
  OP_HSIG:Begin
   V:=(X+3)/6;
   If V<0 Then V:=0 Else If V>1 Then V:=1;
   F1:=V;
  End;
  OP_HSWISH:Begin
   V:=X+3;
   If V<0 Then V:=0 Else If V>6 Then V:=6;
   F1:=X*V/6;
  End;
  OP_LOG:If X<=0 Then Begin
          If X=0 Then F1:=-3.4E38 Else F1:=0;
         End
          Else F1:=Ln(X);
  OP_MISH:Begin
   If X>20 Then V:=X Else V:=Ln(1+Exp(X));
   F1:=X*TanhF(V);
  End;
  OP_NEG:F1:=-X;
  OP_RELU:If X>0 Then F1:=X Else F1:=0;
  OP_SIGMOID:F1:=SigmoidF(X);
  OP_SIGN:If X>0 Then F1:=1 Else If X<0 Then F1:=-1 Else F1:=0;
  OP_SIN:F1:=Sin(X);
  OP_SQRT:If X<0 Then F1:=0 Else F1:=Sqrt(X);
  OP_SWISH:F1:=X*SigmoidF(X);
  OP_TAN:F1:=Sin(X)/Cos(X);
  OP_TANH:F1:=TanhF(X);
  OP_CLAMP:If X<FA Then F1:=FA Else If X>FB Then F1:=FB Else F1:=X;
  Else F1:=X;
 End;
End;

Procedure OpUnary(Op:LongInt;Const A0:TTensor;Var R:TTensor;FA,FB:Double;IA:LongInt;
                  Beta:Single);
Var
 A:TTensor;
 I,N:LongInt;
 Pr:LongInt;
Begin
 A:=A0;
 Mat(A);
 N:=Length(A.D);
 Pr:=A.Prec;
 If Op=OP_NOT Then Pr:=PR_BOOL;
 R:=NewTensor(Pr,A.Dims);
 If Op=OP_SWISH Then Begin
  For I:=0 to N-1 do R.D[I]:=A.D[I]*SigmoidF(Beta*A.D[I]);
 End
  Else
 For I:=0 to N-1 do R.D[I]:=F1(Op,A.D[I],FA,FB,IA);
 If(N>0)and(Pr<>PR_F16)and(Pr<>PR_BF16)Then QuantArr(Pr,@R.D[0],N);
End;

Procedure OpBinary(Op:LongInt;Const A0,B0:TTensor;Var R:TTensor);
Var
 A,B:TTensor;
 OD,SA_,SB_,Idx:TIntArr;
 N,I,J,K,Rk,Inner,OA,OB,SIA,SIB:LongInt;
 Pr:LongInt;
 PA,PB,PO:PSingle;
 X:Single;
Begin
 A:=A0;B:=B0;
 Mat(A);Mat(B);
 Pr:=A.Prec;
 If(Op>=OP_EQ)and(Op<=OP_OR)Then Pr:=PR_BOOL;
 If SameDims(A.Dims,B.Dims)Then OD:=CopyDims(A.Dims)
                           Else OD:=BCastDims(A.Dims,B.Dims);
 R:=NewTensor(Pr,OD);
 N:=Length(R.D);
 If N=0 Then Exit;
 PA:=@A.D[0];PB:=@B.D[0];PO:=@R.D[0];
 If SameDims(A.Dims,B.Dims)Then Begin
  Case Op of
   OP_ADD:For I:=0 to N-1 do PO[I]:=PA[I]+PB[I];
   OP_SUB:For I:=0 to N-1 do PO[I]:=PA[I]-PB[I];
   OP_MUL:For I:=0 to N-1 do PO[I]:=PA[I]*PB[I];
   Else For I:=0 to N-1 do PO[I]:=F2(Op,PA[I],PB[I]);
  End;
 End
  Else
 If Length(B.D)=1 Then Begin
  X:=PB[0];
  Case Op of
   OP_ADD:For I:=0 to N-1 do PO[I]:=PA[I]+X;
   OP_SUB:For I:=0 to N-1 do PO[I]:=PA[I]-X;
   OP_MUL:For I:=0 to N-1 do PO[I]:=PA[I]*X;
   Else For I:=0 to N-1 do PO[I]:=F2(Op,PA[I],X);
  End;
 End
  Else
 If Length(A.D)=1 Then Begin
  X:=PA[0];
  For I:=0 to N-1 do PO[I]:=F2(Op,X,PB[I]);
 End
  Else
 Begin
  SA_:=BStrides(A.Dims,OD);
  SB_:=BStrides(B.Dims,OD);
  Rk:=Length(OD);
  Inner:=OD[Rk-1];
  SIA:=SA_[Rk-1];SIB:=SB_[Rk-1];
  SetLength(Idx,Rk);
  For K:=0 to Rk-1 do Idx[K]:=0;
  OA:=0;OB:=0;J:=0;
  While J<N do Begin
   For I:=0 to Inner-1 do PO[J+I]:=F2(Op,PA[OA+I*SIA],PB[OB+I*SIB]);
   Inc(J,Inner);
   K:=Rk-2;
   While K>=0 do Begin
    Inc(Idx[K]);
    OA:=OA+SA_[K];OB:=OB+SB_[K];
    If Idx[K]<OD[K]Then Break;
    OA:=OA-SA_[K]*OD[K];OB:=OB-SB_[K]*OD[K];
    Idx[K]:=0;
    Dec(K);
   End;
   If K<0 Then Break;
  End;
 End;
 If IsIntPrec(Pr)and(Pr<>PR_BOOL)and((Op=OP_DIV)or(Op=OP_POW)or(Op=OP_MOD))Then
  QuantArr(Pr,PO,N);
End;

Procedure OpConvert(Const A:TTensor;Dest:LongInt;Var R:TTensor);
Var
 N:LongInt;
Begin
 N:=CountOf(A.Dims);
 R:=NewTensor(Dest,A.Dims);
 If N=0 Then Exit;
 If Length(A.Raw)>0 Then DecodeRaw(@A.Raw[0],A.Prec,0,N,@R.D[0])
                    Else Move(A.D[0],R.D[0],Int64(N)*4);
 { FP16 / BF16 : calcules en FP32, comme le plugin CPU avec une precision
   d'inference f32 }
 If(Dest<>PR_F16)and(Dest<>PR_BF16)Then QuantArr(Dest,@R.D[0],N);
End;

Procedure OpSelect(Const C0,A0,B0:TTensor;Var R:TTensor);
Var
 C,A,B:TTensor;
 OD,SC,SA_,SB_,Idx:TIntArr;
 N,I,K,Rk,OC,OA,OB:LongInt;
Begin
 C:=C0;A:=A0;B:=B0;
 Mat(C);Mat(A);Mat(B);
 OD:=BCastDims(BCastDims(C.Dims,A.Dims),B.Dims);
 R:=NewTensor(A.Prec,OD);
 N:=Length(R.D);
 If N=0 Then Exit;
 SC:=BStrides(C.Dims,OD);
 SA_:=BStrides(A.Dims,OD);
 SB_:=BStrides(B.Dims,OD);
 Rk:=Length(OD);
 SetLength(Idx,Rk);
 For K:=0 to Rk-1 do Idx[K]:=0;
 OC:=0;OA:=0;OB:=0;
 For I:=0 to N-1 do Begin
  If C.D[OC]<>0 Then R.D[I]:=A.D[OA]
                Else R.D[I]:=B.D[OB];
  K:=Rk-1;
  While K>=0 do Begin
   Inc(Idx[K]);
   OC:=OC+SC[K];OA:=OA+SA_[K];OB:=OB+SB_[K];
   If Idx[K]<OD[K]Then Break;
   OC:=OC-SC[K]*OD[K];OA:=OA-SA_[K]*OD[K];OB:=OB-SB_[K]*OD[K];
   Idx[K]:=0;
   Dec(K);
  End;
 End;
End;

{ ------------------------------------------------------------------ }
{ Operations de forme                                                 }
{ ------------------------------------------------------------------ }

Procedure OpReshape(Const A:TTensor;Const Pat:TIntArr;Special:Boolean;Var R:TTensor);
Var
 OD:TIntArr;
 I,Neg,Known,N:LongInt;
Begin
 N:=CountOf(A.Dims);
 SetLength(OD,Length(Pat));
 Neg:=-1;Known:=1;
 For I:=0 to High(Pat) do Begin
  If(Pat[I]=0)and Special Then Begin
   If I>=Length(A.Dims)Then Die('Reshape : motif 0 sans dimension d''entree correspondante');
   OD[I]:=A.Dims[I];
  End
   Else
  OD[I]:=Pat[I];
  If OD[I]=-1 Then Begin
   If Neg>=0 Then Die('Reshape : plusieurs dimensions -1');
   Neg:=I;
  End
   Else Known:=Known*OD[I];
 End;
 If Neg>=0 Then Begin
  If(Known=0)or((N mod Known)<>0)Then Die('Reshape : impossible de deduire la dimension -1 ('+IStr(N)+' / '+IStr(Known)+')');
  OD[Neg]:=N div Known;
 End;
 If CountOf(OD)<>N Then Die('Reshape : nombre d''elements incompatible '+DimsToStr(A.Dims)+' -> '+DimsToStr(OD));
 R:=A;
 R.Dims:=OD;
End;

Procedure OpUnsqueeze(Const A:TTensor;Const Axes0:TIntArr;Var R:TTensor);
Var
 OD:TIntArr;
 Mark:Array of Boolean;
 I,J,Rk:LongInt;
Begin
 Rk:=Length(A.Dims)+Length(Axes0);
 SetLength(Mark,Rk);
 For I:=0 to Rk-1 do Mark[I]:=False;
 For I:=0 to High(Axes0) do Mark[NormAxis(Axes0[I],Rk)]:=True;
 SetLength(OD,Rk);
 J:=0;
 For I:=0 to Rk-1 do
  If Mark[I]Then OD[I]:=1
  Else Begin
   If J>=Length(A.Dims)Then Die('Unsqueeze : axes invalides');
   OD[I]:=A.Dims[J];
   Inc(J);
  End;
 R:=A;
 R.Dims:=OD;
End;

Procedure OpSqueeze(Const A:TTensor;Const Axes0:TIntArr;HasAxes:Boolean;Var R:TTensor);
Var
 OD:TIntArr;
 Drop:Array of Boolean;
 I,J,Rk:LongInt;
Begin
 Rk:=Length(A.Dims);
 SetLength(Drop,Rk);
 For I:=0 to Rk-1 do Drop[I]:=False;
 If HasAxes and(Length(Axes0)>0)Then Begin
  For I:=0 to High(Axes0) do Drop[NormAxis(Axes0[I],Rk)]:=True;
 End
  Else
 For I:=0 to Rk-1 do Drop[I]:=A.Dims[I]=1;
 SetLength(OD,0);
 For I:=0 to Rk-1 do
  If Not Drop[I]Then Begin
   J:=Length(OD);
   SetLength(OD,J+1);
   OD[J]:=A.Dims[I];
  End
   Else
  If A.Dims[I]<>1 Then Die('Squeeze : la dimension '+IStr(I)+' n''est pas egale a 1');
 R:=A;
 R.Dims:=OD;
End;

Procedure OpTranspose(Const A0:TTensor;Const Perm0:TIntArr;HasPerm:Boolean;Var R:TTensor);
Var
 A:TTensor;
 Perm,OD,St,AS_:TIntArr;
 I,Rk,P:LongInt;
 Ident:Boolean;
Begin
 A:=A0;
 Rk:=Length(A.Dims);
 SetLength(Perm,Rk);
 If HasPerm and(Length(Perm0)=Rk)Then Begin
  For I:=0 to Rk-1 do Perm[I]:=NormAxis(Perm0[I],Rk);
 End
  Else
 For I:=0 to Rk-1 do Perm[I]:=Rk-1-I;
 Ident:=True;
 For I:=0 to Rk-1 do If Perm[I]<>I Then Ident:=False;
 If Ident Then Begin
  R:=A;
  Exit;
 End;
 Mat(A);
 SetLength(OD,Rk);
 SetLength(St,Rk);
 SetLength(AS_,Rk);
 P:=1;
 For I:=Rk-1 downto 0 do Begin
  St[I]:=P;
  P:=P*A.Dims[I];
 End;
 For I:=0 to Rk-1 do Begin
  OD[I]:=A.Dims[Perm[I]];
  AS_[I]:=St[Perm[I]];
 End;
 R:=NewTensor(A.Prec,OD);
 StridedCopy(A,OD,AS_,R);
End;

Procedure OpBroadcast(Const A0,T0:TTensor;Const AM:TIntArr;HasAM:Boolean;Mode:LongInt;
                      Var R:TTensor);
Var
 A:TTensor;
 Tgt,OD,St,AS_:TIntArr;
 I,Rk,Off,P:LongInt;
Begin
 A:=A0;
 Mat(A);
 Tgt:=TensorInts(T0);
 If Mode=1 Then OD:=BCastDims(A.Dims,Tgt)
           Else OD:=CopyDims(Tgt);
 Rk:=Length(OD);
 SetLength(AS_,Rk);
 If Mode=2 Then Begin
  If Not HasAM Then Die('Broadcast explicit : axes_mapping manquant');
  For I:=0 to Rk-1 do AS_[I]:=0;
  SetLength(St,Length(A.Dims));
  P:=1;
  For I:=High(A.Dims) downto 0 do Begin
   St[I]:=P;
   P:=P*A.Dims[I];
  End;
  For I:=0 to High(A.Dims) do
   If I<Length(AM)Then Begin
    Off:=NormAxis(AM[I],Rk);
    If A.Dims[I]<>1 Then AS_[Off]:=St[I];
    If(A.Dims[I]<>1)and(A.Dims[I]<>OD[Off])Then Die('Broadcast : forme incompatible');
   End;
 End
  Else
 Begin
  If Length(A.Dims)>Rk Then Die('Broadcast : rang de la forme cible trop petit');
  AS_:=BStrides(A.Dims,OD);
  Off:=Rk-Length(A.Dims);
  For I:=0 to High(A.Dims) do
   If(A.Dims[I]<>1)and(A.Dims[I]<>OD[Off+I])Then
    Die('Broadcast : '+DimsToStr(A.Dims)+' ne peut pas etre diffuse vers '+DimsToStr(OD));
 End;
 R:=NewTensor(A.Prec,OD);
 StridedCopy(A,OD,AS_,R);
End;

Procedure OpConcat(Const Ins:Array of TTensor;Axis:LongInt;Var R:TTensor);
Var
 I,K,Rk,Outer,Inner,Tot,Pos,Chunk,O:LongInt;
 OD:TIntArr;
 T:TTensor;
 Prec:LongInt;
Begin
 If Length(Ins)=0 Then Die('Concat sans entree');
 Rk:=Length(Ins[0].Dims);
 Axis:=NormAxis(Axis,Rk);
 OD:=CopyDims(Ins[0].Dims);
 Tot:=0;
 Prec:=Ins[0].Prec;
 For I:=0 to High(Ins) do Begin
  If Length(Ins[I].Dims)<>Rk Then Die('Concat : rangs differents');
  For K:=0 to Rk-1 do
   If(K<>Axis)and(Ins[I].Dims[K]<>OD[K])Then
    Die('Concat : formes incompatibles '+DimsToStr(Ins[0].Dims)+' et '+DimsToStr(Ins[I].Dims));
  Tot:=Tot+Ins[I].Dims[Axis];
 End;
 OD[Axis]:=Tot;
 R:=NewTensor(Prec,OD);
 If Length(R.D)=0 Then Exit;
 Outer:=ProdRange(OD,0,Axis);
 Inner:=ProdRange(OD,Axis+1,Rk);
 Pos:=0;
 For I:=0 to High(Ins) do Begin
  T:=Ins[I];
  Mat(T);
  Chunk:=T.Dims[Axis]*Inner;
  If Chunk>0 Then
   For O:=0 to Outer-1 do
    Move(T.D[O*Chunk],R.D[O*Tot*Inner+Pos*Inner],Int64(Chunk)*4);
  Pos:=Pos+T.Dims[Axis];
 End;
End;

{ Extrait la tranche [Start,Start+Len[ sur Axis }
Procedure SliceAxis(Const A:TTensor;Axis,Start,Len:LongInt;Var R:TTensor);
Var
 OD:TIntArr;
 Outer,Inner,O,Chunk:LongInt;
Begin
 OD:=CopyDims(A.Dims);
 OD[Axis]:=Len;
 R:=NewTensor(A.Prec,OD);
 If Length(R.D)=0 Then Exit;
 Outer:=ProdRange(A.Dims,0,Axis);
 Inner:=ProdRange(A.Dims,Axis+1,Length(A.Dims));
 Chunk:=Len*Inner;
 For O:=0 to Outer-1 do
  Move(A.D[(O*A.Dims[Axis]+Start)*Inner],R.D[O*Chunk],Int64(Chunk)*4);
End;

Procedure OpGather(Const A:TTensor;Const I0:TTensor;Axis,BatchDims:LongInt;Var R:TTensor);
Var
 Idx:TTensor;
 Rk,Batch,Outer,AxD,IPB,Inner,B,O,J,Q:LongInt;
 OD:TIntArr;
 Src:LongInt;
 Tmp:TSingleArr;
Begin
 Idx:=I0;
 Mat(Idx);
 Rk:=Length(A.Dims);
 If BatchDims<0 Then BatchDims:=BatchDims+Length(Idx.Dims);
 Axis:=NormAxis(Axis,Rk);
 Batch:=ProdRange(A.Dims,0,BatchDims);
 Outer:=ProdRange(A.Dims,BatchDims,Axis);
 AxD:=A.Dims[Axis];
 IPB:=ProdRange(Idx.Dims,BatchDims,Length(Idx.Dims));
 Inner:=ProdRange(A.Dims,Axis+1,Rk);
 SetLength(OD,0);
 For Q:=0 to Axis-1 do Begin
  SetLength(OD,Length(OD)+1);OD[High(OD)]:=A.Dims[Q];
 End;
 For Q:=BatchDims to High(Idx.Dims) do Begin
  SetLength(OD,Length(OD)+1);OD[High(OD)]:=Idx.Dims[Q];
 End;
 For Q:=Axis+1 to Rk-1 do Begin
  SetLength(OD,Length(OD)+1);OD[High(OD)]:=A.Dims[Q];
 End;
 R:=NewTensor(A.Prec,OD);
 If Length(R.D)=0 Then Exit;
 If AxD=0 Then Die('Gather : axe de taille nulle');
 For B:=0 to Batch-1 do
  For O:=0 to Outer-1 do
   For J:=0 to IPB-1 do Begin
    Src:=Round(Idx.D[B*IPB+J]);
    If Src<0 Then Src:=Src+AxD;
    { indices hors limites ramenes dans [0,N-1] (entrees aleatoires) }
    If Src<0 Then Src:=0;
    If Src>=AxD Then Src:=AxD-1;
    RdElems(A,((B*Outer+O)*AxD+Src)*Inner,Inner,@R.D[((B*Outer+O)*IPB+J)*Inner]);
   End;
End;

Procedure OpRange(Const S0,E0,St0:TTensor;Prec:LongInt;Var R:TTensor);
Var
 S,E,St:TTensor;
 V0,V1,V2,L:Double;
 N,I:LongInt;
Begin
 S:=S0;E:=E0;St:=St0;
 Mat(S);Mat(E);Mat(St);
 V0:=S.D[0];V1:=E.D[0];V2:=St.D[0];
 If V2=0 Then Die('Range : pas nul');
 L:=(V1-V0)/V2;
 If L<=0 Then N:=0
 Else Begin
  N:=Trunc(L);
  If L-N>1E-6 Then Inc(N);
 End;
 R:=NewTensor(Prec,MakeDims([N]));
 For I:=0 to N-1 do R.D[I]:=V0+I*V2;
 QuantArr(Prec,@R.D[0],N);
End;

{ Reduction sur un axe, en conservant une dimension de taille 1 }
Procedure ReduceOne(Op:LongInt;Const A:TTensor;Axis:LongInt;Var R:TTensor);
Var
 OD:TIntArr;
 Outer,Rd,Inner,O,K,I:LongInt;
 Acc:Double;
 V:Single;
Begin
 OD:=CopyDims(A.Dims);
 OD[Axis]:=1;
 R:=NewTensor(A.Prec,OD);
 Outer:=ProdRange(A.Dims,0,Axis);
 Rd:=A.Dims[Axis];
 Inner:=ProdRange(A.Dims,Axis+1,Length(A.Dims));
 If Length(R.D)=0 Then Exit;
 For O:=0 to Outer-1 do
  For I:=0 to Inner-1 do Begin
   Case Op of
    OP_RMAX:Acc:=-3.4E38;
    OP_RMIN:Acc:=3.4E38;
    OP_RPROD:Acc:=1;
    Else Acc:=0;
   End;
   For K:=0 to Rd-1 do Begin
    V:=A.D[(O*Rd+K)*Inner+I];
    Case Op of
     OP_RMAX:If V>Acc Then Acc:=V;
     OP_RMIN:If V<Acc Then Acc:=V;
     OP_RPROD:Acc:=Acc*V;
     Else Acc:=Acc+V;
    End;
   End;
   If(Op=OP_RMEAN)and(Rd>0)Then Acc:=Acc/Rd;
   R.D[O*Inner+I]:=Acc;
  End;
End;

Procedure OpReduce(Op:LongInt;Const A0:TTensor;Const Axes0:TIntArr;Keep:Boolean;Var R:TTensor);
Var
 A,Cur,Nxt:TTensor;
 Axes:TIntArr;
 I,J,Rk,T:LongInt;
 OD:TIntArr;
 Gone:Array of Boolean;
Begin
 A:=A0;
 Mat(A);
 Rk:=Length(A.Dims);
 SetLength(Axes,Length(Axes0));
 For I:=0 to High(Axes0) do Axes[I]:=NormAxis(Axes0[I],Rk);
 { tri decroissant }
 For I:=0 to High(Axes)-1 do
  For J:=0 to High(Axes)-1-I do
   If Axes[J]<Axes[J+1]Then Begin
    T:=Axes[J];Axes[J]:=Axes[J+1];Axes[J+1]:=T;
   End;
 Cur:=A;
 SetLength(Gone,Rk);
 For I:=0 to Rk-1 do Gone[I]:=False;
 For I:=0 to High(Axes) do Begin
  If Gone[Axes[I]]Then Continue;
  Gone[Axes[I]]:=True;
  ReduceOne(Op,Cur,Axes[I],Nxt);
  Cur:=Nxt;
 End;
 If Keep Then R:=Cur
 Else Begin
  SetLength(OD,0);
  For I:=0 to Rk-1 do
   If Not Gone[I]Then Begin
    SetLength(OD,Length(OD)+1);
    OD[High(OD)]:=A.Dims[I];
   End;
  R:=Cur;
  R.Dims:=OD;
 End;
End;

Procedure OpSoftmax(Const A0:TTensor;Axis:LongInt;Var R:TTensor);
Var
 A:TTensor;
 Outer,Rd,Inner,O,K,I:LongInt;
 Mx,Sm,V:Double;
Begin
 A:=A0;
 Mat(A);
 Axis:=NormAxis(Axis,Length(A.Dims));
 R:=NewTensor(A.Prec,A.Dims);
 Outer:=ProdRange(A.Dims,0,Axis);
 Rd:=A.Dims[Axis];
 Inner:=ProdRange(A.Dims,Axis+1,Length(A.Dims));
 For O:=0 to Outer-1 do
  For I:=0 to Inner-1 do Begin
   Mx:=-3.4E38;
   For K:=0 to Rd-1 do Begin
    V:=A.D[(O*Rd+K)*Inner+I];
    If V>Mx Then Mx:=V;
   End;
   Sm:=0;
   For K:=0 to Rd-1 do Begin
    V:=Exp(A.D[(O*Rd+K)*Inner+I]-Mx);
    R.D[(O*Rd+K)*Inner+I]:=V;
    Sm:=Sm+V;
   End;
   For K:=0 to Rd-1 do R.D[(O*Rd+K)*Inner+I]:=R.D[(O*Rd+K)*Inner+I]/Sm;
  End;
End;

{ ------------------------------------------------------------------ }
{ Produit matriciel                                                   }
{ ------------------------------------------------------------------ }

Type
 TMMJob = Record
  A,B,C:PSingle;
  M,N,K:LongInt;
  SAm,SAk,SBk,SBn:LongInt;
  AOff,BOff:TIntArr;
 End;
 PMMJob = ^TMMJob;

Function Dot(A,B:PSingle;N:LongInt):Single;
Var
 I:LongInt;
 S0,S1,S2,S3:Single;
Begin
 S0:=0;S1:=0;S2:=0;S3:=0;
 I:=0;
 While I+3<N do Begin
  S0:=S0+A[I]*B[I];
  S1:=S1+A[I+1]*B[I+1];
  S2:=S2+A[I+2]*B[I+2];
  S3:=S3+A[I+3]*B[I+3];
  Inc(I,4);
 End;
 While I<N do Begin
  S0:=S0+A[I]*B[I];
  Inc(I);
 End;
 Dot:=(S0+S1)+(S2+S3);
End;

{ Calcule C[b,m,n0..n1[ }
Procedure MMSeg(Const J:TMMJob;B,Mi,N0,N1:LongInt);
Var
 Ap,Bp,Cp,Row:PSingle;
 N,K:LongInt;
 A_:Single;
 S:Single;
Begin
 Ap:=J.A+J.AOff[B];
 Bp:=J.B+J.BOff[B];
 Cp:=J.C+PtrInt((Int64(B)*J.M+Mi)*J.N);
 If(J.SAk=1)and(J.SBk=1)Then Begin
  For N:=N0 to N1-1 do Cp[N]:=Dot(Ap+Mi*J.SAm,Bp+N*J.SBn,J.K);
 End
  Else
 If J.SBn=1 Then Begin
  For N:=N0 to N1-1 do Cp[N]:=0;
  For K:=0 to J.K-1 do Begin
   A_:=Ap[Mi*J.SAm+K*J.SAk];
   Row:=Bp+K*J.SBk;
   For N:=N0 to N1-1 do Cp[N]:=Cp[N]+A_*Row[N];
  End;
 End
  Else
 Begin
  For N:=N0 to N1-1 do Begin
   S:=0;
   For K:=0 to J.K-1 do S:=S+Ap[Mi*J.SAm+K*J.SAk]*Bp[K*J.SBk+N*J.SBn];
   Cp[N]:=S;
  End;
 End;
End;

Procedure MMRange(Ctx:Pointer;S,E:Int64);
Var
 J:PMMJob;
 Idx:Int64;
 B,Mi,N0,N1,Rem:LongInt;
Begin
 J:=PMMJob(Ctx);
 Idx:=S;
 While Idx<E do Begin
  B:=Idx div(Int64(J^.M)*J^.N);
  Rem:=Idx mod(Int64(J^.M)*J^.N);
  Mi:=Rem div J^.N;
  N0:=Rem mod J^.N;
  N1:=J^.N;
  If N1-N0>E-Idx Then N1:=N0+(E-Idx);
  MMSeg(J^,B,Mi,N0,N1);
  Idx:=Idx+(N1-N0);
 End;
End;

Procedure OpMatMul(Const A0,B0:TTensor;TA,TB:Boolean;Threads:LongInt;Var R:TTensor);
Var
 A,B:TTensor;
 AD,BD,OB,OD,SA_,SB_,Idx:TIntArr;
 AVec,BVec:Boolean;
 Ra,Rb,M,N,K,KB,I,J,NBt,Q,Rk:LongInt;
 Job:TMMJob;
 BAd,BBd,OAo,OBo:LongInt;
Begin
 A:=A0;B:=B0;
 Mat(A);Mat(B);
 Ra:=Length(A.Dims);Rb:=Length(B.Dims);
 If(Ra<1)or(Rb<1)Then Die('MatMul : operande de rang 0');
 AVec:=Ra=1;BVec:=Rb=1;
 If AVec Then Begin
  AD:=MakeDims([1,A.Dims[0]]);
  TA:=False;
 End
  Else AD:=A.Dims;
 If BVec Then Begin
  BD:=MakeDims([B.Dims[0],1]);
  TB:=False;
 End
  Else BD:=B.Dims;
 Ra:=Length(AD);Rb:=Length(BD);
 If TA Then Begin
  K:=AD[Ra-2];M:=AD[Ra-1];
 End
  Else
 Begin
  M:=AD[Ra-2];K:=AD[Ra-1];
 End;
 If TB Then Begin
  N:=BD[Rb-2];KB:=BD[Rb-1];
 End
  Else
 Begin
  KB:=BD[Rb-2];N:=BD[Rb-1];
 End;
 If K<>KB Then
  Die('MatMul : dimensions incompatibles '+DimsToStr(A.Dims)+' x '+DimsToStr(B.Dims));
 { dimensions de lot }
 SetLength(OB,0);
 If(Ra>2)or(Rb>2)Then Begin
  Q:=Ra-2;
  SetLength(SA_,Q);
  For I:=0 to Q-1 do SA_[I]:=AD[I];
  Q:=Rb-2;
  SetLength(SB_,Q);
  For I:=0 to Q-1 do SB_[I]:=BD[I];
  OB:=BCastDims(SA_,SB_);
 End;
 NBt:=CountOf(OB);
 { dimensions de sortie }
 SetLength(OD,0);
 For I:=0 to High(OB) do Begin
  SetLength(OD,Length(OD)+1);OD[High(OD)]:=OB[I];
 End;
 If Not AVec Then Begin
  SetLength(OD,Length(OD)+1);OD[High(OD)]:=M;
 End;
 If Not BVec Then Begin
  SetLength(OD,Length(OD)+1);OD[High(OD)]:=N;
 End;
 R:=NewTensor(A.Prec,OD);
 If Length(R.D)=0 Then Exit;
 If K=0 Then Exit;
 { decalages des matrices de chaque lot }
 SetLength(Job.AOff,NBt);
 SetLength(Job.BOff,NBt);
 Rk:=Length(OB);
 If Rk=0 Then Begin
  Job.AOff[0]:=0;Job.BOff[0]:=0;
 End
  Else
 Begin
  SA_:=BStrides(HeadDims(AD,Ra-2),OB);
  SB_:=BStrides(HeadDims(BD,Rb-2),OB);
  { les pas ci-dessus sont en lots; on les convertit en elements }
  BAd:=M*K;BBd:=K*N;
  SetLength(Idx,Rk);
  For I:=0 to Rk-1 do Idx[I]:=0;
  OAo:=0;OBo:=0;
  For J:=0 to NBt-1 do Begin
   Job.AOff[J]:=OAo*BAd;
   Job.BOff[J]:=OBo*BBd;
   Q:=Rk-1;
   While Q>=0 do Begin
    Inc(Idx[Q]);
    OAo:=OAo+SA_[Q];OBo:=OBo+SB_[Q];
    If Idx[Q]<OB[Q]Then Break;
    OAo:=OAo-SA_[Q]*OB[Q];OBo:=OBo-SB_[Q]*OB[Q];
    Idx[Q]:=0;
    Dec(Q);
   End;
  End;
 End;
 Job.A:=@A.D[0];Job.B:=@B.D[0];Job.C:=@R.D[0];
 Job.M:=M;Job.N:=N;Job.K:=K;
 If TA Then Begin
  Job.SAm:=1;Job.SAk:=M;
 End
  Else
 Begin
  Job.SAm:=K;Job.SAk:=1;
 End;
 If TB Then Begin
  Job.SBk:=1;Job.SBn:=K;
 End
  Else
 Begin
  Job.SBk:=N;Job.SBn:=1;
 End;
 ParFor(Threads,Int64(NBt)*M*N,Int64(NBt)*M*N*K,@MMRange,@Job);
End;

{ ------------------------------------------------------------------ }
{ MatMul avec poids compresses (decompression a la volee)            }
{ ------------------------------------------------------------------ }

Type
 PTensor = ^TTensor;

 TQJob = Record
  X,C:PSingle;
  M,N,K,G,GS:LongInt;
  Q:PTensor;
  Sc,Zp:PSingle;        { N*G valeurs ; nil si absents }
 End;
 PQJob = ^TQJob;

{ C[m,n] = sum_k X[m,k] * W[n,k], W[n,k] = (Q[n,k]-zero)*echelle }
Procedure QRange(Ctx:Pointer;S,E:Int64);
Var
 J:PQJob;
 Wrow:TSingleArr;
 Wp:PSingle;
 Nn,Mi,Gi,Jj:LongInt;
 Sc_,Zp_:Single;
Begin
 J:=PQJob(Ctx);
 SetLength(Wrow,J^.K);
 Wp:=@Wrow[0];
 For Nn:=LongInt(S) to LongInt(E)-1 do Begin
  RdElems(J^.Q^,Nn*J^.K,J^.K,Wp);
  If J^.Sc<>nil Then
   For Gi:=0 to J^.G-1 do Begin
    Sc_:=J^.Sc[Nn*J^.G+Gi];
    If J^.Zp<>nil Then Zp_:=J^.Zp[Nn*J^.G+Gi]
                  Else Zp_:=0;
    For Jj:=Gi*J^.GS to Gi*J^.GS+J^.GS-1 do Wp[Jj]:=(Wp[Jj]-Zp_)*Sc_;
   End;
  For Mi:=0 to J^.M-1 do J^.C[Mi*J^.N+Nn]:=Dot(J^.X+Mi*J^.K,Wp,J^.K);
 End;
End;

Procedure OpMatMulQ(Const X0,Q:TTensor;Const Sc0,Zp0:TTensor;HasSc,HasZp:Boolean;
                    Threads:LongInt;Var R:TTensor);
Var
 X:TTensor;
 SCa,ZPa:TSingleArr;
 OD:TIntArr;
 Job:TQJob;
 K,N,M,I,NS:LongInt;
Begin
 X:=X0;
 Mat(X);
 If Length(X.Dims)<1 Then Die('MatMul : operande de rang 0');
 K:=X.Dims[High(X.Dims)];
 N:=Q.Dims[0];
 If CountOf(Q.Dims)<>N*K Then
  Die('MatMul : dimensions incompatibles '+DimsToStr(X.Dims)+' x '+DimsToStr(Q.Dims)+'^T');
 SetLength(OD,Length(X.Dims));
 For I:=0 to High(X.Dims)-1 do OD[I]:=X.Dims[I];
 OD[High(OD)]:=N;
 R:=NewTensor(X.Prec,OD);
 If(Length(R.D)=0)or(K=0)Then Exit;
 M:=CountOf(X.Dims)div K;
 Job.G:=1;Job.GS:=K;
 Job.Sc:=nil;Job.Zp:=nil;
 If HasSc Then Begin
  NS:=CountOf(Sc0.Dims);
  SetLength(SCa,NS);
  RdElems(Sc0,0,NS,@SCa[0]);
  Job.G:=NS div N;
  Job.GS:=K div Job.G;
  Job.Sc:=@SCa[0];
  If HasZp Then Begin
   SetLength(ZPa,NS);
   RdElems(Zp0,0,NS,@ZPa[0]);
   Job.Zp:=@ZPa[0];
  End;
 End;
 Job.X:=@X.D[0];Job.C:=@R.D[0];
 Job.M:=M;Job.N:=N;Job.K:=K;
 Job.Q:=@Q;
 ParFor(Threads,N,Int64(M)*N*K,@QRange,@Job);
End;

{ ------------------------------------------------------------------ }
{ Attention (ScaledDotProductAttention)                               }
{ ------------------------------------------------------------------ }

Type
 TSDPAJob = Record
  Q,K,V,M,O:PSingle;
  L,S,E,Ev:LongInt;
  Scale:Single;
  Causal:Boolean;
  MaskMode:LongInt;        { 0 aucun, 1 flottant, 2 booleen }
  MOff:TIntArr;            { decalage du masque par tete }
  MSl,MSs:LongInt;         { pas du masque sur les lignes et colonnes }
 End;
 PSDPAJob = ^TSDPAJob;

Procedure SDPARange(Ctx:Pointer;S,E_:Int64);
Var
 J:PSDPAJob;
 Row:LongInt;
 BH,Li,Sj,Dd:LongInt;
 Sc:TSingleArr;
 Mx,Sm,Mv:Single;
 Qp,Kp,Vp,Op,Mp:PSingle;
Begin
 J:=PSDPAJob(Ctx);
 SetLength(Sc,J^.S);
 For Row:=LongInt(S) to LongInt(E_)-1 do Begin
  BH:=Row div J^.L;
  Li:=Row mod J^.L;
  Qp:=J^.Q+PtrInt((Int64(BH)*J^.L+Li)*J^.E);
  Kp:=J^.K+PtrInt(Int64(BH)*J^.S*J^.E);
  Vp:=J^.V+PtrInt(Int64(BH)*J^.S*J^.Ev);
  Op:=J^.O+PtrInt((Int64(BH)*J^.L+Li)*J^.Ev);
  If J^.MaskMode<>0 Then Mp:=J^.M+J^.MOff[BH]+Li*J^.MSl
                    Else Mp:=nil;
  Mx:=-3.4E38;
  For Sj:=0 to J^.S-1 do Begin
   Sm:=Dot(Qp,Kp+PtrInt(Int64(Sj)*J^.E),J^.E)*J^.Scale;
   If J^.MaskMode=1 Then Sm:=Sm+Mp[Sj*J^.MSs] Else
   If J^.MaskMode=2 Then Begin
    If Mp[Sj*J^.MSs]=0 Then Sm:=-1E30;
   End;
   If J^.Causal and(Sj>Li)Then Sm:=-1E30;
   Sc[Sj]:=Sm;
   If Sm>Mx Then Mx:=Sm;
  End;
  Sm:=0;
  For Sj:=0 to J^.S-1 do Begin
   Mv:=Exp(Sc[Sj]-Mx);
   Sc[Sj]:=Mv;
   Sm:=Sm+Mv;
  End;
  For Dd:=0 to J^.Ev-1 do Op[Dd]:=0;
  If Sm>0 Then
   For Sj:=0 to J^.S-1 do Begin
    Mv:=Sc[Sj]/Sm;
    For Dd:=0 to J^.Ev-1 do Op[Dd]:=Op[Dd]+Mv*Vp[PtrInt(Int64(Sj)*J^.Ev+Dd)];
   End;
 End;
End;

Procedure OpSDPA(Const Q0,K0,V0,M0:TTensor;HasMask:Boolean;Const Sc0:TTensor;HasScale:Boolean;
                 Causal:Boolean;Threads:LongInt;Var R:TTensor);
Var
 Q,K,V,M,Sc:TTensor;
 Rk,I,NBh,L,S,E,Ev,Rm:LongInt;
 OD,Lead,MD,MSt,Idx:TIntArr;
 Job:TSDPAJob;
 Q_:LongInt;
 Off:LongInt;
Begin
 Q:=Q0;K:=K0;V:=V0;
 Mat(Q);Mat(K);Mat(V);
 Rk:=Length(Q.Dims);
 If(Rk<2)or(Length(K.Dims)<>Rk)or(Length(V.Dims)<>Rk)Then
  Die('ScaledDotProductAttention : rangs incompatibles');
 L:=Q.Dims[Rk-2];E:=Q.Dims[Rk-1];
 S:=K.Dims[Rk-2];Ev:=V.Dims[Rk-1];
 If K.Dims[Rk-1]<>E Then Die('ScaledDotProductAttention : dimensions Q et K incompatibles');
 If V.Dims[Rk-2]<>S Then Die('ScaledDotProductAttention : dimensions K et V incompatibles');
 SetLength(Lead,Rk-2);
 NBh:=1;
 For I:=0 to Rk-3 do Begin
  Lead[I]:=Q.Dims[I];
  If(K.Dims[I]<>Q.Dims[I])or(V.Dims[I]<>Q.Dims[I])Then
   Die('ScaledDotProductAttention : dimensions de lot differentes ('+DimsToStr(Q.Dims)+
       ', '+DimsToStr(K.Dims)+')');
  NBh:=NBh*Q.Dims[I];
 End;
 OD:=CopyDims(Lead);
 SetLength(OD,Rk);
 OD[Rk-2]:=L;OD[Rk-1]:=Ev;
 R:=NewTensor(Q.Prec,OD);
 If Length(R.D)=0 Then Exit;
 Job.L:=L;Job.S:=S;Job.E:=E;Job.Ev:=Ev;
 Job.Causal:=Causal;
 If HasScale Then Begin
  Sc:=Sc0;Mat(Sc);
  Job.Scale:=Sc.D[0];
 End
  Else
 Job.Scale:=1.0/Sqrt(E);
 Job.MaskMode:=0;
 SetLength(Job.MOff,NBh);
 For I:=0 to NBh-1 do Job.MOff[I]:=0;
 Job.MSl:=0;Job.MSs:=0;
 If HasMask Then Begin
  M:=M0;Mat(M);
  If M.Prec=PR_BOOL Then Job.MaskMode:=2
                    Else Job.MaskMode:=1;
  MD:=M.Dims;
  Rm:=Length(MD);
  If Rm<2 Then Begin
   If Rm=1 Then Begin
    MD:=MakeDims([1,MD[0]]);
    Rm:=2;
   End
    Else Die('ScaledDotProductAttention : masque de rang 0');
  End;
  If Rm>Rk Then Die('ScaledDotProductAttention : rang du masque trop grand');
  If MD[Rm-2]=1 Then Job.MSl:=0 Else Job.MSl:=MD[Rm-1];
  If MD[Rm-1]=1 Then Job.MSs:=0 Else Job.MSs:=1;
  If((MD[Rm-2]<>1)and(MD[Rm-2]<>L))or((MD[Rm-1]<>1)and(MD[Rm-1]<>S))Then
   Die('ScaledDotProductAttention : forme de masque incompatible '+DimsToStr(M.Dims));
  { pas du masque pour les dimensions de lot }
  SetLength(MSt,Rk-2);
  Q_:=MD[Rm-2]*MD[Rm-1];
  For I:=Rk-3 downto 0 do Begin
   If(I-(Rk-Rm))<0 Then MSt[I]:=0
   Else If MD[I-(Rk-Rm)]=1 Then Begin
    MSt[I]:=0;
   End
   Else Begin
    MSt[I]:=Q_;
   End;
   If(I-(Rk-Rm))>=0 Then Q_:=Q_*MD[I-(Rk-Rm)];
  End;
  SetLength(Idx,Rk-2);
  For I:=0 to Rk-3 do Idx[I]:=0;
  Off:=0;
  For I:=0 to NBh-1 do Begin
   Job.MOff[I]:=Off;
   Q_:=Rk-3;
   While Q_>=0 do Begin
    Inc(Idx[Q_]);
    Off:=Off+MSt[Q_];
    If Idx[Q_]<Lead[Q_]Then Break;
    Off:=Off-MSt[Q_]*Lead[Q_];
    Idx[Q_]:=0;
    Dec(Q_);
   End;
  End;
  Job.M:=@M.D[0];
 End;
 Job.Q:=@Q.D[0];Job.K:=@K.D[0];Job.V:=@V.D[0];Job.O:=@R.D[0];
 ParFor(Threads,Int64(NBh)*L,Int64(NBh)*L*S*(E+Ev),@SDPARange,@Job);
End;

{ ------------------------------------------------------------------ }
{ Execution du graphe                                                }
{ ------------------------------------------------------------------ }

Type
 TCtx = Record
  Slots:Array of TTensor;
  Refs:TIntArr;
  Ins:Array of TTensor;      { entrees courantes de la requete }
  Outs:Array of TTensor;     { sorties de la derniere inference }
  Times:TDblArr;             { duree de chaque couche (derniere inference, ms) }
  Threads:LongInt;           { fils de calcul pour les operations lourdes }
  Prof:Boolean;              { mesure par couche }
  Lat:TDblArr;               { latences mesurees (ms) }
  NLat:LongInt;
  Done:LongInt;
  Frames:Double;             { images traitees }
 End;
 PCtx = ^TCtx;

Function CopyTensor(Const S:TTensor):TTensor;
Var
 N:LongInt;
 R:TTensor;
Begin
 R.Prec:=S.Prec;
 R.Dims:=CopyDims(S.Dims);
 SetLength(R.Raw,0);
 N:=Length(S.D);
 SetLength(R.D,N);
 If N>0 Then Move(S.D[0],R.D[0],Int64(N)*4);
 CopyTensor:=R;
End;

Procedure ClearTensor(Var T:TTensor);
Begin
 SetLength(T.D,0);
 SetLength(T.Raw,0);
 SetLength(T.Dims,0);
End;

Procedure InitCtx(Var C:TCtx;Threads:LongInt;Prof:Boolean);
Var
 I:LongInt;
Begin
 SetLength(C.Slots,NSlots);
 SetLength(C.Refs,NSlots);
 For I:=0 to NSlots-1 do C.Refs[I]:=0;
 SetLength(C.Ins,Length(InLayers));
 SetLength(C.Outs,Length(OutLayers));
 SetLength(C.Times,NL);
 For I:=0 to NL-1 do C.Times[I]:=0;
 C.Threads:=Threads;
 C.Prof:=Prof;
 SetLength(C.Lat,0);
 C.NLat:=0;
 C.Done:=0;
 C.Frames:=0;
End;

Procedure AddLatency(Var C:TCtx;Ms:Double);
Begin
 If C.NLat>=Length(C.Lat)Then Begin
  If C.NLat=0 Then SetLength(C.Lat,4096)
              Else SetLength(C.Lat,C.NLat*2);
 End;
 C.Lat[C.NLat]:=Ms;
 Inc(C.NLat);
End;

Procedure ExecLayer(Var C:TCtx;LI:LongInt);
Var
 A,B,X,R:TTensor;
 Ts:Array of TTensor;
 I,K,N,Ax,Part,Rest,Fl:LongInt;
 Ints,Lens:TIntArr;
 Beta:Single;
 NO:LongInt;

 Function Inp(Idx:LongInt):TTensor;
 Begin
  Inp:=C.Slots[Layers[Layers[LI].SrcL[Idx]].Base+Layers[LI].SrcP[Idx]];
 End;

 Procedure Put(Idx:LongInt;Const T:TTensor);
 Begin
  C.Slots[Layers[LI].Base+Idx]:=T;
 End;

Begin
 Case Layers[LI].Op of
  OP_PARAM:Put(0,C.Ins[Layers[LI].IA]);
  OP_CONST:Put(0,Layers[LI].Cst);
  OP_RESULT:C.Outs[Layers[LI].IA]:=Inp(0);
  OP_CONVERT:Begin
   OpConvert(Inp(0),Layers[LI].IA,R);
   Put(0,R);
  End;
  OP_ADD..OP_OR:Begin
   OpBinary(Layers[LI].Op,Inp(0),Inp(1),R);
   Put(0,R);
  End;
  OP_NOT..OP_CLAMP:Begin
   Beta:=1;
   If(Layers[LI].Op=OP_SWISH)and(Layers[LI].NIn>1)Then Begin
    B:=Inp(1);Mat(B);
    Beta:=B.D[0];
   End;
   OpUnary(Layers[LI].Op,Inp(0),R,Layers[LI].FA,Layers[LI].FB,Layers[LI].IA,Beta);
   Put(0,R);
  End;
  OP_SOFTMAX:Begin
   OpSoftmax(Inp(0),Layers[LI].IA,R);
   Put(0,R);
  End;
  OP_SELECT:Begin
   OpSelect(Inp(0),Inp(1),Inp(2),R);
   Put(0,R);
  End;
  OP_SHAPEOF:Begin
   A:=Inp(0);
   R:=NewTensor(Layers[LI].IA,MakeDims([Length(A.Dims)]));
   For I:=0 to High(A.Dims) do R.D[I]:=A.Dims[I];
   Put(0,R);
  End;
  OP_GATHER:Begin
   Ints:=TensorInts(Inp(2));
   If Length(Ints)<1 Then Die('Gather : axe manquant');
   OpGather(Inp(0),Inp(1),Ints[0],Layers[LI].IA,R);
   Put(0,R);
  End;
  OP_RANGE:Begin
   OpRange(Inp(0),Inp(1),Inp(2),Layers[LI].IA,R);
   Put(0,R);
  End;
  OP_RESHAPE:Begin
   OpReshape(Inp(0),TensorInts(Inp(1)),Layers[LI].IA<>0,R);
   Put(0,R);
  End;
  OP_SQUEEZE:Begin
   If Layers[LI].NIn>1 Then OpSqueeze(Inp(0),TensorInts(Inp(1)),True,R)
                       Else OpSqueeze(Inp(0),Ints,False,R);
   Put(0,R);
  End;
  OP_UNSQUEEZE:Begin
   OpUnsqueeze(Inp(0),TensorInts(Inp(1)),R);
   Put(0,R);
  End;
  OP_TRANSPOSE:Begin
   If Layers[LI].NIn>1 Then OpTranspose(Inp(0),TensorInts(Inp(1)),True,R)
                       Else OpTranspose(Inp(0),Ints,False,R);
   Put(0,R);
  End;
  OP_MATMUL:Begin
   If Layers[LI].FA<>0 Then Begin
    { poids compresses : entrees [X, Q, echelle, zero] }
    K:=2;
    Fl:=Round(Layers[LI].FB);
    If(Fl and 1)<>0 Then Begin
     B:=Inp(K);
     Inc(K);
    End;
    If(Fl and 2)<>0 Then X:=Inp(K);
    OpMatMulQ(Inp(0),Inp(1),B,X,(Fl and 1)<>0,(Fl and 2)<>0,C.Threads,R);
   End
    Else OpMatMul(Inp(0),Inp(1),Layers[LI].IA<>0,Layers[LI].IB<>0,C.Threads,R);
   Put(0,R);
  End;
  OP_CONCAT:Begin
   SetLength(Ts,Layers[LI].NIn);
   For I:=0 to Layers[LI].NIn-1 do Ts[I]:=Inp(I);
   OpConcat(Ts,Layers[LI].IA,R);
   SetLength(Ts,0);
   Put(0,R);
  End;
  OP_SPLIT,OP_VSPLIT:Begin
   A:=Inp(0);
   Mat(A);
   Ints:=TensorInts(Inp(1));
   If Length(Ints)<1 Then Die('Split : axe manquant');
   Ax:=NormAxis(Ints[0],Length(A.Dims));
   NO:=Length(Layers[LI].Outs);
   If Layers[LI].Op=OP_SPLIT Then Begin
    N:=Layers[LI].IA;
    If(N<1)or((A.Dims[Ax] mod N)<>0)Then Die('Split : division impossible de '+DimsToStr(A.Dims));
    Part:=A.Dims[Ax] div N;
    For K:=0 to N-1 do Begin
     SliceAxis(A,Ax,K*Part,Part,R);
     Put(K,R);
    End;
   End
    Else
   Begin
    Lens:=TensorInts(Inp(2));
    Rest:=A.Dims[Ax];
    N:=-1;
    For K:=0 to High(Lens) do
     If Lens[K]=-1 Then N:=K
                   Else Rest:=Rest-Lens[K];
    If N>=0 Then Lens[N]:=Rest;
    Part:=0;
    For K:=0 to High(Lens) do Begin
     SliceAxis(A,Ax,Part,Lens[K],R);
     Put(K,R);
     Part:=Part+Lens[K];
    End;
   End;
  End;
  OP_BROADCAST:Begin
   If Layers[LI].NIn>2 Then OpBroadcast(Inp(0),Inp(1),TensorInts(Inp(2)),True,Layers[LI].IA,R)
                       Else OpBroadcast(Inp(0),Inp(1),Ints,False,Layers[LI].IA,R);
   Put(0,R);
  End;
  OP_RMEAN..OP_RPROD:Begin
   OpReduce(Layers[LI].Op,Inp(0),TensorInts(Inp(1)),Layers[LI].IA<>0,R);
   Put(0,R);
  End;
  OP_SDPA:Begin
   If Layers[LI].NIn>3 Then B:=Inp(3);
   If Layers[LI].NIn>4 Then X:=Inp(4);
   OpSDPA(Inp(0),Inp(1),Inp(2),B,Layers[LI].NIn>3,X,Layers[LI].NIn>4,
          Layers[LI].IA<>0,C.Threads,R);
   Put(0,R);
  End;
  OP_READVALUE:Begin
   If Layers[LI].NIn<1 Then Die('ReadValue sans valeur initiale : '+Layers[LI].Name);
   Put(0,Inp(0));
  End;
  OP_ASSIGN:Begin
   If Length(Layers[LI].Outs)>0 Then Put(0,Inp(0));
  End;
  Else Die('operation non geree : '+Layers[LI].Typ);
 End;
 { liberation des entrees dont le dernier consommateur vient de s'executer }
 For I:=0 to Layers[LI].NIn-1 do Begin
  K:=Layers[Layers[LI].SrcL[I]].Base+Layers[LI].SrcP[I];
  Dec(C.Refs[K]);
  If C.Refs[K]<=0 Then ClearTensor(C.Slots[K]);
 End;
 For I:=0 to Length(Layers[LI].Outs)-1 do Begin
  K:=Layers[LI].Base+I;
  If C.Refs[K]<=0 Then ClearTensor(C.Slots[K]);
 End;
End;

Var
 CurLI:LongInt;      { couche en cours d'execution (messages d'erreur) }

Function LayerHook:AnsiString;
Begin
 If(CurLI>=0)and(CurLI<NL)Then
  LayerHook:=' [couche '+Layers[CurLI].Name+', type '+Layers[CurLI].Typ+']'
 Else LayerHook:='';
End;

{ Une inference complete }
Procedure RunInference(Var C:TCtx);
Var
 I,LI:LongInt;
 T0:Double;
Begin
 For I:=0 to NSlots-1 do C.Refs[I]:=RefInit[I];
 For I:=0 to NL-1 do C.Times[I]:=0;
 For I:=0 to NOrder-1 do Begin
  LI:=Order[I];
  CurLI:=LI;
  If C.Prof Then Begin
   T0:=NowMs;
   ExecLayer(C,LI);
   C.Times[LI]:=NowMs-T0;
  End
   Else ExecLayer(C,LI);
 End;
End;

{ ------------------------------------------------------------------ }
{ Parametres de la ligne de commande                                 }
{ ------------------------------------------------------------------ }

Const
 HasThreads = {$IFDEF THREADS}True{$ELSE}False{$ENDIF};
 DefaultDyn = 16;     { taille par defaut d'une dimension dynamique }

Var
 OModel,ODevice,OHint,OApi,OShape,ODataShape,OLayout,OCdir,OInferPrec,
 OReportType,OReportFolder,OPcSort,ODumpOut,ONStreams,OWeightFmt,OPin:AnsiString;
 OInputs:TStrArr;
 ONiter:Int64;
 OTime,OMaxIrate:Double;
 OBatch,ONireq,ONthreads,OPercentile:LongInt;
 OPc,OPcseq,ONoWarmup,OJson,OHintSet:Boolean;
 OInferOnly:LongInt;        { -1 : non precise, 0 : non, 1 : oui }
 CmdN,CmdV:TStrArr;         { parametres de la ligne de commande (rapport) }

Procedure ShowHelp;
Begin
 WriteLn('BENCHMARK_APP : Cette commande permet de mesurer les performances d''inference ',
         'd''un modele OpenVINO IR (.xml + .bin).');
 WriteLn;
 WriteLn('Syntaxe : benchmark_app [-h] [-i PATHS_TO_INPUT [PATHS_TO_INPUT ...]] -m PATH_TO_MODEL');
 WriteLn('                     [-d TARGET_DEVICE] [-hint {throughput,tput,cumulative_throughput,');
 WriteLn('                     ctput,latency,none}] [-niter NUMBER_ITERATIONS] [-t TIME]');
 WriteLn('                     [-b BATCH_SIZE] [-shape SHAPE] [-data_shape DATA_SHAPE]');
 WriteLn('                     [-layout LAYOUT] [-cdir CACHE_DIR] [-api {sync,async}]');
 WriteLn('                     [-nireq NUMBER_INFER_REQUESTS] [-nstreams NUMBER_STREAMS]');
 WriteLn('                     [-nthreads NUMBER_THREADS] [-inference_only [INFERENCE_ONLY]]');
 WriteLn('                     [-no_warmup] [-infer_precision INFER_PRECISION]');
 WriteLn('                     [-latency_percentile LATENCY_PERCENTILE]');
 WriteLn('                     [-report_type {no_counters,average_counters,detailed_counters}]');
 WriteLn('                     [-report_folder REPORT_FOLDER] [-json_stats [JSON_STATS]]');
 WriteLn('                     [-pc [PERF_COUNTS]] [-pcsort {no_sort,sort,simple_sort}]');
 WriteLn('                     [-max_irate MAXIMUM_INFERENCE_RATE] [-dump_output DOSSIER]');
 WriteLn; 
 WriteLn('Options :');
 WriteLn('  -h, --help, /?   Affiche cette aide et quitte.');
 WriteLn('  -m, --path_to_model PATH_TO_MODEL');
 WriteLn('                   Obligatoire. Chemin du modele (.xml) ou d''un dossier contenant');
 WriteLn('                   openvino_model.xml. Le fichier .bin doit se trouver a cote.');
 WriteLn('  -d, --target_device, --device TARGET_DEVICE');
 WriteLn('                   Peripherique cible. Seul CPU existe (AUTO:CPU, MULTI:CPU et');
 WriteLn('                   HETERO:CPU sont acceptes). Defaut : CPU.');
 WriteLn('  -i, --paths_to_input PATHS_TO_INPUT');
 WriteLn('                   Fichiers .bin ou .npy, ou dossier. Association aux entrees :');
 WriteLn('                   entree1:fichier1,fichier2,entree2:fichier3. Sans cette option,');
 WriteLn('                   les entrees sont remplies de valeurs aleatoires.');
 WriteLn('  -hint, --perf_hint {throughput,tput,cumulative_throughput,ctput,latency,none}');
 WriteLn('                   Indication de performance : latency privilegie une faible');
 WriteLn('                   latence, throughput (tput) le debit, none la desactive.');
 WriteLn('                   -nstreams, -nthreads et -pin exigent -hint none.');
 WriteLn('  -niter, --number_iterations NUMBER_ITERATIONS');
 WriteLn('                   Nombre d''iterations de mesure. -niter 0 compile le modele et quitte.');
 WriteLn('  -t, --time TIME  Duree du benchmark en secondes (60 par defaut sans -niter).');
 WriteLn('  -api, --api_type {sync,async}');
 WriteLn('                   sync : une requete a la fois (defaut avec -hint latency);');
 WriteLn('                   async : plusieurs requetes en parallele (defaut sinon).');
 WriteLn('  -b, --batch_size BATCH_SIZE');
 WriteLn('                   Taille du lot (batch).');
 WriteLn('  -shape SHAPE     Forme des entrees : "entree1[1,128],entree2[1,128]" ou');
 WriteLn('                   "[1,128]" pour une seule entree. ? ou -1 : dimension dynamique.');
 WriteLn('  -data_shape DATA_SHAPE');
 WriteLn('                   Formes des donnees des entrees dynamiques :');
 WriteLn('                   "entree1[1,16][1,32],entree2[1,16][1,32]".');
 WriteLn('  -layout LAYOUT   Disposition des entrees : "entree1[NCHW],entree2[NC]".');
 WriteLn('  -nireq, --number_infer_requests NUMBER_INFER_REQUESTS');
 WriteLn('                   Nombre de requetes d''inference.');
 WriteLn('  -nstreams, --number_streams NUMBER_STREAMS');
 WriteLn('                   Nombre de flux d''inference (fils d''execution paralleles).');
 WriteLn('  -nthreads, --number_threads NUMBER_THREADS');
 WriteLn('                   Nombre de threads CPU.');
 WriteLn('  -inference_only [true|false]');
 WriteLn('                   Ne mesure que l''inference (remplissage des entrees exclu).');
 WriteLn('  -no_warmup       Saute l''inference de chauffe.');
 WriteLn('  -infer_precision INFER_PRECISION');
 WriteLn('                   Precision d''inference demandee (f32, f16, bf16). Le calcul');
 WriteLn('                   reste en FP32 dans ce clone.');
 WriteLn('  -cdir, --cache_dir CACHE_DIR');
 WriteLn('                   Repertoire de cache (cree; aucun blob n''y est ecrit).');
 WriteLn('  -latency_percentile LATENCY_PERCENTILE');
 WriteLn('                   Percentile de latence affiche, de 1 a 100 (50 : mediane).');
 WriteLn('  -report_type {no_counters,average_counters,detailed_counters}');
 WriteLn('  -report_folder REPORT_FOLDER');
 WriteLn('                   Ecrit benchmark_report.csv (et les compteurs) dans ce dossier.');
 WriteLn('  -json_stats [true|false]');
 WriteLn('                   Ecrit benchmark_report.json au lieu du CSV.');
 WriteLn('  -pc [true|false] Affiche les compteurs de performance par couche.');
 WriteLn('  -pcsort {no_sort,sort,simple_sort}');
 WriteLn('                   Tri des compteurs de performance.');
 WriteLn('  -max_irate MAXIMUM_INFERENCE_RATE');
 WriteLn('                   Limite le nombre d''inferences par seconde.');
 WriteLn('  -dump_output DOSSIER');
 WriteLn('                   Extension : ecrit les sorties de la premiere inference (.bin).');
 WriteLn('  --weight-format  Accepte pour compatibilite avec optimum-cli (sans effet).');
 WriteLn('  -extensions, -c, -lfile, -load_config, -dump_config, -exec_graph_path, -pin,');
 WriteLn('  -pcseq, -mean_values, -scale_values, -ip, -op, -iop, -weight-format :');
 WriteLn('                   acceptes puis ignores.');
 WriteLn;
 WriteLn('Exemples :');
 WriteLn('  benchmark_app -m modele.xml -d CPU -hint latency');
 WriteLn('  benchmark_app -m modele.xml -d CPU -hint throughput');
 WriteLn('  benchmark_app -m modele.xml -d CPU -t 60');
 WriteLn('  benchmark_app -m modele.xml -d CPU -hint none -nthreads 8');
End;

Function IsHelpArg(Const A:AnsiString):Boolean;
Begin
 IsHelpArg:=(A='-h')or(A='--help')or(A='-help')or(A='/?')or(A='-?');
End;

{ Nom canonique d'une option (sans tirets, en minuscules) ; '' si inconnue }
Function CanonOpt(K:AnsiString):AnsiString;
Begin
 K:=LoStr(K);
 CanonOpt:='';
 If(K='m')or(K='path_to_model')Then CanonOpt:='m' Else
 If(K='d')or(K='target_device')or(K='device')Then CanonOpt:='d' Else
 If(K='i')or(K='paths_to_input')Then CanonOpt:='i' Else
 If(K='hint')or(K='perf_hint')Then CanonOpt:='hint' Else
 If(K='niter')or(K='number_iterations')Then CanonOpt:='niter' Else
 If(K='max_irate')or(K='maximum_inference_rate')Then CanonOpt:='max_irate' Else
 If(K='t')or(K='time')Then CanonOpt:='t' Else
 If(K='api')or(K='api_type')Then CanonOpt:='api' Else
 If(K='b')or(K='batch_size')Then CanonOpt:='b' Else
 If K='shape'Then CanonOpt:='shape' Else
 If K='data_shape'Then CanonOpt:='data_shape' Else
 If K='layout'Then CanonOpt:='layout' Else
 If K='extensions'Then CanonOpt:='extensions' Else
 If(K='c')or(K='path_to_cldnn_config')Then CanonOpt:='c' Else
 If(K='cdir')or(K='cache_dir')Then CanonOpt:='cdir' Else
 If(K='lfile')or(K='load_from_file')Then CanonOpt:='lfile' Else
 If(K='nireq')or(K='number_infer_requests')Then CanonOpt:='nireq' Else
 If(K='nstreams')or(K='number_streams')Then CanonOpt:='nstreams' Else
 If K='inference_only'Then CanonOpt:='inference_only' Else
 If K='no_warmup'Then CanonOpt:='no_warmup' Else
 If K='infer_precision'Then CanonOpt:='infer_precision' Else
 If(K='ip')or(K='input_precision')Then CanonOpt:='ip' Else
 If(K='op')or(K='output_precision')Then CanonOpt:='op' Else
 If(K='iop')or(K='input_output_precision')Then CanonOpt:='iop' Else
 If(K='mean_values')or(K='scale_values')Then CanonOpt:=K Else
 If(K='nthreads')or(K='number_threads')Then CanonOpt:='nthreads' Else
 If(K='pin')or(K='infer_threads_pinning')Then CanonOpt:='pin' Else
 If K='latency_percentile'Then CanonOpt:='latency_percentile' Else
 If K='report_type'Then CanonOpt:='report_type' Else
 If K='report_folder'Then CanonOpt:='report_folder' Else
 If K='json_stats'Then CanonOpt:='json_stats' Else
 If(K='pc')or(K='perf_counts')Then CanonOpt:='pc' Else
 If(K='pcsort')or(K='perf_counts_sort')Then CanonOpt:='pcsort' Else
 If K='pcseq'Then CanonOpt:='pcseq' Else
 If K='exec_graph_path'Then CanonOpt:='exec_graph_path' Else
 If K='dump_config'Then CanonOpt:='dump_config' Else
 If K='load_config'Then CanonOpt:='load_config' Else
 If(K='weight-format')or(K='weight_format')Then CanonOpt:='weight_format' Else
 If K='dump_output'Then CanonOpt:='dump_output';
End;

{ 0 : valeur obligatoire, 1 : indicateur, 2 : booleen facultatif, 3 : liste }
Function OptKind(Const C:AnsiString):LongInt;
Begin
 If(C='no_warmup')Then OptKind:=1 Else
 If(C='pc')or(C='pcseq')or(C='lfile')or(C='inference_only')or(C='json_stats')Then OptKind:=2 Else
 If C='i'Then OptKind:=3
         Else OptKind:=0;
End;

Function IsBoolWord(Const S:AnsiString):Boolean;
Var
 L:AnsiString;
Begin
 L:=LoStr(S);
 IsBoolWord:=(L='true')or(L='false')or(L='yes')or(L='no')or(L='1')or(L='0');
End;

Function BoolWord(Const S:AnsiString):Boolean;
Var
 L:AnsiString;
Begin
 L:=LoStr(S);
 BoolWord:=(L='true')or(L='yes')or(L='1');
End;

Procedure AddCmd(Const N,V:AnsiString);
Begin
 SetLength(CmdN,Length(CmdN)+1);
 SetLength(CmdV,Length(CmdV)+1);
 CmdN[High(CmdN)]:=N;
 CmdV[High(CmdV)]:=V;
End;

Procedure SetOpt(Const C,V:AnsiString;Const Raw:AnsiString);
Begin
 If C='m'Then OModel:=V Else
 If C='d'Then ODevice:=V Else
 If C='hint'Then Begin
  OHint:=LoStr(V);
  OHintSet:=True;
 End Else
 If C='niter'Then Begin
  If Not IsInt(V)or(ToI(V,-1)<0)Then Die('valeur invalide pour '+Raw+' : '+V);
  ONiter:=ToI(V,-1);
 End Else
 If C='max_irate'Then OMaxIrate:=ToF(V,0) Else
 If C='t'Then Begin
  OTime:=ToF(V,-1);
  If OTime<0 Then Die('valeur invalide pour '+Raw+' : '+V);
 End Else
 If C='api'Then OApi:=LoStr(V) Else
 If C='b'Then Begin
  If Not IsInt(V)or(ToI(V,-1)<0)Then Die('valeur invalide pour '+Raw+' : '+V);
  OBatch:=ToI(V,0);
 End Else
 If C='shape'Then OShape:=V Else
 If C='data_shape'Then ODataShape:=V Else
 If C='layout'Then OLayout:=V Else
 If C='cdir'Then OCdir:=V Else
 If C='nireq'Then Begin
  If Not IsInt(V)or(ToI(V,-1)<0)Then Die('valeur invalide pour '+Raw+' : '+V);
  ONireq:=ToI(V,0);
 End Else
 If C='nstreams'Then ONStreams:=V Else
 If C='nthreads'Then Begin
  If Not IsInt(V)or(ToI(V,-1)<0)Then Die('valeur invalide pour '+Raw+' : '+V);
  ONthreads:=ToI(V,0);
 End Else
 If C='pin'Then OPin:=V Else
 If C='infer_precision'Then OInferPrec:=V Else
 If C='latency_percentile'Then Begin
  If Not IsInt(V)Then Die('valeur invalide pour '+Raw+' : '+V);
  OPercentile:=ToI(V,50);
 End Else
 If C='report_type'Then OReportType:=LoStr(V) Else
 If C='report_folder'Then OReportFolder:=V Else
 If C='pcsort'Then OPcSort:=LoStr(V) Else
 If C='weight_format'Then OWeightFmt:=V Else
 If C='dump_output'Then ODumpOut:=V Else
 If(C='extensions')or(C='c')or(C='load_config')or(C='dump_config')or
   (C='exec_graph_path')or(C='ip')or(C='op')or(C='iop')or
   (C='mean_values')or(C='scale_values')Then
  Warn('option '+Raw+' acceptee puis ignoree par ce clone');
End;

Procedure ParseArgs;
Var
 I,P:LongInt;
 A,K,V,C:AnsiString;
 HasV:Boolean;
 Pend:AnsiString;
 PendV:AnsiString;
Begin
 OModel:='';ODevice:='CPU';OHint:='throughput';OApi:='';OShape:='';ODataShape:='';
 OLayout:='';OCdir:='';OInferPrec:='';OReportType:='';OReportFolder:='';
 OPcSort:='';ODumpOut:='';ONStreams:='';OWeightFmt:='';OPin:='';
 SetLength(OInputs,0);
 ONiter:=-1;OTime:=0;OMaxIrate:=0;OBatch:=0;ONireq:=0;ONthreads:=0;
 OPercentile:=50;OPc:=False;OPcseq:=False;ONoWarmup:=False;OJson:=False;
 OHintSet:=False;OInferOnly:=-1;
 SetLength(CmdN,0);SetLength(CmdV,0);
 If ParamCount=0 Then Begin
  ShowHelp;
  Halt(0);
 End;
 Pend:='';PendV:='';
 I:=1;
 While I<=ParamCount do Begin
  A:=ParamStr(I);
  If IsHelpArg(A)Then Begin
   ShowHelp;
   Halt(0);
  End;
  If(Length(A)>1)and(A[1]='-')and Not(A[2] in ['0'..'9'])Then Begin
   If Pend<>'' Then Begin
    AddCmd(Pend,PendV);
   End;
   Pend:=A;PendV:='';
   K:=A;
   While(K<>'')and(K[1]='-')do Delete(K,1,1);
   HasV:=False;V:='';
   P:=System.Pos('=',K);
   If P>0 Then Begin
    V:=Copy(K,P+1,Length(K));
    K:=Copy(K,1,P-1);
    HasV:=True;
    PendV:=V;
    Pend:=Copy(A,1,System.Pos('=',A)-1);
   End;
   C:=CanonOpt(K);
   If C='' Then Die('option inconnue : '+A+' (voir -h)');
   Case OptKind(C) of
    0:Begin
     If Not HasV Then Begin
      If I>=ParamCount Then Die('l''option '+A+' attend une valeur');
      Inc(I);
      V:=ParamStr(I);
      PendV:=V;
     End;
     SetOpt(C,V,A);
    End;
    1:Begin
     If C='no_warmup'Then ONoWarmup:=True;
    End;
    2:Begin
     If Not HasV and(I<ParamCount)and IsBoolWord(ParamStr(I+1))Then Begin
      Inc(I);
      V:=ParamStr(I);
      PendV:=V;
      HasV:=True;
     End;
     If Not HasV Then V:='true';
     If C='pc'Then OPc:=BoolWord(V) Else
     If C='pcseq'Then OPcseq:=BoolWord(V) Else
     If C='json_stats'Then OJson:=BoolWord(V) Else
     If C='inference_only'Then OInferOnly:=Ord(BoolWord(V));
    End;
    3:Begin
     If HasV Then Begin
      SetLength(OInputs,Length(OInputs)+1);
      OInputs[High(OInputs)]:=V;
     End;
     While(I<ParamCount)and Not((Length(ParamStr(I+1))>1)and(ParamStr(I+1)[1]='-'))do Begin
      Inc(I);
      SetLength(OInputs,Length(OInputs)+1);
      OInputs[High(OInputs)]:=ParamStr(I);
      If PendV<>'' Then PendV:=PendV+' ';
      PendV:=PendV+ParamStr(I);
     End;
     If Length(OInputs)=0 Then Die('l''option '+A+' attend au moins un chemin');
    End;
   End;
  End
   Else
  Die('argument inattendu : '+A+' (voir -h)');
  Inc(I);
 End;
 If Pend<>'' Then AddCmd(Pend,PendV);
End;

{ Verification des parametres (equivalent de parse_and_check_command_line) }
Procedure CheckArgs;
Begin
 If OModel='' Then Die('l''option -m est obligatoire (chemin du modele)');
 If(OPercentile<1)or(OPercentile>100)Then
  Die('la valeur du percentile est incorrecte; plage applicable : [1, 100].');
 If(OHint<>'throughput')and(OHint<>'tput')and(OHint<>'latency')and(OHint<>'none')and
   (OHint<>'cumulative_throughput')and(OHint<>'ctput')Then
  Die('indication de performance incorrecte : '+OHint+'. Utiliser throughput (tput), latency, '+
      'cumulative_throughput (ctput) ou none.');
 If(OHint<>'none')and((ONStreams<>'')or(ONthreads<>0)or(OPin<>''))Then
  Die('-nstreams, -nthreads et -pin sont des options de reglage fin : il faut definir '+
      'explicitement -hint none pour les utiliser (regle de l''interface de benchmark_app).');
 If OApi='' Then Begin
  If OHint='latency' Then OApi:='sync'
                     Else OApi:='async';
 End;
 If(OApi<>'sync')and(OApi<>'async')Then Die('-api doit valoir sync ou async (recu : '+OApi+')');
 If(OApi='sync')and(OTime=0)and(ONiter>0)and(ONireq>ONiter)Then
  Die('le nombre de requetes d''inference doit etre inferieur ou egal au nombre d''iterations en mode sync.');
 If OReportType<>'' Then
  If(OReportType<>'no_counters')and(OReportType<>'average_counters')and
    (OReportType<>'detailed_counters')Then
   Die('-report_type invalide : '+OReportType);
 If OPcSort<>'' Then
  If(OPcSort<>'no_sort')and(OPcSort<>'sort')and(OPcSort<>'simple_sort')Then
   Die('-pcsort invalide : '+OPcSort);
 If(OReportFolder<>'')and(OReportType='')Then OReportType:='no_counters';
End;

{ ------------------------------------------------------------------ }
{ Affichage                                                           }
{ ------------------------------------------------------------------ }

Const
 StepNames:Array[1..11] of AnsiString=(
  'Parsing and validating input arguments','Loading OpenVINO Runtime',
  'Setting device configuration','Reading model files',
  'Resizing model to match image sizes and given batch',
  'Configuring input of the model','Loading the model to the device',
  'Querying optimal runtime parameters',
  'Creating infer requests and preparing input tensors','Measuring performance',
  'Dumping statistics report');

Procedure Step(N:LongInt;Const Extra:AnsiString);
Begin
 If Extra='' Then WriteLn('[Step ',N,'/11] ',StepNames[N])
             Else WriteLn('[Step ',N,'/11] ',StepNames[N],' (',Extra,')');
End;

Function PadR(Const S:AnsiString;N:LongInt):AnsiString;
Var
 R:AnsiString;
Begin
 R:=S;
 While Length(R)<N do R:=R+' ';
 PadR:=R;
End;

Function Fmt3(X:Double):AnsiString;
Begin
 Fmt3:=FStr(X,3);
End;

{ Nombre de processeurs logiques }
Function CpuCount:LongInt;
Var
 S:AnsiString;
 T:Text;
 Line:AnsiString;
 N:LongInt;
Begin
 S:=GetEnv('NUMBER_OF_PROCESSORS');
 If IsInt(S)and(ToI(S,0)>0)Then Begin
  CpuCount:=ToI(S,1);
  Exit;
 End;
 N:=0;
 Assign(T,'/proc/cpuinfo');
 {$I-}Reset(T);{$I+}
 If IOResult=0 Then Begin
  While Not Eof(T) do Begin
   {$I-}ReadLn(T,Line);{$I+}
   If IOResult<>0 Then Break;
   If StartsWith(Line,'processor')Then Inc(N);
  End;
  {$I-}Close(T);{$I+}
  If IOResult<>0 Then ;
 End;
 If N<1 Then N:=1;
 CpuCount:=N;
End;

Function LayoutDisplay(Const L:AnsiString):AnsiString;
Var
 I:LongInt;
 R:AnsiString;
Begin
 If L='' Then Begin
  LayoutDisplay:='[...]';
  Exit;
 End;
 R:='[';
 I:=1;
 While I<=Length(L) do Begin
  If R<>'[' Then R:=R+',';
  If Copy(L,I,3)='...'Then Begin
   R:=R+'...';
   Inc(I,3);
  End
   Else
  Begin
   R:=R+L[I];
   Inc(I);
  End;
 End;
 LayoutDisplay:=R+']';
End;

{ ------------------------------------------------------------------ }
{ Entrees du modele                                                   }
{ ------------------------------------------------------------------ }

Type
 TShapeList = Array of TIntArr;

 TInInfo = Record
  Name,NodeName:AnsiString;
  Prec:LongInt;
  PShape:TIntArr;         { forme partielle (-1 : dynamique) }
  Layout:AnsiString;
  Shapes:TShapeList;      { formes des donnees, une par groupe }
  Dynamic:Boolean;
  Files:TStrArr;
 End;

Var
 InInfo:Array of TInInfo;
 NInputs:LongInt;
 NCases:LongInt;
 CaseBatch:TIntArr;
 InData:Array of Array of TTensor;    { [groupe][entree] }

Function FirstName(Const Names,Def:AnsiString):AnsiString;
Var
 P:LongInt;
Begin
 If Names='' Then Begin
  FirstName:=Def;
  Exit;
 End;
 P:=System.Pos(',',Names);
 If P>0 Then FirstName:=Copy(Names,1,P-1)
        Else FirstName:=Names;
End;

Function ShapeKnown(Const D:TIntArr):Boolean;
Var
 I:LongInt;
Begin
 ShapeKnown:=True;
 For I:=0 to High(D) do If D[I]<0 Then ShapeKnown:=False;
End;

Procedure PrintIO;
Var
 I:LongInt;
 L,Src:LongInt;
 Dm:TIntArr;
 Nm,Node:AnsiString;
Begin
 Info('Model inputs:');
 For I:=0 to NInputs-1 do
  Info('    '+InInfo[I].Name+' (node: '+InInfo[I].NodeName+') : '+ElemName[InInfo[I].Prec]+
       ' / '+LayoutDisplay(InInfo[I].Layout)+' / '+DimsToStr(InInfo[I].PShape));
 Info('Model outputs:');
 For I:=0 to High(OutLayers) do Begin
  L:=OutLayers[I];
  If Layers[L].NIn<1 Then Continue;
  Src:=Layers[L].SrcL[0];
  Nm:=FirstName(Layers[Src].Outs[Layers[L].SrcP[0]].Names,Layers[Src].Name);
  Node:=Layers[Src].Name;
  Dm:=Layers[Src].Outs[Layers[L].SrcP[0]].Dims;
  Info('    '+Nm+' (node: '+Node+') : '+ElemName[Layers[Src].Outs[Layers[L].SrcP[0]].Prec]+
       ' / [...] / '+DimsToStr(Dm));
 End;
End;

{ Decoupe "nom[a,b][c],nom2[d]" en noms et contenus entre crochets }
Procedure ScanSpec(Const S:AnsiString;Var Names:TStrArr;Var Cont:Array of TStrArr;Var N:LongInt);
Var
 P,Q,Len:LongInt;
 Nm:AnsiString;
Begin
 N:=0;
 Len:=Length(S);
 P:=1;
 While P<=Len do Begin
  While(P<=Len)and(S[P] in [',',' '])do Inc(P);
  If P>Len Then Break;
  Q:=P;
  While(Q<=Len)and(S[Q]<>'[')and(S[Q]<>',')do Inc(Q);
  Nm:=TrimStr(Copy(S,P,Q-P));
  If(Q>Len)or(S[Q]<>'[')Then Die('specification invalide : '+S);
  If N>High(Cont)Then Die('trop d''entrees dans la specification : '+S);
  SetLength(Names,N+1);
  Names[N]:=Nm;
  SetLength(Cont[N],0);
  P:=Q;
  While(P<=Len)and(S[P]='[')do Begin
   Q:=P+1;
   While(Q<=Len)and(S[Q]<>']')do Inc(Q);
   If Q>Len Then Die('crochet non ferme dans : '+S);
   SetLength(Cont[N],Length(Cont[N])+1);
   Cont[N][High(Cont[N])]:=Copy(S,P+1,Q-P-1);
   P:=Q+1;
  End;
  Inc(N);
 End;
End;

Function ParseDimsSpec(Const S:AnsiString):TIntArr;
Var
 Parts:TStrArr;
 I:LongInt;
 T:AnsiString;
Begin
 SetLength(ParseDimsSpec,0);
 T:=TrimStr(S);
 If T='' Then Exit;
 Parts:=SplitStr(T,',');
 SetLength(ParseDimsSpec,Length(Parts));
 For I:=0 to High(Parts) do Begin
  T:=TrimStr(Parts[I]);
  If IsInt(T)and(ToI(T,-1)>=0)Then ParseDimsSpec[I]:=ToI(T,-1)
                              Else ParseDimsSpec[I]:=-1;
 End;
End;

{ Indice de l'entree designee par un nom (nom d'entree ou du noeud), -1 si absente }
Function FindInput(Const Nm:AnsiString):LongInt;
Var
 I:LongInt;
Begin
 FindInput:=-1;
 For I:=0 to NInputs-1 do
  If(InInfo[I].Name=Nm)or(InInfo[I].NodeName=Nm)Then Begin
   FindInput:=I;
   Exit;
  End;
End;

Function ResolveSpecName(Const Nm,What:AnsiString):LongInt;
Begin
 If Nm='' Then Begin
  If NInputs<>1 Then
   Die('le nom de l''entree est obligatoire dans '+What+' quand le modele a plusieurs entrees');
  ResolveSpecName:=0;
  Exit;
 End;
 ResolveSpecName:=FindInput(Nm);
 If ResolveSpecName<0 Then Die('l''entree '''+Nm+''' de '+What+' n''existe pas dans le modele');
End;

Function LayoutBatchIndex(Const L:AnsiString):LongInt;
Var
 P:LongInt;
Begin
 P:=System.Pos('N',L);
 If P>0 Then LayoutBatchIndex:=P-1
        Else LayoutBatchIndex:=-1;
End;

Procedure LoadInputInfo;
Var
 I,K:LongInt;
 Pt:Integer;
 PN:TStrArr;
 PC:Array of TStrArr;
 N:LongInt;
Begin
 NInputs:=Length(InLayers);
 SetLength(InInfo,NInputs);
 For I:=0 to NInputs-1 do Begin
  K:=InLayers[I];
  If Length(Layers[K].Outs)<1 Then Die('entree sans sortie : '+Layers[K].Name);
  InInfo[I].Name:=FirstName(Layers[K].Outs[0].Names,Layers[K].Name);
  InInfo[I].NodeName:=Layers[K].Name;
  Pt:=Layers[K].Outs[0].Prec;
  If Pt<0 Then Pt:=PrecFromName(Attr(Layers[K].Attrs,'element_type'));
  If Pt<0 Then Die('type inconnu pour l''entree '+InInfo[I].Name);
  InInfo[I].Prec:=Pt;
  If Length(Layers[K].Outs[0].Dims)>0 Then InInfo[I].PShape:=CopyDims(Layers[K].Outs[0].Dims)
  Else InInfo[I].PShape:=ParseShapeAttr(Attr(Layers[K].Attrs,'shape'));
  InInfo[I].Layout:='';
  SetLength(InInfo[I].Shapes,0);
  SetLength(InInfo[I].Files,0);
 End;
 { -layout }
 If OLayout<>'' Then Begin
  SetLength(PC,NInputs+1);
  ScanSpec(OLayout,PN,PC,N);
  For I:=0 to N-1 do Begin
   K:=ResolveSpecName(PN[I],'-layout');
   If Length(PC[I])>0 Then InInfo[K].Layout:=ReplaceAll(ReplaceAll(PC[I][0],',',''),' ','');
  End;
 End;
End;

{ ------------------------------------------------------------------ }
{ Formes des entrees (etapes 5 et 6)                                  }
{ ------------------------------------------------------------------ }

Var
 Reshaped:Boolean;
 BatchStr:AnsiString;
 ModelBatch:LongInt;         { -1 : dynamique }

Function ShapeCompat(Const Part,Data:TIntArr):Boolean;
Var
 I:LongInt;
Begin
 ShapeCompat:=False;
 If Length(Part)<>Length(Data)Then Exit;
 For I:=0 to High(Part) do
  If(Part[I]>=0)and(Part[I]<>Data[I])Then Exit;
 ShapeCompat:=True;
End;

Procedure ConfigureShapes;
Var
 I,K,N,G,J,Bi:LongInt;
 PN,DN:TStrArr;
 PC,DC:Array of TStrArr;
 DG:Array of TShapeList;
 D:TIntArr;
 BatchFound:Boolean;
 B:LongInt;
 Msg:AnsiString;
 T0:Double;
Begin
 Reshaped:=False;
 If OShape<>'' Then Begin
  SetLength(PC,NInputs+1);
  ScanSpec(OShape,PN,PC,N);
  For I:=0 to N-1 do Begin
   K:=ResolveSpecName(PN[I],'-shape');
   If Length(PC[I])<1 Then Die('forme manquante dans -shape');
   InInfo[K].PShape:=ParseDimsSpec(PC[I][0]);
   Reshaped:=True;
  End;
 End;
 { formes des donnees }
 SetLength(DG,NInputs);
 For I:=0 to NInputs-1 do SetLength(DG[I],0);
 If ODataShape<>'' Then Begin
  SetLength(DC,NInputs+1);
  ScanSpec(ODataShape,DN,DC,N);
  For I:=0 to N-1 do Begin
   K:=ResolveSpecName(DN[I],'-data_shape');
   SetLength(DG[K],Length(DC[I]));
   For G:=0 to High(DC[I]) do Begin
    D:=ParseDimsSpec(DC[I][G]);
    If Not ShapeKnown(D)Then Die('une forme de donnees doit etre statique : ['+DC[I][G]+']');
    DG[K][G]:=D;
   End;
  End;
 End;
 { taille du lot }
 If OBatch<>0 Then Begin
  If ODataShape<>'' Then
   Warn('Batch size will be ignored. Provide batch deminsion in data_shape parameter.')
  Else Begin
   BatchFound:=False;
   For I:=0 to NInputs-1 do Begin
    Bi:=-1;
    If System.Pos('N',InInfo[I].Layout)>0 Then Bi:=LayoutBatchIndex(InInfo[I].Layout) Else
    If InInfo[I].Layout='' Then Begin
     If(Length(InInfo[I].PShape)>0)and((InInfo[I].PShape[0]<0)or(InInfo[I].PShape[0]<=1))Then Begin
      Warn('Batch dimension is not specified for input '''+InInfo[I].Name+
           '''. The first dimension will be interpreted as batch size.');
      Bi:=0;
      InInfo[I].Layout:='N...';
     End;
    End;
    If(Bi>=0)and(Bi<Length(InInfo[I].PShape))Then Begin
     If InInfo[I].PShape[Bi]<>OBatch Then Begin
      InInfo[I].PShape[Bi]:=OBatch;
      Reshaped:=True;
     End;
     BatchFound:=True;
    End
     Else
    If(Bi<0)and Not BatchFound and(I=NInputs-1)Then
     Die('-b est precise mais aucune entree n''a de dimension de lot (B) dans sa disposition; '+
         'precisez la disposition avec -layout.');
   End;
  End;
 End;
 { taille de lot du modele }
 ModelBatch:=-2;
 For I:=0 to NInputs-1 do Begin
  Bi:=-1;
  If System.Pos('N',InInfo[I].Layout)>0 Then Bi:=LayoutBatchIndex(InInfo[I].Layout);
  If(Bi>=0)and(Bi<Length(InInfo[I].PShape))Then Begin
   If ModelBatch=-2 Then ModelBatch:=InInfo[I].PShape[Bi] Else
   If ModelBatch<>InInfo[I].PShape[Bi]Then
    Die('Can''t determine batch size: batch is different for different inputs!');
  End;
 End;
 If ModelBatch=-2 Then ModelBatch:=1;
 If ModelBatch<0 Then BatchStr:='?'
                 Else BatchStr:=IStr(ModelBatch);
 Info('Model batch size: '+BatchStr);
 If Reshaped Then Begin
  Msg:='';
  For I:=0 to NInputs-1 do Begin
   If I>0 Then Msg:=Msg+', ';
   Msg:=Msg+''''+InInfo[I].Name+''': '+DimsToStr(InInfo[I].PShape);
  End;
  Info('Reshaping model: '+Msg);
  T0:=NowMs;
  Info('Reshape model took '+FStr(NowMs-T0,2)+' ms');
 End;
 { formes finales des donnees }
 For I:=0 to NInputs-1 do Begin
  InInfo[I].Dynamic:=Not ShapeKnown(InInfo[I].PShape);
  If InInfo[I].Dynamic Then Begin
   If Length(DG[I])>0 Then Begin
    SetLength(InInfo[I].Shapes,Length(DG[I]));
    For G:=0 to High(DG[I]) do Begin
     If Not ShapeCompat(InInfo[I].PShape,DG[I][G])Then
      Die('la forme de donnees '+DimsToStr(DG[I][G])+' donnee pour l''entree '''+InInfo[I].Name+
          ''' n''est pas compatible avec la forme partielle '+DimsToStr(InInfo[I].PShape));
     InInfo[I].Shapes[G]:=DG[I][G];
    End;
   End
    Else
   Begin
    SetLength(D,Length(InInfo[I].PShape));
    Bi:=-1;
    If System.Pos('N',InInfo[I].Layout)>0 Then Bi:=LayoutBatchIndex(InInfo[I].Layout);
    For J:=0 to High(D) do Begin
     If InInfo[I].PShape[J]>=0 Then D[J]:=InInfo[I].PShape[J] Else
     If(J=0)or(J=Bi)Then D[J]:=1
                    Else D[J]:=DefaultDyn;
    End;
    If Length(InInfo[I].Files)=0 Then
     Warn('L''entree '''+InInfo[I].Name+''' est dynamique '+DimsToStr(InInfo[I].PShape)+
          ' et aucun -data_shape n''est donne : forme par defaut '+DimsToStr(D)+' utilisee.');
    SetLength(InInfo[I].Shapes,1);
    InInfo[I].Shapes[0]:=D;
   End;
  End
   Else
  Begin
   SetLength(InInfo[I].Shapes,1);
   InInfo[I].Shapes[0]:=CopyDims(InInfo[I].PShape);
   If Length(DG[I])>0 Then
    Warn('Input '''+InInfo[I].Name+''' has static shape. Provided data shapes for this input will be ignored.');
  End;
 End;
End;

{ ------------------------------------------------------------------ }
{ Donnees d'entree                                                    }
{ ------------------------------------------------------------------ }

Var
 RndSeed:LongWord;

Function RndNext:Double;
Begin
 RndSeed:=RndSeed xor(RndSeed shl 13);
 RndSeed:=RndSeed xor(RndSeed shr 17);
 RndSeed:=RndSeed xor(RndSeed shl 5);
 RndNext:=RndSeed/4294967296.0;
End;

Function RandTensor(Prec:LongInt;Const Dims:TIntArr):TTensor;
Var
 I,N:LongInt;
 R:TTensor;
Begin
 R:=NewTensor(Prec,Dims);
 N:=Length(R.D);
 For I:=0 to N-1 do Begin
  If(Prec=PR_F32)or(Prec=PR_F16)or(Prec=PR_BF16)or(Prec=PR_F64)Then
   R.D[I]:=RndNext
  Else If Prec=PR_BOOL Then R.D[I]:=Trunc(RndNext*2)
  Else If(Prec=PR_U4)or(Prec=PR_I4)Then R.D[I]:=Trunc(RndNext*16)
  Else R.D[I]:=Trunc(RndNext*256);
 End;
 If N>0 Then QuantArr(Prec,@R.D[0],N);
 RandTensor:=R;
End;

Function ReadBytes(Const P:AnsiString):TByteArr;
Var
 F:File;
 N:Int64;
 R:TByteArr;
Begin
 SetLength(R,0);
 Assign(F,P);
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0 Then Die('impossible d''ouvrir le fichier '+P);
 N:=FileSize(F);
 SetLength(R,N);
 If N>0 Then Begin
  {$I-}BlockRead(F,R[0],N);{$I+}
  If IOResult<>0 Then Die('erreur de lecture de '+P);
 End;
 {$I-}Close(F);{$I+}
 If IOResult<>0 Then ;
 ReadBytes:=R;
End;

Function NpyPrec(Const D:AnsiString):LongInt;
Var
 S:AnsiString;
Begin
 S:=D;
 If(S<>'')and(S[1] in ['<','>','|','='])Then Begin
  If S[1]='>'Then Die('tableau numpy en gros-boutiste non pris en charge : '+D);
  Delete(S,1,1);
 End;
 NpyPrec:=-1;
 If S='f4'Then NpyPrec:=PR_F32 Else
 If S='f8'Then NpyPrec:=PR_F64 Else
 If S='f2'Then NpyPrec:=PR_F16 Else
 If S='i8'Then NpyPrec:=PR_I64 Else
 If S='i4'Then NpyPrec:=PR_I32 Else
 If S='i2'Then NpyPrec:=PR_I16 Else
 If S='i1'Then NpyPrec:=PR_I8 Else
 If S='u8'Then NpyPrec:=PR_U64 Else
 If S='u4'Then NpyPrec:=PR_U32 Else
 If S='u2'Then NpyPrec:=PR_U16 Else
 If S='u1'Then NpyPrec:=PR_U8 Else
 If S='b1'Then NpyPrec:=PR_BOOL;
End;

{ Charge un fichier .npy : forme et valeurs }
Function LoadNpy(Const Path:AnsiString):TTensor;
Var
 S:AnsiString;
 Bytes:TByteArr;
 HL,Start,P,Q,I:LongInt;
 H,Ds,Sh:AnsiString;
 Prec:LongInt;
 Parts:TStrArr;
 Dims:TIntArr;
 R:TTensor;
Begin
 S:=ReadWholeFile(Path);
 If(Length(S)<10)or(S[1]<>#$93)or(Copy(S,2,5)<>'NUMPY')Then Die('fichier .npy invalide : '+Path);
 If Ord(S[7])=1 Then Begin
  HL:=Ord(S[9])+256*Ord(S[10]);
  Start:=11;
 End
  Else
 Begin
  HL:=Ord(S[9])+256*Ord(S[10])+65536*Ord(S[11]);
  Start:=13;
 End;
 H:=Copy(S,Start,HL);
 P:=FindStr('''descr'':',H,1);
 If P=0 Then Die('en-tete .npy sans descr : '+Path);
 P:=P+8;
 While(P<=Length(H))and(H[P]<>'''')do Inc(P);
 Q:=P+1;
 While(Q<=Length(H))and(H[Q]<>'''')do Inc(Q);
 Ds:=Copy(H,P+1,Q-P-1);
 Prec:=NpyPrec(Ds);
 If Prec<0 Then Die('type numpy non pris en charge ('+Ds+') dans '+Path);
 If FindStr('''fortran_order'': True',H,1)>0 Then Die('ordre Fortran non pris en charge : '+Path);
 P:=FindStr('''shape'':',H,1);
 If P=0 Then Die('en-tete .npy sans shape : '+Path);
 P:=P+8;
 While(P<=Length(H))and(H[P]<>'(')do Inc(P);
 Q:=P+1;
 While(Q<=Length(H))and(H[Q]<>')')do Inc(Q);
 Sh:=TrimStr(Copy(H,P+1,Q-P-1));
 SetLength(Dims,0);
 If Sh<>'' Then Begin
  Parts:=SplitStr(Sh,',');
  For I:=0 to High(Parts) do
   If TrimStr(Parts[I])<>'' Then Begin
    SetLength(Dims,Length(Dims)+1);
    Dims[High(Dims)]:=ToI(Parts[I],0);
   End;
 End;
 R.Prec:=Prec;
 R.Dims:=Dims;
 SetLength(R.D,0);
 P:=Length(S)-(Start+HL)+1;
 If P<(Int64(CountOf(Dims))*PrecBits[Prec]+7)div 8 Then Die('donnees .npy tronquees : '+Path);
 SetLength(R.Raw,P);
 If P>0 Then Move(S[Start+HL],R.Raw[0],P);
 Mat(R);
 LoadNpy:=R;
End;

{ Fichiers d'un dossier (.bin et .npy), tries }
Procedure ListDir(Const Dir:AnsiString;Var L:TStrArr);
Var
 SR:SearchRec;
 N,I,J:LongInt;
 T:AnsiString;
Begin
 FindFirst(JoinPath(Dir,'*'),AnyFile,SR);
 While DosError=0 do Begin
  If((SR.Attr and Directory)=0)and((FileExt(SR.Name)='.bin')or(FileExt(SR.Name)='.npy'))Then Begin
   N:=Length(L);
   SetLength(L,N+1);
   L[N]:=JoinPath(Dir,SR.Name);
  End;
  FindNext(SR);
 End;
 FindClose(SR);
 For I:=1 to High(L) do Begin
  T:=L[I];
  J:=I-1;
  While(J>=0)and(L[J]>T)do Begin
   L[J+1]:=L[J];
   Dec(J);
  End;
  L[J+1]:=T;
 End;
End;

{ Repartit les fichiers de -i entre les entrees }
Procedure CollectInputFiles;
Var
 T,P,I,K,Q:LongInt;
 Parts:TStrArr;
 Part,Path,Cur:AnsiString;
 Cur_:LongInt;
 Un:TStrArr;
 Fs:TStrArr;

 Procedure AddTo(Idx:LongInt;Const F:AnsiString);
 Begin
  If Idx<0 Then Begin
   SetLength(Un,Length(Un)+1);
   Un[High(Un)]:=F;
  End
   Else
  Begin
   SetLength(InInfo[Idx].Files,Length(InInfo[Idx].Files)+1);
   InInfo[Idx].Files[High(InInfo[Idx].Files)]:=F;
  End;
 End;

Begin
 SetLength(Un,0);
 For T:=0 to High(OInputs) do Begin
  Parts:=SplitStr(OInputs[T],',');
  Cur_:=-1;
  For P:=0 to High(Parts) do Begin
   Part:=TrimStr(Parts[P]);
   If Part='' Then Continue;
   Path:=Part;
   Q:=System.Pos(':',Part);
   If Q>1 Then Begin
    K:=FindInput(Copy(Part,1,Q-1));
    If K>=0 Then Begin
     Cur_:=K;
     Path:=Copy(Part,Q+1,Length(Part));
    End;
   End;
   If Path='' Then Continue;
   SetLength(Fs,0);
   If DirExists(Path)Then ListDir(Path,Fs) Else
   If FileExists(Path)Then Begin
    SetLength(Fs,1);
    Fs[0]:=Path;
   End
    Else
   Die('le fichier ou dossier d''entree '''+Path+''' n''existe pas');
   For I:=0 to High(Fs) do Begin
    If(FileExt(Fs[I])<>'.bin')and(FileExt(Fs[I])<>'.npy')Then
     Die('type de fichier d''entree non pris en charge : '+Fs[I]+' (.bin et .npy seulement)');
    AddTo(Cur_,Fs[I]);
   End;
  End;
 End;
 If Length(Un)>0 Then Begin
  If NInputs=1 Then Begin
   For I:=0 to High(Un) do AddTo(0,Un[I]);
  End
   Else
  For I:=0 to High(Un) do AddTo(I mod NInputs,Un[I]);
 End;
End;

{ Construit les tenseurs d'entree de chaque groupe (etape 9) }
Procedure BuildInputs;
Var
 I,G,N,K,J:LongInt;
 T:TTensor;
 Path:AnsiString;
 Need:Int64;
 Bytes:TByteArr;
 Sh:TIntArr;
 Bi:LongInt;
Begin
 NCases:=1;
 For I:=0 to NInputs-1 do Begin
  If Length(InInfo[I].Shapes)>NCases Then NCases:=Length(InInfo[I].Shapes);
  If Length(InInfo[I].Files)>NCases Then NCases:=Length(InInfo[I].Files);
 End;
 For I:=0 to NInputs-1 do
  If(Length(InInfo[I].Shapes)>1)and(Length(InInfo[I].Shapes)<>NCases)Then
   Die('les entrees ont un nombre different de formes de donnees');
 SetLength(InData,NCases);
 For G:=0 to NCases-1 do SetLength(InData[G],NInputs);
 For I:=0 to NInputs-1 do Begin
  RndSeed:=2463534242+LongWord(I)*7919;
  If Length(InInfo[I].Files)=0 Then Begin
   Warn('No input files were given for input '''+InInfo[I].Name+
        '''!. This input will be filled with random values!');
   Info('Fill input '''+InInfo[I].Name+''' with random values ');
  End;
 End;
 For I:=0 to NInputs-1 do Begin
  RndSeed:=2463534242+LongWord(I)*7919;
  For G:=0 to NCases-1 do Begin
   Sh:=InInfo[I].Shapes[G mod Length(InInfo[I].Shapes)];
   If Length(InInfo[I].Files)=0 Then
    InData[G][I]:=RandTensor(InInfo[I].Prec,Sh)
   Else Begin
    Path:=InInfo[I].Files[G mod Length(InInfo[I].Files)];
    If FileExt(Path)='.npy'Then Begin
     Info('Prepare numpy array '+Path);
     T:=LoadNpy(Path);
     If InInfo[I].Dynamic Then Begin
      If Not ShapeCompat(InInfo[I].PShape,T.Dims)Then
       Die('la forme '+DimsToStr(T.Dims)+' du fichier '+Path+' n''est pas compatible avec '+
           DimsToStr(InInfo[I].PShape));
      If Length(InInfo[I].Shapes)<NCases Then Begin
       Sh:=InInfo[I].Shapes[0];
       SetLength(InInfo[I].Shapes,NCases);
       For K:=0 to NCases-1 do InInfo[I].Shapes[K]:=CopyDims(Sh);
      End;
      InInfo[I].Shapes[G]:=CopyDims(T.Dims);
     End
      Else
     If CountOf(T.Dims)<>CountOf(Sh)Then
      Die('le fichier '+Path+' contient '+IStr(CountOf(T.Dims))+' elements, l''entree '''+
          InInfo[I].Name+''' en attend '+IStr(CountOf(Sh)));
     If Not InInfo[I].Dynamic Then T.Dims:=CopyDims(Sh);
     T.Prec:=InInfo[I].Prec;
     QuantArr(T.Prec,@T.D[0],Length(T.D));
     InData[G][I]:=T;
    End
     Else
    Begin
     Info('Prepare binary file '+Path);
     Bytes:=ReadBytes(Path);
     Need:=(Int64(CountOf(Sh))*PrecBits[InInfo[I].Prec]+7)div 8;
     If Length(Bytes)<>Need Then
      Die('la taille du fichier '+Path+' ('+IStr(Length(Bytes))+' octets) ne correspond pas a l''entree '''+
          InInfo[I].Name+''' ('+IStr(Need)+' octets pour '+DimsToStr(Sh)+
          '); precisez la forme avec -data_shape ou -shape');
     T.Prec:=InInfo[I].Prec;
     T.Dims:=CopyDims(Sh);
     SetLength(T.D,0);
     T.Raw:=Bytes;
     Mat(T);
     InData[G][I]:=T;
    End;
   End;
  End;
 End;
 { taille de lot de chaque groupe }
 SetLength(CaseBatch,NCases);
 For G:=0 to NCases-1 do Begin
  CaseBatch[G]:=1;
  If ModelBatch>=0 Then CaseBatch[G]:=ModelBatch Else
  For I:=0 to NInputs-1 do Begin
   Bi:=-1;
   If System.Pos('N',InInfo[I].Layout)>0 Then Bi:=LayoutBatchIndex(InInfo[I].Layout);
   If(Bi>=0)and(Bi<Length(InData[G][I].Dims))Then Begin
    CaseBatch[G]:=InData[G][I].Dims[Bi];
    Break;
   End;
  End;
  If CaseBatch[G]<1 Then CaseBatch[G]:=1;
 End;
End;

{ ------------------------------------------------------------------ }
{ Boucle de mesure                                                    }
{ ------------------------------------------------------------------ }

Var
 Ctxs:Array of TCtx;
 NWork:LongInt;
 GTicket,GNiter:LongInt;
 GDurMs,GStart,GEnd,GMaxRate:Double;
 GFull:Boolean;

Procedure SetInputs(Var C:TCtx;Cs:LongInt;Copy_:Boolean);
Var
 I:LongInt;
Begin
 For I:=0 to NInputs-1 do
  If Copy_ Then C.Ins[I]:=CopyTensor(InData[Cs][I])
           Else C.Ins[I]:=InData[Cs][I];
End;

Function WorkerMain(P:Pointer):PtrInt;
Var
 C:PCtx;
 N,Cs:LongInt;
 T0,T1,Due:Double;
Begin
 C:=PCtx(P);
 While True do Begin
  N:=InterlockedIncrement(GTicket);
  If Not((N<=GNiter)or((GDurMs>0)and(NowMs-GStart<GDurMs)))Then Break;
  Cs:=(N-1)mod NCases;
  If GFull Then SetInputs(C^,Cs,True)
  Else If NCases>1 Then SetInputs(C^,Cs,False);
  T0:=NowMs;
  RunInference(C^);
  T1:=NowMs;
  AddLatency(C^,T1-T0);
  C^.Frames:=C^.Frames+CaseBatch[Cs];
  If GMaxRate>0 Then Begin
   Due:=GStart+C^.Frames/(GMaxRate/NWork)*1000.0;
   While NowMs<Due do ;
  End;
 End;
 InterlockedIncrement(C^.Done);
 WorkerMain:=0;
End;

Procedure RunWorkers;
{$IFDEF THREADS}
Var
 I:LongInt;
 Hs:Array of TThreadID;
Begin
 GTicket:=0;
 GStart:=NowMs;
 If NWork>1 Then Begin
  SetLength(Hs,NWork);
  For I:=1 to NWork-1 do Hs[I]:=BeginThread(@WorkerMain,@Ctxs[I]);
  WorkerMain(@Ctxs[0]);
  For I:=1 to NWork-1 do Begin
   WaitForThreadTerminate(Hs[I],0);
   While InterlockedExchangeAdd(Ctxs[I].Done,0)=0 do ;
   CloseThread(Hs[I]);
  End;
 End
  Else WorkerMain(@Ctxs[0]);
 GEnd:=NowMs;
End;
{$ELSE}
Begin
 GTicket:=0;
 GStart:=NowMs;
 WorkerMain(@Ctxs[0]);
 GEnd:=NowMs;
End;
{$ENDIF}

{ Tri par tas }
Procedure HeapSort(Var A:TDblArr;N:LongInt);
 Procedure Sift(Start,Stop:LongInt);
 Var
  Root,Child:LongInt;
  T:Double;
 Begin
  Root:=Start;
  While Root*2+1<=Stop do Begin
   Child:=Root*2+1;
   If(Child+1<=Stop)and(A[Child]<A[Child+1])Then Inc(Child);
   If A[Root]<A[Child]Then Begin
    T:=A[Root];A[Root]:=A[Child];A[Child]:=T;
    Root:=Child;
   End
    Else Exit;
  End;
 End;
Var
 I:LongInt;
 T:Double;
Begin
 If N<2 Then Exit;
 For I:=(N-2)div 2 downto 0 do Sift(I,N-1);
 For I:=N-1 downto 1 do Begin
  T:=A[0];A[0]:=A[I];A[I]:=T;
  Sift(0,I-1);
 End;
End;

{ Latence affichee en us si la latence moyenne est inferieure a 1 ms }
Function ConsoleLatency(V,Avg:Double):AnsiString;
Begin
 If Avg<1.0 Then ConsoleLatency:=FStr(V*1000.0,2)+' us'
            Else ConsoleLatency:=FStr(V,2)+' ms';
End;

{ ------------------------------------------------------------------ }
{ Compteurs de performance et rapports                                }
{ ------------------------------------------------------------------ }

Function LayerStatus(LI:LongInt):AnsiString;
Begin
 If IsMetaOp(Layers[LI].Op)Then LayerStatus:='Status.NOT_RUN'
                           Else LayerStatus:='Status.EXECUTED';
End;

Function LayerExecType(LI:LongInt):AnsiString;
Var
 P:LongInt;
Begin
 If IsMetaOp(Layers[LI].Op)Then Begin
  LayerExecType:='unknown_f32';
  Exit;
 End;
 P:=PR_F32;
 If(Length(Layers[LI].Outs)>0)and(Layers[LI].Outs[0].Prec>=0)Then P:=Layers[LI].Outs[0].Prec;
 LayerExecType:='pascal_ref_'+ElemName[P];
End;

Function CutName(Const S:AnsiString):AnsiString;
Begin
 If Length(S)>=20 Then CutName:=Copy(S,1,16)+'...'
                  Else CutName:=S;
End;

{ Imprime les compteurs de la derniere inference de chaque requete }
Procedure PrintCounters(Const SortMode:AnsiString);
Var
 K,I,J,P,N:LongInt;
 Idx:TIntArr;
 T:Double;
 Total,Cpu,Pc,Tot:Double;
 Sorted:Boolean;
 Pct:AnsiString;
 Tmp:LongInt;
Begin
 Sorted:=SortMode<>'';
 For K:=0 to Length(Ctxs)-1 do Begin
  SetLength(Idx,0);
  N:=0;
  Total:=0;
  For I:=0 to NOrder-1 do Total:=Total+Ctxs[K].Times[Order[I]];
  For I:=0 to NOrder-1 do Begin
   If Layers[Order[I]].Op=OP_CONST Then Continue;
   If(SortMode='simple_sort')and IsMetaOp(Layers[Order[I]].Op)Then Continue;
   SetLength(Idx,N+1);
   Idx[N]:=Order[I];
   Inc(N);
  End;
  If(SortMode='sort')or(SortMode='simple_sort')Then
   For I:=1 to N-1 do Begin
    Tmp:=Idx[I];
    J:=I-1;
    While(J>=0)and(Ctxs[K].Times[Idx[J]]<Ctxs[K].Times[Tmp])do Begin
     Idx[J+1]:=Idx[J];
     Dec(J);
    End;
    Idx[J+1]:=Tmp;
   End;
  If Sorted Then Info('Performance counts sorted for '+IStr(K)+'-th infer request')
            Else Info('Performance counts for '+IStr(K)+'-th infer request');
  Pc:=0;
  For I:=0 to N-1 do Begin
   P:=Idx[I];
   T:=Ctxs[K].Times[P];
   Write(PadR(CutName(Layers[P].Name),20),' ',PadR(LayerStatus(P),20),' layerType: ',
         PadR(CutName(Layers[P].Typ),20),' execType: ',PadR(LayerExecType(P),20),
         ' realTime (ms): ',PadR(Fmt3(T),10),' cpuTime (ms): ',PadR(Fmt3(T),10));
   If Sorted Then Begin
    If Total>0 Then Tot:=Int(T/Total*10000+0.5)/100
               Else Tot:=0;
    Pc:=Pc+Tot;
    If Tot=0 Then Pct:='N/A'
             Else Pct:=FStr(Tot,2);
    Write('proportion: ',PadR(Pct+'%',8));
   End;
   WriteLn;
  End;
  If Sorted Then Begin
   WriteLn('Total time:       ',Fmt3(Total),' milliseconds');
   WriteLn('Total CPU time:   ',Fmt3(Total),' milliseconds');
   If Total>0 Then WriteLn('Total proportion: 100.00 % ')
              Else WriteLn('Total proportion: 0.00 % ');
   WriteLn;
  End
   Else
  Begin
   WriteLn('Total time:     ',Fmt3(Total),' milliseconds');
   WriteLn('Total CPU time: ',Fmt3(Total),' milliseconds');
   WriteLn;
  End;
 End;
End;

Procedure WriteCounterRows(Var T:Text;Const Times:TDblArr);
Var
 I,P:LongInt;
 Total:Double;
Begin
 Write(T,'layerName;execStatus;layerType;execType;realTime (ms);cpuTime (ms)'#10);
 Total:=0;
 For I:=0 to NOrder-1 do Begin
  P:=Order[I];
  If Layers[P].Op=OP_CONST Then Continue;
  Write(T,Layers[P].Name,';',LayerStatus(P),';',Layers[P].Typ,';',LayerExecType(P),';',
        Fmt3(Times[P]),';',Fmt3(Times[P]),#10);
  Total:=Total+Times[P];
 End;
 Write(T,'Total;;;;',Fmt3(Total),';',Fmt3(Total),#10#10);
End;

Procedure WriteCounterReport(Const Folder:AnsiString;Const RType:AnsiString);
Var
 T:Text;
 Path:AnsiString;
 K,I:LongInt;
 Avg:TDblArr;
Begin
 Path:=JoinPath(Folder,'benchmark_'+RType+'_report.csv');
 Assign(T,Path);
 {$I-}Rewrite(T);{$I+}
 If IOResult<>0 Then Die('impossible de creer '+Path);
 If RType='detailed_counters'Then Begin
  For K:=0 to Length(Ctxs)-1 do WriteCounterRows(T,Ctxs[K].Times);
 End
  Else
 Begin
  SetLength(Avg,NL);
  For I:=0 to NL-1 do Begin
   Avg[I]:=0;
   For K:=0 to Length(Ctxs)-1 do Avg[I]:=Avg[I]+Ctxs[K].Times[I];
   Avg[I]:=Avg[I]/Length(Ctxs);
  End;
  WriteCounterRows(T,Avg);
 End;
 {$I-}Close(T);{$I+}
 If IOResult<>0 Then ;
 Info('Performance counters report is stored to '+Path);
End;

Function JsonEsc(Const S:AnsiString):AnsiString;
Begin
 JsonEsc:=ReplaceAll(ReplaceAll(S,'\','\\'),'"','\"');
End;

Type
 TStat = Record
  Names,Vals:TStrArr;
 End;

Procedure StatAdd(Var S:TStat;Const N,V:AnsiString);
Begin
 SetLength(S.Names,Length(S.Names)+1);
 SetLength(S.Vals,Length(S.Vals)+1);
 S.Names[High(S.Names)]:=N;
 S.Vals[High(S.Vals)]:=V;
End;

Procedure WriteStats(Const Folder:AnsiString;AsJson:Boolean;Const Cmd,Cfg,Res:TStat);
Var
 T:Text;
 Path:AnsiString;

 Procedure CsvSec(Const Title:AnsiString;Const S:TStat);
 Var
  I:LongInt;
 Begin
  Write(T,Title,#10);
  For I:=0 to High(S.Names) do Write(T,S.Names[I],';',S.Vals[I],#10);
  Write(T,#10);
 End;

 Procedure JsonSec(Const Title:AnsiString;Const S:TStat;Last:Boolean);
 Var
  I:LongInt;
 Begin
  Write(T,'"',Title,'": {');
  For I:=0 to High(S.Names) do Begin
   If I>0 Then Write(T,', ');
   Write(T,'"',JsonEsc(S.Names[I]),'": "',JsonEsc(S.Vals[I]),'"');
  End;
  Write(T,'}');
  If Not Last Then Write(T,', ');
 End;

Begin
 If AsJson Then Path:=JoinPath(Folder,'benchmark_report.json')
           Else Path:=JoinPath(Folder,'benchmark_report.csv');
 Assign(T,Path);
 {$I-}Rewrite(T);{$I+}
 If IOResult<>0 Then Die('impossible de creer '+Path);
 If AsJson Then Begin
  Write(T,'{');
  JsonSec('cmd_options',Cmd,False);
  JsonSec('configuration_setup',Cfg,False);
  JsonSec('execution_results',Res,True);
  Write(T,'}');
 End
  Else
 Begin
  If Length(Cmd.Names)>0 Then CsvSec('Command line parameters',Cmd);
  CsvSec('Configuration setup',Cfg);
  CsvSec('Execution results',Res);
 End;
 {$I-}Close(T);{$I+}
 If IOResult<>0 Then ;
 Info('Statistics report is stored to '+Path);
End;

{ Ecrit une sortie du modele en binaire }
Procedure DumpOutputs(Const C:TCtx);
Var
 K,I,N:LongInt;
 L,Src:LongInt;
 Nm,Path:AnsiString;
 T:TTensor;
 F:File;
 Buf:TByteArr;
 H:Word;
 V:Int64;
 L32:LongInt;
Begin
 MakeDirs(ODumpOut);
 If Not DirExists(ODumpOut)Then Die('impossible de creer le dossier '+ODumpOut);
 For K:=0 to High(OutLayers) do Begin
  L:=OutLayers[K];
  Src:=Layers[L].SrcL[0];
  Nm:=FirstName(Layers[Src].Outs[Layers[L].SrcP[0]].Names,Layers[Src].Name);
  Nm:=ReplaceAll(ReplaceAll(ReplaceAll(Nm,'/','_'),'\','_'),':','_');
  T:=C.Outs[K];
  Mat(T);
  N:=Length(T.D);
  Case T.Prec of
   PR_F16:Begin
    SetLength(Buf,N*2);
    For I:=0 to N-1 do Begin
     H:=SingleToHalf(T.D[I]);
     Move(H,Buf[I*2],2);
    End;
   End;
   PR_I64:Begin
    SetLength(Buf,N*8);
    For I:=0 to N-1 do Begin
     V:=Round(T.D[I]);
     Move(V,Buf[I*8],8);
    End;
   End;
   PR_I32:Begin
    SetLength(Buf,N*4);
    For I:=0 to N-1 do Begin
     L32:=Round(T.D[I]);
     Move(L32,Buf[I*4],4);
    End;
   End;
   PR_U8,PR_I8,PR_BOOL:Begin
    SetLength(Buf,N);
    For I:=0 to N-1 do Buf[I]:=Byte(Round(T.D[I]));
   End;
   Else Begin
    SetLength(Buf,N*4);
    If N>0 Then Move(T.D[0],Buf[0],N*4);
   End;
  End;
  Path:=JoinPath(ODumpOut,Nm+'.bin');
  Assign(F,Path);
  {$I-}Rewrite(F,1);{$I+}
  If IOResult<>0 Then Die('impossible de creer '+Path);
  If Length(Buf)>0 Then Begin
   {$I-}BlockWrite(F,Buf[0],Length(Buf));{$I+}
   If IOResult<>0 Then Die('erreur d''ecriture de '+Path);
  End;
  {$I-}Close(F);{$I+}
  If IOResult<>0 Then ;
  Info('Output '''+Nm+''' : '+ElemName[T.Prec]+' '+DimsToStr(T.Dims)+' written to '+Path);
 End;
End;

{ ------------------------------------------------------------------ }
{ Programme principal                                                 }
{ ------------------------------------------------------------------ }

Procedure SetFpuMask;
Begin
 {$IFDEF CPUI386}
 Set8087CW($133F);
 {$ENDIF}
 {$IFDEF CPUX86_64}
 Set8087CW($133F);
 SetMXCSR($1F80);
 {$ENDIF}
End;

{ Verifie le peripherique demande (-d) }
Procedure CheckDevice;
Var
 D,Pre,Rest:AnsiString;
 P,I:LongInt;
 Parts:TStrArr;
Begin
 D:=UpStr(TrimStr(ODevice));
 Rest:=D;
 P:=System.Pos(':',D);
 If P>0 Then Begin
  Pre:=Copy(D,1,P-1);
  Rest:=Copy(D,P+1,Length(D));
  If(Pre<>'AUTO')and(Pre<>'MULTI')and(Pre<>'HETERO')and(Pre<>'BATCH')Then
   Die('Device with "'+Pre+'" name is not registered in the OpenVINO Runtime; available devices: CPU');
 End
  Else
 If(D='AUTO')or(D='MULTI')or(D='HETERO')Then Rest:='CPU';
 Parts:=SplitStr(Rest,',');
 For I:=0 to High(Parts) do Begin
  If(TrimStr(Parts[I])<>'CPU')and Not StartsWith(TrimStr(Parts[I]),'CPU.')Then
   Die('Device with "'+TrimStr(Parts[I])+'" name is not registered in the OpenVINO Runtime; '+
       'available devices: CPU');
 End;
 If D='' Then Die('peripherique vide');
End;

Function HintConst(Const H:AnsiString):AnsiString;
Begin
 If H='latency'Then HintConst:='LATENCY' Else
 If H='throughput'Then HintConst:='THROUGHPUT' Else
 If H='cumulative_throughput'Then HintConst:='CUMULATIVE_THROUGHPUT'
                             Else HintConst:='UNDEFINED';
End;

Function ParseCount(Const S:AnsiString;Def:LongInt):LongInt;
Var
 P:LongInt;
 T:AnsiString;
Begin
 T:=S;
 P:=Length(T);
 While(P>0)and(T[P] in ['0'..'9'])do Dec(P);
 T:=Copy(T,P+1,Length(T));
 ParseCount:=ToI(T,Def);
End;

Var
 ReadMs,CompileMs,FirstMs,T0,T1,TotalMs,Fps,Avg,Med,Mn,Mx,Sum,Frames,
 ReshapeMs:Double;
 ModelPath,HintEff,Xml,PrecShown:AnsiString;
 CompileOnly,InferOnly,StaticMode,Prof:Boolean;
 Cpus,Streams,Tt,NReq,NReqOpt,Per,I,K,N,Cnt,AlignedNiter:LongInt;
 AllLat:TDblArr;
 StC,StF,StE:TStat;
 Lim:AnsiString;
 FirstLat:Double;

Begin
 SetFpuMask;
 InitClock;
 CurLI:=-1;
 ErrHook:=@LayerHook;
 Step(1,'');
 Info('Parsing input parameters');
 ParseArgs;
 CheckArgs;
 CompileOnly:=ONiter=0;
 CheckDevice;
 { ---- Etape 2 ---- }
 Step(2,'');
 Info('OpenVINO:');
 Info('Build ................................. '+VersionStr);
 Info('');
 Info('Device info:');
 Info('CPU');
 Info('Build ................................. '+VersionStr);
 Info('');
 Info('');
 { ---- Etape 3 ---- }
 Step(3,'');
 If OHintSet Then HintEff:=OHint
 Else Begin
  If OApi='sync' Then HintEff:='latency'
                 Else HintEff:='throughput';
  Warn('Performance hint was not explicitly specified in command line or config file. '+
       'Device(CPU) performance hint will be set to PerformanceMode.'+HintConst(HintEff)+'.');
 End;
 If HintEff='tput'Then HintEff:='throughput';
 If HintEff='ctput'Then HintEff:='cumulative_throughput';
 Prof:=False;
 If OPc Then Prof:=True Else
 If(OReportType='average_counters')or(OReportType='detailed_counters')Then Begin
  Warn('Turn on performance counters for CPU device since report type is '+OReportType+'.');
  Prof:=True;
 End Else
 If OPcSort<>'' Then Begin
  Warn('Turn on performance counters for CPU device since pcsort value is '+OPcSort+'.');
  Prof:=True;
 End;
 If OBatch<>0 Then Warn('Batch size is set. Auto batching will be disabled');
 If Not HasThreads Then
  Warn('Threads are not supported by this build (Windows only): a single stream and a single thread are used.');
 {$IFNDEF HIRES}
 Warn('Timer resolution is 10 ms on this build (non-Windows): latencies below 10 ms are not meaningful.');
 {$ENDIF}
 If OWeightFmt<>'' Then
  Warn('--weight-format '+OWeightFmt+' accepted for optimum-cli compatibility and ignored: weight precision comes from the model.');
 If OCdir<>'' Then Begin
  MakeDirs(OCdir);
  If Not DirExists(OCdir)Then Die('impossible de creer le repertoire de cache '+OCdir);
 End;
 PrecShown:='float32';
 If OInferPrec<>'' Then Begin
  K:=System.Pos(':',OInferPrec);
  PrecShown:=LoStr(Copy(OInferPrec,K+1,Length(OInferPrec)));
  If PrecShown='f32'Then PrecShown:='float32' Else
  If(PrecShown='f16')or(PrecShown='bf16')Then Begin
   Warn('-infer_precision '+PrecShown+' accepte; le calcul reste en FP32 dans ce clone.');
   If PrecShown='f16'Then PrecShown:='float16'
                     Else PrecShown:='bfloat16';
  End
   Else Die('-infer_precision invalide : '+OInferPrec+' (f32, f16 ou bf16)');
 End;
 { ---- Etape 4 ---- }
 Step(4,'');
 ModelPath:=OModel;
 If DirExists(ModelPath)Then ModelPath:=JoinPath(ModelPath,'openvino_model.xml');
 If FileExt(ModelPath)='.onnx'Then
  Die('le format ONNX n''est pas pris en charge : convertissez le modele en IR (.xml + .bin) '+
      'avec ovc ou optimum-cli');
 If FileExt(ModelPath)='.bin'Then ModelPath:=ChangeExt(ModelPath,'.xml');
 If FileExt(ModelPath)<>'.xml'Then
  Die('format de modele non pris en charge : '+ModelPath+' (.xml attendu)');
 If Not FileExists(ModelPath)Then Die('le fichier du modele '+ModelPath+' est introuvable');
 Info('Loading model files');
 T0:=NowMs;
 Xml:=ReadWholeFile(ModelPath);
 If Xml='' Then Die('impossible de lire '+ModelPath);
 NL:=0;NE:=0;
 ParseXml(Xml);
 Xml:='';
 If NL=0 Then Die('aucune couche trouvee dans '+ModelPath);
 ResolveGraph;
 FindModelIO;
 BinPath:=ChangeExt(ModelPath,'.bin');
 ReadMs:=NowMs-T0;
 Info('Read model took '+FStr(ReadMs,2)+' ms');
 Info('Original model I/O parameters:');
 LoadInputInfo;
 PrintIO;
 { ---- Etape 5 ---- }
 Step(5,'');
 CollectInputFiles;
 T0:=NowMs;
 ConfigureShapes;
 ReshapeMs:=NowMs-T0;
 { ---- Etape 6 ---- }
 Step(6,'');
 PrintIO;
 { ---- Etape 7 ---- }
 Step(7,'');
 T0:=NowMs;
 CompileModel;
 CompileMs:=NowMs-T0;
 Info('Compile model took '+FStr(CompileMs,2)+' ms');
 If CompileOnly Then Begin
  Info('Model compiled successfully. Skipping inference due to -niter 0.');
  Step(8,'skipped');
  Step(9,'skipped');
  Step(10,'skipped');
  Step(11,'');
  Exit;
 End;
 { ---- Etape 8 ---- }
 Step(8,'');
 Cpus:=CpuCount;
 NReqOpt:=1;
 If HintEff='latency'Then Begin
  Streams:=1;Tt:=Cpus;NReqOpt:=1;
 End
  Else
 If HintEff='none'Then Begin
  Streams:=ParseCount(ONStreams,1);
  If Streams<1 Then Streams:=1;
  If ONthreads>0 Then Tt:=ONthreads Else Tt:=Cpus;
  NReqOpt:=Streams;
 End
  Else
 Begin
  Streams:=Cpus div 2;
  If Streams<1 Then Streams:=1;
  Tt:=Cpus;
  NReqOpt:=Streams;
 End;
 If Not HasThreads Then Begin
  Streams:=1;Tt:=1;NReqOpt:=1;
 End;
 If(ONireq>0)and(OApi='async')Then NReq:=ONireq
                              Else NReq:=NReqOpt;
 If OApi='sync' Then Begin
  NReq:=1;
  NWork:=1;
 End
  Else Begin
   NWork:=NReq;
   If NWork>Streams Then NWork:=Streams;
  End;
 If NWork<1 Then NWork:=1;
 If OApi='async' Then NReq:=NReq
                 Else NReq:=1;
 Per:=Tt div NWork;
 If Per<1 Then Per:=1;
 Info('Model:');
 Info('  NETWORK_NAME: '+NetName);
 Info('  OPTIMAL_NUMBER_OF_INFER_REQUESTS: '+IStr(NReqOpt));
 Info('  NUM_STREAMS: '+IStr(Streams));
 Info('  INFERENCE_NUM_THREADS: '+IStr(Tt));
 If Prof Then Info('  PERF_COUNT: YES')
         Else Info('  PERF_COUNT: NO');
 Info('  INFERENCE_PRECISION_HINT: <Type: '''+PrecShown+'''>');
 Info('  PERFORMANCE_HINT: '+HintConst(HintEff));
 Info('  EXECUTION_MODE_HINT: ExecutionMode.PERFORMANCE');
 Info('  PERFORMANCE_HINT_NUM_REQUESTS: '+IStr(ONireq));
 Info('  ENABLE_CPU_PINNING: True');
 If OCdir<>'' Then Info('  CACHE_DIR: '+OCdir);
 Info('  EXECUTION_DEVICES: [''CPU'']');
 { ---- Etape 9 ---- }
 Step(9,'');
 SetLength(Ctxs,NWork);
 For I:=0 to NWork-1 do InitCtx(Ctxs[I],Per,Prof);
 BuildInputs;
 StaticMode:=True;
 For I:=0 to NInputs-1 do If InInfo[I].Dynamic Then StaticMode:=False;
 If OInferOnly<0 Then InferOnly:=StaticMode Else
 If OInferOnly=1 Then Begin
  InferOnly:=True;
  If Not StaticMode Then Die('Benchmarking dynamic model available with input filling in measurement loop only!');
 End
  Else InferOnly:=False;
 GFull:=Not InferOnly;
 For I:=0 to NWork-1 do SetInputs(Ctxs[I],0,False);
 { limites }
 GMaxRate:=OMaxIrate;
 GNiter:=0;
 AlignedNiter:=0;
 If ONiter>0 Then Begin
  AlignedNiter:=ONiter;
  If OApi='async' Then Begin
   If NCases>NReq Then Begin
    AlignedNiter:=((ONiter+NCases-1)div NCases)*NCases;
    If AlignedNiter<>ONiter Then
     Warn('Number of iterations was aligned by number of input shapes from '+IStr(ONiter)+
          ' to '+IStr(AlignedNiter)+' using number of possible input shapes '+IStr(NCases));
   End
    Else
   Begin
    AlignedNiter:=((ONiter+NReq-1)div NReq)*NReq;
    If AlignedNiter<>ONiter Then
     Warn('Number of iterations was aligned by request number from '+IStr(ONiter)+
          ' to '+IStr(AlignedNiter)+' using number of requests '+IStr(NReq));
   End;
  End;
  GNiter:=AlignedNiter;
 End;
 If OTime>0 Then GDurMs:=OTime*1000.0 Else
 If ONiter<=0 Then GDurMs:=60000.0
              Else GDurMs:=0;
 { ---- Etape 10 ---- }
 If OApi='sync' Then Lim:='Start inference synchronously'
 Else Begin
  Lim:='Start inference asynchronously, '+IStr(NReq)+' inference requests';
  If ONStreams<>'' Then Lim:=Lim+' using '+IStr(Streams)+' streams for CPU';
 End;
 Lim:=Lim+', limits: ';
 If GDurMs>0 Then Lim:=Lim+IStr(Round(GDurMs))+' ms duration';
 If GNiter>0 Then Begin
  If GDurMs>0 Then Lim:=Lim+', ';
  Lim:=Lim+IStr(GNiter)+' iterations';
 End;
 Step(10,Lim);
 If InferOnly Then Info('Benchmarking in inference only mode (inputs filling are not included in measurement loop).')
              Else Info('Benchmarking in full mode (inputs filling are included in measurement loop).');
 FirstMs:=0;
 If Not ONoWarmup Then Begin
  SetInputs(Ctxs[0],0,GFull);
  T0:=NowMs;
  RunInference(Ctxs[0]);
  FirstMs:=NowMs-T0;
  Info('First inference took '+FStr(FirstMs,2)+' ms');
  If ODumpOut<>'' Then DumpOutputs(Ctxs[0]);
 End
  Else Info('Skipping warmup inference due to -no_warmup flag');
 RunWorkers;
 If(ODumpOut<>'')and ONoWarmup Then DumpOutputs(Ctxs[0]);
 { statistiques }
 Cnt:=0;
 For I:=0 to NWork-1 do Cnt:=Cnt+Ctxs[I].NLat;
 If Cnt=0 Then Die('aucune iteration n''a ete mesuree');
 SetLength(AllLat,Cnt);
 K:=0;
 Sum:=0;
 Frames:=0;
 For I:=0 to NWork-1 do Begin
  For N:=0 to Ctxs[I].NLat-1 do Begin
   AllLat[K]:=Ctxs[I].Lat[N];
   Sum:=Sum+AllLat[K];
   Inc(K);
  End;
  Frames:=Frames+Ctxs[I].Frames;
 End;
 HeapSort(AllLat,Cnt);
 N:=(Cnt*OPercentile+99)div 100-1;
 If N<0 Then N:=0;
 If N>=Cnt Then N:=Cnt-1;
 Med:=AllLat[N];
 Avg:=Sum/Cnt;
 Mn:=AllLat[0];
 Mx:=AllLat[Cnt-1];
 TotalMs:=GEnd-GStart;
 If TotalMs<=0 Then TotalMs:=0.001;
 Fps:=Frames/(TotalMs/1000.0);
 { ---- Etape 11 ---- }
 Step(11,'');
 If Prof Then Begin
  If OPcSort<>'' Then PrintCounters(OPcSort)
                 Else PrintCounters('');
  If(OReportType='average_counters')or(OReportType='detailed_counters')Then Begin
   If OReportFolder<>'' Then MakeDirs(OReportFolder);
   WriteCounterReport(OReportFolder,OReportType);
  End;
 End;
 If OReportType<>'' Then Begin
  If OReportFolder<>'' Then Begin
   MakeDirs(OReportFolder);
   If Not DirExists(OReportFolder)Then Die('impossible de creer le dossier '+OReportFolder);
  End;
  SetLength(StC.Names,0);SetLength(StC.Vals,0);
  SetLength(StF.Names,0);SetLength(StF.Vals,0);
  SetLength(StE.Names,0);SetLength(StE.Vals,0);
  For I:=0 to High(CmdN) do StatAdd(StC,CmdN[I],CmdV[I]);
  StatAdd(StF,'topology',NetName);
  StatAdd(StF,'target device','CPU');
  StatAdd(StF,'API',OApi);
  If InferOnly Then StatAdd(StF,'inference_only','True')
               Else StatAdd(StF,'inference_only','False');
  StatAdd(StF,'precision','UNSPECIFIED');
  StatAdd(StF,'batch size',BatchStr);
  If GNiter>0 Then StatAdd(StF,'number of iterations',IStr(GNiter))
              Else StatAdd(StF,'number of iterations','None');
  StatAdd(StF,'number of parallel infer requests',IStr(NReq));
  StatAdd(StF,'duration (ms)',IStr(Round(GDurMs)));
  If ONStreams<>'' Then StatAdd(StF,'number of CPU streams',IStr(Streams));
  StatAdd(StE,'read model time (ms)',FStr(ReadMs,2));
  If Reshaped Then StatAdd(StE,'reshape model time (ms)',FStr(ReshapeMs,2));
  StatAdd(StE,'compile model time (ms)',FStr(CompileMs,2));
  If Not ONoWarmup Then StatAdd(StE,'first inference time (ms)',FStr(FirstMs,2));
  StatAdd(StE,'total execution time (ms)',FStr(TotalMs,2));
  StatAdd(StE,'total number of iterations',IStr(Cnt));
  If OPercentile=50 Then StatAdd(StE,'latency (ms)',FStr(Med,2))
  Else StatAdd(StE,'latency ('+IStr(OPercentile)+' percentile) (ms)',FStr(Med,2));
  StatAdd(StE,'avg latency',FStr(Avg,2));
  StatAdd(StE,'min latency',FStr(Mn,2));
  StatAdd(StE,'max latency',FStr(Mx,2));
  StatAdd(StE,'throughput',FStr(Fps,2));
  WriteStats(OReportFolder,OJson,StC,StF,StE);
 End;
 Info('Execution Devices:[''CPU'']');
 Info('Count:            '+IStr(Cnt)+' iterations');
 Info('Duration:         '+FStr(TotalMs,2)+' ms');
 Info('Latency:');
 If OPercentile=50 Then Info('   Median:        '+ConsoleLatency(Med,Avg))
                   Else Info('   '+IStr(OPercentile)+' percentile:     '+ConsoleLatency(Med,Avg));
 Info('   Average:       '+ConsoleLatency(Avg,Avg));
 Info('   Min:           '+ConsoleLatency(Mn,Avg));
 Info('   Max:           '+ConsoleLatency(Mx,Avg));
 Info('Throughput:   '+FStr(Fps,2)+' FPS');
End.
