#!/bin/bash
# Runs inside the Arch Linux container started by build.sh.
set -e
WINBUILD_REPO=https://github.com/shinchiro/mpv-winbuild-cmake.git
WINBUILD_COMMIT=7e36e1e

pacman -Syu --noconfirm --needed \
    base-devel git gyp mercurial subversion ninja cmake meson ragel yasm nasm asciidoc \
    enca gperf unzip zip p7zip clang lld libc++ libc++abi python python-pip curl wget \
    ccache re2c shaderc python-mako python-jsonschema python-docutils python-jinja \
    >/work/pacman.log

git config --global --add safe.directory '*'
git config --global user.name build
git config --global user.email build@localhost
git config --global advice.detachedHead false

cd /work
[ -d mpv-winbuild-cmake ] || git clone -q "$WINBUILD_REPO"
git -C mpv-winbuild-cmake checkout -q -f "$WINBUILD_COMMIT"
python /scripts/use-forks.py mpv-winbuild-cmake

# an interrupted build can leave a half applied patch that blocks the next one
for am in src/*/.git/rebase-apply; do
    if [ -d "$am" ]; then
        git -C "${am%/.git/rebase-apply}" am --abort || rm -rf "$am"
    fi
done

# sources of the forks are always fetched again
rm -rf build/packages/ffmpeg-prefix build/packages/mpv-prefix src/ffmpeg src/mpv

cmake -DTARGET_ARCH=x86_64-w64-mingw32 -DGCC_ARCH=x86-64 -DSINGLE_SOURCE_LOCATION=/work/src \
    -G Ninja -B build -S mpv-winbuild-cmake
# the x86_64-...-gcc wrapper exists from the start: look for the real compiler
[ -x build/install/bin/cross-gcc ] || ninja -C build gcc

prefix=/work/build/install/x86_64-w64-mingw32
mkdir -p "$prefix/lib"
cp /ngx/ffngx_dlssg.lib "$prefix/lib/"

rm -rf build/mpv-x86_64-* build/mpv-debug-* build/mpv-dev-*
ninja -C build mpv

package=$(ls -d build/mpv-x86_64-* | head -1)
commit=$(git -C src/mpv rev-parse --short=10 HEAD)
name="mpv-dlssg-windows-x86_64-$commit"
rm -rf "/work/$name" && mkdir "/work/$name"
cp "$package"/mpv.exe "$package"/mpv.com "/work/$name/"
cp -r "$package"/mpv "/work/$name/"
cp /ngx/ffngx_dlssg.dll /ngx/nvngx_dlssg.dll /ngx/NVIDIA-RTX-SDK.txt "/work/$name/"
cp /dlssg/dlssg.lua "/work/$name/"
sed 's/$/\r/' /scripts/mpv-dlssg.bat > "/work/$name/mpv-dlssg.bat"
sed 's/$/\r/' /scripts/README.txt > "/work/$name/README.txt"

cd /work
rm -f "/out/$name.zip"
zip -qr "/out/$name.zip" "$name"
chown "$HOST_UID:$HOST_GID" "/out/$name.zip"
echo "created $name.zip"
