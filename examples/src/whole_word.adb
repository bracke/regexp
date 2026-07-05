with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Whole_Word is
   package R renames Regexp;
   use type R.Compile_Status;
   use type R.Match_Status;

   Compiled : constant R.Compile_Result := R.Compile ("cat");
   Loose    : constant R.Match_Result :=
     R.Find_First (Compiled.Expression, "scatter cat");
   Whole    : constant R.Match_Result :=
     R.Find_First
       (Compiled.Expression,
        "scatter cat",
        (Whole_Word => True, others => <>));
begin
   if Compiled.Status /= R.Compile_Ok then
      Put_Line ("compile failed: " & R.Status_Image (Compiled.Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Put_Line ("without whole-word: " & R.Status_Image (Loose.Status));
   Put_Line
     ("  first =" & Natural'Image (Loose.First) &
      ", last =" & Natural'Image (Loose.Last));

   Put_Line ("with whole-word:    " & R.Status_Image (Whole.Status));
   Put_Line
     ("  first =" & Natural'Image (Whole.First) &
      ", last =" & Natural'Image (Whole.Last));

   if Loose.Status /= R.Match_Ok or else Whole.Status /= R.Match_Ok then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Whole_Word;
