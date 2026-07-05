with Ada.Command_Line;
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

   procedure Require_Error
     (Pattern : String;
      Status  : R.Compile_Status;
      Offset  : Natural)
   is
      use type R.Compile_Status;
      Result : constant R.Compile_Result := R.Compile (Pattern);
   begin
      if Result.Status /= Status or else Result.Error_Offset /= Offset then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end Require_Error;
begin
   Try ("");
   Try ("\x");
   Try ("[z-a]");
   Try ("a|b");

   Require_Error ("", R.Empty_Pattern, 0);
   Require_Error ("\x", R.Invalid_Escape, 2);
   Require_Error ("[z-a]", R.Invalid_Class_Range, 4);
   Require_Error ("a|b", R.Unsupported_Syntax, 2);
end Compile_Errors;
