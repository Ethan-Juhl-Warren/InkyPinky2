/*
 * The editor's main process, which does almost nothing.
 *
 * It opens a window and gets out of the way. The engine is loaded and driven
 * by the page itself, in the renderer process, and that is the entire reason
 * this file is short.
 *
 * The obvious arrangement is the opposite one: run the engine here, render
 * offscreen, and send each finished frame to the page. It works and it is slow,
 * for a reason worth writing down. A frame at a normal viewport size is about
 * three megabytes, Electron's IPC copies and serialises it on the way across,
 * and that costs roughly nine milliseconds a frame. Against a sixteen
 * millisecond budget it is most of the frame, and no amount of tuning helps,
 * because the pixels should not be crossing a process boundary at all. Loading
 * the engine where the canvas already is removes the trip rather than
 * optimising it.
 *
 * The cost of that is nodeIntegration, so the page can load a native module.
 * For a local editor driving a native engine that is the point rather than a
 * compromise; this window loads its own files and nothing remote.
 */

import { app, BrowserWindow } from 'electron';
import path from 'node:path';

let window: BrowserWindow | null = null;

app.whenReady().then(() => {
  window = new BrowserWindow({
    width: 1600,
    height: 900,
    title: 'Inky Editor',
    backgroundColor: '#1e1e1e',
    webPreferences: {
      // The page loads the engine itself. Without contextIsolation off, the
      // pixel buffer would be copied across the isolated world boundary on
      // every frame, which is the cost this whole arrangement exists to avoid.
      nodeIntegration: true,
      contextIsolation: false,
    },
  });

  window.loadFile(path.join(__dirname, '..', 'index.html'));

  // Forward the page's console to this process's stdout, so the timings show
  // up in the terminal alongside everything else.
  window.webContents.on('console-message', (_event, _level, message) => {
    console.log('[page]', message);
  });

  window.on('closed', () => {
    window = null;
  });
});

app.on('window-all-closed', () => app.quit());
