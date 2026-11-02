# appkit.table — tables and lists

`appkit.table` wraps `NSTableView` for data-driven tables and simple lists.
The rows come from Loup closures, so the table always shows your own data:
change the data, then call `reload()`.

```loup
from appkit.table import (TableView, ListView);
```

The file is `@mode(host.native)` (`table.lphc`). It builds on `appkit.objc`
and `appkit.app`, and it builds and runs on both the self-hosted `loup build`
and Stage0's `loup-bootstrap build --target native`.

## How it works

- Each `TableView` is an `NSTableView` inside an `NSScrollView`. `handle` is
  the table and `scroll` is the scroll view. **Place and size `scroll`**,
  never the table itself.
- The table is *cell-based*: there is no `tableView:viewForTableColumn:row:`
  delegate method, so AppKit asks for each cell's object value (an
  `NSString`) and draws it with the column's text cell.
- Every table shares one data source, delegate and double-click target: an
  instance of the run-time class `LoupTableSource`. Its methods are Loup
  functions installed with `class_addMethod`:
  - `numberOfRowsInTableView:`
  - `tableView:objectValueForTableColumn:row:`
  - `tableView:setObjectValue:forTableColumn:row:`
  - `tableViewSelectionDidChange:`
  - `tableView:didClickTableColumn:`
  - `loupTableDoubleClick:`

  Each method finds the closures registered for the `NSTableView` pointer
  that called it. The proxies stay immutable: they hold only `handle` and
  `scroll`.
- If a closure throws, the error goes to stderr and never unwinds through
  AppKit. When a data-source closure throws, the table gets 0 rows or `""`
  for that cell.

## Example

```loup
@mode(host.native)

from appkit.app import (appInit, run, Window);
from appkit.table import (TableView, ListView);

var g_names: list[string] = ["Ada", "Grace", "Linus"];
var g_langs: list[string] = ["Analytical Engine", "COBOL", "C"];

pub func main(): void {
    appInit("People");
    let win = Window("People", 520.0, 300.0);

    let table = TableView();
    table.addColumn("name", "Name", 140.0);
    table.addColumn("lang", "Language", 200.0);
    table.setRowCount(func(): int { return g_names.len(); });
    table.setCell(func(column: string, row: int): string {
        if (column == "name") { return g_names[row]; }
        return g_langs[row];
    });
    table.setAlternatingRows(true);
    table.onSelect(func(row: int): void { println("selected " + row.to_string()); });
    table.onDoubleClick(func(row: int): void { println("open " + g_names[row]); });
    table.setEditable(true);
    table.onEdit(func(column: string, row: int, text: string): void {
        global g_names;
        if (column == "name") { g_names[row] = text; }
    });
    win.add(table.scroll, 20.0, 20.0, 340.0, 260.0);

    let list = ListView();
    list.setItems(["Inbox", "Sent", "Trash"]);
    list.onSelect(func(row: int): void { println(list.selectedItem()); });
    win.add(list.scroll, 380.0, 20.0, 120.0, 260.0);

    run(win);
}
```

## `TableView` (extends `appkit.app.View`)

