{
    $Id$
    Copyright (c) 1998-2002 by Florian Klaempfl

    This unit contains the ARM GAS instruction tables

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
unit itcpugas;

{$i fpcdefs.inc}

interface

  uses
    cpubase,cgbase;


  const
    { Standard opcode string table (for each tasmop enumeration). The
      opcode strings should conform to the names as defined by the
      processor manufacturer.
    }
    gas_op2str : op2strtable = (
            '','adc','add','and','n','bic','bkpt','b','bl','blx','bx',
            'cdp','cdp2','clz','cmn','cmp','eor','ldc','ldc2',
            'ldm','ldr','ldrb','ldrd','ldrbt','ldrh','ldrsb',
            'ldrsh','ldrt','mcr','mcr2','mcrr','mla','mov',
            'mrc','mrc2','mrrc','rs','msr','mul','mvn',
            'orr','pld','qadd','qdadd','qdsub','qsub','rsb','rsc',
            'sbc','smlal','smull','smul',
            'smulw','stc','stc2','stm','str','strb','strbt','strd',
            'strh','strt','sub','swi','swp','swpb','teq','tst',
            'umlal','umull',
            { FPA coprocessor codes }
            'ldf','stf','lfm','sfm','flt','fix','wfs','rfs','rfc',
            'adf','dvf','fdv','fml','frd','muf','pol','pw','rdf',
            'rmf','rpw','rsf','suf','abs','acs','asn','atn','cos',
            'exp','log','lgn','mvf','mnf','nrm','rnd','sin','sqt','tan','urd',
            'cmf','cnf'
            { VPA coprocessor codes }
            );


    function gas_regnum_search(const s:string):Tregister;
    function gas_regname(r:Tregister):string;


implementation

    uses
      cutils,verbose;

    const
      gas_regname_table : array[tregisterindex] of string[7] = (
        {$i rarmstd.inc}
      );

      gas_regname_index : array[tregisterindex] of tregisterindex = (
        {$i rarmsri.inc}
      );

    function findreg_by_gasname(const s:string):tregisterindex;
      var
        i,p : tregisterindex;
      begin
        {Binary search.}
        p:=0;
        i:=regnumber_count_bsstart;
        repeat
          if (p+i<=high(tregisterindex)) and (gas_regname_table[gas_regname_index[p+i]]<=s) then
            p:=p+i;
          i:=i shr 1;
        until i=0;
        if gas_regname_table[gas_regname_index[p]]=s then
          findreg_by_gasname:=gas_regname_index[p]
        else
          findreg_by_gasname:=0;
      end;


    function gas_regnum_search(const s:string):Tregister;
      begin
        result:=regnumber_table[findreg_by_gasname(s)];
      end;


    function gas_regname(r:Tregister):string;
      var
        p : tregisterindex;
      begin
        p:=findreg_by_number(r);
        if p<>0 then
          result:=gas_regname_table[p]
        else
          result:=generic_regname(r);
      end;

end.
{
  $Log$
  Revision 1.2  2003-11-17 23:23:47  florian
    + first part of arm assembler reader

  Revision 1.1  2003/11/12 16:05:39  florian
    * assembler readers OOPed
    + typed currency constants
    + typed 128 bit float constants if the CPU supports it

  Revision 1.2  2003/11/02 14:30:03  florian
    * fixed ARM for new reg. allocation scheme

  Revision 1.1  2003/09/04 00:15:29  florian
    * first bunch of adaptions of arm compiler for new register type
}
