{ Program to test OS-specific features of the system unit }
{ routines to test:                                       }
{   mkdir()                                               }
{   chdir()                                               }
{ This program shoulf not be executed in a root directory }
{ Creates the following directory, and sets it as the     }
{ current directory.                                      }
{    ../testdir                                           }
Program tdir;
{$I-}

procedure test(value, required: longint);
begin
  if value <> required then
    begin
      writeln('Got ',value,' instead of ',required);
      halt(1);
    end;
end;



var
 s: string;
Begin
   Write('changing to parent directory...');
   chdir('..');
   test(IOResult, 0);
   WriteLn('Passed!');

   Write('making directory...');
   mkdir('testdir');
   test(IOResult, 0);
   WriteLn('Passed!');

   Write('going into the newly created directory...');
   chdir('testdir');
   test(IOResult, 0);
   WriteLn('Passed!');

   Write('making directory...');
   mkdir('testdir2');
   test(IOResult, 0);
   WriteLn('Passed!');

   Write('removing directory ...');
   rmdir('testdir2');
   test(IOResult, 0);
   WriteLn('Passed!');


   Write('going directory up ...');
   chdir('..');
   test(IOResult, 0);
   WriteLn('Passed!');

   Write('removing directory ...');
   rmdir('testdir');
   test(IOResult, 0);
   WriteLn('Passed!');

   WriteLn('getting current directory...');
   getdir(0,s);
   WriteLn(s);
end.

{
 $Log$
 Revision 1.4  2002-09-07 15:40:56  peter
   * old logs removed and tabs fixed

 Revision 1.3  2002/03/05 21:54:22  carl
 + cleanup

}

