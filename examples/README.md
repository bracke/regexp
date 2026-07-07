# Regexp Examples

Build all examples:

```sh
alr exec -- gprbuild -P examples/examples.gpr
```

Run one example:

```sh
examples/bin/basic_search
```

The examples are intentionally small and independent:

- `basic_search.adb`: compile a pattern and find the first match.

```text basic_search
pattern: a.c
text:    xxabcxx
status:  match ok
first:   3
last:    5
```

- `case_sensitivity.adb`: default case-insensitive matching and explicit case-sensitive matching.

```text case_sensitivity
default match:        match ok
case-sensitive match: no match
```

- `whole_word.adb`: whole-word matching.

```text whole_word
without whole-word: match ok
  first = 2, last = 4
with whole-word:    match ok
  first = 9, last = 11
```

- `find_from_offsets.adb`: repeated searching with `Find_From` and relative offsets.

```text find_from_offsets
text: one two one two
match at first = 5, last = 7
match at first = 13, last = 15
```

- `find_all_matches.adb`: collecting non-overlapping matches with `Find_All`.

```text find_all_matches
text: one two one two
status: find all ok
count:  2
match at first = 5, last = 7
match at first = 13, last = 15
```

- `matches_entire.adb`: validating that a complete string matches a pattern.

```text matches_entire
Ada_2022: match ok
Ada-2022: no match
```

- `character_classes.adb`: ranges, negated classes, set operators, and shorthand classes.

```text character_classes
\d+ in 'abc123':      match ok
\D+ in '123abc':      match ok
0x[0-9A-F]+ in text: match ok
\S+ in spaces+word:  match ok
[a-z--[aeiou]]+ in 'seal': match ok
```

- `preset_patterns.adb`: compile and use built-in preset token patterns.

```text preset_patterns
uuid:  match ok
hex:   match ok
email: match ok
url:   match ok
```

- `lookaround_options.adb`: lookahead, fixed-width lookbehind, and inline options.

```text lookaround_options
lookahead: match ok
lookbehind: match ok
inline options: match ok
```

- `search_workflow.adb`: search summary, line ranges, replacement sizing, and limits.

```text search_workflow
matches:  2
line ranges:  2
replace bytes:  13
limited status: match limit exceeded
```

- `advanced_search_planning.adb`: strategy, capture-aware find-all, replacement summary, and stream captures.

```text advanced_search_planning
strategy: specialized
matches:  2
captures:  2
replacement refs:  2
stream status: stream match
```

- `compile_errors.adb`: handling compile failures and error offsets.

```text compile_errors
pattern '': empty pattern, offset = 0
pattern '\x': invalid escape, offset = 2
pattern '[z-a]': invalid class range, offset = 4
pattern 'a{}': invalid quantifier, offset = 2
```

- `step_limit.adb`: bounding match work with `Max_Steps`.

```text step_limit
status:     match limit exceeded
steps used: 5
```
