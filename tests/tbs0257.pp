{$mode tp}

type proc = procedure(a : longint);
procedure test(b : longint);
begin
  Writeln('Test ',b);
end;

var
  t : proc;

begin
  t:=test;
  t:=proc(test);
  test(3);
  t(5);
end.

