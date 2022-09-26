{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2014 by Jonas Maebe
    member of the Free Pascal development team

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

**********************************************************************}

function getrm: dword; nostackframe; assembler;
  asm
    movfcsr2gr $a0, $r3
    srli.w $a0, $a0, 8
  end;


procedure setrm(val: dword); nostackframe; assembler;
  asm
    slli.w $a0, $a0, 8
    movgr2fcsr $r3, $a0
  end;


procedure setenables(enables : dword); nostackframe; assembler;
  asm
    movgr2fcsr $r1, $a0
  end;


function getcause: dword; nostackframe; assembler;
  asm
    movfcsr2gr $a0, $r2
    srli.w $a0, $a0, 24
  end;


procedure clearcause; nostackframe; assembler;
  asm
    movgr2fcsr $r2, $zero
  end;


function GetRoundMode: TFPURoundingMode;
  const
    bits2rm: array[0..3] of TFPURoundingMode = (rmNearest,rmTruncate,rmUp,rmDown);
  begin
    result:=TFPURoundingMode(bits2rm[getrm])
  end;


function SetRoundMode(const RoundMode: TFPURoundingMode): TFPURoundingMode;
  const
    rm2bits : array[TFPURoundingMode] of byte = (0,3,2,1);
  begin
    softfloat_rounding_mode:=RoundMode;
    SetRoundMode:=GetRoundMode;
    setrm(rm2bits[RoundMode]);
  end;


function GetPrecisionMode: TFPUPrecisionMode;
  begin
    result:=pmDouble;
  end;


function SetPrecisionMode(const Precision: TFPUPrecisionMode): TFPUPrecisionMode;
  begin
    result:=pmDouble;
  end;

const
  fpu_i = 1 shl 0;
  fpu_u = 1 shl 1;
  fpu_o = 1 shl 2;
  fpu_z = 1 shl 3;
  fpu_v = 1 shl 4;


function GetExceptionMask: TFPUExceptionMask;
  begin
    Result:=softfloat_exception_mask;
  end;


function SetExceptionMask(const Mask: TFPUExceptionMask): TFPUExceptionMask;
  var
    newenables: qword;
  begin
    { clear "exception happened" flags }
    ClearExceptions(false);
    softfloat_exception_mask:=Mask;

    newenables:=$1f;
    if exPrecision in Mask then
      newenables:=newenables and not(fpu_i);
    if exUnderflow in Mask then
      newenables:=newenables and not(fpu_u);
    if exOverflow in Mask then
      newenables:=newenables and not(fpu_o);
    if exZeroDivide in Mask then
      newenables:=newenables and not(fpu_z);
    if exInvalidOp in Mask then
      newenables:=newenables and not(fpu_v);
    setenables(newenables);

    Result:=softfloat_exception_mask;
  end;


procedure RaisePendingExceptions;
  var
    cause : dword;
    f: TFPUException;
  begin
    cause:=getcause;
    if (cause and fpu_i) <> 0 then
      float_raise(exPrecision);
    if (cause and fpu_u) <> 0 then
      float_raise(exUnderflow);
    if (cause and fpu_o) <> 0 then
      float_raise(exOverflow);
    if (cause and fpu_z) <> 0 then
      float_raise(exZeroDivide);
    if (cause and fpu_v) <> 0 then
      float_raise(exInvalidOp);
    { now the soft float exceptions }
    for f in softfloat_exception_flags do
      float_raise(f);
  end;


procedure ClearExceptions(RaisePending: Boolean);
  begin
    if raisepending then
      RaisePendingExceptions;
    softfloat_exception_flags:=[];
    clearcause;
  end;
