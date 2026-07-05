with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Step_Limit is
   package R renames Regexp;
   use type R.Compile_Status;
   use type R.Match_Status;

   Compiled : constant R.Compile_Result := R.Compile ("z");
   Found    : constant R.Match_Result :=
     R.Find_First
       (Compiled.Expression,
        "aaaaaaaaaaaaaaaa",
        (Max_Steps => 5, others => <>));
begin
   if Compiled.Status /= R.Compile_Ok then
      Put_Line ("compile failed: " & R.Status_Image (Compiled.Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Put_Line ("status:     " & R.Status_Image (Found.Status));
   Put_Line ("steps used:" & Natural'Image (Found.Steps_Used));

   if Found.Status /= R.Match_Limit_Exceeded or else Found.Steps_Used /= 5 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Step_Limit;
