{
    $Id$

    libasync: Asynchronous event management
    Copyright (C) 2001 by
      Areca Systems GmbH / Sebastian Guenther, sg@freepascal.org

    Unix implementation

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
}

unit libasync;

{$MODE objfpc}

interface

type

  TAsyncData = record
    IsRunning, DoBreak: Boolean;
    HasCallbacks: Boolean;	// True as long as callbacks are set
    FirstTimer: Pointer;
    FirstIOCallback: Pointer;
    FDData: Pointer;
    HighestHandle: LongInt;
  end;

{$INCLUDE libasync.inc}



implementation

uses Linux;

const
  MaxHandle = SizeOf(TFDSet) * 8 - 1;

type
  PTimerData = ^TTimerData;
  TTimerData = record
    Next: PTimerData;
    MSec: LongInt;
    NextTick: Int64;
    Callback: TAsyncCallback;
    UserData: Pointer;
    Periodic: Boolean;
  end;

  PIOCallbackData = ^TIOCallbackData;
  TIOCallbackData = record
    Next: PIOCallbackData;
    IOHandle: LongInt;
    ReadCallback, WriteCallback: TAsyncCallback;
    ReadUserData, WriteUserData: Pointer;
    SavedHandleFlags: LongInt;
  end;



procedure InitIOCallback(Handle: TAsyncHandle; IOHandle: LongInt;
  ARead: Boolean; ReadCallback: TAsyncCallback; ReadUserData: Pointer;
  AWrite: Boolean; WriteCallback: TAsyncCallback; WriteUserData: Pointer);
var
  Data: PIOCallbackData;
  i: LongInt;
  NeedData: Boolean;
begin
  if IOHandle > MaxHandle then
    exit;

  NeedData := True;
  Data := Handle^.Data.FirstIOCallback;
  while Assigned(Data) do
  begin
    if Data^.IOHandle = IOHandle then
    begin
      if ARead then
      begin
        Data^.ReadCallback := ReadCallback;
	Data^.ReadUserData := ReadUserData;
      end;
      if AWrite then
      begin
        Data^.WriteCallback := WriteCallback;
	Data^.WriteUserData := WriteUserData;
      end;
      NeedData := False;
      break;
    end;
    Data := Data^.Next;
  end;

  if NeedData then
  begin
    New(Data);
    Data^.Next := Handle^.Data.FirstIOCallback;
    Handle^.Data.FirstIOCallback := Data;
    Data^.IOHandle := IOHandle;
    if ARead then
    begin
      Data^.ReadCallback := ReadCallback;
      Data^.ReadUserData := ReadUserData;
    end else
      Data^.ReadCallback := nil;
    if AWrite then
    begin
      Data^.WriteCallback := WriteCallback;
      Data^.WriteUserData := WriteUserData;
    end else
      Data^.WriteCallback := nil;

    if not Assigned(Handle^.Data.FDData) then
    begin
      GetMem(Handle^.Data.FDData, SizeOf(TFDSet) * 2);
      FD_Zero(PFDSet(Handle^.Data.FDData)[0]);
      FD_Zero(PFDSet(Handle^.Data.FDData)[1]);
    end;
    if IOHandle > Handle^.Data.HighestHandle then
      Handle^.Data.HighestHandle := IOHandle;
  end;

  Data^.SavedHandleFlags := fcntl(IOHandle, F_GetFl);
  fcntl(IOHandle, F_SetFl, Data^.SavedHandleFlags or Open_NonBlock);

  case IOHandle of
    StdInputHandle:
      i := Open_RdOnly;
    StdOutputHandle, StdErrorHandle:
      i := Open_WrOnly;
    else
      i := Data^.SavedHandleFlags and Open_Accmode;
  end;

  case i of
    Open_RdOnly:
      if ARead then
        FD_Set(IOHandle, PFDSet(Handle^.Data.FDData)[0]);
    Open_WrOnly:
      if AWrite then
        FD_Set(IOHandle, PFDSet(Handle^.Data.FDData)[1]);
    Open_RdWr:
      begin
        if ARead then
	  FD_Set(IOHandle, PFDSet(Handle^.Data.FDData)[0]);
	if AWrite then
	  FD_Set(IOHandle, PFDSet(Handle^.Data.FDData)[1]);
      end;
  end;

  Handle^.Data.HasCallbacks := True;
