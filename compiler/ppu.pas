{
    $Id$
    Copyright (c) 1993-98 by Florian Klaempfl

    Routines to read/write ppu files

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

 ****************************************************************************
}
unit ppu;
interface

const
{ buffer sizes }
  maxentrysize = 1024;
{$ifdef TP}
  ppubufsize   = 1024;
{$else}
  ppubufsize   = 16384;
{$endif}

{ppu entries}
  ibmodulename    = 1;
  ibsourcefile    = 2;
  ibloadunit_int  = 3;
  ibloadunit_imp  = 4;
  ibinitunit      = 5;
  iblinkofile     = 6;
  ibsharedlibs    = 7;
  ibstaticlibs    = 8;
  ibdbxcount      = 9;
  ibref           = 10;
  ibenddefs       = 250;
  ibendsyms       = 251;
  ibendheader     = 252;
  ibentry         = 254;
  ibend           = 255;
  {syms}
  ibtypesym       = 20;
  ibprocsym       = 21;
  ibvarsym        = 22;
  ibconstsym      = 23;
  ibenumsym       = 24;
  ibtypedconstsym = 25;
  ibabsolutesym   = 26;
  ibpropertysym   = 27;
  {defenitions}
  iborddef        = 40;
  ibpointerdef    = 41;
  ibarraydef      = 42;
  ibprocdef       = 43;
  ibstringdef     = 44;
  ibrecorddef     = 45;
  ibfiledef       = 46;
  ibformaldef     = 47;
  ibobjectdef     = 48;
  ibenumdef       = 49;
  ibsetdef        = 50;
  ibprocvardef    = 51;
  ibfloatdef      = 52;
  ibextsymref     = 53;
  ibextdefref     = 54;
  ibclassrefdef   = 55;
  iblongstringdef = 56;
  ibansistringdef = 57;
  ibwidestringdef = 58;

{ unit flags }
  uf_init           = $1;
  uf_uses_dbx       = $2;
  uf_uses_browser   = $4;
  uf_big_endian     = $8;
  uf_in_library     = $10;
  uf_shared_library = $20;
  uf_smartlink      = $40;


type
  tppuerror=(ppuentrytoobig,ppuentryerror);

  tppuheader=packed record
    id       : array[1..3] of char; { = 'PPU' }
    ver      : array[1..3] of char;
    compiler : word;
    target   : word;
    flags    : longint;
    size     : longint;
    checksum : longint;
  end;

  tppuentry=packed record
    id   : byte;
    nr   : byte;
    size : word;
  end;

  pppufile=^tppufile;
  tppufile=object
    f        : file;
    mode     : byte; {0 - Closed, 1 - Reading, 2 - Writing}
    error    : boolean;
    fname    : string;
    fsize    : longint;

    header   : tppuheader;
    size,crc : longint;
    do_crc,
    change_endian : boolean;

    buf      : pchar;
    bufstart,
    bufsize,
    bufidx   : longint;
    entry    : tppuentry;
    entrystart,
    entryidx : longint;

    constructor init(fn:string);
    destructor  done;
    procedure flush;
    procedure close;
    function  CheckPPUId:boolean;
    function  GetPPUVersion:longint;
    procedure NewHeader;
    procedure NewEntry;
    function  EndOfEntry:boolean;
  {read}
    function  open:boolean;
    procedure reloadbuf;
    procedure readdata(var b;len:longint);
    function  readentry:byte;
    procedure getdata(var b;len:longint);
    function  getbyte:byte;
    function  getword:word;
    function  getlongint:longint;
    function  getstring:string;
  {write}
    function  create:boolean;
    procedure writeheader;
    procedure writebuf;
    procedure writedata(var b;len:longint);
    procedure writeentry(ibnr:byte);
    procedure putdata(var b;len:longint);
    procedure putbyte(b:byte);
    procedure putword(w:word);
    procedure putlongint(l:longint);
    procedure putstring(s:string);
  end;

implementation


{*****************************************************************************
                                   Crc 32
*****************************************************************************}

var
  Crc32Tbl : array[0..255] of longint;

procedure MakeCRC32Tbl;
var
  crc : longint;
  i,n : byte;
begin
  for i:=0 to 255 do
   begin
     crc:=i;
     for n:=1 to 8 do
      if odd(crc) then
       crc:=(crc shr 1) xor $edb88320
      else
       crc:=crc shr 1;
     Crc32Tbl[i]:=crc;
   end;
end;



{CRC 32}
Function Crc32(Const HStr:String):longint;
var
  i,InitCrc : longint;
begin
  if Crc32Tbl[1]=0 then
   MakeCrc32Tbl;
  InitCrc:=$ffffffff;
  for i:=1to Length(Hstr) do
   InitCrc:=Crc32Tbl[byte(InitCrc) xor ord(Hstr[i])] xor (InitCrc shr 8);
  Crc32:=InitCrc;
