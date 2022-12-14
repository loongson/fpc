{
    This file is part of the Free Pascal Integrated Development Environment
    Copyright (c) 2000 by Berczi Gabor

    Strings for utilities

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{ $undef USERESSTRINGS} { this doesn't compile under FP!!! why? }

{$ifdef USERESSTRINGS}
    resourcestring
{$else}
    const
{$endif}

    btn_OK = 'O~K~';
    btn_Cancel = 'M?gsem';

    dialog_find = 'Keres?s';
    label_find_options = 'Opci?k';
    label_find_texttofind = '~K~eresend?';
    label_find_casesensitive = 'K~i~s-/nagybet?k k?l?n';
    label_find_wholewordsonly = 'Csak teljes sza~v~akat';
    label_find_direction = 'Ir?ny';
    label_find_forward = 'El?re (~d~)';
    label_find_backward = 'Visszafel? (~b~)';
    label_find_scope = 'Szk?p';
    label_find_global = 'Teljes sz?ve~g~';
    label_find_selectedtext = 'Kiv?la~s~ztott sz?veg';
    label_find_origin = 'Kiindul?si pont';
    label_find_fromcursor = 'A kur~z~ort?l';
    label_find_entirescope = 'T~e~ljes szk?p';

    dialog_replace = 'Csere';
    label_replace_texttofind = label_find_texttofind;
    label_replace_newtext = '   ~?~j sz?veg';
    label_replace_options = label_find_options;
    label_replace_casesensitive = label_find_casesensitive;
    label_replace_wholewordsonly = label_find_wholewordsonly;
    label_replace_promptonreplace = '~P~rompt on replace';
    label_replace_direction = label_find_direction;
    label_replace_forward = label_find_forward;
    label_replace_backward = label_find_backward;
    label_replace_scope = label_find_scope;
    label_replace_global = label_find_global;
    label_replace_selectedtext = label_find_selectedtext;
    label_replace_origin = label_find_origin;
    label_replace_fromcursor = label_find_fromcursor;
    label_replace_entirescope = label_find_entirescope;
    btn_replace_changeall = '~A~z ?sszeset';

    dialog_gotoline = 'Ugr?s sorra';
    label_gotoline_linenumber = 'Az ?j sor s~z~?ma';

    msg_invalidmarkindex = '?rv?nytelen pont index (%d)';
    msg_marknotset = 'A %d. pont nincs be?ll?tva.';

    msg_foldboundsarenotvalid = 'A hajt?s hat?rai nem ?rv?nyesek';

    msg_notenoughmemoryforthisoperation = 'Nincs el?g mem?ria a m?velet elv?gz?s?hez.';
    msg_errorreadingfile = 'Hiba a  %s f?jl olvas?sa k?zben.';
    msg_errorwritingfile = 'Hiba a  %s f?jl ?r?sa k?zben.';
    msg_errorsavingfile = 'Hiba a %s f?jl ment?se k?zben.';
    msg_errorcreatingfile = 'Hiba a %s f?jl l?trehoz?sa k?zben.';
    msg_filehasbeenmodifiedsave = 'A %s m?dosult. Menti?';
    msg_saveuntitledfile = 'Elmenti a c?m n?lk?li f?jlt?';
    msg_filehadtoolonglines = #3'A %s f?jlnak t?l hossz?'#13+
                              #3'sora(i) voltak. Az els? a %d';
    msg_filewasmodified = #3'A %s f?jlt'#13+
                          #3'egy m?sik program m?dos?totta.'#13+
                          #3'Fel?l?rja az ?jabb verzi?t?';

    dialog_savefileas = 'F?jl ment?se m?s n?ven';
    dialog_writeblocktofile = 'Blokk ki?r?sa f?jlba';
    dialog_readblockfromfile = 'Blokk beolvas?sa f?jlb?l';

    label_name = '~N~?v';

    msg_searchstringnotfound = 'A keresett karaktersor nem tal?lhat?.';
    msg_replacethisoccourence = 'Lecser?ljem ezt az el?fordul?st?';
    msg_fileexistsoverwrite = 'A %s f?jl m?r l?tezik. Fel?l?rja?';

    { Help system }

    msg_nohelpfilesinstalled = 'Nincsenek s?g?-f?jlok telep?tve.';
    msg_helpindex = 'S?g? index';
    msg_nohelpavailabelforthistopic = 'Ehhez a t?m?hoz nem tartozik s?g?.';
    msg_pagenotavailable = 'Az oldal nem el?rhet?';
    msg_cantaccessurl = 'Sajnos nem tudom megnyitni a %s URL-t...';

    { WUtils }
    msg_bugcheckfailed = 'Bels? hiba: %s'#13+
                         'K?rem, jelezze a szerz?nek!';
    msg_functionnotimplemented = #3'Ez a funkci? m?g'#13+
                                 #3+'nincs kidolgozva...'#13+
                                 #3+'';

