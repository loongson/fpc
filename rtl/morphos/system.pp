{
    $Id$
    This file is part of the Free Pascal run time library.
    Copyright (c) 2004 by Karoly Balogh for Genesi Sarl

    System unit for MorphOS.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{ These things are set in the makefile, }
{ But you can override them here.}


{ If you use an aout system, set the conditional AOUT}
{ $Define AOUT}

unit {$ifdef VER1_0}SysMorph{$else}System{$endif};

interface

{$define FPC_IS_SYSTEM}

{$I systemh.inc}

type 
  THandle = DWord;

{$I heaph.inc}

const
  LineEnding = #10;
  LFNSupport = True;
  DirectorySeparator = '/';
  DriveSeparator = ':';
  PathSeparator = ';';

const
  UnusedHandle    : LongInt = -1;
  StdInputHandle  : LongInt = 0;
  StdOutputHandle : LongInt = 0;
  StdErrorHandle  : LongInt = 0;

  FileNameCaseSensitive : Boolean = False;

  sLineBreak : string[1] = LineEnding;
  DefaultTextLineBreakStyle : TTextLineBreakStyle = tlbsLF;

var
  MOS_ExecBase : DWord; External Name '_ExecBase';  

implementation

{$I system.inc}

{ OS dependant parts  }

{ $I errno.inc}                          // error numbers
{ $I bunxtype.inc}                       // c-types, unix base types, unix
                                        //    base structures


{ $I ossysc.inc}                         // base syscalls
{ $I osmain.inc}                         // base wrappers *nix RTL (derivatives)


const 
  REG_D0 = 0;
  REG_D1 = 4;
  REG_D2 = 8;
  REG_D3 = 12;
  REG_D4 = 16;
  REG_D5 = 20;
  REG_D6 = 24;
  REG_D7 = 28;
  REG_A0 = 32;
  REG_A1 = 36;
  REG_A2 = 40;
  REG_A3 = 44;
  REG_A4 = 48;
  REG_A5 = 52;
  REG_A6 = 56;

const 
  LVOOpenLibrary = -552;


function Exec_OpenLibrary(LibName: PChar; LibVer: LongInt) : LongInt; Assembler;
asm
  stw   r3,(REG_A0)(r2)
  stw   r4,(REG_D0)(r2)

  lis   r3,(MOS_ExecBase)@ha
  ori   r3,r3,(MOS_ExecBase)@l
  stw   r3,(REG_A6)(r2)

  li    r3,LVOOpenLibrary
  mtlr  r3
  blrl

  mr    r3,r16
end;

{*****************************************************************************
                       Misc. System Dependent Functions
*****************************************************************************}

//procedure haltproc(e:longint);cdecl;external name '_haltproc';

procedure System_exit;
begin
//  haltproc(ExitCode);
End;


{*****************************************************************************
                              ParamStr/Randomize
*****************************************************************************}

{ number of args }
function paramcount : longint;
begin
  {paramcount := argc - 1;}
  paramcount:=0;
end;

{ argument number l }
function paramstr(l : longint) : string;
begin
  {if (l>=0) and (l+1<=argc) then
   paramstr:=strpas(argv[l])
  else}
   paramstr:='';
end;

{ set randseed to a new pseudo random value }
procedure randomize;
begin
  {regs.realeax:=$2c00;
  sysrealintr($21,regs);
  hl:=regs.realedx and $ffff;
  randseed:=hl*$10000+ (regs.realecx and $ffff);}
  randseed:=0;
end;


{*****************************************************************************
                              Heap Management
*****************************************************************************}

{ first address of heap }
function getheapstart:pointer;{assembler;
asm
        leal    HEAP,%eax
end ['EAX'];}
begin
   getheapstart:=NIL;
end;

{ current length of heap }
function getheapsize:longint;{assembler;
asm
        movl    HEAPSIZE,%eax
end ['EAX'];}
begin
   getheapsize:=0;
end;

{ function to allocate size bytes more for the program }
{ must return the first address of new data space or nil if fail }
function Sbrk(size : longint):pointer;{assembler;
asm
        movl    size,%eax
        pushl   %eax
        call    ___sbrk
        addl    $4,%esp
end;}
begin
  Sbrk:=nil;
end;

{$I heap.inc}

{****************************************************************************
                        Low level File Routines
               All these functions can set InOutRes on errors
 ****************************************************************************}

{ close a file from the handle value }
procedure do_close(handle : longint);
begin
  InOutRes:=1;
end;

procedure do_erase(p : pchar);
begin
  InOutRes:=1;
end;

procedure do_rename(p1,p2 : pchar);
begin
  InOutRes:=1;
end;

function do_write(h,addr,len : longint) : longint;
begin
  InOutRes:=1;
end;

function do_read(h,addr,len : longint) : longint;
begin
  InOutRes:=1;
end;

function do_filepos(handle : longint) : longint;
begin
  InOutRes:=1;
end;

procedure do_seek(handle,pos : longint);
begin
  InOutRes:=1;
end;

function do_seekend(handle:longint):longint;
begin
  InOutRes:=1;
end;

function do_filesize(handle : longint) : longint;
begin
  InOutRes:=1;
end;

{ truncate at a given position }
procedure do_truncate (handle,pos:longint);
begin
  InOutRes:=1;
end;

procedure do_open(var f;p:pchar;flags:longint);
{
  filerec and textrec have both handle and mode as the first items so
  they could use the same routine for opening/creating.
  when (flags and $10)   the file will be append
  when (flags and $100)  the file will be truncate/rewritten
  when (flags and $1000) there is no check for close (needed for textfiles)
}
begin
  InOutRes:=1;
end;

function do_isdevice(handle:longint):boolean;
begin
  do_isdevice:=false;
end;

{*****************************************************************************
                          UnTyped File Handling
*****************************************************************************}

{$i file.inc}

{*****************************************************************************
                           Typed File Handling
*****************************************************************************}

{$i typefile.inc}

{*****************************************************************************
                           Text File Handling
*****************************************************************************}

{$I text.inc}


{*****************************************************************************
                           Directory Handling
*****************************************************************************}
procedure mkdir(const s : string);[IOCheck];
begin
  InOutRes:=1;
end;

procedure rmdir(const s : string);[IOCheck];
begin
  InOutRes:=1;
end;

procedure chdir(const s : string);[IOCheck];
begin
  InOutRes:=1;
end;

procedure GetDir (DriveNr: byte; var Dir: ShortString);

begin
  InOutRes := 1;
end;





procedure SysInitStdIO;
begin
  OpenStdIO(Input,fmInput,StdInputHandle);
  OpenStdIO(Output,fmOutput,StdOutputHandle);
  OpenStdIO(StdOut,fmOutput,StdOutputHandle);
 
  { * MorphOS doesn't have a separate stderr, just like AmigaOS (???) * }
  StdErrorHandle:=StdOutputHandle;
  // OpenStdIO(StdErr,fmOutput,StdErrorHandle);
end;


{procedure SysInitExecPath;
var
  hs   : string[16];
  link : string;
  i    : longint;
begin
  str(Fpgetpid,hs);
  hs:='/proc/'+hs+'/exe'#0;
  i:=Fpreadlink(@hs[1],@link[1],high(link));
  { it must also be an absolute filename, linux 2.0 points to a memory
    location so this will skip that }
  if (i>0) and (link[1]='/') then
   begin
     link[0]:=chr(i);
     ExecPathStr:=link;
   end;
end;
}

Begin
  IsConsole := TRUE;
  IsLibrary := FALSE;
  StackLength := InitialStkLen;
  StackBottom := Sptr - StackLength;
{ Set up signals handlers }
//  InstallSignals;
{ Setup heap }
  InitHeap;
  SysInitExceptions;
{ Arguments }
//  SetupCmdLine;
//  SysInitExecPath;
{ Setup stdin, stdout and stderr }
  SysInitStdIO;
{ Reset IO Error }
  InOutRes:=0;
(* This should be changed to a real value during *)
(* thread driver initialization if appropriate.  *)
  ThreadID := 1;
{$ifdef HASVARIANT}
  initvariantmanager;
{$endif HASVARIANT}
End.

{
  $Log$
  Revision 1.2  2004-04-08 06:28:29  karoly
   * first steps to have a morphos system unit

  Revision 1.1  2004/02/13 07:19:53  karoly
   * quick hack from Linux system unit


}
