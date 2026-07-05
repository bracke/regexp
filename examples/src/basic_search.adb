with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Basic_Search is
   package R renames Regexp;
   use type R.Compile_Status;
   use type R.Match_Status;

   Pattern  : constant String := "a.c";
   Text     : constant String := "xxabcxx";
   Compiled : constant R.Compile_Result := R.Compile (Pattern);
   Found    : R.Match_Result;
begin
   if Compiled.Status /= R.Compile_Ok then
      Put_Line ("compile failed: " & R.Status_Image (Compiled.Status));
      return;
   end if;

   Found := R.Find_First (Compiled.Expression, Text);

   Put_Line ("pattern: " & Pattern);
   Put_Line ("text:    " & Text);
   Put_Line ("status:  " & R.Status_Image (Found.Status));

   if Found.Status = R.Match_Ok then
      Put_Line ("first:  " & Natural'Image (Found.First));
      Put_Line ("last:   " & Natural'Image (Found.Last));
   end if;
end Basic_Search;
