{
    $Id$
    Copyright (c) 1993-98 by Florian Klaempfl

    Generate m68k assembler for constants

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
unit cg68kcon;
interface

    uses
      tree;

{.$define SMALLSETORD}


    procedure secondrealconst(var p : ptree);
    procedure secondfixconst(var p : ptree);
    procedure secondordconst(var p : ptree);
    procedure secondstringconst(var p : ptree);
    procedure secondsetconst(var p : ptree);
    procedure secondniln(var p : ptree);


implementation

    uses
      globtype,systems,
      cobjects,verbose,globals,
      symtable,aasm,types,
      hcodegen,temp_gen,pass_2,
      m68k,cga68k,tgen68k;

{*****************************************************************************
                             SecondRealConst
*****************************************************************************}

    procedure secondrealconst(var p : ptree);
      var
         hp1 : pai;
         lastlabel : plabel;
      begin
         lastlabel:=nil;
         { const already used ? }
         if not assigned(p^.lab_real) then
           begin
              { tries to found an old entry }
              hp1:=pai(consts^.first);
              while assigned(hp1) do
                begin
                   if hp1^.typ=ait_label then
                     lastlabel:=pai_label(hp1)^.l
                   else
                     begin
                        if (hp1^.typ=p^.realtyp) and (lastlabel<>nil) then
                          begin
                             if ((p^.realtyp=ait_real_64bit) and (pai_double(hp1)^.value=p^.value_real)) or
                               ((p^.realtyp=ait_real_extended) and (pai_extended(hp1)^.value=p^.value_real)) or
                               ((p^.realtyp=ait_real_32bit) and (pai_single(hp1)^.value=p^.value_real)) then
                               begin
                                  { found! }
                                  p^.lab_real:=lastlabel;
                                  break;
                               end;
                          end;
                        lastlabel:=nil;
                     end;
                   hp1:=pai(hp1^.next);
                end;
              { :-(, we must generate a new entry }
              if not assigned(p^.lab_real) then
                begin
                   getdatalabel(lastlabel);
                   p^.lab_real:=lastlabel;
                   if (cs_smartlink in aktmoduleswitches) then
                    consts^.concat(new(pai_cut,init));
                   consts^.concat(new(pai_label,init(lastlabel)));
                   case p^.realtyp of
                     ait_real_64bit : consts^.concat(new(pai_double,init(p^.value_real)));
                     ait_real_32bit : consts^.concat(new(pai_single,init(p^.value_real)));
                  ait_real_extended : consts^.concat(new(pai_extended,init(p^.value_real)));
                   else
                     internalerror(10120);
                   end;
                end;
           end;
         clear_reference(p^.location.reference);
         p^.location.reference.symbol:=stringdup(lab2str(p^.lab_real));
         p^.location.loc:=LOC_MEM;
      end;


{*****************************************************************************
                             SecondFixConst
*****************************************************************************}

    procedure secondfixconst(var p : ptree);
      begin
         { an fix comma const. behaves as a memory reference }
         p^.location.loc:=LOC_MEM;
         p^.location.reference.isintvalue:=true;
         p^.location.reference.offset:=p^.value_fix;
      end;


{*****************************************************************************
                             SecondOrdConst
*****************************************************************************}

    procedure secondordconst(var p : ptree);
      begin
         { an integer const. behaves as a memory reference }
         p^.location.loc:=LOC_MEM;
         p^.location.reference.isintvalue:=true;
         p^.location.reference.offset:=p^.value;
      end;


{*****************************************************************************
                             SecondStringConst
*****************************************************************************}

    procedure secondstringconst(var p : ptree);
      var
         hp1 : pai;
         l1,l2,
         lastlabel   : plabel;
         pc          : pchar;
         same_string : boolean;
         i,mylength  : longint;
      begin
         lastlabel:=nil;
         { const already used ? }
         if not assigned(p^.lab_str) then
           begin
              if is_shortstring(p^.resulttype) then
               mylength:=p^.length+2
              else
               mylength:=p^.length+1;
              { tries to found an old entry }
              hp1:=pai(consts^.first);
              while assigned(hp1) do
                begin
                   if hp1^.typ=ait_label then
                     lastlabel:=pai_label(hp1)^.l
                   else
                     begin
                        { when changing that code, be careful that }
                        { you don't use typed consts, which are    }
                        { are also written to consts               }
                        { currently, this is no problem, because   }
                        { typed consts have no leading length or   }
                        { they have no trailing zero               }
                        if (hp1^.typ=ait_string) and (lastlabel<>nil) and
                           (pai_string(hp1)^.len=mylength) then
                          begin
                             same_string:=true;
                             for i:=0 to p^.length do
                               if pai_string(hp1)^.str[i]<>p^.value_str[i] then
                                 begin
                                    same_string:=false;
                                    break;
                                 end;
                             if same_string then
                               begin
                                  { found! }
                                  p^.lab_str:=lastlabel;
                                  break;
                               end;
                          end;
                        lastlabel:=nil;
                     end;
                   hp1:=pai(hp1^.next);
                end;
              { :-(, we must generate a new entry }
              if not assigned(p^.lab_str) then
                begin
                   getdatalabel(lastlabel);
                   p^.lab_str:=lastlabel;
                   if (cs_smartlink in aktmoduleswitches) then
                    consts^.concat(new(pai_cut,init));
                   consts^.concat(new(pai_label,init(lastlabel)));
                   { generate an ansi string ? }
                   case p^.stringtype of
                      st_ansistring:
                        begin
                           { an empty ansi string is nil! }
                           if p^.length=0 then
                             consts^.concat(new(pai_const,init_32bit(0)))
                           else
                             begin
                                getdatalabel(l1);
                                getdatalabel(l2);
                                consts^.concat(new(pai_label,init(l2)));
                                consts^.concat(new(pai_const,init_symbol(strpnew(lab2str(l1)))));
                                consts^.concat(new(pai_const,init_32bit(p^.length)));
                                consts^.concat(new(pai_const,init_32bit(p^.length)));
                                consts^.concat(new(pai_const,init_32bit(-1)));
                                consts^.concat(new(pai_label,init(l1)));
                                getmem(pc,p^.length+2);
                                move(p^.value_str^,pc^,p^.length);
                                pc[p^.length]:=#0;
                                { to overcome this problem we set the length explicitly }
                                { with the ending null char }
                                consts^.concat(new(pai_string,init_length_pchar(pc,p^.length+1)));
                                { return the offset of the real string }
                                p^.lab_str:=l2;
                             end;
                        end;
                      st_shortstring:
                        begin
                           { empty strings }
                           if p^.length=0 then
                            consts^.concat(new(pai_const,init_16bit(0)))
                           else
                            begin
                              { also length and terminating zero }
                              getmem(pc,p^.length+3);
                              move(p^.value_str^,pc[1],p^.length+1);
                              pc[0]:=chr(p^.length);
                              { to overcome this problem we set the length explicitly }
                              { with the ending null char }
                              pc[p^.length+1]:=#0;
                              consts^.concat(new(pai_string,init_length_pchar(pc,p^.length+2)));
                            end;
                        end;
                   end;
                end;
           end;
         clear_reference(p^.location.reference);
         p^.location.reference.symbol:=stringdup(lab2str(p^.lab_str));
         p^.location.loc:=LOC_MEM;
      end;


{*****************************************************************************
                             SecondSetCons
*****************************************************************************}

    procedure secondsetconst(var p : ptree);
      var
         hp1         : pai;
         lastlabel   : plabel;
         i           : longint;
         neededtyp   : tait;
      begin
{$ifdef SMALLSETORD}
        { small sets are loaded as constants }
        if psetdef(p^.resulttype)^.settype=smallset then
         begin
           p^.location.loc:=LOC_MEM;
           p^.location.reference.isintvalue:=true;
           p^.location.reference.offset:=plongint(p^.value_set)^;
           exit;
         end;
{$endif}
        if psetdef(p^.resulttype)^.settype=smallset then
         neededtyp:=ait_const_32bit
        else
         neededtyp:=ait_const_8bit;
        lastlabel:=nil;
        { const already used ? }
        if not assigned(p^.lab_set) then
          begin
             { tries to found an old entry }
             hp1:=pai(consts^.first);
             while assigned(hp1) do
               begin
                  if hp1^.typ=ait_label then
                    lastlabel:=pai_label(hp1)^.l
                  else
                    begin
                      if (lastlabel<>nil) and (hp1^.typ=neededtyp) then
                        begin
                          if (hp1^.typ=ait_const_8bit) then
                           begin
                             { compare normal set }
                             i:=0;
                             while assigned(hp1) and (i<32) do
                              begin
                                if pai_const(hp1)^.value<>p^.value_set^[i] then
                                 break;
                                inc(i);
                                hp1:=pai(hp1^.next);
                              end;
                             if i=32 then
                              begin
                                { found! }
                                p^.lab_set:=lastlabel;
                                break;
                              end;
                             { leave when the end of consts is reached, so no
                               hp1^.next is done }
                             if not assigned(hp1) then
                              break;
                           end
                          else
                           begin
                             { compare small set }
                             if plongint(p^.value_set)^=pai_const(hp1)^.value then
                              begin
                                { found! }
                                p^.lab_set:=lastlabel;
                                break;
                              end;
                           end;
                        end;
                      lastlabel:=nil;
                    end;
                  hp1:=pai(hp1^.next);
               end;
             { :-(, we must generate a new entry }
             if not assigned(p^.lab_set) then
               begin
                 getdatalabel(lastlabel);
                 p^.lab_set:=lastlabel;
                 if (cs_smartlink in aktmoduleswitches) then
                  consts^.concat(new(pai_cut,init));
                 consts^.concat(new(pai_label,init(lastlabel)));
                 if psetdef(p^.resulttype)^.settype=smallset then
                  begin
                    move(p^.value_set^,i,sizeof(longint));
                    consts^.concat(new(pai_const,init_32bit(i)));
                  end
                 else
                  begin
                    for i:=0 to 31 do
                      consts^.concat(new(pai_const,init_8bit(p^.value_set^[i])));
                  end;
               end;
          end;
        clear_reference(p^.location.reference);
        p^.location.reference.symbol:=stringdup(lab2str(p^.lab_set));
        p^.location.loc:=LOC_MEM;
      end;


{*****************************************************************************
                             SecondNilN
*****************************************************************************}

    procedure secondniln(var p : ptree);
      begin
         p^.location.loc:=LOC_MEM;
         p^.location.reference.isintvalue:=true;
         p^.location.reference.offset:=0;
      end;

end.
{
  $Log$
  Revision 1.5  1998-12-11 00:03:01  peter
    + globtype,tokens,version unit splitted from globals

  Revision 1.4  1998/11/06 09:47:29  pierre
   * problem of const with ansi fixed

  Revision 1.3  1998/11/05 12:02:37  peter
    * released useansistring
    * removed -Sv, its now available in fpc modes

  Revision 1.2  1998/09/07 18:45:56  peter
    * update smartlinking, uses getdatalabel
    * renamed ptree.value vars to value_str,value_real,value_set

}
