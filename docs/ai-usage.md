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

Use `Matches_Entire` for validation:

```ada
Found := R.Matches_Entire (Compiled.Expression, Text);
```

## Options

The default options are:

```ada
(Case_Sensitive => False,
 Whole_Word     => False,
 Max_Steps      => 50_000)
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

Bounded matching:

```ada
Found := R.Find_First
  (Compiled.Expression,
   Text,
   (Max_Steps => 10_000, others => <>));
```

If `Found.Status = R.Match_Limit_Exceeded`, inspect `Found.Steps_Used`.

## Supported Syntax

Generate patterns using only:

- Literal characters
- `.`
- `^`
- `$`
- Character classes: `[abc]`, `[^abc]`, `[a-z]`
- Quantifiers: `*`, `+`, `?`
- Shorthand classes: `\d`, `\D`, `\w`, `\W`, `\s`, `\S`
- Escaped metacharacters: `\.`, `\*`, `\+`, `\?`, `\(`, `\)`, `\[`, `\]`,
  `\{`, `\}`, `\\`, `\^`, `\$`

Do not generate grouping, alternation, or bounded repeats:

```text
(abc)     unsupported
a|b       unsupported
a{1,3}    unsupported
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
gprbuild -P regexp.gpr
```

Build examples:

```sh
gprbuild -P examples/examples.gpr
```

Run tests when AUnit is available:

```sh
gprbuild -P tests/tests.gpr
tests/bin/tests
```
