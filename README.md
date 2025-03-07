# seamstress

*seamstress* is a Lua scripting environment
for communicating with music, visuals and data.

> [!NOTE]
> this repository is for seamstress v1, for which development is more or less complete.
> i'm willing to provide maintenance for seamstress 1 if requested via the issue tracker!
> the future of the project is at [https://github.com/robbielyman/seamstress](https://github.com/robbielyman/seamstress).

## usage

seamstress is run from the command line. 
invoke it with `seamstress` or `seamstress <filename>`
(`seamstress -h` lists optional command-line arguments).
on startup, seamstress will search for a user-provided script file 
named `<filename>.lua` (defaulting to `script.lua`) to run.
this file may either be found in the current directory of your command-line prompt
or in `~/seamstress` (that is, a folder named `seamstress` under your `$HOME` directory,
which is typically `/Users/<username>` on macOS and `/home/<username>` on Linux).

on startup, seamstress creates two OS windows
and commandeers the command-line prompt as a Lua
REPL (short for **r**ead **e**valuate **p**rint **l**oop).
one of these windows is reserved for seamstress's `params` system,
while the other (the main window)
is available for scripts to draw to using seamstress's `screen` module.
to exit seamstress, close the main window or enter `quit` in to the REPL.

## scripting 

seamstress scripts are written in Lua,
an embeddable, extensible scripting language.
as of 1.0.0, seamstress supports Lua version 5.4.x.
[Lua.org](https://www.lua.org) has resources for programming in Lua.
additionally, [monome](https://monome.org) has studies for scripting in Lua for
[norns](https://monome.org/docs/norns/studies/) and [seamstress](https://monome.org/docs/grid/studies/seamstress/) to get you off the ground.

## installation

seamstress requires `freetype2`, `harfbuzz` and `ncurses`. on macOS do

```bash
brew install freetype2 harfbuzz ncurses
```

alternatively to install with homebrew, do
```bash
brew tap robbielyman/seamstress
brew install seamstress@1
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


building seamstress from source requires the latest stable version of [zig](https://github.com/ziglang/zig).
the easiest way to get zig is to download a binary from [here](https://ziglang.org/download/) and add it to your PATH.
(be sure that you do not choose a download from the "master" section.)
seamstress follows releases of zig.
to build seamstress, install the dependencies listed above (as well as `pkg-config`) and invoke

```bash
zig build
```

NB: this command builds `seamstress` in Debug mode.
you can change this 
by passing `-Doptimize=ReleaseFast` or `-Doptimize=ReleaseSafe` to the build command.

NB: `seamstress` will be built as `zig-out/bin/seamstress`; you can add this to your PATH to have it available as `seamstress`.

if you previously built seamstress with `sudo`, you may want to run `sudo zig build uninstall -p /usr/local` to remove the old binary.
you may also have to delete `~/.cache/zig` as well as `zig-cache` in the relevant directories.

## docs

the lua API is documented [here](https://ryleealanza.org/docs/index.html).
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
