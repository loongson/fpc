 {
    $Id$
    Copyright (c) 1998-2000 by Florian Klaempfl and Jonas Maebe

    This unit contains the peephole optimizer.

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

 ****************************************************************************
}
Unit POpt386;


Interface

Uses Aasm;

Procedure PeepHoleOptPass1(AsmL: PAasmOutput; BlockStart, BlockEnd: Pai);
Procedure PeepHoleOptPass2(AsmL: PAasmOutput; BlockStart, BlockEnd: Pai);

Implementation

Uses
  globtype,systems,
  globals,verbose,hcodegen,
{$ifdef finaldestdebug}
  cobjects,
{$endif finaldestdebug}
  cpubase,cpuasm,DAOpt386,tgeni386;

Function RegUsedAfterInstruction(Reg: TRegister; p: Pai; Var UsedRegs: TRegSet): Boolean;
Begin
  reg := reg32(reg);
  UpdateUsedRegs(UsedRegs, Pai(p^.Next));
  RegUsedAfterInstruction :=
    (Reg in UsedRegs) and
    (not(getNextInstruction(p,p)) or
     not(regLoadedWithNewValue(reg,false,p)));
End;

function doFpuLoadStoreOpt(asmL: paasmoutput; var p: pai): boolean;
{ returns true if a "continue" should be done after this optimization }
var hp1, hp2: pai;
begin
  doFpuLoadStoreOpt := false;
  if (paicpu(p)^.oper[0].typ = top_ref) and
     getNextInstruction(p, hp1) and
     (hp1^.typ = ait_instruction) and
     (((paicpu(hp1)^.opcode = A_FLD) and
       (paicpu(p)^.opcode = A_FSTP)) or
      ((paicpu(p)^.opcode = A_FISTP) and
       (paicpu(hp1)^.opcode = A_FILD))) and
     (paicpu(hp1)^.oper[0].typ = top_ref) and
     (paicpu(hp1)^.opsize = Paicpu(p)^.opsize) and
     refsEqual(paicpu(p)^.oper[0].ref^, paicpu(hp1)^.oper[0].ref^) then
    begin
      if getNextInstruction(hp1, hp2) and
         (hp2^.typ = ait_instruction) and
         ((paicpu(hp2)^.opcode = A_LEAVE) or
          (paicpu(hp2)^.opcode = A_RET)) and
         (paicpu(p)^.oper[0].ref^.Base = procinfo^.FramePointer) and
         (paicpu(p)^.oper[0].ref^.Offset >= procinfo^.Return_Offset) and
         (paicpu(p)^.oper[0].ref^.Index = R_NO) then
        begin
          asmL^.remove(p);
          asmL^.remove(hp1);
          dispose(p, done);
          dispose(hp1, done);
          p := hp2;
          removeLastDeallocForFuncRes(asmL, p);
          doFPULoadStoreOpt := true;
        end
      else
        { fst can't store an extended value! }
        if (paicpu(p)^.opsize <> S_FX) and
           (paicpu(p)^.opsize <> S_IQ) then
          begin
            if (paicpu(p)^.opcode = A_FSTP) then
              paicpu(p)^.opcode := A_FST
            else Paicpu(p)^.opcode := A_FIST;
            asmL^.remove(hp1);
            dispose(hp1, done)
          end
    end;
end;


Procedure PeepHoleOptPass1(Asml: PAasmOutput; BlockStart, BlockEnd: Pai);
{First pass of peepholeoptimizations}

Var
  l,l1 : longint;
  p,hp1,hp2 : pai;
  hp3,hp4: pai;

  TmpRef: TReference;

  UsedRegs, TmpUsedRegs: TRegSet;

  TmpBool1, TmpBool2: Boolean;

  Function SkipLabels(hp: Pai; var hp2: pai): boolean;
  {skips all labels and returns the next "real" instruction}
  Begin
    While assigned(hp^.next) and
          (pai(hp^.next)^.typ In SkipInstr + [ait_label,ait_align]) Do
      hp := pai(hp^.next);
    If assigned(hp^.next) Then
      Begin
        SkipLabels := True;
        hp2 := pai(hp^.next)
      End
    Else
      Begin
        hp2 := hp;
        SkipLabels := False
      End;
  End;

  Procedure GetFinalDestination(AsmL: PAAsmOutput; hp: paicpu);
  {traces sucessive jumps to their final destination and sets it, e.g.
   je l1                je l3
   <code>               <code>
   l1:       becomes    l1:
   je l2                je l3
   <code>               <code>
   l2:                  l2:
   jmp l3               jmp l3}

  Var p1, p2: pai;
      l: pasmlabel;

    Function FindAnyLabel(hp: pai; var l: pasmlabel): Boolean;
    Begin
      FindAnyLabel := false;
      While assigned(hp^.next) and
            (pai(hp^.next)^.typ In (SkipInstr+[ait_align])) Do
        hp := pai(hp^.next);
      If assigned(hp^.next) and
         (pai(hp^.next)^.typ = ait_label) Then
        Begin
          FindAnyLabel := true;
          l := pai_label(hp^.next)^.l;
        End
    End;

  Begin
    If (pasmlabel(hp^.oper[0].sym)^.labelnr >= LoLab) and
       (pasmlabel(hp^.oper[0].sym)^.labelnr <= HiLab) and   {range check, a jump can go past an assembler block!}
       Assigned(LTable^[pasmlabel(hp^.oper[0].sym)^.labelnr-LoLab].PaiObj) Then
      Begin
        p1 := LTable^[pasmlabel(hp^.oper[0].sym)^.labelnr-LoLab].PaiObj; {the jump's destination}
        SkipLabels(p1,p1);
        If (pai(p1)^.typ = ait_instruction) and
           (paicpu(p1)^.is_jmp) Then
          If { the next instruction after the label where the jump hp arrives}
             { is unconditional or of the same type as hp, so continue       }
             (paicpu(p1)^.condition in [C_None,hp^.condition]) or
             { the next instruction after the label where the jump hp arrives}
             { is the opposite of hp (so this one is never taken), but after }
             { that one there is a branch that will be taken, so perform a   }
             { little hack: set p1 equal to this instruction (that's what the}
             { last SkipLabels is for, only works with short bool evaluation)}
             ((paicpu(p1)^.condition = inverse_cond[hp^.condition]) and
              SkipLabels(p1,p2) and
              (p2^.typ = ait_instruction) and
              (paicpu(p2)^.is_jmp) and
              (paicpu(p2)^.condition in [C_None,hp^.condition]) and
              SkipLabels(p1,p1)) Then
            Begin
              GetFinalDestination(asml, paicpu(p1));
              Dec(pasmlabel(hp^.oper[0].sym)^.refs);
              hp^.oper[0].sym:=paicpu(p1)^.oper[0].sym;
              inc(pasmlabel(hp^.oper[0].sym)^.refs);
            End
          Else
            If (paicpu(p1)^.condition = inverse_cond[hp^.condition]) then
              if not FindAnyLabel(p1,l) then
                begin
  {$ifdef finaldestdebug}
                  insertllitem(asml,p1,p1^.next,new(pai_asm_comment,init(
                    strpnew('previous label inserted'))));
  {$endif finaldestdebug}
                  getlabel(l);
                  insertllitem(asml,p1,p1^.next,new(pai_label,init(l)));
                  dec(pasmlabel(paicpu(hp)^.oper[0].sym)^.refs);
                  hp^.oper[0].sym := l;
                  inc(l^.refs);
  {               this won't work, since the new label isn't in the labeltable }
  {               so it will fail the rangecheck. Labeltable should become a   }
  {               hashtable to support this:                                   }
  {               GetFinalDestination(asml, hp);                               }
                end
              else
                begin
  {$ifdef finaldestdebug}
                  insertllitem(asml,p1,p1^.next,new(pai_asm_comment,init(
                    strpnew('next label reused'))));
  {$endif finaldestdebug}
                  inc(l^.refs);
                  hp^.oper[0].sym := l;
                  GetFinalDestination(asml, hp);
                end;
      End;
  End;

  Function DoSubAddOpt(var p: Pai): Boolean;
  Begin
    DoSubAddOpt := False;
    If GetLastInstruction(p, hp1) And
       (hp1^.typ = ait_instruction) And
       (Paicpu(hp1)^.opsize = Paicpu(p)^.opsize) then
      Case Paicpu(hp1)^.opcode Of
        A_DEC:
          If (Paicpu(hp1)^.oper[0].typ = top_reg) And
             (Paicpu(hp1)^.oper[0].reg = Paicpu(p)^.oper[1].reg) Then
            Begin
              Paicpu(p)^.LoadConst(0,Paicpu(p)^.oper[0].val+1);
              AsmL^.Remove(hp1);
              Dispose(hp1, Done)
            End;
         A_SUB:
           If (Paicpu(hp1)^.oper[0].typ = top_const) And
              (Paicpu(hp1)^.oper[1].typ = top_reg) And
              (Paicpu(hp1)^.oper[1].reg = Paicpu(p)^.oper[1].reg) Then
             Begin
               Paicpu(p)^.LoadConst(0,Paicpu(p)^.oper[0].val+Paicpu(hp1)^.oper[0].val);
               AsmL^.Remove(hp1);
               Dispose(hp1, Done)
             End;
         A_ADD:
           If (Paicpu(hp1)^.oper[0].typ = top_const) And
              (Paicpu(hp1)^.oper[1].typ = top_reg) And
              (Paicpu(hp1)^.oper[1].reg = Paicpu(p)^.oper[1].reg) Then
             Begin
               Paicpu(p)^.LoadConst(0,Paicpu(p)^.oper[0].val-Paicpu(hp1)^.oper[0].val);
               AsmL^.Remove(hp1);
               Dispose(hp1, Done);
               If (Paicpu(p)^.oper[0].val = 0) Then
                 Begin
                   hp1 := Pai(p^.next);
                   AsmL^.Remove(p);
                   Dispose(p, Done);
                   If Not GetLastInstruction(hp1, p) Then
                     p := hp1;
                   DoSubAddOpt := True;
                 End
             End;
       End;
  End;

Begin
  P := BlockStart;
  UsedRegs := [];
  While (P <> BlockEnd) Do
    Begin
      UpDateUsedRegs(UsedRegs, Pai(p^.next));
      Case P^.Typ Of
        ait_instruction:
          Begin
            { Handle Jmp Optimizations }
            if Paicpu(p)^.is_jmp then
             begin
     {the following if-block removes all code between a jmp and the next label,
      because it can never be executed}
               If (paicpu(p)^.opcode = A_JMP) Then
                 Begin
                   While GetNextInstruction(p, hp1) and
                         ((hp1^.typ <> ait_label) or
                   { skip unused labels, they're not referenced anywhere }
                          labelCanBeSkipped(pai_label(hp1))) Do
                     If not(hp1^.typ in ([ait_label,ait_align]+skipinstr)) Then
                       Begin
                         AsmL^.Remove(hp1);
                         Dispose(hp1, done);
                       End
                     else break;
                  End;
               If GetNextInstruction(p, hp1) then
                 Begin
                   if FindLabel(pasmlabel(paicpu(p)^.oper[0].sym), hp1) then
                     Begin
                       hp2:=pai(hp1^.next);
                       asml^.remove(p);
                       dispose(p,done);
                       p:=hp2;
                       continue;
                     end
                   Else
                     Begin
                       if hp1^.typ = ait_label then
                         SkipLabels(hp1,hp1);
                       If (pai(hp1)^.typ=ait_instruction) and
                          (paicpu(hp1)^.opcode=A_JMP) and
                          GetNextInstruction(hp1, hp2) And
                          FindLabel(PAsmLabel(paicpu(p)^.oper[0].sym), hp2)
                         Then
                           Begin
                             if paicpu(p)^.opcode=A_Jcc then
                              paicpu(p)^.condition:=inverse_cond[paicpu(p)^.condition]
                             else
                              begin
                                If (LabDif <> 0) Then
                                  GetFinalDestination(asml, paicpu(p));
                                p:=pai(p^.next);
                                continue;
                              end;
                             Dec(pai_label(hp2)^.l^.refs);
                             paicpu(p)^.oper[0].sym:=paicpu(hp1)^.oper[0].sym;
                             Inc(paicpu(p)^.oper[0].sym^.refs);
                             asml^.remove(hp1);
                             dispose(hp1,done);
                             If (LabDif <> 0) Then
                               GetFinalDestination(asml, paicpu(p));
                           end
                         else
                           If (LabDif <> 0) Then
                             GetFinalDestination(asml, paicpu(p));
                     end;
                 end;
             end
            else
            { All other optimizes }
             begin
            For l := 0 to 2 Do
              If (Paicpu(p)^.oper[l].typ = top_ref) Then
                With Paicpu(p)^.oper[l].ref^ Do
                  Begin
                    If (base = R_NO) And
                       (index <> R_NO) And
                       (scalefactor in [0,1])
                      Then
                        Begin
                          base := index;
                          index := R_NO
                        End
                   End;
            Case Paicpu(p)^.opcode Of
              A_AND:
                Begin
                  If (Paicpu(p)^.oper[0].typ = top_const) And
                     (Paicpu(p)^.oper[1].typ = top_reg) And
                     GetNextInstruction(p, hp1) And
                     (Pai(hp1)^.typ = ait_instruction) And
                     (Paicpu(hp1)^.opcode = A_AND) And
                     (Paicpu(hp1)^.oper[0].typ = top_const) And
                     (Paicpu(hp1)^.oper[1].typ = top_reg) And
                     (Paicpu(hp1)^.oper[1].reg = Paicpu(hp1)^.oper[1].reg)
                    Then
{change "and const1, reg; and const2, reg" to "and (const1 and const2), reg"}
                      Begin
                        Paicpu(p)^.LoadConst(0,Paicpu(p)^.oper[0].val And Paicpu(hp1)^.oper[0].val);
                        AsmL^.Remove(hp1);
                        Dispose(hp1, Done)
                      End
                    Else
{change "and x, reg; jxx" to "test x, reg", if reg is deallocated before the
 jump, but only if it's a conditional jump (PFV) }
                      If (Paicpu(p)^.oper[1].typ = top_reg) And
                         GetNextInstruction(p, hp1) And
                         (hp1^.typ = ait_instruction) And
                         (Paicpu(hp1)^.is_jmp) and
                         (Paicpu(hp1)^.opcode<>A_JMP) and
                         Not(Paicpu(p)^.oper[1].reg in UsedRegs) Then
                        Paicpu(p)^.opcode := A_TEST;
                End;
              A_CMP:
                Begin
                  If (Paicpu(p)^.oper[0].typ = top_const) And
                     (Paicpu(p)^.oper[1].typ in [top_reg,top_ref]) And
                     (Paicpu(p)^.oper[0].val = 0) Then
                    If GetNextInstruction(p, hp1) And
                       (hp1^.typ = ait_instruction) And
                       (Paicpu(hp1)^.is_jmp) and
                       (paicpu(hp1)^.opcode=A_Jcc) and
                       (paicpu(hp1)^.condition in [C_LE,C_BE]) and
                       GetNextInstruction(hp1,hp2) and
                       (hp2^.typ = ait_instruction) and
                       (Paicpu(hp2)^.opcode = A_DEC) And
                       OpsEqual(Paicpu(hp2)^.oper[0],Paicpu(p)^.oper[1]) And
                       GetNextInstruction(hp2, hp3) And
                       (hp3^.typ = ait_instruction) and
                       (Paicpu(hp3)^.is_jmp) and
                       (Paicpu(hp3)^.opcode = A_JMP) And
                       GetNextInstruction(hp3, hp4) And
                       FindLabel(PAsmLabel(paicpu(hp1)^.oper[0].sym),hp4)
                      Then
                        Begin
                          Paicpu(hp2)^.Opcode := A_SUB;
                          Paicpu(hp2)^.Loadoper(1,Paicpu(hp2)^.oper[0]);
                          Paicpu(hp2)^.LoadConst(0,1);
                          Paicpu(hp2)^.ops:=2;
                          Paicpu(hp3)^.Opcode := A_Jcc;
                          Case paicpu(hp1)^.condition of
                            C_LE: Paicpu(hp3)^.condition := C_GE;
                            C_BE: Paicpu(hp3)^.condition := C_AE;
                          End;
                          AsmL^.Remove(p);
                          AsmL^.Remove(hp1);
                          Dispose(p, Done);
                          Dispose(hp1, Done);
                          p := hp2;
                          continue;
                        End
                      Else
                 {change "cmp $0, %reg" to "test %reg, %reg"}
                  If (Paicpu(p)^.oper[1].typ = top_reg) Then
                      Begin
                        Paicpu(p)^.opcode := A_TEST;
                        Paicpu(p)^.loadreg(0,Paicpu(p)^.oper[1].reg);
                      End;
                End;
              A_FLD:
                Begin
                  If (Paicpu(p)^.oper[0].typ = top_reg) And
                     GetNextInstruction(p, hp1) And
                     (hp1^.typ = Ait_Instruction) And
                     (Paicpu(hp1)^.oper[0].typ = top_reg) And
                     (Paicpu(hp1)^.oper[1].typ = top_reg) And
                     (Paicpu(hp1)^.oper[0].reg = R_ST) And
                     (Paicpu(hp1)^.oper[1].reg = R_ST1) Then
                     { change                        to
                         fld      reg               fxxx reg,st
                         fxxxp    st, st1 (hp1)
                       Remark: non commutative operations must be reversed!
                     }
                     begin
                        Case Paicpu(hp1)^.opcode Of
                          A_FMULP,A_FADDP,
                          A_FSUBP,A_FDIVP,A_FSUBRP,A_FDIVRP:
                            begin
                               Case Paicpu(hp1)^.opcode Of
                                 A_FADDP: Paicpu(hp1)^.opcode := A_FADD;
                                 A_FMULP: Paicpu(hp1)^.opcode := A_FMUL;
                                 A_FSUBP: Paicpu(hp1)^.opcode := A_FSUBR;
                                 A_FSUBRP: Paicpu(hp1)^.opcode := A_FSUB;
                                 A_FDIVP: Paicpu(hp1)^.opcode := A_FDIVR;
                                 A_FDIVRP: Paicpu(hp1)^.opcode := A_FDIV;
                               End;
                               Paicpu(hp1)^.oper[0].reg := Paicpu(p)^.oper[0].reg;
                               Paicpu(hp1)^.oper[1].reg := R_ST;
                               AsmL^.Remove(p);
                               Dispose(p, Done);
                               p := hp1;
                               Continue;
                            end;
                        end;
                     end
                  else
                  If (Paicpu(p)^.oper[0].typ = top_ref) And
                     GetNextInstruction(p, hp2) And
                     (hp2^.typ = Ait_Instruction) And
                     (Paicpu(hp2)^.oper[0].typ = top_reg) And
                     (Paicpu(hp2)^.oper[1].typ = top_reg) And
                     (Paicpu(p)^.opsize in [S_FS, S_FL]) And
                     (Paicpu(hp2)^.oper[0].reg = R_ST) And
                     (Paicpu(hp2)^.oper[1].reg = R_ST1) Then
                    If GetLastInstruction(p, hp1) And
                       (hp1^.typ = Ait_Instruction) And
                       ((Paicpu(hp1)^.opcode = A_FLD) Or
                        (Paicpu(hp1)^.opcode = A_FST)) And
                       (Paicpu(hp1)^.opsize = Paicpu(p)^.opsize) And
                       (Paicpu(hp1)^.oper[0].typ = top_ref) And
                       RefsEqual(Paicpu(p)^.oper[0].ref^, Paicpu(hp1)^.oper[0].ref^) Then
                      If ((Paicpu(hp2)^.opcode = A_FMULP) Or
                          (Paicpu(hp2)^.opcode = A_FADDP)) Then

                      { change                      to
                          fld/fst   mem1  (hp1)       fld/fst   mem1
                          fld       mem1  (p)         fadd/
                          faddp/                       fmul     st, st
                           fmulp  st, st1 (hp2) }
                        Begin
                          AsmL^.Remove(p);
                          Dispose(p, Done);
                          p := hp1;
                          If (Paicpu(hp2)^.opcode = A_FADDP) Then
                            Paicpu(hp2)^.opcode := A_FADD
                          Else
                            Paicpu(hp2)^.opcode := A_FMUL;
                          Paicpu(hp2)^.oper[1].reg := R_ST;
                        End
                      Else
                      { change              to
                          fld/fst mem1 (hp1)   fld/fst mem1
                          fld     mem1 (p)     fld      st}
                        Begin
                          Paicpu(p)^.changeopsize(S_FL);
                          Paicpu(p)^.loadreg(0,R_ST);
                        End
                    Else
                      Begin
                        Case Paicpu(hp2)^.opcode Of
                          A_FMULP,A_FADDP,A_FSUBP,A_FDIVP,A_FSUBRP,A_FDIVRP:
                     { change                        to
                         fld/fst  mem1    (hp1)      fld/fst    mem1
                         fld      mem2    (p)        fxxx       mem2
                         fxxxp    st, st1 (hp2)                      }

                            Begin
                              Case Paicpu(hp2)^.opcode Of
                                A_FADDP: Paicpu(p)^.opcode := A_FADD;
                                A_FMULP: Paicpu(p)^.opcode := A_FMUL;
                                A_FSUBP: Paicpu(p)^.opcode := A_FSUBR;
                                A_FSUBRP: Paicpu(p)^.opcode := A_FSUB;
                                A_FDIVP: Paicpu(p)^.opcode := A_FDIVR;
                                A_FDIVRP: Paicpu(p)^.opcode := A_FDIV;
                              End;
                              AsmL^.Remove(hp2);
                              Dispose(hp2, Done)
                            End
                        End
                      End
                End;
              A_FSTP,A_FISTP:
                if doFpuLoadStoreOpt(asmL,p) then
                  continue;
              A_IMUL:
                {changes certain "imul const, %reg"'s to lea sequences}
                Begin
                  If (Paicpu(p)^.oper[0].typ = Top_Const) And
                     (Paicpu(p)^.oper[1].typ = Top_Reg) And
                     (Paicpu(p)^.opsize = S_L) Then
                    If (Paicpu(p)^.oper[0].val = 1) Then
                      If (Paicpu(p)^.oper[2].typ = Top_None) Then
                       {remove "imul $1, reg"}
                        Begin
                          hp1 := Pai(p^.Next);
                          AsmL^.Remove(p);
                          Dispose(p, Done);
                          p := hp1;
                          Continue;
                        End
                      Else
                       {change "imul $1, reg1, reg2" to "mov reg1, reg2"}
                        Begin
                          hp1 := New(Paicpu, Op_Reg_Reg(A_MOV, S_L, Paicpu(p)^.oper[1].reg,Paicpu(p)^.oper[2].reg));
                          InsertLLItem(AsmL, p^.previous, p^.next, hp1);
                          Dispose(p, Done);
                          p := hp1;
                        End
                    Else If
                     ((Paicpu(p)^.oper[2].typ = Top_Reg) or
                      (Paicpu(p)^.oper[2].typ = Top_None)) And
                     (aktoptprocessor < ClassP6) And
                     (Paicpu(p)^.oper[0].val <= 12) And
                     Not(CS_LittleSize in aktglobalswitches) And
                     (Not(GetNextInstruction(p, hp1)) Or
                       {GetNextInstruction(p, hp1) And}
                       Not((Pai(hp1)^.typ = ait_instruction) And
                           ((paicpu(hp1)^.opcode=A_Jcc) and
                            (paicpu(hp1)^.condition in [C_O,C_NO]))))
                    Then
                      Begin
                        Reset_reference(tmpref);
                        Case Paicpu(p)^.oper[0].val Of
                          3: Begin
                             {imul 3, reg1, reg2 to
                                lea (reg1,reg1,2), reg2
                              imul 3, reg1 to
                                lea (reg1,reg1,2), reg1}
                               TmpRef.base := Paicpu(p)^.oper[1].reg;
                               TmpRef.Index := Paicpu(p)^.oper[1].reg;
                               TmpRef.ScaleFactor := 2;
                               If (Paicpu(p)^.oper[2].typ = Top_None) Then
                                 hp1 := New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef), Paicpu(p)^.oper[1].reg))
                               Else
                                 hp1 := New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef), Paicpu(p)^.oper[2].reg));
                               InsertLLItem(AsmL,p^.previous, p^.next, hp1);
                               Dispose(p, Done);
                               p := hp1;
                            End;
                         5: Begin
                            {imul 5, reg1, reg2 to
                               lea (reg1,reg1,4), reg2
                             imul 5, reg1 to
                               lea (reg1,reg1,4), reg1}
                              TmpRef.base := Paicpu(p)^.oper[1].reg;
                              TmpRef.Index := Paicpu(p)^.oper[1].reg;
                              TmpRef.ScaleFactor := 4;
                              If (Paicpu(p)^.oper[2].typ = Top_None) Then
                                hp1 := New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef), Paicpu(p)^.oper[1].reg))
                              Else
                                hp1 := New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef), Paicpu(p)^.oper[2].reg));
                              InsertLLItem(AsmL,p^.previous, p^.next, hp1);
                              Dispose(p, Done);
                              p := hp1;
                            End;
                         6: Begin
                            {imul 6, reg1, reg2 to
                               lea (,reg1,2), reg2
                               lea (reg2,reg1,4), reg2
                             imul 6, reg1 to
                               lea (reg1,reg1,2), reg1
                               add reg1, reg1}
                              If (aktoptprocessor <= Class386)
                                Then
                                  Begin
                                    TmpRef.Index := Paicpu(p)^.oper[1].reg;
                                    If (Paicpu(p)^.oper[2].typ = Top_Reg)
                                      Then
                                        Begin
                                          TmpRef.base := Paicpu(p)^.oper[2].reg;
                                          TmpRef.ScaleFactor := 4;
                                          hp1 :=  New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef), Paicpu(p)^.oper[1].reg));
                                        End
                                      Else
                                        Begin
                                          hp1 :=  New(Paicpu, op_reg_reg(A_ADD, S_L,
                                            Paicpu(p)^.oper[1].reg,Paicpu(p)^.oper[1].reg));
                                        End;
                                    InsertLLItem(AsmL,p, p^.next, hp1);
                                    Reset_reference(tmpref);
                                    TmpRef.Index := Paicpu(p)^.oper[1].reg;
                                    TmpRef.ScaleFactor := 2;
                                    If (Paicpu(p)^.oper[2].typ = Top_Reg)
                                      Then
                                        Begin
                                          TmpRef.base := R_NO;
                                          hp1 :=  New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef),
                                            Paicpu(p)^.oper[2].reg));
                                        End
                                      Else
                                        Begin
                                          TmpRef.base := Paicpu(p)^.oper[1].reg;
                                          hp1 := New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef), Paicpu(p)^.oper[1].reg));
                                        End;
                                    InsertLLItem(AsmL,p^.previous, p^.next, hp1);
                                    Dispose(p, Done);
                                    p := Pai(hp1^.next);
                                  End
                            End;
                          9: Begin
                             {imul 9, reg1, reg2 to
                                lea (reg1,reg1,8), reg2
                              imul 9, reg1 to
                                lea (reg1,reg1,8), reg1}
                               TmpRef.base := Paicpu(p)^.oper[1].reg;
                               TmpRef.Index := Paicpu(p)^.oper[1].reg;
                               TmpRef.ScaleFactor := 8;
                               If (Paicpu(p)^.oper[2].typ = Top_None) Then
                                 hp1 := New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef), Paicpu(p)^.oper[1].reg))
                               Else
                                 hp1 := New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef), Paicpu(p)^.oper[2].reg));
                               InsertLLItem(AsmL,p^.previous, p^.next, hp1);
                               Dispose(p, Done);
                               p := hp1;
                             End;
                         10: Begin
                            {imul 10, reg1, reg2 to
                               lea (reg1,reg1,4), reg2
                               add reg2, reg2
                             imul 10, reg1 to
                               lea (reg1,reg1,4), reg1
                               add reg1, reg1}
                               If (aktoptprocessor <= Class386) Then
                                 Begin
                                   If (Paicpu(p)^.oper[2].typ = Top_Reg) Then
                                     hp1 :=  New(Paicpu, op_reg_reg(A_ADD, S_L,
                                       Paicpu(p)^.oper[2].reg,Paicpu(p)^.oper[2].reg))
                                   Else
                                     hp1 := New(Paicpu, op_reg_reg(A_ADD, S_L,
                                       Paicpu(p)^.oper[1].reg,Paicpu(p)^.oper[1].reg));
                                   InsertLLItem(AsmL,p, p^.next, hp1);
                                   TmpRef.base := Paicpu(p)^.oper[1].reg;
                                   TmpRef.Index := Paicpu(p)^.oper[1].reg;
                                   TmpRef.ScaleFactor := 4;
                                   If (Paicpu(p)^.oper[2].typ = Top_Reg)
                                     Then
                                       hp1 :=  New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef), Paicpu(p)^.oper[2].reg))
                                     Else
                                       hp1 :=  New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef), Paicpu(p)^.oper[1].reg));
                                   InsertLLItem(AsmL,p^.previous, p^.next, hp1);
                                   Dispose(p, Done);
                                   p := Pai(hp1^.next);
                                 End
                             End;
                         12: Begin
                            {imul 12, reg1, reg2 to
                               lea (,reg1,4), reg2
                               lea (,reg1,8) reg2
                             imul 12, reg1 to
                               lea (reg1,reg1,2), reg1
                               lea (,reg1,4), reg1}
                               If (aktoptprocessor <= Class386)
                                 Then
                                   Begin
                                     TmpRef.Index := Paicpu(p)^.oper[1].reg;
                                     If (Paicpu(p)^.oper[2].typ = Top_Reg) Then
                                       Begin
                                         TmpRef.base := Paicpu(p)^.oper[2].reg;
                                         TmpRef.ScaleFactor := 8;
                                         hp1 :=  New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef), Paicpu(p)^.oper[2].reg));
                                       End
                                     Else
                                       Begin
                                         TmpRef.base := R_NO;
                                         TmpRef.ScaleFactor := 4;
                                         hp1 :=  New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef), Paicpu(p)^.oper[1].reg));
                                       End;
                                     InsertLLItem(AsmL,p, p^.next, hp1);
                                     Reset_reference(tmpref);
                                     TmpRef.Index := Paicpu(p)^.oper[1].reg;
                                     If (Paicpu(p)^.oper[2].typ = Top_Reg) Then
                                       Begin
                                         TmpRef.base := R_NO;
                                         TmpRef.ScaleFactor := 4;
                                         hp1 :=  New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef), Paicpu(p)^.oper[2].reg));
                                       End
                                     Else
                                       Begin
                                         TmpRef.base := Paicpu(p)^.oper[1].reg;
                                         TmpRef.ScaleFactor := 2;
                                         hp1 :=  New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef), Paicpu(p)^.oper[1].reg));
                                       End;
                                     InsertLLItem(AsmL,p^.previous, p^.next, hp1);
                                     Dispose(p, Done);
                                     p := Pai(hp1^.next);
                                   End
                             End
                        End;
                      End;
                End;
              A_LEA:
                Begin
                {removes seg register prefixes from LEA operations, as they
                 don't do anything}
                 Paicpu(p)^.oper[0].ref^.Segment := R_NO;
                {changes "lea (%reg1), %reg2" into "mov %reg1, %reg2"}
                  If (Paicpu(p)^.oper[0].ref^.Base In [R_EAX..R_EDI]) And
                     (Paicpu(p)^.oper[0].ref^.Index = R_NO) And
                     (Not(Assigned(Paicpu(p)^.oper[0].ref^.Symbol))) Then
                    If (Paicpu(p)^.oper[0].ref^.Base <> Paicpu(p)^.oper[1].reg)
                       and (Paicpu(p)^.oper[0].ref^.Offset = 0)
                       Then
                        Begin
                          hp1 := New(Paicpu, op_reg_reg(A_MOV, S_L,Paicpu(p)^.oper[0].ref^.Base,
                            Paicpu(p)^.oper[1].reg));
                         InsertLLItem(AsmL,p^.previous,p^.next, hp1);
                         Dispose(p, Done);
                         p := hp1;
                         Continue;
                       End
                     Else
                      if (Paicpu(p)^.oper[0].ref^.Offset = 0) then
                       Begin
                         hp1 := Pai(p^.Next);
                         AsmL^.Remove(p);
                         Dispose(p, Done);
                         p := hp1;
                         Continue;
                       End
                      else
                        with Paicpu(p)^.oper[0].ref^ do
                          if (Base = Paicpu(p)^.oper[1].reg) then
                            begin
                              l := offset+offsetfixup;
                              case l of
                                1,-1:
                                  begin
                                    if l = 1 then
                                      paicpu(p)^.opcode := A_INC
                                    else paicpu(p)^.opcode := A_DEC;
                                    paicpu(p)^.loadreg(0,Paicpu(p)^.oper[1].reg);
                                    paicpu(p)^.ops := 1;
                                  end;
                                else
                                  begin
                                    paicpu(p)^.opcode := A_ADD;
                                    paicpu(p)^.loadconst(0,offset+offsetfixup);
                                  end;
                              end;
                            end;

                End;
              A_MOV:
                Begin
                  TmpUsedRegs := UsedRegs;
                  If (Paicpu(p)^.oper[1].typ = top_reg) And
                     (Paicpu(p)^.oper[1].reg In [R_EAX, R_EBX, R_EDX, R_EDI]) And
                     GetNextInstruction(p, hp1) And
                     (Pai(hp1)^.typ = ait_instruction) And
                     (Paicpu(hp1)^.opcode = A_MOV) And
                     (Paicpu(hp1)^.oper[0].typ = top_reg) And
                     (Paicpu(hp1)^.oper[0].reg = Paicpu(p)^.oper[1].reg)
                    Then
                {we have "mov x, %treg; mov %treg, y}
                      If not(RegUsedAfterInstruction(Paicpu(p)^.oper[1].reg, hp1, TmpUsedRegs)) then
                {we've got "mov x, %treg; mov %treg, y; with %treg is not used after }
                          Case Paicpu(p)^.oper[0].typ Of
                            top_reg:
                              Begin
                                { change "mov %reg, %treg; mov %treg, y"
                                  to "mov %reg, y" }
                                Paicpu(p)^.LoadOper(1,Paicpu(hp1)^.oper[1]);
                                AsmL^.Remove(hp1);
                                Dispose(hp1, Done);
                                continue;
                              End;
                            top_ref:
                              If (Paicpu(hp1)^.oper[1].typ = top_reg) Then
                               Begin
                                 { change "mov mem, %treg; mov %treg, %reg"
                                   to "mov mem, %reg" }
                                 Paicpu(p)^.Loadoper(1,Paicpu(hp1)^.oper[1]);
                                 AsmL^.Remove(hp1);
                                 Dispose(hp1, Done);
                                 continue;
                               End;
                          End
                        Else
                    Else
                  {Change "mov %reg1, %reg2; xxx %reg2, ???" to
                   "mov %reg1, %reg2; xxx %reg1, ???" to avoid a write/read
                   penalty}
                      If (Paicpu(p)^.oper[0].typ = top_reg) And
                         (Paicpu(p)^.oper[1].typ = top_reg) And
                         GetNextInstruction(p,hp1) And
                         (Pai(hp1)^.typ = ait_instruction) And
                         (Paicpu(hp1)^.oper[0].typ = top_reg) And
                         (Paicpu(hp1)^.oper[0].reg = Paicpu(p)^.oper[1].reg)
                        Then
                  {we have "mov %reg1, %reg2; XXX %reg2, ???"}
                          Begin
                            If ((Paicpu(hp1)^.opcode = A_OR) Or
                                (Paicpu(hp1)^.opcode = A_TEST)) And
                               (Paicpu(hp1)^.oper[1].typ = top_reg) And
                               (Paicpu(hp1)^.oper[0].reg = Paicpu(hp1)^.oper[1].reg)
                              Then
                   {we have "mov %reg1, %reg2; test/or %reg2, %reg2"}
                                Begin
                                  TmpUsedRegs := UsedRegs;
                                  { reg1 will be used after the first instruction, }
                                  { so update the allocation info                  }
                                  allocRegBetween(asmL,paicpu(p)^.oper[0].reg,p,hp1);
                                  If GetNextInstruction(hp1, hp2) And
                                     (hp2^.typ = ait_instruction) And
                                     paicpu(hp2)^.is_jmp and
                                     Not(RegUsedAfterInstruction(Paicpu(hp1)^.oper[0].reg, hp1, TmpUsedRegs))
                                    Then
                   {change "mov %reg1, %reg2; test/or %reg2, %reg2; jxx" to
                    "test %reg1, %reg1; jxx"}
                                      Begin
                                        Paicpu(hp1)^.Loadoper(0,Paicpu(p)^.oper[0]);
                                        Paicpu(hp1)^.Loadoper(1,Paicpu(p)^.oper[0]);
                                        AsmL^.Remove(p);
                                        Dispose(p, done);
                                        p := hp1;
                                        continue
                                      End
                                    Else
                   {change "mov %reg1, %reg2; test/or %reg2, %reg2" to
                    "mov %reg1, %reg2; test/or %reg1, %reg1"}
                                      Begin
                                        Paicpu(hp1)^.Loadoper(0,Paicpu(p)^.oper[0]);
                                        Paicpu(hp1)^.Loadoper(1,Paicpu(p)^.oper[0]);
                                      End;
                                End
{                              Else
                                If (Paicpu(p^.next)^.opcode
                                   In [A_PUSH, A_OR, A_XOR, A_AND, A_TEST])}
                         {change "mov %reg1, %reg2; push/or/xor/... %reg2, ???" to
                          "mov %reg1, %reg2; push/or/xor/... %reg1, ???"}
                          End
                        Else
                  {leave out the mov from "mov reg, x(%frame_pointer); leave/ret" (with
                   x >= RetOffset) as it doesn't do anything (it writes either to a
                   parameter or to the temporary storage room for the function
                   result)}
                          If GetNextInstruction(p, hp1) And
                             (Pai(hp1)^.typ = ait_instruction)
                            Then
                              If ((Paicpu(hp1)^.opcode = A_LEAVE) Or
                                  (Paicpu(hp1)^.opcode = A_RET)) And
                                 (Paicpu(p)^.oper[1].typ = top_ref) And
                                 (Paicpu(p)^.oper[1].ref^.base = procinfo^.FramePointer) And
                                 (Paicpu(p)^.oper[1].ref^.offset >= procinfo^.Return_Offset) And
                                 (Paicpu(p)^.oper[1].ref^.index = R_NO) And
                                 (Paicpu(p)^.oper[0].typ = top_reg)
                                Then
                                  Begin
                                   AsmL^.Remove(p);
                                   Dispose(p, done);
                                   p := hp1;
                                   RemoveLastDeallocForFuncRes(asmL,p);
                                 End
                               Else
                                 If (Paicpu(p)^.oper[0].typ = top_reg) And
                                    (Paicpu(p)^.oper[1].typ = top_ref) And
                                    (Paicpu(p)^.opsize = Paicpu(hp1)^.opsize) And
                                    (Paicpu(hp1)^.opcode = A_CMP) And
                                    (Paicpu(hp1)^.oper[1].typ = top_ref) And
                                    RefsEqual(Paicpu(p)^.oper[1].ref^, Paicpu(hp1)^.oper[1].ref^) Then
            {change "mov reg1, mem1; cmp x, mem1" to "mov reg, mem1; cmp x, reg1"}
                                   begin
                                     Paicpu(hp1)^.loadreg(1,Paicpu(p)^.oper[0].reg);
                                     allocRegBetween(asmL,paicpu(p)^.oper[0].reg,p,hp1);
                                   end;
                { Next instruction is also a MOV ? }
                  If GetNextInstruction(p, hp1) And
                     (pai(hp1)^.typ = ait_instruction) and
                     (Paicpu(hp1)^.opcode = A_MOV) and
                     (Paicpu(hp1)^.opsize = Paicpu(p)^.opsize)
                  Then
                      Begin
                        If (Paicpu(hp1)^.oper[0].typ = Paicpu(p)^.oper[1].typ) and
                           (Paicpu(hp1)^.oper[1].typ = Paicpu(p)^.oper[0].typ)
                          Then
                            {mov reg1, mem1     or     mov mem1, reg1
                             mov mem2, reg2            mov reg2, mem2}
                            Begin
                              If OpsEqual(Paicpu(hp1)^.oper[1],Paicpu(p)^.oper[0]) Then
                            {mov reg1, mem1     or     mov mem1, reg1
                             mov mem2, reg1            mov reg2, mem1}
                                Begin
                                  If OpsEqual(Paicpu(hp1)^.oper[0],Paicpu(p)^.oper[1]) Then
                        { Removes the second statement from
                            mov reg1, mem1/reg2
                            mov mem1/reg2, reg1 }
                                    Begin
                                      if (paicpu(p)^.oper[0].typ = top_reg) then
                                        AllocRegBetween(asmL,paicpu(p)^.oper[0].reg,p,hp1);
                                      AsmL^.remove(hp1);
                                      Dispose(hp1,done);
                                    End
                                  Else
                                    Begin
                                      TmpUsedRegs := UsedRegs;
                                      UpdateUsedRegs(TmpUsedRegs, Pai(hp1^.next));
                                      If (Paicpu(p)^.oper[0].typ = top_reg) And
                                        { mov reg1, mem1
                                          mov mem2, reg1 }
                                         GetNextInstruction(hp1, hp2) And
                                         (hp2^.typ = ait_instruction) And
                                         (Paicpu(hp2)^.opcode = A_CMP) And
                                         (Paicpu(hp2)^.opsize = Paicpu(p)^.opsize) and
                                         (Paicpu(hp2)^.oper[0].typ = TOp_Ref) And
                                         (Paicpu(hp2)^.oper[1].typ = TOp_Reg) And
                                         RefsEqual(Paicpu(hp2)^.oper[0].ref^, Paicpu(p)^.oper[1].ref^) And
                                         (Paicpu(hp2)^.oper[1].reg = Paicpu(p)^.oper[0].reg) And
                                         Not(RegUsedAfterInstruction(Paicpu(p)^.oper[0].reg, hp2, TmpUsedRegs)) Then
                           { change                   to
                              mov reg1, mem1           mov reg1, mem1
                              mov mem2, reg1           cmp reg1, mem2
                              cmp mem1, reg1                          }
                                        Begin
                                          AsmL^.Remove(hp2);
                                          Dispose(hp2, Done);
                                          Paicpu(hp1)^.opcode := A_CMP;
                                          Paicpu(hp1)^.loadref(1,newreference(Paicpu(hp1)^.oper[0].ref^));
                                          Paicpu(hp1)^.loadreg(0,Paicpu(p)^.oper[0].reg);
                                        End;
                                    End;
                                End
                              Else
                                Begin
                                  tmpUsedRegs := UsedRegs;
                                  If GetNextInstruction(hp1, hp2) And
                                     (Paicpu(p)^.oper[0].typ = top_ref) And
                                     (Paicpu(p)^.oper[1].typ = top_reg) And
                                     (Paicpu(hp1)^.oper[0].typ = top_reg) And
                                     (Paicpu(hp1)^.oper[0].reg = Paicpu(p)^.oper[1].reg) And
                                     (Paicpu(hp1)^.oper[1].typ = top_ref) And
                                     (Pai(hp2)^.typ = ait_instruction) And
                                     (Paicpu(hp2)^.opcode = A_MOV) And
                                     (Paicpu(hp2)^.opsize = Paicpu(p)^.opsize) and
                                     (Paicpu(hp2)^.oper[1].typ = top_reg) And
                                     (Paicpu(hp2)^.oper[0].typ = top_ref) And
                                     RefsEqual(Paicpu(hp2)^.oper[0].ref^, Paicpu(hp1)^.oper[1].ref^)  Then
                                    If not regInRef(Paicpu(hp2)^.oper[1].reg,Paicpu(hp2)^.oper[0].ref^) and
                                       (Paicpu(p)^.oper[1].reg in [R_DI,R_EDI]) and
                                       not(RegUsedAfterInstruction(R_EDI,hp1,tmpUsedRegs)) Then
                             {   mov mem1, %edi
                                 mov %edi, mem2
                                 mov mem2, reg2
                              to:
                                 mov mem1, reg2
                                 mov reg2, mem2}
                                      Begin
                                        Paicpu(p)^.Loadoper(1,Paicpu(hp2)^.oper[1]);
                                        Paicpu(hp1)^.loadoper(0,Paicpu(hp2)^.oper[1]);
                                        AsmL^.Remove(hp2);
                                        Dispose(hp2,Done);
                                      End
                                    Else
                                      If (Paicpu(p)^.oper[1].reg <> Paicpu(hp2)^.oper[1].reg) And
                                         not(RegInRef(Paicpu(p)^.oper[1].reg,Paicpu(p)^.oper[0].ref^)) And
                                         not(RegInRef(Paicpu(hp2)^.oper[1].reg,Paicpu(hp2)^.oper[0].ref^))
                                        Then
                           {   mov mem1, reg1         mov mem1, reg1
                               mov reg1, mem2         mov reg1, mem2
                               mov mem2, reg2         mov mem2, reg1
                            to:                    to:
                               mov mem1, reg1         mov mem1, reg1
                               mov mem1, reg2         mov reg1, mem2
                               mov reg1, mem2

                         or (if mem1 depends on reg1
                             and/or if mem2 depends on reg2)
                            to:
                               mov mem1, reg1
                               mov reg1, mem2
                               mov reg1, reg2
                         }
                                        Begin
                                          Paicpu(hp1)^.LoadRef(0,newreference(Paicpu(p)^.oper[0].ref^));
                                          Paicpu(hp1)^.LoadReg(1,Paicpu(hp2)^.oper[1].reg);
                                          Paicpu(hp2)^.LoadRef(1,newreference(Paicpu(hp2)^.oper[0].ref^));
                                          Paicpu(hp2)^.LoadReg(0,Paicpu(p)^.oper[1].reg);
                                          allocRegBetween(asmL,paicpu(p)^.oper[1].reg,p,hp2);
                                          if (paicpu(p)^.oper[0].ref^.base in (usableregs+[R_EDI])) then
                                            allocRegBetween(asmL,paicpu(p)^.oper[0].ref^.base,p,hp2);
                                          if (paicpu(p)^.oper[0].ref^.index in (usableregs+[R_EDI])) then
                                            allocRegBetween(asmL,paicpu(p)^.oper[0].ref^.index,p,hp2);
                                        End
                                      Else
                                        If (Paicpu(hp1)^.Oper[0].reg <> Paicpu(hp2)^.Oper[1].reg) Then
                                          begin
                                            Paicpu(hp2)^.LoadReg(0,Paicpu(hp1)^.Oper[0].reg);
                                            allocRegBetween(asmL,paicpu(p)^.oper[1].reg,p,hp2);
                                          end
                                        else
                                          begin
                                            asmL^.Remove(hp2);
                                            dispose(hp2, done);
                                          end
                                End;
                            End
                          Else
(*                          {movl [mem1],reg1
                             movl [mem1],reg2
                            to:
                              movl [mem1],reg1
                              movl reg1,reg2 }
                            If (Paicpu(p)^.oper[0].typ = top_ref) and
                               (Paicpu(p)^.oper[1].typ = top_reg) and
                               (Paicpu(hp1)^.oper[0].typ = top_ref) and
                               (Paicpu(hp1)^.oper[1].typ = top_reg) and
                               (Paicpu(p)^.opsize = Paicpu(hp1)^.opsize) and
                               RefsEqual(TReference(Paicpu(p)^.oper[0]^),Paicpu(hp1)^.oper[0]^.ref^) and
                               (Paicpu(p)^.oper[1].reg<>Paicpu(hp1)^.oper[0]^.ref^.base) and
                               (Paicpu(p)^.oper[1].reg<>Paicpu(hp1)^.oper[0]^.ref^.index) then
                              Paicpu(hp1)^.LoadReg(0,Paicpu(p)^.oper[1].reg)
                            Else*)
                            {   movl const1,[mem1]
                                movl [mem1],reg1
                             to:
                                movl const1,reg1
                                movl reg1,[mem1] }
                              If (Paicpu(p)^.oper[0].typ = top_const) and
                                 (Paicpu(p)^.oper[1].typ = top_ref) and
                                 (Paicpu(hp1)^.oper[0].typ = top_ref) and
                                 (Paicpu(hp1)^.oper[1].typ = top_reg) and
                                 (Paicpu(p)^.opsize = Paicpu(hp1)^.opsize) and
                                 RefsEqual(Paicpu(hp1)^.oper[0].ref^,Paicpu(p)^.oper[1].ref^) then
                                Begin
                                  allocregbetween(asml,Paicpu(hp1)^.oper[1].reg,p,hp1);
                                  { allocregbetween doesn't insert this because at }
                                  { this time, no regalloc info is available in    }
                                  { the optinfo field, so do it manually (JM)      }
                                  hp2 := new(paiRegalloc,alloc(Paicpu(hp1)^.oper[1].reg));
                                  insertllitem(asml,p^.previous,p,hp2);
                                  Paicpu(hp1)^.LoadReg(0,Paicpu(hp1)^.oper[1].reg);
                                  Paicpu(hp1)^.LoadRef(1,newreference(Paicpu(p)^.oper[1].ref^));
                                  Paicpu(p)^.LoadReg(1,Paicpu(hp1)^.oper[0].reg);
                                End
                      End;
                End;
              A_MOVZX:
                Begin
                {removes superfluous And's after movzx's}
                  If (Paicpu(p)^.oper[1].typ = top_reg) And
                     GetNextInstruction(p, hp1) And
                     (Pai(hp1)^.typ = ait_instruction) And
                     (Paicpu(hp1)^.opcode = A_AND) And
                     (Paicpu(hp1)^.oper[0].typ = top_const) And
                     (Paicpu(hp1)^.oper[1].typ = top_reg) And
                     (Paicpu(hp1)^.oper[1].reg = Paicpu(p)^.oper[1].reg)
                    Then
                      Case Paicpu(p)^.opsize Of
                        S_BL, S_BW:
                          If (Paicpu(hp1)^.oper[0].val = $ff) Then
                            Begin
                              AsmL^.Remove(hp1);
                              Dispose(hp1, Done);
                            End;
                        S_WL:
                          If (Paicpu(hp1)^.oper[0].val = $ffff) Then
                            Begin
                              AsmL^.Remove(hp1);
                              Dispose(hp1, Done);
                            End;
                      End;
                {changes some movzx constructs to faster synonims (all examples
                 are given with eax/ax, but are also valid for other registers)}
                  If (Paicpu(p)^.oper[1].typ = top_reg) Then
                    If (Paicpu(p)^.oper[0].typ = top_reg) Then
                      Case Paicpu(p)^.opsize of
                        S_BW:
                          Begin
                            If (Paicpu(p)^.oper[0].reg = Reg16ToReg8(Paicpu(p)^.oper[1].reg)) And
                               Not(CS_LittleSize In aktglobalswitches)
                              Then
                                {Change "movzbw %al, %ax" to "andw $0x0ffh, %ax"}
                                Begin
                                  Paicpu(p)^.opcode := A_AND;
                                  Paicpu(p)^.changeopsize(S_W);
                                  Paicpu(p)^.LoadConst(0,$ff);
                                End
                              Else
                                If GetNextInstruction(p, hp1) And
                                   (Pai(hp1)^.typ = ait_instruction) And
                                   (Paicpu(hp1)^.opcode = A_AND) And
                                   (Paicpu(hp1)^.oper[0].typ = top_const) And
                                   (Paicpu(hp1)^.oper[1].typ = top_reg) And
                                   (Paicpu(hp1)^.oper[1].reg = Paicpu(p)^.oper[1].reg)
                                  Then
                                    {Change "movzbw %reg1, %reg2; andw $const, %reg2"
                                     to "movw %reg1, reg2; andw $(const1 and $ff), %reg2"}
                                    Begin
                                      Paicpu(p)^.opcode := A_MOV;
                                      Paicpu(p)^.changeopsize(S_W);
                                      Paicpu(p)^.LoadReg(0,Reg8ToReg16(Paicpu(p)^.oper[0].reg));
                                      Paicpu(hp1)^.LoadConst(0,Paicpu(hp1)^.oper[0].val And $ff);
                                    End;
                          End;
                        S_BL:
                          Begin
                            If (Paicpu(p)^.oper[0].reg = Reg32ToReg8(Paicpu(p)^.oper[1].reg)) And
                               Not(CS_LittleSize in aktglobalswitches)
                              Then
                                {Change "movzbl %al, %eax" to "andl $0x0ffh, %eax"}
                                Begin
                                  Paicpu(p)^.opcode := A_AND;
                                  Paicpu(p)^.changeopsize(S_L);
                                  Paicpu(p)^.loadconst(0,$ff)
                                End
                              Else
                                If GetNextInstruction(p, hp1) And
                                   (Pai(hp1)^.typ = ait_instruction) And
                                   (Paicpu(hp1)^.opcode = A_AND) And
                                   (Paicpu(hp1)^.oper[0].typ = top_const) And
                                   (Paicpu(hp1)^.oper[1].typ = top_reg) And
                                   (Paicpu(hp1)^.oper[1].reg = Paicpu(p)^.oper[1].reg)
                                  Then
                                   {Change "movzbl %reg1, %reg2; andl $const, %reg2"
                                    to "movl %reg1, reg2; andl $(const1 and $ff), %reg2"}
                                    Begin
                                      Paicpu(p)^.opcode := A_MOV;
                                      Paicpu(p)^.changeopsize(S_L);
                                      Paicpu(p)^.LoadReg(0,Reg8ToReg32(Paicpu(p)^.oper[0].reg));
                                      Paicpu(hp1)^.LoadConst(0,Paicpu(hp1)^.oper[0].val And $ff);
                                    End
                          End;
                        S_WL:
                          Begin
                            If (Paicpu(p)^.oper[0].reg = Reg32ToReg16(Paicpu(p)^.oper[1].reg)) And
                               Not(CS_LittleSize In aktglobalswitches)
                              Then
                               {Change "movzwl %ax, %eax" to "andl $0x0ffffh, %eax"}
                                Begin
                                  Paicpu(p)^.opcode := A_AND;
                                  Paicpu(p)^.changeopsize(S_L);
                                  Paicpu(p)^.LoadConst(0,$ffff);
                                End
                              Else
                                If GetNextInstruction(p, hp1) And
                                   (Pai(hp1)^.typ = ait_instruction) And
                                   (Paicpu(hp1)^.opcode = A_AND) And
                                   (Paicpu(hp1)^.oper[0].typ = top_const) And
                                   (Paicpu(hp1)^.oper[1].typ = top_reg) And
                                   (Paicpu(hp1)^.oper[1].reg = Paicpu(p)^.oper[1].reg)
                                  Then
                                    {Change "movzwl %reg1, %reg2; andl $const, %reg2"
                                     to "movl %reg1, reg2; andl $(const1 and $ffff), %reg2"}
                                    Begin
                                      Paicpu(p)^.opcode := A_MOV;
                                      Paicpu(p)^.changeopsize(S_L);
                                      Paicpu(p)^.LoadReg(0,Reg16ToReg32(Paicpu(p)^.oper[0].reg));
                                      Paicpu(hp1)^.LoadConst(0,Paicpu(hp1)^.oper[0].val And $ffff);
                                    End;
                          End;
                        End
                      Else
                        If (Paicpu(p)^.oper[0].typ = top_ref) Then
                          Begin
                            If GetNextInstruction(p, hp1) And
                               (Pai(hp1)^.typ = ait_instruction) And
                               (Paicpu(hp1)^.opcode = A_AND) And
                               (Paicpu(hp1)^.oper[0].typ = Top_Const) And
                               (Paicpu(hp1)^.oper[1].typ = Top_Reg) And
                               (Paicpu(hp1)^.oper[1].reg = Paicpu(p)^.oper[1].reg) Then
                              Begin
                                Paicpu(p)^.opcode := A_MOV;
                                Case Paicpu(p)^.opsize Of
                                  S_BL:
                                    Begin
                                      Paicpu(p)^.changeopsize(S_L);
                                      Paicpu(hp1)^.LoadConst(0,Paicpu(hp1)^.oper[0].val And $ff);
                                    End;
                                  S_WL:
                                    Begin
                                      Paicpu(p)^.changeopsize(S_L);
                                      Paicpu(hp1)^.LoadConst(0,Paicpu(hp1)^.oper[0].val And $ffff);
                                    End;
                                  S_BW:
                                    Begin
                                      Paicpu(p)^.changeopsize(S_W);
                                      Paicpu(hp1)^.LoadConst(0,Paicpu(hp1)^.oper[0].val And $ff);
                                    End;
                                End;
                              End;
                          End;
                End;
              A_POP:
                Begin
                  if target_info.target=target_i386_go32v2 then
                   begin
                     { Transform a series of pop/pop/pop/push/push/push to }
                     { 'movl x(%esp),%reg' for go32v2 (not for the rest,   }
                     { because I'm not sure whether they can cope with     }
                     { 'movl x(%esp),%reg' with x > 0, I believe we had    }
                     { such a problem when using esp as frame pointer (JM) }
                     if (Paicpu(p)^.oper[0].typ = top_reg) then
                       begin
                         hp1 := p;
                         hp2 := p;
                         l := 0;
                         while getNextInstruction(hp1,hp1) and
                               (hp1^.typ = ait_instruction) and
                               (paicpu(hp1)^.opcode = A_POP) and
                               (paicpu(hp1)^.oper[0].typ = top_reg) do
                           begin
                             hp2 := hp1;
                             inc(l,4);
                           end;
                         getLastInstruction(p,hp3);
                         l1 := 0;
                         while (hp2 <> hp3) and
                               assigned(hp1) and
                               (hp1^.typ = ait_instruction) and
                               (paicpu(hp1)^.opcode = A_PUSH) and
                               (paicpu(hp1)^.oper[0].typ = top_reg) and
                               (paicpu(hp1)^.oper[0].reg = paicpu(hp2)^.oper[0].reg) do
                           begin
                             { change it to a two op operation }
                             paicpu(hp2)^.oper[1].typ:=top_none;
                             paicpu(hp2)^.ops:=2;
                             paicpu(hp2)^.opcode := A_MOV;
                             paicpu(hp2)^.Loadoper(1,paicpu(hp1)^.oper[0]);
                             reset_reference(tmpref);
                             tmpRef.base := stack_pointer;
                             tmpRef.offset := l;
                             paicpu(hp2)^.loadRef(0,newReference(tmpRef));
                             hp4 := hp1;
                             getNextInstruction(hp1,hp1);
                             asmL^.remove(hp4);
                             dispose(hp4,done);
                             getLastInstruction(hp2,hp2);
                             dec(l,4);
                             inc(l1);
                           end;
                         if l <> -4 then
                           begin
                             inc(l,4);
                             for l1 := l1 downto 1 do
                               begin
                                 getNextInstruction(hp2,hp2);
                                 dec(paicpu(hp2)^.oper[0].ref^.offset,l);
                               end
                           end
                       end
                    end
                   else
                    begin
                      if (Paicpu(p)^.oper[0].typ = top_reg) And
                         GetNextInstruction(p, hp1) And
                         (pai(hp1)^.typ=ait_instruction) and
                         (Paicpu(hp1)^.opcode=A_PUSH) and
                         (Paicpu(hp1)^.oper[0].typ = top_reg) And
                         (Paicpu(hp1)^.oper[0].reg=Paicpu(p)^.oper[0].reg) then
                        Begin
                          { change it to a two op operation }
                          Paicpu(p)^.oper[1].typ:=top_none;
                          Paicpu(p)^.ops:=2;
                          Paicpu(p)^.opcode := A_MOV;
                          Paicpu(p)^.Loadoper(1,Paicpu(p)^.oper[0]);
                          Reset_reference(tmpref);
                          TmpRef.base := R_ESP;
                          Paicpu(p)^.LoadRef(0,newReference(TmpRef));
                          AsmL^.Remove(hp1);
                          Dispose(hp1, Done)
                        End;
                    end;
                end;
              A_PUSH:
                Begin
                  If (Paicpu(p)^.opsize = S_W) And
                     (Paicpu(p)^.oper[0].typ = Top_Const) And
                     GetNextInstruction(p, hp1) And
                     (Pai(hp1)^.typ = ait_instruction) And
                     (Paicpu(hp1)^.opcode = A_PUSH) And
                     (Paicpu(hp1)^.oper[0].typ = Top_Const) And
                     (Paicpu(hp1)^.opsize = S_W) Then
                    Begin
                      Paicpu(p)^.changeopsize(S_L);
                      Paicpu(p)^.LoadConst(0,Paicpu(p)^.oper[0].val shl 16 + word(Paicpu(hp1)^.oper[0].val));
                      AsmL^.Remove(hp1);
                      Dispose(hp1, Done)
                    End;
                End;
              A_SHL, A_SAL:
                Begin
                  If (Paicpu(p)^.oper[0].typ = Top_Const) And
                     (Paicpu(p)^.oper[1].typ = Top_Reg) And
                     (Paicpu(p)^.opsize = S_L) And
                     (Paicpu(p)^.oper[0].val <= 3)
                {Changes "shl const, %reg32; add const/reg, %reg32" to one lea statement}
                    Then
                      Begin
                        TmpBool1 := True; {should we check the next instruction?}
                        TmpBool2 := False; {have we found an add/sub which could be
                                            integrated in the lea?}
                        Reset_reference(tmpref);
                        TmpRef.index := Paicpu(p)^.oper[1].reg;
                        TmpRef.scalefactor := 1 shl Paicpu(p)^.oper[0].val;
                        While TmpBool1 And
                              GetNextInstruction(p, hp1) And
                              (Pai(hp1)^.typ = ait_instruction) And
                              ((Paicpu(hp1)^.opcode = A_ADD) Or
                               (Paicpu(hp1)^.opcode = A_SUB)) And
                              (Paicpu(hp1)^.oper[1].typ = Top_Reg) And
                              (Paicpu(hp1)^.oper[1].reg = Paicpu(p)^.oper[1].reg) Do
                          Begin
                            TmpBool1 := False;
                            If (Paicpu(hp1)^.oper[0].typ = Top_Const)
                              Then
                                Begin
                                  TmpBool1 := True;
                                  TmpBool2 := True;
                                  If Paicpu(hp1)^.opcode = A_ADD Then
                                    Inc(TmpRef.offset, Paicpu(hp1)^.oper[0].val)
                                  Else
                                    Dec(TmpRef.offset, Paicpu(hp1)^.oper[0].val);
                                  AsmL^.Remove(hp1);
                                  Dispose(hp1, Done);
                                End
                              Else
                                If (Paicpu(hp1)^.oper[0].typ = Top_Reg) And
                                   (Paicpu(hp1)^.opcode = A_ADD) And
                                   (TmpRef.base = R_NO) Then
                                  Begin
                                    TmpBool1 := True;
                                    TmpBool2 := True;
                                    TmpRef.base := Paicpu(hp1)^.oper[0].reg;
                                    AsmL^.Remove(hp1);
                                    Dispose(hp1, Done);
                                  End;
                          End;
                        If TmpBool2 Or
                           ((aktoptprocessor < ClassP6) And
                            (Paicpu(p)^.oper[0].val <= 3) And
                            Not(CS_LittleSize in aktglobalswitches))
                          Then
                            Begin
                              If Not(TmpBool2) And
                                 (Paicpu(p)^.oper[0].val = 1)
                                Then
                                  Begin
                                    hp1 := new(Paicpu,op_reg_reg(A_ADD,Paicpu(p)^.opsize,
                                               Paicpu(p)^.oper[1].reg, Paicpu(p)^.oper[1].reg))
                                  End
                                Else hp1 := New(Paicpu, op_ref_reg(A_LEA, S_L, newReference(TmpRef),
                                                Paicpu(p)^.oper[1].reg));
                              InsertLLItem(AsmL,p^.previous, p^.next, hp1);
                              Dispose(p, Done);
                              p := hp1;
                            End;
                      End
                    Else
                      If (aktoptprocessor < ClassP6) And
                         (Paicpu(p)^.oper[0].typ = top_const) And
                         (Paicpu(p)^.oper[1].typ = top_reg) Then
                        If (Paicpu(p)^.oper[0].val = 1)
                          Then
  {changes "shl $1, %reg" to "add %reg, %reg", which is the same on a 386,
   but faster on a 486, and pairable in both U and V pipes on the Pentium
   (unlike shl, which is only pairable in the U pipe)}
                            Begin
                              hp1 := new(Paicpu,op_reg_reg(A_ADD,Paicpu(p)^.opsize,
                                         Paicpu(p)^.oper[1].reg, Paicpu(p)^.oper[1].reg));
                              InsertLLItem(AsmL,p^.previous, p^.next, hp1);
                              Dispose(p, done);
                              p := hp1;
                            End
                          Else If (Paicpu(p)^.opsize = S_L) and
                                  (Paicpu(p)^.oper[0].val<= 3) Then
                    {changes "shl $2, %reg" to "lea (,%reg,4), %reg"
                             "shl $3, %reg" to "lea (,%reg,8), %reg}
                                 Begin
                                   Reset_reference(tmpref);
                                   TmpRef.index := Paicpu(p)^.oper[1].reg;
                                   TmpRef.scalefactor := 1 shl Paicpu(p)^.oper[0].val;
                                   hp1 := new(Paicpu,op_ref_reg(A_LEA,S_L,newReference(TmpRef), Paicpu(p)^.oper[1].reg));
                                   InsertLLItem(AsmL,p^.previous, p^.next, hp1);
                                   Dispose(p, done);
                                   p := hp1;
                                 End
                End;
              A_SAR, A_SHR:
                  {changes the code sequence
                   shr/sar const1, x
                   shl     const2, x
                   to either "sar/and", "shl/and" or just "and" depending on const1 and const2}
                Begin
                  If GetNextInstruction(p, hp1) And
                     (pai(hp1)^.typ = ait_instruction) and
                     (Paicpu(hp1)^.opcode = A_SHL) and
                     (Paicpu(p)^.oper[0].typ = top_const) and
                     (Paicpu(hp1)^.oper[0].typ = top_const) and
                     (Paicpu(hp1)^.opsize = Paicpu(p)^.opsize) And
                     (Paicpu(hp1)^.oper[1].typ = Paicpu(p)^.oper[1].typ) And
                     OpsEqual(Paicpu(hp1)^.oper[1], Paicpu(p)^.oper[1])
                    Then
                      If (Paicpu(p)^.oper[0].val > Paicpu(hp1)^.oper[0].val) And
                         Not(CS_LittleSize In aktglobalswitches)
                        Then
                   { shr/sar const1, %reg
                     shl     const2, %reg
                      with const1 > const2 }
                          Begin
                            Paicpu(p)^.LoadConst(0,Paicpu(p)^.oper[0].val-Paicpu(hp1)^.oper[0].val);
                            Paicpu(hp1)^.opcode := A_AND;
                            l := (1 shl (Paicpu(hp1)^.oper[0].val)) - 1;
                            Case Paicpu(p)^.opsize Of
                              S_L: Paicpu(hp1)^.LoadConst(0,l Xor longint(-1));
                              S_B: Paicpu(hp1)^.LoadConst(0,l Xor $ff);
                              S_W: Paicpu(hp1)^.LoadConst(0,l Xor $ffff);
                            End;
                          End
                        Else
                          If (Paicpu(p)^.oper[0].val<Paicpu(hp1)^.oper[0].val) And
                             Not(CS_LittleSize In aktglobalswitches)
                            Then
                   { shr/sar const1, %reg
                     shl     const2, %reg
                      with const1 < const2 }
                              Begin
                                Paicpu(hp1)^.LoadConst(0,Paicpu(hp1)^.oper[0].val-Paicpu(p)^.oper[0].val);
                                Paicpu(p)^.opcode := A_AND;
                                l := (1 shl (Paicpu(p)^.oper[0].val))-1;
                                Case Paicpu(p)^.opsize Of
                                  S_L: Paicpu(p)^.LoadConst(0,l Xor $ffffffff);
                                  S_B: Paicpu(p)^.LoadConst(0,l Xor $ff);
                                  S_W: Paicpu(p)^.LoadConst(0,l Xor $ffff);
                                End;
                              End
                            Else
                   { shr/sar const1, %reg
                     shl     const2, %reg
                      with const1 = const2 }
                              if (Paicpu(p)^.oper[0].val = Paicpu(hp1)^.oper[0].val) then
                                Begin
                                  Paicpu(p)^.opcode := A_AND;
                                  l := (1 shl (Paicpu(p)^.oper[0].val))-1;
                                  Case Paicpu(p)^.opsize Of
                                    S_B: Paicpu(p)^.LoadConst(0,l Xor $ff);
                                    S_W: Paicpu(p)^.LoadConst(0,l Xor $ffff);
                                    S_L: Paicpu(p)^.LoadConst(0,l Xor $ffffffff);
                                  End;
                                  AsmL^.remove(hp1);
                                  dispose(hp1, done);
                                End;
                End;
              A_SETcc :
                { changes
                    setcc (funcres)             setcc reg
                    movb (funcres), reg      to leave/ret
                    leave/ret                               }
                Begin
                  If (Paicpu(p)^.oper[0].typ = top_ref) And
                     GetNextInstruction(p, hp1) And
                     GetNextInstruction(hp1, hp2) And
                     (hp2^.typ = ait_instruction) And
                     ((Paicpu(hp2)^.opcode = A_LEAVE) or
                      (Paicpu(hp2)^.opcode = A_RET)) And
                     (Paicpu(p)^.oper[0].ref^.Base = procinfo^.FramePointer) And
                     (Paicpu(p)^.oper[0].ref^.Index = R_NO) And
                     (Paicpu(p)^.oper[0].ref^.Offset >= procinfo^.Return_Offset) And
                     (hp1^.typ = ait_instruction) And
                     (Paicpu(hp1)^.opcode = A_MOV) And
                     (Paicpu(hp1)^.opsize = S_B) And
                     (Paicpu(hp1)^.oper[0].typ = top_ref) And
                     RefsEqual(Paicpu(hp1)^.oper[0].ref^, Paicpu(p)^.oper[0].ref^) Then
                    Begin
                      Paicpu(p)^.LoadReg(0,Paicpu(hp1)^.oper[1].reg);
                      AsmL^.Remove(hp1);
                      Dispose(hp1, Done)
                    End
                End;
              A_SUB:
                { * change "subl $2, %esp; pushw x" to "pushl x"}
                { * change "sub/add const1, reg" or "dec reg" followed by
                    "sub const2, reg" to one "sub ..., reg" }
                Begin
                  If (Paicpu(p)^.oper[0].typ = top_const) And
                     (Paicpu(p)^.oper[1].typ = top_reg) Then
                    If (Paicpu(p)^.oper[0].val = 2) And
                       (Paicpu(p)^.oper[1].reg = R_ESP) and
                       { Don't do the sub/push optimization if the sub }
                       { comes from setting up the stack frame (JM)    }
                       (not getLastInstruction(p,hp1) or
                        (hp1^.typ <> ait_instruction) or
                        (paicpu(hp1)^.opcode <> A_MOV) or
                        (paicpu(hp1)^.oper[0].typ <> top_reg) or
                        (paicpu(hp1)^.oper[0].reg <> R_ESP) or
                        (paicpu(hp1)^.oper[1].typ <> top_reg) or
                        (paicpu(hp1)^.oper[1].reg <> R_EBP)) then
                      Begin
                        hp1 := Pai(p^.next);
                        While Assigned(hp1) And
                              (Pai(hp1)^.typ In [ait_instruction]+SkipInstr) And
                               not regReadByInstruction(R_ESP,hp1) and
                               not regModifiedByInstruction(R_ESP,hp1) do
                          hp1 := Pai(hp1^.next);
                        If Assigned(hp1) And
                           (Pai(hp1)^.typ = ait_instruction) And
                           (Paicpu(hp1)^.opcode = A_PUSH) And
                           (Paicpu(hp1)^.opsize = S_W)
                          Then
                            Begin
                              Paicpu(hp1)^.changeopsize(S_L);
                              if Paicpu(hp1)^.oper[0].typ=top_reg then
                                Paicpu(hp1)^.LoadReg(0,Reg16ToReg32(Paicpu(hp1)^.oper[0].reg));
                              hp1 := Pai(p^.next);
                              AsmL^.Remove(p);
                              Dispose(p, Done);
                              p := hp1;
                              Continue
                            End;
                        If DoSubAddOpt(p) Then continue;
                      End
                    Else If DoSubAddOpt(p) Then Continue
                End;
               A_XOR:
                 If (Paicpu(p)^.oper[0].typ = top_reg) And
                    (Paicpu(p)^.oper[1].typ = top_reg) And
                    (Paicpu(p)^.oper[0].reg = Paicpu(p)^.oper[1].reg) then
                  { temporarily change this to 'mov reg,0' to make it easier }
                  { for the CSE. Will be changed back in pass 2              }
                   begin
                     paicpu(p)^.opcode := A_MOV;
                     paicpu(p)^.loadconst(0,0);
                   end;
            End;
            end; { if is_jmp }
          End;
{        ait_label:
          Begin
            If labelCanBeSkipped(pai_label(p))
              Then
                Begin
                  hp1 := Pai(p^.next);
                  AsmL^.Remove(p);
                  Dispose(p, Done);
                  p := hp1;
                  Continue
                End;
          End;}
      End;
      p:=pai(p^.next);
    end;
end;

function isFoldableArithOp(hp1: paicpu; reg: tregister): boolean;
begin
  IsFoldableArithOp := False;
  case hp1^.opcode of
    A_ADD,A_SUB,A_OR,A_XOR,A_AND,A_SHL,A_SHR,A_SAR:
      isFoldableArithOp :=
        (paicpu(hp1)^.oper[0].typ in [top_reg,top_const]) and
        (paicpu(hp1)^.oper[1].typ = top_reg) and
        (paicpu(hp1)^.oper[1].reg = reg);
    A_INC,A_DEC:
      isFoldableArithOp :=
        (paicpu(hp1)^.oper[0].typ = top_reg) and
        (paicpu(hp1)^.oper[0].reg = reg);
  end;
end;


Procedure PeepHoleOptPass2(AsmL: PAasmOutput; BlockStart, BlockEnd: Pai);

  function CanBeCMOV(p : pai) : boolean;

    begin
       CanBeCMOV:=assigned(p) and (p^.typ=ait_instruction) and
         (paicpu(p)^.opcode=A_MOV) and
         (paicpu(p)^.opsize in [S_L,S_W]) and
         (paicpu(p)^.oper[0].typ in [top_reg,top_ref]) and
         (paicpu(p)^.oper[1].typ in [top_reg,top_ref]);
    end;

var
  p,hp1,hp2: pai;
{$ifdef  USECMOV}
  l : longint;
  condition : tasmcond;
  hp3: pai;
{$endif USECMOV}
  UsedRegs, TmpUsedRegs: TRegSet;

Begin
  P := BlockStart;
  UsedRegs := [];
  While (P <> BlockEnd) Do
    Begin
      UpdateUsedRegs(UsedRegs, Pai(p^.next));
      Case P^.Typ Of
        Ait_Instruction:
          Begin
            Case Paicpu(p)^.opcode Of
              A_CALL:
                If (AktOptProcessor < ClassP6) And
                   GetNextInstruction(p, hp1) And
                   (hp1^.typ = ait_instruction) And
                   (paicpu(hp1)^.opcode = A_JMP) Then
                  Begin
                    Inc(paicpu(hp1)^.oper[0].sym^.refs);
                    hp2 := New(Paicpu,op_sym(A_PUSH,S_L,paicpu(hp1)^.oper[0].sym));
                    InsertLLItem(AsmL, p^.previous, p, hp2);
                    Paicpu(p)^.opcode := A_JMP;
                    AsmL^.Remove(hp1);
                    Dispose(hp1, Done)
                  End;

{$ifdef USECMOV}
              A_Jcc:
                if (aktspecificoptprocessor=ClassP6) then
                  begin
                     { check for
                            jCC   xxx
                            <several movs>
                         xxx:
                     }
                     l:=0;
                     GetNextInstruction(p, hp1);
                     while assigned(hp1) And
                       CanBeCMOV(hp1) do
                       begin
                          inc(l);
                          GetNextInstruction(hp1,hp1);
                       end;
                     if assigned(hp1) then
                       begin
                          if FindLabel(PAsmLabel(paicpu(p)^.oper[0].sym),hp1) then
                            begin
                               if (l<=4) and (l>0) then
                                 begin
                                    condition:=inverse_cond[paicpu(p)^.condition];
                                    GetNextInstruction(p,hp1);
                                    asml^.remove(p);
                                    dispose(p,done);
                                    p:=hp1;
                                    repeat
                                      paicpu(hp1)^.opcode:=A_CMOVcc;
                                      paicpu(hp1)^.condition:=condition;
                                      GetNextInstruction(hp1,hp1);
                                    until not(assigned(hp1)) or
                                      not(CanBeCMOV(hp1));
                                    asml^.remove(hp1);
                                    dispose(hp1,done);
                                    continue;
                                 end;
                            end
                          else
                            begin
                               { check further for
                                      jCC   xxx
                                      <several movs>
                                      jmp   yyy
                              xxx:
                                      <several movs>
                              yyy:
                               }
                              { hp2 points to jmp xxx }
                              hp2:=hp1;
                              { skip hp1 to xxx }
                              GetNextInstruction(hp1, hp1);
                              if assigned(hp2) and
                                assigned(hp1) and
                                (l<=3) and
                                (hp2^.typ=ait_instruction) and
                                (paicpu(hp2)^.is_jmp) and
                                (paicpu(hp2)^.condition=C_None) and
                                FindLabel(PAsmLabel(paicpu(p)^.oper[0].sym),hp1) then
                                 begin
                                    l:=0;
                                    while assigned(hp1) And
                                      CanBeCMOV(hp1) do
                                      begin
                                         inc(l);
                                         GetNextInstruction(hp1, hp1);
                                      end;
                                 end;
                              {
                              if assigned(hp1) and
                                FindLabel(PAsmLabel(paicpu(hp2)^.oper[0].sym),hp1) then
                                begin
                                   condition:=inverse_cond[paicpu(p)^.condition];
                                   GetNextInstruction(p,hp1);
                                   asml^.remove(p);
                                   dispose(p,done);
                                   p:=hp1;
                                   repeat
                                     paicpu(hp1)^.opcode:=A_CMOVcc;
                                     paicpu(hp1)^.condition:=condition;
                                     GetNextInstruction(hp1,hp1);
                                   until not(assigned(hp1)) or
                                     not(CanBeCMOV(hp1));
                                   hp2:=hp1^.next;
                                   condition:=inverse_cond[condition];

                                   asml^.remove(hp1^.next)
                                   dispose(hp1^.next,done);
                                   asml^.remove(hp1);
                                   dispose(hp1,done);
                                   continue;
                                end;
                              }
                            end;
                       end;
                  end;
{$endif USECMOV}
              A_FSTP,A_FISTP:
                if doFpuLoadStoreOpt(asmL,p) then
                  continue;
              A_IMUL:
                begin
                  if ((paicpu(p)^.oper[0].typ = top_const) or
                      (paicpu(p)^.oper[0].typ = top_symbol)) and
                     (paicpu(p)^.oper[1].typ = top_reg) and
                     ((paicpu(p)^.oper[2].typ = top_none) or
                      ((paicpu(p)^.oper[2].typ = top_reg) and
                       (paicpu(p)^.oper[2].reg = paicpu(p)^.oper[1].reg))) and
                     getLastInstruction(p,hp1) and
                     (hp1^.typ = ait_instruction) and
                     (paicpu(hp1)^.opcode = A_MOV) and
                     (paicpu(hp1)^.oper[0].typ = top_reg) and
                     (paicpu(hp1)^.oper[1].typ = top_reg) and
                     (paicpu(hp1)^.oper[1].reg = paicpu(p)^.oper[1].reg) then
              { change "mov reg1,reg2; imul y,reg2" to "imul y,reg1,reg2" }
                    begin
                      paicpu(p)^.ops := 3;
                      paicpu(p)^.loadreg(1,paicpu(hp1)^.oper[0].reg);
                      paicpu(p)^.loadreg(2,paicpu(hp1)^.oper[1].reg);
                      asmL^.remove(hp1);
                      dispose(hp1,done);
                    end;
                end;
              A_MOV:
                Begin
                  If (Paicpu(p)^.oper[0].typ = top_reg) And
                     (Paicpu(p)^.oper[1].typ = top_reg) And
                     GetNextInstruction(p, hp1) And
                     (hp1^.typ = ait_Instruction) And
                     ((Paicpu(hp1)^.opcode = A_MOV) or
                      (Paicpu(hp1)^.opcode = A_MOVZX) or
                      (Paicpu(hp1)^.opcode = A_MOVSX)) And
                     (Paicpu(hp1)^.oper[0].typ = top_ref) And
                     (Paicpu(hp1)^.oper[1].typ = top_reg) And
                     ((Paicpu(hp1)^.oper[0].ref^.Base = Paicpu(p)^.oper[1].reg) Or
                      (Paicpu(hp1)^.oper[0].ref^.Index = Paicpu(p)^.oper[1].reg)) And
                     (Reg32(Paicpu(hp1)^.oper[1].reg) = Paicpu(p)^.oper[1].reg) Then
              {mov reg1, reg2
               mov/zx/sx (reg2, ..), reg2      to   mov/zx/sx (reg1, ..), reg2}
                    Begin
                      If (Paicpu(hp1)^.oper[0].ref^.Base = Paicpu(p)^.oper[1].reg) Then
                        Paicpu(hp1)^.oper[0].ref^.Base := Paicpu(p)^.oper[0].reg;
                      If (Paicpu(hp1)^.oper[0].ref^.Index = Paicpu(p)^.oper[1].reg) Then
                        Paicpu(hp1)^.oper[0].ref^.Index := Paicpu(p)^.oper[0].reg;
                      AsmL^.Remove(p);
                      Dispose(p, Done);
                      p := hp1;
                      Continue;
                    End
                  Else If (Paicpu(p)^.oper[0].typ = top_ref) And
                    GetNextInstruction(p,hp1) And
                    (hp1^.typ = ait_instruction) And
                    IsFoldableArithOp(paicpu(hp1),Paicpu(p)^.oper[1].reg) And
                    GetNextInstruction(hp1,hp2) And
                    (hp2^.typ = ait_instruction) And
                    (Paicpu(hp2)^.opcode = A_MOV) And
                    (Paicpu(hp2)^.oper[0].typ = top_reg) And
                    (Paicpu(hp2)^.oper[0].reg = Paicpu(p)^.oper[1].reg) And
                    (Paicpu(hp2)^.oper[1].typ = top_ref) Then
                   Begin
                     TmpUsedRegs := UsedRegs;
                     UpdateUsedRegs(TmpUsedRegs,Pai(hp1^.next));
                     If (RefsEqual(Paicpu(hp2)^.oper[1].ref^, Paicpu(p)^.oper[0].ref^) And
                         Not(RegUsedAfterInstruction(Paicpu(p)^.oper[1].reg,
                              hp2, TmpUsedRegs)))
                       Then
  { change   mov            (ref), reg            }
  {          add/sub/or/... reg2/$const, reg      }
  {          mov            reg, (ref)            }
  {          # release reg                        }
  { to       add/sub/or/... reg2/$const, (ref)    }
                     Begin
                       case paicpu(hp1)^.opcode of
                         A_INC,A_DEC:
                           paicpu(hp1)^.LoadRef(0,newreference(Paicpu(p)^.oper[0].ref^))
                         else
                           paicpu(hp1)^.LoadRef(1,newreference(Paicpu(p)^.oper[0].ref^));
                       end;
                       AsmL^.Remove(p);
                       AsmL^.Remove(hp2);
                       Dispose(p,done);
                       Dispose(hp2,Done);
                       p := hp1
                     End;
                   End
                  else if (Paicpu(p)^.oper[0].typ = Top_Const) And
                     (Paicpu(p)^.oper[0].val = 0) And
                     (Paicpu(p)^.oper[1].typ = Top_Reg) Then
                    { change "mov $0, %reg" into "xor %reg, %reg" }
                    Begin
                      Paicpu(p)^.opcode := A_XOR;
                      Paicpu(p)^.LoadReg(0,Paicpu(p)^.oper[1].reg);
                    End
                End;
              A_MOVZX:
                Begin
                  If (Paicpu(p)^.oper[1].typ = top_reg) Then
                    If (Paicpu(p)^.oper[0].typ = top_reg)
                      Then
                        Case Paicpu(p)^.opsize of
                          S_BL:
                            Begin
                              If IsGP32Reg(Paicpu(p)^.oper[1].reg) And
                                 Not(CS_LittleSize in aktglobalswitches) And
                                 (aktoptprocessor = ClassP5)
                                Then
                                  {Change "movzbl %reg1, %reg2" to
                                   "xorl %reg2, %reg2; movb %reg1, %reg2" for Pentium and
                                   PentiumMMX}
                                  Begin
                                    hp1 := New(Paicpu, op_reg_reg(A_XOR, S_L,
                                               Paicpu(p)^.oper[1].reg, Paicpu(p)^.oper[1].reg));
                                    InsertLLItem(AsmL,p^.previous, p, hp1);
                                    Paicpu(p)^.opcode := A_MOV;
                                    Paicpu(p)^.changeopsize(S_B);
                                    Paicpu(p)^.LoadReg(1,Reg32ToReg8(Paicpu(p)^.oper[1].reg));
                                  End;
                            End;
                        End
                      Else
                        If (Paicpu(p)^.oper[0].typ = top_ref) And
                           (Paicpu(p)^.oper[0].ref^.base <> Paicpu(p)^.oper[1].reg) And
                           (Paicpu(p)^.oper[0].ref^.index <> Paicpu(p)^.oper[1].reg) And
                           Not(CS_LittleSize in aktglobalswitches) And
                           IsGP32Reg(Paicpu(p)^.oper[1].reg) And
                           (aktoptprocessor = ClassP5) And
                           (Paicpu(p)^.opsize = S_BL)
                          Then
                            {changes "movzbl mem, %reg" to "xorl %reg, %reg; movb mem, %reg8" for
                             Pentium and PentiumMMX}
                            Begin
                              hp1 := New(Paicpu,op_reg_reg(A_XOR, S_L, Paicpu(p)^.oper[1].reg,
                                         Paicpu(p)^.oper[1].reg));
                              Paicpu(p)^.opcode := A_MOV;
                              Paicpu(p)^.changeopsize(S_B);
                              Paicpu(p)^.LoadReg(1,Reg32ToReg8(Paicpu(p)^.oper[1].reg));
                              InsertLLItem(AsmL,p^.previous, p, hp1);
                            End;
                End;
              A_TEST, A_OR:
                {removes the line marked with (x) from the sequence
                 And/or/xor/add/sub/... $x, %y
                 test/or %y, %y   (x)
                 j(n)z _Label
                    as the first instruction already adjusts the ZF}
                 Begin
                   If OpsEqual(Paicpu(p)^.oper[0],Paicpu(p)^.oper[1]) Then
                    If GetLastInstruction(p, hp1) And
                      (pai(hp1)^.typ = ait_instruction) Then
                     Case Paicpu(hp1)^.opcode Of
                       A_ADD, A_SUB, A_OR, A_XOR, A_AND, A_SHL, A_SHR:
                         Begin
                           If OpsEqual(Paicpu(hp1)^.oper[1],Paicpu(p)^.oper[0]) Then
                             Begin
                               hp1 := pai(p^.next);
                               asml^.remove(p);
                               dispose(p, done);
                               p := pai(hp1);
                               continue
                             End;
                         End;
                       A_DEC, A_INC, A_NEG:
                         Begin
                           If OpsEqual(Paicpu(hp1)^.oper[0],Paicpu(p)^.oper[0]) Then
                             Begin
                               Case Paicpu(hp1)^.opcode Of
                                 A_DEC, A_INC:
 {replace inc/dec with add/sub 1, because inc/dec doesn't set the carry flag}
                                   Begin
                                     Case Paicpu(hp1)^.opcode Of
                                       A_DEC: Paicpu(hp1)^.opcode := A_SUB;
                                       A_INC: Paicpu(hp1)^.opcode := A_ADD;
                                     End;
                                     Paicpu(hp1)^.Loadoper(1,Paicpu(hp1)^.oper[0]);
                                     Paicpu(hp1)^.LoadConst(0,1);
                                     Paicpu(hp1)^.ops:=2;
                                   End
                                 End;
                               hp1 := pai(p^.next);
                               asml^.remove(p);
                               dispose(p, done);
                               p := pai(hp1);
                               continue
                             End;
                         End
                     End
                 End;
            End;
          End;
      End;
      p := Pai(p^.next)
    End;
End;

End.

{
  $Log$
  Revision 1.11  2000-09-18 11:28:36  jonas
    * fixed web bug 1133 (merged from fixes branch)

  Revision 1.10  2000/08/18 10:09:13  jonas
    * fix for web bug1099 (merged from fixes branch)

  Revision 1.9  2000/08/05 13:33:08  peter
    * $ifdef go32v2 -> target_info.target=go32v2

  Revision 1.8  2000/08/05 10:35:51  jonas
    * readded l1 variable (between ifdef go32v2 to avoid hints/notes)

  Revision 1.7  2000/08/04 22:00:52  peter
    * merges from fixes

  Revision 1.6  2000/07/31 08:44:05  jonas
    - removed imul support from -dfoldarithops since "imull [reg32],[mem32]"
      doesn't exist (merged from fixes branch)

  Revision 1.5  2000/07/28 13:56:23  jonas
    * fixed bug in shr/shl optimization when -Og is used (merged from fixes
      branch)

  Revision 1.4  2000/07/21 15:19:55  jonas
    * daopt386: changes to getnextinstruction/getlastinstruction so they
      ignore labels who have is_addr set
    + daopt386/csopt386: remove loads of registers which are overwritten
       before their contents are used (especially usefull for removing superfluous
      maybe_loadesi outputs and push/pops transformed by below optimization
    + popt386: transform pop/pop/pop/.../push/push/push to sequences of
      'movl x(%esp),%reg' (only active when compiling a go32v2 compiler
      currently because I don't know whether it's safe to do this under Win32/
      Linux (because of problems we had when using esp as frame pointer on
      those os'es)

  Revision 1.3  2000/07/14 05:11:49  michael
  + Patch to 1.1

  Revision 1.2  2000/07/13 11:32:45  michael
  + removed logs

}
