{ @author: Sylvain Maltais (support@gladir.com)
 @created: 2026
 @version: 1.00
 @website(https://www.gladir.com/vie)
 @website(https://www.gladir.com/speech-to-text-0)
 @abstract(Target: Free Pascal 3.2
 @description: Clone de la commande whisper-cli }

Program WHISPER_CLI;

{$A-}
{$MODE FPC}{$H+}
{ Moteur Whisper procedural integre. Free Pascal 3.2+, memoire 32/64 bits.
  Pas de moteur externe, objets, SysUtils, Classes ou Math.
  L'inference neuronale et les tableaux dynamiques ne tiennent pas dans
  l'environnement 16 bits de Turbo Pascal DOS.
  Reference des architectures et licences: THIRD_PARTY_NOTICES.md. }

Uses DOS;

Type
 Integer = LongInt;
 TBinary = Record
  Handle: File;
  Name: String;
  Size, Position: Int64;
  Buffer: Array[0..8191] Of Byte;
  Used, Index: LongInt;
  Writing: Boolean;
 End;
 PBinary = ^TBinary;
 TSamples = Array Of Single;
 TStringVector = Array Of String;

Const
 TargetRate = 16000;
 MaxInputBytes = 268435456;
 MaxSeconds = 1800;
 NativeVersion = '1.0.0';

Var
 OpenFiles: Array[0..7] Of PBinary;
 ThreadCount: Integer;
 PendingExports: TStringVector;
 SilentConsole, ConsoleReady: Boolean;
 ConsoleLock: TRTLCriticalSection;
Procedure Fail(Const S: String);Forward;

Function IntToStr(Value: Int64): String;Begin
 Str(Value, IntToStr);
End;

Function RealText(Value: Double): String;Begin
 Str(Value:0:6, RealText);
End;

Procedure Diagnostic(Const Text: String);Begin
 If SilentConsole Then Exit;
 If ConsoleReady Then EnterCriticalSection(ConsoleLock);
 WriteLn(StdErr, Text);
 If ConsoleReady Then LeaveCriticalSection(ConsoleLock);
End;

Function Trim(Const Text: String): String;
Var
 First, Last: Integer;
Begin
 First := 1; Last := Length(Text);
 While (First <= Last) And (Text[First] <= ' ') Do Inc(First);
 While (Last >= First) And (Text[Last] <= ' ') Do Dec(Last);
 Trim := Copy(Text, First, Last - First + 1);
End;

Function PathAttributes(Const Name: String; Var Attributes: Word): Boolean;
Var
 F: File;
Begin
 Assign(F, Name);
 DOS.GetFAttr(F, Attributes);
 PathAttributes := DosError = 0;
End;

Function FileExists(Const Name: String): Boolean;
Var
 Attributes: Word;
Begin
 FileExists := PathAttributes(Name, Attributes);
 If FileExists Then FileExists := (Attributes And Directory) = 0;
End;

Function MinInt(A, B: Integer): Integer;Begin
 If A < B Then MinInt := A Else MinInt := B;
End;

Function MinDouble(A, B: Double): Double;Begin
 If A < B Then MinDouble := A Else MinDouble := B;
End;

Function Max(A, B: Integer): Integer;Begin
 If A > B Then Max := A Else Max := B;
End;

Function EnsureRange(Value, LowerBound, UpperBound: Double): Double;Begin
 If Value < LowerBound Then EnsureRange := LowerBound Else
 If Value > UpperBound Then EnsureRange := UpperBound
                       Else EnsureRange := Value;
End;

Function Floor(Value: Double): Int64;Begin
 Floor := Trunc(Value);
 If Value < Floor Then Dec(Floor);
End;

Function Ceil(Value: Double): Int64;Begin
 Ceil := Trunc(Value);
 If Value > Ceil Then Inc(Ceil);
End;

Function IsNan(Const Value: Single): Boolean;
Var
 Bits: LongWord;
Begin
 Move(Value, Bits, SizeOf(Bits));
 IsNan := ((Bits And $7F800000) = $7F800000) And
 ((Bits And $007FFFFF) <> 0);
End;

Function IsInfinite(Const Value: Single): Boolean;
Var
 Bits: LongWord;
Begin
 Move(Value, Bits, SizeOf(Bits));
 IsInfinite := (Bits And $7FFFFFFF) = $7F800000;
End;

Function Bounded(Value, LowBound, HighBound: LongInt; Const What: String): LongInt;Begin
 If (Value < LowBound) Or (Value > HighBound) Then Fail('Valeur invalide: ' + What);
 Bounded := Value;
End;

Procedure Fail(Const S: String);
Var
 I, ErrorCode: Integer;
 F: File;
Begin
 WriteLn(StdErr, 'WHISPER-CLI: ', S);
  { Fermer les fichiers encore ouverts avant de supprimer les temporaires.
    Les pointeurs concernent des records toujours presents sur la pile. }
 For I := 0 To High(OpenFiles) Do    If OpenFiles[I] <> Nil Then Begin
      {$I-}
  Close(OpenFiles[I]^.Handle); ErrorCode := IOResult;
      {$I+}
  If ErrorCode <> 0 Then WriteLn(StdErr, 'Fermeture incomplete: ', OpenFiles[I]^.Name);
  OpenFiles[I] := Nil;
 End;
 For I := 0 To High(PendingExports) Do Begin
  Assign(F, PendingExports[I]);
  {$I-} Erase(F); ErrorCode := IOResult; {$I+}
 End;
 Halt(1);
End;

Procedure OpenBinary(Var S: TBinary; Const Name: String; Writing: Boolean);
Var
 I, ErrorCode: Integer;
 OldMode: Byte;
Begin
 S.Name := Name; S.Position := 0; S.Used := 0; S.Index := 0;
 S.Writing := Writing; S.Size := 0;
 Assign(S.Handle, Name);
 OldMode := FileMode; FileMode := $20; { lecture, partage sans ecriture }
  {$I-}
 If Writing Then Rewrite(S.Handle, 1) Else Reset(S.Handle, 1);
 ErrorCode := IOResult;
  {$I+}
 FileMode := OldMode;
 If ErrorCode <> 0 Then Fail('Ouverture impossible: ' + Name + ' (code ' + IntToStr(
 ErrorCode) + ')');
 I := 0;
 While (I <= High(OpenFiles)) And (OpenFiles[I] <> Nil) Do Inc(I);
 If I > High(OpenFiles) Then Begin
    {$I-}Close(S.Handle); ErrorCode := IOResult;{$I+}
  Fail('Trop de fichiers ouverts.');
 End;
 OpenFiles[I] := @S;
  {$I-}
 S.Size := FileSize(S.Handle); ErrorCode := IOResult;
  {$I+}
 If ErrorCode <> 0 Then Fail('Taille inaccessible: ' + Name);
End;

Procedure FlushBinary(Var S: TBinary);
Var
 Count, ErrorCode: LongInt;
Begin
 If Not S.Writing Or (S.Used = 0) Then Exit;
  {$I-}
 BlockWrite(S.Handle, S.Buffer, S.Used, Count); ErrorCode := IOResult;
  {$I+}
 If (ErrorCode <> 0) Or (Count <> S.Used) Then Fail('Ecriture incomplete: ' + S.Name);
 S.Used := 0;
End;

Procedure CloseBinary(Var S: TBinary);
Var
 I, ErrorCode: Integer;
Begin
 FlushBinary(S);
  {$I-}Close(S.Handle); ErrorCode := IOResult;{$I+}
 For I := 0 To High(OpenFiles) Do    If OpenFiles[I] = @S Then OpenFiles[I] := Nil;
 If ErrorCode <> 0 Then Fail('Fermeture impossible: ' + S.Name);
End;

Procedure ReadBytes(Var S: TBinary; Var Dest; Count: LongInt);
Var
 P: PByte;
 N, ErrorCode: LongInt;
Begin
 P := @Dest;
 While Count > 0 Do Begin
  If S.Index = S.Used Then Begin
      {$I-}
   BlockRead(S.Handle, S.Buffer, SizeOf(S.Buffer), S.Used); ErrorCode := IOResult;
      {$I+}
   If (ErrorCode <> 0) Or (S.Used = 0) Then Fail('Lecture incomplete: ' + S.Name);
   S.Index := 0;
  End;
  N := MinInt(Count, S.Used - S.Index);
  Move(S.Buffer[S.Index], P^, N);
  Inc(P, N); Inc(S.Index, N); Inc(S.Position, N); Dec(Count, N);
 End;
End;

Procedure SeekBinary(Var S: TBinary; Position: Int64);
Var
 ErrorCode: Integer;
Begin
 FlushBinary(S);
  {$I-}Seek(S.Handle, Position); ErrorCode := IOResult;{$I+}
 If ErrorCode <> 0 Then Fail('Position inaccessible: ' + S.Name);
 S.Position := Position; S.Index := 0; S.Used := 0;
End;

Function U16(Var S: TBinary): Word;
Var
 B: Array[0..1] Of Byte;
Begin
 ReadBytes(S, B, 2);
 U16 := Word(B[0]) Or (Word(B[1]) Shl 8);
End;

Function U32(Var S: TBinary): LongWord;
Var
 B: Array[0..3] Of Byte;
Begin
 ReadBytes(S, B, 4);
 U32 := LongWord(B[0]) Or (LongWord(B[1]) Shl 8) Or
 (LongWord(B[2]) Shl 16) Or (LongWord(B[3]) Shl 24);
End;

Function FourCC(Var S: TBinary): AnsiString;Begin
 SetLength(FourCC, 4);
 ReadBytes(S, FourCC[1], 4);
End;

Procedure ReadWave(Const Name: String; Var Samples: TSamples; Var Rate: LongWord;
                   KeepStereo: Boolean; Var Left, Right: TSamples);
Var
 S: TBinary;
 ID: String;
 ChunkSize, RiffSize, ByteRate, V: LongWord;
 Limit, ChunkEnd, DataPos, DataSize, Frames: Int64;
 Fmt, Channels, Bits, BlockSize: Word;
 HaveFmt, HaveData: Boolean;
 C, I: Integer;
 ThirdByte: Byte;
 SignedValue: Int64;
 X, Sum: Double;
 F: Single;
Begin
 OpenBinary(S, Name, False);
 If (S.Size < 12) Or (S.Size > MaxInputBytes) Then      Fail(
 'WAV vide, trop court ou superieur a 256 Mio.');
 If FourCC(S) <> 'RIFF' Then Fail('Seul RIFF WAV little-endian est accepte.');
 RiffSize := U32(S);
 If FourCC(S) <> 'WAVE' Then Fail('Signature WAVE absente.');
 Limit := Int64(RiffSize) + 8;
 If (Limit > S.Size) Or (Limit < 12) Then Fail('Taille RIFF invalide.');
 HaveFmt := False; HaveData := False;
 Fmt := 0; Channels := 0; Bits := 0; BlockSize := 0; Rate := 0;
 DataPos := 0; DataSize := 0;
 While S.Position < Limit Do Begin
  If Limit - S.Position < 8 Then Fail('Entete de chunk tronquee.');
  ID := FourCC(S); ChunkSize := U32(S);
  ChunkEnd := S.Position + Int64(ChunkSize);
  If ChunkEnd + (ChunkSize And 1) > Limit Then Fail('Chunk WAV tronque.');
  If ID = 'fmt ' Then Begin
   If HaveFmt Or (ChunkSize < 16) Then Fail('Chunk fmt invalide ou repete.');
   Fmt := U16(S); Channels := U16(S); Rate := U32(S);
   ByteRate := U32(S); BlockSize := U16(S); Bits := U16(S);
   If Not (Fmt In [1, 3]) Then          Fail(
   'Encodage non pris en charge: utiliser PCM ou float IEEE WAV.');
   If (Channels < 1) Or (Channels > 8) Or (Rate < 8000) Or (Rate > 192000)
   Then          Fail('Canaux (1..8) ou frequence (8000..192000) invalides.');
   If ((Fmt = 1) And Not (Bits In [8,16,24,32])) Or
   ((Fmt = 3) And (Bits <> 32)) Then Fail('Resolution WAV non prise en charge.');
   If (BlockSize <> Channels * (Bits Div 8)) Or
   (ByteRate <> Rate * LongWord(BlockSize)) Then Fail('Alignement PCM invalide.');
   HaveFmt := True;
  End
  Else If ID = 'data' Then Begin
   If HaveData Then Fail('Plusieurs chunks data non pris en charge.');
   DataPos := S.Position; DataSize := ChunkSize; HaveData := True;
  End;
  SeekBinary(S, ChunkEnd + (ChunkSize And 1));
 End;
 If Not HaveFmt Or Not HaveData Then Fail('Chunks fmt/data manquants.');
 If (DataSize = 0) Or (DataSize Mod BlockSize <> 0) Then Fail('Donnees PCM incompletes.');
 Frames := DataSize Div BlockSize;
 If Frames > Int64(Rate) * MaxSeconds Then Fail('Duree maximale: 30 minutes.');
 If KeepStereo And (Channels <> 2) Then Fail(
 '--diarize exige un WAV stereo a deux canaux.');
 Left := Nil; Right := Nil;
 If KeepStereo Then Begin
  SetLength(Left, Frames); SetLength(Right, Frames);
 End;
 SetLength(Samples, Frames);
 SeekBinary(S, DataPos);
 For I := 0 To Frames - 1 Do Begin
  Sum := 0;
  For C := 1 To Channels Do Begin
   V := 0;
   Case Bits Of
   8: ReadBytes(S, V, 1);
   16: V := U16(S);
   24:
   Begin
    V := U16(S); ReadBytes(S, ThirdByte, 1);
    V := V Or (LongWord(ThirdByte) Shl 16);
   End;
   32: V := U32(S);
  End;
  If Fmt = 3 Then Begin
   Move(V, F, 4);
   If IsNan(F) Or IsInfinite(F) Then Fail('Echantillon float non fini.');
   X := F;
  End
  Else If Bits = 8 Then X := (Integer(V) - 128) / 128.0
   Else
  Begin
   SignedValue := V;
   If (QWord(V) And (QWord(1) Shl (Bits - 1))) <> 0 Then            SignedValue :=
   SignedValue - (Int64(1) Shl Bits);
   X := SignedValue / (Int64(1) Shl (Bits - 1));
  End;
  X := EnsureRange(X, -1.0, 1.0);
  If KeepStereo Then Begin
   If C = 1 Then Left[I] := X Else Right[I] := X;
  End;
  Sum := Sum + X;
 End;
 Samples[I] := Sum / Channels;
End;
CloseBinary(S);
End;

Procedure Resample(Const Source: TSamples; Rate: LongWord; Var Dest: TSamples);
Var
 I, J, Center, Radius, Count: Integer;
 Position, Distance, Cutoff, Weight, Total, Norm, Angle: Double;
Begin
 If Rate = TargetRate Then Begin
  Dest := Copy(Source); Exit;
 End;
 Count := (Int64(Length(Source)) * TargetRate + Rate - 1) Div Rate;
 SetLength(Dest, Count);
  { Sinc fenetree Hann, filtre anti-repliement avant sous-echantillonnage.
    Le support augmente avec le rapport des frequences. }
 Cutoff := 0.94 * MinDouble(1.0, TargetRate / Rate);
 Radius := Ceil(16 / Cutoff);
 For I := 0 To Count - 1 Do Begin
  Position := I * (Double(Rate) / TargetRate);
  Center := Floor(Position); Total := 0; Norm := 0;
  For J := Max(0, Center - Radius) To MinInt(High(Source), Center + Radius) Do Begin
   Distance := Position - J;
   If Abs(Distance) >= Radius Then Continue;
   Angle := Pi * Distance * Cutoff;
   If Abs(Angle) < 1E-12 Then Weight := Cutoff
                         Else Weight := Cutoff * Sin(Angle) / Angle;
   Weight := Weight * (0.5 + 0.5 * Cos(Pi * Distance / Radius));
   Total := Total + Source[J] * Weight; Norm := Norm + Weight;
  End;
  If Abs(Norm) > 1E-12 Then Dest[I] := Total / Norm Else Dest[I] := 0;
 End;
End;

Procedure RemoveDC(Var Samples: TSamples);
Var
 I: Integer;
 PrevIn, PrevOut, X: Double;
Begin
  { Passe-haut doux ~40 Hz; pas de gate qui supprimerait les consonnes.
    Le bruit restant est gere par VAD et le modele acoustique entraine. }
 PrevIn := 0; PrevOut := 0;
 For I := 0 To High(Samples) Do Begin
  X := Samples[I] - PrevIn + 0.9844 * PrevOut;
  PrevIn := Samples[I]; PrevOut := X;
  Samples[I] := EnsureRange(X, -1.0, 1.0);
 End;
End;

Type
 TTensor = Record
  Name: String;
  Dims: Array[0..3] Of Integer;
  Rank: Integer;
  Data: TSamples;
 End;
 TTensors = Array Of TTensor;
 TMatrix = Record
  Rows, Cols: Integer;
  Data: TSamples;
 End;
 TAttentionWeights = Record
  Q, QB, K, V, VB, O, OB, LN, LNB: Integer;
 End;
 TWhisperLayer = Record
  Attention, Cross: TAttentionWeights;
  MLP0, MLP0B, MLP2, MLP2B, MLPNorm, MLPNormB: Integer;
 End;
 TWhisperModel = Record
  Tensors: TTensors;
  Vocab: TStringVector;
  AudioContext, AudioWidth, AudioHeads, AudioLayers, TextContext, TextWidth, TextHeads,
  TextLayers, MelCount, VocabCount: Integer;
  Conv1, Conv1B, Conv2, Conv2B, AudioPosition, AudioNorm, AudioNormB, TextPosition,
  TextNorm, TextNormB, Embedding: Integer;
  Encoder, Decoder: Array Of TWhisperLayer;
  Filters: TSamples;
  EOT, SOT, French, Transcribe, NoSpeech, NoTimestamps: Integer;
  TinyDiarize: Boolean;
  DTWHeads: Array Of LongWord;
  Suppressed: Array Of Boolean;
 End;
 TDecoderCache = Record
  SelfK, SelfV, CrossK, CrossV: TMatrix;
  Alignment: TMatrix;
  CaptureDTW: Boolean;
  DTWFrames: Integer;
 End;
 TDecoderCaches = Array Of TDecoderCache;

Function HalfToSingle(Value: Word): Single;
Var
 Bits, Mantissa, Exponent: LongWord;
Begin
 Bits := LongWord(Value And $8000) Shl 16;
 Mantissa := Value And $3FF; Exponent := (Value Shr 10) And 31;
 If Exponent = 0 Then Begin
  If Mantissa <> 0 Then Begin
   Exponent := 113;
   While (Mantissa And $400) = 0 Do Begin
    Mantissa := Mantissa Shl 1; Dec(Exponent);
   End;
   Bits := Bits Or (Exponent Shl 23) Or ((Mantissa And $3FF) Shl 13);
  End;
 End Else If Exponent = 31 Then Bits := Bits Or $7F800000 Or (Mantissa Shl 13)
                           Else Bits := Bits Or ((Exponent + 112) Shl 23) Or (Mantissa Shl 13);
 Move(Bits, HalfToSingle, 4);
End;

Procedure ReadFloatArray(Var S: TBinary; Count, Kind: Integer; Var Values: TSamples);
Var
 I: Integer;
 Raw: Array Of Word;
Begin
 If Not (Kind In [0,1]) Then Fail(
 'Tenseur GGML quantifie/non pris en charge; utiliser un modele FP16 ou FP32.');
 If (Count < 0) Or (Int64(Count) * (4 - Kind * 2) > S.Size - S.Position) Then Fail(
 'Tenseur GGML tronque.');
 SetLength(Values, Count);
 If Kind = 0 Then Begin
  If Count > 0 Then ReadBytes(S, Values[0], Count * 4);
 End
  Else
 Begin
  SetLength(Raw, Count); If Count > 0 Then ReadBytes(S, Raw[0], Count * 2);
  For I := 0 To Count - 1 Do Values[I] := HalfToSingle(Raw[I]);
 End;
 For I := 0 To Count - 1 Do If IsNan(Values[I]) Or IsInfinite(Values[I]) Then Fail(
 'Poids GGML non fini.');
End;

Procedure ReadTensorTable(Var S: TBinary; Var Tensors: TTensors);
Var
 N, I, J, Count, NameLength, Kind: Integer;
 Total: Int64;
 Name: String;
Begin
 SetLength(Tensors, 0); Total := 0;
 While S.Position < S.Size Do Begin
  N := Length(Tensors); If N >= 2000 Then Fail('Trop de tenseurs GGML.');
  SetLength(Tensors, N + 1);
  Tensors[N].Rank := Bounded(LongInt(U32(S)), 0, 4, 'rang GGML');
  NameLength := Bounded(LongInt(U32(S)), 1, 256, 'nom tenseur'); Kind := LongInt(U32(S));
  Count := 1;
  For I := 0 To 3 Do Begin
   Tensors[N].Dims[I] := 1;
   If I < Tensors[N].Rank Then Tensors[N].Dims[I] := Bounded(LongInt(U32(S)), 1, 100000,
   'dimension tenseur');
   If Int64(Count) * Tensors[N].Dims[I] > 300000000 Then Fail('Tenseur GGML trop grand.');
   Count := Count * Tensors[N].Dims[I];
  End;
  Total := Total + Int64(Count) * 4;
  If Total > 1400000000 Then Fail(
  'Modele trop grand pour cette implementation CPU (1,4 Go de poids FP32 maximum).');
  SetLength(Name, NameLength); ReadBytes(S, Name[1], NameLength);
  For J := 0 To N - 1 Do If Tensors[J].Name = Name Then Fail('Tenseur GGML repete: ' +
  Name);
  Tensors[N].Name := Name; ReadFloatArray(S, Count, Kind, Tensors[N].Data);
 End;
End;

Function TensorID(Const Tensors: TTensors; Const Name: String;
                  Const Shape: Array Of Integer): Integer;
Var
 I, J: Integer;
Begin
 For I := 0 To High(Tensors) Do If Tensors[I].Name = Name Then Begin
  For J := 0 To High(Shape) Do If Tensors[I].Dims[J] <> Shape[J] Then Fail(
  'Dimensions incorrectes: ' + Name);
  For J := Length(Shape) To 3 Do If Tensors[I].Dims[J] <> 1 Then Fail(
  'Dimensions supplementaires: ' + Name);
  Begin
   TensorID := I; Exit;
  End;
 End;
 Fail('Tenseur manquant: ' + Name); TensorID := -1;
End;

Procedure BindAttention(Const T: TTensors; Const Prefix, Norm: String; Width: Integer;
                        Var W: TAttentionWeights);Begin
 W.Q := TensorID(T, Prefix + '.query.weight', [Width,Width]);
 W.QB := TensorID(T, Prefix + '.query.bias', [Width]);
 W.K := TensorID(T, Prefix + '.key.weight', [Width,Width]);
 W.V := TensorID(T, Prefix + '.value.weight', [Width,Width]);
 W.VB := TensorID(T, Prefix + '.value.bias', [Width]);
 W.O := TensorID(T, Prefix + '.out.weight', [Width,Width]);
 W.OB := TensorID(T, Prefix + '.out.bias', [Width]);
 W.LN := TensorID(T, Norm + '.weight', [Width]);
 W.LNB := TensorID(T, Norm + '.bias', [Width]);
End;

Procedure BindWhisperLayer(Const T: TTensors; Const Prefix: String; Width: Integer;
                           Decoder: Boolean; Var L: TWhisperLayer);Begin
 BindAttention(T, Prefix + '.attn', Prefix + '.attn_ln', Width, L.Attention);
 If Decoder Then BindAttention(T, Prefix + '.cross_attn', Prefix + '.cross_attn_ln',
 Width, L.Cross);
 L.MLP0 := TensorID(T, Prefix + '.mlp.0.weight', [Width,Width*4]);
 L.MLP0B := TensorID(T, Prefix + '.mlp.0.bias', [Width*4]);
 L.MLP2 := TensorID(T, Prefix + '.mlp.2.weight', [Width*4,Width]);
 L.MLP2B := TensorID(T, Prefix + '.mlp.2.bias', [Width]);
 L.MLPNorm := TensorID(T, Prefix + '.mlp_ln.weight', [Width]);
 L.MLPNormB := TensorID(T, Prefix + '.mlp_ln.bias', [Width]);
End;

Procedure LoadWhisper(Const FileName: String; Var M: TWhisperModel);
Var
 S: TBinary;
 I, Count, N, Kind: Integer;
Begin
 M.TinyDiarize := False;
 OpenBinary(S, FileName, False);
 If U32(S) <> $67676D6C Then Fail(
 'Modele Whisper GGML requis (GGUF/ONNX non pris en charge).');
 M.VocabCount := Bounded(LongInt(U32(S)), 51864, 51866, 'vocabulaire Whisper')
 ;
 M.AudioContext := Bounded(LongInt(U32(S)), 1500, 1500, 'contexte audio Whisper');
 M.AudioWidth := Bounded(LongInt(U32(S)), 4, 1536, 'largeur encodeur');
 M.AudioHeads := Bounded(LongInt(U32(S)), 1, 32, 'tetes encodeur');
 M.AudioLayers := Bounded(LongInt(U32(S)), 1, 32, 'couches encodeur');
 M.TextContext := Bounded(LongInt(U32(S)), 8, 448, 'contexte texte');
 M.TextWidth := Bounded(LongInt(U32(S)), 4, 1536, 'largeur decodeur');
 M.TextHeads := Bounded(LongInt(U32(S)), 1, 32, 'tetes decodeur');
 M.TextLayers := Bounded(LongInt(U32(S)), 1, 32, 'couches decodeur');
 M.MelCount := LongInt(U32(S)); Kind := LongInt(U32(S));
 If Not (M.MelCount In [80,128]) Or (M.AudioWidth <> M.TextWidth) Or
 (M.AudioWidth Mod M.AudioHeads <> 0) Or (M.TextWidth Mod M.TextHeads <> 0) Then Fail(
 'Architecture Whisper non prise en charge.');
 If Not (Kind In [0,1]) Then Fail('Modele Whisper FP16/FP32 non quantifie requis.');
 If (U32(S) <> LongWord(M.MelCount)) Or (U32(S) <> 201) Then Fail(
 'Filtres mel Whisper invalides.');
 ReadFloatArray(S, M.MelCount * 201, 0, M.Filters);
 Count := Bounded(LongInt(U32(S)), 50256, M.VocabCount, 'tokens GGML');
 SetLength(M.Vocab, M.VocabCount);
 For I := 0 To Count - 1 Do Begin
  N := Bounded(LongInt(U32(S)), 0, 4096, 'longueur token'); SetLength(M.Vocab[I], N);
  If N > 0 Then ReadBytes(S, M.Vocab[I][1], N);
 End;
 ReadTensorTable(S, M.Tensors); CloseBinary(S);
 M.Conv1 := TensorID(M.Tensors, 'encoder.conv1.weight', [3,M.MelCount,M.AudioWidth]);
 M.Conv1B := TensorID(M.Tensors, 'encoder.conv1.bias', [1,M.AudioWidth]);
 M.Conv2 := TensorID(M.Tensors, 'encoder.conv2.weight', [3,M.AudioWidth,M.AudioWidth]);
 M.Conv2B := TensorID(M.Tensors, 'encoder.conv2.bias', [1,M.AudioWidth]);
 M.AudioPosition := TensorID(M.Tensors, 'encoder.positional_embedding', [M.AudioWidth,
 M.AudioContext]);
 M.AudioNorm := TensorID(M.Tensors, 'encoder.ln_post.weight', [M.AudioWidth]);
 M.AudioNormB := TensorID(M.Tensors, 'encoder.ln_post.bias', [M.AudioWidth]);
 M.Embedding := TensorID(M.Tensors, 'decoder.token_embedding.weight', [M.TextWidth,
 M.VocabCount]);
 M.TextPosition := TensorID(M.Tensors, 'decoder.positional_embedding', [M.TextWidth,
 M.TextContext]);
 M.TextNorm := TensorID(M.Tensors, 'decoder.ln.weight', [M.TextWidth]);
 M.TextNormB := TensorID(M.Tensors, 'decoder.ln.bias', [M.TextWidth]);
 SetLength(M.Encoder, M.AudioLayers); SetLength(M.Decoder, M.TextLayers);
 For I := 0 To M.AudioLayers - 1 Do BindWhisperLayer(M.Tensors, 'encoder.blocks.' +
 IntToStr(I), M.AudioWidth, False, M.Encoder[I]);
 For I := 0 To M.TextLayers - 1 Do BindWhisperLayer(M.Tensors, 'decoder.blocks.' +
 IntToStr(I), M.TextWidth, True, M.Decoder[I]);
 M.EOT := 50256; If M.VocabCount > 51864 Then Inc(M.EOT);
 M.SOT := M.EOT + 1; M.French := M.SOT + 7;
 M.Transcribe := 50359 + M.VocabCount - 51865;
 M.NoSpeech := 50362 + M.VocabCount - 51865;
 M.NoTimestamps := 50363 + M.VocabCount - 51865;
 If Not SilentConsole Then WriteLn(StdErr, 'Whisper natif: ', M.AudioLayers,
 ' couches encodeur, ', M.TextLayers,
 ' couches decodeur, largeur ', M.AudioWidth, '.');
End;
{$IFDEF CPU386}
{$ASMMODE INTEL}

 Function NeuralDot(A, B: PSingle; N: LongInt): Single;
 register; assembler; nostackframe;
 Asm
 push esi
 push edi
 mov esi,eax
 mov edi,edx
 xorps xmm0,xmm0
 @@vector:
 cmp ecx,4
 jl @@tail
 movups xmm1,[esi]
 movups xmm2,[edi]
 mulps xmm1,xmm2
 addps xmm0,xmm1
 add esi,16
 add edi,16
 sub ecx,4
 jmp @@vector
 @@tail:
 test ecx,ecx
 jz @@sum
 movss xmm1,[esi]
 mulss xmm1,[edi]
 addss xmm0,xmm1
 add esi,4
 add edi,4
 dec ecx
 jmp @@tail
 @@sum:
 movaps xmm1,xmm0
 movhlps xmm1,xmm0
 addps xmm0,xmm1
 movaps xmm1,xmm0
 shufps xmm1,xmm1,$55
 addss xmm0,xmm1
 sub esp,4
 movss [esp],xmm0
 fld dword ptr [esp]
 add esp,4
 pop edi
 pop esi
 End;
{$ELSE}

 Function NeuralDot(A, B: PSingle; N: LongInt): Single;
 Var
  I: Integer;
  Value: Double;
 Begin
  Value := 0;
  For I := 1 To N Do Begin
   Value := Value + A^ * B^; Inc(A); Inc(B);
  End;
  NeuralDot := Value;
 End;
{$ENDIF}

Procedure MatrixSize(Var M: TMatrix; Rows, Cols: Integer);Begin
 If (Rows < 0) Or (Cols <= 0) Or (Int64(Rows) * Cols > 100000000) Then Fail(
 'Matrice neuronale trop grande.');
 M.Rows := Rows; M.Cols := Cols; SetLength(M.Data, Rows * Cols);
End;

Type
 TFloatMemory = Array[0..268435455] Of Single;
 PFloatMemory = ^TFloatMemory;
 TDenseJob = Record
  X, Weight, Bias, Y: PFloatMemory;
  First, Last, Inputs, Outputs: Integer;
 End;
 PDenseJob = ^TDenseJob;

Procedure JoinThread(Handle: TThreadID);
Var
 Code: LongWord;
Begin
 Code := WaitForThreadTerminate(Handle, -1);
 CloseThread(Handle);
 If Code <> 0 Then Fail('Echec d''un thread de calcul.');
End;

Function DenseWorker(Parameter: Pointer): PtrInt;
Var
 Job: PDenseJob;
 Index, Row, Col: Integer;
 Value: Single;
Begin
 Job := Parameter;
 For Index := Job^.First To Job^.Last - 1 Do Begin
  Row := Index Div Job^.Outputs; Col := Index Mod Job^.Outputs;
  Value := NeuralDot(@Job^.X^[Row * Job^.Inputs], @Job^.Weight^[Col * Job^.Inputs],
  Job^.Inputs);
  If Job^.Bias <> Nil Then Value := Value + Job^.Bias^[Col];
  Job^.Y^[Index] := Value;
 End;
 DenseWorker := 0;
End;

Procedure Dense(Const X: TMatrix; Const T: TTensors; Weight, Bias: Integer;
                Var Y: TMatrix);
Var
 Width, Count, Workers, I, J: Integer;
 Jobs: Array[0..63] Of TDenseJob;
 Handles: Array[0..63] Of TThreadID;
Begin
 Width := T[Weight].Dims[1];
 If X.Cols <> T[Weight].Dims[0] Then Fail('Dimension de projection neuronale invalide.');
 MatrixSize(Y, X.Rows, Width); Count := X.Rows * Width;
 If Count = 0 Then Exit;
 Workers := MinInt(ThreadCount, Count);
 If Int64(Count) * X.Cols < 65536 Then Workers := 1;
 For I := 0 To Workers - 1 Do Begin
  Jobs[I].X := @X.Data[0]; Jobs[I].Weight := @T[Weight].Data[0]; Jobs[I].Y := @Y.Data[0];
  Jobs[I].Bias := Nil; If Bias >= 0 Then Jobs[I].Bias := @T[Bias].Data[0];
  Jobs[I].Inputs := X.Cols; Jobs[I].Outputs := Width;
  Jobs[I].First := Int64(Count) * I Div Workers;
  Jobs[I].Last := Int64(Count) * (I + 1) Div Workers;
 End;
 For I := 1 To Workers - 1 Do Begin
  Handles[I] := BeginThread(@DenseWorker, @Jobs[I]);
  If Handles[I] = 0 Then Begin
   For J := 1 To I - 1 Do JoinThread(Handles[J]);
   Fail('Creation d''un thread impossible; reduire --threads.');
  End;
 End;
 DenseWorker(@Jobs[0]);
 For I := 1 To Workers - 1 Do JoinThread(Handles[I]);
End;

Function StableTanh(Value: Double): Double;Begin
 If Value > 15 Then Begin
  StableTanh := 1; Exit;
 End; If Value < -15 Then Begin
  StableTanh := -1; Exit;
 End;
 StableTanh := 2 / (1 + Exp(-2 * Value)) - 1;
End;

Function Sigmoid(Value: Double): Double;Begin
 If Value >= 0 Then Sigmoid := 1 / (1 + Exp(-Value))
  Else
 Begin
  Value := Exp(Value); Sigmoid := Value / (1 + Value);
 End;
End;

Procedure GELU(Var X: TMatrix);
Var
 I: Integer;
 V: Double;
Begin
 For I := 0 To High(X.Data) Do Begin
  V := X.Data[I];
  X.Data[I] := 0.5 * V * (1 + StableTanh(0.7978845608028654 * V * (1 + 0.044715 * V * V)))
  ;
 End;
End;

Procedure NeuralNorm(Const X: TMatrix; Const T: TTensors; Weight, Bias: Integer;
                     Var Y: TMatrix);
Var
 I, J, Offset: Integer;
 Mean, Variance, V, Scale: Double;
Begin
 MatrixSize(Y, X.Rows, X.Cols);
 For I := 0 To X.Rows - 1 Do Begin
  Offset := I * X.Cols; Mean := 0; Variance := 0;
  For J := 0 To X.Cols - 1 Do Mean := Mean + X.Data[Offset + J];
  Mean := Mean / X.Cols;
  For J := 0 To X.Cols - 1 Do Begin
   V := X.Data[Offset + J] - Mean; Variance := Variance + V * V;
  End;
  Scale := 1 / Sqrt(Variance / X.Cols + 1E-5);
  For J := 0 To X.Cols - 1 Do Y.Data[Offset + J] := (X.Data[Offset + J] - Mean) * Scale *
  T[Weight].Data[J] + T[Bias].Data[J];
 End;
End;

Procedure Residual(Var X: TMatrix; Const Y: TMatrix);
Var
 I: Integer;
Begin
 If (X.Rows <> Y.Rows) Or (X.Cols <> Y.Cols) Then Fail('Dimension residuelle invalide.');
 For I := 0 To High(X.Data) Do X.Data[I] := X.Data[I] + Y.Data[I];
End;

Procedure Conv1D(Const X: TMatrix; Const T: TTensors;
                 Weight, Bias, Stride, Padding: Integer; Var Y: TMatrix);
Var
 I, J, C, K, Source, Width, Kernel, Rows: Integer;
 Patch: TSamples;
 Value: Single;
Begin
 Kernel := T[Weight].Dims[0]; Width := T[Weight].Dims[2];
 If T[Weight].Dims[1] <> X.Cols Then Fail('Canaux de convolution invalides.');
 Rows := (X.Rows + 2 * Padding - Kernel) Div Stride + 1; MatrixSize(Y, Rows, Width);
 SetLength(Patch, X.Cols * Kernel);
 For I := 0 To Rows - 1 Do Begin
  For C := 0 To X.Cols - 1 Do
  For K := 0 To Kernel - 1 Do Begin
   Source := I * Stride - Padding + K;
   If (Source < 0) Or (Source >= X.Rows) Then Patch[C * Kernel + K] := 0
                                         Else Patch[C * Kernel + K] := X.Data[Source * X.Cols + C];
  End;
  For J := 0 To Width - 1 Do Begin
   Value := NeuralDot(@Patch[0], @T[Weight].Data[J * Length(Patch)], Length(Patch));
   If Bias >= 0 Then Value := Value + T[Bias].Data[J]; Y.Data[I * Width + J] := Value;
  End;
 End;
End;

Procedure NeuralAttention(Const Q, K, V: TMatrix; KeyCount, Heads: Integer;
                          Var Y: TMatrix);
Var
 I, J, H, D, Width: Integer;
 Scores, Transposed: TSamples;
 Scale, Peak, Sum, Value: Double;
Begin
 If (Q.Cols <> K.Cols) Or (K.Cols <> V.Cols) Or (KeyCount <= 0) Or (KeyCount > K.Rows) Or
 (KeyCount > V.Rows) Or (Q.Cols Mod Heads <> 0) Then Fail(
 'Dimensions attention invalides.');
 Width := Q.Cols Div Heads; Scale := 1 / Sqrt(Width);
 MatrixSize(Y, Q.Rows, Q.Cols); SetLength(Scores, KeyCount);
 SetLength(Transposed, KeyCount * V.Cols);
 For J := 0 To KeyCount - 1 Do
 For D := 0 To V.Cols - 1 Do Transposed[D * KeyCount + J] := V.Data[J * V.Cols + D];
 For I := 0 To Q.Rows - 1 Do
 For H := 0 To Heads - 1 Do Begin
  Peak := -1E30;
  For J := 0 To KeyCount - 1 Do Begin
   Value := NeuralDot(@Q.Data[I * Q.Cols + H * Width], @K.Data[J * K.Cols + H * Width],
   Width) * Scale;
   Scores[J] := Value; If Value > Peak Then Peak := Value;
  End;
  Sum := 0;
  For J := 0 To KeyCount - 1 Do Begin
   Scores[J] := Exp(Scores[J] - Peak); Sum := Sum + Scores[J];
  End;
  For J := 0 To KeyCount - 1 Do Scores[J] := Scores[J] / Sum;
  For D := 0 To Width - 1 Do Y.Data[I * Y.Cols + H * Width + D] :=
  NeuralDot(@Scores[0], @Transposed[(H * Width + D) * KeyCount], KeyCount);
 End;
End;

Procedure NeuralMLP(Var X: TMatrix; Const T: TTensors; Const L: TWhisperLayer);
Var
 N, A, B: TMatrix;
Begin
 NeuralNorm(X, T, L.MLPNorm, L.MLPNormB, N);
 Dense(N, T, L.MLP0, L.MLP0B, A); GELU(A); Dense(A, T, L.MLP2, L.MLP2B, B);
 Residual(X, B);
End;

Procedure EncodeWhisper(Const Mel: TMatrix; Const M: TWhisperModel; Var Encoded: TMatrix);
Var
 X, N, Q, K, V, A, B: TMatrix;
 I, J: Integer;
 W: TAttentionWeights;
Begin
 Conv1D(Mel, M.Tensors, M.Conv1, M.Conv1B, 1, 1, X); GELU(X);
 Conv1D(X, M.Tensors, M.Conv2, M.Conv2B, 2, 1, Encoded); GELU(Encoded);
 For J := 0 To High(Encoded.Data) Do Encoded.Data[J] := Encoded.Data[J] +
 M.Tensors[M.AudioPosition].Data[J];
 For I := 0 To M.AudioLayers - 1 Do Begin
  W := M.Encoder[I].Attention;
  NeuralNorm(Encoded, M.Tensors, W.LN, W.LNB, N);
  Dense(N, M.Tensors, W.Q, W.QB, Q); Dense(N, M.Tensors, W.K, -1, K);
  Dense(N, M.Tensors, W.V, W.VB, V);
  NeuralAttention(Q, K, V, K.Rows, M.AudioHeads, A); Dense(A, M.Tensors, W.O, W.OB, B);
  Residual(Encoded, B);
  NeuralMLP(Encoded, M.Tensors, M.Encoder[I]);
 End;
 NeuralNorm(Encoded, M.Tensors, M.AudioNorm, M.AudioNormB, N); Encoded := N;
End;

Procedure InitDecoderCache(Const Encoded: TMatrix; Const M: TWhisperModel;
                           Var Cache: TDecoderCaches);
Var
 I: Integer;
 W: TAttentionWeights;
Begin
 SetLength(Cache, M.TextLayers);
 For I := 0 To M.TextLayers - 1 Do Begin
  W := M.Decoder[I].Cross;
  Dense(Encoded, M.Tensors, W.K, -1, Cache[I].CrossK);
  Dense(Encoded, M.Tensors, W.V, W.VB, Cache[I].CrossV);
  MatrixSize(Cache[I].SelfK, M.TextContext, M.TextWidth);
  MatrixSize(Cache[I].SelfV, M.TextContext, M.TextWidth);
 End;
End;

Procedure ConfigureDTW(Const Name: String; Var M: TWhisperModel);
Var
 Layers, Width, Heads, Mel, Encoder: Integer;
 English: Boolean;
Begin
 M.DTWHeads := Nil; If Name = '' Then Exit;
 Layers := 0; Width := 0; Heads := 0; Mel := 80; Encoder := 0;
 English := Pos('.en', Name) > 0;
 If Name = 'tiny.en' Then Begin
  Layers := 4; Width := 384; Heads := 6; Mel := 80; Encoder := 4;
  SetLength(M.DTWHeads, Layers);
  M.DTWHeads[1] := M.DTWHeads[1] Or (LongWord(1) Shl 0);
  M.DTWHeads[2] := M.DTWHeads[2] Or (LongWord(1) Shl 0);
  M.DTWHeads[2] := M.DTWHeads[2] Or (LongWord(1) Shl 5);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 0);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 1);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 2);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 3);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 4);
 End;
 If Name = 'tiny' Then Begin
  Layers := 4; Width := 384; Heads := 6; Mel := 80; Encoder := 4;
  SetLength(M.DTWHeads, Layers);
  M.DTWHeads[2] := M.DTWHeads[2] Or (LongWord(1) Shl 2);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 0);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 2);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 3);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 4);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 5);
 End;
 If Name = 'base.en' Then Begin
  Layers := 6; Width := 512; Heads := 8; Mel := 80; Encoder := 6;
  SetLength(M.DTWHeads, Layers);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 3);
  M.DTWHeads[4] := M.DTWHeads[4] Or (LongWord(1) Shl 7);
  M.DTWHeads[5] := M.DTWHeads[5] Or (LongWord(1) Shl 1);
  M.DTWHeads[5] := M.DTWHeads[5] Or (LongWord(1) Shl 5);
  M.DTWHeads[5] := M.DTWHeads[5] Or (LongWord(1) Shl 7);
 End;
 If Name = 'base' Then Begin
  Layers := 6; Width := 512; Heads := 8; Mel := 80; Encoder := 6;
  SetLength(M.DTWHeads, Layers);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 1);
  M.DTWHeads[4] := M.DTWHeads[4] Or (LongWord(1) Shl 2);
  M.DTWHeads[4] := M.DTWHeads[4] Or (LongWord(1) Shl 3);
  M.DTWHeads[4] := M.DTWHeads[4] Or (LongWord(1) Shl 7);
  M.DTWHeads[5] := M.DTWHeads[5] Or (LongWord(1) Shl 1);
  M.DTWHeads[5] := M.DTWHeads[5] Or (LongWord(1) Shl 2);
  M.DTWHeads[5] := M.DTWHeads[5] Or (LongWord(1) Shl 4);
  M.DTWHeads[5] := M.DTWHeads[5] Or (LongWord(1) Shl 6);
 End;
 If Name = 'small.en' Then Begin
  Layers := 12; Width := 768; Heads := 12; Mel := 80; Encoder := 12;
  SetLength(M.DTWHeads, Layers);
  M.DTWHeads[6] := M.DTWHeads[6] Or (LongWord(1) Shl 6);
  M.DTWHeads[7] := M.DTWHeads[7] Or (LongWord(1) Shl 0);
  M.DTWHeads[7] := M.DTWHeads[7] Or (LongWord(1) Shl 3);
  M.DTWHeads[7] := M.DTWHeads[7] Or (LongWord(1) Shl 8);
  M.DTWHeads[8] := M.DTWHeads[8] Or (LongWord(1) Shl 2);
  M.DTWHeads[8] := M.DTWHeads[8] Or (LongWord(1) Shl 5);
  M.DTWHeads[8] := M.DTWHeads[8] Or (LongWord(1) Shl 7);
  M.DTWHeads[9] := M.DTWHeads[9] Or (LongWord(1) Shl 0);
  M.DTWHeads[9] := M.DTWHeads[9] Or (LongWord(1) Shl 4);
  M.DTWHeads[9] := M.DTWHeads[9] Or (LongWord(1) Shl 8);
  M.DTWHeads[9] := M.DTWHeads[9] Or (LongWord(1) Shl 10);
  M.DTWHeads[10] := M.DTWHeads[10] Or (LongWord(1) Shl 0);
  M.DTWHeads[10] := M.DTWHeads[10] Or (LongWord(1) Shl 1);
  M.DTWHeads[10] := M.DTWHeads[10] Or (LongWord(1) Shl 2);
  M.DTWHeads[10] := M.DTWHeads[10] Or (LongWord(1) Shl 3);
  M.DTWHeads[10] := M.DTWHeads[10] Or (LongWord(1) Shl 6);
  M.DTWHeads[10] := M.DTWHeads[10] Or (LongWord(1) Shl 11);
  M.DTWHeads[11] := M.DTWHeads[11] Or (LongWord(1) Shl 2);
  M.DTWHeads[11] := M.DTWHeads[11] Or (LongWord(1) Shl 4);
 End;
 If Name = 'small' Then Begin
  Layers := 12; Width := 768; Heads := 12; Mel := 80; Encoder := 12;
  SetLength(M.DTWHeads, Layers);
  M.DTWHeads[5] := M.DTWHeads[5] Or (LongWord(1) Shl 3);
  M.DTWHeads[5] := M.DTWHeads[5] Or (LongWord(1) Shl 9);
  M.DTWHeads[8] := M.DTWHeads[8] Or (LongWord(1) Shl 0);
  M.DTWHeads[8] := M.DTWHeads[8] Or (LongWord(1) Shl 4);
  M.DTWHeads[8] := M.DTWHeads[8] Or (LongWord(1) Shl 7);
  M.DTWHeads[8] := M.DTWHeads[8] Or (LongWord(1) Shl 8);
  M.DTWHeads[9] := M.DTWHeads[9] Or (LongWord(1) Shl 0);
  M.DTWHeads[9] := M.DTWHeads[9] Or (LongWord(1) Shl 7);
  M.DTWHeads[9] := M.DTWHeads[9] Or (LongWord(1) Shl 9);
  M.DTWHeads[10] := M.DTWHeads[10] Or (LongWord(1) Shl 5);
 End;
 If Name = 'medium.en' Then Begin
  Layers := 24; Width := 1024; Heads := 16; Mel := 80; Encoder := 24;
  SetLength(M.DTWHeads, Layers);
  M.DTWHeads[11] := M.DTWHeads[11] Or (LongWord(1) Shl 4);
  M.DTWHeads[14] := M.DTWHeads[14] Or (LongWord(1) Shl 1);
  M.DTWHeads[14] := M.DTWHeads[14] Or (LongWord(1) Shl 12);
  M.DTWHeads[14] := M.DTWHeads[14] Or (LongWord(1) Shl 14);
  M.DTWHeads[15] := M.DTWHeads[15] Or (LongWord(1) Shl 4);
  M.DTWHeads[16] := M.DTWHeads[16] Or (LongWord(1) Shl 0);
  M.DTWHeads[16] := M.DTWHeads[16] Or (LongWord(1) Shl 4);
  M.DTWHeads[16] := M.DTWHeads[16] Or (LongWord(1) Shl 9);
  M.DTWHeads[17] := M.DTWHeads[17] Or (LongWord(1) Shl 12);
  M.DTWHeads[17] := M.DTWHeads[17] Or (LongWord(1) Shl 14);
  M.DTWHeads[18] := M.DTWHeads[18] Or (LongWord(1) Shl 7);
  M.DTWHeads[18] := M.DTWHeads[18] Or (LongWord(1) Shl 10);
  M.DTWHeads[18] := M.DTWHeads[18] Or (LongWord(1) Shl 15);
  M.DTWHeads[20] := M.DTWHeads[20] Or (LongWord(1) Shl 0);
  M.DTWHeads[20] := M.DTWHeads[20] Or (LongWord(1) Shl 3);
  M.DTWHeads[20] := M.DTWHeads[20] Or (LongWord(1) Shl 9);
  M.DTWHeads[20] := M.DTWHeads[20] Or (LongWord(1) Shl 14);
  M.DTWHeads[21] := M.DTWHeads[21] Or (LongWord(1) Shl 12);
 End;
 If Name = 'medium' Then Begin
  Layers := 24; Width := 1024; Heads := 16; Mel := 80; Encoder := 24;
  SetLength(M.DTWHeads, Layers);
  M.DTWHeads[13] := M.DTWHeads[13] Or (LongWord(1) Shl 15);
  M.DTWHeads[15] := M.DTWHeads[15] Or (LongWord(1) Shl 4);
  M.DTWHeads[15] := M.DTWHeads[15] Or (LongWord(1) Shl 15);
  M.DTWHeads[16] := M.DTWHeads[16] Or (LongWord(1) Shl 1);
  M.DTWHeads[20] := M.DTWHeads[20] Or (LongWord(1) Shl 0);
  M.DTWHeads[23] := M.DTWHeads[23] Or (LongWord(1) Shl 4);
 End;
 If Name = 'large-v1' Then Begin
  Layers := 32; Width := 1280; Heads := 20; Mel := 80; Encoder := 32;
  SetLength(M.DTWHeads, Layers);
  M.DTWHeads[9] := M.DTWHeads[9] Or (LongWord(1) Shl 19);
  M.DTWHeads[11] := M.DTWHeads[11] Or (LongWord(1) Shl 2);
  M.DTWHeads[11] := M.DTWHeads[11] Or (LongWord(1) Shl 4);
  M.DTWHeads[11] := M.DTWHeads[11] Or (LongWord(1) Shl 17);
  M.DTWHeads[22] := M.DTWHeads[22] Or (LongWord(1) Shl 7);
  M.DTWHeads[22] := M.DTWHeads[22] Or (LongWord(1) Shl 11);
  M.DTWHeads[22] := M.DTWHeads[22] Or (LongWord(1) Shl 17);
  M.DTWHeads[23] := M.DTWHeads[23] Or (LongWord(1) Shl 2);
  M.DTWHeads[23] := M.DTWHeads[23] Or (LongWord(1) Shl 15);
 End;
 If Name = 'large-v2' Then Begin
  Layers := 32; Width := 1280; Heads := 20; Mel := 80; Encoder := 32;
  SetLength(M.DTWHeads, Layers);
  M.DTWHeads[10] := M.DTWHeads[10] Or (LongWord(1) Shl 12);
  M.DTWHeads[13] := M.DTWHeads[13] Or (LongWord(1) Shl 17);
  M.DTWHeads[16] := M.DTWHeads[16] Or (LongWord(1) Shl 11);
  M.DTWHeads[16] := M.DTWHeads[16] Or (LongWord(1) Shl 12);
  M.DTWHeads[16] := M.DTWHeads[16] Or (LongWord(1) Shl 13);
  M.DTWHeads[17] := M.DTWHeads[17] Or (LongWord(1) Shl 15);
  M.DTWHeads[17] := M.DTWHeads[17] Or (LongWord(1) Shl 16);
  M.DTWHeads[18] := M.DTWHeads[18] Or (LongWord(1) Shl 4);
  M.DTWHeads[18] := M.DTWHeads[18] Or (LongWord(1) Shl 11);
  M.DTWHeads[18] := M.DTWHeads[18] Or (LongWord(1) Shl 19);
  M.DTWHeads[19] := M.DTWHeads[19] Or (LongWord(1) Shl 11);
  M.DTWHeads[21] := M.DTWHeads[21] Or (LongWord(1) Shl 2);
  M.DTWHeads[21] := M.DTWHeads[21] Or (LongWord(1) Shl 3);
  M.DTWHeads[22] := M.DTWHeads[22] Or (LongWord(1) Shl 3);
  M.DTWHeads[22] := M.DTWHeads[22] Or (LongWord(1) Shl 9);
  M.DTWHeads[22] := M.DTWHeads[22] Or (LongWord(1) Shl 12);
  M.DTWHeads[23] := M.DTWHeads[23] Or (LongWord(1) Shl 5);
  M.DTWHeads[23] := M.DTWHeads[23] Or (LongWord(1) Shl 7);
  M.DTWHeads[23] := M.DTWHeads[23] Or (LongWord(1) Shl 13);
  M.DTWHeads[25] := M.DTWHeads[25] Or (LongWord(1) Shl 5);
  M.DTWHeads[26] := M.DTWHeads[26] Or (LongWord(1) Shl 1);
  M.DTWHeads[26] := M.DTWHeads[26] Or (LongWord(1) Shl 12);
  M.DTWHeads[27] := M.DTWHeads[27] Or (LongWord(1) Shl 15);
 End;
 If Name = 'large-v3' Then Begin
  Layers := 32; Width := 1280; Heads := 20; Mel := 128; Encoder := 32;
  SetLength(M.DTWHeads, Layers);
  M.DTWHeads[7] := M.DTWHeads[7] Or (LongWord(1) Shl 0);
  M.DTWHeads[10] := M.DTWHeads[10] Or (LongWord(1) Shl 17);
  M.DTWHeads[12] := M.DTWHeads[12] Or (LongWord(1) Shl 18);
  M.DTWHeads[13] := M.DTWHeads[13] Or (LongWord(1) Shl 12);
  M.DTWHeads[16] := M.DTWHeads[16] Or (LongWord(1) Shl 1);
  M.DTWHeads[17] := M.DTWHeads[17] Or (LongWord(1) Shl 14);
  M.DTWHeads[19] := M.DTWHeads[19] Or (LongWord(1) Shl 11);
  M.DTWHeads[21] := M.DTWHeads[21] Or (LongWord(1) Shl 4);
  M.DTWHeads[24] := M.DTWHeads[24] Or (LongWord(1) Shl 1);
  M.DTWHeads[25] := M.DTWHeads[25] Or (LongWord(1) Shl 6);
 End;
 If Name = 'large-v3-turbo' Then Begin
  Layers := 4; Width := 1280; Heads := 20; Mel := 128; Encoder := 32;
  SetLength(M.DTWHeads, Layers);
  M.DTWHeads[2] := M.DTWHeads[2] Or (LongWord(1) Shl 4);
  M.DTWHeads[2] := M.DTWHeads[2] Or (LongWord(1) Shl 11);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 3);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 6);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 11);
  M.DTWHeads[3] := M.DTWHeads[3] Or (LongWord(1) Shl 14);
 End;
 If Layers = 0 Then Fail('Profil --dtw inconnu: ' + Name);
 If (M.TextLayers <> Layers) Or (M.AudioLayers <> Encoder) Or (M.TextWidth <> Width) Or
 (M.TextHeads <> Heads) Or (M.MelCount <> Mel) Or (English <> (M.VocabCount = 51864))
 Then  Fail('Le profil --dtw ne correspond pas aux dimensions/langue du modele.');
