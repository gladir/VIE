{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @version: 1.00
  @website(https://www.gladir.com/office-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal
  @description: Clone de l'application TMF (Time Motion Transfer)

  Remplacement de visage en direct a partir d'une photographie, avec une
  webcam, a la maniere du projet libre Deep-Live-Cam :
   - Choix du visage source (photo BMP, PPM, JPEG ou PNG) et d'une cible
     (image ou camera), apercu, mode direct (Live), enregistrement
   - Options : masque de la bouche, garder les FPS, garder les images,
     amelioration du visage, cartographie des visages, plusieurs visages
   - Camera : DirectShow (Windows) ou Video4Linux2 (Linux),
     directement, sans unite ni bibliotheque externe ; sous DOS une mire
     de test animee remplace la camera
   - Menus deroulants, boutons, interrupteurs, fenetres de dialogue
   - Langue : francais par defaut, LANGUAGE=EN (anglais), LANGUAGE=GR
     (allemand), LANGUAGE=SP (espagnol) ou LANGUAGE=IT (italien)

  Important : Deep-Live-Cam repose sur des reseaux de neurones (InsightFace,
  GFPGAN) qui ne peuvent pas etre integres dans un seul fichier Pascal. TMF
  utilise donc des techniques classiques : cascade de Haar (OpenCV, sous FPC)
  ou couleur de peau (YCbCr),
  reperes des yeux et de la bouche, alignement geometrique, transfert de
  couleur et fusion adoucie. Le resultat est une approximation, pas un
  rendu neuronal. N'utilisez que des visages dont vous avez l'autorisation.

  Tout le code est contenu dans ce seul fichier (aucun $I, aucune unite
  externe autre que DOS, Crt et le module graphique).
}

Program TMF;

{$IFDEF FPC}
 {$Q-}
 {$R-}
 {$NOTES OFF}
 {$HINTS OFF}
 {$WARNINGS OFF}
{$ELSE}
 {$R-,Q-,S-}
 {$M 32768,0,655360}
{$ENDIF}

Uses {$IFDEF FPC}
      DOS,Crt,PtcGraph,PtcCrt,PtcMouse
     {$ELSE}
      DOS,Crt,Graph
     {$ENDIF};

Const
 VERSION_STR = '1.00';

 { Taille de la trame de travail (la camera et la cible y sont ramenees).
   Sous Free Pascal ces valeurs sont des variables (voir SetFrameSize) :
   320 x 240 sur un ecran 640 x 480, 640 x 480 sur un grand ecran
   (-maxscreen). Sous Turbo Pascal, ce sont des constantes. }
 {$IFNDEF FPC}
 FW = 160;
 FH = 120;
 T_IPD = 32;           { ecart entre les yeux dans le gabarit }
 T_CX = T_IPD * 7 Div 4;   { milieu des yeux dans le gabarit }
 T_CY = T_IPD * 3 Div 2;
 T_W = T_IPD * 7 Div 2;
 T_H = T_IPD * 4;
 PREV_W = 320;         { zone d'apercu a l'ecran }
 PREV_H = 240;
 PANEL_X = 336;
 UI_W = 640;
 UI_H = 480;
 CamReqW = 640;        { definition demandee a la camera }
 CamReqH = 480;
 {$ENDIF}
 AMAX = 160;            { cote maximal de la grille de detection }

 { Disposition de l'ecran }
 PREV_X = 8;
 PREV_Y = 28;
 MENU_H = 20;
 STATUS_H = 18;

 MAX_FACES = 4;
 N_SLOTS = 4;
 MAX_CAMS = 10;
 MAX_WID = 40;
 LOG_N = 4;

 { Commandes }
 CM_NONE = 0;
 CM_SELFACE = 1;
 CM_SELTARGET = 2;
 CM_SAVE = 3;
 CM_CAPTURE = 4;
 CM_QUIT = 5;
 CM_ADJUST = 6;
 CM_AUTODET = 7;
 CM_SWAPST = 8;
 CM_CLEARFACE = 9;
 CM_SLOT1 = 10;       { 10..13 }
 CM_START = 14;
 CM_PREVIEW = 15;
 CM_LIVE = 16;
 CM_STOP = 17;
 CM_MOUTH = 18;
 CM_KEEPFPS = 19;
 CM_KEEPFR = 20;
 CM_ENHANCE = 21;
 CM_MAPF = 22;
 CM_MANY = 23;
 CM_CAMSEL = 24;
 CM_MIRROR = 25;
 CM_SKIN = 26;
 CM_MARKS = 27;
 CM_SHOWFPS = 28;
 CM_FAST = 29;
 CM_HELP = 30;
 CM_ABOUT = 31;
 CM_ETHICS = 32;
 CM_DESTROY = 33;

 { Menus }
 MN_FILE = 0;
 MN_FACE = 1;
 MN_PROC = 2;
 MN_CAM = 3;
 MN_VIEW = 4;
 MN_HELP = 5;
 MN_COUNT = 6;

 { Types de sources video }
 SRC_SYNTH = 0;
 SRC_VFW = 1;
 SRC_V4L2 = 2;
 SRC_DSHOW = 3;

Type
 {$IFDEF FPC}
 TByteArr = Array[0..134217727] Of Byte;
 {$ELSE}
 TByteArr = Array[0..65519] Of Byte;
 {$ENDIF}
 PByteArr = ^TByteArr;

 { Image RVB (3 octets par pixel) avec plan alpha facultatif }
 TImg = Record
  W, H: LongInt;
  D: PByteArr;
  A: PByteArr;
 End;

 { Visage : cadre de la tete et reperes }
 TFace = Record
  Ok: Boolean;
  X1, Y1, X2, Y2: LongInt;
  ELx, ELy, ERx, ERy, Mx, My: Real;
  Area: LongInt;
 End;
 TFaceList = Array[0..MAX_FACES - 1] Of TFace;

 { Visage source }
 TSlot = Record
  Ok: Boolean;
  Name: String[60];
  Photo: TImg;
  Face: TFace;
  Tpl: TImg;
  Tpl2: TImg;
  VmT: Real;
  Thumb: TImg;
 End;

 TMenuItem = Record
  Caption: String[40];
  Shortcut: String[12];
  Cmd: Integer;
  Separator: Boolean;
 End;
 TMenu = Record
  Title: String[16];
  Items: Array[0..13] Of TMenuItem;
  ItemCount: Integer;
  X, Width: Integer;
 End;

 TWid = Record
  X1, Y1, X2, Y2: Integer;
  Cmd: Integer;
 End;

 TCamInfo = Record
  Name: String[44];
  Kind: Integer;
  Idx: Integer;
 End;

 {$IFDEF FPC}
 TShadowEl = LongInt;
 {$ELSE}
 TShadowEl = Integer;
 {$ENDIF}
 {$IFDEF FPC}
 TShadowArr = Array[0..16777215] Of TShadowEl;
 {$ELSE}
 TShadowArr = Array[0..FW * FH - 1] Of TShadowEl;
 {$ENDIF}
 PShadowArr = ^TShadowArr;

{$IFDEF FPC}
Var
 FW, FH: LongInt;                    { trame de travail }
 PREV_W, PREV_H: LongInt;            { zone d'apercu }
 PANEL_X, UI_W, UI_H: LongInt;       { disposition de l'interface }
 T_IPD, T_CX, T_CY, T_W, T_H: LongInt;  { gabarit du visage source }
 CamReqW, CamReqH: LongInt;          { definition demandee a la camera }
{$ENDIF}

Var
 Lang: Integer;               { 0=FR 1=EN 2=DE 3=ES 4=IT }
 TrueMode: Boolean;
 OptMaxColors, OptMaxScreen: Boolean;   { options de ligne de commande }
 Pal256: Boolean;                       { palette indexee de 256 couleurs }
 ScrOX, ScrOY: Integer;                 { decalage de l'interface 640 x 480 }
 UiRgbTab: Array[0..15] Of LongInt;
 MX_, MY_, MB_, OMX, OMY, OMB: LongInt;

 { Menus }
 Menus: Array[0..MN_COUNT - 1] Of TMenu;
 MenuActive: Boolean;
 ActiveMenu, ActiveItem: Integer;
 UnderBuf: Pointer;
 UnderSize: LongInt;
 UnderX, UnderY: Integer;
 UnderValid: Boolean;

 { Widgets de la fenetre principale }
 Wids: Array[0..MAX_WID - 1] Of TWid;
 NWids: Integer;

 { Etat de l'application }
 Slots: Array[1..N_SLOTS] Of TSlot;
 CurSlot: Integer;
 TargetImg: TImg;             { cible : image fixe }
 TargetOk: Boolean;
 TargetName: String;
 Cur: TImg;                   { trame courante (camera ou cible) }
 Res: TImg;                   { resultat affiche }
 TargetThumb: TImg;
 PreviewHasImage: Boolean;
 Shadow: PShadowArr;
 ShadowOk: Boolean;
 Running, Live, Quit_: Boolean;
 PreviewMode: Boolean;
 OptMouth, OptKeepFps, OptKeepFrames, OptEnhance, OptMap, OptMany: Boolean;
 OptMirror, OptMarks, OptShowFps, OptFast: Boolean;
 OptNoGpu: Boolean;                     { -nogpu : pas de Direct3D }
 FaceCount: Integer;
 Faces: TFaceList;
 SrcDetected: Boolean;
 Fps: Real;
 FrameNo, SavedFrames: LongInt;
 LogTxt: Array[0..LOG_N - 1] Of String[80];
 StatusMsg: String;
 LastDir: String;

 { Camera }
 Cams: Array[0..MAX_CAMS - 1] Of TCamInfo;
 NCams, CurCam: Integer;
 CamOpened: Boolean;
 CamKind: Integer;

{ ---------------------------------------------------------------------- }
{ Squelette : graphique et souris                                         }
{ ---------------------------------------------------------------------- }

Const
 ScrVga: Array[0..15, 0..2] Of Byte = (
  (0,0,0), (0,0,170), (0,170,0), (0,170,170),
  (170,0,0), (170,0,170), (170,85,0), (170,170,170),
  (85,85,85), (85,85,255), (85,255,85), (85,255,255),
  (255,85,85), (255,85,255), (255,255,85), (255,255,255));

{$IFDEF FPC}
{ En couleurs directes, les indices 0..15 de l'interface sont traduits
  en RVB ; les autres valeurs sont deja des couleurs RVB. }
Function MapC(C: LongInt): LongInt;
Begin
 If TrueMode And (C >= 0) And (C <= 15) Then MapC := UiRgbTab[C]
                                         Else MapC := C;
End;

Procedure SetColor(C: LongInt);
Begin
 PtcGraph.SetColor(MapC(C));
End;

Procedure SetFillStyle(Pat: Word; C: LongInt);
Begin
 PtcGraph.SetFillStyle(Pat, MapC(C));
End;

Procedure PutPixel(X, Y: Integer; C: LongInt);
Begin
 PtcGraph.PutPixel(X, Y, MapC(C));
End;
{$ENDIF}

{ Pixel de la video : la valeur est un indice (16 couleurs) ou un RVB }
Procedure RawPixel(X, Y: Integer; C: LongInt);
Begin
 {$IFDEF FPC}
 PtcGraph.PutPixel(X, Y, C);
 {$ELSE}
 PutPixel(X, Y, C);
 {$ENDIF}
End;

{ Choix du mode : par defaut 640 x 480 en 16 couleurs. Avec -maxcolors,
  les couleurs vraies (24 bits) ; avec -maxscreen, la definition maximale.
  Si le mode demande est impossible, on revient au 640 x 480 x 16. }
Procedure InitializeGraphics;
Var
 Driver, Mode: Integer;
 ErrCode: Integer;
 {$IFDEF FPC}
 M, Best: PModeInfo;
 BestArea, Area: LongInt;
 Done: Boolean;
 Lo, Hi: Integer;
 {$ENDIF}
Begin
 {$IFDEF FPC}
  Done := False;
  If OptMaxColors Then Begin
   { couleurs vraies : la plus petite definition d'au moins 640 x 480,
     ou la plus grande avec -maxscreen }
   M := QueryAdapterInfo;
   Best := Nil;
   BestArea := 0;
   While M <> Nil Do Begin
    If M^.DirectColor And (M^.MaxColor >= 16777216) And
       (M^.MaxX + 1 >= 640) And (M^.MaxY + 1 >= 480) Then Begin
     Area := LongInt(M^.MaxX + 1) * (M^.MaxY + 1);
     If OptMaxScreen Then Begin
      If (Best = Nil) Or (Area > BestArea) Then Begin
       Best := M;
       BestArea := Area;
      End;
     End
     Else If (Best = Nil) Or (Area < BestArea) Then Begin
      Best := M;
      BestArea := Area;
     End;
    End;
    M := M^.Next;
   End;
   If Best <> Nil Then Begin
    Driver := Best^.DriverNumber;
    Mode := Best^.ModeNumber;
    InitGraph(Driver, Mode, '');
    If GraphResult = grOk Then Done := True;
   End;
  End;
  If (Not Done) And OptMaxScreen Then Begin
   { definition maximale en 256 couleurs }
   Driver := D8bit;
   GetModeRange(Driver, Lo, Hi);
   If Hi >= Lo Then Begin
    Mode := Hi;
    InitGraph(Driver, Mode, '');
    If GraphResult = grOk Then Begin
     If (GetMaxX + 1 >= 640) And (GetMaxY + 1 >= 480) Then Done := True
                                                      Else CloseGraph;
    End;
   End;
  End;
  If Not Done Then Begin
   Driver := VGA;
   Mode := VGAHi;
   InitGraph(Driver, Mode, '');
  End;
 {$ELSE}
  Driver := Detect;
  Mode := VGAHi;
  InitGraph(Driver, Mode, '');
 {$ENDIF}
 ErrCode := GraphResult;
 If ErrCode = grOk Then Begin
  SetColor(White);
  SetLineStyle(0, 0, 1);
 End
  Else
 Begin
  WriteLn('Erreur graphique : ', GraphErrorMsg(ErrCode));
  Halt;
 End;
End;

{ Les seize couleurs de l'interface restent identiques dans le mode 256
  couleurs ; les indices 16..231 forment un cube 6 x 6 x 6 pour la video. }
{ Choisit la definition de la trame de travail et de l'apercu selon la
  taille de l'ecran : plus l'ecran est grand, plus l'image de la camera est
  definie (640 x 480 au lieu de 320 x 240). }
Procedure SetFrameSize;
Begin
 {$IFDEF FPC}
 FW := 320;
 FH := 240;
 T_IPD := 64;
 If (GetMaxX + 1 >= 960) And (GetMaxY + 1 >= 704) Then Begin
  FW := 640;
  FH := 480;
  T_IPD := 128;
 End;
 T_CX := T_IPD * 7 Div 4;
 T_CY := T_IPD * 3 Div 2;
 T_W := T_IPD * 7 Div 2;
 T_H := T_IPD * 4;
 PREV_W := FW;
 PREV_H := FH;
 PANEL_X := PREV_X + PREV_W + 8;
 UI_W := PANEL_X + 304;
 UI_H := PREV_Y + PREV_H + 196;
 If UI_H < 480 Then UI_H := 480;
 CamReqW := 640;
 CamReqH := 480;
 If FW > CamReqW Then CamReqW := FW;
 If FH > CamReqH Then CamReqH := FH;
 {$ENDIF}
End;

Procedure InitializeScreenPalette;
Var
 I: Integer;
Begin
 TrueMode := False;
 Pal256 := False;
 For I := 0 To 15 Do
  UiRgbTab[I] := (LongInt(ScrVga[I, 0]) Shl 16) Or
                 (LongInt(ScrVga[I, 1]) Shl 8) Or ScrVga[I, 2];
 {$IFDEF FPC}
 If GetMaxColor > 255 Then TrueMode := True
 Else If GetMaxColor > 15 Then Begin
  For I := 0 To 15 Do
   SetRGBPalette(I, ScrVga[I, 0], ScrVga[I, 1], ScrVga[I, 2]);
  If GetMaxColor >= 255 Then Begin
   For I := 16 To 231 Do
    SetRGBPalette(I, ((I - 16) Div 36) * 51, (((I - 16) Div 6) Mod 6) * 51,
                  ((I - 16) Mod 6) * 51);
   Pal256 := True;
  End;
 End;
 {$ENDIF}
 { l'interface 640 x 480 est centree sur les ecrans plus grands }
 ScrOX := 0;
 ScrOY := 0;
 If GetMaxX + 1 > UI_W Then ScrOX := (GetMaxX + 1 - UI_W) Div 2;
 If GetMaxY + 1 > UI_H Then ScrOY := (GetMaxY + 1 - UI_H) Div 2;
End;

{$IFNDEF FPC}
 Function MouseDriverFound: Boolean;
 Var
  Regs: Registers;
 Begin
  Regs.AX := 0;
  Intr($33, Regs);
  MouseDriverFound := Regs.AX = $FFFF;
 End;

 Procedure ShowMouse;
 Var
  Regs: Registers;
 Begin
  Regs.AX := $0001;
  Intr($33, Regs);
 End;

 Procedure HideMouse;
 Var
  Regs: Registers;
 Begin
  Regs.AX := $0002;
  Intr($33, Regs);
 End;

 Procedure GetMouseState(Var X, Y, Button: LongInt);
 Var
  Regs: Registers;
 Begin
  Regs.AX := $0003;
  Intr($33, Regs);
  Button := Regs.BX;
  X := Regs.CX;
  Y := Regs.DX;
 End;
{$ELSE}
 Function MouseDriverFound: Boolean;
 Begin
  MouseDriverFound := True;
 End;

 Procedure ShowMouse;
 Begin
  { Pas d'implementation pour Free Pascal }
 End;

 Procedure HideMouse;
 Begin
  { Pas d'implementation pour Free Pascal }
 End;
{$ENDIF}

{ ---------------------------------------------------------------------- }
{ Utilitaires                                                              }
{ ---------------------------------------------------------------------- }

Function IMin(A, B: LongInt): LongInt;
Begin
 If A < B Then IMin := A Else IMin := B;
End;

Function IMax(A, B: LongInt): LongInt;
Begin
 If A > B Then IMax := A Else IMax := B;
End;

Function IAbs(A: LongInt): LongInt;
Begin
 If A < 0 Then IAbs := -A Else IAbs := A;
End;

Function Clip8(V: LongInt): LongInt;
Begin
 If V < 0 Then Clip8 := 0
 Else If V > 255 Then Clip8 := 255
 Else Clip8 := V;
End;

Function ClipL(V, Lo, Hi: LongInt): LongInt;
Begin
 If V < Lo Then ClipL := Lo
 Else If V > Hi Then ClipL := Hi
 Else ClipL := V;
End;

Function RMin(A, B: Real): Real;
Begin
 If A < B Then RMin := A Else RMin := B;
End;

Function RMax(A, B: Real): Real;
Begin
 If A > B Then RMax := A Else RMax := B;
End;

Function RClip(V, Lo, Hi: Real): Real;
Begin
 If V < Lo Then RClip := Lo
 Else If V > Hi Then RClip := Hi
 Else RClip := V;
End;

Function RoundL(V: Real): LongInt;
Begin
 If V > 2000000000.0 Then V := 2000000000.0;
 If V < -2000000000.0 Then V := -2000000000.0;
 RoundL := Round(V);
End;

Function IStr(N: LongInt): String;
Var
 S: String;
Begin
 Str(N, S);
 IStr := S;
End;

Function Pad2(N: LongInt): String;
Begin
 If N < 10 Then Pad2 := '0' + IStr(N) Else Pad2 := IStr(N);
End;

Function PadN(N, Len: LongInt): String;
Var
 S: String;
Begin
 S := IStr(N);
 While Length(S) < Len Do S := '0' + S;
 PadN := S;
End;

Function UpStr(S: String): String;
Var
 I: Integer;
Begin
 For I := 1 To Length(S) Do
  If (S[I] >= 'a') And (S[I] <= 'z') Then S[I] := Chr(Ord(S[I]) - 32);
 UpStr := S;
End;

Function ExtOf(Const Name: String): String;
Var
 I: Integer;
Begin
 I := Length(Name);
 While (I > 0) And (Name[I] <> '.') And (Name[I] <> '\') And
       (Name[I] <> '/') Do Dec(I);
 If (I > 0) And (Name[I] = '.') Then ExtOf := UpStr(Copy(Name, I, 255))
                                Else ExtOf := '';
End;

Function BaseName(Const Name: String): String;
Var
 I: Integer;
Begin
 I := Length(Name);
 While (I > 0) And (Name[I] <> '\') And (Name[I] <> '/') Do Dec(I);
 BaseName := Copy(Name, I + 1, 255);
End;

Function PathSep: Char;
Begin
 {$IFDEF UNIX}
 PathSep := '/';
 {$ELSE}
 PathSep := '\';
 {$ENDIF}
End;

Function FileExists_(Const Name: String): Boolean;
Var
 F: File;
 Old: Byte;
Begin
 Old := FileMode;
 FileMode := 0;
 {$I-}
 Assign(F, Name);
 Reset(F, 1);
 {$I+}
 FileMode := Old;
 If IOResult = 0 Then Begin
  Close(F);
  FileExists_ := True;
 End
  Else
 FileExists_ := False;
End;

{ Millisecondes depuis minuit }
Function NowMs: LongInt;
Var
 H, M, S, S100: Word;
Begin
 GetTime(H, M, S, S100);
 NowMs := ((LongInt(H) * 60 + M) * 60 + S) * 1000 + S100 * 10;
End;

Function ElapsedMs(T0: LongInt): LongInt;
Var
 D: LongInt;
Begin
 D := NowMs - T0;
 If D < 0 Then D := D + 86400000;
 ElapsedMs := D;
End;

{ ---------------------------------------------------------------------- }
{ Texte : UTF-8 (source) -> CP437 (police 8x8)                            }
{ ---------------------------------------------------------------------- }

Function Win2Glyph(C: Integer): Integer;
Begin
 Win2Glyph := C;
 If C < 128 Then Exit;
 Case C Of
  199: Win2Glyph := 128; 252: Win2Glyph := 129; 233: Win2Glyph := 130;
  226: Win2Glyph := 131; 228: Win2Glyph := 132; 224: Win2Glyph := 133;
  229: Win2Glyph := 134; 231: Win2Glyph := 135; 234: Win2Glyph := 136;
  235: Win2Glyph := 137; 232: Win2Glyph := 138; 239: Win2Glyph := 139;
  238: Win2Glyph := 140; 236: Win2Glyph := 141; 196: Win2Glyph := 142;
  197: Win2Glyph := 143; 201: Win2Glyph := 144; 230: Win2Glyph := 145;
  198: Win2Glyph := 146; 244: Win2Glyph := 147; 246: Win2Glyph := 148;
  242: Win2Glyph := 149; 251: Win2Glyph := 150; 249: Win2Glyph := 151;
  255: Win2Glyph := 152; 214: Win2Glyph := 153; 220: Win2Glyph := 154;
  225: Win2Glyph := 160; 237: Win2Glyph := 161; 243: Win2Glyph := 162;
  250: Win2Glyph := 163; 241: Win2Glyph := 164; 209: Win2Glyph := 165;
  191: Win2Glyph := 168; 161: Win2Glyph := 173; 171: Win2Glyph := 174;
  187: Win2Glyph := 175; 223: Win2Glyph := 225; 176: Win2Glyph := 248;
  192, 193, 194, 195: Win2Glyph := Ord('A');
  200, 202, 203: Win2Glyph := Ord('E');
  204, 205, 206, 207: Win2Glyph := Ord('I');
  210, 211, 212, 213: Win2Glyph := Ord('O');
  217, 218, 219: Win2Glyph := Ord('U');
 Else
  Win2Glyph := Ord('?');
 End;
End;

Function U2C(Const S: String): String;
Var
 I: Integer;
 R: String;
 C: Integer;
Begin
 R := '';
 I := 1;
 While I <= Length(S) Do Begin
  C := Ord(S[I]);
  If (C = $C3) And (I < Length(S)) Then Begin
   R := R + Chr(Win2Glyph(Ord(S[I + 1]) + 64));
   Inc(I, 2);
  End
  Else If (C = $C2) And (I < Length(S)) Then Begin
   R := R + Chr(Win2Glyph(Ord(S[I + 1])));
   Inc(I, 2);
  End
  Else Begin
   R := R + S[I];
   Inc(I);
  End;
 End;
 U2C := R;
End;

Function TW(Const S: String): Integer;
Begin
 TW := Length(U2C(S)) * 8;
End;

Procedure DS(X, Y: Integer; Const S: String);
Begin
 OutTextXY(X, Y, U2C(S));
End;

Procedure DSC(X, Y, W: Integer; Const S: String);
Begin
 DS(X + (W - TW(S)) Div 2, Y, S);
End;

{ ---------------------------------------------------------------------- }
{ Langue : francais par defaut, LANGUAGE=EN / GR / SP / IT                 }
{ ---------------------------------------------------------------------- }

Procedure DetectLanguage;
Var
 S: String;
Begin
 S := UpStr(GetEnv('LANGUAGE'));
 Lang := 0;
 If Copy(S, 1, 2) = 'EN' Then Lang := 1
 Else If (Copy(S, 1, 2) = 'GR') Or (Copy(S, 1, 2) = 'DE') Then Lang := 2
 Else If (Copy(S, 1, 2) = 'SP') Or (Copy(S, 1, 2) = 'ES') Then Lang := 3
 Else If Copy(S, 1, 2) = 'IT' Then Lang := 4;
End;

{ Choisit la chaine selon la langue : francais, anglais, allemand,
  espagnol, italien }
Function L5(Const F, E, D, S, I: String): String;
Begin
 Case Lang Of
  1: L5 := E;
  2: L5 := D;
  3: L5 := S;
  4: L5 := I;
 Else L5 := F;
 End;
End;

Procedure LogAdd(Const S: String);
Var
 I: Integer;
Begin
 For I := 0 To LOG_N - 2 Do LogTxt[I] := LogTxt[I + 1];
 LogTxt[LOG_N - 1] := Copy(S, 1, 80);
End;

Procedure SetStatus(Const S: String);
Begin
 StatusMsg := S;
End;

{ ---------------------------------------------------------------------- }
{ Images : memoire, lecture BMP / PPM, ecriture BMP                        }
{ ---------------------------------------------------------------------- }

Const
 {$IFDEF FPC}
 LOAD_MAX_PIX = 1000000;
 {$ELSE}
 LOAD_MAX_PIX = 20000;
 {$ENDIF}

Type
 {$IFDEF FPC}
 TLongArr = Array[0..16777215] Of LongInt;
 {$ELSE}
 TLongArr = Array[0..8191] Of LongInt;
 {$ENDIF}
 PLongArr = ^TLongArr;

Var
 SkW, SkH, SkStep, SkOW, SkOH, SkCnt: LongInt;
 SkImg: TImg;
 SkAcc: PLongArr;

Function MemAlloc(Size: LongInt): Pointer;
Var
 P: Pointer;
Begin
 P := Nil;
 If Size > 0 Then Begin
  {$IFDEF FPC}
  GetMem(P, Size);
  {$ELSE}
  If (Size <= 65520) And (MaxAvail >= Size) Then GetMem(P, Size);
  {$ENDIF}
 End;
 MemAlloc := P;
End;

Procedure ImgFree(Var I: TImg);
Begin
 If I.D <> Nil Then FreeMem(I.D, I.W * I.H * 3);
 If I.A <> Nil Then FreeMem(I.A, I.W * I.H);
 I.D := Nil;
 I.A := Nil;
 I.W := 0;
 I.H := 0;
End;

Function ImgNew(Var I: TImg; W, H: LongInt; WithAlpha: Boolean): Boolean;
Begin
 I.W := 0;
 I.H := 0;
 I.D := Nil;
 I.A := Nil;
 ImgNew := False;
 If (W < 1) Or (H < 1) Then Exit;
 I.D := MemAlloc(W * H * 3);
 If I.D = Nil Then Exit;
 If WithAlpha Then Begin
  I.A := MemAlloc(W * H);
  If I.A = Nil Then Begin
   FreeMem(I.D, W * H * 3);
   I.D := Nil;
   Exit;
  End;
  FillChar(I.A^, W * H, 0);
 End;
 I.W := W;
 I.H := H;
 FillChar(I.D^, W * H * 3, 0);
 ImgNew := True;
End;

Procedure ImgCopy(Var Src, Dst: TImg);
Begin
 If (Src.D = Nil) Or (Dst.D = Nil) Then Exit;
 If (Src.W <> Dst.W) Or (Src.H <> Dst.H) Then Exit;
 Move(Src.D^, Dst.D^, Src.W * Src.H * 3);
End;

{ --- Recepteur de lignes : reduit l'image par moyenne si elle est trop --- }
{ --- grande pour la memoire disponible                                  --- }

Function SinkBegin(W, H: LongInt; Var Img: TImg): Boolean;
Begin
 SinkBegin := False;
 SkW := W;
 SkH := H;
 SkStep := 1;
 SkAcc := Nil;
 If (W < 1) Or (H < 1) Or (W > 30000) Or (H > 30000) Then Exit;
 While ((W + SkStep - 1) Div SkStep) *
       ((H + SkStep - 1) Div SkStep) > LOAD_MAX_PIX Do Inc(SkStep);
 SkOW := (W + SkStep - 1) Div SkStep;
 SkOH := (H + SkStep - 1) Div SkStep;
 If Not ImgNew(Img, SkOW, SkOH, False) Then Exit;
 SkImg := Img;
 SkCnt := 0;
 If SkStep > 1 Then Begin
  SkAcc := PLongArr(MemAlloc(SkOW * 3 * SizeOf(LongInt)));
  If SkAcc = Nil Then Begin
   ImgFree(Img);
   Exit;
  End;
  FillChar(SkAcc^, SkOW * 3 * SizeOf(LongInt), 0);
 End;
 SinkBegin := True;
End;

Procedure SinkRow(Y: LongInt; Row: PByteArr);
Var
 X, OX, OY, C, Cols: LongInt;
Begin
 If (Y < 0) Or (Y >= SkH) Then Exit;
 If SkStep = 1 Then Begin
  Move(Row^, SkImg.D^[Y * SkW * 3], SkW * 3);
  Exit;
 End;
 For X := 0 To SkW - 1 Do Begin
  OX := X Div SkStep;
  For C := 0 To 2 Do Inc(SkAcc^[OX * 3 + C], Row^[X * 3 + C]);
 End;
 Inc(SkCnt);
 If (SkCnt = SkStep) Or (Y = SkH - 1) Then Begin
  OY := Y Div SkStep;
  For OX := 0 To SkOW - 1 Do Begin
   Cols := IMin(SkStep, SkW - OX * SkStep);
   For C := 0 To 2 Do
    SkImg.D^[(OY * SkOW + OX) * 3 + C] :=
     SkAcc^[OX * 3 + C] Div (Cols * SkCnt);
  End;
  FillChar(SkAcc^, SkOW * 3 * SizeOf(LongInt), 0);
  SkCnt := 0;
 End;
End;

Procedure SinkEnd;
Begin
 If SkAcc <> Nil Then FreeMem(SkAcc, SkOW * 3 * SizeOf(LongInt));
 SkAcc := Nil;
End;

{ Lecture d'un bloc : le compteur de BlockRead est un Word en Turbo Pascal }
Function BRead(Var F: File; Var Buf; Count: LongInt): LongInt;
Var
 {$IFDEF FPC}
 NR: LongInt;
 {$ELSE}
 NR: Word;
 {$ENDIF}
Begin
 NR := 0;
 BlockRead(F, Buf, Count, NR);
 BRead := NR;
End;

Function Rd16(P: PByteArr; O: LongInt): LongInt;
Begin
 Rd16 := P^[O] + P^[O + 1] * 256;
End;

Function Rd32(P: PByteArr; O: LongInt): LongInt;
Begin
 Rd32 := P^[O] + P^[O + 1] * 256 + LongInt(P^[O + 2]) * 65536 +
         LongInt(P^[O + 3] And 127) * 16777216;
End;

Function MaskShift(M: LongInt): Integer;
Var
 S: Integer;
Begin
 S := 0;
 If M = 0 Then Begin MaskShift := 0; Exit; End;
 While (M And 1) = 0 Do Begin M := M Shr 1; Inc(S); End;
 MaskShift := S;
End;

Function MaskBits(M: LongInt): Integer;
Var
 S: Integer;
Begin
 S := 0;
 If M = 0 Then Begin MaskBits := 0; Exit; End;
 While (M And 1) = 0 Do M := M Shr 1;
 While (M And 1) = 1 Do Begin M := M Shr 1; Inc(S); End;
 MaskBits := S;
End;

Function Scale8(V: LongInt; Bits: Integer): LongInt;
Begin
 If Bits <= 0 Then Scale8 := 0
 Else If Bits >= 8 Then Scale8 := V Shr (Bits - 8)
 Else Scale8 := V * 255 Div ((LongInt(1) Shl Bits) - 1);
End;

Function LoadBMP(Const Name: String; Var Img: TImg;
                 Var Err: String): Boolean;
Var
 F: File;
 Hd: Array[0..127] Of Byte;
 Pal: Array[0..255, 0..2] Of Byte;
 Row, Out_: PByteArr;
 N, DataOfs, DibSize, W, H, Bpp, Comp, Colors, RowBytes: LongInt;
 Y, X, SrcY, V, P, I: LongInt;
 TopDown: Boolean;
 MR, MG, MB: LongInt;
 SR, SG, SB, BR, BG, BB: Integer;
Begin
 LoadBMP := False;
 Err := '';
 FileMode := 0;
 {$I-}
 Assign(F, Name);
 Reset(F, 1);
 {$I+}
 If IOResult <> 0 Then Begin
  Err := L5('Fichier introuvable', 'File not found', 'Datei nicht gefunden',
            'Archivo no encontrado', 'File non trovato');
  Exit;
 End;
 FillChar(Hd, SizeOf(Hd), 0);
 N := BRead(F, Hd, 18);
 If (N < 18) Or (Hd[0] <> 66) Or (Hd[1] <> 77) Then Begin
  Err := 'BMP ?';
  Close(F);
  Exit;
 End;
 DibSize := Rd32(@Hd, 14);
 If (DibSize < 40) Or (DibSize > 124) Then Begin
  Err := 'BMP ?';
  Close(F);
  Exit;
 End;
 N := BRead(F, Hd[18], DibSize - 4);
 DataOfs := Rd32(@Hd, 10);
 W := Rd32(@Hd, 18);
 H := Rd32(@Hd, 22);
 If (Hd[25] And 128) <> 0 Then H := H - MaxLongInt - 1;
 TopDown := False;
 If H < 0 Then Begin TopDown := True; H := -H; End;
 Bpp := Rd16(@Hd, 28);
 Comp := Rd32(@Hd, 30);
 Colors := Rd32(@Hd, 46);
 If (Comp <> 0) And (Comp <> 3) Then Begin
  Err := L5('BMP compresse non pris en charge',
            'Compressed BMP not supported',
            'Komprimiertes BMP nicht unterstuetzt',
            'BMP comprimido no admitido', 'BMP compresso non supportato');
  Close(F);
  Exit;
 End;
 MR := $7C00; MG := $03E0; MB := $001F;
 If Bpp = 32 Then Begin MR := $FF0000; MG := $FF00; MB := $FF; End;
 If Comp = 3 Then Begin
  { champs de bits : apres l'en-tete de 40 octets, ou dans l'en-tete }
  If DibSize = 40 Then N := BRead(F, Hd[54], 12);
  MR := Rd32(@Hd, 54);
  MG := Rd32(@Hd, 58);
  MB := Rd32(@Hd, 62);
 End;
 SR := MaskShift(MR); SG := MaskShift(MG); SB := MaskShift(MB);
 BR := MaskBits(MR); BG := MaskBits(MG); BB := MaskBits(MB);
 If Not (Bpp In [1, 4, 8, 16, 24, 32]) Then Begin
  Err := 'BMP ' + IStr(Bpp) + ' bits';
  Close(F);
  Exit;
 End;
 FillChar(Pal, SizeOf(Pal), 0);
 If Bpp <= 8 Then Begin
  If Colors = 0 Then Colors := LongInt(1) Shl Bpp;
  If Colors > 256 Then Colors := 256;
  Seek(F, 14 + DibSize);
  For I := 0 To Colors - 1 Do Begin
   N := BRead(F, Hd, 4);
   Pal[I, 0] := Hd[2];
   Pal[I, 1] := Hd[1];
   Pal[I, 2] := Hd[0];
  End;
 End;
 RowBytes := ((W * Bpp + 31) Div 32) * 4;
 If Not SinkBegin(W, H, Img) Then Begin
  Err := L5('Memoire insuffisante', 'Not enough memory',
            'Nicht genug Speicher', 'Memoria insuficiente',
            'Memoria insufficiente');
  Close(F);
  Exit;
 End;
 Row := PByteArr(MemAlloc(RowBytes + 8));
 Out_ := PByteArr(MemAlloc(W * 3 + 8));
 If (Row = Nil) Or (Out_ = Nil) Then Begin
  If Row <> Nil Then FreeMem(Row, RowBytes + 8);
  If Out_ <> Nil Then FreeMem(Out_, W * 3 + 8);
  SinkEnd;
  ImgFree(Img);
  Err := 'Memoire / Memory';
  Close(F);
  Exit;
 End;
 For Y := 0 To H - 1 Do Begin
  If TopDown Then SrcY := Y Else SrcY := H - 1 - Y;
  Seek(F, DataOfs + SrcY * RowBytes);
  N := BRead(F, Row^, RowBytes);
  For X := 0 To W - 1 Do Begin
   Case Bpp Of
    1: Begin
     V := (Row^[X Shr 3] Shr (7 - (X And 7))) And 1;
     Out_^[X * 3] := Pal[V, 0]; Out_^[X * 3 + 1] := Pal[V, 1];
     Out_^[X * 3 + 2] := Pal[V, 2];
    End;
    4: Begin
     If (X And 1) = 0 Then V := Row^[X Shr 1] Shr 4
                      Else V := Row^[X Shr 1] And 15;
     Out_^[X * 3] := Pal[V, 0]; Out_^[X * 3 + 1] := Pal[V, 1];
     Out_^[X * 3 + 2] := Pal[V, 2];
    End;
    8: Begin
     V := Row^[X];
     Out_^[X * 3] := Pal[V, 0]; Out_^[X * 3 + 1] := Pal[V, 1];
     Out_^[X * 3 + 2] := Pal[V, 2];
    End;
    16: Begin
     V := Rd16(Row, X * 2);
     Out_^[X * 3] := Scale8((V And MR) Shr SR, BR);
     Out_^[X * 3 + 1] := Scale8((V And MG) Shr SG, BG);
     Out_^[X * 3 + 2] := Scale8((V And MB) Shr SB, BB);
    End;
    24: Begin
     P := X * 3;
     Out_^[X * 3] := Row^[P + 2]; Out_^[X * 3 + 1] := Row^[P + 1];
     Out_^[X * 3 + 2] := Row^[P];
    End;
    32: Begin
     P := X * 4;
     Out_^[X * 3] := Row^[P + 2]; Out_^[X * 3 + 1] := Row^[P + 1];
     Out_^[X * 3 + 2] := Row^[P];
    End;
   End;
  End;
  SinkRow(Y, Out_);
 End;
 FreeMem(Row, RowBytes + 8);
 FreeMem(Out_, W * 3 + 8);
 SinkEnd;
 Close(F);
 LoadBMP := True;
End;

Function PpmNum(Var F: File; Var Ch: Byte; Var Eof_: Boolean): LongInt;
Var
 V, N: LongInt;
Begin
 V := 0;
 While (Not Eof_) And ((Ch < 48) Or (Ch > 57)) Do Begin
  If Ch = 35 Then
   While (Not Eof_) And (Ch <> 10) Do Begin
    N := BRead(F, Ch, 1);
    If N = 0 Then Eof_ := True;
   End;
  N := BRead(F, Ch, 1);
  If N = 0 Then Eof_ := True;
 End;
 While (Not Eof_) And (Ch >= 48) And (Ch <= 57) Do Begin
  V := V * 10 + Ch - 48;
  If V > 1000000 Then V := 1000000;
  N := BRead(F, Ch, 1);
  If N = 0 Then Eof_ := True;
 End;
 PpmNum := V;
End;

Function LoadPPM(Const Name: String; Var Img: TImg;
                 Var Err: String): Boolean;
Var
 F: File;
 Ch: Byte;
 Eof_: Boolean;
 N, W, H, Mx, Y, X, Planes: LongInt;
 Typ: Byte;
 Row, Out_: PByteArr;
Begin
 LoadPPM := False;
 Err := '';
 FileMode := 0;
 {$I-}
 Assign(F, Name);
 Reset(F, 1);
 {$I+}
 If IOResult <> 0 Then Begin
  Err := L5('Fichier introuvable', 'File not found', 'Datei nicht gefunden',
            'Archivo no encontrado', 'File non trovato');
  Exit;
 End;
 N := BRead(F, Ch, 1);
 If (N < 1) Or (Ch <> 80) Then Begin Err := 'PPM ?'; Close(F); Exit; End;
 N := BRead(F, Typ, 1);
 If (Typ <> 53) And (Typ <> 54) Then Begin
  Err := 'PPM ?'; Close(F); Exit;
 End;
 If Typ = 54 Then Planes := 3 Else Planes := 1;
 Eof_ := False;
 Ch := 32;
 W := PpmNum(F, Ch, Eof_);
 H := PpmNum(F, Ch, Eof_);
 Mx := PpmNum(F, Ch, Eof_);
 If (W < 1) Or (H < 1) Or (Mx <> 255) Then Begin
  Err := 'PPM ?'; Close(F); Exit;
 End;
 { Ch contient l'espace qui suit la valeur maximale }
 If Not SinkBegin(W, H, Img) Then Begin
  Err := 'Memoire / Memory'; Close(F); Exit;
 End;
 Row := PByteArr(MemAlloc(W * Planes + 8));
 Out_ := PByteArr(MemAlloc(W * 3 + 8));
 If (Row = Nil) Or (Out_ = Nil) Then Begin
  If Row <> Nil Then FreeMem(Row, W * Planes + 8);
  If Out_ <> Nil Then FreeMem(Out_, W * 3 + 8);
  SinkEnd; ImgFree(Img); Close(F); Err := 'Memoire / Memory'; Exit;
 End;
 For Y := 0 To H - 1 Do Begin
  N := BRead(F, Row^, W * Planes);
  If N < W * Planes Then FillChar(Row^[N], W * Planes - N, 0);
  For X := 0 To W - 1 Do
   If Planes = 3 Then Begin
    Out_^[X * 3] := Row^[X * 3]; Out_^[X * 3 + 1] := Row^[X * 3 + 1];
    Out_^[X * 3 + 2] := Row^[X * 3 + 2];
   End
   Else Begin
    Out_^[X * 3] := Row^[X]; Out_^[X * 3 + 1] := Row^[X];
    Out_^[X * 3 + 2] := Row^[X];
   End;
  SinkRow(Y, Out_);
 End;
 FreeMem(Row, W * Planes + 8);
 FreeMem(Out_, W * 3 + 8);
 SinkEnd;
 Close(F);
 LoadPPM := True;
End;

Function SaveBMP(Const Name: String; Var Img: TImg): Boolean;
Var
 F: File;
 Hd: Array[0..53] Of Byte;
 Row: PByteArr;
 RowBytes, Y, X, Size: LongInt;
Begin
 SaveBMP := False;
 If Img.D = Nil Then Exit;
 RowBytes := ((Img.W * 3 + 3) Div 4) * 4;
 Size := 54 + RowBytes * Img.H;
 FillChar(Hd, SizeOf(Hd), 0);
 Hd[0] := 66; Hd[1] := 77;
 Hd[2] := Size And 255; Hd[3] := (Size Shr 8) And 255;
 Hd[4] := (Size Shr 16) And 255; Hd[5] := (Size Shr 24) And 255;
 Hd[10] := 54; Hd[14] := 40;
 Hd[18] := Img.W And 255; Hd[19] := (Img.W Shr 8) And 255;
 Hd[22] := Img.H And 255; Hd[23] := (Img.H Shr 8) And 255;
 Hd[26] := 1; Hd[28] := 24;
 Row := PByteArr(MemAlloc(RowBytes));
 If Row = Nil Then Exit;
 {$I-}
 Assign(F, Name);
 Rewrite(F, 1);
 {$I+}
 If IOResult <> 0 Then Begin FreeMem(Row, RowBytes); Exit; End;
 BlockWrite(F, Hd, 54);
 For Y := Img.H - 1 Downto 0 Do Begin
  FillChar(Row^, RowBytes, 0);
  For X := 0 To Img.W - 1 Do Begin
   Row^[X * 3] := Img.D^[(Y * Img.W + X) * 3 + 2];
   Row^[X * 3 + 1] := Img.D^[(Y * Img.W + X) * 3 + 1];
   Row^[X * 3 + 2] := Img.D^[(Y * Img.W + X) * 3];
  End;
  BlockWrite(F, Row^, RowBytes);
 End;
 Close(F);
 FreeMem(Row, RowBytes);
 SaveBMP := IOResult = 0;
End;

{ ---------------------------------------------------------------------- }
{ Decodeur JPEG integre (sequentiel et progressif 8 bits, Huffman, T.81)   }
{ Free Pascal seulement ; sous Turbo Pascal : BMP et PPM uniquement.       }
{ ---------------------------------------------------------------------- }

Var
 JOrient: Integer;     { orientation EXIF de la derniere image JPEG }

{$IFDEF FPC}
Const
 JZig: Array[0..63] Of Byte =
  (0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,
   12,19,26,33,40,48,41,34,27,20,13,6,7,14,21,28,
   35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,
   58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63);

Type
 TJHuff = Record
  MinCode, MaxCode, ValPtr: Array[1..16] Of LongInt;
  Vals: Array[0..255] Of Byte;
  Ok: Boolean;
 End;
 TJComp = Record
  Id, H, V, Tq, Td, Ta: Integer;
  Pred: LongInt;
  BW, BH: LongInt;
  Plane: PByteArr;
 End;
 TJBlk = Array[0..63] Of LongInt;
 TSIArr = Array[0..134217727] Of SmallInt;
 PSIArr = ^TSIArr;

Var
 JD: PByteArr;
 JSize, JPos: LongInt;
 JQ: Array[0..3, 0..63] Of Word;
 JHf: Array[0..1, 0..3] Of TJHuff;
 JC: Array[0..3] Of TJComp;
 JNC: Integer;
 JW, JHt: LongInt;
 JMaxH, JMaxV: Integer;
 JBuf: LongInt;
 JCnt: Integer;
 JErr: Boolean;
 JRst: LongInt;
 JCos: Array[0..7, 0..7] Of LongInt;
 JCosOk: Boolean;
 JFrame: Boolean;
 JProg: Boolean;
 JCoef: Array[0..3] Of PSIArr;
 JSs, JSe, JAh, JAl: Integer;
 JEobrun: LongInt;

Procedure JInitCos;
Var
 U, X: Integer;
 Cu: Real;
Begin
 For U := 0 To 7 Do Begin
  If U = 0 Then Cu := 0.7071067811865 Else Cu := 1.0;
  For X := 0 To 7 Do
   JCos[U, X] := Round(0.5 * Cu * Cos((2 * X + 1) * U * Pi / 16) * 2048);
 End;
 JCosOk := True;
End;

Function JNextByte: Integer;
Var
 B: Integer;
Begin
 JNextByte := 0;
 If JPos >= JSize Then Exit;
 B := JD^[JPos];
 If B = $FF Then Begin
  If (JPos + 1 < JSize) And (JD^[JPos + 1] = 0) Then Begin
   Inc(JPos, 2);
   JNextByte := $FF;
  End;
  { sinon : marqueur, on ne bouge pas et on fournit des zeros }
 End
 Else Begin
  Inc(JPos);
  JNextByte := B;
 End;
End;

Function JBit: Integer;
Begin
 If JCnt = 0 Then Begin
  JBuf := JNextByte;
  JCnt := 8;
 End;
 Dec(JCnt);
 JBit := (JBuf Shr JCnt) And 1;
End;

Function JBits(N: Integer): LongInt;
Var
 V: LongInt;
 I: Integer;
Begin
 V := 0;
 For I := 1 To N Do V := (V Shl 1) Or JBit;
 JBits := V;
End;

Function JRecv(S: Integer): LongInt;
Var
 V: LongInt;
Begin
 If S = 0 Then Begin JRecv := 0; Exit; End;
 If S > 16 Then Begin JErr := True; JRecv := 0; Exit; End;
 V := JBits(S);
 If V < (LongInt(1) Shl (S - 1)) Then V := V - (LongInt(1) Shl S) + 1;
 JRecv := V;
End;

Function JDecodeHuff(Var H: TJHuff): Integer;
Var
 L: Integer;
 Code: LongInt;
Begin
 Code := 0;
 JDecodeHuff := 0;
 If Not H.Ok Then Begin JErr := True; Exit; End;
 For L := 1 To 16 Do Begin
  Code := (Code Shl 1) Or JBit;
  If (H.MaxCode[L] >= 0) And (Code <= H.MaxCode[L]) Then Begin
   JDecodeHuff := H.Vals[(H.ValPtr[L] + Code - H.MinCode[L]) And 255];
   Exit;
  End;
 End;
 JErr := True;
End;

Function DivR(S, D: LongInt): LongInt;
Begin
 If S >= 0 Then DivR := (S + D Div 2) Div D
           Else DivR := -((-S + D Div 2) Div D);
End;

Procedure JIdct(Var Blk: TJBlk; Ci: Integer; Bx, By: LongInt);
Var
 Tmp: TJBlk;
 V, U, X, Y: Integer;
 S, Stride, Base: LongInt;
 Zero: Boolean;
Begin
 For V := 0 To 7 Do Begin
  Zero := True;
  For U := 0 To 7 Do If Blk[V * 8 + U] <> 0 Then Zero := False;
  If Zero Then
   For X := 0 To 7 Do Tmp[V * 8 + X] := 0
  Else
   For X := 0 To 7 Do Begin
    S := 0;
    For U := 0 To 7 Do S := S + Blk[V * 8 + U] * JCos[U, X];
    Tmp[V * 8 + X] := DivR(S, 2048);
   End;
 End;
 Stride := JC[Ci].BW * 8;
 Base := By * 8 * Stride + Bx * 8;
 For X := 0 To 7 Do
  For Y := 0 To 7 Do Begin
   S := 0;
   For V := 0 To 7 Do S := S + Tmp[V * 8 + X] * JCos[V, Y];
   JC[Ci].Plane^[Base + Y * Stride + X] := Clip8(DivR(S, 2048) + 128);
  End;
End;

Procedure JBlock(Ci: Integer; Bx, By: LongInt);
Var
 Blk: TJBlk;
 T, K, RS, R, S: Integer;
Begin
 FillChar(Blk, SizeOf(Blk), 0);
 If (Bx >= JC[Ci].BW) Or (By >= JC[Ci].BH) Then Begin JErr := True; Exit; End;
 T := JDecodeHuff(JHf[0, JC[Ci].Td]);
 If JErr Or (T > 11) Then Begin JErr := True; Exit; End;
 JC[Ci].Pred := JC[Ci].Pred + JRecv(T);
 Blk[0] := JC[Ci].Pred * JQ[JC[Ci].Tq, 0];
 K := 1;
 While (K < 64) And Not JErr Do Begin
  RS := JDecodeHuff(JHf[1, JC[Ci].Ta]);
  R := RS Shr 4;
  S := RS And 15;
  If S = 0 Then Begin
   If R = 15 Then Inc(K, 16) Else Break;
  End
  Else Begin
   Inc(K, R);
   If K > 63 Then Begin JErr := True; Exit; End;
   Blk[JZig[K]] := JRecv(S) * JQ[JC[Ci].Tq, K];
   Inc(K);
  End;
 End;
 If Not JErr Then JIdct(Blk, Ci, Bx, By);
End;

{ Bloc d'un JPEG progressif : accumule les coefficients (ordre naturel) }
Procedure JBlockP(Ci: Integer; Bx, By: LongInt);
Var
 Base, V: LongInt;
 T, K, RS, R, S, Z, P1, M1: Integer;
 Procedure RefineNZ(Z: Integer);
 Begin
  If JBit = 1 Then
   If (JCoef[Ci]^[Z] And P1) = 0 Then
    If JCoef[Ci]^[Z] >= 0 Then JCoef[Ci]^[Z] := JCoef[Ci]^[Z] + P1
                          Else JCoef[Ci]^[Z] := JCoef[Ci]^[Z] + M1;
 End;
Begin
 If (Bx >= JC[Ci].BW) Or (By >= JC[Ci].BH) Then Begin JErr := True; Exit; End;
 Base := (By * JC[Ci].BW + Bx) * 64;
 P1 := 1 Shl JAl;
 M1 := -P1;
 If JSs = 0 Then Begin
  If JAh = 0 Then Begin
   T := JDecodeHuff(JHf[0, JC[Ci].Td]);
   If JErr Or (T > 11) Then Begin JErr := True; Exit; End;
   JC[Ci].Pred := JC[Ci].Pred + JRecv(T);
   JCoef[Ci]^[Base] := JC[Ci].Pred * P1;
  End
  Else If JBit = 1 Then JCoef[Ci]^[Base] := JCoef[Ci]^[Base] Or P1;
  Exit;
 End;
 If JAh = 0 Then Begin
  If JEobrun > 0 Then Begin Dec(JEobrun); Exit; End;
  K := JSs;
  While (K <= JSe) And Not JErr Do Begin
   RS := JDecodeHuff(JHf[1, JC[Ci].Ta]);
   If JErr Then Exit;
   R := RS Shr 4;
   S := RS And 15;
   If S = 0 Then Begin
    If R < 15 Then Begin
     JEobrun := (LongInt(1) Shl R) - 1;
     If R > 0 Then JEobrun := JEobrun + JBits(R);
     Break;
    End;
    Inc(K, 16);
   End
   Else Begin
    Inc(K, R);
    If K > 63 Then Begin JErr := True; Exit; End;
    JCoef[Ci]^[Base + JZig[K]] := JRecv(S) * P1;
    Inc(K);
   End;
  End;
 End
 Else Begin
  K := JSs;
  If JEobrun <= 0 Then Begin
   While (K <= JSe) And Not JErr Do Begin
    RS := JDecodeHuff(JHf[1, JC[Ci].Ta]);
    If JErr Then Exit;
    R := RS Shr 4;
    S := RS And 15;
    V := 0;
    If S = 0 Then Begin
     If R < 15 Then Begin
      JEobrun := LongInt(1) Shl R;
      If R > 0 Then JEobrun := JEobrun + JBits(R);
      Break;
     End;
    End
    Else Begin
     If JBit = 1 Then V := P1 Else V := M1;
    End;
    While K <= JSe Do Begin
     Z := Base + JZig[K];
     If JCoef[Ci]^[Z] <> 0 Then RefineNZ(Z)
     Else Begin
      If R = 0 Then Break;
      Dec(R);
     End;
     Inc(K);
    End;
    If (V <> 0) And (K <= JSe) Then JCoef[Ci]^[Base + JZig[K]] := V;
    Inc(K);
   End;
  End;
  If (JEobrun > 0) And Not JErr Then Begin
   While K <= JSe Do Begin
    Z := Base + JZig[K];
    If JCoef[Ci]^[Z] <> 0 Then RefineNZ(Z);
    Inc(K);
   End;
   Dec(JEobrun);
  End;
 End;
End;

Procedure JBlockAny(Ci: Integer; Bx, By: LongInt);
Begin
 If JProg Then JBlockP(Ci, Bx, By) Else JBlock(Ci, Bx, By);
End;

{ Quantification inverse + IDCT de tous les blocs (JPEG progressif) }
Procedure JFinishProg;
Var
 Ci, K: Integer;
 Bx, By, Base: LongInt;
 Blk: TJBlk;
Begin
 For Ci := 0 To JNC - 1 Do
  If (JCoef[Ci] <> Nil) And (JC[Ci].Plane <> Nil) Then
   For By := 0 To JC[Ci].BH - 1 Do
    For Bx := 0 To JC[Ci].BW - 1 Do Begin
     Base := (By * JC[Ci].BW + Bx) * 64;
     For K := 0 To 63 Do
      Blk[JZig[K]] := JCoef[Ci]^[Base + JZig[K]] * JQ[JC[Ci].Tq, K];
     JIdct(Blk, Ci, Bx, By);
    End;
End;

Procedure JRestart;
Var
 I: Integer;
Begin
 JCnt := 0;
 While (JPos < JSize - 1) And Not ((JD^[JPos] = $FF) And
       (JD^[JPos + 1] >= $D0) And (JD^[JPos + 1] <= $D7)) Do Inc(JPos);
 If JPos < JSize - 1 Then Inc(JPos, 2) Else JErr := True;
 For I := 0 To 3 Do JC[I].Pred := 0;
 JEobrun := 0;
End;

Procedure JReadScan;
Var
 Ns, I, K, Ci, Sel, V, H: Integer;
 Idx: Array[0..3] Of Integer;
 Len, N, Total, BX_, CW, CH, MX, MY, My_, Mx_: LongInt;
Begin
 Len := JD^[JPos] * 256 + JD^[JPos + 1];
 Ns := JD^[JPos + 2];
 If (Ns < 1) Or (Ns > 4) Or Not JFrame Then Begin JErr := True; Exit; End;
 For I := 0 To Ns - 1 Do Begin
  Sel := JD^[JPos + 3 + I * 2];
  Idx[I] := -1;
  For K := 0 To JNC - 1 Do If JC[K].Id = Sel Then Idx[I] := K;
  If Idx[I] < 0 Then Begin JErr := True; Exit; End;
  JC[Idx[I]].Td := (JD^[JPos + 4 + I * 2] Shr 4) And 3;
  JC[Idx[I]].Ta := JD^[JPos + 4 + I * 2] And 3;
 End;
 JSs := JD^[JPos + 3 + Ns * 2];
 JSe := JD^[JPos + 4 + Ns * 2];
 JAh := JD^[JPos + 5 + Ns * 2] Shr 4;
 JAl := JD^[JPos + 5 + Ns * 2] And 15;
 If JProg Then Begin
  If (JSe > 63) Or (JSs > JSe) Or (JAl > 13) Or ((JSs = 0) And (JSe <> 0)) Or
     ((JSs > 0) And (Ns <> 1)) Then Begin
   JErr := True;
   Exit;
  End;
 End;
 Inc(JPos, Len);
 JCnt := 0;
 JEobrun := 0;
 For I := 0 To 3 Do JC[I].Pred := 0;
 If Ns = 1 Then Begin
  Ci := Idx[0];
  CW := (JW * JC[Ci].H + JMaxH - 1) Div JMaxH;
  CH := (JHt * JC[Ci].V + JMaxV - 1) Div JMaxV;
  BX_ := (CW + 7) Div 8;
  Total := BX_ * ((CH + 7) Div 8);
  N := 0;
  While (N < Total) And Not JErr Do Begin
   If (JRst > 0) And (N > 0) And (N Mod JRst = 0) Then JRestart;
   JBlockAny(Ci, N Mod BX_, N Div BX_);
   Inc(N);
  End;
 End
 Else Begin
  MX := (JW + 8 * JMaxH - 1) Div (8 * JMaxH);
  MY := (JHt + 8 * JMaxV - 1) Div (8 * JMaxV);
  N := 0;
  Total := MX * MY;
  While (N < Total) And Not JErr Do Begin
   If (JRst > 0) And (N > 0) And (N Mod JRst = 0) Then JRestart;
   Mx_ := N Mod MX;
   My_ := N Div MX;
   For I := 0 To Ns - 1 Do Begin
    Ci := Idx[I];
    For V := 0 To JC[Ci].V - 1 Do
     For H := 0 To JC[Ci].H - 1 Do
      If Not JErr Then JBlockAny(Ci, Mx_ * JC[Ci].H + H, My_ * JC[Ci].V + V);
   End;
   Inc(N);
  End;
 End;
 JCnt := 0;
End;

Procedure JReadSOF;
Var
 I: Integer;
 MXn, MYn: LongInt;
Begin
 If JFrame Then Begin JErr := True; Exit; End;
 If JD^[JPos + 2] <> 8 Then Begin JErr := True; Exit; End;
 JHt := JD^[JPos + 3] * 256 + JD^[JPos + 4];
 JW := JD^[JPos + 5] * 256 + JD^[JPos + 6];
 JNC := JD^[JPos + 7];
 If (JNC <> 1) And (JNC <> 3) Then Begin JErr := True; Exit; End;
 If (JW < 1) Or (JHt < 1) Then Begin JErr := True; Exit; End;
 JMaxH := 1;
 JMaxV := 1;
 For I := 0 To JNC - 1 Do Begin
  JC[I].Id := JD^[JPos + 8 + I * 3];
  JC[I].H := JD^[JPos + 9 + I * 3] Shr 4;
  JC[I].V := JD^[JPos + 9 + I * 3] And 15;
  JC[I].Tq := JD^[JPos + 10 + I * 3] And 3;
  If (JC[I].H < 1) Or (JC[I].H > 4) Or (JC[I].V < 1) Or (JC[I].V > 4) Then Begin
   JErr := True;
   Exit;
  End;
  If JC[I].H > JMaxH Then JMaxH := JC[I].H;
  If JC[I].V > JMaxV Then JMaxV := JC[I].V;
 End;
 MXn := (JW + 8 * JMaxH - 1) Div (8 * JMaxH);
 MYn := (JHt + 8 * JMaxV - 1) Div (8 * JMaxV);
 For I := 0 To JNC - 1 Do Begin
  JC[I].BW := MXn * JC[I].H;
  JC[I].BH := MYn * JC[I].V;
  JC[I].Plane := PByteArr(MemAlloc(JC[I].BW * 8 * JC[I].BH * 8));
  If JC[I].Plane = Nil Then Begin JErr := True; Exit; End;
  FillChar(JC[I].Plane^, JC[I].BW * 8 * JC[I].BH * 8, 128);
  If JProg Then Begin
   JCoef[I] := PSIArr(MemAlloc(JC[I].BW * JC[I].BH * 128));
   If JCoef[I] = Nil Then Begin JErr := True; Exit; End;
   FillChar(JCoef[I]^, JC[I].BW * JC[I].BH * 128, 0);
  End;
 End;
 JFrame := True;
End;

Procedure JReadDHT;
Var
 Len, EndP, K, Code: LongInt;
 Tc, Th, L, Cnt, I: Integer;
 Counts: Array[1..16] Of Integer;
Begin
 Len := JD^[JPos] * 256 + JD^[JPos + 1];
 EndP := JPos + Len;
 Inc(JPos, 2);
 While (JPos + 17 <= EndP) And Not JErr Do Begin
  Tc := JD^[JPos] Shr 4;
  Th := JD^[JPos] And 15;
  Inc(JPos);
  If (Tc > 1) Or (Th > 3) Then Begin JErr := True; Exit; End;
  Cnt := 0;
  For L := 1 To 16 Do Begin
   Counts[L] := JD^[JPos];
   Inc(Cnt, Counts[L]);
   Inc(JPos);
  End;
  If (Cnt > 256) Or (JPos + Cnt > EndP) Then Begin JErr := True; Exit; End;
  With JHf[Tc, Th] Do Begin
   Code := 0;
   K := 0;
   For L := 1 To 16 Do Begin
    ValPtr[L] := K;
    MinCode[L] := Code;
    Inc(Code, Counts[L]);
    Inc(K, Counts[L]);
    If Counts[L] > 0 Then MaxCode[L] := Code - 1 Else MaxCode[L] := -1;
    Code := Code Shl 1;
   End;
   For I := 0 To Cnt - 1 Do Vals[I] := JD^[JPos + I];
   Ok := True;
  End;
  Inc(JPos, Cnt);
 End;
 JPos := EndP;
End;

Procedure JReadDQT;
Var
 Len, EndP: LongInt;
 Pq, Tq, I: Integer;
Begin
 Len := JD^[JPos] * 256 + JD^[JPos + 1];
 EndP := JPos + Len;
 Inc(JPos, 2);
 While (JPos < EndP) And Not JErr Do Begin
  Pq := JD^[JPos] Shr 4;
  Tq := JD^[JPos] And 15;
  Inc(JPos);
  If (Tq > 3) Or (JPos + 64 * (Pq + 1) > EndP) Then Begin
   JErr := True;
   Exit;
  End;
  For I := 0 To 63 Do Begin
   If Pq = 0 Then JQ[Tq, I] := JD^[JPos]
             Else JQ[Tq, I] := JD^[JPos] * 256 + JD^[JPos + 1];
   Inc(JPos, Pq + 1);
  End;
 End;
 JPos := EndP;
End;

{ Orientation EXIF (balise $0112) dans un segment APP1 }
Procedure JReadExif;
Var
 Len, T, Ifd, N, I, E, Tag: LongInt;
 Little: Boolean;
 Function R16(O: LongInt): LongInt;
 Begin
  If Little Then R16 := JD^[O] + JD^[O + 1] * 256
            Else R16 := JD^[O] * 256 + JD^[O + 1];
 End;
 Function R32(O: LongInt): LongInt;
 Begin
  If Little Then R32 := R16(O) + R16(O + 2) * 65536
            Else R32 := R16(O) * 65536 + R16(O + 2);
 End;
Begin
 Len := JD^[JPos] * 256 + JD^[JPos + 1];
 If (Len < 20) Or (JPos + Len > JSize) Then Exit;
 If (JD^[JPos + 2] <> 69) Or (JD^[JPos + 3] <> 120) Or
    (JD^[JPos + 4] <> 105) Or (JD^[JPos + 5] <> 102) Then Exit;
 T := JPos + 8;
 Little := JD^[T] = 73;
 Ifd := T + R32(T + 4);
 If (Ifd < T) Or (Ifd + 2 > JPos + Len) Then Exit;
 N := R16(Ifd);
 For I := 0 To N - 1 Do Begin
  E := Ifd + 2 + I * 12;
  If E + 12 > JPos + Len Then Exit;
  Tag := R16(E);
  If Tag = $0112 Then JOrient := R16(E + 8);
 End;
End;

Function JpegDecodeMem(Data: PByteArr; Size: LongInt; Var Img: TImg;
                       Var Err: String): Boolean;
Var
 M, I: Integer;
 Len, X, Y, Xs, Ys, Yv, Cb, Cr, R, G, B: LongInt;
 Row: PByteArr;
 NextP: LongInt;
 Rgb: Boolean;
Begin
 JpegDecodeMem := False;
 Err := '';
 JD := Data;
 JSize := Size;
 JPos := 2;
 JErr := False;
 JFrame := False;
 JRst := 0;
 JOrient := 1;
 JNC := 0;
 JProg := False;
 JEobrun := 0;
 For I := 0 To 3 Do Begin JC[I].Plane := Nil; JCoef[I] := Nil; End;
 FillChar(JHf, SizeOf(JHf), 0);
 FillChar(JQ, SizeOf(JQ), 0);
 If Not JCosOk Then JInitCos;
 If (Size < 4) Or (Data^[0] <> $FF) Or (Data^[1] <> $D8) Then Begin
  Err := 'JPEG ?';
  Exit;
 End;
 While (JPos < JSize - 3) And Not JErr Do Begin
  If JD^[JPos] <> $FF Then Begin Inc(JPos); Continue; End;
  M := JD^[JPos + 1];
  If (M = $FF) Or (M = 0) Then Begin Inc(JPos); Continue; End;
  Inc(JPos, 2);
  If M = $D9 Then Break;
  If (M = $D8) Or (M = 1) Or ((M >= $D0) And (M <= $D7)) Then Continue;
  Len := JD^[JPos] * 256 + JD^[JPos + 1];
  If (Len < 2) Or (JPos + Len > JSize) Then Begin JErr := True; Break; End;
  NextP := JPos + Len;
  Case M Of
   $C0, $C1: JReadSOF;
   $C2: Begin JProg := True; JReadSOF; End;
   $C3, $C5..$C7, $C9..$CB, $CD..$CF: Begin
    Err := 'JPEG ?';
    JErr := True;
   End;
   $C4: JReadDHT;
   $DB: JReadDQT;
   $DD: Begin JRst := JD^[JPos + 2] * 256 + JD^[JPos + 3]; JPos := NextP; End;
   $DA: JReadScan;
   $E1: Begin JReadExif; JPos := NextP; End;
  Else
   JPos := NextP;
  End;
 End;
 If JFrame And JProg And (Err = '') Then JFinishProg;
 If JFrame And (Err = '') Then Begin
  If SinkBegin(JW, JHt, Img) Then Begin
   Row := PByteArr(MemAlloc(JW * 3 + 8));
   If Row <> Nil Then Begin
    Rgb := (JNC = 3) And (JC[0].Id = 82) And (JC[1].Id = 71);
    For Y := 0 To JHt - 1 Do Begin
     For X := 0 To JW - 1 Do Begin
      Xs := X * JC[0].H Div JMaxH;
      Ys := Y * JC[0].V Div JMaxV;
      Yv := JC[0].Plane^[Ys * JC[0].BW * 8 + Xs];
      If JNC = 1 Then Begin R := Yv; G := Yv; B := Yv; End
      Else Begin
       Xs := X * JC[1].H Div JMaxH;
       Ys := Y * JC[1].V Div JMaxV;
       Cb := JC[1].Plane^[Ys * JC[1].BW * 8 + Xs];
       Xs := X * JC[2].H Div JMaxH;
       Ys := Y * JC[2].V Div JMaxV;
       Cr := JC[2].Plane^[Ys * JC[2].BW * 8 + Xs];
       If Rgb Then Begin R := Yv; G := Cb; B := Cr; End
       Else Begin
        R := Yv + (359 * (Cr - 128)) Div 256;
        G := Yv - (88 * (Cb - 128) + 183 * (Cr - 128)) Div 256;
        B := Yv + (454 * (Cb - 128)) Div 256;
       End;
      End;
      Row^[X * 3] := Clip8(R);
      Row^[X * 3 + 1] := Clip8(G);
      Row^[X * 3 + 2] := Clip8(B);
     End;
     SinkRow(Y, Row);
    End;
    FreeMem(Row, JW * 3 + 8);
    JpegDecodeMem := True;
   End
   Else Err := 'Memoire / Memory';
   SinkEnd;
   If Not (Err = '') Then ImgFree(Img);
  End
  Else Err := 'Memoire / Memory';
 End
 Else If Err = '' Then Err := 'JPEG ?';
 For I := 0 To 3 Do
  If JC[I].Plane <> Nil Then Begin
   FreeMem(JC[I].Plane, JC[I].BW * 8 * JC[I].BH * 8);
   JC[I].Plane := Nil;
  End;
 For I := 0 To 3 Do
  If JCoef[I] <> Nil Then Begin
   FreeMem(JCoef[I], JC[I].BW * JC[I].BH * 128);
   JCoef[I] := Nil;
  End;
End;

Function LoadJPEG(Const Name: String; Var Img: TImg;
                  Var Err: String): Boolean;
Var
 F: File;
 Buf: PByteArr;
 Size, N: LongInt;
Begin
 LoadJPEG := False;
 FileMode := 0;
 {$I-}
 Assign(F, Name);
 Reset(F, 1);
 {$I+}
 If IOResult <> 0 Then Begin
  Err := L5('Fichier introuvable', 'File not found', 'Datei nicht gefunden',
            'Archivo no encontrado', 'File non trovato');
  Exit;
 End;
 Size := FileSize(F);
 Buf := PByteArr(MemAlloc(Size + 16));
 If Buf = Nil Then Begin
  Close(F);
  Err := 'Memoire / Memory';
  Exit;
 End;
 N := BRead(F, Buf^, Size);
 Close(F);
 LoadJPEG := JpegDecodeMem(Buf, N, Img, Err);
 FreeMem(Buf, Size + 16);
End;
{$ELSE}
Function LoadJPEG(Const Name: String; Var Img: TImg;
                  Var Err: String): Boolean;
Begin
 Err := 'JPEG : Free Pascal';
 LoadJPEG := False;
End;
{$ENDIF}

{ ---------------------------------------------------------------------- }
{ Decodeur PNG integre (Inflate + filtres ; non entrelace)                 }
{ ---------------------------------------------------------------------- }

{$IFDEF FPC}
Const
 LBase: Array[0..28] Of Word = (3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,
  43,51,59,67,83,99,115,131,163,195,227,258);
 LExtra: Array[0..28] Of Byte = (0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,
  4,4,4,4,5,5,5,5,0);
 DBase: Array[0..29] Of Word = (1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,
  257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577);
 DExtra: Array[0..29] Of Byte = (0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,
  9,9,10,10,11,11,12,12,13,13);
 CLOrder: Array[0..18] Of Byte = (16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,
  14,1,15);

Type
 TInfTree = Record
  Counts: Array[0..15] Of Word;
  Syms: Array[0..287] Of Word;
 End;

Var
 IS_: PByteArr;
 ISLen, ISPos, ITag, IDLen, IDMax: LongInt;
 IBits: Integer;
 IDst: PByteArr;
 IErr: Boolean;
 LTree, DTree: TInfTree;

Function GetBit: Integer;
Begin
 If IBits = 0 Then Begin
  If ISPos >= ISLen Then Begin IErr := True; GetBit := 0; Exit; End;
  ITag := IS_^[ISPos];
  Inc(ISPos);
  IBits := 8;
 End;
 GetBit := ITag And 1;
 ITag := ITag Shr 1;
 Dec(IBits);
End;

Function GetBits(N: Integer): LongInt;
Var
 I: Integer;
 V: LongInt;
Begin
 V := 0;
 For I := 0 To N - 1 Do V := V Or (LongInt(GetBit) Shl I);
 GetBits := V;
End;

Procedure BuildTree(Var T: TInfTree; Const Lens: Array Of Byte;
                    Off, Num: Integer);
Var
 I: Integer;
 Offs: Array[0..16] Of Word;
Begin
 For I := 0 To 15 Do T.Counts[I] := 0;
 For I := 0 To Num - 1 Do Inc(T.Counts[Lens[Off + I]]);
 T.Counts[0] := 0;
 Offs[1] := 0;
 For I := 1 To 15 Do Offs[I + 1] := Offs[I] + T.Counts[I];
 For I := 0 To Num - 1 Do
  If Lens[Off + I] <> 0 Then Begin
   T.Syms[Offs[Lens[Off + I]]] := I;
   Inc(Offs[Lens[Off + I]]);
  End;
End;

Function DecodeSym(Var T: TInfTree): Integer;
Var
 Sum, Cur, Len: LongInt;
Begin
 Sum := 0;
 Cur := 0;
 Len := 0;
 Repeat
  Cur := 2 * Cur + GetBit;
  Inc(Len);
  If Len > 15 Then Begin IErr := True; DecodeSym := 0; Exit; End;
  Sum := Sum + T.Counts[Len];
  Cur := Cur - T.Counts[Len];
 Until (Cur < 0) Or IErr;
 If (Sum + Cur > 287) Or (Sum + Cur < 0) Then Begin
  IErr := True;
  DecodeSym := 0;
  Exit;
 End;
 DecodeSym := T.Syms[Sum + Cur];
End;

Procedure InflateCodes;
Var
 Sym, Len, Dist, I: Integer;
 Src: LongInt;
Begin
 While Not IErr Do Begin
  Sym := DecodeSym(LTree);
  If IErr Then Exit;
  If Sym < 256 Then Begin
   If IDLen >= IDMax Then Begin IErr := True; Exit; End;
   IDst^[IDLen] := Sym;
   Inc(IDLen);
  End
  Else If Sym = 256 Then Exit
  Else Begin
   Sym := Sym - 257;
   If Sym > 28 Then Begin IErr := True; Exit; End;
   Len := LBase[Sym] + GetBits(LExtra[Sym]);
   Dist := DecodeSym(DTree);
   If Dist > 29 Then Begin IErr := True; Exit; End;
   Dist := DBase[Dist] + GetBits(DExtra[Dist]);
   If (Dist > IDLen) Or (IDLen + Len > IDMax) Then Begin
    IErr := True;
    Exit;
   End;
   Src := IDLen - Dist;
   For I := 1 To Len Do Begin
    IDst^[IDLen] := IDst^[Src];
    Inc(IDLen);
    Inc(Src);
   End;
  End;
 End;
End;

Procedure FixedTrees;
Var
 L: Array[0..287] Of Byte;
 D: Array[0..29] Of Byte;
 I: Integer;
Begin
 For I := 0 To 143 Do L[I] := 8;
 For I := 144 To 255 Do L[I] := 9;
 For I := 256 To 279 Do L[I] := 7;
 For I := 280 To 287 Do L[I] := 8;
 For I := 0 To 29 Do D[I] := 5;
 BuildTree(LTree, L, 0, 288);
 BuildTree(DTree, D, 0, 30);
End;

Procedure DynamicTrees;
Var
 L: Array[0..319] Of Byte;
 CL: Array[0..18] Of Byte;
 CT: TInfTree;
 HLit, HDist, HCLen, I, Num, Sym, Prev, Rep: Integer;
Begin
 HLit := GetBits(5) + 257;
 HDist := GetBits(5) + 1;
 HCLen := GetBits(4) + 4;
 If (HLit > 286) Or (HDist > 30) Then Begin IErr := True; Exit; End;
 For I := 0 To 18 Do CL[I] := 0;
 For I := 0 To HCLen - 1 Do CL[CLOrder[I]] := GetBits(3);
 BuildTree(CT, CL, 0, 19);
 FillChar(L, SizeOf(L), 0);
 Num := 0;
 Prev := 0;
 While (Num < HLit + HDist) And (Not IErr) Do Begin
  Sym := DecodeSym(CT);
  If Sym < 16 Then Begin L[Num] := Sym; Prev := Sym; Inc(Num); End
  Else Begin
   If Sym = 16 Then Rep := 3 + GetBits(2)
   Else If Sym = 17 Then Begin Rep := 3 + GetBits(3); Prev := 0; End
   Else Begin Rep := 11 + GetBits(7); Prev := 0; End;
   If Num + Rep > HLit + HDist Then Begin IErr := True; Exit; End;
   While Rep > 0 Do Begin L[Num] := Prev; Inc(Num); Dec(Rep); End;
  End;
 End;
 If IErr Then Exit;
 BuildTree(LTree, L, 0, HLit);
 BuildTree(DTree, L, HLit, HDist);
End;

{ Decompresse un flux zlib (en-tete de 2 octets, somme ignoree) }
Function FlateDec(Src: PByteArr; SLen: LongInt; Dst: PByteArr;
                  DMax: LongInt; Var DLen: LongInt): Boolean;
Var
 Final, BType: Integer;
 Len, NLen, I: LongInt;
Begin
 IS_ := Src;
 ISLen := SLen;
 ISPos := 2;
 ITag := 0;
 IBits := 0;
 IDst := Dst;
 IDLen := 0;
 IDMax := DMax;
 IErr := False;
 If SLen < 3 Then Begin DLen := 0; FlateDec := False; Exit; End;
 Repeat
  Final := GetBit;
  BType := GetBits(2);
  If IErr Then Break;
  Case BType Of
   0: Begin
    IBits := 0;
    If ISPos + 4 > ISLen Then Begin IErr := True; Break; End;
    Len := Src^[ISPos] + Src^[ISPos + 1] * 256;
    NLen := Src^[ISPos + 2] + Src^[ISPos + 3] * 256;
    Inc(ISPos, 4);
    If Len <> (NLen Xor $FFFF) Then Begin IErr := True; Break; End;
    For I := 1 To Len Do Begin
     If (ISPos >= ISLen) Or (IDLen >= IDMax) Then Begin
      IErr := True;
      Break;
     End;
     Dst^[IDLen] := Src^[ISPos];
     Inc(IDLen);
     Inc(ISPos);
    End;
   End;
   1: Begin FixedTrees; InflateCodes; End;
   2: Begin DynamicTrees; If Not IErr Then InflateCodes; End;
  Else IErr := True;
  End;
 Until (Final = 1) Or IErr;
 DLen := IDLen;
 FlateDec := (Not IErr) Or (IDLen > 0);
End;

Function Be32(P: PByteArr; O: LongInt): LongInt;
Begin
 Be32 := LongInt(P^[O] And 127) * 16777216 + LongInt(P^[O + 1]) * 65536 +
         P^[O + 2] * 256 + P^[O + 3];
End;

Function PngSample(Row: PByteArr; I, Depth: Integer): Integer;
Begin
 Case Depth Of
  8: PngSample := Row^[I];
  16: PngSample := Row^[I * 2];
  4: PngSample := (Row^[I Shr 1] Shr (4 - (I And 1) * 4)) And 15;
  2: PngSample := (Row^[I Shr 2] Shr (6 - (I And 3) * 2)) And 3;
 Else PngSample := (Row^[I Shr 3] Shr (7 - (I And 7))) And 1;
 End;
End;

Function LoadPNG(Const Name: String; Var Img: TImg;
                 Var Err: String): Boolean;
Var
 F: File;
 Buf, Idat, Raw, Row, Out_: PByteArr;
 Size, N, P, Len, IdatLen, IdatPos, RawLen, RowB, Stride: LongInt;
 W, H, Y, X, I, Bpp, A, V, Idx, Left, Up, UpLeft, Pa, Pb, Pc, Pr: LongInt;
 Depth, CT, Chans, Filt: Integer;
 Pal: Array[0..255, 0..2] Of Byte;
 Typ: String[4];
 Ok: Boolean;
 Prev: PByteArr;
Begin
 LoadPNG := False;
 Err := '';
 FileMode := 0;
 {$I-}
 Assign(F, Name);
 Reset(F, 1);
 {$I+}
 If IOResult <> 0 Then Begin
  Err := L5('Fichier introuvable', 'File not found', 'Datei nicht gefunden',
            'Archivo no encontrado', 'File non trovato');
  Exit;
 End;
 Size := FileSize(F);
 Buf := PByteArr(MemAlloc(Size + 16));
 If Buf = Nil Then Begin Close(F); Err := 'Memoire / Memory'; Exit; End;
 N := BRead(F, Buf^, Size);
 Close(F);
 Size := N;
 W := 0; H := 0; Depth := 0; CT := 0; IdatLen := 0;
 FillChar(Pal, SizeOf(Pal), 0);
 If (Size < 33) Or (Buf^[0] <> 137) Or (Buf^[1] <> 80) Then Begin
  Err := 'PNG ?';
  FreeMem(Buf, Size + 16);
  Exit;
 End;
 { premier passage : en-tete, palette, taille des donnees }
 P := 8;
 While P + 12 <= Size Do Begin
  Len := Be32(Buf, P);
  Typ := Chr(Buf^[P + 4]) + Chr(Buf^[P + 5]) + Chr(Buf^[P + 6]) +
         Chr(Buf^[P + 7]);
  If (Len < 0) Or (P + 12 + Len > Size) Then Break;
  If Typ = 'IHDR' Then Begin
   W := Be32(Buf, P + 8);
   H := Be32(Buf, P + 12);
   Depth := Buf^[P + 16];
   CT := Buf^[P + 17];
   If Buf^[P + 20] <> 0 Then Err := 'PNG interlace / interlaced';
  End
  Else If Typ = 'PLTE' Then Begin
   For I := 0 To (Len Div 3) - 1 Do
    If I < 256 Then Begin
     Pal[I, 0] := Buf^[P + 8 + I * 3];
     Pal[I, 1] := Buf^[P + 9 + I * 3];
     Pal[I, 2] := Buf^[P + 10 + I * 3];
    End;
  End
  Else If Typ = 'IDAT' Then Inc(IdatLen, Len)
  Else If Typ = 'IEND' Then Break;
  Inc(P, 12 + Len);
 End;
 Case CT Of
  0: Chans := 1;
  2: Chans := 3;
  3: Chans := 1;
  4: Chans := 2;
  6: Chans := 4;
 Else Chans := 0;
 End;
 If (Err = '') And ((W < 1) Or (H < 1) Or (Chans = 0) Or (IdatLen < 3) Or
    Not (Depth In [1, 2, 4, 8, 16])) Then Err := 'PNG ?';
 If Err <> '' Then Begin FreeMem(Buf, Size + 16); Exit; End;
 Idat := PByteArr(MemAlloc(IdatLen));
 RowB := (W * Chans * Depth + 7) Div 8;
 Stride := RowB + 1;
 RawLen := Stride * H;
 Raw := PByteArr(MemAlloc(RawLen + 8));
 If (Idat = Nil) Or (Raw = Nil) Then Begin
  If Idat <> Nil Then FreeMem(Idat, IdatLen);
  If Raw <> Nil Then FreeMem(Raw, RawLen + 8);
  FreeMem(Buf, Size + 16);
  Err := 'Memoire / Memory';
  Exit;
 End;
 IdatPos := 0;
 P := 8;
 While P + 12 <= Size Do Begin
  Len := Be32(Buf, P);
  If (Len < 0) Or (P + 12 + Len > Size) Then Break;
  If (Buf^[P + 4] = 73) And (Buf^[P + 5] = 68) And (Buf^[P + 6] = 65) And
     (Buf^[P + 7] = 84) Then Begin
   Move(Buf^[P + 8], Idat^[IdatPos], Len);
   Inc(IdatPos, Len);
  End;
  Inc(P, 12 + Len);
 End;
 FreeMem(Buf, Size + 16);
 Ok := FlateDec(Idat, IdatLen, Raw, RawLen, N);
 FreeMem(Idat, IdatLen);
 If (Not Ok) Or (N < RawLen) Then Begin
  FreeMem(Raw, RawLen + 8);
  Err := 'PNG ?';
  Exit;
 End;
 If Not SinkBegin(W, H, Img) Then Begin
  FreeMem(Raw, RawLen + 8);
  Err := 'Memoire / Memory';
  Exit;
 End;
 Out_ := PByteArr(MemAlloc(W * 3 + 8));
 If Out_ = Nil Then Begin
  SinkEnd; ImgFree(Img); FreeMem(Raw, RawLen + 8);
  Err := 'Memoire / Memory';
  Exit;
 End;
 Bpp := (Chans * Depth + 7) Div 8;
 Prev := Nil;
 For Y := 0 To H - 1 Do Begin
  Row := PByteArr(@Raw^[Y * Stride + 1]);
  Filt := Raw^[Y * Stride];
  For X := 0 To RowB - 1 Do Begin
   If X >= Bpp Then Left := Row^[X - Bpp] Else Left := 0;
   If Prev <> Nil Then Up := Prev^[X] Else Up := 0;
   If (Prev <> Nil) And (X >= Bpp) Then UpLeft := Prev^[X - Bpp]
                                   Else UpLeft := 0;
   Case Filt Of
    1: Row^[X] := (Row^[X] + Left) And 255;
    2: Row^[X] := (Row^[X] + Up) And 255;
    3: Row^[X] := (Row^[X] + (Left + Up) Div 2) And 255;
    4: Begin
     V := Left + Up - UpLeft;
     Pa := IAbs(V - Left);
     Pb := IAbs(V - Up);
     Pc := IAbs(V - UpLeft);
     If (Pa <= Pb) And (Pa <= Pc) Then Pr := Left
     Else If Pb <= Pc Then Pr := Up
     Else Pr := UpLeft;
     Row^[X] := (Row^[X] + Pr) And 255;
    End;
   End;
  End;
  For X := 0 To W - 1 Do Begin
   A := 255;
   Case CT Of
    0: Begin
     V := PngSample(Row, X, Depth);
     If Depth < 8 Then V := V * 255 Div ((1 Shl Depth) - 1);
     Out_^[X * 3] := V; Out_^[X * 3 + 1] := V; Out_^[X * 3 + 2] := V;
    End;
    2: Begin
     If Depth = 8 Then Begin
      Out_^[X * 3] := Row^[X * 3]; Out_^[X * 3 + 1] := Row^[X * 3 + 1];
      Out_^[X * 3 + 2] := Row^[X * 3 + 2];
     End
     Else Begin
      Out_^[X * 3] := Row^[X * 6]; Out_^[X * 3 + 1] := Row^[X * 6 + 2];
      Out_^[X * 3 + 2] := Row^[X * 6 + 4];
     End;
    End;
    3: Begin
     Idx := PngSample(Row, X, Depth);
     Out_^[X * 3] := Pal[Idx, 0]; Out_^[X * 3 + 1] := Pal[Idx, 1];
     Out_^[X * 3 + 2] := Pal[Idx, 2];
    End;
    4: Begin
     If Depth = 8 Then Begin V := Row^[X * 2]; A := Row^[X * 2 + 1]; End
     Else Begin V := Row^[X * 4]; A := Row^[X * 4 + 2]; End;
     Out_^[X * 3] := V; Out_^[X * 3 + 1] := V; Out_^[X * 3 + 2] := V;
    End;
    6: Begin
     If Depth = 8 Then Begin
      Out_^[X * 3] := Row^[X * 4]; Out_^[X * 3 + 1] := Row^[X * 4 + 1];
      Out_^[X * 3 + 2] := Row^[X * 4 + 2]; A := Row^[X * 4 + 3];
     End
     Else Begin
      Out_^[X * 3] := Row^[X * 8]; Out_^[X * 3 + 1] := Row^[X * 8 + 2];
      Out_^[X * 3 + 2] := Row^[X * 8 + 4]; A := Row^[X * 8 + 6];
     End;
    End;
   End;
   If A < 255 Then
    For I := 0 To 2 Do
     Out_^[X * 3 + I] := (Out_^[X * 3 + I] * A + 255 * (255 - A)) Div 255;
  End;
  SinkRow(Y, Out_);
  Prev := Row;
 End;
 FreeMem(Out_, W * 3 + 8);
 FreeMem(Raw, RawLen + 8);
 SinkEnd;
 LoadPNG := True;
End;
{$ELSE}
Function LoadPNG(Const Name: String; Var Img: TImg;
                 Var Err: String): Boolean;
Begin
 Err := 'PNG : Free Pascal';
 LoadPNG := False;
End;
{$ENDIF}

{ ---------------------------------------------------------------------- }
{ Images : chargement general, rotation, redimensionnement                 }
{ ---------------------------------------------------------------------- }

{ Rotation de 90 degres (6 = sens horaire, 8 = anti-horaire) ou 180 }
Procedure ImgRotate(Var I: TImg; Orient: Integer);
Var
 T: TImg;
 X, Y, NX, NY, C: LongInt;
Begin
 If I.D = Nil Then Exit;
 If Orient = 3 Then Begin
  If Not ImgNew(T, I.W, I.H, False) Then Exit;
 End
 Else If Not ImgNew(T, I.H, I.W, False) Then Exit;
 For Y := 0 To I.H - 1 Do
  For X := 0 To I.W - 1 Do Begin
   Case Orient Of
    6: Begin NX := I.H - 1 - Y; NY := X; End;
    8: Begin NX := Y; NY := I.W - 1 - X; End;
   Else Begin NX := I.W - 1 - X; NY := I.H - 1 - Y; End;
   End;
   For C := 0 To 2 Do
    T.D^[(NY * T.W + NX) * 3 + C] := I.D^[(Y * I.W + X) * 3 + C];
  End;
 ImgFree(I);
 I := T;
End;

Function LoadImageFile(Const Name: String; Var Img: TImg;
                       Var Err: String): Boolean;
Var
 F: File;
 Hd: Array[0..7] Of Byte;
 N: LongInt;
Begin
 LoadImageFile := False;
 Err := '';
 Img.D := Nil;
 Img.A := Nil;
 Img.W := 0;
 Img.H := 0;
 FillChar(Hd, SizeOf(Hd), 0);
 FileMode := 0;
 {$I-}
 Assign(F, Name);
 Reset(F, 1);
 {$I+}
 If IOResult <> 0 Then Begin
  Err := L5('Fichier introuvable', 'File not found', 'Datei nicht gefunden',
            'Archivo no encontrado', 'File non trovato');
  Exit;
 End;
 N := BRead(F, Hd, 8);
 Close(F);
 If (Hd[0] = 66) And (Hd[1] = 77) Then LoadImageFile := LoadBMP(Name, Img, Err)
 Else If (Hd[0] = $FF) And (Hd[1] = $D8) Then Begin
  JOrient := 1;
  LoadImageFile := LoadJPEG(Name, Img, Err);
  If (Err = '') And ((JOrient = 3) Or (JOrient = 6) Or (JOrient = 8)) Then
   ImgRotate(Img, JOrient);
 End
 Else If (Hd[0] = 137) And (Hd[1] = 80) Then
  LoadImageFile := LoadPNG(Name, Img, Err)
 Else If (Hd[0] = 80) And ((Hd[1] = 53) Or (Hd[1] = 54)) Then
  LoadImageFile := LoadPPM(Name, Img, Err)
 Else
  Err := L5('Format non reconnu (BMP, PPM, JPEG, PNG)',
            'Unknown format (BMP, PPM, JPEG, PNG)',
            'Unbekanntes Format (BMP, PPM, JPEG, PNG)',
            'Formato desconocido (BMP, PPM, JPEG, PNG)',
            'Formato sconosciuto (BMP, PPM, JPEG, PNG)');
End;

{ Redimensionnement par moyenne des zones (reduction) }
Procedure ImgResizeBox(Var Src, Dst: TImg);
Var
 X, Y, X0, X1, Y0, Y1, SX, SY, Cnt: LongInt;
 S0, S1, S2: LongInt;
Begin
 For Y := 0 To Dst.H - 1 Do Begin
  Y0 := Y * Src.H Div Dst.H;
  Y1 := (Y + 1) * Src.H Div Dst.H;
  If Y1 <= Y0 Then Y1 := Y0 + 1;
  If Y1 > Src.H Then Y1 := Src.H;
  For X := 0 To Dst.W - 1 Do Begin
   X0 := X * Src.W Div Dst.W;
   X1 := (X + 1) * Src.W Div Dst.W;
   If X1 <= X0 Then X1 := X0 + 1;
   If X1 > Src.W Then X1 := Src.W;
   S0 := 0; S1 := 0; S2 := 0; Cnt := 0;
   For SY := Y0 To Y1 - 1 Do
    For SX := X0 To X1 - 1 Do Begin
     Inc(S0, Src.D^[(SY * Src.W + SX) * 3]);
     Inc(S1, Src.D^[(SY * Src.W + SX) * 3 + 1]);
     Inc(S2, Src.D^[(SY * Src.W + SX) * 3 + 2]);
     Inc(Cnt);
    End;
   If Cnt < 1 Then Cnt := 1;
   Dst.D^[(Y * Dst.W + X) * 3] := S0 Div Cnt;
   Dst.D^[(Y * Dst.W + X) * 3 + 1] := S1 Div Cnt;
   Dst.D^[(Y * Dst.W + X) * 3 + 2] := S2 Div Cnt;
  End;
 End;
End;

{ Echantillon bilineaire : coordonnees en virgule fixe 16.16, le centre
  du pixel (0,0) est en (0,0). Retourne R, V, B (et A si plan alpha). }
Procedure Bilin(Var I: TImg; X16, Y16: LongInt; Var R, G, B, A: LongInt);
Var
 X0, Y0, FX, FY, X1, Y1, P00, P01, P10, P11, W00, W01, W10, W11: LongInt;
 WA, WB: LongInt;
Begin
 X0 := X16 Shr 16;
 Y0 := Y16 Shr 16;
 If X16 < 0 Then X0 := -(((-X16) + 65535) Shr 16);
 If Y16 < 0 Then Y0 := -(((-Y16) + 65535) Shr 16);
 FX := (X16 - X0 * 65536) Shr 8;       { 0..255 }
 FY := (Y16 - Y0 * 65536) Shr 8;
 X1 := X0 + 1;
 Y1 := Y0 + 1;
 If X0 < 0 Then X0 := 0;
 If Y0 < 0 Then Y0 := 0;
 If X1 < 0 Then X1 := 0;
 If Y1 < 0 Then Y1 := 0;
 If X0 >= I.W Then X0 := I.W - 1;
 If X1 >= I.W Then X1 := I.W - 1;
 If Y0 >= I.H Then Y0 := I.H - 1;
 If Y1 >= I.H Then Y1 := I.H - 1;
 P00 := (Y0 * I.W + X0) * 3;
 P01 := (Y0 * I.W + X1) * 3;
 P10 := (Y1 * I.W + X0) * 3;
 P11 := (Y1 * I.W + X1) * 3;
 W00 := (256 - FX) * (256 - FY);
 W01 := FX * (256 - FY);
 W10 := (256 - FX) * FY;
 W11 := FX * FY;
 R := (I.D^[P00] * W00 + I.D^[P01] * W01 + I.D^[P10] * W10 +
       I.D^[P11] * W11 + 32768) Shr 16;
 G := (I.D^[P00 + 1] * W00 + I.D^[P01 + 1] * W01 + I.D^[P10 + 1] * W10 +
       I.D^[P11 + 1] * W11 + 32768) Shr 16;
 B := (I.D^[P00 + 2] * W00 + I.D^[P01 + 2] * W01 + I.D^[P10 + 2] * W10 +
       I.D^[P11 + 2] * W11 + 32768) Shr 16;
 If I.A <> Nil Then Begin
  WA := Y0 * I.W;
  WB := Y1 * I.W;
  A := (I.A^[WA + X0] * W00 + I.A^[WA + X1] * W01 + I.A^[WB + X0] * W10 +
        I.A^[WB + X1] * W11 + 32768) Shr 16;
 End
 Else A := 255;
End;

{ Redimensionnement bilineaire (agrandissement ou reduction legere) }
Procedure ImgResizeBilin(Var Src, Dst: TImg);
Var
 X, Y, R, G, B, A: LongInt;
 SX, SY: Real;
Begin
 For Y := 0 To Dst.H - 1 Do Begin
  SY := (Y + 0.5) * Src.H / Dst.H - 0.5;
  For X := 0 To Dst.W - 1 Do Begin
   SX := (X + 0.5) * Src.W / Dst.W - 0.5;
   Bilin(Src, RoundL(SX * 65536), RoundL(SY * 65536), R, G, B, A);
   Dst.D^[(Y * Dst.W + X) * 3] := R;
   Dst.D^[(Y * Dst.W + X) * 3 + 1] := G;
   Dst.D^[(Y * Dst.W + X) * 3 + 2] := B;
  End;
 End;
End;

Procedure ImgResize(Var Src, Dst: TImg);
Begin
 If (Src.D = Nil) Or (Dst.D = Nil) Then Exit;
 If (Dst.W <= Src.W) And (Dst.H <= Src.H) Then ImgResizeBox(Src, Dst)
                                          Else ImgResizeBilin(Src, Dst);
End;

{ Conversion RVB -> YCbCr (entiers) }
Procedure RgbToYcc(R, G, B: LongInt; Var Y, Cb, Cr: LongInt);
Begin
 Y := (77 * R + 150 * G + 29 * B) Shr 8;
 Cb := ((-43 * R - 85 * G + 128 * B + 32768) Shr 8) + 0;
 Cr := ((128 * R - 107 * G - 21 * B + 32768) Shr 8) + 0;
End;

{ ---------------------------------------------------------------------- }
{ Camera : Video for Windows (WINDOWS) / Video4Linux2 (LINUX) / mire       }
{ Aucune unite supplementaire : les API sont declarees directement.        }
{ ---------------------------------------------------------------------- }

Const
 FMT_RGB24 = 1;      { octets R, V, B en memoire }
 FMT_BGR24 = 2;      { octets B, V, R en memoire (DIB Windows) }
 FMT_BGRA32 = 3;
 FMT_YUYV = 4;
 FMT_UYVY = 5;
 FMT_MJPEG = 6;

Var
 SynT: LongInt;
 Seed: LongInt;

Function Rnd(N: LongInt): LongInt;
Begin
 Seed := (Seed * 1103515 + 12345) And $7FFFFFFF;
 Rnd := (Seed Shr 8) Mod N;
End;

{ Convertit une trame brute de la camera en image FW x FH (RVB).
  Si la camera est plus definie que la trame de travail, chaque pixel est
  la moyenne de plusieurs echantillons (et non un simple sous-echantillon). }
Function RawToFrame(Raw: PByteArr; RawLen, SW, SH: LongInt; Fmt: Integer;
                    BottomUp: Boolean; Var Fr: TImg): Boolean;
Var
 X, Y, KX, KY, IX, IY, SX, SY, P, N, SR, SG, SB: LongInt;
 Stride, CW, CH, OX, OY: LongInt;
 Tmp: TImg;
 Err: String;
 Mjpg: Boolean;
 R, G, B: LongInt;

 { Couleur du pixel (X, Y) de la trame brute }
 Procedure Pix(PX, PY: LongInt; Var R, G, B: LongInt);
 Var
  Y0, U, V, YY, Off, Q: LongInt;
 Begin
  If Mjpg Then Begin
   Q := (PY * Tmp.W + PX) * 3;
   R := Tmp.D^[Q]; G := Tmp.D^[Q + 1]; B := Tmp.D^[Q + 2];
   Exit;
  End;
  If BottomUp Then YY := SH - 1 - PY Else YY := PY;
  Case Fmt Of
   FMT_BGR24: Begin
    Q := YY * Stride + PX * 3;
    B := Raw^[Q]; G := Raw^[Q + 1]; R := Raw^[Q + 2];
   End;
   FMT_RGB24: Begin
    Q := YY * Stride + PX * 3;
    R := Raw^[Q]; G := Raw^[Q + 1]; B := Raw^[Q + 2];
   End;
   FMT_BGRA32: Begin
    Q := YY * Stride + PX * 4;
    B := Raw^[Q]; G := Raw^[Q + 1]; R := Raw^[Q + 2];
   End;
  Else Begin
   Off := YY * Stride + (PX And (Not 1)) * 2;
   If Fmt = FMT_YUYV Then Begin
    If (PX And 1) = 0 Then Y0 := Raw^[Off] Else Y0 := Raw^[Off + 2];
    U := Raw^[Off + 1];
    V := Raw^[Off + 3];
   End
   Else Begin
    If (PX And 1) = 0 Then Y0 := Raw^[Off + 1] Else Y0 := Raw^[Off + 3];
    U := Raw^[Off];
    V := Raw^[Off + 2];
   End;
   R := Y0 + (359 * (V - 128)) Div 256;
   G := Y0 - (88 * (U - 128) + 183 * (V - 128)) Div 256;
   B := Y0 + (454 * (U - 128)) Div 256;
  End;
  End;
 End;

Begin
 RawToFrame := False;
 If (Raw = Nil) Or (Fr.D = Nil) Or (SW < 1) Or (SH < 1) Then Exit;
 Mjpg := Fmt = FMT_MJPEG;
 Tmp.D := Nil;
 Tmp.A := Nil;
 If Mjpg Then Begin
  {$IFDEF FPC}
  If Not JpegDecodeMem(Raw, RawLen, Tmp, Err) Then Exit;
  SW := Tmp.W;
  SH := Tmp.H;
  {$ELSE}
  Exit;
  {$ENDIF}
 End
 Else Begin
  Case Fmt Of
   FMT_RGB24, FMT_BGR24: Stride := ((SW * 3 + 3) Div 4) * 4;
   FMT_BGRA32: Stride := SW * 4;
  Else Stride := SW * 2;
  End;
  If RawLen < Stride * SH - 4 Then Exit;
 End;
 { nombre d'echantillons par pixel de la trame, par axe (1 a 3) }
 { recadrage centre pour conserver les proportions de la trame }
 CW := SW;
 CH := SH;
 OX := 0;
 OY := 0;
 If SW * FH > SH * FW Then Begin
  CW := SH * FW Div FH;
  OX := (SW - CW) Div 2;
 End
 Else If SW * FH < SH * FW Then Begin
  CH := SW * FH Div FW;
  OY := (SH - CH) Div 2;
 End;
 KX := IMax(1, IMin(3, CW Div FW));
 KY := IMax(1, IMin(3, CH Div FH));
 For Y := 0 To FH - 1 Do
  For X := 0 To FW - 1 Do Begin
   SR := 0; SG := 0; SB := 0; N := 0;
   For IY := 0 To KY - 1 Do
    For IX := 0 To KX - 1 Do Begin
     SX := OX + (X * CW + ((2 * IX + 1) * CW) Div (2 * KX)) Div FW;
     SY := OY + (Y * CH + ((2 * IY + 1) * CH) Div (2 * KY)) Div FH;
     If SX >= SW Then SX := SW - 1;
     If SY >= SH Then SY := SH - 1;
     Pix(SX, SY, R, G, B);
     Inc(SR, R); Inc(SG, G); Inc(SB, B); Inc(N);
    End;
   P := (Y * FW + X) * 3;
   Fr.D^[P] := Clip8(SR Div N);
   Fr.D^[P + 1] := Clip8(SG Div N);
   Fr.D^[P + 2] := Clip8(SB Div N);
  End;
 If Mjpg Then ImgFree(Tmp);
 RawToFrame := True;
End;

{ --- Mire de test : un visage anime sur fond sombre --- }

Procedure FillOval(Var Fr: TImg; CX, CY, RX, RY: Real; R, G, B: Integer;
                   Soft: Real);
Var
 X, Y, X1, X2, Y1, Y2, P: LongInt;
 DX, DY, D, A: Real;
Begin
 If (RX < 0.5) Or (RY < 0.5) Then Exit;
 X1 := IMax(0, Trunc(CX - RX - 2));
 X2 := IMin(FW - 1, Trunc(CX + RX + 2));
 Y1 := IMax(0, Trunc(CY - RY - 2));
 Y2 := IMin(FH - 1, Trunc(CY + RY + 2));
 For Y := Y1 To Y2 Do
  For X := X1 To X2 Do Begin
   DX := (X - CX) / RX;
   DY := (Y - CY) / RY;
   D := DX * DX + DY * DY;
   If D < 1.0 Then Begin
    A := 1.0;
    If D > 1.0 - Soft Then A := (1.0 - D) / Soft;
    P := (Y * FW + X) * 3;
    Fr.D^[P] := Round(Fr.D^[P] * (1 - A) + R * A);
    Fr.D^[P + 1] := Round(Fr.D^[P + 1] * (1 - A) + G * A);
    Fr.D^[P + 2] := Round(Fr.D^[P + 2] * (1 - A) + B * A);
   End;
  End;
End;

Procedure SynthFrame(Var Fr: TImg; T: LongInt);
Var
 X, Y, P, N: LongInt;
 CX, CY, S, Mo, Ex, Ey, Bl: Real;
Begin
 S := FW / 320.0;
 For Y := 0 To FH - 1 Do
  For X := 0 To FW - 1 Do Begin
   P := (Y * FW + X) * 3;
   Fr.D^[P] := 38 + Y * 20 Div FH;
   Fr.D^[P + 1] := 32 + Y * 16 Div FH;
   Fr.D^[P + 2] := 30 + Y * 12 Div FH;
  End;
 CX := FW / 2 + 36 * S * Sin(T / 37.0);
 CY := FH * 0.46 + 5 * S * Sin(T / 23.0);
 { epaules (chemise rouge), cou, cheveux, tete }
 FillOval(Fr, CX, FH + 10 * S, 120 * S, 62 * S, 170, 35, 38, 0.1);
 FillOval(Fr, CX, CY + 66 * S, 24 * S, 34 * S, 205, 150, 120, 0.2);
 FillOval(Fr, CX, CY - 18 * S, 56 * S, 62 * S, 48, 34, 28, 0.15);
 FillOval(Fr, CX, CY, 51 * S, 66 * S, 228, 176, 146, 0.12);
 FillOval(Fr, CX, CY - 52 * S, 51 * S, 20 * S, 48, 34, 28, 0.3);
 { oreilles }
 FillOval(Fr, CX - 51 * S, CY + 2 * S, 7 * S, 13 * S, 214, 160, 130, 0.3);
 FillOval(Fr, CX + 51 * S, CY + 2 * S, 7 * S, 13 * S, 214, 160, 130, 0.3);
 { yeux }
 Ey := CY - 8 * S;
 Bl := 1.0;
 If (T Mod 70) < 4 Then Bl := 0.2;
 For N := -1 To 1 Do
  If N <> 0 Then Begin
   Ex := CX + N * 20 * S;
   FillOval(Fr, Ex, Ey, 10 * S, 6 * S * Bl, 245, 245, 245, 0.3);
   FillOval(Fr, Ex + N * 0.5 * S, Ey, 4.4 * S, 4.4 * S * Bl, 56, 38, 30, 0.3);
   FillOval(Fr, Ex, Ey - 12 * S, 12 * S, 2.6 * S, 52, 36, 28, 0.5);
  End;
 { nez et bouche }
 FillOval(Fr, CX, CY + 14 * S, 6 * S, 10 * S, 214, 154, 126, 0.5);
 Mo := 2.5 + 7 * Abs(Sin(T / 8.0));
 FillOval(Fr, CX, CY + 38 * S, 17 * S, Mo * S, 150, 40, 48, 0.4);
 If Mo > 6 Then
  FillOval(Fr, CX, CY + 38 * S, 11 * S, (Mo - 4) * S, 60, 12, 20, 0.4);
 { bruit du capteur }
 For N := 1 To FW * FH Div 3 Do Begin
  P := Rnd(FW * FH) * 3;
  Fr.D^[P] := Clip8(Fr.D^[P] + Rnd(9) - 4);
  Fr.D^[P + 1] := Clip8(Fr.D^[P + 1] + Rnd(9) - 4);
  Fr.D^[P + 2] := Clip8(Fr.D^[P + 2] + Rnd(9) - 4);
 End;
End;

Function PCharToStr(P: PChar): String;
Var
 S: String;
 I: Integer;
Begin
 S := '';
 I := 0;
 While (P[I] <> #0) And (I < 60) Do Begin
  S := S + P[I];
  Inc(I);
 End;
 PCharToStr := S;
End;

{$IFDEF WINDOWS}
{ ---- Windows : DirectShow (cameras reelles et virtuelles) puis Video for
  Windows (avicap32.dll) en secours ---- }
Const
 WM_CAP_START = $0400;
 WM_CAP_DRIVER_CONNECT = WM_CAP_START + 10;
 WM_CAP_DRIVER_DISCONNECT = WM_CAP_START + 11;
 WM_CAP_SET_CALLBACK_FRAME = WM_CAP_START + 5;
 WM_CAP_GET_VIDEOFORMAT = WM_CAP_START + 44;
 WM_CAP_SET_VIDEOFORMAT = WM_CAP_START + 45;
 WM_CAP_SET_PREVIEW = WM_CAP_START + 50;
 WM_CAP_SET_OVERLAY = WM_CAP_START + 51;
 WM_CAP_GRAB_FRAME_NOSTOP = WM_CAP_START + 61;
 WS_POPUP = $80000000;
 FOURCC_YUY2 = $32595559;
 FOURCC_UYVY = $59565955;
 FOURCC_MJPG = $47504A4D;

Type
 PVideoHdr = ^TVideoHdr;
 TVideoHdr = Record
  lpData: PByte;
  dwBufferLength: LongWord;
  dwBytesUsed: LongWord;
  dwTimeCaptured: LongWord;
  dwUser: PtrUInt;
  dwFlags: LongWord;
  dwReserved: Array[0..3] Of PtrUInt;
 End;
 TBmpInfoHdr = Record
  biSize: LongWord;
  biWidth: LongInt;
  biHeight: LongInt;
  biPlanes: Word;
  biBitCount: Word;
  biCompression: LongWord;
  biSizeImage: LongWord;
  biXPelsPerMeter: LongInt;
  biYPelsPerMeter: LongInt;
  biClrUsed: LongWord;
  biClrImportant: LongWord;
  Extra: Array[0..1023] Of Byte;
 End;

Function capCreateCaptureWindowA(Name: PChar; Style: LongWord;
  X, Y, W, H: LongInt; Parent: PtrUInt; Id: LongInt): PtrUInt; stdcall;
  external 'avicap32.dll' name 'capCreateCaptureWindowA';
Function capGetDriverDescriptionA(Idx: Word; Name: PChar; NameLen: LongInt;
  Desc: PChar; DescLen: LongInt): LongBool; stdcall;
  external 'avicap32.dll' name 'capGetDriverDescriptionA';
Function SendMessageA(Wnd: PtrUInt; Msg: LongWord; WP: PtrUInt;
  LP: PtrInt): PtrInt; stdcall; external 'user32.dll' name 'SendMessageA';
Function DestroyWindow(Wnd: PtrUInt): LongBool; stdcall;
  external 'user32.dll' name 'DestroyWindow';

Var
 CapWnd: PtrUInt;
 CamRaw: PByteArr;
 CamRawCap, CamRawLen: LongInt;
 CamCBOk: Boolean;
 CamW, CamH, CamFmt: LongInt;
 CamBottomUp: Boolean;

Function CamFrameCB(Wnd: PtrUInt; Hdr: PVideoHdr): PtrInt; stdcall;
Begin
 CamFrameCB := 0;
 If (Hdr = Nil) Or (Hdr^.lpData = Nil) Or (Hdr^.dwBytesUsed = 0) Then Exit;
 If (CamRaw = Nil) Or (CamRawCap < LongInt(Hdr^.dwBytesUsed)) Then Begin
  If CamRaw <> Nil Then FreeMem(CamRaw, CamRawCap);
  CamRawCap := Hdr^.dwBytesUsed + 4096;
  CamRaw := PByteArr(MemAlloc(CamRawCap));
  If CamRaw = Nil Then Begin CamRawCap := 0; Exit; End;
 End;
 Move(Hdr^.lpData^, CamRaw^, Hdr^.dwBytesUsed);
 CamRawLen := Hdr^.dwBytesUsed;
 CamCBOk := True;
End;

Procedure VfwEnumerate;
Var
 I: Integer;
 NameBuf, VerBuf: Array[0..127] Of Char;
Begin
 NCams := 0;
 For I := 0 To 9 Do
  If NCams < MAX_CAMS - 1 Then
   If capGetDriverDescriptionA(I, @NameBuf, 120, @VerBuf, 120) Then Begin
    Cams[NCams].Kind := SRC_VFW;
    Cams[NCams].Idx := I;
    Cams[NCams].Name := PCharToStr(@NameBuf);
    Inc(NCams);
   End;
End;

Function VfwOpen(Idx: Integer): Boolean;
Var
 Bih: TBmpInfoHdr;
 R: PtrInt;
Begin
 VfwOpen := False;
 CapWnd := capCreateCaptureWindowA('TMF', WS_POPUP, 0, 0, FW, FH, 0, 0);
 If CapWnd = 0 Then Exit;
 If SendMessageA(CapWnd, WM_CAP_DRIVER_CONNECT, Idx, 0) = 0 Then Begin
  DestroyWindow(CapWnd);
  CapWnd := 0;
  Exit;
 End;
 SendMessageA(CapWnd, WM_CAP_SET_PREVIEW, 0, 0);
 SendMessageA(CapWnd, WM_CAP_SET_OVERLAY, 0, 0);
 SendMessageA(CapWnd, WM_CAP_SET_CALLBACK_FRAME, 0, PtrInt(@CamFrameCB));
 { on demande du RVB 24 bits a la taille de la trame }
 FillChar(Bih, SizeOf(Bih), 0);
 Bih.biSize := 40;
 Bih.biWidth := CamReqW;
 Bih.biHeight := CamReqH;
 Bih.biPlanes := 1;
 Bih.biBitCount := 24;
 Bih.biSizeImage := CamReqW * CamReqH * 3;
 SendMessageA(CapWnd, WM_CAP_SET_VIDEOFORMAT, 40, PtrInt(@Bih));
 FillChar(Bih, SizeOf(Bih), 0);
 R := SendMessageA(CapWnd, WM_CAP_GET_VIDEOFORMAT, SizeOf(Bih),
                   PtrInt(@Bih));
 If R = 0 Then Begin
  SendMessageA(CapWnd, WM_CAP_DRIVER_DISCONNECT, 0, 0);
  DestroyWindow(CapWnd);
  CapWnd := 0;
  Exit;
 End;
 CamW := Bih.biWidth;
 CamH := Bih.biHeight;
 CamBottomUp := CamH > 0;
 If CamH < 0 Then CamH := -CamH;
 CamFmt := 0;
 If Bih.biCompression = 0 Then Begin
  If Bih.biBitCount = 24 Then CamFmt := FMT_BGR24
  Else If Bih.biBitCount = 32 Then CamFmt := FMT_BGRA32;
 End
 Else If Bih.biCompression = FOURCC_YUY2 Then CamFmt := FMT_YUYV
 Else If Bih.biCompression = FOURCC_UYVY Then CamFmt := FMT_UYVY
 Else If Bih.biCompression = FOURCC_MJPG Then CamFmt := FMT_MJPEG;
 If CamFmt = 0 Then Begin
  SendMessageA(CapWnd, WM_CAP_DRIVER_DISCONNECT, 0, 0);
  DestroyWindow(CapWnd);
  CapWnd := 0;
  Exit;
 End;
 VfwOpen := True;
End;

Procedure VfwClose;
Begin
 If CapWnd <> 0 Then Begin
  SendMessageA(CapWnd, WM_CAP_SET_CALLBACK_FRAME, 0, 0);
  SendMessageA(CapWnd, WM_CAP_DRIVER_DISCONNECT, 0, 0);
  DestroyWindow(CapWnd);
  CapWnd := 0;
 End;
 If CamRaw <> Nil Then FreeMem(CamRaw, CamRawCap);
 CamRaw := Nil;
 CamRawCap := 0;
End;

Function VfwGrab(Var Fr: TImg): Boolean;
Begin
 VfwGrab := False;
 If CapWnd = 0 Then Exit;
 CamCBOk := False;
 SendMessageA(CapWnd, WM_CAP_GRAB_FRAME_NOSTOP, 0, 0);
 If CamCBOk Then
  VfwGrab := RawToFrame(CamRaw, CamRawLen, CamW, CamH, CamFmt,
                        CamBottomUp, Fr);
End;

{ ---- DirectShow par appels COM directs (tables virtuelles) ---- }
Const
 CLSID_SystemDeviceEnum: TGUID = (D1: $62BE5D10; D2: $60EB; D3: $11D0;
  D4: ($BD, $3B, $00, $A0, $C9, $11, $CE, $86));
 CLSID_VideoInputDeviceCategory: TGUID = (D1: $860BB310; D2: $5D01; D3: $11D0;
  D4: ($BD, $3B, $00, $A0, $C9, $11, $CE, $86));
 IID_ICreateDevEnum: TGUID = (D1: $29840822; D2: $5B84; D3: $11D0;
  D4: ($BD, $3B, $00, $A0, $C9, $11, $CE, $86));
 IID_IPropertyBag: TGUID = (D1: $55272A00; D2: $42CB; D3: $11CE;
  D4: ($81, $35, $00, $AA, $00, $4B, $3F, $73));
 IID_IBaseFilter: TGUID = (D1: $56A86895; D2: $0AD4; D3: $11CE;
  D4: ($B0, $3A, $00, $20, $AF, $0B, $A7, $70));
 CLSID_FilterGraph: TGUID = (D1: $E436EBB3; D2: $524F; D3: $11CE;
  D4: ($9F, $53, $00, $20, $AF, $0B, $A7, $70));
 IID_IGraphBuilder: TGUID = (D1: $56A868A9; D2: $0AD4; D3: $11CE;
  D4: ($B0, $3A, $00, $20, $AF, $0B, $A7, $70));
 IID_IMediaControl: TGUID = (D1: $56A868B1; D2: $0AD4; D3: $11CE;
  D4: ($B0, $3A, $00, $20, $AF, $0B, $A7, $70));
 CLSID_CaptureGraphBuilder2: TGUID = (D1: $BF87B6E1; D2: $8C27; D3: $11D0;
  D4: ($B3, $F0, $00, $AA, $00, $37, $61, $C5));
 IID_ICaptureGraphBuilder2: TGUID = (D1: $93E5A4E0; D2: $2D50; D3: $11D2;
  D4: ($AB, $FA, $00, $A0, $C9, $C6, $E3, $8D));
 CLSID_SampleGrabber: TGUID = (D1: $C1F400A0; D2: $3F08; D3: $11D3;
  D4: ($9F, $0B, $00, $60, $08, $03, $9E, $37));
 CLSID_NullRenderer: TGUID = (D1: $C1F400A4; D2: $3F08; D3: $11D3;
  D4: ($9F, $0B, $00, $60, $08, $03, $9E, $37));
 IID_ISampleGrabber: TGUID = (D1: $6B652FFF; D2: $11FE; D3: $4FCE;
  D4: ($92, $AD, $02, $66, $B5, $D7, $C7, $8F));
 PIN_CATEGORY_CAPTURE: TGUID = (D1: $FB6C4281; D2: $0353; D3: $11D1;
  D4: ($90, $5F, $00, $00, $C0, $CC, $16, $BA));
 PIN_CATEGORY_PREVIEW: TGUID = (D1: $FB6C4282; D2: $0353; D3: $11D1;
  D4: ($90, $5F, $00, $00, $C0, $CC, $16, $BA));
 MEDIATYPE_Video: TGUID = (D1: $73646976; D2: $0000; D3: $0010;
  D4: ($80, $00, $00, $AA, $00, $38, $9B, $71));
 MEDIASUBTYPE_RGB24: TGUID = (D1: $E436EB7D; D2: $524F; D3: $11CE;
  D4: ($9F, $53, $00, $20, $AF, $0B, $A7, $70));
 FORMAT_VideoInfo2_D1 = $F72A76A0;

Type
 TDsVT = Array[0..63] Of Pointer;
 PDsVT = ^TDsVT;
 PPDsVT = ^PDsVT;
 TDsF0 = Function(S: Pointer): LongInt; stdcall;
 TDsF1 = Function(S: Pointer; A: PtrUInt): LongInt; stdcall;
 TDsF2 = Function(S: Pointer; A, B: PtrUInt): LongInt; stdcall;
 TDsF3 = Function(S: Pointer; A, B, C: PtrUInt): LongInt; stdcall;
 TDsF4 = Function(S: Pointer; A, B, C, D: PtrUInt): LongInt; stdcall;
 TDsF5 = Function(S: Pointer; A, B, C, D, E: PtrUInt): LongInt; stdcall;
 TDsVariant = Record
  Vt: Word;
  R1, R2, R3: Word;
  P: Pointer;
  P2: Pointer;
 End;
 TDsMediaType = Record
  Major, Sub: TGUID;
  FixedSize, TemporalComp: LongInt;
  SampleSize: LongWord;
  FormatType: TGUID;
  Unk: Pointer;
  CbFormat: LongWord;
  PbFormat: Pointer;
 End;

Function CoInitialize(Res: Pointer): LongInt; stdcall;
  external 'ole32.dll' name 'CoInitialize';
Function CoCreateInstance(Clsid: Pointer; Outer: Pointer; Ctx: LongWord;
  Iid: Pointer; Obj: Pointer): LongInt; stdcall;
  external 'ole32.dll' name 'CoCreateInstance';
Procedure CoTaskMemFree(P: Pointer); stdcall;
  external 'ole32.dll' name 'CoTaskMemFree';
Function CreateBindCtx(Res: LongWord; Var Ctx: Pointer): LongInt; stdcall;
  external 'ole32.dll' name 'CreateBindCtx';
Function RegOpenKeyExA(Root: PtrUInt; Sub: PChar; Opt, Sam: LongWord;
  Var Res: PtrUInt): LongInt; stdcall;
  external 'advapi32.dll' name 'RegOpenKeyExA';
Function RegQueryValueExA(Key: PtrUInt; Name: PChar; Res: Pointer;
  Typ: Pointer; Data: Pointer; Size: Pointer): LongInt; stdcall;
  external 'advapi32.dll' name 'RegQueryValueExA';
Function RegCloseKey(Key: PtrUInt): LongInt; stdcall;
  external 'advapi32.dll' name 'RegCloseKey';
Procedure SysFreeString(P: Pointer); stdcall;
  external 'oleaut32.dll' name 'SysFreeString';

Var
 DsGraph, DsCgb, DsSrc, DsGrabF, DsNullF, DsGrab, DsCtl: Pointer;
 DsComOk: Boolean;
 DsNum: Integer;

Function DsM(O: Pointer; N: Integer): Pointer;
Begin
 DsM := PPDsVT(O)^^[N];
End;

Procedure DsRel(Var O: Pointer);
Begin
 If O <> Nil Then TDsF0(DsM(O, 2))(O);
 O := Nil;
End;

Function DsMake(Const Clsid, Iid: TGUID; Var Obj: Pointer): Boolean;
Begin
 Obj := Nil;
 DsMake := CoCreateInstance(@Clsid, Nil, 1, @Iid, @Obj) = 0;
 If Not DsMake Then Obj := Nil;
End;

Procedure DsComInit;
Begin
 If Not DsComOk Then Begin
  CoInitialize(Nil);
  DsComOk := True;
 End;
End;

{ Valeur texte de HKEY_LOCAL_MACHINE\Sub\Name (chaine vide si absente) }
Function DsRegStr(Const Sub, Name: String): String;
Var
 H: PtrUInt;
 Buf: Array[0..255] Of Char;
 Sz: LongWord;
 P: Integer;
 R, ZS, ZN: String;
Begin
 DsRegStr := '';
 ZS := Sub + #0;
 ZN := Name + #0;
 If RegOpenKeyExA($80000002, PChar(@ZS[1]), 0, $20019, H) <> 0 Then Exit;
 FillChar(Buf, SizeOf(Buf), 0);
 Sz := 255;
 R := '';
 If RegQueryValueExA(H, PChar(@ZN[1]), Nil, Nil, @Buf, @Sz) = 0 Then
  R := PCharToStr(@Buf);
 RegCloseKey(H);
 { "@oem12.inf,%desc%;Nom reel" : on garde ce qui suit le dernier ';' }
 If (Length(R) > 0) And (R[1] = '@') Then Begin
  P := Length(R);
  While (P > 0) And (R[P] <> ';') Do Dec(P);
  If P > 0 Then R := Copy(R, P + 1, 255);
 End;
 DsRegStr := R;
End;

{ Nom convivial d'un peripherique a partir de son nom d'affichage :
  '@device:sw:{categorie}\{guid}'  -> HKLM\...\CLSID\{categorie}\Instance
  '@device:pnp:\?\bus#materiel#instance#{...}' -> HKLM\...\Enum }
Function DsDisplayToName(Const D: String): String;
Var
 P, Q: Integer;
 Sub, Bus, Hw, Inst, R: String;
Begin
 DsDisplayToName := '';
 If Pos('@device:sw:', D) = 1 Then Begin
  P := Pos('\', D);
  If P = 0 Then Exit;
  Sub := 'SOFTWARE\Classes\CLSID\' + Copy(D, 12, P - 12) + '\Instance\' +
         Copy(D, P + 1, 80);
  DsDisplayToName := DsRegStr(Sub, 'FriendlyName');
 End
 Else If Pos('@device:pnp:', D) = 1 Then Begin
  P := Pos('?\', D);
  If P = 0 Then Exit;
  R := Copy(D, P + 2, 250);
  Q := Pos('#', R);
  If Q = 0 Then Exit;
  Bus := Copy(R, 1, Q - 1);
  Delete(R, 1, Q);
  Q := Pos('#', R);
  If Q = 0 Then Exit;
  Hw := Copy(R, 1, Q - 1);
  Delete(R, 1, Q);
  Q := Pos('#', R);
  If Q = 0 Then Exit;
  Inst := Copy(R, 1, Q - 1);
  Sub := 'SYSTEM\CurrentControlSet\Enum\' + Bus + '\' + Hw + '\' + Inst;
  R := DsRegStr(Sub, 'FriendlyName');
  If R = '' Then R := DsRegStr(Sub, 'DeviceDesc');
  DsDisplayToName := R;
 End;
End;

{ Enumere les peripheriques video DirectShow. Si Want >= 0, retourne le filtre
  (IBaseFilter) du peripherique numero Want dans Flt ; sinon ajoute les noms
  a la liste des cameras (Kind = SRC_DSHOW, Idx = numero). }
Procedure DsScan(Want: Integer; Var Flt: Pointer);
Var
 DevEnum, EnumM, Mon, Bag, Bind, Disp: Pointer;
 V: TDsVariant;
 N: Integer;
 Nm: String;
 Wn: WideString;
 Got: Boolean;
Begin
 Flt := Nil;
 DsComInit;
 DevEnum := Nil;
 EnumM := Nil;
 If Not DsMake(CLSID_SystemDeviceEnum, IID_ICreateDevEnum, DevEnum) Then Exit;
 { CreateClassEnumerator : S_FALSE (1) et EnumM = Nil s'il n'y a aucun
   peripherique }
 If TDsF3(DsM(DevEnum, 3))(DevEnum, PtrUInt(@CLSID_VideoInputDeviceCategory),
                           PtrUInt(@EnumM), 0) = 0 Then Begin
  If EnumM <> Nil Then Begin
   N := 0;
   Mon := Nil;
   While (N < 32) And (TDsF3(DsM(EnumM, 3))(EnumM, 1, PtrUInt(@Mon), 0) = 0)
         And (Mon <> Nil) Do Begin
    If Want >= 0 Then Begin
     If N = Want Then Begin
      { BindToObject (methode 8) }
      If TDsF4(DsM(Mon, 8))(Mon, 0, 0, PtrUInt(@IID_IBaseFilter),
                            PtrUInt(@Flt)) <> 0 Then Flt := Nil;
     End;
    End
    Else If NCams < MAX_CAMS - 1 Then Begin
     Bag := Nil;
     Nm := '';
     { BindToStorage (methode 9) vers IPropertyBag }
     If TDsF4(DsM(Mon, 9))(Mon, 0, 0, PtrUInt(@IID_IPropertyBag),
                           PtrUInt(@Bag)) = 0 Then Begin
      FillChar(V, SizeOf(V), 0);
      V.Vt := 8;  { VT_BSTR }
      Wn := 'FriendlyName';
      Got := TDsF3(DsM(Bag, 3))(Bag, PtrUInt(PWideChar(Wn)), PtrUInt(@V),
                                0) = 0;
      If Got And (V.Vt = 8) And (V.P <> Nil) Then Begin
       Nm := String(WideString(PWideChar(V.P)));
       SysFreeString(V.P);
      End;
      DsRel(Bag);
     End;
     If Nm = '' Then Begin
      { le sac de proprietes n'est pas toujours disponible : on passe par le
        nom d'affichage du moniker (GetDisplayName, methode 20) }
      Bind := Nil;
      CreateBindCtx(0, Bind);
      Disp := Nil;
      If Bind <> Nil Then Begin
       If TDsF3(DsM(Mon, 20))(Mon, PtrUInt(Bind), 0, PtrUInt(@Disp)) = 0 Then
        If Disp <> Nil Then Begin
         Nm := DsDisplayToName(String(WideString(PWideChar(Disp))));
         CoTaskMemFree(Disp);
        End;
       DsRel(Bind);
      End;
     End;
     If Nm = '' Then Nm := 'Camera ' + IStr(N + 1);
     Cams[NCams].Kind := SRC_DSHOW;
     Cams[NCams].Idx := N;
     Cams[NCams].Name := Nm;
     Inc(NCams);
    End;
    DsRel(Mon);
    If (Want >= 0) And (Flt <> Nil) Then Break;
    Inc(N);
    Mon := Nil;
   End;
   DsRel(Mon);
   DsRel(EnumM);
  End;
 End;
 DsRel(DevEnum);
End;

Procedure DsClose;
Begin
 If DsCtl <> Nil Then TDsF0(DsM(DsCtl, 9))(DsCtl);  { Stop }
 DsRel(DsCtl);
 DsRel(DsGrab);
 DsRel(DsGrabF);
 DsRel(DsNullF);
 DsRel(DsSrc);
 DsRel(DsCgb);
 DsRel(DsGraph);
 If CamRaw <> Nil Then FreeMem(CamRaw, CamRawCap);
 CamRaw := Nil;
 CamRawCap := 0;
End;

{ Copie l'image courante du Sample Grabber (RVB 24 bits) dans CamRaw }
Function DsFetch(Var Sz: LongInt): Boolean;
Begin
 DsFetch := False;
 If DsGrab = Nil Then Exit;
 Sz := 0;
 { GetCurrentBuffer (methode 7) : taille puis donnees }
 If TDsF2(DsM(DsGrab, 7))(DsGrab, PtrUInt(@Sz), 0) <> 0 Then Exit;
 If Sz <= 0 Then Exit;
 If (CamRaw = Nil) Or (CamRawCap < Sz) Then Begin
  If CamRaw <> Nil Then FreeMem(CamRaw, CamRawCap);
  CamRawCap := Sz + 4096;
  CamRaw := PByteArr(MemAlloc(CamRawCap));
  If CamRaw = Nil Then Begin CamRawCap := 0; Exit; End;
 End;
 DsFetch := TDsF2(DsM(DsGrab, 7))(DsGrab, PtrUInt(@Sz),
                                  PtrUInt(CamRaw)) = 0;
End;

Function DsOpen(Idx: Integer): Boolean;
Var
 Mt: TDsMediaType;
 Hr, Sz, T0, Off: LongInt;
 Bh: PByteArr;
 Ok: Boolean;
Begin
 DsOpen := False;
 DsGraph := Nil; DsCgb := Nil; DsSrc := Nil; DsGrabF := Nil; DsNullF := Nil;
 DsGrab := Nil; DsCtl := Nil;
 DsComInit;
 DsScan(Idx, DsSrc);
 If DsSrc = Nil Then Exit;
 Ok := DsMake(CLSID_FilterGraph, IID_IGraphBuilder, DsGraph) And
       DsMake(CLSID_CaptureGraphBuilder2, IID_ICaptureGraphBuilder2, DsCgb) And
       DsMake(CLSID_SampleGrabber, IID_IBaseFilter, DsGrabF) And
       DsMake(CLSID_NullRenderer, IID_IBaseFilter, DsNullF);
 If Ok Then Begin
  { SetFiltergraph (3) ; AddFilter (3) du graphe }
  TDsF1(DsM(DsCgb, 3))(DsCgb, PtrUInt(DsGraph));
  Ok := TDsF2(DsM(DsGraph, 3))(DsGraph, PtrUInt(DsSrc),
                               PtrUInt(PWideChar(WideString('Camera')))) >= 0;
 End;
 If Ok Then Begin
  { QueryInterface (0) de ISampleGrabber }
  Ok := TDsF2(DsM(DsGrabF, 0))(DsGrabF, PtrUInt(@IID_ISampleGrabber),
                               PtrUInt(@DsGrab)) = 0;
 End;
 If Ok Then Begin
  FillChar(Mt, SizeOf(Mt), 0);
  Mt.Major := MEDIATYPE_Video;
  Mt.Sub := MEDIASUBTYPE_RGB24;
  { SetMediaType (4) ; SetBufferSamples (6) }
  TDsF1(DsM(DsGrab, 4))(DsGrab, PtrUInt(@Mt));
  TDsF1(DsM(DsGrab, 6))(DsGrab, 1);
  TDsF2(DsM(DsGraph, 3))(DsGraph, PtrUInt(DsGrabF),
                         PtrUInt(PWideChar(WideString('Grabber'))));
  TDsF2(DsM(DsGraph, 3))(DsGraph, PtrUInt(DsNullF),
                         PtrUInt(PWideChar(WideString('Null'))));
  { RenderStream (7) : capture, puis apercu, puis sans categorie }
  Hr := TDsF5(DsM(DsCgb, 7))(DsCgb, PtrUInt(@PIN_CATEGORY_CAPTURE),
         PtrUInt(@MEDIATYPE_Video), PtrUInt(DsSrc), PtrUInt(DsGrabF),
         PtrUInt(DsNullF));
  If Hr < 0 Then
   Hr := TDsF5(DsM(DsCgb, 7))(DsCgb, PtrUInt(@PIN_CATEGORY_PREVIEW),
          PtrUInt(@MEDIATYPE_Video), PtrUInt(DsSrc), PtrUInt(DsGrabF),
          PtrUInt(DsNullF));
  If Hr < 0 Then
   Hr := TDsF5(DsM(DsCgb, 7))(DsCgb, 0, PtrUInt(@MEDIATYPE_Video),
          PtrUInt(DsSrc), PtrUInt(DsGrabF), PtrUInt(DsNullF));
  Ok := Hr >= 0;
 End;
 If Ok Then Begin
  { format reellement negocie : GetConnectedMediaType (5) }
  FillChar(Mt, SizeOf(Mt), 0);
  Ok := TDsF1(DsM(DsGrab, 5))(DsGrab, PtrUInt(@Mt)) = 0;
  If Ok Then Begin
   If Mt.FormatType.D1 = FORMAT_VideoInfo2_D1 Then Off := 72 Else Off := 48;
   Ok := (Mt.PbFormat <> Nil) And (LongInt(Mt.CbFormat) >= Off + 40);
   If Ok Then Begin
    Bh := PByteArr(Mt.PbFormat);
    CamW := PLongInt(@Bh^[Off + 4])^;
    CamH := PLongInt(@Bh^[Off + 8])^;
    CamBottomUp := CamH > 0;
    If CamH < 0 Then CamH := -CamH;
    Ok := (CamW > 0) And (CamH > 0);
   End;
   If Mt.PbFormat <> Nil Then CoTaskMemFree(Mt.PbFormat);
   If Mt.Unk <> Nil Then DsRel(Mt.Unk);
  End;
 End;
 If Ok Then Begin
  { IMediaControl : QueryInterface (0), Run (7) }
  Ok := TDsF2(DsM(DsGraph, 0))(DsGraph, PtrUInt(@IID_IMediaControl),
                               PtrUInt(@DsCtl)) = 0;
  If Ok Then Ok := TDsF0(DsM(DsCtl, 7))(DsCtl) >= 0;
 End;
 If Ok Then Begin
  { attend la premiere image (3 s au maximum) }
  T0 := NowMs;
  Ok := False;
  Repeat
   If DsFetch(Sz) Then Ok := True
   Else Delay(40);
  Until Ok Or (Abs(NowMs - T0) > 3000);
 End;
 If Not Ok Then DsClose;
 DsOpen := Ok;
End;

Function DsGrabFrame(Var Fr: TImg): Boolean;
Var
 Sz: LongInt;
Begin
 DsGrabFrame := False;
 If DsFetch(Sz) Then
  DsGrabFrame := RawToFrame(CamRaw, Sz, CamW, CamH, FMT_BGR24, CamBottomUp,
                            Fr);
End;

Procedure CamEnumerate;
Var
 Dummy: Pointer;
Begin
 NCams := 0;
 DsScan(-1, Dummy);
 If NCams = 0 Then VfwEnumerate;
End;

Function CamOpen(Idx: Integer): Boolean;
Begin
 If CamKind = SRC_DSHOW Then CamOpen := DsOpen(Idx)
 Else CamOpen := VfwOpen(Idx);
End;

Procedure CamClose;
Begin
 If CamKind = SRC_DSHOW Then DsClose Else VfwClose;
End;

Function CamGrabReal(Var Fr: TImg): Boolean;
Begin
 If CamKind = SRC_DSHOW Then CamGrabReal := DsGrabFrame(Fr)
 Else CamGrabReal := VfwGrab(Fr);
End;
{$ENDIF}

{$IFDEF LINUX}
{ ---- Linux : Video4Linux2, appels directs a la libc ---- }
Const
 NBUF = 4;
 V4L2_BUF_TYPE_VIDEO_CAPTURE = 1;
 V4L2_MEMORY_MMAP = 1;
 V4L2_PIX_FMT_YUYV = $56595559;
 V4L2_PIX_FMT_UYVY = $59565955;
 V4L2_PIX_FMT_MJPEG = $47504A4D;
 V4L2_PIX_FMT_RGB24 = $33424752;
 V4L2_PIX_FMT_BGR24 = $33524742;
 PROT_RW = 3;
 MAP_SHARED = 1;
 O_RDWR = 2;

Type
 TV4LCap = Record
  Driver: Array[0..15] Of Char;
  Card: Array[0..31] Of Char;
  BusInfo: Array[0..31] Of Char;
  Version, Capabilities, DeviceCaps: LongWord;
  Reserved: Array[0..2] Of LongWord;
 End;
 TV4LFmt = Record
  FmtType: LongWord;
  {$IFDEF CPU64}
  Pad: LongWord;
  {$ENDIF}
  Width, Height, PixFmt, Field, BytesPerLine, SizeImage, ColorSpace: LongWord;
  Rest: Array[0..171] Of Byte;
 End;
 TV4LReq = Record
  Count, ReqType, Memory, Caps: LongWord;
  Flags: Byte;
  Reserved: Array[0..2] Of Byte;
 End;
 TV4LBuf = Record
  Index, BufType, BytesUsed, Flags, Field: LongWord;
  TsSec, TsUsec: PtrInt;
  TcType, TcFlags: LongWord;
  TcFrames, TcSec, TcMin, TcHour: Byte;
  TcUser: Array[0..3] Of Byte;
  Sequence, Memory: LongWord;
  MOffset: PtrUInt;
  Length: LongWord;
  Reserved2: LongWord;
  RequestFd: LongInt;
 End;
 TPollFd = Record
  Fd: LongInt;
  Events, REvents: SmallInt;
 End;

Function lc_open(Path: PChar; Flags: LongInt): LongInt; cdecl;
  external 'c' name 'open';
Function lc_close(Fd: LongInt): LongInt; cdecl; external 'c' name 'close';
Function lc_ioctl(Fd: LongInt; Req: PtrUInt; Arg: Pointer): LongInt; cdecl;
  external 'c' name 'ioctl';
Function lc_mmap(Addr: Pointer; Len: PtrUInt; Prot, Flags, Fd: LongInt;
  Off: PtrInt): Pointer; cdecl; external 'c' name 'mmap';
Function lc_munmap(Addr: Pointer; Len: PtrUInt): LongInt; cdecl;
  external 'c' name 'munmap';
Function lc_poll(Fds: Pointer; N: PtrUInt; Timeout: LongInt): LongInt;
  cdecl; external 'c' name 'poll';

Var
 VFd: LongInt;
 VMap: Array[0..NBUF - 1] Of Pointer;
 VLen: Array[0..NBUF - 1] Of LongInt;
 VW, VH, VFmtId: LongInt;
 VStream: Boolean;
 VCount: Integer;

{ _IOC(dir, 'V', nr, size) }
Function VIoc(Dir, Nr, Size: LongWord): PtrUInt;
Begin
 VIoc := (PtrUInt(Dir) Shl 30) Or (PtrUInt(Size) Shl 16) Or
         (PtrUInt(86) Shl 8) Or Nr;
End;

Procedure DevName(N: Integer; Var Buf: Array Of Char);
Var
 S: String;
 I: Integer;
Begin
 S := '/dev/video' + IStr(N);
 For I := 1 To Length(S) Do Buf[I - 1] := S[I];
 Buf[Length(S)] := #0;
End;

Procedure CamEnumerate;
Var
 I: Integer;
 Fd: LongInt;
 Cap: TV4LCap;
 Dev: Array[0..31] Of Char;
 Ok: Boolean;
Begin
 NCams := 0;
 For I := 0 To 9 Do
  If NCams < MAX_CAMS - 1 Then Begin
   DevName(I, Dev);
   Fd := lc_open(@Dev, O_RDWR);
   If Fd >= 0 Then Begin
    FillChar(Cap, SizeOf(Cap), 0);
    If lc_ioctl(Fd, VIoc(2, 0, SizeOf(Cap)), @Cap) = 0 Then Begin
     If (Cap.Capabilities And $80000000) <> 0 Then
      Ok := (Cap.DeviceCaps And 1) <> 0
     Else Ok := (Cap.Capabilities And 1) <> 0;
     If Ok Then Begin
      Cams[NCams].Kind := SRC_V4L2;
      Cams[NCams].Idx := I;
      Cams[NCams].Name := PCharToStr(@Cap.Card) + ' (/dev/video' +
                          IStr(I) + ')';
      Inc(NCams);
     End;
    End;
    lc_close(Fd);
   End;
  End;
End;

Procedure CamClose;
Var
 I: Integer;
 T: LongInt;
Begin
 If VFd >= 0 Then Begin
  If VStream Then Begin
   T := V4L2_BUF_TYPE_VIDEO_CAPTURE;
   lc_ioctl(VFd, VIoc(1, 19, 4), @T);
  End;
  For I := 0 To VCount - 1 Do
   If VMap[I] <> Nil Then lc_munmap(VMap[I], VLen[I]);
  lc_close(VFd);
 End;
 VFd := -1;
 VStream := False;
 VCount := 0;
End;

Function CamOpen(Idx: Integer): Boolean;
Var
 Dev: Array[0..31] Of Char;
 Fmt: TV4LFmt;
 Req: TV4LReq;
 Buf: TV4LBuf;
 I: Integer;
 T: LongInt;
 P: Pointer;
Begin
 CamOpen := False;
 DevName(Idx, Dev);
 VFd := lc_open(@Dev, O_RDWR);
 If VFd < 0 Then Exit;
 FillChar(Fmt, SizeOf(Fmt), 0);
 Fmt.FmtType := V4L2_BUF_TYPE_VIDEO_CAPTURE;
 Fmt.Width := CamReqW;
 Fmt.Height := CamReqH;
 Fmt.PixFmt := V4L2_PIX_FMT_YUYV;
 If lc_ioctl(VFd, VIoc(3, 5, SizeOf(Fmt)), @Fmt) <> 0 Then Begin
  FillChar(Fmt, SizeOf(Fmt), 0);
  Fmt.FmtType := V4L2_BUF_TYPE_VIDEO_CAPTURE;
  Fmt.Width := CamReqW;
  Fmt.Height := CamReqH;
  Fmt.PixFmt := V4L2_PIX_FMT_MJPEG;
  If lc_ioctl(VFd, VIoc(3, 5, SizeOf(Fmt)), @Fmt) <> 0 Then Begin
   CamClose;
   Exit;
  End;
 End;
 VW := Fmt.Width;
 VH := Fmt.Height;
 Case Fmt.PixFmt Of
  V4L2_PIX_FMT_YUYV: VFmtId := FMT_YUYV;
  V4L2_PIX_FMT_UYVY: VFmtId := FMT_UYVY;
  V4L2_PIX_FMT_MJPEG: VFmtId := FMT_MJPEG;
  V4L2_PIX_FMT_RGB24: VFmtId := FMT_RGB24;
  V4L2_PIX_FMT_BGR24: VFmtId := FMT_BGR24;
 Else VFmtId := 0;
 End;
 If VFmtId = 0 Then Begin
  CamClose;
  Exit;
 End;
 FillChar(Req, SizeOf(Req), 0);
 Req.Count := NBUF;
 Req.ReqType := V4L2_BUF_TYPE_VIDEO_CAPTURE;
 Req.Memory := V4L2_MEMORY_MMAP;
 If lc_ioctl(VFd, VIoc(3, 8, SizeOf(Req)), @Req) <> 0 Then Begin
  CamClose;
  Exit;
 End;
 If Req.Count > NBUF Then Req.Count := NBUF;
 VCount := 0;
 For I := 0 To Req.Count - 1 Do Begin
  FillChar(Buf, SizeOf(Buf), 0);
  Buf.Index := I;
  Buf.BufType := V4L2_BUF_TYPE_VIDEO_CAPTURE;
  Buf.Memory := V4L2_MEMORY_MMAP;
  If lc_ioctl(VFd, VIoc(3, 9, SizeOf(Buf)), @Buf) <> 0 Then Begin
   CamClose;
   Exit;
  End;
  P := lc_mmap(Nil, Buf.Length, PROT_RW, MAP_SHARED, VFd, Buf.MOffset);
  If PtrInt(P) = -1 Then Begin
   CamClose;
   Exit;
  End;
  VMap[I] := P;
  VLen[I] := Buf.Length;
  Inc(VCount);
  If lc_ioctl(VFd, VIoc(3, 15, SizeOf(Buf)), @Buf) <> 0 Then Begin
   CamClose;
   Exit;
  End;
 End;
 T := V4L2_BUF_TYPE_VIDEO_CAPTURE;
 If lc_ioctl(VFd, VIoc(1, 18, 4), @T) <> 0 Then Begin
  CamClose;
  Exit;
 End;
 VStream := True;
 CamOpen := True;
End;

Function CamGrabReal(Var Fr: TImg): Boolean;
Var
 Pf: TPollFd;
 Buf: TV4LBuf;
Begin
 CamGrabReal := False;
 If (VFd < 0) Or Not VStream Then Exit;
 Pf.Fd := VFd;
 Pf.Events := 1;
 Pf.REvents := 0;
 If lc_poll(@Pf, 1, 250) <= 0 Then Exit;
 FillChar(Buf, SizeOf(Buf), 0);
 Buf.BufType := V4L2_BUF_TYPE_VIDEO_CAPTURE;
 Buf.Memory := V4L2_MEMORY_MMAP;
 If lc_ioctl(VFd, VIoc(3, 17, SizeOf(Buf)), @Buf) <> 0 Then Exit;
 If Buf.Index < LongWord(VCount) Then
  CamGrabReal := RawToFrame(PByteArr(VMap[Buf.Index]), Buf.BytesUsed,
                            VW, VH, VFmtId, False, Fr);
 lc_ioctl(VFd, VIoc(3, 15, SizeOf(Buf)), @Buf);
End;
{$ENDIF}

{$IFNDEF WINDOWS}
{$IFNDEF LINUX}
Procedure CamEnumerate;
Begin
 NCams := 0;
End;

Function CamOpen(Idx: Integer): Boolean;
Begin
 CamOpen := False;
End;

Procedure CamClose;
Begin
End;

Function CamGrabReal(Var Fr: TImg): Boolean;
Begin
 CamGrabReal := False;
End;
{$ENDIF}
{$ENDIF}

Procedure CamListBuild;
Begin
 CamEnumerate;
 Cams[NCams].Kind := SRC_SYNTH;
 Cams[NCams].Idx := 0;
 Cams[NCams].Name := L5('Mire de test (visage anime)',
                        'Test pattern (animated face)',
                        'Testbild (animiertes Gesicht)',
                        'Imagen de prueba (rostro animado)',
                        'Immagine di prova (volto animato)');
 Inc(NCams);
 CurCam := 0;
End;

Function CamStart(Idx: Integer): Boolean;
Begin
 CamStart := False;
 CamOpened := False;
 If (Idx < 0) Or (Idx >= NCams) Then Exit;
 CamKind := Cams[Idx].Kind;
 If CamKind = SRC_SYNTH Then Begin
  CamOpened := True;
  CamStart := True;
  Exit;
 End;
 If CamOpen(Cams[Idx].Idx) Then Begin
  CamOpened := True;
  CamStart := True;
 End;
End;

Procedure CamStop;
Begin
 If CamOpened And (CamKind <> SRC_SYNTH) Then CamClose;
 CamOpened := False;
End;

Function CamGrab(Var Fr: TImg): Boolean;
Begin
 CamGrab := False;
 If Not CamOpened Then Exit;
 If CamKind = SRC_SYNTH Then Begin
  Inc(SynT);
  SynthFrame(Fr, SynT);
  CamGrab := True;
 End
 Else CamGrab := CamGrabReal(Fr);
End;

{ ---------------------------------------------------------------------- }
{ Detection des visages                                                    }
{ Peau en YCbCr (modele adaptatif), composantes connexes, cadre de la      }
{ tete, puis reperes des yeux et de la bouche (sombre / non-peau / levres) }
{ ---------------------------------------------------------------------- }

Const
 MAX_COMP = 24;

Type
 {$IFDEF FPC}
 TWordArr = Array[0..67108863] Of Word;
 {$ELSE}
 TWordArr = Array[0..32759] Of Word;
 {$ENDIF}
 PWordArr = ^TWordArr;
 TComp = Record
  Area, X1, Y1, X2, Y2: LongInt;
 End;

Var
 AStep, AWd, AHt: LongInt;
 AMask, ATmp: PByteArr;
 ALab, AStk: PWordArr;
 SkinCb, SkinCr, SkinDCb, SkinDCr: LongInt;
 Feat: Array[0..4999] Of Integer;
 FGW, FGH: LongInt;
 PrevCx, PrevCy, PrevW: Real;
 PrevOk: Boolean;
 TrackMiss: Integer;

Function DetectAlloc: Boolean;
Begin
 AMask := PByteArr(MemAlloc(AMAX * AMAX));
 ATmp := PByteArr(MemAlloc(AMAX * AMAX));
 ALab := PWordArr(MemAlloc(AMAX * AMAX * 2));
 AStk := PWordArr(MemAlloc(AMAX * AMAX * 2));
 DetectAlloc := (AMask <> Nil) And (ATmp <> Nil) And (ALab <> Nil) And
                (AStk <> Nil);
End;

Procedure SkinReset;
Begin
 SkinCb := 105;
 SkinCr := 153;
 SkinDCb := 22;
 SkinDCr := 20;
End;

Function SkinPix(Y, Cb, Cr: LongInt): Boolean;
Begin
 SkinPix := (Y >= 22) And (IAbs(Cb - SkinCb) <= SkinDCb) And
            (IAbs(Cr - SkinCr) <= SkinDCr) And (Cr - Cb >= 14);
End;

Procedure PixYcc(Var Fr: TImg; X, Y: LongInt; Var Yy, Cb, Cr: LongInt);
Var
 P: LongInt;
Begin
 X := ClipL(X, 0, Fr.W - 1);
 Y := ClipL(Y, 0, Fr.H - 1);
 P := (Y * Fr.W + X) * 3;
 RgbToYcc(Fr.D^[P], Fr.D^[P + 1], Fr.D^[P + 2], Yy, Cb, Cr);
End;

{ Masque de peau sur une grille reduite (4 echantillons par cellule) }
Procedure BuildMask(Var Fr: TImg);
Var
 AX, AY, X, Y, S, P, R, G, B, Yy, Cb, Cr, H1, H2, N: LongInt;
Begin
 AStep := (IMax(Fr.W, Fr.H) + AMAX - 1) Div AMAX;
 If AStep < 1 Then AStep := 1;
 AWd := Fr.W Div AStep;
 AHt := Fr.H Div AStep;
 H1 := AStep Div 4;
 H2 := (AStep * 3) Div 4;
 For AY := 0 To AHt - 1 Do
  For AX := 0 To AWd - 1 Do Begin
   R := 0; G := 0; B := 0;
   For S := 0 To 3 Do Begin
    If (S And 1) = 0 Then X := AX * AStep + H1 Else X := AX * AStep + H2;
    If (S And 2) = 0 Then Y := AY * AStep + H1 Else Y := AY * AStep + H2;
    P := (Y * Fr.W + X) * 3;
    Inc(R, Fr.D^[P]);
    Inc(G, Fr.D^[P + 1]);
    Inc(B, Fr.D^[P + 2]);
   End;
   RgbToYcc(R Shr 2, G Shr 2, B Shr 2, Yy, Cb, Cr);
   If SkinPix(Yy, Cb, Cr) Then AMask^[AY * AWd + AX] := 1
                          Else AMask^[AY * AWd + AX] := 0;
  End;
 { filtre majoritaire 3x3, deux fois }
 For N := 1 To 2 Do Begin
  For AY := 0 To AHt - 1 Do
   For AX := 0 To AWd - 1 Do Begin
    S := 0;
    For Y := AY - 1 To AY + 1 Do
     For X := AX - 1 To AX + 1 Do
      If (X >= 0) And (Y >= 0) And (X < AWd) And (Y < AHt) Then
       Inc(S, AMask^[Y * AWd + X]);
    If S >= 5 Then ATmp^[AY * AWd + AX] := 1
              Else ATmp^[AY * AWd + AX] := 0;
   End;
  Move(ATmp^, AMask^, AWd * AHt);
 End;
End;

{ Etiquetage des composantes connexes (4-voisins, pile explicite) }
Function LabelComps(Var Comps: Array Of TComp; MinArea: LongInt): Integer;
Var
 AX, AY, X, Y, Sp, Idx, NC, Cnt: LongInt;
 C: TComp;
 Procedure Push(XX, YY: LongInt);
 Begin
  If (XX >= 0) And (YY >= 0) And (XX < AWd) And (YY < AHt) Then
   If (AMask^[YY * AWd + XX] = 1) And (ALab^[YY * AWd + XX] = 0) Then Begin
    ALab^[YY * AWd + XX] := NC + 1;
    AStk^[Sp] := YY * AWd + XX;
    Inc(Sp);
   End;
 End;
Begin
 FillChar(ALab^, AWd * AHt * 2, 0);
 NC := 0;
 Cnt := 0;
 For AY := 0 To AHt - 1 Do
  For AX := 0 To AWd - 1 Do
   If (AMask^[AY * AWd + AX] = 1) And (ALab^[AY * AWd + AX] = 0) And
      (NC < MAX_COMP) Then Begin
    Sp := 0;
    C.Area := 0; C.X1 := AX; C.X2 := AX; C.Y1 := AY; C.Y2 := AY;
    Push(AX, AY);
    While Sp > 0 Do Begin
     Dec(Sp);
     Idx := AStk^[Sp];
     X := Idx Mod AWd;
     Y := Idx Div AWd;
     Inc(C.Area);
     If X < C.X1 Then C.X1 := X;
     If X > C.X2 Then C.X2 := X;
     If Y < C.Y1 Then C.Y1 := Y;
     If Y > C.Y2 Then C.Y2 := Y;
     Push(X + 1, Y); Push(X - 1, Y); Push(X, Y + 1); Push(X, Y - 1);
    End;
    If C.Area >= MinArea Then Begin
     { l'etiquette de la composante est NC + 1 }
     Comps[Cnt] := C;
     Inc(Cnt);
     Inc(NC);
    End
    Else Begin
     { composante trop petite : on l'efface pour ne pas la revisiter }
     For Y := C.Y1 To C.Y2 Do
      For X := C.X1 To C.X2 Do
       If ALab^[Y * AWd + X] = NC + 1 Then ALab^[Y * AWd + X] := 65535;
    End;
   End;
 LabelComps := Cnt;
End;

{ Cadre de la tete a partir d'une composante de peau }
Function HeadFromComp(Lab: Integer; Var Cp: TComp; Var F: TFace): Boolean;
Var
 Cnt: Array[0..AMAX - 1] Of LongInt;
 SumX: Array[0..AMAX - 1] Of LongInt;
 X, Y, BH, Wf, Hh, Wr, I, HeadArea, SX, Lim: LongInt;
 Cx: Real;
Begin
 HeadFromComp := False;
 BH := Cp.Y2 - Cp.Y1 + 1;
 For Y := Cp.Y1 To Cp.Y2 Do Begin
  Cnt[Y] := 0;
  SumX[Y] := 0;
  For X := Cp.X1 To Cp.X2 Do
   If ALab^[Y * AWd + X] = Lab Then Begin
    Inc(Cnt[Y]);
    Inc(SumX[Y], X);
   End;
 End;
 { largeur du visage : maximum lisse sur la moitie superieure }
 Wf := 0;
 Lim := Cp.Y1 + (BH * 55) Div 100;
 For Y := Cp.Y1 To Lim Do Begin
  Wr := Cnt[Y];
  If (Y > Cp.Y1) And (Y < Cp.Y2) Then
   Wr := (Cnt[Y - 1] + 2 * Cnt[Y] + Cnt[Y + 1]) Div 4;
  If Wr > Wf Then Wf := Wr;
 End;
 If (Wf < 6) Or (BH * 100 < Wf * 75) Then Exit;
 If Wf * 100 > AWd * 96 Then Exit;
 Hh := (Wf * 128) Div 100;
 If Hh > BH Then Hh := BH;
 HeadArea := 0;
 SX := 0;
 For Y := Cp.Y1 To Cp.Y1 + Hh - 1 Do Begin
  Inc(HeadArea, Cnt[Y]);
  Inc(SX, SumX[Y]);
 End;
 If HeadArea < 1 Then Exit;
 If HeadArea * 100 < Wf * Hh * 45 Then Exit;
 If Cp.Area > 4 * HeadArea Then Exit;
 Cx := SX / HeadArea;
 F.Ok := True;
 F.X1 := RoundL((Cx - Wf / 2.0) * AStep);
 F.X2 := RoundL((Cx + Wf / 2.0 + 1) * AStep) - 1;
 F.Y1 := Cp.Y1 * AStep;
 F.Y2 := (Cp.Y1 + Hh) * AStep - 1;
 F.Area := HeadArea;
 HeadFromComp := True;
End;

{ Reperes : yeux et bouche, dans le cadre de la tete }
Procedure FindLandmarks(Var Fr: TImg; Var F: TFace);
Var
 Wf, Cx, Sx, XA, XB, YA, YB, X, Y, Yy, Cb, Cr, N: LongInt;
 YRef, CbRef, CrRef, NRef, YLo, I, J, Best, K: LongInt;
 Pr, Ps: Array[0..99] Of Real;
 GX0, GY0: LongInt;
 V, Mx, My, Sc, BestSc, W, YE0: Real;
 ELx, ELy, ERx, ERy, Mxx, Myy, Ex, Ey: Real;
 Mass, MassL, MassR: LongInt;
 Ux, Uy, Vx, Vy, Len, Ipd, Vm: Real;
 MFeat: Integer;

 { Centroide (moyenne decalee) de la grille d'attributs }
 Procedure Centroid(CX0, CY0, RX, RY: Real; Var OX, OY: Real;
                    Var M: LongInt);
 Var
  It, XI, YI: LongInt;
  PX, PY, SW, SXX, SYY, WW: Real;
 Begin
  OX := CX0;
  OY := CY0;
  M := 0;
  For It := 1 To 3 Do Begin
   SW := 0; SXX := 0; SYY := 0;
   For YI := 0 To FGH - 1 Do
    For XI := 0 To FGW - 1 Do Begin
     PX := XA + XI * Sx;
     PY := YA + YI * Sx;
     If (Abs(PX - OX) <= RX) And (Abs(PY - OY) <= RY) Then Begin
      WW := Feat[YI * FGW + XI];
      WW := WW * WW;
      SW := SW + WW;
      SXX := SXX + WW * PX;
      SYY := SYY + WW * PY;
     End;
    End;
   If SW < 1 Then Begin M := 0; Exit; End;
   OX := SXX / SW;
   OY := SYY / SW;
   M := RoundL(SW / 100);
  End;
 End;

Begin
 Wf := F.X2 - F.X1 + 1;
 Cx := (F.X1 + F.X2) Div 2;
 Sx := IMax(1, Wf Div 90);
 { couleur de reference : joues }
 YRef := 0; CbRef := 0; CrRef := 0; NRef := 0;
 For J := 0 To 1 Do
  For Y := F.Y1 + (Wf * 50) Div 100 To F.Y1 + (Wf * 78) Div 100 Do
   If (Y Mod Sx) = 0 Then
    For X := Cx - (Wf * 40) Div 100 To Cx - (Wf * 24) Div 100 Do
     If (X Mod Sx) = 0 Then Begin
      If J = 0 Then PixYcc(Fr, X, Y, Yy, Cb, Cr)
               Else PixYcc(Fr, 2 * Cx - X, Y, Yy, Cb, Cr);
      If SkinPix(Yy, Cb, Cr) Then Begin
       Inc(YRef, Yy); Inc(CbRef, Cb); Inc(CrRef, Cr); Inc(NRef);
      End;
     End;
 If NRef < 4 Then Begin
  YRef := 110; CbRef := SkinCb; CrRef := SkinCr;
 End
 Else Begin
  YRef := YRef Div NRef; CbRef := CbRef Div NRef; CrRef := CrRef Div NRef;
 End;
 YLo := YRef * 85 Div 100;
 { grille d'attributs pour les yeux }
 XA := Cx - (Wf * 42) Div 100;
 XB := Cx + (Wf * 42) Div 100;
 YA := F.Y1 + (Wf * 14) Div 100;
 YB := F.Y1 + (Wf * 74) Div 100;
 FGW := (XB - XA) Div Sx + 1;
 FGH := (YB - YA) Div Sx + 1;
 If FGW * FGH > 5000 Then Begin
  FGH := 5000 Div FGW;
 End;
 If FGH > 100 Then FGH := 100;
 For J := 0 To FGH - 1 Do
  For I := 0 To FGW - 1 Do Begin
   PixYcc(Fr, XA + I * Sx, YA + J * Sx, Yy, Cb, Cr);
   N := 0;
   If Yy < YLo Then N := YLo - Yy;
   If Not SkinPix(Yy, Cb, Cr) Then N := N + 8;
   Feat[J * FGW + I] := N;
  End;
 { profil des lignes dans la bande centrale }
 For J := 0 To FGH - 1 Do Begin
  Pr[J] := 0;
  For I := 0 To FGW - 1 Do
   If (Abs(XA + I * Sx - Cx) <= (Wf * 38) Div 100) Then
    Pr[J] := Pr[J] + Feat[J * FGW + I];
 End;
 For J := 0 To FGH - 1 Do Begin
  Ps[J] := Pr[J] * 2;
  If J > 0 Then Ps[J] := Ps[J] + Pr[J - 1] Else Ps[J] := Ps[J] + Pr[J];
  If J < FGH - 1 Then Ps[J] := Ps[J] + Pr[J + 1] Else Ps[J] := Ps[J] + Pr[J];
 End;
 YE0 := F.Y1 + 0.40 * Wf;
 Best := -1;
 BestSc := 0;
 For J := 0 To FGH - 1 Do Begin
  W := (YA + J * Sx - YE0) / (0.15 * Wf);
  Sc := Ps[J] * Exp(-W * W);
  If Sc > BestSc Then Begin BestSc := Sc; Best := J; End;
 End;
 { les yeux sont sous les sourcils : second pic juste en dessous }
 If Best >= 0 Then Begin
  BestSc := 0;
  K := Best;
  For J := Best + 1 To FGH - 2 Do
   If ((J - Best) * Sx >= 0.05 * Wf) And ((J - Best) * Sx <= 0.17 * Wf) And
      (Ps[J] >= Ps[J - 1]) And (Ps[J] >= Ps[J + 1]) And
      (Ps[J] >= 0.18 * Ps[Best]) And (Ps[J] > BestSc) Then Begin
    BestSc := Ps[J];
    K := J;
   End;
  Best := K;
 End;
 Ex := Cx;
 If Best >= 0 Then Ey := YA + Best * Sx Else Ey := YE0;
 { oeil gauche / droit : centroides de part et d'autre du centre }
 Centroid(Cx - 0.22 * Wf, Ey, 0.17 * Wf, 0.055 * Wf, ELx, ELy, MassL);
 Centroid(Cx + 0.22 * Wf, Ey, 0.17 * Wf, 0.055 * Wf, ERx, ERy, MassR);
 If MassL > 0 Then
  Centroid(ELx, ELy, 0.09 * Wf, 0.04 * Wf, ELx, ELy, MassL);
 If MassR > 0 Then
  Centroid(ERx, ERy, 0.09 * Wf, 0.04 * Wf, ERx, ERy, MassR);
 If (MassL <= 0) Or (MassR <= 0) Or (ERx - ELx < 0.28 * Wf) Or
    (ERx - ELx > 0.66 * Wf) Or (Abs(ERy - ELy) > 0.14 * Wf) Then Begin
  ELx := Cx - 0.225 * Wf;
  ERx := Cx + 0.225 * Wf;
  ELy := Ey;
  ERy := Ey;
 End;
 { bouche : levres (Cr eleve) ou ouverture sombre sous les yeux }
 Ux := ERx - ELx;
 Uy := ERy - ELy;
 Len := Sqrt(Ux * Ux + Uy * Uy);
 If Len < 1 Then Len := 1;
 Ux := Ux / Len;
 Uy := Uy / Len;
 Vx := -Uy;
 Vy := Ux;
 Ipd := Len;
 Ex := (ELx + ERx) / 2;
 Ey := (ELy + ERy) / 2;
 Mxx := Ex + Vx * 0.95 * Ipd;
 Myy := Ey + Vy * 0.95 * Ipd;
 { recherche autour de la position attendue }
 YA := RoundL(Ey + 0.55 * Ipd);
 YB := RoundL(Ey + 1.45 * Ipd);
 XA := RoundL(Ex - 0.7 * Ipd);
 XB := RoundL(Ex + 0.7 * Ipd);
 FGW := (XB - XA) Div Sx + 1;
 FGH := (YB - YA) Div Sx + 1;
 If FGH > 100 Then FGH := 100;
 If FGW * FGH > 5000 Then FGW := 5000 Div FGH;
 For J := 0 To FGH - 1 Do
  For I := 0 To FGW - 1 Do Begin
   PixYcc(Fr, XA + I * Sx, YA + J * Sx, Yy, Cb, Cr);
   N := 0;
   If Cr > CrRef + 7 Then N := (Cr - CrRef - 7) * 3;
   If Yy < YRef * 70 Div 100 Then N := N + (YRef * 70 Div 100 - Yy);
   Feat[J * FGW + I] := N;
  End;
 Centroid(Mxx, Myy, 0.50 * Ipd, 0.30 * Ipd, Mx, My, Mass);
 If (Mass > 0) And (Abs(Mx - Mxx) < 0.6 * Ipd) And
    (Abs(My - Myy) < 0.4 * Ipd) Then Begin
  Mxx := 0.4 * Mxx + 0.6 * Mx;
  Myy := 0.4 * Myy + 0.6 * My;
 End;
 F.ELx := ELx; F.ELy := ELy; F.ERx := ERx; F.ERy := ERy;
 F.Mx := Mxx; F.My := Myy;
End;

{ Detecte jusqu'a MaxN visages (le plus grand d'abord) }
{ ---------------------------------------------------------------------- }
{ Detection de visages par cascade de Haar (classique, sans reseau de        }
{ neurones) : 'haarcascade_frontalface_default' d'OpenCV, Rainer Lienhart.   }
{ Licence d'origine (Intel License Agreement For Open Source Computer       }
{ Vision Library, redistribuee sous les memes conditions) :                  }
{ Copyright (C) 2000, Intel Corporation, all rights reserved.               }
{ Redistribution and use in source and binary forms, with or without        }
{ modification, are permitted provided that the following conditions are    }
{ met: redistribution's of source code must retain the above copyright      }
{ notice and this list of conditions; redistribution's in binary form must  }
{ reproduce the above copyright notice and this list of conditions in the   }
{ documentation and/or other materials provided with the distribution; the  }
{ name of Intel Corporation may not be used to endorse or promote products  }
{ derived from this software without specific prior written permission.     }
{ This software is provided by the copyright holders and contributors 'as   }
{ is' and any express or implied warranties are disclaimed.                 }
{ Fenetre de base 24 x 24, 25 etages, 2913 classifieurs faibles.               }
{ Free Pascal seulement : sous Turbo Pascal, detection par la couleur de    }
{ peau uniquement.                                                          }
{ ---------------------------------------------------------------------- }

{$IFDEF FPC}
Const
 HAAR_WIN = 24;
 HAAR_NS = 25;
 HAAR_NW = 2913;
 HaarStageCnt: Array[0..24] Of Word = (
  9, 16, 27, 32, 52, 53, 62, 72, 83, 91, 99, 115, 127, 135, 136, 137,
  159, 155, 169, 196, 197, 181, 199, 211, 200);
 HaarStageThr: Array[0..24] Of Single = (
  (-5.0426), (-4.9842), (-4.6552), (-4.4532), (-4.3865), (-4.1299),
  (-4.0218), (-3.8832), (-3.8425), (-3.6479), (-3.87), (-3.7161),
  (-3.5645), (-3.7026), (-3.4266), (-3.5125), (-3.594), (-3.3934),
  (-3.2397), (-3.2104), (-3.2773), (-3.3196), (-3.2573), (-3.3703),
  (-2.9928));
 HaarWF: Array[0..2912] Of Word = (
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
  16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
  48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
  64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
  80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95,
  96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111,
  112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127,
  128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143,
  144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159,
  160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175,
  176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191,
  192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207,
  208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223,
  224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239,
  240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255,
  256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271,
  272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287,
  288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303,
  304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319,
  320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335,
  336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351,
  352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367,
  368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383,
  384, 385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399,
  400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415,
  416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431,
  432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447,
  448, 449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463,
  464, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479,
  480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495,
  496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511,
  512, 513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 524, 525, 526, 527,
  528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543,
  544, 545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559,
  560, 561, 562, 563, 564, 565, 566, 567, 568, 569, 570, 571, 572, 573, 574, 575,
  576, 577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591,
  592, 593, 594, 595, 596, 597, 598, 599, 600, 601, 602, 603, 604, 605, 606, 607,
  608, 609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623,
  624, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 639,
  640, 641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653, 654, 655,
  656, 657, 658, 659, 660, 661, 662, 663, 664, 665, 666, 667, 668, 669, 670, 671,
  672, 673, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683, 684, 685, 686, 687,
  688, 689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703,
  704, 705, 706, 707, 708, 709, 710, 711, 712, 713, 714, 715, 716, 717, 718, 719,
  720, 721, 722, 723, 724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734, 735,
  736, 737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 749, 750, 751,
  752, 753, 754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 765, 766, 767,
  768, 769, 770, 771, 772, 773, 774, 775, 776, 777, 778, 779, 780, 781, 782, 783,
  784, 785, 786, 787, 788, 789, 790, 791, 792, 793, 794, 795, 796, 797, 798, 799,
  800, 801, 802, 803, 804, 805, 806, 807, 808, 809, 810, 811, 812, 813, 814, 815,
  816, 817, 818, 819, 820, 821, 822, 823, 824, 825, 826, 827, 828, 829, 830, 831,
  832, 833, 834, 835, 836, 837, 838, 839, 840, 841, 842, 843, 844, 845, 846, 847,
  848, 849, 850, 851, 852, 853, 854, 855, 856, 857, 858, 859, 860, 861, 862, 863,
  864, 865, 866, 867, 868, 869, 870, 871, 872, 873, 874, 875, 876, 877, 878, 879,
  880, 881, 882, 883, 884, 885, 886, 887, 888, 889, 890, 891, 892, 893, 894, 895,
  896, 897, 898, 899, 900, 901, 902, 903, 904, 905, 906, 907, 908, 909, 910, 911,
  912, 913, 914, 915, 916, 917, 918, 919, 920, 921, 922, 923, 924, 925, 926, 927,
  928, 929, 930, 931, 932, 933, 934, 935, 936, 937, 938, 939, 940, 941, 942, 943,
  944, 945, 946, 947, 948, 949, 950, 951, 952, 953, 954, 955, 956, 957, 958, 959,
  960, 961, 962, 963, 964, 965, 966, 967, 968, 969, 970, 971, 972, 973, 974, 975,
  976, 977, 978, 979, 980, 981, 982, 983, 984, 985, 986, 987, 988, 989, 990, 991,
  992, 993, 994, 995, 996, 997, 998, 999, 1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007,
  1008, 1009, 1010, 1011, 1012, 1013, 1014, 1015, 1016, 1017, 1018, 1019, 1020, 1021, 1022, 1023,
  1024, 1025, 1026, 1027, 1028, 1029, 1030, 1031, 1032, 1033, 1034, 1035, 1036, 1037, 1038, 1039,
  1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055,
  1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1065, 1066, 1067, 1068, 1069, 1070, 1071,
  1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081, 1082, 1083, 1084, 1085, 1086, 1087,
  1088, 1089, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097, 1098, 1099, 1100, 1101, 1102, 1103,
  1104, 1105, 1106, 1107, 1108, 1109, 1110, 1111, 1112, 1113, 1114, 1115, 1116, 1117, 1118, 1119,
  1120, 1121, 1122, 1123, 1124, 1125, 1126, 1127, 1128, 1129, 1130, 1131, 1132, 1133, 1134, 1135,
  1136, 1137, 1138, 1139, 1140, 1141, 1142, 1143, 1144, 1145, 1146, 1147, 1148, 1149, 1150, 1151,
  1152, 1153, 1154, 1155, 1156, 1157, 1158, 1159, 1160, 1161, 1162, 1163, 1164, 1165, 1166, 1167,
  1168, 1169, 1170, 1171, 1172, 1173, 1174, 1175, 1176, 1177, 1178, 1179, 1180, 1181, 1182, 1183,
  1184, 1185, 1186, 1187, 1188, 1189, 1190, 1191, 1192, 1193, 1194, 1195, 1196, 1197, 1198, 1199,
  1200, 1201, 1202, 1203, 1204, 1205, 1206, 1207, 1208, 1209, 1210, 1211, 1212, 1213, 1214, 1215,
  1216, 1217, 1218, 1219, 1220, 1221, 1222, 1223, 1224, 1225, 1226, 1227, 1228, 1229, 1230, 1231,
  1232, 1233, 1234, 1235, 1236, 1237, 1238, 1239, 1240, 1241, 1242, 1243, 1244, 1245, 1246, 1247,
  1248, 1249, 1250, 1251, 1252, 1253, 1254, 1255, 1256, 1257, 1258, 1259, 1260, 1261, 1262, 1263,
  1264, 1265, 1266, 1267, 1268, 1269, 1270, 1271, 1272, 1273, 1274, 1275, 1276, 1277, 1278, 1279,
  1280, 1281, 1282, 1283, 1284, 1285, 1286, 1287, 1288, 1289, 1290, 1291, 1292, 1293, 1294, 1295,
  1296, 1297, 1298, 1299, 1300, 1301, 1302, 1303, 1304, 1305, 1306, 1307, 1308, 1309, 1310, 1311,
  1312, 1313, 1314, 1315, 1316, 1317, 1318, 1319, 1320, 1321, 1322, 1323, 1324, 1325, 1326, 1327,
  1328, 1329, 1330, 1331, 1332, 1333, 1334, 1335, 1336, 1337, 1338, 1339, 1340, 1341, 1342, 1343,
  1344, 1345, 1346, 1347, 1348, 1349, 1350, 1351, 1352, 1353, 1354, 1355, 1356, 1357, 1358, 1359,
  1360, 1361, 1362, 1363, 1364, 1365, 1366, 1367, 1368, 1369, 1370, 1371, 1372, 1373, 1374, 1375,
  1376, 1377, 1378, 1379, 1380, 1381, 1382, 1383, 1384, 1385, 1386, 1387, 1388, 1389, 1390, 1391,
  1392, 1393, 1394, 1395, 1396, 1397, 1398, 1399, 1400, 1401, 1402, 1403, 1404, 1405, 1406, 1407,
  1408, 1409, 1410, 1411, 1412, 1413, 1414, 1415, 1416, 1417, 1418, 1419, 1420, 1421, 1422, 1423,
  1424, 1425, 1426, 1427, 1428, 1429, 1430, 1431, 1432, 1433, 1434, 1435, 1436, 1437, 1438, 1439,
  1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447, 1448, 1449, 1450, 1451, 1452, 1453, 1454, 1455,
  1456, 1457, 1458, 1459, 1460, 1461, 1462, 1463, 1464, 1465, 1466, 1467, 1468, 1469, 1470, 1471,
  1472, 1473, 1474, 1475, 1476, 1477, 1478, 1479, 1480, 1481, 1482, 1483, 1484, 1485, 1486, 1487,
  1488, 1489, 1490, 1491, 1492, 1493, 1494, 1495, 1496, 1497, 1498, 1499, 1500, 1501, 1502, 1503,
  1504, 1505, 1506, 1507, 1508, 1509, 1510, 1511, 1512, 1513, 1514, 1515, 1516, 1517, 1518, 1519,
  1520, 1521, 1522, 1523, 1524, 1525, 1526, 1527, 1528, 1529, 1530, 1531, 1532, 1533, 1534, 1535,
  1536, 1537, 1538, 1539, 1540, 1541, 1542, 1543, 1544, 1545, 1546, 1547, 1548, 1549, 1550, 1551,
  1552, 1553, 1554, 1555, 1556, 1557, 1558, 1559, 1560, 1561, 1562, 1563, 1564, 1565, 1566, 1567,
  1568, 1569, 1570, 1571, 1572, 1573, 1574, 1575, 1576, 1577, 1578, 1579, 1580, 1581, 1582, 1583,
  1584, 1585, 1586, 1587, 1588, 1589, 1590, 1591, 1592, 1593, 1594, 1595, 1596, 1597, 1598, 1599,
  1600, 1601, 1602, 1603, 1604, 1605, 1606, 1607, 1608, 1609, 1610, 1611, 1612, 1613, 1614, 1615,
  1616, 1617, 1618, 1619, 1620, 1621, 1622, 1623, 1624, 1625, 1626, 1627, 1628, 1629, 1630, 1631,
  1632, 1633, 1634, 1635, 1636, 1637, 1638, 1639, 1640, 1641, 1642, 1643, 1644, 1645, 1646, 1647,
  1648, 1649, 1650, 1651, 1652, 1653, 1654, 1655, 1656, 1657, 1658, 1659, 1660, 1661, 1662, 1663,
  1664, 1665, 1666, 1667, 1668, 1669, 1670, 1671, 1672, 1673, 1674, 1675, 1676, 1677, 1678, 1679,
  1680, 1681, 1682, 1683, 1684, 1685, 1686, 1687, 1688, 1689, 1690, 1691, 1692, 1693, 1694, 1695,
  1696, 1697, 1698, 1699, 1700, 1701, 1702, 1703, 1704, 1705, 1706, 1707, 1708, 1709, 1710, 1711,
  1712, 1713, 1714, 1715, 1716, 1717, 1718, 1719, 1720, 1721, 1722, 1723, 1724, 1725, 1726, 1727,
  1728, 1729, 1730, 1731, 1732, 1733, 1734, 1735, 1736, 1737, 1738, 1739, 1740, 1741, 1742, 1743,
  1744, 1745, 1746, 1747, 1748, 1749, 1750, 1751, 1752, 1753, 1754, 1755, 1756, 1757, 1758, 1759,
  1760, 1761, 1762, 1763, 1764, 1765, 1766, 1767, 1768, 1769, 1770, 1771, 1772, 1773, 1774, 1775,
  1776, 1777, 1778, 1779, 1780, 1781, 1782, 1783, 1784, 1785, 1786, 1787, 1788, 1789, 1790, 1791,
  1792, 1793, 1794, 1795, 1796, 1797, 1798, 1799, 1800, 1801, 1802, 1803, 1804, 1805, 1806, 1807,
  1808, 1809, 1810, 1811, 1812, 1813, 1814, 1815, 1816, 1817, 1818, 1819, 1820, 1821, 1822, 1823,
  1824, 1825, 1826, 1827, 1828, 1829, 1830, 1831, 1832, 1833, 1834, 1835, 1836, 1837, 1838, 1839,
  1840, 1841, 1842, 1843, 1844, 1845, 1846, 1847, 1848, 1849, 1850, 1851, 1852, 1853, 1854, 1855,
  1856, 1857, 1858, 1859, 1860, 1861, 1862, 1863, 1864, 1865, 1866, 1867, 1868, 1869, 1870, 1871,
  1872, 1873, 1874, 1875, 1876, 1877, 1878, 1879, 1880, 1881, 1882, 1883, 1884, 1885, 1886, 1887,
  1888, 1889, 1890, 1891, 1892, 1893, 1894, 1895, 1896, 1897, 1898, 1899, 1900, 1901, 1902, 1903,
  1904, 1905, 1906, 1907, 1908, 1909, 1910, 1911, 1912, 1913, 1914, 1915, 1916, 1917, 1918, 1919,
  1920, 1921, 1922, 1923, 1924, 1925, 1926, 1927, 1928, 1929, 1930, 1931, 1932, 1933, 1934, 1935,
  1936, 1937, 1938, 1939, 1940, 1941, 1942, 1943, 1944, 1945, 1946, 1947, 1948, 1949, 1950, 1951,
  1952, 1953, 1954, 1955, 1956, 1957, 1958, 1959, 1960, 1961, 1962, 1963, 1964, 1965, 1966, 1967,
  1968, 1969, 1970, 1971, 1972, 1973, 1974, 1975, 1976, 1977, 1978, 1979, 1980, 1981, 1982, 1983,
  1984, 1985, 1986, 1987, 1988, 1989, 1990, 1991, 1992, 1993, 1994, 1995, 1996, 1997, 1998, 1999,
  2000, 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015,
  2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025, 2026, 2027, 2028, 2029, 2030, 2031,
  2032, 2033, 2034, 2035, 2036, 2037, 2038, 2039, 2040, 2041, 2042, 2043, 2044, 2045, 2046, 2047,
  2048, 2049, 2050, 2051, 2052, 2053, 2054, 2055, 2056, 2057, 2058, 2059, 2060, 2061, 2062, 2063,
  2064, 2065, 2066, 2067, 2068, 2069, 2070, 2071, 2072, 2073, 2074, 2075, 2076, 2077, 2078, 2079,
  2080, 2081, 2082, 2083, 2084, 2085, 2086, 2087, 2088, 2089, 2090, 2091, 2092, 2093, 2094, 2095,
  2096, 2097, 2098, 2099, 2100, 2101, 2102, 2103, 2104, 2105, 2106, 2107, 2108, 2109, 2110, 2111,
  2112, 2113, 2114, 2115, 2116, 2117, 2118, 2119, 2120, 2121, 2122, 2123, 2124, 2125, 2126, 2127,
  2128, 2129, 2130, 2131, 2132, 2133, 2134, 2135, 2136, 2137, 2138, 2139, 2140, 2141, 2142, 2143,
  2144, 2145, 2146, 2147, 2148, 2149, 2150, 2151, 2152, 2153, 2154, 2155, 2156, 2157, 2158, 2159,
  2160, 2161, 2162, 2163, 2164, 2165, 2166, 2167, 2168, 2169, 2170, 2171, 2172, 2173, 2174, 2175,
  2176, 2177, 2178, 2179, 2180, 2181, 2182, 2183, 2184, 2185, 2186, 2187, 2188, 2189, 2190, 2191,
  2192, 2193, 2194, 2195, 2196, 2197, 2198, 2199, 2200, 2201, 2202, 2203, 2204, 2205, 2206, 2207,
  2208, 2209, 2210, 2211, 2212, 2213, 2214, 2215, 2216, 2217, 2218, 2219, 2220, 2221, 2222, 2223,
  2224, 2225, 2226, 2227, 2228, 2229, 2230, 2231, 2232, 2233, 2234, 2235, 2236, 2237, 2238, 2239,
  2240, 2241, 2242, 2243, 2244, 2245, 2246, 2247, 2248, 2249, 2250, 2251, 2252, 2253, 2254, 2255,
  2256, 2257, 2258, 2259, 2260, 2261, 2262, 2263, 2264, 2265, 2266, 2267, 2268, 2269, 2270, 2271,
  2272, 2273, 2274, 2275, 2276, 2277, 2278, 2279, 2280, 2281, 2282, 2283, 2284, 2285, 2286, 2287,
  2288, 2289, 2290, 2291, 2292, 2293, 2294, 2295, 2296, 2297, 2298, 2299, 2300, 2301, 2302, 2303,
  2304, 2305, 2306, 2307, 2308, 2309, 2310, 2311, 2312, 2313, 2314, 2315, 2316, 2317, 2318, 2319,
  2320, 2321, 2322, 2323, 2324, 2325, 2326, 2327, 2328, 2329, 2330, 2331, 2332, 2333, 2334, 2335,
  2336, 2337, 2338, 2339, 2340, 2341, 2342, 2343, 2344, 2345, 2346, 2347, 2348, 2349, 2350, 2351,
  2352, 2353, 2354, 2355, 2356, 2357, 2358, 2359, 2360, 2361, 2362, 2363, 2364, 2365, 2366, 2367,
  2368, 2369, 2370, 2371, 2372, 2373, 2374, 2375, 2376, 2377, 2378, 2379, 2380, 2381, 2382, 2383,
  2384, 2385, 2386, 2387, 2388, 2389, 2390, 2391, 2392, 2393, 2394, 2395, 2396, 2397, 2398, 2399,
  2400, 2401, 2402, 2403, 2404, 2405, 2406, 2407, 2408, 2409, 2410, 2411, 2412, 2413, 2414, 2415,
  2416, 2417, 2418, 2419, 2420, 2421, 2422, 2423, 2424, 2425, 2426, 2427, 2428, 2429, 2430, 2431,
  2432, 2433, 2434, 2435, 2436, 2437, 2438, 2439, 2440, 2441, 2442, 2443, 2444, 2445, 2446, 2447,
  2448, 2449, 2450, 2451, 2452, 2453, 2454, 2455, 2456, 2457, 2458, 2459, 2460, 2461, 2462, 2463,
  2464, 2465, 2466, 2467, 2468, 2469, 2470, 2471, 2472, 2473, 2474, 2475, 2476, 2477, 2478, 2479,
  2480, 2481, 2482, 2483, 2484, 2485, 2486, 2487, 2488, 2489, 2490, 2491, 2492, 2493, 2494, 2495,
  2496, 2497, 2498, 2499, 2500, 2501, 2502, 2503, 2504, 2505, 2506, 2507, 2508, 2509, 2510, 2511,
  2512, 2513, 2514, 2515, 2516, 2517, 2518, 2519, 2520, 2521, 2522, 2523, 2524, 2525, 2526, 2527,
  2528, 2529, 2530, 2531, 2532, 2533, 2534, 2535, 2536, 2537, 2538, 2539, 2540, 2541, 2542, 2543,
  2544, 2545, 2546, 2547, 2548, 2549, 2550, 2551, 2552, 2553, 2554, 2555, 2556, 2557, 2558, 2559,
  2560, 2561, 2562, 2563, 2564, 2565, 2566, 2567, 2568, 2569, 2570, 2571, 2572, 2573, 2574, 2575,
  2576, 2577, 2578, 2579, 2580, 2581, 2582, 2583, 2584, 2585, 2586, 2587, 2588, 2589, 2590, 2591,
  2592, 2593, 2594, 2595, 2596, 2597, 2598, 2599, 2600, 2601, 2602, 2603, 2604, 2605, 2606, 2607,
  2608, 2609, 2610, 2611, 2612, 2613, 2614, 2615, 2616, 2617, 2618, 2619, 2620, 2621, 2622, 2623,
  2624, 2625, 2626, 2627, 2628, 2629, 2630, 2631, 2632, 2633, 2634, 2635, 2636, 2637, 2638, 2639,
  2640, 2641, 2642, 2643, 2644, 2645, 2646, 2647, 2648, 2649, 2650, 2651, 2652, 2653, 2654, 2655,
  2656, 2657, 2658, 2659, 2660, 2661, 2662, 2663, 2664, 2665, 2666, 2667, 2668, 2669, 2670, 2671,
  2672, 2673, 2674, 2675, 2676, 2677, 2678, 2679, 2680, 2681, 2682, 2683, 2684, 2685, 2686, 2687,
  2688, 2689, 2690, 2691, 2692, 2693, 2694, 2695, 2696, 2697, 2698, 2699, 2700, 2701, 2702, 2703,
  2704, 2705, 2706, 2707, 2708, 2709, 2710, 2711, 2712, 2713, 2714, 2715, 2716, 2717, 2718, 2719,
  2720, 2721, 2722, 2723, 2724, 2725, 2726, 2727, 2728, 2729, 2730, 2731, 2732, 2733, 2734, 2735,
  2736, 2737, 2738, 2739, 2740, 2741, 2742, 2743, 2744, 2745, 2746, 2747, 2748, 2749, 2750, 2751,
  2752, 2753, 2754, 2755, 2756, 2757, 2758, 2759, 2760, 2761, 2762, 2763, 2764, 2765, 2766, 2767,
  2768, 2769, 2770, 2771, 2772, 2773, 2774, 2775, 2776, 2777, 2778, 2779, 2780, 2781, 2782, 2783,
  2784, 2785, 2786, 2787, 2788, 2789, 2790, 2791, 2792, 2793, 2794, 2795, 2796, 2797, 2798, 2799,
  2800, 2801, 2802, 2803, 2804, 2805, 2806, 2807, 2808, 2809, 2810, 2811, 2812, 2813, 2814, 2815,
  2816, 2817, 2818, 2819, 2820, 2821, 2822, 2823, 2824, 2825, 2826, 2827, 2828, 2829, 2830, 2831,
  2832, 2833, 2834, 2835, 2836, 2837, 2838, 2839, 2840, 2841, 2842, 2843, 2844, 2845, 2846, 2847,
  2848, 2849, 2850, 2851, 2852, 2853, 2854, 2855, 2856, 2857, 2858, 2859, 2860, 2861, 2862, 2863,
  2864, 2865, 2866, 2867, 2868, 2869, 2870, 2871, 2872, 2873, 2874, 2875, 2876, 2877, 2878, 2879,
  2880, 2881, 2882, 2883, 2884, 2885, 2886, 2887, 2888, 2889, 2890, 2891, 2892, 2893, 2894, 2895,
  2896, 2897, 2898, 2899, 2900, 2901, 2902, 2903, 2904, 2905, 2906, 2907, 2908, 2909, 2910, 2911,
  2912);
 HaarWT: Array[0..2912] Of Single = (
  (-0.031512), 0.012396, 0.021928, 0.005753, 0.015014, 0.099371, 0.002734, (-0.018859),
  0.005974, (-0.02111), 0.020356, 0.021309, 0.09166, 0.036288, (-0.01911), 0.008254,
  0.018355, (-0.007057), (-0.009877), 0.015814, (-0.0207), (-0.13761), 0.014319, 0.010253,
  0.091508, 0.069747, 0.031503, 0.014261, 0.014453, (-0.003051), 0.032723, (-0.007296),
  0.050425, 0.046879, (-0.069359), (-0.049034), 0.084828, (-0.001723), 0.11562, (-0.05128),
  (-0.042707), 0.37178, 0.019413, 0.017439, 0.039639, (-0.009147), 0.001722, 0.030231,
  (-0.078796), 0.002111, 0.027091, (-0.044965), (-0.065701), 0.01584, 0.14571, 0.006139,
  0.006718, 0.018518, 0.019958, (-0.27755), 0.009186, (-0.037738), 0.018463, (-0.011115),
  0.033928, (-0.035649), (-0.011438), (-0.065236), (-0.042272), 0.001922, (-0.12922), 0.022931,
  (-0.03412), 0.026223, 0.022237, (-0.005824), 0.043653, 0.057267, 0.002341, 0.012996,
  (-0.026517), (-0.00584), (-0.016569), (-0.068157), 0.039974, 0.1882, 0.078027, 0.000119,
  0.085057, 0.008972, 0.008812, (-0.023508), 0.007004, 0.033852, (-0.003253), 0.029097,
  (-0.008479), (-0.010795), (-0.02462), 0.003738, (-0.012264), (-0.004867), 0.076726, 0.028578,
  0.019694, (-0.029094), (-0.029144), 0.019741, 0.00433, (-0.035501), (-0.016173), (-0.022151),
  (-0.022707), 0.016608, (-0.013309), (-0.033732), 0.016935, 0.003326, 0.083644, 0.25785,
  (-0.036567), (-0.016446), (-0.003752), (-0.006366), (-0.00385), (-0.045494), (-0.023941), (-0.077558),
  0.023614, (-0.002575), 0.12011, 0.00229, 0.069717, (-0.04667), (-0.050129), 0.030148,
  0.091085, 0.012819, 0.015932, 0.002278, 0.031841, 0.002696, (-0.012055), 0.021325,
  0.030486, (-0.04508), (-0.071701), 0.059218, 0.006701, 0.041047, (-0.000855), (-0.03036),
  (-0.01293), 0.037368, 0.024434, 0.057008, (-0.016314), (-0.17649), 0.17615, (-0.007391),
  0.060891, (-0.029123), (-0.045649), 0.037333, (-0.024411), (-0.059807), (-0.030106), 0.007421,
  (-0.002191), 0.020861, (-0.006699), 0.018758, (-0.044323), 0.02286, (-0.000986), 0.017239,
  (-0.034531), 0.067007, 0.23777, (-0.012903), 0.010515, 0.016969, (-0.007246), 0.010557,
  0.006138, 0.013158, 0.003131, (-0.10921), 0.008182, 0.031347, 0.031918, 0.006594,
  0.026148, 0.012845, 0.026345, (-0.015083), (-0.038887), (-0.005703), (-0.001486), (-0.028486),
  0.066225, 0.008857, 0.011356, (-0.002768), 0.011247, 0.007197, 0.031769, 0.025174,
  0.007536, 0.032873, (-0.002738), (-0.038075), (-0.038984), 0.002803, (-0.054146), (-0.008328),
  0.033778, (-0.11238), (-0.010408), (-0.004944), (-0.009303), (-0.01175), (-0.023217), 0.016866,
  (-0.024031), (-0.036946), (-0.061564), 0.021661, (-0.003671), 0.044849, 0.057195, (-0.011342),
  (-0.012004), 0.022516, (-0.019809), 0.015891, (-0.009142), (-0.004474), 0.12743, 0.047703,
  0.053608, (-0.039681), (-0.067327), 0.13338, (-0.20919), (-0.065589), 0.061883, (-0.025579),
  (-0.034827), (-0.01821), 0.015071, 0.046325, 0.015407, 0.012809, 0.049151, 0.012621,
  (-0.018769), 0.041965, (-0.051402), (-0.070961), 0.016746, (-0.00624), (-0.039398), 0.0,
  (-0.022308), 0.001892, 0.001073, 0.039231, 0.062238, 0.00214, 0.000918, (-0.006917),
  (-0.023867), (-0.10263), (-0.009524), 0.039877, (-0.013145), (-0.050591), 0.024917, (-0.007637),
  0.042912, 0.00023, 0.009093, 0.011145, (-0.052453), (-0.23021), (-0.016366), (-0.017208),
  (-0.036648), (-0.010305), (-0.013713), 0.029308, 0.024077, 0.006128, (-0.022378), (-0.007044),
  (-0.040603), (-0.024466), 0.002531, (-0.019589), (-0.029636), (-0.01503), (-0.060715), (-0.01279),
  (-0.020248), (-0.030684), (-0.020718), (-0.001729), (-0.031394), 0.019003, 0.006177, (-0.010166),
  (-0.001417), (-0.00408), (-0.044097), (-0.06067), (-0.032932), (-0.14723), (-0.01193), 0.14518,
  0.051448, 0.003148, (-0.0436), 0.129, (-0.091262), 0.014272, 0.03289, 0.01259,
  0.014661, (-0.033556), 0.14253, (-0.006208), 0.018179, 0.025037, 0.046561, (-0.009),
  0.040806, (-0.034222), (-0.039716), 0.002517, 0.027429, 0.034986, 0.004497, 0.00277,
  0.035174, 0.025971, (-0.015784), (-0.007588), 0.020754, 0.059829, 0.039039, 0.021666,
  (-0.027497), 0.010462, 0.024871, (-0.016036), 0.048627, 0.001262, (-0.088035), 0.018357,
  0.035275, (-0.20393), (-0.016619), 0.037739, 0.002272, (-0.014803), (-0.048319), (-0.029539),
  (-0.046169), (-0.028065), (-0.005734), (-0.010111), 0.01136, 0.051809, 0.033292, (-0.014494),
  (-0.034222), (-0.080654), (-0.000894), 0.097162, 0.036614, 0.051694, (-0.024557), 0.32737,
  0.007696, 0.16172, (-0.004789), (-0.018403), 0.077665, 0.018921, (-0.079398), (-0.068037),
  (-0.006101), 0.031927, (-0.029844), (-0.080542), 0.003811, 0.033647, 0.008281, 0.10104,
  (-0.010009), 0.007192, 0.024969, 0.27908, (-0.044213), (-0.014137), 0.13771, 0.034461,
  0.01858, 0.025042, 0.057179, 0.014932, 0.00889, 0.030436, (-0.04416), 0.018461,
  0.010615, (-0.045974), 0.0829, (-0.008913), 0.042814, (-0.008714), (-0.004339), 0.008075,
  0.096739, (-0.030537), (-0.060856), (-0.038162), (-0.009696), 0.048903, (-0.041612), (-0.020188),
  (-0.000979), (-0.033622), 0.019456, (-0.000318), (-0.000389), (-0.093496), (-0.077878), 0.016948,
  (-0.021459), (-0.012866), 0.007822, 0.10294, (-0.037488), 0.025506, 0.000667, (-0.28868),
  0.091295, 0.12057, (-0.073775), (-0.033128), (-0.043937), 0.1811, (-0.011851), 0.004592,
  0.007062, (-0.023715), (-0.067172), (-0.06531), 0.022791, (-0.019038), (-0.006869), (-0.040146),
  (-0.040531), (-0.012254), (-0.02722), (-0.088366), (-0.007916), (-0.04196), 0.045663, (-0.14091),
  (-0.059216), 0.004339, (-0.002037), 0.27516, (-0.026602), 0.040906, 0.005532, 0.031879,
  (-0.041482), (-0.096131), (-0.011569), 0.018313, (-0.034166), (-0.024477), 0.048957, (-0.020703),
  (-0.023002), 0.064585, 0.012666, (-0.012003), (-0.026444), (-0.025548), 0.039115, (-0.006033),
  (-0.033937), 0.040673, 0.02561, 0.1996, 0.012405, 0.039208, (-0.030844), (-0.035523),
  (-0.06165), (-0.01174), 0.066934, (-0.020631), (-0.022357), 0.00115, 0.035873, 0.03066,
  0.005556, (-0.006116), (-0.030317), (-0.00972), (-0.057127), 0.004006, 0.033734, (-0.034642),
  0.046923, (-0.008766), 0.065628, (-0.044165), 0.017305, 0.033136, (-0.02103), 0.029784,
  0.055292, (-0.033598), 0.019603, (-0.020787), 0.032536, (-0.010788), (-0.009956), (-0.003749),
  (-0.04178), (-0.034221), 0.01013, (-0.089849), 0.026098, (-0.003754), 0.031973, 0.019333,
  0.001949, (-0.044147), (-0.044682), (-0.10757), (-0.12847), (-0.044758), (-0.043991), (-0.12269),
  (-0.019983), (-0.015528), (-0.048971), 0.055976, (-0.009858), 0.013481, 0.006561, 0.007115,
  0.004816, 0.009532, (-0.027475), (-0.03952), (-0.030659), (-0.001468), 0.19078, 0.005179,
  0.024126, (-0.026384), 0.005414, 0.054216, 0.000238, 0.015217, 0.017008, 0.030497,
  0.006543, 0.14164, 0.019338, (-0.017324), (-0.006207), (-0.016109), (-0.10123), (-0.007551),
  0.044248, (-0.11636), 0.004736, 0.022459, (-0.012109), 0.05612, (-0.008738), 0.00664,
  (-0.018132), (-0.022719), 0.012705, (-0.013683), 0.031358, 0.09305, 0.02595, 0.016472,
  (-0.001878), (-0.009013), 0.022548, (-0.03778), (-0.00538), (-0.023893), (-0.026522), 0.01228,
  0.096595, (-0.027415), (-0.015767), (-0.00211), 0.012007, (-0.015422), (-0.004158), (-0.021186),
  (-0.017077), (-0.04085), (-0.008193), (-0.019238), (-0.044192), (-0.062392), (-0.001008), 0.02387,
  0.021391, 0.020255, (-0.028772), 0.00342, 0.056983, (-0.093892), 0.0177, 0.22844,
  (-0.18288), (-0.069892), 0.015297, 0.00675, (-0.015983), 0.013088, 0.013061, (-0.039907),
  0.015027, (-0.020518), (-0.022359), (-0.007915), 0.015258, (-0.031666), (-0.030774), (-0.015483),
  0.035167, (-0.017906), (-0.00318), 0.01572, 0.029864, 0.00299, 0.08475, (-0.058725),
  0.044756, 0.040369, 0.037736, 0.060753, (-0.019832), (-0.16593), 0.069015, 0.011358,
  0.0017, 0.079769, (-0.057144), 0.007383, (-0.018041), 0.094503, 0.005421, 0.007029,
  0.034516, (-0.051925), (-0.069162), (-0.005523), 0.0686, (-0.067039), (-0.021005), 0.020279,
  (-0.047108), 0.18768, (-0.043229), 0.020004, 0.008088, 0.027101, (-0.091746), (-0.012455),
  0.014649, 0.029102, 0.00878, (-0.05474), (-0.014798), 0.025013, 0.046548, 0.017624,
  0.1632, 0.013138, (-0.015665), 0.080554, 0.035364, 0.032987, 0.012195, 0.043066,
  0.030327, 0.035493, (-0.014597), 0.012607, 0.010172, 0.028843, 0.000551, 0.048344,
  0.03246, 0.03334, 0.006402, (-0.005689), 0.012698, 0.006055, 0.002642, (-0.016926),
  0.028236, 0.010429, 0.009886, 0.026015, (-0.025538), (-0.003531), 0.009245, 0.021031,
  (-0.051063), (-0.06233), (-0.032963), (-0.037418), 0.12403, (-0.008923), (-0.05988), 0.006262,
  (-0.017673), 0.017579, 0.005156, (-0.0106), 0.20884, (-0.026413), 0.058892, (-0.011579),
  0.045988, (-0.022838), (-0.008171), 0.003536, 0.049445, 0.003514, (-0.030996), 0.086453,
  (-0.13653), (-0.005769), (-0.0179), (-0.01997), (-0.057493), (-0.083056), (-0.053771), (-0.008367),
  0.055407, (-0.067181), (-0.0239), 0.005595, 0.021295, (-0.024613), (-0.019626), (-0.053266),
  0.007129, (-0.022487), (-0.082311), 0.13097, 0.014293, 0.006348, (-0.046055), 0.057694,
  (-0.006061), (-0.052163), 0.046573, 0.007531, 0.021615, (-0.017864), (-0.037195), (-0.000311),
  0.025043, 0.009345, 0.032364, (-0.00623), 0.051489, (-0.026449), (-0.01542), 0.019457,
  0.033621, 0.028906, 0.000203, (-0.049142), 0.076426, 0.023898, 0.003897, (-0.089445),
  (-0.015009), (-0.011146), 0.094579, 0.55039, 0.041381, 0.024772, 0.050999, (-0.016894),
  (-0.12162), (-0.003605), 0.11575, 0.036904, 0.011484, (-0.020234), (-0.028765), (-0.005832),
  (-0.055469), (-0.014801), (-0.007094), (-0.045124), 0.064377, (-0.014727), 0.045007, (-0.001133),
  0.049451, 0.029103, 0.034786, (-0.006131), 0.015525, 0.002925, (-0.053571), (-0.019218),
  (-0.055283), 0.056336, (-0.023824), 0.001781, (-0.037689), (-0.024145), 0.027445, 0.11554,
  (-0.022297), 0.013325, (-0.003806), (-0.002682), 0.003382, 0.037643, (-0.013862), (-0.002735),
  (-0.038337), (-0.034698), 0.023361, 0.035058, (-0.013257), 0.01274, 0.00364, 0.10065,
  0.0, 0.011709, (-0.035965), (-0.021236), 0.014874, (-0.005141), 0.02345, (-0.025062),
  (-0.000774), (-0.040484), 0.028171, 0.045693, 0.039707, 0.050517, (-0.017267), 0.080186,
  0.097676, (-0.015572), (-0.015305), (-0.016485), (-0.026142), 0.008868, (-0.026887), 0.007779,
  (-0.015974), 0.020867, 0.085482, 0.023873, (-0.039105), (-0.077947), (-0.016876), 0.11876,
  0.15624, (-0.045908), (-0.01031), 0.095769, 0.013687, 0.002399, 0.033265, (-0.033206),
  0.002798, (-0.065792), 0.002143, 0.022364, (-0.05741), 0.006655, 0.012327, (-0.008187),
  0.036681, (-0.4022), (-0.022126), (-0.013157), (-0.01286), 0.021628, 0.011896, (-0.019549),
  0.064445, 0.10898, (-0.034078), (-0.003749), (-0.010972), (-0.011485), 0.025984, 0.004216,
  (-0.047697), 0.000403, 0.1154, 0.016021, 0.056632, (-0.010726), 0.1242, (-0.00538),
  0.011908, (-0.043008), (-0.03315), (-0.021342), (-0.012219), (-0.016861), (-0.0025), (-0.045038),
  0.039058, 0.006672, (-0.016361), 0.006172, 0.045722, 0.004121, (-0.000178), 0.007111,
  (-0.049864), (-0.025012), 0.03094, 0.046271, (-0.003187), (-0.024352), 0.011974, 0.01307,
  0.059163, (-0.041095), (-0.083989), 0.044619, 0.024419, (-0.004387), 0.024608, (-0.085182),
  0.021845, (-0.016829), 0.032548, 0.002471, 0.055416, (-0.10635), (-0.007989), 0.075568,
  (-0.092806), 0.049432, (-0.011773), 0.085886, 0.081031, (-0.033841), 0.01541, 0.054906,
  0.02139, 0.007885, (-0.037545), 0.15926, (-0.06894), (-0.033695), (-0.063315), 0.00737,
  (-0.009597), (-0.13068), 0.057403, (-0.007234), 0.031099, 0.035854, (-0.031535), (-0.019437),
  (-0.007242), 0.008164, (-0.043653), 0.02657, 0.032217, (-0.072236), 0.031425, (-0.000477),
  0.002719, 0.032875, (-0.014553), 0.038018, 0.002866, (-0.041607), (-0.024803), 0.010098,
  (-0.020947), 0.022458, (-0.037111), (-0.010648), 0.055423, 0.021602, 8.7e-05, 0.014406,
  0.10777, 0.035944, (-0.003951), 0.020942, (-0.029878), 0.025972, 0.010603, 0.008582,
  0.021271, 0.074518, 0.004657, 0.001712, 0.000985, 0.028234, (-0.032678), 0.022536,
  (-0.021658), 0.00768, 0.014592, 0.027868, 0.005694, (-0.010003), (-0.004072), (-0.022594),
  (-0.03958), (-0.017538), 0.00903, (-0.007954), 0.027091, (-0.020626), (-0.07199), (-0.026965),
  (-0.047378), (-0.10896), 0.013574, (-0.006692), (-0.003907), (-0.037613), 0.008633, (-0.032097),
  0.058496, (-0.040902), (-0.019925), (-0.004602), 0.016825, 0.009479, (-0.019535), 0.010746,
  0.037927, 0.016391, (-0.019785), 0.011067, 0.005248, (-0.011142), (-0.010667), 0.10545,
  0.054828, 0.017761, (-0.031186), (-0.057296), (-0.011312), 0.030592, 0.001849, 0.011419,
  0.081403, 0.053496, (-0.023948), 0.006769, (-0.032344), 0.037863, 0.01544, (-0.044376),
  (-0.023102), 0.0194, 0.10386, (-0.018964), 0.038751, 0.022767, (-0.031357), 0.009691,
  (-0.049285), (-0.039511), 0.047998, 0.051423, 0.01428, (-0.091612), 0.006508, 0.035723,
  0.050638, (-0.014614), (-0.038663), (-0.040347), 0.023902, 0.008564, (-0.13293), 0.00984,
  0.005089, (-0.061039), (-0.000466), 0.003389, 0.021007, 0.007556, 0.02478, (-0.03562),
  0.01981, 0.01502, (-0.023138), (-0.018743), 0.4508, 0.011855, (-0.02483), (-0.044743),
  (-0.0146), (-0.024527), 0.023024, (-0.024917), 0.001013, 0.015603, (-0.026686), 0.001394,
  (-0.000648), (-0.031888), (-0.004929), 0.031168, (-0.033663), 0.011967, (-0.03468), 0.009929,
  0.059575, (-0.065428), (-0.092896), (-0.041184), 0.021448, (-0.02557), (-0.041201), (-0.017669),
  0.009006, (-0.011653), (-0.007478), 0.000855, (-0.030538), (-0.018847), (-0.008113), (-0.03483),
  0.019021, (-0.019004), (-0.089058), 0.006862, (-0.028241), (-0.000321), (-0.10829), 0.015879,
  0.008686, (-0.025235), (-0.013509), (-0.007715), 0.07158, (-0.013554), 0.002945, (-0.050833),
  (-0.008799), 0.21424, 0.013963, 0.042502, 0.019828, (-0.03356), 0.063543, 0.021933,
  (-0.078425), 0.01439, (-0.06731), 0.13047, (-0.046246), (-0.029842), (-0.000381), (-0.022379),
  (-0.001557), 0.012013, 0.024385, (-0.047181), (-0.024894), 0.021945, 0.1881, (-0.077872),
  (-0.048769), (-0.017115), (-0.00275), (-0.098794), (-0.021937), 0.061097, (-0.024564), 0.033752,
  0.038199, (-0.020118), 0.024735, (-0.024357), (-0.026442), (-0.003443), 0.10702, 0.045153,
  0.04435, 0.001084, 0.071433, 0.035838, (-0.020839), 0.42526, 0.011408, (-0.015365),
  (-0.015212), (-0.018972), (-0.003333), 0.093248, (-0.012555), (-0.02707), (-0.023677), (-0.014275),
  0.028097, 0.05084, 0.011506, (-0.014661), 0.22842, 0.11107, 0.003245, 0.08531,
  0.022048, (-0.015677), 0.33113, 0.008847, 0.04608, (-0.037703), (-0.081809), 0.21761,
  0.014878, 0.052435, 0.009143, 0.007917, (-0.026084), (-0.00294), 0.05713, (-0.006131),
  (-0.040405), (-0.020297), (-0.017189), (-0.024216), 0.056869, 0.000362, 0.009979, (-0.052625),
  (-0.013749), (-0.030517), (-0.30038), (-0.035991), (-0.055112), 0.033762, (-0.008271), (-0.00544),
  0.003106, 0.053652, (-0.12541), 0.092542, 0.038514, (-0.00202), 0.00976, 0.024095,
  (-0.017982), (-0.010555), (-0.007289), 0.023939, (-0.018366), 0.015716, (-0.048804), 0.006713,
  0.009777, 0.014745, 0.097079, 0.048286, 0.009781, (-0.039894), 0.022848, 0.006718,
  0.0596, 0.006934, 0.015757, (-0.04969), 0.052347, 0.022431, 0.041142, (-0.021632),
  (-0.082808), 0.008506, 0.078905, (-0.090207), (-0.029269), 0.00695, (-0.008063), 0.019596,
  (-0.014885), 0.025217, (-0.015856), 0.029441, (-0.008528), 0.024422, (-0.033887), (-0.002081),
  0.030359, 0.004021, 0.027681, 0.007904, 0.044031, (-0.032371), 0.020933, 0.025228,
  0.006552, (-0.058558), 0.0319, (-0.030445), 0.014933, (-0.049008), 0.083159, 0.023903,
  0.016429, (-0.011838), (-0.000168), 0.019194, (-0.010032), (-0.014004), (-0.1032), (-0.095697),
  (-0.041481), 0.00241, 0.10725, 0.003187, 0.029167, 0.011287, (-0.012001), (-0.012696),
  0.024597, 0.045953, (-0.027241), 0.040064, 0.023055, (-0.023737), 0.077522, (-0.013345),
  (-0.02172), (-0.071475), (-0.0055), 0.026741, (-0.039408), 0.025889, 0.048925, 0.036893,
  0.07893, 0.029006, 0.006309, (-0.065831), (-0.068965), (-0.11669), (-0.001306), (-0.044559),
  0.051033, (-0.031578), 0.02102, (-0.13824), 0.052229, 0.025884, (-0.012139), (-0.024238),
  (-0.025272), 0.012597, 0.057331, 0.016671, (-0.022819), 3.7e-05, (-0.00767), 0.094086,
  (-0.062267), 0.017416, (-0.022066), (-0.010404), (-0.009367), (-0.02904), (-0.021062), (-0.037001),
  0.010736, 0.16368, 0.094918, 0.035262, 0.012811, 0.13904, 0.011917, (-0.010007),
  (-0.006048), (-0.001249), 0.032382, (-0.013958), 0.001116, 2.7e-05, (-0.000257), 0.004046,
  0.014356, (-0.055375), 0.093595, 0.026625, 0.003747, (-0.031886), (-0.0226), 0.025202,
  (-0.031037), (-0.026476), (-0.013854), (-0.062925), (-0.044751), (-0.020428), (-0.008033), 0.008728,
  (-0.027202), (-0.016471), (-0.013744), 0.029165, 0.037457, (-0.02507), (-0.063812), (-0.00939),
  (-0.00076), (-0.021741), (-0.01787), (-0.024831), 0.15716, 0.069027, (-0.011022), (-0.013835),
  (-0.030941), 0.021258, 0.09308, 0.029636, (-0.000122), (-0.042098), (-0.022505), (-0.012863),
  0.02786, (-0.027808), (-0.006163), (-0.020436), (-0.012308), (-0.040494), 0.029657, 0.006838,
  0.016165, 0.050193, 0.001968, 0.02498, (-0.01581), 0.037207, (-0.079265), (-0.017152),
  0.03274, (-0.11757), 0.12057, 0.004278, (-0.072545), 0.17711, 0.008423, (-0.013035),
  0.018912, 0.021448, 0.063357, (-0.032436), (-0.023565), 0.018789, 0.031042, (-0.011227),
  (-0.012846), (-0.012792), 0.068652, 0.005279, (-0.038779), 0.006182, 0.17515, 0.11628,
  (-0.022964), (-0.05141), 0.22474, 0.009486, (-0.11846), 0.037811, 0.022202, (-0.036366),
  (-0.13185), (-0.041656), (-0.033152), 0.01577, (-0.039363), (-0.067849), (-0.026775), 0.039919,
  0.10066, (-0.081022), (-0.021258), (-0.010631), 0.000813, 0.003465, 0.018836, (-0.025632),
  (-0.004094), (-0.000892), (-0.049518), 0.011681, 0.034564, (-0.008291), (-0.022358), (-0.030801),
  0.043779, 0.043046, 0.027189, 0.009415, 0.094312, 0.17025, (-0.047148), 0.11186,
  (-0.014354), 0.034024, 0.021602, 0.021772, 0.082417, 0.084672, (-0.055128), (-0.064823),
  (-0.022769), 0.054756, (-8.9e-05), 0.098362, (-0.007093), 0.050278, (-0.005787), 0.013974,
  0.02145, (-0.029214), 0.000481, 0.001711, 0.008666, 0.063658, (-0.027968), 0.048954,
  (-0.029313), 0.12415, 0.007935, 0.030366, 0.025218, 0.010014, (-0.016775), (-0.002695),
  0.042258, (-0.048505), 0.028993, (-0.040089), (-0.041022), 0.011838, (-0.021328), (-0.023905),
  0.018009, (-0.043614), (-0.009245), 0.047485, (-0.014234), 0.003801, 0.003433, (-0.029221),
  (-0.006495), (-0.030034), 0.007836, 0.008855, 0.095974, (-0.032877), (-0.013384), 0.015236,
  0.012054, (-0.076295), (-0.01204), 0.021916, (-0.002733), (-0.048652), (-0.010464), (-0.006655),
  0.008547, 0.019914, 0.022013, (-0.052179), 0.019699, 0.02304, (-0.015038), (-0.049956),
  (-0.06927), 0.00474, (-0.033924), (-0.016231), (-0.050193), 0.056944, 0.040937, (-0.003084),
  (-0.0326), 0.098481, (-0.038185), (-0.045917), (-0.11955), (-0.12044), 0.070619, 0.008489,
  0.022711, 0.000497, 0.034652, (-0.00447), 0.023643, 0.012813, (-0.011251), (-0.041535),
  (-0.093471), (-0.02725), (-0.02176), (-0.009689), 0.069396, 0.031209, (-0.049727), (-0.020302),
  (-0.015367), (-0.050735), (-0.020726), (-0.030994), (-0.004427), (-0.045744), 0.016699, 0.003221,
  0.024434, (-0.079678), 0.04453, (-0.12528), 0.017972, 0.019184, 0.040024, 0.013559,
  0.016221, 0.011229, 0.039193, (-0.009554), 0.027879, (-0.023601), 0.02693, 0.00029,
  (-0.041125), 0.006679, 0.047865, (-0.003168), (-0.008623), (-0.007435), (-0.001877), (-0.086226),
  0.046834, (-9.2e-05), (-0.016344), 0.045704, (-0.027383), (-0.027602), 0.007694, (-0.000705),
  0.11054, 0.068766, 0.0018, 0.19232, 0.15742, (-0.049387), 0.051929, 0.049965,
  (-0.042633), (-0.037554), (-0.037175), 0.013946, (-0.000448), 0.031993, (-0.00428), 0.009855,
  0.093357, 0.01721, 0.008432, (-0.014055), (-0.007718), 0.028005, (-0.018885), (-0.018585),
  (-0.036437), 0.032455, 0.059782, 0.009821, (-0.035164), 0.002743, 0.008106, 0.088943,
  (-0.030055), (-0.021735), 0.037649, 0.002719, (-0.010548), 0.12966, (-0.017677), (-0.077052),
  (-0.01923), (-0.051223), 0.002083, 0.025418, (-0.023906), (-0.006374), (-0.037699), 0.21655,
  (-0.013401), 0.071269, 0.056111, 0.040464, 0.063155, 0.010321, 0.062607, (-0.039416),
  (-0.005396), 0.10773, 0.016982, 0.031217, (-0.023107), (-0.011204), (-0.004748), (-0.017359),
  0.018852, 0.007225, 0.018916, 0.031157, 0.020952, 0.011291, (-0.057011), 0.072194,
  (-0.019874), (-0.016693), (-0.039835), 0.02701, (-0.003942), 0.022833, (-0.068888), 0.043097,
  0.008624, 0.014561, (-0.011501), (-0.10971), 0.045228, (-0.027048), 0.018031, 0.050525,
  (-0.029924), 0.038058, 0.18564, (-0.004067), 0.010109, (-0.011567), (-0.006565), 0.010582,
  (-0.020304), 0.002353, (-0.001469), 0.008645, (-0.024326), 0.074419, 0.017078, (-0.024578),
  0.030205, 0.012136, 0.086717, (-0.042309), (-0.002642), (-0.056662), 0.023475, (-0.020803),
  0.00726, 0.3416, 0.006203, 0.032692, 0.000211, 0.000721, 0.054491, (-0.010141),
  (-0.018816), (-0.005348), (-0.010847), (-0.049926), 0.01216, (-0.002219), 0.003158, 0.004144,
  (-0.007373), 0.051812, 0.01834, 0.17491, 0.053994, (-0.32033), (-0.02706), 0.077464,
  0.023772, 0.011501, 0.032616, (-0.044383), (-0.058476), 0.019304, (-0.044706), (-0.060335),
  0.011667, 0.02801, 0.065397, 0.009624, 0.002551, 0.031847, 0.033055, 0.047601,
  (-0.019572), (-0.05473), (-0.022686), 0.10713, (-0.03638), 0.013936, 0.020992, 0.049119,
  0.036316, 0.041228, 0.015672, (-0.016286), (-0.003023), (-0.13786), (-0.009676), (-0.02484),
  (-0.13964), (-0.082154), 0.003845, (-0.006658), (-0.015898), (-0.050946), 0.016838, 0.015919,
  0.003631, (-0.086145), 0.033141, (-0.003968), (-0.024008), 0.008732, (-0.027787), (-0.19455),
  (-0.1087), (-0.019495), 0.003065, 0.059194, (-0.054208), (-0.039325), 0.082279, (-0.007448),
  0.007377, 0.007078, (-0.015582), (-0.00274), (-0.0706), (-0.011706), 0.000715, (-0.036866),
  (-0.032527), (-0.074814), 0.04147, (-0.02888), 0.046382, 0.25425, 0.0024, (-0.082806),
  (-0.011438), (-0.12913), 0.038553, 0.10191, (-0.019068), (-0.060775), 0.02468, 0.026759,
  0.01497, 0.026143, (-0.037512), (-0.005323), 0.017813, (-0.03401), (-0.015953), 0.019744,
  (-0.10375), (-0.019285), (-0.01278), (-0.016353), (-0.12764), 0.019069, 0.032481, 0.009485,
  0.005047, 0.041268, (-0.076359), (-0.072835), 0.059577, 0.020264, (-0.080301), (-0.017835),
  0.011431, (-0.025541), (-0.000769), (-0.014454), 0.008673, 0.054709, (-0.10839), 0.022997,
  0.002754, (-0.002152), (-0.022559), 0.083025, (-0.006674), 0.076485, 0.005491, (-0.010415),
  0.027608, (-0.023272), (-0.05562), (-0.040632), (-0.007356), 0.017007, (-0.037034), (-0.019633),
  (-0.023547), (-0.043353), (-0.022184), 0.016531, (-0.032744), 0.071416, 0.00081, (-0.008409),
  (-0.017254), (-0.018641), (-0.009198), 0.018538, (-0.050335), (-0.023529), (-0.0271), 0.006588,
  0.02336, 0.012947, (-0.006656), (-0.022571), (-0.063814), (-0.049945), 0.006832, (-0.055836),
  0.31957, 0.080956, (-0.014912), 0.046709, 0.006054, (-0.034376), (-0.034924), 0.003003,
  (-0.014133), (-0.006794), (-0.052886), (-0.002108), 0.018353, 0.012672, 0.012925, (-0.017921),
  0.001916, (-0.014698), (-0.014973), 0.014637, (-0.010974), (-0.00916), 0.004618, 0.023477,
  0.031767, (-0.01842), 0.019544, 0.41159, (-0.041596), (-0.010336), 0.012393, (-0.008727),
  0.016295, (-0.010484), (-0.012432), (-0.050375), 0.049548, (-0.041085), 0.001007, (-0.050143),
  (-0.008788), (-0.050171), 0.10216, (-0.014373), 0.010282, (-0.011814), 0.072115, (-0.019002),
  (-0.004699), (-0.058157), 0.001136, (-0.049415), (-0.11914), (-0.018304), (-0.00792), 0.051926,
  0.066724, (-0.013778), (-0.017761), (-0.042235), (-0.013525), (-0.011106), (-0.12285), 0.047716,
  0.031817, 0.004257, (-0.061373), (-0.002703), (-0.068544), 0.10373, 0.015799, (-0.009804),
  (-0.009023), (-0.063755), 0.038955, (-0.039803), 0.050302, 0.04625, 0.062196, (-0.064776),
  0.027523, 0.000399, (-0.00433), 0.047297, 0.012509, 0.045899, 0.19853, 0.016675,
  0.001983, 0.022448, (-0.013913), (-0.007766), (-0.013209), 0.049053, 0.020264, (-0.016828),
  (-0.16939), (-0.11336), (-0.077686), (-0.015568), (-0.066019), 0.00837, 0.035403, (-0.039051),
  (-0.00979), (-0.023047), 0.003117, 0.013136, 0.014782, (-0.060139), 0.051999, 0.024792,
  (-0.012015), (-0.098656), 0.11758, (-0.018923), (-0.028391), 0.013183, (-0.11653), (-0.003888),
  0.031229, 0.025199, (-0.028124), 0.036499, (-0.072293), (-0.041671), 0.047703, 0.065793,
  0.013905, (-0.027731), (-0.01588), 0.074128, (-0.00089), 0.017965, (-0.002538), (-0.009068),
  0.04917, (-0.030681), 0.10017, 0.003195, 0.035503, 0.000459, 0.025259, (-0.005155),
  0.001587, (-0.016205), (-0.029624), (-0.001593), (-0.054019), (-0.066211), 0.027941, 0.028957,
  (-0.020425), 0.012417, 0.043274, 0.18616, 0.031861, 0.014022, (-0.006303), (-0.005431),
  0.016823, 0.026039, (-0.02672), (-0.017042), 0.005957, (-0.002868), (-0.043775), 0.051633,
  0.008178, (-0.052842), 0.052584, (-0.012659), 0.011694, (-0.023919), (-0.061674), (-0.001828),
  0.035258, (-0.018438), (-0.038389), 0.099721, 0.084462, 0.04027, 0.058936, 0.14957,
  0.000694, (-0.033369), 0.009376, 0.043194, (-0.067555), (-0.31169), 0.029744, 0.010737,
  (-0.028841), (-0.005765), 0.028411, (-0.029008), 0.024966, 0.012036, (-0.042514), 0.010276,
  (-0.069192), (-0.004677), (-0.013924), (-0.015334), (-0.010239), (-0.050989), 0.03069, (-0.011224),
  (-0.00629), 0.078591, (-0.010179), 0.031227, 0.040197, 0.016138, (-0.045519), (-0.01813),
  (-0.014002), (-0.038816), 0.031656, (-0.01084), 0.012033, 0.070773, 0.5314, (-0.014774),
  (-0.002241), 0.049968, (-0.047702), (-0.091311), 0.03807, (-0.015539), (-0.015446), (-0.057388),
  (-0.005944), (-0.069969), (-0.025065), 0.017216, (-0.044279), 0.043989, 0.015907, (-0.092755),
  0.071037, 0.057762, (-0.016432), 0.023939, 0.012636, (-0.054348), (-0.013262), 0.006134,
  0.028991, (-0.021986), 0.005327, 0.086048, (-0.008555), 0.006779, (-0.006396), 0.008947,
  0.003259, 0.041477, (-0.006745), 0.030565, (-0.007478), 0.089089, 0.007323, (-0.018205),
  (-0.025828), 0.10936, (-0.011425), (-0.057566), 0.10278, 0.027042, (-0.013635), (-0.32158),
  0.20458, (-0.070347), 0.037831, (-0.070298), 0.063221, 0.036393, 0.00401, (-0.049106),
  (-0.071583), (-0.038009), (-0.003157), 0.019459, 0.011294, (-0.033495), 0.092035, 0.003753,
  0.012848, (-0.14316), (-0.09688), (-0.008846), 0.0159, 0.070372, (-0.037954), 0.51598,
  (-0.032843), (-0.036357), 0.006808, (-0.016114), 0.008453, (-0.13752), 0.17688, 0.007931,
  0.10972, (-0.030293), (-0.023118), (-0.00309), (-0.033392), 0.01319, 0.014661, (-0.013248),
  (-0.016219), (-0.029052), (-0.10153), 0.037754, (-0.28556), 0.15361, (-0.000212), (-0.020598),
  0.037354, 0.057275, 0.005103, (-0.054645), 0.025349, 0.024311, 0.035962, (-0.10001),
  0.084436, 0.015948, 0.033824, (-0.061996), 0.069877, (-0.027917), (-0.012764), 0.021662,
  0.10045, 0.026004, 0.028441, 0.038612, (-0.046595), (-0.042792), 0.003796, 0.042349,
  0.019599, 0.000874, (-0.004363), 0.016973, 0.036064, (-0.070865), (-0.063076), 0.02967,
  0.037874, (-0.033289), (-0.031609), 0.001074, (-0.071556), (-0.08117), 0.004486, (-0.042176),
  (-0.06564), 0.018189, (-0.05152), (-0.047151), 0.017489, (-0.025264), (-0.040745), (-0.037667),
  (-0.013411), (-7.9e-05), (-0.011415), 0.0372, 0.003405, (-0.022483), 0.023275, (-0.013917),
  0.007543, (-0.011539), 0.052502, 0.052716, (-0.011726), 0.095946, (-0.015872), 0.034818,
  0.034792, 0.016284, (-0.044319), (-0.005569), (-0.065842), (-0.073337), 0.01645, (-0.009263),
  0.005914, (-0.000847), 0.20533, (-0.016883), (-0.019111), (-0.025963), (-0.021762), (-0.02412),
  0.04713, (-0.045985), 0.026508, (-0.048615), (-0.018562), 0.012678, (-0.001192), (-0.049089),
  (-0.017437), (-0.01477), (-0.22905), (-0.12707), 0.010339, 0.006901, 0.29025, (-0.23805),
  0.062481, 0.004711, (-0.027816), (-0.01702), (-0.049755), (-0.074733), 0.032009, (-0.094464),
  (-0.015427), (-0.004054), 0.003008, (-0.010092), (-0.038818), 0.034652, (-0.004673), 0.000685,
  0.035317, (-0.02357), (-0.001911), (-0.016659), 0.66062, 0.10971, 0.013501, (-0.022872),
  (-0.081821), (-0.052728), (-0.025242), (-0.043819), (-0.018189), 0.023466, 0.034216, 0.025693,
  (-0.026565), 0.060942, 0.14475, 0.053411, 0.011408, (-0.002318), (-0.029695), 0.02725,
  (-0.00362), (-0.012579), (-0.088849), (-0.019257), (-0.016667), 0.012932, (-0.013432), 0.01881,
  (-0.006435), (-0.024249), (-0.029668), 0.005115, (-0.005782), 0.016607, 0.038228, (-0.057094),
  (-0.053883), (-0.002611), 0.29714, (-0.089063), (-0.056193), 0.037005, (-0.008484), (-0.002438),
  (-0.07164), 0.005226, (-0.006136), 0.015595, 0.025996, (-0.012085), (-0.067836), (-0.014715),
  0.025119, 0.018826, (-0.021264), 0.009461, 0.22958, (-0.038062), (-0.013485), 0.036239,
  0.006721, 0.096526, (-0.035657), 0.010772, 0.07928, 0.032841, (-0.027781), (-0.004034),
  0.007426, 0.11214, (-0.11878), (-0.041585), (-0.027966), (-0.12506), 0.23667, (-0.029476),
  0.037793, 0.072044, 0.009776, 0.052154, (-0.043791), (-0.038379), (-0.098839), (-0.12191),
  (-0.11982), 0.03091, 0.010801, 0.056845, 0.001028, (-0.028274), (-0.16014), 0.004963,
  0.046937, 0.024286, 0.070202, 0.009812, (-0.056201), 0.10983, 0.02091, 0.035032,
  0.039799, (-0.004841), 0.002344, 0.025313, (-0.032193), 0.075409, (-0.018469), (-0.012802),
  (-0.026598), 0.021989, 0.14654, 0.003531, 0.009401, (-0.008639), (-0.039193), 0.024855,
  (-0.034995), (-0.018379), (-0.013592), 0.006263, (-0.018478), 0.014236, (-0.032547), (-0.002641),
  (-0.000878), 0.047372, (-0.007079), (-0.043146), 0.020592, (-0.022367), 0.05004, 0.061795,
  (-0.041862), (-0.003196), 0.024255, (-0.017304), (-0.004147), (-0.01437), (-0.00904), (-0.12373),
  (-0.082222), 0.065659, (-0.031583), (-0.079636), (-0.01888), (-0.005015), (-0.012218), 0.001271,
  0.029744, 0.028175, 0.030345, (-0.017326), (-0.084178), 0.007495, 0.056495, (-0.005294),
  (-0.014945), 0.054919, (-0.019722), (-0.067159), (-0.014326), 0.029841, 0.051883, 0.041127,
  (-0.12865), 0.002417, 0.007703, 0.04552, (-0.078701), 0.007862, (-0.013459), 0.028827,
  (-0.027366), (-0.072918), (-0.013989), 0.043243, 0.029533, (-0.031897), 0.037869, (-0.022418),
  0.058959, 0.031223, 0.037485, (-0.020966), (-0.025478), (-0.007257), (-0.050983), (-0.02064),
  0.010673, 0.031896, (-0.023825), (-0.006068), 0.023882, 0.027966, 0.014603, 0.10872,
  (-0.014038), 0.004044, (-0.004977), (-0.085183), 0.002156, 0.36384, 0.22083, (-0.01614),
  (-0.04833), 0.01753, (-0.03431), (-0.004583), 0.12896, 0.030361, 0.044086, 0.003016,
  (-0.026337), (-0.027866), 0.011725, 0.001569, (-0.003555), (-0.031695), (-0.032097), 0.15544,
  0.088046, (-0.001672), 0.009341, 0.037138, 0.080184, (-0.000791), (-0.00504), 0.11962,
  (-0.004528), (-0.029639), 0.02665, 0.044422, (-0.02436), 0.019735, 0.005493, (-0.232),
  (-0.025614), (-0.006495), 0.003984, (-0.035813), (-0.014169), (-0.12642), 0.068678, 0.085865,
  0.015512, 0.081091, 0.018495, (-0.086321), 0.072355, (-0.078179), 0.096682, (-0.039876),
  (-0.009535), 0.000406, 0.012108, (-0.020874), 0.057888, 0.000132, (-0.017137), 0.030655,
  (-0.000787), 0.088037, (-0.039029), 0.080106, 0.039539, 0.020684, (-0.067038), 0.046815,
  0.078444, 0.06638, 0.030054, 0.01712, 0.020073, 0.033102, (-0.014882), (-0.010281),
  (-0.028695), (-0.004719), 0.32202, (-0.017045), (-0.007347), (-0.030002), (-0.011293), 0.004775,
  0.005071, 0.19344, 0.005375, (-0.068276), (-0.034933), 0.005122, 0.095312, (-0.062849),
  (-0.17041), 0.010584, (-0.041579), 0.12719, 0.082557, 0.085293, 0.055544, 0.004565,
  0.012998, 0.057892, (-0.022824), 0.048312, 0.025714, 0.006927, (-0.034447), 0.029388,
  (-0.002432), (-0.095944), 0.016834, 0.02605, 0.000365, (-0.006694), 0.018874, (-0.000163),
  (-0.076259), 0.050149, (-0.002924), 0.016244, 0.037812, (-0.01232), 0.058004, 0.004863,
  0.045691, 0.021321, 0.15679, (-0.010329), 0.002429, (-0.023339), (-0.006897), (-0.034403),
  (-0.021235), 0.002062, (-0.004219), (-0.014335), (-0.008212), (-0.009335), (-0.037938), 0.004706,
  (-0.00445), 0.005219, (-0.00954), 0.04497, 0.014209, 0.1638, 0.002558, (-0.00385),
  (-0.025222), (-0.019415), 0.01442, 0.051583, (-0.03796), (-0.029561), (-0.039111), (-0.029159),
  (-0.083617), 0.42004, 0.060005, (-0.018981), (-0.006005), (-0.058214), (-0.012271), 0.046586,
  0.001211, (-0.088642), (-0.023185), 0.04309, 0.000206, 0.008916, (-0.017753), 0.00623,
  0.02277, (-0.021535), 0.061759, (-0.07807), 0.011315, (-0.02559), (-0.038059), 0.009797,
  (-0.013842), 0.008346, (-0.07144), 0.010006, 0.11005, 0.035311, (-0.11175), (-0.11368),
  0.016668, (-0.008034), (-0.033097), 0.012548, (-0.042074), 0.025222, (-0.024269), (-0.01228),
  (-0.11377), (-0.084772), (-0.024552), (-0.009027), 0.011178, (-0.029367), 0.006364, 0.014026,
  (-0.013342), 0.28423, (-0.23724), (-0.1117), 0.12788, (-0.062901), 0.017439, 0.001232,
  0.027495, (-0.043544), 0.011026, 0.020866, (-0.022304), 0.032492, 0.01227, 0.008382,
  0.037354, (-0.014111), 0.057067, 0.004968, (-0.024493), (-0.011255), 0.034533, 0.024303,
  (-0.007879), 0.035142, 0.004626, (-0.083131), (-0.014016), 0.001245, (-0.016803), (-0.076748),
  (-0.23672), (-0.10057), 0.001324, 0.022153, (-0.11246), 0.016481, 0.068114, 0.016012,
  0.004664, 0.006758, 0.004729, 0.002587, 0.002899, (-0.030054), 0.014181, (-0.060527),
  (-0.019883), 0.031219, 0.018272, 0.001109, (-0.036714), 0.012044, 0.074749, (-0.23473),
  0.14096, 0.006179, (-0.057217), (-0.055227), (-0.021583), 0.025748, (-0.013099), 0.00228,
  0.008806, (-0.00897), 0.004023, 0.025017, (-0.005901), 0.004385, (-0.033772), 0.044523,
  (-0.040929), 0.039352, (-0.070323), 0.035743, (-0.042962), (-0.021008), (-0.15742), 0.007866,
  0.023622, 0.074692, (-0.000648), (-0.016291), (-0.033134), 0.048798, 0.002287, 0.045304,
  0.10706, (-0.040525), 0.031969, (-0.057617), 0.013594, 0.071396, (-0.014896), (-0.010026),
  0.003759, 0.016263, (-0.040176), 0.027081, 0.05242, (-0.01916), (-0.003773), 0.075762,
  (-0.022173));
 HaarWL: Array[0..5825] Of Single = (
  2.0875, (-2.2172), (-1.8634), 1.3272, (-1.5105), 1.0626, (-0.87464), 1.176,
  (-0.77946), 1.2608, 0.55751, (-1.8743), (-1.6912), 0.4401, (-1.477), 0.4435,
  (-0.85909), 0.85256, 1.2436, (-1.5713), (-1.6205), 1.1818, (-1.9416), 0.70069,
  (-0.5567), 1.7284, 0.26764, (-2.1832), (-2.673), 0.45671, (-1.0853), 0.53564,
  (-0.352), 0.93339, 0.92782, (-0.6635), 1.1577, (-0.29775), (-0.41961), 1.3576,
  1.459, (-0.19739), 1.1187, (-0.52916), (-0.35127), 1.1441, (-0.60851), 0.77099,
  0.38818, (-1.5123), (-1.0131), 1.4687, (-1.6464), 1.0001, 0.4648, (-1.596),
  (-0.65512), 0.83022, (-1.3982), 0.42551, (-0.50703), 1.0526, 0.36357, (-1.3465),
  (-0.30461), 1.4504, (-0.40286), 1.2146, 1.0539, (-0.4572), (-1.6253), 0.15379,
  0.28403, (-1.5662), (-1.0147), 0.23295, (-0.16733), 1.2804, 1.5162, (-0.30271),
  1.7632, (-0.051832), (-0.31389), 1.5358, (-0.10018), 0.93655, (-0.4038), 0.96293,
  0.17039, (-2.9603), 0.88787, (-0.43819), (-0.37219), 0.40019, 0.065924, (-2.6469),
  (-1.7491), 0.28475, (-0.93908), 0.23205, (-0.052664), 1.0757, (-1.8294), 0.099562,
  1.1559, (-1.0716), (-1.5635), 0.76877, (-0.5745), 1.3809, (-1.4571), 0.5161,
  (-0.83534), 0.58522, (-0.31312), 1.1697, (-0.43443), 0.95447, 1.4906, (-0.13816),
  (-0.96362), 0.27665, (-2.4464), 0.2362, 0.17539, (-1.3423), 0.48711, (-0.89852),
  0.17874, (-1.6342), (-1.9607), 0.18102, 0.99011, (-0.38103), (-2.5794), 0.24754,
  1.4412, (-0.29508), (-0.49609), 0.63174, (-2.3314), 0.054497, (-0.84447), 0.38738,
  (-1.4432), 0.098423, 0.18223, (-1.2587), 0.069808, (-2.3821), 0.39333, (-0.27543),
  0.14833, (-1.1369), 0.24628, (-1.2687), (-0.75449), 0.27164, (-0.36395), 0.70959,
  (-2.3222), 0.035744, 0.42194, (-0.048185), 1.11, (-0.3485), (-3.327), 0.21299,
  (-1.2173), 1.0827, (-0.48289), 1.4045, (-1.0782), 0.7404, (-1.202), 0.37749,
  (-0.43939), 1.2647, (-0.1844), 0.45726, 0.30397, (-0.95991), 1.2488, 0.046228,
  (-0.59442), 0.53963, 0.28496, (-1.4895), 0.48121, (-0.52712), 0.26744, (-1.6008),
  (-1.3108), 0.15243, 0.45614, (-0.72051), (-1.7321), 0.068363, (-0.19303), 0.68243,
  (-1.6095), 0.075268, 0.74287, (-0.2151), (-0.26835), 1.3094, (-0.058793), 1.2196,
  (-0.35143), 0.84927, (-1.0507), 0.29806, 0.82548, (-0.32687), 0.20453, (-0.8376),
  0.20578, (-0.6683), (-1.297), 0.13897, (-1.3111), 0.075752, (-1.0524), 0.19241,
  (-1.3735), 0.066781, (-0.037136), 0.77846, (-0.99851), 0.12248, 1.4461, 0.013152,
  (-0.37121), 0.52842, (-0.57569), 0.39262, 0.016116, (-2.1173), (-0.081609), 0.98782,
  (-1.1512), 0.096459, 0.37315, (-0.14585), 0.26179, (-0.58157), 0.75477, (-0.17055),
  0.22654, (-0.63876), (-1.264), 0.25261, 0.87068, (-0.27105), (-1.3902), 0.23612,
  0.06614, (-1.2645), (-0.53842), 0.30379, (-0.35343), 0.52866, (-0.58702), 0.24061,
  (-0.33349), 0.51916, 0.69795, (-0.014896), 0.86146, (-0.25986), 0.19333, (-0.59131),
  (-0.89233), 1.0434, (-1.2598), 0.55317, (-0.86254), 0.63732, (-0.74639), 0.53156,
  (-1.265), 0.36154, (-0.9829), 0.36013, 0.64068, (-0.50125), (-0.24035), 0.85448,
  (-0.34274), 1.1429, 1.0977, (-0.17975), 1.5735, (-0.31433), (-0.27582), 1.0449,
  (-1.0974), 0.19801, 0.30548, (-1.3288), 0.25807, (-0.70053), (-1.2306), 0.22609,
  0.40759, (-0.51235), (-0.094755), 0.61765, (-0.41101), 0.47631, 0.25249, (-0.6867),
  (-0.93928), 0.11448, 1.2451, (-0.056519), (-0.32528), 0.82792, 0.34784, (-0.17929),
  0.055098, (-1.5481), (-1.0256), 0.24107, 1.0302, (-0.31672), 0.21621, (-0.8259),
  (-1.5958), 0.051139, (-1.0312), 0.13092, (-1.4782), 0.037212, (-0.24024), 0.49334,
  0.28942, (-0.5726), (-0.23148), 0.63766, (-1.2108), 0.064018, 0.24461, (-0.99787),
  (-1.3699), 0.036052, 0.21288, (-1.0398), 0.32444, (-0.54292), (-0.28324), 0.44468,
  (-2.3107), (-0.00314), 0.28716, (-0.64481), (-0.27175), 0.80219, (-1.5318), 0.21424,
  0.077038, (-1.0581), 0.14307, (-0.85828), (-1.102), 0.064907, 0.013964, 0.63601,
  (-0.34546), 0.56297, 0.19927, (-1.504), (-0.40904), 0.37796, (-2.2227), 0.12178,
  (-0.28652), 0.67891, (-0.88885), 0.94937, (-1.1147), 0.48889, (-1.0098), 0.49724,
  0.25991, (-1.2537), (-0.57139), 0.59659, (-0.55203), 0.30217, (-1.2871), 0.22354,
  1.7425, (-0.099747), (-1.0523), 0.18363, 0.56784, (-0.46742), 1.3083, (-0.26461),
  (-0.46211), 0.4175, (-0.41475), 0.59205, 0.36103, (-0.45781), (-0.89239), 0.14199,
  0.29353, (-0.97331), (-0.79335), 0.18313, 0.15523, (-1.3246), 0.034215, (-2.0948),
  (-0.39451), 0.51334, 0.088373, (-1.2814), 0.55287, (-0.46385), (-1.8497), 0.045944,
  (-0.48224), 0.34761, (-0.45155), 0.42806, (-0.84521), 0.16675, 0.35348, (-0.47163),
  0.18463, (-1.6687), (-1.2522), 0.035992, (-0.8162), 0.23429, (-0.92585), 0.10035,
  0.56499, (-0.18882), 0.80302, (-0.38277), (-0.84927), 0.19671, (-0.40592), 0.50695,
  (-1.5298), 0.23345, 0.63008, (-0.3178), 0.58628, (-0.012108), (-0.25624), 1.041,
  0.29171, (-0.83287), (-0.39633), 0.45662, 0.21024, (-1.5005), 0.44071, (-0.38654),
  0.93955, (-0.10589), 0.009448, (-1.68), (-1.0134), 0.24147, (-0.37508), 0.46614,
  (-0.80484), 0.17817, (-1.0562), 0.073305, 0.20166, (-1.5468), (-0.37938), 0.37886,
  0.2122, (-1.24), (-1.0258), 0.051283, (-1.0305), 0.23005, (-0.20869), 1.2273,
  0.8793, (-0.044255), 1.0443, (-0.21682), 0.13798, (-1.9009), (-1.6608), 0.005844,
  0.7994, (-0.082407), (-0.96074), 0.06632, 0.19899, (-0.76433), (-1.0363), 0.82201,
  (-1.2328), 0.29648, (-0.75852), 0.57986, (-0.38984), 0.8968, (-0.71799), 0.50441,
  0.55148, (-0.70555), (-0.44782), 0.70986, (-1.0932), 0.26702, 0.83618, (-0.38318),
  (-0.25733), 0.25967, 0.31631, (-0.58797), (-1.0491), 0.16822, 0.16144, (-0.87877),
  (-0.69054), 0.23607, 0.24989, (-0.56583), (-0.50416), 0.38375, 0.042619, (-1.3876),
  0.14119, (-1.0689), (-0.89622), 0.19796, (-0.45337), 0.43533, 0.33823, (-0.44793),
  (-0.78909), 0.22512, (-2.2831), (-0.005396), 0.39347, (-0.52242), 0.032799, (-1.5079),
  (-1.084), 0.18482, (-1.8822), (-0.00222), 0.14593, (-2.2197), (-1.0165), 0.058797,
  0.15443, (-1.1844), (-0.77306), 0.1219, (-0.1145), 0.71091, 0.070001, (-1.0535),
  (-1.7594), 0.19524, 0.9584, (-0.25046), 0.46732, (-0.21108), 0.70836, (-0.28018),
  (-1.1013), 0.24341, (-1.0933), 0.056259, (-0.26438), 0.19821, (-0.22142), 1.0526,
  0.18486, (-1.7204), (-0.92721), 0.058753, 1.9647, 0.027786, 0.21428, (-0.48408),
  (-1.1754), 0.16061, (-1.124), 0.04111, (-0.1717), 0.32179, 0.8272, (-0.26377),
  (-1.1525), 0.14999, (-1.0492), 0.040161, (-1.0904), 0.15331, 0.42249, (-0.42399),
  (-0.91867), 0.18486, (-1.5959), 0.002576, (-0.663), 0.31037, 0.19183, (-0.65085),
  (-0.63643), 0.15408, (-0.18919), 1.5295, (-0.10598), 0.6486, (-1.0803), 0.037176,
  0.34157, (-0.097738), 0.47625, (-0.34366), 0.97634, (-0.019173), (-2.1753), (-0.028926),
  (-0.64383), 0.16494, (-1.4746), 0.002584, 0.42441, (-0.17713), 0.025445, (-1.2779),
  0.15678, (-1.5188), (-0.40424), 0.3243, (-1.9932), 0.15019, (-0.62162), 1.1117,
  1.0143, (-0.61335), (-1.0262), 0.3978, (-1.1386), 0.28691, (-0.56646), 0.45172,
  0.30506, (-0.6813), (-1.7209), 0.061439, 0.23192, (-1.7297), (-1.2163), 0.1216,
  0.32554, (-0.81004), (-0.31699), 0.67361, (-0.1109), 0.84083, 0.39575, (-0.47625),
  (-0.00018), 0.94571, 0.75206, (-0.31532), (-0.8314), 0.17744, (-0.59378), 0.24657,
  0.15998, (-0.42782), 0.035056, (-1.5989), (-0.52034), 0.37828, (-0.53183), 0.24951,
  0.19983, (-1.4446), 0.044427, (-1.3623), (-0.9102), 0.2719, 0.092065, (-0.81629),
  0.21186, (-0.74729), (-0.27301), 0.80923, (-0.10432), 0.86226, 0.062709, (-0.98894),
  (-0.92691), 0.15586, 0.13418, (-0.70386), 0.19707, (-0.40263), (-1.141), 0.073998,
  0.1699, (-0.72152), (-0.4739), 0.26255, (-2.1607), 0.14555, 0.044751, (-1.0766),
  (-0.032919), 1.2154, (-1.3188), 0.015504, 0.3685, (-0.15284), (-0.25728), 0.70655,
  (-0.077603), 0.33368, (-0.78525), 0.076934, 1.7022, 0.049722, 0.77671, (-0.24534),
  (-1.4923), 0.1234, (-2.1345), (-0.025797), 0.56983, (-0.12057), 0.67911, (-0.26638),
  0.2479, (-0.64493), 0.014716, (-1.2396), (-0.008256), 1.0168, 0.45067, (-0.36251),
  (-0.95293), 0.20685, (-2.014), (-0.023085), 0.39572, (-0.29351), (-0.2498), 1.0859,
  (-0.057844), 1.2162, 0.043063, (-1.0636), (-0.48947), 0.17183, (-0.29689), 0.51798,
  (-0.59806), 0.24803, (-0.029614), (-2.3163), 0.37458, (-0.32779), (-0.99693), 0.072948,
  0.14176, (-1.7239), (-0.21273), 1.0165, (-1.3164), 0.14982, 0.49422, (-0.29091),
  0.4243, (-0.33899), (-0.031047), (-2.346), (-0.7899), 0.15418, (-2.2509), (-0.030907),
  (-0.25577), 0.23786, (-0.22541), 0.92307, (-0.28896), 0.31046, (-0.034864), (-2.7103),
  0.59715, (-0.033831), (-0.47738), 0.22686, 0.22878, (-1.0436), (-0.25818), 0.7678,
  (-0.59798), 0.2804, 0.70987, (-0.25645), (-0.55871), 1.0954, (-0.71172), 0.529,
  (-1.1158), 0.40594, (-0.40892), 0.7413, (-0.38054), 0.73648, (-0.69946), 0.37951,
  (-0.54559), 0.36332, (-0.10125), 0.79586, 0.84411, (-0.32976), 0.26327, (-0.96737),
  0.15252, (-1.059), (-1.9918), 0.13629, (-0.32037), 0.60304, 0.59587, (-0.2114),
  0.022925, (-1.4679), (-0.4399), 0.2044, (-0.89067), 0.1047, 0.21164, (-0.40232),
  0.01332, (-1.6085), 1.0064, (-0.13413), (-1.469), 0.009424, (-0.81636), 0.26171,
  0.11562, (-0.71693), 0.1305, (-1.6448), (-1.1796), 0.025017, 0.63188, (-0.1049),
  0.18508, (-0.53566), (-0.93128), 0.20072, 0.038029, (-1.0112), 0.36458, (-0.27611),
  0.19666, (-0.53411), (-1.6772), 0.20727, (-3.0761), (-0.035804), 0.21447, (-0.71376),
  (-1.1468), 0.015856, 0.83812, (-0.065944), (-0.28027), 0.79377, 0.17832, (-0.68412),
  0.9619, (-0.21736), 0.010104, 1.2461, (-0.53488), 0.14746, 0.82173, (-0.014948),
  (-0.19605), 1.0803, (-0.023849), 1.1393, (-1.3584), (-0.004204), (-0.64483), 0.24142,
  0.84285, (-0.20625), 0.19212, (-1.2222), (-0.72677), 0.052688, (-0.36305), 0.29224,
  0.058116, (-0.67162), 0.47142, 0.01858, (-1.1332), 0.023781, 0.98254, 0.028362,
  (-0.28214), 0.58993, (-0.63712), 0.26515, 0.37487, (-0.33232), (-1.3049), 0.15724,
  (-2.0458), (-0.026926), 0.77649, (-0.042971), 0.17424, (-0.44601), (-1.5036), 0.1429,
  0.28667, (-0.37924), 1.3847, 0.065027, (-0.22452), 0.79521, (-1.5879), 0.11359,
  (-1.1946), (-0.007164), (-0.15529), 0.40664, 0.25928, (-0.38368), (-0.088498), 0.76788,
  0.75024, (-0.22622), 0.12159, (-1.4567), (-0.36612), 0.25969, (-0.075019), 0.48485,
  0.7822, (-0.21992), (-0.89456), 0.14681, 0.82714, (-0.20276), 0.016368, 0.27307,
  1.1307, (-0.18811), (-0.57791), 0.15812, (-0.022565), (-1.6373), (-0.54512), 0.24087,
  (-1.2237), (-0.007344), 0.14696, (-0.44967), (-0.27874), 0.43877, (-0.24289), 0.2535,
  (-0.85865), 0.026026, 0.69288, (-0.002116), (-0.16589), 1.5209, 0.43857, (-0.21614),
  (-0.97998), 0.022133, (-0.90475), 0.64411, (-0.79217), 0.5749, (-0.301), 1.3144,
  (-0.89883), 0.29206, (-0.41955), 0.53463, 0.45793, (-0.44629), 0.91311, (-0.27373),
  (-1.4698), 0.20364, (-1.0483), 0.067802, 0.29274, (-0.52283), (-1.2855), 0.044551,
  (-0.85754), 0.18434, 0.16406, (-0.69125), 0.15756, (-0.84263), 0.021637, (-1.3635),
  (-0.16737), 0.25888, (-0.97272), 0.0661, 0.98474, (-0.016448), 0.47605, (-0.32517),
  (-0.95921), 0.19938, (-0.52613), 0.22429, 0.1707, (-1.0738), (-1.1343), 0.03654,
  0.25832, (-0.71536), 0.19641, (-0.53355), (-0.051195), 0.97611, 1.0632, (-0.23463),
  (-0.18583), 0.4589, (-0.029382), (-2.6651), 0.9998, 0.024937, (-0.029606), (-2.1696),
  (-0.000756), 0.74652, (-1.5274), 0.01106, 0.033575, 0.99526, 0.76613, (-0.24671),
  0.16263, (-0.61134), (-0.9784), 0.02897, 0.46146, (-0.1351), 0.25458, (-0.51956),
  (-0.80565), 0.15209, (-1.3138), (-0.00358), 0.20176, (-0.6134), 0.97633, (-0.20885),
  (-0.18808), 0.47706, (-0.6798), 0.11289, 0.18952, (-1.4967), (-0.2361), 0.81321,
  0.2483, (-0.069212), (-1.0419), 0.048053, 0.51346, (-0.00738), 1.6202, (-0.18668),
  2.9869, 0.095428, 0.60405, (-0.27059), (-0.61791), 0.15997, 0.66327, (-0.23637),
  (-1.1229), 0.19617, (-1.077), 0.020693, 0.81168, (-0.017252), (-0.022529), (-1.7357),
  0.67881, (-0.05818), 0.057848, (-0.77255), (-0.13147), 0.67056, (-0.37881), 0.30979,
  (-0.5847), 0.25602, (-0.30217), 0.41253, 0.59155, 0.017964, 0.96913, (-0.2102),
  0.91156, 0.04055, (-0.6049), 0.16961, 0.043515, 0.81893, (-0.93617), 0.024937,
  0.18176, (-0.34186), (-1.2913), (-0.003428), (-0.046292), 0.2527, (-0.012848), (-1.4305),
  (-0.26677), 0.33588, (-0.51367), 0.13005, 0.41576, (-0.31241), (-0.24821), 0.70828,
  (-0.22637), 0.19185, 0.065227, (-0.8881), 0.18891, (-0.27398), (-0.94867), 0.024197,
  0.36938, (-0.17495), 0.96159, (-0.20005), (-3.0699), 0.11364, 0.22921, (-0.45645),
  (-0.000316), 0.39225, 0.95234, (-0.20202), (-0.099177), 0.2037, 0.008728, (-1.0217),
  0.64813, (-0.090149), (-0.03676), (-1.9276), 0.69261, (-0.068375), (-0.4057), 0.18626,
  (-0.64518), 0.21976, 0.97776, (-0.18654), (-0.10547), 0.37404, 0.61064, (-0.26881),
  (-1.0184), 0.57529, (-0.41298), 1.0091, (-0.58588), 0.56606, (-0.92857), 0.30924,
  0.11951, (-1.118), (-0.5785), 0.33154, (-0.38325), 0.52462, 1.1791, (-0.034167),
  (-0.86266), 0.11868, (-0.74951), 0.21011, 0.92129, (-0.28253), 0.26663, (-0.70014),
  (-0.28454), 0.73169, (-0.61493), 0.15576, 0.57551, (-0.34362), 0.326, (-0.13008),
  0.089323, (-0.96026), 0.34449, (-0.46712), 0.23696, (-0.52563), (-0.74268), 0.21702,
  (-0.90472), 0.066012, (-0.34447), 0.21504, (-0.93389), 0.050471, (-0.53204), 0.17241,
  0.92075, (-0.22149), (-0.71054), 0.18324, (-0.87063), 0.05533, (-0.22854), 0.52416,
  (-0.30326), 0.55861, 0.26902, (-0.70262), (-1.1835), 0.046512, (-0.54652), 0.25962,
  (-0.26983), 0.58171, (-0.91046), 0.19678, (-0.44003), 0.2135, 0.023605, 0.77172,
  0.79229, (-0.24645), 0.80268, (-0.036072), (-0.20072), 1.1031, (-0.045968), 0.72095,
  (-0.90357), 0.044988, 0.35297, (-0.37711), (-0.19584), 1.1199, (-1.3998), 0.19145,
  0.00236, (-1.1611), (-0.48908), 0.16743, (-1.2203), (-0.011976), 0.37228, (-0.085063),
  (-0.29413), 0.59406, (-1.4396), 0.13579, (-2.2545), (-0.033971), 0.37701, 0.015848,
  (-0.29446), 0.53159, (-0.99788), 0.16236, 0.047657, (-0.7525), 0.14874, (-0.65375),
  (-0.014952), (-1.2275), (-0.14264), 0.43273, (-0.019281), (-1.1946), (-1.7328), 0.14375,
  (-0.24141), 0.5402, 0.005768, 0.56578, 0.038181, (-0.7937), 0.076453, 1.4813,
  (-1.6972), (-0.02737), 0.62976, 0.031763, (-0.33463), 0.30077, 0.22741, (-0.38225),
  0.19224, (-0.52735), 0.091492, 2.1049, (-1.7452), (-0.04091), (-0.24215), 0.35578,
  1.178, (-0.17677), 0.13936, (-1.2994), (-0.54609), 0.13916, (-0.21597), 0.39258,
  0.063189, (-0.72108), 0.68668, 0.063273, 1.7412, (-0.16619), 0.30695, (-0.16663),
  (-0.21405), 0.73185, (-0.79361), 0.20526, 0.37344, (-0.29619), (-0.0152), 0.40555,
  1.2117, (-0.17464), (-0.022909), 0.69646, (-1.0602), (-0.000556), (-0.032751), 0.53805,
  0.037548, (-0.74769), (-0.08179), 0.33387, (-1.9214), (-0.038953), 0.48361, 0.018168,
  (-0.19907), 0.72815, 0.19871, (-0.49217), (-0.195), 0.77317, 1.8087, 0.068323,
  0.78065, (-0.1871), 0.15285, (-1.6021), (-0.16738), 1.1902, (-0.10285), 0.39176,
  (-0.035624), (-1.6098), (-0.056359), 0.54159, 0.28063, (-0.31709), 0.1264, (-1.0298),
  0.020753, (-0.79106), 0.19057, (-0.8384), 0.073729, (-0.62781), 0.047385, 1.5713,
  (-0.27315), 0.38572, 0.054594, 0.52583, 0.38153, (-0.28332), 0.15455, (-0.30501),
  0.023637, (-0.87218), 0.16091, (-0.20278), (-0.61545), 0.080936, (-0.84905), 0.56974,
  (-0.81417), 0.44782, (-0.36424), 0.67937, (-1.1885), 0.19239, 0.33085, (-0.71334),
  (-0.50991), 0.11376, (-1.0471), 0.20223, (-0.50559), 0.36441, (-0.99542), 0.12602,
  (-0.094138), 0.5778, 0.23273, (-0.5257), (-0.10316), 0.47658, (-0.001092), (-1.5582),
  (-0.65451), 0.18843, 0.28141, (-0.44575), 0.15612, (-0.21371), (-0.2917), 0.52234,
  1.3661, 0.030466, 1.2207, (-0.22434), (-0.82017), 0.14532, (-1.2218), 0.019449,
  0.12082, (-0.98729), (-1.1688), 0.021105, (-1.0689), 0.1986, (-0.3623), 0.38001,
  0.49094, (-0.14607), 0.58728, (-0.27774), (-0.075195), 0.60193, 0.27637, (-0.37794),
  (-0.00536), 1.0318, 0.82336, (-0.22481), 0.13098, (-1.1854), (-0.90668), 0.044127,
  0.010144, 1.0741, 1.7792, (-0.17315), 0.57386, (-0.074106), (-0.32073), 0.40183,
  0.19288, (-1.2167), 0.069568, (-0.71324), (-0.38862), 0.18099, (-0.025793), (-1.5453),
  (-1.9199), 0.16613, (-1.2823), (-0.015908), (-0.4041), 0.23592, (-0.72892), 0.056235,
  0.57831, (-0.015796), 0.91512, (-0.21121), (-0.51931), 0.18576, 0.2411, (-0.39649),
  0.16771, (-2.5665), (-1.3659), (-0.014232), (-1.7085), 0.16508, (-0.31374), 0.32838,
  0.14953, (-0.4858), 0.74346, (-0.22305), (-0.40918), 0.18893, 0.81382, (-0.20854),
  0.32996, (-0.59937), (-1.2552), (-0.020413), 1.3821, 0.059309, (-0.035844), (-1.5396),
  (-0.18475), 0.37455, (-0.44901), 0.13877, 0.67833, (-0.017072), (-0.011956), (-1.2261),
  0.33959, 0.000628, (-1.0621), (-0.01378), 0.14539, (-1.2385), (-0.24468), 0.51377,
  0.13073, (-0.70997), (-1.0475), 0.000496, (-1.5127), 0.14801, 0.13972, (-0.46867),
  0.28632, (-0.41795), (-0.27336), 0.43445, 0.18439, (-0.95019), 0.32582, (-0.30816),
  0.11416, (-1.9795), (-1.1067), (-0.008552), 0.80139, (-0.032035), (-0.26449), 0.38754,
  0.016052, 0.58841, 0.015216, (-0.94724), (-0.30766), 0.21236, (-1.6059), (-0.031095),
  0.074759, 1.1639, (-0.006432), (-1.1151), (-0.24106), 0.20859, 1.9158, (-0.15721),
  (-0.25174), 0.1818, (-0.69349), 0.044928, 0.18102, (-0.74979), (-0.030974), (-1.6746),
  0.06391, 0.76561, 0.01138, (-0.88559), 0.1489, (-2.4634), 0.38871, (-0.2988),
  (-1.5543), 0.16301, 0.21843, (-0.37312), (-0.047061), 0.59404, (-0.25509), 0.55397,
  (-0.18129), 0.40683, 0.54311, (-0.23822), (-0.69172), 0.15943, 0.29448, (-0.34006),
  0.92201, 0.094093, (-0.7954), 0.031522, 0.33096, (-0.050887), (-1.372), (-0.021409),
  0.063902, 0.91478, 0.36051, (-0.28615), (-0.1562), 0.5316, 0.13423, (-0.44359),
  0.10572, (-2.5589), (-0.010088), (-1.1074), (-0.002772), 0.56701, (-0.46889), 0.12636,
  (-0.008428), 0.87469, (-0.34434), 0.20852, 1.4983, 0.057328, (-0.99234), (-0.009392),
  (-0.57682), 0.16861, (-0.033775), (-1.389), 0.40182, 0.001836, 0.18146, (-0.41743),
  0.54683, 0.01822, 0.68352, (-0.1965), (-0.89984), 0.51876, (-0.56524), 0.70551,
  0.3608, (-0.66865), (-0.55573), 0.3579, (-1.0713), 0.1885, (-0.71584), 0.26344,
  (-0.46931), 0.26658, 0.21099, (-1.0804), 0.66912, (-0.27943), (-0.95332), 0.24051,
  0.81433, (-0.24919), 1.233, 0.00686, (-0.30795), 0.70714, 0.21206, (-1.44),
  (-0.90261), 0.04861, 0.22655, (-0.44644), (-0.39818), 0.34665, 0.18384, (-1.3411),
  0.15536, (-0.51582), 0.21651, (-0.72705), (-1.479), (-0.024317), (-0.16844), 0.19527,
  0.037336, (-0.87557), 0.33467, (-0.2411), 0.005532, (-1.251), 0.45212, (-0.08447),
  0.1525, (-0.48487), (-1.3025), 0.17984, (-0.24411), 0.62271, 0.028122, 0.92394,
  (-0.22333), 0.77674, 0.2032, (-1.0896), 0.68598, (-0.23304), (-0.010292), 0.61881,
  (-0.2007), 1.0088, 0.47615, 0.045624, (-1.1077), 0.004524, 1.0153, 0.016328,
  0.41723, (-0.28646), 0.21405, (-0.16773), (-1.1564), (-0.010324), 0.35359, (-0.29611),
  (-1.5374), (-0.029958), 0.20244, (-0.7127), (-0.025933), (-1.5157), 0.16803, (-0.38806),
  (-1.1958), (-0.020361), (-1.0899), 0.1453, 0.2805, (-0.41336), (-0.043491), 0.41264,
  (-0.2643), 0.55128, 0.60189, 0.018921, 0.38153, (-0.29508), 0.13247, (-0.46267),
  0.11739, (-0.51664), (-0.34008), 0.20954, (-0.17053), 1.4367, 0.61296, (-0.04155),
  (-0.48554), 0.13373, (-4.0258), 0.10877, (-0.3918), 0.22427, (-0.08643), 0.37785,
  1.1454, (-0.19737), (-0.021105), 0.58453, 0.037817, (-0.66987), 0.56366, (-0.076878),
  (-0.17343), 1.167, 1.2641, 0.043399, 0.66978, (-0.21605), (-0.41199), 0.20215,
  (-0.91583), 0.039233, 0.003872, 0.35668, (-0.37304), 0.19235, (-0.42375), 0.2443,
  (-0.16559), 1.2697, 0.14894, (-2.1535), 1.3779, (-0.16198), (-0.33829), 0.21153,
  0.76518, (-0.19693), (-0.69271), 0.21657, (-0.011984), (-0.99697), (-0.10206), 0.48884,
  1.0666, (-0.17576), 0.18525, (-0.7479), (-0.2202), 0.5451, 0.25488, (-0.5074),
  (-0.011256), (-0.95968), (-0.28545), 0.16995, (-0.03614), (-1.3133), 0.33093, 0.013308,
  (-0.3483), 0.24042, (-1.439), 0.156, (-1.1806), (-0.012348), 2.2119, 0.062737,
  (-1.871), (-0.0455), (-0.76913), 0.1533, (-0.62987), 0.0516, 0.85429, 0.00626,
  (-0.032459), (-1.3326), (-0.19424), 0.37329, 2.0606, (-0.15043), (-0.11611), 0.25455,
  (-0.01634), (-1.0449), (-0.041998), 0.39681, (-0.66423), 0.033443, (-0.058232), 0.37857,
  0.61019, (-0.21006), (-0.571), 0.17848, 0.056363, (-0.64731), 0.17482, (-0.98909),
  (-0.66805), 0.032267, 0.29445, (-0.00136), (-0.28345), 0.47171, (-0.10835), 0.57193,
  (-0.050939), (-1.906), 0.45105, (-0.00976), (-2.0349), (-0.051019), 0.17041, (-1.2279),
  (-0.021797), (-1.0823), 0.30467, (-0.37067), (-0.3117), 0.23657, (-1.7982), 0.15254,
  (-0.051888), (-1.9017), 0.21026, 0.021657, (-0.20293), 0.60944, (-0.95371), 0.18568,
  (-0.14405), 2.1506, (-1.0912), 0.13228, 0.10253, (-0.51745), 0.058965, 1.2354,
  (-1.3432), (-0.034463), 0.049602, 1.6055, (-1.0261), (-0.004156), 0.084643, 0.95221,
  (-0.14687), 1.936, 0.6589, (-0.69755), (-0.90728), 0.30479, (-0.49775), 0.57133,
  (-0.42565), 0.58097, (-0.47906), 0.43016, 0.50862, (-0.19986), (-0.23264), 1.0993,
  0.40569, 0.056855, 0.45133, (-0.33333), (-0.85016), 0.22342, (-0.93082), 0.059217,
  (-1.2795), 0.18447, 0.58427, (-0.26007), (-0.053789), 0.71176, (-0.86962), 0.075215,
  (-0.075007), 0.90782, (-0.24795), 0.72272, (-1.1238), 0.20988, (-1.4499), (-0.0151),
  0.53865, (-0.11375), 0.066889, (-0.76873), 1.1414, 0.040217, (-0.24719), 0.59295,
  (-0.040025), 0.32688, 0.58729, (-0.25396), 0.15315, (-0.56042), 0.16959, (-0.52627),
  (-0.14945), 0.29659, (-0.39944), 0.25157, 0.27973, (-0.47204), (-0.00292), (-1.13),
  0.41112, (-0.26221), (-1.4294), (-0.019133), (-0.25014), 0.15979, 0.043739, (-0.69986),
  (-0.94138), 0.23204, (-0.27186), 0.45319, (-1.0315), 0.14422, 0.63107, (-0.25521),
  0.16207, (-1.7723), (-0.25016), 0.5412, (-0.29009), 0.33508, (-0.007884), (-1.1677),
  0.11292, (-2.494), (-0.19481), 0.95758, 0.30928, (-0.2553), (-0.007632), (-1.0086),
  (-0.46028), 0.19507, (-0.012188), (-1.0036), (-0.075969), 0.4167, (-0.26649), 0.39112,
  0.18274, (-0.36052), (-0.18938), 0.92658, (-0.14506), 0.33295, (-0.52464), 0.08988,
  (-0.38382), 0.24393, (-0.005788), (-1.2617), (-0.57953), 0.16955, 0.022281, (-0.8787),
  (-0.65109), 0.12967, (-0.33965), 0.22013, 0.15077, (-0.50452), (-0.25045), 0.45742,
  (-0.10949), 0.55758, (-0.97366), 0.018468, 0.38222, (-0.16921), (-1.0391), 0.005184,
  (-5.5109), 0.11164, 0.95486, (-0.18585), 0.010436, 0.82115, 0.22633, (-0.34568),
  0.1643, (-1.3926), (-0.86366), 0.002388, (-2.8193), 0.1157, (-1.2946), (-0.024661),
  (-0.81306), 0.11831, 0.65938, (-0.20844), 0.007424, 0.53152, 0.30656, (-0.31084),
  0.25576, (-0.052932), (-1.435), (-0.015448), (-0.16884), 0.42125, (-0.64979), 0.04111,
  (-0.052964), 0.63368, (-0.92101), 0.009064, 0.5376, (-0.062997), (-0.54334), 0.084105,
  0.15564, (-0.40171), (-0.24245), 0.51509, (-0.51118), 0.13832, (-0.21855), 0.62829,
  0.1164, (-2.7302), (-0.014636), (-1.0797), 1.2166, 0.033275, (-0.25388), 0.44039,
  0.22497, (-0.24216), 0.25018, (-0.30812), (-0.32729), 0.26168, (-0.05575), (-1.9606),
  (-0.001952), 0.73866, (-0.30647), 0.26347, (-0.24601), 0.17082, 0.47034, (-0.26048),
  0.38629, (-0.28817), (-0.048826), (-1.7639), 0.211, (-0.025941), (-0.1683), 1.0279,
  0.11532, (-1.2482), (-0.046304), (-1.7166), (-0.40247), 0.20562, (-0.33152), 0.20683,
  (-0.72633), 0.20074, (-0.15631), 1.6697, 0.19487, (-0.35384), 0.82094, (-0.18194),
  (-0.43044), 0.12375, (-0.029726), (-1.1598), 0.1115, (-4.6835), 2.1774, (-0.14544),
  (-0.049446), 0.34018, (-0.32803), 0.30531, 1.1521, 0.027306, (-0.388), 0.21513,
  (-1.6775), 0.15774, (-0.97648), (-0.010552), 0.20844, (-0.68993), (-0.16665), 1.2149,
  0.23628, (-0.41397), (-0.92831), (-0.018345), (-0.73647), 0.19497, 0.14198, (-0.42089),
  0.011644, 0.78487, (-1.191), (-0.035128), 2.4315, 0.065648, 0.71755, (-0.19108),
  0.15646, (-0.79295), (-0.81451), 0.58875, 0.93213, (-0.29367), (-0.56463), 0.41648,
  (-0.79233), 0.16975, (-1.4169), 0.025021, 0.37982, (-0.41567), (-0.40769), 0.35548,
  (-0.2408), 0.86113, (-0.87467), 0.098572, 0.15566, (-0.6923), (-1.1472), 0.03636,
  0.15516, (-0.6952), 0.04199, (-0.96623), 0.43397, 0.002416, 0.43481, (-0.32522),
  (-0.094574), 0.72421, (-0.38133), 0.30098, 0.89301, (-0.10296), 0.8628, (-0.21716),
  0.60069, (-0.15906), (-1.5873), (-0.021817), 0.16853, (-0.38107), 0.50811, (-0.2728),
  (-0.43139), 0.26438, (-0.31624), 0.55716, 1.0554, 0.029074, (-0.71874), 0.065391,
  0.24884, (-0.20978), (-0.68844), 0.06359, (-0.59153), 0.27944, 0.045224, (-0.88639),
  (-0.6159), 0.15749, (-0.30607), 0.42293, (-1.3735), 0.15909, (-0.5586), 0.12119,
  0.004972, 0.82055, 1.5651, (-0.16817), (-1.5795), 0.14662, (-1.5519), (-0.02997),
  0.17196, (-0.69343), (-1.3061), (-0.024337), (-1.3821), 0.14802, (-0.7089), 0.036524,
  (-0.040914), 0.80373, 0.57547, (-0.24992), (-0.49281), 0.19811, (-0.48858), 0.13563,
  (-0.60278), 0.18522, 0.23566, (-0.35136), (-0.081305), 0.2107, (-1.2066), (-0.014252),
  0.2335, (-0.45665), (-0.81076), 0.01314, 0.61542, 0.032983, (-0.29583), 0.27004,
  (-0.61103), 0.17357, (-0.53323), 0.068539, (-1.288), 0.11802, (-0.17073), 1.1104,
  (-0.10995), 0.46011, 1.0221, (-0.18694), (-0.78317), 0.14203, (-0.88061), 0.01106,
  0.11369, (-1.1033), (-0.81097), 0.003408, (-0.07288), 0.34998, (-1.2869), (-0.028842),
  0.47614, (-0.1469), (-0.059702), (-2.4802), 0.1742, (-0.43911), (-0.19965), 0.70655,
  (-0.069136), 0.61643, (-1.2741), (-0.025673), 0.12404, (-1.0776), 0.014952, (-0.71023),
  0.62034, 0.033611, (-0.36325), 0.17308, 0.52374, 0.0128, (-0.17122), 1.1235,
  (-1.1908), 0.17426, 0.83931, (-0.18064), 0.35533, (-0.23842), (-0.87944), (-0.000784),
  (-0.14253), 0.25876, (-0.29015), 0.26051, (-0.031439), 0.58696, 0.6943, (-0.21816),
  (-0.64599), 0.15612, (-0.027742), (-1.1347), (-0.010076), 1.2429, 0.85008, (-0.19015),
  (-2.0763), 0.12179, (-0.85687), 0.007876, 0.38645, (-0.11391), (-1.7234), (-0.056063),
  0.54749, (-0.042482), (-0.038945), (-1.0808), 0.58311, (-0.000976), (-0.013796), (-0.8473),
  0.15114, (-0.79473), 0.51579, (-0.21445), (-0.022105), 0.42918, (-0.86201), (-0.003676),
  (-0.45397), 0.22463, 0.13073, (-0.38623), 0.13159, (-0.79307), (-0.25297), 0.40672,
  0.022613, 0.79618, (-0.39158), 0.11639, 0.082467, 1.2531, (-0.18203), 0.77079,
  (-0.61744), 0.15891, (-0.048978), (-1.8422), 0.17918, (-0.15383), (-0.84017), (-0.001028),
  (-0.18996), 0.17131, (-0.79542), 0.00668, (-0.23531), 0.2473, (-0.054758), (-1.8324),
  0.26385, (-0.38526), (-0.6693), 0.020341, 0.67265, (-0.014344), 0.30186, (-0.28514),
  0.14766, (-1.4079), (-0.18614), 0.79953, 0.19118, (-0.085035), 0.45239, (-0.22205),
  0.13488, (-1.2895), (-0.20754), 0.54562, 0.32054, (-0.16404), (-0.20211), 0.53297,
  0.15699, (-0.17014), (-0.62863), 0.040762, 0.16609, (-1.0326), (-0.25076), 0.31661,
  0.15352, (-1.6334), 0.56874, (-0.20103), 0.57125, (-0.67439), (-0.3861), 0.90344,
  0.22242, (-1.2779), (-0.2869), 0.75742, (-0.6488), 0.22269, (-0.29254), 0.3103,
  0.45533, (-0.38501), (-0.51264), 0.27432, 0.015788, (-1.2133), 0.39175, (-0.30867),
  1.1902, (-0.20347), (-0.68239), 0.20459, (-0.8494), 0.038433, (-1.1039), 0.15975,
  (-0.19595), 1.1807, (-0.40848), 0.32939, (-0.29673), 0.41548, (-1.3069), 0.17863,
  0.23666, (-0.44537), 0.29018, (-0.1121), (-2.4238), (-0.042831), 0.88206, (-0.047013),
  0.80119, (-0.20491), 0.14618, (-1.1349), (-0.81605), 0.018988, (-0.70981), 0.22344,
  (-0.72809), 0.040225, 0.17171, (-1.1164), 2.768, (-0.14612), 0.1161, (-3.9636),
  (-0.00764), (-0.98781), 0.2306, (-0.7497), (-0.31138), 0.30288, (-0.04953), 0.5269,
  (-1.1611), (-0.0057), (-0.27189), 0.23598, (-0.54219), 0.081914, 0.17976, (-0.67049),
  0.62664, (-0.2097), 0.24194, (-1.0444), (-0.94061), (-0.003752), (-0.075432), 0.61575,
  0.039285, (-0.8481), 0.16969, (-0.50906), (-0.033103), (-1.2706), 0.09433, 2.7203,
  (-0.39533), 0.15364, (-0.22767), 0.13914, (-0.27392), 0.342, (-0.10874), 0.48125,
  (-0.049522), (-2.0117), 0.15037, (-0.11272), (-0.020885), (-1.1652), (-0.80213), 0.14372,
  (-0.20837), 0.61678, 0.20306, (-0.75326), (-0.18118), 1.0033, 0.49999, (-0.034663),
  1.1712, (-0.18434), (-0.063225), 0.29025, (-0.23275), 0.59696, (-0.82212), 0.17772,
  0.60861, (-0.21469), (-0.042666), 0.60512, (-1.1508), (-0.027286), (-0.009188), 0.56858,
  0.37659, (-0.2715), (-0.099991), 0.24665, 0.66827, (-0.20615), 0.15832, (-0.76061),
  0.38212, (-0.25408), 0.15105, (-0.28753), (-0.68003), 0.034327, 0.25414, (-0.26859),
  (-0.030842), (-1.1477), (-0.35254), 0.29868, (-0.038149), (-1.3262), (-0.023737), 0.70503,
  0.10675, (-0.45261), 0.46675, (-0.061547), (-0.28448), 0.43846, (-0.022537), 0.70389,
  (-0.32555), 0.24024, (-1.2228), 0.11669, (-0.019305), (-1.0973), 0.65583, 0.075091,
  (-0.52156), 0.11523, (-0.78304), 0.16657, (-0.002688), (-0.85282), (-0.051011), 0.41999,
  0.019233, (-0.65049), (-0.6241), 0.15411, 0.17589, (-0.34339), 0.043419, 0.79069,
  0.45649, (-0.22495), 0.33571, (-0.00488), (-2.3378), (-0.058933), (-0.66154), 0.20099,
  0.45939, (-0.22314), (-0.26899), 0.24923, (-0.1864), 0.7277, (-0.024609), 0.28644,
  (-0.034683), (-1.1163), 0.006376, 0.66632, 0.4242, (-0.2628), (-0.021957), 0.18937,
  (-0.034964), (-1.0989), 0.1111, (-2.9306), 0.29102, (-0.27408), 0.11878, (-0.62802),
  0.14814, (-0.37007), (-0.53725), 0.19358, (-0.060194), (-1.949), (-0.4523), 0.18742,
  1.2144, (-0.15366), (-2.3047), 0.11, (-0.71855), 0.020101, 0.073545, 0.98786,
  (-1.2227), (-0.043507), 0.13409, (-1.1771), (-0.03081), (-0.9348), 0.13334, (-1.4998),
  (-0.14539), 1.5632, 0.19384, (-0.67643), (-0.37465), 0.10858, 0.81059, 0.030202,
  0.83773, (-0.17141), (-0.94647), 0.13123, 0.046008, (-0.52012), (-1.9424), 0.13201,
  (-0.21481), 0.48674, 0.5999, 0.007916, (-0.2207), 0.54046, 0.62958, (-0.021713),
  (-0.23361), 0.49761, 0.18042, (-0.22039), (-0.69732), 0.015712, 0.34593, 0.07147,
  (-0.87583), (-0.009824), 0.2365, (-0.28731), (-0.061531), (-2.2326), (-0.1985), 0.40811,
  0.96488, (-0.20246), (-0.058909), 0.27055, (-0.45317), 0.089628, 0.11605, (-1.0951),
  1.8097, (-0.14773), 0.23068, (-0.42418), 0.4927, (-0.20631), 0.60924, 0.02813,
  0.40171, (-0.21682), (-0.84877), 0.14247, (-0.79198), (-0.012596), (-0.67489), 0.1283,
  0.03678, (-0.63393), 0.13804, (-0.47189), (-0.13856), 1.9492, 0.13722, (-2.1187),
  (-0.20008), 0.49508, (-0.46581), 0.76432, (-0.94399), 0.39726, 0.32719, (-0.63367),
  0.27428, (-0.57447), 0.23629, (-0.68594), (-0.5763), 0.27493, (-0.61062), 0.24542,
  (-0.56539), 0.27179, (-0.80236), 0.11509, (-0.81206), 0.23845, 0.1391, (-0.66163),
  (-0.16485), 0.41902, 1.4426, (-0.1882), 0.13548, (-0.91636), (-0.33748), 0.39234,
  (-0.11615), 0.44399, (-0.99498), 0.001612, (-0.48067), 0.17007, 0.03558, (-0.80215),
  (-1.0895), 0.18082, 0.95671, (-0.21049), (-1.037), 0.22167, 0.90199, (-0.19085),
  (-1.0119), 0.14691, 0.61624, (-0.23553), (-0.08328), 0.21729, 0.065459, (-0.60319),
  (-0.93447), 0.1527, (-0.84177), 0.013332, 0.60567, (-0.092021), (-0.028114), (-1.4015),
  0.13081, (-0.49382), (-1.1289), (-0.0146), 0.75872, (-0.00182), 0.29936, (-0.29488),
  0.019725, 0.19994, (-0.85248), 0.04917, (-0.059986), 0.15223, 0.35603, (-0.2626),
  0.000156, 1.0429, (-0.033007), (-1.1797), 0.58988, (-0.057648), 0.59503, (-0.24419),
  (-1.1724), 0.16907, (-0.018901), (-1.0685), 0.16306, (-1.3375), (-0.22525), 0.454,
  0.27409, (-0.37371), (-0.75829), 0.017137, (-0.22759), 0.23699, 0.19252, (-0.32127),
  0.16724, (-1.0209), 1.2825, (-0.17225), (-0.54073), 0.23886, 0.63355, (-0.21091),
  (-0.49778), 0.17403, (-1.1849), (-0.033891), 0.021741, 1.007, 0.029218, (-0.59906),
  (-0.21001), 0.37637, 0.002532, (-0.71668), (-0.21921), 0.32299, (-0.009684), (-0.77573),
  0.44638, (-0.06176), (-0.20495), 0.57722, (-0.76745), 0.1255, (-1.4122), (-0.051704),
  0.19334, (-0.63634), 0.84325, (-0.18019), 0.1253, (-2.1214), (-0.46604), 0.089644,
  0.51827, 0.016824, (-0.03091), (-1.1047), 0.24446, (-0.38613), 0.98004, (-0.17017),
  0.20248, (-0.38546), (-0.25717), 0.35181, 0.16995, (-0.91384), (-0.85682), (-0.021681),
  0.56116, (-0.000224), (-0.2546), 0.34513, 0.007572, 0.348, (-0.6022), 0.042815,
  0.4202, (-0.053801), 0.22725, (-0.32398), 0.093532, 10.0, (-0.26926), 0.33303,
  (-0.72365), 0.17807, (-0.35119), 0.16586, 0.11623, (-1.5419), (-0.009148), (-0.99843),
  0.20565, 0.015432, 0.58072, (-0.20118), 0.018729, 1.0829, (-0.33171), 0.19903,
  1.3711, 0.068927, (-0.000936), (-0.83997), (-0.011964), 0.36674, 0.37867, (-0.27715),
  (-2.7481), 0.10667, 0.47524, (-0.2325), (-0.57929), 0.17434, (-0.011284), (-0.83701),
  0.34822, (-0.17455), 1.4226, (-0.14766), 0.23947, 0.013272, (-0.009), (-0.75939),
  (-0.018685), 0.76245, (-0.90439), (-0.008588), (-0.2132), 0.2192, 0.19598, (-0.35768),
  (-0.092795), 0.26146, (-0.55336), 0.027386, 0.18446, (-0.66934), 1.9383, (-0.14709),
  (-0.26452), 0.20733, (-0.55032), 0.050375, (-2.5615), 0.13142, (-0.2482), 0.39983,
  0.16179, (-0.71419), 0.2218, (-0.29182), 0.31044, (-0.002728), (-0.95673), (-0.00834),
  0.12557, (-1.176), (-0.058877), (-1.8568), 0.042858, 0.39037, (-0.043567), (-1.1094),
  0.040257, 0.98442, 0.02951, (-0.69509), 1.0339, 0.067602, (-0.068683), (-2.4986),
  (-0.59482), 0.15002, (-0.064823), (-2.1383), 0.05531, 0.78293, (-0.007128), (-0.72148),
  0.14609, (-1.3637), (-0.17785), 0.72858, (-0.59402), 0.19358, (-1.0784), (-0.040734),
  0.779, 0.003496, (-0.065684), (-1.8188), (-0.017892), 0.20768, (-0.055947), (-1.4154),
  0.34135, (-0.1209), (-0.26287), 0.25797, (-0.13179), 0.1735, 0.028518, (-0.61152),
  0.026182, 0.30307, 0.44941, (-0.22803), (-0.1988), 0.20744, (-0.54037), 0.067866,
  (-0.013128), 0.52298, 0.068299, (-0.49235), 0.68184, 0.078781, (-0.20622), 0.50388,
  0.71285, (-0.58231), (-0.36863), 0.60067, (-0.86008), 0.21725, (-0.27187), 0.61248,
  (-0.34748), 0.50428, (-0.31899), 0.41377, (-0.69048), 0.094831, (-0.2083), 0.23737,
  (-0.49367), 0.18171, 1.343, 0.039769, 0.046496, (-0.81643), (-0.71198), 0.22554,
  1.0058, (-0.1969), (-0.0126), 0.80767, (-0.82024), 0.020525, 0.54211, (-0.074767),
  (-0.33828), 0.42359, (-1.1983), 0.15566, (-0.8903), 0.011004, 0.16664, (-0.90764),
  0.62695, (-0.25791), (-0.2823), 0.26625, (-0.63772), 0.098423, (-0.7677), 0.22635,
  0.456, (-0.26529), (-0.76551), 0.14009, 0.046756, (-0.72356), (-0.049142), 0.51473,
  (-0.020069), (-1.0851), (-0.95875), 0.14544, (-0.70014), 0.029158, (-0.28236), 0.25368,
  (-0.25303), 0.46527, (-0.69916), 0.13217, 0.45895, (-0.23856), 0.18269, (-0.6163),
  (-0.63258), 0.034219, (-1.0298), 0.17387, 0.34757, (-0.27464), (-0.2898), 0.24038,
  (-0.44341), 0.14267, 0.1774, (-0.24096), (-0.010812), (-0.94691), 1.6547, 0.096487,
  (-0.006756), (-0.86312), (-0.002352), 0.38531, (-0.61906), 0.031078, 0.70657, 0.047881,
  0.39213, (-0.23848), (-0.024309), 0.25386, 0.4693, (-0.23322), 0.32319, (-0.20546),
  (-1.2278), (-0.040798), 0.045184, 0.60198, (-0.16773), 0.89819, 0.33716, (-0.27241),
  (-0.85447), 0.019665, 0.054742, 0.63827, 0.52275, (-0.23385), 0.62829, 0.032859,
  (-0.61573), 0.03468, (-0.8438), 0.16531, (-0.063261), (-1.9864), (-0.17663), 0.38011,
  (-0.027606), (-0.91921), (-0.24293), 0.22879, (-0.23706), 0.54011, 0.39079, (-0.12694),
  (-0.26664), 0.32313, 0.17541, (-0.60788), (-1.0853), (-0.028046), 0.71887, 0.027982,
  (-1.1906), (-0.044811), 0.62942, 0.009504, 1.3234, (-0.15027), (-0.33947), 0.17086,
  (-0.25658), 0.47652, 0.14154, (-0.34942), (-1.1676), (-0.040758), (-0.39486), 0.15815,
  0.493, (-0.20092), 1.8736, 0.08673, (-0.88938), (-0.00732), (-1.1665), 0.14275,
  (-0.66815), 0.004412, (-0.47955), 0.15122, 0.12049, (-0.45236), (-0.077615), 0.27847,
  (-0.19987), 0.67254, 0.92222, 0.092558, (-0.26691), 0.33321, (-0.54253), 0.13976,
  0.01822, (-0.68049), (-0.012584), 0.54127, (-0.17639), 0.7881, 0.20738, (-0.47744),
  0.023077, (-0.61182), (-0.017728), 0.41764, (-0.18948), 0.74019, 0.40947, (-0.13509),
  (-0.20351), 0.61625, (-1.6967), 0.14633, (-0.030402), (-1.0909), (-0.20076), 0.22314,
  (-0.45242), 0.057392, 0.23825, (-0.21262), (-0.18195), 0.61918, (-0.27393), 0.25017,
  (-0.4628), 0.042398, 0.41797, (-0.001708), 0.14602, (-0.33721), 0.75143, 0.010712,
  (-0.1912), 0.48415, 0.3522, (-0.17333), (-0.64398), 0.009068, 0.018216, 0.31971,
  1.0564, (-0.17276), 0.29715, (-0.00946), (-0.2166), 0.47385, 0.24049, (-0.26776),
  (-0.033539), (-1.0234), (-0.004324), 0.57153, 0.077575, (-0.42093), 0.082022, 2.881,
  (-0.13708), 2.089, (-1.8611), 0.14332, (-0.18737), 0.54232, 0.14175, (-1.5626),
  1.6059, (-0.14713), (-0.80975), 0.13257, (-1.3945), (-0.057055), 0.033427, 0.57475,
  (-0.55327), 0.021953, 0.020341, 0.37459, 0.44429, (-0.23), 0.18316, (-0.40965),
  (-0.063661), (-1.6929), 0.20154, (-0.46061), (-0.32004), 0.15312, 0.86882, 0.032575,
  0.63687, (-0.18426), 0.17357, (-0.47884), 0.24102, (-0.26548), 0.54233, 0.053633,
  2.3909, (-0.13635), 0.15911, (-0.67581), (-0.002348), (-0.73054), (-0.11444), 0.3057,
  (-1.0511), (-0.033103), (-0.20135), 0.32754, (-0.21384), 0.43362, 0.10941, (-4.7609),
  (-1.7169), (-0.060919), 0.64779, (-0.032831), (-0.01006), (-0.76569), 0.19889, (-0.082479),
  (-0.86614), (-0.025986), 0.13912, (-2.2272), 0.33968, (-0.2399), (-2.5018), 0.12842,
  0.50641, (-0.19752), (-2.9333), 0.13859, (-0.60044), 0.029718, 0.33916, (-0.14392),
  (-1.1083), (-0.047377), 0.44534, (-0.067053), (-1.0407), (-0.04179), 0.033863, 0.82017,
  0.52903, (-0.19133), (-0.53631), 0.60715, (-0.50142), 0.43976, (-0.32922), 0.54835,
  (-0.31702), 0.46153, 0.10695, (-0.98244), (-0.1433), 0.71095, 0.9438, (-0.21572),
  (-0.54612), 0.25304, 0.012496, (-1.0809), (-0.31536), 0.5124, (-0.00452), (-1.2443),
  (-0.76493), 0.20641, 0.24093, (-0.35142), (-0.097008), 0.20638, (-0.7902), 0.021853,
  (-0.10395), 0.54844, (-0.40409), 0.26764, 0.20508, (-1.0206), 0.00124, (-0.87293),
  (-0.005556), 0.80356, (-0.36478), 0.22768, (-1.4296), 0.14322, (-0.04185), (-1.9112),
  0.26425, (-0.32618), (-0.83908), 0.000408, (-0.48858), 0.16436, (-0.18862), 0.83419,
  0.23232, (-0.07236), (-0.035884), (-1.1549), (-1.7837), 0.15159, (-0.21608), 0.50624,
  (-0.17796), 0.28958, (-0.011408), (-0.89402), 0.30172, (-0.043659), (-0.95147), (-0.019973),
  0.033111, 0.9662, 0.97964, (-0.17262), (-0.020801), 0.27386, (-0.056803), (-1.7775),
  0.65329, (-0.023537), 0.026317, (-0.70666), (-0.005604), 0.32874, 0.34205, (-0.30172),
  (-0.00736), 0.57982, (-0.52722), 0.046448, (-0.58529), 0.19102, 0.021073, (-0.68893),
  (-0.36401), 0.15339, 0.036164, (-0.59825), (-0.14708), 0.37508, (-0.21709), 0.51937,
  (-1.0847), 0.14085, (-0.15514), 1.1823, 0.044231, 0.91561, (-1.5504), (-0.054746),
  0.16663, (-1.0001), (-0.77079), (-0.004864), 0.11062, (-1.6858), 1.1076, (-0.15439),
  0.27452, (-0.18456), (-0.80626), (-0.016928), 0.14188, (-0.25501), 0.19826, (-0.31171),
  (-0.050591), 0.41924, (-0.16675), 0.92749, (-0.12626), 0.40445, (-0.032635), (-0.9894),
  (-0.064534), 0.25474, (-0.36619), 0.11973, 0.12073, (-1.0291), (-0.52177), 0.033735,
  0.65182, 0.00134, 0.17371, (-0.34132), (-0.197), 0.15045, (-0.50889), 0.030762,
  (-0.069252), 0.18745, (-0.40849), 0.079955, (-0.21125), 0.22366, (-0.499), 0.062917,
  (-0.20553), 0.22097, 0.18097, (-0.43496), 0.0152, 0.37992, (-0.20921), 0.40013,
  0.24752, (-0.26713), (-1.9094), (-0.066961), (-0.71371), 0.15905, (-0.1697), 0.77553,
  0.19022, (-0.60162), 0.007704, (-0.6173), 0.17159, (-0.70978), (-2.2606), (-0.073277),
  2.4088, 0.083092, (-0.27082), 0.2737, 0.31356, (-0.062492), (-1.4515), (-0.058761),
  (-0.018085), 0.5048, (-0.23303), 0.30709, 0.14136, (-0.50011), (-0.22055), 0.39191,
  (-0.11382), 0.20032, 0.025477, (-0.53326), 0.17808, (-0.62794), (-0.14748), 1.4204,
  (-0.52693), 0.15839, 0.88232, (-0.16628), (-0.48387), 0.15, (-0.21336), 0.42334,
  (-0.074198), 0.14589, (-0.24912), 0.26771, 0.008796, 0.43065, (-0.17592), 0.69283,
  0.13145, (-0.33597), (-0.045692), (-1.3516), 0.17544, (-0.06055), (-1.1308), (-0.039533),
  (-0.22454), 0.23628, 0.45377, (-0.21099), (-0.15105), 0.20782, (-0.6835), (-0.008004),
  0.65011, 0.046544, 0.44887, (-0.23592), (-0.088173), 0.27347, (-0.46867), 0.077002,
  0.29268, (-0.021941), (-1.2094), (-0.04211), (-0.045596), 0.50181, (-0.26904), 0.26516,
  (-0.13046), 0.31807, 1.9444, (-0.13978), 0.15267, (-0.030866), (-0.71202), (-0.013844),
  0.92008, 0.046724, (-0.22567), 0.31932, (-0.72337), 0.17019, 1.2462, (-0.14736),
  (-1.4465), 0.12145, (-0.78153), (-0.023733), (-0.85471), 0.16687, (-0.14854), 1.1273,
  0.54727, 0.035524, 0.36643, (-0.20544), (-0.035008), 0.53994, (-0.61537), (-0.003532),
  (-0.065591), 0.41961, (-0.3413), 0.12537, (-0.3024), 0.21511, 0.076553, (-0.41061),
  (-0.97356), 0.11242, 0.18561, (-0.29755), (-0.05965), 0.24825, 0.32752, (-0.2306),
  (-0.2932), 0.15428, (-1.2144), (-0.052244), 0.13062, (-2.3274), (-0.66075), (-0.009096),
  0.1663, (-0.66949), (-0.054642), (-1.2676), 0.20277, 0.014668, (-0.78714), (-0.024469),
  0.28623, (-0.030894), 1.7293, (-0.14294), 0.019233, 0.37733, (-0.074534), (-3.3869),
  0.31814, 0.019261, 0.76936, (-0.17644), 0.18396, (-0.30869), (-0.23455), 0.33057,
  0.17214, (-0.18249), (-0.046464), (-1.1318), 0.80404, 0.06966, (-0.81884), (-0.018225),
  0.14958, (-0.18667), (-0.72852), (-0.016616), 0.56944, 0.013832, 0.040525, (-0.41773),
  (-1.9825), 0.1196, 0.50231, (-0.19746), 0.40195, (-0.026958), (-0.76609), (-0.024209),
  0.86579, 0.064206, (-0.5593), (-0.001688), 0.040722, 0.48925, (-0.19232), 0.5114,
  0.18707, (-0.16114), (-0.048818), (-1.1326), 1.4169, 0.08732, 1.319, (-0.14819),
  0.048377, 0.85612, (-0.21044), 0.33859, (-1.2464), 0.11857, 0.25782, (-0.24565),
  0.2295, (-0.29498), (-0.86253), (-0.000704), 0.31511, (-0.14349), 0.25148, (-0.28233),
  0.26601, (-0.28191), (-0.54144), 0.61043, 0.7174, (-0.41196), (-0.5827), 0.29646,
  (-0.74244), 0.14183, 0.1788, (-0.68549), (-1.0776), 0.12389, 0.024501, (-1.0252),
  (-0.45283), 0.2123, (-0.26973), 0.4858, (-0.48871), 0.31616, 0.41513, (-0.30045),
  0.16204, (-0.99869), (-1.1024), 0.021125, 0.65033, (-0.027938), 0.42117, (-0.26764),
  0.35278, (-0.37854), (-0.2919), 0.41054, (-1.3216), 0.12967, (-0.87702), 0.00108,
  0.26106, (-0.21481), (-0.9909), (-0.009956), 0.63454, (-0.056547), 0.024665, (-0.73327),
  (-0.56297), 0.1664, (-0.0003), (-0.93286), (-0.09538), 0.25185, (-0.65497), 0.067301,
  (-0.46493), 0.16071, (-1.0594), (-0.019617), 0.50716, (-0.15339), (-0.30498), 0.73506,
  (-1.114), 0.18, (-0.86908), (-0.01246), 0.65943, (-0.035324), (-0.22953), 0.42425,
  0.18356, (-0.98587), (-0.33147), 0.21323, (-0.11951), 0.29753, 0.38499, (-0.24434),
  (-0.89384), 0.14218, 0.53864, (-0.20485), (-0.056679), 0.39971, (-1.5239), (-0.051183),
  0.074574, 1.2448, (-0.19666), 0.5989, (-0.64021), 0.15808, 0.085239, (-0.45487),
  (-0.43184), 0.22453, 0.40203, (-0.23904), 0.5287, 0.039709, (-0.38754), 0.14193,
  0.87528, 0.085508, (-1.1649), (-0.033943), 1.0931, 0.051187, 0.13696, (-0.3385),
  0.13662, (-0.40778), (-0.014936), (-0.81708), 0.17625, (-0.32492), (-0.52745), 0.044443,
  (-0.10979), 0.22068, 0.39068, (-0.22225), (-0.25451), 0.1779, (-0.025125), (-0.87121),
  0.79083, 0.020121, (-0.47907), 0.052232, (-0.17245), 0.34528, 0.003776, (-0.65334),
  0.016364, 0.58724, 0.19994, (-0.32056), 0.1845, (-0.23794), (-0.060382), (-1.6072),
  (-0.32756), 0.15058, (-0.62394), 0.013112, (-0.033115), 0.5558, 0.19883, (-0.37636),
  0.20373, (-0.42801), (-0.56847), 0.044199, 0.74642, 0.043679, 0.8509, (-0.17774),
  0.16785, (-0.29877), (-1.3303), (-0.049182), (-0.060539), 0.18483, 0.76448, (-0.18357),
  0.22656, (-0.063157), (-1.5899), (-0.061255), 0.12072, (-1.412), (-1.3117), (-0.051936),
  (-0.002164), 0.44247, 0.65378, (-0.18724), 0.071847, 0.81496, (-0.67427), (-0.000432),
  0.33312, 0.055794, 0.45572, (-0.20305), (-0.044687), 0.22682, 0.26695, (-0.26117),
  (-0.83018), 0.13249, (-0.67499), 0.017092, (-0.072287), 0.14426, 0.030922, (-0.55861),
  0.13666, (-0.29411), (-0.59444), 0.0153, 0.40497, (-0.003356), (-1.0898), (-0.040225),
  0.28922, (-0.25195), 0.65313, (-0.18054), (-1.9571), 0.14815, (-0.22876), 0.34234,
  0.15976, (-1.0092), (-0.38881), 0.08421, 1.7153, 0.059325, (-0.38162), 0.085127,
  (-3.0926), 0.11788, (-0.13769), 1.9009, (-0.06266), 0.25918, (-0.56292), 0.043923,
  0.25287, (-0.041226), (-2.6179), (-0.074006), 0.059033, 0.85946, 0.936, (-0.15639),
  0.13726, (-2.555), (-0.013964), (-0.71026), 0.059526, 1.6509, 0.71369, (-0.1727),
  0.14632, (-0.081429), (-0.37145), 0.10153, (-0.23756), 0.26798, (-0.027682), (-0.8491),
  0.1873, (-0.56001), (-0.15601), 0.97073, 0.14896, (-1.1016), (-0.16615), 0.82211,
  (-0.07125), 0.28811, (-0.020981), (-0.78417), (-0.18166), 0.20492, (-0.45596), 0.063577,
  0.26632, (-0.17796), (-0.15477), 1.107, 0.068915, 0.69867, 0.27607, (-0.25139),
  (-3.0768), 0.11618, (-1.4639), (-0.051447), 0.8843, 0.043307, 0.13672, (-0.34506),
  (-1.03), 0.11601, 0.076429, (-0.44003), 0.1198, (-0.72668), 0.67375, (-0.18196),
  0.21265, 0.036756, 0.44742, (-0.20987), 0.037544, 0.27808, (-0.19842), 0.54336,
  0.13531, (-0.11154), 0.84039, (-0.16712), 0.17372, (-0.78548), (-0.17739), 0.66753,
  (-0.14264), 0.16071, 1.043, (-0.1577), 0.10956, (-4.492), (-0.78543), 0.012984,
  (-0.6057), 0.12903, (-0.014416), (-0.73211), (-2.0442), 0.14053, (-0.41862), 0.078705,
  0.024633, 0.4187, (-0.17558), 0.64711, (-0.22006), 0.14121, (-0.068427), (-2.3411),
  1.2899, 0.084875, (-1.1631), (-0.053753), 0.070101, 0.73677, (-0.17755), 0.6978,
  0.21937, (-0.20391), 0.61868, (-0.17804), (-0.46484), 0.18829, (-0.12858), 3.2792,
  (-0.30118), 0.23819, (-0.22285), 0.29954, 0.25064, (-0.13666), 0.29017, (-0.2893),
  0.19156, (-0.68329), (-0.75677), (-0.01328), 0.084454, 1.0889, (-0.26919), 0.19538,
  0.13632, (-0.56917), (-0.40444), 0.14075, 0.16243, (-0.55742), 0.31133, (-0.22756),
  (-0.26868), 0.19565, 0.15486, (-0.34058), 1.1467, 0.090558, (-0.71258), (-0.000704),
  0.41537, 0.027246, (-1.334), (-0.047353), 0.14446, (-0.51518), (-0.049966), (-1.1929),
  0.63881, 0.038141, (-0.21547), 0.49478, (-0.80494), 0.39897, (-0.31655), 0.68877,
  (-0.64266), 0.25551, (-0.45927), 0.31171, 0.46027, (-0.27439), 0.36609, (-0.27206),
  0.023477, (-0.88444), 0.17489, (-0.54565), (-0.96396), 0.023525, (-0.70849), 0.21468,
  0.073601, (-0.68226), (-0.74935), 0.23803, 0.68323, (-0.2138), (-0.12566), 0.67524,
  0.07069, (-0.80666), 0.95434, 0.016548, (-0.28414), 0.4713, 0.38445, (-0.062288),
  5.6e-05, (-1.0173), 0.84921, 0.00574, (-0.92571), (-0.001768), (-0.54372), 0.24932,
  (-0.007372), (-0.93964), 0.72137, 0.010492, 0.19273, (-0.35832), 0.11354, (-1.6304),
  (-0.053421), (-1.6981), (-0.10783), 0.51927, (-0.18054), 0.9512, 0.16785, (-1.1592),
  0.20491, (-0.33118), 0.93468, (-0.002964), 0.0037, (-0.7755), (-0.002204), 0.7459,
  0.72292, (-0.18404), 1.0014, 0.034003, (-0.046356), (-1.2782), 0.014812, 0.6665,
  (-0.94223), (-0.020797), (-0.43542), 0.23386, (-0.17616), 0.85765, 0.57978, 0.028566,
  (-0.022729), (-0.96773), (-0.14215), 0.51688, 0.97274, (-0.1812), (-0.0831), 0.31763,
  (-2.0669), (-0.060174), 0.44132, 0.023209, 0.28607, (-0.29153), (-0.57415), 0.23063,
  0.34479, (-0.2608), 0.56154, 0.061219, (-0.14773), 1.6378, 0.24006, (-0.44865),
  0.43119, (-0.23809), 0.019865, 0.80854, 0.18193, (-0.32878), 0.14974, (-1.418),
  (-0.1976), 0.58508, 0.0005, 0.3905, 1.2647, (-0.15633), 0.65149, 0.010236,
  (-1.0345), (-0.032183), (-0.47874), 0.16291, (-0.20983), 0.54576, 0.51899, (-0.01508),
  (-0.21108), 0.75937, 0.18049, (-0.74049), (-0.14492), 1.536, (-0.28154), 0.20407,
  (-0.44876), 0.053989, 0.041514, 0.29417, 0.39674, (-0.28302), 2.1994, 0.087965,
  (-0.28026), 0.25156, 0.34157, 0.017925, 0.2868, (-0.25136), 0.6383, 0.088598,
  0.079017, (-0.40775), (-0.44644), 0.1722, (-0.9827), (-0.035388), 0.22706, (-0.8055),
  0.83952, (-0.1743), 0.11557, (-1.9667), (-0.037576), (-1.0311), (-1.353), 0.12141,
  (-0.17684), 0.74485, 0.12836, (-0.44444), 0.80153, (-0.17492), 0.16145, (-0.12365),
  0.15412, (-0.33294), (-1.8401), 0.14836, (-0.80839), (-0.027726), (-0.13785), 0.32858,
  (-0.025517), (-0.83387), (-0.7374), 0.17887, (-0.45449), 0.068791, 0.21009, (-0.37809),
  0.40135, (-0.21074), (-0.021649), 0.45421, (-0.49819), 0.075908, 0.17858, (-0.28455),
  0.046625, (-0.55206), 0.1755, (-0.20704), (-0.46393), 0.069304, 0.051735, 0.75551,
  0.14894, (-0.31907), 0.13739, (-1.138), (-0.28829), 0.19089, (-0.30179), 0.16796,
  (-0.98138), (-0.019861), 0.04879, 0.53118, 0.23706, (-0.27925), 0.47255, 0.065171,
  (-0.20765), 0.50948, 0.16421, (-1.4509), (-0.56544), 0.023789, (-3.5603), 0.11801,
  (-0.037016), (-1.0225), (-0.56492), 0.18525, (-0.029902), (-0.82921), (-0.53172), 0.1443,
  (-0.22041), 0.47952, 0.14223, (-0.61194), (-0.34561), 0.11739, 0.95984, 0.064935,
  1.7386, (-0.14253), 1.3873, 0.066188, 0.053677, (-0.54048), (-0.09362), 0.39131,
  0.037224, (-0.54252), 0.95308, 0.037697, (-0.13488), 2.2897, 0.22824, (-0.59984),
  (-0.22005), 0.37222, 1.2856, 0.047237, (-3.9551), (-0.072904), 0.37675, (-0.046484),
  (-0.024457), (-0.80035), 0.17019, (-0.63069), (-0.93667), (-0.041214), 0.13081, (-1.5802),
  (-1.1442), (-0.049174), 0.49606, (-0.034459), (-0.30998), 0.17055, (-0.37905), 0.16079,
  (-0.18655), 0.56368, (-0.5899), 0.1175, (-0.15425), 0.92911, 0.32191, (-0.16393),
  (-0.15877), 1.0186, 0.75587, 0.031795, (-0.88451), (-0.009504), 0.23838, (-0.11606),
  (-1.8738), (-0.068503), 0.1292, (-0.67512), (-0.024829), (-0.74397), 0.4682, (-0.024165),
  0.40084, (-0.21256), (-1.565), 0.14376, (-1.9221), (-0.06956), 0.13397, (-2.2639),
  1.0215, (-0.15232), (-0.097409), 0.41662, 0.11272, (-0.41654), 0.6054, 0.062468,
  (-0.18919), 0.46465, 0.11565, (-1.3213), (-0.28062), 0.19313, 0.72429, 0.075448,
  (-0.19482), 0.46033, 0.15564, (-0.49914), (-0.058573), (-1.5418), (-1.61), 0.11451,
  (-0.061407), (-1.4673), 0.16288, (-0.11026), (-0.17933), 0.57218, 4.6512, 0.094534,
  (-0.16986), 0.87029, 0.91043, 0.056827, 0.22067, (-0.27769), (-0.89869), 0.29436,
  (-0.37659), 0.60891, (-0.38129), 0.39217, (-0.18182), 0.58927, (-0.224), 0.6378,
  0.70812, (-0.14666), 0.4768, (-0.29233), (-0.1851), 0.52627, 0.039245, (-0.89198),
  (-0.23358), 0.44146, (-0.46064), 0.1769, 0.33493, (-0.29893), (-0.16409), 1.5994,
  0.22602, (-0.53186), 0.15221, (-0.41915), (-1.4874), 0.12954, (-0.19146), 0.98185,
  0.1346, (-0.56316), (-1.0828), (-0.011504), (-0.59224), 0.13395, (-0.49186), 0.094446,
  0.5971, (-0.039553), (-1.1818), (-0.028254), (-0.61028), 0.22619, (-1.1436), (-0.029002),
  (-1.647), 0.1281, (-0.31149), 0.2574, (-0.69207), 0.15271, (-0.71868), 0.002688,
  0.22371, (-0.55382), 1.032, (-0.17496), 0.44962, 0.039349, (-0.85476), (-0.012464),
  0.57846, (-0.017468), (-0.37749), 0.13962, (-0.26187), 0.23712, (-0.028626), (-1.2945),
  0.20531, (-0.18747), 0.67027, (-0.19594), 0.17405, (-0.32746), (-0.83954), (-0.006376),
  (-0.034195), 0.58998, 0.42143, (-0.2351), 0.069304, 0.73226, (-0.15688), 1.0907,
  (-0.70934), 0.16829, (-0.16193), 1.0073, 0.39008, (-0.053777), 0.01718, (-0.93942),
  0.050463, 0.54466, (-0.26981), 0.40365, 0.844, 0.032883, 0.15309, (-0.3496),
  (-0.92711), 0.16801, 0.51614, (-0.20236), 0.13951, (-0.49301), (-0.90102), (-0.016116),
  0.19858, (-0.16731), 0.094005, (-0.41571), (-0.060022), 0.70994, 0.24392, (-0.30552),
  0.6123, 0.024253, 0.90765, (-0.16722), (-0.31385), 0.20135, (-0.66588), 0.007456,
  0.059534, 0.87805, 0.80068, (-0.17252), 0.18774, (-0.60851), 0.58644, (-0.19428),
  (-0.25588), 0.16326, (-0.014228), (-0.76738), 0.20495, (-0.11404), (-1.0741), (-0.038941),
  (-0.57974), 0.18585, (-0.6615), 0.005312, (-0.48305), 0.12326, 0.57453, (-0.1942),
  (-0.054642), 0.24502, 0.12181, (-0.38797), 0.10966, (-30.0), (-1.7353), (-0.06381),
  0.13523, (-0.70301), (-0.46984), 0.060342, 0.69808, 0.001372, 1.687, (-0.14315),
  0.79498, 0.000772, (-1.0132), (-0.019389), 0.14412, (-0.42139), 0.50683, (-0.20479),
  (-0.15811), 0.17807, (-0.54367), 0.031235, (-0.17377), 0.30442, 0.25104, (-0.26224),
  0.93227, 0.07266, (-0.033935), (-0.85708), 0.34969, (-0.048518), 0.066573, (-0.44974),
  0.14276, (-0.46726), (-1.0286), (-0.045288), (-0.19652), 0.28661, (-0.77532), (-0.008328),
  0.13232, (-3.5267), (-0.15547), 1.4674, 0.15233, (-1.3021), (-0.71326), (-0.008704),
  1.1128, 0.08322, 0.93165, (-0.17104), (-0.19734), 0.25359, 0.41815, (-0.24586),
  (-0.51743), 0.20174, (-0.043071), (-1.0637), 0.053781, 0.49707, (-0.238), 0.41651,
  (-0.88575), 0.13366, (-0.2067), 0.58309, 0.13282, (-3.1449), (-0.17325), 0.69191,
  0.054822, 0.3024, 0.15821, (-0.31973), 0.71275, 0.058136, (-0.15754), 0.92144,
  (-0.34548), 0.20221, (-0.5565), 0.020389, (-3.61), 0.13164, 0.51909, (-0.19284),
  (-0.0875), 0.15812, 0.027406, (-0.55124), 0.23458, (-0.043235), (-0.039681), (-0.94373),
  0.45704, (-0.004052), (-0.76248), (-0.019857), (-3.7413), 0.11251, (-0.63782), 0.011224,
  0.19374, (-0.082042), (-0.16192), 1.1335, 0.021105, 0.76264, (-1.6975), (-0.059762),
  1.185, 0.090967, (-0.40941), 0.083821, 0.1553, (-1.0995), 0.48947, (-0.20041),
  (-0.24581), 0.14366, (-0.048169), (-1.2311), 0.43373, 0.01378, 0.1895, (-0.32294),
  (-0.43979), 0.2273, (-0.20548), 0.50933, 0.31157, 0.070681, (-0.30935), 0.15628,
  0.13822, (-0.17617), (-0.5107), 0.058441, 0.47757, (-0.071446), 0.45239, (-0.19861),
  0.12955, (-0.86266), (-0.04157), (-1.1355), (-0.34738), 0.15779, 0.004864, (-0.61655),
  0.081373, 0.69841, 1.1616, (-0.14977), (-0.32036), 0.17365, (-0.18158), 0.61957,
  0.000796, 0.42441, (-0.14697), 1.2526, (-0.39782), 0.14191, (-0.18194), 0.59762,
  0.14642, (-0.78837), (-0.062408), (-1.4227), 0.34033, 0.03067, 0.31085, (-0.22596),
  (-0.038937), 0.31702, (-0.17578), 0.65057, (-1.0093), 0.1107, (-0.53806), 0.019905,
  0.48143, 0.033591, 0.26352, (-0.25738), 0.036508, 0.90656, (-0.60049), 0.009588,
  0.15506, (-0.95733), (-0.14526), 1.3677, 0.012916, 0.21641, (-0.01636), (-0.88356),
  0.3583, 0.065131, 1.1961, (-0.14972), (-0.61834), 0.12786, (-1.8276), (-0.064863),
  (-30.0), 0.11323, (-0.23934), 0.36333, (-0.03514), 0.27708, (-0.15524), 1.0803,
  (-0.061203), 0.20508, (-0.64778), 0.023917, 1.0892, 0.058389, (-0.25806), 0.20835,
  0.13886, (-1.5663), (-0.20728), 0.52431, 0.14797, (-1.3095), 0.027906, (-0.50865),
  1.2618, 0.063802, (-0.1285), 3.0776, (-0.68559), 0.38984, (-0.47724), 0.45027,
  (-0.47011), 0.42702, 0.25614, (-0.66556), (-0.48083), 0.28014, (-0.23948), 0.44192,
  0.76087, (-0.25059), (-0.34975), 0.3438, (-0.79086), 0.034788, 0.47108, (-0.060006),
  0.67116, (-0.24258), 0.24717, (-0.48302), (-0.21504), 0.72056, 0.27931, (-0.3434),
  0.055862, (-0.82144), (-0.99621), 0.18875, (-1.1946), (-0.029198), 0.14988, (-0.54138),
  (-1.421), (-0.042314), (-0.28243), 0.15582, 0.47317, (-0.21937), (-0.059714), 0.60626,
  (-0.85647), (-0.013784), 0.16655, (-0.27714), (-1.1728), (-0.040185), 0.26514, (-0.056343),
  0.036556, (-0.55075), (-0.042614), 0.48195, 0.28699, (-0.32923), (-1.4065), 0.12836,
  (-0.21435), 0.53982, 0.33718, 0.045212, (-0.25122), 0.4175, 0.040085, 0.6878,
  0.53027, (-0.22902), 0.25161, (-0.21515), 0.007232, (-0.72519), (-0.49958), 0.18395,
  0.085212, (-0.46365), (-0.52259), 0.23893, (-0.6325), 0.032551, 1.2856, 0.076545,
  0.83208, (-0.18591), 0.11299, (-30.0), (-1.3486), (-0.047097), (-1.3534), 0.15669,
  0.403, (-0.25149), (-0.26287), 0.18583, 0.58692, (-0.19428), (-0.16689), 0.23007,
  0.01252, (-0.66724), (-0.01706), 0.64579, (-0.24179), 0.34879, (-0.53599), 0.20996,
  0.75093, (-0.17593), (-0.16188), 0.30658, (-0.17319), 1.0016, 0.23418, (-0.065347),
  0.25019, (-0.30591), 0.13122, (-0.93765), (-0.83978), (-0.023473), 2.3587, 0.082971,
  0.18814, (-0.31222), 0.14825, (-0.84682), (-0.043731), (-1.3366), 0.1766, (-0.60904),
  (-0.98701), (-0.037785), (-0.1612), 0.32676, (-0.23842), 0.29319, 0.14425, (-1.501),
  (-1.0395), (-0.045376), 0.19634, (-0.14472), (-0.90635), (-0.038049), (-0.029474), 0.60058,
  (-0.99804), (-0.038653), 0.73361, 0.05744, 0.27893, (-0.26516), 0.004776, 0.35926,
  (-0.20084), 0.51203, 0.64722, (-0.001376), (-0.18364), 0.61343, (-0.29188), 0.18195,
  (-0.066452), (-1.929), (-0.012732), 0.61561, (-0.20857), 0.44364, (-0.35713), 0.24252,
  1.0847, (-0.15054), 0.21303, (-0.18308), 0.51737, (-0.18833), (-0.4403), 0.22746,
  0.03506, (-0.51665), 0.013228, 0.34915, 0.34119, (-0.2151), 0.32937, (-0.28524),
  (-0.25334), 0.26296, 0.14049, (-0.49887), (-0.015396), (-0.76958), 0.1907, (-0.32393),
  0.34925, (-0.22359), (-0.038329), 0.51177, (-0.42888), 0.049174, 0.66625, 0.007808,
  (-0.49135), 0.069556, 0.12997, (-1.895), (-0.057212), (-1.4281), (-0.57589), 0.18063,
  0.97308, (-0.16513), 0.17933, (-0.27949), (-0.81072), (-0.016596), 0.27909, (-0.007452),
  (-0.13509), 2.5412, (-0.068419), 0.28734, (-0.18136), 0.65413, (-0.1569), 0.26964,
  0.29176, (-0.25274), 0.44388, 0.055038, (-0.19346), 0.46657, (-0.008236), 0.25701,
  (-0.42431), 0.071174, (-0.85394), 0.16916, 0.83785, (-0.17597), 0.09955, 2.3873,
  (-0.18725), 0.62384, 0.25009, (-0.065119), (-0.35379), 0.10715, 0.16387, (-0.91718),
  (-0.14813), 1.4895, (-0.21327), 0.19676, (-0.71319), 0.001824, 0.033099, 1.0442,
  (-0.27308), 0.2723, 0.36226, 0.056795, (-0.048041), (-0.96724), 0.13053, (-0.35077),
  (-1.0767), (-0.051223), 0.026238, 0.28071, (-0.26111), 0.21011, (-1.7748), 0.11483,
  0.29901, (-0.22502), 0.19564, (-0.099763), (-0.43022), 0.081261, (-0.50987), 0.16346,
  0.77978, (-0.17476), (-0.63048), 0.12728, (-0.046448), (-1.1129), 0.11835, (-4.8235),
  (-0.017468), (-0.63693), 0.086133, 2.4559, 0.040229, (-0.50858), (-1.9007), 0.11019,
  (-0.062112), (-1.4165), 0.88849, 0.04237, (-0.22094), 0.33575, 0.57805, 0.045348,
  (-0.54176), 0.00324, (-0.081549), 0.35838, (-0.2028), 0.43768, 0.4147, (-0.045568),
  (-0.02901), (-0.91822), (-0.11772), 0.2, 0.33005, (-0.23055), (-0.021545), 0.26878,
  (-0.44101), 0.049158, 0.11782, (-2.8293), 0.91777, (-0.15827), 0.11289, (-1.9937),
  (-0.14357), 1.3085, 0.20048, (-0.044187), 0.32619, (-0.2055), 0.15825, (-0.95535),
  (-0.074651), (-2.1161), 0.11642, (-1.6114), (-0.16563), 0.70025, 0.22628, (-0.40115),
  (-0.1939), 0.4442, 0.11637, (-1.5772), (-0.8968), (-0.04201), 0.35603, (-0.013124),
  (-0.4604), 0.026802, 0.23789, (-0.065519), (-0.02849), (-0.84235), (-0.50939), 0.16058,
  (-0.54155), 0.004732, (-0.88786), 0.13622, 0.80615, (-0.1616), 0.012968, 0.5508,
  (-0.045728), (-1.0766), 0.071262, 1.1695, (-0.19736), 0.38207, (-5.4372), 0.11152,
  0.44793, (-0.18658), (-0.014872), 0.18414, (-0.15117), 0.94991, 0.46474, 0.038405,
  (-1.65), (-0.063237), (-0.038349), 0.41914, 0.34462, (-0.21188), 0.12398, (-2.1255),
  (-0.062024), (-1.4876), 0.017088, 0.32077, (-0.27414), 0.18976, (-0.1792), 0.27967,
  (-0.32298), 0.26942, 0.12644, (-0.60713), (-0.49682), 0.022377, 0.043607, 0.48538,
  (-0.042951), (-0.93024), (-0.002968), 0.34296, (-1.53), (-0.061015), 0.037596, 0.64172,
  0.099089, (-0.39688), 0.62419, (-0.45875), (-0.93073), 0.21564, (-0.40532), 0.42257,
  0.095288, (-0.63298), 0.37244, (-0.30332), (-0.23357), 0.40331, 0.042887, (-0.77797),
  (-0.49628), 0.16335, 0.032747, (-0.80048), (-0.50003), 0.25481, 0.038913, (-0.70725),
  (-0.066268), 0.73869, 0.48696, (-0.24486), 0.13459, (-0.13232), (-0.44173), 0.14006,
  0.031218, 0.89818, 0.012008, (-0.86066), 0.014056, 0.85333, 0.29023, (-0.29479),
  (-0.4044), 0.194, 0.32945, (-0.25713), (-0.53353), 0.21635, (-1.4425), (-0.044683),
  (-0.79018), 0.19084, (-0.26931), 0.31488, (-0.54464), 0.16575, 0.022105, (-0.62343),
  (-0.49885), 0.19237, (-0.79131), (-0.014144), 0.79841, (-0.033799), (-0.33163), 0.20726,
  (-0.27256), 0.18402, (-0.53096), 0.052608, (-0.56485), 0.19269, (-0.17412), 0.95383,
  (-0.091949), 0.24836, (-0.058497), (-1.6404), 0.23448, (-0.092734), 0.17881, (-0.35844),
  (-0.42903), 0.20245, 0.58016, (-0.18806), 0.032847, 0.81981, 0.069176, (-0.45866),
  (-1.2553), 0.14333, 0.53152, (-0.20596), 1.1659, 0.053897, 0.39308, (-0.22185),
  (-0.73744), 0.14268, (-0.14277), 1.7895, 0.11977, (-1.8886), (-1.4148), (-0.056523),
  0.44171, (-0.10201), (-1.3918), (-0.048269), 0.51318, (-0.093697), (-0.057484), (-1.4283),
  (-0.080892), 0.32333, (-0.86449), (-0.033147), 0.52162, (-0.016168), (-0.16154), 1.0915,
  (-0.17091), 0.31237, (-0.006704), (-0.6881), 0.63293, (-0.004236), (-0.33637), 0.12791,
  (-0.034704), 0.39142, 0.64765, (-0.20098), 0.054297, 0.907, 0.65523, (-0.19754),
  0.19385, (-0.51707), (-0.93097), (-0.031547), (-0.68327), 0.12709, 0.015524, (-0.63348),
  1.0061, 0.062813, (-0.23383), 0.30983, (-0.72505), 0.17148, (-0.22072), 0.35266,
  0.16662, (-0.74319), (-0.23983), 0.41436, 0.51045, 0.002232, 0.90475, (-0.16615),
  0.14025, (-0.52179), (-0.66178), 0.003764, 0.80186, 0.059385, (-0.33546), 0.14579,
  (-0.55509), 0.13267, (-0.061632), (-1.3679), 0.34185, (-0.007416), 0.27746, (-0.31034),
  1.172, 0.083681, 0.81695, (-0.17838), (-0.18627), 0.1434, 0.32659, (-0.23541),
  0.19761, (-0.021701), (-0.93415), (-0.021705), 0.025573, 0.46413, (-0.21229), 0.40079,
  0.74203, 0.029002, (-0.19244), 0.43631, 0.69736, 0.069308, 0.39147, (-0.20922),
  (-0.072556), 0.36088, 0.95425, (-0.15403), (-0.051135), 0.2775, 0.075628, (-0.36456),
  0.051844, 0.41563, 0.7197, (-0.17132), 0.14355, (-0.65403), 0.040089, (-0.45743),
  0.53855, 0.071663, (-0.045992), (-1.0047), 0.034335, 0.42432, (-0.25851), 0.26263,
  0.15692, (-1.0429), (-0.73178), (-0.020277), 0.08336, 1.5661, (-0.35318), 0.14698,
  0.28326, (-0.003464), (-0.84017), (-0.036252), 0.14999, (-0.87367), (-0.18788), 0.59484,
  0.44316, (-0.056571), (-0.056495), (-1.3617), (-0.31162), 0.25448, 1.6424, (-0.14429),
  (-0.7782), 0.17173, (-0.23191), 0.28528, (-0.35965), 0.20413, 0.78051, (-0.15613),
  1.1814, 0.078112, (-0.47104), 0.079173, 0.22263, (-0.371), (-0.038649), (-0.92275),
  0.419, 0.080411, (-0.16757), 0.71842, 0.1572, (-0.87681), (-0.00416), (-0.59328),
  (-0.030154), 0.48345, (-0.22667), 0.33662, (-0.060374), 0.31458, (-0.29873), 0.17787,
  0.2189, (-0.29567), 1.215, (-0.14355), 0.012452, 0.5549, (-1.4934), (-0.065227),
  (-0.38526), 0.19761, (-0.21281), 0.29447, 0.000972, 0.66814, (-0.62468), (-0.00166),
  (-0.42334), 0.12085, 0.025882, (-0.50732), 0.13185, (-0.2174), 1.1776, (-0.15115),
  0.033991, 0.39923, (-0.31807), 0.11682, 0.84399, 0.083889, 0.36888, (-0.18913),
  (-0.52162), 0.15773, (-0.059922), (-1.0675), 0.78958, 0.0521, (-1.1704), (-0.059357),
  0.041718, 0.66353, (-0.35863), 0.060458, 0.20979, (-0.24806), (-0.18796), 0.39547,
  0.25664, (-0.094919), 0.033139, (-0.46075), (-0.98882), 0.14637, (-0.13287), 1.5797,
  0.33877, 0.074971, (-0.18328), 0.46981, (-0.98323), 0.11808, (-0.033051), (-0.83611),
  1.1671, 0.080692, 0.6387, (-0.17626), (-0.23302), 0.12517, (-0.22038), 0.27197,
  0.16127, (-0.43329), (-0.16992), 0.58885, 0.25843, (-0.035912), (-0.76764), (-0.020473),
  (-0.2718), 0.14326, 0.076409, (-0.41445), (-0.038629), 0.20754, (-0.17778), 0.63461,
  0.18972, (-0.51236), 0.70615, (-0.17803), 0.06815, 0.68733, 0.7517, (-0.15765),
  0.19412, (-0.24562), (-0.046881), (-0.88198), (-0.44532), 0.1768, 0.65123, (-0.1671),
  (-0.058301), 0.34483, (-0.15582), 0.86433, (-0.61029), 0.11796, (-0.049602), (-0.8999),
  0.11297, (-1.0834), (-0.7988), (-0.034079), (-0.19124), 0.21535, (-0.13422), 1.6807,
  0.48601, 0.003616);
 HaarRc: Array[0..34955] Of Byte = (
  6, 4, 12, 9, 6, 7, 12, 3, 0, 0, 0, 0, 6, 4, 12, 7, 10, 4, 4, 7, 0, 0, 0, 0,
  3, 9, 18, 9, 3, 12, 18, 3, 0, 0, 0, 0, 8, 18, 9, 6, 8, 20, 9, 2, 0, 0, 0, 0,
  3, 5, 4, 19, 5, 5, 2, 19, 0, 0, 0, 0, 6, 5, 12, 16, 6, 13, 12, 8, 0, 0, 0, 0,
  5, 8, 12, 6, 5, 11, 12, 3, 0, 0, 0, 0, 11, 14, 4, 10, 11, 19, 4, 5, 0, 0, 0, 0,
  4, 0, 7, 6, 4, 3, 7, 3, 0, 0, 0, 0, 6, 6, 12, 6, 6, 8, 12, 2, 0, 0, 0, 0,
  6, 4, 12, 7, 10, 4, 4, 7, 0, 0, 0, 0, 1, 8, 19, 12, 1, 12, 19, 4, 0, 0, 0, 0,
  0, 2, 24, 3, 8, 2, 8, 3, 0, 0, 0, 0, 9, 9, 6, 15, 9, 14, 6, 5, 0, 0, 0, 0,
  5, 6, 14, 10, 5, 11, 14, 5, 0, 0, 0, 0, 5, 0, 14, 9, 5, 3, 14, 3, 0, 0, 0, 0,
  13, 11, 9, 6, 16, 11, 3, 6, 0, 0, 0, 0, 7, 5, 6, 10, 9, 5, 2, 10, 0, 0, 0, 0,
  10, 8, 6, 10, 12, 8, 2, 10, 0, 0, 0, 0, 2, 5, 4, 9, 4, 5, 2, 9, 0, 0, 0, 0,
  18, 0, 6, 11, 20, 0, 2, 11, 0, 0, 0, 0, 0, 6, 24, 13, 8, 6, 8, 13, 0, 0, 0, 0,
  9, 6, 6, 9, 11, 6, 2, 9, 0, 0, 0, 0, 7, 18, 10, 6, 7, 20, 10, 2, 0, 0, 0, 0,
  5, 7, 14, 12, 5, 13, 14, 6, 0, 0, 0, 0, 0, 3, 24, 3, 8, 3, 8, 3, 0, 0, 0, 0,
  5, 8, 15, 6, 5, 11, 15, 3, 0, 0, 0, 0, 9, 6, 5, 14, 9, 13, 5, 7, 0, 0, 0, 0,
  9, 5, 6, 10, 11, 5, 2, 10, 0, 0, 0, 0, 6, 6, 3, 12, 6, 12, 3, 6, 0, 0, 0, 0,
  3, 21, 18, 3, 9, 21, 6, 3, 0, 0, 0, 0, 5, 6, 13, 6, 5, 8, 13, 2, 0, 0, 0, 0,
  18, 1, 6, 15, 18, 1, 3, 15, 0, 0, 0, 0, 1, 1, 6, 15, 4, 1, 3, 15, 0, 0, 0, 0,
  0, 8, 24, 15, 8, 8, 8, 15, 0, 0, 0, 0, 5, 6, 14, 12, 5, 6, 7, 6, 12, 12, 7, 6,
  2, 12, 21, 12, 2, 16, 21, 4, 0, 0, 0, 0, 8, 1, 4, 10, 10, 1, 2, 10, 0, 0, 0, 0,
  2, 13, 20, 10, 2, 13, 10, 10, 0, 0, 0, 0, 0, 1, 6, 13, 2, 1, 2, 13, 0, 0, 0, 0,
  20, 2, 4, 13, 20, 2, 2, 13, 0, 0, 0, 0, 0, 5, 22, 19, 11, 5, 11, 19, 0, 0, 0, 0,
  18, 4, 6, 9, 20, 4, 2, 9, 0, 0, 0, 0, 0, 3, 6, 11, 2, 3, 2, 11, 0, 0, 0, 0,
  12, 1, 4, 9, 12, 1, 2, 9, 0, 0, 0, 0, 0, 6, 19, 3, 0, 7, 19, 1, 0, 0, 0, 0,
  12, 1, 4, 9, 12, 1, 2, 9, 0, 0, 0, 0, 8, 1, 4, 9, 10, 1, 2, 9, 0, 0, 0, 0,
  5, 5, 14, 14, 12, 5, 7, 7, 5, 12, 7, 7, 1, 10, 18, 2, 1, 11, 18, 1, 0, 0, 0, 0,
  17, 13, 4, 11, 17, 13, 2, 11, 0, 0, 0, 0, 0, 4, 6, 9, 0, 7, 6, 3, 0, 0, 0, 0,
  6, 4, 12, 9, 6, 7, 12, 3, 0, 0, 0, 0, 6, 5, 12, 6, 10, 5, 4, 6, 0, 0, 0, 0,
  0, 1, 24, 5, 8, 1, 8, 5, 0, 0, 0, 0, 4, 10, 18, 6, 4, 12, 18, 2, 0, 0, 0, 0,
  2, 17, 12, 6, 2, 17, 6, 3, 8, 20, 6, 3, 19, 3, 4, 13, 19, 3, 2, 13, 0, 0, 0, 0,
  1, 3, 4, 13, 3, 3, 2, 13, 0, 0, 0, 0, 0, 1, 24, 23, 8, 1, 8, 23, 0, 0, 0, 0,
  1, 7, 8, 12, 1, 11, 8, 4, 0, 0, 0, 0, 14, 7, 3, 14, 14, 14, 3, 7, 0, 0, 0, 0,
  3, 12, 16, 6, 3, 12, 8, 3, 11, 15, 8, 3, 6, 6, 12, 6, 6, 8, 12, 2, 0, 0, 0, 0,
  8, 7, 6, 12, 8, 13, 6, 6, 0, 0, 0, 0, 15, 15, 9, 6, 15, 17, 9, 2, 0, 0, 0, 0,
  1, 17, 18, 3, 1, 18, 18, 1, 0, 0, 0, 0, 4, 4, 16, 12, 4, 10, 16, 6, 0, 0, 0, 0,
  0, 1, 4, 20, 2, 1, 2, 20, 0, 0, 0, 0, 3, 0, 18, 2, 3, 1, 18, 1, 0, 0, 0, 0,
  1, 5, 20, 14, 1, 5, 10, 7, 11, 12, 10, 7, 5, 8, 14, 12, 5, 12, 14, 4, 0, 0, 0, 0,
  3, 14, 7, 9, 3, 17, 7, 3, 0, 0, 0, 0, 14, 15, 9, 6, 14, 17, 9, 2, 0, 0, 0, 0,
  1, 15, 9, 6, 1, 17, 9, 2, 0, 0, 0, 0, 11, 6, 8, 10, 15, 6, 4, 5, 11, 11, 4, 5,
  5, 5, 14, 14, 5, 5, 7, 7, 12, 12, 7, 7, 6, 0, 12, 5, 10, 0, 4, 5, 0, 0, 0, 0,
  9, 0, 6, 9, 9, 3, 6, 3, 0, 0, 0, 0, 9, 6, 6, 9, 11, 6, 2, 9, 0, 0, 0, 0,
  7, 0, 6, 9, 9, 0, 2, 9, 0, 0, 0, 0, 10, 6, 6, 9, 12, 6, 2, 9, 0, 0, 0, 0,
  8, 6, 6, 9, 10, 6, 2, 9, 0, 0, 0, 0, 3, 8, 18, 4, 9, 8, 6, 4, 0, 0, 0, 0,
  6, 0, 12, 9, 6, 3, 12, 3, 0, 0, 0, 0, 0, 0, 24, 6, 8, 0, 8, 6, 0, 0, 0, 0,
  4, 7, 16, 12, 4, 11, 16, 4, 0, 0, 0, 0, 11, 6, 6, 6, 11, 6, 3, 6, 0, 0, 0, 0,
  0, 20, 24, 3, 8, 20, 8, 3, 0, 0, 0, 0, 11, 6, 4, 9, 11, 6, 2, 9, 0, 0, 0, 0,
  4, 13, 15, 4, 9, 13, 5, 4, 0, 0, 0, 0, 11, 6, 4, 9, 11, 6, 2, 9, 0, 0, 0, 0,
  9, 6, 4, 9, 11, 6, 2, 9, 0, 0, 0, 0, 9, 12, 6, 12, 9, 18, 6, 6, 0, 0, 0, 0,
  1, 22, 18, 2, 1, 23, 18, 1, 0, 0, 0, 0, 10, 7, 4, 10, 10, 12, 4, 5, 0, 0, 0, 0,
  6, 7, 8, 10, 6, 12, 8, 5, 0, 0, 0, 0, 7, 6, 10, 6, 7, 8, 10, 2, 0, 0, 0, 0,
  0, 14, 10, 4, 0, 16, 10, 2, 0, 0, 0, 0, 6, 18, 18, 2, 6, 19, 18, 1, 0, 0, 0, 0,
  1, 1, 22, 3, 1, 2, 22, 1, 0, 0, 0, 0, 6, 16, 18, 3, 6, 17, 18, 1, 0, 0, 0, 0,
  2, 4, 6, 15, 5, 4, 3, 15, 0, 0, 0, 0, 20, 4, 4, 10, 20, 4, 2, 10, 0, 0, 0, 0,
  0, 4, 4, 10, 2, 4, 2, 10, 0, 0, 0, 0, 2, 16, 20, 6, 12, 16, 10, 3, 2, 19, 10, 3,
  0, 12, 8, 9, 4, 12, 4, 9, 0, 0, 0, 0, 12, 0, 6, 9, 14, 0, 2, 9, 0, 0, 0, 0,
  5, 10, 6, 6, 8, 10, 3, 6, 0, 0, 0, 0, 11, 8, 12, 6, 17, 8, 6, 3, 11, 11, 6, 3,
  0, 8, 12, 6, 0, 8, 6, 3, 6, 11, 6, 3, 12, 0, 6, 9, 14, 0, 2, 9, 0, 0, 0, 0,
  6, 0, 6, 9, 8, 0, 2, 9, 0, 0, 0, 0, 8, 14, 9, 6, 8, 16, 9, 2, 0, 0, 0, 0,
  0, 16, 9, 6, 0, 18, 9, 2, 0, 0, 0, 0, 10, 8, 6, 10, 12, 8, 2, 10, 0, 0, 0, 0,
  3, 19, 12, 3, 9, 19, 6, 3, 0, 0, 0, 0, 2, 10, 20, 2, 2, 11, 20, 1, 0, 0, 0, 0,
  2, 9, 18, 12, 2, 9, 9, 6, 11, 15, 9, 6, 3, 0, 18, 24, 3, 0, 9, 24, 0, 0, 0, 0,
  5, 6, 14, 10, 5, 6, 7, 5, 12, 11, 7, 5, 9, 5, 10, 12, 14, 5, 5, 6, 9, 11, 5, 6,
  4, 5, 12, 12, 4, 5, 6, 6, 10, 11, 6, 6, 4, 14, 18, 3, 4, 15, 18, 1, 0, 0, 0, 0,
  6, 13, 8, 8, 6, 17, 8, 4, 0, 0, 0, 0, 3, 16, 18, 6, 3, 19, 18, 3, 0, 0, 0, 0,
  0, 0, 6, 6, 3, 0, 3, 6, 0, 0, 0, 0, 6, 6, 12, 18, 10, 6, 4, 18, 0, 0, 0, 0,
  6, 1, 4, 14, 8, 1, 2, 14, 0, 0, 0, 0, 3, 2, 19, 2, 3, 3, 19, 1, 0, 0, 0, 0,
  1, 8, 22, 13, 12, 8, 11, 13, 0, 0, 0, 0, 8, 9, 11, 4, 8, 11, 11, 2, 0, 0, 0, 0,
  0, 12, 15, 10, 5, 12, 5, 10, 0, 0, 0, 0, 12, 16, 12, 6, 16, 16, 4, 6, 0, 0, 0, 0,
  0, 16, 12, 6, 4, 16, 4, 6, 0, 0, 0, 0, 19, 1, 5, 12, 19, 5, 5, 4, 0, 0, 0, 0,
  0, 2, 24, 4, 8, 2, 8, 4, 0, 0, 0, 0, 6, 8, 12, 4, 6, 10, 12, 2, 0, 0, 0, 0,
  7, 5, 9, 6, 10, 5, 3, 6, 0, 0, 0, 0, 9, 17, 6, 6, 9, 20, 6, 3, 0, 0, 0, 0,
  0, 7, 22, 15, 0, 12, 22, 5, 0, 0, 0, 0, 4, 1, 17, 9, 4, 4, 17, 3, 0, 0, 0, 0,
  7, 5, 6, 10, 9, 5, 2, 10, 0, 0, 0, 0, 18, 1, 6, 8, 18, 1, 3, 8, 0, 0, 0, 0,
  0, 1, 6, 7, 3, 1, 3, 7, 0, 0, 0, 0, 18, 0, 6, 22, 18, 0, 3, 22, 0, 0, 0, 0,
  0, 0, 6, 22, 3, 0, 3, 22, 0, 0, 0, 0, 16, 7, 8, 16, 16, 7, 4, 16, 0, 0, 0, 0,
  2, 10, 19, 6, 2, 12, 19, 2, 0, 0, 0, 0, 9, 9, 6, 12, 9, 13, 6, 4, 0, 0, 0, 0,
  2, 15, 17, 6, 2, 17, 17, 2, 0, 0, 0, 0, 14, 7, 3, 14, 14, 14, 3, 7, 0, 0, 0, 0,
  5, 6, 8, 10, 5, 6, 4, 5, 9, 11, 4, 5, 15, 8, 9, 11, 18, 8, 3, 11, 0, 0, 0, 0,
  0, 8, 9, 11, 3, 8, 3, 11, 0, 0, 0, 0, 8, 6, 10, 18, 8, 15, 10, 9, 0, 0, 0, 0,
  7, 7, 3, 14, 7, 14, 3, 7, 0, 0, 0, 0, 0, 14, 24, 8, 8, 14, 8, 8, 0, 0, 0, 0,
  1, 10, 18, 14, 10, 10, 9, 14, 0, 0, 0, 0, 14, 12, 6, 6, 14, 15, 6, 3, 0, 0, 0, 0,
  7, 0, 10, 16, 7, 0, 5, 8, 12, 8, 5, 8, 10, 0, 9, 6, 13, 0, 3, 6, 0, 0, 0, 0,
  4, 3, 16, 4, 12, 3, 8, 4, 0, 0, 0, 0, 10, 0, 9, 6, 13, 0, 3, 6, 0, 0, 0, 0,
  1, 1, 20, 4, 1, 1, 10, 2, 11, 3, 10, 2, 10, 0, 9, 6, 13, 0, 3, 6, 0, 0, 0, 0,
  5, 0, 9, 6, 8, 0, 3, 6, 0, 0, 0, 0, 8, 18, 10, 6, 8, 20, 10, 2, 0, 0, 0, 0,
  6, 3, 6, 9, 8, 3, 2, 9, 0, 0, 0, 0, 7, 3, 12, 6, 7, 5, 12, 2, 0, 0, 0, 0,
  0, 10, 18, 3, 0, 11, 18, 1, 0, 0, 0, 0, 1, 10, 22, 3, 1, 11, 22, 1, 0, 0, 0, 0,
  5, 11, 8, 8, 9, 11, 4, 8, 0, 0, 0, 0, 12, 11, 6, 6, 12, 11, 3, 6, 0, 0, 0, 0,
  6, 11, 6, 6, 9, 11, 3, 6, 0, 0, 0, 0, 7, 10, 11, 6, 7, 12, 11, 2, 0, 0, 0, 0,
  0, 13, 24, 4, 0, 13, 12, 2, 12, 15, 12, 2, 2, 4, 22, 12, 13, 4, 11, 6, 2, 10, 11, 6,
  2, 0, 20, 17, 12, 0, 10, 17, 0, 0, 0, 0, 14, 0, 2, 24, 14, 0, 1, 24, 0, 0, 0, 0,
  8, 0, 2, 24, 9, 0, 1, 24, 0, 0, 0, 0, 14, 1, 2, 22, 14, 1, 1, 22, 0, 0, 0, 0,
  8, 1, 2, 22, 9, 1, 1, 22, 0, 0, 0, 0, 17, 6, 3, 18, 18, 6, 1, 18, 0, 0, 0, 0,
  6, 14, 9, 6, 6, 16, 9, 2, 0, 0, 0, 0, 13, 14, 9, 4, 13, 16, 9, 2, 0, 0, 0, 0,
  3, 18, 18, 3, 3, 19, 18, 1, 0, 0, 0, 0, 9, 4, 8, 18, 13, 4, 4, 9, 9, 13, 4, 9,
  0, 17, 18, 3, 0, 18, 18, 1, 0, 0, 0, 0, 0, 2, 12, 4, 6, 2, 6, 4, 0, 0, 0, 0,
  6, 8, 14, 6, 6, 11, 14, 3, 0, 0, 0, 0, 7, 5, 6, 6, 10, 5, 3, 6, 0, 0, 0, 0,
  10, 5, 6, 16, 10, 13, 6, 8, 0, 0, 0, 0, 1, 4, 9, 16, 4, 4, 3, 16, 0, 0, 0, 0,
  5, 0, 18, 9, 5, 3, 18, 3, 0, 0, 0, 0, 9, 15, 5, 8, 9, 19, 5, 4, 0, 0, 0, 0,
  20, 0, 4, 9, 20, 0, 2, 9, 0, 0, 0, 0, 2, 0, 18, 3, 2, 1, 18, 1, 0, 0, 0, 0,
  5, 22, 19, 2, 5, 23, 19, 1, 0, 0, 0, 0, 0, 0, 4, 9, 2, 0, 2, 9, 0, 0, 0, 0,
  5, 6, 19, 18, 5, 12, 19, 6, 0, 0, 0, 0, 0, 1, 6, 9, 2, 1, 2, 9, 0, 0, 0, 0,
  6, 5, 14, 12, 13, 5, 7, 6, 6, 11, 7, 6, 0, 1, 20, 2, 0, 2, 20, 1, 0, 0, 0, 0,
  1, 2, 22, 3, 1, 3, 22, 1, 0, 0, 0, 0, 2, 8, 7, 9, 2, 11, 7, 3, 0, 0, 0, 0,
  2, 12, 22, 4, 13, 12, 11, 2, 2, 14, 11, 2, 0, 12, 22, 4, 0, 12, 11, 2, 11, 14, 11, 2,
  9, 7, 6, 11, 11, 7, 2, 11, 0, 0, 0, 0, 7, 1, 9, 6, 10, 1, 3, 6, 0, 0, 0, 0,
  11, 2, 4, 10, 11, 7, 4, 5, 0, 0, 0, 0, 6, 4, 12, 12, 6, 10, 12, 6, 0, 0, 0, 0,
  18, 1, 6, 15, 18, 6, 6, 5, 0, 0, 0, 0, 3, 15, 18, 3, 3, 16, 18, 1, 0, 0, 0, 0,
  18, 5, 6, 9, 18, 8, 6, 3, 0, 0, 0, 0, 1, 5, 16, 6, 1, 5, 8, 3, 9, 8, 8, 3,
  11, 0, 6, 9, 13, 0, 2, 9, 0, 0, 0, 0, 0, 4, 24, 14, 0, 4, 12, 7, 12, 11, 12, 7,
  13, 0, 4, 13, 13, 0, 2, 13, 0, 0, 0, 0, 7, 0, 4, 13, 9, 0, 2, 13, 0, 0, 0, 0,
  11, 6, 6, 9, 13, 6, 2, 9, 0, 0, 0, 0, 8, 7, 6, 9, 10, 7, 2, 9, 0, 0, 0, 0,
  13, 17, 9, 6, 13, 19, 9, 2, 0, 0, 0, 0, 2, 18, 14, 6, 2, 18, 7, 3, 9, 21, 7, 3,
  3, 18, 18, 4, 12, 18, 9, 2, 3, 20, 9, 2, 0, 20, 15, 4, 5, 20, 5, 4, 0, 0, 0, 0,
  9, 15, 15, 9, 14, 15, 5, 9, 0, 0, 0, 0, 4, 4, 16, 4, 4, 6, 16, 2, 0, 0, 0, 0,
  7, 6, 10, 6, 7, 8, 10, 2, 0, 0, 0, 0, 0, 14, 15, 10, 5, 14, 5, 10, 0, 0, 0, 0,
  7, 9, 10, 14, 12, 9, 5, 7, 7, 16, 5, 7, 7, 6, 6, 9, 9, 6, 2, 9, 0, 0, 0, 0,
  3, 6, 18, 3, 3, 7, 18, 1, 0, 0, 0, 0, 0, 10, 18, 3, 0, 11, 18, 1, 0, 0, 0, 0,
  3, 16, 18, 4, 12, 16, 9, 2, 3, 18, 9, 2, 4, 6, 14, 6, 4, 6, 7, 3, 11, 9, 7, 3,
  13, 0, 2, 18, 13, 0, 1, 18, 0, 0, 0, 0, 9, 0, 2, 18, 10, 0, 1, 18, 0, 0, 0, 0,
  5, 7, 15, 10, 10, 7, 5, 10, 0, 0, 0, 0, 1, 20, 21, 4, 8, 20, 7, 4, 0, 0, 0, 0,
  10, 5, 5, 18, 10, 14, 5, 9, 0, 0, 0, 0, 0, 2, 24, 6, 0, 2, 12, 3, 12, 5, 12, 3,
  1, 1, 22, 8, 12, 1, 11, 4, 1, 5, 11, 4, 4, 0, 15, 9, 4, 3, 15, 3, 0, 0, 0, 0,
  0, 0, 24, 19, 8, 0, 8, 19, 0, 0, 0, 0, 2, 21, 18, 3, 11, 21, 9, 3, 0, 0, 0, 0,
  9, 7, 10, 4, 9, 7, 5, 4, 0, 0, 0, 0, 5, 7, 10, 4, 10, 7, 5, 4, 0, 0, 0, 0,
  17, 8, 6, 16, 20, 8, 3, 8, 17, 16, 3, 8, 1, 15, 20, 4, 1, 15, 10, 2, 11, 17, 10, 2,
  14, 15, 10, 6, 14, 17, 10, 2, 0, 0, 0, 0, 3, 0, 16, 9, 3, 3, 16, 3, 0, 0, 0, 0,
  15, 6, 7, 15, 15, 11, 7, 5, 0, 0, 0, 0, 9, 1, 6, 13, 11, 1, 2, 13, 0, 0, 0, 0,
  17, 2, 6, 14, 17, 2, 3, 14, 0, 0, 0, 0, 3, 14, 12, 10, 3, 14, 6, 5, 9, 19, 6, 5,
  7, 6, 10, 6, 7, 8, 10, 2, 0, 0, 0, 0, 1, 2, 6, 14, 4, 2, 3, 14, 0, 0, 0, 0,
  10, 4, 5, 12, 10, 8, 5, 4, 0, 0, 0, 0, 0, 17, 24, 5, 8, 17, 8, 5, 0, 0, 0, 0,
  15, 7, 5, 12, 15, 11, 5, 4, 0, 0, 0, 0, 3, 1, 6, 12, 3, 1, 3, 6, 6, 7, 3, 6,
  12, 13, 6, 6, 12, 16, 6, 3, 0, 0, 0, 0, 6, 13, 6, 6, 6, 16, 6, 3, 0, 0, 0, 0,
  14, 6, 3, 16, 14, 14, 3, 8, 0, 0, 0, 0, 1, 12, 13, 6, 1, 14, 13, 2, 0, 0, 0, 0,
  13, 1, 4, 9, 13, 1, 2, 9, 0, 0, 0, 0, 7, 0, 9, 6, 10, 0, 3, 6, 0, 0, 0, 0,
  12, 2, 6, 9, 12, 2, 3, 9, 0, 0, 0, 0, 6, 2, 6, 9, 9, 2, 3, 9, 0, 0, 0, 0,
  6, 18, 12, 6, 6, 20, 12, 2, 0, 0, 0, 0, 7, 6, 6, 9, 9, 6, 2, 9, 0, 0, 0, 0,
  7, 7, 12, 3, 7, 7, 6, 3, 0, 0, 0, 0, 8, 3, 8, 21, 8, 10, 8, 7, 0, 0, 0, 0,
  7, 4, 10, 12, 7, 8, 10, 4, 0, 0, 0, 0, 0, 1, 6, 9, 0, 4, 6, 3, 0, 0, 0, 0,
  15, 2, 2, 20, 15, 2, 1, 20, 0, 0, 0, 0, 0, 3, 6, 9, 0, 6, 6, 3, 0, 0, 0, 0,
  15, 3, 2, 21, 15, 3, 1, 21, 0, 0, 0, 0, 7, 0, 2, 23, 8, 0, 1, 23, 0, 0, 0, 0,
  15, 8, 9, 4, 15, 10, 9, 2, 0, 0, 0, 0, 0, 8, 9, 4, 0, 10, 9, 2, 0, 0, 0, 0,
  8, 14, 9, 6, 8, 16, 9, 2, 0, 0, 0, 0, 0, 14, 9, 6, 0, 16, 9, 2, 0, 0, 0, 0,
  3, 10, 18, 4, 9, 10, 6, 4, 0, 0, 0, 0, 0, 0, 24, 19, 8, 0, 8, 19, 0, 0, 0, 0,
  9, 1, 8, 12, 9, 7, 8, 6, 0, 0, 0, 0, 10, 6, 4, 10, 12, 6, 2, 10, 0, 0, 0, 0,
  7, 9, 10, 12, 12, 9, 5, 6, 7, 15, 5, 6, 5, 0, 3, 19, 6, 0, 1, 19, 0, 0, 0, 0,
  14, 0, 6, 10, 16, 0, 2, 10, 0, 0, 0, 0, 2, 0, 6, 12, 2, 0, 3, 6, 5, 6, 3, 6,
  0, 11, 24, 2, 0, 12, 24, 1, 0, 0, 0, 0, 4, 9, 13, 4, 4, 11, 13, 2, 0, 0, 0, 0,
  9, 8, 6, 9, 9, 11, 6, 3, 0, 0, 0, 0, 0, 12, 16, 4, 0, 14, 16, 2, 0, 0, 0, 0,
  18, 12, 6, 9, 18, 15, 6, 3, 0, 0, 0, 0, 0, 12, 6, 9, 0, 15, 6, 3, 0, 0, 0, 0,
  8, 7, 10, 4, 8, 7, 5, 4, 0, 0, 0, 0, 8, 7, 6, 9, 10, 7, 2, 9, 0, 0, 0, 0,
  11, 0, 6, 9, 13, 0, 2, 9, 0, 0, 0, 0, 7, 0, 6, 9, 9, 0, 2, 9, 0, 0, 0, 0,
  12, 3, 6, 15, 14, 3, 2, 15, 0, 0, 0, 0, 6, 3, 6, 15, 8, 3, 2, 15, 0, 0, 0, 0,
  15, 2, 9, 4, 15, 4, 9, 2, 0, 0, 0, 0, 5, 10, 6, 7, 8, 10, 3, 7, 0, 0, 0, 0,
  9, 14, 6, 10, 9, 19, 6, 5, 0, 0, 0, 0, 7, 13, 5, 8, 7, 17, 5, 4, 0, 0, 0, 0,
  14, 5, 3, 16, 14, 13, 3, 8, 0, 0, 0, 0, 2, 17, 18, 3, 2, 18, 18, 1, 0, 0, 0, 0,
  5, 18, 19, 3, 5, 19, 19, 1, 0, 0, 0, 0, 9, 0, 6, 9, 11, 0, 2, 9, 0, 0, 0, 0,
  12, 4, 3, 18, 13, 4, 1, 18, 0, 0, 0, 0, 9, 4, 3, 18, 10, 4, 1, 18, 0, 0, 0, 0,
  3, 3, 18, 9, 9, 3, 6, 9, 0, 0, 0, 0, 6, 1, 6, 14, 8, 1, 2, 14, 0, 0, 0, 0,
  12, 16, 9, 6, 12, 19, 9, 3, 0, 0, 0, 0, 1, 3, 20, 16, 1, 3, 10, 8, 11, 11, 10, 8,
  12, 5, 6, 12, 15, 5, 3, 6, 12, 11, 3, 6, 1, 2, 22, 16, 1, 2, 11, 8, 12, 10, 11, 8,
  10, 14, 5, 10, 10, 19, 5, 5, 0, 0, 0, 0, 3, 21, 18, 3, 3, 22, 18, 1, 0, 0, 0, 0,
  10, 14, 6, 10, 12, 14, 2, 10, 0, 0, 0, 0, 0, 2, 24, 4, 8, 2, 8, 4, 0, 0, 0, 0,
  6, 4, 12, 9, 6, 7, 12, 3, 0, 0, 0, 0, 6, 6, 12, 5, 10, 6, 4, 5, 0, 0, 0, 0,
  5, 8, 14, 12, 5, 12, 14, 4, 0, 0, 0, 0, 4, 14, 8, 10, 4, 14, 4, 5, 8, 19, 4, 5,
  11, 6, 5, 14, 11, 13, 5, 7, 0, 0, 0, 0, 7, 6, 3, 16, 7, 14, 3, 8, 0, 0, 0, 0,
  3, 7, 18, 8, 9, 7, 6, 8, 0, 0, 0, 0, 2, 3, 20, 2, 2, 4, 20, 1, 0, 0, 0, 0,
  3, 12, 19, 6, 3, 14, 19, 2, 0, 0, 0, 0, 8, 6, 6, 9, 10, 6, 2, 9, 0, 0, 0, 0,
  16, 6, 6, 14, 16, 6, 3, 14, 0, 0, 0, 0, 7, 9, 6, 12, 9, 9, 2, 12, 0, 0, 0, 0,
  18, 6, 6, 18, 21, 6, 3, 9, 18, 15, 3, 9, 0, 6, 6, 18, 0, 6, 3, 9, 3, 15, 3, 9,
  18, 2, 6, 9, 18, 5, 6, 3, 0, 0, 0, 0, 3, 18, 15, 6, 3, 20, 15, 2, 0, 0, 0, 0,
  18, 2, 6, 9, 18, 5, 6, 3, 0, 0, 0, 0, 0, 2, 6, 9, 0, 5, 6, 3, 0, 0, 0, 0,
  5, 10, 18, 2, 5, 11, 18, 1, 0, 0, 0, 0, 6, 0, 12, 6, 6, 2, 12, 2, 0, 0, 0, 0,
  10, 0, 6, 9, 12, 0, 2, 9, 0, 0, 0, 0, 8, 0, 6, 9, 10, 0, 2, 9, 0, 0, 0, 0,
  15, 12, 9, 6, 15, 14, 9, 2, 0, 0, 0, 0, 3, 6, 13, 6, 3, 8, 13, 2, 0, 0, 0, 0,
  15, 12, 9, 6, 15, 14, 9, 2, 0, 0, 0, 0, 2, 5, 6, 15, 5, 5, 3, 15, 0, 0, 0, 0,
  8, 8, 9, 6, 11, 8, 3, 6, 0, 0, 0, 0, 8, 6, 3, 14, 8, 13, 3, 7, 0, 0, 0, 0,
  15, 12, 9, 6, 15, 14, 9, 2, 0, 0, 0, 0, 4, 12, 10, 4, 9, 12, 5, 4, 0, 0, 0, 0,
  13, 1, 4, 19, 13, 1, 2, 19, 0, 0, 0, 0, 7, 1, 4, 19, 9, 1, 2, 19, 0, 0, 0, 0,
  18, 9, 6, 9, 18, 12, 6, 3, 0, 0, 0, 0, 1, 21, 18, 3, 1, 22, 18, 1, 0, 0, 0, 0,
  14, 13, 10, 9, 14, 16, 10, 3, 0, 0, 0, 0, 1, 13, 22, 4, 1, 13, 11, 2, 12, 15, 11, 2,
  4, 6, 16, 6, 12, 6, 8, 3, 4, 9, 8, 3, 1, 0, 18, 22, 1, 0, 9, 11, 10, 11, 9, 11,
  10, 7, 8, 14, 14, 7, 4, 7, 10, 14, 4, 7, 0, 4, 6, 20, 0, 4, 3, 10, 3, 14, 3, 10,
  15, 0, 6, 9, 17, 0, 2, 9, 0, 0, 0, 0, 3, 0, 6, 9, 5, 0, 2, 9, 0, 0, 0, 0,
  15, 12, 6, 12, 18, 12, 3, 6, 15, 18, 3, 6, 3, 12, 6, 12, 3, 12, 3, 6, 6, 18, 3, 6,
  15, 12, 9, 6, 15, 14, 9, 2, 0, 0, 0, 0, 0, 12, 9, 6, 0, 14, 9, 2, 0, 0, 0, 0,
  4, 14, 19, 3, 4, 15, 19, 1, 0, 0, 0, 0, 2, 13, 19, 3, 2, 14, 19, 1, 0, 0, 0, 0,
  14, 15, 10, 6, 14, 17, 10, 2, 0, 0, 0, 0, 6, 0, 10, 12, 6, 0, 5, 6, 11, 6, 5, 6,
  17, 1, 6, 12, 20, 1, 3, 6, 17, 7, 3, 6, 1, 1, 6, 12, 1, 1, 3, 6, 4, 7, 3, 6,
  16, 14, 6, 9, 16, 17, 6, 3, 0, 0, 0, 0, 7, 3, 9, 12, 7, 9, 9, 6, 0, 0, 0, 0,
  12, 1, 4, 12, 12, 7, 4, 6, 0, 0, 0, 0, 4, 0, 14, 8, 4, 4, 14, 4, 0, 0, 0, 0,
  10, 6, 6, 9, 12, 6, 2, 9, 0, 0, 0, 0, 2, 10, 18, 3, 8, 10, 6, 3, 0, 0, 0, 0,
  15, 15, 9, 6, 15, 17, 9, 2, 0, 0, 0, 0, 0, 1, 21, 23, 7, 1, 7, 23, 0, 0, 0, 0,
  6, 9, 17, 4, 6, 11, 17, 2, 0, 0, 0, 0, 1, 0, 11, 18, 1, 6, 11, 6, 0, 0, 0, 0,
  6, 15, 13, 6, 6, 17, 13, 2, 0, 0, 0, 0, 0, 15, 9, 6, 0, 17, 9, 2, 0, 0, 0, 0,
  8, 7, 15, 4, 13, 7, 5, 4, 0, 0, 0, 0, 9, 12, 6, 9, 9, 15, 6, 3, 0, 0, 0, 0,
  6, 8, 18, 3, 12, 8, 6, 3, 0, 0, 0, 0, 0, 14, 24, 4, 8, 14, 8, 4, 0, 0, 0, 0,
  16, 10, 3, 12, 16, 16, 3, 6, 0, 0, 0, 0, 0, 3, 24, 3, 0, 4, 24, 1, 0, 0, 0, 0,
  14, 17, 10, 6, 14, 19, 10, 2, 0, 0, 0, 0, 1, 13, 18, 3, 7, 13, 6, 3, 0, 0, 0, 0,
  5, 0, 18, 9, 5, 3, 18, 3, 0, 0, 0, 0, 4, 3, 16, 9, 4, 6, 16, 3, 0, 0, 0, 0,
  16, 5, 3, 12, 16, 11, 3, 6, 0, 0, 0, 0, 0, 7, 18, 4, 6, 7, 6, 4, 0, 0, 0, 0,
  10, 6, 6, 9, 12, 6, 2, 9, 0, 0, 0, 0, 9, 8, 6, 10, 11, 8, 2, 10, 0, 0, 0, 0,
  9, 15, 6, 9, 11, 15, 2, 9, 0, 0, 0, 0, 3, 1, 18, 21, 12, 1, 9, 21, 0, 0, 0, 0,
  6, 8, 12, 7, 6, 8, 6, 7, 0, 0, 0, 0, 8, 5, 6, 9, 10, 5, 2, 9, 0, 0, 0, 0,
  0, 2, 24, 4, 8, 2, 8, 4, 0, 0, 0, 0, 14, 7, 5, 12, 14, 11, 5, 4, 0, 0, 0, 0,
  5, 7, 5, 12, 5, 11, 5, 4, 0, 0, 0, 0, 9, 6, 6, 9, 11, 6, 2, 9, 0, 0, 0, 0,
  0, 1, 6, 17, 3, 1, 3, 17, 0, 0, 0, 0, 3, 1, 19, 9, 3, 4, 19, 3, 0, 0, 0, 0,
  3, 18, 12, 6, 3, 18, 6, 3, 9, 21, 6, 3, 20, 4, 4, 19, 20, 4, 2, 19, 0, 0, 0, 0,
  0, 16, 10, 7, 5, 16, 5, 7, 0, 0, 0, 0, 8, 7, 10, 12, 13, 7, 5, 6, 8, 13, 5, 6,
  6, 7, 10, 12, 6, 7, 5, 6, 11, 13, 5, 6, 9, 2, 9, 6, 12, 2, 3, 6, 0, 0, 0, 0,
  1, 20, 21, 4, 8, 20, 7, 4, 0, 0, 0, 0, 9, 12, 9, 6, 9, 14, 9, 2, 0, 0, 0, 0,
  7, 2, 9, 6, 10, 2, 3, 6, 0, 0, 0, 0, 13, 0, 4, 14, 13, 0, 2, 14, 0, 0, 0, 0,
  7, 0, 4, 14, 9, 0, 2, 14, 0, 0, 0, 0, 14, 15, 9, 6, 14, 17, 9, 2, 0, 0, 0, 0,
  2, 8, 18, 5, 8, 8, 6, 5, 0, 0, 0, 0, 18, 3, 6, 11, 20, 3, 2, 11, 0, 0, 0, 0,
  6, 5, 11, 14, 6, 12, 11, 7, 0, 0, 0, 0, 18, 4, 6, 9, 18, 7, 6, 3, 0, 0, 0, 0,
  7, 6, 9, 6, 7, 8, 9, 2, 0, 0, 0, 0, 18, 4, 6, 9, 18, 7, 6, 3, 0, 0, 0, 0,
  0, 4, 6, 9, 0, 7, 6, 3, 0, 0, 0, 0, 9, 4, 9, 4, 9, 6, 9, 2, 0, 0, 0, 0,
  0, 22, 19, 2, 0, 23, 19, 1, 0, 0, 0, 0, 17, 14, 6, 9, 17, 17, 6, 3, 0, 0, 0, 0,
  1, 14, 6, 9, 1, 17, 6, 3, 0, 0, 0, 0, 14, 11, 4, 9, 14, 11, 2, 9, 0, 0, 0, 0,
  6, 11, 4, 9, 8, 11, 2, 9, 0, 0, 0, 0, 3, 9, 18, 7, 9, 9, 6, 7, 0, 0, 0, 0,
  9, 12, 6, 10, 9, 17, 6, 5, 0, 0, 0, 0, 12, 0, 6, 9, 14, 0, 2, 9, 0, 0, 0, 0,
  6, 0, 6, 9, 8, 0, 2, 9, 0, 0, 0, 0, 6, 17, 18, 3, 6, 18, 18, 1, 0, 0, 0, 0,
  1, 17, 18, 3, 1, 18, 18, 1, 0, 0, 0, 0, 10, 6, 11, 12, 10, 12, 11, 6, 0, 0, 0, 0,
  5, 6, 14, 6, 5, 6, 7, 3, 12, 9, 7, 3, 5, 4, 15, 4, 5, 6, 15, 2, 0, 0, 0, 0,
  0, 0, 22, 2, 0, 1, 22, 1, 0, 0, 0, 0, 0, 0, 24, 24, 8, 0, 8, 24, 0, 0, 0, 0,
  1, 15, 18, 4, 10, 15, 9, 4, 0, 0, 0, 0, 6, 8, 12, 9, 6, 11, 12, 3, 0, 0, 0, 0,
  4, 12, 7, 12, 4, 16, 7, 4, 0, 0, 0, 0, 1, 2, 22, 6, 12, 2, 11, 3, 1, 5, 11, 3,
  5, 20, 14, 3, 12, 20, 7, 3, 0, 0, 0, 0, 0, 0, 24, 16, 12, 0, 12, 8, 0, 8, 12, 8,
  3, 13, 18, 4, 3, 13, 9, 2, 12, 15, 9, 2, 2, 10, 22, 2, 2, 11, 22, 1, 0, 0, 0, 0,
  6, 3, 11, 8, 6, 7, 11, 4, 0, 0, 0, 0, 14, 5, 6, 6, 14, 8, 6, 3, 0, 0, 0, 0,
  0, 7, 24, 6, 0, 9, 24, 2, 0, 0, 0, 0, 14, 0, 10, 10, 19, 0, 5, 5, 14, 5, 5, 5,
  0, 0, 10, 10, 0, 0, 5, 5, 5, 5, 5, 5, 0, 1, 24, 4, 12, 1, 12, 2, 0, 3, 12, 2,
  0, 17, 18, 3, 0, 18, 18, 1, 0, 0, 0, 0, 5, 15, 16, 6, 13, 15, 8, 3, 5, 18, 8, 3,
  3, 15, 16, 6, 3, 15, 8, 3, 11, 18, 8, 3, 6, 16, 18, 3, 6, 17, 18, 1, 0, 0, 0, 0,
  0, 13, 21, 10, 0, 18, 21, 5, 0, 0, 0, 0, 13, 0, 6, 24, 15, 0, 2, 24, 0, 0, 0, 0,
  7, 4, 6, 11, 9, 4, 2, 11, 0, 0, 0, 0, 9, 5, 9, 6, 12, 5, 3, 6, 0, 0, 0, 0,
  1, 4, 2, 20, 1, 14, 2, 10, 0, 0, 0, 0, 13, 0, 6, 24, 15, 0, 2, 24, 0, 0, 0, 0,
  5, 0, 6, 24, 7, 0, 2, 24, 0, 0, 0, 0, 16, 7, 6, 14, 19, 7, 3, 7, 16, 14, 3, 7,
  4, 7, 4, 12, 6, 7, 2, 12, 0, 0, 0, 0, 0, 5, 24, 14, 8, 5, 8, 14, 0, 0, 0, 0,
  5, 13, 10, 6, 5, 15, 10, 2, 0, 0, 0, 0, 12, 0, 6, 9, 14, 0, 2, 9, 0, 0, 0, 0,
  2, 7, 6, 14, 2, 7, 3, 7, 5, 14, 3, 7, 15, 2, 9, 15, 18, 2, 3, 15, 0, 0, 0, 0,
  0, 2, 6, 9, 2, 2, 2, 9, 0, 0, 0, 0, 12, 2, 10, 14, 17, 2, 5, 7, 12, 9, 5, 7,
  11, 6, 2, 18, 12, 6, 1, 18, 0, 0, 0, 0, 9, 5, 15, 6, 14, 5, 5, 6, 0, 0, 0, 0,
  8, 6, 6, 10, 10, 6, 2, 10, 0, 0, 0, 0, 12, 0, 6, 9, 14, 0, 2, 9, 0, 0, 0, 0,
  3, 3, 9, 7, 6, 3, 3, 7, 0, 0, 0, 0, 6, 7, 14, 3, 6, 7, 7, 3, 0, 0, 0, 0,
  7, 7, 8, 6, 11, 7, 4, 6, 0, 0, 0, 0, 12, 7, 7, 12, 12, 13, 7, 6, 0, 0, 0, 0,
  10, 6, 4, 18, 10, 6, 2, 9, 12, 15, 2, 9, 16, 14, 6, 9, 16, 17, 6, 3, 0, 0, 0, 0,
  4, 0, 6, 13, 6, 0, 2, 13, 0, 0, 0, 0, 2, 2, 21, 3, 9, 2, 7, 3, 0, 0, 0, 0,
  5, 4, 5, 12, 5, 8, 5, 4, 0, 0, 0, 0, 10, 3, 4, 10, 10, 8, 4, 5, 0, 0, 0, 0,
  8, 4, 5, 8, 8, 8, 5, 4, 0, 0, 0, 0, 6, 0, 11, 9, 6, 3, 11, 3, 0, 0, 0, 0,
  6, 6, 12, 5, 10, 6, 4, 5, 0, 0, 0, 0, 0, 0, 24, 5, 8, 0, 8, 5, 0, 0, 0, 0,
  1, 10, 23, 6, 1, 12, 23, 2, 0, 0, 0, 0, 3, 21, 18, 3, 9, 21, 6, 3, 0, 0, 0, 0,
  3, 6, 21, 6, 3, 8, 21, 2, 0, 0, 0, 0, 0, 5, 6, 12, 2, 5, 2, 12, 0, 0, 0, 0,
  10, 2, 4, 15, 10, 7, 4, 5, 0, 0, 0, 0, 8, 7, 8, 10, 8, 12, 8, 5, 0, 0, 0, 0,
  5, 7, 15, 12, 10, 7, 5, 12, 0, 0, 0, 0, 0, 17, 10, 6, 0, 19, 10, 2, 0, 0, 0, 0,
  14, 18, 9, 6, 14, 20, 9, 2, 0, 0, 0, 0, 9, 6, 6, 16, 9, 14, 6, 8, 0, 0, 0, 0,
  14, 18, 9, 6, 14, 20, 9, 2, 0, 0, 0, 0, 1, 18, 9, 6, 1, 20, 9, 2, 0, 0, 0, 0,
  15, 9, 9, 6, 15, 11, 9, 2, 0, 0, 0, 0, 0, 9, 9, 6, 0, 11, 9, 2, 0, 0, 0, 0,
  17, 3, 6, 9, 19, 3, 2, 9, 0, 0, 0, 0, 2, 17, 18, 3, 2, 18, 18, 1, 0, 0, 0, 0,
  3, 15, 21, 6, 3, 17, 21, 2, 0, 0, 0, 0, 9, 17, 6, 6, 9, 20, 6, 3, 0, 0, 0, 0,
  18, 3, 6, 9, 18, 6, 6, 3, 0, 0, 0, 0, 0, 3, 6, 9, 0, 6, 6, 3, 0, 0, 0, 0,
  4, 0, 16, 10, 12, 0, 8, 5, 4, 5, 8, 5, 2, 0, 10, 16, 2, 0, 5, 8, 7, 8, 5, 8,
  14, 0, 10, 5, 14, 0, 5, 5, 0, 0, 0, 0, 0, 0, 10, 5, 5, 0, 5, 5, 0, 0, 0, 0,
  18, 3, 6, 10, 18, 3, 3, 10, 0, 0, 0, 0, 5, 11, 12, 6, 5, 11, 6, 3, 11, 14, 6, 3,
  21, 0, 3, 18, 22, 0, 1, 18, 0, 0, 0, 0, 6, 0, 6, 9, 8, 0, 2, 9, 0, 0, 0, 0,
  8, 8, 9, 7, 11, 8, 3, 7, 0, 0, 0, 0, 7, 12, 8, 10, 7, 12, 4, 5, 11, 17, 4, 5,
  21, 0, 3, 18, 22, 0, 1, 18, 0, 0, 0, 0, 10, 6, 4, 9, 12, 6, 2, 9, 0, 0, 0, 0,
  15, 0, 9, 6, 15, 2, 9, 2, 0, 0, 0, 0, 0, 2, 24, 3, 0, 3, 24, 1, 0, 0, 0, 0,
  11, 7, 6, 9, 13, 7, 2, 9, 0, 0, 0, 0, 7, 6, 6, 10, 9, 6, 2, 10, 0, 0, 0, 0,
  12, 1, 6, 12, 14, 1, 2, 12, 0, 0, 0, 0, 6, 4, 12, 12, 6, 10, 12, 6, 0, 0, 0, 0,
  14, 3, 2, 21, 14, 3, 1, 21, 0, 0, 0, 0, 6, 1, 12, 8, 6, 5, 12, 4, 0, 0, 0, 0,
  3, 0, 18, 8, 3, 4, 18, 4, 0, 0, 0, 0, 3, 0, 18, 3, 3, 1, 18, 1, 0, 0, 0, 0,
  0, 13, 24, 4, 12, 13, 12, 2, 0, 15, 12, 2, 10, 5, 4, 9, 12, 5, 2, 9, 0, 0, 0, 0,
  11, 1, 6, 9, 13, 1, 2, 9, 0, 0, 0, 0, 6, 2, 6, 22, 8, 2, 2, 22, 0, 0, 0, 0,
  16, 10, 8, 14, 20, 10, 4, 7, 16, 17, 4, 7, 3, 4, 16, 15, 3, 9, 16, 5, 0, 0, 0, 0,
  16, 10, 8, 14, 20, 10, 4, 7, 16, 17, 4, 7, 0, 10, 8, 14, 0, 10, 4, 7, 4, 17, 4, 7,
  10, 14, 11, 6, 10, 17, 11, 3, 0, 0, 0, 0, 0, 7, 24, 9, 8, 7, 8, 9, 0, 0, 0, 0,
  13, 1, 4, 16, 13, 1, 2, 16, 0, 0, 0, 0, 7, 1, 4, 16, 9, 1, 2, 16, 0, 0, 0, 0,
  5, 5, 16, 8, 13, 5, 8, 4, 5, 9, 8, 4, 0, 9, 6, 9, 0, 12, 6, 3, 0, 0, 0, 0,
  6, 16, 18, 3, 6, 17, 18, 1, 0, 0, 0, 0, 3, 12, 6, 9, 3, 15, 6, 3, 0, 0, 0, 0,
  8, 14, 9, 6, 8, 16, 9, 2, 0, 0, 0, 0, 2, 13, 8, 10, 2, 13, 4, 5, 6, 18, 4, 5,
  15, 5, 3, 18, 15, 11, 3, 6, 0, 0, 0, 0, 3, 5, 18, 3, 3, 6, 18, 1, 0, 0, 0, 0,
  17, 5, 6, 11, 19, 5, 2, 11, 0, 0, 0, 0, 1, 5, 6, 11, 3, 5, 2, 11, 0, 0, 0, 0,
  19, 1, 4, 9, 19, 1, 2, 9, 0, 0, 0, 0, 1, 1, 4, 9, 3, 1, 2, 9, 0, 0, 0, 0,
  4, 15, 18, 9, 4, 15, 9, 9, 0, 0, 0, 0, 6, 9, 12, 4, 6, 11, 12, 2, 0, 0, 0, 0,
  15, 2, 9, 6, 15, 4, 9, 2, 0, 0, 0, 0, 0, 2, 9, 6, 0, 4, 9, 2, 0, 0, 0, 0,
  15, 0, 6, 17, 17, 0, 2, 17, 0, 0, 0, 0, 3, 0, 6, 17, 5, 0, 2, 17, 0, 0, 0, 0,
  8, 17, 9, 4, 8, 19, 9, 2, 0, 0, 0, 0, 6, 5, 3, 18, 6, 11, 3, 6, 0, 0, 0, 0,
  5, 2, 14, 12, 5, 8, 14, 6, 0, 0, 0, 0, 10, 2, 3, 12, 10, 8, 3, 6, 0, 0, 0, 0,
  10, 7, 14, 15, 10, 12, 14, 5, 0, 0, 0, 0, 0, 7, 14, 15, 0, 12, 14, 5, 0, 0, 0, 0,
  15, 0, 9, 6, 15, 2, 9, 2, 0, 0, 0, 0, 0, 0, 9, 6, 0, 2, 9, 2, 0, 0, 0, 0,
  12, 6, 6, 14, 14, 6, 2, 14, 0, 0, 0, 0, 9, 7, 6, 9, 11, 7, 2, 9, 0, 0, 0, 0,
  12, 6, 6, 15, 14, 6, 2, 15, 0, 0, 0, 0, 6, 6, 6, 15, 8, 6, 2, 15, 0, 0, 0, 0,
  15, 3, 8, 9, 15, 3, 4, 9, 0, 0, 0, 0, 0, 0, 9, 21, 3, 0, 3, 21, 0, 0, 0, 0,
  11, 9, 8, 12, 11, 13, 8, 4, 0, 0, 0, 0, 6, 7, 10, 12, 6, 7, 5, 6, 11, 13, 5, 6,
  10, 6, 4, 18, 12, 6, 2, 9, 10, 15, 2, 9, 0, 0, 6, 9, 0, 3, 6, 3, 0, 0, 0, 0,
  3, 14, 18, 3, 3, 15, 18, 1, 0, 0, 0, 0, 3, 14, 8, 10, 3, 14, 4, 5, 7, 19, 4, 5,
  0, 12, 24, 4, 12, 12, 12, 2, 0, 14, 12, 2, 0, 2, 3, 20, 1, 2, 1, 20, 0, 0, 0, 0,
  12, 16, 10, 8, 17, 16, 5, 4, 12, 20, 5, 4, 2, 16, 10, 8, 2, 16, 5, 4, 7, 20, 5, 4,
  7, 0, 10, 9, 7, 3, 10, 3, 0, 0, 0, 0, 0, 0, 24, 3, 8, 0, 8, 3, 0, 0, 0, 0,
  3, 8, 15, 4, 3, 10, 15, 2, 0, 0, 0, 0, 6, 5, 12, 6, 10, 5, 4, 6, 0, 0, 0, 0,
  5, 13, 14, 6, 5, 16, 14, 3, 0, 0, 0, 0, 11, 14, 4, 10, 11, 19, 4, 5, 0, 0, 0, 0,
  0, 6, 6, 7, 3, 6, 3, 7, 0, 0, 0, 0, 18, 0, 6, 6, 18, 0, 3, 6, 0, 0, 0, 0,
  3, 1, 18, 3, 3, 2, 18, 1, 0, 0, 0, 0, 9, 6, 14, 18, 9, 12, 14, 6, 0, 0, 0, 0,
  0, 0, 6, 6, 3, 0, 3, 6, 0, 0, 0, 0, 13, 11, 6, 6, 13, 11, 3, 6, 0, 0, 0, 0,
  0, 20, 24, 3, 8, 20, 8, 3, 0, 0, 0, 0, 13, 11, 6, 7, 13, 11, 3, 7, 0, 0, 0, 0,
  4, 12, 10, 6, 4, 14, 10, 2, 0, 0, 0, 0, 13, 11, 6, 6, 13, 11, 3, 6, 0, 0, 0, 0,
  5, 11, 6, 7, 8, 11, 3, 7, 0, 0, 0, 0, 7, 4, 11, 12, 7, 8, 11, 4, 0, 0, 0, 0,
  6, 15, 10, 4, 6, 17, 10, 2, 0, 0, 0, 0, 14, 0, 6, 9, 16, 0, 2, 9, 0, 0, 0, 0,
  4, 0, 6, 9, 6, 0, 2, 9, 0, 0, 0, 0, 11, 2, 4, 15, 11, 7, 4, 5, 0, 0, 0, 0,
  0, 0, 20, 3, 0, 1, 20, 1, 0, 0, 0, 0, 13, 18, 10, 6, 13, 20, 10, 2, 0, 0, 0, 0,
  2, 7, 6, 11, 5, 7, 3, 11, 0, 0, 0, 0, 10, 14, 10, 9, 10, 17, 10, 3, 0, 0, 0, 0,
  8, 2, 4, 9, 10, 2, 2, 9, 0, 0, 0, 0, 14, 3, 10, 4, 14, 3, 5, 4, 0, 0, 0, 0,
  6, 6, 12, 6, 6, 6, 6, 3, 12, 9, 6, 3, 8, 8, 8, 10, 12, 8, 4, 5, 8, 13, 4, 5,
  7, 4, 4, 16, 7, 12, 4, 8, 0, 0, 0, 0, 8, 8, 9, 4, 8, 10, 9, 2, 0, 0, 0, 0,
  5, 2, 14, 9, 5, 5, 14, 3, 0, 0, 0, 0, 3, 16, 19, 8, 3, 20, 19, 4, 0, 0, 0, 0,
  0, 0, 10, 8, 5, 0, 5, 8, 0, 0, 0, 0, 5, 2, 16, 18, 5, 2, 8, 18, 0, 0, 0, 0,
  0, 11, 24, 11, 8, 11, 8, 11, 0, 0, 0, 0, 3, 3, 18, 5, 3, 3, 9, 5, 0, 0, 0, 0,
  1, 16, 18, 3, 1, 17, 18, 1, 0, 0, 0, 0, 5, 17, 18, 3, 5, 18, 18, 1, 0, 0, 0, 0,
  1, 13, 9, 6, 1, 15, 9, 2, 0, 0, 0, 0, 1, 9, 23, 10, 1, 14, 23, 5, 0, 0, 0, 0,
  3, 7, 18, 3, 3, 8, 18, 1, 0, 0, 0, 0, 6, 8, 12, 3, 6, 8, 6, 3, 0, 0, 0, 0,
  6, 2, 3, 22, 7, 2, 1, 22, 0, 0, 0, 0, 14, 17, 10, 6, 14, 19, 10, 2, 0, 0, 0, 0,
  1, 18, 10, 6, 1, 20, 10, 2, 0, 0, 0, 0, 11, 3, 6, 12, 13, 3, 2, 12, 0, 0, 0, 0,
  10, 6, 4, 9, 12, 6, 2, 9, 0, 0, 0, 0, 11, 0, 6, 9, 13, 0, 2, 9, 0, 0, 0, 0,
  7, 0, 6, 9, 9, 0, 2, 9, 0, 0, 0, 0, 12, 10, 9, 6, 15, 10, 3, 6, 0, 0, 0, 0,
  2, 11, 6, 9, 5, 11, 3, 9, 0, 0, 0, 0, 14, 5, 3, 19, 15, 5, 1, 19, 0, 0, 0, 0,
  6, 6, 9, 6, 6, 8, 9, 2, 0, 0, 0, 0, 14, 5, 3, 19, 15, 5, 1, 19, 0, 0, 0, 0,
  0, 3, 6, 9, 0, 6, 6, 3, 0, 0, 0, 0, 5, 21, 18, 3, 5, 22, 18, 1, 0, 0, 0, 0,
  1, 10, 18, 4, 7, 10, 6, 4, 0, 0, 0, 0, 13, 4, 8, 10, 17, 4, 4, 5, 13, 9, 4, 5,
  7, 8, 9, 6, 10, 8, 3, 6, 0, 0, 0, 0, 12, 9, 9, 8, 15, 9, 3, 8, 0, 0, 0, 0,
  0, 6, 5, 12, 0, 10, 5, 4, 0, 0, 0, 0, 7, 6, 14, 6, 14, 6, 7, 3, 7, 9, 7, 3,
  7, 5, 3, 19, 8, 5, 1, 19, 0, 0, 0, 0, 8, 4, 15, 20, 13, 4, 5, 20, 0, 0, 0, 0,
  1, 4, 15, 20, 6, 4, 5, 20, 0, 0, 0, 0, 13, 10, 6, 6, 13, 10, 3, 6, 0, 0, 0, 0,
  5, 10, 6, 6, 8, 10, 3, 6, 0, 0, 0, 0, 14, 2, 6, 14, 17, 2, 3, 7, 14, 9, 3, 7,
  4, 2, 6, 14, 4, 2, 3, 7, 7, 9, 3, 7, 12, 4, 6, 7, 12, 4, 3, 7, 0, 0, 0, 0,
  9, 4, 6, 9, 11, 4, 2, 9, 0, 0, 0, 0, 11, 4, 8, 10, 11, 4, 4, 10, 0, 0, 0, 0,
  5, 4, 8, 10, 9, 4, 4, 10, 0, 0, 0, 0, 8, 18, 10, 6, 8, 20, 10, 2, 0, 0, 0, 0,
  1, 18, 21, 6, 1, 20, 21, 2, 0, 0, 0, 0, 9, 2, 12, 6, 9, 2, 6, 6, 0, 0, 0, 0,
  3, 2, 12, 6, 9, 2, 6, 6, 0, 0, 0, 0, 12, 5, 12, 6, 18, 5, 6, 3, 12, 8, 6, 3,
  8, 8, 6, 9, 8, 11, 6, 3, 0, 0, 0, 0, 2, 7, 20, 6, 2, 9, 20, 2, 0, 0, 0, 0,
  0, 5, 12, 6, 0, 5, 6, 3, 6, 8, 6, 3, 14, 14, 8, 10, 18, 14, 4, 5, 14, 19, 4, 5,
  2, 14, 8, 10, 2, 14, 4, 5, 6, 19, 4, 5, 2, 11, 20, 13, 2, 11, 10, 13, 0, 0, 0, 0,
  6, 9, 12, 5, 12, 9, 6, 5, 0, 0, 0, 0, 5, 6, 16, 6, 13, 6, 8, 3, 5, 9, 8, 3,
  1, 19, 9, 4, 1, 21, 9, 2, 0, 0, 0, 0, 7, 5, 12, 5, 11, 5, 4, 5, 0, 0, 0, 0,
  3, 5, 14, 12, 3, 5, 7, 6, 10, 11, 7, 6, 9, 4, 9, 6, 12, 4, 3, 6, 0, 0, 0, 0,
  2, 6, 19, 3, 2, 7, 19, 1, 0, 0, 0, 0, 18, 10, 6, 9, 18, 13, 6, 3, 0, 0, 0, 0,
  3, 7, 18, 2, 3, 8, 18, 1, 0, 0, 0, 0, 20, 2, 4, 18, 22, 2, 2, 9, 20, 11, 2, 9,
  2, 18, 20, 3, 2, 19, 20, 1, 0, 0, 0, 0, 1, 9, 22, 3, 1, 10, 22, 1, 0, 0, 0, 0,
  0, 2, 4, 18, 0, 2, 2, 9, 2, 11, 2, 9, 19, 0, 4, 23, 19, 0, 2, 23, 0, 0, 0, 0,
  0, 3, 6, 19, 3, 3, 3, 19, 0, 0, 0, 0, 18, 2, 6, 9, 20, 2, 2, 9, 0, 0, 0, 0,
  0, 5, 10, 6, 0, 7, 10, 2, 0, 0, 0, 0, 7, 0, 12, 12, 13, 0, 6, 6, 7, 6, 6, 6,
  0, 3, 24, 6, 0, 3, 12, 3, 12, 6, 12, 3, 10, 14, 4, 10, 10, 19, 4, 5, 0, 0, 0, 0,
  8, 9, 4, 15, 8, 14, 4, 5, 0, 0, 0, 0, 4, 11, 17, 6, 4, 14, 17, 3, 0, 0, 0, 0,
  2, 5, 18, 8, 2, 5, 9, 4, 11, 9, 9, 4, 7, 6, 14, 6, 14, 6, 7, 3, 7, 9, 7, 3,
  3, 6, 14, 6, 3, 6, 7, 3, 10, 9, 7, 3, 16, 5, 3, 18, 17, 5, 1, 18, 0, 0, 0, 0,
  5, 5, 3, 18, 6, 5, 1, 18, 0, 0, 0, 0, 10, 10, 14, 4, 10, 12, 14, 2, 0, 0, 0, 0,
  4, 10, 9, 4, 4, 12, 9, 2, 0, 0, 0, 0, 2, 0, 18, 9, 2, 3, 18, 3, 0, 0, 0, 0,
  6, 3, 12, 8, 10, 3, 4, 8, 0, 0, 0, 0, 1, 1, 8, 5, 5, 1, 4, 5, 0, 0, 0, 0,
  12, 7, 7, 8, 12, 11, 7, 4, 0, 0, 0, 0, 0, 12, 22, 4, 0, 14, 22, 2, 0, 0, 0, 0,
  15, 6, 4, 15, 15, 11, 4, 5, 0, 0, 0, 0, 5, 7, 7, 8, 5, 11, 7, 4, 0, 0, 0, 0,
  8, 18, 9, 4, 8, 20, 9, 2, 0, 0, 0, 0, 1, 2, 22, 4, 1, 4, 22, 2, 0, 0, 0, 0,
  17, 3, 6, 17, 19, 3, 2, 17, 0, 0, 0, 0, 8, 2, 8, 18, 8, 11, 8, 9, 0, 0, 0, 0,
  17, 0, 6, 12, 20, 0, 3, 6, 17, 6, 3, 6, 7, 0, 6, 9, 9, 0, 2, 9, 0, 0, 0, 0,
  15, 5, 9, 12, 15, 11, 9, 6, 0, 0, 0, 0, 2, 22, 18, 2, 2, 23, 18, 1, 0, 0, 0, 0,
  10, 10, 12, 6, 16, 10, 6, 3, 10, 13, 6, 3, 0, 1, 4, 11, 2, 1, 2, 11, 0, 0, 0, 0,
  20, 0, 4, 10, 20, 0, 2, 10, 0, 0, 0, 0, 1, 3, 6, 17, 3, 3, 2, 17, 0, 0, 0, 0,
  15, 15, 9, 6, 15, 17, 9, 2, 0, 0, 0, 0, 0, 13, 8, 9, 0, 16, 8, 3, 0, 0, 0, 0,
  16, 8, 6, 12, 16, 12, 6, 4, 0, 0, 0, 0, 2, 8, 6, 12, 2, 12, 6, 4, 0, 0, 0, 0,
  10, 2, 4, 15, 10, 7, 4, 5, 0, 0, 0, 0, 1, 5, 19, 3, 1, 6, 19, 1, 0, 0, 0, 0,
  11, 8, 9, 7, 14, 8, 3, 7, 0, 0, 0, 0, 3, 8, 12, 9, 3, 11, 12, 3, 0, 0, 0, 0,
  3, 6, 18, 3, 3, 7, 18, 1, 0, 0, 0, 0, 10, 0, 4, 12, 10, 6, 4, 6, 0, 0, 0, 0,
  3, 9, 18, 14, 3, 9, 9, 14, 0, 0, 0, 0, 0, 0, 4, 9, 2, 0, 2, 9, 0, 0, 0, 0,
  12, 5, 4, 18, 12, 5, 2, 18, 0, 0, 0, 0, 8, 5, 4, 18, 10, 5, 2, 18, 0, 0, 0, 0,
  10, 5, 6, 10, 12, 5, 2, 10, 0, 0, 0, 0, 9, 4, 4, 11, 11, 4, 2, 11, 0, 0, 0, 0,
  4, 16, 18, 3, 4, 17, 18, 1, 0, 0, 0, 0, 0, 16, 20, 3, 0, 17, 20, 1, 0, 0, 0, 0,
  9, 9, 6, 12, 9, 13, 6, 4, 0, 0, 0, 0, 8, 13, 8, 8, 8, 17, 8, 4, 0, 0, 0, 0,
  13, 10, 3, 12, 13, 16, 3, 6, 0, 0, 0, 0, 5, 9, 14, 14, 5, 9, 7, 7, 12, 16, 7, 7,
  0, 0, 24, 10, 12, 0, 12, 5, 0, 5, 12, 5, 1, 11, 18, 2, 1, 12, 18, 1, 0, 0, 0, 0,
  19, 5, 5, 12, 19, 9, 5, 4, 0, 0, 0, 0, 0, 5, 5, 12, 0, 9, 5, 4, 0, 0, 0, 0,
  16, 6, 8, 18, 20, 6, 4, 9, 16, 15, 4, 9, 0, 6, 8, 18, 0, 6, 4, 9, 4, 15, 4, 9,
  12, 5, 12, 12, 18, 5, 6, 6, 12, 11, 6, 6, 7, 6, 6, 9, 9, 6, 2, 9, 0, 0, 0, 0,
  9, 13, 6, 11, 11, 13, 2, 11, 0, 0, 0, 0, 0, 5, 12, 12, 0, 5, 6, 6, 6, 11, 6, 6,
  1, 2, 23, 3, 1, 3, 23, 1, 0, 0, 0, 0, 1, 15, 19, 3, 1, 16, 19, 1, 0, 0, 0, 0,
  13, 17, 11, 4, 13, 19, 11, 2, 0, 0, 0, 0, 0, 13, 8, 5, 4, 13, 4, 5, 0, 0, 0, 0,
  12, 10, 10, 4, 12, 10, 5, 4, 0, 0, 0, 0, 4, 6, 9, 9, 4, 9, 9, 3, 0, 0, 0, 0,
  15, 14, 9, 6, 15, 16, 9, 2, 0, 0, 0, 0, 1, 12, 9, 6, 1, 14, 9, 2, 0, 0, 0, 0,
  3, 10, 20, 8, 13, 10, 10, 4, 3, 14, 10, 4, 2, 0, 9, 18, 5, 0, 3, 18, 0, 0, 0, 0,
  13, 11, 9, 10, 16, 11, 3, 10, 0, 0, 0, 0, 1, 2, 8, 5, 5, 2, 4, 5, 0, 0, 0, 0,
  3, 4, 21, 6, 10, 4, 7, 6, 0, 0, 0, 0, 7, 0, 10, 14, 7, 0, 5, 7, 12, 7, 5, 7,
  12, 17, 12, 4, 12, 19, 12, 2, 0, 0, 0, 0, 0, 6, 23, 4, 0, 8, 23, 2, 0, 0, 0, 0,
  13, 10, 8, 10, 17, 10, 4, 5, 13, 15, 4, 5, 0, 16, 18, 3, 0, 17, 18, 1, 0, 0, 0, 0,
  15, 16, 9, 4, 15, 18, 9, 2, 0, 0, 0, 0, 0, 16, 9, 4, 0, 18, 9, 2, 0, 0, 0, 0,
  13, 11, 6, 6, 13, 11, 3, 6, 0, 0, 0, 0, 5, 11, 6, 6, 8, 11, 3, 6, 0, 0, 0, 0,
  0, 3, 24, 6, 12, 3, 12, 3, 0, 6, 12, 3, 2, 4, 18, 3, 2, 5, 18, 1, 0, 0, 0, 0,
  0, 0, 24, 4, 12, 0, 12, 2, 0, 2, 12, 2, 1, 16, 18, 3, 1, 17, 18, 1, 0, 0, 0, 0,
  15, 15, 9, 6, 15, 17, 9, 2, 0, 0, 0, 0, 0, 15, 9, 6, 0, 17, 9, 2, 0, 0, 0, 0,
  6, 17, 18, 3, 6, 18, 18, 1, 0, 0, 0, 0, 8, 8, 6, 10, 10, 8, 2, 10, 0, 0, 0, 0,
  10, 6, 6, 9, 12, 6, 2, 9, 0, 0, 0, 0, 8, 8, 5, 8, 8, 12, 5, 4, 0, 0, 0, 0,
  12, 8, 6, 8, 12, 12, 6, 4, 0, 0, 0, 0, 6, 5, 6, 11, 8, 5, 2, 11, 0, 0, 0, 0,
  13, 6, 8, 9, 13, 9, 8, 3, 0, 0, 0, 0, 1, 7, 21, 6, 1, 9, 21, 2, 0, 0, 0, 0,
  15, 5, 3, 12, 15, 11, 3, 6, 0, 0, 0, 0, 6, 9, 11, 12, 6, 13, 11, 4, 0, 0, 0, 0,
  13, 8, 10, 8, 18, 8, 5, 4, 13, 12, 5, 4, 5, 8, 12, 3, 11, 8, 6, 3, 0, 0, 0, 0,
  6, 11, 18, 4, 12, 11, 6, 4, 0, 0, 0, 0, 0, 0, 22, 22, 0, 11, 22, 11, 0, 0, 0, 0,
  11, 2, 6, 8, 11, 6, 6, 4, 0, 0, 0, 0, 9, 0, 6, 9, 11, 0, 2, 9, 0, 0, 0, 0,
  10, 0, 6, 9, 12, 0, 2, 9, 0, 0, 0, 0, 8, 3, 6, 14, 8, 3, 3, 7, 11, 10, 3, 7,
  3, 10, 18, 8, 9, 10, 6, 8, 0, 0, 0, 0, 10, 0, 3, 14, 10, 7, 3, 7, 0, 0, 0, 0,
  4, 3, 16, 20, 4, 13, 16, 10, 0, 0, 0, 0, 9, 4, 6, 10, 11, 4, 2, 10, 0, 0, 0, 0,
  5, 0, 16, 4, 5, 2, 16, 2, 0, 0, 0, 0, 2, 5, 18, 4, 8, 5, 6, 4, 0, 0, 0, 0,
  13, 0, 6, 9, 15, 0, 2, 9, 0, 0, 0, 0, 8, 4, 8, 5, 12, 4, 4, 5, 0, 0, 0, 0,
  12, 10, 10, 4, 12, 10, 5, 4, 0, 0, 0, 0, 2, 10, 10, 4, 7, 10, 5, 4, 0, 0, 0, 0,
  7, 11, 12, 5, 11, 11, 4, 5, 0, 0, 0, 0, 3, 10, 8, 10, 3, 10, 4, 5, 7, 15, 4, 5,
  11, 12, 9, 8, 14, 12, 3, 8, 0, 0, 0, 0, 0, 21, 24, 3, 8, 21, 8, 3, 0, 0, 0, 0,
  3, 20, 18, 4, 9, 20, 6, 4, 0, 0, 0, 0, 1, 15, 9, 6, 1, 17, 9, 2, 0, 0, 0, 0,
  11, 17, 10, 4, 11, 19, 10, 2, 0, 0, 0, 0, 9, 12, 4, 12, 9, 18, 4, 6, 0, 0, 0, 0,
  9, 6, 9, 6, 12, 6, 3, 6, 0, 0, 0, 0, 1, 13, 6, 9, 1, 16, 6, 3, 0, 0, 0, 0,
  6, 16, 12, 4, 6, 18, 12, 2, 0, 0, 0, 0, 1, 5, 20, 3, 1, 6, 20, 1, 0, 0, 0, 0,
  8, 1, 9, 9, 8, 4, 9, 3, 0, 0, 0, 0, 2, 19, 9, 4, 2, 21, 9, 2, 0, 0, 0, 0,
  11, 1, 4, 18, 11, 7, 4, 6, 0, 0, 0, 0, 7, 2, 8, 12, 7, 2, 4, 6, 11, 8, 4, 6,
  11, 10, 9, 8, 14, 10, 3, 8, 0, 0, 0, 0, 5, 11, 12, 5, 9, 11, 4, 5, 0, 0, 0, 0,
  11, 9, 9, 6, 14, 9, 3, 6, 0, 0, 0, 0, 5, 10, 6, 9, 7, 10, 2, 9, 0, 0, 0, 0,
  4, 7, 5, 12, 4, 11, 5, 4, 0, 0, 0, 0, 2, 0, 21, 6, 9, 0, 7, 6, 0, 0, 0, 0,
  7, 6, 10, 6, 7, 8, 10, 2, 0, 0, 0, 0, 9, 0, 6, 15, 11, 0, 2, 15, 0, 0, 0, 0,
  2, 2, 18, 2, 2, 3, 18, 1, 0, 0, 0, 0, 8, 17, 8, 6, 8, 20, 8, 3, 0, 0, 0, 0,
  3, 0, 18, 2, 3, 1, 18, 1, 0, 0, 0, 0, 8, 0, 9, 6, 11, 0, 3, 6, 0, 0, 0, 0,
  0, 17, 18, 3, 0, 18, 18, 1, 0, 0, 0, 0, 6, 7, 12, 5, 10, 7, 4, 5, 0, 0, 0, 0,
  0, 3, 6, 9, 2, 3, 2, 9, 0, 0, 0, 0, 20, 2, 4, 9, 20, 2, 2, 9, 0, 0, 0, 0,
  0, 2, 4, 9, 2, 2, 2, 9, 0, 0, 0, 0, 0, 1, 24, 4, 12, 1, 12, 2, 0, 3, 12, 2,
  0, 16, 9, 6, 0, 18, 9, 2, 0, 0, 0, 0, 14, 13, 9, 6, 14, 15, 9, 2, 0, 0, 0, 0,
  0, 15, 19, 3, 0, 16, 19, 1, 0, 0, 0, 0, 1, 5, 22, 12, 12, 5, 11, 6, 1, 11, 11, 6,
  5, 13, 6, 6, 8, 13, 3, 6, 0, 0, 0, 0, 4, 2, 20, 3, 4, 3, 20, 1, 0, 0, 0, 0,
  8, 14, 6, 10, 10, 14, 2, 10, 0, 0, 0, 0, 6, 12, 16, 6, 14, 12, 8, 3, 6, 15, 8, 3,
  2, 13, 8, 9, 2, 16, 8, 3, 0, 0, 0, 0, 11, 8, 6, 14, 14, 8, 3, 7, 11, 15, 3, 7,
  2, 12, 16, 6, 2, 12, 8, 3, 10, 15, 8, 3, 5, 16, 16, 8, 5, 20, 16, 4, 0, 0, 0, 0,
  9, 1, 4, 12, 9, 7, 4, 6, 0, 0, 0, 0, 8, 2, 8, 10, 12, 2, 4, 5, 8, 7, 4, 5,
  6, 6, 12, 6, 6, 6, 6, 3, 12, 9, 6, 3, 10, 7, 6, 9, 12, 7, 2, 9, 0, 0, 0, 0,
  0, 0, 8, 12, 0, 0, 4, 6, 4, 6, 4, 6, 18, 8, 6, 9, 18, 11, 6, 3, 0, 0, 0, 0,
  2, 12, 6, 6, 5, 12, 3, 6, 0, 0, 0, 0, 3, 21, 21, 3, 10, 21, 7, 3, 0, 0, 0, 0,
  2, 0, 16, 6, 2, 3, 16, 3, 0, 0, 0, 0, 13, 6, 7, 6, 13, 9, 7, 3, 0, 0, 0, 0,
  6, 4, 4, 14, 6, 11, 4, 7, 0, 0, 0, 0, 9, 7, 6, 9, 11, 7, 2, 9, 0, 0, 0, 0,
  7, 8, 6, 14, 7, 8, 3, 7, 10, 15, 3, 7, 18, 8, 4, 16, 18, 16, 4, 8, 0, 0, 0, 0,
  9, 14, 6, 10, 11, 14, 2, 10, 0, 0, 0, 0, 6, 11, 12, 5, 10, 11, 4, 5, 0, 0, 0, 0,
  0, 12, 23, 3, 0, 13, 23, 1, 0, 0, 0, 0, 13, 0, 6, 12, 15, 0, 2, 12, 0, 0, 0, 0,
  0, 10, 12, 5, 4, 10, 4, 5, 0, 0, 0, 0, 13, 2, 10, 4, 13, 4, 10, 2, 0, 0, 0, 0,
  5, 0, 6, 12, 7, 0, 2, 12, 0, 0, 0, 0, 11, 6, 9, 6, 14, 6, 3, 6, 0, 0, 0, 0,
  4, 6, 9, 6, 7, 6, 3, 6, 0, 0, 0, 0, 6, 11, 18, 13, 12, 11, 6, 13, 0, 0, 0, 0,
  0, 11, 18, 13, 6, 11, 6, 13, 0, 0, 0, 0, 12, 16, 12, 6, 16, 16, 4, 6, 0, 0, 0, 0,
  0, 6, 21, 3, 0, 7, 21, 1, 0, 0, 0, 0, 12, 16, 12, 6, 16, 16, 4, 6, 0, 0, 0, 0,
  5, 7, 6, 14, 5, 14, 6, 7, 0, 0, 0, 0, 5, 10, 19, 2, 5, 11, 19, 1, 0, 0, 0, 0,
  5, 4, 14, 4, 5, 6, 14, 2, 0, 0, 0, 0, 3, 18, 18, 4, 9, 18, 6, 4, 0, 0, 0, 0,
  7, 0, 4, 9, 9, 0, 2, 9, 0, 0, 0, 0, 13, 3, 11, 4, 13, 5, 11, 2, 0, 0, 0, 0,
  2, 0, 9, 6, 5, 0, 3, 6, 0, 0, 0, 0, 19, 1, 4, 23, 19, 1, 2, 23, 0, 0, 0, 0,
  1, 1, 4, 23, 3, 1, 2, 23, 0, 0, 0, 0, 5, 16, 18, 3, 5, 17, 18, 1, 0, 0, 0, 0,
  0, 3, 11, 4, 0, 5, 11, 2, 0, 0, 0, 0, 2, 16, 20, 3, 2, 17, 20, 1, 0, 0, 0, 0,
  5, 3, 13, 4, 5, 5, 13, 2, 0, 0, 0, 0, 1, 9, 22, 15, 1, 9, 11, 15, 0, 0, 0, 0,
  3, 4, 14, 3, 10, 4, 7, 3, 0, 0, 0, 0, 8, 7, 10, 4, 8, 7, 5, 4, 0, 0, 0, 0,
  6, 7, 10, 4, 11, 7, 5, 4, 0, 0, 0, 0, 10, 4, 6, 9, 12, 4, 2, 9, 0, 0, 0, 0,
  1, 12, 9, 6, 4, 12, 3, 6, 0, 0, 0, 0, 8, 3, 8, 10, 12, 3, 4, 5, 8, 8, 4, 5,
  3, 6, 16, 6, 3, 6, 8, 3, 11, 9, 8, 3, 5, 6, 14, 6, 5, 9, 14, 3, 0, 0, 0, 0,
  4, 3, 9, 6, 4, 5, 9, 2, 0, 0, 0, 0, 6, 3, 18, 2, 6, 4, 18, 1, 0, 0, 0, 0,
  7, 6, 9, 6, 10, 6, 3, 6, 0, 0, 0, 0, 0, 1, 24, 3, 0, 2, 24, 1, 0, 0, 0, 0,
  0, 17, 10, 6, 0, 19, 10, 2, 0, 0, 0, 0, 3, 18, 18, 3, 3, 19, 18, 1, 0, 0, 0, 0,
  2, 5, 6, 16, 2, 5, 3, 8, 5, 13, 3, 8, 7, 6, 11, 6, 7, 8, 11, 2, 0, 0, 0, 0,
  5, 2, 12, 22, 5, 13, 12, 11, 0, 0, 0, 0, 10, 7, 4, 10, 10, 12, 4, 5, 0, 0, 0, 0,
  9, 0, 4, 18, 9, 6, 4, 6, 0, 0, 0, 0, 18, 8, 6, 9, 18, 11, 6, 3, 0, 0, 0, 0,
  4, 7, 15, 10, 9, 7, 5, 10, 0, 0, 0, 0, 10, 5, 6, 9, 12, 5, 2, 9, 0, 0, 0, 0,
  9, 9, 6, 10, 11, 9, 2, 10, 0, 0, 0, 0, 11, 14, 6, 10, 13, 14, 2, 10, 0, 0, 0, 0,
  7, 14, 6, 10, 9, 14, 2, 10, 0, 0, 0, 0, 4, 8, 16, 9, 4, 11, 16, 3, 0, 0, 0, 0,
  2, 11, 20, 3, 2, 12, 20, 1, 0, 0, 0, 0, 13, 0, 4, 13, 13, 0, 2, 13, 0, 0, 0, 0,
  7, 0, 4, 13, 9, 0, 2, 13, 0, 0, 0, 0, 3, 1, 18, 7, 9, 1, 6, 7, 0, 0, 0, 0,
  1, 11, 6, 9, 1, 14, 6, 3, 0, 0, 0, 0, 8, 18, 9, 6, 8, 20, 9, 2, 0, 0, 0, 0,
  3, 9, 15, 6, 3, 11, 15, 2, 0, 0, 0, 0, 5, 10, 19, 2, 5, 11, 19, 1, 0, 0, 0, 0,
  8, 6, 7, 16, 8, 14, 7, 8, 0, 0, 0, 0, 9, 14, 9, 6, 9, 16, 9, 2, 0, 0, 0, 0,
  0, 7, 8, 12, 0, 11, 8, 4, 0, 0, 0, 0, 6, 4, 18, 3, 6, 5, 18, 1, 0, 0, 0, 0,
  0, 16, 12, 6, 4, 16, 4, 6, 0, 0, 0, 0, 13, 13, 9, 4, 13, 15, 9, 2, 0, 0, 0, 0,
  5, 8, 14, 14, 5, 8, 7, 7, 12, 15, 7, 7, 1, 16, 22, 6, 12, 16, 11, 3, 1, 19, 11, 3,
  9, 0, 6, 9, 11, 0, 2, 9, 0, 0, 0, 0, 9, 5, 10, 10, 14, 5, 5, 5, 9, 10, 5, 5,
  5, 5, 10, 10, 5, 5, 5, 5, 10, 10, 5, 5, 4, 6, 16, 6, 12, 6, 8, 3, 4, 9, 8, 3,
  0, 7, 6, 9, 0, 10, 6, 3, 0, 0, 0, 0, 16, 10, 8, 14, 20, 10, 4, 7, 16, 17, 4, 7,
  9, 12, 6, 12, 9, 18, 6, 6, 0, 0, 0, 0, 8, 10, 8, 12, 12, 10, 4, 6, 8, 16, 4, 6,
  8, 0, 4, 9, 10, 0, 2, 9, 0, 0, 0, 0, 10, 4, 8, 16, 14, 4, 4, 8, 10, 12, 4, 8,
  7, 10, 10, 6, 7, 12, 10, 2, 0, 0, 0, 0, 5, 6, 14, 14, 12, 6, 7, 7, 5, 13, 7, 7,
  2, 11, 20, 2, 2, 12, 20, 1, 0, 0, 0, 0, 18, 8, 4, 16, 18, 16, 4, 8, 0, 0, 0, 0,
  1, 11, 12, 10, 1, 11, 6, 5, 7, 16, 6, 5, 6, 9, 12, 4, 6, 11, 12, 2, 0, 0, 0, 0,
  9, 12, 6, 7, 12, 12, 3, 7, 0, 0, 0, 0, 10, 4, 8, 16, 14, 4, 4, 8, 10, 12, 4, 8,
  6, 4, 8, 16, 6, 4, 4, 8, 10, 12, 4, 8, 8, 9, 9, 6, 11, 9, 3, 6, 0, 0, 0, 0,
  1, 5, 16, 12, 1, 5, 8, 6, 9, 11, 8, 6, 9, 9, 6, 8, 9, 9, 3, 8, 0, 0, 0, 0,
  6, 0, 3, 18, 7, 0, 1, 18, 0, 0, 0, 0, 17, 9, 5, 14, 17, 16, 5, 7, 0, 0, 0, 0,
  2, 9, 5, 14, 2, 16, 5, 7, 0, 0, 0, 0, 7, 4, 10, 6, 7, 7, 10, 3, 0, 0, 0, 0,
  1, 3, 23, 18, 1, 9, 23, 6, 0, 0, 0, 0, 1, 1, 21, 3, 8, 1, 7, 3, 0, 0, 0, 0,
  9, 6, 6, 9, 11, 6, 2, 9, 0, 0, 0, 0, 3, 18, 12, 6, 3, 18, 6, 3, 9, 21, 6, 3,
  16, 8, 8, 16, 20, 8, 4, 8, 16, 16, 4, 8, 0, 19, 24, 4, 8, 19, 8, 4, 0, 0, 0, 0,
  16, 8, 8, 16, 20, 8, 4, 8, 16, 16, 4, 8, 0, 8, 8, 16, 0, 8, 4, 8, 4, 16, 4, 8,
  8, 12, 8, 10, 8, 17, 8, 5, 0, 0, 0, 0, 5, 7, 5, 8, 5, 11, 5, 4, 0, 0, 0, 0,
  4, 1, 19, 2, 4, 2, 19, 1, 0, 0, 0, 0, 0, 12, 24, 9, 8, 12, 8, 9, 0, 0, 0, 0,
  6, 0, 13, 8, 6, 4, 13, 4, 0, 0, 0, 0, 0, 0, 24, 3, 0, 1, 24, 1, 0, 0, 0, 0,
  20, 3, 4, 11, 20, 3, 2, 11, 0, 0, 0, 0, 8, 6, 6, 9, 10, 6, 2, 9, 0, 0, 0, 0,
  6, 11, 12, 8, 12, 11, 6, 4, 6, 15, 6, 4, 0, 8, 12, 6, 0, 8, 6, 3, 6, 11, 6, 3,
  6, 17, 18, 3, 6, 18, 18, 1, 0, 0, 0, 0, 0, 14, 9, 6, 0, 16, 9, 2, 0, 0, 0, 0,
  20, 3, 4, 9, 20, 3, 2, 9, 0, 0, 0, 0, 0, 3, 4, 9, 2, 3, 2, 9, 0, 0, 0, 0,
  15, 0, 9, 19, 18, 0, 3, 19, 0, 0, 0, 0, 0, 0, 9, 19, 3, 0, 3, 19, 0, 0, 0, 0,
  13, 11, 6, 8, 13, 11, 3, 8, 0, 0, 0, 0, 5, 11, 6, 8, 8, 11, 3, 8, 0, 0, 0, 0,
  5, 11, 19, 3, 5, 12, 19, 1, 0, 0, 0, 0, 3, 20, 18, 4, 9, 20, 6, 4, 0, 0, 0, 0,
  6, 6, 16, 6, 6, 8, 16, 2, 0, 0, 0, 0, 6, 0, 9, 6, 9, 0, 3, 6, 0, 0, 0, 0,
  10, 3, 4, 14, 10, 10, 4, 7, 0, 0, 0, 0, 1, 5, 15, 12, 1, 11, 15, 6, 0, 0, 0, 0,
  11, 12, 8, 5, 11, 12, 4, 5, 0, 0, 0, 0, 5, 0, 6, 9, 7, 0, 2, 9, 0, 0, 0, 0,
  12, 0, 6, 9, 14, 0, 2, 9, 0, 0, 0, 0, 5, 5, 12, 8, 5, 5, 6, 4, 11, 9, 6, 4,
  13, 12, 11, 6, 13, 14, 11, 2, 0, 0, 0, 0, 0, 13, 21, 3, 0, 14, 21, 1, 0, 0, 0, 0,
  8, 1, 8, 12, 12, 1, 4, 6, 8, 7, 4, 6, 1, 0, 6, 12, 1, 0, 3, 6, 4, 6, 3, 6,
  2, 2, 21, 2, 2, 3, 21, 1, 0, 0, 0, 0, 2, 2, 19, 3, 2, 3, 19, 1, 0, 0, 0, 0,
  17, 10, 6, 14, 20, 10, 3, 7, 17, 17, 3, 7, 1, 10, 6, 14, 1, 10, 3, 7, 4, 17, 3, 7,
  7, 6, 14, 14, 14, 6, 7, 7, 7, 13, 7, 7, 0, 12, 9, 6, 0, 14, 9, 2, 0, 0, 0, 0,
  15, 14, 8, 9, 15, 17, 8, 3, 0, 0, 0, 0, 1, 1, 22, 4, 1, 1, 11, 2, 12, 3, 11, 2,
  9, 11, 9, 6, 9, 13, 9, 2, 0, 0, 0, 0, 0, 15, 18, 3, 0, 16, 18, 1, 0, 0, 0, 0,
  16, 14, 7, 9, 16, 17, 7, 3, 0, 0, 0, 0, 4, 3, 16, 4, 12, 3, 8, 4, 0, 0, 0, 0,
  7, 6, 12, 5, 7, 6, 6, 5, 0, 0, 0, 0, 9, 6, 4, 9, 11, 6, 2, 9, 0, 0, 0, 0,
  12, 1, 4, 10, 12, 1, 2, 10, 0, 0, 0, 0, 8, 1, 4, 10, 10, 1, 2, 10, 0, 0, 0, 0,
  15, 15, 6, 9, 15, 18, 6, 3, 0, 0, 0, 0, 3, 15, 6, 9, 3, 18, 6, 3, 0, 0, 0, 0,
  15, 1, 3, 19, 16, 1, 1, 19, 0, 0, 0, 0, 1, 3, 6, 9, 3, 3, 2, 9, 0, 0, 0, 0,
  15, 0, 3, 19, 16, 0, 1, 19, 0, 0, 0, 0, 6, 3, 12, 4, 12, 3, 6, 4, 0, 0, 0, 0,
  10, 5, 4, 9, 10, 5, 2, 9, 0, 0, 0, 0, 6, 0, 3, 19, 7, 0, 1, 19, 0, 0, 0, 0,
  11, 1, 3, 12, 11, 7, 3, 6, 0, 0, 0, 0, 6, 7, 10, 5, 11, 7, 5, 5, 0, 0, 0, 0,
  11, 3, 3, 18, 12, 3, 1, 18, 0, 0, 0, 0, 9, 3, 6, 12, 11, 3, 2, 12, 0, 0, 0, 0,
  3, 7, 19, 3, 3, 8, 19, 1, 0, 0, 0, 0, 2, 7, 18, 3, 2, 8, 18, 1, 0, 0, 0, 0,
  3, 13, 18, 4, 12, 13, 9, 2, 3, 15, 9, 2, 3, 5, 6, 9, 5, 5, 2, 9, 0, 0, 0, 0,
  4, 1, 20, 4, 14, 1, 10, 2, 4, 3, 10, 2, 0, 1, 20, 4, 0, 1, 10, 2, 10, 3, 10, 2,
  10, 15, 6, 6, 10, 15, 3, 6, 0, 0, 0, 0, 0, 2, 24, 8, 8, 2, 8, 8, 0, 0, 0, 0,
  5, 5, 18, 3, 5, 6, 18, 1, 0, 0, 0, 0, 8, 15, 6, 6, 11, 15, 3, 6, 0, 0, 0, 0,
  11, 12, 8, 5, 11, 12, 4, 5, 0, 0, 0, 0, 5, 12, 8, 5, 9, 12, 4, 5, 0, 0, 0, 0,
  5, 0, 14, 6, 5, 2, 14, 2, 0, 0, 0, 0, 10, 2, 4, 15, 10, 7, 4, 5, 0, 0, 0, 0,
  10, 7, 5, 12, 10, 11, 5, 4, 0, 0, 0, 0, 7, 9, 8, 14, 7, 9, 4, 7, 11, 16, 4, 7,
  1, 5, 22, 6, 12, 5, 11, 3, 1, 8, 11, 3, 0, 5, 6, 6, 0, 8, 6, 3, 0, 0, 0, 0,
  12, 17, 9, 4, 12, 19, 9, 2, 0, 0, 0, 0, 2, 18, 19, 3, 2, 19, 19, 1, 0, 0, 0, 0,
  12, 17, 9, 4, 12, 19, 9, 2, 0, 0, 0, 0, 1, 17, 18, 3, 1, 18, 18, 1, 0, 0, 0, 0,
  12, 17, 9, 4, 12, 19, 9, 2, 0, 0, 0, 0, 0, 0, 24, 3, 0, 1, 24, 1, 0, 0, 0, 0,
  5, 0, 14, 4, 5, 2, 14, 2, 0, 0, 0, 0, 6, 14, 9, 6, 6, 16, 9, 2, 0, 0, 0, 0,
  14, 13, 6, 9, 14, 16, 6, 3, 0, 0, 0, 0, 5, 20, 13, 4, 5, 22, 13, 2, 0, 0, 0, 0,
  9, 9, 6, 12, 9, 13, 6, 4, 0, 0, 0, 0, 1, 10, 21, 3, 8, 10, 7, 3, 0, 0, 0, 0,
  8, 8, 9, 6, 11, 8, 3, 6, 0, 0, 0, 0, 3, 10, 9, 7, 6, 10, 3, 7, 0, 0, 0, 0,
  12, 10, 10, 8, 17, 10, 5, 4, 12, 14, 5, 4, 0, 15, 24, 3, 8, 15, 8, 3, 0, 0, 0, 0,
  8, 5, 9, 6, 8, 7, 9, 2, 0, 0, 0, 0, 4, 13, 6, 9, 4, 16, 6, 3, 0, 0, 0, 0,
  12, 17, 9, 4, 12, 19, 9, 2, 0, 0, 0, 0, 9, 12, 6, 6, 9, 15, 6, 3, 0, 0, 0, 0,
  9, 9, 14, 10, 16, 9, 7, 5, 9, 14, 7, 5, 1, 9, 14, 10, 1, 9, 7, 5, 8, 14, 7, 5,
  8, 7, 9, 17, 11, 7, 3, 17, 0, 0, 0, 0, 3, 4, 6, 20, 3, 4, 3, 10, 6, 14, 3, 10,
  7, 8, 10, 4, 7, 8, 5, 4, 0, 0, 0, 0, 10, 7, 4, 9, 12, 7, 2, 9, 0, 0, 0, 0,
  10, 15, 6, 9, 12, 15, 2, 9, 0, 0, 0, 0, 3, 8, 6, 16, 3, 8, 3, 8, 6, 16, 3, 8,
  12, 17, 9, 4, 12, 19, 9, 2, 0, 0, 0, 0, 3, 17, 9, 4, 3, 19, 9, 2, 0, 0, 0, 0,
  10, 1, 9, 6, 13, 1, 3, 6, 0, 0, 0, 0, 5, 7, 4, 10, 5, 12, 4, 5, 0, 0, 0, 0,
  7, 5, 12, 6, 11, 5, 4, 6, 0, 0, 0, 0, 6, 4, 9, 8, 9, 4, 3, 8, 0, 0, 0, 0,
  12, 16, 10, 8, 17, 16, 5, 4, 12, 20, 5, 4, 2, 16, 10, 8, 2, 16, 5, 4, 7, 20, 5, 4,
  0, 0, 24, 4, 12, 0, 12, 2, 0, 2, 12, 2, 0, 6, 9, 6, 0, 8, 9, 2, 0, 0, 0, 0,
  0, 4, 24, 6, 12, 4, 12, 3, 0, 7, 12, 3, 5, 0, 11, 4, 5, 2, 11, 2, 0, 0, 0, 0,
  1, 1, 22, 4, 12, 1, 11, 2, 1, 3, 11, 2, 9, 6, 6, 18, 9, 15, 6, 9, 0, 0, 0, 0,
  2, 9, 20, 4, 2, 11, 20, 2, 0, 0, 0, 0, 5, 2, 14, 14, 5, 9, 14, 7, 0, 0, 0, 0,
  4, 2, 16, 6, 4, 5, 16, 3, 0, 0, 0, 0, 2, 3, 19, 3, 2, 4, 19, 1, 0, 0, 0, 0,
  7, 1, 10, 4, 7, 3, 10, 2, 0, 0, 0, 0, 0, 9, 4, 15, 0, 14, 4, 5, 0, 0, 0, 0,
  2, 10, 21, 3, 2, 11, 21, 1, 0, 0, 0, 0, 3, 0, 6, 6, 6, 0, 3, 6, 0, 0, 0, 0,
  6, 4, 14, 9, 6, 7, 14, 3, 0, 0, 0, 0, 9, 1, 6, 9, 11, 1, 2, 9, 0, 0, 0, 0,
  15, 8, 9, 9, 15, 11, 9, 3, 0, 0, 0, 0, 8, 0, 4, 21, 8, 7, 4, 7, 0, 0, 0, 0,
  3, 22, 19, 2, 3, 23, 19, 1, 0, 0, 0, 0, 2, 15, 20, 3, 2, 16, 20, 1, 0, 0, 0, 0,
  19, 0, 4, 13, 19, 0, 2, 13, 0, 0, 0, 0, 1, 7, 8, 8, 1, 11, 8, 4, 0, 0, 0, 0,
  14, 14, 6, 9, 14, 17, 6, 3, 0, 0, 0, 0, 4, 14, 6, 9, 4, 17, 6, 3, 0, 0, 0, 0,
  14, 5, 4, 10, 14, 5, 2, 10, 0, 0, 0, 0, 6, 5, 4, 10, 8, 5, 2, 10, 0, 0, 0, 0,
  14, 5, 6, 6, 14, 8, 6, 3, 0, 0, 0, 0, 4, 5, 6, 6, 4, 8, 6, 3, 0, 0, 0, 0,
  0, 2, 24, 21, 8, 2, 8, 21, 0, 0, 0, 0, 1, 2, 6, 13, 3, 2, 2, 13, 0, 0, 0, 0,
  20, 0, 4, 21, 20, 0, 2, 21, 0, 0, 0, 0, 0, 4, 4, 20, 2, 4, 2, 20, 0, 0, 0, 0,
  8, 16, 9, 6, 8, 18, 9, 2, 0, 0, 0, 0, 7, 0, 6, 9, 9, 0, 2, 9, 0, 0, 0, 0,
  16, 12, 7, 9, 16, 15, 7, 3, 0, 0, 0, 0, 5, 21, 14, 3, 12, 21, 7, 3, 0, 0, 0, 0,
  11, 5, 6, 9, 11, 5, 3, 9, 0, 0, 0, 0, 10, 5, 4, 10, 12, 5, 2, 10, 0, 0, 0, 0,
  10, 6, 6, 9, 12, 6, 2, 9, 0, 0, 0, 0, 7, 5, 6, 9, 10, 5, 3, 9, 0, 0, 0, 0,
  14, 14, 10, 4, 14, 16, 10, 2, 0, 0, 0, 0, 5, 5, 14, 14, 5, 5, 7, 7, 12, 12, 7, 7,
  12, 8, 12, 6, 18, 8, 6, 3, 12, 11, 6, 3, 6, 6, 12, 12, 6, 6, 6, 6, 12, 12, 6, 6,
  11, 13, 6, 10, 13, 13, 2, 10, 0, 0, 0, 0, 1, 10, 20, 8, 1, 10, 10, 4, 11, 14, 10, 4,
  15, 13, 9, 6, 15, 15, 9, 2, 0, 0, 0, 0, 9, 0, 6, 9, 9, 3, 6, 3, 0, 0, 0, 0,
  10, 1, 5, 14, 10, 8, 5, 7, 0, 0, 0, 0, 3, 4, 16, 6, 3, 6, 16, 2, 0, 0, 0, 0,
  16, 3, 8, 9, 16, 6, 8, 3, 0, 0, 0, 0, 7, 13, 6, 10, 9, 13, 2, 10, 0, 0, 0, 0,
  15, 13, 9, 6, 15, 15, 9, 2, 0, 0, 0, 0, 0, 13, 9, 6, 0, 15, 9, 2, 0, 0, 0, 0,
  13, 16, 9, 6, 13, 18, 9, 2, 0, 0, 0, 0, 2, 16, 9, 6, 2, 18, 9, 2, 0, 0, 0, 0,
  5, 16, 18, 3, 5, 17, 18, 1, 0, 0, 0, 0, 1, 16, 18, 3, 1, 17, 18, 1, 0, 0, 0, 0,
  5, 0, 18, 3, 5, 1, 18, 1, 0, 0, 0, 0, 1, 1, 19, 2, 1, 2, 19, 1, 0, 0, 0, 0,
  14, 2, 6, 11, 16, 2, 2, 11, 0, 0, 0, 0, 4, 15, 15, 6, 9, 15, 5, 6, 0, 0, 0, 0,
  14, 2, 6, 11, 16, 2, 2, 11, 0, 0, 0, 0, 4, 2, 6, 11, 6, 2, 2, 11, 0, 0, 0, 0,
  18, 2, 6, 9, 18, 5, 6, 3, 0, 0, 0, 0, 1, 2, 22, 4, 1, 2, 11, 2, 12, 4, 11, 2,
  2, 0, 21, 12, 9, 0, 7, 12, 0, 0, 0, 0, 0, 12, 18, 3, 0, 13, 18, 1, 0, 0, 0, 0,
  12, 2, 6, 9, 14, 2, 2, 9, 0, 0, 0, 0, 3, 10, 18, 3, 3, 11, 18, 1, 0, 0, 0, 0,
  16, 3, 8, 9, 16, 6, 8, 3, 0, 0, 0, 0, 3, 7, 18, 3, 3, 8, 18, 1, 0, 0, 0, 0,
  9, 11, 6, 9, 11, 11, 2, 9, 0, 0, 0, 0, 9, 8, 6, 9, 11, 8, 2, 9, 0, 0, 0, 0,
  15, 0, 2, 18, 15, 0, 1, 18, 0, 0, 0, 0, 7, 0, 2, 18, 8, 0, 1, 18, 0, 0, 0, 0,
  17, 3, 7, 9, 17, 6, 7, 3, 0, 0, 0, 0, 3, 18, 9, 6, 3, 20, 9, 2, 0, 0, 0, 0,
  3, 18, 21, 3, 3, 19, 21, 1, 0, 0, 0, 0, 0, 3, 7, 9, 0, 6, 7, 3, 0, 0, 0, 0,
  2, 7, 22, 3, 2, 8, 22, 1, 0, 0, 0, 0, 0, 3, 24, 16, 0, 3, 12, 8, 12, 11, 12, 8,
  13, 17, 9, 4, 13, 19, 9, 2, 0, 0, 0, 0, 5, 5, 12, 8, 5, 5, 6, 4, 11, 9, 6, 4,
  5, 6, 14, 6, 12, 6, 7, 3, 5, 9, 7, 3, 5, 16, 14, 6, 5, 16, 7, 3, 12, 19, 7, 3,
  18, 2, 6, 9, 18, 5, 6, 3, 0, 0, 0, 0, 0, 2, 6, 9, 0, 5, 6, 3, 0, 0, 0, 0,
  3, 4, 20, 10, 13, 4, 10, 5, 3, 9, 10, 5, 2, 13, 9, 8, 5, 13, 3, 8, 0, 0, 0, 0,
  2, 1, 21, 15, 9, 1, 7, 15, 0, 0, 0, 0, 5, 12, 14, 8, 12, 12, 7, 8, 0, 0, 0, 0,
  6, 7, 12, 4, 6, 7, 6, 4, 0, 0, 0, 0, 6, 5, 9, 6, 9, 5, 3, 6, 0, 0, 0, 0,
  13, 11, 6, 6, 13, 11, 3, 6, 0, 0, 0, 0, 5, 11, 6, 6, 8, 11, 3, 6, 0, 0, 0, 0,
  6, 4, 18, 2, 6, 5, 18, 1, 0, 0, 0, 0, 0, 2, 6, 11, 2, 2, 2, 11, 0, 0, 0, 0,
  18, 0, 6, 15, 20, 0, 2, 15, 0, 0, 0, 0, 0, 0, 6, 13, 2, 0, 2, 13, 0, 0, 0, 0,
  12, 0, 6, 9, 14, 0, 2, 9, 0, 0, 0, 0, 6, 0, 6, 9, 8, 0, 2, 9, 0, 0, 0, 0,
  0, 2, 24, 4, 8, 2, 8, 4, 0, 0, 0, 0, 3, 13, 18, 4, 12, 13, 9, 4, 0, 0, 0, 0,
  9, 7, 10, 4, 9, 7, 5, 4, 0, 0, 0, 0, 5, 8, 12, 3, 11, 8, 6, 3, 0, 0, 0, 0,
  4, 14, 19, 3, 4, 15, 19, 1, 0, 0, 0, 0, 10, 0, 4, 20, 10, 10, 4, 10, 0, 0, 0, 0,
  8, 15, 9, 6, 8, 17, 9, 2, 0, 0, 0, 0, 2, 9, 15, 4, 7, 9, 5, 4, 0, 0, 0, 0,
  8, 4, 12, 7, 12, 4, 4, 7, 0, 0, 0, 0, 0, 10, 6, 9, 0, 13, 6, 3, 0, 0, 0, 0,
  18, 5, 6, 9, 18, 8, 6, 3, 0, 0, 0, 0, 0, 18, 16, 6, 0, 18, 8, 3, 8, 21, 8, 3,
  9, 18, 14, 6, 16, 18, 7, 3, 9, 21, 7, 3, 1, 20, 20, 4, 1, 20, 10, 2, 11, 22, 10, 2,
  2, 8, 20, 6, 12, 8, 10, 3, 2, 11, 10, 3, 7, 8, 6, 9, 9, 8, 2, 9, 0, 0, 0, 0,
  8, 5, 12, 8, 12, 5, 4, 8, 0, 0, 0, 0, 4, 5, 12, 8, 8, 5, 4, 8, 0, 0, 0, 0,
  10, 6, 6, 9, 12, 6, 2, 9, 0, 0, 0, 0, 2, 0, 6, 16, 4, 0, 2, 16, 0, 0, 0, 0,
  15, 4, 6, 12, 15, 8, 6, 4, 0, 0, 0, 0, 3, 4, 6, 12, 3, 8, 6, 4, 0, 0, 0, 0,
  15, 12, 9, 6, 15, 14, 9, 2, 0, 0, 0, 0, 4, 0, 15, 22, 4, 11, 15, 11, 0, 0, 0, 0,
  15, 12, 9, 6, 15, 14, 9, 2, 0, 0, 0, 0, 0, 12, 9, 6, 0, 14, 9, 2, 0, 0, 0, 0,
  15, 15, 9, 6, 15, 17, 9, 2, 0, 0, 0, 0, 0, 15, 9, 6, 0, 17, 9, 2, 0, 0, 0, 0,
  10, 0, 8, 10, 14, 0, 4, 5, 10, 5, 4, 5, 1, 0, 4, 16, 3, 0, 2, 16, 0, 0, 0, 0,
  7, 6, 10, 6, 7, 8, 10, 2, 0, 0, 0, 0, 10, 12, 4, 10, 10, 17, 4, 5, 0, 0, 0, 0,
  8, 4, 10, 6, 8, 6, 10, 2, 0, 0, 0, 0, 3, 22, 18, 2, 12, 22, 9, 2, 0, 0, 0, 0,
  7, 7, 11, 6, 7, 9, 11, 2, 0, 0, 0, 0, 0, 0, 12, 10, 0, 0, 6, 5, 6, 5, 6, 5,
  10, 1, 12, 6, 16, 1, 6, 3, 10, 4, 6, 3, 7, 16, 9, 4, 7, 18, 9, 2, 0, 0, 0, 0,
  5, 7, 15, 16, 10, 7, 5, 16, 0, 0, 0, 0, 5, 10, 12, 13, 11, 10, 6, 13, 0, 0, 0, 0,
  6, 2, 12, 6, 12, 2, 6, 3, 6, 5, 6, 3, 3, 9, 12, 9, 3, 12, 12, 3, 0, 0, 0, 0,
  16, 2, 8, 6, 16, 5, 8, 3, 0, 0, 0, 0, 0, 2, 8, 6, 0, 5, 8, 3, 0, 0, 0, 0,
  0, 3, 24, 11, 0, 3, 12, 11, 0, 0, 0, 0, 0, 13, 8, 10, 0, 13, 4, 5, 4, 18, 4, 5,
  10, 14, 4, 10, 10, 19, 4, 5, 0, 0, 0, 0, 10, 2, 4, 21, 10, 9, 4, 7, 0, 0, 0, 0,
  4, 4, 15, 9, 4, 7, 15, 3, 0, 0, 0, 0, 0, 1, 24, 6, 8, 1, 8, 6, 0, 0, 0, 0,
  9, 6, 5, 16, 9, 14, 5, 8, 0, 0, 0, 0, 3, 21, 18, 3, 9, 21, 6, 3, 0, 0, 0, 0,
  6, 5, 3, 12, 6, 11, 3, 6, 0, 0, 0, 0, 11, 6, 4, 9, 11, 6, 2, 9, 0, 0, 0, 0,
  5, 6, 9, 8, 8, 6, 3, 8, 0, 0, 0, 0, 4, 3, 20, 2, 4, 4, 20, 1, 0, 0, 0, 0,
  2, 10, 18, 3, 8, 10, 6, 3, 0, 0, 0, 0, 7, 15, 10, 6, 7, 17, 10, 2, 0, 0, 0, 0,
  1, 4, 4, 18, 1, 4, 2, 9, 3, 13, 2, 9, 13, 0, 6, 9, 15, 0, 2, 9, 0, 0, 0, 0,
  5, 0, 6, 9, 7, 0, 2, 9, 0, 0, 0, 0, 11, 0, 6, 9, 13, 0, 2, 9, 0, 0, 0, 0,
  6, 7, 9, 6, 9, 7, 3, 6, 0, 0, 0, 0, 3, 0, 18, 2, 3, 1, 18, 1, 0, 0, 0, 0,
  0, 10, 20, 4, 0, 10, 10, 2, 10, 12, 10, 2, 10, 2, 4, 12, 10, 8, 4, 6, 0, 0, 0, 0,
  6, 5, 6, 12, 6, 5, 3, 6, 9, 11, 3, 6, 6, 0, 18, 22, 15, 0, 9, 11, 6, 11, 9, 11,
  0, 0, 18, 22, 0, 0, 9, 11, 9, 11, 9, 11, 18, 2, 6, 11, 20, 2, 2, 11, 0, 0, 0, 0,
  0, 2, 6, 11, 2, 2, 2, 11, 0, 0, 0, 0, 11, 0, 6, 9, 13, 0, 2, 9, 0, 0, 0, 0,
  0, 0, 20, 3, 0, 1, 20, 1, 0, 0, 0, 0, 2, 2, 20, 2, 2, 3, 20, 1, 0, 0, 0, 0,
  1, 10, 18, 2, 1, 11, 18, 1, 0, 0, 0, 0, 18, 7, 6, 9, 18, 10, 6, 3, 0, 0, 0, 0,
  0, 0, 22, 9, 0, 3, 22, 3, 0, 0, 0, 0, 17, 3, 6, 9, 17, 6, 6, 3, 0, 0, 0, 0,
  0, 7, 6, 9, 0, 10, 6, 3, 0, 0, 0, 0, 0, 6, 24, 6, 0, 8, 24, 2, 0, 0, 0, 0,
  0, 2, 6, 10, 2, 2, 2, 10, 0, 0, 0, 0, 10, 6, 6, 9, 12, 6, 2, 9, 0, 0, 0, 0,
  7, 0, 6, 9, 9, 0, 2, 9, 0, 0, 0, 0, 15, 0, 6, 9, 17, 0, 2, 9, 0, 0, 0, 0,
  3, 0, 6, 9, 5, 0, 2, 9, 0, 0, 0, 0, 15, 17, 9, 6, 15, 19, 9, 2, 0, 0, 0, 0,
  0, 17, 18, 3, 0, 18, 18, 1, 0, 0, 0, 0, 15, 14, 9, 6, 15, 16, 9, 2, 0, 0, 0, 0,
  0, 15, 23, 6, 0, 17, 23, 2, 0, 0, 0, 0, 5, 15, 18, 3, 5, 16, 18, 1, 0, 0, 0, 0,
  0, 14, 9, 6, 0, 16, 9, 2, 0, 0, 0, 0, 9, 8, 8, 10, 13, 8, 4, 5, 9, 13, 4, 5,
  3, 7, 15, 6, 8, 7, 5, 6, 0, 0, 0, 0, 9, 8, 8, 10, 13, 8, 4, 5, 9, 13, 4, 5,
  5, 0, 6, 12, 8, 0, 3, 12, 0, 0, 0, 0, 9, 8, 8, 10, 13, 8, 4, 5, 9, 13, 4, 5,
  8, 5, 6, 9, 10, 5, 2, 9, 0, 0, 0, 0, 10, 6, 4, 18, 12, 6, 2, 9, 10, 15, 2, 9,
  5, 7, 12, 4, 11, 7, 6, 4, 0, 0, 0, 0, 9, 8, 8, 10, 13, 8, 4, 5, 9, 13, 4, 5,
  7, 8, 8, 10, 7, 8, 4, 5, 11, 13, 4, 5, 11, 10, 6, 14, 14, 10, 3, 7, 11, 17, 3, 7,
  9, 5, 6, 19, 12, 5, 3, 19, 0, 0, 0, 0, 6, 12, 12, 6, 12, 12, 6, 3, 6, 15, 6, 3,
  1, 9, 18, 6, 1, 9, 9, 3, 10, 12, 9, 3, 16, 14, 8, 10, 20, 14, 4, 5, 16, 19, 4, 5,
  0, 9, 22, 8, 0, 9, 11, 4, 11, 13, 11, 4, 8, 18, 12, 6, 14, 18, 6, 3, 8, 21, 6, 3,
  0, 6, 20, 18, 0, 6, 10, 9, 10, 15, 10, 9, 3, 6, 20, 12, 13, 6, 10, 6, 3, 12, 10, 6,
  0, 16, 10, 8, 0, 16, 5, 4, 5, 20, 5, 4, 6, 16, 18, 3, 6, 17, 18, 1, 0, 0, 0, 0,
  0, 11, 19, 3, 0, 12, 19, 1, 0, 0, 0, 0, 14, 6, 6, 9, 14, 9, 6, 3, 0, 0, 0, 0,
  1, 7, 22, 4, 1, 7, 11, 2, 12, 9, 11, 2, 13, 6, 7, 12, 13, 10, 7, 4, 0, 0, 0, 0,
  4, 7, 11, 9, 4, 10, 11, 3, 0, 0, 0, 0, 12, 10, 10, 8, 17, 10, 5, 4, 12, 14, 5, 4,
  2, 12, 9, 7, 5, 12, 3, 7, 0, 0, 0, 0, 16, 14, 6, 9, 16, 17, 6, 3, 0, 0, 0, 0,
  3, 12, 6, 12, 3, 16, 6, 4, 0, 0, 0, 0, 14, 13, 6, 6, 14, 16, 6, 3, 0, 0, 0, 0,
  8, 0, 6, 9, 10, 0, 2, 9, 0, 0, 0, 0, 9, 1, 6, 23, 11, 1, 2, 23, 0, 0, 0, 0,
  0, 16, 9, 6, 0, 18, 9, 2, 0, 0, 0, 0, 4, 17, 18, 3, 4, 18, 18, 1, 0, 0, 0, 0,
  5, 2, 13, 14, 5, 9, 13, 7, 0, 0, 0, 0, 15, 0, 8, 12, 19, 0, 4, 6, 15, 6, 4, 6,
  0, 0, 8, 12, 0, 0, 4, 6, 4, 6, 4, 6, 8, 2, 8, 7, 8, 2, 4, 7, 0, 0, 0, 0,
  1, 1, 6, 9, 3, 1, 2, 9, 0, 0, 0, 0, 14, 8, 6, 12, 17, 8, 3, 6, 14, 14, 3, 6,
  4, 8, 6, 12, 4, 8, 3, 6, 7, 14, 3, 6, 16, 5, 5, 15, 16, 10, 5, 5, 0, 0, 0, 0,
  3, 5, 5, 15, 3, 10, 5, 5, 0, 0, 0, 0, 18, 4, 6, 9, 18, 7, 6, 3, 0, 0, 0, 0,
  1, 7, 6, 15, 1, 12, 6, 5, 0, 0, 0, 0, 11, 15, 12, 8, 17, 15, 6, 4, 11, 19, 6, 4,
  0, 2, 24, 4, 0, 2, 12, 2, 12, 4, 12, 2, 15, 1, 2, 19, 15, 1, 1, 19, 0, 0, 0, 0,
  7, 1, 2, 19, 8, 1, 1, 19, 0, 0, 0, 0, 22, 1, 2, 20, 22, 1, 1, 20, 0, 0, 0, 0,
  0, 1, 2, 20, 1, 1, 1, 20, 0, 0, 0, 0, 18, 11, 6, 12, 20, 11, 2, 12, 0, 0, 0, 0,
  0, 11, 6, 12, 2, 11, 2, 12, 0, 0, 0, 0, 3, 6, 18, 14, 3, 13, 18, 7, 0, 0, 0, 0,
  6, 10, 7, 8, 6, 14, 7, 4, 0, 0, 0, 0, 7, 9, 12, 12, 7, 13, 12, 4, 0, 0, 0, 0,
  2, 18, 18, 5, 11, 18, 9, 5, 0, 0, 0, 0, 4, 21, 20, 3, 4, 22, 20, 1, 0, 0, 0, 0,
  9, 12, 6, 12, 9, 12, 3, 6, 12, 18, 3, 6, 4, 6, 18, 3, 4, 7, 18, 1, 0, 0, 0, 0,
  3, 6, 18, 3, 3, 7, 18, 1, 0, 0, 0, 0, 18, 4, 6, 9, 18, 7, 6, 3, 0, 0, 0, 0,
  2, 12, 9, 6, 2, 14, 9, 2, 0, 0, 0, 0, 4, 14, 18, 4, 13, 14, 9, 2, 4, 16, 9, 2,
  7, 7, 6, 14, 7, 7, 3, 7, 10, 14, 3, 7, 7, 13, 12, 6, 13, 13, 6, 3, 7, 16, 6, 3,
  6, 7, 12, 9, 10, 7, 4, 9, 0, 0, 0, 0, 12, 12, 6, 6, 12, 12, 3, 6, 0, 0, 0, 0,
  0, 2, 4, 10, 0, 7, 4, 5, 0, 0, 0, 0, 8, 0, 9, 6, 11, 0, 3, 6, 0, 0, 0, 0,
  2, 9, 12, 6, 2, 12, 12, 3, 0, 0, 0, 0, 13, 10, 6, 9, 13, 13, 6, 3, 0, 0, 0, 0,
  5, 10, 6, 9, 5, 13, 6, 3, 0, 0, 0, 0, 9, 15, 9, 6, 9, 17, 9, 2, 0, 0, 0, 0,
  5, 16, 12, 6, 5, 19, 12, 3, 0, 0, 0, 0, 3, 2, 20, 3, 3, 3, 20, 1, 0, 0, 0, 0,
  2, 5, 12, 6, 6, 5, 4, 6, 0, 0, 0, 0, 11, 0, 3, 24, 12, 0, 1, 24, 0, 0, 0, 0,
  3, 16, 15, 4, 8, 16, 5, 4, 0, 0, 0, 0, 9, 12, 6, 12, 9, 18, 6, 6, 0, 0, 0, 0,
  1, 15, 12, 8, 1, 15, 6, 4, 7, 19, 6, 4, 15, 10, 8, 14, 19, 10, 4, 7, 15, 17, 4, 7,
  1, 9, 8, 14, 1, 9, 4, 7, 5, 16, 4, 7, 9, 11, 9, 10, 9, 16, 9, 5, 0, 0, 0, 0,
  6, 7, 12, 6, 6, 9, 12, 2, 0, 0, 0, 0, 10, 15, 6, 9, 12, 15, 2, 9, 0, 0, 0, 0,
  7, 8, 9, 7, 10, 8, 3, 7, 0, 0, 0, 0, 10, 4, 8, 10, 14, 4, 4, 5, 10, 9, 4, 5,
  4, 6, 6, 9, 4, 9, 6, 3, 0, 0, 0, 0, 0, 6, 24, 12, 8, 6, 8, 12, 0, 0, 0, 0,
  3, 7, 6, 14, 6, 7, 3, 14, 0, 0, 0, 0, 19, 8, 5, 8, 19, 12, 5, 4, 0, 0, 0, 0,
  0, 8, 5, 8, 0, 12, 5, 4, 0, 0, 0, 0, 17, 3, 6, 6, 17, 6, 6, 3, 0, 0, 0, 0,
  1, 3, 6, 6, 1, 6, 6, 3, 0, 0, 0, 0, 18, 2, 6, 9, 18, 5, 6, 3, 0, 0, 0, 0,
  0, 2, 6, 9, 0, 5, 6, 3, 0, 0, 0, 0, 3, 3, 18, 6, 3, 5, 18, 2, 0, 0, 0, 0,
  2, 3, 9, 6, 2, 5, 9, 2, 0, 0, 0, 0, 9, 3, 10, 8, 14, 3, 5, 4, 9, 7, 5, 4,
  5, 3, 10, 8, 5, 3, 5, 4, 10, 7, 5, 4, 10, 11, 6, 12, 10, 11, 3, 12, 0, 0, 0, 0,
  8, 11, 6, 11, 11, 11, 3, 11, 0, 0, 0, 0, 7, 8, 10, 4, 7, 8, 5, 4, 0, 0, 0, 0,
  9, 6, 6, 7, 12, 6, 3, 7, 0, 0, 0, 0, 5, 18, 18, 3, 5, 19, 18, 1, 0, 0, 0, 0,
  8, 4, 6, 9, 10, 4, 2, 9, 0, 0, 0, 0, 8, 1, 9, 7, 11, 1, 3, 7, 0, 0, 0, 0,
  6, 11, 6, 6, 9, 11, 3, 6, 0, 0, 0, 0, 14, 12, 4, 11, 14, 12, 2, 11, 0, 0, 0, 0,
  6, 12, 4, 11, 8, 12, 2, 11, 0, 0, 0, 0, 8, 0, 12, 18, 12, 0, 4, 18, 0, 0, 0, 0,
  2, 12, 10, 5, 7, 12, 5, 5, 0, 0, 0, 0, 2, 20, 22, 3, 2, 21, 22, 1, 0, 0, 0, 0,
  0, 4, 2, 20, 1, 4, 1, 20, 0, 0, 0, 0, 0, 2, 24, 4, 8, 2, 8, 4, 0, 0, 0, 0,
  7, 8, 10, 4, 7, 10, 10, 2, 0, 0, 0, 0, 6, 7, 8, 10, 6, 7, 4, 5, 10, 12, 4, 5,
  14, 0, 6, 14, 17, 0, 3, 7, 14, 7, 3, 7, 4, 11, 5, 8, 4, 15, 5, 4, 0, 0, 0, 0,
  2, 0, 20, 9, 2, 3, 20, 3, 0, 0, 0, 0, 6, 7, 12, 8, 6, 7, 6, 4, 12, 11, 6, 4,
  9, 17, 6, 6, 9, 20, 6, 3, 0, 0, 0, 0, 7, 10, 10, 4, 7, 12, 10, 2, 0, 0, 0, 0,
  6, 5, 12, 9, 10, 5, 4, 9, 0, 0, 0, 0, 5, 11, 6, 8, 8, 11, 3, 8, 0, 0, 0, 0,
  18, 4, 4, 17, 18, 4, 2, 17, 0, 0, 0, 0, 0, 0, 6, 6, 3, 0, 3, 6, 0, 0, 0, 0,
  18, 4, 4, 17, 18, 4, 2, 17, 0, 0, 0, 0, 2, 4, 4, 17, 4, 4, 2, 17, 0, 0, 0, 0,
  5, 18, 19, 3, 5, 19, 19, 1, 0, 0, 0, 0, 11, 0, 2, 18, 11, 9, 2, 9, 0, 0, 0, 0,
  15, 4, 2, 18, 15, 13, 2, 9, 0, 0, 0, 0, 7, 4, 2, 18, 7, 13, 2, 9, 0, 0, 0, 0,
  7, 11, 10, 8, 12, 11, 5, 4, 7, 15, 5, 4, 10, 6, 4, 9, 12, 6, 2, 9, 0, 0, 0, 0,
  10, 0, 6, 9, 12, 0, 2, 9, 0, 0, 0, 0, 2, 9, 16, 8, 2, 9, 8, 4, 10, 13, 8, 4,
  14, 15, 6, 9, 14, 18, 6, 3, 0, 0, 0, 0, 8, 7, 6, 9, 10, 7, 2, 9, 0, 0, 0, 0,
  14, 15, 6, 9, 14, 18, 6, 3, 0, 0, 0, 0, 3, 12, 12, 6, 3, 14, 12, 2, 0, 0, 0, 0,
  14, 12, 9, 6, 14, 14, 9, 2, 0, 0, 0, 0, 1, 12, 9, 6, 1, 14, 9, 2, 0, 0, 0, 0,
  3, 7, 18, 3, 3, 8, 18, 1, 0, 0, 0, 0, 1, 7, 22, 6, 1, 9, 22, 2, 0, 0, 0, 0,
  18, 4, 6, 6, 18, 7, 6, 3, 0, 0, 0, 0, 0, 4, 6, 6, 0, 7, 6, 3, 0, 0, 0, 0,
  5, 11, 16, 6, 5, 14, 16, 3, 0, 0, 0, 0, 6, 16, 9, 4, 6, 18, 9, 2, 0, 0, 0, 0,
  14, 15, 6, 9, 14, 18, 6, 3, 0, 0, 0, 0, 4, 15, 6, 9, 4, 18, 6, 3, 0, 0, 0, 0,
  15, 1, 6, 23, 17, 1, 2, 23, 0, 0, 0, 0, 0, 21, 24, 3, 8, 21, 8, 3, 0, 0, 0, 0,
  0, 20, 24, 4, 8, 20, 8, 4, 0, 0, 0, 0, 3, 1, 6, 23, 5, 1, 2, 23, 0, 0, 0, 0,
  3, 17, 18, 3, 3, 18, 18, 1, 0, 0, 0, 0, 0, 16, 18, 3, 0, 17, 18, 1, 0, 0, 0, 0,
  1, 16, 22, 4, 12, 16, 11, 2, 1, 18, 11, 2, 0, 16, 9, 6, 0, 18, 9, 2, 0, 0, 0, 0,
  2, 10, 21, 3, 9, 10, 7, 3, 0, 0, 0, 0, 2, 18, 12, 6, 2, 18, 6, 3, 8, 21, 6, 3,
  0, 5, 24, 4, 0, 7, 24, 2, 0, 0, 0, 0, 10, 2, 4, 15, 10, 7, 4, 5, 0, 0, 0, 0,
  10, 7, 6, 12, 10, 13, 6, 6, 0, 0, 0, 0, 6, 6, 6, 9, 8, 6, 2, 9, 0, 0, 0, 0,
  11, 0, 6, 9, 13, 0, 2, 9, 0, 0, 0, 0, 9, 7, 6, 9, 11, 7, 2, 9, 0, 0, 0, 0,
  2, 1, 20, 3, 2, 2, 20, 1, 0, 0, 0, 0, 1, 18, 12, 6, 1, 18, 6, 3, 7, 21, 6, 3,
  13, 2, 4, 13, 13, 2, 2, 13, 0, 0, 0, 0, 6, 7, 12, 4, 12, 7, 6, 4, 0, 0, 0, 0,
  10, 1, 4, 13, 10, 1, 2, 13, 0, 0, 0, 0, 6, 0, 3, 18, 7, 0, 1, 18, 0, 0, 0, 0,
  14, 3, 10, 5, 14, 3, 5, 5, 0, 0, 0, 0, 6, 15, 12, 8, 10, 15, 4, 8, 0, 0, 0, 0,
  9, 10, 6, 9, 11, 10, 2, 9, 0, 0, 0, 0, 8, 3, 4, 9, 10, 3, 2, 9, 0, 0, 0, 0,
  17, 0, 6, 14, 20, 0, 3, 7, 17, 7, 3, 7, 1, 0, 6, 14, 1, 0, 3, 7, 4, 7, 3, 7,
  14, 0, 6, 16, 17, 0, 3, 8, 14, 8, 3, 8, 7, 4, 4, 10, 9, 4, 2, 10, 0, 0, 0, 0,
  3, 17, 18, 6, 12, 17, 9, 3, 3, 20, 9, 3, 1, 20, 22, 4, 12, 20, 11, 4, 0, 0, 0, 0,
  14, 3, 10, 5, 14, 3, 5, 5, 0, 0, 0, 0, 0, 3, 10, 5, 5, 3, 5, 5, 0, 0, 0, 0,
  12, 6, 12, 16, 16, 6, 4, 16, 0, 0, 0, 0, 0, 6, 12, 16, 4, 6, 4, 16, 0, 0, 0, 0,
  10, 9, 5, 15, 10, 14, 5, 5, 0, 0, 0, 0, 1, 18, 21, 2, 1, 19, 21, 1, 0, 0, 0, 0,
  15, 0, 9, 6, 15, 2, 9, 2, 0, 0, 0, 0, 6, 1, 12, 4, 12, 1, 6, 4, 0, 0, 0, 0,
  6, 0, 12, 12, 12, 0, 6, 6, 6, 6, 6, 6, 8, 10, 8, 12, 8, 10, 4, 6, 12, 16, 4, 6,
  14, 16, 10, 8, 19, 16, 5, 4, 14, 20, 5, 4, 0, 16, 10, 8, 0, 16, 5, 4, 5, 20, 5, 4,
  10, 12, 12, 5, 14, 12, 4, 5, 0, 0, 0, 0, 6, 16, 10, 8, 6, 16, 5, 4, 11, 20, 5, 4,
  7, 6, 12, 6, 13, 6, 6, 3, 7, 9, 6, 3, 9, 6, 4, 18, 9, 6, 2, 9, 11, 15, 2, 9,
  10, 9, 6, 14, 13, 9, 3, 7, 10, 16, 3, 7, 8, 9, 6, 14, 8, 9, 3, 7, 11, 16, 3, 7,
  7, 4, 11, 12, 7, 10, 11, 6, 0, 0, 0, 0, 4, 8, 6, 16, 4, 8, 3, 8, 7, 16, 3, 8,
  17, 3, 4, 21, 17, 10, 4, 7, 0, 0, 0, 0, 3, 3, 4, 21, 3, 10, 4, 7, 0, 0, 0, 0,
  10, 1, 8, 18, 14, 1, 4, 9, 10, 10, 4, 9, 2, 5, 16, 8, 2, 5, 8, 4, 10, 9, 8, 4,
  3, 6, 18, 12, 3, 10, 18, 4, 0, 0, 0, 0, 4, 10, 16, 12, 4, 14, 16, 4, 0, 0, 0, 0,
  15, 4, 8, 20, 19, 4, 4, 10, 15, 14, 4, 10, 7, 2, 9, 6, 10, 2, 3, 6, 0, 0, 0, 0,
  15, 4, 8, 20, 19, 4, 4, 10, 15, 14, 4, 10, 1, 4, 8, 20, 1, 4, 4, 10, 5, 14, 4, 10,
  11, 8, 8, 14, 15, 8, 4, 7, 11, 15, 4, 7, 5, 8, 8, 14, 5, 8, 4, 7, 9, 15, 4, 7,
  10, 13, 5, 8, 10, 17, 5, 4, 0, 0, 0, 0, 4, 13, 7, 9, 4, 16, 7, 3, 0, 0, 0, 0,
  0, 13, 24, 10, 0, 18, 24, 5, 0, 0, 0, 0, 4, 2, 8, 11, 8, 2, 4, 11, 0, 0, 0, 0,
  10, 2, 8, 16, 14, 2, 4, 8, 10, 10, 4, 8, 0, 2, 24, 6, 0, 2, 12, 3, 12, 5, 12, 3,
  6, 0, 12, 9, 6, 3, 12, 3, 0, 0, 0, 0, 1, 2, 12, 12, 1, 2, 6, 6, 7, 8, 6, 6,
  18, 5, 6, 9, 18, 8, 6, 3, 0, 0, 0, 0, 4, 3, 8, 10, 4, 3, 4, 5, 8, 8, 4, 5,
  6, 21, 18, 3, 6, 22, 18, 1, 0, 0, 0, 0, 1, 10, 18, 2, 1, 11, 18, 1, 0, 0, 0, 0,
  1, 10, 22, 3, 1, 11, 22, 1, 0, 0, 0, 0, 2, 8, 12, 9, 2, 11, 12, 3, 0, 0, 0, 0,
  12, 8, 12, 6, 18, 8, 6, 3, 12, 11, 6, 3, 0, 8, 12, 6, 0, 8, 6, 3, 6, 11, 6, 3,
  10, 15, 6, 9, 12, 15, 2, 9, 0, 0, 0, 0, 7, 13, 9, 6, 7, 15, 9, 2, 0, 0, 0, 0,
  9, 8, 7, 12, 9, 14, 7, 6, 0, 0, 0, 0, 4, 13, 9, 6, 7, 13, 3, 6, 0, 0, 0, 0,
  6, 15, 18, 4, 12, 15, 6, 4, 0, 0, 0, 0, 5, 4, 4, 16, 7, 4, 2, 16, 0, 0, 0, 0,
  10, 15, 6, 9, 12, 15, 2, 9, 0, 0, 0, 0, 8, 15, 6, 9, 10, 15, 2, 9, 0, 0, 0, 0,
  9, 11, 12, 10, 15, 11, 6, 5, 9, 16, 6, 5, 3, 6, 14, 6, 3, 8, 14, 2, 0, 0, 0, 0,
  4, 2, 17, 8, 4, 6, 17, 4, 0, 0, 0, 0, 6, 2, 12, 21, 6, 9, 12, 7, 0, 0, 0, 0,
  8, 1, 9, 9, 8, 4, 9, 3, 0, 0, 0, 0, 0, 7, 24, 3, 12, 7, 12, 3, 0, 0, 0, 0,
  11, 6, 9, 10, 11, 11, 9, 5, 0, 0, 0, 0, 2, 11, 18, 3, 2, 12, 18, 1, 0, 0, 0, 0,
  8, 16, 9, 4, 8, 18, 9, 2, 0, 0, 0, 0, 0, 0, 9, 6, 0, 2, 9, 2, 0, 0, 0, 0,
  0, 11, 24, 6, 0, 13, 24, 2, 0, 0, 0, 0, 2, 9, 20, 6, 2, 12, 20, 3, 0, 0, 0, 0,
  4, 5, 16, 12, 12, 5, 8, 6, 4, 11, 8, 6, 10, 2, 4, 15, 10, 7, 4, 5, 0, 0, 0, 0,
  7, 3, 10, 4, 7, 5, 10, 2, 0, 0, 0, 0, 9, 15, 6, 8, 9, 19, 6, 4, 0, 0, 0, 0,
  17, 0, 7, 10, 17, 5, 7, 5, 0, 0, 0, 0, 0, 0, 7, 10, 0, 5, 7, 5, 0, 0, 0, 0,
  16, 1, 6, 12, 19, 1, 3, 6, 16, 7, 3, 6, 1, 0, 19, 8, 1, 4, 19, 4, 0, 0, 0, 0,
  12, 2, 9, 4, 12, 4, 9, 2, 0, 0, 0, 0, 3, 2, 9, 4, 3, 4, 9, 2, 0, 0, 0, 0,
  12, 2, 10, 6, 12, 4, 10, 2, 0, 0, 0, 0, 3, 4, 18, 2, 12, 4, 9, 2, 0, 0, 0, 0,
  12, 1, 4, 9, 12, 1, 2, 9, 0, 0, 0, 0, 8, 1, 4, 9, 10, 1, 2, 9, 0, 0, 0, 0,
  10, 5, 8, 10, 14, 5, 4, 5, 10, 10, 4, 5, 6, 4, 12, 13, 10, 4, 4, 13, 0, 0, 0, 0,
  13, 5, 6, 6, 13, 5, 3, 6, 0, 0, 0, 0, 1, 5, 12, 3, 7, 5, 6, 3, 0, 0, 0, 0,
  7, 5, 10, 6, 7, 7, 10, 2, 0, 0, 0, 0, 2, 0, 21, 5, 9, 0, 7, 5, 0, 0, 0, 0,
  0, 8, 9, 9, 0, 11, 9, 3, 0, 0, 0, 0, 9, 6, 6, 9, 11, 6, 2, 9, 0, 0, 0, 0,
  0, 3, 6, 7, 3, 3, 3, 7, 0, 0, 0, 0, 9, 18, 12, 6, 15, 18, 6, 3, 9, 21, 6, 3,
  2, 8, 20, 6, 2, 8, 10, 3, 12, 11, 10, 3, 13, 2, 10, 4, 13, 4, 10, 2, 0, 0, 0, 0,
  4, 5, 5, 18, 4, 11, 5, 6, 0, 0, 0, 0, 20, 4, 4, 9, 20, 4, 2, 9, 0, 0, 0, 0,
  8, 6, 8, 14, 8, 13, 8, 7, 0, 0, 0, 0, 0, 1, 24, 6, 12, 1, 12, 3, 0, 4, 12, 3,
  0, 4, 4, 9, 2, 4, 2, 9, 0, 0, 0, 0, 3, 6, 18, 3, 3, 7, 18, 1, 0, 0, 0, 0,
  3, 17, 16, 6, 3, 19, 16, 2, 0, 0, 0, 0, 13, 6, 6, 9, 13, 9, 6, 3, 0, 0, 0, 0,
  5, 6, 14, 6, 5, 6, 7, 3, 12, 9, 7, 3, 13, 5, 8, 10, 17, 5, 4, 5, 13, 10, 4, 5,
  2, 2, 20, 3, 2, 3, 20, 1, 0, 0, 0, 0, 9, 2, 9, 6, 12, 2, 3, 6, 0, 0, 0, 0,
  8, 6, 6, 9, 10, 6, 2, 9, 0, 0, 0, 0, 12, 3, 4, 11, 12, 3, 2, 11, 0, 0, 0, 0,
  8, 3, 4, 11, 10, 3, 2, 11, 0, 0, 0, 0, 8, 3, 8, 10, 12, 3, 4, 5, 8, 8, 4, 5,
  11, 1, 2, 18, 12, 1, 1, 18, 0, 0, 0, 0, 9, 2, 9, 6, 12, 2, 3, 6, 0, 0, 0, 0,
  0, 2, 19, 3, 0, 3, 19, 1, 0, 0, 0, 0, 9, 14, 9, 6, 9, 16, 9, 2, 0, 0, 0, 0,
  1, 8, 18, 5, 7, 8, 6, 5, 0, 0, 0, 0, 12, 0, 6, 9, 14, 0, 2, 9, 0, 0, 0, 0,
  6, 0, 6, 9, 8, 0, 2, 9, 0, 0, 0, 0, 13, 6, 4, 15, 13, 11, 4, 5, 0, 0, 0, 0,
  1, 5, 18, 3, 1, 6, 18, 1, 0, 0, 0, 0, 9, 7, 14, 6, 9, 9, 14, 2, 0, 0, 0, 0,
  2, 16, 18, 3, 2, 17, 18, 1, 0, 0, 0, 0, 15, 17, 9, 6, 15, 19, 9, 2, 0, 0, 0, 0,
  0, 8, 12, 6, 0, 8, 6, 3, 6, 11, 6, 3, 9, 13, 7, 8, 9, 17, 7, 4, 0, 0, 0, 0,
  2, 17, 20, 3, 2, 18, 20, 1, 0, 0, 0, 0, 15, 17, 9, 6, 15, 19, 9, 2, 0, 0, 0, 0,
  4, 0, 15, 4, 4, 2, 15, 2, 0, 0, 0, 0, 17, 2, 6, 6, 17, 5, 6, 3, 0, 0, 0, 0,
  0, 3, 6, 9, 0, 6, 6, 3, 0, 0, 0, 0, 15, 17, 9, 6, 15, 19, 9, 2, 0, 0, 0, 0,
  0, 17, 9, 6, 0, 19, 9, 2, 0, 0, 0, 0, 9, 18, 12, 6, 15, 18, 6, 3, 9, 21, 6, 3,
  3, 15, 6, 9, 3, 18, 6, 3, 0, 0, 0, 0, 16, 13, 8, 10, 20, 13, 4, 5, 16, 18, 4, 5,
  0, 14, 24, 4, 8, 14, 8, 4, 0, 0, 0, 0, 13, 18, 6, 6, 13, 18, 3, 6, 0, 0, 0, 0,
  0, 13, 8, 10, 0, 13, 4, 5, 4, 18, 4, 5, 0, 14, 24, 6, 0, 17, 24, 3, 0, 0, 0, 0,
  5, 2, 12, 8, 5, 2, 6, 4, 11, 6, 6, 4, 8, 9, 9, 6, 11, 9, 3, 6, 0, 0, 0, 0,
  4, 3, 16, 4, 4, 5, 16, 2, 0, 0, 0, 0, 10, 2, 4, 10, 10, 7, 4, 5, 0, 0, 0, 0,
  8, 4, 5, 8, 8, 8, 5, 4, 0, 0, 0, 0, 11, 5, 9, 12, 11, 9, 9, 4, 0, 0, 0, 0,
  4, 5, 9, 12, 4, 9, 9, 4, 0, 0, 0, 0, 14, 6, 6, 9, 14, 9, 6, 3, 0, 0, 0, 0,
  2, 4, 20, 12, 2, 8, 20, 4, 0, 0, 0, 0, 4, 4, 17, 16, 4, 12, 17, 8, 0, 0, 0, 0,
  8, 7, 7, 6, 8, 10, 7, 3, 0, 0, 0, 0, 1, 9, 23, 2, 1, 10, 23, 1, 0, 0, 0, 0,
  7, 0, 6, 9, 9, 0, 2, 9, 0, 0, 0, 0, 13, 3, 4, 9, 13, 3, 2, 9, 0, 0, 0, 0,
  8, 1, 6, 13, 10, 1, 2, 13, 0, 0, 0, 0, 4, 22, 18, 2, 4, 23, 18, 1, 0, 0, 0, 0,
  3, 10, 9, 6, 6, 10, 3, 6, 0, 0, 0, 0, 14, 0, 2, 24, 14, 0, 1, 24, 0, 0, 0, 0,
  8, 0, 2, 24, 9, 0, 1, 24, 0, 0, 0, 0, 3, 2, 18, 10, 9, 2, 6, 10, 0, 0, 0, 0,
  4, 13, 15, 6, 9, 13, 5, 6, 0, 0, 0, 0, 3, 21, 18, 3, 9, 21, 6, 3, 0, 0, 0, 0,
  9, 1, 4, 11, 11, 1, 2, 11, 0, 0, 0, 0, 9, 7, 10, 4, 9, 7, 5, 4, 0, 0, 0, 0,
  7, 0, 10, 18, 12, 0, 5, 18, 0, 0, 0, 0, 12, 1, 6, 16, 14, 1, 2, 16, 0, 0, 0, 0,
  6, 1, 6, 16, 8, 1, 2, 16, 0, 0, 0, 0, 18, 2, 6, 6, 18, 5, 6, 3, 0, 0, 0, 0,
  3, 5, 18, 2, 3, 6, 18, 1, 0, 0, 0, 0, 18, 2, 6, 6, 18, 5, 6, 3, 0, 0, 0, 0,
  0, 2, 6, 6, 0, 5, 6, 3, 0, 0, 0, 0, 13, 11, 11, 6, 13, 13, 11, 2, 0, 0, 0, 0,
  5, 7, 10, 4, 10, 7, 5, 4, 0, 0, 0, 0, 11, 9, 10, 7, 11, 9, 5, 7, 0, 0, 0, 0,
  3, 9, 10, 7, 8, 9, 5, 7, 0, 0, 0, 0, 16, 4, 6, 6, 16, 4, 3, 6, 0, 0, 0, 0,
  5, 6, 10, 8, 5, 6, 5, 4, 10, 10, 5, 4, 7, 21, 16, 3, 7, 21, 8, 3, 0, 0, 0, 0,
  1, 21, 16, 3, 9, 21, 8, 3, 0, 0, 0, 0, 2, 5, 22, 14, 13, 5, 11, 7, 2, 12, 11, 7,
  3, 10, 8, 10, 3, 10, 4, 5, 7, 15, 4, 5, 17, 0, 6, 12, 20, 0, 3, 6, 17, 6, 3, 6,
  5, 2, 6, 18, 7, 2, 2, 18, 0, 0, 0, 0, 13, 0, 6, 9, 15, 0, 2, 9, 0, 0, 0, 0,
  0, 12, 7, 9, 0, 15, 7, 3, 0, 0, 0, 0, 15, 13, 8, 10, 19, 13, 4, 5, 15, 18, 4, 5,
  1, 0, 6, 12, 1, 0, 3, 6, 4, 6, 3, 6, 12, 1, 3, 12, 12, 7, 3, 6, 0, 0, 0, 0,
  1, 13, 8, 10, 1, 13, 4, 5, 5, 18, 4, 5, 3, 21, 19, 2, 3, 22, 19, 1, 0, 0, 0, 0,
  6, 3, 4, 13, 8, 3, 2, 13, 0, 0, 0, 0, 5, 10, 18, 3, 5, 11, 18, 1, 0, 0, 0, 0,
  9, 3, 5, 12, 9, 7, 5, 4, 0, 0, 0, 0, 11, 2, 4, 15, 11, 7, 4, 5, 0, 0, 0, 0,
  4, 1, 16, 4, 4, 3, 16, 2, 0, 0, 0, 0, 6, 0, 18, 3, 6, 1, 18, 1, 0, 0, 0, 0,
  5, 1, 10, 8, 5, 1, 5, 4, 10, 5, 5, 4, 11, 18, 12, 6, 17, 18, 6, 3, 11, 21, 6, 3,
  5, 15, 12, 3, 11, 15, 6, 3, 0, 0, 0, 0, 1, 10, 22, 4, 1, 10, 11, 4, 0, 0, 0, 0,
  7, 9, 9, 6, 10, 9, 3, 6, 0, 0, 0, 0, 6, 11, 12, 5, 10, 11, 4, 5, 0, 0, 0, 0,
  6, 7, 10, 7, 11, 7, 5, 7, 0, 0, 0, 0, 11, 2, 8, 10, 11, 2, 4, 10, 0, 0, 0, 0,
  5, 2, 8, 10, 9, 2, 4, 10, 0, 0, 0, 0, 6, 4, 18, 6, 15, 4, 9, 3, 6, 7, 9, 3,
  0, 5, 10, 9, 0, 8, 10, 3, 0, 0, 0, 0, 2, 7, 21, 6, 2, 9, 21, 2, 0, 0, 0, 0,
  0, 4, 22, 16, 0, 4, 11, 8, 11, 12, 11, 8, 9, 0, 6, 22, 9, 11, 6, 11, 0, 0, 0, 0,
  9, 1, 3, 12, 9, 7, 3, 6, 0, 0, 0, 0, 12, 0, 12, 18, 18, 0, 6, 9, 12, 9, 6, 9,
  0, 0, 12, 18, 0, 0, 6, 9, 6, 9, 6, 9, 1, 1, 22, 4, 12, 1, 11, 2, 1, 3, 11, 2,
  3, 0, 18, 4, 3, 2, 18, 2, 0, 0, 0, 0, 2, 5, 22, 6, 2, 7, 22, 2, 0, 0, 0, 0,
  5, 0, 6, 9, 5, 3, 6, 3, 0, 0, 0, 0, 10, 14, 6, 9, 12, 14, 2, 9, 0, 0, 0, 0,
  8, 14, 6, 9, 10, 14, 2, 9, 0, 0, 0, 0, 5, 18, 18, 3, 5, 19, 18, 1, 0, 0, 0, 0,
  6, 0, 6, 13, 9, 0, 3, 13, 0, 0, 0, 0, 7, 4, 12, 4, 7, 4, 6, 4, 0, 0, 0, 0,
  5, 2, 12, 6, 9, 2, 4, 6, 0, 0, 0, 0, 4, 1, 18, 3, 4, 2, 18, 1, 0, 0, 0, 0,
  0, 8, 6, 12, 0, 12, 6, 4, 0, 0, 0, 0, 9, 15, 6, 9, 11, 15, 2, 9, 0, 0, 0, 0,
  9, 10, 6, 13, 11, 10, 2, 13, 0, 0, 0, 0, 6, 17, 18, 2, 6, 18, 18, 1, 0, 0, 0, 0,
  9, 4, 6, 9, 11, 4, 2, 9, 0, 0, 0, 0, 10, 0, 6, 9, 12, 0, 2, 9, 0, 0, 0, 0,
  5, 6, 10, 8, 5, 6, 5, 4, 10, 10, 5, 4, 14, 9, 5, 8, 14, 13, 5, 4, 0, 0, 0, 0,
  5, 9, 5, 8, 5, 13, 5, 4, 0, 0, 0, 0, 14, 11, 9, 6, 14, 13, 9, 2, 0, 0, 0, 0,
  0, 2, 23, 15, 0, 7, 23, 5, 0, 0, 0, 0, 16, 0, 8, 12, 16, 6, 8, 6, 0, 0, 0, 0,
  4, 15, 6, 9, 4, 18, 6, 3, 0, 0, 0, 0, 8, 18, 9, 4, 8, 20, 9, 2, 0, 0, 0, 0,
  0, 17, 18, 3, 0, 18, 18, 1, 0, 0, 0, 0, 13, 11, 11, 6, 13, 13, 11, 2, 0, 0, 0, 0,
  0, 11, 11, 6, 0, 13, 11, 2, 0, 0, 0, 0, 0, 9, 24, 6, 12, 9, 12, 3, 0, 12, 12, 3,
  6, 16, 8, 8, 6, 20, 8, 4, 0, 0, 0, 0, 10, 16, 14, 6, 10, 18, 14, 2, 0, 0, 0, 0,
  1, 1, 21, 3, 1, 2, 21, 1, 0, 0, 0, 0, 0, 2, 24, 3, 0, 2, 12, 3, 0, 0, 0, 0,
  2, 15, 8, 5, 6, 15, 4, 5, 0, 0, 0, 0, 2, 11, 21, 3, 9, 11, 7, 3, 0, 0, 0, 0,
  1, 18, 12, 6, 1, 18, 6, 3, 7, 21, 6, 3, 10, 14, 4, 10, 10, 19, 4, 5, 0, 0, 0, 0,
  7, 7, 4, 10, 7, 12, 4, 5, 0, 0, 0, 0, 9, 8, 6, 12, 9, 12, 6, 4, 0, 0, 0, 0,
  7, 1, 9, 6, 10, 1, 3, 6, 0, 0, 0, 0, 3, 14, 19, 2, 3, 15, 19, 1, 0, 0, 0, 0,
  7, 7, 10, 10, 7, 7, 5, 5, 12, 12, 5, 5, 3, 12, 18, 12, 3, 12, 9, 12, 0, 0, 0, 0,
  8, 0, 6, 12, 10, 0, 2, 12, 0, 0, 0, 0, 3, 0, 17, 9, 3, 3, 17, 3, 0, 0, 0, 0,
  6, 0, 12, 11, 10, 0, 4, 11, 0, 0, 0, 0, 1, 0, 6, 13, 4, 0, 3, 13, 0, 0, 0, 0,
  5, 8, 16, 6, 5, 11, 16, 3, 0, 0, 0, 0, 8, 8, 5, 12, 8, 14, 5, 6, 0, 0, 0, 0,
  3, 21, 18, 3, 9, 21, 6, 3, 0, 0, 0, 0, 0, 0, 6, 6, 3, 0, 3, 6, 0, 0, 0, 0,
  2, 0, 20, 3, 2, 1, 20, 1, 0, 0, 0, 0, 4, 6, 15, 10, 9, 6, 5, 10, 0, 0, 0, 0,
  9, 6, 6, 9, 11, 6, 2, 9, 0, 0, 0, 0, 9, 0, 6, 9, 11, 0, 2, 9, 0, 0, 0, 0,
  14, 0, 6, 9, 16, 0, 2, 9, 0, 0, 0, 0, 7, 16, 9, 6, 7, 18, 9, 2, 0, 0, 0, 0,
  14, 0, 6, 9, 16, 0, 2, 9, 0, 0, 0, 0, 4, 0, 6, 9, 6, 0, 2, 9, 0, 0, 0, 0,
  17, 1, 6, 16, 19, 1, 2, 16, 0, 0, 0, 0, 1, 1, 6, 16, 3, 1, 2, 16, 0, 0, 0, 0,
  14, 13, 6, 9, 14, 16, 6, 3, 0, 0, 0, 0, 0, 0, 6, 9, 0, 3, 6, 3, 0, 0, 0, 0,
  9, 5, 6, 6, 9, 5, 3, 6, 0, 0, 0, 0, 3, 10, 9, 6, 6, 10, 3, 6, 0, 0, 0, 0,
  14, 7, 3, 16, 14, 15, 3, 8, 0, 0, 0, 0, 4, 10, 14, 12, 4, 10, 7, 6, 11, 16, 7, 6,
  7, 6, 12, 6, 7, 8, 12, 2, 0, 0, 0, 0, 7, 2, 4, 20, 9, 2, 2, 20, 0, 0, 0, 0,
  14, 13, 6, 9, 14, 16, 6, 3, 0, 0, 0, 0, 10, 6, 4, 9, 12, 6, 2, 9, 0, 0, 0, 0,
  14, 13, 6, 9, 14, 16, 6, 3, 0, 0, 0, 0, 5, 20, 14, 4, 5, 22, 14, 2, 0, 0, 0, 0,
  4, 4, 16, 12, 4, 10, 16, 6, 0, 0, 0, 0, 9, 6, 6, 9, 11, 6, 2, 9, 0, 0, 0, 0,
  3, 0, 21, 4, 3, 2, 21, 2, 0, 0, 0, 0, 4, 13, 6, 9, 4, 16, 6, 3, 0, 0, 0, 0,
  16, 16, 5, 8, 16, 20, 5, 4, 0, 0, 0, 0, 4, 0, 16, 16, 4, 0, 8, 8, 12, 8, 8, 8,
  6, 6, 14, 6, 13, 6, 7, 3, 6, 9, 7, 3, 10, 5, 4, 15, 10, 10, 4, 5, 0, 0, 0, 0,
  9, 15, 12, 8, 15, 15, 6, 4, 9, 19, 6, 4, 6, 7, 12, 4, 12, 7, 6, 4, 0, 0, 0, 0,
  5, 6, 14, 6, 12, 6, 7, 3, 5, 9, 7, 3, 3, 6, 18, 10, 3, 6, 9, 5, 12, 11, 9, 5,
  6, 0, 18, 21, 12, 0, 6, 21, 0, 0, 0, 0, 0, 0, 24, 21, 8, 0, 8, 21, 0, 0, 0, 0,
  6, 18, 18, 3, 6, 19, 18, 1, 0, 0, 0, 0, 0, 15, 9, 6, 0, 17, 9, 2, 0, 0, 0, 0,
  4, 3, 19, 2, 4, 4, 19, 1, 0, 0, 0, 0, 0, 3, 24, 2, 0, 4, 24, 1, 0, 0, 0, 0,
  15, 14, 9, 4, 15, 16, 9, 2, 0, 0, 0, 0, 0, 14, 9, 4, 0, 16, 9, 2, 0, 0, 0, 0,
  6, 15, 18, 2, 6, 16, 18, 1, 0, 0, 0, 0, 3, 17, 18, 3, 3, 18, 18, 1, 0, 0, 0, 0,
  12, 0, 3, 23, 13, 0, 1, 23, 0, 0, 0, 0, 6, 0, 8, 6, 6, 3, 8, 3, 0, 0, 0, 0,
  6, 16, 18, 3, 6, 17, 18, 1, 0, 0, 0, 0, 9, 0, 3, 23, 10, 0, 1, 23, 0, 0, 0, 0,
  10, 7, 4, 10, 10, 12, 4, 5, 0, 0, 0, 0, 7, 8, 10, 12, 7, 12, 10, 4, 0, 0, 0, 0,
  14, 9, 6, 14, 17, 9, 3, 7, 14, 16, 3, 7, 2, 0, 10, 9, 2, 3, 10, 3, 0, 0, 0, 0,
  11, 1, 5, 12, 11, 7, 5, 6, 0, 0, 0, 0, 1, 4, 12, 10, 1, 4, 6, 5, 7, 9, 6, 5,
  15, 1, 9, 4, 15, 3, 9, 2, 0, 0, 0, 0, 1, 2, 8, 10, 1, 2, 4, 5, 5, 7, 4, 5,
  10, 1, 5, 12, 10, 5, 5, 4, 0, 0, 0, 0, 4, 0, 14, 24, 11, 0, 7, 24, 0, 0, 0, 0,
  7, 17, 10, 4, 7, 19, 10, 2, 0, 0, 0, 0, 10, 14, 4, 10, 10, 19, 4, 5, 0, 0, 0, 0,
  13, 15, 6, 9, 15, 15, 2, 9, 0, 0, 0, 0, 3, 21, 18, 3, 3, 22, 18, 1, 0, 0, 0, 0,
  13, 15, 6, 9, 15, 15, 2, 9, 0, 0, 0, 0, 5, 15, 6, 9, 7, 15, 2, 9, 0, 0, 0, 0,
  10, 6, 4, 18, 12, 6, 2, 9, 10, 15, 2, 9, 7, 3, 6, 11, 9, 3, 2, 11, 0, 0, 0, 0,
  15, 1, 9, 4, 15, 3, 9, 2, 0, 0, 0, 0, 5, 4, 14, 8, 5, 8, 14, 4, 0, 0, 0, 0,
  8, 1, 15, 9, 8, 4, 15, 3, 0, 0, 0, 0, 7, 2, 8, 10, 7, 2, 4, 5, 11, 7, 4, 5,
  12, 2, 6, 12, 12, 2, 3, 12, 0, 0, 0, 0, 6, 2, 6, 12, 9, 2, 3, 12, 0, 0, 0, 0,
  7, 7, 12, 4, 7, 7, 6, 4, 0, 0, 0, 0, 6, 3, 12, 10, 10, 3, 4, 10, 0, 0, 0, 0,
  5, 6, 16, 6, 13, 6, 8, 3, 5, 9, 8, 3, 3, 1, 18, 9, 9, 1, 6, 9, 0, 0, 0, 0,
  3, 8, 18, 5, 9, 8, 6, 5, 0, 0, 0, 0, 0, 0, 24, 22, 0, 0, 12, 11, 12, 11, 12, 11,
  14, 16, 9, 6, 14, 18, 9, 2, 0, 0, 0, 0, 0, 16, 24, 8, 0, 20, 24, 4, 0, 0, 0, 0,
  1, 19, 22, 4, 12, 19, 11, 2, 1, 21, 11, 2, 1, 16, 9, 6, 1, 18, 9, 2, 0, 0, 0, 0,
  7, 8, 10, 4, 7, 8, 5, 4, 0, 0, 0, 0, 9, 15, 6, 9, 11, 15, 2, 9, 0, 0, 0, 0,
  10, 18, 12, 6, 16, 18, 6, 3, 10, 21, 6, 3, 2, 18, 12, 6, 2, 18, 6, 3, 8, 21, 6, 3,
  8, 3, 16, 9, 8, 6, 16, 3, 0, 0, 0, 0, 0, 5, 10, 6, 0, 7, 10, 2, 0, 0, 0, 0,
  5, 5, 18, 3, 5, 6, 18, 1, 0, 0, 0, 0, 2, 6, 9, 6, 2, 9, 9, 3, 0, 0, 0, 0,
  14, 2, 10, 9, 14, 5, 10, 3, 0, 0, 0, 0, 3, 6, 18, 3, 3, 7, 18, 1, 0, 0, 0, 0,
  9, 2, 15, 6, 9, 4, 15, 2, 0, 0, 0, 0, 4, 8, 15, 6, 4, 10, 15, 2, 0, 0, 0, 0,
  0, 5, 24, 4, 12, 5, 12, 2, 0, 7, 12, 2, 7, 8, 6, 12, 9, 8, 2, 12, 0, 0, 0, 0,
  11, 0, 6, 9, 13, 0, 2, 9, 0, 0, 0, 0, 0, 12, 6, 12, 0, 12, 3, 6, 3, 18, 3, 6,
  14, 12, 10, 6, 14, 14, 10, 2, 0, 0, 0, 0, 2, 7, 18, 9, 2, 10, 18, 3, 0, 0, 0, 0,
  11, 14, 10, 9, 11, 17, 10, 3, 0, 0, 0, 0, 7, 6, 10, 8, 7, 6, 5, 4, 12, 10, 5, 4,
  6, 6, 14, 6, 13, 6, 7, 3, 6, 9, 7, 3, 4, 13, 9, 7, 7, 13, 3, 7, 0, 0, 0, 0,
  14, 10, 6, 12, 17, 10, 3, 6, 14, 16, 3, 6, 4, 10, 6, 12, 4, 10, 3, 6, 7, 16, 3, 6,
  13, 9, 8, 6, 13, 9, 4, 6, 0, 0, 0, 0, 8, 3, 4, 14, 10, 3, 2, 14, 0, 0, 0, 0,
  17, 0, 3, 18, 18, 0, 1, 18, 0, 0, 0, 0, 4, 12, 16, 12, 12, 12, 8, 12, 0, 0, 0, 0,
  15, 0, 6, 14, 17, 0, 2, 14, 0, 0, 0, 0, 3, 0, 6, 14, 5, 0, 2, 14, 0, 0, 0, 0,
  12, 2, 12, 20, 16, 2, 4, 20, 0, 0, 0, 0, 0, 2, 12, 20, 4, 2, 4, 20, 0, 0, 0, 0,
  16, 0, 6, 17, 18, 0, 2, 17, 0, 0, 0, 0, 2, 0, 6, 17, 4, 0, 2, 17, 0, 0, 0, 0,
  15, 6, 9, 6, 15, 8, 9, 2, 0, 0, 0, 0, 0, 6, 9, 6, 0, 8, 9, 2, 0, 0, 0, 0,
  18, 1, 6, 13, 20, 1, 2, 13, 0, 0, 0, 0, 0, 1, 6, 13, 2, 1, 2, 13, 0, 0, 0, 0,
  16, 0, 4, 9, 16, 0, 2, 9, 0, 0, 0, 0, 5, 10, 12, 7, 9, 10, 4, 7, 0, 0, 0, 0,
  12, 9, 12, 6, 12, 11, 12, 2, 0, 0, 0, 0, 0, 9, 12, 6, 0, 11, 12, 2, 0, 0, 0, 0,
  5, 7, 14, 9, 5, 10, 14, 3, 0, 0, 0, 0, 0, 15, 20, 3, 0, 16, 20, 1, 0, 0, 0, 0,
  8, 10, 8, 10, 12, 10, 4, 5, 8, 15, 4, 5, 5, 4, 13, 9, 5, 7, 13, 3, 0, 0, 0, 0,
  10, 2, 6, 18, 10, 8, 6, 6, 0, 0, 0, 0, 6, 0, 6, 9, 8, 0, 2, 9, 0, 0, 0, 0,
  6, 9, 12, 4, 6, 11, 12, 2, 0, 0, 0, 0, 3, 2, 15, 12, 3, 6, 15, 4, 0, 0, 0, 0,
  12, 0, 12, 5, 16, 0, 4, 5, 0, 0, 0, 0, 0, 15, 18, 3, 6, 15, 6, 3, 0, 0, 0, 0,
  0, 14, 24, 5, 8, 14, 8, 5, 0, 0, 0, 0, 5, 1, 3, 18, 6, 1, 1, 18, 0, 0, 0, 0,
  10, 0, 4, 14, 10, 0, 2, 14, 0, 0, 0, 0, 9, 3, 4, 9, 11, 3, 2, 9, 0, 0, 0, 0,
  8, 2, 12, 6, 14, 2, 6, 3, 8, 5, 6, 3, 0, 4, 17, 4, 0, 6, 17, 2, 0, 0, 0, 0,
  16, 16, 5, 8, 16, 20, 5, 4, 0, 0, 0, 0, 3, 16, 5, 8, 3, 20, 5, 4, 0, 0, 0, 0,
  6, 18, 18, 2, 6, 19, 18, 1, 0, 0, 0, 0, 0, 0, 12, 5, 4, 0, 4, 5, 0, 0, 0, 0,
  14, 3, 6, 12, 17, 3, 3, 6, 14, 9, 3, 6, 0, 12, 6, 12, 2, 12, 2, 12, 0, 0, 0, 0,
  2, 3, 21, 3, 2, 4, 21, 1, 0, 0, 0, 0, 4, 3, 6, 12, 4, 3, 3, 6, 7, 9, 3, 6,
  12, 8, 12, 6, 18, 8, 6, 3, 12, 11, 6, 3, 0, 15, 16, 9, 8, 15, 8, 9, 0, 0, 0, 0,
  6, 13, 18, 5, 6, 13, 9, 5, 0, 0, 0, 0, 1, 6, 15, 6, 6, 6, 5, 6, 0, 0, 0, 0,
  11, 9, 9, 6, 14, 9, 3, 6, 0, 0, 0, 0, 3, 0, 15, 11, 8, 0, 5, 11, 0, 0, 0, 0,
  15, 3, 3, 18, 15, 9, 3, 6, 0, 0, 0, 0, 6, 3, 3, 18, 6, 9, 3, 6, 0, 0, 0, 0,
  9, 5, 10, 8, 14, 5, 5, 4, 9, 9, 5, 4, 4, 4, 16, 8, 4, 4, 8, 4, 12, 8, 8, 4,
  7, 7, 12, 3, 7, 7, 6, 3, 0, 0, 0, 0, 5, 0, 9, 13, 8, 0, 3, 13, 0, 0, 0, 0,
  11, 0, 6, 9, 13, 0, 2, 9, 0, 0, 0, 0, 7, 0, 6, 9, 9, 0, 2, 9, 0, 0, 0, 0,
  8, 1, 10, 9, 8, 4, 10, 3, 0, 0, 0, 0, 0, 2, 18, 2, 0, 3, 18, 1, 0, 0, 0, 0,
  10, 13, 14, 6, 17, 13, 7, 3, 10, 16, 7, 3, 0, 13, 14, 6, 0, 13, 7, 3, 7, 16, 7, 3,
  20, 2, 3, 21, 21, 2, 1, 21, 0, 0, 0, 0, 0, 9, 5, 12, 0, 13, 5, 4, 0, 0, 0, 0,
  12, 6, 12, 6, 12, 8, 12, 2, 0, 0, 0, 0, 1, 8, 20, 3, 1, 9, 20, 1, 0, 0, 0, 0,
  5, 7, 19, 3, 5, 8, 19, 1, 0, 0, 0, 0, 1, 12, 9, 6, 1, 14, 9, 2, 0, 0, 0, 0,
  6, 10, 14, 12, 6, 14, 14, 4, 0, 0, 0, 0, 5, 6, 14, 18, 5, 12, 14, 6, 0, 0, 0, 0,
  11, 12, 9, 7, 14, 12, 3, 7, 0, 0, 0, 0, 1, 15, 18, 4, 1, 17, 18, 2, 0, 0, 0, 0,
  11, 14, 6, 9, 11, 17, 6, 3, 0, 0, 0, 0, 0, 8, 18, 4, 0, 8, 9, 2, 9, 10, 9, 2,
  3, 10, 20, 6, 13, 10, 10, 3, 3, 13, 10, 3, 1, 10, 20, 6, 1, 10, 10, 3, 11, 13, 10, 3,
  0, 9, 24, 2, 0, 9, 12, 2, 0, 0, 0, 0, 1, 12, 20, 8, 1, 12, 10, 4, 11, 16, 10, 4,
  11, 12, 9, 7, 14, 12, 3, 7, 0, 0, 0, 0, 4, 12, 9, 7, 7, 12, 3, 7, 0, 0, 0, 0,
  12, 12, 8, 5, 12, 12, 4, 5, 0, 0, 0, 0, 4, 12, 8, 5, 8, 12, 4, 5, 0, 0, 0, 0,
  13, 10, 4, 10, 13, 10, 2, 10, 0, 0, 0, 0, 1, 15, 20, 2, 11, 15, 10, 2, 0, 0, 0, 0,
  9, 10, 6, 6, 9, 10, 3, 6, 0, 0, 0, 0, 0, 1, 21, 3, 7, 1, 7, 3, 0, 0, 0, 0,
  6, 4, 13, 9, 6, 7, 13, 3, 0, 0, 0, 0, 6, 5, 12, 5, 10, 5, 4, 5, 0, 0, 0, 0,
  10, 10, 10, 6, 10, 12, 10, 2, 0, 0, 0, 0, 6, 12, 5, 8, 6, 16, 5, 4, 0, 0, 0, 0,
  13, 0, 6, 9, 15, 0, 2, 9, 0, 0, 0, 0, 2, 10, 18, 6, 8, 10, 6, 6, 0, 0, 0, 0,
  11, 2, 9, 4, 11, 4, 9, 2, 0, 0, 0, 0, 1, 20, 21, 3, 8, 20, 7, 3, 0, 0, 0, 0,
  1, 10, 22, 2, 1, 11, 22, 1, 0, 0, 0, 0, 0, 17, 18, 3, 0, 18, 18, 1, 0, 0, 0, 0,
  13, 0, 6, 9, 15, 0, 2, 9, 0, 0, 0, 0, 5, 0, 6, 9, 7, 0, 2, 9, 0, 0, 0, 0,
  18, 2, 6, 20, 20, 2, 2, 20, 0, 0, 0, 0, 0, 2, 6, 20, 2, 2, 2, 20, 0, 0, 0, 0,
  11, 7, 6, 14, 14, 7, 3, 7, 11, 14, 3, 7, 0, 1, 4, 9, 2, 1, 2, 9, 0, 0, 0, 0,
  12, 14, 9, 4, 12, 16, 9, 2, 0, 0, 0, 0, 1, 13, 9, 4, 1, 15, 9, 2, 0, 0, 0, 0,
  7, 6, 15, 6, 7, 8, 15, 2, 0, 0, 0, 0, 8, 2, 3, 18, 8, 8, 3, 6, 0, 0, 0, 0,
  6, 6, 12, 6, 12, 6, 6, 3, 6, 9, 6, 3, 2, 19, 20, 4, 2, 19, 10, 2, 12, 21, 10, 2,
  14, 15, 6, 9, 14, 18, 6, 3, 0, 0, 0, 0, 3, 5, 18, 14, 3, 5, 9, 7, 12, 12, 9, 7,
  15, 6, 4, 18, 17, 6, 2, 9, 15, 15, 2, 9, 5, 6, 4, 18, 5, 6, 2, 9, 7, 15, 2, 9,
  11, 0, 6, 9, 13, 0, 2, 9, 0, 0, 0, 0, 7, 0, 6, 9, 9, 0, 2, 9, 0, 0, 0, 0,
  11, 5, 6, 9, 13, 5, 2, 9, 0, 0, 0, 0, 9, 5, 6, 6, 12, 5, 3, 6, 0, 0, 0, 0,
  4, 1, 16, 6, 12, 1, 8, 3, 4, 4, 8, 3, 9, 13, 6, 11, 11, 13, 2, 11, 0, 0, 0, 0,
  17, 1, 6, 12, 20, 1, 3, 6, 17, 7, 3, 6, 1, 17, 18, 3, 1, 18, 18, 1, 0, 0, 0, 0,
  7, 13, 10, 8, 7, 17, 10, 4, 0, 0, 0, 0, 6, 18, 10, 6, 6, 20, 10, 2, 0, 0, 0, 0,
  9, 14, 9, 4, 9, 16, 9, 2, 0, 0, 0, 0, 1, 1, 6, 12, 1, 1, 3, 6, 4, 7, 3, 6,
  19, 4, 5, 12, 19, 8, 5, 4, 0, 0, 0, 0, 0, 0, 8, 8, 4, 0, 4, 8, 0, 0, 0, 0,
  3, 5, 19, 3, 3, 6, 19, 1, 0, 0, 0, 0, 1, 5, 12, 6, 1, 5, 6, 3, 7, 8, 6, 3,
  2, 1, 21, 8, 9, 1, 7, 8, 0, 0, 0, 0, 4, 1, 16, 8, 4, 5, 16, 4, 0, 0, 0, 0,
  6, 0, 18, 3, 6, 1, 18, 1, 0, 0, 0, 0, 4, 4, 10, 14, 4, 11, 10, 7, 0, 0, 0, 0,
  15, 6, 4, 10, 15, 11, 4, 5, 0, 0, 0, 0, 3, 18, 18, 3, 9, 18, 6, 3, 0, 0, 0, 0,
  8, 18, 12, 6, 12, 18, 4, 6, 0, 0, 0, 0, 3, 15, 6, 9, 6, 15, 3, 9, 0, 0, 0, 0,
  15, 7, 6, 8, 15, 11, 6, 4, 0, 0, 0, 0, 3, 7, 6, 8, 3, 11, 6, 4, 0, 0, 0, 0,
  5, 9, 18, 6, 14, 9, 9, 3, 5, 12, 9, 3, 1, 13, 12, 6, 1, 15, 12, 2, 0, 0, 0, 0,
  14, 15, 10, 6, 14, 17, 10, 2, 0, 0, 0, 0, 0, 15, 10, 6, 0, 17, 10, 2, 0, 0, 0, 0,
  15, 13, 6, 9, 15, 16, 6, 3, 0, 0, 0, 0, 3, 13, 6, 9, 3, 16, 6, 3, 0, 0, 0, 0,
  9, 5, 8, 8, 9, 5, 4, 8, 0, 0, 0, 0, 1, 18, 12, 6, 1, 18, 6, 3, 7, 21, 6, 3,
  13, 19, 10, 4, 13, 21, 10, 2, 0, 0, 0, 0, 1, 19, 10, 4, 1, 21, 10, 2, 0, 0, 0, 0,
  6, 19, 18, 3, 6, 20, 18, 1, 0, 0, 0, 0, 8, 14, 4, 10, 8, 19, 4, 5, 0, 0, 0, 0,
  0, 0, 24, 6, 0, 2, 24, 2, 0, 0, 0, 0, 0, 1, 6, 9, 0, 4, 6, 3, 0, 0, 0, 0,
  4, 9, 20, 6, 14, 9, 10, 3, 4, 12, 10, 3, 1, 15, 19, 8, 1, 19, 19, 4, 0, 0, 0, 0,
  14, 0, 10, 6, 14, 2, 10, 2, 0, 0, 0, 0, 1, 10, 21, 14, 8, 10, 7, 14, 0, 0, 0, 0,
  10, 10, 8, 8, 10, 10, 4, 8, 0, 0, 0, 0, 6, 8, 10, 4, 11, 8, 5, 4, 0, 0, 0, 0,
  10, 5, 4, 9, 10, 5, 2, 9, 0, 0, 0, 0, 7, 5, 6, 10, 9, 5, 2, 10, 0, 0, 0, 0,
  14, 4, 4, 13, 14, 4, 2, 13, 0, 0, 0, 0, 6, 4, 4, 13, 8, 4, 2, 13, 0, 0, 0, 0,
  8, 7, 9, 6, 11, 7, 3, 6, 0, 0, 0, 0, 3, 6, 16, 6, 3, 6, 8, 3, 11, 9, 8, 3,
  5, 4, 16, 14, 13, 4, 8, 7, 5, 11, 8, 7, 0, 0, 24, 4, 0, 0, 12, 2, 12, 2, 12, 2,
  9, 1, 9, 6, 12, 1, 3, 6, 0, 0, 0, 0, 4, 1, 14, 4, 11, 1, 7, 4, 0, 0, 0, 0,
  10, 14, 7, 9, 10, 17, 7, 3, 0, 0, 0, 0, 8, 3, 8, 10, 8, 3, 4, 5, 12, 8, 4, 5,
  7, 3, 12, 5, 11, 3, 4, 5, 0, 0, 0, 0, 8, 2, 4, 13, 10, 2, 2, 13, 0, 0, 0, 0,
  11, 2, 3, 19, 12, 2, 1, 19, 0, 0, 0, 0, 7, 7, 9, 6, 10, 7, 3, 6, 0, 0, 0, 0,
  4, 22, 20, 2, 4, 22, 10, 2, 0, 0, 0, 0, 0, 16, 24, 4, 0, 16, 12, 2, 12, 18, 12, 2,
  7, 3, 12, 5, 11, 3, 4, 5, 0, 0, 0, 0, 1, 10, 8, 14, 1, 10, 4, 7, 5, 17, 4, 7,
  11, 16, 6, 6, 11, 19, 6, 3, 0, 0, 0, 0, 6, 0, 10, 24, 6, 0, 5, 12, 11, 12, 5, 12,
  7, 5, 14, 14, 14, 5, 7, 7, 7, 12, 7, 7, 7, 8, 10, 8, 7, 8, 5, 4, 12, 12, 5, 4,
  9, 1, 9, 6, 12, 1, 3, 6, 0, 0, 0, 0, 0, 6, 24, 3, 12, 6, 12, 3, 0, 0, 0, 0,
  7, 3, 12, 5, 11, 3, 4, 5, 0, 0, 0, 0, 1, 13, 22, 4, 1, 13, 11, 2, 12, 15, 11, 2,
  9, 12, 12, 6, 9, 14, 12, 2, 0, 0, 0, 0, 0, 5, 9, 6, 0, 7, 9, 2, 0, 0, 0, 0,
  1, 5, 23, 6, 1, 7, 23, 2, 0, 0, 0, 0, 1, 6, 19, 12, 1, 10, 19, 4, 0, 0, 0, 0,
  9, 1, 6, 21, 9, 8, 6, 7, 0, 0, 0, 0, 3, 19, 18, 3, 9, 19, 6, 3, 0, 0, 0, 0,
  9, 14, 6, 9, 11, 14, 2, 9, 0, 0, 0, 0, 9, 6, 4, 12, 11, 6, 2, 12, 0, 0, 0, 0,
  16, 0, 6, 9, 18, 0, 2, 9, 0, 0, 0, 0, 2, 0, 6, 9, 4, 0, 2, 9, 0, 0, 0, 0,
  13, 1, 4, 22, 15, 1, 2, 11, 13, 12, 2, 11, 1, 8, 8, 12, 1, 14, 8, 6, 0, 0, 0, 0,
  14, 7, 7, 9, 14, 10, 7, 3, 0, 0, 0, 0, 3, 12, 18, 4, 3, 12, 9, 2, 12, 14, 9, 2,
  13, 1, 4, 22, 15, 1, 2, 11, 13, 12, 2, 11, 7, 1, 4, 22, 7, 1, 2, 11, 9, 12, 2, 11,
  4, 7, 20, 4, 14, 7, 10, 2, 4, 9, 10, 2, 9, 10, 6, 7, 12, 10, 3, 7, 0, 0, 0, 0,
  7, 7, 10, 4, 7, 7, 5, 4, 0, 0, 0, 0, 0, 3, 4, 15, 0, 8, 4, 5, 0, 0, 0, 0,
  15, 0, 8, 12, 19, 0, 4, 6, 15, 6, 4, 6, 1, 0, 8, 12, 1, 0, 4, 6, 5, 6, 4, 6,
  14, 5, 6, 16, 16, 5, 2, 16, 0, 0, 0, 0, 4, 5, 6, 16, 6, 5, 2, 16, 0, 0, 0, 0,
  15, 0, 6, 16, 17, 0, 2, 16, 0, 0, 0, 0, 3, 0, 6, 16, 5, 0, 2, 16, 0, 0, 0, 0,
  0, 2, 24, 3, 0, 3, 24, 1, 0, 0, 0, 0, 7, 1, 10, 4, 7, 3, 10, 2, 0, 0, 0, 0,
  1, 0, 23, 8, 1, 4, 23, 4, 0, 0, 0, 0, 1, 17, 19, 3, 1, 18, 19, 1, 0, 0, 0, 0,
  6, 18, 18, 2, 6, 19, 18, 1, 0, 0, 0, 0, 1, 17, 9, 6, 1, 19, 9, 2, 0, 0, 0, 0,
  15, 15, 6, 9, 15, 18, 6, 3, 0, 0, 0, 0, 3, 15, 6, 9, 3, 18, 6, 3, 0, 0, 0, 0,
  4, 14, 20, 6, 4, 17, 20, 3, 0, 0, 0, 0, 0, 10, 6, 14, 0, 10, 3, 7, 3, 17, 3, 7,
  6, 18, 18, 3, 6, 19, 18, 1, 0, 0, 0, 0, 4, 12, 9, 7, 7, 12, 3, 7, 0, 0, 0, 0,
  6, 10, 18, 5, 12, 10, 6, 5, 0, 0, 0, 0, 0, 10, 18, 5, 6, 10, 6, 5, 0, 0, 0, 0,
  3, 2, 18, 9, 9, 2, 6, 9, 0, 0, 0, 0, 4, 6, 10, 10, 4, 6, 5, 5, 9, 11, 5, 5,
  20, 14, 4, 9, 20, 14, 2, 9, 0, 0, 0, 0, 0, 14, 4, 9, 2, 14, 2, 9, 0, 0, 0, 0,
  11, 1, 4, 20, 13, 1, 2, 10, 11, 11, 2, 10, 6, 21, 12, 3, 12, 21, 6, 3, 0, 0, 0, 0,
  11, 1, 4, 20, 13, 1, 2, 10, 11, 11, 2, 10, 1, 16, 10, 8, 1, 16, 5, 4, 6, 20, 5, 4,
  11, 1, 4, 20, 13, 1, 2, 10, 11, 11, 2, 10, 1, 0, 3, 19, 2, 0, 1, 19, 0, 0, 0, 0,
  11, 1, 4, 20, 13, 1, 2, 10, 11, 11, 2, 10, 0, 1, 6, 9, 2, 1, 2, 9, 0, 0, 0, 0,
  3, 7, 19, 4, 3, 9, 19, 2, 0, 0, 0, 0, 7, 14, 9, 6, 7, 16, 9, 2, 0, 0, 0, 0,
  17, 1, 7, 6, 17, 4, 7, 3, 0, 0, 0, 0, 5, 0, 14, 8, 5, 4, 14, 4, 0, 0, 0, 0,
  16, 1, 8, 6, 16, 4, 8, 3, 0, 0, 0, 0, 0, 1, 8, 6, 0, 4, 8, 3, 0, 0, 0, 0,
  6, 0, 18, 4, 15, 0, 9, 2, 6, 2, 9, 2, 0, 14, 9, 6, 0, 16, 9, 2, 0, 0, 0, 0,
  3, 7, 18, 8, 9, 7, 6, 8, 0, 0, 0, 0, 2, 11, 6, 9, 4, 11, 2, 9, 0, 0, 0, 0,
  10, 5, 6, 9, 12, 5, 2, 9, 0, 0, 0, 0, 10, 6, 4, 18, 10, 6, 2, 9, 12, 15, 2, 9,
  11, 1, 4, 20, 13, 1, 2, 10, 11, 11, 2, 10, 9, 1, 4, 20, 9, 1, 2, 10, 11, 11, 2, 10,
  5, 9, 18, 6, 14, 9, 9, 3, 5, 12, 9, 3, 6, 4, 6, 9, 8, 4, 2, 9, 0, 0, 0, 0,
  10, 16, 8, 6, 10, 16, 4, 6, 0, 0, 0, 0, 0, 0, 18, 8, 0, 0, 9, 4, 9, 4, 9, 4,
  6, 5, 14, 12, 13, 5, 7, 6, 6, 11, 7, 6, 4, 3, 15, 7, 9, 3, 5, 7, 0, 0, 0, 0,
  14, 12, 10, 6, 14, 14, 10, 2, 0, 0, 0, 0, 0, 11, 4, 10, 0, 16, 4, 5, 0, 0, 0, 0,
  1, 10, 22, 3, 1, 11, 22, 1, 0, 0, 0, 0, 8, 9, 6, 10, 10, 9, 2, 10, 0, 0, 0, 0,
  13, 2, 6, 12, 16, 2, 3, 6, 13, 8, 3, 6, 10, 6, 4, 18, 10, 6, 2, 9, 12, 15, 2, 9,
  7, 8, 10, 16, 12, 8, 5, 8, 7, 16, 5, 8, 8, 1, 8, 12, 8, 1, 4, 6, 12, 7, 4, 6,
  7, 1, 12, 14, 13, 1, 6, 7, 7, 8, 6, 7, 2, 14, 12, 6, 2, 16, 12, 2, 0, 0, 0, 0,
  11, 16, 6, 6, 11, 19, 6, 3, 0, 0, 0, 0, 7, 16, 6, 6, 7, 19, 6, 3, 0, 0, 0, 0,
  13, 4, 4, 10, 13, 4, 2, 10, 0, 0, 0, 0, 0, 19, 19, 3, 0, 20, 19, 1, 0, 0, 0, 0,
  12, 8, 6, 8, 12, 12, 6, 4, 0, 0, 0, 0, 8, 1, 8, 22, 8, 12, 8, 11, 0, 0, 0, 0,
  12, 8, 6, 8, 12, 12, 6, 4, 0, 0, 0, 0, 6, 8, 6, 8, 6, 12, 6, 4, 0, 0, 0, 0,
  14, 5, 6, 9, 14, 8, 6, 3, 0, 0, 0, 0, 0, 6, 24, 4, 0, 8, 24, 2, 0, 0, 0, 0,
  14, 12, 10, 6, 14, 14, 10, 2, 0, 0, 0, 0, 0, 12, 10, 6, 0, 14, 10, 2, 0, 0, 0, 0,
  4, 6, 19, 3, 4, 7, 19, 1, 0, 0, 0, 0, 1, 6, 19, 3, 1, 7, 19, 1, 0, 0, 0, 0,
  4, 0, 16, 9, 4, 3, 16, 3, 0, 0, 0, 0, 0, 1, 24, 5, 8, 1, 8, 5, 0, 0, 0, 0,
  3, 6, 6, 15, 3, 11, 6, 5, 0, 0, 0, 0, 9, 6, 6, 9, 11, 6, 2, 9, 0, 0, 0, 0,
  0, 17, 18, 3, 0, 18, 18, 1, 0, 0, 0, 0, 6, 22, 18, 2, 6, 23, 18, 1, 0, 0, 0, 0,
  2, 12, 6, 9, 2, 15, 6, 3, 0, 0, 0, 0, 18, 12, 6, 9, 18, 15, 6, 3, 0, 0, 0, 0,
  0, 12, 6, 9, 0, 15, 6, 3, 0, 0, 0, 0, 11, 14, 4, 10, 11, 19, 4, 5, 0, 0, 0, 0,
  9, 6, 6, 16, 9, 14, 6, 8, 0, 0, 0, 0, 7, 7, 10, 10, 7, 12, 10, 5, 0, 0, 0, 0,
  1, 3, 6, 13, 3, 3, 2, 13, 0, 0, 0, 0, 18, 1, 6, 13, 18, 1, 3, 13, 0, 0, 0, 0,
  5, 1, 6, 9, 7, 1, 2, 9, 0, 0, 0, 0, 18, 2, 6, 11, 18, 2, 3, 11, 0, 0, 0, 0,
  0, 2, 6, 11, 3, 2, 3, 11, 0, 0, 0, 0, 9, 12, 15, 6, 9, 14, 15, 2, 0, 0, 0, 0,
  2, 2, 20, 3, 2, 3, 20, 1, 0, 0, 0, 0, 10, 6, 4, 9, 10, 6, 2, 9, 0, 0, 0, 0,
  5, 6, 12, 14, 5, 6, 6, 7, 11, 13, 6, 7, 9, 0, 6, 9, 11, 0, 2, 9, 0, 0, 0, 0,
  7, 0, 9, 6, 10, 0, 3, 6, 0, 0, 0, 0, 10, 6, 6, 9, 12, 6, 2, 9, 0, 0, 0, 0,
  4, 1, 12, 20, 4, 1, 6, 10, 10, 11, 6, 10, 6, 7, 18, 3, 6, 7, 9, 3, 0, 0, 0, 0,
  0, 7, 18, 3, 9, 7, 9, 3, 0, 0, 0, 0, 3, 20, 18, 3, 9, 20, 6, 3, 0, 0, 0, 0,
  9, 6, 6, 9, 11, 6, 2, 9, 0, 0, 0, 0, 6, 2, 12, 15, 10, 2, 4, 15, 0, 0, 0, 0,
  2, 3, 18, 3, 2, 4, 18, 1, 0, 0, 0, 0, 19, 4, 4, 18, 21, 4, 2, 9, 19, 13, 2, 9,
  0, 1, 19, 3, 0, 2, 19, 1, 0, 0, 0, 0, 5, 0, 15, 4, 5, 2, 15, 2, 0, 0, 0, 0,
  5, 2, 14, 5, 12, 2, 7, 5, 0, 0, 0, 0, 1, 2, 22, 14, 1, 2, 11, 14, 0, 0, 0, 0,
  8, 15, 6, 9, 10, 15, 2, 9, 0, 0, 0, 0, 6, 17, 18, 3, 6, 18, 18, 1, 0, 0, 0, 0,
  9, 6, 3, 18, 9, 12, 3, 6, 0, 0, 0, 0, 2, 0, 20, 3, 2, 1, 20, 1, 0, 0, 0, 0,
  5, 4, 5, 12, 5, 8, 5, 4, 0, 0, 0, 0, 8, 6, 12, 5, 12, 6, 4, 5, 0, 0, 0, 0,
  9, 12, 6, 12, 9, 12, 3, 6, 12, 18, 3, 6, 14, 14, 8, 10, 18, 14, 4, 5, 14, 19, 4, 5,
  2, 14, 8, 10, 2, 14, 4, 5, 6, 19, 4, 5, 10, 18, 12, 6, 16, 18, 6, 3, 10, 21, 6, 3,
  1, 3, 6, 9, 1, 6, 6, 3, 0, 0, 0, 0, 11, 3, 3, 20, 12, 3, 1, 20, 0, 0, 0, 0,
  4, 6, 14, 6, 4, 6, 7, 3, 11, 9, 7, 3, 6, 5, 12, 13, 10, 5, 4, 13, 0, 0, 0, 0,
  5, 4, 4, 15, 5, 9, 4, 5, 0, 0, 0, 0, 9, 16, 15, 4, 14, 16, 5, 4, 0, 0, 0, 0,
  7, 8, 6, 14, 7, 8, 3, 7, 10, 15, 3, 7, 7, 6, 10, 6, 7, 8, 10, 2, 0, 0, 0, 0,
  2, 5, 18, 3, 2, 6, 18, 1, 0, 0, 0, 0, 5, 1, 15, 8, 5, 5, 15, 4, 0, 0, 0, 0,
  7, 1, 8, 18, 7, 10, 8, 9, 0, 0, 0, 0, 0, 10, 24, 3, 0, 11, 24, 1, 0, 0, 0, 0,
  0, 2, 6, 13, 2, 2, 2, 13, 0, 0, 0, 0, 16, 0, 8, 10, 20, 0, 4, 5, 16, 5, 4, 5,
  5, 1, 10, 9, 5, 4, 10, 3, 0, 0, 0, 0, 5, 6, 18, 3, 5, 7, 18, 1, 0, 0, 0, 0,
  0, 1, 24, 3, 0, 2, 24, 1, 0, 0, 0, 0, 11, 4, 6, 11, 13, 4, 2, 11, 0, 0, 0, 0,
  0, 0, 8, 10, 0, 0, 4, 5, 4, 5, 4, 5, 4, 16, 18, 3, 4, 17, 18, 1, 0, 0, 0, 0,
  2, 16, 18, 3, 2, 17, 18, 1, 0, 0, 0, 0, 3, 0, 18, 10, 12, 0, 9, 5, 3, 5, 9, 5,
  2, 3, 20, 21, 12, 3, 10, 21, 0, 0, 0, 0, 6, 7, 14, 3, 6, 7, 7, 3, 0, 0, 0, 0,
  0, 9, 12, 6, 0, 9, 6, 3, 6, 12, 6, 3, 3, 14, 21, 4, 10, 14, 7, 4, 0, 0, 0, 0,
  0, 14, 21, 4, 7, 14, 7, 4, 0, 0, 0, 0, 5, 21, 18, 3, 11, 21, 6, 3, 0, 0, 0, 0,
  1, 21, 18, 3, 7, 21, 6, 3, 0, 0, 0, 0, 19, 4, 4, 18, 21, 4, 2, 9, 19, 13, 2, 9,
  3, 7, 18, 3, 3, 8, 18, 1, 0, 0, 0, 0, 19, 4, 4, 18, 21, 4, 2, 9, 19, 13, 2, 9,
  7, 15, 10, 6, 7, 17, 10, 2, 0, 0, 0, 0, 9, 13, 11, 9, 9, 16, 11, 3, 0, 0, 0, 0,
  0, 6, 4, 10, 0, 11, 4, 5, 0, 0, 0, 0, 15, 16, 9, 6, 15, 18, 9, 2, 0, 0, 0, 0,
  1, 5, 4, 18, 1, 5, 2, 9, 3, 14, 2, 9, 9, 8, 8, 10, 13, 8, 4, 5, 9, 13, 4, 5,
  7, 8, 8, 10, 7, 8, 4, 5, 11, 13, 4, 5, 9, 8, 12, 5, 13, 8, 4, 5, 0, 0, 0, 0,
  7, 8, 9, 7, 10, 8, 3, 7, 0, 0, 0, 0, 9, 8, 12, 5, 13, 8, 4, 5, 0, 0, 0, 0,
  7, 6, 9, 7, 10, 6, 3, 7, 0, 0, 0, 0, 9, 8, 12, 5, 13, 8, 4, 5, 0, 0, 0, 0,
  10, 5, 4, 18, 10, 11, 4, 6, 0, 0, 0, 0, 5, 5, 14, 12, 5, 11, 14, 6, 0, 0, 0, 0,
  0, 1, 11, 4, 0, 3, 11, 2, 0, 0, 0, 0, 9, 10, 6, 10, 11, 10, 2, 10, 0, 0, 0, 0,
  2, 17, 11, 6, 2, 19, 11, 2, 0, 0, 0, 0, 15, 16, 9, 6, 15, 18, 9, 2, 0, 0, 0, 0,
  1, 10, 18, 2, 1, 11, 18, 1, 0, 0, 0, 0, 6, 4, 12, 13, 10, 4, 4, 13, 0, 0, 0, 0,
  0, 18, 18, 3, 0, 19, 18, 1, 0, 0, 0, 0, 6, 18, 18, 3, 6, 19, 18, 1, 0, 0, 0, 0,
  0, 16, 9, 6, 0, 18, 9, 2, 0, 0, 0, 0, 13, 15, 9, 6, 13, 17, 9, 2, 0, 0, 0, 0,
  2, 15, 9, 6, 2, 17, 9, 2, 0, 0, 0, 0, 13, 1, 6, 16, 13, 1, 3, 16, 0, 0, 0, 0,
  5, 1, 6, 16, 8, 1, 3, 16, 0, 0, 0, 0, 11, 5, 6, 10, 13, 5, 2, 10, 0, 0, 0, 0,
  7, 5, 6, 10, 9, 5, 2, 10, 0, 0, 0, 0, 10, 0, 6, 24, 12, 0, 2, 24, 0, 0, 0, 0,
  3, 4, 4, 20, 3, 4, 2, 10, 5, 14, 2, 10, 14, 0, 6, 9, 16, 0, 2, 9, 0, 0, 0, 0,
  4, 0, 6, 9, 6, 0, 2, 9, 0, 0, 0, 0, 4, 5, 18, 5, 10, 5, 6, 5, 0, 0, 0, 0,
  5, 6, 6, 9, 7, 6, 2, 9, 0, 0, 0, 0, 7, 2, 15, 8, 12, 2, 5, 8, 0, 0, 0, 0,
  2, 2, 15, 8, 7, 2, 5, 8, 0, 0, 0, 0, 10, 0, 4, 9, 10, 0, 2, 9, 0, 0, 0, 0,
  3, 4, 6, 12, 3, 4, 3, 6, 6, 10, 3, 6, 16, 0, 8, 18, 16, 0, 4, 18, 0, 0, 0, 0,
  0, 0, 8, 18, 4, 0, 4, 18, 0, 0, 0, 0, 0, 7, 24, 6, 0, 9, 24, 2, 0, 0, 0, 0,
  4, 7, 14, 3, 11, 7, 7, 3, 0, 0, 0, 0, 10, 8, 8, 15, 10, 8, 4, 15, 0, 0, 0, 0,
  7, 0, 10, 14, 12, 0, 5, 14, 0, 0, 0, 0, 13, 10, 8, 10, 17, 10, 4, 5, 13, 15, 4, 5,
  3, 0, 4, 9, 5, 0, 2, 9, 0, 0, 0, 0, 16, 1, 6, 8, 16, 1, 3, 8, 0, 0, 0, 0,
  2, 1, 6, 8, 5, 1, 3, 8, 0, 0, 0, 0, 3, 6, 18, 12, 3, 10, 18, 4, 0, 0, 0, 0,
  4, 12, 16, 4, 4, 14, 16, 2, 0, 0, 0, 0, 4, 9, 16, 15, 4, 14, 16, 5, 0, 0, 0, 0,
  3, 10, 8, 10, 3, 10, 4, 5, 7, 15, 4, 5, 8, 18, 16, 6, 16, 18, 8, 3, 8, 21, 8, 3,
  2, 16, 12, 5, 6, 16, 4, 5, 0, 0, 0, 0, 14, 14, 9, 4, 14, 16, 9, 2, 0, 0, 0, 0,
  7, 14, 9, 6, 7, 16, 9, 2, 0, 0, 0, 0, 4, 10, 16, 12, 4, 14, 16, 4, 0, 0, 0, 0,
  0, 13, 19, 6, 0, 15, 19, 2, 0, 0, 0, 0, 10, 13, 9, 6, 10, 15, 9, 2, 0, 0, 0, 0,
  5, 0, 3, 23, 6, 0, 1, 23, 0, 0, 0, 0, 0, 8, 24, 6, 0, 10, 24, 2, 0, 0, 0, 0,
  0, 5, 5, 12, 0, 9, 5, 4, 0, 0, 0, 0, 3, 0, 19, 18, 3, 9, 19, 9, 0, 0, 0, 0,
  9, 11, 6, 12, 9, 11, 3, 6, 12, 17, 3, 6, 0, 5, 24, 8, 12, 5, 12, 4, 0, 9, 12, 4,
  6, 18, 9, 4, 6, 20, 9, 2, 0, 0, 0, 0, 8, 8, 10, 6, 8, 10, 10, 2, 0, 0, 0, 0,
  2, 7, 20, 3, 2, 8, 20, 1, 0, 0, 0, 0, 12, 0, 7, 20, 12, 10, 7, 10, 0, 0, 0, 0,
  5, 0, 7, 20, 5, 10, 7, 10, 0, 0, 0, 0, 14, 2, 2, 18, 14, 11, 2, 9, 0, 0, 0, 0,
  5, 8, 10, 12, 10, 8, 5, 12, 0, 0, 0, 0, 6, 9, 12, 8, 12, 9, 6, 4, 6, 13, 6, 4,
  7, 7, 3, 14, 7, 14, 3, 7, 0, 0, 0, 0, 11, 2, 12, 16, 17, 2, 6, 8, 11, 10, 6, 8,
  7, 0, 6, 9, 9, 0, 2, 9, 0, 0, 0, 0, 13, 14, 9, 4, 13, 16, 9, 2, 0, 0, 0, 0,
  0, 12, 22, 4, 0, 12, 11, 2, 11, 14, 11, 2, 1, 12, 22, 6, 12, 12, 11, 3, 1, 15, 11, 3,
  6, 6, 9, 6, 9, 6, 3, 6, 0, 0, 0, 0, 10, 0, 4, 9, 10, 0, 2, 9, 0, 0, 0, 0,
  3, 8, 18, 7, 9, 8, 6, 7, 0, 0, 0, 0, 0, 6, 24, 6, 0, 8, 24, 2, 0, 0, 0, 0,
  0, 11, 24, 10, 8, 11, 8, 10, 0, 0, 0, 0, 3, 3, 18, 21, 9, 3, 6, 21, 0, 0, 0, 0,
  7, 12, 4, 10, 9, 12, 2, 10, 0, 0, 0, 0, 10, 16, 10, 8, 15, 16, 5, 4, 10, 20, 5, 4,
  8, 6, 6, 9, 10, 6, 2, 9, 0, 0, 0, 0, 12, 10, 6, 12, 15, 10, 3, 6, 12, 16, 3, 6,
  6, 10, 6, 12, 6, 10, 3, 6, 9, 16, 3, 6, 16, 12, 6, 12, 19, 12, 3, 6, 16, 18, 3, 6,
  2, 12, 6, 12, 2, 12, 3, 6, 5, 18, 3, 6, 10, 15, 6, 9, 12, 15, 2, 9, 0, 0, 0, 0,
  8, 15, 6, 9, 10, 15, 2, 9, 0, 0, 0, 0, 14, 20, 10, 4, 14, 20, 5, 4, 0, 0, 0, 0,
  0, 20, 10, 4, 5, 20, 5, 4, 0, 0, 0, 0, 11, 17, 9, 6, 11, 19, 9, 2, 0, 0, 0, 0,
  3, 2, 14, 4, 3, 4, 14, 2, 0, 0, 0, 0, 10, 1, 10, 4, 10, 3, 10, 2, 0, 0, 0, 0,
  0, 15, 10, 4, 5, 15, 5, 4, 0, 0, 0, 0, 19, 2, 3, 19, 20, 2, 1, 19, 0, 0, 0, 0,
  4, 12, 9, 8, 7, 12, 3, 8, 0, 0, 0, 0, 4, 7, 5, 12, 4, 11, 5, 4, 0, 0, 0, 0,
  0, 1, 24, 3, 8, 1, 8, 3, 0, 0, 0, 0, 6, 8, 12, 4, 6, 10, 12, 2, 0, 0, 0, 0,
  19, 3, 4, 10, 19, 3, 2, 10, 0, 0, 0, 0, 0, 6, 9, 6, 3, 6, 3, 6, 0, 0, 0, 0,
  18, 0, 6, 22, 20, 0, 2, 22, 0, 0, 0, 0, 0, 0, 6, 22, 2, 0, 2, 22, 0, 0, 0, 0,
  5, 15, 19, 3, 5, 16, 19, 1, 0, 0, 0, 0, 10, 7, 4, 15, 10, 12, 4, 5, 0, 0, 0, 0,
  9, 6, 6, 9, 11, 6, 2, 9, 0, 0, 0, 0, 0, 21, 18, 3, 0, 22, 18, 1, 0, 0, 0, 0,
  7, 3, 10, 15, 7, 8, 10, 5, 0, 0, 0, 0, 1, 7, 18, 3, 1, 8, 18, 1, 0, 0, 0, 0,
  8, 2, 9, 6, 11, 2, 3, 6, 0, 0, 0, 0, 0, 10, 24, 14, 0, 17, 24, 7, 0, 0, 0, 0,
  13, 9, 8, 10, 17, 9, 4, 5, 13, 14, 4, 5, 10, 5, 4, 9, 12, 5, 2, 9, 0, 0, 0, 0,
  13, 9, 8, 10, 17, 9, 4, 5, 13, 14, 4, 5, 7, 11, 10, 10, 7, 11, 5, 5, 12, 16, 5, 5,
  4, 13, 18, 4, 13, 13, 9, 2, 4, 15, 9, 2, 0, 0, 19, 2, 0, 1, 19, 1, 0, 0, 0, 0,
  0, 18, 24, 6, 8, 18, 8, 6, 0, 0, 0, 0, 6, 4, 8, 16, 6, 12, 8, 8, 0, 0, 0, 0,
  7, 8, 10, 4, 7, 10, 10, 2, 0, 0, 0, 0, 0, 3, 6, 9, 0, 6, 6, 3, 0, 0, 0, 0,
  13, 15, 7, 9, 13, 18, 7, 3, 0, 0, 0, 0, 3, 18, 12, 6, 3, 18, 6, 3, 9, 21, 6, 3,
  12, 14, 6, 9, 12, 17, 6, 3, 0, 0, 0, 0, 2, 15, 15, 8, 2, 19, 15, 4, 0, 0, 0, 0,
  9, 6, 6, 16, 9, 14, 6, 8, 0, 0, 0, 0, 6, 6, 7, 12, 6, 10, 7, 4, 0, 0, 0, 0,
  14, 6, 6, 9, 14, 9, 6, 3, 0, 0, 0, 0, 5, 14, 6, 9, 5, 17, 6, 3, 0, 0, 0, 0,
  10, 8, 6, 9, 12, 8, 2, 9, 0, 0, 0, 0, 6, 6, 4, 18, 6, 6, 2, 9, 8, 15, 2, 9,
  14, 9, 6, 12, 17, 9, 3, 6, 14, 15, 3, 6, 4, 9, 6, 12, 4, 9, 3, 6, 7, 15, 3, 6,
  14, 15, 9, 6, 14, 17, 9, 2, 0, 0, 0, 0, 0, 20, 18, 4, 0, 20, 9, 2, 9, 22, 9, 2,
  13, 18, 9, 6, 13, 20, 9, 2, 0, 0, 0, 0, 2, 18, 9, 6, 2, 20, 9, 2, 0, 0, 0, 0,
  6, 16, 18, 3, 6, 17, 18, 1, 0, 0, 0, 0, 0, 16, 18, 3, 0, 17, 18, 1, 0, 0, 0, 0,
  19, 2, 4, 22, 21, 2, 2, 11, 19, 13, 2, 11, 1, 2, 4, 22, 1, 2, 2, 11, 3, 13, 2, 11,
  15, 0, 2, 24, 15, 0, 1, 24, 0, 0, 0, 0, 3, 20, 16, 4, 11, 20, 8, 4, 0, 0, 0, 0,
  11, 6, 4, 18, 13, 6, 2, 9, 11, 15, 2, 9, 7, 9, 10, 14, 7, 9, 5, 7, 12, 16, 5, 7,
  14, 6, 6, 9, 14, 9, 6, 3, 0, 0, 0, 0, 3, 6, 7, 9, 3, 9, 7, 3, 0, 0, 0, 0,
  20, 4, 4, 20, 22, 4, 2, 10, 20, 14, 2, 10, 7, 6, 6, 9, 7, 9, 6, 3, 0, 0, 0, 0,
  7, 0, 10, 14, 12, 0, 5, 7, 7, 7, 5, 7, 2, 1, 18, 6, 11, 1, 9, 6, 0, 0, 0, 0,
  15, 0, 2, 24, 15, 0, 1, 24, 0, 0, 0, 0, 7, 0, 2, 24, 8, 0, 1, 24, 0, 0, 0, 0,
  13, 12, 6, 7, 13, 12, 3, 7, 0, 0, 0, 0, 5, 12, 6, 7, 8, 12, 3, 7, 0, 0, 0, 0,
  3, 5, 18, 19, 9, 5, 6, 19, 0, 0, 0, 0, 5, 6, 9, 6, 8, 6, 3, 6, 0, 0, 0, 0,
  9, 5, 9, 6, 12, 5, 3, 6, 0, 0, 0, 0, 3, 16, 10, 8, 3, 16, 5, 4, 8, 20, 5, 4,
  19, 8, 5, 15, 19, 13, 5, 5, 0, 0, 0, 0, 0, 8, 5, 15, 0, 13, 5, 5, 0, 0, 0, 0,
  20, 4, 4, 20, 22, 4, 2, 10, 20, 14, 2, 10, 0, 4, 4, 20, 0, 4, 2, 10, 2, 14, 2, 10,
  7, 7, 10, 4, 7, 7, 5, 4, 0, 0, 0, 0, 4, 19, 14, 4, 11, 19, 7, 4, 0, 0, 0, 0,
  10, 11, 12, 3, 10, 11, 6, 3, 0, 0, 0, 0, 0, 1, 24, 3, 0, 2, 24, 1, 0, 0, 0, 0,
  7, 2, 14, 20, 14, 2, 7, 10, 7, 12, 7, 10, 0, 13, 6, 9, 2, 13, 2, 9, 0, 0, 0, 0,
  13, 0, 4, 19, 13, 0, 2, 19, 0, 0, 0, 0, 1, 11, 14, 3, 8, 11, 7, 3, 0, 0, 0, 0,
  7, 1, 16, 20, 15, 1, 8, 10, 7, 11, 8, 10, 0, 10, 21, 9, 7, 10, 7, 9, 0, 0, 0, 0,
  6, 19, 15, 5, 11, 19, 5, 5, 0, 0, 0, 0, 8, 10, 6, 6, 11, 10, 3, 6, 0, 0, 0, 0,
  7, 1, 16, 20, 15, 1, 8, 10, 7, 11, 8, 10, 1, 1, 16, 20, 1, 1, 8, 10, 9, 11, 8, 10,
  16, 4, 3, 12, 16, 10, 3, 6, 0, 0, 0, 0, 5, 4, 3, 12, 5, 10, 3, 6, 0, 0, 0, 0,
  7, 6, 10, 8, 12, 6, 5, 4, 7, 10, 5, 4, 4, 9, 6, 6, 4, 12, 6, 3, 0, 0, 0, 0,
  6, 5, 12, 4, 6, 7, 12, 2, 0, 0, 0, 0, 9, 2, 5, 15, 9, 7, 5, 5, 0, 0, 0, 0,
  15, 0, 9, 6, 15, 2, 9, 2, 0, 0, 0, 0, 6, 0, 11, 10, 6, 5, 11, 5, 0, 0, 0, 0,
  12, 7, 4, 12, 12, 13, 4, 6, 0, 0, 0, 0, 7, 2, 9, 4, 7, 4, 9, 2, 0, 0, 0, 0,
  6, 0, 13, 6, 6, 2, 13, 2, 0, 0, 0, 0, 10, 6, 4, 18, 10, 6, 2, 9, 12, 15, 2, 9,
  10, 8, 6, 9, 12, 8, 2, 9, 0, 0, 0, 0, 3, 18, 10, 6, 3, 20, 10, 2, 0, 0, 0, 0,
  4, 14, 20, 3, 4, 15, 20, 1, 0, 0, 0, 0, 2, 15, 9, 6, 2, 17, 9, 2, 0, 0, 0, 0,
  13, 0, 4, 19, 13, 0, 2, 19, 0, 0, 0, 0, 7, 0, 4, 19, 9, 0, 2, 19, 0, 0, 0, 0,
  1, 4, 22, 2, 1, 5, 22, 1, 0, 0, 0, 0, 0, 0, 9, 6, 0, 2, 9, 2, 0, 0, 0, 0,
  0, 0, 24, 18, 0, 9, 24, 9, 0, 0, 0, 0, 3, 2, 16, 8, 3, 6, 16, 4, 0, 0, 0, 0,
  3, 6, 18, 6, 3, 8, 18, 2, 0, 0, 0, 0, 3, 1, 6, 10, 5, 1, 2, 10, 0, 0, 0, 0,
  13, 0, 9, 6, 16, 0, 3, 6, 0, 0, 0, 0, 2, 0, 9, 6, 5, 0, 3, 6, 0, 0, 0, 0,
  10, 2, 4, 15, 10, 7, 4, 5, 0, 0, 0, 0, 6, 0, 7, 10, 6, 5, 7, 5, 0, 0, 0, 0,
  2, 2, 20, 4, 12, 2, 10, 2, 2, 4, 10, 2, 2, 11, 19, 3, 2, 12, 19, 1, 0, 0, 0, 0,
  10, 8, 6, 9, 12, 8, 2, 9, 0, 0, 0, 0, 8, 8, 6, 9, 10, 8, 2, 9, 0, 0, 0, 0,
  13, 8, 4, 9, 13, 8, 2, 9, 0, 0, 0, 0, 3, 11, 9, 9, 6, 11, 3, 9, 0, 0, 0, 0,
  3, 9, 18, 5, 9, 9, 6, 5, 0, 0, 0, 0, 2, 4, 2, 20, 2, 14, 2, 10, 0, 0, 0, 0,
  14, 17, 8, 6, 14, 20, 8, 3, 0, 0, 0, 0, 3, 21, 18, 2, 3, 22, 18, 1, 0, 0, 0, 0,
  5, 4, 15, 6, 10, 4, 5, 6, 0, 0, 0, 0, 2, 15, 12, 6, 2, 17, 12, 2, 0, 0, 0, 0,
  17, 8, 6, 9, 17, 11, 6, 3, 0, 0, 0, 0, 2, 12, 20, 4, 2, 12, 10, 2, 12, 14, 10, 2,
  0, 17, 24, 6, 0, 19, 24, 2, 0, 0, 0, 0, 7, 16, 9, 4, 7, 18, 9, 2, 0, 0, 0, 0,
  15, 1, 4, 22, 17, 1, 2, 11, 15, 12, 2, 11, 5, 1, 4, 22, 5, 1, 2, 11, 7, 12, 2, 11,
  11, 13, 8, 9, 11, 16, 8, 3, 0, 0, 0, 0, 6, 1, 6, 9, 8, 1, 2, 9, 0, 0, 0, 0,
  11, 4, 3, 18, 11, 10, 3, 6, 0, 0, 0, 0, 5, 8, 12, 6, 5, 8, 6, 3, 11, 11, 6, 3,
  15, 7, 5, 8, 15, 11, 5, 4, 0, 0, 0, 0, 4, 7, 5, 8, 4, 11, 5, 4, 0, 0, 0, 0,
  12, 6, 6, 12, 15, 6, 3, 6, 12, 12, 3, 6, 6, 6, 6, 12, 6, 6, 3, 6, 9, 12, 3, 6,
  5, 9, 14, 8, 12, 9, 7, 4, 5, 13, 7, 4, 9, 1, 3, 14, 9, 8, 3, 7, 0, 0, 0, 0,
  12, 6, 6, 12, 12, 10, 6, 4, 0, 0, 0, 0, 4, 5, 4, 18, 4, 5, 2, 9, 6, 14, 2, 9,
  4, 6, 16, 18, 4, 12, 16, 6, 0, 0, 0, 0, 5, 4, 7, 20, 5, 14, 7, 10, 0, 0, 0, 0,
  14, 8, 8, 12, 14, 14, 8, 6, 0, 0, 0, 0, 9, 10, 6, 14, 9, 10, 3, 7, 12, 17, 3, 7,
  9, 5, 9, 6, 12, 5, 3, 6, 0, 0, 0, 0, 9, 4, 3, 18, 10, 4, 1, 18, 0, 0, 0, 0,
  1, 4, 22, 14, 12, 4, 11, 7, 1, 11, 11, 7, 2, 7, 18, 2, 2, 8, 18, 1, 0, 0, 0, 0,
  12, 6, 6, 12, 12, 10, 6, 4, 0, 0, 0, 0, 6, 5, 9, 7, 9, 5, 3, 7, 0, 0, 0, 0,
  12, 7, 4, 12, 12, 13, 4, 6, 0, 0, 0, 0, 8, 7, 4, 12, 8, 13, 4, 6, 0, 0, 0, 0,
  7, 2, 10, 22, 7, 13, 10, 11, 0, 0, 0, 0, 0, 1, 3, 20, 1, 1, 1, 20, 0, 0, 0, 0,
  4, 13, 18, 4, 13, 13, 9, 2, 4, 15, 9, 2, 2, 13, 18, 4, 2, 13, 9, 2, 11, 15, 9, 2,
  15, 15, 9, 6, 15, 17, 9, 2, 0, 0, 0, 0, 0, 15, 9, 6, 0, 17, 9, 2, 0, 0, 0, 0,
  6, 0, 18, 24, 15, 0, 9, 12, 6, 12, 9, 12, 6, 6, 6, 12, 6, 10, 6, 4, 0, 0, 0, 0,
  8, 7, 10, 4, 8, 9, 10, 2, 0, 0, 0, 0, 1, 9, 18, 6, 1, 9, 9, 3, 10, 12, 9, 3,
  6, 6, 18, 3, 6, 7, 18, 1, 0, 0, 0, 0, 7, 7, 9, 8, 10, 7, 3, 8, 0, 0, 0, 0,
  10, 12, 6, 12, 12, 12, 2, 12, 0, 0, 0, 0, 3, 14, 18, 3, 3, 15, 18, 1, 0, 0, 0, 0,
  15, 17, 9, 7, 18, 17, 3, 7, 0, 0, 0, 0, 1, 12, 10, 6, 1, 14, 10, 2, 0, 0, 0, 0,
  15, 17, 9, 7, 18, 17, 3, 7, 0, 0, 0, 0, 10, 3, 3, 19, 11, 3, 1, 19, 0, 0, 0, 0,
  15, 17, 9, 7, 18, 17, 3, 7, 0, 0, 0, 0, 6, 1, 11, 9, 6, 4, 11, 3, 0, 0, 0, 0,
  15, 17, 9, 7, 18, 17, 3, 7, 0, 0, 0, 0, 6, 5, 11, 6, 6, 8, 11, 3, 0, 0, 0, 0,
  16, 7, 8, 5, 16, 7, 4, 5, 0, 0, 0, 0, 2, 4, 20, 19, 12, 4, 10, 19, 0, 0, 0, 0,
  2, 1, 21, 6, 9, 1, 7, 6, 0, 0, 0, 0, 6, 5, 12, 14, 6, 5, 6, 7, 12, 12, 6, 7,
  9, 0, 6, 9, 11, 0, 2, 9, 0, 0, 0, 0, 2, 11, 8, 5, 6, 11, 4, 5, 0, 0, 0, 0,
  16, 7, 8, 5, 16, 7, 4, 5, 0, 0, 0, 0, 0, 7, 8, 5, 4, 7, 4, 5, 0, 0, 0, 0,
  15, 17, 9, 7, 18, 17, 3, 7, 0, 0, 0, 0, 8, 6, 8, 10, 8, 6, 4, 5, 12, 11, 4, 5,
  15, 15, 9, 9, 18, 15, 3, 9, 0, 0, 0, 0, 0, 15, 9, 9, 3, 15, 3, 9, 0, 0, 0, 0,
  12, 10, 9, 7, 15, 10, 3, 7, 0, 0, 0, 0, 3, 10, 9, 7, 6, 10, 3, 7, 0, 0, 0, 0,
  13, 15, 10, 8, 18, 15, 5, 4, 13, 19, 5, 4, 0, 1, 6, 12, 0, 1, 3, 6, 3, 7, 3, 6,
  10, 0, 6, 12, 13, 0, 3, 6, 10, 6, 3, 6, 7, 0, 10, 12, 7, 0, 5, 6, 12, 6, 5, 6,
  4, 1, 16, 8, 4, 1, 8, 8, 0, 0, 0, 0, 0, 21, 19, 3, 0, 22, 19, 1, 0, 0, 0, 0,
  6, 9, 18, 4, 15, 9, 9, 2, 6, 11, 9, 2, 3, 4, 9, 6, 3, 6, 9, 2, 0, 0, 0, 0,
  9, 1, 6, 15, 9, 6, 6, 5, 0, 0, 0, 0, 5, 9, 6, 6, 8, 9, 3, 6, 0, 0, 0, 0,
  5, 1, 14, 9, 5, 4, 14, 3, 0, 0, 0, 0, 3, 0, 8, 20, 3, 0, 4, 10, 7, 10, 4, 10,
  5, 0, 7, 9, 5, 3, 7, 3, 0, 0, 0, 0, 6, 6, 12, 5, 10, 6, 4, 5, 0, 0, 0, 0,
  0, 1, 8, 14, 4, 1, 4, 14, 0, 0, 0, 0, 2, 12, 22, 4, 2, 14, 22, 2, 0, 0, 0, 0,
  8, 17, 6, 6, 8, 20, 6, 3, 0, 0, 0, 0, 18, 1, 6, 7, 18, 1, 3, 7, 0, 0, 0, 0,
  0, 0, 6, 6, 3, 0, 3, 6, 0, 0, 0, 0, 4, 6, 17, 18, 4, 12, 17, 6, 0, 0, 0, 0,
  6, 0, 12, 6, 6, 0, 6, 3, 12, 3, 6, 3, 4, 7, 18, 4, 13, 7, 9, 2, 4, 9, 9, 2,
  4, 12, 10, 6, 4, 14, 10, 2, 0, 0, 0, 0, 7, 9, 10, 12, 12, 9, 5, 6, 7, 15, 5, 6,
  0, 1, 24, 3, 8, 1, 8, 3, 0, 0, 0, 0, 13, 11, 6, 6, 13, 11, 3, 6, 0, 0, 0, 0,
  5, 11, 6, 6, 8, 11, 3, 6, 0, 0, 0, 0, 3, 10, 19, 3, 3, 11, 19, 1, 0, 0, 0, 0,
  0, 2, 6, 9, 0, 5, 6, 3, 0, 0, 0, 0, 14, 16, 10, 6, 14, 18, 10, 2, 0, 0, 0, 0,
  0, 16, 10, 6, 0, 18, 10, 2, 0, 0, 0, 0, 14, 13, 9, 6, 14, 15, 9, 2, 0, 0, 0, 0,
  0, 16, 18, 3, 0, 17, 18, 1, 0, 0, 0, 0, 6, 16, 18, 3, 6, 17, 18, 1, 0, 0, 0, 0,
  0, 18, 9, 6, 0, 20, 9, 2, 0, 0, 0, 0, 14, 13, 9, 6, 14, 15, 9, 2, 0, 0, 0, 0,
  6, 2, 6, 9, 8, 2, 2, 9, 0, 0, 0, 0, 15, 8, 4, 12, 15, 8, 2, 12, 0, 0, 0, 0,
  8, 13, 8, 8, 8, 17, 8, 4, 0, 0, 0, 0, 4, 20, 18, 3, 10, 20, 6, 3, 0, 0, 0, 0,
  5, 8, 4, 12, 7, 8, 2, 12, 0, 0, 0, 0, 7, 7, 12, 3, 7, 7, 6, 3, 0, 0, 0, 0,
  10, 6, 4, 9, 12, 6, 2, 9, 0, 0, 0, 0, 5, 20, 18, 3, 11, 20, 6, 3, 0, 0, 0, 0,
  1, 20, 18, 3, 7, 20, 6, 3, 0, 0, 0, 0, 18, 1, 6, 20, 21, 1, 3, 10, 18, 11, 3, 10,
  0, 1, 6, 20, 0, 1, 3, 10, 3, 11, 3, 10, 13, 3, 4, 18, 15, 3, 2, 9, 13, 12, 2, 9,
  0, 2, 6, 12, 0, 6, 6, 4, 0, 0, 0, 0, 12, 9, 12, 6, 18, 9, 6, 3, 12, 12, 6, 3,
  7, 3, 4, 18, 7, 3, 2, 9, 9, 12, 2, 9, 14, 0, 6, 9, 16, 0, 2, 9, 0, 0, 0, 0,
  0, 9, 12, 6, 0, 9, 6, 3, 6, 12, 6, 3, 14, 4, 8, 20, 18, 4, 4, 10, 14, 14, 4, 10,
  2, 4, 8, 20, 2, 4, 4, 10, 6, 14, 4, 10, 14, 13, 9, 6, 14, 15, 9, 2, 0, 0, 0, 0,
  1, 13, 9, 6, 1, 15, 9, 2, 0, 0, 0, 0, 3, 15, 18, 3, 9, 15, 6, 3, 0, 0, 0, 0,
  5, 13, 9, 6, 5, 15, 9, 2, 0, 0, 0, 0, 5, 0, 18, 3, 5, 1, 18, 1, 0, 0, 0, 0,
  8, 2, 6, 7, 11, 2, 3, 7, 0, 0, 0, 0, 9, 1, 9, 6, 12, 1, 3, 6, 0, 0, 0, 0,
  6, 1, 9, 6, 9, 1, 3, 6, 0, 0, 0, 0, 5, 6, 14, 6, 12, 6, 7, 3, 5, 9, 7, 3,
  8, 2, 6, 13, 10, 2, 2, 13, 0, 0, 0, 0, 6, 11, 12, 6, 12, 11, 6, 3, 6, 14, 6, 3,
  3, 1, 18, 15, 9, 1, 6, 15, 0, 0, 0, 0, 13, 0, 6, 7, 13, 0, 3, 7, 0, 0, 0, 0,
  3, 3, 16, 6, 3, 6, 16, 3, 0, 0, 0, 0, 12, 1, 3, 12, 12, 7, 3, 6, 0, 0, 0, 0,
  7, 7, 6, 9, 9, 7, 2, 9, 0, 0, 0, 0, 13, 0, 4, 24, 13, 0, 2, 24, 0, 0, 0, 0,
  7, 0, 4, 24, 9, 0, 2, 24, 0, 0, 0, 0, 11, 9, 5, 12, 11, 13, 5, 4, 0, 0, 0, 0,
  7, 15, 9, 6, 7, 17, 9, 2, 0, 0, 0, 0, 5, 7, 18, 6, 5, 9, 18, 2, 0, 0, 0, 0,
  8, 9, 5, 12, 8, 13, 5, 4, 0, 0, 0, 0, 4, 17, 17, 6, 4, 19, 17, 2, 0, 0, 0, 0,
  0, 3, 18, 14, 0, 3, 9, 7, 9, 10, 9, 7, 0, 1, 24, 2, 0, 2, 24, 1, 0, 0, 0, 0,
  0, 15, 18, 3, 0, 16, 18, 1, 0, 0, 0, 0, 9, 0, 6, 9, 11, 0, 2, 9, 0, 0, 0, 0,
  3, 3, 14, 12, 3, 9, 14, 6, 0, 0, 0, 0, 12, 1, 3, 12, 12, 7, 3, 6, 0, 0, 0, 0,
  8, 0, 6, 9, 10, 0, 2, 9, 0, 0, 0, 0, 10, 6, 6, 10, 12, 6, 2, 10, 0, 0, 0, 0,
  5, 0, 6, 9, 7, 0, 2, 9, 0, 0, 0, 0, 2, 0, 21, 7, 9, 0, 7, 7, 0, 0, 0, 0,
  6, 11, 12, 5, 10, 11, 4, 5, 0, 0, 0, 0, 8, 7, 9, 8, 11, 7, 3, 8, 0, 0, 0, 0,
  9, 6, 6, 18, 9, 6, 3, 9, 12, 15, 3, 9, 15, 14, 8, 10, 19, 14, 4, 5, 15, 19, 4, 5,
  1, 14, 8, 10, 1, 14, 4, 5, 5, 19, 4, 5, 11, 0, 8, 10, 15, 0, 4, 5, 11, 5, 4, 5,
  5, 0, 8, 10, 5, 0, 4, 5, 9, 5, 4, 5, 6, 1, 12, 5, 6, 1, 6, 5, 0, 0, 0, 0,
  1, 12, 18, 2, 10, 12, 9, 2, 0, 0, 0, 0, 2, 8, 20, 6, 12, 8, 10, 3, 2, 11, 10, 3,
  7, 6, 9, 7, 10, 6, 3, 7, 0, 0, 0, 0, 10, 5, 8, 16, 14, 5, 4, 8, 10, 13, 4, 8,
  3, 9, 16, 8, 3, 9, 8, 4, 11, 13, 8, 4, 7, 8, 10, 4, 7, 8, 5, 4, 0, 0, 0, 0,
  7, 12, 10, 8, 7, 12, 5, 4, 12, 16, 5, 4, 9, 19, 15, 4, 14, 19, 5, 4, 0, 0, 0, 0,
  1, 0, 18, 9, 7, 0, 6, 9, 0, 0, 0, 0, 13, 4, 10, 8, 18, 4, 5, 4, 13, 8, 5, 4,
  3, 16, 18, 4, 9, 16, 6, 4, 0, 0, 0, 0, 8, 7, 10, 12, 13, 7, 5, 6, 8, 13, 5, 6,
  6, 7, 10, 12, 6, 7, 5, 6, 11, 13, 5, 6, 4, 6, 18, 7, 10, 6, 6, 7, 0, 0, 0, 0,
  0, 17, 18, 3, 0, 18, 18, 1, 0, 0, 0, 0, 3, 17, 18, 3, 3, 18, 18, 1, 0, 0, 0, 0,
  2, 4, 6, 10, 4, 4, 2, 10, 0, 0, 0, 0, 16, 0, 8, 24, 16, 0, 4, 24, 0, 0, 0, 0,
  4, 0, 8, 15, 8, 0, 4, 15, 0, 0, 0, 0, 16, 0, 8, 24, 16, 0, 4, 24, 0, 0, 0, 0,
  1, 4, 18, 9, 7, 4, 6, 9, 0, 0, 0, 0, 15, 12, 9, 6, 15, 14, 9, 2, 0, 0, 0, 0,
  3, 9, 18, 6, 3, 9, 9, 3, 12, 12, 9, 3, 18, 5, 6, 9, 18, 8, 6, 3, 0, 0, 0, 0,
  0, 5, 6, 9, 0, 8, 6, 3, 0, 0, 0, 0, 4, 7, 18, 4, 13, 7, 9, 2, 4, 9, 9, 2,
  2, 1, 12, 20, 2, 1, 6, 10, 8, 11, 6, 10, 17, 0, 6, 23, 17, 0, 3, 23, 0, 0, 0, 0,
  1, 6, 2, 18, 1, 15, 2, 9, 0, 0, 0, 0, 8, 8, 10, 6, 8, 10, 10, 2, 0, 0, 0, 0,
  0, 6, 20, 6, 0, 6, 10, 3, 10, 9, 10, 3, 11, 12, 12, 5, 15, 12, 4, 5, 0, 0, 0, 0,
  0, 4, 3, 19, 1, 4, 1, 19, 0, 0, 0, 0, 19, 1, 3, 18, 20, 1, 1, 18, 0, 0, 0, 0,
  2, 1, 3, 18, 3, 1, 1, 18, 0, 0, 0, 0, 3, 10, 18, 3, 9, 10, 6, 3, 0, 0, 0, 0,
  4, 4, 10, 9, 9, 4, 5, 9, 0, 0, 0, 0, 7, 13, 14, 7, 7, 13, 7, 7, 0, 0, 0, 0,
  3, 13, 14, 7, 10, 13, 7, 7, 0, 0, 0, 0, 8, 15, 9, 6, 11, 15, 3, 6, 0, 0, 0, 0,
  4, 14, 8, 10, 4, 14, 4, 5, 8, 19, 4, 5, 10, 14, 4, 10, 10, 19, 4, 5, 0, 0, 0, 0,
  3, 8, 5, 16, 3, 16, 5, 8, 0, 0, 0, 0, 15, 10, 9, 6, 15, 12, 9, 2, 0, 0, 0, 0,
  0, 10, 9, 6, 0, 12, 9, 2, 0, 0, 0, 0, 6, 7, 12, 9, 6, 10, 12, 3, 0, 0, 0, 0,
  9, 10, 5, 8, 9, 14, 5, 4, 0, 0, 0, 0, 12, 1, 3, 12, 12, 7, 3, 6, 0, 0, 0, 0,
  8, 15, 6, 9, 10, 15, 2, 9, 0, 0, 0, 0, 16, 6, 7, 6, 16, 9, 7, 3, 0, 0, 0, 0,
  8, 1, 4, 22, 10, 1, 2, 22, 0, 0, 0, 0, 6, 6, 14, 3, 6, 6, 7, 3, 0, 0, 0, 0,
  0, 18, 19, 3, 0, 19, 19, 1, 0, 0, 0, 0, 17, 0, 6, 24, 17, 0, 3, 24, 0, 0, 0, 0,
  0, 13, 15, 6, 5, 13, 5, 6, 0, 0, 0, 0, 9, 6, 10, 14, 14, 6, 5, 7, 9, 13, 5, 7,
  1, 6, 8, 10, 1, 6, 4, 5, 5, 11, 4, 5, 7, 6, 12, 5, 7, 6, 6, 5, 0, 0, 0, 0,
  7, 7, 9, 6, 10, 7, 3, 6, 0, 0, 0, 0, 7, 8, 14, 14, 14, 8, 7, 7, 7, 15, 7, 7,
  3, 8, 14, 14, 3, 8, 7, 7, 10, 15, 7, 7, 9, 8, 13, 4, 9, 10, 13, 2, 0, 0, 0, 0,
  3, 2, 6, 12, 3, 2, 3, 6, 6, 8, 3, 6, 6, 10, 17, 6, 6, 13, 17, 3, 0, 0, 0, 0,
  1, 10, 17, 6, 1, 13, 17, 3, 0, 0, 0, 0, 16, 7, 8, 9, 16, 10, 8, 3, 0, 0, 0, 0,
  0, 7, 8, 9, 0, 10, 8, 3, 0, 0, 0, 0, 0, 9, 24, 10, 12, 9, 12, 5, 0, 14, 12, 5,
  3, 2, 15, 8, 8, 2, 5, 8, 0, 0, 0, 0, 4, 2, 18, 8, 10, 2, 6, 8, 0, 0, 0, 0,
  0, 1, 18, 4, 0, 1, 9, 2, 9, 3, 9, 2, 20, 2, 3, 18, 21, 2, 1, 18, 0, 0, 0, 0,
  1, 3, 3, 19, 2, 3, 1, 19, 0, 0, 0, 0, 18, 8, 6, 16, 20, 8, 2, 16, 0, 0, 0, 0,
  0, 8, 6, 16, 2, 8, 2, 16, 0, 0, 0, 0, 8, 18, 11, 6, 8, 20, 11, 2, 0, 0, 0, 0,
  4, 6, 12, 5, 8, 6, 4, 5, 0, 0, 0, 0, 7, 6, 12, 5, 11, 6, 4, 5, 0, 0, 0, 0,
  6, 3, 9, 6, 9, 3, 3, 6, 0, 0, 0, 0, 7, 6, 12, 5, 7, 6, 6, 5, 0, 0, 0, 0,
  9, 8, 6, 7, 12, 8, 3, 7, 0, 0, 0, 0, 8, 2, 9, 6, 11, 2, 3, 6, 0, 0, 0, 0,
  8, 14, 6, 9, 8, 17, 6, 3, 0, 0, 0, 0, 8, 2, 9, 6, 11, 2, 3, 6, 0, 0, 0, 0,
  4, 3, 16, 20, 4, 3, 8, 10, 12, 13, 8, 10, 7, 6, 10, 12, 12, 6, 5, 6, 7, 12, 5, 6,
  0, 2, 7, 12, 0, 6, 7, 4, 0, 0, 0, 0, 12, 17, 11, 6, 12, 19, 11, 2, 0, 0, 0, 0,
  4, 7, 12, 8, 4, 7, 6, 4, 10, 11, 6, 4, 8, 11, 8, 10, 12, 11, 4, 5, 8, 16, 4, 5,
  9, 1, 4, 9, 11, 1, 2, 9, 0, 0, 0, 0, 14, 0, 3, 22, 15, 0, 1, 22, 0, 0, 0, 0,
  7, 0, 3, 22, 8, 0, 1, 22, 0, 0, 0, 0, 4, 7, 18, 4, 13, 7, 9, 2, 4, 9, 9, 2,
  10, 2, 4, 15, 10, 7, 4, 5, 0, 0, 0, 0, 12, 1, 3, 12, 12, 7, 3, 6, 0, 0, 0, 0,
  0, 0, 18, 13, 9, 0, 9, 13, 0, 0, 0, 0, 16, 0, 3, 24, 17, 0, 1, 24, 0, 0, 0, 0,
  5, 0, 3, 24, 6, 0, 1, 24, 0, 0, 0, 0, 10, 15, 5, 8, 10, 19, 5, 4, 0, 0, 0, 0,
  2, 18, 18, 2, 2, 19, 18, 1, 0, 0, 0, 0, 2, 8, 20, 3, 2, 9, 20, 1, 0, 0, 0, 0,
  7, 6, 9, 6, 7, 8, 9, 2, 0, 0, 0, 0, 3, 2, 19, 10, 3, 7, 19, 5, 0, 0, 0, 0,
  2, 7, 19, 3, 2, 8, 19, 1, 0, 0, 0, 0, 15, 6, 9, 4, 15, 8, 9, 2, 0, 0, 0, 0,
  2, 2, 18, 8, 8, 2, 6, 8, 0, 0, 0, 0, 10, 9, 14, 4, 10, 9, 7, 4, 0, 0, 0, 0,
  4, 4, 6, 16, 7, 4, 3, 16, 0, 0, 0, 0, 15, 8, 9, 16, 18, 8, 3, 16, 0, 0, 0, 0,
  0, 8, 9, 16, 3, 8, 3, 16, 0, 0, 0, 0, 18, 0, 6, 14, 20, 0, 2, 14, 0, 0, 0, 0,
  0, 0, 6, 14, 2, 0, 2, 14, 0, 0, 0, 0, 15, 0, 6, 22, 17, 0, 2, 22, 0, 0, 0, 0,
  3, 0, 6, 22, 5, 0, 2, 22, 0, 0, 0, 0, 12, 2, 12, 20, 16, 2, 4, 20, 0, 0, 0, 0,
  0, 2, 12, 20, 4, 2, 4, 20, 0, 0, 0, 0, 11, 6, 4, 9, 11, 6, 2, 9, 0, 0, 0, 0,
  9, 0, 6, 16, 12, 0, 3, 16, 0, 0, 0, 0, 12, 1, 3, 12, 12, 7, 3, 6, 0, 0, 0, 0,
  3, 4, 18, 6, 3, 4, 9, 3, 12, 7, 9, 3, 5, 5, 16, 8, 13, 5, 8, 4, 5, 9, 8, 4,
  0, 13, 10, 6, 0, 15, 10, 2, 0, 0, 0, 0, 8, 14, 9, 6, 8, 16, 9, 2, 0, 0, 0, 0,
  6, 2, 9, 6, 9, 2, 3, 6, 0, 0, 0, 0, 14, 1, 10, 8, 19, 1, 5, 4, 14, 5, 5, 4,
  9, 1, 3, 12, 9, 7, 3, 6, 0, 0, 0, 0, 6, 4, 12, 9, 6, 7, 12, 3, 0, 0, 0, 0,
  6, 5, 12, 6, 10, 5, 4, 6, 0, 0, 0, 0, 1, 1, 8, 5, 5, 1, 4, 5, 0, 0, 0, 0,
  12, 12, 6, 8, 12, 16, 6, 4, 0, 0, 0, 0, 3, 12, 12, 6, 3, 14, 12, 2, 0, 0, 0, 0,
  9, 18, 12, 6, 15, 18, 6, 3, 9, 21, 6, 3, 4, 13, 6, 6, 4, 16, 6, 3, 0, 0, 0, 0,
  11, 3, 7, 18, 11, 12, 7, 9, 0, 0, 0, 0, 3, 9, 18, 3, 9, 9, 6, 3, 0, 0, 0, 0,
  5, 3, 19, 2, 5, 4, 19, 1, 0, 0, 0, 0, 4, 2, 12, 6, 4, 2, 6, 3, 10, 5, 6, 3,
  9, 6, 6, 9, 11, 6, 2, 9, 0, 0, 0, 0, 8, 6, 6, 9, 10, 6, 2, 9, 0, 0, 0, 0,
  16, 9, 5, 15, 16, 14, 5, 5, 0, 0, 0, 0, 3, 9, 5, 15, 3, 14, 5, 5, 0, 0, 0, 0,
  6, 6, 14, 6, 13, 6, 7, 3, 6, 9, 7, 3, 8, 6, 3, 14, 8, 13, 3, 7, 0, 0, 0, 0,
  0, 16, 24, 5, 8, 16, 8, 5, 0, 0, 0, 0, 0, 20, 20, 3, 10, 20, 10, 3, 0, 0, 0, 0,
  5, 10, 18, 2, 5, 11, 18, 1, 0, 0, 0, 0, 0, 6, 6, 10, 2, 6, 2, 10, 0, 0, 0, 0,
  2, 1, 20, 3, 2, 2, 20, 1, 0, 0, 0, 0, 9, 13, 6, 11, 11, 13, 2, 11, 0, 0, 0, 0,
  9, 15, 6, 8, 9, 19, 6, 4, 0, 0, 0, 0, 9, 12, 6, 9, 9, 15, 6, 3, 0, 0, 0, 0,
  5, 11, 18, 2, 5, 12, 18, 1, 0, 0, 0, 0, 2, 6, 15, 6, 2, 8, 15, 2, 0, 0, 0, 0,
  6, 0, 18, 3, 6, 1, 18, 1, 0, 0, 0, 0, 5, 0, 3, 18, 6, 0, 1, 18, 0, 0, 0, 0,
  18, 3, 6, 10, 20, 3, 2, 10, 0, 0, 0, 0, 0, 3, 6, 10, 2, 3, 2, 10, 0, 0, 0, 0,
  10, 5, 8, 9, 10, 5, 4, 9, 0, 0, 0, 0, 6, 5, 8, 9, 10, 5, 4, 9, 0, 0, 0, 0,
  3, 2, 20, 3, 3, 3, 20, 1, 0, 0, 0, 0, 5, 2, 13, 4, 5, 4, 13, 2, 0, 0, 0, 0,
  17, 0, 7, 14, 17, 7, 7, 7, 0, 0, 0, 0, 0, 0, 7, 14, 0, 7, 7, 7, 0, 0, 0, 0,
  9, 11, 10, 6, 9, 11, 5, 6, 0, 0, 0, 0, 5, 11, 10, 6, 10, 11, 5, 6, 0, 0, 0, 0,
  11, 6, 3, 18, 11, 12, 3, 6, 0, 0, 0, 0, 0, 16, 18, 3, 0, 17, 18, 1, 0, 0, 0, 0,
  6, 16, 18, 3, 6, 17, 18, 1, 0, 0, 0, 0, 4, 6, 9, 10, 4, 11, 9, 5, 0, 0, 0, 0,
  9, 7, 15, 4, 9, 9, 15, 2, 0, 0, 0, 0, 5, 6, 12, 6, 5, 6, 6, 3, 11, 9, 6, 3,
  6, 1, 12, 9, 6, 4, 12, 3, 0, 0, 0, 0, 7, 9, 6, 12, 7, 9, 3, 6, 10, 15, 3, 6,
  11, 5, 13, 6, 11, 7, 13, 2, 0, 0, 0, 0, 1, 11, 22, 13, 12, 11, 11, 13, 0, 0, 0, 0,
  18, 8, 6, 6, 18, 11, 6, 3, 0, 0, 0, 0, 0, 8, 6, 6, 0, 11, 6, 3, 0, 0, 0, 0,
  0, 6, 24, 3, 0, 7, 24, 1, 0, 0, 0, 0, 0, 5, 10, 6, 0, 7, 10, 2, 0, 0, 0, 0,
  6, 7, 18, 3, 6, 8, 18, 1, 0, 0, 0, 0, 0, 0, 10, 6, 0, 2, 10, 2, 0, 0, 0, 0,
  19, 0, 3, 19, 20, 0, 1, 19, 0, 0, 0, 0, 4, 6, 12, 16, 4, 6, 6, 8, 10, 14, 6, 8,
  19, 6, 4, 18, 21, 6, 2, 9, 19, 15, 2, 9, 1, 6, 4, 18, 1, 6, 2, 9, 3, 15, 2, 9,
  3, 21, 18, 3, 3, 22, 18, 1, 0, 0, 0, 0, 0, 19, 9, 4, 0, 21, 9, 2, 0, 0, 0, 0,
  12, 18, 12, 6, 18, 18, 6, 3, 12, 21, 6, 3, 7, 18, 9, 4, 7, 20, 9, 2, 0, 0, 0, 0,
  12, 16, 10, 8, 17, 16, 5, 4, 12, 20, 5, 4, 2, 16, 10, 8, 2, 16, 5, 4, 7, 20, 5, 4,
  14, 0, 10, 12, 19, 0, 5, 6, 14, 6, 5, 6, 0, 0, 10, 12, 0, 0, 5, 6, 5, 6, 5, 6,
  15, 14, 9, 6, 15, 16, 9, 2, 0, 0, 0, 0, 0, 14, 9, 6, 0, 16, 9, 2, 0, 0, 0, 0,
  14, 14, 10, 6, 14, 16, 10, 2, 0, 0, 0, 0, 0, 14, 10, 6, 0, 16, 10, 2, 0, 0, 0, 0,
  5, 18, 18, 2, 5, 19, 18, 1, 0, 0, 0, 0, 0, 18, 18, 3, 0, 19, 18, 1, 0, 0, 0, 0,
  3, 5, 18, 12, 12, 5, 9, 6, 3, 11, 9, 6, 5, 3, 7, 9, 5, 6, 7, 3, 0, 0, 0, 0,
  4, 0, 19, 15, 4, 5, 19, 5, 0, 0, 0, 0, 3, 0, 16, 4, 3, 2, 16, 2, 0, 0, 0, 0,
  4, 12, 16, 12, 4, 12, 8, 12, 0, 0, 0, 0, 4, 3, 12, 15, 10, 3, 6, 15, 0, 0, 0, 0,
  16, 4, 2, 19, 16, 4, 1, 19, 0, 0, 0, 0, 6, 4, 2, 19, 7, 4, 1, 19, 0, 0, 0, 0,
  13, 14, 8, 10, 17, 14, 4, 5, 13, 19, 4, 5, 3, 14, 8, 10, 3, 14, 4, 5, 7, 19, 4, 5,
  12, 6, 3, 18, 12, 12, 3, 6, 0, 0, 0, 0, 5, 11, 12, 6, 5, 11, 6, 3, 11, 14, 6, 3,
  10, 5, 8, 10, 14, 5, 4, 5, 10, 10, 4, 5, 6, 4, 12, 10, 6, 4, 6, 5, 12, 9, 6, 5,
  6, 8, 18, 10, 15, 8, 9, 5, 6, 13, 9, 5, 0, 8, 18, 10, 0, 8, 9, 5, 9, 13, 9, 5,
  12, 6, 3, 18, 12, 12, 3, 6, 0, 0, 0, 0, 0, 14, 18, 3, 0, 15, 18, 1, 0, 0, 0, 0,
  12, 6, 3, 18, 12, 12, 3, 6, 0, 0, 0, 0, 9, 6, 3, 18, 9, 12, 3, 6, 0, 0, 0, 0,
  6, 14, 18, 3, 6, 15, 18, 1, 0, 0, 0, 0, 0, 5, 18, 3, 0, 6, 18, 1, 0, 0, 0, 0,
  2, 5, 22, 3, 2, 6, 22, 1, 0, 0, 0, 0, 0, 0, 21, 10, 7, 0, 7, 10, 0, 0, 0, 0,
  6, 3, 18, 17, 12, 3, 6, 17, 0, 0, 0, 0, 0, 3, 18, 17, 6, 3, 6, 17, 0, 0, 0, 0,
  0, 12, 24, 11, 8, 12, 8, 11, 0, 0, 0, 0, 4, 10, 16, 6, 4, 13, 16, 3, 0, 0, 0, 0,
  12, 8, 6, 8, 12, 12, 6, 4, 0, 0, 0, 0, 6, 14, 8, 7, 10, 14, 4, 7, 0, 0, 0, 0,
  15, 10, 6, 14, 18, 10, 3, 7, 15, 17, 3, 7, 3, 10, 6, 14, 3, 10, 3, 7, 6, 17, 3, 7,
  6, 12, 18, 2, 6, 13, 18, 1, 0, 0, 0, 0, 5, 8, 10, 6, 5, 10, 10, 2, 0, 0, 0, 0,
  12, 11, 9, 4, 12, 13, 9, 2, 0, 0, 0, 0, 0, 11, 9, 6, 0, 13, 9, 2, 0, 0, 0, 0,
  11, 2, 3, 18, 12, 2, 1, 18, 0, 0, 0, 0, 10, 2, 3, 18, 11, 2, 1, 18, 0, 0, 0, 0,
  9, 12, 6, 10, 11, 12, 2, 10, 0, 0, 0, 0, 1, 10, 6, 9, 1, 13, 6, 3, 0, 0, 0, 0,
  6, 9, 16, 6, 14, 9, 8, 3, 6, 12, 8, 3, 1, 8, 9, 6, 1, 10, 9, 2, 0, 0, 0, 0,
  7, 7, 16, 6, 7, 9, 16, 2, 0, 0, 0, 0, 0, 0, 18, 3, 0, 1, 18, 1, 0, 0, 0, 0,
  10, 0, 6, 9, 12, 0, 2, 9, 0, 0, 0, 0, 9, 5, 6, 6, 12, 5, 3, 6, 0, 0, 0, 0,
  10, 6, 4, 18, 12, 6, 2, 9, 10, 15, 2, 9, 8, 0, 6, 9, 10, 0, 2, 9, 0, 0, 0, 0,
  9, 1, 6, 9, 9, 4, 6, 3, 0, 0, 0, 0, 1, 0, 18, 9, 1, 3, 18, 3, 0, 0, 0, 0,
  0, 3, 24, 3, 0, 4, 24, 1, 0, 0, 0, 0, 6, 14, 9, 4, 6, 16, 9, 2, 0, 0, 0, 0,
  8, 9, 8, 10, 12, 9, 4, 5, 8, 14, 4, 5, 5, 2, 13, 9, 5, 5, 13, 3, 0, 0, 0, 0,
  4, 4, 16, 9, 4, 7, 16, 3, 0, 0, 0, 0, 4, 4, 14, 9, 4, 7, 14, 3, 0, 0, 0, 0,
  8, 5, 9, 6, 8, 7, 9, 2, 0, 0, 0, 0, 1, 7, 16, 6, 1, 9, 16, 2, 0, 0, 0, 0,
  10, 5, 13, 9, 10, 8, 13, 3, 0, 0, 0, 0, 1, 5, 13, 9, 1, 8, 13, 3, 0, 0, 0, 0,
  0, 4, 24, 6, 12, 4, 12, 3, 0, 7, 12, 3, 1, 14, 10, 9, 1, 17, 10, 3, 0, 0, 0, 0,
  5, 17, 18, 3, 5, 18, 18, 1, 0, 0, 0, 0, 0, 16, 18, 3, 0, 17, 18, 1, 0, 0, 0, 0,
  9, 17, 9, 6, 9, 19, 9, 2, 0, 0, 0, 0, 1, 20, 22, 4, 1, 20, 11, 2, 12, 22, 11, 2,
  8, 14, 8, 6, 8, 17, 8, 3, 0, 0, 0, 0, 8, 6, 8, 15, 8, 11, 8, 5, 0, 0, 0, 0,
  5, 4, 18, 3, 5, 5, 18, 1, 0, 0, 0, 0, 9, 3, 5, 10, 9, 8, 5, 5, 0, 0, 0, 0,
  6, 8, 12, 3, 6, 8, 6, 3, 0, 0, 0, 0, 2, 6, 18, 6, 2, 6, 9, 3, 11, 9, 9, 3,
  10, 6, 4, 18, 12, 6, 2, 9, 10, 15, 2, 9, 7, 5, 6, 6, 10, 5, 3, 6, 0, 0, 0, 0,
  14, 5, 2, 18, 14, 14, 2, 9, 0, 0, 0, 0, 8, 5, 2, 18, 8, 14, 2, 9, 0, 0, 0, 0,
  9, 2, 10, 6, 9, 2, 5, 6, 0, 0, 0, 0, 3, 1, 18, 12, 12, 1, 9, 12, 0, 0, 0, 0,
  5, 2, 17, 22, 5, 13, 17, 11, 0, 0, 0, 0, 4, 0, 12, 6, 4, 2, 12, 2, 0, 0, 0, 0,
  6, 9, 16, 6, 14, 9, 8, 3, 6, 12, 8, 3, 9, 0, 5, 18, 9, 9, 5, 9, 0, 0, 0, 0,
  12, 0, 6, 9, 14, 0, 2, 9, 0, 0, 0, 0, 6, 0, 6, 9, 8, 0, 2, 9, 0, 0, 0, 0,
  9, 1, 6, 12, 11, 1, 2, 12, 0, 0, 0, 0, 5, 9, 13, 4, 5, 11, 13, 2, 0, 0, 0, 0,
  5, 8, 19, 3, 5, 9, 19, 1, 0, 0, 0, 0, 9, 9, 6, 8, 9, 13, 6, 4, 0, 0, 0, 0,
  11, 9, 4, 15, 11, 14, 4, 5, 0, 0, 0, 0, 2, 0, 6, 14, 2, 0, 3, 7, 5, 7, 3, 7,
  15, 1, 6, 14, 18, 1, 3, 7, 15, 8, 3, 7, 3, 1, 6, 14, 3, 1, 3, 7, 6, 8, 3, 7,
  3, 20, 18, 4, 12, 20, 9, 2, 3, 22, 9, 2, 5, 0, 4, 20, 5, 0, 2, 10, 7, 10, 2, 10,
  16, 8, 8, 12, 20, 8, 4, 6, 16, 14, 4, 6, 0, 8, 8, 12, 0, 8, 4, 6, 4, 14, 4, 6,
  13, 13, 10, 8, 18, 13, 5, 4, 13, 17, 5, 4, 1, 13, 10, 8, 1, 13, 5, 4, 6, 17, 5, 4,
  15, 8, 4, 15, 15, 13, 4, 5, 0, 0, 0, 0, 5, 8, 4, 15, 5, 13, 4, 5, 0, 0, 0, 0,
  6, 11, 16, 12, 6, 15, 16, 4, 0, 0, 0, 0, 2, 11, 16, 12, 2, 15, 16, 4, 0, 0, 0, 0,
  14, 12, 7, 9, 14, 15, 7, 3, 0, 0, 0, 0, 10, 1, 3, 21, 10, 8, 3, 7, 0, 0, 0, 0,
  13, 11, 9, 4, 13, 13, 9, 2, 0, 0, 0, 0, 3, 10, 17, 9, 3, 13, 17, 3, 0, 0, 0, 0,
  13, 8, 8, 15, 13, 13, 8, 5, 0, 0, 0, 0, 3, 8, 8, 15, 3, 13, 8, 5, 0, 0, 0, 0,
  11, 14, 10, 8, 16, 14, 5, 4, 11, 18, 5, 4, 0, 18, 22, 6, 0, 18, 11, 3, 11, 21, 11, 3,
  0, 16, 24, 4, 0, 16, 12, 4, 0, 0, 0, 0, 6, 20, 12, 3, 12, 20, 6, 3, 0, 0, 0, 0,
  18, 12, 6, 12, 21, 12, 3, 6, 18, 18, 3, 6, 0, 12, 6, 12, 0, 12, 3, 6, 3, 18, 3, 6,
  15, 17, 9, 6, 15, 19, 9, 2, 0, 0, 0, 0, 1, 6, 22, 10, 1, 6, 11, 5, 12, 11, 11, 5,
  15, 17, 9, 6, 15, 19, 9, 2, 0, 0, 0, 0, 0, 18, 18, 2, 0, 19, 18, 1, 0, 0, 0, 0,
  3, 15, 19, 3, 3, 16, 19, 1, 0, 0, 0, 0, 0, 13, 18, 3, 0, 14, 18, 1, 0, 0, 0, 0,
  15, 17, 9, 6, 15, 19, 9, 2, 0, 0, 0, 0, 0, 17, 9, 6, 0, 19, 9, 2, 0, 0, 0, 0,
  12, 17, 9, 6, 12, 19, 9, 2, 0, 0, 0, 0, 3, 17, 9, 6, 3, 19, 9, 2, 0, 0, 0, 0,
  16, 2, 3, 20, 17, 2, 1, 20, 0, 0, 0, 0, 0, 13, 24, 8, 0, 17, 24, 4, 0, 0, 0, 0,
  9, 1, 6, 22, 12, 1, 3, 11, 9, 12, 3, 11);
 HaarRw: Array[0..8738] Of ShortInt = (
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2,
  (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2,
  (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2,
  (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2,
  (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2,
  (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2,
  (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0, (-1), 2, 0,
  (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2,
  (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 2, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 2, (-1), 2, 2,
  (-1), 2, 0, (-1), 2, 0, (-1), 2, 2, (-1), 2, 2, (-1), 3, 0, (-1), 2, 2, (-1), 3, 0, (-1), 2, 0,
  (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 3, 0, (-1), 2, 0,
  (-1), 2, 2);

Type
 TLArr = Array[0..33554431] Of LongInt;
 PLArr = ^TLArr;
 TDArr = Array[0..33554431] Of Double;
 PDArr = ^TDArr;

Var
 HaarInt: PLArr;
 HaarSq: PDArr;
 HaarIntSz, HaarGSz: LongInt;
 HaarG, HaarL: PByteArr;
 HaarOff: Array[0..HAAR_NW * 12 - 1] Of LongInt;
 HaarHX, HaarHY, HaarHW: Array[0..511] Of Integer;
 HaarHN: Integer;
 HaarFrame: LongInt;
 HaarBias: Single = 0.9;

{ Image reduite en niveaux de gris (octets) }
Function HaarGray(Var Fr: TImg; Var GW, GH, R: LongInt): Boolean;
Var
 X, Y, IX, IY, S, P: LongInt;
Begin
 HaarGray := False;
 If Fr.D = Nil Then Exit;
 R := IMax(1, Fr.W Div 320);
 GW := Fr.W Div R;
 GH := Fr.H Div R;
 If HaarGSz < GW * GH Then Begin
  If HaarG <> Nil Then FreeMem(HaarG, HaarGSz);
  If HaarL <> Nil Then FreeMem(HaarL, HaarGSz);
  If HaarInt <> Nil Then FreeMem(HaarInt, HaarIntSz * 4);
  If HaarSq <> Nil Then FreeMem(HaarSq, HaarIntSz * 8);
  HaarGSz := GW * GH;
  HaarIntSz := (GW + 1) * (GH + 1);
  HaarG := PByteArr(MemAlloc(HaarGSz));
  HaarL := PByteArr(MemAlloc(HaarGSz));
  HaarInt := PLArr(MemAlloc(HaarIntSz * 4));
  HaarSq := PDArr(MemAlloc(HaarIntSz * 8));
  If (HaarG = Nil) Or (HaarL = Nil) Or (HaarInt = Nil) Or (HaarSq = Nil) Then
  Begin
   If HaarG <> Nil Then FreeMem(HaarG, HaarGSz);
   If HaarL <> Nil Then FreeMem(HaarL, HaarGSz);
   If HaarInt <> Nil Then FreeMem(HaarInt, HaarIntSz * 4);
   If HaarSq <> Nil Then FreeMem(HaarSq, HaarIntSz * 8);
   HaarG := Nil; HaarL := Nil; HaarInt := Nil; HaarSq := Nil;
   HaarGSz := 0;
   HaarIntSz := 0;
   Exit;
  End;
 End;
 For Y := 0 To GH - 1 Do
  For X := 0 To GW - 1 Do Begin
   S := 0;
   For IY := 0 To R - 1 Do
    For IX := 0 To R - 1 Do Begin
     P := ((Y * R + IY) * Fr.W + X * R + IX) * 3;
     S := S + Fr.D^[P] + 2 * Fr.D^[P + 1] + Fr.D^[P + 2];
    End;
   HaarG^[Y * GW + X] := S Div (4 * R * R);
  End;
 HaarGray := True;
End;

{ Niveau de la pyramide : image reduite d'un facteur Sc (interpolation
  bilineaire), puis images integrales (somme et carres) ; retourne les
  dimensions du niveau }
Procedure HaarLevel(GW, GH: LongInt; Sc: Real; Var LW, LH: LongInt);
Var
 X, Y, Wd, P, X0, Y0, FX, FY, V: LongInt;
 SX, SY: Real;
 Row: LongInt;
 RowSq: Double;
Begin
 LW := Trunc(GW / Sc);
 LH := Trunc(GH / Sc);
 For Y := 0 To LH - 1 Do Begin
  SY := Y * Sc;
  Y0 := Trunc(SY);
  If Y0 > GH - 2 Then Y0 := GH - 2;
  FY := Trunc((SY - Y0) * 256);
  For X := 0 To LW - 1 Do Begin
   SX := X * Sc;
   X0 := Trunc(SX);
   If X0 > GW - 2 Then X0 := GW - 2;
   FX := Trunc((SX - X0) * 256);
   P := Y0 * GW + X0;
   V := (HaarG^[P] * (256 - FX) + HaarG^[P + 1] * FX) * (256 - FY) +
        (HaarG^[P + GW] * (256 - FX) + HaarG^[P + GW + 1] * FX) * FY;
   HaarL^[Y * LW + X] := V Shr 16;
  End;
 End;
 Wd := LW + 1;
 For X := 0 To LW Do Begin HaarInt^[X] := 0; HaarSq^[X] := 0; End;
 For Y := 0 To LH - 1 Do Begin
  Row := 0;
  RowSq := 0;
  HaarInt^[(Y + 1) * Wd] := 0;
  HaarSq^[(Y + 1) * Wd] := 0;
  For X := 0 To LW - 1 Do Begin
   V := HaarL^[Y * LW + X];
   Row := Row + V;
   RowSq := RowSq + V * V;
   HaarInt^[(Y + 1) * Wd + X + 1] := HaarInt^[Y * Wd + X + 1] + Row;
   HaarSq^[(Y + 1) * Wd + X + 1] := HaarSq^[Y * Wd + X + 1] + RowSq;
  End;
 End;
End;

{ Decalages des rectangles (fenetre 24 x 24) pour une largeur integrale Wd }
Procedure HaarOffsets(Wd: LongInt);
Var
 F, K, RX, RY, RW, RH: LongInt;
Begin
 For F := 0 To HAAR_NW - 1 Do
  For K := 0 To 2 Do Begin
   RX := HaarRc[(F * 3 + K) * 4];
   RY := HaarRc[(F * 3 + K) * 4 + 1];
   RW := HaarRc[(F * 3 + K) * 4 + 2];
   RH := HaarRc[(F * 3 + K) * 4 + 3];
   HaarOff[(F * 3 + K) * 4] := RY * Wd + RX;
   HaarOff[(F * 3 + K) * 4 + 1] := RY * Wd + RX + RW;
   HaarOff[(F * 3 + K) * 4 + 2] := (RY + RH) * Wd + RX;
   HaarOff[(F * 3 + K) * 4 + 3] := (RY + RH) * Wd + RX + RW;
  End;
End;

{ Evalue la cascade pour la fenetre dont le coin haut-gauche est Base ;
  E0..E3 : coins de la zone de normalisation, Area : sa surface }
Function HaarWindow(Base, E0, E1, E2, E3: LongInt; Area: Double): Boolean;
Var
 Mean, Var_, Nf, V, St: Double;
 St_, W, WI, K, O: LongInt;
Begin
 HaarWindow := False;
 { variance de la zone de normalisation }
 Mean := (HaarInt^[Base + E3] - HaarInt^[Base + E1] -
          HaarInt^[Base + E2] + HaarInt^[Base + E0]) / Area;
 Var_ := (HaarSq^[Base + E3] - HaarSq^[Base + E1] -
          HaarSq^[Base + E2] + HaarSq^[Base + E0]) / Area - Mean * Mean;
 If Var_ > 0 Then Nf := Sqrt(Var_) Else Nf := 1;
 Nf := Nf * Area;
 WI := 0;
 For St_ := 0 To HAAR_NS - 1 Do Begin
  St := 0;
  For W := 0 To HaarStageCnt[St_] - 1 Do Begin
   V := 0;
   For K := 0 To 2 Do Begin
    If HaarRw[WI * 3 + K] <> 0 Then Begin
     O := (WI * 3 + K) * 4;
     V := V + HaarRw[WI * 3 + K] *
          (HaarInt^[Base + HaarOff[O + 3]] - HaarInt^[Base + HaarOff[O + 1]] -
           HaarInt^[Base + HaarOff[O + 2]] + HaarInt^[Base + HaarOff[O]]);
    End;
   End;
   If V < HaarWT[WI] * Nf Then St := St + HaarWL[WI * 2]
                          Else St := St + HaarWL[WI * 2 + 1];
   Inc(WI);
  End;
  If St < HaarStageThr[St_] - HaarBias Then Exit;
 End;
 HaarWindow := True;
End;

Function HaarSimilar(I, J: Integer): Boolean;
Var
 D: Integer;
Begin
 D := IMax(HaarHW[I], HaarHW[J]);
 HaarSimilar := (Abs(HaarHX[I] - HaarHX[J]) * 10 < D * 3) And
                (Abs(HaarHY[I] - HaarHY[J]) * 10 < D * 3) And
                (HaarHW[I] * 10 < HaarHW[J] * 14) And
                (HaarHW[J] * 10 < HaarHW[I] * 14);
End;

{ Detecte les visages de face : retourne le nombre de visages (cadre de la
  tete et reperes dans L) }
{ Recherche des fenetres : dans tout le cadre (Roi = False) ou seulement
  autour du dernier visage suivi (Roi = True : plus rapide) }
Procedure HaarScan(Var Fr: TImg; GW, GH, R: LongInt; Roi: Boolean);
Var
 LW, LH, Wd, PX, PY, PX0, PX1, PY0, PY1: LongInt;
 Sc: Real;
 RX0, RY0, RX1, RY1: Real;
Begin
 HaarHN := 0;
 RX0 := 0; RY0 := 0; RX1 := Fr.W; RY1 := Fr.H;
 If Roi Then Begin
  RX0 := PrevCx - PrevW * 1.1;
  RX1 := PrevCx + PrevW * 1.1;
  RY0 := PrevCy - PrevW * 1.1;
  RY1 := PrevCy + PrevW * 1.1;
 End;
 { visages d'au moins 1/9 de la largeur du cadre }
 Sc := (Fr.W / 9.0) / (HAAR_WIN * R);
 If Sc < 1.0 Then Sc := 1.0;
 While (GW / Sc >= HAAR_WIN + 2) And (GH / Sc >= HAAR_WIN + 2) Do Begin
  { en mode cible : seulement les tailles proches de celle du visage suivi }
  If (Not Roi) Or ((HAAR_WIN * Sc * R > PrevW * 0.6) And
                   (HAAR_WIN * Sc * R < PrevW * 1.7)) Then Begin
   HaarLevel(GW, GH, Sc, LW, LH);
   Wd := LW + 1;
   HaarOffsets(Wd);
   PX0 := IMax(0, Trunc(RX0 / (R * Sc)) - 1);
   PX1 := IMin(LW - HAAR_WIN - 1, Trunc(RX1 / (R * Sc)));
   PY0 := IMax(0, Trunc(RY0 / (R * Sc)) - 1);
   PY1 := IMin(LH - HAAR_WIN - 1, Trunc(RY1 / (R * Sc)));
   PX0 := PX0 And (Not 1);
   PY0 := PY0 And (Not 1);
   PY := PY0;
   While PY <= PY1 Do Begin
    PX := PX0;
    While PX <= PX1 Do Begin
     If HaarWindow(PY * Wd + PX, Wd + 1, Wd + 23, 23 * Wd + 1, 23 * Wd + 23,
                   484.0) Then
      If HaarHN < 512 Then Begin
       HaarHX[HaarHN] := Round(PX * Sc);
       HaarHY[HaarHN] := Round(PY * Sc);
       HaarHW[HaarHN] := Round(HAAR_WIN * Sc);
       Inc(HaarHN);
      End;
     Inc(PX, 2);
    End;
    Inc(PY, 2);
   End;
  End;
  Sc := Sc * 1.15;
 End;
End;

Function HaarDetect(Var Fr: TImg; Var L: TFaceList; MaxN: Integer): Integer;
Const
 MIN_NEIGH = 3;
Var
 GW, GH, R, LW, LH, Wd, PX, PY, I, J, K, NF, Best, BestN: LongInt;
 Sc: Real;
 Neigh: Array[0..511] Of Integer;
 Used: Array[0..511] Of Boolean;
 SX, SY, SW, Cnt: LongInt;
 Wf, Cx, Hh: LongInt;
 Cand: TFaceList;
 Key: Array[0..MAX_FACES - 1] Of Real;
 T: TFace;
 TK, Pcx, Pcy: Real;
 PL: Array[0..MAX_FACES - 1, 0..5] Of Real;
 PW: Array[0..MAX_FACES - 1] Of Real;
 Wr, Ry: LongInt;
 Est: Array[0..5] Of Real;
 TP: Array[0..5] Of Real;
 TPW: Real;
Begin
 HaarDetect := 0;
 For I := 0 To MAX_FACES - 1 Do L[I].Ok := False;
 If Not HaarGray(Fr, GW, GH, R) Then Exit;
 { en direct, avec un visage suivi : recherche locale (sauf une trame sur 8) ;
   si elle ne trouve rien, recherche dans tout le cadre }
 Inc(HaarFrame);
 If Live And PrevOk And (PrevW > 0) And ((HaarFrame And 7) <> 0) Then Begin
  HaarScan(Fr, GW, GH, R, True);
  If HaarHN < MIN_NEIGH Then HaarScan(Fr, GW, GH, R, False);
 End
 Else HaarScan(Fr, GW, GH, R, False);
 { regroupement des detections voisines }
 For I := 0 To HaarHN - 1 Do Begin
  Neigh[I] := 0;
  Used[I] := False;
  For J := 0 To HaarHN - 1 Do
   If HaarSimilar(I, J) Then Inc(Neigh[I]);
 End;
 NF := 0;
 While NF < MAX_FACES Do Begin
  Best := -1;
  BestN := MIN_NEIGH - 1;
  For I := 0 To HaarHN - 1 Do
   If (Not Used[I]) And (Neigh[I] > BestN) Then Begin
    BestN := Neigh[I];
    Best := I;
   End;
  If Best < 0 Then Break;
  SX := 0; SY := 0; SW := 0; Cnt := 0;
  For J := 0 To HaarHN - 1 Do
   If (Not Used[J]) And HaarSimilar(Best, J) Then Begin
    Inc(SX, HaarHX[J]); Inc(SY, HaarHY[J]); Inc(SW, HaarHW[J]); Inc(Cnt);
    Used[J] := True;
   End;
  Used[Best] := True;
  If Cnt < 1 Then Break;
  { trop petit pour etre un visage utilisable (moins de 1/10 de la largeur) }
  If (SW * R) Div Cnt < Fr.W Div 10 Then Continue;
  { cadre de la tete (pleine resolution) : la fenetre de la cascade va des
    sourcils au menton }
  Wf := (SW * R * 120) Div (Cnt * 100);
  Cx := (SX * 2 * R + SW * R) Div (2 * Cnt);
  Hh := (Wf * 128) Div 100;
  FillChar(T, SizeOf(T), 0);
  T.Ok := True;
  T.X1 := Cx - Wf Div 2;
  T.X2 := T.X1 + Wf - 1;
  T.Y1 := (SY * R) Div Cnt - (Wf * 10) Div 100;
  T.Y2 := T.Y1 + Hh - 1;
  T.Area := Wf * Hh * 6 Div 10;
  { reperes theoriques a partir du cadre de la cascade (yeux a ~34 % de la
    hauteur, bouche a ~84 %) : l'analyse de l'image n'est retenue que si elle
    est proche, sinon elle est ecartee (ombres, cheveux, lunettes) }
  Wr := (SW * R * 105) Div (Cnt * 100);
  Ry := (SY * R) Div Cnt - (Wr * 5) Div 100;
  PL[NF, 0] := Cx - 0.205 * Wr;  PL[NF, 1] := Ry + 0.345 * Wr;
  PL[NF, 2] := Cx + 0.205 * Wr;  PL[NF, 3] := Ry + 0.345 * Wr;
  PL[NF, 4] := Cx;               PL[NF, 5] := Ry + 0.84 * Wr;
  PW[NF] := Wr;
  Cand[NF] := T;
  Key[NF] := BestN * Wf;
  If PrevOk Then Begin
   Pcx := (T.X1 + T.X2) / 2;
   Pcy := (T.Y1 + T.Y2) / 2;
   If (Abs(Pcx - PrevCx) < Wf * 0.6) And (Abs(Pcy - PrevCy) < Hh * 0.6) Then
    Key[NF] := Key[NF] * 2;
  End;
  Inc(NF);
 End;
 For I := 0 To NF - 2 Do
  For J := I + 1 To NF - 1 Do
   If Key[J] > Key[I] Then Begin
    T := Cand[I]; Cand[I] := Cand[J]; Cand[J] := T;
    TK := Key[I]; Key[I] := Key[J]; Key[J] := TK;
    TP := PL[I]; PL[I] := PL[J]; PL[J] := TP;
    TPW := PW[I]; PW[I] := PW[J]; PW[J] := TPW;
   End;
 If NF > MaxN Then NF := MaxN;
 K := 0;
 For I := 0 To NF - 1 Do Begin
  FindLandmarks(Fr, Cand[I]);
  Est[0] := Cand[I].ELx; Est[1] := Cand[I].ELy;
  Est[2] := Cand[I].ERx; Est[3] := Cand[I].ERy;
  Est[4] := Cand[I].Mx;  Est[5] := Cand[I].My;
  For J := 0 To 5 Do
   If Abs(Est[J] - PL[I, J]) < 0.07 * PW[I] Then
    Est[J] := (Est[J] + PL[I, J]) / 2
   Else Est[J] := PL[I, J];
  Cand[I].ELx := Est[0]; Cand[I].ELy := Est[1];
  Cand[I].ERx := Est[2]; Cand[I].ERy := Est[3];
  Cand[I].Mx := Est[4];  Cand[I].My := Est[5];
  L[K] := Cand[I];
  Inc(K);
 End;
 HaarDetect := K;
End;
{$ENDIF}

Function DetectFacesSkin(Var Fr: TImg; Var L: TFaceList; MaxN: Integer): Integer;
Var
 Comps: Array[0..MAX_COMP - 1] Of TComp;
 Cand: TFaceList;
 Key: Array[0..MAX_COMP - 1] Of Real;
 NC, I, J, NF, K: Integer;
 T: TFace;
 TK: Real;
 Cx, Cy: Real;
 MinArea: LongInt;
Begin
 DetectFacesSkin := 0;
 If (Fr.D = Nil) Or (AMask = Nil) Then Exit;
 For I := 0 To MAX_FACES - 1 Do L[I].Ok := False;
 BuildMask(Fr);
 MinArea := IMax(30, AWd * AHt Div 400);
 NC := LabelComps(Comps, MinArea);
 NF := 0;
 For I := 0 To NC - 1 Do
  If NF < MAX_FACES Then
   If HeadFromComp(I + 1, Comps[I], Cand[NF]) Then Begin
    Key[NF] := Cand[NF].Area;
    If PrevOk Then Begin
     Cx := (Cand[NF].X1 + Cand[NF].X2) / 2;
     Cy := (Cand[NF].Y1 + Cand[NF].Y2) / 2;
     If (Abs(Cx - PrevCx) < (Cand[NF].X2 - Cand[NF].X1) * 0.6) And
        (Abs(Cy - PrevCy) < (Cand[NF].Y2 - Cand[NF].Y1) * 0.6) Then
      Key[NF] := Key[NF] * 2;
    End;
    Inc(NF);
   End;
 { tri par cle decroissante }
 For I := 0 To NF - 2 Do
  For J := I + 1 To NF - 1 Do
   If Key[J] > Key[I] Then Begin
    T := Cand[I]; Cand[I] := Cand[J]; Cand[J] := T;
    TK := Key[I]; Key[I] := Key[J]; Key[J] := TK;
   End;
 If NF > MaxN Then NF := MaxN;
 K := 0;
 For I := 0 To NF - 1 Do Begin
  FindLandmarks(Fr, Cand[I]);
  L[K] := Cand[I];
  Inc(K);
 End;
 DetectFacesSkin := K;
End;

{ Detection des visages : cascade de Haar (Free Pascal) ; la couleur de peau ne
  sert de secours que hors du direct (photos), car elle confond facilement
  le bois, les murs ou les mains avec un visage }
Function DetectFaces(Var Fr: TImg; Var L: TFaceList; MaxN: Integer): Integer;
Var
 N: Integer;
Begin
 {$IFDEF FPC}
 N := HaarDetect(Fr, L, MaxN);
 If (N > 0) Or Live Then Begin
  DetectFaces := N;
  Exit;
 End;
 {$ENDIF}
 DetectFaces := DetectFacesSkin(Fr, L, MaxN);
End;

{ Apprentissage de la couleur de peau a partir d'un visage trouve }
Procedure SkinLearn(Var Fr: TImg; Var F: TFace);
Var
 X, Y, Yy, Cb, Cr, N, SCb, SCr, SS, Sx, X1, X2, Y1, Y2, Wf: LongInt;
 MCb, MCr, VCb, VCr: Real;
Begin
 Wf := F.X2 - F.X1 + 1;
 Sx := IMax(1, Wf Div 40);
 X1 := (F.X1 + F.X2) Div 2 - Wf Div 5;
 X2 := (F.X1 + F.X2) Div 2 + Wf Div 5;
 Y1 := F.Y1 + (Wf * 52) Div 100;
 Y2 := F.Y1 + (Wf * 78) Div 100;
 N := 0; SCb := 0; SCr := 0;
 For Y := Y1 To Y2 Do
  If (Y Mod Sx) = 0 Then
   For X := X1 To X2 Do
    If (X Mod Sx) = 0 Then Begin
     PixYcc(Fr, X, Y, Yy, Cb, Cr);
     If SkinPix(Yy, Cb, Cr) Then Begin
      Inc(N); Inc(SCb, Cb); Inc(SCr, Cr);
     End;
    End;
 If N < 12 Then Exit;
 MCb := SCb / N;
 MCr := SCr / N;
 SkinCb := ClipL(RoundL(SkinCb * 0.9 + MCb * 0.1), 88, 122);
 SkinCr := ClipL(RoundL(SkinCr * 0.9 + MCr * 0.1), 138, 172);
End;

{ Calibrage manuel : la peau est prise autour du point (X, Y). Retourne
  False (sans rien changer) si la couleur n'a pas l'air d'une peau. }
Function SkinSeed(Var Fr: TImg; X, Y: LongInt): Boolean;
Var
 DX, DY, Yy, Cb, Cr, N, SCb, SCr, MCb, MCr: LongInt;
Begin
 N := 0; SCb := 0; SCr := 0;
 For DY := -3 To 3 Do
  For DX := -3 To 3 Do Begin
   PixYcc(Fr, X + DX * 2, Y + DY * 2, Yy, Cb, Cr);
   Inc(N); Inc(SCb, Cb); Inc(SCr, Cr);
  End;
 MCb := SCb Div N;
 MCr := SCr Div N;
 SkinSeed := False;
 If (MCr - MCb < 12) Or (MCb < 80) Or (MCb > 128) Or (MCr < 132) Or
    (MCr > 180) Then Exit;
 SkinCb := MCb;
 SkinCr := MCr;
 SkinDCb := 16;
 SkinDCr := 16;
 SkinSeed := True;
End;

{ ---------------------------------------------------------------------- }
{ Gabarit du visage source et echange de visage                            }
{ ---------------------------------------------------------------------- }

Const
 MASK_CV = 0.55;      { centre de l'ellipse du visage (unites d'ecart yeux) }
 MASK_AU = 0.98;
 MASK_AV = 1.38;

Var
 WarpRGB: PByteArr;
 WarpA: PByteArr;
 WarpCap: LongInt;
 LastBox: Array[0..3] Of LongInt;

Function SwapAlloc: Boolean;
Begin
 WarpRGB := PByteArr(MemAlloc(FW * FH * 3));
 WarpA := PByteArr(MemAlloc(FW * FH));
 WarpCap := FW * FH;
 SwapAlloc := (WarpRGB <> Nil) And (WarpA <> Nil);
End;

{ Agrandit les tampons de deformation si le cadre du visage est plus
  grand que la trame de la camera (cibles de type image) }
Function WarpEnsure(N: LongInt): Boolean;
Begin
 WarpEnsure := True;
 If N <= WarpCap Then Exit;
 {$IFDEF FPC}
 FreeMem(WarpRGB, WarpCap * 3);
 FreeMem(WarpA, WarpCap);
 WarpRGB := PByteArr(MemAlloc(N * 3));
 WarpA := PByteArr(MemAlloc(N));
 If (WarpRGB = Nil) Or (WarpA = Nil) Then Begin
  WarpCap := 0;
  WarpEnsure := False;
  Exit;
 End;
 WarpCap := N;
 {$ELSE}
 WarpEnsure := False;
 {$ENDIF}
End;

{ Exclut du gabarit les cheveux et le fond : en peripherie du visage, les
  pixels dont la couleur s'ecarte de la peau (ou trop sombres) deviennent
  transparents ; le plan alpha est ensuite adouci. }
Procedure SkinEdgeMask(Var T: TImg; Vm: Real);
Var
 X, Y, N, Yy, Cb, Cr, MY, MCb, MCr, Dc, F, K, S0, P: LongInt;
 R2: Real;
 Tmp: PByteArr;
 Eye, Mou: Boolean;
Begin
 N := 0; MY := 0; MCb := 0; MCr := 0;
 For Y := 0 To T.H - 1 Do
  For X := 0 To T.W - 1 Do Begin
   R2 := Sqr((X - T_CX) / (MASK_AU * T_IPD)) +
         Sqr((Y - T_CY - MASK_CV * T_IPD) / (MASK_AV * T_IPD));
   If (R2 < 0.25) And (T.A^[Y * T.W + X] >= 250) Then Begin
    P := (Y * T.W + X) * 3;
    RgbToYcc(T.D^[P], T.D^[P + 1], T.D^[P + 2], Yy, Cb, Cr);
    Inc(N); Inc(MY, Yy); Inc(MCb, Cb); Inc(MCr, Cr);
   End;
  End;
 If N < 20 Then Exit;
 MY := MY Div N; MCb := MCb Div N; MCr := MCr Div N;
 For Y := 0 To T.H - 1 Do
  For X := 0 To T.W - 1 Do Begin
   R2 := Sqr((X - T_CX) / (MASK_AU * T_IPD)) +
         Sqr((Y - T_CY - MASK_CV * T_IPD) / (MASK_AV * T_IPD));
   { les yeux, sourcils et la bouche ne sont pas de la couleur de la peau }
   Eye := (Abs(Abs(X - T_CX) - 0.5 * T_IPD) <= 0.36 * T_IPD) And
          (Y - T_CY >= -0.5 * T_IPD) And (Y - T_CY <= 0.28 * T_IPD);
   Mou := (Abs(X - T_CX) <= 0.56 * T_IPD) And
          (Abs(Y - T_CY - Vm) <= 0.34 * T_IPD);
   If (R2 > 0.30) And (Not Eye) And (T.A^[Y * T.W + X] > 0) Then Begin
    P := (Y * T.W + X) * 3;
    RgbToYcc(T.D^[P], T.D^[P + 1], T.D^[P + 2], Yy, Cb, Cr);
    Dc := IAbs(Cb - MCb) + IAbs(Cr - MCr);
    F := 255;
    If Mou Then Begin
     { levres et dents : tolerance plus large }
     If Dc > 38 Then F := 255 - (Dc - 38) * 15;
    End
    Else Begin
     If Dc > 18 Then F := 255 - (Dc - 18) * 20;
     If Yy * 100 < MY * 50 Then F := 0;
    End;
    If F < 0 Then F := 0;
    T.A^[Y * T.W + X] := T.A^[Y * T.W + X] * F Div 255;
   End;
  End;
 { adoucissement 3x3 du plan alpha (deux passes) }
 Tmp := PByteArr(MemAlloc(T.W * T.H));
 If Tmp = Nil Then Exit;
 For K := 1 To 2 Do Begin
  For Y := 0 To T.H - 1 Do
   For X := 0 To T.W - 1 Do Begin
    S0 := 0;
    N := 0;
    For F := -1 To 1 Do
     For Dc := -1 To 1 Do
      If (X + Dc >= 0) And (X + Dc < T.W) And (Y + F >= 0) And
         (Y + F < T.H) Then Begin
       Inc(S0, T.A^[(Y + F) * T.W + X + Dc]);
       Inc(N);
      End;
    Tmp^[Y * T.W + X] := S0 Div N;
   End;
  Move(Tmp^, T.A^, T.W * T.H);
 End;
 FreeMem(Tmp, T.W * T.H);
End;

{ Construit le gabarit normalise (ecart des yeux = T_IPD) a partir de la
  photo et des reperes de S.Face }
Function BuildTemplate(Var S: TSlot): Boolean;
Var
 Ipd, Ux, Uy, Vx, Vy, Mx0, My0, Vm, Rat, Fc, Du, Dv, SX, SY, DE: Real;
 Work: TImg;
 Own: Boolean;
 Fct, X, Y, R, G, B, A, W2, H2, X2, Y2, C, S0: LongInt;
 Half: TImg;
Begin
 BuildTemplate := False;
 ImgFree(S.Tpl);
 ImgFree(S.Tpl2);
 If S.Photo.D = Nil Then Exit;
 With S.Face Do Begin
  Ipd := Sqrt(Sqr(ERx - ELx) + Sqr(ERy - ELy));
  If Ipd < 6 Then Exit;
  Ux := (ERx - ELx) / Ipd;
  Uy := (ERy - ELy) / Ipd;
  Vx := -Uy;
  Vy := Ux;
  Mx0 := (ELx + ERx) / 2;
  My0 := (ELy + ERy) / 2;
  Vm := (Mx - Mx0) * Vx + (My - My0) * Vy;
 End;
 Rat := Ipd / T_IPD;
 Fct := 1;
 If Rat >= 1.5 Then Fct := Trunc(Rat);
 Own := False;
 If Fct > 1 Then Begin
  If ImgNew(Work, S.Photo.W Div Fct, S.Photo.H Div Fct, False) Then Begin
   ImgResizeBox(S.Photo, Work);
   Own := True;
  End
  Else Begin
   Work := S.Photo;
   Fct := 1;
  End;
 End
 Else Work := S.Photo;
 Fc := Fct;
 Ipd := Ipd / Fc;
 Mx0 := Mx0 / Fc;
 My0 := My0 / Fc;
 Vm := Vm / Fc;
 Rat := RClip(Vm / Ipd, 0.8, 1.25);
 S.VmT := Rat * T_IPD;
 If Not ImgNew(S.Tpl, T_W, T_H, True) Then Begin
  If Own Then ImgFree(Work);
  Exit;
 End;
 For Y := 0 To T_H - 1 Do
  For X := 0 To T_W - 1 Do Begin
   Du := (X - T_CX) / T_IPD * Ipd;
   Dv := (Y - T_CY) / T_IPD * Ipd;
   SX := Mx0 + Ux * Du + Vx * Dv;
   SY := My0 + Uy * Du + Vy * Dv;
   DE := SX;
   If SY < DE Then DE := SY;
   If Work.W - 1 - SX < DE Then DE := Work.W - 1 - SX;
   If Work.H - 1 - SY < DE Then DE := Work.H - 1 - SY;
   If DE >= 0 Then Begin
    Bilin(Work, RoundL(SX * 65536), RoundL(SY * 65536), R, G, B, A);
    S.Tpl.D^[(Y * T_W + X) * 3] := R;
    S.Tpl.D^[(Y * T_W + X) * 3 + 1] := G;
    S.Tpl.D^[(Y * T_W + X) * 3 + 2] := B;
    S.Tpl.A^[Y * T_W + X] := Clip8(RoundL(DE * 40));
   End;
  End;
 If Own Then ImgFree(Work);
 SkinEdgeMask(S.Tpl, S.VmT);
 { version demi-echelle pour les visages eloignes }
 W2 := T_W Div 2;
 H2 := T_H Div 2;
 If ImgNew(S.Tpl2, W2, H2, True) Then Begin
  Half.W := W2; Half.H := H2; Half.D := S.Tpl2.D; Half.A := Nil;
  ImgResizeBox(S.Tpl, Half);
  For Y2 := 0 To H2 - 1 Do
   For X2 := 0 To W2 - 1 Do Begin
    S0 := 0;
    For C := 0 To 3 Do
     Inc(S0, S.Tpl.A^[(Y2 * 2 + (C Shr 1)) * T_W + X2 * 2 + (C And 1)]);
    S.Tpl2.A^[Y2 * W2 + X2] := S0 Div 4;
   End;
 End;
 BuildTemplate := True;
End;

{ Vignette d'une image (ajustee dans W x H) }
Procedure MakeThumb(Var Src, Dst: TImg; W, H: LongInt);
Var
 TW_, TH_: LongInt;
Begin
 ImgFree(Dst);
 If Src.D = Nil Then Exit;
 TW_ := W;
 TH_ := Src.H * W Div Src.W;
 If TH_ > H Then Begin
  TH_ := H;
  TW_ := Src.W * H Div Src.H;
 End;
 If TW_ < 1 Then TW_ := 1;
 If TH_ < 1 Then TH_ := 1;
 If ImgNew(Dst, TW_, TH_, False) Then ImgResize(Src, Dst);
End;

Procedure BuildThumb(Var S: TSlot; W, H: LongInt);
Begin
 MakeThumb(S.Photo, S.Thumb, W, H);
End;

{ Remplace le visage F de la trame Fr par le visage source S }
Procedure SwapFace(Var Fr: TImg; Var F: TFace; Var S: TSlot);
Var
 D, Ux, Uy, Vx, Vy, Mx, My, Vm, Kh, Kv, KhT, KvT, TCx, TCy: Real;
 AuD, AvD, CvD, MuD, MvD: Real;
 Ex, Ey, Cx, Cy: Real;
 BX1, BY1, BX2, BY2, BW, BH, X, Y, P, Q, R, G, B, TA, Al, E2, EA, EB: LongInt;
 TP: ^TImg;
 TXx, TXy, TX0, TYx, TYy, TY0: LongInt;
 EAx, EAy, EA0, EBx, EBy, EB0: LongInt;
 MAx, MAy, MA0, MBx, MBy, MB0: LongInt;
 TX, TY, EAv, EBv, MAv, MBv, M2, MF, E0, E1, M0, M1: LongInt;
 Yy, Cb, Cr: LongInt;
 N, SY, SCb, SCr, TY_, TCb, TCr: LongInt;
 SY2, SCb2, SCr2, TY2, TCb2, TCr2: Real;
 MuSY, MuSCb, MuSCr, MuTY, MuTCb, MuTCr: Real;
 SdS, SdT, GY, GC, ShCb, ShCr: Real;
 GY16, GC16, MuSY16, MuSCb16, MuSCr16, MuTY16, MuTCb16, MuTCr16: LongInt;
 ShCb16, ShCr16, NewY, NewCb, NewCr, Fv, Bl: LongInt;
 Strength: LongInt;
 Cnt, CoreE2, V0, Sum: LongInt;
 Pk, XN, YN, PP: LongInt;
Begin
 If (Fr.D = Nil) Or (S.Tpl.D = Nil) Or (Not F.Ok) Then Exit;
 { --- geometrie de la cible --- }
 D := Sqrt(Sqr(F.ERx - F.ELx) + Sqr(F.ERy - F.ELy));
 If D < 8 Then Exit;
 Ux := (F.ERx - F.ELx) / D;
 Uy := (F.ERy - F.ELy) / D;
 Vx := -Uy;
 Vy := Ux;
 Mx := (F.ELx + F.ERx) / 2;
 My := (F.ELy + F.ERy) / 2;
 Vm := (F.Mx - Mx) * Vx + (F.My - My) * Vy;
 Vm := RClip(Vm, 0.8 * D, 1.2 * D);
 Kh := D / T_IPD;
 Kv := RClip(Vm / S.VmT, 0.88 * Kh, 1.15 * Kh);
 If (Kh < 0.62) And (S.Tpl2.D <> Nil) Then Begin
  TP := @S.Tpl2;
  KhT := Kh * 2;
  KvT := Kv * 2;
  TCx := T_CX / 2.0;
  TCy := T_CY / 2.0;
 End
 Else Begin
  TP := @S.Tpl;
  KhT := Kh;
  KvT := Kv;
  TCx := T_CX;
  TCy := T_CY;
 End;
 AuD := MASK_AU * D;
 AvD := MASK_AV * D;
 CvD := MASK_CV * D;
 { cadre englobant de l'ellipse tournee }
 Cx := Mx + Vx * CvD;
 Cy := My + Vy * CvD;
 Ex := Sqrt(Sqr(AuD * Ux) + Sqr(AvD * Vx));
 Ey := Sqrt(Sqr(AuD * Uy) + Sqr(AvD * Vy));
 BX1 := ClipL(RoundL(Cx - Ex) - 2, 0, Fr.W - 1);
 BX2 := ClipL(RoundL(Cx + Ex) + 2, 0, Fr.W - 1);
 BY1 := ClipL(RoundL(Cy - Ey) - 2, 0, Fr.H - 1);
 BY2 := ClipL(RoundL(Cy + Ey) + 2, 0, Fr.H - 1);
 BW := BX2 - BX1 + 1;
 BH := BY2 - BY1 + 1;
 If (BW < 4) Or (BH < 4) Then Exit;
 If Not WarpEnsure(BW * BH) Then Exit;
 LastBox[0] := BX1; LastBox[1] := BY1; LastBox[2] := BX2; LastBox[3] := BY2;
 { --- formes lineaires en virgule fixe --- }
 { gabarit : tx = TCx + a / KhT, ty = TCy + b / KvT }
 TXx := RoundL(Ux / KhT * 65536);
 TXy := RoundL(Uy / KhT * 65536);
 TX0 := RoundL((TCx - (Mx * Ux + My * Uy) / KhT) * 65536);
 TYx := RoundL(Vx / KvT * 65536);
 TYy := RoundL(Vy / KvT * 65536);
 TY0 := RoundL((TCy - (Mx * Vx + My * Vy) / KvT) * 65536);
 { ellipse du visage : (a / AuD)^2 + ((b - CvD) / AvD)^2, unite 1/4096 }
 EAx := RoundL(Ux / AuD * 4096);
 EAy := RoundL(Uy / AuD * 4096);
 EA0 := RoundL(-(Mx * Ux + My * Uy) / AuD * 4096);
 EBx := RoundL(Vx / AvD * 4096);
 EBy := RoundL(Vy / AvD * 4096);
 EB0 := RoundL((-(Mx * Vx + My * Vy) - CvD) / AvD * 4096);
 { ellipse de la bouche }
 MuD := 0.52 * D;
 MvD := 0.26 * D;
 MAx := RoundL(Ux / MuD * 4096);
 MAy := RoundL(Uy / MuD * 4096);
 MA0 := RoundL(-(F.Mx * Ux + F.My * Uy) / MuD * 4096);
 MBx := RoundL(Vx / MvD * 4096);
 MBy := RoundL(Vy / MvD * 4096);
 MB0 := RoundL(-(F.Mx * Vx + F.My * Vy) / MvD * 4096);
 E1 := 4096 * 4096;
 E0 := (E1 Div 100) * 52;
 M1 := 4096 * 4096;
 M0 := (M1 Div 100) * 30;
 { --- passe 1 : deformation du gabarit et masque --- }
 For Y := BY1 To BY2 Do
  For X := BX1 To BX2 Do Begin
   Q := (Y - BY1) * BW + (X - BX1);
   EAv := X * EAx + Y * EAy + EA0;
   EBv := X * EBx + Y * EBy + EB0;
   E2 := EAv * EAv + EBv * EBv;
   If E2 >= E1 Then Begin
    WarpA^[Q] := 0;
   End
   Else Begin
    If E2 <= E0 Then Al := 255
    Else Al := ((E1 - E2) Shr 8) * 255 Div ((E1 - E0) Shr 8);
    If OptMouth Then Begin
     MAv := X * MAx + Y * MAy + MA0;
     MBv := X * MBx + Y * MBy + MB0;
     M2 := MAv * MAv + MBv * MBv;
     If M2 < M1 Then Begin
      If M2 <= M0 Then MF := 0
      Else MF := ((M2 - M0) Shr 8) * 255 Div ((M1 - M0) Shr 8);
      Al := Al * MF Div 255;
     End;
    End;
    TX := X * TXx + Y * TXy + TX0;
    TY := X * TYx + Y * TYy + TY0;
    Bilin(TP^, TX, TY, R, G, B, TA);
    Al := Al * TA Div 255;
    WarpA^[Q] := Al;
    WarpRGB^[Q * 3] := R;
    WarpRGB^[Q * 3 + 1] := G;
    WarpRGB^[Q * 3 + 2] := B;
   End;
  End;
 { --- passe 2 : statistiques de couleur (Y, Cb, Cr) au coeur du visage --- }
 N := 0;
 SY2 := 0; SCb2 := 0; SCr2 := 0; TY2 := 0; TCb2 := 0; TCr2 := 0;
 SY := 0; SCb := 0; SCr := 0; TY_ := 0; TCb := 0; TCr := 0;
 For Y := BY1 To BY2 Do
  If ((Y - BY1) And 1) = 0 Then
   For X := BX1 To BX2 Do
    If ((X - BX1) And 1) = 0 Then Begin
     Q := (Y - BY1) * BW + (X - BX1);
     If WarpA^[Q] >= 250 Then Begin
      Inc(N);
      RgbToYcc(WarpRGB^[Q * 3], WarpRGB^[Q * 3 + 1], WarpRGB^[Q * 3 + 2],
               Yy, Cb, Cr);
      Inc(SY, Yy); Inc(SCb, Cb); Inc(SCr, Cr);
      SY2 := SY2 + Yy * Yy;
      P := (Y * Fr.W + X) * 3;
      RgbToYcc(Fr.D^[P], Fr.D^[P + 1], Fr.D^[P + 2], Yy, Cb, Cr);
      Inc(TY_, Yy); Inc(TCb, Cb); Inc(TCr, Cr);
      TY2 := TY2 + Yy * Yy;
     End;
    End;
 If N < 20 Then Begin
  GY := 1.0; GC := 1.0;
  MuSY := 0; MuTY := 0; MuSCb := 128; MuTCb := 128; MuSCr := 128;
  MuTCr := 128;
  ShCb := 0; ShCr := 0;
 End
 Else Begin
  MuSY := SY / N;
  MuTY := TY_ / N;
  MuSCb := SCb / N;
  MuTCb := TCb / N;
  MuSCr := SCr / N;
  MuTCr := TCr / N;
  SdS := Sqrt(RMax(1.0, SY2 / N - MuSY * MuSY));
  SdT := Sqrt(RMax(1.0, TY2 / N - MuTY * MuTY));
  GY := 1.0 + 0.65 * (SdT / SdS - 1.0);
  GY := RClip(GY, 0.55, 1.25);
  GC := 1.0;
  ShCb := 0.75 * (MuTCb - MuSCb);
  ShCr := 0.75 * (MuTCr - MuSCr);
 End;
 GY16 := RoundL(GY * 256);
 MuSY16 := RoundL(MuSY * 256);
 MuTY16 := RoundL(MuTY * 256);
 ShCb16 := RoundL(ShCb);
 ShCr16 := RoundL(ShCr);
 { --- passe 3 : correction de couleur et fusion --- }
 For Y := BY1 To BY2 Do
  For X := BX1 To BX2 Do Begin
   Q := (Y - BY1) * BW + (X - BX1);
   Al := WarpA^[Q];
   If Al > 0 Then Begin
    RgbToYcc(WarpRGB^[Q * 3], WarpRGB^[Q * 3 + 1], WarpRGB^[Q * 3 + 2],
             Yy, Cb, Cr);
    NewY := ((Yy * 256 - MuSY16) * GY16) Div 256 + MuTY16;
    NewY := NewY Div 256;
    NewCb := Cb + ShCb16;
    NewCr := Cr + ShCr16;
    R := NewY + (359 * (NewCr - 128)) Div 256;
    G := NewY - (88 * (NewCb - 128) + 183 * (NewCr - 128)) Div 256;
    B := NewY + (454 * (NewCb - 128)) Div 256;
    P := (Y * Fr.W + X) * 3;
    Fr.D^[P] := (Fr.D^[P] * (255 - Al) + Clip8(R) * Al) Div 255;
    Fr.D^[P + 1] := (Fr.D^[P + 1] * (255 - Al) + Clip8(G) * Al) Div 255;
    Fr.D^[P + 2] := (Fr.D^[P + 2] * (255 - Al) + Clip8(B) * Al) Div 255;
   End;
  End;
 { --- amelioration du visage : renforcement local (masque flou) --- }
 If OptEnhance Then Begin
  For Y := BY1 To BY2 Do
   Move(Fr.D^[(Y * Fr.W + BX1) * 3], WarpRGB^[(Y - BY1) * BW * 3], BW * 3);
  For Y := BY1 + 1 To BY2 - 1 Do
   For X := BX1 + 1 To BX2 - 1 Do Begin
    Q := (Y - BY1) * BW + (X - BX1);
    Al := WarpA^[Q];
    If Al > 0 Then Begin
     P := (Y * Fr.W + X) * 3;
     For N := 0 To 2 Do Begin
      Sum := 0;
      Sum := WarpRGB^[(Q - BW - 1) * 3 + N] + WarpRGB^[(Q - BW) * 3 + N] +
             WarpRGB^[(Q - BW + 1) * 3 + N] + WarpRGB^[(Q - 1) * 3 + N] +
             WarpRGB^[(Q + 1) * 3 + N] + WarpRGB^[(Q + BW - 1) * 3 + N] +
             WarpRGB^[(Q + BW) * 3 + N] + WarpRGB^[(Q + BW + 1) * 3 + N];
      Sum := (Sum + WarpRGB^[Q * 3 + N]) Div 9;
      V0 := WarpRGB^[Q * 3 + N];
      V0 := V0 + ((V0 - Sum) * 3 Div 4);
      Fr.D^[P + N] := Clip8(V0);
     End;
    End;
   End;
 End;
End;

{ ---------------------------------------------------------------------- }
{ Suivi des visages et traitement d'une trame                              }
{ ---------------------------------------------------------------------- }

Var
 Tracks: TFaceList;
 TrackN: Integer;
 TrackAge: Array[0..MAX_FACES - 1] Of Integer;
 TrackConf: Array[0..MAX_FACES - 1] Of Integer;
 SkinTick: Integer;

Procedure FlipH(Var I: TImg);
Var
 X, Y, C, P1, P2: LongInt;
 T: Byte;
Begin
 For Y := 0 To I.H - 1 Do
  For X := 0 To I.W Div 2 - 1 Do
   For C := 0 To 2 Do Begin
    P1 := (Y * I.W + X) * 3 + C;
    P2 := (Y * I.W + (I.W - 1 - X)) * 3 + C;
    T := I.D^[P1];
    I.D^[P1] := I.D^[P2];
    I.D^[P2] := T;
   End;
End;

Procedure TrackReset;
Begin
 TrackN := 0;
 PrevOk := False;
 TrackMiss := 0;
End;

{ Lisse les reperes d'un visage vers la nouvelle mesure : plus le visage
  bouge vite, moins on lisse. }
Procedure TrackBlend(Var Old, New: TFace);
Var
 Wf, Mv, A: Real;
Begin
 Wf := New.X2 - New.X1 + 1;
 Mv := Sqrt(Sqr((New.ELx + New.ERx) / 2 - (Old.ELx + Old.ERx) / 2) +
            Sqr((New.ELy + New.ERy) / 2 - (Old.ELy + Old.ERy) / 2));
 A := RClip(0.35 + Mv / (0.12 * Wf) * 0.65, 0.35, 1.0);
 Old.ELx := Old.ELx + A * (New.ELx - Old.ELx);
 Old.ELy := Old.ELy + A * (New.ELy - Old.ELy);
 Old.ERx := Old.ERx + A * (New.ERx - Old.ERx);
 Old.ERy := Old.ERy + A * (New.ERy - Old.ERy);
 Old.Mx := Old.Mx + A * (New.Mx - Old.Mx);
 Old.My := Old.My + A * (New.My - Old.My);
 Old.X1 := Old.X1 + RoundL(A * (New.X1 - Old.X1));
 Old.X2 := Old.X2 + RoundL(A * (New.X2 - Old.X2));
 Old.Y1 := Old.Y1 + RoundL(A * (New.Y1 - Old.Y1));
 Old.Y2 := Old.Y2 + RoundL(A * (New.Y2 - Old.Y2));
 Old.Area := New.Area;
End;

{ Associe les nouvelles detections aux suivis existants }
Procedure TrackUpdate(Var New: TFaceList; NN: Integer);
Var
 Res_: TFaceList;
 Age, Conf: Array[0..MAX_FACES - 1] Of Integer;
 Used: Array[0..MAX_FACES - 1] Of Boolean;
 I, J, Best, K: Integer;
 D, BD, Wf, Cx, Cy: Real;
 Tmp: TFace;
Begin
 K := 0;
 FillChar(Used, SizeOf(Used), 0);
 For I := 0 To NN - 1 Do Begin
  Best := -1;
  BD := 1E30;
  Wf := New[I].X2 - New[I].X1 + 1;
  Cx := (New[I].X1 + New[I].X2) / 2;
  Cy := (New[I].Y1 + New[I].Y2) / 2;
  For J := 0 To TrackN - 1 Do
   If Not Used[J] Then Begin
    D := Sqrt(Sqr((Tracks[J].X1 + Tracks[J].X2) / 2 - Cx) +
              Sqr((Tracks[J].Y1 + Tracks[J].Y2) / 2 - Cy));
    If (D < BD) And (D < 0.9 * Wf) Then Begin BD := D; Best := J; End;
   End;
  If Best >= 0 Then Begin
   Used[Best] := True;
   Tmp := Tracks[Best];
   TrackBlend(Tmp, New[I]);
   Res_[K] := Tmp;
   Conf[K] := TrackConf[Best] + 1;
  End
  Else Begin
   Res_[K] := New[I];
   { en direct, un nouveau visage doit etre vu sur 2 images de suite
     (evite les fausses detections isolees) }
   If Live Then Conf[K] := 1 Else Conf[K] := 2;
  End;
  Age[K] := 0;
  Inc(K);
 End;
 { suivis non retrouves : conserves quelques trames }
 For J := 0 To TrackN - 1 Do
  If (Not Used[J]) And (K < MAX_FACES) And (TrackAge[J] < 5) And
     (NN = 0) Then Begin
   Res_[K] := Tracks[J];
   Age[K] := TrackAge[J] + 1;
   Conf[K] := TrackConf[J];
   Inc(K);
  End;
 For I := 0 To K - 1 Do Begin
  Tracks[I] := Res_[I];
  TrackAge[I] := Age[I];
  TrackConf[I] := Conf[I];
 End;
 TrackN := K;
 If K > 0 Then Begin
  PrevOk := True;
  PrevCx := (Tracks[0].X1 + Tracks[0].X2) / 2;
  PrevCy := (Tracks[0].Y1 + Tracks[0].Y2) / 2;
  PrevW := Tracks[0].X2 - Tracks[0].X1 + 1;
 End
 Else PrevOk := False;
End;

{ Tri des visages de gauche a droite (pour la cartographie) }
Procedure SortFacesByX(Var L: TFaceList; N: Integer);
Var
 I, J: Integer;
 T: TFace;
Begin
 For I := 0 To N - 2 Do
  For J := I + 1 To N - 1 Do
   If L[J].X1 + L[J].X2 < L[I].X1 + L[I].X2 Then Begin
    T := L[I]; L[I] := L[J]; L[J] := T;
   End;
End;

Procedure DrawMarks(Var Fr: TImg);
Var
 I: Integer;
 Procedure Pt(X, Y: LongInt; R, G, B: Byte);
 Var
  P: LongInt;
 Begin
  If (X >= 0) And (X < Fr.W) And (Y >= 0) And (Y < Fr.H) Then Begin
   P := (Y * Fr.W + X) * 3;
   Fr.D^[P] := R; Fr.D^[P + 1] := G; Fr.D^[P + 2] := B;
  End;
 End;
 Procedure Cross(X, Y: LongInt; R, G, B: Byte);
 Var
  K: LongInt;
 Begin
  For K := -3 To 3 Do Begin
   Pt(X + K, Y, R, G, B);
   Pt(X, Y + K, R, G, B);
  End;
 End;
 Procedure Rect(X1, Y1, X2, Y2: LongInt);
 Var
  K: LongInt;
 Begin
  For K := X1 To X2 Do Begin
   Pt(K, Y1, 255, 255, 0);
   Pt(K, Y2, 255, 255, 0);
  End;
  For K := Y1 To Y2 Do Begin
   Pt(X1, K, 255, 255, 0);
   Pt(X2, K, 255, 255, 0);
  End;
 End;
Begin
 For I := 0 To FaceCount - 1 Do Begin
  Rect(Faces[I].X1, Faces[I].Y1, Faces[I].X2, Faces[I].Y2);
  Cross(RoundL(Faces[I].ELx), RoundL(Faces[I].ELy), 0, 255, 0);
  Cross(RoundL(Faces[I].ERx), RoundL(Faces[I].ERy), 0, 255, 0);
  Cross(RoundL(Faces[I].Mx), RoundL(Faces[I].My), 255, 0, 255);
 End;
End;

{ Premier emplacement source utilisable }
Function SlotFor(Index: Integer): Integer;
Var
 I: Integer;
Begin
 SlotFor := 0;
 If OptMap And (Index + 1 <= N_SLOTS) Then
  If Slots[Index + 1].Ok Then Begin SlotFor := Index + 1; Exit; End;
 If Slots[CurSlot].Ok Then Begin SlotFor := CurSlot; Exit; End;
 For I := 1 To N_SLOTS Do
  If Slots[I].Ok Then Begin SlotFor := I; Exit; End;
End;

{ Detecte les visages de la trame Fr (modifiee sur place) et echange }
Procedure ProcessFrame(Var Fr: TImg);
Var
 N, I, MaxN, Sl: Integer;
 New: TFaceList;
Begin
 If OptMirror Then FlipH(Fr);
 MaxN := 1;
 If OptMany Or OptMap Then MaxN := MAX_FACES;
 N := DetectFaces(Fr, New, MaxN);
 TrackUpdate(New, N);
 FaceCount := 0;
 For I := 0 To TrackN - 1 Do
  If TrackConf[I] >= 2 Then Begin
   Faces[FaceCount] := Tracks[I];
   Inc(FaceCount);
  End;
 If OptMap Then SortFacesByX(Faces, FaceCount);
 If (FaceCount > 0) And (N > 0) Then Begin
  Inc(SkinTick);
  If SkinTick >= 12 Then Begin
   SkinTick := 0;
   SkinLearn(Fr, Faces[0]);
  End;
 End;
 For I := 0 To FaceCount - 1 Do Begin
  Sl := SlotFor(I);
  If Sl > 0 Then SwapFace(Fr, Faces[I], Slots[Sl]);
 End;
 If OptMarks Then DrawMarks(Fr);
End;

{ ---------------------------------------------------------------------- }
{ Affichage de la video : tramage 16 couleurs ou couleurs vraies           }
{ ---------------------------------------------------------------------- }

Const
 Bayer4: Array[0..15] Of Integer =
  (-30, 2, -22, 10, 18, -14, 26, -6, -18, 14, -26, 6, 30, -2, 22, -10);

Var
 Q16: Array[0..4095] Of Byte;

Procedure BuildQ16;
Var
 I, K, Best: Integer;
 R, G, B, D, BD, DR, DG, DB: LongInt;
Begin
 For I := 0 To 4095 Do Begin
  R := (I Shr 8) * 17;
  G := ((I Shr 4) And 15) * 17;
  B := (I And 15) * 17;
  Best := 0;
  BD := MaxLongInt;
  For K := 0 To 15 Do Begin
   DR := R - ScrVga[K, 0];
   DG := G - ScrVga[K, 1];
   DB := B - ScrVga[K, 2];
   D := DR * DR * 3 + DG * DG * 4 + DB * DB * 2;
   If D < BD Then Begin BD := D; Best := K; End;
  End;
  Q16[I] := Best;
 End;
End;

Function Dither16(R, G, B, X, Y: LongInt): LongInt;
Var
 O: LongInt;
Begin
 O := Bayer4[((Y And 3) Shl 2) + (X And 3)];
 R := Clip8(R + O);
 G := Clip8(G + O);
 B := Clip8(B + O);
 Dither16 := Q16[((R Shr 4) Shl 8) Or ((G Shr 4) Shl 4) Or (B Shr 4)];
End;

Procedure RawFill(C: LongInt);
Begin
 {$IFDEF FPC}
 PtcGraph.SetFillStyle(SolidFill, C);
 {$ELSE}
 SetFillStyle(SolidFill, C);
 {$ENDIF}
End;

{ Indice du cube 6 x 6 x 6 (mode 256 couleurs), avec tramage leger }
Function Pal6(R, G, B, X, Y: LongInt): LongInt;
Var
 O: LongInt;
Begin
 O := Bayer4[((Y And 3) Shl 2) + (X And 3)] * 2 Div 3;
 Pal6 := 16 + 36 * ((Clip8(R + O) * 5 + 127) Div 255) +
         6 * ((Clip8(G + O) * 5 + 127) Div 255) +
         ((Clip8(B + O) * 5 + 127) Div 255);
End;

Function PixCol(Var I: TImg; X, Y: LongInt): LongInt;
Var
 P: LongInt;
Begin
 P := (Y * I.W + X) * 3;
 If TrueMode Then
  PixCol := (LongInt(I.D^[P]) Shl 16) Or (LongInt(I.D^[P + 1]) Shl 8) Or
            I.D^[P + 2]
 Else If Pal256 Then
  PixCol := Pal6(I.D^[P], I.D^[P + 1], I.D^[P + 2], X, Y)
 Else PixCol := Dither16(I.D^[P], I.D^[P + 1], I.D^[P + 2], X, Y);
End;

{ ---------------------------------------------------------------------- }
{ Acceleration Direct3D 9 (WINDOWS) : l'image est envoyee au GPU comme      }
{ texture et affichee par un quadrilatere filtre, dans une fenetre fille    }
{ posee sur la zone d'apercu. Aucune unite : d3d9.dll est chargee           }
{ dynamiquement et ses interfaces COM sont appelees par leur table de       }
{ fonctions. Si la carte n'est pas une vraie carte graphique (pilote        }
{ logiciel Microsoft, WARP, peu de memoire) ou si une etape echoue, on      }
{ garde l'affichage logiciel.                                               }
{ ---------------------------------------------------------------------- }

{$IFDEF WINDOWS}
Const
 D3D_SDK_VERSION = 32;
 GWL_STYLE = -16;
 WS_CHILD_ = $40000000;
 WS_CLIPSIBLINGS_ = $04000000;
 WS_CLIPCHILDREN_ = $02000000;
 GPU_MIN_MEM = 200;      { Mo de memoire video minimale }

Type
 TGpuVtx = Record
  X, Y, Z, Rhw: Single;
  Col: LongWord;
  U, V: Single;
 End;
 TLockedRect = Record
  Pitch: LongInt;
  Bits: Pointer;
 End;
 TD3DPP = Record
  BackBufferWidth, BackBufferHeight: LongWord;
  BackBufferFormat, BackBufferCount: LongWord;
  MultiSampleType, MultiSampleQuality, SwapEffect: LongWord;
  hDeviceWindow: PtrUInt;
  Windowed, EnableAutoDepthStencil, AutoDepthStencilFormat, Flags: LongWord;
  RefreshRate, PresentationInterval: LongWord;
 End;
 TVTable = Array[0..127] Of Pointer;
 PVTable = ^TVTable;
 PPVTable = ^PVTable;
 TFnCreate9 = Function(Ver: LongWord): Pointer; stdcall;
 TFnRelease = Function(Self: Pointer): LongWord; stdcall;
 TFnAdId = Function(Self: Pointer; Adapter, Flags: LongWord;
                    Ident: Pointer): LongInt; stdcall;
 TFnCreateDev = Function(Self: Pointer; Adapter, DevType: LongWord;
                         Wnd: PtrUInt; BehFlags: LongWord; PP: Pointer;
                         Dev: Pointer): LongInt; stdcall;
 TFnAvail = Function(Self: Pointer): LongWord; stdcall;
 TFnCreateTex = Function(Self: Pointer; W, H, Levels, Usage: LongWord;
                         Fmt, Pool: LongWord; Tex: Pointer;
                         Shared: Pointer): LongInt; stdcall;
 TFnLock = Function(Self: Pointer; Level: LongWord; Lr: Pointer; Rc: Pointer;
                    Flags: LongWord): LongInt; stdcall;
 TFnUnlock = Function(Self: Pointer; Level: LongWord): LongInt; stdcall;
 TFnClear = Function(Self: Pointer; Count: LongWord; Rects: Pointer;
                     Flags, Color: LongWord; Z: Single;
                     Stencil: LongWord): LongInt; stdcall;
 TFnVoid = Function(Self: Pointer): LongInt; stdcall;
 TFnSet1 = Function(Self: Pointer; A: LongWord): LongInt; stdcall;
 TFnSet2 = Function(Self: Pointer; A, B: LongWord): LongInt; stdcall;
 TFnSet3 = Function(Self: Pointer; A, B, C: LongWord): LongInt; stdcall;
 TFnSetTex = Function(Self: Pointer; Stage: LongWord;
                      Tex: Pointer): LongInt; stdcall;
 TFnDrawUP = Function(Self: Pointer; PrimType, PrimCount: LongWord;
                      Data: Pointer; Stride: LongWord): LongInt; stdcall;
 TFnPresent = Function(Self: Pointer; A, B: Pointer; Wnd: PtrUInt;
                       C: Pointer): LongInt; stdcall;

Function LoadLibraryA(Name: PChar): PtrUInt; stdcall;
  external 'kernel32.dll' name 'LoadLibraryA';
Function GetProcAddress(Lib: PtrUInt; Name: PChar): Pointer; stdcall;
  external 'kernel32.dll' name 'GetProcAddress';
Function GetActiveWindow: PtrUInt; stdcall;
  external 'user32.dll' name 'GetActiveWindow';
Function GetForegroundWindow: PtrUInt; stdcall;
  external 'user32.dll' name 'GetForegroundWindow';
Function CreateWindowExA(ExStyle: LongWord; ClassName, WindowName: PChar;
  Style: LongWord; X, Y, W, H: LongInt; Parent, Menu, Inst: PtrUInt;
  Param: Pointer): PtrUInt; stdcall;
  external 'user32.dll' name 'CreateWindowExA';
Function ShowWindow(Wnd: PtrUInt; Cmd: LongInt): LongBool; stdcall;
  external 'user32.dll' name 'ShowWindow';
Function GetWindowLongA(Wnd: PtrUInt; Idx: LongInt): LongInt; stdcall;
  external 'user32.dll' name 'GetWindowLongA';
Function SetWindowLongA(Wnd: PtrUInt; Idx: LongInt;
  Value: LongInt): LongInt; stdcall;
  external 'user32.dll' name 'SetWindowLongA';

Var
 GpuOn, GpuVisible: Boolean;
 GpuWnd: PtrUInt;
 GpuD3D, GpuDev, GpuTex: Pointer;
 GpuTexW, GpuTexH: LongInt;
 GpuName: String[60];

{ Methode numero N de l'interface COM I }
Function VT(I: Pointer; N: Integer): Pointer;
Begin
 VT := PPVTable(I)^^[N];
End;

Procedure GpuRelease(Var I: Pointer);
Begin
 If I <> Nil Then TFnRelease(VT(I, 2))(I);
 I := Nil;
End;

Procedure GpuShutdown;
Begin
 GpuRelease(GpuTex);
 GpuRelease(GpuDev);
 GpuRelease(GpuD3D);
 If GpuWnd <> 0 Then DestroyWindow(GpuWnd);
 GpuWnd := 0;
 GpuOn := False;
 GpuVisible := False;
End;

{ Carte reellement exploitable ? (pas de pilote logiciel Microsoft) }
Function GpuSignificant(Var Name: String): Boolean;
Var
 Id: Array[0..1199] Of Byte;
 D: String;
 Vendor: LongInt;
 I: Integer;
Begin
 GpuSignificant := False;
 FillChar(Id, SizeOf(Id), 0);
 If TFnAdId(VT(GpuD3D, 5))(GpuD3D, 0, 0, @Id) < 0 Then Exit;
 D := '';
 For I := 512 To 700 Do Begin
  If Id[I] = 0 Then Break;
  D := D + Chr(Id[I]);
 End;
 Name := Copy(D, 1, 60);
 Vendor := Id[1064] + Id[1065] * 256;
 D := UpStr(D);
 If Vendor = $1414 Then Exit;
 If (Pos('MICROSOFT', D) > 0) Or (Pos('BASIC', D) > 0) Or
    (Pos('SOFTWARE', D) > 0) Or (Pos('GDI', D) > 0) Or
    (Pos('WARP', D) > 0) Or (Pos('REFERENCE', D) > 0) Then Exit;
 GpuSignificant := True;
End;

Function GpuInit: Boolean;
Var
 Lib: PtrUInt;
 P: Pointer;
 Parent: PtrUInt;
 PP: TD3DPP;
 Style: LongInt;
 Nm: String;
 Mem: LongWord;
Begin
 GpuInit := False;
 GpuOn := False;
 GpuVisible := False;
 GpuD3D := Nil; GpuDev := Nil; GpuTex := Nil; GpuWnd := 0;
 Lib := LoadLibraryA('d3d9.dll');
 If Lib = 0 Then Exit;
 P := GetProcAddress(Lib, 'Direct3DCreate9');
 If P = Nil Then Exit;
 GpuD3D := TFnCreate9(P)(D3D_SDK_VERSION);
 If GpuD3D = Nil Then Exit;
 Nm := '';
 If Not GpuSignificant(Nm) Then Begin
  GpuShutdown;
  Exit;
 End;
 { fenetre fille posee sur l'apercu (classe predefinie STATIC : elle laisse
   passer la souris vers la fenetre graphique) }
 Parent := GetActiveWindow;
 If Parent = 0 Then Parent := GetForegroundWindow;
 If Parent = 0 Then Begin GpuShutdown; Exit; End;
 Style := GetWindowLongA(Parent, GWL_STYLE);
 SetWindowLongA(Parent, GWL_STYLE, Style Or LongInt(WS_CLIPCHILDREN_));
 GpuWnd := CreateWindowExA(0, 'STATIC', Nil, WS_CHILD_ Or WS_CLIPSIBLINGS_,
             ScrOX + PREV_X, ScrOY + PREV_Y, PREV_W, PREV_H, Parent, 0, 0,
             Nil);
 If GpuWnd = 0 Then Begin GpuShutdown; Exit; End;
 FillChar(PP, SizeOf(PP), 0);
 PP.BackBufferCount := 1;
 PP.SwapEffect := 1;                  { D3DSWAPEFFECT_DISCARD }
 PP.hDeviceWindow := GpuWnd;
 PP.Windowed := 1;
 PP.PresentationInterval := $80000000;  { sans attente du retour vertical }
 If TFnCreateDev(VT(GpuD3D, 16))(GpuD3D, 0, 1, GpuWnd, $20, @PP,
                                 @GpuDev) < 0 Then
  If TFnCreateDev(VT(GpuD3D, 16))(GpuD3D, 0, 1, GpuWnd, $40, @PP,
                                  @GpuDev) < 0 Then Begin
   GpuShutdown;
   Exit;
  End;
 Mem := TFnAvail(VT(GpuDev, 4))(GpuDev);
 If Mem < LongWord(GPU_MIN_MEM) * 1024 * 1024 Then Begin
  GpuShutdown;
  Exit;
 End;
 { texture (puissances de deux), format X8R8G8B8, memoire geree }
 GpuTexW := 1;
 While GpuTexW < FW Do GpuTexW := GpuTexW * 2;
 GpuTexH := 1;
 While GpuTexH < FH Do GpuTexH := GpuTexH * 2;
 If TFnCreateTex(VT(GpuDev, 23))(GpuDev, GpuTexW, GpuTexH, 1, 0, 22, 1,
                                 @GpuTex, Nil) < 0 Then Begin
  GpuShutdown;
  Exit;
 End;
 { etats fixes : pas d'eclairage, pas d'elimination, filtrage lineaire }
 TFnSet2(VT(GpuDev, 57))(GpuDev, 137, 0);    { LIGHTING }
 TFnSet2(VT(GpuDev, 57))(GpuDev, 22, 1);     { CULLMODE = NONE }
 TFnSet2(VT(GpuDev, 57))(GpuDev, 7, 0);      { ZENABLE }
 TFnSet3(VT(GpuDev, 69))(GpuDev, 0, 5, 2);   { MAGFILTER = LINEAR }
 TFnSet3(VT(GpuDev, 69))(GpuDev, 0, 6, 2);   { MINFILTER = LINEAR }
 TFnSet3(VT(GpuDev, 69))(GpuDev, 0, 1, 3);   { ADDRESSU = CLAMP }
 TFnSet3(VT(GpuDev, 69))(GpuDev, 0, 2, 3);   { ADDRESSV = CLAMP }
 GpuName := Nm;
 GpuOn := True;
 GpuInit := True;
End;

Procedure GpuHide;
Begin
 If GpuOn And GpuVisible Then Begin
  ShowWindow(GpuWnd, 0);
  GpuVisible := False;
 End;
End;

{ Envoie la trame au GPU et l'affiche ; en cas d'erreur, le GPU est
  abandonne et l'affichage logiciel prend le relais. }
Procedure GpuPresent(Var Fr: TImg);
Var
 Lr: TLockedRect;
 X, Y, P: LongInt;
 Row: PByteArr;
 V: Array[0..3] Of TGpuVtx;
 U1, V1: Single;
 I: Integer;
Begin
 If (Not GpuOn) Or (Fr.D = Nil) Or (Fr.W <> FW) Or (Fr.H <> FH) Then Exit;
 If Not GpuVisible Then Begin
  ShowWindow(GpuWnd, 8);             { SW_SHOWNA }
  GpuVisible := True;
 End;
 FillChar(Lr, SizeOf(Lr), 0);
 If TFnLock(VT(GpuTex, 19))(GpuTex, 0, @Lr, Nil, 0) < 0 Then Begin
  GpuShutdown;
  Exit;
 End;
 For Y := 0 To FH - 1 Do Begin
  Row := PByteArr(PtrUInt(Lr.Bits) + PtrUInt(Y * Lr.Pitch));
  P := Y * FW * 3;
  For X := 0 To FW - 1 Do Begin
   Row^[X * 4] := Fr.D^[P + 2];
   Row^[X * 4 + 1] := Fr.D^[P + 1];
   Row^[X * 4 + 2] := Fr.D^[P];
   Row^[X * 4 + 3] := 255;
   Inc(P, 3);
  End;
 End;
 TFnUnlock(VT(GpuTex, 20))(GpuTex, 0);
 U1 := FW / GpuTexW;
 V1 := FH / GpuTexH;
 For I := 0 To 3 Do Begin
  V[I].Z := 0;
  V[I].Rhw := 1;
  V[I].Col := $FFFFFFFF;
 End;
 V[0].X := -0.5;          V[0].Y := -0.5;          V[0].U := 0;  V[0].V := 0;
 V[1].X := PREV_W - 0.5;  V[1].Y := -0.5;          V[1].U := U1; V[1].V := 0;
 V[2].X := -0.5;          V[2].Y := PREV_H - 0.5;  V[2].U := 0;  V[2].V := V1;
 V[3].X := PREV_W - 0.5;  V[3].Y := PREV_H - 0.5;  V[3].U := U1; V[3].V := V1;
 TFnClear(VT(GpuDev, 43))(GpuDev, 0, Nil, 1, $FF000000, 1.0, 0);
 If TFnVoid(VT(GpuDev, 41))(GpuDev) >= 0 Then Begin
  TFnSetTex(VT(GpuDev, 65))(GpuDev, 0, GpuTex);
  TFnSet1(VT(GpuDev, 89))(GpuDev, $144);        { SetFVF : RHW+DIFFUSE+TEX1 }
  TFnDrawUP(VT(GpuDev, 83))(GpuDev, 5, 2, @V, SizeOf(TGpuVtx));
  TFnVoid(VT(GpuDev, 42))(GpuDev);
 End;
 { Present : un echec (peripherique perdu) ramene a l'affichage logiciel }
 If TFnPresent(VT(GpuDev, 17))(GpuDev, Nil, Nil, 0, Nil) < 0 Then Begin
  GpuShutdown;
  ShadowOk := False;
 End;
End;
{$ENDIF}

{ Affiche une trame FW x FH dans la zone d'apercu (seuls les pixels
  modifies sont redessines) }
Procedure ShowFrameSoft(Var Fr: TImg);
Var
 X, Y, Z, Step, C, Idx: LongInt;
Begin
 If (Fr.D = Nil) Or (Fr.W <> FW) Or (Fr.H <> FH) Then Exit;
 If Shadow = Nil Then Exit;
 Z := PREV_W Div FW;
 Step := 1;
 If OptFast Then Step := 2;
 Y := 0;
 While Y < FH Do Begin
  X := 0;
  While X < FW Do Begin
   C := PixCol(Fr, X, Y);
   Idx := Y * FW + X;
   If (Not ShadowOk) Or (Shadow^[Idx] <> C) Then Begin
    Shadow^[Idx] := C;
    If (Z * Step) = 1 Then RawPixel(PREV_X + X, PREV_Y + Y, C)
    Else Begin
     RawFill(C);
     Bar(PREV_X + X * Z, PREV_Y + Y * Z, PREV_X + (X + Step) * Z - 1,
         PREV_Y + (Y + Step) * Z - 1);
    End;
   End;
   Inc(X, Step);
  End;
  Inc(Y, Step);
 End;
 ShadowOk := True;
End;

{ Affichage de la video : par le GPU (Direct3D) si disponible, sinon par
  l'affichage logiciel }
Procedure ShowFrame(Var Fr: TImg);
Begin
 {$IFDEF WINDOWS}
 If GpuOn And (Not MenuActive) Then Begin
  GpuPresent(Fr);
  If GpuOn Then Exit;
 End;
 {$ENDIF}
 ShowFrameSoft(Fr);
End;

{ Dessine une image a l'ecran en (X0, Y0), a l'echelle 1:1 }
Procedure BlitImg(Var I: TImg; X0, Y0: Integer);
Var
 X, Y: LongInt;
Begin
 If I.D = Nil Then Exit;
 For Y := 0 To I.H - 1 Do
  For X := 0 To I.W - 1 Do RawPixel(X0 + X, Y0 + Y, PixCol(I, X, Y));
End;

{ ---------------------------------------------------------------------- }
{ Interface : menus deroulants                                             }
{ ---------------------------------------------------------------------- }

Function CmdChecked(Cmd: Integer): Boolean;
Begin
 Case Cmd Of
  CM_MOUTH: CmdChecked := OptMouth;
  CM_KEEPFPS: CmdChecked := OptKeepFps;
  CM_KEEPFR: CmdChecked := OptKeepFrames;
  CM_ENHANCE: CmdChecked := OptEnhance;
  CM_MAPF: CmdChecked := OptMap;
  CM_MANY: CmdChecked := OptMany;
  CM_MIRROR: CmdChecked := OptMirror;
  CM_MARKS: CmdChecked := OptMarks;
  CM_SHOWFPS: CmdChecked := OptShowFps;
  CM_FAST: CmdChecked := OptFast;
  CM_SLOT1..CM_SLOT1 + N_SLOTS - 1: CmdChecked := CurSlot = Cmd - CM_SLOT1 + 1;
 Else CmdChecked := False;
 End;
End;

Function CmdEnabled(Cmd: Integer): Boolean;
Begin
 Case Cmd Of
  CM_ADJUST, CM_AUTODET, CM_CLEARFACE: CmdEnabled := Slots[CurSlot].Ok;
  CM_SWAPST: CmdEnabled := Slots[CurSlot].Ok And TargetOk;
  CM_STOP: CmdEnabled := Live;
  CM_SAVE, CM_CAPTURE: CmdEnabled := Res.D <> Nil;
 Else CmdEnabled := True;
 End;
End;

Procedure MItem(M: Integer; Const Cap, Sc: String; Cmd: Integer);
Begin
 With Menus[M] Do Begin
  Items[ItemCount].Caption := Cap;
  Items[ItemCount].Shortcut := Sc;
  Items[ItemCount].Cmd := Cmd;
  Items[ItemCount].Separator := False;
  Inc(ItemCount);
 End;
End;

Procedure MSep(M: Integer);
Begin
 With Menus[M] Do Begin
  Items[ItemCount].Caption := '';
  Items[ItemCount].Shortcut := '';
  Items[ItemCount].Cmd := 0;
  Items[ItemCount].Separator := True;
  Inc(ItemCount);
 End;
End;

Procedure InitMenus;
Var
 M, I, Need: Integer;
 Ct: String;
Begin
 FillChar(Menus, SizeOf(Menus), 0);
 Ct := L5('Ctrl+', 'Ctrl+', 'Strg+', 'Ctrl+', 'Ctrl+');
 Menus[MN_FILE].Title := L5('Fichier', 'File', 'Datei', 'Archivo', 'File');
 MItem(MN_FILE, L5('Choisir un visage...', 'Select a face...',
   'Gesicht wählen...', 'Elegir un rostro...', 'Scegli un volto...'),
   Ct + 'F', CM_SELFACE);
 MItem(MN_FILE, L5('Choisir une cible...', 'Select a target...',
   'Ziel wählen...', 'Elegir un objetivo...', 'Scegli un bersaglio...'),
   Ct + 'T', CM_SELTARGET);
 MSep(MN_FILE);
 MItem(MN_FILE, L5('Enregistrer le résultat...', 'Save the result...',
   'Ergebnis speichern...', 'Guardar el resultado...',
   'Salva il risultato...'), Ct + 'S', CM_SAVE);
 MItem(MN_FILE, L5('Capturer une image', 'Capture a frame',
   'Bild aufnehmen', 'Capturar un fotograma', 'Cattura un fotogramma'),
   'F9', CM_CAPTURE);
 MSep(MN_FILE);
 MItem(MN_FILE, L5('Quitter', 'Exit', 'Beenden', 'Salir', 'Esci'),
   Ct + 'Q', CM_QUIT);

 Menus[MN_FACE].Title := L5('Visage', 'Face', 'Gesicht', 'Rostro', 'Volto');
 MItem(MN_FACE, L5('Ajuster les repères...', 'Adjust landmarks...',
   'Punkte anpassen...', 'Ajustar puntos...', 'Regola i punti...'),
   Ct + 'A', CM_ADJUST);
 MItem(MN_FACE, L5('Détection automatique', 'Auto detection',
   'Automatische Erkennung', 'Detección automática',
   'Rilevamento automatico'), '', CM_AUTODET);
 MItem(MN_FACE, L5('Inverser source/cible', 'Swap source/target',
   'Quelle/Ziel tauschen', 'Intercambiar origen/destino',
   'Scambia origine/destinazione'), Ct + 'W', CM_SWAPST);
 MItem(MN_FACE, L5('Effacer le visage', 'Clear the face',
   'Gesicht löschen', 'Borrar el rostro', 'Cancella il volto'),
   '', CM_CLEARFACE);
 MSep(MN_FACE);
 For I := 1 To N_SLOTS Do
  MItem(MN_FACE, L5('Emplacement source ', 'Source slot ',
    'Quellplatz ', 'Ranura de origen ', 'Posizione origine ') + IStr(I),
    '', CM_SLOT1 + I - 1);

 Menus[MN_PROC].Title := L5('Traitement', 'Process', 'Verarbeitung',
                            'Proceso', 'Elaborazione');
 MItem(MN_PROC, L5('Démarrer', 'Start', 'Start', 'Iniciar', 'Avvia'),
   'F5', CM_START);
 MItem(MN_PROC, L5('Aperçu', 'Preview', 'Vorschau', 'Vista previa',
   'Anteprima'), 'F6', CM_PREVIEW);
 MItem(MN_PROC, L5('Direct (Live)', 'Live', 'Live', 'En vivo', 'Diretta'),
   'F7', CM_LIVE);
 MItem(MN_PROC, L5('Arrêter', 'Stop', 'Stopp', 'Detener', 'Ferma'),
   'F8', CM_STOP);
 MSep(MN_PROC);
 MItem(MN_PROC, L5('Masque de la bouche', 'Mouth Mask', 'Mundmaske',
   'Máscara de boca', 'Maschera bocca'), '', CM_MOUTH);
 MItem(MN_PROC, L5('Garder les FPS', 'Keep fps', 'FPS beibehalten',
   'Mantener fps', 'Mantieni fps'), '', CM_KEEPFPS);
 MItem(MN_PROC, L5('Garder les images', 'Keep frames', 'Bilder behalten',
   'Mantener fotogramas', 'Mantieni fotogrammi'), '', CM_KEEPFR);
 MItem(MN_PROC, L5('Amélioration du visage', 'Face Enhancer',
   'Gesichtsverbesserung', 'Mejora del rostro', 'Miglioramento volto'),
   '', CM_ENHANCE);
 MItem(MN_PROC, L5('Cartographier les visages', 'Map faces',
   'Gesichter zuordnen', 'Mapear rostros', 'Mappa i volti'), '', CM_MAPF);
 MItem(MN_PROC, L5('Plusieurs visages', 'Many faces', 'Mehrere Gesichter',
   'Varios rostros', 'Più volti'), '', CM_MANY);

 Menus[MN_CAM].Title := L5('Caméra', 'Camera', 'Kamera', 'Cámara',
                           'Fotocamera');
 MItem(MN_CAM, L5('Choisir la caméra...', 'Select camera...',
   'Kamera wählen...', 'Elegir cámara...', 'Scegli fotocamera...'),
   '', CM_CAMSEL);
 MItem(MN_CAM, L5('Effet miroir', 'Mirror', 'Spiegeln', 'Espejo',
   'Specchio'), '', CM_MIRROR);
 MItem(MN_CAM, L5('Recalibrer la peau', 'Recalibrate skin',
   'Haut neu kalibrieren', 'Recalibrar la piel', 'Ricalibra la pelle'),
   '', CM_SKIN);

 Menus[MN_VIEW].Title := L5('Affichage', 'View', 'Ansicht', 'Ver',
                            'Visualizza');
 MItem(MN_VIEW, L5('Afficher les repères', 'Show landmarks',
   'Punkte zeigen', 'Mostrar puntos', 'Mostra i punti'), '', CM_MARKS);
 MItem(MN_VIEW, L5('Afficher les FPS', 'Show FPS', 'FPS anzeigen',
   'Mostrar fps', 'Mostra fps'), '', CM_SHOWFPS);
 MItem(MN_VIEW, L5('Aperçu rapide', 'Fast preview', 'Schnelle Vorschau',
   'Vista rápida', 'Anteprima rapida'), '', CM_FAST);

 Menus[MN_HELP].Title := L5('Aide', 'Help', 'Hilfe', 'Ayuda', 'Aiuto');
 MItem(MN_HELP, L5('Raccourcis clavier...', 'Keyboard shortcuts...',
   'Tastenkürzel...', 'Atajos de teclado...', 'Scorciatoie...'),
   'F1', CM_HELP);
 MItem(MN_HELP, L5('À propos...', 'About...', 'Info...', 'Acerca de...',
   'Informazioni...'), '', CM_ABOUT);
 MItem(MN_HELP, L5('Avertissement...', 'Notice...', 'Hinweis...',
   'Aviso...', 'Avviso...'), '', CM_ETHICS);

 For M := 0 To MN_COUNT - 1 Do Begin
  Menus[M].Width := 120;
  For I := 0 To Menus[M].ItemCount - 1 Do
   If Not Menus[M].Items[I].Separator Then Begin
    Need := 28 + TW(Menus[M].Items[I].Caption);
    If Menus[M].Items[I].Shortcut <> '' Then
     Need := Need + 20 + TW(Menus[M].Items[I].Shortcut);
    If Need > Menus[M].Width Then Menus[M].Width := Need;
   End;
 End;
End;

{ Zone de l'interface (640 x 480, centree sur l'ecran) }
Procedure SetFullView;
Begin
 SetViewPort(ScrOX, ScrOY, ScrOX + UI_W - 1, ScrOY + UI_H - 1, True);
End;

{ Ecran complet (pour l'effacer) }
Procedure SetScreenView;
Begin
 SetViewPort(0, 0, GetMaxX, GetMaxY, True);
End;

{ Avant un menu ou un dialogue : la fenetre Direct3D (placee au-dessus de
  l'apercu) est masquee et la derniere image est redessinee par le logiciel,
  pour que le menu ou le dialogue puisse etre dessine par-dessus. }
Procedure GpuSuspend;
Begin
 {$IFDEF WINDOWS}
 If GpuOn And GpuVisible Then Begin
  GpuHide;
  SetFullView;
  ShadowOk := False;
  If PreviewHasImage And (Res.D <> Nil) Then ShowFrameSoft(Res);
 End;
 {$ENDIF}
End;

Procedure DrawMenuBar;
Var
 I, X: Integer;
Begin
 SetFullView;
 SetFillStyle(SolidFill, LightGray);
 Bar(0, 0, UI_W - 1, MENU_H - 1);
 SetColor(DarkGray);
 Line(0, MENU_H - 1, UI_W - 1, MENU_H - 1);
 X := 6;
 For I := 0 To MN_COUNT - 1 Do Begin
  Menus[I].X := X;
  If MenuActive And (ActiveMenu = I) Then Begin
   SetFillStyle(SolidFill, Blue);
   Bar(X - 4, 2, X + TW(Menus[I].Title) + 4, MENU_H - 3);
   SetColor(White);
  End
  Else SetColor(Black);
  DS(X, 6, Menus[I].Title);
  X := X + TW(Menus[I].Title) + 16;
 End;
End;

Procedure DrawDropdown(M: Integer);
Var
 I, X, Y, W, H, IH: Integer;
 En: Boolean;
Begin
 If (M < 0) Or (M >= MN_COUNT) Then Exit;
 SetFullView;
 IH := 18;
 X := Menus[M].X - 4;
 If X + Menus[M].Width > UI_W - 1 Then X := UI_W - 1 - Menus[M].Width - 2;
 Menus[M].X := X + 4;
 Y := MENU_H;
 W := Menus[M].Width;
 H := Menus[M].ItemCount * IH + 4;
 SetFillStyle(SolidFill, LightGray);
 Bar(X, Y, X + W, Y + H);
 SetColor(White);
 Line(X, Y, X + W, Y);
 Line(X, Y, X, Y + H);
 SetColor(DarkGray);
 Line(X + W, Y, X + W, Y + H);
 Line(X, Y + H, X + W, Y + H);
 SetColor(Black);
 Line(X + W + 1, Y + 1, X + W + 1, Y + H + 1);
 Line(X + 1, Y + H + 1, X + W + 1, Y + H + 1);
 For I := 0 To Menus[M].ItemCount - 1 Do Begin
  If Menus[M].Items[I].Separator Then Begin
   SetColor(DarkGray);
   Line(X + 3, Y + 2 + I * IH + IH Div 2, X + W - 3,
        Y + 2 + I * IH + IH Div 2);
   SetColor(White);
   Line(X + 3, Y + 3 + I * IH + IH Div 2, X + W - 3,
        Y + 3 + I * IH + IH Div 2);
  End
  Else Begin
   En := CmdEnabled(Menus[M].Items[I].Cmd);
   If ActiveItem = I Then Begin
    SetFillStyle(SolidFill, Blue);
    Bar(X + 2, Y + 2 + I * IH, X + W - 2, Y + 1 + (I + 1) * IH);
    If En Then SetColor(White) Else SetColor(LightGray);
   End
   Else If En Then SetColor(Black) Else SetColor(DarkGray);
   If CmdChecked(Menus[M].Items[I].Cmd) Then DS(X + 6, Y + 6 + I * IH, #251);
   DS(X + 20, Y + 6 + I * IH, Menus[M].Items[I].Caption);
   If Menus[M].Items[I].Shortcut <> '' Then
    DS(X + W - TW(Menus[M].Items[I].Shortcut) - 8, Y + 6 + I * IH,
       Menus[M].Items[I].Shortcut);
  End;
 End;
End;

Function MenuBarHit(MX, MY: LongInt): Integer;
Var
 I: Integer;
Begin
 MenuBarHit := -1;
 If MY >= MENU_H Then Exit;
 For I := 0 To MN_COUNT - 1 Do
  If (MX >= Menus[I].X - 4) And (MX <= Menus[I].X + TW(Menus[I].Title) + 4)
  Then Begin
   MenuBarHit := I;
   Exit;
  End;
End;

Function MenuItemHit(MX, MY: LongInt; M: Integer): Integer;
Var
 Idx: Integer;
Begin
 MenuItemHit := -1;
 If (M < 0) Or (M >= MN_COUNT) Then Exit;
 If (MX < Menus[M].X - 4) Or (MX > Menus[M].X - 4 + Menus[M].Width) Then Exit;
 If (MY < MENU_H + 2) Or (MY > MENU_H + Menus[M].ItemCount * 18 + 2) Then Exit;
 Idx := (MY - MENU_H - 2) Div 18;
 If (Idx < 0) Or (Idx >= Menus[M].ItemCount) Then Exit;
 If Menus[M].Items[Idx].Separator Then Exit;
 MenuItemHit := Idx;
End;

{ Sauvegarde / restauration de la zone sous un menu deroulant }
Procedure SaveUnder(M: Integer);
Var
 X, Y, W, H: Integer;
Begin
 SetFullView;
 X := Menus[M].X - 4;
 If X + Menus[M].Width > UI_W - 1 Then X := UI_W - 1 - Menus[M].Width - 2;
 Y := MENU_H;
 W := Menus[M].Width + 3;
 H := Menus[M].ItemCount * 18 + 8;
 UnderX := X;
 UnderY := Y;
 UnderSize := ImageSize(X, Y, X + W, Y + H);
 If UnderSize > 0 Then Begin
  GetMem(UnderBuf, UnderSize);
  GetImage(X, Y, X + W, Y + H, UnderBuf^);
  UnderValid := True;
 End;
End;

Procedure RestoreUnder;
Begin
 If UnderValid Then Begin
  SetFullView;
  PutImage(UnderX, UnderY, UnderBuf^, NormalPut);
  FreeMem(UnderBuf, UnderSize);
  UnderValid := False;
  { la zone de l'apercu a pu etre recouverte }
  ShadowOk := False;
 End;
End;

Procedure OpenMenu(M: Integer);
Begin
 If UnderValid Then RestoreUnder;
 MenuActive := True;
 ActiveMenu := M;
 ActiveItem := -1;
 HideMouse;
 GpuSuspend;
 DrawMenuBar;
 SaveUnder(M);
 DrawDropdown(M);
 ShowMouse;
End;

Procedure CloseMenu;
Begin
 If Not MenuActive Then Exit;
 HideMouse;
 RestoreUnder;
 MenuActive := False;
 ActiveItem := -1;
 DrawMenuBar;
 ShowMouse;
 {$IFDEF WINDOWS}
 If GpuOn And PreviewHasImage And (Res.D <> Nil) Then ShowFrame(Res);
 {$ENDIF}
End;

{ ---------------------------------------------------------------------- }
{ Interface : panneau principal                                            }
{ ---------------------------------------------------------------------- }

Const
 BTN_BLUE = 1;

Procedure ApplyUiPalette;
Begin
 If Not TrueMode Then Exit;
 UiRgbTab[0] := $1C1C1C;
 UiRgbTab[1] := $1F538D;
 UiRgbTab[8] := $4A4A4A;
 UiRgbTab[9] := $3B8ED0;
 UiRgbTab[7] := $D4D0C8;
End;

Procedure DrawButton(X1, Y1, X2, Y2: Integer; Const Cap: String;
                     Enabled: Boolean);
Begin
 If Enabled Then SetFillStyle(SolidFill, BTN_BLUE)
            Else SetFillStyle(SolidFill, DarkGray);
 Bar(X1, Y1, X2, Y2);
 SetColor(LightBlue);
 Rectangle(X1, Y1, X2, Y2);
 If Enabled Then SetColor(White) Else SetColor(LightGray);
 DSC(X1, Y1 + (Y2 - Y1 - 7) Div 2, X2 - X1 + 1, Cap);
End;

Procedure DrawSwitch(X, Y: Integer; On_: Boolean; Const Cap: String);
Begin
 SetFillStyle(SolidFill, Black);
 Bar(X, Y - 2, X + 270, Y + 14);
 If On_ Then SetFillStyle(SolidFill, LightBlue)
        Else SetFillStyle(SolidFill, DarkGray);
 Bar(X, Y, X + 27, Y + 11);
 SetColor(LightGray);
 Rectangle(X, Y, X + 27, Y + 11);
 SetFillStyle(SolidFill, White);
 If On_ Then Bar(X + 16, Y + 2, X + 25, Y + 9)
        Else Bar(X + 2, Y + 2, X + 11, Y + 9);
 SetColor(LightGray);
 DS(X + 36, Y + 2, Cap);
End;

Procedure AddWid(X1, Y1, X2, Y2, Cmd: Integer);
Begin
 If NWids >= MAX_WID Then Exit;
 Wids[NWids].X1 := X1;
 Wids[NWids].Y1 := Y1;
 Wids[NWids].X2 := X2;
 Wids[NWids].Y2 := Y2;
 Wids[NWids].Cmd := Cmd;
 Inc(NWids);
End;

Function WidHit(MX, MY: LongInt): Integer;
Var
 I: Integer;
Begin
 WidHit := CM_NONE;
 For I := 0 To NWids - 1 Do
  If (MX >= Wids[I].X1) And (MX <= Wids[I].X2) And (MY >= Wids[I].Y1) And
     (MY <= Wids[I].Y2) Then Begin
   WidHit := Wids[I].Cmd;
   Exit;
  End;
End;

Function Trunc_(Const S: String; MaxCh: Integer): String;
Begin
 If Length(U2C(S)) <= MaxCh Then Trunc_ := S
 Else Trunc_ := Copy(S, 1, MaxCh - 2) + '..';
End;

Procedure DrawThumbBox(X, Y, W, H: Integer; Var T: TImg; Const Cap: String);
Begin
 SetFillStyle(SolidFill, Black);
 Bar(X, Y, X + W - 1, Y + H - 1);
 SetColor(DarkGray);
 Rectangle(X - 1, Y - 1, X + W, Y + H);
 If T.D <> Nil Then
  BlitImg(T, X + (W - T.W) Div 2, Y + (H - T.H) Div 2)
 Else Begin
  SetColor(DarkGray);
  DSC(X, Y + H Div 2 - 4, W, Cap);
 End;
End;

{ Panneau de droite (reproduit la fenetre de Deep-Live-Cam) }
Procedure DrawPanel;
Var
 X0, I: Integer;
 En: Boolean;
 LiveCap: String;
 Tg: Array[0..5] Of Integer;
Begin
 X0 := PANEL_X + 4;
 NWids := 0;
 SetFillStyle(SolidFill, Black);
 Bar(PANEL_X, MENU_H + 1, UI_W - 1, UI_H - STATUS_H - 1);
 SetColor(LightCyan);
 DS(X0, 30, 'Time Motion Transfer');
 SetColor(DarkGray);
 DS(X0 + 168, 30, 'v' + VERSION_STR);
 DrawThumbBox(X0, 46, 128, 112, Slots[CurSlot].Thumb,
              L5('(aucun)', '(none)', '(keins)', '(ninguno)', '(nessuno)'));
 DrawThumbBox(X0 + 160, 46, 128, 112, TargetThumb,
              L5('(aucune)', '(none)', '(keins)', '(ninguno)', '(nessuno)'));
 AddWid(X0, 46, X0 + 127, 157, CM_ADJUST);
 DrawButton(X0 + 132, 90, X0 + 155, 112, '<>', True);
 AddWid(X0 + 132, 90, X0 + 155, 112, CM_SWAPST);
 DrawButton(X0, 164, X0 + 134, 186,
   L5('Choisir visage', 'Select a face', 'Gesicht wählen', 'Elegir rostro',
      'Scegli volto'), True);
 AddWid(X0, 164, X0 + 134, 186, CM_SELFACE);
 DrawButton(X0 + 154, 164, X0 + 288, 186,
   L5('Choisir cible', 'Select a target', 'Ziel wählen', 'Elegir objetivo',
      'Scegli bersaglio'), True);
 AddWid(X0 + 154, 164, X0 + 288, 186, CM_SELTARGET);
 Tg[0] := CM_MOUTH; Tg[1] := CM_KEEPFPS; Tg[2] := CM_KEEPFR;
 Tg[3] := CM_ENHANCE; Tg[4] := CM_MAPF; Tg[5] := CM_MANY;
 For I := 0 To 5 Do Begin
  DrawSwitch(X0 + 2, 198 + I * 20, CmdChecked(Tg[I]),
   Menus[MN_PROC].Items[5 + I].Caption);
  AddWid(X0, 196 + I * 20, X0 + 260, 212 + I * 20, Tg[I]);
 End;
 DrawButton(X0, 326, X0 + 134, 348,
   L5('Démarrer', 'Start', 'Start', 'Iniciar', 'Avvia'), True);
 AddWid(X0, 326, X0 + 134, 348, CM_START);
 DrawButton(X0 + 154, 326, X0 + 288, 348,
   L5('Aperçu', 'Preview', 'Vorschau', 'Vista previa', 'Anteprima'),
   True);
 AddWid(X0 + 154, 326, X0 + 288, 348, CM_PREVIEW);
 If Live Then
  LiveCap := L5('Arrêter', 'Stop', 'Stopp', 'Detener', 'Ferma')
 Else LiveCap := L5('Direct', 'Live', 'Live', 'En vivo', 'Diretta');
 DrawButton(X0, 354, X0 + 134, 376, LiveCap, True);
 AddWid(X0, 354, X0 + 134, 376, CM_LIVE);
 DrawButton(X0 + 154, 354, X0 + 288, 376,
   L5('Détruire', 'Destroy', 'Zerstören', 'Destruir', 'Distruggi'), True);
 AddWid(X0 + 154, 354, X0 + 288, 376, CM_DESTROY);
 SetColor(LightGray);
 DS(X0, 392, L5('Caméra :', 'Camera:', 'Kamera:', 'Cámara:', 'Fotocam.:'));
 SetFillStyle(SolidFill, Blue);
 Bar(X0 + 80, 386, X0 + 288, 404);
 SetColor(LightBlue);
 Rectangle(X0 + 80, 386, X0 + 288, 404);
 SetColor(White);
 If (CurCam >= 0) And (CurCam < NCams) Then
  DS(X0 + 84, 391, Trunc_(Cams[CurCam].Name, 25));
 DS(X0 + 276, 391, #31);
 AddWid(X0 + 80, 386, X0 + 288, 404, CM_CAMSEL);
 SetColor(DarkGray);
 DS(X0, 416, L5('F1 : aide  F7 : direct  F10 : menus',
                'F1: help  F7: live  F10: menus',
                'F1: Hilfe  F7: Live  F10: Menüs',
                'F1: ayuda  F7: vivo  F10: menús',
                'F1: aiuto  F7: diretta  F10: menu'));
End;

Procedure DrawPreviewPlaceholder;
Begin
 {$IFDEF WINDOWS}
 GpuHide;
 {$ENDIF}
 SetFillStyle(SolidFill, Black);
 Bar(PREV_X, PREV_Y, PREV_X + PREV_W - 1, PREV_Y + PREV_H - 1);
 SetColor(DarkGray);
 DSC(PREV_X, PREV_Y + PREV_H Div 2 - 20, PREV_W,
     L5('Aucune image', 'No image', 'Kein Bild', 'Sin imagen',
        'Nessuna immagine'));
 DSC(PREV_X, PREV_Y + PREV_H Div 2 - 4, PREV_W,
     L5('F7 : lancer la caméra', 'F7: start the camera',
        'F7: Kamera starten', 'F7: iniciar la cámara',
        'F7: avvia la fotocamera'));
End;

{ Colonne de gauche sous l'apercu : informations }
Procedure DrawInfo;
Var
 Y, I: Integer;
 S: String;
Begin
 SetFillStyle(SolidFill, Black);
 Bar(PREV_X - 2, PREV_Y + PREV_H + 4, PANEL_X - 6, UI_H - 82);
 SetColor(LightGray);
 Y := PREV_Y + PREV_H + 8;
 If Slots[CurSlot].Ok Then S := Slots[CurSlot].Name
  Else S := L5('(aucun)', '(none)', '(keins)', '(ninguno)', '(nessuno)');
 DS(PREV_X, Y, Trunc_(L5('Source : ', 'Source: ', 'Quelle: ', 'Origen: ',
                         'Origine: ') + S, 40));
 Inc(Y, 13);
 If TargetOk Then S := BaseName(TargetName)
  Else S := L5('(caméra)', '(camera)', '(Kamera)', '(cámara)',
               '(fotocamera)');
 DS(PREV_X, Y, Trunc_(L5('Cible : ', 'Target: ', 'Ziel: ', 'Destino: ',
                         'Bersaglio: ') + S, 40));
 Inc(Y, 13);
 If OptShowFps Then Begin
  Str(Fps:0:1, S);
  DS(PREV_X, Y, 'FPS: ' + S + '   ' + L5('Visages: ', 'Faces: ',
     'Gesichter: ', 'Rostros: ', 'Volti: ') + IStr(FaceCount));
 End;
 Inc(Y, 13);
 DS(PREV_X, Y, Trunc_(L5('Image : ', 'Frame: ', 'Bild: ', 'Imagen: ',
    'Immagine: ') + IStr(FW) + 'x' + IStr(FH) + '  ' + L5('Peau ', 'Skin ',
    'Haut ', 'Piel ', 'Pelle ') + IStr(SkinCb) + '/' + IStr(SkinCr), 40));
 Inc(Y, 13);
 If TrueMode Then S := 'x24'
 Else If Pal256 Then S := 'x256'
 Else S := 'x16';
 DS(PREV_X, Y, Trunc_(L5('Affichage : ', 'Display: ', 'Anzeige: ',
    'Pantalla: ', 'Schermo: ') + IStr(GetMaxX + 1) + 'x' +
    IStr(GetMaxY + 1) + S, 40));
 { journal }
 SetFillStyle(SolidFill, Black);
 Bar(0, UI_H - 76, UI_W - 1, UI_H - STATUS_H - 1);
 SetColor(DarkGray);
 Line(0, UI_H - 73, UI_W - 1, UI_H - 73);
 SetColor(LightGray);
 For I := 0 To LOG_N - 1 Do DS(8, UI_H - 68 + I * 11, Trunc_(LogTxt[I], 78));
End;

Procedure DrawStatus;
Begin
 SetFullView;
 SetFillStyle(SolidFill, LightGray);
 Bar(0, UI_H - STATUS_H, UI_W - 1, UI_H - 1);
 SetColor(White);
 Line(0, UI_H - STATUS_H, UI_W - 1, UI_H - STATUS_H);
 SetColor(Black);
 DS(6, UI_H - STATUS_H + 6, Trunc_(StatusMsg, 76));
End;

Procedure DrawPreviewBorder;
Begin
 SetColor(DarkGray);
 Rectangle(PREV_X - 1, PREV_Y - 1, PREV_X + PREV_W, PREV_Y + PREV_H);
End;

Procedure RedrawPreview;
Begin
 ShadowOk := False;
 DrawPreviewBorder;
 If PreviewHasImage And (Res.D <> Nil) Then ShowFrame(Res)
                                        Else DrawPreviewPlaceholder;
End;

Procedure RedrawAll;
Begin
 HideMouse;
 SetScreenView;
 SetFillStyle(SolidFill, Black);
 Bar(0, 0, GetMaxX, GetMaxY);
 SetFullView;
 DrawPanel;
 DrawInfo;
 RedrawPreview;
 DrawStatus;
 DrawMenuBar;
 ShowMouse;
End;

Procedure RefreshUi;
Begin
 If MenuActive Then Exit;
 HideMouse;
 DrawPanel;
 DrawInfo;
 DrawStatus;
 ShowMouse;
End;

{ ---------------------------------------------------------------------- }
{ Entrees clavier / souris et fenetres de dialogue                         }
{ ---------------------------------------------------------------------- }

Const
 K_ESC = 27;
 K_ENTER = 13;
 K_BACK = 8;
 K_TAB = 9;
 K_UP = 256 + 72;
 K_DOWN = 256 + 80;
 K_LEFT = 256 + 75;
 K_RIGHT = 256 + 77;
 K_PGUP = 256 + 73;
 K_PGDN = 256 + 81;
 K_HOME = 256 + 71;
 K_END = 256 + 79;
 K_F1 = 256 + 59;
 K_F5 = 256 + 63;
 K_F6 = 256 + 64;
 K_F7 = 256 + 65;
 K_F8 = 256 + 66;
 K_F9 = 256 + 67;
 K_F10 = 256 + 68;
 K_ALTX = 256 + 45;
 MAXFE = 300;

Type
 TFE = Record
  Name: String[44];
  Dir: Boolean;
 End;

Var
 DlgX1, DlgY1, DlgX2, DlgY2: Integer;
 FE: Array[0..MAXFE - 1] Of TFE;
 FECount: Integer;

Procedure PollMouse;
Begin
 OMX := MX_;
 OMY := MY_;
 OMB := MB_;
 GetMouseState(MX_, MY_, MB_);
 MX_ := MX_ - ScrOX;
 MY_ := MY_ - ScrOY;
End;

Function MouseClicked: Boolean;
Begin
 MouseClicked := ((MB_ And 1) <> 0) And ((OMB And 1) = 0);
End;

{ Touche : -1 si aucune, code ASCII, ou 256 + code etendu }
Function GetKeyEx: Integer;
Var
 C: Char;
Begin
 GetKeyEx := -1;
 If Not KeyPressed Then Exit;
 C := ReadKey;
 If C = #0 Then Begin
  If KeyPressed Then GetKeyEx := 256 + Ord(ReadKey) Else GetKeyEx := 256;
 End
 Else GetKeyEx := Ord(C);
End;

Procedure WaitMouseUp;
Begin
 Repeat
  PollMouse;
  Delay(5);
 Until (MB_ And 1) = 0;
 OMB := 0;
End;

Procedure Frame3D(X1, Y1, X2, Y2: Integer; Raised: Boolean);
Begin
 If Raised Then SetColor(White) Else SetColor(DarkGray);
 Line(X1, Y1, X2, Y1);
 Line(X1, Y1, X1, Y2);
 If Raised Then SetColor(DarkGray) Else SetColor(White);
 Line(X2, Y1, X2, Y2);
 Line(X1, Y2, X2, Y2);
End;

Procedure DlgButton(X1, Y1, X2, Y2: Integer; Const Cap: String);
Begin
 SetFillStyle(SolidFill, LightGray);
 Bar(X1, Y1, X2, Y2);
 Frame3D(X1, Y1, X2, Y2, True);
 SetColor(Black);
 DSC(X1, Y1 + (Y2 - Y1 - 7) Div 2 + 1, X2 - X1 + 1, Cap);
End;

Procedure DlgFrame(W, H: Integer; Const Title: String);
Begin
 GpuSuspend;
 SetFullView;
 DlgX1 := (UI_W - W) Div 2;
 DlgY1 := (UI_H - H) Div 2;
 If DlgX1 < 0 Then DlgX1 := 0;
 If DlgY1 < 0 Then DlgY1 := 0;
 DlgX2 := DlgX1 + W - 1;
 DlgY2 := DlgY1 + H - 1;
 SetFillStyle(SolidFill, DarkGray);
 Bar(DlgX1 + 4, DlgY1 + 4, DlgX2 + 4, DlgY2 + 4);
 SetFillStyle(SolidFill, LightGray);
 Bar(DlgX1, DlgY1, DlgX2, DlgY2);
 Frame3D(DlgX1, DlgY1, DlgX2, DlgY2, True);
 SetFillStyle(SolidFill, Blue);
 Bar(DlgX1 + 3, DlgY1 + 3, DlgX2 - 3, DlgY1 + 19);
 SetColor(White);
 DS(DlgX1 + 10, DlgY1 + 8, Title);
End;

Function InBox(X1, Y1, X2, Y2: Integer): Boolean;
Begin
 InBox := (MX_ >= X1) And (MX_ <= X2) And (MY_ >= Y1) And (MY_ <= Y2);
End;

{ Lignes du message affiche par MsgBoxL (une chaine Pascal est limitee
  a 255 caracteres : les textes longs sont ajoutes ligne par ligne) }
Var
 MsgL: Array[0..15] Of String[78];
 MsgN: Integer;

Procedure MsgClear;
Begin
 MsgN := 0;
End;

Procedure MsgAdd(Const S: String);
Begin
 If MsgN < 16 Then Begin
  MsgL[MsgN] := Copy(S, 1, 78);
  Inc(MsgN);
 End;
End;

{ Affiche les lignes MsgL ; retourne True pour OK / Oui }
Function MsgBoxL(Const Title: String; YesNo: Boolean): Boolean;
Var
 N, I, W, H, MaxW, BY: Integer;
 Done, Res_: Boolean;
 K: Integer;
 YesCap, NoCap: String;
Begin
 N := MsgN;
 MaxW := TW(Title) + 20;
 For I := 0 To N - 1 Do If TW(MsgL[I]) > MaxW Then MaxW := TW(MsgL[I]);
 W := MaxW + 40;
 If W < 280 Then W := 280;
 If W > 628 Then W := 628;
 H := 66 + N * 13 + 14;
 HideMouse;
 DlgFrame(W, H, Title);
 SetColor(Black);
 For I := 0 To N - 1 Do DS(DlgX1 + 20, DlgY1 + 32 + I * 13, MsgL[I]);
 BY := DlgY2 - 30;
 YesCap := L5('Oui', 'Yes', 'Ja', 'Sí', 'Sì');
 NoCap := L5('Non', 'No', 'Nein', 'No', 'No');
 If YesNo Then Begin
  DlgButton(DlgX1 + W Div 2 - 90, BY, DlgX1 + W Div 2 - 10, BY + 22, YesCap);
  DlgButton(DlgX1 + W Div 2 + 10, BY, DlgX1 + W Div 2 + 90, BY + 22, NoCap);
 End
 Else DlgButton(DlgX1 + W Div 2 - 40, BY, DlgX1 + W Div 2 + 40, BY + 22,
                'OK');
 ShowMouse;
 Done := False;
 Res_ := True;
 WaitMouseUp;
 Repeat
  PollMouse;
  K := GetKeyEx;
  If K = K_ENTER Then Done := True;
  If K = K_ESC Then Begin Done := True; Res_ := Not YesNo; End;
  If YesNo And ((K = Ord('n')) Or (K = Ord('N'))) Then Begin
   Done := True;
   Res_ := False;
  End;
  If YesNo And ((K = Ord('y')) Or (K = Ord('Y')) Or (K = Ord('o')) Or
     (K = Ord('O')) Or (K = Ord('j')) Or (K = Ord('J')) Or (K = Ord('s')) Or
     (K = Ord('S'))) Then Done := True;
  If MouseClicked Then Begin
   If YesNo Then Begin
    If InBox(DlgX1 + W Div 2 - 90, BY, DlgX1 + W Div 2 - 10, BY + 22) Then
     Done := True
    Else If InBox(DlgX1 + W Div 2 + 10, BY, DlgX1 + W Div 2 + 90, BY + 22)
    Then Begin
     Done := True;
     Res_ := False;
    End;
   End
   Else If InBox(DlgX1 + W Div 2 - 40, BY, DlgX1 + W Div 2 + 40, BY + 22) Then
    Done := True;
  End;
  Delay(10);
 Until Done;
 WaitMouseUp;
 MsgBoxL := Res_;
End;

{ Message : lignes separees par '|' ; retourne True pour OK / Oui }
Function MsgBox(Const Title, Text: String; YesNo: Boolean): Boolean;
Var
 P: Integer;
 S: String;
Begin
 MsgClear;
 S := Text;
 While (S <> '') And (MsgN < 16) Do Begin
  P := Pos('|', S);
  If P = 0 Then Begin MsgAdd(S); S := ''; End
  Else Begin MsgAdd(Copy(S, 1, P - 1)); S := Copy(S, P + 1, 255); End;
 End;
 MsgBox := MsgBoxL(Title, YesNo);
End;

{ Saisie d'une ligne de texte }
Function InputDlg(Const Title, Prompt: String; Var S: String;
                  MaxLen: Integer): Boolean;
Var
 W, K, BY: Integer;
 Done, Ok: Boolean;
 Old: String;
 Blink: LongInt;
 Procedure Draw;
 Begin
  HideMouse;
  SetFillStyle(SolidFill, White);
  Bar(DlgX1 + 16, DlgY1 + 56, DlgX2 - 16, DlgY1 + 72);
  Frame3D(DlgX1 + 16, DlgY1 + 56, DlgX2 - 16, DlgY1 + 72, False);
  SetColor(Black);
  DS(DlgX1 + 20, DlgY1 + 60, Copy(S, Length(S) - 50, 52) + '_');
  ShowMouse;
 End;
Begin
 Old := S;
 W := 460;
 HideMouse;
 DlgFrame(W, 120, Title);
 SetColor(Black);
 DS(DlgX1 + 16, DlgY1 + 34, Prompt);
 BY := DlgY2 - 30;
 DlgButton(DlgX1 + W Div 2 - 100, BY, DlgX1 + W Div 2 - 10, BY + 22, 'OK');
 DlgButton(DlgX1 + W Div 2 + 10, BY, DlgX1 + W Div 2 + 100, BY + 22,
           L5('Annuler', 'Cancel', 'Abbruch', 'Cancelar', 'Annulla'));
 ShowMouse;
 Draw;
 Done := False;
 Ok := False;
 WaitMouseUp;
 Repeat
  PollMouse;
  K := GetKeyEx;
  If K = K_ENTER Then Begin Done := True; Ok := True; End
  Else If K = K_ESC Then Done := True
  Else If K = K_BACK Then Begin
   If Length(S) > 0 Then Delete(S, Length(S), 1);
   Draw;
  End
  Else If (K >= 32) And (K < 256) And (Length(S) < MaxLen) Then Begin
   S := S + Chr(K);
   Draw;
  End;
  If MouseClicked Then Begin
   If InBox(DlgX1 + W Div 2 - 100, BY, DlgX1 + W Div 2 - 10, BY + 22) Then Begin
    Done := True;
    Ok := True;
   End
   Else If InBox(DlgX1 + W Div 2 + 10, BY, DlgX1 + W Div 2 + 100, BY + 22)
   Then Done := True;
  End;
  Delay(10);
 Until Done;
 WaitMouseUp;
 If Not Ok Then S := Old;
 InputDlg := Ok;
End;

{ --- Selecteur de fichiers --- }

Function ParentDir(Const D: String): String;
Var
 I: Integer;
Begin
 I := Length(D);
 If (I > 0) And ((D[I] = '\') Or (D[I] = '/')) Then Dec(I);
 While (I > 0) And (D[I] <> '\') And (D[I] <> '/') Do Dec(I);
 If I <= 1 Then ParentDir := PathSep
 Else If (I = 3) And (D[2] = ':') Then ParentDir := Copy(D, 1, 3)
 Else ParentDir := Copy(D, 1, I - 1);
 {$IFNDEF UNIX}
 If (I = 0) And (Length(D) >= 2) And (D[2] = ':') Then
  ParentDir := Copy(D, 1, 2) + '\';
 {$ENDIF}
End;

Function JoinPath(Const D, N: String): String;
Begin
 If (D <> '') And ((D[Length(D)] = '\') Or (D[Length(D)] = '/')) Then
  JoinPath := D + N
 Else JoinPath := D + PathSep + N;
End;

Function ImgExt(Const N: String; SaveMode: Boolean): Boolean;
Var
 E: String;
Begin
 E := ExtOf(N);
 If SaveMode Then ImgExt := E = '.BMP'
 Else ImgExt := (E = '.BMP') Or (E = '.PPM') Or (E = '.PGM') Or
                (E = '.JPG') Or (E = '.JPEG') Or (E = '.PNG');
End;

Procedure ScanDir(Const Dir: String; SaveMode: Boolean);
Var
 SR: SearchRec;
 I, J: Integer;
 T: TFE;
 Pat: String;
Begin
 FECount := 0;
 FE[0].Name := '..';
 FE[0].Dir := True;
 FECount := 1;
 {$IFDEF UNIX}
 Pat := JoinPath(Dir, '*');
 {$ELSE}
 Pat := JoinPath(Dir, '*.*');
 {$ENDIF}
 FindFirst(Pat, AnyFile, SR);
 While (DosError = 0) And (FECount < MAXFE) Do Begin
  If (SR.Name <> '.') And (SR.Name <> '..') Then Begin
   If (SR.Attr And Directory) <> 0 Then Begin
    FE[FECount].Name := Copy(SR.Name, 1, 44);
    FE[FECount].Dir := True;
    Inc(FECount);
   End
   Else If ImgExt(SR.Name, SaveMode) Then Begin
    FE[FECount].Name := Copy(SR.Name, 1, 44);
    FE[FECount].Dir := False;
    Inc(FECount);
   End;
  End;
  FindNext(SR);
 End;
 {$IFDEF FPC}
 FindClose(SR);
 {$ENDIF}
 { tri : dossiers d'abord, puis par nom }
 For I := 1 To FECount - 2 Do
  For J := I + 1 To FECount - 1 Do
   If (FE[J].Dir And Not FE[I].Dir) Or
      ((FE[J].Dir = FE[I].Dir) And (UpStr(FE[J].Name) < UpStr(FE[I].Name)))
   Then Begin
    T := FE[I]; FE[I] := FE[J]; FE[J] := T;
   End;
End;

{ Retourne True et le chemin complet dans Path si un fichier est choisi }
Function FileDlg(Const Title: String; SaveMode: Boolean;
                 Var Path: String): Boolean;
Const
 ROWS = 15;
 RH = 13;
Var
 Dir, Name_, S: String;
 Sel, Top, I, K, W, H, LX1, LY1, LX2, LY2, BY: Integer;
 Done, Ok, Fresh: Boolean;
 LastT: LongInt;
 LastSel: Integer;
 Procedure DrawList;
 Var
  R, Idx: Integer;
 Begin
  HideMouse;
  SetFillStyle(SolidFill, White);
  Bar(LX1, LY1, LX2, LY2);
  Frame3D(LX1 - 1, LY1 - 1, LX2 + 1, LY2 + 1, False);
  For R := 0 To ROWS - 1 Do Begin
   Idx := Top + R;
   If Idx < FECount Then Begin
    If Idx = Sel Then Begin
     SetFillStyle(SolidFill, Blue);
     Bar(LX1 + 1, LY1 + R * RH + 1, LX2 - 1, LY1 + R * RH + RH);
     SetColor(White);
    End
    Else SetColor(Black);
    If FE[Idx].Dir Then DS(LX1 + 4, LY1 + R * RH + 3, '[' + FE[Idx].Name + ']')
                   Else DS(LX1 + 4, LY1 + R * RH + 3, FE[Idx].Name);
   End;
  End;
  { ascenseur }
  SetFillStyle(SolidFill, LightGray);
  Bar(LX2 + 3, LY1, LX2 + 15, LY2);
  If FECount > ROWS Then Begin
   SetFillStyle(SolidFill, DarkGray);
   Bar(LX2 + 4, LY1 + (LY2 - LY1 - 20) * Top Div (FECount - ROWS),
       LX2 + 14, LY1 + (LY2 - LY1 - 20) * Top Div (FECount - ROWS) + 20);
  End;
  ShowMouse;
 End;
 Procedure DrawFields;
 Begin
  HideMouse;
  SetFillStyle(SolidFill, LightGray);
  Bar(DlgX1 + 8, DlgY1 + 24, DlgX2 - 8, DlgY1 + 40);
  SetColor(Black);
  DS(DlgX1 + 12, DlgY1 + 28, Copy(Dir, Length(Dir) - 62, 64));
  SetFillStyle(SolidFill, White);
  Bar(DlgX1 + 76, BY - 26, DlgX2 - 12, BY - 10);
  Frame3D(DlgX1 + 76, BY - 26, DlgX2 - 12, BY - 10, False);
  SetColor(Black);
  DS(DlgX1 + 80, BY - 22, Copy(Name_, Length(Name_) - 50, 52) + '_');
  ShowMouse;
 End;
 Procedure Enter_(Const NewDir: String);
 Begin
  Dir := NewDir;
  ScanDir(Dir, SaveMode);
  Sel := 0;
  Top := 0;
  DrawList;
  DrawFields;
 End;
 Procedure Accept;
 Var
  F: String;
  SR: SearchRec;
 Begin
  If Name_ = '' Then Begin
   If (Sel >= 0) And (Sel < FECount) Then Begin
    If FE[Sel].Dir Then Begin
     If FE[Sel].Name = '..' Then Enter_(ParentDir(Dir))
     Else Enter_(JoinPath(Dir, FE[Sel].Name));
    End
    Else Begin
     Path := JoinPath(Dir, FE[Sel].Name);
     Done := True;
     Ok := True;
    End;
   End;
   Exit;
  End;
  If (Pos('/', Name_) > 0) Or (Pos('\', Name_) > 0) Or
     ((Length(Name_) = 2) And (Name_[2] = ':')) Then F := Name_
  Else F := JoinPath(Dir, Name_);
  If (F[Length(F)] = '\') Or (F[Length(F)] = '/') Or
     ((Length(F) = 2) And (F[2] = ':')) Then Begin
   { racine ou lecteur : on change de dossier }
   If F[Length(F)] = ':' Then F := F + '\';
   Name_ := '';
   Enter_(F);
   Exit;
  End;
  FindFirst(F, AnyFile, SR);
  If (DosError = 0) And ((SR.Attr And Directory) <> 0) Then Begin
   {$IFDEF FPC}
   FindClose(SR);
   {$ENDIF}
   Name_ := '';
   Enter_(F);
   Exit;
  End;
  {$IFDEF FPC}
  FindClose(SR);
  {$ENDIF}
  If SaveMode And (ExtOf(F) = '') Then F := F + '.bmp';
  Path := F;
  Done := True;
  Ok := True;
 End;
Begin
 W := 540;
 H := 306;
 GetDir(0, Dir);
 If LastDir <> '' Then Dir := LastDir;
 If Dir = '' Then Dir := PathSep;
 Name_ := '';
 Fresh := False;
 If SaveMode Then Begin
  Name_ := BaseName(Path);
  Fresh := True;
 End;
 HideMouse;
 DlgFrame(W, H, Title);
 BY := DlgY2 - 30;
 LX1 := DlgX1 + 12;
 LY1 := DlgY1 + 46;
 LX2 := DlgX2 - 30;
 LY2 := LY1 + ROWS * RH + 1;
 SetColor(Black);
 DS(DlgX1 + 12, BY - 22, L5('Nom :', 'Name:', 'Name:', 'Nombre:', 'Nome:'));
 DlgButton(DlgX2 - 190, BY, DlgX2 - 110, BY + 22, 'OK');
 DlgButton(DlgX2 - 100, BY, DlgX2 - 12, BY + 22,
           L5('Annuler', 'Cancel', 'Abbruch', 'Cancelar', 'Annulla'));
 ShowMouse;
 ScanDir(Dir, SaveMode);
 Sel := 0;
 Top := 0;
 LastSel := -1;
 LastT := 0;
 DrawList;
 DrawFields;
 Done := False;
 Ok := False;
 WaitMouseUp;
 Repeat
  PollMouse;
  K := GetKeyEx;
  Case K Of
   K_ESC: Done := True;
   K_ENTER: Accept;
   K_UP: If Sel > 0 Then Begin Dec(Sel); Name_ := ''; End;
   K_DOWN: If Sel < FECount - 1 Then Begin Inc(Sel); Name_ := ''; End;
   K_PGUP: Begin Sel := IMax(0, Sel - ROWS); Name_ := ''; End;
   K_PGDN: Begin Sel := IMin(FECount - 1, Sel + ROWS); Name_ := ''; End;
   K_HOME: Begin Sel := 0; Name_ := ''; End;
   K_END: Begin Sel := FECount - 1; Name_ := ''; End;
   K_BACK: Begin
    Fresh := False;
    If Length(Name_) > 0 Then Delete(Name_, Length(Name_), 1);
   End;
  Else
   If (K >= 32) And (K < 256) And (Length(Name_) < 200) Then Begin
    If Fresh Then Name_ := '';
    Fresh := False;
    Name_ := Name_ + Chr(K);
   End;
  End;
  If K >= 0 Then Begin
   If Sel < Top Then Top := Sel;
   If Sel >= Top + ROWS Then Top := Sel - ROWS + 1;
   DrawList;
   DrawFields;
  End;
  If MouseClicked Then Begin
   If InBox(LX1, LY1, LX2, LY2) Then Begin
    I := Top + (MY_ - LY1) Div RH;
    If (I >= 0) And (I < FECount) Then Begin
     If (I = LastSel) And (ElapsedMs(LastT) < 500) Then Begin
      Sel := I;
      Name_ := '';
      Accept;
     End
     Else Begin
      Sel := I;
      Name_ := '';
      If Not FE[I].Dir Then Name_ := FE[I].Name;
      DrawList;
      DrawFields;
     End;
     LastSel := I;
     LastT := NowMs;
    End;
   End
   Else If InBox(LX2 + 3, LY1, LX2 + 15, LY2) And (FECount > ROWS) Then Begin
    If MY_ < (LY1 + LY2) Div 2 Then Top := IMax(0, Top - ROWS)
    Else Top := IMin(FECount - ROWS, Top + ROWS);
    DrawList;
   End
   Else If InBox(DlgX2 - 190, BY, DlgX2 - 110, BY + 22) Then Accept
   Else If InBox(DlgX2 - 100, BY, DlgX2 - 12, BY + 22) Then Done := True;
  End;
  Delay(10);
 Until Done;
 WaitMouseUp;
 If Ok Then Begin
  LastDir := ParentDir(Path);
  If (Length(Path) > 0) And (Pos(PathSep, Path) = 0) Then LastDir := Dir;
 End;
 FileDlg := Ok;
End;

{ Liste de choix : les cameras }
Function CamDlg(Var Sel: Integer): Boolean;
Const
 PVW = 192;
 PVH = 144;
Var
 W, H, I, K, BY, Orig, PrevSel, PX, PY: Integer;
 Done, Ok, WasOpen, PrevOk, Shown: Boolean;
 SelT, LastT, T: LongInt;
 Th: TImg;
 Procedure PvBox(Const Msg: String);
 Begin
  HideMouse;
  SetFillStyle(SolidFill, Black);
  Bar(PX, PY, PX + PVW - 1, PY + PVH - 1);
  SetColor(LightGray);
  DS(PX + 10, PY + PVH Div 2 - 4, Msg);
  ShowMouse;
 End;
 Procedure PvFrame;
 Begin
  If Not CamGrab(Cur) Then Exit;
  MakeThumb(Cur, Th, PVW, PVH);
  If Th.D = Nil Then Exit;
  HideMouse;
  If (Th.W < PVW) Or (Th.H < PVH) Then Begin
   SetFillStyle(SolidFill, Black);
   Bar(PX, PY, PX + PVW - 1, PY + PVH - 1);
  End;
  BlitImg(Th, PX + (PVW - Th.W) Div 2, PY + (PVH - Th.H) Div 2);
  ShowMouse;
  Shown := True;
 End;
 Procedure PvStart;
 Begin
  CamStop;
  Shown := False;
  PvBox(L5('Ouverture de la camera...', 'Opening camera...',
           'Kamera wird geoeffnet...', 'Abriendo la camara...',
           'Apertura fotocamera...'));
  PrevOk := CamStart(Sel);
  PrevSel := Sel;
  LastT := NowMs;
  If Not PrevOk Then
   PvBox(L5('Camera indisponible.', 'Camera unavailable.',
            'Kamera nicht verfuegbar.', 'Camara no disponible.',
            'Fotocamera non disponibile.'));
 End;
 Procedure DrawL;
 Var
  R: Integer;
 Begin
  HideMouse;
  SetFillStyle(SolidFill, White);
  Bar(DlgX1 + 12, DlgY1 + 30, DlgX2 - 12, DlgY1 + 30 + NCams * 14 + 4);
  For R := 0 To NCams - 1 Do Begin
   If R = Sel Then Begin
    SetFillStyle(SolidFill, Blue);
    Bar(DlgX1 + 13, DlgY1 + 32 + R * 14, DlgX2 - 13, DlgY1 + 45 + R * 14);
    SetColor(White);
   End
   Else SetColor(Black);
   DS(DlgX1 + 18, DlgY1 + 35 + R * 14, Trunc_(Cams[R].Name, 56));
  End;
  ShowMouse;
 End;
Begin
 W := 520;
 H := 100 + NCams * 14 + PVH + 12;
 Orig := Sel;
 WasOpen := CamOpened;
 If WasOpen Then CamStop;
 PrevSel := -1;
 PrevOk := False;
 Th.D := Nil;
 Th.A := Nil;
 Th.W := 0;
 Th.H := 0;
 HideMouse;
 DlgFrame(W, H, L5('Choisir la caméra', 'Select camera', 'Kamera wählen',
                   'Elegir cámara', 'Scegli fotocamera'));
 BY := DlgY2 - 30;
 DlgButton(DlgX1 + W Div 2 - 100, BY, DlgX1 + W Div 2 - 10, BY + 22, 'OK');
 DlgButton(DlgX1 + W Div 2 + 10, BY, DlgX1 + W Div 2 + 100, BY + 22,
           L5('Annuler', 'Cancel', 'Abbruch', 'Cancelar', 'Annulla'));
 ShowMouse;
 DrawL;
 PX := DlgX1 + 14;
 PY := DlgY1 + 30 + NCams * 14 + 10;
 SelT := NowMs;
 PvBox('');
 Done := False;
 Ok := False;
 WaitMouseUp;
 Repeat
  PollMouse;
  K := GetKeyEx;
  { apercu : ouverture apres un court delai de stabilite de la selection,
    puis rafraichissement environ 10 fois par seconde }
  T := NowMs;
  If PrevSel <> Sel Then Begin
   If Abs(T - SelT) > 250 Then PvStart;
  End
  Else If PrevOk And (Abs(T - LastT) >= 90) Then Begin
   PvFrame;
   LastT := NowMs;
  End;
  If K = K_ESC Then Done := True
  Else If K = K_ENTER Then Begin Done := True; Ok := True; End
  Else If (K = K_UP) And (Sel > 0) Then Begin Dec(Sel); DrawL; SelT := NowMs; End
  Else If (K = K_DOWN) And (Sel < NCams - 1) Then Begin
   Inc(Sel); DrawL; SelT := NowMs;
  End;
  If MouseClicked Then Begin
   If InBox(DlgX1 + 12, DlgY1 + 32, DlgX2 - 12, DlgY1 + 32 + NCams * 14) Then
   Begin
    I := (MY_ - DlgY1 - 32) Div 14;
    If (I >= 0) And (I < NCams) And (I <> Sel) Then Begin
     Sel := I; DrawL; SelT := NowMs;
    End;
   End
   Else If InBox(DlgX1 + W Div 2 - 100, BY, DlgX1 + W Div 2 - 10, BY + 22)
   Then Begin Done := True; Ok := True; End
   Else If InBox(DlgX1 + W Div 2 + 10, BY, DlgX1 + W Div 2 + 100, BY + 22)
   Then Done := True;
  End;
  Delay(10);
 Until Done;
 WaitMouseUp;
 CamStop;
 ImgFree(Th);
 { la camera du direct (si elle tournait) est rouverte telle qu'elle etait }
 If WasOpen Then CamStart(Orig);
 CamDlg := Ok;
End;

{ Ajustement manuel des reperes du visage (yeux et bouche) sur la photo }
Function LandmarkDlg(Var Ph: TImg; Var F: TFace): Boolean;
Var
 View: TImg;
 W, H, VX, VY, VW, VH, BY, Cur_, K, I: Integer;
 Sc: Real;
 Done, Ok: Boolean;
 Px, Py: Array[0..2] Of Real;
 Procedure Marker(N: Integer);
 Var
  X, Y: Integer;
 Begin
  X := VX + RoundL(Px[N] * Sc);
  Y := VY + RoundL(Py[N] * Sc);
  If N = 2 Then SetColor(LightMagenta) Else SetColor(LightGreen);
  Line(X - 7, Y, X + 7, Y);
  Line(X, Y - 7, X, Y + 7);
  Circle(X, Y, 6);
  If N = Cur_ Then Begin
   SetColor(Yellow);
   Rectangle(X - 9, Y - 9, X + 9, Y + 9);
  End;
 End;
 Procedure Draw;
 Var
  N: Integer;
 Begin
  HideMouse;
  BlitImg(View, VX, VY);
  For N := 0 To 2 Do Marker(N);
  SetFillStyle(SolidFill, LightGray);
  Bar(DlgX1 + 4, DlgY2 - 56, DlgX2 - 4, DlgY2 - 4);
  SetColor(Black);
  Case Cur_ Of
   0: DS(DlgX1 + 10, DlgY2 - 50, L5(
        'Cliquez sur l''oeil GAUCHE (côté gauche de l''image)',
        'Click the LEFT eye (left side of the image)',
        'Linkes Auge anklicken (linke Bildseite)',
        'Pulse el ojo IZQUIERDO (lado izquierdo de la imagen)',
        'Clicca l''occhio SINISTRO (lato sinistro dell''immagine)'));
   1: DS(DlgX1 + 10, DlgY2 - 50, L5('Cliquez sur l''oeil DROIT',
        'Click the RIGHT eye', 'Rechtes Auge anklicken',
        'Pulse el ojo DERECHO', 'Clicca l''occhio DESTRO'));
  Else DS(DlgX1 + 10, DlgY2 - 50, L5('Cliquez sur le centre de la BOUCHE',
        'Click the center of the MOUTH', 'Mitte des MUNDES anklicken',
        'Pulse el centro de la BOCA', 'Clicca il centro della BOCCA'));
  End;
  DS(DlgX1 + 10, DlgY2 - 36, L5(
     'Entrée : valider   A : auto   Tab : point suivant   Échap : annuler',
     'Enter: accept   A: auto   Tab: next point   Esc: cancel',
     'Enter: OK   A: Auto   Tab: nächster Punkt   Esc: Abbruch',
     'Intro: aceptar   A: auto   Tab: siguiente   Esc: cancelar',
     'Invio: ok   A: auto   Tab: punto successivo   Esc: annulla'));
  ShowMouse;
 End;
 Procedure Auto;
 Var
  L: TFaceList;
  N: Integer;
  S0: Array[0..3] Of LongInt;
 Begin
  S0[0] := SkinCb; S0[1] := SkinCr; S0[2] := SkinDCb; S0[3] := SkinDCr;
  SkinReset;
  N := DetectFaces(Ph, L, 1);
  SkinCb := S0[0]; SkinCr := S0[1]; SkinDCb := S0[2]; SkinDCr := S0[3];
  If N > 0 Then Begin
   Px[0] := L[0].ELx; Py[0] := L[0].ELy;
   Px[1] := L[0].ERx; Py[1] := L[0].ERy;
   Px[2] := L[0].Mx; Py[2] := L[0].My;
  End
  Else Begin
   { hypothese : portrait centre }
   Px[0] := Ph.W * 0.38; Py[0] := Ph.H * 0.40;
   Px[1] := Ph.W * 0.62; Py[1] := Ph.H * 0.40;
   Px[2] := Ph.W * 0.50; Py[2] := Ph.H * 0.62;
  End;
 End;
Begin
 LandmarkDlg := False;
 W := 628;
 H := 466;
 VW := W - 20;
 VH := H - 100;
 Sc := RMin(VW / Ph.W, VH / Ph.H);
 If Sc > 1.0 Then Sc := 1.0;
 If Not ImgNew(View, IMax(1, RoundL(Ph.W * Sc)), IMax(1, RoundL(Ph.H * Sc)),
               False) Then Exit;
 ImgResize(Ph, View);
 Sc := View.W / Ph.W;
 HideMouse;
 DlgFrame(W, H, L5('Repères du visage source', 'Source face landmarks',
                   'Punkte des Quellgesichts', 'Puntos del rostro de origen',
                   'Punti del volto di origine'));
 VX := DlgX1 + (W - View.W) Div 2;
 VY := DlgY1 + 26 + (VH - View.H) Div 2;
 BY := DlgY2 - 28;
 DlgButton(DlgX2 - 270, BY, DlgX2 - 190, BY + 22, 'OK');
 DlgButton(DlgX2 - 180, BY, DlgX2 - 100, BY + 22, 'Auto');
 DlgButton(DlgX2 - 90, BY, DlgX2 - 10, BY + 22,
           L5('Annuler', 'Cancel', 'Abbruch', 'Cancelar', 'Annulla'));
 ShowMouse;
 If F.Ok Then Begin
  Px[0] := F.ELx; Py[0] := F.ELy; Px[1] := F.ERx; Py[1] := F.ERy;
  Px[2] := F.Mx; Py[2] := F.My;
 End
 Else Auto;
 Cur_ := 0;
 Draw;
 Done := False;
 Ok := False;
 WaitMouseUp;
 Repeat
  PollMouse;
  K := GetKeyEx;
  If K = K_ENTER Then Begin Done := True; Ok := True; End
  Else If K = K_ESC Then Done := True
  Else If K = K_TAB Then Begin Cur_ := (Cur_ + 1) Mod 3; Draw; End
  Else If (K = Ord('a')) Or (K = Ord('A')) Then Begin Auto; Draw; End
  Else If (K >= Ord('1')) And (K <= Ord('3')) Then Begin
   Cur_ := K - Ord('1');
   Draw;
  End;
  If MouseClicked Then Begin
   If InBox(VX, VY, VX + View.W - 1, VY + View.H - 1) Then Begin
    Px[Cur_] := (MX_ - VX) / Sc;
    Py[Cur_] := (MY_ - VY) / Sc;
    Cur_ := (Cur_ + 1) Mod 3;
    Draw;
   End
   Else If InBox(DlgX2 - 270, BY, DlgX2 - 190, BY + 22) Then Begin
    Done := True;
    Ok := True;
   End
   Else If InBox(DlgX2 - 180, BY, DlgX2 - 100, BY + 22) Then Begin
    Auto;
    Draw;
   End
   Else If InBox(DlgX2 - 90, BY, DlgX2 - 10, BY + 22) Then Done := True;
  End;
  Delay(10);
 Until Done;
 WaitMouseUp;
 ImgFree(View);
 If Ok Then Begin
  If Px[1] < Px[0] Then Begin
   { yeux inverses : on les echange }
   Sc := Px[0]; Px[0] := Px[1]; Px[1] := Sc;
   Sc := Py[0]; Py[0] := Py[1]; Py[1] := Sc;
  End;
  F.Ok := True;
  F.ELx := Px[0]; F.ELy := Py[0];
  F.ERx := Px[1]; F.ERy := Py[1];
  F.Mx := Px[2]; F.My := Py[2];
  LandmarkDlg := True;
 End;
End;

{ ---------------------------------------------------------------------- }
{ Commandes                                                                }
{ ---------------------------------------------------------------------- }

Var
 TargetRes: TImg;
 LiveFails: Integer;
 CapCount: LongInt;
 FramesDirOk: Boolean;

Procedure ShowError(Const Msg: String);
Begin
 MsgBox(L5('Erreur', 'Error', 'Fehler', 'Error', 'Errore'), Msg, False);
 RedrawAll;
End;

Procedure Info(Const S: String);
Begin
 LogAdd(S);
 SetStatus(S);
End;

{ Fait entrer une image dans la trame FW x FH (barres noires si besoin) }
Procedure FitToFrame(Var Src, Dst: TImg);
Var
 Sc: Real;
 TW_, TH_, X0, Y0, Y: LongInt;
 T: TImg;
Begin
 If (Src.D = Nil) Or (Dst.D = Nil) Then Exit;
 FillChar(Dst.D^, Dst.W * Dst.H * 3, 0);
 Sc := RMin(Dst.W / Src.W, Dst.H / Src.H);
 TW_ := IMax(1, RoundL(Src.W * Sc));
 TH_ := IMax(1, RoundL(Src.H * Sc));
 If TW_ > Dst.W Then TW_ := Dst.W;
 If TH_ > Dst.H Then TH_ := Dst.H;
 If Not ImgNew(T, TW_, TH_, False) Then Exit;
 ImgResize(Src, T);
 X0 := (Dst.W - TW_) Div 2;
 Y0 := (Dst.H - TH_) Div 2;
 For Y := 0 To TH_ - 1 Do
  Move(T.D^[Y * TW_ * 3], Dst.D^[((Y0 + Y) * Dst.W + X0) * 3], TW_ * 3);
 ImgFree(T);
End;

{ Installe une photo comme visage source (detection + validation) }
Function InstallSource(Var Photo: TImg; Const Name: String): Boolean;
Var
 L: TFaceList;
 N: Integer;
 F: TFace;
 S0: Array[0..3] Of LongInt;
Begin
 InstallSource := False;
 S0[0] := SkinCb; S0[1] := SkinCr; S0[2] := SkinDCb; S0[3] := SkinDCr;
 SkinReset;
 N := DetectFaces(Photo, L, 1);
 SkinCb := S0[0]; SkinCr := S0[1]; SkinDCb := S0[2]; SkinDCr := S0[3];
 FillChar(F, SizeOf(F), 0);
 If N > 0 Then Begin
  F := L[0];
  Info(L5('Visage détecté dans la photo : vérifiez les repères.',
          'Face detected in the photo: check the landmarks.',
          'Gesicht im Foto erkannt: Punkte prüfen.',
          'Rostro detectado en la foto: compruebe los puntos.',
          'Volto rilevato nella foto: controlla i punti.'));
 End
 Else Info(L5('Aucun visage détecté : placez les repères à la souris.',
              'No face detected: place the landmarks with the mouse.',
              'Kein Gesicht erkannt: Punkte mit der Maus setzen.',
              'Ningún rostro detectado: coloque los puntos con el ratón.',
              'Nessun volto rilevato: posiziona i punti con il mouse.'));
 If Not LandmarkDlg(Photo, F) Then Begin
  ImgFree(Photo);
  Exit;
 End;
 ImgFree(Slots[CurSlot].Photo);
 ImgFree(Slots[CurSlot].Tpl);
 ImgFree(Slots[CurSlot].Tpl2);
 ImgFree(Slots[CurSlot].Thumb);
 Slots[CurSlot].Photo := Photo;
 Slots[CurSlot].Face := F;
 Slots[CurSlot].Name := Copy(Name, 1, 60);
 Slots[CurSlot].Ok := False;
 If BuildTemplate(Slots[CurSlot]) Then Begin
  BuildThumb(Slots[CurSlot], 128, 112);
  Slots[CurSlot].Ok := True;
  InstallSource := True;
 End
 Else Begin
  ImgFree(Slots[CurSlot].Photo);
  ShowError(L5('Repères invalides (yeux trop proches).',
               'Invalid landmarks (eyes too close).',
               'Ungültige Punkte (Augen zu nah).',
               'Puntos no válidos (ojos demasiado juntos).',
               'Punti non validi (occhi troppo vicini).'));
 End;
End;

Procedure CmdSelFace;
Var
 Path, Err: String;
 Img: TImg;
Begin
 Path := '';
 If Live Then Begin Live := False; CamStop; End;
 If FileDlg(L5('Choisir un visage (photo)', 'Select a face (photo)',
     'Gesicht wählen (Foto)', 'Elegir un rostro (foto)',
     'Scegli un volto (foto)'), False, Path) Then Begin
  RedrawAll;
  Info(L5('Chargement...', 'Loading...', 'Laden...', 'Cargando...',
          'Caricamento...'));
  DrawStatus;
  If LoadImageFile(Path, Img, Err) Then Begin
   If InstallSource(Img, BaseName(Path)) Then
    Info(L5('Visage source prêt : ', 'Source face ready: ',
            'Quellgesicht bereit: ', 'Rostro de origen listo: ',
            'Volto di origine pronto: ') + BaseName(Path));
  End
  Else Begin
   RedrawAll;
   ShowError(Err);
  End;
 End;
 RedrawAll;
End;

Procedure CmdSelTarget;
Var
 Path, Err: String;
 Img: TImg;
Begin
 Path := '';
 If Live Then Begin Live := False; CamStop; End;
 If FileDlg(L5('Choisir une cible (image)', 'Select a target (image)',
     'Ziel wählen (Bild)', 'Elegir un objetivo (imagen)',
     'Scegli un bersaglio (immagine)'), False, Path) Then Begin
  RedrawAll;
  If LoadImageFile(Path, Img, Err) Then Begin
   ImgFree(TargetImg);
   ImgFree(TargetThumb);
   TargetImg := Img;
   TargetName := Path;
   TargetOk := True;
   MakeThumb(TargetImg, TargetThumb, 128, 112);
   Info(L5('Cible : ', 'Target: ', 'Ziel: ', 'Destino: ', 'Bersaglio: ') +
        BaseName(Path) + ' (' + IStr(TargetImg.W) + 'x' + IStr(TargetImg.H) +
        ')');
  End
  Else Begin
   RedrawAll;
   ShowError(Err);
  End;
 End;
 RedrawAll;
End;

{ Traite l'image cible a sa taille d'origine ; l'apercu est ajuste a la
  trame }
Function ProcessTarget: Boolean;
Var
 Work, Snap: TImg;
 SrcP: ^TImg;
 Mir, HaveSnap, SnapOk: Boolean;
 I: Integer;
Begin
 ProcessTarget := False;
 HaveSnap := False;
 If TargetOk Then SrcP := @TargetImg
 Else Begin
  { pas d'image cible : on traite une image prise avec la camera choisie }
  Snap.D := Nil; Snap.A := Nil; Snap.W := 0; Snap.H := 0;
  SnapOk := False;
  If ImgNew(Snap, FW, FH, False) Then Begin
   Info(L5('Capture d''une image de la caméra...',
           'Capturing a camera image...', 'Kamerabild wird aufgenommen...',
           'Capturando una imagen de la cámara...',
           'Acquisizione di un''immagine dalla fotocamera...'));
   If CamStart(CurCam) Then Begin
    For I := 1 To 8 Do Begin
     SnapOk := CamGrab(Snap);
     If Not SnapOk Then Delay(60);
    End;
    CamStop;
   End;
  End;
  If Not SnapOk Then Begin
   ImgFree(Snap);
   Info(L5('Choisissez une cible ou une caméra disponible.',
           'Select a target or an available camera.',
           'Ziel oder verfügbare Kamera wählen.',
           'Elija un objetivo o una cámara disponible.',
           'Scegli un bersaglio o una fotocamera disponibile.'));
   Exit;
  End;
  SrcP := @Snap;
  HaveSnap := True;
 End;
 If Not Slots[CurSlot].Ok Then
  Info(L5('Aucun visage source : l''image reste inchangée.',
          'No source face: the image is left unchanged.',
          'Kein Quellgesicht: Bild bleibt unverändert.',
          'Sin rostro de origen: la imagen no cambia.',
          'Nessun volto di origine: immagine invariata.'));
 If Not ImgNew(Work, SrcP^.W, SrcP^.H, False) Then Begin
  If HaveSnap Then ImgFree(Snap);
  Info('Memoire / Memory');
  Exit;
 End;
 ImgCopy(SrcP^, Work);
 If HaveSnap Then ImgFree(Snap);
 TrackReset;
 SkinReset;
 Mir := OptMirror;
 If Not HaveSnap Then OptMirror := False;
 ProcessFrame(Work);
 OptMirror := Mir;
 If FaceCount = 0 Then
  Info(L5('Aucun visage détecté dans la cible (peau : menu Caméra).',
          'No face detected in the target (adjust skin: Camera menu).',
          'Kein Gesicht im Ziel erkannt (Haut: Menü Kamera).',
          'Ningún rostro en el objetivo (piel: menú Cámara).',
          'Nessun volto nel bersaglio (pelle: menu Fotocamera).'))
 Else Info(IStr(FaceCount) + ' ' + L5('visage(s) traité(s).',
          'face(s) processed.', 'Gesicht(er) verarbeitet.',
          'rostro(s) procesado(s).', 'volto/i elaborato/i.'));
 ImgFree(TargetRes);
 TargetRes := Work;
 FitToFrame(TargetRes, Res);
 PreviewHasImage := True;
 ProcessTarget := True;
End;

Procedure CmdPreview;
Begin
 If Live Then Begin Live := False; CamStop; End;
 If ProcessTarget Then Begin
  RedrawAll;
 End
 Else RefreshUi;
End;

Procedure CmdSave;
Var
 Path: String;
 Im: ^TImg;
Begin
 If Res.D = Nil Then Exit;
 Path := 'tmf_result.bmp';
 If (Not Live) And (TargetRes.D <> Nil) Then Im := @TargetRes Else Im := @Res;
 If FileDlg(L5('Enregistrer le résultat (BMP)', 'Save the result (BMP)',
     'Ergebnis speichern (BMP)', 'Guardar el resultado (BMP)',
     'Salva il risultato (BMP)'), True, Path) Then Begin
  RedrawAll;
  If SaveBMP(Path, Im^) Then
   Info(L5('Enregistré : ', 'Saved: ', 'Gespeichert: ', 'Guardado: ',
           'Salvato: ') + Path)
  Else ShowError(L5('Écriture impossible : ', 'Cannot write: ',
                    'Schreiben nicht möglich: ', 'No se puede escribir: ',
                    'Impossibile scrivere: ') + Path);
 End;
 RedrawAll;
End;

Procedure CmdStart;
Var
 Path: String;
Begin
 If Live Then Begin Live := False; CamStop; End;
 If Not ProcessTarget Then Begin RefreshUi; Exit; End;
 RedrawAll;
 Path := 'tmf_result.bmp';
 If FileDlg(L5('Enregistrer le résultat (BMP)', 'Save the result (BMP)',
     'Ergebnis speichern (BMP)', 'Guardar el resultado (BMP)',
     'Salva il risultato (BMP)'), True, Path) Then Begin
  RedrawAll;
  If SaveBMP(Path, TargetRes) Then
   Info(L5('Enregistré : ', 'Saved: ', 'Gespeichert: ', 'Guardado: ',
           'Salvato: ') + Path)
  Else ShowError(L5('Écriture impossible : ', 'Cannot write: ',
                    'Schreiben nicht möglich: ', 'No se puede escribir: ',
                    'Impossibile scrivere: ') + Path);
 End;
 RedrawAll;
End;

Procedure CmdCapture;
Var
 Name_: String;
 Im: ^TImg;
Begin
 If Res.D = Nil Then Exit;
 Repeat
  Inc(CapCount);
  Name_ := 'TMF' + PadN(CapCount, 5) + '.BMP';
 Until (Not FileExists_(Name_)) Or (CapCount > 99999);
 If (Not Live) And (TargetRes.D <> Nil) Then Im := @TargetRes Else Im := @Res;
 If SaveBMP(Name_, Im^) Then
  Info(L5('Image enregistrée : ', 'Frame saved: ', 'Bild gespeichert: ',
          'Fotograma guardado: ', 'Fotogramma salvato: ') + Name_)
 Else Info(L5('Écriture impossible : ', 'Cannot write: ',
              'Schreiben nicht möglich: ', 'No se puede escribir: ',
              'Impossibile scrivere: ') + Name_);
 RefreshUi;
End;

Procedure SaveSeqFrame;
Var
 Name_: String;
Begin
 If Not FramesDirOk Then Begin
  {$I-}
  MkDir('TMF_FRAMES');
  {$I+}
  If IOResult = 0 Then ;
  FramesDirOk := True;
 End;
 Name_ := 'TMF_FRAMES' + PathSep + 'FR' + PadN(SavedFrames, 6) + '.BMP';
 If SaveBMP(Name_, Res) Then Inc(SavedFrames);
End;

Procedure StopLive;
Begin
 If Live Then Begin
  Live := False;
  CamStop;
  Info(L5('Direct arrêté.', 'Live stopped.', 'Live beendet.',
          'En vivo detenido.', 'Diretta fermata.'));
 End;
End;

Procedure CmdLive;
Begin
 If Live Then Begin
  StopLive;
  RefreshUi;
  Exit;
 End;
 If Not CamStart(CurCam) Then Begin
  ShowError(L5('Impossible d''ouvrir la caméra : ',
               'Cannot open the camera: ', 'Kamera nicht zu öffnen: ',
               'No se puede abrir la cámara: ',
               'Impossibile aprire la fotocamera: ') + Cams[CurCam].Name);
  Exit;
 End;
 Live := True;
 LiveFails := 0;
 FrameNo := 0;
 Fps := 0;
 TrackReset;
 PreviewHasImage := True;
 Info(L5('Direct : ', 'Live: ', 'Live: ', 'En vivo: ', 'Diretta: ') +
      Trunc_(Cams[CurCam].Name, 50));
 If Not Slots[CurSlot].Ok Then
  Info(L5('Aucun visage source : choisissez un visage (Ctrl+F).',
          'No source face: select a face (Ctrl+F).',
          'Kein Quellgesicht: Gesicht wählen (Strg+F).',
          'Sin rostro de origen: elija un rostro (Ctrl+F).',
          'Nessun volto di origine: scegli un volto (Ctrl+F).'));
 RefreshUi;
End;

Procedure LiveStep;
Var
 T0, Dt: LongInt;
 Cur_: Real;
Begin
 T0 := NowMs;
 If CamGrab(Cur) Then Begin
  LiveFails := 0;
  ImgCopy(Cur, Res);
  ProcessFrame(Res);
  ShowFrame(Res);
  Inc(FrameNo);
  If OptKeepFrames Then SaveSeqFrame;
  If OptKeepFps Then Begin
   Dt := ElapsedMs(T0);
   If Dt < 33 Then Delay(33 - Dt);
  End;
  Dt := ElapsedMs(T0);
  If Dt < 1 Then Dt := 1;
  Cur_ := 1000.0 / Dt;
  If Fps < 0.1 Then Fps := Cur_ Else Fps := Fps * 0.85 + Cur_ * 0.15;
  If (FrameNo Mod 6) = 0 Then Begin
   HideMouse;
   DrawInfo;
   ShowMouse;
  End;
 End
 Else Begin
  Inc(LiveFails);
  Delay(10);
  If LiveFails > 40 Then Begin
   StopLive;
   ShowError(L5('La caméra ne répond plus.', 'The camera stopped responding.',
                'Die Kamera antwortet nicht mehr.',
                'La cámara no responde.', 'La fotocamera non risponde.'));
  End;
 End;
End;

Procedure CmdCamSel;
Var
 Sel: Integer;
 Was: Boolean;
Begin
 Sel := CurCam;
 Was := Live;
 If CamDlg(Sel) Then Begin
  If Sel <> CurCam Then Begin
   If Was Then StopLive;
   CurCam := Sel;
   Info(L5('Caméra : ', 'Camera: ', 'Kamera: ', 'Cámara: ',
           'Fotocamera: ') + Cams[CurCam].Name);
   RedrawAll;
   If Was Then CmdLive;
   Exit;
  End;
 End;
 RedrawAll;
End;

Procedure CmdAdjust;
Var
 F: TFace;
Begin
 If Not Slots[CurSlot].Ok Then Exit;
 F := Slots[CurSlot].Face;
 If LandmarkDlg(Slots[CurSlot].Photo, F) Then Begin
  Slots[CurSlot].Face := F;
  If BuildTemplate(Slots[CurSlot]) Then
   Info(L5('Repères mis à jour.', 'Landmarks updated.',
           'Punkte aktualisiert.', 'Puntos actualizados.',
           'Punti aggiornati.'))
  Else Slots[CurSlot].Ok := False;
 End;
 RedrawAll;
End;

Procedure CmdAutoDet;
Var
 L: TFaceList;
 N: Integer;
 S0: Array[0..3] Of LongInt;
Begin
 If Not Slots[CurSlot].Ok Then Exit;
 S0[0] := SkinCb; S0[1] := SkinCr; S0[2] := SkinDCb; S0[3] := SkinDCr;
 SkinReset;
 N := DetectFaces(Slots[CurSlot].Photo, L, 1);
 SkinCb := S0[0]; SkinCr := S0[1]; SkinDCb := S0[2]; SkinDCr := S0[3];
 If N > 0 Then Begin
  Slots[CurSlot].Face := L[0];
  If BuildTemplate(Slots[CurSlot]) Then
   Info(L5('Repères détectés automatiquement.',
           'Landmarks detected automatically.',
           'Punkte automatisch erkannt.', 'Puntos detectados automáticamente.',
           'Punti rilevati automaticamente.'));
 End
 Else Info(L5('Aucun visage détecté : utilisez Ajuster les repères.',
              'No face detected: use Adjust landmarks.',
              'Kein Gesicht erkannt: Punkte anpassen verwenden.',
              'Ningún rostro: use Ajustar puntos.',
              'Nessun volto: usa Regola i punti.'));
 RefreshUi;
End;

Procedure CmdSwapST;
Var
 T: TImg;
 N, OldT: String;
 Photo: TImg;
Begin
 If (Not Slots[CurSlot].Ok) Or (Not TargetOk) Then Exit;
 OldT := TargetName;
 If Live Then StopLive;
 { la cible devient la source, l'ancienne source devient la cible }
 T := Slots[CurSlot].Photo;
 Photo := TargetImg;
 N := Slots[CurSlot].Name;
 Slots[CurSlot].Photo.D := Nil;
 Slots[CurSlot].Photo.A := Nil;
 TargetImg.D := Nil;
 TargetImg.A := Nil;
 ImgFree(Slots[CurSlot].Tpl);
 ImgFree(Slots[CurSlot].Tpl2);
 ImgFree(Slots[CurSlot].Thumb);
 ImgFree(TargetThumb);
 ImgFree(TargetRes);
 Slots[CurSlot].Ok := False;
 TargetImg := T;
 TargetName := N;
 MakeThumb(TargetImg, TargetThumb, 128, 112);
 RedrawAll;
 InstallSource(Photo, BaseName(OldT));
 PreviewHasImage := False;
 RedrawAll;
End;

Procedure CmdClearFace;
Begin
 ImgFree(Slots[CurSlot].Photo);
 ImgFree(Slots[CurSlot].Tpl);
 ImgFree(Slots[CurSlot].Tpl2);
 ImgFree(Slots[CurSlot].Thumb);
 Slots[CurSlot].Ok := False;
 Slots[CurSlot].Name := '';
 RedrawAll;
End;

Procedure ShowHelp;
Var
 Ct: String;
Begin
 Ct := L5('Ctrl+', 'Ctrl+', 'Strg+', 'Ctrl+', 'Ctrl+');
 MsgClear;
 MsgAdd(Ct + L5('F : choisir le visage source (photo)',
   'F: select the source face (photo)', 'F: Quellgesicht wählen (Foto)',
   'F: elegir el rostro de origen (foto)',
   'F: scegli il volto di origine (foto)'));
 MsgAdd(Ct + L5('T : choisir une cible (image)',
   'T: select a target (image)', 'T: Ziel wählen (Bild)',
   'T: elegir un objetivo (imagen)', 'T: scegli un bersaglio (immagine)'));
 MsgAdd(Ct + L5('A : ajuster les repères du visage source',
   'A: adjust the source face landmarks',
   'A: Punkte des Quellgesichts anpassen',
   'A: ajustar los puntos del rostro de origen',
   'A: regola i punti del volto di origine'));
 MsgAdd(Ct + L5('W : inverser source et cible', 'W: swap source and target',
   'W: Quelle und Ziel tauschen', 'W: intercambiar origen y destino',
   'W: scambia origine e bersaglio'));
 MsgAdd(L5('F5 : démarrer (traiter la cible et l''enregistrer)',
   'F5: start (process the target and save it)',
   'F5: Start (Ziel verarbeiten und speichern)',
   'F5: iniciar (procesar el objetivo y guardarlo)',
   'F5: avvia (elabora il bersaglio e salvalo)'));
 MsgAdd(L5('F6 : aperçu de la cible', 'F6: preview the target',
   'F6: Vorschau des Ziels', 'F6: vista previa del objetivo',
   'F6: anteprima del bersaglio'));
 MsgAdd(L5('F7 : direct avec la caméra', 'F7: live with the camera',
   'F7: Live mit der Kamera', 'F7: en vivo con la cámara',
   'F7: diretta con la fotocamera'));
 MsgAdd(L5('F8 ou Échap : arrêter le direct', 'F8 or Esc: stop live',
   'F8 oder Esc: Live beenden', 'F8 o Esc: detener', 'F8 o Esc: ferma'));
 MsgAdd(L5('F9 : capturer une image', 'F9: capture a frame',
   'F9: Bild aufnehmen', 'F9: capturar un fotograma',
   'F9: cattura un fotogramma'));
 MsgAdd(Ct + L5('S : enregistrer le résultat', 'S: save the result',
   'S: Ergebnis speichern', 'S: guardar el resultado',
   'S: salva il risultato'));
 MsgAdd(L5('F10 : menus     Alt+X : quitter', 'F10: menus     Alt+X: exit',
   'F10: Menüs     Alt+X: Beenden', 'F10: menús     Alt+X: salir',
   'F10: menu     Alt+X: esci'));
 MsgAdd(L5('Clic dans l''aperçu (direct) : calibrer la peau',
   'Click in the preview (live): calibrate skin',
   'Klick in die Vorschau (Live): Haut kalibrieren',
   'Clic en la vista previa (vivo): calibrar la piel',
   'Clic nell''anteprima (diretta): calibra la pelle'));
 MsgBoxL(L5('Raccourcis clavier', 'Keyboard shortcuts', 'Tastenkürzel',
            'Atajos de teclado', 'Scorciatoie da tastiera'), False);
 RedrawAll;
End;

Procedure ShowAbout;
Begin
 MsgClear;
 MsgAdd('Time Motion Transfer ' + VERSION_STR);
 MsgAdd('');
 MsgAdd(L5('Clone en Pascal de Deep-Live-Cam : remplacement de visage',
   'Pascal clone of Deep-Live-Cam: live face replacement from',
   'Pascal-Klon von Deep-Live-Cam: Gesichtsersatz live aus',
   'Clon en Pascal de Deep-Live-Cam: sustitución de rostro en',
   'Clone in Pascal di Deep-Live-Cam: sostituzione del volto'));
 MsgAdd(L5('en direct à partir d''une photographie et d''une webcam.',
   'a photograph and a webcam.',
   'einem Foto und einer Webcam.',
   'vivo a partir de una foto y una webcam.',
   'dal vivo da una foto e una webcam.'));
 MsgAdd(L5('Méthode classique : peau YCbCr, repères, alignement, fusion.',
   'Classic method: YCbCr skin, landmarks, alignment, blending.',
   'Klassisch: YCbCr-Haut, Punkte, Ausrichtung, Überblendung.',
   'Método clásico: piel YCbCr, puntos, alineación, mezcla.',
   'Metodo classico: pelle YCbCr, punti, allineamento, fusione.'));
 MsgAdd('');
 MsgAdd('Sylvain Maltais - support@gladir.com');
 MsgAdd('https://www.gladir.com/office-0');
 MsgBoxL(L5('À propos', 'About', 'Info', 'Acerca de', 'Informazioni'),
         False);
 RedrawAll;
End;

Procedure ShowEthics;
Begin
 MsgClear;
 MsgAdd(L5('N''utilisez que des visages dont vous avez l''autorisation.',
   'Only use faces you have permission to use.',
   'Nur Gesichter verwenden, für die eine Erlaubnis vorliegt.',
   'Use solo rostros para los que tenga permiso.',
   'Usa solo volti per i quali hai il permesso.'));
 MsgAdd(L5('Indiquez clairement qu''un contenu est synthétique.',
   'Clearly label content as synthetic.',
   'Inhalte klar als synthetisch kennzeichnen.',
   'Indique claramente que el contenido es sintético.',
   'Indica chiaramente che il contenuto è sintetico.'));
 MsgAdd(L5('Ne l''utilisez pas pour tromper, harceler ou usurper.',
   'Do not use it to deceive, harass or impersonate anyone.',
   'Nicht zum Täuschen, Belästigen oder Nachahmen verwenden.',
   'No lo use para engañar, acosar o suplantar identidades.',
   'Non usarlo per ingannare, molestare o impersonare.'));
 MsgBoxL(L5('Avertissement', 'Notice', 'Hinweis', 'Aviso', 'Avviso'), False);
 RedrawAll;
End;

Procedure ExecCmd(Cmd: Integer);
Begin
 If Not CmdEnabled(Cmd) Then Exit;
 Case Cmd Of
  CM_SELFACE: CmdSelFace;
  CM_SELTARGET: CmdSelTarget;
  CM_SAVE: CmdSave;
  CM_CAPTURE: CmdCapture;
  CM_QUIT: Quit_ := True;
  CM_DESTROY: Begin
   If MsgBox('TMF', L5('Quitter Time Motion Transfer ?',
        'Exit Time Motion Transfer?', 'Time Motion Transfer beenden?',
        '¿Salir de Time Motion Transfer?', 'Uscire da Time Motion Transfer?'),
        True) Then Quit_ := True
   Else RedrawAll;
  End;
  CM_ADJUST: CmdAdjust;
  CM_AUTODET: CmdAutoDet;
  CM_SWAPST: CmdSwapST;
  CM_CLEARFACE: CmdClearFace;
  CM_SLOT1..CM_SLOT1 + N_SLOTS - 1: Begin
   CurSlot := Cmd - CM_SLOT1 + 1;
   RefreshUi;
  End;
  CM_START: CmdStart;
  CM_PREVIEW: CmdPreview;
  CM_LIVE: CmdLive;
  CM_STOP: Begin StopLive; RefreshUi; End;
  CM_MOUTH: Begin OptMouth := Not OptMouth; RefreshUi; End;
  CM_KEEPFPS: Begin OptKeepFps := Not OptKeepFps; RefreshUi; End;
  CM_KEEPFR: Begin
   OptKeepFrames := Not OptKeepFrames;
   If OptKeepFrames Then
    Info(L5('Les images traitées seront enregistrées dans TMF_FRAMES.',
            'Processed frames will be saved in TMF_FRAMES.',
            'Verarbeitete Bilder werden in TMF_FRAMES gespeichert.',
            'Los fotogramas procesados se guardarán en TMF_FRAMES.',
            'I fotogrammi elaborati saranno salvati in TMF_FRAMES.'));
   RefreshUi;
  End;
  CM_ENHANCE: Begin OptEnhance := Not OptEnhance; RefreshUi; End;
  CM_MAPF: Begin OptMap := Not OptMap; RefreshUi; End;
  CM_MANY: Begin OptMany := Not OptMany; RefreshUi; End;
  CM_CAMSEL: CmdCamSel;
  CM_MIRROR: Begin OptMirror := Not OptMirror; RefreshUi; End;
  CM_SKIN: Begin
   SkinReset;
   TrackReset;
   Info(L5('Cliquez sur la peau du visage dans l''aperçu pour calibrer.',
           'Click on the face skin in the preview to calibrate.',
           'Klicken Sie in der Vorschau auf die Gesichtshaut.',
           'Pulse en la piel del rostro en la vista previa.',
           'Clicca sulla pelle del volto nell''anteprima.'));
   RefreshUi;
  End;
  CM_MARKS: Begin OptMarks := Not OptMarks; RefreshUi; End;
  CM_SHOWFPS: Begin OptShowFps := Not OptShowFps; RefreshUi; End;
  CM_FAST: Begin
   OptFast := Not OptFast;
   ShadowOk := False;
   RefreshUi;
  End;
  CM_HELP: ShowHelp;
  CM_ABOUT: ShowAbout;
  CM_ETHICS: ShowEthics;
 End;
End;

Procedure MenuRun(M, Item: Integer);
Var
 Cmd: Integer;
Begin
 Cmd := Menus[M].Items[Item].Cmd;
 CloseMenu;
 ExecCmd(Cmd);
End;

{ Navigation clavier dans les menus }
Procedure MenuKey(K: Integer);
Var
 N, I: Integer;
Begin
 Case K Of
  K_ESC: CloseMenu;
  K_LEFT: OpenMenu((ActiveMenu + MN_COUNT - 1) Mod MN_COUNT);
  K_RIGHT: OpenMenu((ActiveMenu + 1) Mod MN_COUNT);
  K_UP, K_DOWN: Begin
   N := Menus[ActiveMenu].ItemCount;
   I := ActiveItem;
   Repeat
    If K = K_DOWN Then I := (I + 1 + N) Mod N Else I := (I - 1 + N) Mod N;
    If I < 0 Then I := N - 1;
   Until Not Menus[ActiveMenu].Items[I].Separator;
   ActiveItem := I;
   HideMouse;
   DrawDropdown(ActiveMenu);
   ShowMouse;
  End;
  K_ENTER: If ActiveItem >= 0 Then MenuRun(ActiveMenu, ActiveItem);
 End;
End;

Procedure HandleKey(K: Integer);
Begin
 If K < 0 Then Exit;
 If MenuActive Then Begin
  MenuKey(K);
  Exit;
 End;
 Case K Of
  6: ExecCmd(CM_SELFACE);
  20: ExecCmd(CM_SELTARGET);
  19: ExecCmd(CM_SAVE);
  17, K_ALTX: ExecCmd(CM_QUIT);
  1: ExecCmd(CM_ADJUST);
  23: ExecCmd(CM_SWAPST);
  K_F1: ExecCmd(CM_HELP);
  K_F5: ExecCmd(CM_START);
  K_F6: ExecCmd(CM_PREVIEW);
  K_F7: ExecCmd(CM_LIVE);
  K_F8: ExecCmd(CM_STOP);
  { Echap : arrete le direct ; hors direct, quitte le programme }
  K_ESC: If Live Then ExecCmd(CM_STOP) Else ExecCmd(CM_QUIT);
  K_F9: ExecCmd(CM_CAPTURE);
  K_F10: OpenMenu(0);
 End;
End;

Procedure PreviewClick;
Var
 FX, FY, Z: LongInt;
 Ok: Boolean;
Begin
 If Not Live Then Exit;
 Z := PREV_W Div FW;
 FX := (MX_ - PREV_X) Div Z;
 FY := (MY_ - PREV_Y) Div Z;
 { la detection travaille sur l'image retournee }
 If OptMirror Then FX := FW - 1 - FX;
 Ok := SkinSeed(Cur, FX, FY);
 If Ok Then Begin
  TrackReset;
  Info(L5('Peau calibrée : Cb/Cr = ', 'Skin calibrated: Cb/Cr = ',
          'Haut kalibriert: Cb/Cr = ', 'Piel calibrada: Cb/Cr = ',
          'Pelle calibrata: Cb/Cr = ') + IStr(SkinCb) + '/' + IStr(SkinCr));
 End
 Else Info(L5('Cette zone ne ressemble pas à de la peau : clic ignoré.',
              'This area does not look like skin: click ignored.',
              'Dieser Bereich sieht nicht nach Haut aus: Klick ignoriert.',
              'Esta zona no parece piel: clic ignorado.',
              'Questa zona non sembra pelle: clic ignorato.'));
 RefreshUi;
End;

Procedure HandleMouse;
Var
 Down: Boolean;
 Bar_, Item, Cmd: Integer;
Begin
 PollMouse;
 Down := MouseClicked;
 If MenuActive Then Begin
  If (MX_ <> OMX) Or (MY_ <> OMY) Then Begin
   Bar_ := MenuBarHit(MX_, MY_);
   If (Bar_ >= 0) And (Bar_ <> ActiveMenu) Then OpenMenu(Bar_)
   Else Begin
    Item := MenuItemHit(MX_, MY_, ActiveMenu);
    If Item <> ActiveItem Then Begin
     ActiveItem := Item;
     HideMouse;
     DrawDropdown(ActiveMenu);
     ShowMouse;
    End;
   End;
  End;
  If Down Then Begin
   Bar_ := MenuBarHit(MX_, MY_);
   If Bar_ = ActiveMenu Then CloseMenu
   Else If Bar_ >= 0 Then OpenMenu(Bar_)
   Else Begin
    Item := MenuItemHit(MX_, MY_, ActiveMenu);
    If Item >= 0 Then MenuRun(ActiveMenu, Item) Else CloseMenu;
   End;
  End;
  Exit;
 End;
 If Not Down Then Exit;
 If MY_ < MENU_H Then Begin
  Bar_ := MenuBarHit(MX_, MY_);
  If Bar_ >= 0 Then OpenMenu(Bar_);
  Exit;
 End;
 If (MX_ >= PREV_X) And (MX_ < PREV_X + PREV_W) And (MY_ >= PREV_Y) And
    (MY_ < PREV_Y + PREV_H) Then Begin
  PreviewClick;
  Exit;
 End;
 Cmd := WidHit(MX_, MY_);
 If Cmd <> CM_NONE Then ExecCmd(Cmd);
End;

Procedure MainLoop;
Begin
 RedrawAll;
 Repeat
  HandleMouse;
  HandleKey(GetKeyEx);
  If Quit_ Then Break;
  If Live And (Not MenuActive) Then LiveStep Else Delay(15);
 Until Quit_;
End;

{ ---------------------------------------------------------------------- }
{ Programme principal                                                      }
{ ---------------------------------------------------------------------- }

Procedure InitVars;
Var
 I: Integer;
Begin
 FillChar(Slots, SizeOf(Slots), 0);
 FillChar(TargetImg, SizeOf(TargetImg), 0);
 FillChar(TargetRes, SizeOf(TargetRes), 0);
 FillChar(TargetThumb, SizeOf(TargetThumb), 0);
 FillChar(Cur, SizeOf(Cur), 0);
 FillChar(Res, SizeOf(Res), 0);
 CurSlot := 1;
 For I := 0 To LOG_N - 1 Do LogTxt[I] := '';
 OptMouth := False;
 OptKeepFps := True;
 OptKeepFrames := False;
 OptEnhance := False;
 OptMap := False;
 OptMany := False;
 OptMirror := False;
 OptMarks := False;
 OptShowFps := True;
 OptFast := False;
 MenuActive := False;
 UnderValid := False;
 Live := False;
 Quit_ := False;
 TargetOk := False;
 PreviewHasImage := False;
 ShadowOk := False;
 FaceCount := 0;
 Fps := 0;
 SavedFrames := 0;
 CapCount := 0;
 FramesDirOk := False;
 LastDir := '';
 StatusMsg := '';
 LiveFails := 0;
 SkinTick := 0;
 Seed := 12345;
 SynT := 0;
 CamOpened := False;
 MX_ := 0; MY_ := 0; MB_ := 0; OMX := 0; OMY := 0; OMB := 0;
 {$IFDEF LINUX}
 VFd := -1;
 VCount := 0;
 {$ENDIF}
 {$IFDEF WINDOWS}
 CapWnd := 0;
 CamRaw := Nil;
 {$ENDIF}
End;

Procedure ShowHelpLine;
Begin
 WriteLn('TMF (Time Motion Transfer) ', VERSION_STR);
 WriteLn(L5(
  'Syntaxe : TMF [-maxcolors] [-maxscreen] [-nogpu] [/? | -h | --help]',
  'Syntax: TMF [-maxcolors] [-maxscreen] [-nogpu] [/? | -h | --help]',
  'Syntax: TMF [-maxcolors] [-maxscreen] [-nogpu] [/? | -h | --help]',
  'Sintaxis: TMF [-maxcolors] [-maxscreen] [-nogpu] [/? | -h | --help]',
  'Sintassi: TMF [-maxcolors] [-maxscreen] [-nogpu] [/? | -h | --help]'));
 WriteLn;
 WriteLn(L5('  Sans option  Affichage 640x480 en 16 couleurs (tramage).',
            '  No option    640x480 display in 16 colors (dithered).',
            '  Ohne Option  Anzeige 640x480 mit 16 Farben (Raster).',
            '  Sin opcion   Pantalla 640x480 de 16 colores (tramado).',
            '  Senza opz.   Schermo 640x480 a 16 colori (retino).'));
 WriteLn(L5('  -maxcolors   Utilise le maximum de couleurs (24 bits) ; si',
            '  -maxcolors   Uses the maximum number of colors (24-bit); if',
            '  -maxcolors   Maximale Farbtiefe (24 Bit); falls unmoeglich:',
            '  -maxcolors   Usa el maximo de colores (24 bits); si no es',
            '  -maxcolors   Usa il massimo dei colori (24 bit); se non e'));
 WriteLn(L5('               impossible, revient au 640x480x16.',
            '               not possible, falls back to 640x480x16.',
            '               zurueck zu 640x480x16.',
            '               posible, vuelve a 640x480x16.',
            '               possibile, torna a 640x480x16.'));
 WriteLn(L5('  -maxscreen   Utilise la definition maximale de l''ecran',
            '  -maxscreen   Uses the maximum screen resolution (256 colors,',
            '  -maxscreen   Maximale Aufloesung (256 Farben, oder mit',
            '  -maxscreen   Usa la resolucion maxima (256 colores, o con',
            '  -maxscreen   Usa la massima risoluzione (256 colori, o con'));
 WriteLn(L5('               (256 couleurs, ou 24 bits avec -maxcolors).',
            '               or 24-bit with -maxcolors).',
            '               -maxcolors 24 Bit).',
            '               -maxcolors 24 bits).',
            '               -maxcolors 24 bit).'));
 WriteLn(L5('  -nogpu       Windows : sans acceleration Direct3D (GPU).',
            '  -nogpu       Windows: no Direct3D (GPU) acceleration.',
            '  -nogpu       Windows: ohne Direct3D-(GPU-)Beschleunigung.',
            '  -nogpu       Windows: sin aceleracion Direct3D (GPU).',
            '  -nogpu       Windows: senza accelerazione Direct3D (GPU).'));
 WriteLn(L5('  /?           Affiche cette aide.',
            '  /?           Shows this help.',
            '  /?           Zeigt diese Hilfe.',
            '  /?           Muestra esta ayuda.',
            '  /?           Mostra questo aiuto.'));
 WriteLn;
 WriteLn(L5(
  'Langue : variable LANGUAGE (EN, GR, SP, IT ; francais par defaut).',
  'Language: LANGUAGE variable (EN, GR, SP, IT; French by default).',
  'Sprache: Variable LANGUAGE (EN, GR, SP, IT; Standard Franzoesisch).',
  'Idioma: variable LANGUAGE (EN, GR, SP, IT; frances por defecto).',
  'Lingua: variabile LANGUAGE (EN, GR, SP, IT; francese di default).'));
 WriteLn(L5(
  'Windows : Direct3D est utilise seul avec une vraie carte graphique.',
  'Windows: Direct3D is used by itself with a real graphics card.',
  'Windows: Direct3D wird mit einer echten Grafikkarte automatisch genutzt.',
  'Windows: Direct3D se usa solo con una tarjeta grafica real.',
  'Windows: Direct3D e usato da solo con una vera scheda grafica.'));
 WriteLn(L5('Les options d''affichage sont ignorees sous Turbo Pascal.',
            'Display options are ignored under Turbo Pascal.',
            'Anzeigeoptionen werden unter Turbo Pascal ignoriert.',
            'Las opciones de pantalla se ignoran en Turbo Pascal.',
            'Le opzioni dello schermo sono ignorate in Turbo Pascal.'));
End;

Var
 I: Integer;
 Arg: String;
 Dummy: Boolean;

BEGIN
 DetectLanguage;
 For I := 1 To ParamCount Do Begin
  Arg := UpStr(ParamStr(I));
  If (Arg = '/?') Or (Arg = '-H') Or (Arg = '--HELP') Then Begin
   ShowHelpLine;
   Halt;
  End
  Else If Arg = '-MAXCOLORS' Then OptMaxColors := True
  Else If Arg = '-MAXSCREEN' Then OptMaxScreen := True
  Else If Arg = '-NOGPU' Then OptNoGpu := True;
 End;
 {$IFDEF FPC}
 ReturnNilIfGrowHeapFails := True;
 {$ENDIF}
 InitVars;
 InitializeGraphics;
 SetFrameSize;
 InitializeScreenPalette;
 ApplyUiPalette;
 {$IFDEF FPC}
 Dummy := PtcMouse.InitMouse;
 PtcMouse.ShowMouse;
 {$ELSE}
 If MouseDriverFound Then ShowMouse;
 {$ENDIF}
 SetTextStyle(DefaultFont, HorizDir, 1);
 If Not (ImgNew(Cur, FW, FH, False) And ImgNew(Res, FW, FH, False) And
         DetectAlloc And SwapAlloc) Then Begin
  CloseGraph;
  WriteLn('Memoire insuffisante / Not enough memory');
  Halt;
 End;
 Shadow := PShadowArr(MemAlloc(FW * FH * SizeOf(TShadowEl)));
 If Shadow = Nil Then Begin
  CloseGraph;
  WriteLn('Memoire insuffisante / Not enough memory');
  Halt;
 End;
 BuildQ16;
 SkinReset;
 TrackReset;
 CamListBuild;
 InitMenus;
 {$IFDEF WINDOWS}
 If Not OptNoGpu Then Begin
  If GpuInit Then LogAdd('Direct3D : ' + GpuName)
  Else LogAdd(L5('Direct3D non utilisé (pas de carte significative) :'+
                 ' affichage logiciel.',
                 'Direct3D not used (no significant graphics card): '+
                 'software display.',
                 'Direct3D nicht genutzt (keine geeignete Karte): '+
                 'Softwareanzeige.',
                 'Direct3D no usado (sin tarjeta adecuada): '+
                 'pantalla por software.',
                 'Direct3D non usato (nessuna scheda adatta): '+
                 'schermo software.'));
 End;
 {$ENDIF}
 Info(L5(
  'Bienvenue. Choisissez un visage source (Ctrl+F) puis lancez le direct (F7).',
  'Welcome. Select a source face (Ctrl+F), then start live (F7).',
  'Willkommen. Quellgesicht wählen (Strg+F), dann Live starten (F7).',
  'Bienvenido. Elija un rostro de origen (Ctrl+F) y pulse F7.',
  'Benvenuto. Scegli un volto di origine (Ctrl+F), poi F7.'));
 LogAdd(L5('Caméras détectées : ', 'Cameras found: ', 'Kameras gefunden: ',
           'Cámaras encontradas: ', 'Fotocamere trovate: ') +
        IStr(NCams - 1) + ' (+ ' + L5('mire de test', 'test pattern',
        'Testbild', 'imagen de prueba', 'immagine di prova') + ')');
 MainLoop;
 StopLive;
 CamStop;
 {$IFDEF WINDOWS}
 If GpuOn Then GpuShutdown;
 {$ENDIF}
 HideMouse;
 CloseGraph;
END.
