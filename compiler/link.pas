{
    $Id$
    Copyright (c) 1998 by the FPC development team

    This unit handles the linker and binder calls for programs and
    libraries

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
Unit link;

Interface

uses cobjects,files;

Type
    TLinker = Object
       LinkToC,                           { Should we link to the C libs? }
       Strip             : Boolean;       { Strip symbols ? }
       ObjectFiles,
       SharedLibFiles,
       StaticLibFiles    : TStringContainer;
       LibrarySearchPath,                 { Search path for libraries }
       LinkOptions       : string;        { Additional options to the linker }
       DynamicLinker     : String[80];    { What Dynamic linker ? }
       LinkResName       : String[32];    { Name of response file }
     { Methods }
       Constructor Init;
       Destructor Done;
       procedure AddModuleFiles(hp:pmodule);
       function  FindObjectFile(s : string) : string;
       function  FindLibraryFile(s:string;const ext:string) : string;
       Procedure AddObject(const S : String);
       Procedure AddStaticLibrary(const S : String);
       Procedure AddSharedLibrary(const S : String);
       Function  FindLinker:String;      { Find linker, sets Name }
       Function  DoExec(const command,para:string;info,useshell:boolean):boolean;
       Function  WriteResponseFile:Boolean;
       Function  MakeExecutable:boolean;
       Procedure MakeStaticLibrary(const path:string;filescnt:longint);
       Procedure MakeSharedLibrary;
     end;
     PLinker=^TLinker;

Var
  Linker : TLinker;


Implementation

uses
  Script,globals,systems,verbose
{$ifdef linux}
  ,linux
{$endif}
  ,dos;

{$ifndef linux}
Procedure Shell(command:string);
{ This is already defined in the linux.ppu for linux, need for the *
  expansion under linux }
var
  comspec : string;
begin
  comspec:=getenv('COMSPEC');
  Exec(comspec,' /C '+command);
end;
{$endif}



Constructor TLinker.Init;
begin
  ObjectFiles.Init;
  SharedLibFiles.Init;
  StaticLibFiles.Init;
  ObjectFiles.Doubles:=False;
  SharedLibFiles.Doubles:=False;
  StaticLibFiles.Doubles:=False;
  LinkToC:=False;
  Strip:=false;
  LinkOptions:='';
{$ifdef linux}
  { first try glibc2 }
  DynamicLinker:='/lib/ld-linux.so.2';
  if not FileExists(DynamicLinker) then
   DynamicLinker:='/lib/ld-linux.so.1';
  LibrarySearchPath:='/lib;/usr/lib';
{$else}
  DynamicLinker:='';
  LibrarySearchPath:='';
{$endif}
  LinkResName:='link.res';
end;


Destructor TLinker.Done;
begin
end;


procedure TLinker.AddModuleFiles(hp:pmodule);
begin
  with hp^ do
   begin
     while not linkofiles.empty do
      AddObject(linkofiles.Get);
     while not linksharedlibs.empty do
      AddSharedLibrary(linksharedlibs.Get);
     while not linkstaticlibs.empty do
      AddStaticLibrary(linkstaticlibs.Get);
   end;
end;


var
  LastLDBin : string;
Function TLinker.FindLinker:string;
var
  ldfound : boolean;
begin
  if LastLDBin='' then
   begin
     LastLDBin:=FindExe(target_link.linkbin,ldfound);
     if (not ldfound) and not(cs_link_extern in aktglobalswitches) then
      begin
        Message1(exec_w_linker_not_found,LastLDBin);
        aktglobalswitches:=aktglobalswitches+[cs_link_extern];
      end;
     if ldfound then
      Message1(exec_u_using_linker,LastLDBin);
   end;
  FindLinker:=LastLDBin;
end;


{ searches an object file }
function TLinker.FindObjectFile(s:string) : string;
var
  found : boolean;
begin
  if pos('.',s)=0 then
   s:=s+target_info.objext;
  s:=FixFileName(s);
  if FileExists(s) then
   begin
     Findobjectfile:=s;
     exit;
   end;
  findobjectfile:=search(s,'.;'+unitsearchpath+';'+exepath,found)+s;
  if not(cs_link_extern in aktglobalswitches) and (not found) then
   Message1(exec_w_objfile_not_found,s);
end;


{ searches an library file }
function TLinker.FindLibraryFile(s:string;const ext:string) : string;
var
  found : boolean;
begin
  if pos('.',s)=0 then
   s:=s+ext;
  if FileExists(s) then
   begin
     FindLibraryFile:=s;
     exit;
   end;
  findlibraryfile:=search(s,'.;'+librarysearchpath+';'+exepath,found)+s;
  if not(cs_link_extern in aktglobalswitches) and (not found) then
   Message1(exec_w_libfile_not_found,s);
end;


Procedure TLinker.AddObject(const S : String);
begin
  ObjectFiles.Insert(FindObjectFile(s));
end;


Procedure TLinker.AddSharedLibrary(const S:String);
begin
  SharedLibFiles.Insert (S);
end;


Procedure TLinker.AddStaticLibrary(const S:String);
begin
  StaticLibFiles.Insert(FindLibraryFile(s,target_os.staticlibext));
end;


Function TLinker.DoExec(const command,para:string;info,useshell:boolean):boolean;
begin
  DoExec:=true;
  if not(cs_link_extern in aktglobalswitches) then
   begin
     swapvectors;
     if useshell then
      shell(command+' '+para)
     else
      exec(command,para);
     swapvectors;
     if (dosexitcode<>0) then
      begin
        Message(exec_w_error_while_linking);
        aktglobalswitches:=aktglobalswitches+[cs_link_extern];
        DoExec:=false;
      end
     else
      if (dosError<>0) then
       begin
         Message(exec_w_cant_call_linker);
         aktglobalswitches:=aktglobalswitches+[cs_link_extern];
         DoExec:=false;
       end;
   end;
{ Update asmres when externmode is set }
  if cs_link_extern in aktglobalswitches then
   begin
     if info then
      AsmRes.AddLinkCommand(Command,Para,current_module^.libfilename^)
     else
      AsmRes.AddLinkCommand(Command,Para,'');
   end;
end;


Function TLinker.WriteResponseFile : Boolean;
Var
  LinkResponse : Text;
  i            : longint;
  prtobj,s,s2  : string;
  found,
  linklibc     : boolean;

  procedure WriteRes(const s:string);
  begin
    if s<>'' then
     WriteLn(Linkresponse,s);
  end;

begin
  WriteResponseFile:=False;
{ set special options for some targets }
  linklibc:=SharedLibFiles.Find('c');
  prtobj:='prt0';
  case target_info.target of
{$ifdef i386}
   target_Win32 : prtobj:='';
   target_linux : begin
                    if cs_profile in aktmoduleswitches then
                     begin
                       prtobj:='gprt0';
                       AddSharedLibrary('gmon');
                       AddSharedLibrary('c');
                       linklibc:=true;
                     end
                    else
                     begin
                       if linklibc then
                        prtobj:='cprt0';
                     end;
                  end;
{$endif i386}
{$ifdef m68k}
   target_linux : begin
                    if cs_profile in aktmoduleswitches then
                     begin
                       prtobj:='gprt0';
                       AddSharedLibrary('gmon');
                       AddSharedLibrary('c');
                     end;
                  end;
{$endif}
  end;

{ Fix command line options }
  If not SharedLibFiles.Empty then
   LinkOptions:='-dynamic-linker='+DynamicLinker+' '+LinkOptions;
  if Strip then
   LinkOptions:=LinkOptions+target_link.stripopt;

{ Open linkresponse and write header }
  assign(linkresponse,inputdir+LinkResName);
  {$I-}
   rewrite(linkresponse);
  {$I+}
  if ioresult<>0 then
   exit;

  { Write library searchpath }
  S2:=LibrarySearchPath;
  Repeat
    i:=Pos(';',S2);
    If i=0 then
     i:=255;
    S:=Copy(S2,1,i-1);
    If S<>'' then
      WriteRes(target_link.libpathprefix+s+target_link.libpathsuffix);
    Delete (S2,1,i);
  until S2='';

  WriteRes(target_link.inputstart);
  { add objectfiles, start with prt0 always }
  if prtobj<>'' then
   WriteRes(FindObjectFile(prtobj));
  if linklibc then
   begin
     s2:=search('crti.o',librarysearchpath,found);
     if s2<>'' then
      begin
        WriteRes(s2+'crti.o');
        WriteRes(s2+'crtbegin.o');
      end;
   end;

  while not ObjectFiles.Empty do
   begin
     s:=ObjectFiles.Get;
     if s<>'' then
      WriteRes(s);
   end;
  if linklibc then
   begin
     if s2<>'' then
      begin
        WriteRes(s2+'crtend.o');
        WriteRes(s2+'crtn.o');
      end;
   end;

  { Write sharedlibraries like -l<lib> }
  While not SharedLibFiles.Empty do
   begin
     S:=SharedLibFiles.Get;
     i:=Pos(target_os.sharedlibext,S);
     if i>0 then
      Delete(S,i,255);
     WriteRes(target_link.libprefix+s);
   end;
  WriteRes(target_link.inputend);

  { Write staticlibraries }
  if not StaticLibFiles.Empty then
   begin
     WriteRes(target_link.GroupStart);
     While not StaticLibFiles.Empty do
      begin
        S:=StaticLibFiles.Get;
        WriteRes(s)
      end;
     WriteRes(target_link.GroupEnd);
   end;

{ Close response }
  close(linkresponse);
  WriteResponseFile:=True;
end;


function TLinker.MakeExecutable:boolean;
var
  bindbin    : string[80];
  bindfound  : boolean;
  i          : longint;
  s          : string;
  dummy      : file;
  success    : boolean;
begin
{$ifdef linux}
  if LinkToC then
   begin
     AddObject('/usr/lib/crt0.o');
     AddObject('lprt');
     AddStaticLibrary('libc.a');
     AddStaticLibrary('libgcc.a');
   end;
{$endif Linux}

{ Write used files and libraries }
  WriteResponseFile;

{ Call linker }
  if not(cs_link_extern in aktglobalswitches) then
   Message1(exec_i_linking,current_module^.exefilename^);
  s:=target_link.linkcmd;
  Replace(s,'$EXE',current_module^.exefilename^);
  Replace(s,'$OPT',LinkOptions);
  Replace(s,'$RES',inputdir+LinkResName);
  success:=DoExec(FindLinker,s,true,false);
{Bind}
  if target_link.bindbin<>'' then
   begin
     s:=target_link.bindcmd;
     Replace(s,'$EXE',current_module^.exefilename^);
     Replace(s,'$HEAPKB',tostr((heapsize+1023) shr 10));
     Replace(s,'$STACKKB',tostr((stacksize+1023) shr 10));
     bindbin:=FindExe(target_link.bindbin,bindfound);
     if (not bindfound) and not(cs_link_extern in aktglobalswitches) then
      begin
        Message1(exec_w_binder_not_found,bindbin);
        aktglobalswitches:=aktglobalswitches+[cs_link_extern];
      end;
     DoExec(bindbin,s,false,false);
   end;
{Remove ReponseFile}
  if (success) and not(cs_link_extern in aktglobalswitches) then
   begin
     assign(dummy,LinkResName);
     {$I-}
      erase(dummy);
     {$I+}
     i:=ioresult;
   end;
  MakeExecutable:=success;   { otherwise a recursive call to link method }
end;


Procedure TLinker.MakeStaticLibrary(const path:string;filescnt:longint);
var
  s,
  arbin   : string;
  arfound : boolean;
  cnt     : longint;
  i       : word;
  f       : file;
begin
  arbin:=FindExe(target_ar.arbin,arfound);
  if (not arfound) and not(cs_link_extern in aktglobalswitches) then
   begin
     Message(exec_w_ar_not_found);
     aktglobalswitches:=aktglobalswitches+[cs_link_extern];
   end;
  s:=target_ar.arcmd;
  Replace(s,'$LIB',current_module^.libfilename^);
  Replace(s,'$FILES',FixPath(path)+current_module^.asmprefix^+'*'+target_info.objext);
  DoExec(arbin,s,false,true);
{ Clean up }
  if not(cs_asm_leave in aktglobalswitches) and not(cs_link_extern in aktglobalswitches) then
   begin
     for cnt:=1to filescnt do
      begin
        assign(f,FixPath(path)+current_module^.asmprefix^+tostr(cnt)+target_info.objext);
        {$I-}
         erase(f);
        {$I+}
        i:=ioresult;
      end;
     {$I-}
      rmdir(path);
     {$I+}
     i:=ioresult;
   end;
end;


Procedure TLinker.MakeSharedLibrary;
begin
  DoExec(FindLinker,' -shared -o '+current_module^.libfilename^+' link.res',false,false);
end;


end.
{
  $Log$
  Revision 1.18  1998-08-14 21:56:34  peter
    * setting the outputfile using -o works now to create static libs

  Revision 1.17  1998/08/14 18:16:08  peter
    * return after a failed call will now add it to ppas

  Revision 1.16  1998/08/12 19:28:15  peter
    * better libc support

  Revision 1.15  1998/08/10 14:50:02  peter
    + localswitches, moduleswitches, globalswitches splitting

  Revision 1.14  1998/06/17 14:10:13  peter
    * small os2 fixes
    * fixed interdependent units with newppu (remake3 under linux works now)

  Revision 1.13  1998/06/08 22:59:46  peter
    * smartlinking works for win32
    * some defines to exclude some compiler parts

  Revision 1.12  1998/06/04 23:51:44  peter
    * m68k compiles
    + .def file creation moved to gendef.pas so it could also be used
      for win32

  Revision 1.11  1998/05/27 00:20:31  peter
    * some scanner optimizes
    * automaticly aout2exe for go32v1
    * fixed dynamiclinker option which was added at the wrong place

  Revision 1.10  1998/05/22 12:32:47  peter
    * fixed -L on the commandline, Dos commandline is only 128 bytes

  Revision 1.9  1998/05/12 10:46:59  peter
    * moved printstatus to verb_def
    + V_Normal which is between V_Error and V_Warning and doesn't have a
      prefix like error: warning: and is included in V_Default
    * fixed some messages
    * first time parameter scan is only for -v and -T
    - removed old style messages

  Revision 1.8  1998/05/11 13:07:54  peter
    + $ifdef NEWPPU for the new ppuformat
    + $define GDB not longer required
    * removed all warnings and stripped some log comments
    * no findfirst/findnext anymore to remove smartlink *.o files

  Revision 1.7  1998/05/08 09:21:20  michael
  * Added missing -Fl message to messages file.
  * Corrected mangling of file names when doing Linklib
  * -Fl now actually WORKS.
  * Librarysearchpath is now a field in linker object.

  Revision 1.6  1998/05/06 09:26:49  peter
    * fixed ld call with shell

  Revision 1.4  1998/05/04 17:54:25  peter
    + smartlinking works (only case jumptable left todo)
    * redesign of systems.pas to support assemblers and linkers
    + Unitname is now also in the PPU-file, increased version to 14

  Revision 1.3  1998/04/16 10:54:30  daniel
  * Fixed linking for OS/2.
}
