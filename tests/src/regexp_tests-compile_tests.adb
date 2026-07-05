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
      Check_Compile
        ("\d\D\w\W\s\S\.\*\+\?\(\)\[\]\{\}\\\^\$",
         Compile_Ok,
         "escapes");
   end Test_Compile_Valid;

   procedure Test_Compile_Errors (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Compile ("", Empty_Pattern, "empty pattern");
      Check_Compile ("[^]", Empty_Class, "negated empty class");
      Check_Compile_Error ("\x", Invalid_Escape, 2, "invalid escape");
      Check_Compile_Error ("[abc", Unterminated_Class, 4, "unterminated class");
      Check_Compile_Error ("[]", Empty_Class, 2, "empty class");
      Check_Compile_Error ("[z-a]", Invalid_Class_Range, 4, "invalid range");
      Check_Compile_Error ("[\x]", Invalid_Escape, 3, "invalid class escape");
      Check_Compile_Error ("[\d-z]", Invalid_Class_Range, 4, "class range starts with shorthand");
      Check_Compile_Error ("[a-\d]", Invalid_Class_Range, 5, "class range ends with shorthand");
      Check_Compile_Error ("*a", Quantifier_Without_Atom, 1, "leading quantifier");
      Check_Compile_Error ("a**", Invalid_Quantifier, 3, "repeated quantifier");
      Check_Compile_Error ("(a)", Unsupported_Syntax, 1, "unsupported grouping");
      Check_Compile_Error ("a|b", Unsupported_Syntax, 2, "unsupported alternation");
      Check_Compile_Error ("|a", Unsupported_Syntax, 1, "unsupported leading alternation");
      Check_Compile_Error ("a|", Unsupported_Syntax, 2, "unsupported trailing alternation");
      Check_Compile_Error ("a{1}", Unsupported_Syntax, 2, "unsupported bounded repeat");
      Check_Compile_Error ("{", Unsupported_Syntax, 1, "unsupported open brace");
      Check_Compile_Error ("}", Unsupported_Syntax, 1, "unsupported close brace");
      Check_Compile_Error (")", Unsupported_Syntax, 1, "unsupported close paren");
      Check_Compile_Error ("\", Invalid_Escape, 1, "trailing escape");

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
