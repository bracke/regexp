with AUnit.Assertions;

with Regexp;
with Regexp_Tests.Support;

package body Regexp_Tests.Focused_Tests is
   use AUnit.Assertions;
   use Regexp;
   use Regexp_Tests.Support;

   procedure Test_Default_Limits (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Limit (Default_Max_Pattern_Length, 256, "focused pattern limit");
      Check_Limit (Default_Max_States, 512, "focused state limit");
      Check_Limit (Default_Max_Steps, 50_000, "focused step limit");
   end Test_Default_Limits;

   procedure Test_Literal_Compile (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Compile ("abc", Compile_Ok, "focused literal compile");
   end Test_Literal_Compile;

   procedure Test_Invalid_Escape (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Compile_Error ("\x", Invalid_Escape, 2, "focused invalid escape");
   end Test_Invalid_Escape;

   procedure Test_Literal_Find (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Match ("abc", "xxabcxx", Match_Ok, "focused literal find", 3, 5);
   end Test_Literal_Find;

   procedure Test_Anchor_Match (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Match ("^abc$", "abc", Match_Ok, "focused anchored match", 1, 3);
   end Test_Anchor_Match;

   procedure Test_Character_Class (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Match ("[a-c]+", "xxbca", Match_Ok, "focused class match", 3, 5);
   end Test_Character_Class;

   procedure Test_Whole_Word (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Match
        ("cat",
         "a cat b",
         Match_Ok,
         "focused whole word",
         3,
         5,
         Options => (Whole_Word => True, others => <>));
   end Test_Whole_Word;

   procedure Test_Find_From (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Compiled : constant Compile_Result := Compile ("abc");
      Found    : constant Match_Result := Find_From (Compiled.Expression, "xxabcxx", 3);
   begin
      Assert (Found.Status = Match_Ok, "focused find from status");
      Assert (Found.First = 3, "focused find from first");
      Assert (Found.Last = 5, "focused find from last");
   end Test_Find_From;

   procedure Test_Invalid_Regexp (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Invalid : Regexp.Regexp;
      Found   : constant Match_Result := Find_First (Invalid, "abc");
   begin
      Assert (Found.Status = Invalid_Regexp, "focused invalid regexp status");
   end Test_Invalid_Regexp;

   procedure Test_Step_Limit (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Compiled : constant Compile_Result := Compile ("z");
      Found    : constant Match_Result := Find_First
        (Compiled.Expression, "aaaaaaaa", (Max_Steps => 4, others => <>));
   begin
      Assert (Found.Status = Match_Limit_Exceeded, "focused step limit status");
      Assert (Found.Steps_Used = 4, "focused step limit count");
   end Test_Step_Limit;

   --  UTF-8 code-point matching (Character_Mode => UTF_8_Mode). Multibyte
   --  literals are built from explicit bytes so the source encoding cannot fold
   --  them to Latin-1. Offsets are byte offsets. é=C3 A9, α=CE B1, δ=CE B4,
   --  ω=CF 89.
   procedure Test_Utf8_Codepoints (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      E_Acute : constant String := Character'Val (16#C3#) & Character'Val (16#A9#);
      Alpha   : constant String := Character'Val (16#CE#) & Character'Val (16#B1#);
      Delta_C : constant String := Character'Val (16#CE#) & Character'Val (16#B4#);
      Omega   : constant String := Character'Val (16#CF#) & Character'Val (16#89#);
   begin
      --  "." matches one whole code point (byte offsets 1 .. 2).
      Check_Match_Utf8 ("^.$", E_Acute, Match_Ok, "utf8 dot one codepoint", 1, 2);
      --  A quantifier counts code points: two dots over a two-code-point string.
      Check_Match_Utf8 ("^..$", E_Acute & E_Acute, Match_Ok, "utf8 dot quantifier", 1, 4);
      --  A positive code-point range: [α-ω] matches δ.
      Check_Match_Utf8 ("[" & Alpha & "-" & Omega & "]", Delta_C, Match_Ok,
                        "utf8 codepoint range", 1, 2);
      --  A negated class matches a whole multibyte code point.
      Check_Match_Utf8 ("[^a]", E_Acute, Match_Ok, "utf8 negated class", 1, 2);
      --  A multibyte literal matches its own code point.
      Check_Match_Utf8 (E_Acute, "x" & E_Acute & "y", Match_Ok, "utf8 literal", 2, 3);
      --  An ASCII letter is not in the Greek range.
      Check_Match_Utf8 ("[" & Alpha & "-" & Omega & "]", "x", No_Match, "utf8 range excludes ascii");
   end Test_Utf8_Codepoints;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Regexp focused regression tests");
   end Name;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Default_Limits'Access), "Focused default limits");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Literal_Compile'Access), "Focused literal compile");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Invalid_Escape'Access), "Focused invalid escape");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Literal_Find'Access), "Focused literal find");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Anchor_Match'Access), "Focused anchors");
      Register_Routine
        (T,
         AUnit.Test_Cases.Test_Routine'(Test_Character_Class'Access),
         "Focused character class");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Whole_Word'Access), "Focused whole word");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Find_From'Access), "Focused find from");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Invalid_Regexp'Access), "Focused invalid regexp");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Step_Limit'Access), "Focused step limit");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Utf8_Codepoints'Access), "Focused UTF-8 codepoints");
   end Register_Tests;
end Regexp_Tests.Focused_Tests;
