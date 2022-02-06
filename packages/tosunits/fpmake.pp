{$ifndef ALLPACKAGES}
{$mode objfpc}{$H+}
program fpmake;

uses fpmkunit;

Var
  P : TPackage;
  T : TTarget;
begin
  With Installer do
    begin
{$endif ALLPACKAGES}

    P:=AddPackage('tosunits');
    P.ShortName := 'tos';

    P.Author := 'FPC core team';
    P.License := 'LGPL with modification';
    P.HomepageURL := 'www.freepascal.org';
    P.Description := 'tosunits, OS interface units for Atari TOS/GEM';

{$ifdef ALLPACKAGES}
    P.Directory:=ADirectory;
{$endif ALLPACKAGES}
    P.Version:='3.3.1';
    P.SourcePath.Add('src');

    P.OSes:=[atari];

    T:=P.Targets.AddUnit('gemdos.pas');
    T:=P.Targets.AddUnit('xbios.pas');
    T:=P.Targets.AddUnit('bios.pas');
    T:=P.Targets.AddUnit('tos.pas');
    T:=P.Targets.AddUnit('vdi.pas');
    T:=P.Targets.AddUnit('aes.pas');
    T:=P.Targets.AddUnit('gem.pas');
    T:=P.Targets.AddUnit('gemcommon.pas');

    P.ExamplePath.Add('examples');
    T:=P.Targets.AddExampleProgram('higem.pas');
    T:=P.Targets.AddExampleProgram('gemwin.pas');
    T:=P.Targets.AddExampleProgram('gemcube.pas');
    T:=P.Targets.AddExampleProgram('showpic.pas');

{$ifndef ALLPACKAGES}
    Run;
    end;
end.
{$endif ALLPACKAGES}
