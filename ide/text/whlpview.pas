{
    $Id$
    This file is part of the Free Pascal Integrated Development Environment
    Copyright (c) 1998 by Berczi Gabor

    Help display objects

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
unit WHlpView;

interface

uses
  Objects,Drivers,Commands,Views,
{$ifdef EDITORS}
  Editors,
{$else}
  WEditor,WCEdit,
{$endif}
  WUtils,WHelp;

{$IFNDEF EDITORS}
type
    TEditor = TCodeEditor; PEditor = PCodeEditor;
{$ENDIF}

const
     cmPrevTopic         = 90;
     HistorySize         = 30;

     CHelpViewer         = #33#34#35#36;
     CHelpFrame          = #37#37#38#38#39;

     cmHelpFilesChanged  = 57340;

type
      PHelpLink = ^THelpLink;
      THelpLink = record
        Bounds   : TRect;
        FileID   : longint;
        Context  : THelpCtx;
      end;

      PHelpColorArea = ^THelpColorArea;
      THelpColorArea = record
        Color    : byte;
        Bounds   : TRect;
        AttrMask : byte;
      end;

      PHelpKeyword = ^THelpKeyword;
      THelpKeyword = record
        KWord    : PString;
        Index    : sw_integer;
      end;

      PLinkCollection = ^TLinkCollection;
      TLinkCollection = object(TCollection)
        procedure FreeItem(Item: Pointer); virtual;
      end;

      PColorAreaCollection = ^TColorAreaCollection;
      TColorAreaCollection = object(TCollection)
        procedure FreeItem(Item: Pointer); virtual;
      end;

      PKeywordCollection = ^TKeywordCollection;
      TKeywordCollection = object({TSorted}TCollection)
        function  At(Index: sw_Integer): PHelpKeyword;
        procedure FreeItem(Item: Pointer); virtual;
        function  Compare(Key1, Key2: Pointer): sw_Integer; virtual;
      end;

{      TSearchRelation = (srEqual,srGreater,srLess,srGreatEqu,srLessEqu);

      PAdvancedStringCollection = ^TAdvancedStringCollection;
      TAdvancedStringCollection = object(TStringCollection)
        function SearchItem(Key: pointer; Rel: TSearchRelation; var Index: integer): boolean; virtual;
      end;}

      PNamedMark = ^TNamedMark;
      TNamedMark = object(TObject)
        constructor Init(const AName: string; AX, AY: integer);
        function    GetName: string;
        destructor  Done; virtual;
      private
        Name: PString;
        Pos: TPoint;
      end;

      PNamedMarkCollection = ^TNamedMarkCollection;
      TNamedMarkCollection = object(TSortedCollection)
        function At(Index: sw_Integer): PNamedMark;
        function Compare(Key1, Key2: Pointer): sw_Integer; virtual;
        function SearchMark(const Name: string): PNamedMark;
        function GetMarkPos(const Name: string; var P: TPoint): boolean;
        procedure Add(const Name: string; P: TPoint);
      end;

      PHelpTopic = ^THelpTopic;
      THelpTopic = object(TObject)
        Topic: PTopic;
        Lines: PUnsortedStringCollection;
        Links: PLinkCollection;
        NamedMarks: PNamedMarkCollection;
        ColorAreas: PColorAreaCollection;
      public
        constructor Init(ATopic: PTopic);
        procedure   SetParams(AMargin, AWidth: sw_integer); virtual;
        function    GetLineCount: sw_integer; virtual;
        function    GetLineText(Line: sw_integer): string; virtual;
        function    GetLinkCount: sw_integer; virtual;
        procedure   GetLinkBounds(Index: sw_integer; var R: TRect); virtual;
        function    GetLinkFileID(Index: sw_integer): word; virtual;
        function    GetLinkContext(Index: sw_integer): THelpCtx; virtual;
        function    GetColorAreaCount: sw_integer; virtual;
        procedure   GetColorAreaBounds(Index: sw_integer; var R: TRect); virtual;
        function    GetColorAreaColor(Index: sw_integer): word; virtual;
        function    GetColorAreaMask(Index: sw_integer): word; virtual;
        destructor  Done; virtual;
      private
        Width,Margin: sw_integer;
{        StockItem: boolean;}
        procedure  ReBuild;
      end;

      THelpHistoryEntry = record
        Context_     : THelpCtx;
        Delta_       : TPoint;
        CurPos_      : TPoint;
        CurLink_     : sw_integer;
        FileID_      : word;
      end;

      PHelpViewer = ^THelpViewer;
      THelpViewer = object(TEditor)
        Margin: sw_integer;
        HelpTopic: PHelpTopic;
        CurLink: sw_integer;
        constructor Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar);
        procedure   ChangeBounds(var Bounds: TRect); virtual;
        procedure   Draw; virtual;
        procedure   HandleEvent(var Event: TEvent); virtual;
        procedure   SetCurPtr(X,Y: sw_integer); virtual;
        function    GetLineCount: sw_integer; virtual;
        function    GetLineText(Line: sw_integer): string; virtual;
        function    GetDisplayText(I: sw_integer): string; virtual;
        function    GetLinkCount: sw_integer; virtual;
        procedure   GetLinkBounds(Index: sw_integer; var R: TRect); virtual;
        function    GetLinkFileID(Index: sw_integer): word; virtual;
        function    GetLinkContext(Index: sw_integer): THelpCtx; virtual;
        function    GetLinkText(Index: sw_integer): string; virtual;
        function    GetColorAreaCount: sw_integer; virtual;
        procedure   GetColorAreaBounds(Index: sw_integer; var R: TRect); virtual;
        function    GetColorAreaColor(Index: sw_integer): word; virtual;
        function    GetColorAreaMask(Index: sw_integer): word; virtual;
        procedure   SelectNextLink(ANext: boolean); virtual;
        procedure   SwitchToIndex; virtual;
        procedure   SwitchToTopic(SourceFileID: word; Context: THelpCtx); virtual;
        procedure   SetTopic(Topic: PTopic); virtual;
        procedure   SetCurLink(Link: sw_integer); virtual;
        procedure   SelectLink(Index: sw_integer); virtual;
        procedure   PrevTopic; virtual;
        procedure   RenderTopic; virtual;
        procedure   Lookup(S: string); virtual;
        function    GetPalette: PPalette; virtual;
        constructor Load(var S: TStream);
        procedure   Store(var S: TStream);
        destructor  Done; virtual;
      private
        History    : array[0..HistorySize] of THelpHistoryEntry;
        HistoryPtr : integer;
        WordList   : PKeywordCollection;
        Lookupword : string;
        InLookUp   : boolean;
        IndexTopic : PTopic;
        IndexHelpTopic: PHelpTopic;
        function    LinkContainsPoint(var R: TRect; var P: TPoint): boolean;
        procedure   ISwitchToTopic(SourceFileID: word; Context: THelpCtx; RecordInHistory: boolean);
        procedure   ISwitchToTopicPtr(P: PTopic; RecordInHistory: boolean);
        procedure   BuildTopicWordList;
      end;

      PHelpFrame = ^THelpFrame;
      THelpFrame = object(TFrame)
        function GetPalette: PPalette; virtual;
      end;

      PHelpWindow = ^THelpWindow;
      THelpWindow = object(TWindow)
        HSB,VSB : PScrollBar;
        HelpView: PHelpViewer;
        HideOnClose: boolean;
        constructor Init(var Bounds: TRect; ATitle: TTitleStr; ASourceFileID: word; AContext: THelpCtx; ANumber: Integer);
        procedure   InitFrame; virtual;
        procedure   InitScrollBars; virtual;
        procedure   InitHelpView; virtual;
        procedure   ShowIndex; virtual;
        procedure   ShowTopic(SourceFileID: word; Context: THelpCtx); virtual;
        procedure   HandleEvent(var Event: TEvent); virtual;
        procedure   Close; virtual;
        function    GetPalette: PPalette; virtual; { needs to be overriden }
      end;

