{
   $Id$
}

{****************************************************************************
                                 Interface
****************************************************************************}

{$ifdef read_interface}

  type
     PGtkSeparator = ^TGtkSeparator;
     TGtkSeparator = record
          widget : TGtkWidget;
       end;

     PGtkSeparatorClass = ^TGtkSeparatorClass;
     TGtkSeparatorClass = record
          parent_class : TGtkWidgetClass;
       end;

Type
  GTK_SEPARATOR=PGtkSeparator;
  GTK_SEPARATOR_CLASS=PGtkSeparatorClass;

function  GTK_SEPARATOR_TYPE:TGtkType;cdecl;external gtkdll name 'gtk_separator_get_type';
function  GTK_IS_SEPARATOR(obj:pointer):boolean;
function  GTK_IS_SEPARATOR_CLASS(klass:pointer):boolean;

function  gtk_separator_get_type:TGtkType;cdecl;external gtkdll name 'gtk_separator_get_type';

{$endif read_interface}


{****************************************************************************
                              Implementation
****************************************************************************}

{$ifdef read_implementation}

function  GTK_IS_SEPARATOR(obj:pointer):boolean;
begin
  GTK_IS_SEPARATOR:=(obj<>nil) and GTK_IS_SEPARATOR_CLASS(PGtkTypeObject(obj)^.klass);
end;

function  GTK_IS_SEPARATOR_CLASS(klass:pointer):boolean;
begin
  GTK_IS_SEPARATOR_CLASS:=(klass<>nil) and (PGtkTypeClass(klass)^.thetype=GTK_SEPARATOR_TYPE);
end;

{$endif read_implementation}


{
  $Log$
  Revision 1.2  2002-09-07 15:43:00  peter
    * old logs removed and tabs fixed

  Revision 1.1  2002/01/29 17:55:13  peter
    * splitted to base and extra

}
