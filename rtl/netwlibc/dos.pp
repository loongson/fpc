{
    $Id$
    This file is part of the Free Pascal run time library.
    Copyright (c) 1999-2004 by the Free Pascal development team.

    Dos unit for BP7 compatible RTL (novell netware libc)

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

unit dos;
interface

uses libc;

Const
  FileNameLen = 255;

Type
  searchrec = packed record
     DirP  : POINTER;              { used for opendir }
     EntryP: POINTER;              { and readdir }
     Magic : WORD;
     fill  : array[1..11] of byte;
     attr  : byte;
     time  : longint;
     size  : longint;
     name  : string[255];
     { Internals used by netware port only: }
     _mask : string[255];
     _dir  : string[255];
   end;

  registers = packed record
    case i : integer of
     0 : (ax,f1,bx,f2,cx,f3,dx,f4,bp,f5,si,f51,di,f6,ds,f7,es,f8,flags,fs,gs : word);
     1 : (al,ah,f9,f10,bl,bh,f11,f12,cl,ch,f13,f14,dl,dh : byte);
     2 : (eax,  ebx,  ecx,  edx,  ebp,  esi,  edi : longint);
    end;

{$i dosh.inc}

implementation

uses
  strings;

{$ASMMODE ATT}

{*****************************************************************************
                        --- Info / Date / Time ---
******************************************************************************}
{$PACKRECORDS 4}


function dosversion : word;
var i : Tutsname;
begin
  if uname (i) >= 0 then
    dosversion := WORD (i.netware_major) SHL 8 + i.netware_minor
  else dosversion := $0005;
end;


procedure getdate(var year,month,mday,wday : word);
var
  t  : TTime;
  tm : Ttm;
begin
  time(t); localtime_r(t,tm);
  with tm do
  begin
    year := tm_year+1900;
    month := tm_mon+1;
    mday := tm_mday;
    wday := tm_wday;
  end;
end;


procedure setdate(year,month,day : word);
begin
end;


procedure gettime(var hour,minute,second,sec100 : word);
var
  t  : TTime;
  tm : Ttm;
begin
  time(t); localtime_r(t,tm);
  with tm do
  begin
    hour := tm_hour;
    minute := tm_min;
    second := tm_sec;
    sec100 := 0;
  end;
end;


procedure settime(hour,minute,second,sec100 : word);
begin
end;


Procedure packtime(var t : datetime;var p : longint);
Begin
  p:=(t.sec shr 1)+(t.min shl 5)+(t.hour shl 11)+(t.day shl 16)+(t.month shl 21)+((t.year-1980) shl 25);
End;


Procedure unpacktime(p : longint;var t : datetime);
Begin
  with t do
   begin
     sec:=(p and 31) shl 1;
     min:=(p shr 5) and 63;
     hour:=(p shr 11) and 31;
     day:=(p shr 16) and 31;
     month:=(p shr 21) and 15;
     year:=(p shr 25)+1980;
   end;
End;


{******************************************************************************
                               --- Exec ---
******************************************************************************}

{$ifdef HASTHREADVAR}
threadvar
{$else HASTHREADVAR}
var
{$endif HASTHREADVAR}
  lastdosexitcode : word;

const maxargs=256;
procedure exec(const path : pathstr;const comline : comstr);
var c : comstr;
    i : integer;
    args : array[0..maxargs] of pchar;
    arg0 : pathstr;
    numargs,wstat : integer;
begin
  //writeln ('dos.exec (',path,',',comline,')');
  arg0 := fexpand (path)+#0;
  args[0] := @arg0[1];
  numargs := 0;
  c:=comline;
  i:=1;
  while i<=length(c) do
  begin
    if c[i]<>' ' then
    begin
      {Commandline argument found. append #0 and set pointer in args }
      inc(numargs);
      args[numargs]:=@c[i];
      while (i<=length(c)) and (c[i]<>' ') do
        inc(i);
      c[i] := #0;
    end;
    inc(i);
  end;
  args[numargs+1] := nil;
  // i := spawnvp (P_WAIT,args[0],@args);
  i := procve(args[0], PROC_CURRENT_SPACE+PROC_INHERIT_CWD,nil,nil,nil,nil,0,nil,args);
  if i <> -1 then
  begin
    waitpid(i,@wstat,0);
    doserror := 0;
    lastdosexitcode := wstat;
  end else
  begin
    doserror := 8;  // for now, what about errno ?
  end;
end;



function dosexitcode : word;
begin
  dosexitcode:=lastdosexitcode;
end;


procedure getcbreak(var breakvalue : boolean);
begin
end;


procedure setcbreak(breakvalue : boolean);
begin
end;


procedure getverify(var verify : boolean);
begin
  verify := true;
end;


procedure setverify(verify : boolean);
begin
end;


{******************************************************************************
                               --- Disk ---
******************************************************************************}

function getvolnum (drive : byte) : longint;
var dir : STRING[255];
    P,PS,
    V   : LONGINT;
begin
  {if drive = 0 then
  begin  // get volume name from current directory (i.e. SERVER-NAME/VOL2:TEST)
    getdir (0,dir);
    p := pos (':', dir);
    if p = 0 then
    begin
      getvolnum := -1;
      exit;
    end;
    byte (dir[0]) := p-1;
    dir[p] := #0;
    PS := pos ('/', dir);
    INC (PS);
    if _GetVolumeNumber (@dir[PS], V) <> 0 then
      getvolnum := -1
    else
      getvolnum := V;
  end else
    getvolnum := drive-1;}
end;


function diskfree(drive : byte) : int64;
VAR Buf                 : ARRAY [0..255] OF CHAR;
    TotalBlocks         : WORD;
    SectorsPerBlock     : WORD;
    availableBlocks     : WORD;
    totalDirectorySlots : WORD;
    availableDirSlots   : WORD;
    volumeisRemovable   : WORD;
    volumeNumber        : LONGINT;
begin
  volumeNumber := getvolnum (drive);
  (*
  if volumeNumber >= 0 then
  begin
    {i think thats not the right function but for others i need a connection handle}
    if _GetVolumeInfoWithNumber (byte(volumeNumber),@Buf,
                                 TotalBlocks,
                                 SectorsPerBlock,
                                 availableBlocks,
                                 totalDirectorySlots,
                                 availableDirSlots,
                                 volumeisRemovable) = 0 THEN
    begin
      diskfree := int64 (availableBlocks) * int64 (SectorsPerBlock) * 512;
    end else
      diskfree := 0;
  end else*)
    diskfree := 0;
end;


function disksize(drive : byte) : int64;
VAR Buf                 : ARRAY [0..255] OF CHAR;
    TotalBlocks         : WORD;
    SectorsPerBlock     : WORD;
    availableBlocks     : WORD;
    totalDirectorySlots : WORD;
    availableDirSlots   : WORD;
    volumeisRemovable   : WORD;
    volumeNumber        : LONGINT;
begin
  volumeNumber := getvolnum (drive);
  (*
  if volumeNumber >= 0 then
  begin
    {i think thats not the right function but for others i need a connection handle}
    if _GetVolumeInfoWithNumber (byte(volumeNumber),@Buf,
                                 TotalBlocks,
                                 SectorsPerBlock,
                                 availableBlocks,
                                 totalDirectorySlots,
                                 availableDirSlots,
                                 volumeisRemovable) = 0 THEN
    begin
      disksize := int64 (TotalBlocks) * int64 (SectorsPerBlock) * 512;
    end else
      disksize := 0;
  end else*)
    disksize := 0;
end;


{******************************************************************************
                     --- Utils ---
******************************************************************************}

procedure timet2dostime (timet:longint; var dostime : longint);
var tm : Ttm;
begin
  localtime_r(timet,tm);
  dostime:=(tm.tm_sec shr 1)+(tm.tm_min shl 5)+(tm.tm_hour shl 11)+(tm.tm_mday shl 16)+((tm.tm_mon+1) shl 21)+((tm.tm_year+1900-1980) shl 25);
end;

function nwattr2dosattr (nwattr : longint) : word;
begin
  nwattr2dosattr := 0;
  if nwattr and M_A_RDONLY > 0 then nwattr2dosattr := nwattr2dosattr + readonly;
  if nwattr and M_A_HIDDEN > 0 then nwattr2dosattr := nwattr2dosattr + hidden;
  if nwattr and M_A_SYSTEM > 0 then nwattr2dosattr := nwattr2dosattr + sysfile;
  if nwattr and M_A_SUBDIR > 0 then nwattr2dosattr := nwattr2dosattr + directory;
  if nwattr and M_A_ARCH   > 0 then nwattr2dosattr := nwattr2dosattr + archive;
end;


{******************************************************************************
                     --- Findfirst FindNext ---
******************************************************************************}


procedure find_setfields (var f : searchRec);
var
  StatBuf : TStat;
  fname   : string[255];
begin
  with F do
  begin
    if Magic = $AD01 then
    begin
      attr := nwattr2dosattr (Pdirent(EntryP)^.d_mode);
      size := Pdirent(EntryP)^.d_size;
      name := strpas (Pdirent(EntryP)^.d_name);
      doserror := 0;
      fname := f._dir + f.name;
      if length (fname) = 255 then dec (byte(fname[0]));
      fname := fname + #0;
      if stat (@fname[1],StatBuf) = 0 then
        timet2dostime (StatBuf.st_mtim.tv_sec, time)
      else
        time := 0;
    end else
    begin
      FillChar (f,sizeof(f),0);
      doserror := 18;
    end;
  end;
end;


procedure findfirst(const path : pathstr;attr : word;var f : searchRec);
var
  path0 : array[0..256] of char;
  p     : longint;
begin
  IF path = '' then
  begin
    doserror := 18;
    exit;
  end;
  if (pos ('?',path) > 0) or (pos ('*',path) > 0) then
  begin
    p := length (path);
    while (p > 0) and (not (path[p] in ['\','/'])) do
      dec (p);
    if p > 0 then
    begin
      f._mask := copy (path,p+1,255);
      f._dir := copy (path,1,p);
      strpcopy(path0,f._dir);
    end else
    begin
      f._mask := path;
      getdir (0,f._dir);
      if (f._dir[length(f._dir)] <> '/') and
         (f._dir[length(f._dir)] <> '\') then
        f._dir := f._dir + '/';
    end;
  end;
  //writeln (stderr,'mask: "',f._mask,'" dir:"',path0,'"');
  f._mask := f._mask + #0;
  Pdirent(f.DirP) := opendir (path0);
  if f.DirP = nil then
    doserror := 18
  else begin
    F.Magic := $AD01;
    findnext (f);
  end;
end;


procedure findnext(var f : searchRec);
begin
  if F.Magic <> $AD01 then
  begin
    doserror := 18;
    exit;
  end;
  doserror:=0;
  repeat
    Pdirent(f.EntryP) := readdir (Pdirent(f.DirP));
    if F.EntryP = nil then
      doserror := 18
    else
    if f._mask = #0 then
    begin
      find_setfields (f);
      exit;
    end else
    if fnmatch(@f._mask[1],Pdirent(f.EntryP)^.d_name,FNM_CASEFOLD) = 0 then
    begin
      find_setfields (f);
      exit;
    end;
  until doserror <> 0;
end;


Procedure FindClose(Var f: SearchRec);
begin
  if F.Magic <> $AD01 then
  begin
    doserror := 18;
    EXIT;
  end;
  doserror:=0;
  closedir (Pdirent(f.DirP));
  f.Magic := 0;
  f.DirP := NIL;
  f.EntryP := NIL;
end;


procedure swapvectors;
begin
end;


{******************************************************************************
                               --- File ---
******************************************************************************}

procedure fsplit(path : pathstr;var dir : dirstr;var name : namestr;var ext : extstr);
var
   dotpos,p1,i : longint;
begin
  { allow backslash as slash }
  for i:=1 to length(path) do
   if path[i]='\' then path[i]:='/';
  { get volume name }
  p1:=pos(':',path);
  if p1>0 then
    begin
       dir:=copy(path,1,p1);
       delete(path,1,p1);
    end
  else
    dir:='';
  { split the path and the name, there are no more path informtions }
  { if path contains no backslashes                                 }
  while true do
    begin
       p1:=pos('/',path);
       if p1=0 then
         break;
       dir:=dir+copy(path,1,p1);
       delete(path,1,p1);
    end;
  { try to find out a extension }
  //if LFNSupport then
    begin
       Ext:='';
       i:=Length(Path);
       DotPos:=256;
       While (i>0) Do
         Begin
            If (Path[i]='.') Then
              begin
                 DotPos:=i;
                 break;
              end;
            Dec(i);
         end;
       Ext:=Copy(Path,DotPos,255);
       Name:=Copy(Path,1,DotPos - 1);
    end
end;


function  GetShortName(var p : String) : boolean;
begin
  GetShortName := false;
end;

function  GetLongName(var p : String) : boolean;
begin
  GetLongName := false;
end;


{$define FPC_FEXPAND_DRIVES}
{$define FPC_FEXPAND_VOLUMES}
{$define FPC_FEXPAND_NO_DEFAULT_PATHS}
{$i fexpand.inc}

Function FSearch(path: pathstr; dirlist: string): pathstr;
var
  i,p1   : longint;
  s      : searchrec;
  newdir : pathstr;
begin
  system.write ('FSearch ("',path,'","',dirlist,'"');
{ check if the file specified exists }
  findfirst(path,anyfile,s);
  if doserror=0 then
   begin
     findclose(s);
     fsearch:=path;
     exit;
   end;
{ No wildcards allowed in these things }
  if (pos('?',path)<>0) or (pos('*',path)<>0) then
    fsearch:=''
  else
    begin
       { allow backslash as slash }
       for i:=1 to length(dirlist) do
         if dirlist[i]='\' then dirlist[i]:='/';
       repeat
         p1:=pos(';',dirlist);
         if p1<>0 then
          begin
            newdir:=copy(dirlist,1,p1-1);
            delete(dirlist,1,p1);
          end
         else
          begin
            newdir:=dirlist;
            dirlist:='';
          end;
         if (newdir<>'') and (not (newdir[length(newdir)] in ['/',':'])) then
          newdir:=newdir+'/';
         findfirst(newdir+path,anyfile,s);
         if doserror=0 then
          newdir:=newdir+path
         else
          newdir:='';
       until (dirlist='') or (newdir<>'');
       fsearch:=newdir;
    end;
  findclose(s);
end;


{******************************************************************************
                       --- Get/Set File Time,Attr ---
******************************************************************************}


procedure getftime(var f;var time : longint);
var
  StatBuf : TStat;
begin
  doserror := 0;
  if fstat (FileRec (f).Handle, StatBuf) = 0 then
    timet2dostime (StatBuf.st_mtim.tv_sec,time)
  else begin
    time := 0;
    doserror := ___errno^;
   end;
end;


procedure setftime(var f;time : longint);
begin
  {is there a netware function to do that ?????}
  ConsolePrintf ('warning: fpc dos.setftime not implemented'#13#10);
end;


procedure getfattr(var f;var attr : word);
VAR StatBuf : TStat;
begin
  doserror := 0;
  if fstat (FileRec (f).Handle, StatBuf) = 0 then
    attr := nwattr2dosattr (StatBuf.st_mode)
  else
  begin
    attr := 0;
    doserror := ___errno^;
  end;
end;


procedure setfattr(var f;attr : word);
var
  StatBuf : TStat;
  newMode : longint;
begin
  if fstat (FileRec(f).Handle,StatBuf) = 0 then
  begin
    newmode := StatBuf.st_mode and ($FFFFFFFF - M_A_RDONLY-M_A_HIDDEN-M_A_SYSTEM-M_A_ARCH); {only this can be set by dos unit}
    newmode := newmode and M_A_BITS_SIGNIFICANT;  {set netware attributes}
    if attr and readonly > 0 then
      newmode := newmode or M_A_RDONLY;
    if attr and hidden > 0 then
      newmode := newmode or M_A_HIDDEN;
    if attr and sysfile > 0 then
      newmode := newmode or M_A_SYSTEM;
    if attr and archive > 0 then
      newmode := newmode or M_A_ARCH;
    if fchmod (FileRec(f).Handle,newMode) < 0 then
      doserror := ___errno^ else
      doserror := 0;
  end else
    doserror := ___errno^;
end;


{******************************************************************************
                             --- Environment ---
******************************************************************************}

Function EnvCount: Longint;
var
  envcnt : longint;
  p      : ppchar;
Begin
  envcnt:=0;
  p:=envp;      {defined in system}
  while (p^<>nil) do
  begin
    inc(envcnt);
    inc(p);
  end;
  EnvCount := envcnt
End;


Function EnvStr (Index: longint): String;
Var
  i : longint;
  p : ppchar;
Begin
  if Index <= 0 then
    envstr:=''
  else
  begin
    p:=envp;      {defined in system}
    i:=1;
    while (i<Index) and (p^<>nil) do
    begin
      inc(i);
      inc(p);
    end;
    if p=nil then
      envstr:=''
    else
      envstr:=strpas(p^)
  end;
end;


{ works fine (at least with netware 6.5) }
Function  GetEnv(envvar: string): string;
var envvar0 : array[0..512] of char;
    p       : pchar;
    i,isDosPath,res : longint;
begin
  if upcase(envvar) = 'PATH' then
  begin  // netware does not have search paths in the environment var PATH
         // return it here (needed for the compiler)
    GetEnv := '';
    i := 1;
    res := GetSearchPathElement (i, isdosPath, @envvar0[0]);
    while res = 0 do
    begin
      if GetEnv <> '' then GetEnv := GetEnv + ';';
      GetEnv := GetEnv + envvar0;
      inc (i);
      res := GetSearchPathElement (i, isdosPath, @envvar0[0]);
    end;
    for i := 1 to length(GetEnv) do
      if GetEnv[i] = '\' then
        GetEnv[i] := '/';
  end else
  begin
    strpcopy(envvar0,envvar);
    p := libc.getenv (envvar0);
    if p = NIL then
      GetEnv := ''
    else
      GetEnv := strpas (p);
  end;
end;


{******************************************************************************
                             --- Not Supported ---
******************************************************************************}

Procedure keep(exitcode : word);
Begin
 { simply wait until nlm will be unloaded }
 while true do delay (60000);
End;

Procedure getintvec(intno : byte;var vector : pointer);
Begin
 { no netware equivalent }
End;

Procedure setintvec(intno : byte;vector : pointer);
Begin
 { no netware equivalent }
End;

procedure intr(intno : byte;var regs : registers);
begin
 { no netware equivalent }
end;

procedure msdos(var regs : registers);
begin
 { no netware equivalent }
end;


end.
{
  $Log$
  Revision 1.1  2004-09-05 20:58:47  armin
  * first rtl version for netwlibc

}

