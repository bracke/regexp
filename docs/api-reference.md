# Regexp API Reference

Authoritative source: [`src/regexp.ads`](../src/regexp.ads).

## Package

```ada
package Regexp is
   pragma Pure;
   pragma SPARK_Mode (On);
```

## Types

### `Regexp`

```ada
type Regexp is private;
```

Compiled regular expression. Values are created by `Compile`.

### `Compile_Status`

```ada
type Compile_Status is
  (Compile_Ok,
   Empty_Pattern,
   Pattern_Too_Long,
   Too_Many_States,
   Too_Many_Captures,
   Invalid_Capture_Name,
   Duplicate_Capture_Name,
   Invalid_Escape,
   Unterminated_Class,
   Empty_Class,
   Invalid_Class_Range,
   Invalid_Quantifier,
   Quantifier_Without_Atom,
   Unsupported_Syntax);
```

### `Match_Status`

```ada
type Match_Status is
  (Match_Ok,
   No_Match,
   Match_Limit_Exceeded,
   Invalid_Regexp);
```

### `Find_All_Status`

```ada
type Find_All_Status is
  (Find_All_Ok,
   No_Matches,
   Too_Many_Matches,
   Find_All_Limit_Exceeded,
   Find_All_Invalid_Regexp);
```

### `Replace_Status`

```ada
type Replace_Status is
  (Replace_Ok,
   Replace_No_Match,
   Replace_Output_Too_Small,
   Replace_Limit_Exceeded,
   Replace_Invalid_Regexp);
```

### `Replacement_Validation_Status`

```ada
type Replacement_Validation_Status is
  (Replacement_Ok,
   Replacement_Invalid_Regexp,
   Replacement_Invalid_Escape,
   Replacement_Unknown_Capture,
   Replacement_Unterminated_Name,
   Replacement_Unterminated_Case_Conversion);
```

### `Split_Status`

```ada
type Split_Status is
  (Split_Ok,
   Too_Many_Parts,
   Split_Limit_Exceeded,
   Split_Invalid_Regexp);
```

### `Compile_Result`

```ada
type Compile_Result is record
   Status       : Compile_Status := Empty_Pattern;
   Expression   : Regexp;
   Error_Offset : Natural := 0;
end record;
```

### `Match_Result`

```ada
type Match_Result is record
   Status     : Match_Status := No_Match;
   First      : Natural := 0;
   Last       : Natural := 0;
   Steps_Used : Natural := 0;
end record;
```

`First` and `Last` are one-based offsets relative to `Text'First`.

### `Match_Result_Array`

```ada
type Match_Result_Array is array (Positive range <>) of Match_Result;
type Capture_Index_Array is array (Positive range <>) of Natural;
```

Caller-supplied output buffers for `Find_All` and `Named_Captures`.

### `Match_Options`

```ada
type Match_Options is record
   Case_Sensitive : Boolean := False;
   Whole_Word     : Boolean := False;
   Dot_Matches_Newline : Boolean := False;
   Multiline_Anchors   : Boolean := False;
   Character_Mode      : Character_Mode_Type := ASCII_Mode;
   Max_Steps      : Natural := 50_000;
   Abort          : Match_Abort_Callback := null;
end record;
```

`Dot_Matches_Newline` controls whether `.` matches LF and CR.
`Multiline_Anchors` controls whether `^` and `$` match after and before LF/CR.
`Character_Mode_Type` is `ASCII_Mode` or `UTF_8_Mode`. `UTF_8_Mode` validates
input as UTF-8 and treats non-ASCII bytes as word bytes for word-boundary and
whole-word checks; invalid UTF-8 returns `No_Match`.
`Abort` is an optional callback checked during matching to request early
termination. If it returns `True`, matching returns `Match_Limit_Exceeded` and
the current step count.
`Default_Options`, `Case_Sensitive_Options`, `Multiline_Options`,
`Dot_All_Options`, and `UTF_8_Options` provide named defaults for common
matching modes.

### `UTF_8_Validation_Result`

```ada
type UTF_8_Validation_Result is record
   Valid        : Boolean := True;
   Error_Offset : Natural := 0;
end record;
```

