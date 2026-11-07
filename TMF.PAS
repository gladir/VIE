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
   - Camera : API Video for Windows (Windows) ou Video4Linux2 (Linux),
     directement, sans unite ni bibliotheque externe ; sous DOS une mire
     de test animee remplace la camera
   - Menus deroulants, boutons, interrupteurs, fenetres de dialogue
   - Langue : francais par defaut, LANGUAGE=EN (anglais), LANGUAGE=GR
     (allemand), LANGUAGE=SP (espagnol) ou LANGUAGE=IT (italien)

  Important : Deep-Live-Cam repose sur des reseaux de neurones (InsightFace,
  GFPGAN) qui ne peuvent pas etre integres dans un seul fichier Pascal. TMF
  utilise donc des techniques classiques : detection de la peau (YCbCr),
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
{ Decodeur JPEG integre (sequentiel 8 bits, Huffman, ITU-T T.81)           }
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

Procedure JRestart;
Var
 I: Integer;
Begin
 JCnt := 0;
 While (JPos < JSize - 1) And Not ((JD^[JPos] = $FF) And
       (JD^[JPos + 1] >= $D0) And (JD^[JPos + 1] <= $D7)) Do Inc(JPos);
 If JPos < JSize - 1 Then Inc(JPos, 2) Else JErr := True;
 For I := 0 To 3 Do JC[I].Pred := 0;
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
 Inc(JPos, Len);
 JCnt := 0;
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
   JBlock(Ci, N Mod BX_, N Div BX_);
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
      If Not JErr Then JBlock(Ci, Mx_ * JC[Ci].H + H, My_ * JC[Ci].V + V);
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
 For I := 0 To 3 Do JC[I].Plane := Nil;
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
   $C2: Begin
    Err := L5('JPEG progressif non pris en charge (convertir en JPEG '+
              'de base ou BMP)',
              'Progressive JPEG not supported (convert to baseline '+
              'JPEG or BMP)',
              'Progressives JPEG nicht unterstuetzt',
              'JPEG progresivo no admitido', 'JPEG progressivo non '+
              'supportato');
    JErr := True;
   End;
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
 Stride: LongInt;
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
 KX := IMax(1, IMin(3, SW Div FW));
 KY := IMax(1, IMin(3, SH Div FH));
 For Y := 0 To FH - 1 Do
  For X := 0 To FW - 1 Do Begin
   SR := 0; SG := 0; SB := 0; N := 0;
   For IY := 0 To KY - 1 Do
    For IX := 0 To KX - 1 Do Begin
     SX := (X * SW + ((2 * IX + 1) * SW) Div (2 * KX)) Div FW;
     SY := (Y * SH + ((2 * IY + 1) * SH) Div (2 * KY)) Div FH;
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
{ ---- Windows : Video for Windows (avicap32.dll) ---- }
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

Procedure CamEnumerate;
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

Function CamOpen(Idx: Integer): Boolean;
Var
 Bih: TBmpInfoHdr;
 R: PtrInt;
Begin
 CamOpen := False;
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
 CamOpen := True;
End;

Procedure CamClose;
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

Function CamGrabReal(Var Fr: TImg): Boolean;
Begin
 CamGrabReal := False;
 If CapWnd = 0 Then Exit;
 CamCBOk := False;
 SendMessageA(CapWnd, WM_CAP_GRAB_FRAME_NOSTOP, 0, 0);
 If CamCBOk Then
  CamGrabReal := RawToFrame(CamRaw, CamRawLen, CamW, CamH, CamFmt,
                            CamBottomUp, Fr);
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
 PrevCx, PrevCy: Real;
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
Function DetectFaces(Var Fr: TImg; Var L: TFaceList; MaxN: Integer): Integer;
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
 DetectFaces := 0;
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
 DetectFaces := K;
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
 Age: Array[0..MAX_FACES - 1] Of Integer;
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
  End
  Else Res_[K] := New[I];
  Age[K] := 0;
  Inc(K);
 End;
 { suivis non retrouves : conserves quelques trames }
 For J := 0 To TrackN - 1 Do
  If (Not Used[J]) And (K < MAX_FACES) And (TrackAge[J] < 5) And
     (NN = 0) Then Begin
   Res_[K] := Tracks[J];
   Age[K] := TrackAge[J] + 1;
   Inc(K);
  End;
 For I := 0 To K - 1 Do Begin
  Tracks[I] := Res_[I];
  TrackAge[I] := Age[I];
 End;
 TrackN := K;
 If K > 0 Then Begin
  PrevOk := True;
  PrevCx := (Tracks[0].X1 + Tracks[0].X2) / 2;
  PrevCy := (Tracks[0].Y1 + Tracks[0].Y2) / 2;
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
 FaceCount := TrackN;
 For I := 0 To TrackN - 1 Do Faces[I] := Tracks[I];
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

{ Affiche une trame FW x FH dans la zone d'apercu (seuls les pixels
  modifies sont redessines) }
