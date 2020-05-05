{
    Copyright (c) 2020 by Nikolay Nikolov

    Contains the ASCII relocatable object file format (*.rel) reader and writer
    This is the object format used on the Z80 platforms.

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
unit ogrel;

{$i fpcdefs.inc}

interface

    uses
       { common }
       cclasses,globtype,
       { target }
       systems,
       { assembler }
       cpuinfo,cpubase,aasmbase,assemble,link,
       { output }
       ogbase,
       owbase;

    type

      { TRelRelocation }

      TRelRelocation = class(TObjRelocation)
      end;

      { TRelObjData }

      TRelObjData = class(TObjData)
      public
        function sectionname(atype:TAsmSectiontype;const aname:string;aorder:TAsmSectionOrder):string;override;
        procedure writeReloc(Data:TRelocDataInt;len:aword;p:TObjSymbol;Reloctype:TObjRelocationType);override;
      end;

      { TRelObjOutput }

      TRelObjOutput = class(tObjOutput)
      private
        procedure writeString(const S: ansistring);
        procedure writeLine(const S: ansistring);
        procedure WriteAreaContentAndRelocations(sec: TObjSection);
      protected
        function writeData(Data:TObjData):boolean;override;
      public
        constructor create(AWriter:TObjectWriter);override;
      end;

      { TRelAssembler }

      TRelAssembler = class(tinternalassembler)
        constructor create(info: pasminfo; smart:boolean);override;
      end;

implementation

    uses
       SysUtils,
       cutils,verbose,globals,
       fmodule,aasmtai,aasmdata,
       ogmap,
       version
       ;

    function tohex(q: qword): string;
      begin
        result:=HexStr(q,16);
        while (Length(result)>1) and (result[1]='0') do
          delete(result,1,1);
      end;

{*****************************************************************************
                                TRelObjData
*****************************************************************************}

    function TRelObjData.sectionname(atype: TAsmSectiontype; const aname: string; aorder: TAsmSectionOrder): string;
      const
        secnames : array[TAsmSectiontype] of string[length('__DATA, __datacoal_nt,coalesced')] = ('','',
          '_CODE',
          '_DATA',
          '_DATA',
          '.rodata',
          '.bss',
          '.threadvar',
          '.pdata',
          '', { stubs }
          '__DATA,__nl_symbol_ptr',
          '__DATA,__la_symbol_ptr',
          '__DATA,__mod_init_func',
          '__DATA,__mod_term_func',
          '.stab',
          '.stabstr',
          '.idata$2','.idata$4','.idata$5','.idata$6','.idata$7','.edata',
          '.eh_frame',
          '.debug_frame','.debug_info','.debug_line','.debug_abbrev','.debug_aranges','.debug_ranges',
          '.fpc',
          '.toc',
          '.init',
          '.fini',
          '.objc_class',
          '.objc_meta_class',
          '.objc_cat_cls_meth',
          '.objc_cat_inst_meth',
          '.objc_protocol',
          '.objc_string_object',
          '.objc_cls_meth',
          '.objc_inst_meth',
          '.objc_cls_refs',
          '.objc_message_refs',
          '.objc_symbols',
          '.objc_category',
          '.objc_class_vars',
          '.objc_instance_vars',
          '.objc_module_info',
          '.objc_class_names',
          '.objc_meth_var_types',
          '.objc_meth_var_names',
          '.objc_selector_strs',
          '.objc_protocol_ext',
          '.objc_class_ext',
          '.objc_property',
          '.objc_image_info',
          '.objc_cstring_object',
          '.objc_sel_fixup',
          '__DATA,__objc_data',
          '__DATA,__objc_const',
          '.objc_superrefs',
          '__DATA, __datacoal_nt,coalesced',
          '.objc_classlist',
          '.objc_nlclasslist',
          '.objc_catlist',
          '.obcj_nlcatlist',
          '.objc_protolist',
          '.stack',
          '.heap',
          '.gcc_except_table',
          '.ARM.attributes'
        );
      begin
        result:=secnames[atype];
      end;

    procedure TRelObjData.writeReloc(Data: TRelocDataInt; len: aword; p: TObjSymbol; Reloctype: TObjRelocationType);
      var
        bytes: array [0..1] of Byte;
        symaddr: QWord;
        objreloc: TRelRelocation;
      begin
        if CurrObjSec=nil then
          internalerror(200403072);
        objreloc:=nil;
        if assigned(p) then
          begin
            { real address of the symbol }
            symaddr:=p.address;

            if p.bind=AB_EXTERNAL then
              begin
                objreloc:=TRelRelocation.CreateSymbol(CurrObjSec.Size,p,Reloctype);
                CurrObjSec.ObjRelocations.Add(objreloc);
              end
            { relative relocations within the same section can be calculated directly,
              without the need to emit a relocation entry }
            else if (p.objsection=CurrObjSec) and
                    (p.bind<>AB_COMMON) and
                    (Reloctype=RELOC_RELATIVE) then
              begin
                data:=data+symaddr-len-CurrObjSec.Size;
              end
            else
              begin
                objreloc:=TRelRelocation.CreateSection(CurrObjSec.Size,p.objsection,Reloctype);
                CurrObjSec.ObjRelocations.Add(objreloc);
              end;
          end;
        case len of
          2:
            begin
              bytes[0]:=Byte(Data);
              bytes[1]:=Byte(Data shr 8);
              writebytes(bytes,2);
            end;
          1:
            begin
              bytes[0]:=Byte(Data);
              writebytes(bytes,1);
            end;
          else
            internalerror(2020050423);
        end;
      end;

{*****************************************************************************
                                TRelObjOutput
*****************************************************************************}

    procedure TRelObjOutput.writeString(const S: ansistring);
      begin
        FWriter.write(S[1],Length(S));
      end;

    procedure TRelObjOutput.writeLine(const S: ansistring);
      begin
        writeString(S+#10)
      end;

    procedure TRelObjOutput.WriteAreaContentAndRelocations(sec: TObjSection);
      const
        MaxChunkSize=14;
      var
        ChunkStart,ChunkLen, i: LongWord;
        ChunkFixupStart,ChunkFixupEnd: Integer;
        s: ansistring;
        buf: array [0..MaxChunkSize-1] of Byte;
      begin
        if oso_data in sec.SecOptions then
          begin
            if sec.Data=nil then
              internalerror(200403073);
            sec.data.seek(0);
            ChunkFixupStart:=0;
            ChunkFixupEnd:=-1;
            ChunkStart:=0;
            ChunkLen:=Min(MaxChunkSize, sec.Data.size-ChunkStart);
            while ChunkLen>0 do
            begin
              { find last fixup in the chunk }
              while (ChunkFixupEnd<(sec.ObjRelocations.Count-1)) and
                    (TRelRelocation(sec.ObjRelocations[ChunkFixupEnd+1]).DataOffset<(ChunkStart+ChunkLen)) do
                inc(ChunkFixupEnd);
              { check if last chunk is crossing the chunk boundary, and trim ChunkLen if necessary }
              if (ChunkFixupEnd>=ChunkFixupStart) and
                ((TRelRelocation(sec.ObjRelocations[ChunkFixupEnd]).DataOffset+
                  TRelRelocation(sec.ObjRelocations[ChunkFixupEnd]).size)>(ChunkStart+ChunkLen)) then
                begin
                  ChunkLen:=TRelRelocation(sec.ObjRelocations[ChunkFixupEnd]).DataOffset-ChunkStart;
                  Dec(ChunkFixupEnd);
                end;
              s:='T '+HexStr(Byte(ChunkStart),2)+' '+HexStr(Byte(ChunkStart shr 8),2);
              if ChunkLen>SizeOf(buf) then
                internalerror(2020050501);
              sec.Data.read(buf,ChunkLen);
              for i:=0 to ChunkLen-1 do
                s:=s+' '+HexStr(buf[i],2);
              writeLine(s);
              writeLine('R 00 00 '+HexStr(Byte(sec.SecSymIdx),2)+' '+HexStr(Byte(sec.SecSymIdx shr 8),2));
              { prepare next chunk }
              Inc(ChunkStart, ChunkLen);
              ChunkLen:=Min(MaxChunkSize, sec.Data.size-ChunkStart);
              ChunkFixupStart:=ChunkFixupEnd+1;
            end;
          end;
      end;

    function TRelObjOutput.writeData(Data: TObjData): boolean;
      var
        global_symbols_count: Integer = 0;
        secidx, idx, i, j: Integer;
        objsym: TObjSymbol;
        objsec: TObjSection;
      begin
        global_symbols_count:=0;
        for i:=0 to Data.ObjSymbolList.Count-1 do
          begin
            objsym:=TObjSymbol(Data.ObjSymbolList[i]);
            if objsym.bind in [AB_EXTERNAL,AB_GLOBAL] then
              Inc(global_symbols_count);
          end;

        writeLine('XL2');
        writeLine('H '+tohex(data.ObjSectionList.Count)+' areas '+tohex(global_symbols_count)+' global symbols');

        idx:=0;
        for i:=0 to Data.ObjSymbolList.Count-1 do
          begin
            objsym:=TObjSymbol(Data.ObjSymbolList[i]);
            if objsym.bind=AB_EXTERNAL then
              begin
                writeLine('S '+ApplyAsmSymbolRestrictions(objsym.Name)+' Ref0000');
                objsym.symidx:=idx;
                Inc(idx);
              end;
          end;
        secidx:=0;
        for i:=0 to Data.ObjSectionList.Count-1 do
          begin
            objsec:=TObjSection(Data.ObjSectionList[i]);
            writeLine('A '+objsec.Name+' size '+tohex(objsec.Size)+' flags 0 addr 0');
            objsec.SecSymIdx:=secidx;
            Inc(secidx);
            for j:=0 to Data.ObjSymbolList.Count-1 do
              begin
                objsym:=TObjSymbol(Data.ObjSymbolList[j]);
                if (objsym.bind=AB_GLOBAL) and (objsym.objsection=objsec) then
                  begin
                    writeLine('S '+ApplyAsmSymbolRestrictions(objsym.Name)+' Def'+HexStr(objsym.offset,4));
                    objsym.symidx:=idx;
                    Inc(idx);
                  end;
              end;
          end;
        for i:=0 to Data.ObjSectionList.Count-1 do
          begin
            objsec:=TObjSection(Data.ObjSectionList[i]);
            WriteAreaContentAndRelocations(objsec);
          end;
        result:=true;
      end;

    constructor TRelObjOutput.create(AWriter: TObjectWriter);
      begin
        inherited;
        cobjdata:=TRelObjData;
      end;

{*****************************************************************************
                                TRelAssembler
*****************************************************************************}

    constructor TRelAssembler.create(info: pasminfo; smart: boolean);
      begin
        inherited;
        CObjOutput:=TRelObjOutput;
      end;

{*****************************************************************************
                                  Initialize
*****************************************************************************}
    const
       as_z80_rel_info : tasminfo =
          (
            id     : as_z80_rel;
            idtxt  : 'REL';
            asmbin : '';
            asmcmd : '';
            supported_targets : [system_z80_embedded,system_z80_zxspectrum];
            flags : [af_outputbinary,af_smartlink_sections];
            labelprefix : '..@';
            labelmaxlen : 79;
            comment : '; ';
            dollarsign: '$';
          );

initialization
  RegisterAssembler(as_z80_rel_info,TRelAssembler);
end.
