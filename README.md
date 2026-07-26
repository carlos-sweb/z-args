# z-args

Un paquete de módulos para parseo de argumentos de línea de comandos en Zig — no una librería monolítica, sino una **escalera de complejidad** que el usuario sube solo hasta donde su CLI lo necesita.

## Por qué existe

El ecosistema Zig hoy ofrece básicamente dos opciones para parsear `argv`: algo tan simple como un `switch` manual, o librerías como `zig-clap`/`zig-args` que ya asumen bastante complejidad. No hay un camino intermedio declarado como tal. Mientras tanto, en C, `arg.h` (suckless) resuelve el caso trivial en un puñado de líneas — hasta que aparece una flag que depende de otra, y ahí se vuelve insuficiente. Ese es exactamente el problema que `z-args` busca resolver: **un mismo espíritu de "usa solo lo que necesitás", pero con un escalón siguiente al que subir cuando lo simple deja de alcanzar**, en vez de saltar directo a un framework completo.

## Cómo llegamos acá

Antes de escribir una sola línea de Zig, este repo empezó por investigar cómo resuelven este mismo problema las librerías de parseo de argumentos en los lenguajes más usados — C, C++, Python, Java, C#, JavaScript, R, Rust, y también Crystal y Nim por compartir con Zig la metaprogramación en tiempo de compilación. Esa investigación está en [`args.md`](./args.md) y es la base de todo lo que sigue: clasifica las librerías reales en **8 patrones/estilos** (desde macros+switch imperativo hasta comandos/subcomandos en árbol), y evalúa para cada uno **qué tan literalmente se puede portar a Zig 0.16** dado lo que el lenguaje ofrece (`comptime`, `@typeInfo`, tipos genéricos parametrizados) y lo que no ofrece (preprocesador, macros de token-pasting, atributos/anotaciones sobre campos de struct).

## La escalera propuesta

| Tier | Inspirado en | Módulo | Nivel |
|---|---|---|---|
| 0 | `arg.h` (suckless) | *(sin librería, helper `ArgIter` opcional)* | Trivial |
| 1 | `getopt`/`getopt_long` POSIX | `z-args/getopt` | Bajo |
| 2 | Builders tipo `argh`, `clap` (builder) | `z-args/builder` | Medio |
| 3 | DSL de texto en comptime (`zig-clap`) | `z-args/dsl` | Medio-alto |
| 4 | Struct/reflection declarativo (`zig-args`, `clap derive`) | `z-args/declarative` | Alto |
| — | Subcomandos en árbol (`cobra`, `clap` + subcommands) | `z-args/commands` | Capa ortogonal, se combina con Tier 2 o 4 |

Cada módulo es independiente y se importa por separado — el costo de compilación y la superficie de API que paga quien lo usa es la del tier que eligió, nunca la de un framework completo si solo necesitaba un `getopt`.

El detalle completo de cada tier — justificación, bocetos de API en Zig 0.16, y las limitaciones de lenguaje que hay que resolver de diseño (como la ausencia de atributos sobre campos de struct) — está documentado en la sección *"Plan de diseño de `z-args`"* dentro de [`args.md`](./args.md).

## Estado actual

Fase de investigación y diseño. Todavía no hay código Zig en el repo: el objetivo de esta etapa es cerrar el diseño de cada módulo antes de implementar, para no repetir el problema que motivó este proyecto (empezar simple y quedar atrapado sin un siguiente escalón).

## Target

Zig 0.16.0 (stable).
