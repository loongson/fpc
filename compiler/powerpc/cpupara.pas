{
    $Id$
    Copyright (c) 2002 by Florian Klaempfl

    PowerPC specific calling conventions

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
{ PowerPC specific calling conventions are handled by this unit
}
unit cpupara;

{$i fpcdefs.inc}

  interface

    uses
       globtype,
       cclasses,
       aasmtai,
       cpubase,cpuinfo,
       symconst,symbase,symtype,symdef,paramgr,cgbase;

    type
       tppcparamanager = class(tparamanager)
          function get_volatile_registers_int(calloption : tproccalloption):tcpuregisterset;override;
          function get_volatile_registers_fpu(calloption : tproccalloption):tcpuregisterset;override;
          function push_addr_param(varspez:tvarspez;def : tdef;calloption : tproccalloption) : boolean;override;
          function getintparaloc(calloption : tproccalloption; nr : longint) : tparalocation;override;
          function create_paraloc_info(p : tabstractprocdef; side: tcallercallee):longint;override;
          function create_varargs_paraloc_info(p : tabstractprocdef; varargspara:tvarargspara):longint;override;
         private
           procedure init_values(var curintreg, curfloatreg, curmmreg: tsuperregister; var cur_stack_offset: aword);
           function create_paraloc_info_intern(p : tabstractprocdef; side: tcallercallee; firstpara: tparaitem;
               var curintreg, curfloatreg, curmmreg: tsuperregister; var cur_stack_offset: aword):longint;
           function parseparaloc(p : tparaitem;const s : string) : boolean;override;
       end;

  implementation

    uses
       verbose,systems,
       procinfo,
       rgobj,
       defutil,symsym,cpupi;


    function tppcparamanager.get_volatile_registers_int(calloption : tproccalloption):tcpuregisterset;
      begin
        result := [RS_R3..RS_R12];
      end;


    function tppcparamanager.get_volatile_registers_fpu(calloption : tproccalloption):tcpuregisterset;
      begin
        case target_info.abi of
          abi_powerpc_aix:
            result := [RS_F0..RS_F13];
          abi_powerpc_sysv:
            {$warning: the 64bit sysv abi also uses RS_F0..RS_F13 like the aix abi above }
            result := [RS_F0..RS_F8];
          else
            internalerror(2003091401);
        end;
      end;


    function tppcparamanager.getintparaloc(calloption : tproccalloption; nr : longint) : tparalocation;

      begin
         fillchar(result,sizeof(tparalocation),0);
         result.lochigh:=LOC_INVALID;
         if nr<1 then
           internalerror(2002070801)
         else if nr<=8 then
           begin
              result.loc:=LOC_REGISTER;
              result.register:=newreg(R_INTREGISTER,RS_R2+nr,R_SUBWHOLE);
           end
         else
           begin
              result.loc:=LOC_REFERENCE;
              result.reference.index:=NR_STACK_POINTER_REG;
              result.reference.offset:=(nr-8)*4;
           end;
         result.size := OS_INT;
      end;


    function getparaloc(p : tdef) : tcgloc;

      begin
         { Later, the LOC_REFERENCE is in most cases changed into LOC_REGISTER
           if push_addr_param for the def is true
         }
         case p.deftype of
            orddef:
              getparaloc:=LOC_REGISTER;
            floatdef:
              getparaloc:=LOC_FPUREGISTER;
            enumdef:
              getparaloc:=LOC_REGISTER;
            pointerdef:
              getparaloc:=LOC_REGISTER;
            formaldef:
              getparaloc:=LOC_REGISTER;
            classrefdef:
              getparaloc:=LOC_REGISTER;
            recorddef:
              getparaloc:=LOC_REFERENCE;
            objectdef:
              if is_object(p) then
                getparaloc:=LOC_REFERENCE
              else
                getparaloc:=LOC_REGISTER;
            stringdef:
              if is_shortstring(p) or is_longstring(p) then
                getparaloc:=LOC_REFERENCE
              else
                getparaloc:=LOC_REGISTER;
            procvardef:
              if (po_methodpointer in tprocvardef(p).procoptions) then
                getparaloc:=LOC_REFERENCE
              else
                getparaloc:=LOC_REGISTER;
            filedef:
              getparaloc:=LOC_REGISTER;
            arraydef:
              getparaloc:=LOC_REFERENCE;
            setdef:
              if is_smallset(p) then
                getparaloc:=LOC_REGISTER
              else
                getparaloc:=LOC_REFERENCE;
            variantdef:
              getparaloc:=LOC_REFERENCE;
            { avoid problems with errornous definitions }
            errordef:
              getparaloc:=LOC_REGISTER;
            else
              internalerror(2002071001);
         end;
      end;

    function tppcparamanager.push_addr_param(varspez:tvarspez;def : tdef;calloption : tproccalloption) : boolean;
      begin
        { var,out always require address }
        if varspez in [vs_var,vs_out] then
          begin
            result:=true;
            exit;
          end;
        case def.deftype of
          recorddef:
            result:=true;
          arraydef:
            result:=(tarraydef(def).highrange>=tarraydef(def).lowrange) or
                             is_open_array(def) or
                             is_array_of_const(def) or
                             is_array_constructor(def);
          setdef :
            result:=(tsetdef(def).settype<>smallset);
          stringdef :
            result:=tstringdef(def).string_typ in [st_shortstring,st_longstring];
          procvardef :
            result:=po_methodpointer in tprocvardef(def).procoptions;
          else
            result:=inherited push_addr_param(varspez,def,calloption);
        end;
      end;


    procedure tppcparamanager.init_values(var curintreg, curfloatreg, curmmreg: tsuperregister; var cur_stack_offset: aword);
      begin
        case target_info.abi of
          abi_powerpc_aix:
            cur_stack_offset:=24;
          abi_powerpc_sysv:
            cur_stack_offset:=8;
          else
            internalerror(2003051901);
        end;
        curintreg:=RS_R3;
        curfloatreg:=RS_F1;
        curmmreg:=RS_M1;
      end;


    function tppcparamanager.create_paraloc_info(p : tabstractprocdef; side: tcallercallee):longint;

      var
        paraloc : tparalocation;
        cur_stack_offset: aword;
        curintreg, curfloatreg, curmmreg: tsuperregister;
      begin
        init_values(curintreg,curfloatreg,curmmreg,cur_stack_offset);

        result := create_paraloc_info_intern(p,side,tparaitem(p.para.first),curintreg,curfloatreg,curmmreg,cur_stack_offset);

        { Function return }
        fillchar(paraloc,sizeof(tparalocation),0);
        paraloc.alignment:= std_param_align;
        paraloc.size:=def_cgsize(p.rettype.def);
        paraloc.lochigh:=LOC_INVALID;
        { Return in FPU register? }
        if p.rettype.def.deftype=floatdef then
          begin
            paraloc.loc:=LOC_FPUREGISTER;
            paraloc.register:=NR_FPU_RESULT_REG;
          end
        else
         { Return in register? }
         if not ret_in_param(p.rettype.def,p.proccalloption) then
          begin
            paraloc.loc:=LOC_REGISTER;
{$ifndef cpu64bit}
            if paraloc.size in [OS_64,OS_S64] then
             begin
               paraloc.register64.reglo:=NR_FUNCTION_RETURN64_LOW_REG;
               paraloc.register64.reghi:=NR_FUNCTION_RETURN64_HIGH_REG;
               paraloc.lochigh:=LOC_REGISTER;
             end
            else
{$endif cpu64bit}
             paraloc.register:=NR_FUNCTION_RETURN_REG;
          end
        else
          begin
            paraloc.loc:=LOC_REFERENCE;
          end;
        p.funcret_paraloc[side]:=paraloc;
      end;



    function tppcparamanager.create_paraloc_info_intern(p : tabstractprocdef; side: tcallercallee; firstpara: tparaitem;
               var curintreg, curfloatreg, curmmreg: tsuperregister; var cur_stack_offset: aword):longint;
      var
         stack_offset: aword;
         nextintreg,nextfloatreg,nextmmreg : tsuperregister;
         paradef : tdef;
         paraloc : tparalocation;
         hp : tparaitem;
         loc : tcgloc;
         is_64bit: boolean;

      procedure assignintreg;

        begin
           if nextintreg<=ord(NR_R10) then
             begin
                paraloc.loc:=LOC_REGISTER;
                paraloc.register:=newreg(R_INTREGISTER,nextintreg,R_SUBNONE);
                inc(nextintreg);
                if target_info.abi=abi_powerpc_aix then
                  inc(stack_offset,4);
             end
           else
              begin
                 paraloc.loc:=LOC_REFERENCE;
                 paraloc.reference.index:=NR_STACK_POINTER_REG;
                 paraloc.reference.offset:=stack_offset;
                 inc(stack_offset,4);
             end;
        end;

      begin
         result:=0;
         nextintreg := curintreg;
         nextfloatreg := curfloatreg;
         nextmmreg := curmmreg;
         stack_offset := cur_stack_offset;

         hp:=firstpara;
         while assigned(hp) do
           begin
              { currently only support C-style array of const }
              if (p.proccalloption in [pocall_cdecl,pocall_cppdecl]) and
                 is_array_of_const(hp.paratype.def) then
                begin
                  { hack: the paraloc must be valid, but is not actually used }
                  hp.paraloc[side].loc := LOC_REGISTER;
                  hp.paraloc[side].lochigh := LOC_INVALID;
                  hp.paraloc[side].register := NR_R0;
                  hp.paraloc[side].size := OS_ADDR;
                  break;
                end;

              if (hp.paratyp in [vs_var,vs_out]) then
                begin
                  paradef := voidpointertype.def;
                  loc := LOC_REGISTER;
                end
              else
                begin
                  paradef := hp.paratype.def;
                  loc:=getparaloc(paradef);
                end;
              { make sure all alignment bytes are 0 as well }
              fillchar(paraloc,sizeof(paraloc),0);
              paraloc.alignment:= std_param_align;
              paraloc.lochigh:=LOC_INVALID;
              case loc of
                 LOC_REGISTER:
                   begin
                      paraloc.size := def_cgsize(paradef);
                      { for things like formaldef }
                      if paraloc.size = OS_NO then
                        paraloc.size := OS_ADDR;
                      is_64bit := paraloc.size in [OS_64,OS_S64];
                      if nextintreg<=(RS_R10-ord(is_64bit))  then
                        begin
                           paraloc.loc:=LOC_REGISTER;
                           if is_64bit then
                             begin
                               if odd(nextintreg-RS_R3) and (target_info.abi=abi_powerpc_sysv) Then
                                 inc(nextintreg);
                               paraloc.registerhigh:=newreg(R_INTREGISTER,nextintreg,R_SUBNONE);
                               paraloc.lochigh:=LOC_REGISTER;
                               inc(nextintreg);
                               if target_info.abi=abi_powerpc_aix then
                                 inc(stack_offset,4);
                             end;
                           paraloc.registerlow:=newreg(R_INTREGISTER,nextintreg,R_SUBNONE);
                           inc(nextintreg);
                           if target_info.abi=abi_powerpc_aix then
                             inc(stack_offset,4);
                        end
                      else
                         begin
                            nextintreg:=RS_R11;
                            paraloc.loc:=LOC_REFERENCE;
                            paraloc.reference.index:=NR_STACK_POINTER_REG;
                            paraloc.reference.offset:=stack_offset;
                            if not is_64bit then
                              inc(stack_offset,4)
                            else
                              inc(stack_offset,8);
                        end;
                   end;
                 LOC_FPUREGISTER:
                   begin
                      paraloc.size:=def_cgsize(paradef);
                      if nextfloatreg<=RS_F10 then
                        begin
                           paraloc.loc:=LOC_FPUREGISTER;
                           paraloc.register:=newreg(R_FPUREGISTER,nextfloatreg,R_SUBWHOLE);
                           inc(nextfloatreg);
                           if target_info.abi=abi_powerpc_aix then
                             inc(stack_offset,8);
                        end
                      else
                         begin
                            {!!!!!!!}
                            paraloc.size:=def_cgsize(paradef);
                            internalerror(2002071004);
                        end;
                   end;
                 LOC_REFERENCE:
                   begin
                      paraloc.size:=OS_ADDR;
                      if push_addr_param(hp.paratyp,paradef,p.proccalloption) or
                        is_open_array(paradef) or
                        is_array_of_const(paradef) then
                        assignintreg
                      else
                        begin
                           paraloc.loc:=LOC_REFERENCE;
                           paraloc.reference.index:=NR_STACK_POINTER_REG;
                           paraloc.reference.offset:=stack_offset;
                           inc(stack_offset,hp.paratype.def.size);
                        end;
                   end;
                 else
                   internalerror(2002071002);
              end;
{
              this is filled in in ncgutil

              if side = calleeside then
                begin
                  if (paraloc.loc = LOC_REFERENCE) then
                    begin
                      if (current_procinfo.procdef <> p) then
                        internalerror(2003112201);
                      inc(paraloc.reference.offset,current_procinfo.calc_stackframe_size);
                    end;
                end;
}
              hp.paraloc[side]:=paraloc;
              hp:=tparaitem(hp.next);
           end;
         curintreg:=nextintreg;
         curfloatreg:=nextfloatreg;
         curmmreg:=nextmmreg;
         cur_stack_offset:=stack_offset;
         result:=cur_stack_offset;
      end;


    function tppcparamanager.create_varargs_paraloc_info(p : tabstractprocdef; varargspara:tvarargspara):longint;
      var
        cur_stack_offset: aword;
        parasize, l: longint;
        curintreg, firstfloatreg, curfloatreg, curmmreg: tsuperregister;
        hp: tparaitem;
        paraloc: tparalocation;
      begin
        init_values(curintreg,curfloatreg,curmmreg,cur_stack_offset);
        firstfloatreg:=curfloatreg;

        result := create_paraloc_info_intern(p,callerside,tparaitem(p.para.first),curintreg,curfloatreg,curmmreg,cur_stack_offset);
        if (p.proccalloption in [pocall_cdecl,pocall_cppdecl]) then
          { just continue loading the parameters in the registers }
          result := create_paraloc_info_intern(p,callerside,tparaitem(varargspara.first),curintreg,curfloatreg,curmmreg,cur_stack_offset)
        else
          begin
            hp := tparaitem(varargspara.first);
            parasize := cur_stack_offset;
            while assigned(hp) do
              begin
                paraloc.size:=def_cgsize(hp.paratype.def);
                paraloc.lochigh:=LOC_INVALID;
                paraloc.loc:=LOC_REFERENCE;
                paraloc.alignment:=4;
                paraloc.reference.index:=NR_STACK_POINTER_REG;
                l:=push_size(hp.paratyp,hp.paratype.def,p.proccalloption);
                paraloc.reference.offset:=parasize;
                parasize:=parasize+l;
                hp.paraloc[callerside]:=paraloc;
                hp:=tparaitem(hp.next);
              end;
            result := parasize;
          end;
        if curfloatreg<>firstfloatreg then
          include(varargspara.varargsinfo,va_uses_float_reg);
      end;


    function tppcparamanager.parseparaloc(p : tparaitem;const s : string) : boolean;
      begin
        result:=false;
        case target_info.system of
          system_powerpc_morphos:
            begin
              p.paraloc[callerside].loc:=LOC_REFERENCE;
              p.paraloc[callerside].lochigh:=LOC_INVALID;
              p.paraloc[callerside].size:=def_cgsize(p.paratype.def);
              p.paraloc[callerside].alignment:=4;
              p.paraloc[callerside].reference.index:=NR_R2;
              { pattern is always uppercase'd }
              if s='D0' then
                p.paraloc[callerside].reference.offset:=0
              else if s='D1' then
                p.paraloc[callerside].reference.offset:=4
              else if s='D2' then
                p.paraloc[callerside].reference.offset:=8
              else if s='D3' then
                p.paraloc[callerside].reference.offset:=12
              else if s='D4' then
                p.paraloc[callerside].reference.offset:=16
              else if s='D5' then
                p.paraloc[callerside].reference.offset:=20
              else if s='D6' then
                p.paraloc[callerside].reference.offset:=24
              else if s='D7' then
                p.paraloc[callerside].reference.offset:=28
              else if s='A0' then
                p.paraloc[callerside].reference.offset:=32
              else if s='A1' then
                p.paraloc[callerside].reference.offset:=36
              else if s='A2' then
                p.paraloc[callerside].reference.offset:=40
              else if s='A3' then
                p.paraloc[callerside].reference.offset:=44
              else if s='A4' then
                p.paraloc[callerside].reference.offset:=48
              else if s='A5' then
                p.paraloc[callerside].reference.offset:=52
              { 'A6' (offset 56) is used by mossyscall as libbase, so API
                never passes parameters in it,
                Indeed, but this allows to declare libbase either explicitly
                or let the compiler insert it }
              else if s='A6' then
                p.paraloc[callerside].reference.offset:=56
              { 'A7' is the stack pointer on 68k, can't be overwritten
                by API calls, so it has no offset }
              else
                exit;
              p.paraloc[calleeside]:=p.paraloc[callerside];
            end;
          else
            internalerror(200404182);
        end;
        result:=true;
      end;


begin
   paramanager:=tppcparamanager.create;
end.
{
  $Log$
  Revision 1.62  2004-05-01 22:05:02  florian
    + added lib support for Amiga/MorphOS syscalls

  Revision 1.61  2004/04/18 23:19:48  karoly
   * added correct offsets for PowerPC/MorphOS location support

  Revision 1.60  2004/04/18 15:22:24  florian
    + location support for arguments, currently PowerPC/MorphOS only

  Revision 1.59  2004/02/19 17:07:42  florian
    * fixed arg. area calculation

  Revision 1.58  2004/02/11 23:18:59  florian
    * fixed to compile the rtl again

  Revision 1.57  2004/01/17 15:55:11  jonas
    * fixed allocation of parameters passed by reference for powerpc in
      callee

  Revision 1.56  2004/01/15 14:01:18  florian
    + x86 instruction tables for x86-64 extended

  Revision 1.55  2003/12/28 22:09:12  florian
    + setting of bit 6 of cr for c var args on ppc implemented

  Revision 1.54  2003/12/28 15:33:06  jonas
    * hopefully fixed varargs (both Pascal- and C-style)

  Revision 1.53  2003/12/16 21:49:47  florian
    * fixed ppc compilation

  Revision 1.52  2003/12/07 22:35:05  florian
    + dummy tppcparamanager.create_varargs_paraloc_info added

  Revision 1.51  2003/11/29 16:27:19  jonas
    * fixed several ppc assembler reader related problems
    * local vars in assembler procedures now start at offset 4
    * fixed second_int_to_bool (apparently an integer can be in  LOC_JUMP??)

  Revision 1.50  2003/10/17 14:52:07  peter
    * fixed ppc build

  Revision 1.49  2003/10/08 21:15:27  olle
    * changed to symbolic const for alignment

  Revision 1.47  2003/10/01 20:34:49  peter
    * procinfo unit contains tprocinfo
    * cginfo renamed to cgbase
    * moved cgmessage to verbose
    * fixed ppc and sparc compiles

  Revision 1.46  2003/09/14 21:56:41  jonas
    + implemented volatile register queries

  Revision 1.45  2003/09/14 16:37:20  jonas
    * fixed some ppc problems

  Revision 1.44  2003/09/03 21:04:14  peter
    * some fixes for ppc

  Revision 1.43  2003/09/03 19:35:24  peter
    * powerpc compiles again

  Revision 1.42  2003/08/11 21:18:20  peter
    * start of sparc support for newra

  Revision 1.41  2003/07/05 20:11:41  jonas
    * create_paraloc_info() is now called separately for the caller and
      callee info
    * fixed ppc cycle

  Revision 1.40  2003/07/02 22:18:04  peter
    * paraloc splitted in callerparaloc,calleeparaloc
    * sparc calling convention updates

  Revision 1.39  2003/06/17 17:27:08  jonas
    - removed allocparaloc/freeparaloc, generic ones are ok now

  Revision 1.38  2003/06/17 16:34:44  jonas
    * lots of newra fixes (need getfuncretparaloc implementation for i386)!
    * renamed all_intregisters to volatile_intregisters and made it
      processor dependent

  Revision 1.37  2003/06/09 14:54:26  jonas
    * (de)allocation of registers for parameters is now performed properly
      (and checked on the ppc)
    - removed obsolete allocation of all parameter registers at the start
      of a procedure (and deallocation at the end)

  Revision 1.36  2003/06/08 10:52:01  jonas
    * zero paraloc tregisters, so that the alignment bytes are 0 (otherwise
      the crc of the ppu files can change between interface and
      implementation)

  Revision 1.35  2003/06/07 18:57:04  jonas
    + added freeintparaloc
    * ppc get/freeintparaloc now check whether the parameter regs are
      properly allocated/deallocated (and get an extra list para)
    * ppc a_call_* now internalerrors if pi_do_call is not yet set
    * fixed lot of missing pi_do_call's

  Revision 1.34  2003/05/30 23:45:49  marco
   * register skipping (aligning) for int64 parameters, sys V abi only.

  Revision 1.33  2003/05/30 22:54:19  marco
   * getfuncretparaloc now uses r3 for highdword and r4 for lo. Doesn't work tho

  Revision 1.32  2003/05/30 22:35:03  marco
   * committed fix that swaps int64 parameters hi and lo.

  Revision 1.31  2003/05/24 11:48:40  jonas
    * added some missing paralocation size settings

  Revision 1.30  2003/05/19 12:15:28  florian
    * fixed calling sequence for subroutines using the aix abi

  Revision 1.29  2003/05/12 20:14:47  florian
    * fixed parameter passing by value of large sets, strings and method pointers

  Revision 1.28  2003/05/11 23:19:32  florian
    * fixed passing of small const arrays and const records, they are always passed by reference

  Revision 1.27  2003/04/26 11:30:59  florian
    * fixed the powerpc to work with the new function result handling

  Revision 1.26  2003/04/23 12:35:35  florian
    * fixed several issues with powerpc
    + applied a patch from Jonas for nested function calls (PowerPC only)
    * ...

  Revision 1.25  2003/04/17 18:52:35  jonas
    * process para's from first to last instead of the other way round

  Revision 1.24  2003/04/16 07:55:07  jonas
    * fixed paralocation for integer var/out parameters

  Revision 1.23  2003/03/11 21:46:24  jonas
    * lots of new regallocator fixes, both in generic and ppc-specific code
      (ppc compiler still can't compile the linux system unit though)

  Revision 1.22  2003/01/09 22:00:53  florian
    * fixed some PowerPC issues

  Revision 1.21  2003/01/09 20:41:10  florian
    * fixed broken PowerPC compiler

  Revision 1.20  2003/01/09 11:22:14  olle
    * made powerpc compiler compile after Daniels Tregister modification

  Revision 1.19  2003/01/08 18:43:58  daniel
   * Tregister changed into a record

  Revision 1.18  2002/12/15 19:22:01  florian
    * fixed some crashes and a rte 201

  Revision 1.17  2002/11/25 17:43:27  peter
    * splitted defbase in defutil,symutil,defcmp
    * merged isconvertable and is_equal into compare_defs(_ext)
    * made operator search faster by walking the list only once

  Revision 1.16  2002/11/18 17:32:01  peter
    * pass proccalloption to ret_in_xxx and push_xxx functions

  Revision 1.15  2002/10/02 13:33:36  jonas
    + set, variant support in getfuncretparaloc

  Revision 1.14  2002/09/28 21:27:16  florian
    + getparaloc supports now sets and variants

  Revision 1.13  2002/09/10 21:28:05  jonas
    * int64 paras are now handled correctly (until the registers are used up
      anyway :)
    * the return location is now initialized correctly
    * fixed bug where ret_in_reg() was called for the procdefinition instead
      of for the result of the procedure

  Revision 1.12  2002/09/09 09:11:37  florian
    - removed passes_parameters_in_reg

  Revision 1.11  2002/09/07 17:54:59  florian
    * first part of PowerPC fixes

  Revision 1.10  2002/09/01 21:04:49  florian
    * several powerpc related stuff fixed

  Revision 1.9  2002/08/31 12:43:31  florian
    * ppc compilation fixed

  Revision 1.8  2002/08/18 10:42:38  florian
    * remaining assembler writer bugs fixed, the errors in the
      system unit are inline assembler problems

  Revision 1.7  2002/08/17 22:09:47  florian
    * result type handling in tcgcal.pass_2 overhauled
    * better tnode.dowrite
    * some ppc stuff fixed

  Revision 1.6  2002/08/13 21:40:58  florian
    * more fixes for ppc calling conventions

  Revision 1.5  2002/07/30 20:50:44  florian
    * the code generator knows now if parameters are in registers

  Revision 1.4  2002/07/28 20:45:22  florian
    + added direct assembler reader for PowerPC

  Revision 1.3  2002/07/26 22:22:10  florian
    * several PowerPC related fixes to get forward with system unit compilation

  Revision 1.2  2002/07/11 14:41:34  florian
    * start of the new generic parameter handling

  Revision 1.1  2002/07/07 09:44:32  florian
    * powerpc target fixed, very simple units can be compiled
}
