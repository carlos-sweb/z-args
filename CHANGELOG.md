# Changelog

## 0.1.0 — 2026-10-12

Initial release of the command-line parsing ladder:

- Simple: allocation-free POSIX/GNU option tokenization.
- Builder: runtime registration, usage generation, and requires/conflicts rules.
- Declarative: typed struct parsing, defaults, required fields, and rest collectors.
- Commands: static subcommand trees with aliases and leaf callbacks.
- Process argument collection shared by all tiers.

Requires Zig 0.17.0. Migrates array repetition to `@splat` and struct reflection
to `std.lang.Type.Struct` field name/type arrays. Public parsing APIs are unchanged.

Native API documentation is generated with `zig build docs` and published at
https://carlos-sweb.github.io/z-args/. CI runs the test suite in Debug, ReleaseSafe,
ReleaseFast, and ReleaseSmall before deploying the documentation.
