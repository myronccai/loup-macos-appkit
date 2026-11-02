---
name: loup-macos-developer-skill
description: Builds macOS programs and GUI applications in Loup, and explains Loup's host scripting (host.scripted) and host compiled (host.dual, host.native) modes. Covers the macOS toolchain (the self-hosted loup-build → loup-llvm → clang route and the Stage0 loup-bootstrap route), native builds to Mach-O, calling C and Objective-C through `extern native`, `@symbol`, linking libraries and Apple frameworks from the manifest, and the AppKit application pattern. Use when a task targets macOS with Loup, mentions AppKit, Cocoa, Objective-C, frameworks, .app bundles, `@mode(host.native)`, `.lphc` files, or asks which host mode to use.
---

# Loup macOS developer

This skill is for writing Loup programs that run on macOS: scripts, native
command-line tools, and GUI applications that call AppKit. For the language
itself (syntax, ownership, the standard library) use the `loup-programmer`
skill (`skills/loup-programmer/` in the Loup repository); this one assumes it.

This copy is published with the `appkit` library,
https://github.com/myronccai/loup-macos-appkit ("this repository" below
means that library; the example apps are the sibling repositories
https://github.com/myronccai/loup-macos-<app>, listed in its
[README.md](../../README.md)). It describes the Loup toolchain **as it
behaves after the 1.27.0 release** (the Loup repository's main after 1.27.0; the
library and the apps need fixes made after that release). Where
something is planned but not implemented, it says so. Trust a build and a
run over any document, including this one.

## 1. Pick the host mode

A Loup file's first token is its mode, and the extension follows the mode.

| Mode | Ext. | How it runs on macOS | Use it for |
|---|---|---|---|
| `host.scripted` | `.lpscr` | interpreted: `loup run x.lpscr` | scripts, glue, quick tools, tests |
| `host.dual` | `.loup` | interpreted (`loup run`) or compiled (Wasm via Stage0, native via `--target native`) | libraries and programs that must also run interpreted |
| `host.native` | `.lphc` | compiled to a Mach-O executable (`loup build --target native`) | anything that calls C or Objective-C, GUI apps, `unique class`, `asm` |

- **Host scripting** (`host.scripted`): top-level statements run in order, no
  `main` needed, every statement allowed at module scope.
- **Host compiled** (`host.dual`, `host.native`): module scope holds only
  declarations and `const`/`let` initializers; the program starts at
  `func main(): void` or `func main(): int` (no parameters; `runtime.args()`
  gives the arguments).
- **FFI needs a native build.** `extern native` calls do not run under either
  interpreter (`loup run` fails with `unsupported instruction:
  FfiBoundaryCheck` on Stage0 and `unsupported instruction <other>` on the
  self-hosted `loup`). A program that touches AppKit, libobjc or any C library
  is `host.native` in a `.lphc` file and is built, then run.
- Keep pure logic (parsing, models, view state) in `host.dual` `.loup`
  modules, which also run under `loup run` and `loup test`; put the FFI layer
  in `.lphc` modules that only the native build compiles.

Details and examples: [references/host-modes.md](references/host-modes.md).

## 2. The macOS toolchain

Two drivers build native code on macOS. Both emit LLVM IR, compile it with the
host `clang`, and link Mach-O with Apple's ld64 (`arm64-apple-macosx` or
`x86_64-apple-macosx`; the arch defaults to the host's).

| Route | Command | Notes |
|---|---|---|
| Self-hosted (preferred) | `loup-build` (what the self-hosted `loup build` execs) | `loup-build` → `loup-llvm <entry> <out.ll> <arch> os=macos` → `clang` with the companion runtime. No Rust anywhere in the build. |
| Stage0 (the trusted Rust bootstrap) | `loup-bootstrap build --target native` | Also builds the self-hosted tools themselves. |

Requirements: the Xcode Command Line Tools (`xcode-select --install`).

Building the toolchain from a checkout of the Loup repository:

```sh
./install.sh --prefix ~/.local     # Stage0 (via bootstrap.sh if needed), then loup,
                                   # loup-build, loup-llvm and the other self-hosted tools
export PATH="$HOME/.local/bin:$PATH"
```