Returned by `Validate_UTF_8`. `Error_Offset` is one-based and is 0 when the
input is valid.

### `Text_Range`

```ada
type Text_Range is record
   First : Natural := 0;
   Last  : Natural := 0;
end record;

type Text_Range_Array is array (Positive range <>) of Text_Range;
```

Ranges are one-based and relative to `Text'First`.

### `Source_Position`

```ada
type Source_Position is record
   Line   : Natural := 0;
   Column : Natural := 0;
end record;
```

`Line_Column` maps a one-based text offset to line and column, treating LF, CR,
and CRLF as line breaks. `Match_Line_Range` returns the full line containing a
match, excluding the line break. `Match_Context` splits text into before, match,
and after `Text_Range` values for a successful `Match_Result`.
`Find_First_Line` combines `Find_First`, `Line_Column`, and
`Match_Line_Range`.

### `Replacement_Validation_Result`

```ada
type Replacement_Validation_Result is record
   Status       : Replacement_Validation_Status := Replacement_Ok;
   Error_Offset : Natural := 0;
   Capture      : Natural := 0;
   Name         : Text_Range := (others => 0);
end record;
```

Returned by `Validate_Replacement_Detail`.

### `Find_All_Summary_Result`

`Find_All_Summary_Result` is returned by `Find_All_Summary`. It reports the
overall `Find_All_Status`, total match count, first match, last match, and
total matching steps without requiring a match array.
`Find_All_Line_Summary_Result` adds first/last line positions and containing
line ranges for grep/editor summaries.
`Expression_Summary` reports validity, state/capture counts, features, retained
source metadata, prefix length, and recommended strategy.
`Pattern_Lint` reports bounded lint flags such as empty-match risk, stream
lookaround, broad dot-star source, and missing required prefix.
`Compile_Diagnostic_Record` and `Replacement_Diagnostic_Record` provide
machine-readable diagnostic categories for compile and replacement validation
results.

### `Pattern_Features`

`Pattern_Features` is a Boolean record returned by `Features`. It summarizes
captures, named captures, backreferences, anchors, word boundaries, lookaround,
atomic internals, character classes, dot usage, scoped options, split states,
and whether the expression may match the empty string.

### `Replacement_Reference_Array`

`Replacement_Reference_Array` is a caller-supplied array of
`Replacement_Reference` records. `Replacement_References` fills it with `\0`,
numbered-capture, and named-capture references discovered in a valid
replacement template.
`Replacement_Features` is returned by `Replacement_Summary` and reports whether
a valid template uses the whole match, numbered captures, named captures, case
conversion, and whether the supplied reference buffer was complete.

### `Capture_Result_Array`

`Capture_Result_Array` is a two-dimensional caller-supplied matrix used by
`Find_All_With_Captures`. Rows are match slots and columns are capture slots.
`Captured_Match_Result` is a fixed capture-buffer record returned by
`Next_Captured` and embedded in `Line_Captured_Match_Result`.
`Pattern_Match_Captures_Result` and `Pattern_Match_Captures_Array` add the
same fixed capture buffer to pattern-set and tokenization helpers.

### `Syntax_Feature`

`Syntax_Feature` enumerates the supported syntax families that
`Supports_Syntax` can query, including literals, dot, anchors, character
classes, Unicode property classes, POSIX classes, class set operations, groups,
named captures, lookaround, backreferences, bounded repeats, lazy and
possessive quantifiers, atomic groups, inline options, and word boundaries.
`Syntax_Feature_Image` and `Supported_Syntax` provide printable/inventory forms
for tooling. `Supported_Syntax_Detail` fills a `Syntax_Support_Array` with
structured support flags, notes, and examples copied into caller buffers.

### `Search_Strategy`

`Recommended_Strategy` returns `Search_Invalid`, `Search_Literal`,
`Search_Anchored`, `Search_Prefix`, or `Search_General` for planning tools.
`Pattern_Source_Kind`, `Source_Kind`, and `Copy_Source_Pattern` expose retained
source provenance and bounded source text.

## Constants