End;

Procedure CaptureAlignment(Const Q, K: TMatrix; Heads: Integer; Mask: LongWord;
                           Frames: Integer; Var Alignment: TMatrix);
Var
 H, J, D, Row, Count: Integer;
 Peak, Sum, Scale: Double;
Begin
 Count := 0;
 For H := 0 To Heads - 1 Do If (Mask And (LongWord(1) Shl H)) <> 0 Then Inc(Count);
 MatrixSize(Alignment, Count, Frames); Row := 0; D := Q.Cols Div Heads;
 Scale := 1 / Sqrt(D);
 For H := 0 To Heads - 1 Do If (Mask And (LongWord(1) Shl H)) <> 0 Then Begin
  Peak := -1E30;
  For J := 0 To Frames - 1 Do Begin
   Alignment.Data[Row * Frames + J] := NeuralDot(@Q.Data[H * D], @K.Data[J * K.Cols + H *
   D], D) * Scale;
   If Alignment.Data[Row * Frames + J] > Peak Then Peak := Alignment.Data[Row * Frames +
   J];
  End;
  Sum := 0;
  For J := 0 To Frames - 1 Do Begin
   Alignment.Data[Row * Frames + J] := Exp(Alignment.Data[Row * Frames + J] - Peak);
   Sum := Sum + Alignment.Data[Row * Frames + J];
  End;
  For J := 0 To Frames - 1 Do Alignment.Data[Row * Frames + J] := Alignment.Data[Row *
  Frames + J] / Sum;
  Inc(Row);
 End;
