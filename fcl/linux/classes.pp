{
    $Id$
    This file is part of the Free Component Library (FCL)
    Copyright (c) 1999-2000 by Michael Van Canneyt and Florian Klaempfl

    Classes unit for linux

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{$mode objfpc}

{ determine the type of the resource/form file }
{$define Win16Res}

unit Classes;

interface

uses
  sysutils,
  typinfo;

{$i classesh.inc}

implementation

uses
  linux;

var
ClassList : TThreadlist;
ClassAliasList : TStringList;
{ OS - independent class implementations are in /inc directory. }
{$i classes.inc}


initialization
  ClassList := TThreadList.Create;
  ClassAliasList := TStringList.Create;

finalization
  ClassList.Free;
  ClassAliasList.Free;

  if ThreadsInited then
     DoneThreads;

end.
{
  $Log$
  Revision 1.17  2000-06-27 17:17:34  lazarus
  Added code for registerclass, GetClass and RegisterClasses
  Shane

  Revision 1.16  2000/06/27 15:55:19  lazarus
  Added TThreadlist code.   Shane

  Revision 1.15  2000/01/07 01:24:34  peter
    * updated copyright to 2000

  Revision 1.14  2000/01/07 00:01:33  peter
    * uses typinfo moved to interface

  Revision 1.13  2000/01/06 01:20:33  peter
    * moved out of packages/ back to topdir

  Revision 1.2  2000/01/04 18:07:58  michael
  + Added typinfo unit

  Revision 1.1  2000/01/03 19:33:09  peter
    * moved to packages dir

  Revision 1.11  1999/05/30 10:46:41  peter
    * start of tthread for linux,win32

}
