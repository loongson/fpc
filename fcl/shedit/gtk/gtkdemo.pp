{
    $Id$

    GTK (demo) implementation for shedit
    Copyright (C) 1999-2000 by Sebastian Guenther (sg@freepascal.org)

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
}

{$MODE objfpc}
{$H+}

program GTKDemo;
uses
  SysUtils, Classes,
  Doc_text, shedit, sh_pas, sh_xml,
  GDK, GTK, GtkSHEdit;


function CreateTextEditWidget(ADoc: TTextDoc): TGtkSHWidget;
begin
  Result := TGtkSHWidget.Create(ADoc, TSHTextEdit);
end;

function CreatePasEditWidget(ADoc: TTextDoc): TGtkSHWidget;
var
  e: TSHPasEdit;
begin
  Result := TGtkSHWidget.Create(ADoc, TSHPasEdit);
  e := Result.Edit as TSHPasEdit;

  e.shSymbol     := Result.AddSHStyle('Symbol',        colBrown,       colDefault, fsNormal);
  e.shKeyword    := Result.AddSHStyle('Keyword',       colBlack,       colDefault, fsBold);
  e.shComment    := Result.AddSHStyle('Comment',       colDarkCyan,    colDefault, fsItalics);
  e.shDirective  := Result.AddSHStyle('Directive',     colRed,         colDefault, fsItalics);
  e.shNumbers    := Result.AddSHStyle('Numbers',       colDarkMagenta, colDefault, fsNormal);
  e.shCharacters := Result.AddSHStyle('Characters',    colDarkBlue,    colDefault, fsNormal);
  e.shStrings    := Result.AddSHStyle('Strings',       colBlue,        colDefault, fsNormal);
  e.shAssembler  := Result.AddSHStyle('Assembler',     colDarkGreen,   colDefault, fsNormal);
end;

function CreateXMLEditWidget(ADoc: TTextDoc): TGtkSHWidget;
var
  e: TSHXMLEdit;
begin
  Result := TGtkSHWidget.Create(ADoc, TSHXMLEdit);
  e := Result.Edit as TSHXMLEdit;

  e.shTag        := Result.AddSHStyle('Tag',           colBlack,       colDefault, fsBold);
  e.shTagName    := Result.AddSHStyle('Tag Name',      colBlack,       colDefault, fsBold);
  e.shDefTagName := Result.AddSHStyle('Definition Tag Name', colDarkGreen, colDefault, fsBold);
  e.shArgName    := Result.AddSHStyle('Argument Name', colBrown,       colDefault, fsNormal);
  e.shString     := Result.AddSHStyle('String',        colBlue,        colDefault, fsNormal);
  e.shReference  := Result.AddSHStyle('Reference',     colDarkMagenta, colDefault, fsNormal);
  e.shInvalid    := Result.AddSHStyle('Invalid',       colRed,         colDefault, fsNormal);
  e.shComment    := Result.AddSHStyle('Comment',       colDarkCyan,    colDefault, fsItalics);
  e.shCDATA      := Result.AddSHStyle('CDATA',         colDarkGreen,   colDefault, fsNormal);
end;


var
  MainWindow, Notebook: PGtkWidget;
  Pages: array[0..2] of TGtkSHWidget;
  PasDoc, XMLDoc, TxtDoc: TTextDoc;

procedure OnMainWindowDestroyed; cdecl;
begin
  gtk_main_quit;
end;

begin

  gtk_init(@argc, @argv);

  // Create main window
  MainWindow := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_widget_set_usize(MainWindow, 600, 400);
  gtk_window_set_title(PGtkWindow(MainWindow), 'FPC SHEdit GTK Demo');
  gtk_signal_connect(PGtkObject(MainWindow), 'destroy', GTK_SIGNAL_FUNC(@OnMainWindowDestroyed), nil);

  // Set up documents
  PasDoc := TTextDoc.Create; PasDoc.LoadFromFile('gtkdemo.pp');
  XMLDoc := TTextDoc.Create; XMLDoc.LoadFromFile('simple.xml');
  TxtDoc := TTextDoc.Create; TxtDoc.LoadFromFile('gtkshedit.pp');

  // Create notebook pages (editor widgets)
  Pages[0] := CreatePasEditWidget (PasDoc);
  Pages[1] := CreateXMLEditWidget (XMLDoc);
  Pages[2] := CreateTextEditWidget(TxtDoc);

  // Create notebook
  Notebook := gtk_notebook_new;
  gtk_notebook_append_page(PGtkNotebook(Notebook), Pages[0].Widget, gtk_label_new('Pascal'));
  gtk_notebook_append_page(PGtkNotebook(Notebook), Pages[1].Widget, gtk_label_new('XML'));
  gtk_notebook_append_page(PGtkNotebook(Notebook), Pages[2].Widget, gtk_label_new('Text'));
  gtk_container_add(PGtkContainer(MainWindow), Notebook);
  gtk_widget_show(Notebook);
  gtk_widget_show(MainWindow);
  Pages[0].SetFocus;
  gtk_main;
end.


{
  $Log$
  Revision 1.3  2000-01-07 01:24:34  peter
    * updated copyright to 2000

  Revision 1.2  2000/01/06 16:12:53  sg
  * The demo can't display the file README anymore now in this directory,
    as it doesn't exist here... not it displays the source of gtkshedit.pp
    without syntax highlighting.

  Revision 1.1  2000/01/06 16:03:25  peter
    * moved gtkshedit to gtk dir

  Revision 1.9  2000/01/06 01:20:34  peter
    * moved out of packages/ back to topdir

  Revision 1.1  2000/01/03 19:33:09  peter
    * moved to packages dir

  Revision 1.7  1999/12/30 21:03:25  sg
  * Major restructuring and simplifications

  Revision 1.6  1999/12/22 22:28:08  peter
    * updates for cursor setting
    * button press event works

  Revision 1.5  1999/12/08 01:03:15  peter
    * changes so redrawing and walking with the cursor finally works
      correct

  Revision 1.4  1999/11/15 21:47:36  peter
    * first working keypress things

  Revision 1.3  1999/11/14 21:32:55  peter
    * fixes to get it working without crashes

}