End;

Procedure DecoderStep(Token, Position: Integer; Const M: TWhisperModel;
                      Var Cache: TDecoderCaches; Var Logits: TMatrix);
Var
 X, N, Q, K, V, A, B: TMatrix;
 I, J: Integer;
 W: TAttentionWeights;
Begin
 Bounded(Token, 0, M.VocabCount - 1, 'token decodeur');
 Bounded(Position, 0, M.TextContext - 1, 'position decodeur');
 MatrixSize(X, 1, M.TextWidth);
 For J := 0 To M.TextWidth - 1 Do X.Data[J] := M.Tensors[M.Embedding].Data[Token *
 M.TextWidth + J] +
 M.Tensors[M.TextPosition].Data[Position * M.TextWidth + J];
 For I := 0 To M.TextLayers - 1 Do Begin
  W := M.Decoder[I].Attention; NeuralNorm(X, M.Tensors, W.LN, W.LNB, N);
  Dense(N, M.Tensors, W.Q, W.QB, Q); Dense(N, M.Tensors, W.K, -1, K);
  Dense(N, M.Tensors, W.V, W.VB, V);
  Move(K.Data[0], Cache[I].SelfK.Data[Position * M.TextWidth], M.TextWidth * 4);
  Move(V.Data[0], Cache[I].SelfV.Data[Position * M.TextWidth], M.TextWidth * 4);
  NeuralAttention(Q, Cache[I].SelfK, Cache[I].SelfV, Position + 1, M.TextHeads, A);
  Dense(A, M.Tensors, W.O, W.OB, B); Residual(X, B);
  W := M.Decoder[I].Cross; NeuralNorm(X, M.Tensors, W.LN, W.LNB, N);
  Dense(N, M.Tensors, W.Q, W.QB, Q);
  If Cache[0].CaptureDTW And (Length(M.DTWHeads) > I) Then   If M.DTWHeads[I] <>
  0 Then CaptureAlignment(Q, Cache[I].CrossK, M.TextHeads,
  M.DTWHeads[I], Cache[0].DTWFrames, Cache[I].Alignment);
  NeuralAttention(Q, Cache[I].CrossK, Cache[I].CrossV, Cache[I].CrossK.Rows, M.TextHeads,
  A);
  Dense(A, M.Tensors, W.O, W.OB, B); Residual(X, B);
  NeuralMLP(X, M.Tensors, M.Decoder[I]);
 End;
 NeuralNorm(X, M.Tensors, M.TextNorm, M.TextNormB, N);
 Dense(N, M.Tensors, M.Embedding, -1, Logits);
End;
{ Whisper: DFT 400 points, fenetre Hann periodique et filtres mel du modele.
  Les tables trigonomÃƒÂ©triques sont calculees une fois; aucun moteur FFT externe. }

Procedure WhisperMel(Const Audio: TSamples; First, Last: Integer; Const M: TWhisperModel;
                     AudioContext: Integer; Var Mel: TMatrix);
Var
 C, S, Frame, Power: TSamples;
 I, J, K, P: Integer;
 A, B, V, Peak: Double;
Begin
 SetLength(C, 201 * 400); SetLength(S, 201 * 400); SetLength(Frame, 400);
 SetLength(Power, 201);
 For K := 0 To 200 Do
 For J := 0 To 399 Do Begin
  A := 2 * Pi * K * J / 400; B := 0.5 - 0.5 * Cos(2 * Pi * J / 400);
  C[K * 400 + J] := B * Cos(A); S[K * 400 + J] := B * Sin(A);
 End;
 MatrixSize(Mel, AudioContext * 2, M.MelCount); Peak := -10;
 For I := 0 To Mel.Rows - 1 Do Begin
  If I * 160 - 200 < Last - First Then Begin
   For J := 0 To 399 Do Begin
    P := I * 160 + J - 200; If P < 0 Then P := -P;
    If P < Last - First Then Frame[J] := Audio[First + P] Else Frame[J] := 0;
   End;
   For K := 0 To 200 Do Begin
    A := NeuralDot(@Frame[0], @C[K * 400], 400);
    B := NeuralDot(@Frame[0], @S[K * 400], 400);
    Power[K] := A * A + B * B;
   End;
   For K := 0 To M.MelCount - 1 Do Begin
    V := NeuralDot(@Power[0], @M.Filters[K * 201], 201);
    If V < 1E-10 Then V := 1E-10;
    V := Ln(V) / Ln(10); Mel.Data[I * M.MelCount + K] := V;
    If V > Peak Then Peak := V;
   End;
  End Else
  For K := 0 To M.MelCount - 1 Do Mel.Data[I * M.MelCount + K] := -10;
 End;
 For I := 0 To High(Mel.Data) Do Begin
  V := Mel.Data[I]; If V < Peak - 8 Then V := Peak - 8;
  Mel.Data[I] := (V + 4) / 4;
 End;
