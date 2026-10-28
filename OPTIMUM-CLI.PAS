{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/vie)
  @abstract(Target: Free Pascal 3.x)

  OPTIMUM-CLI : clone de la commande optimum-cli (Hugging Face Optimum
  Intel) limite a "optimum-cli export openvino" pour les modeles de la
  famille LLaMA.

  Convertit un modele Hugging Face local (config.json + fichiers
  *.safetensors) au format OpenVINO IR (openvino_model.xml +
  openvino_model.bin) et compresse (quantifie) les poids : fp32, fp16,
  int8, int4 (symetrique ou asymetrique, par groupes) et nf4. Le modele
  produit est pret a etre charge par OpenVINO (OVModelForCausalLM,
  openvino_genai, Core.read_model, ...).

  Syntaxe :
   optimum-cli export openvino --help
   optimum-cli export openvino --model meta-llama/Llama-2-7b-chat-hf
                               --weight-format int4 .\models\llama-2-7b-int4
   optimum-cli export openvino -m C:\modeles\llama --task text-generation-with-past
                               --weight-format int8 sortie

  Principaux parametres :
   export openvino  Exporte un modele vers le format OpenVINO.
   --model          Identifiant du modele ou chemin local.
   --task           Type de tache a exporter (text-generation-with-past ...).
   --weight-format  Precision des poids : fp32, fp16, int8, int4, nf4.
   --device         Peripherique (accepte pour compatibilite, sans effet).
   -h, --help, /?   Affiche l'aide detaillee.

  Graphe produit (comme optimum-intel, mode "stateful" par defaut) :
   entrees  input_ids, attention_mask, position_ids, beam_idx;
   sortie   logits;
   cache KV conserve dans des variables (ReadValue/Assign) ou, avec
   --disable-stateful, dans les entrees past_key_values.N.key/value et les
   sorties present.N.key/value.

  Limites de ce clone (le reste de l'outil original n'est pas reproduit) :
   - aucun acces reseau : un identifiant Hugging Face n'est resolu que s'il
     est deja present dans le cache local (--cache_dir, HF_HUB_CACHE,
     HF_HOME ou ~/.cache/huggingface/hub); sinon telechargez d'abord le
     modele (huggingface-cli download) et donnez son dossier;
   - poids au format safetensors uniquement (F32, F16 et BF16);
   - architectures LLaMA (llama, mistral, qwen2), activation silu;
   - les fichiers du tokenizer sont copies tels quels; les modeles
     openvino_tokenizer.xml / openvino_detokenizer.xml ne sont pas generes;
   - les options AWQ, GPTQ, scale-estimation, lora-correction, dataset,
     smooth-quant demandent un jeu de calibration et un moteur de
     reference : elles sont acceptees puis ignorees (avertissement);
   - mxfp4 et cb4 ne sont pas pris en charge;
   - la repartition int4/int8 pour --ratio < 1 utilise l'erreur de
     quantification des poids comme mesure de sensibilite (sans donnees).

  Contraintes respectees :
   - un seul fichier source, aucun fichier d'inclusion;
   - la seule unite utilisee est DOS (le reste vient de l'unite System).

  Un programme Turbo Pascal 16 bits ne peut pas lire des fichiers de
  plusieurs Go : il faut un compilateur 32 ou 64 bits (Free Pascal) pour
  compiler ce programme.

  Compilation : fpc -O3 OPTIMUM-CLI.PAS
}

Program OPTIMUM_CLI;

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
 VersionStr   = '1.0 (clone Pascal de optimum-cli export openvino)';

 { Precisions des ports OpenVINO }
 PR_F32=0; PR_F16=1; PR_I64=2; PR_I32=3; PR_U8=4; PR_U4=5; PR_I8=6;
 PR_I4=7; PR_NF4=8; PR_BOOL=9;

 PrecName:Array[0..9] of AnsiString=
  ('FP32','FP16','I64','I32','U8','U4','I8','I4','NF4','BOOL');
 ElemName:Array[0..9] of AnsiString=
  ('f32','f16','i64','i32','u8','u4','i8','i4','nf4','boolean');

 { Modes de stockage des poids }
 M_F32=0; M_F16=1; M_I8A=2; M_I8S=3; M_I4A=4; M_I4S=5; M_NF4=6;
 ModeName:Array[0..6] of AnsiString=
  ('fp32','fp16','int8_asym','int8_sym','int4_asym','int4_sym','nf4');

 { Types de donnees safetensors }
 DT_F32=0; DT_F16=1; DT_BF16=2;

 { Gestion du cache KV }
 CM_NONE=0; CM_STATELESS=1; CM_STATEFUL=2;

 NF4Table:Array[0..15] of Single=(
  -1.0,-0.6961928009986877,-0.5250730514526367,-0.39491748809814453,
  -0.28444138169288635,-0.18477343022823334,-0.09105003625154495,0.0,
  0.07958029955625534,0.16093020141124725,0.24611230194568634,
  0.33791524171829224,0.44070982933044434,0.5626170039176941,
  0.7229568362236023,1.0);

Type
 TIntArr = Array of LongInt;
 TSingleArr = Array of Single;
 TByteArr = Array of Byte;
 TStrArr = Array of AnsiString;

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

Procedure Die(Const Msg:AnsiString);
Begin
 WriteLn(StdErr,'optimum-cli: erreur : ',Msg);
 Halt(1);
End;

Procedure Warn(Const Msg:AnsiString);
Begin
 WriteLn(StdErr,'optimum-cli: avertissement : ',Msg);
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
 If N>0 Then BlockRead(F,S[1],N);
 Close(F);
 ReadWholeFile:=S;
End;

Function CopyFileTo(Const Src,Dst:AnsiString):Boolean;
Var
 F,G:File;
 Buf:Array[0..65535] of Byte;
 N:LongInt;
Begin
 CopyFileTo:=False;
 Assign(F,Src);
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0 Then Exit;
 Assign(G,Dst);
 {$I-}Rewrite(G,1);{$I+}
 If IOResult<>0 Then Begin
  Close(F);
  Exit;
 End;
 Repeat
  BlockRead(F,Buf,SizeOf(Buf),N);
  If N>0 Then BlockWrite(G,Buf,N);
 Until N<=0;
 Close(F);
 Close(G);
 CopyFileTo:=True;
End;

Function GetEnvVar(Const Name:AnsiString):AnsiString;
Begin
 GetEnvVar:=GetEnv(Name);
End;

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

{ ------------------------------------------------------------------ }
{ Analyseur JSON                                                      }
{ ------------------------------------------------------------------ }

Type
 TJKind=(jkNull,jkBool,jkNum,jkStr,jkArr,jkObj);

 TJson=Class
  Kind:TJKind;
  Num:Double;
  Str:AnsiString;
  Bool:Boolean;
  Count:LongInt;
  Keys:TStrArr;
  Items:Array of TJson;
  Procedure Add(Const K:AnsiString;V:TJson);
  Function Get(Const K:AnsiString):TJson;
 End;

Var
 JS:AnsiString;
 JP:LongInt;
 JErr:Boolean;

Procedure TJson.Add(Const K:AnsiString;V:TJson);
Begin
 If Count>=Length(Items)Then Begin
  If Count=0 Then Begin
   SetLength(Items,8);
   SetLength(Keys,8);
  End
   Else
  Begin
   SetLength(Items,Count*2);
   SetLength(Keys,Count*2);
  End;
 End;
 Items[Count]:=V;
 Keys[Count]:=K;
 Inc(Count);
End;

Function TJson.Get(Const K:AnsiString):TJson;
Var
 I:LongInt;
Begin
 Get:=Nil;
 If Kind<>jkObj Then Exit;
 For I:=0 to Count-1 do If Keys[I]=K Then Begin
  Get:=Items[I];
  Exit;
 End;
End;

