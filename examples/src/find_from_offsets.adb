with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Find_From_Offsets is
   package R renames Regexp;
   use type R.Match_Status;

   Text     : constant String := "one two one two";
   Compiled : constant R.Compile_Result := R.Compile ("two");
   From     : Positive := 1;
   Found    : R.Match_Result;
begin
   Put_Line ("text: " & Text);

   loop
      Found := R.Find_From (Compiled.Expression, Text, From);
      exit when Found.Status /= R.Match_Ok;

      Put_Line
        ("match at first =" & Natural'Image (Found.First) &
         ", last =" & Natural'Image (Found.Last));

      From := Found.Last + 1;
   end loop;
end Find_From_Offsets;