```ada
Default_Max_Pattern_Length : constant Positive := 256;
Default_Max_States         : constant Positive := 512;
Default_Max_Steps          : constant Positive := 50_000;
Default_Options            : constant Match_Options := (others => <>);
Case_Sensitive_Options     : constant Match_Options := (Case_Sensitive => True, others => <>);
Multiline_Options          : constant Match_Options := (Multiline_Anchors => True, others => <>);
Dot_All_Options            : constant Match_Options := (Dot_Matches_Newline => True, others => <>);
UTF_8_Options              : constant Match_Options := (Character_Mode => UTF_8_Mode, others => <>);
```

Preset patterns are provided for common bounded tokens:
`Identifier_Pattern`, `Integer_Pattern`, `Whitespace_Run_Pattern`,
`Path_Segment_Pattern`, `UUID_Pattern`, `Hex_Integer_Pattern`,
`Quoted_String_Pattern`, `Line_Comment_Pattern`, `Path_Extension_Pattern`,
`Simple_Email_Pattern`, and `Simple_URL_Pattern`.

Policy presets are also provided: `Literal_Search_Policy`,
`Editor_Search_Policy`, `No_Backtracking_Features_Policy`,
`Safe_User_Search_Policy`, `Streaming_Search_Policy`, and
`Editor_Replace_Policy`. Stricter presets are `No_Empty_Match_Policy`,
`No_Lookaround_Policy`, and `No_Backreferences_Policy`.

## Functions

### `Compile`

```ada
function Compile
  (Pattern            : String;
   Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
   Max_States         : Positive := Default_Max_States)
   return Compile_Result
   with Pre => Pattern'Last < Positive'Last;
```

Compiles a pattern into a reusable expression.

### `Is_Valid`

```ada
function Is_Valid (Expression : Regexp) return Boolean;
```

Returns whether `Expression` can be used for matching.

### `Find_First`

```ada
function Find_First
  (Expression : Regexp;
   Text       : String;
   Options    : Match_Options := (others => <>))
   return Match_Result
   with Pre => Text'Last < Positive'Last;
```

Finds the first match in `Text`.

### `Find_From`

```ada
function Find_From
  (Expression : Regexp;
   Text       : String;
   From       : Positive;
   Options    : Match_Options := (others => <>))
   return Match_Result
   with Pre => Text'Last < Positive'Last;
```

Finds the first match at or after one-based offset `From`.

### `Find_All`

```ada
procedure Find_All
  (Expression : Regexp;
   Text       : String;
   Matches    : out Match_Result_Array;
   Count      : out Natural;
   Status     : out Find_All_Status;
   Options    : Match_Options := (others => <>))
   with Pre => Text'Last < Positive'Last;
```

Collects non-overlapping matches into `Matches` and writes the number of stored
matches to `Count`. `Too_Many_Matches` reports an undersized output buffer.
Zero-length matches are advanced by one input position before the next search.
`Options.Max_Steps` applies to the whole scan.

### `Find_All_From`

Collects non-overlapping matches starting at one-based offset `From`.

### Convenience

