# appkit.canvas — custom drawing and input

```loup
from appkit.canvas import (Canvas, Graphics);
# line styles: LINE_CAP_BUTT, LINE_CAP_ROUND, LINE_CAP_SQUARE,
#              LINE_JOIN_MITER, LINE_JOIN_ROUND, LINE_JOIN_BEVEL
```

A `Canvas` is a view you paint yourself and that receives mouse and keyboard
events. It is an instance of `LoupCanvas`, an `NSView` subclass the module
creates once at run time (`objc_allocateClassPair`); its `drawRect:`,
`isFlipped`, `acceptsFirstResponder`, `acceptsFirstMouse:`, `mouseDown:`,
`mouseDragged:`, `mouseUp:` and `keyDown:` methods are Loup functions that call
the handlers you register.

**Coordinates are flipped: (0, 0) is the TOP-LEFT corner and y grows
downwards**, in drawing and in every mouse handler. Only the canvas's own
frame (`setFrame`, `Window.add`) is in the superview's usual bottom-left
coordinates, like every other view.

The module is `@mode(host.native)`; the app's manifest needs
`[delivery.native] framework = ["AppKit"]`.

## Example

```loup
@mode(host.native)

from appkit.app import (appInit, run, Window);
from appkit.canvas import (Canvas, Graphics);

var g_points: list[float] = [];

pub func main(): void {
    appInit("Sketch");
    let win = Window("Sketch", 400.0, 300.0);
    let canvas = Canvas(400.0, 300.0);
    win.add(canvas, 0.0, 0.0, 400.0, 300.0);

    canvas.onDraw(func(g: Graphics): void {
        g.clear(1.0, 1.0, 1.0);
        g.setFillColor(0.2, 0.4, 0.9, 1.0);
        g.fillOval(20.0, 20.0, 60.0, 60.0);
        g.text(100.0, 30.0, "drag to draw", 16.0, 0.0, 0.0, 0.0);
        if (g_points.len() >= 4) {
            g.setStrokeColor(0.8, 0.0, 0.4, 1.0);
            g.setLineWidth(3.0);
            g.polyline(g_points);
        }
    });
    canvas.onMouseDown(func(x: float, y: float): void {
        global g_points;
        g_points = [x, y];
        canvas.redraw();
    });
    canvas.onMouseDrag(func(x: float, y: float): void {
        global g_points;
        g_points.push(x);
        g_points.push(y);
        canvas.redraw();
    });
    canvas.onKey(func(chars: string, keyCode: int): void {
        global g_points;
        if (keyCode == 53) {          # Escape clears
            g_points = [];
            canvas.redraw();
        }
    });
    canvas.focus();
    run(win);
}
```

The working probe is `probes/canvas_probe/` (`./canvas-probe --self-test
out.png` draws, sends synthetic mouse and key events, prints what it saw and
writes a snapshot; a second canvas draws caps, joins and dashes, reads them
back from its pixels and from its exported PNG, and carries per-region tool
tips).

## Canvas

`pub class Canvas : View` — everything `appkit.app.View` has (`handle`,
`setFrame`, `setSize`, `frame`, `addSubview`, `setHidden`, `isHidden`,
`setToolTip`, `setWidth`, `setHeight`), plus:

