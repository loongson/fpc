{
    $Id$
    Copyright (c) 1993-98 by Florian Klaempfl

    Generate i386 assembler for nodes that influence the flow

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
unit cg386flw;
interface

    uses
      tree;

    procedure second_while_repeatn(var p : ptree);
    procedure secondifn(var p : ptree);
    procedure secondfor(var p : ptree);
    procedure secondexitn(var p : ptree);
    procedure secondbreakn(var p : ptree);
    procedure secondcontinuen(var p : ptree);
    procedure secondgoto(var p : ptree);
    procedure secondlabel(var p : ptree);
    procedure secondraise(var p : ptree);
    procedure secondtryexcept(var p : ptree);
    procedure secondtryfinally(var p : ptree);
    procedure secondon(var p : ptree);
    procedure secondfail(var p : ptree);


implementation

    uses
      cobjects,verbose,globals,systems,
      symtable,aasm,types,
      hcodegen,temp_gen,pass_2,
      i386,cgai386,tgeni386;

{*****************************************************************************
                         Second_While_RepeatN
*****************************************************************************}

    procedure second_while_repeatn(var p : ptree);
      var
         lcont,lbreak,lloop,
         oldclabel,oldblabel : plabel;
         otlabel,oflabel : plabel;
      begin
         getlabel(lloop);
         getlabel(lcont);
         getlabel(lbreak);
         { arrange continue and breaklabels: }
         oldclabel:=aktcontinuelabel;
         oldblabel:=aktbreaklabel;

         { handling code at the end as it is much more efficient, and makes
           while equal to repeat loop, only the end true/false is swapped (PFV) }
         if p^.treetype=whilen then
          emitl(A_JMP,lcont);

         emitl(A_LABEL,lloop);

         aktcontinuelabel:=lcont;
         aktbreaklabel:=lbreak;
         cleartempgen;
         if assigned(p^.right) then
          secondpass(p^.right);

         emitl(A_LABEL,lcont);
         otlabel:=truelabel;
         oflabel:=falselabel;
         if p^.treetype=whilen then
          begin
            truelabel:=lloop;
            falselabel:=lbreak;
          end
         { repeatn }
         else
          begin
            truelabel:=lbreak;
            falselabel:=lloop;
          end;
         cleartempgen;
         secondpass(p^.left);
         maketojumpbool(p^.left);
         emitl(A_LABEL,lbreak);
         freelabel(lloop);
         freelabel(lcont);
         freelabel(lbreak);
         truelabel:=otlabel;
         falselabel:=oflabel;

         aktcontinuelabel:=oldclabel;
         aktbreaklabel:=oldblabel;
      end;


{*****************************************************************************
                               SecondIfN
*****************************************************************************}

    procedure secondifn(var p : ptree);
      var
         hl,otlabel,oflabel : plabel;
      begin
         otlabel:=truelabel;
         oflabel:=falselabel;
         getlabel(truelabel);
         getlabel(falselabel);
         cleartempgen;
         secondpass(p^.left);
         maketojumpbool(p^.left);
         if assigned(p^.right) then
           begin
              emitl(A_LABEL,truelabel);
              cleartempgen;
              secondpass(p^.right);
           end;
         if assigned(p^.t1) then
           begin
              if assigned(p^.right) then
                begin
                   getlabel(hl);
                   { do go back to if line !! }
                   aktfilepos:=exprasmlist^.getlasttaifilepos^;
                   emitl(A_JMP,hl);
                end;
              emitl(A_LABEL,falselabel);
              cleartempgen;
              secondpass(p^.t1);
              if assigned(p^.right) then
                emitl(A_LABEL,hl);
           end
         else
           emitl(A_LABEL,falselabel);
         if not(assigned(p^.right)) then
           emitl(A_LABEL,truelabel);
         freelabel(truelabel);
         freelabel(falselabel);
         truelabel:=otlabel;
         falselabel:=oflabel;
      end;


{*****************************************************************************
                              SecondFor
*****************************************************************************}

    procedure secondfor(var p : ptree);
      var
         l3,oldclabel,oldblabel : plabel;
         omitfirstcomp,temptovalue : boolean;
         hs : byte;
         temp1 : treference;
         hop : tasmop;
         cmpreg,cmp32 : tregister;
         opsize : topsize;
         count_var_is_signed : boolean;

      begin
         oldclabel:=aktcontinuelabel;
         oldblabel:=aktbreaklabel;
         getlabel(aktcontinuelabel);
         getlabel(aktbreaklabel);
         getlabel(l3);

         { could we spare the first comparison ? }
             omitfirstcomp:=false;
         if p^.right^.treetype=ordconstn then
           if p^.left^.right^.treetype=ordconstn then
             omitfirstcomp:=(p^.backward and (p^.left^.right^.value>=p^.right^.value))
               or (not(p^.backward) and (p^.left^.right^.value<=p^.right^.value));

         { only calculate reference }
         cleartempgen;
         secondpass(p^.t2);
         if not(simple_loadn) then
          CGMessage(cg_e_illegal_count_var);

         { produce start assignment }
         cleartempgen;
         secondpass(p^.left);
         count_var_is_signed:=is_signed(porddef(p^.t2^.resulttype));
             hs:=p^.t2^.resulttype^.size;
         cmp32:=getregister32;
             case hs of
            1 : begin
                   opsize:=S_B;
                   cmpreg:=reg32toreg8(cmp32);
                end;
            2 : begin
                   opsize:=S_W;
                   cmpreg:=reg32toreg16(cmp32);
                end;
            4 : begin
                   opsize:=S_L;
                   cmpreg:=cmp32;
                end;
         end;
         cleartempgen;
             secondpass(p^.right);
         { calculate pointer value and check if changeable and if so }
         { load into temporary variable                              }
         if p^.right^.treetype<>ordconstn then
           begin
              temp1.symbol:=nil;
              gettempofsizereference(hs,temp1);
              temptovalue:=true;
              if (p^.right^.location.loc=LOC_REGISTER) or
                 (p^.right^.location.loc=LOC_CREGISTER) then
                begin
                   exprasmlist^.concat(new(pai386,op_reg_ref(A_MOV,opsize,p^.right^.location.register,
                      newreference(temp1))));
                 end
              else
                 concatcopy(p^.right^.location.reference,temp1,hs,false);
           end
         else temptovalue:=false;

         if temptovalue then
             begin
              if p^.t2^.location.loc=LOC_CREGISTER then
                begin
                   exprasmlist^.concat(new(pai386,op_ref_reg(A_CMP,opsize,newreference(temp1),
                     p^.t2^.location.register)));
                end
              else
                begin
                   exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,opsize,newreference(p^.t2^.location.reference),
                     cmpreg)));
                   exprasmlist^.concat(new(pai386,op_ref_reg(A_CMP,opsize,newreference(temp1),
                     cmpreg)));
                end;
           end
         else
             begin
              if not(omitfirstcomp) then
                begin
                   if p^.t2^.location.loc=LOC_CREGISTER then
                     exprasmlist^.concat(new(pai386,op_const_reg(A_CMP,opsize,p^.right^.value,
                       p^.t2^.location.register)))
                   else
                     exprasmlist^.concat(new(pai386,op_const_ref(A_CMP,opsize,p^.right^.value,
                 newreference(p^.t2^.location.reference))));
                end;
           end;
         if p^.backward then
           if count_var_is_signed then
             hop:=A_JL
           else hop:=A_JB
         else
           if count_var_is_signed then
             hop:=A_JG
            else hop:=A_JA;

             if not(omitfirstcomp) or temptovalue then
           emitl(hop,aktbreaklabel);

         emitl(A_LABEL,l3);

         { help register must not be in instruction block }
         cleartempgen;
         if assigned(p^.t1) then
           secondpass(p^.t1);

         emitl(A_LABEL,aktcontinuelabel);

         { makes no problems there }
         cleartempgen;

         { demand help register again }
         cmp32:=getregister32;
         case hs of
            1 : begin
                   opsize:=S_B;
                   cmpreg:=reg32toreg8(cmp32);
                end;
            2 : begin
                   opsize:=S_W;
                   cmpreg:=reg32toreg16(cmp32);
                end;
            4 : opsize:=S_L;
         end;

          { produce comparison and the corresponding }
         { jump                                     }
         if temptovalue then
           begin
              if p^.t2^.location.loc=LOC_CREGISTER then
                begin
                   exprasmlist^.concat(new(pai386,op_ref_reg(A_CMP,opsize,newreference(temp1),
                     p^.t2^.location.register)));
                end
              else
                begin
                   exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,opsize,newreference(p^.t2^.location.reference),
                     cmpreg)));
                   exprasmlist^.concat(new(pai386,op_ref_reg(A_CMP,opsize,newreference(temp1),
                     cmpreg)));
                    end;
           end
         else
           begin
              if p^.t2^.location.loc=LOC_CREGISTER then
                exprasmlist^.concat(new(pai386,op_const_reg(A_CMP,opsize,p^.right^.value,
                  p^.t2^.location.register)))
              else
                 exprasmlist^.concat(new(pai386,op_const_ref(A_CMP,opsize,p^.right^.value,
                   newreference(p^.t2^.location.reference))));
           end;
         if p^.backward then
           if count_var_is_signed then
             hop:=A_JLE
           else
             hop :=A_JBE
          else
            if count_var_is_signed then
              hop:=A_JGE
            else
                hop:=A_JAE;
         emitl(hop,aktbreaklabel);
         { according to count direction DEC or INC... }
         { must be after the test because of 0to 255 for bytes !! }
         if p^.backward then
           hop:=A_DEC
         else hop:=A_INC;

         if p^.t2^.location.loc=LOC_CREGISTER then
           exprasmlist^.concat(new(pai386,op_reg(hop,opsize,p^.t2^.location.register)))
         else
             exprasmlist^.concat(new(pai386,op_ref(hop,opsize,newreference(p^.t2^.location.reference))));
         emitl(A_JMP,l3);

           { this is the break label: }
         emitl(A_LABEL,aktbreaklabel);
         ungetregister32(cmp32);

         if temptovalue then
           ungetiftemp(temp1);

         freelabel(aktcontinuelabel);
         freelabel(aktbreaklabel);
         freelabel(l3);
         aktcontinuelabel:=oldclabel;
         aktbreaklabel:=oldblabel;
      end;


