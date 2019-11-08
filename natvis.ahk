; This is a AutoHotKey script that converts a C++ class/struct to a natvis
; type declaration, 
;
; To use, highlight the class/struct from begining to end and then press ALT-
; SHIFT-2.  This will then be replace with corrisponding natvis definition.
;
; The following list the changes made:
;
;   1. C++ comments to XML comments
;   2. removes function definitions/declarations
;   3. Adds <Item Name="base_class_name [base]">(base_class_name*)this, nd</Item>
;      tags for each inherited class.
;   4. Adds <Item Name="static_var_name [static]">static_var_name</Item> tags 
;      for each member variable.
;   5. Adds <Item Name="member_var_name">member_var_name</Item> tags for each
;      member variable.
;
; Static and member variables will have the type added as a comment before the
; <Item> tag on the previous line.
;
; Anything not understood will be surrounded in XML comments.
;
; TODO:
;   1. Currently dones't recognise function pointers.
;   2. If there are a set of consecutive minus signs in a comment, they will be
;      not removed or modified, resulting in invalid XML.
;   3. Annomyous structs/class in a class/struct will get partially converted
;      as if part of the containing class/struct.
;
; LOG:
;  2017/02/01 - Fixed problem with capturing functions with =0, =delete and
;               =default.
;             - Improved regex which find function and variable names to reduce
;               backtracking, improving efficiency.
;             - Removed more blank lines from output.
;             - Indent is based on the leading whitespace before the class
;               / struct definition.
;  2019/11/07 - Now handles variable lists and types that are scope resolved
;               and have template parameters.
;  2019/11/08 - Now handles cv qualified types.

#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
#Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.

#include %A_LineFile%\..\Debug.ahk

