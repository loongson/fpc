{
    $Id$
    Copyright (c) 1996-98 by Florian Klaempfl

    This unit implements an extended file management and the first loading
    and searching of the modules (ppufiles)

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
unit files;

  interface

    uses
       cobjects,globals;

    const
{$ifdef FPC}
       maxunits = 1024;
       extbufsize = 65535;
{$else}
       maxunits = 128;
       extbufsize = 2000;
{$endif}

    type
       { this isn't a text file, this is t-ext-file }
       { which means a extended file this files can }
       { be handled by a file manager               }
       pextfile = ^textfile;
       textfile = object(tbufferedfile)
          path,name,ext : pstring;
          _next      : pextfile; { else conflicts with tinputstack }
          ref_index  : word;     { 65000 input files for a unit should be enough !! }
          { p must be the complete path (with ending \ (or / for unix ...) }
          constructor init(const p,n,e : string);
          destructor done;virtual;
       end;

       pinputfile = ^tinputfile;
       tinputfile = object(textfile)
          filenotatend : boolean;
          line_no      : longint;
          line_count   : longint;    { second counter for unimportant tokens }
          next         : pinputfile; { next input file in the stack of input files }
          ref_count    : longint;    { to handle the browser refs }
          constructor init(const p,n,e : string);
          procedure write_file_line(var t : text); { writes the file name and line number to t }
          function  get_file_line : string;
       end;

       pfilemanager = ^tfilemanager;
       tfilemanager = object
          files : pextfile;
          last_ref_index : word;
          constructor init;
          destructor done;
          procedure close_all;
          procedure register_file(f : pextfile);
          function  get_file(w : word) : pextfile;
       end;

    type
       tunitmap = array[0..maxunits-1] of pointer;
       punitmap = ^tunitmap;

       pmodule = ^tmodule;
       tmodule = object(tlinkedlist_item)
          ppufile       : pextfile; { the PPU file }
          ppuversion,               { PPU version, handle different versions }
          crc,                      { check sum written to the file }
          flags         : longint;  { flags }

          compiled,                 { unit is already compiled }
          do_assemble,              { only assemble the object, don't recompile }
          do_compile,               { need to compile the sources }
          sources_avail,            { if all sources are reachable }
          in_implementation,        { processing the implementation part? }
          in_main       : boolean;  { global, after uses else false }

          map           : punitmap; { mapping of all used units }
          unitcount     : word;     { local unit counter }
          symtable      : pointer;  { pointer to the psymtable of this unit }
          output_format : tof;      { how to write this file }

          uses_imports  : boolean;  { Set if the module imports from DLL's.}
          imports       : plinkedlist;

          sourcefiles   : tfilemanager;
          linksharedlibs,
          linkstaticlibs,
          linkofiles    : tstringcontainer;
          used_units    : tlinkedlist;
          current_inputfile : pinputfile;
          { used in firstpass for faster settings }
          current_index : word;

          unitname,                 { name of the (unit) module in uppercase }
          objfilename,              { fullname of the objectfile }
          asmfilename,              { fullname of the assemblerfile }
          ppufilename,              { fullname of the ppufile }
          arfilename,               { fullname of the archivefile }
          mainsource    : pstring;  { name of the main sourcefile }

          constructor init(const s:string;is_unit:boolean);
          destructor special_done;virtual; { this is to be called only when compiling again }

          procedure setfilename(const path,name:string);
          function  load_ppu(const unit_path,n,ext:string):boolean;
          procedure search_unit(const n : string);
       end;

       pused_unit = ^tused_unit;
       tused_unit = object(tlinkedlist_item)
          u               : pmodule;
          in_uses,
          in_interface,
          is_stab_written : boolean;
          unitid          : word;
          constructor init(_u : pmodule;f : byte);
          destructor done;virtual;
       end;

       tunitheader = array[0..19] of char;

    const
                                   {                compiler version }
                                   {             format      |       }
                                   { signature    |          |       }
                                   {  |           |          |       }
                                   { /-------\   /-------\  /----\   }
       unitheader : tunitheader  = ('P','P','U','0','1','4',#0,#99,
                                     #0,#0,#0,#0,#0,#0,#255,#255,
                                   { |   | \---------/ \-------/    }
                                   { |   |    |             |        }
                                   { |   |    check sum     |        }
                                   { |   \--flags        unused      }
                                   { target system                   }
                                    #0,#0,#0,#0);
                                   {\---------/                      }
                                   {  |                              }
                                   {  start of machine language      }

       ibloadunit      = 1;
       iborddef        = 2;
       ibpointerdef    = 3;
       ibtypesym       = 4;
       ibarraydef      = 5;
       ibprocdef       = 6;
       ibprocsym       = 7;
       iblinkofile     = 8;
       ibstringdef     = 9;
       ibvarsym        = 10;
       ibconstsym      = 11;
       ibinitunit      = 12;
       ibaufzaehlsym   = 13;
       ibtypedconstsym = 14;
       ibrecorddef     = 15;
       ibfiledef       = 16;
       ibformaldef     = 17;
       ibobjectdef     = 18;
       ibenumdef       = 19;
       ibsetdef        = 20;
       ibprocvardef    = 21;
       ibsourcefile    = 22;
       ibdbxcount      = 23;
       ibfloatdef      = 24;
       ibref           = 25;
       ibextsymref     = 26;
       ibextdefref     = 27;
       ibabsolutesym   = 28;
       ibclassrefdef   = 29;
       ibpropertysym   = 30;
       ibsharedlibs    = 31;
       iblongstringdef = 32;
       ibansistringdef = 33;
       ibunitname      = 34;
       ibwidestringdef = 35;
       ibstaticlibs    = 36;
       ibend           = 255;

       { unit flags }
       uf_init           = $1;
       uf_uses_dbx       = $2;
       uf_uses_browser   = $4;
       uf_in_library     = $8;
       uf_shared_library = $10;
       uf_big_endian     = $20;
       uf_smartlink      = $40;

    const
       main_module    : pmodule = nil;
       current_module : pmodule = nil;

    var
       loaded_units   : tlinkedlist;


  implementation

  uses
    dos,verbose,systems;


{****************************************************************************
                                  TFILE
 ****************************************************************************}

    constructor textfile.init(const p,n,e : string);

      begin
         inherited init(p+n+e,extbufsize);
         path:=stringdup(p);
         name:=stringdup(n);
         ext:=stringdup(e);
      end;

    destructor textfile.done;

      begin
         inherited done;
      end;

{****************************************************************************
                                  TINPUTFILE
 ****************************************************************************}

    constructor tinputfile.init(const p,n,e : string);

      begin
         inherited init(p,n,e);
         filenotatend:=true;
         line_no:=1;
         line_count:=0;
         next:=nil;
      end;

    procedure tinputfile.write_file_line(var t : text);

      begin
         write(t,get_file_line);
      end;

    function tinputfile.get_file_line : string;

      begin
        if Use_Rhide then
          get_file_line:=lowercase(bstoslash(path^)+name^+ext^)+':'+tostr(line_no)+':'
        else
          get_file_line:=name^+ext^+'('+tostr(line_no)+')'
      end;

{****************************************************************************
                                TFILEMANAGER
 ****************************************************************************}

    constructor tfilemanager.init;

      begin
         files:=nil;
         last_ref_index:=0;
      end;

    destructor tfilemanager.done;

      var
         hp : pextfile;

      begin
         hp:=files;
         while assigned(hp) do
           begin
              files:=files^._next;
              dispose(hp,done);
              hp:=files;
           end;
      end;

    procedure tfilemanager.close_all;

      begin
      end;

    procedure tfilemanager.register_file(f : pextfile);

      begin
         inc(last_ref_index);
         f^._next:=files;
         f^.ref_index:=last_ref_index;
         files:=f;
      end;

   function tfilemanager.get_file(w : word) : pextfile;

     var
        ff : pextfile;
     begin
        ff:=files;
        while assigned(ff) and (ff^.ref_index<>w) do
          ff:=ff^._next;
        get_file:=ff;
     end;
{****************************************************************************
                                  TMODULE
 ****************************************************************************}

    procedure tmodule.setfilename(const path,name:string);
      var
        s : string;
      begin
         stringdispose(objfilename);
         stringdispose(asmfilename);
         stringdispose(ppufilename);
         stringdispose(arfilename);
         s:=FixFileName(FixPath(path)+name);
         objfilename:=stringdup(s+target_info.objext);
         asmfilename:=stringdup(s+target_info.asmext);
         ppufilename:=stringdup(s+target_info.unitext);
         arfilename:=stringdup(s+target_os.staticlibext);
      end;

    function tmodule.load_ppu(const unit_path,n,ext : string):boolean;
      var
         header  : tunitheader;
         count   : longint;
         temp,hs : string;
         b       : byte;
         code    : word;
         objfiletime,
         ppufiletime,
         asmfiletime,
         source_time : longint;
{$ifdef UseBrowser}
         hp : pextfile;
         _d : dirstr;
         _n : namestr;
         _e : extstr;
{$endif UseBrowser}

    begin
      load_ppu:=false;

      Message1(unit_u_ppu_loading,ppufilename^);
      ppufile:=new(pextfile,init(unit_path,n,ext));
      ppufile^.reset;
      ppufile^.flush;

      {Get ppufile time}
      ppufiletime:=getnamedfiletime(ppufilename^);
      Message1(unit_d_ppu_time,filetimestring(ppufiletime));

      { load the header }
      ppufile^.read_data(header,sizeof(header),count);
      if count<>sizeof(header) then
       begin
         ppufile^.done;
         Message(unit_d_ppu_file_too_short);
         exit;
       end;

      { check for a valid PPU file }
      if (header[0]<>'P') or (header[1]<>'P') or (header[2]<>'U') then
       begin
         ppufile^.done;
         Message(unit_d_ppu_invalid_header);
         exit;
       end;

      { load ppu version }
      val(header[3]+header[4]+header[5],ppuversion,code);
      if not(ppuversion in [13..14]) then
       begin
         ppufile^.done;
         Message1(unit_d_ppu_invalid_version,tostr(ppuversion));
         exit;
       end;

      flags:=byte(header[9]);
      Message1(unit_d_ppu_flags,tostr(flags));

      crc:=plongint(@header[10])^;
      Message1(unit_d_ppu_crc,tostr(crc));

    { read name if its there }
      ppufile^.read_data(b,1,count);
      if b=ibunitname then
       begin
         ppufile^.read_data(hs[0],1,count);
         ppufile^.read_data(hs[1],ord(hs[0]),count);
         stringdispose(unitname);
         unitname:=stringdup(hs);
         ppufile^.read_data(b,1,count);
       end;

    { search source files there is at least one source file }
      do_compile:=false;
      sources_avail:=true;
      while b<>ibend do
       begin
         ppufile^.read_data(hs[0],1,count);
         ppufile^.read_data(hs[1],ord(hs[0]),count);
         if (flags and uf_in_library)<>0 then
          begin
            sources_avail:=false;
            temp:=' library';
          end
         else
          begin
            { check the date of the source files }
            Source_Time:=GetNamedFileTime(unit_path+hs);
            if Source_Time=-1 then
             begin
               sources_avail:=false;
               temp:=' not found';
             end
            else
             begin
               temp:=' time '+filetimestring(source_time);
               if (source_time>ppufiletime) then
                begin
                  do_compile:=true;
                  temp:=temp+' *'
                end;
             end;
          end;
         Message1(unit_t_ppu_source,unit_path+hs+temp);
{$ifdef UseBrowser}
         fsplit(unit_path+hs,_d,_n,_e);
         new(hp,init(_d,_n,_e));
         { the indexing should match what is done in writeasunit }
         sourcefiles.register_file(hp);
{$endif UseBrowser}
         ppufile^.read_data(b,1,count);
       end;
    { main source is always the last }
      stringdispose(mainsource);
      mainsource:=stringdup(ppufile^.path^+hs);

    { check the object and assembler file if not a library }
      if (flags and uf_smartlink)<>0 then
       begin
         objfiletime:=getnamedfiletime(arfilename^);
         if (ppufiletime<0) or (objfiletime<0) or (ppufiletime>objfiletime) then
           do_compile:=true;
       end
      else
       begin
         if (flags and uf_in_library)=0 then
          begin
          { the objectfile should be newer than the ppu file }
            objfiletime:=getnamedfiletime(objfilename^);
            if (ppufiletime<0) or (objfiletime<0) or (ppufiletime>objfiletime) then
             begin
             { check if assembler file is older than ppu file }
               asmfileTime:=GetNamedFileTime(asmfilename^);
               if (asmfiletime<0) or (ppufiletime>asmfiletime) then
                begin
                  Message(unit_d_obj_and_asm_are_older_than_ppu);
                  do_compile:=true;
                end
               else
                begin
                  Message(unit_d_obj_is_older_than_asm);
                  do_assemble:=true;
                end;
             end;
          end;
       end;
      load_ppu:=true;
    end;

    procedure tmodule.search_unit(const n : string);
      var
         ext       : string[8];
         singlepathstring,
         Path,
         filename  : string;
         found     : boolean;
         start,i   : longint;

         Function UnitExists(const ext:string):boolean;
         begin
           Message1(unit_t_unitsearch,Singlepathstring+filename+ext);
           UnitExists:=FileExists(Singlepathstring+FileName+ext);
         end;

       begin
         start:=1;
         filename:=FixFileName(n);
         path:=UnitSearchPath;
         Found:=false;
         repeat
         {Create current path to check}
           i:=pos(';',path);
           if i=0 then
            i:=length(path)+1;
           singlepathstring:=FixPath(copy(path,start,i-start));
           delete(path,start,i-start+1);
         { Check for PPL file }
           if not (cs_link_static in aktswitches) then
            begin
              Found:=UnitExists(target_info.unitlibext);
              if Found then
               Begin
                 SetFileName(SinglePathString,FileName);
                 Found:=Load_PPU(singlepathstring,filename,target_info.unitlibext);
               End;
             end;
         { Check for PPU file }
           if not (cs_link_dynamic in aktswitches) and not Found then
            begin
              Found:=UnitExists(target_info.unitext);
              if Found then
               Begin
                 SetFileName(SinglePathString,FileName);
                 Found:=Load_PPU(singlepathstring,filename,target_info.unitext);
               End;
            end;
         { Check for Sources }
           if not Found then
            begin
              ppufile:=nil;
              do_compile:=true;
            {Check for .pp file}
              Found:=UnitExists(target_os.sourceext);
              if Found then
               Ext:=target_os.sourceext
              else
               begin
               {Check for .pas}
                 Found:=UnitExists(target_os.pasext);
                 if Found then
                  Ext:=target_os.pasext;
               end;
              stringdispose(mainsource);
              if Found then
               begin
                 sources_avail:=true;
               {Load Filenames when found}
                 mainsource:=StringDup(SinglePathString+FileName+Ext);
                 SetFileName(SinglePathString,FileName);
               end
              else
               sources_avail:=false;
            end;
         until Found or (path='');
      end;


    constructor tmodule.init(const s:string;is_unit:boolean);
      var
        p : dirstr;
        n : namestr;
        e : extstr;
      begin
         FSplit(s,p,n,e);
         unitname:=stringdup(Upper(n));
         mainsource:=stringdup(s);
         objfilename:=nil;
         asmfilename:=nil;
         arfilename:=nil;
         ppufilename:=nil;
         setfilename(p,n);
         used_units.init;
         sourcefiles.init;
         linkofiles.init;
         linkstaticlibs.init;
         linksharedlibs.init;
         ppufile:=nil;
         current_inputfile:=nil;
         map:=nil;
         symtable:=nil;
         flags:=0;
         crc:=0;
         unitcount:=1;
         do_assemble:=false;
         do_compile:=false;
         sources_avail:=true;
         compiled:=false;
         in_implementation:=false;
         in_main:=false;
         uses_imports:=false;
         imports:=new(plinkedlist,init);
         output_format:=commandline_output_format;
       { set smartlink flag }
         if smartlink then
          flags:=flags or uf_smartlink;
       { search the PPU file if it is an unit }
         if is_unit then
          search_unit(unitname^);
      end;

    destructor tmodule.special_done;

      begin
         if assigned(map) then
           dispose(map);
         { cannot remove that because it is linked
         in the global chain of used_objects
         used_units.done; }
         sourcefiles.done;
         linkofiles.done;
         linkstaticlibs.done;
         linksharedlibs.done;
         if assigned(ppufile) then
          dispose(ppufile,done);
         if assigned(imports) then
          dispose(imports,done);
         inherited done;
      end;

{****************************************************************************
                              TUSED_UNIT
 ****************************************************************************}


    constructor tused_unit.init(_u : pmodule;f : byte);

      begin
         u:=_u;
         in_interface:=false;
         in_uses:=false;
         is_stab_written:=false;
         unitid:=f;
      end;

    destructor tused_unit.done;
      begin
         inherited done;
      end;

end.
{
  $Log$
  Revision 1.8  1998-05-04 17:54:25  peter
    + smartlinking works (only case jumptable left todo)
    * redesign of systems.pas to support assemblers and linkers
    + Unitname is now also in the PPU-file, increased version to 14

  Revision 1.7  1998/05/01 16:38:44  florian
    * handling of private and protected fixed
    + change_keywords_to_tp implemented to remove
      keywords which aren't supported by tp
    * break and continue are now symbols of the system unit
    + widestring, longstring and ansistring type released

  Revision 1.6  1998/05/01 07:43:53  florian
    + basics for rtti implemented
    + switch $m (generate rtti for published sections)

  Revision 1.5  1998/04/30 15:59:40  pierre
    * GDB works again better :
      correct type info in one pass
    + UseTokenInfo for better source position
    * fixed one remaining bug in scanner for line counts
    * several little fixes

  Revision 1.4  1998/04/29 10:33:52  pierre
    + added some code for ansistring (not complete nor working yet)
    * corrected operator overloading
    * corrected nasm output
    + started inline procedures
    + added starstarn : use ** for exponentiation (^ gave problems)
    + started UseTokenInfo cond to get accurate positions

  Revision 1.3  1998/04/27 23:10:28  peter
    + new scanner
    * $makelib -> if smartlink
    * small filename fixes pmodule.setfilename
    * moved import from files.pas -> import.pas

  Revision 1.2  1998/04/21 10:16:47  peter
    * patches from strasbourg
    * objects is not used anymore in the fpc compiled version
}
