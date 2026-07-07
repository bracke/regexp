# Regexp

`Regexp` is a small bounded regular-expression engine for Ada. It is designed
for editor and project-search style workloads where predictable limits matter:
compiled patterns have bounded size, matching has a configurable step limit, and
the public API is SPARK-compatible.

## Toolchain

Regexp must be built and validated with Alire GNAT 15. The root, tests, and
`check_regexp` crates pin `gnat_native = "=15.2.1"`. Confirm with:

```sh
alr exec -- gnatls --version
```

Do not run plain system `gnat*`, `gnatmake`, `gnatls`, `gnatprove`, or
`gprbuild` in this workspace. Use `alr exec -- ...` for compiler, builder, and
proof commands so PATH cannot select a different GNAT installation.

## Quickstart

Add the project to your GPR file:

```gpr
with "regexp.gpr";

project My_App is
   for Source_Dirs use ("src");
   for Main use ("my_app.adb");
end My_App;
```

Compile a pattern, check the result, and search text:

```ada
with Ada.Text_IO; use Ada.Text_IO;
with Regexp;

procedure My_App is
   package R renames Regexp;
   use type R.Compile_Status;
   use type R.Match_Status;

   Compiled : constant R.Compile_Result := R.Compile ("a.c");
   Found    : R.Match_Result;
begin
   if Compiled.Status /= R.Compile_Ok then
      Put_Line
        ("compile failed: " &
         R.Status_Image (Compiled.Status) &
         " at offset" & Natural'Image (Compiled.Error_Offset));
      return;
   end if;

   Found := R.Find_First (Compiled.Expression, "xxabcxx");

   if Found.Status = R.Match_Ok then
      Put_Line
        ("match from" & Natural'Image (Found.First) &
         " to" & Natural'Image (Found.Last));
   else
      Put_Line (R.Status_Image (Found.Status));
   end if;
end My_App;
```

Build the library:

```sh
alr exec -- gprbuild -P regexp.gpr
```

Run the mandatory SPARK proof check when validating a release:

```sh
alr exec -- gnatprove -P regexp.gpr --level=4
```

Run the root Alire test action:

```sh
alr test
```

Build and run the examples:

```sh
alr exec -- gprbuild -P examples/examples.gpr
examples/bin/basic_search
```

## AI And Tooling

AI agents and documentation tools should start with:

- [`llms.txt`](llms.txt): compact project map and usage constraints.
- [`docs/ai-usage.md`](docs/ai-usage.md): implementation rules and safe code
  patterns for generated Ada.
- [`docs/api-reference.md`](docs/api-reference.md): stable public API summary.
- [`docs/SPARK.md`](docs/SPARK.md): SPARK proof scope and mandatory GNATprove release command.
- [`docs/ai-index.json`](docs/ai-index.json): machine-readable project index.
- [`src/regexp.ads`](src/regexp.ads): authoritative package specification.

## Matching Model

The library separates compilation from matching:

1. Call `Compile` once for a pattern.
2. Check that `Compile_Result.Status = Compile_Ok`.
3. Reuse `Compile_Result.Expression` with `Find_First`, `Find_From`,
   `Find_All`, or `Matches_Entire`.

A default-initialized `Regexp` value is invalid. Passing an invalid expression
to a matching function returns `Invalid_Regexp`.

Match offsets are one-based and relative to the `Text` argument's first index.
If you pass a string slice, result offsets start at 1 for that slice.

Zero-length matches report `Last < First`. For example, a zero-length match at
the start of a string reports `First = 1` and `Last = 0`.

## Supported Pattern Syntax

