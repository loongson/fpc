{
    $Id$
    This file is part of the Free Pascal run time library.
    Copyright (c) 1999-2000 by the Free Pascal development team

    This unit makes Free Pascal as much as possible Delphi compatible

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{$Mode ObjFpc}
{$I-}
{$ifndef Unix}
  {$S-}
{$endif}
unit objpas;

  interface

    { first, in object pascal, the integer type must be redefined }
    const
       MaxInt  = MaxLongint;
    type
       integer = longint;

{****************************************************************************
                             Compatibility routines.
****************************************************************************}

    { Untyped file support }

     Procedure AssignFile(Var f:File;const Name:string);
     Procedure AssignFile(Var f:File;p:pchar);
     Procedure AssignFile(Var f:File;c:char);
     Procedure CloseFile(Var f:File);

     { Text file support }
     Procedure AssignFile(Var t:Text;const s:string);
     Procedure AssignFile(Var t:Text;p:pchar);
     Procedure AssignFile(Var t:Text;c:char);
     Procedure CloseFile(Var t:Text);

     { Typed file supoort }

     Procedure AssignFile(Var f:TypedFile;const Name:string);
     Procedure AssignFile(Var f:TypedFile;p:pchar);
     Procedure AssignFile(Var f:TypedFile;c:char);

     { ParamStr should return also an ansistring }
     Function ParamStr(Param : Integer) : Ansistring;

Type
   TResourceIterator = Function (Name,Value : AnsiString; Hash : Longint) : AnsiString;

   Function Hash(S : AnsiString) : longint;
   Procedure ResetResourceTables;
   Procedure SetResourceStrings (SetFunction :  TResourceIterator);
   Function ResourceStringTableCount : Longint;
   Function ResourceStringCount(TableIndex : longint) : longint;
   Function GetResourceStringName(TableIndex,StringIndex : Longint) : Ansistring;
   Function GetResourceStringHash(TableIndex,StringIndex : Longint) : Longint;
   Function GetResourceStringDefaultValue(TableIndex,StringIndex : Longint) : AnsiString;
   Function GetResourceStringCurrentValue(TableIndex,StringIndex : Longint) : AnsiString;
   Function SetResourceStringValue(TableIndex,StringIndex : longint; Value : Ansistring) : Boolean;



  implementation

{****************************************************************************
                             Compatibility routines.
****************************************************************************}

{ Untyped file support }

Procedure AssignFile(Var f:File;const Name:string);

begin
  System.Assign (F,Name);
end;

Procedure AssignFile(Var f:File;p:pchar);

begin
  System.Assign (F,P);
end;

Procedure AssignFile(Var f:File;c:char);

begin
  System.Assign (F,C);
end;

Procedure CloseFile(Var f:File);

begin
  { Catch Runtime error/Exception }
  {$I+}
  System.Close(f);
  {$I-}
end;

{ Text file support }

Procedure AssignFile(Var t:Text;const s:string);

begin
  System.Assign (T,S);
end;

Procedure AssignFile(Var t:Text;p:pchar);

begin
  System.Assign (T,P);
end;

Procedure AssignFile(Var t:Text;c:char);

begin
  System.Assign (T,C);
end;

Procedure CloseFile(Var t:Text);

begin
  { Catch Runtime error/Exception }
  {$I+}
  System.Close(T);
  {$I-}
end;

{ Typed file supoort }

Procedure AssignFile(Var f:TypedFile;const Name:string);

begin
  system.Assign(F,Name);
end;

Procedure AssignFile(Var f:TypedFile;p:pchar);

begin
  system.Assign (F,p);
end;

Procedure AssignFile(Var f:TypedFile;c:char);

begin
  system.Assign (F,C);
end;

Function ParamStr(Param : Integer) : Ansistring;

Var Len : longint;

begin
    if (Param>=0) and (Param<argc) then
      begin
      Len:=0;
      While Argv[Param][Len]<>#0 do
        Inc(len);
      SetLength(Result,Len);
      If Len>0 then
        Move(Argv[Param][0],Result[1],Len);
      end
    else
      paramstr:='';
  end;



{ ---------------------------------------------------------------------
    ResourceString support
  ---------------------------------------------------------------------}
Type

  PResourceStringRecord = ^TResourceStringRecord;
  TResourceStringRecord = Packed Record
     DefaultValue,
     CurrentValue : AnsiString;
     HashValue : longint;
     Name : AnsiString;
   end;

   TResourceStringTable = Packed Record
     Count : longint;
     Resrec : Array[Word] of TResourceStringRecord;
   end;
   PResourceStringTable = ^TResourceStringTable;

   TResourceTableList = Packed Record
     Count : longint;
     Tables : Array[Word] of PResourceStringTable;
     end;



Var
  ResourceStringTable : TResourceTablelist; External Name 'FPC_RESOURCESTRINGTABLES';

Function Hash(S : AnsiString) : longint;

Var thehash,g,I : longint;

begin
   thehash:=0;
   For I:=1 to Length(S) do { 0 terminated }
     begin
     thehash:=thehash shl 4;
     inc(theHash,Ord(S[i]));
     g:=thehash and longint($f shl 28);
     if g<>0 then
       begin
       thehash:=thehash xor (g shr 24);
       thehash:=thehash xor g;
       end;
     end;
   If theHash=0 then
     Hash:=Not(0)
   else
     Hash:=TheHash;
end;

Function GetResourceString(Const TheTable: TResourceStringTable;Index : longint) : AnsiString;[Public,Alias : 'FPC_GETRESOURCESTRING'];
begin
  If (Index>=0) and (Index<TheTAble.Count) then
     Result:=TheTable.ResRec[Index].CurrentValue
  else
     Result:='';
end;

(*
Function SetResourceString(Hash : Longint;Const Name : ShortString; Const Value : AnsiString) : Boolean;

begin
  Hash:=FindIndex(Hash,Name);
  Result:=Hash<>-1;
  If Result then
    ResourceStringTable.ResRec[Hash].CurrentValue:=Value;
end;
*)

Procedure SetResourceStrings (SetFunction :  TResourceIterator);

Var I,J : longint;

begin
  With ResourceStringTable do
    For I:=0 to Count-1 do
      With Tables[I]^ do
         For J:=0 to Count-1 do
           With ResRec[J] do
             CurrentValue:=SetFunction(Name,DefaultValue,HashValue);
end;


Procedure ResetResourceTables;

Var I,J : longint;

begin
  With ResourceStringTable do
  For I:=0 to Count-1 do
    With Tables[I]^ do
        For J:=0 to Count-1 do
          With ResRec[J] do
            CurrentValue:=DefaultValue;
end;

Function ResourceStringTableCount : Longint;

begin
  Result:=ResourceStringTable.Count;
end;

Function CheckTableIndex (Index: longint) : Boolean;
begin
  Result:=(Index<ResourceStringTable.Count) and (Index>=0)
end;

Function CheckStringIndex (TableIndex,Index: longint) : Boolean;
begin
  Result:=(TableIndex<ResourceStringTable.Count) and (TableIndex>=0) and
          (Index<ResourceStringTable.Tables[TableIndex]^.Count) and (Index>=0)
end;

Function ResourceStringCount(TableIndex : longint) : longint;

begin
  If not CheckTableIndex(TableIndex) then
     Result:=-1
  else
    Result:=ResourceStringTable.Tables[TableIndex]^.Count;
end;

Function GetResourceStringName(TableIndex,StringIndex : Longint) : Ansistring;

begin
  If not CheckStringIndex(Tableindex,StringIndex) then
    Result:=''
  else
    result:=ResourceStringTable.Tables[TableIndex]^.ResRec[StringIndex].Name;
end;

Function GetResourceStringHash(TableIndex,StringIndex : Longint) : Longint;

begin
  If not CheckStringIndex(Tableindex,StringIndex) then
    Result:=0
  else
    result:=ResourceStringTable.Tables[TableIndex]^.ResRec[StringIndex].HashValue;
end;

Function GetResourceStringDefaultValue(TableIndex,StringIndex : Longint) : AnsiString;

begin
  If not CheckStringIndex(Tableindex,StringIndex) then
    Result:=''
  else
    result:=ResourceStringTable.Tables[TableIndex]^.ResRec[StringIndex].DefaultValue;
end;

Function GetResourceStringCurrentValue(TableIndex,StringIndex : Longint) : AnsiString;

begin
  If not CheckStringIndex(Tableindex,StringIndex) then
    Result:=''
  else
    result:=ResourceStringTable.Tables[TableIndex]^.ResRec[StringIndex].CurrentValue;
end;

Function SetResourceStringValue(TableIndex,StringIndex : longint; Value : Ansistring) : Boolean;

begin
  Result:=CheckStringIndex(Tableindex,StringIndex);
  If Result then
   ResourceStringTable.Tables[TableIndex]^.ResRec[StringIndex].CurrentValue:=Value;
end;

Initialization
  ResetResourceTables;
finalization

end.

{
  $Log$
  Revision 1.7  2001-08-19 21:02:02  florian
    * fixed and added a lot of stuff to get the Jedi DX( headers
      compiled

  Revision 1.6  2001/08/01 21:43:11  peter
    * generate error for closefile

  Revision 1.5  2000/12/16 15:58:18  jonas
    * removed warnings about possible range check errors

  Revision 1.4  2000/11/13 14:41:20  marco
   * Unix renamefest for defines

  Revision 1.3  2000/07/14 10:33:10  michael
  + Conditionals fixed

  Revision 1.2  2000/07/13 11:33:51  michael
  + removed logs
}
