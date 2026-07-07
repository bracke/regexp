with AUnit.Assertions;

with Regexp;
with Regexp_Tests.Support;

package body Regexp_Tests.Compile_Tests is
   use AUnit.Assertions;
   use Regexp;
   use Regexp_Tests.Support;

   procedure Test_Compile_Valid (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Compile ("abc", Compile_Ok, "literal");
      Check_Compile (".", Compile_Ok, "dot");
      Check_Compile ("^abc$", Compile_Ok, "anchors");
      Check_Compile ("ab*c+d?", Compile_Ok, "quantifiers");
      Check_Compile ("[abc]", Compile_Ok, "class");
      Check_Compile ("[^abc]", Compile_Ok, "negated class");
      Check_Compile ("[a-z]", Compile_Ok, "range");
      Check_Compile ("[a-]", Compile_Ok, "trailing hyphen class");
      Check_Compile ("[-a]", Compile_Ok, "leading hyphen class");
      Check_Compile ("cat|dog", Compile_Ok, "alternation");
      Check_Compile ("cat|dog|fox", Compile_Ok, "multiple alternatives");
      Check_Compile ("(ab)", Compile_Ok, "capturing group");
      Check_Compile ("(cat|dog)", Compile_Ok, "capturing grouped alternation");
      Check_Compile ("(ab)+", Compile_Ok, "capturing grouped quantifier");
      Check_Compile ("(?<word>ab)", Compile_Ok, "named capture");
      Check_Compile ("(?<outer>a(?<inner>b))", Compile_Ok, "nested named captures");
      Check_Compile ("(?:ab)", Compile_Ok, "non-capturing group");
      Check_Compile ("(?:cat|dog)", Compile_Ok, "grouped alternation");
      Check_Compile ("(?:ab)+", Compile_Ok, "grouped quantifier");
      Check_Compile ("(?:ab){2,3}", Compile_Ok, "grouped bounded repeat");
      Check_Compile ("(?:(?:ab)|cd)", Compile_Ok, "nested non-capturing group");
      Check_Compile ("a(?=b)", Compile_Ok, "positive lookahead");
      Check_Compile ("a(?!b)", Compile_Ok, "negative lookahead");
      Check_Compile ("(?=ab)ab", Compile_Ok, "leading lookahead");
      Check_Compile ("(?:a)(?=b)", Compile_Ok, "lookahead after non-capturing group");
      Check_Compile ("(?<=a)b", Compile_Ok, "positive lookbehind");
      Check_Compile ("(?<!a)b", Compile_Ok, "negative lookbehind");
      Check_Compile ("(?<=ab|cd)e", Compile_Ok, "fixed-width alternation lookbehind");
      Check_Compile ("(?i:a)", Compile_Ok, "inline case-insensitive option");
      Check_Compile ("(?-i:a)", Compile_Ok, "inline case-sensitive option");
      Check_Compile ("(?m:^a)", Compile_Ok, "inline multiline option");
      Check_Compile ("(?s:.)", Compile_Ok, "inline dot-newline option");
      Check_Compile ("(?im-s:a)", Compile_Ok, "combined inline options");
      Check_Compile ("(a)\1", Compile_Ok, "numbered backreference");
      Check_Compile ("(?<word>a)\k<word>", Compile_Ok, "named backreference");
      Check_Compile ("a*+", Compile_Ok, "possessive star");
      Check_Compile ("a++", Compile_Ok, "possessive plus");
      Check_Compile ("a?+", Compile_Ok, "possessive optional");
      Check_Compile ("a{2,4}+", Compile_Ok, "possessive bounded repeat");
      Check_Compile ("(?>ab|a)", Compile_Ok, "atomic group");
      Check_Compile ("()", Compile_Ok, "empty capturing group");
      Check_Compile ("(?:)", Compile_Ok, "empty non-capturing group");
      Check_Compile ("|a", Compile_Ok, "leading empty alternative");
      Check_Compile ("a|", Compile_Ok, "trailing empty alternative");
      Check_Compile ("a||b", Compile_Ok, "middle empty alternative");
      Check_Compile ("a{2}", Compile_Ok, "exact bounded repeat");
      Check_Compile ("a{2,4}", Compile_Ok, "bounded repeat range");
      Check_Compile ("a{2,}", Compile_Ok, "open-ended bounded repeat");
      Check_Compile ("a{0,2}", Compile_Ok, "zero minimum bounded repeat");
      Check_Compile ("a*?", Compile_Ok, "lazy star");
      Check_Compile ("a+?", Compile_Ok, "lazy plus");
      Check_Compile ("a??", Compile_Ok, "lazy optional");
      Check_Compile ("a{2,4}?", Compile_Ok, "lazy bounded repeat");
      Check_Compile ("(?:ab)+?", Compile_Ok, "lazy grouped quantifier");
      Check_Compile ("[a-c]{2}", Compile_Ok, "class bounded repeat");
      Check_Compile ("\d{3}", Compile_Ok, "escape bounded repeat");
      Check_Compile ("\p{digit}", Compile_Ok, "unicode property at atom");
      Check_Compile ("\P{ascii}", Compile_Ok, "inverse unicode property at atom");
      Check_Compile ("[\\p{digit}]", Compile_Ok, "unicode property in class");
      Check_Compile
        ("\d\D\w\W\s\S\.\*\+\?\(\)\[\]\{\}\\\^\$\|",
         Compile_Ok,
         "escapes");
   end Test_Compile_Valid;

   procedure Test_Compile_Errors (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Compile ("", Empty_Pattern, "empty pattern");
      Check_Compile ("[^]", Empty_Class, "negated empty class");
      Check_Compile_Error ("\x", Invalid_Escape, 2, "invalid escape");
      Check_Compile_Error ("\p{bogus}", Invalid_Escape, 3, "invalid unicode property");
      Check_Compile_Error ("[abc", Unterminated_Class, 4, "unterminated class");
      Check_Compile_Error ("[]", Empty_Class, 2, "empty class");
      Check_Compile_Error ("[z-a]", Invalid_Class_Range, 4, "invalid range");
      Check_Compile_Error ("[\x]", Invalid_Escape, 3, "invalid class escape");
      Check_Compile_Error ("[\d-z]", Invalid_Class_Range, 4, "class range starts with shorthand");
      Check_Compile_Error ("[a-\d]", Invalid_Class_Range, 5, "class range ends with shorthand");
      Check_Compile_Error ("*a", Quantifier_Without_Atom, 1, "leading quantifier");
      Check_Compile_Error ("a**", Invalid_Quantifier, 3, "repeated quantifier");
      Check_Compile_Error ("(?<>a)", Invalid_Capture_Name, 1, "empty named capture");
      Check_Compile_Error ("(?<1>a)", Invalid_Capture_Name, 1, "bad named capture start");
      Check_Compile_Error ("(?<a-b>a)", Invalid_Capture_Name, 5, "bad named capture character");
      Check_Compile_Error ("(?<dup>a)(?<dup>b)", Duplicate_Capture_Name, 13, "duplicate named capture");
      Check_Compile_Error ("(?:a", Unsupported_Syntax, 4, "unterminated non-capturing group");
      Check_Compile_Error ("(?<=a*)b", Unsupported_Syntax, 1, "variable-width lookbehind");
      Check_Compile_Error ("(?<=a|bc)d", Unsupported_Syntax, 1, "uneven-width lookbehind");
      Check_Compile_Error ("\1", Invalid_Escape, 2, "missing numbered backreference target");
      Check_Compile_Error ("(a)\2", Invalid_Escape, 5, "missing numbered backreference");
      Check_Compile_Error ("(?<word>a)\k<missing>", Invalid_Escape, 12, "missing named backreference");
      Check_Compile_Error ("(?>((a)))", Unsupported_Syntax, 1, "atomic group captures unsupported");
      Check_Compile_Error ("(a)++", Unsupported_Syntax, 5, "possessive capture unsupported");
      Check_Compile_Error ("a{}", Invalid_Quantifier, 2, "empty bounded repeat");
      Check_Compile_Error ("a{,2}", Invalid_Quantifier, 2, "missing bounded repeat minimum");
      Check_Compile_Error ("a{3,2}", Invalid_Quantifier, 6, "inverted bounded repeat range");
      Check_Compile_Error ("a{2", Invalid_Quantifier, 2, "unterminated bounded repeat");
      Check_Compile_Error ("a{2}*", Invalid_Quantifier, 5, "repeated bounded repeat quantifier");
      Check_Compile_Error ("a*??", Invalid_Quantifier, 4, "repeated lazy quantifier");
      Check_Compile_Error ("a{2,4}??", Invalid_Quantifier, 8, "repeated lazy bounded repeat");
      Check_Compile_Error ("{", Unsupported_Syntax, 1, "unsupported open brace");
      Check_Compile_Error ("}", Unsupported_Syntax, 1, "unsupported close brace");
      Check_Compile_Error (")", Unsupported_Syntax, 1, "unsupported close paren");
      Check_Compile_Error ("\", Invalid_Escape, 1, "trailing escape");

      declare
         Too_Many_Groups : constant String :=
           "(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)";
      begin
         Check_Compile_Error (Too_Many_Groups, Too_Many_Captures, 49, "too many captures");
      end;

      declare
         Long   : constant String (1 .. Default_Max_Pattern_Length + 1) := [others => 'a'];
         Result : constant Compile_Result := Compile (Long);
      begin
         Assert (Result.Status = Pattern_Too_Long, "pattern too long status");
         Assert (Result.Error_Offset = Default_Max_Pattern_Length + 1, "pattern too long offset");
      end;

      declare
         Result : constant Compile_Result := Compile ("ab", Max_States => 2);
      begin
         Assert (Result.Status = Too_Many_States, "too many states status");
         Assert (Result.Error_Offset = 2, "too many states offset");
      end;

      declare
         Result : constant Compile_Result := Compile ("a{999}");
      begin
         Assert (Result.Status = Too_Many_States, "large repeat too many states status");
      end;
   end Test_Compile_Errors;

   procedure Test_Result_Shapes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      declare
         Result : constant Compile_Result := Compile ("");
      begin
         Assert (Result.Status = Empty_Pattern, "empty pattern status");
         Assert (Result.Error_Offset = 0, "empty pattern offset");
         Assert (not Is_Valid (Result.Expression), "compile failure expression invalid");
      end;

      declare
         Result : constant Compile_Result := Compile ("\x");
      begin
         Assert (Result.Status = Invalid_Escape, "invalid escape status");
         Assert (not Is_Valid (Result.Expression), "invalid escape expression invalid");
      end;

      declare
         Invalid : Regexp.Regexp;
         Found   : constant Match_Result := Find_First (Invalid, "abc");
      begin
         Assert (Found.Status = Invalid_Regexp, "invalid regexp status");
         Assert (Found.First = 0, "invalid regexp first");
         Assert (Found.Last = 0, "invalid regexp last");
         Assert (Found.Steps_Used = 0, "invalid regexp steps");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("z");
         Found    : constant Match_Result := Find_First (Compiled.Expression, "abc");
      begin
         Assert (Found.Status = No_Match, "no match status");
         Assert (Found.First = 0, "no match first");
         Assert (Found.Last = 0, "no match last");
      end;
   end Test_Result_Shapes;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Regexp compile tests");
   end Name;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Compile_Valid'Access), "Compile valid patterns");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Compile_Errors'Access), "Compile errors");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Result_Shapes'Access), "Result shapes");
   end Register_Tests;
end Regexp_Tests.Compile_Tests;
