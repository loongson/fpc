{
   $Id$
}

{****************************************************************************
                                 Interface
****************************************************************************}

{$ifdef read_interface}

  type
     PGtkVScale = ^TGtkVScale;
     TGtkVScale = record
          scale : TGtkScale;
       end;

     PGtkVScaleClass = ^TGtkVScaleClass;
     TGtkVScaleClass = record
          parent_class : TGtkScaleClass;
       end;

Type
  GTK_VSCALE=PGtkVScale;
  GTK_VSCALE_CLASS=PGtkVScaleClass;

function  GTK_VSCALE_TYPE:TGtkType;cdecl;external gtkdll name 'gtk_vscale_get_type';
function  GTK_IS_VSCALE(obj:pointer):boolean;
function  GTK_IS_VSCALE_CLASS(klass:pointer):boolean;

function  gtk_vscale_get_type:TGtkType;cdecl;external gtkdll name 'gtk_vscale_get_type';
function  gtk_vscale_new(adjustment:PGtkAdjustment):PGtkWidget;cdecl;external gtkdll name 'gtk_vscale_new';

{$endif read_interface}


{****************************************************************************
                              Implementation
****************************************************************************}

{$ifdef read_implementation}

function  GTK_IS_VSCALE(obj:pointer):boolean;
begin
  GTK_IS_VSCALE:=(obj<>nil) and GTK_IS_VSCALE_CLASS(PGtkTypeObject(obj)^.klass);
end;

function  GTK_IS_VSCALE_CLASS(klass:pointer):boolean;
begin
  GTK_IS_VSCALE_CLASS:=(klass<>nil) and (PGtkTypeClass(klass)^.thetype=GTK_VSCALE_TYPE);
end;

{$endif read_implementation}


{
  $Log$
  Revision 1.2  2002-09-07 15:43:00  peter
    * old logs removed and tabs fixed

  Revision 1.1  2002/01/29 17:55:14  peter
    * splitted to base and extra

}
