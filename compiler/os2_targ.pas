{
    $Id$
    Copyright (c) 1993-98 by Daniel Mantione
    Portions Copyright (c) 1992-96 Eberhard Mattes

    Unit to write out import libraries and def files for OS/2

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
{
   A lot of code in this unit has been ported from C to Pascal from the
   emximp utility, part of the EMX development system. Emximp is copyrighted
   by Eberhard Mattes. Note: Eberhard doesn't know much about the Pascal
   port, please send questions to Daniel Mantione
   <d.s.p.mantione@twi.tudelft.nl>.
}
unit os2_targ;

interface

uses import;

type
  pimportlibos2=^timportlibos2;
  timportlibos2=object(timportlib)
    procedure preparelib(const s:string);virtual;
    procedure importprocedure(const func,module:string;index:longint;const name:string);virtual;
    procedure generatelib;virtual;
  end;

procedure write_def_file;

{***************************************************************************}

{***************************************************************************}

implementation

uses    dos,strings,globals,link,files;

const   profile_flag:boolean=false;

const   n_ext   = 1;
        n_abs   = 2;
        n_text  = 4;
        n_data  = 6;
        n_bss   = 8;
        n_imp1  = $68;
        n_imp2  = $6a;

type    reloc=packed record     {This is the layout of a relocation table
                                 entry.}
            address:longint;    {Fixup location}
            remaining:longint;
            {Meaning of bits for remaining:
             0..23:              Symbol number or segment
             24:                 Self-relative fixup if non-zero
             25..26:             Fixup size (0: 1 byte, 1: 2, 2: 4 bytes)
             27:                 Reference to symbol or segment
             28..31              Not used}
        end;

        nlist=packed record     {This is the layout of a symbol table entry.}
            strofs:longint;     {Offset in string table}
            typ:byte;           {Type of the symbol}
            other:byte;         {Other information}
            desc:word;          {More information}
            value:longint;      {Value (address)}
        end;

        a_out_header=packed record
            magic:word;         {Magic word, must be $0107}
            machtype:byte;      {Machine type}
            flags:byte;         {Flags}
            text_size:longint;  {Length of text, in bytes}
            data_size:longint;  {Length of initialized data, in bytes}
            bss_size:longint;   {Length of uninitialized data, in bytes}
            sym_size:longint;   {Length of symbol table, in bytes}
            entry:longint;      {Start address (entry point)}
            trsize:longint;     {Length of relocation info for text, bytes}
            drsize:longint;     {Length of relocation info for data, bytes}
        end;

        ar_hdr=packed record
            ar_name:array[0..15] of char;
            ar_date:array[0..11] of char;
            ar_uid:array[0..5] of char;
            ar_gid:array[0..5] of char;
            ar_mode:array[0..7] of char;
            ar_size:array[0..9] of char;
            ar_fmag:array[0..1] of char;
        end;

var aout_str_size:longint;
    aout_str_tab:array[0..2047] of byte;
    aout_sym_count:longint;
    aout_sym_tab:array[0..5] of nlist;

    aout_text:array[0..63] of byte;
    aout_text_size:longint;

    aout_treloc_tab:array[0..1] of reloc;
    aout_treloc_count:longint;

    aout_size:longint;
    seq_no:longint;

    ar_member_size:longint;

    out_file:file;

procedure write_ar(const name:string;size:longint);

var ar:ar_hdr;
    time:datetime;
    dummy:word;
    numtime:longint;
    tmp:string[19];


begin
    ar_member_size:=size;
    fillchar(ar.ar_name,sizeof(ar.ar_name),' ');
    move(name[1],ar.ar_name,length(name));
    getdate(time.year,time.month,time.day,dummy);
    gettime(time.hour,time.min,time.sec,dummy);
    packtime(time,numtime);
    str(numtime,tmp);
    fillchar(ar.ar_date,sizeof(ar.ar_date),' ');
    move(tmp[1],ar.ar_date,length(tmp));
    ar.ar_uid:='0     ';
    ar.ar_gid:='0     ';
    ar.ar_mode:='100666'#0#0;
    str(size,tmp);
    fillchar(ar.ar_size,sizeof(ar.ar_size),' ');
    move(tmp[1],ar.ar_size,length(tmp));
    ar.ar_fmag:='`'#10;
    blockwrite(out_file,ar,sizeof(ar));
end;

procedure finish_ar;

var a:byte;

begin
    a:=0;
    if odd(ar_member_size) then
        blockwrite(out_file,a,1);
end;

procedure aout_init;

begin
  aout_str_size:=sizeof(longint);
  aout_sym_count:=0;
  aout_text_size:=0;
  aout_treloc_count:=0;
end;

function aout_sym(const name:string;typ,other:byte;desc:word;
                  value:longint):longint;

begin
    if aout_str_size+length(name)+1>sizeof(aout_str_tab) then
        runerror($da);
    if aout_sym_count>=sizeof(aout_sym_tab) div sizeof(aout_sym_tab[0]) then
        runerror($da);
    aout_sym_tab[aout_sym_count].strofs:=aout_str_size;
    aout_sym_tab[aout_sym_count].typ:=typ;
    aout_sym_tab[aout_sym_count].other:=other;
    aout_sym_tab[aout_sym_count].desc:=desc;
    aout_sym_tab[aout_sym_count].value:=value;
    strPcopy(@aout_str_tab[aout_str_size],name);
    aout_str_size:=aout_str_size+length(name)+1;
    aout_sym:=aout_sym_count;
    inc(aout_sym_count);
end;

procedure aout_text_byte(b:byte);

begin
    if aout_text_size>=sizeof(aout_text) then
        runerror($da);
    aout_text[aout_text_size]:=b;
    inc(aout_text_size);
end;

procedure aout_text_dword(d:longint);

type li_ar=array[0..3] of byte;

begin
    aout_text_byte(li_ar(d)[0]);
    aout_text_byte(li_ar(d)[1]);
    aout_text_byte(li_ar(d)[2]);
    aout_text_byte(li_ar(d)[3]);
end;

procedure aout_treloc(address,symbolnum,pcrel,len,ext:longint);

begin
    if aout_treloc_count>=sizeof(aout_treloc_tab) div sizeof(reloc) then
        runerror($da);
    aout_treloc_tab[aout_treloc_count].address:=address;
    aout_treloc_tab[aout_treloc_count].remaining:=symbolnum+pcrel shl 24+
     len shl 25+ext shl 27;
    inc(aout_treloc_count);
end;

procedure aout_finish;

begin
    while (aout_text_size and 3)<>0 do
        aout_text_byte ($90);
    aout_size:=sizeof(a_out_header)+aout_text_size+aout_treloc_count*
     sizeof(reloc)+aout_sym_count*sizeof(aout_sym_tab[0])+aout_str_size;
end;

procedure aout_write;

var ao:a_out_header;

begin
    ao.magic:=$0107;
    ao.machtype:=0;
    ao.flags:=0;
    ao.text_size:=aout_text_size;
    ao.data_size:=0;
    ao.bss_size:=0;
    ao.sym_size:=aout_sym_count*sizeof(aout_sym_tab[0]);
    ao.entry:=0;
    ao.trsize:=aout_treloc_count*sizeof(reloc);
    ao.drsize:=0;
    blockwrite(out_file,ao,sizeof(ao));
    blockwrite(out_file,aout_text,aout_text_size);
    blockwrite(out_file,aout_treloc_tab,sizeof(reloc)*aout_treloc_count);
    blockwrite(out_file,aout_sym_tab,sizeof(aout_sym_tab[0])*aout_sym_count);
    longint((@aout_str_tab)^):=aout_str_size;
    blockwrite(out_file,aout_str_tab,aout_str_size);
end;

procedure timportlibos2.preparelib(const s:string);

{This code triggers a lot of bugs in the compiler.
const   armag='!<arch>'#10;
        ar_magic:array[1..length(armag)] of char=armag;}
const   ar_magic:array[1..8] of char='!<arch>'#10;

begin
    seq_no:=1;
    Linker.AddSharedLibrary(s+'.dll');
    current_module^.linkofiles.insert(s+'.dll');
    assign(out_file,s+'.ao2');
    rewrite(out_file,1);
    blockwrite(out_file,ar_magic,sizeof(ar_magic));
end;

procedure timportlibos2.importprocedure(const func,module:string;index:longint;const name:string);
{func       = Name of function to import.
 module     = Name of DLL to import from.
 index      = Index of function in DLL. Use 0 to import by name.
 name       = Name of function in DLL. Ignored when index=0;}
var tmp1,tmp2,tmp3:string;
    sym_mcount,sym_entry,sym_import:longint;
    fixup_mcount,fixup_import:longint;
begin
    aout_init;
    tmp2:=func;
    if profile_flag and not (copy(func,1,4)='_16_') then
        begin
            sym_entry:=aout_sym(func,n_text+n_ext,0,0,aout_text_size);
            sym_mcount:=aout_sym('__mcount',n_ext,0,0,0);
            {Use, say, "_$U_DosRead" for "DosRead" to import the
             non-profiled function.}
            tmp2:='__$U_'+func;
            sym_import:=aout_sym(tmp2,n_ext,0,0,0);
            aout_text_byte($55);    {push ebp}
            aout_text_byte($89);    {mov ebp, esp}
            aout_text_byte($e5);
            aout_text_byte($e8);    {call _mcount}
            fixup_mcount:=aout_text_size;
            aout_text_dword(0-(aout_text_size+4));
            aout_text_byte($5d);    {pop ebp}
            aout_text_byte($e9);    {jmp _$U_DosRead}
            fixup_import:=aout_text_size;
            aout_text_dword(0-(aout_text_size+4));

            aout_treloc(fixup_mcount,sym_mcount,1,2,1);
            aout_treloc (fixup_import, sym_import,1,2,1);
        end;
    str(seq_no,tmp1);
    tmp1:='IMPORT#'+tmp1;
    if name='' then
        begin
            str(index,tmp3);
            tmp3:=func+'='+module+'.'+tmp3;
        end
    else
        tmp3:=func+'='+module+'.'+name;
    aout_sym(tmp2,n_imp1+n_ext,0,0,0);
    aout_sym(tmp3,n_imp2+n_ext,0,0,0);
    aout_finish;
    write_ar(tmp1,aout_size);
    aout_write;
    finish_ar;
    inc(seq_no);
end;

procedure timportlibos2.generatelib;

begin
    close(out_file);
end;


procedure write_def_file;
begin
   assign(deffile,inputdir+inputfile+'.DEF');
   {$I+}
    rewrite(deffile);
   {$I-}
   if ioresult=0 then
    begin
      write(deffile,'NAME '+inputfile);
      if genpm then
        write(deffile,' WINDOWAPI');
      writeln(deffile,#13#10#13#10'PROTMODE'#13#10);
      writeln(deffile,'DESCRIPTION '+''''+description+''''#13#10);
      writeln(deffile,'DATA'#9'MULTIPLE'#13#10);
      writeln(deffile,'STACKSIZE'#9+tostr(stacksize));
      writeln(deffile,'HEAPSIZE'#9+tostr(heapsize)+#13#10);
      write(deffile,'EXPORTS');
    end
   else
    gendeffile:=false;
end;

end.

{
  $Log$
  Revision 1.2  1998-05-04 17:54:27  peter
    + smartlinking works (only case jumptable left todo)
    * redesign of systems.pas to support assemblers and linkers
    + Unitname is now also in the PPU-file, increased version to 14

}
