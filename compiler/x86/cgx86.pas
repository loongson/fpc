{
    $Id$
    Copyright (c) 1998-2002 by Florian Klaempfl

    This unit implements the common parts of the code generator for the i386 and the x86-64.

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
{ This unit implements the common parts of the code generator for the i386 and the x86-64.
}
unit cgx86;

{$i fpcdefs.inc}

  interface

    uses
       globtype,
       cgbase,cgobj,
       aasmbase,aasmtai,aasmcpu,
       cpubase,cpuinfo,rgobj,rgx86,rgcpu,
       symconst,symtype;

    type
      tcgx86 = class(tcg)
        rgfpu   : Trgx86fpu;
        procedure done_register_allocators;override;

        function getfpuregister(list:Taasmoutput;size:Tcgsize):Tregister;override;
        function getmmxregister(list:Taasmoutput):Tregister;

        procedure getcpuregister(list:Taasmoutput;r:Tregister);override;
        procedure ungetcpuregister(list:Taasmoutput;r:Tregister);override;
        procedure alloccpuregisters(list:Taasmoutput;rt:Tregistertype;r:Tcpuregisterset);override;
        procedure dealloccpuregisters(list:Taasmoutput;rt:Tregistertype;r:Tcpuregisterset);override;
        function  uses_registers(rt:Tregistertype):boolean;override;
        procedure add_reg_instruction(instr:Tai;r:tregister);override;
        procedure dec_fpu_stack;
        procedure inc_fpu_stack;

        procedure a_call_name(list : taasmoutput;const s : string);override;
        procedure a_call_reg(list : taasmoutput;reg : tregister);override;

        procedure a_op_const_reg(list : taasmoutput; Op: TOpCG; size: TCGSize; a: aint; reg: TRegister); override;
        procedure a_op_const_ref(list : taasmoutput; Op: TOpCG; size: TCGSize; a: aint; const ref: TReference); override;
        procedure a_op_reg_reg(list : taasmoutput; Op: TOpCG; size: TCGSize; src, dst: TRegister); override;
        procedure a_op_ref_reg(list : taasmoutput; Op: TOpCG; size: TCGSize; const ref: TReference; reg: TRegister); override;
        procedure a_op_reg_ref(list : taasmoutput; Op: TOpCG; size: TCGSize;reg: TRegister; const ref: TReference); override;

        procedure a_op_const_reg_reg(list: taasmoutput; op: TOpCg;
          size: tcgsize; a: aint; src, dst: tregister); override;
        procedure a_op_reg_reg_reg(list: taasmoutput; op: TOpCg;
          size: tcgsize; src1, src2, dst: tregister); override;

        { move instructions }
        procedure a_load_const_reg(list : taasmoutput; tosize: tcgsize; a : aint;reg : tregister);override;
        procedure a_load_const_ref(list : taasmoutput; tosize: tcgsize; a : aint;const ref : treference);override;
        procedure a_load_reg_ref(list : taasmoutput;fromsize,tosize: tcgsize; reg : tregister;const ref : treference);override;
        procedure a_load_ref_reg(list : taasmoutput;fromsize,tosize: tcgsize;const ref : treference;reg : tregister);override;
        procedure a_load_reg_reg(list : taasmoutput;fromsize,tosize: tcgsize;reg1,reg2 : tregister);override;
        procedure a_loadaddr_ref_reg(list : taasmoutput;const ref : treference;r : tregister);override;

        { fpu move instructions }
        procedure a_loadfpu_reg_reg(list: taasmoutput; size: tcgsize; reg1, reg2: tregister); override;
        procedure a_loadfpu_ref_reg(list: taasmoutput; size: tcgsize; const ref: treference; reg: tregister); override;
        procedure a_loadfpu_reg_ref(list: taasmoutput; size: tcgsize; reg: tregister; const ref: treference); override;

        { vector register move instructions }
        procedure a_loadmm_reg_reg(list: taasmoutput; fromsize, tosize : tcgsize;reg1, reg2: tregister;shuffle : pmmshuffle); override;
        procedure a_loadmm_ref_reg(list: taasmoutput; fromsize, tosize : tcgsize;const ref: treference; reg: tregister;shuffle : pmmshuffle); override;
        procedure a_loadmm_reg_ref(list: taasmoutput; fromsize, tosize : tcgsize;reg: tregister; const ref: treference;shuffle : pmmshuffle); override;
        procedure a_opmm_ref_reg(list: taasmoutput; Op: TOpCG; size : tcgsize;const ref: treference; reg: tregister;shuffle : pmmshuffle); override;
        procedure a_opmm_reg_reg(list: taasmoutput; Op: TOpCG; size : tcgsize;src,dst: tregister;shuffle : pmmshuffle);override;

        {  comparison operations }
        procedure a_cmp_const_reg_label(list : taasmoutput;size : tcgsize;cmp_op : topcmp;a : aint;reg : tregister;
          l : tasmlabel);override;
        procedure a_cmp_const_ref_label(list : taasmoutput;size : tcgsize;cmp_op : topcmp;a : aint;const ref : treference;
          l : tasmlabel);override;
        procedure a_cmp_reg_reg_label(list : taasmoutput;size : tcgsize;cmp_op : topcmp;reg1,reg2 : tregister;l : tasmlabel); override;
        procedure a_cmp_ref_reg_label(list : taasmoutput;size : tcgsize;cmp_op : topcmp;const ref: treference; reg : tregister; l : tasmlabel); override;
        procedure a_cmp_reg_ref_label(list : taasmoutput;size : tcgsize;cmp_op : topcmp;reg : tregister; const ref: treference; l : tasmlabel); override;

        procedure a_jmp_name(list : taasmoutput;const s : string);override;
        procedure a_jmp_always(list : taasmoutput;l: tasmlabel); override;
        procedure a_jmp_flags(list : taasmoutput;const f : TResFlags;l: tasmlabel); override;

        procedure g_flags2reg(list: taasmoutput; size: TCgSize; const f: tresflags; reg: TRegister); override;
        procedure g_flags2ref(list: taasmoutput; size: TCgSize; const f: tresflags; const ref: TReference); override;

        procedure g_concatcopy(list : taasmoutput;const source,dest : treference;len : aint; loadref : boolean);override;

        { entry/exit code helpers }
        procedure g_releasevaluepara_openarray(list : taasmoutput;const ref:treference);override;
        procedure g_profilecode(list : taasmoutput);override;
        procedure g_stackpointer_alloc(list : taasmoutput;localsize : longint);override;
        procedure g_proc_entry(list : taasmoutput;localsize : longint;nostackframe:boolean);override;
        procedure g_save_standard_registers(list:Taasmoutput);override;
        procedure g_restore_standard_registers(list:Taasmoutput);override;

        procedure g_overflowcheck(list: taasmoutput; const l:tlocation;def:tdef);override;

      protected
        procedure a_jmp_cond(list : taasmoutput;cond : TOpCmp;l: tasmlabel);
        procedure check_register_size(size:tcgsize;reg:tregister);

        procedure opmm_loc_reg(list: taasmoutput; Op: TOpCG; size : tcgsize;loc : tlocation;dst: tregister; shuffle : pmmshuffle);
      private
        procedure sizes2load(s1,s2 : tcgsize;var op: tasmop; var s3: topsize);

        procedure floatload(list: taasmoutput; t : tcgsize;const ref : treference);
        procedure floatstore(list: taasmoutput; t : tcgsize;const ref : treference);
        procedure floatloadops(t : tcgsize;var op : tasmop;var s : topsize);
        procedure floatstoreops(t : tcgsize;var op : tasmop;var s : topsize);
      end;

    function use_sse(def : tdef) : boolean;

   const
{$ifdef x86_64}
      TCGSize2OpSize: Array[tcgsize] of topsize =
        (S_NO,S_B,S_W,S_L,S_Q,S_Q,S_B,S_W,S_L,S_Q,S_Q,
         S_FS,S_FL,S_FX,S_IQ,S_FXX,
         S_NO,S_NO,S_NO,S_MD,S_NO,S_NO,S_NO,S_NO,S_NO,S_NO);
{$else x86_64}
      TCGSize2OpSize: Array[tcgsize] of topsize =
        (S_NO,S_B,S_W,S_L,S_L,S_L,S_B,S_W,S_L,S_L,S_L,
         S_FS,S_FL,S_FX,S_IQ,S_FXX,
         S_NO,S_NO,S_NO,S_MD,S_NO,S_NO,S_NO,S_NO,S_NO,S_NO);
{$endif x86_64}

{$ifndef NOTARGETWIN32}
      winstackpagesize = 4096;
{$endif NOTARGETWIN32}


  implementation

    uses
       globals,verbose,systems,cutils,
       cgutils,
       dwarf,
       symdef,defutil,paramgr,tgobj,procinfo;

    const
      TOpCG2AsmOp: Array[topcg] of TAsmOp = (A_NONE,A_ADD,A_AND,A_DIV,
                            A_IDIV,A_MUL, A_IMUL, A_NEG,A_NOT,A_OR,
                            A_SAR,A_SHL,A_SHR,A_SUB,A_XOR);

      TOpCmp2AsmCond: Array[topcmp] of TAsmCond = (C_NONE,
          C_E,C_G,C_L,C_GE,C_LE,C_NE,C_BE,C_B,C_AE,C_A);

    function use_sse(def : tdef) : boolean;
      begin
        use_sse:=(is_single(def) and (aktfputype in sse_singlescalar)) or
          (is_double(def) and (aktfputype in sse_doublescalar));
      end;


    procedure Tcgx86.done_register_allocators;
      begin
        rg[R_INTREGISTER].free;
        rg[R_MMREGISTER].free;
        rg[R_MMXREGISTER].free;
        rgfpu.free;
        inherited done_register_allocators;
      end;


    function Tcgx86.getfpuregister(list:Taasmoutput;size:Tcgsize):Tregister;
      begin
        result:=rgfpu.getregisterfpu(list);
      end;

    function Tcgx86.getmmxregister(list:Taasmoutput):Tregister;
      begin
        if not assigned(rg[R_MMXREGISTER]) then
          internalerror(200312124);
        result:=rg[R_MMXREGISTER].getregister(list,R_SUBNONE);
      end;

    procedure Tcgx86.getcpuregister(list:Taasmoutput;r:Tregister);
      begin
        if getregtype(r)=R_FPUREGISTER then
          internalerror(2003121210)
        else
          inherited getcpuregister(list,r);
      end;


    procedure tcgx86.ungetcpuregister(list:Taasmoutput;r:Tregister);
      begin
        if getregtype(r)=R_FPUREGISTER then
          rgfpu.ungetregisterfpu(list,r)
        else
          inherited ungetcpuregister(list,r);
      end;


    procedure Tcgx86.alloccpuregisters(list:Taasmoutput;rt:Tregistertype;r:Tcpuregisterset);
      begin
        if rt<>R_FPUREGISTER then
          inherited alloccpuregisters(list,rt,r);
      end;


    procedure Tcgx86.dealloccpuregisters(list:Taasmoutput;rt:Tregistertype;r:Tcpuregisterset);
      begin
        if rt<>R_FPUREGISTER then
          inherited dealloccpuregisters(list,rt,r);
      end;


    function  Tcgx86.uses_registers(rt:Tregistertype):boolean;
      begin
        if rt=R_FPUREGISTER then
          result:=false
        else
          result:=inherited uses_registers(rt);
      end;


    procedure tcgx86.add_reg_instruction(instr:Tai;r:tregister);
      begin
        if getregtype(r)<>R_FPUREGISTER then
          inherited add_reg_instruction(instr,r);
      end;


    procedure tcgx86.dec_fpu_stack;
      begin
        dec(rgfpu.fpuvaroffset);
      end;


    procedure tcgx86.inc_fpu_stack;
      begin
        inc(rgfpu.fpuvaroffset);
      end;


{****************************************************************************
                       This is private property, keep out! :)
****************************************************************************}

    procedure tcgx86.sizes2load(s1,s2 : tcgsize; var op: tasmop; var s3: topsize);

       begin
         case s2 of
           OS_8,OS_S8 :
             if S1 in [OS_8,OS_S8] then
               s3 := S_B
             else
               internalerror(200109221);
           OS_16,OS_S16:
             case s1 of
               OS_8,OS_S8:
                 s3 := S_BW;
               OS_16,OS_S16:
                 s3 := S_W;
               else
                 internalerror(200109222);
             end;
           OS_32,OS_S32:
             case s1 of
               OS_8,OS_S8:
                 s3 := S_BL;
               OS_16,OS_S16:
                 s3 := S_WL;
               OS_32,OS_S32:
                 s3 := S_L;
               else
                 internalerror(200109223);
             end;
{$ifdef x86_64}
           OS_64,OS_S64:
             case s1 of
               OS_8:
                 s3 := S_BL;
               OS_S8:
                 s3 := S_BQ;
               OS_16:
                 s3 := S_WL;
               OS_S16:
                 s3 := S_WQ;
               OS_32:
                 s3 := S_L;
               OS_S32:
                 s3 := S_LQ;
               OS_64,OS_S64:
                 s3 := S_Q;
               else
                 internalerror(200304302);
             end;
{$endif x86_64}
           else
             internalerror(200109227);
         end;
         if s3 in [S_B,S_W,S_L,S_Q] then
           op := A_MOV
         else if s1 in [OS_8,OS_16,OS_32,OS_64] then
           op := A_MOVZX
         else
{$ifdef x86_64}
           if s3 in [S_LQ] then
             op := A_MOVSXD
         else
{$endif x86_64}
           op := A_MOVSX;
       end;


    procedure tcgx86.floatloadops(t : tcgsize;var op : tasmop;var s : topsize);
      begin
         case t of
            OS_F32 :
              begin
                 op:=A_FLD;
                 s:=S_FS;
              end;
            OS_F64 :
              begin
                 op:=A_FLD;
                 s:=S_FL;
              end;
            OS_F80 :
              begin
                 op:=A_FLD;
                 s:=S_FX;
              end;
            OS_C64 :
              begin
                 op:=A_FILD;
                 s:=S_IQ;
              end;
            else
              internalerror(200204041);
         end;
      end;


    procedure tcgx86.floatload(list: taasmoutput; t : tcgsize;const ref : treference);

      var
         op : tasmop;
         s : topsize;

      begin
         floatloadops(t,op,s);
         list.concat(Taicpu.Op_ref(op,s,ref));
         inc_fpu_stack;
      end;


    procedure tcgx86.floatstoreops(t : tcgsize;var op : tasmop;var s : topsize);

      begin
         case t of
            OS_F32 :
              begin
                 op:=A_FSTP;
                 s:=S_FS;
              end;
            OS_F64 :
              begin
                 op:=A_FSTP;
                 s:=S_FL;
              end;
            OS_F80 :
              begin
                  op:=A_FSTP;
                  s:=S_FX;
               end;
            OS_C64 :
               begin
                  op:=A_FISTP;
                  s:=S_IQ;
               end;
            else
               internalerror(200204042);
         end;
      end;


    procedure tcgx86.floatstore(list: taasmoutput; t : tcgsize;const ref : treference);

      var
         op : tasmop;
         s : topsize;

      begin
         floatstoreops(t,op,s);
         list.concat(Taicpu.Op_ref(op,s,ref));
         dec_fpu_stack;
      end;


    procedure tcgx86.check_register_size(size:tcgsize;reg:tregister);
      begin
        if TCGSize2OpSize[size]<>TCGSize2OpSize[reg_cgsize(reg)] then
          internalerror(200306031);
      end;


