with Regexp;

package Regexp_Tests.Support is
   procedure Check_Limit
     (Value    : Positive;
      Expected : Positive;
      Name     : String);

   procedure Check_Compile
     (Pattern  : String;
      Expected : Regexp.Compile_Status;
      Name     : String);

   procedure Check_Compile_Error
     (Pattern  : String;
      Expected : Regexp.Compile_Status;
      Offset   : Natural;
      Name     : String);

   procedure Check_Match
     (Pattern  : String;
      Text     : String;
      Expected : Regexp.Match_Status;
      Name     : String;
      First    : Natural := 0;
      Last     : Natural := 0;
      Options  : Regexp.Match_Options := (others => <>);
      Entire   : Boolean := False);
end Regexp_Tests.Support;
