with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Step_Limit is
   package R renames Regexp;

   Compiled : constant R.Compile_Result := R.Compile ("z");
   Found    : constant R.Match_Result :=
     R.Find_First
       (Compiled.Expression,
        "aaaaaaaaaaaaaaaa",
        (Max_Steps => 5, others => <>));
begin
   Put_Line ("status:     " & R.Status_Image (Found.Status));
   Put_Line ("steps used:" & Natural'Image (Found.Steps_Used));
end Step_Limit;