| Member | Description |
|---|---|
| `TableView()` | Creates a new, empty table (no columns, no rows) inside a scroll view. |
| `scroll: View` | The `NSScrollView`. This is the view to place and lay out, e.g. `win.add(t.scroll, x, y, w, h)` or add it to a stack. |
| `handle: int` | The `NSTableView`, inherited from `View`. |
| `addColumn(identifier, title, width)` | Adds a column. `identifier` is what the `setCell` closure receives as `column`. `title` is the header text and `width` the initial width in points. |
| `columnCount(): int` | The number of columns. |
| `column(identifier): int` | The `NSTableColumn` pointer for raw messaging, or 0 if there is no such column. |
| `setColumnTitle(identifier, title)` | Changes a column's header text. |
| `columnWidth(identifier): float` | A column's current width (0 if there is no such column). |
| `setRowCount(count: fn(): int)` | Data source: the number of rows. It is called on every (re)load. |
| `setCell(cell: fn(string, int): string)` | Data source: `cell(column, row)` returns the text at that cell. `row` is 0-based. |
| `reload()` | Asks for the row count and the visible cells again. Call it after your data changes. |
| `rowCount(): int` | The number of rows the table shows, as of the last load. |
| `cellText(column, row): string` | The text the table shows at a cell, read back through AppKit's prepared cell. Returns `""` when the column or row does not exist. |
| `selectedRow(): int` | The selected row, or -1. With a multiple selection, this is the row most recently added to it. |
| `selectRow(row)` | Selects only `row` and scrolls it into view. A negative `row` clears the selection. Runs `onSelect`. |
| `selectedRows(): list[int]` | All selected rows, in ascending order. |
| `selectRows(rows: list[int])` | Selects exactly `rows`. More than one row needs `setMultipleSelection(true)`. Runs `onSelect`. |
| `setMultipleSelection(allow)` | Allows ⌘-click and ⇧-click to select several rows. |
| `deselectAll()` | Clears the selection. Runs `onSelect` with -1. |
| `scrollToRow(row)` | Scrolls until `row` is visible. |
| `onSelect(handler: fn(int): void)` | Runs whenever the selection changes, whether by the user or in code. The argument is `selectedRow()` at that moment. |
| `onClick(handler: fn(int): void)` | Runs after every single click in the table (the table's action, sent when the mouse button goes up). The argument is the clicked row, -1 for a click below the last row. Unlike `onSelect` it also runs for a click on the row that is already selected. A double-click runs it for the first click, then `onDoubleClick`. |
| `onDoubleClick(handler: fn(int): void)` | Runs when a row is double-clicked. The argument is the clicked row; when the action is sent in code, it is the selected row instead. |
| `setEditable(editable)` | Makes every column, now and later, editable or not. The default is not editable. |
| `setColumnEditable(identifier, editable)` | Makes one column editable or not. |
| `onEdit(handler: fn(string, int, string): void)` | Runs as `handler(column, row, newText)` when the user finishes editing a cell. Store the new text in your data: afterwards the table shows whatever `setCell` returns. |
| `editCell(column, row)` | Starts editing a cell the way a double-click would. It selects the row, and the column must be editable. |
| `onHeaderClick(handler: fn(string): void)` | Runs with the column identifier when a header is clicked. This is the sorting hook: sort your data, call `setSortIndicator`, then `reload()`. |
| `setSortIndicator(identifier, ascending)` | Shows the ▲ or ▼ indicator on one column and highlights it, clearing every other column's indicator. `""` clears all of them. |
| `sortIndicator(identifier): string` | Returns `"ascending"`, `"descending"` or `""`. |
| `setAlternatingRows(on)` / `alternatingRows(): bool` | Tints every other row. |
| `setHeaderVisible(visible)` / `headerVisible(): bool` | Shows or hides the column headers. |
| `setGridLines(show)` | Draws solid grid lines between rows and between columns. |
| `setRowHeight(h)` / `rowHeight(): float` | The row height in points. |
| `setColumnAlignment(identifier, alignment)` / `columnAlignment(identifier): string` | Aligns a column's cells and its header: `appkit.controls` `TEXT_LEFT`, `TEXT_CENTER`, `TEXT_RIGHT`, `TEXT_JUSTIFIED` or `TEXT_NATURAL` (the ABI difference of `NSTextAlignment` is handled there). Throws `ValueError` for an unknown column or name. |
| `setColumnFont(identifier, font: Font)` / `columnFont(identifier): Font` | Draws a column's cells in an `appkit.controls` `Font`, e.g. `monospacedDigitSystemFont(12.0, WEIGHT_REGULAR)` for figures. A larger font needs `setRowHeight`. Throws `ValueError` for an unknown column. |
| `setCellFont(font: Font)` | Every column's cells in `font` (a `ListView`'s one column too). |
| `columnTitle(identifier): string` | The header title the column draws (read-back for `setColumnTitle`). Throws `ValueError` for an unknown column. |
| `setColumnWidth(identifier, width)` | Sets a column's width, kept within its minimum and maximum. |
| `setColumnWidthRange(identifier, min, max)` / `columnMinWidth(identifier)` / `columnMaxWidth(identifier)` | Limits a column's width for user drags and autoresizing alike. `max <= 0` means no maximum (read back as 0). `ValueError` when `max < min`. |
| `setColumnResizing(identifier, mode)` / `columnResizing(identifier): int` | Who may resize the column: `COLUMN_FIXED`, `COLUMN_AUTORESIZES` (the table, by its autoresizing style), `COLUMN_USER_RESIZES` (the user only) or `COLUMN_RESIZABLE` (both; what `addColumn` gives). |
| `setColumnAutoresizing(style)` / `columnAutoresizing(): int` | How a width change is shared between the columns whose resizing includes `COLUMN_AUTORESIZES`: `AUTORESIZE_UNIFORM` (the default), `AUTORESIZE_NONE`, `AUTORESIZE_SEQUENTIAL`, `AUTORESIZE_REVERSE_SEQUENTIAL`, `AUTORESIZE_LAST` or `AUTORESIZE_FIRST`. |
| `sizeColumnsToFit()` | Resizes the columns (by the autoresizing style) so that together they fill the visible width. Call it once the table is in its window (after `Window.setContent` or `add`); it lays the window out first. |
| `sizeLastColumnToFit()` | The same, resizing only the last column whose resizing includes `COLUMN_AUTORESIZES`. |
| `addCheckBoxColumn(identifier, title, width)` | Adds a column of check boxes (`NSButtonCell` switches, centered, fixed width). The `setCell` closure gives each box's state as text: `"1"`, `"true"`, `"yes"`, `"on"` or `"x"` means checked. The column stays clickable whatever `setEditable` says; `setColumnEditable(identifier, false)` makes it read-only. |
| `isCheckBoxColumn(identifier): bool` | Whether a column is a check-box column. |
| `onToggle(handler: fn(string, int, bool): void)` | Runs as `handler(column, row, checked)` when a box is clicked. Store the new state; the table shows what `setCell` returns next. Without `onToggle`, a click runs `onEdit` with `"1"` / `"0"`. |
| `isChecked(column, row): bool` | Whether a box is checked, as the table shows it. `cellText` reads `"1"` / `"0"` for a check-box column. |
| `onSort(handler: fn(string, bool): void)` | Runs as `handler(column, ascending)` on a header click, with the direction toggled for you: the sorted column flips, another column starts ascending. The indicator is already shown when the handler runs: sort your data and `reload()`. Runs after `onHeaderClick`. |
| `setColumnSortable(identifier, sortable)` | Whether header clicks on a column sort (default true). `onHeaderClick` runs either way. |
| `sortColumn(): string` / `sortAscending(): bool` | The sort state, set by `onSort` clicks and by `setSortIndicator`. `""` / `true` when nothing is sorted. |
| `isEditing(): bool` | Whether a cell's field editor is open. |

