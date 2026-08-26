# Inky editor

A reference Electron front end for the engine, in TypeScript. It exists to be
read and copied from: the smallest complete example of an application that is
not written in Odin driving the engine and showing it inside its own UI.

```
npm install
npm start
```

The engine has to be built first. From the repository root:

```
.\run.ps1 -Engine          # Windows
make linux-engine          # Linux
```

## How it works

The engine is started in **offscreen mode**, so it is never given a window. It
renders into its own framebuffer, the page copies each finished frame out with
`engine_read_pixels`, and paints it onto an ordinary `<canvas>`.

All of that happens in the **renderer process**, on the page's own thread:

```
requestAnimationFrame
  engine.tick(dt, input)      renders into the engine's framebuffer
  engine.readPixels(buf)      copies it out as RGBA bytes
  putImageData(buf)           paints it
```

Measured at 1082x749: tick 0.0ms, readPixels 0.9ms, putImageData 0.2ms. About
1.1ms of work against a 5.6ms frame at 180Hz, so the rest is `rAF` waiting for
vsync and there is a lot of headroom.

## Why the engine runs in the renderer process

Because a frame is about three megabytes and Electron's IPC copies and
serialises everything that crosses it.

The obvious arrangement is to run the engine in the main process and send each
frame to the page. That was tried here and it caps out around 70fps: nine of
every fourteen milliseconds go on moving the pixels between processes. It is
not fixable by tuning, because the pixels should not be crossing a process
boundary at all. Loading the engine where the canvas already is removes the
trip instead of optimising it, and the same scene goes from 70fps to 180.

The cost is `nodeIntegration: true` and `contextIsolation: false`, so the page
can load a native module and share memory with it. For a local editor driving a
native engine that is the point rather than a compromise, and this window loads
only its own files. Leaving `contextIsolation` on would put the copy back,
since the buffer would be cloned across the isolated world boundary every frame.

## Why offscreen and not a native window

The engine will happily render into a window handle you give it — that is what
the game front end does. Doing it here means handing it a native child window
placed over the page, and it costs:

- Win32 and Xlib called through an FFI, with no compiler checking the calls.
- A fight with Chromium over which of you owns that rectangle of screen. It
  presents through DirectComposition, which DWM composites above every child
  window regardless of z order, so the viewport is invisible until GPU
  compositing is disabled for the whole application.
- A viewport nothing in the interface can draw on top of. No menu, dropdown or
  tooltip can overlap it, because it is a window and not an element.
- A viewport that swallows every mouse event before the page sees it.

A readback per frame costs 0.9ms and buys all four away. **Mouse look works
here** precisely because the viewport is an element and can take pointer lock.

## Layout

```
src/main.ts       opens a window and gets out of the way
src/renderer.ts   owns the engine, the frame loop, input, painting
src/engine.ts     the engine's five functions, bound with koffi
index.html        the panel layout
```

## Things worth knowing before you change it

**Thread affinity.** The engine's graphics context is made current on whichever
thread calls `engine_init`, and every later engine call has to come from that
same thread. Here that is the page's main thread, which is also where the
painting happens. Moving any of it to a worker breaks it.

**Frames arrive upside down.** OpenGL numbers image rows from the bottom, a
canvas from the top. The canvas is flipped once in CSS with
`transform: scaleY(-1)`, which measures at no cost, rather than reversing
megabytes of rows per frame.

**Nothing is copied.** The bytes go into a `Buffer` the engine writes directly,
and reach `ImageData` as a **view** over it. Handing that `Buffer` to the
`Uint8ClampedArray` constructor instead of `(buffer, byteOffset, byteLength)`
copies three megabytes a frame for nothing.

**Sizes are in physical pixels.** The canvas backing store is scaled by
`devicePixelRatio` while CSS stretches it over the panel. Leaving that out
looks correct until the display scale is not 100%.

**No structs cross the boundary.** Every engine argument is an integer, a float
or a pointer, so there is no memory layout to reproduce. The pointer arguments
are declared `uint64` and passed as `bigint`, which is the same call on a 64
bit target and avoids inventing a pointer type TypeScript does not have.

The status bar shows the live frame rate and the terminal gets a per-second
breakdown of where the time went, so a regression in any of the above is
visible immediately.

## Not done yet

`engine_init` returns 1 or 0 and no reason. When it returns 0, the likely
causes are a missing `build/engine.dll` or a driver without OpenGL 3.3.
