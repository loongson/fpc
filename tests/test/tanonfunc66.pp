program tanonfunc66;

{$mode delphi}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

{ test generic local reference declaration 

  same as tanonfunc39 but mode delphi
}

procedure Foo;
type
  TLocalFunc<T> = reference to function(arg: T): T;
var
  F: TLocalFunc<longint>;
begin
  F := function(arg: longint): longint
    begin
      Result := arg * arg;
    end;
  if F(5) <> 25 then
    halt(1);
end;

begin
  Foo;
end.

