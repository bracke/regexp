# Regexp Examples

Build all examples:

```sh
gprbuild -P examples/examples.gpr
```

Run one example:

```sh
examples/bin/basic_search
```

The examples are intentionally small and independent:

- `basic_search.adb`: compile a pattern and find the first match.
- `case_sensitivity.adb`: default case-insensitive matching and explicit case-sensitive matching.
- `whole_word.adb`: whole-word matching.
- `find_from_offsets.adb`: repeated searching with `Find_From` and relative offsets.
- `matches_entire.adb`: validating that a complete string matches a pattern.
- `character_classes.adb`: ranges, negated classes, and shorthand classes.
- `compile_errors.adb`: handling compile failures and error offsets.
- `step_limit.adb`: bounding match work with `Max_Steps`.
