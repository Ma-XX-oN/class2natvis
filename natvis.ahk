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
						(?:[a-zA-Z_](?>[a-zA-Z0-9_]+|[<>*&,\s]+)+)
						(?:  ; Backtrack to find the end of the type. Could be the end of the type if one of the following is true:
							 (?<=[a-zA-Z_0-9\s])(?=\s+[a-zA-Z_])    ; last char is a letter, number or underscore and the next is one or more whitespece followed by a letter or underscore.
							|(?<=[*&>\s])(?=[a-zA-Z_])  ; last char is a whitespace, *, & or > and the next is a whitespace, letter or underscore.
						`)
					`)\s*
					(*PRUNE) ; after this, if it fails, it fails.  No more backtracking.
					(?<name>(?>operator\s*(?:->\*?|\&\&|\|\||\+\+|--|[-+*/`%ˆ&|!=<>]=?|[~,]|(?:<<|>>)=?|\(\s*\)|\[\s*\]|"")|[a-zA-Z_][a-zA-Z_0-9]*))\s*                          ; Gets name of function
					| ~?%classname%

				`)
				(?<parms>(?>\((?:[^()]*+|(?-1))*\)))\s*                       ; Gets parameter list
				(?<cv>(?:const(?:\s+volitile)?|volitile(?:\s+const)?)?)\s*  ; Get cv qualifier if any
				(?<override>(?:override\s*(?=%semicolon%|{))?)              ; Get override keyword if any
				(?<body>(?>\s*+=\s*+(?>0|delete|default)\s*+)?%semicolon%|(?>\{(?:[^{}]|(?-1))*\}))  ; Gets body or '=0;', '=delete', '=default' or ';' if none
				(?:\s*%semicolon%)?                                         ; Remove random ; at end of function body.
		)
	return re
}

; Convert class/struct to natvis format
class2natvis()
{
	local clip := ClipboardAll, value := "", _, _leading, _name, _body, found, _bases, bases := "", className
		, __, __end := "", __static := "", __className, __assignment := "", one_item, additional

	; Set the default callout function for use when debugging regular expressions
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
						(?:[a-zA-Z_](?>[a-zA-Z0-9_]+|[<>*&,\s]+)+)
						(?:  ; Backtrack to find the end of the type. Could be the end of the type if one of the following is true:
							 (?<=[a-zA-Z_0-9\s])(?=\s+[a-zA-Z_])    ; last char is a letter, number or underscore and the next is one or more whitespece followed by a letter or underscore.
							|(?<=[*&>\s])(?=[a-zA-Z_])  ; last char is a whitespace, *, & or > and the next is a whitespace, letter or underscore.
						`)
					`)\s*
					(*PRUNE) ; after this, if it fails, it fails.  No more backtracking.
					(?<var>(?>[a-zA-Z_][a-zA-Z_0-9]*)(?<!operator))\s*+
					(?<array>(?:\[[^\]]*])?)\s*(?::\s*\d*\s*)?+
					(?<assignment>=[^%semicolon%]*\s*)?+ ; default assignment of variable
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
	}

	<Type Name='testClass'>
		<DisplayString ExcludeView='preview'>{*this, view(preview)}</DisplayString>
		<Expand>
			<Item Name='baseClass [base]' ExcludeView='preview'>(baseClass*)this, nd</Item>
			<!-- LPCSTR const [3] -->
			<Item Name='strings'>strings</Item>  <!-- some LPCSTR strings -->
		</Expand>
	</Type>
*/