{*****************************************************************************
                              SecondExitN
*****************************************************************************}

    procedure secondexitn(var p : ptree);
      var
         is_mem : boolean;
         {op : tasmop;
         s : topsize;}
         otlabel,oflabel : plabel;
      label
         do_jmp;
      begin
         if assigned(p^.left) then
           begin
              otlabel:=truelabel;
              oflabel:=falselabel;
              getlabel(truelabel);
              getlabel(falselabel);
              secondpass(p^.left);
              case p^.left^.location.loc of
                 LOC_FPU : goto do_jmp;
                 LOC_MEM,
           LOC_REFERENCE : is_mem:=true;
           LOC_CREGISTER,
            LOC_REGISTER : is_mem:=false;
               LOC_FLAGS : begin
                             exprasmlist^.concat(new(pai386,op_reg(flag_2_set[p^.right^.location.resflags],S_B,R_AL)));
                             goto do_jmp;
                           end;
                LOC_JUMP : begin
                             emitl(A_LABEL,truelabel);
                             exprasmlist^.concat(new(pai386,op_const_reg(A_MOV,S_B,1,R_AL)));
                             emitl(A_JMP,aktexit2label);
                             exprasmlist^.concat(new(pai386,op_reg_reg(A_XOR,S_B,R_AL,R_AL)));
                             goto do_jmp;
                           end;
              else
                internalerror(2001);
              end;
              case procinfo.retdef^.deftype of
               orddef,
              enumdef : begin
                          case procinfo.retdef^.size of
                           4 : if is_mem then
                                 exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,S_L,
                                   newreference(p^.left^.location.reference),R_EAX)))
                               else
                                 emit_reg_reg(A_MOV,S_L,p^.left^.location.register,R_EAX);
                           2 : if is_mem then
                                 exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,S_W,
                                   newreference(p^.left^.location.reference),R_AX)))
                               else
                                 emit_reg_reg(A_MOV,S_W,p^.left^.location.register,R_AX);
                           1 : if is_mem then
                                 exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,S_B,
                                   newreference(p^.left^.location.reference),R_AL)))
                               else
                                 emit_reg_reg(A_MOV,S_B,p^.left^.location.register,R_AL);
                          end;
                        end;
           pointerdef,
           procvardef : begin
                          if is_mem then
                            exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,S_L,
                              newreference(p^.left^.location.reference),R_EAX)))
                          else
                            exprasmlist^.concat(new(pai386,op_reg_reg(A_MOV,S_L,
                              p^.left^.location.register,R_EAX)));
                        end;
             floatdef : begin
                          if pfloatdef(procinfo.retdef)^.typ=f32bit then
                           begin
                             if is_mem then
                               exprasmlist^.concat(new(pai386,op_ref_reg(A_MOV,S_L,
                                 newreference(p^.left^.location.reference),R_EAX)))
                             else
                               emit_reg_reg(A_MOV,S_L,p^.left^.location.register,R_EAX);
                           end
                          else
                           if is_mem then
                            floatload(pfloatdef(procinfo.retdef)^.typ,p^.left^.location.reference);
                        end;
              end;
