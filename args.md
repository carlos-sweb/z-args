# Argument-parsing library patterns (args parser)

Research on the variants/styles found in real libraries (C, C++, Zig, Rust, Go), classified by design pattern.

## 1. Macros + imperative switch (Plan 9 / suckless style)

**Examples:** `arg.h` (suckless, ~20 lines), used in `st`, `dwm`, `sbase`.

The programmer manually writes a `switch` over the option character, wrapped in `ARGBEGIN`/`ARGEND` macros. `ARGF()`/`EARGF()` extract the option's value.

```c
ARGBEGIN {
case 'a':
    argument = EARGF(usage());
    break;
case 'b':
    flag = 1;
    break;
default:
    usage();
} ARGEND
```

## 2. Builder / fluent API (imperative argument registration)

**Examples:** `argh` (adishavit), `args-parser` (igormironchik), `p-ranav/argparse`, `cxx_argp`.

A parser object is built and arguments are added one by one with chainable methods before calling `parse()`.

```cpp
argh::parser cmdl(argv);
if (cmdl[{"-v", "--verbose"}]) { ... }
```

## 3. "add_arg"-style macro registration (single-header, dynamic table)

**Examples:** `argl.h`, `cargs` (stb-style), `stb_argparse.h`.

Similar to the builder, but in pure C via `add_arg(name, letter, type, required, default)` functions that register into an internal table; then typed getters (`argl_get_int`, etc.).

## 4. X-Macros / code generation (struct + parsing in a single definition)

**Examples:** `easy-args` (gouwsxander).

Arguments are defined once with macros (`REQUIRED_STRING_ARG`, `OPTIONAL_UINT_ARG`, `BOOLEAN_ARG`) that simultaneously expand into: struct fields, parsing logic, and help text. Avoids duplication but is hard to debug due to macro indirection.

## 5. Text DSL parsed at comptime (string-driven declarative)

**Examples:** `zig-clap` (Hejsil).

Parameters are described as a "man page"-style string parsed at compile time (`parseParamsComptime`), automatically generating the result type.

```zig
const params = comptime clap.parseParamsComptime(
    \\-h, --help             Show help.
    \\-n, --number <usize>   A numeric value.
    \\
);
```

## 6. Declarative struct/reflection (comptime over a type, no text DSL)

**Examples:** `zig-args` (MasterQ32), Rust `clap` in `derive` mode.

Instead of a string, a normal language `struct` is defined (or annotated with macros/derive), and the library uses reflection/comptime to generate the parser from the fields and their types.

## 7. Classic getopt/getopt_long (POSIX standard)

**Examples:** libc's `getopt`, `getopt_long`.

A manual loop repeatedly calls the function, which returns the next option found and sets global variables (`optarg`, `optind`). The "lowest level" and the historical basis for almost everything else.

## 8. Command/subcommand tree (full CLI framework)

**Examples:** Rust's `clap` (builder or derive with subcommands), `cobra` (Go), a clap-rs-inspired Zig design seen on Ziggit.

