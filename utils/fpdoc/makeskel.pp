{
    $Id$

    FPDoc  -  Free Pascal Documentation Tool
    Copyright (C) 2000 - 2003 by
      Areca Systems GmbH / Sebastian Guenther, sg@freepascal.org

    * Skeleton XML description file generator

    See the file COPYING, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
}


program MakeSkel;

uses
  SysUtils, Classes, Gettext,
  dGlobals, PasTree, PParser,PScanner;

resourcestring
  STitle = 'MakeSkel - FPDoc skeleton XML description file generator';
  SCopyright = '(c) 2000 - 2003 Areca Systems GmbH / Sebastian Guenther, sg@freepascal.org';
  SCmdLineHelp = 'See documentation for usage.';
  SCmdLineInvalidOption = 'Ignoring unknown option "%s"';
  SNoPackageNameProvided = 'Please specify a package name with --package=<name>';
  SDone = 'Done.';

type
  TCmdLineAction = (actionHelp, actionConvert);

  TSkelEngine = class(TFPDocEngine)
  public
    function CreateElement(AClass: TPTreeElement; const AName: String;
      AParent: TPasElement; AVisibility :TPasMemberVisibility;
      const ASourceFilename: String; ASourceLinenumber: Integer): TPasElement; override;
  end;

const
  CmdLineAction: TCmdLineAction = actionConvert;
  OSTarget: String = {$I %FPCTARGETOS%};
  CPUTarget: String = {$I %FPCTARGETCPU%};

var
  InputFiles, DescrFiles: TStringList;
  DocLang: String;
  Engine: TSkelEngine;
  UpdateMode,
  DisableErrors,
  DisableSeealso,
  DisableArguments,
  DisableProtected,
  DisablePrivate,
  DisableFunctionResults: Boolean;
  
  EmitClassSeparator: Boolean;
  PackageName, OutputName: String;
  f: Text;


function TSkelEngine.CreateElement(AClass: TPTreeElement; const AName: String;
  AParent: TPasElement; AVisibility : TPasMemberVisibility;
  const ASourceFilename: String; ASourceLinenumber: Integer): TPasElement;
  
  Function WriteThisNode(APasElement : TPasElement)  : Boolean;
  
  begin
    Result:=Assigned(AParent) and (Length(AName) > 0) and
            (not DisableArguments or (APasElement.ClassType <> TPasArgument)) and
            (not DisableFunctionResults or (APasElement.ClassType <> TPasResultElement)) and
            (not DisablePrivate or (AVisibility<>visPrivate)) and
            (not DisableProtected or (AVisibility<>visProtected));
    If Result and updateMode then
      begin        
      Result:=FindDocNode(APasElement)=Nil;
      If Result then
        Writeln(stderr,'Creating documentation for new node ',APasElement.PathName);
      end;
  end;
  
begin
  Result := AClass.Create(AName, AParent);
  if AClass.InheritsFrom(TPasModule) then
    CurModule := TPasModule(Result);
  if Result.ClassType = TPasModule then
    begin
    WriteLn(f);
    WriteLn(f, '<!--');
    WriteLn(f, '  ====================================================================');
    WriteLn(f, '    ', Result.Name);
    WriteLn(f, '  ====================================================================');
    WriteLn(f, '-->');
    WriteLn(f);
    WriteLn(f, '<module name="', Result.Name, '">');
    WriteLn(f, '<short></short>');
    WriteLn(f, '<descr>');
    WriteLn(f, '</descr>');
    end 
  else if WriteThisNode(Result) then
    begin
    WriteLn(f);
    if EmitClassSeparator and (Result.ClassType = TPasClassType) then
      begin
      WriteLn(f, '<!--');
      WriteLn(f, '  ********************************************************************');
      WriteLn(f, '    ', Result.PathName);
      WriteLn(f, '  ********************************************************************');
      WriteLn(f, '-->');
      WriteLn(f);
      end;
    Writeln(F,'<!-- ', Result.ElementTypeName,' Visibility: ',VisibilityNames[AVisibility], ' -->');
    WriteLn(f,'<element name="', Result.FullName, '">');
    WriteLn(f, '<short></short>');
    WriteLn(f, '<descr>');
    WriteLn(f, '</descr>');
    if not DisableErrors then
      begin
      WriteLn(f, '<errors>');
      WriteLn(f, '</errors>');
      end;
    if not DisableSeealso then
      begin
      WriteLn(f, '<seealso>');
      WriteLn(f, '</seealso>');
      end;
    WriteLn(f, '</element>');
    end;
end;


procedure InitOptions;
begin
  InputFiles := TStringList.Create;
  DescrFiles := TStringList.Create;
end;

procedure FreeOptions;
begin
  DescrFiles.Free;
  InputFiles.Free;
end;

procedure ParseOption(const s: String);

  procedure AddToFileList(List: TStringList; const FileName: String);
  var
    f: Text;
    s: String;
  begin
    if Copy(FileName, 1, 1) = '@' then
    begin
      Assign(f, Copy(FileName, 2, Length(FileName)));
      Reset(f);
      while not EOF(f) do
      begin
        ReadLn(f, s);
	List.Add(s);
      end;
      Close(f);
    end else
      List.Add(FileName);
  end;

