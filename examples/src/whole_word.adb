with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Whole_Word is
   package R renames Regexp;

   Compiled : constant R.Compile_Result := R.Compile ("cat");
   Loose    : constant R.Match_Result :=
     R.Find_First (Compiled.Expression, "scatter cat");
   Whole    : constant R.Match_Result :=
     R.Find_First
       (Compiled.Expression,
        "scatter cat",
        (Whole_Word => True, others => <>));
begin
   Put_Line ("without whole-word: " & R.Status_Image (Loose.Status));
   Put_Line
     ("  first =" & Natural'Image (Loose.First) &
      ", last =" & Natural'Image (Loose.Last));

   Put_Line ("with whole-word:    " & R.Status_Image (Whole.Status));
   Put_Line
     ("  first =" & Natural'Image (Whole.First) &
      ", last =" & Natural'Image (Whole.Last));
end Whole_Word;
