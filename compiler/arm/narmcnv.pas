{
    $Id$
    Copyright (c) 1998-2002 by Florian Klaempfl

    Generate ARM assembler for type converting nodes

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
unit narmcnv;

{$i fpcdefs.inc}

interface

    uses
      node,ncnv,ncgcnv,defcmp;

    type
       tarmtypeconvnode = class(tcgtypeconvnode)
         protected
           function first_int_to_real: tnode;override;
         { procedure second_int_to_int;override; }
         { procedure second_string_to_string;override; }
         { procedure second_cstring_to_pchar;override; }
         { procedure second_string_to_chararray;override; }
         { procedure second_array_to_pointer;override; }
         // function first_int_to_real: tnode; override;
         { procedure second_pointer_to_array;override; }
         { procedure second_chararray_to_string;override; }
         { procedure second_char_to_string;override; }
           procedure second_int_to_real;override;
         // procedure second_real_to_real;override;
         { procedure second_cord_to_pointer;override; }
         { procedure second_proc_to_procvar;override; }
         { procedure second_bool_to_int;override; }
           procedure second_int_to_bool;override;
         { procedure second_load_smallset;override;  }
         { procedure second_ansistring_to_pchar;override; }
         { procedure second_pchar_to_string;override; }
         { procedure second_class_to_intf;override; }
         { procedure second_char_to_char;override; }
       end;

implementation

   uses
      verbose,globals,systems,
      symconst,symdef,aasmbase,aasmtai,
      defutil,
      cgbase,pass_1,pass_2,
      ncon,ncal,
      ncgutil,
      cpubase,aasmcpu,
      rgobj,tgobj,cgobj,cgcpu;


{*****************************************************************************
                             FirstTypeConv
*****************************************************************************}

    function tarmtypeconvnode.first_int_to_real: tnode;
      var
        fname: string[19];
      begin
        { converting a 64bit integer to a float requires a helper }
        if is_64bitint(left.resulttype.def) then
          begin
            if is_signed(left.resulttype.def) then
              fname := 'fpc_int64_to_double'
            else
              fname := 'fpc_qword_to_double';
            result := ccallnode.createintern(fname,ccallparanode.create(
              left,nil));
            left:=nil;
            firstpass(result);
            exit;
          end
        else
          { other integers are supposed to be 32 bit }
          begin
            if is_signed(left.resulttype.def) then
              inserttypeconv(left,s32bittype)
            else
              inserttypeconv(left,u32bittype);
            firstpass(left);
          end;
        result := nil;
        if registersfpu<1 then
          registersfpu:=1;
        expectloc:=LOC_FPUREGISTER;
      end;


    procedure tarmtypeconvnode.second_int_to_real;
      var
        instr : taicpu;
      begin
        location_reset(location,LOC_FPUREGISTER,def_cgsize(resulttype.def));
        location_force_reg(exprasmlist,left.location,OS_32,true);
        location.register:=cg.getfpuregister(exprasmlist,location.size);
        instr:=taicpu.op_reg_reg(A_FLT,location.register,left.location.register);
        instr.oppostfix:=cgsize2fpuoppostfix[def_cgsize(resulttype.def)];
        exprasmlist.concat(instr);
      end;


    procedure tarmtypeconvnode.second_int_to_bool;
      var
        hregister : tregister;
        href      : treference;
        resflags  : tresflags;
        hlabel,oldtruelabel,oldfalselabel : tasmlabel;
      begin
         oldtruelabel:=truelabel;
         oldfalselabel:=falselabel;
         objectlibrary.getlabel(truelabel);
         objectlibrary.getlabel(falselabel);
         secondpass(left);
         if codegenerror then
          exit;
         { byte(boolean) or word(wordbool) or longint(longbool) must
           be accepted for var parameters                            }
         if (nf_explicit in flags) and
            (left.resulttype.def.size=resulttype.def.size) and
            (left.location.loc in [LOC_REFERENCE,LOC_CREFERENCE,LOC_CREGISTER]) then
           begin
              location_copy(location,left.location);
              truelabel:=oldtruelabel;
              falselabel:=oldfalselabel;
              exit;
           end;

         { Load left node into flag F_NE/F_E }
         resflags:=F_NE;
         case left.location.loc of
            LOC_CREFERENCE,
            LOC_REFERENCE :
              begin
                if left.location.size in [OS_64,OS_S64] then
                 begin
                   location_release(exprasmlist,left.location);
                   hregister:=cg.getintregister(exprasmlist,OS_INT);
                   cg.a_load_ref_reg(exprasmlist,OS_32,OS_32,left.location.reference,hregister);
                   href:=left.location.reference;
                   inc(href.offset,4);
                   cg.ungetregister(exprasmlist,hregister);
                   tcgarm(cg).setflags:=true;
                   cg.a_op_ref_reg(exprasmlist,OP_OR,OS_32,href,hregister);
                   tcgarm(cg).setflags:=false;
                 end
                else
                 begin
                   location_force_reg(exprasmlist,left.location,left.location.size,true);
                   location_release(exprasmlist,left.location);
                   tcgarm(cg).setflags:=true;
                   cg.a_op_reg_reg(exprasmlist,OP_OR,left.location.size,left.location.register,left.location.register);
                   tcgarm(cg).setflags:=false;
                 end;
              end;
            LOC_FLAGS :
              begin
                resflags:=left.location.resflags;
              end;
            LOC_REGISTER,LOC_CREGISTER :
              begin
                if left.location.size in [OS_64,OS_S64] then
                 begin
                   hregister:=cg.getintregister(exprasmlist,OS_32);
                   cg.a_load_reg_reg(exprasmlist,OS_32,OS_32,left.location.registerlow,hregister);
                   cg.ungetregister(exprasmlist,hregister);
                   location_release(exprasmlist,left.location);
                   tcgarm(cg).setflags:=true;
                   cg.a_op_reg_reg(exprasmlist,OP_OR,OS_32,left.location.registerhigh,hregister);
                   tcgarm(cg).setflags:=false;
                 end
                else
                 begin
                   location_release(exprasmlist,left.location);
                   tcgarm(cg).setflags:=true;
                   cg.a_op_reg_reg(exprasmlist,OP_OR,left.location.size,left.location.register,left.location.register);
                   tcgarm(cg).setflags:=false;
                 end;
              end;
            LOC_JUMP :
              begin
                hregister:=cg.getintregister(exprasmlist,OS_INT);
                objectlibrary.getlabel(hlabel);
                cg.a_label(exprasmlist,truelabel);
                cg.a_load_const_reg(exprasmlist,OS_INT,1,hregister);
                cg.a_jmp_always(exprasmlist,hlabel);
                cg.a_label(exprasmlist,falselabel);
                cg.a_load_const_reg(exprasmlist,OS_INT,0,hregister);
                cg.a_label(exprasmlist,hlabel);
                cg.ungetregister(exprasmlist,hregister);
                tcgarm(cg).setflags:=true;
                cg.a_op_reg_reg(exprasmlist,OP_OR,OS_INT,hregister,hregister);
                tcgarm(cg).setflags:=false;
              end;
            else
              internalerror(200311301);
         end;
         { load flags to register }
         location_reset(location,LOC_REGISTER,def_cgsize(resulttype.def));
         location.register:=cg.getintregister(exprasmlist,location.size);
         cg.g_flags2reg(exprasmlist,location.size,resflags,location.register);
         truelabel:=oldtruelabel;
         falselabel:=oldfalselabel;
      end;


begin
  ctypeconvnode:=tarmtypeconvnode;
end.
{
  $Log$
  Revision 1.8  2004-01-22 20:13:18  florian
    * fixed several issues with flags

  Revision 1.7  2003/11/30 19:35:29  florian
    * fixed several arm related problems

  Revision 1.6  2003/11/04 22:30:15  florian
    + type cast variant<->enum
    * cnv. node second pass uses now as well helper wrappers

  Revision 1.5  2003/11/02 14:30:03  florian
    * fixed ARM for new reg. allocation scheme

  Revision 1.4  2003/09/01 15:11:16  florian
    * fixed reference handling
    * fixed operand postfix for floating point instructions
    * fixed wrong shifter constant handling

  Revision 1.3  2003/09/01 09:54:57  florian
    *  results of work on arm port last weekend

  Revision 1.2  2003/08/25 23:20:38  florian
    + started to implement FPU support for the ARM
    * fixed a lot of other things

  Revision 1.1  2003/08/21 23:24:08  florian
    * continued to work on the arm skeleton
}
