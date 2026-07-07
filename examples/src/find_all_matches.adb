with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Find_All_Matches is
   package R renames Regexp;
   use type R.Compile_Status;
   use type R.Find_All_Status;
   use type R.Match_Status;

   Text     : constant String := "one two one two";
   Compiled : constant R.Compile_Result := R.Compile ("two");
   Matches  : R.Match_Result_Array (1 .. 4);
   Count    : Natural;
   Status   : R.Find_All_Status;
begin
   if Compiled.Status /= R.Compile_Ok then
      Put_Line ("compile failed: " & R.Status_Image (Compiled.Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   R.Find_All (Compiled.Expression, Text, Matches, Count, Status);

   Put_Line ("text: " & Text);
   Put_Line ("status: " & R.Status_Image (Status));
   Put_Line ("count: " & Natural'Image (Count));

   for I in 1 .. Count loop
      if Matches (I).Status /= R.Match_Ok then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      Put_Line
        ("match at first =" & Natural'Image (Matches (I).First) &
         ", last =" & Natural'Image (Matches (I).Last));
   end loop;

   if Status /= R.Find_All_Ok or else Count /= 2 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Find_All_Matches;
