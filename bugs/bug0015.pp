program test;
type            
    realgr=    array [1..1000]  of double;  
var                                
    sx    :realgr;
    i     :integer;
    stemp :double;
begin
     sx[1]:=10;
     sx[2]:=-20;
     sx[3]:=30;
     sx[4]:=-40;
     sx[5]:=50;
     sx[6]:=-60;
     i:=1;
     stemp:=1000;
     stemp := stemp+abs(sx[i])+abs(sx[i+1])+abs(sx[i+2])+abs(sx[i+3])+
              abs(sx[i+4])+abs(sx[i+5]);
     writeln(stemp);
end.
