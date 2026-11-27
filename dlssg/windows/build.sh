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
VFX_WHL="nvidia_vfx-0.2.0.0-cp312-abi3-win_amd64.whl"
VFX_SHA256=cebaa12411f7e22b39293205c5c4d07b8073d14ca1e0e7727ee4375207a36445
MODERNZ_REPO="${MODERNZ_REPO:-https://github.com/s-brue/ModernZ.git}"
MODERNZ_BRANCH="${MODERNZ_BRANCH:-dlssg}"
THUMBFAST_REPO="${THUMBFAST_REPO:-https://github.com/s-brue/thumbfast.git}"
THUMBFAST_BRANCH="${THUMBFAST_BRANCH:-dlssg}"
VOLUME="${VOLUME:-mpv-dlssg-windows}"

command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }
mkdir -p "$workdir" "$outdir"

# sources needed on this side
rm -rf "$workdir/FFmpeg"
git clone -q --depth 1 --branch "$FFMPEG_BRANCH" "$FFMPEG_REPO" "$workdir/FFmpeg"
rm -rf "$workdir/ModernZ"
git clone -q --depth 1 --branch "$MODERNZ_BRANCH" "$MODERNZ_REPO" "$workdir/ModernZ"
rm -rf "$workdir/thumbfast"
git clone -q --depth 1 --branch "$THUMBFAST_BRANCH" "$THUMBFAST_REPO" "$workdir/thumbfast"
if [ ! -d "$workdir/DLSS" ]; then
    git clone -q --depth 1 --branch "$DLSS_TAG" "$DLSS_REPO" "$workdir/DLSS"
fi

"$here/build-shim.sh" "$workdir/FFmpeg" "$workdir/DLSS" "$workdir/ngx"

# NVIDIA VFX SDK for Video Frame Generation and Super Resolution, from the wheel of
# its Python package,
# plus the Visual C++ runtime it needs (from the MSVC used above)
[ -f "$workdir/$VFX_WHL" ] || curl -sSfL -o "$workdir/$VFX_WHL" "https://pypi.nvidia.com/nvidia-vfx/$VFX_WHL"
echo "$VFX_SHA256  $workdir/$VFX_WHL" | sha256sum -c --quiet
rm -rf "$workdir/nvvfx" && mkdir -p "$workdir/nvvfx"
(cd "$workdir/nvvfx" && unzip -q -j "../$VFX_WHL" nvvfx/libs/NVCVImage.dll nvvfx/libs/NVVideoEffects.dll \
    nvvfx/libs/nvVFXVideoFrameGeneration.dll nvvfx/libs/cudart64_12.dll \
    nvvfx/libs/nvVFXVideoSuperRes.dll nvvfx/libs/nvngxruntime.dll nvvfx/libs/nvngx_vsr.dll \
    '*.dist-info/licenses/packaging/NVIDIA-Software-License-Agreement-*' \
    '*.dist-info/licenses/packaging/product-specific-terms-*' \
    '*.dist-info/licenses/packaging/ThirdPartyLicenses_VFX_SDK.txt')
runtime=$(ls -d "${MSVC:-$HOME/.local/opt/msvc}"/VC/Tools/MSVC/*/bin/Hostx64/x64 | tail -1)
cp "$runtime"/msvcp140.dll "$runtime"/vcruntime140.dll "$runtime"/vcruntime140_1.dll "$workdir/nvvfx/"
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
    -v "$workdir/nvvfx:/nvvfx:ro" \
    -v "$workdir/ModernZ:/modernz:ro" \
    -v "$workdir/thumbfast:/thumbfast:ro" \
    -v "$outdir:/out" \
    "${mounts[@]}" \
    -e FFMPEG_REPO="$FFMPEG_REPO" -e FFMPEG_BRANCH="$FFMPEG_BRANCH" \
    -e MPV_REPO="$MPV_REPO" -e MPV_BRANCH="$MPV_BRANCH" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    archlinux:base-devel /scripts/in-container.sh
