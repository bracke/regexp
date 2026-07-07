# SPARK and GNATprove

Regexp is intended to be SPARK-checkable as a small bounded regular-expression
engine. The public specification and implementation use `SPARK_Mode => On`;
matching and compilation are bounded by public defaults so editor/project-search
callers can avoid unbounded work.

The release proof command is:

```sh
alr exec -- gnatprove -P regexp.gpr --level=4
```

This command is mandatory for release validation. The aggregate release checker
`tools/bin/check_all` must fail when Alire GNAT 15 cannot run GNATprove rather
than silently skipping proof or using a system GNATprove.

Current SPARK-enabled units:

- `Regexp` specification
- `Regexp` body
- `Ada_Regexp` compatibility package

When new APIs are added, keep proof scope explicit: prefer bounded data
structures, total status-returning operations, and deterministic failure
statuses over exceptions for ordinary user input.
