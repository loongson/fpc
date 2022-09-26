{
    This file is part of the Free Pascal run time library.
    Copyright (C) 2022 Loongson Technology Corporation Limited.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{******************************************************************************
                          Process start/halt
 ******************************************************************************}

var
  dlexitproc : pointer;

procedure _FPC_proc_start; assembler; nostackframe; public name '_start';
  asm
    { clear frame pointer }
    ori $fp, $zero, 0
    { save operatingsystem parameter argc }
    ld.d $a1, $sp, 0
    la.got $t0, operatingsystem_parameter_argc
    st.d $a1, $t0, 0
    { save operatingsystem parameter argv }
    addi.d $a2, $sp, 8
    la.got $t0, operatingsystem_parameter_argv
    st.d $a2, $t0, 0
    { save operatingsystem parameter envp }
    la.got $t0, operatingsystem_parameter_envp
    alsl.d $t1, $a1, $a2, 3
    addi.d $t1, $t1, 8
    st.d $t1, $t0, 0
    { adjust $sp for 16-aligned }
    bstrins.d $sp, $zero, 3, 0
    { save stack pointer }
    la.got $t0, initialstkptr
    st.d $sp, $t0, 0
    { call PascalMain }
    bl PASCALMAIN
  end;


procedure _FPC_dynamic_proc_start; assembler; nostackframe; public name '_dynamic_start';
  asm
    la.got $t0, dlexitproc
    st.d $a0, $t0, 0
    b _FPC_proc_start
  end;


procedure _FPC_loongarch_exit(e:longint); assembler; nostackframe;
  asm
    ori $a7, $zero, 94
    syscall 0
    b _FPC_loongarch_exit
  end;


procedure _FPC_proc_haltproc(e:longint); cdecl; public name '_haltproc';
  begin
    if assigned(dlexitproc) then
      TProcedure(dlexitproc);
    _FPC_loongarch_exit(e);
  end;
