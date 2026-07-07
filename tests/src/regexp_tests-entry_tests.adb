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
      Buffer  : Match_Result_Array (1 .. 1);
      Count   : Natural;
      Status  : Find_All_Status;
   begin
      Found := Find_First (Invalid, "abc");
      Assert (Found.Status = Invalid_Regexp, "invalid regexp find first");

      Found := Find_From (Invalid, "abc", 2);
      Assert (Found.Status = Invalid_Regexp, "invalid regexp find from");

      Find_All (Invalid, "abc", Buffer, Count, Status);
      Assert (Status = Find_All_Invalid_Regexp, "invalid regexp find all");
      Assert (Count = 0, "invalid regexp find all count");

      Found := Matches_Entire (Invalid, "abc");
      Assert (Found.Status = Invalid_Regexp, "invalid regexp matches entire");
   end Test_Invalid_Regexp_Entry_Points;

   procedure Test_Find_All (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      declare
         Compiled : constant Compile_Result := Compile ("two");
         Matches  : Match_Result_Array (1 .. 3);
         Count    : Natural;
         Status   : Find_All_Status;
      begin
         Find_All (Compiled.Expression, "one two one two", Matches, Count, Status);
         Assert (Status = Find_All_Ok, "find all status");
         Assert (Count = 2, "find all count");
         Assert (Matches (1).Status = Match_Ok, "find all first status");
         Assert (Matches (1).First = 5, "find all first first");
         Assert (Matches (1).Last = 7, "find all first last");
         Assert (Matches (2).Status = Match_Ok, "find all second status");
         Assert (Matches (2).First = 13, "find all second first");
         Assert (Matches (2).Last = 15, "find all second last");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("^");
         Matches  : Match_Result_Array (1 .. 2);
         Count    : Natural;
         Status   : Find_All_Status;
      begin
         Find_All (Compiled.Expression, "abc", Matches, Count, Status);
         Assert (Status = Find_All_Ok, "find all zero-length status");
         Assert (Count = 1, "find all zero-length count");
         Assert (Matches (1).First = 1, "find all zero-length first");
         Assert (Matches (1).Last = 0, "find all zero-length last");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("a*");
         Matches  : Match_Result_Array (1 .. 5);
         Count    : Natural;
         Status   : Find_All_Status;
      begin
         Find_All (Compiled.Expression, "bbb", Matches, Count, Status);
         Assert (Status = Find_All_Ok, "find all optional status");
         Assert (Count = 4, "find all optional count");
         Assert (Matches (1).First = 1 and then Matches (1).Last = 0, "find all optional first");
         Assert (Matches (4).First = 4 and then Matches (4).Last = 3, "find all optional end");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("two");
         Base     : constant String := "xxone two one twoxx";
         Matches  : Match_Result_Array (1 .. 3);
         Count    : Natural;
         Status   : Find_All_Status;
      begin
         Find_All (Compiled.Expression, Base (3 .. 17), Matches, Count, Status);
         Assert (Status = Find_All_Ok, "find all slice status");
         Assert (Count = 2, "find all slice count");
         Assert (Matches (1).First = 5, "find all slice first match first");
         Assert (Matches (2).First = 13, "find all slice second match first");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("two");
         Matches  : Match_Result_Array (1 .. 1);
         Count    : Natural;
         Status   : Find_All_Status;
      begin
         Find_All (Compiled.Expression, "one two one two", Matches, Count, Status);
         Assert (Status = Too_Many_Matches, "find all small buffer status");
         Assert (Count = 1, "find all small buffer count");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("z");
         Matches  : Match_Result_Array (1 .. 2);
         Count    : Natural;
         Status   : Find_All_Status;
      begin
         Find_All (Compiled.Expression, "aaaaaaaa", Matches, Count, Status, (Max_Steps => 4, others => <>));
         Assert (Status = Find_All_Limit_Exceeded, "find all low step status");
         Assert (Count = 0, "find all low step count");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("z");
         Matches  : Match_Result_Array (1 .. 2);
         Count    : Natural;
         Status   : Find_All_Status;
      begin
         Find_All (Compiled.Expression, "abc", Matches, Count, Status);
         Assert (Status = No_Matches, "find all no matches status");
         Assert (Count = 0, "find all no matches count");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("two");
         Matches  : Match_Result_Array (1 .. 2);
         Count    : Natural;
         Status   : Find_All_Status;
      begin
         Find_All_From (Compiled.Expression, "one two one two", 8, Matches, Count, Status);
         Assert (Status = Find_All_Ok, "find all from status");
         Assert (Count = 1, "find all from count");
         Assert (Matches (1).First = 13, "find all from first");
         Assert (Matches (1).Last = 15, "find all from last");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("aba");
         Matches  : Match_Result_Array (1 .. 3);
         Count    : Natural;
         Status   : Find_All_Status;
      begin
         Find_All_Overlapping (Compiled.Expression, "ababa", Matches, Count, Status);
         Assert (Status = Find_All_Ok, "find all overlapping status");
         Assert (Count = 2, "find all overlapping count");
         Assert (Matches (1).First = 1 and then Matches (1).Last = 3, "overlap first range");
         Assert (Matches (2).First = 3 and then Matches (2).Last = 5, "overlap second range");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("aba");
         Matches  : Match_Result_Array (1 .. 1);
         Count    : Natural;
         Status   : Find_All_Status;
      begin
         Find_All_Overlapping (Compiled.Expression, "ababa", Matches, Count, Status);
         Assert (Status = Too_Many_Matches, "find all overlapping small buffer status");
         Assert (Count = 1, "find all overlapping small buffer count");
      end;

      declare
         Compiled      : constant Compile_Result := Compile ("(?<word>t\w+)");
         Matches       : Match_Result_Array (1 .. 2);
         Captures      : Capture_Result_Array (1 .. 2, 1 .. 1);
         Count         : Natural;
         Capture_Total : Natural;
         Status        : Find_All_Status;
      begin
         Find_All_With_Captures
           (Compiled.Expression, "one two three", Matches, Captures, Count, Capture_Total, Status);
         Assert (Status = Find_All_Ok, "find all captures status");
         Assert (Count = 2 and then Capture_Total = 1, "find all captures count");
         Assert (Matches (1).First = 5 and then Matches (2).First = 9, "find all captures matches");
         Assert (Captures (1, 1) = (First => 5, Last => 7), "find all captures first capture");
         Assert (Captures (2, 1) = (First => 9, Last => 13), "find all captures second capture");
      end;

      declare
         Compiled      : constant Compile_Result := Compile ("(aba)");
         Matches       : Match_Result_Array (1 .. 2);
         Captures      : Capture_Result_Array (1 .. 2, 1 .. 1);
         Count         : Natural;
         Capture_Total : Natural;
         Status        : Find_All_Status;
      begin
         Find_All_Overlapping_With_Captures
           (Compiled.Expression, "ababa", Matches, Captures, Count, Capture_Total, Status);
         Assert (Status = Find_All_Ok and then Count = 2 and then Capture_Total = 1,
                 "overlapping captures status");
         Assert (Matches (1).First = 1 and then Matches (2).First = 3, "overlapping captures matches");
         Assert (Captures (2, 1) = (First => 3, Last => 5), "overlapping captures range");
      end;

      declare
         Compiled      : constant Compile_Result := Compile ("(two)");
         Matches       : Match_Result_Array (1 .. 1);
         Captures      : Capture_Result_Array (1 .. 1, 1 .. 1);
         Count         : Natural;
         Capture_Total : Natural;
         Status        : Find_All_Status;
      begin
         Find_All_With_Captures_From
           (Compiled.Expression, "one two two", 8, Matches, Captures, Count, Capture_Total, Status);
         Assert (Status = Find_All_Ok and then Count = 1 and then Capture_Total = 1,
                 "find all captures from status");
         Assert (Matches (1).First = 9 and then Captures (1, 1) = (First => 9, Last => 11),
                 "find all captures from range");
      end;
   end Test_Find_All;

   procedure Test_Additional_Entry_Points (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      declare
         Compiled : constant Compile_Result := Compile ("a.c");
         Found    : Match_Result;
      begin
         Found := Find_First (Compiled.Expression, "a" & Character'Val (10) & "c");
         Assert (Found.Status = No_Match, "dot excludes newline default");

         Found := Find_First
           (Compiled.Expression,
            "a" & Character'Val (10) & "c",
            (Dot_Matches_Newline => True, others => <>));
         Assert (Found.Status = Match_Ok, "dot matches newline option");
         Assert (Found.First = 1 and then Found.Last = 3, "dot newline range");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("^two$");
         Text     : constant String := "one" & Character'Val (10) & "two";
         Found    : Match_Result;
      begin
         Found := Find_First (Compiled.Expression, Text);
         Assert (Found.Status = No_Match, "multiline anchors disabled");
         Found := Find_First (Compiled.Expression, Text, (Multiline_Anchors => True, others => <>));
         Assert (Found.Status = Match_Ok, "multiline anchors enabled");
         Assert (Found.First = 5 and then Found.Last = 7, "multiline anchor range");
      end;

      declare
         Compiled : constant Compile_Result := Compile_Literal ("a.c|d");
         Found    : Match_Result;
      begin
         Assert (Compiled.Status = Compile_Ok, "compile literal status");
         Found := Find_First (Compiled.Expression, "xxa.c|dxx");
         Assert (Found.Status = Match_Ok, "compile literal match");
         Assert (Found.First = 3 and then Found.Last = 7, "compile literal range");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("two");
         Count    : Natural;
         Status   : Find_All_Status;
         Summary  : Find_All_Summary_Result;
      begin
         Assert (Has_Match (Compiled.Expression, "one two"), "has match");
         Count_Matches (Compiled.Expression, "one two one two", Count, Status);
         Assert (Status = Find_All_Ok, "count matches status");
         Assert (Count = 2, "count matches count");
         Summary := Find_All_Summary (Compiled.Expression, "one two one two");
         Assert (Summary.Status = Find_All_Ok and then Summary.Count = 2, "find all summary status");
         Assert (Summary.First_Match.First = 5 and then Summary.Last_Match.First = 13, "find all summary range");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("two");
         Text     : constant String := "one" & Character'Val (10) & "two" & Character'Val (10) & "two";
         Summary  : constant Find_All_Line_Summary_Result := Find_All_Line_Summary (Compiled.Expression, Text);
      begin
         Assert (Summary.Status = Find_All_Ok and then Summary.Count = 2, "find all line summary status");
         Assert (Summary.First_Position = (Line => 2, Column => 1), "find all line summary first position");
         Assert (Summary.Last_Position = (Line => 3, Column => 1), "find all line summary last position");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("two");
         Text     : constant String := "one two" & Character'Val (10) & "two";
         Lines    : Text_Range_Array (1 .. 2);
         Count    : Natural;
         Status   : Find_All_Status;
      begin
         Find_All_Lines (Compiled.Expression, Text, Lines, Count, Status);
         Assert (Status = Find_All_Ok and then Count = 2, "find all lines status");
         Assert (Lines (1) = (First => 1, Last => 7), "find all lines first");
         Assert (Lines (2) = (First => 9, Last => 11), "find all lines second");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("two");
         Text     : constant String := "one two" & Character'Val (10) & "two";
         Lines    : Text_Range_Array (1 .. 3);
         Count    : Natural;
         F_Status : Find_All_Status;
         S_Status : Split_Status;
      begin
         Replace_All_Lines (Compiled.Expression, Text, Lines, Count, F_Status);
         Assert (F_Status = Find_All_Ok and then Count = 2, "replace all lines status");
         Split_Lines (Compiled.Expression, Text, Lines, Count, S_Status);
         Assert (S_Status = Split_Ok and then Count = 3, "split lines status");
      end;

      declare
         Word     : constant Compile_Result := Compile ("[A-Z_]\w*");
         Number   : constant Compile_Result := Compile ("\d+");
         Set      : constant Regexp_Array (1 .. 2) := [Word.Expression, Number.Expression];
         Text     : constant String := "id 42";
         Best     : constant Pattern_Match_Result := Find_First_Of (Set, Text);
         Planned  : constant Match_Result := Find_From_Planned (Number.Expression, Text);
         Tokens   : Pattern_Match_Array (1 .. 2);
         Captured : Pattern_Match_Captures_Array (1 .. 2);
         Best_Cap : Pattern_Match_Captures_Result;
         Found    : Match_Result;
         Caps     : Text_Range_Array (1 .. 1);
         Count    : Natural;
         Status   : Find_All_Status;
         Cap_Count : Natural;
      begin
         Assert (Best.Found.Status = Match_Ok and then Best.Pattern_Index = 1, "find first of");
         Assert (Planned.Status = Match_Ok and then Planned.First = 4, "planned find");
         Tokenize (Set, Text, Tokens, Count, Status);
         Assert (Status = Find_All_Ok and then Count = 2, "tokenize status");
         Assert (Tokens (1).Kind = 1 and then Tokens (2).Kind = 2, "tokenize kinds");
         Tokenize_With_Kinds (Set, [10, 20], Text, Tokens, Count, Status);
         Assert (Status = Find_All_Ok and then Tokens (2).Kind = 20, "tokenize explicit kinds");
         Best_Cap := Find_First_Of_With_Captures ([Compile ("(id)").Expression, Number.Expression], Text);
         Assert (Best_Cap.Match.Found.Status = Match_Ok and then Best_Cap.Match.Capture_Count = 1,
                 "find first of captures");
         Tokenize_With_Captures ([Compile ("([A-Z_]\w*)").Expression, Number.Expression], [10, 20],
                                 Text, Captured, Count, Status);
         Assert (Status = Find_All_Ok and then Captured (1).Match.Capture_Count = 1,
                 "tokenize captures");
         Find_From_Planned_With_Captures (Compile ("(\d+)").Expression, Text, 1, Found, Caps, Cap_Count);
         Assert (Found.Status = Match_Ok and then Cap_Count = 1 and then Caps (1) = (First => 4, Last => 5),
                 "planned captures");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(?<word>\w+)");
         Cursor   : Match_Cursor;
         Result   : Captured_Match_Result;
         Line     : Line_Captured_Match_Result;
      begin
         Start (Cursor, Compiled.Expression);
         Next_Captured (Cursor, "one two", Result);
         Assert (Result.Found.Status = Match_Ok and then Result.Capture_Count = 1, "next captured");
         Assert (Result.Captures (1) = (First => 1, Last => 3), "next captured range");
         Start (Cursor, Compiled.Expression);
         Next_Line_Captured (Cursor, "one" & Character'Val (10) & "two", Line);
         Assert (Line.Match.Found.Status = Match_Ok and then Line.Position.Line = 1, "line captured");
         Assert (Line.Line = (First => 1, Last => 3), "line captured range");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("two");
         Edits    : Replacement_Edit_Array (1 .. 3);
         Refs     : Replacement_Reference_Array (1 .. 2);
         Maps     : Replacement_Output_Map_Array (1 .. 3);
         Plan     : Replacement_Plan;
         Count    : Natural;
         Status   : Replace_Status;
         Complete : Boolean;
      begin
         Plan_Replacement (Compiled.Expression, "one two", "2", Edits, Count, Status, Complete);
         Assert (Status = Replace_Ok and then Complete and then Count = 2, "replacement plan status");
         Assert (not Edits (1).Is_Replacement and then Edits (2).Is_Replacement, "replacement plan edits");
         Assert (Edits (2).Source = (First => 5, Last => 7), "replacement plan range");
         Assert (Edits (2).Required_Length = 1, "replacement plan length");
         Plan_Replacement_Detail (Compile ("(?<word>two)").Expression, "one two", "\k<word>",
                                  Edits, Refs, Maps, Plan);
         Assert (Plan.Status = Replace_Ok and then Plan.Reference_Count = 1, "replacement detail status");
         Assert (Maps (2).Output = (First => 5, Last => 7), "replacement output map");
      end;

      declare
         Word   : constant Compile_Result := Compile ("[A-Z_]\w*");
         Number : constant Compile_Result := Compile ("\d+");
         Set    : constant Regexp_Array (1 .. 2) := [Word.Expression, Number.Expression];
         Cursor : Token_Stream_Cursor;
         Tokens : Pattern_Match_Array (1 .. 2);
         C_Tokens : Pattern_Match_Captures_Array (1 .. 2);
         Count  : Natural;
         Status : Find_All_Status;
         Detail : Token_Stream_Status;
      begin
         Start_Token_Stream (Cursor);
         Feed_Tokens (Cursor, Set, [10, 20], "id 42", True, Tokens, Count, Status);
         Assert (Status = Find_All_Ok and then Count = 2, "feed tokens status");
         Assert (Tokens (1).Kind = 10 and then Tokens (2).Found.First = 4, "feed tokens offsets");
         Start_Token_Stream (Cursor);
         Feed_Tokens_Detail (Cursor, Set, [10, 20], "", False, Tokens, Count, Detail);
         Assert (Detail = Token_Stream_Need_More_Data, "feed tokens need more");
         Start_Token_Stream (Cursor);
         Feed_Tokens_With_Captures
           (Cursor, [Compile ("([A-Z_]\w*)").Expression, Number.Expression], [10, 20],
            "id 42", True, C_Tokens, Count, Detail);
         Assert (Detail = Token_Stream_Ok and then C_Tokens (1).Match.Capture_Count = 1,
                 "feed tokens captures");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("two");
         Cursor   : Match_Cursor;
         Found    : Match_Result;
      begin
         Start (Cursor, Compiled.Expression);
         Next (Cursor, "one two one two", Found);
         Assert (Found.Status = Match_Ok, "cursor first status");
         Assert (Found.First = 5, "cursor first");
         Next (Cursor, "one two one two", Found);
         Assert (Found.Status = Match_Ok, "cursor second status");
         Assert (Found.First = 13, "cursor second");
         Next (Cursor, "one two one two", Found);
         Assert (Found.Status = No_Match, "cursor done");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("two");
         Found    : constant Match_Result := Find_First (Compiled.Expression, "one two three");
      begin
         Assert (Match_Length (Found) = 3, "match length");
         Assert (Contains_Offset (Found, 6), "contains offset");
         Assert (Before_Match ("one two three", Found) = (First => 1, Last => 4), "before match range");
         Assert (After_Match ("one two three", Found) = (First => 8, Last => 13), "after match range");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(?<word>two)");
         Cursor   : Match_Cursor;
         Found    : Match_Result;
         Captures : Text_Range_Array (1 .. 1);
         Count    : Natural;
      begin
         Start (Cursor, Compiled.Expression);
         Next_With_Captures (Cursor, "one two two", Found, Captures, Count);
         Assert (Found.Status = Match_Ok, "cursor captures first status");
         Assert (Count = 1 and then Captures (1) = (First => 5, Last => 7), "cursor captures first");
         Next_With_Captures (Cursor, "one two two", Found, Captures, Count);
         Assert (Found.Status = Match_Ok, "cursor captures second status");
         Assert (Count = 1 and then Captures (1) = (First => 9, Last => 11), "cursor captures second");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(?<key>\w+)=(?<value>\d+)");
         Found    : Match_Result;
         Captures : Text_Range_Array (1 .. 2);
         Count    : Natural;
         Output   : String (1 .. 8);
         Last     : Natural;
         Status   : Copy_Status;
      begin
         Find_First_With_Captures (Compiled.Expression, "id=42", Found, Captures, Count);
         Copy_Capture ("id=42", Captures, 1, Output, Last, Status);
         Assert (Status = Copy_Ok and then Output (1 .. Last) = "id", "copy numbered capture");
         Copy_Named_Capture (Compiled.Expression, "id=42", Captures, "value", Output, Last, Status);
         Assert (Status = Copy_Ok and then Output (1 .. Last) = "42", "copy named capture");
         Assert (Named_Capture_Range (Compiled.Expression, Captures, "value") = (First => 4, Last => 5),
                 "named capture range");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("two");
         Output   : String (1 .. 32);
         Last     : Natural;
         Status   : Replace_Status;
         Count    : Natural;
         Fits     : Boolean;
      begin
         Replace_First (Compiled.Expression, "one two two", "2", Output, Last, Status);
         Assert (Status = Replace_Ok, "replace first status");
         Assert (Output (1 .. Last) = "one 2 two", "replace first output");

         Replace_First_Count (Compiled.Expression, "one two two", "2", Output, Last, Status, Count);
         Assert (Status = Replace_Ok and then Count = 1, "replace first count status");
         Assert (Output (1 .. Last) = "one 2 two", "replace first count output");

         Replace_All (Compiled.Expression, "one two two", "2", Output, Last, Status);
         Assert (Status = Replace_Ok, "replace all status");
         Assert (Output (1 .. Last) = "one 2 2", "replace all output");

         Replace_All_Count (Compiled.Expression, "one two two", "2", Output, Last, Status, Count);
         Assert (Status = Replace_Ok and then Count = 2, "replace all count status");
         Assert (Output (1 .. Last) = "one 2 2", "replace all count output");

         Replace_All_Size (Compiled.Expression, "one two two", "2", Last, Status, Count);
         Assert (Status = Replace_Ok and then Count = 2 and then Last = 7, "replace all size");
         Replace_First_Size (Compiled.Expression, "one two two", "2", Last, Status, Count);
         Assert (Status = Replace_Ok and then Count = 1 and then Last = 9, "replace first size");
         Required_All_Output_Length (Compiled.Expression, "one two two", "2", Last, Status);
         Assert (Status = Replace_Ok and then Last = 7, "required all output length");
         Replacement_Fits (Compiled.Expression, "one two two", "2", 8, Fits, Status);
         Assert (Status = Replace_Ok and then Fits, "replacement fits");

         Replace_All (Compiled.Expression, "one two", "[\0]", Output, Last, Status);
         Assert (Status = Replace_Ok, "replace all expansion status");
         Assert (Output (1 .. Last) = "one [two]", "replace all expansion output");
         Assert (Escape_Replacement ("\1") = "\\1", "escape replacement");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(\w+)=(\d+)");
         Output   : String (1 .. 32);
         Last     : Natural;
         Status   : Replace_Status;
      begin
         Replace_First (Compiled.Expression, "id=42 next", "\2:\1", Output, Last, Status);
         Assert (Status = Replace_Ok, "replace first numbered backref status");
         Assert (Output (1 .. Last) = "42:id next", "replace first numbered backref output");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(?<key>\w+)=(?<value>\d+)");
         Output   : String (1 .. 32);
         Last     : Natural;
         Status   : Replace_Status;
         Validate : Replacement_Validation_Status;
         Offset   : Natural;
         Detail   : Replacement_Validation_Result;
         Refs     : Replacement_Reference_Array (1 .. 2);
         Summary  : Replacement_Features;
         Ref_Count : Natural;
         Complete : Boolean;
      begin
         Validate_Replacement (Compiled.Expression, "\k<value>:\k<key>", Validate, Offset);
         Assert (Validate = Replacement_Ok and then Offset = 0, "validate named replacement ok");
         Detail := Validate_Replacement_Detail (Compiled.Expression, "\k<value>:\k<key>");
         Assert (Detail.Status = Replacement_Ok and then Detail.Capture = 1, "validate detail last capture");
         Assert (Detail.Name = (First => 14, Last => 16), "validate detail last name range");
         Replacement_References
           (Compiled.Expression, "\0-\k<value>-\k<key>", Refs, Ref_Count, Detail, Complete);
         Assert (Detail.Status = Replacement_Ok and then Ref_Count = 2, "replacement references count");
         Assert (not Complete, "replacement references incomplete");
         Assert (Refs (1).Kind = Replacement_Whole_Match and then Refs (1).Offset = 1,
                 "replacement whole match ref");
         Assert (Refs (2).Kind = Replacement_Named_Capture and then Refs (2).Capture = 2,
                 "replacement named ref");
         Replacement_Summary (Compiled.Expression, "\U\0-\k<value>\E", Refs, Summary);
         Assert (Summary.Valid and then Summary.Uses_Whole_Match, "replacement summary whole match");
         Assert (Summary.Uses_Named_Captures and then Summary.Uses_Case_Conversion,
                 "replacement summary features");
         Replace_All (Compiled.Expression, "id=42 x=7", "\k<value>:\k<key>", Output, Last, Status);
         Assert (Status = Replace_Ok, "replace all named backref status");
         Assert (Output (1 .. Last) = "42:id 7:x", "replace all named backref output");

         Validate_Replacement (Compiled.Expression, "\3", Validate, Offset);
         Assert (Validate = Replacement_Unknown_Capture and then Offset = 1,
                 "validate missing numbered replacement");
         Detail := Validate_Replacement_Detail (Compiled.Expression, "\3");
         Assert (Detail.Status = Replacement_Unknown_Capture and then Detail.Capture = 3,
                 "validate missing numbered detail");
         Validate_Replacement (Compiled.Expression, "\k<missing>", Validate, Offset);
         Assert (Validate = Replacement_Unknown_Capture and then Offset = 1,
                 "validate missing named replacement");
         Detail := Validate_Replacement_Detail (Compiled.Expression, "\k<missing>");
         Assert (Detail.Status = Replacement_Unknown_Capture and then Detail.Name = (First => 4, Last => 10),
                 "validate missing named detail");
         Validate_Replacement (Compiled.Expression, "\k<value", Validate, Offset);
         Assert (Validate = Replacement_Unterminated_Name and then Offset = 1,
                 "validate unterminated named replacement");
         Validate_Replacement (Compiled.Expression, "\q", Validate, Offset);
         Assert (Validate = Replacement_Invalid_Escape and then Offset = 1,
                 "validate invalid replacement escape");
         Validate_Replacement (Compiled.Expression, "\U\k<value>", Validate, Offset);
         Assert (Validate = Replacement_Unterminated_Case_Conversion,
                 "validate unterminated replacement case conversion");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(\w+)");
         Output   : String (1 .. 32);
         Last     : Natural;
         Status   : Replace_Status;
      begin
         Replace_First (Compiled.Expression, "cat", "\U\1\E-\lMIX-\uword", Output, Last, Status);
         Assert (Status = Replace_Ok, "replace case escapes status");
         Assert (Output (1 .. Last) = "CAT-mIX-Word", "replace case escapes output");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(?<word>\w+)");
         Output   : String (1 .. 32);
         Last     : Natural;
         Status   : Replace_Status;
      begin
         Replace_First (Compiled.Expression, "Cat", "\L\k<word>\E", Output, Last, Status);
         Assert (Status = Replace_Ok, "replace named lower status");
         Assert (Output (1 .. Last) = "cat", "replace named lower output");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("cat");
         Output   : String (1 .. 32);
         Last     : Natural;
         Status   : Replace_Status;
      begin
         Replace_All_Preserving_Case (Compiled.Expression, "cat CAT Cat", "dog", Output, Last, Status);
         Assert (Status = Replace_Ok, "replace preserving case status");
         Assert (Output (1 .. Last) = "dog DOG Dog", "replace preserving case output");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(cat)");
         Output   : String (1 .. 32);
         Last     : Natural;
         Status   : Replace_Status;
      begin
         Replace_All_Preserving_Case (Compiled.Expression, "cat CAT", "\1 dog", Output, Last, Status);
         Assert (Status = Replace_Ok, "replace preserving case backref status");
         Assert (Output (1 .. Last) = "cat dog CAT DOG", "replace preserving case backref output");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("z");
         Output   : String (1 .. 8);
         Last     : Natural;
         Status   : Replace_Status;
      begin
         Replace_All (Compiled.Expression, "abc", "x", Output, Last, Status);
         Assert (Status = Replace_No_Match, "replace no match status");
         Assert (Output (1 .. Last) = "abc", "replace no match output");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("two");
         Output   : String (1 .. 4);
         Last     : Natural;
         Status   : Replace_Status;
      begin
         Replace_All (Compiled.Expression, "one two", "22222", Output, Last, Status);
         Assert (Status = Replace_Output_Too_Small, "replace output too small");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(\w+)=(\d+)");
         Output   : String (1 .. 4);
         Last     : Natural;
         Status   : Replace_Status;
      begin
         Replace_First (Compiled.Expression, "id=42", "\1:\2", Output, Last, Status);
         Assert (Status = Replace_Output_Too_Small, "replace backref output too small");
      end;

      declare
         Compiled : constant Compile_Result := Compile (",");
         Parts    : Text_Range_Array (1 .. 4);
         Count    : Natural;
         Status   : Split_Status;
      begin
         Split (Compiled.Expression, "a,b,c", Parts, Count, Status);
         Assert (Status = Split_Ok, "split status");
         Assert (Count = 3, "split count");
         Assert (Parts (1) = (First => 1, Last => 1), "split first");
         Assert (Parts (2) = (First => 3, Last => 3), "split second");
         Assert (Parts (3) = (First => 5, Last => 5), "split third");
      end;

      declare
         Compiled : constant Compile_Result := Compile (",");
         Parts    : Text_Range_Array (1 .. 1);
         Count    : Natural;
         Status   : Split_Status;
      begin
         Split (Compiled.Expression, "a,b", Parts, Count, Status);
         Assert (Status = Too_Many_Parts, "split too many parts");
         Assert (Count = 1, "split too many count");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("\w+");
         Found    : constant Match_Result := Find_First (Compiled.Expression, "xx abc yy");
         Output   : String (1 .. 8);
         Last     : Natural;
         Status   : Copy_Status;
      begin
         Copy_Match ("xx abc yy", Found, Output, Last, Status);
         Assert (Status = Copy_Ok, "copy match status");
         Assert (Output (1 .. Last) = "xx", "copy match output");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(ab)(cd)");
         Found    : Match_Result;
         Captures : Text_Range_Array (1 .. 2);
         Count    : Natural;
      begin
         Find_First_With_Captures (Compiled.Expression, "xxabcdyy", Found, Captures, Count);
         Assert (Found.Status = Match_Ok, "captures match status");
         Assert (Found.First = 3 and then Found.Last = 6, "captures match range");
         Assert (Count = 2, "captures count");
         Assert (Captures (1) = (First => 3, Last => 4), "first capture range");
         Assert (Captures (2) = (First => 5, Last => 6), "second capture range");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(?<word>\w+)-(?<num>\d+)");
         Found    : Match_Result;
         Captures : Text_Range_Array (1 .. 2);
         Count    : Natural;
         Word     : constant Natural := Capture_Index (Compiled.Expression, "word");
         Num      : constant Natural := Capture_Index (Compiled.Expression, "num");
      begin
         Find_First_With_Captures (Compiled.Expression, "id-42", Found, Captures, Count);
         Assert (Found.Status = Match_Ok, "named captures match status");
         Assert (Word = 1 and then Num = 2, "named capture indexes");
         Assert (Captures (Word) = (First => 1, Last => 2), "named word capture");
         Assert (Captures (Num) = (First => 4, Last => 5), "named number capture");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(a(b))");
         Found    : Match_Result;
         Captures : Text_Range_Array (1 .. 2);
         Count    : Natural;
      begin
         Find_First_With_Captures (Compiled.Expression, "xxabyy", Found, Captures, Count);
         Assert (Found.Status = Match_Ok, "nested captures status");
         Assert (Count = 2, "nested captures count");
         Assert (Captures (1) = (First => 3, Last => 4), "outer capture range");
         Assert (Captures (2) = (First => 4, Last => 4), "inner capture range");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(a)?b");
         Found    : Match_Result;
         Captures : Text_Range_Array (1 .. 1);
         Count    : Natural;
      begin
         Find_First_With_Captures (Compiled.Expression, "b", Found, Captures, Count);
         Assert (Found.Status = Match_Ok, "optional capture status");
         Assert (Count = 1, "optional capture count");
         Assert (Captures (1) = (First => 0, Last => 0), "unmatched optional capture");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(b)");
         Base     : constant String := "xxabc";
         Found    : Match_Result;
         Captures : Text_Range_Array (1 .. 1);
         Count    : Natural;
      begin
         Find_From_With_Captures (Compiled.Expression, Base (3 .. 5), 1, Found, Captures, Count);
         Assert (Found.Status = Match_Ok, "slice capture status");
         Assert (Found.First = 2 and then Found.Last = 2, "slice capture match range");
         Assert (Captures (1) = (First => 2, Last => 2), "slice capture range");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("abc");
         Cursor   : Stream_Cursor;
         Found    : Match_Result;
         Status   : Stream_Status;
      begin
         Start_Stream (Cursor, Compiled.Expression);
         Feed (Cursor, "xxa", False, Found, Status);
         Assert (Status = Stream_No_Match, "stream holds partial match");
         Feed (Cursor, "bc yy", False, Found, Status);
         Assert (Status = Stream_Match, "stream cross chunk status");
         Assert (Found.First = 3 and then Found.Last = 5, "stream cross chunk range");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("(abc)");
         Cursor   : Stream_Cursor;
         Found    : Match_Result;
         Captures : Text_Range_Array (1 .. 1);
         Count    : Natural;
         Status   : Stream_Status;
      begin
         Start_Stream (Cursor, Compiled.Expression);
         Feed_With_Captures (Cursor, "xxa", False, Found, Captures, Count, Status);
         Assert (Status = Stream_No_Match, "stream captures holds partial match");
         Feed_With_Captures (Cursor, "bc yy", False, Found, Captures, Count, Status);
         Assert (Status = Stream_Match and then Count = 1, "stream captures status");
         Assert (Found.First = 3 and then Found.Last = 5, "stream captures match range");
         Assert (Captures (1) = (First => 3, Last => 5), "stream captures capture range");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("a+");
         Cursor   : Stream_Cursor;
         Found    : Match_Result;
         Status   : Stream_Status;
      begin
         Start_Stream (Cursor, Compiled.Expression);
         Feed (Cursor, "aaa", False, Found, Status);
         Assert (Status = Stream_No_Match, "stream holds greedy edge match");
         Feed (Cursor, "", True, Found, Status);
         Assert (Status = Stream_Match, "stream final greedy status");
         Assert (Found.First = 1 and then Found.Last = 3, "stream final greedy range");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("a+?");
         Cursor   : Stream_Cursor;
         Found    : Match_Result;
         Status   : Stream_Status;
      begin
         Start_Stream (Cursor, Compiled.Expression);
         Feed (Cursor, "aaa", False, Found, Status);
         Assert (Status = Stream_Match, "stream lazy edge status");
         Assert (Found.First = 1 and then Found.Last = 1, "stream lazy edge range");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("two");
         Cursor   : Stream_Cursor;
         Found    : Match_Result;
         Status   : Stream_Status;
      begin
         Start_Stream (Cursor, Compiled.Expression);
         Feed (Cursor, "two two", True, Found, Status);
         Assert (Status = Stream_Match, "stream drain first status");
         Assert (Found.First = 1 and then Found.Last = 3, "stream drain first range");
         Feed (Cursor, "", True, Found, Status);
         Assert (Status = Stream_Match, "stream drain second status");
         Assert (Found.First = 5 and then Found.Last = 7, "stream drain second range");
      end;

      declare
         Invalid : Regexp.Regexp;
         Cursor  : Stream_Cursor;
         Found   : Match_Result;
         Status  : Stream_Status;
      begin
         Start_Stream (Cursor, Invalid);
         Feed (Cursor, "abc", True, Found, Status);
         Assert (Status = Stream_Invalid_Regexp, "stream invalid status");
         Assert (Found.Status = Invalid_Regexp, "stream invalid match status");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("z");
         Cursor   : Stream_Cursor;
         Found    : Match_Result;
         Status   : Stream_Status;
         Big      : constant String (1 .. Default_Stream_Buffer_Length + 1) := [others => 'a'];
      begin
         Start_Stream (Cursor, Compiled.Expression);
         Feed (Cursor, Big, False, Found, Status);
         Assert (Status = Stream_Buffer_Full, "stream buffer full status");
      end;

      declare
         Compiled : constant Compile_Result := Compile ("z");
         Cursor   : Stream_Cursor;
         Found    : Match_Result;
         Status   : Stream_Status;
      begin
         Start_Stream (Cursor, Compiled.Expression, Max_Buffer_Length => 3);
         Feed (Cursor, "aaaa", False, Found, Status);
         Assert (Status = Stream_Buffer_Full, "stream configured buffer full status");
      end;
   end Test_Additional_Entry_Points;

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
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Find_All'Access), "Find all entry point");
      Register_Routine
        (T,
         AUnit.Test_Cases.Test_Routine'(Test_Additional_Entry_Points'Access),
         "Additional entry points");
   end Register_Tests;
end Regexp_Tests.Entry_Tests;