| Syntax | Meaning |
| --- | --- |
| `abc` | Literal characters |
| `.` | Any character except LF and CR |
| `^` | Start of text |
| `$` | End of text |
| `[abc]` | Character class |
| `[^abc]` | Negated character class |
| `[a-z]` | Character range |
| `[a-z&&[^aeiou]]` | Character-class intersection |
| `[a-z--[aeiou]]` | Character-class subtraction |
| `[[:alpha:]]`, `[[:digit:]]` | POSIX ASCII character classes |
| `*` | Zero or more of the previous atom |
| `+` | One or more of the previous atom |
| `?` | Zero or one of the previous atom |
| `{m}`, `{m,n}`, `{m,}` | Bounded repeats of the previous atom |
| `*?`, `+?`, `??`, `{m,n}?` | Lazy quantifiers |
| `*+`, `++`, `?+`, `{m,n}+` | Possessive quantifiers |
| `(cat|dog)` | Numbered capture group |
| `(?<name>cat|dog)` | Named capture group |
| `(?:cat|dog)` | Non-capturing group |
| `(?>cat|dog)` | Atomic group |
| `(?=cat)` | Positive lookahead assertion |
| `(?!cat)` | Negative lookahead assertion |
| `(?<=cat)` | Fixed-width positive lookbehind assertion |
| `(?<!cat)` | Fixed-width negative lookbehind assertion |
| `(?i:cat)`, `(?-i:cat)` | Scoped case-insensitive or case-sensitive matching |
| `(?m:^cat)`, `(?-m:^cat)` | Scoped multiline anchor mode |
| `(?s:.)`, `(?-s:.)` | Scoped dot-matches-newline mode |
| `cat|dog` | Top-level alternation |
| `\1`, `\k<name>` | Match the text captured by an earlier group |
| `\d`, `\D` | Digit and non-digit classes |
| `\w`, `\W` | Word and non-word classes |
| `\s`, `\S` | Whitespace and non-whitespace classes |
| `\p{...}`, `\P{...}` | Unicode property classes |
| `\b`, `\B` | Word boundary and non-boundary |

Escaped literals are supported for regex metacharacters such as `\.`, `\*`,
`\+`, `\?`, `\(`, `\)`, `\[`, `\]`, `\{`, `\}`, `\\`, `\^`, `\$`, and
`\|`.

Empty alternatives and empty groups match the empty string, including `|a`,
`a|`, `a||b`, `()`, and `(?:)`. Unsupported syntax is reported as
`Unsupported_Syntax`.
Malformed bounded repeats such as `a{}`, `a{,2}`, and `a{3,2}` are reported as
`Invalid_Quantifier`. That is an intentional scope choice: `Regexp` is a
bounded search engine for editor/project-search workloads, not a
Perl-compatible expression engine. Extending the syntax should keep the same
bounded compile size, deterministic error offsets, and step-limit behavior.

## API Reference

### `Compile`

```ada
function Compile
  (Pattern            : String;
   Max_Pattern_Length : Positive := Default_Max_Pattern_Length;
   Max_States         : Positive := Default_Max_States)
   return Compile_Result;
```

Compiles a pattern into a reusable expression. `Max_Pattern_Length` and
`Max_States` bound compilation work and output size.

`Compile_Result` contains:

- `Status`: compile status.
- `Expression`: valid only when `Status = Compile_Ok`.
- `Error_Offset`: one-based pattern offset for compile errors, or 0 when no
  specific offset applies.

### `Is_Valid`

```ada
function Is_Valid (Expression : Regexp) return Boolean;
```

Returns `True` when an expression was successfully compiled.

### `Find_First`

```ada
function Find_First
  (Expression : Regexp;
   Text       : String;
   Options    : Match_Options := (others => <>))
   return Match_Result;
```

Finds the earliest match in `Text`.

### `Find_From`

```ada
function Find_From
  (Expression : Regexp;
   Text       : String;
   From       : Positive;
   Options    : Match_Options := (others => <>))
   return Match_Result;
```

Finds the earliest match at or after `From`, where `From` is a one-based offset
relative to `Text'First`.

Use this to iterate through matches:

```ada
From := 1;
loop
   Found := R.Find_From (Compiled.Expression, Text, From);
   exit when Found.Status /= R.Match_Ok;

   --  Use Found.First and Found.Last here.

   From := Found.Last + 1;
end loop;
```

For patterns that can produce zero-length matches, advance carefully to avoid
searching from the same position repeatedly.

### `Find_All`

