program outport;

uses crt, go32;

begin
 { turn on speaker }
 outportb($61, $ff);
 { wait a little bit }
 delay(50);
 { turn it off again }
 outportb($61, $0);
end.