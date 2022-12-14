{
    This file is part of the Free Pascal run time library.
    Copyright (c) 1999-2000 by the Free Pascal development team

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{$mode objfpc}
{$modeswitch advancedrecords}

type
  PVideoMode = ^TVideoMode;
  TVideoMode = record
    Col,Row : Word;
    Color   : Boolean;
  end;
  TVideoModeSelector = function (const VideoMode: TVideoMode; Params: Longint): Boolean;

  TVideoCell = Word;
  PVideoCell = ^TVideoCell;

  TVideoBuf = array[0..{$ifdef CPU16}16382{$else}32759{$endif}] of TVideoCell;
  PVideoBuf = ^TVideoBuf;

  TEnhancedVideoAttribute = (
    { Bold or increased intensity, VT100, xterm }
    evaBold,
    { Faint, decreased intensity or second color, ECMA-48 2nd, xterm }
    evaFaint,
    { Italicized, ECMA-48 2nd, xterm }
    evaItalicized,
    { Singly underlined, VT100, xterm }
    evaUnderlined,
    { Slowly blinking (less than 150 per minute), EMCA 48 2nd, VT100, xterm }
    evaBlinkSlow,
    { Rapidly blinking (150 per minute or more), ECMA-48 2nd }
    evaBlinkFast,
    { Inverse (negative image), VT100, xterm }
    evaInverse,
    { Concealed characters, ECMA-48 2nd, VT300, xterm }
    evaInvisible,
    { Crossed-out (characters still legible but marked as to be deleted), ECMA-48 3rd, xterm }
    evaCrossedOut,
    { Doubly underlined, ECMA-48 3d }
    evaDoublyUnderlined
  );
{$push}
{$packset 2}
  TEnhancedVideoAttributes = set of TEnhancedVideoAttribute;
{$pop}

  TEnhancedVideoCell = record
  private
    class operator Initialize(var evc: TEnhancedVideoCell);
    class operator Finalize(var evc: TEnhancedVideoCell);
    class operator AddRef(var evc: TEnhancedVideoCell);
    class operator Copy(constref aSrc: TEnhancedVideoCell; var aDst: TEnhancedVideoCell);
    function GetExtendedGraphemeCluster: UnicodeString;
    procedure SetExtendedGraphemeCluster(const AExtendedGraphemeCluster: UnicodeString);
    function GetAttribute: Byte;
    procedure SetAttribute(Attr: Byte);
    function GetEnhancedVideoAttributes: TEnhancedVideoAttributes;
    procedure SetEnhancedVideoAttributes(AEnhancedVideoAttributes: TEnhancedVideoAttributes);
    function GetForegroundColor: Byte;
    procedure SetForegroundColor(AForegroundColor: Byte);
    function GetBackgroundColor: Byte;
    procedure SetBackgroundColor(ABackgroundColor: Byte);
  public
    property ExtendedGraphemeCluster: UnicodeString read GetExtendedGraphemeCluster write SetExtendedGraphemeCluster;
    property Attribute: Byte read GetAttribute write SetAttribute;
    property EnhancedVideoAttributes: TEnhancedVideoAttributes read GetEnhancedVideoAttributes write SetEnhancedVideoAttributes;
    property ForegroundColor: Byte read GetForegroundColor write SetForegroundColor;
    property BackgroundColor: Byte read GetBackgroundColor write SetBackgroundColor;

  private
    FInternalAttributes: Word;
    FForegroundColor : Byte;
    FBackgroundColor : Byte;
    case integer of
      0: (EGC_SingleChar: WideChar);
      1: (EGC_WideStr: Pointer);
  end;
  PEnhancedVideoCell = ^TEnhancedVideoCell;

  TEnhancedVideoBuf = array of TEnhancedVideoCell;

  TVideoDriver = Record
    InitDriver               : Procedure;
    InitEnhancedDriver       : Procedure;
    DoneDriver               : Procedure;
    UpdateScreen             : Procedure(Force : Boolean);
    UpdateScreenArea         : Procedure(const X1, Y1, X2, Y2: Word; Force : Boolean);
    ClearScreen              : Procedure;
    SetVideoMode             : Function (Const Mode : TVideoMode) : Boolean;
    GetVideoModeCount        : Function : Word;
    GetVideoModeData         : Function(Index : Word; Var Data : TVideoMode) : Boolean;
    SetCursorPos             : procedure (NewCursorX, NewCursorY: Word);
    GetCursorType            : function : Word;
    SetCursorType            : procedure (NewType: Word);
    GetCapabilities          : Function : Word;
    GetActiveCodePage        : function : TSystemCodePage;
    ActivateCodePage         : procedure(CodePage: TSystemCodePage);
    GetSupportedCodePageCount: function : Integer;
    GetSupportedCodePage     : function(Index: Integer): TSystemCodePage;
  end;

const
  { Foreground and background color constants }
  Black         = 0;
  Blue          = 1;
  Green         = 2;
  Cyan          = 3;
  Red           = 4;
  Magenta       = 5;
  Brown         = 6;
  LightGray     = 7;

  { Foreground color constants }
  DarkGray      = 8;
  LightBlue     = 9;
  LightGreen    = 10;
  LightCyan     = 11;
  LightRed      = 12;
  LightMagenta  = 13;
  Yellow        = 14;
  White         = 15;

  { Add-in for blinking }
  Blink         = 128;

  { Capabilities bitmask }
  cpUnderLine     = $0001;
  cpBlink         = $0002;
  cpColor         = $0004;
  cpChangeFont    = $0008;
  cpChangeMode    = $0010;
  cpChangeCursor  = $0020;

  { Possible cursor types }
  crHidden        = 0;
  crUnderLine     = 1;
  crBlock         = 2;
  crHalfBlock     = 3;

  { Possible error codes }
  vioOK              = 0;
  errVioBase         = 1000;
  errVioInit         = errVioBase + 1; { Initialization error, shouldn't occur on DOS, but may
                         on Linux }
  errVioNotSupported = errVioBase + 2; { call to an unsupported function }
  errVioNoSuchMode   = errVioBase + 3; { No such video mode }

const
  ScreenWidth  : Word = 0;
  ScreenHeight : Word = 0;

var
  ScreenColor  : Boolean;
  CursorX,
  CursorY      : Word;
  VideoBuf,
  OldVideoBuf  : PVideoBuf;
  VideoBufSize : Longint;
  CursorLines  : Byte;
  EnhancedVideoBuf,
  OldEnhancedVideoBuf: TEnhancedVideoBuf;

const {The following constants were variables in the past.
       - Lowascii was set to true if ASCII characters < 32 were available
       - NoExtendedFrame was set to true if the double with line drawing
         characters were set to true.

      These variables did exist because of VT100 limitations on Unix. However,
      only part of the character set problem was solved this way. Nowadays, the
      video unit converts characters to the output character set (which might be
      VT100) automatically, so the user does not need to worry about it anymore.}
      LowAscii = true;
      NoExtendedFrame = false;

      FVMaxWidth = 240;

operator = (const a,b : TEnhancedVideoCell) res: Boolean;

Procedure LockScreenUpdate;
{ Increments the screen update lock count with one.}
Procedure UnlockScreenUpdate;
{ Decrements the screen update lock count with one.}
Function GetLockScreenCount : integer;
{ Gets the current lock level }
Function SetVideoDriver (Const Driver : TVideoDriver) : Boolean;
{ Sets the videodriver to be used }
Procedure GetVideoDriver (Var Driver : TVideoDriver);
{ Retrieves the current videodriver }

procedure InitVideo;
{ Initializes the video subsystem }
procedure DoneVideo;
{ Deinitializes the video subsystem }
procedure InitEnhancedVideo;
{ Initializes the enhanced (Unicode) video subsystem }
procedure DoneEnhancedVideo;
{ Deinitializes the enhanced (Unicode) video subsystem }
function GetCapabilities: Word;
{ Return the capabilities of the current environment }
procedure ClearScreen;
{ Clears the screen }
procedure UpdateScreen(Force: Boolean);
{ Force specifies whether the whole screen has to be redrawn, or (if target
  platform supports it) only the changed parts }
procedure UpdateScreenArea(const X1, Y1, X2, Y2: Word; Force: Boolean);
{ Updates the screen in the area marked by coordinates X1, Y1 (top left) and
  X2, Y2 (bottom right), coordinates inclusive. Force specifies whether the
  whole area has to be redrawn, or (if target platform supports it) its changed
  parts only. If the target doesn't implement it, UpdateScreen() will be called
  instead. }
procedure SetCursorPos(NewCursorX, NewCursorY: Word);
{ Position the cursor to the given position }
function GetCursorType: Word;
{ Return the cursor type: Hidden, UnderLine or Block }
procedure SetCursorType(NewType: Word);
{ Set the cursor to the given type }
function ExtendedGraphemeClusterDisplayWidth(const EGC: UnicodeString): Integer;
{ Returns the number of display columns needed for the given extended grapheme cluster }
function StringDisplayWidth(const S: UnicodeString): Integer;
{ Returns the number of display columns needed for the given string }
function GetActiveCodePage: TSystemCodePage;
{ Returns the current active legacy code page }
procedure ActivateCodePage(CodePage: TSystemCodePage);
{ Activates a specified legacy code page (if supported) }
function GetSupportedCodePageCount: Integer;
{ Get the number of code pages supported by this driver }
function GetSupportedCodePage(Index: Integer): TSystemCodePage;
{ Get the supported code page with index Index. Index is zero based. }

procedure GetVideoMode(var Mode: TVideoMode);
{ Return dimensions of the current video mode }
Function SetVideoMode(Const Mode: TVideoMode) : Boolean;
{ Set video-mode to have Mode dimensions, may return errVioNoSuchMode }
Function GetVideoModeCount : Word;
{ Get the number of video modes supported by this driver }
Function GetVideoModeData(Index : Word; Var Data: TVideoMode) : Boolean;
{ Get the data for Video mode Index. Index is zero based. }

type
  TErrorHandlerReturnValue = (errRetry, errAbort, errContinue);
  { errRetry = retry the operation,
    errAbort = abort, return error code,
    errContinue = abort, without returning errorcode }

  TErrorHandler = function (Code: Longint; Info: Pointer): TErrorHandlerReturnValue;
    { ErrorHandler is the standard procedural interface for all error functions.
      Info may contain any data type specific to the error code passed to the
      function. }

function DefaultErrorHandler(AErrorCode: Longint; AErrorInfo: Pointer): TErrorHandlerReturnValue;
{ Default error handler, simply sets error code, and returns errContinue }

const
  errOk              = 0;
  ErrorCode: Longint = ErrOK;
  ErrorInfo: Pointer = nil;
  ErrorHandler: TErrorHandler = @DefaultErrorHandler;

