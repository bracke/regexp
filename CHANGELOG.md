# Changelog

All notable changes to regexp are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to adhere
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