function_re(classname)
{
  local re
  re =
    ( LTrim Comment
      mx)
        ^(?<leading>[ \t]*+)                                        ; Gets leading whitespace on the line.
        (?<virtual>(?:virtual\s+)?)                                 ; Gets virtual keyword if any
        (?:
          (?<type>
            (?<cv_qualifier>const\s++|volitile\s++)*+
            (?:
              (?:decltype\s*+\(([^()]|\((?-1)?\))*+\))        ; deal with decltype types
             |(?:[a-zA-Z_][a-zA-Z0-9_]*+\s*+                  
              (?:<\s*+                                        ; May have a template parameter list
                (?<template_param>                            
                   \g<type>                                   ; Template type parameter (can be empty)
                  |(?:[^<>(),]*+                              ;  Consists of either an equation not containing any "<>()," chars,
                    (?:\(([^()]|\((?-1)?\))*+\))?             ;  which may be followed by a parenthesized equation that may have <> or anything else,
                   `)*+                                       ;  which may be repeated 0 or more times.  NOTE: doesn't validate the equation. 
                `)                                            
                (?:,\s*+\g<template_param>)*+                 ; Template may have more than one. NOTE: Doesn't validate that previous parameter is not empty.
              \s*+>)?+)                                       
              (?: :: \g<type>)*+                              ; In case type type is scope resolved.
              (?:\g<cv_qualifier>|[*\s])*+                    ; 0 or more pointers or cv qualifiers.
              \&?                                             ; 0 or 1 reference.
            `)
          `)\s*                                                
          (*PRUNE) ; after this, if it fails, it fails.  No more backtracking.
          (?<name>(?>operator\s*(?:->\*?|\&\&|\|\||\+\+|--|[-+*/`%ˆ&|!=<>]=?|[~,]|(?:<<|>>)=?|\(\s*\)|\[\s*\]|"")|[a-zA-Z_][a-zA-Z_0-9]*))\s*                          ; Gets name of function
          | ~?%classname%

        `)
        (?<parms>(?>\((?:[^()]*+|(?-1))*\)))\s*                     ; Gets parameter list
        (?<cv>(?:const(?:\s+volitile)?|volitile(?:\s+const)?)?)\s*  ; Get cv qualifier if any
        (?<override>(?:override\s*(?=%semicolon%|{))?)              ; Get override keyword if any
        (?<body>(?>\s*+=\s*+(?>0|delete|default)\s*+)?%semicolon%|(?>\{(?:[^{}]|(?-1))*\}))  ; Gets body or '=0;', '=delete', '=default' or ';' if none
        (?:\s*%semicolon%)?                                         ; Remove random ; at end of function body.
    )
  return re
}

; Convert class/struct to natvis format
; DOESN'T handle nested classes/structs yet.
class2natvis()
{
  local clip := ClipboardAll, value := "", _, _leading, _name, _body, found, _bases, bases := "", className
    , __, __end := "", __static := "", __className, __assignment := "", one_item, additional

  ; Set the default callout function for use when debugging regular expressions.
  ;
  ; To use, add the capital letter C to the options list.  A message box will
  ; appear with what part of the needle it is looking at and what part of the
  ; haystack it has found.
  pcre_callout = DebugRegEx

  clipboard := ""
  Send ^c
  ClipWait 3
  if (clipboard != "")
  {
    value := clipboard
    semicolon := ";"
    lparen := "("
    classInfo_re = 
      ( LTrim Comment
        mxJ)
          ^(?<leading>[ \t]*+)                     ; Gets leading whitespace on the line.
          (
              (?:class|struct)\s+(?<name>[a-zA-Z_][a-zA-Z0-9_]*+)\s*  ; Gets the class name.
              (?::\s*(?<bases>(?:[^{]*))|(?<bases>))
              (?:[^{\%semicolon%]|[\r\n])*+            ; Skip over anything before the first '{' but fail if find a ';'.
              \{(?<body>(?>(?:[^{}])|\{(?-1)\})*+)\}   ; Extract the body out of the class.
            |
              typedef\s+struct
              (?<bases>)
              \s*+                                     ; Skip over whitespace before the first '{' but fail if find a ';'.
              \{(?<body>(?>(?:[^{}])|\{(?-1)\})*+)\}   ; Extract the body out of the class.
              \s*(?<name>[a-zA-Z_][a-zA-Z0-9_]*)       ; extract the name out of the typedef
          `)
          \s*%semicolon%?                          ; Wipe any trailing ';' if found.
      )
    base_re =
      ( LTrim Comment
        mx)
          ^(?:(?:public|protected|private)?+\s++|)
          (?<className>(?:[^\s,{<>]++|\s+|<(?-1)>)+)(?<!\s)
          (?:\s*,)?\s*+
      )
    variable_re =
      ( LTrim Comment
        mx)
          ^(?<leading>[ \t]*+)
          (?!typedef|using)
          (?<static>(?:static\s+)?+)
          (?<type>
            (?<cv_qualifier>const\s++|volitile\s++)*+
            (?:
              (?:decltype\s*+\(([^()]|\((?-1)?\))*+\))        ; deal with decltype types
             |(?:[a-zA-Z_][a-zA-Z0-9_]*+\s*+                  
              (?:<\s*+                                        ; May have a template parameter list
                (?<template_param>                            
                   \g<type>                                   ; Template type parameter (can be empty)
                  |(?:[^<>(),]*+                              ;  Consists of either an equation not containing any "<>()," chars,
                    (?:\(([^()]|\((?-1)?\))*+\))?             ;  which may be followed by a parenthesized equation that may have <> or anything else,
                   `)*+                                       ;  which may be repeated 0 or more times.  NOTE: doesn't validate the equation. 
                `)                                            
                (?:,\s*+\g<template_param>)*+                 ; Template may have more than one. NOTE: Doesn't validate that previous parameter is not empty.
              \s*+>)?+)                                       
              (?: :: \g<type>)*+                              ; In case type type is scope resolved.
              (?:\g<cv_qualifier>|[*\s])*+                    ; 0 or more pointers or cv qualifiers.
              \&?                                             ; 0 or 1 reference.
            `)
          `)\s*                                                
          (*PRUNE)                                            ; No more backtracking before this.
          (?<var>(?>[a-zA-Z_][a-zA-Z_0-9]*)(?<!operator))\s*+ ; Variable name.
          (?<array>(?:\[[^\]]*+])*+)\s*                       ; 0 or more array dimensions.
          (?::\s*+\d*+\s*+)?+                                 ; Bit field
          (?<assignment>=[^%semicolon%]*\s*)?+                ; default assignment of variable.
          (?<end>[%semicolon%,])
      )
    unrecognised_re =
      ( LTrim Comment
        mx)
          ^(?<leading>[\t ]*+)
          (?<unrecognised>
            (?!<) ; doesn't start with a <
            [^\s][^\r\n]* ; must contain at least one non whitespace on the line
          `)
      )
    fixNested_re =
      ( LTrim Comment
        mx)
          (?<leftOuter><!--(?>(?!<!--)(?!-->)[^-<]*+ (?:(?!-->)-?+|))*+)
          (?<inner>    <!--(?>        (?!-->) [^-]*+ (?:(?!-->)-?+|))*+-->)
          (?<rightOuter>   (?>        (?!-->) [^-]*+ (?:(?!-->)-?+|))*+-->)
      )
    emptyComment_re =
      ( LTrim Comment
        mx)
          (?:<!--\s*-->)
      )
    enum_re = 
      ( LTrim Comment
        mx)
          ^\s*enum
          (?:\s+class)? ; could be an enum class
          \s+(?:[a-zA-Z_](?>[a-zA-Z0-9_]+|[<>*&,\s]+)+) ; enum type name
          (?:[^{]*) ; ignore integral type this enum is based on
          \{[^}]*\}\s*%semicolon% ; enum body
      )
    friend_re =
      ( LTrim Comment
        mx)
          ^(?<leading>[\t ]*+)
          friend[^%semicolon%]+%semicolon%
      )
    blankLines_re =
    ( LTrim Comment
      mx)
          ^(?<leading>[\t ]*+)[\r\n]++
        
    )
    if (RegExMatch(value, classInfo_re, _))
    {
      ; replace /*...*/ comments
      _body := RegExReplace(_body, "/\* ?((?:[^ ]| (?!\*/))*) \*/", "<!-- $1 -->")
      ;msgbox Replaces comments 1:`n%_body%
      
      ; replace //... comments
      _body := RegExReplace(_body, "// ?([^\r\n]*)", "<!-- $1 -->")
      ;msgbox Replaces comments 2:`n%_body%
      
      ; replace nested enum declarations with nothing
      _body := RegExReplace(_body, enum_re, "")
      ;msgbox Replace function definitions/declarations:`n%_body%
      
      ; replace friend declarations with nothing
      _body := RegExReplace(_body, friend_re, "")
      ;msgbox Replaces friend declarations:`n%_body%
      
      ; replace functions or function declarations with nothing
      _body := RegExReplace(_body, function_re(_name), "")
      ;msgbox Replace function definitions/declarations:`n%_body%
      
      ; replace var declarations one at a time
      while (RegExMatch(_body, variable_re, __))
      {
        one_item
          ; comment describing type of variable and default if specified inline
          := _leading . _leading . _leading . "<!--" . (__static != "" ? " static" : "") . " ${type}${array}" . (__assignment != "" ? " (default " . __assignment . ")" : "") . " -->`r`n"
          .  _leading . _leading . _leading . "<Item Name='${var}" . (__static != "" ? " [static]" : "") . "'>${var}</Item>"
        additional := __end != ";" ? "`r`n${leading}" . (__static != "" ? " ${static}" : "") . "${type}" : ""

        _body := RegExReplace(_body, variable_re, one_item . additional ,, 1)
      }
      ;msgbox Replaces variable declarations:`n%_body%
      
      ; replace blank lines
      _body := RegExReplace(_body, blankLines_re, "")
      ;msgbox Replace blank lines:`n%_body%

      ;tooltip %_body%
      ; replace all other things not recognised as comments
      _body := RegExReplace(_body, unrecognised_re, "${leading}<!-- ${unrecognised} -->")
      ;msgbox Replaces unrecognised:`n%_body%

      ; Replace nested comments with unnested comments
      _body := RegExReplace(_body, fixNested_re, "${leftOuter}-->${inner}<!--${rightOuter}")
      ;msgbox Replacss nested comments:`n%_body%

      ; Replace empty comments with nothing
      _body := RegExReplace(_body, emptyComment_re, "")
      ;msgbox Removed empty comments:`n%_body%
      
      ; replace any multiple spaces or tabs with a single space within a comment
      loop {
        old := _body
        _body := RegExReplace(_body, "(<!--(?>(?:[^- \t]|-(?!->)| (?![ \t]))*))(?:[ \t]{2,}|\t)", "$1 ") ; should do this till no more replacements
      } until (old == _body)

      ; replace any spaces in front of comma with nothing
      loop {
        old := _body
        _body := RegExReplace(_body, ")(<!--(?>(?:[^- ]|-(?!->)|(?! ,) )*)) ", "$1") ; do this till no more replacements
      } until (old == _body)
      ; remove last CR LF
      _body := RegExReplace(_body, "mx)(?:\r\n?|\n\r?)*$", "")

      ; Get class base class names
      while (RegExMatch(_bases, base_re, __))
      {
        className := StrReplace(__className, "<", "&lt;")
        className := StrReplace(className, ">", "&gt;")
        bases .= _leading . _leading . _leading . "<Item Name='" . className . " [base]' ExcludeView='preview'>(" . className . "*)this, nd</Item>`r`n"
        _bases := RegExReplace(_bases, base_re, "",, 1)
      }
    }
    _body =
    ( LTrim Comment

      %_leading%<Type Name='%_name%'>
      %_leading%`t<DisplayString ExcludeView='preview'>{*this, view(preview)}</DisplayString>
      %_leading%`t<Expand>
      %bases%
      %_body%
      %_leading%`t</Expand>
      %_leading%</Type>

    )
    ; replace blank lines
    _body := RegExReplace(_body, blankLines_re, "")
    clipboard := _body
    ;tooltip %_body%, 0, 30, 1
    Send ^v
    sleep 1000
  }
  clipboard := clip
}


!+2::
  class2natvis()
  return


/* Test case:

  class testClass : public baseClass
  {
    int function(LPCTSTR param1);
    int function(LPCTSTR param2, int value)
    {
      /* some code here */
    }
    LPCSTR const strings[3];  // some LPCSTR strings
    int a, b, c;           // Converts list of vars.
    ns::tclass<abc> var;
    decltype(x()) y;       // Takes decltypes
    X<decltype(x)> y2;     // Takes templates with arbitrary parameters
    X<(x < 4),a, b<c>> y3;
    const X<> * const volitile * y4;
    
    struct a : b, c   // TODO: Does not handle nested struct/class yet.
    {
      int x = 3, y;
      type z;
    }
  }

  <Type Name='testClass'>
    <DisplayString ExcludeView='preview'>{*this, view(preview)}</DisplayString>
    <Expand>
      <Item Name='baseClass [base]' ExcludeView='preview'>(baseClass*)this, nd</Item>
      <!-- LPCSTR const [3] -->
      <Item Name='strings'>strings</Item>  <!-- some LPCSTR strings -->
      <!-- int -->
      <Item Name='a'>a</Item>
      <!-- int -->
      <Item Name='b'>b</Item>
      <!-- int -->
      <Item Name='c'>c</Item>           <!-- Converts list of vars. -->
      <!-- ns::tclass<abc> -->
      <Item Name='var'>var</Item>
      <!-- decltype(x()) -->
      <Item Name='y'>y</Item>       <!-- Takes decltypes -->
      <!-- X<decltype(x)> -->
      <Item Name='y2'>y2</Item>     <!-- Takes templates with arbitrary parameters -->
      <!-- X<(x < 4),a, b<c>> -->
      <Item Name='y3'>y3</Item>
      <!-- const X<> * const volitile * -->
      <Item Name='y4'>y4</Item>
    <!-- struct a : b, c --><!-- TODO: Does not handle nested struct/class yet. -->
    <!-- { -->
      <!-- int (default = 3, y) -->
      <Item Name='x'>x</Item>
      <!-- type -->
      <Item Name='z'>z</Item>
    <!-- } -->
    </Expand>
  </Type>

*/