end;

procedure CheckForCallbacks(Handle: TAsyncHandle);
var
  Data: PIOCallbackData;
begin
  if (Handle^.Data.HasCallbacks) and
    (not Assigned(Handle^.Data.FirstIOCallback)) and
    (not Assigned(Handle^.Data.FirstTimer)) then
    Handle^.Data.HasCallbacks := False;
end;



procedure asyncInit(Handle: TAsyncHandle); cdecl;
begin
  Handle^.Data.HighestHandle := -1;
end;

procedure asyncFree(Handle: TAsyncHandle); cdecl;
var
  Timer, NextTimer: PTimerData;
  IOCallback, NextIOCallback: PIOCallbackData;
begin
  Timer := PTimerData(Handle^.Data.FirstTimer);
  while Assigned(Timer) do
  begin
    NextTimer := Timer^.Next;
    Dispose(Timer);
    Timer := NextTimer;
  end;

  IOCallback := PIOCallbackData(Handle^.Data.FirstIOCallback);
  while Assigned(IOCallback) do
  begin
    if (IOCallback^.SavedHandleFlags and Open_NonBlock) = 0 then
      fcntl(IOCallback^.IOHandle, F_SetFl, IOCallback^.SavedHandleFlags);
    NextIOCallback := IOCallback^.Next;
    Dispose(IOCallback);
    IOCallback := NextIOCallback;
  end;

  if Assigned(Handle^.Data.FDData) then
    FreeMem(Handle^.Data.FDData);
end;

procedure asyncRun(Handle: TAsyncHandle); cdecl;
var
  Timer, NextTimer: PTimerData;
  TimeOut, AsyncResult: Integer;
  CurTime, NextTick: Int64;
  CurReadFDSet, CurWriteFDSet: TFDSet;
  IOCallback: PIOCallbackData;
