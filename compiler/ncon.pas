{
    $Id$
    Copyright (c) 2000 by Florian Klaempfl

    Type checking and register allocation for constants

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
unit ncon;

{$i defines.inc}

interface

    uses
      globtype,node,aasm,cpuinfo,symconst,symtable;

    type
       trealconstnode = class(tnode)
          value_real : bestreal;
          lab_real : pasmlabel;
          constructor create(v : bestreal;def : pdef);virtual;
          function getcopy : tnode;override;
          function pass_1 : tnode;override;
       end;

       tfixconstnode = class(tnode)
          value_fix: longint;
          constructor create(v : longint;def : pdef);virtual;
          function getcopy : tnode;override;
          function pass_1 : tnode;override;
       end;

       tordconstnode = class(tnode)
          value : TConstExprInt;
          constructor create(v : tconstexprint;def : pdef);virtual;
          function getcopy : tnode;override;
          function pass_1 : tnode;override;
       end;

       tpointerconstnode = class(tnode)
          value : TPointerOrd;
          constructor create(v : tpointerord;def : pdef);virtual;
          function getcopy : tnode;override;
          function pass_1 : tnode;override;
       end;

       tstringconstnode = class(tnode)
          value_str : pchar;
          len : longint;
          lab_str : pasmlabel;
          stringtype : tstringtype;
          constructor createstr(const s : string;st:tstringtype);virtual;
          constructor createpchar(s : pchar;l : longint);virtual;
          function getcopy : tnode;override;
          function pass_1 : tnode;override;
          function getpcharcopy : pchar;
       end;

       tsetconstnode = class(tunarynode)
          value_set : pconstset;
          lab_set : pasmlabel;
          constructor create(s : pconstset;settype : psetdef);virtual;
          function getcopy : tnode;override;
          function pass_1 : tnode;override;
       end;

       tnilnode = class(tnode)
          constructor create;virtual;
          function pass_1 : tnode;override;
       end;

    var
       crealconstnode : class of trealconstnode;
       cfixconstnode : class of tfixconstnode;
       cordconstnode : class of tordconstnode;
       cpointerconstnode : class of tpointerconstnode;
       cstringconstnode : class of tstringconstnode;
       csetconstnode : class of tsetconstnode;
       cnilnode : class of tnilnode;

    function genordinalconstnode(v : TConstExprInt;def : pdef) : tordconstnode;
    { same as genordinalconstnode, but the resulttype }
    { is determines automatically                     }
    function genintconstnode(v : TConstExprInt) : tordconstnode;
    function genpointerconstnode(v : tpointerord;def : pdef) : tpointerconstnode;
    function genenumnode(v : penumsym) : tordconstnode;
    function genfixconstnode(v : longint;def : pdef) : tfixconstnode;
    function genrealconstnode(v : bestreal;def : pdef) : trealconstnode;
    { allow pchar or string for defining a pchar node }
    function genstringconstnode(const s : string;st:tstringtype) : tstringconstnode;
    { length is required for ansistrings }
    function genpcharconstnode(s : pchar;length : longint) : tstringconstnode;

    function gensetconstnode(s : pconstset;settype : psetdef) : tsetconstnode;

implementation

    uses
      cobjects,verbose,globals,systems,
      types,hcodegen,pass_1,cpubase;

    function genordinalconstnode(v : tconstexprint;def : pdef) : tordconstnode;
      begin
         genordinalconstnode:=cordconstnode.create(v,def);
      end;

    function genintconstnode(v : TConstExprInt) : tordconstnode;

      var
         i : TConstExprInt;

      begin
         { we need to bootstrap this code, so it's a little bit messy }
         i:=2147483647;
         if (v<=i) and (v>=-i-1) then
           genintconstnode:=genordinalconstnode(v,s32bitdef)
         else
           genintconstnode:=genordinalconstnode(v,cs64bitdef);
      end;

    function genpointerconstnode(v : tpointerord;def : pdef) : tpointerconstnode;
      begin
         genpointerconstnode:=cpointerconstnode.create(v,def);
      end;

    function genenumnode(v : penumsym) : tordconstnode;
      begin
         genenumnode:=cordconstnode.create(v^.value,v^.definition);
      end;

    function gensetconstnode(s : pconstset;settype : psetdef) : tsetconstnode;
      begin
         gensetconstnode:=csetconstnode.create(s,settype);
      end;

    function genrealconstnode(v : bestreal;def : pdef) : trealconstnode;
      begin
         genrealconstnode:=crealconstnode.create(v,def);
      end;

    function genfixconstnode(v : longint;def : pdef) : tfixconstnode;
      begin
         genfixconstnode:=cfixconstnode.create(v,def);
      end;

    function genstringconstnode(const s : string;st:tstringtype) : tstringconstnode;
      begin
         genstringconstnode:=cstringconstnode.createstr(s,st);
      end;

    function genpcharconstnode(s : pchar;length : longint) : tstringconstnode;
      begin
         genpcharconstnode:=cstringconstnode.createpchar(s,length);
      end;

{*****************************************************************************
                             TREALCONSTNODE
*****************************************************************************}

    constructor trealconstnode.create(v : bestreal;def : pdef);

      begin
         inherited create(realconstn);
         resulttype:=def;
         value_real:=v;
         lab_real:=nil;
      end;

    function trealconstnode.getcopy : tnode;

      var
         n : trealconstnode;

      begin
         n:=trealconstnode(inherited getcopy);
         n.value_real:=value_real;
         n.lab_real:=lab_real;
         getcopy:=n;
      end;

    function trealconstnode.pass_1 : tnode;
      begin
         pass_1:=nil;
         if (value_real=1.0) or (value_real=0.0) then
           begin
              location.loc:=LOC_FPU;
              registersfpu:=1;
           end
         else
           location.loc:=LOC_MEM;
      end;


{*****************************************************************************
                             TFIXCONSTNODE
*****************************************************************************}

    constructor tfixconstnode.create(v : longint;def : pdef);

      begin
         inherited create(fixconstn);
         resulttype:=def;
         value_fix:=v;
      end;

    function tfixconstnode.getcopy : tnode;

      var
         n : tfixconstnode;

      begin
         n:=tfixconstnode(inherited getcopy);
         n.value_fix:=value_fix;
         getcopy:=n;
      end;

    function tfixconstnode.pass_1 : tnode;

      begin
         pass_1:=nil;
         location.loc:=LOC_MEM;
      end;


{*****************************************************************************
                              TORDCONSTNODE
*****************************************************************************}

    constructor tordconstnode.create(v : tconstexprint;def : pdef);

      begin
         inherited create(ordconstn);
         value:=v;
         resulttype:=def;
{$ifdef NEWST}
         if typeof(resulttype^)=typeof(Torddef) then
          testrange(resulttype,value);
{$else NEWST}
         if resulttype^.deftype=orddef then
          testrange(resulttype,value);
{$endif ELSE}
      end;

    function tordconstnode.getcopy : tnode;

      var
         n : tordconstnode;

      begin
         n:=tordconstnode(inherited getcopy);
         n.value:=value;
         getcopy:=n;
      end;

    function tordconstnode.pass_1 : tnode;
      begin
         pass_1:=nil;
         location.loc:=LOC_MEM;
      end;


{*****************************************************************************
                            TPOINTERCONSTNODE
*****************************************************************************}

    constructor tpointerconstnode.create(v : tpointerord;def : pdef);

      begin
         inherited create(pointerconstn);
         value:=v;
         resulttype:=def;
      end;

    function tpointerconstnode.getcopy : tnode;

      var
         n : tpointerconstnode;

      begin
         n:=tpointerconstnode(inherited getcopy);
         n.value:=value;
         getcopy:=n;
      end;

    function tpointerconstnode.pass_1 : tnode;
      begin
         pass_1:=nil;
         location.loc:=LOC_MEM;
      end;


{*****************************************************************************
                             TSTRINGCONSTNODE
*****************************************************************************}

    constructor tstringconstnode.createstr(const s : string;st:tstringtype);

      var
         l : longint;

      begin
         inherited create(stringconstn);
         l:=length(s);
         len:=l;
         { stringdup write even past a #0 }
         getmem(value_str,l+1);
         move(s[1],value_str^,l);
         value_str[l]:=#0;
         lab_str:=nil;
         if st=st_default then
          begin
            if cs_ansistrings in aktlocalswitches then
              stringtype:=st_ansistring
            else
              stringtype:=st_shortstring;
          end
         else
          stringtype:=st;
         case stringtype of
           st_shortstring :
             resulttype:=cshortstringdef;
           st_ansistring :
             resulttype:=cansistringdef;
           else
             internalerror(44990099);
         end;
      end;

    constructor tstringconstnode.createpchar(s : pchar;l : longint);

      begin
         inherited create(stringconstn);
         len:=l;
         if (cs_ansistrings in aktlocalswitches) or
            (len>255) then
          begin
             stringtype:=st_ansistring;
             resulttype:=cansistringdef;
          end
         else
          begin
             stringtype:=st_shortstring;
             resulttype:=cshortstringdef;
          end;
         value_str:=s;
         lab_str:=nil;
      end;

    function tstringconstnode.getcopy : tnode;

      var
         n : tstringconstnode;

      begin
         n:=tstringconstnode(inherited getcopy);
         n.stringtype:=stringtype;
         n.len:=len;
         n.value_str:=getpcharcopy;
         n.lab_str:=lab_str;
      end;

    function tstringconstnode.pass_1 : tnode;
      begin
         pass_1:=nil;
{        if cs_ansistrings in aktlocalswitches then
          resulttype:=cansistringdef
         else
          resulttype:=cshortstringdef; }
        case stringtype of
          st_shortstring :
            resulttype:=cshortstringdef;
          st_ansistring :
            resulttype:=cansistringdef;
          st_widestring :
            resulttype:=cwidestringdef;
          st_longstring :
            resulttype:=clongstringdef;
        end;
        location.loc:=LOC_MEM;
      end;

    function tstringconstnode.getpcharcopy : pchar;
      var
         pc : pchar;
      begin
         pc:=nil;
         getmem(pc,len+1);
         if pc=nil then
           Message(general_f_no_memory_left);
         move(value_str^,pc^,len+1);
         getpcharcopy:=pc;
      end;


{*****************************************************************************
                             TSETCONSTNODE
*****************************************************************************}

    constructor tsetconstnode.create(s : pconstset;settype : psetdef);

      begin
         inherited create(setconstn,nil);
         resulttype:=settype;
         new(value_set);
         value_set^:=s^;
      end;

    function tsetconstnode.getcopy : tnode;

      var
         n : tsetconstnode;

      begin
         n:=tsetconstnode(inherited getcopy);
         new(n.value_set);
         n.value_set^:=value_set^;
         n.lab_set:=lab_set;
         getcopy:=n;
      end;

    function tsetconstnode.pass_1 : tnode;
      begin
         pass_1:=nil;
         location.loc:=LOC_MEM;
      end;

{*****************************************************************************
                               TNILNODE
*****************************************************************************}

    constructor tnilnode.create;

      begin
         inherited create(niln);
      end;

    function tnilnode.pass_1 : tnode;
      begin
        pass_1:=nil;
        resulttype:=voidpointerdef;
        location.loc:=LOC_MEM;
      end;

begin
   crealconstnode:=trealconstnode;
   cfixconstnode:=tfixconstnode;
   cordconstnode:=tordconstnode;
   cpointerconstnode:=tpointerconstnode;
   cstringconstnode:=tstringconstnode;
   csetconstnode:=tsetconstnode;
   cnilnode:=tnilnode;
end.
{
  $Log$
  Revision 1.4  2000-09-26 14:59:34  florian
    * more conversion work done

  Revision 1.3  2000/09/24 21:15:34  florian
    * some errors fix to get more stuff compilable

  Revision 1.2  2000/09/24 15:06:19  peter
    * use defines.inc

  Revision 1.1  2000/09/22 21:44:48  florian
    + initial revision

}