with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Find_From_Offsets is
   package R renames Regexp;
   use type R.Compile_Status;
   use type R.Match_Status;

   Text     : constant String := "one two one two";
   Compiled : constant R.Compile_Result := R.Compile ("two");
   From     : Positive := 1;
   Found    : R.Match_Result;
   Count    : Natural := 0;
begin
   if Compiled.Status /= R.Compile_Ok then
      Put_Line ("compile failed: " & R.Status_Image (Compiled.Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Put_Line ("text: " & Text);

   loop
      Found := R.Find_From (Compiled.Expression, Text, From);
      exit when Found.Status /= R.Match_Ok;

      Put_Line
        ("match at first =" & Natural'Image (Found.First) &
         ", last =" & Natural'Image (Found.Last));

      Count := Count + 1;
      From := Found.Last + 1;
   end loop;

   if Found.Status /= R.No_Match or else Count /= 2 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Find_From_Offsets;