do_jmp:
              freelabel(truelabel);
              freelabel(falselabel);
              truelabel:=otlabel;
              falselabel:=oflabel;
              emitl(A_JMP,aktexit2label);
           end
         else
           begin
              emitl(A_JMP,aktexitlabel);
           end;
       end;


{*****************************************************************************
                              SecondBreakN
*****************************************************************************}

    procedure secondbreakn(var p : ptree);
      begin
         if aktbreaklabel<>nil then
           emitl(A_JMP,aktbreaklabel)
         else
           CGMessage(cg_e_break_not_allowed);
      end;


{*****************************************************************************
                              SecondContinueN
*****************************************************************************}

    procedure secondcontinuen(var p : ptree);
      begin
         if aktcontinuelabel<>nil then
           emitl(A_JMP,aktcontinuelabel)
         else
           CGMessage(cg_e_continue_not_allowed);
      end;


{*****************************************************************************
                             SecondGoto
*****************************************************************************}

    procedure secondgoto(var p : ptree);

       begin
         emitl(A_JMP,p^.labelnr);
       end;


{*****************************************************************************
                             SecondLabel
*****************************************************************************}

    procedure secondlabel(var p : ptree);
      begin
         emitl(A_LABEL,p^.labelnr);
         cleartempgen;
         secondpass(p^.left);
      end;