end;



Function UpdateCrc32(InitCrc:longint;var InBuf;InLen:Longint):longint;
var
  i : word;
  p : pchar;
begin
  if Crc32Tbl[1]=0 then
   MakeCrc32Tbl;
  p:=@InBuf;
  for i:=1to InLen do
   begin
     InitCrc:=Crc32Tbl[byte(InitCrc) xor byte(p^)] xor (InitCrc shr 8);
     inc(longint(p));
   end;
  UpdateCrc32:=InitCrc;
end;



Function UpdCrc32(InitCrc:longint;b:byte):longint;
begin
  if Crc32Tbl[1]=0 then
   MakeCrc32Tbl;
  UpdCrc32:=Crc32Tbl[byte(InitCrc) xor b] xor (InitCrc shr 8);
end;


{*****************************************************************************
                                  TPPUFile
*****************************************************************************}

constructor tppufile.init(fn:string);
begin
  fname:=fn;
  change_endian:=false;
  Mode:=0;
  NewHeader;
  getmem(buf,ppubufsize);
end;


destructor tppufile.done;
begin
  close;
  freemem(buf,ppubufsize);
end;


procedure tppufile.flush;
begin
  if Mode=2 then
   writebuf;
end;


procedure tppufile.close;
var
  i : word;
begin
  if Mode<>0 then
   begin
     Flush;
     {$I-}
      system.close(f);
     {$I+}
     i:=ioresult;
     Mode:=0;
   end;
end;


function tppufile.CheckPPUId:boolean;
begin
  CheckPPUId:=((Header.Id[1]='P') and (Header.Id[2]='P') and (Header.Id[3]='U'));
end;


function tppufile.GetPPUVersion:longint;
var
  l    : longint;
  code : word;
begin
  Val(header.ver[1]+header.ver[2]+header.ver[3],l,code);
  if code=0 then
   GetPPUVersion:=l
  else
   GetPPUVersion:=0;
end;


procedure tppufile.NewHeader;
begin
  fillchar(header,sizeof(tppuheader),0);
  with header do
   begin
     Id[1]:='P';
     Id[2]:='P';
     Id[3]:='U';
     Ver[1]:='0';
     Ver[2]:='1';
     Ver[3]:='5';
   end;
end;


procedure tppufile.NewEntry;
begin
  with entry do
   begin
     id:=ibentry;
     nr:=ibend;
     size:=0;
   end;
  entryidx:=0;
end;



function tppufile.endofentry:boolean;
begin
  endofentry:=(entryidx>=entry.size);
end;

{*****************************************************************************
                                TPPUFile Reading
*****************************************************************************}

function tppufile.open:boolean;
var
  ofmode : byte;
  i      : word;
begin
  open:=false;
  assign(f,fname);
  ofmode:=filemode;
  filemode:=$0;
  {$I-}
   reset(f,1);
  {$I+}
  filemode:=ofmode;
  if ioresult<>0 then
   exit;
{read ppuheader}
  fsize:=filesize(f);
  if fsize<sizeof(tppuheader) then
   exit;
  blockread(f,header,sizeof(tppuheader),i);
{reset buffer}
  bufstart:=i;
  bufsize:=0;
  Mode:=1;
  open:=true;
end;


procedure tppufile.reloadbuf;
{$ifdef TP}
var
  i : word;
{$endif}
begin
  inc(bufstart,bufsize);
{$ifdef TP}
  blockread(f,buf,ppubufsize,i);
  bufsize:=i;
{$else}
  blockread(f,buf,ppubufsize,bufsize);
{$endif}
  bufidx:=0;
end;


procedure tppufile.readdata(var b;len:longint);
var
  p   : pchar;
  left,
  idx : longint;
begin
  p:=pchar(@b);
  idx:=0;
  while len>0 do
   begin
     left:=bufsize-bufidx;
     if len>left then
      begin
        move(buf[bufidx],p[idx],left);
        dec(len,left);
        inc(idx,left);
        reloadbuf;
        if bufsize=0 then
         exit;
      end
     else
      begin
        move(buf[bufidx],p[idx],len);
        inc(bufidx,len);
        exit;
      end;
   end;
end;


function tppufile.readentry:byte;
begin
  readdata(entry,sizeof(tppuentry));
  if entry.id<>ibentry then
   begin
     error:=true;
     exit;
   end;
  readentry:=entry.nr;
  entryidx:=0;
end;


procedure tppufile.getdata(var b;len:longint);
begin
  if entryidx+len>entry.size then
   begin
     error:=true;
     exit;
   end;
  readdata(b,len);
  inc(entryidx,len);
end;


function tppufile.getbyte:byte;
var
  b : byte;
