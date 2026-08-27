# InkyPinky2

## Dependencies
    - Odin (SPECIFICALLY VERSION `dev-2026-07-nightly:819fdc7`)
    - GLFW
    - Mesa

## To build engine

First install Dependencies
Arch:
``` bash
yay -S odin
sudo pacman -S glfw mesa
```

Build engine:

``` bash
make linux-engine          # Linux
```

``` bash
.\run.ps1 -Engine          # Windows
```

Run the editor:
``` bash
cd src/editor/
npm install
npm start
```

Run the runtime (just the viewport without editor, not recommended):
``` bash
make linux-engine
make linux-runtime
./build/inky
```

## Troubleshooting

### `make linux-engine` fails linking `libbox3d.a` / `libraylib.a` / `libraygui.a`

You have the wrong odin version or don't have the dependencies, please get `dev-2026-07-nightly:819fdc7` (or
later, YAY might have an outdated version) or any
version that supports box 3D. Make sure you have the dependencies too.

### `npm start` fails with "Electron failed to install correctly"

Electron's `postinstall` step downloads its real binary as a zip and unpacks
it with the `extract-zip` npm package, which can silently fail midway through
(stops after writing a single file, exits 0, prints nothing). You end up with
a `node_modules/electron/dist` folder that's a few hundred KB instead of
~250MB, and no `node_modules/electron/path.txt`.

Confirm the cached zip itself is fine (it usually is — this is a bug in the
JS unzip step, not a bad download):

```bash
unzip -l ~/.cache/electron/*/electron-v*-linux-x64.zip | tail -3
# should list ~74 files totaling ~270MB
```

Work around it by extracting with the system `unzip` instead:

```bash
cd src/editor
rm -rf node_modules/electron/dist
mkdir -p node_modules/electron/dist
unzip -q ~/.cache/electron/*/electron-v*-linux-x64.zip -d node_modules/electron/dist
mv node_modules/electron/dist/electron.d.ts node_modules/electron/electron.d.ts
printf 'electron' > node_modules/electron/path.txt
```

Then `npm start` should work normally.
