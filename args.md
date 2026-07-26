# Patrones de librerías de parseo de argumentos (args parser)

Investigación de variantes/estilos encontrados en librerías reales (C, C++, Zig, Rust, Go), clasificados por patrón de diseño.

## 1. Macros + switch imperativo (estilo Plan 9 / suckless)

**Ejemplos:** `arg.h` (suckless, de 20h), usado en `st`, `dwm`, `sbase`.

El programador escribe manualmente un `switch` sobre el carácter de la opción, envuelto en macros `ARGBEGIN`/`ARGEND`. `ARGF()`/`EARGF()` extraen el valor de la opción.

```c
ARGBEGIN {
case 'a':
    argumento = EARGF(uso());
    break;
case 'b':
    bandera = 1;
    break;
default:
    uso();
} ARGEND
```

## 2. Builder / API fluida (registro imperativo de argumentos)

**Ejemplos:** `argh` (adishavit), `args-parser` (igormironchik), `p-ranav/argparse`, `cxx_argp`.

Se construye un objeto parser y se van agregando argumentos uno a uno con métodos encadenables antes de llamar a `parse()`.

```cpp
argh::parser cmdl(argv);
if (cmdl[{"-v", "--verbose"}]) { ... }
```

## 3. Registro con macros tipo "add_arg" (single-header, tabla dinámica)

**Ejemplos:** `argl.h`, `cargs` (stb-style), `stb_argparse.h`.

Similar al builder, pero en C puro vía funciones `add_arg(nombre, letra, tipo, requerido, default)` que registran en una tabla interna; luego getters tipados (`argl_get_int`, etc.).

## 4. X-Macros / generación de código (struct + parsing en una sola definición)

**Ejemplos:** `easy-args` (gouwsxander).

Se definen los argumentos una sola vez con macros (`REQUIRED_STRING_ARG`, `OPTIONAL_UINT_ARG`, `BOOLEAN_ARG`) que expanden simultáneamente: campos del struct, lógica de parseo y texto de ayuda. Evita duplicación pero es difícil de depurar por la indirección de macros.

## 5. DSL de texto parseado en comptime (string-driven declarativo)

**Ejemplos:** `zig-clap` (Hejsil).

Los parámetros se describen como un string tipo "man page" que se parsea en tiempo de compilación (`parseParamsComptime`) generando el tipo de resultado automáticamente.

```zig
const params = comptime clap.parseParamsComptime(
    \\-h, --help         Muestra ayuda.
    \\-n, --number <usize>  Un valor numérico.
    \\
);
```

## 6. Struct/reflection declarativo (comptime sobre un tipo, sin DSL de texto)

**Ejemplos:** `zig-args` (MasterQ32), `clap` de Rust en modo `derive`.

En vez de un string, se define un `struct` normal del lenguaje (o se anota con macros/derive) y la librería usa reflection/comptime para generar el parser a partir de los campos y sus tipos.

## 7. getopt/getopt_long clásico (estándar POSIX)

**Ejemplos:** `getopt`, `getopt_long` de libc.

Bucle manual que llama repetidamente a la función, la cual va devolviendo la siguiente opción encontrada y setea variables globales (`optarg`, `optind`). Es el "más bajo nivel" y la base histórica de casi todo lo demás.

## 8. Comandos/subcomandos en árbol (framework CLI completo)

**Ejemplos:** `clap` de Rust (builder o derive con subcomandos), `cobra` (Go), un diseño Zig inspirado en clap-rs visto en Ziggit.

