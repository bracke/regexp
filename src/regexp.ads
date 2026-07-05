package Regexp is
   pragma Pure;
   pragma SPARK_Mode (On);

   --  Compiled regular expression.
   --
   --  Values are produced by Compile. A default-initialized value is invalid and
   --  matching functions return Invalid_Regexp for it.
   type Regexp is private;

   --  Result status returned by Compile.
   type Compile_Status is
     (Compile_Ok,
      --  The pattern was compiled successfully.
      Empty_Pattern,
      --  The supplied pattern was empty.
      Pattern_Too_Long,
      --  The pattern length exceeded the supplied maximum.
      Too_Many_States,
      --  The pattern would require more states than the supplied maximum.
      Invalid_Escape,
      --  The pattern contains an unknown or incomplete escape sequence.
      Unterminated_Class,
      --  A character class was opened but not closed.
      Empty_Class,
      --  A character class contained no members.
      Invalid_Class_Range,
      --  A character class range is malformed.
      Invalid_Quantifier,
      --  A quantifier is repeated or otherwise malformed.
      Quantifier_Without_Atom,
      --  A quantifier appeared without a preceding atom.
      Unsupported_Syntax);
      --  The pattern uses syntax not supported by this implementation.

   --  Result status returned by matching functions.
   type Match_Status is
     (Match_Ok,
      --  A match was found.
      No_Match,
      --  No match was found.
      Match_Limit_Exceeded,
      --  Matching stopped after consuming the configured step limit.
      Invalid_Regexp);
      --  The supplied expression is not a valid compiled regular expression.

   --  Result returned by matching functions.
   type Match_Result is record
      Status     : Match_Status := No_Match;
      --  Match outcome.
      First      : Natural := 0;
      --  One-based offset of the first matched character relative to Text'First.
      Last       : Natural := 0;
      --  One-based offset of the last matched character relative to Text'First.
      --  Zero-length matches report Last less than First.
      Steps_Used : Natural := 0;
      --  Number of matching steps consumed before returning.
   end record;

   --  Result returned by Compile.
   type Compile_Result is record
      Status       : Compile_Status := Empty_Pattern;
      --  Compile outcome.
      Expression   : Regexp;
      --  Compiled expression. Valid only when Status is Compile_Ok.
      Error_Offset : Natural := 0;
      --  One-based pattern offset associated with a compile error, or 0 when
      --  no specific offset applies.
   end record;

   --  Options controlling matching behavior.
   type Match_Options is record
      Case_Sensitive : Boolean := False;
      --  When False, ASCII letters are matched case-insensitively.
      Whole_Word     : Boolean := False;
      --  When True, successful matches must be bounded by non-word characters
      --  or text boundaries.
      Max_Steps      : Natural := 50_000;
      --  Maximum number of matching steps before reporting Match_Limit_Exceeded.
   end record;

   --  Default maximum pattern length accepted by Compile.
   Default_Max_Pattern_Length : constant Positive := 256;
   --  Default maximum number of NFA states accepted by Compile.
   Default_Max_States         : constant Positive := 512;
   --  Default maximum number of matching steps.
   Default_Max_Steps          : constant Positive := 50_000;

   --  Compile Pattern into a regular expression.
   --
   --  Supported syntax includes literals, '.', '^', '$', character classes,
   --  negated classes, ranges, '*', '+', '?', and the \d, \D, \w, \W, \s,
   --  and \S escapes. Grouping, alternation, and bounded repeats are reported
   --  as Unsupported_Syntax.
   --
   --  @param Pattern Source regular-expression pattern.
   --  @param Max_Pattern_Length Maximum accepted length for Pattern.
   --  @param Max_States Maximum accepted number of compiled states.
   --  @return Compile result containing status, compiled expression, and any
   --          error offset.
   function Compile
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
      with Pre => Pattern'Last < Positive'Last;

   --  Test whether Expression is a successfully compiled regular expression.
   --
   --  @param Expression Regular expression value to test.
   --  @return True when Expression can be used for matching.
   function Is_Valid (Expression : Regexp) return Boolean;

   --  Find the first match of Expression in Text.
   --
   --  The returned First and Last offsets are relative to Text'First, so slices
   --  report positions starting at 1.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Options Matching options.
   --  @return Match result for the earliest match, or a failure status.
   function Find_First
     (Expression : Regexp;
      Text       : String;
      Options    : Match_Options := (others => <>))
      return Match_Result
      with Pre => Text'Last < Positive'Last;

   --  Find the first match of Expression in Text at or after From.
   --
   --  From is a one-based offset relative to Text'First. Passing Text'Length + 1
   --  permits zero-length end-anchor matches at the end of Text.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param From One-based starting offset relative to Text'First.
   --  @param Options Matching options.
   --  @return Match result for the earliest match at or after From, or a
   --          failure status.
   function Find_From
     (Expression : Regexp;
      Text       : String;
      From       : Positive;
      Options    : Match_Options := (others => <>))
      return Match_Result
      with Pre => Text'Last < Positive'Last;

   --  Match Expression against all of Text.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to match.
   --  @param Options Matching options.
   --  @return Match result with Match_Ok only when the expression consumes the
   --          entire Text.
   function Matches_Entire
     (Expression : Regexp;
      Text       : String;
      Options    : Match_Options := (others => <>))
      return Match_Result
      with Pre => Text'Last < Positive'Last;

   --  Return an image for a compile status.
   --
   --  @param Status Compile status to format.
   --  @return Human-readable status name.
   function Status_Image (Status : Compile_Status) return String;

   --  Return an image for a match status.
   --
   --  @param Status Match status to format.
   --  @return Human-readable status name.
   function Status_Image (Status : Match_Status) return String;

private
   type Node_Kind is
     (Node_Invalid,
      Node_Match,
      Node_Char,
      Node_Any,
      Node_Class,
      Node_Split,
      Node_Start_Line,
      Node_End_Line);

   type State_Index is new Natural range 0 .. Default_Max_States;
   subtype State_Count_Type is Natural range 0 .. Default_Max_States;
   No_State : constant State_Index := 0;

   type Character_Set is array (Character) of Boolean;

   type Character_Class is record
      Negated : Boolean := False;
      Members : Character_Set := [others => False];
   end record;

   type State is record
      Kind  : Node_Kind := Node_Invalid;
      Ch    : Character := Character'Val (0);
      Class : Character_Class;
      Out_1 : State_Index := No_State;
      Out_2 : State_Index := No_State;
   end record;

   type State_Array is array (Positive range <>) of State;

   type Regexp is record
      Valid       : Boolean := False;
      State_Count : State_Count_Type := 0;
      Start       : State_Index := No_State;
      States      : State_Array (1 .. Default_Max_States);
   end record;
end Regexp;
