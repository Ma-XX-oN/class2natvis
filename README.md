# class2natvis
## Brief Description
Converts classes/structs to a natvis format.

## Detail
Having to convert a class or a struct to a natvis type representation is a bit
of a PITA if you want to include all of the elements and want to be reminded as
to what the types are being represented.

This uses [AutoHotKey][1] to aid in quickly trying to convert
classes/structures into a format which is still fairly readable.

I got tired of doing this manually so I used my knowledge of AHK and its regex
engine to convert a class/struct to a natvis <Type> tag format.

## Usage
Highlight a complete copy of the class/struct where you want it to be
converted, and then press Ctrl-Shift-2.  This will then replace the highlighted
copy with the natvis <Type> block.

The indent character is the whitespace located directly to the left of the
class/struct definition.

I normally do this directly in my .natvis file, but this will work in any
editor, in any file.

## Quick Start
1. Clone this repository in your Documents folder.
2. Download and install [AutoHotKey][1] if you haven't already.
3. In your %USERPROFILE%\Documents\AutoHotKey.ahk file, add to the end of the
   file:
    ```
    #include %A_LineFile%\..\class2natvis\natvis.ahk
    ```
   and save it.
4. Reload the AHK script
  1. Go to your system tray and find the green H icon.
  2. Right click on it and select `Reload This Script`.
5. Now try it out! :)

## Caveats
At the moment, this doesn't recognise function pointers or nested
classes/struct, anonymous classes/structs and will convert only one
class/struct at a time.  There may be some ways that I've not thought of which
may not recognising certain constructs.  Feel free to leave a bug report or add
a fix.  I'm not very sure how the push/pull thing works on git so please be
patient.


[1]: https://autohotkey.com/
