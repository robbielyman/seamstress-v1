#!/bin/bash

sudo mkdir /opt/zig
wget https://ziglang.org/builds/zig-macos-aarch64-0.11.0-dev.3971+6bc9c4f71.tar.xz
tar -xf zig-macos-aarch64-0.11.0-dev.3971+6bc9c4f71.tar.xz -C /tmp
sudo cp -R /tmp/zig-macos-aarch64-0.11.0-dev.3971+6bc9c4f71/* /opt/zig
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install freetype2 harfbuzz ncurses pkg-config
pushd lib/ziglua
/opt/zig/zig build -Doptimize=ReleaseFast
popd
/opt/zig/zig build -Doptimize=ReleaseFast
