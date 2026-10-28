{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/vie)
  @abstract(Target: Free Pascal 3.x)

  HF : clone de la commande hf (Hugging Face Hub CLI, huggingface_hub).

  Syntaxe :
   hf --help
   hf version
   hf env
   hf auth login | logout | whoami | list | switch
   hf download REPO_ID [FICHIERS...] [--repo-type model|dataset|space]
               [--revision REV] [--include MOTIF] [--exclude MOTIF]
               [--local-dir DIR] [--cache-dir DIR] [--force-download]
               [--dry-run] [--quiet] [--token JETON]
   hf upload REPO_ID [CHEMIN_LOCAL] [CHEMIN_DANS_DEPOT] [--include ..]
             [--exclude ..] [--delete ..] [--commit-message ..] [--create-pr]
   hf models|datasets|spaces ls|info
   hf repos create|delete|move|settings|branch|tag|delete-files
   hf cache ls|rm|prune|verify
   hf collections | papers | discussions | endpoints | jobs
   hf cp | sync | extensions | skills | update | buckets

  Chaque sous-commande accepte --help (ex. : hf download --help).

  Fonctionnement :
   - download : liste les fichiers du depot (API /revision), telecharge avec
     reprise (.incomplete), range les fichiers dans le cache
     (models--org--nom/snapshots/COMMIT/..., refs/REV) ou dans --local-dir
     (avec les fichiers .cache/huggingface/download/*.metadata). Sans lien
     symbolique (impossible avec l'unite DOS), le cache contient les fichiers
     directement dans snapshots/ (comme huggingface_hub sous Windows sans
     mode developpeur).
   - upload : preupload, objets LFS (SHA-256, envoi simple ou multipart,
     verification) puis commit NDJSON ; creation du depot si absent.
   - auth : jetons stockes comme huggingface_hub (~/.cache/huggingface/token et
     stored_tokens), variables HF_TOKEN / HF_HOME / HF_HUB_CACHE / HF_ENDPOINT.

  Reseau :
   - sous Windows, WinInet (wininet.dll) est utilise (HTTPS, proxy du
     systeme) ; les redirections sont suivies manuellement et le jeton n'est
     envoye qu'a l'hote d'origine (jamais au CDN);
   - sous les autres systemes, la commande curl est appelee via Exec (unite
     DOS) afin que le programme reste utilisable et testable.

  Limites de ce clone :
   - les "buckets" (hf buckets, hf cp/sync vers un bucket) ne sont pas pris
     en charge ; hf endpoints deploy, hf jobs scheduled et l'installation
     d'extensions depuis GitHub non plus;
   - le telechargement est sequentiel (--max-workers est accepte puis ignore);
   - --add-to-git-credential et hf upload --every ne sont pas implementes;
   - l'aide en ligne (hf --help, hf COMMANDE --help, hf /?) et les erreurs
     d'usage sont en francais par defaut, et en anglais si la variable
     d'environnement LANGUAGE commence par EN (ex. : LANGUAGE=EN);
     les autres messages d'execution restent en anglais, comme l'outil
     d'origine.

  Contraintes respectees :
   - un seul fichier source, aucun fichier d'inclusion;
   - la seule unite utilisee est DOS (le reste vient de l'unite System);
   - compilable en Windows 32 bits.

  Compilation : fpc -O3 HF.PAS
}

Program HF;

{$IFDEF FPC}
 {$MODE OBJFPC}
 {$H+}
 {$INLINE ON}
 {$R-}
 {$Q-}
 {$IOCHECKS OFF}
 {$NOTES OFF}
 {$HINTS OFF}
 {$WARNINGS OFF}
{$ENDIF}

Uses DOS;

Const
 ToolVersion  = '1.0.0';
 UserAgent    = 'hf-pascal/1.0.0';
 DefaultEndpoint = 'https://huggingface.co';
 EndpointsApi = 'https://api.endpoints.huggingface.cloud/v2/endpoint';
 {$IFDEF WINDOWS}
 DS = '\';
 {$ELSE}
 DS = '/';
 {$ENDIF}

Type
 TStrArr = Array of AnsiString;

 TSList = Record
  A:TStrArr;
  N:LongInt;
 End;

 TBuf = Record
  D:AnsiString;
  N:LongInt;
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

Function Fix1(X:Double):AnsiString;
Var
 S:AnsiString;
Begin
 Str(X:0:1,S);
 Fix1:=S;
End;

Function ToInt(Const S:AnsiString;Def:Int64):Int64;
Var
 V:Int64;
 Code:LongInt;
Begin
 Val(S,V,Code);
 If(Code<>0)or(S='')Then ToInt:=Def Else ToInt:=V;
End;

Function LoStr(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 Result:=S;
 For I:=1 to Length(Result)do If Result[I]in['A'..'Z']Then
   Result[I]:=Chr(Ord(Result[I])+32);
End;

Function UpStr(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 Result:=S;
 For I:=1 to Length(Result)do If Result[I]in['a'..'z']Then
   Result[I]:=Chr(Ord(Result[I])-32);
End;

Function TrimStr(Const S:AnsiString):AnsiString;
Var
 A,B:LongInt;
Begin
 A:=1;B:=Length(S);
 While(A<=B)and(S[A]in[#0..#32])do Inc(A);
 While(B>=A)and(S[B]in[#0..#32])do Dec(B);
 TrimStr:=Copy(S,A,B-A+1);
End;

Function StartsWith(Const S,P:AnsiString):Boolean;
Begin
 StartsWith:=(Length(S)>=Length(P))and(Copy(S,1,Length(P))=P);
End;

Function EndsWith(Const S,P:AnsiString):Boolean;
Begin
 EndsWith:=(Length(S)>=Length(P))and(Copy(S,Length(S)-Length(P)+1,Length(P))=P);
End;

Function ReplaceAll(Const S,From,Dest:AnsiString):AnsiString;
Var
 P:LongInt;
 T,R:AnsiString;
Begin
 If From='' Then Begin ReplaceAll:=S;Exit;End;
 T:=S;R:='';
 Repeat
  P:=Pos(From,T);
  If P=0 Then Break;
  R:=R+Copy(T,1,P-1)+Dest;
  Delete(T,1,P+Length(From)-1);
 Until False;
 ReplaceAll:=R+T;
End;

Procedure SAdd(Var L:TSList;Const S:AnsiString);
Begin
 If L.N>=Length(L.A)Then SetLength(L.A,Length(L.A)*2+16);
 L.A[L.N]:=S;
 Inc(L.N);
End;

Procedure SClear(Var L:TSList);
Begin
 SetLength(L.A,0);
 L.N:=0;
End;

Function SIndex(Const L:TSList;Const S:AnsiString):LongInt;
Var
 I:LongInt;
Begin
 For I:=0 to L.N-1 do If L.A[I]=S Then Begin SIndex:=I;Exit;End;
 SIndex:=-1;
End;

Procedure SortRange(Var A:TStrArr;Lo,Hi:LongInt);
Var
 I,J:LongInt;
 P,T:AnsiString;
Begin
 While Lo<Hi do Begin
  I:=Lo;J:=Hi;
  P:=A[(Lo+Hi)div 2];
  Repeat
   While A[I]<P do Inc(I);
   While A[J]>P do Dec(J);
   If I<=J Then Begin
    T:=A[I];A[I]:=A[J];A[J]:=T;
    Inc(I);Dec(J);
   End;
  Until I>J;
  If J-Lo<Hi-I Then Begin
   SortRange(A,Lo,J);Lo:=I;
  End
  Else Begin
   SortRange(A,I,Hi);Hi:=J;
  End;
 End;
End;

Procedure SSort(Var L:TSList);
Begin
 If L.N>1 Then SortRange(L.A,0,L.N-1);
End;

{ decoupe S selon le caractere Sep }
Procedure SplitStr(Const S:AnsiString;Sep:Char;Var L:TSList);
Var
 I,B:LongInt;
Begin
 SClear(L);
 B:=1;
 For I:=1 to Length(S)do If S[I]=Sep Then Begin
  SAdd(L,Copy(S,B,I-B));
  B:=I+1;
 End;
 SAdd(L,Copy(S,B,Length(S)-B+1));
End;

Procedure BufAdd(Var B:TBuf;Const S:AnsiString);
Var
 Need:LongInt;
Begin
 If S='' Then Exit;
 Need:=B.N+Length(S);
 If Need>Length(B.D)Then Begin
  If Length(B.D)*2>Need Then SetLength(B.D,Length(B.D)*2)
                        Else SetLength(B.D,Need+4096);
 End;
 Move(S[1],B.D[B.N+1],Length(S));
 B.N:=Need;
End;

Function BufStr(Var B:TBuf):AnsiString;
Begin
 BufStr:=Copy(B.D,1,B.N);
End;

Procedure BufClear(Var B:TBuf);
Begin
 B.D:='';B.N:=0;
End;

Procedure Die(Const Msg:AnsiString);
Begin
 WriteLn(StdErr,'Error: '+Msg);
 Halt(1);
End;

Procedure Warn(Const Msg:AnsiString);
Begin
 WriteLn(StdErr,'Warning: '+Msg);
End;

{ ------------------------------------------------------------------ }
{ Fichiers et repertoires                                             }
{ ------------------------------------------------------------------ }

Function NormSep(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 Result:=S;
 For I:=1 to Length(Result)do If Result[I]in['/','\']Then Result[I]:=DS;
End;

Function UnixSep(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 Result:=S;
 For I:=1 to Length(Result)do If Result[I]='\' Then Result[I]:='/';
End;

Function DropSlash(Const S:AnsiString):AnsiString;
Begin
 Result:=S;
 While(Length(Result)>1)and(Result[Length(Result)]in['/','\'])and
  not((Length(Result)=3)and(Result[2]=':'))do Delete(Result,Length(Result),1);
End;

Function JoinPath(Const A,B:AnsiString):AnsiString;
Begin
 If A='' Then JoinPath:=B Else If B='' Then JoinPath:=A
  Else If A[Length(A)]in['/','\']Then JoinPath:=A+B
  Else JoinPath:=A+DS+B;
End;

Function BaseName(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
 T:AnsiString;
Begin
 T:=DropSlash(S);
 I:=Length(T);
 While(I>0)and not(T[I]in['/','\'])do Dec(I);
 BaseName:=Copy(T,I+1,Length(T)-I);
End;

Function ParentDir(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
 T:AnsiString;
Begin
 T:=DropSlash(S);
 I:=Length(T);
 While(I>0)and not(T[I]in['/','\'])do Dec(I);
 If I<=0 Then ParentDir:='' Else If I=1 Then ParentDir:=Copy(T,1,1)
  Else ParentDir:=Copy(T,1,I-1);
End;

Function PathExists(Const P:AnsiString;Var IsDir:Boolean):Boolean;
Var
 SR:SearchRec;
 T:AnsiString;
Begin
 PathExists:=False;IsDir:=False;
 T:=DropSlash(P);
 If T='' Then Exit;
 FindFirst(T,AnyFile,SR);
 If DosError=0 Then Begin
  PathExists:=True;
  IsDir:=(SR.Attr and Directory)<>0;
 End;
 FindClose(SR);
End;

Function FileExists_(Const P:AnsiString):Boolean;
Var
 D:Boolean;
Begin
 FileExists_:=PathExists(P,D)and not D;
End;

Function DirExists_(Const P:AnsiString):Boolean;
Var
 D:Boolean;
Begin
 DirExists_:=PathExists(P,D)and D;
End;

Procedure MkDirs(Const Path:AnsiString);
Var
 I:LongInt;
 T:AnsiString;
Begin
 T:=DropSlash(Path);
 If(T='')or DirExists_(T)Then Exit;
 For I:=2 to Length(T)do If T[I]in['/','\']Then Begin
  {$I-}MkDir(Copy(T,1,I-1));{$I+}
  If IOResult<>0 Then;
 End;
 {$I-}MkDir(T);{$I+}
 If IOResult<>0 Then;
End;

Function FileSizeOf(Const P:AnsiString):Int64;
Var
 F:File;
Begin
 FileSizeOf:=-1;
 Assign(F,P);
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0 Then Exit;
 FileSizeOf:=FileSize(F);
 Close(F);
 If IOResult<>0 Then;
End;

Function DelFile(Const P:AnsiString):Boolean;
Var
 F:File;
Begin
 Assign(F,P);
 {$I-}Erase(F);{$I+}
 DelFile:=IOResult=0;
End;

Function MoveFile_(Const A,B:AnsiString):Boolean;
Var
 F:File;
Begin
 If FileExists_(B)Then DelFile(B);
 Assign(F,A);
 {$I-}Rename(F,B);{$I+}
 MoveFile_:=IOResult=0;
End;

Function ReadAll(Const P:AnsiString;Var S:AnsiString):Boolean;
Var
 F:File;
 N:Int64;
Begin
 ReadAll:=False;
 S:='';
 Assign(F,P);
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0 Then Exit;
 N:=FileSize(F);
 SetLength(S,N);
 If N>0 Then BlockRead(F,S[1],N);
 Close(F);
 If IOResult<>0 Then Exit;
 ReadAll:=True;
End;

Function WriteAll(Const P,S:AnsiString):Boolean;
Var
 F:File;
Begin
 WriteAll:=False;
 MkDirs(ParentDir(P));
 Assign(F,P);
 {$I-}Rewrite(F,1);{$I+}
 If IOResult<>0 Then Exit;
 If Length(S)>0 Then BlockWrite(F,S[1],Length(S));
 Close(F);
 WriteAll:=IOResult=0;
End;

Function CopyFile_(Const A,B:AnsiString):Boolean;
Var
 F,G:File;
 Buf:Pointer;
 N,W:LongInt;
Begin
 CopyFile_:=False;
 Assign(F,A);
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0 Then Exit;
 MkDirs(ParentDir(B));
 Assign(G,B);
 {$I-}Rewrite(G,1);{$I+}
 If IOResult<>0 Then Begin Close(F);Exit;End;
 GetMem(Buf,262144);
 Repeat
  N:=0;
  {$I-}BlockRead(F,Buf^,262144,N);{$I+}
  If IOResult<>0 Then Break;
  If N>0 Then Begin
   W:=0;
   {$I-}BlockWrite(G,Buf^,N,W);{$I+}
   If(IOResult<>0)or(W<>N)Then Begin N:=-1;Break;End;
  End;
 Until N=0;
 FreeMem(Buf);
 Close(F);Close(G);
 If IOResult<>0 Then;
 CopyFile_:=N=0;
End;

Type
 TEntry = Record
  Name:AnsiString;
  IsDir:Boolean;
 End;
 TEntries = Array of TEntry;

Procedure ListDir(Const Dir:AnsiString;Var E:TEntries);
Var
 SR:SearchRec;
 N:LongInt;
Begin
 SetLength(E,0);N:=0;
 FindFirst(JoinPath(DropSlash(Dir),'*'),AnyFile,SR);
 While DosError=0 do Begin
  If(SR.Name<>'.')and(SR.Name<>'..')Then Begin
   If N>=Length(E)Then SetLength(E,Length(E)*2+16);
   E[N].Name:=SR.Name;
   E[N].IsDir:=(SR.Attr and Directory)<>0;
   Inc(N);
  End;
  FindNext(SR);
 End;
 FindClose(SR);
 SetLength(E,N);
End;

Procedure WalkRec(Const Root,Rel:AnsiString;Var L:TSList);
Var
 E:TEntries;
 I:LongInt;
 R:AnsiString;
Begin
 ListDir(JoinPath(Root,NormSep(Rel)),E);
 For I:=0 to High(E)do Begin
  If Rel='' Then R:=E[I].Name Else R:=Rel+'/'+E[I].Name;
  If E[I].IsDir Then WalkRec(Root,R,L) Else SAdd(L,R);
 End;
End;

{ liste recursive des fichiers : chemins relatifs avec '/' (la liste est videe) }
Procedure WalkFiles(Const Root,Rel:AnsiString;Var L:TSList);
Begin
 SClear(L);
 WalkRec(Root,Rel,L);
End;

Procedure RmTree(Const Dir:AnsiString);
Var
 E:TEntries;
 I:LongInt;
 P:AnsiString;
Begin
 ListDir(Dir,E);
 For I:=0 to High(E)do Begin
  P:=JoinPath(Dir,E[I].Name);
  If E[I].IsDir Then RmTree(P) Else DelFile(P);
 End;
 {$I-}RmDir(DropSlash(Dir));{$I+}
 If IOResult<>0 Then;
End;

Function AbsPath(Const P:AnsiString):AnsiString;
Begin
 AbsPath:=DropSlash(FExpand(P));
End;

Function HomeDir:AnsiString;
Begin
 Result:=GetEnv('HOME');
 If Result='' Then Result:=GetEnv('USERPROFILE');
 If Result='' Then Result:='.';
End;

{ ------------------------------------------------------------------ }
{ Dates                                                               }
{ ------------------------------------------------------------------ }

Function DaysFromCivil(Y0,M,D:LongInt):Int64;
Var
 Y,Era,Yoe,Doy,Doe:Int64;
Begin
 Y:=Y0;
 If M<=2 Then Dec(Y);
 If Y>=0 Then Era:=Y div 400 Else Era:=(Y-399)div 400;
 Yoe:=Y-Era*400;
 If M>2 Then Doy:=(153*(M-3)+2)div 5+D-1 Else Doy:=(153*(M+9)+2)div 5+D-1;
 Doe:=Yoe*365+Yoe div 4-Yoe div 100+Doy;
 DaysFromCivil:=Era*146097+Doe-719468;
End;

Function NowEpoch:Int64;
Var
 Y,M,D,DW,H,Mi,S,HS:Word;
Begin
 GetDate(Y,M,D,DW);
 GetTime(H,Mi,S,HS);
 NowEpoch:=DaysFromCivil(Y,M,D)*86400+H*3600+Mi*60+S;
End;

Function PackedEpoch(T:LongInt):Int64;
Var
 DT:DateTime;
Begin
 UnpackTime(T,DT);
 PackedEpoch:=DaysFromCivil(DT.Year,DT.Month,DT.Day)*86400+DT.Hour*3600+DT.Min*60+DT.Sec;
End;

Function FileMTime(Const P:AnsiString):Int64;
Var
 F:File;
 T:LongInt;
Begin
 FileMTime:=0;
 Assign(F,P);
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0 Then Exit;
 GetFTime(F,T);
 If DosError=0 Then FileMTime:=PackedEpoch(T);
 Close(F);
 If IOResult<>0 Then;
End;

Function StampToStr(E:Int64):AnsiString;
Var
 Days,Rem_:Int64;
 Z,Era,Doe,Yoe,Y,Doy,Mp,D,M:Int64;
 S:AnsiString;
 Function P2(N:Int64):AnsiString;
 Begin
  If N<10 Then P2:='0'+IStr(N) Else P2:=IStr(N);
 End;
Begin
 Days:=E div 86400;Rem_:=E mod 86400;
 Z:=Days+719468;
 If Z>=0 Then Era:=Z div 146097 Else Era:=(Z-146096)div 146097;
 Doe:=Z-Era*146097;
 Yoe:=(Doe-Doe div 1460+Doe div 36524-Doe div 146096)div 365;
 Y:=Yoe+Era*400;
 Doy:=Doe-(365*Yoe+Yoe div 4-Yoe div 100);
 Mp:=(5*Doy+2)div 153;
 D:=Doy-(153*Mp+2)div 5+1;
 If Mp<10 Then M:=Mp+3 Else M:=Mp-9;
 If M<=2 Then Inc(Y);
 S:=IStr(Y)+'-'+P2(M)+'-'+P2(D)+' '+P2(Rem_ div 3600)+':'+P2((Rem_ mod 3600)div 60)+
   ':'+P2(Rem_ mod 60);
 StampToStr:=S;
End;

Function AgoStr(Secs:Int64):AnsiString;
Var
 N:Int64;
 Function Pl(N:Int64;Const U:AnsiString):AnsiString;
 Begin
  If N=1 Then Pl:='1 '+U+' ago' Else Pl:=IStr(N)+' '+U+'s ago';
 End;
Begin
 If Secs<0 Then Secs:=0;
 If Secs<60 Then AgoStr:='a few seconds ago'
 Else If Secs<3600 Then AgoStr:=Pl(Secs div 60,'minute')
 Else If Secs<86400 Then AgoStr:=Pl(Secs div 3600,'hour')
 Else If Secs<86400*30 Then AgoStr:=Pl(Secs div 86400,'day')
 Else If Secs<86400*365 Then AgoStr:=Pl(Secs div(86400*30),'month')
 Else AgoStr:=Pl(Secs div(86400*365),'year');
End;

Procedure WaitSec(N:LongInt);
Var
 Y,M,D,DW:Word;
 H,Mi,S,HS:Word;
 T0,T1:Int64;
Begin
 T0:=NowEpoch;
 Repeat
  T1:=NowEpoch;
 Until T1-T0>=N;
End;

Function HumanSize(N:Int64):AnsiString;
Const
 Units:Array[0..4]of AnsiString=('B','K','M','G','T');
Var
 D:Double;
 U:LongInt;
Begin
 D:=N;U:=0;
 While(D>=1000)and(U<4)do Begin D:=D/1000;Inc(U);End;
 If U=0 Then HumanSize:=IStr(N)+'B' Else HumanSize:=Fix1(D)+Units[U];
End;

{ ------------------------------------------------------------------ }
{ Globs (fnmatch) et URL                                              }
{ ------------------------------------------------------------------ }

Function GlobMatch(Const P:AnsiString;PI:LongInt;Const S:AnsiString;SI:LongInt):Boolean;
Var
 C:Char;
 J:LongInt;
 Neg,Ok:Boolean;
Begin
 GlobMatch:=False;
 While PI<=Length(P)do Begin
  C:=P[PI];
  If C='*' Then Begin
   While(PI<=Length(P))and(P[PI]='*')do Inc(PI);
   If PI>Length(P)Then Begin GlobMatch:=True;Exit;End;
   While SI<=Length(S)+1 do Begin
    If GlobMatch(P,PI,S,SI)Then Begin GlobMatch:=True;Exit;End;
    Inc(SI);
   End;
   Exit;
  End
  Else If C='?' Then Begin
   If SI>Length(S)Then Exit;
   Inc(PI);Inc(SI);
  End
  Else If C='[' Then Begin
   J:=PI+1;
   Neg:=False;
   If(J<=Length(P))and(P[J]in['!','^'])Then Begin Neg:=True;Inc(J);End;
   Ok:=False;
   If SI>Length(S)Then Exit;
   Repeat
    If J>Length(P)Then Break;
    If(P[J]=']')and(J>PI+1+Ord(Neg))Then Break;
    If(J+2<=Length(P))and(P[J+1]='-')and(P[J+2]<>']')Then Begin
     If(S[SI]>=P[J])and(S[SI]<=P[J+2])Then Ok:=True;
     Inc(J,3);
    End
    Else Begin
     If S[SI]=P[J]Then Ok:=True;
     Inc(J);
    End;
   Until False;
   If J>Length(P)Then Begin
    { crochet non ferme : caractere litteral }
    If S[SI]<>'[' Then Exit;
    Inc(PI);Inc(SI);
   End
   Else Begin
    If Ok=Neg Then Exit;
    PI:=J+1;Inc(SI);
   End;
  End
  Else Begin
   If(SI>Length(S))or(S[SI]<>C)Then Exit;
   Inc(PI);Inc(SI);
  End;
 End;
 GlobMatch:=SI>Length(S);
End;

Function Glob(Const Pat,S:AnsiString):Boolean;
Var
 P:AnsiString;
Begin
 P:=Pat;
 If EndsWith(P,'/')Then P:=P+'*';
 Glob:=GlobMatch(P,1,S,1);
End;

Function HasWild(Const S:AnsiString):Boolean;
Begin
 HasWild:=(Pos('*',S)>0)or(Pos('?',S)>0)or(Pos('[',S)>0);
End;

Function UrlEnc(Const S:AnsiString;KeepSlash:Boolean):AnsiString;
Const
 Hex:AnsiString='0123456789ABCDEF';
Var
 I:LongInt;
 C:Char;
Begin
 Result:='';
 For I:=1 to Length(S)do Begin
  C:=S[I];
  If C in['A'..'Z','a'..'z','0'..'9','-','_','.','~']Then Result:=Result+C
  Else If(C='/')and KeepSlash Then Result:=Result+C
  Else Result:=Result+'%'+Hex[(Ord(C)shr 4)+1]+Hex[(Ord(C)and 15)+1];
 End;
End;

Function UrlQ(Const S:AnsiString):AnsiString;
Begin
 UrlQ:=UrlEnc(S,False);
End;

Procedure SplitUrl(Const U:AnsiString;Var Scheme,Host:AnsiString;Var Port:LongInt;Var Path:AnsiString);
Var
 P,Q:LongInt;
 HP:AnsiString;
Begin
 Scheme:='http';Port:=0;Path:='/';
 P:=Pos('://',U);
 If P>0 Then Begin
  Scheme:=LoStr(Copy(U,1,P-1));
  HP:=Copy(U,P+3,Length(U));
 End
 Else HP:=U;
 Q:=Pos('/',HP);
 If Q>0 Then Begin
  Path:=Copy(HP,Q,Length(HP));
  HP:=Copy(HP,1,Q-1);
 End;
 Q:=Pos('@',HP);
 If Q>0 Then Delete(HP,1,Q);
 Q:=Pos(':',HP);
 If Q>0 Then Begin
  Port:=ToInt(Copy(HP,Q+1,Length(HP)),0);
  HP:=Copy(HP,1,Q-1);
 End;
 If Port=0 Then If Scheme='https' Then Port:=443 Else Port:=80;
 Host:=HP;
End;

Function UrlHost(Const U:AnsiString):AnsiString;
Var
 Sc,H,Pa:AnsiString;
 Po:LongInt;
Begin
 SplitUrl(U,Sc,H,Po,Pa);
 UrlHost:=LoStr(H);
End;

Function ResolveUrl(Const Base,Loc:AnsiString):AnsiString;
Var
 Sc,H,Pa:AnsiString;
 Po,I:LongInt;
 Pre:AnsiString;
Begin
 If(Pos('://',Loc)>0)and(Pos('://',Loc)<8)Then Begin ResolveUrl:=Loc;Exit;End;
 SplitUrl(Base,Sc,H,Po,Pa);
 Pre:=Sc+'://'+H;
 If((Sc='https')and(Po<>443))or((Sc='http')and(Po<>80))Then Pre:=Pre+':'+IStr(Po);
 If StartsWith(Loc,'/')Then ResolveUrl:=Pre+Loc
 Else Begin
  I:=Length(Pa);
  While(I>0)and(Pa[I]<>'/')do Dec(I);
  ResolveUrl:=Pre+Copy(Pa,1,I)+Loc;
 End;
End;

{ ------------------------------------------------------------------ }
{ JSON                                                                }
{ ------------------------------------------------------------------ }

Const
 JK_NULL=0; JK_BOOL=1; JK_NUM=2; JK_STR=3; JK_ARR=4; JK_OBJ=5;

Type
 TJNode = Record
  Kind:Byte;
  Key,S:AnsiString;
  First,Last,Next,Cnt:LongInt;
 End;

Var
 JP:Array of TJNode;
 JN:LongInt;
 JSrc:AnsiString;
 JPos:LongInt;
 JErr:Boolean;

Function JNew(K:Byte):LongInt;
Begin
 If JN>=Length(JP)Then SetLength(JP,Length(JP)*2+1024);
 JP[JN].Kind:=K;
 JP[JN].Key:='';
 JP[JN].S:='';
 JP[JN].First:=-1;JP[JN].Last:=-1;JP[JN].Next:=-1;JP[JN].Cnt:=0;
 JNew:=JN;
 Inc(JN);
End;

Procedure JAppend(Par,Child:LongInt);
Begin
 If JP[Par].Last<0 Then JP[Par].First:=Child Else JP[JP[Par].Last].Next:=Child;
 JP[Par].Last:=Child;
 Inc(JP[Par].Cnt);
End;

Procedure JReset;
Begin
 SetLength(JP,0);
 JN:=0;
End;

Procedure JSkip;
Begin
 While(JPos<=Length(JSrc))and(JSrc[JPos]in[#9,#10,#13,' '])do Inc(JPos);
End;

Function Utf8Enc(C:LongWord):AnsiString;
Begin
 If C<$80 Then Utf8Enc:=Chr(C)
 Else If C<$800 Then Utf8Enc:=Chr($C0 or(C shr 6))+Chr($80 or(C and $3F))
 Else If C<$10000 Then Utf8Enc:=Chr($E0 or(C shr 12))+Chr($80 or((C shr 6)and $3F))+
   Chr($80 or(C and $3F))
 Else Utf8Enc:=Chr($F0 or(C shr 18))+Chr($80 or((C shr 12)and $3F))+
   Chr($80 or((C shr 6)and $3F))+Chr($80 or(C and $3F));
End;

Function HexVal(Const S:AnsiString;P:LongInt):LongInt;
Var
 I:LongInt;
 C:Char;
Begin
 Result:=0;
 For I:=P to P+3 do Begin
  If I>Length(S)Then Begin JErr:=True;Exit;End;
  C:=S[I];
  If C in['0'..'9']Then Result:=Result*16+Ord(C)-48
  Else If C in['a'..'f']Then Result:=Result*16+Ord(C)-87
  Else If C in['A'..'F']Then Result:=Result*16+Ord(C)-55
  Else Begin JErr:=True;Exit;End;
 End;
End;

Function JStrLit:AnsiString;
Var
 B:TBuf;
 C:Char;
 U,U2:LongInt;
 Run:LongInt;
Begin
 BufClear(B);
 Inc(JPos);
 Run:=JPos;
 While True do Begin
  If JPos>Length(JSrc)Then Begin JErr:=True;Break;End;
  C:=JSrc[JPos];
  If(C='"')or(C='\')Then Begin
   If JPos>Run Then BufAdd(B,Copy(JSrc,Run,JPos-Run));
   If C='"' Then Begin Inc(JPos);Break;End;
   Inc(JPos);
   If JPos>Length(JSrc)Then Begin JErr:=True;Break;End;
   C:=JSrc[JPos];
   Case C of
    'n':BufAdd(B,#10);
    't':BufAdd(B,#9);
    'r':BufAdd(B,#13);
    'b':BufAdd(B,#8);
    'f':BufAdd(B,#12);
    'u':Begin
         U:=HexVal(JSrc,JPos+1);
         Inc(JPos,4);
         If(U>=$D800)and(U<$DC00)and(Copy(JSrc,JPos+1,2)='\u')Then Begin
          U2:=HexVal(JSrc,JPos+3);
          If(U2>=$DC00)and(U2<$E000)Then Begin
           U:=$10000+((U-$D800)shl 10)+(U2-$DC00);
           Inc(JPos,6);
          End;
         End;
         BufAdd(B,Utf8Enc(U));
        End;
    Else BufAdd(B,C);
   End;
   Inc(JPos);
   Run:=JPos;
  End
  Else Inc(JPos);
  If JErr Then Break;
 End;
 JStrLit:=BufStr(B);
End;

Function JVal(Depth:LongInt):LongInt;
Var
 C:Char;
 K,Q:LongInt;
 Key:AnsiString;
Begin
 Result:=-1;
 JSkip;
 If(JPos>Length(JSrc))or(Depth>200)Then Begin JErr:=True;Exit;End;
 C:=JSrc[JPos];
 If C='{' Then Begin
  Result:=JNew(JK_OBJ);
  Inc(JPos);JSkip;
  If(JPos<=Length(JSrc))and(JSrc[JPos]='}')Then Begin Inc(JPos);Exit;End;
  Repeat
   JSkip;
   If(JPos>Length(JSrc))or(JSrc[JPos]<>'"')Then Begin JErr:=True;Exit;End;
   Key:=JStrLit;
   If JErr Then Exit;
   JSkip;
   If(JPos>Length(JSrc))or(JSrc[JPos]<>':')Then Begin JErr:=True;Exit;End;
   Inc(JPos);
   K:=JVal(Depth+1);
   If JErr Then Exit;
   JP[K].Key:=Key;
   JAppend(Result,K);
   JSkip;
   If JPos>Length(JSrc)Then Begin JErr:=True;Exit;End;
   If JSrc[JPos]=',' Then Inc(JPos)
   Else If JSrc[JPos]='}' Then Begin Inc(JPos);Exit;End
   Else Begin JErr:=True;Exit;End;
  Until False;
 End
 Else If C='[' Then Begin
  Result:=JNew(JK_ARR);
  Inc(JPos);JSkip;
  If(JPos<=Length(JSrc))and(JSrc[JPos]=']')Then Begin Inc(JPos);Exit;End;
  Repeat
   K:=JVal(Depth+1);
   If JErr Then Exit;
   JAppend(Result,K);
   JSkip;
   If JPos>Length(JSrc)Then Begin JErr:=True;Exit;End;
   If JSrc[JPos]=',' Then Inc(JPos)
   Else If JSrc[JPos]=']' Then Begin Inc(JPos);Exit;End
   Else Begin JErr:=True;Exit;End;
  Until False;
 End
 Else If C='"' Then Begin
  Key:=JStrLit;
  Result:=JNew(JK_STR);
  JP[Result].S:=Key;
 End
 Else If Copy(JSrc,JPos,4)='true' Then Begin
  Result:=JNew(JK_BOOL);JP[Result].S:='true';Inc(JPos,4);
 End
 Else If Copy(JSrc,JPos,5)='false' Then Begin
  Result:=JNew(JK_BOOL);JP[Result].S:='false';Inc(JPos,5);
 End
 Else If Copy(JSrc,JPos,4)='null' Then Begin
  Result:=JNew(JK_NULL);Inc(JPos,4);
 End
 Else If C in['-','0'..'9']Then Begin
  Q:=JPos;
  While(JPos<=Length(JSrc))and(JSrc[JPos]in['-','+','.','e','E','0'..'9'])do Inc(JPos);
  Result:=JNew(JK_NUM);
  JP[Result].S:=Copy(JSrc,Q,JPos-Q);
 End
 Else JErr:=True;
End;

{ analyse S ; renvoie l'indice de la racine ou -1 }
Function JParse(Const S:AnsiString):LongInt;
Begin
 JSrc:=S;JPos:=1;JErr:=False;
 Result:=JVal(0);
 If JErr Then Result:=-1;
End;

Function JGet(O:LongInt;Const Key:AnsiString):LongInt;
Var
 C:LongInt;
Begin
 JGet:=-1;
 If(O<0)or(JP[O].Kind<>JK_OBJ)Then Exit;
 C:=JP[O].First;
 While C>=0 do Begin
  If JP[C].Key=Key Then Begin JGet:=C;Exit;End;
  C:=JP[C].Next;
 End;
End;

{ chemin a points : "a.b.c" }
Function JPath(O:LongInt;Const Path:AnsiString):LongInt;
Var
 L:TSList;
 I:LongInt;
Begin
 SplitStr(Path,'.',L);
 JPath:=O;
 For I:=0 to L.N-1 do Begin
  JPath:=JGet(JPath,L.A[I]);
  If JPath<0 Then Exit;
 End;
End;

Function JAt(A,I:LongInt):LongInt;
Var
 C:LongInt;
Begin
 JAt:=-1;
 If(A<0)or not(JP[A].Kind in[JK_ARR,JK_OBJ])Then Exit;
 C:=JP[A].First;
 While(C>=0)and(I>0)do Begin C:=JP[C].Next;Dec(I);End;
 JAt:=C;
End;

Function JCnt(A:LongInt):LongInt;
Begin
 If A<0 Then JCnt:=0 Else JCnt:=JP[A].Cnt;
End;

Function JTxt(N:LongInt):AnsiString;
Begin
 If N<0 Then JTxt:='' Else If JP[N].Kind in[JK_STR,JK_NUM,JK_BOOL]Then JTxt:=JP[N].S
  Else JTxt:='';
End;

Function JS(O:LongInt;Const Path:AnsiString):AnsiString;
Begin
 JS:=JTxt(JPath(O,Path));
End;

Function JI(O:LongInt;Const Path:AnsiString):Int64;
Var
 N:LongInt;
 D:Double;
 Code:LongInt;
 V:Int64;
Begin
 N:=JPath(O,Path);
 JI:=0;
 If(N<0)or(JP[N].Kind<>JK_NUM)Then Exit;
 Val(JP[N].S,V,Code);
 If Code=0 Then JI:=V
 Else Begin
  Val(JP[N].S,D,Code);
  If Code=0 Then JI:=Trunc(D);
 End;
End;

Function JB(O:LongInt;Const Path:AnsiString):Boolean;
Begin
 JB:=JS(O,Path)='true';
End;

Function JEsc(Const S:AnsiString):AnsiString;
Const
 Hex:AnsiString='0123456789abcdef';
Var
 I:LongInt;
 B:TBuf;
 C:Char;
Begin
 BufClear(B);
 For I:=1 to Length(S)do Begin
  C:=S[I];
  Case C of
   '"':BufAdd(B,'\"');
   '\':BufAdd(B,'\\');
   #10:BufAdd(B,'\n');
   #13:BufAdd(B,'\r');
   #9:BufAdd(B,'\t');
   #0..#8,#11,#12,#14..#31:BufAdd(B,'\u00'+Hex[(Ord(C)shr 4)+1]+Hex[(Ord(C)and 15)+1]);
   Else BufAdd(B,C);
  End;
 End;
 JEsc:=BufStr(B);
End;

Function JQ(Const S:AnsiString):AnsiString;
Begin
 JQ:='"'+JEsc(S)+'"';
End;

Function JBool(B:Boolean):AnsiString;
Begin
 If B Then JBool:='true' Else JBool:='false';
End;

Procedure JDump(N:LongInt;Ind:LongInt;Var B:TBuf);
Var
 C:LongInt;
 Pad:AnsiString;
Begin
 If N<0 Then Begin BufAdd(B,'null');Exit;End;
 Case JP[N].Kind of
  JK_NULL:BufAdd(B,'null');
  JK_BOOL,JK_NUM:BufAdd(B,JP[N].S);
  JK_STR:BufAdd(B,JQ(JP[N].S));
  JK_ARR,JK_OBJ:Begin
   If JP[N].Cnt=0 Then Begin
    If JP[N].Kind=JK_ARR Then BufAdd(B,'[]') Else BufAdd(B,'{}');
    Exit;
   End;
   Pad:=StringOfChar(' ',(Ind+1)*2);
   If JP[N].Kind=JK_ARR Then BufAdd(B,'[') Else BufAdd(B,'{');
   C:=JP[N].First;
   While C>=0 do Begin
    BufAdd(B,#10+Pad);
    If JP[N].Kind=JK_OBJ Then BufAdd(B,JQ(JP[C].Key)+': ');
    JDump(C,Ind+1,B);
    C:=JP[C].Next;
    If C>=0 Then BufAdd(B,',');
   End;
   BufAdd(B,#10+StringOfChar(' ',Ind*2));
   If JP[N].Kind=JK_ARR Then BufAdd(B,']') Else BufAdd(B,'}');
  End;
 End;
End;

Procedure JPrint(N:LongInt);
Var
 B:TBuf;
Begin
 BufClear(B);
 JDump(N,0,B);
 WriteLn(BufStr(B));
End;

{ ------------------------------------------------------------------ }
{ SHA-256, SHA-1 et base64                                            }
{ ------------------------------------------------------------------ }

Const
 K256:Array[0..63]of LongWord=(
  $428a2f98,$71374491,$b5c0fbcf,$e9b5dba5,$3956c25b,$59f111f1,$923f82a4,$ab1c5ed5,
  $d807aa98,$12835b01,$243185be,$550c7dc3,$72be5d74,$80deb1fe,$9bdc06a7,$c19bf174,
  $e49b69c1,$efbe4786,$0fc19dc6,$240ca1cc,$2de92c6f,$4a7484aa,$5cb0a9dc,$76f988da,
  $983e5152,$a831c66d,$b00327c8,$bf597fc7,$c6e00bf3,$d5a79147,$06ca6351,$14292967,
  $27b70a85,$2e1b2138,$4d2c6dfc,$53380d13,$650a7354,$766a0abb,$81c2c92e,$92722c85,
  $a2bfe8a1,$a81a664b,$c24b8b70,$c76c51a3,$d192e819,$d6990624,$f40e3585,$106aa070,
  $19a4c116,$1e376c08,$2748774c,$34b0bcb5,$391c0cb3,$4ed8aa4a,$5b9cca4f,$682e6ff3,
  $748f82ee,$78a5636f,$84c87814,$8cc70208,$90befffa,$a4506ceb,$bef9a3f7,$c67178f2);

Type
 THash = Record
  H:Array[0..7]of LongWord;
  Buf:Array[0..63]of Byte;
  BufLen:LongInt;
  Total:Int64;
  Is1:Boolean;
 End;

Function Ror32(X:LongWord;N:Byte):LongWord;Inline;
Begin
 Ror32:=(X shr N)or(X shl(32-N));
End;

Function Rol32(X:LongWord;N:Byte):LongWord;Inline;
Begin
 Rol32:=(X shl N)or(X shr(32-N));
End;

Procedure HashInit(Var C:THash;Sha1:Boolean);
Begin
 C.BufLen:=0;C.Total:=0;C.Is1:=Sha1;
 If Sha1 Then Begin
  C.H[0]:=$67452301;C.H[1]:=$EFCDAB89;C.H[2]:=$98BADCFE;C.H[3]:=$10325476;
  C.H[4]:=$C3D2E1F0;
 End
 Else Begin
  C.H[0]:=$6a09e667;C.H[1]:=$bb67ae85;C.H[2]:=$3c6ef372;C.H[3]:=$a54ff53a;
  C.H[4]:=$510e527f;C.H[5]:=$9b05688c;C.H[6]:=$1f83d9ab;C.H[7]:=$5be0cd19;
 End;
End;

Procedure HashBlock(Var C:THash);
Var
 W:Array[0..79]of LongWord;
 A,B,Cc,D,E,F,G,H,T1,T2,S0,S1,K,Tmp:LongWord;
 I:LongInt;
Begin
 For I:=0 to 15 do
  W[I]:=(LongWord(C.Buf[I*4])shl 24)or(LongWord(C.Buf[I*4+1])shl 16)or
        (LongWord(C.Buf[I*4+2])shl 8)or LongWord(C.Buf[I*4+3]);
 If C.Is1 Then Begin
  For I:=16 to 79 do W[I]:=Rol32(W[I-3]xor W[I-8]xor W[I-14]xor W[I-16],1);
  A:=C.H[0];B:=C.H[1];Cc:=C.H[2];D:=C.H[3];E:=C.H[4];
  For I:=0 to 79 do Begin
   If I<20 Then Begin F:=(B and Cc)or((not B)and D);K:=$5A827999;End
   Else If I<40 Then Begin F:=B xor Cc xor D;K:=$6ED9EBA1;End
   Else If I<60 Then Begin F:=(B and Cc)or(B and D)or(Cc and D);K:=$8F1BBCDC;End
   Else Begin F:=B xor Cc xor D;K:=$CA62C1D6;End;
   Tmp:=Rol32(A,5)+F+E+K+W[I];
   E:=D;D:=Cc;Cc:=Rol32(B,30);B:=A;A:=Tmp;
  End;
  C.H[0]:=C.H[0]+A;C.H[1]:=C.H[1]+B;C.H[2]:=C.H[2]+Cc;C.H[3]:=C.H[3]+D;
  C.H[4]:=C.H[4]+E;
 End
 Else Begin
  For I:=16 to 63 do Begin
   S0:=Ror32(W[I-15],7)xor Ror32(W[I-15],18)xor(W[I-15]shr 3);
   S1:=Ror32(W[I-2],17)xor Ror32(W[I-2],19)xor(W[I-2]shr 10);
   W[I]:=W[I-16]+S0+W[I-7]+S1;
  End;
  A:=C.H[0];B:=C.H[1];Cc:=C.H[2];D:=C.H[3];
  E:=C.H[4];F:=C.H[5];G:=C.H[6];H:=C.H[7];
  For I:=0 to 63 do Begin
   S1:=Ror32(E,6)xor Ror32(E,11)xor Ror32(E,25);
   T1:=H+S1+((E and F)xor((not E)and G))+K256[I]+W[I];
   S0:=Ror32(A,2)xor Ror32(A,13)xor Ror32(A,22);
   T2:=S0+((A and B)xor(A and Cc)xor(B and Cc));
   H:=G;G:=F;F:=E;E:=D+T1;D:=Cc;Cc:=B;B:=A;A:=T1+T2;
  End;
  C.H[0]:=C.H[0]+A;C.H[1]:=C.H[1]+B;C.H[2]:=C.H[2]+Cc;C.H[3]:=C.H[3]+D;
  C.H[4]:=C.H[4]+E;C.H[5]:=C.H[5]+F;C.H[6]:=C.H[6]+G;C.H[7]:=C.H[7]+H;
 End;
End;

Procedure HashUpdate(Var C:THash;P:PByte;Len:LongInt);
Var
 N:LongInt;
Begin
 Inc(C.Total,Len);
 While Len>0 do Begin
  N:=64-C.BufLen;
  If N>Len Then N:=Len;
  Move(P^,C.Buf[C.BufLen],N);
  Inc(C.BufLen,N);Inc(P,N);Dec(Len,N);
  If C.BufLen=64 Then Begin HashBlock(C);C.BufLen:=0;End;
 End;
End;

Function HashFinal(Var C:THash):AnsiString;
Const
 Hex:AnsiString='0123456789abcdef';
Var
 Bits:Int64;
 I,Nw:LongInt;
 Pad:Byte;
 Z:Array[0..7]of Byte;
 B:Byte;
Begin
 Bits:=C.Total*8;
 Pad:=$80;
 HashUpdate(C,@Pad,1);
 Pad:=0;
 While C.BufLen<>56 do HashUpdate(C,@Pad,1);
 For I:=0 to 7 do Z[I]:=Byte((Bits shr((7-I)*8))and $FF);
 HashUpdate(C,@Z[0],8);
 If C.Is1 Then Nw:=5 Else Nw:=8;
 Result:='';
 For I:=0 to Nw-1 do
  For B:=0 to 3 do
   Result:=Result+Hex[((C.H[I]shr(24-B*8))shr 4)and 15+1]+
     Hex[((C.H[I]shr(24-B*8)))and 15+1];
End;

{ condense sha256 d'un fichier (portion Ofs..Ofs+Len), '' si erreur }
Function HashFile(Const Path:AnsiString;Sha1Blob:Boolean):AnsiString;
Var
 F:File;
 C:THash;
 Buf:Pointer;
 N:LongInt;
 Sz:Int64;
 Hd:AnsiString;
Begin
 HashFile:='';
 Assign(F,Path);
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0 Then Exit;
 Sz:=FileSize(F);
 HashInit(C,Sha1Blob);
 If Sha1Blob Then Begin
  Hd:='blob '+IStr(Sz)+#0;
  HashUpdate(C,PByte(@Hd[1]),Length(Hd));
 End;
 GetMem(Buf,1048576);
 Repeat
  N:=0;
  {$I-}BlockRead(F,Buf^,1048576,N);{$I+}
  If IOResult<>0 Then Begin FreeMem(Buf);Close(F);Exit;End;
  If N>0 Then HashUpdate(C,PByte(Buf),N);
 Until N=0;
 FreeMem(Buf);
 Close(F);
 If IOResult<>0 Then;
 HashFile:=HashFinal(C);
End;

Function HashStr(Const S:AnsiString;Sha1:Boolean):AnsiString;
Var
 C:THash;
Begin
 HashInit(C,Sha1);
 If S<>'' Then HashUpdate(C,PByte(@S[1]),Length(S));
 HashStr:=HashFinal(C);
End;

Const
 B64:AnsiString='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

Procedure B64Add(Var B:TBuf;Const S:AnsiString);
Var
 I,N:LongInt;
 X:LongWord;
 O:AnsiString;
Begin
 N:=Length(S);
 SetLength(O,((N+2)div 3)*4);
 I:=1;
 N:=0;
 While I+2<=Length(S)do Begin
  X:=(LongWord(Ord(S[I]))shl 16)or(LongWord(Ord(S[I+1]))shl 8)or Ord(S[I+2]);
  O[N+1]:=B64[(X shr 18)+1];O[N+2]:=B64[((X shr 12)and 63)+1];
  O[N+3]:=B64[((X shr 6)and 63)+1];O[N+4]:=B64[(X and 63)+1];
  Inc(N,4);Inc(I,3);
 End;
 If Length(S)-I+1=1 Then Begin
  X:=LongWord(Ord(S[I]))shl 16;
  O[N+1]:=B64[(X shr 18)+1];O[N+2]:=B64[((X shr 12)and 63)+1];
  O[N+3]:='=';O[N+4]:='=';
 End
 Else If Length(S)-I+1=2 Then Begin
  X:=(LongWord(Ord(S[I]))shl 16)or(LongWord(Ord(S[I+1]))shl 8);
  O[N+1]:=B64[(X shr 18)+1];O[N+2]:=B64[((X shr 12)and 63)+1];
  O[N+3]:=B64[((X shr 6)and 63)+1];O[N+4]:='=';
 End;
 BufAdd(B,O);
End;

Function B64Str(Const S:AnsiString):AnsiString;
Var
 B:TBuf;
Begin
 BufClear(B);
 B64Add(B,S);
 B64Str:=BufStr(B);
End;

Function TrimRight_(Const S:AnsiString):AnsiString;
Var
 B:LongInt;
Begin
 B:=Length(S);
 While(B>0)and(S[B]=' ')do Dec(B);
 TrimRight_:=Copy(S,1,B);
End;

Function IfThen_(C:Boolean;Const A,B:AnsiString):AnsiString;
Begin
 If C Then IfThen_:=A Else IfThen_:=B;
End;

{ ------------------------------------------------------------------ }
{ Couche HTTP : WinInet (Windows) ou curl (autres systemes)           }
{ ------------------------------------------------------------------ }

Type
 THttpReq = Record
  Method,Url,Token,Headers:AnsiString;
  BodyStr:AnsiString;
  BodyFile:AnsiString;
  BodyOfs,BodyLen:Int64;
  OutFile:AnsiString;
  ResumeFrom:Int64;
  Follow,StopAtLinked:Boolean;
  ProgLabel:AnsiString;
  ShowProg:Boolean;
  Status:LongInt;
  RespHeaders,RespBody,Err:AnsiString;
  Got,Total:Int64;
 End;

Var
 Endpoint:AnsiString;
 ProgLast:LongInt;

Procedure ReqInit(Var R:THttpReq;Const Method,Url,Token:AnsiString);
Begin
 R.Method:=Method;R.Url:=Url;R.Token:=Token;R.Headers:='';
 R.BodyStr:='';R.BodyFile:='';R.BodyOfs:=0;R.BodyLen:=0;
 R.OutFile:='';R.ResumeFrom:=0;
 R.Follow:=True;R.StopAtLinked:=False;
 R.ProgLabel:='';R.ShowProg:=False;
 R.Status:=0;R.RespHeaders:='';R.RespBody:='';R.Err:='';
 R.Got:=0;R.Total:=-1;
End;

{ derniere reponse d'un en-tete HTTP (curl ajoute plusieurs blocs) }
Function LastHeaderBlock(Const S:AnsiString):AnsiString;
Var
 I,B:LongInt;
Begin
 B:=1;
 I:=1;
 While I<=Length(S)do Begin
  If(Copy(S,I,5)='HTTP/')and((I=1)or(S[I-1]=#10))Then B:=I;
  Inc(I);
 End;
 LastHeaderBlock:=Copy(S,B,Length(S));
End;

Function HeaderGet(Const H,Name:AnsiString):AnsiString;
Var
 L:TSList;
 I,P:LongInt;
 Ln,Nm:AnsiString;
Begin
 HeaderGet:='';
 Nm:=LoStr(Name)+':';
 SplitStr(ReplaceAll(H,#13,''),#10,L);
 For I:=0 to L.N-1 do Begin
  Ln:=L.A[I];
  If StartsWith(LoStr(Ln),Nm)Then Begin
   P:=Pos(':',Ln);
   HeaderGet:=TrimStr(Copy(Ln,P+1,Length(Ln)));
   Exit;
  End;
 End;
End;

Function StatusFromHeaders(Const H:AnsiString):LongInt;
Var
 P:LongInt;
 T:AnsiString;
Begin
 T:=LastHeaderBlock(H);
 P:=Pos(' ',T);
 If P=0 Then Begin StatusFromHeaders:=0;Exit;End;
 StatusFromHeaders:=ToInt(Copy(T,P+1,3),0);
End;

Function BuildHeaders(Var R:THttpReq):AnsiString;
Begin
 Result:='Accept: */*'#13#10'Accept-Encoding: identity'#13#10;
 If R.Token<>'' Then Result:=Result+'Authorization: Bearer '+R.Token+#13#10;
 If R.ResumeFrom>0 Then Result:=Result+'Range: bytes='+IStr(R.ResumeFrom)+'-'#13#10;
 Result:=Result+R.Headers;
End;

Procedure ShowProgress(Var R:THttpReq);
Var
 Pc,Bar,I:LongInt;
 S:AnsiString;
Begin
 If not R.ShowProg Then Exit;
 If R.Total>0 Then Begin
  Pc:=(R.Got*100)div R.Total;
  If(Pc=ProgLast)and(R.Got<R.Total)Then Exit;
  ProgLast:=Pc;
  Bar:=Pc div 5;
  S:='';
  For I:=1 to 20 do If I<=Bar Then S:=S+'#' Else S:=S+'.';
  Write(StdErr,#13,R.ProgLabel,' [',S,'] ',Pc:3,'% ',HumanSize(R.Got),'/',
    HumanSize(R.Total),'      ');
 End
 Else Begin
  Pc:=R.Got div 1048576;
  If Pc=ProgLast Then Exit;
  ProgLast:=Pc;
  Write(StdErr,#13,R.ProgLabel,' ',HumanSize(R.Got),'      ');
 End;
End;

Procedure ProgressEnd(Var R:THttpReq);
Begin
 If R.ShowProg and(R.Got>0)Then WriteLn(StdErr);
End;

{$IFDEF WINDOWS}
Type
 TInetBuf = Record
  dwStructSize:LongWord;
  Next:Pointer;
  lpcszHeader:PChar;
  dwHeadersLength,dwHeadersTotal:LongWord;
  lpvBuffer:Pointer;
  dwBufferLength,dwBufferTotal,dwOffsetLow,dwOffsetHigh:LongWord;
 End;

Function InternetOpenA(Agent:PChar;Access:LongWord;Proxy,
  Bypass:PChar;Flags:LongWord):Pointer;
 stdcall;external 'wininet.dll' name 'InternetOpenA';
Function InternetConnectA(H:Pointer;Host:PChar;Port:LongWord;User,
  Pass:PChar;Service,Flags:LongWord;Ctx:PtrUInt):Pointer;
 stdcall;external 'wininet.dll' name 'InternetConnectA';
Function HttpOpenRequestA(H:Pointer;Verb,Obj,Ver,Ref:PChar;Accept:Pointer;
  Flags:LongWord;Ctx:PtrUInt):Pointer;
 stdcall;external 'wininet.dll' name 'HttpOpenRequestA';
Function HttpSendRequestA(H:Pointer;Hdr:PChar;HdrLen:LongWord;Opt:Pointer;
  OptLen:LongWord):LongInt;
 stdcall;external 'wininet.dll' name 'HttpSendRequestA';
Function HttpSendRequestExA(H:Pointer;InBuf,OutBuf:Pointer;Flags:LongWord;
  Ctx:PtrUInt):LongInt;
 stdcall;external 'wininet.dll' name 'HttpSendRequestExA';
Function InternetWriteFile(H:Pointer;Buf:Pointer;N:LongWord;Var Written:LongWord):LongInt;
 stdcall;external 'wininet.dll' name 'InternetWriteFile';
Function HttpEndRequestA(H:Pointer;OutBuf:Pointer;Flags:LongWord;Ctx:PtrUInt):LongInt;
 stdcall;external 'wininet.dll' name 'HttpEndRequestA';
Function InternetReadFile(H:Pointer;Buf:Pointer;ToRead:LongWord;Var
  Got:LongWord):LongInt;
 stdcall;external 'wininet.dll' name 'InternetReadFile';
Function InternetCloseHandle(H:Pointer):LongInt;
 stdcall;external 'wininet.dll' name 'InternetCloseHandle';
Function HttpQueryInfoA(H:Pointer;InfoLevel:LongWord;Buf:Pointer;Var
  BufLen:LongWord;Index:Pointer):LongInt;
 stdcall;external 'wininet.dll' name 'HttpQueryInfoA';
Function InternetSetOptionA(H:Pointer;Opt:LongWord;Buf:Pointer;BufLen:LongWord):LongInt;
 stdcall;external 'wininet.dll' name 'InternetSetOptionA';

Procedure HttpOnce(Var R:THttpReq);
Var
 Sc,Host,Path,Hdr,HB:AnsiString;
 Port:LongInt;
 Sess,Conn,Req:Pointer;
 Flags,Tmo,L,Gt:LongWord;
 IB:TInetBuf;
 Buf:Pointer;
 F,BF:File;
 N,Want:LongInt;
 Left,Ofs:Int64;
 B:TBuf;
 OpenOut,UseEx,Ok:Boolean;
 Cl:AnsiString;
Begin
 R.Status:=0;R.RespHeaders:='';R.RespBody:='';R.Err:='';R.Got:=0;R.Total:=-1;
 SplitUrl(R.Url,Sc,Host,Port,Path);
 Sess:=InternetOpenA(UserAgent,0,Nil,Nil,0);
 If Sess=Nil Then Begin R.Err:='cannot initialize WinInet';Exit;End;
 Tmo:=60000;
 InternetSetOptionA(Sess,2,@Tmo,4);
 InternetSetOptionA(Sess,5,@Tmo,4);
 InternetSetOptionA(Sess,6,@Tmo,4);
 Conn:=InternetConnectA(Sess,PChar(Host),Port,Nil,Nil,3,0,0);
 If Conn=Nil Then Begin
  R.Err:='cannot connect to '+Host;
  InternetCloseHandle(Sess);Exit;
 End;
 Flags:=$80000000 or $04000000 or $00200000 or $00000200;
 If Sc='https' Then Flags:=Flags or $00800000;
 Req:=HttpOpenRequestA(Conn,PChar(R.Method),PChar(Path),Nil,Nil,Nil,Flags,0);
 If Req=Nil Then Begin
  R.Err:='cannot open request '+R.Url;
  InternetCloseHandle(Conn);InternetCloseHandle(Sess);Exit;
 End;
 Hdr:=BuildHeaders(R);
 GetMem(Buf,65536);
 UseEx:=(R.BodyFile<>'')or(Length(R.BodyStr)>0);
 Ok:=False;
 If not UseEx Then
  Ok:=HttpSendRequestA(Req,PChar(Hdr),Length(Hdr),Nil,0)<>0
 Else Begin
  FillChar(IB,SizeOf(IB),0);
  IB.dwStructSize:=SizeOf(IB);
  IB.lpcszHeader:=PChar(Hdr);
  IB.dwHeadersLength:=Length(Hdr);
  If R.BodyFile<>'' Then IB.dwBufferTotal:=LongWord(R.BodyLen)
                    Else IB.dwBufferTotal:=Length(R.BodyStr);
  If HttpSendRequestExA(Req,@IB,Nil,8,0)<>0 Then Begin
   Ok:=True;
   If R.BodyFile='' Then Begin
    Ofs:=1;
    While Ok and(Ofs<=Length(R.BodyStr))do Begin
     Want:=Length(R.BodyStr)-Ofs+1;
     If Want>65536 Then Want:=65536;
     Gt:=0;
     If InternetWriteFile(Req,@R.BodyStr[Ofs],Want,Gt)=0 Then Ok:=False;
     Inc(Ofs,Want);
    End;
   End
   Else Begin
    Assign(BF,R.BodyFile);
    {$I-}Reset(BF,1);{$I+}
    If IOResult<>0 Then Ok:=False
    Else Begin
     Seek(BF,R.BodyOfs);
     Left:=R.BodyLen;
     R.Total:=R.BodyLen;
     While Ok and(Left>0)do Begin
      Want:=65536;
      If Left<Want Then Want:=Left;
      N:=0;
      BlockRead(BF,Buf^,Want,N);
      If N<=0 Then Begin Ok:=False;Break;End;
      Gt:=0;
      If InternetWriteFile(Req,Buf,N,Gt)=0 Then Ok:=False;
      Dec(Left,N);Inc(R.Got,N);
      ShowProgress(R);
     End;
     Close(BF);
     ProgressEnd(R);
    End;
   End;
   If Ok Then Ok:=HttpEndRequestA(Req,Nil,0,0)<>0
   Else HttpEndRequestA(Req,Nil,0,0);
  End;
 End;
 If not Ok Then Begin
  R.Err:='request failed: '+R.Method+' '+R.Url;
  FreeMem(Buf);
  InternetCloseHandle(Req);InternetCloseHandle(Conn);InternetCloseHandle(Sess);
  Exit;
 End;
 L:=0;Tmo:=0;
 L:=4;
 If HttpQueryInfoA(Req,19 or $20000000,@Tmo,L,Nil)<>0 Then R.Status:=Tmo;
 SetLength(HB,32768);
 L:=32768;
 If HttpQueryInfoA(Req,22,@HB[1],L,Nil)<>0 Then Begin
  SetLength(HB,L);
  R.RespHeaders:=HB;
 End;
 Cl:=HeaderGet(R.RespHeaders,'content-length');
 R.Got:=0;R.Total:=-1;
 If Cl<>'' Then R.Total:=ToInt(Cl,-1);
 If R.Method='HEAD' Then Begin
  FreeMem(Buf);
  InternetCloseHandle(Req);InternetCloseHandle(Conn);InternetCloseHandle(Sess);
  Exit;
 End;
 OpenOut:=(R.OutFile<>'')and(R.Status>=200)and(R.Status<300);
 If OpenOut Then Begin
  MkDirs(ParentDir(R.OutFile));
  Assign(F,R.OutFile);
  If(R.Status=206)and(R.ResumeFrom>0)Then Begin
   {$I-}Reset(F,1);{$I+}
   If IOResult<>0 Then OpenOut:=False Else Begin
    Seek(F,R.ResumeFrom);
    If R.Total>0 Then R.Total:=R.Total+R.ResumeFrom;
    R.Got:=R.ResumeFrom;
   End;
  End
  Else Begin
   {$I-}Rewrite(F,1);{$I+}
   If IOResult<>0 Then OpenOut:=False;
  End;
  If not OpenOut Then R.Err:='cannot write '+R.OutFile;
 End;
 BufClear(B);
 ProgLast:=-1;
 While R.Err='' do Begin
  Gt:=0;
  If InternetReadFile(Req,Buf,65536,Gt)=0 Then Begin
   If R.Status<>0 Then R.Err:='network read error';
   Break;
  End;
  If Gt=0 Then Break;
  If OpenOut Then Begin
   BlockWrite(F,Buf^,Gt);
   Inc(R.Got,Gt);
   ShowProgress(R);
  End
  Else Begin
   SetLength(HB,Gt);
   Move(Buf^,HB[1],Gt);
   BufAdd(B,HB);
  End;
 End;
 If OpenOut Then Begin
  Close(F);
  If IOResult<>0 Then;
  ProgressEnd(R);
 End
 Else R.RespBody:=BufStr(B);
 FreeMem(Buf);
 InternetCloseHandle(Req);InternetCloseHandle(Conn);InternetCloseHandle(Sess);
End;
{$ELSE}
Function CfgQ(Const S:AnsiString):AnsiString;
Begin
 CfgQ:='"'+ReplaceAll(ReplaceAll(ReplaceAll(S,'\','\\'),'"','\"'),#10,'\n')+'"';
End;

Function TempName(Const Tag:AnsiString):AnsiString;
Var
 D:AnsiString;
Begin
 D:=GetEnv('TMPDIR');
 If D='' Then D:='/tmp';
 TempName:=DropSlash(D)+'/hfpas'+IStr(Random(1000000000))+Tag;
End;

Procedure HttpOnce(Var R:THttpReq);
Var
 Curl,Cfg,HFile,OFile,BFile,Hdr:AnsiString;
 T:Text;
 L:TSList;
 I:LongInt;
 UseBody,TmpBody:Boolean;
 Sz:Int64;
 F,G:File;
 Buf:Pointer;
 N:LongInt;
 Dat:AnsiString;
 Code:Integer;
Begin
 R.Status:=0;R.RespHeaders:='';R.RespBody:='';R.Err:='';R.Got:=0;R.Total:=-1;
 Curl:=FSearch('curl',GetEnv('PATH'));
 If Curl='' Then Begin R.Err:='curl not found (needed on non-Windows systems)';Exit;End;
 Cfg:=TempName('.cfg');HFile:=TempName('.hdr');OFile:=TempName('.out');
 BFile:='';TmpBody:=False;
 UseBody:=(R.BodyFile<>'')or(Length(R.BodyStr)>0);
 If UseBody Then Begin
  If R.BodyFile='' Then Begin
   BFile:=TempName('.body');TmpBody:=True;
   WriteAll(BFile,R.BodyStr);
  End
  Else If(R.BodyOfs=0)and(R.BodyLen=FileSizeOf(R.BodyFile))Then BFile:=R.BodyFile
  Else Begin
   BFile:=TempName('.body');TmpBody:=True;
   Assign(F,R.BodyFile);Reset(F,1);Seek(F,R.BodyOfs);
   Assign(G,BFile);Rewrite(G,1);
   GetMem(Buf,262144);
   Sz:=R.BodyLen;
   While Sz>0 do Begin
    N:=262144;If Sz<N Then N:=Sz;
    BlockRead(F,Buf^,N,N);
    If N<=0 Then Break;
    BlockWrite(G,Buf^,N);
    Dec(Sz,N);
   End;
   FreeMem(Buf);Close(F);Close(G);
  End;
 End;
 Assign(T,Cfg);
 Rewrite(T);
 WriteLn(T,'silent');
 WriteLn(T,'globoff');
 WriteLn(T,'url = ',CfgQ(R.Url));
 If R.Method='HEAD' Then WriteLn(T,'head')
 Else WriteLn(T,'request = ',CfgQ(R.Method));
 WriteLn(T,'dump-header = ',CfgQ(HFile));
 WriteLn(T,'output = ',CfgQ(OFile));
 WriteLn(T,'connect-timeout = 30');
 Hdr:=BuildHeaders(R);
 SplitStr(ReplaceAll(Hdr,#13,''),#10,L);
 For I:=0 to L.N-1 do If L.A[I]<>'' Then WriteLn(T,'header = ',CfgQ(L.A[I]));
 If UseBody Then Begin
  WriteLn(T,'header = "Expect:"');
  If Pos('content-type',LoStr(R.Headers))=0 Then WriteLn(T,'header = "Content-Type:"');
  WriteLn(T,'data-binary = ',CfgQ('@'+BFile));
 End;
 Close(T);
 DosError:=0;
 SwapVectors;
 Exec(Curl,'-K '+Cfg);
 SwapVectors;
 If DosError<>0 Then R.Err:='cannot run curl'
 Else If DosExitCode<>0 Then R.Err:='curl failed with exit code '+IStr(DosExitCode);
 If ReadAll(HFile,Dat)Then Begin
  R.RespHeaders:=LastHeaderBlock(Dat);
  R.Status:=StatusFromHeaders(R.RespHeaders);
 End;
 If R.Err='' Then Begin
  Dat:=HeaderGet(R.RespHeaders,'content-length');
  If Dat<>'' Then R.Total:=ToInt(Dat,-1);
  If R.Method<>'HEAD' Then Begin
   If(R.OutFile<>'')and(R.Status>=200)and(R.Status<300)Then Begin
    MkDirs(ParentDir(R.OutFile));
    If(R.Status=206)and(R.ResumeFrom>0)Then Begin
     { ajoute le complement au fichier partiel }
     Assign(F,OFile);Reset(F,1);
     Assign(G,R.OutFile);Reset(G,1);Seek(G,R.ResumeFrom);
     GetMem(Buf,262144);
     Repeat
      N:=0;BlockRead(F,Buf^,262144,N);
      If N>0 Then BlockWrite(G,Buf^,N);
     Until N=0;
     FreeMem(Buf);Close(F);Close(G);
     DelFile(OFile);
     R.Got:=FileSizeOf(R.OutFile);
    End
    Else Begin
     MoveFile_(OFile,R.OutFile);
     R.Got:=FileSizeOf(R.OutFile);
    End;
   End
   Else Begin
    ReadAll(OFile,R.RespBody);
    DelFile(OFile);
   End;
  End;
 End;
 DelFile(Cfg);DelFile(HFile);
 If FileExists_(OFile)Then DelFile(OFile);
 If TmpBody Then DelFile(BFile);
End;
{$ENDIF}

{ requete avec redirections manuelles : le jeton n'est envoye qu'a l'hote d'origine }
Procedure HttpDo(Var R:THttpReq);
Var
 I:LongInt;
 Loc,Host0:AnsiString;
 Tok0:AnsiString;
Begin
 If GetEnv('HF_HUB_OFFLINE')='1' Then Begin
  R.Status:=0;
  R.Err:='offline mode is enabled (HF_HUB_OFFLINE=1)';
  Exit;
 End;
 Host0:=UrlHost(R.Url);
 Tok0:=R.Token;
 For I:=1 to 10 do Begin
  HttpOnce(R);
  If R.Err<>'' Then Exit;
  If(R.Status<>301)and(R.Status<>302)and(R.Status<>303)and(R.Status<>307)and(R.Status<>308)Then Exit;
  If not R.Follow Then Exit;
  If R.StopAtLinked and(HeaderGet(R.RespHeaders,'x-linked-etag')<>'')Then Exit;
  Loc:=HeaderGet(R.RespHeaders,'location');
  If Loc='' Then Exit;
  R.Url:=ResolveUrl(R.Url,Loc);
  If UrlHost(R.Url)<>Host0 Then R.Token:='' Else R.Token:=Tok0;
  If R.Status=303 Then Begin
   R.Method:='GET';R.BodyStr:='';R.BodyFile:='';
  End;
 End;
End;

{ ------------------------------------------------------------------ }
{ Langue de l'aide : francais par defaut, anglais si LANGUAGE=EN        }
{ ------------------------------------------------------------------ }

Type
 TTrPair = Record
  E,F:AnsiString;
 End;

Const
 NTr=243;
 TrTable:Array[0..NTr-1]of TTrPair=(
  (E:'A User Access Token generated from https://huggingface.co/settings/tokens.';F:'Jeton d''accès utilisateur généré sur https://huggingface.co/settings/tokens.'),
  (E:'The type of repository (model, dataset, or space). [default: model]';F:'Type de dépôt (model, dataset ou space). [défaut : model]'),
  (E:'Download files from the Hub.';F:'Télécharge des fichiers depuis le Hub.'),
  (E:'The ID of the repo (e.g. `username/repo-name`).';F:'Identifiant du dépôt (ex. : `utilisateur/nom-du-depot`).'),
  (E:'Files to download (e.g. `config.json`, `data/metadata.jsonl`).';F:'Fichiers à télécharger (ex. : `config.json`, `data/metadata.jsonl`).'),
  (E:'Git revision id which can be a branch name, a tag, or a commit hash.';F:'Révision Git : nom de branche, étiquette (tag) ou empreinte de commit.'),
  (E:'Glob patterns to include from files to download. eg: *.json';F:'Motifs glob des fichiers à inclure dans le téléchargement. ex. : *.json'),
  (E:'Glob patterns to exclude from files to download.';F:'Motifs glob des fichiers à exclure du téléchargement.'),
  (E:'Directory where to save files.';F:'Répertoire où enregistrer les fichiers.'),
  (E:'If set, the downloaded file will be placed under this directory.';F:'Si défini, les fichiers téléchargés sont placés dans ce répertoire.'),
  (E:'If True, the files will be downloaded even if they are already cached.';F:'Télécharge les fichiers même s''ils sont déjà dans le cache.'),
  (E:'If True, perform a dry run without actually downloading the file.';F:'Simulation : indique ce qui serait téléchargé sans rien télécharger.'),
  (E:'Disable progress bars and warnings; print only the returned path.';F:'Désactive les barres de progression et les avertissements ; affiche uniquement le chemin obtenu.'),
  (E:'Maximum number of workers to use for downloading files. Default is 8.';F:'Nombre maximal de téléchargements parallèles. Par défaut : 8 (ignoré par ce clone).'),
  (E:'The ID of the repo to upload to (e.g. `username/repo-name`).';F:'Identifiant du dépôt cible (ex. : `utilisateur/nom-du-depot`).'),
  (E:'Local path to the file or folder to upload. Defaults to the current directory.';F:'Chemin local du fichier ou du dossier à envoyer. Par défaut : le répertoire courant.'),
  (E:'Path of the file or folder in the repo. Defaults to the root of the repo.';F:'Chemin du fichier ou du dossier dans le dépôt. Par défaut : la racine du dépôt.'),
  (E:'An optional Git revision to push to. It can be a branch name or a PR reference.';F:'Révision Git cible (facultatif) : nom de branche ou référence de PR.'),
  (E:'Whether to create a private repo if repo doesn''t exist on the Hub.';F:'Crée un dépôt privé si le dépôt n''existe pas sur le Hub.'),
  (E:'Glob patterns to match files to upload.';F:'Motifs glob des fichiers à envoyer.'),
  (E:'Glob patterns to exclude from files to upload.';F:'Motifs glob des fichiers à exclure de l''envoi.'),
  (E:'Glob patterns for file to be deleted from the repo while committing.';F:'Motifs glob des fichiers à supprimer du dépôt pendant le commit.'),
  (E:'The summary / title / first line of the generated commit.';F:'Résumé / titre / première ligne du commit généré.'),
  (E:'The description of the generated commit.';F:'Description du commit généré.'),
  (E:'Whether to upload content as a new Pull Request.';F:'Envoie le contenu dans une nouvelle Pull Request.'),
  (E:'Not supported by this clone.';F:'Non pris en charge par ce clone.'),
  (E:'Login using a token from huggingface.co/settings/tokens.';F:'Se connecte avec un jeton obtenu sur huggingface.co/settings/tokens.'),
  (E:'Save to git credential helper (not supported by this clone).';F:'Enregistre dans l''assistant d''identifiants git (non pris en charge par ce clone).'),
  (E:'Logout from a specific token.';F:'Se déconnecte d''un jeton précis.'),
  (E:'Name of token to logout';F:'Nom du jeton dont il faut se déconnecter'),
  (E:'Find out which huggingface.co account you are logged in as.';F:'Indique avec quel compte huggingface.co vous êtes connecté.'),
  (E:'Output format (table or json).';F:'Format de sortie (table ou json).'),
  (E:'List all stored access tokens.';F:'Liste tous les jetons d''accès enregistrés.'),
  (E:'Switch between access tokens.';F:'Bascule entre les jetons d''accès.'),
  (E:'Name of the token to switch to';F:'Nom du jeton à activer'),
  (E:'Search query.';F:'Requête de recherche.'),
  (E:'Filter by author or organization.';F:'Filtre par auteur ou organisation.'),
  (E:'Filter by tags (e.g. ''text-classification''). Can be used multiple times.';F:'Filtre par étiquettes (ex. : ''text-classification''). Répétable.'),
  (E:'Sort key. One of downloads, likes, created_at, last_modified, trending_score.';F:'Critère de tri : downloads, likes, created_at, last_modified ou trending_score.'),
  (E:'Limit the number of results. [default: 10]';F:'Limite le nombre de résultats. [défaut : 10]'),
  (E:'Properties to expand in the response. Can be used multiple times.';F:'Propriétés à développer dans la réponse. Répétable.'),
  (E:'Output format: table or json. [default: table]';F:'Format de sortie : table ou json. [défaut : table]'),
  (E:'Print only IDs, one per line.';F:'Affiche uniquement les identifiants, un par ligne.'),
  (E:'List cached repositories or revisions.';F:'Liste les dépôts ou les révisions présents dans le cache.'),
  (E:'Cache directory to scan (defaults to Hugging Face cache).';F:'Répertoire de cache à analyser (par défaut : le cache Hugging Face).'),
  (E:'Include revisions in the output instead of aggregated repositories.';F:'Affiche les révisions au lieu des dépôts agrégés.'),
  (E:'Filter entries (e.g. ''size>1GB'', ''modified>1w''). Can be used multiple times.';F:'Filtre les entrées (ex. : ''size>1GB'', ''modified>1w''). Répétable.'),
  (E:'Print only IDs (repo IDs or revision hashes).';F:'Affiche uniquement les identifiants (dépôts ou empreintes de révisions).'),
  (E:'Remove cached repositories or revisions.';F:'Supprime des dépôts ou des révisions du cache.'),
  (E:'One or more repo IDs (e.g. model/bert-base-uncased) or revision hashes to delete.';F:'Un ou plusieurs identifiants de dépôts (ex. : model/bert-base-uncased) ou empreintes de révisions à supprimer.'),
  (E:'Skip confirmation prompt.';F:'Ne demande pas de confirmation.'),
  (E:'Preview deletions without removing anything.';F:'Affiche les suppressions prévues sans rien supprimer.'),
  (E:'Remove detached revisions from the cache.';F:'Supprime les révisions détachées (non référencées) du cache.'),
  (E:'Cache directory to use when verifying files from the cache.';F:'Répertoire de cache à utiliser pour vérifier les fichiers du cache.'),
  (E:'If set, verify files under this directory instead of the cache.';F:'Si défini, vérifie les fichiers de ce répertoire au lieu du cache.'),
  (E:'Fail if some files exist on the remote but are missing locally.';F:'Échoue si des fichiers du dépôt distant sont absents en local.'),
  (E:'Fail if some files exist locally but are not present on the remote revision.';F:'Échoue si des fichiers locaux n''existent pas dans la révision distante.'),
  (E:'Create a new repo on the Hub.';F:'Crée un nouveau dépôt sur le Hub.'),
  (E:'Hugging Face Spaces SDK type. Required when --repo-type is ''space''.';F:'Type de SDK Hugging Face Spaces. Obligatoire quand --repo-type vaut ''space''.'),
  (E:'Do not raise an error if repo already exists.';F:'Ne signale pas d''erreur si le dépôt existe déjà.'),
  (E:'Delete a repo from the Hub. This is an irreversible operation.';F:'Supprime un dépôt du Hub. Opération irréversible.'),
  (E:'If set to True, do not raise an error if repo does not exist.';F:'Ne signale pas d''erreur si le dépôt n''existe pas.'),
  (E:'The ID of the repo to move (e.g. `username/repo-name`).';F:'Identifiant du dépôt à déplacer (ex. : `utilisateur/nom-du-depot`).'),
  (E:'The new ID of the repo (e.g. `username/new-repo-name`).';F:'Nouvel identifiant du dépôt (ex. : `utilisateur/nouveau-nom`).'),
  (E:'Update the settings of a repository.';F:'Modifie les paramètres d''un dépôt.'),
  (E:'The gated status for the repository (auto, manual or false).';F:'Mode d''accès restreint (« gated ») du dépôt : auto, manual ou false.'),
  (E:'Make the repository private.';F:'Rend le dépôt privé.'),
  (E:'Make the repository public.';F:'Rend le dépôt public.'),
  (E:'Create a new branch for a repo on the Hub.';F:'Crée une nouvelle branche pour un dépôt du Hub.'),
  (E:'The name of the branch to create.';F:'Nom de la branche à créer.'),
  (E:'The git revision to create the branch from.';F:'Révision git à partir de laquelle créer la branche.'),
  (E:'If set to True, do not raise an error if branch already exists.';F:'Ne signale pas d''erreur si la branche existe déjà.'),
  (E:'Delete a branch from a repo on the Hub.';F:'Supprime une branche d''un dépôt du Hub.'),
  (E:'The name of the branch to delete.';F:'Nom de la branche à supprimer.'),
  (E:'Create a tag for a repo.';F:'Crée une étiquette (tag) pour un dépôt.'),
  (E:'The name of the tag to create.';F:'Nom de l''étiquette à créer.'),
  (E:'The description of the tag to create.';F:'Description de l''étiquette à créer.'),
  (E:'The git revision to tag.';F:'Révision git à étiqueter.'),
  (E:'Delete a tag from a repo.';F:'Supprime une étiquette (tag) d''un dépôt.'),
  (E:'The name of the tag to delete.';F:'Nom de l''étiquette à supprimer.'),
  (E:'Answer Yes to prompt automatically.';F:'Répond automatiquement oui à la confirmation.'),
  (E:'List tags for a repo.';F:'Liste les étiquettes (tags) d''un dépôt.'),
  (E:'Delete files from a repo on the Hub.';F:'Supprime des fichiers d''un dépôt du Hub.'),
  (E:'Glob patterns to match files to delete.';F:'Motifs glob des fichiers à supprimer.'),
  (E:'An optional Git revision to delete files from.';F:'Révision Git (facultatif) dont il faut supprimer les fichiers.'),
  (E:'Whether to create a Pull Request from the changes.';F:'Crée une Pull Request à partir des modifications.'),
  (E:'List collections on the Hub.';F:'Liste les collections du Hub.'),
  (E:'Filter by owner username or organization.';F:'Filtre par propriétaire (utilisateur ou organisation).'),
  (E:'Filter collections containing a specific item (e.g. models/gpt2).';F:'Filtre les collections contenant un élément précis (ex. : models/gpt2).'),
  (E:'Sort results by lastModified, trending or upvotes.';F:'Trie les résultats par lastModified, trending ou upvotes.'),
  (E:'Print only slugs.';F:'Affiche uniquement les identifiants courts (slugs).'),
  (E:'The collection slug (e.g. `username/collection-slug-123abc`).';F:'Identifiant court (slug) de la collection (ex. : `utilisateur/slug-123abc`).'),
  (E:'Create a new collection on the Hub.';F:'Crée une nouvelle collection sur le Hub.'),
  (E:'The title of the collection.';F:'Titre de la collection.'),
  (E:'The namespace of the collection (defaults to the authenticated user).';F:'Espace de noms de la collection (par défaut : l''utilisateur connecté).'),
  (E:'The description of the collection.';F:'Description de la collection.'),
  (E:'Create a private collection.';F:'Crée une collection privée.'),
  (E:'Do not raise an error if the collection already exists.';F:'Ne signale pas d''erreur si la collection existe déjà.'),
  (E:'Delete a collection from the Hub.';F:'Supprime une collection du Hub.'),
  (E:'Do not raise an error if the collection does not exist.';F:'Ne signale pas d''erreur si la collection n''existe pas.'),
  (E:'Add an item to a collection.';F:'Ajoute un élément à une collection.'),
  (E:'The ID of the item to add (e.g. `username/repo-name`).';F:'Identifiant de l''élément à ajouter (ex. : `utilisateur/nom-du-depot`).'),
  (E:'Type of item: model, dataset, space, paper or collection. [default: model]';F:'Type d''élément : model, dataset, space, paper ou collection. [défaut : model]'),
  (E:'A note to attach to the item (max 500 characters).';F:'Note à associer à l''élément (500 caractères maximum).'),
  (E:'Do not raise an error if the item is already in the collection.';F:'Ne signale pas d''erreur si l''élément est déjà dans la collection.'),
  (E:'The item object id (as shown by `hf collections info`).';F:'Identifiant objet de l''élément (affiché par `hf collections info`).'),
  (E:'Do not raise an error if the item does not exist.';F:'Ne signale pas d''erreur si l''élément n''existe pas.'),
  (E:'List daily papers on the Hub.';F:'Liste les articles du jour (daily papers) du Hub.'),
  (E:'Date in ISO format (YYYY-MM-DD).';F:'Date au format ISO (AAAA-MM-JJ).'),
  (E:'Sort order: publishedAt or trending.';F:'Ordre de tri : publishedAt ou trending.'),
  (E:'Limit the number of results. [default: 50]';F:'Limite le nombre de résultats. [défaut : 50]'),
  (E:'Search papers on the Hub.';F:'Recherche des articles scientifiques sur le Hub.'),
  (E:'Get info about a paper on the Hub. Output is in JSON format.';F:'Affiche les informations d''un article du Hub, au format JSON.'),
  (E:'The arXiv id of the paper (e.g. `2307.09288`).';F:'Identifiant arXiv de l''article (ex. : `2307.09288`).'),
  (E:'List discussions and pull requests on a repo.';F:'Liste les discussions et les pull requests d''un dépôt.'),
  (E:'Filter by status (open, closed, all). [default: open]';F:'Filtre par statut (open, closed, all). [défaut : open]'),
  (E:'Filter by kind (discussion, pull_request, all). [default: all]';F:'Filtre par nature (discussion, pull_request, all). [défaut : all]'),
  (E:'Filter by author.';F:'Filtre par auteur.'),
  (E:'The discussion number.';F:'Numéro de la discussion.'),
  (E:'Create a new discussion or pull request on a repo.';F:'Crée une discussion ou une pull request sur un dépôt.'),
  (E:'The title of the discussion or pull request.';F:'Titre de la discussion ou de la pull request.'),
  (E:'The description of the discussion or pull request.';F:'Description de la discussion ou de la pull request.'),
  (E:'Create a pull request instead of a discussion.';F:'Crée une pull request au lieu d''une discussion.'),
  (E:'Comment on a discussion or pull request.';F:'Commente une discussion ou une pull request.'),
  (E:'The comment text.';F:'Texte du commentaire.'),
  (E:'An optional comment to post with the change.';F:'Commentaire facultatif à publier avec le changement.'),
  (E:'Merge a pull request.';F:'Fusionne une pull request.'),
  (E:'The pull request number.';F:'Numéro de la pull request.'),
  (E:'An optional comment to post with the merge.';F:'Commentaire facultatif à publier avec la fusion.'),
  (E:'Lists all Inference Endpoints for the given namespace.';F:'Liste les Inference Endpoints de l''espace de noms indiqué.'),
  (E:'The namespace associated with the Inference Endpoints. Defaults to the current user.';F:'Espace de noms des Inference Endpoints. Par défaut : l''utilisateur courant.'),
  (E:'Endpoint name.';F:'Nom du point de terminaison (endpoint).'),
  (E:'The namespace associated with the Inference Endpoint. Defaults to the current user.';F:'Espace de noms de l''Inference Endpoint. Par défaut : l''utilisateur courant.'),
  (E:'Skip confirmation prompts.';F:'Ne demande pas de confirmation.'),
  (E:'Run a Job.';F:'Exécute un Job.'),
  (E:'The Docker image to use (or a Space URL).';F:'Image Docker à utiliser (ou URL d''un Space).'),
  (E:'The command to run.';F:'Commande à exécuter.'),
  (E:'Flavor for the hardware, as in HF Spaces. [default: cpu-basic]';F:'Type de matériel, comme pour les HF Spaces. [défaut : cpu-basic]'),
  (E:'Set environment variables. E.g. --env ENV=value';F:'Définit des variables d''environnement. Ex. : --env ENV=valeur'),
  (E:'Set secret environment variables. E.g. --secrets SECRET=value';F:'Définit des variables d''environnement secrètes. Ex. : --secrets SECRET=valeur'),
  (E:'Max duration: int/float with s (seconds), m (minutes), h (hours) or d (days).';F:'Durée maximale : nombre suivi de s (secondes), m (minutes), h (heures) ou d (jours).'),
  (E:'Run the Job in the background and print the Job ID.';F:'Exécute le Job en arrière-plan et affiche son identifiant.'),
  (E:'The namespace where the job will be running. Defaults to the current user''s namespace.';F:'Espace de noms où le job s''exécute. Par défaut : celui de l''utilisateur courant.'),
  (E:'List Jobs.';F:'Liste les Jobs.'),
  (E:'Show all Jobs (default shows just running Jobs).';F:'Affiche tous les Jobs (par défaut, seulement ceux en cours d''exécution).'),
  (E:'The namespace from where it lists the jobs. Defaults to the current user''s namespace.';F:'Espace de noms dont les jobs sont listés. Par défaut : celui de l''utilisateur courant.'),
  (E:'Print only Job IDs.';F:'Affiche uniquement les identifiants des Jobs.'),
  (E:'Display detailed information on one or more Jobs.';F:'Affiche les informations détaillées d''un ou plusieurs Jobs.'),
  (E:'The jobs to inspect.';F:'Jobs à inspecter.'),
  (E:'The namespace where the job is running. Defaults to the current user''s namespace.';F:'Espace de noms où le job s''exécute. Par défaut : celui de l''utilisateur courant.'),
  (E:'Fetch the logs of a Job.';F:'Récupère les journaux d''un Job.'),
  (E:'Job ID.';F:'Identifiant du Job.'),
  (E:'Cancel a Job.';F:'Annule un Job.'),
  (E:'Copy files between local paths and Hub repositories (hf://...).';F:'Copie des fichiers entre des chemins locaux et des dépôts du Hub (hf://...).'),
  (E:'Source: a local path or hf://[datasets/|spaces/]owner/name[@revision]/path.';F:'Source : un chemin local ou hf://[datasets/|spaces/]propriétaire/nom[@révision]/chemin.'),
  (E:'Destination: a local path or hf://[datasets/|spaces/]owner/name[@revision]/path.';F:'Destination : un chemin local ou hf://[datasets/|spaces/]propriétaire/nom[@révision]/chemin.'),
  (E:'Copy directories recursively.';F:'Copie les répertoires récursivement.'),
  (E:'Commit message when copying to a repository.';F:'Message de commit lors d''une copie vers un dépôt.'),
  (E:'Sync files between two local directories.';F:'Synchronise les fichiers entre deux répertoires locaux.'),
  (E:'Source directory.';F:'Répertoire source.'),
  (E:'Destination directory.';F:'Répertoire de destination.'),
  (E:'Delete files in DST that do not exist in SRC.';F:'Supprime dans DST les fichiers absents de SRC.'),
  (E:'Show what would be done without doing it.';F:'Affiche ce qui serait fait sans le faire.'),
  (E:'Glob patterns to include.';F:'Motifs glob à inclure.'),
  (E:'Glob patterns to exclude.';F:'Motifs glob à exclure.'),
  (E:'Commands to interact with buckets.';F:'Commandes pour interagir avec les buckets.'),
  (E:'List installed extensions.';F:'Liste les extensions installées.'),
  (E:'Path to a local hf-NAME executable (GitHub sources are not supported).';F:'Chemin d''un exécutable local hf-NOM (les sources GitHub ne sont pas prises en charge).'),
  (E:'Overwrite an existing extension.';F:'Écrase une extension existante.'),
  (E:'Remove an installed extension.';F:'Supprime une extension installée.'),
  (E:'Extension name (without the hf- prefix).';F:'Nom de l''extension (sans le préfixe hf-).'),
  (E:'Run an extension.';F:'Exécute une extension.'),
  (E:'Print information about the environment.';F:'Affiche des informations sur l''environnement.'),
  (E:'Print information about the hf version.';F:'Affiche des informations sur la version de hf.'),
  (E:'Check for a newer version of the hf CLI.';F:'Vérifie l''existence d''une version plus récente de la CLI hf.'),
  (E:'Print the generated SKILL.md to stdout.';F:'Affiche le fichier SKILL.md généré sur la sortie standard.'),
  (E:'Install the hf-cli skill for AI assistants.';F:'Installe la compétence (skill) hf-cli pour les assistants IA.'),
  (E:'Install for Claude Code (.claude/skills).';F:'Installe pour Claude Code (.claude/skills).'),
  (E:'Install for Codex (.agents/skills).';F:'Installe pour Codex (.agents/skills).'),
  (E:'Install for OpenCode (.opencode/skills).';F:'Installe pour OpenCode (.opencode/skills).'),
  (E:'Install globally (in the home directory) instead of the current project.';F:'Installe globalement (dans le répertoire personnel) plutôt que dans le projet courant.'),
  (E:'Install into this skills directory.';F:'Installe dans ce répertoire de compétences.'),
  (E:'Overwrite an existing installation.';F:'Écrase une installation existante.'),
  (E:'Verify checksums for a single repo revision from cache or a local directory.';F:'Vérifie les sommes de contrôle d''une révision de dépôt, depuis le cache ou un répertoire local.'),
  (E:'List models on the Hub.';F:'Liste les modèles du Hub.'),
  (E:'Get info about a model on the Hub.';F:'Affiche les informations d''un modèle du Hub.'),
  (E:'List datasets on the Hub.';F:'Liste les jeux de données du Hub.'),
  (E:'Get info about a dataset on the Hub.';F:'Affiche les informations d''un jeu de données du Hub.'),
  (E:'List spaces on the Hub.';F:'Liste les Spaces du Hub.'),
  (E:'Get info about a space on the Hub.';F:'Affiche les informations d''un Space du Hub.'),
  (E:'Get info about a model on the Hub. Output is in JSON format.';F:'Affiche les informations d''un modèle du Hub, au format JSON.'),
  (E:'Get info about a dataset on the Hub. Output is in JSON format.';F:'Affiche les informations d''un jeu de données du Hub, au format JSON.'),
  (E:'Get info about a space on the Hub. Output is in JSON format.';F:'Affiche les informations d''un Space du Hub, au format JSON.'),
  (E:'The ID of the model (e.g. `username/repo-name`).';F:'Identifiant du modèle (ex. : `utilisateur/nom-du-depot`).'),
  (E:'The ID of the dataset (e.g. `username/repo-name`).';F:'Identifiant du jeu de données (ex. : `utilisateur/nom-du-depot`).'),
  (E:'The ID of the space (e.g. `username/repo-name`).';F:'Identifiant du Space (ex. : `utilisateur/nom-du-depot`).'),
  (E:'Move a repository from a namespace to another namespace.';F:'Déplace un dépôt d''un espace de noms vers un autre.'),
  (E:'Manage branches for a repo on the Hub.';F:'Gère les branches d''un dépôt du Hub.'),
  (E:'Manage tags for a repo on the Hub.';F:'Gère les étiquettes (tags) d''un dépôt du Hub.'),
  (E:'Get info about a collection on the Hub.';F:'Affiche les informations d''une collection du Hub.'),
  (E:'Get info about a collection on the Hub. Output is in JSON format.';F:'Affiche les informations d''une collection du Hub, au format JSON.'),
  (E:'Delete an item from a collection.';F:'Supprime un élément d''une collection.'),
  (E:'Get info about a paper on the Hub.';F:'Affiche les informations d''un article du Hub.'),
  (E:'Get info about a discussion or pull request.';F:'Affiche les informations d''une discussion ou d''une pull request.'),
  (E:'Get info about a discussion or pull request. Output is in JSON format.';F:'Affiche les informations d''une discussion ou d''une pull request, au format JSON.'),
  (E:'Close a discussion or pull request.';F:'Ferme une discussion ou une pull request.'),
  (E:'Reopen a closed discussion or pull request.';F:'Rouvre une discussion ou une pull request fermée.'),
  (E:'Get information about an existing endpoint.';F:'Affiche les informations d''un endpoint existant.'),
  (E:'Pause an Inference Endpoint.';F:'Met en pause un Inference Endpoint.'),
  (E:'Resume an Inference Endpoint.';F:'Reprend un Inference Endpoint.'),
  (E:'Scale an Inference Endpoint to zero.';F:'Ramène un Inference Endpoint à zéro réplique.'),
  (E:'Delete an Inference Endpoint permanently.';F:'Supprime définitivement un Inference Endpoint.'),
  (E:'Create a bucket (not supported by this clone).';F:'Crée un bucket (non pris en charge par ce clone).'),
  (E:'List buckets (not supported by this clone).';F:'Liste les buckets (non pris en charge par ce clone).'),
  (E:'Get info about a bucket (not supported by this clone).';F:'Affiche les informations d''un bucket (non pris en charge par ce clone).'),
  (E:'Delete a bucket (not supported by this clone).';F:'Supprime un bucket (non pris en charge par ce clone).'),
  (E:'Copy files to or from a bucket (not supported by this clone).';F:'Copie des fichiers vers ou depuis un bucket (non pris en charge par ce clone).'),
  (E:'Sync a directory with a bucket (not supported by this clone).';F:'Synchronise un répertoire avec un bucket (non pris en charge par ce clone).'),
  (E:'Install an extension from a local executable named hf-NAME.';F:'Installe une extension à partir d''un exécutable local nommé hf-NOM.'),
  (E:'Install an extension.';F:'Installe une extension.'),
  (E:'Manage authentication (login, logout, etc.).';F:'Gère l''authentification (connexion, déconnexion, etc.).'),
  (E:'Manage local cache directory.';F:'Gère le répertoire de cache local.'),
  (E:'Interact with collections on the Hub.';F:'Interagit avec les collections du Hub.'),
  (E:'Copy files between local paths and Hub repositories.';F:'Copie des fichiers entre des chemins locaux et des dépôts du Hub.'),
  (E:'Interact with datasets on the Hub.';F:'Interagit avec les jeux de données du Hub.'),
  (E:'Manage discussions and pull requests on the Hub.';F:'Gère les discussions et les pull requests du Hub.'),
  (E:'Manage Hugging Face Inference Endpoints.';F:'Gère les Inference Endpoints de Hugging Face.'),
  (E:'Manage hf CLI extensions.';F:'Gère les extensions de la CLI hf.'),
  (E:'Run and manage Jobs on the Hub.';F:'Exécute et gère des Jobs sur le Hub.'),
  (E:'Interact with models on the Hub.';F:'Interagit avec les modèles du Hub.'),
  (E:'Interact with papers on the Hub.';F:'Interagit avec les articles scientifiques du Hub.'),
  (E:'Manage repos on the Hub.';F:'Gère les dépôts du Hub.'),
  (E:'Manage skills for AI assistants.';F:'Gère les compétences (skills) des assistants IA.'),
  (E:'Interact with spaces on the Hub.';F:'Interagit avec les Spaces du Hub.'),
  (E:'Upload a file or a folder to the Hub.';F:'Envoie un fichier ou un dossier vers le Hub.'),
  (E:'Upload a file or a folder to the Hub. Recommended for single-commit uploads.';F:'Envoie un fichier ou un dossier vers le Hub, en un seul commit.'),
  (E:'Hugging Face Hub CLI (Pascal clone)';F:'CLI du Hugging Face Hub (clone Pascal)'),
  (E:'Show this message and exit.';F:'Affiche ce message et quitte.'),
  (E:'Missing option ''--title''.';F:'Option ''--title'' manquante.'),
  (E:'Missing option ''--body''.';F:'Option ''--body'' manquante.'),
  (E:'--space-sdk is required when --repo-type is ''space''.';F:'--space-sdk est obligatoire quand --repo-type vaut ''space''.'),
  (E:'Nothing to update: pass --gated, --private or --public.';F:'Rien à modifier : indiquez --gated, --private ou --public.'),
  (E:'Lists the Inference Endpoints.';F:'Liste les Inference Endpoints.'));

Function IsEn:Boolean;
Begin
 IsEn:=LoStr(Copy(TrimStr(GetEnv('LANGUAGE')),1,2))='en';
End;

{ choisit le texte selon la langue }
Function L(Const En,Fr:AnsiString):AnsiString;
Begin
 If IsEn Then L:=En Else L:=Fr;
End;

{ traduit un texte d'aide anglais (inchange s'il n'est pas dans la table) }
Function Tr(Const S:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 Tr:=S;
 If IsEn Then Exit;
 For I:=0 to NTr-1 do If TrTable[I].E=S Then Begin Tr:=TrTable[I].F;Exit;End;
End;

{ ------------------------------------------------------------------ }
{ Analyse de la ligne de commande et aide (style typer/click)         }
{ ------------------------------------------------------------------ }

Const
 MaxOpt=40;

Type
 TOptDef = Record
  Long,Short,Meta,Help:AnsiString;
  Multi:Boolean;
 End;

Var
 CmdPath,CmdDesc,CmdUsage:AnsiString;
 ArgNames,ArgDescs:TSList;
 ODef:Array[0..MaxOpt-1]of TOptDef;
 ONum:LongInt;
 OVals:Array[0..MaxOpt-1]of TSList;
 OSet:Array[0..MaxOpt-1]of Boolean;
 PosArgs:TSList;
 StopAfter:LongInt;
 ArgStart:LongInt;

Procedure CmdBegin(Const Path,Desc,Usage:AnsiString);
Var
 I:LongInt;
Begin
 CmdPath:=Path;CmdDesc:=Desc;CmdUsage:=Usage;
 SClear(ArgNames);SClear(ArgDescs);
 For I:=0 to MaxOpt-1 do Begin SClear(OVals[I]);OSet[I]:=False;End;
 ONum:=0;SClear(PosArgs);StopAfter:=0;
End;

Procedure CmdArg(Const Name,Desc:AnsiString);
Begin
 SAdd(ArgNames,Name);SAdd(ArgDescs,Desc);
End;

{ Meta='' : option sans valeur ; Meta commencant par '*' : option repetable }
Procedure Opt(Const Long,Short,Meta,Help:AnsiString);
Begin
 ODef[ONum].Long:=Long;
 ODef[ONum].Short:=Short;
 ODef[ONum].Multi:=(Meta<>'')and(Meta[1]='*');
 If ODef[ONum].Multi Then ODef[ONum].Meta:=Copy(Meta,2,Length(Meta))
                     Else ODef[ONum].Meta:=Meta;
 ODef[ONum].Help:=Help;
 Inc(ONum);
End;

Function PadR(Const S:AnsiString;N:LongInt):AnsiString;
Begin
 If Length(S)>=N Then PadR:=S Else PadR:=S+StringOfChar(' ',N-Length(S));
End;

Procedure PrintCmdHelp;
Var
 I,W:LongInt;
 Ls:TSList;
 S:AnsiString;
Begin
 WriteLn(L('Usage: ','Utilisation : '),CmdPath,' [OPTIONS] ',CmdUsage);
 WriteLn;
 WriteLn('  ',Tr(CmdDesc));
 WriteLn;
 If ArgNames.N>0 Then Begin
  WriteLn(L('Arguments:','Arguments :'));
  W:=0;
  For I:=0 to ArgNames.N-1 do If Length(ArgNames.A[I])>W Then W:=Length(ArgNames.A[I]);
  For I:=0 to ArgNames.N-1 do WriteLn('  ',PadR(ArgNames.A[I],W),'  ',Tr(ArgDescs.A[I]));
  WriteLn;
 End;
 WriteLn(L('Options:','Options :'));
 SClear(Ls);
 W:=0;
 For I:=0 to ONum do Begin
  If I=ONum Then S:='-h, --help, /?'
  Else Begin
   If ODef[I].Short<>'' Then S:='-'+ODef[I].Short+', ' Else S:='    ';
   S:=S+'--'+ODef[I].Long;
   If ODef[I].Meta<>'' Then S:=S+' '+ODef[I].Meta;
  End;
  SAdd(Ls,S);
  If Length(S)>W Then W:=Length(S);
 End;
 For I:=0 to ONum do Begin
  If I=ONum Then WriteLn('  ',PadR(Ls.A[I],W),'  ',Tr('Show this message and exit.'))
  Else WriteLn('  ',PadR(Ls.A[I],W),'  ',Tr(ODef[I].Help));
 End;
End;

Procedure UsageErr(Const Msg:AnsiString);
Begin
 WriteLn(StdErr,L('Usage: ','Utilisation : '),CmdPath,' [OPTIONS] ',CmdUsage);
 WriteLn(StdErr,L('Try ''','Essayez ''') ,CmdPath,L(' -h'' for help.',' -h'' pour obtenir de l''aide.'));
 WriteLn(StdErr);
 WriteLn(StdErr,L('Error: ','Erreur : '),Tr(Msg));
 Halt(2);
End;

Function FindOpt(Const Name:AnsiString;IsShort:Boolean):LongInt;
Var
 I:LongInt;
Begin
 FindOpt:=-1;
 For I:=0 to ONum-1 do
  If(IsShort and(ODef[I].Short=Name))or((not IsShort)and(ODef[I].Long=Name))Then Begin
   FindOpt:=I;Exit;
  End;
End;

Procedure ParseArgs(First:LongInt);
Var
 I,K,P:LongInt;
 A,Nm,V:AnsiString;
 Rest:Boolean;
Begin
 Rest:=False;
 I:=First;
 While I<=ParamCount do Begin
  A:=ParamStr(I);
  If Rest or((StopAfter>0)and(PosArgs.N>=StopAfter))Then SAdd(PosArgs,A)
  Else If A='--' Then Rest:=True
  Else If(A='-h')or(A='--help')or(A='/?')Then Begin PrintCmdHelp;Halt(0);End
  Else If StartsWith(A,'--')Then Begin
   Nm:=Copy(A,3,Length(A));V:='';
   P:=Pos('=',Nm);
   If P>0 Then Begin V:=Copy(Nm,P+1,Length(Nm));Nm:=Copy(Nm,1,P-1);End;
   K:=FindOpt(Nm,False);
   If K<0 Then UsageErr(L('No such option: --','Option inconnue : --')+Nm);
   If ODef[K].Meta='' Then Begin
    If P>0 Then UsageErr(L('Option ''--'+Nm+''' does not take a value.','L''option ''--'+Nm+''' n''accepte pas de valeur.'));
    OSet[K]:=True;
   End
   Else Begin
    If P=0 Then Begin
     If I>=ParamCount Then UsageErr(L('Option ''--'+Nm+''' requires an argument.','L''option ''--'+Nm+''' requiert un argument.'));
     Inc(I);V:=ParamStr(I);
    End;
    OSet[K]:=True;
    If(not ODef[K].Multi)and(OVals[K].N>0)Then OVals[K].A[0]:=V Else SAdd(OVals[K],V);
   End;
  End
  Else If(Length(A)>=2)and(A[1]='-')and not(A[2]in['0'..'9'])Then Begin
   Nm:=Copy(A,2,1);
   K:=FindOpt(Nm,True);
   If K<0 Then UsageErr(L('No such option: -','Option inconnue : -')+Nm);
   If ODef[K].Meta='' Then OSet[K]:=True
   Else Begin
    If Length(A)>2 Then V:=Copy(A,3,Length(A))
    Else Begin
     If I>=ParamCount Then UsageErr(L('Option ''-'+Nm+''' requires an argument.','L''option ''-'+Nm+''' requiert un argument.'));
     Inc(I);V:=ParamStr(I);
    End;
    OSet[K]:=True;
    If(not ODef[K].Multi)and(OVals[K].N>0)Then OVals[K].A[0]:=V Else SAdd(OVals[K],V);
   End;
  End
  Else SAdd(PosArgs,A);
  Inc(I);
 End;
End;

Procedure NeedArgs(Min,Max:LongInt);
Begin
 If PosArgs.N<Min Then Begin
  If PosArgs.N<ArgNames.N Then UsageErr(L('Missing argument ''','Argument manquant : ''')+ArgNames.A[PosArgs.N]+'''.')
  Else UsageErr(L('Missing argument.','Argument manquant.'));
 End;
 If(Max>=0)and(PosArgs.N>Max)Then
   UsageErr(L('Got unexpected extra argument (','Argument supplémentaire inattendu (')+PosArgs.A[Max]+')');
End;

Function OptHas(Const Long:AnsiString):Boolean;
Var
 K:LongInt;
Begin
 K:=FindOpt(Long,False);
 OptHas:=(K>=0)and OSet[K];
End;

Function OptGet(Const Long:AnsiString):AnsiString;
Var
 K:LongInt;
Begin
 OptGet:='';
 K:=FindOpt(Long,False);
 If(K>=0)and(OVals[K].N>0)Then OptGet:=OVals[K].A[OVals[K].N-1];
End;

Function OptGetDef(Const Long,Def:AnsiString):AnsiString;
Begin
 If OptHas(Long)Then OptGetDef:=OptGet(Long) Else OptGetDef:=Def;
End;

Function OptInt(Const Long:AnsiString;Def:Int64):Int64;
Begin
 If OptHas(Long)Then Begin
  OptInt:=ToInt(OptGet(Long),-1);
  If ToInt(OptGet(Long),-1)=-1 Then UsageErr('Invalid value for ''--'+Long+''': '''+
    OptGet(Long)+''' is not a valid integer.');
 End
 Else OptInt:=Def;
End;

Procedure OptList(Const Long:AnsiString;Var L:TSList);
Var
 K,I:LongInt;
Begin
 SClear(L);
 K:=FindOpt(Long,False);
 If K>=0 Then For I:=0 to OVals[K].N-1 do SAdd(L,OVals[K].A[I]);
End;

Function Pos1(I:LongInt):AnsiString;
Begin
 If I<PosArgs.N Then Pos1:=PosArgs.A[I] Else Pos1:='';
End;

{ ------------------------------------------------------------------ }
{ Reglages, jetons                                                    }
{ ------------------------------------------------------------------ }

Function HfHome:AnsiString;
Var
 D:AnsiString;
Begin
 D:=GetEnv('HF_HOME');
 If D='' Then Begin
  D:=GetEnv('XDG_CACHE_HOME');
  If D='' Then D:=JoinPath(HomeDir,'.cache');
  D:=JoinPath(D,'huggingface');
 End;
 HfHome:=DropSlash(D);
End;

Function HubCache:AnsiString;
Var
 D:AnsiString;
Begin
 D:=GetEnv('HF_HUB_CACHE');
 If D='' Then D:=GetEnv('HUGGINGFACE_HUB_CACHE');
 If D='' Then D:=JoinPath(HfHome,'hub');
 HubCache:=DropSlash(D);
End;

Function TokenPath:AnsiString;
Begin
 TokenPath:=GetEnv('HF_TOKEN_PATH');
 If TokenPath='' Then TokenPath:=JoinPath(HfHome,'token');
End;

Function StoredTokensPath:AnsiString;
Begin
 StoredTokensPath:=JoinPath(HfHome,'stored_tokens');
End;

Function ReadTokenFile:AnsiString;
Var
 S:AnsiString;
Begin
 ReadTokenFile:='';
 If ReadAll(TokenPath,S)Then ReadTokenFile:=TrimStr(S);
End;

Function ResolveToken(Const Opt_:AnsiString):AnsiString;
Begin
 If Opt_<>'' Then Begin ResolveToken:=Opt_;Exit;End;
 Result:=GetEnv('HF_TOKEN');
 If Result='' Then Result:=GetEnv('HUGGING_FACE_HUB_TOKEN');
 If Result='' Then Result:=ReadTokenFile;
End;

Function TokenOpt:AnsiString;
Begin
 TokenOpt:=ResolveToken(OptGet('token'));
End;

Procedure AddTokenOpt;
Begin
 Opt('token','','TEXT','A User Access Token generated from https://huggingface.co/settings/tokens.');
End;

Procedure AddTypeOpt;
Begin
 Opt('repo-type','','TEXT','The type of repository (model, dataset, or space). [default: model]');
End;

Function RepoType:AnsiString;
Var
 T:AnsiString;
Begin
 T:=LoStr(OptGetDef('repo-type','model'));
 If T='models' Then T:='model' Else If T='datasets' Then T:='dataset'
  Else If T='spaces' Then T:='space';
 If(T<>'model')and(T<>'dataset')and(T<>'space')Then
   UsageErr('Invalid value for ''--repo-type'': '''+T+''' is not one of ''model'', ''dataset'', ''space''.');
 RepoType:=T;
End;

Function TypeApi(Const T:AnsiString):AnsiString;
Begin
 TypeApi:=T+'s';
End;

Function TypePrefix(Const T:AnsiString):AnsiString;
Begin
 If T='dataset' Then TypePrefix:='datasets/' Else If T='space' Then
   TypePrefix:='spaces/' Else TypePrefix:='';
End;

{ ------------------------------------------------------------------ }
{ Acces a l'API du Hub                                                }
{ ------------------------------------------------------------------ }

Function ReasonOf(S:LongInt):AnsiString;
Begin
 Case S of
  400:ReasonOf:='Bad Request';
  401:ReasonOf:='Unauthorized';
  403:ReasonOf:='Forbidden';
  404:ReasonOf:='Not Found';
  409:ReasonOf:='Conflict';
  410:ReasonOf:='Gone';
  422:ReasonOf:='Unprocessable Entity';
  429:ReasonOf:='Too Many Requests';
  500:ReasonOf:='Internal Server Error';
  502:ReasonOf:='Bad Gateway';
  503:ReasonOf:='Service Unavailable';
  504:ReasonOf:='Gateway Timeout';
  Else ReasonOf:='HTTP error';
 End;
End;

Function ErrText(Var R:THttpReq):AnsiString;
Var
 J:LongInt;
 Msg,Code:AnsiString;
Begin
 If R.Status=0 Then Begin ErrText:=R.Err;Exit;End;
 Msg:='';
 JReset;
 J:=JParse(R.RespBody);
 If J>=0 Then Begin
  Msg:=JS(J,'error');
  If Msg='' Then Msg:=JS(J,'message');
  If(Msg='')and(JGet(J,'error')>=0)Then Msg:=JS(J,'error.message');
 End;
 If(Msg='')and(J<0)Then Msg:=Copy(TrimStr(R.RespBody),1,300);
 Code:=HeaderGet(R.RespHeaders,'x-error-code');
 Result:=IStr(R.Status)+' '+ReasonOf(R.Status)+' for url: '+R.Url;
 If Msg<>'' Then Result:=Result+#10+Msg;
 Case R.Status of
  401:Result:=Result+#10'Invalid credentials. Please log in with `hf auth login` or pass --token.';
  404:If Code='RepoNotFound' Then
       Result:=Result+#10'Repository not found. Make sure the repo id and --repo-type are correct. '+
       'If it is private or gated, make sure you are authenticated.'
      Else If Code='RevisionNotFound' Then Result:=Result+#10'Revision not found.'
      Else If Code='EntryNotFound' Then Result:=Result+#10'Entry not found in the repository.';
 End;
End;

Procedure ApiCall(Var R:THttpReq;Const Method,Path,Body,Token:AnsiString);
Begin
 ReqInit(R,Method,Endpoint+Path,Token);
 If Body<>'' Then Begin
  R.BodyStr:=Body;
  R.Headers:='Content-Type: application/json'#13#10;
 End;
 HttpDo(R);
End;

Function ApiOk(Var R:THttpReq):Boolean;
Begin
 ApiOk:=(R.Err='')and(R.Status>=200)and(R.Status<300);
End;

{ requete obligatoire : arrete le programme en cas d'echec }
Procedure ApiMust(Var R:THttpReq;Const Method,Path,Body,Token:AnsiString);
Begin
 ApiCall(R,Method,Path,Body,Token);
 If not ApiOk(R)Then Die(ErrText(R));
End;

{ requete obligatoire dont le corps est du JSON : renvoie la racine }
Function ApiJson(Const Method,Path,Body,Token:AnsiString):LongInt;
Var
 R:THttpReq;
Begin
 ApiMust(R,Method,Path,Body,Token);
 JReset;
 ApiJson:=JParse(R.RespBody);
 If ApiJson<0 Then Die('invalid JSON response from '+R.Url);
End;

Function LinkNext(Const H:AnsiString):AnsiString;
Var
 V:AnsiString;
 P,Q:LongInt;
Begin
 LinkNext:='';
 V:=HeaderGet(H,'link');
 P:=Pos('rel="next"',V);
 If P=0 Then Exit;
 Q:=P;
 While(Q>0)and(V[Q]<>'<')do Dec(Q);
 If Q=0 Then Exit;
 P:=Pos('>',Copy(V,Q,Length(V)));
 If P>0 Then LinkNext:=Copy(V,Q+1,P-2);
End;

Var
 WhoCache:AnsiString;

Function WhoamiName(Const Token:AnsiString):AnsiString;
Var
 J:LongInt;
Begin
 If WhoCache<>'' Then Begin WhoamiName:=WhoCache;Exit;End;
 If Token='' Then Die('Not logged in. Run `hf auth login` or pass --token.');
 J:=ApiJson('GET','/api/whoami-v2','',Token);
 WhoCache:=JS(J,'name');
 WhoamiName:=WhoCache;
End;

{ ajoute l'espace de noms de l'utilisateur si absent }
Function FullRepo(Const Repo,Token:AnsiString):AnsiString;
Begin
 If Pos('/',Repo)>0 Then FullRepo:=Repo Else FullRepo:=Repo;
End;

{ ------------------------------------------------------------------ }
{ Tableaux                                                            }
{ ------------------------------------------------------------------ }

Var
 TblHead:AnsiString;
 TblRows:TSList;

Procedure TblBegin(Const Head:AnsiString);
Begin
 TblHead:=Head;
 SClear(TblRows);
End;

Procedure TblRow(Const Cells:AnsiString);
Begin
 SAdd(TblRows,ReplaceAll(Cells,#13,''));
End;

Procedure TblPrint;
Var
 Cols:LongInt;
 W:Array[0..15]of LongInt;
 H,Cell:TSList;
 I,J:LongInt;
 Line:AnsiString;
Begin
 SplitStr(TblHead,#9,H);
 Cols:=H.N;
 If Cols>16 Then Cols:=16;
 For I:=0 to Cols-1 do W[I]:=Length(H.A[I]);
 For I:=0 to TblRows.N-1 do Begin
  SplitStr(TblRows.A[I],#9,Cell);
  For J:=0 to Cell.N-1 do If(J<Cols)and(Length(Cell.A[J])>W[J])Then W[J]:=Length(Cell.A[J]);
 End;
 Line:='';
 For I:=0 to Cols-1 do Begin
  If I>0 Then Line:=Line+' ';
  Line:=Line+PadR(H.A[I],W[I]);
 End;
 WriteLn(TrimRight_(Line));
 Line:='';
 For I:=0 to Cols-1 do Begin
  If I>0 Then Line:=Line+' ';
  Line:=Line+StringOfChar('-',W[I]);
 End;
 WriteLn(Line);
 For I:=0 to TblRows.N-1 do Begin
  SplitStr(TblRows.A[I],#9,Cell);
  Line:='';
  For J:=0 to Cols-1 do Begin
   If J>0 Then Line:=Line+' ';
   If J<Cell.N Then Line:=Line+PadR(Cell.A[J],W[J]) Else Line:=Line+PadR('',W[J]);
  End;
  WriteLn(TrimRight_(Line));
 End;
End;

{ ------------------------------------------------------------------ }
{ Telechargement                                                      }
{ ------------------------------------------------------------------ }

Type
 TRFile = Record
  Path:AnsiString;
  Size:Int64;
  Etag,BlobId:AnsiString;
  IsLfs:Boolean;
 End;
 TRFiles = Array of TRFile;

Function IsCommitHash(Const S:AnsiString):Boolean;
Var
 I:LongInt;
Begin
 IsCommitHash:=False;
 If Length(S)<>40 Then Exit;
 For I:=1 to 40 do If not(S[I]in['0'..'9','a'..'f'])Then Exit;
 IsCommitHash:=True;
End;

Function CleanEtag(Const S:AnsiString):AnsiString;
Begin
 Result:=TrimStr(S);
 If StartsWith(Result,'W/')Then Delete(Result,1,2);
 Result:=ReplaceAll(Result,'"','');
End;

Procedure FetchRepo(Const Repo,RType,Rev,Token:AnsiString;Var Commit:AnsiString;
  Var Files:TRFiles);
Var
 J,S,X,I,N:LongInt;
Begin
 J:=ApiJson('GET','/api/'+TypeApi(RType)+'/'+UrlEnc(Repo,True)+'/revision/'+
   UrlEnc(Rev,False)+'?blobs=true','',Token);
 Commit:=JS(J,'sha');
 S:=JGet(J,'siblings');
 N:=JCnt(S);
 SetLength(Files,N);
 For I:=0 to N-1 do Begin
  X:=JAt(S,I);
  Files[I].Path:=JS(X,'rfilename');
  Files[I].Size:=JI(X,'size');
  Files[I].IsLfs:=JGet(X,'lfs')>=0;
  Files[I].BlobId:=JS(X,'blobId');
  If Files[I].IsLfs Then Begin
   Files[I].Etag:=JS(X,'lfs.sha256');
   If JGet(JGet(X,'lfs'),'size')>=0 Then Files[I].Size:=JI(X,'lfs.size');
  End
  Else Files[I].Etag:=Files[I].BlobId;
 End;
End;

Function ResolveFileUrl(Const Repo,RType,Rev,FilePath:AnsiString):AnsiString;
Begin
 ResolveFileUrl:=Endpoint+'/'+TypePrefix(RType)+UrlEnc(Repo,True)+'/resolve/'+
   UrlEnc(Rev,False)+'/'+UrlEnc(FilePath,True);
End;

Function RepoFolder(Const CacheD,Repo,RType:AnsiString):AnsiString;
Begin
 RepoFolder:=JoinPath(CacheD,RType+'s--'+ReplaceAll(Repo,'/','--'));
End;

{ telecharge Url vers Dest en passant par IncPath (reprise possible) ; '' si ok }
Function FetchFile(Const Url,Token,Dest,IncPath,Lbl:AnsiString;Size:Int64;
  Quiet:Boolean):AnsiString;
Var
 R:THttpReq;
 T:LongInt;
 Have,Final:Int64;
 Done:Boolean;
Begin
 FetchFile:='';
 MkDirs(ParentDir(Dest));
 MkDirs(ParentDir(IncPath));
 Done:=False;
 For T:=1 to 5 do Begin
  Have:=FileSizeOf(IncPath);
  If Have<0 Then Have:=0;
  If(Size>0)and(Have>Size)Then Begin DelFile(IncPath);Have:=0;End;
  If(Size>0)and(Have=Size)Then Begin Done:=True;Break;End;
  ReqInit(R,'GET',Url,Token);
  R.OutFile:=IncPath;
  R.ResumeFrom:=Have;
  R.ShowProg:=not Quiet;
  R.ProgLabel:=Lbl;
  HttpDo(R);
  If ApiOk(R)Then Begin Done:=True;Break;End;
  If R.Status=416 Then Begin DelFile(IncPath);Continue;End;
  If(R.Status>=400)and(R.Status<500)and(R.Status<>429)and(R.Status<>408)Then Begin
   FetchFile:=ErrText(R);
   Exit;
  End;
  If T<5 Then Begin
   If not Quiet Then WriteLn(StdErr,'Retrying ',Lbl,' (',T,'/5): ',ErrText(R));
   WaitSec(T*2);
  End
  Else Begin FetchFile:=ErrText(R);Exit;End;
 End;
 If not Done Then Begin FetchFile:='download failed: '+Url;Exit;End;
 Final:=FileSizeOf(IncPath);
 If(Size>=0)and(Final<>Size)Then Begin
  FetchFile:='size mismatch for '+Lbl+': expected '+IStr(Size)+' bytes, got '+IStr(Final);
  DelFile(IncPath);
  Exit;
 End;
 If not MoveFile_(IncPath,Dest)Then FetchFile:='cannot write '+Dest;
End;

Procedure WriteLocalMeta(Const LocalD,FilePath,Commit,Etag:AnsiString);
Var
 M:AnsiString;
Begin
 M:=JoinPath(JoinPath(JoinPath(LocalD,'.cache'),'huggingface'),'download');
 WriteAll(JoinPath(M,NormSep(FilePath)+'.metadata'),Commit+#10+Etag+#10+IStr(NowEpoch)+#10);
 WriteAll(JoinPath(JoinPath(JoinPath(LocalD,'.cache'),'huggingface'),'.gitignore'),'*'#10);
End;

Function LocalMetaMatches(Const LocalD,FilePath,Etag:AnsiString):Boolean;
Var
 M,S:AnsiString;
 L:TSList;
Begin
 LocalMetaMatches:=False;
 M:=JoinPath(JoinPath(JoinPath(JoinPath(LocalD,'.cache'),'huggingface'),'download'),
   NormSep(FilePath)+'.metadata');
 If not ReadAll(M,S)Then Exit;
 SplitStr(ReplaceAll(S,#13,''),#10,L);
 LocalMetaMatches:=(L.N>=2)and(L.A[1]=Etag);
End;

Function Selected(Const P:AnsiString;Const Allow,Deny:TSList):Boolean;
Var
 I:LongInt;
 Ok:Boolean;
Begin
 Ok:=Allow.N=0;
 For I:=0 to Allow.N-1 do If Glob(Allow.A[I],P)Then Ok:=True;
 For I:=0 to Deny.N-1 do If Glob(Deny.A[I],P)Then Ok:=False;
 Selected:=Ok;
End;

{ telecharge un fichier du depot vers Dest (hors cache), utilise par cp }
Procedure DownloadTo(Const Repo,RType,Rev,FilePath,Token,Dest:AnsiString;Quiet:Boolean);
Var
 Err:AnsiString;
Begin
 Err:=FetchFile(ResolveFileUrl(Repo,RType,Rev,FilePath),Token,Dest,Dest+'.incomplete',
   BaseName(FilePath),-1,Quiet);
 If Err<>'' Then Die(Err);
End;

Procedure CmdDownload;
Var
 Repo,RType,Rev,Tok,CacheD,LocalD,RepoDir,Commit,Etag,SnapDir,Dest,Inc_,Err:AnsiString;
 Allow,Deny,Names:TSList;
 Quiet,Force,Dry,Single:Boolean;
 Files:TRFiles;
 I,NSel,NSkip:LongInt;
 Total,Todo:Int64;
 R:THttpReq;
 Size:Int64;
 Skip:Boolean;
 Todos:TSList;
Begin
 CmdBegin('hf download','Download files from the Hub.','REPO_ID [FILENAMES]...');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 CmdArg('FILENAMES','Files to download (e.g. `config.json`, `data/metadata.jsonl`).');
 AddTypeOpt;
 Opt('revision','','TEXT','Git revision id which can be a branch name, a tag, or a commit hash.');
 Opt('include','','*TEXT','Glob patterns to include from files to download. eg: *.json');
 Opt('exclude','','*TEXT','Glob patterns to exclude from files to download.');
 Opt('cache-dir','','TEXT','Directory where to save files.');
 Opt('local-dir','','TEXT','If set, the downloaded file will be placed under this directory.');
 Opt('force-download','','','If True, the files will be downloaded even if they are already cached.');
 Opt('dry-run','','','If True, perform a dry run without actually downloading the file.');
 AddTokenOpt;
 Opt('quiet','q','','Disable progress bars and warnings; print only the returned path.');
 Opt('max-workers','','INTEGER','Maximum number of workers to use for downloading files. Default is 8.');
 ParseArgs(ArgStart);
 NeedArgs(1,-1);
 Repo:=Pos1(0);RType:=RepoType;
 Rev:=OptGetDef('revision','main');
 Tok:=TokenOpt;
 Quiet:=OptHas('quiet');Force:=OptHas('force-download');Dry:=OptHas('dry-run');
 CacheD:=OptGetDef('cache-dir',HubCache);
 If OptHas('local-dir')Then LocalD:=AbsPath(OptGet('local-dir')) Else LocalD:='';
 OptInt('max-workers',8);
 OptList('include',Allow);OptList('exclude',Deny);
 SClear(Names);
 For I:=1 to PosArgs.N-1 do SAdd(Names,PosArgs.A[I]);
 Single:=(Names.N=1)and not HasWild(Names.A[0])and(Allow.N=0)and(Deny.N=0);
 RepoDir:=RepoFolder(CacheD,Repo,RType);

 If Single Then Begin
  { un seul fichier : HEAD pour connaitre le commit, la taille et l'etag }
  ReqInit(R,'HEAD',ResolveFileUrl(Repo,RType,Rev,Names.A[0]),Tok);
  R.StopAtLinked:=True;
  HttpDo(R);
  If R.Err<>'' Then Die(R.Err);
  If not((R.Status=200)or((R.Status>=300)and(R.Status<400)and
    (HeaderGet(R.RespHeaders,'x-linked-etag')<>'')))Then Begin
   If R.Status=404 Then Die('404 Client Error: Entry Not Found for url: '+R.Url+#10+
     'Entry not found: '+Names.A[0]+' in '+RType+' '+Repo+' (revision '+Rev+').'
     +' If the repo is private or gated, make sure you are authenticated.')
   Else Die(ErrText(R));
  End;
  Commit:=HeaderGet(R.RespHeaders,'x-repo-commit');
  Etag:=CleanEtag(HeaderGet(R.RespHeaders,'x-linked-etag'));
  If Etag='' Then Etag:=CleanEtag(HeaderGet(R.RespHeaders,'etag'));
  Size:=ToInt(HeaderGet(R.RespHeaders,'x-linked-size'),-1);
  If Size<0 Then Size:=ToInt(HeaderGet(R.RespHeaders,'content-length'),-1);
  If Commit='' Then Commit:=Rev;
  If LocalD<>'' Then Dest:=JoinPath(LocalD,NormSep(Names.A[0]))
  Else Dest:=JoinPath(JoinPath(JoinPath(RepoDir,'snapshots'),Commit),NormSep(Names.A[0]));
  If Dry Then Begin
   WriteLn('[dry-run] Will download 1 files (out of 1) totalling ',HumanSize(Size),'.');
   TblBegin('File'+#9+'Bytes to download');
   TblRow(Names.A[0]+#9+IStr(Size));
   TblPrint;
   Exit;
  End;
  Skip:=False;
  If not Force Then Begin
   If LocalD<>'' Then Skip:=FileExists_(Dest)and LocalMetaMatches(LocalD,Names.A[0],Etag)
   Else Skip:=FileExists_(Dest)and((Size<0)or(FileSizeOf(Dest)=Size));
  End;
  If not Skip Then Begin
   If LocalD<>'' Then
     Inc_:=JoinPath(JoinPath(JoinPath(JoinPath(LocalD,'.cache'),'huggingface'),'download'),
       NormSep(Names.A[0])+'.incomplete')
   Else Inc_:=JoinPath(JoinPath(RepoDir,'blobs'),Etag+'.incomplete');
   If Force Then DelFile(Inc_);
   Err:=FetchFile(ResolveFileUrl(Repo,RType,Commit,Names.A[0]),Tok,Dest,Inc_,
     Names.A[0],Size,Quiet);
   If Err<>'' Then Die(Err);
  End;
  If LocalD<>'' Then WriteLocalMeta(LocalD,Names.A[0],Commit,Etag)
  Else If not IsCommitHash(Rev)Then
    WriteAll(JoinPath(JoinPath(RepoDir,'refs'),NormSep(Rev)),Commit);
  WriteLn(Dest);
  Exit;
 End;

 { plusieurs fichiers : liste du depot puis filtrage }
 For I:=0 to Names.N-1 do SAdd(Allow,Names.A[I]);
 FetchRepo(Repo,RType,Rev,Tok,Commit,Files);
 If Commit='' Then Die('cannot determine the commit of '+Repo);
 If LocalD<>'' Then SnapDir:=LocalD
 Else SnapDir:=JoinPath(JoinPath(RepoDir,'snapshots'),Commit);
 NSel:=0;NSkip:=0;Total:=0;Todo:=0;SClear(Todos);
 For I:=0 to High(Files)do If Selected(Files[I].Path,Allow,Deny)Then Begin
  Inc(NSel);
  Dest:=JoinPath(SnapDir,NormSep(Files[I].Path));
  Skip:=False;
  If not Force Then Begin
   If LocalD<>'' Then Skip:=FileExists_(Dest)and LocalMetaMatches(LocalD,Files[I].Path,
     Files[I].Etag)and(FileSizeOf(Dest)=Files[I].Size)
   Else Skip:=FileExists_(Dest)and(FileSizeOf(Dest)=Files[I].Size);
  End;
  Inc(Total,Files[I].Size);
  If Skip Then Inc(NSkip) Else Begin
   Inc(Todo,Files[I].Size);
   SAdd(Todos,IStr(I));
  End;
 End;
 If NSel=0 Then Warn('no file matches the given patterns in '+Repo+'.');
 If Dry Then Begin
  WriteLn('[dry-run] Will download ',Todos.N,' files (out of ',NSel,') totalling ',
    HumanSize(Todo),'.');
  TblBegin('File'+#9+'Bytes to download');
  For I:=0 to Todos.N-1 do
   TblRow(Files[ToInt(Todos.A[I],0)].Path+#9+IStr(Files[ToInt(Todos.A[I],0)].Size));
  TblPrint;
  Exit;
 End;
 For I:=0 to High(Files)do If Selected(Files[I].Path,Allow,Deny)Then Begin
  Dest:=JoinPath(SnapDir,NormSep(Files[I].Path));
  If SIndex(Todos,IStr(I))>=0 Then Begin
   If LocalD<>'' Then
     Inc_:=JoinPath(JoinPath(JoinPath(JoinPath(LocalD,'.cache'),'huggingface'),'download'),
       NormSep(Files[I].Path)+'.incomplete')
   Else Inc_:=JoinPath(JoinPath(RepoDir,'blobs'),Files[I].Etag+'.incomplete');
   If Force Then DelFile(Inc_);
   Err:=FetchFile(ResolveFileUrl(Repo,RType,Commit,Files[I].Path),Tok,Dest,Inc_,
     Files[I].Path,Files[I].Size,Quiet);
   If Err<>'' Then Die(Err);
  End;
  If LocalD<>'' Then WriteLocalMeta(LocalD,Files[I].Path,Commit,Files[I].Etag);
 End;
 If(LocalD='')Then Begin
  MkDirs(SnapDir);
  If not IsCommitHash(Rev)Then
    WriteAll(JoinPath(JoinPath(RepoDir,'refs'),NormSep(Rev)),Commit);
 End;
 WriteLn(SnapDir);
End;

{ ------------------------------------------------------------------ }
{ Envoi (commit)                                                      }
{ ------------------------------------------------------------------ }

Function ShouldIgnoreUpload(Const P:AnsiString):Boolean;
Begin
 ShouldIgnoreUpload:=(P='.git')or StartsWith(P,'.git/')or(Pos('/.git/',P)>0)or
   StartsWith(P,'.cache/huggingface')or(P='.cache');
End;

{ cree le depot s'il n'existe pas ; renvoie l'identifiant complet }
Function CreateRepo(Const Repo,RType,Token:AnsiString;IsPrivate:Boolean;
  Const SpaceSdk:AnsiString;ExistOk:Boolean):AnsiString;
Var
 R:THttpReq;
 Body,Ns,Nm,U:AnsiString;
 P,J:LongInt;
Begin
 P:=Pos('/',Repo);
 If P>0 Then Begin Ns:=Copy(Repo,1,P-1);Nm:=Copy(Repo,P+1,Length(Repo));End
 Else Begin Ns:='';Nm:=Repo;End;
 Body:='{"name":'+JQ(Nm);
 If Ns<>'' Then Body:=Body+',"organization":'+JQ(Ns);
 If RType<>'model' Then Body:=Body+',"type":'+JQ(RType);
 If IsPrivate Then Body:=Body+',"private":true';
 If SpaceSdk<>'' Then Body:=Body+',"sdk":'+JQ(SpaceSdk);
 Body:=Body+'}';
 ApiCall(R,'POST','/api/repos/create',Body,Token);
 CreateRepo:=Repo;
 If ApiOk(R)Then Begin
  JReset;
  J:=JParse(R.RespBody);
  U:=JS(J,'url');
  P:=Pos('://',U);
  If P>0 Then Begin
   U:=Copy(U,P+3,Length(U));
   Delete(U,1,Pos('/',U));
   If StartsWith(U,TypePrefix(RType))Then Delete(U,1,Length(TypePrefix(RType)));
   If U<>'' Then CreateRepo:=U;
  End;
 End
 Else If(R.Status=409)and ExistOk Then Begin
  If Ns='' Then CreateRepo:=WhoamiName(Token)+'/'+Nm;
 End
 Else Die(ErrText(R));
End;

Function LfsHeaders(Const Extra:AnsiString):AnsiString;
Begin
 LfsHeaders:='Accept: application/vnd.git-lfs+json'#13#10+
   'Content-Type: application/vnd.git-lfs+json'#13#10+Extra;
End;

{ envoie un fichier LFS ; Actions = noeud "actions" de la reponse batch }
Procedure LfsUpload(Const Repo,RType,Token,Local,Oid:AnsiString;Size:Int64;Act:LongInt;
  Quiet:Boolean);
Var
 R:THttpReq;
 Up,Hd,Ver,C:LongInt;
 Href,Body,Key,Etags,Hdrs:AnsiString;
 Chunk,Ofs,Len:Int64;
 Keys:TSList;
 I:LongInt;
 Parts:TBuf;
Begin
 Up:=JGet(Act,'upload');
 If Up<0 Then Exit;
 Href:=JS(Up,'href');
 Hd:=JGet(Up,'header');
 Chunk:=0;
 If Hd>=0 Then Chunk:=ToInt(JS(Hd,'chunk_size'),0);
 If Chunk>0 Then Begin
  { envoi en plusieurs parties }
  SClear(Keys);
  C:=JP[Hd].First;
  While C>=0 do Begin
   Key:=JP[C].Key;
   If(Key<>'')and(Key[1]in['0'..'9'])Then SAdd(Keys,Key);
   C:=JP[C].Next;
  End;
  SSort(Keys);
  BufClear(Parts);
  Ofs:=0;
  For I:=0 to Keys.N-1 do Begin
   Len:=Chunk;
   If Ofs+Len>Size Then Len:=Size-Ofs;
   ReqInit(R,'PUT',JS(Hd,Keys.A[I]),'');
   R.BodyFile:=Local;R.BodyOfs:=Ofs;R.BodyLen:=Len;
   R.ShowProg:=not Quiet;
   R.ProgLabel:=BaseName(Local)+' part '+IStr(I+1)+'/'+IStr(Keys.N);
   HttpDo(R);
   If not ApiOk(R)Then Die('LFS part upload failed: '+ErrText(R));
   If I>0 Then BufAdd(Parts,',');
   BufAdd(Parts,'{"partNumber":'+IStr(I+1)+',"etag":'+JQ(CleanEtag(HeaderGet(R.RespHeaders,
     'etag')))+'}');
   Inc(Ofs,Len);
  End;
  Body:='{"oid":'+JQ(Oid)+',"parts":['+BufStr(Parts)+']}';
  ReqInit(R,'POST',Href,Token);
  R.Headers:=LfsHeaders('');
  R.BodyStr:=Body;
  HttpDo(R);
  If not ApiOk(R)Then Die('LFS multipart completion failed: '+ErrText(R));
 End
 Else Begin
  ReqInit(R,'PUT',Href,'');
  Hdrs:='';
  If Hd>=0 Then Begin
   C:=JP[Hd].First;
   While C>=0 do Begin
    Hdrs:=Hdrs+JP[C].Key+': '+JTxt(C)+#13#10;
    C:=JP[C].Next;
   End;
  End;
  R.Headers:=Hdrs;
  R.BodyFile:=Local;R.BodyOfs:=0;R.BodyLen:=Size;
  R.ShowProg:=not Quiet;
  R.ProgLabel:=BaseName(Local);
  HttpDo(R);
  If not ApiOk(R)Then Die('LFS upload failed: '+ErrText(R));
 End;
 Ver:=JGet(Act,'verify');
 If Ver>=0 Then Begin
  ReqInit(R,'POST',JS(Ver,'href'),Token);
  R.Headers:=LfsHeaders('');
  R.BodyStr:='{"oid":'+JQ(Oid)+',"size":'+IStr(Size)+'}';
  HttpDo(R);
  If not ApiOk(R)Then Die('LFS verify failed: '+ErrText(R));
 End;
End;

{ fabrique un commit ; Locals/Remotes : fichiers a ajouter, Dels : chemins a supprimer
  (un chemin se terminant par '/' est un dossier) ; renvoie l'URL du commit }
Function CommitFiles(Const Repo,RType,Rev,Token:AnsiString;Const Locals,Remotes,Dels:TSList;
  Const Msg,Desc:AnsiString;CreatePr,Quiet:Boolean):AnsiString;
Var
 R:THttpReq;
 Q,Body,Samp,Dat,Oid:AnsiString;
 Mode:TSList;
 Sz:Array of Int64;
 Ign:Array of Boolean;
 I,J,K,N,B,J2,X,Obj:LongInt;
 F:File;
 Chunk:LongInt;
 Nb:LongInt;
 Ops:TBuf;
 Lfs:TSList;
 Sha:TSList;
 NOps:LongInt;
 Fd:LongInt;
 Have:Boolean;
Begin
 N:=Locals.N;
 SetLength(Sz,N);SetLength(Ign,N);
 Q:='';
 If CreatePr Then Q:='?create_pr=1';
 SClear(Mode);
 For I:=0 to N-1 do Begin SAdd(Mode,'regular');Sz[I]:=FileSizeOf(Locals.A[I]);Ign[I]:=False;End;
 { 1. preupload : le serveur decide regular/lfs }
 I:=0;
 While I<N do Begin
  B:=N-I;If B>256 Then B:=256;
  Body:='{"files":[';
  For J:=I to I+B-1 do Begin
   Samp:='';
   Assign(F,Locals.A[J]);
   {$I-}Reset(F,1);{$I+}
   If IOResult<>0 Then Die('cannot read '+Locals.A[J]);
   K:=512;If Sz[J]<K Then K:=Sz[J];
   SetLength(Dat,K);
   If K>0 Then BlockRead(F,Dat[1],K);
   Close(F);
   If J>I Then Body:=Body+',';
   Body:=Body+'{"path":'+JQ(Remotes.A[J])+',"sample":'+JQ(B64Str(Dat))+',"size":'+
     IStr(Sz[J])+'}';
  End;
  Body:=Body+']}';
  ApiMust(R,'POST','/api/'+TypeApi(RType)+'/'+UrlEnc(Repo,True)+'/preupload/'+
    UrlEnc(Rev,False)+Q,Body,Token);
  JReset;
  Obj:=JParse(R.RespBody);
  X:=JGet(Obj,'files');
  For J2:=0 to JCnt(X)-1 do Begin
   Fd:=JAt(X,J2);
   For J:=I to I+B-1 do If Remotes.A[J]=JS(Fd,'path')Then Begin
    Mode.A[J]:=JS(Fd,'uploadMode');
    Ign[J]:=JB(Fd,'shouldIgnore');
   End;
  End;
  Inc(I,B);
 End;
 { 2. objets LFS }
 SClear(Lfs);SClear(Sha);
 For I:=0 to N-1 do If(Mode.A[I]='lfs')and not Ign[I]Then Begin
  If not Quiet Then WriteLn(StdErr,'Computing checksum of ',Remotes.A[I],'...');
  Oid:=HashFile(Locals.A[I],False);
  If Oid='' Then Die('cannot read '+Locals.A[I]);
  SAdd(Lfs,IStr(I));SAdd(Sha,Oid);
 End;
 I:=0;
 While I<Lfs.N do Begin
  B:=Lfs.N-I;If B>256 Then B:=256;
  Body:='{"operation":"upload","transfers":["basic","multipart"],"objects":[';
  For J:=I to I+B-1 do Begin
   If J>I Then Body:=Body+',';
   Body:=Body+'{"oid":'+JQ(Sha.A[J])+',"size":'+IStr(Sz[ToInt(Lfs.A[J],0)])+'}';
  End;
  Body:=Body+'],"hash_algo":"sha256","ref":{"name":'+JQ(Rev)+'}}';
  ReqInit(R,'POST',Endpoint+'/'+TypePrefix(RType)+UrlEnc(Repo,True)+
    '.git/info/lfs/objects/batch',Token);
  R.Headers:=LfsHeaders('');
  R.BodyStr:=Body;
  HttpDo(R);
  If not ApiOk(R)Then Die('LFS batch request failed: '+ErrText(R));
  JReset;
  Obj:=JParse(R.RespBody);
  X:=JGet(Obj,'objects');
  For J2:=0 to JCnt(X)-1 do Begin
   Fd:=JAt(X,J2);
   If JGet(Fd,'error')>=0 Then Die('LFS error for '+JS(Fd,'oid')+': '+JS(Fd,'error.message'));
   For J:=I to I+B-1 do If Sha.A[J]=JS(Fd,'oid')Then
    If JGet(Fd,'actions')>=0 Then
     LfsUpload(Repo,RType,Token,Locals.A[ToInt(Lfs.A[J],0)],Sha.A[J],
       Sz[ToInt(Lfs.A[J],0)],JGet(Fd,'actions'),Quiet);
  End;
  Inc(I,B);
 End;
 { 3. commit }
 BufClear(Ops);
 BufAdd(Ops,'{"key":"header","value":{"summary":'+JQ(Msg)+',"description":'+JQ(Desc)+'}}'#10);
 NOps:=0;
 For I:=0 to N-1 do If not Ign[I]Then Begin
  If Mode.A[I]='lfs' Then Begin
   J:=SIndex(Lfs,IStr(I));
   BufAdd(Ops,'{"key":"lfsFile","value":{"path":'+JQ(Remotes.A[I])+',"algo":"sha256","size":'+
     IStr(Sz[I])+',"oid":'+JQ(Sha.A[J])+'}}'#10);
  End
  Else Begin
   If not ReadAll(Locals.A[I],Dat)Then Die('cannot read '+Locals.A[I]);
   BufAdd(Ops,'{"key":"file","value":{"content":"');
   B64Add(Ops,Dat);
   BufAdd(Ops,'","path":'+JQ(Remotes.A[I])+',"encoding":"base64"}}'#10);
   Dat:='';
  End;
  Inc(NOps);
 End;
 For I:=0 to Dels.N-1 do Begin
  If EndsWith(Dels.A[I],'/')Then
   BufAdd(Ops,'{"key":"deletedFolder","value":{"path":'+JQ(Copy(Dels.A[I],1,
     Length(Dels.A[I])-1))+'}}'#10)
  Else BufAdd(Ops,'{"key":"deletedFile","value":{"path":'+JQ(Dels.A[I])+'}}'#10);
  Inc(NOps);
 End;
 If NOps=0 Then Begin
  Warn('no files to commit.');
  CommitFiles:=Endpoint+'/'+TypePrefix(RType)+Repo+'/tree/'+Rev;
  Exit;
 End;
 ReqInit(R,'POST',Endpoint+'/api/'+TypeApi(RType)+'/'+UrlEnc(Repo,True)+'/commit/'+
   UrlEnc(Rev,False)+Q,Token);
 R.Headers:='Content-Type: application/x-ndjson'#13#10;
 R.BodyStr:=BufStr(Ops);
 HttpDo(R);
 If not ApiOk(R)Then Die(ErrText(R));
 JReset;
 Obj:=JParse(R.RespBody);
 If JS(Obj,'pullRequestUrl')<>'' Then CommitFiles:=JS(Obj,'pullRequestUrl')
 Else If JS(Obj,'commitUrl')<>'' Then CommitFiles:=JS(Obj,'commitUrl')
 Else CommitFiles:=Endpoint+'/'+TypePrefix(RType)+Repo+'/tree/'+Rev;
End;

{ liste des fichiers du depot (chemins) pour --delete }
Procedure RemoteFileList(Const Repo,RType,Rev,Token:AnsiString;Var L:TSList);
Var
 Files:TRFiles;
 Commit:AnsiString;
 I:LongInt;
Begin
 SClear(L);
 FetchRepo(Repo,RType,Rev,Token,Commit,Files);
 For I:=0 to High(Files)do SAdd(L,Files[I].Path);
End;

Procedure CmdUpload;
Var
 Repo,RType,Rev,Tok,Local,InRepo,Msg,Desc,Url,Full:AnsiString;
 Allow,Deny,DelPat,Locals,Remotes,Dels,Rel,Remote:TSList;
 I,J:LongInt;
 IsDir,Quiet:Boolean;
 Base:AnsiString;
Begin
 CmdBegin('hf upload','Upload a file or a folder to the Hub. Recommended for single-commit uploads.',
   'REPO_ID [LOCAL_PATH] [PATH_IN_REPO]');
 CmdArg('REPO_ID','The ID of the repo to upload to (e.g. `username/repo-name`).');
 CmdArg('LOCAL_PATH','Local path to the file or folder to upload. Defaults to the current directory.');
 CmdArg('PATH_IN_REPO','Path of the file or folder in the repo. Defaults to the root of the repo.');
 AddTypeOpt;
 Opt('revision','','TEXT','An optional Git revision to push to. It can be a branch name or a PR reference.');
 Opt('private','','','Whether to create a private repo if repo doesn''t exist on the Hub.');
 Opt('include','','*TEXT','Glob patterns to match files to upload.');
 Opt('exclude','','*TEXT','Glob patterns to exclude from files to upload.');
 Opt('delete','','*TEXT','Glob patterns for file to be deleted from the repo while committing.');
 Opt('commit-message','','TEXT','The summary / title / first line of the generated commit.');
 Opt('commit-description','','TEXT','The description of the generated commit.');
 Opt('create-pr','','','Whether to upload content as a new Pull Request.');
 Opt('every','','FLOAT','Not supported by this clone.');
 AddTokenOpt;
 Opt('quiet','q','','Disable progress bars and warnings; print only the returned path.');
 ParseArgs(ArgStart);
 NeedArgs(1,3);
 If OptHas('every')Then Die('--every (scheduled uploads) is not supported by this clone.');
 Repo:=Pos1(0);RType:=RepoType;
 Rev:=OptGetDef('revision','main');
 Tok:=TokenOpt;
 Quiet:=OptHas('quiet');
 If Tok='' Then Die('Not logged in. Run `hf auth login` or pass --token.');
 If PosArgs.N>=2 Then Local:=Pos1(1) Else Local:='.';
 If not PathExists(Local,IsDir)Then Die('Local path does not exist: '+Local);
 OptList('include',Allow);OptList('exclude',Deny);OptList('delete',DelPat);
 SClear(Locals);SClear(Remotes);SClear(Dels);
 If IsDir Then Begin
  If PosArgs.N>=3 Then InRepo:=UnixSep(Pos1(2)) Else InRepo:='';
  While StartsWith(InRepo,'/')do Delete(InRepo,1,1);
  While EndsWith(InRepo,'/')do Delete(InRepo,Length(InRepo),1);
  WalkFiles(Local,'',Rel);
  SSort(Rel);
  For I:=0 to Rel.N-1 do If not ShouldIgnoreUpload(Rel.A[I])and
    Selected(Rel.A[I],Allow,Deny)Then Begin
   SAdd(Locals,JoinPath(AbsPath(Local),NormSep(Rel.A[I])));
   If InRepo='' Then SAdd(Remotes,Rel.A[I]) Else SAdd(Remotes,InRepo+'/'+Rel.A[I]);
  End;
 End
 Else Begin
  If PosArgs.N>=3 Then InRepo:=UnixSep(Pos1(2)) Else InRepo:=BaseName(Local);
  While StartsWith(InRepo,'/')do Delete(InRepo,1,1);
  If EndsWith(InRepo,'/')Then InRepo:=InRepo+BaseName(Local);
  SAdd(Locals,AbsPath(Local));
  SAdd(Remotes,InRepo);
 End;
 If(Locals.N=0)and(DelPat.N=0)Then Die('no file to upload (check the path and the --include / --exclude patterns).');
 Full:=CreateRepo(Repo,RType,Tok,OptHas('private'),'',True);
 If Full<>Repo Then Begin
  If not Quiet Then WriteLn(StdErr,'Repository: ',Full);
  Repo:=Full;
 End;
 If DelPat.N>0 Then Begin
  RemoteFileList(Repo,RType,Rev,Tok,Remote);
  For I:=0 to Remote.N-1 do Begin
   For J:=0 to DelPat.N-1 do If Glob(DelPat.A[J],Remote.A[I])and
     (SIndex(Remotes,Remote.A[I])<0)Then Begin
    SAdd(Dels,Remote.A[I]);Break;
   End;
  End;
 End;
 Msg:=OptGet('commit-message');
 If Msg='' Then Begin
  If IsDir Then Msg:='Upload folder using hf CLI' Else Msg:='Upload '+InRepo+' with hf CLI';
 End;
 Desc:=OptGet('commit-description');
 Url:=CommitFiles(Repo,RType,Rev,Tok,Locals,Remotes,Dels,Msg,Desc,OptHas('create-pr'),Quiet);
 WriteLn(Url);
End;

{ ------------------------------------------------------------------ }
{ Authentification                                                    }
{ ------------------------------------------------------------------ }

Procedure LoadTokens(Var Names,Vals:TSList);
Var
 S,Ln,Cur:AnsiString;
 L:TSList;
 I,P:LongInt;
Begin
 SClear(Names);SClear(Vals);
 If not ReadAll(StoredTokensPath,S)Then Exit;
 SplitStr(ReplaceAll(S,#13,''),#10,L);
 Cur:='';
 For I:=0 to L.N-1 do Begin
  Ln:=TrimStr(L.A[I]);
  If(Length(Ln)>2)and(Ln[1]='[')and(Ln[Length(Ln)]=']')Then Cur:=Copy(Ln,2,Length(Ln)-2)
  Else If(Cur<>'')and StartsWith(Ln,'hf_token')Then Begin
   P:=Pos('=',Ln);
   If P>0 Then Begin SAdd(Names,Cur);SAdd(Vals,TrimStr(Copy(Ln,P+1,Length(Ln))));End;
  End;
 End;
End;

Procedure SaveTokens(Const Names,Vals:TSList);
Var
 S:AnsiString;
 I:LongInt;
Begin
 S:='';
 For I:=0 to Names.N-1 do S:=S+'['+Names.A[I]+']'#10'hf_token='+Vals.A[I]+#10#10;
 If Names.N=0 Then Begin DelFile(StoredTokensPath);Exit;End;
 WriteAll(StoredTokensPath,S);
End;

Function MaskToken(Const T:AnsiString):AnsiString;
Begin
 If Length(T)<=8 Then MaskToken:='****'
 Else MaskToken:=Copy(T,1,3)+'****'+Copy(T,Length(T)-3,4);
End;

{$IFDEF WINDOWS}
Function GetStdHandle(N:LongWord):PtrUInt;stdcall;external 'kernel32.dll' name 'GetStdHandle';
Function GetConsoleMode(H:PtrUInt;Var Mode:LongWord):LongInt;stdcall;external
  'kernel32.dll' name 'GetConsoleMode';
Function SetConsoleMode(H:PtrUInt;Mode:LongWord):LongInt;stdcall;external
  'kernel32.dll' name 'SetConsoleMode';
{$ENDIF}

{ lit une ligne sans l'afficher (jeton) }
Function ReadSecret(Const Prompt:AnsiString):AnsiString;
Var
 S:AnsiString;
 {$IFDEF WINDOWS}
 H:PtrUInt;
 Mode:LongWord;
 Ok:Boolean;
 {$ENDIF}
Begin
 Write(Prompt);
 {$IFDEF WINDOWS}
 H:=GetStdHandle(LongWord(-10));
 Ok:=GetConsoleMode(H,Mode)<>0;
 If Ok Then SetConsoleMode(H,Mode and not LongWord(4));
 {$ELSE}
 DosError:=0;
 SwapVectors;Exec('/bin/stty','-echo');SwapVectors;
 {$ENDIF}
 ReadLn(S);
 {$IFDEF WINDOWS}
 If Ok Then SetConsoleMode(H,Mode);
 WriteLn;
 {$ELSE}
 DosError:=0;
 SwapVectors;Exec('/bin/stty','echo');SwapVectors;
 WriteLn;
 {$ENDIF}
 ReadSecret:=TrimStr(S);
End;

Procedure EnvTokenNote;
Begin
 If GetEnv('HF_TOKEN')<>'' Then
   WriteLn('Note: Environment variable`HF_TOKEN` is set and is the current active token '+
     'independently from the token you''ve just configured.');
End;

Procedure CmdAuthLogin;
Var
 Tok,Name:AnsiString;
 R:THttpReq;
 J,I:LongInt;
 Names,Vals:TSList;
Begin
 CmdBegin('hf auth login','Login using a token from huggingface.co/settings/tokens.','');
 AddTokenOpt;
 Opt('add-to-git-credential','','','Save to git credential helper (not supported by this clone).');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 Tok:=OptGet('token');
 If Tok='' Then Begin
  WriteLn('To log in, `hf` requires a token generated from https://huggingface.co/settings/tokens .');
  Tok:=ReadSecret('Enter your token (input will not be visible): ');
 End;
 If Tok='' Then Die('empty token.');
 ApiCall(R,'GET','/api/whoami-v2','',Tok);
 If not ApiOk(R)Then Begin
  If R.Status=401 Then Die('Invalid user token. The token is not valid.');
  Die(ErrText(R));
 End;
 JReset;
 J:=JParse(R.RespBody);
 Name:=JS(J,'auth.accessToken.displayName');
 If Name='' Then Name:=JS(J,'name');
 LoadTokens(Names,Vals);
 I:=SIndex(Names,Name);
 If I>=0 Then Vals.A[I]:=Tok Else Begin SAdd(Names,Name);SAdd(Vals,Tok);End;
 SaveTokens(Names,Vals);
 If not WriteAll(TokenPath,Tok)Then Die('cannot write '+TokenPath);
 If OptHas('add-to-git-credential')Then
   Warn('--add-to-git-credential is not supported by this clone; the token was not saved in git.');
 WriteLn('Login successful.');
 WriteLn('The current active token is: `'+Name+'`');
 EnvTokenNote;
End;

Procedure CmdAuthLogout;
Var
 Names,Vals:TSList;
 Nm:AnsiString;
 I:LongInt;
 Active:AnsiString;
Begin
 CmdBegin('hf auth logout','Logout from a specific token.','');
 Opt('token-name','','TEXT','Name of token to logout');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 Nm:=OptGet('token-name');
 LoadTokens(Names,Vals);
 Active:=ReadTokenFile;
 If Nm='' Then Begin
  DelFile(StoredTokensPath);
  DelFile(TokenPath);
  WriteLn('Successfully logged out from all access tokens.');
 End
 Else Begin
  I:=SIndex(Names,Nm);
  If I<0 Then Die('Access token '+Nm+' not found in '+StoredTokensPath);
  If Vals.A[I]=Active Then DelFile(TokenPath);
  Names.A[I]:=Names.A[Names.N-1];Vals.A[I]:=Vals.A[Vals.N-1];
  Dec(Names.N);Dec(Vals.N);
  SaveTokens(Names,Vals);
  WriteLn('Successfully logged out from access token: '+Nm+'.');
 End;
 EnvTokenNote;
End;

Procedure CmdAuthWhoami;
Var
 Tok:AnsiString;
 J,O,I:LongInt;
 S:AnsiString;
Begin
 CmdBegin('hf auth whoami','Find out which huggingface.co account you are logged in as.','');
 AddTokenOpt;
 Opt('format','','TEXT','Output format (table or json).');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 Tok:=TokenOpt;
 If Tok='' Then Die('Not logged in');
 J:=ApiJson('GET','/api/whoami-v2','',Tok);
 If LoStr(OptGet('format'))='json' Then Begin JPrint(J);Exit;End;
 WriteLn('user: ',JS(J,'name'));
 O:=JGet(J,'orgs');
 If JCnt(O)>0 Then Begin
  S:='';
  For I:=0 to JCnt(O)-1 do Begin
   If I>0 Then S:=S+',';
   S:=S+JS(JAt(O,I),'name');
  End;
  WriteLn('orgs: ',S);
 End;
End;

Procedure CmdAuthList;
Var
 Names,Vals:TSList;
 I:LongInt;
 Active:AnsiString;
Begin
 CmdBegin('hf auth list','List all stored access tokens.','');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 LoadTokens(Names,Vals);
 Active:=ReadTokenFile;
 If Names.N=0 Then Begin
  WriteLn('No access tokens found in ',StoredTokensPath,'.');
  Exit;
 End;
 TblBegin('  name'+#9+'token');
 For I:=0 to Names.N-1 do Begin
  If Vals.A[I]=Active Then TblRow('* '+Names.A[I]+#9+MaskToken(Vals.A[I]))
  Else TblRow('  '+Names.A[I]+#9+MaskToken(Vals.A[I]));
 End;
 TblPrint;
 EnvTokenNote;
End;

Procedure CmdAuthSwitch;
Var
 Names,Vals:TSList;
 Nm,S:AnsiString;
 I:LongInt;
Begin
 CmdBegin('hf auth switch','Switch between access tokens.','');
 Opt('token-name','','TEXT','Name of the token to switch to');
 Opt('add-to-git-credential','','','Not supported by this clone.');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 LoadTokens(Names,Vals);
 If Names.N=0 Then Die('No access tokens found. Run `hf auth login` first.');
 Nm:=OptGet('token-name');
 If Nm='' Then Begin
  For I:=0 to Names.N-1 do WriteLn(I+1,'. ',Names.A[I]);
  Write('Select a token (number or name): ');
  ReadLn(S);S:=TrimStr(S);
  If(ToInt(S,0)>=1)and(ToInt(S,0)<=Names.N)Then Nm:=Names.A[ToInt(S,0)-1] Else Nm:=S;
 End;
 I:=SIndex(Names,Nm);
 If I<0 Then Die('Access token '+Nm+' not found in '+StoredTokensPath);
 If not WriteAll(TokenPath,Vals.A[I])Then Die('cannot write '+TokenPath);
 WriteLn('The current active token is: `'+Nm+'`');
 EnvTokenNote;
End;

{ ------------------------------------------------------------------ }
{ models / datasets / spaces                                          }
{ ------------------------------------------------------------------ }

Function DateOnly(Const S:AnsiString):AnsiString;
Begin
 DateOnly:=Copy(S,1,10);
End;

Function SortParam(Const S:AnsiString):AnsiString;
Begin
 If S='created_at' Then SortParam:='createdAt'
 Else If S='last_modified' Then SortParam:='lastModified'
 Else If S='trending_score' Then SortParam:='trendingScore'
 Else SortParam:=S;
End;

Procedure CmdHubList(Const Kind:AnsiString);
Var
 Tok,Url,Fmt,Q,Sort,Nx:AnsiString;
 Limit,Got,PerPage,I,J,K:LongInt;
 Filt,Exp:TSList;
 R:THttpReq;
 Rows:TSList;
 JsB:TBuf;
 Quiet:Boolean;
 Obj:LongInt;
 Id:AnsiString;
Begin
 CmdBegin('hf '+Kind+'s ls','List '+Kind+'s on the Hub.','');
 Opt('search','','TEXT','Search query.');
 Opt('author','','TEXT','Filter by author or organization.');
 Opt('filter','','*TEXT','Filter by tags (e.g. ''text-classification''). Can be used multiple times.');
 Opt('sort','','TEXT','Sort key. One of downloads, likes, created_at, last_modified, trending_score.');
 Opt('limit','','INTEGER','Limit the number of results. [default: 10]');
 Opt('expand','','*TEXT','Properties to expand in the response. Can be used multiple times.');
 Opt('format','','TEXT','Output format: table or json. [default: table]');
 Opt('quiet','q','','Print only IDs, one per line.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 Tok:=TokenOpt;
 Limit:=OptInt('limit',10);
 Fmt:=LoStr(OptGetDef('format','table'));
 Quiet:=OptHas('quiet');
 OptList('filter',Filt);OptList('expand',Exp);
 Q:='?limit='+IStr(Limit);
 If Limit>1000 Then Q:='?limit=1000';
 If OptHas('search')Then Q:=Q+'&search='+UrlQ(OptGet('search'));
 If OptHas('author')Then Q:=Q+'&author='+UrlQ(OptGet('author'));
 For I:=0 to Filt.N-1 do Q:=Q+'&filter='+UrlQ(Filt.A[I]);
 Sort:=SortParam(OptGet('sort'));
 If Sort<>'' Then Q:=Q+'&sort='+UrlQ(Sort)+'&direction=-1';
 For I:=0 to Exp.N-1 do Q:=Q+'&expand%5B%5D='+UrlQ(Exp.A[I]);
 Url:='/api/'+TypeApi(Kind)+Q;
 SClear(Rows);BufClear(JsB);
 Got:=0;
 If Kind='model' Then TblBegin('ID'+#9+'DOWNLOADS'+#9+'LIKES'+#9+'TASK'+#9+'CREATED')
 Else If Kind='dataset' Then TblBegin('ID'+#9+'DOWNLOADS'+#9+'LIKES'+#9+'CREATED')
 Else TblBegin('ID'+#9+'LIKES'+#9+'SDK'+#9+'CREATED');
 Repeat
  ApiCall(R,'GET',Url,'',Tok);
  If not ApiOk(R)Then Die(ErrText(R));
  Nx:=LinkNext(R.RespHeaders);
  JReset;
  Obj:=JParse(R.RespBody);
  If(Obj<0)or(JP[Obj].Kind<>JK_ARR)Then Die('unexpected response from the Hub.');
  For I:=0 to JCnt(Obj)-1 do Begin
   If Got>=Limit Then Break;
   J:=JAt(Obj,I);
   Id:=JS(J,'id');
   If Id='' Then Id:=JS(J,'modelId');
   If Quiet Then WriteLn(Id)
   Else If Fmt='json' Then Begin
    If JsB.N>0 Then BufAdd(JsB,','#10);
    BufAdd(JsB,'  ');
    JDump(J,1,JsB);
   End
   Else If Kind='model' Then
     TblRow(Id+#9+JS(J,'downloads')+#9+JS(J,'likes')+#9+JS(J,'pipeline_tag')+#9+
       DateOnly(JS(J,'createdAt')))
   Else If Kind='dataset' Then
     TblRow(Id+#9+JS(J,'downloads')+#9+JS(J,'likes')+#9+DateOnly(JS(J,'createdAt')))
   Else TblRow(Id+#9+JS(J,'likes')+#9+JS(J,'sdk')+#9+DateOnly(JS(J,'createdAt')));
   Inc(Got);
  End;
  If(Got>=Limit)or(Nx='')Then Break;
  If Pos('://',Nx)=0 Then Url:=Nx Else Begin
   Url:=Nx;
   If StartsWith(Url,Endpoint)Then Delete(Url,1,Length(Endpoint));
  End;
 Until False;
 If Quiet Then Exit;
 If Fmt='json' Then Begin
  If JsB.N=0 Then WriteLn('[]') Else WriteLn('['#10,BufStr(JsB),#10']');
 End
 Else TblPrint;
End;

Procedure CmdHubInfo(Const Kind:AnsiString);
Var
 Tok,Path,Rev:AnsiString;
 Exp:TSList;
 I:LongInt;
 J:LongInt;
Begin
 CmdBegin('hf '+Kind+'s info','Get info about a '+Kind+' on the Hub. Output is in JSON format.',
   'REPO_ID');
 CmdArg('REPO_ID','The ID of the '+Kind+' (e.g. `username/repo-name`).');
 Opt('revision','','TEXT','Git revision id which can be a branch name, a tag, or a commit hash.');
 Opt('expand','','*TEXT','Properties to expand in the response. Can be used multiple times.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 Tok:=TokenOpt;
 Path:='/api/'+TypeApi(Kind)+'/'+UrlEnc(Pos1(0),True);
 Rev:=OptGet('revision');
 If Rev<>'' Then Path:=Path+'/revision/'+UrlEnc(Rev,False);
 OptList('expand',Exp);
 For I:=0 to Exp.N-1 do Begin
  If I=0 Then Path:=Path+'?' Else Path:=Path+'&';
  Path:=Path+'expand%5B%5D='+UrlQ(Exp.A[I]);
 End;
 J:=ApiJson('GET',Path,'',Tok);
 JPrint(J);
End;

{ ------------------------------------------------------------------ }
{ Cache local                                                         }
{ ------------------------------------------------------------------ }

Type
 TCRev = Record
  Hash,Refs,Path:AnsiString;
  Size:Int64;
  NFiles:LongInt;
  MTime:Int64;
 End;
 TCRepo = Record
  Id,Kind,Path,Refs:AnsiString;
  Size:Int64;
  NFiles:LongInt;
  MTime:Int64;
  Revs:Array of TCRev;
 End;

Var
 CRepos:Array of TCRepo;
 CNum:LongInt;

Procedure ScanCache(Const CacheD:AnsiString);
Var
 E,Sn:TEntries;
 I,J,K,P:LongInt;
 Nm,Rest,RD,Rf,H:AnsiString;
 Files,RefFiles:TSList;
 Rv:TCRev;
 Sz:Int64;
 MT:Int64;
 Rp:^TCRepo;
Begin
 SetLength(CRepos,0);CNum:=0;
 ListDir(CacheD,E);
 For I:=0 to High(E)do If E[I].IsDir Then Begin
  Nm:=E[I].Name;
  P:=Pos('--',Nm);
  If P=0 Then Continue;
  Rest:=Copy(Nm,1,P-1);
  If(Rest<>'models')and(Rest<>'datasets')and(Rest<>'spaces')Then Continue;
  SetLength(CRepos,CNum+1);
  Rp:=@CRepos[CNum];
  Inc(CNum);
  Rp^.Kind:=Copy(Rest,1,Length(Rest)-1);
  Rp^.Id:=ReplaceAll(Copy(Nm,P+2,Length(Nm)),'--','/');
  Rp^.Path:=JoinPath(CacheD,Nm);
  Rp^.Size:=0;Rp^.NFiles:=0;Rp^.MTime:=0;Rp^.Refs:='';
  SetLength(Rp^.Revs,0);
  RD:=Rp^.Path;
  { refs : nom -> commit }
  SClear(RefFiles);
  WalkFiles(JoinPath(RD,'refs'),'',RefFiles);
  ListDir(JoinPath(RD,'snapshots'),Sn);
  For J:=0 to High(Sn)do If Sn[J].IsDir Then Begin
   Rv.Hash:=Sn[J].Name;
   Rv.Path:=JoinPath(JoinPath(RD,'snapshots'),Sn[J].Name);
   Rv.Refs:='';Rv.Size:=0;Rv.NFiles:=0;Rv.MTime:=0;
   For K:=0 to RefFiles.N-1 do Begin
    If ReadAll(JoinPath(JoinPath(RD,'refs'),NormSep(RefFiles.A[K])),H)and
      (TrimStr(H)=Rv.Hash)Then Begin
     If Rv.Refs<>'' Then Rv.Refs:=Rv.Refs+', ';
     Rv.Refs:=Rv.Refs+RefFiles.A[K];
    End;
   End;
   SClear(Files);
   WalkFiles(Rv.Path,'',Files);
   For K:=0 to Files.N-1 do Begin
    Sz:=FileSizeOf(JoinPath(Rv.Path,NormSep(Files.A[K])));
    If Sz>0 Then Inc(Rv.Size,Sz);
    MT:=FileMTime(JoinPath(Rv.Path,NormSep(Files.A[K])));
    If MT>Rv.MTime Then Rv.MTime:=MT;
    Inc(Rv.NFiles);
   End;
   SetLength(Rp^.Revs,Length(Rp^.Revs)+1);
   Rp^.Revs[High(Rp^.Revs)]:=Rv;
   If Rv.MTime>Rp^.MTime Then Rp^.MTime:=Rv.MTime;
   If Rv.Refs<>'' Then Begin
    If Rp^.Refs<>'' Then Rp^.Refs:=Rp^.Refs+', ';
    Rp^.Refs:=Rp^.Refs+Rv.Refs;
   End;
  End;
  { taille du depot : blobs s'ils existent (liens symboliques), sinon somme des revisions }
  SClear(Files);
  WalkFiles(JoinPath(RD,'blobs'),'',Files);
  Sz:=0;
  For K:=0 to Files.N-1 do If not EndsWith(Files.A[K],'.incomplete')Then Begin
   Sz:=Sz+FileSizeOf(JoinPath(JoinPath(RD,'blobs'),NormSep(Files.A[K])));
  End;
  If Sz>0 Then Rp^.Size:=Sz
  Else For K:=0 to High(Rp^.Revs)do Inc(Rp^.Size,Rp^.Revs[K].Size);
  For K:=0 to High(Rp^.Revs)do Inc(Rp^.NFiles,Rp^.Revs[K].NFiles);
 End;
End;

Function ParseSize(Const S:AnsiString;Var V:Int64):Boolean;
Var
 I:LongInt;
 N:AnsiString;
 U:AnsiString;
 X:Double;
 Code:LongInt;
 M:Double;
Begin
 ParseSize:=False;
 I:=1;
 While(I<=Length(S))and(S[I]in['0'..'9','.'])do Inc(I);
 N:=Copy(S,1,I-1);U:=UpStr(TrimStr(Copy(S,I,Length(S))));
 Val(N,X,Code);
 If(Code<>0)or(N='')Then Exit;
 If(U='')or(U='B')Then M:=1
 Else If(U='K')or(U='KB')Then M:=1e3
 Else If(U='M')or(U='MB')Then M:=1e6
 Else If(U='G')or(U='GB')Then M:=1e9
 Else If(U='T')or(U='TB')Then M:=1e12
 Else Exit;
 V:=Round(X*M);
 ParseSize:=True;
End;

Function ParseDuration(Const S:AnsiString;Var V:Int64):Boolean;
Var
 I:LongInt;
 N,U:AnsiString;
 X:Double;
 Code:LongInt;
 M:Double;
Begin
 ParseDuration:=False;
 I:=1;
 While(I<=Length(S))and(S[I]in['0'..'9','.'])do Inc(I);
 N:=Copy(S,1,I-1);U:=LoStr(TrimStr(Copy(S,I,Length(S))));
 Val(N,X,Code);
 If(Code<>0)or(N='')Then Exit;
 If(U='s')Then M:=1 Else If U='m' Then M:=60 Else If U='h' Then M:=3600
 Else If U='d' Then M:=86400 Else If U='w' Then M:=604800 Else If U='mo' Then M:=2592000
 Else If U='y' Then M:=31536000 Else Exit;
 V:=Round(X*M);
 ParseDuration:=True;
End;

Function Compare(Op:AnsiString;A,B:Int64):Boolean;
Begin
 If Op='>' Then Compare:=A>B Else If Op='<' Then Compare:=A<B
 Else If Op='>=' Then Compare:=A>=B Else If Op='<=' Then Compare:=A<=B
 Else If Op='!=' Then Compare:=A<>B Else Compare:=A=B;
End;

{ filtre "size>1GB", "modified>1w", "type=model", "id=gpt*" }
Function CacheFilter(Const Expr:AnsiString;Const R:TCRepo):Boolean;
Var
 I,L:LongInt;
 Op,Key,Val_:AnsiString;
 V:Int64;
Begin
 CacheFilter:=True;
 I:=1;
 While(I<=Length(Expr))and not(Expr[I]in['>','<','=','!'])do Inc(I);
 If I>Length(Expr)Then Die('invalid filter '''+Expr+''' (expected key>value, e.g. size>1GB).');
 L:=1;
 If(I<Length(Expr))and(Expr[I+1]='=')Then L:=2;
 Key:=LoStr(TrimStr(Copy(Expr,1,I-1)));
 Op:=Copy(Expr,I,L);
 Val_:=TrimStr(Copy(Expr,I+L,Length(Expr)));
 If Key='size' Then Begin
  If not ParseSize(Val_,V)Then Die('invalid size in filter '''+Expr+'''.');
  CacheFilter:=Compare(Op,R.Size,V);
 End
 Else If(Key='modified')or(Key='accessed')Then Begin
  If not ParseDuration(Val_,V)Then Die('invalid duration in filter '''+Expr+'''.');
  CacheFilter:=Compare(Op,NowEpoch-R.MTime,V);
 End
 Else If Key='type' Then CacheFilter:=(R.Kind=LoStr(Val_))=(Op<>'!=')
 Else If Key='id' Then CacheFilter:=Glob(Val_,R.Id)=(Op<>'!=')
 Else Die('unknown filter key '''+Key+''' (use size, modified, accessed, type or id).');
End;

Function CacheArg:AnsiString;
Begin
 CacheArg:=OptGetDef('cache-dir',HubCache);
End;

Procedure CmdCacheLs;
Var
 I,J,K:LongInt;
 Fl:TSList;
 Ok,Revs,Quiet:Boolean;
 Fmt:AnsiString;
 B:TBuf;
 First:Boolean;
 Now_:Int64;
Begin
 CmdBegin('hf cache ls','List cached repositories or revisions.','');
 Opt('cache-dir','','TEXT','Cache directory to scan (defaults to Hugging Face cache).');
 Opt('revisions','','','Include revisions in the output instead of aggregated repositories.');
 Opt('filter','f','*TEXT','Filter entries (e.g. ''size>1GB'', ''modified>1w''). Can be used multiple times.');
 Opt('format','','TEXT','Output format: table or json. [default: table]');
 Opt('quiet','q','','Print only IDs (repo IDs or revision hashes).');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 ScanCache(CacheArg);
 OptList('filter',Fl);
 Revs:=OptHas('revisions');Quiet:=OptHas('quiet');
 Fmt:=LoStr(OptGetDef('format','table'));
 Now_:=NowEpoch;
 If Fmt='json' Then Begin BufClear(B);BufAdd(B,'[');End;
 First:=True;
 If not Revs Then TblBegin('ID'+#9+'SIZE'+#9+'FILES'+#9+'LAST_MODIFIED'+#9+'REFS')
 Else TblBegin('ID'+#9+'REVISION'+#9+'SIZE'+#9+'FILES'+#9+'LAST_MODIFIED'+#9+'REFS');
 For I:=0 to CNum-1 do Begin
  Ok:=True;
  For J:=0 to Fl.N-1 do If not CacheFilter(Fl.A[J],CRepos[I])Then Ok:=False;
  If not Ok Then Continue;
  If Quiet and not Revs Then Begin WriteLn(CRepos[I].Kind+'/'+CRepos[I].Id);Continue;End;
  If Fmt='json' Then Begin
   If not First Then BufAdd(B,',');
   First:=False;
   BufAdd(B,#10'  {"repo_id":'+JQ(CRepos[I].Id)+',"repo_type":'+JQ(CRepos[I].Kind)+
     ',"size_on_disk":'+IStr(CRepos[I].Size)+',"nb_files":'+IStr(CRepos[I].NFiles)+
     ',"repo_path":'+JQ(CRepos[I].Path)+',"last_modified":'+JQ(StampToStr(CRepos[I].MTime))+
     ',"revisions":[');
   For K:=0 to High(CRepos[I].Revs)do Begin
    If K>0 Then BufAdd(B,',');
    BufAdd(B,'{"commit_hash":'+JQ(CRepos[I].Revs[K].Hash)+',"size_on_disk":'+
      IStr(CRepos[I].Revs[K].Size)+',"nb_files":'+IStr(CRepos[I].Revs[K].NFiles)+
      ',"refs":'+JQ(CRepos[I].Revs[K].Refs)+'}');
   End;
   BufAdd(B,']}');
  End
  Else If not Revs Then
   TblRow(CRepos[I].Kind+'/'+CRepos[I].Id+#9+HumanSize(CRepos[I].Size)+#9+
     IStr(CRepos[I].NFiles)+#9+AgoStr(Now_-CRepos[I].MTime)+#9+CRepos[I].Refs)
  Else For K:=0 to High(CRepos[I].Revs)do Begin
   If Quiet Then WriteLn(CRepos[I].Revs[K].Hash)
   Else TblRow(CRepos[I].Kind+'/'+CRepos[I].Id+#9+Copy(CRepos[I].Revs[K].Hash,1,12)+#9+
     HumanSize(CRepos[I].Revs[K].Size)+#9+IStr(CRepos[I].Revs[K].NFiles)+#9+
     AgoStr(Now_-CRepos[I].Revs[K].MTime)+#9+CRepos[I].Revs[K].Refs);
  End;
 End;
 If Fmt='json' Then Begin BufAdd(B,#10']');WriteLn(BufStr(B));End
 Else If not Quiet Then Begin
  If TblRows.N=0 Then WriteLn('No cached entries found in ',CacheArg,'.')
  Else TblPrint;
 End;
End;

Function Confirm(Const Q:AnsiString):Boolean;
Var
 S:AnsiString;
Begin
 Write(Q,' [y/N]: ');
 S:='';
 ReadLn(S);
 S:=LoStr(TrimStr(S));
 Confirm:=(S='y')or(S='yes');
End;

Procedure CmdCacheRm;
Var
 I,J,K,N:LongInt;
 T,Id:AnsiString;
 Paths:TSList;
 Free_:Int64;
 Found:Boolean;
Begin
 CmdBegin('hf cache rm','Remove cached repositories or revisions.','TARGETS...');
 CmdArg('TARGETS','One or more repo IDs (e.g. model/bert-base-uncased) or revision hashes to delete.');
 Opt('cache-dir','','TEXT','Cache directory to scan (defaults to Hugging Face cache).');
 Opt('yes','y','','Skip confirmation prompt.');
 Opt('dry-run','','','Preview deletions without removing anything.');
 ParseArgs(ArgStart);
 NeedArgs(1,-1);
 ScanCache(CacheArg);
 SClear(Paths);Free_:=0;
 For N:=0 to PosArgs.N-1 do Begin
  T:=PosArgs.A[N];
  Found:=False;
  For I:=0 to CNum-1 do Begin
   Id:=CRepos[I].Kind+'/'+CRepos[I].Id;
   If(T=Id)or((Pos('/',T)>0)and(StartsWith(T,'model/')=False)and
     (StartsWith(T,'dataset/')=False)and(StartsWith(T,'space/')=False)and
     (CRepos[I].Kind='model')and(CRepos[I].Id=T))Then Begin
    SAdd(Paths,CRepos[I].Path);Inc(Free_,CRepos[I].Size);Found:=True;
   End
   Else For J:=0 to High(CRepos[I].Revs)do
    If(Length(T)>=6)and StartsWith(CRepos[I].Revs[J].Hash,T)Then Begin
     SAdd(Paths,CRepos[I].Revs[J].Path);Inc(Free_,CRepos[I].Revs[J].Size);Found:=True;
    End;
  End;
  If not Found Then Die('target not found in the cache: '+T);
 End;
 WriteLn('About to delete ',Paths.N,' item(s), freeing ',HumanSize(Free_),':');
 For K:=0 to Paths.N-1 do WriteLn('  ',Paths.A[K]);
 If OptHas('dry-run')Then Begin WriteLn('Dry run: nothing deleted.');Exit;End;
 If not OptHas('yes')Then If not Confirm('Proceed?')Then Begin WriteLn('Aborted.');Exit;End;
 For K:=0 to Paths.N-1 do RmTree(Paths.A[K]);
 WriteLn('Deleted ',Paths.N,' item(s), freed ',HumanSize(Free_),'.');
End;

Procedure CmdCachePrune;
Var
 I,J,K:LongInt;
 Paths:TSList;
 Free_:Int64;
Begin
 CmdBegin('hf cache prune','Remove detached revisions from the cache.','');
 Opt('cache-dir','','TEXT','Cache directory to scan (defaults to Hugging Face cache).');
 Opt('yes','y','','Skip confirmation prompt.');
 Opt('dry-run','','','Preview deletions without removing anything.');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 ScanCache(CacheArg);
 SClear(Paths);Free_:=0;
 For I:=0 to CNum-1 do For J:=0 to High(CRepos[I].Revs)do
  If CRepos[I].Revs[J].Refs='' Then Begin
   SAdd(Paths,CRepos[I].Revs[J].Path);Inc(Free_,CRepos[I].Revs[J].Size);
  End;
 If Paths.N=0 Then Begin WriteLn('No unreferenced revisions found. Nothing to prune.');Exit;End;
 WriteLn('About to delete ',Paths.N,' unreferenced revision(s), freeing ',HumanSize(Free_),':');
 For K:=0 to Paths.N-1 do WriteLn('  ',Paths.A[K]);
 If OptHas('dry-run')Then Begin WriteLn('Dry run: nothing deleted.');Exit;End;
 If not OptHas('yes')Then If not Confirm('Proceed?')Then Begin WriteLn('Aborted.');Exit;End;
 For K:=0 to Paths.N-1 do RmTree(Paths.A[K]);
 WriteLn('Deleted ',Paths.N,' revision(s), freed ',HumanSize(Free_),'.');
End;

Procedure CmdCacheVerify;
Var
 Repo,RType,Rev,Tok,Root,Commit,H,Got,Sx:AnsiString;
 Files:TRFiles;
 Local,Bad,Missing,Extra:TSList;
 I,Nok:LongInt;
 P:AnsiString;
 RefP:AnsiString;
 K_:LongInt;
 Nok2:Boolean;
Begin
 CmdBegin('hf cache verify','Verify checksums for a single repo revision from cache or a local directory.',
   'REPO_ID');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 AddTypeOpt;
 Opt('revision','','TEXT','Git revision id which can be a branch name, a tag, or a commit hash.');
 Opt('cache-dir','','TEXT','Cache directory to use when verifying files from the cache.');
 Opt('local-dir','','TEXT','If set, verify files under this directory instead of the cache.');
 Opt('fail-on-missing-files','','','Fail if some files exist on the remote but are missing locally.');
 Opt('fail-on-extra-files','','','Fail if some files exist locally but are not present on the remote revision.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 Repo:=Pos1(0);RType:=RepoType;Rev:=OptGetDef('revision','main');
 Tok:=TokenOpt;
 FetchRepo(Repo,RType,Rev,Tok,Commit,Files);
 If OptHas('local-dir')Then Root:=AbsPath(OptGet('local-dir'))
 Else Begin
  P:=RepoFolder(CacheArg,Repo,RType);
  If IsCommitHash(Rev)Then Commit:=Rev
  Else Begin
   RefP:=JoinPath(JoinPath(P,'refs'),NormSep(Rev));
   If not ReadAll(RefP,H)Then Die('revision '''+Rev+''' of '+Repo+' is not in the cache ('+P+').');
   Commit:=TrimStr(H);
  End;
  Root:=JoinPath(JoinPath(P,'snapshots'),Commit);
  If not DirExists_(Root)Then Die('snapshot '+Commit+' not found in '+P+'.');
 End;
 SClear(Bad);SClear(Missing);SClear(Extra);Nok:=0;
 For I:=0 to High(Files)do Begin
  P:=JoinPath(Root,NormSep(Files[I].Path));
  If not FileExists_(P)Then Begin SAdd(Missing,Files[I].Path);Continue;End;
  If Files[I].IsLfs Then Got:=HashFile(P,False) Else Got:=HashFile(P,True);
  If Got=Files[I].Etag Then Inc(Nok)
  Else SAdd(Bad,Files[I].Path+' (expected '+Copy(Files[I].Etag,1,12)+'..., got '+
    Copy(Got,1,12)+'...)');
 End;
 If OptHas('local-dir')Then Begin
  WalkFiles(Root,'',Local);
  For I:=0 to Local.N-1 do If not StartsWith(Local.A[I],'.cache/')Then Begin
   Sx:=Local.A[I];
   Nok2:=False;
   For K_:=0 to High(Files)do If Files[K_].Path=Sx Then Nok2:=True;
   If not Nok2 Then SAdd(Extra,Sx);
  End;
 End;
 If(Bad.N=0)and((Missing.N=0)or not OptHas('fail-on-missing-files'))and
   ((Extra.N=0)or not OptHas('fail-on-extra-files'))Then Begin
  WriteLn('Verified ',Nok,' file(s) for ''',Repo,''' (',RType,') in ',Root);
  If Bad.N=0 Then WriteLn('  All checksums match.');
  If Missing.N>0 Then WriteLn('  ',Missing.N,' file(s) missing locally (ignored).');
  If Extra.N>0 Then WriteLn('  ',Extra.N,' extra file(s) locally (ignored).');
 End
 Else Begin
  WriteLn('Verification failed for ''',Repo,''' (',RType,') in ',Root);
  For I:=0 to Bad.N-1 do WriteLn('  Checksum mismatch: ',Bad.A[I]);
  If OptHas('fail-on-missing-files')Then
   For I:=0 to Missing.N-1 do WriteLn('  Missing file: ',Missing.A[I]);
  If OptHas('fail-on-extra-files')Then
   For I:=0 to Extra.N-1 do WriteLn('  Extra file: ',Extra.A[I]);
  Halt(1);
 End;
End;

{ ------------------------------------------------------------------ }
{ repos                                                               }
{ ------------------------------------------------------------------ }

Procedure SplitRepo(Const Repo:AnsiString;Var Ns,Nm:AnsiString);
Var
 P:LongInt;
Begin
 P:=Pos('/',Repo);
 If P>0 Then Begin Ns:=Copy(Repo,1,P-1);Nm:=Copy(Repo,P+1,Length(Repo));End
 Else Begin Ns:='';Nm:=Repo;End;
End;

Function RepoUrl(Const Repo,RType:AnsiString):AnsiString;
Begin
 RepoUrl:=Endpoint+'/'+TypePrefix(RType)+Repo;
End;

Procedure CmdReposCreate;
Var
 Repo,RType,Tok,Full:AnsiString;
Begin
 CmdBegin('hf repos create','Create a new repo on the Hub.','REPO_ID');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 AddTypeOpt;
 Opt('space-sdk','','TEXT','Hugging Face Spaces SDK type. Required when --repo-type is ''space''.');
 Opt('private','','','Whether to create a private repo if repo doesn''t exist on the Hub.');
 Opt('exist-ok','','','Do not raise an error if repo already exists.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 Repo:=Pos1(0);RType:=RepoType;Tok:=TokenOpt;
 If Tok='' Then Die('Not logged in. Run `hf auth login` or pass --token.');
 If(RType='space')and(OptGet('space-sdk')='')Then
   UsageErr('--space-sdk is required when --repo-type is ''space''.');
 Full:=CreateRepo(Repo,RType,Tok,OptHas('private'),OptGet('space-sdk'),OptHas('exist-ok'));
 WriteLn('Successfully created ',Full,' on the Hub.');
 WriteLn('Your repo is now available at ',RepoUrl(Full,RType));
End;

Procedure CmdReposDelete;
Var
 Repo,RType,Tok,Ns,Nm,Body:AnsiString;
 R:THttpReq;
Begin
 CmdBegin('hf repos delete','Delete a repo from the Hub. This is an irreversible operation.','REPO_ID');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 AddTypeOpt;
 Opt('missing-ok','','','If set to True, do not raise an error if repo does not exist.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 Repo:=Pos1(0);RType:=RepoType;Tok:=TokenOpt;
 If Tok='' Then Die('Not logged in. Run `hf auth login` or pass --token.');
 SplitRepo(Repo,Ns,Nm);
 If Ns='' Then Begin Ns:=WhoamiName(Tok);End;
 Body:='{"name":'+JQ(Nm)+',"organization":'+JQ(Ns);
 If RType<>'model' Then Body:=Body+',"type":'+JQ(RType);
 Body:=Body+'}';
 ApiCall(R,'DELETE','/api/repos/delete',Body,Tok);
 If not ApiOk(R)Then Begin
  If(R.Status=404)and OptHas('missing-ok')Then Exit;
  Die(ErrText(R));
 End;
 WriteLn('Successfully deleted ',Ns+'/'+Nm,' on the Hub.');
End;

Procedure CmdReposMove;
Var
 RType,Tok,Body:AnsiString;
 R:THttpReq;
Begin
 CmdBegin('hf repos move','Move a repository from a namespace to another namespace.',
   'FROM_ID TO_ID');
 CmdArg('FROM_ID','The ID of the repo to move (e.g. `username/repo-name`).');
 CmdArg('TO_ID','The new ID of the repo (e.g. `username/new-repo-name`).');
 AddTypeOpt;
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 RType:=RepoType;Tok:=TokenOpt;
 If Tok='' Then Die('Not logged in. Run `hf auth login` or pass --token.');
 Body:='{"fromRepo":'+JQ(Pos1(0))+',"toRepo":'+JQ(Pos1(1));
 If RType<>'model' Then Body:=Body+',"type":'+JQ(RType);
 Body:=Body+'}';
 ApiMust(R,'POST','/api/repos/move',Body,Tok);
 WriteLn('Successfully moved ',Pos1(0),' to ',Pos1(1),' on the Hub.');
End;

Procedure CmdReposSettings;
Var
 Repo,RType,Tok,Body,G:AnsiString;
 R:THttpReq;
Begin
 CmdBegin('hf repos settings','Update the settings of a repository.','REPO_ID');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 AddTypeOpt;
 Opt('gated','','TEXT','The gated status for the repository (auto, manual or false).');
 Opt('private','','','Make the repository private.');
 Opt('public','','','Make the repository public.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 Repo:=Pos1(0);RType:=RepoType;Tok:=TokenOpt;
 If Tok='' Then Die('Not logged in. Run `hf auth login` or pass --token.');
 Body:='';
 If OptHas('private')Then Body:='"private":true';
 If OptHas('public')Then Body:='"private":false';
 If OptHas('gated')Then Begin
  G:=LoStr(OptGet('gated'));
  If Body<>'' Then Body:=Body+',';
  If G='false' Then Body:=Body+'"gated":false' Else If(G='auto')or(G='manual')Then
    Body:=Body+'"gated":'+JQ(G)
  Else UsageErr('Invalid value for ''--gated'': '''+G+''' (auto, manual or false).');
 End;
 If Body='' Then UsageErr('Nothing to update: pass --gated, --private or --public.');
 ApiMust(R,'PUT','/api/'+TypeApi(RType)+'/'+UrlEnc(Repo,True)+'/settings','{'+Body+'}',Tok);
 WriteLn('Successfully updated the settings of ',Repo,'.');
End;

Procedure CmdReposBranchCreate;
Var
 Repo,RType,Tok,Body:AnsiString;
 R:THttpReq;
Begin
 CmdBegin('hf repos branch create','Create a new branch for a repo on the Hub.','REPO_ID BRANCH');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 CmdArg('BRANCH','The name of the branch to create.');
 AddTypeOpt;
 Opt('revision','','TEXT','The git revision to create the branch from.');
 Opt('exist-ok','','','If set to True, do not raise an error if branch already exists.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 Repo:=Pos1(0);RType:=RepoType;Tok:=TokenOpt;
 Body:='';
 If OptGet('revision')<>'' Then Body:='{"startingPoint":'+JQ(OptGet('revision'))+'}';
 ApiCall(R,'POST','/api/'+TypeApi(RType)+'/'+UrlEnc(Repo,True)+'/branch/'+UrlEnc(Pos1(1),False),
   Body,Tok);
 If not ApiOk(R)Then Begin
  If(R.Status=409)and OptHas('exist-ok')Then Exit;
  Die(ErrText(R));
 End;
 WriteLn('Branch ''',Pos1(1),''' created on ',Repo,'.');
End;

Procedure CmdReposBranchDelete;
Var
 Repo,RType,Tok:AnsiString;
 R:THttpReq;
Begin
 CmdBegin('hf repos branch delete','Delete a branch from a repo on the Hub.','REPO_ID BRANCH');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 CmdArg('BRANCH','The name of the branch to delete.');
 AddTypeOpt;
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 Repo:=Pos1(0);RType:=RepoType;Tok:=TokenOpt;
 ApiMust(R,'DELETE','/api/'+TypeApi(RType)+'/'+UrlEnc(Repo,True)+'/branch/'+
   UrlEnc(Pos1(1),False),'',Tok);
 WriteLn('Branch ''',Pos1(1),''' deleted from ',Repo,'.');
End;

Procedure CmdReposTagCreate;
Var
 Repo,RType,Tok,Body:AnsiString;
 R:THttpReq;
Begin
 CmdBegin('hf repos tag create','Create a tag for a repo.','REPO_ID TAG');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 CmdArg('TAG','The name of the tag to create.');
 AddTypeOpt;
 Opt('message','m','TEXT','The description of the tag to create.');
 Opt('revision','','TEXT','The git revision to tag.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 Repo:=Pos1(0);RType:=RepoType;Tok:=TokenOpt;
 Body:='{"tag":'+JQ(Pos1(1));
 If OptGet('message')<>'' Then Body:=Body+',"message":'+JQ(OptGet('message'));
 Body:=Body+'}';
 ApiMust(R,'POST','/api/'+TypeApi(RType)+'/'+UrlEnc(Repo,True)+'/tag/'+
   UrlEnc(OptGetDef('revision','main'),False),Body,Tok);
 WriteLn('Tag ''',Pos1(1),''' created on ',Repo,'.');
End;

Procedure CmdReposTagDelete;
Var
 Repo,RType,Tok:AnsiString;
 R:THttpReq;
Begin
 CmdBegin('hf repos tag delete','Delete a tag from a repo.','REPO_ID TAG');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 CmdArg('TAG','The name of the tag to delete.');
 AddTypeOpt;
 Opt('yes','y','','Answer Yes to prompt automatically.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 Repo:=Pos1(0);RType:=RepoType;Tok:=TokenOpt;
 If not OptHas('yes')Then If not Confirm('Delete tag '''+Pos1(1)+''' from '+Repo+'?')Then Begin
  WriteLn('Aborted.');Exit;
 End;
 ApiMust(R,'DELETE','/api/'+TypeApi(RType)+'/'+UrlEnc(Repo,True)+'/tag/'+UrlEnc(Pos1(1),False),
   '',Tok);
 WriteLn('Tag ''',Pos1(1),''' deleted from ',Repo,'.');
End;

Procedure CmdReposTagList;
Var
 Repo,RType,Tok:AnsiString;
 J,T,I:LongInt;
Begin
 CmdBegin('hf repos tag list','List tags for a repo.','REPO_ID');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 AddTypeOpt;
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 Repo:=Pos1(0);RType:=RepoType;Tok:=TokenOpt;
 J:=ApiJson('GET','/api/'+TypeApi(RType)+'/'+UrlEnc(Repo,True)+'/refs','',Tok);
 T:=JGet(J,'tags');
 If JCnt(T)=0 Then Begin WriteLn('No tags found for ',Repo,'.');Exit;End;
 For I:=0 to JCnt(T)-1 do WriteLn(JS(JAt(T,I),'name'));
End;

Procedure CmdReposDeleteFiles;
Var
 Repo,RType,Tok,Rev,Url:AnsiString;
 Remote,Dels,Pat,NoL:TSList;
 I,J:LongInt;
Begin
 CmdBegin('hf repos delete-files','Delete files from a repo on the Hub.','REPO_ID PATTERNS...');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 CmdArg('PATTERNS','Glob patterns to match files to delete.');
 AddTypeOpt;
 Opt('revision','','TEXT','An optional Git revision to delete files from.');
 Opt('commit-message','','TEXT','The summary / title / first line of the generated commit.');
 Opt('commit-description','','TEXT','The description of the generated commit.');
 Opt('create-pr','','','Whether to create a Pull Request from the changes.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(2,-1);
 Repo:=Pos1(0);RType:=RepoType;Tok:=TokenOpt;Rev:=OptGetDef('revision','main');
 If Tok='' Then Die('Not logged in. Run `hf auth login` or pass --token.');
 RemoteFileList(Repo,RType,Rev,Tok,Remote);
 SClear(Dels);SClear(NoL);
 For I:=0 to Remote.N-1 do
  For J:=1 to PosArgs.N-1 do If Glob(PosArgs.A[J],Remote.A[I])Then Begin
   SAdd(Dels,Remote.A[I]);Break;
  End;
 If Dels.N=0 Then Begin WriteLn('No file matches the given patterns. Nothing to delete.');Exit;End;
 Url:=CommitFiles(Repo,RType,Rev,Tok,NoL,NoL,Dels,
   OptGetDef('commit-message','Delete files using hf CLI'),OptGet('commit-description'),
   OptHas('create-pr'),True);
 WriteLn(Url);
End;

{ ------------------------------------------------------------------ }
{ collections                                                         }
{ ------------------------------------------------------------------ }

Procedure CmdCollectionsLs;
Var
 Tok,Q,Fmt:AnsiString;
 J,I:LongInt;
 Quiet:Boolean;
Begin
 CmdBegin('hf collections ls','List collections on the Hub.','');
 Opt('owner','','TEXT','Filter by owner username or organization.');
 Opt('item','','TEXT','Filter collections containing a specific item (e.g. models/gpt2).');
 Opt('sort','','TEXT','Sort results by lastModified, trending or upvotes.');
 Opt('limit','','INTEGER','Limit the number of results. [default: 10]');
 Opt('format','','TEXT','Output format: table or json. [default: table]');
 Opt('quiet','q','','Print only slugs.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 Tok:=TokenOpt;
 Fmt:=LoStr(OptGetDef('format','table'));
 Quiet:=OptHas('quiet');
 Q:='?limit='+IStr(OptInt('limit',10));
 If OptHas('owner')Then Q:=Q+'&owner='+UrlQ(OptGet('owner'));
 If OptHas('item')Then Q:=Q+'&item='+UrlQ(OptGet('item'));
 If OptHas('sort')Then Q:=Q+'&sort='+UrlQ(OptGet('sort'));
 J:=ApiJson('GET','/api/collections'+Q,'',Tok);
 If Fmt='json' Then Begin JPrint(J);Exit;End;
 TblBegin('SLUG'+#9+'TITLE'+#9+'UPVOTES'+#9+'LAST_UPDATED');
 For I:=0 to JCnt(J)-1 do Begin
  If Quiet Then WriteLn(JS(JAt(J,I),'slug'))
  Else TblRow(JS(JAt(J,I),'slug')+#9+JS(JAt(J,I),'title')+#9+JS(JAt(J,I),'upvotes')+#9+
    DateOnly(JS(JAt(J,I),'lastUpdated')));
 End;
 If not Quiet Then TblPrint;
End;

Procedure CmdCollectionsInfo;
Begin
 CmdBegin('hf collections info','Get info about a collection on the Hub. Output is in JSON format.',
   'COLLECTION_SLUG');
 CmdArg('COLLECTION_SLUG','The collection slug (e.g. `username/collection-slug-123abc`).');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 JPrint(ApiJson('GET','/api/collections/'+UrlEnc(Pos1(0),True),'',TokenOpt));
End;

Procedure CmdCollectionsCreate;
Var
 Tok,Ns,Body:AnsiString;
 R:THttpReq;
 J:LongInt;
Begin
 CmdBegin('hf collections create','Create a new collection on the Hub.','TITLE');
 CmdArg('TITLE','The title of the collection.');
 Opt('namespace','','TEXT','The namespace of the collection (defaults to the authenticated user).');
 Opt('description','','TEXT','The description of the collection.');
 Opt('private','','','Create a private collection.');
 Opt('exists-ok','','','Do not raise an error if the collection already exists.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 Tok:=TokenOpt;
 If Tok='' Then Die('Not logged in. Run `hf auth login` or pass --token.');
 Ns:=OptGet('namespace');
 If Ns='' Then Ns:=WhoamiName(Tok);
 Body:='{"title":'+JQ(Pos1(0))+',"namespace":'+JQ(Ns)+',"private":'+JBool(OptHas('private'));
 If OptGet('description')<>'' Then Body:=Body+',"description":'+JQ(OptGet('description'));
 Body:=Body+'}';
 ApiCall(R,'POST','/api/collections',Body,Tok);
 If not ApiOk(R)Then Begin
  If(R.Status=409)and OptHas('exists-ok')Then Begin
   JReset;J:=JParse(R.RespBody);
   WriteLn(Endpoint,'/collections/',JS(J,'slug'));Exit;
  End;
  Die(ErrText(R));
 End;
 JReset;J:=JParse(R.RespBody);
 WriteLn('Collection created: ',Endpoint,'/collections/',JS(J,'slug'));
End;

Procedure CmdCollectionsDelete;
Var
 R:THttpReq;
Begin
 CmdBegin('hf collections delete','Delete a collection from the Hub.','COLLECTION_SLUG');
 CmdArg('COLLECTION_SLUG','The collection slug (e.g. `username/collection-slug-123abc`).');
 Opt('missing-ok','','','Do not raise an error if the collection does not exist.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 ApiCall(R,'DELETE','/api/collections/'+UrlEnc(Pos1(0),True),'',TokenOpt);
 If not ApiOk(R)Then Begin
  If(R.Status=404)and OptHas('missing-ok')Then Exit;
  Die(ErrText(R));
 End;
 WriteLn('Collection deleted: ',Pos1(0));
End;

Procedure CmdCollectionsAddItem;
Var
 T,Body:AnsiString;
 R:THttpReq;
Begin
 CmdBegin('hf collections add-item','Add an item to a collection.','COLLECTION_SLUG ITEM_ID [ITEM_TYPE]');
 CmdArg('COLLECTION_SLUG','The collection slug (e.g. `username/collection-slug-123abc`).');
 CmdArg('ITEM_ID','The ID of the item to add (e.g. `username/repo-name`).');
 CmdArg('ITEM_TYPE','Type of item: model, dataset, space, paper or collection. [default: model]');
 Opt('note','','TEXT','A note to attach to the item (max 500 characters).');
 Opt('exists-ok','','','Do not raise an error if the item is already in the collection.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(2,3);
 T:=LoStr(Pos1(2));
 If T='' Then T:='model';
 Body:='{"item":{"id":'+JQ(Pos1(1))+',"type":'+JQ(T)+'}';
 If OptGet('note')<>'' Then Body:=Body+',"note":'+JQ(OptGet('note'));
 Body:=Body+'}';
 ApiCall(R,'POST','/api/collections/'+UrlEnc(Pos1(0),True)+'/items',Body,TokenOpt);
 If not ApiOk(R)Then Begin
  If(R.Status=409)and OptHas('exists-ok')Then Exit;
  Die(ErrText(R));
 End;
 WriteLn('Item added to collection: ',Endpoint,'/collections/',Pos1(0));
End;

Procedure CmdCollectionsDeleteItem;
Var
 R:THttpReq;
Begin
 CmdBegin('hf collections delete-item','Delete an item from a collection.',
   'COLLECTION_SLUG ITEM_OBJECT_ID');
 CmdArg('COLLECTION_SLUG','The collection slug (e.g. `username/collection-slug-123abc`).');
 CmdArg('ITEM_OBJECT_ID','The item object id (as shown by `hf collections info`).');
 Opt('missing-ok','','','Do not raise an error if the item does not exist.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 ApiCall(R,'DELETE','/api/collections/'+UrlEnc(Pos1(0),True)+'/items/'+UrlEnc(Pos1(1),False),
   '',TokenOpt);
 If not ApiOk(R)Then Begin
  If(R.Status=404)and OptHas('missing-ok')Then Exit;
  Die(ErrText(R));
 End;
 WriteLn('Item deleted from collection: ',Pos1(0));
End;

{ ------------------------------------------------------------------ }
{ papers                                                              }
{ ------------------------------------------------------------------ }

Procedure PaperRows(J:LongInt;Fmt:AnsiString);
Var
 I,P:LongInt;
Begin
 If Fmt='json' Then Begin JPrint(J);Exit;End;
 TblBegin('ID'+#9+'TITLE'+#9+'UPVOTES');
 For I:=0 to JCnt(J)-1 do Begin
  P:=JGet(JAt(J,I),'paper');
  If P<0 Then P:=JAt(J,I);
  TblRow(JS(P,'id')+#9+JS(P,'title')+#9+JS(P,'upvotes'));
 End;
 TblPrint;
End;

Procedure CmdPapersLs;
Var
 Q:AnsiString;
Begin
 CmdBegin('hf papers ls','List daily papers on the Hub.','');
 Opt('date','','TEXT','Date in ISO format (YYYY-MM-DD).');
 Opt('sort','','TEXT','Sort order: publishedAt or trending.');
 Opt('limit','','INTEGER','Limit the number of results. [default: 50]');
 Opt('format','','TEXT','Output format: table or json. [default: table]');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 Q:='?limit='+IStr(OptInt('limit',50));
 If OptHas('date')Then Q:=Q+'&date='+UrlQ(OptGet('date'));
 If OptHas('sort')Then Q:=Q+'&sort='+UrlQ(OptGet('sort'));
 PaperRows(ApiJson('GET','/api/daily_papers'+Q,'',TokenOpt),LoStr(OptGetDef('format','table')));
End;

Procedure CmdPapersSearch;
Begin
 CmdBegin('hf papers search','Search papers on the Hub.','QUERY');
 CmdArg('QUERY','Search query.');
 Opt('limit','','INTEGER','Limit the number of results. [default: 10]');
 Opt('format','','TEXT','Output format: table or json. [default: table]');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 PaperRows(ApiJson('GET','/api/papers/search?q='+UrlQ(Pos1(0))+'&limit='+IStr(OptInt('limit',10)),
   '',TokenOpt),LoStr(OptGetDef('format','table')));
End;

Procedure CmdPapersInfo;
Begin
 CmdBegin('hf papers info','Get info about a paper on the Hub. Output is in JSON format.','PAPER_ID');
 CmdArg('PAPER_ID','The arXiv id of the paper (e.g. `2307.09288`).');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 JPrint(ApiJson('GET','/api/papers/'+UrlEnc(Pos1(0),False),'',TokenOpt));
End;

{ ------------------------------------------------------------------ }
{ discussions                                                         }
{ ------------------------------------------------------------------ }

Function DiscBase(Const Repo,RType:AnsiString):AnsiString;
Begin
 DiscBase:='/api/'+TypeApi(RType)+'/'+UrlEnc(Repo,True)+'/discussions';
End;

Procedure CmdDiscLs;
Var
 Repo,RType,Q,Fmt:AnsiString;
 J,D,I:LongInt;
Begin
 CmdBegin('hf discussions ls','List discussions and pull requests on a repo.','REPO_ID');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 AddTypeOpt;
 Opt('status','s','TEXT','Filter by status (open, closed, all). [default: open]');
 Opt('kind','k','TEXT','Filter by kind (discussion, pull_request, all). [default: all]');
 Opt('author','','TEXT','Filter by author.');
 Opt('format','','TEXT','Output format: table or json. [default: table]');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 Repo:=Pos1(0);RType:=RepoType;
 Fmt:=LoStr(OptGetDef('format','table'));
 Q:='?status='+UrlQ(LoStr(OptGetDef('status','open')))+'&type='+UrlQ(LoStr(OptGetDef('kind','all')));
 If OptHas('author')Then Q:=Q+'&author='+UrlQ(OptGet('author'));
 J:=ApiJson('GET',DiscBase(Repo,RType)+Q,'',TokenOpt);
 D:=JGet(J,'discussions');
 If Fmt='json' Then Begin JPrint(D);Exit;End;
 TblBegin('NUM'+#9+'TITLE'+#9+'KIND'+#9+'STATUS'+#9+'AUTHOR'+#9+'CREATED');
 For I:=0 to JCnt(D)-1 do Begin
  TblRow(JS(JAt(D,I),'num')+#9+JS(JAt(D,I),'title')+#9+
    IfThen_(JB(JAt(D,I),'isPullRequest'),'pr','discussion')+#9+JS(JAt(D,I),'status')+#9+
    JS(JAt(D,I),'author.name')+#9+DateOnly(JS(JAt(D,I),'createdAt')));
 End;
 TblPrint;
End;

Procedure CmdDiscInfo;
Begin
 CmdBegin('hf discussions info','Get info about a discussion or pull request. Output is in JSON format.',
   'REPO_ID NUM');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 CmdArg('NUM','The discussion number.');
 AddTypeOpt;
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 JPrint(ApiJson('GET',DiscBase(Pos1(0),RepoType)+'/'+UrlEnc(Pos1(1),False),'',TokenOpt));
End;

Procedure CmdDiscCreate;
Var
 Repo,RType,Tok,Body:AnsiString;
 R:THttpReq;
 J:LongInt;
Begin
 CmdBegin('hf discussions create','Create a new discussion or pull request on a repo.','REPO_ID');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 AddTypeOpt;
 Opt('title','','TEXT','The title of the discussion or pull request.');
 Opt('body','','TEXT','The description of the discussion or pull request.');
 Opt('pull-request','','','Create a pull request instead of a discussion.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 Repo:=Pos1(0);RType:=RepoType;Tok:=TokenOpt;
 If OptGet('title')='' Then UsageErr('Missing option ''--title''.');
 Body:='{"title":'+JQ(OptGet('title'))+',"description":'+JQ(OptGet('body'))+
   ',"pullRequest":'+JBool(OptHas('pull-request'))+'}';
 ApiMust(R,'POST',DiscBase(Repo,RType),Body,Tok);
 JReset;J:=JParse(R.RespBody);
 WriteLn(RepoUrl(Repo,RType),'/discussions/',JS(J,'num'));
End;

Procedure CmdDiscComment;
Var
 R:THttpReq;
Begin
 CmdBegin('hf discussions comment','Comment on a discussion or pull request.','REPO_ID NUM');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 CmdArg('NUM','The discussion number.');
 AddTypeOpt;
 Opt('body','','TEXT','The comment text.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 If OptGet('body')='' Then UsageErr('Missing option ''--body''.');
 ApiMust(R,'POST',DiscBase(Pos1(0),RepoType)+'/'+UrlEnc(Pos1(1),False)+'/comment',
   '{"comment":'+JQ(OptGet('body'))+'}',TokenOpt);
 WriteLn('Comment posted on ',RepoUrl(Pos1(0),RepoType),'/discussions/',Pos1(1));
End;

Procedure DiscStatus(Const Cmd,Status,Desc:AnsiString);
Var
 R:THttpReq;
Begin
 CmdBegin('hf discussions '+Cmd,Desc,'REPO_ID NUM');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 CmdArg('NUM','The discussion number.');
 AddTypeOpt;
 Opt('comment','','TEXT','An optional comment to post with the change.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 ApiMust(R,'POST',DiscBase(Pos1(0),RepoType)+'/'+UrlEnc(Pos1(1),False)+'/status',
   '{"status":'+JQ(Status)+',"comment":'+JQ(OptGet('comment'))+'}',TokenOpt);
 WriteLn('Discussion ',Pos1(1),' is now ',Status,'.');
End;

Procedure CmdDiscMerge;
Var
 R:THttpReq;
Begin
 CmdBegin('hf discussions merge','Merge a pull request.','REPO_ID NUM');
 CmdArg('REPO_ID','The ID of the repo (e.g. `username/repo-name`).');
 CmdArg('NUM','The pull request number.');
 AddTypeOpt;
 Opt('comment','','TEXT','An optional comment to post with the merge.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 ApiMust(R,'POST',DiscBase(Pos1(0),RepoType)+'/'+UrlEnc(Pos1(1),False)+'/merge',
   '{"comment":'+JQ(OptGet('comment'))+'}',TokenOpt);
 WriteLn('Pull request ',Pos1(1),' merged.');
End;

{ ------------------------------------------------------------------ }
{ endpoints (Inference Endpoints)                                     }
{ ------------------------------------------------------------------ }

Function EpBase(Const Tok:AnsiString):AnsiString;
Var
 Ns:AnsiString;
Begin
 Ns:=OptGet('namespace');
 If Ns='' Then Ns:=WhoamiName(Tok);
 EpBase:=EndpointsApi+'/'+Ns;
End;

Procedure EpCall(Var R:THttpReq;Const Method,Url,Tok:AnsiString);
Begin
 ReqInit(R,Method,Url,Tok);
 HttpDo(R);
 If not ApiOk(R)Then Die(ErrText(R));
End;

Procedure CmdEpLs;
Var
 Tok:AnsiString;
 R:THttpReq;
 J,L,I:LongInt;
Begin
 CmdBegin('hf endpoints ls','Lists all Inference Endpoints for the given namespace.','');
 Opt('namespace','','TEXT','The namespace associated with the Inference Endpoints. Defaults to the current user.');
 Opt('format','','TEXT','Output format: table or json. [default: table]');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 Tok:=TokenOpt;
 EpCall(R,'GET',EpBase(Tok),Tok);
 JReset;J:=JParse(R.RespBody);
 L:=JGet(J,'items');
 If L<0 Then L:=J;
 If LoStr(OptGet('format'))='json' Then Begin JPrint(L);Exit;End;
 TblBegin('NAME'+#9+'MODEL'+#9+'TASK'+#9+'STATE'+#9+'INSTANCE');
 For I:=0 to JCnt(L)-1 do
  TblRow(JS(JAt(L,I),'name')+#9+JS(JAt(L,I),'model.repository')+#9+JS(JAt(L,I),'model.task')+
    #9+JS(JAt(L,I),'status.state')+#9+JS(JAt(L,I),'compute.instanceType')+' '+
    JS(JAt(L,I),'compute.instanceSize'));
 TblPrint;
End;

Procedure EpSimple(Const Cmd,Verb,Sub,Desc:AnsiString);
Var
 Tok:AnsiString;
 R:THttpReq;
 J:LongInt;
Begin
 CmdBegin('hf endpoints '+Cmd,Desc,'NAME');
 CmdArg('NAME','Endpoint name.');
 Opt('namespace','','TEXT','The namespace associated with the Inference Endpoint. Defaults to the current user.');
 If Cmd='delete' Then Opt('yes','y','','Skip confirmation prompts.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 Tok:=TokenOpt;
 If(Cmd='delete')and not OptHas('yes')Then
  If not Confirm('Delete endpoint '''+Pos1(0)+'''?')Then Begin WriteLn('Aborted.');Exit;End;
 EpCall(R,Verb,EpBase(Tok)+'/'+UrlEnc(Pos1(0),False)+Sub,Tok);
 If Cmd='describe' Then Begin
  JReset;J:=JParse(R.RespBody);JPrint(J);
 End
 Else If Cmd='delete' Then WriteLn('Deleted ''',Pos1(0),'''.')
 Else Begin
  JReset;J:=JParse(R.RespBody);
  WriteLn('Endpoint ''',Pos1(0),''': ',Cmd,' requested (state: ',JS(J,'status.state'),').');
 End;
End;

{ ------------------------------------------------------------------ }
{ jobs                                                                }
{ ------------------------------------------------------------------ }

Function KvJson(Const L:TSList):AnsiString;
Var
 I,P:LongInt;
 S,K,V:AnsiString;
Begin
 S:='{';
 For I:=0 to L.N-1 do Begin
  P:=Pos('=',L.A[I]);
  If P>0 Then Begin K:=Copy(L.A[I],1,P-1);V:=Copy(L.A[I],P+1,Length(L.A[I]));End
  Else Begin K:=L.A[I];V:=GetEnv(K);End;
  If I>0 Then S:=S+',';
  S:=S+JQ(K)+':'+JQ(V);
 End;
 KvJson:=S+'}';
End;

Function JobNs(Const Tok:AnsiString):AnsiString;
Begin
 JobNs:=OptGet('namespace');
 If JobNs='' Then JobNs:=WhoamiName(Tok);
End;

Function ParseTimeout(Const S:AnsiString):Int64;
Var
 N:AnsiString;
 U:Char;
 V:Int64;
Begin
 ParseTimeout:=0;
 If S='' Then Exit;
 U:=S[Length(S)];
 If U in['s','m','h','d']Then N:=Copy(S,1,Length(S)-1) Else Begin N:=S;U:='s';End;
 V:=ToInt(N,-1);
 If V<0 Then UsageErr('Invalid timeout '''+S+''' (examples: 300, 5m, 2h).');
 Case U of
  'm':V:=V*60;
  'h':V:=V*3600;
  'd':V:=V*86400;
 End;
 ParseTimeout:=V;
End;

Procedure PrintJobLogs(Const Ns,Id,Tok:AnsiString);
Var
 R:THttpReq;
 L:TSList;
 I,J:LongInt;
 Ln:AnsiString;
Begin
 ReqInit(R,'GET',Endpoint+'/api/jobs/'+Ns+'/'+Id+'/logs',Tok);
 HttpDo(R);
 If not ApiOk(R)Then Die(ErrText(R));
 SplitStr(ReplaceAll(R.RespBody,#13,''),#10,L);
 For I:=0 to L.N-1 do Begin
  Ln:=L.A[I];
  If StartsWith(Ln,'data:')Then Begin
   Delete(Ln,1,5);Ln:=TrimStr(Ln);
   JReset;J:=JParse(Ln);
   If(J>=0)and(JGet(J,'data')>=0)Then WriteLn(JS(J,'data')) Else WriteLn(Ln);
  End
  Else If(Ln<>'')and not StartsWith(Ln,':')and not StartsWith(Ln,'event:')Then WriteLn(Ln);
 End;
End;

Procedure CmdJobsRun;
Var
 Tok,Ns,Body,Img:AnsiString;
 Env,Sec:TSList;
 I:LongInt;
 R:THttpReq;
 J:LongInt;
 Cmd:AnsiString;
 T:Int64;
 Id:AnsiString;
Begin
 CmdBegin('hf jobs run','Run a Job.','IMAGE COMMAND...');
 CmdArg('IMAGE','The Docker image to use (or a Space URL).');
 CmdArg('COMMAND','The command to run.');
 StopAfter:=1;
 Opt('flavor','','TEXT','Flavor for the hardware, as in HF Spaces. [default: cpu-basic]');
 Opt('env','e','*TEXT','Set environment variables. E.g. --env ENV=value');
 Opt('secrets','s','*TEXT','Set secret environment variables. E.g. --secrets SECRET=value');
 Opt('timeout','','TEXT','Max duration: int/float with s (seconds), m (minutes), h (hours) or d (days).');
 Opt('detach','d','','Run the Job in the background and print the Job ID.');
 Opt('namespace','','TEXT','The namespace where the job will be running. Defaults to the current user''s namespace.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(2,-1);
 Tok:=TokenOpt;
 If Tok='' Then Die('Not logged in. Run `hf auth login` or pass --token.');
 Ns:=JobNs(Tok);
 OptList('env',Env);OptList('secrets',Sec);
 Img:=Pos1(0);
 Cmd:='';
 For I:=1 to PosArgs.N-1 do Begin
  If I>1 Then Cmd:=Cmd+',';
  Cmd:=Cmd+JQ(PosArgs.A[I]);
 End;
 Body:='{"command":['+Cmd+'],"arguments":[],"environment":'+KvJson(Env)+',"flavor":'+
   JQ(OptGetDef('flavor','cpu-basic'));
 If StartsWith(Img,'https://huggingface.co/spaces/')Then
   Body:=Body+',"spaceId":'+JQ(Copy(Img,Length('https://huggingface.co/spaces/')+1,Length(Img)))
 Else Body:=Body+',"dockerImage":'+JQ(Img);
 If Sec.N>0 Then Body:=Body+',"secrets":'+KvJson(Sec);
 T:=ParseTimeout(OptGet('timeout'));
 If T>0 Then Body:=Body+',"timeoutSeconds":'+IStr(T);
 Body:=Body+'}';
 ApiMust(R,'POST','/api/jobs/'+Ns,Body,Tok);
 JReset;J:=JParse(R.RespBody);
 Id:=JS(J,'id');
 WriteLn('Job started with ID: ',Id);
 WriteLn('View at: ',Endpoint,'/jobs/',Ns,'/',Id);
 If not OptHas('detach')Then PrintJobLogs(Ns,Id,Tok);
End;

Procedure CmdJobsPs;
Var
 Tok,Ns:AnsiString;
 J,I,Stg:LongInt;
 Quiet,All:Boolean;
 St,Cmd:AnsiString;
 K,C:LongInt;
Begin
 CmdBegin('hf jobs ps','List Jobs.','');
 Opt('all','a','','Show all Jobs (default shows just running Jobs).');
 Opt('namespace','','TEXT','The namespace from where it lists the jobs. Defaults to the current user''s namespace.');
 Opt('format','','TEXT','Output format: table or json. [default: table]');
 Opt('quiet','q','','Print only Job IDs.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 Tok:=TokenOpt;
 If Tok='' Then Die('Not logged in. Run `hf auth login` or pass --token.');
 Ns:=JobNs(Tok);
 J:=ApiJson('GET','/api/jobs/'+Ns,'',Tok);
 If LoStr(OptGet('format'))='json' Then Begin JPrint(J);Exit;End;
 Quiet:=OptHas('quiet');All:=OptHas('all');
 TblBegin('JOB ID'+#9+'IMAGE/SPACE'+#9+'COMMAND'+#9+'CREATED'+#9+'STATUS');
 For I:=0 to JCnt(J)-1 do Begin
  St:=JS(JAt(J,I),'status.stage');
  If not All and(St<>'RUNNING')and(St<>'UPDATING')Then Continue;
  If Quiet Then Begin WriteLn(JS(JAt(J,I),'id'));Continue;End;
  Cmd:='';
  C:=JGet(JAt(J,I),'command');
  For K:=0 to JCnt(C)-1 do Begin
   If K>0 Then Cmd:=Cmd+' ';
   Cmd:=Cmd+JTxt(JAt(C,K));
  End;
  If Length(Cmd)>40 Then Cmd:=Copy(Cmd,1,37)+'...';
  TblRow(JS(JAt(J,I),'id')+#9+IfThen_(JS(JAt(J,I),'dockerImage')<>'',
    JS(JAt(J,I),'dockerImage'),JS(JAt(J,I),'spaceId'))+#9+Cmd+#9+
    Copy(ReplaceAll(JS(JAt(J,I),'createdAt'),'T',' '),1,19)+#9+St);
 End;
 If not Quiet Then TblPrint;
End;

Procedure CmdJobsInspect;
Var
 Tok,Ns:AnsiString;
 I:LongInt;
Begin
 CmdBegin('hf jobs inspect','Display detailed information on one or more Jobs.','JOB_IDS...');
 CmdArg('JOB_IDS','The jobs to inspect.');
 Opt('namespace','','TEXT','The namespace where the job is running. Defaults to the current user''s namespace.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,-1);
 Tok:=TokenOpt;
 Ns:=JobNs(Tok);
 For I:=0 to PosArgs.N-1 do JPrint(ApiJson('GET','/api/jobs/'+Ns+'/'+UrlEnc(PosArgs.A[I],False),'',Tok));
End;

Procedure CmdJobsLogs;
Var
 Tok:AnsiString;
Begin
 CmdBegin('hf jobs logs','Fetch the logs of a Job.','JOB_ID');
 CmdArg('JOB_ID','Job ID.');
 Opt('namespace','','TEXT','The namespace where the job is running. Defaults to the current user''s namespace.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 Tok:=TokenOpt;
 PrintJobLogs(JobNs(Tok),UrlEnc(Pos1(0),False),Tok);
End;

Procedure CmdJobsCancel;
Var
 Tok,Ns:AnsiString;
 R:THttpReq;
Begin
 CmdBegin('hf jobs cancel','Cancel a Job.','JOB_ID');
 CmdArg('JOB_ID','Job ID.');
 Opt('namespace','','TEXT','The namespace where the job is running. Defaults to the current user''s namespace.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 Tok:=TokenOpt;
 Ns:=JobNs(Tok);
 ApiMust(R,'POST','/api/jobs/'+Ns+'/'+UrlEnc(Pos1(0),False)+'/cancel','',Tok);
 WriteLn('Job ',Pos1(0),' cancelled.');
End;

{ ------------------------------------------------------------------ }
{ cp, sync, buckets                                                   }
{ ------------------------------------------------------------------ }

Procedure NoBuckets;
Begin
 Die('Buckets are not supported by this clone (the Storage Buckets API is not implemented). '+
   'Use `hf download` / `hf upload` / `hf cp` with Hub repositories instead.');
End;

{ hf://[datasets/|spaces/]owner/name[@rev]/chemin }
Function ParseHfUrl(Const U:AnsiString;Var RType,Repo,Rev,Path:AnsiString):Boolean;
Var
 S:AnsiString;
 L:TSList;
 I,P:LongInt;
Begin
 ParseHfUrl:=False;
 If not StartsWith(LoStr(U),'hf://')Then Exit;
 S:=Copy(U,6,Length(U));
 SplitStr(S,'/',L);
 RType:='model';
 I:=0;
 If L.N>0 Then Begin
  If L.A[0]='buckets' Then NoBuckets;
  If L.A[0]='datasets' Then Begin RType:='dataset';I:=1;End
  Else If L.A[0]='spaces' Then Begin RType:='space';I:=1;End
  Else If L.A[0]='models' Then I:=1;
 End;
 If L.N<I+2 Then Die('invalid hf:// URL, expected hf://[datasets/|spaces/]owner/name[@revision]/path: '+U);
 Repo:=L.A[I];
 Rev:='main';
 S:=L.A[I+1];
 P:=Pos('@',S);
 If P>0 Then Begin Rev:=Copy(S,P+1,Length(S));S:=Copy(S,1,P-1);End;
 Repo:=Repo+'/'+S;
 Path:='';
 For P:=I+2 to L.N-1 do Begin
  If Path<>'' Then Path:=Path+'/';
  Path:=Path+L.A[P];
 End;
 ParseHfUrl:=True;
End;

Procedure CopyTree(Const Src,Dst:AnsiString);
Var
 L:TSList;
 I:LongInt;
Begin
 WalkFiles(Src,'',L);
 For I:=0 to L.N-1 do
  If not CopyFile_(JoinPath(Src,NormSep(L.A[I])),JoinPath(Dst,NormSep(L.A[I])))Then
    Die('cannot copy '+L.A[I]);
End;

Procedure CmdCp;
Var
 Src,Dst,RType,Repo,Rev,Path,Tok,D,Url:AnsiString;
 SrcHf,DstHf,IsDir:Boolean;
 Files:TRFiles;
 Commit:AnsiString;
 Locals,Remotes,NoL,L:TSList;
 I:LongInt;
Begin
 CmdBegin('hf cp','Copy files between local paths and Hub repositories (hf://...).','SRC DST');
 CmdArg('SRC','Source: a local path or hf://[datasets/|spaces/]owner/name[@revision]/path.');
 CmdArg('DST','Destination: a local path or hf://[datasets/|spaces/]owner/name[@revision]/path.');
 Opt('recursive','r','','Copy directories recursively.');
 Opt('commit-message','','TEXT','Commit message when copying to a repository.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 Src:=Pos1(0);Dst:=Pos1(1);
 Tok:=TokenOpt;
 SrcHf:=StartsWith(LoStr(Src),'hf://');DstHf:=StartsWith(LoStr(Dst),'hf://');
 If SrcHf and DstHf Then Die('copying between two Hub locations is not supported by this clone.');
 If not SrcHf and not DstHf Then Begin
  If not PathExists(Src,IsDir)Then Die('source does not exist: '+Src);
  If IsDir Then Begin
   If not OptHas('recursive')Then Die(Src+' is a directory (use --recursive).');
   CopyTree(Src,Dst);
  End
  Else Begin
   D:=Dst;
   If DirExists_(D)or EndsWith(D,'/')or EndsWith(D,'\')Then D:=JoinPath(D,BaseName(Src));
   If not CopyFile_(Src,D)Then Die('cannot copy '+Src+' to '+D);
  End;
  Exit;
 End;
 If DstHf Then Begin
  ParseHfUrl(Dst,RType,Repo,Rev,Path);
  If Tok='' Then Die('Not logged in. Run `hf auth login` or pass --token.');
  If not PathExists(Src,IsDir)Then Die('source does not exist: '+Src);
  SClear(Locals);SClear(Remotes);SClear(NoL);
  If IsDir Then Begin
   If not OptHas('recursive')Then Die(Src+' is a directory (use --recursive).');
   WalkFiles(Src,'',L);SSort(L);
   For I:=0 to L.N-1 do If not ShouldIgnoreUpload(L.A[I])Then Begin
    SAdd(Locals,JoinPath(AbsPath(Src),NormSep(L.A[I])));
    If Path='' Then SAdd(Remotes,L.A[I]) Else SAdd(Remotes,Path+'/'+L.A[I]);
   End;
  End
  Else Begin
   SAdd(Locals,AbsPath(Src));
   If(Path='')or EndsWith(Path,'/')Then SAdd(Remotes,Path+BaseName(Src)) Else SAdd(Remotes,Path);
  End;
  Url:=CommitFiles(Repo,RType,Rev,Tok,Locals,Remotes,NoL,
    OptGetDef('commit-message','Upload with hf cp'),'',False,False);
  WriteLn(Url);
  Exit;
 End;
 ParseHfUrl(Src,RType,Repo,Rev,Path);
 If Path='' Then Die('the source URL must point to a file or a folder in the repository.');
 If OptHas('recursive')Then Begin
  FetchRepo(Repo,RType,Rev,Tok,Commit,Files);
  I:=0;
  For I:=0 to High(Files)do If(Files[I].Path=Path)or StartsWith(Files[I].Path,Path+'/')Then
    DownloadTo(Repo,RType,Commit,Files[I].Path,Tok,
      JoinPath(Dst,NormSep(Copy(Files[I].Path,Length(Path)+2,Length(Files[I].Path)))),False);
 End
 Else Begin
  D:=Dst;
  If DirExists_(D)or EndsWith(D,'/')or EndsWith(D,'\')Then D:=JoinPath(D,BaseName(Path));
  DownloadTo(Repo,RType,Rev,Path,Tok,D,False);
  WriteLn(D);
 End;
End;

Procedure CmdSync;
Var
 Src,Dst:AnsiString;
 L,DL:TSList;
 Allow,Deny:TSList;
 I,NCopy,NDel:LongInt;
 SP,DP:AnsiString;
 Need:Boolean;
 Dry:Boolean;
 ST,DT:Int64;
Begin
 CmdBegin('hf sync','Sync files between two local directories.','SRC DST');
 CmdArg('SRC','Source directory.');
 CmdArg('DST','Destination directory.');
 Opt('delete','','','Delete files in DST that do not exist in SRC.');
 Opt('dry-run','','','Show what would be done without doing it.');
 Opt('include','','*TEXT','Glob patterns to include.');
 Opt('exclude','','*TEXT','Glob patterns to exclude.');
 AddTokenOpt;
 ParseArgs(ArgStart);
 NeedArgs(2,2);
 Src:=Pos1(0);Dst:=Pos1(1);
 If StartsWith(LoStr(Src),'hf://')or StartsWith(LoStr(Dst),'hf://')Then
   Die('syncing with a bucket or a Hub repository is not supported by this clone '+
     '(use `hf upload` / `hf download` for repositories).');
 If not DirExists_(Src)Then Die('source directory does not exist: '+Src);
 OptList('include',Allow);OptList('exclude',Deny);
 WalkFiles(Src,'',L);SSort(L);
 Dry:=OptHas('dry-run');
 NCopy:=0;NDel:=0;
 For I:=0 to L.N-1 do If Selected(L.A[I],Allow,Deny)Then Begin
  SP:=JoinPath(Src,NormSep(L.A[I]));DP:=JoinPath(Dst,NormSep(L.A[I]));
  Need:=not FileExists_(DP);
  If not Need Then Begin
   ST:=FileSizeOf(SP);DT:=FileSizeOf(DP);
   Need:=(ST<>DT)or(FileMTime(SP)>FileMTime(DP));
  End;
  If Need Then Begin
   WriteLn('copy ',L.A[I]);
   If not Dry Then If not CopyFile_(SP,DP)Then Die('cannot copy '+L.A[I]);
   Inc(NCopy);
  End;
 End;
 If OptHas('delete')and DirExists_(Dst)Then Begin
  WalkFiles(Dst,'',DL);SSort(DL);
  For I:=0 to DL.N-1 do If Selected(DL.A[I],Allow,Deny)and(SIndex(L,DL.A[I])<0)Then Begin
   WriteLn('delete ',DL.A[I]);
   If not Dry Then DelFile(JoinPath(Dst,NormSep(DL.A[I])));
   Inc(NDel);
  End;
 End;
 WriteLn('Sync complete: ',NCopy,' file(s) copied, ',NDel,' deleted',IfThen_(Dry,' (dry run)',''),'.');
End;

Procedure CmdBuckets;
Begin
 CmdBegin('hf buckets','Commands to interact with buckets.','COMMAND [ARGS]...');
 NoBuckets;
End;

{ ------------------------------------------------------------------ }
{ extensions                                                          }
{ ------------------------------------------------------------------ }

Function ExeSuffix:AnsiString;
Begin
 {$IFDEF WINDOWS}
 ExeSuffix:='.exe';
 {$ELSE}
 ExeSuffix:='';
 {$ENDIF}
End;

Function ExtDir:AnsiString;
Var
 D:AnsiString;
Begin
 D:=GetEnv('HF_EXTENSIONS_HOME');
 If D='' Then Begin
  {$IFDEF WINDOWS}
  D:=GetEnv('LOCALAPPDATA');
  If D='' Then D:=JoinPath(HomeDir,'AppData\Local');
  D:=JoinPath(JoinPath(D,'hf'),'extensions');
  {$ELSE}
  D:=GetEnv('XDG_DATA_HOME');
  If D='' Then D:=JoinPath(HomeDir,'.local/share');
  D:=JoinPath(JoinPath(D,'hf'),'extensions');
  {$ENDIF}
 End;
 ExtDir:=DropSlash(D);
End;

Function FindExt(Const Name:AnsiString):AnsiString;
Var
 P:AnsiString;
Begin
 P:=JoinPath(JoinPath(ExtDir,'hf-'+Name),'hf-'+Name+ExeSuffix);
 If FileExists_(P)Then Begin FindExt:=P;Exit;End;
 P:=JoinPath(ExtDir,'hf-'+Name+ExeSuffix);
 If FileExists_(P)Then Begin FindExt:=P;Exit;End;
 FindExt:=FSearch('hf-'+Name+ExeSuffix,GetEnv('PATH'));
End;

Function QuoteArg(Const S:AnsiString):AnsiString;
Begin
 If(S<>'')and(Pos(' ',S)=0)and(Pos('"',S)=0)Then QuoteArg:=S
 Else QuoteArg:='"'+ReplaceAll(S,'"','\"')+'"';
End;

Procedure RunExt(Const Path:AnsiString;FromIdx:LongInt);
Var
 A:AnsiString;
 I:LongInt;
Begin
 A:='';
 For I:=FromIdx to ParamCount do Begin
  If A<>'' Then A:=A+' ';
  A:=A+QuoteArg(ParamStr(I));
 End;
 DosError:=0;
 SwapVectors;
 Exec(Path,A);
 SwapVectors;
 If DosError<>0 Then Die('cannot run '+Path);
 Halt(DosExitCode);
End;

Procedure CmdExtList;
Var
 E:TEntries;
 I:LongInt;
 N:AnsiString;
Begin
 CmdBegin('hf extensions list','List installed extensions.','');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 ListDir(ExtDir,E);
 TblBegin('NAME'+#9+'PATH');
 For I:=0 to High(E)do If StartsWith(E[I].Name,'hf-')Then Begin
  N:=Copy(E[I].Name,4,Length(E[I].Name));
  If EndsWith(N,'.exe')Then Delete(N,Length(N)-3,4);
  TblRow(N+#9+FindExt(N));
 End;
 If TblRows.N=0 Then WriteLn('No extensions installed in ',ExtDir,'.') Else TblPrint;
End;

Procedure CmdExtInstall;
Var
 Src,Nm,Dest:AnsiString;
 IsDir:Boolean;
Begin
 CmdBegin('hf extensions install','Install an extension from a local executable named hf-NAME.',
   'SOURCE');
 CmdArg('SOURCE','Path to a local hf-NAME executable (GitHub sources are not supported).');
 Opt('force','','','Overwrite an existing extension.');
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 Src:=Pos1(0);
 If not PathExists(Src,IsDir)or IsDir Then
  Die('only local executables named hf-NAME are supported by this clone: '+Src);
 Nm:=BaseName(Src);
 If EndsWith(LoStr(Nm),'.exe')Then Delete(Nm,Length(Nm)-3,4);
 If not StartsWith(Nm,'hf-')Then Die('the executable name must start with "hf-": '+Nm);
 Dest:=JoinPath(JoinPath(ExtDir,Nm),Nm+ExeSuffix);
 If FileExists_(Dest)and not OptHas('force')Then Die('extension already installed (use --force).');
 If not CopyFile_(Src,Dest)Then Die('cannot copy to '+Dest);
 {$IFNDEF WINDOWS}
 { la copie perd le droit d'execution }
 DosError:=0;
 SwapVectors;Exec('/bin/chmod','+x '+Dest);SwapVectors;
 {$ENDIF}
 WriteLn('Installed extension ''',Copy(Nm,4,Length(Nm)),''' in ',Dest);
End;

Procedure CmdExtRemove;
Begin
 CmdBegin('hf extensions remove','Remove an installed extension.','NAME');
 CmdArg('NAME','Extension name (without the hf- prefix).');
 ParseArgs(ArgStart);
 NeedArgs(1,1);
 If not DirExists_(JoinPath(ExtDir,'hf-'+Pos1(0)))and not FileExists_(JoinPath(ExtDir,
   'hf-'+Pos1(0)+ExeSuffix))Then Die('extension not installed: '+Pos1(0));
 RmTree(JoinPath(ExtDir,'hf-'+Pos1(0)));
 DelFile(JoinPath(ExtDir,'hf-'+Pos1(0)+ExeSuffix));
 WriteLn('Removed extension ''',Pos1(0),'''.');
End;

Procedure CmdExtExec;
Var
 P:AnsiString;
Begin
 CmdBegin('hf extensions exec','Run an extension.','NAME [ARGS]...');
 CmdArg('NAME','Extension name (without the hf- prefix).');
 StopAfter:=1;
 ParseArgs(ArgStart);
 NeedArgs(1,-1);
 P:=FindExt(Pos1(0));
 If P='' Then Die('extension not found: '+Pos1(0));
 RunExt(P,ArgStart+1);
End;

{ ------------------------------------------------------------------ }
{ Tables des commandes, aide principale                               }
{ ------------------------------------------------------------------ }

Type
 TSub = Record
  G,N,D:AnsiString;
 End;

Const
 NSubs=66;
 Subs:Array[0..NSubs-1]of TSub=(
  (G:'auth';N:'login';D:'Login using a token from huggingface.co/settings/tokens.'),
  (G:'auth';N:'logout';D:'Logout from a specific token.'),
  (G:'auth';N:'switch';D:'Switch between access tokens.'),
  (G:'auth';N:'list';D:'List all stored access tokens.'),
  (G:'auth';N:'whoami';D:'Find out which huggingface.co account you are logged in as.'),
  (G:'cache';N:'ls';D:'List cached repositories or revisions.'),
  (G:'cache';N:'rm';D:'Remove cached repositories or revisions.'),
  (G:'cache';N:'prune';D:'Remove detached revisions from the cache.'),
  (G:'cache';N:'verify';D:'Verify checksums for a single repo revision from cache or a local directory.'),
  (G:'models';N:'ls';D:'List models on the Hub.'),
  (G:'models';N:'info';D:'Get info about a model on the Hub.'),
  (G:'datasets';N:'ls';D:'List datasets on the Hub.'),
  (G:'datasets';N:'info';D:'Get info about a dataset on the Hub.'),
  (G:'spaces';N:'ls';D:'List spaces on the Hub.'),
  (G:'spaces';N:'info';D:'Get info about a space on the Hub.'),
  (G:'repos';N:'create';D:'Create a new repo on the Hub.'),
  (G:'repos';N:'delete';D:'Delete a repo from the Hub. This is an irreversible operation.'),
  (G:'repos';N:'move';D:'Move a repository from a namespace to another namespace.'),
  (G:'repos';N:'settings';D:'Update the settings of a repository.'),
  (G:'repos';N:'branch';D:'Manage branches for a repo on the Hub.'),
  (G:'repos';N:'tag';D:'Manage tags for a repo on the Hub.'),
  (G:'repos';N:'delete-files';D:'Delete files from a repo on the Hub.'),
  (G:'repos branch';N:'create';D:'Create a new branch for a repo on the Hub.'),
  (G:'repos branch';N:'delete';D:'Delete a branch from a repo on the Hub.'),
  (G:'repos tag';N:'create';D:'Create a tag for a repo.'),
  (G:'repos tag';N:'delete';D:'Delete a tag from a repo.'),
  (G:'repos tag';N:'list';D:'List tags for a repo.'),
  (G:'collections';N:'ls';D:'List collections on the Hub.'),
  (G:'collections';N:'info';D:'Get info about a collection on the Hub.'),
  (G:'collections';N:'create';D:'Create a new collection on the Hub.'),
  (G:'collections';N:'delete';D:'Delete a collection from the Hub.'),
  (G:'collections';N:'add-item';D:'Add an item to a collection.'),
  (G:'collections';N:'delete-item';D:'Delete an item from a collection.'),
  (G:'papers';N:'ls';D:'List daily papers on the Hub.'),
  (G:'papers';N:'search';D:'Search papers on the Hub.'),
  (G:'papers';N:'info';D:'Get info about a paper on the Hub.'),
  (G:'discussions';N:'ls';D:'List discussions and pull requests on a repo.'),
  (G:'discussions';N:'info';D:'Get info about a discussion or pull request.'),
  (G:'discussions';N:'create';D:'Create a new discussion or pull request on a repo.'),
  (G:'discussions';N:'comment';D:'Comment on a discussion or pull request.'),
  (G:'discussions';N:'close';D:'Close a discussion or pull request.'),
  (G:'discussions';N:'reopen';D:'Reopen a closed discussion or pull request.'),
  (G:'discussions';N:'merge';D:'Merge a pull request.'),
  (G:'endpoints';N:'ls';D:'Lists all Inference Endpoints for the given namespace.'),
  (G:'endpoints';N:'describe';D:'Get information about an existing endpoint.'),
  (G:'endpoints';N:'pause';D:'Pause an Inference Endpoint.'),
  (G:'endpoints';N:'resume';D:'Resume an Inference Endpoint.'),
  (G:'endpoints';N:'scale-to-zero';D:'Scale an Inference Endpoint to zero.'),
  (G:'endpoints';N:'delete';D:'Delete an Inference Endpoint permanently.'),
  (G:'jobs';N:'run';D:'Run a Job.'),
  (G:'jobs';N:'ps';D:'List Jobs.'),
  (G:'jobs';N:'inspect';D:'Display detailed information on one or more Jobs.'),
  (G:'jobs';N:'logs';D:'Fetch the logs of a Job.'),
  (G:'jobs';N:'cancel';D:'Cancel a Job.'),
  (G:'buckets';N:'create';D:'Create a bucket (not supported by this clone).'),
  (G:'buckets';N:'list';D:'List buckets (not supported by this clone).'),
  (G:'buckets';N:'info';D:'Get info about a bucket (not supported by this clone).'),
  (G:'buckets';N:'delete';D:'Delete a bucket (not supported by this clone).'),
  (G:'buckets';N:'cp';D:'Copy files to or from a bucket (not supported by this clone).'),
  (G:'buckets';N:'sync';D:'Sync a directory with a bucket (not supported by this clone).'),
  (G:'extensions';N:'list';D:'List installed extensions.'),
  (G:'extensions';N:'install';D:'Install an extension.'),
  (G:'extensions';N:'remove';D:'Remove an installed extension.'),
  (G:'extensions';N:'exec';D:'Run an extension.'),
  (G:'skills';N:'add';D:'Install the hf-cli skill for AI assistants.'),
  (G:'skills';N:'preview';D:'Print the generated SKILL.md to stdout.'));

 NTop=21;
 Tops:Array[0..NTop-1]of TSub=(
  (G:'main';N:'auth';D:'Manage authentication (login, logout, etc.).'),
  (G:'main';N:'buckets';D:'Commands to interact with buckets.'),
  (G:'main';N:'cache';D:'Manage local cache directory.'),
  (G:'main';N:'collections';D:'Interact with collections on the Hub.'),
  (G:'main';N:'cp';D:'Copy files between local paths and Hub repositories.'),
  (G:'main';N:'datasets';D:'Interact with datasets on the Hub.'),
  (G:'main';N:'discussions';D:'Manage discussions and pull requests on the Hub.'),
  (G:'main';N:'download';D:'Download files from the Hub.'),
  (G:'main';N:'endpoints';D:'Manage Hugging Face Inference Endpoints.'),
  (G:'help';N:'env';D:'Print information about the environment.'),
  (G:'main';N:'extensions';D:'Manage hf CLI extensions.'),
  (G:'main';N:'jobs';D:'Run and manage Jobs on the Hub.'),
  (G:'main';N:'models';D:'Interact with models on the Hub.'),
  (G:'main';N:'papers';D:'Interact with papers on the Hub.'),
  (G:'main';N:'repos';D:'Manage repos on the Hub.'),
  (G:'main';N:'skills';D:'Manage skills for AI assistants.'),
  (G:'main';N:'spaces';D:'Interact with spaces on the Hub.'),
  (G:'main';N:'sync';D:'Sync files between two local directories.'),
  (G:'help';N:'update';D:'Check for a newer version of the hf CLI.'),
  (G:'main';N:'upload';D:'Upload a file or a folder to the Hub.'),
  (G:'help';N:'version';D:'Print information about the hf version.'));

Procedure PrintMainHelp;
Var
 I:LongInt;
Begin
 WriteLn(L('Usage: ','Utilisation : '),'hf [OPTIONS] ',L('COMMAND','COMMANDE'),' [ARGS]...');
 WriteLn;
 WriteLn('  ',Tr('Hugging Face Hub CLI (Pascal clone)'));
 WriteLn;
 WriteLn(L('Options:','Options :'));
 WriteLn('  -h, --help, /?  ',Tr('Show this message and exit.'));
 WriteLn;
 WriteLn(L('Main commands:','Commandes principales :'));
 For I:=0 to NTop-1 do If Tops[I].G='main' Then
   WriteLn('  ',PadR(Tops[I].N,12),'  ',Tr(Tops[I].D));
 WriteLn;
 WriteLn(L('Help commands:','Commandes d''aide :'));
 For I:=0 to NTop-1 do If Tops[I].G='help' Then
   WriteLn('  ',PadR(Tops[I].N,12),'  ',Tr(Tops[I].D));
 WriteLn;
 WriteLn(L('Learn more:','Pour en savoir plus :'));
 WriteLn(L('  Use `hf <command> --help` for more information about a command.',
   '  Utilisez `hf <commande> --help` (ou `/?`) pour obtenir l''aide d''une commande.'));
 WriteLn(L('  Read the documentation at ','  Consultez la documentation sur ')+
   'https://huggingface.co/docs/huggingface_hub/en/guides/cli');
 WriteLn(L('  Set LANGUAGE=EN to display this help in English.',
   '  Définissez LANGUAGE=EN pour afficher cette aide en anglais.'));
End;

Function TopDesc(Const Name:AnsiString):AnsiString;
Var
 I:LongInt;
Begin
 TopDesc:='';
 For I:=0 to NTop-1 do If Tops[I].N=Name Then TopDesc:=Tops[I].D;
End;

Procedure PrintGroupHelp(Const Path,Desc:AnsiString);
Var
 I,W:LongInt;
 G:AnsiString;
Begin
 G:=Copy(Path,4,Length(Path));
 WriteLn(L('Usage: ','Utilisation : '),Path,' [OPTIONS] ',L('COMMAND','COMMANDE'),' [ARGS]...');
 WriteLn;
 WriteLn('  ',Tr(Desc));
 WriteLn;
 WriteLn(L('Options:','Options :'));
 WriteLn('  -h, --help, /?  ',Tr('Show this message and exit.'));
 WriteLn;
 WriteLn(L('Commands:','Commandes :'));
 W:=0;
 For I:=0 to NSubs-1 do If(Subs[I].G=G)and(Length(Subs[I].N)>W)Then W:=Length(Subs[I].N);
 For I:=0 to NSubs-1 do If Subs[I].G=G Then WriteLn('  ',PadR(Subs[I].N,W),'  ',Tr(Subs[I].D));
End;

Procedure NoSuchCommand(Const Path,Name:AnsiString);
Begin
 WriteLn(StdErr,L('Usage: ','Utilisation : '),Path,' [OPTIONS] ',L('COMMAND','COMMANDE'),' [ARGS]...');
 WriteLn(StdErr,L('Try ''','Essayez ''') ,Path,L(' -h'' for help.',' -h'' pour obtenir de l''aide.'));
 WriteLn(StdErr);
 WriteLn(StdErr,L('Error: No such command ''','Erreur : Commande inconnue '''),Name,'''.');
 Halt(2);
End;

{ ------------------------------------------------------------------ }
{ env, version, update, skills                                        }
{ ------------------------------------------------------------------ }

Function PlatformName:AnsiString;
Begin
 {$IFDEF WINDOWS}
 PlatformName:='Windows';
 {$ELSE}
  {$IFDEF LINUX}
 PlatformName:='Linux';
  {$ELSE}
   {$IFDEF DARWIN}
 PlatformName:='macOS';
   {$ELSE}
 PlatformName:='Unix';
   {$ENDIF}
  {$ENDIF}
 {$ENDIF}
End;

Function BoolEnv(Const Name:AnsiString):AnsiString;
Var
 V:AnsiString;
Begin
 V:=LoStr(GetEnv(Name));
 If(V='1')or(V='true')or(V='yes')or(V='on')Then BoolEnv:='True' Else BoolEnv:='False';
End;

Procedure CmdEnv;
Var
 Tok,Who:AnsiString;
 R:THttpReq;
 J:LongInt;
Begin
 CmdBegin('hf env','Print information about the environment.','');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 Tok:=ResolveToken('');
 Who:='N/A';
 If(Tok<>'')and(GetEnv('HF_HUB_OFFLINE')<>'1')Then Begin
  ApiCall(R,'GET','/api/whoami-v2','',Tok);
  If ApiOk(R)Then Begin
   JReset;J:=JParse(R.RespBody);
   Who:=JS(J,'name');
  End
  Else Who:='Invalid token';
 End;
 WriteLn('Copy-and-paste the text below in your GitHub issue.');
 WriteLn;
 WriteLn('- huggingface_hub version: ',ToolVersion,' (HF.PAS, Pascal clone)');
 WriteLn('- Platform: ',PlatformName);
 WriteLn('- Python version: n/a (native Free Pascal build)');
 WriteLn('- Running in iPython ?: No');
 WriteLn('- Running in notebook ?: No');
 WriteLn('- Running in Google Colab ?: No');
 WriteLn('- Token path ?: ',TokenPath);
 WriteLn('- Has saved token ?: ',IfThen_(ReadTokenFile<>'','True','False'));
 WriteLn('- Who am I ?: ',Who);
 WriteLn('- Endpoint: ',Endpoint);
 WriteLn('- HF_HUB_CACHE: ',HubCache);
 WriteLn('- HF_TOKEN_PATH: ',TokenPath);
 WriteLn('- HF_STORED_TOKENS_PATH: ',StoredTokensPath);
 WriteLn('- HF_HUB_OFFLINE: ',BoolEnv('HF_HUB_OFFLINE'));
 WriteLn('- HF_HUB_DISABLE_TELEMETRY: ',BoolEnv('HF_HUB_DISABLE_TELEMETRY'));
 WriteLn('- HF_HUB_DISABLE_PROGRESS_BARS: ',IfThen_(GetEnv('HF_HUB_DISABLE_PROGRESS_BARS')='',
   'None',GetEnv('HF_HUB_DISABLE_PROGRESS_BARS')));
 WriteLn('- HF_HUB_DISABLE_SYMLINKS_WARNING: ',BoolEnv('HF_HUB_DISABLE_SYMLINKS_WARNING'));
 WriteLn('- HF_HUB_DISABLE_IMPLICIT_TOKEN: ',BoolEnv('HF_HUB_DISABLE_IMPLICIT_TOKEN'));
 WriteLn('- HF_HUB_ENABLE_HF_TRANSFER: ',BoolEnv('HF_HUB_ENABLE_HF_TRANSFER'));
End;

Procedure CmdVersion;
Begin
 CmdBegin('hf version','Print information about the hf version.','');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 WriteLn('hf (HF.PAS) version: ',ToolVersion);
End;

Procedure CmdUpdate;
Var
 R:THttpReq;
 J:LongInt;
 Latest:AnsiString;
Begin
 CmdBegin('hf update','Check for a newer version of the hf CLI.','');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 WriteLn('Current version: ',ToolVersion,' (HF.PAS, native Pascal build)');
 ReqInit(R,'GET','https://pypi.org/pypi/huggingface_hub/json','');
 HttpDo(R);
 If ApiOk(R)Then Begin
  JReset;J:=JParse(R.RespBody);
  Latest:=JS(J,'info.version');
  WriteLn('Latest huggingface_hub release: ',Latest);
 End
 Else WriteLn('Could not query PyPI: ',ErrText(R));
 WriteLn('This build is not installed through pip, so it cannot update itself.');
 WriteLn('To update, download the latest HF.PAS from https://github.com/gladir/VIE and recompile it.');
End;

Function SkillText:AnsiString;
Var
 B:TBuf;
 I:LongInt;
 Last:AnsiString;
Begin
 BufClear(B);
 BufAdd(B,'---'#10'name: hf-cli'#10+
   'description: "Hugging Face Hub CLI (`hf`): download and upload models, datasets and spaces, '+
   'manage repos, cache, collections, discussions, jobs and inference endpoints from the terminal."'#10+
   '---'#10#10'# Hugging Face Hub CLI (`hf`)'#10#10+
   'Use the `hf` command to interact with the Hugging Face Hub. Authenticate with `hf auth login` '+
   '(or set `HF_TOKEN`), then run `hf <command> --help` for the options of each command.'#10#10+
   '## Commands'#10#10);
 For I:=0 to NTop-1 do BufAdd(B,'- `hf '+Tops[I].N+'`: '+Tops[I].D+#10);
 BufAdd(B,#10'## Sub-commands'#10#10);
 Last:='';
 For I:=0 to NSubs-1 do Begin
  If Subs[I].G<>Last Then Begin
   BufAdd(B,#10'### hf '+Subs[I].G+#10#10);
   Last:=Subs[I].G;
  End;
  BufAdd(B,'- `hf '+Subs[I].G+' '+Subs[I].N+'`: '+Subs[I].D+#10);
 End;
 BufAdd(B,#10'## Examples'#10#10+
   '```bash'#10'hf download openai-community/gpt2 config.json'#10+
   'hf download openai-community/gpt2 --include "*.json" --local-dir ./gpt2'#10+
   'hf upload my-user/my-model ./output /'#10'hf cache ls --revisions'#10'```'#10);
 SkillText:=BufStr(B);
End;

Procedure CmdSkills(Const Sub:AnsiString);
Var
 Dir,Base,Target:AnsiString;
 Names:TSList;
 I:LongInt;
Begin
 If Sub='preview' Then Begin
  CmdBegin('hf skills preview','Print the generated SKILL.md to stdout.','');
  ParseArgs(ArgStart);
  NeedArgs(0,0);
  Write(SkillText);
  Exit;
 End;
 CmdBegin('hf skills add','Install the hf-cli skill for AI assistants.','');
 Opt('claude','','','Install for Claude Code (.claude/skills).');
 Opt('codex','','','Install for Codex (.agents/skills).');
 Opt('opencode','','','Install for OpenCode (.opencode/skills).');
 Opt('global','g','','Install globally (in the home directory) instead of the current project.');
 Opt('dest','','TEXT','Install into this skills directory.');
 Opt('force','','','Overwrite an existing installation.');
 ParseArgs(ArgStart);
 NeedArgs(0,0);
 SClear(Names);
 If OptHas('dest')Then SAdd(Names,OptGet('dest'))
 Else Begin
  If OptHas('global')Then Base:=HomeDir Else Base:='.';
  If OptHas('codex')Then SAdd(Names,JoinPath(Base,'.agents'+DS+'skills'));
  If OptHas('opencode')Then SAdd(Names,JoinPath(Base,'.opencode'+DS+'skills'));
  If OptHas('claude')or(Names.N=0)Then SAdd(Names,JoinPath(Base,'.claude'+DS+'skills'));
 End;
 For I:=0 to Names.N-1 do Begin
  Dir:=JoinPath(Names.A[I],'hf-cli');
  Target:=JoinPath(Dir,'SKILL.md');
  If FileExists_(Target)and not OptHas('force')Then
   Die('skill already installed at '+Target+' (use --force to overwrite).');
  If not WriteAll(Target,SkillText)Then Die('cannot write '+Target);
  WriteLn('Installed skill hf-cli to ',Target);
 End;
End;

{ ------------------------------------------------------------------ }
{ Programme principal                                                 }
{ ------------------------------------------------------------------ }

{$IFDEF WINDOWS}
Function SetConsoleOutputCP(CP:LongWord):LongInt;stdcall;external 'kernel32.dll' name
  'SetConsoleOutputCP';
Function GetConsoleOutputCP:LongWord;stdcall;external 'kernel32.dll' name
  'GetConsoleOutputCP';

Var
 SavedCP:LongWord;
 OldExit:Pointer;

Procedure RestoreConsole;
Begin
 ExitProc:=OldExit;
 SetConsoleOutputCP(SavedCP);
End;
{$ENDIF}

{ sous-groupe : "repos branch" / "repos tag" ; Idx = indice du sous-sous-commande }
Procedure RunNested(Const Grp:AnsiString;Idx:LongInt);
Var
 Sub,Key:AnsiString;
Begin
 If(Idx>ParamCount)or(ParamStr(Idx)='-h')or(ParamStr(Idx)='--help')or(ParamStr(Idx)='/?')Then Begin
  PrintGroupHelp('hf '+Grp,TopDesc('repos'));
  Halt(0);
 End;
 Sub:=ParamStr(Idx);
 ArgStart:=Idx+1;
 Key:=Grp+' '+Sub;
 If Key='repos branch create' Then CmdReposBranchCreate
 Else If Key='repos branch delete' Then CmdReposBranchDelete
 Else If Key='repos tag create' Then CmdReposTagCreate
 Else If Key='repos tag delete' Then CmdReposTagDelete
 Else If Key='repos tag list' Then CmdReposTagList
 Else NoSuchCommand('hf '+Grp,Sub);
End;

Procedure RunGroup(Const Grp:AnsiString);
Var
 Sub,Key:AnsiString;
Begin
 If(ParamCount<2)or(ParamStr(2)='-h')or(ParamStr(2)='--help')or(ParamStr(2)='/?')Then Begin
  PrintGroupHelp('hf '+Grp,TopDesc(Grp));
  Halt(0);
 End;
 Sub:=ParamStr(2);
 ArgStart:=3;
 Key:=Grp+' '+Sub;
 If Key='auth login' Then CmdAuthLogin
 Else If Key='auth logout' Then CmdAuthLogout
 Else If Key='auth switch' Then CmdAuthSwitch
 Else If Key='auth list' Then CmdAuthList
 Else If Key='auth whoami' Then CmdAuthWhoami
 Else If Key='cache ls' Then CmdCacheLs
 Else If Key='cache rm' Then CmdCacheRm
 Else If Key='cache prune' Then CmdCachePrune
 Else If Key='cache verify' Then CmdCacheVerify
 Else If Key='models ls' Then CmdHubList('model')
 Else If Key='models info' Then CmdHubInfo('model')
 Else If Key='datasets ls' Then CmdHubList('dataset')
 Else If Key='datasets info' Then CmdHubInfo('dataset')
 Else If Key='spaces ls' Then CmdHubList('space')
 Else If Key='spaces info' Then CmdHubInfo('space')
 Else If Key='repos create' Then CmdReposCreate
 Else If Key='repos delete' Then CmdReposDelete
 Else If Key='repos move' Then CmdReposMove
 Else If Key='repos settings' Then CmdReposSettings
 Else If Key='repos delete-files' Then CmdReposDeleteFiles
 Else If Key='repos branch' Then RunNested(Key,3)
 Else If Key='repos tag' Then RunNested(Key,3)
 Else If Key='collections ls' Then CmdCollectionsLs
 Else If Key='collections info' Then CmdCollectionsInfo
 Else If Key='collections create' Then CmdCollectionsCreate
 Else If Key='collections delete' Then CmdCollectionsDelete
 Else If Key='collections add-item' Then CmdCollectionsAddItem
 Else If Key='collections delete-item' Then CmdCollectionsDeleteItem
 Else If Key='papers ls' Then CmdPapersLs
 Else If Key='papers search' Then CmdPapersSearch
 Else If Key='papers info' Then CmdPapersInfo
 Else If Key='discussions ls' Then CmdDiscLs
 Else If Key='discussions info' Then CmdDiscInfo
 Else If Key='discussions create' Then CmdDiscCreate
 Else If Key='discussions comment' Then CmdDiscComment
 Else If Key='discussions close' Then DiscStatus('close','closed','Close a discussion or pull request.')
 Else If Key='discussions reopen' Then DiscStatus('reopen','open','Reopen a closed discussion or pull request.')
 Else If Key='discussions merge' Then CmdDiscMerge
 Else If Key='endpoints ls' Then CmdEpLs
 Else If Key='endpoints describe' Then EpSimple('describe','GET','','Get information about an existing endpoint.')
 Else If Key='endpoints pause' Then EpSimple('pause','POST','/pause','Pause an Inference Endpoint.')
 Else If Key='endpoints resume' Then EpSimple('resume','POST','/resume','Resume an Inference Endpoint.')
 Else If Key='endpoints scale-to-zero' Then EpSimple('scale-to-zero','POST','/scale-to-zero',
   'Scale an Inference Endpoint to zero.')
 Else If Key='endpoints delete' Then EpSimple('delete','DELETE','','Delete an Inference Endpoint permanently.')
 Else If Key='jobs run' Then CmdJobsRun
 Else If Key='jobs ps' Then CmdJobsPs
 Else If Key='jobs inspect' Then CmdJobsInspect
 Else If Key='jobs logs' Then CmdJobsLogs
 Else If Key='jobs cancel' Then CmdJobsCancel
 Else If Grp='buckets' Then CmdBuckets
 Else If Key='extensions list' Then CmdExtList
 Else If Key='extensions install' Then CmdExtInstall
 Else If Key='extensions remove' Then CmdExtRemove
 Else If Key='extensions exec' Then CmdExtExec
 Else If Key='skills add' Then CmdSkills('add')
 Else If Key='skills preview' Then CmdSkills('preview')
 Else NoSuchCommand('hf '+Grp,Sub);
End;

Procedure Run;
Var
 C,P:AnsiString;
Begin
 If ParamCount=0 Then Begin PrintMainHelp;Halt(0);End;
 C:=ParamStr(1);
 ArgStart:=2;
 If(C='-h')or(C='--help')or(C='/?')or(C='help')Then Begin PrintMainHelp;Halt(0);End;
 If C='download' Then CmdDownload
 Else If C='upload' Then CmdUpload
 Else If C='env' Then CmdEnv
 Else If C='version' Then CmdVersion
 Else If C='update' Then CmdUpdate
 Else If C='cp' Then CmdCp
 Else If C='sync' Then CmdSync
 Else If C='repo' Then RunGroup('repos')
 Else If(C='auth')or(C='cache')or(C='models')or(C='datasets')or(C='spaces')or(C='repos')or
   (C='collections')or(C='papers')or(C='discussions')or(C='endpoints')or(C='jobs')or
   (C='buckets')or(C='extensions')or(C='skills')Then RunGroup(C)
 Else Begin
  P:=FindExt(C);
  If P<>'' Then RunExt(P,2);
  NoSuchCommand('hf',C);
 End;
End;

Begin
 Randomize;
 JN:=0;
 Endpoint:=GetEnv('HF_ENDPOINT');
 If Endpoint='' Then Endpoint:=DefaultEndpoint;
 Endpoint:=DropSlash(Endpoint);
 {$IFDEF WINDOWS}
 SavedCP:=GetConsoleOutputCP;
 SetConsoleOutputCP(65001);
 OldExit:=ExitProc;
 ExitProc:=@RestoreConsole;
 {$ENDIF}
 Run;
End.
