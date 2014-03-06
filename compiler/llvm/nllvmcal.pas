{
    Copyright (c) 2014 by Jonas Maebe

    Generate LLVM bytecode for call nodes

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
unit nllvmcal;

{$mode objfpc}

interface

    uses
      ncgcal;

    type
      tllvmcallnode = class(tcgcallnode)
       protected
        procedure pushparas; override;
      end;


implementation

     uses
       verbose,
       ncal;

{ tllvmcallnode }

    procedure tllvmcallnode.pushparas;
      var
        n: tcgcallparanode;
        paraindex: longint;
      begin
        { we just pass the temp paralocs here }
        setlength(paralocs,procdefinition.paras.count);
        n:=tcgcallparanode(left);
        while assigned(n) do
          begin
            { TODO: check whether this is correct for left-to-right calling
              conventions, may also depend on whether or not llvm knows about
              the calling convention }
            paraindex:=procdefinition.paras.indexof(n.parasym);
            if paraindex=-1 then
             internalerror(2014010602);
            paralocs[paraindex]:=@n.tempcgpara;
            n:=tcgcallparanode(n.right);
         end;
      end;

begin
  ccallnode:=tllvmcallnode;
end.

