# Host scripting and host compiled modes

Loup has three host modes. They share one language and one standard library;
they differ in what may stand at module scope, where the program starts, and
how it runs. (The full mode table, including web and freestanding, is in
`skills/loup-programmer/references/modes-and-projects.md` in the Loup
repository.)

## Host scripting — `@mode(host.scripted)`, `.lpscr`

```loup
@mode(host.scripted)

from io.path import (basename);

let argv = args();
for (a in argv) {
    println(basename(a));
}
```

```sh
loup run tool.lpscr one/two.txt three
```

- Interpreted; no build step and no manifest needed.
- Top-level statements run in order; any statement may stand at module scope;
  `await` is allowed at top level.
- `args()` (or `runtime.args()`) gives the arguments; `exit(n)` sets the
  status; an uncaught exception exits 1, a compile error 2.
- Imports resolve from the script's directory (`from helpers import (f);`
  loads `helpers.lpscr` / `helpers.loup` beside it).
- Use it for automation, glue, generators, and test files (`*_test.lpscr`).
- Cannot call `extern native` functions (no FFI in the interpreter) and cannot
  be a native build entry: Stage0 refuses it with `E-BUILD-COMPILED`; the
  self-hosted `loup build` currently gets as far as the link and fails there
  (`Undefined symbols … "_main"`) — the same happens for a misspelled
  `@mode(...)`, so read that link error as "check the entry's mode".

## Host compiled — `@mode(host.dual)`, `.loup`

```loup
@mode(host.dual)

pub func greet(name: string): string {
    return "hello, " + name;
}

func main(): void {
    println(greet("mac"));
}
```

```sh
loup run src/main.loup                 # interpreted
loup build --target native -o app      # native Mach-O (host.dual compiles natively too)
loup-bootstrap build                   # Wasm module (Stage0 only)
```

- An ahead-of-time mode: module scope holds declarations and `const` / `let`
  initializers only; the program starts at `func main()` (no parameters,
  returns `void` or `int`).
- The same file runs interpreted and compiles, so it is the mode for
  libraries and for logic you want to `loup run` and `loup test`.
- No `unique class` and no `asm` (those are `host.native` features). Keep
  `extern native` out of these modules: a call to one stops `loup run`, which
  is the reason to have a `host.dual` module at all.

## Host compiled, native only — `@mode(host.native)`, `.lphc`

```loup
@mode(host.native)

extern native "c" func getpid(): int32;

func main(): int {
    println("pid " + getpid().to_string());
    return 0;
}
```

```sh
loup build            # in a project whose [build] entry is this file
./app
```

- Same module-scope rules as `host.dual`, plus the native-only features:
  `extern native` calls, `unique class`, inline `asm`, `@repr(C)` structs.
- `Any` as a declared type gives the `W_ANY_IN_AOT_MODE` advisory.
- Native builds refuse `async` / `await` (both drivers: `E-BUILD-NATIVE`
  naming the async function — no task scheduler) and rendering a template
  fence (Stage0 `E-BUILD-NATIVE`, self-hosted `E-CODEGEN-UNHANDLED-METHOD`
  for `render`); the interpreters run both. `for concurrent` is not accepted
  in host files by either front end yet, interpreted or built (a parse or
  name error), so write a plain `for` / `while` loop.
- `loup run` type-checks and interprets it, but any `extern native` call stops
  the interpreter, so an FFI program must be built and run.

## Mixing modes in one program

Each file is checked under its own mode, and modules import each other freely:

```text
app/
├── app.lppkg              # [build] entry = "src/main.lphc", mode = "host.native"
├── src/main.lphc          # @mode(host.native): main(), the AppKit/FFI layer
├── src/model.loup         # @mode(host.dual): state and logic, runs under loup run / loup test
└── tests/model_test.loup  # @mode(host.dual): debug.assert tests of model.loup
```

- `loup test` covers `model.loup` interpreted; the native build covers
  `main.lphc`.
- A manifest's `[build] mode` is the default for files without a directive,
  but always write the directive (ruling MODE-2). A misspelled or retired
  `@mode(…)` directive silently runs the file as `host.scripted` on both
  interpreters; a misspelled manifest mode is refused by `loup-bootstrap run`
  and both native builds, but `loup run` still runs the file as
  `host.scripted`.
