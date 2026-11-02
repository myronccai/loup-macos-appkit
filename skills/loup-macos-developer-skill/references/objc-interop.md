# Objective-C interop cookbook (host.native, macOS)

Loup reaches AppKit and Foundation through the Objective-C runtime's C API in
`libobjc`. Everything here is `@mode(host.native)` in a `.lphc` file, built
with `loup build` and run as a binary.

## The runtime calls

```loup
extern native "objc" func objc_getClass(name: string): int;        # Class, 0 if not loaded
extern native "objc" func sel_registerName(name: string): int;     # SEL
extern native "objc" func objc_autoreleasePoolPush(): int;
extern native "objc" func objc_autoreleasePoolPop(pool: int): void;
```

Pointers (`id`, `Class`, `SEL`) are `int` words. 0 is `nil`.

## One declaration per message shape

`objc_msgSend` takes the receiver, the selector, then the method's arguments,
and returns the method's result. Declare each shape you use and bind it with
`@symbol("objc_msgSend")`:

```loup
@symbol("objc_msgSend") extern native "objc" func msg(recv: int, sel: int): int;
@symbol("objc_msgSend") extern native "objc" func msgI(recv: int, sel: int, a: int): int;
@symbol("objc_msgSend") extern native "objc" func msgII(recv: int, sel: int, a: int, b: int): int;
@symbol("objc_msgSend") extern native "objc" func msgS(recv: int, sel: int, s: string): int;
@symbol("objc_msgSend") extern native "objc" func msgD(recv: int, sel: int, d: float): int;
@symbol("objc_msgSend") extern native "objc" func msgRetD(recv: int, sel: int): float;
@symbol("objc_msgSend") extern native "objc" func msgV(recv: int, sel: int): void;
```

(Each annotation may also stand on its own line above the declaration.)

- `BOOL`/`NSInteger`/`NSUInteger`/pointers are `int`; `CGFloat` is `float`
  (a C `double` on 64-bit macOS); a C `int` is `int32`.
- A method that returns a struct (`frame`, `bounds`) cannot be called yet:
  struct returns are not lowered, and a declaration with a `@repr(C)` struct
  result builds anyway and crashes at the call. Read struct-valued
  properties through key-value coding (an `NSValue`, as
  `appkit.objc.rect_of` does) or an `NSInvocation`.
- Struct arguments: on **arm64** a struct of up to four doubles is passed as
  that many `float` arguments, so `setFrameOrigin:` (NSPoint) takes
  `(recv, sel, x: float, y: float)` and `initWithContentRect:…` (NSRect) takes
  `(recv, sel, x, y, w, h: float, …)`. On **x86-64** only two-double structs
  (NSPoint, NSSize) follow that rule; NSRect goes in memory there, so prefer
  APIs that take a point and a size (`setFrameOrigin:` + `setFrameSize:`,
  `setContentSize:`) when a binary must run on both.

## Helpers worth writing once

```loup
func cls(name: string): int { return objc_getClass(name); }
func sel(name: string): int { return sel_registerName(name); }
func nsstr(text: string): int {
    return msgS(cls("NSString"), sel("stringWithUTF8String:"), text);
}
```

Cache selectors in module-level `var`s if a hot path sends the same message
repeatedly.

## Linking

Classes are looked up by name, so no call forces their framework onto the
link. List them in the manifest:

```toml
[delivery.native]
framework = ["AppKit"]     # AppKit loads Foundation and CoreFoundation itself
```

`objc_getClass("NSWindow") == 0` at run time means AppKit was not linked.

## Memory

- Objects from `alloc`/`new`/`copy`/`mutableCopy` are owned by the caller
  (+1); release them with `release` when done. Convenience constructors
  (`stringWithUTF8String:`, `labelWithString:`) return autoreleased objects.
- Wrap work outside the run loop in a pool:
  `let pool = objc_autoreleasePoolPush(); … objc_autoreleasePoolPop(pool);`.
  Inside `[NSApp run]` AppKit drains a pool per event.
- Loup's ARC does not see Objective-C objects: an `int` holding an `id` is a
  plain word. Keep long-lived objects (the window, controls) in module-level
  `var`s or class fields so they are not lost.

## Threads

AppKit is main-thread only. Create and touch every window and view from
`main()` (or from code it calls), never from a spawned thread.

## Debugging

- Message to nil returns 0: check each `objc_getClass` and each `alloc`
  result while developing.
- An unknown selector raises an Objective-C exception and aborts the process
  with `unrecognized selector sent to instance`; the message names the
  selector.
- `loup-build --verbose` shows the clang line and the `native libraries:`
  line.
