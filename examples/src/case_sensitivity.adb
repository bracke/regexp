with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Case_Sensitivity is
   package R renames Regexp;

   Compiled : constant R.Compile_Result := R.Compile ("ada");
   Default  : constant R.Match_Result :=
     R.Find_First (Compiled.Expression, "Ada");
   Strict   : constant R.Match_Result :=
     R.Find_First
       (Compiled.Expression,
        "Ada",
        (Case_Sensitive => True, others => <>));
begin
   Put_Line ("default match:        " & R.Status_Image (Default.Status));
   Put_Line ("case-sensitive match: " & R.Status_Image (Strict.Status));
end Case_Sensitivity;
