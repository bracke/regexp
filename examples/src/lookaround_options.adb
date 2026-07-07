with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Lookaround_Options is
   package R renames Regexp;
   use type R.Compile_Status;
   use type R.Match_Status;

   procedure Check
     (Pattern : String;
      Text    : String;
      Label   : String)
   is
      Compiled : constant R.Compile_Result := R.Compile (Pattern);
      Found    : R.Match_Result;
   begin
      if Compiled.Status /= R.Compile_Ok then
         Put_Line (Label & ": compile failed: " & R.Status_Image (Compiled.Status));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      Found := R.Find_First (Compiled.Expression, Text);
      Put_Line (Label & ": " & R.Status_Image (Found.Status));

      if Found.Status /= R.Match_Ok then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end Check;
begin
   Check ("Ada(?=2022)", "Ada2022", "lookahead");
   Check ("(?<=Ada)2022", "Ada2022", "lookbehind");
   Check ("(?i:ada)", "ADA", "inline options");
end Lookaround_Options;
