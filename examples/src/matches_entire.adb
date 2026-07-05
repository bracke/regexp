with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Matches_Entire is
   package R renames Regexp;
   use type R.Compile_Status;
   use type R.Match_Status;

   Identifier : constant R.Compile_Result := R.Compile ("[A-Z]\w*");
   Good       : constant R.Match_Result :=
     R.Matches_Entire (Identifier.Expression, "Ada_2022");
   Bad        : constant R.Match_Result :=
     R.Matches_Entire (Identifier.Expression, "Ada-2022");
begin
   if Identifier.Status /= R.Compile_Ok then
      Put_Line ("compile failed: " & R.Status_Image (Identifier.Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Put_Line ("Ada_2022: " & R.Status_Image (Good.Status));
   Put_Line ("Ada-2022: " & R.Status_Image (Bad.Status));

   if Good.Status /= R.Match_Ok or else Bad.Status /= R.No_Match then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Matches_Entire;