begin
  if entryidx+1>entry.size then
   begin
     error:=true;
     exit;
   end;
{  if bufidx+1>bufsize then
  getbyte:=ord(buf[bufidx]);
  inc(bufidx);}
  readdata(b,1);
  getbyte:=b;
  inc(entryidx);
end;


function tppufile.getword:word;
type
  pword = ^word;
var
  w : word;
begin
  if entryidx+2>entry.size then
   begin
     error:=true;
     exit;
   end;
{  getword:=pword(@entrybuf[entrybufidx])^;}
  readdata(w,2);
  getword:=w;
  inc(entryidx,2);
end;


function tppufile.getlongint:longint;
type
  plongint = ^longint;
var
  l : longint;
begin
  if entryidx+4>entry.size then
   begin
     error:=true;
     exit;
   end;
  readdata(l,4);
  getlongint:=l;
{
  getlongint:=plongint(@entrybuf[entrybufidx])^;}
  inc(entryidx,4);
end;


function tppufile.getstring:string;
var
  s : string;
begin
  s[0]:=chr(getbyte);
  if entryidx+length(s)>entry.size then
   begin
     error:=true;
     exit;
   end;
  ReadData(s[1],length(s));
  getstring:=s;
{ move(entrybuf[entrybufidx],s[1],length(s));}
  inc(entryidx,length(s));
end;


{*****************************************************************************
                                TPPUFile Writing
*****************************************************************************}

function tppufile.create:boolean;
begin
  create:=false;
  assign(f,fname);
  {$I-}
   rewrite(f,1);
  {$I+}
  if ioresult<>0 then
   exit;
  Mode:=2;
{write header for sure}
  blockwrite(f,header,sizeof(tppuheader));
  bufsize:=ppubufsize;
{reset}
  crc:=$ffffffff;
  do_crc:=true;
  size:=0;
  create:=true;
end;


procedure tppufile.writeheader;
var
  opos : longint;
begin
  writebuf;
  opos:=filepos(f);
  seek(f,0);
  blockwrite(f,header,sizeof(tppuheader));
  seek(f,opos);
end;


procedure tppufile.writebuf;
begin
  if do_crc then
   UpdateCrc32(crc,buf,bufidx);
  blockwrite(f,buf,bufidx);
  inc(bufstart,bufidx);
  bufidx:=0;
end;


procedure tppufile.writedata(var b;len:longint);
var
  p   : pchar;
  left,
  idx : longint;
begin
  p:=pchar(@b);
  idx:=0;
  while len>0 do
   begin
     left:=bufsize-bufidx;
     if len>left then
      begin
        move(p[idx],buf[bufidx],left);
        dec(len,left);
        inc(idx,left);
        writebuf;
      end
     else
      begin
        move(p[idx],buf[bufidx],len);
        inc(bufidx,len);
        exit;
      end;
   end;
end;


procedure tppufile.writeentry(ibnr:byte);
var
  opos : longint;
begin
{create entry}
  entry.id:=ibentry;
  entry.nr:=ibnr;
  entry.size:=entryidx;
{flush}
  writebuf;
{write entry}
  opos:=filepos(f);
  seek(f,entrystart);
  blockwrite(f,entry,sizeof(tppuentry));
  seek(f,opos);
  entrystart:=opos; {next entry position}
{Add New Entry, which is ibend by default}
  NewEntry;
  writedata(entry,sizeof(tppuentry));
end;


procedure tppufile.putdata(var b;len:longint);
begin
  writedata(b,len);
  inc(entryidx,len);
end;



procedure tppufile.putbyte(b:byte);
begin
  writedata(b,1);
{
  entrybuf[entrybufidx]:=chr(b);}
  inc(entryidx);
end;


procedure tppufile.putword(w:word);
type
  pword = ^word;
begin
  if change_endian then
   w:=swap(w);
{  pword(@entrybuf[entrybufidx])^:=w;}
  writedata(w,2);
  inc(entryidx,2);
end;


procedure tppufile.putlongint(l:longint);
type
  plongint = ^longint;
begin
{  plongint(@entrybuf[entrybufidx])^:=l;}
  if change_endian then
   l:=swap(l shr 16) or (longint(swap(l and $ffff)) shl 16);
  writedata(l,4);
  inc(entryidx,4);
end;


procedure tppufile.putstring(s:string);
begin
  writedata(s,length(s)+1);
{  move(s,entrybuf[entrybufidx],length(s)+1);}
  inc(entryidx,length(s)+1);
end;


end.
{
  $Log$
  Revision 1.2  1998-05-27 19:45:08  peter
    * symtable.pas splitted into includefiles
    * symtable adapted for $ifdef NEWPPU

  Revision 1.1  1998/05/12 10:56:07  peter
    + the ppufile object unit

}