begin
  if Handle^.Data.IsRunning then
    exit;

  Handle^.Data.DoBreak := False;
  Handle^.Data.IsRunning := True;

  // Prepare timers
  if Assigned(Handle^.Data.FirstTimer) then
  begin
    CurTime := asyncGetTicks;
    Timer := Handle^.Data.FirstTimer;
    while Assigned(Timer) do
    begin
      Timer^.NextTick := CurTime + Timer^.MSec;
      Timer := Timer^.Next;
    end;
  end;

  while (not Handle^.Data.DoBreak) and Handle^.Data.HasCallbacks do
  begin
    Timer := Handle^.Data.FirstTimer;
    if Assigned(Handle^.Data.FirstTimer) then
    begin
      // Determine when the next timer tick will happen
      CurTime := asyncGetTicks;
      NextTick := High(Int64);
      Timer := Handle^.Data.FirstTimer;
      while Assigned(Timer) do
      begin
        if Timer^.NextTick < NextTick then
	  NextTick := Timer^.NextTick;
	Timer := Timer^.Next;
      end;
      TimeOut := NextTick - CurTime;
      if TimeOut < 0 then
        TimeOut := 0;
    end else
      TimeOut := -1;

    if Handle^.Data.HighestHandle >= 0 then
    begin
      CurReadFDSet := PFDSet(Handle^.Data.FDData)[0];
      CurWriteFDSet := PFDSet(Handle^.Data.FDData)[1];
      AsyncResult := Select(Handle^.Data.HighestHandle + 1,
        @CurReadFDSet, @CurWriteFDSet, nil, TimeOut);
    end else
      AsyncResult := Select(0, nil, nil, nil, TimeOut);

    if Assigned(Handle^.Data.FirstTimer) then
    begin
      // Check for triggered timers
      CurTime := asyncGetTicks;
      Timer := Handle^.Data.FirstTimer;
      while Assigned(Timer) do
      begin
        if Timer^.NextTick <= CurTime then
	begin
	  Timer^.Callback(Timer^.UserData);
	  NextTimer := Timer^.Next;
	  if Timer^.Periodic then
	    Inc(Timer^.NextTick, Timer^.MSec)
	  else
	    asyncRemoveTimer(Handle, Timer);
	  if Handle^.Data.DoBreak then
	    break;
	  Timer := NextTimer;
	end else
	  Timer := Timer^.Next;
      end;
    end;

    if (AsyncResult > 0) and not Handle^.Data.DoBreak then
    begin
      // Check for I/O events
      IOCallback := Handle^.Data.FirstIOCallback;
      while Assigned(IOCallback) do
      begin
	if FD_IsSet(IOCallback^.IOHandle, CurReadFDSet) and
	  FD_IsSet(IOCallback^.IOHandle, PFDSet(Handle^.Data.FDData)[0]) then
	begin
	  IOCallback^.ReadCallback(IOCallback^.ReadUserData);
	  if Handle^.Data.DoBreak then
	    break;
	end;

	if FD_IsSet(IOCallback^.IOHandle, CurWriteFDSet) and
	  FD_IsSet(IOCallback^.IOHandle, PFDSet(Handle^.Data.FDData)[1]) then
	begin
	  IOCallback^.WriteCallback(IOCallback^.WriteUserData);
	  if Handle^.Data.DoBreak then
	    break;
	end;

	IOCallback := IOCallback^.Next;
      end;
    end;
  end;
  Handle^.Data.IsRunning := False;
end;

procedure asyncBreak(Handle: TAsyncHandle); cdecl;
begin
  Handle^.Data.DoBreak := True;
end;

function asyncIsRunning(Handle: TAsyncHandle): Boolean; cdecl;
begin
  Result := Handle^.Data.IsRunning;
end;

function asyncGetTicks: Int64; cdecl;
var
  Time: TimeVal;
begin
  GetTimeOfDay(Time);
  Result := Int64(Time.Sec) * 1000 + Int64(Time.USec div 1000);
end;

function asyncAddTimer(
  Handle: TAsyncHandle;
  MSec: LongInt;
  Periodic: Boolean;
  Callback: TAsyncCallback;
  UserData: Pointer
  ): TAsyncTimer; cdecl;
var
  Data: PTimerData;
begin
  if not Assigned(Callback) then
    exit;

  New(Data);
  Result := Data;
  Data^.Next := Handle^.Data.FirstTimer;
  Handle^.Data.FirstTimer := Data;
  Data^.MSec := MSec;
  Data^.Periodic := Periodic;
  Data^.Callback := Callback;
  Data^.UserData := UserData;
  if Handle^.Data.IsRunning then
    Data^.NextTick := asyncGetTicks + MSec;

  Handle^.Data.HasCallbacks := True;
end;

procedure asyncRemoveTimer(
  Handle: TAsyncHandle;
  Timer: TASyncTimer); cdecl;
var
  Data, CurData, PrevData, NextData: PTimerData;
begin
  Data := PTimerData(Timer);
  CurData := Handle^.Data.FirstTimer;
  PrevData := nil;
  while Assigned(CurData) do
  begin
    NextData := CurData^.Next;
    if CurData = Data then
    begin
      if Assigned(PrevData) then
        PrevData^.Next := NextData
      else
        Handle^.Data.FirstTimer := NextData;
      break;
    end;
    PrevData := CurData;
    CurData := NextData;
  end;
  Dispose(Data);
  CheckForCallbacks(Handle);
end;

procedure asyncSetIOCallback(
  Handle: TAsyncHandle;
  IOHandle: LongInt;
  Callback: TAsyncCallback;
  UserData: Pointer); cdecl;
