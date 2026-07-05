with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Matches_Entire is
   package R renames Regexp;

   Identifier : constant R.Compile_Result := R.Compile ("[A-Z]\w*");
   Good       : constant R.Match_Result :=
     R.Matches_Entire (Identifier.Expression, "Ada_2022");
   Bad        : constant R.Match_Result :=
     R.Matches_Entire (Identifier.Expression, "Ada-2022");
begin
   Put_Line ("Ada_2022: " & R.Status_Image (Good.Status));
   Put_Line ("Ada-2022: " & R.Status_Image (Bad.Status));
end Matches_Entire;