`Compile_Literal` compiles literal text by escaping all regexp metacharacters.
`Compile_Literal_Set` compiles caller-selected `Text_Range_Array` terms as one
escaped literal alternation.
`Compile_Literal_Word_Set` compiles caller-selected word terms as an escaped
alternation wrapped in word boundaries.
`Compile_Anchored`, `Compile_Whole_Word`, `Compile_Line`,
`Compile_Literal_Anchored`, `Compile_Literal_Whole_Word`, and
`Compile_Literal_Line` wrap raw or literal patterns for common anchored,
whole-word, and whole-line matching.
`Supports_Syntax` lets tools ask whether a `Syntax_Feature` family is compiled
by this library.
`Supported_Syntax_Detail` inventories each `Syntax_Feature` with support
status plus bounded note and example ranges for generated documentation.
`Validate_UTF_8` checks text before matching in `UTF_8_Mode`.
`Is_Literal`, `Is_Anchored`, `Is_Whole_Line`, `Needs_Backtracking`,
`Can_Stream_Safely`, and `Recommended_Strategy` classify compiled expressions
for search planners.
`Summary` returns the common expression metadata in one call. `Fingerprint`
returns a stable bounded `Pattern_Fingerprint` for cache keys, and `Metadata`
combines the fingerprint, source kind, source length, limits, strategy, and
features into `Pattern_Metadata`. `Lint` returns bounded warnings for broad or
difficult expressions.
`Escape_Literal` returns escaped literal text for callers building a larger
pattern around user input.
`Append_Fragment`, `Append_Literal`, `Append_Literal_Alternative`,
`Append_Class_Literal`, and `Append_Class_Range` append to a caller-supplied
pattern buffer and return `Copy_Status`. Use `Append_Fragment` only for trusted
regexp syntax; the literal helpers escape user-supplied text and can build
literal alternation or character-class members.
`Build_Character_Class` finalizes escaped class members into a complete
`[...]` or `[^...]` pattern fragment.
`Build_Literal_Alternation` and `Build_Literal_Word_Alternation` build escaped
literal alternation patterns into caller-supplied buffers.
Class fragment constants are available for builders: `Digit_Class`,
`Non_Digit_Class`, `Word_Class`, `Non_Word_Class`, `Whitespace_Class`,
`Non_Whitespace_Class`, `Identifier_Start_Class`, and
`Identifier_Continue_Class`.
`Has_Match` tests for any match, and `Count_Matches` counts non-overlapping
matches without storing every range.
`Find_First_Line` returns the first match with source-position and line ranges.
`Has_Captures`, `Uses_Anchors`, `May_Match_Empty`, `Required_Prefix`, and
`Features` provide bounded introspection over a compiled expression.
`Validate_Policy` rejects compiled expressions that violate a supplied
`Pattern_Policy`.
`Validate_Policy_Detail` returns a `Pattern_Policy_Diagnostic` with the first
disallowed `Policy_Feature`.
`Compile_Diagnostic` and `Replacement_Diagnostic` return structured diagnostic
records for tooling that should not parse formatted diagnostic strings.

Preset patterns: `Identifier_Pattern`, `Integer_Pattern`,
`Whitespace_Run_Pattern`, and `Path_Segment_Pattern`.

### Captures

Numbered capture grouping uses `(...)`; named capture grouping uses
`(?<name>...)`. `Capture_Count` returns the number of groups in a compiled
expression, `Capture_Index` maps a name to its one-based capture index,
`Named_Captures` collects the indexes of named captures, and `Capture_Name`
copies the name associated with a one-based capture index.
`Has_Captures` is a convenience predicate over `Capture_Count`.
`Find_First_With_Captures` and `Find_From_With_Captures` copy submatch ranges
into a caller-supplied `Text_Range_Array`. Capture offsets are one-based and
relative to the `Text` argument, like `Match_Result`; unmatched optional
captures report `First = 0` and `Last = 0`. `Max_Captures` bounds the number of
capture groups; patterns above that limit return `Too_Many_Captures`. Capture
names are bounded by `Max_Capture_Name_Length`.
`Copy_Capture` and `Copy_Named_Capture` copy capture ranges into
caller-supplied buffers.

### Overlapping Matches

`Find_All_Overlapping` and `Find_All_Overlapping_From` collect matches into a
caller-supplied `Match_Result_Array`, advancing one character after the previous
match start so later matches may overlap earlier matches.
`Find_All_Lines` collects the containing line range for each non-overlapping
match.
`Find_All_Summary` counts all matches, keeps the first and last match, and
accumulates steps without storing every match range.
`Find_All_Line_Summary` adds first/last source positions and line ranges.
`Find_All_With_Captures` and `Find_All_With_Captures_From` collect match ranges
and capture ranges in one bounded call.
`Find_All_Overlapping_With_Captures` and
`Find_All_Overlapping_With_Captures_From` do the same for overlapping matches.
`Find_First_Of` and `Find_From_Of` search a caller-supplied `Regexp_Array` and
return the earliest match plus the expression index. `Tokenize` repeatedly uses
that pattern-set search to fill a bounded `Pattern_Match_Array`.
`Tokenize_With_Kinds` maps expressions to caller-defined numeric token kinds.
`Find_First_Of_With_Captures`, `Find_From_Of_With_Captures`, and
`Tokenize_With_Captures` add capture ranges. `Find_From_Planned_With_Captures`
combines required-prefix planning with capture output.
`Find_From_Planned` uses a deterministic required-prefix skip when available
before falling back to the general matcher.

