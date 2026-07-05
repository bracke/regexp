with AUnit.Assertions;

with Regexp;
with Regexp_Tests.Support;

package body Regexp_Tests.Api_Tests is
   use AUnit.Assertions;
   use Regexp;
   use Regexp_Tests.Support;

   procedure Test_API_Stability (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Invalid : Regexp.Regexp;
   begin
      Check_Limit (Default_Max_Pattern_Length, 256, "default max pattern length");
      Check_Limit (Default_Max_States, 512, "default max states");
      Check_Limit (Default_Max_Steps, 50_000, "default max steps");
      Assert (Regexp.Compile ("alias").Status = Regexp.Compile_Ok, "ada_regexp alias");
      Assert (not Is_Valid (Invalid), "default regexp invalid");
      Assert (Status_Image (Compile_Ok)'Length > 0, "compile status image");
      Assert (Status_Image (No_Match)'Length > 0, "match status image");
   end Test_API_Stability;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Regexp API tests");
   end Name;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_API_Stability'Access), "API stability");
   end Register_Tests;
end Regexp_Tests.Api_Tests;