End;

Const
 LanguageCodes: Array[0..99] Of String[3] = (
 'en','zh','de','es','ru','ko','fr','ja','pt','tr','pl','ca','nl','ar','sv','it',
 'id','hi','fi','vi','he','uk','el','ms','cs','ro','da','hu','ta','no','th','ur',
 'hr','bg','lt','la','mi','ml','cy','sk','te','fa','lv','bn','sr','az','sl','kn',
 'et','mk','br','eu','is','hy','ne','mn','bs','kk','sq','sw','gl','mr','pa','si',
 'km','sn','yo','so','af','oc','ka','be','tg','sd','gu','am','yi','lo','uz','fo',
 'ht','ps','tk','nn','mt','sa','lb','my','bo','tl','mg','as','tt','haw','ln','ha',
 'ba','jw','su','yue');

Type
 TTokens = Array Of Integer;
 TTimeHint = Record
  Sample, EndSample: Integer;
  Probability: Double;
  Aligned: Boolean;
 End;
 TAlignedToken = Record
  ID, First, Last: Integer;
  Probability: Double;
 End;
 TAlignedTokens = Array Of TAlignedToken;
 TCharacterTimes = Array Of Integer;
 TTimeHints = Array Of TTimeHint;
 TExportFormat = (efTXT, efVTT, efSRT, efLRC, efCSV, efJSON, efWords, efHTML);
 TExportFormats = Set Of TExportFormat;
 TDecodeReport = Record
  Confidence: Double;
  SpecialPrefix, SpecialSuffix, LogText: String;
 End;
 TOptions = Record
  Files: TStringVector;
  OutputBases: TStringVector;
  OutputFormats: TExportFormats;
  FullJSON: Boolean;
  FontPath: String;
  Model, Language, DTWModel: String;
  Threads, Processors: Integer;
  OffsetMS, DurationMS, OffsetIndex: Integer;
  ShowIndex: Boolean;
  MaxContext, MaxLength, AudioContext: Integer;
  SplitOnWord, CarryPrompt: Boolean;
  Prompt: String;
  BestOf, BeamSize: Integer;
  Temperature, TemperatureInc: Double;
  NoFallback: Boolean;
  SuppressNST, HasSuppressRegex: Boolean;
  SuppressRegex: String;
  NoPrints, PrintSpecial, PrintColors, PrintProgress, NoTimestamps: Boolean;
  PrintConfidence, LogScore: Boolean;
  DetectLanguage, Translate: Boolean;
  Diarize, TinyDiarize: Boolean;
  WordThreshold, EntropyThreshold, LogProbThreshold, NoSpeechThreshold: Double;
 End;
 TSegment = Record
  First, Last: Integer;
  Text, Language: String;
  Tokens: TAlignedTokens;
  CharacterTimes: TCharacterTimes;
  Speaker: String;
  SpeakerTurnNext: Boolean;
  Confidence: Double;
  SpecialPrefix, SpecialSuffix: String;
 End;
 TSegments = Array Of TSegment;
 PWhisperModel = ^TWhisperModel;
 PSamples = ^TSamples;
 TProcessorJob = Record
  Model: PWhisperModel;
  Audio: PSamples;
  First, Last, Language, WorkerIndex: Integer;
  LogText: String;
  Segments: TSegments;
  Options: ^TOptions;
  InitialTokens: TTokens;
 End;
 PProcessorJob = ^TProcessorJob;

Const
 ExportExtensions: Array[TExportFormat] Of String[5] =
 ('.txt', '.vtt', '.srt', '.lrc', '.csv', '.json', '.wts', '.html');

Function ExportBase(Const O: TOptions; FileIndex: Integer): String;Begin
 If FileIndex < Length(O.OutputBases) Then ExportBase := O.OutputBases[FileIndex]
                                      Else ExportBase := O.Files[FileIndex];
End;

Function CanonicalOutput(Const Name: String): String;
Var
 I: Integer;
Begin
 CanonicalOutput := FExpand(Name);
 {$IFDEF MSWINDOWS}
  For I := 1 To Length(CanonicalOutput) Do  CanonicalOutput[I] := UpCase(
  CanonicalOutput[I]);
 {$ENDIF}
End;

Procedure CheckExports(Const O: TOptions);
Var
 I, J, N: Integer;
 F: TExportFormat;
 Names: TStringVector;
 Name, Canonical: String;
 Attributes: Word;
Begin
 Names := Nil;
 If Length(O.OutputBases) > Length(O.Files) Then Fail('Trop de noms --output-file.');
 If O.DetectLanguage Then Exit;
 If (efHTML In O.OutputFormats) And (O.FontPath <> '') Then  If Not FileExists(O.FontPath)
 Then Fail('Police introuvable: ' + O.FontPath);
 For I := 0 To High(O.Files) Do
 For F := Low(TExportFormat) To High(TExportFormat) Do  If F In O.OutputFormats Then Begin
  Name := ExportBase(O, I) + ExportExtensions[F];
  If Length(Name) > 255 Then Fail('Nom de sortie trop long: ' + Name);
  If PathAttributes(Name, Attributes) Then Fail('Sortie deja existante: ' + Name);
  Canonical := CanonicalOutput(Name);
  For J := 0 To High(Names) Do If Names[J] = Canonical Then    Fail(
  'Plusieurs sorties portent le meme nom: ' + Name);
  N := Length(Names); SetLength(Names, N + 1); Names[N] := Canonical;
 End;
End;
{ Regex procedural: automate non deterministe, sans retour arriere exponentiel.
  Correspondance complete sur les octets UTF-8 du vocabulaire GGML. }

Type
 TRegexChars = Set Of Char;
 TRegexNodeKind = (rnEmpty, rnChars, rnConcat, rnAlt, rnRepeat, rnBegin, rnEnd);
 TRegexNode = Record
  Kind: TRegexNodeKind;
  Chars: TRegexChars;
  Left, Right, Minimum, Maximum: Integer;
 End;
 TRegexNodes = Array Of TRegexNode;
 TRegexStateKind = (rsChars, rsSplit, rsBegin, rsEnd, rsMatch);
 TRegexState = Record
  Kind: TRegexStateKind;
  Chars: TRegexChars;
  A, B: Integer;
 End;
 TRegex = Record
  States: Array Of TRegexState;
  Start: Integer;
 End;
 TRegexFlags = Array Of Boolean;
 TRegexStack = Array Of Integer;

Procedure CompileRegex(Const Pattern: String; Var Regex: TRegex);
Var
 Nodes: TRegexNodes;
 P, Depth, Root, Terminal: Integer;

Procedure Invalid(Const Message: String);Begin
 Fail('--suppress-regex: ' + Message + ' (position ' + IntToStr(P) + ')');
End;

Function Node(Kind: TRegexNodeKind; Left, Right: Integer): Integer;
Var
 N: Integer;
Begin
 N := Length(Nodes); If N >= 2048 Then Invalid('expression trop complexe');
 SetLength(Nodes, N + 1); Nodes[N].Kind := Kind; Nodes[N].Left := Left;
 Nodes[N].Right := Right;
 Node := N;
End;

Function Escape: TRegexChars;
Var
 C: Char;
 I, V, D: Integer;
