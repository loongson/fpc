{
    $Id$
    Copyright (c) 1993-98 by Florian Klaempfl

    Type checking and register allocation for type converting nodes

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
  {$E+,F+,N+,D+,L+,Y+}
{$endif}
unit tccnv;
interface

    uses
      tree;

    procedure arrayconstructor_to_set(var p:ptree);

    procedure firsttypeconv(var p : ptree);
    procedure firstas(var p : ptree);
    procedure firstis(var p : ptree);


implementation

   uses
      cobjects,verbose,globals,systems,
      symtable,aasm,types,
      hcodegen,htypechk,pass_1
{$ifdef i386}
      ,i386
{$endif}
{$ifdef m68k}
      ,m68k
{$endif}
      ;


{*****************************************************************************
                    Array constructor to Set Conversion
*****************************************************************************}

    procedure arrayconstructor_to_set(var p:ptree);
      var
        constp,
        buildp,
        p2,p3,p4    : ptree;
        pd          : pdef;
        constset    : pconstset;
        constsetlo,
        constsethi  : longint;

        procedure update_constsethi(p:pdef);
        begin
          if ((p^.deftype=orddef) and
              (porddef(p)^.high>constsethi)) then
            constsethi:=porddef(p)^.high
          else
            if ((p^.deftype=enumdef) and
                (penumdef(p)^.max>constsethi)) then
              constsethi:=penumdef(p)^.max;
        end;

        procedure do_set(pos : longint);
        var
          mask,l : longint;
        begin
          if (pos>255) or (pos<0) then
           Message(parser_e_illegal_set_expr);
          if pos>constsethi then
           constsethi:=pos;
          if pos<constsetlo then
           constsetlo:=pos;
          l:=pos shr 3;
          mask:=1 shl (pos mod 8);
          { do we allow the same twice }
          if (constset^[l] and mask)<>0 then
           Message(parser_e_illegal_set_expr);
          constset^[l]:=constset^[l] or mask;
        end;

      var
        l : longint;
      begin
        new(constset);
        FillChar(constset^,sizeof(constset^),0);
        pd:=nil;
        constsetlo:=0;
        constsethi:=0;
        constp:=gensinglenode(setconstn,nil);
        constp^.value_set:=constset;
        buildp:=constp;
        if assigned(p^.left) then
         begin
           while assigned(p) do
            begin
              p4:=nil; { will contain the tree to create the set }
            { split a range into p2 and p3 }
              if p^.left^.treetype=arrayconstructrangen then
               begin
                 p2:=p^.left^.left;
                 p3:=p^.left^.right;
               { node is not used anymore }
                 putnode(p^.left);
               end
              else
               begin
                 p2:=p^.left;
                 p3:=nil;
               end;
              firstpass(p2);
              if assigned(p3) then
               firstpass(p3);
              if codegenerror then
               break;
              case p2^.resulttype^.deftype of
            enumdef,
             orddef : begin
                        if is_integer(p2^.resulttype) then
                         begin
                           p2:=gentypeconvnode(p2,u8bitdef);
                           firstpass(p2);
                         end;
                        { set settype result }
                        if pd=nil then
                          pd:=p2^.resulttype;
                        if not(is_equal(pd,p2^.resulttype)) then
                         begin
                           CGMessage(type_e_typeconflict_in_set);
                           disposetree(p2);
                         end
                        else
                         begin
                           if assigned(p3) then
                            begin
                              if is_integer(p3^.resulttype) then
                               begin
                                 p3:=gentypeconvnode(p3,u8bitdef);
                                 firstpass(p3);
                               end;
                              if not(is_equal(pd,p3^.resulttype)) then
                                CGMessage(type_e_typeconflict_in_set)
                              else
                                begin
                                  if (p2^.treetype=ordconstn) and (p3^.treetype=ordconstn) then
                                   begin
                                     for l:=p2^.value to p3^.value do
                                      do_set(l);
                                     disposetree(p3);
                                     disposetree(p2);
                                   end
                                  else
                                   begin
                                     update_constsethi(p3^.resulttype);
                                     p4:=gennode(setelementn,p2,p3);
                                   end;
                                end;
                            end
                           else
                            begin
                           { Single value }
                              if p2^.treetype=ordconstn then
                               begin
                                 do_set(p2^.value);
                                 disposetree(p2);
                               end
                              else
                               begin
                                 update_constsethi(p2^.resulttype);
                                 p4:=gennode(setelementn,p2,nil);
                               end;
                            end;
                         end;
                      end;
          stringdef : begin
                        if pd=nil then
                         pd:=cchardef;
                        if not(is_equal(pd,cchardef)) then
                         CGMessage(type_e_typeconflict_in_set)
                        else
                         for l:=1 to length(pstring(p2^.value_str)^) do
                          do_set(ord(pstring(p2^.value_str)^[l]));
                        disposetree(p2);
                      end;
              else
               CGMessage(type_e_ordinal_expr_expected);
              end;
            { insert the set creation tree }
              if assigned(p4) then
               buildp:=gennode(addn,buildp,p4);
            { load next and dispose current node }
              p2:=p;
              p:=p^.right;
              putnode(p2);
            end;
         end
        else
         begin
         { empty set [], only remove node }
           putnode(p);
         end;
      { set the initial set type }
        constp^.resulttype:=new(psetdef,init(pd,constsethi));
      { set the new tree }
        p:=buildp;
      end;


{*****************************************************************************
                             FirstTypeConv
*****************************************************************************}

    type
       tfirstconvproc = procedure(var p : ptree);


    procedure first_bigger_smaller(var p : ptree);
      begin
         if (p^.left^.location.loc<>LOC_REGISTER) and (p^.registers32=0) then
           p^.registers32:=1;
         p^.location.loc:=LOC_REGISTER;
      end;


    procedure first_cstring_charpointer(var p : ptree);
      begin
         p^.registers32:=1;
         p^.location.loc:=LOC_REGISTER;
      end;


    procedure first_string_chararray(var p : ptree);
      begin
         p^.registers32:=1;
         p^.location.loc:=LOC_REGISTER;
      end;


    procedure first_string_string(var p : ptree);
      begin
         if pstringdef(p^.resulttype)^.string_typ<>
            pstringdef(p^.left^.resulttype)^.string_typ then
           begin
              if p^.left^.treetype=stringconstn then
                begin
                   p^.left^.stringtype:=pstringdef(p^.resulttype)^.string_typ;
                   { we don't have to do anything, the const }
                   { node generates an ansistring            }
                   p^.convtyp:=tc_equal;
                end
              else
                procinfo.flags:=procinfo.flags or pi_do_call;
           end;
         { for simplicity lets first keep all ansistrings
           as LOC_MEM, could also become LOC_REGISTER }
         p^.location.loc:=LOC_MEM;
      end;


    procedure first_char_to_string(var p : ptree);
      var
         hp : ptree;
      begin
         if p^.left^.treetype=ordconstn then
           begin
              hp:=genstringconstnode(chr(p^.left^.value));
              hp^.stringtype:=pstringdef(p^.resulttype)^.string_typ;
              firstpass(hp);
              disposetree(p);
              p:=hp;
           end
         else
           p^.location.loc:=LOC_MEM;
      end;


    procedure first_nothing(var p : ptree);
      begin
         p^.location.loc:=LOC_MEM;
      end;


    procedure first_array_to_pointer(var p : ptree);
      begin
         if p^.registers32<1 then
           p^.registers32:=1;
         p^.location.loc:=LOC_REGISTER;
      end;


    procedure first_int_real(var p : ptree);
      var
        t : ptree;
      begin
         if p^.left^.treetype=ordconstn then
           begin
              { convert constants direct }
              { not because of type conversion }
              t:=genrealconstnode(p^.left^.value);
              { do a first pass here
                because firstpass of typeconv does
                not redo it for left field !! }
              firstpass(t);
              { the type can be something else than s64real !!}
              t:=gentypeconvnode(t,p^.resulttype);
              firstpass(t);
              disposetree(p);
              p:=t;
              exit;
           end
         else
           begin
              if p^.registersfpu<1 then
                p^.registersfpu:=1;
              p^.location.loc:=LOC_FPU;
           end;
      end;


    procedure first_int_fix(var p : ptree);
      begin
         if p^.left^.treetype=ordconstn then
           begin
              { convert constants direct }
              p^.treetype:=fixconstn;
              p^.value_fix:=p^.left^.value shl 16;
              p^.disposetyp:=dt_nothing;
              disposetree(p^.left);
              p^.location.loc:=LOC_MEM;
           end
         else
           begin
              if p^.registers32<1 then
                p^.registers32:=1;
                  p^.location.loc:=LOC_REGISTER;
           end;
      end;


    procedure first_real_fix(var p : ptree);
      begin
         if p^.left^.treetype=realconstn then
           begin
              { convert constants direct }
              p^.treetype:=fixconstn;
              p^.value_fix:=round(p^.left^.value_real*65536);
              p^.disposetyp:=dt_nothing;
              disposetree(p^.left);
              p^.location.loc:=LOC_MEM;
           end
         else
           begin
              { at least one fpu and int register needed }
              if p^.registers32<1 then
                p^.registers32:=1;
              if p^.registersfpu<1 then
                p^.registersfpu:=1;
              p^.location.loc:=LOC_REGISTER;
           end;
      end;


    procedure first_fix_real(var p : ptree);
      begin
         if p^.left^.treetype=fixconstn then
           begin
              { convert constants direct }
              p^.treetype:=realconstn;
              p^.value_real:=round(p^.left^.value_fix/65536.0);
              p^.disposetyp:=dt_nothing;
              disposetree(p^.left);
              p^.location.loc:=LOC_MEM;
           end
         else
           begin
              if p^.registersfpu<1 then
                p^.registersfpu:=1;
                  p^.location.loc:=LOC_FPU;
           end;
      end;


    procedure first_real_real(var p : ptree);
      begin
         if p^.registersfpu<1 then
           p^.registersfpu:=1;
         p^.location.loc:=LOC_FPU;
      end;


    procedure first_pointer_to_array(var p : ptree);
      begin
         if p^.registers32<1 then
           p^.registers32:=1;
         p^.location.loc:=LOC_REFERENCE;
      end;


    procedure first_chararray_string(var p : ptree);
      begin
         { the only important information is the location of the }
         { result                                                }
         { other stuff is done by firsttypeconv                  }
         p^.location.loc:=LOC_MEM;
      end;


    procedure first_cchar_charpointer(var p : ptree);
      begin
         p^.left:=gentypeconvnode(p^.left,cstringdef);
         { convert constant char to constant string }
         firstpass(p^.left);
         { evalute tree }
         firstpass(p);
      end;


    procedure first_locmem(var p : ptree);
      begin
         p^.location.loc:=LOC_MEM;
      end;


    procedure first_bool_int(var p : ptree);
      begin
         p^.location.loc:=LOC_REGISTER;
         { Florian I think this is overestimated
           but I still do not really understand how to get this right (PM) }
         { Hmmm, I think we need only one reg to return the result of      }
         { this node => so }
         if p^.registers32<1 then
           p^.registers32:=1;
         {  should work (FK)
         p^.registers32:=p^.left^.registers32+1;}
      end;


    procedure first_int_bool(var p : ptree);
      begin
         p^.location.loc:=LOC_REGISTER;
         { Florian I think this is overestimated
           but I still do not really understand how to get this right (PM) }
         { Hmmm, I think we need only one reg to return the result of      }
         { this node => so }
         p^.left:=gentypeconvnode(p^.left,s32bitdef);
         firstpass(p^.left);
         if p^.registers32<1 then
           p^.registers32:=1;
{          p^.resulttype:=booldef; }
         {  should work (FK)
         p^.registers32:=p^.left^.registers32+1;}
      end;


    procedure first_proc_to_procvar(var p : ptree);
      begin
         { hmmm, I'am not sure if that is necessary (FK) }
         firstpass(p^.left);
         if codegenerror then
           exit;

         if (p^.left^.location.loc<>LOC_REFERENCE) then
           CGMessage(cg_e_illegal_expression);

         p^.registers32:=p^.left^.registers32;
         if p^.registers32<1 then
           p^.registers32:=1;
         p^.location.loc:=LOC_REGISTER;
      end;


    procedure first_load_smallset(var p : ptree);
      begin
      end;


    procedure first_pchar_to_string(var p : ptree);
      begin
         p^.location.loc:=LOC_MEM;
      end;

    procedure first_ansistring_to_pchar(var p : ptree);
      begin
         p^.location.loc:=LOC_REGISTER;
         if p^.registers32<1 then
           p^.registers32:=1;
      end;


    procedure first_arrayconstructor_to_set(var p:ptree);
      var
        hp : ptree;
      begin
        if p^.left^.treetype<>arrayconstructn then
         internalerror(5546);
      { remove typeconv node }
        hp:=p;
        p:=p^.left;
        putnode(hp);
      { create a set constructor tree }
        arrayconstructor_to_set(p);
      end;


  procedure firsttypeconv(var p : ptree);
    var
      hp : ptree;
      aprocdef : pprocdef;
      proctype : tdeftype;
    const
       firstconvert : array[tconverttype] of
         tfirstconvproc = (first_nothing,first_nothing,
                           first_bigger_smaller,first_nothing,first_bigger_smaller,
                           first_bigger_smaller,first_bigger_smaller,
                           first_bigger_smaller,first_bigger_smaller,
                           first_bigger_smaller,first_string_string,
                           first_cstring_charpointer,first_string_chararray,
                           first_array_to_pointer,first_pointer_to_array,
                           first_char_to_string,first_bigger_smaller,
                           first_bigger_smaller,first_bigger_smaller,
                           first_bigger_smaller,first_bigger_smaller,
                           first_bigger_smaller,first_bigger_smaller,
                           first_bigger_smaller,first_bigger_smaller,
                           first_bigger_smaller,first_bigger_smaller,
                           first_bigger_smaller,first_bigger_smaller,
                           first_bigger_smaller,first_bigger_smaller,
                           first_bigger_smaller,first_bigger_smaller,
                           first_bigger_smaller,first_bigger_smaller,
                           first_bool_int,first_int_bool,
                           first_int_real,first_real_fix,
                           first_fix_real,first_int_fix,first_real_real,
                           first_locmem,first_proc_to_procvar,
                           first_cchar_charpointer,
                           first_load_smallset,
                           first_ansistring_to_pchar,
                           first_pchar_to_string,
                           first_arrayconstructor_to_set);

     begin
       aprocdef:=nil;
       { if explicite type cast, then run firstpass }
       if p^.explizit then
         firstpass(p^.left);

       if codegenerror then
         begin
           p^.resulttype:=generrordef;
           exit;
         end;

       if not assigned(p^.left^.resulttype) then
        begin
          codegenerror:=true;
          internalerror(52349);
          exit;
        end;

       { load the value_str from the left part }
       p^.registers32:=p^.left^.registers32;
       p^.registersfpu:=p^.left^.registersfpu;
{$ifdef SUPPORT_MMX}
       p^.registersmmx:=p^.left^.registersmmx;
{$endif}
       set_location(p^.location,p^.left^.location);

       { remove obsolete type conversions }
       if is_equal(p^.left^.resulttype,p^.resulttype) then
         begin
         { becuase is_equal only checks the basetype for sets we need to
           check here if we are loading a smallset into a normalset }
           if (p^.resulttype^.deftype=setdef) and
              (p^.left^.resulttype^.deftype=setdef) and
              (psetdef(p^.resulttype)^.settype<>smallset) and
              (psetdef(p^.left^.resulttype)^.settype=smallset) then
            begin
            { try to define the set as a normalset if it's a constant set }
              if p^.left^.treetype=setconstn then
               begin
                 p^.resulttype:=p^.left^.resulttype;
                 psetdef(p^.resulttype)^.settype:=normset
               end
              else
               p^.convtyp:=tc_load_smallset;
              exit;
            end
           else
            begin
              hp:=p;
              p:=p^.left;
              p^.resulttype:=hp^.resulttype;
              putnode(hp);
              exit;
            end;
         end;

       if is_assignment_overloaded(p^.left^.resulttype,p^.resulttype) then
         begin
            procinfo.flags:=procinfo.flags or pi_do_call;
            hp:=gencallnode(overloaded_operators[assignment],nil);
            hp^.left:=gencallparanode(p^.left,nil);
            putnode(p);
            p:=hp;
            firstpass(p);
            exit;
         end;

       if (not(isconvertable(p^.left^.resulttype,p^.resulttype,
           p^.convtyp,p^.left^.treetype,p^.explizit))) then
         begin
           {Procedures have a resulttype of voiddef and functions of their
           own resulttype. They will therefore always be incompatible with
           a procvar. Because isconvertable cannot check for procedures we
           use an extra check for them.}
           if (m_tp_procvar in aktmodeswitches) and
             ((is_procsym_load(p^.left) or is_procsym_call(p^.left)) and
             (p^.resulttype^.deftype=procvardef)) then
             begin
                { just a test: p^.explizit:=false; }
                if is_procsym_call(p^.left) then
                  begin
                     if p^.left^.right=nil then
                       begin
                          p^.left^.treetype:=loadn;
                          { are at same offset so this could be spared, but
                          it more secure to do it anyway }
                          p^.left^.symtableentry:=p^.left^.symtableprocentry;
                          p^.left^.resulttype:=pprocsym(p^.left^.symtableentry)^.definition;
                          aprocdef:=pprocdef(p^.left^.resulttype);
                       end
                     else
                       begin
                          p^.left^.right^.treetype:=loadn;
                          p^.left^.right^.symtableentry:=p^.left^.right^.symtableentry;
                          P^.left^.right^.resulttype:=pvarsym(p^.left^.symtableentry)^.definition;
                          hp:=p^.left^.right;
                          putnode(p^.left);
                          p^.left:=hp;
                          { should we do that ? }
                          firstpass(p^.left);
                          if not is_equal(p^.left^.resulttype,p^.resulttype) then
                            begin
                               CGMessage(type_e_mismatch);
                               exit;
                            end
                          else
                            begin
                               hp:=p;
                               p:=p^.left;
                               p^.resulttype:=hp^.resulttype;
                               putnode(hp);
                               exit;
                            end;
                       end;
                  end
                else
                  begin
                     if p^.left^.treetype=addrn then
                       begin
                          hp:=p^.left;
                          p^.left:=p^.left^.left;
                          putnode(p^.left);
                       end
                     else
                       aprocdef:=pprocsym(p^.left^.symtableentry)^.definition;
                  end;

                p^.convtyp:=tc_proc2procvar;
                { Now check if the procedure we are going to assign to
                  the procvar,  is compatible with the procvar's type.
                  Did the original procvar support do such a check?
                  I can't find any.}
                { answer : is_equal works for procvardefs !! }
                { but both must be procvardefs, so we cheet  little }
                if assigned(aprocdef) then
                  begin
                    proctype:=aprocdef^.deftype;
                    aprocdef^.deftype:=procvardef;

                    if not is_equal(aprocdef,p^.resulttype) then
                      begin
                        aprocdef^.deftype:=proctype;
                        CGMessage(type_e_mismatch);
                      end;
                    aprocdef^.deftype:=proctype;
                    firstconvert[p^.convtyp](p);
                  end
                else
                  CGMessage(type_e_mismatch);
                exit;
             end
           else
             begin
                if p^.explizit then
                  begin
                     { boolean to byte are special because the
                       location can be different }
                     if (p^.resulttype^.deftype=orddef) and
                        (porddef(p^.resulttype)^.typ=u8bit) and
                        (p^.left^.resulttype^.deftype=orddef) and
                        (porddef(p^.left^.resulttype)^.typ=bool8bit) then
                       begin
                          p^.convtyp:=tc_bool_2_int;
                          firstconvert[p^.convtyp](p);
                          exit;
                       end;
                     if is_pchar(p^.resulttype) and
                       is_ansistring(p^.left^.resulttype) then
                       begin
                          p^.convtyp:=tc_ansistring_2_pchar;
                          firstconvert[p^.convtyp](p);
                          exit;
                       end;
                     { normal tc_equal-Konvertierung durchf�hren }
                     p^.convtyp:=tc_equal;
                     { wenn Aufz�hltyp nach Ordinal konvertiert werden soll }
                     { dann Aufz�hltyp=s32bit                               }
                     if (p^.left^.resulttype^.deftype=enumdef) and
                        is_ordinal(p^.resulttype) then
                       begin
                          if p^.left^.treetype=ordconstn then
                            begin
                               hp:=genordinalconstnode(p^.left^.value,p^.resulttype);
                               disposetree(p);
                               firstpass(hp);
                               p:=hp;
                               exit;
                            end
                          else
                            begin
                               if not isconvertable(s32bitdef,p^.resulttype,p^.convtyp,
                               ordconstn { only Dummy},false ) then
                                 CGMessage(cg_e_illegal_type_conversion);
                            end;

                       end
                     { ordinal to enumeration }
                     else
                       if (p^.resulttype^.deftype=enumdef) and
                          is_ordinal(p^.left^.resulttype) then
                         begin
                            if p^.left^.treetype=ordconstn then
                              begin
                                 hp:=genordinalconstnode(p^.left^.value,p^.resulttype);
                                 disposetree(p);
                                 firstpass(hp);
                                 p:=hp;
                                 exit;
                              end
                            else
                              begin
                                 if not isconvertable(p^.left^.resulttype,s32bitdef,p^.convtyp,
                                   ordconstn { nur Dummy},false ) then
                                   CGMessage(cg_e_illegal_type_conversion);
                              end;
                         end
                     {Are we typecasting an ordconst to a char?}
                     else
                       if is_equal(p^.resulttype,cchardef) and
                          is_ordinal(p^.left^.resulttype) then
                         begin
                            if p^.left^.treetype=ordconstn then
                              begin
                                 hp:=genordinalconstnode(p^.left^.value,p^.resulttype);
                                 firstpass(hp);
                                 disposetree(p);
                                 p:=hp;
                                 exit;
                              end
                            else
                              begin
                                 { this is wrong because it converts to a 4 byte long var !!
                                   if not isconvertable(p^.left^.resulttype,s32bitdef,p^.convtyp,ordconstn  nur Dummy ) then }
                                 if not isconvertable(p^.left^.resulttype,u8bitdef,
                                   p^.convtyp,ordconstn { nur Dummy},false ) then
                                   CGMessage(cg_e_illegal_type_conversion);
                              end;
                         end
                     { only if the same size or formal def }
                     { why do we allow typecasting of voiddef ?? (PM) }
                     else
                       if not(
                             (p^.left^.resulttype^.deftype=formaldef) or
                             (p^.left^.resulttype^.size=p^.resulttype^.size) or
                             (is_equal(p^.left^.resulttype,voiddef)  and
                             (p^.left^.treetype=derefn))
                             ) then
                         CGMessage(cg_e_illegal_type_conversion);
                     { the conversion into a strutured type is only }
                     { possible, if the source is no register         }
                     if ((p^.resulttype^.deftype in [recorddef,stringdef,arraydef]) or
                         ((p^.resulttype^.deftype=objectdef) and not(pobjectdef(p^.resulttype)^.isclass))
                        ) and (p^.left^.location.loc in [LOC_REGISTER,LOC_CREGISTER]) and
                        {it also works if the assignment is overloaded }
                        not is_assignment_overloaded(p^.left^.resulttype,p^.resulttype) then
                       CGMessage(cg_e_illegal_type_conversion);
                end
              else
                CGMessage(type_e_mismatch);
           end
         end
       else
         begin
            { ordinal contants can be directly converted }
            if (p^.left^.treetype=ordconstn) and is_ordinal(p^.resulttype) then
              begin
                 { perform range checking }
                 if not(p^.explizit and (m_tp in aktmodeswitches)) then
                   testrange(p^.resulttype,p^.left^.value);
                 hp:=genordinalconstnode(p^.left^.value,p^.resulttype);
                 disposetree(p);
                 firstpass(hp);
                 p:=hp;
                 exit;
              end;
            if p^.convtyp<>tc_equal then
              firstconvert[p^.convtyp](p);
         end;
      end;


{*****************************************************************************
                                FirstIs
*****************************************************************************}

    procedure firstis(var p : ptree);

      begin
         firstpass(p^.left);
         firstpass(p^.right);
         if codegenerror then
           exit;

         if (p^.right^.resulttype^.deftype<>classrefdef) then
           CGMessage(type_e_mismatch);

         left_right_max(p);

         { left must be a class }
         if (p^.left^.resulttype^.deftype<>objectdef) or
            not(pobjectdef(p^.left^.resulttype)^.isclass) then
           CGMessage(type_e_mismatch);

         { the operands must be related }
         if (not(pobjectdef(p^.left^.resulttype)^.isrelated(
           pobjectdef(pclassrefdef(p^.right^.resulttype)^.definition)))) and
           (not(pobjectdef(pclassrefdef(p^.right^.resulttype)^.definition)^.isrelated(
           pobjectdef(p^.left^.resulttype)))) then
           CGMessage(type_e_mismatch);

         p^.location.loc:=LOC_FLAGS;
         p^.resulttype:=booldef;
      end;


{*****************************************************************************
                                FirstAs
*****************************************************************************}

    procedure firstas(var p : ptree);
      begin
         firstpass(p^.right);
         firstpass(p^.left);
         if codegenerror then
           exit;

         if (p^.right^.resulttype^.deftype<>classrefdef) then
           CGMessage(type_e_mismatch);

         left_right_max(p);

         { left must be a class }
         if (p^.left^.resulttype^.deftype<>objectdef) or
           not(pobjectdef(p^.left^.resulttype)^.isclass) then
           CGMessage(type_e_mismatch);

         { the operands must be related }
         if (not(pobjectdef(p^.left^.resulttype)^.isrelated(
           pobjectdef(pclassrefdef(p^.right^.resulttype)^.definition)))) and
           (not(pobjectdef(pclassrefdef(p^.right^.resulttype)^.definition)^.isrelated(
           pobjectdef(p^.left^.resulttype)))) then
           CGMessage(type_e_mismatch);

         set_location(p^.location,p^.left^.location);
         p^.resulttype:=pclassrefdef(p^.right^.resulttype)^.definition;
      end;


end.
{
  $Log$
  Revision 1.5  1998-10-07 10:38:55  peter
    * forgot a firstpass in arrayconstruct2set

  Revision 1.4  1998/10/05 21:33:32  peter
    * fixed 161,165,166,167,168

  Revision 1.3  1998/09/27 10:16:26  florian
    * type casts pchar<->ansistring fixed
    * ansistring[..] calls does now an unique call

  Revision 1.2  1998/09/24 23:49:22  peter
    + aktmodeswitches

  Revision 1.1  1998/09/23 20:42:24  peter
    * splitted pass_1

}