```ada
type Match_Result_Array is array (Positive range <>) of Match_Result;

type Find_All_Status is
  (Find_All_Ok,
   No_Matches,
   Too_Many_Matches,
   Find_All_Limit_Exceeded,
   Find_All_Invalid_Regexp);

procedure Find_All
  (Expression : Regexp;
   Text       : String;
   Matches    : out Match_Result_Array;
   Count      : out Natural;
   Status     : out Find_All_Status;
   Options    : Match_Options := (others => <>));
```

Collects non-overlapping matches into a caller-supplied output buffer. `Count`
is the number of elements written. `Too_Many_Matches` reports that the output
array was too small. Zero-length matches are advanced by one input position
before the next search, so callers do not need a special loop rule.

`Find_All_From` collects matches from an explicit one-based start offset.
`Find_All_Overlapping` and `Find_All_Overlapping_From` collect overlapping
matches by advancing one character after each match start.
`Find_All_Summary` counts all matches, keeps the first and last match, and
accumulates steps without storing every match in an array.
`Find_All_Line_Summary` also reports first/last source positions and containing
line ranges. `Find_All_With_Captures` and `Find_All_With_Captures_From` collect
matches and capture ranges in one bounded call.
`Find_All_Overlapping_With_Captures` and
`Find_All_Overlapping_With_Captures_From` add the same capture matrix for
overlapping matches.
`Find_First_Of`, `Find_From_Of`, and `Tokenize` provide bounded multi-pattern
search and tokenization over a caller-supplied `Regexp_Array`.
`Tokenize_With_Kinds` uses caller-supplied numeric token kinds, while
`Find_First_Of_With_Captures`, `Find_From_Of_With_Captures`, and
`Tokenize_With_Captures` add capture ranges.
`Find_From_Planned` uses a deterministic required-prefix skip when available.
`Find_From_Planned_With_Captures` keeps that planned search path while copying
captures.
`Start` and `Next` provide cursor-style incremental matching without a match
array. `Next_With_Captures` advances the same cursor while copying capture
ranges for each match.
`Next_Captured` returns match and capture ranges in one record, and
`Next_Line_Captured` adds source line/column context.
`Start_Token_Stream` and `Feed_Tokens` provide bounded chunked tokenization with
stream-relative offsets. `Feed_Tokens_Detail` returns `Token_Stream_Status`
for chunked tokenization status handling, and `Feed_Tokens_With_Captures` also
copies token capture ranges.

`Start_Stream` and `Feed` provide bounded chunked matching with
`Default_Stream_Buffer_Length` bytes of retained data, allowing matches to span
chunk boundaries. Stream matches report one-based offsets relative to the start
of the stream. Greedy matches ending at the current buffer edge are reported
only after another chunk arrives or the caller passes `Is_Final => True`. The
`Start_Stream` overload with `Max_Buffer_Length` lets callers choose a smaller
retained-buffer limit for a cursor.
`Feed_With_Captures` returns capture ranges for stream matches using one-based
stream offsets.