On macOS `install.sh` builds the self-hosted units into `target/loup-units`
(never over the tree's tracked Linux `*-elf` files) and skips `loup-llbe`,
which writes ELF objects only.

`loup-build` finds `loup-llvm` on `PATH` (or `$LOUP_LLVM`) and `clang` on
`PATH` (or `$LOUP_CLANG`).

**SDK pitfall.** If a link fails with `tapi error: malformed file …
MacOSX27.0.sdk/usr/lib/libSystem.B.tbd … unknown architecture`, `xcrun` picked
an SDK newer than the installed linker understands. Point the build at one it
does: `export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`
(list them with `ls /Library/Developer/CommandLineTools/SDKs`). This affects
`cargo` too.

## 3. A native project

```text
hello-mac/
├── hello-mac.lppkg
└── src/main.lphc
```

```toml
# hello-mac.lppkg
name = "hello-mac"
version = "0.1.0"

[build]
entry = "src/main.lphc"
mode = "host.native"
delivery = "native"
```

```loup
@mode(host.native)

pub func main(): void {
    println("hello from a Mach-O binary");
}
```

```sh
cd hello-mac
loup build                      # self-hosted `loup` → loup-build → ./hello-mac
loup-build                      # the same, calling the driver directly
loup-bootstrap build --target native   # or the Stage0 route
./hello-mac
file hello-mac                  # Mach-O 64-bit executable arm64
```

`[build] mode = "host.native"` (never the retired `"native"`, which is
`E_MANIFEST_MODE_LEGACY`). Without `delivery = "native"` (or
`--target native`) Stage0 builds a Wasm module instead.

## 4. Calling C: `extern native`, libraries and frameworks

```loup
@mode(host.native)

extern native "objc" func objc_getClass(name: string): int;
extern native "objc" func sel_registerName(name: string): int;
extern native "AppKit.framework" func NSApplicationLoad(): bool;
```

- The string names the library: `"sqlite3"` / `"libsqlite3"` links
  `-lsqlite3`; `"Name.framework"` links `-framework Name` (macOS only; nothing
  elsewhere). `"c"`, `"m"`, `"pthread"`, `"dl"` and `"System"` add nothing (the
  hosted link always has them).
- **Only libraries of CALLED declarations are linked.** A declaration nothing
  calls links nothing.
- Libraries a program needs but calls no function from — the usual case for
  Objective-C, where classes are found by name at run time — go in the
  manifest:

  ```toml
  [delivery.native]
  framework = ["AppKit", "Foundation"]   # -framework AppKit -framework Foundation
  link = ["sqlite3"]                     # -lsqlite3
  link_path = ["vendor/lib"]             # -L<project>/vendor/lib (relative to the manifest)
  ```

  These keys are valid in `[delivery.native]` only (Stage0 reports them
  elsewhere). Symptom of a missing framework: `objc_getClass("NSWindow")`
  returns 0 and every message to it returns 0, with no error.
- Types at the boundary: `int` / `uint` / `NativeHandle` are 64-bit words
  (pointers); `int32`, `uint8`, … are truncated to their C width and
  sign/zero-extended on return; `float` is a C `double`, `float32` a C
  `float` (passed in floating-point registers); `bool` is a word; a `string`
  argument is passed as a NUL-terminated UTF-8 copy that lives for the call.
  An omitted return type is `void`.
- Structs by value are **not** supported yet, and nothing refuses them: an
  `extern native` whose parameter or result is a `@repr(C)` struct builds on
  both drivers, then passes garbage (an argument) or crashes (a result,
  e.g. `ldiv`). Never declare one; instead, on arm64 a struct of up to four
  `double`s (`NSPoint`, `NSSize`, `NSRect`) is passed exactly as that many
  `float` arguments; on x86-64 that holds only for two-`double` structs
  (`NSPoint`, `NSSize`). Struct returns are not available on either arch:
  read a struct-valued property through key-value coding
  (`appkit.objc.rect_of` / `point_of`) or an `NSInvocation`.

## 5. Objective-C: `@symbol` and `objc_msgSend`

Every Objective-C message is a call to `objc_msgSend` cast to the method's
signature. Loup declares one `extern native` per signature and binds each to
the same C symbol with `@symbol`:

```loup
@mode(host.native)

extern native "objc" func objc_getClass(name: string): int;
extern native "objc" func sel_registerName(name: string): int;

@symbol("objc_msgSend")
extern native "objc" func msg(recv: int, sel: int): int;
@symbol("objc_msgSend")
extern native "objc" func msgD(recv: int, sel: int, v: float): int;
@symbol("objc_msgSend")
extern native "objc" func msgRetD(recv: int, sel: int): float;

pub func main(): void {
    let n = msgD(objc_getClass("NSNumber"), sel_registerName("numberWithDouble:"), 2.5);
    println(msgRetD(n, sel_registerName("doubleValue")).to_string());   # 2.5
}
```

(Link Foundation: `framework = ["Foundation"]` in `[delivery.native]`.)

- `@symbol("c_name")` is valid on `extern native` only; its one argument is a
  string literal that is a C identifier (`E_ANNOTATION_ARGS` otherwise). The
  Loup name is what Loup code calls; the C symbol is what the linker sees.
- Name the variants by shape (`msg`, `msgI`, `msgD`, `msgRetD`, …) and keep
  them in one `.lphc` module.
- Strings: make an `NSString` with
  `msgS(objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"), text)`
  where `msgS` takes `(recv: int, sel: int, s: string): int`.

Full cookbook (selectors, nil, retain/release, the run loop, the arm64 rect
rule): [references/objc-interop.md](references/objc-interop.md).

## 6. Callbacks: `addressOf(f)`

C and Objective-C call back into Loup through a C function pointer to a
module-level function:

```loup
extern native "objc" func class_addMethod(cls: int, sel: int, imp: uint64, types: string): bool;

## `- (void)onAction:(id)sender` — self, _cmd, then the method's arguments.
func onAction(self_obj: int, cmd: int, sender: int): void {
    println("clicked");
}

# … class_addMethod(cls, sel_registerName("onAction:"), addressOf(onAction), "v@:@");
```

- `addressOf(f)` is a builtin in `host.native` (and freestanding); `f` is the
  bare name of a module-level function in the same module
  (`E_ADDRESSOF_OPERAND` otherwise). It returns a `uint64`. Not available in
  `host.dual` (`undefined identifier`).
- The callback's parameters and result are words (`int`, `uint`, pointers,
  `bool`), narrow integers (`int32`, …) or floating point (`float` = C
  `double`, `float32` = C `float`), matching the C signature. A function with
  a floating-point parameter or result is handed out through a C-ABI wrapper
  `@<f>__cabi` that both drivers emit, so the doubles arrive in the FP
  registers as C passes them — e.g. `drawRect:` can take its `NSRect` as
  `(self_obj: int, cmd: int, x: float, y: float, w: float, h: float)` on
  arm64. An Objective-C `BOOL` result can be returned as an `int` 0/1.