| Member | Description |
|---|---|
| `constructor(width: float, height: float)` | A new canvas of that size (place it with `Window.add`, `setFrame` or a layout). |
| `onDraw(handler: fn(Graphics): void): void` | Paint the canvas. AppKit calls it whenever the canvas needs drawing (first display, resize, `redraw()`, snapshot). Replaces an earlier handler and schedules a draw. |
| `onMouseDown(handler: fn(float, float): void): void` | Left button pressed on the canvas, `(x, y)` in canvas coordinates. The click also gives the canvas keyboard focus. |
| `onMouseDrag(handler: fn(float, float): void): void` | Mouse moved with the left button held. Keeps reporting outside the canvas, so x / y can be negative or beyond the size. |
| `onMouseUp(handler: fn(float, float): void): void` | Left button released. |
| `onKey(handler: fn(string, int): void): void` | A key pressed while the canvas has focus: the characters it produces (`""` for most function keys; arrows give private-use characters) and the hardware key code (36 Return, 48 Tab, 49 Space, 51 Delete, 53 Escape, 123 ←, 124 →, 125 ↓, 126 ↑). Without a handler key presses go on to the next responder. |
| `redraw(): void` | Ask AppKit to repaint (`setNeedsDisplay:`); `onDraw` runs on the next display pass. Call it from event handlers after changing your model. |
| `redrawRect(x, y, w, h: float): void` | Ask AppKit to repaint only that rectangle (canvas coordinates, `setNeedsDisplayInRect:`); `onDraw` then sees it as `Graphics.dirtyX/Y/W/H` and drawing outside it is clipped. arm64 (NSRect by value). |
| `flush(): void` | Repaint now whatever `redraw` / `redrawRect` marked (`displayIfNeeded`); does nothing when nothing is pending. |
| `display(): void` | Repaint the whole canvas now: `onDraw` runs before this returns (when the canvas is on screen). |
| `focus(): bool` | Make the canvas the window's first responder so `onKey` sees key presses; false when it is not in a window or the window refused. |
| `hasFocus(): bool` | Whether the canvas is the first responder. |
| `drawCount(): int` | How many times AppKit has called `drawRect:` on this canvas. |
| `toWindow(x: float, y: float): Rect` | Canvas point → window coordinates (bottom-left origin of the window), in `Rect.x` / `Rect.y`. |
| `fromWindow(x: float, y: float): Rect` | Window point → canvas coordinates. |
| `sendMouse(kind: string, x: float, y: float): void` | Send a synthetic left-mouse NSEvent at canvas point (x, y) through the real `mouseDown:` / `mouseDragged:` / `mouseUp:`; `kind` is `"down"`, `"drag"` or `"up"` (anything else throws `ValueError`). For self-tests and demos. |
| `sendKey(chars: string, keyCode: int): void` | Send a synthetic key-down NSEvent through the window (`sendEvent:`), so it reaches the canvas only when it has focus. For self-tests and demos. |
| `addToolTip(x, y, w, h: float, text: string): int` | Give the rectangle (canvas coordinates, top-left origin) its own tool tip (`addToolTipRect:owner:userData:`; the library retains the `NSString` owner AppKit asks for the text). Returns the tip's tag. `ValueError` for an empty rectangle. arm64 (NSRect argument). |
| `removeToolTip(tag: int): void` | Remove that tip (`removeToolTip:`); `ValueError` when this canvas has no such tag. |
| `removeAllToolTips(): void` | Remove every tip of the canvas (`removeAllToolTips`, which also drops a whole-view `setToolTip`). |
| `toolTipCount(): int` | How many `addToolTip` rectangles the canvas has. |
| `toolTipAt(x, y: float): string` | The text of the rectangle under the point (`""` for none; the one added last where they overlap). AppKit has no getter for tool-tip rectangles: this reads the library's record of them. |

### Reading back what the canvas drew

A `Canvas` is an `appkit.app.View`, so the View rendering helpers work on it
(`appkit.app`, see its module header):

| Member | Description |
|---|---|
| `render(): Bitmap` | Draw the canvas now into an in-memory bitmap at the screen's scale, tagged sRGB before drawing: its pixels are exactly the sRGB values drawn, whatever the display's profile. Works off screen (quiet self-test). |
| `colorAt(x, y: float): Pixel` | The pixel at a canvas point (top-left origin, y down) from a fresh render; `pixelHex(p)` gives `#RRGGBB`. To read many pixels, `render()` once and ask the `Bitmap`. |
| `snapshot(path: string): void` | Write a PNG of the canvas with the sRGB profile (`RuntimeError` when it cannot be written). |
| `loadBitmap(path, flipped): Bitmap` (appkit.app) | Read such a PNG back (`flipped` true: `colorAt` in canvas coordinates); `Bitmap.isSrgb()` checks its color space. |

A render holds its bitmap until `release()`:
`let b = canvas.render(); … b.release();`.

## Graphics

`pub class Graphics` — the drawing surface passed to `onDraw`. All
coordinates are canvas points (top-left origin, y down); colors are sRGB
components in 0…1. Use it only inside the draw handler: AppKit's drawing
context exists only during `drawRect:`. Drawing state (fill and stroke
colors, line width, current path) resets to black / 1 pt / no path at the
start of every draw. So does the stroke style (cap, join, dash) — until a
draw sets a cap or join, strokes use `NSBezierPath`'s class-wide default
(`setDefaultLineCapStyle:`; butt cap and miter join unless the app changed
it), and `lineCap()` / `lineJoin()` report that default.