implementation

uses
  Video,
  WConsts,WViews;

const CommentColor = Blue;

function NewLink(FileID: longint; Topic: THelpCtx; StartP, EndP: TPoint): PHelpLink;
var P: PHelpLink;
begin
  New(P); FillChar(P^, SizeOf(P^), 0);
  P^.FileID:=FileID;
  P^.Context:=Topic; P^.Bounds.A:=StartP; P^.Bounds.B:=EndP;
  NewLink:=P;
end;

procedure DisposeLink(P: PHelpLink);
begin
  if P<>nil then Dispose(P);
end;

function NewColorArea(Color, AttrMask: byte; StartP, EndP: TPoint): PHelpColorArea;
var P: PHelpColorArea;
begin
  New(P); FillChar(P^, SizeOf(P^), 0);
  P^.Color:=Color; P^.AttrMask:=AttrMask;
  P^.Bounds.A:=StartP; P^.Bounds.B:=EndP;
  NewColorArea:=P;
end;

procedure DisposeColorArea(P: PHelpColorArea);
begin
  if P<>nil then Dispose(P);
end;

function NewKeyword(Index: sw_integer; KWord: string): PHelpKeyword;
var P: PHelpKeyword;
begin
  New(P); FillChar(P^, SizeOf(P^), 0);
  P^.Index:=Index; P^.KWord:=NewStr(KWord);
  NewKeyword:=P;
end;

procedure DisposeKeyword(P: PHelpKeyword);
begin
  if P<>nil then
  begin
    if P^.KWord<>nil then DisposeStr(P^.KWord);
    Dispose(P);
  end;
end;

procedure TLinkCollection.FreeItem(Item: Pointer);
begin
  if Item<>nil then DisposeLink(Item);
end;

procedure TColorAreaCollection.FreeItem(Item: Pointer);
begin
  if Item<>nil then DisposeColorArea(Item);
end;

function TKeywordCollection.At(Index: sw_Integer): PHelpKeyword;
begin
  At:=inherited At(Index);
end;

procedure TKeywordCollection.FreeItem(Item: Pointer);
begin
  if Item<>nil then DisposeKeyword(Item);
end;

function TKeywordCollection.Compare(Key1, Key2: Pointer): sw_Integer;
var R: sw_integer;
    K1: PHelpKeyword absolute Key1;
    K2: PHelpKeyword absolute Key2;
    S1,S2: string;
begin
  S1:=UpcaseStr(K1^.KWord^); S2:=UpcaseStr(K2^.KWord^);
  if S1<S2 then R:=-1 else
  if S1>S2 then R:=1 else
  R:=0;
  Compare:=R;
end;

{function TAdvancedStringCollection.SearchItem(Key: pointer; Rel: TSearchRelation; var Index: sw_integer): boolean;
var
  L, H, I, C: sw_Integer;
const resSmaller = -1; resEqual = 0; resGreater = 1;
begin
  Index:=-1;
  case Rel of
    srEqual  :
      while (L <= H) and (Index=-1) do
      begin
        I := (L + H) shr 1;
        C := Compare(KeyOf(Items^[I]), Key);
        if C = resSmaller then L := I + 1 else
        begin
          H := I - 1;
          if C = resEqual then
          begin
            if not Duplicates then L := I;
            Index := L;
          end;
        end;
      end;
    srGreater  :
      begin
      end;
    srLess     :
      ;
    srGreatEqu :
      ;
    srLessEqu  :
      ;
  else Exit;
  end;
  Search:=Index<>-1;
end;}

constructor TNamedMark.Init(const AName: string; AX, AY: integer);
begin
  inherited Init;
  Name:=NewStr(AName);
  Pos.X:=AX; Pos.Y:=AY;
end;

function TNamedMark.GetName: string;
begin
  GetName:=GetStr(Name);
end;

destructor TNamedMark.Done;
begin
  if Assigned(Name) then DisposeStr(Name); Name:=nil;
  inherited Done;
end;

function TNamedMarkCollection.At(Index: sw_Integer): PNamedMark;
begin
  At:=inherited At(Index);
end;

function TNamedMarkCollection.Compare(Key1, Key2: Pointer): sw_Integer;
var K1: PNamedMark absolute Key1;
    K2: PNamedMark absolute Key2;
    R: integer;
    N1,N2: string;
begin
  N1:=UpcaseStr(K1^.GetName); N2:=UpcaseStr(K2^.GetName);
  if N1<N2 then R:=-1 else
  if N1>N2 then R:= 1 else
  R:=0;
  Compare:=R;