{****************************************************************************
                              Assembler code
****************************************************************************}

    procedure tcgx86.a_jmp_name(list : taasmoutput;const s : string);
      begin
        list.concat(taicpu.op_sym(A_JMP,S_NO,objectlibrary.newasmsymbol(s,AB_EXTERNAL,AT_FUNCTION)));
      end;


    procedure tcgx86.a_jmp_always(list : taasmoutput;l: tasmlabel);
      begin
        a_jmp_cond(list, OC_NONE, l);
      end;


    procedure tcgx86.a_call_name(list : taasmoutput;const s : string);
      begin
        list.concat(taicpu.op_sym(A_CALL,S_NO,objectlibrary.newasmsymbol(s,AB_EXTERNAL,AT_FUNCTION)));
      end;


    procedure tcgx86.a_call_reg(list : taasmoutput;reg : tregister);
      begin
        list.concat(taicpu.op_reg(A_CALL,S_NO,reg));
      end;


{********************** load instructions ********************}

    procedure tcgx86.a_load_const_reg(list : taasmoutput; tosize: TCGSize; a : aint; reg : TRegister);

      begin
        check_register_size(tosize,reg);
        { the optimizer will change it to "xor reg,reg" when loading zero, }
        { no need to do it here too (JM)                                   }
        list.concat(taicpu.op_const_reg(A_MOV,TCGSize2OpSize[tosize],a,reg))
      end;


    procedure tcgx86.a_load_const_ref(list : taasmoutput; tosize: tcgsize; a : aint;const ref : treference);

