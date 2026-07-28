# z-args

Un paquete de módulos para parseo de argumentos de línea de comandos en Zig — no una librería monolítica, sino una **escalera de complejidad** que el usuario sube solo hasta donde su CLI lo necesita.

## Por qué existe

El ecosistema Zig hoy ofrece básicamente dos opciones para parsear `argv`: algo tan simple como un `switch` manual, o librerías como `zig-clap`/`zig-args` que ya asumen bastante complejidad. No hay un camino intermedio declarado como tal. Mientras tanto, en C, `arg.h` (suckless) resuelve el caso trivial en un puñado de líneas — hasta que aparece una flag que depende de otra, y ahí se vuelve insuficiente. Ese es exactamente el problema que `z-args` busca resolver: **un mismo espíritu de "usa solo lo que necesitás", pero con un escalón siguiente al que subir cuando lo simple deja de alcanzar**, en vez de saltar directo a un framework completo.

## Cómo llegamos acá

Antes de escribir una sola línea de Zig, este repo empezó por investigar cómo resuelven este mismo problema las librerías de parseo de argumentos en los lenguajes más usados — C, C++, Python, Java, C#, JavaScript, R, Rust, y también Crystal y Nim por compartir con Zig la metaprogramación en tiempo de compilación. Esa investigación está en [`args.md`](./args.md) y es la base de todo lo que sigue: clasifica las librerías reales en **8 patrones/estilos** (desde macros+switch imperativo hasta comandos/subcomandos en árbol), y evalúa para cada uno **qué tan literalmente se puede portar a Zig 0.16** dado lo que el lenguaje ofrece (`comptime`, `@typeInfo`, tipos genéricos parametrizados) y lo que no ofrece (preprocesador, macros de token-pasting, atributos/anotaciones sobre campos de struct).

## La escalera propuesta

Categorías por **alcance funcional** (qué resuelve, no de qué librería copia la sintaxis), validadas contra los dos únicos ecosistemas relevados con una escalera completa dentro de un mismo lenguaje: Nim y Crystal.

| Categoría | Alcance | Referencia (ecosistema maduro) |
|---|---|---|
| **Simple** | Tokenizador de flags cortas/largas estilo POSIX/GNU `getopt_long`. Sin tipos, sin ayuda auto-generada, sin validación cruzada. | Nim `std/parseopt` |
| **Builder** | Registro imperativo en runtime, ayuda auto-generada, validación cruzada entre flags. Resultados por nombre, sin chequeo de tipos en compilación. | Crystal `OptionParser` |
| **Declarative** | Struct/función del lenguaje como fuente de verdad, generado en tiempo de compilación: tipos verificados, mínimo boilerplate. | Nim `cligen`, Crystal `admiral.cr` |
| **Commands** (ortogonal) | Árbol de subcomandos, compone sobre Builder o Declarative como hoja. No es un escalón de complejidad de parsing, es un eje aparte. | `admiral.cr`, `cobra` |

Un único módulo Zig (`zargs`), no un módulo por tier — Zig solo genera código para lo que efectivamente se usa, así que importar `zargs.Simple` no paga el costo de `Builder`/`Declarative`, sin necesitar `build.zig.zon` separados. Matchea la convención del resto del ecosistema `z-*`: un repo, un módulo raíz.

El detalle completo de cada categoría — justificación, la reformulación desde el research inicial (patrones numerados) a esta taxonomía, el caso de estudio de `argh` (por qué se clasifica por alcance y no por sintaxis), y los bocetos de API en Zig 0.16 — está documentado en [`args.md`](./args.md).

## Ejemplos

### `Simple`: parseo directo sobre un `argv` literal

```zig
const std = @import("std");
const zargs = @import("zargs");
const Simple = zargs.Simple;

const specs = [_]Simple.OptionSpec{
    .{ .short = 'v', .long = "verbose", .kind = .flag },
    .{ .short = 'o', .long = "output", .kind = .value },
};

pub fn main() !void {
    const args = [_][:0]const u8{ "-v", "--output=out.txt", "input.txt" };
    var parser = Simple.Parser.init(&args, &specs);

    var verbose = false;
    var output: []const u8 = "a.out";
    var input: ?[]const u8 = null;

    while (true) {
        const token = parser.next();
        switch (token) {
            .flag => |f| if (f.short == 'v') {
                verbose = true;
            },
            .option => |o| if (o.short == 'o') {
                output = o.value;
            },
            .positional => |p| input = p,
            .unknown_option => |u| std.debug.print("opción desconocida: {?c}{s}\n", .{ u.short, u.long orelse "" }),
            .missing_value, .unexpected_value => {}, // el caller decide qué hacer con cada error
            .end => break,
        }
    }
    // verbose == true, output == "out.txt", input == "input.txt"
}
```

`Parser` no asigna memoria ni hace I/O: solo referencia slices dentro de `args`. Un flag inválido (`.unknown_option`) no aborta el resto del parseo — igual que el `getopt()` real, cada llamada a `.next()` reporta un problema a la vez y sigue, dejando la decisión de abortar o seguir en manos del caller.

### `Simple`: parseando el `argv` real del proceso

El único punto de este tier que toca un allocator — `zargs.collectProcessArgs` materializa el iterador real de `std.process.Init` en el slice que `Parser` espera:

```zig
const std = @import("std");
const zargs = @import("zargs");

pub fn main(init: std.process.Init) !u8 {
    var it = std.process.Args.Iterator.init(init.minimal.args);
    const args = try zargs.collectProcessArgs(init.gpa, &it);
    defer init.gpa.free(args);

    var parser = zargs.Simple.Parser.init(args, &specs);
    // ... mismo bucle que el ejemplo anterior
    return 0;
}
```

## Estado actual

**Simple** está implementado (`src/simple.zig`, `src/process.zig`) — tokenizador de flags cero-allocation, cero I/O, ground-truthed contra `getopt_long(3)` real (bundling, valores adjuntos/separados, opciones largas con `=`, `--`, errores no-fatales que permiten seguir parseando). `Builder`, `Declarative` y `Commands` siguen en fase de research únicamente — cada uno espera su propia sesión de diseño antes de implementarse, para no repetir el problema que motivó este proyecto (empezar simple y quedar atrapado sin un siguiente escalón).

## Target

Zig 0.16.0 (stable).