Each subcommand is a node with its own arguments, enabling CLIs like `git commit -m "..."`. Usually combined with the builder or declarative pattern (#2 or #6).

---

## Comparison table

| # | Pattern | Examples | Pros | Cons |
|---|--------|----------|------|---------|
| 1 | Macros + imperative switch | arg.h (suckless) | Zero dependencies, minimal binary, full control of flow, very readable for idiomatic suckless C | Single-character flags only, no native `--long=value`, no auto-generated help, fragile macros (mutate global `argv`/`argc`) |
| 2 | Builder / fluent API | argh, args-parser, p-ranav/argparse, cxx_argp | Easy to read and write, good modern type support (C++17), extensible at runtime | Requires C++ (STL, templates), object overhead, help must be configured separately in several of them |
| 3 | add_arg + dynamic table | argl.h, cargs (stb-style) | Simple to integrate (single header, pure C), decent auto-generated help, explicit per-parameter typing | Fixed-size or internally opaque dynamic table, string-named getters (no compile-time checking) |
| 4 | X-Macros (struct+parse in one definition) | easy-args | Eliminates duplication (one source of truth), auto-generates struct + parsing + help | Painful debugging (unclear macro errors), requires understanding the preprocessor, not very flexible outside the intended mold |
| 5 | Text DSL at comptime | zig-clap | Very compact and readable (looks like the `--help` page), strong types generated automatically, zero runtime cost | The text DSL is a separate "mini-language" you have to learn; DSL syntax errors are reported at compile time but less clearly than a normal type error |
| 6 | Declarative struct/reflection | zig-args, Rust clap derive | Arguments are a normal language struct (autocomplete, safe refactoring), very idiomatic | Less fine-grained control over unusual parsing cases, reflection "magic" can be opaque to debug |
| 7 | getopt/getopt_long | libc | POSIX standard, available on any Unix system with no dependencies, very predictable | Low-level API, verbose, no types, no help or subcommands, everything else has to be reimplemented by hand |
| 8 | Command/subcommand tree | clap (Rust), cobra (Go) | Scales well to large CLIs (`git`, `docker`), separates responsibilities per subcommand, contextual help per level | Higher initial configuration complexity, can be "too much" for small single-command tools |

## The 10 most-used languages (TIOBE, July 2026) and their args-parsing libraries

Ranking per the TIOBE Index, July 2026: Python, C, C++, Java, C#, JavaScript, Visual Basic, SQL, R, Rust.

| # | Language | Args-parsing library/ies | Pattern (from the table above) |
|---|----------|------------------------------|----------------------------------|
| 1 | Python | `argparse` (stdlib) | #2 Builder / fluent API |
| 1 | Python | `click`, `typer` | #6 Declarative struct/reflection (decorators + type hints) |
| 1 | Python | `docopt` | #5 Text DSL (usage string), runtime variant instead of comptime |
| 1 | Python | `getopt` (stdlib) | #7 Classic getopt |
| 2 | C | `arg.h` (suckless) | #1 Macros + imperative switch |
| 2 | C | `argl.h`, `cargs` | #3 add_arg + dynamic table |
| 2 | C | `getopt`/`getopt_long` (libc) | #7 Classic getopt |
| 3 | C++ | `argh`, `args-parser`, `p-ranav/argparse`, `cxx_argp` | #2 Builder / fluent API |
| 3 | C++ | `easy-args` (a C library, but applies equally in C++) | #4 X-Macros |
| 4 | Java | `JCommander`, `picocli`, `args4j` | #6 Declarative struct/reflection (variant: field annotations instead of type hints) |
| 4 | Java | `Apache Commons CLI` | #2 Builder / fluent API |
| 5 | C# | `System.CommandLine` | #2 Builder / fluent API (with extensions supporting #8 subcommands) |
| 5 | C# | `CommandLineParser` (CommandLine.dll) | #6 Declarative struct/reflection (property attributes) |
| 6 | JavaScript/TypeScript | `commander.js` | #2 Builder / fluent API, with a strong focus on #8 subcommands (git-style) |
| 6 | JavaScript/TypeScript | `yargs` | #2 Builder / fluent API, lower-level and more configurable |
| 7 | Visual Basic | `System.CommandLine`, `CommandLineParser` (same as the .NET ecosystem) | #2 and #6 (shares runtime with C#) |
| 8 | SQL | Not applicable: SQL is a query language, it doesn't have command-line programs of its own. Client tools (`psql`, `sqlcmd`, `mysql`) use the libraries of whatever language they're written in (typically C or C#), not a "SQL" library. | — |
| 9 | R | `optparse` | #2 Builder / fluent API (directly inspired by Python's `optparse`) |
| 9 | R | `argparse` (R package) | #2 Builder / fluent API, a wrapper over Python's argparse |
| 10 | Rust | `clap` (builder mode) | #2 Builder / fluent API |
| 10 | Rust | `clap` (`derive` mode) | #6 Declarative struct/reflection (`#[derive(Parser)]` macro over a struct) |

### Observation

Pattern **#2 (Builder/fluent API)** is by far the most repeated across the 10 languages: it shows up in Python, C++, Java, C#, JavaScript, R, and Rust. The second most common is **#6 (declarative struct/reflection)**, which takes a different shape in each language depending on its metaprogramming capabilities: decorators + type hints in Python, annotations in Java and C#, derive macros in Rust. The more "artisanal" patterns (#1 macros+switch, #3 add_arg, #4 X-Macros) are nearly exclusive to C, where there's no native support for powerful metaprogramming.

## Per-language detail: justified classification, real execution examples, and scope

This section expands on the table above: for each library it explains **why** it's classified under its pattern (not just the number), shows a **minimal code + real shell invocation** example, and describes its **scope** (what size of CLI it's for, what it solves, and what it doesn't).

### 1. Python

**`argparse` (stdlib) — Pattern #2 (Builder / fluent API)**
- *Why:* an `ArgumentParser` object is instantiated and arguments are added one by one with `add_argument(...)` — exactly the same imperative registration flow as `argh` in C++. There's no reflection-based generation: the programmer explicitly describes each flag at runtime.
- *Example:*
  ```python
  import argparse
  parser = argparse.ArgumentParser(prog="myapp")
  parser.add_argument("-v", "--verbose", action="store_true")
  parser.add_argument("file")
  args = parser.parse_args()
  ```
  ```bash
  $ python myapp.py -v data.csv
  ```
- *Scope:* included in the stdlib (zero dependencies), auto-generates `--help`, supports subcommands via `add_subparsers()` (edges into pattern #8 territory). The reasonable default for any small-to-medium Python CLI.

**`click`, `typer` — Pattern #6 (Declarative struct/reflection)**
- *Why:* in `click` a function is decorated with `@click.option(...)` and the framework itself inspects the signature to inject the parsed values as function arguments; in `typer` the parameters' **type hints** (`bool`, `int`, `str`) are read directly, with no per-option decorator — the same way `zig-args` reads a struct's fields. The source of truth is the function/type signature, not a sequence of builder calls.
- *Example (typer):*
  ```python
  import typer
  def main(verbose: bool = False, file: str = ""):
      if verbose: print("verbose mode")
  if __name__ == "__main__":
      typer.run(main)
  ```
  ```bash
  $ python myapp.py --verbose data.csv
  ```
- *Scope:* requires an external dependency (`pip install click`/`typer`). `click` is the de facto standard for medium-to-large Python CLIs with subcommands (used by Flask, Black, etc.); `typer` targets the same audience but prioritizes type inference and less boilerplate.

**`docopt` — Pattern #5 (text DSL), runtime variant**
- *Why:* shares the core idea of `zig-clap` (the help text **is** the specification), but since Python has no comptime, the docstring is parsed at runtime with a grammar/regex engine instead of generating types at compile time.
- *Example:*
  ```python
  """Usage: myapp.py [-v] <file>"""
  from docopt import docopt
  args = docopt(__doc__)
  ```
  ```bash
  $ python myapp.py -v data.csv
  ```
- *Scope:* ideal for small CLIs where the `--help` and the parser must literally be the same text with no duplication; loses steam on large CLIs because the text DSL becomes hard to maintain and there's no type checking.

**`getopt` (stdlib) — Pattern #7 (classic getopt)**
- *Why:* a direct wrapper around POSIX `getopt`/`getopt_long` semantics: it returns a list of `(option, value)` tuples that must be walked and interpreted by hand in a loop, just like in C.
- *Example:*
  ```python
  import getopt, sys
  opts, args = getopt.getopt(sys.argv[1:], "v", ["verbose"])
  for opt, val in opts:
      if opt in ("-v", "--verbose"):
          print("verbose")
  ```
- *Scope:* only for trivial scripts or for migrating C code to Python while keeping the same parsing logic; `argparse` replaces it in almost all new cases.

### 2. C

**`arg.h` (suckless) — Pattern #1** — already detailed in section 1 of this document. *Scope:* binaries with single-letter flags, no heap, aimed at suckless tools (`st`, `dwm`) where binary size and zero dependencies outweigh features.

**`argl.h`, `cargs` — Pattern #3 (add_arg + dynamic table)**
- *Why:* unlike `arg.h` there's no manual `switch`: an array of options with their metadata (letter, long name, description) is registered, and a library function walks `argv` comparing against that table, also auto-generating `--help`.
- *Example (`cargs`):*
  ```c
  struct cag_option options[] = {
    {.identifier = 'v', .access_letters = "v",
     .access_name = "verbose", .description = "verbose mode"}
  };
  cag_option_context ctx;
  cag_option_init(&ctx, options, CAG_ARRAY_SIZE(options), argc, argv);
  while (cag_option_fetch(&ctx)) {
      if (cag_option_get_identifier(&ctx) == 'v') verbose = 1;
  }
  ```
  ```bash
  $ ./myapp -v data.csv
  ```
- *Scope:* single-header pure C, a good middle ground when `arg.h` falls short (generated `--help` or ergonomic long flags are needed) but adopting C++ isn't desired.

**`getopt`/`getopt_long` (libc) — Pattern #7**
- *Why:* the canonical definition of the pattern: global variables `optarg`/`optind`, a `while ((c = getopt_long(...)) != -1)` loop.
- *Example:*
  ```c
  static struct option long_opts[] = {
      {"verbose", no_argument, 0, 'v'}, {0,0,0,0}
  };
  int c;
  while ((c = getopt_long(argc, argv, "v", long_opts, NULL)) != -1) {
      if (c == 'v') verbose = 1;
  }
  ```
  ```bash
  $ ./myapp --verbose data.csv
  ```
- *Scope:* available on any Unix with nothing to install; the historical base almost everything else in this table was built on or inspired by.

### 3. C++

**`argh`, `args-parser`, `p-ranav/argparse`, `cxx_argp` — Pattern #2**
- *Why:* all four build a runtime parser object and chain/call methods (`add_argument`, `addArgWithFlagAndName`, `operator[]`) before invoking `parse()`; none use reflection over user-defined types — all the CLI's knowledge lives in the builder calls.
- *Example (`p-ranav/argparse`, the closest in spirit to Python's `argparse`):*
  ```cpp
  argparse::ArgumentParser program("myapp");
  program.add_argument("-v", "--verbose").flag();
  program.parse_args(argc, argv);
  bool verbose = program.get<bool>("--verbose");
  ```
  ```bash
  $ ./myapp -v data.csv
  ```
- *Scope:* single-header, require C++17 (except `args-parser`, C++14); `argh` is the most minimalist (no auto-generated help), `argparse` and `args-parser` generate `--help`; `cxx_argp` wraps GNU's `argp.h`, so it inherits its POSIX behavior but with an object-oriented API. Good for medium-sized CLIs without wanting to pull in a large framework like Boost.Program_options.

**`easy-args` — Pattern #4 (X-Macros)** — already detailed in the original section 4.
- *Additional example:*
  ```c
  #define ARGS BOOLEAN_ARG(verbose, 'v', "verbose", "Verbose mode")
  DEFINE_ARGS(ARGS)
  int main(int argc, char **argv) {
      struct Args args = parse_args(argc, argv);
      if (args.verbose) { /* ... */ }
  }
  ```
- *Scope:* applies equally in C++ as in C (it's a C library); useful when a single source of truth for struct+parsing+help is wanted, at the cost of cryptic macro errors.

### 4. Java

**`JCommander`, `picocli`, `args4j` — Pattern #6 (variant: field annotations)**
- *Why:* the programmer declares a normal class with annotated fields (`@Parameter`, `@Option`, `@Argument`) and the library uses runtime reflection (not comptime, since Java doesn't have it) to read those annotations and populate the instance. Same spirit as `zig-args` or `clap derive`, but with dynamic reflection instead of static metaprogramming.
- *Example (`picocli`, which also supports subcommands → touches pattern #8):*
  ```java
  @Command(name = "myapp")
  class MyApp implements Runnable {
      @Option(names = {"-v", "--verbose"}) boolean verbose;
      public void run() { if (verbose) System.out.println("verbose"); }
  }
  public class Main {
      public static void main(String[] args) {
          new CommandLine(new MyApp()).execute(args);
      }
  }
  ```
  ```bash
  $ java Main -v
  ```
- *Scope:* require a dependency (Maven/Gradle); `picocli` is the most complete (shell autocompletion, colors, git-style nested subcommands), `JCommander` and `args4j` are lighter and older.

**`Apache Commons CLI` — Pattern #2 (Builder / fluent API)**
- *Why:* no annotations; an `Options` object is built and options are added with `addOption(...)` before parsing with `DefaultParser`.
- *Example:*
  ```java
  Options options = new Options();
  options.addOption("v", "verbose", false, "verbose mode");
  CommandLine cmd = new DefaultParser().parse(options, args);
  boolean verbose = cmd.hasOption("v");
  ```
- *Scope:* the "classic" Java library, predates the annotation-based ones; a more verbose API but with no reflection magic, useful when explicit control is preferred.

### 5. C#

**`System.CommandLine` — Pattern #2, with extensions toward #8**
- *Why:* `Option<T>` and `Command` objects are built and added to a `RootCommand` via chained calls; nesting `Command`s inside `Command`s produces a subcommand tree (pattern #8) mounted on the same builder.
- *Example:*
  ```csharp
  var verboseOption = new Option<bool>("--verbose");
  var root = new RootCommand { verboseOption };
  root.SetHandler(v => Console.WriteLine(v), verboseOption);
  return root.Invoke(args);
  ```
  ```bash
  $ ./myapp --verbose
  ```
- *Scope:* Microsoft's official library for .NET CLIs; generates `--help`, shell autocompletion, and type validation; the choice when the .NET equivalent of `clap`/`cobra` is wanted.

**`CommandLineParser` (CommandLine.dll) — Pattern #6 (property attributes)**
- *Why:* a POCO class is defined with annotated properties `[Option('v', "verbose")]`, and the library uses reflection to populate it from `args`, analogous to `args4j`/`picocli` in Java.
- *Example:*
  ```csharp
  class Options { [Option('v', "verbose")] public bool Verbose { get; set; } }
  Parser.Default.ParseArguments<Options>(args)
      .WithParsed(o => { if (o.Verbose) Console.WriteLine("verbose"); });
  ```
- *Scope:* a community alternative older than `System.CommandLine`, popular in small/medium projects for its declarative brevity.

### 6. JavaScript / TypeScript

**`commander.js` — Pattern #2, with a strong focus on #8 (git-style subcommands)**
- *Why:* everything is registered on a `program` object by chaining `.option()`/`.command()`, but its main use case and documentation revolve around building subcommand trees (`git`-like), so in practice it lives between #2 and #8.
- *Example:*
  ```javascript
  const { program } = require('commander');
  program.option('-v, --verbose').command('build')
      .action(() => console.log('building...'));
  program.parse();
  ```
  ```bash
  $ node myapp.js build -v
  ```
- *Scope:* the most popular CLI library in the Node ecosystem; auto-generates help and subcommand suggestions.

**`yargs` — Pattern #2, lower-level and more configurable**
- *Why:* the same chainable builder style (`.option()`, `.command()`, `.demandOption()`), but exposes finer-grained control (custom validation, type coercion, middlewares) at the cost of more explicit configuration than `commander.js`.
- *Example:*
  ```javascript
  const argv = require('yargs/yargs')(process.argv.slice(2))
      .option('verbose', { alias: 'v', type: 'boolean' }).argv;
  ```
  ```bash
  $ node myapp.js -v
  ```
- *Scope:* preferred when complex validation/parsing is needed (arrays, coercion, dynamic commands) that `commander.js` doesn't cover as directly.

### 7. Visual Basic

**`System.CommandLine`, `CommandLineParser` — same libraries as section 5, VB syntax**
- *Why:* Visual Basic .NET shares the same CLR and the same libraries as C#; only the host language's syntax changes, not the library's design pattern.
- *Example (`CommandLineParser` in VB):*
  ```vb
  Class Options
      <[Option]("v", "verbose")>
      Public Property Verbose As Boolean
  End Class
  Parser.Default.ParseArguments(Of Options)(args) _
      .WithParsed(Sub(o) If o.Verbose Then Console.WriteLine("verbose"))
  ```
- *Scope:* identical to C# (#5): useful in shops already running VB.NET on modern .NET, with no language-specific libraries of its own.

### 8. SQL

Doesn't apply directly: SQL is an embedded query language, it doesn't compile into binaries with `argv`. But it's worth looking at what its most common CLI clients use, since it illustrates how the same problem is solved in each tool's actual implementation language:
- `psql` (PostgreSQL) is written in C and uses `getopt_long` — pattern **#7**.
- `mysql` (MySQL client) is written in C and uses `my_getopt`, its own reimplementation of `getopt_long` — pattern **#7**.
- Modern `sqlcmd` (Microsoft's Go rewrite, `go-sqlcmd`) uses `spf13/cobra` — pattern **#8** mounted on a builder.
- *Scope:* confirms the general observation: the pattern depends on the tool's implementation language, not the query language it exposes.

### 9. R

**`optparse` — Pattern #2 (Builder / fluent API)**
- *Why:* explicitly inspired by Python's `optparse`/`argparse`: an `option_list` is built with `make_option(...)` and registered in an `OptionParser`, with `parse_args()` at the end.
- *Example:*
  ```r
  library(optparse)
  option_list <- list(make_option(c("-v", "--verbose"), action = "store_true"))
  parser <- OptionParser(option_list = option_list)
  args <- parse_args(parser)
  ```
  ```bash
  $ Rscript myapp.R --verbose
  ```
- *Scope:* the standard choice for `Rscript` scripts in data-analysis/bioinformatics pipelines.

**`argparse` (R package) — Pattern #2**
- *Why:* an API deliberately modeled after Python's `argparse` (`ArgumentParser()`, `add_argument()`, `parse_args()`); the same imperative, method-by-method registration style.
- *Example:*
  ```r
  library(argparse)
  parser <- ArgumentParser()
  parser$add_argument("-v", "--verbose", action = "store_true")
  args <- parser$parse_args()
  ```
- *Scope:* same audience as `optparse`, chosen when the team already knows Python's `argparse` and wants the same API in R.

### 10. Rust

**`clap` builder mode — Pattern #2**
- *Why:* a `Command` is built and `Arg`s are added one by one by chaining methods before `get_matches()`.
- *Example:*
  ```rust
  let matches = Command::new("myapp")
      .arg(Arg::new("verbose").short('v').long("verbose").action(ArgAction::SetTrue))
      .get_matches();
  ```
  ```bash
  $ ./myapp -v
  ```
- *Scope:* maximum control and dynamic validation (useful when the CLI's structure is decided at runtime).

**`clap` `derive` mode — Pattern #6**
- *Why:* a normal `struct` is annotated with `#[derive(Parser)]` and per-field `#[arg(...)]` attributes; the procedural macro generates the parser at compile time from the struct's types, the same as `zig-args`.
- *Example:*
  ```rust
  #[derive(Parser)]
  struct Cli {
      #[arg(short, long)]
      verbose: bool,
  }
  let cli = Cli::parse();
  ```
- *Scope:* the most idiomatic and widely used option in the modern Rust ecosystem; requires clap's `derive` feature and procedural-macro compilation (somewhat higher compile time).

### Extra (outside the TIOBE top 10, added on request): Crystal and Nim

Although they don't make the July 2026 TIOBE ranking used above, Crystal and Nim are relevant to this project because, like Zig, they're systems languages with compile-time metaprogramming (macros/comptime) — the same ground where `zig-clap` and `zig-args` compete. Worth seeing how they solve the same problem.

**Crystal**

**`OptionParser` (stdlib) — Pattern #2 (Builder / fluent API)**
- *Why:* explicitly modeled on Ruby stdlib's `OptionParser`: an `OptionParser.parse do |parser| ... end` block is opened and each flag is registered inside with `parser.on(...)`, chaining imperative registrations just like `argh` or `argparse`. The block form is Crystal syntactic sugar, but the underlying flow is "create parser → register options one by one → run".
- *Example:*
  ```crystal
  require "option_parser"
  verbose = false
  OptionParser.parse do |parser|
    parser.banner = "Usage: myapp [options]"
    parser.on("-v", "--verbose", "Verbose mode") { verbose = true }
  end
  ```
  ```bash
  $ ./myapp -v
  ```
- *Scope:* included in the stdlib (zero dependencies), generates `--help` from the `banner` + descriptions; enough for most single-purpose Crystal scripts and tools.

**`admiral.cr` — Pattern #6 (Declarative struct/reflection, via macros)**
- *Why:* a class inheriting from `Admiral::Command` is defined, and flags are declared with the `define_flag` macro (analogous to an annotated struct field); Crystal's macro expands, at compile time, the getters, the parsing, and the help — the same as `clap derive` in Rust or `zig-args` with reflection over a struct.
- *Example:*
  ```crystal
  class MyCLI < Admiral::Command
    define_flag verbose : Bool, default: false, short: v, description: "Verbose mode"
    def run
      puts "verbose" if flags.verbose
    end
  end
  MyCLI.run
  ```
  ```bash
  $ ./myapp -v
  ```
- *Scope:* supports subcommands (`define_command`, touching pattern #8, git-style); it's Crystal's "full framework" option, analogous to `picocli`/`clap` — better suited once the CLI grows past a handful of flags.

**Nim**

**`std/parseopt` (stdlib) — Pattern #7 (classic getopt)**
- *Why:* a low-level iterator (`for kind, key, val in getopt(): ...`) that returns the next `argv` token and its type (`cmdShortOption`, `cmdLongOption`, `cmdArgument`), leaving all interpretation to the programmer — the same contract as libc's `getopt`/`getopt_long`, just expressed as an iterator instead of a loop with global variables.
- *Example:*
  ```nim
  import std/parseopt
  var verbose = false
  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      if key == "verbose" or key == "v": verbose = true
    else: discard
  ```
  ```bash
  $ ./myapp -v
  ```
- *Scope:* no external dependencies, but no automatic help or types — the base higher-level Nim libraries are built on, the same way `getopt` is the base in C.

**`cligen` — Pattern #6 (Declarative struct/reflection, via macros over a function signature)**
- *Why:* instead of annotating a struct, a normal Nim `proc` is written with typed parameters and default values; the `dispatch(myProc)` macro inspects that signature at compile time and generates the parser, type conversion, and `--help` automatically. Same reflective spirit as `typer` in Python (read the signature as the source of truth) but resolved at comptime with Nim macros instead of runtime type hints.
- *Example:*
  ```nim
  import cligen
  proc myapp(verbose = false, file = "") =
    if verbose: echo "verbose mode"
  dispatch(myapp)
  ```
  ```bash
  $ ./myapp --verbose --file=data.csv
  ```
- *Scope:* the most popular CLI library in the Nim ecosystem for its very low boilerplate (one function = one full CLI); like other pattern #6 members, offers less fine-grained control over unusual parsing cases than an explicit builder.

**`docopt.nim` — Pattern #5 (text DSL, runtime variant)**
- *Why:* a direct port of Python's `docopt` to the Nim ecosystem: the usage/help string is the specification, parsed at runtime.
- *Scope:* same trade-off as `docopt` in Python — very compact for small CLIs, impractical for large CLIs or complex validation logic.

### Observation (updated with Crystal and Nim)

Including Crystal and Nim reinforces the pattern already seen in Zig: in systems languages with compile-time metaprogramming, the underlying tradeoff is always the same **#2 (explicit builder, more control) vs. #6 (struct/function + reflection/macros, less boilerplate)** — `OptionParser` vs. `admiral.cr` in Crystal, and `parseopt` vs. `cligen` in Nim, exactly replicate the `zig-clap`/`zig-args` tradeoff (though those last two are both declarative relative to each other, #5 vs #6) that motivates this project: an options package in `z-args` should, at minimum, cover the "low-level getopt-style builder" rung (#7), the "imperative builder" rung (#2), and the "struct-declarative" rung (#6) — consistently where the most-used libraries land in each surveyed language.

## `z-args` design plan: real-world scope of each pattern in Zig 0.16

Goal of this section: for each of the 8 patterns (and variant #4, which turns out to be a special case), evaluate **how literally it can be ported to Zig 0.16** given what the language actually offers (comptime, `@typeInfo`, generic structs parameterized by comptime values) and what it **doesn't** offer (a C-style preprocessor, token-pasting macros, attributes/annotations on struct fields like Rust/Java/C#). The result is a proposal of modules (`tiers`) that `z-args` would expose, from simplest to most complete, so the end user only loads the complexity they need — same as the motivating example: start at the equivalent of `arg.h` and climb a rung the day a flag needs to depend on another one.

The whole codebase starts from `std.process.Init` (Zig 0.16, "Juicy Main"): `std.process.Args.Iterator.init(init.minimal.args)` to iterate `argv` lazily (confirmed against real Zig 0.16 stdlib and `z-run`'s own usage — an earlier draft of this note assumed a nonexistent `init.args.iterate()` shape).

### Tier 0 — Pattern #1 (macros + switch) → no library / `z-args` "raw"

- **Real-world scope:** `arg.h`'s ARGBEGIN/ARGEND depend on preprocessor macros with token-pasting and mutation of global `argc`/`argv` — Zig has no preprocessor, so that mechanism **isn't literally portable**. What is 100% idiomatic is the spirit: walking `argv` by hand with an explicit `while` + `switch`, which is just as lightweight in Zig as in C.
- **Sketch:**
  ```zig
  pub fn main(init: std.process.Init) !void {
      var it = std.process.Args.Iterator.init(init.minimal.args);
      _ = it.skip(); // program name
      var verbose = false;
      var out_file: []const u8 = "a.out";
      while (it.next()) |arg| {
          if (std.mem.eql(u8, arg, "-v")) {
              verbose = true;
          } else if (std.mem.eql(u8, arg, "-o")) {
              out_file = it.next() orelse return error.MissingValue;
          } else {
              return error.UnknownFlag;
          }
      }
  }
  ```
- **Conclusion:** doesn't warrant being packaged as a library on its own — at most, `z-args` can offer a minimal helper (`ArgIter` with `.shift()`/`.expect()`, equivalent to `EARGF`) to trim boilerplate without hiding the `switch`. It's the "no abstraction, full control" rung, useful as a reference and for when you don't even want to pay the cost of a generic parser.

### Tier 1 — Pattern #7 (classic getopt) → `z-args/getopt`

- **Real-world scope:** fully portable and genuinely valuable, since Zig **doesn't ship `getopt` in its stdlib**. Reimplementing it in pure Zig (argv permutation, `--` as a terminator, short-flag bundling `-abc`) is useful both as a standalone option (porting C tools 1:1) and as an internal base for the higher tiers.
- **Sketch:**
  ```zig
  pub const Getopt = struct {
      args: [][:0]const u8,
      optstring: []const u8,
      index: usize = 1,
      optarg: ?[:0]const u8 = null,

      pub fn next(self: *Getopt) ?u8 {
          // same semantics as libc's getopt(), no global variables
      }
  };
  ```
- **Conclusion:** the "standard POSIX, no surprises" rung. Low implementation effort, zero dependencies, but inherits the same limitations as in C: no types, no auto-generated help, no subcommands.

### Tier 2 — Patterns #2 + #3 merged (runtime builder) → `z-args/builder`

- **Real-world scope:** in C++, pattern #2 is chained methods, and in C, #3 is free functions (`add_arg`) over a table; that OOP-vs-procedural distinction **disappears in Zig**, where `s.method()` is sugar over `Struct.method(&s)`. A single runtime design (a dynamically populated list of `Option`) covers both patterns at once.
- **Sketch:**
  ```zig
  var parser = z_args.Builder.init(gpa);
  defer parser.deinit();
  try parser.addFlag(.{ .short = 'v', .long = "verbose", .help = "verbose mode" });
  try parser.addOption(.{ .short = 'o', .long = "output", .value_name = "FILE" });
  const result = try parser.parse(args);
  if (result.flag("verbose")) { ... }
  ```
- **Conclusion:** the first rung where it makes sense to hook in **cross-flag validation** — exactly the point where `arg.h` falls short in the motivating example. `.parse()` returns a complete result over which rules like `.requires("output", "verbose")` or `.conflictsWith(...)` can be expressed before it's handed off. Cost: getters are by string name (`result.flag("verbose")`), with no compile-time type checking — same as `cargs` in C.

### Tier 3 — Pattern #5 (comptime text DSL) → `z-args/dsl`

- **Real-world scope:** native Zig territory — comptime string parsing is exactly what `zig-clap` does today, and Zig supports it with no loss of fidelity relative to the original pattern.
- **Sketch:**
  ```zig
  const params = comptime z_args.parseParamsComptime(
      \\-h, --help             Show help.
      \\-v, --verbose          Verbose mode.
      \\-o, --output <str>     Output file.
  );
  const res = try z_args.parseComptime(&params, gpa, args);
  ```
- **Conclusion:** the "compact and self-documenting" rung (the help text and the specification are the same source). The cost is the same as in the original: the DSL is a separate mini-language with its own syntax and its own errors, less ergonomic to debug than a normal Zig type error.

### Tier 4 — Pattern #6 (declarative struct/reflection) → `z-args/declarative`

- **Real-world scope:** feasible via `@typeInfo(T)` over a user-defined struct, evaluated at comptime — what `zig-args` does today. **But there's a real language limitation with no direct equivalent**: unlike Rust (`#[derive(Parser)]` + `#[arg(short, long)]`) or Java/C# (annotations/attributes on the field), **Zig has no system of attributes attachable to a struct field**. There's no way to write something like `@[short('v')] verbose: bool`. There are two real strategies to work around this, both used in practice:
  1. **Parallel "meta" struct** (what `zig-args` does): alongside the data struct, a `const meta = .{ .verbose = .{ .short = 'v', .help = "..." } };` is declared, which the library cross-references with `@typeInfo` of the main struct. Risk: two declarations that must be kept in sync by hand.
  2. **Generic per-field wrapper types**: instead of `verbose: bool`, write `verbose: z_args.Flag(bool, .{ .short = 'v', .help = "..." })`, packing the metadata *inside the type itself* — something Zig allows more directly than Rust/Java thanks to generic types parameterized by comptime values (`fn Flag(comptime T: type, comptime opts: FlagOpts) type`).
  - **Sketch (strategy 2, more idiomatic in Zig since it avoids syncing two declarations):**
    ```zig
    const Cli = struct {
        verbose: z_args.Flag(bool, .{ .short = 'v', .help = "verbose mode" }) = .{ .value = false },
        output: z_args.Flag([]const u8, .{ .short = 'o', .default = "a.out" }) = .{ .value = "a.out" },
    };
    const cli = try z_args.parseStruct(Cli, gpa, args);
    if (cli.verbose.value) { ... }
    ```
- **Conclusion:** the most idiomatic rung (IDE autocomplete, safe refactoring, compile-time-checked types) and the one that **demands the most original design** in Zig, precisely because the metadata mechanism that comes free with annotations in other languages has to be invented here. This should be documented as an explicit `z-args` design decision, not a minor implementation detail.

### Pattern #4 (X-Macros) → doesn't get its own port, absorbed into Tier 4

- **Real-world scope:** the value of X-Macros — a single source of truth generating struct + parsing + help at once — is exactly what pattern #6 already achieves in a language with real comptime, with no need for preprocessor token-pasting tricks. Zig has no text macros, so reproducing X-Macros as-is is neither possible nor desirable.
- **Conclusion:** doesn't warrant its own tier in `z-args`; documented as "already solved by Tier 4" rather than reimplemented.

### Pattern #8 (command/subcommand tree) → `z-args/commands` (orthogonal compositional layer)

- **Real-world scope:** fully feasible, but **not a parsing tier of its own** — rather a layer that wraps either Tier 2 or Tier 4 as each subcommand's "leaf". A `Command` is a node with a name + parser (builder or declarative struct) + a list of sub-`Command`s.
- **Sketch:**
  ```zig
  var root = z_args.Command.init(gpa, "myapp");
  defer root.deinit();
  var commit = try root.addSubcommand("commit");
  try commit.args.addOption(.{ .short = 'm', .long = "message" });
  const invocation = try root.parse(args); // resolves "myapp commit -m '...'"
  ```
- **Conclusion:** offered as an independent, composable module, not as a parsing-complexity rung in itself — same as in `clap`, `picocli`, or `System.CommandLine`, where subcommands are mounted *on top of* the builder or the declarative engine, never replacing the leaf parsing engine.

### Final proposed ladder for `z-args`

**Key reformulation (post-research):** the goal isn't to port the exact syntax of one particular library, but to classify by **functional scope** — what each category solves, not what its API looks like — and give it its own name, independent of any originating library. The validation that this is a real concept and not something invented for this project: **of the languages surveyed, Nim and Crystal are the only two with a "mature" ecosystem covering the full ladder within a single language** (not an isolated library) — `std/parseopt` → `cligen` in Nim, `OptionParser` → `admiral.cr` in Crystal. That's what fixes each category's name and scope; the numbered pattern (#1-#8) from the earlier sections stands as supporting research, not as the final taxonomy.

| Category | Scope | Reference (mature ecosystem) | When it becomes insufficient |
|---|---|---|---|
| **Simple** | POSIX/GNU `getopt_long`-style short/long flag tokenizer. No types, no auto-generated help, no cross-flag validation. | Nim `std/parseopt` | When types, auto-generated help, or cross-flag validation are needed beyond what POSIX defines. |
| **Builder** | Imperative runtime registration, auto-generated help, room for cross-flag validation (`requires`, `conflictsWith`). Results accessed by name (string-keyed), no compile-time type checking. | Crystal `OptionParser` | When the program's own struct should be the single source of truth (no string getters) and compile-time type checking is wanted. |
| **Declarative** | The source of truth is a language type/signature (struct or function), generated at compile time: type-checked, minimal boilerplate. The maturity ceiling for a single command. | Nim `cligen`, Crystal `admiral.cr` | Rarely — the next step is scaling to subcommands. |
| **Commands** (orthogonal) | Subcommand tree, composes over Builder or Declarative as a "leaf". Not a parsing-complexity rung, a separate axis. | `admiral.cr` (`define_command`), `cobra` | N/A |

**"Raw" is dropped as its own category**: iterating `argv` by hand with no library at all is what any language offers by default — it's not something `z-args` should package or name, it's the absence of the library, not a rung of it.

**The comptime text DSL (`zig-clap`) is demoted to an optional/bonus variant**, not part of the ladder's core: neither Nim nor Crystal — the two reference ecosystems — has that rung: neither solves its "middle" range with a separate text mini-language.

**Case study — why classification is by functional scope and not surface syntax (`argh`, C++):** `argh` looks like a Builder because it's an object queried with methods (`cmdl[{"-v","--verbose"}]`), but functionally it satisfies neither of the two traits that define Builder: it doesn't generate `--help`, and there's no schema to attach cross-flag validation to (there's no upfront registration step — it parses `argv` generically and only afterward do you query what showed up). By real scope, `argh` lands in **Simple**: it shares with `getopt` the total absence of help/validation, just with a more convenient query API (multiple aliases, type casting) than C's classic `switch`. Moral: an object with methods isn't automatically a Builder — what defines the category is what it solves, not how it's invoked.

The packaging design recommendation: a single root module `zargs` (not separate per-tier modules via `build.zig.zon`) — Zig only generates code for referenced declarations, so `zargs.Simple` doesn't pay the compilation cost of `Builder`/`Declarative` even though they live in the same module. This also matches the convention of every sibling repo in the `z-*` ecosystem (`z-array`, `z-number`, `z-temporal`, ...): one repo, one root module.

**Implementation status**: `Simple` is implemented (`src/simple.zig`, `src/process.zig`), ground-truthed against real `getopt_long(3)`. `Builder`, `Declarative`, and `Commands` are still research-only — each awaits its own design and implementation session.

## Quick notes

- For C focused on minimal size (suckless style): pattern **#1**.
- For C needing types and automatic help without C++: pattern **#3**.
- For Zig, the typical tradeoff is **#5 (zig-clap)** vs. **#6 (zig-args)**: text DSL vs. native struct.
- For modern C++ with no external dependencies: pattern **#2**.
- For large CLIs with subcommands: pattern **#8**, usually mounted on **#2** or **#6**.
