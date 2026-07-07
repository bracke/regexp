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
      Too_Many_Captures,
      --  The pattern declares more capture groups than Max_Captures.
      Invalid_Capture_Name,
      --  A named capture has an empty, too long, or malformed name.
      Duplicate_Capture_Name,
      --  A named capture reuses an earlier capture name.
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

   --  Optional callback used to request cancellation during matching.
   type Match_Abort_Callback is access function return Boolean;

   --  Result status returned by Find_All.
   type Find_All_Status is
     (Find_All_Ok,
      --  All matches were collected.
      No_Matches,
      --  No matches were found.
      Too_Many_Matches,
      --  The supplied output array was too small for all matches.
      Find_All_Limit_Exceeded,
      --  Matching stopped after consuming the configured step limit.
      Find_All_Invalid_Regexp);
      --  The supplied expression is not a valid compiled regular expression.

   --  Detailed status for streaming tokenization.
   type Token_Stream_Status is
     (Token_Stream_Ok,
      --  Tokens were produced or the final chunk was fully processed.
      Token_Stream_Need_More_Data,
      --  No token is complete yet and more input may produce one.
      Token_Stream_No_Token,
      --  No token can be produced.
      Token_Stream_Output_Too_Small,
      --  The supplied token output array was too small.
      Token_Stream_Buffer_Full,
      --  The retained token buffer cannot accept the supplied chunk.
      Token_Stream_Limit_Exceeded,
      --  Matching stopped after consuming the configured step limit.
      Token_Stream_Invalid_Regexp);
      --  A supplied expression is invalid.

   --  Result status returned by replacement helpers.
   type Replace_Status is
     (Replace_Ok,
      --  Replacement completed.
      Replace_No_Match,
      --  No match was found and Output contains the original text.
      Replace_Output_Too_Small,
      --  Output was too small for the replaced text.
      Replace_Limit_Exceeded,
      --  Matching stopped after consuming the configured step limit.
      Replace_Invalid_Regexp);
      --  The supplied expression is not a valid compiled regular expression.

   --  Result status returned by replacement validation.
   type Replacement_Validation_Status is
     (Replacement_Ok,
      --  Replacement syntax is valid for the supplied expression.
      Replacement_Invalid_Regexp,
      --  The supplied expression is not a valid compiled regular expression.
      Replacement_Invalid_Escape,
      --  The replacement contains an unknown or incomplete escape.
      Replacement_Unknown_Capture,
      --  The replacement refers to a missing numbered or named capture.
      Replacement_Unterminated_Name,
      --  A named capture reference was opened but not closed.
      Replacement_Unterminated_Case_Conversion);
      --  A \U or \L case-conversion span was not closed with \E.

   --  Result status returned by Split.
   type Split_Status is
     (Split_Ok,
      --  Split completed.
      Too_Many_Parts,
      --  The supplied Parts array was too small for all split ranges.
      Split_Limit_Exceeded,
      --  Matching stopped after consuming the configured step limit.
      Split_Invalid_Regexp);
      --  The supplied expression is not a valid compiled regular expression.

   --  Result status returned by Copy_Match.
   type Copy_Status is
     (Copy_Ok,
      --  Match text was copied.
      Copy_No_Match,
      --  The supplied match result does not contain a match.
      Copy_Output_Too_Small);
      --  Output was too small for the match text.

   --  Result status returned by streaming search.
   type Stream_Status is
     (Stream_Match,
      --  A match was found in the buffered stream data.
      Stream_No_Match,
      --  No complete match is currently available.
      Stream_Limit_Exceeded,
      --  Matching stopped after consuming the configured step limit.
      Stream_Buffer_Full,
      --  The internal stream buffer cannot accept the supplied chunk.
      Stream_Invalid_Regexp);
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

   --  Caller-supplied output buffer for Find_All.
   type Match_Result_Array is array (Positive range <>) of Match_Result;

   --  Caller-supplied output buffer for capture indexes.
   type Capture_Index_Array is array (Positive range <>) of Natural;

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

   --  Character interpretation mode for matching helpers.
   type Character_Mode_Type is
     (ASCII_Mode,
      --  Existing byte-oriented ASCII behavior.
      UTF_8_Mode);
      --  Validate UTF-8 input and treat non-ASCII UTF-8 bytes as word bytes.

   --  Options controlling matching behavior.
   type Match_Options is record
      Case_Sensitive : Boolean := False;
      --  When False, ASCII letters are matched case-insensitively.
      Whole_Word     : Boolean := False;
      --  When True, successful matches must be bounded by non-word characters
      --  or text boundaries.
      Dot_Matches_Newline : Boolean := False;
      --  When True, '.' also matches LF and CR.
      Multiline_Anchors   : Boolean := False;
      --  When True, '^' and '$' match after and before line breaks.
      Character_Mode      : Character_Mode_Type := ASCII_Mode;
      --  Character interpretation mode. UTF_8_Mode preserves byte offsets.
      Max_Steps      : Natural := 50_000;
      --  Maximum number of matching steps before reporting Match_Limit_Exceeded.
      Abort_Callback : Match_Abort_Callback := null;
      --  Optional user callback that returns True to request cancellation.
      --  Cancellation ends matching early and returns Match_Limit_Exceeded.
   end record;

   --  One-based inclusive range relative to Text'First. Empty ranges report
   --  Last less than First.
   type Text_Range is record
      First : Natural := 0;
      Last  : Natural := 0;
   end record;

   --  Caller-supplied output buffer for text ranges.
   type Text_Range_Array is array (Positive range <>) of Text_Range;

   --  Fixed capture buffer returned by convenience iterator APIs.
   subtype Capture_Buffer is Text_Range_Array (1 .. 16);

   --  Match plus capture ranges returned by convenience iterator APIs.
   type Captured_Match_Result is record
      Found         : Match_Result := (others => <>);
      --  Match result.
      Captures      : Capture_Buffer := [others => (First => 0, Last => 0)];
      --  Capture ranges for the match.
      Capture_Count : Natural := 0;
      --  Number of capture ranges written.
   end record;

   --  One-based source position. A zero line and column report an invalid or
   --  out-of-range input offset.
   type Source_Position is record
      Line   : Natural := 0;
      Column : Natural := 0;
   end record;

   --  UTF-8 validation result.
   type UTF_8_Validation_Result is record
      Valid        : Boolean := False;
      --  True when the input is well-formed UTF-8.
      Error_Offset : Natural := 0;
      --  First invalid byte offset, or 0.
   end record;

   --  Detailed result returned by replacement validation.
   type Replacement_Validation_Result is record
      Status       : Replacement_Validation_Status := Replacement_Ok;
      --  Validation status.
      Error_Offset : Natural := 0;
      --  One-based replacement offset for the error, or 0.
      Capture      : Natural := 0;
      --  Numbered or named capture index associated with the reference.
      Name         : Text_Range := (others => 0);
      --  One-based replacement range containing the name in \k<name>.
   end record;

   --  Bounded feature summary for a compiled expression.
   type Pattern_Features is record
      Has_Captures          : Boolean := False;
      --  The expression exports numbered captures.
      Has_Named_Captures    : Boolean := False;
      --  At least one exported capture has a name.
      Has_Backreferences    : Boolean := False;
      --  The expression uses numbered or named backreferences.
      Has_Anchors           : Boolean := False;
      --  The expression uses ^ or $ anchors.
      Has_Word_Boundaries   : Boolean := False;
      --  The expression uses \b or \B.
      Has_Lookaround        : Boolean := False;
      --  The expression uses lookahead or lookbehind assertions.
      Has_Atomic            : Boolean := False;
      --  The expression uses atomic groups or possessive internals.
      Has_Character_Classes : Boolean := False;
      --  The expression uses character classes or shorthand classes.
      Has_Dot               : Boolean := False;
      --  The expression uses '.'.
      Has_Scoped_Options    : Boolean := False;
      --  The expression contains scoped option state.
      Has_Splits            : Boolean := False;
      --  The compiled graph contains split states.
      May_Match_Empty       : Boolean := False;
      --  The expression can match the empty string.
   end record;

   --  Syntax feature query for tools.
   type Syntax_Feature is
     (Syntax_Literals,
      Syntax_Dot,
      Syntax_Anchors,
      Syntax_Character_Classes,
      Syntax_Unicode_Properties,
      Syntax_Posix_Classes,
      Syntax_Class_Set_Operations,
      Syntax_Groups,
      Syntax_Named_Captures,
      Syntax_Non_Capturing_Groups,
      Syntax_Alternation,
      Syntax_Lookahead,
      Syntax_Lookbehind,
      Syntax_Backreferences,
      Syntax_Bounded_Repeats,
      Syntax_Lazy_Quantifiers,
      Syntax_Possessive_Quantifiers,
      Syntax_Atomic_Groups,
      Syntax_Inline_Options,
      Syntax_Word_Boundaries);

   --  Caller-supplied output buffer for syntax feature inventories.
   type Syntax_Feature_Array is array (Positive range <>) of Syntax_Feature;

   --  Structured syntax support inventory item.
   type Syntax_Support is record
      Feature   : Syntax_Feature := Syntax_Literals;
      --  Syntax feature described by this item.
      Supported : Boolean := False;
      --  True when this implementation supports the feature.
      Note_First    : Natural := 0;
      --  First one-based note offset in the shared notes text, or 0.
      Note_Last     : Natural := 0;
      --  Last one-based note offset in the shared notes text, or 0.
      Example_First : Natural := 0;
      --  First one-based example offset in the shared examples text, or 0.
      Example_Last  : Natural := 0;
      --  Last one-based example offset in the shared examples text, or 0.
   end record;

   --  Caller-supplied output buffer for structured syntax support.
   type Syntax_Support_Array is array (Positive range <>) of Syntax_Support;

   --  Summary returned by Find_All_Summary.
   type Find_All_Summary_Result is record
      Status      : Find_All_Status := No_Matches;
      --  Summary status.
      Count       : Natural := 0;
      --  Number of non-overlapping matches found.
      First_Match : Match_Result := (others => <>);
      --  First match, or No_Match when Count is zero.
      Last_Match  : Match_Result := (others => <>);
      --  Last match, or No_Match when Count is zero.
      Steps_Used  : Natural := 0;
      --  Total matching steps consumed.
   end record;

   --  Summary returned by Find_All_Line_Summary.
   type Find_All_Line_Summary_Result is record
      Status         : Find_All_Status := No_Matches;
      --  Summary status.
      Count          : Natural := 0;
      --  Number of non-overlapping matches found.
      First_Position : Source_Position := (others => 0);
      --  Line/column of the first match, or (0, 0).
      Last_Position  : Source_Position := (others => 0);
      --  Line/column of the last match, or (0, 0).
      First_Line     : Text_Range := (others => 0);
      --  Containing line for the first match, or (0, 0).
      Last_Line      : Text_Range := (others => 0);
      --  Containing line for the last match, or (0, 0).
      Steps_Used     : Natural := 0;
      --  Total matching steps consumed.
   end record;

   --  Capture ranges for capture-aware Find_All helpers.
   type Capture_Result_Array is array (Positive range <>, Positive range <>) of Text_Range;

   --  Replacement feature summary for a replacement template.
   type Replacement_Features is record
      Valid                  : Boolean := False;
      --  True when replacement syntax validates for the expression.
      Uses_Whole_Match       : Boolean := False;
      --  The template references \0.
      Uses_Numbered_Captures : Boolean := False;
      --  The template references \1 through \9.
      Uses_Named_Captures    : Boolean := False;
      --  The template references \k<name>.
      Uses_Case_Conversion   : Boolean := False;
      --  The template uses \U, \L, \u, or \l.
      Reference_Count        : Natural := 0;
      --  Number of references written or counted.
      Complete               : Boolean := True;
      --  False when more references exist than the caller-supplied buffer.
      Validation             : Replacement_Validation_Result := (others => <>);
      --  Replacement validation detail.
   end record;

   --  Suggested search strategy for tools and planners.
   type Search_Strategy is
     (Search_Invalid,
      --  The expression is invalid.
      Search_Literal,
      --  The expression is a pure literal sequence.
      Search_Anchored,
      --  The expression uses anchors and should be tried at anchor positions.
      Search_Prefix,
      --  The expression has a deterministic literal prefix.
      Search_General);
      --  No stronger public strategy is known.

   --  Pattern provenance retained by a compiled expression.
   type Pattern_Source_Kind is
     (Source_Unknown,
      --  No source text is retained.
      Source_Pattern,
      --  Source text came from Compile.
      Source_Literal,
      --  Source text came from Compile_Literal.
      Source_Anchored,
      --  Source text was generated by Compile_Anchored.
      Source_Whole_Word,
      --  Source text was generated by Compile_Whole_Word.
      Source_Line,
      --  Source text was generated by Compile_Line.
      Source_Literal_Anchored,
      --  Source text was generated by Compile_Literal_Anchored.
      Source_Literal_Whole_Word,
      --  Source text was generated by Compile_Literal_Whole_Word.
      Source_Literal_Line,
      --  Source text was generated by Compile_Literal_Line.
      Source_Literal_Set,
      --  Source text was generated by Compile_Literal_Set.
      Source_Literal_Word_Set);
      --  Source text was generated by Compile_Literal_Word_Set.

   --  Bounded expression metadata for tools.
   type Expression_Summary is record
      Valid                  : Boolean := False;
      --  True when Expression can be used for matching.
      State_Count            : Natural := 0;
      --  Number of compiled states.
      Capture_Count          : Natural := 0;
      --  Number of exported captures.
      Feature                : Pattern_Features := (others => <>);
      --  Compiled feature flags.
      Source_Kind            : Pattern_Source_Kind := Source_Unknown;
      --  Source provenance.
      Source_Length          : Natural := 0;
      --  Retained source text length.
      Required_Prefix_Length : Natural := 0;
      --  Deterministic prefix length, or 0.
      Strategy               : Search_Strategy := Search_Invalid;
      --  Recommended search strategy.
   end record;

   --  Bounded lint flags for compiled expressions and source patterns.
   type Pattern_Lint is record
      Valid                    : Boolean := False;
      --  True when Expression is valid.
      May_Match_Empty          : Boolean := False;
      --  Expression may match empty text.
      Uses_Lookaround_In_Stream : Boolean := False;
      --  Expression is not recommended for stream matching.
      Broad_Dot_Star           : Boolean := False;
      --  Pattern source contains a broad dot-star fragment.
      No_Required_Prefix       : Boolean := False;
      --  No deterministic literal prefix was found.
   end record;

   --  Replacement reference kind reported by Replacement_References.
   type Replacement_Reference_Kind is
     (Replacement_Whole_Match,
      --  The replacement references \0.
      Replacement_Numbered_Capture,
      --  The replacement references \1 through \9.
      Replacement_Named_Capture);
      --  The replacement references \k<name>.

   --  Replacement reference discovered in a replacement template.
   type Replacement_Reference is record
      Kind    : Replacement_Reference_Kind := Replacement_Whole_Match;
      --  Reference kind.
      Offset  : Natural := 0;
      --  One-based replacement offset of the escape.
      Capture : Natural := 0;
      --  Referenced capture index, or 0 when not applicable.
      Name    : Text_Range := (others => 0);
      --  One-based name range for \k<name>, or (0, 0).
   end record;

   --  Policy for rejecting compiled patterns before matching.
   type Pattern_Policy is record
      Allow_Captures          : Boolean := True;
      --  Allow exported captures.
      Allow_Named_Captures    : Boolean := True;
      --  Allow named captures.
      Allow_Backreferences    : Boolean := True;
      --  Allow backreferences.
      Allow_Anchors           : Boolean := True;
      --  Allow ^ and $.
      Allow_Word_Boundaries   : Boolean := True;
      --  Allow \b and \B.
      Allow_Lookaround        : Boolean := True;
      --  Allow lookahead and lookbehind.
      Allow_Atomic            : Boolean := True;
      --  Allow atomic or possessive internals.
      Allow_Character_Classes : Boolean := True;
      --  Allow character classes and shorthand classes.
      Allow_Dot               : Boolean := True;
      --  Allow '.'.
      Allow_Empty_Match       : Boolean := True;
      --  Allow expressions that can match the empty string.
   end record;

   --  Result status returned by policy validation.
   type Pattern_Policy_Status is
     (Policy_Ok,
      --  The expression satisfies the supplied policy.
      Policy_Invalid_Regexp,
      --  The expression is invalid.
      Policy_Disallowed_Feature,
      --  A policy-disallowed feature was found.
      Policy_Disallowed_Empty_Match);
      --  The expression can match empty text and the policy forbids it.

   --  Feature identified by detailed policy validation.
   type Policy_Feature is
     (Policy_Feature_None,
      Policy_Feature_Captures,
      Policy_Feature_Named_Captures,
      Policy_Feature_Backreferences,
      Policy_Feature_Anchors,
      Policy_Feature_Word_Boundaries,
      Policy_Feature_Lookaround,
      Policy_Feature_Atomic,
      Policy_Feature_Character_Classes,
      Policy_Feature_Dot,
      Policy_Feature_Empty_Match);

   --  Detailed policy validation result.
   type Pattern_Policy_Diagnostic is record
      Status  : Pattern_Policy_Status := Policy_Ok;
      --  Policy validation status.
      Feature : Policy_Feature := Policy_Feature_None;
      --  First disallowed feature, or None.
   end record;

   --  Caller-supplied output buffer for replacement references.
   type Replacement_Reference_Array is array (Positive range <>) of Replacement_Reference;

   --  Caller-supplied pattern list for multi-pattern helpers.
   type Regexp_Array is array (Positive range <>) of Regexp;

   --  Caller-supplied numeric token kinds.
   type Natural_Array is array (Positive range <>) of Natural;

   --  Token or pattern-set result.
   type Pattern_Match_Result is record
      Pattern_Index : Natural := 0;
      --  One-based index in the supplied expression array.
      Kind          : Natural := 0;
      --  Caller-defined token kind, or Pattern_Index when no kind array is used.
      Found         : Match_Result := (others => <>);
      --  Best match.
   end record;

   --  Caller-supplied output buffer for tokenization.
   type Pattern_Match_Array is array (Positive range <>) of Pattern_Match_Result;

   --  Pattern-set result with capture ranges.
   type Pattern_Match_Captures_Result is record
      Pattern_Index : Natural := 0;
      --  One-based index in the supplied expression array.
      Kind          : Natural := 0;
      --  Caller-defined token kind, or Pattern_Index when no kind array is used.
      Match         : Captured_Match_Result := (others => <>);
      --  Match and capture ranges.
   end record;

   --  Caller-supplied output buffer for captured tokenization.
   type Pattern_Match_Captures_Array is array (Positive range <>) of Pattern_Match_Captures_Result;

   --  Bounded token name storage for diagnostics and highlighting.
   type Token_Name_Buffer is array (Positive range 1 .. 32) of Character;

   type Token_Name is record
      Kind   : Natural := 0;
      --  Token kind associated with this name.
      Length : Natural := 0;
      --  Number of characters stored in Text.
      Text   : Token_Name_Buffer := [others => Character'Val (0)];
      --  Bounded token name text.
   end record;

   type Token_Name_Array is array (Positive range <>) of Token_Name;

   --  Machine-readable diagnostic category.
   type Diagnostic_Kind is
     (Diagnostic_None,
      Diagnostic_Syntax,
      Diagnostic_Unsupported,
      Diagnostic_Limit,
      Diagnostic_Invalid_Expression,
      Diagnostic_Invalid_Replacement,
      Diagnostic_Unknown_Capture);

   --  Structured compile diagnostic.
   type Compile_Diagnostic_Record is record
      Status : Compile_Status := Compile_Ok;
      --  Compile status.
      Kind   : Diagnostic_Kind := Diagnostic_None;
      --  Diagnostic class.
      Offset : Natural := 0;
      --  One-based pattern offset, or 0.
   end record;

   --  Structured replacement diagnostic.
   type Replacement_Diagnostic_Record is record
      Detail : Replacement_Validation_Result := (others => <>);
      --  Replacement validation detail.
      Kind   : Diagnostic_Kind := Diagnostic_None;
      --  Diagnostic class.
   end record;

   --  Planned source range for replacement previews.
   type Replacement_Edit is record
      Source         : Text_Range := (others => 0);
      --  Source range copied or replaced.
      Is_Replacement : Boolean := False;
      --  True when Source is a match that would be replaced.
      Required_Length : Natural := 0;
      --  Required expanded output length for this edit.
      Output_First    : Natural := 0;
      --  First one-based output offset for this edit in the planned output.
      Output_Last     : Natural := 0;
      --  Last one-based output offset for this edit in the planned output.
      Reference_First : Natural := 0;
      --  First replacement-reference slot used by this edit, or 0.
      Reference_Last  : Natural := 0;
      --  Last replacement-reference slot used by this edit, or 0.
   end record;

   --  Caller-supplied output buffer for replacement previews.
   type Replacement_Edit_Array is array (Positive range <>) of Replacement_Edit;

   --  Stable bounded fingerprint for cache keys and manifests.
   type Pattern_Fingerprint is record
      Hash          : Natural := 0;
      --  Deterministic non-cryptographic hash.
      Source_Length : Natural := 0;
      --  Retained source length included in the hash.
      State_Count   : Natural := 0;
      --  Compiled state count included in the hash.
      Capture_Count : Natural := 0;
      --  Capture count included in the hash.
   end record;

   --  Pattern serialization metadata for cache manifests and logs.
   type Pattern_Metadata is record
      Valid          : Boolean := False;
      --  True when Expression is valid.
      Source_Kind    : Pattern_Source_Kind := Source_Unknown;
      --  Retained source provenance.
      Source_Length  : Natural := 0;
      --  Retained source length.
      Max_Pattern_Length : Natural := 256;
      --  Default maximum pattern length associated with this build.
      Max_States     : Natural := 512;
      --  Default maximum state count associated with this build.
      Feature        : Pattern_Features := (others => <>);
      --  Feature flags.
      Fingerprint    : Pattern_Fingerprint := (others => <>);
      --  Stable fingerprint.
   end record;

   --  Source-to-output mapping for replacement previews.
   type Replacement_Output_Map is record
      Source        : Text_Range := (others => 0);
      --  Source range copied or replaced.
      Output        : Text_Range := (others => 0);
      --  Output range produced by this source range.
      Is_Replacement : Boolean := False;
      --  True when Source is a replacement range.
   end record;

   type Replacement_Output_Map_Array is array (Positive range <>) of Replacement_Output_Map;

   --  Replacement plan with capture-reference inventory and output mapping.
   type Replacement_Plan is record
      Status          : Replace_Status := Replace_No_Match;
      --  Planning status.
      Edit_Count      : Natural := 0;
      --  Number of edits written.
      Reference_Count : Natural := 0;
      --  Number of replacement references written.
      Map_Count       : Natural := 0;
      --  Number of output map entries written.
      Complete        : Boolean := True;
      --  True when every edit, reference, and map entry fit.
      Required_Length : Natural := 0;
      --  Total required output length.
   end record;

   --  Line-oriented captured match result.
   type Line_Captured_Match_Result is record
      Match         : Captured_Match_Result := (others => <>);
      --  Match and capture ranges.
      Position      : Source_Position := (others => 0);
      --  Source position of the match.
      Line          : Text_Range := (others => 0);
      --  Containing line range.
   end record;

   --  Public structured expression node kind.
   type Expression_Node_Kind is
     (Expression_Node_Invalid,
      Expression_Node_Match,
      Expression_Node_Char,
      Expression_Node_Any,
      Expression_Node_Class,
      Expression_Node_Split,
      Expression_Node_Start_Line,
      Expression_Node_End_Line,
      Expression_Node_Start_Absolute,
      Expression_Node_End_Absolute,
      Expression_Node_End_Absolute_Optional_Newline,
      Expression_Node_Word_Boundary,
      Expression_Node_Not_Word_Boundary,
      Expression_Node_Lookaround,
      Expression_Node_Capture_Start,
      Expression_Node_Capture_End,
      Expression_Node_Backreference,
      Expression_Node_Atomic);

   --  Structured compiled expression node summary.
   type Expression_Node is record
      Kind    : Expression_Node_Kind := Expression_Node_Invalid;
      --  Public node kind.
      Index   : Natural := 0;
      --  One-based compiled state index.
      Out_1   : Natural := 0;
      --  First outgoing state index, or 0.
      Out_2   : Natural := 0;
      --  Second outgoing state index, or 0.
      Capture : Natural := 0;
      --  Capture index or assertion width when applicable.
      Ch      : Character := Character'Val (0);
      --  Literal character for char nodes.
      Zero_Width : Boolean := False;
      --  True for anchors, word boundaries, and capture markers.
      Negated_Class : Boolean := False;
      --  True for negated character-class nodes.
      Has_Scoped_Options : Boolean := False;
      --  True when this node carries scoped option overrides.
   end record;

   --  Caller-supplied output buffer for structured expression nodes.
   type Expression_Node_Array is array (Positive range <>) of Expression_Node;

   --  Built-in smoke and benchmark cases.
   type Benchmark_Case is
     (Benchmark_Identifier,
      Benchmark_Integer,
      Benchmark_Email,
      Benchmark_Url,
      Benchmark_Key_Value,
      Benchmark_Line_Comment);

   --  Default maximum pattern length accepted by Compile.
   Default_Max_Pattern_Length : constant Positive := 256;
   --  Default maximum number of NFA states accepted by Compile.
   Default_Max_States         : constant Positive := 512;
   --  Default maximum number of matching steps.
   Default_Max_Steps          : constant Positive := 50_000;
   --  Internal bytes retained by Stream_Cursor for cross-chunk matching.
   Default_Stream_Buffer_Length : constant Positive := 4_096;
   --  Maximum numbered capture groups retained by capture-aware APIs.
   Max_Captures : constant Positive := 16;
   --  Maximum length of a named capture.
   Max_Capture_Name_Length : constant Positive := 32;

   Digit_Class : constant String := "\d";
   --  ASCII digit class fragment.
   Non_Digit_Class : constant String := "\D";
   --  ASCII non-digit class fragment.
   Word_Class : constant String := "\w";
   --  ASCII word class fragment.
   Non_Word_Class : constant String := "\W";
   --  ASCII non-word class fragment.
   Whitespace_Class : constant String := "\s";
   --  ASCII whitespace class fragment.
   Non_Whitespace_Class : constant String := "\S";
   --  ASCII non-whitespace class fragment.
   Identifier_Start_Class : constant String := "[A-Z_]";
   --  ASCII identifier-start class fragment for default case-insensitive matching.
   Identifier_Continue_Class : constant String := "\w";
   --  ASCII identifier-continue class fragment.

   Default_Options : constant Match_Options := (others => <>);
   --  Default match options.
   Case_Sensitive_Options : constant Match_Options := (Case_Sensitive => True, others => <>);
   --  Default options with case-sensitive matching enabled.
   Multiline_Options : constant Match_Options := (Multiline_Anchors => True, others => <>);
   --  Default options with multiline anchors enabled.
   Dot_All_Options : constant Match_Options := (Dot_Matches_Newline => True, others => <>);
   --  Default options with dot matching LF and CR.
   UTF_8_Options : constant Match_Options := (Character_Mode => UTF_8_Mode, others => <>);
   --  Default options with UTF-8 validation and UTF-8 word-byte boundaries.

   Literal_Search_Policy : constant Pattern_Policy :=
     (Allow_Captures          => False,
      Allow_Named_Captures    => False,
      Allow_Backreferences    => False,
      Allow_Anchors           => False,
      Allow_Word_Boundaries   => False,
      Allow_Lookaround        => False,
      Allow_Atomic            => False,
      Allow_Character_Classes => False,
      Allow_Dot               => False,
      Allow_Empty_Match       => False);
   --  Policy for pure literal-search patterns.
   Editor_Search_Policy : constant Pattern_Policy := (others => True);
   --  Policy for full editor-search syntax.
   No_Backtracking_Features_Policy : constant Pattern_Policy :=
     (Allow_Captures          => True,
      Allow_Named_Captures    => True,
      Allow_Backreferences    => False,
      Allow_Anchors           => True,
      Allow_Word_Boundaries   => True,
      Allow_Lookaround        => False,
      Allow_Atomic            => False,
      Allow_Character_Classes => True,
      Allow_Dot               => True,
      Allow_Empty_Match       => True);
   --  Policy forbidding backreferences, lookaround, and atomic internals.
   Safe_User_Search_Policy : constant Pattern_Policy :=
     (Allow_Captures          => True,
      Allow_Named_Captures    => True,
      Allow_Backreferences    => False,
      Allow_Anchors           => True,
      Allow_Word_Boundaries   => True,
      Allow_Lookaround        => False,
      Allow_Atomic            => False,
      Allow_Character_Classes => True,
      Allow_Dot               => True,
      Allow_Empty_Match       => False);
   --  Policy for user-supplied searches that should avoid empty and backtracking-heavy forms.
   Streaming_Search_Policy : constant Pattern_Policy :=
     (Allow_Captures          => True,
      Allow_Named_Captures    => True,
      Allow_Backreferences    => False,
      Allow_Anchors           => True,
      Allow_Word_Boundaries   => True,
      Allow_Lookaround        => False,
      Allow_Atomic            => False,
      Allow_Character_Classes => True,
      Allow_Dot               => True,
      Allow_Empty_Match       => False);
   --  Policy for expressions intended for Stream_Cursor.
   Editor_Replace_Policy : constant Pattern_Policy :=
     (Allow_Captures          => True,
      Allow_Named_Captures    => True,
      Allow_Backreferences    => True,
      Allow_Anchors           => True,
      Allow_Word_Boundaries   => True,
      Allow_Lookaround        => True,
      Allow_Atomic            => True,
      Allow_Character_Classes => True,
      Allow_Dot               => True,
      Allow_Empty_Match       => False);
   --  Policy for editor replacements that should not repeatedly replace empty matches.
   No_Empty_Match_Policy : constant Pattern_Policy :=
     (Allow_Captures          => True,
      Allow_Named_Captures    => True,
      Allow_Backreferences    => True,
      Allow_Anchors           => True,
      Allow_Word_Boundaries   => True,
      Allow_Lookaround        => True,
      Allow_Atomic            => True,
      Allow_Character_Classes => True,
      Allow_Dot               => True,
      Allow_Empty_Match       => False);
   --  Policy that only rejects expressions that can match empty text.
   No_Lookaround_Policy : constant Pattern_Policy :=
     (Allow_Captures          => True,
      Allow_Named_Captures    => True,
      Allow_Backreferences    => True,
      Allow_Anchors           => True,
      Allow_Word_Boundaries   => True,
      Allow_Lookaround        => False,
      Allow_Atomic            => True,
      Allow_Character_Classes => True,
      Allow_Dot               => True,
      Allow_Empty_Match       => True);
   --  Policy that rejects lookahead and lookbehind.
   No_Backreferences_Policy : constant Pattern_Policy :=
     (Allow_Captures          => True,
      Allow_Named_Captures    => True,
      Allow_Backreferences    => False,
      Allow_Anchors           => True,
      Allow_Word_Boundaries   => True,
      Allow_Lookaround        => True,
      Allow_Atomic            => True,
      Allow_Character_Classes => True,
      Allow_Dot               => True,
      Allow_Empty_Match       => True);
   --  Policy that rejects numbered and named backreferences.

   Identifier_Pattern     : constant String := "[A-Z_]\w*";
   Integer_Pattern        : constant String := "\d+";
   Whitespace_Run_Pattern : constant String := "\s+";
   Path_Segment_Pattern   : constant String := "[^\s/]+";
   UUID_Pattern           : constant String :=
     "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}";
   Hex_Integer_Pattern    : constant String := "0x[0-9A-F]+";
   Quoted_String_Pattern  : constant String := """([^""\\]|\\.)*""";
   Line_Comment_Pattern   : constant String := "--.*";
   Path_Extension_Pattern : constant String := "\.[A-Z0-9_+-]+";
   Simple_Email_Pattern   : constant String := "[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}";
   Simple_URL_Pattern     : constant String := "https?://[^\s]+";

   --  Compile Pattern into a regular expression.
   --
   --  Supported syntax includes literals, '.', '^', '$', character classes,
   --  negated classes, ranges, class intersection with &&[...], class
   --  subtraction with --[...], numbered capture groups with (...), named
   --  captures with (?<name>...), non-capturing groups with (?:...), top-level
   --  alternation with '|', lookahead assertions with (?=...) and (?!...),
   --  fixed-width lookbehind assertions with (?<=...) and (?<!...), greedy and
   --  lazy quantifiers, possessive quantifiers, bounded repeats, atomic groups
   --  with (?>...), scoped inline option groups such as (?i:...), (?-i:...),
   --  (?m:...), and (?s:...), and the \d, \D, \w, \W, \s, \S, \b, and \B
   --  escapes. Backreferences with \1 through \9 and \k<name> can refer to
   --  earlier captures. Captures inside lookaround assertions are
   --  assertion-local and are not exported by capture-aware APIs.
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

   --  Compile Pattern as literal text, escaping all regexp metacharacters.
   --
   --  @param Pattern Literal text to compile.
   --  @param Max_Pattern_Length Maximum accepted length for Pattern.
   --  @param Max_States Maximum accepted number of compiled states.
   --  @return Compile result containing status, compiled expression, and any
   --          error offset.
   function Compile_Literal
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
      with Pre => Pattern'Last < Positive'Last;

   --  Compile literal terms selected from Text as a safe alternation.
   --
   --  Each range in Literals is escaped and joined with '|'. Empty ranges are
   --  permitted and match the empty string. Invalid ranges return
   --  Unsupported_Syntax. If the generated pattern does not fit
   --  Max_Pattern_Length, Pattern_Too_Long is returned.
   --
   --  @param Text Source text containing literal terms.
   --  @param Literals One-based ranges selecting literal terms from Text.
   --  @param Max_Pattern_Length Maximum generated pattern length.
   --  @param Max_States Maximum accepted number of compiled states.
   --  @return Compile result for the generated literal alternation.
   function Compile_Literal_Set
     (Text               : String;
      Literals           : Text_Range_Array;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
      with Pre => Text'Last < Positive'Last;

   --  Compile literal word terms selected from Text as a safe alternation.
   --
   --  Terms are escaped, joined with '|', grouped, and wrapped in word
   --  boundaries. Empty terms and invalid ranges return Unsupported_Syntax.
   --
   --  @param Text Source text containing literal word terms.
   --  @param Literals One-based ranges selecting literal word terms from Text.
   --  @param Max_Pattern_Length Maximum generated pattern length.
   --  @param Max_States Maximum accepted number of compiled states.
   --  @return Compile result for the generated whole-word alternation.
   function Compile_Literal_Word_Set
     (Text               : String;
      Literals           : Text_Range_Array;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
      with Pre => Text'Last < Positive'Last;

   --  Compile Pattern wrapped as ^(?:Pattern)$.
   --
   --  @param Pattern Source regular-expression pattern to wrap.
   --  @param Max_Pattern_Length Maximum generated pattern length.
   --  @param Max_States Maximum accepted number of compiled states.
   --  @return Compile result for the anchored expression.
   function Compile_Anchored
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
      with Pre => Pattern'Last < Positive'Last;

   --  Compile Pattern wrapped as \b(?:Pattern)\b.
   --
   --  @param Pattern Source regular-expression pattern to wrap.
   --  @param Max_Pattern_Length Maximum generated pattern length.
   --  @param Max_States Maximum accepted number of compiled states.
   --  @return Compile result for the whole-word expression.
   function Compile_Whole_Word
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
      with Pre => Pattern'Last < Positive'Last;

   --  Compile literal Pattern wrapped as ^(?:escaped Pattern)$.
   --
   --  @param Pattern Literal text to escape and wrap.
   --  @param Max_Pattern_Length Maximum generated pattern length.
   --  @param Max_States Maximum accepted number of compiled states.
   --  @return Compile result for the anchored literal expression.
   function Compile_Literal_Anchored
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
      with Pre => Pattern'Last < Positive'Last;

   --  Compile literal Pattern wrapped as \b(?:escaped Pattern)\b.
   --
   --  @param Pattern Literal text to escape and wrap.
   --  @param Max_Pattern_Length Maximum generated pattern length.
   --  @param Max_States Maximum accepted number of compiled states.
   --  @return Compile result for the whole-word literal expression.
   function Compile_Literal_Whole_Word
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
      with Pre => Pattern'Last < Positive'Last;

   --  Compile Pattern wrapped to match a whole line in multiline mode.
   --
   --  @param Pattern Source regular-expression pattern to wrap.
   --  @param Max_Pattern_Length Maximum generated pattern length.
   --  @param Max_States Maximum accepted number of compiled states.
   --  @return Compile result for the line expression.
   function Compile_Line
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
      with Pre => Pattern'Last < Positive'Last;

   --  Compile literal Pattern wrapped to match a whole line in multiline mode.
   --
   --  @param Pattern Literal text to escape and wrap.
   --  @param Max_Pattern_Length Maximum generated pattern length.
   --  @param Max_States Maximum accepted number of compiled states.
   --  @return Compile result for the literal line expression.
   function Compile_Literal_Line
     (Pattern            : String;
      Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
      Max_States         : Positive := Default_Max_States)
      return Compile_Result
      with Pre => Pattern'Last < Positive'Last;

   --  Return True when Feature is supported by this library.
   --
   --  @param Feature Syntax feature to query.
   --  @return True when Compile supports the feature.
   function Supports_Syntax (Feature : Syntax_Feature) return Boolean;

   --  Return a stable image for a syntax feature.
   --
   --  @param Feature Syntax feature to format.
   --  @return Lowercase feature name.
   function Syntax_Feature_Image (Feature : Syntax_Feature) return String;

   --  Inventory supported syntax features.
   --
   --  @param Features Output buffer receiving supported syntax features.
   --  @param Count Number of features written.
   --  @param Complete True when all supported features fit.
   procedure Supported_Syntax
     (Features : out Syntax_Feature_Array;
      Count    : out Natural;
      Complete : out Boolean);

   --  Inventory structured syntax support.
   --
   --  Notes and Examples are shared caller-supplied text buffers. Each support
   --  record contains ranges into these buffers.
   --
   --  @param Support Output buffer receiving support records.
   --  @param Count Number of records written.
   --  @param Complete True when all records and text fit.
   --  @param Notes Output buffer receiving note text.
   --  @param Notes_Last Number of note characters written.
   --  @param Examples Output buffer receiving example text.
   --  @param Examples_Last Number of example characters written.
   procedure Supported_Syntax_Detail
     (Support       : out Syntax_Support_Array;
      Count         : out Natural;
      Complete      : out Boolean;
      Notes         : out String;
      Notes_Last    : out Natural;
      Examples      : out String;
      Examples_Last : out Natural);

   --  Validate that Text is well-formed UTF-8.
   --
   --  @param Text Text to validate.
   --  @return UTF-8 validation result.
   function Validate_UTF_8 (Text : String) return UTF_8_Validation_Result
      with Pre => Text'Last < Positive'Last;

   --  Build a complete character class from already escaped members.
   --
   --  Members can be produced with Append_Class_Literal and Append_Class_Range.
   --
   --  @param Members Character-class members.
   --  @param Negated True to build a negated class.
   --  @param Pattern Output pattern buffer receiving '[' ... ']'.
   --  @param Last Number of pattern characters written.
   --  @param Status Copy status.
   procedure Build_Character_Class
     (Members : String;
      Negated : Boolean;
      Pattern : out String;
      Last    : out Natural;
      Status  : out Copy_Status)
      with Pre => Members'Last < Positive'Last;

   --  Return Pattern with all regexp metacharacters escaped.
   --
   --  This is useful when building a larger regular expression around
   --  user-supplied literal text.
   --
   --  @param Pattern Literal text to escape.
   --  @return Pattern with regexp metacharacters prefixed by '\'.
   function Escape_Literal (Pattern : String) return String
      with Pre => Pattern'Last < Positive'Last;

   --  Append a raw regular-expression fragment to a caller-supplied pattern
   --  buffer.
   --
   --  Use this only for trusted regexp syntax. Use Append_Literal for
   --  user-supplied text.
   --
   --  @param Fragment Raw regexp syntax to append.
   --  @param Pattern Output pattern buffer.
   --  @param Last Number of characters currently written to Pattern.
   --  @param Status Copy_Ok on success, or Copy_Output_Too_Small.
   procedure Append_Fragment
     (Fragment : String;
      Pattern  : in out String;
      Last     : in out Natural;
      Status   : out Copy_Status)
      with Pre => Fragment'Last < Positive'Last;

   --  Append literal text escaped as regular-expression syntax.
   --
   --  @param Literal Literal text to escape and append.
   --  @param Pattern Output pattern buffer.
   --  @param Last Number of characters currently written to Pattern.
   --  @param Status Copy_Ok on success, or Copy_Output_Too_Small.
   procedure Append_Literal
     (Literal : String;
      Pattern : in out String;
      Last    : in out Natural;
      Status  : out Copy_Status)
      with Pre => Literal'Last < Positive'Last;

   --  Append Literal as a branch in a literal alternation.
   --
   --  A '|' separator is inserted when Last is nonzero. The literal branch is
   --  escaped before it is appended.
   --
   --  @param Literal Literal branch text to escape and append.
   --  @param Pattern Output pattern buffer.
   --  @param Last Number of characters currently written to Pattern.
   --  @param Status Copy_Ok on success, or Copy_Output_Too_Small.
   procedure Append_Literal_Alternative
     (Literal : String;
      Pattern : in out String;
      Last    : in out Natural;
      Status  : out Copy_Status)
      with Pre => Literal'Last < Positive'Last;

   --  Append a literal character to a character-class pattern buffer.
   --
   --  This escapes class metacharacters such as '\', ']', '^', and '-'.
   --
   --  @param Literal Character to append as a class member.
   --  @param Pattern Output pattern buffer.
   --  @param Last Number of characters currently written to Pattern.
   --  @param Status Copy_Ok on success, or Copy_Output_Too_Small.
   procedure Append_Class_Literal
     (Literal : Character;
      Pattern : in out String;
      Last    : in out Natural;
      Status  : out Copy_Status);

   --  Append a character range to a character-class pattern buffer.
   --
   --  Invalid descending ranges return Copy_No_Match.
   --
   --  @param First First character in the range.
   --  @param Last_Ch Last character in the range.
   --  @param Pattern Output pattern buffer.
   --  @param Last Number of characters currently written to Pattern.
   --  @param Status Copy_Ok, Copy_No_Match, or Copy_Output_Too_Small.
   procedure Append_Class_Range
     (First  : Character;
      Last_Ch : Character;
      Pattern : in out String;
      Last    : in out Natural;
      Status  : out Copy_Status);

   --  Build an escaped literal alternation from Text ranges.
   --
   --  @param Text Source text containing literal terms.
   --  @param Literals One-based ranges selecting literal terms from Text.
   --  @param Pattern Output pattern buffer.
   --  @param Last Number of characters written to Pattern.
   --  @param Status Copy_Ok, Copy_No_Match for invalid ranges, or
   --         Copy_Output_Too_Small.
   procedure Build_Literal_Alternation
     (Text     : String;
      Literals : Text_Range_Array;
      Pattern  : out String;
      Last     : out Natural;
      Status   : out Copy_Status)
      with Pre => Text'Last < Positive'Last;

   --  Build an escaped whole-word literal alternation from Text ranges.
   --
   --  @param Text Source text containing literal word terms.
   --  @param Literals One-based ranges selecting literal word terms from Text.
   --  @param Pattern Output pattern buffer.
   --  @param Last Number of characters written to Pattern.
   --  @param Status Copy_Ok, Copy_No_Match for empty/invalid ranges, or
   --         Copy_Output_Too_Small.
   procedure Build_Literal_Word_Alternation
     (Text     : String;
      Literals : Text_Range_Array;
      Pattern  : out String;
      Last     : out Natural;
      Status   : out Copy_Status)
      with Pre => Text'Last < Positive'Last;

   --  Test whether Expression is a successfully compiled regular expression.
   --
   --  @param Expression Regular expression value to test.
   --  @return True when Expression can be used for matching.
   function Is_Valid (Expression : Regexp) return Boolean;

   --  Test whether Expression matches anywhere in Text.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Options Matching options.
   --  @return True when Find_First would return Match_Ok.
   function Has_Match
     (Expression : Regexp;
      Text       : String;
      Options    : Match_Options := (others => <>))
      return Boolean
      with Pre => Text'Last < Positive'Last;

   --  Count non-overlapping matches of Expression in Text.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Count Number of matches found.
   --  @param Status Overall count status.
   --  @param Options Matching options.
   procedure Count_Matches
     (Expression : Regexp;
      Text       : String;
      Count      : out Natural;
      Status     : out Find_All_Status;
      Options    : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Find the earliest match from a list of expressions.
   --
   --  Ties are resolved by the lowest expression index.
   --
   --  @param Expressions Compiled expressions to search.
   --  @param Text Text to search.
   --  @param Options Matching options.
   --  @return Pattern index and match result.
   function Find_First_Of
     (Expressions : Regexp_Array;
      Text        : String;
      Options     : Match_Options := (others => <>))
      return Pattern_Match_Result
      with Pre => Text'Last < Positive'Last;

   --  Find the earliest match from a list of expressions at or after From.
   --
   --  @param Expressions Compiled expressions to search.
   --  @param Text Text to search.
   --  @param From One-based starting offset relative to Text'First.
   --  @param Options Matching options.
   --  @return Pattern index and match result.
   function Find_From_Of
     (Expressions : Regexp_Array;
      Text        : String;
      From        : Positive;
      Options     : Match_Options := (others => <>))
      return Pattern_Match_Result
      with Pre => Text'Last < Positive'Last;

   --  Tokenize Text by repeatedly selecting the earliest match from Expressions.
   --
   --  Token kinds are the expression indexes. Too_Many_Matches means Tokens was
   --  too small to store all tokens.
   --
   --  @param Expressions Compiled token expressions in priority order.
   --  @param Text Text to tokenize.
   --  @param Tokens Output buffer receiving token matches.
   --  @param Count Number of tokens written.
   --  @param Status Overall tokenization status.
   --  @param Options Matching options.
   procedure Tokenize
     (Expressions : Regexp_Array;
      Text        : String;
      Tokens      : out Pattern_Match_Array;
      Count       : out Natural;
      Status      : out Find_All_Status;
      Options     : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Tokenize Text with caller-supplied token kinds.
   --
   --  Kinds is indexed like Expressions; missing entries fall back to the
   --  expression index.
   --
   --  @param Expressions Compiled token expressions in priority order.
   --  @param Kinds Token kinds indexed like Expressions.
   --  @param Text Text to tokenize.
   --  @param Tokens Output buffer receiving token matches.
   --  @param Count Number of tokens written.
   --  @param Status Overall tokenization status.
   --  @param Options Matching options.
   procedure Tokenize_With_Kinds
     (Expressions : Regexp_Array;
      Kinds       : Natural_Array;
      Text        : String;
      Tokens      : out Pattern_Match_Array;
      Count       : out Natural;
      Status      : out Find_All_Status;
      Options     : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Find the earliest pattern-set match and capture ranges.
   --
   --  @param Expressions Compiled expressions to search.
   --  @param Text Text to search.
   --  @param Options Matching options.
   --  @return Pattern index, match result, and capture ranges.
   function Find_First_Of_With_Captures
     (Expressions : Regexp_Array;
      Text        : String;
      Options     : Match_Options := (others => <>))
      return Pattern_Match_Captures_Result
      with Pre => Text'Last < Positive'Last;

   --  Find the earliest pattern-set match with captures at or after From.
   --
   --  @param Expressions Compiled expressions to search.
   --  @param Text Text to search.
   --  @param From One-based starting offset relative to Text'First.
   --  @param Options Matching options.
   --  @return Pattern index, match result, and capture ranges.
   function Find_From_Of_With_Captures
     (Expressions : Regexp_Array;
      Text        : String;
      From        : Positive;
      Options     : Match_Options := (others => <>))
      return Pattern_Match_Captures_Result
      with Pre => Text'Last < Positive'Last;

   --  Tokenize Text and capture ranges for each token.
   --
   --  @param Expressions Compiled token expressions in priority order.
   --  @param Kinds Token kinds indexed like Expressions.
   --  @param Text Text to tokenize.
   --  @param Tokens Output buffer receiving captured token matches.
   --  @param Count Number of tokens written.
   --  @param Status Overall tokenization status.
   --  @param Options Matching options.
   procedure Tokenize_With_Captures
     (Expressions : Regexp_Array;
      Kinds       : Natural_Array;
      Text        : String;
      Tokens      : out Pattern_Match_Captures_Array;
      Count       : out Natural;
      Status      : out Find_All_Status;
      Options     : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

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

   --  Find the first match using a deterministic prefix skip when available.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param From One-based starting offset relative to Text'First.
   --  @param Options Matching options.
   --  @return Match result for the earliest match at or after From.
   function Find_From_Planned
     (Expression : Regexp;
      Text       : String;
      From       : Positive := 1;
      Options    : Match_Options := (others => <>))
      return Match_Result
      with Pre => Text'Last < Positive'Last;

   --  Planned find variant that also copies capture ranges.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param From One-based starting offset relative to Text'First.
   --  @param Found Match result.
   --  @param Captures Output buffer receiving capture ranges.
   --  @param Count Number of capture ranges written.
   --  @param Options Matching options.
   procedure Find_From_Planned_With_Captures
     (Expression : Regexp;
      Text       : String;
      From       : Positive;
      Found      : out Match_Result;
      Captures   : out Text_Range_Array;
      Count      : out Natural;
      Options    : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Return the number of capture groups compiled into Expression.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return Number of numbered capture groups, or 0 for invalid expressions.
   function Capture_Count (Expression : Regexp) return Natural;

   --  Test whether Expression contains exported capture groups.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return True when Capture_Count would be greater than zero.
   function Has_Captures (Expression : Regexp) return Boolean;

   --  Test whether Expression contains start or end anchors.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return True when the compiled graph contains '^' or '$' states.
   function Uses_Anchors (Expression : Regexp) return Boolean;

   --  Test whether Expression can match the empty string.
   --
   --  This is a conservative graph inspection over zero-width and control
   --  states; it does not run the matcher.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return True when an epsilon path can reach a match state.
   function May_Match_Empty (Expression : Regexp) return Boolean;

   --  Return a bounded feature summary for Expression.
   --
   --  Invalid expressions return all False fields.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return Feature flags derived from the compiled graph.
   function Features (Expression : Regexp) return Pattern_Features;

   --  Test whether Expression is a pure literal sequence.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return True when the compiled graph contains only literal characters.
   function Is_Literal (Expression : Regexp) return Boolean;

   --  Test whether Expression uses start or end anchors.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return True when the expression contains anchor states.
   function Is_Anchored (Expression : Regexp) return Boolean;

   --  Test whether Expression is suitable for whole-line matching.
   --
   --  This is a structural query for expressions that contain both start and
   --  end anchors. It does not require that anchors were introduced by
   --  Compile_Line.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return True when both start and end anchor states are present.
   function Is_Whole_Line (Expression : Regexp) return Boolean;

   --  Test whether Expression uses features that can require backtracking.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return True for split, backreference, lookaround, or atomic features.
   function Needs_Backtracking (Expression : Regexp) return Boolean;

   --  Test whether Expression is safe for the bounded stream cursor.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return True when Expression is valid and does not depend on lookaround.
   function Can_Stream_Safely (Expression : Regexp) return Boolean;

   --  Return a suggested search strategy for Expression.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return Strategy derived from literal, anchor, and prefix information.
   function Recommended_Strategy (Expression : Regexp) return Search_Strategy;

   --  Return a bounded summary for Expression.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return Summary with size, features, source metadata, and strategy.
   function Summary (Expression : Regexp) return Expression_Summary;

   --  Return a stable bounded fingerprint for Expression.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return Deterministic non-cryptographic fingerprint.
   function Fingerprint (Expression : Regexp) return Pattern_Fingerprint;

   --  Return serialization metadata for Expression.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return Metadata suitable for logs and cache manifests.
   function Metadata (Expression : Regexp) return Pattern_Metadata;

   --  Return the retained source kind for Expression.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return Pattern source provenance.
   function Source_Kind (Expression : Regexp) return Pattern_Source_Kind;

   --  Copy retained source text for Expression.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @param Output Caller-supplied output buffer.
   --  @param Last Number of characters written to Output.
   --  @param Status Copy_Ok, Copy_No_Match, or Copy_Output_Too_Small.
   procedure Copy_Source_Pattern
     (Expression : Regexp;
      Output     : out String;
      Last       : out Natural;
      Status     : out Copy_Status);

   --  Validate Expression against Policy.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @param Policy Feature policy to enforce.
   --  @param Status Policy validation result.
   --  @param Feature Feature summary used for the decision.
   procedure Validate_Policy
     (Expression : Regexp;
      Policy     : Pattern_Policy;
      Status     : out Pattern_Policy_Status;
      Feature    : out Pattern_Features);

   --  Validate Expression against Policy and report the first disallowed feature.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @param Policy Feature policy to enforce.
   --  @return Detailed policy validation result.
   function Validate_Policy_Detail
     (Expression : Regexp;
      Policy     : Pattern_Policy)
      return Pattern_Policy_Diagnostic;

   --  Return a structured diagnostic for a compile result.
   --
   --  @param Result Compile result to classify.
   --  @return Machine-readable diagnostic record.
   function Compile_Diagnostic (Result : Compile_Result) return Compile_Diagnostic_Record;

   --  Return a structured diagnostic for a replacement template.
   --
   --  @param Expression Compiled regular expression used for validation.
   --  @param Replacement Replacement template to validate.
   --  @return Machine-readable replacement diagnostic record.
   function Replacement_Diagnostic
     (Expression  : Regexp;
      Replacement : String)
      return Replacement_Diagnostic_Record
      with Pre => Replacement'Last < Positive'Last;

   --  Copy the deterministic leading literal prefix of Expression.
   --
   --  Last is set to the number of characters written. An expression with no
   --  required literal prefix returns Copy_Ok with Last = 0.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @param Output Caller-supplied prefix buffer.
   --  @param Last Number of characters written to Output.
   --  @param Status Copy_Ok, Copy_No_Match for invalid expressions, or
   --         Copy_Output_Too_Small.
   procedure Required_Prefix
     (Expression : Regexp;
      Output     : out String;
      Last       : out Natural;
      Status     : out Copy_Status);

   --  Return the capture index associated with Name.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @param Name Capture name to look up.
   --  @return One-based capture index, or 0 when Name is absent or invalid.
   function Capture_Index (Expression : Regexp; Name : String) return Natural
      with Pre => Name'Last < Positive'Last;

   --  Collect indexes of captures that have names.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @param Indexes Output buffer receiving one-based capture indexes.
   --  @param Count Number of indexes written.
   --  @param Complete True when all named capture indexes fit.
   procedure Named_Captures
     (Expression : Regexp;
      Indexes    : out Capture_Index_Array;
      Count      : out Natural;
      Complete   : out Boolean);

   --  Copy the capture name associated with Index.
   --
   --  Unnamed captures return Copy_No_Match. Invalid expressions and indexes
   --  outside Capture_Count also return Copy_No_Match.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @param Index One-based capture index.
   --  @param Output Caller-supplied output buffer.
   --  @param Last Number of characters written to Output.
   --  @param Status Copy status.
   procedure Capture_Name
     (Expression : Regexp;
      Index      : Positive;
      Output     : out String;
      Last       : out Natural;
      Status     : out Copy_Status);

   --  Convert a one-based text offset to a one-based line and column.
   --
   --  Offset is relative to Text'First and may be Text'Length + 1 to identify
   --  the end position. LF, CR, and CRLF are line breaks.
   --
   --  @param Text Source text.
   --  @param Offset One-based offset relative to Text'First.
   --  @return Source position for Offset, or (0, 0) when Offset is invalid.
   function Line_Column (Text : String; Offset : Natural) return Source_Position
      with Pre => Text'Last < Positive'Last;

   --  Return the full line range containing Found.
   --
   --  For zero-length matches, Found.First determines the containing line.
   --  The returned range excludes the line break. Invalid or non-matching
   --  results return (0, 0).
   --
   --  @param Text Source text.
   --  @param Found Match result to locate.
   --  @return One-based text range for the containing line.
   function Match_Line_Range (Text : String; Found : Match_Result) return Text_Range
      with Pre => Text'Last < Positive'Last;

   --  Return the length of Found, or 0 for zero-length/non-matches.
   --
   --  @param Found Match result to measure.
   --  @return Number of matched characters.
   function Match_Length (Found : Match_Result) return Natural;

   --  Return True when Offset lies within Found.
   --
   --  @param Found Match result to test.
   --  @param Offset One-based offset relative to the searched text.
   --  @return True when Offset is inside a non-empty match.
   function Contains_Offset (Found : Match_Result; Offset : Natural) return Boolean;

   --  Return range before Found in Text.
   --
   --  @param Text Source text.
   --  @param Found Match result to split around.
   --  @return One-based range before Found, or (0, 0) for non-matches.
   function Before_Match (Text : String; Found : Match_Result) return Text_Range
      with Pre => Text'Last < Positive'Last;

   --  Return range after Found in Text.
   --
   --  @param Text Source text.
   --  @param Found Match result to split around.
   --  @return One-based range after Found, or (0, 0) for non-matches.
   function After_Match (Text : String; Found : Match_Result) return Text_Range
      with Pre => Text'Last < Positive'Last;

   --  Split Text into before/match/after ranges for Found.
   --
   --  Ranges are one-based and relative to Text'First. Zero-length matches
   --  report Match.Last less than Match.First. Invalid or non-matching results
   --  set all ranges to (0, 0) and Status to Copy_No_Match.
   --
   --  @param Text Source text.
   --  @param Found Match result to split around.
   --  @param Before Range before the match.
   --  @param Match Range covered by the match.
   --  @param After Range after the match.
   --  @param Status Copy_Ok or Copy_No_Match.
   procedure Match_Context
     (Text   : String;
      Found  : Match_Result;
      Before : out Text_Range;
      Match  : out Text_Range;
      After  : out Text_Range;
      Status : out Copy_Status)
      with Pre => Text'Last < Positive'Last;

   --  Find the first match and report source-position context.
   --
   --  Position is the line/column of Found.First. Line is the containing line
   --  range. When no match is found, Position is (0, 0) and Line is (0, 0).
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Found Match result.
   --  @param Position Line/column for the match start.
   --  @param Line Full line range containing the match.
   --  @param Options Matching options.
   procedure Find_First_Line
     (Expression : Regexp;
      Text       : String;
      Found      : out Match_Result;
      Position   : out Source_Position;
      Line       : out Text_Range;
      Options    : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Copy a one-based text range into Output.
   --
   --  Empty ranges copy no characters and return Copy_Ok. Invalid ranges
   --  return Copy_No_Match.
   --
   --  @param Text Source text.
   --  @param Span Range to copy.
   --  @param Output Caller-supplied output buffer.
   --  @param Last Number of characters written to Output.
   --  @param Status Copy status.
   procedure Copy_Range
     (Text   : String;
      Span   : Text_Range;
      Output : out String;
      Last   : out Natural;
      Status : out Copy_Status)
      with Pre => Text'Last < Positive'Last;

   --  Copy the text before Found.
   --
   --  @param Text Source text.
   --  @param Found Match result to split around.
   --  @param Output Caller-supplied output buffer.
   --  @param Last Number of characters written to Output.
   --  @param Status Copy status.
   procedure Copy_Before
     (Text   : String;
      Found  : Match_Result;
      Output : out String;
      Last   : out Natural;
      Status : out Copy_Status)
      with Pre => Text'Last < Positive'Last;

   --  Copy the text after Found.
   --
   --  @param Text Source text.
   --  @param Found Match result to split around.
   --  @param Output Caller-supplied output buffer.
   --  @param Last Number of characters written to Output.
   --  @param Status Copy status.
   procedure Copy_After
     (Text   : String;
      Found  : Match_Result;
      Output : out String;
      Last   : out Natural;
      Status : out Copy_Status)
      with Pre => Text'Last < Positive'Last;

   --  Copy the full line containing Found, excluding the line break.
   --
   --  @param Text Source text.
   --  @param Found Match result to locate.
   --  @param Output Caller-supplied output buffer.
   --  @param Last Number of characters written to Output.
   --  @param Status Copy status.
   procedure Copy_Match_Line
     (Text   : String;
      Found  : Match_Result;
      Output : out String;
      Last   : out Natural;
      Status : out Copy_Status)
      with Pre => Text'Last < Positive'Last;

   --  Copy a numbered capture range from Captures.
   --
   --  @param Text Text that produced Captures.
   --  @param Captures Capture ranges returned by a capture-aware match.
   --  @param Index One-based capture index to copy.
   --  @param Output Caller-supplied output buffer.
   --  @param Last Number of characters written to Output.
   --  @param Status Copy status.
   procedure Copy_Capture
     (Text     : String;
      Captures : Text_Range_Array;
      Index    : Positive;
      Output   : out String;
      Last     : out Natural;
      Status   : out Copy_Status)
      with Pre => Text'Last < Positive'Last;

   --  Copy a named capture range from Captures.
   --
   --  @param Expression Compiled expression that defines capture names.
   --  @param Text Text that produced Captures.
   --  @param Captures Capture ranges returned by a capture-aware match.
   --  @param Name Capture name to copy.
   --  @param Output Caller-supplied output buffer.
   --  @param Last Number of characters written to Output.
   --  @param Status Copy status.
   procedure Copy_Named_Capture
     (Expression : Regexp;
      Text       : String;
      Captures   : Text_Range_Array;
      Name       : String;
      Output     : out String;
      Last       : out Natural;
      Status     : out Copy_Status)
      with Pre => Text'Last < Positive'Last
                  and then Name'Last < Positive'Last;

   --  Return a named capture range from Captures.
   --
   --  @param Expression Compiled expression that defines capture names.
   --  @param Captures Capture ranges returned by a capture-aware match.
   --  @param Name Capture name to look up.
   --  @return Matching capture range, or (0, 0) when absent.
   function Named_Capture_Range
     (Expression : Regexp;
      Captures   : Text_Range_Array;
      Name       : String)
      return Text_Range
      with Pre => Name'Last < Positive'Last;

   --  Validate replacement syntax against Expression.
   --
   --  Checks numbered and named capture references, malformed \k<name>,
   --  unknown escapes, dangling '\' escapes, and unterminated \U or \L spans.
   --
   --  @param Expression Compiled expression whose captures are referenced.
   --  @param Replacement Replacement template to validate.
   --  @param Status Validation status.
   --  @param Error_Offset One-based replacement offset for the error, or 0.
   procedure Validate_Replacement
     (Expression    : Regexp;
      Replacement   : String;
      Status        : out Replacement_Validation_Status;
      Error_Offset  : out Natural)
      with Pre => Replacement'Last < Positive'Last;

   --  Validate replacement syntax and return detailed information.
   --
   --  @param Expression Compiled expression whose captures are referenced.
   --  @param Replacement Replacement template to validate.
   --  @return Validation status, error offset, capture index, and name range.
   function Validate_Replacement_Detail
     (Expression  : Regexp;
      Replacement : String)
      return Replacement_Validation_Result
      with Pre => Replacement'Last < Positive'Last;

   --  Validate replacement syntax and collect capture references.
   --
   --  References to \0, \1 through \9, and \k<name> are written into
   --  References until the caller-supplied buffer fills. Complete is False
   --  when more valid references exist than the buffer can hold.
   --
   --  @param Expression Compiled expression whose captures are referenced.
   --  @param Replacement Replacement template to scan.
   --  @param References Output buffer receiving replacement references.
   --  @param Count Number of references written.
   --  @param Result Validation detail for the replacement.
   --  @param Complete True when all references were written.
   procedure Replacement_References
     (Expression  : Regexp;
      Replacement : String;
      References  : out Replacement_Reference_Array;
      Count       : out Natural;
      Result      : out Replacement_Validation_Result;
      Complete    : out Boolean)
      with Pre => Replacement'Last < Positive'Last;

   --  Validate replacement syntax and summarize replacement features.
   --
   --  @param Expression Compiled expression whose captures are referenced.
   --  @param Replacement Replacement template to scan.
   --  @param References Optional output buffer receiving references.
   --  @param Summary Replacement feature summary.
   procedure Replacement_Summary
     (Expression  : Regexp;
      Replacement : String;
      References  : out Replacement_Reference_Array;
      Summary     : out Replacement_Features)
      with Pre => Replacement'Last < Positive'Last;

   --  Escape replacement text so it is inserted literally.
   --
   --  @param Replacement Literal replacement text.
   --  @return Replacement with '\' escaped.
   function Escape_Replacement (Replacement : String) return String
      with Pre => Replacement'Last < Positive'Last;

   --  Measure Replace_First and return only the required output length.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Replacement Replacement text.
   --  @param Required_Length Required output length.
   --  @param Status Replacement status.
   --  @param Options Matching options.
   procedure Required_First_Output_Length
     (Expression      : Regexp;
      Text            : String;
      Replacement     : String;
      Required_Length : out Natural;
      Status          : out Replace_Status;
      Options         : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Measure Replace_All and return only the required output length.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Replacement Replacement text.
   --  @param Required_Length Required output length.
   --  @param Status Replacement status.
   --  @param Options Matching options.
   procedure Required_All_Output_Length
     (Expression      : Regexp;
      Text            : String;
      Replacement     : String;
      Required_Length : out Natural;
      Status          : out Replace_Status;
      Options         : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Test whether Replace_All output fits Output_Length bytes.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Replacement Replacement text.
   --  @param Output_Length Available output length.
   --  @param Fits True when required output length is not larger.
   --  @param Status Replacement status.
   --  @param Options Matching options.
   procedure Replacement_Fits
     (Expression    : Regexp;
      Text          : String;
      Replacement   : String;
      Output_Length : Natural;
      Fits          : out Boolean;
      Status        : out Replace_Status;
      Options       : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Find the first match and copy numbered capture ranges.
   --
   --  Captures are written into the caller-supplied Captures array. Count is
   --  the number of groups written, limited by both Capture_Count (Expression)
   --  and Captures'Length. Unmatched optional captures are reported as
   --  (First => 0, Last => 0). Capture offsets are one-based and relative to
   --  Text'First, like Match_Result offsets.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Found Overall match result.
   --  @param Captures Output buffer receiving capture ranges.
   --  @param Count Number of capture ranges written.
   --  @param Options Matching options.
   procedure Find_First_With_Captures
     (Expression : Regexp;
      Text       : String;
      Found      : out Match_Result;
      Captures   : out Text_Range_Array;
      Count      : out Natural;
      Options    : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Find the first match at or after From and copy numbered capture ranges.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param From One-based starting offset relative to Text'First.
   --  @param Found Overall match result.
   --  @param Captures Output buffer receiving capture ranges.
   --  @param Count Number of capture ranges written.
   --  @param Options Matching options.
   procedure Find_From_With_Captures
     (Expression : Regexp;
      Text       : String;
      From       : Positive;
      Found      : out Match_Result;
      Captures   : out Text_Range_Array;
      Count      : out Natural;
      Options    : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Find every non-overlapping match of Expression in Text.
   --
   --  Matches are written into the caller-supplied Matches array. Count is the
   --  number of array elements written. Zero-length matches are advanced by one
   --  input position before searching for the next match, so callers do not
   --  need to special-case anchors or optional expressions.
   --
   --  Options.Max_Steps applies to the entire scan. Each stored match reports
   --  the steps consumed by the individual search that found that match.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Matches Output buffer receiving non-overlapping matches.
   --  @param Count Number of matches written to Matches.
   --  @param Status Overall collection status.
   --  @param Options Matching options.
   procedure Find_All
     (Expression : Regexp;
      Text       : String;
      Matches    : out Match_Result_Array;
      Count      : out Natural;
      Status     : out Find_All_Status;
      Options    : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Find every non-overlapping match of Expression in Text starting at From.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param From One-based starting offset relative to Text'First.
   --  @param Matches Output buffer receiving non-overlapping matches.
   --  @param Count Number of matches written to Matches.
   --  @param Status Overall collection status.
   --  @param Options Matching options.
   procedure Find_All_From
     (Expression : Regexp;
      Text       : String;
      From       : Positive;
      Matches    : out Match_Result_Array;
      Count      : out Natural;
      Status     : out Find_All_Status;
      Options    : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Find every non-overlapping match and copy capture ranges for each match.
   --
   --  Captures is indexed as (match slot, capture slot). Count is the number
   --  of matches written. Capture_Count is the number of capture columns used
   --  per match, limited by Expression and Captures' second dimension.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Matches Output buffer receiving non-overlapping matches.
   --  @param Captures Output matrix receiving capture ranges.
   --  @param Count Number of matches written.
   --  @param Capture_Count Number of capture columns used.
   --  @param Status Overall collection status.
   --  @param Options Matching options.
   procedure Find_All_With_Captures
     (Expression    : Regexp;
      Text          : String;
      Matches       : out Match_Result_Array;
      Captures      : out Capture_Result_Array;
      Count         : out Natural;
      Capture_Count : out Natural;
      Status        : out Find_All_Status;
      Options       : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Find every non-overlapping match with captures starting at From.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param From One-based starting offset relative to Text'First.
   --  @param Matches Output buffer receiving non-overlapping matches.
   --  @param Captures Output matrix receiving capture ranges.
   --  @param Count Number of matches written.
   --  @param Capture_Count Number of capture columns used.
   --  @param Status Overall collection status.
   --  @param Options Matching options.
   procedure Find_All_With_Captures_From
     (Expression    : Regexp;
      Text          : String;
      From          : Positive;
      Matches       : out Match_Result_Array;
      Captures      : out Capture_Result_Array;
      Count         : out Natural;
      Capture_Count : out Natural;
      Status        : out Find_All_Status;
      Options       : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Find every overlapping match of Expression in Text.
   --
   --  After each non-empty match, the next search begins one character after
   --  the previous match start rather than after the previous match end.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Matches Output buffer receiving overlapping matches.
   --  @param Count Number of matches written to Matches.
   --  @param Status Overall collection status.
   --  @param Options Matching options.
   procedure Find_All_Overlapping
     (Expression : Regexp;
      Text       : String;
      Matches    : out Match_Result_Array;
      Count      : out Natural;
      Status     : out Find_All_Status;
      Options    : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Find every overlapping match starting at From.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param From One-based starting offset relative to Text'First.
   --  @param Matches Output buffer receiving overlapping matches.
   --  @param Count Number of matches written to Matches.
   --  @param Status Overall collection status.
   --  @param Options Matching options.
   procedure Find_All_Overlapping_From
     (Expression : Regexp;
      Text       : String;
      From       : Positive;
      Matches    : out Match_Result_Array;
      Count      : out Natural;
      Status     : out Find_All_Status;
      Options    : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Find every overlapping match and copy capture ranges for each match.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Matches Output buffer receiving overlapping matches.
   --  @param Captures Output matrix receiving capture ranges.
   --  @param Count Number of matches written.
   --  @param Capture_Count Number of capture columns used.
   --  @param Status Overall collection status.
   --  @param Options Matching options.
   procedure Find_All_Overlapping_With_Captures
     (Expression    : Regexp;
      Text          : String;
      Matches       : out Match_Result_Array;
      Captures      : out Capture_Result_Array;
      Count         : out Natural;
      Capture_Count : out Natural;
      Status        : out Find_All_Status;
      Options       : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Find every overlapping match with captures starting at From.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param From One-based starting offset relative to Text'First.
   --  @param Matches Output buffer receiving overlapping matches.
   --  @param Captures Output matrix receiving capture ranges.
   --  @param Count Number of matches written.
   --  @param Capture_Count Number of capture columns used.
   --  @param Status Overall collection status.
   --  @param Options Matching options.
   procedure Find_All_Overlapping_With_Captures_From
     (Expression    : Regexp;
      Text          : String;
      From          : Positive;
      Matches       : out Match_Result_Array;
      Captures      : out Capture_Result_Array;
      Count         : out Natural;
      Capture_Count : out Natural;
      Status        : out Find_All_Status;
      Options       : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Find all non-overlapping matches and collect containing line ranges.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Lines Output buffer receiving containing line ranges.
   --  @param Count Number of line ranges written.
   --  @param Status Overall collection status.
   --  @param Options Matching options.
   procedure Find_All_Lines
     (Expression : Regexp;
      Text       : String;
      Lines      : out Text_Range_Array;
      Count      : out Natural;
      Status     : out Find_All_Status;
      Options    : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Collect containing line ranges for matches that Replace_All would edit.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Lines Output buffer receiving containing line ranges.
   --  @param Count Number of line ranges written.
   --  @param Status Overall collection status.
   --  @param Options Matching options.
   procedure Replace_All_Lines
     (Expression : Regexp;
      Text       : String;
      Lines      : out Text_Range_Array;
      Count      : out Natural;
      Status     : out Find_All_Status;
      Options    : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Preview source ranges that Replace_All would copy or replace.
   --
   --  The plan alternates copied source ranges and replacement ranges. The
   --  replacement template is validated but not expanded.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Replacement Replacement template to validate.
   --  @param Edits Output buffer receiving planned edits.
   --  @param Count Number of edits written.
   --  @param Status Replacement planning status.
   --  @param Complete True when all edits fit in Edits.
   --  @param Options Matching options.
   procedure Plan_Replacement
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Edits       : out Replacement_Edit_Array;
      Count       : out Natural;
      Status      : out Replace_Status;
      Complete    : out Boolean;
      Options     : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last and then Replacement'Last < Positive'Last;

   --  Preview replacement edits, references, and source-to-output mapping.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Replacement Replacement template to validate.
   --  @param Edits Output buffer receiving planned edits.
   --  @param References Output buffer receiving replacement references.
   --  @param Maps Output buffer receiving source-to-output mapping.
   --  @param Plan Overall plan result.
   --  @param Options Matching options.
   procedure Plan_Replacement_Detail
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Edits       : out Replacement_Edit_Array;
      References  : out Replacement_Reference_Array;
      Maps        : out Replacement_Output_Map_Array;
      Plan        : out Replacement_Plan;
      Options     : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last and then Replacement'Last < Positive'Last;

   --  Collect containing line ranges for split parts.
   --
   --  @param Expression Compiled regular expression to split around.
   --  @param Text Text to split.
   --  @param Lines Output buffer receiving containing line ranges.
   --  @param Count Number of line ranges written.
   --  @param Status Split status.
   --  @param Options Matching options.
   procedure Split_Lines
     (Expression : Regexp;
      Text       : String;
      Lines      : out Text_Range_Array;
      Count      : out Natural;
      Status     : out Split_Status;
      Options    : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Count all matches and report first/last matches without storing all.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Options Matching options.
   --  @return Match count, first/last matches, total steps, and status.
   function Find_All_Summary
     (Expression : Regexp;
      Text       : String;
      Options    : Match_Options := (others => <>))
      return Find_All_Summary_Result
      with Pre => Text'Last < Positive'Last;

   --  Count all matches and report first/last source line information.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Options Matching options.
   --  @return Match count, first/last line positions, total steps, and status.
   function Find_All_Line_Summary
     (Expression : Regexp;
      Text       : String;
      Options    : Match_Options := (others => <>))
      return Find_All_Line_Summary_Result
      with Pre => Text'Last < Positive'Last;

   --  Cursor for incremental non-overlapping matching.
   type Match_Cursor is private;

   --  Cursor for bounded chunked stream matching.
   type Stream_Cursor is private;

   --  Cursor for bounded chunked tokenization.
   type Token_Stream_Cursor is private;

   --  Initialize Cursor for incremental matching of Expression.
   --
   --  @param Cursor Cursor value to initialize.
   --  @param Expression Compiled regular expression to run.
   --  @param From One-based starting offset relative to Text'First.
   --  @param Options Matching options.
   procedure Start
     (Cursor     : out Match_Cursor;
      Expression : Regexp;
      From       : Positive := 1;
      Options    : Match_Options := (others => <>));

   --  Return the next match from Cursor in Text.
   --
   --  @param Cursor Cursor to advance.
   --  @param Text Text to search.
   --  @param Found Match result for the next match, or a failure status.
   procedure Next
     (Cursor : in out Match_Cursor;
      Text   : String;
      Found  : out Match_Result);

   --  Return the next match from Cursor and copy numbered capture ranges.
   --
   --  Captures and Count have the same meaning as Find_First_With_Captures.
   --
   --  @param Cursor Cursor to advance.
   --  @param Text Text to search.
   --  @param Found Match result for the next match, or a failure status.
   --  @param Captures Output buffer receiving capture ranges.
   --  @param Count Number of capture ranges written.
   procedure Next_With_Captures
     (Cursor   : in out Match_Cursor;
      Text     : String;
      Found    : out Match_Result;
      Captures : out Text_Range_Array;
      Count    : out Natural);

   --  Return the next match and captures as one bounded record.
   --
   --  @param Cursor Cursor to advance.
   --  @param Text Text to search.
   --  @param Result Match and capture ranges.
   procedure Next_Captured
     (Cursor : in out Match_Cursor;
      Text   : String;
      Result : out Captured_Match_Result);

   --  Return the next match, captures, and containing source line.
   --
   --  @param Cursor Cursor to advance.
   --  @param Text Text to search.
   --  @param Result Match, captures, position, and line range.
   procedure Next_Line_Captured
     (Cursor : in out Match_Cursor;
      Text   : String;
      Result : out Line_Captured_Match_Result)
      with Pre => Text'Last < Positive'Last;

   --  Initialize a bounded streaming token cursor.
   --
   --  @param Cursor Cursor value to initialize.
   --  @param Options Matching options.
   procedure Start_Token_Stream
     (Cursor : out Token_Stream_Cursor;
      Options : Match_Options := (others => <>));

   --  Feed one chunk and collect tokens with stream-relative offsets.
   --
   --  @param Cursor Token stream cursor to advance.
   --  @param Expressions Compiled token expressions in priority order.
   --  @param Kinds Token kinds indexed like Expressions.
   --  @param Chunk Text chunk to append.
   --  @param Is_Final True when this is the last chunk.
   --  @param Tokens Output buffer receiving stream-relative token matches.
   --  @param Count Number of tokens written.
   --  @param Status Overall tokenization status.
   procedure Feed_Tokens
     (Cursor      : in out Token_Stream_Cursor;
      Expressions : Regexp_Array;
      Kinds       : Natural_Array;
      Chunk       : String;
      Is_Final    : Boolean;
      Tokens      : out Pattern_Match_Array;
      Count       : out Natural;
      Status      : out Find_All_Status)
      with Pre => Chunk'Last < Positive'Last;

   --  Feed one chunk and return detailed token-stream status.
   --
   --  @param Cursor Token stream cursor to advance.
   --  @param Expressions Compiled token expressions in priority order.
   --  @param Kinds Token kinds indexed like Expressions.
   --  @param Chunk Text chunk to append.
   --  @param Is_Final True when this is the last chunk.
   --  @param Tokens Output buffer receiving stream-relative token matches.
   --  @param Count Number of tokens written.
   --  @param Status Detailed token stream status.
   procedure Feed_Tokens_Detail
     (Cursor      : in out Token_Stream_Cursor;
      Expressions : Regexp_Array;
      Kinds       : Natural_Array;
      Chunk       : String;
      Is_Final    : Boolean;
      Tokens      : out Pattern_Match_Array;
      Count       : out Natural;
      Status      : out Token_Stream_Status)
      with Pre => Chunk'Last < Positive'Last;

   --  Feed one chunk and collect captured token matches.
   --
   --  @param Cursor Token stream cursor to advance.
   --  @param Expressions Compiled token expressions in priority order.
   --  @param Kinds Token kinds indexed like Expressions.
   --  @param Chunk Text chunk to append.
   --  @param Is_Final True when this is the last chunk.
   --  @param Tokens Output buffer receiving captured token matches.
   --  @param Count Number of tokens written.
   --  @param Status Detailed token stream status.
   procedure Feed_Tokens_With_Captures
     (Cursor      : in out Token_Stream_Cursor;
      Expressions : Regexp_Array;
      Kinds       : Natural_Array;
      Chunk       : String;
      Is_Final    : Boolean;
      Tokens      : out Pattern_Match_Captures_Array;
      Count       : out Natural;
      Status      : out Token_Stream_Status)
      with Pre => Chunk'Last < Positive'Last;

   --  Initialize Cursor for chunked stream matching of Expression.
   --
   --  Stream matches report one-based offsets relative to the start of the
   --  stream, not relative to the current chunk. Feed retains unmatched data so
   --  matches can span chunk boundaries. If the retained data reaches
   --  Default_Stream_Buffer_Length before a complete match is available, Feed
   --  returns Stream_Buffer_Full.
   --
   --  @param Cursor Stream cursor value to initialize.
   --  @param Expression Compiled regular expression to run.
   --  @param Options Matching options.
   procedure Start_Stream
     (Cursor     : out Stream_Cursor;
      Expression : Regexp;
      Options    : Match_Options := (others => <>));

   --  Initialize Cursor with a caller-selected retained-buffer limit.
   --
   --  Max_Buffer_Length must not exceed Default_Stream_Buffer_Length. Smaller
   --  values let callers fail earlier with Stream_Buffer_Full when retaining
   --  more data would be undesirable.
   --
   --  @param Cursor Stream cursor value to initialize.
   --  @param Expression Compiled regular expression to run.
   --  @param Max_Buffer_Length Maximum retained bytes for this cursor.
   --  @param Options Matching options.
   procedure Start_Stream
     (Cursor            : out Stream_Cursor;
      Expression        : Regexp;
      Max_Buffer_Length : Positive;
      Options           : Match_Options := (others => <>))
      with Pre => Max_Buffer_Length <= Default_Stream_Buffer_Length;

   --  Feed one chunk into Cursor and return the next complete match if present.
   --
   --  Pass Is_Final as True for the last chunk. Greedy matches that end at the
   --  current buffer edge are held until another chunk arrives or Is_Final is
   --  True, because additional input may extend the match. After Stream_Match,
   --  call Feed again with an empty Chunk to drain additional buffered matches.
   --
   --  @param Cursor Stream cursor to advance.
   --  @param Chunk Next stream bytes, or an empty string to drain the buffer.
   --  @param Is_Final True when no more chunks will be supplied.
   --  @param Found Match result using one-based stream offsets.
   --  @param Status Streaming status.
   procedure Feed
     (Cursor   : in out Stream_Cursor;
      Chunk    : String;
      Is_Final : Boolean;
      Found    : out Match_Result;
      Status   : out Stream_Status)
      with Pre => Chunk'Last < Positive'Last;

   --  Feed one chunk and copy capture ranges for a returned stream match.
   --
   --  Capture offsets are one-based stream offsets, like Found. Unmatched
   --  optional captures report (0, 0).
   --
   --  @param Cursor Stream cursor to advance.
   --  @param Chunk Next stream bytes, or an empty string to drain the buffer.
   --  @param Is_Final True when no more chunks will be supplied.
   --  @param Found Match result using one-based stream offsets.
   --  @param Captures Output buffer receiving capture ranges.
   --  @param Count Number of capture ranges written.
   --  @param Status Streaming status.
   procedure Feed_With_Captures
     (Cursor   : in out Stream_Cursor;
      Chunk    : String;
      Is_Final : Boolean;
      Found    : out Match_Result;
      Captures : out Text_Range_Array;
      Count    : out Natural;
      Status   : out Stream_Status)
      with Pre => Chunk'Last < Positive'Last;

   --  Replace the first non-overlapping match in Text.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Replacement Replacement text.
   --  @param Output Output buffer receiving replaced text.
   --  @param Last Number of output characters written.
   --  @param Status Replacement status.
   --  @param Options Matching options.
   procedure Replace_First
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Output      : out String;
      Last        : out Natural;
      Status      : out Replace_Status;
      Options     : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Replace the first non-overlapping match and report replacements made.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Replacement Replacement text.
   --  @param Output Output buffer receiving replaced text.
   --  @param Last Number of output characters written.
   --  @param Status Replacement status.
   --  @param Count Number of replacements made.
   --  @param Options Matching options.
   procedure Replace_First_Count
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Output      : out String;
      Last        : out Natural;
      Status      : out Replace_Status;
      Count       : out Natural;
      Options     : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Replace every non-overlapping match in Text.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Replacement Replacement text.
   --  @param Output Output buffer receiving replaced text.
   --  @param Last Number of output characters written.
   --  @param Status Replacement status.
   --  @param Options Matching options.
   procedure Replace_All
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Output      : out String;
      Last        : out Natural;
      Status      : out Replace_Status;
      Options     : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Replace every non-overlapping match and report replacements made.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Replacement Replacement text.
   --  @param Output Output buffer receiving replaced text.
   --  @param Last Number of output characters written.
   --  @param Status Replacement status.
   --  @param Count Number of replacements made.
   --  @param Options Matching options.
   procedure Replace_All_Count
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Output      : out String;
      Last        : out Natural;
      Status      : out Replace_Status;
      Count       : out Natural;
      Options     : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Measure Replace_First output length without writing replacement text.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Replacement Replacement text.
   --  @param Required_Length Required output length for the replacement.
   --  @param Status Replacement status.
   --  @param Count Number of replacements that would be made.
   --  @param Options Matching options.
   procedure Replace_First_Size
     (Expression      : Regexp;
      Text            : String;
      Replacement     : String;
      Required_Length : out Natural;
      Status          : out Replace_Status;
      Count           : out Natural;
      Options         : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Measure Replace_All output length without writing replacement text.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Replacement Replacement text.
   --  @param Required_Length Required output length for the replacement.
   --  @param Status Replacement status.
   --  @param Count Number of replacements that would be made.
   --  @param Options Matching options.
   procedure Replace_All_Size
     (Expression      : Regexp;
      Text            : String;
      Replacement     : String;
      Required_Length : out Natural;
      Status          : out Replace_Status;
      Count           : out Natural;
      Options         : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Replace the first match, adapting replacement letter case to the match.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Replacement Replacement text.
   --  @param Output Output buffer receiving replaced text.
   --  @param Last Number of output characters written.
   --  @param Status Replacement status.
   --  @param Options Matching options.
   procedure Replace_First_Preserving_Case
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Output      : out String;
      Last        : out Natural;
      Status      : out Replace_Status;
      Options     : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Replace every match, adapting replacement letter case to each match.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to search.
   --  @param Replacement Replacement text.
   --  @param Output Output buffer receiving replaced text.
   --  @param Last Number of output characters written.
   --  @param Status Replacement status.
   --  @param Options Matching options.
   procedure Replace_All_Preserving_Case
     (Expression  : Regexp;
      Text        : String;
      Replacement : String;
      Output      : out String;
      Last        : out Natural;
      Status      : out Replace_Status;
      Options     : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Split Text around non-overlapping matches of Expression.
   --
   --  @param Expression Compiled regular expression to run.
   --  @param Text Text to split.
   --  @param Parts Output buffer receiving non-matching text ranges.
   --  @param Count Number of ranges written to Parts.
   --  @param Status Split status.
   --  @param Options Matching options.
   procedure Split
     (Expression : Regexp;
      Text       : String;
      Parts      : out Text_Range_Array;
      Count      : out Natural;
      Status     : out Split_Status;
      Options    : Match_Options := (others => <>))
      with Pre => Text'Last < Positive'Last;

   --  Copy the text covered by Found into Output.
   --
   --  @param Text Text that produced Found.
   --  @param Found Match result to copy.
   --  @param Output Output buffer receiving match text.
   --  @param Last Number of output characters written.
   --  @param Status Copy status.
   procedure Copy_Match
     (Text   : String;
      Found  : Match_Result;
      Output : out String;
      Last   : out Natural;
      Status : out Copy_Status)
      with Pre => Text'Last < Positive'Last;

   --  Write a deterministic diagnostic dump of Expression into Output.
   --
   --  This is intended for tooling, tests, and maintainers. The format is
   --  stable enough for diagnostics but is not a pattern serialization format.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @param Output Output buffer receiving diagnostic text.
   --  @param Last Number of output characters written.
   --  @param Status Copy_Ok, Copy_No_Match for invalid expressions, or
   --         Copy_Output_Too_Small when Output cannot hold the dump.
   procedure Debug_Dump
     (Expression : Regexp;
      Output     : out String;
      Last       : out Natural;
      Status     : out Copy_Status);

   --  Write a compact human-readable explanation of Expression into Output.
   --
   --  The explanation summarizes compiled graph size, feature flags, capture
   --  names, and deterministic literal prefix. It does not reconstruct source
   --  syntax.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @param Output Output buffer receiving explanation text.
   --  @param Last Number of output characters written.
   --  @param Status Copy_Ok, Copy_No_Match for invalid expressions, or
   --         Copy_Output_Too_Small when Output cannot hold the explanation.
   procedure Explain
     (Expression : Regexp;
      Output     : out String;
      Last       : out Natural;
      Status     : out Copy_Status);

   --  Copy structured compiled node summaries into Nodes.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @param Nodes Output buffer receiving node summaries.
   --  @param Count Number of nodes written.
   --  @param Complete True when all nodes fit.
   procedure Explain_Nodes
     (Expression : Regexp;
      Nodes      : out Expression_Node_Array;
      Count      : out Natural;
      Complete   : out Boolean);

   --  Return the built-in benchmark pattern for Case_Id.
   --
   --  @param Case_Id Benchmark case.
   --  @return Regular-expression pattern for the case.
   function Benchmark_Pattern (Case_Id : Benchmark_Case) return String;

   --  Return sample text for a built-in benchmark case.
   --
   --  @param Case_Id Benchmark case.
   --  @return Representative input text for the case.
   function Benchmark_Text (Case_Id : Benchmark_Case) return String;

   --  Run a built-in benchmark case and return the match summary.
   --
   --  @param Case_Id Benchmark case.
   --  @param Options Matching options.
   --  @return Match summary for the built-in case.
   function Benchmark_Summary
     (Case_Id : Benchmark_Case;
      Options : Match_Options := (others => <>))
      return Find_All_Summary_Result;

   --  Copy the name for Token_Kind from Names.
   --
   --  @param Names Token names to search.
   --  @param Token_Kind Token kind to look up.
   --  @param Output Output buffer receiving the name.
   --  @param Last Number of output characters written.
   --  @param Status Copy status.
   procedure Copy_Token_Name
     (Names      : Token_Name_Array;
      Token_Kind : Natural;
      Output     : out String;
      Last       : out Natural;
      Status     : out Copy_Status);

   --  Build a bounded token-name record.
   --
   --  @param Token_Kind Token kind associated with Name.
   --  @param Name Token name text.
   --  @param Result Output token-name record.
   --  @param Status Copy status.
   procedure Make_Token_Name
     (Token_Kind : Natural;
      Name       : String;
      Result     : out Token_Name;
      Status     : out Copy_Status)
      with Pre => Name'Last < Positive'Last;

   --  Write a compile diagnostic with source text and a caret.
   --
   --  @param Pattern Pattern that produced Result.
   --  @param Result Compile result to format.
   --  @param Output Output buffer receiving diagnostic text.
   --  @param Last Number of output characters written.
   --  @param Status Copy status.
   procedure Format_Compile_Diagnostic
     (Pattern : String;
      Result  : Compile_Result;
      Output  : out String;
      Last    : out Natural;
      Status  : out Copy_Status)
      with Pre => Pattern'Last < Positive'Last;

   --  Write a replacement diagnostic with source text and a caret.
   --
   --  @param Expression Compiled expression whose captures are referenced.
   --  @param Replacement Replacement template to validate and format.
   --  @param Output Output buffer receiving diagnostic text.
   --  @param Last Number of output characters written.
   --  @param Status Copy status.
   procedure Format_Replacement_Diagnostic
     (Expression  : Regexp;
      Replacement : String;
      Output      : out String;
      Last        : out Natural;
      Status      : out Copy_Status)
      with Pre => Replacement'Last < Positive'Last;

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

   --  Return lint flags for Expression and retained source text.
   --
   --  @param Expression Compiled regular expression to inspect.
   --  @return Bounded lint flags.
   function Lint (Expression : Regexp) return Pattern_Lint;

   --  Test whether Status is a compile syntax error.
   --
   --  @param Status Compile status to classify.
   --  @return True for syntax errors and unsupported syntax.
   function Is_Syntax_Error (Status : Compile_Status) return Boolean;

   --  Test whether Status reports unsupported syntax.
   --
   --  @param Status Compile status to classify.
   --  @return True when Status is Unsupported_Syntax.
   function Is_Unsupported (Status : Compile_Status) return Boolean;

   --  Test whether Status is caused by a configured compile limit.
   --
   --  @param Status Compile status to classify.
   --  @return True for Pattern_Too_Long, Too_Many_States, or Too_Many_Captures.
   function Is_Limit_Error (Status : Compile_Status) return Boolean;

   --  Test whether Status is caused by a match step limit.
   --
   --  @param Status Match status to classify.
   --  @return True when Status is Match_Limit_Exceeded.
   function Is_Limit_Error (Status : Match_Status) return Boolean;

   --  Test whether Status is caused by a find-all step limit.
   --
   --  @param Status Find_All status to classify.
   --  @return True when Status is Find_All_Limit_Exceeded.
   function Is_Limit_Error (Status : Find_All_Status) return Boolean;

   --  Test whether Status is caused by a replacement step limit.
   --
   --  @param Status Replacement status to classify.
   --  @return True when Status is Replace_Limit_Exceeded.
   function Is_Limit_Error (Status : Replace_Status) return Boolean;

   --  Test whether Status is caused by a split step limit.
   --
   --  @param Status Split status to classify.
   --  @return True when Status is Split_Limit_Exceeded.
   function Is_Limit_Error (Status : Split_Status) return Boolean;

   --  Test whether Status is caused by a stream step or buffer limit.
   --
   --  @param Status Stream status to classify.
   --  @return True for Stream_Limit_Exceeded or Stream_Buffer_Full.
   function Is_Limit_Error (Status : Stream_Status) return Boolean;

   --  Return an image for a compile status.
   --
   --  @param Status Compile status to format.
   --  @return Human-readable status name.
   function Status_Image (Status : Compile_Status) return String;

   --  Return a diagnostic image for a compile result.
   --
   --  @param Result Compile result to format.
   --  @return Human-readable diagnostic with status and offset.
   function Diagnostic_Image (Result : Compile_Result) return String;

   --  Return an image for a match status.
   --
   --  @param Status Match status to format.
   --  @return Human-readable status name.
   function Status_Image (Status : Match_Status) return String;

   --  Return an image for a Find_All status.
   --
   --  @param Status Find_All status to format.
   --  @return Human-readable status name.
   function Status_Image (Status : Find_All_Status) return String;

   --  Return an image for a replacement status.
   --
   --  @param Status Replacement status to format.
   --  @return Human-readable status name.
   function Status_Image (Status : Replace_Status) return String;

   --  Return an image for a replacement validation status.
   --
   --  @param Status Replacement validation status to format.
   --  @return Human-readable status name.
   function Status_Image (Status : Replacement_Validation_Status) return String;

   --  Return an image for a split status.
   --
   --  @param Status Split status to format.
   --  @return Human-readable status name.
   function Status_Image (Status : Split_Status) return String;

   --  Return an image for a copy status.
   --
   --  @param Status Copy status to format.
   --  @return Human-readable status name.
   function Status_Image (Status : Copy_Status) return String;

   --  Return an image for a stream status.
   --
   --  @param Status Stream status to format.
   --  @return Human-readable status name.
   function Status_Image (Status : Stream_Status) return String;

   --  Return an image for a pattern policy status.
   --
   --  @param Status Policy status to format.
   --  @return Human-readable status name.
   function Status_Image (Status : Pattern_Policy_Status) return String;

private
   type Node_Kind is
     (Node_Invalid,
      Node_Match,
      Node_Char,
      Node_Any,
      Node_Class,
      Node_Split,
      Node_Start_Line,
      Node_End_Line,
      Node_Start_Absolute,
      Node_End_Absolute,
      Node_End_Absolute_Optional_Newline,
      Node_Word_Boundary,
      Node_Not_Word_Boundary,
      Node_Lookahead_Positive,
      Node_Lookahead_Negative,
      Node_Lookbehind_Positive,
      Node_Lookbehind_Negative,
      Node_Lookahead_Match,
      Node_Capture_Start,
      Node_Capture_End,
      Node_Backreference,
      Node_Atomic);

   type State_Index is new Natural range 0 .. Default_Max_States;
   subtype State_Count_Type is Natural range 0 .. Default_Max_States;
   No_State : constant State_Index := 0;

   type Character_Set is array (Character) of Boolean;

   type Character_Class is record
      Negated : Boolean := False;
      Members : Character_Set := [others => False];
   end record;

   type Option_Mode is (Option_Inherit, Option_Off, Option_On);

   type Scoped_Options is record
      Case_Sensitive      : Option_Mode := Option_Inherit;
      Dot_Matches_Newline : Option_Mode := Option_Inherit;
      Multiline_Anchors   : Option_Mode := Option_Inherit;
      Free_Spacing        : Option_Mode := Option_Inherit;
   end record;

   type State is record
      Kind  : Node_Kind := Node_Invalid;
      Ch    : Character := Character'Val (0);
      Class : Character_Class;
      Capture : Natural := 0;
      Modes : Scoped_Options := (others => Option_Inherit);
      Out_1 : State_Index := No_State;
      Out_2 : State_Index := No_State;
   end record;

   type State_Array is array (Positive range <>) of State;
   subtype Capture_Name_Length is Natural range 0 .. Max_Capture_Name_Length;
   type Capture_Name_Buffer is array (Positive range 1 .. Max_Capture_Name_Length) of Character;
   type Capture_Name_Array is array (Positive range 1 .. Max_Captures) of Capture_Name_Buffer;
   type Capture_Name_Length_Array is array (Positive range 1 .. Max_Captures) of Capture_Name_Length;
   type Source_Pattern_Buffer is array (Positive range 1 .. Default_Max_Pattern_Length) of Character;

   type Regexp is record
      Valid       : Boolean := False;
      State_Count : State_Count_Type := 0;
      Start       : State_Index := No_State;
      Prefer_First_Match : Boolean := False;
      Has_Backreferences : Boolean := False;
      Has_Atomic : Boolean := False;
      Capture_Count : Natural := 0;
      Capture_Names : Capture_Name_Array := [others => [others => Character'Val (0)]];
      Capture_Name_Lengths : Capture_Name_Length_Array := [others => 0];
      Source_Kind : Pattern_Source_Kind := Source_Unknown;
      Source_Length : Natural := 0;
      Source_Pattern : Source_Pattern_Buffer := [others => Character'Val (0)];
      States      : State_Array (1 .. Default_Max_States);
   end record;

   type Match_Cursor is record
      Expression  : Regexp;
      From        : Positive := 1;
      Options     : Match_Options := (others => <>);
      Done        : Boolean := True;
   end record;

   type Stream_Buffer is array (Positive range 1 .. Default_Stream_Buffer_Length) of Character;

   type Stream_Cursor is record
      Expression  : Regexp;
      Options     : Match_Options := (others => <>);
      Buffer      : Stream_Buffer := [others => Character'Val (0)];
      Length      : Natural := 0;
      Active_Buffer_Length : Positive := Default_Stream_Buffer_Length;
      Base_Offset : Natural := 1;
      Search_From : Positive := 1;
      Done        : Boolean := True;
      Final       : Boolean := False;
   end record;

   type Token_Stream_Cursor is record
      Buffer      : Stream_Buffer := [others => Character'Val (0)];
      Length      : Natural := 0;
      Base_Offset : Natural := 1;
      Options     : Match_Options := (others => <>);
      Final       : Boolean := False;
   end record;
end Regexp;
