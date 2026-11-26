#!/bin/sh
# Turn the Arch package into a .tbz that can be unpacked on /.
#   usage: make-tbz.sh PACKAGE OUTDIR
set -eu
pkg=$1
outdir=$2

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/root"
bsdtar -xf "$pkg" -C "$tmp/root" --exclude .BUILDINFO --exclude .MTREE --exclude .PKGINFO
bsdtar -xOf "$pkg" .PKGINFO > "$tmp/pkginfo"
version=$(sed -n 's/^pkgver = //p' "$tmp/pkginfo")
deps=$(sed -n 's/^depend = //p' "$tmp/pkginfo" | tr '\n' ' ')

name="mpv-dlssg-${version}-$(uname -m).tbz"
{
    cat <<TEXT
mpv-dlssg: mpv with NVIDIA DLSS Frame Generation

PERSONAL USE ONLY, DO NOT REDISTRIBUTE: GPL code (mpv, FFmpeg) linked with the
proprietary NVIDIA NGX SDK, plus NVIDIA's libnvidia-ngx-dlssg.so.

Requirements: GeForce RTX 50 series for up to 6x (40 series: 2x, untested), the
proprietary NVIDIA driver, and an up to date Arch Linux: the binaries link
against the library versions of the day they were built.

Install:    sudo tar -xjf $name -C /
Run:        mpv-dlssg video.mkv      (k rotates 2x..6x/off)
Uninstall:  sudo rm -rf /opt/mpv-dlssg /usr/bin/mpv-dlssg \\
                 /usr/share/fonts/mpv-dlssg /usr/share/licenses/mpv-dlssg-git

Dependencies (pacman does not track them with this method):
TEXT
    echo "  sudo pacman -S --needed $deps" | fold -s -w 78
    echo
    echo "Version: $version"
} > "$tmp/root/opt/mpv-dlssg/INSTALL.txt"

# only files go in, so that unpacking on / never changes system directories
(cd "$tmp/root" && find . \( -type f -o -type l \) | sed 's|^\./||' | sort) > "$tmp/files"
mkdir -p "$outdir"
tar -C "$tmp/root" --owner=0 --group=0 --numeric-owner --no-recursion \
    -cjf "$outdir/$name" -T "$tmp/files"
echo "created $outdir/$name"
