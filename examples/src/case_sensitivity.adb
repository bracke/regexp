with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Case_Sensitivity is
   package R renames Regexp;
   use type R.Compile_Status;
   use type R.Match_Status;

   Compiled : constant R.Compile_Result := R.Compile ("ada");
   Default  : constant R.Match_Result :=
     R.Find_First (Compiled.Expression, "Ada");
   Strict   : constant R.Match_Result :=
     R.Find_First
       (Compiled.Expression,
        "Ada",
        (Case_Sensitive => True, others => <>));
begin
   if Compiled.Status /= R.Compile_Ok then
      Put_Line ("compile failed: " & R.Status_Image (Compiled.Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Put_Line ("default match:        " & R.Status_Image (Default.Status));
   Put_Line ("case-sensitive match: " & R.Status_Image (Strict.Status));

   if Default.Status /= R.Match_Ok or else Strict.Status /= R.No_Match then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Case_Sensitivity;
