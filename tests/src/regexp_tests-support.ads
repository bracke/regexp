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

   --  Like Check_Match but compiles the pattern in UTF_8_Mode, so ".", classes,
   --  and quantifiers match whole code points. First/Last remain byte offsets.
   procedure Check_Match_Utf8
     (Pattern  : String;
      Text     : String;
      Expected : Regexp.Match_Status;
      Name     : String;
      First    : Natural := 0;
      Last     : Natural := 0);
end Regexp_Tests.Support;
