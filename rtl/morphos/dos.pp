{
    $Id$
    This file is part of the Free Pascal run time library.
    Copyright (c) 2004 by Karoly Balogh for Genesi S.a.r.l.

    Heavily based on the Commodore Amiga/m68k RTL by Nils Sjoholm and
    Carl Eric Codere

    MorphOS port was done on a free Pegasos II/G4 machine 
    provided by Genesi S.a.r.l. <www.genesi.lu>

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{$INLINE ON}

unit Dos;

{--------------------------------------------------------------------}
{ LEFT TO DO:                                                        }
{--------------------------------------------------------------------}
{ o DiskFree / Disksize don't work as expected                       }
{ o Implement EnvCount,EnvStr                                        }
{ o FindFirst should only work with correct attributes               }
{--------------------------------------------------------------------}


interface

type
  SearchRec = Packed Record
    { watch out this is correctly aligned for all processors }
    { don't modify.                                          }
    { Replacement for Fill }
{0} AnchorPtr : Pointer;    { Pointer to the Anchorpath structure }
{4} Fill: Array[1..15] of Byte; {future use}
    {End of replacement for fill}
    Attr : BYTE;        {attribute of found file}
    Time : LongInt;     {last modify date of found file}
    Size : LongInt;     {file size of found file}
    Name : String[255]; {name of found file}
  End;

{$I dosh.inc}

implementation

{$DEFINE HAS_GETMSCOUNT}
{$DEFINE HAS_GETCBREAK}
{$DEFINE HAS_SETCBREAK}

{$DEFINE FPC_FEXPAND_VOLUMES} (* Full paths begin with drive specification *)
{$DEFINE FPC_FEXPAND_DRIVESEP_IS_ROOT}
{$DEFINE FPC_FEXPAND_NO_DEFAULT_PATHS}
{$I dos.inc}


{ * include MorphOS specific functions & definitions * }

{$include execd.inc}
{$include execf.inc}
{$include timerd.inc}
{$include doslibd.inc}
{$include doslibf.inc}
{$include utilf.inc}

const
  DaysPerMonth :  Array[1..12] of ShortInt =
         (031,028,031,030,031,030,031,031,030,031,030,031);
  DaysPerYear  :  Array[1..12] of Integer  =
         (031,059,090,120,151,181,212,243,273,304,334,365);
  DaysPerLeapYear :    Array[1..12] of Integer  =
         (031,060,091,121,152,182,213,244,274,305,335,366);
  SecsPerYear      : LongInt  = 31536000;
  SecsPerLeapYear  : LongInt  = 31622400;
  SecsPerDay       : LongInt  = 86400;
  SecsPerHour      : Integer  = 3600;
  SecsPerMinute    : ShortInt = 60;
  TICKSPERSECOND    = 50;


{******************************************************************************
                           --- Internal routines ---
******************************************************************************}

{ * PathConv is implemented in the system unit! * }
function PathConv(path: string): string; external name 'PATHCONV';

function dosLock(const name: String;
                 accessmode: Longint) : LongInt;
var
 buffer: array[0..255] of Char;
begin
  move(name[1],buffer,length(name));
  buffer[length(name)]:=#0;
  dosLock:=Lock(buffer,accessmode);
end;

function BADDR(bval: LongInt): Pointer; Inline;
begin
  BADDR:=Pointer(bval Shl 2);
end;

function BSTR2STRING(s : LongInt): PChar; Inline;
begin
  BSTR2STRING:=Pointer(Longint(BADDR(s))+1);
end;

function IsLeapYear(Source : Word) : Boolean;
begin
  if (source Mod 400 = 0) or ((source Mod 4 = 0) and (source Mod 100 <> 0)) then
    IsLeapYear:=True
  else
    IsLeapYear:=False;
end;

Procedure Amiga2DateStamp(Date : LongInt; Var TotalDays,Minutes,Ticks: longint);
{ Converts a value in seconds past 1978 to a value in AMIGA DateStamp format }
{ Taken from SWAG and modified to work with the Amiga format - CEC           }
Var
  LocalDate : LongInt; Done : Boolean; TotDays : Integer;
  Y: Word;
  H: Word;
  Min: Word;
  S : Word;
Begin
  Y   := 1978; H := 0; Min := 0; S := 0;
  TotalDays := 0;
  Minutes := 0;
  Ticks := 0;
  LocalDate := Date;
  Done := False;
  While Not Done Do
  Begin
    If LocalDate >= SecsPerYear Then
    Begin
      Inc(Y,1);
      Dec(LocalDate,SecsPerYear);
      Inc(TotalDays,DaysPerYear[12]);
    End
    Else
      Done := True;
    If (IsLeapYear(Y+1)) And (LocalDate >= SecsPerLeapYear) And
       (Not Done) Then
    Begin
      Inc(Y,1);
      Dec(LocalDate,SecsPerLeapYear);
      Inc(TotalDays,DaysPerLeapYear[12]);
    End;
  End; { END WHILE }
  Done := False;
  TotDays := LocalDate Div SecsPerDay;
  { Total number of days }
  TotalDays := TotalDays + TotDays;
    Dec(LocalDate,TotDays*SecsPerDay);
  { Absolute hours since start of day }
  H := LocalDate Div SecsPerHour;
  { Convert to minutes }
  Minutes := H*60;
    Dec(LocalDate,(H * SecsPerHour));
  { Find the remaining minutes to add }
  Min := LocalDate Div SecsPerMinute;
    Dec(LocalDate,(Min * SecsPerMinute));
  Minutes:=Minutes+Min;
  { Find the number of seconds and convert to ticks }
  S := LocalDate;
  Ticks:=TICKSPERSECOND*S;
End;


function dosSetProtection(const name: string; mask:longint): Boolean;
var
  buffer : array[0..255] of Char;
begin
  move(name[1],buffer,length(name));
  buffer[length(name)]:=#0;
  dosSetProtection:=SetProtection(buffer,mask);
end;

function dosSetFileDate(name: string; p : PDateStamp): Boolean;
var buffer : array[0..255] of Char;
begin
  move(name[1],buffer,length(name));
  buffer[length(name)]:=#0;
  dosSetFileDate:=SetFileDate(buffer,p);
end;


{******************************************************************************
                        --- Info / Date / Time ---
******************************************************************************}

function DosVersion: Word;
var p: PLibrary;
begin
  p:=PLibrary(MOS_DOSBase);
  DosVersion:= p^.lib_Version or (p^.lib_Revision shl 8);
end;

{ Here are a lot of stuff just for setdate and settime }

var
    TimerBase   : Pointer;


procedure NewList (list: pList);
begin
    with list^ do
    begin
        lh_Head     := pNode(@lh_Tail);
        lh_Tail     := NIL;
        lh_TailPred := pNode(@lh_Head)
    end
end;

function CreateExtIO (port: pMsgPort; size: Longint): pIORequest;
var
   IOReq: pIORequest;
begin
    IOReq := NIL;
    if port <> NIL then
    begin
        IOReq := execAllocMem(size, MEMF_CLEAR or MEMF_PUBLIC);
        if IOReq <> NIL then
        begin
            IOReq^.io_Message.mn_Node.ln_Type   := 7;
            IOReq^.io_Message.mn_Length    := size;
            IOReq^.io_Message.mn_ReplyPort := port;
        end;
    end;
    CreateExtIO := IOReq;
end;

procedure DeleteExtIO (ioReq: pIORequest);
begin
    if ioReq <> NIL then
    begin
        ioReq^.io_Message.mn_Node.ln_Type := $FF;
        ioReq^.io_Message.mn_ReplyPort    := pMsgPort(-1);
        ioReq^.io_Device                  := pDevice(-1);
        execFreeMem(ioReq, ioReq^.io_Message.mn_Length);
    end
end;

function Createport(name : PChar; pri : longint): pMsgPort;
var
   sigbit : ShortInt;
   port    : pMsgPort;
begin
   sigbit := AllocSignal(-1);
   if sigbit = -1 then CreatePort := nil;
   port := execAllocMem(sizeof(tMsgPort),MEMF_CLEAR or MEMF_PUBLIC);
   if port = nil then begin
      FreeSignal(sigbit);
      CreatePort := nil;
   end;
   with port^ do begin
       if assigned(name) then
       mp_Node.ln_Name := name
       else mp_Node.ln_Name := nil;
       mp_Node.ln_Pri := pri;
       mp_Node.ln_Type := 4;
       mp_Flags := 0;
       mp_SigBit := sigbit;
       mp_SigTask := FindTask(nil);
   end;
   if assigned(name) then AddPort(port)
   else NewList(addr(port^.mp_MsgList));
   CreatePort := port;
end;

procedure DeletePort (port: pMsgPort);
begin
    if port <> NIL then
    begin
        if port^.mp_Node.ln_Name <> NIL then
            RemPort(port);

        port^.mp_Node.ln_Type     := $FF;
        port^.mp_MsgList.lh_Head  := pNode(-1);
        FreeSignal(port^.mp_SigBit);
        execFreeMem(port, sizeof(tMsgPort));
    end;
end;


Function Create_Timer(theUnit : longint) : pTimeRequest;
var
    Error : longint;
    TimerPort : pMsgPort;
    TimeReq : pTimeRequest;
begin
    TimerPort := CreatePort(Nil, 0);
    if TimerPort = Nil then 
  Create_Timer := Nil;
    TimeReq := pTimeRequest(CreateExtIO(TimerPort,sizeof(tTimeRequest)));
    if TimeReq = Nil then begin
  DeletePort(TimerPort);
  Create_Timer := Nil;
    end; 
    Error := OpenDevice(TIMERNAME, theUnit, pIORequest(TimeReq), 0);
    if Error <> 0 then begin
  DeleteExtIO(pIORequest(TimeReq));
  DeletePort(TimerPort);
  Create_Timer := Nil;
    end;
    TimerBase := pointer(TimeReq^.tr_Node.io_Device); 
    Create_Timer := pTimeRequest(TimeReq);
end;

Procedure Delete_Timer(WhichTimer : pTimeRequest);
var
    WhichPort : pMsgPort;
begin
    
    WhichPort := WhichTimer^.tr_Node.io_Message.mn_ReplyPort;
    if assigned(WhichTimer) then begin
        CloseDevice(pIORequest(WhichTimer));
        DeleteExtIO(pIORequest(WhichTimer));
    end;
    if assigned(WhichPort) then
        DeletePort(WhichPort);
end;

function set_new_time(secs, micro : longint): longint;
var
    tr : ptimerequest;
begin
    tr := create_timer(UNIT_MICROHZ);

    { non zero return says error }
    if tr = nil then set_new_time := -1;
  
    tr^.tr_time.tv_secs := secs;
    tr^.tr_time.tv_micro := micro;
    tr^.tr_node.io_Command := TR_SETSYSTIME;
    DoIO(pIORequest(tr));

    delete_timer(tr);
    set_new_time := 0;
end;

function get_sys_time(tv : ptimeval): longint;
var
    tr : ptimerequest;
begin
    tr := create_timer( UNIT_MICROHZ );

    { non zero return says error }
    if tr = nil then get_sys_time := -1;

    tr^.tr_node.io_Command := TR_GETSYSTIME;
    DoIO(pIORequest(tr));

   { structure assignment }
   tv^ := tr^.tr_time;

   delete_timer(tr);
   get_sys_time := 0;
end;

Procedure GetDate(Var Year, Month, MDay, WDay: Word);
Var
  cd    : pClockData;
  oldtime : ttimeval;
begin
  New(cd);
  get_sys_time(@oldtime);
  Amiga2Date(oldtime.tv_secs,cd);
  Year  := cd^.year;
  Month := cd^.month;
  MDay  := cd^.mday;
  WDay  := cd^.wday;
  Dispose(cd);
end;

Procedure SetDate(Year, Month, Day: Word);
var
  cd : pClockData;
  oldtime : ttimeval;
Begin
  new(cd);
  get_sys_time(@oldtime);
  Amiga2Date(oldtime.tv_secs,cd);
  cd^.year := Year;
  cd^.month := Month;
  cd^.mday := Day;
  set_new_time(Date2Amiga(cd),0);
  dispose(cd);
  End;

Procedure GetTime(Var Hour, Minute, Second, Sec100: Word);
Var
  cd      : pClockData;
  oldtime : ttimeval;
begin
  New(cd);
  get_sys_time(@oldtime);
  Amiga2Date(oldtime.tv_secs,cd);
  Hour   := cd^.hour;
  Minute := cd^.min;
  Second := cd^.sec;
  Sec100 := oldtime.tv_micro div 10000;
  Dispose(cd);
END;


Procedure SetTime(Hour, Minute, Second, Sec100: Word);
var
  cd : pClockData;
  oldtime : ttimeval;
Begin
  new(cd);
  get_sys_time(@oldtime);
  Amiga2Date(oldtime.tv_secs,cd);
  cd^.hour := Hour;
  cd^.min := Minute;
  cd^.sec := Second;
  set_new_time(Date2Amiga(cd), Sec100 * 10000);
  dispose(cd);
  End;


function GetMsCount: int64;
var
  TV: TTimeVal;
begin
  Get_Sys_Time (@TV);
  GetMsCount := TV.TV_Secs * 1000 + TV.TV_Micro div 1000;
end;

{******************************************************************************
                               --- Exec ---
******************************************************************************}


Procedure Exec (Const Path: PathStr; Const ComLine: ComStr);
  var
   p : string;
   buf: array[0..255] of char;
   result : longint;
   MyLock : longint;
   i : Integer;
  Begin
   DosError := 0;
   LastdosExitCode := 0;
   p:=Path+' '+ComLine;
   { allow backslash as slash }
   for i:=1 to length(p) do
       if p[i]='\' then p[i]:='/';
   Move(p[1],buf,length(p));
   buf[Length(p)]:=#0;
   { Here we must first check if the command we wish to execute }
   { actually exists, because this is NOT handled by the        }
   { _SystemTagList call (program will abort!!)                 }

   { Try to open with shared lock                               }
   MyLock:=dosLock(Path,SHARED_LOCK);
   if MyLock <> 0 then
     Begin
        { File exists - therefore unlock it }
        Unlock(MyLock);
        result:=SystemTagList(buf,nil);
        { on return of -1 the shell could not be executed }
        { probably because there was not enough memory    }
        if result = -1 then
          DosError:=8
        else
          LastDosExitCode:=word(result);
     end
   else
    DosError:=3;
  End;


  Procedure GetCBreak(Var BreakValue: Boolean);
  Begin
   breakvalue := system.BreakOn;
  End;


 Procedure SetCBreak(BreakValue: Boolean);
  Begin
   system.Breakon := BreakValue;
  End;


{******************************************************************************
                               --- Disk ---
******************************************************************************}

{ How to solve the problem with this:       }
{  We could walk through the device list    }
{  at startup to determine possible devices }

const

  not_to_use_devs : array[0..12] of string =(
                   'DF0:',
                   'DF1:',
                   'DF2:',
                   'DF3:',
                   'PED:',
                   'PRJ:',
                   'PIPE:',
                   'RAM:',
                   'CON:',
                   'RAW:',
                   'SER:',
                   'PAR:',
                   'PRT:');

var
   deviceids : array[1..20] of byte;
   devicenames : array[1..20] of string[20];
   numberofdevices : Byte;

Function DiskFree(Drive: Byte): int64;
Var
  MyLock      : LongInt;
  Inf         : pInfoData;
  Free        : Longint;
  myproc      : pProcess;
  OldWinPtr   : Pointer;
Begin
  Free := -1;
  { Here we stop systemrequesters to appear }
  myproc := pProcess(FindTask(nil));
  OldWinPtr := myproc^.pr_WindowPtr;
  myproc^.pr_WindowPtr := Pointer(-1);
  { End of systemrequesterstop }
  New(Inf);
  MyLock := dosLock(devicenames[deviceids[Drive]],SHARED_LOCK);
  If MyLock <> 0 then begin
     if Info(MyLock,Inf) then begin
        Free := (Inf^.id_NumBlocks * Inf^.id_BytesPerBlock) -
                (Inf^.id_NumBlocksUsed * Inf^.id_BytesPerBlock);
     end;
     Unlock(MyLock);
  end;
  Dispose(Inf);
  { Restore systemrequesters }
  myproc^.pr_WindowPtr := OldWinPtr;
  diskfree := Free;
end;



Function DiskSize(Drive: Byte): int64;
Var
  MyLock      : LongInt;
  Inf         : pInfoData;
  Size        : Longint;
  myproc      : pProcess;
  OldWinPtr   : Pointer;
Begin
  Size := -1;
  { Here we stop systemrequesters to appear }
  myproc := pProcess(FindTask(nil));
  OldWinPtr := myproc^.pr_WindowPtr;
  myproc^.pr_WindowPtr := Pointer(-1);
  { End of systemrequesterstop }
  New(Inf);
  MyLock := dosLock(devicenames[deviceids[Drive]],SHARED_LOCK);
  If MyLock <> 0 then begin
     if Info(MyLock,Inf) then begin
        Size := (Inf^.id_NumBlocks * Inf^.id_BytesPerBlock);
     end;
     Unlock(MyLock);
  end;
  Dispose(Inf);
  { Restore systemrequesters }
  myproc^.pr_WindowPtr := OldWinPtr;
  disksize := Size;
end;


Procedure FindFirst(const Path: PathStr; Attr: Word; Var f: SearchRec);
var
 tmpStr: Array[0..255] of char;
 Anchor: pAnchorPath;
 Result: Longint;
 index : Integer;
 s     : string;
 j     : integer;
Begin
 tmpStr:=PathConv(path)+#0;
 DosError:=0;

 New(Anchor);
 FillChar(Anchor^,sizeof(TAnchorPath),#0);

 Result:=MatchFirst(@tmpStr,Anchor);
 f.AnchorPtr:=Anchor;
 if Result = ERROR_NO_MORE_ENTRIES then
   DosError:=18
 else
 if Result <> 0 then
   DosError:=3;
 { If there is an error, deallocate }
 { the anchorpath structure         }
 if DosError <> 0 then
   Begin
     MatchEnd(Anchor);
     if assigned(Anchor) then
       Dispose(Anchor);
   end
 else
 {-------------------------------------------------------------------}
 { Here we fill up the SearchRec attribute, but we also do check     }
 { something else, if the it does not match the mask we are looking  }
 { for we should go to the next file or directory.                   }
 {-------------------------------------------------------------------}
   begin
         with Anchor^.ap_Info do
          Begin
             f.Time := fib_Date.ds_Days * (24 * 60 * 60) +
             fib_Date.ds_Minute * 60 +
             fib_Date.ds_Tick div 50;
           {*------------------------------------*}
           {* Determine if is a file or a folder *}
           {*------------------------------------*}
           if fib_DirEntryType > 0 then
               f.attr:=f.attr OR DIRECTORY;

           {*------------------------------------*}
           {* Determine if Read only             *}
           {*  Readonly if R flag on and W flag  *}
           {*   off.                             *}
           {* Should we check also that EXEC     *}
           {* is zero? for read only?            *}
           {*------------------------------------*}
           if   ((fib_Protection and FIBF_READ) <> 0)
            AND ((fib_Protection and FIBF_WRITE) = 0)
           then
              f.attr:=f.attr or READONLY;
           f.Name := strpas(fib_FileName);
           f.Size := fib_Size;
         end; { end with }
   end;
End;


Procedure FindNext(Var f: SearchRec);
var
 Result: longint;
 Anchor : pAnchorPath;
Begin
 DosError:=0;
 Result:=MatchNext(f.AnchorPtr);
 if Result = ERROR_NO_MORE_ENTRIES then
   DosError:=18
 else
 if Result <> 0 then
   DosError:=3;
 { If there is an error, deallocate }
 { the anchorpath structure         }
 if DosError <> 0 then
   Begin
     MatchEnd(f.AnchorPtr);
     if assigned(f.AnchorPtr) then
       {Dispose}FreeMem(f.AnchorPtr);
   end
 else
 { Fill up the Searchrec information     }
 { and also check if the files are with  }
 { the correct attributes                }
   Begin
         Anchor:=pAnchorPath(f.AnchorPtr);
         with Anchor^.ap_Info do
          Begin
             f.Time := fib_Date.ds_Days * (24 * 60 * 60) +
             fib_Date.ds_Minute * 60 +
             fib_Date.ds_Tick div 50;
           {*------------------------------------*}
           {* Determine if is a file or a folder *}
           {*------------------------------------*}
           if fib_DirEntryType > 0 then
               f.attr:=f.attr OR DIRECTORY;

           {*------------------------------------*}
           {* Determine if Read only             *}
           {*  Readonly if R flag on and W flag  *}
           {*   off.                             *}
           {* Should we check also that EXEC     *}
           {* is zero? for read only?            *}
           {*------------------------------------*}
           if   ((fib_Protection and FIBF_READ) <> 0)
            AND ((fib_Protection and FIBF_WRITE) = 0)
           then
              f.attr:=f.attr or READONLY;
           f.Name := strpas(fib_FileName);
           f.Size := fib_Size;
         end; { end with }
   end;
End;

    Procedure FindClose(Var f: SearchRec);
      begin
      end;

{******************************************************************************
                               --- File ---
******************************************************************************}

function FSearch(path: PathStr; dirlist: String) : PathStr;
var
  counter: LongInt;
  p1     : LongInt;
  tmpSR  : SearchRec;
  newdir : PathStr;
begin
  { No wildcards allowed in these things }
  if (pos('?',path)<>0) or (pos('*',path)<>0) or (path='') then
    FSearch:=''
  else begin
    { allow slash as backslash }
    for counter:=1 to length(dirlist) do
      if dirlist[counter]='\' then dirlist[counter]:='/';
    
    repeat
      p1:=pos(';',dirlist);
      if p1<>0 then begin
        newdir:=Copy(dirlist,1,p1-1);
        Delete(dirlist,1,p1);
      end else begin
        newdir:=dirlist;
        dirlist:='';
      end;
      if (newdir<>'') and (not (newdir[length(newdir)] in ['/',':'])) then
        newdir:=newdir+'/';
      FindFirst(newdir+path,anyfile,tmpSR);
      if doserror=0 then
        newdir:=newdir+path
      else
        newdir:='';
    until (dirlist='') or (newdir<>'');
    FSearch:=newdir;
  end;
end;


Procedure getftime (var f; var time : longint);
{
    This function returns a file's date and time as the number of
    seconds after January 1, 1978 that the file was created.
}
var
    FInfo : pFileInfoBlock;
    FTime : Longint;
    FLock : Longint;
    Str   : String;
    i     : integer;
begin
    DosError:=0;
    FTime := 0;
    Str := StrPas(filerec(f).name);
    for i:=1 to length(Str) do
     if str[i]='\' then str[i]:='/';
    FLock := dosLock(Str, SHARED_LOCK);
    IF FLock <> 0 then begin
        New(FInfo);
        if Examine(FLock, FInfo) then begin
             with FInfo^.fib_Date do
             FTime := ds_Days * (24 * 60 * 60) +
             ds_Minute * 60 +
             ds_Tick div 50;
        end else begin
             FTime := 0;
        end;
        Unlock(FLock);
        Dispose(FInfo);
    end
    else
     DosError:=6;
    time := FTime;
end;


  Procedure setftime(var f; time : longint);
   var
    DateStamp: pDateStamp;
    Str: String;
    i: Integer;
    Days, Minutes,Ticks: longint;
    FLock: longint;
  Begin
    new(DateStamp);
    Str := StrPas(filerec(f).name);
    for i:=1 to length(Str) do
     if str[i]='\' then str[i]:='/';
    { Check first of all, if file exists }
    FLock := dosLock(Str, SHARED_LOCK);
    IF FLock <> 0 then
      begin
        Unlock(FLock);
        Amiga2DateStamp(time,Days,Minutes,ticks);
        DateStamp^.ds_Days:=Days;
        DateStamp^.ds_Minute:=Minutes;
        DateStamp^.ds_Tick:=Ticks;
        if dosSetFileDate(Str,DateStamp) then
            DosError:=0
        else
            DosError:=6;
      end
    else
      DosError:=2;
    if assigned(DateStamp) then Dispose(DateStamp);
  End;

  Procedure getfattr(var f; var attr : word);
  var
    info : pFileInfoBlock;
    MyLock : Longint;
    flags: word;
    Str: String;
    i: integer;
  Begin
    DosError:=0;
    flags:=0;
    New(info);
    Str := StrPas(filerec(f).name);
    for i:=1 to length(Str) do
     if str[i]='\' then str[i]:='/';
    { open with shared lock to check if file exists }
    MyLock:=dosLock(Str,SHARED_LOCK);
    if MyLock <> 0 then
      Begin
        Examine(MyLock,info);
        {*------------------------------------*}
        {* Determine if is a file or a folder *}
        {*------------------------------------*}
        if info^.fib_DirEntryType > 0 then
             flags:=flags OR DIRECTORY;

        {*------------------------------------*}
        {* Determine if Read only             *}
        {*  Readonly if R flag on and W flag  *}
        {*   off.                             *}
        {* Should we check also that EXEC     *}
        {* is zero? for read only?            *}
        {*------------------------------------*}
        if   ((info^.fib_Protection and FIBF_READ) <> 0)
         AND ((info^.fib_Protection and FIBF_WRITE) = 0)
         then
          flags:=flags OR ReadOnly;
        Unlock(mylock);
      end
    else
      DosError:=3;
    attr:=flags;
    Dispose(info);
  End;


Procedure setfattr (var f;attr : word);
  var
   flags: longint;
   MyLock : longint;
   str: string;
   i: integer;
  Begin
    DosError:=0;
    flags:=FIBF_WRITE;
    { open with shared lock }
    Str := StrPas(filerec(f).name);
    for i:=1 to length(Str) do
     if str[i]='\' then str[i]:='/';

    MyLock:=dosLock(Str,SHARED_LOCK);

    { By default files are read-write }
    if attr AND ReadOnly <> 0 then
      { Clear the Fibf_write flags }
      flags:=FIBF_READ;


    if MyLock <> 0 then
     Begin
       Unlock(MyLock);
       if Not dosSetProtection(Str,flags) then
         DosError:=5;
     end
    else
      DosError:=3;
  End;



{******************************************************************************
                             --- Environment ---
******************************************************************************}

var
StrofPaths : string[255];

function getpathstring: string;
var
   f : text;
   s : string;
   found : boolean;
   temp : string[255];
begin
   found := true;
   temp := '';
   assign(f,'ram:makepathstr');
   rewrite(f);
   writeln(f,'path >ram:temp.lst');
   close(f);
   exec('c:protect','ram:makepathstr sarwed quiet');
   exec('C:execute','ram:makepathstr');
   exec('c:delete','ram:makepathstr quiet');
   assign(f,'ram:temp.lst');
   reset(f);
   { skip the first line, garbage }
   if not eof(f) then readln(f,s);
   while not eof(f) do begin
      readln(f,s);
      if found then begin
         temp := s;
         found := false;
      end else begin;
         if (length(s) + length(temp)) < 255 then
            temp := temp + ';' + s;
      end;
   end;
   close(f);
   exec('C:delete','ram:temp.lst quiet');
   getpathstring := temp;
end;


 Function EnvCount: Longint;
 { HOW TO GET THIS VALUE:                                }
 {   Each time this function is called, we look at the   }
 {   local variables in the Process structure (2.0+)     }
 {   And we also read all files in the ENV: directory    }
  Begin
   EnvCount := 0;
  End;


 Function EnvStr(Index: LongInt): String;
  Begin
    EnvStr:='';
  End;



function GetEnv(envvar : String): String;
var
   bufarr : array[0..255] of char;
   strbuffer : array[0..255] of char;
   temp : Longint;
begin
   if UpCase(envvar) = 'PATH' then begin
       if StrOfpaths = '' then StrOfPaths := GetPathString;
       GetEnv := StrofPaths;
   end else begin
      move(envvar[1],strbuffer,length(envvar));
      strbuffer[length(envvar)] := #0;
      temp := GetVar(strbuffer,bufarr,255,$100);
      if temp = -1 then
        GetEnv := ''
      else GetEnv := StrPas(bufarr);
   end;
end;


procedure AddDevice(str : String);
begin
    inc(numberofdevices);
    deviceids[numberofdevices] := numberofdevices;
    devicenames[numberofdevices] := str;
end;

function MakeDeviceName(str : pchar): string;
var
   temp : string[20];
begin
   temp := strpas(str);
   temp := temp + ':';
   MakeDeviceName := temp;
end;

function IsInDeviceList(str : string): boolean;
var
   i : byte;
   theresult : boolean;
begin
   theresult := false;
   for i := low(not_to_use_devs) to high(not_to_use_devs) do
   begin
       if str = not_to_use_devs[i] then begin
          theresult := true;
          break;
       end;
   end;
   IsInDeviceList := theresult;
end;

procedure ReadInDevices;
var
   dl : pDosList;
   temp : pchar;
   str  : string[20];
begin
   dl := LockDosList(LDF_DEVICES or LDF_READ );
   repeat
      dl := NextDosEntry(dl,LDF_DEVICES );
      if dl <> nil then begin
         temp := BSTR2STRING(dl^.dol_Name);
         str := MakeDeviceName(temp);
         if not IsInDeviceList(str) then
              AddDevice(str);
      end;
   until dl = nil;
   UnLockDosList(LDF_DEVICES or LDF_READ );
end;

Begin
 DosError:=0;
 numberofdevices := 0;
 StrOfPaths := '';
 ReadInDevices;
End.

{
  $Log$
  Revision 1.12  2004-12-06 20:01:20  karoly

    * made it compile again after changes by Tomas
    * cleaned up FindFirst mess (still more things to do, as usual)

  Revision 1.11  2004/12/05 16:44:43  hajny
    * GetMsCount added, platform independent routines moved to single include file

  Revision 1.10  2004/11/23 02:57:58  karoly
    * Fixed missing $INLINE

  Revision 1.9  2004/11/18 22:30:33  karoly
    * Some cleanup, leap year calculation fixed

  Revision 1.8  2004/10/27 01:31:40  karoly
    * GetEnv fixed

  Revision 1.7  2004/08/03 15:59:41  karoly
    * more cleanup & more includes

  Revision 1.6  2004/06/26 20:48:24  karoly
    * more cleanup + changes to use new includes

  Revision 1.5  2004/06/13 22:51:08  karoly
    * cleanup and changes to use new includes

  Revision 1.4  2004/05/16 00:24:19  karoly
    * some cleanup

  Revision 1.3  2004/05/13 00:48:52  karoly
    * fixed a typo

  Revision 1.2  2004/05/13 00:42:29  karoly
    * getpathstring displayed dos messages, fixed

  Revision 1.1  2004/05/12 20:27:29  karoly
    * first implementation of MorphOS DOS unit, based on Amiga version

}
