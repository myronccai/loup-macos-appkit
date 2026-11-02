# appkit: AppKit for Loup, and the Loup macOS example apps

`appkit` is a Loup library for native macOS GUI applications: Loup proxy
classes over AppKit (package name `appkit`, imported as `appkit.app`,
`appkit.controls`, …). Programs that use it are built into Mach-O
executables with the self-hosted Loup toolchain (`loup build`) or with the
Stage0 bootstrap compiler (`loup-bootstrap build --target native`).

This repository is also the home of the Loup macOS example collection: ten
complete apps, each in its own repository, all built on this library and
all checked by this repository's gate, [`run_all.sh`](run_all.sh).

| In this repository | What it is |
|---|---|
| `*.lphc`, [`appkit.lppkg`](appkit.lppkg) | **The `appkit` library** (see below). Each module's header comment is its reference. |
| [`docs/`](docs) | Longer notes for [`canvas`](docs/canvas.md), [`dialogs`](docs/dialogs.md) and [`table`](docs/table.md). |
| [`probes/`](probes) | A probe program per module (`<module>_probe/`), each driven by its own `--self-test`. |
| [`run_all.sh`](run_all.sh) | The gate: builds every app with both drivers, runs its `loup test` suite and its `--self-test`; `--probes` adds the probes. |
| [`skills/loup-macos-developer-skill/`](skills/loup-macos-developer-skill/SKILL.md) | The Loup macOS developer skill (host modes, `extern native`, Objective-C messaging, callbacks, the library, self-tests), bundled for people and coding agents. |
| [`Agents.md`](Agents.md) | Working notes for coding agents. |

## The example apps