Cada subcomando es un nodo con sus propios argumentos, permitiendo CLIs tipo `git commit -m "..."`. Suele combinarse con el patrón builder o declarativo (#2 o #6).

---

## Tabla comparativa

| # | Patrón | Ejemplos | Pros | Contras |
|---|--------|----------|------|---------|
| 1 | Macros + switch imperativo | arg.h (suckless) | Cero dependencias, binario mínimo, control total del flujo, muy legible para C idiomático suckless | Solo flags de un carácter, sin `--largo=valor` nativo, sin ayuda auto-generada, macros frágiles (mutan `argv`/`argc` globales) |
| 2 | Builder / API fluida | argh, args-parser, p-ranav/argparse, cxx_argp | Fácil de leer y escribir, buen soporte de tipos modernos (C++17), extensible en runtime | Requiere C++ (STL, plantillas), overhead de objetos, ayuda debe configurarse aparte en varias de ellas |
| 3 | add_arg + tabla dinámica | argl.h, cargs (stb-style) | Simple de integrar (single header, C puro), ayuda auto-generada decente, tipado explícito por parámetro | Tabla de tamaño fijo o dinámica interna poco visible, getters por nombre de string (sin chequeo en compilación) |
| 4 | X-Macros (struct+parse en 1 definición) | easy-args | Elimina duplicación (1 fuente de verdad), genera struct + parseo + ayuda automáticamente | Debug doloroso (errores de macro poco claros), requiere entender preprocesador, poco flexible fuera del molde previsto |
| 5 | DSL de texto en comptime | zig-clap | Muy compacto y legible (se parece a la página de `--help`), tipado fuerte generado automáticamente, cero costo en runtime | El DSL de texto es un "mini-lenguaje" aparte que hay que aprender, errores de sintaxis del DSL se reportan en tiempo de compilación pero de forma menos clara que un error de tipo normal |
| 6 | Struct/reflection declarativo | zig-args, Rust clap derive | Los argumentos son un struct normal del lenguaje (autocompletado, refactorización segura), muy idiomático | Menos control fino sobre casos raros de parsing, la "magia" de reflection puede ser opaca para debug |
| 7 | getopt/getopt_long | libc | Estándar POSIX, disponible en cualquier sistema Unix sin dependencias, muy predecible | API de bajo nivel, verboso, sin tipos, sin ayuda ni subcomandos, hay que reimplementar todo lo demás a mano |
| 8 | Comandos/subcomandos en árbol | clap (Rust), cobra (Go) | Escala bien a CLIs grandes (`git`, `docker`), separa responsabilidades por subcomando, ayuda contextual por nivel | Mayor complejidad de configuración inicial, puede ser "demasiado" para herramientas pequeñas de un solo comando |

## Los 10 lenguajes más usados (TIOBE, julio 2026) y sus librerías de args parsing

Ranking según TIOBE Index julio 2026: Python, C, C++, Java, C#, JavaScript, Visual Basic, SQL, R, Rust.

| # | Lenguaje | Librería(s) de args parsing | Patrón (de la tabla de arriba) |
|---|----------|------------------------------|----------------------------------|
| 1 | Python | `argparse` (stdlib) | #2 Builder / API fluida |
| 1 | Python | `click`, `typer` | #6 Struct/reflection declarativo (decoradores + type hints) |
| 1 | Python | `docopt` | #5 DSL de texto (usage string), variante en runtime en vez de comptime |
| 1 | Python | `getopt` (stdlib) | #7 getopt clásico |
| 2 | C | `arg.h` (suckless) | #1 Macros + switch imperativo |
| 2 | C | `argl.h`, `cargs` | #3 add_arg + tabla dinámica |
| 2 | C | `getopt`/`getopt_long` (libc) | #7 getopt clásico |
| 3 | C++ | `argh`, `args-parser`, `p-ranav/argparse`, `cxx_argp` | #2 Builder / API fluida |
| 3 | C++ | `easy-args` (aunque es C, aplica igual en C++) | #4 X-Macros |
| 4 | Java | `JCommander`, `picocli`, `args4j` | #6 Struct/reflection declarativo (variante: anotaciones sobre campos en vez de type hints) |
| 4 | Java | `Apache Commons CLI` | #2 Builder / API fluida |
| 5 | C# | `System.CommandLine` | #2 Builder / API fluida (con extensiones que soportan #8 subcomandos) |
| 5 | C# | `CommandLineParser` (CommandLine.dll) | #6 Struct/reflection declarativo (atributos sobre propiedades) |
| 6 | JavaScript/TypeScript | `commander.js` | #2 Builder / API fluida, con fuerte foco en #8 subcomandos (estilo git) |
| 6 | JavaScript/TypeScript | `yargs` | #2 Builder / API fluida, más bajo nivel y configurable |
| 7 | Visual Basic | `System.CommandLine`, `CommandLineParser` (mismas del ecosistema .NET) | #2 y #6 (comparte runtime con C#) |
| 8 | SQL | No aplica: SQL es un lenguaje de consultas, no tiene programas de línea de comandos propios. Las herramientas cliente (`psql`, `sqlcmd`, `mysql`) usan las librerías del lenguaje en que están escritas (típicamente C o C#), no una librería "de SQL". | — |
| 9 | R | `optparse` | #2 Builder / API fluida (inspirada directamente en el `optparse` de Python) |
| 9 | R | `argparse` (paquete de R) | #2 Builder / API fluida, envoltorio sobre el argparse de Python |
| 10 | Rust | `clap` (modo builder) | #2 Builder / API fluida |
| 10 | Rust | `clap` (modo `derive`) | #6 Struct/reflection declarativo (macro `#[derive(Parser)]` sobre struct) |

### Observación

El patrón **#2 (Builder/API fluida)** es, por lejos, el más repetido entre los 10 lenguajes: aparece en Python, C++, Java, C#, JavaScript, R y Rust. El segundo más común es **#6 (struct/reflection declarativo)**, que en cada lenguaje toma una forma distinta según sus capacidades de metaprogramación: decoradores + type hints en Python, anotaciones en Java y C#, macros de derive en Rust. Los patrones más "artesanales" (#1 macros+switch, #3 add_arg, #4 X-Macros) quedan casi exclusivos de C, donde no hay soporte nativo de metaprogramación potente.

## Detalle por lenguaje: clasificación justificada, ejemplos de ejecución y alcance

Esta sección completa la tabla anterior: para cada librería se explica **por qué** se clasifica en su patrón (no solo el número), se muestra un **ejemplo mínimo de código + invocación real por shell**, y se describe su **alcance** (para qué tamaño de CLI sirve, qué resuelve y qué no).

### 1. Python

**`argparse` (stdlib) — Patrón #2 (Builder / API fluida)**
- *Por qué:* se instancia un objeto `ArgumentParser` y se le van agregando argumentos uno a uno con `add_argument(...)`, exactamente el mismo flujo imperativo de registro que `argh` en C++. No hay generación por reflexión: el programador describe cada flag explícitamente en tiempo de ejecución.
- *Ejemplo:*
  ```python
  import argparse
  parser = argparse.ArgumentParser(prog="miapp")
  parser.add_argument("-v", "--verbose", action="store_true")
  parser.add_argument("archivo")
  args = parser.parse_args()
  ```
  ```bash
  $ python miapp.py -v datos.csv
  ```
- *Alcance:* incluida en stdlib (cero dependencias), genera `--help` automáticamente, soporta subcomandos vía `add_subparsers()` (entra en terreno del patrón #8). Es el default razonable para cualquier CLI Python de tamaño pequeño a mediano.

**`click`, `typer` — Patrón #6 (Struct/reflection declarativo)**
- *Por qué:* en `click` se decora una función con `@click.option(...)` y el propio framework inspecciona la firma para inyectar los valores parseados como argumentos de la función; en `typer` directamente se leen los **type hints** de los parámetros (`bool`, `int`, `str`) sin decorador por opción, igual que `zig-args` lee los campos de un struct. La fuente de verdad es la firma de la función/tipo, no una secuencia de llamadas a un builder.
- *Ejemplo (typer):*
  ```python
  import typer
  def main(verbose: bool = False, archivo: str = ""):
      if verbose: print("modo verbose")
  if __name__ == "__main__":
      typer.run(main)
  ```
  ```bash
  $ python miapp.py --verbose datos.csv
  ```
- *Alcance:* requiere dependencia externa (`pip install click`/`typer`). `click` es el estándar de facto para CLIs Python medianas-grandes con subcomandos (usado por Flask, Black, etc.); `typer` apunta a la misma audiencia pero prioriza inferencia de tipos y menos boilerplate.

**`docopt` — Patrón #5 (DSL de texto), variante runtime**
- *Por qué:* comparte la idea central de `zig-clap` (el texto de ayuda **es** la especificación), pero como Python no tiene comptime, el docstring se parsea en tiempo de ejecución con un motor de gramática/regex en vez de generar tipos en compilación.
- *Ejemplo:*
  ```python
  """Uso: miapp.py [-v] <archivo>"""
  from docopt import docopt
  args = docopt(__doc__)
  ```
  ```bash
  $ python miapp.py -v datos.csv
  ```
- *Alcance:* ideal para CLIs pequeñas donde el `--help` y el parser deben ser literalmente el mismo texto sin duplicación; pierde fuerza en CLIs grandes porque el DSL de texto se vuelve difícil de mantener y no hay chequeo de tipos.

**`getopt` (stdlib) — Patrón #7 (getopt clásico)**
- *Por qué:* es un envoltorio directo de la semántica POSIX `getopt`/`getopt_long`: devuelve una lista de tuplas `(opción, valor)` que hay que recorrer e interpretar a mano con un bucle, igual que en C.
- *Ejemplo:*
  ```python
  import getopt, sys
  opts, args = getopt.getopt(sys.argv[1:], "v", ["verbose"])
  for opt, val in opts:
      if opt in ("-v", "--verbose"):
          print("verbose")
  ```
- *Alcance:* solo para scripts triviales o para migrar código C a Python conservando la misma lógica de parseo; `argparse` lo reemplaza en casi todos los casos nuevos.

### 2. C

**`arg.h` (suckless) — Patrón #1** — ya detallado en la sección 1 de este documento. *Alcance:* binarios de una sola letra por flag, sin heap, pensado para herramientas suckless (`st`, `dwm`) donde el tamaño del binario y cero dependencias priman sobre features.

**`argl.h`, `cargs` — Patrón #3 (add_arg + tabla dinámica)**
- *Por qué:* a diferencia de `arg.h` no hay `switch` manual: se registra un arreglo de opciones con su metadata (letra, nombre largo, descripción) y una función de biblioteca recorre `argv` comparando contra esa tabla, generando además `--help` automáticamente.
- *Ejemplo (`cargs`):*
  ```c
  struct cag_option options[] = {
    {.identifier = 'v', .access_letters = "v",
     .access_name = "verbose", .description = "modo verbose"}
  };
  cag_option_context ctx;
  cag_option_init(&ctx, options, CAG_ARRAY_SIZE(options), argc, argv);
  while (cag_option_fetch(&ctx)) {
      if (cag_option_get_identifier(&ctx) == 'v') verbose = 1;
  }
  ```
  ```bash
  $ ./miapp -v datos.csv
  ```
- *Alcance:* single-header en C puro, buen punto intermedio cuando `arg.h` se queda corto (se necesita `--help` generado o flags largas) pero no se quiere adoptar C++.

**`getopt`/`getopt_long` (libc) — Patrón #7**
- *Por qué:* es la definición canónica del patrón: variables globales `optarg`/`optind`, bucle `while ((c = getopt_long(...)) != -1)`.
- *Ejemplo:*
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
  $ ./miapp --verbose datos.csv
  ```
- *Alcance:* disponible en cualquier Unix sin instalar nada; es la base histórica sobre la que casi todo lo demás en esta tabla se construyó o se inspiró.

### 3. C++

**`argh`, `args-parser`, `p-ranav/argparse`, `cxx_argp` — Patrón #2**
- *Por qué:* las cuatro construyen un objeto parser en runtime y encadenan/llaman métodos (`add_argument`, `addArgWithFlagAndName`, `operator[]`) antes de invocar `parse()`; ninguna usa reflexión sobre tipos definidos por el usuario, todo el conocimiento del CLI vive en las llamadas al builder.
- *Ejemplo (`p-ranav/argparse`, el más cercano en espíritu a Python `argparse`):*
  ```cpp
  argparse::ArgumentParser program("miapp");
  program.add_argument("-v", "--verbose").flag();
  program.parse_args(argc, argv);
  bool verbose = program.get<bool>("--verbose");
  ```
  ```bash
  $ ./miapp -v datos.csv
  ```
- *Alcance:* single-header, requieren C++17 (salvo `args-parser`, C++14); `argh` es el más minimalista (sin ayuda auto-generada), `argparse` y `args-parser` generan `--help`; `cxx_argp` envuelve `argp.h` de GNU por lo que hereda su comportamiento POSIX pero con API orientada a objetos. Buenos para CLIs medianas sin querer traer un framework grande como Boost.Program_options.

**`easy-args` — Patrón #4 (X-Macros)** — ya detallado en la sección 4 original.
- *Ejemplo adicional:*
  ```c
  #define ARGS BOOLEAN_ARG(verbose, 'v', "verbose", "Modo verbose")
  DEFINE_ARGS(ARGS)
  int main(int argc, char **argv) {
      struct Args args = parse_args(argc, argv);
      if (args.verbose) { /* ... */ }
  }
  ```
- *Alcance:* aplica igual en C++ que en C (es una librería C); útil cuando se quiere una única fuente de verdad para struct+parseo+ayuda, a costa de que los errores de macro son crípticos.

### 4. Java

**`JCommander`, `picocli`, `args4j` — Patrón #6 (variante: anotaciones sobre campos)**
- *Por qué:* el programador declara una clase normal con campos anotados (`@Parameter`, `@Option`, `@Argument`) y la librería usa reflexión en runtime (no comptime, porque Java no lo tiene) para leer esas anotaciones y poblar la instancia. Es el mismo espíritu que `zig-args` o `clap derive`, pero con reflexión dinámica en vez de metaprogramación estática.
- *Ejemplo (`picocli`, además soporta subcomandos → toca el patrón #8):*
  ```java
  @Command(name = "miapp")
  class MiApp implements Runnable {
      @Option(names = {"-v", "--verbose"}) boolean verbose;
      public void run() { if (verbose) System.out.println("verbose"); }
  }
  public class Main {
      public static void main(String[] args) {
          new CommandLine(new MiApp()).execute(args);
      }
  }
  ```
  ```bash
  $ java Main -v
  ```
- *Alcance:* requieren dependencia (Maven/Gradle); `picocli` es el más completo (autocompletado de shell, colores, subcomandos anidados tipo git), `JCommander` y `args4j` son más ligeras y antiguas.

**`Apache Commons CLI` — Patrón #2 (Builder / API fluida)**
- *Por qué:* no hay anotaciones; se construye un objeto `Options` y se agregan opciones con `addOption(...)` antes de parsear con `DefaultParser`.
- *Ejemplo:*
  ```java
  Options options = new Options();
  options.addOption("v", "verbose", false, "modo verbose");
  CommandLine cmd = new DefaultParser().parse(options, args);
  boolean verbose = cmd.hasOption("v");
  ```
- *Alcance:* la librería Java "clásica", predatan las de anotaciones; API más verbosa pero sin magia de reflexión, útil cuando se prefiere control explícito.

### 5. C#

**`System.CommandLine` — Patrón #2, con extensiones hacia #8**
- *Por qué:* se construyen objetos `Option<T>` y `Command` y se agregan a un `RootCommand` mediante llamadas encadenadas; cuando se anidan `Command` dentro de `Command` se obtiene un árbol de subcomandos (patrón #8) montado sobre el mismo builder.
- *Ejemplo:*
  ```csharp
  var verboseOption = new Option<bool>("--verbose");
  var root = new RootCommand { verboseOption };
  root.SetHandler(v => Console.WriteLine(v), verboseOption);
  return root.Invoke(args);
  ```
  ```bash
  $ ./miapp --verbose
  ```
- *Alcance:* librería oficial de Microsoft para CLIs .NET; genera `--help`, autocompletado de shell y validación de tipos; es la elegida cuando se quiere el equivalente .NET de `clap`/`cobra`.

**`CommandLineParser` (CommandLine.dll) — Patrón #6 (atributos sobre propiedades)**
- *Por qué:* se define una clase POCO con propiedades anotadas `[Option('v', "verbose")]` y la librería usa reflexión para poblarla desde `args`, análogo a `args4j`/`picocli` en Java.
- *Ejemplo:*
  ```csharp
  class Options { [Option('v', "verbose")] public bool Verbose { get; set; } }
  Parser.Default.ParseArguments<Options>(args)
      .WithParsed(o => { if (o.Verbose) Console.WriteLine("verbose"); });
  ```
- *Alcance:* alternativa comunitaria más antigua que `System.CommandLine`, popular en proyectos pequeños/medianos por su brevedad declarativa.

### 6. JavaScript / TypeScript

**`commander.js` — Patrón #2, con fuerte foco en #8 (subcomandos estilo git)**
- *Por qué:* se registra todo sobre un objeto `program` encadenando `.option()`/`.command()`, pero su caso de uso principal y su documentación giran en torno a construir árboles de subcomandos (`git`-like), por lo que en la práctica vive a caballo entre #2 y #8.
- *Ejemplo:*
  ```javascript
  const { program } = require('commander');
  program.option('-v, --verbose').command('build')
      .action(() => console.log('building...'));
  program.parse();
  ```
  ```bash
  $ node miapp.js build -v
  ```
- *Alcance:* la librería CLI más popular del ecosistema Node; genera ayuda y sugerencias de subcomando automáticamente.

**`yargs` — Patrón #2, más bajo nivel y configurable**
- *Por qué:* mismo estilo builder encadenable (`.option()`, `.command()`, `.demandOption()`), pero expone más control fino (validaciones custom, coerción de tipos, middlewares) a costa de más configuración explícita que `commander.js`.
- *Ejemplo:*
  ```javascript
  const argv = require('yargs/yargs')(process.argv.slice(2))
      .option('verbose', { alias: 'v', type: 'boolean' }).argv;
  ```
  ```bash
  $ node miapp.js -v
  ```
- *Alcance:* preferida cuando se necesita validación/parseo complejo (arrays, coerción, comandos dinámicos) que `commander.js` no cubre de forma tan directa.

### 7. Visual Basic

**`System.CommandLine`, `CommandLineParser` — mismas librerías del punto 5, sintaxis VB**
- *Por qué:* Visual Basic .NET comparte el mismo CLR y las mismas librerías que C#; solo cambia la sintaxis del lenguaje anfitrión, no el patrón de diseño de la librería.
- *Ejemplo (`CommandLineParser` en VB):*
  ```vb
  Class Options
      <[Option]("v", "verbose")>
      Public Property Verbose As Boolean
  End Class
  Parser.Default.ParseArguments(Of Options)(args) _
      .WithParsed(Sub(o) If o.Verbose Then Console.WriteLine("verbose"))
  ```
- *Alcance:* idéntico al de C# (#5): útil en shops que ya usan VB.NET sobre .NET moderno, sin librerías propias del lenguaje.

### 8. SQL

No aplica directamente: SQL es un lenguaje de consultas embebido, no compila a binarios con `argv`. Pero vale la pena mirar qué usan sus clientes CLI más comunes, porque ilustra cómo el mismo problema se resuelve en el lenguaje real de implementación de cada herramienta:
- `psql` (PostgreSQL) está escrito en C y usa `getopt_long` — patrón **#7**.
- `mysql` (cliente MySQL) está escrito en C y usa `my_getopt`, una reimplementación propia de `getopt_long` — patrón **#7**.
- `sqlcmd` moderno (reescritura Microsoft en Go, `go-sqlcmd`) usa `spf13/cobra` — patrón **#8** montado sobre builder.
- *Alcance:* confirma la observación general: el patrón depende del lenguaje de implementación de la herramienta, no del lenguaje de consulta que expone.

### 9. R

**`optparse` — Patrón #2 (Builder / API fluida)**
- *Por qué:* inspirada explícitamente en el `optparse`/`argparse` de Python: se arma una `option_list` con `make_option(...)` y se registra en un `OptionParser`, con `parse_args()` al final.
- *Ejemplo:*
  ```r
  library(optparse)
  option_list <- list(make_option(c("-v", "--verbose"), action = "store_true"))
  parser <- OptionParser(option_list = option_list)
  args <- parse_args(parser)
  ```
  ```bash
  $ Rscript miapp.R --verbose
  ```
- *Alcance:* la opción estándar para scripts `Rscript` en pipelines de análisis de datos/bioinformática.

**`argparse` (paquete de R) — Patrón #2**
- *Por qué:* API deliberadamente calcada del `argparse` de Python (`ArgumentParser()`, `add_argument()`, `parse_args()`); mismo estilo imperativo de registro método a método.
- *Ejemplo:*
  ```r
  library(argparse)
  parser <- ArgumentParser()
  parser$add_argument("-v", "--verbose", action = "store_true")
  args <- parser$parse_args()
  ```
- *Alcance:* misma audiencia que `optparse`, elegida cuando el equipo ya conoce el `argparse` de Python y quiere la misma API en R.

### 10. Rust

**`clap` modo builder — Patrón #2**
- *Por qué:* se construye un `Command` y se le agregan `Arg` uno a uno encadenando métodos antes de `get_matches()`.
- *Ejemplo:*
  ```rust
  let matches = Command::new("miapp")
      .arg(Arg::new("verbose").short('v').long("verbose").action(ArgAction::SetTrue))
      .get_matches();
  ```
  ```bash
  $ ./miapp -v
  ```
- *Alcance:* máximo control y validaciones dinámicas (útil cuando la estructura del CLI se decide en runtime).

**`clap` modo `derive` — Patrón #6**
- *Por qué:* se anota un `struct` normal con `#[derive(Parser)]` y atributos `#[arg(...)]` por campo; el macro procedural genera el parser en tiempo de compilación a partir de los tipos del struct, igual que `zig-args`.
- *Ejemplo:*
  ```rust
  #[derive(Parser)]
  struct Cli {
      #[arg(short, long)]
      verbose: bool,
  }
  let cli = Cli::parse();
  ```
- *Alcance:* la opción más idiomática y usada en el ecosistema Rust moderno; requiere el feature `derive` de `clap` y compilación de macros procedurales (tiempo de compilación algo mayor).

### Extra (fuera del top 10 TIOBE, agregados a pedido): Crystal y Nim

Aunque no entran en el ranking TIOBE de julio 2026 usado arriba, Crystal y Nim son relevantes para este proyecto porque, como Zig, son lenguajes de sistemas con metaprogramación en tiempo de compilación (macros/comptime) — el mismo terreno donde compiten `zig-clap` y `zig-args`. Vale la pena ver cómo resuelven el mismo problema.

**Crystal**

**`OptionParser` (stdlib) — Patrón #2 (Builder / API fluida)**
- *Por qué:* está modelada explícitamente sobre el `OptionParser` de la stdlib de Ruby: se abre un bloque `OptionParser.parse do |parser| ... end` y dentro se registra cada flag con `parser.on(...)`, encadenando registros imperativos igual que `argh` o `argparse`. La forma de bloque es azúcar sintáctica de Crystal, pero el flujo de fondo es "crear parser → registrar opciones una por una → ejecutar".
- *Ejemplo:*
  ```crystal
  require "option_parser"
  verbose = false
  OptionParser.parse do |parser|
    parser.banner = "Uso: miapp [opciones]"
    parser.on("-v", "--verbose", "Modo verbose") { verbose = true }
  end
  ```
  ```bash
  $ ./miapp -v
  ```
- *Alcance:* incluida en la stdlib (cero dependencias), genera `--help` a partir del `banner` + las descripciones; suficiente para la mayoría de scripts y herramientas Crystal de una sola vía.

**`admiral.cr` — Patrón #6 (Struct/reflection declarativo, vía macros)**
- *Por qué:* se define una clase que hereda de `Admiral::Command` y se declaran los flags con el macro `define_flag` (análogo a un campo de struct anotado); el macro de Crystal expande en tiempo de compilación los getters, el parseo y la ayuda, igual que hace `clap derive` en Rust o `zig-args` con reflection sobre un struct.
- *Ejemplo:*
  ```crystal
  class MiCLI < Admiral::Command
    define_flag verbose : Bool, default: false, short: v, description: "Modo verbose"
    def run
      puts "verbose" if flags.verbose
    end
  end
  MiCLI.run
  ```
  ```bash
  $ ./miapp -v
  ```
- *Alcance:* soporta subcomandos (`define_command`, tocando el patrón #8, estilo git); es la opción "framework completo" de Crystal, análoga a `picocli`/`clap` — más apropiada cuando el CLI crece más allá de un puñado de flags.

**Nim**

**`std/parseopt` (stdlib) — Patrón #7 (getopt clásico)**
- *Por qué:* es un iterador de bajo nivel (`for kind, key, val in getopt(): ...`) que va devolviendo el siguiente token de `argv` y su tipo (`cmdShortOption`, `cmdLongOption`, `cmdArgument`), dejando toda la interpretación al programador — el mismo contrato que `getopt`/`getopt_long` de libc, solo que expresado como iterador en vez de bucle con variables globales.
- *Ejemplo:*
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
  $ ./miapp -v
  ```
- *Alcance:* sin dependencias externas, pero sin ayuda automática ni tipos — la base sobre la que se construyen librerías Nim de más alto nivel, igual que `getopt` es la base en C.

**`cligen` — Patrón #6 (Struct/reflection declarativo, vía macros sobre firma de función)**
- *Por qué:* en vez de anotar un struct, se escribe un `proc` normal de Nim con parámetros tipados y valores por defecto; el macro `dispatch(miProc)` inspecciona esa firma en tiempo de compilación y genera el parser, la conversión de tipos y el `--help` automáticamente. Es el mismo espíritu reflexivo de `typer` en Python (leer la firma como fuente de verdad) pero resuelto en comptime con macros de Nim en vez de type hints runtime.
- *Ejemplo:*
  ```nim
  import cligen
  proc miapp(verbose = false, archivo = "") =
    if verbose: echo "modo verbose"
  dispatch(miapp)
  ```
  ```bash
  $ ./miapp --verbose --archivo=datos.csv
  ```
- *Alcance:* es la librería de CLI más popular del ecosistema Nim por su bajísimo boilerplate (una función = un CLI completo); igual que otros miembros del patrón #6, ofrece menos control fino sobre casos de parsing atípicos que un builder explícito.

**`docopt.nim` — Patrón #5 (DSL de texto, variante runtime)**
- *Por qué:* es un port directo del `docopt` de Python al ecosistema Nim: el string de uso/ayuda es la especificación, parseada en tiempo de ejecución.
- *Alcance:* mismo trade-off que `docopt` en Python — muy compacto para CLIs chicas, poco práctico para CLIs grandes o con lógica de validación compleja.

### Observación (actualizada con Crystal y Nim)

La inclusión de Crystal y Nim refuerza el patrón ya visto en Zig: en lenguajes de sistemas con metaprogramación en tiempo de compilación, la disyuntiva de fondo es siempre la misma **#2 (builder explícito, más control) vs. #6 (struct/función + reflection/macros, menos boilerplate)** — `OptionParser` vs. `admiral.cr` en Crystal, y `parseopt` vs. `cligen` en Nim, replican exactamente la disyuntiva `zig-clap`/`zig-args` (aunque estos últimos dos son ambos declarativos entre sí, #5 vs #6) que motiva este proyecto: un paquete de opciones en `z-args` debería, como mínimo, cubrir el escalón "builder de bajo nivel tipo getopt" (#7), el escalón "builder imperativo" (#2) y el escalón "declarativo por struct" (#6), que es donde consistentemente aparecen las librerías más usadas en cada lenguaje relevado.

## Plan de diseño de `z-args`: alcance real de cada patrón en Zig 0.16

Objetivo de esta sección: para cada uno de los 8 patrones (y la variante #4, que resulta ser un caso especial), evaluar **qué tan literalmente se puede portar a Zig 0.16** dado lo que el lenguaje realmente ofrece (comptime, `@typeInfo`, structs genéricos parametrizados por valores comptime) y lo que **no** ofrece (preprocesador tipo C, macros de token-pasting, atributos/anotaciones sobre campos de struct como Rust/Java/C#). El resultado es una propuesta de módulos (`tiers`) que `z-args` expondría, de más simple a más completo, para que el usuario final cargue solo la complejidad que necesita — igual que en tu ejemplo: empezar en el equivalente de `arg.h` y subir de escalón el día que aparezca una flag que dependa de otra.

Todo el código base parte de `std.process.Init` (Zig 0.16, "Juicy Main"): `init.args.iterate()` para iterar `argv` de forma perezosa, o `init.minimal.args.toSlice(allocator)` si se necesita un slice materializado.

### Tier 0 — Patrón #1 (macros + switch) → sin librería / `z-args` "raw"

- **Alcance real:** ARGBEGIN/ARGEND de `arg.h` dependen de macros de preprocesador con pegado de tokens y mutación de `argc`/`argv` globales — Zig no tiene preprocesador, así que esa mecánica **no es portable literalmente**. Lo que sí es 100% idiomático es el espíritu: recorrer `argv` a mano con un `while` + `switch` explícito, que en Zig es tan ligero como en C.
- **Boceto:**
  ```zig
  pub fn main(init: std.process.Init) !void {
      var args = init.args.iterate();
      _ = args.next(); // nombre del programa
      var verbose = false;
      var out_file: []const u8 = "a.out";
      while (args.next()) |arg| {
          if (std.mem.eql(u8, arg, "-v")) {
              verbose = true;
          } else if (std.mem.eql(u8, arg, "-o")) {
              out_file = args.next() orelse return error.MissingValue;
          } else {
              return error.UnknownFlag;
          }
      }
  }
  ```
- **Conclusión:** no amerita empaquetarse como librería en sí — como mucho, `z-args` puede ofrecer un helper mínimo (`ArgIter` con `.shift()`/`.expect()`, equivalente a `EARGF`) para recortar boilerplate sin ocultar el `switch`. Es el escalón "sin abstracción, control total", útil como referencia y como lo que uno usa cuando ni siquiera quiere pagar el costo de un parser genérico.

### Tier 1 — Patrón #7 (getopt clásico) → `z-args/getopt`

- **Alcance real:** totalmente portable y con valor real, porque Zig **no trae `getopt` en su stdlib**. Reimplementarlo puro-Zig (permutación de `argv`, `--` como terminador, agrupamiento de flags cortas `-abc`) sirve tanto como opción standalone (portar herramientas C 1:1) como base interna para los tiers superiores.
- **Boceto:**
  ```zig
  pub const Getopt = struct {
      args: [][:0]const u8,
      optstring: []const u8,
      index: usize = 1,
      optarg: ?[:0]const u8 = null,

      pub fn next(self: *Getopt) ?u8 {
          // misma semántica que getopt() de libc, sin variables globales
      }
  };
  ```
- **Conclusión:** escalón "estándar POSIX sin sorpresas". Bajo esfuerzo de implementación, cero dependencias, pero hereda las mismas limitaciones que en C: sin tipos, sin ayuda auto-generada, sin subcomandos.

### Tier 2 — Patrones #2 + #3 fusionados (builder runtime) → `z-args/builder`

- **Alcance real:** en C++ el patrón #2 son métodos encadenados y en C el #3 son funciones libres (`add_arg`) sobre una tabla; esa distinción OOP-vs-procedural **desaparece en Zig**, donde `s.method()` es azúcar sintáctica sobre `Struct.method(&s)`. Un único diseño runtime (una lista de `Option` poblada dinámicamente) cubre ambos patrones a la vez.
- **Boceto:**
  ```zig
  var parser = z_args.Builder.init(gpa);
  defer parser.deinit();
  try parser.addFlag(.{ .short = 'v', .long = "verbose", .help = "modo verbose" });
  try parser.addOption(.{ .short = 'o', .long = "output", .value_name = "FILE" });
  const result = try parser.parse(args);
  if (result.flag("verbose")) { ... }
  ```
- **Conclusión:** primer escalón donde tiene sentido enganchar **validación cruzada entre flags** — exactamente el punto donde `arg.h` se queda corto en tu ejemplo motivador. El `.parse()` devuelve un resultado completo sobre el que se pueden expresar reglas tipo `.requires("output", "verbose")` o `.conflictsWith(...)` antes de entregarlo. Costo: los getters son por nombre de string (`result.flag("verbose")`), sin chequeo de tipos en compilación — igual que `cargs` en C.

### Tier 3 — Patrón #5 (DSL de texto en comptime) → `z-args/dsl`

- **Alcance real:** terreno nativo de Zig — comptime string parsing es exactamente lo que hace `zig-clap` hoy, y Zig lo soporta sin pérdida de fidelidad respecto al patrón original.
- **Boceto:**
  ```zig
  const params = comptime z_args.parseParamsComptime(
      \\-h, --help             Muestra ayuda.
      \\-v, --verbose          Modo verbose.
      \\-o, --output <str>     Archivo de salida.
  );
  const res = try z_args.parseComptime(&params, gpa, args);
  ```
- **Conclusión:** escalón "compacto y auto-documentado" (el texto de ayuda y la especificación son la misma fuente). El costo es el mismo que en el original: el DSL es un mini-lenguaje aparte con su propia sintaxis y sus propios errores, menos ergonómico de depurar que un error de tipo Zig normal.

### Tier 4 — Patrón #6 (struct/reflection declarativo) → `z-args/declarative`

- **Alcance real:** factible vía `@typeInfo(T)` sobre un struct definido por el usuario, evaluado en comptime — lo que hace `zig-args` hoy. **Pero hay una limitación real de lenguaje que no tiene equivalente directo**: a diferencia de Rust (`#[derive(Parser)]` + `#[arg(short, long)]`) o Java/C# (anotaciones/atributos sobre el campo), **Zig no tiene un sistema de atributos adjuntables a un campo de struct**. No existe forma de escribir algo como `@[short('v')] verbose: bool`. Hay dos estrategias reales para resolverlo, ambas usadas en la práctica:
  1. **Struct "meta" paralelo** (lo que hace `zig-args`): junto al struct de datos se declara un `const meta = .{ .verbose = .{ .short = 'v', .help = "..." } };` que la librería cruza con `@typeInfo` del struct principal. Riesgo: dos declaraciones que hay que mantener sincronizadas a mano.
  2. **Tipos wrapper genéricos por campo**: en vez de `verbose: bool`, escribir `verbose: z_args.Flag(bool, .{ .short = 'v', .help = "..." })`, empaquetando la metadata *dentro del tipo* — algo que Zig permite de forma más directa que Rust/Java gracias a los tipos genéricos parametrizados por valores comptime (`fn Flag(comptime T: type, comptime opts: FlagOpts) type`).
  - **Boceto (estrategia 2, más idiomática en Zig porque evita sincronizar dos declaraciones):**
    ```zig
    const Cli = struct {
        verbose: z_args.Flag(bool, .{ .short = 'v', .help = "modo verbose" }) = .{ .value = false },
        output: z_args.Flag([]const u8, .{ .short = 'o', .default = "a.out" }) = .{ .value = "a.out" },
    };
    const cli = try z_args.parseStruct(Cli, gpa, args);
    if (cli.verbose.value) { ... }
    ```
- **Conclusión:** el escalón más idiomático (autocompletado del IDE, refactor seguro, tipos verificados en compilación) y el que **más diseño propio exige** en Zig, precisamente porque hay que inventar el mecanismo de metadata que en otros lenguajes viene gratis con anotaciones. Esto debe documentarse como decisión de diseño explícita de `z-args`, no como detalle menor de implementación.

### Patrón #4 (X-Macros) → no se traduce, queda absorbido por el Tier 4

- **Alcance real:** el valor de X-Macros — una sola fuente de verdad que genera struct + parseo + ayuda a la vez — es exactamente lo que el patrón #6 ya logra en un lenguaje con comptime real, sin necesidad de trucos de token-pasting de preprocesador. Zig no tiene macros de texto, así que reproducir X-Macros tal cual no es posible ni deseable.
- **Conclusión:** no amerita un tier propio en `z-args`; se documenta como "ya resuelto por el Tier 4" en vez de reimplementarse.

### Patrón #8 (subcomandos en árbol) → `z-args/commands` (capa compositiva ortogonal)

- **Alcance real:** totalmente factible, pero **no es un tier de parsing propio** sino una capa que envuelve cualquiera de los Tier 2 o Tier 4 como "hoja" de cada subcomando. Un `Command` es un nodo con nombre + parser (builder o struct declarativo) + lista de sub-`Command`s.
- **Boceto:**
  ```zig
  var root = z_args.Command.init(gpa, "miapp");
  defer root.deinit();
  var commit = try root.addSubcommand("commit");
  try commit.args.addOption(.{ .short = 'm', .long = "message" });
  const invocation = try root.parse(args); // resuelve "miapp commit -m '...'"
  ```
- **Conclusión:** se ofrece como módulo independiente y composable, no como escalón de complejidad de parsing en sí — igual que en `clap`, `picocli` o `System.CommandLine`, donde subcomandos se monta *sobre* el builder o el declarativo, nunca reemplaza al motor de parsing de hojas.

### Escalera final propuesta para `z-args`

| Tier | Patrón(es) de origen | Módulo | Nivel | Cuándo se vuelve insuficiente |
|---|---|---|---|---|
| 0 | #1 (arg.h) | *(sin librería, solo helper `ArgIter`)* | Trivial | En cuanto una flag depende del valor de otra: no hay dónde enganchar validación cruzada sin escribirla a mano después del `switch`. |
| 1 | #7 (getopt) | `z-args/getopt` | Bajo | Cuando se necesitan tipos, ayuda auto-generada o flags largas ergonómicas más allá de lo que POSIX define. |
| 2 | #2 + #3 (builder) | `z-args/builder` | Medio | Cuando se prefiere que el propio struct del programa sea la única fuente de verdad (sin getters por string) y se quiere chequeo de tipos en compilación. |
| 3 | #5 (DSL comptime) | `z-args/dsl` | Medio-alto | Cuando el "mini-lenguaje" del DSL de texto empieza a estorbar más de lo que ahorra, o se necesita metadata rica por campo (validadores custom, tipos complejos). |
| 4 | #6 (declarativo) | `z-args/declarative` | Alto | Rara vez — es el techo de expresividad de parsing de una sola línea de comandos; lo próximo es escalar a subcomandos. |
| — (ortogonal) | #8 (árbol) | `z-args/commands` | Se combina con Tier 2 o 4 | N/A — es un eje de composición, no de complejidad de parsing. |
| — (absorbido) | #4 (X-Macros) | *(no se implementa; cubierto por Tier 4)* | — | — |

La recomendación de diseño es que `z-args` no sea una única librería monolítica sino un **paquete de módulos independientes** bajo un mismo namespace (`z-args/getopt`, `z-args/builder`, `z-args/dsl`, `z-args/declarative`, `z-args/commands`), cada uno importable por separado vía `build.zig.zon`, de forma que el costo de compilación y la superficie de API que paga el usuario final sea exactamente la del tier que eligió — nunca la de un framework completo si solo necesita un `getopt`.

## Notas rápidas

- Para C con foco en tamaño mínimo (estilo suckless): patrón **#1**.
- Para C con necesidad de tipos y ayuda automática sin C++: patrón **#3**.
- Para Zig, la disyuntiva típica es **#5 (zig-clap)** vs **#6 (zig-args)**: DSL de texto vs struct nativo.
- Para C++ moderno sin dependencias externas: patrón **#2**.
- Para CLIs grandes con subcomandos: patrón **#8**, normalmente montado sobre **#2** o **#6**.
