with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Compile_Errors is
   package R renames Regexp;

   procedure Try (Pattern : String) is
      Result : constant R.Compile_Result := R.Compile (Pattern);
   begin
      Put_Line
        ("pattern '" & Pattern & "': " &
         R.Status_Image (Result.Status) &
         ", offset =" & Natural'Image (Result.Error_Offset));
   end Try;
begin
   Try ("");
   Try ("\x");
   Try ("[z-a]");
   Try ("a|b");
end Compile_Errors;
