{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2024
  @website(https://www.gladir.com/vie)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program MAKEMAZE;

{$R-}

Uses {$IFDEF FPC}
      Crt,PtcGraph,PtcCrt,PtcMouse
     {$ELSE}
      Crt,Graph
     {$ENDIF};

Const
 ScreenWidth=640;
 ScreenHeight=350;
 MinBlockWidth=2;
 MaxX=200;
 MaxY=109;
 FlistSize=5000;

 Background=Black;
 Gridcolor=Green;
 SolveColor=White;

 EastDir=$01;
 NorthDir=$02;
 WestDir=$04;
 SouthDir=$08;

 Unused=$00;
 Frontier=$10;
 Reserved=$20;
 Tree=$30;

Type
 FRec=Record
  Column,Row:Byte;
 End;
 CellRec=Record
  Point:Word;
  Flags:Byte;
 End;
 CellArr=Array[1..MaxX,1..MaxY] of CellRec;
 { Un octet par cellule, drapeaux de bits :
    0: Est,    1 = barriŠre enlev‚
    1: Nord,   1 = barriŠre enlev‚
    2: Ouest,  1 = barriŠre enlev‚
    3: Sud,    1 = barriŠre enlev‚
    5,4: 0,0 = Type de cellule non utilis‚
         0,1 = FrontiŠre de cellule
         1,1 = Arbre de cellule
         1,0 = Reserv‚
    6: (Pas utilis‚)
    7: Chemin r‚solu, 1 = cette partie de cellule du chemin r‚solu
  }

Var
 FileName,FileNameCSV:String;
 RepeatQuestion,ShowGraph,SolveImmediately:Boolean;
 I:Integer;
 Err:Word;
 FList:Array[1..FListSize] of FRec;
 Cell:^CellArr;
 FNum,Width,Height:Word;
 BlockWidth:LongInt;
 HalfBlock,MaxRun:LongInt;
 RunSet:Byte;
 Ch:Char;

Function StrToUpper(S:String):String;
Var
 I:Byte;
Begin
 For I:=1 to Length(S)do Begin
  If S[I] in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
 End;
 StrToUpper:=S;
End;

Procedure InitScr;
Var
 Driver,Mode:Integer;
 ErrCode:Integer;
Begin
 {$IFDEF FPC}
  Driver:=VGA;
  Mode:=VGAHi;
 {$ELSE}
  Driver:=Detect;
  Mode:=VGAHi;
 {$ENDIF}
 InitGraph(Driver,Mode,'');
 ErrCode:=GraphResult;
 If ErrCode=grOk Then Begin
  SetColor(White);
  SetLineStyle(0, 0, 1);
 End
  Else
 Begin
  WriteLn('Erreur graphique : ',GraphErrorMsg(ErrCode));
  Halt;
 End;
End;

Function Adjust(Var x,y:Word;d:Byte):Boolean;Begin
 Case d of
  EastDir:Begin
   Inc(x);
   Adjust:=x<=Width;
  End;
  NorthDir:Begin
   Dec(y);
   Adjust:=y>0;
  End;
  WestDir:Begin
   Dec(x);
   Adjust:=x>0;
  End;
  SouthDir:Begin
   Inc(y);
   Adjust:=y<=height;
  End;
 End;
End;

Procedure Remove(x,y:Word);
Var
 I:Word;
Begin
 I:=Cell^[x,y].Point;
 With FList[FNum] do Cell^[Column,Row].Point:=I;
 FList[i]:=FList[FNum];
 Dec(FNum);
End;

Procedure Add(X,Y:Word;D:Byte);
Var
 I:Byte;
Begin
 I:=Cell^[x,y].Flags;
 Case I and $30 of
  Unused:Begin
   Cell^[X,Y].Flags:=I or Frontier;
   Inc(FNum);
   If FNum>FListSize Then Begin
    Dispose(Cell);
    CloseGraph;
    Writeln('D‚bordement de FList ! - Augmenter ®FListSize¯ pour corriger.');
    Halt(1);
   End;
   With FList[FNum] do Begin
    Column:=X;
    Row:=Y;
   End;
   Cell^[x,y].Point:=FNum;
   RunSet:=RunSet or d;
  End;
  Frontier:RunSet:=RunSet or d;
 End;
End;

Procedure AddFront(x,y:Word);
Var
 j,k:Word;
 d:Byte;
Begin
 Remove(x,y);
 RunSet:=0;
 Cell^[x,y].Flags:=Cell^[x,y].Flags or Tree;
 d:=$01;
 While d<=$08 do Begin
  J:=X;
  K:=Y;
  If Adjust(j,k,d)Then
   Add(j, k, d);
   D:=D shl 1;
  End;
End;

Procedure RemLine(x,y:Word;d:Byte);Begin
 SetColor(Background);
 x:=(x-1)*BlockWidth;
 y:=(y-1)*BlockWidth;
 Case d of
  EastDir:Line(X+BlockWidth,Y+1,X+BlockWidth,Y+BlockWidth-1);
  NorthDir:Line(X+1,Y,X+BlockWidth-1,Y);
  WestDir:Line(X,Y+1,X,Y+BlockWidth-1);
  SouthDir:Line(X+1,Y+BlockWidth,X+BlockWidth-1,Y+BlockWidth);
 End;
End;

Procedure RemBar(X,Y:Word;D:Byte);
Var
 d2:Byte;
Begin
 If(ShowGraph)Then RemLine(x,y,d);
 Cell^[x,y].Flags:=Cell^[x,y].flags or d;
 D2:=d shl 2;
 If d2>$08 Then d2:=d2 shr 4;
 If Adjust(x,y,d)Then Cell^[X,Y].Flags:=Cell^[X,Y].Flags or d2;
End;

Function RandomDir:Byte;Begin
 Case Random(4) of
  0:RandomDir:=EastDir;
  1:RandomDir:=NorthDir;
  2:RandomDir:=WestDir;
  3:RandomDir:=SouthDir;
 End;
End;

Procedure Connect(x,y:Word);
Var
 j,k:Word;
 d :Byte;
 Found:Boolean;
Begin
 Found:=False;
 While Not Found do Begin
  j:=x;
  k:=y;
  d:=RandomDir;
  If Adjust(j,k,d)Then Found:=Cell^[j,k].Flags and Tree=Tree;
 End;
 RemBar(x,y,d);
End;

Procedure Branch(x,y:Word);
Var
 RunNum:Word;
 d:Byte;
 i:Boolean;
Begin
 RunNum:=MaxRun;
 Connect(X,Y);
 AddFront(X,Y);
 Dec(RunNum);
 While(RunNum>0)and(FNum>0)and(RunSet>0)do Begin
  Repeat
   D:=RandomDir;
  Until d and RunSet>0;
  RemBar(x,y,d);
  i:=Adjust(x,y,d);
  AddFront(x,y);
  Dec(RunNum);
 End;
End;

Procedure ComputeMaze;
Var
 x,y,i:Word;
Begin
 y:=Height*BlockWidth;
 For i:=0 to Width do Begin
  x:=i*blockwidth;
 End;
 x:=Width*BlockWidth;
 For i:=0 to Height do Begin
  y:=i*BlockWidth;
 End;
 FillChar(Cell^,SizeOf(Cell^),Chr(0));
 FNum:=0;
 RunSet:=0;
 Randomize;
 x:=Random(Width)+1;
 y:=Random(Height)+1;
 Add(x,y,EastDir);
 AddFront(x,y);
 While(FNum>0)do With FList[Random(FNum)+1] do Branch(Column,Row);
End;

Procedure DrawMaze;
Var
 x,y,i:Word;
Begin
 SetColor(GridColor);
 y:=Height*BlockWidth;
 For i:=0 to Width do Begin
  x:=i*blockwidth;
  Line(x,0,x,y);
 End;
 x:=Width*BlockWidth;
 For i:=0 to height do Begin
  y:=i*BlockWidth;
  Line(0,Y,X,Y);
 End;
 FillChar(Cell^,SizeOf(Cell^),Chr(0));
 FNum:=0;
 RunSet:=0;
 Randomize;
 x:=Random(Width)+1;
 y:=Random(Height)+1;
 Add(x,y,EastDir);
 AddFront(x,y);
 While(FNum>0)do With FList[Random(FNum)+1] do Branch(Column,Row);
End;

Procedure SaveInFileMazeCSV;
Var
 F:Text;
 I,J:Integer;
Begin
 {$I-}Assign(F,FileNameCSV);
 Rewrite(F);{$I+}
 If IOResult<>0 Then Begin
  WriteLn('Impossible de cr‚er le fichier : ',FileNameCSV);
  Halt;
 End;
 For J:=1 to Height do Begin
  For I:=1 to Width do Begin
   If I>1 Then Write(F,',');
   Write(F,Cell^[I,J].Flags)
  End;
  WriteLn(F);
 End;
 Close(F);
End;

Procedure WriteInFileMaze;
Var
 F:Text;
 I,J:Integer;
Begin
 {$I-}Assign(F,FileName);
 Rewrite(F);{$I+}
 If IOResult<>0 Then Begin
  WriteLn('Impossible de cr‚er le fichier : ',FileName);
  Halt;
 End;
 Write(F,'#');
 For I:=1 to Width do Begin
  Write(F,'###');
 End;
 WriteLn(F,'#');
 For J:=1 to Height do Begin
  Write(F,'#');
  For I:=1 to Width do Begin
   If Cell^[I,J].Flags and WestDir=0 Then Write(F,'#')
                                     Else Write(F,' ');
   If Cell^[I,J].Flags and NorthDir=0 Then Write(F,'#')  Else
   If Cell^[I,J].Flags and $80=$80 Then Write(F,'.')
   			            Else Write(F,' ');
   If Cell^[I,J].Flags and EastDir=0 Then Write(F,'#')
                                     Else Write(F,' ');
  End;
  WriteLn(F,'#');
  Write(F,'#');
  For I:=1 to Width do Begin
   If Cell^[I,J].Flags and WestDir=0 Then Write(F,'#') Else
   If Cell^[I,J].Flags and $80=$80 Then Write(F,'.')
                                     Else Write(F,' ');
   If Cell^[I,J].Flags and $80=$80 Then Write(F,'.') Else
   If Cell^[I,J].Flags and Tree=Tree Then Write(F,'#')
                               Else Write(F,' ');
   If Cell^[I,J].Flags and EastDir=0 Then Write(F,'#') Else
   If Cell^[I,J].Flags and $80=$80 Then Write(F,'.')
                                      Else Write(F,' ');
  End;
  WriteLn(F,'#');
  Write(F,'#');
  For I:=1 to Width do Begin
   If Cell^[I,J].Flags and WestDir=0 Then Write(F,'#')
                                     Else Write(F,' ');
   If Cell^[I,J].Flags and SouthDir=0 Then Write(F,'#') Else
   If Cell^[I,J].Flags and $80=$80 Then Write(F,'.')
                               Else Write(F,' ');
   If Cell^[I,J].Flags and EastDir=0 Then Write(F,'#')
                                     Else Write(F,' ');
  End;
  WriteLn(F,'#');
 End;
 Write(F,'#');
 For I:=1 to Width do Begin
  Write(F,'###');
 End;
 WriteLn(F,'#');
 Close(F);
End;

Procedure Dot(x,y,Colr:Word);Begin
 PutPixel(BlockWidth*x-HalfBlock,BlockWidth*y-HalfBlock,Colr);
End;

Procedure Solve(X,Y,EndX,EndY:Word);
Var
 j,k:Word;
 d:Byte;
 i:Boolean;
Begin
 d:=EastDir;
 While(x<>EndX)or(Y<>Endy)do Begin
  If d=$01 Then d:=$08
           Else d:=d shr 1;
  While Cell^[x,y].Flags and d=0 do Begin
   D:=D shl 1;
   If D>$08 Then D:=D shr 4;
  End;
  j:=x;
  k:=y;
  i:=Adjust(x,y,d);
  With Cell^[j,k] do Begin
   Flags:=((((Cell^[x,y].Flags xor $80) xor Flags)and $80) xor Flags);
   If(ShowGraph)Then Begin
    If Flags and $80<>0 Then Dot(j,k,SolveColor)
                        Else Dot(j,k,Background);
   End;
  End;
 End;
 If(ShowGraph)Then Dot(endx,endy,SolveColor);
End;

Procedure ManSolve(X,Y,EndX,EndY:Word);
Var
 j,k:Word;
 d:Byte;
 ch:Char;
Begin
 Ch:=' ';
 While((x<>EndX)or(Y<>EndY))and(Ch<>'X')and(Ch<>#27) do Begin
  Dot(x,y,SolveColor);
  Ch:=UpCase(ReadKey);
  Dot(x,y,Background);
  d:=0;
  Case ch of
   #0:Begin
    Ch:=ReadKey;
    Case Ch of
     #72:d:=NorthDir;
     #75:d:=WestDir;
     #77:d:=EastDir;
     #80:d:=SouthDir;
    End;
   End;
   'I','W':d:=NorthDir;
   'J','A':d:=WestDir;
   'K','D':d:=EastDir;
   'M','S':d:=SouthDir;
  End;
  If d>0 Then Begin
   j:=x;
   k:=y;
   If(Cell^[x,y].Flags and d>0)and Adjust(j, k, d)Then Begin
    x:=j;
    y:=k;
   End;
  End;
 End;
End;

Procedure SolveMaze;
Var
 x,y,EndX,EndY:Word;
 Ch:Char;
Begin
 X:=1;
 Y:=Random(Height)+1;
 EndX:=Width;
 EndY:=Random(Height)+1;
 If(ShowGraph)Then Begin
  RemLine(x,y,WestDir);
  RemLine(EndX,EndY,EastDir);
 End;
 If Not(SolveImmediately)Then ManSolve(X,Y,EndX,EndY);
 Solve(X,Y,EndX,EndY);
End;

Procedure GetSize;
Var
 J,K:Real;
Begin
 If BlockWidth<minblockwidth Then Begin
  Repeat
   WriteLn;
   Write('Taille du labyrinthe : ',MinBlockWidth,' (difficile) … 95 (facile) ');
   Readln(BlockWidth);
  Until (BlockWidth>=MinBlockWidth)and(BlockWidth<96);
  WriteLn;
 End;
 If MaxRun=-1 Then Begin
  Write('Longueur maximal d''une branche: 1 Facile … 50 Diffilce, (0 illimit‚) ');
  Readln(MaxRun);
 End;
 If MaxRun<=0 Then MaxRun:=65535;
 J:=ScreenWidth/BlockWidth;
 K:=ScreenHeight/BlockWidth;
 If J=Int(J)Then J:=J-1;
 If K=Int(K)Then K:=K-1;
 Width:=Trunc(J);
 Height:=Trunc(K);
 If(Width>MaxX)or(Height>MaxY)Then Begin
  Width:=MaxX;
  Height:=MaxY;
 End;
 HalfBlock:=BlockWidth shr 1;
End;

BEGIN
 {$IFDEF FPC}
  {$IFDEF WINDOWS}
   SetUseACP(False);
  {$ENDIF}
 {$ENDIF}
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('MAKEMAZE : Cette commande permet de g‚n‚rer un labyrinthe.');
  WriteLn;
  WriteLn('Syntaxe : MAKEMAZE [/SHOWGRAPH] [/WIDTH=largeur] [/MAXBRANCH=branche]');
  WriteLn('                   [/SOLVE] [/FILE:fichier] [/SAVECSV:fichier]');
  WriteLn;
  WriteLn(' /FILE:fichier      Sauvegarde le labyrinthe dans un fichier texte.');
  WriteLn(' /MAXBRANCH=branche Longueur maximal d''une branche: 1=facile ',
                              '… 50=difficile, (0 illimit‚)');
  WriteLn(' /SAVECSV:fichier   Sauvegarde le labyrinthe dans un fichier CSV.');
  WriteLn(' /SHOWGRAPH         Affiche en ‚cran graphique le labyrinthe');
  WriteLn(' /SOLVE             Affiche imm‚diatement la solution');
  WriteLn(' /WIDTH=largeur     Largeur du labyrinthe (',MinBlockWidth,
                               '=difficile … 95=facile');
 End
  Else
 Begin
  FileName:='';
  FileNameCSV:='';
  BlockWidth:=-1;
  ShowGraph:=False;
  RepeatQuestion:=True;
  SolveImmediately:=False;
  For I:=1 to ParamCount do Begin
   If(StrToUpper(Copy(ParamStr(I),1,Length('/SAVECSV:')))='/SAVECSV:')Then Begin
    FileNameCSV:=Copy(ParamStr(I),Length('/SAVECSV:')+1,255);
    RepeatQuestion:=False;
   End
    Else
   If(StrToUpper(Copy(ParamStr(I),1,Length('/FILE:')))='/FILE:')Then Begin
    FileName:=Copy(ParamStr(I),Length('/FILE:')+1,255);
    RepeatQuestion:=False;
   End
    Else
   If(StrToUpper(Copy(ParamStr(I),1,Length('/MAXBRANCH=')))='/MAXBRANCH=')Then Begin
    Val(Copy(ParamStr(I),Length('/MAXBRANCH=')+1,255),MaxRun,Err);
    RepeatQuestion:=False;
   End
    Else
   If(StrToUpper(Copy(ParamStr(I),1,Length('/WIDTH=')))='/WIDTH=')Then Begin
    Val(Copy(ParamStr(I),Length('/WIDTH=')+1,255),BlockWidth,Err);
    RepeatQuestion:=False;
   End
    Else
   If StrToUpper(ParamStr(I))='/SHOWGRAPH'Then ShowGraph:=True Else
   If StrToUpper(ParamStr(I))='/SOLVE'Then SolveImmediately:=True;
  End;
  If FileName<>''Then Begin
   GetSize;
   If(ShowGraph)Then InitScr;
   New(Cell);
   If(ShowGraph)Then DrawMaze
                Else ComputeMaze;
   If(SolveImmediately)Then SolveMaze;
   WriteInFileMaze;
   If(ShowGraph)Then Begin
    While KeyPressed do Ch:=ReadKey;
    Ch:=ReadKey;
   End;
   Dispose(Cell);
   If(ShowGraph)Then CloseGraph;
  End
   Else
  If FileNameCSV<>''Then Begin
   GetSize;
   If(ShowGraph)Then InitScr;
   New(Cell);
   If(ShowGraph)Then DrawMaze
                Else ComputeMaze;
   If(SolveImmediately)Then SolveMaze;
   SaveInFileMazeCSV;
   If(ShowGraph)Then Begin
    While KeyPressed do Ch:=ReadKey;
    Ch:=ReadKey;
   End;
   Dispose(Cell);
   If(ShowGraph)Then CloseGraph;
  End
   Else
  If(ShowGraph)Then Begin
   Repeat
    GetSize;
    InitScr;
    New(Cell);
    DrawMaze;
    SolveMaze;
    If(ShowGraph)Then Begin
     While KeyPressed do Ch:=ReadKey;
     Ch:=ReadKey;
    End;
    Dispose(Cell);
    CloseGraph;
    If(RepeatQuestion)Then Begin
     while KeyPressed do ch := readkey;
     Write('Un autre labyrinthe ? ');
     ch:=UpCase(ReadKey);
    End
     Else
    Ch:=#27;
   Until Ch in[#27,'N'];
  End;
 End;
END.