`Has_Match` and `Count_Matches` cover existence/count-only scans. `Compile_Literal`
escapes all regexp metacharacters before compiling. `Compile_Literal_Set`
compiles caller-selected text ranges as an escaped literal alternation.
`Compile_Literal_Word_Set` builds a word-boundary-wrapped literal alternation
for keyword and token sets.
`Compile_Anchored`, `Compile_Whole_Word`, `Compile_Line`,
`Compile_Literal_Anchored`, `Compile_Literal_Whole_Word`, and
`Compile_Literal_Line` wrap raw or literal patterns safely for common anchored,
whole-word, and whole-line use cases.
`Supports_Syntax` reports whether a `Syntax_Feature` family is compiled by this
library. `Supported_Syntax_Detail` returns a structured `Syntax_Support_Array`
with support flags, notes, and examples.
`Is_Literal`, `Is_Anchored`, `Is_Whole_Line`, `Needs_Backtracking`,
`Can_Stream_Safely`, and `Recommended_Strategy` classify compiled expressions
for search planners.
`Summary` returns common compiled metadata in one call. `Fingerprint` and
`Metadata` expose `Pattern_Fingerprint` and `Pattern_Metadata` for bounded
compile-cache keys. `Source_Kind` and `Copy_Source_Pattern` expose retained
bounded source provenance. `Lint` reports bounded warning flags for broad or
difficult expressions.
`Compile_Diagnostic` and `Replacement_Diagnostic` return structured diagnostic
records for tools that should not parse formatted strings.
`Escape_Literal` returns escaped literal text for callers building a larger
pattern. `Append_Fragment`, `Append_Literal`, and
`Append_Literal_Alternative` build patterns in a caller-supplied buffer; use the
literal helpers for user-supplied text.
`Append_Class_Literal` and `Append_Class_Range` build character-class members
without hand-escaping class metacharacters.
`Build_Character_Class` finalizes escaped class members into a complete class
fragment.
`Build_Literal_Alternation` and `Build_Literal_Word_Alternation` build escaped
literal alternation patterns into caller-supplied buffers.
ASCII class fragments such as `Digit_Class`, `Word_Class`, `Whitespace_Class`,
and `Identifier_Start_Class` are available for builders.
`Line_Column`, `Match_Line_Range`, `Match_Length`, `Contains_Offset`,
`Before_Match`, `After_Match`, `Match_Context`, and `Find_First_Line` map match
offsets to source positions and before/match/after ranges.
`Has_Captures`, `Uses_Anchors`, `May_Match_Empty`, `Required_Prefix`, and
`Features` provide bounded compiled-pattern introspection for tools.
`Validate_Policy` rejects compiled expressions that use policy-disallowed
features such as captures, lookaround, backreferences, or empty matches.
Preset policies include `No_Empty_Match_Policy`, `No_Lookaround_Policy`, and
`No_Backreferences_Policy` for single-feature restrictions.
`Validate_Policy_Detail` identifies the first disallowed `Policy_Feature`.
The preset policies are `Literal_Search_Policy`, `Editor_Search_Policy`, and
`No_Backtracking_Features_Policy`. Additional workflow presets are
`Safe_User_Search_Policy`, `Streaming_Search_Policy`, and
`Editor_Replace_Policy`.
`Copy_Range`, `Copy_Before`, `Copy_After`, and `Copy_Match_Line` copy those
ranges into caller-supplied buffers. `Find_All_Lines` collects containing line
ranges for all non-overlapping matches.

`Capture_Count`, `Capture_Index`, `Named_Captures`, `Capture_Name`,
`Find_First_With_Captures`, and `Find_From_With_Captures` support numbered and
named capture groups. Captures are copied into caller-supplied
`Text_Range_Array` buffers. Unmatched optional captures are reported as
`First = 0` and `Last = 0`. `Copy_Capture` and `Copy_Named_Capture` copy
capture ranges into caller-supplied buffers.
`Named_Capture_Range` maps a name directly to a range from a capture array.

Captures inside lookahead and lookbehind assertions are assertion-local and are
not exported by `Capture_Count` or capture-aware match results. Lookbehind
assertions must have a fixed width; variable-width forms such as `(?<=a*)` are
reported as `Unsupported_Syntax`.

Inline option groups apply only inside their group. `i` makes matching
case-insensitive, `-i` makes it case-sensitive, `m` enables multiline anchors,
`-m` disables multiline anchors, `s` lets `.` match LF and CR, and `-s` restores
the normal dot behavior.

Backreferences match text captured by an earlier numbered or named capture
group. Forward references are rejected during compilation.

Possessive quantifiers and atomic groups commit to their longest internal match
before the outer expression continues. Atomic subpatterns currently reject
captures and backreferences so capture ranges remain deterministic.