- The callback runs on the calling thread (AppKit: the main thread) and may
  read and write module-level `var`s. Catch exceptions inside it: one must not
  unwind through C or Objective-C frames.
- Plain C works the same way: `qsort(base, n, 8, addressOf(compare))`.

## 7. GUI applications (AppKit)

**For a real application, use the `appkit` library** — this repository,
https://github.com/myronccai/loup-macos-appkit (a package; clone it next to
your project and depend on it with a relative path dependency,
`appkit = { path = "../loup-macos-appkit" }`, plus
`[delivery.native] framework = ["AppKit"]`). It wraps AppKit in Loup proxy classes —
`appkit.app` (application, menus, windows, timers, `View`), `appkit.controls`
(buttons, fields, sliders, pop-ups, …), `appkit.layout` (VStack / HStack,
grid, tabs, split, scroll), `appkit.table`, `appkit.canvas` (custom drawing
and mouse/keys), `appkit.text`, `appkit.dialogs` — each documented in its
module header and [`docs/`](../../docs). Every module has a probe under
`probes/` that `run_all.sh --probes` builds with both drivers and runs. The
example apps — each its own repository, cloned next to this one
(`loup-macos-*`, e.g. https://github.com/myronccai/loup-macos-calculator,
https://github.com/myronccai/loup-macos-notepad) — show complete programs;
`bash run_all.sh` from inside `loup-macos-appkit` checks every one cloned
beside it.

Self-tests with the library (`--self-test`):

- **Quiet by default.** A `--self-test` run has no Dock icon, never takes the
  focus, and its windows are transparent and let clicks through; they still
  lay out and draw, so `Window.snapshot(path)` and every frame/state read work.
  `beep` is silent and `playSound` plays at volume 0. Set
  `LOUP_APPKIT_VISIBLE=1` to watch a self-test.
- **No real modal UI.** Queue dialog answers with
  `appkit.dialogs.setTestAnswers([...])`; in a self-test a dialog, panel,
  `openURL` or `revealInFinder` with no answer queued throws instead of
  appearing. Wrap clipboard use in `saveClipboard` / `restoreClipboard`.
- **Run GUI binaries under lldb while developing**
  (`lldb --batch -o "process launch -- --self-test" -k "thread backtrace" -k "process kill" -- ./app`):
  a crash then prints a backtrace instead of opening a crash-report window on
  the user's screen. `run_all.sh` does this for every app and probe.
- **A throwing handler fails the self-test.** In a `--self-test` run an
  exception from any handler (`after`, an action, a timer) is printed and the
  process exits with status 1, instead of idling until the gate kills it.
- **Drive menus and keys through the library.** The quiet window is never
  key (AppKit gives an app that was never activated no key window, and
  `makeKeyWindow` does not change that), so a standard nil-targeted action
  (Window ▸ Close, Edit ▸ Copy / Undo) would go nowhere. `MenuItem.perform()`
  (choose an item as a click does), `Menu.sendKey` / `Window.sendKey(chars,
  MOD_…)` (a key-down through `performKeyEquivalent:`) and
  `Window.sendAction("selectAll:")` send such actions along the shown
  window's responder chain as if it were key; `Window.performClose()` and
  `shouldQuit()` exercise the `onShouldClose` / `onShouldQuit` veto hooks
  without AppKit's refusal beep (a hook that throws refuses;
  `setHandlerErrorsFatal(false)` lets a self-test check that). `sendKey`
  with modifiers sends the event a real key press makes: ⇧ + a key matches
  as on the keyboard, so an item declared ("c", `MOD_SHIFT_COMMAND`) takes
  ⇧⌘C. Focus any view with `Window.focus(view)` (a table too) and read it
  with `hasFocus(view)`.