{*****************************************************************************
                             SecondRaise
*****************************************************************************}

    procedure secondraise(var p : ptree);

      var
         a : plabel;

      begin
         if assigned(p^.left) then
           begin
              { generate the address }
              if assigned(p^.right) then
                begin
                   secondpass(p^.right);
                   if codegenerror then
                     exit;
                end
              else
                begin
                   getlabel(a);
                   emitl(A_LABEL,a);
                   exprasmlist^.concat(new(pai386,
                     op_csymbol(A_PUSH,S_L,newcsymbol(lab2str(a),0))));
                end;
              secondpass(p^.left);
              if codegenerror then
                exit;

              case p^.left^.location.loc of
                 LOC_MEM,LOC_REFERENCE:
                   exprasmlist^.concat(new(pai386,op_ref(A_PUSH,S_L,
                       newreference(p^.left^.location.reference))));
                 LOC_CREGISTER,LOC_REGISTER : exprasmlist^.concat(new(pai386,op_reg(A_PUSH,S_L,
                       p^.left^.location.register)));
                 else CGMessage(type_e_mismatch);
              end;
              emitcall('FPC_RAISEEXCEPTION',true);
             end
           else
             begin
                emitcall('FPC_RERAISE',true);
             end;
       end;


{*****************************************************************************
                             SecondTryExcept
*****************************************************************************}

    var
       endexceptlabel : plabel;

    procedure secondtryexcept(var p : ptree);

      var
         exceptlabel,doexceptlabel,oldendexceptlabel,
         lastonlabel : plabel;

      begin
         { this can be called recursivly }
         oldendexceptlabel:=endexceptlabel;
         { we modify EAX }
         usedinproc:=usedinproc or ($80 shr byte(R_EAX));

         getlabel(exceptlabel);
         getlabel(doexceptlabel);
         getlabel(endexceptlabel);
         getlabel(lastonlabel);
         push_int (1); { push type of exceptionframe }
         emitcall('FPC_PUSHEXCEPTADDR',true);
         exprasmlist^.concat(new(pai386,
           op_reg(A_PUSH,S_L,R_EAX)));
         emitcall('FPC_SETJMP',true);
         exprasmlist^.concat(new(pai386,
           op_reg(A_PUSH,S_L,R_EAX)));
         exprasmlist^.concat(new(pai386,
           op_reg_reg(A_TEST,S_L,R_EAX,R_EAX)));
         emitl(A_JNE,exceptlabel);

         { try code }
         secondpass(p^.left);
         if codegenerror then
           exit;

         emitl(A_LABEL,exceptlabel);
         exprasmlist^.concat(new(pai386,
           op_reg(A_POP,S_L,R_EAX)));
         exprasmlist^.concat(new(pai386,
           op_reg_reg(A_TEST,S_L,R_EAX,R_EAX)));
         emitl(A_JNE,doexceptlabel);
         emitcall('FPC_POPADDRSTACK',true);
         emitl(A_JMP,endexceptlabel);
         emitl(A_LABEL,doexceptlabel);

         if assigned(p^.right) then
           secondpass(p^.right);

         emitl(A_LABEL,lastonlabel);
         { default handling }
         if assigned(p^.t1) then
           begin
              { FPC_CATCHES must be called with
                'default handler' flag (=-1)
              }
              push_int (-1);
              emitcall('FPC_CATCHES',true);
              secondpass(p^.t1);
           end
         else
           emitcall('FPC_RERAISE',true);
         emitl(A_LABEL,endexceptlabel);
         freelabel(exceptlabel);
         freelabel(doexceptlabel);
         freelabel(endexceptlabel);
         freelabel(lastonlabel);
         endexceptlabel:=oldendexceptlabel;
      end;

    procedure secondon(var p : ptree);

      var
         nextonlabel : plabel;
         ref : treference;

      begin
         getlabel(nextonlabel);

         { push the vmt }
         exprasmlist^.concat(new(pai386,op_csymbol(A_PUSH,S_L,
           newcsymbol(p^.excepttype^.vmt_mangledname,0))));
         maybe_concat_external(p^.excepttype^.owner,
           p^.excepttype^.vmt_mangledname);

         emitcall('FPC_CATCHES',true);
         exprasmlist^.concat(new(pai386,
           op_reg_reg(A_TEST,S_L,R_EAX,R_EAX)));
         emitl(A_JE,nextonlabel);
         ref.symbol:=nil;
         gettempofsizereference(4,ref);

         { what a hack ! }
         if assigned(p^.exceptsymtable) then
           pvarsym(p^.exceptsymtable^.root)^.address:=ref.offset;

         exprasmlist^.concat(new(pai386,op_reg_ref(A_MOV,S_L,
           R_EAX,newreference(ref))));

         if assigned(p^.right) then
           secondpass(p^.right);
         { clear some stuff }
         ungetiftemp(ref);
         emitl(A_JMP,endexceptlabel);
         emitl(A_LABEL,nextonlabel);
         { next on node }
         if assigned(p^.left) then
           secondpass(p^.left);
      end;

