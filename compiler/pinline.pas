{
    $Id$
    Copyright (c) 1998-2002 by Florian Klaempfl

    Generates nodes for routines that need compiler support

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
unit pinline;

{$i fpcdefs.inc}

interface

    uses
      symtype,
      node,
      globals,
      cpuinfo;

    function new_dispose_statement(is_new:boolean) : tnode;
    function new_function : tnode;

    function inline_setlength : tnode;
    function inline_finalize : tnode;
    function inline_copy : tnode;


implementation

    uses
{$ifdef delphi}
       SysUtils,
{$endif}
       { common }
       cutils,
       { global }
       globtype,tokens,verbose,
       systems,
       { symtable }
       symconst,symdef,symsym,symtable,defutil,
       { pass 1 }
       pass_1,htypechk,
       nmat,nadd,ncal,nmem,nset,ncnv,ninl,ncon,nld,nflw,nbas,nutils,
       { parser }
       scanner,
       pbase,pexpr,
       { codegen }
       cgbase,procinfo
       ;


    function new_dispose_statement(is_new:boolean) : tnode;
      var
        newstatement : tstatementnode;
        temp         : ttempcreatenode;
        para         : tcallparanode;
        p,p2     : tnode;
        again    : boolean; { dummy for do_proc_call }
        destructorname : stringid;
        sym      : tsym;
        classh   : tobjectdef;
        callflag : tnodeflag;
        destructorpos,
        storepos : tfileposinfo;
      begin
        consume(_LKLAMMER);
        p:=comp_expr(true);
        { calc return type }
        set_varstate(p,(not is_new));
        { constructor,destructor specified }
        if try_to_consume(_COMMA) then
          begin
            { extended syntax of new and dispose }
            { function styled new is handled in factor }
            { destructors have no parameters }
            destructorname:=pattern;
            destructorpos:=akttokenpos;
            consume(_ID);

            if (p.resulttype.def.deftype<>pointerdef) then
              begin
                 Message1(type_e_pointer_type_expected,p.resulttype.def.typename);
                 p.free;
                 p:=factor(false);
                 p.free;
                 consume(_RKLAMMER);
                 new_dispose_statement:=cerrornode.create;
                 exit;
              end;
            { first parameter must be an object or class }
            if tpointerdef(p.resulttype.def).pointertype.def.deftype<>objectdef then
              begin
                 Message(parser_e_pointer_to_class_expected);
                 p.free;
                 new_dispose_statement:=factor(false);
                 consume_all_until(_RKLAMMER);
                 consume(_RKLAMMER);
                 exit;
              end;
            { check, if the first parameter is a pointer to a _class_ }
            classh:=tobjectdef(tpointerdef(p.resulttype.def).pointertype.def);
            if is_class(classh) then
              begin
                 Message(parser_e_no_new_or_dispose_for_classes);
                 new_dispose_statement:=factor(false);
                 consume_all_until(_RKLAMMER);
                 consume(_RKLAMMER);
                 exit;
              end;
            { search cons-/destructor, also in parent classes }
            storepos:=akttokenpos;
            akttokenpos:=destructorpos;
            sym:=search_class_member(classh,destructorname);
            akttokenpos:=storepos;

            { the second parameter of new/dispose must be a call }
            { to a cons-/destructor                              }
            if (not assigned(sym)) or (sym.typ<>procsym) then
              begin
                 if is_new then
                  Message(parser_e_expr_have_to_be_constructor_call)
                 else
                  Message(parser_e_expr_have_to_be_destructor_call);
                 p.free;
                 new_dispose_statement:=cerrornode.create;
              end
            else
              begin
                p2:=cderefnode.create(p.getcopy);
                do_resulttypepass(p2);
                if is_new then
                  callflag:=nf_new_call
                else
                  callflag:=nf_dispose_call;
                if is_new then
                  do_member_read(classh,false,sym,p2,again,[callflag])
                else
                  begin
                    if not(m_fpc in aktmodeswitches) then
                      do_member_read(classh,false,sym,p2,again,[callflag])
                    else
                      begin
                        p2:=ccallnode.create(nil,tprocsym(sym),sym.owner,p2);
                        if is_new then
                          include(p2.flags,nf_new_call)
                        else
                          include(p2.flags,nf_dispose_call);
                        { support dispose(p,done()); }
                        if try_to_consume(_LKLAMMER) then
                          begin
                            if not try_to_consume(_RKLAMMER) then
                              begin
                                Message(parser_e_no_paras_for_destructor);
                                consume_all_until(_RKLAMMER);
                                consume(_RKLAMMER);
                              end;
                          end;
                      end;
                  end;

                { we need the real called method }
                do_resulttypepass(p2);

                if p2.nodetype<>calln then
                  begin
                    if is_new then
                      CGMessage(parser_e_expr_have_to_be_constructor_call)
                    else
                      CGMessage(parser_e_expr_have_to_be_destructor_call);
                  end;

                if not codegenerror then
                 begin
                   if is_new then
                    begin
                      if (tcallnode(p2).procdefinition.proctypeoption<>potype_constructor) then
                        Message(parser_e_expr_have_to_be_constructor_call);
                      p2.resulttype:=p.resulttype;
                      p2:=cassignmentnode.create(p,p2);
                    end
                   else
                    begin
                      if (tcallnode(p2).procdefinition.proctypeoption<>potype_destructor) then
                        Message(parser_e_expr_have_to_be_destructor_call);
                    end;
                 end;
                new_dispose_statement:=p2;
              end;
          end
        else
          begin
             if (p.resulttype.def.deftype<>pointerdef) then
               Begin
                  Message1(type_e_pointer_type_expected,p.resulttype.def.typename);
                  new_dispose_statement:=cerrornode.create;
               end
             else
               begin
                  if (tpointerdef(p.resulttype.def).pointertype.def.deftype=objectdef) and
                     (oo_has_vmt in tobjectdef(tpointerdef(p.resulttype.def).pointertype.def).objectoptions) then
                    Message(parser_w_use_extended_syntax_for_objects);
                  if (tpointerdef(p.resulttype.def).pointertype.def.deftype=orddef) and
                     (torddef(tpointerdef(p.resulttype.def).pointertype.def).typ=uvoid) then
                    begin
                      if (m_tp7 in aktmodeswitches) or
                         (m_delphi in aktmodeswitches) then
                       Message(parser_w_no_new_dispose_on_void_pointers)
                      else
                       Message(parser_e_no_new_dispose_on_void_pointers);
                    end;

                  { create statements with call to getmem+initialize or
                    finalize+freemem }
                  new_dispose_statement:=internalstatements(newstatement,true);

                  if is_new then
                   begin
                     { create temp for result }
                     temp := ctempcreatenode.create(p.resulttype,p.resulttype.def.size,tt_persistent);
                     addstatement(newstatement,temp);

                     { create call to fpc_getmem }
                     para := ccallparanode.create(cordconstnode.create
                         (tpointerdef(p.resulttype.def).pointertype.def.size,s32bittype,true),nil);
                     addstatement(newstatement,cassignmentnode.create(
                         ctemprefnode.create(temp),
                         ccallnode.createintern('fpc_getmem',para)));

                     { create call to fpc_initialize }
                     if tpointerdef(p.resulttype.def).pointertype.def.needs_inittable then
                       addstatement(newstatement,initialize_data_node(ctemprefnode.create(temp)));

                     { copy the temp to the destination }
                     addstatement(newstatement,cassignmentnode.create(
                         p,
                         ctemprefnode.create(temp)));

                     { release temp }
                     addstatement(newstatement,ctempdeletenode.create(temp));
                   end
                  else
                   begin
                     { create call to fpc_finalize }
                     if tpointerdef(p.resulttype.def).pointertype.def.needs_inittable then
                       addstatement(newstatement,finalize_data_node(cderefnode.create(p.getcopy)));

                     { create call to fpc_freemem }
                     para := ccallparanode.create(p,nil);
                     addstatement(newstatement,ccallnode.createintern('fpc_freemem',para));
                   end;
               end;
          end;
        consume(_RKLAMMER);
      end;


    function new_function : tnode;
      var
        newstatement : tstatementnode;
        newblock     : tblocknode;
        temp         : ttempcreatenode;
        para         : tcallparanode;
        p1,p2  : tnode;
        classh : tobjectdef;
        sym    : tsym;
        again  : boolean; { dummy for do_proc_call }
      begin
        consume(_LKLAMMER);
        p1:=factor(false);
        if p1.nodetype<>typen then
         begin
           Message(type_e_type_id_expected);
           consume_all_until(_RKLAMMER);
           consume(_RKLAMMER);
           p1.destroy;
           new_function:=cerrornode.create;
           exit;
         end;

        if (p1.resulttype.def.deftype<>pointerdef) then
         begin
           Message1(type_e_pointer_type_expected,p1.resulttype.def.typename);
           consume_all_until(_RKLAMMER);
           consume(_RKLAMMER);
           p1.destroy;
           new_function:=cerrornode.create;
           exit;
         end;

        if try_to_consume(_RKLAMMER) then
          begin
            if (tpointerdef(p1.resulttype.def).pointertype.def.deftype=objectdef) and
               (oo_has_vmt in tobjectdef(tpointerdef(p1.resulttype.def).pointertype.def).objectoptions)  then
              Message(parser_w_use_extended_syntax_for_objects);

            { create statements with call to getmem+initialize }
            newblock:=internalstatements(newstatement,true);

            { create temp for result }
            temp := ctempcreatenode.create(p1.resulttype,p1.resulttype.def.size,tt_persistent);
            addstatement(newstatement,temp);

            { create call to fpc_getmem }
            para := ccallparanode.create(cordconstnode.create
                (tpointerdef(p1.resulttype.def).pointertype.def.size,s32bittype,true),nil);
            addstatement(newstatement,cassignmentnode.create(
                ctemprefnode.create(temp),
                ccallnode.createintern('fpc_getmem',para)));

            { create call to fpc_initialize }
            if tpointerdef(p1.resulttype.def).pointertype.def.needs_inittable then
             begin
               para := ccallparanode.create(caddrnode.create(crttinode.create
                          (tstoreddef(tpointerdef(p1.resulttype.def).pointertype.def),initrtti)),
                       ccallparanode.create(ctemprefnode.create
                          (temp),nil));
               addstatement(newstatement,ccallnode.createintern('fpc_initialize',para));
             end;

            { the last statement should return the value as
              location and type, this is done be referencing the
              temp and converting it first from a persistent temp to
              normal temp }
            addstatement(newstatement,ctempdeletenode.create_normal_temp(temp));
            addstatement(newstatement,ctemprefnode.create(temp));

            p1.destroy;
            p1:=newblock;
          end
        else
          begin
            consume(_COMMA);
            if tpointerdef(p1.resulttype.def).pointertype.def.deftype<>objectdef then
             begin
               Message(parser_e_pointer_to_class_expected);
               consume_all_until(_RKLAMMER);
               consume(_RKLAMMER);
               p1.destroy;
               new_function:=cerrornode.create;
               exit;
             end;
            classh:=tobjectdef(tpointerdef(p1.resulttype.def).pointertype.def);
            { use the objectdef for loading the VMT }
            p2:=p1;
            p1:=ctypenode.create(tpointerdef(p1.resulttype.def).pointertype);
            do_resulttypepass(p1);
            { search the constructor also in the symbol tables of
              the parents }
            afterassignment:=false;
            sym:=searchsym_in_class(classh,pattern);
            consume(_ID);
            do_member_read(classh,false,sym,p1,again,[nf_new_call]);
            { we need to know which procedure is called }
            do_resulttypepass(p1);
            if not(
                   (p1.nodetype=calln) and
                   assigned(tcallnode(p1).procdefinition) and
                   (tcallnode(p1).procdefinition.proctypeoption=potype_constructor)
                  ) then
              Message(parser_e_expr_have_to_be_constructor_call);
            { constructors return boolean, update resulttype to return
              the pointer to the object }
            p1.resulttype:=p2.resulttype;
            p2.free;
            consume(_RKLAMMER);
          end;
        new_function:=p1;
      end;


    function inline_setlength : tnode;
      var
        paras   : tnode;
        npara,
        ppn     : tcallparanode;
        counter : integer;
        isarray : boolean;
        def     : tdef;
        destppn : tnode;
        newstatement : tstatementnode;
        temp    : ttempcreatenode;
        newblock : tnode;
      begin
        { for easy exiting if something goes wrong }
        result := cerrornode.create;

        consume(_LKLAMMER);
        paras:=parse_paras(false,false);
        consume(_RKLAMMER);
        if not assigned(paras) then
         begin
           CGMessage(parser_e_wrong_parameter_size);
           exit;
         end;

        counter:=0;
        if assigned(paras) then
         begin
           { check type of lengths }
           ppn:=tcallparanode(paras);
           while assigned(ppn.right) do
            begin
              set_varstate(ppn.left,true);
              inserttypeconv(ppn.left,s32bittype);
              inc(counter);
              ppn:=tcallparanode(ppn.right);
            end;
         end;
        if counter=0 then
         begin
           CGMessage(parser_e_wrong_parameter_size);
           paras.free;
           exit;
         end;
        { last param must be var }
        destppn:=ppn.left;
        inc(parsing_para_level);
        valid_for_var(destppn);
        set_varstate(destppn,false);
        dec(parsing_para_level);
        { first param must be a string or dynamic array ...}
        isarray:=is_dynamic_array(destppn.resulttype.def);
        if not((destppn.resulttype.def.deftype=stringdef) or
               isarray) then
         begin
           CGMessage(type_e_mismatch);
           paras.free;
           exit;
         end;

        { only dynamic arrays accept more dimensions }
        if (counter>1) then
         begin
           if (not isarray) then
            CGMessage(type_e_mismatch)
           else
            begin
              { check if the amount of dimensions is valid }
              def := tarraydef(destppn.resulttype.def).elementtype.def;
              while counter > 1 do
                begin
                  if not(is_dynamic_array(def)) then
                    begin
                      CGMessage(parser_e_wrong_parameter_size);
                      break;
                    end;
                  dec(counter);
                  def := tarraydef(def).elementtype.def;
                end;
            end;
         end;

        if isarray then
         begin
            { create statements with call initialize the arguments and
              call fpc_dynarr_setlength }
            newblock:=internalstatements(newstatement,true);

            { get temp for array of lengths }
            temp := ctempcreatenode.create(s32bittype,counter*s32bittype.def.size,tt_persistent);
            addstatement(newstatement,temp);

            { load array of lengths }
            ppn:=tcallparanode(paras);
            counter:=0;
            while assigned(ppn.right) do
             begin
               addstatement(newstatement,cassignmentnode.create(
                   ctemprefnode.create_offset(temp,counter*s32bittype.def.size),
                   ppn.left));
               ppn.left:=nil;
               inc(counter);
               ppn:=tcallparanode(ppn.right);
             end;
            { destppn is also reused }
            ppn.left:=nil;

            { create call to fpc_dynarr_setlength }
            npara:=ccallparanode.create(caddrnode.create
                      (ctemprefnode.create(temp)),
                   ccallparanode.create(cordconstnode.create
                      (counter,s32bittype,true),
                   ccallparanode.create(caddrnode.create
                      (crttinode.create(tstoreddef(destppn.resulttype.def),initrtti)),
                   ccallparanode.create(ctypeconvnode.create_explicit(destppn,voidpointertype),nil))));
            addstatement(newstatement,ccallnode.createintern('fpc_dynarray_setlength',npara));
            addstatement(newstatement,ctempdeletenode.create(temp));

            { we don't need original the callparanodes tree }
            paras.free;
         end
        else
         begin
            { we can reuse the supplied parameters }
            newblock:=ccallnode.createintern(
               'fpc_'+tstringdef(destppn.resulttype.def).stringtypname+'_setlength',paras);
         end;

        result.free;
        result:=newblock;
      end;


    function inline_finalize : tnode;
      var
        newblock,
        paras   : tnode;
        npara,
        destppn,
        ppn     : tcallparanode;
      begin
        { for easy exiting if something goes wrong }
        result := cerrornode.create;

        consume(_LKLAMMER);
        paras:=parse_paras(false,false);
        consume(_RKLAMMER);
        if not assigned(paras) then
         begin
           CGMessage(parser_e_wrong_parameter_size);
           exit;
         end;

        ppn:=tcallparanode(paras);
        { 2 arguments? }
        if assigned(ppn.right) then
         begin
           destppn:=tcallparanode(ppn.right);
           { 3 arguments is invalid }
           if assigned(destppn.right) then
            begin
              CGMessage(parser_e_wrong_parameter_size);
              paras.free;
              exit;
            end;
           { create call to fpc_finalize_array }
           npara:=ccallparanode.create(cordconstnode.create
                     (destppn.left.resulttype.def.size,s32bittype,true),
                  ccallparanode.create(ctypeconvnode.create
                     (ppn.left,s32bittype),
                  ccallparanode.create(caddrnode.create
                     (crttinode.create(tstoreddef(destppn.left.resulttype.def),initrtti)),
                  ccallparanode.create(caddrnode.create
                     (destppn.left),nil))));
           newblock:=ccallnode.createintern('fpc_finalize_array',npara);
           destppn.left:=nil;
           ppn.left:=nil;
         end
        else
         begin
           newblock:=finalize_data_node(ppn.left);
           ppn.left:=nil;
         end;
        paras.free;
        result.free;
        result:=newblock;
      end;


    function inline_copy : tnode;
      var
        copynode,
        lowppn,
        highppn,
        npara,
        paras   : tnode;
        temp    : ttempcreatenode;
        ppn     : tcallparanode;
        paradef : tdef;
        counter : integer;
        newstatement : tstatementnode;
      begin
        { for easy exiting if something goes wrong }
        result := cerrornode.create;

        consume(_LKLAMMER);
        paras:=parse_paras(false,false);
        consume(_RKLAMMER);
        if not assigned(paras) then
         begin
           CGMessage(parser_e_wrong_parameter_size);
           exit;
         end;

        { determine copy function to use based on the first argument,
          also count the number of arguments in this loop }
        counter:=1;
        ppn:=tcallparanode(paras);
        while assigned(ppn.right) do
         begin
           inc(counter);
           ppn:=tcallparanode(ppn.right);
         end;
        paradef:=ppn.left.resulttype.def;
        if is_ansistring(paradef) or
           (is_chararray(paradef) and
            (paradef.size>255)) or
           ((cs_ansistrings in aktlocalswitches) and
            is_pchar(paradef)) then
          copynode:=ccallnode.createintern('fpc_ansistr_copy',paras)
        else
         if is_widestring(paradef) or
            is_widechararray(paradef) or
            is_pwidechar(paradef) then
           copynode:=ccallnode.createintern('fpc_widestr_copy',paras)
        else
         if is_char(paradef) then
           copynode:=ccallnode.createintern('fpc_char_copy',paras)
        else
         if is_dynamic_array(paradef) then
          begin
            { Only allow 1 or 3 arguments }
            if (counter<>1) and (counter<>3) then
             begin
               CGMessage(parser_e_wrong_parameter_size);
               exit;
             end;

            { create statements with call }
            copynode:=internalstatements(newstatement,true);

            if (counter=3) then
             begin
               highppn:=tcallparanode(paras).left.getcopy;
               lowppn:=tcallparanode(tcallparanode(paras).right).left.getcopy;
             end
            else
             begin
               { use special -1,-1 argument to copy the whole array }
               highppn:=cordconstnode.create(-1,s32bittype,false);
               lowppn:=cordconstnode.create(-1,s32bittype,false);
             end;

            { create temp for result, we've to use a temp because a dynarray
              type is handled differently from a pointer so we can't
              use createinternres() and a function }
            temp := ctempcreatenode.create(voidpointertype,voidpointertype.def.size,tt_persistent);
            addstatement(newstatement,temp);

            { create call to fpc_dynarray_copy }
            npara:=ccallparanode.create(highppn,
                   ccallparanode.create(lowppn,
                   ccallparanode.create(caddrnode.create
                      (crttinode.create(tstoreddef(ppn.left.resulttype.def),initrtti)),
                   ccallparanode.create
                      (ctypeconvnode.create_explicit(ppn.left,voidpointertype),
                   ccallparanode.create
                      (ctemprefnode.create(temp),nil)))));
            addstatement(newstatement,ccallnode.createintern('fpc_dynarray_copy',npara));

            { convert the temp to normal and return the reference to the
              created temp, and convert the type of the temp to the dynarray type }
            addstatement(newstatement,ctempdeletenode.create_normal_temp(temp));
            addstatement(newstatement,ctypeconvnode.create_explicit(ctemprefnode.create(temp),ppn.left.resulttype));

            ppn.left:=nil;
            paras.free;
          end
        else
         begin
           { generic fallback that will give an error if a wrong
             type is passed }
           copynode:=ccallnode.createintern('fpc_shortstr_copy',paras)
         end;

        result.free;
        result:=copynode;
      end;

end.
{
  $Log$
  Revision 1.20  2003-10-02 21:15:31  peter
    * protected visibility fixes

  Revision 1.19  2003/10/01 20:34:49  peter
    * procinfo unit contains tprocinfo
    * cginfo renamed to cgbase
    * moved cgmessage to verbose
    * fixed ppc and sparc compiles

  Revision 1.18  2003/09/23 17:56:05  peter
    * locals and paras are allocated in the code generation
    * tvarsym.localloc contains the location of para/local when
      generating code for the current procedure

  Revision 1.17  2003/08/21 15:10:51  peter
    * fixed copy support for array of char,pchar in $H+ mode
    * fixed copy support for pwidechar,array of widechar

  Revision 1.16  2003/08/10 17:25:23  peter
    * fixed some reported bugs

  Revision 1.15  2003/05/17 13:30:08  jonas
    * changed tt_persistant to tt_persistent :)
    * tempcreatenode now doesn't accept a boolean anymore for persistent
      temps, but a ttemptype, so you can also create ansistring temps etc

  Revision 1.14  2003/05/16 14:33:31  peter
    * regvar fixes

  Revision 1.13  2003/05/09 17:47:03  peter
    * self moved to hidden parameter
    * removed hdisposen,hnewn,selfn

  Revision 1.12  2002/04/25 20:15:40  florian
    * block nodes within expressions shouldn't release the used registers,
      fixed using a flag till the new rg is ready

  Revision 1.11  2002/11/26 22:59:09  peter
    * fix Copy(array,x,y)

  Revision 1.10  2002/11/25 17:43:22  peter
    * splitted defbase in defutil,symutil,defcmp
    * merged isconvertable and is_equal into compare_defs(_ext)
    * made operator search faster by walking the list only once

  Revision 1.9  2002/10/29 10:01:22  pierre
   * fix crash report as webbug 2174

  Revision 1.8  2002/10/02 18:20:52  peter
    * Copy() is now internal syssym that calls compilerprocs

  Revision 1.7  2002/09/07 12:16:03  carl
    * second part bug report 1996 fix, testrange in cordconstnode
      only called if option is set (also make parsing a tiny faster)

  Revision 1.6  2002/07/20 11:57:56  florian
    * types.pas renamed to defbase.pas because D6 contains a types
      unit so this would conflicts if D6 programms are compiled
    + Willamette/SSE2 instructions to assembler added

  Revision 1.5  2002/05/18 13:34:12  peter
    * readded missing revisions

  Revision 1.4  2002/05/16 19:46:43  carl
  + defines.inc -> fpcdefs.inc to avoid conflicts if compiling by hand
  + try to fix temp allocation (still in ifdef)
  + generic constructor calls
  + start of tassembler / tmodulebase class cleanup

  Revision 1.2  2002/05/12 16:53:09  peter
    * moved entry and exitcode to ncgutil and cgobj
    * foreach gets extra argument for passing local data to the
      iterator function
    * -CR checks also class typecasts at runtime by changing them
      into as
    * fixed compiler to cycle with the -CR option
    * fixed stabs with elf writer, finally the global variables can
      be watched
    * removed a lot of routines from cga unit and replaced them by
      calls to cgobj
    * u32bit-s32bit updates for and,or,xor nodes. When one element is
      u32bit then the other is typecasted also to u32bit without giving
      a rangecheck warning/error.
    * fixed pascal calling method with reversing also the high tree in
      the parast, detected by tcalcst3 test

  Revision 1.1  2002/04/23 19:16:35  peter
    * add pinline unit that inserts compiler supported functions using
      one or more statements
    * moved finalize and setlength from ninl to pinline

}
