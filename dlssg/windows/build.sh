#!/bin/bash
# "make windows": cross-build mpv with DLSS Frame Generation for Windows x86_64.
#
#   1. here: build ffngx_dlssg.dll with MSVC (see build-shim.sh)
#   2. in an Arch Linux container: build a MinGW toolchain, FFmpeg and mpv with
#      mpv-winbuild-cmake, and pack a .zip
#
# Needs Docker and MSVC (through msvc-wine). The toolchain and the downloads are
# kept in the Docker volume $VOLUME, so only the first build takes long.
set -e
here=$(dirname "$(realpath "$0")")
workdir=$(realpath -m "${WORKDIR:-$here/../_work}")/windows
outdir=$(realpath -m "${OUTDIR:-$here/../_out}")
FFMPEG_REPO="${FFMPEG_REPO:-https://github.com/s-brue/FFmpeg.git}"
FFMPEG_BRANCH="${FFMPEG_BRANCH:-dlssg}"
MPV_REPO="${MPV_REPO:-https://github.com/s-brue/mpv.git}"
MPV_BRANCH="${MPV_BRANCH:-dlssg}"
DLSS_REPO="${DLSS_REPO:-https://github.com/NVIDIA/DLSS.git}"
DLSS_TAG="${DLSS_TAG:-v310.9.16}"
MODERNZ_REPO="${MODERNZ_REPO:-https://github.com/s-brue/ModernZ.git}"
MODERNZ_BRANCH="${MODERNZ_BRANCH:-dlssg}"
VOLUME="${VOLUME:-mpv-dlssg-windows}"

command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }
mkdir -p "$workdir" "$outdir"

# sources needed on this side
rm -rf "$workdir/FFmpeg"
git clone -q --depth 1 --branch "$FFMPEG_BRANCH" "$FFMPEG_REPO" "$workdir/FFmpeg"
rm -rf "$workdir/ModernZ"
git clone -q --depth 1 --branch "$MODERNZ_BRANCH" "$MODERNZ_REPO" "$workdir/ModernZ"
if [ ! -d "$workdir/DLSS" ]; then
    git clone -q --depth 1 --branch "$DLSS_TAG" "$DLSS_REPO" "$workdir/DLSS"
fi

"$here/build-shim.sh" "$workdir/FFmpeg" "$workdir/DLSS" "$workdir/ngx"
cp "$workdir"/DLSS/lib/Windows_x86_64/rel/nvngx_dlssg.dll "$workdir/ngx/"
cp "$workdir"/DLSS/LICENSE.txt "$workdir/ngx/NVIDIA-RTX-SDK.txt"

# local repositories have to be visible inside the container, at the same path
mounts=()
for repo in "$FFMPEG_REPO" "$MPV_REPO"; do
    case $repo in
        file://*) mounts+=(-v "${repo#file://}:${repo#file://}:ro") ;;
    esac
done

docker run --rm \
    -v "$VOLUME:/work" \
    -v "$here:/scripts:ro" \
    -v "$here/..:/dlssg:ro" \
    -v "$workdir/ngx:/ngx:ro" \
    -v "$workdir/ModernZ:/modernz:ro" \
    -v "$outdir:/out" \
    "${mounts[@]}" \
    -e FFMPEG_REPO="$FFMPEG_REPO" -e FFMPEG_BRANCH="$FFMPEG_BRANCH" \
    -e MPV_REPO="$MPV_REPO" -e MPV_BRANCH="$MPV_BRANCH" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    archlinux:base-devel /scripts/in-container.sh
