Program rmpm_int;

uses crt, go32;

{$ASMMODE DIRECT}

var r : trealregs;
    axreg : Word; 

    oldint21h : tseginfo;
    newint21h : tseginfo;

procedure int21h_handler; assembler;
asm
   cmpw $0x3001, %ax
   jne CallOld
   movw $0x3112, %ax
   iret

CallOld:
   ljmp %cs:OLDHANDLER

OLDHANDLER: .long 0
            .word 0
end;

procedure resume;
begin
     Writeln;
     Write('-- press any key to resume --'); readkey;
     gotoxy(1, wherey); clreol;
end;

begin
     clrscr;
     Writeln('Executing real mode interrupt');
     resume;
     r.ah := $30; r.al := $01;  realintr($21, r);
     Writeln('DOS v', r.al,'.',r.ah, ' detected');
     resume;
     Writeln('Executing protected mode interrupt',
             ' without our own handler');
     Writeln;
     asm
        movb $0x30, %ah
        movb $0x01, %al
        int $0x21
        movw %ax, _AXREG
     end;
     Writeln('DOS v', r.al,'.',r.ah, ' detected');
     resume;
     Writeln('As you can see the DPMI hosts',
             ' default protected mode handler');
     Writeln('simply redirects it to the real mode handler');
     resume;
     Writeln('Now exchanging the protected mode',
             'interrupt with our own handler');
     resume;

     newint21h.offset := @int21h_handler;
     newint21h.segment := get_cs;
     get_pm_interrupt($21, oldint21h);
     asm
        movl _OLDINT21H, %eax
        movl %eax, OLDHANDLER
        movw 4+_OLDINT21H, %ax
        movw %ax, 4+OLDHANDLER
     end;
     set_pm_interrupt($21, newint21h);

     Writeln('Executing real mode interrupt again');
     resume;
     r.ah := $30; r.al := $01; realintr($21, r);
     Writeln('DOS v', r.al,'.',r.ah, ' detected');
     Writeln;
     Writeln('See, it didn''t change in any way.');
     resume;
     Writeln('Now calling protected mode interrupt');
     resume;
     asm
        movb $0x30, %ah
        movb $0x01, %al
        int $0x21
        movw %ax, _AXREG
     end;
     Writeln('DOS v', lo(axreg),'.',hi(axreg), ' detected');
     Writeln;
     Writeln('Now you can see that there''s',
             ' a distinction between the two ways of ');
     Writeln('calling interrupts...');
     set_pm_interrupt($21, oldint21h);
end.