end;

function TNamedMarkCollection.SearchMark(const Name: string): PNamedMark;
var M,P: PNamedMark;
    I: sw_integer;
begin
  New(M, Init(Name,0,0));
  if Search(M,I)=false then P:=nil else
    P:=At(I);
  Dispose(M, Done);
  SearchMark:=P;
end;

function TNamedMarkCollection.GetMarkPos(const Name: string; var P: TPoint): boolean;
var M: PNamedMark;
begin
  M:=SearchMark(Name);
  if Assigned(M) then
    P:=M^.Pos;
  GetMarkPos:=Assigned(M);
end;

procedure TNamedMarkCollection.Add(const Name: string; P: TPoint);
begin
  Insert(New(PNamedMark, Init(Name, P.X, P.Y)));
end;

constructor THelpTopic.Init(ATopic: PTopic);
begin
  inherited Init;
  Topic:=ATopic;
  New(Lines, Init(100,100)); New(Links, Init(50,50)); New(ColorAreas, Init(50,50));
  New(NamedMarks, Init(10,10));
end;

procedure THelpTopic.SetParams(AMargin, AWidth: sw_integer);
begin
  if Width<>AWidth then
  begin
    Width:=AWidth; Margin:=AMargin;
    ReBuild;
  end;
end;

procedure THelpTopic.ReBuild;
var TextPos,LinkNo,NamedMarkNo: sw_word;
    Line,CurWord: string;
    C: char;
    InLink,InCodeArea,InColorArea: boolean;
    LinkStart,LinkEnd,CodeAreaStart,CodeAreaEnd: TPoint;
    ColorAreaStart,ColorAreaEnd: TPoint;
    ColorAreaType: (atText,atFull);
    CurPos: TPoint;
    ZeroLevel: sw_integer;
    LineStart,NextLineStart: sw_integer;
    LineAlign : (laLeft,laCenter,laRight);
    FirstLink,LastLink: sw_integer;
    AreaColor: word;
    NextByte: (nbNormal,nbAreaColor);
procedure ClearLine;
begin
  Line:='';
end;
procedure AddWord(TheWord: string); forward;
procedure NextLine;
var P: sw_integer;
    I,Delta: sw_integer;