{$ifdef x86_64}
      var
        href : treference;
{$endif x86_64}
      begin
{$ifdef x86_64}
        { x86_64 only supports signed 32 bits constants directly }
        if (tosize in [OS_S64,OS_64]) and
            ((a<low(longint)) or (a>high(longint))) then
          begin
            href:=ref;
            a_load_const_ref(list,OS_32,longint(a and $ffffffff),href);
            inc(href.offset,4);
            a_load_const_ref(list,OS_32,longint(a shr 32),href);
          end
        else
{$endif x86_64}
          list.concat(taicpu.op_const_ref(A_MOV,TCGSize2OpSize[tosize],a,ref));
      end;


    procedure tcgx86.a_load_reg_ref(list : taasmoutput; fromsize,tosize: TCGSize; reg : tregister;const ref : treference);
      var
        op: tasmop;
        s: topsize;
        tmpreg : tregister;
      begin
        check_register_size(fromsize,reg);
        sizes2load(fromsize,tosize,op,s);
        case s of
{$ifdef x86_64}
          S_BQ,S_WQ,S_LQ,
{$endif x86_64}
          S_BW,S_BL,S_WL :
            begin
              tmpreg:=getintregister(list,tosize);
{$ifdef x86_64}
              { zero extensions to 64 bit on the x86_64 are simply done by writting to the lower 32 bit
                which clears the upper 64 bit too, so it could be that s is S_L while the reg is
                64 bit (FK) }
              if s in [S_BL,S_WL,S_L] then
                tmpreg:=makeregsize(list,tmpreg,OS_32);
{$endif x86_64}
              list.concat(taicpu.op_reg_reg(op,s,reg,tmpreg));
              a_load_reg_ref(list,tosize,tosize,tmpreg,ref);
            end;
        else
          list.concat(taicpu.op_reg_ref(op,s,reg,ref));
        end;
      end;


    procedure tcgx86.a_load_ref_reg(list : taasmoutput;fromsize,tosize : tcgsize;const ref: treference;reg : tregister);
      var
        op: tasmop;
        s: topsize;
      begin
        check_register_size(tosize,reg);
        sizes2load(fromsize,tosize,op,s);
 {$ifdef x86_64}
        { zero extensions to 64 bit on the x86_64 are simply done by writting to the lower 32 bit
          which clears the upper 64 bit too, so it could be that s is S_L while the reg is
          64 bit (FK) }
        if s in [S_BL,S_WL,S_L] then
          reg:=makeregsize(list,reg,OS_32);
{$endif x86_64}
        list.concat(taicpu.op_ref_reg(op,s,ref,reg));
      end;


    procedure tcgx86.a_load_reg_reg(list : taasmoutput;fromsize,tosize : tcgsize;reg1,reg2 : tregister);
      var
        op: tasmop;
        s: topsize;
        instr:Taicpu;
      begin
        check_register_size(fromsize,reg1);
        check_register_size(tosize,reg2);
        if tcgsize2size[fromsize]>tcgsize2size[tosize] then
          begin
            reg1:=makeregsize(list,reg1,tosize);
            s:=tcgsize2opsize[tosize];
            op:=A_MOV;
          end
        else
          sizes2load(fromsize,tosize,op,s);
{$ifdef x86_64}
        { zero extensions to 64 bit on the x86_64 are simply done by writting to the lower 32 bit
          which clears the upper 64 bit too, so it could be that s is S_L while the reg is
          64 bit (FK) }
        if s in [S_BL,S_WL,S_L] then
          reg2:=makeregsize(list,reg2,OS_32);
{$endif x86_64}
        if (reg1<>reg2) then
          begin
            instr:=taicpu.op_reg_reg(op,s,reg1,reg2);
            { Notify the register allocator that we have written a move instruction so
              it can try to eliminate it. }
            add_move_instruction(instr);
            list.concat(instr);
          end;
      end;


    procedure tcgx86.a_loadaddr_ref_reg(list : taasmoutput;const ref : treference;r : tregister);
      begin
        with ref do
          if (base=NR_NO) and (index=NR_NO) then
            begin
              if assigned(ref.symbol) then
                list.concat(Taicpu.op_sym_ofs_reg(A_MOV,tcgsize2opsize[OS_ADDR],symbol,offset,r))
              else
                a_load_const_reg(list,OS_ADDR,offset,r);
            end
          else if (base=NR_NO) and (index<>NR_NO) and
                  (offset=0) and (scalefactor=0) and (symbol=nil) then
            a_load_reg_reg(list,OS_ADDR,OS_ADDR,index,r)
          else if (base<>NR_NO) and (index=NR_NO) and
                  (offset=0) and (symbol=nil) then
            a_load_reg_reg(list,OS_ADDR,OS_ADDR,base,r)
          else
            list.concat(taicpu.op_ref_reg(A_LEA,tcgsize2opsize[OS_ADDR],ref,r));
      end;


    { all fpu load routines expect that R_ST[0-7] means an fpu regvar and }
    { R_ST means "the current value at the top of the fpu stack" (JM)     }
    procedure tcgx86.a_loadfpu_reg_reg(list: taasmoutput; size: tcgsize; reg1, reg2: tregister);

       begin
         if (reg1<>NR_ST) then
           begin
             list.concat(taicpu.op_reg(A_FLD,S_NO,rgfpu.correct_fpuregister(reg1,rgfpu.fpuvaroffset)));
             inc_fpu_stack;
           end;
         if (reg2<>NR_ST) then
           begin
             list.concat(taicpu.op_reg(A_FSTP,S_NO,rgfpu.correct_fpuregister(reg2,rgfpu.fpuvaroffset)));
             dec_fpu_stack;
           end;
       end;


    procedure tcgx86.a_loadfpu_ref_reg(list: taasmoutput; size: tcgsize; const ref: treference; reg: tregister);
       begin
         floatload(list,size,ref);
         if (reg<>NR_ST) then
           a_loadfpu_reg_reg(list,size,NR_ST,reg);
       end;


    procedure tcgx86.a_loadfpu_reg_ref(list: taasmoutput; size: tcgsize; reg: tregister; const ref: treference);
       begin
         if reg<>NR_ST then
           a_loadfpu_reg_reg(list,size,reg,NR_ST);
         floatstore(list,size,ref);
       end;


    function get_scalar_mm_op(fromsize,tosize : tcgsize) : tasmop;
      const
        convertop : array[OS_F32..OS_F128,OS_F32..OS_F128] of tasmop = (
          (A_MOVSS,A_CVTSS2SD,A_NONE,A_NONE,A_NONE),
          (A_CVTSD2SS,A_MOVSD,A_NONE,A_NONE,A_NONE),
          (A_NONE,A_NONE,A_NONE,A_NONE,A_NONE),
          (A_NONE,A_NONE,A_NONE,A_MOVQ,A_NONE),
          (A_NONE,A_NONE,A_NONE,A_NONE,A_NONE));
      begin
        result:=convertop[fromsize,tosize];
        if result=A_NONE then
          internalerror(200312205);
      end;


    procedure tcgx86.a_loadmm_reg_reg(list: taasmoutput; fromsize, tosize : tcgsize;reg1, reg2: tregister;shuffle : pmmshuffle);
       begin
         if shuffle=nil then
           begin
             if fromsize=tosize then
               list.concat(taicpu.op_reg_reg(A_MOVAPS,S_NO,reg1,reg2))
             else
               internalerror(200312202);
           end
         else if shufflescalar(shuffle) then
           list.concat(taicpu.op_reg_reg(get_scalar_mm_op(fromsize,tosize),S_NO,reg1,reg2))
         else
           internalerror(200312201);
       end;


    procedure tcgx86.a_loadmm_ref_reg(list: taasmoutput; fromsize, tosize : tcgsize;const ref: treference; reg: tregister;shuffle : pmmshuffle);
       begin
         if shuffle=nil then
           begin
             list.concat(taicpu.op_ref_reg(A_MOVQ,S_NO,ref,reg));
           end
         else if shufflescalar(shuffle) then
           list.concat(taicpu.op_ref_reg(get_scalar_mm_op(fromsize,tosize),S_NO,ref,reg))
         else
           internalerror(200312252);
       end;


    procedure tcgx86.a_loadmm_reg_ref(list: taasmoutput; fromsize, tosize : tcgsize;reg: tregister; const ref: treference;shuffle : pmmshuffle);
       begin
         if shuffle=nil then
           begin
             list.concat(taicpu.op_reg_ref(A_MOVQ,S_NO,reg,ref));
           end
         else if shufflescalar(shuffle) then
           list.concat(taicpu.op_reg_ref(get_scalar_mm_op(fromsize,tosize),S_NO,reg,ref))
         else
           internalerror(200312252);
       end;


    procedure tcgx86.a_opmm_ref_reg(list: taasmoutput; Op: TOpCG; size : tcgsize;const ref: treference; reg: tregister;shuffle : pmmshuffle);
      var
        l : tlocation;
      begin
        l.loc:=LOC_REFERENCE;
        l.reference:=ref;
        l.size:=size;
        opmm_loc_reg(list,op,size,l,reg,shuffle);
      end;


    procedure tcgx86.a_opmm_reg_reg(list: taasmoutput; Op: TOpCG; size : tcgsize;src,dst: tregister;shuffle : pmmshuffle);
     var
       l : tlocation;
     begin
       l.loc:=LOC_MMREGISTER;
       l.register:=src;
       l.size:=size;
       opmm_loc_reg(list,op,size,l,dst,shuffle);
     end;


    procedure tcgx86.opmm_loc_reg(list: taasmoutput; Op: TOpCG; size : tcgsize;loc : tlocation;dst: tregister; shuffle : pmmshuffle);
      const
        opmm2asmop : array[0..1,OS_F32..OS_F64,topcg] of tasmop = (
          ( { scalar }
            ( { OS_F32 }
              A_NOP,A_ADDSS,A_NOP,A_DIVSS,A_NOP,A_NOP,A_MULSS,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_SUBSS,A_NOP
            ),
            ( { OS_F64 }
              A_NOP,A_ADDSD,A_NOP,A_DIVSD,A_NOP,A_NOP,A_MULSD,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_SUBSD,A_NOP
            )
          ),
          ( { vectorized/packed }
            { because the logical packed single instructions have shorter op codes, we use always
              these
            }
            ( { OS_F32 }
              A_NOP,A_ADDPS,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_XORPS
            ),
            ( { OS_F64 }
              A_NOP,A_ADDPD,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_NOP,A_XORPS
            )
          )
        );

      var
        resultreg : tregister;
        asmop : tasmop;
      begin
        { this is an internally used procedure so the parameters have
          some constrains
        }
        if loc.size<>size then
          internalerror(200312213);
        resultreg:=dst;
        { deshuffle }
        //!!!
        if (shuffle<>nil) and not(shufflescalar(shuffle)) then
          begin
          end
        else if (shuffle=nil) then
          asmop:=opmm2asmop[1,size,op]
        else if shufflescalar(shuffle) then
          begin
            asmop:=opmm2asmop[0,size,op];
            { no scalar operation available? }
            if asmop=A_NOP then
              begin
                { do vectorized and shuffle finally }
                //!!!
              end;
          end
        else
          internalerror(200312211);
        if asmop=A_NOP then
          internalerror(200312215);
        case loc.loc of
          LOC_CREFERENCE,LOC_REFERENCE:
            list.concat(taicpu.op_ref_reg(asmop,S_NO,loc.reference,resultreg));
          LOC_CMMREGISTER,LOC_MMREGISTER:
            list.concat(taicpu.op_reg_reg(asmop,S_NO,loc.register,resultreg));
          else
            internalerror(200312214);
        end;
        { shuffle }
        if resultreg<>dst then
          begin
            internalerror(200312212);
          end;
      end;


    procedure tcgx86.a_op_const_reg(list : taasmoutput; Op: TOpCG; size: TCGSize; a: aint; reg: TRegister);

      var
        opcode : tasmop;
        power  : longint;
{$ifdef x86_64}
        tmpreg : tregister;
{$endif x86_64}
      begin
{$ifdef x86_64}
        { x86_64 only supports signed 32 bits constants directly }
        if (size in [OS_S64,OS_64]) and
            ((a<low(longint)) or (a>high(longint))) then
          begin
            tmpreg:=getintregister(list,size);
            a_load_const_reg(list,size,a,tmpreg);
            a_op_reg_reg(list,op,size,tmpreg,reg);
            exit;
          end;
{$endif x86_64}
        check_register_size(size,reg);
        case op of
          OP_DIV, OP_IDIV:
            begin
              if ispowerof2(int64(a),power) then
                begin
                  case op of
                    OP_DIV:
                      opcode := A_SHR;
                    OP_IDIV:
                      opcode := A_SAR;
                  end;
                  list.concat(taicpu.op_const_reg(opcode,TCgSize2OpSize[size],power,reg));
                  exit;
                end;
              { the rest should be handled specifically in the code      }
              { generator because of the silly register usage restraints }
              internalerror(200109224);
            end;
          OP_MUL,OP_IMUL:
            begin
              if not(cs_check_overflow in aktlocalswitches) and
                 ispowerof2(int64(a),power) then
                begin
                  list.concat(taicpu.op_const_reg(A_SHL,TCgSize2OpSize[size],power,reg));
                  exit;
                end;
              if op = OP_IMUL then
                list.concat(taicpu.op_const_reg(A_IMUL,TCgSize2OpSize[size],a,reg))
              else
                { OP_MUL should be handled specifically in the code        }
                { generator because of the silly register usage restraints }
                internalerror(200109225);
            end;
          OP_ADD, OP_AND, OP_OR, OP_SUB, OP_XOR:
            if not(cs_check_overflow in aktlocalswitches) and
               (a = 1) and
               (op in [OP_ADD,OP_SUB]) then
              if op = OP_ADD then
                list.concat(taicpu.op_reg(A_INC,TCgSize2OpSize[size],reg))
              else
                list.concat(taicpu.op_reg(A_DEC,TCgSize2OpSize[size],reg))
            else if (a = 0) then
              if (op <> OP_AND) then
                exit
              else
                list.concat(taicpu.op_const_reg(A_MOV,TCgSize2OpSize[size],0,reg))
            else if (aword(a) = high(aword)) and
                    (op in [OP_AND,OP_OR,OP_XOR]) then
                   begin
                     case op of
                       OP_AND:
                         exit;
                       OP_OR:
                         list.concat(taicpu.op_const_reg(A_MOV,TCgSize2OpSize[size],aint(high(aword)),reg));
                       OP_XOR:
                         list.concat(taicpu.op_reg(A_NOT,TCgSize2OpSize[size],reg));
                     end
                   end
            else
              list.concat(taicpu.op_const_reg(TOpCG2AsmOp[op],TCgSize2OpSize[size],a,reg));
          OP_SHL,OP_SHR,OP_SAR:
            begin
              if (a and 31) <> 0 Then
                list.concat(taicpu.op_const_reg(TOpCG2AsmOp[op],TCgSize2OpSize[size],a and 31,reg));
              if (a shr 5) <> 0 Then
                internalerror(68991);
            end
          else internalerror(68992);
        end;
      end;


    procedure tcgx86.a_op_const_ref(list : taasmoutput; Op: TOpCG; size: TCGSize; a: aint; const ref: TReference);
      var
        opcode: tasmop;
        power: longint;
{$ifdef x86_64}
        tmpreg : tregister;
{$endif x86_64}
      begin
{$ifdef x86_64}
        { x86_64 only supports signed 32 bits constants directly }
        if (size in [OS_S64,OS_64]) and
            ((a<low(longint)) or (a>high(longint))) then
          begin
            tmpreg:=getintregister(list,size);
            a_load_const_reg(list,size,a,tmpreg);
            a_op_reg_ref(list,op,size,tmpreg,ref);
            exit;
          end;
{$endif x86_64}
        Case Op of
          OP_DIV, OP_IDIV:
            Begin
              if ispowerof2(int64(a),power) then
                begin
                  case op of
                    OP_DIV:
                      opcode := A_SHR;
                    OP_IDIV:
                      opcode := A_SAR;
                  end;
                  list.concat(taicpu.op_const_ref(opcode,
                    TCgSize2OpSize[size],power,ref));
                  exit;
                end;
              { the rest should be handled specifically in the code      }
              { generator because of the silly register usage restraints }
              internalerror(200109231);
            End;
          OP_MUL,OP_IMUL:
            begin
              if not(cs_check_overflow in aktlocalswitches) and
                 ispowerof2(int64(a),power) then
                begin
                  list.concat(taicpu.op_const_ref(A_SHL,TCgSize2OpSize[size],
                    power,ref));
                  exit;
                end;
              { can't multiply a memory location directly with a constant }
              if op = OP_IMUL then
                inherited a_op_const_ref(list,op,size,a,ref)
              else
                { OP_MUL should be handled specifically in the code        }
                { generator because of the silly register usage restraints }
                internalerror(200109232);
            end;
          OP_ADD, OP_AND, OP_OR, OP_SUB, OP_XOR:
            if not(cs_check_overflow in aktlocalswitches) and
               (a = 1) and
               (op in [OP_ADD,OP_SUB]) then
              if op = OP_ADD then
                list.concat(taicpu.op_ref(A_INC,TCgSize2OpSize[size],ref))
              else
                list.concat(taicpu.op_ref(A_DEC,TCgSize2OpSize[size],ref))
            else if (a = 0) then
              if (op <> OP_AND) then
                exit
              else
                a_load_const_ref(list,size,0,ref)
            else if (aword(a) = high(aword)) and
                    (op in [OP_AND,OP_OR,OP_XOR]) then
                   begin
                     case op of
                       OP_AND:
                         exit;
                       OP_OR:
                         list.concat(taicpu.op_const_ref(A_MOV,TCgSize2OpSize[size],aint(high(aword)),ref));
                       OP_XOR:
                         list.concat(taicpu.op_ref(A_NOT,TCgSize2OpSize[size],ref));
                     end
                   end
            else
              list.concat(taicpu.op_const_ref(TOpCG2AsmOp[op],
                TCgSize2OpSize[size],a,ref));
          OP_SHL,OP_SHR,OP_SAR:
            begin
              if (a and 31) <> 0 then
                list.concat(taicpu.op_const_ref(
                  TOpCG2AsmOp[op],TCgSize2OpSize[size],a and 31,ref));
              if (a shr 5) <> 0 Then
                internalerror(68991);
            end
          else internalerror(68992);
        end;
      end;


    procedure tcgx86.a_op_reg_reg(list : taasmoutput; Op: TOpCG; size: TCGSize; src, dst: TRegister);
      var
        dstsize: topsize;
        instr:Taicpu;
      begin
        check_register_size(size,src);
        check_register_size(size,dst);
        dstsize := tcgsize2opsize[size];
        case op of
          OP_NEG,OP_NOT:
            begin
              if src<>dst then
                a_load_reg_reg(list,size,size,src,dst);
              list.concat(taicpu.op_reg(TOpCG2AsmOp[op],dstsize,dst));
            end;
          OP_MUL,OP_DIV,OP_IDIV:
            { special stuff, needs separate handling inside code }
            { generator                                          }
            internalerror(200109233);
          OP_SHR,OP_SHL,OP_SAR:
            begin
              getcpuregister(list,NR_CL);
              a_load_reg_reg(list,OS_8,OS_8,makeregsize(list,src,OS_8),NR_CL);
              list.concat(taicpu.op_reg_reg(Topcg2asmop[op],tcgsize2opsize[size],NR_CL,src));
              ungetcpuregister(list,NR_CL);
            end;
          else
            begin
              if reg2opsize(src) <> dstsize then
                internalerror(200109226);
              instr:=taicpu.op_reg_reg(TOpCG2AsmOp[op],dstsize,src,dst);
              list.concat(instr);
            end;
        end;
      end;


    procedure tcgx86.a_op_ref_reg(list : taasmoutput; Op: TOpCG; size: TCGSize; const ref: TReference; reg: TRegister);
      begin
        check_register_size(size,reg);
        case op of
          OP_NEG,OP_NOT,OP_IMUL:
            begin
              inherited a_op_ref_reg(list,op,size,ref,reg);
            end;
          OP_MUL,OP_DIV,OP_IDIV:
            { special stuff, needs separate handling inside code }
            { generator                                          }
            internalerror(200109239);
          else
            begin
              reg := makeregsize(list,reg,size);
              list.concat(taicpu.op_ref_reg(TOpCG2AsmOp[op],tcgsize2opsize[size],ref,reg));
            end;
        end;
      end;


    procedure tcgx86.a_op_reg_ref(list : taasmoutput; Op: TOpCG; size: TCGSize;reg: TRegister; const ref: TReference);
      begin
        check_register_size(size,reg);
        case op of
          OP_NEG,OP_NOT:
            begin
              if reg<>NR_NO then
                internalerror(200109237);
              list.concat(taicpu.op_ref(TOpCG2AsmOp[op],tcgsize2opsize[size],ref));
            end;
          OP_IMUL:
            begin
              { this one needs a load/imul/store, which is the default }
              inherited a_op_ref_reg(list,op,size,ref,reg);
            end;
          OP_MUL,OP_DIV,OP_IDIV:
            { special stuff, needs separate handling inside code }
            { generator                                          }
            internalerror(200109238);
          else
            begin
              list.concat(taicpu.op_reg_ref(TOpCG2AsmOp[op],tcgsize2opsize[size],reg,ref));
            end;
        end;
      end;


    procedure tcgx86.a_op_const_reg_reg(list: taasmoutput; op: TOpCg; size: tcgsize; a: aint; src, dst: tregister);
      var
        tmpref: treference;
        power: longint;
{$ifdef x86_64}
        tmpreg : tregister;
{$endif x86_64}
      begin
{$ifdef x86_64}
        { x86_64 only supports signed 32 bits constants directly }
        if (size in [OS_S64,OS_64]) and
            ((a<low(longint)) or (a>high(longint))) then
          begin
            tmpreg:=getintregister(list,size);
            a_load_const_reg(list,size,a,tmpreg);
            a_op_reg_reg_reg(list,op,size,tmpreg,src,dst);
            exit;
          end;
{$endif x86_64}
        check_register_size(size,src);
        check_register_size(size,dst);
        if tcgsize2size[size]<>tcgsize2size[OS_INT] then
          begin
            inherited a_op_const_reg_reg(list,op,size,a,src,dst);
            exit;
          end;
        { if we get here, we have to do a 32 bit calculation, guaranteed }
        case op of
          OP_DIV, OP_IDIV, OP_MUL, OP_AND, OP_OR, OP_XOR, OP_SHL, OP_SHR,
          OP_SAR:
            { can't do anything special for these }
            inherited a_op_const_reg_reg(list,op,size,a,src,dst);
          OP_IMUL:
            begin
              if not(cs_check_overflow in aktlocalswitches) and
                 ispowerof2(int64(a),power) then
                { can be done with a shift }
                begin
                  inherited a_op_const_reg_reg(list,op,size,a,src,dst);
                  exit;
                end;
              list.concat(taicpu.op_const_reg_reg(A_IMUL,tcgsize2opsize[size],a,src,dst));
            end;
          OP_ADD, OP_SUB:
            if (a = 0) then
              a_load_reg_reg(list,size,size,src,dst)
            else
              begin
                reference_reset(tmpref);
                tmpref.base := src;
                tmpref.offset := longint(a);
                if op = OP_SUB then
                  tmpref.offset := -tmpref.offset;
                list.concat(taicpu.op_ref_reg(A_LEA,tcgsize2opsize[size],tmpref,dst));
              end
          else internalerror(200112302);
        end;
      end;


    procedure tcgx86.a_op_reg_reg_reg(list: taasmoutput; op: TOpCg;size: tcgsize; src1, src2, dst: tregister);
      var
        tmpref: treference;
      begin
        check_register_size(size,src1);
        check_register_size(size,src2);
        check_register_size(size,dst);
        if tcgsize2size[size]<>tcgsize2size[OS_INT] then
          begin
            inherited a_op_reg_reg_reg(list,op,size,src1,src2,dst);
            exit;
          end;
        { if we get here, we have to do a 32 bit calculation, guaranteed }
        Case Op of
          OP_DIV, OP_IDIV, OP_MUL, OP_AND, OP_OR, OP_XOR, OP_SHL, OP_SHR,
          OP_SAR,OP_SUB,OP_NOT,OP_NEG:
            { can't do anything special for these }
            inherited a_op_reg_reg_reg(list,op,size,src1,src2,dst);
          OP_IMUL:
            list.concat(taicpu.op_reg_reg_reg(A_IMUL,tcgsize2opsize[size],src1,src2,dst));
          OP_ADD:
            begin
              reference_reset(tmpref);
              tmpref.base := src1;
              tmpref.index := src2;
              tmpref.scalefactor := 1;
              list.concat(taicpu.op_ref_reg(A_LEA,tcgsize2opsize[size],tmpref,dst));
            end
          else internalerror(200112303);
        end;
      end;

{*************** compare instructructions ****************}

    procedure tcgx86.a_cmp_const_reg_label(list : taasmoutput;size : tcgsize;cmp_op : topcmp;a : aint;reg : tregister;
      l : tasmlabel);

{$ifdef x86_64}
      var
        tmpreg : tregister;
{$endif x86_64}
      begin
{$ifdef x86_64}
        { x86_64 only supports signed 32 bits constants directly }
        if (size in [OS_S64,OS_64]) and
            ((a<low(longint)) or (a>high(longint))) then
          begin
            tmpreg:=getintregister(list,size);
            a_load_const_reg(list,size,a,tmpreg);
            a_cmp_reg_reg_label(list,size,cmp_op,tmpreg,reg,l);
            exit;
          end;
{$endif x86_64}
        if (a = 0) then
          list.concat(taicpu.op_reg_reg(A_TEST,tcgsize2opsize[size],reg,reg))
        else
          list.concat(taicpu.op_const_reg(A_CMP,tcgsize2opsize[size],a,reg));
        a_jmp_cond(list,cmp_op,l);
      end;


    procedure tcgx86.a_cmp_const_ref_label(list : taasmoutput;size : tcgsize;cmp_op : topcmp;a : aint;const ref : treference;
      l : tasmlabel);

{$ifdef x86_64}
      var
        tmpreg : tregister;
{$endif x86_64}
      begin
{$ifdef x86_64}
        { x86_64 only supports signed 32 bits constants directly }
        if (size in [OS_S64,OS_64]) and
            ((a<low(longint)) or (a>high(longint))) then
          begin
            tmpreg:=getintregister(list,size);
            a_load_const_reg(list,size,a,tmpreg);
            a_cmp_reg_ref_label(list,size,cmp_op,tmpreg,ref,l);
            exit;
          end;
{$endif x86_64}
        list.concat(taicpu.op_const_ref(A_CMP,TCgSize2OpSize[size],a,ref));
        a_jmp_cond(list,cmp_op,l);
      end;


    procedure tcgx86.a_cmp_reg_reg_label(list : taasmoutput;size : tcgsize;cmp_op : topcmp;
      reg1,reg2 : tregister;l : tasmlabel);

      begin
        check_register_size(size,reg1);
        check_register_size(size,reg2);
        list.concat(taicpu.op_reg_reg(A_CMP,TCgSize2OpSize[size],reg1,reg2));
        a_jmp_cond(list,cmp_op,l);
      end;


    procedure tcgx86.a_cmp_ref_reg_label(list : taasmoutput;size : tcgsize;cmp_op : topcmp;const ref: treference; reg : tregister;l : tasmlabel);
      begin
        check_register_size(size,reg);
        list.concat(taicpu.op_ref_reg(A_CMP,TCgSize2OpSize[size],ref,reg));
        a_jmp_cond(list,cmp_op,l);
      end;


    procedure tcgx86.a_cmp_reg_ref_label(list : taasmoutput;size : tcgsize;cmp_op : topcmp;reg : tregister;const ref: treference; l : tasmlabel);
      begin
        check_register_size(size,reg);
        list.concat(taicpu.op_reg_ref(A_CMP,TCgSize2OpSize[size],reg,ref));
        a_jmp_cond(list,cmp_op,l);
      end;


    procedure tcgx86.a_jmp_cond(list : taasmoutput;cond : TOpCmp;l: tasmlabel);
      var
        ai : taicpu;
      begin
        if cond=OC_None then
          ai := Taicpu.Op_sym(A_JMP,S_NO,l)
        else
          begin
            ai:=Taicpu.Op_sym(A_Jcc,S_NO,l);
            ai.SetCondition(TOpCmp2AsmCond[cond]);
          end;
        ai.is_jmp:=true;
        list.concat(ai);
      end;


     procedure tcgx86.a_jmp_flags(list : taasmoutput;const f : TResFlags;l: tasmlabel);
       var
         ai : taicpu;
       begin
         ai := Taicpu.op_sym(A_Jcc,S_NO,l);
         ai.SetCondition(flags_to_cond(f));
         ai.is_jmp := true;
         list.concat(ai);
       end;


    procedure tcgx86.g_flags2reg(list: taasmoutput; size: TCgSize; const f: tresflags; reg: TRegister);
      var
        ai : taicpu;
        hreg : tregister;
      begin
        hreg:=makeregsize(list,reg,OS_8);
        ai:=Taicpu.op_reg(A_SETcc,S_B,hreg);
        ai.setcondition(flags_to_cond(f));
        list.concat(ai);
        if (reg<>hreg) then
          a_load_reg_reg(list,OS_8,size,hreg,reg);
      end;


     procedure tcgx86.g_flags2ref(list: taasmoutput; size: TCgSize; const f: tresflags; const ref: TReference);
       var
         ai : taicpu;
       begin
          if not(size in [OS_8,OS_S8]) then
            a_load_const_ref(list,size,0,ref);
          ai:=Taicpu.op_ref(A_SETcc,S_B,ref);
          ai.setcondition(flags_to_cond(f));
          list.concat(ai);
       end;


{ ************* concatcopy ************ }

    procedure Tcgx86.g_concatcopy(list:Taasmoutput;const source,dest:Treference;len:aint;loadref:boolean);

    const
{$ifdef cpu64bit}
        REGCX=NR_RCX;
        REGSI=NR_RSI;
        REGDI=NR_RDI;
{$else cpu64bit}
        REGCX=NR_ECX;
        REGSI=NR_ESI;
        REGDI=NR_EDI;
{$endif cpu64bit}

    type  copymode=(copy_move,copy_mmx,copy_string);

    var srcref,dstref:Treference;
        r,r0,r1,r2,r3:Tregister;
        helpsize:aint;
        copysize:byte;
        cgsize:Tcgsize;
        cm:copymode;

    begin
      cm:=copy_move;
      helpsize:=12;
      if cs_littlesize in aktglobalswitches then
        helpsize:=8;
      if (cs_mmx in aktlocalswitches) and
         not(pi_uses_fpu in current_procinfo.flags) and
         ((len=8) or (len=16) or (len=24) or (len=32)) then
        cm:=copy_mmx;
      if (len>helpsize) then
        cm:=copy_string;
      if (cs_littlesize in aktglobalswitches) and
         not((len<=16) and (cm=copy_mmx)) then
        cm:=copy_string;
      if loadref then
        cm:=copy_string;
      case cm of
        copy_move:
          begin
            dstref:=dest;
            srcref:=source;
            copysize:=sizeof(aint);
            cgsize:=int_cgsize(copysize);
            while len<>0 do
              begin
                if len<2 then
                  begin
                    copysize:=1;
                    cgsize:=OS_8;
                  end
                else if len<4 then
                  begin
                    copysize:=2;
                    cgsize:=OS_16;
                  end
                else if len<8 then
                  begin
                    copysize:=4;
                    cgsize:=OS_32;
                  end;
                dec(len,copysize);
                r:=getintregister(list,cgsize);
                a_load_ref_reg(list,cgsize,cgsize,srcref,r);
                a_load_reg_ref(list,cgsize,cgsize,r,dstref);
                inc(srcref.offset,copysize);
                inc(dstref.offset,copysize);
              end;
          end;
        copy_mmx:
          begin
            dstref:=dest;
            srcref:=source;
            r0:=getmmxregister(list);
            a_loadmm_ref_reg(list,OS_M64,OS_M64,srcref,r0,nil);
            if len>=16 then
              begin
                inc(srcref.offset,8);
                r1:=getmmxregister(list);
                a_loadmm_ref_reg(list,OS_M64,OS_M64,srcref,r1,nil);
              end;
            if len>=24 then
              begin
                inc(srcref.offset,8);
                r2:=getmmxregister(list);
                a_loadmm_ref_reg(list,OS_M64,OS_M64,srcref,r2,nil);
              end;
            if len>=32 then
              begin
                inc(srcref.offset,8);
                r3:=getmmxregister(list);
                a_loadmm_ref_reg(list,OS_M64,OS_M64,srcref,r3,nil);
              end;
            a_loadmm_reg_ref(list,OS_M64,OS_M64,r0,dstref,nil);
            if len>=16 then
              begin
                inc(dstref.offset,8);
                a_loadmm_reg_ref(list,OS_M64,OS_M64,r1,dstref,nil);
              end;
            if len>=24 then
              begin
                inc(dstref.offset,8);
                a_loadmm_reg_ref(list,OS_M64,OS_M64,r2,dstref,nil);
              end;
            if len>=32 then
              begin
                inc(dstref.offset,8);
                a_loadmm_reg_ref(list,OS_M64,OS_M64,r3,dstref,nil);
              end;
          end
        else {copy_string, should be a good fallback in case of unhandled}
          begin
            getcpuregister(list,REGDI);
            a_loadaddr_ref_reg(list,dest,REGDI);
            getcpuregister(list,REGSI);
            if loadref then
              a_load_ref_reg(list,OS_ADDR,OS_ADDR,source,REGSI)
            else
              a_loadaddr_ref_reg(list,source,REGSI);

            getcpuregister(list,REGCX);

            list.concat(Taicpu.op_none(A_CLD,S_NO));
            if cs_littlesize in aktglobalswitches  then
              begin
                a_load_const_reg(list,OS_INT,len,REGCX);
                list.concat(Taicpu.op_none(A_REP,S_NO));
                list.concat(Taicpu.op_none(A_MOVSB,S_NO));
              end
            else
              begin
                helpsize:=len div sizeof(aint);
                len:=len mod sizeof(aint);
                if helpsize>1 then
                  begin
                    a_load_const_reg(list,OS_INT,helpsize,REGCX);
                    list.concat(Taicpu.op_none(A_REP,S_NO));
                  end;
                if helpsize>0 then
                  begin
{$ifdef cpu64bit}
                    if sizeof(aint)=8 then
                      list.concat(Taicpu.op_none(A_MOVSQ,S_NO))
                    else
{$endif cpu64bit}
                      list.concat(Taicpu.op_none(A_MOVSD,S_NO));
                  end;
                if len>=4 then
                  begin
                    dec(len,4);
                    list.concat(Taicpu.op_none(A_MOVSD,S_NO));
                  end;
                if len>=2 then
                  begin
                    dec(len,2);
                    list.concat(Taicpu.op_none(A_MOVSW,S_NO));
                  end;
                if len=1 then
                  list.concat(Taicpu.op_none(A_MOVSB,S_NO));
              end;
            ungetcpuregister(list,REGCX);
            ungetcpuregister(list,REGSI);
            ungetcpuregister(list,REGDI);
          end;
        end;
    end;


{****************************************************************************
                              Entry/Exit Code Helpers
****************************************************************************}

    procedure tcgx86.g_releasevaluepara_openarray(list : taasmoutput;const ref:treference);
      begin
        { Nothing to release }
      end;


    procedure tcgx86.g_profilecode(list : taasmoutput);

      var
        pl           : tasmlabel;
        mcountprefix : String[4];

      begin
        case target_info.system of
        {$ifndef NOTARGETWIN32}
           system_i386_win32,
        {$endif}
           system_i386_freebsd,
           system_i386_netbsd,
//         system_i386_openbsd,
           system_i386_wdosx :
             begin
                Case target_info.system Of
                 system_i386_freebsd : mcountprefix:='.';
                 system_i386_netbsd : mcountprefix:='__';
//               system_i386_openbsd : mcountprefix:='.';
                else
                 mcountPrefix:='';
                end;
                objectlibrary.getaddrlabel(pl);
                new_section(list,sec_data,lower(current_procinfo.procdef.mangledname),sizeof(aint));
                list.concat(Tai_label.Create(pl));
                list.concat(Tai_const.Create_32bit(0));
                new_section(list,sec_code,lower(current_procinfo.procdef.mangledname),0);
                list.concat(Taicpu.Op_reg(A_PUSH,S_L,NR_EDX));
                list.concat(Taicpu.Op_sym_ofs_reg(A_MOV,S_L,pl,0,NR_EDX));
                a_call_name(list,target_info.Cprefix+mcountprefix+'mcount');
                list.concat(Taicpu.Op_reg(A_POP,S_L,NR_EDX));
             end;

           system_i386_linux:
             a_call_name(list,target_info.Cprefix+'mcount');

           system_i386_go32v2,system_i386_watcom:
             begin
               a_call_name(list,'MCOUNT');
             end;
        end;
      end;


    procedure tcgx86.g_stackpointer_alloc(list : taasmoutput;localsize : longint);
{$ifdef i386}
{$ifndef NOTARGETWIN32}
      var
        href : treference;
        i : integer;
        again : tasmlabel;
{$endif NOTARGETWIN32}
{$endif i386}
      begin
        if localsize>0 then
         begin
{$ifdef i386}
{$ifndef NOTARGETWIN32}
           { windows guards only a few pages for stack growing, }
           { so we have to access every page first              }
           if (target_info.system=system_i386_win32) and
              (localsize>=winstackpagesize) then
             begin
               if localsize div winstackpagesize<=5 then
                 begin
                    list.concat(Taicpu.Op_const_reg(A_SUB,S_L,localsize-4,NR_ESP));
                    for i:=1 to localsize div winstackpagesize do
                      begin
                         reference_reset_base(href,NR_ESP,localsize-i*winstackpagesize);
                         list.concat(Taicpu.op_const_ref(A_MOV,S_L,0,href));
                      end;
                    list.concat(Taicpu.op_reg(A_PUSH,S_L,NR_EAX));
                 end
               else
                 begin
                    objectlibrary.getlabel(again);
                    getcpuregister(list,NR_EDI);
                    list.concat(Taicpu.op_const_reg(A_MOV,S_L,localsize div winstackpagesize,NR_EDI));
                    a_label(list,again);
                    list.concat(Taicpu.op_const_reg(A_SUB,S_L,winstackpagesize-4,NR_ESP));
                    list.concat(Taicpu.op_reg(A_PUSH,S_L,NR_EAX));
                    list.concat(Taicpu.op_reg(A_DEC,S_L,NR_EDI));
                    a_jmp_cond(list,OC_NE,again);
                    ungetcpuregister(list,NR_EDI);
                    list.concat(Taicpu.op_const_reg(A_SUB,S_L,localsize mod winstackpagesize,NR_ESP));
                 end
             end
           else
{$endif NOTARGETWIN32}
{$endif i386}
            list.concat(Taicpu.Op_const_reg(A_SUB,tcgsize2opsize[OS_ADDR],localsize,NR_STACK_POINTER_REG));
         end;
      end;


    procedure tcgx86.g_proc_entry(list : taasmoutput;localsize : longint;nostackframe:boolean);
      begin
{$ifdef i386}
        { interrupt support for i386 }
        if (po_interrupt in current_procinfo.procdef.procoptions) then
          begin
            { .... also the segment registers }
            list.concat(Taicpu.Op_reg(A_PUSH,S_W,NR_GS));
            list.concat(Taicpu.Op_reg(A_PUSH,S_W,NR_FS));
            list.concat(Taicpu.Op_reg(A_PUSH,S_W,NR_ES));
            list.concat(Taicpu.Op_reg(A_PUSH,S_W,NR_DS));
            { save the registers of an interrupt procedure }
            list.concat(Taicpu.Op_reg(A_PUSH,S_L,NR_EDI));
            list.concat(Taicpu.Op_reg(A_PUSH,S_L,NR_ESI));
            list.concat(Taicpu.Op_reg(A_PUSH,S_L,NR_EDX));
            list.concat(Taicpu.Op_reg(A_PUSH,S_L,NR_ECX));
            list.concat(Taicpu.Op_reg(A_PUSH,S_L,NR_EBX));
            list.concat(Taicpu.Op_reg(A_PUSH,S_L,NR_EAX));
          end;
{$endif i386}

        { save old framepointer }
        if not nostackframe then
          begin
            if (current_procinfo.framepointer=NR_STACK_POINTER_REG) then
              CGmessage(cg_d_stackframe_omited)
            else
              begin
                list.concat(tai_regalloc.alloc(NR_FRAME_POINTER_REG));
                include(rg[R_INTREGISTER].preserved_by_proc,RS_FRAME_POINTER_REG);
                list.concat(Taicpu.op_reg(A_PUSH,tcgsize2opsize[OS_ADDR],NR_FRAME_POINTER_REG));
                { Return address and FP are both on stack }
                dwarfcfi.cfa_def_cfa_offset(list,2*sizeof(aint));
                dwarfcfi.cfa_offset(list,NR_FRAME_POINTER_REG,-(2*sizeof(aint)));
                list.concat(Taicpu.op_reg_reg(A_MOV,tcgsize2opsize[OS_ADDR],NR_STACK_POINTER_REG,NR_FRAME_POINTER_REG));
                dwarfcfi.cfa_def_cfa_register(list,NR_FRAME_POINTER_REG);
              end;

            { allocate stackframe space }
            if localsize<>0 then
              begin
                cg.g_stackpointer_alloc(list,localsize);
              end;
          end;

        { allocate PIC register }
        if cs_create_pic in aktmoduleswitches then
          begin
            a_call_name(list,'FPC_GETEIPINEBX');
            list.concat(taicpu.op_sym_ofs_reg(A_ADD,tcgsize2opsize[OS_ADDR],objectlibrary.newasmsymbol('_GLOBAL_OFFSET_TABLE_',AB_EXTERNAL,AT_DATA),0,NR_PIC_OFFSET_REG));
            list.concat(tai_regalloc.alloc(NR_PIC_OFFSET_REG));
          end;
      end;


    procedure tcgx86.g_save_standard_registers(list:Taasmoutput);
      var
        href : treference;
        size : longint;
        r : integer;
      begin
        { Get temp }
        size:=0;
        for r:=low(saved_standard_registers) to high(saved_standard_registers) do
          if saved_standard_registers[r] in rg[R_INTREGISTER].used_in_proc then
            inc(size,sizeof(aint));
        if size>0 then
          begin
            tg.GetTemp(list,size,tt_noreuse,current_procinfo.save_regs_ref);
            { Copy registers to temp }
            href:=current_procinfo.save_regs_ref;

            for r:=low(saved_standard_registers) to high(saved_standard_registers) do
              begin
                if saved_standard_registers[r] in rg[R_INTREGISTER].used_in_proc then
                  begin
                    a_load_reg_ref(list,OS_ADDR,OS_ADDR,newreg(R_INTREGISTER,saved_standard_registers[r],R_SUBWHOLE),href);
                    inc(href.offset,sizeof(aint));
                  end;
                include(rg[R_INTREGISTER].preserved_by_proc,saved_standard_registers[r]);
              end;
          end;
      end;


    procedure tcgx86.g_restore_standard_registers(list:Taasmoutput);
      var
        href : treference;
        r : integer;
      begin
        { Copy registers from temp }
        href:=current_procinfo.save_regs_ref;
        for r:=low(saved_standard_registers) to high(saved_standard_registers) do
          if saved_standard_registers[r] in rg[R_INTREGISTER].used_in_proc then
            begin
              a_load_ref_reg(list,OS_ADDR,OS_ADDR,href,newreg(R_INTREGISTER,saved_standard_registers[r],R_SUBWHOLE));
              inc(href.offset,sizeof(aint));
            end;
        tg.UnGetTemp(list,current_procinfo.save_regs_ref);
      end;


    { produces if necessary overflowcode }
    procedure tcgx86.g_overflowcheck(list: taasmoutput; const l:tlocation;def:tdef);
      var
         hl : tasmlabel;
         ai : taicpu;
         cond : TAsmCond;
      begin
         if not(cs_check_overflow in aktlocalswitches) then
          exit;
         objectlibrary.getlabel(hl);
         if not ((def.deftype=pointerdef) or
                ((def.deftype=orddef) and
                 (torddef(def).typ in [u64bit,u16bit,u32bit,u8bit,uchar,
                                       bool8bit,bool16bit,bool32bit]))) then
           cond:=C_NO
         else
           cond:=C_NB;
         ai:=Taicpu.Op_Sym(A_Jcc,S_NO,hl);
         ai.SetCondition(cond);
         ai.is_jmp:=true;
         list.concat(ai);

         a_call_name(list,'FPC_OVERFLOW');
         a_label(list,hl);
      end;


end.
{
  $Log$
  Revision 1.127  2004-10-04 20:46:22  peter
    * spilling code rewritten for x86. It now used the generic
      spilling routines. Special x86 optimization still needs
      to be added.
    * Spilling fixed when both operands needed to be spilled
    * Cleanup of spilling routine, do_spill_readwritten removed

  Revision 1.126  2004/10/03 12:42:22  florian
    * made sqrt, sqr and abs internal for the sparc

  Revision 1.125  2004/09/25 14:23:55  peter
    * ungetregister is now only used for cpuregisters, renamed to
      ungetcpuregister
    * renamed (get|unget)explicitregister(s) to ..cpuregister
    * removed location-release/reference_release

  Revision 1.124  2004/06/20 08:55:32  florian
    * logs truncated

  Revision 1.123  2004/06/16 20:07:11  florian
    * dwarf branch merged

  Revision 1.122  2004/05/22 23:34:28  peter
  tai_regalloc.allocation changed to ratype to notify rgobj of register size changes

  Revision 1.121  2004/04/28 15:19:03  florian
    + syscall directive support for MorphOS added

  Revision 1.120  2004/04/09 14:36:05  peter
    * A_MOVSL renamed to A_MOVSD

  Revision 1.119.2.22  2004/05/28 20:29:50  florian
    * fixed currency trouble on x86-64

}