Test helpers. Each one takes the path a user's action takes, so the same
handlers run. Unknown columns and rows throw `ValueError`.

| Member | Description |
|---|---|
| `clickRow(row)` | Clicks `row` once, taking the steps of NSTableView's own click handling: the table takes the keyboard focus (which ends a text field's editing, as a click does); `row` is proposed as the whole selection (with multiple selection too) and the delegate's `tableView:selectionIndexesForProposedSelection:` or `tableView:shouldSelectRow:`, when it has one, may change or refuse it; a changed selection runs `onSelect`; then the table's action runs `onClick(row)`, also when the row was already selected. The row is scrolled into view. A table in no window skips the focus step. |
| `clickHeader(identifier)` | Clicks a column header: the delegate's `tableView:didClickTableColumn:`, which AppKit sends on a click, so `onHeaderClick` and `onSort` run. |
| `doubleClickRow(row)` | Selects `row`, then sends the table's double action, so `onDoubleClick(row)` runs. It never starts editing, even on an editable column. |
| `clickCheckBox(column, row)` | Clicks a box (`performClickOnCellAtColumn:row:`), so `onToggle` runs. A read-only check-box column ignores it. `ValueError` for a text column. |
| `commitEdit(column, row, text)` | Edits a cell and commits `text`: `editCell`, then the field editor selects all, types `text` and gets Return, so AppKit hands the value to `tableView:setObjectValue:forTableColumn:row:` and `onEdit` runs. A table in no window cannot open a field editor; then the value goes to that data-source method directly. `ValueError` for a read-only column or a check-box column. |

Constants: `AUTORESIZE_NONE` (0), `AUTORESIZE_UNIFORM` (1),
`AUTORESIZE_SEQUENTIAL` (2), `AUTORESIZE_REVERSE_SEQUENTIAL` (3),
`AUTORESIZE_LAST` (4), `AUTORESIZE_FIRST` (5); `COLUMN_FIXED` (0),
`COLUMN_AUTORESIZES` (1), `COLUMN_USER_RESIZES` (2), `COLUMN_RESIZABLE` (3);
`LIST_COLUMN` (`"item"`).

`View` methods such as `setHidden` and `setToolTip` act on the table itself.
To position or size the table, use `scroll`.

## `ListView` (extends `TableView`)

