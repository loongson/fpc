{
    $Id$
    Copyright (c) 1993-98 by Florian Klaempfl

    Generate i386 assembler for load/assignment nodes

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
unit cg386ld;
interface

    uses
      tree,i386;

    var
       { this is for open arrays and strings        }
       { but be careful, this data is in the        }
       { generated code destroyed quick, and also   }
       { the next call of secondload destroys this  }
       { data                                       }
       { So be careful using the informations       }
       { provided by this variables                 }
       highframepointer : tregister;
       highoffset : longint;

    procedure secondload(var p : ptree);
    procedure secondassignment(var p : ptree);
    procedure secondfuncret(var p : ptree);
    procedure secondarrayconstruct(var p : ptree);


implementation

    uses
      cobjects,verbose,globals,systems,
      symtable,aasm,types,
      hcodegen,temp_gen,pass_2,
      cgai386,tgeni386,cg386cnv;

{*****************************************************************************
                             SecondLoad
*****************************************************************************}

    procedure secondload(var p : ptree);
      var
         hregister : tregister;
         symtabletype : tsymtabletype;
         i : longint;
         hp : preference;
      begin
         simple_loadn:=true;
         reset_reference(p^.location.reference);
         case p^.symtableentry^.typ of
              { this is only for toasm and toaddr }
              absolutesym :
                 begin
                    stringdispose(p^.location.reference.symbol);
                    if (pabsolutesym(p^.symtableentry)^.abstyp=toaddr) then
                     begin
                       if pabsolutesym(p^.symtableentry)^.absseg then
                        p^.location.reference.segment:=R_FS;
                       p^.location.reference.offset:=pabsolutesym(p^.symtableentry)^.address;
                     end
                    else
                     p^.location.reference.symbol:=stringdup(p^.symtableentry^.mangledname);
                    maybe_concat_external(p^.symtableentry^.owner,p^.symtableentry^.mangledname);
                 end;
              varsym :
                 begin
                    hregister:=R_NO;
                    if (pvarsym(p^.symtableentry)^.var_options and vo_is_C_var)<>0 then
                      begin
                         stringdispose(p^.location.reference.symbol);
                         p^.location.reference.symbol:=stringdup(p^.symtableentry^.mangledname);
                         if (pvarsym(p^.symtableentry)^.var_options and vo_is_external)<>0 then
                           maybe_concat_external(p^.symtableentry^.owner,p^.symtableentry^.mangledname);
                      end
                    else
                      begin
                         symtabletype:=p^.symtable^.symtabletype;
                         { in case it is a register variable: }
                         if pvarsym(p^.symtableentry)^.reg<>R_NO then
                           begin
                              p^.location.loc:=LOC_CREGISTER;
                              p^.location.register:=pvarsym(p^.symtableentry)^.reg;
                              unused:=unused-[pvarsym(p^.symtableentry)^.reg];
                           end
                         else
                           begin
                              { first handle local and temporary variables }
                              if (symtabletype in [parasymtable,inlinelocalsymtable,
                                                   inlineparasymtable,localsymtable]) then
                                begin
                                   p^.location.reference.base:=procinfo.framepointer;
                                   p^.location.reference.offset:=pvarsym(p^.symtableentry)^.address;
                                   if (symtabletype=localsymtable) or (symtabletype=inlinelocalsymtable) then
                                     p^.location.reference.offset:=-p^.location.reference.offset;
                                   if (symtabletype=parasymtable) or (symtabletype=inlineparasymtable) then
                                     inc(p^.location.reference.offset,p^.symtable^.call_offset);
                                   if (lexlevel>(p^.symtable^.symtablelevel)) then
                                     begin
                                        hregister:=getregister32;

                                        { make a reference }
                                        hp:=new_reference(procinfo.framepointer,
                                          procinfo.framepointer_offset);


                                        exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,S_L,hp,hregister)));

                                        simple_loadn:=false;
                                        i:=lexlevel-1;
                                        while i>(p^.symtable^.symtablelevel) do
                                          begin
                                             { make a reference }
                                             hp:=new_reference(hregister,8);
                                             exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,S_L,hp,hregister)));
                                             dec(i);
                                          end;
                                        p^.location.reference.base:=hregister;
                                     end;
                                end
                              else
                                case symtabletype of
                                   unitsymtable,globalsymtable,
                                   staticsymtable : begin
                                                       stringdispose(p^.location.reference.symbol);
                                                       p^.location.reference.symbol:=stringdup(p^.symtableentry^.mangledname);
                                                       if symtabletype=unitsymtable then
                                                         concat_external(p^.symtableentry^.mangledname,EXT_NEAR);
                                                    end;
                                   stt_exceptsymtable:
                                     begin
                                        p^.location.reference.base:=procinfo.framepointer;
                                        p^.location.reference.offset:=pvarsym(p^.symtableentry)^.address;
                                     end;
                                   objectsymtable:
                                     begin
                                        if (pvarsym(p^.symtableentry)^.properties and sp_static)<>0 then
                                          begin
                                             stringdispose(p^.location.reference.symbol);
                                             p^.location.reference.symbol:=
                                                stringdup(p^.symtableentry^.mangledname);
                                             if p^.symtable^.defowner^.owner^.symtabletype=unitsymtable then
                                               concat_external(p^.symtableentry^.mangledname,EXT_NEAR);
                                          end
                                        else
                                          begin
                                             p^.location.reference.base:=R_ESI;
                                             p^.location.reference.offset:=pvarsym(p^.symtableentry)^.address;
                                          end;
                                     end;
                                   withsymtable:
                                     begin
                                        hregister:=getregister32;
                                        p^.location.reference.base:=hregister;
                                        { make a reference }
                                        { symtable datasize field
                                          contains the offset of the temp
                                          stored }
                                        hp:=new_reference(procinfo.framepointer,
                                          p^.symtable^.datasize);

                                        exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,S_L,hp,hregister)));

                                        p^.location.reference.offset:=
                                          pvarsym(p^.symtableentry)^.address;
                                     end;
                                end;
                           end;
                         { in case call by reference, then calculate: }
                         if (pvarsym(p^.symtableentry)^.varspez=vs_var) or
                            ((pvarsym(p^.symtableentry)^.varspez=vs_const) and
                             dont_copy_const_param(pvarsym(p^.symtableentry)^.definition)) or
                             { call by value open arrays are also indirect addressed }
                             is_open_array(pvarsym(p^.symtableentry)^.definition) then
                           begin
                              simple_loadn:=false;
                              if hregister=R_NO then
                                hregister:=getregister32;
                              if is_open_array(pvarsym(p^.symtableentry)^.definition) then
                                begin
                                   if (p^.location.reference.base=procinfo.framepointer) then
                                     begin
                                        highframepointer:=p^.location.reference.base;
                                        highoffset:=p^.location.reference.offset;
                                     end
                                   else
                                     begin
                                        highframepointer:=R_EDI;
                                        highoffset:=p^.location.reference.offset;
                                        exprasmlist^.concat(new(pai386,op_reg_reg(A_MOV,S_L,
                                          p^.location.reference.base,R_EDI)));
                                     end;
                                end;
                              if p^.location.loc=LOC_CREGISTER then
                                begin
                                   exprasmlist^.concat(new(pai386,op_reg_reg(A_MOV,S_L,
                                     p^.location.register,hregister)));
                                   p^.location.loc:=LOC_REFERENCE;
                                end
                              else
                                begin
                                   exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,S_L,
                                     newreference(p^.location.reference),
                                     hregister)));
                                end;
                              clear_reference(p^.location.reference);
                              p^.location.reference.base:=hregister;
                          end;
                      end;
                 end;
              procsym:
                 begin
                    {!!!!! Be aware, work on virtual methods too }
                    stringdispose(p^.location.reference.symbol);
                    p^.location.reference.symbol:=
                      stringdup(pprocsym(p^.symtableentry)^.definition^.mangledname);
                    maybe_concat_external(p^.symtable,p^.symtableentry^.mangledname);
                 end;
              typedconstsym :
                 begin
                    stringdispose(p^.location.reference.symbol);
                    p^.location.reference.symbol:=stringdup(p^.symtableentry^.mangledname);
                    maybe_concat_external(p^.symtable,p^.symtableentry^.mangledname);
                 end;
              else internalerror(4);
         end;
      end;


