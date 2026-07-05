with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Character_Classes is
   package R renames Regexp;

   Digit_Run   : constant R.Compile_Result := R.Compile ("\d+");
   Non_Digits  : constant R.Compile_Result := R.Compile("\D+");
   Hex_Literal : constant R.Compile_Result := R.Compile ("0x[0-9A-F]+");
   Not_Space   : constant R.Compile_Result := R.Compile ("\S+");
begin
   Put_Line
     ("\d+ in 'abc123':      " &
      R.Status_Image (R.Find_First (Digit_Run.Expression, "abc123").Status));
   Put_Line
     ("\D+ in '123abc':      " &
      R.Status_Image (R.Find_First (Non_Digits.Expression, "123abc").Status));
   Put_Line
     ("0x[0-9A-F]+ in text: " &
      R.Status_Image (R.Find_First (Hex_Literal.Expression, "value 0xBEEF").Status));
   Put_Line
     ("\S+ in spaces+word:  " &
      R.Status_Image (R.Find_First (Not_Space.Expression, "   word").Status));
end Character_Classes;