| Member | Description |
|---|---|
| `canvas: int` | The canvas's `NSView` pointer (its `handle`). |
| `width: float`, `height: float` | The canvas's size in points (its bounds). |
| `dirtyX`, `dirtyY`, `dirtyW`, `dirtyH: float` | The area AppKit is repainting (what `drawRect:` receives), in canvas coordinates. The whole canvas for a full draw; a large canvas may skip what lies outside it (it is clipped anyway). |
| `constructor(canvas: int, width: float, height: float, dirtyX: float, dirtyY: float, dirtyW: float, dirtyH: float)` | Made by the canvas for each draw; apps do not need it. |
| `setFillColor(r, g, b, a: float): void` | Color for `fillRect`, `fillRoundedRect`, `fillOval`, `fillPolygon`, `fill`. |
| `setStrokeColor(r, g, b, a: float): void` | Color for `strokeRect`, `strokeRoundedRect`, `strokeOval`, `line`, `polyline`, `stroke`. |
| `setLineWidth(w: float): void` | Width of later strokes (default 1). |
| `setLineCap(style: int): void` / `lineCap(): int` | Ends of later strokes: `LINE_CAP_BUTT` (0, flat at the end point), `LINE_CAP_ROUND` (1) or `LINE_CAP_SQUARE` (2) (both reach half the line width past it); `ValueError` for anything else. A pen tool wants `LINE_CAP_ROUND`. |
| `setLineJoin(style: int): void` / `lineJoin(): int` | Corners of later strokes (`polyline`, `strokeRect`, paths): `LINE_JOIN_MITER` (0), `LINE_JOIN_ROUND` (1) or `LINE_JOIN_BEVEL` (2); `ValueError` for anything else. |
| `setLineDash(pattern: list[float], phase: float): void` / `lineDash(): list[float]` / `lineDashPhase(): float` | Dash later strokes: alternating painted / skipped lengths in points (`[6.0, 3.0]`), starting `phase` points into the pattern; `[]` is solid. With `LINE_CAP_ROUND` a 0 length paints a dot (`[0.0, 8.0]`: dotted). `ValueError` for a negative length or a pattern that adds up to 0. |
| `clear(r, g, b: float): void` | Fill the whole canvas with an opaque color (`NSRectFill`: copies, no blending). |
| `applyFillColor(color: ColorRef): void` / `applyStrokeColor(color: ColorRef): void` | The fill / stroke color as an `appkit.controls` `ColorRef`: `srgbColor(r, g, b, a)` or a dynamic system color such as `systemColor(COLOR_SYSTEM_BLUE)`, which is resolved for the canvas's appearance (light or dark) at each draw. Make the `ColorRef`s once (e.g. at start-up), not in every draw. |
| `clearWith(color: ColorRef): void` | `clear` with a `ColorRef` (e.g. `systemColor(COLOR_WINDOW_BACKGROUND)` for a background that follows Dark Mode). |
| `fillRect(x, y, w, h: float): void` / `strokeRect(...)` | Rectangle with top-left (x, y). Fills blend with alpha (`NSBezierPath`). |
| `fillRoundedRect(x, y, w, h, radius: float): void` / `strokeRoundedRect(...)` | Rounded rectangle. |
| `fillOval(x, y, w, h: float): void` / `strokeOval(...)` | Ellipse inscribed in the rectangle. |
| `line(x1, y1, x2, y2: float): void` | Straight line, stroked. |
| `polyline(points: list[float]): void` | Connected segments through `[x0, y0, x1, y1, …]`, stroked (an odd trailing value is ignored). |
| `fillPolygon(points: list[float]): void` | Closed polygon through the points, filled. |
| `beginPath(): void` | Start a new, empty current path. |
| `moveTo(x, y: float): void` | Start a subpath (starts a path if there is none). |
| `lineTo(x, y: float): void` | Segment to (x, y); acts as `moveTo` without a current point. |
| `closePath(): void` | Close the current subpath. |
| `fill(): void` / `stroke(): void` | Fill / stroke the current path (the path is kept, so both can be used). |
| `text(x, y: float, s: string, size: float, r, g, b: float): void` | Draw `s` in the system font of `size` points, opaque color (r, g, b); (x, y) is the top-left of the line box (`NSString drawAtPoint:withAttributes:` with the `NSFont` and `NSColor` attributes). |
| `textWidth(s: string, size: float): float` | Width of `s` as `text` draws it at `size`. |

## Known limitations

- **Left button only.** Right / other buttons, mouse-moved without a button,
  scroll wheel, modifier flags, key-up and repeat flags are not delivered.
- **System font only** in `text`; no font family / weight choice, no
  multi-line layout (use an `appkit.text` / label view for that).
- No images, gradients, shadows, clipping or transforms in `Graphics`; no
  miter limit setting.
- `sendMouse` dispatches to the canvas's methods directly (not through
  `NSWindow sendEvent:`), so it never starts AppKit's own drag tracking.
- `toWindow` / `fromWindow` call `convertPoint:…View:` through
  `NSInvocation` (Loup cannot receive a struct result); they are exact for
  any nesting of flipped, scrolled or scaled views. arm64 / x86-64 alike.