{*****************************************************************************
                             SecondTryFinally
*****************************************************************************}

    procedure secondtryfinally(var p : ptree);

      var
         finallylabel,noreraiselabel,endfinallylabel : plabel;

      begin
         { we modify EAX }
         usedinproc:=usedinproc or ($80 shr byte(R_EAX));

         getlabel(finallylabel);
         getlabel(noreraiselabel);
         getlabel(endfinallylabel);
         push_int(1); { Type of stack-frame must be pushed}
         emitcall('FPC_PUSHEXCEPTADDR',true);
         exprasmlist^.concat(new(pai386,
           op_reg(A_PUSH,S_L,R_EAX)));
         emitcall('FPC_SETJMP',true);
         exprasmlist^.concat(new(pai386,
           op_reg(A_PUSH,S_L,R_EAX)));
         exprasmlist^.concat(new(pai386,
           op_reg_reg(A_TEST,S_L,R_EAX,R_EAX)));
         emitl(A_JNE,finallylabel);

         { try code }
         secondpass(p^.left);
         if codegenerror then
           exit;

         emitl(A_LABEL,finallylabel);

         { finally code }
         secondpass(p^.right);
         if codegenerror then
           exit;
         exprasmlist^.concat(new(pai386,
           op_reg(A_POP,S_L,R_EAX)));
         exprasmlist^.concat(new(pai386,
           op_reg_reg(A_TEST,S_L,R_EAX,R_EAX)));
         emitl(A_JE,noreraiselabel);
         emitcall('FPC_RERAISE',true);
         emitl(A_LABEL,noreraiselabel);
         emitcall('FPC_POPADDRSTACK',true);
         emitl(A_LABEL,endfinallylabel);
      end;


