{
    $Id$
    Copyright (c) 1993-98 by Florian Klaempfl

    This unit implements the basic code generator object

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
unit cgobj;

  interface

    uses
       cobjects,aasm,symtable
{$I cpuunit.inc}
       ;

    type
       qword = comp;

       pcg = ^tcg;
       tcg = object
          constructor init;
          destructor done;virtual;

          procedure a_call_name_ext(list : paasmoutput;const s : string;
            offset : longint;m : texternal_typ);

          {************************************************}
          { code generation for subroutine entry/exit code }

          { helper routines }
          procedure g_initialize_data(p : psym);
          procedure g_incr_data(p : psym);
          procedure g_finalize_data(p : psym);
{$ifndef VALUEPARA}
          procedure g_copyopenarrays(p : psym);
{$else}
          procedure g_copyvalueparas(p : psym);
{$endif}

          procedure g_entrycode(list : paasmoutput;
            const proc_names : tstringcontainer;make_global : boolean;
            stackframe : longint;var parasize : longint;
            var nostackframe : boolean;inlined : boolean);

          procedure g_exitcode(list : paasmoutput;parasize : longint;
            nostackframe,inlined : boolean);

          { string helper routines }
          procedure g_decransiref(const ref : treference);

          procedure g_removetemps(list : paasmoutput;p : plinkedlist);

          {**********************************}
          { these methods must be overriden: }
          procedure a_push_reg(list : paasmoutput;r : tregister);virtual;
          procedure a_call_name(list : paasmoutput;const s : string;
            offset : longint);virtual;

          procedure a_load_const8_ref(list : paasmoutput;b : byte;const ref : treference);virtual;
          procedure a_load_const16_ref(list : paasmoutput;w : word;const ref : treference);virtual;
          procedure a_load_const32_ref(list : paasmoutput;l : longint;const ref : treference);virtual;
          procedure a_load_const64_ref(list : paasmoutput;q : qword;const ref : treference);virtual;


          procedure g_stackframe_entry(list : paasmoutput;localsize : longint);virtual;
          procedure g_maybe_loadself(list : paasmoutput);virtual;

          {********************************************************}
          { these methods can be overriden for extra functionality }

          { the following methods do nothing: }
          procedure g_interrupt_stackframe_entry(list : paasmoutput);virtual;
          procedure g_interrupt_stackframe_exit(list : paasmoutput);virtual;

          procedure g_profilecode(list : paasmoutput);virtual;
          procedure g_stackcheck(list : paasmoutput;stackframesize : longint);virtual;

          { passing parameters, per default the parameter is pushed }
          { nr gives the number of the parameter (enumerated from   }
          { left to right), this allows to move the parameter to    }
          { register, if the cpu supports register calling          }
          { conventions                                             }
          procedure a_param_reg(list : paasmoutput;r : tregister;nr : longint);virtual;
          procedure a_param_const8(list : paasmoutput;b : byte;nr : longint);virtual;
          procedure a_param_const16(list : paasmoutput;w : word;nr : longint);virtual;
          procedure a_param_const32(list : paasmoutput;l : longint;nr : longint);virtual;
          procedure a_param_const64(list : paasmoutput;q : qword;nr : longint);virtual;
       end;

    var
       cg : pcg; { this is the main code generator class }

  implementation

    uses
       globals,globtype,options,files,gdb,systems,
       ppu,cgbase,temp_gen,verbose,types
{$ifdef i386}
       ,tgeni386
{$endif i386}
       ;

    constructor tcg.init;

      begin
      end;

    destructor tcg.done;

      begin
      end;

{*****************************************************************************
                  per default, this methods nothing, can overriden
*****************************************************************************}

    procedure tcg.g_interrupt_stackframe_entry(list : paasmoutput);

      begin
      end;

    procedure tcg.g_interrupt_stackframe_exit(list : paasmoutput);

      begin
      end;

    procedure tcg.g_profilecode(list : paasmoutput);

      begin
      end;

    procedure tcg.a_param_reg(list : paasmoutput;r : tregister;nr : longint);

      begin
         a_push_reg(list,r);
      end;

    procedure tcg.a_param_const8(list : paasmoutput;b : byte;nr : longint);

      begin
         {!!!!!!!! a_push_const8(list,b); }
      end;

    procedure tcg.a_param_const16(list : paasmoutput;w : word;nr : longint);

      begin
         {!!!!!!!! a_push_const16(list,w); }
      end;

    procedure tcg.a_param_const32(list : paasmoutput;l : longint;nr : longint);

      begin
         {!!!!!!!! a_push_const32(list,l); }
      end;

    procedure tcg.a_param_const64(list : paasmoutput;q : qword;nr : longint);

      begin
         {!!!!!!!! a_push_const64(list,q); }
      end;

    procedure tcg.g_stackcheck(list : paasmoutput;stackframesize : longint);

      begin
         a_param_const32(list,stackframesize,1);
         a_call_name_ext(list,'FPC_STACKCHECK',0,EXT_NEAR);
      end;

    procedure tcg.a_call_name_ext(list : paasmoutput;const s : string;
      offset : longint;m : texternal_typ);

      begin
         a_call_name(list,s,offset);
         concat_external(s,m);
      end;

{*****************************************************************************
                         String helper routines
*****************************************************************************}

    procedure tcg.g_removetemps(list : paasmoutput;p : plinkedlist);

      var
         hp : ptemptodestroy;
         pushedregs : tpushed;

      begin
         hp:=ptemptodestroy(p^.first);
         if not(assigned(hp)) then
           exit;
         pushusedregisters(pushedregs,$ff);
         while assigned(hp) do
           begin
              if is_ansistring(hp^.typ) then
                begin
                   g_decransiref(hp^.address);
                   ungetiftemp(hp^.address);
                end;
              hp:=ptemptodestroy(hp^.next);
           end;
         popusedregisters(pushedregs);
      end;

    procedure tcg.g_decransiref(const ref : treference);

      begin
         {!!!!!!!!!}
         { emitpushreferenceaddr(exprasmlist,ref);
         emitcall('FPC_ANSISTR_DECR_REF',true); }
      end;

{*****************************************************************************
                  Code generation for subroutine entry- and exit code
 *****************************************************************************}

    { generates the code for initialisation of local data }
    procedure tcg.g_initialize_data(p : psym);

      var
         r : preference;
         hr : treference;

      begin
{$ifdef dummy}
         if (p^.typ=varsym) and
            assigned(pvarsym(p)^.definition) and
            pvarsym(p)^.definition^.needs_inittable and
            not((pvarsym(p)^.definition^.deftype=objectdef) and
              pobjectdef(pvarsym(p)^.definition)^.isclass) then
           begin
              if is_ansistring(pvarsym(p)^.definition) or
                is_widestring(pvarsym(p)^.definition) then
                begin
                   new(r);
                   reset_reference(r^);
                   if p^.owner^.symtabletype=localsymtable then
                     begin
                        r^.base:=procinfo.framepointer;
                        r^.offset:=-pvarsym(p)^.address;
                     end
                   else
                     r^.symbol:=stringdup(pvarsym(p)^.mangledname);
                   curlist^.concat(new(pai386,op_const_ref(A_MOV,S_L,0,r)));
                end
              else
                begin
                   reset_reference(hr);
                   hr.symbol:=stringdup(lab2str(pvarsym(p)^.definition^.get_inittable_label));
                   emitpushreferenceaddr(curlist,hr);
                   clear_reference(hr);
                   if p^.owner^.symtabletype=localsymtable then
                     begin
                        hr.base:=procinfo.framepointer;
                        hr.offset:=-pvarsym(p)^.address;
                     end
                   else
                     begin
                        hr.symbol:=stringdup(pvarsym(p)^.mangledname);
                     end;
                   emitpushreferenceaddr(curlist,hr);
                   clear_reference(hr);
                   curlist^.concat(new(pai386,
                     op_csymbol(A_CALL,S_NO,newcsymbol('FPC_INITIALIZE',0))));
                   if not(cs_compilesystem in aktmoduleswitches) then
                     concat_external('FPC_INITIALIZE',EXT_NEAR);
                end;
           end;
{$endif dummy}
      end;

    { generates the code for incrementing the reference count of parameters }
    procedure tcg.g_incr_data(p : psym);

      var
         hr : treference;

      begin
{$ifdef dummy}
         if (p^.typ=varsym) and
            pvarsym(p)^.definition^.needs_inittable and
            ((pvarsym(p)^.varspez=vs_value) {or
             (pvarsym(p)^.varspez=vs_const) and
             not(dont_copy_const_param(pvarsym(p)^.definition))}) and
            not((pvarsym(p)^.definition^.deftype=objectdef) and
              pobjectdef(pvarsym(p)^.definition)^.isclass) then
           begin
              reset_reference(hr);
              hr.symbol:=stringdup(lab2str(pvarsym(p)^.definition^.get_inittable_label));
              emitpushreferenceaddr(curlist,hr);
              clear_reference(hr);
              hr.base:=procinfo.framepointer;
              hr.offset:=pvarsym(p)^.address+procinfo.call_offset;

              emitpushreferenceaddr(curlist,hr);
              clear_reference(hr);

              curlist^.concat(new(pai386,
                op_csymbol(A_CALL,S_NO,newcsymbol('FPC_ADDREF',0))));
              if not (cs_compilesystem in aktmoduleswitches) then
                concat_external('FPC_ADDREF',EXT_NEAR);
           end;
{$endif}
      end;

    { generates the code for finalisation of local data }
    procedure tcg.g_finalize_data(p : psym);

      var
         hr : treference;

      begin
{$ifdef dummy}
         if (p^.typ=varsym) and
            assigned(pvarsym(p)^.definition) and
            pvarsym(p)^.definition^.needs_inittable and
            not((pvarsym(p)^.definition^.deftype=objectdef) and
              pobjectdef(pvarsym(p)^.definition)^.isclass) then
           begin
              { not all kind of parameters need to be finalized  }
              if (p^.owner^.symtabletype=parasymtable) and
                ((pvarsym(p)^.varspez=vs_var)  or
                 (pvarsym(p)^.varspez=vs_const) { and
                 (dont_copy_const_param(pvarsym(p)^.definition)) } ) then
                exit;
              reset_reference(hr);
              hr.symbol:=stringdup(lab2str(pvarsym(p)^.definition^.get_inittable_label));
              emitpushreferenceaddr(curlist,hr);
              clear_reference(hr);
              case p^.owner^.symtabletype of
                 localsymtable:
                   begin
                      hr.base:=procinfo.framepointer;
                      hr.offset:=-pvarsym(p)^.address;
                   end;
                 parasymtable:
                   begin
                      hr.base:=procinfo.framepointer;
                      hr.offset:=pvarsym(p)^.address+procinfo.call_offset;
                   end;
                 else
                   hr.symbol:=stringdup(pvarsym(p)^.mangledname);
              end;
              emitpushreferenceaddr(curlist,hr);
              clear_reference(hr);
              curlist^.concat(new(pai386,
                op_csymbol(A_CALL,S_NO,newcsymbol('FPC_FINALIZE',0))));
              if not (cs_compilesystem in aktmoduleswitches) then
              concat_external('FPC_FINALIZE',EXT_NEAR);
           end;
{$endif dummy}
      end;


    { generates the code to make local copies of the value parameters }
  {$ifndef VALUEPARA}
    procedure tcg.g_copyopenarrays(p : psym);
  {$else}
    procedure tcg.g_copyvalueparas(p : psym);
  {$endif}
      var
  {$ifdef VALUEPARA}
        href1,href2 : treference;
  {$endif}
        r    : preference;
        len  : longint;
        opsize : topsize;
        oldexprasmlist : paasmoutput;
      begin
{$ifdef dummy}
         if (p^.typ=varsym) and
  {$ifdef VALUEPARA}
            (pvarsym(p)^.varspez=vs_value) and
            (push_addr_param(pvarsym(p)^.definition)) then
  {$else}
            (pvarsym(p)^.varspez=vs_value) then
  {$endif}
          begin
            oldexprasmlist:=exprasmlist;
            exprasmlist:=curlist;
  {$ifdef VALUEPARA}
  {$ifdef GDB}
            if (cs_debuginfo in aktmoduleswitches) and
               (exprasmlist^.first=exprasmlist^.last) then
              exprasmlist^.concat(new(pai_force_line,init));
  {$endif GDB}
  {$endif}
            if is_open_array(pvarsym(p)^.definition) then
             begin
                { get stack space }
                new(r);
                reset_reference(r^);
                r^.base:=procinfo.framepointer;
                r^.offset:=pvarsym(p)^.address+4+procinfo.call_offset;
                curlist^.concat(new(pai386,
                  op_ref_reg(A_MOV,S_L,r,R_EDI)));

                curlist^.concat(new(pai386,
                  op_reg(A_INC,S_L,R_EDI)));

                curlist^.concat(new(pai386,
                  op_const_reg(A_IMUL,S_L,
                  parraydef(pvarsym(p)^.definition)^.definition^.size,R_EDI)));

                curlist^.concat(new(pai386,
                  op_reg_reg(A_SUB,S_L,R_EDI,R_ESP)));
                { load destination }
                curlist^.concat(new(pai386,
                  op_reg_reg(A_MOV,S_L,R_ESP,R_EDI)));

                { don't destroy the registers! }
                curlist^.concat(new(pai386,
                  op_reg(A_PUSH,S_L,R_ECX)));
                curlist^.concat(new(pai386,
                  op_reg(A_PUSH,S_L,R_ESI)));

                { load count }
                new(r);
                reset_reference(r^);
                r^.base:=procinfo.framepointer;
                r^.offset:=pvarsym(p)^.address+4+procinfo.call_offset;
                curlist^.concat(new(pai386,
                  op_ref_reg(A_MOV,S_L,r,R_ECX)));

                { load source }
                new(r);
                reset_reference(r^);
                r^.base:=procinfo.framepointer;
                r^.offset:=pvarsym(p)^.address+procinfo.call_offset;
                curlist^.concat(new(pai386,
                  op_ref_reg(A_MOV,S_L,r,R_ESI)));

                { scheduled .... }
                curlist^.concat(new(pai386,
                  op_reg(A_INC,S_L,R_ECX)));

                { calculate size }
                len:=parraydef(pvarsym(p)^.definition)^.definition^.size;
                if (len and 3)=0 then
                 begin
                   opsize:=S_L;
                   len:=len shr 2;
                 end
                else
                 if (len and 1)=0 then
                  begin
                    opsize:=S_W;
                    len:=len shr 1;
                  end;

                curlist^.concat(new(pai386,
                  op_const_reg(A_IMUL,S_L,len,R_ECX)));
                curlist^.concat(new(pai386,
                  op_none(A_REP,S_NO)));
                curlist^.concat(new(pai386,
                  op_none(A_MOVS,opsize)));

                curlist^.concat(new(pai386,
                  op_reg(A_POP,S_L,R_ESI)));
                curlist^.concat(new(pai386,
                  op_reg(A_POP,S_L,R_ECX)));

                { patch the new address }
                new(r);
                reset_reference(r^);
                r^.base:=procinfo.framepointer;
                r^.offset:=pvarsym(p)^.address+procinfo.call_offset;
                curlist^.concat(new(pai386,
                  op_reg_ref(A_MOV,S_L,R_ESP,r)));
             end
  {$ifdef VALUEPARA}
            else
             if is_shortstring(pvarsym(p)^.definition) then
              begin
                reset_reference(href1);
                href1.base:=procinfo.framepointer;
                href1.offset:=pvarsym(p)^.address+procinfo.call_offset;
                reset_reference(href2);
                href2.base:=procinfo.framepointer;
                href2.offset:=-pvarsym(p)^.localaddress;
                copyshortstring(href2,href1,pstringdef(pvarsym(p)^.definition)^.len,true);
              end
             else
              begin
                reset_reference(href1);
                href1.base:=procinfo.framepointer;
                href1.offset:=pvarsym(p)^.address+procinfo.call_offset;
                reset_reference(href2);
                href2.base:=procinfo.framepointer;
                href2.offset:=-pvarsym(p)^.localaddress;
                concatcopy(href1,href2,pvarsym(p)^.definition^.size,true,true);
              end;
  {$else}
            ;
  {$endif}
            exprasmlist:=oldexprasmlist;
          end;
{$endif dummy}
      end;

    { wrappers for the methods, because TP doesn't know procedures }
    { of objects                                                   }

    procedure _copyopenarrays(s : psym);{$ifndef FPC}far;{$endif}

      begin
         cg^.g_copyopenarrays(s);
      end;

    procedure _finalize_data(s : psym);{$ifndef FPC}far;{$endif}

      begin
         cg^.g_finalize_data(s);
      end;

    procedure _incr_data(s : psym);{$ifndef FPC}far;{$endif}

      begin
         cg^.g_incr_data(s);
      end;
    procedure _initialize_data(s : psym);{$ifndef FPC}far;{$endif}

      begin
         cg^.g_initialize_data(s);
      end;

    { generates the entry code for a procedure }
    procedure tcg.g_entrycode(list : paasmoutput;const proc_names:Tstringcontainer;make_global:boolean;
       stackframe:longint;var parasize:longint;var nostackframe:boolean;
       inlined : boolean);

      var
         hs : string;
         hp : pused_unit;
         initcode : taasmoutput;
{$ifdef GDB}
         stab_function_name : Pai_stab_function_name;
{$endif GDB}
         hr : treference;
         r : tregister;

      begin
         { Align }
         if (not inlined) then
           begin
              { gprof uses 16 byte granularity !! }
              if (cs_profile in aktmoduleswitches) then
                list^.insert(new(pai_align,init_op(16,$90)))
              else
                if not(cs_littlesize in aktglobalswitches) then
                  list^.insert(new(pai_align,init(4)));
          end;
         { save registers on cdecl }
         if ((aktprocsym^.definition^.options and pocdecl)<>0) then
           begin
              for r:=firstregister to lastregister do
                begin
                   if (r in registers_saved_on_cdecl) then
                     if (r in general_registers) then
                       begin
                          if not(r in unused) then
                            a_push_reg(list,r)
                       end
                     else
                       a_push_reg(list,r);
                end;
           end;
        { omit stack frame ? }
        if not inlined then
          if procinfo.framepointer=stack_pointer then
            begin
               CGMessage(cg_d_stackframe_omited);
               nostackframe:=true;
               if (aktprocsym^.definition^.options and (pounitinit or poproginit or pounitfinalize)<>0) then
                 parasize:=0
               else
                 parasize:=aktprocsym^.definition^.parast^.datasize+procinfo.call_offset-4;
            end
          else
            begin
               if (aktprocsym^.definition^.options and (pounitinit or poproginit or pounitfinalize)<>0) then
                 parasize:=0
               else
                 parasize:=aktprocsym^.definition^.parast^.datasize+procinfo.call_offset-8;
               nostackframe:=false;

               if (aktprocsym^.definition^.options and pointerrupt)<>0 then
                 g_interrupt_stackframe_entry(list);

               g_stackframe_entry(list,stackframe);

               if (cs_check_stack in aktlocalswitches) and
                 (tf_supports_stack_checking in target_info.flags) then
                 g_stackcheck(@initcode,stackframe);
            end;

         if cs_profile in aktmoduleswitches then
           g_profilecode(@initcode);
          if (not inlined) and ((aktprocsym^.definition^.options and poproginit)<>0) then
            begin

              { needs the target a console flags ? }
              if tf_needs_isconsole in target_info.flags then
                begin
                   hr.symbol:=stringdup('U_'+target_info.system_unit+'_ISCONSOLE');
                   if apptype=at_cui then
                     a_load_const8_ref(list,1,hr)
                   else
                     a_load_const8_ref(list,0,hr);
                   stringdispose(hr.symbol);
                end;

              hp:=pused_unit(usedunits.first);
              while assigned(hp) do
                begin
                   { call the unit init code and make it external }
                   if (hp^.u^.flags and uf_init)<>0 then
                     a_call_name_ext(list,
                       'INIT$$'+hp^.u^.modulename^,0,EXT_NEAR);
                    hp:=Pused_unit(hp^.next);
                end;
           end;

         { a constructor needs a help procedure }
         if (aktprocsym^.definition^.options and poconstructor)<>0 then
           begin
             if procinfo._class^.isclass then
               begin
                 list^.insert(new(pai_labeled,init(A_JZ,quickexitlabel)));
                 list^.insert(new(pai386,op_csymbol(A_CALL,S_NO,
                   newcsymbol('FPC_NEW_CLASS',0))));
                 concat_external('FPC_NEW_CLASS',EXT_NEAR);
               end
             else
               begin
                 list^.insert(new(pai_labeled,init(A_JZ,quickexitlabel)));
                 list^.insert(new(pai386,op_csymbol(A_CALL,S_NO,
                   newcsymbol('FPC_HELP_CONSTRUCTOR',0))));
                 list^.insert(new(pai386,op_const_reg(A_MOV,S_L,procinfo._class^.vmt_offset,R_EDI)));
                 concat_external('FPC_HELP_CONSTRUCTOR',EXT_NEAR);
               end;
           end;

  {$ifdef GDB}
         if (cs_debuginfo in aktmoduleswitches) then
           list^.insert(new(pai_force_line,init));
  {$endif GDB}

         { initialize return value }
         if is_ansistring(procinfo.retdef) or
           is_widestring(procinfo.retdef) then
           begin
              reset_reference(hr);
              hr.offset:=procinfo.retoffset;
              hr.base:=procinfo.framepointer;
              a_load_const32_ref(list,0,hr);
           end;

         { generate copies of call by value parameters }
         if (aktprocsym^.definition^.options and poassembler=0) then
           begin
  {$ifndef VALUEPARA}
              aktprocsym^.definition^.parast^.foreach(_copyopenarrays);
  {$else}
              aktprocsym^.definition^.parast^.foreach(_copyvalueparas);
  {$endif}
           end;

         { initialisizes local data }
         aktprocsym^.definition^.localst^.foreach(_initialize_data);
         { add a reference to all call by value/const parameters }
         aktprocsym^.definition^.parast^.foreach(_incr_data);

         if (cs_profile in aktmoduleswitches) or
           (aktprocsym^.definition^.owner^.symtabletype=globalsymtable) or
           (assigned(procinfo._class) and (procinfo._class^.owner^.symtabletype=globalsymtable)) then
           make_global:=true;
         if not inlined then
           begin
              hs:=proc_names.get;

  {$ifdef GDB}
              if (cs_debuginfo in aktmoduleswitches) and target_os.use_function_relative_addresses then
                stab_function_name := new(pai_stab_function_name,init(strpnew(hs)));
  {$endif GDB}

              { insert the names for the procedure }
              while hs<>'' do
                begin
                   if make_global then
                     list^.insert(new(pai_symbol,init_global(hs)))
                   else
                     list^.insert(new(pai_symbol,init(hs)));

  {$ifdef GDB}
                   if (cs_debuginfo in aktmoduleswitches) then
                     begin
                       if target_os.use_function_relative_addresses then
                         list^.insert(new(pai_stab_function_name,init(strpnew(hs))));
                    end;
  {$endif GDB}

                  hs:=proc_names.get;
               end;
          end;

  {$ifdef GDB}
         if (not inlined) and (cs_debuginfo in aktmoduleswitches) then
           begin
              if target_os.use_function_relative_addresses then
                  list^.insert(stab_function_name);
              if make_global or ((procinfo.flags and pi_is_global) <> 0) then
                  aktprocsym^.is_global := True;
              list^.insert(new(pai_stabs,init(aktprocsym^.stabstring)));
              aktprocsym^.isstabwritten:=true;
            end;
  {$endif GDB}
    end;

  procedure tcg.g_exitcode(list : paasmoutput;parasize:longint;nostackframe,inlined:boolean);
{$ifdef GDB}
    var
       mangled_length : longint;
       p : pchar;
{$endif GDB}
  begin
{$ifdef dummy}
      { !!!! insert there automatic destructors }
      curlist:=list;
      if aktexitlabel^.is_used then
        list^.insert(new(pai_label,init(aktexitlabel)));

      { call the destructor help procedure }
      if (aktprocsym^.definition^.options and podestructor)<>0 then
        begin
          if procinfo._class^.isclass then
            begin
              list^.insert(new(pai386,op_csymbol(A_CALL,S_NO,
                newcsymbol('FPC_DISPOSE_CLASS',0))));
              concat_external('FPC_DISPOSE_CLASS',EXT_NEAR);
            end
          else
            begin
              list^.insert(new(pai386,op_csymbol(A_CALL,S_NO,
                newcsymbol('FPC_HELP_DESTRUCTOR',0))));
              list^.insert(new(pai386,op_const_reg(A_MOV,S_L,procinfo._class^.vmt_offset,R_EDI)));
              concat_external('FPC_HELP_DESTRUCTOR',EXT_NEAR);
            end;
        end;

      { finalize local data }
      aktprocsym^.definition^.localst^.foreach(finalize_data);

      { finalize paras data }
      if assigned(aktprocsym^.definition^.parast) then
        aktprocsym^.definition^.parast^.foreach(finalize_data);

      { call __EXIT for main program }
      if (not DLLsource) and (not inlined) and ((aktprocsym^.definition^.options and poproginit)<>0) then
       begin
         list^.concat(new(pai386,op_csymbol(A_CALL,S_NO,newcsymbol('FPC_DO_EXIT',0))));
         concat_external('FPC_DO_EXIT',EXT_NEAR);
       end;

      { handle return value }
      if (aktprocsym^.definition^.options and poassembler)=0 then
          if (aktprocsym^.definition^.options and poconstructor)=0 then
            handle_return_value(list,inlined)
          else
              begin
                  { successful constructor deletes the zero flag }
                  { and returns self in eax                      }
                  list^.concat(new(pai_label,init(quickexitlabel)));
                  { eax must be set to zero if the allocation failed !!! }
                  list^.concat(new(pai386,op_reg_reg(A_MOV,S_L,R_ESI,R_EAX)));
                  list^.concat(new(pai386,op_reg_reg(A_OR,S_L,R_EAX,R_EAX)));
              end;

      { stabs uses the label also ! }
      if aktexit2label^.is_used or
         ((cs_debuginfo in aktmoduleswitches) and not inlined) then
        list^.concat(new(pai_label,init(aktexit2label)));
      { gives problems for long mangled names }
      {list^.concat(new(pai_symbol,init(aktprocsym^.definition^.mangledname+'_end')));}

      { should we restore edi ? }
      { for all i386 gcc implementations }
      if ((aktprocsym^.definition^.options and pocdecl)<>0) then
        begin
          list^.insert(new(pai386,op_reg(A_POP,S_L,R_EDI)));
          list^.insert(new(pai386,op_reg(A_POP,S_L,R_ESI)));
          if (aktprocsym^.definition^.usedregisters and ($80 shr byte(R_EBX)))<>0 then
           list^.insert(new(pai386,op_reg(A_POP,S_L,R_EBX)));
          { here we could reset R_EBX
            but that is risky because it only works
            if genexitcode is called after genentrycode
            so lets skip this for the moment PM
          aktprocsym^.definition^.usedregisters:=
            aktprocsym^.definition^.usedregisters or not ($80 shr byte(R_EBX));
          }
        end;

      if not(nostackframe) and not inlined then
          list^.concat(new(pai386,op_none(A_LEAVE,S_NO)));
      { parameters are limited to 65535 bytes because }
      { ret allows only imm16                         }
      if (parasize>65535) and not(aktprocsym^.definition^.options and poclearstack<>0) then
       CGMessage(cg_e_parasize_too_big);

      { at last, the return is generated }

      if not inlined then
      if (aktprocsym^.definition^.options and pointerrupt)<>0 then
          generate_interrupt_stackframe_exit
      else
       begin
       {Routines with the poclearstack flag set use only a ret.}
       { also routines with parasize=0           }
         if (parasize=0) or (aktprocsym^.definition^.options and poclearstack<>0) then
          list^.concat(new(pai386,op_none(A_RET,S_NO)))
         else
          list^.concat(new(pai386,op_const(A_RET,S_NO,parasize)));
       end;

{$ifdef GDB}
      if (cs_debuginfo in aktmoduleswitches) and not inlined  then
          begin
              aktprocsym^.concatstabto(list);
              if assigned(procinfo._class) then
                  list^.concat(new(pai_stabs,init(strpnew(
                   '"$t:v'+procinfo._class^.numberstring+'",'+
                   tostr(N_PSYM)+',0,0,'+tostr(procinfo.esi_offset)))));

              if (porddef(aktprocsym^.definition^.retdef) <> voiddef) then
                if ret_in_param(aktprocsym^.definition^.retdef) then
                  list^.concat(new(pai_stabs,init(strpnew(
                   '"'+aktprocsym^.name+':X*'+aktprocsym^.definition^.retdef^.numberstring+'",'+
                   tostr(N_PSYM)+',0,0,'+tostr(procinfo.retoffset)))))
                else
                  list^.concat(new(pai_stabs,init(strpnew(
                   '"'+aktprocsym^.name+':X'+aktprocsym^.definition^.retdef^.numberstring+'",'+
                   tostr(N_PSYM)+',0,0,'+tostr(procinfo.retoffset)))));

              mangled_length:=length(aktprocsym^.definition^.mangledname);
              getmem(p,mangled_length+50);
              strpcopy(p,'192,0,0,');
              strpcopy(strend(p),aktprocsym^.definition^.mangledname);
              list^.concat(new(pai_stabn,init(strnew(p))));
              {list^.concat(new(pai_stabn,init(strpnew('192,0,0,'
               +aktprocsym^.definition^.mangledname))));
              p[0]:='2';p[1]:='2';p[2]:='4';
              strpcopy(strend(p),'_end');}
              freemem(p,mangled_length+50);
              list^.concat(new(pai_stabn,init(
                strpnew('224,0,0,'+lab2str(aktexit2label)))));
               { strpnew('224,0,0,'
               +aktprocsym^.definition^.mangledname+'_end'))));}
          end;
{$endif GDB}
      curlist:=nil;
{$endif dummy}
  end;
{*****************************************************************************
                       some abstract definitions
 ****************************************************************************}

    procedure tcg.a_push_reg(list : paasmoutput;r : tregister);

      begin
         abstract;
      end;

    procedure tcg.a_call_name(list : paasmoutput;const s : string;
      offset : longint);

      begin
         abstract;
      end;

    procedure tcg.a_load_const8_ref(list : paasmoutput;b : byte;const ref : treference);

      begin
         abstract;
      end;

    procedure tcg.a_load_const16_ref(list : paasmoutput;w : word;const ref : treference);

      begin
         abstract;
      end;

    procedure tcg.a_load_const32_ref(list : paasmoutput;l : longint;const ref : treference);

      begin
         abstract;
      end;

    procedure tcg.a_load_const64_ref(list : paasmoutput;q : qword;const ref : treference);

      begin
         abstract;
      end;

    procedure tcg.g_stackframe_entry(list : paasmoutput;localsize : longint);

      begin
         abstract;
      end;

    procedure tcg.g_maybe_loadself(list : paasmoutput);

      begin
         abstract;
      end;

end.
{
  $Log$
  Revision 1.5  1999-01-23 23:29:46  florian
    * first running version of the new code generator
    * when compiling exceptions under Linux fixed

  Revision 1.4  1999/01/13 22:52:36  florian
    + YES, finally the new code generator is compilable, but it doesn't run yet :(

  Revision 1.3  1998/12/26 15:20:30  florian
    + more changes for the new version

  Revision 1.2  1998/12/15 22:18:55  florian
    * some code added

  Revision 1.1  1998/12/15 16:32:58  florian
    + first version, derived from old routines

}

