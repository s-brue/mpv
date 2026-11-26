#!/bin/bash
# Build ffngx_dlssg.dll, the NVIDIA NGX wrapper of the dlssg_vulkan filter, with
# MSVC. The NGX SDK libraries for Windows do not link with MinGW.
#
#   usage: build-shim.sh FFMPEG_SOURCE DLSS_SDK OUTDIR
#
# On Linux this uses msvc-wine (https://github.com/mstorsjo/msvc-wine): set MSVC
# to its installation directory and, if needed, WINEPREFIX.
set -e
ffmpeg=$(realpath "$1")
dlss=$(realpath "$2")
mkdir -p "$3"
out=$(realpath "$3")
MSVC="${MSVC:-$HOME/.local/opt/msvc}"
[ -x "$MSVC/bin/x64/cl" ] || { echo "MSVC not found in $MSVC (set MSVC=...)" >&2; exit 1; }
if [ -z "$WINEPREFIX" ] && [ -d "$MSVC-wineprefix" ]; then
    export WINEPREFIX="$MSVC-wineprefix"
fi
export WINEDEBUG=-all PATH="$MSVC/bin/x64:$PATH"

work="$out/shim"
mkdir -p "$work/include" && cd "$work"
# only the Vulkan and NGX headers: never put /usr/include on the path of MSVC
cp -r /usr/include/vulkan /usr/include/vk_video include/
cp -r "$dlss"/include/. include/
cp "$ffmpeg"/libavfilter/ngx_dlssg.h "$ffmpeg"/libavfilter/ngx_dlssg.cpp .
cp "$dlss"/lib/Windows_x86_64/x64/nvsdk_ngx_s.lib .

cl /nologo /LD /EHsc /O2 /MT /std:c++latest /DFF_NGX_BUILD_DLL /Iinclude ngx_dlssg.cpp \
   /link nvsdk_ngx_s.lib advapi32.lib user32.lib /OUT:ffngx_dlssg.dll /IMPLIB:ffngx_dlssg.lib
cp ffngx_dlssg.dll ffngx_dlssg.lib "$out/"
