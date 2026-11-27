#!/bin/bash
# Build the package in a clean Arch Linux container, where only what the
# PKGBUILD declares is installed, and check the result. Nothing is kept.
# The source overrides of the PKGBUILD apply (file:// repositories included).
set -e
here=$(dirname "$(realpath "$0")")

command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }
args=()
for var in FFMPEG_REPO FFMPEG_BRANCH MPV_REPO MPV_BRANCH \
    MODERNZ_REPO MODERNZ_BRANCH THUMBFAST_REPO THUMBFAST_BRANCH DLSS_REPO; do
    [ -n "${!var}" ] || continue
    args+=(-e "$var=${!var}")
    case ${!var} in
        file://*) args+=(-v "${!var#file://}:${!var#file://}:ro") ;;
    esac
done

docker run --rm -i -v "$here/PKGBUILD:/PKGBUILD:ro" "${args[@]}" archlinux:base-devel bash -s <<'CONTAINER'
set -e
pacman -Syu --noconfirm --needed base-devel git namcap >/tmp/pacman.log
useradd -m build
echo 'build ALL=(ALL) NOPASSWD: /usr/bin/pacman' > /etc/sudoers.d/build
install -d -o build /home/build/pkg
install -o build -m644 /PKGBUILD /home/build/pkg/
echo "MAKEFLAGS=-j$(nproc)" >> /etc/makepkg.conf
su build -c 'git config --global --add safe.directory "*" &&
    cd ~/pkg && makepkg --syncdeps --noconfirm --noprogressbar'

pkg=$(ls /home/build/pkg/*.pkg.tar.*)
echo "=== namcap"
namcap /home/build/pkg/PKGBUILD "$pkg"
echo "=== install and run"
pacman -U --noconfirm "$pkg" >/tmp/install.log
if ldd /opt/mpv-dlssg/bin/mpv /opt/mpv-dlssg/lib/*.so | grep 'not found'; then
    echo "missing libraries" >&2
    exit 1
fi
# resolve every symbol now: one left undefined (a library missing from the link)
# would otherwise only show when the filter starts, which needs a GPU
LD_BIND_NOW=1 /opt/mpv-dlssg/bin/ffmpeg -hide_banner -version >/dev/null
LD_BIND_NOW=1 mpv-dlssg --version >/dev/null
mpv-dlssg --version | head -3
test -s /opt/mpv-dlssg/share/mpv-dlssg/dlssg-sharpen.glsl
/opt/mpv-dlssg/bin/ffmpeg -hide_banner -filters | grep nvvfg_cuda
test -s /opt/mpv-dlssg/lib/nvvfx/libnvVFXVideoFrameGeneration.so
# the interface has to load, and its icon font has to be found
fc-list | grep modernz-icons
run() {
    mpv-dlssg --no-config --vo=null --ao=null --end=1 --msg-level=all=debug \
        av://lavfi:testsrc 2>&1
}
out=$(run)
grep -m1 'Loading lua script.*modernz' <<<"$out"
if grep -i 'lua error' <<<"$out"; then exit 1; fi
# not on top of another interface
mkdir -p /tmp/other/scripts/uosc
out=$(MPV_HOME=/tmp/other run)
if grep 'Loading lua script.*modernz' <<<"$out"; then exit 1; fi
# thumbnails: loaded, unless there is another copy
out=$(run)
grep -m1 'Loading lua script.*thumbfast' <<<"$out"
mkdir -p /tmp/thumbs/scripts && touch /tmp/thumbs/scripts/thumbfast.lua
out=$(MPV_HOME=/tmp/thumbs run)
if grep 'Loading lua script.*/opt/.*thumbfast' <<<"$out"; then exit 1; fi
# the filters thumbfast converts HDR thumbnails with (a failing one hangs mpv)
timeout 30 /opt/mpv-dlssg/bin/mpv --no-config --msg-level=all=error --frames=1 \
    "--vf=lavfi=[setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc,format=yuv420p10le,zscale=transfer=linear:npl=203,format=gbrpf32le,zscale=primaries=bt709,tonemap=mobius:desat=0,zscale=transfer=bt709:matrix=bt709:range=tv,format=yuv420p]" \
    --ovc=rawvideo --of=image2 --o=/tmp/thumb.yuv av://lavfi:testsrc=size=320x240
test -s /tmp/thumb.yuv
/opt/mpv-dlssg/bin/ffmpeg -hide_banner -filters | grep dlssg_vulkan
echo "=== OK"
CONTAINER
