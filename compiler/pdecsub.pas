{
    $Id$
    Copyright (c) 1998-2000 by Florian Klaempfl, Daniel Mantione

    Does the parsing of the procedures/functions

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
unit pdecsub;

{$i defines.inc}

interface

    uses
      cobjects,tokens,symconst,symtype,symdef,symsym;

    const
      pd_global    = $1;    { directive must be global }
      pd_body      = $2;    { directive needs a body }
      pd_implemen  = $4;    { directive can be used implementation section }
      pd_interface = $8;    { directive can be used interface section }
      pd_object    = $10;   { directive can be used object declaration }
      pd_procvar   = $20;   { directive can be used procvar declaration }
      pd_notobject = $40;   { directive can not be used object declaration }

    function  is_proc_directive(tok:ttoken):boolean;
    function  check_identical_proc(var p : pprocdef) : boolean;

    procedure parameter_dec(aktprocdef:pabstractprocdef);

    procedure parse_proc_directives(Anames:Pstringcontainer;var pdflags:word);

    procedure parse_proc_head(options:tproctypeoption);
    procedure parse_proc_dec;
    procedure parse_var_proc_directives(var sym : psym);
    procedure parse_object_proc_directives(var sym : pprocsym);


implementation

    uses
{$ifdef delphi}
       sysutils,
{$else delphi}
       strings,
{$endif delphi}
       { common }
       cutils,
       { global }
       globtype,globals,verbose,
       systems,cpuinfo,
       { aasm }
       aasm,
       { symtable }
       symbase,symtable,types,
{$ifdef GDB}
       gdb,
{$endif}
       { pass 1 }
       node,pass_1,htypechk,
       nmat,nadd,ncal,nmem,nset,ncnv,ninl,ncon,nld,nflw,
       { parser }
       fmodule,scanner,
       pbase,pexpr,ptype,pdecl,
       { linking }
       import,gendef,
       { codegen }
{$ifdef newcg}
       cgbase
{$else}
       hcodegen
{$endif}
       ;


    procedure parameter_dec(aktprocdef:pabstractprocdef);
      {
        handle_procvar needs the same changes
      }
      var
        is_procvar : boolean;
        sc      : Pstringcontainer;
        s       : string;
        hpos,
        storetokenpos : tfileposinfo;
        tt      : ttype;
        hvs,
        vs      : Pvarsym;
        hs1,hs2 : string;
        varspez : Tvarspez;
        inserthigh : boolean;
        pdefaultvalue : pconstsym;
        defaultrequired : boolean;
      begin
        { reset }
        defaultrequired:=false;
        { parsing a proc or procvar ? }
        is_procvar:=(aktprocdef^.deftype=procvardef);
        consume(_LKLAMMER);
        inc(testcurobject);
        repeat
          if try_to_consume(_VAR) then
            varspez:=vs_var
          else
            if try_to_consume(_CONST) then
              varspez:=vs_const
          else
            if try_to_consume(_OUT) then
              varspez:=vs_out
          else
              varspez:=vs_value;
          inserthigh:=false;
          pdefaultvalue:=nil;
          tt.reset;
          { self is only allowed in procvars and class methods }
          if (idtoken=_SELF) and
             (is_procvar or
              (assigned(procinfo^._class) and procinfo^._class^.is_class)) then
            begin
              if not is_procvar then
               begin
{$ifndef UseNiceNames}
                 hs2:=hs2+'$'+'self';
{$else UseNiceNames}
                 hs2:=hs2+tostr(length('self'))+'self';
{$endif UseNiceNames}
                 vs:=new(Pvarsym,initdef('@',procinfo^._class));
                 vs^.varspez:=vs_var;
               { insert the sym in the parasymtable }
                 pprocdef(aktprocdef)^.parast^.insert(vs);
                 include(aktprocdef^.procoptions,po_containsself);
                 inc(procinfo^.selfpointer_offset,vs^.address);
               end;
              consume(idtoken);
              consume(_COLON);
              single_type(tt,hs1,false);
              aktprocdef^.concatpara(tt,vs_value,nil);
              { check the types for procedures only }
              if not is_procvar then
               CheckTypes(tt.def,procinfo^._class);
            end
          else
            begin
             { read identifiers }
               sc:=idlist;
{$ifdef fixLeaksOnError}
               strContStack.push(sc);
{$endif fixLeaksOnError}
             { read type declaration, force reading for value and const paras }
               if (token=_COLON) or (varspez=vs_value) then
                begin
                  consume(_COLON);
                { check for an open array }
                  if token=_ARRAY then
                   begin
                     consume(_ARRAY);
                     consume(_OF);
                   { define range and type of range }
                     tt.setdef(new(Parraydef,init(0,-1,s32bitdef)));
                   { array of const ? }
                     if (token=_CONST) and (m_objpas in aktmodeswitches) then
                      begin
                        consume(_CONST);
                        srsym:=nil;
                        getsymonlyin(systemunit,'TVARREC');
                        if not assigned(srsym) then
                         InternalError(1234124);
                        Parraydef(tt.def)^.elementtype:=ptypesym(srsym)^.restype;
                        Parraydef(tt.def)^.IsArrayOfConst:=true;
                        hs1:='array_of_const';
                      end
                     else
                      begin
                        { define field type }
                        single_type(parraydef(tt.def)^.elementtype,hs1,false);
                        hs1:='array_of_'+hs1;
                      end;
                     inserthigh:=true;
                   end
                  else
                   begin
                     { open string ? }
                     if (varspez=vs_var) and
                             (
                               (
                                 ((token=_STRING) or (idtoken=_SHORTSTRING)) and
                                 (cs_openstring in aktmoduleswitches) and
                                 not(cs_ansistrings in aktlocalswitches)
                               ) or
                             (idtoken=_OPENSTRING)) then
                      begin
                        consume(token);
                        tt.setdef(openshortstringdef);
                        hs1:='openstring';
                        inserthigh:=true;
                      end
                     else
                      begin
                        { everything else }
                        single_type(tt,hs1,false);
                      end;
                     { default parameter }
                     if (m_default_para in aktmodeswitches) then
                      begin
                        if try_to_consume(_EQUAL) then
                         begin
                           s:=sc^.get_with_tokeninfo(hpos);
                           if not sc^.empty then
                            Comment(V_Error,'default value only allowed for one parameter');
                           sc^.insert_with_tokeninfo(s,hpos);
                           { prefix 'def' to the parameter name }
                           pdefaultvalue:=ReadConstant('$def'+Upper(s),hpos);
                           if assigned(pdefaultvalue) then
                            pprocdef(aktprocdef)^.parast^.insert(pdefaultvalue);
                           defaultrequired:=true;
                         end
                        else
                         begin
                           if defaultrequired then
                            Comment(V_Error,'default parameter required');
                         end;
                      end;
                   end;
                end
               else
                begin
{$ifndef UseNiceNames}
                  hs1:='$$$';
{$else UseNiceNames}
                  hs1:='var';
{$endif UseNiceNames}
                  tt.setdef(cformaldef);
                end;
               if not is_procvar then
                hs2:=pprocdef(aktprocdef)^.mangledname;
               storetokenpos:=akttokenpos;
               while not sc^.empty do
                begin
                  s:=sc^.get_with_tokeninfo(akttokenpos);
                  aktprocdef^.concatpara(tt,varspez,pdefaultvalue);
                  { For proc vars we only need the definitions }
                  if not is_procvar then
                   begin
{$ifndef UseNiceNames}
                     hs2:=hs2+'$'+hs1;
{$else UseNiceNames}
                     hs2:=hs2+tostr(length(hs1))+hs1;
{$endif UseNiceNames}
                     vs:=new(pvarsym,init(s,tt));
                     vs^.varspez:=varspez;
                   { we have to add this to avoid var param to be in registers !!!}
                   { I don't understand the comment above,                          }
                   { but I suppose the comment is wrong and                         }
                   { it means that the address of var parameters can be placed      }
                   { in a register (FK)                                             }
                     if (varspez in [vs_var,vs_const,vs_out]) and push_addr_param(tt.def) then
                       include(vs^.varoptions,vo_regable);

                   { insert the sym in the parasymtable }
                     pprocdef(aktprocdef)^.parast^.insert(vs);

                   { do we need a local copy? Then rename the varsym, do this after the
                     insert so the dup id checking is done correctly }
                     if (varspez=vs_value) and
                        push_addr_param(tt.def) and
                        not(is_open_array(tt.def) or is_array_of_const(tt.def)) then
                       pprocdef(aktprocdef)^.parast^.rename(vs^.name,'val'+vs^.name);

                   { also need to push a high value? }
                     if inserthigh then
                      begin
                        hvs:=new(Pvarsym,initdef('$high'+Upper(s),s32bitdef));
                        hvs^.varspez:=vs_const;
                        pprocdef(aktprocdef)^.parast^.insert(hvs);
                      end;

                   end;
                end;
{$ifdef fixLeaksOnError}
               if PStringContainer(strContStack.pop) <> sc then
                  writeln('problem with strContStack in pdecl (1)');
{$endif fixLeaksOnError}
               dispose(sc,done);
               akttokenpos:=storetokenpos;
            end;
          { set the new mangled name }
          if not is_procvar then
            pprocdef(aktprocdef)^.setmangledname(hs2);
        until not try_to_consume(_SEMICOLON);
        dec(testcurobject);
        consume(_RKLAMMER);
      end;




procedure parse_proc_head(options:tproctypeoption);
var orgsp,sp:stringid;
    pd:Pprocdef;
    paramoffset:longint;
    sym:Psym;
    hs:string;
    st : psymtable;
    overloaded_level:word;
    storepos,procstartfilepos : tfileposinfo;
begin
{ Save the position where this procedure really starts and set col to 1 which
  looks nicer }
  procstartfilepos:=akttokenpos;
{  procstartfilepos.column:=1; I do not agree here !!
   lets keep excat position PM }

  if (options=potype_operator) then
    begin
      sp:=overloaded_names[optoken];
      orgsp:=sp;
    end
  else
    begin
      sp:=pattern;
      orgsp:=orgpattern;
      consume(_ID);
    end;

{ method ? }
  if not(parse_only) and
     (lexlevel=normal_function_level) and
     try_to_consume(_POINT) then
   begin
     storepos:=akttokenpos;
     akttokenpos:=procstartfilepos;
     getsym(sp,true);
     sym:=srsym;
     akttokenpos:=storepos;
     { load proc name }
     sp:=pattern;
     orgsp:=orgpattern;
     procstartfilepos:=akttokenpos;
     { qualifier is class name ? }
     if (sym^.typ<>typesym) or
        (ptypesym(sym)^.restype.def^.deftype<>objectdef) then
       begin
          Message(parser_e_class_id_expected);
          aktprocsym:=nil;
          consume(_ID);
       end
     else
       begin
          { used to allow private syms to be seen }
          aktobjectdef:=pobjectdef(ptypesym(sym)^.restype.def);
          procinfo^._class:=pobjectdef(ptypesym(sym)^.restype.def);
          aktprocsym:=pprocsym(procinfo^._class^.symtable^.search(sp));
          consume(_ID);
          {The procedure has been found. So it is
           a global one. Set the flags to mark this.}
          procinfo^.flags:=procinfo^.flags or pi_is_global;
          aktobjectdef:=nil;
          { we solve this below }
          if not(assigned(aktprocsym)) then
            Message(parser_e_methode_id_expected);
       end;
   end
  else
   begin
     { check for constructor/destructor which is not allowed here }
     if (not parse_only) and
        (options in [potype_constructor,potype_destructor]) then
        Message(parser_e_constructors_always_objects);

     akttokenpos:=procstartfilepos;
     aktprocsym:=pprocsym(symtablestack^.search(sp));

     if not(parse_only) then
       begin
         {The procedure we prepare for is in the implementation
          part of the unit we compile. It is also possible that we
          are compiling a program, which is also some kind of
          implementaion part.

          We need to find out if the procedure is global. If it is
          global, it is in the global symtable.}
         if not assigned(aktprocsym) and
            (symtablestack^.symtabletype=staticsymtable) then
          begin
            {Search the procedure in the global symtable.}
            aktprocsym:=Pprocsym(search_a_symtable(sp,globalsymtable));
            if assigned(aktprocsym) then
             begin
               {Check if it is a procedure.}
               if aktprocsym^.typ<>procsym then
                DuplicateSym(aktprocsym);
               {The procedure has been found. So it is
                a global one. Set the flags to mark this.}
               procinfo^.flags:=procinfo^.flags or pi_is_global;
             end;
          end;
       end;
   end;

{ Create the mangledname }
{$ifndef UseNiceNames}
  if assigned(procinfo^._class) then
   begin
     if (pos('_$$_',procprefix)=0) then
      hs:=procprefix+'_$$_'+procinfo^._class^.objname^+'_$$_'+sp
     else
      hs:=procprefix+'_$'+sp;
   end
  else
   begin
     if lexlevel=normal_function_level then
      hs:=procprefix+'_'+sp
     else
      hs:=procprefix+'_$'+sp;
   end;
{$else UseNiceNames}
  if assigned(procinfo^._class) then
   begin
     if (pos('_5Class_',procprefix)=0) then
      hs:=procprefix+'_5Class_'+procinfo^._class^.name^+'_'+tostr(length(sp))+sp
     else
      hs:=procprefix+'_'+tostr(length(sp))+sp;
   end
  else
   begin
     if lexlevel=normal_function_level then
      hs:=procprefix+'_'+tostr(length(sp))+sp
     else
      hs:=lowercase(procprefix)+'_'+tostr(length(sp))+sp;
   end;
{$endif UseNiceNames}

  if assigned(aktprocsym) then
   begin
     { Check if overloaded is a procsym, we use a different error message
       for tp7 so it looks more compatible }
     if aktprocsym^.typ<>procsym then
      begin
        if (m_fpc in aktmodeswitches) then
         Message1(parser_e_overloaded_no_procedure,aktprocsym^.realname)
        else
         DuplicateSym(aktprocsym);
        { try to recover by creating a new aktprocsym }
        akttokenpos:=procstartfilepos;
        aktprocsym:=new(pprocsym,init(orgsp));
      end;
   end
  else
   begin
     { create a new procsym and set the real filepos }
     akttokenpos:=procstartfilepos;
     { for operator we have only one definition for each overloaded
       operation }
     if (options=potype_operator) then
       begin
          { create the procsym with saving the original case }
          aktprocsym:=new(pprocsym,init('$'+sp));
          { the only problem is that nextoverloaded might not be in a unit
            known for the unit itself }
          { not anymore PM }
          if assigned(overloaded_operators[optoken]) then
            aktprocsym^.definition:=overloaded_operators[optoken]^.definition;
{$ifndef DONOTCHAINOPERATORS}
          overloaded_operators[optoken]:=aktprocsym;
{$endif DONOTCHAINOPERATORS}
       end
      else
       aktprocsym:=new(pprocsym,init(orgsp));
     symtablestack^.insert(aktprocsym);
   end;

  st:=symtablestack;
  pd:=new(pprocdef,init);
  pd^.symtablelevel:=symtablestack^.symtablelevel;

  if assigned(procinfo^._class) then
    pd^._class := procinfo^._class;

  { set the options from the caller (podestructor or poconstructor) }
  pd^.proctypeoption:=options;

  { calculate the offset of the parameters }
  paramoffset:=8;

  { calculate frame pointer offset }
  if lexlevel>normal_function_level then
    begin
      procinfo^.framepointer_offset:=paramoffset;
      inc(paramoffset,target_os.size_of_pointer);
      { this is needed to get correct framepointer push for local
        forward functions !! }
      pd^.parast^.symtablelevel:=lexlevel;
    end;

  if assigned (procinfo^._Class)  and
     not(procinfo^._Class^.is_class) and
     (pd^.proctypeoption in [potype_constructor,potype_destructor]) then
    inc(paramoffset,target_os.size_of_pointer);

  { self pointer offset                       }
  { self isn't pushed in nested procedure of methods }
  if assigned(procinfo^._class) and (lexlevel=normal_function_level) then
    begin
      procinfo^.selfpointer_offset:=paramoffset;
      if assigned(aktprocsym^.definition) and
         not(po_containsself in aktprocsym^.definition^.procoptions) then
        inc(paramoffset,target_os.size_of_pointer);
    end;

  { con/-destructor flag ? }
  if assigned (procinfo^._Class) and
     procinfo^._class^.is_class and
     (pd^.proctypeoption in [potype_destructor,potype_constructor]) then
    inc(paramoffset,target_os.size_of_pointer);

  procinfo^.para_offset:=paramoffset;

  pd^.parast^.datasize:=0;

  pd^.nextoverloaded:=aktprocsym^.definition;
  aktprocsym^.definition:=pd;
  { this is probably obsolete now PM }
  aktprocsym^.definition^.fileinfo:=procstartfilepos;
  aktprocsym^.definition^.setmangledname(hs);
  aktprocsym^.definition^.procsym:=aktprocsym;

  if not parse_only then
    begin
       overloaded_level:=0;
       { we need another procprefix !!! }
       { count, but only those in the same unit !!}
       while assigned(pd) and
          (pd^.owner^.symtabletype in [globalsymtable,staticsymtable]) do
         begin
            { only count already implemented functions }
            if  not(pd^.forwarddef) then
              inc(overloaded_level);
            pd:=pd^.nextoverloaded;
         end;
       if overloaded_level>0 then
         procprefix:=hs+'$'+tostr(overloaded_level)+'$'
       else
         procprefix:=hs+'$';
    end;

  { this must also be inserted in the right symtable !! PM }
  { otherwise we get subbtle problems with
    definitions of args defs in staticsymtable for
    implementation of a global method }
  if token=_LKLAMMER then
    parameter_dec(aktprocsym^.definition);

  { so we only restore the symtable now }
  symtablestack:=st;
  if (options=potype_operator) then
    overloaded_operators[optoken]:=aktprocsym;
end;


procedure parse_proc_dec;
var
  hs : string;
  isclassmethod : boolean;
begin
  inc(lexlevel);
{ read class method }
  if token=_CLASS then
   begin
     consume(_CLASS);
     isclassmethod:=true;
   end
  else
   isclassmethod:=false;
  case token of
     _FUNCTION : begin
                   consume(_FUNCTION);
                   parse_proc_head(potype_none);
                   if token<>_COLON then
                    begin
                       if not(aktprocsym^.definition^.forwarddef) or
                         (m_repeat_forward in aktmodeswitches) then
                       begin
                         consume(_COLON);
                         consume_all_until(_SEMICOLON);
                       end;
                    end
                   else
                    begin
                      consume(_COLON);
                      inc(testcurobject);
                      single_type(aktprocsym^.definition^.rettype,hs,false);
                      aktprocsym^.definition^.test_if_fpu_result;
                      dec(testcurobject);
                    end;
                 end;
    _PROCEDURE : begin
                   consume(_PROCEDURE);
                   parse_proc_head(potype_none);
                   aktprocsym^.definition^.rettype.def:=voiddef;
                 end;
  _CONSTRUCTOR : begin
                   consume(_CONSTRUCTOR);
                   parse_proc_head(potype_constructor);
                   if assigned(procinfo^._class) and
                      procinfo^._class^.is_class then
                    begin
                      { CLASS constructors return the created instance }
                      aktprocsym^.definition^.rettype.def:=procinfo^._class;
                    end
                   else
                    begin
                      { OBJECT constructors return a boolean }
{$IfDef GDB}
                      { GDB doesn't like unnamed types !}
                      aktprocsym^.definition^.rettype.def:=globaldef('boolean');
{$else GDB}
                      aktprocsym^.definition^.rettype.def:=new(porddef,init(bool8bit,0,1));
{$Endif GDB}
                    end;
                 end;
   _DESTRUCTOR : begin
                   consume(_DESTRUCTOR);
                   parse_proc_head(potype_destructor);
                   aktprocsym^.definition^.rettype.def:=voiddef;
                 end;
     _OPERATOR : begin
                   if lexlevel>normal_function_level then
                     Message(parser_e_no_local_operator);
                   consume(_OPERATOR);
                   if not(token in [_PLUS..last_overloaded]) then
                     Message(parser_e_overload_operator_failed);
                   optoken:=token;
                   consume(Token);
                   procinfo^.flags:=procinfo^.flags or pi_operator;
                   parse_proc_head(potype_operator);
                   if token<>_ID then
                     begin
                        opsym:=nil;
                        if not(m_result in aktmodeswitches) then
                          consume(_ID);
                     end
                   else
                     begin
                       opsym:=new(pvarsym,initdef(pattern,voiddef));
                       consume(_ID);
                     end;
                   if not try_to_consume(_COLON) then
                     begin
                       consume(_COLON);
                       aktprocsym^.definition^.rettype.def:=generrordef;
                       consume_all_until(_SEMICOLON);
                     end
                   else
                    begin
                      single_type(aktprocsym^.definition^.rettype,hs,false);
                      aktprocsym^.definition^.test_if_fpu_result;
                      if (optoken in [_EQUAL,_GT,_LT,_GTE,_LTE]) and
                         ((aktprocsym^.definition^.rettype.def^.deftype<>
                         orddef) or (porddef(aktprocsym^.definition^.
                         rettype.def)^.typ<>bool8bit)) then
                        Message(parser_e_comparative_operator_return_boolean);
                       if assigned(opsym) then
                         opsym^.vartype.def:=aktprocsym^.definition^.rettype.def;
                       { We need to add the return type in the mangledname
                         to allow overloading with just different results !! (PM) }
                       aktprocsym^.definition^.setmangledname(
                         aktprocsym^.definition^.mangledname+'$$'+hs);
                       if (optoken=_ASSIGNMENT) and
                          is_equal(aktprocsym^.definition^.rettype.def,
                             pvarsym(aktprocsym^.definition^.parast^.symindex^.first)^.vartype.def) then
                         message(parser_e_no_such_assignment)
                       else if not isoperatoracceptable(aktprocsym^.definition,optoken) then
                         Message(parser_e_overload_impossible);
                     end;
                 end;
  end;
  if isclassmethod and
     assigned(aktprocsym) then
    include(aktprocsym^.definition^.procoptions,po_classmethod);
  { support procedure proc;stdcall export; in Delphi mode only }
  if not((m_delphi in aktmodeswitches) and
     is_proc_directive(token)) then
   consume(_SEMICOLON);
  dec(lexlevel);
end;


{****************************************************************************
                        Procedure directive handlers
****************************************************************************}

procedure pd_far(const procnames:Tstringcontainer);
begin
  Message(parser_w_proc_far_ignored);
end;

procedure pd_near(const procnames:Tstringcontainer);
begin
  Message(parser_w_proc_near_ignored);
end;

procedure pd_export(const procnames:Tstringcontainer);
begin
  if assigned(procinfo^._class) then
    Message(parser_e_methods_dont_be_export);
  if lexlevel<>normal_function_level then
    Message(parser_e_dont_nest_export);
  { only os/2 needs this }
  if target_info.target=target_i386_os2 then
   begin
     procnames.insert(aktprocsym^.realname);
     procinfo^.exported:=true;
     if cs_link_deffile in aktglobalswitches then
       deffile.AddExport(aktprocsym^.definition^.mangledname);
   end;
end;

procedure pd_inline(const procnames:Tstringcontainer);
begin
  if not(cs_support_inline in aktmoduleswitches) then
   Message(parser_e_proc_inline_not_supported);
end;

procedure pd_forward(const procnames:Tstringcontainer);
begin
  aktprocsym^.definition^.forwarddef:=true;
end;

procedure pd_stdcall(const procnames:Tstringcontainer);
begin
end;

procedure pd_safecall(const procnames:Tstringcontainer);
begin
end;

procedure pd_alias(const procnames:Tstringcontainer);
begin
  consume(_COLON);
  procnames.insert(get_stringconst);
end;

procedure pd_asmname(const procnames:Tstringcontainer);
begin
  aktprocsym^.definition^.setmangledname(target_os.Cprefix+pattern);
  if token=_CCHAR then
    consume(_CCHAR)
  else
    consume(_CSTRING);
  { we don't need anything else }
  aktprocsym^.definition^.forwarddef:=false;
end;

procedure pd_intern(const procnames:Tstringcontainer);
begin
  consume(_COLON);
  aktprocsym^.definition^.extnumber:=get_intconst;
end;

procedure pd_interrupt(const procnames:Tstringcontainer);
begin
{$ifndef i386}
  Message(parser_w_proc_interrupt_ignored);
{$else i386}
  if lexlevel<>normal_function_level then
    Message(parser_e_dont_nest_interrupt);
{$endif i386}
end;

procedure pd_system(const procnames:Tstringcontainer);
begin
  aktprocsym^.definition^.setmangledname(aktprocsym^.realname);
end;

procedure pd_abstract(const procnames:Tstringcontainer);
begin
  if (po_virtualmethod in aktprocsym^.definition^.procoptions) then
    include(aktprocsym^.definition^.procoptions,po_abstractmethod)
  else
    Message(parser_e_only_virtual_methods_abstract);
  { the method is defined }
  aktprocsym^.definition^.forwarddef:=false;
end;

procedure pd_virtual(const procnames:Tstringcontainer);
{$ifdef WITHDMT}
var
  pt : tnode;
{$endif WITHDMT}
begin
  if (aktprocsym^.definition^.proctypeoption=potype_constructor) and
     not(aktprocsym^.definition^._class^.is_class) then
    Message(parser_e_constructor_cannot_be_not_virtual);
{$ifdef WITHDMT}
  if not(aktprocsym^.definition^._class^.is_class) and
    (token<>_SEMICOLON) then
    begin
       { any type of parameter is allowed here! }

       pt:=comp_expr(true);
       do_firstpass(pt);
       if is_constintnode(pt) then
         begin
           include(aktprocsym^.definition^.procoptions,po_msgint);
           aktprocsym^.definition^.messageinf.i:=pt^.value;
         end
       else
         Message(parser_e_ill_msg_expr);
       disposetree(pt);
    end;
{$endif WITHDMT}
end;

procedure pd_static(const procnames:Tstringcontainer);
begin
  if (cs_static_keyword in aktmoduleswitches) then
    begin
      include(aktprocsym^.symoptions,sp_static);
      include(aktprocsym^.definition^.procoptions,po_staticmethod);
    end;
end;

procedure pd_override(const procnames:Tstringcontainer);
begin
  if not(aktprocsym^.definition^._class^.is_class) then
    Message(parser_e_no_object_override);
end;

procedure pd_overload(const procnames:Tstringcontainer);
begin
end;

procedure pd_message(const procnames:Tstringcontainer);
var
  pt : tnode;
begin
  { check parameter type }
  if not(po_containsself in aktprocsym^.definition^.procoptions) and
     ((aktprocsym^.definition^.minparacount<>1) or
      (aktprocsym^.definition^.maxparacount<>1) or
      (pparaitem(aktprocsym^.definition^.para^.first)^.paratyp<>vs_var)) then
   Message(parser_e_ill_msg_param);
  pt:=comp_expr(true);
  do_firstpass(pt);
  if pt.nodetype=stringconstn then
    begin
      include(aktprocsym^.definition^.procoptions,po_msgstr);
      aktprocsym^.definition^.messageinf.str:=strnew(tstringconstnode(pt).value_str);
    end
  else
   if is_constintnode(pt) then
    begin
      include(aktprocsym^.definition^.procoptions,po_msgint);
      aktprocsym^.definition^.messageinf.i:=tordconstnode(pt).value;
    end
  else
    Message(parser_e_ill_msg_expr);
  pt.free;
end;


procedure resetvaluepara(p:pnamedindexobject);
begin
  if psym(p)^.typ=varsym then
    with pvarsym(p)^ do
       if copy(name,1,3)='val' then
          aktprocsym^.definition^.parast^.symsearch^.rename(name,copy(name,4,length(name)));
end;


procedure pd_cdecl(const procnames:Tstringcontainer);
begin
  if aktprocsym^.definition^.deftype<>procvardef then
    aktprocsym^.definition^.setmangledname(target_os.Cprefix+aktprocsym^.realname);
  { do not copy on local !! }
  if (aktprocsym^.definition^.deftype=procdef) and
     assigned(aktprocsym^.definition^.parast) then
    aktprocsym^.definition^.parast^.foreach({$ifdef FPCPROCVAR}@{$endif}resetvaluepara);
end;

procedure pd_cppdecl(const procnames:Tstringcontainer);
begin
  if aktprocsym^.definition^.deftype<>procvardef then
    aktprocsym^.definition^.setmangledname(
      target_os.Cprefix+aktprocsym^.definition^.cplusplusmangledname);
  { do not copy on local !! }
  if (aktprocsym^.definition^.deftype=procdef) and
     assigned(aktprocsym^.definition^.parast) then
    aktprocsym^.definition^.parast^.foreach({$ifdef FPCPROCVAR}@{$endif}resetvaluepara);
end;


procedure pd_pascal(const procnames:Tstringcontainer);
var st,parast : psymtable;
    lastps,ps : psym;
begin
   new(st,init(parasymtable));
   parast:=aktprocsym^.definition^.parast;
   lastps:=nil;
   while assigned(parast^.symindex^.first) and (lastps<>psym(parast^.symindex^.first)) do
     begin
       ps:=psym(parast^.symindex^.first);
       while assigned(ps^.indexnext) and (psym(ps^.indexnext)<>lastps) do
         ps:=psym(ps^.indexnext);
       ps^.owner:=st;
       { recalculate the corrected offset }
       { the really_insert_in_data procedure
         for parasymtable should only calculateoffset PM }
       pstoredsym(ps)^.insert_in_data;
       { reset the owner correctly }
       ps^.owner:=parast;
       lastps:=ps;
     end;
end;


procedure pd_register(const procnames:Tstringcontainer);
begin
  Message1(parser_w_proc_directive_ignored,'REGISTER');
end;


procedure pd_reintroduce(const procnames:Tstringcontainer);
begin
  Message1(parser_w_proc_directive_ignored,'REINTRODUCE');
end;


procedure pd_syscall(const procnames:Tstringcontainer);
begin
  aktprocsym^.definition^.forwarddef:=false;
  aktprocsym^.definition^.extnumber:=get_intconst;
end;


procedure pd_external(const procnames:Tstringcontainer);
{
  If import_dll=nil the procedure is assumed to be in another
  object file. In that object file it should have the name to
  which import_name is pointing to. Otherwise, the procedure is
  assumed to be in the DLL to which import_dll is pointing to. In
  that case either import_nr<>0 or import_name<>nil is true, so
  the procedure is either imported by number or by name. (DM)
}
var
  import_dll,
  import_name : string;
  import_nr   : word;
begin
  aktprocsym^.definition^.forwarddef:=false;
{ If the procedure should be imported from a DLL, a constant string follows.
  This isn't really correct, an contant string expression follows
  so we check if an semicolon follows, else a string constant have to
  follow (FK) }
  import_nr:=0;
  import_name:='';
  if not(token=_SEMICOLON) and not(idtoken=_NAME) then
    begin
      import_dll:=get_stringconst;
      if (idtoken=_NAME) then
       begin
         consume(_NAME);
         import_name:=get_stringconst;
       end;
      if (idtoken=_INDEX) then
       begin
         {After the word index follows the index number in the DLL.}
         consume(_INDEX);
         import_nr:=get_intconst;
       end;
      if (import_nr=0) and (import_name='') then
        {if (aktprocsym^.definition^.options and pocdecl)<>0 then
          import_name:=aktprocsym^.definition^.mangledname
        else
          Message(parser_w_empty_import_name);}
        { this should work both for win32 and Linux !! PM }
        import_name:=aktprocsym^.realname;
      if not(current_module^.uses_imports) then
       begin
         current_module^.uses_imports:=true;
         importlib^.preparelib(current_module^.modulename^);
       end;
      if not(m_repeat_forward in aktmodeswitches) then
        begin
          { we can only have one overloaded here ! }
          if assigned(aktprocsym^.definition^.nextoverloaded) then
            importlib^.importprocedure(aktprocsym^.definition^.nextoverloaded^.mangledname,
              import_dll,import_nr,import_name)
          else
            importlib^.importprocedure(aktprocsym^.mangledname,import_dll,import_nr,import_name);
        end
      else
        importlib^.importprocedure(aktprocsym^.mangledname,import_dll,import_nr,import_name);
    end
  else
    begin
      if (idtoken=_NAME) then
       begin
         consume(_NAME);
         import_name:=get_stringconst;
         aktprocsym^.definition^.setmangledname(import_name);
       end
      else
       begin
         { external shouldn't override the cdecl/system name }
         if not (pocall_clearstack in aktprocsym^.definition^.proccalloptions) then
           aktprocsym^.definition^.setmangledname(aktprocsym^.realname);
       end;
    end;
end;

type
   pd_handler=procedure(const procnames:Tstringcontainer);
   proc_dir_rec=record
     idtok     : ttoken;
     pd_flags  : longint;
     handler   : pd_handler;
     pocall    : tproccalloptions;
     pooption  : tprocoptions;
     mutexclpocall : tproccalloptions;
     mutexclpotype : tproctypeoptions;
     mutexclpo     : tprocoptions;
   end;
const
  {Should contain the number of procedure directives we support.}
  num_proc_directives=32;
  proc_direcdata:array[1..num_proc_directives] of proc_dir_rec=
   (
    (
      idtok:_ABSTRACT;
      pd_flags : pd_interface+pd_object;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_abstract;
      pocall   : [];
      pooption : [po_abstractmethod];
      mutexclpocall : [pocall_internproc,pocall_inline];
      mutexclpotype : [potype_constructor,potype_destructor];
      mutexclpo     : [po_exports,po_interrupt,po_external]
    ),(
      idtok:_ALIAS;
      pd_flags : pd_implemen+pd_body;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_alias;
      pocall   : [];
      pooption : [];
      mutexclpocall : [pocall_inline];
      mutexclpotype : [];
      mutexclpo     : [po_external]
    ),(
      idtok:_ASMNAME;
      pd_flags : pd_interface+pd_implemen;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_asmname;
      pocall   : [pocall_cdecl,pocall_clearstack];
      pooption : [po_external];
      mutexclpocall : [pocall_internproc];
      mutexclpotype : [];
      mutexclpo     : [po_external]
    ),(
      idtok:_ASSEMBLER;
      pd_flags : pd_implemen+pd_body;
      handler  : nil;
      pocall   : [];
      pooption : [po_assembler];
      mutexclpocall : [];
      mutexclpotype : [];
      mutexclpo     : [po_external]
    ),(
      idtok:_CDECL;
      pd_flags : pd_interface+pd_implemen+pd_body+pd_procvar;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_cdecl;
      pocall   : [pocall_cdecl,pocall_clearstack];
      pooption : [po_savestdregs];
      mutexclpocall : [pocall_cppdecl,pocall_internproc,pocall_leftright,pocall_inline];
      mutexclpotype : [];
      mutexclpo     : [po_assembler,po_external]
    ),(
      idtok:_DYNAMIC;
      pd_flags : pd_interface+pd_object;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_virtual;
      pocall   : [];
      pooption : [po_virtualmethod];
      mutexclpocall : [pocall_internproc,pocall_inline];
      mutexclpotype : [];
      mutexclpo     : [po_exports,po_interrupt,po_external]
    ),(
      idtok:_EXPORT;
      pd_flags : pd_body+pd_global+pd_interface+pd_implemen{??};
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_export;
      pocall   : [];
      pooption : [po_exports];
      mutexclpocall : [pocall_internproc,pocall_inline];
      mutexclpotype : [];
      mutexclpo     : [po_external,po_interrupt]
    ),(
      idtok:_EXTERNAL;
      pd_flags : pd_implemen+pd_interface;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_external;
      pocall   : [];
      pooption : [po_external];
      mutexclpocall : [pocall_internproc,pocall_inline,pocall_palmossyscall];
      mutexclpotype : [];
      mutexclpo     : [po_exports,po_interrupt,po_assembler]
    ),(
      idtok:_FAR;
      pd_flags : pd_implemen+pd_body+pd_interface+pd_procvar;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_far;
      pocall   : [];
      pooption : [];
      mutexclpocall : [pocall_internproc,pocall_inline];
      mutexclpotype : [];
      mutexclpo     : []
    ),(
      idtok:_FORWARD;
      pd_flags : pd_implemen;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_forward;
      pocall   : [];
      pooption : [];
      mutexclpocall : [pocall_internproc,pocall_inline];
      mutexclpotype : [];
      mutexclpo     : [po_external]
    ),(
      idtok:_INLINE;
      pd_flags : pd_implemen+pd_body;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_inline;
      pocall   : [pocall_inline];
      pooption : [];
      mutexclpocall : [pocall_internproc];
      mutexclpotype : [potype_constructor,potype_destructor];
      mutexclpo     : [po_exports,po_external,po_interrupt]
    ),(
      idtok:_INTERNCONST;
      pd_flags : pd_implemen+pd_body;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_intern;
      pocall   : [pocall_internconst];
      pooption : [];
      mutexclpocall : [];
      mutexclpotype : [potype_operator];
      mutexclpo     : []
    ),(
      idtok:_INTERNPROC;
      pd_flags : pd_implemen;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_intern;
      pocall   : [pocall_internproc];
      pooption : [];
      mutexclpocall : [pocall_inline,pocall_clearstack,pocall_leftright,pocall_cdecl,pocall_cppdecl];
      mutexclpotype : [potype_constructor,potype_destructor,potype_operator];
      mutexclpo     : [po_exports,po_external,po_interrupt,po_assembler,po_iocheck]
    ),(
      idtok:_INTERRUPT;
      pd_flags : pd_implemen+pd_body;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_interrupt;
      pocall   : [];
      pooption : [po_interrupt];
      mutexclpocall : [pocall_internproc,pocall_cdecl,pocall_cppdecl,pocall_clearstack,pocall_leftright,pocall_inline];
      mutexclpotype : [potype_constructor,potype_destructor,potype_operator];
      mutexclpo     : [po_external]
    ),(
      idtok:_IOCHECK;
      pd_flags : pd_implemen+pd_body;
      handler  : nil;
      pocall   : [];
      pooption : [po_iocheck];
      mutexclpocall : [pocall_internproc];
      mutexclpotype : [];
      mutexclpo     : [po_external]
    ),(
      idtok:_MESSAGE;
      pd_flags : pd_interface+pd_object;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_message;
      pocall   : [];
      pooption : []; { can be po_msgstr or po_msgint }
      mutexclpocall : [pocall_inline,pocall_internproc];
      mutexclpotype : [potype_constructor,potype_destructor,potype_operator];
      mutexclpo     : [po_interrupt,po_external]
    ),(
      idtok:_NEAR;
      pd_flags : pd_implemen+pd_body+pd_procvar;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_near;
      pocall   : [];
      pooption : [];
      mutexclpocall : [pocall_internproc];
      mutexclpotype : [];
      mutexclpo     : []
    ),(
      idtok:_OVERLOAD;
      pd_flags : pd_implemen+pd_interface+pd_body;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_overload;
      pocall   : [];
      pooption : [po_overload];
      mutexclpocall : [pocall_internproc];
      mutexclpotype : [];
      mutexclpo     : []
    ),(
      idtok:_OVERRIDE;
      pd_flags : pd_interface+pd_object;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_override;
      pocall   : [];
      pooption : [po_overridingmethod,po_virtualmethod];
      mutexclpocall : [pocall_inline,pocall_internproc];
      mutexclpotype : [];
      mutexclpo     : [po_exports,po_external,po_interrupt]
    ),(
      idtok:_PASCAL;
      pd_flags : pd_implemen+pd_body+pd_procvar;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_pascal;
      pocall   : [pocall_leftright];
      pooption : [];
      mutexclpocall : [pocall_internproc];
      mutexclpotype : [];
      mutexclpo     : [po_external]
    ),(
      idtok:_POPSTACK;
      pd_flags : pd_interface+pd_implemen+pd_body+pd_procvar;
      handler  : nil;
      pocall   : [pocall_clearstack];
      pooption : [];
      mutexclpocall : [pocall_inline,pocall_internproc];
      mutexclpotype : [];
      mutexclpo     : [po_assembler,po_external]
    ),(
      idtok:_PUBLIC;
      pd_flags : pd_implemen+pd_body+pd_global+pd_notobject;
      handler  : nil;
      pocall   : [];
      pooption : [];
      mutexclpocall : [pocall_internproc,pocall_inline];
      mutexclpotype : [];
      mutexclpo     : [po_external]
    ),(
      idtok:_REGISTER;
      pd_flags : pd_interface+pd_implemen+pd_body+pd_procvar;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_register;
      pocall   : [pocall_register];
      pooption : [];
      mutexclpocall : [pocall_leftright,pocall_cdecl,pocall_internproc,pocall_cppdecl];
      mutexclpotype : [];
      mutexclpo     : [po_external]
    ),(
      idtok:_REINTRODUCE;
      pd_flags : pd_interface+pd_object;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_reintroduce;
      pocall   : [];
      pooption : [];
      mutexclpocall : [];
      mutexclpotype : [];
      mutexclpo     : []
    ),(
      idtok:_SAFECALL;
      pd_flags : pd_interface+pd_implemen+pd_body+pd_procvar;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_safecall;
      pocall   : [pocall_safecall];
      pooption : [po_savestdregs];
      mutexclpocall : [pocall_leftright,pocall_cdecl,pocall_cppdecl,pocall_internproc,pocall_inline];
      mutexclpotype : [];
      mutexclpo     : [po_external]
    ),(
      idtok:_SAVEREGISTERS;
      pd_flags : pd_interface+pd_implemen+pd_body+pd_procvar;
      handler  : nil;
      pocall   : [];
      pooption : [po_saveregisters];
      mutexclpocall : [pocall_internproc];
      mutexclpotype : [];
      mutexclpo     : [po_external]
    ),(
      idtok:_STATIC;
      pd_flags : pd_interface+pd_object;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_static;
      pocall   : [];
      pooption : [po_staticmethod];
      mutexclpocall : [pocall_inline,pocall_internproc];
      mutexclpotype : [potype_constructor,potype_destructor];
      mutexclpo     : [po_external,po_interrupt,po_exports]
    ),(
      idtok:_STDCALL;
      pd_flags : pd_interface+pd_implemen+pd_body+pd_procvar;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_stdcall;
      pocall   : [pocall_stdcall];
      pooption : [po_savestdregs];
      mutexclpocall : [pocall_leftright,pocall_cdecl,pocall_cppdecl,pocall_inline,pocall_internproc];
      mutexclpotype : [];
      mutexclpo     : [po_external]
    ),(
      idtok:_SYSCALL;
      pd_flags : pd_interface;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_syscall;
      pocall   : [pocall_palmossyscall];
      pooption : [];
      mutexclpocall : [pocall_cdecl,pocall_cppdecl,pocall_inline,pocall_internproc];
      mutexclpotype : [];
      mutexclpo     : [po_external,po_assembler,po_interrupt,po_exports]
    ),(
      idtok:_SYSTEM;
      pd_flags : pd_implemen;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_system;
      pocall   : [pocall_clearstack];
      pooption : [];
      mutexclpocall : [pocall_leftright,pocall_inline,pocall_internproc];
      mutexclpotype : [];
      mutexclpo     : [po_external,po_assembler,po_interrupt]
    ),(
      idtok:_VIRTUAL;
      pd_flags : pd_interface+pd_object;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_virtual;
      pocall   : [];
      pooption : [po_virtualmethod];
      mutexclpocall : [pocall_inline,pocall_internproc];
      mutexclpotype : [];
      mutexclpo     : [po_external,po_interrupt,po_exports]
    ),(
      idtok:_CPPDECL;
      pd_flags : pd_interface+pd_implemen+pd_body+pd_procvar;
      handler  : {$ifdef FPCPROCVAR}@{$endif}pd_cppdecl;
      pocall   : [pocall_cppdecl,pocall_clearstack];
      pooption : [po_savestdregs];
      mutexclpocall : [pocall_cdecl,pocall_internproc,pocall_leftright,pocall_inline];
      mutexclpotype : [];
      mutexclpo     : [po_assembler,po_external]
    )
   );


function is_proc_directive(tok:ttoken):boolean;
var
  i : longint;
begin
  is_proc_directive:=false;
  for i:=1 to num_proc_directives do
   if proc_direcdata[i].idtok=idtoken then
    begin
      is_proc_directive:=true;
      exit;
    end;
end;


function parse_proc_direc(const proc_names:Tstringcontainer;var pdflags:word):boolean;
{
  Parse the procedure directive, returns true if a correct directive is found
}
var
  p     : longint;
  found : boolean;
  name  : string;
begin
  parse_proc_direc:=false;
  name:=pattern;
  found:=false;
  for p:=1 to num_proc_directives do
   if proc_direcdata[p].idtok=idtoken then
    begin
      found:=true;
      break;
    end;

{ Check if the procedure directive is known }
  if not found then
   begin
      { parsing a procvar type the name can be any
        next variable !! }
      if (pdflags and (pd_procvar or pd_object))=0 then
        Message1(parser_w_unknown_proc_directive_ignored,name);
      exit;
   end;

  { static needs a special treatment }
  if (idtoken=_STATIC) and not (cs_static_keyword in aktmoduleswitches) then
    exit;

{ Conflicts between directives ? }
  if (aktprocsym^.definition^.proctypeoption in proc_direcdata[p].mutexclpotype) or
     ((aktprocsym^.definition^.proccalloptions*proc_direcdata[p].mutexclpocall)<>[]) or
     ((aktprocsym^.definition^.procoptions*proc_direcdata[p].mutexclpo)<>[]) then
   begin
     Message1(parser_e_proc_dir_conflict,name);
     exit;
   end;

{ Check if the directive is only for objects }
  if ((proc_direcdata[p].pd_flags and pd_object)<>0) and
     not assigned(aktprocsym^.definition^._class) then
    begin
      exit;
    end;
{ check if method and directive not for object public }
  if ((proc_direcdata[p].pd_flags and pd_notobject)<>0) and
     assigned(aktprocsym^.definition^._class) then
    begin
      exit;
    end;

{ consume directive, and turn flag on }
  consume(token);
  parse_proc_direc:=true;

{ Check the pd_flags if the directive should be allowed }
  if ((pdflags and pd_interface)<>0) and
     ((proc_direcdata[p].pd_flags and pd_interface)=0) then
    begin
      Message1(parser_e_proc_dir_not_allowed_in_interface,name);
      exit;
    end;
  if ((pdflags and pd_implemen)<>0) and
     ((proc_direcdata[p].pd_flags and pd_implemen)=0) then
    begin
      Message1(parser_e_proc_dir_not_allowed_in_implementation,name);
      exit;
    end;
  if ((pdflags and pd_procvar)<>0) and
     ((proc_direcdata[p].pd_flags and pd_procvar)=0) then
    begin
      Message1(parser_e_proc_dir_not_allowed_in_procvar,name);
      exit;
    end;

{ Return the new pd_flags }
  if (proc_direcdata[p].pd_flags and pd_body)=0 then
    pdflags:=pdflags and (not pd_body);
  if (proc_direcdata[p].pd_flags and pd_global)<>0 then
    pdflags:=pdflags or pd_global;

{ Add the correct flag }
  aktprocsym^.definition^.proccalloptions:=aktprocsym^.definition^.proccalloptions+proc_direcdata[p].pocall;
  aktprocsym^.definition^.procoptions:=aktprocsym^.definition^.procoptions+proc_direcdata[p].pooption;

 { Adjust positions of args for cdecl or stdcall }
   if (aktprocsym^.definition^.deftype=procdef) and
      (([pocall_cdecl,pocall_cppdecl,pocall_stdcall]*aktprocsym^.definition^.proccalloptions)<>[]) then
     pstoredsymtable(aktprocsym^.definition^.parast)^.set_alignment(target_os.size_of_longint);

{ Call the handler }
  if pointer({$ifndef FPC}@{$endif}proc_direcdata[p].handler)<>nil then
    proc_direcdata[p].handler(proc_names);
end;


procedure parse_proc_directives(Anames:Pstringcontainer;var pdflags:word);
{
  Parse the procedure directives. It does not matter if procedure directives
  are written using ;procdir; or ['procdir'] syntax.
}
var
  res : boolean;
begin
  while token in [_ID,_LECKKLAMMER] do
   begin
     if try_to_consume(_LECKKLAMMER) then
      begin
        repeat
          parse_proc_direc(Anames^,pdflags);
        until not try_to_consume(_COMMA);
        consume(_RECKKLAMMER);
        { we always expect at least '[];' }
        res:=true;
      end
     else
      res:=parse_proc_direc(Anames^,pdflags);
   { A procedure directive normally followed by a semicolon, but in
     a const section we should stop when _EQUAL is found }
     if res then
      begin
        if (block_type=bt_const) and
           (token=_EQUAL) then
         break;
        { support procedure proc;stdcall export; in Delphi mode only }
        if not((m_delphi in aktmodeswitches) and
               is_proc_directive(token)) then
         consume(_SEMICOLON);
      end
     else
      break;
   end;
end;

procedure parse_var_proc_directives(var sym : psym);
var
  anames  : pstringcontainer;
  pdflags : word;
  oldsym  : pprocsym;
  pd      : pabstractprocdef;
begin
  oldsym:=aktprocsym;
  anames:=new(pstringcontainer,init);
  pdflags:=pd_procvar;
  { we create a temporary aktprocsym to read the directives }
  aktprocsym:=new(pprocsym,init(sym^.name));
  case sym^.typ of
    varsym :
      pd:=pabstractprocdef(pvarsym(sym)^.vartype.def);
    typedconstsym :
      pd:=pabstractprocdef(ptypedconstsym(sym)^.typedconsttype.def);
    typesym :
      pd:=pabstractprocdef(ptypesym(sym)^.restype.def);
    else
      internalerror(994932432);
  end;
  if pd^.deftype<>procvardef then
   internalerror(994932433);
  pabstractprocdef(aktprocsym^.definition):=pd;
  { names should never be used anyway }
  inc(lexlevel);
  parse_proc_directives(anames,pdflags);
  dec(lexlevel);
  aktprocsym^.definition:=nil;
  dispose(aktprocsym,done);
  dispose(anames,done);
  aktprocsym:=oldsym;
end;


procedure parse_object_proc_directives(var sym : pprocsym);
var
  anames : pstringcontainer;
  pdflags : word;
begin
  pdflags:=pd_object;
  anames:=new(pstringcontainer,init);
  inc(lexlevel);
  parse_proc_directives(anames,pdflags);
  dec(lexlevel);
  dispose(anames,done);
  if (po_containsself in aktprocsym^.definition^.procoptions) and
     (([po_msgstr,po_msgint]*aktprocsym^.definition^.procoptions)=[]) then
    Message(parser_e_self_in_non_message_handler);
end;

{***************************************************************************}

function check_identical_proc(var p : pprocdef) : boolean;
{
  Search for idendical definitions,
  if there is a forward, then kill this.

  Returns the result of the forward check.

  Removed from unter_dec to keep the source readable
}
var
  hd,pd : Pprocdef;
  storeparast : psymtable;
  ad,fd : psym;
  s : string;
begin
  check_identical_proc:=false;
  p:=nil;
  pd:=aktprocsym^.definition;
  if assigned(pd) then
   begin
   { Is there an overload/forward ? }
     if assigned(pd^.nextoverloaded) then
      begin
      { walk the procdef list }
        while (assigned(pd)) and (assigned(pd^.nextoverloaded)) do
         begin
           hd:=pd^.nextoverloaded;

           { check the parameters }
           if (not(m_repeat_forward in aktmodeswitches) and
               (aktprocsym^.definition^.maxparacount=0)) or
              (equal_paras(aktprocsym^.definition^.para,hd^.para,cp_none) and
              { for operators equal_paras is not enough !! }
              ((aktprocsym^.definition^.proctypeoption<>potype_operator) or (optoken<>_ASSIGNMENT) or
               is_equal(hd^.rettype.def,aktprocsym^.definition^.rettype.def))) then
             begin
               if not equal_paras(aktprocsym^.definition^.para,hd^.para,cp_all) and
                  ((m_repeat_forward in aktmodeswitches) or
                   (aktprocsym^.definition^.maxparacount>0)) then
                 begin
                    MessagePos1(aktprocsym^.definition^.fileinfo,parser_e_header_dont_match_forward,
                                aktprocsym^.definition^.fullprocname);
                    exit;
                 end;
               if hd^.forwarddef then
               { remove the forward definition  but don't delete it,      }
               { the symtable is the owner !!  }
                 begin
                 { Check if the procedure type and return type are correct }
                   if (hd^.proctypeoption<>aktprocsym^.definition^.proctypeoption) or
                      (not(is_equal(hd^.rettype.def,aktprocsym^.definition^.rettype.def)) and
                      (m_repeat_forward in aktmodeswitches)) then
                     begin
                       MessagePos1(aktprocsym^.definition^.fileinfo,parser_e_header_dont_match_forward,
                                   aktprocsym^.definition^.fullprocname);
                       exit;
                     end;
                   { Check calling convention, no check for internconst,internproc which
                     are only defined in interface or implementation }
                   if (hd^.proccalloptions-[pocall_internconst,pocall_internproc]<>
                       aktprocsym^.definition^.proccalloptions-[pocall_internconst,pocall_internproc]) then
                    begin
                      { only trigger an error, becuase it doesn't hurt, for delphi check
                        if the current implementation has no proccalloptions, then
                        take the options from the interface }
                      if (m_delphi in aktmodeswitches) then
                       begin
                         if (aktprocsym^.definition^.proccalloptions=[]) then
                          aktprocsym^.definition^.proccalloptions:=hd^.proccalloptions
                         else
                          MessagePos(aktprocsym^.definition^.fileinfo,parser_e_call_convention_dont_match_forward);
                       end
                      else
                       MessagePos(aktprocsym^.definition^.fileinfo,parser_e_call_convention_dont_match_forward);
                      { set the mangledname to the interface name so it doesn't trigger
                        the Note about different manglednames (PFV) }
                      aktprocsym^.definition^.setmangledname(hd^.mangledname);
                    end;
                   { manglednames are equal? }
                   hd^.count:=false;
                   if (m_repeat_forward in aktmodeswitches) or
                      aktprocsym^.definition^.haspara then
                    begin
                      if (hd^.mangledname<>aktprocsym^.definition^.mangledname) then
                       begin
                         if not(po_external in aktprocsym^.definition^.procoptions) then
                           MessagePos2(aktprocsym^.definition^.fileinfo,parser_n_interface_name_diff_implementation_name,hd^.mangledname,
                             aktprocsym^.definition^.mangledname);
                       { reset the mangledname of the interface part to be sure }
                       { this is wrong because the mangled name might have been used already !! }
                          if hd^.is_used then
                            renameasmsymbol(hd^.mangledname,aktprocsym^.definition^.mangledname);
                          hd^.setmangledname(aktprocsym^.definition^.mangledname);
                       { so we need to keep the name of interface !!
                         No!!!! The procedure directives can change the mangledname.
                         I fixed this by first calling check_identical_proc and then doing
                         the proc directives, but this is not a good solution.(DM)}
                         { this is also wrong (PM)
                         aktprocsym^.definition^.setmangledname(hd^.mangledname);}
                       end
                      else
                       begin
                       { If mangled names are equal, therefore    }
                       { they have the same number of parameters  }
                       { Therefore we can check the name of these }
                       { parameters...                      }
                         if hd^.forwarddef and aktprocsym^.definition^.forwarddef then
                           begin
                             MessagePos1(aktprocsym^.definition^.fileinfo,
                                         parser_e_function_already_declared_public_forward,
                                         aktprocsym^.definition^.fullprocname);
                             check_identical_proc:=true;
                           { Remove other forward from the list to reduce errors }
                             pd^.nextoverloaded:=pd^.nextoverloaded^.nextoverloaded;
                             exit;
                           end;
                         ad:=psym(hd^.parast^.symindex^.first);
                         fd:=psym(aktprocsym^.definition^.parast^.symindex^.first);
                         if assigned(ad) and assigned(fd) then
                           begin
                             while assigned(ad) and assigned(fd) do
                               begin
                                 s:=ad^.name;
                                 if s<>fd^.name then
                                   begin
                                     MessagePos3(aktprocsym^.definition^.fileinfo,parser_e_header_different_var_names,
                                       aktprocsym^.name,s,fd^.name);
                                     break;
                                   end;
                               { it is impossible to have a nil pointer }
                               { for only one parameter - since they    }
                               { have the same number of parameters.    }
                               { Left = next parameter.          }
                                 ad:=psym(ad^.left);
                                 fd:=psym(fd^.left);
                               end;
                           end;
                       end;
                    end;
                 { also the para_offset }
                   hd^.parast^.address_fixup:=aktprocsym^.definition^.parast^.address_fixup;
                   hd^.count:=true;

                 { remove pd^.nextoverloaded from the list }
                 { and add aktprocsym^.definition }
                   pd^.nextoverloaded:=pd^.nextoverloaded^.nextoverloaded;
                   hd^.nextoverloaded:=aktprocsym^.definition^.nextoverloaded;
                 { Alert! All fields of aktprocsym^.definition that are modified
                   by the procdir handlers must be copied here!.}
                   hd^.forwarddef:=false;
                   hd^.hasforward:=true;
                   hd^.proccalloptions:=hd^.proccalloptions + aktprocsym^.definition^.proccalloptions;
                   hd^.procoptions:=hd^.procoptions + aktprocsym^.definition^.procoptions;
                   if aktprocsym^.definition^.extnumber=-1 then
                     aktprocsym^.definition^.extnumber:=hd^.extnumber
                   else
                     if hd^.extnumber=-1 then
                       hd^.extnumber:=aktprocsym^.definition^.extnumber;
                   { switch parast for warning in implementation  PM }
                   if (m_repeat_forward in aktmodeswitches) or
                      aktprocsym^.definition^.haspara then
                     begin
                        storeparast:=hd^.parast;
                        hd^.parast:=aktprocsym^.definition^.parast;
                        aktprocsym^.definition^.parast:=storeparast;
                     end;
                   if pd=aktprocsym^.definition then
                     p:=nil
                   else
                     p:=pd;
                   aktprocsym^.definition:=hd;
                   check_identical_proc:=true;
                 end
               else
               { abstract methods aren't forward defined, but this }
               { needs another error message                   }
                 if not(po_abstractmethod in pd^.nextoverloaded^.procoptions) then
                   MessagePos(aktprocsym^.definition^.fileinfo,parser_e_overloaded_have_same_parameters)
                 else
                   MessagePos(aktprocsym^.definition^.fileinfo,parser_e_abstract_no_definition);
               break;
             end;

           { check for allowing overload directive }
           if not(m_fpc in aktmodeswitches) then
            begin
              { overload directive turns on overloading }
              if ((po_overload in aktprocsym^.definition^.procoptions) or
                  ((po_overload in hd^.procoptions))) then
               begin
                 { check if all procs have overloading, but not if the proc was
                   already declared forward, then the check is already done }
                 if not(hd^.hasforward) and
                    (aktprocsym^.definition^.forwarddef=hd^.forwarddef) and
                    not((po_overload in aktprocsym^.definition^.procoptions) and
                        ((po_overload in hd^.procoptions))) then
                  begin
                    MessagePos1(aktprocsym^.definition^.fileinfo,parser_e_no_overload_for_all_procs,aktprocsym^.realname);
                    break;
                  end;
               end
              else
               begin
                 if not(hd^.forwarddef) then
                  begin
                    MessagePos(aktprocsym^.definition^.fileinfo,parser_e_procedure_overloading_is_off);
                    break;
                  end;
               end;
            end;

           { try next overloaded }
           pd:=pd^.nextoverloaded;
         end;
      end
     else
      begin
      { there is no overloaded, so its always identical with itself }
        check_identical_proc:=true;
      end;
   end;
{ insert opsym only in the right symtable }
  if ((procinfo^.flags and pi_operator)<>0) and assigned(opsym)
     and not parse_only then
    begin
      if ret_in_param(aktprocsym^.definition^.rettype.def) then
        begin
          pprocdef(aktprocsym^.definition)^.parast^.insert(opsym);
        { this increases the data size }
        { correct this to get the right ret $value }
          dec(pprocdef(aktprocsym^.definition)^.parast^.datasize,opsym^.getpushsize);
          { this allows to read the funcretoffset }
          opsym^.address:=-4;
          opsym^.varspez:=vs_var;
        end
      else
        pprocdef(aktprocsym^.definition)^.localst^.insert(opsym);
    end;
end;



procedure checkvaluepara(p:pnamedindexobject);
var
  vs : pvarsym;
  s  : string;
begin
  with pvarsym(p)^ do
   begin
     if copy(name,1,3)='val' then
      begin
        s:=Copy(name,4,255);
        if not(po_assembler in aktprocsym^.definition^.procoptions) then
         begin
           vs:=new(Pvarsym,initdef(s,vartype.def));
           vs^.fileinfo:=fileinfo;
           vs^.varspez:=varspez;
           aktprocsym^.definition^.localst^.insert(vs);
           include(vs^.varoptions,vo_is_local_copy);
           vs^.varstate:=vs_assigned;
           localvarsym:=vs;
           inc(refs); { the para was used to set the local copy ! }
           { warnings only on local copy ! }
           varstate:=vs_used;
         end
        else
         begin
           aktprocsym^.definition^.parast^.rename(name,s);
         end;
      end;
   end;
end;

end.
{
  $Log$
  Revision 1.5  2000-11-01 23:04:37  peter
    * tprocdef.fullprocname added for better casesensitve writing of
      procedures

  Revision 1.4  2000/10/31 22:02:49  peter
    * symtable splitted, no real code changes

  Revision 1.3  2000/10/21 18:16:11  florian
    * a lot of changes:
       - basic dyn. array support
       - basic C++ support
       - some work for interfaces done
       ....

  Revision 1.2  2000/10/15 07:47:51  peter
    * unit names and procedure names are stored mixed case

  Revision 1.1  2000/10/14 10:14:51  peter
    * moehrendorf oct 2000 rewrite

}