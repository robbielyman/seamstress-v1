#!/bin/sh

mkdir /opt/zig
wget https://ziglang.org/builds/zig-linux-x86_64-0.12.0.tar.xz
tar -xf zig-linux-x86_64-0.12.0.tar.xz -C /tmp
cp -R /tmp/zig-linux-x86_64-0.12.0/* /opt/zig
sudo apt-get update
sudo apt-get install \
     libncurses-dev libasound2-dev libfreetype-dev \
     libharfbuzz-dev libudev-dev libsamplerate0-dev \
     libdbus-1-dev libwayland-dev libxkbcommon-dev \
     libdecor-0-dev libxcb-xkb-dev libx11-dev \
     libegl-dev libxcursor-dev libxext-dev libxi-dev \
     libxrandr-dev libxss-dev libjack-dev libpipewire-0.3-dev \
     multimedia-devel libgudev-1.0-0 libdrm-dev libgbm-dev
/opt/zig/zig build -Doptimize=ReleaseFast -Dcpu=x86_64 --summary all