`Replace_First` and `Replace_All` write into a caller-supplied `String` buffer,
expand `\0` to the whole match, `\1` through `\9` to numbered captures,
`\k<name>` to named captures, `\\` to a literal backslash, and apply
replacement case escapes `\U...\E`, `\L...\E`, `\u`, and `\l`.
They return `Replace_Output_Too_Small` when the result does not fit.
`Replace_First_Count` and `Replace_All_Count` also report the number of
replacements made. `Validate_Replacement` checks replacement syntax and capture
references before running replacement. `Validate_Replacement_Detail` returns
the same status plus the error offset, capture index, and named-reference range.
`Replacement_References` inventories `\0`, numbered, and named capture
references in a valid replacement template. `Replace_First_Size` and
`Replace_All_Size` dry-run replacement expansion and report required output
length plus replacement count.
`Replacement_Summary` reports replacement feature flags and validation detail.
`Required_First_Output_Length`, `Required_All_Output_Length`, and
`Replacement_Fits` wrap replacement sizing for planning.
`Plan_Replacement` previews copied and replaced source ranges without expanding
the replacement output and reports each edit's required expanded length.
`Plan_Replacement_Detail` also returns replacement references,
`Replacement_Output_Map` entries, and a `Replacement_Plan` summary.
`Escape_Replacement` doubles replacement backslashes so literal replacement
text cannot be interpreted as captures or case escapes.
`Replace_First_Preserving_Case` and
`Replace_All_Preserving_Case` adapt replacement letter case to each match.
`Split` writes non-matching ranges into a caller-supplied `Text_Range_Array`.
`Replace_All_Lines` and `Split_Lines` provide line-oriented planning helpers.
`Copy_Match` copies a successful match into a caller-supplied buffer.
`Debug_Dump` writes a bounded diagnostic view of a compiled expression for
tooling and tests. `Explain` writes a compact feature/capture/prefix summary.
`Explain_Nodes` returns structured compiled-node summaries.
`Format_Compile_Diagnostic` and `Format_Replacement_Diagnostic` render bounded
caret diagnostics into caller-supplied buffers.

Preset patterns are available for common searches: `Identifier_Pattern`,
`Integer_Pattern`, `Whitespace_Run_Pattern`, `Path_Segment_Pattern`,
`UUID_Pattern`, `Hex_Integer_Pattern`, `Quoted_String_Pattern`,
`Line_Comment_Pattern`, `Path_Extension_Pattern`, `Simple_Email_Pattern`, and
`Simple_URL_Pattern`.

Named match-option constants are available for common modes:
`Default_Options`, `Case_Sensitive_Options`, `Multiline_Options`,
`Dot_All_Options`, and `UTF_8_Options`.

Use `Character_Mode_Type`, `ASCII_Mode`, `UTF_8_Mode`, `Validate_UTF_8`, and
`UTF_8_Validation_Result` when a caller needs UTF-8 validation before matching.

`Benchmark_Pattern` and `Benchmark_Text` provide a small built-in smoke corpus
for common search workloads. `Benchmark_Summary` runs one corpus case.
`Make_Token_Name` and `Copy_Token_Name` provide bounded token-name helpers for
diagnostics and highlighting.

### `Matches_Entire`

```ada
function Matches_Entire
  (Expression : Regexp;
   Text       : String;
   Options    : Match_Options := (others => <>))
   return Match_Result;
```

Returns `Match_Ok` only when the expression consumes all of `Text`.

### `Status_Image`

```ada
function Status_Image (Status : Compile_Status) return String;
function Status_Image (Status : Match_Status) return String;
function Status_Image (Status : Find_All_Status) return String;
function Status_Image (Status : Replace_Status) return String;
function Status_Image (Status : Split_Status) return String;
```

Formats status values for diagnostics and examples.
`Is_Syntax_Error`, `Is_Unsupported`, and the overloaded `Is_Limit_Error`
helpers classify statuses for CLI and tooling diagnostics.

### `Debug_Dump`

```ada
procedure Debug_Dump
  (Expression : Regexp;
   Output     : out String;
   Last       : out Natural;
   Status     : out Copy_Status);
```

Writes a deterministic diagnostic dump of the compiled states into a
caller-supplied buffer. This is for tooling and maintainers, not pattern
serialization.

## Match Options

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

`Case_Sensitive` controls ASCII letter matching. The default is
case-insensitive.

```ada
Found := R.Find_First
  (Compiled.Expression,
   "Ada",
   (Case_Sensitive => True, others => <>));
```

`Whole_Word` requires a match to be bounded by non-word characters or text
boundaries. Word characters are ASCII letters, digits, and underscore.

```ada
Found := R.Find_First
  (Compiled.Expression,
   "scatter cat",
   (Whole_Word => True, others => <>));
```