| Repository | What it is |
|---|---|
| [loup-macos-calculator](https://github.com/myronccai/loup-macos-calculator) | A desktop calculator with memory keys (button grid, display label). |
| [loup-macos-todo](https://github.com/myronccai/loup-macos-todo) | A to-do list: table with check boxes, filtering, open/save. |
| [loup-macos-unit-converter](https://github.com/myronccai/loup-macos-unit-converter) | Live unit conversion with category and unit pop-ups. |
| [loup-macos-stopwatch](https://github.com/myronccai/loup-macos-stopwatch) | Stopwatch with laps, and a countdown timer (tabs, timers, progress bar). |
| [loup-macos-sketchpad](https://github.com/myronccai/loup-macos-sketchpad) | A drawing app on a custom canvas: pen, line, rectangle, oval, undo, PNG export. |
| [loup-macos-notepad](https://github.com/myronccai/loup-macos-notepad) | A plain-text editor: File menu, find, live text statistics. |
| [loup-macos-loan-calculator](https://github.com/myronccai/loup-macos-loan-calculator) | Loan payments and a live amortization table. |
| [loup-macos-color-mixer](https://github.com/myronccai/loup-macos-color-mixer) | RGB / HSB / hex color mixing with harmony swatches. |
| [loup-macos-life](https://github.com/myronccai/loup-macos-life) | Conway's Game of Life on a canvas, with patterns and a timer. |
| [loup-macos-control-gallery](https://github.com/myronccai/loup-macos-control-gallery) | Every control and container the library wraps, with a coverage table. |

Each app keeps its logic in `host.dual` modules (tested with `loup test`,
runnable interpreted) and its user interface in `host.native` code that uses
the `appkit` library. Each has a `README.md`, a `screenshot.png` taken by its
own self-test, and a `selftest.out` golden. Every app depends on this
library by a relative path (`appkit = { path = "../loup-macos-appkit" }`),
so clone this repository next to it, in the same parent directory.

## The `appkit` library

AppKit is an Objective-C framework; Loup reaches it through `extern native`
declarations bound to `objc_msgSend` with `@symbol`, and AppKit calls back into
Loup through functions handed out with `addressOf(f)` (Loup Language Reference
Vol 2 §2-3.4, Vol 3 §3-3.4.2). The library hides all of that behind proxy
classes: each proxy holds its Objective-C object as `handle` and extends
`appkit.app.View`, so it can be placed in any window or container.

| Module | Provides |
|---|---|
| `appkit.app` | `appInit`, `run`, `quit`, `Window` (resizable or fixed, fit to content, `minSize`, `isVisible` / `hide`, document state `setDocumentEdited` / `setRepresentedFilename`, `setAppearance` / `isDark`, keyboard focus `focus(view)` / `hasFocus`, a document undo hook `onUndo` + `registerUndo` on the window's undo manager, close / quit veto hooks (a throwing hook refuses), `snapshot` / `render`, `sendKey` / `sendAction` test helpers), `View` (with `render` / `snapshot` / `colorAt`, `isDark`, Auto Layout `setHugging` / `setCompressionResistance` with `PRIORITY_*`, `setFocusable`), `Bitmap` / `Pixel` (sRGB read-back of what a view drew; `loadBitmap` reads an exported PNG back, `Bitmap.isSrgb`), `Menu` / `MenuItem` (menu-bar placement, the standard menus, modifier masks, hidden items with working shortcuts `addHiddenItem`, `perform`, `checked`), `onStandardAction` (copy: / paste: … on the responder chain), `Timer` / `after` / `every` (`runInCommonModes` keeps firing during menu tracking), the monotonic clock `uptimeSeconds` / `uptimeMs`, `executablePath` / `executableDir`, `isSelfTest`, `isDarkMode`, `setHandlerErrorsFatal`, action and text-change dispatch |
| `appkit.controls` | `Label` (shrink-to-fit, `setMaxWidth`, text measurement), `Button` (title / bezel colors, key equivalents with modifiers), `Checkbox`, `RadioGroup`, `Switch`, `TextField`, `SecureField`, `SearchField` (`typeKey` / `deleteBackward` / `selectAll` test typing, `onReturn`, `onEndEditing`), `Slider`, `Stepper`, `PopUpButton`, `ComboBox`, `SegmentedControl`, `ProgressBar`, `Spinner`, `LevelIndicator`, `ColorWell`, `DatePicker`, `ImageView`, `Font` (weights `WEIGHT_*`, `monospacedDigitSystemFont`, `isFixedPitch`), `ColorRef` (dynamic system colors `systemColor(COLOR_*)` that follow Dark Mode, and `srgbColor`), the text alignment names `TEXT_*` and `textAlignmentValue` |
| `appkit.layout` | `VStack`, `HStack` (`fittingSize` includes the insets on both sides whatever the alignment), `GridView` (column settings before the first row, per-cell placement `setCellXAlignment` / `setCellYAlignment`, block merges `mergeCellRange`, checked indexes), `TabView`, `SplitView`, `ScrollView`, `Box`, `Separator`, `pinToEdges`, `fillWindow` |
| `appkit.table` | `TableView` (columns, data callbacks, selection, editing, check-box columns with `onToggle`, column alignment, fonts, widths, resizing modes and `sizeColumnsToFit`, header titles, `onSort` with the direction toggle, `onClick` for every single click, test helpers `clickRow` / `clickHeader` / `doubleClickRow` / `clickCheckBox` / `commitEdit`), `ListView` (`LIST_COLUMN`) |
| `appkit.canvas` | `Canvas` (custom drawing through `Graphics`, mouse and key events, per-region tool tips `addToolTip`, pixel read-back and sRGB PNG export through `render` / `colorAt` / `snapshot`), `Graphics` line caps, joins and dashes (`LINE_CAP_*`, `LINE_JOIN_*`, `setLineDash`) |
| `appkit.text` | `TextArea` (an `NSTextView` in a scroll view; font, alignment and text color; plain-text editor setup `usePlainText`, border, inset; scrollers `setScrollerStyle(SCROLLER_OVERLAY)` / `setAutohidesScrollers` / `setScrollers`; selection `selectedRange` / `setSelectedRange` / `selectedText` / `scrollRangeToVisible` as a `TextRange` in UTF-16 units, with `utf16Offset` / `scalarIndex`; `undo` / `redo`, `endUndoStep`, `breakUndoCoalescing`, `clearUndoHistory`; `onEdited`, which also runs after Undo and Redo) |
| `appkit.dialogs` | alerts, `prompt`, open / save panels (`saveFileWithTypes` adds and checks the extension), clipboard, sounds, `openURL`, `revealInFinder`, text files read and written with Foundation's user-facing failure message and a UTF-8 check (`readTextFile` → `TextRead`, `writeTextFile`), canned answers for self-tests (`setTestAnswers`, including an alert's `"-1"`) |
| `appkit.objc` | the Objective-C runtime layer: message shapes, selectors, `NSString` ↔ `string`, reading struct-valued properties |

Each module has a probe program under [`probes/`](probes):
`core_probe` (`appkit.objc` and `appkit.app`), `controls_probe`,
`layout_probe`, `table_probe`, `canvas_probe`, `text_probe` and
`dialogs_probe`.

## Getting started

### Requirements

- macOS on Apple silicon or Intel, with the Xcode Command Line Tools
  (`xcode-select --install`).
- A Loup toolchain of version **newer than 1.27.0**, with `loup`, `loup-build`,
  `loup-llvm`, `loup-test` and `loup-bootstrap` on `PATH`. The library and
  the apps need toolchain fixes made after the 1.27.0 release ([Loup releases](https://github.com/code-craft-ai-company/loup-releases/releases)).

If linking fails with `tapi error … unknown architecture`, the default SDK is
newer than the linker understands; point `SDKROOT` at an older SDK, e.g.
`export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`
(list them with `ls /Library/Developer/CommandLineTools/SDKs`).

### Using the library from your own package

Clone this repository next to your project, so both sit in the same parent
directory:

```sh
git clone https://github.com/myronccai/loup-macos-appkit.git
# …/loup-macos-appkit
# …/my-app            (your package)
```

Then depend on it with a relative path dependency, and link AppKit (its
classes are found by name at run time, so nothing the program calls pulls
the framework in):

```toml
[build]
entry = "src/main.lphc"
mode = "host.native"
delivery = "native"

[dependencies]
appkit = { path = "../loup-macos-appkit" }

[delivery.native]
framework = ["AppKit"]
```

Any of the example apps is a complete starting point; the
[skill](skills/loup-macos-developer-skill/SKILL.md) explains host modes,
`extern native` and self-tests.

### Building and testing an app

Clone the apps you want next to this repository (the gate checks every
`loup-macos-*` directory beside it):

```sh
mkdir loup-macos && cd loup-macos
git clone https://github.com/myronccai/loup-macos-appkit.git
git clone https://github.com/myronccai/loup-macos-calculator.git
# … and any of the other apps
```

```sh
cd loup-macos-calculator
loup build                              # → ./loup-macos-calculator
./loup-macos-calculator                 # the app
loup test --strict src                  # the logic tests
./loup-macos-calculator --self-test     # drives the UI, prints, quits

bash ../loup-macos-appkit/run_all.sh loup-macos-calculator   # both drivers, tests and self-test
```

### Running the probes and the whole collection

From inside `loup-macos-appkit`:

```sh
bash run_all.sh                    # every app cloned beside this repository, both drivers, tests and self-tests
bash run_all.sh --probes           # … and the library's probes
bash run_all.sh loup-macos-todo    # one app
bash run_all.sh --probes loup-macos-todo                 # one app and the probes
bash run_all.sh --screenshots loup-macos-calculator      # refresh one screenshot
```

`run_all.sh` builds each app with the self-hosted toolchain (`loup build`)
and with Stage0 (`loup-bootstrap build --target native`), runs its
`loup test --strict src`, and runs both binaries' `--self-test` against the
app's `selftest.out` (the two outputs must also agree). `TIMEOUT` sets the
seconds allowed per self-test (default 30).

### Quiet self-tests

A `--self-test` run stays off the screen of the person running it: no Dock
icon, no focus taken, transparent windows that let clicks through (they still
lay out and draw, so screenshots work), no sounds, and no real dialogs (the
self-test queues canned answers with `appkit.dialogs.setTestAnswers`). Set
`LOUP_APPKIT_VISIBLE=1` to watch one. `run_all.sh` runs every self-test under
`lldb`, so a crash prints a backtrace instead of opening a crash report.
A handler that throws during a self-test ends it with exit status 1 (outside
a self-test it is only reported; a throwing `onShouldClose` / `onShouldQuit`
hook refuses the close or quit; `setHandlerErrorsFatal(false)` lets a
self-test check that). Such a window is never the key window, so
the self-test drives menus and keys through `MenuItem.perform()`,
`Window.sendKey` and `Window.sendAction`, which send standard (nil-targeted)
actions along the shown window's responder chain as if it were key; a key
with modifiers is the event a real key press makes, so ⇧ + a key matches as
on the keyboard (an item set as ("c", `MOD_SHIFT_COMMAND`) takes ⇧⌘C). It types
into fields with `TextInput.typeKey` (one key at a time at the insertion
point, a change event per key), `deleteBackward`, `selectAll` and `submit`
(Return), and clicks table rows with `TableView.clickRow` (the focus, the
selection, `onSelect` and `onClick`). AppKit draws a button's bezel color
and content tint only in a key window, so they never show in a quiet
self-test's screenshot (`bezelColor()` / `contentTint()` read them back); a
color that must show goes in the title (`Button.setTitleColor`). A self-test's steps all run within one event, so AppKit
never closes the undo group between them: `TextArea.endUndoStep()` closes it
the way the end of a key press does, and `TextArea.undo()` / `redo()` act as
Edit ▸ Undo / Redo (`onEdited` runs after them).

## License

MIT; see [LICENSE](LICENSE). Copyright (c) 2026 Code Craft AI LLC. Each
example app carries the same license in its own repository.
