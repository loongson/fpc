{
    $Id$
    Copyright (c) 1998-2002 by Florian Klaempfl

    Generate x86-64 assembler for math nodes

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
unit nx64mat;

{$i fpcdefs.inc}

interface

    uses
      node,nmat,ncgmat,nx86mat;

    type
      tx8664moddivnode = class(tmoddivnode)
         procedure pass_2;override;
      end;

      tx8664shlshrnode = class(tshlshrnode)
         procedure pass_2;override;
      end;

      tx8664unaryminusnode = class(tx86unaryminusnode)
      end;

      tx8664notnode = class(tx86notnode)
      end;

implementation

    uses
      globtype,systems,
      cutils,verbose,globals,
      symconst,symdef,aasmbase,aasmtai,defutil,
      pass_1,pass_2,
      ncon,
      cpubase,cpuinfo,
      cgbase,cgutils,cga,cgobj,cgx86,
      ncgutil;

{*****************************************************************************
                             TX8664MODDIVNODE
*****************************************************************************}

    procedure tx8664moddivnode.pass_2;
      var
        hreg1,hreg2:Tregister;
        power:longint;
        op:Tasmop;
      begin
        secondpass(left);
        if codegenerror then
          exit;
        secondpass(right);
        if codegenerror then
          exit;

        { put numerator in register }
        location_reset(location,LOC_REGISTER,OS_INT);
        location_force_reg(exprasmlist,left.location,OS_INT,false);
        hreg1:=left.location.register;

        if (nodetype=divn) and (right.nodetype=ordconstn) and
           ispowerof2(int64(tordconstnode(right).value),power) then
          begin
            { for signed numbers, the numerator must be adjusted before the
              shift instruction, but not wih unsigned numbers! Otherwise,
              "Cardinal($ffffffff) div 16" overflows! (JM) }
            if is_signed(left.resulttype.def) Then
              begin
                  { use a sequence without jumps, saw this in
                    comp.compilers (JM) }
                  { no jumps, but more operations }
                  hreg2:=cg.getintregister(exprasmlist,OS_INT);
                  emit_reg_reg(A_MOV,S_Q,hreg1,hreg2);
                  {If the left value is signed, hreg2=$ffffffff, otherwise 0.}
                  emit_const_reg(A_SAR,S_Q,63,hreg2);
                  {If signed, hreg2=right value-1, otherwise 0.}
                  emit_const_reg(A_AND,S_Q,tordconstnode(right).value-1,hreg2);
                  { add to the left value }
                  emit_reg_reg(A_ADD,S_Q,hreg2,hreg1);
                  { do the shift }
                  emit_const_reg(A_SAR,S_Q,power,hreg1);
              end
            else
              emit_const_reg(A_SHR,S_Q,power,hreg1);
            location.register:=hreg1;
          end
        else
          begin
            {Bring denominator to a register.}
            cg.getcpuregister(exprasmlist,NR_RAX);
            emit_reg_reg(A_MOV,S_Q,hreg1,NR_RAX);
            cg.getcpuregister(exprasmlist,NR_RDX);
            {Sign extension depends on the left type.}
            if torddef(left.resulttype.def).typ=u64bit then
              emit_reg_reg(A_XOR,S_Q,NR_RDX,NR_RDX)
            else
              emit_none(A_CDO,S_NO);

            {Division depends on the right type.}
            if Torddef(right.resulttype.def).typ=u64bit then
              op:=A_DIV
            else
              op:=A_IDIV;

            if right.location.loc in [LOC_REFERENCE,LOC_CREFERENCE] then
              emit_ref(op,S_Q,right.location.reference)
            else if right.location.loc in [LOC_REGISTER,LOC_CREGISTER] then
              emit_reg(op,S_Q,right.location.register)
            else
              begin
                hreg1:=cg.getintregister(exprasmlist,right.location.size);
                cg.a_load_loc_reg(exprasmlist,OS_64,right.location,hreg1);
                emit_reg(op,S_Q,hreg1);
              end;

            { Copy the result into a new register. Release RAX & RDX.}
            cg.ungetcpuregister(exprasmlist,NR_RDX);
            cg.ungetcpuregister(exprasmlist,NR_RAX);
            location.register:=cg.getintregister(exprasmlist,OS_INT);
            if nodetype=divn then
              cg.a_load_reg_reg(exprasmlist,OS_INT,OS_INT,NR_RAX,location.register)
            else
              cg.a_load_reg_reg(exprasmlist,OS_INT,OS_INT,NR_RDX,location.register);
          end;
      end;


{*****************************************************************************
                             TX8664SHLRSHRNODE
*****************************************************************************}


    procedure tx8664shlshrnode.pass_2;
      var
        op : Tasmop;
        opsize : tcgsize;
        mask : aint;
      begin
        secondpass(left);
        secondpass(right);

        { determine operator }
        if nodetype=shln then
          op:=A_SHL
        else
          op:=A_SHR;

        { special treatment of 32bit values for backwards compatibility }
        if left.resulttype.def.size<=4 then
          begin
            opsize:=OS_32;
            mask:=31;
          end
        else
          begin
            opsize:=OS_64;
            mask:=63;
          end;

        { load left operators in a register }
        location_copy(location,left.location);
        location_force_reg(exprasmlist,location,opsize,false);

        { shifting by a constant directly coded: }
        if (right.nodetype=ordconstn) then
          emit_const_reg(op,tcgsize2opsize[opsize],tordconstnode(right).value and mask,location.register)
        else
          begin
            { load right operators in a RCX }
            cg.getcpuregister(exprasmlist,NR_RCX);
            cg.a_load_loc_reg(exprasmlist,OS_INT,right.location,NR_RCX);

            { right operand is in ECX }
            cg.ungetcpuregister(exprasmlist,NR_RCX);
            emit_reg_reg(op,tcgsize2opsize[opsize],NR_CL,location.register);
          end;
      end;


begin
   cunaryminusnode:=tx8664unaryminusnode;
   cmoddivnode:=tx8664moddivnode;
   cshlshrnode:=tx8664shlshrnode;
   cnotnode:=tx8664notnode;
end.
{
  $Log$
  Revision 1.8  2004-11-01 17:40:29  florian
    + added cgutils uses clause

  Revision 1.7  2004/09/25 14:23:55  peter
    * ungetregister is now only used for cpuregisters, renamed to
      ungetcpuregister
    * renamed (get|unget)explicitregister(s) to ..cpuregister
    * removed location-release/reference_release

  Revision 1.6  2004/06/20 08:55:32  florian
    * logs truncated

  Revision 1.5  2004/06/16 20:07:11  florian
    * dwarf branch merged

  Revision 1.4.2.3  2004/05/03 16:27:38  peter
    * fixed shl for x86-64

  Revision 1.4.2.2  2004/04/26 15:54:33  peter
    * small x86-64 fixes

  Revision 1.4.2.1  2004/04/24 16:02:19  florian
    * sign extension for int div int fixed

  Revision 1.4  2004/02/05 18:28:37  peter
    * x86_64 fixes for opsize

}
