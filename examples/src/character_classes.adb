with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Character_Classes is
   package R renames Regexp;
   use type R.Compile_Status;
   use type R.Match_Status;

   Digit_Run   : constant R.Compile_Result := R.Compile ("\d+");
   Non_Digits    : constant R.Compile_Result := R.Compile ("\D+");
   Hex_Literal   : constant R.Compile_Result := R.Compile ("0x[0-9A-F]+");
   Not_Space     : constant R.Compile_Result := R.Compile ("\S+");
   Consonant_Run : constant R.Compile_Result := R.Compile ("[a-z--[aeiou]]+");
   Digit_Found   : R.Match_Result;
   Non_Found     : R.Match_Result;
   Hex_Found     : R.Match_Result;
   Word_Found    : R.Match_Result;
   Conson_Found  : R.Match_Result;
begin
   if Digit_Run.Status /= R.Compile_Ok
     or else Non_Digits.Status /= R.Compile_Ok
     or else Hex_Literal.Status /= R.Compile_Ok
     or else Not_Space.Status /= R.Compile_Ok
     or else Consonant_Run.Status /= R.Compile_Ok
   then
      Put_Line ("compile failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Digit_Found := R.Find_First (Digit_Run.Expression, "abc123");
   Non_Found   := R.Find_First (Non_Digits.Expression, "123abc");
   Hex_Found   := R.Find_First (Hex_Literal.Expression, "value 0xBEEF");
   Word_Found  := R.Find_First (Not_Space.Expression, "   word");
   Conson_Found := R.Find_First (Consonant_Run.Expression, "seal");

   Put_Line
     ("\d+ in 'abc123':      " &
      R.Status_Image (Digit_Found.Status));
   Put_Line
     ("\D+ in '123abc':      " &
      R.Status_Image (Non_Found.Status));
   Put_Line
     ("0x[0-9A-F]+ in text: " &
      R.Status_Image (Hex_Found.Status));
   Put_Line
     ("\S+ in spaces+word:  " &
      R.Status_Image (Word_Found.Status));
   Put_Line
     ("[a-z--[aeiou]]+ in 'seal': " &
      R.Status_Image (Conson_Found.Status));

   if Digit_Found.Status /= R.Match_Ok
     or else Non_Found.Status /= R.Match_Ok
     or else Hex_Found.Status /= R.Match_Ok
     or else Word_Found.Status /= R.Match_Ok
     or else Conson_Found.Status /= R.Match_Ok
   then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Character_Classes;