begin
  Line:=CharStr(' ',Margin)+Line;
  repeat
    P:=Pos(#255,Line);
    if P>0 then Line[P]:=#32;
  until P=0;
  while copy(Line,length(Line),1)=' ' do Delete(Line,length(Line),1);
  Delta:=0;
  if Line<>'' then
  case LineAlign of
    laLeft    : ;
    laCenter  : if Margin+length(Line)+Margin<Width then
                  begin
                    Delta:=(Width-(Margin+length(Line)+Margin)) div 2;
                    Line:=CharStr(' ',Delta)+Line;
                  end;
    laRight   : if Margin+length(Line)+Margin<Width then
                  begin
                    Delta:=Width-(Margin+length(Line)+Margin);
                    Line:=CharStr(' ',Delta)+Line;
                  end;
  end;
  if (Delta>0) and (FirstLink<>LastLink) then
  for I:=FirstLink to LastLink-1 do
    with PHelpLink(Links^.At(I))^ do
      Bounds.Move(Delta,0);
  if Line='' then Line:=' ';
  Lines^.Insert(NewStr(Line));
  ClearLine;
  LineStart:=NextLineStart;
  CurPos.X:=Margin+LineStart; Line:=CharStr(#255,LineStart); Inc(CurPos.Y);
  if InLink then LinkStart:=CurPos;
  FirstLink:=LastLink;
end;
procedure FlushLine;
var W: string;
begin
  if CurWord<>'' then begin W:=CurWord; CurWord:=''; AddWord(W); end;
  NextLine;
end;
procedure AddWord(TheWord: string);
var W: string;
begin
  W:=TheWord;
  while (length(W)>0) and (W[length(W)] in [' ',#255]) do
     Delete(W,length(W),1);
  if (copy(Line+TheWord,1,1)<>' ') then
    if (Line<>'') and (Margin+length(Line)+length(W)+Margin>Width) then
       NextLine;
  Line:=Line+TheWord;
  CurPos.X:=Margin+length(Line);
end;
procedure CheckZeroLevel;
begin
  if ZeroLevel<>0 then
     begin
       if CurWord<>'' then AddWord(CurWord+' ');
       CurWord:='';
       ZeroLevel:=0;
     end;
end;
procedure EndColorArea;
var Mask: word;
begin
  if ColorAreaType=atText then Mask:=$f0 else Mask:=$00;
  if CurWord<>'' then AddWord(CurWord); CurWord:='';
  ColorAreaEnd:=CurPos; Dec(ColorAreaEnd.X);
  ColorAreas^.Insert(NewColorArea(AreaColor,Mask,ColorAreaStart,ColorAreaEnd));
  InColorArea:=false; AreaColor:=0;
end;
begin
  Lines^.FreeAll; Links^.FreeAll; NamedMarks^.FreeAll; ColorAreas^.FreeAll;
  if Topic=nil then Lines^.Insert(NewStr(msg_nohelpavailabelforthistopic)) else
  begin
    LineStart:=0; NextLineStart:=0;
    TextPos:=0; ClearLine; CurWord:=''; Line:='';
    CurPos.X:=Margin+LineStart; CurPos.Y:=0; LinkNo:=0;
    NamedMarkNo:=0;
    InLink:=false; InCodeArea:=false; InColorArea:=false; ZeroLevel:=0;
    LineAlign:=laLeft;
    FirstLink:=0; LastLink:=0; NextByte:=nbNormal;
    while (TextPos<Topic^.TextSize) do
    begin
      C:=chr(PByteArray(Topic^.Text)^[TextPos]);
      case NextByte of
        nbAreaColor :
          begin
            AreaColor:=ord(C);
            NextByte:=nbNormal;
          end;
        nbNormal :
          begin
            case C of
              hscLineBreak :
                  {if ZeroLevel=0 then ZeroLevel:=1 else
                      begin FlushLine; FlushLine; ZeroLevel:=0; end;}
                   if InLink then CurWord:=CurWord+' ' else
                     begin
                       NextLineStart:=0;
                       FlushLine;
                       LineStart:=0;
                       LineAlign:=laLeft;
                     end;
              #1 : Break;
              hscLink :
                   begin
                     CheckZeroLevel;
                     if InLink=false then
                        begin LinkStart:=CurPos; InLink:=true; end else
                      begin
                        if CurWord<>'' then AddWord(CurWord); CurWord:='';
                        LinkEnd:=CurPos; Dec(LinkEnd.X);
                        if Topic^.Links<>nil then
                          begin
                            Inc(LastLink);
                            if LinkNo<Topic^.LinkCount then
                            Links^.Insert(NewLink(Topic^.Links^[LinkNo].FileID,
                              Topic^.Links^[LinkNo].Context,LinkStart,LinkEnd));
                            Inc(LinkNo);
                          end;
                        InLink:=false;
                      end;
                    end;
              hscLineStart :
                   begin
                     NextLineStart:=length(Line)+length(CurWord);
      {               LineStart:=LineStart+(NextLineStart-LineStart);}
                   end;
              hscCode :
                   begin
                     if InCodeArea=false then
                        CodeAreaStart:=CurPos else
                      begin
                        if CurWord<>'' then AddWord(CurWord); CurWord:='';
                        CodeAreaEnd:=CurPos; Dec(CodeAreaEnd.X);
                        ColorAreas^.Insert(NewColorArea(CommentColor,$f0,CodeAreaStart,CodeAreaEnd));
                      end;
                     InCodeArea:=not InCodeArea;
                   end;
              hscCenter :
                   LineAlign:=laCenter;
              hscRight  :
                   LineAlign:=laCenter;
              hscNamedMark :
                   begin
                     if NamedMarkNo<Topic^.NamedMarks^.Count then
                       NamedMarks^.Add(GetStr(Topic^.NamedMarks^.At(NamedMarkNo)),CurPos);
                     Inc(NamedMarkNo);
                   end;
              hscTextAttr,hscTextColor :
                   begin
                     if InColorArea then
                       EndColorArea;
                     if C=hscTextAttr then
                       ColorAreaType:=atFull
                     else
                       ColorAreaType:=atText;
                     NextByte:=nbAreaColor;
                     ColorAreaStart:=CurPos;
                     InColorArea:=true;
                   end;
              hscNormText :
                   begin
                     if InColorArea then
                       EndColorArea;
                   end;
              #32: if InLink then CurWord:=CurWord+C else
                      begin CheckZeroLevel; AddWord(CurWord+C); CurWord:=''; end;
            else begin CheckZeroLevel; CurWord:=CurWord+C; end;
            end;
          end;
      end;
      CurPos.X:=Margin+length(Line)+length(CurWord);
      Inc(TextPos);
    end;
    if (Line<>'') or (CurWord<>'') then FlushLine;
  end;
end;

function THelpTopic.GetLineCount: sw_integer;
begin
  GetLineCount:=Lines^.Count;
end;

function THelpTopic.GetLineText(Line: sw_integer): string;
var S: string;
begin
  if Line<GetLineCount then S:=PString(Lines^.At(Line))^ else S:='';
  GetLineText:=S;
end;

function THelpTopic.GetLinkCount: sw_integer;
begin
  GetLinkCount:=Links^.Count;
end;

procedure THelpTopic.GetLinkBounds(Index: sw_integer; var R: TRect);
var P: PHelpLink;
begin
  P:=Links^.At(Index);
  R:=P^.Bounds;
end;

function THelpTopic.GetLinkFileID(Index: sw_integer): word;
var P: PHelpLink;
begin
  P:=Links^.At(Index);
  GetLinkFileID:=P^.FileID;
end;

function THelpTopic.GetLinkContext(Index: sw_integer): THelpCtx;
var P: PHelpLink;
begin
  P:=Links^.At(Index);
  GetLinkContext:=P^.Context;
end;

function THelpTopic.GetColorAreaCount: sw_integer;
begin
  GetColorAreaCount:=ColorAreas^.Count;
end;

procedure THelpTopic.GetColorAreaBounds(Index: sw_integer; var R: TRect);
var P: PHelpColorArea;
begin
  P:=ColorAreas^.At(Index);
  R:=P^.Bounds;
end;

function THelpTopic.GetColorAreaColor(Index: sw_integer): word;
var P: PHelpColorArea;
begin
  P:=ColorAreas^.At(Index);
  GetColorAreaColor:=P^.Color;
end;

function THelpTopic.GetColorAreaMask(Index: sw_integer): word;
var P: PHelpColorArea;
begin
  P:=ColorAreas^.At(Index);
  GetColorAreaMask:=P^.AttrMask;
end;

destructor THelpTopic.Done;
begin
  inherited Done;
  Dispose(Lines, Done); Dispose(Links, Done); Dispose(ColorAreas, Done);
  Dispose(NamedMarks, Done);
  if (Topic<>nil) then DisposeTopic(Topic);
end;

constructor THelpViewer.Init(var Bounds: TRect; AHScrollBar, AVScrollBar: PScrollBar);
begin
  inherited Init(Bounds, AHScrollBar, AVScrollBar, nil, nil);
  Flags:=efInsertMode; ReadOnly:=true;
  New(WordList, Init(50,50));
  Margin:=1; CurLink:=-1;
end;

procedure THelpViewer.ChangeBounds(var Bounds: TRect);
begin
  if Owner<>nil then Owner^.Lock;
  inherited ChangeBounds(Bounds);
  if (HelpTopic<>nil) and (HelpTopic^.Topic<>nil) and
     (HelpTopic^.Topic^.FileID<>0) then RenderTopic;
  if Owner<>nil then Owner^.UnLock;
end;

procedure THelpViewer.RenderTopic;
begin
  if HelpTopic<>nil then
    HelpTopic^.SetParams(Margin,Size.X);
{$ifndef EDITORS}
  SetLimit(255,GetLineCount);
{$endif}
  DrawView;
end;

function THelpViewer.LinkContainsPoint(var R: TRect; var P: TPoint): boolean;
var OK: boolean;
begin
  if (R.A.Y=R.B.Y) then
    OK:= (P.Y=R.A.Y) and (R.A.X<=P.X) and (P.X<=R.B.X) else
    OK:=
    ( (R.A.Y=P.Y) and (R.A.X<=P.X) ) or
    ( (R.A.Y<P.Y) and (P.Y<R.B.Y)  ) or
    ( (R.B.Y=P.Y) and (P.X<=R.B.X) );
  LinkContainsPoint:=OK;
end;

procedure THelpViewer.SetCurPtr(X,Y: sw_integer);
var OldCurLink,I: sw_integer;
    OldPos,P: TPoint;
    R: TRect;
begin
  OldPos:=CurPos;
  OldCurLink:=CurLink;
  inherited SetCurPtr(X,Y);
  CurLink:=-1;
  P:=CurPos;
  for I:=0 to GetLinkCount-1 do
  begin
    GetLinkBounds(I,R);
    if LinkContainsPoint(R,P) then
       begin CurLink:=I; Break; end;
  end;
  if OldCurLink<>CurLink then DrawView;
  if ((OldPos.X<>CurPos.X) or (OldPos.Y<>CurPos.Y)) and (InLookup=false) then
     Lookup('');
end;

function THelpViewer.GetLineCount: sw_integer;
var Count: sw_integer;
begin
  if HelpTopic=nil then Count:=0 else Count:=HelpTopic^.GetLineCount;
  GetLineCount:=Count;
end;

function THelpViewer.GetDisplayText(I: sw_integer): string;
begin
  GetDisplayText:=ExtractTabs(GetLineText(I),DefaultTabSize);
end;

function THelpViewer.GetLineText(Line: sw_integer): string;
var S: string;
begin
  if HelpTopic=nil then S:='' else S:=HelpTopic^.GetLineText(Line);
  GetLineText:=S;
end;

function THelpViewer.GetLinkCount: sw_integer;
var Count: sw_integer;
begin
  if HelpTopic=nil then Count:=0 else Count:=HelpTopic^.GetLinkCount;
  GetLinkCount:=Count;
end;

procedure THelpViewer.GetLinkBounds(Index: sw_integer; var R: TRect);
begin
  HelpTopic^.GetLinkBounds(Index,R);
end;

function THelpViewer.GetLinkFileID(Index: sw_integer): word;
begin
  GetLinkFileID:=HelpTopic^.GetLinkFileID(Index);
end;

function THelpViewer.GetLinkContext(Index: sw_integer): THelpCtx;
begin
  GetLinkContext:=HelpTopic^.GetLinkContext(Index);
end;

function THelpViewer.GetLinkText(Index: sw_integer): string;
var S: string;
    R: TRect;
    Y,StartX,EndX: sw_integer;
begin
  S:=''; GetLinkBounds(Index,R);
  Y:=R.A.Y;
  while (Y<=R.B.Y) do
  begin
    if Y=R.A.Y then StartX:=R.A.X else StartX:=Margin;
    if Y=R.B.Y then EndX:=R.B.X else EndX:=255;
    S:=S+copy(GetLineText(Y),StartX+1,EndX-StartX+1);
    Inc(Y);
  end;
  GetLinkText:=S;
end;

function THelpViewer.GetColorAreaCount: sw_integer;
var Count: sw_integer;
begin
  if HelpTopic=nil then Count:=0 else Count:=HelpTopic^.GetColorAreaCount;
  GetColorAreaCount:=Count;
end;

procedure THelpViewer.GetColorAreaBounds(Index: sw_integer; var R: TRect);
begin
  HelpTopic^.GetColorAreaBounds(Index,R);
end;

function THelpViewer.GetColorAreaColor(Index: sw_integer): word;
begin
  GetColorAreaColor:=HelpTopic^.GetColorAreaColor(Index);
end;

function THelpViewer.GetColorAreaMask(Index: sw_integer): word;
begin
  GetColorAreaMask:=HelpTopic^.GetColorAreaMask(Index);
end;

procedure THelpViewer.SelectNextLink(ANext: boolean);
var I,Link: sw_integer;
    R: TRect;
begin
  if HelpTopic=nil then Exit;
  Link:=CurLink;
  if Link<>-1 then
  begin
    if ANext then
       begin Inc(Link); if Link>=GetLinkCount then Link:=0; end else
       begin Dec(Link); if Link=-1 then Link:=GetLinkCount-1; end;
  end else
  for I:=0 to GetLinkCount-1 do
  begin
    GetLinkBounds(I,R);
    if (R.A.Y>CurPos.Y) or
       (R.A.Y=CurPos.Y) and (R.A.X>CurPos.X) then
       begin Link:=I; Break; end;
  end;
  if (Link=-1) and (GetLinkCount>0) then
     if ANext then Link:=0
              else Link:=GetLinkCount-1;
  SetCurLink(Link);
end;

procedure THelpViewer.SetCurLink(Link: sw_integer);
var R: TRect;
begin
  if Link<>-1 then
  begin
    GetLinkBounds(Link,R);
    SetCurPtr(R.A.X,R.A.Y);
    TrackCursor(true);
  end;
end;

procedure THelpViewer.SwitchToIndex;
begin
  if IndexTopic=nil then
     IndexTopic:=HelpFacility^.BuildIndexTopic;
  ISwitchToTopicPtr(IndexTopic,true);
end;

procedure THelpViewer.SwitchToTopic(SourceFileID: word; Context: THelpCtx);
begin
  ISwitchToTopic(SourceFileID,Context,true);
end;

procedure THelpViewer.ISwitchToTopic(SourceFileID: word; Context: THelpCtx; RecordInHistory: boolean);
var P: PTopic;
begin
  if HelpFacility=nil then P:=nil else
    if (SourceFileID=0) and (Context=0) and (HelpTopic<>nil) then
       P:=IndexTopic else
     P:=HelpFacility^.LoadTopic(SourceFileID, Context);
  ISwitchToTopicPtr(P,RecordInHistory);
end;

procedure THelpViewer.ISwitchToTopicPtr(P: PTopic; RecordInHistory: boolean);
var HistoryFull: boolean;
begin
  if (P<>nil) and RecordInHistory and (HelpTopic<>nil) then
  begin
    HistoryFull:=HistoryPtr>=HistorySize;
    if HistoryFull then
       Move(History[1],History[0],SizeOf(History)-SizeOf(History[0]));
    with History[HistoryPtr] do
    begin
      {SourceTopic_:=SourceTopic; }Context_:=HelpTopic^.Topic^.HelpCtx;
      FileID_:=HelpTopic^.Topic^.FileID;
      Delta_:=Delta; CurPos_:=CurPos; CurLink_:=CurLink;
    end;
    if HistoryFull=false then Inc(HistoryPtr);
  end;

  if Owner<>nil then Owner^.Lock;
  SetTopic(P);
  DrawView;
  if Owner<>nil then Owner^.UnLock;
end;

procedure THelpViewer.PrevTopic;
begin
  if HistoryPtr>0 then
  begin
    if Owner<>nil then Owner^.Lock;
    Dec(HistoryPtr);
    with History[HistoryPtr] do
    begin
      ISwitchToTopic(FileID_,Context_,false);
      ScrollTo(Delta_.X,Delta_.Y);
      SetCurPtr(CurPos_.X,CurPos_.Y);
      TrackCursor(false);
      if CurLink<>CurLink_ then SetCurLink(CurLink_);
    end;
    DrawView;
    if Owner<>nil then Owner^.UnLock;
  end;
end;

procedure THelpViewer.SetTopic(Topic: PTopic);
var Bookmark: string;
    P: TPoint;
begin
  CurLink:=-1;
  if (HelpTopic=nil) or (Topic<>HelpTopic^.Topic) then
 begin
  if (HelpTopic<>nil) and (HelpTopic<>IndexHelpTopic) then
     Dispose(HelpTopic, Done);
  HelpTopic:=nil;
  if Topic<>nil then
     begin
       if (Topic=IndexTopic) and (IndexHelpTopic<>nil) then
          HelpTopic:=IndexHelpTopic else
       New(HelpTopic, Init(Topic));
       if Topic=IndexTopic then
          IndexHelpTopic:=HelpTopic;
     end;
 end;
  if Owner<>nil then Owner^.Lock;
  SetCurPtr(0,0); TrackCursor(false);
  RenderTopic;
  BuildTopicWordList;
  Lookup('');
  if Assigned(Topic) then
  if Topic^.StartNamedMark>0 then
   if Topic^.NamedMarks^.Count>=Topic^.StartNamedMark then
    begin
      Bookmark:=GetStr(Topic^.NamedMarks^.At(Topic^.StartNamedMark-1));
      if HelpTopic^.NamedMarks^.GetMarkPos(Bookmark,P) then
      begin
        SetCurPtr(P.X,P.Y);
        ScrollTo(0,Max(0,P.Y-1));
      end;
    end;
  SetSelection(CurPos,CurPos);
  DrawView;
  if Owner<>nil then Owner^.UnLock;
end;

procedure THelpViewer.BuildTopicWordList;
var I: sw_integer;
begin
  WordList^.FreeAll;
  for I:=0 to GetLinkCount-1 do
    WordList^.Insert(NewKeyword(I,Trim(GetLinkText(I))));
end;

procedure THelpViewer.Lookup(S: string);
var Index, I: Sw_integer;
    W: string;
    OldLookup: string;
    R: TRect;
    P: PHelpKeyword;
begin
  InLookup:=true;
  OldLookup:=LookupWord;
  S:=UpcaseStr(S);
  Index:=-1;
  I:=0; {J:=0;
  while (J<GetLinkCount) do
    begin
      GetLinkBounds(J,R);
      if (R.A.Y<CurPos.Y) or ((R.A.Y=CurPos.Y) and (R.B.X<CurPos.X))
         then Inc(J) else
           begin I:=J; Break; end;
    end;}
  if S='' then LookupWord:='' else
  begin
    while (Index=-1) and (I<WordList^.Count) do
      begin
        P:=WordList^.At(I);
        if P^.KWord<>nil then
          begin
            W:=UpcaseStr(Trim(P^.KWord^));
            if copy(W,1,length(S))=S then Index:=I;
          end;
{        if W>S then Break else}
        Inc(I);
      end;
    if Index<>-1 then
    begin
      W:=Trim(WordList^.At(Index)^.KWord^);
      LookupWord:=copy(W,1,length(S));
    end;
  end;

  if LookupWord<>OldLookup then
  begin
    if Index=-1 then SetCurLink(CurLink) else
    begin
      if Owner<>nil then Owner^.Lock;
      P:=WordList^.At(Index);
      S:=GetLinkText(P^.Index);
      I:=Pos(LookupWord,S); if I=0 then I:=1;
      GetLinkBounds(P^.Index,R);
      SetCurPtr(R.A.X+(I-1)+length(Lookupword),R.A.Y);
      CurLink:=P^.Index; DrawView;
      TrackCursor(true);
      if Owner<>nil then Owner^.UnLock;
    end;
  end;
  InLookup:=false;
end;

procedure THelpViewer.SelectLink(Index: sw_integer);
var ID: word;
    Ctx: THelpCtx;
begin
  if Index=-1 then Exit;
  if HelpTopic=nil then begin ID:=0; Ctx:=0; end else
     begin
       ID:=GetLinkFileID(Index);
       Ctx:=GetLinkContext(Index);
     end;
  SwitchToTopic(ID,Ctx);
end;

procedure THelpViewer.HandleEvent(var Event: TEvent);
var DontClear: boolean;
procedure GetMousePos(var P: TPoint);
begin
  MakeLocal(Event.Where,P);
  Inc(P.X,Delta.X); Inc(P.Y,Delta.Y);
end;
begin
  case Event.What of
    evMouseDown :
      if MouseInView(Event.Where) then
      if (Event.Buttons=mbLeftButton) and (Event.Double) then
      begin
        inherited HandleEvent(Event);
        if CurLink<>-1 then
           SelectLink(CurLink);
      end;
    evBroadcast :
      case Event.Command of
        cmHelpFilesChanged :
          begin
            if HelpTopic=IndexHelpTopic then HelpTopic:=nil;
            IndexTopic:=nil;
            if IndexHelpTopic<>nil then Dispose(IndexHelpTopic, Done);
            IndexHelpTopic:=nil;
          end;
      end;
    evCommand :
      begin
        DontClear:=false;
        case Event.Command of
          cmPrevTopic :
            PrevTopic;
        else DontClear:=true;
        end;
        if DontClear=false then ClearEvent(Event);
      end;
    evKeyDown :
      begin
        DontClear:=false;
        case Event.KeyCode of
          kbTab :
            SelectNextLink(true);
          kbShiftTab :
            begin NoSelect:=true; SelectNextLink(false); NoSelect:=false; end;
          kbEnter :
            if CurLink<>-1 then
              SelectLink(CurLink);
        else
          case Event.CharCode of
             #32..#255 :
               begin NoSelect:=true; Lookup(LookupWord+Event.CharCode); NoSelect:=false; end;
          else DontClear:=true;
          end;
        end;
        TrackCursor(false);
        if DontClear=false then ClearEvent(Event);
      end;
  end;
  inherited HandleEvent(Event);
end;

procedure THelpViewer.Draw;
var NormalColor, LinkColor,
    SelectColor, SelectionColor: word;
    B: TDrawBuffer;
    DX,DY,X,Y,I,MinX,MaxX,ScreenX: sw_integer;
    LastLinkDrawn,LastColorAreaDrawn: sw_integer;
    S: string;
    R: TRect;
{$ifndef EDITORS}
    SelR : TRect;
{$endif}
    C,Mask: word;
    CurP: TPoint;
    ANDSB,ORSB: word;
begin
  if LockFlag>0 then
    begin
      DrawCalled:=true;
      Exit;
    end;
  DrawCalled:=false;


  NormalColor:=GetColor(1); LinkColor:=GetColor(2);
  SelectColor:=GetColor(3); SelectionColor:=GetColor(4);
{$ifndef EDITORS}
  SelR.A:=SelStart; SelR.B:=SelEnd;
{$endif}
  LastLinkDrawn:=0; LastColorAreaDrawn:=0;
  for DY:=0 to Size.Y-1 do
  begin
    Y:=Delta.Y+DY;
    MoveChar(B,' ',NormalColor,Size.X);
    if Y<GetLineCount then
    begin
      S:=copy(GetLineText(Y),Delta.X+1,255);
      S:=copy(S,1,MaxViewWidth);
      MoveStr(B,S,NormalColor);

      for I:=LastColorAreaDrawn to GetColorAreaCount-1 do
      begin
        GetColorAreaBounds(I,R);
        if R.A.Y>Y then Break;
        LastColorAreaDrawn:=I;
        if Y=R.B.Y then MaxX:=R.B.X else MaxX:=(length(S)-1);
        if Y=R.A.Y then MinX:=R.A.X else MinX:=0;
        if (R.A.Y<=Y) and (Y<=R.B.Y) then
        begin
          C:=GetColorAreaColor(I);
          Mask:=GetColorAreaMask(I);
          for DX:=MinX to MaxX do
          begin
            X:=DX;
            ScreenX:=X-(Delta.X);
            if (ScreenX>0) and (ScreenX<=High(B)) then
            begin
{              CurP.X:=X; CurP.Y:=Y;
              if LinkAreaContainsPoint(R,CurP) then}
(*              B[ScreenX]:=(B[ScreenX] and $f0ff) or (C shl 8);*)
              ANDSB:=(Mask shl 8)+$ff;
              ORSB:=(C shl 8);
              B[ScreenX]:=(B[ScreenX] and ANDSB) or ORSB;
            end;
          end;
        end;
      end;

      for I:=LastLinkDrawn to GetLinkCount-1 do
      begin
        GetLinkBounds(I,R);
        if R.A.Y>Y then Break;
        LastLinkDrawn:=I;
        if Y=R.B.Y then MaxX:=R.B.X else MaxX:=(length(S)-1);
        if Y=R.A.Y then MinX:=R.A.X else MinX:=0;
        if (R.A.Y<=Y) and (Y<=R.B.Y) then
          for DX:=MinX to MaxX do
          begin
            X:=DX;
            ScreenX:=X-(Delta.X);
            if (ScreenX>=0) and (ScreenX<=High(B)) then
            begin
              CurP.X:=X; CurP.Y:=Y;
              if LinkContainsPoint(R,CurP) then
                if I=CurLink then C:=SelectColor else C:=LinkColor;
              B[ScreenX]:=(B[ScreenX] and $ff) or (C shl 8);
            end;
          end;
      end;

{$ifndef EDITORS}
      if ((SelR.A.X<>SelR.B.X) or (SelR.A.Y<>SelR.B.Y)) and (SelR.A.Y<=Y) and (Y<=SelR.B.Y) then
      begin
        if Y=SelR.A.Y then MinX:=SelR.A.X else MinX:=0;
        if Y=SelR.B.Y then MaxX:=SelR.B.X-1 else MaxX:=255;
        for DX:=MinX to MaxX do
        begin
          X:=DX;
          ScreenX:=X-(Delta.X);
          if (ScreenX>=0) and (ScreenX<High(B)) then
            B[ScreenX]:=(B[ScreenX] and $0fff) or ((SelectionColor and $f0) shl 8);
        end;
      end;
{$endif}

    end;
    WriteLine(0,DY,Size.X,1,B);
  end;
  DrawCursor;
end;

function THelpViewer.GetPalette: PPalette;
const P: string[length(CHelpViewer)] = CHelpViewer;
begin
  GetPalette:=@P;
end;

constructor THelpViewer.Load(var S: TStream);
begin
  inherited Load(S);
end;

procedure THelpViewer.Store(var S: TStream);
begin
  inherited Store(S);
end;

destructor THelpViewer.Done;
begin
  inherited Done;
  if assigned(WordList) then
    Dispose(WordList, Done);
end;

function THelpFrame.GetPalette: PPalette;
const P: string[length(CHelpFrame)] = CHelpFrame;
begin
  GetPalette:=@P;
end;

constructor THelpWindow.Init(var Bounds: TRect; ATitle: TTitleStr; ASourceFileID: word; AContext: THelpCtx; ANumber: Integer);
begin
  inherited Init(Bounds, ATitle, ANumber);
  InitScrollBars;
  if Assigned(HSB) then Insert(HSB);
  if Assigned(VSB) then Insert(VSB);
  InitHelpView;
  if Assigned(HelpView) then
  begin
    if (ASourceFileID<>0) or (AContext<>0) then
       ShowTopic(ASourceFileID, AContext);
    Insert(HelpView);
  end;
end;

procedure THelpWindow.InitScrollBars;
var R: TRect;
begin
  GetExtent(R); R.Grow(0,-1); R.A.X:=R.B.X-1;
  New(VSB, Init(R)); VSB^.GrowMode:=gfGrowLoX+gfGrowHiX+gfGrowHiY;
  GetExtent(R); R.Grow(-1,0); R.A.Y:=R.B.Y-1;
  New(HSB, Init(R)); HSB^.GrowMode:=gfGrowLoY+gfGrowHiX+gfGrowHiY;
end;

procedure THelpWindow.InitHelpView;
var R: TRect;
begin
  GetExtent(R); R.Grow(-1,-1);
  New(HelpView, Init(R, HSB, VSB));
  HelpView^.GrowMode:=gfGrowHiX+gfGrowHiY;
end;

procedure THelpWindow.InitFrame;
var R: TRect;
begin
  GetExtent(R);
  Frame:=New(PHelpFrame, Init(R));
end;

procedure THelpWindow.ShowIndex;
begin
  HelpView^.SwitchToIndex;
end;

procedure THelpWindow.ShowTopic(SourceFileID: word; Context: THelpCtx);
begin
  HelpView^.SwitchToTopic(SourceFileID, Context);
end;

procedure THelpWindow.HandleEvent(var Event: TEvent);
begin
  case Event.What of
    evKeyDown :
      case Event.KeyCode of
        kbEsc :
          begin
            Event.What:=evCommand; Event.Command:=cmClose;
          end;
      end;
  end;
  inherited HandleEvent(Event);
end;

procedure THelpWindow.Close;
begin
  if HideOnClose then Hide else inherited Close;
end;

function THelpWindow.GetPalette: PPalette;
begin
  GetPalette:=nil;
end;

END.
{
  $Log$
  Revision 1.17  2000-06-16 08:50:45  pierre
   + new bunch of Gabor's changes

  Revision 1.16  2000/05/30 07:18:33  pierre
   + colors for HTML help by Gabor

  Revision 1.15  2000/05/29 10:45:00  pierre
   + New bunch of Gabor's changes: see fixes.txt

  Revision 1.14  2000/04/25 08:42:35  pierre
   * New Gabor changes : see fixes.txt

  Revision 1.13  2000/04/18 11:42:39  pierre
   lot of Gabor changes : see fixes.txt

  Revision 1.12  2000/03/21 23:21:38  pierre
   adapted to wcedit addition

  Revision 1.11  2000/02/07 08:29:13  michael
  [*] the fake (!) TOKENS.PAS still contained the typo bug
       FSplit(,n,d,e) (correctly FSplit(,d,n,e))
  [*] CodeComplete had a very ugly bug - coordinates were document-relative
      (instead of being screen-relative)
  [*] TResourceStream didn't count the size of the resource names when
      determining the file size and this could lead to the last resources not
      loaded correctly


  [+] Ctrl-Enter in editor now tries to open the file at cursor
  [+] CodeComplete option added to Options|Environment|Editor
  [+] user interface for managing CodeComplete implemented
  [+] user interface for CodeTemplates implemented
  [+] CodeComplete wordlist and CodeTemplates stored in desktop file
  [+] help topic size no longer limited to 64KB when compiled with FPC

  Revision 1.10  1999/08/16 18:25:31  peter
    * Adjusting the selection when the editor didn't contain any line.
    * Reserved word recognition redesigned, but this didn't affect the overall
      syntax highlight speed remarkably (at least not on my Amd-K6/350).
      The syntax scanner loop is a bit slow but the main problem is the
      recognition of special symbols. Switching off symbol processing boosts
      the performance up to ca. 200%...
    * The editor didn't allow copying (for ex to clipboard) of a single character
    * 'File|Save as' caused permanently run-time error 3. Not any more now...
    * Compiler Messages window (actually the whole desktop) did not act on any
      keypress when compilation failed and thus the window remained visible
    + Message windows are now closed upon pressing Esc
    + At 'Run' the IDE checks whether any sources are modified, and recompiles
      only when neccessary
    + BlockRead and BlockWrite (Ctrl+K+R/W) implemented in TCodeEditor
    + LineSelect (Ctrl+K+L) implemented
    * The IDE had problems closing help windows before saving the desktop

  Revision 1.9  1999/06/28 19:32:35  peter
    * fixes from gabor

  Revision 1.8  1999/04/07 21:56:02  peter
    + object support for browser
    * html help fixes
    * more desktop saving things
    * NODEBUG directive to exclude debugger

  Revision 1.7  1999/03/08 14:58:20  peter
    + prompt with dialogs for tools

  Revision 1.6  1999/03/01 15:42:13  peter
    + Added dummy entries for functions not yet implemented
    * MenuBar didn't update itself automatically on command-set changes
    * Fixed Debugging/Profiling options dialog
    * TCodeEditor converts spaces to tabs at save only if efUseTabChars is set
    * efBackSpaceUnindents works correctly
    + 'Messages' window implemented
    + Added '$CAP MSG()' and '$CAP EDIT' to available tool-macros
    + Added TP message-filter support (for ex. you can call GREP thru
      GREP2MSG and view the result in the messages window - just like in TP)
    * A 'var' was missing from the param-list of THelpFacility.TopicSearch,
      so topic search didn't work...
    * In FPHELP.PAS there were still context-variables defined as word instead
      of THelpCtx
    * StdStatusKeys() was missing from the statusdef for help windows
    + Topic-title for index-table can be specified when adding a HTML-files

  Revision 1.5  1999/02/18 13:44:38  peter
    * search fixed
    + backward search
    * help fixes
    * browser updates

  Revision 1.4  1999/02/08 10:37:47  peter
    + html helpviewer

  Revision 1.3  1999/01/21 11:54:32  peter
    + tools menu
    + speedsearch in symbolbrowser
    * working run command

  Revision 1.2  1998/12/28 15:47:57  peter
    + Added user screen support, display & window
    + Implemented Editor,Mouse Options dialog
    + Added location of .INI and .CFG file
    + Option (INI) file managment implemented (see bottom of Options Menu)
    + Switches updated
    + Run program

  Revision 1.31 1998/12/27 12:07:30  gabor
    * changed THelpViewer.Init to reflect changes in WEDITOR
  Revision 1.3  1998/12/22 10:39:56  peter
    + options are now written/read
    + find and replace routines

}