begin
  InitIOCallback(Handle, IOHandle, True, Callback, UserData,
    True, Callback, UserData);
end;

procedure asyncClearIOCallback(Handle: TAsyncHandle;
  IOHandle: LongInt); cdecl;
var
  CurData, PrevData, NextData: PIOCallbackData;
begin
  CurData := Handle^.Data.FirstIOCallback;
  PrevData := nil;
  while Assigned(CurData) do
  begin
    NextData := CurData^.Next;
    if CurData^.IOHandle = IOHandle then
    begin
      FD_Clr(IOHandle, PFDSet(Handle^.Data.FDData)[0]);
      FD_Clr(IOHandle, PFDSet(Handle^.Data.FDData)[1]);
      if Assigned(PrevData) then
        PrevData^.Next := NextData
      else
        Handle^.Data.FirstIOCallback := NextData;
      Dispose(CurData);
      break;
    end;
    PrevData := CurData;
    CurData := NextData;
  end;
  CheckForCallbacks(Handle);
end;

procedure asyncSetDataAvailableCallback(
  Handle: TAsyncHandle;
  IOHandle: LongInt;
  Callback: TAsyncCallback;
  UserData: Pointer); cdecl;
begin
  InitIOCallback(Handle, IOHandle, True, Callback, UserData, False, nil, nil);
end;

procedure asyncClearDataAvailableCallback(Handle: TAsyncHandle;
  IOHandle: LongInt); cdecl;
var
  CurData, PrevData, NextData: PIOCallbackData;
begin
  CurData := Handle^.Data.FirstIOCallback;
  PrevData := nil;
  while Assigned(CurData) do
  begin
    NextData := CurData^.Next;
    if CurData^.IOHandle = IOHandle then
    begin
      FD_Clr(IOHandle, PFDSet(Handle^.Data.FDData)[0]);
      if Assigned(CurData^.WriteCallback) then
        CurData^.ReadCallback := nil
      else
      begin
        if Assigned(PrevData) then
          PrevData^.Next := NextData
        else
          Handle^.Data.FirstIOCallback := NextData;
        Dispose(CurData);
      end;
      break;
    end;
    PrevData := CurData;
    CurData := NextData;
  end;
  CheckForCallbacks(Handle);
end;

procedure asyncSetCanWriteCallback(
  Handle: TAsyncHandle;
  IOHandle: LongInt;
  Callback: TAsyncCallback;
  UserData: Pointer); cdecl;
begin
  InitIOCallback(Handle, IOHandle, False, nil, nil, True, Callback, UserData);
end;

procedure asyncClearCanWriteCallback(Handle: TAsyncHandle;
  IOHandle: LongInt); cdecl;
var
  CurData, PrevData, NextData: PIOCallbackData;
begin
  CurData := Handle^.Data.FirstIOCallback;
  PrevData := nil;
  while Assigned(CurData) do
  begin
    NextData := CurData^.Next;
    if CurData^.IOHandle = IOHandle then
    begin
      FD_Clr(IOHandle, PFDSet(Handle^.Data.FDData)[1]);
      if Assigned(CurData^.ReadCallback) then
        CurData^.WriteCallback := nil
      else
      begin
        if Assigned(PrevData) then
          PrevData^.Next := NextData
        else
          Handle^.Data.FirstIOCallback := NextData;
        Dispose(CurData);
      end;
      break;
    end;
    PrevData := CurData;
    CurData := NextData;
  end;
  CheckForCallbacks(Handle);
end;


end.


{
  $Log$
  Revision 1.1.2.2  2001-11-16 12:51:41  sg
  * Now different handlers for available data and space in write buffer can
    be set
  * LOTS of bugfixes in the implementation
  * fpAsync now has a write buffer class (a read buffer class for reading
    line by line will be included in the next release)

  Revision 1.1.2.1  2001/09/08 15:43:24  sg
  * First public version

}