{*****************************************************************************
                             SecondAssignment
*****************************************************************************}

    procedure secondassignment(var p : ptree);
      var
         opsize : topsize;
         otlabel,hlabel,oflabel : plabel;
         hregister : tregister;
         loc : tloc;
         r : preference;
      begin
         otlabel:=truelabel;
         oflabel:=falselabel;
         getlabel(truelabel);
         getlabel(falselabel);
         { calculate left sides }
         if not(p^.concat_string) then
           secondpass(p^.left);

         if codegenerror then
           exit;

         case p^.left^.location.loc of
            LOC_REFERENCE : begin
                              { in case left operator uses to register }
                              { but to few are free then LEA }
                              if (p^.left^.location.reference.base<>R_NO) and
                                 (p^.left^.location.reference.index<>R_NO) and
                                 (usablereg32<p^.right^.registers32) then
                                begin
                                   del_reference(p^.left^.location.reference);
                                   hregister:=getregister32;
                                   exprasmlist^.concat(new(pai386,op_ref_reg(A_LEA,S_L,newreference(
                                     p^.left^.location.reference),
                                     hregister)));
                                   clear_reference(p^.left^.location.reference);
                                   p^.left^.location.reference.base:=hregister;
                                   p^.left^.location.reference.index:=R_NO;
                                end;
                              loc:=LOC_REFERENCE;
                           end;
            LOC_CREGISTER:
              loc:=LOC_CREGISTER;
            LOC_MMXREGISTER:
              loc:=LOC_MMXREGISTER;
            LOC_CMMXREGISTER:
              loc:=LOC_CMMXREGISTER;
            else
               begin
                  CGMessage(cg_e_illegal_expression);
                  exit;
               end;
         end;
         { lets try to optimize this (PM)             }
         { define a dest_loc that is the location      }
         { and a ptree to verify that it is the right }
         { place to insert it                         }
{$ifdef test_dest_loc}
         if (aktexprlevel<4) then
           begin
              dest_loc_known:=true;
              dest_loc:=p^.left^.location;
              dest_loc_tree:=p^.right;
           end;
{$endif test_dest_loc}

         if (p^.right^.treetype=realconstn) then
           begin
              if p^.left^.resulttype^.deftype=floatdef then
                begin
                   case pfloatdef(p^.left^.resulttype)^.typ of
                     s32real : p^.right^.realtyp:=ait_real_32bit;
                     s64real : p^.right^.realtyp:=ait_real_64bit;
                     s80real : p^.right^.realtyp:=ait_real_extended;
                     { what about f32bit and s64bit }
                     end;
                end;
           end;
         secondpass(p^.right);

         if codegenerror then
           exit;