{*****************************************************************************
                             SecondFail
*****************************************************************************}

    procedure secondfail(var p : ptree);
      var
        hp : preference;
      begin
         exprasmlist^.concat(new(pai386,op_reg_reg(A_XOR,S_L,R_ESI,R_ESI)));
         { also reset to zero in the stack }
         new(hp);
         reset_reference(hp^);
         hp^.offset:=procinfo.ESI_offset;
         hp^.base:=procinfo.framepointer;
         exprasmlist^.concat(new(pai386,op_reg_ref(A_MOV,S_L,R_ESI,hp)));
         exprasmlist^.concat(new(pai_labeled,init(A_JMP,quickexitlabel)));
      end;


end.
{
  $Log$
  Revision 1.20  1998-10-06 17:16:42  pierre
    * some memory leaks fixed (thanks to Peter for heaptrc !)

  Revision 1.19  1998/09/28 12:13:53  peter
    * fixed repeat continue until true;

  Revision 1.18  1998/09/26 15:03:04  florian
    * small problems with DOM and excpetions fixed (code generation
      of raise was wrong and self was sometimes destroyed :()

  Revision 1.17  1998/09/17 09:42:14  peter
    + pass_2 for cg386
    * Message() -> CGMessage() for pass_1/pass_2

  Revision 1.16  1998/09/14 10:43:48  peter
    * all internal RTL functions start with FPC_

  Revision 1.15  1998/09/04 08:41:39  peter
    * updated some error CGMessages

  Revision 1.14  1998/09/03 17:08:39  pierre
    * better lines for stabs
      (no scroll back to if before else part
      no return to case line at jump outside case)
    + source lines also if not in order

  Revision 1.13  1998/09/01 12:47:58  peter
    * use pdef^.size instead of orddef^.typ

  Revision 1.12  1998/08/28 10:56:58  peter
    * removed warnings

  Revision 1.11  1998/08/05 16:00:10  florian
    * some fixes for ansi strings

  Revision 1.10  1998/08/04 16:26:26  jonas
    * converted // comment to TP comment

  Revision 1.9  1998/07/31 11:36:34  michael
  Default exception handler also needs to call FPC_CATCHES

  Revision 1.8  1998/07/30 13:30:32  florian
    * final implemenation of exception support, maybe it needs
      some fixes :)

  Revision 1.7  1998/07/30 11:18:13  florian
    + first implementation of try ... except on .. do end;
    * limitiation of 65535 bytes parameters for cdecl removed

  Revision 1.6  1998/07/29 13:29:11  michael
  + Corrected try.. code. Type of exception fram is pushed

  Revision 1.5  1998/07/28 21:52:49  florian
    + implementation of raise and try..finally
    + some misc. exception stuff

  Revision 1.4  1998/07/24 22:16:53  florian
    * internal error 10 together with array access fixed. I hope
      that's the final fix.

  Revision 1.3  1998/06/25 08:48:08  florian
    * first version of rtti support

  Revision 1.2  1998/06/08 13:13:33  pierre
    + temporary variables now in temp_gen.pas unit
      because it is processor independent
    * mppc68k.bat modified to undefine i386 and support_mmx
      (which are defaults for i386)

  Revision 1.1  1998/06/05 17:44:12  peter
    * splitted cgi386

}

