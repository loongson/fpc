Program svgasel;

uses go32;

var vgasel : Word;
    r : trealregs;

begin
  r.eax := $13; realintr($10, r);
  vgasel := segment_to_descriptor($A000);
  { simply fill the screen memory with color 15 }
  seg_fillchar(vgasel, 0, 64000, #15);
  readln;
 { back to text mode }
  r.eax := $3; 
  realintr($10, r);
end.