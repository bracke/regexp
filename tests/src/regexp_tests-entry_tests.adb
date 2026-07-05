with AUnit.Assertions;

with Regexp;
with Regexp_Tests.Support;

package body Regexp_Tests.Entry_Tests is
   use AUnit.Assertions;
   use Regexp;
   use Regexp_Tests.Support;

   procedure Test_Match_Entry_Points (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Match ("abc", "abc", Match_Ok, "entire positive", 1, 3, Entire => True);
      Check_Match ("abc", "abcd", No_Match, "entire negative", Entire => True);

      declare
         Compiled : constant Compile_Result := Compile ("abc");
         Base     : constant String := "xxabcxx";
         Found    : constant Match_Result := Find_First (Compiled.Expression, Base (3 .. 5));
      begin
         Assert (Found.Status = Match_Ok, "slice status");
         Assert (Found.First = 1, "slice first is relative");
         Assert (Found.Last = 3, "slice last is relative");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("abc");
         Found    : constant Match_Result := Find_From (Compiled.Expression, "xxabcxx", 4);
      begin
         Assert (Found.Status = No_Match, "find from skips earlier match");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("abc");
         Found    : constant Match_Result := Find_From (Compiled.Expression, "xxabcxx", 3);
      begin
         Assert (Found.Status = Match_Ok, "find from exact status");
         Assert (Found.First = 3, "find from exact first");
         Assert (Found.Last = 5, "find from exact last");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("b");
         Base     : constant String := "xxabcxx";
         Found    : constant Match_Result := Find_From (Compiled.Expression, Base (3 .. 5), 2);
      begin
         Assert (Found.Status = Match_Ok, "find from slice status");
         Assert (Found.First = 2, "find from slice first is relative");
         Assert (Found.Last = 2, "find from slice last is relative");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("$");
         Found    : constant Match_Result := Find_From (Compiled.Expression, "abc", 4);
      begin
         Assert (Found.Status = Match_Ok, "find from end anchor status");
         Assert (Found.First = 4, "find from end anchor first");
         Assert (Found.Last = 3, "find from end anchor last");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("cat");
         Found    : constant Match_Result := Find_From
           (Compiled.Expression,
            "scatter cat",
            1,
            (Whole_Word => True, others => <>));
      begin
         Assert (Found.Status = Match_Ok, "find from whole word status");
         Assert (Found.First = 9, "find from whole word first");
         Assert (Found.Last = 11, "find from whole word last");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("z");
         Base     : constant String := "xxaaaaaaaa";
         Found    : constant Match_Result := Find_From
           (Compiled.Expression,
            Base (3 .. 10),
            1,
            (Max_Steps => 3, others => <>));
      begin
         Assert (Found.Status = Match_Limit_Exceeded, "find from slice low step limit");
         Assert (Found.Steps_Used = 3, "find from slice low steps used");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("z");
         Found_1  : constant Match_Result := Find_First
           (Compiled.Expression, "aaaaaaaa", (Max_Steps => 4, others => <>));
         Found_2  : constant Match_Result := Find_First
           (Compiled.Expression, "aaaaaaaa", (Max_Steps => 4, others => <>));
      begin
         Assert (Found_1.Status = Match_Limit_Exceeded, "step limit determinism status");
         Assert (Found_2.Status = Found_1.Status, "step limit deterministic status repeat");
         Assert (Found_2.Steps_Used = Found_1.Steps_Used, "step limit deterministic steps");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("abc");
         Found    : constant Match_Result := Find_From (Compiled.Expression, "abc", 4);
      begin
         Assert (Found.Status = No_Match, "find from length plus one literal");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("^");
         Base     : constant String := "xxabc";
         Found    : constant Match_Result := Find_From (Compiled.Expression, Base (3 .. 5), 1);
      begin
         Assert (Found.Status = Match_Ok, "slice start anchor status");
         Assert (Found.First = 1, "slice start anchor first");
         Assert (Found.Last = 0, "slice start anchor last");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("$");
         Base     : constant String := "xxabc";
         Found    : constant Match_Result := Find_From (Compiled.Expression, Base (3 .. 5), 4);
      begin
         Assert (Found.Status = Match_Ok, "slice end anchor from length plus one status");
         Assert (Found.First = 4, "slice end anchor first");
         Assert (Found.Last = 3, "slice end anchor last");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("a*");
         Found    : constant Match_Result := Find_From (Compiled.Expression, "", 1);
      begin
         Assert (Found.Status = Match_Ok, "find from empty status");
         Assert (Found.First = 1, "find from empty first");
         Assert (Found.Last = 0, "find from empty last");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("a*");
         Found    : constant Match_Result := Find_From (Compiled.Expression, "", 2);
      begin
         Assert (Found.Status = No_Match, "find from empty length plus one");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("abc");
         Base     : constant String := "xxabcxx";
         Found    : constant Match_Result := Matches_Entire (Compiled.Expression, Base (3 .. 5));
      begin
         Assert (Found.Status = Match_Ok, "entire slice status");
         Assert (Found.First = 1, "entire slice first is relative");
         Assert (Found.Last = 3, "entire slice last is relative");
      end;
   end Test_Match_Entry_Points;

   procedure Test_Invalid_Regexp_Entry_Points (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Invalid : Regexp.Regexp;
      Found   : Match_Result;
   begin
      Found := Find_First (Invalid, "abc");
      Assert (Found.Status = Invalid_Regexp, "invalid regexp find first");

      Found := Find_From (Invalid, "abc", 2);
      Assert (Found.Status = Invalid_Regexp, "invalid regexp find from");

      Found := Matches_Entire (Invalid, "abc");
      Assert (Found.Status = Invalid_Regexp, "invalid regexp matches entire");
   end Test_Invalid_Regexp_Entry_Points;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Regexp entry-point tests");
   end Name;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Match_Entry_Points'Access), "Match entry points");
      Register_Routine
        (T,
         AUnit.Test_Cases.Test_Routine'(Test_Invalid_Regexp_Entry_Points'Access),
         "Invalid regexp entry points");
   end Register_Tests;
end Regexp_Tests.Entry_Tests;