### Match Ranges

`Match_Length`, `Contains_Offset`, `Before_Match`, and `After_Match` provide
small containment and slicing helpers around a `Match_Result`.
`Named_Capture_Range` maps a capture name directly to a range from a capture
array.

### `Match_Cursor`

`Start` and `Next` provide incremental non-overlapping matching without a match
array. `Next_With_Captures` advances the same cursor while copying capture
ranges for the returned match. The cursor stores the compiled expression, next
offset, and options.
`Next_Captured` returns the same data as a `Captured_Match_Result`.
`Next_Line_Captured` also reports the source position and containing line.
`Start_Token_Stream` and `Feed_Tokens` provide bounded chunked tokenization with
stream-relative offsets. `Feed_Tokens_Detail` returns `Token_Stream_Status` so
callers can distinguish need-more-data, no-token, output-too-small,
buffer-full, limit-exceeded, and invalid-expression outcomes.
`Feed_Tokens_With_Captures` adds capture ranges to chunked tokenization.

### `Stream_Cursor`

`Start_Stream` and `Feed` provide bounded chunked matching. `Feed` appends each
chunk to an internal buffer of `Default_Stream_Buffer_Length` bytes, so matches
can span chunk boundaries without heap allocation. Returned `Match_Result`
offsets are one-based stream offsets. Greedy matches that end at the current
buffer edge are held until another chunk arrives or `Is_Final` is `True`;
`Stream_Buffer_Full` reports that no complete match was available before the
bounded buffer filled. The `Start_Stream` overload with `Max_Buffer_Length`
configures a smaller retained-buffer limit for a cursor.
`Feed_With_Captures` returns capture ranges for stream matches using one-based
stream offsets.

### Replacement

`Replace_First` and `Replace_All` write to a caller-supplied output buffer and
return a `Replace_Status`. Replacements expand `\0` to the whole match and
`\\` to a literal backslash. Numbered replacement backreferences use `\1`
through `\9`; named replacement backreferences use `\k<name>`.
Replacement case escapes are supported: `\U...\E` uppercases a span, `\L...\E`
lowercases a span, `\u` uppercases the next emitted character, and `\l`
lowercases the next emitted character. These transforms apply to literal
replacement text and expanded captures.
`Replace_First_Count` and `Replace_All_Count` also return the number of
replacements made.
`Replace_First_Preserving_Case` and
`Replace_All_Preserving_Case` adapt replacement letter case to each match.
`Validate_Replacement` checks replacement syntax and capture references before
running a replacement. `Validate_Replacement_Detail` returns a
`Replacement_Validation_Result` with status, error offset, capture index, and
the `\k<name>` name range when applicable.
`Replacement_References` validates a template and inventories `\0`, numbered,
and named capture references into a caller-supplied
`Replacement_Reference_Array`.
`Replacement_Summary` returns replacement feature flags and validation detail.
`Escape_Replacement` doubles replacement backslashes so literal replacement
text cannot be interpreted as captures or case escapes.
`Required_First_Output_Length`, `Required_All_Output_Length`, and
`Replacement_Fits` are convenience wrappers around replacement sizing.
`Plan_Replacement` previews source ranges that `Replace_All` would copy or
replace without expanding the replacement template. Each `Replacement_Edit`
also reports the required expanded length for that edit.
`Plan_Replacement_Detail` additionally inventories replacement capture
references, fills `Replacement_Output_Map_Array`, and returns a
`Replacement_Plan` with status, edit count, reference count, output map count,
required output length, and replacement count.
`Replace_First_Size` and `Replace_All_Size` dry-run expansion and report the
required output length plus replacement count.

### `Split`

`Split` writes non-matching text ranges into a caller-supplied
`Text_Range_Array`.
`Replace_All_Lines` collects containing lines for matches that would be
replaced. `Split_Lines` collects containing line ranges for split parts.

### `Copy_Match`

