# AI Usage Guide For Regexp

This guide is written for coding agents and language models that need to use
the `Regexp` Ada library correctly.

## Correct Usage Pattern

Always compile first, check the compile status, then match:

```ada
with Regexp;

procedure Example is
   package R renames Regexp;
   use type R.Compile_Status;
   use type R.Match_Status;

   Compiled : constant R.Compile_Result := R.Compile ("[A-Z]\w*");
   Found    : R.Match_Result;
begin
   if Compiled.Status /= R.Compile_Ok then
      return;
   end if;

   Found := R.Find_First (Compiled.Expression, "Ada_2022");

   if Found.Status = R.Match_Ok then
      --  Found.First and Found.Last are one-based offsets relative to Text'First.
      null;
   end if;
end Example;
```

## Important Rules

- Import the package with `with Regexp;`.
- Use `use type Regexp.Compile_Status;` before comparing compile statuses.
- Use `use type Regexp.Match_Status;` before comparing match statuses.
- Do not use `Compile_Result.Expression` unless `Status = Compile_Ok`.
- Treat a default `Regexp.Regexp` value as invalid.
- Use `Status_Image` for user-facing diagnostics.
- Result offsets are one-based and relative to the `Text` argument.
- For string slices, offsets are relative to the slice, not the original string.
- Zero-length matches report `Last < First`.
- Default matching is ASCII case-insensitive.

## Choosing A Match Function

Use `Find_First` when you need the first occurrence:

```ada
Found := R.Find_First (Compiled.Expression, Text);
```

Use `Find_From` when searching repeatedly or starting after a known offset:

```ada
From := 1;
loop
   Found := R.Find_From (Compiled.Expression, Text, From);
   exit when Found.Status /= R.Match_Ok;

   --  Process Found.

   if Found.Last < Found.First then
      From := Found.First + 1;
   else
      From := Found.Last + 1;
   end if;
end loop;
```

Prefer `Find_All` when collecting non-overlapping matches into a bounded output
buffer:

```ada
Matches : R.Match_Result_Array (1 .. 16);
Count   : Natural;
Status  : R.Find_All_Status;

R.Find_All (Compiled.Expression, Text, Matches, Count, Status);

if Status = R.Find_All_Ok then
   for I in 1 .. Count loop
      --  Process Matches (I).
      null;
   end loop;
end if;
```

`Find_All` advances automatically after zero-length matches. Handle
`Too_Many_Matches`, `Find_All_Limit_Exceeded`, and `Find_All_Invalid_Regexp`
explicitly when they matter to the caller.

Use `Find_All_From` when collection should begin after offset 1.
Use `Find_All_Overlapping` when matches may start inside a previous match.
Use `Find_All_Overlapping_With_Captures` when overlapping matches also need
capture ranges.
Use `Find_First_Of`, `Find_From_Of`, and `Tokenize` for bounded multi-pattern
search and tokenization. Use `Find_From_Planned` when a search planner should
use a required-prefix skip before falling back to the general matcher.
Use `Tokenize_With_Kinds` for stable caller-defined token IDs, and use
`Find_First_Of_With_Captures`, `Find_From_Of_With_Captures`,
`Tokenize_With_Captures`, or `Find_From_Planned_With_Captures` when captures
are needed.
Use `Find_All_Summary` when the caller needs count, first match, last match,
and total steps without storing every match.
Use `Find_All_Line_Summary` for grep/editor summaries that need first/last
line positions. Use `Find_All_With_Captures` or
`Find_All_With_Captures_From` when each collected match also needs capture
ranges.
Use `Find_First_With_Captures` or `Find_From_With_Captures` when the pattern
uses numbered or named capture groups and the caller needs submatch ranges.
Use `Named_Captures`, `Capture_Name`, and `Capture_Index` to present named
capture metadata and map names to numbered range slots.

Use `Match_Cursor` for incremental scanning without a match array:

```ada
R.Start (Cursor, Compiled.Expression);
loop
   R.Next (Cursor, Text, Found);
   exit when Found.Status /= R.Match_Ok;
end loop;
```

Use `Next_Captured` for iterator results that bundle the match and capture
ranges in one record. Use `Next_Line_Captured` when each cursor result also
needs line and column context.
Use `Start_Token_Stream` and `Feed_Tokens` for bounded chunked tokenization.
Use `Feed_Tokens_Detail` when the caller needs `Token_Stream_Status`
distinctions such as `Token_Stream_Need_More_Data`,
`Token_Stream_Output_Too_Small`, or `Token_Stream_Buffer_Full`.
Use `Feed_Tokens_With_Captures` when chunked tokenization must also return
capture ranges.