`Dot_Matches_Newline` allows `.` to match LF and CR. The default keeps line
breaks excluded.

`Multiline_Anchors` allows `^` and `$` to match after and before LF/CR. The
default anchors only at the start and end of the whole text.

`Max_Steps` bounds matching work. When the limit is reached, matching returns
`Match_Limit_Exceeded` and records the consumed step count in `Steps_Used`.

`Abort` is an optional callback evaluated during matching. Return `True` to end
matching early. This returns `Match_Limit_Exceeded` and reports the steps
already consumed.

```ada
Found := R.Find_First
  (Compiled.Expression,
   Text,
   (Max_Steps => 5_000, others => <>));
```

## Status Values

Compile statuses:

- `Compile_Ok`
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

Match statuses:

- `Match_Ok`
- `No_Match`
- `Match_Limit_Exceeded`
- `Invalid_Regexp`

## Defaults

```ada
Default_Max_Pattern_Length : constant Positive := 256;
Default_Max_States         : constant Positive := 512;
Default_Max_Steps          : constant Positive := 50_000;
```

Override compile limits per call to `Compile`, and override match step limits
through `Match_Options`.

## Examples

The `examples/` directory contains focused programs:

- `basic_search.adb`: compile a pattern and find the first match.
- `case_sensitivity.adb`: default case-insensitive matching and explicit
  case-sensitive matching.
- `whole_word.adb`: whole-word matching.
- `find_from_offsets.adb`: repeated searching with `Find_From`.
- `find_all_matches.adb`: collecting non-overlapping matches with `Find_All`.
- `matches_entire.adb`: validating that a complete string matches a pattern.
- `character_classes.adb`: ranges, negated classes, and shorthand classes.
- `preset_patterns.adb`: compiling and using built-in preset token patterns.
- `lookaround_options.adb`: lookahead, fixed-width lookbehind, and inline options.
- `search_workflow.adb`: search summary, line ranges, replacement sizing, and limits.
- `advanced_search_planning.adb`: strategy, capture-aware find-all, replacement summary, and stream captures.
- `compile_errors.adb`: handling compile failures and error offsets.
- `step_limit.adb`: bounding match work with `Max_Steps`.

Build them with:

```sh
alr exec -- gprbuild -P examples/examples.gpr
```

## Build And Test

Build the library:

```sh
alr exec -- gprbuild -P regexp.gpr
```

Run the mandatory SPARK proof check when validating a release:

```sh
alr exec -- gnatprove -P regexp.gpr --level=4
```

Run the root Alire test action:

```sh
alr test
```

Build tests when AUnit is available:

```sh
cd tests && alr exec -- gprbuild -P tests.gpr
tests/bin/tests
```

Run the project-tools-backed release checklist:

```sh
alr exec -- gprbuild -P tools/tools.gpr
tools/bin/check_all
```

The checklist builds the library, examples, AUnit tests, runs `alr test`,
requires Alire GNAT 15, runs GNATprove through `alr exec`, and runs the `check_regexp` documentation/release-surface
checker. `check_regexp` is an internal tooling crate that depends on
`project_tools` for shared file and text assertions.
It also verifies documented example output, checks the staged release manifest
workflow, rejects nonempty captured stderr artifacts, and finishes by requiring
a clean Git worktree. Run it after committing intended changes.

`check_regexp/alire.toml` is the development manifest and keeps local workspace
pins for `regexp` and `project_tools`. `check_regexp/alire.release.toml` is the
pin-free release manifest template. During validation, `check_regexp` stages
fresh `regexp` and `project_tools` source trees under `/tmp`, copies the release
manifest as the staged publish manifest, writes a local `alire.build.toml`
overlay with workspace pins, activates that overlay, and builds the staged
checker.

## Limitations

This is intentionally not a full Perl-compatible regular-expression engine.
It favors a small API, bounded compilation and matching, and predictable behavior.
Use `Compile_Result.Status` to reject unsupported patterns before matching.

## License

Dual licensed under either the MIT license or the Apache License, Version 2.0
with LLVM Exceptions. See [`LICENSE`](LICENSE).
