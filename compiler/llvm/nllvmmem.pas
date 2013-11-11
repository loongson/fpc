{
    Copyright (c) 2012 by Jonas Maebe

    Generate LLVM byetcode for in memory related nodes

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
unit nllvmmem;

{$mode objfpc}

interface

    uses
      globtype,
      cgbase,cgutils,
      symtype,
      node,ncgnstmm, ncgmem;

    type
      tllvmloadparentfpnode = class(tcgnestloadparentfpnode)
      end;

      tllvmvecnode= class(tcgvecnode)
       private
        constarrayoffset: aint;
        arraytopointerconverted: boolean;
       public
        procedure pass_generate_code; override;
        procedure update_reference_reg_mul(maybe_const_reg: tregister; regsize: tdef; l: aint); override;
        procedure update_reference_reg_packed(maybe_const_reg: tregister; regsize: tdef; l: aint); override;
        procedure update_reference_offset(var ref: treference; index, mulsize: aint); override;
      end;


implementation

    uses
      verbose,cutils,
      aasmdata,aasmllvm,
      symconst,symdef,defutil,
      nmem,
      cpubase,llvmbase,hlcgobj;

  { tllvmvecnode }

  procedure tllvmvecnode.pass_generate_code;
    var
      locref: preference;
      hreg: tregister;
      arrptrelementdef: tdef;

    procedure getarrelementptrdef;
      begin
        if assigned(locref) then
          exit;
        case location.loc of
          LOC_SUBSETREF,LOC_CSUBSETREF:
            locref:=@location.reference;
          LOC_REFERENCE,LOC_CREFERENCE:
            locref:=@location.sref.ref;
          else
            internalerror(2013111001);
        end;
        { special handling for s80real: inside aggregates (such as arrays) it's
          declared as an array of 10 bytes in order to force the allocation of
          the right size (llvm only supports s80real according to the ABI size/
          alignment) -> convert the pointer to this array into a pointer to the
          s80real type (loads from and stores to this type will always only store
          10 bytes) }
        if (resultdef.typ=floatdef) and
           (tfloatdef(resultdef).floattype=s80real) then
          arrptrelementdef:=getpointerdef(getarraydef(u8inttype,10))
        else
          arrptrelementdef:=getpointerdef(resultdef);
      end;

    begin
      inherited;
      locref:=nil;
      if not arraytopointerconverted then
        begin
          { the result is currently a pointer left.resultdef (the array type)
             -> convert it into a pointer to an element inside this array }
          getarrelementptrdef;
          hreg:=hlcg.getaddressregister(current_asmdata.CurrAsmList,arrptrelementdef);
          current_asmdata.CurrAsmList.Concat(taillvm.getelementptr_reg_size_ref_size_const(hreg,getpointerdef(left.resultdef),
            locref^,ptruinttype,constarrayoffset));
          reference_reset_base(locref^,hreg,0,locref^.alignment);
        end;

      { see comment in getarrelementptrdef }
      if (resultdef.typ=floatdef) and
         (tfloatdef(resultdef).floattype=s80real) then
       begin
         getarrelementptrdef;
         hreg:=hlcg.getaddressregister(current_asmdata.CurrAsmList,getpointerdef(resultdef));
         hlcg.a_load_reg_reg(current_asmdata.CurrAsmList,arrptrelementdef,getpointerdef(resultdef),locref^.base,hreg);
         locref^.base:=hreg;
       end;
    end;


  procedure tllvmvecnode.update_reference_reg_mul(maybe_const_reg: tregister; regsize: tdef; l: aint);
    var
      hreg: tregister;
    begin
      if l<>resultdef.size then
        internalerror(2013102602);
      if constarrayoffset<>0 then
        begin
          hreg:=hlcg.getintregister(current_asmdata.CurrAsmList,ptruinttype);
          hlcg.a_op_const_reg_reg(current_asmdata.CurrAsmList,OP_ADD,ptruinttype,constarrayoffset,maybe_const_reg,hreg);
          maybe_const_reg:=hreg;
        end;
      hreg:=hlcg.getaddressregister(current_asmdata.CurrAsmList,getpointerdef(resultdef));
      { get address of indexed array element and convert pointer to array into
        pointer to the elementdef in the process }
      current_asmdata.CurrAsmList.Concat(taillvm.getelementptr_reg_size_ref_size_reg(hreg,getpointerdef(left.resultdef),
        location.reference,ptruinttype,maybe_const_reg));
      arraytopointerconverted:=true;
      reference_reset_base(location.reference,hreg,0,location.reference.alignment);
      location.reference.alignment:=newalignment(location.reference.alignment,l);
    end;


  procedure tllvmvecnode.update_reference_reg_packed(maybe_const_reg: tregister; regsize: tdef; l: aint);
    var
      sref: tsubsetreference;
      offsetreg, basereg, hreg, hreg2: tregister;
      alignpower: aint;
      temp, intloadsize : longint;
      defloadsize: tdef;
    begin
      { only orddefs are bitpacked. Even then we only need special code in }
      { case the bitpacked *byte size* is not a power of two, otherwise    }
      { everything can be handled using the the regular array code.        }
      if ((l mod 8) = 0) and
         (ispowerof2(l div 8,temp) or
          not is_ordinal(resultdef)
{$ifndef cpu64bitalu}
          or is_64bitint(resultdef)
{$endif not cpu64bitalu}
          ) then
        begin
          update_reference_reg_mul(maybe_const_reg,regsize,l div 8);
          exit;
        end;
      if (l>8*sizeof(aint)) then
        internalerror(200608051);

      { adjust the index by subtracting the lower bound of the array and adding
        any constant adjustments }
      sref.ref:=location.reference;
      hreg:=hlcg.getintregister(current_asmdata.CurrAsmList,ptruinttype);
      hlcg.a_op_const_reg_reg(current_asmdata.CurrAsmList,OP_SUB,ptruinttype,tarraydef(left.resultdef).lowrange-constarrayoffset,maybe_const_reg,hreg);

      { keep alignment for index }
      sref.ref.alignment:=left.resultdef.alignment;
      intloadsize:=packedbitsloadsize(l);
      if not ispowerof2(intloadsize,temp) then
        internalerror(2006081201);
      defloadsize:=cgsize_orddef(int_cgsize(intloadsize));
      alignpower:=temp;
      { determine start of the 8/16/32/64 bits chunk that contains the wanted
        value: divide the index by 8 (we're working with a bitpacked array here,
        all quantities are expressed in bits), and then by the size of the
        chunks (alignpower) }
      offsetreg:=hlcg.getintregister(current_asmdata.CurrAsmList,ptruinttype);
      hlcg.a_op_const_reg_reg(current_asmdata.CurrAsmList,OP_SHR,ptruinttype,3+alignpower,hreg,offsetreg);
      { index the array using this chunk index }
      basereg:=hlcg.getaddressregister(current_asmdata.CurrAsmList,getpointerdef(defloadsize));
      current_asmdata.CurrAsmList.Concat(taillvm.getelementptr_reg_size_ref_size_reg(basereg,getpointerdef(left.resultdef),
        sref.ref,ptruinttype,offsetreg));
      arraytopointerconverted:=true;
      reference_reset_base(sref.ref,basereg,0,sref.ref.alignment);
      { calculate the bit index inside that chunk }
      hreg2:=hlcg.getintregister(current_asmdata.CurrAsmList,ptruinttype);
      { multiple index with bitsize of every element }
      hlcg.a_op_const_reg_reg(current_asmdata.CurrAsmList,OP_MUL,ptruinttype,l,hreg,hreg2);
      hreg:=hlcg.getintregister(current_asmdata.CurrAsmList,ptruinttype);
      { mask out the chunk index part }
      hlcg.a_op_const_reg_reg(current_asmdata.CurrAsmList,OP_AND,ptruinttype,(1 shl (3+alignpower))-1,hreg2,hreg);
      sref.bitindexreg:=hreg;
      sref.startbit:=0;
      sref.bitlen:=resultdef.packedbitsize;
      if (left.location.loc=LOC_REFERENCE) then
        location.loc:=LOC_SUBSETREF
      else
        location.loc:=LOC_CSUBSETREF;
      location.sref:=sref;
    end;


  procedure tllvmvecnode.update_reference_offset(var ref: treference; index, mulsize: aint);
    begin
      inc(constarrayoffset,index);
    end;


begin
  cloadparentfpnode:=tllvmloadparentfpnode;
  cvecnode:=tllvmvecnode;
end.