Use `Stream_Cursor` for bounded chunked input:

```ada
R.Start_Stream (Stream, Compiled.Expression);
R.Feed (Stream, Chunk, Is_Final => False, Found => Found, Status => Status);
```

After `Stream_Match`, call `Feed` again with an empty chunk to drain additional
buffered matches. Stream offsets are one-based from the beginning of the stream.
Handle `Stream_Buffer_Full`; the cursor is bounded by
`Default_Stream_Buffer_Length`.
Use the `Start_Stream` overload with `Max_Buffer_Length` to select a smaller
per-cursor retained-buffer limit.
Use `Feed_With_Captures` when a stream match also needs capture ranges; returned
capture offsets are stream-relative.

Use `Replace_First`, `Replace_All`, `Replace_First_Count`, `Replace_All_Count`,
and `Split` only with caller-supplied output buffers, and always check
`Replace_Status` or `Split_Status`.
Use `Copy_Match` to copy a successful match into a bounded output buffer.
Replacement strings expand `\0` to the whole match and `\\` to a literal
backslash. They also expand `\1` through `\9` and `\k<name>` to captured text.
Use `Replace_First_Preserving_Case` or
`Replace_All_Preserving_Case` when replacement case should follow each match.

Use `Compile_Literal` for literal search text from users. Use
`Compile_Literal_Set` for escaped alternation from caller-selected ranges. Use
`Compile_Literal_Word_Set` for keyword/token sets that should match whole
words. Use `Compile_Anchored`, `Compile_Whole_Word`,
`Compile_Line`, `Compile_Literal_Anchored`, `Compile_Literal_Whole_Word`, and
`Compile_Literal_Line` instead of hand-building common wrappers. Use
`Supports_Syntax` when tooling needs to query a `Syntax_Feature` family. Use
`Escape_Literal` or the buffer-based `Append_Literal`,
`Append_Literal_Alternative`, `Append_Class_Literal`, and
`Append_Class_Range` helpers when composing larger patterns from user-supplied
text. Use `Build_Character_Class` to finalize escaped character-class members.
Use `Build_Literal_Alternation` and `Build_Literal_Word_Alternation`
when ranges should become a reusable escaped pattern. Use `Has_Match` or
`Count_Matches` when the caller does not need stored ranges. Common preset
patterns are `Identifier_Pattern`,
`Integer_Pattern`,
`Whitespace_Run_Pattern`, `Path_Segment_Pattern`, `UUID_Pattern`,
`Hex_Integer_Pattern`, `Quoted_String_Pattern`, `Line_Comment_Pattern`,
`Path_Extension_Pattern`, `Simple_Email_Pattern`, and `Simple_URL_Pattern`.
Use `Default_Options`, `Case_Sensitive_Options`, `Multiline_Options`,
`Dot_All_Options`, and `UTF_8_Options` when named option presets make calls
clearer. Use `Validate_UTF_8` and `UTF_8_Validation_Result` when diagnostics
need a specific invalid byte offset before matching with `UTF_8_Mode`.

Use `Line_Column`, `Match_Line_Range`, `Match_Context`, and `Find_First_Line`
when reporting matches in editor or grep-style output. Use `Match_Length`,
`Contains_Offset`, `Before_Match`, and `After_Match` for small containment and
range checks. Use
`Next_With_Captures` when iterating matches and captures without a full match
array. Use `Has_Captures`, `Uses_Anchors`, `May_Match_Empty`,
`Required_Prefix`, and `Features` for bounded compiled-pattern introspection
before choosing a search strategy. Use `Validate_Policy` with
`Literal_Search_Policy`, `Editor_Search_Policy`,
`No_Backtracking_Features_Policy`, `Safe_User_Search_Policy`,
`Streaming_Search_Policy`, `Editor_Replace_Policy`,
`No_Empty_Match_Policy`, `No_Lookaround_Policy`, or
`No_Backreferences_Policy` to reject disallowed pattern features before
matching.
Use `Validate_Policy_Detail` when diagnostics need the first disallowed
`Policy_Feature`.
Use `Is_Literal`, `Is_Anchored`, `Is_Whole_Line`, `Needs_Backtracking`,
`Can_Stream_Safely`, and `Recommended_Strategy` for simple search planning.
Use `Summary` for state/capture counts, features, source metadata, prefix
length, and strategy in one call. Use `Fingerprint` and `Pattern_Fingerprint`
for compile-cache keys, and `Metadata`/`Pattern_Metadata` when tools need the
fingerprint, source kind, source length, limits, strategy, and features
together. Use `Source_Kind` and `Copy_Source_Pattern` for bounded retained
source text, and `Lint` for warning flags.
Use `Compile_Diagnostic` and `Replacement_Diagnostic` for structured diagnostic
records. Use `Explain_Nodes` when tooling needs a structured compiled-node
summary instead of formatted explanation text.
Use `Copy_Range`, `Copy_Before`, `Copy_After`, and `Copy_Match_Line` to copy
reported ranges into caller-supplied output buffers. Use `Copy_Capture`,
`Copy_Named_Capture`, and `Find_All_Lines` for capture and grep-style line
output helpers.
Use `Replace_All_Lines` and `Split_Lines` when replacement or split planning
needs containing source-line ranges.
Use `Named_Capture_Range` when only the range is needed.