var
  i: Integer;
  Cmd, Arg: String;
begin
  if (s = '-h') or (s = '--help') then
    CmdLineAction := actionHelp
  else if s = '--update' then
    UpdateMode := True
  else if s = '--disable-arguments' then
    DisableArguments := True
  else if s = '--disable-errors' then
    DisableErrors := True
  else if s = '--disable-function-results' then
    DisableFunctionResults := True
  else if s = '--disable-seealso' then
    DisableSeealso := True
  else if s = '--disable-private' then
    DisablePrivate := True
  else if s = '--disable-protected' then
    begin
    DisableProtected := True;
    DisablePrivate :=True;
    end
  else if s = '--emitclassseparator' then
    EmitClassSeparator := True
  else
  begin
    i := Pos('=', s);
    if i > 0 then
    begin
      Cmd := Copy(s, 1, i - 1);
      Arg := Copy(s, i + 1, Length(s));
    end else
    begin
      Cmd := s;
      SetLength(Arg, 0);
    end;
    if (Cmd = '-i') or (Cmd = '--input') then
      AddToFileList(InputFiles, Arg)
    else if (Cmd = '-l') or (Cmd = '--lang') then
      DocLang := Arg
    else if (Cmd = '-o') or (Cmd = '--output') then
      OutputName := Arg
    else if Cmd = '--package' then
      PackageName := Arg
    else if Cmd = '--descr' then
      begin
      if FileExists(Arg) then
        DescrFiles.Add(Arg);
      end
    else
      WriteLn(StdErr, Format(SCmdLineInvalidOption, [s]));
  end;
end;

procedure ParseCommandLine;

Const
{$IFDEF Unix}
  MoFileTemplate = '/usr/local/share/locale/%s/LC_MESSAGES/makeskel.mo';
{$ELSE}
  MoFileTemplate ='intl/makeskel.%s.mo';
{$ENDIF}

var
  MOFilename: string;
  i: Integer;
begin
  DocLang:='';
  for i := 1 to ParamCount do
    ParseOption(ParamStr(i));
  If (DocLang<>'') then
    begin
    MOFilename:=Format(MOFileTemplate,[DocLang]);
    if FileExists(MOFilename) then
      gettext.TranslateResourceStrings(MoFileName)
    else
      writeln('NOTE: unable to find tranlation file ',MOFilename);
    // Translate internal documentation strings
    TranslateDocStrings(DocLang);
    end;  
end;



var
  i: Integer;
  Module: TPasModule;
  
begin
  InitOptions;
  ParseCommandLine;
  WriteLn(STitle);
  WriteLn(SCopyright);
  WriteLn;
  if CmdLineAction = actionHelp then
    WriteLn(SCmdLineHelp)
  else
  begin
    // Action is to create the XML skeleton

    if Length(PackageName) = 0 then
    begin
      WriteLn(SNoPackageNameProvided);
      Halt(2);
    end;

    Assign(f, OutputName);
    Rewrite(f);

    WriteLn(f, '<?xml version="1.0" encoding="ISO8859-1"?>');
    WriteLn(f, '<fpdoc-descriptions>');
    WriteLn(f, '<package name="', PackageName, '">');

    // Process all source files
    for i := 0 to InputFiles.Count - 1 do
    begin
      Engine := TSkelEngine.Create;
      try
       try
         Engine.SetPackageName(PackageName);
         if UpdateMode then
           For I:=0 to DescrFiles.Count-1 do
             Engine.AddDocFile(DescrFiles[i]);
         Module := ParseSource(Engine, InputFiles[i], OSTarget, CPUTarget);
   	 WriteLn(f, '</module> <!-- ', Module.Name, ' -->');
       except
        on e:EFileNotFoundError do
           begin
    	     Writeln(StdErr,' file ', e.message, ' not found');
	     close(f);	
	     Halt(1);
           end; 
         end;
      finally
        Engine.Free; 
       end;
    end;

    WriteLn(f, '</package>');
    WriteLn(f, '</fpdoc-descriptions>');

    Close(f);
  end;

  FreeOptions;

  WriteLn(SDone);
end.


{
  $Log$
  Revision 1.9  2004-08-28 18:04:06  michael
  + Added update mode

  Revision 1.8  2004/08/25 07:16:43  michael
  + Improved translation handling

  Revision 1.7  2004/08/24 14:48:25  michael
  + Translate now called correctly...

  Revision 1.6  2004/05/01 20:13:40  marco
   * got fed up with exceptions on file not found.  Fileresolver now raises a
  	EFileNotFound error, and makeskel catches and exists gracefully

  Revision 1.5  2003/11/28 12:51:37  sg
  * Added support for source references

  Revision 1.4  2003/09/02 13:26:47  mattias
  MG: makeskel now ignores missing translation file

  Revision 1.3  2003/05/07 16:31:32  sg
  * Fixed a severe memory corruption problem on termination

  Revision 1.2  2003/03/28 13:01:36  michael
  + Patch from Charlie/iNQ to work with new scanner/parser

  Revision 1.1  2003/03/17 23:03:20  michael
  + Initial import in CVS
}