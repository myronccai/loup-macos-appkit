# appkit.dialogs

Modal dialogs (NSAlert, NSOpenPanel, NSSavePanel) and the system services an
app needs next to them: the clipboard (NSPasteboard), the beep, named sounds
(NSSound), opening URLs and revealing files in the Finder (NSWorkspace).

```loup
from appkit.dialogs import (alert, confirm, info, prompt, openFile, openFolder, saveFile,
    saveFileWithTypes, copyText, pasteText, beep, playSound, openURL, revealInFinder, setTestAnswers);
```

(The module also exports `clipboardHasText`, `saveClipboard`,
`restoreClipboard`, `ClipboardContents`, `hasSound`, `soundCopiesPlaying`,
`testAnswersLeft`, `testLog`, the text-file helpers `readTextFile`,
`writeTextFile` and `TextRead`, and the constants below.)

Every function runs on the main thread. A dialog function blocks the calling
handler until the user answers; the app keeps redrawing meanwhile. Call the
dialogs from an event handler (a button's `onAction`, a menu item, a timer),
after `appInit`.

## Example

```loup
@mode(host.native)

from appkit.objc import (cls, sel, nsstr, msgIII);
from appkit.app import (appInit, run, onAction, Window, View);
from appkit.dialogs import (alert, prompt, openFile, copyText);

pub func main(): void {
    appInit("Notes");
    let win = Window("Notes", 300.0, 120.0);
    let b = View(msgIII(cls("NSButton"), sel("buttonWithTitle:target:action:"), nsstr("Open…"), 0, 0));
    win.add(b, 20.0, 40.0, 120.0, 32.0);
    onAction(b.handle, func(): void {
        let path = openFile(["txt", "md"]);
        if (path == "") {
            return;                                 # cancelled
        }
        let name = prompt("Rename", "New title for " + path + ":", "Untitled");
        let choice = alert("Copy the title?", name, ["Copy", "Don't Copy"]);
        if (choice == 0) {
            copyText(name);
        }
    });
    run(win);
}
```

## Dialogs

| Function | Shows | Returns |
|---|---|---|
| `alert(title: string, message: string, buttons: list[string]): int` | An NSAlert with `title` (bold), `message` and one button per entry. The first is the default (Return); a button titled "Cancel" answers Escape. `[]` adds a single "OK" button. | The 0-based index of the pressed button (`runModal` − `ALERT_FIRST_BUTTON`); `[]` returns 0 for its "OK". `-1` when the alert ended without a button press (other code called `stopModal` / `abortModal`). |
| `confirm(title: string, message: string): bool` | An alert with "OK" (default) and "Cancel". | `true` for OK. |
| `info(title: string, message: string): void` | An alert with one "OK". | Nothing (it returns once the alert is dismissed). |
| `prompt(title: string, message: string, defaultText: string): string` | An alert with a text field pre-filled with `defaultText` (it has focus, text selected), "OK" and "Cancel". | The typed text, or `""` when cancelled. |
| `openFile(allowedExtensions: list[string]): string` | An NSOpenPanel choosing one file. `allowedExtensions` without dots (`["txt", "md"]`); `[]` allows any file. | The chosen path, or `""` when cancelled. |
| `openFolder(): string` | An NSOpenPanel choosing one folder (with New Folder). | The folder's path, or `""` when cancelled. |
| `saveFile(suggestedName: string): string` | An NSSavePanel proposing `suggestedName` (`""` for none). The panel itself asks about replacing an existing file. It takes any name as typed (`drawing` stays `drawing`, and the replace check sees only that name). Nothing is written. | The chosen path, or `""` when cancelled. |
| `saveFileWithTypes(suggestedName: string, allowedExtensions: list[string]): string` | An NSSavePanel restricted to the types of `allowedExtensions` (without dots: `["png"]`, `["txt", "md"]`; `setAllowedContentTypes:`). A name typed without one of their extensions gets the first type's preferred extension (`drawing` → `drawing.png`; `jpg` prefers `jpeg`), and the panel asks about replacing an existing file under that full name. `[]` allows any name, as `saveFile`. Nothing is written. | The chosen path, with the extension, or `""` when cancelled. |

A cancelled prompt and a prompt answered with an empty field both return
`""`.

The real and the canned paths agree: `alert(t, m, [])` returns 0 both when
a person clicks its "OK" and when the canned answer is `"0"`. (NSAlert's own
fallback button, made when no button is added, has tag 0 and would make
`runModal` return 0, not 1000; `alert` always adds its buttons itself so the
index arithmetic holds.)

## Clipboard

| Item | Meaning |
|---|---|
| `copyText(text: string): bool` | Replace the clipboard's contents with `text` (type `public.utf8-plain-text`). Returns whether the pasteboard accepted it. |
| `pasteText(): string` | The clipboard's text, `""` when it holds none. |
| `clipboardHasText(): bool` | Whether the clipboard holds text (tells "no text" from an empty string). |
| `saveClipboard(): ClipboardContents` | A copy of everything on the clipboard: every item, with the data of every type it offers. |
| `restoreClipboard(saved: ClipboardContents): void` | Put the saved contents back (replacing the clipboard) and release the copy. A `ClipboardContents` restores once: a second `restoreClipboard` on it throws `RuntimeError` (it never touches the released copy). |
| `class ClipboardContents` | The saved copy: `handle` (a retained NSArray of NSPasteboardItems) and `count(): int` (how many items; throws `RuntimeError` after the restore). |

```loup
let saved = saveClipboard();
copyText("temporary");
println(pasteText());                 # temporary
restoreClipboard(saved);              # the user's clipboard is back
```

## Text files

Reading or writing the file a user picked in `openFile` / `saveFile` can
fail (a missing file, a folder, no permission, bytes that are not UTF-8, a
folder that does not exist). These helpers REPORT that as a value with
Foundation's own localized message, written for the user, instead of
throwing.

`io.fs` works in a native app too: its failures are `IoError`s that
`catch` catches on every lane. The helpers exist for what `io.fs` does not
give a GUI app:

- **A message to show.** `readTextFile` gives Foundation's sentence for
  the user (`The file “x.txt” couldn’t be opened because there is no such
  file.`, in the user's language); an `io.fs` `IoError` is written for
  developers (`read_text failed on '…/x.txt': No such file or
  directory (os error 2)`).
- **The UTF-8 check.** `io.fs.readText` loads bytes that are not UTF-8 (a
  Latin-1 file) as broken text; `readTextFile` refuses them and says why.
- **Atomic writes** (a temporary file renamed over the target).

`io.fs` stays the portable route — it works in every host mode and in
`loup test` — and these helpers are macOS-only (`host.native`).

| Item | Meaning |
|---|---|
| `readTextFile(path: string): TextRead` | Read a UTF-8 text file (`+[NSString stringWithContentsOfFile:encoding:error:]`). Never throws for a file problem. |
| `struct TextRead` | `succeeded: bool`; `contents: string` (the text, `""` on failure); `failure: string` (`""` on success, else the NSError's `localizedDescription`, e.g. `The file “x.txt” couldn’t be opened because there is no such file.`). |
| `writeTextFile(path: string, text: string): string` | Write `text` as UTF-8, replacing the file atomically (`-writeToFile:atomically:encoding:error:`). Returns `""` on success, else the failure message. Never throws for a file problem. |

Paths are used as given (no `~` expansion). The messages are localized
(the user's language), so show them; a test should check `succeeded` and
`failure != ""`, not the wording.

```loup
let path = openFile(["txt"]);
if (path != "") {
    let r = readTextFile(path);
    if (r.succeeded) {
        editor.setText(r.contents);
    } else {
        info("The document could not be opened.", r.failure);
    }
}
let problem = writeTextFile(savePath, editor.text());
if (problem != "") {
    info("The document could not be saved.", problem);
}
```

## Sounds

| Function | Meaning |
|---|---|
| `beep(): void` | The system alert sound (`NSBeep`). |
| `hasSound(name: string): bool` | Whether `[NSSound soundNamed:name]` finds a sound: a system sound ("Tink", "Glass", "Ping", "Pop", "Submarine", …) or a sound file in the app bundle, named without its extension. |
| `playSound(name: string): bool` | Start playing that sound and return at once. Quick repeated calls overlap: `soundNamed:` hands out one shared NSSound, and while it is still playing `playSound` plays a copy of it instead (so a click sound on every key press is never dropped). `false` when there is no such sound or the sound device refused it. |
| `soundCopiesPlaying(): int` | How many such extra copies `playSound` still holds. Finished copies are released on the next `playSound`. |

## Workspace

| Function | Meaning |
|---|---|
| `openURL(url: string): bool` | Open `url` (`https://…`, `mailto:…`, `file:///…`) in its default app. `false` when it is not a valid URL or nothing opened it. |
| `revealInFinder(path: string): bool` | Select the file or folder at `path` in a Finder window. `false` when it does not exist. |

## Constants

| Constant | Value |
|---|---|
| `ALERT_FIRST_BUTTON: int` | 1000 (`NSAlertFirstButtonReturn`) |
| `PANEL_OK: int` | 1 (`NSModalResponseOK`) |
| `PASTEBOARD_TEXT: string` | `"public.utf8-plain-text"` (`NSPasteboardTypeString`) |

## Testing: canned answers

A modal dialog stops the event loop until a person answers, so a
`--self-test` cannot drive one. Queue the answers instead:

| Function | Meaning |
|---|---|
| `setTestAnswers(answers: list[string]): void` | Replace the queue of canned answers and clear `testLog()`. `setTestAnswers([])` turns them off. |
| `testAnswersLeft(): int` | How many answers are still queued (0: the real dialogs run). |
| `testLog(): list[string]` | One line per answered call, in order: `<function>: <what it would have shown> -> <answer>`. |

While answers are left, each of these functions takes the next answer and
returns WITHOUT showing anything (or leaving the app):

| Function | Canned answer |
|---|---|
| `alert` | The button index as a decimal string: `"0"`, `"1"`, …, or `"-1"`: the alert ended without a button press (what `alert` returns when other code stopped the modal session). Non-numbers, other negative numbers and indexes past the last button throw `ValueError`. |
| `confirm` | `"yes"` or `"no"` (anything else throws `ValueError`). |
| `info` | Any string (consumed and ignored). |
| `prompt` | The text typed; `""` stands for Cancel. |
| `openFile`, `openFolder`, `saveFile` | The chosen path; `""` stands for Cancel. |
| `saveFileWithTypes` | The path as typed; `""` stands for Cancel. It is completed by the panel's rule: a path without one of the allowed extensions gets the first type's preferred one (`"/tmp/drawing"` with `["png"]` returns `"/tmp/drawing.png"`; `"/tmp/Shot.PNG"` stays; `"/tmp/notes.txt"` becomes `"/tmp/notes.txt.png"`). |
| `openURL`, `revealInFinder` | `"yes"` or `"no"`: what the call returns. Nothing is opened. |

In a `--self-test` run with no answer queued, each of them throws a
`RuntimeError` naming the function instead of showing a real dialog or
panel or opening another app: a self-test never puts modal UI on the
screen of the person running it.

The clipboard functions always act for real; use `saveClipboard` /
`restoreClipboard` around a test that touches the clipboard. In a quiet
self-test (`--self-test` without `LOUP_APPKIT_VISIBLE=1`, see
`appkit.app.isQuietSelfTest`) `beep` is silent and `playSound` plays at
volume 0, so the sound bookkeeping (`soundCopiesPlaying`) still runs.

```loup
if (isSelfTest()) {
    after(0.5, func(): void {
        setTestAnswers(["1", "yes", "/tmp/in.txt"]);
        println(alert("Save?", "", ["Save", "Don't Save"]));   # 1
        println(confirm("Delete?", ""));                      # true
        println(openFile(["txt"]));                           # /tmp/in.txt
        for (line in testLog()) { println(line); }
        quit();
    });
}
```

The probe `probes/dialogs_probe` does this for every function (including
an alert's `"-1"` answer and `saveFileWithTypes`' extension rule) and also
round-trips the real clipboard (and checks that a second restore throws),
then plays "Tink" twice in a row to show overlapping sounds, and writes and
reads text files (a UTF-8 round trip, an empty file, a missing file, a
folder, a missing folder, bytes that are not UTF-8).

## Known limitations

- The app's icon is the generic one in alerts (a folder) unless the program
  runs from an `.app` bundle that has an icon. The toolchain does not make
  bundles.
- `Window.snapshot` (cacheDisplayInRect) cannot capture an alert's text,
  which sits in vibrancy layers. Use `screencapture -l <windowNumber>` to
  picture a real dialog.
- The dialogs are app-modal (`runModal`), not window-attached sheets.
- `openFile` returns one file; there is no multiple selection.
- `openFile` and `saveFileWithTypes` filter through `UTType`
  (`setAllowedContentTypes:`) when the class is available and fall back to
  the deprecated `setAllowedFileTypes:`.
- `saveFileWithTypes`' canned answers follow the panel's documented rule
  for names (an allowed extension, compared by type, else the first type's
  preferred one is added); a real panel cannot be checked off screen, as it
  computes the chosen URL only when it runs.
- `prompt` cannot tell Cancel from an empty answer (both are `""`).
- A `ClipboardContents` that is never restored is never released (one
  retained NSArray each); always pair `saveClipboard` with
  `restoreClipboard`.
- `saveClipboard` copies the data of every type the items offer. Promised
  (lazily provided) data is fetched when saving, and a provider that never
  answers would stall it.
- `readTextFile` reads UTF-8 only (no encoding detection) and converts the
  text through a byte buffer: fine for documents, slow for files of many
  megabytes.
- No user notifications (`UNUserNotificationCenter` needs a bundled, signed
  app).