Replacement strings expand `\0`, `\1` through `\9`, `\k<name>`, and `\\`.
They also support case conversion escapes: `\U...\E`, `\L...\E`, `\u`, and
`\l`. Use `Validate_Replacement` to reject malformed replacement templates or
references to missing captures before writing output. Use
`Validate_Replacement_Detail` when diagnostics need the capture index or
`\k<name>` name range. Use `Replacement_References` when tooling needs an
inventory of replacement capture references.
Use `Replacement_Summary` when tooling needs replacement feature flags.
Use `Required_First_Output_Length`, `Required_All_Output_Length`, and
`Replacement_Fits` for output planning.
Use `Plan_Replacement` to preview copied and replaced source ranges without
expanding replacement output; each edit reports its required expanded length.
Use `Plan_Replacement_Detail` when tooling also needs replacement reference
inventory, `Replacement_Output_Map` entries, and the aggregate
`Replacement_Plan`.
Use `Escape_Replacement` when user-supplied replacement text should be inserted
literally.
Use `Replace_First_Size` and `Replace_All_Size` when callers need the required
output length before selecting a bounded output buffer.

Use `Explain`, `Format_Compile_Diagnostic`, and
`Format_Replacement_Diagnostic` for bounded user-facing diagnostics. These
helpers write into caller-supplied buffers and report `Copy_Status`.
Use `Is_Syntax_Error`, `Is_Unsupported`, and `Is_Limit_Error` to group statuses
for CLI exits or diagnostics.
Use `Syntax_Feature_Image` and `Supported_Syntax` when printing supported
syntax. Use `Supported_Syntax_Detail`, `Syntax_Support`, and
`Syntax_Support_Array` when a structured support inventory is needed. Prefer
class constants such as `Digit_Class`, `Word_Class`, and
`Identifier_Start_Class` over hand-written duplicate fragments.
Use `Benchmark_Pattern` and `Benchmark_Text` for built-in smoke corpus cases.
Use `Benchmark_Summary` to run a built-in case. Use `Make_Token_Name` and
`Copy_Token_Name` for bounded token-name diagnostics.

Use `Matches_Entire` for validation:

```ada
Found := R.Matches_Entire (Compiled.Expression, Text);
```

## Options

The default options are:

```ada
(Case_Sensitive => False,
 Whole_Word     => False,
 Dot_Matches_Newline => False,
 Multiline_Anchors => False,
 Character_Mode => ASCII_Mode,
 Max_Steps      => 50_000,
 Abort          => null)
```

Case-sensitive matching:

```ada
Found := R.Find_First
  (Compiled.Expression,
   Text,
   (Case_Sensitive => True, others => <>));
```

Whole-word matching:

```ada
Found := R.Find_First
  (Compiled.Expression,
   Text,
   (Whole_Word => True, others => <>));
```

Dot matching across LF/CR:

```ada
Found := R.Find_First
  (Compiled.Expression,
   Text,
   (Dot_Matches_Newline => True, others => <>));
```

Multiline anchors:

```ada
Found := R.Find_First
  (Compiled.Expression,
   Text,
   (Multiline_Anchors => True, others => <>));
```

Bounded matching:

```ada
Found := R.Find_First
  (Compiled.Expression,
   Text,
   (Max_Steps => 10_000, others => <>));
```

If `Found.Status = R.Match_Limit_Exceeded`, inspect `Found.Steps_Used`.

Abort callback:

```ada
function Should_Stop return Boolean is
begin
   return False;
end Should_Stop;

Found := R.Find_First
  (Compiled.Expression,
   Text,
   (Abort => Should_Stop'Access, others => <>));
```

## Supported Syntax

Generate patterns using only:

- Literal characters
- `.`
- `^`
- `$`
- Character classes: `[abc]`, `[^abc]`, `[a-z]`
- Character-class operators: `[a-z&&[^aeiou]]`, `[a-z--[aeiou]]`
- Quantifiers: `*`, `+`, `?`
- Bounded repeats: `{m}`, `{m,n}`, `{m,}`
- Lazy quantifiers: `*?`, `+?`, `??`, `{m,n}?`
- Possessive quantifiers: `*+`, `++`, `?+`, `{m,n}+`
- Numbered capture grouping: `(cat|dog)`
- Named capture grouping: `(?<name>cat|dog)`
- Non-capturing grouping: `(?:cat|dog)`, `(?:ab)+`
- Atomic grouping: `(?>cat|dog)`
- Lookahead assertions: `(?=cat)`, `(?!cat)`
- Fixed-width lookbehind assertions: `(?<=cat)`, `(?<!cat)`
- Scoped inline options: `(?i:cat)`, `(?-i:cat)`, `(?m:^cat)`, `(?s:.)`
- Top-level alternation: `cat|dog`
- Backreferences to earlier captures: `\1`, `\k<name>`
- Shorthand classes: `\d`, `\D`, `\w`, `\W`, `\s`, `\S`
- Unicode property classes: `\p{...}`, `\P{...}`
- Word boundaries: `\b`, `\B`
- Escaped metacharacters: `\.`, `\*`, `\+`, `\?`, `\(`, `\)`, `\[`, `\]`,
  `\{`, `\}`, `\\`, `\^`, `\$`, `\|`

Captures inside lookahead and lookbehind assertions are assertion-local and are
not exported by `Capture_Count` or capture-aware match results. Generate only
fixed-width lookbehind patterns; variable-width lookbehind is rejected as
`Unsupported_Syntax`.
Inline option groups are scoped to the group body. Use `i`/`-i` for
case-insensitive or case-sensitive matching, `m`/`-m` for multiline anchors,
and `s`/`-s` for dot-newline behavior.
Backreferences must refer to captures declared earlier in the pattern.
Possessive quantifiers and atomic groups commit to their longest internal match.
Atomic subpatterns currently reject captures and backreferences.

Empty alternatives and empty groups are valid and match the empty string:

```text
|abc       valid
abc|       valid
a||b       valid
()         valid
(?:)       valid
```

Malformed bounded repeats are invalid quantifiers:

```text
a{}       invalid
a{,2}     invalid
a{3,2}    invalid
```

## Compile Errors

Handle compile failures explicitly:

```ada
if Compiled.Status /= R.Compile_Ok then
   Put_Line
     ("invalid pattern: " &
      R.Status_Image (Compiled.Status) &
      " at offset" & Natural'Image (Compiled.Error_Offset));
   return;
end if;
```

Common statuses:

- `Empty_Pattern`
- `Pattern_Too_Long`
- `Too_Many_States`
- `Too_Many_Captures`
- `Invalid_Capture_Name`
- `Duplicate_Capture_Name`
- `Invalid_Escape`
- `Unterminated_Class`
- `Empty_Class`
- `Invalid_Class_Range`
- `Invalid_Quantifier`
- `Quantifier_Without_Atom`
- `Unsupported_Syntax`

## Build And Verification

Build the library:

```sh
alr exec -- gprbuild -P regexp.gpr
```

Build examples:

```sh
alr exec -- gprbuild -P examples/examples.gpr
```

Run tests when AUnit is available:

```sh
cd tests && alr exec -- gprbuild -P tests.gpr
tests/bin/tests
```

Run the full release checklist from a clean Git worktree after committing
intended changes:

```sh
alr build
alr exec -- gprbuild -P regexp.gpr
cd tests && alr exec -- gprbuild -P tests.gpr
cd tests && ./bin/tests
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
tools/bin/check_all
```

`tools/bin/check_all` requires Alire GNAT 15 and does not accept plain system
`gprbuild` or `gnatprove`. It builds the
library, examples, AUnit tests, tools, and `check_regexp`; runs `alr test`; runs
`alr exec -- gnatprove -P regexp.gpr --level=4`; rejects nonempty captured stderr artifacts;
and requires the regexp Git worktree to be clean at the end.

`check_regexp` is repository tooling, not a consumer dependency. It validates
release metadata, example output fences, example failure handling, public
API-only examples, split AUnit inventory, source policy, and the staged manifest
workflow. `check_regexp/alire.toml` is the development manifest with local pins.
`check_regexp/alire.release.toml` is the pin-free release manifest template. The
checker stages `regexp` and sibling `project_tools` source trees under `/tmp`,
writes a local `alire.build.toml` overlay for workspace pins, activates it, and
builds the staged checker.