{$ifdef test_dest_loc}
         dest_loc_known:=false;
         if in_dest_loc then
           begin
              truelabel:=otlabel;
              falselabel:=oflabel;
              in_dest_loc:=false;
              exit;
           end;
{$endif test_dest_loc}
         if p^.left^.resulttype^.deftype=stringdef then
           begin
              if is_ansistring(p^.left^.resulttype) then
                begin
                  { the source and destinations are released
                    in loadansistring, because an ansi string can
                    also be in a register
                  }
                  loadansistring(p);
                end
              else
              if is_shortstring(p^.left^.resulttype) and
                not (p^.concat_string) then
                begin
                  if is_ansistring(p^.right^.resulttype) then
                    loadansi2short(p^.right,p^.left)
                  else
                    begin
                       { we do not need destination anymore }
                       del_reference(p^.left^.location.reference);
                       del_reference(p^.right^.location.reference);
                       loadstring(p);
                       ungetiftemp(p^.right^.location.reference);
                    end;
                end
              else
                begin
                  { its the only thing we have to do }
                  del_reference(p^.right^.location.reference);
                end
           end
        else case p^.right^.location.loc of
            LOC_REFERENCE,
            LOC_MEM : begin
                         { extra handling for ordinal constants }
                         if (p^.right^.treetype in [ordconstn,fixconstn]) or
                            (loc=LOC_CREGISTER) then
                           begin
                              case p^.left^.resulttype^.size of
                                 1 : opsize:=S_B;
                                 2 : opsize:=S_W;
                                 4 : opsize:=S_L;
                              end;
                              if loc=LOC_CREGISTER then
                                exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,opsize,
                                  newreference(p^.right^.location.reference),
                                  p^.left^.location.register)))
                              else
                                exprasmlist^.concat(new(pai386,op_const_ref(A_MOV,opsize,
                                  p^.right^.location.reference.offset,
                                  newreference(p^.left^.location.reference))));
                              {exprasmlist^.concat(new(pai386,op_const_loc(A_MOV,opsize,
                                  p^.right^.location.reference.offset,
                                  p^.left^.location)));}
                           end
                         else
                           begin
                              if p^.right^.resulttype^.needs_inittable then
                                begin
                                   { this would be a problem }
                                   if not(p^.left^.resulttype^.needs_inittable) then
                                     internalerror(3457);

                                   { increment source reference counter }
                                   new(r);
                                   reset_reference(r^);
                                   r^.symbol:=stringdup(lab2str(p^.right^.resulttype^.get_rtti_label));
                                   emitpushreferenceaddr(exprasmlist,r^);

                                   emitpushreferenceaddr(exprasmlist,p^.right^.location.reference);
                                   exprasmlist^.concat(new(pai386,
                                     op_csymbol(A_CALL,S_NO,newcsymbol('FPC_ADDREF',0))));

                                   if not (cs_compilesystem in aktmoduleswitches) then
                                     concat_external('FPC_ADDREF',EXT_NEAR);

                                   { decrement destination reference counter }
                                   new(r);
                                   reset_reference(r^);
                                   r^.symbol:=stringdup(lab2str(p^.left^.resulttype^.get_rtti_label));
                                   emitpushreferenceaddr(exprasmlist,r^);

                                   emitpushreferenceaddr(exprasmlist,p^.left^.location.reference);
                                   exprasmlist^.concat(new(pai386,
                                     op_csymbol(A_CALL,S_NO,newcsymbol('FPC_DECREF',0))));

                                   if not(cs_compilesystem in aktmoduleswitches) then
                                     concat_external('FPC_DECREF',EXT_NEAR);

                                end;
                              concatcopy(p^.right^.location.reference,
                                p^.left^.location.reference,p^.left^.resulttype^.size,false);
                              ungetiftemp(p^.right^.location.reference);
                           end;
                      end;
{$ifdef SUPPORT_MMX}
            LOC_CMMXREGISTER,
            LOC_MMXREGISTER:
              begin
                 if loc=LOC_CMMXREGISTER then
                   exprasmlist^.concat(new(pai386,op_reg_reg(A_MOVQ,S_NO,
                   p^.right^.location.register,p^.left^.location.register)))
                 else
                   exprasmlist^.concat(new(pai386,op_reg_ref(A_MOVQ,S_NO,
                     p^.right^.location.register,newreference(p^.left^.location.reference))));
              end;
{$endif SUPPORT_MMX}
            LOC_REGISTER,
            LOC_CREGISTER : begin
                              case p^.right^.resulttype^.size of
                                 1 : opsize:=S_B;
                                 2 : opsize:=S_W;
                                 4 : opsize:=S_L;
                              end;
                              { simplified with op_reg_loc         }
                              if loc=LOC_CREGISTER then
                                exprasmlist^.concat(new(pai386,op_reg_reg(A_MOV,opsize,
                                  p^.right^.location.register,
                                  p^.left^.location.register)))
                              else
                                exprasmlist^.concat(new(pai386,op_reg_ref(A_MOV,opsize,
                                  p^.right^.location.register,
                                  newreference(p^.left^.location.reference))));
                              {exprasmlist^.concat(new(pai386,op_reg_loc(A_MOV,opsize,
                                  p^.right^.location.register,
                                  p^.left^.location)));             }

                           end;
            LOC_FPU : begin
                              if loc<>LOC_REFERENCE then
                                internalerror(10010)
                              else
                                floatstore(pfloatdef(p^.left^.resulttype)^.typ,
                                  p^.left^.location.reference);
                           end;
            LOC_JUMP     : begin
                              getlabel(hlabel);
                              emitl(A_LABEL,truelabel);
                              if loc=LOC_CREGISTER then
                                exprasmlist^.concat(new(pai386,op_const_reg(A_MOV,S_B,
                                  1,p^.left^.location.register)))
                              else
                                exprasmlist^.concat(new(pai386,op_const_ref(A_MOV,S_B,
                                  1,newreference(p^.left^.location.reference))));
                              {exprasmlist^.concat(new(pai386,op_const_loc(A_MOV,S_B,
                                  1,p^.left^.location)));}
                              emitl(A_JMP,hlabel);
                              emitl(A_LABEL,falselabel);
                              if loc=LOC_CREGISTER then
                                exprasmlist^.concat(new(pai386,op_reg_reg(A_XOR,S_B,
                                  p^.left^.location.register,
                                  p^.left^.location.register)))
                              else
                                exprasmlist^.concat(new(pai386,op_const_ref(A_MOV,S_B,
                                  0,newreference(p^.left^.location.reference))));
                              emitl(A_LABEL,hlabel);
                           end;
            LOC_FLAGS    : begin
                              if loc=LOC_CREGISTER then
                                exprasmlist^.concat(new(pai386,op_reg(flag_2_set[p^.right^.location.resflags],S_B,
                                  p^.left^.location.register)))
                              else
                                exprasmlist^.concat(new(pai386,op_ref(flag_2_set[p^.right^.location.resflags],S_B,
                                  newreference(p^.left^.location.reference))));
                           end;
         end;
         freelabel(truelabel);
         freelabel(falselabel);
         truelabel:=otlabel;
         falselabel:=oflabel;
      end;