- **Document windows and undo.** `Window.setDocumentEdited`,
  `setRepresentedFilename`, `isVisible` / `hide()`, `minSize()`,
  `setAppearance("dark")` + `View.isDark()` (a canvas palette), and for an
  app's own undo stack `Window.onUndo(undo, redo)` + `registerUndo(name)`
  per change (Edit ▸ Undo / ⌘Z then runs it; `onStandardAction("undo:")`
  never runs while a window is shown — NSWindow answers undo: itself).
  `Timer.runInCommonModes()` keeps a timer firing while a menu is open;
  `uptimeMs()` is a monotonic clock; `executableDir()` the binary's
  directory; `Menu.addHiddenItem` a second shortcut for an action.
- **Type like a keyboard.** `TextInput.typeText(text)` focuses the field
  (selecting its text) and replaces it; `typeKey(text)` types at the
  insertion point without re-focusing (successive calls append, one change
  event each), `deleteBackward()` / `selectAll()` act like Delete and ⌘A, and
  `submit()` presses Return. `onSubmit` is the field's action — Return, and
  for a `TextField` also the end of editing; `onReturn` is Return only and
  `onEndEditing` the end of editing.
- **Colors that show in a quiet window.** AppKit draws a button's bezel
  color and content tint only while the window is key, and a quiet
  self-test's window never is (making it key means activating the app,
  which takes the user's focus), so they never appear in its
  `render` / `snapshot` — check them with `bezelColor()` / `contentTint()`.
  `Button.setTitleColor(color)` (an attributed title) always shows.
