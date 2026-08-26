/*
 * The engine's entire interface.
 *
 * Five functions and no structs, so there is no memory layout for a client to
 * reproduce and get wrong. The pointer arguments are declared uint64 and passed
 * as bigint: on a 64 bit target a pointer and a 64 bit integer are passed
 * identically, and this way TypeScript never has to invent a pointer type it
 * does not have. In offscreen mode they are unused anyway.
 */

import koffi from 'koffi';
import path from 'node:path';

/** Which kind of surface the engine should draw into. */
export const Surface = {
  WIN32: 1,
  X11: 2,
  WAYLAND: 3,
  /** No window at all: the engine renders into its own framebuffer. */
  OFFSCREEN: 4,
} as const;

/**
 * Movement intents, as a bit mask.
 *
 * These are not key codes. The engine has no notion of a keyboard, which is
 * why the same bits could come from a gamepad, a script or a recording without
 * it noticing the difference. Deciding that W means forward happens in the
 * renderer.
 */
export const Action = {
  FORWARD: 1 << 0,
  BACK: 1 << 1,
  LEFT: 1 << 2,
  RIGHT: 1 << 3,
  UP: 1 << 4,
  DOWN: 1 << 5,
} as const;

export interface Engine {
  /** Returns 1 on success, 0 on failure. */
  init(kind: number, display: bigint, handle: bigint, width: number, height: number): number;
  /** Advances and draws one frame. Returns 1 on success. */
  tick(dt: number, mouseDx: number, mouseDy: number, actions: number): number;
  /** Copies the last frame out as RGBA bytes. Returns the number written. */
  readPixels(dest: Buffer, capacity: number): number;
  resize(width: number, height: number): void;
  destroy(): number;
}

export function load(repoRoot: string): Engine {
  const file = process.platform === 'win32' ? 'engine.dll' : 'libengine.so';
  const lib = koffi.load(path.join(repoRoot, 'build', file));

  return {
    init: lib.func(
      'int32_t engine_init(uint32_t kind, uint64_t display, uint64_t handle, int32_t width, int32_t height)'
    ),
    tick: lib.func('int32_t engine_tick(float dt, float mouseDx, float mouseDy, uint32_t actions)'),
    // _Out_ so koffi writes straight into the Buffer passed in rather than
    // allocating one of its own.
    readPixels: lib.func('int32_t engine_read_pixels(_Out_ void *dest, int32_t capacity)'),
    resize: lib.func('void engine_resize(int32_t width, int32_t height)'),
    destroy: lib.func('int32_t engine_destroy()'),
  };
}