{*****************************************************************************
                             SecondFuncRet
*****************************************************************************}

    procedure secondfuncret(var p : ptree);
      var
         hr : tregister;
         hp : preference;
         pp : pprocinfo;
         hr_valid : boolean;
      begin
         clear_reference(p^.location.reference);
         hr_valid:=false;
         if @procinfo<>pprocinfo(p^.funcretprocinfo) then
           begin
              hr:=getregister32;
              hr_valid:=true;
              hp:=new_reference(procinfo.framepointer,
                procinfo.framepointer_offset);
              exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,S_L,hp,hr)));
              pp:=procinfo.parent;
              { walk up the stack frame }
              while pp<>pprocinfo(p^.funcretprocinfo) do
                begin
                   hp:=new_reference(hr,
                     pp^.framepointer_offset);
                   exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,S_L,hp,hr)));
                   pp:=pp^.parent;
                end;
              p^.location.reference.base:=hr;
           end
         else
           p^.location.reference.base:=procinfo.framepointer;
         p^.location.reference.offset:=procinfo.retoffset;
         if ret_in_param(p^.retdef) then
           begin
              if not hr_valid then
                hr:=getregister32;
              exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,S_L,newreference(p^.location.reference),hr)));
              p^.location.reference.base:=hr;
              p^.location.reference.offset:=0;
           end;
      end;


