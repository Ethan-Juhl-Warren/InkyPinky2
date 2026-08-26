/*
 * The page, which owns the engine and everything else.
 *
 * The engine runs here rather than in the main process, so a finished frame
 * goes straight from engine memory into the canvas without crossing a process
 * boundary. That is worth about nine milliseconds a frame at a normal viewport
 * size; see the note in main.ts.
 *
 * The engine is started in offscreen mode, so it is never given a window. It
 * renders into its own framebuffer and hands back pixels. The alternative is a
 * native window placed over the page, which means Win32 and Xlib through an
 * FFI, a fight with Chromium over which of you owns that rectangle of screen,
 * a viewport nothing in the interface can draw on top of, and a viewport that
 * swallows every mouse event before the page sees it. Mouse look works here
 * precisely because the viewport is an ordinary element.
 *
 * One rule: the engine's graphics context is made current on whichever thread
 * calls init, and every later engine call has to come from that same thread.
 * Here that is the page's main thread, which is also where the painting
 * happens, so there is nothing to be careful about as long as it stays here.
 */

import path from 'node:path';
import { load, Engine, Surface } from './engine';

const canvas = document.getElementById('viewport') as HTMLCanvasElement;
const context = canvas.getContext('2d')!;
const statusLabel = document.getElementById('status')!;

// The engine reads ./engine.cfg relative to the working directory.
const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');
process.chdir(REPO_ROOT);

let engine: Engine | null = null;
let frame = Buffer.alloc(0);

// ------------------------------------------------------------------ size ---

/*
 * The engine renders at physical pixels, so the canvas backing store is sized
 * in physical pixels while CSS stretches it across the panel. Leaving
 * devicePixelRatio out is the classic bug here: it looks correct until the
 * display scale is not 100%, and then the viewport is soft and the wrong shape.
 */
function syncSize(): void {
  const bounds = canvas.getBoundingClientRect();
  const scale = window.devicePixelRatio || 1;
  const width = Math.max(1, Math.round(bounds.width * scale));
  const height = Math.max(1, Math.round(bounds.height * scale));

  if (canvas.width === width && canvas.height === height) return;

  canvas.width = width;
  canvas.height = height;
  frame = Buffer.alloc(width * height * 4);

  if (!engine) {
    start(width, height);
  } else {
    engine.resize(width, height);
  }
}

function start(width: number, height: number): void {
  const loaded = load(REPO_ROOT);

  // No window, so no display and no handle. Those arguments are there for
  // clients that do have one.
  if (!loaded.init(Surface.OFFSCREEN, 0n, 0n, width, height)) {
    statusLabel.textContent = 'engine_init failed';
    return;
  }
  engine = loaded;
  requestAnimationFrame(pump);
}

new ResizeObserver(syncSize).observe(canvas);
window.addEventListener('resize', syncSize);
requestAnimationFrame(syncSize);

// ----------------------------------------------------------------- frames ---

let previous = performance.now();
let framesThisSecond = 0;
let fpsSince = previous;
let tickMs = 0;
let readMs = 0;
let paintMs = 0;

/*
 * Frames come out of the engine upside down, because OpenGL numbers image rows
 * from the bottom and a canvas numbers them from the top. The canvas is
 * flipped once in CSS with transform: scaleY(-1), which costs nothing, rather
 * than reversing several megabytes of rows every frame.
 */
function pump(): void {
  if (!engine) return;

  const now = performance.now();
  const dt = Math.min((now - previous) / 1000, 0.1); // clamped, so a stall does not teleport the camera
  previous = now;

  const a = performance.now();
  engine.tick(dt, mouseDx, mouseDy, actions);
  mouseDx = 0;
  mouseDy = 0;

  const b = performance.now();
  const written = engine.readPixels(frame, frame.length);

  const c = performance.now();
  if (written > 0 && frame.length === canvas.width * canvas.height * 4) {
    // A view over the engine's bytes, not a copy of them.
    const pixels = new Uint8ClampedArray(
      frame.buffer as ArrayBuffer,
      frame.byteOffset,
      frame.byteLength
    );
    context.putImageData(new ImageData(pixels, canvas.width, canvas.height), 0, 0);
  }
  const d = performance.now();

  tickMs += b - a;
  readMs += c - b;
  paintMs += d - c;
  framesThisSecond += 1;

  if (now - fpsSince >= 1000) {
    const fps = Math.round((framesThisSecond * 1000) / (now - fpsSince));
    statusLabel.textContent = `viewport ${canvas.width} x ${canvas.height}  ${fps} fps`;
    console.log(
      `${fps} fps  frame ${((now - fpsSince) / framesThisSecond).toFixed(1)}ms` +
        `  tick ${(tickMs / framesThisSecond).toFixed(1)}ms` +
        `  read ${(readMs / framesThisSecond).toFixed(1)}ms` +
        `  paint ${(paintMs / framesThisSecond).toFixed(1)}ms`
    );
    tickMs = readMs = paintMs = 0;
    framesThisSecond = 0;
    fpsSince = now;
  }

  requestAnimationFrame(pump);
}

window.addEventListener('beforeunload', () => {
  engine?.destroy();
  engine = null;
});

// ------------------------------------------------------------------ input ---

/*
 * Key bindings live here, not in the engine.
 *
 * The engine is told which of six movement intents are active and nothing
 * more. It has no notion of a keyboard, which is why these same bits could
 * come from a gamepad, a script or a recorded session without it noticing.
 */
const BINDINGS: Record<string, number> = {
  KeyW: 1 << 0, // forward
  KeyS: 1 << 1, // back
  KeyA: 1 << 2, // left
  KeyD: 1 << 3, // right
  Space: 1 << 4, // up
  ShiftLeft: 1 << 5, // down
};

let actions = 0;
let mouseDx = 0;
let mouseDy = 0;

window.addEventListener('keydown', (event) => {
  const bit = BINDINGS[event.code];
  if (bit !== undefined) actions |= bit;
});

window.addEventListener('keyup', (event) => {
  const bit = BINDINGS[event.code];
  if (bit !== undefined) actions &= ~bit;
});

// Release everything on blur, so a key held as the window loses focus does not
// stick down forever waiting for a keyup that never comes.
window.addEventListener('blur', () => {
  actions = 0;
});

/*
 * Mouse look, which only works because the viewport is a canvas. A native
 * window placed over the page would swallow these events before the page saw
 * them; an ordinary element receives them like any other.
 */
canvas.addEventListener('click', () => canvas.requestPointerLock());

document.addEventListener('mousemove', (event) => {
  if (document.pointerLockElement !== canvas) return;
  mouseDx += event.movementX;
  mouseDy += event.movementY;
});
