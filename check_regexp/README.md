# check_regexp

Internal release and documentation checks for the regexp crate.

This executable is repository tooling. It depends on `regexp` and
`project_tools`, validates release metadata and documentation, runs example
output checks, and exercises the staged build manifest workflow used by release
checks.

Build and run it from this directory:

```sh
alr build
./bin/check_regexp
```

The normal top-level entry point is `tools/bin/check_all`, which builds and runs
this checker as part of the release checklist.

## Manifests

- `alire.toml` is the development manifest. It keeps local workspace pins for
  `regexp` and sibling `project_tools`.
- `alire.release.toml` is the pin-free release manifest template used to verify
  publishable metadata.

During validation, the checker creates `/tmp/regexp-check-regexp-staging`, copies
fresh `regexp` and `project_tools` source trees into that workspace, installs
`alire.release.toml` as the staged `alire.toml`, writes an `alire.build.toml`
overlay with local pins, activates the overlay, builds the staged checker, then
restores the publish manifest and removes the staging tree.
