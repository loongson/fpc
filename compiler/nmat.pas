{
    $Id$
    Copyright (c) 2000 by Florian Klaempfl

    Type checking and register allocation for math nodes

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
unit nmat;

{$i defines.inc}

interface

    uses
       node;

    type
       tmoddivnode = class(tbinopnode)
          function pass_1 : tnode;override;
          function det_resulttype:tnode;override;
         protected
          { override the following if you want to implement }
          { parts explicitely in the code generator (JM)    }
          function first_moddiv64bitint: tnode; virtual;
       end;
       tmoddivnodeclass = class of tmoddivnode;

       tshlshrnode = class(tbinopnode)
          function pass_1 : tnode;override;
          function det_resulttype:tnode;override;
       end;
       tshlshrnodeclass = class of tshlshrnode;

       tunaryminusnode = class(tunarynode)
          constructor create(expr : tnode);virtual;
          function pass_1 : tnode;override;
          function det_resulttype:tnode;override;
       end;
       tunaryminusnodeclass = class of tunaryminusnode;

       tnotnode = class(tunarynode)
          constructor create(expr : tnode);virtual;
          function pass_1 : tnode;override;
          function det_resulttype:tnode;override;
       end;
       tnotnodeclass = class of tnotnode;

    var
       cmoddivnode : tmoddivnodeclass;
       cshlshrnode : tshlshrnodeclass;
       cunaryminusnode : tunaryminusnodeclass;
       cnotnode : tnotnodeclass;


implementation

    uses
      systems,tokens,
      verbose,globals,cutils,
{$ifdef support_mmx}
      globtype,
{$endif}
      symconst,symtype,symtable,symdef,types,
      htypechk,pass_1,cpubase,cpuinfo,
      cgbase,
      ncon,ncnv,ncal,nadd;

{****************************************************************************
                              TMODDIVNODE
 ****************************************************************************}

    function tmoddivnode.det_resulttype:tnode;
      var
         t : tnode;
         rd,ld : tdef;
         rv,lv : tconstexprint;
      begin
         result:=nil;
         resulttypepass(left);
         resulttypepass(right);
         set_varstate(left,true);
         set_varstate(right,true);
         if codegenerror then
           exit;

         { constant folding }
         if is_constintnode(left) and is_constintnode(right) then
           begin
              rv:=tordconstnode(right).value;
              lv:=tordconstnode(left).value;

              { check for division by zero }
              if (rv=0) then
               begin
                 Message(parser_e_division_by_zero);
                 { recover }
                 rv:=1;
               end;

              case nodetype of
                modn:
                  t:=genintconstnode(lv mod rv);
                divn:
                  t:=genintconstnode(lv div rv);
              end;
              result:=t;
              exit;
           end;

         { allow operator overloading }
         t:=self;
         if isbinaryoverloaded(t) then
           begin
              result:=t;
              exit;
           end;

         { if one operand is a cardinal and the other is a positive constant, convert the }
         { constant to a cardinal as well so we don't have to do a 64bit division (JM)    }

         { Do the same for qwords and positive constants as well, otherwise things like   }
         { "qword mod 10" are evaluated with int64 as result, which is wrong if the       }
         { "qword" was > high(int64) (JM)                                                 }
         if (left.resulttype.def.deftype=orddef) and (right.resulttype.def.deftype=orddef) then
           if (torddef(right.resulttype.def).typ in [u32bit,u64bit]) and
              is_constintnode(left) and
              (tordconstnode(left).value >= 0) then
             inserttypeconv(left,right.resulttype)
           else if (torddef(left.resulttype.def).typ in [u32bit,u64bit]) and
              is_constintnode(right) and
              (tordconstnode(right).value >= 0) then
             inserttypeconv(right,left.resulttype);

         if (left.resulttype.def.deftype=orddef) and (right.resulttype.def.deftype=orddef) and
            (is_64bitint(left.resulttype.def) or is_64bitint(right.resulttype.def) or
             { when mixing cardinals and signed numbers, convert everythign to 64bit (JM) }
             ((torddef(right.resulttype.def).typ = u32bit) and
              is_signed(left.resulttype.def)) or
             ((torddef(left.resulttype.def).typ = u32bit) and
              is_signed(right.resulttype.def))) then
           begin
              rd:=right.resulttype.def;
              ld:=left.resulttype.def;
              { issue warning if necessary }
              if not (is_64bitint(left.resulttype.def) or is_64bitint(right.resulttype.def)) then
                CGMessage(type_w_mixed_signed_unsigned);
              if is_signed(rd) or is_signed(ld) then
                begin
                   if (torddef(ld).typ<>s64bit) then
                     inserttypeconv(left,cs64bittype);
                   if (torddef(rd).typ<>s64bit) then
                     inserttypeconv(right,cs64bittype);
                end
              else
                begin
                   if (torddef(ld).typ<>u64bit) then
                     inserttypeconv(left,cu64bittype);
                   if (torddef(rd).typ<>u64bit) then
                     inserttypeconv(right,cu64bittype);
                end;
              resulttype:=left.resulttype;
           end
         else
           begin
              if not(right.resulttype.def.deftype=orddef) or
                 not(torddef(right.resulttype.def).typ in [s32bit,u32bit]) then
                inserttypeconv(right,s32bittype);

              if not(left.resulttype.def.deftype=orddef) or
                 not(torddef(left.resulttype.def).typ in [s32bit,u32bit]) then
                inserttypeconv(left,s32bittype);

              { the resulttype.def depends on the right side, because the left becomes }
              { always 64 bit                                                      }
              resulttype:=right.resulttype;
           end;
      end;


    function tmoddivnode.first_moddiv64bitint: tnode;
      var
        procname: string[31];
        power: longint;
      begin
        result := nil;
        
        { divide/mod an unsigned number by a constant which is a power of 2? }
        if (right.nodetype = ordconstn) and
           not is_signed(resulttype.def) and
           ispowerof2(tordconstnode(right).value,power) then
          begin
            if nodetype = divn then
              begin
                tordconstnode(right).value := power;
                result := cshlshrnode.create(shrn,left,right)
              end
            else
              begin
                dec(tordconstnode(right).value);
                result := caddnode.create(andn,left,right);
              end;
            { left and right are reused }
            left := nil;
            right := nil;
            firstpass(result);
            exit;
          end;
          
        { otherwise create a call to a helper }
        if nodetype = divn then
          procname := 'fpc_div_'
        else
          procname := 'fpc_mod_';
        if is_signed(resulttype.def) then
          procname := procname + 'int64'
        else
          procname := procname + 'qword';

        result := ccallnode.createintern(procname,ccallparanode.create(left,
          ccallparanode.create(right,nil)));
        left := nil;
        right := nil;
        firstpass(result);
      end;

    function tmoddivnode.pass_1 : tnode;
      begin
         result:=nil;
         firstpass(left);
         firstpass(right);
         if codegenerror then
           exit;

         { 64bit }
         if (left.resulttype.def.deftype=orddef) and (right.resulttype.def.deftype=orddef) and
            (is_64bitint(left.resulttype.def) or is_64bitint(right.resulttype.def)) then
           begin
             result := first_moddiv64bitint;
             if assigned(result) then
               exit;
             location.loc:=LOC_REGISTER;
             calcregisters(self,2,0,0);
           end
         else
           begin
             left_right_max;
             if left.registers32<=right.registers32 then
              inc(registers32);
           end;
         location.loc:=LOC_REGISTER;
      end;



{****************************************************************************
                              TSHLSHRNODE
 ****************************************************************************}

    function tshlshrnode.det_resulttype:tnode;
      var
         t : tnode;
      begin
         result:=nil;
         resulttypepass(left);
         resulttypepass(right);
         set_varstate(right,true);
         set_varstate(left,true);
         if codegenerror then
           exit;

         { constant folding }
         if is_constintnode(left) and is_constintnode(right) then
           begin
              case nodetype of
                 shrn:
                   t:=genintconstnode(tordconstnode(left).value shr tordconstnode(right).value);
                 shln:
                   t:=genintconstnode(tordconstnode(left).value shl tordconstnode(right).value);
              end;
              result:=t;
              exit;
           end;

         { allow operator overloading }
         t:=self;
         if isbinaryoverloaded(t) then
           begin
              result:=t;
              exit;
           end;

         { 64 bit ints have their own shift handling }
         if not(is_64bitint(left.resulttype.def)) then
           begin
              if torddef(left.resulttype.def).typ <> u32bit then
               inserttypeconv(left,s32bittype);
           end;

         inserttypeconv(right,s32bittype);

         resulttype:=left.resulttype;
      end;


    function tshlshrnode.pass_1 : tnode;
      var
         regs : longint;
      begin
         result:=nil;
         firstpass(left);
         firstpass(right);
         if codegenerror then
           exit;

         { 64 bit ints have their own shift handling }
         if not(is_64bitint(left.resulttype.def)) then
          regs:=1
         else
          regs:=2;

         if (right.nodetype<>ordconstn) then
          inc(regs);
         location.loc:=LOC_REGISTER;
         calcregisters(self,regs,0,0);
      end;


{****************************************************************************
                            TUNARYMINUSNODE
 ****************************************************************************}

    constructor tunaryminusnode.create(expr : tnode);
      begin
         inherited create(unaryminusn,expr);
      end;

    function tunaryminusnode.det_resulttype : tnode;
      var
         t : tnode;
         minusdef : tprocdef;
      begin
         result:=nil;
         resulttypepass(left);
         set_varstate(left,true);
         if codegenerror then
           exit;

         { constant folding }
         if is_constintnode(left) then
           begin
              tordconstnode(left).value:=-tordconstnode(left).value;
              result:=left;
              left:=nil;
              exit;
           end;
         if is_constrealnode(left) then
           begin
              trealconstnode(left).value_real:=-trealconstnode(left).value_real;
              result:=left;
              left:=nil;
              exit;
           end;

         resulttype:=left.resulttype;
         if (left.resulttype.def.deftype=floatdef) then
           begin
           end
{$ifdef SUPPORT_MMX}
         else if (cs_mmx in aktlocalswitches) and
           is_mmx_able_array(left.resulttype.def) then
             begin
               { if saturation is on, left.resulttype.def isn't
                 "mmx able" (FK)
               if (cs_mmx_saturation in aktlocalswitches^) and
                 (torddef(tarraydef(resulttype.def).definition).typ in
                 [s32bit,u32bit]) then
                 CGMessage(type_e_mismatch);
               }
             end
{$endif SUPPORT_MMX}
         else if is_64bitint(left.resulttype.def) then
           begin
           end
         else if (left.resulttype.def.deftype=orddef) then
           begin
              inserttypeconv(left,s32bittype);
              resulttype:=left.resulttype;
           end
         else
           begin
              if assigned(overloaded_operators[_minus]) then
                minusdef:=overloaded_operators[_minus].definition
              else
                minusdef:=nil;
              while assigned(minusdef) do
                begin
                   if is_equal(tparaitem(minusdef.para.first).paratype.def,left.resulttype.def) and
                      (tparaitem(minusdef.para.first).next=nil) then
                     begin
                        t:=ccallnode.create(ccallparanode.create(left,nil),
                                            overloaded_operators[_minus],nil,nil);
                        left:=nil;
                        result:=t;
                        exit;
                     end;
                   minusdef:=minusdef.nextoverloaded;
                end;
              CGMessage(type_e_mismatch);
           end;
      end;

    { generic code     }
    { overridden by:   }
    {   i386           }
    function tunaryminusnode.pass_1 : tnode;
      begin
         result:=nil;
         firstpass(left);
         if codegenerror then
           exit;

         registers32:=left.registers32;
         registersfpu:=left.registersfpu;
{$ifdef SUPPORT_MMX}
         registersmmx:=left.registersmmx;
{$endif SUPPORT_MMX}

         if (left.resulttype.def.deftype=floatdef) then
           begin
              if (left.location.loc<>LOC_REGISTER) and
                 (registers32<1) then
                registers32:=1;
              location.loc:=LOC_REGISTER;
           end
{$ifdef SUPPORT_MMX}
         else if (cs_mmx in aktlocalswitches) and
           is_mmx_able_array(left.resulttype.def) then
             begin
               if (left.location.loc<>LOC_MMXREGISTER) and
                  (registersmmx<1) then
                 registersmmx:=1;
             end
{$endif SUPPORT_MMX}
         else if is_64bitint(left.resulttype.def) then
           begin
              if (left.location.loc<>LOC_REGISTER) and
                 (registers32<2) then
                registers32:=2;
              location.loc:=LOC_REGISTER;
           end
         else if (left.resulttype.def.deftype=orddef) then
           begin
              if (left.location.loc<>LOC_REGISTER) and
                 (registers32<1) then
                registers32:=1;
              location.loc:=LOC_REGISTER;
           end;
      end;


{****************************************************************************
                               TNOTNODE
 ****************************************************************************}

    constructor tnotnode.create(expr : tnode);

      begin
         inherited create(notn,expr);
      end;

    function tnotnode.det_resulttype : tnode;
      var
         t : tnode;
         notdef : tprocdef;
         v : tconstexprint;
      begin
         result:=nil;
         resulttypepass(left);
         set_varstate(left,true);
         if codegenerror then
           exit;

         { constant folding }
         if (left.nodetype=ordconstn) then
           begin
              v:=tordconstnode(left).value;
              case torddef(left.resulttype.def).typ of
                bool8bit,
                bool16bit,
                bool32bit :
                  begin
                    { here we do a boolean(byte(..)) type cast because }
                    { boolean(<int64>) is buggy in 1.00                }
                    v:=byte(not(boolean(byte(v))));
                  end;
                uchar,
                u8bit :
                  v:=byte(not byte(v));
                s8bit :
                  v:=shortint(not shortint(v));
                uwidechar,
                u16bit :
                  v:=word(not word(v));
                s16bit :
                  v:=smallint(not smallint(v));
                u32bit :
                  v:=cardinal(not cardinal(v));
                s32bit :
                  v:=longint(not longint(v));
                u64bit :
                  v:=int64(not int64(v)); { maybe qword is required }
                s64bit :
                  v:=int64(not int64(v));
                else
                  CGMessage(type_e_mismatch);
              end;
              t:=cordconstnode.create(v,left.resulttype);
              result:=t;
              exit;
           end;

         resulttype:=left.resulttype;
         if is_boolean(resulttype.def) then
           begin
           end
         else
{$ifdef SUPPORT_MMX}
           if (cs_mmx in aktlocalswitches) and
             is_mmx_able_array(left.resulttype.def) then
             begin
             end
         else
{$endif SUPPORT_MMX}
           if is_64bitint(left.resulttype.def) then
             begin
             end
         else if is_integer(left.resulttype.def) then
           begin
           end
         else
           begin
              if assigned(overloaded_operators[_op_not]) then
                notdef:=overloaded_operators[_op_not].definition
              else
                notdef:=nil;
              while assigned(notdef) do
                begin
                   if is_equal(tparaitem(notdef.para.first).paratype.def,left.resulttype.def) and
                      (tparaitem(notdef.para.first).next=nil) then
                     begin
                        t:=ccallnode.create(ccallparanode.create(left,nil),
                                            overloaded_operators[_op_not],nil,nil);
                        left:=nil;
                        result:=t;
                        exit;
                     end;
                   notdef:=notdef.nextoverloaded;
                end;
              CGMessage(type_e_mismatch);
           end;
      end;


    function tnotnode.pass_1 : tnode;
      begin
         result:=nil;
         firstpass(left);
         if codegenerror then
           exit;

         location.loc:=left.location.loc;
         registers32:=left.registers32;
{$ifdef SUPPORT_MMX}
         registersmmx:=left.registersmmx;
{$endif SUPPORT_MMX}
         if is_boolean(resulttype.def) then
           begin
             if (location.loc in [LOC_REFERENCE,LOC_MEM,LOC_CREGISTER]) then
              begin
                location.loc:=LOC_REGISTER;
                if (registers32<1) then
                 registers32:=1;
              end;
            { before loading it into flags we need to load it into
              a register thus 1 register is need PM }
{$ifdef i386}
             if left.location.loc<>LOC_JUMP then
               location.loc:=LOC_FLAGS;
{$endif def i386}
           end
         else
{$ifdef SUPPORT_MMX}
           if (cs_mmx in aktlocalswitches) and
             is_mmx_able_array(left.resulttype.def) then
             begin
               if (left.location.loc<>LOC_MMXREGISTER) and
                 (registersmmx<1) then
                 registersmmx:=1;
             end
         else
{$endif SUPPORT_MMX}
           if is_64bitint(left.resulttype.def) then
             begin
                if (location.loc in [LOC_REFERENCE,LOC_MEM,LOC_CREGISTER]) then
                 begin
                   location.loc:=LOC_REGISTER;
                   if (registers32<2) then
                    registers32:=2;
                 end;
             end
         else if is_integer(left.resulttype.def) then
           begin
              if (left.location.loc<>LOC_REGISTER) and
                 (registers32<1) then
                registers32:=1;
              location.loc:=LOC_REGISTER;
           end
      end;

begin
   cmoddivnode:=tmoddivnode;
   cshlshrnode:=tshlshrnode;
   cunaryminusnode:=tunaryminusnode;
   cnotnode:=tnotnode;
end.
{
  $Log$
  Revision 1.24  2001-10-12 13:51:51  jonas
    * fixed internalerror(10) due to previous fpu overflow fixes ("merged")
    * fixed bug in n386add (introduced after compilerproc changes for string
      operations) where calcregisters wasn't called for shortstring addnodes
    * NOTE: from now on, the location of a binary node must now always be set
       before you call calcregisters() for it

  Revision 1.23  2001/09/05 15:22:09  jonas
    * made multiplying, dividing and mod'ing of int64 and qword processor
      independent with compilerprocs (+ small optimizations by using shift/and
      where possible)

  Revision 1.22  2001/09/02 21:12:07  peter
    * move class of definitions into type section for delphi

  Revision 1.21  2001/08/26 13:36:41  florian
    * some cg reorganisation
    * some PPC updates

  Revision 1.20  2001/04/13 01:22:10  peter
    * symtable change to classes
    * range check generation and errors fixed, make cycle DEBUG=1 works
    * memory leaks fixed

  Revision 1.19  2001/04/05 21:00:27  peter
    * fix constant not evaluation

  Revision 1.18  2001/04/04 22:42:40  peter
    * move constant folding into det_resulttype

  Revision 1.17  2001/04/02 21:20:31  peter
    * resulttype rewrite

  Revision 1.16  2001/03/20 18:11:03  jonas
    * not (cardinal) now has cardinal instead of longint result (bug reported
      in mailinglist) ("merged")

  Revision 1.15  2001/03/04 10:38:55  jonas
    * fixed 'qword mod/div pos_const' to have qword result

  Revision 1.14  2001/02/20 21:48:17  peter
    * remove nasm hack

  Revision 1.13  2001/01/06 18:28:39  peter
    * fixed wrong notes about locals

  Revision 1.12  2001/01/05 17:36:57  florian
  * the info about exception frames is stored now on the stack
  instead on the heap

  Revision 1.11  2000/12/25 00:07:26  peter
    + new tlinkedlist class (merge of old tstringqueue,tcontainer and
      tlinkedlist objects)

  Revision 1.10  2000/12/16 15:54:01  jonas
    * 'resulttype.def of cardinal shl/shr x' is cardinal instead of longint

  Revision 1.9  2000/11/29 00:30:34  florian
    * unused units removed from uses clause
    * some changes for widestrings

  Revision 1.8  2000/10/31 22:02:49  peter
    * symtable splitted, no real code changes

  Revision 1.7  2000/10/01 19:48:24  peter
    * lot of compile updates for cg11

  Revision 1.6  2000/09/27 21:33:22  florian
    * finally nadd.pas compiles

  Revision 1.5  2000/09/27 20:25:44  florian
    * more stuff fixed

  Revision 1.4  2000/09/24 15:06:19  peter
    * use defines.inc

  Revision 1.3  2000/09/22 22:48:54  florian
    * some fixes

  Revision 1.2  2000/09/22 22:09:54  florian
    * more stuff converted

  Revision 1.1  2000/09/20 21:35:12  florian
    * initial revision
}
