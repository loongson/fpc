{
   $Id$
}

{****************************************************************************
                                 Interface
****************************************************************************}

{$ifdef read_interface}

  type
     PGtkHRuler = ^TGtkHRuler;
     TGtkHRuler = record
          ruler : TGtkRuler;
       end;

     PGtkHRulerClass = ^TGtkHRulerClass;
     TGtkHRulerClass = record
          parent_class : TGtkRulerClass;
       end;

Type
  GTK_HRULER=PGtkHRuler;
  GTK_HRULER_CLASS=PGtkHRulerClass;

function  GTK_HRULER_TYPE:TGtkType;cdecl;external gtkdll name 'gtk_hruler_get_type';
function  GTK_IS_HRULER(obj:pointer):boolean;
function  GTK_IS_HRULER_CLASS(klass:pointer):boolean;

function  gtk_hruler_get_type:TGtkType;cdecl;external gtkdll name 'gtk_hruler_get_type';
function  gtk_hruler_new:PGtkWidget;cdecl;external gtkdll name 'gtk_hruler_new';

{$endif read_interface}


{****************************************************************************
                              Implementation
****************************************************************************}

{$ifdef read_implementation}

function  GTK_IS_HRULER(obj:pointer):boolean;
begin
  GTK_IS_HRULER:=(obj<>nil) and GTK_IS_HRULER_CLASS(PGtkTypeObject(obj)^.klass);
end;

function  GTK_IS_HRULER_CLASS(klass:pointer):boolean;
begin
  GTK_IS_HRULER_CLASS:=(klass<>nil) and (PGtkTypeClass(klass)^.thetype=GTK_HRULER_TYPE);
end;

{$endif read_implementation}


{
  $Log$
  Revision 1.2  2002-09-07 15:42:59  peter
    * old logs removed and tabs fixed

  Revision 1.1  2002/01/29 17:55:11  peter
    * splitted to base and extra

}