{*****************************************************************************
                           SecondArrayConstruct
*****************************************************************************}

      const
        vtInteger    = 0;
        vtBoolean    = 1;
        vtChar       = 2;
        vtExtended   = 3;
        vtString     = 4;
        vtPointer    = 5;
        vtPChar      = 6;
        vtObject     = 7;
        vtClass      = 8;
        vtWideChar   = 9;
        vtPWideChar  = 10;
        vtAnsiString = 11;
        vtCurrency   = 12;
        vtVariant    = 13;
        vtInterface  = 14;
        vtWideString = 15;
        vtInt64      = 16;

    procedure emit_mov_loc_ref(const t:tlocation;const ref:treference);
      begin
        case t.loc of
          LOC_REGISTER,
         LOC_CREGISTER : begin
                           exprasmlist^.concat(new(pai386,op_reg_ref(A_MOV,S_L,
                             t.register,newreference(ref))));
                           ungetregister32(t.register); { the register is not needed anymore }
                         end;
               LOC_MEM,
         LOC_REFERENCE : begin
                           if t.reference.isintvalue then
                             exprasmlist^.concat(new(pai386,op_const_ref(A_MOV,S_L,
                               t.reference.offset,newreference(ref))))
                           else
                             begin
                               exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,S_L,
                                 newreference(t.reference),R_EDI)));
                               exprasmlist^.concat(new(pai386,op_reg_ref(A_MOV,S_L,
                                 R_EDI,newreference(ref))));
                             end;
                           ungetiftemp(t.reference);
                         end;
        else
         internalerror(330);
        end;
      end;


    procedure emit_push_loc(const t:tlocation);
      begin
        case t.loc of
          LOC_REGISTER,
         LOC_CREGISTER : begin
                           exprasmlist^.concat(new(pai386,op_reg(A_PUSH,S_L,t.register)));
                           ungetregister32(t.register); { the register is not needed anymore }
                         end;
               LOC_MEM,
         LOC_REFERENCE : begin
                           if t.reference.isintvalue then
                             exprasmlist^.concat(new(pai386,op_const(A_PUSH,S_L,t.reference.offset)))
                           else
                             exprasmlist^.concat(new(pai386,op_ref(A_PUSH,S_L,newreference(t.reference))));
                           ungetiftemp(t.reference);
                         end;
        else
         internalerror(330);
        end;
      end;


    procedure emit_to_reference(var p:ptree);
      begin
        case p^.location.loc of
               LOC_FPU : begin
                           reset_reference(p^.location.reference);
                           gettempofsizereference(10,p^.location.reference);
                           floatstore(pfloatdef(p^.resulttype)^.typ,p^.location.reference);
                           p^.location.loc:=LOC_REFERENCE;
                         end;
               LOC_MEM,
         LOC_REFERENCE : ;
        else
         internalerror(333);
        end;
      end;


    procedure emit_lea_loc_ref(const t:tlocation;const ref:treference);
      begin
        case t.loc of
               LOC_MEM,
         LOC_REFERENCE : begin
                           if t.reference.isintvalue then
                             internalerror(331)
                           else
                             begin
                               exprasmlist^.concat(new(pai386,op_ref_reg(A_LEA,S_L,
                                 newreference(t.reference),R_EDI)));
                               exprasmlist^.concat(new(pai386,op_reg_ref(A_MOV,S_L,
                                 R_EDI,newreference(ref))));
                             end;
                           ungetiftemp(t.reference);
                         end;
        else
         internalerror(332);
        end;
      end;


    procedure emit_push_lea_loc(const t:tlocation);
      begin
        case t.loc of
               LOC_MEM,
         LOC_REFERENCE : begin
                           if t.reference.isintvalue then
                             internalerror(331)
                           else
                             begin
                               exprasmlist^.concat(new(pai386,op_ref_reg(A_LEA,S_L,
                                 newreference(t.reference),R_EDI)));
                               exprasmlist^.concat(new(pai386,op_reg(A_PUSH,S_L,R_EDI)));
                             end;
                           ungetiftemp(t.reference);
                         end;
        else
         internalerror(332);
        end;
      end;


    procedure secondarrayconstruct(var p : ptree);
      var
        hp    : ptree;
        href  : treference;
        lt    : pdef;
        vaddr : boolean;
        vtype : longint;
      begin
        if not p^.cargs then
         begin
           clear_reference(p^.location.reference);
           gettempofsizereference((parraydef(p^.resulttype)^.highrange+1)*8,p^.location.reference);
           href:=p^.location.reference;
         end;
        hp:=p;
        while assigned(hp) do
         begin
           secondpass(hp^.left);
           if codegenerror then
            exit;
           { find the correct vtype value }
           vtype:=$ff;
           vaddr:=false;
           lt:=hp^.left^.resulttype;
           case lt^.deftype of
           enumdef,
            orddef : begin
                       if (lt^.deftype=enumdef) or
                          is_integer(lt) then
                        vtype:=vtInteger
                       else
                        if is_boolean(lt) then
                         vtype:=vtBoolean
                       else
                        if (lt^.deftype=orddef) and (porddef(lt)^.typ=uchar) then
                         vtype:=vtChar;
                     end;
          floatdef : begin
                       vtype:=vtExtended;
                       vaddr:=true;
                     end;
        procvardef,
        pointerdef : begin
                       if is_pchar(lt) then
                        vtype:=vtPChar
                       else
                        vtype:=vtPointer;
                     end;
       classrefdef : vtype:=vtClass;
         objectdef : begin
                       vtype:=vtObject;
                     end;
         stringdef : begin
                       if is_shortstring(lt) then
                        begin
                          vtype:=vtString;
                          vaddr:=true;
                        end
                       else
                        if is_ansistring(lt) then
                         vtype:=vtAnsiString;
                     end;
           end;
           if vtype=$ff then
            internalerror(14357);
           { write C style pushes or an pascal array }
           if p^.cargs then
            begin
              if vaddr then
               begin
                 emit_to_reference(hp^.left);
                 emit_push_lea_loc(hp^.left^.location);
               end
              else
               emit_push_loc(hp^.left^.location);
            end
           else
            begin
              { update href to the vtype field and write it }
              exprasmlist^.concat(new(pai386,op_const_ref(A_MOV,S_L,
                vtype,newreference(href))));
              inc(href.offset,4);
              { write changing field update href to the next element }
              if vaddr then
               begin
                 emit_to_reference(hp^.left);
                 emit_lea_loc_ref(hp^.left^.location,href);
               end
              else
               emit_mov_loc_ref(hp^.left^.location,href);
              inc(href.offset,4);
            end;
           { load next entry }
           hp:=hp^.right;
         end;
      end;


