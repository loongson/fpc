program EnumPtrConvTest;

{$APPTYPE CONSOLE}

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$packenum 1}

type
  TEnum = (a, b);

var
  e: TEnum;
  p: Pointer;

begin
  e := b;
  p := Pointer(e);
  if Integer(p)<>1 then
    halt(1); // produces "1" in Delphi
end.
