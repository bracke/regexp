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
      Check_Limit (Default_Stream_Buffer_Length, 4_096, "default stream buffer length");
      Check_Limit (Max_Captures, 16, "max captures");
      Check_Limit (Max_Capture_Name_Length, 32, "max capture name length");
      Assert (Regexp.Compile ("alias").Status = Regexp.Compile_Ok, "ada_regexp alias");
      Assert (not Is_Valid (Invalid), "default regexp invalid");
      Assert (Status_Image (Compile_Ok)'Length > 0, "compile status image");
      Assert (Status_Image (Too_Many_Captures)'Length > 0, "capture status image");
      Assert (Status_Image (Invalid_Capture_Name)'Length > 0, "invalid capture name image");
      Assert (Status_Image (Duplicate_Capture_Name)'Length > 0, "duplicate capture name image");
      Assert (Status_Image (No_Match)'Length > 0, "match status image");
      Assert (Status_Image (Find_All_Ok)'Length > 0, "find all status image");
      Assert (Status_Image (Replace_Ok)'Length > 0, "replace status image");
      Assert (Status_Image (Replacement_Invalid_Escape)'Length > 0, "replacement validation status image");
      Assert (Status_Image (Split_Ok)'Length > 0, "split status image");
      Assert (Status_Image (Copy_Ok)'Length > 0, "copy status image");
      Assert (Status_Image (Stream_Match)'Length > 0, "stream status image");
      Assert (Status_Image (Policy_Ok)'Length > 0, "policy status image");
      Assert (Is_Syntax_Error (Invalid_Escape), "syntax error helper");
      Assert (Is_Unsupported (Unsupported_Syntax), "unsupported helper");
      Assert (Is_Limit_Error (Too_Many_States), "compile limit helper");
      Assert (Is_Limit_Error (Match_Limit_Exceeded), "match limit helper");
      Assert (Is_Limit_Error (Find_All_Limit_Exceeded), "find all limit helper");
      Assert (Is_Limit_Error (Replace_Limit_Exceeded), "replace limit helper");
      Assert (Is_Limit_Error (Split_Limit_Exceeded), "split limit helper");
      Assert (Is_Limit_Error (Stream_Buffer_Full), "stream limit helper");
      Assert (Supports_Syntax (Syntax_Posix_Classes), "syntax support query");
      declare
         Syntaxes : Syntax_Feature_Array (1 .. 32);
         Count    : Natural;
         Complete : Boolean;
      begin
         Supported_Syntax (Syntaxes, Count, Complete);
         Assert (Complete and then Count = Syntax_Feature'Pos (Syntax_Feature'Last) + 1,
                 "supported syntax inventory");
         Assert (Syntax_Feature_Image (Syntax_Lookahead) = "lookahead", "syntax feature image");
         Assert (Supports_Syntax (Syntax_Unicode_Properties), "unicode properties syntax support");
         Assert (Syntax_Feature_Image (Syntax_Unicode_Properties) = "unicode properties",
                 "unicode properties syntax image");
      end;
      Assert (Default_Options.Max_Steps = Default_Max_Steps, "default options constant");
      Assert (Case_Sensitive_Options.Case_Sensitive, "case-sensitive options constant");
      Assert (Multiline_Options.Multiline_Anchors, "multiline options constant");
      Assert (Dot_All_Options.Dot_Matches_Newline, "dot-all options constant");
      Assert (Capture_Count (Compile ("(a)(b)").Expression) = 2, "capture count");
      Assert (Capture_Index (Compile ("(?<word>a)").Expression, "word") = 1, "capture index");
      Assert (Capture_Index (Compile ("(?<word>a)").Expression, "missing") = 0, "missing capture index");
      declare
         Compiled : constant Compile_Result := Compile ("(?<word>a)(b)");
         Name     : String (1 .. Max_Capture_Name_Length);
         Indexes  : Capture_Index_Array (1 .. 2);
         Count    : Natural;
         Complete : Boolean;
         Last     : Natural;
         Status   : Copy_Status;
      begin
         Capture_Name (Compiled.Expression, 1, Name, Last, Status);
         Assert (Status = Copy_Ok and then Name (1 .. Last) = "word", "capture name copy");
         Capture_Name (Compiled.Expression, 2, Name, Last, Status);
         Assert (Status = Copy_No_Match, "unnamed capture name copy");
         Named_Captures (Compiled.Expression, Indexes, Count, Complete);
         Assert (Complete and then Count = 1 and then Indexes (1) = 1, "named capture inventory");
      end;
      Assert (Capture_Count (Compile ("(?=(a))b").Expression) = 0, "lookahead capture count");
      Assert (Capture_Count (Compile ("(?<=(a))b").Expression) = 0, "lookbehind capture count");
      Assert (Capture_Count (Invalid) = 0, "invalid capture count");
      Assert (Has_Captures (Compile ("(a)").Expression), "has captures");
      Assert (not Has_Captures (Compile ("(?:a)").Expression), "no exported captures");
      Assert (Uses_Anchors (Compile ("^a$").Expression), "uses anchors");
      Assert (not Uses_Anchors (Compile ("abc").Expression), "does not use anchors");
      Assert (May_Match_Empty (Compile ("a*").Expression), "star may match empty");
      Assert (May_Match_Empty (Compile ("()").Expression), "empty group may match empty");
      Assert (not May_Match_Empty (Compile ("a+").Expression), "plus does not match empty");
      Assert (Diagnostic_Image (Compile ("\x"))'Length > 0, "compile diagnostic image");
      Assert (Find_First (Compile ("[[:digit:]]+").Expression, "abc123").Status = Match_Ok,
              "posix digit class");
      Assert (Find_First (Compile ("[[:alpha:]]+").Expression, "123abc").Status = Match_Ok,
              "posix alpha class");
      Assert (Compile (Identifier_Pattern).Status = Compile_Ok, "identifier preset");
      Assert (Compile (Integer_Pattern).Status = Compile_Ok, "integer preset");
      Assert (Compile (Whitespace_Run_Pattern).Status = Compile_Ok, "whitespace preset");
      Assert (Compile (Path_Segment_Pattern).Status = Compile_Ok, "path segment preset");
      Assert (Compile (UUID_Pattern).Status = Compile_Ok, "uuid preset");
      Assert (Compile (Hex_Integer_Pattern).Status = Compile_Ok, "hex integer preset");
      Assert (Compile (Quoted_String_Pattern).Status = Compile_Ok, "quoted string preset");
      Assert (Compile (Line_Comment_Pattern).Status = Compile_Ok, "line comment preset");
      Assert (Compile (Path_Extension_Pattern).Status = Compile_Ok, "path extension preset");
      Assert (Compile (Simple_Email_Pattern).Status = Compile_Ok, "simple email preset");
      Assert (Compile (Simple_URL_Pattern).Status = Compile_Ok, "simple url preset");
      Assert (Digit_Class = "\d", "digit class constant");
      Assert (Identifier_Start_Class = "[A-Z_]", "identifier start class constant");
      Assert (Find_First (Compile (UUID_Pattern).Expression, "550e8400-e29b-41d4-a716-446655440000").Status = Match_Ok,
              "uuid preset match");
      Assert (Find_First (Compile (Quoted_String_Pattern).Expression, """a\""b""").Status = Match_Ok,
              "quoted string preset match");
      Assert (Escape_Literal ("") = "", "escape literal empty");
      Assert (Escape_Literal ("a.c|d") = "a\.c\|d", "escape literal metacharacters");
      Assert
        (Find_First
           (Compile ("^" & Escape_Literal ("a.c|d") & "$").Expression,
            "a.c|d",
            (others => <>)).Status = Match_Ok,
         "escaped literal embeds in larger pattern");

      declare
         Alternatives : String (1 .. 64);
         Alt_Last     : Natural := 0;
         Pattern      : String (1 .. 64);
         Last         : Natural := 0;
         Status       : Copy_Status;
      begin
         Append_Literal_Alternative ("a.c", Alternatives, Alt_Last, Status);
         Assert (Status = Copy_Ok, "append first literal alternative");
         Append_Literal_Alternative ("x+y", Alternatives, Alt_Last, Status);
         Assert (Status = Copy_Ok, "append second literal alternative");
         Assert (Alternatives (1 .. Alt_Last) = "a\.c|x\+y", "literal alternation branches");

         Append_Fragment ("^(", Pattern, Last, Status);
         Assert (Status = Copy_Ok, "append opening fragment");
         Append_Fragment (Alternatives (1 .. Alt_Last), Pattern, Last, Status);
         Assert (Status = Copy_Ok, "append alternation fragment");
         Append_Fragment (")$", Pattern, Last, Status);
         Assert (Status = Copy_Ok, "append closing fragment");
         Assert (Pattern (1 .. Last) = "^(a\.c|x\+y)$", "composed literal alternation");
         Assert (Find_First (Compile (Pattern (1 .. Last)).Expression, "x+y").Status = Match_Ok,
                 "composed literal alternation matches");
      end;

      declare
         Text     : constant String := "a.c x+y";
         Terms    : constant Text_Range_Array := [1 => (First => 1, Last => 3), 2 => (First => 5, Last => 7)];
         Compiled : constant Compile_Result := Compile_Literal_Set (Text, Terms);
      begin
         Assert (Compiled.Status = Compile_Ok, "compile literal set status");
         Assert (Find_First (Compiled.Expression, "x+y").Status = Match_Ok, "literal set second term");
         Assert (Find_First (Compiled.Expression, "xy").Status = No_Match, "literal set escaped plus");
      end;

      declare
         Text     : constant String := "cat dog";
         Terms    : constant Text_Range_Array := [1 => (First => 1, Last => 3), 2 => (First => 5, Last => 7)];
         Compiled : constant Compile_Result := Compile_Literal_Word_Set (Text, Terms);
      begin
         Assert (Compiled.Status = Compile_Ok, "compile literal word set status");
         Assert (Find_First (Compiled.Expression, "the dog ran").Status = Match_Ok, "literal word set match");
         Assert (Find_First (Compiled.Expression, "hotdog").Status = No_Match, "literal word set boundary");
      end;

      declare
         Anchored     : constant Compile_Result := Compile_Anchored ("a+");
         Whole_Word   : constant Compile_Result := Compile_Whole_Word ("cat");
         Lit_Anchored : constant Compile_Result := Compile_Literal_Anchored ("a.c");
         Lit_Word     : constant Compile_Result := Compile_Literal_Whole_Word ("cat");
         Line         : constant Compile_Result := Compile_Line ("two");
         Lit_Line     : constant Compile_Result := Compile_Literal_Line ("a.c");
      begin
         Assert (Find_First (Anchored.Expression, "aaa").Status = Match_Ok, "anchored compile match");
         Assert (Find_First (Anchored.Expression, "baaa").Status = No_Match, "anchored compile rejects prefix");
         Assert (Find_First (Whole_Word.Expression, "a cat").Status = Match_Ok, "whole word compile match");
         Assert (Find_First (Whole_Word.Expression, "scatter").Status = No_Match, "whole word compile boundary");
         Assert (Find_First (Lit_Anchored.Expression, "a.c").Status = Match_Ok, "literal anchored compile");
         Assert (Find_First (Lit_Word.Expression, "a cat").Status = Match_Ok, "literal whole word compile");
         Assert (Find_First (Line.Expression, "one" & Character'Val (10) & "two").Status = Match_Ok,
                 "line compile");
         Assert (Find_First (Lit_Line.Expression, "a.c").Status = Match_Ok, "literal line compile");
      end;

      declare
         Pattern : String (1 .. 16);
         Last    : Natural := 0;
         Status  : Copy_Status;
      begin
         Append_Fragment ("[", Pattern, Last, Status);
         Assert (Status = Copy_Ok, "class opening append");
         Append_Class_Range ('a', 'c', Pattern, Last, Status);
         Assert (Status = Copy_Ok, "class range append");
         Append_Class_Literal (']', Pattern, Last, Status);
         Assert (Status = Copy_Ok, "class literal append");
         Append_Fragment ("]", Pattern, Last, Status);
         Assert (Status = Copy_Ok and then Pattern (1 .. Last) = "[a-c\]]", "class builder pattern");
      end;

      declare
         Text    : constant String := "cat dog";
         Terms   : constant Text_Range_Array := [1 => (First => 1, Last => 3), 2 => (First => 5, Last => 7)];
         Pattern : String (1 .. 32);
         Last    : Natural;
         Status  : Copy_Status;
      begin
         Build_Literal_Alternation (Text, Terms, Pattern, Last, Status);
         Assert (Status = Copy_Ok and then Pattern (1 .. Last) = "cat|dog", "literal alternation builder");
         Build_Literal_Word_Alternation (Text, Terms, Pattern, Last, Status);
         Assert (Status = Copy_Ok and then Pattern (1 .. Last) = "\b(?:cat|dog)\b",
                 "literal word alternation builder");
      end;

      declare
         Text     : constant String := "";
         Terms    : constant Text_Range_Array := [1 => (First => 1, Last => 0)];
         Compiled : constant Compile_Result := Compile_Literal_Set (Text, Terms);
      begin
         Assert (Compiled.Status = Compile_Ok, "compile empty literal set term");
         Assert (Find_First (Compiled.Expression, "").Status = Match_Ok, "empty literal set term matches");
      end;

      declare
         Pattern : String (1 .. 3);
         Last    : Natural := 0;
         Status  : Copy_Status;
      begin
         Append_Literal ("a.c", Pattern, Last, Status);
         Assert (Status = Copy_Output_Too_Small, "append literal too small");
      end;

      declare
         Prefix : String (1 .. 8);
         Last   : Natural;
         Status : Copy_Status;
      begin
         Required_Prefix (Compile ("^abc\d+").Expression, Prefix, Last, Status);
         Assert (Status = Copy_Ok, "required prefix status");
         Assert (Prefix (1 .. Last) = "abc", "required prefix value");

         Required_Prefix (Compile ("cat|dog").Expression, Prefix, Last, Status);
         Assert (Status = Copy_Ok, "empty required prefix status");
         Assert (Last = 0, "empty required prefix value");

         Required_Prefix (Compile ("abcdef").Expression, Prefix (1 .. 3), Last, Status);
         Assert (Status = Copy_Output_Too_Small, "required prefix too small");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("^(?<word>a+)\b(?=z)");
         F        : constant Pattern_Features := Features (Compiled.Expression);
         Policy   : Pattern_Policy := (others => True);
         Status   : Pattern_Policy_Status;
         Seen     : Pattern_Features;
      begin
         Assert (F.Has_Captures, "features captures");
         Assert (F.Has_Named_Captures, "features named captures");
         Assert (F.Has_Anchors, "features anchors");
         Assert (F.Has_Word_Boundaries, "features word boundaries");
         Assert (F.Has_Lookaround, "features lookaround");
         Assert (F.Has_Splits, "features splits");
         Assert (not Features (Invalid).Has_Captures, "invalid features empty");
         Assert (Is_Literal (Compile ("abc").Expression), "literal classifier");
         Assert (Is_Anchored (Compile ("^abc").Expression), "anchored classifier");
         Assert (Is_Whole_Line (Compile_Line ("abc").Expression), "whole-line classifier");
         Assert (Needs_Backtracking (Compile ("a|b").Expression), "backtracking classifier");
         Assert (Can_Stream_Safely (Compile ("abc").Expression), "stream safe classifier");
         Assert (Recommended_Strategy (Compile ("abc").Expression) = Search_Literal, "literal strategy");
         Assert (Recommended_Strategy (Compile ("^abc").Expression) = Search_Anchored, "anchored strategy");
         Assert (Recommended_Strategy (Compile ("abc\d+").Expression) = Search_Prefix, "prefix strategy");
         declare
            Compiled : constant Compile_Result := Compile_Anchored ("abc");
            Sum      : constant Expression_Summary := Summary (Compiled.Expression);
            Source   : String (1 .. 32);
            Last     : Natural;
            C_Status : Copy_Status;
         begin
            Assert (Sum.Valid and then Sum.Source_Kind = Source_Anchored, "expression summary source");
            Assert (Source_Kind (Compiled.Expression) = Source_Anchored, "source kind");
            Copy_Source_Pattern (Compiled.Expression, Source, Last, C_Status);
            Assert (C_Status = Copy_Ok and then Source (1 .. Last) = "^(?:abc)$", "copy source pattern");
         end;
         declare
            L : constant Pattern_Lint := Lint (Compile (".*").Expression);
         begin
            Assert (L.Valid and then L.Broad_Dot_Star and then L.May_Match_Empty, "pattern lint");
         end;
         Validate_Policy (Compiled.Expression, Policy, Status, Seen);
         Assert (Status = Policy_Ok and then Seen.Has_Lookaround, "policy ok");
         Policy.Allow_Lookaround := False;
         Validate_Policy (Compiled.Expression, Policy, Status, Seen);
         Assert (Status = Policy_Disallowed_Feature, "policy disallowed feature");
         Validate_Policy (Compile ("abc").Expression, Literal_Search_Policy, Status, Seen);
         Assert (Status = Policy_Ok, "literal policy preset");
         Validate_Policy (Compile ("a*").Expression, Safe_User_Search_Policy, Status, Seen);
         Assert (Status = Policy_Disallowed_Empty_Match, "safe user policy empty");
         Validate_Policy (Compile ("(?=a)a").Expression, Streaming_Search_Policy, Status, Seen);
         Assert (Status = Policy_Disallowed_Feature, "streaming policy lookahead");
         Validate_Policy (Compile ("(?=a)a").Expression, Editor_Replace_Policy, Status, Seen);
         Assert (Status = Policy_Ok, "editor replace policy");
         Validate_Policy (Compile ("a*").Expression, No_Empty_Match_Policy, Status, Seen);
         Assert (Status = Policy_Disallowed_Empty_Match, "no empty policy");
         Validate_Policy (Compile ("(?=a)a").Expression, No_Lookaround_Policy, Status, Seen);
         Assert (Status = Policy_Disallowed_Feature, "no lookaround policy");
         Validate_Policy (Compile ("(a)\1").Expression, No_Backreferences_Policy, Status, Seen);
         Assert (Status = Policy_Disallowed_Feature, "no backreferences policy");
         declare
            Detail : constant Pattern_Policy_Diagnostic :=
              Validate_Policy_Detail (Compile ("(?=a)a").Expression, Streaming_Search_Policy);
         begin
            Assert
              (Detail.Status = Policy_Disallowed_Feature
               and then Detail.Feature = Policy_Feature_Lookaround,
               "policy detail feature");
         end;
      end;

      declare
         Bad      : constant Compile_Result := Compile ("[");
         Diag     : constant Compile_Diagnostic_Record := Compile_Diagnostic (Bad);
         Compiled : constant Compile_Result := Compile ("(?<word>\w+)");
         R_Diag   : constant Replacement_Diagnostic_Record :=
           Replacement_Diagnostic (Compiled.Expression, "\k<missing>");
         Nodes    : Expression_Node_Array (1 .. 16);
         Count    : Natural;
         Complete : Boolean;
         Summary  : constant Find_All_Summary_Result := Benchmark_Summary (Benchmark_Integer);
         Names    : Token_Name_Array (1 .. 1);
         N_Status : Copy_Status;
         Output   : String (1 .. 16);
         Last     : Natural;
         UTF8     : constant UTF_8_Validation_Result := Validate_UTF_8 ("h" & Character'Val (16#C3#)
                                                                         & Character'Val (16#A6#));
         Members  : String (1 .. 8);
         M_Last   : Natural := 0;
         Class    : String (1 .. 12);
         Fp       : Pattern_Fingerprint;
         Meta     : Pattern_Metadata;
         Support  : Syntax_Support_Array (1 .. 32);
         S_Count  : Natural;
         S_Full   : Boolean;
         Notes    : String (1 .. 512);
         N_Last   : Natural;
         Examples : String (1 .. 512);
         E_Last   : Natural;
      begin
         Assert (Diag.Kind = Diagnostic_Syntax and then Diag.Offset = 1, "compile diagnostic");
         Assert (R_Diag.Kind = Diagnostic_Unknown_Capture, "replacement diagnostic");
         Explain_Nodes (Compiled.Expression, Nodes, Count, Complete);
         Assert (Count > 0 and then Complete, "explain nodes complete");
         Assert (Nodes (1).Kind /= Expression_Node_Invalid, "explain nodes kind");
         Assert (Nodes (1).Has_Scoped_Options = False, "explain nodes flags");
         Assert (Benchmark_Pattern (Benchmark_Key_Value) = "(?<key>[A-Z_]\w*)=(?<value>\d+)",
                 "benchmark pattern");
         Assert (Benchmark_Text (Benchmark_Integer)'Length > 0, "benchmark text");
         Assert (Summary.Status = Find_All_Ok and then Summary.Count = 4, "benchmark summary");
         Make_Token_Name (10, "word", Names (1), N_Status);
         Assert (N_Status = Copy_Ok, "make token name");
         Copy_Token_Name (Names, 10, Output, Last, N_Status);
         Assert (N_Status = Copy_Ok and then Output (1 .. Last) = "word", "copy token name");
         Assert (UTF8.Valid and then UTF_8_Options.Character_Mode = UTF_8_Mode, "utf8 validation");
         Append_Class_Range ('a', 'z', Members, M_Last, N_Status);
         Build_Character_Class (Members (1 .. M_Last), False, Class, Last, N_Status);
         Assert (N_Status = Copy_Ok and then Class (1 .. Last) = "[a-z]", "build character class");
         Fp := Fingerprint (Compiled.Expression);
         Meta := Metadata (Compiled.Expression);
         Assert (Fp.Hash /= 0 and then Meta.Valid and then Meta.Fingerprint.Hash = Fp.Hash,
                 "fingerprint metadata");
         Supported_Syntax_Detail (Support, S_Count, S_Full, Notes, N_Last, Examples, E_Last);
         Assert (S_Full and then S_Count > 0 and then N_Last > 0 and then E_Last > 0,
                 "syntax support detail");
      end;

      declare
         Text     : constant String := "one" & Character'Val (10) & "two three";
         Compiled : constant Compile_Result := Compile ("two");
         Found    : Match_Result := Find_First (Compiled.Expression, Text);
         Pos      : Source_Position;
         Line     : Text_Range;
         Before   : Text_Range;
         Match    : Text_Range;
         After    : Text_Range;
         Status   : Copy_Status;
         Output   : String (1 .. 16);
         Last     : Natural;
      begin
         Find_First_Line (Compiled.Expression, Text, Found, Pos, Line);
         Assert (Found.Status = Match_Ok, "find first line status");
         Assert (Pos.Line = 2 and then Pos.Column = 1, "find first line position");
         Assert (Line.First = 5 and then Line.Last = 13, "find first line range");
         Pos := Line_Column (Text, Found.First);
         Assert (Pos.Line = 2 and then Pos.Column = 1, "match line column");
         Line := Match_Line_Range (Text, Found);
         Assert (Line.First = 5 and then Line.Last = 13, "match line range");
         Match_Context (Text, Found, Before, Match, After, Status);
         Assert (Status = Copy_Ok, "match context status");
         Assert (Before = (First => 1, Last => 4), "match context before");
         Assert (Match = (First => 5, Last => 7), "match context match");
         Assert (After = (First => 8, Last => 13), "match context after");
         Assert (Line_Column (Text, 0) = (Line => 0, Column => 0), "invalid line column");

         Copy_Before (Text, Found, Output, Last, Status);
         Assert (Status = Copy_Ok and then Output (1 .. Last) = "one" & Character'Val (10),
                 "copy before match");
         Copy_Match (Text, Found, Output, Last, Status);
         Assert (Status = Copy_Ok and then Output (1 .. Last) = "two", "copy match");
         Copy_After (Text, Found, Output, Last, Status);
         Assert (Status = Copy_Ok and then Output (1 .. Last) = " three", "copy after match");
         Copy_Match_Line (Text, Found, Output, Last, Status);
         Assert (Status = Copy_Ok and then Output (1 .. Last) = "two three", "copy match line");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(?i:a)(?<word>b)");
         Dump     : String (1 .. 2_000);
         Last     : Natural;
         Status   : Copy_Status;
      begin
         Debug_Dump (Compiled.Expression, Dump, Last, Status);
         Assert (Status = Copy_Ok, "debug dump status");
         Assert (Last > 0, "debug dump output");
         Assert (Dump (1 .. Last)'Length > 0, "debug dump slice");

         Explain (Compiled.Expression, Dump, Last, Status);
         Assert (Status = Copy_Ok, "explain status");
         Assert (Last > 0, "explain output");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("abc");
         Dump     : String (1 .. 4);
         Last     : Natural;
         Status   : Copy_Status;
      begin
         Debug_Dump (Compiled.Expression, Dump, Last, Status);
         Assert (Status = Copy_Output_Too_Small, "debug dump small output");
      end;

      declare
         Dump   : String (1 .. 64);
         Last   : Natural;
         Status : Copy_Status;
      begin
         Debug_Dump (Invalid, Dump, Last, Status);
         Assert (Status = Copy_No_Match, "debug dump invalid regexp");
         Explain (Invalid, Dump, Last, Status);
         Assert (Status = Copy_No_Match, "explain invalid regexp");
      end;

      declare
         Result : constant Compile_Result := Compile ("\x");
         Output : String (1 .. 80);
         Last   : Natural;
         Status : Copy_Status;
      begin
         Format_Compile_Diagnostic ("\x", Result, Output, Last, Status);
         Assert (Status = Copy_Ok, "compile caret diagnostic status");
         Assert (Output (1 .. Last)'Length > 0, "compile caret diagnostic output");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(a)");
         Output   : String (1 .. 80);
         Last     : Natural;
         Status   : Copy_Status;
      begin
         Format_Replacement_Diagnostic (Compiled.Expression, "\2", Output, Last, Status);
         Assert (Status = Copy_Ok, "replacement caret diagnostic status");
         Assert (Output (1 .. Last)'Length > 0, "replacement caret diagnostic output");
      end;
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
