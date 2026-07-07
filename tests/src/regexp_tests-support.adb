with AUnit.Assertions;
package body Regexp_Tests.Support is
   use AUnit.Assertions;
   use Regexp;

   procedure Check_Limit
     (Value    : Positive;
      Expected : Positive;
      Name     : String)
   is
   begin
      Assert (Value = Expected, Name);
   end Check_Limit;

   procedure Check_Compile
     (Pattern  : String;
      Expected : Compile_Status;
      Name     : String)
   is
      Result : constant Compile_Result := Compile (Pattern);
   begin
      Assert
        (Result.Status = Expected,
         Name & " compile status got " & Status_Image (Result.Status));
   end Check_Compile;

   procedure Check_Compile_Error
     (Pattern  : String;
      Expected : Compile_Status;
      Offset   : Natural;
      Name     : String)
   is
      Result : constant Compile_Result := Compile (Pattern);
   begin
      Assert
        (Result.Status = Expected,
         Name & " compile status got " & Status_Image (Result.Status));
      Assert (Result.Error_Offset = Offset, Name & " error offset");
   end Check_Compile_Error;

   procedure Check_Match
     (Pattern  : String;
      Text     : String;
      Expected : Match_Status;
      Name     : String;
      First    : Natural := 0;
      Last     : Natural := 0;
      Options  : Match_Options := (others => <>);
      Entire   : Boolean := False)
   is
      Compiled : constant Compile_Result := Compile (Pattern);
      Found    : Match_Result;
   begin
      Assert (Compiled.Status = Compile_Ok, Name & " compiled");
      if Entire then
         Found := Matches_Entire (Compiled.Expression, Text, Options);
      else
         Found := Find_First (Compiled.Expression, Text, Options);
      end if;

      Assert (Found.Status = Expected, Name & " status got " & Status_Image (Found.Status));
      if Expected = Match_Ok then
         Assert (Found.First = First, Name & " first");
         Assert (Found.Last = Last, Name & " last");
      end if;
   end Check_Match;
end Regexp_Tests.Support;
