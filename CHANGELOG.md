# Changelog

All notable changes to regexp are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to adhere
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Matching with captures is around eight times faster.** Three working stores were
  sized by `Default_Max_States` and rebuilt at every starting position a search tried,
  so the cost of a search was set by the ceiling on states rather than by the expression
  in hand. `Add_Capture_State` kept a queue of capture sets beside its queue of states,
  and `Text_Range` carries default component values, so sixty-four kilobytes were
  initialised on entry however the array was declared — ninety-three per cent of the
  time spent matching, by profile. That queue is gone: `Enqueue` has already stored the
  captures in the thread set and a state is enqueued at most once, so they are read back
  from there. `Run_From_With_Captures` and `Run_From` now take their thread and state
  sets from the caller, which initialises them once per search instead of once per
  starting position, and both touch only `State_Count` entries. Clearing a thread writes
  its flag rather than its whole capture set.

  `Run_From` became a procedure with an `out` result, because SPARK does not allow a
  function to take `in out` parameters. Flow analysis reports fewer findings than before
  the change (32, from 36); no behaviour changed, and the suite is unaffected.

### Fixed

- **A literal `p` or `P` in a character class no longer fails to compile.** Inside a
  class the parser tested the *unescaped* character for `p`/`P` and read it as the start
  of a Unicode property, so ordinary sets like `[dp]`, `[pq]` and `[^p]` were rejected as
  malformed properties. The property form is recognised on the escaped character now,
  which is where it was always written. **This changes the class dialect**: a property
  inside a class is `[\p{digit}]`, not `[\\p{digit}]` as before, and a bare `p` in a
  class is the letter. Properties outside a class (`\p{digit}`) are unaffected.

### Added

- **UTF-8 code-point matching.** Compiling a pattern with `Character_Mode => UTF_8_Mode`
  makes the matcher advance and match by code point rather than byte: `.` and
  quantifiers span whole code points, and character classes carry code points — positive
  ranges like `[α-ω]`, negated classes like `[^,]`, and multibyte literals all work.
  Class members above U+00FF are held in a per-`Regexp` interval pool, so the compiled
  state array is unchanged in size. `ASCII_Mode` (the default) is byte-identical, and
  match offsets remain byte offsets in both modes. The engine stays fully proven at
  `gnatprove --level=4`.
- Tri-platform CI: the suite and examples now build and run on Linux, macOS, and Windows
  (previously Linux only).

### Notes

- GNATprove is deliberately not run in CI (regexp's `--level=4` proof exceeds GitHub's
  job limits); it remains the local release gate via `tools/check_all`.
