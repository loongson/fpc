{
   $Id$
}

{****************************************************************************
                                 Interface
****************************************************************************}

{$ifdef read_interface}

  type
     PGtkHBox = ^TGtkHBox;
     TGtkHBox = record
          box : TGtkBox;
       end;

     PGtkHBoxClass = ^TGtkHBoxClass;
     TGtkHBoxClass = record
          parent_class : TGtkBoxClass;
       end;

Type
  GTK_HBOX=PGtkHBox;
  GTK_HBOX_CLASS=PGtkHBoxClass;

function  GTK_HBOX_TYPE:TGtkType;cdecl;external gtkdll name 'gtk_hbox_get_type';
function  GTK_IS_HBOX(obj:pointer):boolean;
function  GTK_IS_HBOX_CLASS(klass:pointer):boolean;

function  gtk_hbox_get_type:TGtkType;cdecl;external gtkdll name 'gtk_hbox_get_type';
function  gtk_hbox_new(homogeneous:gboolean; spacing:gint):PGtkWidget;cdecl;external gtkdll name 'gtk_hbox_new';

{$endif read_interface}


{****************************************************************************
                              Implementation
****************************************************************************}

{$ifdef read_implementation}

function  GTK_IS_HBOX(obj:pointer):boolean;
begin
  GTK_IS_HBOX:=(obj<>nil) and GTK_IS_HBOX_CLASS(PGtkTypeObject(obj)^.klass);
end;

function  GTK_IS_HBOX_CLASS(klass:pointer):boolean;
begin
  GTK_IS_HBOX_CLASS:=(klass<>nil) and (PGtkTypeClass(klass)^.thetype=GTK_HBOX_TYPE);
end;

{$endif read_implementation}


{
  $Log$
  Revision 1.2  2002-09-07 15:42:59  peter
    * old logs removed and tabs fixed

  Revision 1.1  2002/01/29 17:55:11  peter
    * splitted to base and extra

}