`Copy_Match` copies the text covered by a successful `Match_Result` into a
caller-supplied output buffer and returns a `Copy_Status`.
`Copy_Range`, `Copy_Before`, `Copy_After`, and `Copy_Match_Line` copy ranges
derived from `Match_Context` and `Match_Line_Range`.

### Structured Explanation And Corpus

`Explain_Nodes` copies bounded `Expression_Node` records for the compiled graph
when tooling needs a structured explanation rather than text output. Node
records include zero-width, negated-class, and scoped-option flags.
`Benchmark_Pattern` and `Benchmark_Text` expose a small built-in smoke corpus
for common identifier, number, email, URL, key/value, and line-comment searches.
`Benchmark_Summary` compiles and runs one built-in case and returns match
counts and steps. `Make_Token_Name` and `Copy_Token_Name` provide bounded token
name storage for diagnostics and highlighting.

### `Debug_Dump`

`Debug_Dump` writes a deterministic diagnostic view of a compiled expression
into a caller-supplied `String` buffer. It is intended for tooling, tests, and
maintainers rather than pattern serialization.
`Explain` writes a compact feature/capture/prefix summary.
`Format_Compile_Diagnostic` and `Format_Replacement_Diagnostic` write bounded
caret diagnostics into caller-supplied buffers.

### `Matches_Entire`

```ada
function Matches_Entire
  (Expression : Regexp;
   Text       : String;
   Options    : Match_Options := (others => <>))
   return Match_Result
   with Pre => Text'Last < Positive'Last;
```

Returns `Match_Ok` only when `Expression` consumes all of `Text`.

### `Status_Image`

```ada
function Status_Image (Status : Compile_Status) return String;
function Status_Image (Status : Match_Status) return String;
function Status_Image (Status : Find_All_Status) return String;
function Status_Image (Status : Replace_Status) return String;
function Status_Image (Status : Replacement_Validation_Status) return String;
function Status_Image (Status : Split_Status) return String;
function Status_Image (Status : Copy_Status) return String;
function Diagnostic_Image (Result : Compile_Result) return String;
```

Returns a human-readable status string.
`Is_Syntax_Error`, `Is_Unsupported`, and the overloaded `Is_Limit_Error`
helpers classify statuses for CLI and tooling diagnostics.

## Syntax Scope

`Regexp` intentionally supports a compact, bounded syntax for editor and
project-search style workloads. Top-level alternation with `|` and bounded
repeats with `{m}`, `{m,n}`, and `{m,}` are supported. Lazy quantifiers use the
usual trailing `?`, such as `*?`, `+?`, `??`, and `{m,n}?`. Character classes
support intersection with `&&[...]` and subtraction with `--[...]`, such as
`[a-z&&[^aeiou]]` and `[a-z--[aeiou]]`. Word-boundary escapes `\b` and `\B` are
supported. Non-capturing grouping with `(?:...)` is supported, including grouped
alternation and quantifiers. Numbered capture grouping with `(...)` and named
capture grouping with `(?<name>...)` are supported by the capture-aware APIs.
Positive and negative lookahead assertions use `(?=...)` and `(?!...)`.
Fixed-width positive and negative lookbehind assertions use `(?<=...)` and
`(?<!...)`; variable-width lookbehind is rejected as `Unsupported_Syntax`.
Captures inside lookahead and lookbehind assertions are assertion-local and are
not exported by `Capture_Count` or capture-aware match results.
Scoped inline option groups use `(?i:...)`, `(?-i:...)`, `(?m:...)`,
`(?-m:...)`, `(?s:...)`, and `(?-s:...)` for case sensitivity, multiline
anchors, and dot-newline behavior.
Backreferences with `\1` through `\9` and `\k<name>` match text captured by an
earlier numbered or named capture group. Forward references are rejected during
compilation.
Possessive quantifiers `*+`, `++`, `?+`, and `{m,n}+` and atomic groups
`(?>...)` commit to their longest internal match before the outer expression
continues. Atomic subpatterns currently reject captures and backreferences.
Adding new grouping behavior should preserve bounded compile size,
deterministic error offsets, and match step-limit behavior.
