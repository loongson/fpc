{
    $Id$
    This file is part of the Free Pascal Integrated Development Environment
    Copyright (c) 1998 by Berczi Gabor

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
unit WUtils;

interface

{$ifndef FPC}
  {$define TPUNIXLF}
{$endif}


uses
  Objects;

type
  PByteArray = ^TByteArray;
  TByteArray = array[0..65520] of byte;

  PNoDisposeCollection = ^TNoDisposeCollection;
  TNoDisposeCollection = object(TCollection)
    procedure FreeItem(Item: Pointer); virtual;
  end;

  PUnsortedStringCollection = ^TUnsortedStringCollection;
  TUnsortedStringCollection = object(TCollection)
    constructor CreateFrom(ALines: PUnsortedStringCollection);
    procedure   Assign(ALines: PUnsortedStringCollection);
    function    At(Index: Integer): PString;
    procedure   FreeItem(Item: Pointer); virtual;
    function    GetItem(var S: TStream): Pointer; virtual;
    procedure   PutItem(var S: TStream; Item: Pointer); virtual;
  end;

  PNulStream = ^TNulStream;
  TNulStream = object(TStream)
    constructor Init;
    function    GetPos: Longint; virtual;
    function    GetSize: Longint; virtual;
    procedure   Read(var Buf; Count: Word); virtual;
    procedure   Seek(Pos: Longint); virtual;
    procedure   Write(var Buf; Count: Word); virtual;
  end;

  PSubStream = ^TSubStream;
  TSubStream = object(TStream)
    constructor Init(AStream: PStream; AStartPos, ASize: longint);
    function    GetPos: Longint; virtual;
    function    GetSize: Longint; virtual;
    procedure   Read(var Buf; Count: Word); virtual;
    procedure   Seek(Pos: Longint); virtual;
    procedure   Write(var Buf; Count: Word); virtual;
  private
    StartPos: longint;
    S       : PStream;
  end;

  PTextCollection = ^TTextCollection;
  TTextCollection = object(TStringCollection)
    function LookUp(const S: string; var Idx: sw_integer): string;
    function Compare(Key1, Key2: Pointer): sw_Integer; virtual;
  end;

{$ifdef TPUNIXLF}
  procedure readln(var t:text;var s:string);
{$endif}

procedure ReadlnFromStream(Stream: PStream; var s:string;var linecomplete : boolean);
function eofstream(s: pstream): boolean;

function Min(A,B: longint): longint;
function Max(A,B: longint): longint;

function CharStr(C: char; Count: byte): string;
function UpcaseStr(const S: string): string;
function LowCase(C: char): char;
function LowcaseStr(S: string): string;
function RExpand(const S: string; MinLen: byte): string;
function LTrim(const S: string): string;
function RTrim(const S: string): string;
function Trim(const S: string): string;
function IntToStr(L: longint): string;
function StrToInt(const S: string): longint;
function GetStr(P: PString): string;
function GetPChar(P: PChar): string;
function BoolToStr(B: boolean; const TrueS, FalseS: string): string;

function DirOf(const S: string): string;
function ExtOf(const S: string): string;
function NameOf(const S: string): string;
function NameAndExtOf(const S: string): string;
function DirAndNameOf(const S: string): string;
{ return Dos GetFTime value or -1 if the file does not exist }
function GetFileTime(const FileName: string): longint;
{ copied from compiler global unit }
function GetShortName(const n:string):string;

function EatIO: integer;

procedure GiveUpTimeSlice;

const LastStrToIntResult : integer = 0;
      DirSep             : char    = {$ifdef Linux}'/'{$else}'\'{$endif};

procedure RegisterWUtils;

implementation

uses
{$ifdef win32}
  windows,
{$endif win32}
  Strings, Dos;

{$ifndef NOOBJREG}
const
  RUnsortedStringCollection: TStreamRec = (
     ObjType: 22500;
     VmtLink: Ofs(TypeOf(TUnsortedStringCollection)^);
     Load:    @TUnsortedStringCollection.Load;
     Store:   @TUnsortedStringCollection.Store
  );
{$endif}

{$ifdef TPUNIXLF}
  procedure readln(var t:text;var s:string);
  var
    c : char;
    i : longint;
  begin
    if TextRec(t).UserData[1]=2 then
      system.readln(t,s)
    else
     begin
      c:=#0;
      i:=0;
      while (not eof(t)) and (c<>#10) do
       begin
         read(t,c);
         if c<>#10 then
          begin
            inc(i);
            s[i]:=c;
          end;
       end;
      if (i>0) and (s[i]=#13) then
       begin
         dec(i);
         TextRec(t).UserData[1]:=2;
       end;
      s[0]:=chr(i);
     end;
  end;
{$endif}

function eofstream(s: pstream): boolean;
begin
  eofstream:=(s^.getpos>=s^.getsize);
end;

procedure ReadlnFromStream(Stream: PStream; var S:string;var linecomplete : boolean);
  var
    c : char;
    i : longint;
  begin
    linecomplete:=false;
    c:=#0;
    i:=0;
    { this created problems for lines longer than 255 characters
      now those lines are cutted into pieces without warning PM }
    while (not eofstream(stream)) and (c<>#10) and (i<255) do
     begin
       stream^.read(c,sizeof(c));
       if c<>#10 then
        begin
          inc(i);
          s[i]:=c;
        end;
     end;
    if (c=#10) or eofstream(stream) then
      linecomplete:=true;
    { if there was a CR LF then remove the CR Dos newline style }
    if (i>0) and (s[i]=#13) then
      dec(i);
    s[0]:=chr(i);
  end;


function Max(A,B: longint): longint;
begin
  if A>B then Max:=A else Max:=B;
end;

function Min(A,B: longint): longint;
begin
  if A<B then Min:=A else Min:=B;
end;

function CharStr(C: char; Count: byte): string;
{$ifndef FPC}
var S: string;
{$endif}
begin
{$ifdef FPC}
  CharStr[0]:=chr(Count);
  FillChar(CharStr[1],Count,C);
{$else}
  S[0]:=chr(Count);
  FillChar(S[1],Count,C);
  CharStr:=S;
{$endif}
end;

function UpcaseStr(const S: string): string;
var
  I: Longint;
begin
  for I:=1 to length(S) do
    if S[I] in ['a'..'z'] then
      UpCaseStr[I]:=chr(ord(S[I])-32)
    else
      UpCaseStr[I]:=S[I];
  UpcaseStr[0]:=S[0];
end;

function LowerCaseStr(S: string): string;
var
  I: Longint;
begin
  for I:=1 to length(S) do
    if S[I] in ['A'..'Z'] then
      LowerCaseStr[I]:=chr(ord(S[I])+32)
    else
      LowerCaseStr[I]:=S[I];
  LowercaseStr[0]:=S[0];
end;

function RExpand(const S: string; MinLen: byte): string;
begin
  if length(S)<MinLen then
    RExpand:=S+CharStr(' ',MinLen-length(S))
  else
    RExpand:=S;
end;

function LTrim(const S: string): string;
var
  i : longint;
begin
  i:=1;
  while (i<length(s)) and (s[i]=' ') do
   inc(i);
  LTrim:=Copy(s,i,255);
end;

function RTrim(const S: string): string;
var
  i : longint;
begin
  i:=length(s);
  while (i>0) and (s[i]=' ') do
   dec(i);
  RTrim:=Copy(s,1,i);
end;

function Trim(const S: string): string;
begin
  Trim:=RTrim(LTrim(S));
end;

function IntToStr(L: longint): string;
var S: string;
begin
  Str(L,S);
  IntToStr:=S;
end;


function StrToInt(const S: string): longint;
var L: longint;
    C: integer;
begin
  Val(S,L,C); if C<>0 then L:=-1;
  LastStrToIntResult:=C;
  StrToInt:=L;
end;

function GetStr(P: PString): string;
begin
  if P=nil then GetStr:='' else GetStr:=P^;
end;

function GetPChar(P: PChar): string;
begin
  if P=nil then GetPChar:='' else GetPChar:=StrPas(P);
end;

function DirOf(const S: string): string;
var D: DirStr; E: ExtStr; N: NameStr;
begin
  FSplit(S,D,N,E);
  if (D<>'') and (D[Length(D)]<>DirSep) then
   DirOf:=D+DirSep
  else
   DirOf:=D;
end;


function ExtOf(const S: string): string;
var D: DirStr; E: ExtStr; N: NameStr;
begin
  FSplit(S,D,N,E);
  ExtOf:=E;
end;


function NameOf(const S: string): string;
var D: DirStr; E: ExtStr; N: NameStr;
begin
  FSplit(S,D,N,E);
  NameOf:=N;
end;

function NameAndExtOf(const S: string): string;
var D: DirStr; E: ExtStr; N: NameStr;
begin
  FSplit(S,D,N,E);
  NameAndExtOf:=N+E;
end;

function DirAndNameOf(const S: string): string;
var D: DirStr; E: ExtStr; N: NameStr;
begin
  FSplit(S,D,N,E);
  DirAndNameOf:=D+N;
end;

{ return Dos GetFTime value or -1 if the file does not exist }
function GetFileTime(const FileName: string): longint;
var T: longint;
    f: file;
    FM: integer;
begin
  if FileName='' then
    T:=-1
  else
    begin
      FM:=FileMode; FileMode:=0;
      EatIO; DosError:=0;
      Assign(f,FileName);
      {$I-}
      Reset(f);
      if InOutRes=0 then
        begin
          GetFTime(f,T);
          Close(f);
        end;
      {$I+}
      if (EatIO<>0) or (DosError<>0) then T:=-1;
      FileMode:=FM;
    end;
  GetFileTime:=T;
end;

function GetShortName(const n:string):string;
{$ifdef win32}
      var
        hs,hs2 : string;
        i : longint;
{$endif}
{$ifdef go32v2}
      var
        hs : string;
{$endif}
      begin
        GetShortName:=n;
{$ifdef win32}
        hs:=n+#0;
        i:=Windows.GetShortPathName(@hs[1],@hs2[1],high(hs2));
        if (i>0) and (i<=high(hs2)) then
          begin
            hs2[0]:=chr(strlen(@hs2[1]));
            GetShortName:=hs2;
          end;
{$endif}
{$ifdef go32v2}
        hs:=n;
        if Dos.GetShortName(hs) then
         GetShortName:=hs;
{$endif}
      end;


function EatIO: integer;
begin
  EatIO:=IOResult;
end;


function LowCase(C: char): char;
begin
  if ('A'<=C) and (C<='Z') then C:=chr(ord(C)+32);
  LowCase:=C;
end;


function LowcaseStr(S: string): string;
var I: Longint;
begin
  for I:=1 to length(S) do
      S[I]:=Lowcase(S[I]);
  LowcaseStr:=S;
end;


function BoolToStr(B: boolean; const TrueS, FalseS: string): string;
begin
  if B then BoolToStr:=TrueS else BoolToStr:=FalseS;
end;

procedure TNoDisposeCollection.FreeItem(Item: Pointer);
begin
  { don't do anything here }
end;

constructor TUnsortedStringCollection.CreateFrom(ALines: PUnsortedStringCollection);
begin
  if Assigned(ALines)=false then Fail;
  inherited Init(ALines^.Count,ALines^.Count div 10);
  Assign(ALines);
end;

procedure TUnsortedStringCollection.Assign(ALines: PUnsortedStringCollection);
procedure AddIt(P: PString); {$ifndef FPC}far;{$endif}
begin
  Insert(NewStr(GetStr(P)));
end;
begin
  FreeAll;
  if Assigned(ALines) then
    ALines^.ForEach(@AddIt);
end;

function TUnsortedStringCollection.At(Index: Integer): PString;
begin
  At:=inherited At(Index);
end;

procedure TUnsortedStringCollection.FreeItem(Item: Pointer);
begin
  if Item<>nil then DisposeStr(Item);
end;

function TUnsortedStringCollection.GetItem(var S: TStream): Pointer;
begin
  GetItem:=S.ReadStr;
end;

procedure TUnsortedStringCollection.PutItem(var S: TStream; Item: Pointer);
begin
  S.WriteStr(Item);
end;

constructor TNulStream.Init;
begin
  inherited Init;
  Position:=0;
end;

function TNulStream.GetPos: Longint;
begin
  GetPos:=Position;
end;

function TNulStream.GetSize: Longint;
begin
  GetSize:=Position;
end;

procedure TNulStream.Read(var Buf; Count: Word);
begin
  Error(stReadError,0);
end;

procedure TNulStream.Seek(Pos: Longint);
begin
  if Pos<=Position then
    Position:=Pos;
end;

procedure TNulStream.Write(var Buf; Count: Word);
begin
  Inc(Position,Count);
end;

constructor TSubStream.Init(AStream: PStream; AStartPos, ASize: longint);
begin
  inherited Init;
  if Assigned(AStream)=false then Fail;
  S:=AStream; StartPos:=AStartPos; StreamSize:=ASize;
  Seek(0);
end;

function TSubStream.GetPos: Longint;
var Pos: longint;
begin
  Pos:=S^.GetPos; Dec(Pos,StartPos);
  GetPos:=Pos;
end;

function TSubStream.GetSize: Longint;
begin
  GetSize:=StreamSize;
end;

procedure TSubStream.Read(var Buf; Count: Word);
var Pos: longint;
    RCount: word;
begin
  Pos:=GetPos;
  if Pos+Count>StreamSize then RCount:=StreamSize-Pos else RCount:=Count;
  S^.Read(Buf,RCount);
  if RCount<Count then
    Error(stReadError,0);
end;

procedure TSubStream.Seek(Pos: Longint);
var RPos: longint;
begin
  if (Pos<=StreamSize) then RPos:=Pos else RPos:=StreamSize;
  S^.Seek(StartPos+RPos);
end;

procedure TSubStream.Write(var Buf; Count: Word);
begin
  S^.Write(Buf,Count);
end;

function TTextCollection.Compare(Key1, Key2: Pointer): Sw_Integer;
var K1: PString absolute Key1;
    K2: PString absolute Key2;
    R: Sw_integer;
    S1,S2: string;
begin
  S1:=UpCaseStr(K1^);
  S2:=UpCaseStr(K2^);
  if S1<S2 then R:=-1 else
  if S1>S2 then R:=1 else
  R:=0;
  Compare:=R;
end;

function TTextCollection.LookUp(const S: string; var Idx: sw_integer): string;
var OLI,ORI,Left,Right,Mid: integer;
    LeftP,RightP,MidP: PString;
    RL: integer;
    LeftS,MidS,RightS: string;
    FoundS: string;
    UpS : string;
begin
  Idx:=-1; FoundS:='';
  Left:=0; Right:=Count-1;
  UpS:=UpCaseStr(S);
  if Left<Right then
  begin
    while (Left<Right) do
    begin
      OLI:=Left; ORI:=Right;
      Mid:=Left+(Right-Left) div 2;
      LeftP:=At(Left); RightP:=At(Right); MidP:=At(Mid);
      LeftS:=UpCaseStr(LeftP^); MidS:=UpCaseStr(MidP^);
      RightS:=UpCaseStr(RightP^);
      if copy(MidS,1,length(UpS))=UpS then
        begin
          Idx:=Mid; FoundS:=GetStr(MidP);
        end;
{      else}
        if UpS<MidS then
          Right:=Mid
        else
          Left:=Mid;
      if (OLI=Left) and (ORI=Right) then
        Break;
    end;
  end;
  LookUp:=FoundS;
end;


procedure GiveUpTimeSlice;
{$ifdef GO32V2}{$define DOS}{$endif}
{$ifdef TP}{$define DOS}{$endif}
{$ifdef DOS}
var r: registers;
begin
  r.ax:=$1680;
  intr($2f,r);
end;
{$endif}
{$ifdef Linux}
begin
end;
{$endif}
{$ifdef Win32}
begin
end;
{$endif}
{$undef DOS}

procedure RegisterWUtils;
begin
{$ifndef NOOBJREG}
  RegisterType(RUnsortedStringCollection);
{$endif}
end;


END.
{
  $Log$
  Revision 1.16  2000-03-14 13:36:12  pierre
   * error for unexistant file in GetFileTime fixed

  Revision 1.15  2000/02/07 11:45:11  pierre
   + TUnsortedStringCollection CreateFrom/Assign/GetItem/PutItem from Gabor

  Revision 1.14  2000/01/20 00:30:32  pierre
   * Result of GetShortPathName is checked

  Revision 1.13  2000/01/17 12:20:03  pierre
   * uses windows needed for GetShortName

  Revision 1.12  2000/01/14 15:36:43  pierre
   + GetShortFileName used for tcodeeditor file opening

  Revision 1.11  2000/01/05 17:27:20  pierre
   + linecomplete arg for ReadlnFromStream

  Revision 1.10  2000/01/03 11:38:35  michael
  Changes from Gabor

  Revision 1.9  1999/12/01 16:19:46  pierre
   + GetFileTime moved here

  Revision 1.8  1999/10/25 16:39:03  pierre
   + GetPChar to avoid nil pointer problems

  Revision 1.7  1999/09/13 11:44:00  peter
    * fixes from gabor, idle event, html fix

  Revision 1.6  1999/08/24 22:01:48  pierre
   * readlnfromstream length check added

  Revision 1.5  1999/08/03 20:22:45  peter
    + TTab acts now on Ctrl+Tab and Ctrl+Shift+Tab...
    + Desktop saving should work now
       - History saved
       - Clipboard content saved
       - Desktop saved
       - Symbol info saved
    * syntax-highlight bug fixed, which compared special keywords case sensitive
      (for ex. 'asm' caused asm-highlighting, while 'ASM' didn't)
    * with 'whole words only' set, the editor didn't found occourences of the
      searched text, if the text appeared previously in the same line, but didn't
      satisfied the 'whole-word' condition
    * ^QB jumped to (SelStart.X,SelEnd.X) instead of (SelStart.X,SelStart.Y)
      (ie. the beginning of the selection)
    * when started typing in a new line, but not at the start (X=0) of it,
      the editor inserted the text one character more to left as it should...
    * TCodeEditor.HideSelection (Ctrl-K+H) didn't update the screen
    * Shift shouldn't cause so much trouble in TCodeEditor now...
    * Syntax highlight had problems recognizing a special symbol if it was
      prefixed by another symbol character in the source text
    * Auto-save also occours at Dos shell, Tool execution, etc. now...

  Revision 1.4  1999/04/07 21:56:06  peter
    + object support for browser
    * html help fixes
    * more desktop saving things
    * NODEBUG directive to exclude debugger

  Revision 1.2  1999/03/08 14:58:22  peter
    + prompt with dialogs for tools

  Revision 1.1  1999/03/01 15:51:43  peter
    + Log

}