Procedure ShowFrame(Var Fr: TImg);
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
  CM_PREVIEW, CM_START: CmdEnabled := TargetOk;
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
   L5('Démarrer', 'Start', 'Start', 'Iniciar', 'Avvia'), TargetOk);
 AddWid(X0, 326, X0 + 134, 348, CM_START);
 DrawButton(X0 + 154, 326, X0 + 288, 348,
   L5('Aperçu', 'Preview', 'Vorschau', 'Vista previa', 'Anteprima'),
   TargetOk);
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
Var
 W, H, I, K, BY: Integer;
 Done, Ok: Boolean;
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
 H := 100 + NCams * 14;
 HideMouse;
 DlgFrame(W, H, L5('Choisir la caméra', 'Select camera', 'Kamera wählen',
                   'Elegir cámara', 'Scegli fotocamera'));
 BY := DlgY2 - 30;
 DlgButton(DlgX1 + W Div 2 - 100, BY, DlgX1 + W Div 2 - 10, BY + 22, 'OK');
 DlgButton(DlgX1 + W Div 2 + 10, BY, DlgX1 + W Div 2 + 100, BY + 22,
           L5('Annuler', 'Cancel', 'Abbruch', 'Cancelar', 'Annulla'));
 ShowMouse;
 DrawL;
 Done := False;
 Ok := False;
 WaitMouseUp;
 Repeat
  PollMouse;
  K := GetKeyEx;
  If K = K_ESC Then Done := True
  Else If K = K_ENTER Then Begin Done := True; Ok := True; End
  Else If (K = K_UP) And (Sel > 0) Then Begin Dec(Sel); DrawL; End
  Else If (K = K_DOWN) And (Sel < NCams - 1) Then Begin Inc(Sel); DrawL; End;
  If MouseClicked Then Begin
   If InBox(DlgX1 + 12, DlgY1 + 32, DlgX2 - 12, DlgY1 + 32 + NCams * 14) Then
   Begin
    I := (MY_ - DlgY1 - 32) Div 14;
    If (I >= 0) And (I < NCams) Then Begin Sel := I; DrawL; End;
   End
   Else If InBox(DlgX1 + W Div 2 - 100, BY, DlgX1 + W Div 2 - 10, BY + 22)
   Then Begin Done := True; Ok := True; End
   Else If InBox(DlgX1 + W Div 2 + 10, BY, DlgX1 + W Div 2 + 100, BY + 22)
   Then Done := True;
  End;
  Delay(10);
 Until Done;
 WaitMouseUp;
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
 Work: TImg;
 Mir: Boolean;
Begin
 ProcessTarget := False;
 If Not TargetOk Then Begin
  Info(L5('Choisissez d''abord une cible.', 'Select a target first.',
          'Zuerst ein Ziel wählen.', 'Elija primero un objetivo.',
          'Scegli prima un bersaglio.'));
  Exit;
 End;
 If Not Slots[CurSlot].Ok Then
  Info(L5('Aucun visage source : l''image reste inchangée.',
          'No source face: the image is left unchanged.',
          'Kein Quellgesicht: Bild bleibt unverändert.',
          'Sin rostro de origen: la imagen no cambia.',
          'Nessun volto di origine: immagine invariata.'));
 If Not ImgNew(Work, TargetImg.W, TargetImg.H, False) Then Begin
  Info('Memoire / Memory');
  Exit;
 End;
 ImgCopy(TargetImg, Work);
 TrackReset;
 SkinReset;
 Mir := OptMirror;
 OptMirror := False;
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
  K_F8, K_ESC: ExecCmd(CM_STOP);
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
  'Syntaxe : TMF [-maxcolors] [-maxscreen] [/? | -h | --help]',
  'Syntax: TMF [-maxcolors] [-maxscreen] [/? | -h | --help]',
  'Syntax: TMF [-maxcolors] [-maxscreen] [/? | -h | --help]',
  'Sintaxis: TMF [-maxcolors] [-maxscreen] [/? | -h | --help]',
  'Sintassi: TMF [-maxcolors] [-maxscreen] [/? | -h | --help]'));
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
 WriteLn(L5('Les options d''affichage sont ignorees sous Turbo Pascal.',
            'Display options are ignored under Turbo Pascal.',
            'Anzeigeoptionen werden unter Turbo Pascal ignoriert.',
            'Las opciones de pantalla se ignoran en Turbo Pascal.',
            'Le opzioni dello schermo sono ignorate in Turbo Pascal.'));
End;

Var
 I: Integer;
 Arg: String;
 Dummy: LongInt;

BEGIN
 DetectLanguage;
 For I := 1 To ParamCount Do Begin
  Arg := UpStr(ParamStr(I));
  If (Arg = '/?') Or (Arg = '-H') Or (Arg = '--HELP') Then Begin
   ShowHelpLine;
   Halt;
  End
  Else If Arg = '-MAXCOLORS' Then OptMaxColors := True
  Else If Arg = '-MAXSCREEN' Then OptMaxScreen := True;
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
 HideMouse;
 CloseGraph;
END.
