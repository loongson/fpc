{
    $Id$
    Copyright (c) 1998 by Peter Vreman

    This unit handles the default verbose routines

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
unit verb_def;
interface
uses verbose;

{$define allow_oldstyle}

procedure SetRedirectFile(const fn:string);

procedure _stop;
procedure _comment(Level:Longint;const s:string);
{$ifdef allow_oldstyle}
function _warning(w : tmsgconst) : boolean;
function _note(w : tmsgconst) : boolean;
function _error(w : tmsgconst) : boolean;
function _fatalerror(w : tmsgconst) : boolean;
function _internalerror(i : longint) : boolean;
{$endif}

implementation
uses
  strings,dos,cobjects,systems,globals,files;

const
  { RHIDE expect gcc like error output }
  rh_errorstr='error: ';
  rh_warningstr='warning: ';
  fatalstr='Fatal Error: ';
  errorstr='Error: ';
  warningstr='Warning: ';
  notestr='Note: ';
  hintstr='Hint: ';

var
  redirexitsave : pointer;
  redirtext : boolean;
  redirfile : text;

{****************************************************************************
                       Extra Handlers for default compiler
****************************************************************************}

procedure DoneRedirectFile;{$ifndef FPC}far;{$ENDIF}
begin
  exitproc:=redirexitsave;
  if redirtext then
   close(redirfile);
end;


procedure SetRedirectFile(const fn:string);
begin
  assign(redirfile,fn);
  {$I-}
   rewrite(redirfile);
  {$I+}
  redirtext:=(ioresult=0);
  if redirtext then
   begin
     redirexitsave:=exitproc;
     exitproc:=@DoneRedirectFile;
   end;
end;


{****************************************************************************
                         Predefined default Handlers
****************************************************************************}


{ predefined handler to stop the compiler }
procedure _stop;
begin
  halt(1);
end;


Procedure _comment(Level:Longint;const s:string);
var
  hs : string;
begin
  if (verbosity and Level)=Level then
   begin
   {Create hs}
     hs:='';
     if not(use_rhide) then
       begin
          if (verbosity and Level)=V_Hint then
           hs:=hintstr;
          if (verbosity and Level)=V_Note then
           hs:=notestr;
          if (verbosity and Level)=V_Warning then
           hs:=warningstr;
          if (verbosity and Level)=V_Error then
           hs:=errorstr;
          if (verbosity and Level)=V_Fatal then
           hs:=fatalstr;
       end
     else
       begin
          if (verbosity and Level)=V_Hint then
           hs:=rh_warningstr;
          if (verbosity and Level)=V_Note then
           hs:=rh_warningstr;
          if (verbosity and Level)=V_Warning then
           hs:=rh_warningstr;
          if (verbosity and Level)=V_Error then
           hs:=rh_errorstr;
          if (verbosity and Level)=V_Fatal then
           hs:=rh_errorstr;
       end;
     if (Level<$100) and Assigned(current_module) and Assigned(current_module^.current_inputfile) then
       hs:=current_module^.current_inputfile^.get_file_line+' '+hs;
   { add the message to the text }

     hs:=hs+s;

{$ifdef FPC}
     if UseStdErr and (Level<$100) then
      begin
        writeln(stderr,hs);
        flush(stderr);
      end
     else
{$ENDIF}
      begin
        if redirtext then
         writeln(redirfile,hs)
        else
         writeln(hs);
      end;
   end;
end;


function _internalerror(i : longint) : boolean;
begin
  comment(V_Fatal,'Internal error '+tostr(i));
  _internalerror:=true;
end;

{****************************************************************************
                                 Old Style
****************************************************************************}


{$ifdef allow_oldstyle}

procedure ShowExtError(l:longint;w:tmsgconst);
var
  s : string;
begin
{fix the string to be written }
  s:=msg^.get(ord(w));
  if assigned(exterror) then
   begin
     s:=s+strpas(exterror);
     strdispose(exterror);
     exterror:=nil;
   end;
  _comment(l,s);
end;


{ predefined handler for warnings }
function _warning(w : tmsgconst) : boolean;
begin
  ShowExtError(V_Warning,w);
  _warning:=false;
end;


function _note(w : tmsgconst) : boolean;
begin
  ShowExtError(V_Note,w);
  _note:=false;
end;


function _error(w : tmsgconst) : boolean;
begin
  ShowExtError(V_Error,w);
  _error:=(errorcount>50);
end;


function _fatalerror(w : tmsgconst) : boolean;
begin
  ShowExtError(V_Error,w);
  _fatalerror:=true;
end;

{$endif}

begin
(* {$ifdef USE_RHIDE}
  UseStdErr:=true;
{$endif USE_RHIDE} *)
{$ifdef FPC}
  do_stop:=@_stop;
  do_comment:=@_comment;
  {$ifdef allow_oldstyle}
     do_note:=@_note;
     do_warning:=@_warning;
     do_error:=@_error;
     do_fatalerror:=@_fatalerror;
     do_internalerror:=@_internalerror;
  {$endif}
{$else}
  do_stop:=_stop;
  do_comment:=_comment;
  {$ifdef allow_oldstyle}
     do_note:=_note;
     do_warning:=_warning;
     do_error:=_error;
     do_fatalerror:=_fatalerror;
     do_internalerror:=_internalerror;
  {$endif}
{$endif}
end.
{
  $Log$
  Revision 1.6  1998-05-11 13:07:58  peter
    + $ifdef NEWPPU for the new ppuformat
    + $define GDB not longer required
    * removed all warnings and stripped some log comments
    * no findfirst/findnext anymore to remove smartlink *.o files

  Revision 1.5  1998/04/30 15:59:43  pierre
    * GDB works again better :
      correct type info in one pass
    + UseTokenInfo for better source position
    * fixed one remaining bug in scanner for line counts
    * several little fixes

  Revision 1.4  1998/04/29 10:34:09  pierre
    + added some code for ansistring (not complete nor working yet)
    * corrected operator overloading
    * corrected nasm output
    + started inline procedures
    + added starstarn : use ** for exponentiation (^ gave problems)
    + started UseTokenInfo cond to get accurate positions
}
