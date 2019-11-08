#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
#Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.


DebugRegEx(Match, CalloutNumber, FoundPos, Haystack, NeedleRegEx)
{
    static debug_counter := 0
    ; See pcre.txt for descriptions of these fields.
    start_match       := NumGet(A_EventInfo, 12 + A_PtrSize*2, "Int")
    current_position  := NumGet(A_EventInfo, 16 + A_PtrSize*2, "Int")
    pad := A_PtrSize=8 ? 4 : 0
    pattern_position  := NumGet(A_EventInfo, 28 + pad + A_PtrSize*3, "Int")
    next_item_length  := NumGet(A_EventInfo, 32 + pad + A_PtrSize*3, "Int")

    ; Point out >>current match<<.
    _HAYSTACK:=SubStr(Haystack, 1, start_match)
        . "##>>]" SubStr(Haystack, start_match + 1, current_position - start_match)
        . "[<<##" SubStr(Haystack, current_position + 1)
    
    ; Point out >>next item to be evaluated<<.
    _NEEDLE:=  SubStr(NeedleRegEx, 1, pattern_position)
        . "##>>]" SubStr(NeedleRegEx, pattern_position + 1, next_item_length)
        . "[<<##" SubStr(NeedleRegEx, pattern_position + 1 + next_item_length)
    
    ;ListVars
    ; Press Pause to continue.
    ;Pause
	msgbox % "Step: " . debug_counter++ . "`r`nNeedle:`r`n" . _NEEDLE . "`r`n`r`nHaystack:`r`n" . _HAYSTACK
}
