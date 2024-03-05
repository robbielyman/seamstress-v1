# seamstress 2

*seamstress* is a Lua scripting environment
for communicating with music, visuals and data.

seamstress version 2 is pre-alpha software.

## discussion

if you'd like to help brainstorm (or develop!) seamstress version 2,
please consider joining the conversation [here](https://llllllll.co/t/seamstress-devlog/62356).
that link will contain a summary of seamstress 2's current capabilities.

## installation

seamstress requires `lua` and `notcurses`. on macOS do

```bash
brew install lua notcurses pkg-config
```

on ubuntu (for example) do

```bash
sudo apt-get install liblua5.4-dev libnotcurses-core-dev
```

alternatively to install with homebrew, do
```bash
brew tap ryleelyman/seamstress
brew install seamstress
```

## building from source


building seamstress from source requires the master (nightly) version of [zig](https://github.com/ziglang/zig).
the easiest way to get zig is to download a binary from [here](https://ziglang.org/download/) and add it to your PATH.
to build seamstress, install the dependencies listed above (as well as `pkg-config`) and invoke

```bash
zig build
```

NB: this command builds `seamstress` in Debug mode.
you can change this 
by passing `-Doptimize=ReleaseFast` or `-Doptimize=ReleaseSafe` to the build command.

NB: `seamstress` will be built as `zig-out/bin/seamstress`; you can add this to your PATH to have it available as `seamstress`.

## acknowledgments

seamstress is inspired by [monome norns's](https://github.com/monome/norns) matron,
which was written by [@catfact](https://github.com/catfact).
norns was initiated by [@tehn](https://github.com/tehn).
