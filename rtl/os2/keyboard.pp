{
    $Id$
    This file is part of the Free Pascal run time library.
    Copyright (c) 1999-2000 by Florian Klaempfl
    member of the Free Pascal development team

    Keyboard unit for linux

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
unit Keyboard;
interface

{$i keybrdh.inc}

implementation

uses
 KbdCalls, DosCalls;

{$i keyboard.inc}

const
 DefaultKeyboard = 0;
 Handle: word = DefaultKeyboard;

procedure InitKeyboard;
var
 K: TKbdInfo;
begin
 if KbdGetFocus (IO_Wait, DefaultKeyboard) = No_Error then
 begin
  if KbdOpen (Handle) <> No_Error then Handle := DefaultKeyboard;
  KbdFlushBuffer (Handle);
  KbdFreeFocus (DefaultKeyboard);
  KbdGetFocus (IO_Wait, Handle);
  K.cb := 10;
  KbdGetStatus (K, Handle);
  K.fsMask := $14;
  KbdSetStatus (K, Handle);
 end;
end;

procedure DoneKeyboard;
begin
 KbdFreeFocus (Handle);
 if KbdGetFocus (IO_Wait, DefaultKeyboard) = No_Error then
 begin
  KbdClose (Handle);
  Handle := DefaultKeyboard;
  KbdFreeFocus (DefaultKeyboard);
 end;
end;

function GetKeyEvent: TKeyEvent;
var
 K: TKbdKeyInfo;
begin
 if PendingKeyEvent <> 0 then
 begin
  GetKeyEvent := PendingKeyEvent;
  PendingKeyEvent := 0;
 end else
 begin
  KbdGetFocus (IO_Wait, Handle);
  while (KbdCharIn (K, IO_Wait, Handle) <> No_Error)
                                   or (K.fbStatus and $40 = 0) do DosSleep (5);
  with K do
  begin
   if (byte (chChar) = $E0) and (fbStatus and 2 <> 0) then chChar := #0;
   GetKeyEvent := cardinal ($0300 or fsState and $F) shl 16 or
                               cardinal (byte (chScan)) shl 8 or byte (chChar);
  end;
 end;
end;

function PollKeyEvent: TKeyEvent;
var
 K: TKbdKeyInfo;
begin
 if PendingKeyEvent = 0 then
 begin
  KbdGetFocus (IO_NoWait, Handle);
  if (KbdCharIn (K, IO_NoWait, Handle) <> No_Error) or
                 (K.fbStatus and $40 = 0) then FillChar (K, SizeOf (K), 0) else
  with K do
  begin
   if (byte (chChar) = $E0) and (fbStatus and 2 <> 0) then chChar := #0;
   PendingKeyEvent := cardinal ($0300 or fsState and $F) shl 16 or
                               cardinal (byte (chScan)) shl 8 or byte (chChar);
  end;
 end;
 PollKeyEvent := PendingKeyEvent;
 if PendingKeyEvent and $FFFF = 0 then PendingKeyEvent := 0;
end;

function PollShiftStateEvent: TKeyEvent;
var
 K: TKbdInfo;
begin
 KbdGetFocus (IO_NoWait, Handle);
 KbdGetStatus (K, Handle);
 PollShiftStateEvent := cardinal (K.fsState and $F) shl 16;
end;

type
 TTranslationEntry = packed record
  Min, Max: byte;
  Offset: word;
 end;

const
 TranslationTableEntries = 12;
 TranslationTable: array [1..TranslationTableEntries] of TTranslationEntry =
    ((Min: $3B; Max: $44; Offset: kbdF1),   { function keys F1-F10 }
     (Min: $54; Max: $5D; Offset: kbdF1),   { Shift fn keys F1-F10 }
     (Min: $5E; Max: $67; Offset: kbdF1),   { Ctrl fn keys F1-F10 }
     (Min: $68; Max: $71; Offset: kbdF1),   { Alt fn keys F1-F10 }
     (Min: $85; Max: $86; Offset: kbdF11),  { function keys F11-F12 }
     (Min: $87; Max: $88; Offset: kbdF11),  { Shift+function keys F11-F12 }
     (Min: $89; Max: $8A; Offset: kbdF11),  { Ctrl+function keys F11-F12 }
     (Min: $8B; Max: $8C; Offset: kbdF11),  { Alt+function keys F11-F12 }
     (Min:  71; Max:  73; Offset: kbdHome), { Keypad keys kbdHome-kbdPgUp }
     (Min:  75; Max:  77; Offset: kbdLeft), { Keypad keys kbdLeft-kbdRight }
     (Min:  79; Max:  81; Offset: kbdEnd),  { Keypad keys kbdEnd-kbdPgDn }
     (Min: $52; Max: $53; Offset: kbdInsert));


function TranslateKeyEvent (KeyEvent: TKeyEvent): TKeyEvent;
var
 I: integer;
 ScanCode: byte;
begin
 if KeyEvent and $03000000 = $03000000 then
 begin
  if (KeyEvent and $000000FF <> 0) and (KeyEvent and $000000FF <> $E0) then
                               TranslateKeyEvent := KeyEvent and $00FFFFFF else
  begin
{ This is a function key }
   ScanCode := (KeyEvent and $0000FF00) shr 8;
   I := 1;
   while (I <= TranslationTableEntries) and
       ((TranslationTable [I].Min > ScanCode) or
                             (ScanCode > TranslationTable [I].Max)) do Inc (I);
   if I > TranslationTableEntries then TranslateKeyEvent := KeyEvent else
           TranslateKeyEvent := $02000000 + (KeyEvent and $00FF0000) +
             (ScanCode - TranslationTable[I].Min) + TranslationTable[I].Offset;
  end;
 end else TranslateKeyEvent := KeyEvent;
end;

function TranslateKeyEventUniCode (KeyEvent: TKeyEvent): TKeyEvent;
begin
 TranslateKeyEventUniCode := KeyEvent;
 ErrorHandler (errKbdNotImplemented, nil);
end;

end.
{
  $Log$
  Revision 1.1  2001-01-13 11:03:58  peter
    * API 2 RTL commit

}
