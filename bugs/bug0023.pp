type
   tobject = object
      a : longint;
      procedure t1;
      procedure t2;virtual;
      constructor init;
   end;

procedure tobject.t1;

  procedure nested1;

    begin
       writeln;
       a:=1;
    end;

  begin
  end;

procedure tobject.t2;

  procedure nested1;

    begin
       writeln;
       a:=1;
    end;

  begin
  end;

constructor tobject.init;

  procedure nested1;

    begin
       writeln;
       a:=1;
    end;

  begin
  end;


begin
end.