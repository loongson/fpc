{
    $Id$
    Copyright (c) 1998-2000 by Jonas Maebe, member of the Free Pascal
    Development Team

    This unit contains the processor specific implementation of the
    assembler optimizer data flow analyzer.

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
Unit aoptcpud;

Interface

uses
  AOptDA;

Type
  PAOptDFACpu = ^TAOptDFACpu;
  TAOptDFACpu = Object(TAOptDFA)
  End;

Implementation


End.

{
  $Log$
  Revision 1.2  2002-09-07 15:25:10  peter
    * old logs removed and tabs fixed

  Revision 1.1  2002/08/18 09:06:54  florian
    * alpha files moved compiler/alpha

}
