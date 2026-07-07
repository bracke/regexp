with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Preset_Patterns is
   package R renames Regexp;
   use type R.Compile_Status;
   use type R.Match_Status;

   UUID  : constant R.Compile_Result := R.Compile (R.UUID_Pattern);
   Hex   : constant R.Compile_Result := R.Compile (R.Hex_Integer_Pattern);
   Email : constant R.Compile_Result := R.Compile (R.Simple_Email_Pattern);
   URL   : constant R.Compile_Result := R.Compile (R.Simple_URL_Pattern);

   UUID_Found  : R.Match_Result;
   Hex_Found   : R.Match_Result;
   Email_Found : R.Match_Result;
   URL_Found   : R.Match_Result;
begin
   if UUID.Status /= R.Compile_Ok
     or else Hex.Status /= R.Compile_Ok
     or else Email.Status /= R.Compile_Ok
     or else URL.Status /= R.Compile_Ok
   then
      Put_Line ("compile failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   UUID_Found := R.Find_First (UUID.Expression, "id 550e8400-e29b-41d4-a716-446655440000");
   Hex_Found := R.Find_First (Hex.Expression, "mask 0xBEEF");
   Email_Found := R.Find_First (Email.Expression, "contact ops@example.com");
   URL_Found := R.Find_First (URL.Expression, "see https://example.com/docs");

   Put_Line ("uuid:  " & R.Status_Image (UUID_Found.Status));
   Put_Line ("hex:   " & R.Status_Image (Hex_Found.Status));
   Put_Line ("email: " & R.Status_Image (Email_Found.Status));
   Put_Line ("url:   " & R.Status_Image (URL_Found.Status));

   if UUID_Found.Status /= R.Match_Ok
     or else Hex_Found.Status /= R.Match_Ok
     or else Email_Found.Status /= R.Match_Ok
     or else URL_Found.Status /= R.Match_Ok
   then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Preset_Patterns;
