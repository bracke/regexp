with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;

with Regexp;

procedure Search_Workflow is
   package R renames Regexp;
   use type R.Compile_Status;
   use type R.Find_All_Status;
   use type R.Match_Status;
   use type R.Replace_Status;

   Text     : constant String := "one two" & Character'Val (10) & "two three";
   Compiled : constant R.Compile_Result := R.Compile_Whole_Word ("two");
   Lines    : R.Text_Range_Array (1 .. 4);
   Summary  : R.Find_All_Summary_Result;
   Count    : Natural;
   Status   : R.Find_All_Status;
   Needed   : Natural;
   Replaced : Natural;
   R_Status : R.Replace_Status;
   Limited_Found : R.Match_Result;
begin
   if Compiled.Status /= R.Compile_Ok then
      Put_Line ("compile failed: " & R.Status_Image (Compiled.Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Summary := R.Find_All_Summary (Compiled.Expression, Text);
   R.Find_All_Lines (Compiled.Expression, Text, Lines, Count, Status);
   R.Replace_All_Size (Compiled.Expression, Text, "2", Needed, R_Status, Replaced);
   Limited_Found := R.Find_First (Compiled.Expression, Text, (Max_Steps => 1, others => <>));

   Put_Line ("matches: " & Natural'Image (Summary.Count));
   Put_Line ("line ranges: " & Natural'Image (Count));
   Put_Line ("replace bytes: " & Natural'Image (Needed));
   Put_Line ("limited status: " & R.Status_Image (Limited_Found.Status));

   if Summary.Status /= R.Find_All_Ok
     or else Status /= R.Find_All_Ok
     or else R_Status /= R.Replace_Ok
     or else Summary.Count /= 2
     or else Count /= 2
     or else Replaced /= 2
     or else Limited_Found.Status /= R.Match_Limit_Exceeded
   then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Search_Workflow;
