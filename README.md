# Regexp

`Regexp` is a small bounded regular-expression engine for Ada. It is designed
for editor and project-search style workloads where predictable limits matter:
compiled patterns have bounded size, matching has a configurable step limit, and
the public API is SPARK-compatible.

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
gprbuild -P regexp.gpr
```

Run the mandatory SPARK proof check when validating a release:

```sh
gnatprove -P regexp.gpr --level=4
```

Run the root Alire test action:

```sh
alr test
```

Build and run the examples:

```sh
gprbuild -P examples/examples.gpr
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
3. Reuse `Compile_Result.Expression` with `Find_First`, `Find_From`, or
   `Matches_Entire`.

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
| `*` | Zero or more of the previous atom |
| `+` | One or more of the previous atom |
| `?` | Zero or one of the previous atom |
| `\d`, `\D` | Digit and non-digit classes |
| `\w`, `\W` | Word and non-word classes |
| `\s`, `\S` | Whitespace and non-whitespace classes |

Escaped literals are supported for regex metacharacters such as `\.`, `\*`,
`\+`, `\?`, `\(`, `\)`, `\[`, `\]`, `\{`, `\}`, `\\`, `\^`, and `\$`.

Unsupported syntax is reported as `Unsupported_Syntax`. This currently includes
grouping, alternation, and bounded repeats. That is an intentional scope choice:
`Regexp` is a bounded search engine for editor/project-search workloads, not a
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
```

Formats status values for diagnostics and examples.

## Match Options

```ada
type Match_Options is record
   Case_Sensitive : Boolean := False;
   Whole_Word     : Boolean := False;
   Max_Steps      : Natural := 50_000;
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

`Max_Steps` bounds matching work. When the limit is reached, matching returns
`Match_Limit_Exceeded` and records the consumed step count in `Steps_Used`.

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
- `matches_entire.adb`: validating that a complete string matches a pattern.
- `character_classes.adb`: ranges, negated classes, and shorthand classes.
- `compile_errors.adb`: handling compile failures and error offsets.
- `step_limit.adb`: bounding match work with `Max_Steps`.

Build them with:

```sh
gprbuild -P examples/examples.gpr
```

## Build And Test

Build the library:

```sh
gprbuild -P regexp.gpr
```

Run the mandatory SPARK proof check when validating a release:

```sh
gnatprove -P regexp.gpr --level=4
```

Run the root Alire test action:

```sh
alr test
```

Build tests when AUnit is available:

```sh
gprbuild -P tests/tests.gpr
tests/bin/tests
```

Run the project-tools-backed release checklist:

```sh
gprbuild -P tools/tools.gpr
tools/bin/check_all
```

The checklist builds the library, examples, AUnit tests, runs `alr test`, requires GNATprove, and runs the `check_regexp`
documentation/release-surface checker. `check_regexp` is an internal tooling
crate that depends on `project_tools` for shared file and text assertions.

## Limitations

This is intentionally not a full Perl-compatible regular-expression engine.
It favors a small API, bounded compilation and matching, and predictable behavior.
Use `Compile_Result.Status` to reject unsupported patterns before matching.

## License

Dual licensed under either the MIT license or the Apache License, Version 2.0
with LLVM Exceptions. See [`LICENSE`](LICENSE).