- **Drive tables like a user.** `TableView.clickRow(row)` (a single click:
  the table takes the focus, the row becomes the selection, `onSelect` if
  it changed, then the table's action `onClick(row)`; `selectRow` is only
  the selection), `clickHeader(id)` (header click:
  `onHeaderClick` and `onSort`), `doubleClickRow(row)`,
  `clickCheckBox(id, row)` (a check-box column's `onToggle`) and
  `commitEdit(id, row, text)` (the field editor types and gets Return, so
  `onEdit` runs as for a real edit) take AppKit's own path; read back with
  `cellText`, `isChecked`, `columnTitle`, `sortColumn` / `sortAscending`.
- **Undo in a self-test.** All self-test steps run within one event, and
  AppKit closes an event's undo group only when the next event is
  dispatched, so one Undo would take back everything typed.
  `TextArea.endUndoStep()` closes the step as the end of a key press does;
  `TextArea.undo()` / `redo()` act as Edit ▸ Undo / Redo, and `onEdited`
  (unlike `onChange`, which is `textDidChange:` only) also runs after them.
- **Read pixels, not just PNGs.** `View.render()` returns a `Bitmap` tagged
  sRGB before the view draws (exact drawn values, whatever the monitor's
  profile); `Bitmap.colorAt(x, y)` / `View.colorAt` give a `Pixel`
  (`pixelHex(p)` → `#RRGGBB`). `Window.snapshot` / `render` cover the whole
  window; a render commits pending Core Animation work first, so a view
  switched in by the same handler draws.

**Toolchain traps that still reproduce** (re-checked with the installed
tools on 2026-11-02, with a small program
on `loup-bootstrap run`, `loup run`, `loup-bootstrap build --target native`
and `loup build`; a build and a run are the final word — re-check before
working around one). Each is a loud build error, not a miscompile, and the
interpreters run the code, so a `host.dual` module's `loup test` passes while
a native build fails:

- **Not lowered natively:** `list.map` / `filter` with closures,
  `list.reverse()`, `list.is_empty()` (Stage0 ``E-BUILD-NATIVE: … call method
  `reverse` on a managed receiver``, self-hosted `E-CODEGEN-UNHANDLED-METHOD`).
  Write the loop; compare `len()` with 0.
- **Native, inside a closure: a list returned by a method of a
  captured object** (`popup.items()`), bound without a type, loses its list
  type, so `join`, `clone()` and `pop()` on it are refused
  (``E-BUILD-NATIVE: … call method `join` on a managed receiver (in
  `__lambda_…`)``; `len()`, indexing, `contains`, `push` work). Write the
  type out — `let xs: list[string] = popup.items();` — or pass it to a
  typed parameter. The self-hosted build refuses `clone()` the same way
  (`E-CODEGEN-UNHANDLED-METHOD`); its `join` and `pop` work.
- **Native code has no task scheduler and no templates:** `async` / `await`
  (`E-BUILD-NATIVE` names the async function) and a template fence's
  `render` are refused by both native drivers; see
  [references/host-modes.md](references/host-modes.md).

Fixed (no workaround needed; each re-checked on every lane it applies to):
a field read on an object captured by a closure (it used to be resolved by
field name program-wide and read garbage, with any number of captures); the
result of a method a subclass inherits (`let size = canvas.frame();`,
`let b = canvas.render(); b.release();` need no type annotation); a virtual
call on a `list[Base]` element inside another module's function; an
interface method a class only inherits (`Mid implements Named`, `Leaf : Mid`,
called through a `Named` or a `list[Named]` — the override in a subclass
wins); an imported const in another module's const initialiser; an absolute
`path` dependency and a very long package path under `loup build`; an
imported subclass read from a field, returned by a function or mixed into a
list literal where its base class is expected; a closure that builds a
struct literal; `Rect(...)` built in any module; `io.fs` failures are
catchable `IoError`s natively; `list.join`, `clear()`, `clone()` and `pop()`
are lowered natively (but see the closure case above); `char.toLower()` maps
non-ASCII letters natively; float `to_string` prints the same text on every
lane; a let-bound object pushed
into a module-level list or captured by a stored closure keeps its strong
count. A method call on a receiver whose class is not known statically (an
`Any`) that finds no implementation for its runtime type now stops a native
program — ``RuntimeError: no implementation of method `m` for the
receiver's runtime type``, exit 1 — instead of returning an empty value.

Styling goes through the library, not raw `NSColor` / `NSFont` messages:
`appkit.controls` has `ColorRef` colors — `systemColor(COLOR_SECONDARY_LABEL)`,
`COLOR_SYSTEM_RED`, `COLOR_CONTROL_ACCENT`, … (dynamic: they follow Dark
Mode) and `srgbColor(r, g, b, a)` — for `Label.applyTextColor`,
`Button.setTitleColor`, `ImageView.applyTint`, `TextArea.applyTextColor` and a
canvas's `Graphics.applyFillColor`; fonts with weights
(`systemFontWithWeight(size, WEIGHT_LIGHT)`, `monospacedDigitSystemFont` for
figures and timers, `Control.applyFont`, `TableView.setColumnFont`); text
alignment names `TEXT_LEFT` … `TEXT_NATURAL` (`Control.setAlignment`,
`TableView.setColumnAlignment`, `TextArea.setAlignment`; NSTextAlignment's
raw values differ between arm64 and x86-64, `textAlignmentValue` gives the
right one for raw cell code); label sizing (`setMaxWidth`, `textWidth`,
`setShrinkToFit`); and on every `View` the Auto Layout priorities
`setHugging` / `setCompressionResistance` (`PRIORITY_*`) and
`setFocusable(false)`. Text: `TextArea.usePlainText(false)` for an
editor (rich text off, undo on, no smart substitutions), `setBorder`,
`setTextInset`, and the scrollers (`setScrollerStyle(SCROLLER_OVERLAY)` or
`setAutohidesScrollers(true)` — with a mouse attached the system's legacy
style leaves a scroller strip beside short text, also in screenshots;
`setScrollers(vertical, horizontal)`); `Font.isFixedPitch()` checks a
monospaced font; the selection API (`selectedRange` / `setSelectedRange` /
`selectedText` / `scrollRangeToVisible`) counts AppKit's UTF-16 units —
convert Loup string indexes with `appkit.text.utf16Offset` / `scalarIndex`;
`clearUndoHistory()` after loading a file, `breakUndoCoalescing()` after a
save. Canvas: `Graphics.setLineCap(LINE_CAP_ROUND)` / `setLineJoin` /
`setLineDash`, `Canvas.addToolTip(x, y, w, h, text)` per region, and
`canvas.colorAt` / `render()` / `snapshot(path)` (sRGB) plus
`appkit.app.loadBitmap` to check what was drawn or exported. Files a user
picked: `appkit.dialogs.readTextFile(path)` (a `TextRead`: `succeeded`,
`contents`, `failure`) and `writeTextFile(path, text)` (`""` or the failure
message) report problems as values with Foundation's localized message for
the user (ready for an alert) and refuse bytes that are not UTF-8.
`io.fs` failures are catchable `IoError`s on the native lanes too, but
their text is for developers (`read_text failed on '…': No such file or
directory (os error 2)`) and `io.fs.readText` loads non-UTF-8 bytes as
broken text; `io.fs` remains the portable route for `host.dual` code. Save
a typed file with `saveFileWithTypes(name, ["png"])` (the panel adds the
extension and checks for an existing file under the full name; `saveFile`
takes the name as typed); a canned `alert` answer may be `"-1"` (ended
without a button press). Tables: `addCheckBoxColumn` + `onToggle` for check
boxes, `sizeColumnsToFit()` once the table is in its window (the widths given
to `addColumn` do not fill it by themselves), `setColumnResizing(id,
COLUMN_FIXED)` / `setColumnWidthRange` for columns that must not stretch, and
`onSort(column, ascending)` (the direction toggle and indicator are handled).
Grids: column settings may precede the first `addRow`;
`setCellXAlignment` / `setCellYAlignment` place one cell and
`mergeCellRange` merges a block. A stack's `fittingSize` includes its insets
on both sides whatever the alignment.

**The minimal starting point without the library is `examples/macos-counter/` in the Loup
repository** (a window, a label, three buttons, an
app menu with ⌘Q; quits when the window closes). Copy its
`src/appkit.lphc` — the binding layer — into the new app and extend it.
Its API: `appInit(name)`, `window(title, w, h)`, `label(text, size)`,
`button(title, handler: fn(): void)`, `place(win, view, x, y, w, h)`,
`setText(view, text)`, `intValue(view)`, `after(seconds, handler)`,
`click(view)`, `run(win)`, `quit()`.

How it works, for extending it:

1. `NSApplication.sharedApplication`, `setActivationPolicy:` 0 (Regular) so an
   unbundled binary gets a Dock icon and a menu bar, and an app menu whose Quit
   item sends `terminate:`.
2. One Objective-C class, created at run time (`objc_allocateClassPair`), whose
   `onAction:` method is the Loup function `onAction` (`addressOf`). Every
   control's target is its single instance; the control's `tag` indexes a Loup
   `list[fn(): void]` of handlers. The same object is the app delegate
   (`applicationShouldTerminateAfterLastWindowClosed:` → 1).
3. Views are created by messaging AppKit classes and positioned with
   `setFrameOrigin:` / `setFrameSize:` (two `float`s each — portable to x86-64).
4. `makeKeyAndOrderFront:`, `activateIgnoringOtherApps:` 1, then `run`.
   (The appkit library skips the activation and hides the windows in a
   `--self-test`; the counter example does not.)

```sh
cd examples/macos-counter      # in a checkout of the Loup repository
loup build                     # links -framework AppKit -lobjc
./macos-counter                # the window
./macos-counter --self-test    # clicks the buttons through the real run loop, prints, quits
```

Test GUI code with a `--self-test` mode like the example's: schedule a handler
with `after(0.2, …)`, drive controls with `click(view)` (`performClick:`), read
them back (`intValue`, or `isEqualToString:` against an `nsstr`), print, then
`quit()`. In the Loup repository, `tests/ffi_native/run.sh` runs the
example's self-test on both drivers.

**Status (Loup after 1.27.0):**

| Piece | State |
|---|---|
| Linking AppKit/Foundation/libobjc, `@symbol`, messaging, double args/returns | works (self-hosted and Stage0 routes) |
| Callbacks (actions, delegates, timers) through `addressOf(f)`, including `float` / `NSRect` parameters | works |
| Windows, labels, buttons, menus | works (`examples/macos-counter` in the Loup repository) |
| Controls, layout stacks, tables, custom drawing, text views, dialogs | works (this repository's `appkit` library) |
| Reading a view's frame (struct results) | through key-value coding: `appkit.objc.rect_of(obj, "frame")` (an `NSValue` read into memory); a struct cannot be returned by `objc_msgSend` to Loup |
| `NSRect` arguments on x86-64 | not available (arm64 passes them as four `float`s) |
| Converting an `NSString` back to a Loup `string` | `appkit.objc.str_of(ns)` (UTF-8 bytes through `getCString:maxLength:encoding:`) |
| `.app` bundles (Info.plist, icon) | not provided by the toolchain; the unbundled executable with activation policy Regular works |
| `loup run` of a GUI program | not possible (no FFI in the interpreters) |

## 8. Verify

- `loup-build --verbose` prints every step, including the
  `native libraries:` line, so a missing `-framework` is visible.
- `file <binary>` must say `Mach-O 64-bit executable arm64` (or `x86_64`).
- Test non-FFI logic with `loup test` on `host.dual` modules; test the FFI
  layer by building and running a small native program that prints values.
- Never claim a GUI works without building it and launching it.
