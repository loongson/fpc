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

{
The entry point's job is to call __libc_start_main.  Per the ABI,
a0 contains the address of a function to be passed to atexit.
__libc_start_main wants this in a5.

int __libc_start_main (
  int (*main) (int, char **, char **),
  int argc,
  char **argv,
  __typeof (main) init,
  void (*fini) (void),
  void (*rtld_fini) (void),
  void *stack_end);
}

var
  libc_environ: pchar; external name '__environ';
  libc_fpu_control: word; external name '__fpu_control';
  libc_init_proc: procedure; external name '_init';
  libc_fini_proc: procedure; external name '_fini';
  _etext: pointer; external name '_etext';

  fpc_ret_ra,fpc_ret_sp : pointer;

procedure libc_atexit; external name 'atexit';
procedure libc_exit; external name '__libc_exit';
procedure libc_init; external name '__libc_init';
procedure libc_setfpucw; external name '__setfpucw';
procedure libc_start_main; external name '__libc_start_main';

procedure _FPC_libc_haltproc(e:longint); forward;

procedure ___libc_csu_init; external name '__libc_csu_init';
{$if FPC_FULLVERSION>30202}
procedure __libc_csu_init; public name '__libc_csu_init'; assembler; nostackframe;
  asm
    .weak __libc_csu_init
  end;
{$endif}

procedure ___libc_csu_fini; external name '__libc_csu_fini';
{$if FPC_FULLVERSION>30202}
procedure __libc_csu_fini; public name '__libc_csu_fini'; assembler; nostackframe;
  asm
    .weak __libc_csu_fini
  end;
{$endif}

procedure main_stub; assembler; nostackframe;
  asm
    { let fp = sp in case of no fp value }
    ori $fp, $sp, 0
    { save ra and sp }
    la.pcrel $t0, fpc_ret_ra
    st.d $ra, $t0, 0
    la.pcrel $t1, fpc_ret_sp
    st.d $sp, $t1, 0
    { save stack pointer }
    la.got $t1, initialstkptr
    st.d $sp, $t1, 0
    { call PascalMain }
    la.got $t0, PASCALMAIN
    jr $t0
  end;

procedure ini_dummy;
  begin
  end;

{******************************************************************************
                          C library start/halt
 ******************************************************************************}

procedure _FPC_libc_start; assembler; nostackframe; public name '_start';
  asm
    { clear frame pointer }
    ori $fp, $zero, 0
    { argc = *(int *)sp }
    ld.d $a1, $sp, 0
    { save operatingsystem parameter argc }
    la.got $t0, operatingsystem_parameter_argc
    st.d $a1, $t0, 0
    { argv = (char **)(sp + 8) }
    addi.d $a2, $sp, 8
    { save operatingsystem parameter argv }
    la.got $t0, operatingsystem_parameter_argv
    st.d $a2, $t0, 0
    { save operatingsystem parameter envp }
    la.got $t0, operatingsystem_parameter_envp
    alsl.d $t1, $a1, $a2, 3
    addi.d $t1, $t1, 8
    st.d $t1, $t0, 0
    { adjust $sp for 16-aligned }
    bstrins.d $sp, $zero, 3, 0
    { a3 = our own enter to .init }
    la.got $a3, ___libc_csu_fini
    { a4 = our own enter to .fiit }
    la.got $a4, ___libc_csu_fini
    { a5 = rtld_fini }
    ori $a5, $a0, 0
    { a6 = stack_end }
    ori $a6, $sp, 0
    { a0 = &main_stub }
    la.pcrel $a0, main_stub
    { call libc_start_main }
    la.got $ra, libc_start_main
    jirl $ra, $ra, 0
    break 2
  end;

procedure _FPC_libc_haltproc(e:longint); assembler; nostackframe; public name '_haltproc';
  asm
    la.pcrel $t0, fpc_ret_sp
    ld.d $sp, $t0, 0
    la.pcrel $t1, fpc_ret_ra
    ld.d $ra, $t1, 0
    jr $ra
  end;
