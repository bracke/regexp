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

### `Match_Options`

```ada
type Match_Options is record
   Case_Sensitive : Boolean := False;
   Whole_Word     : Boolean := False;
   Max_Steps      : Natural := 50_000;
end record;
```

## Constants

```ada
Default_Max_Pattern_Length : constant Positive := 256;
Default_Max_States         : constant Positive := 512;
Default_Max_Steps          : constant Positive := 50_000;
```

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
```

Returns a human-readable status string.

## Syntax Scope

`Regexp` intentionally supports a compact, bounded syntax for editor and
project-search style workloads. Grouping, alternation, and bounded repeats are
reported as `Unsupported_Syntax`; adding them should preserve bounded compile
size, deterministic error offsets, and match step-limit behavior.