Procedure JSkip;
Begin
 While(JP<=Length(JS))and(JS[JP] in [' ',#9,#10,#13])do Inc(JP);
End;

Function HexVal(C:Char):LongInt;
Begin
 Case C of
  '0'..'9':HexVal:=Ord(C)-48;
  'a'..'f':HexVal:=Ord(C)-87;
  'A'..'F':HexVal:=Ord(C)-55;
  Else HexVal:=0;
 End;
End;

Function Utf8Of(CP:LongWord):AnsiString;
Begin
 If CP<$80 Then Utf8Of:=Chr(CP) Else
 If CP<$800 Then Utf8Of:=Chr($C0 or(CP shr 6))+Chr($80 or(CP and $3F)) Else
 If CP<$10000 Then Utf8Of:=Chr($E0 or(CP shr 12))+Chr($80 or((CP shr 6)and $3F))+
                           Chr($80 or(CP and $3F))
 Else Utf8Of:=Chr($F0 or(CP shr 18))+Chr($80 or((CP shr 12)and $3F))+
              Chr($80 or((CP shr 6)and $3F))+Chr($80 or(CP and $3F));
End;

Function JParseStr:AnsiString;
Var
 R:AnsiString;
 St,CP,Lo:LongWord;
 C:Char;
Begin
 R:='';
 Inc(JP);
 St:=JP;
 While(JP<=Length(JS))and(JS[JP]<>'"')and(JS[JP]<>'\')do Inc(JP);
 If(JP<=Length(JS))and(JS[JP]='"')Then Begin
  JParseStr:=Copy(JS,St,JP-St);
  Inc(JP);
  Exit;
 End;
 R:=Copy(JS,St,JP-St);
 While JP<=Length(JS) do Begin
  C:=JS[JP];
  If C='"'Then Begin
   Inc(JP);
   JParseStr:=R;
   Exit;
  End;
  If C='\'Then Begin
   Inc(JP);
   If JP>Length(JS)Then Break;
   C:=JS[JP];
   Case C of
    'n':R:=R+#10;
    'r':R:=R+#13;
    't':R:=R+#9;
    'b':R:=R+#8;
    'f':R:=R+#12;
    'u':Begin
     CP:=(HexVal(JS[JP+1])shl 12)or(HexVal(JS[JP+2])shl 8)or
         (HexVal(JS[JP+3])shl 4)or HexVal(JS[JP+4]);
     Inc(JP,4);
     If(CP>=$D800)and(CP<=$DBFF)and(Copy(JS,JP+1,2)='\u')Then Begin
      Lo:=(HexVal(JS[JP+3])shl 12)or(HexVal(JS[JP+4])shl 8)or
          (HexVal(JS[JP+5])shl 4)or HexVal(JS[JP+6]);
      CP:=$10000+((CP-$D800)shl 10)+(Lo-$DC00);
      Inc(JP,6);
     End;
     R:=R+Utf8Of(CP);
    End;
    Else R:=R+C;
   End;
   Inc(JP);
  End
   Else
  Begin
   R:=R+C;
   Inc(JP);
  End;
 End;
 JErr:=True;
 JParseStr:=R;
End;

Function JParseVal:TJson;
Var
 V,E:TJson;
 K:AnsiString;
 St:LongInt;
 Code:LongInt;
 D:Double;
Begin
 V:=TJson.Create;
 V.Kind:=jkNull;
 V.Count:=0;
 JParseVal:=V;
 JSkip;
 If JP>Length(JS)Then Begin
  JErr:=True;
  Exit;
 End;
 Case JS[JP] of
  '{':Begin
   V.Kind:=jkObj;
   Inc(JP);
   JSkip;
   If(JP<=Length(JS))and(JS[JP]='}')Then Begin
    Inc(JP);
    Exit;
   End;
   While Not JErr do Begin
    JSkip;
    If(JP>Length(JS))or(JS[JP]<>'"')Then Begin
     JErr:=True;
     Exit;
    End;
    K:=JParseStr;
    JSkip;
    If(JP>Length(JS))or(JS[JP]<>':')Then Begin
     JErr:=True;
     Exit;
    End;
    Inc(JP);
    E:=JParseVal();
    V.Add(K,E);
    JSkip;
    If JP>Length(JS)Then Begin
     JErr:=True;
     Exit;
    End;
    If JS[JP]=','Then Inc(JP) Else
    If JS[JP]='}'Then Begin
     Inc(JP);
     Exit;
    End
     Else
    Begin
     JErr:=True;
     Exit;
    End;
   End;
  End;
  '[':Begin
   V.Kind:=jkArr;
   Inc(JP);
   JSkip;
   If(JP<=Length(JS))and(JS[JP]=']')Then Begin
    Inc(JP);
    Exit;
   End;
   While Not JErr do Begin
    E:=JParseVal();
    V.Add('',E);
    JSkip;
    If JP>Length(JS)Then Begin
     JErr:=True;
     Exit;
    End;
    If JS[JP]=','Then Inc(JP) Else
    If JS[JP]=']'Then Begin
     Inc(JP);
     Exit;
    End
     Else
    Begin
     JErr:=True;
     Exit;
    End;
   End;
  End;
  '"':Begin
   V.Kind:=jkStr;
   V.Str:=JParseStr;
  End;
  't':Begin
   V.Kind:=jkBool;
   V.Bool:=True;
   Inc(JP,4);
  End;
  'f':Begin
   V.Kind:=jkBool;
   V.Bool:=False;
   Inc(JP,5);
  End;
  'n':Inc(JP,4);
  Else Begin
   St:=JP;
   While(JP<=Length(JS))and(JS[JP] in ['0'..'9','-','+','.','e','E'])do Inc(JP);
   If JP=St Then Begin
    JErr:=True;
    Exit;
   End;
   Val(Copy(JS,St,JP-St),D,Code);
   V.Kind:=jkNum;
   V.Num:=D;
  End;
 End;
End;

Function ParseJson(Const S:AnsiString):TJson;
Begin
 JS:=S;
 JP:=1;
 JErr:=False;
 ParseJson:=JParseVal();
 If JErr Then ParseJson:=Nil;
End;

Function JNum(O:TJson;Const K:AnsiString;Def:Double):Double;
Var
 V:TJson;
Begin
 JNum:=Def;
 If O=Nil Then Exit;
 V:=O.Get(K);
 If(V<>Nil)and(V.Kind=jkNum)Then JNum:=V.Num;
End;

Function JStrOf(O:TJson;Const K,Def:AnsiString):AnsiString;
Var
 V:TJson;
Begin
 JStrOf:=Def;
 If O=Nil Then Exit;
 V:=O.Get(K);
 If(V<>Nil)and(V.Kind=jkStr)Then JStrOf:=V.Str;
End;

Function JBoolOf(O:TJson;Const K:AnsiString;Def:Boolean):Boolean;
Var
 V:TJson;
Begin
 JBoolOf:=Def;
 If O=Nil Then Exit;
 V:=O.Get(K);
 If(V<>Nil)and(V.Kind=jkBool)Then JBoolOf:=V.Bool;
End;

{ ------------------------------------------------------------------ }
{ Lecture des fichiers safetensors                                    }
{ ------------------------------------------------------------------ }

Type
 TTensor = Record
  Name:AnsiString;
  DType:LongInt;
  NDim:LongInt;
  Shape:Array[0..3] of Int64;
  Shard:LongInt;
  Base:Int64;
  Bytes:Int64;
 End;

 TShard = Record
  Path:AnsiString;
  F:File;
 End;

Var
 Tensors:Array of TTensor;
 NT:LongInt;
 Shards:Array of TShard;
 NShards:LongInt;
 RawBuf:TByteArr;

Procedure AddTensor(Const T:TTensor);
Begin
 If NT>=Length(Tensors)Then Begin
  If NT=0 Then SetLength(Tensors,256)
          Else SetLength(Tensors,NT*2);
 End;
 Tensors[NT]:=T;
 Inc(NT);
End;

Function FindTensor(Const Name:AnsiString):LongInt;
Var
 I:LongInt;
Begin
 For I:=0 to NT-1 do If Tensors[I].Name=Name Then Begin
  FindTensor:=I;
  Exit;
 End;
 FindTensor:=-1;
End;

Procedure LoadShard(Const Path:AnsiString;Idx:LongInt);
Var
 HL:Int64;
 Buf:Array[0..7] of Byte;
 H:AnsiString;
 J,D,Sh,Of_:TJson;
 I,K:LongInt;
 T:TTensor;
 Dt:AnsiString;
 N:LongInt;
Begin
 Assign(Shards[Idx].F,Path);
 {$I-}Reset(Shards[Idx].F,1);{$I+}
 If IOResult<>0 Then Die('impossible d''ouvrir '+Path);
 BlockRead(Shards[Idx].F,Buf,8,N);
 If N<>8 Then Die('fichier safetensors invalide : '+Path);
 HL:=0;
 For I:=7 downto 0 do HL:=(HL shl 8)or Buf[I];
 If(HL<=0)or(HL>1000000000)Then Die('en-tete safetensors invalide : '+Path);
 SetLength(H,HL);
 BlockRead(Shards[Idx].F,H[1],HL,N);
 If N<>HL Then Die('en-tete safetensors tronque : '+Path);
 J:=ParseJson(H);
 If(J=Nil)or(J.Kind<>jkObj)Then Die('en-tete JSON invalide : '+Path);
 For I:=0 to J.Count-1 do Begin
  If J.Keys[I]='__metadata__'Then Continue;
  D:=J.Items[I];
  If D.Kind<>jkObj Then Continue;
  Dt:=JStrOf(D,'dtype','');
  If Dt='F32'Then T.DType:=DT_F32 Else
  If Dt='F16'Then T.DType:=DT_F16 Else
  If Dt='BF16'Then T.DType:=DT_BF16
  Else Die('type de donnees non pris en charge ('+Dt+') pour '+J.Keys[I]);
  T.Name:=J.Keys[I];
  Sh:=D.Get('shape');
  Of_:=D.Get('data_offsets');
  If(Sh=Nil)or(Of_=Nil)or(Of_.Count<>2)or(Sh.Count>4)Then
   Die('entree de tenseur invalide : '+J.Keys[I]);
  T.NDim:=Sh.Count;
  For K:=0 to 3 do T.Shape[K]:=1;
  For K:=0 to Sh.Count-1 do T.Shape[K]:=Trunc(Sh.Items[K].Num);
  T.Shard:=Idx;
  T.Base:=8+HL+Trunc(Of_.Items[0].Num);
  T.Bytes:=Trunc(Of_.Items[1].Num)-Trunc(Of_.Items[0].Num);
  AddTensor(T);
 End;
End;

Function TElems(Const T:TTensor):Int64;
Var
 K:LongInt;
 N:Int64;
Begin
 N:=1;
 For K:=0 to T.NDim-1 do N:=N*T.Shape[K];
 TElems:=N;
End;

{ Lit les elements [Start, Start+Cnt) d'un tenseur dans Dst (Single) }
Procedure ReadElems(Const T:TTensor;Start,Cnt:Int64;Var Dst:TSingleArr);
Var
 ES:LongInt;
 NB:Int64;
 I:LongInt;
 N:LongInt;
 PW:PWord;
 PS:PSingle;
Begin
 If T.DType=DT_F32 Then ES:=4 Else ES:=2;
 NB:=Cnt*ES;
 If Length(RawBuf)<NB Then SetLength(RawBuf,NB);
 If Length(Dst)<Cnt Then SetLength(Dst,Cnt);
 Seek(Shards[T.Shard].F,T.Base+Start*ES);
 BlockRead(Shards[T.Shard].F,RawBuf[0],NB,N);
 If N<>NB Then Die('lecture tronquee du tenseur '+T.Name);
 Case T.DType of
  DT_F32:Begin
   PS:=PSingle(@RawBuf[0]);
   For I:=0 to Cnt-1 do Dst[I]:=PS[I];
  End;
  DT_F16:Begin
   PW:=PWord(@RawBuf[0]);
   For I:=0 to Cnt-1 do Dst[I]:=HalfToSingle(PW[I]);
  End;
  Else Begin
   PW:=PWord(@RawBuf[0]);
   For I:=0 to Cnt-1 do Dst[I]:=BitsToSingle(LongWord(PW[I])shl 16);
  End;
 End;
End;

{ ------------------------------------------------------------------ }
{ Configuration du modele                                             }
{ ------------------------------------------------------------------ }

Type
 TCfg = Record
  ModelType:AnsiString;
  Hidden,Inter,Layers,Heads,KVHeads,HeadDim,Vocab,MaxPos:LongInt;
  Eps,Theta:Double;
  Tied:Boolean;
  RopeType:AnsiString;
  RopeFactor,RopeLow,RopeHigh,RopeOrig:Double;
  TorchDtype:AnsiString;
  Architecture:AnsiString;
 End;

Var
 Cfg:TCfg;
 ConfigText:AnsiString;

Procedure LoadConfig(Const Dir:AnsiString);
Var
 J,A,R:TJson;
 Path:AnsiString;
Begin
 Path:=JoinPath(Dir,'config.json');
 ConfigText:=ReadWholeFile(Path);
 If ConfigText=''Then Die('config.json introuvable dans '+Dir);
 J:=ParseJson(ConfigText);
 If(J=Nil)or(J.Kind<>jkObj)Then Die('config.json invalide');
 Cfg.ModelType:=JStrOf(J,'model_type','');
 Cfg.Architecture:='';
 A:=J.Get('architectures');
 If(A<>Nil)and(A.Kind=jkArr)and(A.Count>0)and(A.Items[0].Kind=jkStr)Then
  Cfg.Architecture:=A.Items[0].Str;
 If(Cfg.ModelType<>'llama')and(Cfg.ModelType<>'mistral')and
   (Cfg.ModelType<>'qwen2')Then
  Die('architecture non prise en charge (model_type='+Cfg.ModelType+
      ') : seuls llama, mistral et qwen2 sont geres');
 Cfg.Hidden:=Trunc(JNum(J,'hidden_size',0));
 Cfg.Inter:=Trunc(JNum(J,'intermediate_size',0));
 Cfg.Layers:=Trunc(JNum(J,'num_hidden_layers',0));
 Cfg.Heads:=Trunc(JNum(J,'num_attention_heads',0));
 Cfg.KVHeads:=Trunc(JNum(J,'num_key_value_heads',Cfg.Heads));
 Cfg.Vocab:=Trunc(JNum(J,'vocab_size',0));
 Cfg.MaxPos:=Trunc(JNum(J,'max_position_embeddings',2048));
 Cfg.Eps:=JNum(J,'rms_norm_eps',1E-6);
 Cfg.Theta:=JNum(J,'rope_theta',10000.0);
 Cfg.Tied:=JBoolOf(J,'tie_word_embeddings',False);
 If(Cfg.Hidden<=0)or(Cfg.Inter<=0)or(Cfg.Layers<=0)or(Cfg.Heads<=0)or
   (Cfg.Vocab<=0)Then Die('config.json incomplet (hidden_size, ...)');
 Cfg.HeadDim:=Trunc(JNum(J,'head_dim',Cfg.Hidden div Cfg.Heads));
 If Cfg.KVHeads<=0 Then Cfg.KVHeads:=Cfg.Heads;
 If(Cfg.Heads mod Cfg.KVHeads)<>0 Then Die('num_attention_heads non multiple de num_key_value_heads');
 If(Cfg.HeadDim and 1)<>0 Then Die('head_dim impair non pris en charge');
 If LoStr(JStrOf(J,'hidden_act','silu'))<>'silu'Then
  Die('activation non prise en charge : '+JStrOf(J,'hidden_act',''));
 Cfg.TorchDtype:=JStrOf(J,'torch_dtype',JStrOf(J,'dtype',''));
 Cfg.RopeType:='default';
 Cfg.RopeFactor:=1;Cfg.RopeLow:=1;Cfg.RopeHigh:=4;Cfg.RopeOrig:=Cfg.MaxPos;
 R:=J.Get('rope_scaling');
 If(R=Nil)or(R.Kind<>jkObj)Then R:=J.Get('rope_parameters');
 If(R<>Nil)and(R.Kind=jkObj)Then Begin
  Cfg.RopeType:=JStrOf(R,'rope_type',JStrOf(R,'type','default'));
  If R.Get('rope_theta')<>Nil Then Cfg.Theta:=JNum(R,'rope_theta',Cfg.Theta);
  Cfg.RopeFactor:=JNum(R,'factor',1);
  Cfg.RopeLow:=JNum(R,'low_freq_factor',1);
  Cfg.RopeHigh:=JNum(R,'high_freq_factor',4);
  Cfg.RopeOrig:=JNum(R,'original_max_position_embeddings',Cfg.MaxPos);
  If(Cfg.RopeType<>'default')and(Cfg.RopeType<>'linear')and
    (Cfg.RopeType<>'llama3')Then
   Die('rope_scaling non pris en charge : '+Cfg.RopeType);
 End;
End;

{ ------------------------------------------------------------------ }
{ Parametres de la ligne de commande                                  }
{ ------------------------------------------------------------------ }

Var
 OptModel,OptTask,OptFramework,OptWeightFormat,OptQuantMode,OptLibrary,
 OptCacheDir,OptPadToken,OptBackup,OptDataset,OptSensitivity,OptNumSamples,
 OptSmoothAlpha,OptDevice,OptOutput:AnsiString;
 OptRatio:Double;
 OptGroupSize:LongInt;
 OptGroupGiven:Boolean;
 OptSym,OptAllLayers,OptAwq,OptScaleEst,OptGptq,OptLora,OptDisableStateful,
 OptNoTokenizer,OptTrust,OptRatioGiven:Boolean;

Procedure ShowMainHelp;
Begin
 WriteLn('usage: optimum-cli <command> [<args>]');
 WriteLn;
 WriteLn('Clone Pascal de optimum-cli (Hugging Face Optimum). Commande prise en charge :');
 WriteLn;
 WriteLn('  export openvino   Exporte un modele vers le format OpenVINO.');
 WriteLn;
 WriteLn('options :');
 WriteLn('  -h, --help, /?    Affiche cette aide');
 WriteLn('  --version         Affiche la version');
 WriteLn;
 WriteLn('Exemple :');
 WriteLn('  optimum-cli export openvino --model meta-llama/Llama-2-7b-chat-hf --weight-format int4 models\llama-2-7b-int4');
End;

Procedure ShowExportHelp;
Begin
 WriteLn('usage: optimum-cli export openvino [-h] -m MODEL [--task TASK]');
 WriteLn('                                   [--framework {pt,tf}] [--trust-remote-code]');
 WriteLn('                                   [--weight-format {fp32,fp16,int8,int4,nf4}]');
 WriteLn('                                   [--quant-mode MODE] [--library LIBRARY]');
 WriteLn('                                   [--cache_dir CACHE_DIR] [--pad-token-id ID]');
 WriteLn('                                   [--ratio RATIO] [--sym] [--group-size N]');
 WriteLn('                                   [--backup-precision {none,int8_sym,int8_asym}]');
 WriteLn('                                   [--dataset DATASET] [--all-layers] [--awq]');
 WriteLn('                                   [--scale-estimation] [--gptq] [--lora-correction]');
 WriteLn('                                   [--sensitivity-metric METRIC] [--num-samples N]');
 WriteLn('                                   [--disable-stateful] [--disable-convert-tokenizer]');
 WriteLn('                                   [--device DEVICE]');
 WriteLn('                                   output');
 WriteLn;
 WriteLn('Exporte un modele LLaMA (config.json + *.safetensors) vers OpenVINO IR');
 WriteLn('(openvino_model.xml / openvino_model.bin) avec compression des poids.');
 WriteLn;
 WriteLn('arguments positionnels :');
 WriteLn('  output                Dossier ou le modele OpenVINO est enregistre.');
 WriteLn;
 WriteLn('options :');
 WriteLn('  -h, --help, /?        Affiche cette aide.');
 WriteLn('  -m MODEL, --model MODEL');
 WriteLn('                        Identifiant du modele ou chemin local (dossier contenant');
 WriteLn('                        config.json et les fichiers .safetensors). Un identifiant');
 WriteLn('                        Hugging Face doit deja etre present dans le cache local.');
 WriteLn('  --task TASK           Tache a exporter : auto, text-generation-with-past');
 WriteLn('                        (defaut) ou text-generation (sans cache KV).');
 WriteLn('  --framework {pt,tf}   Accepte pour compatibilite (les poids sont lus tels quels).');
 WriteLn('  --trust-remote-code   Accepte pour compatibilite (sans effet).');
 WriteLn('  --weight-format {fp32,fp16,int8,int4,nf4}');
 WriteLn('                        Precision des poids. Defaut : fp16. mxfp4 et cb4 ne sont');
 WriteLn('                        pas pris en charge par ce clone.');
 WriteLn('  --quant-mode MODE     Accepte pour compatibilite (seule la compression des poids');
 WriteLn('                        est prise en charge).');
 WriteLn('  --library LIB         Accepte pour compatibilite (transformers).');
 WriteLn('  --cache_dir DIR       Cache Hugging Face ou chercher le modele.');
 WriteLn('  --pad-token-id ID     Accepte pour compatibilite (sans effet).');
 WriteLn('  --ratio RATIO         Part (0..1) des poids en precision principale (int4/nf4);');
 WriteLn('                        le reste utilise la precision de secours. Defaut : 1.0.');
 WriteLn('  --sym                 Quantification symetrique (int8_sym / int4_sym).');
 WriteLn('  --group-size N        Taille de groupe de la quantification (int4/nf4 : 128 par');
 WriteLn('                        defaut; -1 : par canal).');
 WriteLn('  --backup-precision {none,int8_sym,int8_asym}');
 WriteLn('                        Precision des couches non compressees en int4 (embeddings,');
 WriteLn('                        lm_head, couches sensibles). Defaut : int8_asym.');
 WriteLn('  --all-layers          Compresse aussi lm_head avec la precision principale.');
 WriteLn('  --dataset, --awq, --scale-estimation, --gptq, --lora-correction,');
 WriteLn('  --sensitivity-metric, --num-samples, --smooth-quant-alpha');
 WriteLn('                        Options de calibration : acceptees mais ignorees.');
 WriteLn('  --disable-stateful    Cache KV en entrees/sorties (past_key_values/present)');
 WriteLn('                        au lieu de variables internes.');
 WriteLn('  --disable-convert-tokenizer');
 WriteLn('                        Accepte pour compatibilite (aucun tokenizer OpenVINO n''est');
 WriteLn('                        genere; les fichiers du tokenizer sont copies).');
 WriteLn('  --device DEVICE       Peripherique pour certaines operations (sans effet ici).');
End;

Function NeedsValue(Const O:AnsiString):Boolean;
Begin
 NeedsValue:=(O='-m')or(O='--model')or(O='--task')or(O='--framework')or
  (O='--weight-format')or(O='--quant-mode')or(O='--library')or
  (O='--cache_dir')or(O='--cache-dir')or(O='--pad-token-id')or
  (O='--ratio')or(O='--group-size')or(O='--backup-precision')or
  (O='--dataset')or(O='--sensitivity-metric')or(O='--num-samples')or
  (O='--smooth-quant-alpha')or(O='--device')or(O='--revision')or
  (O='--variant')or(O='--token')or(O='--output');
End;

Procedure SetValueOpt(Const O,V:AnsiString);
Begin
 If(O='-m')or(O='--model')Then OptModel:=V Else
 If O='--task'Then OptTask:=V Else
 If O='--framework'Then OptFramework:=V Else
 If O='--weight-format'Then OptWeightFormat:=LoStr(V) Else
 If O='--quant-mode'Then OptQuantMode:=V Else
 If O='--library'Then OptLibrary:=V Else
 If(O='--cache_dir')or(O='--cache-dir')Then OptCacheDir:=V Else
 If O='--pad-token-id'Then OptPadToken:=V Else
 If O='--ratio'Then Begin
  OptRatio:=ToF(V,-1);
  OptRatioGiven:=True;
 End Else
 If O='--group-size'Then Begin
  OptGroupSize:=Trunc(ToI(V,0));
  OptGroupGiven:=True;
 End Else
 If O='--backup-precision'Then OptBackup:=LoStr(V) Else
 If O='--dataset'Then OptDataset:=V Else
 If O='--sensitivity-metric'Then OptSensitivity:=V Else
 If O='--num-samples'Then OptNumSamples:=V Else
 If O='--smooth-quant-alpha'Then OptSmoothAlpha:=V Else
 If O='--device'Then OptDevice:=V Else
 If O='--output'Then OptOutput:=V;
End;

Function IsHelp(Const A:AnsiString):Boolean;
Begin
 IsHelp:=(A='-h')or(A='--help')or(A='/?')or(A='-?');
End;

Procedure ParseArgs;
Var
 I,P:LongInt;
 A,O,V:AnsiString;
 Pos_:TStrArr;
 NP:LongInt;
Begin
 OptModel:='';OptTask:='auto';OptFramework:='';OptWeightFormat:='';
 OptQuantMode:='';OptLibrary:='';OptCacheDir:='';OptPadToken:='';
 OptBackup:='int8_asym';OptDataset:='';OptSensitivity:='';OptNumSamples:='';
 OptSmoothAlpha:='';OptDevice:='';OptOutput:='';
 OptRatio:=1.0;OptGroupSize:=-1;OptGroupGiven:=False;
 OptSym:=False;OptAllLayers:=False;OptAwq:=False;OptScaleEst:=False;
 OptGptq:=False;OptLora:=False;OptDisableStateful:=False;
 OptNoTokenizer:=False;OptTrust:=False;OptRatioGiven:=False;
 NP:=0;
 If ParamCount=0 Then Begin
  ShowMainHelp;
  Halt(0);
 End;
 { Sous-commandes }
 A:=ParamStr(1);
 If IsHelp(A)Then Begin
  ShowMainHelp;
  Halt(0);
 End;
 If A='--version'Then Begin
  WriteLn('optimum-cli ',VersionStr);
  Halt(0);
 End;
 If A<>'export'Then Begin
  WriteLn(StdErr,'optimum-cli: commande inconnue : ',A);
  ShowMainHelp;
  Halt(2);
 End;
 If ParamCount<2 Then Begin
  WriteLn('usage: optimum-cli export {openvino} ...');
  Halt(2);
 End;
 A:=ParamStr(2);
 If IsHelp(A)Then Begin
  WriteLn('usage: optimum-cli export [-h] {openvino} ...');
  WriteLn;
  WriteLn('  openvino    Exporte un modele vers le format OpenVINO.');
  Halt(0);
 End;
 If A<>'openvino'Then Begin
  WriteLn(StdErr,'optimum-cli: seul "export openvino" est pris en charge (recu : ',A,')');
  Halt(2);
 End;
 SetLength(Pos_,ParamCount);
 I:=3;
 While I<=ParamCount do Begin
  A:=ParamStr(I);
  If IsHelp(A)Then Begin
   ShowExportHelp;
   Halt(0);
  End;
  If(Length(A)>1)and(A[1]='-')and Not(A[2] in ['0'..'9'])Then Begin
   P:=0;
   If StartsWith(A,'--')Then P:=System.Pos('=',A);
   If P>0 Then Begin
    O:=Copy(A,1,P-1);
    V:=Copy(A,P+1,Length(A));
    If Not NeedsValue(O)Then Die('option inconnue ou sans valeur : '+O);
    SetValueOpt(O,V);
   End
    Else
   If NeedsValue(A)Then Begin
    If I>=ParamCount Then Die('l''option '+A+' attend une valeur');
    Inc(I);
    SetValueOpt(A,ParamStr(I));
   End
    Else
   If A='--sym'Then OptSym:=True Else
   If A='--all-layers'Then OptAllLayers:=True Else
   If A='--awq'Then OptAwq:=True Else
   If A='--scale-estimation'Then OptScaleEst:=True Else
   If A='--gptq'Then OptGptq:=True Else
   If A='--lora-correction'Then OptLora:=True Else
   If A='--disable-stateful'Then OptDisableStateful:=True Else
   If A='--disable-convert-tokenizer'Then OptNoTokenizer:=True Else
   If A='--trust-remote-code'Then OptTrust:=True Else
   If(A='--no-post-process')or(A='--no-dynamic-axes')or(A='--fp16')or
     (A='--int8')Then Begin
    If A='--fp16'Then OptWeightFormat:='fp16' Else
    If A='--int8'Then OptWeightFormat:='int8';
   End
    Else
   Die('arguments non reconnus : '+A);
  End
   Else
  Begin
   Pos_[NP]:=A;
   Inc(NP);
  End;
  Inc(I);
 End;
 If OptModel=''Then Begin
  ShowExportHelp;
  WriteLn(StdErr,'optimum-cli export openvino: erreur : l''argument -m/--model est obligatoire');
  Halt(2);
 End;
 If NP<>1 Then Begin
  If NP=0 Then WriteLn(StdErr,'optimum-cli export openvino: erreur : l''argument "output" est obligatoire')
          Else WriteLn(StdErr,'optimum-cli export openvino: erreur : plusieurs arguments "output"');
  Halt(2);
 End;
 If OptOutput=''Then OptOutput:=Pos_[0];
 If OptWeightFormat=''Then OptWeightFormat:='fp16';
End;

{ ------------------------------------------------------------------ }
{ Localisation du modele                                              }
{ ------------------------------------------------------------------ }

Function FirstSnapshot(Const RepoDir:AnsiString):AnsiString;
Var
 SR:SearchRec;
 Ref,Snap:AnsiString;
Begin
 FirstSnapshot:='';
 Ref:=TrimStr(ReadWholeFile(JoinPath(JoinPath(RepoDir,'refs'),'main')));
 Snap:=JoinPath(JoinPath(RepoDir,'snapshots'),Ref);
 If(Ref<>'')and DirExists(Snap)Then Begin
  FirstSnapshot:=Snap;
  Exit;
 End;
 FindFirst(JoinPath(JoinPath(RepoDir,'snapshots'),'*'),Directory,SR);
 While DosError=0 do Begin
  If(SR.Name<>'.')and(SR.Name<>'..')and((SR.Attr and Directory)<>0)Then Begin
   FirstSnapshot:=JoinPath(JoinPath(RepoDir,'snapshots'),SR.Name);
   Break;
  End;
  FindNext(SR);
 End;
 FindClose(SR);
End;

Function ResolveModel(Const Id:AnsiString):AnsiString;
Var
 Cands:TStrArr;
 NC,I:LongInt;
 Repo,Snap,Hf:AnsiString;
Begin
 If DirExists(Id)Then Begin
  ResolveModel:=Id;
  Exit;
 End;
 NC:=0;
 SetLength(Cands,8);
 If OptCacheDir<>''Then Begin
  Cands[NC]:=OptCacheDir;Inc(NC);
 End;
 Hf:=GetEnvVar('HF_HUB_CACHE');
 If Hf<>''Then Begin
  Cands[NC]:=Hf;Inc(NC);
 End;
 Hf:=GetEnvVar('HF_HOME');
 If Hf<>''Then Begin
  Cands[NC]:=JoinPath(Hf,'hub');Inc(NC);
 End;
 Hf:=GetEnvVar('HOME');
 If Hf=''Then Hf:=GetEnvVar('USERPROFILE');
 If Hf<>''Then Begin
  Cands[NC]:=JoinPath(JoinPath(JoinPath(Hf,'.cache'),'huggingface'),'hub');Inc(NC);
 End;
 Repo:='models--'+ReplaceAll(ReplaceAll(Id,'/','--'),'\','--');
 For I:=0 to NC-1 do Begin
  If DirExists(JoinPath(Cands[I],Repo))Then Begin
   Snap:=FirstSnapshot(JoinPath(Cands[I],Repo));
   If Snap<>''Then Begin
    ResolveModel:=Snap;
    Exit;
   End;
  End;
  { Le cache peut deja pointer sur le dossier du depot }
  If DirExists(JoinPath(Cands[I],Id))Then Begin
   ResolveModel:=JoinPath(Cands[I],Id);
   Exit;
  End;
 End;
 Die('modele introuvable : "'+Id+'". Ce clone n''a pas d''acces reseau : '+
     'telechargez d''abord le modele (par exemple "huggingface-cli download '+
     Id+' --local-dir dossier") puis passez le dossier a --model.');
 ResolveModel:='';
End;

Procedure LoadWeights(Const Dir:AnsiString);
Var
 Idx,J,WM:TJson;
 Files:TStrArr;
 NF,I,K:LongInt;
 SR:SearchRec;
 Known:Boolean;
Begin
 NF:=0;
 SetLength(Files,16);
 Idx:=Nil;
 If FileExists(JoinPath(Dir,'model.safetensors.index.json'))Then
  Idx:=ParseJson(ReadWholeFile(JoinPath(Dir,'model.safetensors.index.json')));
 If Idx<>Nil Then Begin
  WM:=Idx.Get('weight_map');
  If(WM<>Nil)and(WM.Kind=jkObj)Then
   For I:=0 to WM.Count-1 do Begin
    Known:=False;
    For K:=0 to NF-1 do If Files[K]=WM.Items[I].Str Then Known:=True;
    If Not Known Then Begin
     If NF>=Length(Files)Then SetLength(Files,NF*2);
     Files[NF]:=WM.Items[I].Str;
     Inc(NF);
    End;
   End;
 End;
 If NF=0 Then Begin
  FindFirst(JoinPath(Dir,'*.safetensors'),AnyFile,SR);
  While DosError=0 do Begin
   If(SR.Attr and Directory)=0 Then Begin
    If NF>=Length(Files)Then SetLength(Files,NF*2);
    Files[NF]:=SR.Name;
    Inc(NF);
   End;
   FindNext(SR);
  End;
  FindClose(SR);
 End;
 If NF=0 Then
  Die('aucun fichier .safetensors dans '+Dir+
      ' (les poids PyTorch .bin ne sont pas pris en charge)');
 SetLength(Shards,NF);
 NShards:=NF;
 For I:=0 to NF-1 do Begin
  Shards[I].Path:=JoinPath(Dir,Files[I]);
  LoadShard(Shards[I].Path,I);
 End;
End;

{ ------------------------------------------------------------------ }
{ Sortie binaire (.bin) avec tampon                                   }
{ ------------------------------------------------------------------ }

Var
 BinF:File;
 BinBuf:TByteArr;
 BinFill:LongInt;
 BinPos:Int64;
 NibPend:LongInt;

Const
 BinCap = 4194304;

Procedure BinFlush;
Begin
 If BinFill>0 Then Begin
  BlockWrite(BinF,BinBuf[0],BinFill);
  If IOResult<>0 Then Die('erreur d''ecriture du fichier .bin (disque plein ?)');
  BinFill:=0;
 End;
End;

Procedure BinPut(Const Buf;Cnt:Int64);
Var
 P:PByte;
 N:Int64;
Begin
 P:=PByte(@Buf);
 While Cnt>0 do Begin
  N:=BinCap-BinFill;
  If N>Cnt Then N:=Cnt;
  Move(P^,BinBuf[BinFill],N);
  Inc(BinFill,N);
  Inc(P,N);
  Dec(Cnt,N);
  Inc(BinPos,N);
  If BinFill>=BinCap Then BinFlush;
 End;
End;

Procedure BinPutByte(B:Byte);
Begin
 BinPut(B,1);
End;

Procedure PutNib(V:LongInt);
Begin
 V:=V and 15;
 If NibPend<0 Then NibPend:=V
 Else Begin
  BinPutByte(NibPend or(V shl 4));
  NibPend:=-1;
 End;
End;

Procedure FlushNib;
Begin
 If NibPend>=0 Then Begin
  BinPutByte(NibPend);
  NibPend:=-1;
 End;
End;

{ ------------------------------------------------------------------ }
{ Tampon de texte (XML)                                               }
{ ------------------------------------------------------------------ }

Type
 TBuf = Class
  Chunks:TStrArr;
  NCh:LongInt;
  Cur:AnsiString;
  Fill:LongInt;
  Constructor Create;
  Procedure Add(Const S:AnsiString);
  Procedure WriteTo(Var T:Text);
 End;

Constructor TBuf.Create;
Begin
 NCh:=0;
 Fill:=0;
 SetLength(Cur,65536);
 SetLength(Chunks,16);
End;

Procedure TBuf.Add(Const S:AnsiString);
Var
 L:LongInt;
Begin
 L:=Length(S);
 If L=0 Then Exit;
 If Fill+L>Length(Cur)Then Begin
  If NCh>=Length(Chunks)Then SetLength(Chunks,NCh*2);
  SetLength(Cur,Fill);
  Chunks[NCh]:=Cur;
  Inc(NCh);
  Cur:='';
  If L>65536 Then SetLength(Cur,L)
             Else SetLength(Cur,65536);
  Fill:=0;
 End;
 Move(S[1],Cur[Fill+1],L);
 Inc(Fill,L);
End;

Procedure TBuf.WriteTo(Var T:Text);
Var
 I:LongInt;
Begin
 For I:=0 to NCh-1 do Write(T,Chunks[I]);
 If Fill>0 Then Write(T,Copy(Cur,1,Fill));
End;

{ ------------------------------------------------------------------ }
{ Constructeur de graphe OpenVINO IR                                  }
{ ------------------------------------------------------------------ }

Type
 TPort = Record
  Node:LongInt;
  Port:LongInt;
 End;

 TNode = Record
  NIn:LongInt;
  Prec:Array[0..1] of LongInt;
  Shp:Array[0..1] of TIntArr;
 End;

Var
 Nodes:Array of TNode;
 NNodes:LongInt;
 LayersXml,EdgesXml:TBuf;

Function SA(Const A:Array of LongInt):TIntArr;
Var
 I:LongInt;
Begin
 SetLength(SA,Length(A));
 For I:=0 to High(A) do SA[I]:=A[I];
End;

Function DimsXml(Const S:TIntArr):AnsiString;
Var
 I:LongInt;
 R:AnsiString;
Begin
 R:='';
 For I:=0 to Length(S)-1 do R:=R+'<dim>'+IStr(S[I])+'</dim>';
 DimsXml:=R;
End;

Function ShapeAttr(Const S:TIntArr):AnsiString;
Var
 I:LongInt;
 R:AnsiString;
Begin
 R:='';
 For I:=0 to Length(S)-1 do Begin
  If I>0 Then R:=R+',';
  If S[I]<0 Then R:=R+'?'
            Else R:=R+IStr(S[I]);
 End;
 ShapeAttr:=R;
End;

Function MkPort(N,P:LongInt):TPort;
Begin
 MkPort.Node:=N;
 MkPort.Port:=P;
End;

Function NewNode(NIn:LongInt):LongInt;
Begin
 If NNodes>=Length(Nodes)Then Begin
  If NNodes=0 Then SetLength(Nodes,1024)
              Else SetLength(Nodes,NNodes*2);
 End;
 Nodes[NNodes].NIn:=NIn;
 NewNode:=NNodes;
 Inc(NNodes);
End;

Procedure EmitInputs(Id:LongInt;Const Ins:Array of TPort);
Var
 I:LongInt;
 P:TPort;
 X:AnsiString;
Begin
 If Length(Ins)=0 Then Exit;
 X:=' <input>'#10;
 For I:=0 to High(Ins) do Begin
  P:=Ins[I];
  X:=X+'  <port id="'+IStr(I)+'" precision="'+PrecName[Nodes[P.Node].Prec[P.Port]]+'">'+
     DimsXml(Nodes[P.Node].Shp[P.Port])+'</port>'#10;
  EdgesXml.Add('  <edge from-layer="'+IStr(P.Node)+'" from-port="'+
     IStr(Nodes[P.Node].NIn+P.Port)+'" to-layer="'+IStr(Id)+'" to-port="'+
     IStr(I)+'"/>'#10);
 End;
 LayersXml.Add(X+' </input>'#10);
End;

Function NamesAttr(Const N:AnsiString):AnsiString;
Begin
 If N='' Then NamesAttr:=''
         Else NamesAttr:=' names="'+N+'"';
End;

{ Ajoute une couche a une sortie. Nom d'affichage = Lbl_Id. }
Function L1(Const Lbl,Typ,Ver,Attrs:AnsiString;Const Ins:Array of TPort;
            Prec:LongInt;Const Shp:Array of LongInt;
            Const Names:AnsiString=''):TPort;
Var
 Id:LongInt;
 X:AnsiString;
Begin
 Id:=NewNode(Length(Ins));
 Nodes[Id].Prec[0]:=Prec;
 Nodes[Id].Shp[0]:=SA(Shp);
 X:='<layer id="'+IStr(Id)+'" name="'+Lbl+'_'+IStr(Id)+'" type="'+Typ+
    '" version="'+Ver+'">'#10;
 If Attrs<>''Then X:=X+' <data '+Attrs+'/>'#10;
 LayersXml.Add(X);
 EmitInputs(Id,Ins);
 LayersXml.Add(' <output>'#10'  <port id="'+IStr(Length(Ins))+'" precision="'+
    PrecName[Prec]+'"'+NamesAttr(Names)+'>'+DimsXml(Nodes[Id].Shp[0])+
    '</port>'#10' </output>'#10'</layer>'#10);
 L1:=MkPort(Id,0);
End;

{ Couche Split a deux sorties }
Procedure L2Split(Const Lbl:AnsiString;A,Axis:TPort;Prec:LongInt;
                  Const Shp:Array of LongInt;Var O0,O1:TPort);
Var
 Id:LongInt;
 X:AnsiString;
Begin
 Id:=NewNode(2);
 Nodes[Id].Prec[0]:=Prec;
 Nodes[Id].Shp[0]:=SA(Shp);
 Nodes[Id].Prec[1]:=Prec;
 Nodes[Id].Shp[1]:=SA(Shp);
 LayersXml.Add('<layer id="'+IStr(Id)+'" name="'+Lbl+'_'+IStr(Id)+
    '" type="Split" version="opset1">'#10' <data num_splits="2"/>'#10);
 EmitInputs(Id,[A,Axis]);
 X:=' <output>'#10;
 X:=X+'  <port id="2" precision="'+PrecName[Prec]+'">'+DimsXml(Nodes[Id].Shp[0])+'</port>'#10;
 X:=X+'  <port id="3" precision="'+PrecName[Prec]+'">'+DimsXml(Nodes[Id].Shp[1])+'</port>'#10;
 LayersXml.Add(X+' </output>'#10'</layer>'#10);
 O0:=MkPort(Id,0);
 O1:=MkPort(Id,1);
End;

{ Couche sans sortie utilisee (Assign garde une sortie, Result aucune) }
Procedure LResult(Const Lbl:AnsiString;A:TPort);
Var
 Id:LongInt;
Begin
 Id:=NewNode(1);
 LayersXml.Add('<layer id="'+IStr(Id)+'" name="'+Lbl+'_'+IStr(Id)+
    '" type="Result" version="opset1">'#10);
 EmitInputs(Id,[A]);
 LayersXml.Add('</layer>'#10);
End;

Procedure LAssign(Const VarId:AnsiString;A:TPort);
Var
 Id:LongInt;
Begin
 Id:=NewNode(1);
 Nodes[Id].Prec[0]:=Nodes[A.Node].Prec[A.Port];
 Nodes[Id].Shp[0]:=Nodes[A.Node].Shp[A.Port];
 LayersXml.Add('<layer id="'+IStr(Id)+'" name="Assign_'+VarId+'" type="Assign" '+
    'version="opset6">'#10' <data variable_id="'+VarId+'"/>'#10);
 EmitInputs(Id,[A]);
 LayersXml.Add(' <output>'#10'  <port id="1" precision="'+
    PrecName[Nodes[Id].Prec[0]]+'">'+DimsXml(Nodes[Id].Shp[0])+
    '</port>'#10' </output>'#10'</layer>'#10);
End;

{ --- Constantes --- }

Function ConstLayer(Prec:LongInt;Const Shp:TIntArr;Off,Size:Int64):TPort;
Var
 Id:LongInt;
Begin
 Id:=NewNode(0);
 Nodes[Id].Prec[0]:=Prec;
 Nodes[Id].Shp[0]:=Shp;
 LayersXml.Add('<layer id="'+IStr(Id)+'" name="Const_'+IStr(Id)+
    '" type="Const" version="opset1">'#10' <data element_type="'+
    ElemName[Prec]+'" shape="'+ShapeAttr(Shp)+'" offset="'+IStr(Off)+
    '" size="'+IStr(Size)+'"/>'#10' <output>'#10'  <port id="0" precision="'+
    PrecName[Prec]+'">'+DimsXml(Shp)+'</port>'#10' </output>'#10'</layer>'#10);
 ConstLayer:=MkPort(Id,0);
End;

Function CI64(Const V:Array of Int64;Const Shp:Array of LongInt):TPort;
Var
 Off:Int64;
Begin
 Off:=BinPos;
 If Length(V)>0 Then BinPut(V[0],Length(V)*8);
 CI64:=ConstLayer(PR_I64,SA(Shp),Off,Length(V)*8);
End;

Function CI64s(V:Int64):TPort;
Var
 Off:Int64;
Begin
 Off:=BinPos;
 BinPut(V,8);
 CI64s:=ConstLayer(PR_I64,SA([]),Off,8);
End;

Function CF32s(V:Single):TPort;
Var
 Off:Int64;
Begin
 Off:=BinPos;
 BinPut(V,4);
 CF32s:=ConstLayer(PR_F32,SA([]),Off,4);
End;

Function CF32a(Const V:TSingleArr;Cnt:LongInt;Const Shp:Array of LongInt):TPort;
Var
 Off:Int64;
Begin
 Off:=BinPos;
 If Cnt>0 Then BinPut(V[0],Int64(Cnt)*4);
 CF32a:=ConstLayer(PR_F32,SA(Shp),Off,Int64(Cnt)*4);
End;

Function CF16a(Const V:TSingleArr;Cnt:LongInt;Const Shp:Array of LongInt):TPort;
Var
 Off:Int64;
 I:LongInt;
 H:Word;
Begin
 Off:=BinPos;
 For I:=0 to Cnt-1 do Begin
  H:=SingleToHalf(V[I]);
  BinPut(H,2);
 End;
 CF16a:=ConstLayer(PR_F16,SA(Shp),Off,Int64(Cnt)*2);
End;

{ --- Operations --- }

Function NodeShape(P:TPort):TIntArr;
Begin
 NodeShape:=Nodes[P.Node].Shp[P.Port];
End;

Function BShape(Const A,B:TIntArr):TIntArr;
Var
 R,I,DA,DB,NA,NB:LongInt;
Begin
 NA:=Length(A);NB:=Length(B);
 If NA>NB Then R:=NA Else R:=NB;
 SetLength(BShape,R);
 For I:=0 to R-1 do Begin
  If NA-R+I>=0 Then DA:=A[NA-R+I] Else DA:=1;
  If NB-R+I>=0 Then DB:=B[NB-R+I] Else DB:=1;
  If DA=1 Then BShape[I]:=DB Else
  If DB=1 Then BShape[I]:=DA Else
  If DA<0 Then BShape[I]:=DB
          Else BShape[I]:=DA;
 End;
End;

Function Bn(Const Typ:AnsiString;A,B:TPort):TPort;
Var
 Pr:LongInt;
 Sh:TIntArr;
Begin
 Pr:=Nodes[A.Node].Prec[A.Port];
 If(Typ='LessEqual')or(Typ='LogicalAnd')Then Pr:=PR_BOOL;
 Sh:=BShape(NodeShape(A),NodeShape(B));
 Bn:=L1(Typ,Typ,'opset1','auto_broadcast="numpy"',[A,B],Pr,Sh);
End;

Function Un(Const Typ:AnsiString;A:TPort):TPort;
Begin
 Un:=L1(Typ,Typ,'opset1','',[A],Nodes[A.Node].Prec[A.Port],NodeShape(A));
End;

Function Cvt(A:TPort;Prec:LongInt):TPort;
Begin
 Cvt:=L1('Convert','Convert','opset1','destination_type="'+ElemName[Prec]+'"',
         [A],Prec,NodeShape(A));
End;

Function Rsh(A:TPort;Const Pat:Array of Int64;Const OutShp:Array of LongInt):TPort;
Var
 P:TPort;
 Sh:Array[0..0] of LongInt;
Begin
 Sh[0]:=Length(Pat);
 P:=CI64(Pat,Sh);
 Rsh:=L1('Reshape','Reshape','opset1','special_zero="true"',[A,P],
         Nodes[A.Node].Prec[A.Port],OutShp);
End;

Function Trn(A:TPort;Const Perm:Array of Int64;Const OutShp:Array of LongInt):TPort;
Var
 P:TPort;
 Sh:Array[0..0] of LongInt;
Begin
 Sh[0]:=Length(Perm);
 P:=CI64(Perm,Sh);
 Trn:=L1('Transpose','Transpose','opset1','',[A,P],Nodes[A.Node].Prec[A.Port],OutShp);
End;

Function Uns(A:TPort;Const Axes:Array of Int64;Const OutShp:Array of LongInt):TPort;
Var
 P:TPort;
 Sh:Array[0..0] of LongInt;
Begin
 Sh[0]:=Length(Axes);
 P:=CI64(Axes,Sh);
 Uns:=L1('Unsqueeze','Unsqueeze','opset1','',[A,P],Nodes[A.Node].Prec[A.Port],OutShp);
End;

Function MM(A,B:TPort;TB:Boolean;Const OutShp:Array of LongInt;
            Const Names:AnsiString=''):TPort;
Var
 S:AnsiString;
Begin
 If TB Then S:='true' Else S:='false';
 MM:=L1('MatMul','MatMul','opset1','transpose_a="false" transpose_b="'+S+'"',
        [A,B],Nodes[A.Node].Prec[A.Port],OutShp,Names);
End;

Function Cat(Const Ins:Array of TPort;Axis:LongInt;Const OutShp:Array of LongInt;
             Const Names:AnsiString=''):TPort;
Begin
 Cat:=L1('Concat','Concat','opset1','axis="'+IStr(Axis)+'"',Ins,
         Nodes[Ins[0].Node].Prec[Ins[0].Port],OutShp,Names);
End;

Function Gat(A,Idx:TPort;Axis:LongInt;Const OutShp:Array of LongInt):TPort;
Var
 Ax:TPort;
Begin
 Ax:=CI64s(Axis);
 Gat:=L1('Gather','Gather','opset8','batch_dims="0"',[A,Idx,Ax],
         Nodes[A.Node].Prec[A.Port],OutShp);
End;

{ ------------------------------------------------------------------ }
{ Quantification des poids                                            }
{ ------------------------------------------------------------------ }

Var
 PMode:TIntArr;     { mode de stockage par tenseur }
 PGroup:TIntArr;    { taille de groupe par tenseur (<=0 : par canal) }
 RowBuf:TSingleArr;
 QBuf:TIntArr;

Function IsAsym(M:LongInt):Boolean;
Begin
 IsAsym:=(M=M_I8A)or(M=M_I4A);
End;

Function Is4Bit(M:LongInt):Boolean;
Begin
 Is4Bit:=(M=M_I4A)or(M=M_I4S)or(M=M_NF4);
End;

{ Quantifie N valeurs de Row a partir de Off. Q recoit les codes entiers.
  Sc16 : echelle (flottant 16 bits); Zp : zero (modes asymetriques). }
Procedure QuantGroup(Const Row:TSingleArr;Off,N:LongInt;Mode:LongInt;
                     Var Q:TIntArr;Var Sc16:Word;Var Zp:LongInt);
Var
 I:LongInt;
 Mn,Mx,M,Sc,Lv,X,Best,D:Single;
 Lo,Hi,V,K,BI:LongInt;
Begin
 Zp:=0;
 Case Mode of
  M_I8A,M_I4A:Begin
   If Mode=M_I8A Then Lv:=255 Else Lv:=15;
   Mn:=0;Mx:=0;
   For I:=Off to Off+N-1 do Begin
    If Row[I]<Mn Then Mn:=Row[I];
    If Row[I]>Mx Then Mx:=Row[I];
   End;
   Sc:=(Mx-Mn)/Lv;
   If Sc<=0 Then Sc:=1;
   Sc16:=SingleToHalf(Sc);
   Sc:=HalfToSingle(Sc16);
   If Sc<=0 Then Begin
    Sc16:=SingleToHalf(1.0);
    Sc:=1;
   End;
   Zp:=Round(-Mn/Sc);
   If Zp<0 Then Zp:=0;
   If Zp>Lv Then Zp:=Trunc(Lv);
   For I:=Off to Off+N-1 do Begin
    V:=Round(Row[I]/Sc)+Zp;
    If V<0 Then V:=0;
    If V>Lv Then V:=Trunc(Lv);
    Q[I]:=V;
   End;
  End;
  M_I8S,M_I4S:Begin
   If Mode=M_I8S Then Begin
    Lo:=-128;Hi:=127;
   End
    Else
   Begin
    Lo:=-8;Hi:=7;
   End;
   M:=0;
   For I:=Off to Off+N-1 do If Abs(Row[I])>Abs(M)Then M:=Row[I];
   If M=0 Then Sc:=1
          Else Sc:=M/Lo;
   Sc16:=SingleToHalf(Sc);
   Sc:=HalfToSingle(Sc16);
   If Sc=0 Then Begin
    Sc16:=SingleToHalf(1.0);
    Sc:=1;
   End;
   For I:=Off to Off+N-1 do Begin
    V:=Round(Row[I]/Sc);
    If V<Lo Then V:=Lo;
    If V>Hi Then V:=Hi;
    Q[I]:=V;
   End;
  End;
  M_NF4:Begin
   M:=0;
   For I:=Off to Off+N-1 do If Abs(Row[I])>M Then M:=Abs(Row[I]);
   If M=0 Then Sc:=1
          Else Sc:=M;
   Sc16:=SingleToHalf(Sc);
   Sc:=HalfToSingle(Sc16);
   If Sc<=0 Then Begin
    Sc16:=SingleToHalf(1.0);
    Sc:=1;
   End;
   For I:=Off to Off+N-1 do Begin
    X:=Row[I]/Sc;
    Best:=1E30;
    BI:=0;
    For K:=0 to 15 do Begin
     D:=Abs(X-NF4Table[K]);
     If D<Best Then Begin
      Best:=D;
      BI:=K;
     End;
    End;
    Q[I]:=BI;
   End;
  End;
 End;
End;

Function DequantVal(Mode,Q,Zp:LongInt;Sc:Single):Single;
Begin
 Case Mode of
  M_I8A,M_I4A:DequantVal:=(Q-Zp)*Sc;
  M_NF4:DequantVal:=NF4Table[Q and 15]*Sc;
  Else DequantVal:=Q*Sc;
 End;
End;

{ Erreur relative de quantification d'un tenseur 2D (mesure de sensibilite) }
Function QuantError(TI:LongInt;Mode,Gs:LongInt):Double;
Var
 T:TTensor;
 R,G,I,Out_,In_,NG,Zp:LongInt;
 Sc16:Word;
 Sc:Single;
 E2,N2,D:Double;
Begin
 T:=Tensors[TI];
 Out_:=T.Shape[0];In_:=T.Shape[1];
 If Gs<=0 Then Gs:=In_;
 NG:=In_ div Gs;
 If Length(QBuf)<In_ Then SetLength(QBuf,In_);
 E2:=0;N2:=0;
 For R:=0 to Out_-1 do Begin
  ReadElems(T,Int64(R)*In_,In_,RowBuf);
  For G:=0 to NG-1 do Begin
   QuantGroup(RowBuf,G*Gs,Gs,Mode,QBuf,Sc16,Zp);
   Sc:=HalfToSingle(Sc16);
   For I:=G*Gs to G*Gs+Gs-1 do Begin
    D:=RowBuf[I]-DequantVal(Mode,QBuf[I],Zp,Sc);
    E2:=E2+D*D;
    N2:=N2+Double(RowBuf[I])*RowBuf[I];
   End;
  End;
 End;
 If N2<=0 Then QuantError:=0
          Else QuantError:=Sqrt(E2/N2);
End;

Type
 TWP = Record
  Mode:LongInt;
  Q,ZP,SC:TPort;
  Out_,In_,Gs:LongInt;
  Grouped:Boolean;
 End;

Function QPrec(Mode:LongInt):LongInt;
Begin
 Case Mode of
  M_I8A:QPrec:=PR_U8;
  M_I8S:QPrec:=PR_I8;
  M_I4A:QPrec:=PR_U4;
  M_I4S:QPrec:=PR_I4;
  Else QPrec:=PR_NF4;
 End;
End;

{ Lit le tenseur 2D et ecrit ses poids (compresses selon le mode) dans le
  fichier .bin sous forme de constantes OpenVINO. }
Function LoadWeight(TI:LongInt):TWP;
Var
 T:TTensor;
 W:TWP;
 Mode,Gs,NG,R,G,I,Zp,Out_,In_:LongInt;
 Start:Int64;
 Scales:Array of Word;
 Zps:TByteArr;
 Sc16:Word;
 H:Word;
 Sh:TIntArr;
Begin
 T:=Tensors[TI];
 If T.NDim<>2 Then Die('le tenseur '+T.Name+' n''est pas une matrice');
 Out_:=T.Shape[0];In_:=T.Shape[1];
 Mode:=PMode[TI];
 W.Mode:=Mode;W.Out_:=Out_;W.In_:=In_;
 W.Grouped:=PGroup[TI]>0;
 Gs:=PGroup[TI];
 If Gs<=0 Then Gs:=In_;
 W.Gs:=Gs;
 NG:=In_ div Gs;
 If Length(RowBuf)<In_ Then SetLength(RowBuf,In_);
 If Length(QBuf)<In_ Then SetLength(QBuf,In_);
 Start:=BinPos;
 If(Mode=M_F32)or(Mode=M_F16)Then Begin
  For R:=0 to Out_-1 do Begin
   ReadElems(T,Int64(R)*In_,In_,RowBuf);
   If Mode=M_F32 Then BinPut(RowBuf[0],Int64(In_)*4)
   Else
    For I:=0 to In_-1 do Begin
     H:=SingleToHalf(RowBuf[I]);
     BinPut(H,2);
    End;
  End;
  If Mode=M_F32 Then W.Q:=ConstLayer(PR_F32,SA([Out_,In_]),Start,BinPos-Start)
                Else W.Q:=ConstLayer(PR_F16,SA([Out_,In_]),Start,BinPos-Start);
  LoadWeight:=W;
  Exit;
 End;
 SetLength(Scales,Int64(Out_)*NG);
 SetLength(Zps,Int64(Out_)*NG);
 NibPend:=-1;
 For R:=0 to Out_-1 do Begin
  ReadElems(T,Int64(R)*In_,In_,RowBuf);
  For G:=0 to NG-1 do Begin
   QuantGroup(RowBuf,G*Gs,Gs,Mode,QBuf,Sc16,Zp);
   Scales[Int64(R)*NG+G]:=Sc16;
   Zps[Int64(R)*NG+G]:=Zp;
  End;
  If Is4Bit(Mode)Then
   For I:=0 to In_-1 do PutNib(QBuf[I])
  Else
   For I:=0 to In_-1 do BinPutByte(Byte(QBuf[I] and 255));
 End;
 FlushNib;
 If W.Grouped Then Sh:=SA([Out_,NG,Gs])
              Else Sh:=SA([Out_,In_]);
 W.Q:=ConstLayer(QPrec(Mode),Sh,Start,BinPos-Start);
 { Zero points }
 If IsAsym(Mode)Then Begin
  Start:=BinPos;
  NibPend:=-1;
  For I:=0 to Out_*NG-1 do
   If Is4Bit(Mode)Then PutNib(Zps[I])
                  Else BinPutByte(Zps[I]);
  FlushNib;
  If W.Grouped Then Sh:=SA([Out_,NG,1])
               Else Sh:=SA([Out_,1]);
  W.ZP:=ConstLayer(QPrec(Mode),Sh,Start,BinPos-Start);
 End;
 { Echelles }
 Start:=BinPos;
 For I:=0 to Out_*NG-1 do BinPut(Scales[I],2);
 If W.Grouped Then Sh:=SA([Out_,NG,1])
              Else Sh:=SA([Out_,1]);
 W.SC:=ConstLayer(PR_F16,Sh,Start,BinPos-Start);
 LoadWeight:=W;
End;

{ Sous-graphe de decompression : retourne le poids FP32 [Out,In] }
Function Decomp(Const W:TWP):TPort;
Var
 C,Z:TPort;
Begin
 If W.Mode=M_F32 Then Begin
  Decomp:=W.Q;
  Exit;
 End;
 If W.Mode=M_F16 Then Begin
  Decomp:=Cvt(W.Q,PR_F32);
  Exit;
 End;
 C:=Cvt(W.Q,PR_F16);
 If IsAsym(W.Mode)Then Begin
  Z:=Cvt(W.ZP,PR_F16);
  C:=Bn('Subtract',C,Z);
 End;
 C:=Bn('Multiply',C,W.SC);
 If W.Grouped Then C:=Rsh(C,[W.Out_,W.In_],[W.Out_,W.In_]);
 Decomp:=Cvt(C,PR_F32);
End;

{ Lit un petit tenseur 1D et en fait une constante (FP32 ou FP16+Convert) }
Function Vec1D(Const Name:AnsiString;AsHalf:Boolean):TPort;
Var
 TI,N:LongInt;
 C:TPort;
Begin
 TI:=FindTensor(Name);
 If TI<0 Then Die('tenseur introuvable : '+Name);
 N:=Tensors[TI].Shape[0];
 ReadElems(Tensors[TI],0,N,RowBuf);
 If AsHalf Then Begin
  C:=CF16a(RowBuf,N,[N]);
  Vec1D:=Cvt(C,PR_F32);
 End
  Else Vec1D:=CF32a(RowBuf,N,[N]);
End;

{ ------------------------------------------------------------------ }
{ Plan de compression                                                 }
{ ------------------------------------------------------------------ }

Type
 TCand = Record
  TI:LongInt;
  Params:Int64;
  Sens:Double;
 End;

Var
 WFmt:AnsiString;           { fp32, fp16, int8, int4, nf4 }
 PrimaryMode,BackupMode:LongInt;
 PrimaryGroup:LongInt;
 NonQuantHalf:Boolean;      { constantes diverses en FP16 ? }
 TEmbed,THead:LongInt;
 TProj:Array of Array[0..6] of LongInt;   { par couche }

Const
 ProjNames:Array[0..6] of AnsiString=
  ('self_attn.q_proj','self_attn.k_proj','self_attn.v_proj','self_attn.o_proj',
   'mlp.gate_proj','mlp.up_proj','mlp.down_proj');

Function LayerName(L:LongInt;Const S:AnsiString):AnsiString;
Begin
 LayerName:='model.layers.'+IStr(L)+'.'+S;
End;

Procedure CheckShape2(TI:LongInt;A,B:LongInt);
Begin
 If TI<0 Then Die('tenseur manquant');
 If(Tensors[TI].NDim<>2)or(Tensors[TI].Shape[0]<>A)or(Tensors[TI].Shape[1]<>B)Then
  Die('forme inattendue pour '+Tensors[TI].Name+' (attendu '+IStr(A)+'x'+IStr(B)+')');
End;

Procedure PlanQuantization;
Var
 L,P,I,K,NC:LongInt;
 QDim,KVDim:LongInt;
 Cands:Array of TCand;
 Tmp:TCand;
 Total,Used:Int64;
 Gs:LongInt;
 TI:LongInt;
 Sw:Boolean;
 BackupDflt:LongInt;
Begin
 SetLength(PMode,NT);
 SetLength(PGroup,NT);
 PrimaryGroup:=-1;
 NonQuantHalf:=True;
 BackupMode:=-1;
 If OptBackup='int8_asym'Then BackupMode:=M_I8A Else
 If OptBackup='int8_sym'Then BackupMode:=M_I8S Else
 If OptBackup='none'Then BackupMode:=-1
 Else Die('--backup-precision invalide : '+OptBackup);
 If WFmt='fp32'Then Begin
  PrimaryMode:=M_F32;
  NonQuantHalf:=False;
 End Else
 If WFmt='fp16'Then PrimaryMode:=M_F16 Else
 If WFmt='int8'Then Begin
  If OptSym Then PrimaryMode:=M_I8S
            Else PrimaryMode:=M_I8A;
  If OptGroupGiven and(OptGroupSize>0)Then PrimaryGroup:=OptGroupSize;
 End Else
 If WFmt='int4'Then Begin
  If OptSym Then PrimaryMode:=M_I4S
            Else PrimaryMode:=M_I4A;
  PrimaryGroup:=128;
  If OptGroupGiven Then PrimaryGroup:=OptGroupSize;
 End Else
 If WFmt='nf4'Then Begin
  PrimaryMode:=M_NF4;
  PrimaryGroup:=128;
  If OptGroupGiven Then PrimaryGroup:=OptGroupSize;
 End
  Else
 Begin
  If(WFmt='mxfp4')or(WFmt='cb4')Then
   Die('le format de poids '+WFmt+' n''est pas pris en charge par ce clone');
  Die('--weight-format invalide : '+WFmt+' (fp32, fp16, int8, int4, nf4)');
 End;
 If PrimaryGroup=0 Then Die('--group-size ne peut pas valoir 0');
 If(OptRatio<0)or(OptRatio>1)Then Die('--ratio doit etre compris entre 0 et 1');
 If WFmt='fp32'Then BackupDflt:=M_F32 Else BackupDflt:=M_F16;
 For I:=0 to NT-1 do Begin
  PMode[I]:=BackupDflt;
  PGroup[I]:=-1;
 End;
 { Localisation des tenseurs }
 TEmbed:=FindTensor('model.embed_tokens.weight');
 If TEmbed<0 Then Die('tenseur introuvable : model.embed_tokens.weight');
 CheckShape2(TEmbed,Cfg.Vocab,Cfg.Hidden);
 THead:=FindTensor('lm_head.weight');
 If THead<0 Then Begin
  Cfg.Tied:=True;
  THead:=TEmbed;
 End
  Else
 Begin
  CheckShape2(THead,Cfg.Vocab,Cfg.Hidden);
  If Cfg.Tied Then THead:=TEmbed;
 End;
 QDim:=Cfg.Heads*Cfg.HeadDim;
 KVDim:=Cfg.KVHeads*Cfg.HeadDim;
 SetLength(TProj,Cfg.Layers);
 NC:=0;
 SetLength(Cands,Cfg.Layers*7);
 Total:=0;
 For L:=0 to Cfg.Layers-1 do
  For P:=0 to 6 do Begin
   TI:=FindTensor(LayerName(L,ProjNames[P]+'.weight'));
   If TI<0 Then Die('tenseur introuvable : '+LayerName(L,ProjNames[P]+'.weight'));
   Case P of
    0:CheckShape2(TI,QDim,Cfg.Hidden);
    1,2:CheckShape2(TI,KVDim,Cfg.Hidden);
    3:CheckShape2(TI,Cfg.Hidden,QDim);
    4,5:CheckShape2(TI,Cfg.Inter,Cfg.Hidden);
    6:CheckShape2(TI,Cfg.Hidden,Cfg.Inter);
   End;
   TProj[L][P]:=TI;
   Cands[NC].TI:=TI;
   Cands[NC].Params:=Int64(Tensors[TI].Shape[0])*Tensors[TI].Shape[1];
   Cands[NC].Sens:=0;
   Total:=Total+Cands[NC].Params;
   Inc(NC);
  End;
 { Modes par defaut }
 If(PrimaryMode=M_F32)or(PrimaryMode=M_F16)Then Begin
  For I:=0 to NT-1 do PMode[I]:=PrimaryMode;
 End
  Else
 Begin
  { Embeddings et lm_head : precision de secours }
  If WFmt='int8'Then Begin
   For I:=0 to NC-1 do Begin
    PMode[Cands[I].TI]:=PrimaryMode;
    PGroup[Cands[I].TI]:=PrimaryGroup;
   End;
   PMode[TEmbed]:=PrimaryMode;PGroup[TEmbed]:=-1;
   PMode[THead]:=PrimaryMode;PGroup[THead]:=-1;
  End
   Else
  Begin
   { int4 / nf4 : couches du decodeur en precision principale (ou de secours) }
   For I:=0 to NC-1 do Begin
    TI:=Cands[I].TI;
    Gs:=PrimaryGroup;
    If(Gs>0)and((Tensors[TI].Shape[1] mod Gs)<>0)Then Begin
     Warn(Tensors[TI].Name+' : dimension '+IStr(Tensors[TI].Shape[1])+
          ' non multiple de group_size='+IStr(Gs)+', precision de secours utilisee');
     If BackupMode>=0 Then Begin
      PMode[TI]:=BackupMode;PGroup[TI]:=-1;
     End
      Else
     PMode[TI]:=M_F16;
    End
     Else
    Begin
     PMode[TI]:=PrimaryMode;
     PGroup[TI]:=Gs;
    End;
   End;
   { Mode mixte : --ratio < 1 }
   If OptRatio<1.0 Then Begin
    Write('Calcul de la sensibilite des couches (erreur de quantification) ');
    For I:=0 to NC-1 do Begin
     TI:=Cands[I].TI;
     If PMode[TI]=PrimaryMode Then
      Cands[I].Sens:=QuantError(TI,PrimaryMode,PGroup[TI])
     Else Cands[I].Sens:=1E30;
     If(I mod 14)=0 Then Write('.');
    End;
    WriteLn;
    { Tri par sensibilite croissante }
    For I:=0 to NC-2 do
     For K:=0 to NC-2-I do
      If Cands[K].Sens>Cands[K+1].Sens Then Begin
       Tmp:=Cands[K];Cands[K]:=Cands[K+1];Cands[K+1]:=Tmp;
      End;
    Used:=0;
    Sw:=False;
    For I:=0 to NC-1 do Begin
     TI:=Cands[I].TI;
     If PMode[TI]<>PrimaryMode Then Continue;
     If Not Sw and(Used+Cands[I].Params<=OptRatio*Total+0.5)Then
      Used:=Used+Cands[I].Params
     Else
     Begin
      Sw:=True;
      If BackupMode>=0 Then PMode[TI]:=BackupMode
                       Else PMode[TI]:=M_F16;
      PGroup[TI]:=-1;
     End;
    End;
   End;
  End;
  { Embeddings et lm_head }
  If WFmt<>'int8'Then Begin
   If BackupMode>=0 Then Begin
    PMode[TEmbed]:=BackupMode;PGroup[TEmbed]:=-1;
   End
    Else
   PMode[TEmbed]:=M_F16;
   If OptAllLayers and(THead<>TEmbed)and(PrimaryGroup<=0)or
     (OptAllLayers and(THead<>TEmbed)and(PrimaryGroup>0)and
      ((Tensors[THead].Shape[1] mod PrimaryGroup)=0))Then Begin
    PMode[THead]:=PrimaryMode;PGroup[THead]:=PrimaryGroup;
   End
    Else
   If BackupMode>=0 Then Begin
    PMode[THead]:=BackupMode;PGroup[THead]:=-1;
   End
    Else
   PMode[THead]:=M_F16;
   If THead=TEmbed Then Begin
    PMode[THead]:=PMode[TEmbed];PGroup[THead]:=PGroup[TEmbed];
   End;
  End;
 End;
End;

Procedure PrintStats;
Var
 Cnt:Array[0..6] of LongInt;
 Par:Array[0..6] of Int64;
 L,P,M:LongInt;
 Total:Int64;
 Seen:Array of Boolean;

 Procedure Count(TI:LongInt);
 Begin
  If Seen[TI]Then Exit;
  Seen[TI]:=True;
  Inc(Cnt[PMode[TI]]);
  Par[PMode[TI]]:=Par[PMode[TI]]+Int64(Tensors[TI].Shape[0])*Tensors[TI].Shape[1];
 End;

Begin
 For M:=0 to 6 do Begin
  Cnt[M]:=0;Par[M]:=0;
 End;
 SetLength(Seen,NT);
 For L:=0 to NT-1 do Seen[L]:=False;
 Count(TEmbed);
 If THead<>TEmbed Then Count(THead);
 For L:=0 to Cfg.Layers-1 do
  For P:=0 to 6 do Count(TProj[L][P]);
 Total:=0;
 For M:=0 to 6 do Total:=Total+Par[M];
 WriteLn;
 WriteLn('Repartition des precisions des poids :');
 WriteLn('  Precision      Poids (%)   Couches');
 For M:=0 to 6 do If Cnt[M]>0 Then
  WriteLn('  ',ModeName[M]:-12,' ',FStr(100.0*Par[M]/Total,0):10,'   ',Cnt[M]);
End;

{ ------------------------------------------------------------------ }
{ Construction du graphe LLaMA                                        }
{ ------------------------------------------------------------------ }

Var
 CacheMode:LongInt;
 InputIds,AttnMask,PosIds,BeamIdx:TPort;
 CosP,SinP,MaskP,BatchDim1:TPort;
 NodeCountLinear:LongInt;
 ParamNames:AnsiString;

Function Param(Const Nm:AnsiString;Prec:LongInt;Const Shp:Array of LongInt):TPort;
Var
 Id:LongInt;
 S:TIntArr;
Begin
 S:=SA(Shp);
 Id:=NewNode(0);
 Nodes[Id].Prec[0]:=Prec;
 Nodes[Id].Shp[0]:=S;
 LayersXml.Add('<layer id="'+IStr(Id)+'" name="'+Nm+'" type="Parameter" '+
    'version="opset1">'#10' <data shape="'+ShapeAttr(S)+'" element_type="'+
    ElemName[Prec]+'"/>'#10' <output>'#10'  <port id="0" precision="'+
    PrecName[Prec]+'" names="'+Nm+'">'+DimsXml(S)+'</port>'#10' </output>'#10+
    '</layer>'#10);
 Param:=MkPort(Id,0);
End;

Function Linear(X:TPort;Const W:TWP;Const BiasName:AnsiString;
                OutDim:LongInt;Const Names:AnsiString=''):TPort;
Var
 Wt,R,B:TPort;
Begin
 Wt:=Decomp(W);
 R:=MM(X,Wt,True,[-1,-1,OutDim],Names);
 If BiasName<>''Then Begin
  B:=Vec1D(BiasName,NonQuantHalf);
  R:=Bn('Add',R,B);
 End;
 Linear:=R;
End;

Function RMSNorm(X:TPort;Const WName:AnsiString):TPort;
Var
 Ax,Eps,W,Sq,Mean,Den:TPort;
Begin
 Ax:=CI64([-1],[1]);
 Eps:=CF32s(Cfg.Eps);
 Sq:=Bn('Multiply',X,X);
 Mean:=L1('ReduceMean','ReduceMean','opset1','keep_dims="true"',[Sq,Ax],
          PR_F32,[-1,-1,1]);
 Mean:=Bn('Add',Mean,Eps);
 Den:=Un('Sqrt',Mean);
 W:=Vec1D(WName,NonQuantHalf);
 RMSNorm:=Bn('Multiply',Bn('Divide',X,Den),W);
End;

Function ApplyRope(X:TPort;Heads:LongInt):TPort;
Var
 Ax,X1,X2,Neg,Rot:TPort;
Begin
 Ax:=CI64s(-1);
 L2Split('Split',X,Ax,PR_F32,[-1,Heads,-1,Cfg.HeadDim div 2],X1,X2);
 Neg:=Un('Negative',X2);
 Rot:=Cat([Neg,X1],-1,[-1,Heads,-1,Cfg.HeadDim]);
 ApplyRope:=Bn('Add',Bn('Multiply',X,CosP),Bn('Multiply',Rot,SinP));
End;

Function SplitHeads(X:TPort;Heads:LongInt):TPort;
Var
 R:TPort;
Begin
 R:=Rsh(X,[0,0,Heads,Cfg.HeadDim],[-1,-1,Heads,Cfg.HeadDim]);
 SplitHeads:=Trn(R,[0,2,1,3],[-1,Heads,-1,Cfg.HeadDim]);
End;

{ Cache KV : retourne les cles ou valeurs completes [B,KV,K,HD] }
Function KVCache(NewKV:TPort;L:LongInt;Const Kind:AnsiString):TPort;
Var
 Past,Init,Full,Zero,Bt,Tgt,Rest:TPort;
 VarId,Names:AnsiString;
 X:AnsiString;
 Id:LongInt;
 S:TIntArr;
Begin
 If CacheMode=CM_NONE Then Begin
  KVCache:=NewKV;
  Exit;
 End;
 If CacheMode=CM_STATELESS Then Begin
  Past:=Param('past_key_values.'+IStr(L)+'.'+Kind,PR_F32,[-1,Cfg.KVHeads,-1,Cfg.HeadDim]);
  Full:=Cat([Past,NewKV],2,[-1,Cfg.KVHeads,-1,Cfg.HeadDim],
            'present.'+IStr(L)+'.'+Kind);
  LResult('Result_present_'+IStr(L)+'_'+Kind,Full);
  KVCache:=Full;
  Exit;
 End;
 { Mode "stateful" }
 VarId:=Kind+'_cache.'+IStr(L);
 Zero:=CF32s(0);
 Rest:=CI64([Cfg.KVHeads,0,Cfg.HeadDim],[3]);
 Tgt:=Cat([BatchDim1,Rest],0,[4]);
 Init:=L1('Broadcast','Broadcast','opset3','mode="numpy"',[Zero,Tgt],PR_F32,
          [-1,Cfg.KVHeads,0,Cfg.HeadDim]);
 S:=SA([-1,Cfg.KVHeads,-1,Cfg.HeadDim]);
 Id:=NewNode(1);
 Nodes[Id].Prec[0]:=PR_F32;
 Nodes[Id].Shp[0]:=S;
 LayersXml.Add('<layer id="'+IStr(Id)+'" name="ReadValue_'+VarId+'" type="ReadValue" '+
    'version="opset6">'#10' <data variable_id="'+VarId+
    '" variable_type="f32" variable_shape="'+ShapeAttr(S)+'"/>'#10);
 EmitInputs(Id,[Init]);
 LayersXml.Add(' <output>'#10'  <port id="1" precision="FP32">'+DimsXml(S)+
    '</port>'#10' </output>'#10'</layer>'#10);
 Past:=MkPort(Id,0);
 Past:=Gat(Past,BeamIdx,0,[-1,Cfg.KVHeads,-1,Cfg.HeadDim]);
 Full:=Cat([Past,NewKV],2,[-1,Cfg.KVHeads,-1,Cfg.HeadDim]);
 LAssign(VarId,Full);
 KVCache:=Full;
End;

Function RepeatKV(X:TPort):TPort;
Var
 Rep:LongInt;
 U,T,Bc:TPort;
Begin
 Rep:=Cfg.Heads div Cfg.KVHeads;
 If Rep=1 Then Begin
  RepeatKV:=X;
  Exit;
 End;
 U:=Uns(X,[2],[-1,Cfg.KVHeads,1,-1,Cfg.HeadDim]);
 T:=CI64([1,1,Rep,1,1],[5]);
 Bc:=L1('Broadcast','Broadcast','opset3','mode="bidirectional"',[U,T],PR_F32,
        [-1,Cfg.KVHeads,Rep,-1,Cfg.HeadDim]);
 RepeatKV:=Rsh(Bc,[0,Cfg.Heads,-1,Cfg.HeadDim],[-1,Cfg.Heads,-1,Cfg.HeadDim]);
End;

Procedure BuildGraph;
Var
 L,I,Half,H:LongInt;
 InvFreq:TSingleArr;
 Inv,Wl,Smooth,LowWl,HighWl:Double;
 W:TWP;
 Emb,Hid,Res,N1,Q,K,V,Att,O,Gate,Up,Act,Mlp,Down,Logits:TPort;
 ShIds,ShAm,Q0,Q1,K0,Pad,Causal,QIdx,KIdx,QCol,Past,Zero,NegInf,Cond,Msk:TPort;
 PosF,Freq,Fr2,Emb2,Ident:TPort;
 BiasQ,BiasK,BiasV:AnsiString;
 TI:LongInt;
 Pre:AnsiString;
 EmbG,ZpG,ScG:TPort;
 Wemb:TWP;
 WantsHead:Boolean;
Begin
 H:=Cfg.Hidden;
 Half:=Cfg.HeadDim div 2;
 { Entrees }
 InputIds:=Param('input_ids',PR_I64,[-1,-1]);
 AttnMask:=Param('attention_mask',PR_I64,[-1,-1]);
 PosIds:=Param('position_ids',PR_I64,[-1,-1]);
 If CacheMode=CM_STATEFUL Then BeamIdx:=Param('beam_idx',PR_I32,[-1]);
 { Formes }
 ShIds:=L1('ShapeOf','ShapeOf','opset3','output_type="i64"',[InputIds],PR_I64,[2]);
 ShAm:=L1('ShapeOf','ShapeOf','opset3','output_type="i64"',[AttnMask],PR_I64,[2]);
 BatchDim1:=Gat(ShIds,CI64([0],[1]),0,[1]);
 Q0:=Gat(ShIds,CI64s(1),0,[]);
 K0:=Gat(ShAm,CI64s(1),0,[]);
 { Masque d'attention [B,1,Q,K] }
 Past:=Bn('Subtract',K0,Q0);
 QIdx:=L1('Range','Range','opset4','output_type="i64"',[Past,K0,CI64s(1)],PR_I64,[-1]);
 KIdx:=L1('Range','Range','opset4','output_type="i64"',[CI64s(0),K0,CI64s(1)],PR_I64,[-1]);
 QCol:=Uns(QIdx,[1],[-1,1]);
 Causal:=Bn('LessEqual',KIdx,QCol);
 Causal:=Uns(Causal,[0,1],[1,1,-1,-1]);
 Pad:=Cvt(AttnMask,PR_BOOL);
 Pad:=Uns(Pad,[1,2],[-1,1,1,-1]);
 Cond:=Bn('LogicalAnd',Causal,Pad);
 Zero:=CF32s(0);
 NegInf:=CF32s(-65504.0);
 MaskP:=L1('Select','Select','opset1','auto_broadcast="numpy"',[Cond,Zero,NegInf],
           PR_F32,[-1,1,-1,-1]);
 { Rotary embeddings }
 SetLength(InvFreq,Half);
 For I:=0 to Half-1 do Begin
  Inv:=Exp(-Ln(Cfg.Theta)*(2.0*I)/Cfg.HeadDim);
  If Cfg.RopeType='linear'Then Inv:=Inv/Cfg.RopeFactor Else
  If Cfg.RopeType='llama3'Then Begin
   Wl:=2*Pi/Inv;
   LowWl:=Cfg.RopeOrig/Cfg.RopeLow;
   HighWl:=Cfg.RopeOrig/Cfg.RopeHigh;
   If Wl>LowWl Then Inv:=Inv/Cfg.RopeFactor Else
   If Wl>=HighWl Then Begin
    Smooth:=(Cfg.RopeOrig/Wl-Cfg.RopeLow)/(Cfg.RopeHigh-Cfg.RopeLow);
    Inv:=(1-Smooth)*Inv/Cfg.RopeFactor+Smooth*Inv;
   End;
  End;
  InvFreq[I]:=Inv;
 End;
 Ident:=CF32a(InvFreq,Half,[1,Half,1]);
 PosF:=Cvt(PosIds,PR_F32);
 PosF:=Uns(PosF,[1],[-1,1,-1]);
 Freq:=MM(Ident,PosF,False,[-1,Half,-1]);
 Freq:=Trn(Freq,[0,2,1],[-1,-1,Half]);
 Emb2:=Cat([Freq,Freq],-1,[-1,-1,Cfg.HeadDim]);
 CosP:=Uns(Un('Cos',Emb2),[1],[-1,1,-1,Cfg.HeadDim]);
 SinP:=Uns(Un('Sin',Emb2),[1],[-1,1,-1,Cfg.HeadDim]);
 { Embeddings }
 Wemb:=LoadWeight(TEmbed);
 If(Wemb.Mode=M_F32)Then
  Hid:=Gat(Wemb.Q,InputIds,0,[-1,-1,H])
 Else
 If Wemb.Mode=M_F16 Then
  Hid:=Cvt(Gat(Wemb.Q,InputIds,0,[-1,-1,H]),PR_F32)
 Else
 If Not Wemb.Grouped and((Wemb.Mode=M_I8A)or(Wemb.Mode=M_I8S))Then Begin
  EmbG:=Cvt(Gat(Wemb.Q,InputIds,0,[-1,-1,H]),PR_F16);
  If IsAsym(Wemb.Mode)Then Begin
   ZpG:=Cvt(Gat(Wemb.ZP,InputIds,0,[-1,-1,1]),PR_F16);
   EmbG:=Bn('Subtract',EmbG,ZpG);
  End;
  ScG:=Gat(Wemb.SC,InputIds,0,[-1,-1,1]);
  Hid:=Cvt(Bn('Multiply',EmbG,ScG),PR_F32);
 End
  Else
 Hid:=Gat(Decomp(Wemb),InputIds,0,[-1,-1,H]);
 { Couches du decodeur }
 For L:=0 to Cfg.Layers-1 do Begin
  Write(#13'Construction du graphe : couche ',L+1,'/',Cfg.Layers,'   ');
  Res:=Hid;
  N1:=RMSNorm(Hid,LayerName(L,'input_layernorm.weight'));
  BiasQ:='';BiasK:='';BiasV:='';
  If FindTensor(LayerName(L,'self_attn.q_proj.bias'))>=0 Then
   BiasQ:=LayerName(L,'self_attn.q_proj.bias');
  If FindTensor(LayerName(L,'self_attn.k_proj.bias'))>=0 Then
   BiasK:=LayerName(L,'self_attn.k_proj.bias');
  If FindTensor(LayerName(L,'self_attn.v_proj.bias'))>=0 Then
   BiasV:=LayerName(L,'self_attn.v_proj.bias');
  W:=LoadWeight(TProj[L][0]);
  Q:=Linear(N1,W,BiasQ,Cfg.Heads*Cfg.HeadDim);
  W:=LoadWeight(TProj[L][1]);
  K:=Linear(N1,W,BiasK,Cfg.KVHeads*Cfg.HeadDim);
  W:=LoadWeight(TProj[L][2]);
  V:=Linear(N1,W,BiasV,Cfg.KVHeads*Cfg.HeadDim);
  Q:=SplitHeads(Q,Cfg.Heads);
  K:=SplitHeads(K,Cfg.KVHeads);
  V:=SplitHeads(V,Cfg.KVHeads);
  Q:=ApplyRope(Q,Cfg.Heads);
  K:=ApplyRope(K,Cfg.KVHeads);
  K:=KVCache(K,L,'key');
  V:=KVCache(V,L,'value');
  K:=RepeatKV(K);
  V:=RepeatKV(V);
  Att:=L1('ScaledDotProductAttention','ScaledDotProductAttention','opset13',
          'causal="false"',[Q,K,V,MaskP],PR_F32,[-1,Cfg.Heads,-1,Cfg.HeadDim]);
  Att:=Trn(Att,[0,2,1,3],[-1,-1,Cfg.Heads,Cfg.HeadDim]);
  Att:=Rsh(Att,[0,0,Cfg.Heads*Cfg.HeadDim],[-1,-1,Cfg.Heads*Cfg.HeadDim]);
  W:=LoadWeight(TProj[L][3]);
  O:=Linear(Att,W,'',H);
  Hid:=Bn('Add',Res,O);
  Res:=Hid;
  N1:=RMSNorm(Hid,LayerName(L,'post_attention_layernorm.weight'));
  W:=LoadWeight(TProj[L][4]);
  Gate:=Linear(N1,W,'',Cfg.Inter);
  W:=LoadWeight(TProj[L][5]);
  Up:=Linear(N1,W,'',Cfg.Inter);
  Act:=L1('Swish','Swish','opset4','',[Gate],PR_F32,[-1,-1,Cfg.Inter]);
  Mlp:=Bn('Multiply',Act,Up);
  W:=LoadWeight(TProj[L][6]);
  Down:=Linear(Mlp,W,'',H);
  Hid:=Bn('Add',Res,Down);
 End;
 WriteLn;
 Hid:=RMSNorm(Hid,'model.norm.weight');
 { lm_head }
 If THead=TEmbed Then W:=Wemb
                 Else W:=LoadWeight(THead);
 Logits:=MM(Hid,Decomp(W),True,[-1,-1,Cfg.Vocab],'logits');
 LResult('Result_logits',Logits);
End;

{ ------------------------------------------------------------------ }
{ Ecriture du modele                                                  }
{ ------------------------------------------------------------------ }

Procedure WriteXml(Const Path:AnsiString);
Var
 T:Text;
Begin
 Assign(T,Path);
 {$I-}Rewrite(T);{$I+}
 If IOResult<>0 Then Die('impossible de creer '+Path);
 Write(T,'<?xml version="1.0"?>'#10);
 Write(T,'<net name="Model0" version="11">'#10);
 Write(T,'<layers>'#10);
 LayersXml.WriteTo(T);
 Write(T,'</layers>'#10);
 Write(T,'<edges>'#10);
 EdgesXml.WriteTo(T);
 Write(T,'</edges>'#10);
 Write(T,'<rt_info>'#10'  <framework>'#10'    <item name="pascal" value="optimum-cli.pas"/>'#10+
         '  </framework>'#10'</rt_info>'#10);
 Write(T,'</net>'#10);
 Close(T);
End;

Function JsonBool(B:Boolean):AnsiString;
Begin
 If B Then JsonBool:='true' Else JsonBool:='false';
End;

Procedure WriteOvConfig(Const Path:AnsiString);
Var
 T:Text;
 Bits:LongInt;
 Q:AnsiString;
Begin
 Assign(T,Path);
 {$I-}Rewrite(T);{$I+}
 If IOResult<>0 Then Begin
  Warn('impossible de creer '+Path);
  Exit;
 End;
 WriteLn(T,'{');
 WriteLn(T,'  "compression": null,');
 WriteLn(T,'  "dtype": "',WFmt,'",');
 WriteLn(T,'  "input_info": null,');
 WriteLn(T,'  "optimum_version": "clone-pascal-1.0",');
 If(WFmt='int8')or(WFmt='int4')or(WFmt='nf4')Then Begin
  If WFmt='int8'Then Bits:=8 Else Bits:=4;
  If WFmt='int8'Then Q:='int8'
                Else Q:=WFmt;
  WriteLn(T,'  "quantization_config": {');
  WriteLn(T,'    "all_layers": ',JsonBool(OptAllLayers),',');
  WriteLn(T,'    "backup_precision": "',OptBackup,'",');
  WriteLn(T,'    "bits": ',Bits,',');
  WriteLn(T,'    "dataset": null,');
  WriteLn(T,'    "group_size": ',PrimaryGroup,',');
  WriteLn(T,'    "quant_method": "default",');
  WriteLn(T,'    "ratio": ',FStr(OptRatio,2),',');
  WriteLn(T,'    "sym": ',JsonBool(OptSym),',');
  WriteLn(T,'    "weight_format": "',Q,'"');
  WriteLn(T,'  },');
 End;
 WriteLn(T,'  "save_onnx_model": false,');
 WriteLn(T,'  "stateful": ',JsonBool(CacheMode=CM_STATEFUL),',');
 WriteLn(T,'  "task": "',OptTask,'"');
 WriteLn(T,'}');
 Close(T);
End;

Const
 AuxFiles:Array[0..11] of AnsiString=(
  'generation_config.json','tokenizer.json','tokenizer.model',
  'tokenizer_config.json','special_tokens_map.json','added_tokens.json',
  'vocab.json','merges.txt','chat_template.jinja','chat_template.json',
  'preprocessor_config.json','tiktoken.model');

Procedure CopyAux(Const SrcDir,DstDir:AnsiString);
Var
 I,N:LongInt;
Begin
 N:=0;
 If CopyFileTo(JoinPath(SrcDir,'config.json'),JoinPath(DstDir,'config.json'))Then Inc(N);
 For I:=0 to High(AuxFiles) do
  If FileExists(JoinPath(SrcDir,AuxFiles[I]))Then
   If CopyFileTo(JoinPath(SrcDir,AuxFiles[I]),JoinPath(DstDir,AuxFiles[I]))Then Inc(N);
 WriteLn(N,' fichier(s) de configuration/tokenizer copie(s).');
End;

{ ------------------------------------------------------------------ }
{ Programme principal                                                 }
{ ------------------------------------------------------------------ }

Var
 ModelDir,OutDir,XmlPath,BinPath:AnsiString;
 FinalTask:AnsiString;
 I:LongInt;

Begin
 ParseArgs;
 WFmt:=OptWeightFormat;
 If OptAwq or OptGptq or OptScaleEst or OptLora or(OptDataset<>'')Then
  Warn('options de calibration (--dataset, --awq, --gptq, --scale-estimation, '+
       '--lora-correction) ignorees : aucun jeu de donnees n''est evalue');
 If OptQuantMode<>''Then
  Warn('--quant-mode ignore : seule la compression des poids est geree');
 If(OptDevice<>'')and(LoStr(OptDevice)<>'cpu')Then
  Warn('--device '+OptDevice+' ignore (aucun effet dans ce clone)');
 If OptRatioGiven and(WFmt<>'int4')and(WFmt<>'nf4')Then
  Warn('--ratio n''a d''effet qu''avec --weight-format int4 ou nf4');
 { Tache }
 FinalTask:=LoStr(OptTask);
 If(FinalTask='auto')or(FinalTask='')Then FinalTask:='text-generation-with-past';
 If FinalTask='text-generation-with-past'Then Begin
  If OptDisableStateful Then CacheMode:=CM_STATELESS
                        Else CacheMode:=CM_STATEFUL;
 End
  Else
 If FinalTask='text-generation'Then CacheMode:=CM_NONE
 Else Die('tache non prise en charge : '+OptTask+
          ' (text-generation-with-past ou text-generation)');
 OptTask:=FinalTask;
 WriteLn('optimum-cli export openvino (',VersionStr,')');
 ModelDir:=ResolveModel(OptModel);
 WriteLn('Modele          : ',ModelDir);
 LoadConfig(ModelDir);
 WriteLn('Architecture    : ',Cfg.ModelType,' (',Cfg.Layers,' couches, hidden=',Cfg.Hidden,
         ', heads=',Cfg.Heads,'/',Cfg.KVHeads,', vocab=',Cfg.Vocab,')');
 LoadWeights(ModelDir);
 WriteLn(NT,' tenseurs dans ',NShards,' fichier(s) safetensors.');
 PlanQuantization;
 WriteLn('Tache           : ',FinalTask);
 Write('Format des poids : ',WFmt);
 If Is4Bit(PrimaryMode)Then Begin
  If PrimaryGroup>0 Then Write(' (group_size=',PrimaryGroup,', ',ModeName[PrimaryMode],')')
                    Else Write(' (par canal, ',ModeName[PrimaryMode],')');
  Write(', ratio=',FStr(OptRatio,2));
 End;
 WriteLn;
 OutDir:=OptOutput;
 MakeDirs(OutDir);
 If Not DirExists(OutDir)Then Die('impossible de creer le dossier '+OutDir);
 XmlPath:=JoinPath(OutDir,'openvino_model.xml');
 BinPath:=JoinPath(OutDir,'openvino_model.bin');
 SetLength(BinBuf,BinCap);
 BinFill:=0;BinPos:=0;NibPend:=-1;
 Assign(BinF,BinPath);
 {$I-}Rewrite(BinF,1);{$I+}
 If IOResult<>0 Then Die('impossible de creer '+BinPath);
 LayersXml:=TBuf.Create;
 EdgesXml:=TBuf.Create;
 NNodes:=0;
 BuildGraph;
 BinFlush;
 Close(BinF);
 WriteXml(XmlPath);
 WriteOvConfig(JoinPath(OutDir,'openvino_config.json'));
 CopyAux(ModelDir,OutDir);
 For I:=0 to NShards-1 do Close(Shards[I].F);
 PrintStats;
 WriteLn;
 WriteLn('Modele OpenVINO enregistre dans ',OutDir);
 WriteLn('  ',XmlPath);
 WriteLn('  ',BinPath,' (',BinPos div 1048576,' Mo)');
 If Not OptNoTokenizer Then
  WriteLn('Note : openvino_tokenizer.xml n''est pas genere par ce clone (tokenizer copie tel quel).');
End.
