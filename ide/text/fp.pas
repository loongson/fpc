{
    $Id$
    This file is part of the Free Pascal Integrated Development Environment
    Copyright (c) 1998 by Berczi Gabor

    Main program of the IDE

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
program FP;

uses
{$ifdef IDEHeapTrc}
  HeapTrc,
{$endif IDEHeapTrc}
  Dos,
  BrowCol,
  FPIni,FPViews,FPConst,FPVars,FPUtils,FPIde,FPHelp,FPSwitch,FPUsrScr,
  FPTools,FPDebug,FPTemplt,FPCatch;


procedure ProcessParams(BeforeINI: boolean);

  function IsSwitch(const Param: string): boolean;
  begin
    IsSwitch:=(Param<>'') and (Param[1]<>DirSep) { <- allow UNIX root-relative paths            }
          and (Param[1] in ['-','/']);           { <- but still accept dos switch char, eg. '/' }
  end;

var I: integer;
    Param: string;
begin
  for I:=1 to ParamCount do
  begin
    Param:=ParamStr(I);
    if IsSwitch(Param) then
      begin
        Param:=copy(Param,2,255);
        if Param<>'' then
        case Upcase(Param[1]) of
          'C' : { custom config file (BP compatiblity) }
           if BeforeINI then
            INIPath:=copy(Param,2,255);
          'R' : { enter the directory last exited from (BP comp.) }
            begin
              Param:=copy(Param,2,255);
              if (Param='') or (Param='+') then
                StartupOptions:=StartupOptions or soReturnToLastDir
              else
              if (Param='-') then
                StartupOptions:=StartupOptions and (not soReturnToLastDir);
            end;
        end;
      end
    else
      if not BeforeINI then
        MyApp.Open(Param);
  end;
end;


BEGIN
  {$ifdef DEV}HeapLimit:=4096;{$endif}
  writeln('� Free Pascal IDE  Version '+VersionStr);
  StartupDir:=CompleteDir(FExpand('.'));

  ProcessParams(true);

  InitBreakpoints;
  InitReservedWords;
  InitHelpFiles;
  InitSwitches;
  InitINIFile;
  InitUserScreen;
  InitTools;
  InitTemplates;

{ load old options }
  ReadINIFile;
  ReadSwitches(SwitchesPath);

  MyApp.Init;

  ProcessParams(false);

  MyApp.Run;
  MyApp.Done;

  WriteSwitches(SwitchesPath);
  WriteINIFile;

  DoneTemplates;
  DoneTools;
  DoneUserScreen;
  DoneSwitches;
  DoneHelpFiles;
  DoneReservedWords;
  DoneBrowserCol;
  DoneDebugger;
  DoneBreakpoints;
END.
{
  $Log$
  Revision 1.12  1999-02-20 15:18:25  peter
    + ctrl-c capture with confirm dialog
    + ascii table in the tools menu
    + heapviewer
    * empty file fixed
    * fixed callback routines in fpdebug to have far for tp7

  Revision 1.11  1999/02/18 13:44:30  peter
    * search fixed
    + backward search
    * help fixes
    * browser updates

  Revision 1.10  1999/02/15 09:07:10  pierre
   * HEAPTRC conditionnal renamed IDEHEAPTRC

  Revision 1.9  1999/02/10 09:55:43  pierre
     + Memory tracing if compiled with -dHEAPTRC
     * Many memory leaks removed

  Revision 1.8  1999/02/08 09:30:59  florian
    + some split heap stuff, in $ifdef TEMPHEAP

  Revision 1.7  1999/02/05 13:51:38  peter
    * unit name of FPSwitches -> FPSwitch which is easier to use
    * some fixes for tp7 compiling

  Revision 1.6  1999/01/21 11:54:10  peter
    + tools menu
    + speedsearch in symbolbrowser
    * working run command

  Revision 1.5  1999/01/12 14:29:31  peter
    + Implemented still missing 'switch' entries in Options menu
    + Pressing Ctrl-B sets ASCII mode in editor, after which keypresses (even
      ones with ASCII < 32 ; entered with Alt+<###>) are interpreted always as
      ASCII chars and inserted directly in the text.
    + Added symbol browser
    * splitted fp.pas to fpide.pas

}