A list is a one-column table with no header. Its rows are the strings you
pass to `setItems`. Every `TableView` method works on it, for example
`onSelect`, `onDoubleClick`, `selectRow`, `setAlternatingRows` and the test
helpers `clickRow`, `doubleClickRow` and (with `setEditable(true)` and `onEdit`)
`commitEdit`. The column identifier is `LIST_COLUMN` (`"item"`), for
`cellText`, `editCell`, `commitEdit` and `setColumnAlignment`.

| Member | Description |
|---|---|
| `ListView()` | Creates an empty list inside a scroll view. Place `list.scroll`. |
| `setItems(items: list[string])` | Replaces the rows and reloads. |
| `items(): list[string]` | The rows as last passed to `setItems`. |
| `selectedItem(): string` | The selected item's text, or `""` when nothing is selected. |

Do not call `setRowCount` or `setCell` on a `ListView`: they would replace
the closures that serve its items.

## Probe

`probes/table_probe` builds a window with a 3-column, 20-row table and a list.
Run `./table-probe --self-test [png]` to drive every API and print what it
observes: reads of cells through AppKit, programmatic selection,
`selectedRow` / `selectedRows`, a reload after the data changes, a
double-click, a header click that sorts the data, a real in-place edit
(`editCell` → field editor → commit → `onEdit`), headers, grid lines, row
height, column alignment and fonts, and the list. A second table checks
the check-box column (clicks, read-only boxes), column widths, ranges and
resizing modes, `sizeColumnsToFit` / `sizeLastColumnToFit`, header titles,
the `onSort` direction toggle and the test helpers (`clickHeader`,
`doubleClickRow`, `commitEdit`, also on a table with no window), and the
list's `LIST_COLUMN`. A last section clicks rows with `clickRow` (the
selection, `onSelect` only when it changed, `onClick` every time, the
focus, a multiple selection replaced by the clicked row, a table in no
window). `run_all.sh --probes`
checks the output against `selftest.out`. If you give a PNG path, it also
writes a snapshot of the window.

## Known limitations

- **Text cells and check boxes only.** The table is cell-based, so cells
  are strings shown with the default text cell, or check boxes
  (`addCheckBoxColumn`, an `NSButtonCell`). There are no per-cell views,
  images or pop-ups. Those would need `tableView:viewForTableColumn:row:`
  (view-based tables), which this module does not implement.
- **Uniform column resizing.** The table uses uniform column resizing by
  default, so AppKit can adjust the requested widths by a few points to fit
  the scroll view. For example, 150 can become 148. The requested widths do
  not fill the table by themselves: call `sizeColumnsToFit()` once the table
  is in its window. Keep a narrow column fixed with
  `setColumnResizing(id, COLUMN_FIXED)` (check-box columns start fixed).
- **Sorting is yours to do.** The module provides the hooks (`onSort` with
  the direction toggle, or the raw `onHeaderClick`) and the indicator, but
  no `NSSortDescriptor` support. Sort your own data and call `reload()`.
- **Double-clicking an editable cell edits it.** It does not run
  `onDoubleClick`. Keep a column non-editable if double-clicks on it should
  open something.
- **Edit values come back as text.** `onEdit` receives the value's
  `description`, which is the text for string cells.
- **Programmatic double-clicks report the selected row.** When the double
  action is sent in code, `clickedRow` is -1, so the handler gets the selected
  row instead. `doubleClickRow(row)` selects the row first, so the handler
  gets `row`.
- **`clickRow` is not a mouse event.** NSTableView ignores a synthetic
  mouse-down in an app that was never activated (a quiet self-test), so
  `clickRow` takes the click's steps itself. During the action AppKit's
  `clickedRow` is -1 (only a real click sets it); `onClick` gets the row.
  A raw action of your own that reads `clickedRow` sees -1. A click on an
  editable cell of the selected row does not start editing (use `editCell`
  / `commitEdit`).
- **A read-only check box still flips for a moment.** With a non-editable
  check-box column, the delegate refuses to track the cell, and a value that
  arrives anyway is not passed on: the row is reloaded from the data source.
- **Header visibility re-attaches the table.** `setHeaderVisible`
  re-attaches the table to the scroll view so AppKit rebuilds the header's
  space. Without that, a header that is shown again covers row 0. The
  re-attach may reset the scroll position, so afterwards the module scrolls
  the selected row, if there is one, back into view.
- **Main thread only.** Every call must be made on the main thread, which is
  AppKit's rule.
