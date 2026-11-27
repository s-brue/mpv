#!/bin/bash
# "make windows-installer": turn the .zip of "make windows" into one setup .exe
# for your own use. Do not distribute it.
#
# Needs Docker: NSIS runs in a Debian container.
#
#   ZIP=...           the .zip to pack (default: the newest one in OUTDIR)
#   EXTRA_CONFIG=...  directory copied over portable_config: more scripts or
#                     options of your own. Its mpv.conf is appended.
set -e
here=$(dirname "$(realpath "$0")")
outdir=$(realpath -m "${OUTDIR:-$here/../_out}")
zip=${ZIP:-$(ls -t "$outdir"/mpv-dlssg-windows-x86_64-*.zip 2>/dev/null | head -1)}

[ -f "$zip" ] || { echo "no .zip found: run 'make windows' first" >&2; exit 1; }
command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unzip -q "$zip" -d "$work/zip"
src=$(echo "$work"/zip/*)
version=${src##*-}
program=$work/program
config=$work/config
mkdir -p "$program" "$config/portable_config/scripts" "$config/portable_config/fonts" "$program/licenses"

# the program, and the scripts as part of its own configuration directory, so
# that mpv.exe alone does everything
cp -r "$src"/mpv.exe "$src"/mpv.com "$src"/mpv "$src"/ffmpeg.exe "$src"/ffngx_dlssg.dll "$src"/nvngx_dlssg.dll "$src"/nvvfx "$program/"
cp "$src"/NVIDIA-RTX-SDK.txt "$src"/ModernZ-LGPL-2.1.txt "$src"/thumbfast-MPL-2.0.txt "$program/licenses/"
cp "$here/../../LICENSE.GPL" "$program/licenses/mpv-GPL.txt"
mkdir -p "$program/portable_config/scripts" "$program/portable_config/fonts"
cp "$src"/dlssg.lua "$src"/modernz.lua "$src"/thumbfast.lua "$program/portable_config/scripts/"
cp "$src"/fonts/modernz-icons.ttf "$program/portable_config/fonts/"
mkdir -p "$program/portable_config/shaders"
cp "$src"/dlssg-sharpen.glsl "$program/portable_config/shaders/"

cat > "$config/portable_config/mpv.conf" <<'CONF'
# DLSS Frame Generation needs Vulkan
gpu-api=vulkan
hwdec=auto-safe

# No title bar: drag the picture to move the window, its edges to resize it.
# border=yes brings the title bar back.
border=no
CONF
if [ -n "${EXTRA_CONFIG:-}" ]; then
    # scripts and fonts are replaced when installing again, settings are kept
    (cd "$EXTRA_CONFIG" && find . -type f ! -path ./mpv.conf | while read -r f; do
        case $f in
            ./scripts/*|./fonts/*) to=$program/portable_config ;;
            *) to=$config/portable_config ;;
        esac
        cp --parents "$f" "$to/"
    done)
    if [ -f "$EXTRA_CONFIG/mpv.conf" ]; then
        cat "$EXTRA_CONFIG/mpv.conf" >> "$config/portable_config/mpv.conf"
    fi
fi

cat > "$program/DO-NOT-DISTRIBUTE.txt" <<TEXT
DO NOT DISTRIBUTE UNDER ANY CIRCUMSTANCES

mpv-dlssg $version: personal use only.

It contains GPL code (mpv, FFmpeg) linked with the proprietary NVIDIA NGX SDK,
NVIDIA's own nvngx_dlssg.dll and the NVIDIA VFX SDK libraries (nvvfx directory). Do not copy it to other people, do not upload
it anywhere and do not publish it. Licenses are in the "licenses" directory.

Keys: k DLSS Frame Generation (off, 2x..6x), h NVIDIA video Frame Generation
(medium/high 2x, 4x, medium 6x), a NVIDIA Super
Resolution, y sharpness, c window size, Alt+1..Alt+4 window at
100/75/50/25 % of the video, Ctrl+1 full screen, Ctrl+2..Ctrl+4 window at 75/50/25 %
of the screen, f or F11 full screen, Esc or q quit. Right click: menu.
The window has no title bar: drag the picture to move it and its edges to resize
it (border=yes in portable_config\\mpv.conf brings the bar back).

Needs Windows 10 or 11 (64 bit), a GeForce RTX 50 series card for up to 6x
(40 series: 2x, untested) and a recent NVIDIA driver.
TEXT
sed -i 's/$/\r/' "$program/DO-NOT-DISTRIBUTE.txt" "$config/portable_config/mpv.conf"

# what the uninstaller removes
{
    (cd "$program" && find . -type f; cd "$config" && find . -type f) | sort -u |
        sed 's|^\./||; s|/|\\|g; s|.*|  Delete "$INSTDIR\\&"|'
    (cd "$program" && find . -mindepth 1 -type d; cd "$config" && find . -mindepth 1 -type d) |
        sort -ur | sed 's|^\./||; s|/|\\|g; s|.*|  RMDir "$INSTDIR\\&"|'
} > "$work/delete.nsh"

cp "$here/installer.nsi" "$here/../../etc/mpv-icon.ico" "$work/"
cp "$program/DO-NOT-DISTRIBUTE.txt" "$work/notice.txt"
name=mpv-dlssg-setup-$version.exe
mkdir -p "$outdir"

docker run --rm -v "$work:/work" -e VERSION="$version" -e NAME="$name" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" debian:stable-slim sh -ec '
    apt-get update -qq >/dev/null
    apt-get install -qq -y --no-install-recommends nsis >/dev/null
    cd /work
    makensis -V2 -DOUTFILE="/work/$NAME" -DVERSION="$VERSION" -DICON=/work/mpv-icon.ico \
        -DNOTICE=/work/notice.txt -DPROGRAM=/work/program -DCONFIG=/work/config \
        -DDELETE_LIST=/work/delete.nsh installer.nsi
    chown "$HOST_UID:$HOST_GID" "$NAME"'

mv "$work/$name" "$outdir/"
echo "created $outdir/$name (do not distribute it)"
