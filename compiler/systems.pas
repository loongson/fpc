
{
    $Id$
    Copyright (C) 1995,97 by Florian Klaempfl

    This unit contains informations about the target systems supported
    (these are not processor specific)

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
unit systems;

  interface

    type
       tendian = (endian_little,en_big_endian);

       ttargetcpu = (i386,m68k,alpha);

       tprocessors = (
       {$ifdef i386}
              Class386,ClassP5,ClassP6
       {$endif}
       {$ifdef m68k}
              MC68000,MC68020
       {$endif}
       );


       tasmmode = (
       {$ifdef i386}
              I386_ATT,I386_INTEL,I386_DIRECT
       {$endif}
       {$ifdef m68k}
              M68K_MOT
       {$endif}
       );


       ttarget = (
       {$ifdef i386}
              target_GO32V1,target_GO32V2,target_LINUX,target_OS2,target_WIN32
       {$endif i386}
       {$ifdef m68k}
              target_Amiga,target_Atari,target_Mac68k,target_Linux,target_PalmOS
       {$endif}
       );


       tasm = (
       {$ifdef i386}
              as_o,as_o_aout,as_asw,as_nasmcoff, as_nasmelf, as_nasmobj,
              as_tasm, as_masm
       {$endif}
       {$ifdef m68k}
              as_o,as_gas,as_mit,as_mot
       {$endif}
       );

       tlink = (
       {$ifdef i386}
              link_ld,link_ldgo32v1, link_ldgo32v2, link_ldw, link_ldos2
       {$endif i386}
       {$ifdef m68k}
              link_ld
       {$endif}
       );

       tar = (
       {$ifdef i386}
              ar_ar,ar_arw
       {$endif}
       {$ifdef m68k}
              ar_ar
       {$endif}
       );


       tos = (
       {$ifdef i386}
              os_GO32V1, os_GO32V2, os_Linux, os_OS2, os_WIN32
       {$endif i386}
       {$ifdef m68k}
              os_Amiga, os_Atari, os_Mac68k, os_Linux, os_PalmOS
       {$endif}
       );


       tosinfo = record
          name      : string[30];
          sharedlibext,
          staticlibext,
          sourceext,
          pasext,
          exeext,
          scriptext : string[4];
          libprefix : string[3];
          Cprefix   : string[2];
          newline   : string[2];
          endian    : tendian;
          use_function_relative_addresses : boolean;
       end;

       tasminfo = record
          id          : tasm;
          idtxt       : string[8];
          asmbin      : string[8];
          asmcmd      : string[50];
          externals   : boolean;
          labelprefix : string[2];
          comment     : string[2];
       end;

       tlinkinfo = record
          linkbin       : string[8];
          linkcmd       : string[50];
          bindbin       : string[8];
          bindcmd       : string[50];
          stripopt      : string[2];
          libpathprefix : string[12];
          libpathsuffix : string[2];
          groupstart    : string[8];
          groupend      : string[2];
          inputstart    : string[8];
          inputend      : string[2];
          libprefix     : string[2];
       end;

       tarinfo = record
          arbin   : string[8];
          arcmd   : string[50];
       end;

       ttargetinfo = record
          target      : ttarget;
          short_name  : string[8];
          unit_env    : string[12];
          system_unit : string[8];
          smartext,
          unitext,
          unitlibext,
          asmext,
          objext,
          exeext      : string[4];
          os          : tos;
          link        : tlink;
          assem       : tasm;
          ar          : tar;
          heapsize,
          stacksize   : longint;
       end;

       tasmmodeinfo=record
          id    : tasmmode;
          idtxt : string[8];
       end;

    const
{$ifdef i386}
       target_cpu = i386;
{$endif i386}
{$ifdef m68k}
       target_cpu = m68k;
{$endif m68k}

    var
       target_info : ttargetinfo;
       target_os   : tosinfo;
       target_asm  : tasminfo;
       target_link : tlinkinfo;
       target_ar   : tarinfo;
       source_os   : tosinfo;

    function set_string_target(const s : string) : boolean;
    function set_string_asm(const s : string) : boolean;
    function set_string_asmmode(const s:string;var t:tasmmode):boolean;

implementation

    const

{****************************************************************************
                                 OS Info
****************************************************************************}
       os_infos : array[tos] of tosinfo = (
{$ifdef i386}
          (
            name         : 'GO32 V1 DOS extender';
            sharedlibext : '.dll';
            staticlibext : '.a';
            sourceext    : '.pp';
            pasext       : '.pas';
            exeext       : '';      { No .exe, the linker only output a.out ! }
            scriptext    : '.bat';
            libprefix    : '';
            Cprefix      : '_';
            newline      : #13#10;
            endian       : endian_little;
            use_function_relative_addresses : true
                  ),
          (
            name         : 'GO32 V2 DOS extender';
            sharedlibext : '.dll';
            staticlibext : '.a';
            sourceext    : '.pp';
            pasext       : '.pas';
            exeext       : '.exe';
            scriptext    : '.bat';
            libprefix    : '';
            Cprefix      : '_';
            newline      : #13#10;
            endian       : endian_little;
            use_function_relative_addresses : true
          ),
          (
            name         : 'Linux-i386';
            sharedlibext : '.so';
            staticlibext : '.a';
            sourceext    : '.pp';
            pasext       : '.pas';
            exeext       : '';
            scriptext    : '.sh';
            libprefix    : 'lib';
            Cprefix      : '';
            newline      : #10;
            endian       : endian_little;
            use_function_relative_addresses : true
          ),
          (
            name         : 'OS/2 via EMX';
            sharedlibext : '.ao2';
            staticlibext : '.ao2';
            sourceext    : '.pas';
            pasext       : '.pp';
            exeext       : '.exe';
            scriptext    : '.cmd';
            libprefix    : '';
            Cprefix      : '_';
            newline      : #13#10;
            endian       : endian_little;
            use_function_relative_addresses : false
          ),
          (
            name         : 'Win32';
            sharedlibext : '.dll';
            staticlibext : '.a';
            sourceext    : '.pp';
            pasext       : '.pas';
            exeext       : '.exe';
            scriptext    : '.bat';
            libprefix    : 'lib';
            Cprefix      : '_';
            newline      : #13#10;
            endian       : endian_little;
            use_function_relative_addresses : true
          )
{$endif i386}
{$ifdef m68k}
          (
            name         : 'Commodore Amiga';
            sharedlibext : '.library';
            staticlibext : '.a';
            sourceext    : '.pp';
            pasext       : '.pas';
            exeext       : '';
            scriptext    : '';
            libprefix    : '';
            Cprefix      : '_';
            newline      : #10;
            endian       : en_big_endian;
            use_function_relative_addresses : false
          ),
          (
            name         : 'Atari ST/STE';
            sharedlibext : '.dll';
            staticlibext : '.a';
            sourceext    : '.pp';
            pasext       : '.pas';
            exeext       : '.tpp';
            scriptext    : '';
            libprefix    : '';
            Cprefix      : '_';
            newline      : #10;
            endian       : en_big_endian;
            use_function_relative_addresses : false
          ),
          (
            name         : 'Macintosh m68k';
            sharedlibext : '.dll';
            staticlibext : '.a';
            sourceext    : '.pp';
            pasext       : '.pas';
            exeext       : '.tpp';
            scriptext    : '';
            libprefix    : '';
            Cprefix      : '_';
            newline      : #13;
            endian       : en_big_endian;
            use_function_relative_addresses : false
          ),
          (
            name         : 'Linux-m68k';
            sharedlibext : '.so';
            staticlibext : '.a';
            sourceext    : '.pp';
            pasext       : '.pas';
            exeext       : '';
            scriptext    : '.sh';
            libprefix    : 'lib';
            Cprefix      : '';
            newline      : #10;
            endian       : en_big_endian;
            use_function_relative_addresses : true
          ),
          (
            name         : 'PalmOS';
            sharedlibext : '.so';
            staticlibext : '.a';
            sourceext    : '.pp';
            pasext       : '.pas';
            exeext       : '';
            scriptext    : '';
            libprefix    : '';
            Cprefix      : '_';
            newline      : #10;
            endian       : en_big_endian;
            use_function_relative_addresses : false
          )
{$endif m68k}
          );


{****************************************************************************
                             Assembler Info
****************************************************************************}

       as_infos : array[tasm] of tasminfo = (
{$ifdef i386}
          (
            id     : as_o;
            idtxt  : 'O';
            asmbin : 'as';
            asmcmd : '-D -o $OBJ $ASM';
            externals : false;
            labelprefix : '.L';
            comment : '# '
          )
          ,(
            id     : as_o_aout;
            idtxt  : 'O_AOUT';
            asmbin : 'as';
            asmcmd : '-D -o $OBJ $ASM';
            externals : false;
            labelprefix : 'L';
            comment : '# '
          )
          ,(
            id     : as_asw;
            idtxt  : 'ASW';
            asmbin : 'asw';
            asmcmd : '-D -o $OBJ $ASM';
            externals : false;
            labelprefix : '.L';
            comment : '# '
          )
          ,(
            id     : as_nasmcoff;
            idtxt  : 'NASMCOFF';
            asmbin : 'nasm';
            asmcmd : '-f coff -o $OBJ $ASM';
            externals : true;
            labelprefix : 'L';
            comment : '; '
          )
          ,(
            id     : as_nasmelf;
            idtxt  : 'NASMELF';
            asmbin : 'nasm';
            asmcmd : '-f elf -o $OBJ $ASM';
            externals : true;
            labelprefix : 'L';
            comment : '; '
          )
          ,(
            id     : as_nasmobj;
            idtxt  : 'NASMOBJ';
            asmbin : 'nasm';
            asmcmd : '-f obj -o $OBJ $ASM';
            externals : true;
            labelprefix : 'L';
            comment : '; '
          )
          ,(
            id     : as_tasm;
            idtxt  : 'TASM';
            asmbin : 'tasm';
            asmcmd : '/m2 $ASM $OBJ';
            externals : true;
            labelprefix : '.L';
            comment : '; '
          )
          ,(
            id     : as_tasm;
            idtxt  : 'MASM';
            asmbin : 'masm';
            asmcmd : '$ASM $OBJ';
            externals : true;
            labelprefix : '.L';
            comment : '; '
          )
{$endif i386}
{$ifdef m68k}
          (
            id     : as_o;
            idtxt  : 'O';
            asmbin : 'as';
            asmcmd : '-D -o $OBJ $ASM';
            externals : false;
            labelprefix : '.L';
            comment : '# '
          )
          ,(
            id     : as_gas;
            idtxt  : 'GAS';
            asmbin : 'as68k'; { Gas for the Amiga}
            asmcmd : '-D --register-prefix-optional -o $OBJ $ASM';
            externals : false;
            labelprefix : '__L';
            comment : '| '
          )
          ,(
            id     : as_mit;
            idtxt  : 'MIT';
            asmbin : '';
            asmcmd : '-o $OBJ $ASM';
            externals : false;
            labelprefix : '__L';
            comment : '| '
          )
          ,(
            id     : as_mot;
            idtxt  : 'MOT';
            asmbin : '';
            asmcmd : '-o $OBJ $ASM';
            externals : false;
            labelprefix : '__L';
            comment : '| '
          )
{$endif m68k}
          );

{****************************************************************************
                            Linker Info
****************************************************************************}
       link_infos : array[tlink] of tlinkinfo = (
{$ifdef i386}
          (
            linkbin : 'ld';
            linkcmd : '$OPT -o $EXE $RES';
            bindbin : '';
            bindcmd : '';
            stripopt   : '-s';
            libpathprefix : 'SEARCH_DIR(';
            libpathsuffix : ')';
            groupstart : 'GROUP(';
            groupend   : ')';
            inputstart : 'INPUT(';
            inputend   : ')';
            libprefix  : '-l'
          )
          ,(
            linkbin : 'ld';
            linkcmd : '-oformat coff-go32 $OPT -o $EXE @$RES';
            bindbin : 'aout2exe';
            bindcmd : '$EXE';
            stripopt   : '-s';
            libpathprefix : '-L';
            libpathsuffix : '';
            groupstart : '-(';
            groupend   : '-)';
            inputstart : '';
            inputend   : '';
            libprefix  : '-l'
          )
          ,(
            linkbin : 'ld';
            linkcmd : '-oformat coff-go32-exe $OPT -o $EXE @$RES';
            bindbin : '';
            bindcmd : '';
            stripopt   : '-s';
            libpathprefix : '-L';
            libpathsuffix : '';
            groupstart : '-(';
            groupend   : '-)';
            inputstart : '';
            inputend   : '';
            libprefix  : '-l'
          )
          ,(
            linkbin : 'ldw';
            linkcmd : '$OPT -o $EXE $RES';
            bindbin : '';
            bindcmd : '';
            stripopt   : '-s';
            libpathprefix : 'SEARCH_DIR(';
            libpathsuffix : ')';
            groupstart : 'GROUP(';
            groupend   : ')';
            inputstart : 'INPUT(';
            inputend   : ')';
            libprefix  : '-l'
          )
          ,(
            linkbin : 'ld';  { Os/2 }
            linkcmd : '-o $EXE @$RES';
            bindbin : 'emxbind';
            bindcmd : '-o $EXE.exe $EXE -k$STACKKB -aim -s$HEAPKB';
            stripopt   : '-s';
            libpathprefix : '-L';
            libpathsuffix : '';
            groupstart : '-(';
            groupend   : '-)';
            inputstart : '';
            inputend   : '';
            libprefix  : ''
          )
{$endif i386}
{$ifdef m68k}
          (
            linkbin : 'ld';
            linkcmd : '$OPT -o $EXE $RES';
            bindbin : '';
            bindcmd : '';
            stripopt   : '-s';
            libpathprefix : 'SEARCH_DIR(';
            libpathsuffix : ')';
            groupstart : 'GROUP(';
            groupend   : ')';
            inputstart : 'INPUT(';
            inputend   : ')';
            libprefix  : '-l'
          )
{$endif m68k}
          );

{****************************************************************************
                                 Ar Info
****************************************************************************}
           ar_infos : array[tar] of tarinfo = (
{$ifdef i386}
          (
            arbin : 'ar';
            arcmd : 'rs $LIB $FILES'
          ),
          (
            arbin : 'arw';
            arcmd : 'rs $LIB $FILES'
          )
{$endif i386}
{$ifdef m68k}
          (
            arbin : 'ar';
            arcmd : 'rs $LIB $FILES'
          )
{$endif m68k}
          );

{****************************************************************************
                            Targets Info
****************************************************************************}
       target_infos : array[ttarget] of ttargetinfo = (
{$ifdef i386}
          (
            target      : target_GO32V1;
            short_name  : 'GO32V1';
            unit_env    : 'GO32V1UNITS';
            system_unit : 'SYSTEM';
            smartext    : '.sl';
            unitext     : '.pp1';
            unitlibext  : '.ppl';
            asmext      : '.s1';
            objext      : '.o1';
            exeext      : ''; { The linker produces a.out }
            os          : os_GO32V1;
            link        : link_ldgo32v1;
            assem       : as_o;
            ar          : ar_ar;
            heapsize    : 2048*1024;
            stacksize   : 16384
          ),
          (
            target      : target_GO32V2;
            short_name  : 'GO32V2';
            unit_env    : 'GO32V2UNITS';
            system_unit : 'SYSTEM';
            smartext    : '.sl';
            unitext     : '.ppu';
            unitlibext  : '.ppl';
            asmext      : '.s';
            objext      : '.o';
            exeext      : '.exe';
            os          : os_GO32V2;
            link        : link_ldgo32v2;
            assem       : as_o;
            ar          : ar_ar;
            heapsize    : 2048*1024;
            stacksize   : 16384
          ),
          (
            target      : target_LINUX;
            short_name  : 'LINUX';
            unit_env    : 'LINUXUNITS';
            system_unit : 'syslinux';
            smartext    : '.sl';
            unitext     : '.ppu';
            unitlibext  : '.ppl';
            asmext      : '.s';
            objext      : '.o';
            exeext      : '';
            os          : os_Linux;
            link        : link_ld;
            assem       : as_o;
            ar          : ar_ar;
            heapsize    : 2048*1024;
            stacksize   : 8192
          ),
          (
            target      : target_OS2;
            short_name  : 'OS2';
            unit_env    : 'OS2UNITS';
            system_unit : 'SYSOS2';
            smartext    : '.sl';
            unitext     : '.ppo';
            unitlibext  : '.ppl';
            asmext      : '.so2';
            objext      : '.oo2';
            exeext      : ''; { The linker produces a.out }
            os          : os_OS2;
            link        : link_ldos2;
            assem       : as_o_aout;
            ar          : ar_ar;
            heapsize    : 256*1024;
            stacksize   : 32768
          ),
          (
            target      : target_WIN32;
            short_name  : 'WIN32';
            unit_env    : 'WIN32UNITS';
            system_unit : 'SYSWIN32';
            smartext    : '.sl';
            unitext     : '.ppw';
            unitlibext  : '.ppl';
            asmext      : '.s';
            objext      : '.o';
            exeext      : '.exe';
            os          : os_Win32;
            link        : link_ldw;
            assem       : as_asw;
            ar          : ar_arw;
            heapsize    : 8192*1024;   { Until growing heap works !! (PFV) }
            stacksize   : 32768
          )
{$endif i386}
{$ifdef m68k}
          (
            target      : target_Amiga;
            short_name  : 'AMIGA';
            unit_env    : '';
            system_unit : 'sysamiga';
            smartext    : '.sl';
            unitext     : '.ppa';
            unitlibext  : '.ppl';
            asmext      : '.asm';
            objext      : '.o';
            exeext      : '';
            os          : os_Amiga;
            link        : link_ld;
            assem       : as_o;
            ar          : ar_ar;
            heapsize    : 128*1024;
            stacksize   : 8192
          ),
          (
            target      : target_Atari;
            short_name  : 'ATARI';
            unit_env    : '';
            system_unit : 'SYSATARI';
            smartext    : '.sl';
            unitext     : '.ppt';
            unitlibext  : '.ppl';
            asmext      : '.s';
            objext      : '.o';
            exeext      : '';
            os          : os_Atari;
            link        : link_ld;
            assem       : as_o;
            ar          : ar_ar;
            heapsize    : 16*1024;
            stacksize   : 8192
          ),
          (
            target      : target_Mac68k;
            short_name  : 'MACOS';
            unit_env    : '';
            system_unit : 'sysmac';
            smartext    : '.sl';
            unitext     : '.ppt';
            unitlibext  : '.ppl';
            asmext      : '.s';
            objext      : '.o';
            exeext      : '';
            os          : os_Mac68k;
            link        : link_ld;
            assem       : as_o;
            ar          : ar_ar;
            heapsize    : 128*1024;
            stacksize   : 8192
          ),
          (
            target      : target_Linux;
            short_name  : 'LINUX';
            unit_env    : 'LINUXUNITS';
            system_unit : 'syslinux';
            smartext    : '.sl';
            unitext     : '.ppu';
            unitlibext  : '.ppl';
            asmext      : '.s';
            objext      : '.o';
            exeext      : '';
            os          : os_Linux;
            link        : link_ld;
            assem       : as_o;
            ar          : ar_ar;
            heapsize    : 128*1024;
            stacksize   : 8192
          ),
          (
            target      : target_PalmOS;
            short_name  : 'PALMOS';
            unit_env    : 'PALMUNITS';
            system_unit : 'syspalm';
            smartext    : '.sl';
            unitext     : '.ppu';
            unitlibext  : '.ppl';
            asmext      : '.s';
            objext      : '.o';
            exeext      : '';
            os          : os_PalmOS;
            link        : link_ld;
            assem       : as_o;
            ar          : ar_ar;
            heapsize    : 128*1024;
            stacksize   : 8192
          )
{$endif m68k}
          );

{****************************************************************************
                             AsmModeInfo
****************************************************************************}
       asmmodeinfos : array[tasmmode] of tasmmodeinfo = (
{$ifdef i386}
          (
            id    : I386_DIRECT;
            idtxt : 'DIRECT'
          ),
          (
            id    : I386_INTEL;
            idtxt : 'INTEL'
          ),
          (
            id    : I386_ATT;
            idtxt : 'ATT'
          )
{$endif i386}
{$ifdef m68k}
          (
            id    : M68K_MOT;
            idtxt : 'MOT'
          )
{$endif m68k}
          );

{****************************************************************************
                                Helpers
****************************************************************************}

procedure set_target(t : ttarget);
begin
  target_info:=target_infos[t];
  target_os:=os_infos[target_info.os];
  target_asm:=as_infos[target_info.assem];
  target_link:=link_infos[target_info.link];
  target_ar:=ar_infos[target_info.ar];
end;


{****************************************************************************
                             Load from string
****************************************************************************}

function set_string_target(const s : string) : boolean;
var
  i : longint;
begin
  set_string_target:=false;
  for i:=0 to (sizeof(target_infos) div sizeof(ttargetinfo))-1 do
   if target_infos[ttarget(i)].short_name=s then
    begin
      set_target(ttarget(i));
      set_string_target:=true;
    end;
end;


function set_string_asm(const s : string) : boolean;
var
  i : longint;
begin
  set_string_asm:=false;
  for i:=0 to (sizeof(as_infos) div sizeof(tasminfo))-1 do
   if as_infos[tasm(i)].idtxt=s then
    begin
      target_asm:=as_infos[tasm(i)];
      set_string_asm:=true;
    end;
end;


function set_string_asmmode(const s:string;var t:tasmmode):boolean;
var
  i : longint;
begin
  set_string_asmmode:=false;
  for i:=0 to (sizeof(asmmodeinfos) div sizeof(tasmmodeinfo))-1 do
   if asmmodeinfos[tasmmode(i)].idtxt=s then
    begin
      t:=asmmodeinfos[tasmmode(i)].id;
      set_string_asmmode:=true;
    end;
end;


{****************************************************************************
                      Initialization of default target
****************************************************************************}

procedure default_os(t:ttarget);
begin
  set_target(t);
  source_os:=os_infos[target_info.os];
end;


begin
{$ifdef i386}
  {$ifdef GO32V1}
     default_os(target_GO32V1);
  {$else}
    {$ifdef GO32V2}
      default_os(target_GO32V2);
    {$else}
      {$ifdef OS2}
        default_os(target_OS2);
      {$else}
        {$ifdef LINUX}
          default_os(target_LINUX);
        {$else}
           {$ifdef WIN32}
             default_os(target_WIN32);
           {$else}
              default_os(target_GO32V2);
           {$endif win32}
        {$endif linux}
      {$endif os2}
    {$endif go32v2}
  {$endif go32v1}
{$endif i386}
{$ifdef m68k}
  {$ifdef AMIGA}
    default_os(target_Amiga);
  {$else}
    {$ifdef ATARI}
      default_os(target_Atari);
    {$else}
      {$ifdef MACOS}
        default_os(target_MAC68k);
      {$else}
        default_os(target_Amiga);
      {$endif macos}
    {$endif atari}
  {$endif amiga}
{$endif m68k}
end.
{
  $Log$
  Revision 1.30  1998-08-31 12:26:34  peter
    * m68k and palmos updates from surebugfixes

  Revision 1.29  1998/08/26 10:09:21  peter
    * more lowercase extensions

  Revision 1.28  1998/08/25 12:42:47  pierre
    * CDECL changed to CVAR for variables
      specifications are read in structures also
    + started adding GPC compatibility mode ( option  -Sp)
    * names changed to lowercase

  Revision 1.27  1998/08/21 15:16:57  peter
    * win32 compiles a bit better, no growheap crash

  Revision 1.26  1998/08/19 16:07:55  jonas
    * changed optimizer switches + cleanup of DestroyRefs in daopt386.pas

  Revision 1.25  1998/08/18 09:24:45  pierre
    * small warning position bug fixed
    * support_mmx switches splitting was missing
    * rhide error and warning output corrected

  Revision 1.24  1998/08/17 09:17:54  peter
    * static/shared linking updates

  Revision 1.23  1998/06/25 08:48:20  florian
    * first version of rtti support

  Revision 1.22  1998/06/17 14:10:21  peter
    * small os2 fixes
    * fixed interdependent units with newppu (remake3 under linux works now)

  Revision 1.20  1998/06/15 15:38:14  pierre
    * small bug in systems.pas corrected
    + operators in different units better hanlded

  Revision 1.19  1998/06/15 13:34:24  daniel


  * Fixed spelling mistakes in comments.
  * Fixed some OS/2 parameters.

  Revision 1.18  1998/06/08 22:59:54  peter
    * smartlinking works for win32
    * some defines to exclude some compiler parts

  Revision 1.17  1998/06/04 23:52:04  peter
    * m68k compiles
    + .def file creation moved to gendef.pas so it could also be used
      for win32

  Revision 1.16  1998/06/01 16:50:22  peter
    + boolean -> ord conversion
    * fixed ord -> boolean conversion

  Revision 1.15  1998/05/30 14:31:11  peter
    + $ASMMODE

  Revision 1.14  1998/05/29 13:24:45  peter
    + asw assembler

  Revision 1.13  1998/05/27 00:20:33  peter
    * some scanner optimizes
    * automaticly aout2exe for go32v1
    * fixed dynamiclinker option which was added at the wrong place

  Revision 1.12  1998/05/23 01:21:32  peter
        + aktasmmode, aktoptprocessor, aktoutputformat
    + smartlink per module $SMARTLINK-/+ (like MMX) and moved to aktswitches
    + $LIBNAME to set the library name where the unit will be put in
    * splitted cgi386 a bit (codeseg to large for bp7)
    * nasm, tasm works again. nasm moved to ag386nsm.pas

  Revision 1.11  1998/05/22 12:32:49  peter
    * fixed -L on the commandline, Dos commandline is only 128 bytes

  Revision 1.10  1998/05/11 13:07:58  peter
    + $ifdef NEWPPU for the new ppuformat
    + $define GDB not longer required
    * removed all warnings and stripped some log comments
    * no findfirst/findnext anymore to remove smartlink *.o files

  Revision 1.9  1998/05/06 08:38:49  pierre
    * better position info with UseTokenInfo
      UseTokenInfo greatly simplified
    + added check for changed tree after first time firstpass
      (if we could remove all the cases were it happen
      we could skip all firstpass if firstpasscount > 1)
      Only with ExtDebug

  Revision 1.8  1998/05/04 20:19:54  peter
    * small fix for go32v2

  Revision 1.7  1998/05/04 17:54:29  peter
    + smartlinking works (only case jumptable left todo)
    * redesign of systems.pas to support assemblers and linkers
    + Unitname is now also in the PPU-file, increased version to 14

  Revision 1.6  1998/05/01 07:43:57  florian
    + basics for rtti implemented
    + switch $m (generate rtti for published sections)

  Revision 1.5  1998/04/29 10:34:06  pierre
    + added some code for ansistring (not complete nor working yet)
    * corrected operator overloading
    * corrected nasm output
    + started inline procedures
    + added starstarn : use ** for exponentiation (^ gave problems)
    + started UseTokenInfo cond to get accurate positions

  Revision 1.4  1998/04/27 15:45:20  peter
    + -Xl for smartlink
        + target_info.arext = .a

  Revision 1.3  1998/04/16 10:50:45  daniel
  * Fixed some things that were broken for OS/2.
}