Begin
 If P > Length(Pattern) Then Invalid('echappement incomplet');
 C := Pattern[P]; Inc(P); Escape := [];
 Case C Of
 'd', 'D': Escape := ['0'..'9'];
 'w', 'W': Escape := ['A'..'Z','a'..'z','0'..'9','_'];
 's', 'S': Escape := [' ',#9,#10,#11,#12,#13];
 't': Escape := [#9]; 'n': Escape := [#10]; 'r': Escape := [#13];
 'f': Escape := [#12]; 'v': Escape := [#11];
 'x':
 Begin
  V := 0;
  For I := 1 To 2 Do Begin
   If P > Length(Pattern) Then Invalid('hexadecimal incomplet');
   C := UpCase(Pattern[P]); Inc(P);
   If C In ['0'..'9'] Then D := Ord(C) - Ord('0') Else
   If C In ['A'..'F'] Then D := Ord(C) - Ord('A') + 10
    Else
   Begin
    Invalid('hexadecimal invalide'); D := 0;
   End;
   V := V * 16 + D;
  End;
  Escape := [Chr(V)]; Exit;
 End;
 '0'..'9', 'b', 'B', 'p', 'P', 'u', 'k': Invalid('echappement non pris en charge');
  Else
 Begin
  If C In ['A'..'Z','a'..'z'] Then Invalid('echappement inconnu');
  Escape := [C];
 End;
End;
If C In ['D','W','S'] Then Escape := [#0..#255] - Escape;
End;

Function ClassItem: TRegexChars;Begin
 If P > Length(Pattern) Then Invalid('classe non fermee');
 If Pattern[P] = '\' Then Begin
  Inc(P); ClassItem := Escape;
 End
  Else
 Begin
  ClassItem := [Pattern[P]]; Inc(P);
 End;
End;

Function Singleton(Const Chars: TRegexChars): Integer;
Var
 I, Count: Integer;
Begin
 Singleton := -1; Count := 0;
 For I := 0 To 255 Do If Chr(I) In Chars Then Begin
  Singleton := I; Inc(Count);
 End;
 If Count <> 1 Then Invalid('borne de plage non litterale');
End;
Function Expression: Integer;Forward;

Function Atom: Integer;
Var
 C: Char;
 N, Lo, Hi, I: Integer;
 Negated, Any: Boolean;
 Chars, Part: TRegexChars;
Begin
 If P > Length(Pattern) Then Begin
  Atom := Node(rnEmpty, -1, -1); Exit;
 End;
 C := Pattern[P]; Inc(P);
 If C = '(' Then Begin
  Inc(Depth); If Depth > 64 Then Invalid('imbrication trop profonde');
  If P <= Length(Pattern) Then If Pattern[P] = '?' Then Begin
   If Copy(Pattern, P, 2) <> '?:' Then Invalid('assertion/groupe non pris en charge');
   Inc(P, 2);
  End;
  N := Expression;
  If (P > Length(Pattern)) Or (Pattern[P] <> ')') Then Invalid('parenthese non fermee');
  Inc(P); Dec(Depth); Atom := N; Exit;
 End;
 If C = '^' Then Begin
  Atom := Node(rnBegin, -1, -1); Exit;
 End;
 If C = '$' Then Begin
  Atom := Node(rnEnd, -1, -1); Exit;
 End;
 Chars := [];
 If C = '[' Then Begin
  Negated := False; Any := False;
  If P <= Length(Pattern) Then If Pattern[P] = '^' Then Begin
   Negated := True; Inc(P);
  End;
  While P <= Length(Pattern) Do Begin
   If Pattern[P] = ']' Then Break;
   Part := ClassItem; Any := True;
   If (P < Length(Pattern)) And (Pattern[P] = '-') And (Pattern[P + 1] <> ']') Then Begin
    Inc(P); Lo := Singleton(Part); Hi := Singleton(ClassItem);
    If Hi < Lo Then Invalid('plage inversee');
    Part := [];
    For I := Lo To Hi Do Include(Part, Chr(I));
   End;
   Chars := Chars + Part;
  End;
  If Not Any Or (P > Length(Pattern)) Then Invalid('classe vide ou non fermee');
  Inc(P); If Negated Then Chars := [#0..#255] - Chars;
 End
 Else If C = '\' Then Chars := Escape Else
 If C = '.' Then Chars := [#0..#255] - [#10,#13]
  Else
 Begin
  If C In ['*','+','?','{','}',']',')','|'] Then Invalid('operateur sans operande');
  Chars := [C];
 End;
 N := Node(rnChars, -1, -1); Nodes[N].Chars := Chars; Atom := N;
End;

Function Number: Integer;Begin
 Number := 0;
 If (P > Length(Pattern)) Or Not (Pattern[P] In ['0'..'9']) Then Invalid(
 'entier de repetition attendu');
 While P <= Length(Pattern) Do Begin
  If Not (Pattern[P] In ['0'..'9']) Then Break;
  Number := Number * 10 + Ord(Pattern[P]) - Ord('0'); Inc(P);
  If Number > 1000 Then Invalid('repetition superieure a 1000');
 End;
End;

Function Factor: Integer;
Var
 N, R, Lo, Hi: Integer;
 C: Char;
Begin
 N := Atom; Factor := N; If P > Length(Pattern) Then Exit;
 C := Pattern[P]; If Not (C In ['*','+','?','{']) Then Exit;
 If Nodes[N].Kind In [rnBegin, rnEnd] Then Invalid('assertion repetee');
 Inc(P); Lo := 0; Hi := -1;
 If C = '+' Then Lo := 1 Else If C = '?' Then Hi := 1 Else
 If C = '{' Then Begin
  Lo := Number; Hi := Lo;
  If P <= Length(Pattern) Then If Pattern[P] = ',' Then Begin
   Inc(P); Hi := -1;
   If P <= Length(Pattern) Then If Pattern[P] <> '}' Then Hi := Number;
  End;
  If (P > Length(Pattern)) Or (Pattern[P] <> '}') Then Invalid('repetition non fermee');
  Inc(P); If (Hi >= 0) And (Hi < Lo) Then Invalid('bornes de repetition inversees');
 End;
 R := Node(rnRepeat, N, -1); Nodes[R].Minimum := Lo; Nodes[R].Maximum := Hi; Factor := R;
End;

Function Sequence: Integer;
Var
 N: Integer;
Begin
 Sequence := Node(rnEmpty, -1, -1);
 While P <= Length(Pattern) Do Begin
  If Pattern[P] In ['|',')'] Then Break;
  N := Factor; Sequence := Node(rnConcat, Sequence, N);
 End;
End;

Function Expression: Integer;
Var
 N: Integer;
Begin
 Expression := Sequence;
 While P <= Length(Pattern) Do Begin
  If Pattern[P] <> '|' Then Break;
  Inc(P); N := Sequence; Expression := Node(rnAlt, Expression, N);
 End;
End;

Function State(Kind: TRegexStateKind; A, B: Integer; Const Chars: TRegexChars): Integer;
Var
 N: Integer;
Begin
 N := Length(Regex.States); If N >= 4096 Then Invalid('automate trop grand');
 SetLength(Regex.States, N + 1);
 Regex.States[N].Kind := Kind; Regex.States[N].A := A; Regex.States[N].B := B;
 Regex.States[N].Chars := Chars; State := N;
End;

Function Emit(N, Next: Integer): Integer;
Var
 I, Tail, Loop: Integer;
Begin
 Emit := Next;
 Case Nodes[N].Kind Of
 rnEmpty: ;
 rnChars: Emit := State(rsChars, Next, -1, Nodes[N].Chars);
 rnBegin: Emit := State(rsBegin, Next, -1, []);
 rnEnd: Emit := State(rsEnd, Next, -1, []);
 rnConcat:
 Begin
  Tail := Emit(Nodes[N].Right, Next); Emit := Emit(Nodes[N].Left, Tail);
 End;
 rnAlt:
 Begin
  Tail := Emit(Nodes[N].Left, Next); Loop := Emit(Nodes[N].Right, Next);
  Emit := State(rsSplit, Tail, Loop, []);
 End;
 rnRepeat:
 Begin
  Tail := Next;
  If Nodes[N].Maximum < 0 Then Begin
   Loop := State(rsSplit, -1, Next, []);
   Tail := Emit(Nodes[N].Left, Loop); Regex.States[Loop].A := Tail; Tail := Loop;
  End Else
  For I := Nodes[N].Minimum + 1 To Nodes[N].Maximum Do Begin
   Loop := Emit(Nodes[N].Left, Tail); Tail := State(rsSplit, Loop, Tail, []);
  End;
  For I := 1 To Nodes[N].Minimum Do Tail := Emit(Nodes[N].Left, Tail);
  Emit := Tail;
 End;
End;
End;
Begin
 If Length(Pattern) > 1024 Then Fail('--suppress-regex: maximum 1024 octets.');
 Nodes := Nil; Regex.States := Nil; P := 1; Depth := 0;
 Root := Expression; If P <= Length(Pattern) Then Invalid('caractere inattendu');
 Terminal := State(rsMatch, -1, -1, []); Regex.Start := Emit(Root, Terminal);
End;

Function RegexMatches(Const Regex: TRegex; Const Value: String): Boolean;
Var
 Active, Next, Seen: TRegexFlags;
 Stack: TRegexStack;
 I, J, N: Integer;

Procedure Closure(Start, Position: Integer; Var Flags: TRegexFlags);
Var
 Top, Current: Integer;

Procedure Push(Index: Integer);Begin
 If Not Seen[Index] Then Begin
  Seen[Index] := True; Stack[Top] := Index; Inc(Top);
 End;
End;
Begin
 Top := 0; Push(Start);
 While Top > 0 Do Begin
  Dec(Top); Current := Stack[Top];
  Case Regex.States[Current].Kind Of
  rsSplit:
  Begin
   Push(Regex.States[Current].A); Push(Regex.States[Current].B);
  End;
  rsBegin: If Position = 0 Then Push(Regex.States[Current].A);
  rsEnd: If Position = Length(Value) Then Push(Regex.States[Current].A);
                                     Else Flags[Current] := True;
 End;
End;
End;
Begin
 N := Length(Regex.States); SetLength(Active, N); SetLength(Next, N); SetLength(Seen, N);
 SetLength(Stack, N);
 Closure(Regex.Start, 0, Active);
 For I := 1 To Length(Value) Do Begin
  For J := 0 To N - 1 Do Begin
   Next[J] := False; Seen[J] := False;
  End;
  For J := 0 To N - 1 Do If Active[J] And (Regex.States[J].Kind = rsChars)
  Then   If Value[I] In Regex.States[J].Chars Then Closure(Regex.States[J].A, I, Next);
  For J := 0 To N - 1 Do Active[J] := Next[J];
 End;
 RegexMatches := False;
 For J := 0 To N - 1 Do If Active[J] And (Regex.States[J].Kind = rsMatch)
 Then RegexMatches := True;
End;

Const
 NonSpeechTokens: Array[0..53] Of String = (
 '"',
 '#',
 '(',
 ')',
 '*',
 '+',
 '/',
 ':',
 ';',
 '<',
 '=',
 '>',
 '@',
 '[',
 '\',
 ']',
 '^',
 '_',
 '`',
 '{',
 '|',
 '}',
 '~',
 #$E3#$80#$8C,
 #$E3#$80#$8D,
 #$E3#$80#$8E,
 #$E3#$80#$8F,
 '<<',
 '>>',
 '<<<',
 '>>>',
 '--',
 '---',
 '-(',
 '-[',
 '(''',
 '("',
 '((',
 '))',
 '(((',
 ')))',
 '[[',
 ']]',
 '{{',
 '}}',
 #$E2#$99#$AA#$E2#$99#$AA,
 #$E2#$99#$AA#$E2#$99#$AA#$E2#$99#$AA,
 #$E2#$99#$A9,
 #$E2#$99#$AA,
 #$E2#$99#$AB,
 #$E2#$99#$AC,
 #$E2#$99#$AD,
 #$E2#$99#$AE,
 #$E2#$99#$AF);

Procedure ConfigureSuppression(Var M: TWhisperModel; NonSpeech, HasRegex: Boolean;
                               Const Pattern: String);
Var
 Regex: TRegex;
 I, J, Count, Remaining: Integer;
 Blocked: Boolean;
Begin
 M.Suppressed := Nil; If Not NonSpeech And Not HasRegex Then Exit;
 If HasRegex Then CompileRegex(Pattern, Regex);
 SetLength(M.Suppressed, M.EOT); Count := 0; Remaining := 0;
 For I := 0 To M.EOT - 1 Do If M.Vocab[I] <> '' Then Begin
  Blocked := False;
  If NonSpeech Then Begin
   For J := 0 To High(NonSpeechTokens) Do    If (M.Vocab[I] = NonSpeechTokens[J]) Or (
   M.Vocab[I] = ' ' + NonSpeechTokens[J]) Then Blocked := True;
   If (M.Vocab[I] = ' -') Or (M.Vocab[I] = ' ' + #39) Then Blocked := True;
  End;
  If HasRegex Then If RegexMatches(Regex, M.Vocab[I]) Then Blocked := True;
  M.Suppressed[I] := Blocked;
  If Blocked Then Inc(Count) Else If M.Vocab[I] <> ' ' Then Inc(Remaining);
 End;
 If Remaining = 0 Then Fail('Suppression: aucun token de texte disponible.');
 Diagnostic('Tokens supprimes: ' + IntToStr(Count));
End;

Procedure Version;Begin
 WriteLn('WHISPER-CLI.PAS ', NativeVersion, ' - moteur Whisper natif en Pascal');
 WriteLn('whisper.cpp: non lie; compatibilite partielle de la ligne de commande.');
End;

Procedure Help;Begin
 WriteLn('WHISPER-CLI - Cette commande permet de lancer le moteur Whisper natif en Pascal.');
 WriteLn;
 WriteLn('Syntaxe : whisper-cli [options] fichier0.wav fichier1.wav ...');
 WriteLn('          whisper-cli [options] -f fichier.wav');
 WriteLn;
 WriteLn('  -h, --help           Affiche cette aide (/? accepte aussi)');
 WriteLn('      --version        Version du port Pascal autonome');
 WriteLn(
 '  -t N, --threads N    Threads de calcul matriciel par processeur (1..64, defaut 1)');
 WriteLn('  -p N, --processors N Portions audio traitees en parallele (1..8, defaut 1)');
 WriteLn('  -m NOM, --model NOM  Modele GGML FP16/FP32 (defaut models/ggml-base.en.bin)');
 WriteLn(
 '  -f NOM, --file NOM   Fichier WAV; option repetable, cumulable avec les fichiers positionnels');
 WriteLn(
 '  -wt N, --word-thold N       Probabilite des reperes temporels (0..1, defaut 0.01)');
 WriteLn(
 '  -et N, --entropy-thold N    Entropie minimale des tokens recents (defaut 2.4)');
 WriteLn('  -lpt N, --logprob-thold N   Log-probabilite moyenne minimale (defaut -1)');
 WriteLn('  -nth N, --no-speech-thold N Probabilite de non-parole (0..1, defaut 0.6)');
 WriteLn('  -bo N, --best-of N      Candidats echantillonnes (1..16, defaut 1)');
 WriteLn('  -bs N, --beam-size N    Taille du faisceau a temperature 0 (1..16, defaut 1)')
 ;
 WriteLn('  -tp N, --temperature N  Temperature entre 0 et 1 (defaut 0)');
 WriteLn('  -tpi N, --temperature-inc N  Increment des reprises (0..1, defaut 0.2)');
 WriteLn('  -nf, --no-fallback      Desactiver les nouvelles tentatives');
 WriteLn('  -mc N, --max-context N  Tokens de contexte conserves (defaut 16384; 0 aucun)')
 ;
 WriteLn('  -ml N, --max-len N      Caracteres par segment (0 sans limite)');
 WriteLn('  -sow, --split-on-word   Preferer les coupures entre mots');
 WriteLn('  -ac N, --audio-ctx N    Contexte encodeur (0 complet, sinon 1..1500)');
 WriteLn('      --prompt TEXTE      Texte initial pour guider le decodeur');
 WriteLn('      --carry-initial-prompt  Conserver le prompt a chaque fenetre');
 WriteLn('  -ot N, --offset-t N  Debut en millisecondes (defaut 0)');
 WriteLn('  -on N, --offset-n N  Premier index affiche des segments (defaut 0)');
 WriteLn('  -d N, --duration N   Duree en millisecondes (0 = jusqu''a la fin)');
 WriteLn('  -sns, --suppress-nst   Supprimer les tokens non vocaux');
 WriteLn('  --suppress-regex REGEX Masquer les tokens correspondant entierement au regex')
 ;
 WriteLn('  -dtw MODEL, --dtw MODEL  Alignement DTW des tokens (profil du modele)');
 WriteLn('  -di, --diarize         Identifier le canal stereo du locuteur (0/1/?)');
 WriteLn('  -tdrz, --tinydiarize   Changements de locuteur (modele tdrz requis)');
 WriteLn('  -np, --no-prints       Resultats seulement (les erreurs restent visibles)');
 WriteLn('  -ps, --print-special   Afficher les tokens speciaux du prefixe et de fin');
 WriteLn('  -pc, --print-colors    Couleurs ANSI selon le score de confiance');
 WriteLn('  -pp, --print-progress  Progression par processeur sur stderr');
 WriteLn('  -nt, --no-timestamps   Masquer les temps dans la console');
 WriteLn('       --print-confidence  Score de confiance de la fenetre');
 WriteLn('  -ls, --log-score       Scores des tokens retenus, sur stderr');
 WriteLn('  -otxt, --output-txt     Export .txt');
 WriteLn('  -ovtt, --output-vtt     Sous-titres .vtt');
 WriteLn('  -osrt, --output-srt     Sous-titres .srt');
 WriteLn('  -olrc, --output-lrc     Paroles synchronisees .lrc');
 WriteLn('  -ocsv, --output-csv     Export .csv');
 WriteLn('  -oj, --output-json      Export .json');
 WriteLn('  -ojf, --output-json-full  JSON avec metadonnees et mots');
 WriteLn('  -owts, --output-words   Mots horodates .wts (JSON) et lecteur .html');
 WriteLn(
 '  -of NOM, --output-file NOM  Base de sortie, repetable dans l''ordre des entrees');
 WriteLn('  -fp NOM, --font-path NOM    Police locale du lecteur HTML');
 WriteLn('  -dl, --detect-language  Detecter la langue puis quitter, sans transcription');
 WriteLn('  -tr, --translate        Traduire vers l''anglais (modele multilingue)');
 WriteLn('  -l CODE, --language CODE  Langue Whisper, ou auto (defaut en; francais: fr)');
 WriteLn(
 '      --               Fin des options; les arguments suivants sont des fichiers');
 WriteLn;
 WriteLn(
 'Decodeur CPU integre (glouton, faisceau, echantillonnage), aucun outil externe. Texte UTF-8 sur stdout.');
 WriteLn('Temps affiches: bornes des portions audio, pas alignement mot par mot.');
 WriteLn('WAV PCM/float32, 256 Mio/30 min maximum. Pour MP3: convertir avec MP32WAV.');
 WriteLn('Modeles quantifies/GGUF, GPU et autres options whisper.cpp non pris en charge.')
 ;
 WriteLn('Les poids de modele restent des fichiers de donnees necessaires.');
 WriteLn('Free Pascal 3.2+ requis; Turbo Pascal DOS ne peut pas executer ce moteur.');
 WriteLn('Parallelisme avec System: disponible dans cette version sous Windows.');
End;

Function PositiveInteger(Const Text, Option: String; Maximum: Integer): Integer;
Var
 I, V, Code: Integer;
Begin
 If Text = '' Then Fail('Valeur vide: ' + Option);
 For I := 1 To Length(Text) Do If Not (Text[I] In ['0'..'9']) Then Fail(
 'Entier positif requis: ' + Option);
 Val(Text, V, Code);
 If (Code <> 0) Or (V < 1) Or (V > Maximum) Then Fail(Option + ': valeur entre 1 et ' +
 IntToStr(Maximum) + ' requise.');
 PositiveInteger := V;
End;

Function NonNegativeInteger(Const Text, Option: String): Integer;
Var
 I, V, Code: Integer;
Begin
 If Text = '' Then Fail('Valeur vide: ' + Option);
 For I := 1 To Length(Text) Do If Not (Text[I] In ['0'..'9']) Then  Fail(
 'Entier positif ou nul requis: ' + Option);
 Val(Text, V, Code);
 If (Code <> 0) Or (V < 0) Then  Fail(Option + ': valeur entre 0 et 2147483647 requise.');
 NonNegativeInteger := V;
End;

Function BoundedReal(Const Text, Option: String; Lower, Upper: Double): Double;
Var
 I, Digits, BeforePoint, FirstNonZero, Kept, Exponent, Code, J: Integer;
 V: Double;
 PointSeen, Negative: Boolean;
Begin
 If Text = '' Then Fail('Valeur vide: ' + Option);
 I := 1; Negative := False;
 If Text[I] In ['+', '-'] Then Begin
  Negative := Text[I] = '-'; Inc(I);
 End;
 Digits := 0; BeforePoint := 0; FirstNonZero := 0; Kept := 0;
 V := 0; PointSeen := False; Exponent := 0;
 While I <= Length(Text) Do Begin
  If Text[I] In ['e', 'E'] Then Break;
  If Text[I] = '.' Then Begin
   If PointSeen Then Fail('Nombre decimal invalide: ' + Option);
   PointSeen := True;
  End Else
  Begin
   If Not (Text[I] In ['0'..'9']) Then Fail('Nombre decimal invalide: ' + Option);
   Inc(Digits); If Not PointSeen Then Inc(BeforePoint);
   If (FirstNonZero = 0) And (Text[I] <> '0') Then FirstNonZero := Digits;
   If (FirstNonZero > 0) And (Kept < 16) Then Begin
    V := V * 10 + Ord(Text[I]) - Ord('0'); Inc(Kept);
   End;
  End;
  Inc(I);
 End;
 If Digits = 0 Then Fail('Nombre decimal invalide: ' + Option);
 If I <= Length(Text) Then Begin
  Inc(I); J := I;
  If I <= Length(Text) Then If Text[I] In ['+', '-'] Then Inc(I);
  If I > Length(Text) Then Fail('Exposant invalide: ' + Option);
  While I <= Length(Text) Do Begin
   If Not (Text[I] In ['0'..'9']) Then Fail('Exposant invalide: ' + Option);
   Inc(I);
  End;
  Val(Copy(Text, J, Length(Text) - J + 1), Exponent, Code);
  If (Code <> 0) Or (Exponent < -10000) Or (Exponent > 10000) Then   Fail(
  'Exposant hors limites: ' + Option);
 End;
 BoundedReal := 0; If FirstNonZero = 0 Then Exit;
 Exponent := Exponent + BeforePoint - FirstNonZero;
 For J := 2 To Kept Do V := V / 10;
 If Exponent > 300 Then Fail('Valeur trop grande: ' + Option);
 If Exponent < -300 Then Fail(Option + ': valeur non nulle trop petite (minimum 1e-300).')
 ;
 If Exponent > 0 Then
 For J := 1 To Exponent Do V := V * 10
  Else
 For J := 1 To -Exponent Do V := V / 10;
 If Negative Then V := -V;
 If (V < Lower) Or (V > Upper) Then Fail('Valeur hors limites: ' + Option);
 BoundedReal := V;
End;

Function UnitReal(Const Text, Option: String): Double;Begin
 UnitReal := BoundedReal(Text, Option, 0, 1);
End;

Function LanguageIndex(Const Name: String): Integer;
Var
 I: Integer;
Begin
 LanguageIndex := -1; If Name = 'auto' Then Exit;
 For I := 0 To High(LanguageCodes) Do If Name = LanguageCodes[I] Then Begin
  LanguageIndex := I; Exit;
 End;
 Fail('Code de langue inconnu: ' + Name);
End;

Procedure AddInput(Var O: TOptions; Const Name: String);
Var
 N: Integer;
Begin
 If Name = '' Then Fail('Nom de fichier audio vide.');
 N := Length(O.Files);
 If N >= 1024 Then Fail('Maximum 1024 fichiers par commande.');
 SetLength(O.Files, N + 1); O.Files[N] := Name;
End;

Procedure ParseOptions(Var O: TOptions);
Var
 I, L, N: Integer;
 Arg, Value: String;
 PromptUTF8: UTF8String;
 Positional, LanguageSet: Boolean;
Begin
 O.Threads := 1; O.Processors := 1; O.Model := 'models/ggml-base.en.bin';
 O.Language := 'en'; O.DTWModel := ''; LanguageSet := False;
 O.SuppressNST := False; O.HasSuppressRegex := False; O.SuppressRegex := '';
 O.NoPrints := False; O.PrintSpecial := False; O.PrintColors := False;
 O.PrintProgress := False; O.NoTimestamps := False;
 O.PrintConfidence := False; O.LogScore := False;
 O.OutputFormats := []; O.FullJSON := False; O.FontPath := ''; O.OutputBases := Nil;
 O.DetectLanguage := False; O.Translate := False;
 O.Diarize := False; O.TinyDiarize := False;
 O.WordThreshold := 0.01; O.EntropyThreshold := 2.4;
 O.LogProbThreshold := -1; O.NoSpeechThreshold := 0.6;
 O.BestOf := 1; O.BeamSize := 1; O.Temperature := 0;
 O.TemperatureInc := 0.2; O.NoFallback := False;
 O.MaxContext := 16384; O.MaxLength := 0; O.AudioContext := 0;
 O.SplitOnWord := False; O.CarryPrompt := False; O.Prompt := '';
 O.OffsetMS := 0; O.DurationMS := 0; O.OffsetIndex := 0; O.ShowIndex := False;
 SetLength(O.Files, 0); Positional := False; I := 1;
 If ParamCount = 0 Then Begin
  Help; Halt(1);
 End;
 While I <= ParamCount Do Begin
  Arg := ParamStr(I);
  If Positional Then AddInput(O, Arg) Else
  If Arg = '--' Then Positional := True Else
  If (Arg = '-h') Or (Arg = '--help') Or (Arg = '/?') Then Begin
   Help; Halt(0);
  End
  Else If Arg = '--version' Then Begin
   Version; Halt(0);
  End
  Else If (Arg = '-sns') Or (Arg = '--suppress-nst') Then O.SuppressNST := True Else
  If (Arg = '-di') Or (Arg = '--diarize') Then O.Diarize := True Else
  If (Arg = '-tdrz') Or (Arg = '--tinydiarize') Then O.TinyDiarize := True Else
  If (Arg = '-np') Or (Arg = '--no-prints') Then O.NoPrints := True Else
  If (Arg = '-ps') Or (Arg = '--print-special') Then O.PrintSpecial := True Else
  If (Arg = '-pc') Or (Arg = '--print-colors') Then O.PrintColors := True Else
  If (Arg = '-pp') Or (Arg = '--print-progress') Then O.PrintProgress := True Else
  If (Arg = '-nt') Or (Arg = '--no-timestamps') Then O.NoTimestamps := True Else
  If Arg = '--print-confidence' Then O.PrintConfidence := True Else
  If (Arg = '-ls') Or (Arg = '--log-score') Then O.LogScore := True Else
  If (Arg = '-otxt') Or (Arg = '--output-txt') Then Include(O.OutputFormats, efTXT) Else
  If (Arg = '-ovtt') Or (Arg = '--output-vtt') Then Include(O.OutputFormats, efVTT) Else
  If (Arg = '-osrt') Or (Arg = '--output-srt') Then Include(O.OutputFormats, efSRT) Else
  If (Arg = '-olrc') Or (Arg = '--output-lrc') Then Include(O.OutputFormats, efLRC) Else
  If (Arg = '-ocsv') Or (Arg = '--output-csv') Then Include(O.OutputFormats, efCSV) Else
  If (Arg = '-oj') Or (Arg = '--output-json') Then Include(O.OutputFormats, efJSON) Else
  If (Arg = '-ojf') Or (Arg = '--output-json-full') Then Begin
   Include(O.OutputFormats, efJSON); O.FullJSON := True;
  End
  Else If (Arg = '-owts') Or (Arg = '--output-words') Then Begin
   Include(O.OutputFormats, efWords); Include(O.OutputFormats, efHTML);
  End
  Else If (Arg = '-dl') Or (Arg = '--detect-language') Then O.DetectLanguage := True Else
  If (Arg = '-tr') Or (Arg = '--translate') Then O.Translate := True Else
  If (Arg = '-nf') Or (Arg = '--no-fallback') Then O.NoFallback := True Else
  If (Arg = '-sow') Or (Arg = '--split-on-word') Then O.SplitOnWord := True Else
  If Arg = '--carry-initial-prompt' Then O.CarryPrompt := True Else
  If (Arg = '-t') Or (Arg = '--threads') Or (Arg = '-p') Or (Arg = '--processors') Or
  (Arg = '-m') Or (Arg = '--model') Or (Arg = '-f') Or (Arg = '--file') Or
  (Arg = '--suppress-regex') Or
  (Arg = '-dtw') Or (Arg = '--dtw') Or
  (Arg = '-of') Or (Arg = '--output-file') Or
  (Arg = '-fp') Or (Arg = '--font-path') Or
  (Arg = '-wt') Or (Arg = '--word-thold') Or
  (Arg = '-et') Or (Arg = '--entropy-thold') Or
  (Arg = '-lpt') Or (Arg = '--logprob-thold') Or
  (Arg = '-nth') Or (Arg = '--no-speech-thold') Or
  (Arg = '-bo') Or (Arg = '--best-of') Or
  (Arg = '-bs') Or (Arg = '--beam-size') Or
  (Arg = '-tp') Or (Arg = '--temperature') Or
  (Arg = '-tpi') Or (Arg = '--temperature-inc') Or
  (Arg = '-mc') Or (Arg = '--max-context') Or
  (Arg = '-ml') Or (Arg = '--max-len') Or
  (Arg = '-ac') Or (Arg = '--audio-ctx') Or (Arg = '--prompt') Or
  (Arg = '-ot') Or (Arg = '--offset-t') Or
  (Arg = '-on') Or (Arg = '--offset-n') Or
  (Arg = '-d') Or (Arg = '--duration') Or
  (Arg = '-l') Or (Arg = '--language') Then Begin
   Inc(I); If I > ParamCount Then Fail('Valeur manquante: ' + Arg);
   Value := ParamStr(I);
   If (Value = '') And (Arg <> '--prompt') And (Arg <> '--suppress-regex') Then Fail(
   'Valeur vide: ' + Arg);
   If (Arg = '-t') Or (Arg = '--threads') Then O.Threads := PositiveInteger(Value, Arg,
   64)
   Else If (Arg = '-p') Or (Arg = '--processors') Then O.Processors := PositiveInteger(
   Value, Arg, 8)
   Else If (Arg = '-m') Or (Arg = '--model') Then O.Model := Value Else
   If (Arg = '-l') Or (Arg = '--language') Then Begin
    O.Language := Value; LanguageSet := True;
   End
   Else If (Arg = '-ot') Or (Arg = '--offset-t') Then    O.OffsetMS := NonNegativeInteger(
   Value, Arg)
   Else If (Arg = '-d') Or (Arg = '--duration') Then    O.DurationMS :=
   NonNegativeInteger(Value, Arg)
   Else If (Arg = '-on') Or (Arg = '--offset-n') Then Begin
    O.OffsetIndex := NonNegativeInteger(Value, Arg); O.ShowIndex := True;
   End
   Else If (Arg = '-mc') Or (Arg = '--max-context') Then    O.MaxContext :=
   NonNegativeInteger(Value, Arg)
   Else If (Arg = '-ml') Or (Arg = '--max-len') Then    O.MaxLength := NonNegativeInteger(
   Value, Arg)
   Else If (Arg = '-ac') Or (Arg = '--audio-ctx') Then    O.AudioContext :=
   NonNegativeInteger(Value, Arg)
   Else If Arg = '--prompt' Then Begin
    PromptUTF8 := UTF8String(Value);
    SetString(O.Prompt, PChar(PromptUTF8), Length(PromptUTF8));
   End
   Else If (Arg = '-bo') Or (Arg = '--best-of') Then    O.BestOf := PositiveInteger(Value,
   Arg, 16)
   Else If (Arg = '-bs') Or (Arg = '--beam-size') Then    O.BeamSize := PositiveInteger(
   Value, Arg, 16)
   Else If (Arg = '-tp') Or (Arg = '--temperature') Then    O.Temperature := UnitReal(
   Value, Arg)
   Else If (Arg = '-tpi') Or (Arg = '--temperature-inc') Then    O.TemperatureInc :=
   UnitReal(Value, Arg)
   Else If (Arg = '-wt') Or (Arg = '--word-thold') Then    O.WordThreshold := UnitReal(
   Value, Arg)
   Else If (Arg = '-nth') Or (Arg = '--no-speech-thold') Then    O.NoSpeechThreshold :=
   UnitReal(Value, Arg)
   Else If (Arg = '-et') Or (Arg = '--entropy-thold') Then    O.EntropyThreshold :=
   BoundedReal(Value, Arg, 0, 1000000)
   Else If (Arg = '-lpt') Or (Arg = '--logprob-thold') Then    O.LogProbThreshold :=
   BoundedReal(Value, Arg, -1000000, 0)
   Else If (Arg = '-of') Or (Arg = '--output-file') Then Begin
    N := Length(O.OutputBases); SetLength(O.OutputBases, N + 1);
    O.OutputBases[N] := Value;
   End
   Else If (Arg = '-fp') Or (Arg = '--font-path') Then O.FontPath := Value Else
   If (Arg = '-dtw') Or (Arg = '--dtw') Then O.DTWModel := Value Else
   If Arg = '--suppress-regex' Then Begin
    PromptUTF8 := UTF8Encode(UnicodeString(Value));
    SetString(O.SuppressRegex, PChar(PromptUTF8), Length(PromptUTF8));
    O.HasSuppressRegex := True;
   End
   Else AddInput(O, Value);
  End
  Else If (Arg <> '') And (Arg[1] = '-') Then Fail('Option non prise en charge: ' + Arg)
                                         Else AddInput(O, Arg);
  Inc(I);
 End;
 If O.Diarize And O.TinyDiarize Then Fail('--diarize et --tinydiarize sont exclusifs.');
 If Length(O.Files) = 0 Then Fail('Au moins un fichier WAV est requis.');
 If O.Threads * O.Processors > 64 Then Fail(
 'Le produit threads * processors ne doit pas depasser 64.');
 {$IFNDEF MSWINDOWS}
  If (O.Threads > 1) Or (O.Processors > 1) Then  Fail(
  'Cette compilation sans gestionnaire POSIX exige -t 1 -p 1; parallelisme disponible sous Windows.');
 {$ENDIF}
 If O.DetectLanguage Or (O.Translate And Not LanguageSet) Then O.Language := 'auto';
 L := LanguageIndex(O.Language);
 If Not FileExists(O.Model) Then Fail('Modele introuvable: ' + O.Model +
 '; utiliser -m chemin_du_modele.bin');
 For I := 0 To High(O.Files) Do If Not FileExists(O.Files[I]) Then Fail(
 'Fichier audio introuvable: ' + O.Files[I]);
 CheckExports(O);
End;

Procedure AppendToken(Var Tokens: TTokens; Token: Integer);
Var
 N: Integer;
Begin
 N := Length(Tokens); SetLength(Tokens, N + 1); Tokens[N] := Token;
End;
{ Matching glouton du vocabulaire GGML, comme le tokenizer de reference
  whisper.cpp: les poids contiennent directement les octets des tokens. }

Function PromptClass(C: Char): Integer;Begin
 If C In [' ', #9, #10, #13] Then PromptClass := 0 Else
 If C In ['0'..'9'] Then PromptClass := 2 Else
 If (C In ['A'..'Z', 'a'..'z']) Or (Ord(C) >= 128) Then PromptClass := 1
                                                   Else PromptClass := 3;
End;

Procedure TokenizePrompt(Const Text: String; Const M: TWhisperModel;Var Tokens: TTokens);
Var
 P, Stop, Start, Kind, I, Best, Size, BestSize: Integer;
 Suffix: String;
 Piece: String;
Begin
 Tokens := Nil; P := 1;
 While P <= Length(Text) Do Begin
  Start := P;
  If (Text[P] = ' ') And (P < Length(Text)) Then   If PromptClass(Text[P + 1]) <>
  0 Then Inc(P);
  Kind := PromptClass(Text[P]);
  Size := 0;
  If Text[P] = #39 Then Begin
   Suffix := Copy(Text, P + 1, 2);
   If (Suffix = 're') Or (Suffix = 've') Or (Suffix = 'll') Then Size := 3 Else
   If P < Length(Text) Then    If Text[P + 1] In ['s', 't', 'm', 'd'] Then Size := 2;
  End;
  If Size > 0 Then Inc(P, Size)
   Else
  Begin
   Inc(P);
   While P <= Length(Text) Do Begin
    If PromptClass(Text[P]) <> Kind Then Break;
    Inc(P);
   End;
   { Laisser le dernier espace pour le mot suivant. }
   If (Kind = 0) And (P <= Length(Text)) And (P - Start > 1) Then    Dec(P);
  End;
  Stop := P;
  While Start < Stop Do Begin
   Best := -1; BestSize := 0;
   For I := 0 To M.EOT - 1 Do Begin
    Size := Length(M.Vocab[I]);
    If (Size > BestSize) And (Size <= Stop - Start) Then Begin
     Piece := Copy(Text, Start, Size);
     If Piece = M.Vocab[I] Then Begin
      Best := I; BestSize := Size;
     End;
    End;
   End;
   If Best < 0 Then Fail('Prompt: octet absent du vocabulaire GGML.');
   AppendToken(Tokens, Best); Inc(Start, BestSize);
  End;
 End;
End;

Procedure KeepTail(Var Tokens: TTokens; Limit: Integer);
Var
 I, Count: Integer;
Begin
 Count := Length(Tokens);
 If Count <= Limit Then Exit;
 For I := 0 To Limit - 1 Do Tokens[I] := Tokens[Count - Limit + I];
 SetLength(Tokens, Limit);
End;

Procedure BuildContext(Const Initial, History: TTokens; Carry: Boolean;Limit: Integer;
                       Var Context: TTokens);
Var
 I, TakeInitial, TakeHistory: Integer;
Begin
 Context := Nil; TakeInitial := 0;
 If Carry Then TakeInitial := MinInt(Length(Initial), Limit);
 TakeHistory := MinInt(Length(History), Limit - TakeInitial);
 For I := Length(Initial) - TakeInitial To High(Initial) Do AppendToken(Context,
 Initial[I]);
 For I := Length(History) - TakeHistory To High(History) Do AppendToken(Context,
 History[I]);
End;

Type
 TLogProbabilities = Array Of Double;
 TTokenScore = Record
  Token: Integer;
  LogProbability, BestLogProbability: Double;
 End;
 TTokenScores = Array Of TTokenScore;
 TDecodeCandidate = Record
  Tokens: TTokens;
  TimeHints: TTimeHints;
  Scores: TTokenScores;
  Cache: TDecoderCaches;
  Logits: TMatrix;
  Position: Integer;
  Score: Double;
  Finished, Stopped: Boolean;
 End;
 TCandidates = Array Of TDecodeCandidate;
 TBeamChoice = Record
  Parent, Token: Integer;
  Score: Double;
 End;
 TBeamChoices = Array[0..15] Of TBeamChoice;

Procedure CloneCache(Const Source: TDecoderCaches; Var Dest: TDecoderCaches);
Var
 I: Integer;
Begin
 Dest := Nil; SetLength(Dest, Length(Source));
 For I := 0 To High(Source) Do Begin
  Dest[I] := Source[I];
  { Les projections audio sont immuables et partagees. L'historique est prive. }
  Dest[I].SelfK.Data := Copy(Source[I].SelfK.Data, 0, Length(Source[I].SelfK.Data));
  Dest[I].SelfV.Data := Copy(Source[I].SelfV.Data, 0, Length(Source[I].SelfV.Data));
 End;
End;

Procedure StartCandidate(Const Cache: TDecoderCaches; Const Logits: TMatrix;
                         Position: Integer; Var Candidate: TDecodeCandidate);Begin
 Candidate.Tokens := Nil; Candidate.TimeHints := Nil; Candidate.Scores := Nil;
 CloneCache(Cache, Candidate.Cache);
 Candidate.Logits := Logits;
 Candidate.Logits.Data := Copy(Logits.Data, 0, Length(Logits.Data));
 Candidate.Position := Position; Candidate.Score := 0;
 Candidate.Finished := False; Candidate.Stopped := False;
End;

Function LastOutputToken(Const M: TWhisperModel): Integer;Begin
 LastOutputToken := M.EOT;
 If M.TinyDiarize Then LastOutputToken := M.Transcribe + 1;
End;

Function AllowedOutputToken(Token: Integer; Const M: TWhisperModel): Boolean;Begin
 AllowedOutputToken := (Token = M.EOT) Or
 ((Token < M.EOT) And (M.Vocab[Token] <> '')) Or
 (M.TinyDiarize And (Token = M.Transcribe + 1));
 If Token < Length(M.Suppressed) Then  If M.Suppressed[Token] Then AllowedOutputToken :=
 False;
End;

Procedure TokenProbabilities(Const Logits: TMatrix; Const M: TWhisperModel;
                             FirstToken: Boolean; Var Probabilities: TLogProbabilities);
Var
 I: Integer;
 Peak, Sum: Double;
 Allowed: Boolean;
Begin
 SetLength(Probabilities, LastOutputToken(M) + 1); Peak := -1E30;
 For I := 0 To High(Probabilities) Do Begin
  Allowed := AllowedOutputToken(I, M);
  If FirstToken And ((I = M.EOT) Or (M.TinyDiarize And (I = M.Transcribe + 1)) Or (
  M.Vocab[I] = ' ')) Then Allowed := False;
  Probabilities[I] := -1E30;
  If Allowed Then Begin
   Probabilities[I] := Logits.Data[I];
   If Probabilities[I] > Peak Then Peak := Probabilities[I];
  End;
 End;
 If Peak <= -1E30 Then Fail('Aucun token de texte disponible.');
 Sum := 0;
 For I := 0 To High(Probabilities) Do  If Probabilities[I] > -1E30 Then Sum := Sum + Exp(
 Probabilities[I] - Peak);
 Sum := Ln(Sum);
 For I := 0 To High(Probabilities) Do  If Probabilities[I] > -
 1E30 Then Probabilities[I] := Probabilities[I] - Peak - Sum;
End;

Function NextRandom(Var Seed: LongInt): Double;Begin
 { Park-Miller: etat local au processeur, reproductible et sans Random global. }
 Seed := (Int64(Seed) * 48271) Mod 2147483647;
 NextRandom := Seed / 2147483647.0;
End;

Function SampleToken(Const Probabilities: TLogProbabilities; Temperature: Double;
                     Var Seed: LongInt): Integer;
Var
 I, Best: Integer;
 Peak, Sum, Target, Scale: Double;
Begin
 Best := 0; Peak := -1E30;
 For I := 0 To High(Probabilities) Do  If Probabilities[I] > Peak Then Begin
  Peak := Probabilities[I]; Best := I;
 End;
 SampleToken := Best; If Temperature <= 0 Then Exit;
 Scale := Temperature; If Scale < 1E-6 Then Scale := 1E-6;
 Sum := 0;
 For I := 0 To High(Probabilities) Do  If Probabilities[I] > -1E30 Then Sum := Sum + Exp((
 Probabilities[I] - Peak) / Scale);
 Target := NextRandom(Seed) * Sum;
 For I := 0 To High(Probabilities) Do If Probabilities[I] > -1E30 Then Begin
  Target := Target - Exp((Probabilities[I] - Peak) / Scale);
  If Target <= 0 Then Begin
   SampleToken := I; Exit;
  End;
 End;
End;

Function TimestampHint(Const Logits: TMatrix; Const M: TWhisperModel): TTimeHint;
Var
 I, Best, Start: Integer;
 Peak, Sum: Double;
 Hint: TTimeHint;
Begin
 Hint.Sample := 0; Hint.EndSample := 0; Hint.Probability := 0; Hint.Aligned := False;
 Start := M.NoTimestamps + 1; Best := -1; Peak := -1E30;
 For I := 0 To High(Logits.Data) Do  If Logits.Data[I] > Peak Then Peak := Logits.Data[I];
 For I := Start To High(Logits.Data) Do  If Best < 0 Then Best := I Else
 If Logits.Data[I] > Logits.Data[Best] Then Best := I;
 If Best >= 0 Then Begin
  Sum := 0;
  For I := 0 To High(Logits.Data) Do Sum := Sum + Exp(Logits.Data[I] - Peak);
  Hint.Sample := (Best - Start) * 320;
  Hint.Probability := Exp(Logits.Data[Best] - Peak) / Sum;
 End;
 TimestampHint := Hint;
End;

Procedure AdvanceCandidate(Var Candidate: TDecodeCandidate; Token: Integer;
                           LogProbability: Double; Const M: TWhisperModel);
Var
 I, N: Integer;
 Peak: Double;
Begin
 N := Length(Candidate.Scores); SetLength(Candidate.Scores, N + 1);
 Peak := -1E30;
 For I := 0 To LastOutputToken(M) Do Begin
  If Not AllowedOutputToken(I, M) Then Continue;
  If (Length(Candidate.Tokens) = 0) And ((I = M.EOT) Or (M.TinyDiarize And (I =
  M.Transcribe + 1)) Or (M.Vocab[I] = ' ')) Then Continue;
  If Candidate.Logits.Data[I] > Peak Then Peak := Candidate.Logits.Data[I];
 End;
 Candidate.Scores[N].Token := Token;
 Candidate.Scores[N].LogProbability := LogProbability;
 Candidate.Scores[N].BestLogProbability := LogProbability + Peak -
 Candidate.Logits.Data[Token];
 Candidate.Score := Candidate.Score + LogProbability;
 If Token = M.EOT Then Begin
  Candidate.Finished := True; Candidate.Stopped := True; Exit;
 End;
 SetLength(Candidate.TimeHints, Length(Candidate.Tokens) + 1);
 Candidate.TimeHints[Length(Candidate.Tokens)] := TimestampHint(Candidate.Logits, M);
 AppendToken(Candidate.Tokens, Token);
 If Candidate.Position >= M.TextContext Then Begin
  Candidate.Stopped := True; Exit;
 End;
 DecoderStep(Token, Candidate.Position, M, Candidate.Cache, Candidate.Logits);
 Inc(Candidate.Position);
End;

Function CandidateScore(Const Candidate: TDecodeCandidate): Double;
Var
 Count: Integer;
Begin
 Count := Length(Candidate.Tokens); If Candidate.Finished Then Inc(Count);
 If Count < 1 Then Count := 1;
 CandidateScore := Candidate.Score / Count;
End;

Procedure InsertChoice(Var Choices: TBeamChoices; Var Count: Integer;
                       Width, Parent, Token: Integer; Score: Double);
Var
 P, I: Integer;
Begin
 P := 0;
 While P < Count Do Begin
  If Score > Choices[P].Score Then Break; Inc(P);
 End;
 If P >= Width Then Exit;
 If Count < Width Then Inc(Count);
 For I := Count - 1 Downto P + 1 Do Choices[I] := Choices[I - 1];
 Choices[P].Parent := Parent; Choices[P].Token := Token; Choices[P].Score := Score;
End;

Procedure BeamDecode(Const Cache: TDecoderCaches; Const Logits: TMatrix;
                     Position, Width: Integer; Const M: TWhisperModel;
                     Var Winner: TDecodeCandidate);
Var
 Beams, Next: TCandidates;
 Choices: TBeamChoices;
 Probabilities: TLogProbabilities;
 I, J, Count, Parent, Token, Best: Integer;
 Active: Boolean;
Begin
 SetLength(Beams, 1); StartCandidate(Cache, Logits, Position, Beams[0]);
 Repeat
 Count := 0; Active := False;
 For I := 0 To High(Beams) Do Begin
  If Beams[I].Stopped Then    InsertChoice(Choices, Count, Width, I, -1, Beams[I].Score)
   Else
  Begin
   Active := True;
   TokenProbabilities(Beams[I].Logits, M, Length(Beams[I].Tokens) = 0, Probabilities);
   For J := 0 To High(Probabilities) Do If Probabilities[J] > -1E30 Then     InsertChoice(
   Choices, Count, Width, I, J, Beams[I].Score + Probabilities[J]);
  End;
 End;
 If Not Active Then Break;
 Next := Nil; SetLength(Next, Count);
 For I := 0 To Count - 1 Do Begin
  Parent := Choices[I].Parent; Token := Choices[I].Token;
  Next[I] := Beams[Parent];
  If Token >= 0 Then Begin
   Next[I].Tokens := Copy(Beams[Parent].Tokens, 0, Length(Beams[Parent].Tokens));
   Next[I].Scores := Copy(Beams[Parent].Scores, 0, Length(Beams[Parent].Scores));
   Next[I].TimeHints := Copy(Beams[Parent].TimeHints, 0, Length(Beams[Parent].TimeHints));
    { Ne jamais modifier les caches d'un parent encore utilise par un autre fils. }
   CloneCache(Beams[Parent].Cache, Next[I].Cache);
   Next[I].Logits.Data := Copy(Beams[Parent].Logits.Data, 0, Length(
   Beams[Parent].Logits.Data));
   AdvanceCandidate(Next[I], Token, Choices[I].Score - Beams[Parent].Score, M);
  End;
 End;
 Beams := Next;
 Until False;
 Best := 0;
 For I := 1 To High(Beams) Do  If (Beams[I].Finished And Not Beams[Best].Finished) Or
 ((Beams[I].Finished = Beams[Best].Finished) And
 (CandidateScore(Beams[I]) > CandidateScore(Beams[Best]))) Then Best := I;
 Winner := Beams[Best];
End;

Procedure SampleDecode(Const Cache: TDecoderCaches; Const Logits: TMatrix;
                       Position, Count: Integer; Temperature: Double;
                       Const M: TWhisperModel;Var Seed: LongInt;
                       Var Winner: TDecodeCandidate);
Var
 Candidate: TDecodeCandidate;
 Probabilities: TLogProbabilities;
 I, Token: Integer;
Begin
 For I := 1 To Count Do Begin
  StartCandidate(Cache, Logits, Position, Candidate);
  While Not Candidate.Stopped Do Begin
   TokenProbabilities(Candidate.Logits, M, Length(Candidate.Tokens) = 0, Probabilities);
   Token := SampleToken(Probabilities, Temperature, Seed);
   AdvanceCandidate(Candidate, Token, Probabilities[Token], M);
  End;
  If I = 1 Then Winner := Candidate Else
  If (Candidate.Finished And Not Winner.Finished) Or
  ((Candidate.Finished = Winner.Finished) And
  (CandidateScore(Candidate) > CandidateScore(Winner))) Then Winner := Candidate;
 End;
End;

Function TokenEntropy(Const Tokens: TTokens): Double;
Var
 I, J, Start, Count, N: Integer;
 P: Double;
 Seen: Boolean;
Begin
 TokenEntropy := 0; N := MinInt(Length(Tokens), 32);
 If N = 0 Then Exit;
 Start := Length(Tokens) - N;
 For I := Start To High(Tokens) Do Begin
  Seen := False;
  For J := Start To I - 1 Do If Tokens[J] = Tokens[I] Then Seen := True;
  If Seen Then Continue;
  Count := 0;
  For J := I To High(Tokens) Do If Tokens[J] = Tokens[I] Then Inc(Count);
  P := Count / N; TokenEntropy := TokenEntropy - P * Ln(P);
 End;
End;

Function EntropyFailure(Const Tokens: TTokens; Threshold: Double): Boolean;Begin
 EntropyFailure := (Length(Tokens) > 32) And (TokenEntropy(Tokens) < Threshold);
End;

Procedure DTWPath(Const Weights: TMatrix; Var Starts: TTokens);
Var
 Previous, Current: Array Of Double;
 Trace: Array Of Byte;
 I, J, K, Direction: Integer;
 Best: Double;
Begin
 If (Weights.Rows < 1) Or (Weights.Cols < 1) Then Fail('Matrice DTW vide.');
 SetLength(Previous, Weights.Cols); SetLength(Current, Weights.Cols);
 SetLength(Trace, Weights.Rows * Weights.Cols); SetLength(Starts, Weights.Rows);
 For I := 0 To Weights.Rows - 1 Do Begin
  For J := 0 To Weights.Cols - 1 Do Begin
   Best := 1E100; Direction := 0;
   If (I = 0) And (J = 0) Then Best := 0;
   If (I > 0) And (J > 0) Then Begin
    Best := Previous[J - 1]; Direction := 0;
   End;
   If I > 0 Then If Previous[J] < Best Then Begin
    Best := Previous[J]; Direction := 1;
   End;
   If J > 0 Then If Current[J - 1] < Best Then Begin
    Best := Current[J - 1]; Direction := 2;
   End;
   Current[J] := Best - Weights.Data[I * Weights.Cols + J];
   Trace[I * Weights.Cols + J] := Direction;
  End;
  For J := 0 To Weights.Cols - 1 Do Previous[J] := Current[J];
 End;
 I := Weights.Rows - 1; J := Weights.Cols - 1;
 Repeat
 Starts[I] := J;
 If (I = 0) And (J = 0) Then Break;
 K := Trace[I * Weights.Cols + J];
 If K = 0 Then Begin
  Dec(I); Dec(J);
 End
 Else If K = 1 Then Dec(I) Else Dec(J);
 Until False;
End;

Procedure AlignDTWTokens(Const M: TWhisperModel; Const PrefixCache: TDecoderCaches;
                         Position, Samples: Integer; Const Winner: TDecodeCandidate;
                         Var Hints: TTimeHints);
Var
 Cache: TDecoderCaches;
 Logits, Weights: TMatrix;
 Heads: Array Of TMatrix;
 Starts: TTokens;
 Frames, Count, I, J, L, H, K, HeadCount, Row, N, A, B: Integer;
 Mean, Variance, Scale, V: Double;
 Median: Array[0..6] Of Single;
Begin
 Count := Length(Winner.Tokens); If Count = 0 Then Exit;
 Frames := MinInt(PrefixCache[0].CrossK.Rows, (Samples + 319) Div 320);
 HeadCount := 0;
 For L := 0 To High(M.DTWHeads) Do
 For H := 0 To M.TextHeads - 1 Do  If (M.DTWHeads[L] And (LongWord(1) Shl H)) <>
 0 Then Inc(HeadCount);
 If (Frames < 1) Or (HeadCount = 0) Then Fail('Contexte DTW invalide.');
 SetLength(Heads, HeadCount);
 For H := 0 To HeadCount - 1 Do MatrixSize(Heads[H], Count + 2, Frames);
 CloneCache(PrefixCache, Cache); Cache[0].CaptureDTW := True;
 Cache[0].DTWFrames := Frames;
 For I := 0 To Count + 1 Do Begin
  If I = 0 Then DecoderStep(M.NoTimestamps, Position - 1, M, Cache, Logits) Else
  If I <= Count Then DecoderStep(Winner.Tokens[I - 1], Position + I - 1, M, Cache,
  Logits)
  Else If Position + Count < M.TextContext Then DecoderStep(M.EOT, Position + Count, M,
  Cache, Logits);
  N := 0;
  For L := 0 To High(Cache) Do If M.DTWHeads[L] <> 0 Then
  For H := 0 To Cache[L].Alignment.Rows - 1 Do Begin
   Move(Cache[L].Alignment.Data[H * Frames], Heads[N].Data[I * Frames], Frames * SizeOf(
   Single));
   Inc(N);
  End;
 End;
 Cache := Nil;
 MatrixSize(Weights, Count + 2, Frames);
 For H := 0 To HeadCount - 1 Do Begin
  { Normalisation par trame sur les tokens, puis mediane temporelle de largeur 7. }
  For J := 0 To Frames - 1 Do Begin
   Mean := 0; Variance := 0;
   For I := 0 To Count + 1 Do Mean := Mean + Heads[H].Data[I * Frames + J];
   Mean := Mean / (Count + 2);
   For I := 0 To Count + 1 Do Variance := Variance + Sqr(Heads[H].Data[I * Frames + J] -
   Mean);
   Scale := 1 / Sqrt(Variance / (Count + 2) + 1E-9);
   For I := 0 To Count + 1 Do Heads[H].Data[I * Frames + J] := (Heads[H].Data[I * Frames +
   J] - Mean) * Scale;
  End;
  For I := 0 To Count + 1 Do
  For J := 0 To Frames - 1 Do Begin
   For K := 0 To 6 Do Median[K] := Heads[H].Data[I * Frames + Max(0, MinInt(Frames - 1,
   J + K - 3))];
   For A := 1 To 6 Do Begin
    V := Median[A]; B := A - 1;
    While B >= 0 Do Begin
     If Median[B] <= V Then Break; Median[B + 1] := Median[B]; Dec(B);
    End;
    Median[B + 1] := V;
   End;
   Row := I * Frames + J; Weights.Data[Row] := Weights.Data[Row] + Median[3] / HeadCount;
  End;
  Heads[H].Data := Nil;
 End;
 DTWPath(Weights, Starts);
 For I := 0 To Count - 1 Do Begin
  Hints[I].Sample := MinInt(Samples, Starts[I + 1] * 320);
  Hints[I].EndSample := MinInt(Samples, Starts[I + 2] * 320);
  Hints[I].Probability := Exp(Winner.Scores[I].LogProbability);
  Hints[I].Aligned := True;
 End;
End;

Function DecodeChunk(Const Audio: TSamples; First, Last: Integer;Const M: TWhisperModel;
                     RequestedLanguage: Integer;Const Context: TTokens;
                     AudioContext: Integer; Const O: TOptions;Var Seed: LongInt;
                     Var Generated: TTokens; Var TimeHints: TTimeHints;
                     Var DetectedLanguage: Integer;Var LanguageProbability: Double;
                     Var Report: TDecodeReport): String;
Var
 Mel, Encoded, Logits: TMatrix;
 Cache: TDecoderCaches;
 Position, I, LanguageCount, Attempt: Integer;
 Peak, Sum, NoSpeechProbability, Energy, Temperature: Double;
 Winner: TDecodeCandidate;
 Retry: Boolean;
Begin
 Report.Confidence := 0; Report.SpecialPrefix := ''; Report.SpecialSuffix := '';
 Report.LogText := '';
 LanguageProbability := 0; Generated := Nil; TimeHints := Nil; DecodeChunk := '';
 DetectedLanguage := RequestedLanguage;
 Energy := 0;
 For I := First To Last - 1 Do Energy := Energy + Sqr(Audio[I]);
 If (Last <= First) Or (Energy / (Last - First) < 1E-12) Then Exit;
 WhisperMel(Audio, First, Last, M, AudioContext, Mel); EncodeWhisper(Mel, M, Encoded);
 Mel.Data := Nil; InitDecoderCache(Encoded, M, Cache); Encoded.Data := Nil;
 DecoderStep(M.SOT, 0, M, Cache, Logits);
 Peak := -1E30;
 For I := 0 To High(Logits.Data) Do If Logits.Data[I] > Peak Then Peak := Logits.Data[I];
 Sum := 0;
 For I := 0 To High(Logits.Data) Do Sum := Sum + Exp(Logits.Data[I] - Peak);
 NoSpeechProbability := Exp(Logits.Data[M.NoSpeech] - Peak) / Sum;
 If M.VocabCount > 51864 Then Begin
  LanguageCount := 99 + M.VocabCount - 51865;
  If DetectedLanguage < 0 Then Begin
   DetectedLanguage := 0;
   For I := 1 To LanguageCount - 1 Do    If Logits.Data[M.SOT + 1 + I] >
   Logits.Data[M.SOT + 1 + DetectedLanguage] Then DetectedLanguage := I;
  End;
  If DetectedLanguage >= LanguageCount Then Fail('Langue absente de ce modele Whisper.');
  Peak := -1E30;
  For I := 0 To LanguageCount - 1 Do   If Logits.Data[M.SOT + 1 + I] > Peak Then Peak :=
  Logits.Data[M.SOT + 1 + I];
  Sum := 0;
  For I := 0 To LanguageCount - 1 Do Sum := Sum + Exp(Logits.Data[M.SOT + 1 + I] - Peak);
  LanguageProbability := Exp(Logits.Data[M.SOT + 1 + DetectedLanguage] - Peak) / Sum;
 End Else DetectedLanguage := 0;
 If O.DetectLanguage Then Exit;
 Position := 0;
 If Length(Context) > 0 Then Begin
  DecoderStep(M.NoSpeech - 1, Position, M, Cache, Logits); Inc(Position);
  For I := 0 To High(Context) Do Begin
   DecoderStep(Context[I], Position, M, Cache, Logits); Inc(Position);
  End;
 End;
 DecoderStep(M.SOT, Position, M, Cache, Logits); Inc(Position);
 If M.VocabCount > 51864 Then Begin
  DecoderStep(M.SOT + 1 + DetectedLanguage, Position, M, Cache, Logits); Inc(Position);
  If O.Translate Then DecoderStep(M.Transcribe - 1, Position, M, Cache, Logits)
                 Else DecoderStep(M.Transcribe, Position, M, Cache, Logits);
  Inc(Position);
 End Else DetectedLanguage := 0;
 DecoderStep(M.NoTimestamps, Position, M, Cache, Logits); Inc(Position);
 Temperature := O.Temperature; Attempt := 0;
 Repeat
 Inc(Attempt);
 If Temperature = 0 Then Begin
  If O.BeamSize > 1 Then BeamDecode(Cache, Logits, Position, O.BeamSize, M, Winner)
                    Else SampleDecode(Cache, Logits, Position, 1, 0, M, Seed, Winner);
 End Else SampleDecode(Cache, Logits, Position, O.BestOf, Temperature, M, Seed, Winner);
 If O.LogScore And Not O.NoPrints Then Begin
  Report.LogText := Report.LogText + 'Score fenetre=' + IntToStr(First) +
  ' tentative=' + IntToStr(Attempt) + ' temperature=' + RealText(Temperature) +
  ' moyenne=' + RealText(CandidateScore(Winner)) + #10;
  For I := 0 To High(Winner.Scores) Do Report.LogText := Report.LogText +
  ' token=' + IntToStr(Winner.Scores[I].Token) + ' logp=' +
  RealText(Winner.Scores[I].LogProbability) + ' best_logp=' +
  RealText(Winner.Scores[I].BestLogProbability) + #10;
 End;
 If (NoSpeechProbability > O.NoSpeechThreshold) And (CandidateScore(Winner) <
 O.LogProbThreshold) Then Exit;
 Retry := Not Winner.Finished Or (CandidateScore(Winner) < O.LogProbThreshold) Or
 EntropyFailure(Winner.Tokens, O.EntropyThreshold);
 If Not Retry Or O.NoFallback Or (O.TemperatureInc <= 0) Or
 (Temperature >= 1) Or (Attempt >= 8) Then Break;
 Temperature := Temperature + O.TemperatureInc;
 If Temperature > 1 Then Temperature := 1;
 If Not O.NoPrints Then Diagnostic('Reprise du decodage: temperature=' + RealText(
 Temperature));
 Until False;
 If Not Winner.Finished Then Fail(
 'Limite du contexte Whisper atteinte sans fin de texte.');
 Report.Confidence := Exp(CandidateScore(Winner));
 If Length(Context) > 0 Then Report.SpecialPrefix := '<|startofprev|>';
 Report.SpecialPrefix := Report.SpecialPrefix + '<|startoftranscript|>';
 If M.VocabCount > 51864 Then Begin
  Report.SpecialPrefix := Report.SpecialPrefix + '<|' + LanguageCodes[DetectedLanguage] +
  '|>';
  If O.Translate Then Report.SpecialPrefix := Report.SpecialPrefix + '<|translate|>'
                 Else Report.SpecialPrefix := Report.SpecialPrefix + '<|transcribe|>';
 End;
 Report.SpecialPrefix := Report.SpecialPrefix + '<|notimestamps|>';
 Report.SpecialSuffix := '<|endoftext|>';
 Generated := Winner.Tokens; TimeHints := Winner.TimeHints;
 If Length(M.DTWHeads) > 0 Then AlignDTWTokens(M, Cache, Position, Last - First, Winner,
 TimeHints);
 For I := 0 To High(Generated) Do  If Not (M.TinyDiarize And (Generated[I] =
 M.Transcribe + 1)) Then   DecodeChunk := DecodeChunk + M.Vocab[Generated[I]];
End;
{ Les limites sont comptees en points de code UTF-8, jamais en octets.
  Les temps des sous-segments sont interpoles, pas des alignements acoustiques. }

Function UTF8Boundary(Const Text: String; Position: Integer): Boolean;Begin
 UTF8Boundary := True;
 If Position <= Length(Text) Then  UTF8Boundary := (Ord(Text[Position]) And $C0) <> $80;
End;

Procedure AddSegments(Var Job: TProcessorJob; Const Text: String;Const Tokens: TTokens;
                      Const TimeHints: TTimeHints; First, Last, Detected: Integer);
Var
 Ends, Turns: Array Of Boolean;
 Times: Array Of Integer;
 AnchorByte, AnchorTime, HintTime, K, FinalTime, PieceStart, PieceEnd, TokenStart,
 TokenEnd, T: Integer;
 P, Start, Stop, Limit, Count, I, N, Offset, Best, TotalChars, UsedChars: Integer;
 Piece: String;
Begin
 If Trim(Text) = '' Then Exit;
 SetLength(Ends, Length(Text) + 1); SetLength(Turns, Length(Text) + 1); Offset := 0;
 For I := 0 To High(Tokens) Do Begin
  Inc(Offset, Length(Job.Model^.Vocab[Tokens[I]]));
  If Offset <= Length(Text) Then Begin
   Ends[Offset] := True;
   If Job.Model^.TinyDiarize And (Tokens[I] = Job.Model^.Transcribe + 1)
   Then Turns[Offset] := True;
  End;
 End;
 { Reperes de debut de token, acceptes seulement s'ils sont probables,
   dans la fenetre et monotones. Interpolation entre reperes fiables. }
 SetLength(Times, Length(Text) + 1); AnchorByte := 0; AnchorTime := First;
 FinalTime := Last;
 If Length(TimeHints) > 0 Then Begin
  If TimeHints[0].Aligned And (TimeHints[0].Probability >= Job.Options^.WordThreshold)
  Then   AnchorTime := Max(First, MinInt(Last, First + TimeHints[0].Sample));
  K := High(TimeHints);
  If TimeHints[K].Aligned And (TimeHints[K].Probability >= Job.Options^.WordThreshold)
  Then   FinalTime := Max(AnchorTime, MinInt(Last, First + TimeHints[K].EndSample));
 End;
 Times[0] := AnchorTime; Offset := 0;
 For I := 0 To Length(Tokens) Do Begin
  HintTime := FinalTime;
  If I < Length(Tokens) Then Begin
   If I >= Length(TimeHints) Then Break;
   HintTime := First + TimeHints[I].Sample;
  End;
  If (I = Length(Tokens)) Or ((TimeHints[I].Probability >= Job.Options^.WordThreshold) And
  (HintTime > AnchorTime) And (HintTime < FinalTime) And
  UTF8Boundary(Text, Offset + 1)) Then Begin
   If Offset > AnchorByte Then Begin
    Count := 0;
    For K := AnchorByte + 1 To Offset Do If UTF8Boundary(Text, K) Then Inc(Count);
    N := 0;
    For K := AnchorByte + 1 To Offset Do Begin
     If UTF8Boundary(Text, K) Then Inc(N);
     If Count > 0 Then Times[K] := AnchorTime + Int64(HintTime - AnchorTime) *
     N Div Count;
    End;
    AnchorByte := Offset; AnchorTime := HintTime;
   End;
  End;
  If I < Length(Tokens) Then Inc(Offset, Length(Job.Model^.Vocab[Tokens[I]]));
 End;
 { Absence de reperes: la fin de la fenetre reste toujours connue. }
 Count := 0;
 For K := AnchorByte + 1 To Length(Text) Do If UTF8Boundary(Text, K) Then Inc(Count);
 N := 0;
 For K := AnchorByte + 1 To Length(Text) Do Begin
  If UTF8Boundary(Text, K) Then Inc(N);
  If Count > 0 Then Times[K] := AnchorTime + Int64(FinalTime - AnchorTime) * N Div Count;
 End;
 TotalChars := 0;
 For P := 1 To Length(Text) Do If UTF8Boundary(Text, P) Then Inc(TotalChars);
 Start := 1; UsedChars := 0;
 While Start <= Length(Text) Do Begin
  P := Start; Count := 0; Best := 0;
  Limit := Job.Options^.MaxLength;
  While P <= Length(Text) Do Begin
   If UTF8Boundary(Text, P) Then Begin
    If (Limit > 0) And (Count >= Limit) Then Break;
    Inc(Count);
   End;
   If UTF8Boundary(Text, P + 1) Then Begin
    If Job.Options^.SplitOnWord Then Begin
     If Text[P] In [' ', #9, #10, #13] Then Best := P;
     If P < Length(Text) Then      If Text[P + 1] In [' ', #9, #10, #13] Then Best := P;
    End Else If Ends[P] Then Best := P;
   End;
   Inc(P);
  End;
  Stop := P - 1;
  If (P <= Length(Text)) And (Best >= Start) Then Stop := Best;
  For K := Start To Stop Do If Turns[K] And UTF8Boundary(Text, K + 1) Then Begin
   Stop := K; Break;
  End;
  { Mot ou token plus long que la limite: couper entre caracteres. }
  Count := 0;
  For P := Start To Stop Do If UTF8Boundary(Text, P) Then Inc(Count);
  Piece := Trim(Copy(Text, Start, Stop - Start + 1));
  If Piece <> '' Then Begin
   N := Length(Job.Segments); SetLength(Job.Segments, N + 1);
   Job.Segments[N].First := Times[Start - 1];
   Job.Segments[N].Last := Times[Stop];
   Job.Segments[N].Text := Piece; Job.Segments[N].SpeakerTurnNext := Turns[Stop];
   PieceStart := Start;
   While Text[PieceStart] <= ' ' Do Inc(PieceStart);
   PieceEnd := Stop;
   While Text[PieceEnd] <= ' ' Do Dec(PieceEnd);
   Job.Segments[N].CharacterTimes := Copy(Times, PieceStart - 1, PieceEnd - PieceStart +
   2);
   TokenStart := 0;
   For T := 0 To High(Tokens) Do Begin
    TokenEnd := TokenStart + Length(Job.Model^.Vocab[Tokens[T]]);
    If (T < Length(TimeHints)) And (TokenEnd >= PieceStart) And (TokenStart < PieceEnd)
    Then     If TimeHints[T].Aligned Then Begin
     K := Length(Job.Segments[N].Tokens); SetLength(Job.Segments[N].Tokens, K + 1);
     Job.Segments[N].Tokens[K].ID := Tokens[T];
     Job.Segments[N].Tokens[K].First := First + TimeHints[T].Sample;
     Job.Segments[N].Tokens[K].Last := First + TimeHints[T].EndSample;
     Job.Segments[N].Tokens[K].Probability := TimeHints[T].Probability;
    End;
    TokenStart := TokenEnd;
   End;
   If Detected >= 0 Then Job.Segments[N].Language := LanguageCodes[Detected];
  End Else If Turns[Stop] And (Length(Job.Segments) > 0) Then   Job.Segments[High(
  Job.Segments)].SpeakerTurnNext := True;
  Inc(UsedChars, Count); Start := Stop + 1;
 End;
End;

Function ProcessorWorker(Parameter: Pointer): PtrInt;
Var
 Job: PProcessorJob;
 First, Last, I, Detected, Limit, AudioContext, SegmentStart: Integer;
 Text: String;
 History, Context, Generated: TTokens;
 TimeHints: TTimeHints;
 Seed: LongInt;
 LanguageProbability: Double;
 Report: TDecodeReport;
Begin
 Job := Parameter; First := Job^.First; Seed := 1 + First;
 If Job^.Options^.PrintProgress And Not Job^.Options^.NoPrints Then  Diagnostic(
 'Progression processeur ' + IntToStr(Job^.WorkerIndex) + ': 0%');
 AudioContext := Job^.Options^.AudioContext;
 If AudioContext = 0 Then AudioContext := Job^.Model^.AudioContext;
 Limit := MinInt(Job^.Options^.MaxContext, Job^.Model^.TextContext Div 2);
 Limit := MinInt(Limit, Job^.Model^.TextContext - 6);
 If Not Job^.Options^.CarryPrompt Then Begin
  History := Copy(Job^.InitialTokens, 0, Length(Job^.InitialTokens));
  KeepTail(History, Limit);
 End;
 While First < Job^.Last Do Begin
  Last := MinInt(First + AudioContext * 320, Job^.Last);
  BuildContext(Job^.InitialTokens, History, Job^.Options^.CarryPrompt, Limit, Context);
  Text := DecodeChunk(Job^.Audio^, First, Last, Job^.Model^, Job^.Language,
  Context, AudioContext, Job^.Options^, Seed, Generated, TimeHints, Detected,
  LanguageProbability, Report);
  Job^.LogText := Job^.LogText + Report.LogText;
  SegmentStart := Length(Job^.Segments);
  AddSegments(Job^, Text, Generated, TimeHints, First, Last, Detected);
  For I := SegmentStart To High(Job^.Segments) Do Job^.Segments[I].Confidence :=
  Report.Confidence;
  If Length(Job^.Segments) > SegmentStart Then Begin
   Job^.Segments[SegmentStart].SpecialPrefix := Report.SpecialPrefix;
   Job^.Segments[High(Job^.Segments)].SpecialSuffix := Report.SpecialSuffix;
  End;
  If Job^.Options^.PrintProgress And Not Job^.Options^.NoPrints Then   Diagnostic(
  'Progression processeur ' + IntToStr(Job^.WorkerIndex) + ': ' +
  IntToStr(Int64(Last - Job^.First) * 100 Div (Job^.Last - Job^.First)) + '%');
  For I := 0 To High(Generated) Do AppendToken(History, Generated[I]);
  KeepTail(History, Limit);
  First := Last;
 End;
 ProcessorWorker := 0;
End;

Function PadNumber(Value, Digits: Integer): String;Begin
 PadNumber := IntToStr(Value);
 While Length(PadNumber) < Digits Do PadNumber := '0' + PadNumber;
End;

Function TimeStamp(Samples: Integer): String;
Var
 MS: Integer;
Begin
 MS := Int64(Samples) * 1000 Div TargetRate;
 TimeStamp := PadNumber(MS Div 3600000, 2) + ':' + PadNumber((MS Div 60000) Mod 60, 2) +
 ':' +
 PadNumber((MS Div 1000) Mod 60, 2) + '.' + PadNumber(MS Mod 1000, 3);
End;

Function UTF8Path(Const Value: String): String;
Var
 U: UTF8String;
Begin
 U := UTF8String(Value); SetString(UTF8Path, PChar(U), Length(U));
End;

Function JSONString(Const Value: String): String;
Const
 Hex: String[16] = '0123456789abcdef';
Var
 I, C: Integer;
Begin
 JSONString := '"';
 For I := 1 To Length(Value) Do Begin
  C := Ord(Value[I]);
  If Value[I] In ['"', '\'] Then JSONString := JSONString + '\' + Value[I] Else
  If C < 32 Then JSONString := JSONString + '\u00' + Hex[C Div 16 + 1] +
  Hex[C Mod 16 + 1]
  Else JSONString := JSONString + Value[I];
 End;
 JSONString := JSONString + '"';
End;

Function CSVString(Const Value: String): String;
Var
 I: Integer;
Begin
 CSVString := '"';
 For I := 1 To Length(Value) Do Begin
  If Value[I] = '"' Then CSVString := CSVString + '"';
  CSVString := CSVString + Value[I];
 End;
 CSVString := CSVString + '"';
End;

Function FlatText(Const Value: String): String;
Var
 I: Integer;
Begin
 FlatText := Value;
 For I := 1 To Length(FlatText) Do If FlatText[I] < ' ' Then FlatText[I] := ' ';
End;

Function HTMLText(Const Value: String): String;
Var
 I: Integer;
Begin
 HTMLText := '';
 For I := 1 To Length(Value) Do Case Value[I] Of
 '&': HTMLText := HTMLText + '&amp;';
 '<': HTMLText := HTMLText + '&lt;';
 '>': HTMLText := HTMLText + '&gt;';
 '"': HTMLText := HTMLText + '&quot;';
 #39: HTMLText := HTMLText + '&#39;';
 #0..#31: HTMLText := HTMLText + ' ';
 Else HTMLText := HTMLText + Value[I];
End;
End;

Function FileURL(Const Name: String): String;
Const
 Hex: String[16] = '0123456789ABCDEF';
Var
 Path: String;
 I, C: Integer;
Begin
 Path := UTF8Path(FExpand(Name));
 For I := 1 To Length(Path) Do If Path[I] = '\' Then Path[I] := '/';
 If Copy(Path, 1, 2) = '//' Then FileURL := 'file:' Else
 If Copy(Path, 1, 1) = '/' Then FileURL := 'file://'
                           Else FileURL := 'file:///';
 For I := 1 To Length(Path) Do Begin
  C := Ord(Path[I]);
  If Path[I] In ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~', '/',
  ':'] Then   FileURL := FileURL + Path[I]
       Else FileURL := FileURL + '%' + Hex[C Div 16 + 1] + Hex[C Mod 16 + 1];
 End;
End;

Function Milliseconds(Sample: Integer): Int64;Begin
 Milliseconds := Int64(Sample) * 1000 Div TargetRate;
End;

Function SecondsText(Sample: Integer): String;
Var
 MS: Int64;
Begin
 MS := Milliseconds(Sample);
 SecondsText := IntToStr(MS Div 1000) + '.' + PadNumber(MS Mod 1000, 3);
End;

Function SRTTime(Sample: Integer): String;Begin
 SRTTime := TimeStamp(Sample); SRTTime[9] := ',';
End;

Procedure ExportWrite(Var Stream: TBinary; Const Value: String);
Var
 Count, Code: Integer;
Begin
 If Value = '' Then Exit;
 {$I-} BlockWrite(Stream.Handle, Value[1], Length(Value), Count); Code := IOResult; {$I+}
 If (Code <> 0) Or (Count <> Length(Value)) Then Fail('Ecriture incomplete: ' +
 Stream.Name);
End;

Procedure ExportLine(Var Stream: TBinary; Const Value: String);Begin
 ExportWrite(Stream, Value + #13#10);
End;

Procedure MakeWords(Const Segments: TSegments; Var Words: TSegments);
Var
 I, P, Start, Before, Count, Total, J, N: Integer;
Begin
 Words := Nil;
 For I := 0 To High(Segments) Do Begin
  Total := 0;
  For J := 1 To Length(Segments[I].Text) Do   If UTF8Boundary(Segments[I].Text, J)
  Then Inc(Total);
  P := 1; Count := 0;
  While P <= Length(Segments[I].Text) Do Begin
   While P <= Length(Segments[I].Text) Do Begin
    If Segments[I].Text[P] > ' ' Then Break;
    Inc(P); Inc(Count);
   End;
   Start := P; Before := Count;
   While P <= Length(Segments[I].Text) Do Begin
    If Segments[I].Text[P] <= ' ' Then Break;
    If UTF8Boundary(Segments[I].Text, P) Then Inc(Count);
    Inc(P);
   End;
   If P > Start Then Begin
    N := Length(Words); SetLength(Words, N + 1);
    Words[N].Text := Copy(Segments[I].Text, Start, P - Start);
    Words[N].Language := Segments[I].Language; Words[N].Speaker := Segments[I].Speaker;
    Words[N].SpeakerTurnNext := Segments[I].SpeakerTurnNext And (P > Length(
    Segments[I].Text));
    Words[N].First := Segments[I].First + Int64(Segments[I].Last - Segments[I].First) *
    Before Div Total;
    Words[N].Last := Segments[I].First + Int64(Segments[I].Last - Segments[I].First) *
    Count Div Total;
    If Length(Segments[I].CharacterTimes) = Length(Segments[I].Text) + 1 Then Begin
     Words[N].First := Segments[I].CharacterTimes[Start - 1];
     Words[N].Last := Segments[I].CharacterTimes[P - 1];
    End;
   End;
  End;
 End;
End;

Procedure WriteJSONSegments(Var Stream: TBinary; Const Segments: TSegments;
                            IndexOffset: Integer; IncludeLanguage: Boolean);
Var
 I, J: Integer;
Begin
 ExportLine(Stream, '[');
 For I := 0 To High(Segments) Do Begin
  If I > 0 Then ExportLine(Stream, ',');
  ExportWrite(Stream, '{"id":' + IntToStr(Int64(IndexOffset) + I) +
  ',"start":' + SecondsText(Segments[I].First) + ',"end":' + SecondsText(Segments[I].Last)
  +
  ',"text":' + JSONString(Segments[I].Text));
  If IncludeLanguage Then ExportWrite(Stream, ',"language":' + JSONString(
  Segments[I].Language));
  If IncludeLanguage And (Length(Segments[I].Tokens) > 0) Then Begin
   ExportWrite(Stream, ',"tokens":[');
   For J := 0 To High(Segments[I].Tokens) Do Begin
    If J > 0 Then ExportWrite(Stream, ',');
    ExportWrite(Stream, '{"id":' + IntToStr(Segments[I].Tokens[J].ID) +
    ',"start":' + SecondsText(Segments[I].Tokens[J].First) +
    ',"end":' + SecondsText(Segments[I].Tokens[J].Last) +
    ',"p":' + RealText(Segments[I].Tokens[J].Probability) + '}');
   End;
   ExportWrite(Stream, ']');
  End;
  If Segments[I].Speaker <> '' Then ExportWrite(Stream, ',"speaker":' + JSONString(
  Segments[I].Speaker));
  If Segments[I].SpeakerTurnNext Then ExportWrite(Stream, ',"speaker_turn_next":true');
  ExportWrite(Stream, '}');
 End;
 ExportLine(Stream, ']');
End;

Function DisplaySegment(Const Segment: TSegment): String;Begin
 DisplaySegment := Segment.Text;
 If Segment.Speaker <> '' Then DisplaySegment := '[speaker ' + Segment.Speaker + '] ' +
 DisplaySegment;
 If Segment.SpeakerTurnNext Then DisplaySegment := DisplaySegment + ' [SPEAKER_TURN]';
End;

Procedure ExportResults(Const InputName: String; Const O: TOptions; FileIndex: Integer;
                        Const Segments: TSegments);
Var
 Stream: TBinary;
 Format: TExportFormat;
 Words: TSegments;
 I, N: Integer;
 MS: Int64;
 Name, Text, Task: String;
 Attributes: Word;
Begin
 If O.OutputFormats = [] Then Exit;
 If (efWords In O.OutputFormats) Or O.FullJSON Then MakeWords(Segments, Words);
 Text := '';
 For I := 0 To High(Segments) Do Begin
  If I > 0 Then Text := Text + #10;
  Text := Text + Segments[I].Text;
 End;
 PendingExports := Nil;
 For Format := Low(TExportFormat) To High(TExportFormat)
 Do If Format In O.OutputFormats Then Begin
  Name := ExportBase(O, FileIndex) + ExportExtensions[Format];
  If PathAttributes(Name, Attributes) Then Fail('Sortie deja existante: ' + Name);
  OpenBinary(Stream, Name, True);
  N := Length(PendingExports); SetLength(PendingExports, N + 1);
  PendingExports[N] := Name;
  Case Format Of
  efTXT:
  For I := 0 To High(Segments) Do ExportLine(Stream, DisplaySegment(Segments[I]));
  efVTT, efSRT:
  Begin
   If Format = efVTT Then Begin
    ExportLine(Stream, 'WEBVTT'); ExportLine(Stream, '');
   End;
   For I := 0 To High(Segments) Do Begin
    ExportLine(Stream, IntToStr(Int64(O.OffsetIndex) + I + 1));
    If Format = efSRT Then ExportLine(Stream, SRTTime(Segments[I].First) + ' --> ' +
    SRTTime(Segments[I].Last))
    Else ExportLine(Stream, TimeStamp(Segments[I].First) + ' --> ' + TimeStamp(
    Segments[I].Last));
    ExportLine(Stream, HTMLText(DisplaySegment(Segments[I]))); ExportLine(Stream, '');
   End;
  End;
  efLRC:
  For I := 0 To High(Segments) Do Begin
   MS := Milliseconds(Segments[I].First);
   ExportLine(Stream, '[' + PadNumber(MS Div 60000, 2) + ':' +
   PadNumber((MS Div 1000) Mod 60, 2) + '.' + PadNumber((MS Mod 1000) Div 10, 2) + ']' +
   Trim(FlatText(DisplaySegment(Segments[I]))));
  End;
  efCSV:
  Begin
   ExportLine(Stream, 'id,start,end,text');
   For I := 0 To High(Segments) Do ExportLine(Stream,
   IntToStr(Int64(O.OffsetIndex) + I) + ',' + SecondsText(Segments[I].First) + ',' +
   SecondsText(Segments[I].Last) + ',' + CSVString(DisplaySegment(Segments[I])));
  End;
  efJSON:
  Begin
   ExportLine(Stream, '{"text":' + JSONString(Text) + ',"segments":');
   WriteJSONSegments(Stream, Segments, O.OffsetIndex, O.FullJSON);
   If O.FullJSON Then Begin
    If O.DTWModel <> '' Then ExportLine(Stream, ',"alignment":"dtw","dtw_model":' +
    JSONString(O.DTWModel));
    Task := 'transcribe'; If O.Translate Then Task := 'translate';
    ExportLine(Stream, ',"source":' + JSONString(UTF8Path(InputName)) +
    ',"model":' + JSONString(UTF8Path(O.Model)) + ',"task":' + JSONString(Task) +
    ',"language":' + JSONString(O.Language) + ',"sample_rate":16000,' +
    '"timestamps_estimated":true,"offset_ms":' + IntToStr(O.OffsetMS) +
    ',"duration_ms":' + IntToStr(O.DurationMS) + ',"words":');
    WriteJSONSegments(Stream, Words, 0, True);
   End;
   ExportLine(Stream, '}');
  End;
  efWords:
  Begin
   ExportLine(Stream, '{"format":"pascal-words-1","timestamps_estimated":true,"words":');
   WriteJSONSegments(Stream, Words, 0, True); ExportLine(Stream, '}');
  End;
  efHTML:
  Begin
   ExportLine(Stream, '<!doctype html><html lang="fr"><meta charset="utf-8">');
   ExportLine(Stream, '<title>Paroles synchronisees</title><style>');
   If O.FontPath <> '' Then     ExportLine(Stream,
   '@font-face{font-family:paroles;src:url("' + FileURL(O.FontPath) + '")}');
   ExportLine(Stream,
   'body{font-family:paroles,monospace;max-width:60em;margin:2em auto;padding:1em}' +
   '.active{background:#ffe68a}span{display:inline-block;padding:.2em}audio{width:100%}</style>');
   ExportLine(Stream, '<h1>Paroles synchronisees</h1><p>Horodatages estimes.</p>');
   ExportLine(Stream, '<audio id="audio" controls src="' + FileURL(InputName) +
   '"></audio><p>');
   For I := 0 To High(Words) Do ExportLine(Stream, '<span data-start="' + SecondsText(
   Words[I].First) +
   '" data-end="' + SecondsText(Words[I].Last) + '">' + HTMLText(DisplaySegment(Words[I]))
   + '</span>');
   ExportLine(Stream, '</p><script>const audio=document.getElementById("audio");' +
   'const words=document.querySelectorAll("span[data-start]");' +
   'audio.addEventListener("timeupdate",()=>{for(const w of words)' +
   'w.classList.toggle("active",audio.currentTime>=Number(w.dataset.start)' +
   '&&audio.currentTime<Number(w.dataset.end));});</script></html>');
  End;
 End;
 CloseBinary(Stream); Diagnostic('Sortie: ' + Name);
End;
PendingExports := Nil;
End;

Function StereoSpeaker(Const Left, Right: TSamples; First, Last: Integer): String;
Var
 I: Integer;
 L, R: Double;
Begin
 L := 0; R := 0;
 Last := MinInt(Last, MinInt(Length(Left), Length(Right)));
 For I := Max(0, First) To Last - 1 Do Begin
  L := L + Abs(Left[I]); R := R + Abs(Right[I]);
 End;
 StereoSpeaker := '?';
 If L > 1.1 * R Then StereoSpeaker := '0' Else
 If R > 1.1 * L Then StereoSpeaker := '1';
End;

Procedure TranscribeFile(Const Name: String; Const O: TOptions; Var M: TWhisperModel;
                         FileIndex: Integer);
Var
 Source, Audio, LeftSource, RightSource, LeftAudio, RightAudio: TSamples;
 Rate: LongWord;
 Workers, I, J, Language, FirstSample, LastSample, Selected: Integer;
 Boundary, SegmentIndex: Int64;
 Jobs: Array[0..7] Of TProcessorJob;
 Handles: Array[0..7] Of TThreadID;
 UTF8Text: UTF8String;
 InitialTokens, DetectedTokens: TTokens;
 Results: TSegments;
 ResultCount: Integer;
 Hints: TTimeHints;
 DetectedText: String;
 Probability: Double;
 Seed: LongInt;
 DetectContext: Integer;
 Report: TDecodeReport;
Begin
 Results := Nil;
 If O.AudioContext > M.AudioContext Then Fail(
 '--audio-ctx depasse le contexte du modele.');
 If (O.DetectLanguage Or O.Translate) And (M.VocabCount = 51864) Then  Fail(
 'Detection de langue et traduction exigent un modele Whisper multilingue.');
 If Not O.DetectLanguage Then TokenizePrompt(O.Prompt, M, InitialTokens);
 ReadWave(Name, Source, Rate, O.Diarize, LeftSource, RightSource);
 Resample(Source, Rate, Audio); Source := Nil;
 If O.Diarize Then Begin
  Resample(LeftSource, Rate, LeftAudio); LeftSource := Nil; RemoveDC(LeftAudio);
  Resample(RightSource, Rate, RightAudio); RightSource := Nil; RemoveDC(RightAudio);
 End;
 RemoveDC(Audio);
 Language := LanguageIndex(O.Language);
 If (M.VocabCount = 51864) And (Language > 0) Then Fail(
 'Le modele .en ne prend en charge que l''anglais.');
 If Language >= 99 + M.VocabCount - 51865 Then Fail(
 'Langue absente de ce modele Whisper.');
 { Calcul en 64 bits avant de borner aux echantillons disponibles. }
 Boundary := Int64(O.OffsetMS) * TargetRate Div 1000;
 If Boundary >= Length(Audio) Then Begin
  Diagnostic('Fichier: ' + Name + ' | aucune portion audio apres le decalage.');
  If Not O.DetectLanguage Then ExportResults(Name, O, FileIndex, Results);
  Exit;
 End;
 FirstSample := Boundary; LastSample := Length(Audio);
 If O.DurationMS > 0 Then Begin
  Boundary := Int64(FirstSample) + Int64(O.DurationMS) * TargetRate Div 1000;
  If Boundary < LastSample Then LastSample := Boundary;
 End;
 Selected := LastSample - FirstSample;
 If Selected <= 0 Then Exit;
 If O.DetectLanguage Then Begin
  DetectContext := O.AudioContext;
  If DetectContext = 0 Then DetectContext := M.AudioContext;
  Seed := 1;
  If O.PrintProgress And Not O.NoPrints Then Diagnostic('Progression detection: 0%');
  DetectedText := DecodeChunk(Audio, FirstSample,
  MinInt(LastSample, FirstSample + DetectContext * 320), M, -1,
  InitialTokens, DetectContext, O, Seed, DetectedTokens, Hints, Language, Probability,
  Report);
  If O.PrintProgress And Not O.NoPrints Then Diagnostic('Progression detection: 100%');
  Diagnostic('Detection de langue: ' + Name);
  If Language < 0 Then WriteLn('und (silence)')
                  Else WriteLn(LanguageCodes[Language], ' (probabilite=', Probability:0:6, ')');
  Exit;
 End;
 Workers := MinInt(O.Processors, Selected);
 If Not O.NoPrints Then WriteLn(StdErr, 'Fichier: ', Name, ' | ', O.Threads,
 ' thread(s) x ', Workers,
 ' processeur(s), langue=', O.Language, ', debut=', TimeStamp(FirstSample), ', duree=',
 TimeStamp(Selected));
 For I := 0 To Workers - 1 Do Begin
  Jobs[I].WorkerIndex := I + 1;
  Jobs[I].Options := @O; Jobs[I].InitialTokens := InitialTokens;
  Jobs[I].Model := @M; Jobs[I].Audio := @Audio; Jobs[I].Language := Language;
  Jobs[I].First := FirstSample + Int64(Selected) * I Div Workers;
  Jobs[I].Last := FirstSample + Int64(Selected) * (I + 1) Div Workers;
 End;
 For I := 1 To Workers - 1 Do Begin
  Handles[I] := BeginThread(@ProcessorWorker, @Jobs[I]);
  If Handles[I] = 0 Then Begin
   For J := 1 To I - 1 Do JoinThread(Handles[J]);
   Fail('Creation d''un processeur impossible; reduire --processors.');
  End;
 End;
 ProcessorWorker(@Jobs[0]);
 For I := 1 To Workers - 1 Do JoinThread(Handles[I]);
 For I := 0 To Workers - 1 Do If Jobs[I].LogText <> '' Then Diagnostic(Trim(
 Jobs[I].LogText));
 SegmentIndex := O.OffsetIndex;
 For I := 0 To Workers - 1 Do
 For J := 0 To High(Jobs[I].Segments) Do  If Jobs[I].Segments[J].Text <> '' Then Begin
   { Les tokens GGML contiennent des octets UTF-8, parfois des caracteres
     coupes entre tokens. Ne declarer l'encodage qu'apres leur assemblage. }
  ResultCount := Length(Results); SetLength(Results, ResultCount + 1);
  If O.Diarize Then Jobs[I].Segments[J].Speaker := StereoSpeaker(LeftAudio, RightAudio,
  Jobs[I].Segments[J].First, Jobs[I].Segments[J].Last);
  Results[ResultCount] := Jobs[I].Segments[J];
  SetString(UTF8Text, PChar(Jobs[I].Segments[J].Text), Length(Jobs[I].Segments[J].Text));
  If O.ShowIndex Then Write('[', SegmentIndex, '] ');
  Inc(SegmentIndex);
  If Not O.NoTimestamps Then Write('[', TimeStamp(Jobs[I].Segments[J].First), ' --> ',
  TimeStamp(Jobs[I].Segments[J].Last), '] ');
  If O.PrintConfidence Then Write('[confiance=', RealText(Jobs[I].Segments[J].Confidence),
  '] ');
  If O.PrintColors Then Begin
   If Jobs[I].Segments[J].Confidence >= 0.8 Then Write(#27'[32m') Else
   If Jobs[I].Segments[J].Confidence >= 0.5 Then Write(#27'[33m')
                                            Else Write(#27'[31m');
  End;
  If O.PrintSpecial Then Write(Jobs[I].Segments[J].SpecialPrefix);
  If Jobs[I].Segments[J].Speaker <> '' Then Write('[speaker ',
  Jobs[I].Segments[J].Speaker, '] ');
  Write(UTF8Text);
  If Jobs[I].Segments[J].SpeakerTurnNext Then Write(' [SPEAKER_TURN]');
  If O.PrintSpecial Then Write(Jobs[I].Segments[J].SpecialSuffix);
  If O.PrintColors Then Write(#27'[0m');
  WriteLn;
 End;
 ExportResults(Name, O, FileIndex, Results);
End;

Var
 Options: TOptions;
 Model: TWhisperModel;
 FileIndex: Integer;

BEGIN
 SetTextCodePage(Output, 65001);
 ParseOptions(Options); ThreadCount := Options.Threads; SilentConsole := Options.NoPrints;
 InitCriticalSection(ConsoleLock); ConsoleReady := True;
 LoadWhisper(Options.Model, Model);
 ConfigureDTW(Options.DTWModel, Model);
 ConfigureSuppression(Model, Options.SuppressNST, Options.HasSuppressRegex,
 Options.SuppressRegex);
 Model.TinyDiarize := Options.TinyDiarize;
 If Model.TinyDiarize Then Model.Vocab[Model.Transcribe + 1] := '';
 For FileIndex := 0 To High(Options.Files) Do TranscribeFile(Options.Files[FileIndex],
 Options, Model, FileIndex);
 ConsoleReady := False; DoneCriticalSection(ConsoleLock);
END.
