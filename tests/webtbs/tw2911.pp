{ Source provided for Free Pascal Bug Report 2911 }
{ Submitted by "Chris Hilder" on  2004-01-19 }
{ e-mail: cj.hilder@astronomyinyourhands.com }
program bug_demo;
{$LONGSTRINGS ON}

{$ifdef fpc}{$Mode objfpc}{$endif}

type
        RecordWithStrings =
                record
                        one,
                        two : string;
                end;

var
        onestring,
        twostring : string;
        ARecordWithStrings : RecordWithStrings;

procedure RefCount(const s : string;expect:longint);
type
        PLongint = ^Longint;
var
        P : PLongint;
        rc : longint;
begin
        P := PLongint(s);
        rc:=0;
        if (p = nil)
        then writeln('Nil string.')
        else
{$ifdef  fpc}
         rc:=(p-1)^;
{$else}
         rc:=plongint(pchar(p)-8)^);
{$endif}
  writeln('Ref count is ',rc,' expected ',expect);
  if rc<>expect then
    halt(1);
end;

function FunctionResultIsRecord(a : RecordWithStrings) : RecordWithStrings;
begin
        result := a;
end;

begin
        writeln('All reference counts should be 1 for the following...');
        onestring := 'one';
        twostring := 'two';
        ARecordWithStrings.one := onestring + twostring;
        twostring := onestring + twostring;
        RefCount(ARecordWithStrings.one,1);
        ARecordWithStrings := FunctionResultIsRecord(ARecordWithStrings);
        twostring := onestring + twostring;
        RefCount(ARecordWithStrings.one,2);
        ARecordWithStrings := FunctionResultIsRecord(ARecordWithStrings);
        twostring := onestring + twostring;
        RefCount(ARecordWithStrings.one,3);
        ARecordWithStrings := FunctionResultIsRecord(ARecordWithStrings);
        twostring := onestring + twostring;
        RefCount(ARecordWithStrings.one,4);
end.