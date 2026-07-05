with AUnit.Assertions;

with Regexp;

package body Regexp_Tests.Limit_Tests is
   use AUnit.Assertions;
   use Regexp;

   procedure Test_Match_Limits (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      declare
         Compiled : constant Compile_Result := Compile ("a*a*a*a*a*b");
         Found    : constant Match_Result := Find_First
           (Compiled.Expression,
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            (Max_Steps => 3, others => <>));
      begin
         Assert (Found.Status = Match_Limit_Exceeded, "low match step limit");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("a");
         Found    : constant Match_Result := Find_First
           (Compiled.Expression,
            "a",
            (Max_Steps => 0, others => <>));
      begin
         Assert (Found.Status = Match_Limit_Exceeded, "zero match step limit");
         Assert (Found.Steps_Used = 0, "zero match steps used");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("a*a*a*a*a*b");
         Found    : constant Match_Result := Matches_Entire
           (Compiled.Expression,
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            (Max_Steps => 3, others => <>));
      begin
         Assert (Found.Status = Match_Limit_Exceeded, "matches entire low step limit");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("z");
         Found    : constant Match_Result := Find_First
           (Compiled.Expression,
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            (Max_Steps => 5, others => <>));
      begin
         Assert (Found.Status = Match_Limit_Exceeded, "find first total step limit");
         Assert (Found.Steps_Used = 5, "find first total steps used");
      end;

      declare
         Pattern  : constant String := "a*a*a*a*a*a*a*a*a*a*b";
         Compiled : constant Compile_Result := Compile (Pattern);
         Found    : constant Match_Result := Find_First
           (Compiled.Expression,
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            (Max_Steps => Default_Max_Steps, others => <>));
      begin
         Assert (Compiled.Status = Compile_Ok, "pathological pattern compiles");
         Assert (Found.Status /= Match_Limit_Exceeded, "pathological pattern bounded under generous limit");
      end;
   end Test_Match_Limits;

   procedure Test_Compile_Limits (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      declare
         Result : constant Compile_Result := Compile ("ab", Max_States => 2);
      begin
         Assert (Result.Status = Too_Many_States, "too many states simple pattern");
      end;

      declare
         Result : constant Compile_Result := Compile ("a*", Max_States => 2);
      begin
         Assert (Result.Status = Too_Many_States, "too many states quantified pattern");
      end;

      declare
         Exact_Max : constant String (1 .. Default_Max_Pattern_Length) := [others => 'a'];
         Result    : constant Compile_Result := Compile (Exact_Max);
      begin
         Assert (Result.Status = Compile_Ok, "exact max pattern length compile");
      end;

      declare
         Result : constant Compile_Result := Compile ("a", Max_States => 1);
      begin
         Assert (Result.Status = Too_Many_States, "one atom still needs match state");
      end;
   end Test_Compile_Limits;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Regexp limit tests");
   end Name;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Match_Limits'Access), "Match limits");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Compile_Limits'Access), "Compile limits");
   end Register_Tests;
end Regexp_Tests.Limit_Tests;
