{
    $Id$
    Copyright (c) 1997-99 by Carl Eric Codere and Peter Vreman

    Does the parsing for the AT&T styled inline assembler.

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
{$ifdef TP}
  {$N+,E+}
{$endif TP}
Unit Ra386att;
Interface

uses
  tree;

   function assemble: ptree;


Implementation

Uses
  globtype,
  strings,cobjects,systems,verbose,globals,
  files,aasm,types,symtable,scanner,hcodegen
  ,i386base
  ,rautils,ra386;

type
 tasmtoken = (
   AS_NONE,AS_LABEL,AS_LLABEL,AS_STRING,AS_INTNUM,
   AS_REALNUM,AS_COMMA,AS_LPAREN,
   AS_RPAREN,AS_COLON,AS_DOT,AS_PLUS,AS_MINUS,AS_STAR,
   AS_SEPARATOR,AS_ID,AS_REGISTER,AS_OPCODE,AS_SLASH,AS_DOLLAR,
   {------------------ Assembler directives --------------------}
   AS_DB,AS_DW,AS_DD,AS_DQ,AS_GLOBAL,AS_ALIGN,AS_ASCII,
   AS_ASCIIZ,AS_LCOMM,AS_COMM,AS_SINGLE,AS_DOUBLE,AS_EXTENDED,
   AS_DATA,AS_TEXT,AS_END,
   {------------------ Assembler Operators  --------------------}
   AS_MOD,AS_SHL,AS_SHR,AS_NOT,AS_AND,AS_OR,AS_XOR,AS_NOR);

   tasmkeyword = string[8];

const
   { These tokens should be modified accordingly to the modifications }
   { in the different enumerations.                                   }
   firstdirective = AS_DB;
   lastdirective  = AS_END;

   _count_asmprefixes   = 5;
   _count_asmspecialops = 25;
   _count_asmoverrides  = 3;

  token2str : array[tasmtoken] of string[10]=(
    '','Label','LLabel','string','integer',
    'float',',','(',
    ')',':','.','+','-','*',
    ';','identifier','register','opcode','/','$',
    '.byte','.word','.long','.quad','.globl','.align','.ascii',
    '.asciz','.lcomm','.comm','.single','.double','.tfloat',
    '.data','.text','END',
    '%','<<','>>','!','&','|','^','~');

const
  newline = #10;
  firsttoken : boolean = TRUE;
  charcount  : byte = 0;
var
  _asmsorted,
  inexpression   : boolean;
  curlist        : paasmoutput;
  c              : char;
  actasmtoken    : tasmtoken;
  prevasmtoken   : tasmtoken;
  actasmpattern  : string;
  actopcode      : tasmop;
  actasmregister : tregister;
  actopsize      : topsize;
  actcondition   : tasmcond;
  iasmops        : ^op2strtable;
  iasmregs       : ^reg2strtable;


Procedure SetupTables;
{ creates uppercased symbol tables for speed access }
var
  i : tasmop;
  j : tregister;
Begin
  { opcodes }
  new(iasmops);
  for i:=firstop to lastop do
   iasmops^[i] := upper(att_op2str[i]);
  { registers }
  new(iasmregs);
  for j:=firstreg to lastreg do
   iasmregs^[j] := upper(att_reg2str[j]);
end;


  {---------------------------------------------------------------------}
  {                    Routines for the tokenizing                     }
  {---------------------------------------------------------------------}

function is_asmopcode(const s: string):boolean;
const
  att_sizesuffixstr : array[0..8] of string[2] = (
    '','B','W','L','BW','BL','WL','Q','T'
  );
  att_sizesuffix : array[0..8] of topsize = (
    S_NO,S_B,S_W,S_L,S_BW,S_BL,S_WL,S_IQ,S_FX
  );
var
  i    : tasmop;
  cond : string[4];
  cnd  : tasmcond;
  len,
  j,
  sufidx : longint;
  hid  : string;
Begin
  is_asmopcode:=FALSE;

  actopcode:=A_None;
  actcondition:=C_None;
  actopsize:=S_NO;

  { search for all possible suffixes }
  for sufidx:=low(att_sizesuffixstr) to high(att_sizesuffixstr) do
   begin
     len:=length(s)-length(att_sizesuffixstr[sufidx]);
     if copy(s,len+1,length(att_sizesuffixstr[sufidx]))=att_sizesuffixstr[sufidx] then
      begin
        { here we search the entire table... }
        hid:=copy(s,1,len);
        for i:=firstop to lastop do
         if (length(hid) > 0) and (hid=iasmops^[i]) then
          begin
            actopsize:=att_sizesuffix[sufidx];
            actopcode:=i;
            actasmtoken:=AS_OPCODE;
            is_asmopcode:=TRUE;
            exit;
          end;
        { not found, check condition opcodes }
        j:=0;
        while (j<CondAsmOps) do
         begin
           if Copy(s,1,Length(CondAsmOpStr[j]))=CondAsmOpStr[j] then
            begin
              cond:=Copy(s,Length(CondAsmOpStr[j])+1,len-Length(CondAsmOpStr[j]));
              if cond<>'' then
               begin
                 for cnd:=low(TasmCond) to high(TasmCond) do
                  if Cond=Upper(cond2str[cnd]) then
                   begin
                     actopcode:=CondASmOp[j];
                     actopsize:=att_sizesuffix[sufidx];
                     actcondition:=cnd;
                     actasmtoken:=AS_OPCODE;
                     is_asmopcode:=TRUE;
                     exit;
                   end;
               end;
            end;
           inc(j);
         end;
     end;
   end;
end;


Function is_asmdirective(const s: string):boolean;
var
  i : tasmtoken;
  hs : string;
Begin
  { GNU as is also not casesensitive with this }
  hs:=lower(s);
  for i:=firstdirective to lastdirective do
   if hs=token2str[i] then
    begin
      actasmtoken:=i;
      is_asmdirective:=true;
      exit;
    end;
  is_asmdirective:=false;
end;


Function is_register(const s: string):boolean;
Var
  i : tregister;
Begin
  actasmregister:=R_NO;
  for i:=firstreg to lastreg do
   if s=iasmregs^[i] then
    begin
      actasmtoken:=AS_REGISTER;
      actasmregister:=i;
      is_register:=true;
      exit;
    end;
  is_register:=false;
end;


Function is_locallabel(const s: string):boolean;
begin
  is_locallabel:=(length(s)>=2) and (s[1]='.') and (s[2]='L');
end;


Procedure GetToken;
var
  forcelabel: boolean;
  errorflag : boolean;
  len : longint;
begin
  { save old token and reset new token }
  prevasmtoken:=actasmtoken;
  actasmtoken:=AS_NONE;
  { reset }
  errorflag:=FALSE;
  forcelabel:=FALSE;
  actasmpattern:='';
  { while space and tab , continue scan... }
  while c in [' ',#9] do
   c:=current_scanner^.asmgetchar;
  { get token pos }
  if not (c in [newline,#13,'{',';']) then
    current_scanner^.gettokenpos;
{ Local Label, Label, Directive, Prefix or Opcode }
  if firsttoken and not(c in [newline,#13,'{',';']) then
   begin
     firsttoken:=FALSE;
     len:=0;
     { directive or local label }
     if c = '.' then
      begin
        inc(len);
        actasmpattern[len]:=c;
        { Let us point to the next character }
        c:=current_scanner^.asmgetchar;
        while c in ['A'..'Z','a'..'z','0'..'9','_','$'] do
         begin
           inc(len);
           actasmpattern[len]:=c;
           c:=current_scanner^.asmgetchar;
         end;
        actasmpattern[0]:=chr(len);
        { this is a local label... }
        if (c=':') and is_locallabel(actasmpattern) then
         Begin
           { local variables are case sensitive }
           actasmtoken:=AS_LLABEL;
           c:=current_scanner^.asmgetchar;
           exit;
         end
        { must be a directive }
        else
         Begin
           { directives are case sensitive!! }
           if is_asmdirective(actasmpattern) then
            exit;
           Message1(asmr_e_not_directive_or_local_symbol,actasmpattern);
         end;
      end;
     { only opcodes and global labels are allowed now. }
     while c in ['A'..'Z','a'..'z','0'..'9','_'] do
      begin
        inc(len);
        actasmpattern[len]:=c;
        c:=current_scanner^.asmgetchar;
      end;
     actasmpattern[0]:=chr(len);
     { Label ? }
     if c = ':' then
      begin
        actasmtoken:=AS_LABEL;
        { let us point to the next character }
        c:=current_scanner^.asmgetchar;
        exit;
      end;
     { Opcode ? }
     If is_asmopcode(upper(actasmpattern)) then
      Begin
        uppervar(actasmpattern);
        exit;
      end;
     { End of assemblerblock ? }
     if upper(actasmpattern) = 'END' then
      begin
        actasmtoken:=AS_END;
        exit;
      end;
     actasmtoken:=AS_NONE;
   end
  else { else firsttoken }
  { Here we must handle all possible cases }
   begin
     case c of
       '.' :  { possiblities : - local label reference , such as in jmp @local1 }
              {               - field of object/record                         }
              {               - directive.                                     }
         begin
           if (prevasmtoken=AS_ID) then
            begin
              c:=current_scanner^.asmgetchar;
              actasmtoken:=AS_DOT;
              exit;
            end;
           actasmpattern:=c;
           c:=current_scanner^.asmgetchar;
           while c in  ['A'..'Z','a'..'z','0'..'9','_','$'] do
            begin
              actasmpattern:=actasmpattern + c;
              c:=current_scanner^.asmgetchar;
            end;
           if is_asmdirective(actasmpattern) then
            exit;
           { local label references and directives }
           { are case sensitive                    }
           actasmtoken:=AS_ID;
           exit;
         end;

    { identifier, register, prefix or directive }
       '_','A'..'Z','a'..'z':
         begin
           len:=0;
           while c in ['A'..'Z','a'..'z','0'..'9','_','$'] do
            begin
              inc(len);
              actasmpattern[len]:=c;
              c:=current_scanner^.asmgetchar;
            end;
           actasmpattern[0]:=chr(len);
           uppervar(actasmpattern);
           { Opcode, can only be when the previous was a prefix }
           If is_prefix(actopcode) and is_asmopcode(upper(actasmpattern)) then
            Begin
              uppervar(actasmpattern);
              exit;
            end;
           { check for end which is a reserved word unlike the opcodes }
           if actasmpattern = 'END' then
            Begin
              actasmtoken:=AS_END;
              exit;
            end;
           actasmtoken:=AS_ID;
           exit;
         end;

       '%' : { register or modulo }
         begin
           len:=1;
           actasmpattern[len]:='%';
           c:=current_scanner^.asmgetchar;
           while c in ['a'..'z','A'..'Z','0'..'9'] do
            Begin
              inc(len);
              actasmpattern[len]:=c;
              c:=current_scanner^.asmgetchar;
            end;
           actasmpattern[0]:=chr(len);
           uppervar(actasmpattern);
           if (actasmpattern = '%ST') and (c='(') then
            Begin
              actasmpattern:=actasmpattern+c;
              c:=current_scanner^.asmgetchar;
              if c in ['0'..'9'] then
               actasmpattern:=actasmpattern + c
              else
               Message(asmr_e_invalid_fpu_register);
              c:=current_scanner^.asmgetchar;
              if c <> ')' then
               Message(asmr_e_invalid_fpu_register)
              else
               Begin
                 actasmpattern:=actasmpattern + c;
                 c:=current_scanner^.asmgetchar; { let us point to next character. }
               end;
            end;
           if is_register(actasmpattern) then
            exit;
           Message(asmr_w_modulo_not_supported);
         end;

       '1'..'9': { integer number }
         begin
           len:=0;
           while c in ['0'..'9'] do
            Begin
              inc(len);
              actasmpattern[len]:=c;
              c:=current_scanner^.asmgetchar;
            end;
           actasmpattern[0]:=chr(len);
           actasmpattern:=tostr(ValDecimal(actasmpattern));
           actasmtoken:=AS_INTNUM;
           exit;
         end;
       '0' : { octal,hexa,real or binary number. }
         begin
           actasmpattern:=c;
           c:=current_scanner^.asmgetchar;
           case upcase(c) of
             'B': { binary }
               Begin
                 c:=current_scanner^.asmgetchar;
                 while c in ['0','1'] do
                  Begin
                    actasmpattern:=actasmpattern + c;
                    c:=current_scanner^.asmgetchar;
                  end;
                 actasmpattern:=tostr(ValBinary(actasmpattern));
                 actasmtoken:=AS_INTNUM;
                 exit;
               end;
             'D': { real }
               Begin
                 c:=current_scanner^.asmgetchar;
                 { get ridd of the 0d }
                 if (c in ['+','-']) then
                  begin
                    actasmpattern:=c;
                    c:=current_scanner^.asmgetchar;
                  end
                 else
                  actasmpattern:='';
                 while c in ['0'..'9'] do
                  Begin
                    actasmpattern:=actasmpattern + c;
                    c:=current_scanner^.asmgetchar;
                  end;
                 if c='.' then
                  begin
                    actasmpattern:=actasmpattern + c;
                    c:=current_scanner^.asmgetchar;
                    while c in ['0'..'9'] do
                     Begin
                       actasmpattern:=actasmpattern + c;
                       c:=current_scanner^.asmgetchar;
                     end;
                    if upcase(c) = 'E' then
                     begin
                       actasmpattern:=actasmpattern + c;
                       c:=current_scanner^.asmgetchar;
                       if (c in ['+','-']) then
                        begin
                          actasmpattern:=actasmpattern + c;
                          c:=current_scanner^.asmgetchar;
                        end;
                       while c in ['0'..'9'] do
                        Begin
                          actasmpattern:=actasmpattern + c;
                          c:=current_scanner^.asmgetchar;
                        end;
                     end;
                    actasmtoken:=AS_REALNUM;
                    exit;
                  end
                 else
                  begin
                    Message1(asmr_e_invalid_float_const,actasmpattern+c);
                    actasmtoken:=AS_NONE;
                 end;
               end;
             'X': { hexadecimal }
               Begin
                 c:=current_scanner^.asmgetchar;
                 while c in ['0'..'9','a'..'f','A'..'F'] do
                  Begin
                    actasmpattern:=actasmpattern + c;
                    c:=current_scanner^.asmgetchar;
                  end;
                 actasmpattern:=tostr(ValHexaDecimal(actasmpattern));
                 actasmtoken:=AS_INTNUM;
                 exit;
               end;
             '1'..'7': { octal }
               begin
                 actasmpattern:=actasmpattern + c;
                 while c in ['0'..'7'] do
                  Begin
                    actasmpattern:=actasmpattern + c;
                    c:=current_scanner^.asmgetchar;
                  end;
                 actasmpattern:=tostr(ValOctal(actasmpattern));
                 actasmtoken:=AS_INTNUM;
                 exit;
               end;
             else { octal number zero value...}
               Begin
                 actasmpattern:=tostr(ValOctal(actasmpattern));
                 actasmtoken:=AS_INTNUM;
                 exit;
               end;
           end; { end case }
         end;

       '&' :
         begin
           c:=current_scanner^.asmgetchar;
           actasmtoken:=AS_AND;
         end;

       '''' : { char }
         begin
           actasmpattern:='';
           repeat
             c:=current_scanner^.asmgetchar;
             case c of
               '\' :
                 begin
                   { copy also the next char so \" is parsed correctly }
                   c:=current_scanner^.asmgetchar;
                   actasmpattern:=actasmpattern+c;
                 end;
               '''' :
                 begin
                   c:=current_scanner^.asmgetchar;
                   break;
                 end;
               newline:
                 Message(scan_f_string_exceeds_line);
               else
                 actasmpattern:=actasmpattern+c;
             end;
           until false;
           actasmpattern:=EscapeToPascal(actasmpattern);
           actasmtoken:=AS_STRING;
           exit;
         end;

       '"' : { string }
         begin
           actasmpattern:='';
           repeat
             c:=current_scanner^.asmgetchar;
             case c of
               '\' :
                 begin
                   { copy also the next char so \" is parsed correctly }
                   c:=current_scanner^.asmgetchar;
                   actasmpattern:=actasmpattern+c;
                 end;
               '"' :
                 begin
                   c:=current_scanner^.asmgetchar;
                   break;
                 end;
               newline:
                 Message(scan_f_string_exceeds_line);
               else
                 actasmpattern:=actasmpattern+c;
             end;
           until false;
           actasmpattern:=EscapeToPascal(actasmpattern);
           actasmtoken:=AS_STRING;
           exit;
         end;

       '$' :
         begin
           actasmtoken:=AS_DOLLAR;
           c:=current_scanner^.asmgetchar;
           exit;
         end;

       ',' :
         begin
           actasmtoken:=AS_COMMA;
           c:=current_scanner^.asmgetchar;
           exit;
         end;

       '<' :
         begin
           actasmtoken:=AS_SHL;
           c:=current_scanner^.asmgetchar;
           if c = '<' then
            c:=current_scanner^.asmgetchar;
           exit;
         end;

       '>' :
         begin
           actasmtoken:=AS_SHL;
           c:=current_scanner^.asmgetchar;
           if c = '>' then
            c:=current_scanner^.asmgetchar;
           exit;
         end;

       '|' :
         begin
           actasmtoken:=AS_OR;
           c:=current_scanner^.asmgetchar;
           exit;
         end;

       '^' :
         begin
           actasmtoken:=AS_XOR;
           c:=current_scanner^.asmgetchar;
           exit;
         end;

       '!' :
         begin
           Message(asmr_e_nor_not_supported);
           c:=current_scanner^.asmgetchar;
           actasmtoken:=AS_NONE;
           exit;
         end;

       '(' :
         begin
           actasmtoken:=AS_LPAREN;
           c:=current_scanner^.asmgetchar;
           exit;
         end;

       ')' :
         begin
           actasmtoken:=AS_RPAREN;
           c:=current_scanner^.asmgetchar;
           exit;
         end;

       ':' :
         begin
           actasmtoken:=AS_COLON;
           c:=current_scanner^.asmgetchar;
           exit;
         end;

       '+' :
         begin
           actasmtoken:=AS_PLUS;
           c:=current_scanner^.asmgetchar;
           exit;
         end;

       '-' :
         begin
           actasmtoken:=AS_MINUS;
           c:=current_scanner^.asmgetchar;
           exit;
         end;

       '*' :
         begin
           actasmtoken:=AS_STAR;
           c:=current_scanner^.asmgetchar;
           exit;
         end;

       '/' :
         begin
           c:=current_scanner^.asmgetchar;
           actasmtoken:=AS_SLASH;
           exit;
         end;

       '{',#13,newline,';' :
         begin
           { the comment is read by asmgetchar }
           c:=current_scanner^.asmgetchar;
           firsttoken:=TRUE;
           actasmtoken:=AS_SEPARATOR;
           exit;
         end;

       else
         Begin
           Message(scan_f_illegal_char);
         end;
     end;
   end;
end;


function consume(t : tasmtoken):boolean;
begin
  Consume:=true;
  if t<>actasmtoken then
   begin
     Message2(scan_f_syn_expected,token2str[t],token2str[actasmtoken]);
     Consume:=false;
   end;
  repeat
    gettoken;
  until actasmtoken<>AS_NONE;
end;


procedure RecoverConsume(allowcomma:boolean);
begin
  While not (actasmtoken in [AS_SEPARATOR,AS_END]) do
   begin
     if allowcomma and (actasmtoken=AS_COMMA) then
      break;
     Consume(actasmtoken);
   end;
end;


{*****************************************************************************
                               Parsing Helpers
*****************************************************************************}

Procedure BuildRecordOffsetSize(const expr: string;var offset:longint;var size:longint);
{ Description: This routine builds up a record offset after a AS_DOT }
{ token is encountered.                                              }
{ On entry actasmtoken should be equal to AS_DOT                     }
var
  s : string;
Begin
  offset:=0;
  size:=0;
  s:=expr;
  while (actasmtoken=AS_DOT) do
   begin
     Consume(AS_DOT);
     if actasmtoken=AS_ID then
      s:=s+'.'+actasmpattern;
     if not Consume(AS_ID) then
      begin
        RecoverConsume(true);
        break;
      end;
   end;
  if not GetRecordOffsetSize(s,offset,size) then
   Message(asmr_e_building_record_offset);
end;


Procedure BuildConstSymbolExpression(allowref,betweenbracket,needofs:boolean;var value:longint;var asmsym:string);
var
  hs,tempstr,expr : string;
  parenlevel,l,k : longint;
  errorflag : boolean;
  prevtok : tasmtoken;
  sym : psym;
  hl  : PAsmLabel;
Begin
  asmsym:='';
  value:=0;
  errorflag:=FALSE;
  tempstr:='';
  expr:='';
  inexpression:=TRUE;
  parenlevel:=0;
  Repeat
    Case actasmtoken of
      AS_LPAREN:
        Begin
          { Exit if ref? }
          if allowref and (prevasmtoken in [AS_INTNUM,AS_ID]) then
           break;
          Consume(AS_LPAREN);
          expr:=expr + '(';
          inc(parenlevel);
        end;
      AS_RPAREN:
        Begin
          { end of ref ? }
          if (parenlevel=0) and betweenbracket then
           break;
          Consume(AS_RPAREN);
          expr:=expr + ')';
          dec(parenlevel);
        end;
      AS_SHL:
        Begin
          Consume(AS_SHL);
          expr:=expr + '<';
        end;
      AS_SHR:
        Begin
          Consume(AS_SHR);
          expr:=expr + '>';
        end;
      AS_SLASH:
        Begin
          Consume(AS_SLASH);
          expr:=expr + '/';
        end;
      AS_MOD:
        Begin
          Consume(AS_MOD);
          expr:=expr + '%';
        end;
      AS_STAR:
        Begin
          Consume(AS_STAR);
          expr:=expr + '*';
        end;
      AS_PLUS:
        Begin
          Consume(AS_PLUS);
          expr:=expr + '+';
        end;
      AS_MINUS:
        Begin
          Consume(AS_MINUS);
          expr:=expr + '-';
        end;
      AS_AND:
        Begin
          Consume(AS_AND);
          expr:=expr + '&';
        end;
      AS_NOT:
        Begin
          Consume(AS_NOT);
          expr:=expr + '~';
        end;
      AS_XOR:
        Begin
          Consume(AS_XOR);
          expr:=expr + '^';
        end;
      AS_OR:
        Begin
          Consume(AS_OR);
          expr:=expr + '|';
        end;
      AS_INTNUM:
        Begin
          expr:=expr + actasmpattern;
          Consume(AS_INTNUM);
        end;
      AS_DOLLAR:
        begin
          Consume(AS_DOLLAR);
          if actasmtoken<>AS_ID then
           Comment(V_Error,'assem_e_dollar_without_identifier');
        end;
      AS_ID:
        Begin
          tempstr:=actasmpattern;
          prevtok:=prevasmtoken;
          consume(AS_ID);
          if actasmtoken=AS_DOT then
           begin
             BuildRecordOffsetSize(tempstr,l,k);
             str(l, tempstr);
             expr:=expr + tempstr;
           end
          else
           if SearchIConstant(tempstr,l) then
            begin
              str(l, tempstr);
              expr:=expr + tempstr;
            end
          else
           begin
             hs:='';
             if is_locallabel(tempstr) then
              begin
                CreateLocalLabel(tempstr,hl,false);
                hs:=hl^.name
              end
             else
              if SearchLabel(tempstr,hl,false) then
               hs:=hl^.name
             else
              begin
                getsym(tempstr,false);
                sym:=srsym;
                if assigned(sym) then
                 begin
                   if sym^.owner^.symtabletype in [localsymtable,parasymtable] then
                     Message(asmr_e_no_local_or_para_allowed);
                   case srsym^.typ of
                     varsym :
                       hs:=pvarsym(srsym)^.mangledname;
                     typedconstsym :
                       hs:=ptypedconstsym(srsym)^.mangledname;
                     procsym :
                       hs:=pprocsym(srsym)^.mangledname;
                     else
                       Message(asmr_e_wrong_sym_type);
                   end;
                 end
                else
                 Message1(sym_e_unknown_id,tempstr);
              end;
             { symbol found? }
             if hs<>'' then
              begin
                if needofs and (prevtok<>AS_DOLLAR) then
                 Message(asmr_e_need_offset);
                if asmsym='' then
                 asmsym:=hs
                else
                 Message(asmr_e_cant_have_multiple_relocatable_symbols);
                if (expr='') or (expr[length(expr)]='+') then
                 begin
                   delete(expr,length(expr),1);
                   if not(actasmtoken in [AS_MINUS,AS_PLUS,AS_COMMA,AS_SEPARATOR,AS_END]) then
                    Message(asmr_e_only_add_relocatable_symbol);
                 end
                else
                 Message(asmr_e_only_add_relocatable_symbol);
              end
             else
              begin
                { Error recovery }
                if (expr='') or (expr[length(expr)] in ['+','-','/','*']) then
                 delete(expr,length(expr),1);
              end;
           end;
        end;
      AS_SEPARATOR,
      AS_COMMA:
        Begin
          break;
        end;
    else
      Begin
        { write error only once. }
        if not errorflag then
          Message(asmr_e_invalid_constant_expression);
        { consume tokens until we find COMMA or SEPARATOR }
        Consume(actasmtoken);
        errorflag:=TRUE;
      end;
    end;
  Until false;
  { calculate expression }
  if not ErrorFlag then
    value:=CalculateExpression(expr)
  else
    value:=0;
  { no longer in an expression }
  inexpression:=FALSE;
end;


Function BuildConstExpression(allowref,betweenbracket:boolean): longint;
var
  l : longint;
  hs : string;
begin
  BuildConstSymbolExpression(allowref,betweenbracket,false,l,hs);
  if hs<>'' then
   Message(asmr_e_relocatable_symbol_not_allowed);
  BuildConstExpression:=l;
end;


{****************************************************************************
                                T386ATTOperand
****************************************************************************}

type
  P386ATTOperand=^T386ATTOperand;
  T386ATTOperand=object(T386Operand)
    Procedure BuildOperand;virtual;
  private
    Procedure BuildReference;
    Procedure BuildConstant;
  end;


Procedure T386ATTOperand.BuildReference;

  procedure Consume_RParen;
  begin
    if actasmtoken <> AS_RPAREN then
     Begin
       Message(asmr_e_invalid_reference_syntax);
       RecoverConsume(true);
     end
    else
     begin
       Consume(AS_RPAREN);
       if not (actasmtoken in [AS_COMMA,AS_SEPARATOR]) then
        Begin
          Message(asmr_e_invalid_reference_syntax);
          RecoverConsume(true);
        end;
     end;
  end;

  procedure Consume_Scale;
  var
    l : longint;
  begin
    { we have to process the scaling }
    l:=BuildConstExpression(false,true);
    if ((l = 2) or (l = 4) or (l = 8) or (l = 1)) then
     opr.ref.scalefactor:=l
    else
     Begin
       Message(asmr_e_wrong_scale_factor);
       opr.ref.scalefactor:=0;
     end;
  end;

Begin
  Consume(AS_LPAREN);
  Case actasmtoken of
    AS_INTNUM,
    AS_MINUS,
    AS_PLUS: { absolute offset, such as fs:(0x046c) }
      Begin
        { offset(offset) is invalid }
        If opr.Ref.Offset <> 0 Then
         Begin
           Message(asmr_e_invalid_reference_syntax);
           RecoverConsume(true);
         End
        Else
         Begin
           opr.Ref.Offset:=BuildConstExpression(false,true);
           Consume_RParen;
         end;
        exit;
      End;
    AS_REGISTER: { (reg ...  }
      Begin
        { Check if there is already a base (mostly ebp,esp) than this is
          not allowed,becuase it will give crashing code }
        if opr.ref.base<>R_NO then
         Message(asmr_e_cannot_index_relative_var);
        opr.ref.base:=actasmregister;
        Consume(AS_REGISTER);
        { can either be a register or a right parenthesis }
        { (reg)        }
        if actasmtoken=AS_RPAREN then
         Begin
           Consume_RParen;
           exit;
         end;
        { (reg,reg ..  }
        Consume(AS_COMMA);
        if actasmtoken=AS_REGISTER then
         Begin
           opr.ref.index:=actasmregister;
           Consume(AS_REGISTER);
           { check for scaling ... }
           case actasmtoken of
             AS_RPAREN:
               Begin
                 Consume_RParen;
                 exit;
               end;
             AS_COMMA:
               Begin
                 Consume(AS_COMMA);
                 Consume_Scale;
                 Consume_RParen;
               end;
           else
             Begin
               Message(asmr_e_invalid_reference_syntax);
               RecoverConsume(false);
             end;
           end; { end case }
         end
        else
         Begin
           Message(asmr_e_invalid_reference_syntax);
           RecoverConsume(false);
         end;
      end; {end case }
    AS_COMMA: { (, ...  can either be scaling, or index }
      Begin
        Consume(AS_COMMA);
        { Index }
        if (actasmtoken=AS_REGISTER) then
         Begin
           opr.ref.index:=actasmregister;
           Consume(AS_REGISTER);
           { check for scaling ... }
           case actasmtoken of
             AS_RPAREN:
               Begin
                 Consume_RParen;
                 exit;
               end;
             AS_COMMA:
               Begin
                 Consume(AS_COMMA);
                 Consume_Scale;
                 Consume_RParen;
               end;
           else
             Begin
               Message(asmr_e_invalid_reference_syntax);
               RecoverConsume(false);
             end;
           end; {end case }
         end
        { Scaling }
        else
         Begin
           Consume_Scale;
           Consume_RParen;
           exit;
         end;
      end;

  else
    Begin
      Message(asmr_e_invalid_reference_syntax);
      RecoverConsume(false);
    end;
  end;
end;


Procedure T386ATTOperand.BuildConstant;
var
  l : longint;
  tempstr : string;
begin
  BuildConstSymbolExpression(false,false,true,l,tempstr);
  if tempstr<>'' then
   begin
     opr.typ:=OPR_SYMBOL;
     opr.symofs:=l;
     opr.symbol:=newasmsymbol(tempstr);
   end
  else
   begin
     opr.typ:=OPR_CONSTANT;
     opr.val:=l;
   end;
end;


Procedure T386ATTOperand.BuildOperand;

  procedure AddLabelOperand(hl:pasmlabel);
  begin
    if not(actasmtoken in [AS_PLUS,AS_MINUS,AS_LPAREN]) and
       is_calljmp(actopcode) then
     begin
       opr.typ:=OPR_SYMBOL;
       opr.symbol:=hl;
     end
    else
     begin
       InitRef;
       opr.ref.symbol:=hl;
     end;
  end;

  function MaybeBuildReference:boolean;
  { Try to create a reference, if not a reference is found then false
    is returned }
  begin
    MaybeBuildReference:=true;
    case actasmtoken of
      AS_INTNUM,
      AS_MINUS,
      AS_PLUS:
        Begin
          opr.ref.offset:=BuildConstExpression(True,False);
          if actasmtoken<>AS_LPAREN then
            Message(asmr_e_invalid_reference_syntax)
          else
            BuildReference;
        end;
      AS_LPAREN:
        BuildReference;
      AS_ID: { only a variable is allowed ... }
        Begin
          if not SetupVar(actasmpattern) then
            Message(asmr_e_invalid_reference_syntax);
          Consume(actasmtoken);
          case actasmtoken of
            AS_SEPARATOR,
            AS_COMMA: ;
            AS_LPAREN: BuildReference;
          else
            Begin
              Message(asmr_e_invalid_reference_syntax);
              Consume(actasmtoken);
            end;
          end; {end case }
        end;
      else
       MaybeBuildReference:=false;
    end; { end case }
  end;

var
  expr,
  tempstr : string;
  tempreg : tregister;
  hl      : PAsmLabel;
  tsize,l,
  toffset : longint;
Begin
  tempstr:='';
  expr:='';
  case actasmtoken of
    AS_LPAREN: { Memory reference or constant expression }
      Begin
        InitRef;
        BuildReference;
      end;

    AS_DOLLAR: { Constant expression  }
      Begin
        Consume(AS_DOLLAR);
        BuildConstant;
      end;

    AS_INTNUM,
    AS_MINUS,
    AS_PLUS:
      Begin
        { Constant memory offset }
        { This must absolutely be followed by (  }
        InitRef;
        opr.ref.offset:=BuildConstExpression(True,False);
        if actasmtoken<>AS_LPAREN then
          Message(asmr_e_invalid_reference_syntax)
        else
          BuildReference;
      end;

    AS_STAR: { Call from memory address }
      Begin
        Consume(AS_STAR);
        if actasmtoken=AS_REGISTER then
         begin
           opr.typ:=OPR_REGISTER;
           opr.reg:=actasmregister;
           size:=reg_2_opsize[actasmregister];
           Consume(AS_REGISTER);
         end
        else
         begin
           InitRef;
           if not MaybeBuildReference then
            Message(asmr_e_syn_operand);
         end;
        { this is only allowed for call's and jmp's }
        if not is_calljmp(actopcode) then
         Message(asmr_e_syn_operand);
      end;

    AS_ID: { A constant expression, or a Variable ref.  }
      Begin
        { Local Label ? }
        if is_locallabel(actasmpattern) then
         begin
           CreateLocalLabel(actasmpattern,hl,false);
           Consume(AS_ID);
           AddLabelOperand(hl);
         end
        else
         { Check for label }
         if SearchLabel(actasmpattern,hl,false) then
          begin
            Consume(AS_ID);
            AddLabelOperand(hl);
          end
        else
         { probably a variable or normal expression }
         { or a procedure (such as in CALL ID)      }
         Begin
           InitRef;
           if not SetupVar(actasmpattern) then
            Begin
              { look for special symbols ... }
              if actasmpattern = '__RESULT' then
                SetUpResult
              else
               if actasmpattern = '__SELF' then
                SetupSelf
              else
               if actasmpattern = '__OLDEBP' then
                SetupOldEBP
              else
                { check for direct symbolic names   }
                { only if compiling the system unit }
                if (cs_compilesystem in aktmoduleswitches) then
                 begin
                   if not SetupDirectVar(actasmpattern) then
                    Begin
                      { not found, finally ... add it anyways ... }
                      Message1(asmr_w_id_supposed_external,actasmpattern);
                      opr.ref.symbol:=newasmsymbol(actasmpattern);
                    end;
                 end
              else
                Message1(sym_e_unknown_id,actasmpattern);
            end;
           { constant expression? }
           if (opr.typ=OPR_CONSTANT) then
            begin
              l:=BuildConstExpression(true,false);
              { indexing? }
              if actasmtoken=AS_LPAREN then
               begin
                 opr.typ:=OPR_REFERENCE;
                 reset_reference(opr.Ref);
                 opr.Ref.Offset:=l;
                 BuildReference;
               end
              else
               opr.Val:=l;
            end
           else
            begin
              expr:=actasmpattern;
              Consume(AS_ID);
              if actasmtoken=AS_DOT then
               begin
                 BuildRecordOffsetSize(expr,toffset,tsize);
                 inc(opr.ref.offset,toffset);
                 SetSize(tsize);
               end;
            end;
         end;
        if opr.typ=OPR_REFERENCE then
         begin
           { Do we have a +[constant] ? }
           if actasmtoken in [AS_PLUS,AS_MINUS] then
            inc(opr.ref.offset,BuildConstExpression(true,false));
           { Do we have a indexing reference, then parse it also }
           if actasmtoken=AS_LPAREN then
             BuildReference;
         end;
      end;

    AS_REGISTER: { Register, a variable reference or a constant reference  }
      Begin
        { save the type of register used. }
        tempreg:=actasmregister;
        Consume(AS_REGISTER);
        if actasmtoken = AS_COLON then
         Begin
           Consume(AS_COLON);
           InitRef;
           opr.ref.segment:=tempreg;
           { This must absolutely be followed by a reference }
           if not MaybeBuildReference then
            Begin
              Message(asmr_e_invalid_seg_override);
              Consume(actasmtoken);
            end;
         end
        { Simple register  }
        else if (actasmtoken in [AS_SEPARATOR,AS_COMMA]) then
         Begin
           if not (opr.typ in [OPR_NONE,OPR_REGISTER]) then
             Message(asmr_e_invalid_operand_type);
           opr.typ:=OPR_REGISTER;
           opr.reg:=tempreg;
           size:=reg_2_opsize[tempreg];
         end
        else
         Message(asmr_e_syn_operand);
      end;
    AS_SEPARATOR,
    AS_COMMA: ;
  else
    Begin
      Message(asmr_e_syn_operand);
      Consume(actasmtoken);
    end;
  end; { end case }
end;

{*****************************************************************************
                                T386ATTInstruction
*****************************************************************************}

type
  P386AttInstruction=^T386AttInstruction;
  T386AttInstruction=object(T386Instruction)
    procedure InitOperands;virtual;
    procedure BuildOpcode;virtual;
  end;

procedure T386AttInstruction.InitOperands;
var
  i : longint;
begin
  for i:=1to 3 do
   Operands[i]:=new(P386AttOperand,Init);
end;


Procedure T386AttInstruction.BuildOpCode;
var
  operandnum : longint;
  PrefixOp,OverrideOp: tasmop;
  expr : string;
Begin
  expr:='';
  PrefixOp:=A_None;
  OverrideOp:=A_None;
  { prefix seg opcode / prefix opcode }
  repeat
    if is_prefix(actopcode) then
     begin
       PrefixOp:=ActOpcode;
       opcode:=ActOpcode;
       condition:=ActCondition;
       opsize:=ActOpsize;
       ConcatInstruction(curlist);
       Consume(AS_OPCODE);
     end
    else
     if is_override(actopcode) then
      begin
        OverrideOp:=ActOpcode;
        opcode:=ActOpcode;
        condition:=ActCondition;
        opsize:=ActOpsize;
        ConcatInstruction(curlist);
        Consume(AS_OPCODE);
      end
    else
     break;
    { allow for newline as in gas styled syntax }
    while actasmtoken=AS_SEPARATOR do
      Consume(AS_SEPARATOR);
  until (actasmtoken<>AS_OPCODE);
  { opcode }
  if (actasmtoken <> AS_OPCODE) then
   Begin
     Message(asmr_e_invalid_or_missing_opcode);
     RecoverConsume(true);
     exit;
   end;
  { Fill the instr object with the current state }
  Opcode:=ActOpcode;
  condition:=ActCondition;
  opsize:=ActOpsize;
  { Valid combination of prefix/override and instruction ?  }
  if (prefixop<>A_NONE) and (NOT CheckPrefix(PrefixOp,actopcode)) then
    Message1(asmr_e_invalid_prefix_and_opcode,actasmpattern);
  if (overrideop<>A_NONE) and (NOT CheckOverride(OverrideOp,ActOpcode)) then
    Message1(asmr_e_invalid_override_and_opcode,actasmpattern);
  { We are reading operands, so opcode will be an AS_ID }
  operandnum:=1;
  Consume(AS_OPCODE);
  { Zero operand opcode ?  }
  if actasmtoken in [AS_SEPARATOR,AS_END] then
   begin
     operandnum:=0;
     exit;
   end;
{ Read the operands }
  repeat
    case actasmtoken of
      AS_COMMA: { Operand delimiter }
        Begin
          if operandnum > MaxOperands then
           Message(asmr_e_too_many_operands)
          else
           Inc(operandnum);
          Consume(AS_COMMA);
        end;
      AS_SEPARATOR,
      AS_END : { End of asm operands for this opcode  }
        begin
          break;
        end;
    else
      Operands[operandnum]^.BuildOperand;
    end; { end case }
  until false;
  Ops:=operandnum;
end;



Procedure BuildConstant(maxvalue: longint);
var
 strlength: byte;
 asmsym,
 expr: string;
 value : longint;
Begin
  Repeat
    Case actasmtoken of
      AS_STRING:
        Begin
          if maxvalue = $ff then
           strlength:=1
          else
           Message(asmr_e_string_not_allowed_as_const);
          expr:=actasmpattern;
          if length(expr) > 1 then
           Message(asmr_e_string_not_allowed_as_const);
          Consume(AS_STRING);
          Case actasmtoken of
            AS_COMMA: Consume(AS_COMMA);
            AS_SEPARATOR: ;
          else
            Message(asmr_e_invalid_string_expression);
          end; { end case }
          ConcatString(curlist,expr);
        end;
      AS_INTNUM,
      AS_PLUS,
      AS_MINUS,
      AS_LPAREN,
      AS_NOT,
      AS_ID :
        Begin
          BuildConstSymbolExpression(false,false,false,value,asmsym);
          if asmsym<>'' then
           begin
             if maxvalue<>$ffffffff then
              Comment(V_Warning,'32bit constant created for address');
             ConcatConstSymbol(curlist,asmsym,value)
           end
          else
           ConcatConstant(curlist,value,maxvalue);
        end;
      AS_COMMA:
        Consume(AS_COMMA);
      AS_SEPARATOR:
        break;
      else
        begin
          Message(asmr_e_syn_constant);
          RecoverConsume(false);
        end
   end; { end case }
 Until false;
end;


Procedure BuildRealConstant(typ : tfloattype);
var
  expr : string;
  r : bestreal;
  code : integer;
  negativ : boolean;
  errorflag: boolean;
Begin
  errorflag:=FALSE;
  Repeat
    negativ:=false;
    expr:='';
    if actasmtoken=AS_PLUS then
      Consume(AS_PLUS)
    else
     if actasmtoken=AS_MINUS then
      begin
        negativ:=true;
        consume(AS_MINUS);
      end;
    Case actasmtoken of
      AS_INTNUM:
        Begin
          expr:=actasmpattern;
          Consume(AS_INTNUM);
          if negativ then
           expr:='-'+expr;
          val(expr,r,code);
          if code<>0 then
           Begin
             r:=0;
             Message(asmr_e_invalid_float_expr);
           End;
          ConcatRealConstant(curlist,r,typ);
        end;
      AS_REALNUM:
        Begin
          expr:=actasmpattern;
          Consume(AS_REALNUM);
          { in ATT syntax you have 0d in front of the real }
          { should this be forced ?  yes i think so, as to }
          { conform to gas as much as possible.            }
          if (expr[1]='0') and (upper(expr[2])='D') then
           Delete(expr,1,2);
          if negativ then
           expr:='-'+expr;
          val(expr,r,code);
          if code<>0 then
           Begin
             r:=0;
             Message(asmr_e_invalid_float_expr);
           End;
          ConcatRealConstant(curlist,r,typ);
        end;
      AS_COMMA:
        begin
          Consume(AS_COMMA);
        end;
      AS_SEPARATOR:
        begin
          break;
        end;
   else
     Begin
       Consume(actasmtoken);
       if not errorflag then
        Message(asmr_e_invalid_float_expr);
       errorflag:=TRUE;
     end;
   end;
 Until false;
end;


Procedure BuildStringConstant(asciiz: boolean);
var
  expr: string;
  errorflag : boolean;
Begin
  errorflag:=FALSE;
  Repeat
    Case actasmtoken of
      AS_STRING:
        Begin
          expr:=actasmpattern;
          if asciiz then
            expr:=expr+#0;
          ConcatPasString(curlist,expr);
          Consume(AS_STRING);
        end;
      AS_COMMA:
        begin
          Consume(AS_COMMA);
        end;
      AS_SEPARATOR:
        begin
          break;
        end;
   else
     Begin
       Consume(actasmtoken);
       if not errorflag then
        Message(asmr_e_invalid_string_expression);
       errorflag:=TRUE;
     end;
   end;
 Until false;
end;


Function Assemble: Ptree;
Var
  hl         : PAsmLabel;
  commname   : string;
  lastsec    : tsection;
  instr      : T386ATTInstruction;
Begin
  Message1(asmr_d_start_reading,'AT&T');
  firsttoken:=TRUE;
  if assigned(procinfo.retdef) and
     (is_fpu(procinfo.retdef) or
     ret_in_acc(procinfo.retdef)) then
    procinfo.funcret_is_valid:=true;
  { sets up all opcode and register tables in uppercase }
  if not _asmsorted then
   Begin
     SetupTables;
     _asmsorted:=TRUE;
   end;
  curlist:=new(paasmoutput,init);
  lastsec:=sec_code;
  { setup label linked list }
  new(LocalLabelList,Init);
  { start tokenizer }
  c:=current_scanner^.asmgetchar;
  gettoken;
  { main loop }
  repeat
    case actasmtoken of
      AS_LLABEL:
        Begin
          if CreateLocalLabel(actasmpattern,hl,true) then
            ConcatLabel(curlist,hl);
          Consume(AS_LLABEL);
        end;

      AS_LABEL:
        Begin
          if SearchLabel(upper(actasmpattern),hl,true) then
           ConcatLabel(curlist,hl)
          else
           Message1(asmr_e_unknown_label_identifier,actasmpattern);
          Consume(AS_LABEL);
        end;

      AS_DW:
        Begin
          Consume(AS_DW);
          BuildConstant($ffff);
        end;

      AS_DATA:
        Begin
          curlist^.Concat(new(pai_section,init(sec_data)));
          lastsec:=sec_data;
          Consume(AS_DATA);
        end;

      AS_TEXT:
        Begin
          curlist^.Concat(new(pai_section,init(sec_code)));
          lastsec:=sec_code;
          Consume(AS_TEXT);
        end;

      AS_DB:
        Begin
          Consume(AS_DB);
          BuildConstant($ff);
        end;

      AS_DD:
        Begin
          Consume(AS_DD);
          BuildConstant($ffffffff);
        end;

      AS_DQ:
        Begin
          Consume(AS_DQ);
          BuildRealConstant(s64comp);
        end;

      AS_SINGLE:
        Begin
          Consume(AS_SINGLE);
          BuildRealConstant(s32real);
        end;

      AS_DOUBLE:
        Begin
          Consume(AS_DOUBLE);
          BuildRealConstant(s64real);
        end;

      AS_EXTENDED:
        Begin
          Consume(AS_EXTENDED);
          BuildRealConstant(s80real);
        end;

      AS_GLOBAL:
        Begin
          Consume(AS_GLOBAL);
          if actasmtoken=AS_ID then
            ConcatPublic(curlist,actasmpattern);
          Consume(AS_ID);
          if actasmtoken<>AS_SEPARATOR then
           Consume(AS_SEPARATOR);
        end;

      AS_ALIGN:
        Begin
          Consume(AS_ALIGN);
          ConcatAlign(curlist,BuildConstExpression(false,false));
          if actasmtoken<>AS_SEPARATOR then
           Consume(AS_SEPARATOR);
        end;

      AS_ASCIIZ:
        Begin
          Consume(AS_ASCIIZ);
          BuildStringConstant(TRUE);
        end;

      AS_ASCII:
        Begin
          Consume(AS_ASCII);
          BuildStringConstant(FALSE);
        end;

      AS_LCOMM:
        Begin
          Consume(AS_LCOMM);
          commname:=actasmpattern;
          Consume(AS_ID);
          Consume(AS_COMMA);
          ConcatLocalBss(commname,BuildConstExpression(false,false));
          if actasmtoken<>AS_SEPARATOR then
           Consume(AS_SEPARATOR);
        end;

      AS_COMM:
        Begin
          Consume(AS_COMM);
          commname:=actasmpattern;
          Consume(AS_ID);
          Consume(AS_COMMA);
          ConcatGlobalBss(commname,BuildConstExpression(false,false));
          if actasmtoken<>AS_SEPARATOR then
           Consume(AS_SEPARATOR);
        end;
      AS_OPCODE:
        Begin
          instr.init;
          instr.BuildOpcode;
          instr.AddReferenceSizes;
          instr.SetInstructionOpsize;
          instr.CheckOperandSizes;
          instr.ConcatInstruction(curlist);
          instr.done;
        end;

      AS_SEPARATOR:
        Begin
          Consume(AS_SEPARATOR);
        end;

      AS_END:
        begin
          break; { end assembly block }
        end;

      else
        Begin
          Message(asmr_e_syntax_error);
          RecoverConsume(false);
        end;
    end;
  until false;
  { Check LocalLabelList }
  LocalLabelList^.CheckEmitted;
  dispose(LocalLabelList,Done);
  { are we back in the code section? }
  if lastsec<>sec_code then
   begin
     Message(asmr_w_assembler_code_not_returned_to_text);
     curlist^.Concat(new(pai_section,init(sec_code)));
   end;
  { Return the list in an asmnode }
  assemble:=genasmnode(curlist);
  Message1(asmr_d_finish_reading,'AT&T');
end;


{*****************************************************************************
                                     Initialize
*****************************************************************************}

var
  old_exit : pointer;

procedure ra386att_exit;{$ifndef FPC}far;{$endif}
begin
  if assigned(iasmops) then
    dispose(iasmops);
  if assigned(iasmregs) then
    dispose(iasmregs);
  exitproc:=old_exit;
end;


begin
   old_exit:=exitproc;
   exitproc:=@ra386att_exit;
end.
{
  $Log$
  Revision 1.49  1999-06-03 16:28:03  pierre
   * typo corrected

  Revision 1.48  1999/05/27 19:44:56  peter
    * removed oldasm
    * plabel -> pasmlabel
    * -a switches to source writing automaticly
    * assembler readers OOPed
    * asmsymbol automaticly external
    * jumptables and other label fixes for asm readers

  Revision 1.47  1999/05/21 13:55:13  peter
    * NEWLAB for label as symbol

  Revision 1.46  1999/05/12 00:19:56  peter
    * removed R_DEFAULT_SEG
    * uniform float names

  Revision 1.45  1999/05/06 09:05:25  peter
    * generic write_float and str_float
    * fixed constant float conversions

  Revision 1.44  1999/05/05 22:22:00  peter
    * updated messages

  Revision 1.43  1999/05/04 21:45:01  florian
    * changes to compile it with Delphi 4.0

  Revision 1.42  1999/05/02 14:25:07  peter
    * only allow *<reg/ref> when call/jmp is used

  Revision 1.41  1999/05/01 13:48:39  peter
    * merged nasm compiler

  Revision 1.7  1999/04/29 09:37:47  peter
    * fixed var+const support

  Revision 1.6  1999/04/26 23:26:17  peter
    * redesigned record offset parsing to support nested records
    * normal compiler uses the redesigned createvarinstr()

  Revision 1.5  1999/04/20 11:01:23  peter
    * better tokenpos info

  Revision 1.4  1999/04/14 09:07:45  peter
    * asm reader improvements

  Revision 1.3  1999/03/06 17:24:26  peter
    * rewritten intel parser a lot, especially reference reading
    * size checking added for asm parsers

  Revision 1.2  1999/03/02 02:56:30  peter
    + stabs support for binary writers
    * more fixes and missing updates from the previous commit :(

  Revision 1.1  1999/03/01 15:46:26  peter
    * ag386bin finally make cycles correct
    * prefixes are now also normal opcodes

}

