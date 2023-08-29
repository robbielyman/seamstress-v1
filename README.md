# seamstress

seamstress is a lua scripting environment for musical communication.

write scripts that interact with monome devices, OSC, and MIDI.
a screen is provided for you to play with.

currently beta software.

## installation

seamstress requires `freetype2`, `harfbuzz` and `ncurses`. on macOS do

```bash
brew install freetype2 harfbuzz ncurses
```

on linux, additional requirements include `alsa`.
each release comes with a binary for `x86_64` linux and macOS,
as well as `aarch64` (Apple silicon) macOS.
download the appropriate file, unzip it and 
(technically optionally) add it to your PATH.

if you'd like to use [monome](https://monome.org) devices with seamstress,
you'll need to install [serialosc](https://github.com/monome/serialosc).

NB: `seamstress` expects the file structure found inside the zipped folder
and will not work as expected if you move only the binary to a different folder.

## building from source


building seamstress from source requires version 0.11.0 of [zig](https://github.com/ziglang/zig).
the easiest way to get zig is to download a binary from [here](https://ziglang.org/download/) and add it to your PATH.
seamstress follows releases of zig.
to build seamstress, install the dependencies listed above (as well as `pkg-config`) and invoke

```bash
git submodule update --init --recursive
zig build
```

if you get an error about `lua.h` not being found or `SDL2_image` fails to build, try these
```bash
pushd lib/SDL
zig build
popd
pushd lib/ziglua
zig build
popd
```
and then retry the `zig build` step above.

NB: these commands build `seamstress` in Debug mode.
you can change this 
by passing `-Doptimize=ReleaseFast` or `-Doptimize=ReleaseSafe` to the build command.

NB: `seamstress` will be built as `zig-out/bin/seamstress`; you can add this to your PATH to have it available as `seamstress`.

if you previously built seamstress with `sudo`, you may want to run `sudo zig build uninstall -p /usr/local` to remove the old binary.
you may also have to delete `~/.cache/zig` as well as `zig-cache` in the relevant directories.

## usage

invoke `seamstress` from the terminal.
`Ctrl+C`, 'quit' or closing the OS window exits.
by default seamstress looks for and runs a file called `script.lua`
in either the current directory or in `~/seamstress/`.
this behavior can be overridden, see `seamstress -h` for details.

## docs

the lua API is documented [here](https://ryleealanza.org/assets/docs/index.html).
to regenerate docs, you'll need [LDoc](https://github.com/lunarmodules/ldoc),
which requires Penlight.
with both installed, running `ldoc .` in the base directory of seamstress will
regenerate documentation.

## style

lua formatting is done with [stylua](https://github.com/JohnnyMorganz/StyLua),
while zig formatting is done with `zig fmt`.
a `stylua.toml` is provided, so if you feel like matching seamstress's "house lua style",
simply run `stylua .` in the root of the repo.
similarly, you can run `zig fmt filename.zig` to format `filename.zig`.
(this is not a requirement for contributing.)

## acknowledgments

seamstress is inspired by [monome norns's](https://github.com/monome/norns) matron,
which was written by [@catfact](https://github.com/catfact).
norns was initiated by [@tehn](https://github.com/tehn).