end.
{
  $Log$
  Revision 1.26  1998-11-10 10:09:10  peter
    * va_list -> array of const

  Revision 1.25  1998/11/05 12:02:35  peter
    * released useansistring
    * removed -Sv, its now available in fpc modes

  Revision 1.24  1998/10/14 08:47:14  pierre
    * bugs in secondfuncret for result in subprocedures removed

  Revision 1.23  1998/10/06 17:16:44  pierre
    * some memory leaks fixed (thanks to Peter for heaptrc !)

  Revision 1.22  1998/10/01 09:22:53  peter
    * fixed value openarray
    * ungettemp of arrayconstruct

  Revision 1.21  1998/09/28 11:07:39  peter
    + floatdef support for array of const

  Revision 1.20  1998/09/24 14:26:03  peter
    * updated for new tvarrec

  Revision 1.19  1998/09/23 17:49:59  peter
    * high(arrayconstructor) is now correct
    * procvardef support for variant record

  Revision 1.18  1998/09/23 09:58:48  peter
    * first working array of const things

  Revision 1.17  1998/09/20 18:00:19  florian
    * small compiling problems fixed

  Revision 1.16  1998/09/20 17:46:48  florian
    * some things regarding ansistrings fixed

  Revision 1.15  1998/09/17 09:42:16  peter
    + pass_2 for cg386
    * Message() -> CGMessage() for pass_1/pass_2

  Revision 1.14  1998/09/14 10:43:50  peter
    * all internal RTL functions start with FPC_

  Revision 1.13  1998/09/04 12:24:24  florian
    * bug0159 fixed

  Revision 1.12  1998/09/04 11:55:17  florian
    * problem with -Or fixed

  Revision 1.11  1998/09/03 16:03:14  florian
    + rtti generation
    * init table generation changed

  Revision 1.10  1998/08/21 14:08:40  pierre
    + TEST_FUNCRET now default (old code removed)
      works also for m68k (at least compiles)

  Revision 1.9  1998/08/20 09:26:37  pierre
    + funcret setting in underproc testing
      compile with _dTEST_FUNCRET

  Revision 1.8  1998/08/10 14:49:48  peter
    + localswitches, moduleswitches, globalswitches splitting

  Revision 1.7  1998/07/30 13:30:33  florian
    * final implemenation of exception support, maybe it needs
      some fixes :)

  Revision 1.6  1998/07/26 21:58:57  florian
   + better support for switch $H
   + index access to ansi strings added
   + assigment of data (records/arrays) containing ansi strings

  Revision 1.5  1998/07/24 22:16:54  florian
    * internal error 10 together with array access fixed. I hope
      that's the final fix.

  Revision 1.4  1998/06/11 13:58:45  peter
    * fixed too long line

  Revision 1.3  1998/06/09 16:01:35  pierre
    + added procedure directive parsing for procvars
      (accepted are popstack cdecl and pascal)
    + added C vars with the following syntax
      var C calias 'true_c_name';(can be followed by external)
      reason is that you must add the Cprefix

      which is target dependent

  Revision 1.2  1998/06/08 13:13:34  pierre
    + temporary variables now in temp_gen.pas unit
      because it is processor independent
    * mppc68k.bat modified to undefine i386 and support_mmx
      (which are defaults for i386)

  Revision 1.1  1998/06/05 17:44:12  peter
    * splitted cgi386

}

