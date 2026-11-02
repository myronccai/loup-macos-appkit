# Agents.md — loup-macos-appkit

This repository is the `appkit` library: Loup proxy classes over AppKit
(package name `appkit`, imported as `appkit.app`, `appkit.controls`, …) for
native macOS (AppKit) applications written in Loup. It is also the home of
the Loup macOS example collection: ten apps, each its own repository
(https://github.com/myronccai/loup-macos-calculator, …), all built on this
library and all checked by this repository's `run_all.sh`. Start with
[README.md](README.md): the library's modules, the list of apps, the
requirements, and how to build and test.

## Where things are

- The library is this repository's root: `appkit.lppkg` and one `.lphc`
  file per module (`app`, `controls`, `layout`, `table`, `canvas`, `text`,
  `dialogs`, `objc`). Each module's header comment is its reference;
  [`docs/`](docs) has longer notes for `canvas`, `dialogs` and `table`.
  `probes/<module>_probe/` are small programs exercising each module.
- [`skills/loup-macos-developer-skill/SKILL.md`](skills/loup-macos-developer-skill/SKILL.md)
  — the Loup macOS developer skill, bundled with the library.
- `run_all.sh` — the gate for the library, its probes and every app.
- The apps are sibling checkouts in this repository's PARENT directory,
  never inside it: `../loup-macos-<name>/`, one application per
  repository (https://github.com/myronccai/loup-macos-<name>):
  `loup-macos-<name>.lppkg` (with
  `appkit = { path = "../loup-macos-appkit" }`), `src/main.lphc` (UI,
  `host.native`), `src/*.loup` (logic, `host.dual`), `src/*_test.lpscr`
  (`loup test`), `selftest.out`, `screenshot.png`, its own `README.md` and
  `Agents.md`. `run_all.sh` checks every `loup-macos-*` directory beside
  this one.

## How to work here

- Read the Loup macOS skill first:
  [`skills/loup-macos-developer-skill/SKILL.md`](skills/loup-macos-developer-skill/SKILL.md)
  (host modes, `extern native`, Objective-C messaging, callbacks, the
  library, self-tests). From an app checkout it is
  `../loup-macos-appkit/skills/loup-macos-developer-skill/SKILL.md`.
- Toolchain: Loup newer than 1.27.0 (`loup`, `loup-build`, `loup-llvm`,
  `loup-test`, `loup-bootstrap` on `PATH`); the library and the apps need
  fixes made after the 1.27.0 release ([Loup releases](https://github.com/code-craft-ai-company/loup-releases/releases)). macOS (Apple silicon or Intel)
  with the Xcode Command Line Tools.
- Every build needs an SDK the linker understands; if a link fails with
  `tapi error … unknown architecture`, point at an older one, e.g.
  `export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.
- Verify a change with `bash run_all.sh <app>` from inside this
  repository (both drivers, `loup test`, self-test against `selftest.out`;
  from an app checkout, `bash ../loup-macos-appkit/run_all.sh <app>`); a
  library change with `bash run_all.sh --probes` and every app (clone the
  apps next to this repository first; `bash run_all.sh` with no app names
  checks every `loup-macos-*` sibling).
- Never launch an app without `--self-test` from an automated session (it
  opens a real window that waits for a person), and never let a self-test show
  real modal UI: queue answers with `appkit.dialogs.setTestAnswers`.
- Keep app logic in `host.dual` modules so `loup test` covers it; the
  interpreters have no FFI, so AppKit code is `host.native` only.
- Drive menus and keys in a self-test through the library, not raw
  Objective-C: `MenuItem.perform()`, `Menu.sendKey` / `Window.sendKey`,
  `Window.sendAction`, `Window.performClose()`, `shouldQuit()`. A quiet
  self-test's window is never key (AppKit gives an app that was never
  activated no key window), so AppKit itself would send a standard action
  (Close, Copy, Undo) nowhere; these helpers send it along the shown window's
  responder chain. `sendKey` with modifiers sends the event a real key press
  makes, so ("c", MOD_SHIFT_COMMAND) and ("C", MOD_SHIFT_COMMAND) both press
  ⇧⌘C, whichever way the item was declared. Read pixels with
  `View.render()` / `View.colorAt` (sRGB); a render draws each label's text once, so translucent
  label colors look as they do on screen.
- Windows and documents: `Window.setDocumentEdited` / `isDocumentEdited`,
  `setRepresentedFilename`, `isVisible`, `hide()` (orderOut), `minSize()`,
  `focus(view)` / `hasFocus(view)` (any view, e.g. a table — not raw
  `makeFirstResponder:`), `setAppearance("dark" | "light" | "")` and
  `View.isDark()` for a view's own palette. Undo of an app's own document
  changes: `Window.onUndo(undo, redo)` + `registerUndo(name)` per change —
  NOT `onStandardAction("undo:")`, which never runs while a window is shown
  (NSWindow answers undo:/redo: itself). A throwing `onShouldClose` /
  `onShouldQuit` handler refuses. Timers that must run while a menu is open:
  `Timer.runInCommonModes()`; a monotonic clock: `uptimeMs()`; the binary's
  directory for scratch files: `executableDir()`. A hidden menu item whose
  shortcut still works: `Menu.addHiddenItem`.
  Drive tables the same way: `TableView.clickRow(row)` (a single click: the
  table takes the focus, the row becomes the selection, `onSelect` when it
  changed, then `onClick(row)` — not `selectRow`, which skips the focus and
  the click), `clickHeader(id)`, `doubleClickRow(row)`,
  `clickCheckBox(id, row)` and `commitEdit(id, row, text)` take the path a
  user's action takes, so the app's `onClick`, `onHeaderClick` / `onSort`,
  `onDoubleClick`, `onToggle` and `onEdit` handlers run; read back with
  `cellText`, `isChecked`, `columnTitle`, `sortColumn` / `sortAscending`.
- Tables and grids: check boxes are `addCheckBoxColumn` + `onToggle`; make
  columns fill the table with `sizeColumnsToFit()` once it is in its window;
  keep narrow columns fixed with `setColumnResizing(id, COLUMN_FIXED)`. A
  `GridView` takes column settings before its first `addRow`, and
  `setCellXAlignment` / `setCellYAlignment` / `mergeCellRange` for single
  cells; a missing cell, row or column throws ValueError instead of an
  uncaught NSRangeException.
- Text, drawing and files: a plain-text editor is
  `TextArea.usePlainText(false)` (+ `setBorder`, `setTextInset`); select and
  find with `setSelectedRange` / `selectedRange` / `selectedText` /
  `scrollRangeToVisible` — AppKit's UTF-16 units, converted from Loup string
  indexes with `appkit.text.utf16Offset` / `scalarIndex`; use `onEdited`
  (runs after Undo / Redo too) rather than `onChange` for anything that must
  track the text; after loading a file call `clearUndoHistory()`, after a
  save `breakUndoCoalescing()`. In a self-test, `endUndoStep()` between typing
  steps (otherwise one Undo takes all of them) and `undo()` / `redo()`.
  Canvas strokes: `setLineCap` / `setLineJoin` / `setLineDash`; per-region
  tool tips: `Canvas.addToolTip`; check drawing with `canvas.colorAt` /
  `render()` and an exported PNG with `appkit.app.loadBitmap`. Read and write
  a user's file with `appkit.dialogs.readTextFile` / `writeTextFile`: they
  report failure as a value carrying Foundation's localized message for the
  user (ready for an alert) and refuse bytes that are not UTF-8. `io.fs`
  failures are catchable `IoError`s natively too, but their messages are for
  developers (op, path, errno) and `io.fs.readText` loads non-UTF-8 bytes as
  broken text; keep `io.fs` for portable `host.dual` code. Ask for a save
  path with `saveFileWithTypes(name, ["png"])` when the file has a type: the
  panel adds the extension and checks for an existing file under the full
  name (`saveFile` takes the name as typed). A canned `alert` answer may be
  `"-1"` (the alert ended without a button press). A text area without a
  legacy scroller strip: `TextArea.setScrollerStyle(SCROLLER_OVERLAY)` or
  `setAutohidesScrollers(true)`; a monospaced check: `Font.isFixedPitch()`.
- A probe with a `selftest.out` (`core_probe`, `controls_probe`,
  `canvas_probe`, `table_probe`, `text_probe`) is checked against it like an
  app (`layout_probe` prints font-dependent frames, and `dialogs_probe`
  sound-device results and Foundation's localized file-error messages, so
  they have none: only the two drivers' outputs are compared); keep its output free of machine-dependent values (screen scale,
  appearance — print comparisons such as "differs between light and dark",
  not resolved system colors — window positions, raw NSTextAlignment values,
  which differ between arm64 and x86-64).
- Colors: use `appkit.controls` `systemColor(COLOR_…)` (dynamic, follows Dark
  Mode) or `srgbColor` with `Label.applyTextColor`, `Button.setTitleColor`,
  `Graphics.applyFillColor`, …, not raw `[NSColor …]` messages (a button's
  bezel color and content tint never show in a quiet self-test's
  screenshot — the window is never key — so use `setTitleColor` where a
  screenshot must show a color); fonts:
  `systemFontWithWeight`, `monospacedDigitSystemFont`; text alignment: the
  `TEXT_*` names (and `textAlignmentValue` for raw cell code); typing in a
  self-test: `typeKey` / `deleteBackward` / `selectAll` / `submit`; Return
  only: `onReturn` (`onSubmit` also fires when a TextField's editing ends);
  keeping a field at its natural size in a stack:
  `setCompressionResistance(…, PRIORITY_REQUIRED)`.
- Toolchain traps — re-checked with the installed tools on 2026-11-02,
  with a small program on each lane
  (`loup-bootstrap run`, `loup run`, `loup-bootstrap build --target native`,
  `loup build`). A build and a run are the final word; re-check before
  working around anything.
  - Still real: not lowered natively (a loud build error, never a
    miscompile): `list.map` / `filter` with closures, `list.reverse()`,
    `list.is_empty()` (Stage0 `E-BUILD-NATIVE`, self-hosted
    `E-CODEGEN-UNHANDLED-METHOD`). Write the loop, compare `len()` with 0.
    The interpreters run them, so a `host.dual` module's `loup test` passes
    while its native build fails.
  - Still real (native, a loud build error): inside a closure,
    the un-annotated result of a method called on a CAPTURED object loses
    its list type, so `join`, `clone()` and `pop()` on it are refused
    (``E-BUILD-NATIVE: … call method `join` on a managed receiver (in
    `__lambda_…`)``); `len()`, indexing, `contains` and `push` work, and so
    does the same call outside a closure or on a closure parameter. Bind the
    result with its type (`let xs: list[string] = popup.items();`) or pass
    it to a typed parameter (controls_probe's `joined`). The self-hosted
    build refuses `clone()` the same way (`E-CODEGEN-UNHANDLED-METHOD`); its
    `join` and `pop` work.
  - Fixed, no workaround needed (re-checked on every lane each applies to):
    a field read on an object captured by a closure (any number of
    captures); the result of a method a subclass inherits
    (`let size = canvas.frame()`, `let b = canvas.render(); b.release();`);
    a virtual call on a `list[Base]` element in another module's function;
    an interface method a class only inherits (`Mid implements Named`,
    `Leaf : Mid`, called as a `Named`, also in a `list[Named]`); an
    imported const in another module's const initialiser (loup-macos-calculator's
    keypad tables are `const`s); an absolute `path` dependency and a long
    package path under `loup build`; an imported subclass read from a field,
    returned by a function or mixed in a list literal where its base is
    expected; a closure that builds a struct literal; `list.join`,
    `clear()`, `clone()`, `pop()` natively (apart from the closure case
    above); `Rect(...)` built in any module.
    The habits the probes and apps adopted for the old captured-field bug
    (capturing plain handles, self-tests as module functions over
    module-level lists, the field names `Bitmap.rep`,
    `ColorRef.color_handle`, `TextRead.succeeded`) stay valid; they are no
    longer required.
  - A method call that finds no implementation for the receiver's runtime
    type (an `Any` receiver) stops a native build's program with
    ``RuntimeError: no implementation of method `m` …`` and exit 1, instead
    of returning an empty value.

## License

MIT (see [LICENSE](LICENSE)); every app repository carries the same license.
