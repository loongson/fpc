type
   tobject1 = class
      readl : longint;
      function readl2 : longint;
      procedure writel(l : longint);
      procedure writel2(l : longint);
      property l : longint read readl write writel;
      property l2 : longint read readl2 write writel2;
   end;

procedure tobject1.writel(l : longint);

  begin
  end;

procedure tobject1.writel2(l : longint);

  begin
  end;

function tobject1.readl2 : longint;

  begin
  end;

var
   object1 : tobject1;
   i : longint;

begin
   i:=object1.l;
   i:=object1.l2;
   object1.l:=123;
end.