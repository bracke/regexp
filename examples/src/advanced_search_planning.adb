with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Advanced_Search_Planning is
   package R renames Regexp;
   use type R.Compile_Status;
   use type R.Find_All_Status;
   use type R.Match_Status;
   use type R.Replacement_Validation_Status;
   use type R.Search_Strategy;
   use type R.Stream_Status;

   Text           : constant String := "id=42" & Character'Val (10) & "id=7";
   Compiled       : constant R.Compile_Result := R.Compile ("(?<key>id)=(?<value>\d+)");
   Matches        : R.Match_Result_Array (1 .. 4);
   Captures       : R.Capture_Result_Array (1 .. 4, 1 .. 2);
   Refs           : R.Replacement_Reference_Array (1 .. 4);
   Stream_Cursor  : R.Stream_Cursor;
   Stream_Found   : R.Match_Result;
   Stream_Captures : R.Text_Range_Array (1 .. 2);
   Summary        : R.Expression_Summary;
   Replacement    : R.Replacement_Features;
   Count          : Natural;
   Capture_Count  : Natural;
   Stream_Count   : Natural;
   Find_Status    : R.Find_All_Status;
   Stream_Status  : R.Stream_Status;
begin
   if Compiled.Status /= R.Compile_Ok then
      Put_Line ("compile failed: " & R.Status_Image (Compiled.Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Summary := R.Summary (Compiled.Expression);
   R.Find_All_With_Captures (Compiled.Expression, Text, Matches, Captures, Count, Capture_Count, Find_Status);
   R.Replacement_Summary (Compiled.Expression, "\k<value>:\k<key>", Refs, Replacement);

   R.Start_Stream (Stream_Cursor, Compiled.Expression);
   R.Feed_With_Captures (Stream_Cursor, "id=", False, Stream_Found, Stream_Captures, Stream_Count, Stream_Status);
   R.Feed_With_Captures (Stream_Cursor, "42", True, Stream_Found, Stream_Captures, Stream_Count, Stream_Status);

   Put_Line ("strategy: " & (if Summary.Strategy = R.Search_General then "general" else "specialized"));
   Put_Line ("matches: " & Natural'Image (Count));
   Put_Line ("captures: " & Natural'Image (Capture_Count));
   Put_Line ("replacement refs: " & Natural'Image (Replacement.Reference_Count));
   Put_Line ("stream status: " & R.Status_Image (Stream_Status));

   if Find_Status /= R.Find_All_Ok
     or else Count /= 2
     or else Capture_Count /= 2
     or else not Replacement.Valid
     or else Replacement.Reference_Count /= 2
     or else Stream_Status /= R.Stream_Match
     or else Stream_Found.Status /= R.Match_Ok
     or else Stream_Count /= 2
   then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Advanced_Search_Planning;
