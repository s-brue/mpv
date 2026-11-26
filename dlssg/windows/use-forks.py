#!/usr/bin/env python
"""Point the FFmpeg and mpv recipes of mpv-winbuild-cmake at the dlssg forks."""
import os, re, sys

packages = os.path.join(sys.argv[1], "packages")


def edit(name, replacements):
    path = os.path.join(packages, name)
    with open(path) as f:
        text = f.read()
    for old, new in replacements:
        if old not in text:
            sys.exit(f"{name}: expected text not found: {old!r}")
        text = text.replace(old, new, 1)
    with open(path, "w") as f:
        f.write(text)


def source(prefix):
    return f'GIT_REPOSITORY {os.environ[prefix + "_REPO"]}\n    GIT_TAG {os.environ[prefix + "_BRANCH"]}'


edit("ffmpeg.cmake", [
    ("        libplacebo\n        libzvbi", "        libplacebo\n        vulkan-header\n        libzvbi"),
    ("GIT_REPOSITORY https://github.com/FFmpeg/FFmpeg.git", source("FFMPEG")),
    ('GIT_CLONE_FLAGS "--sparse --filter=tree:0"\n    GIT_CLONE_POST_COMMAND "sparse-checkout set --no-cone /* !tests/ref/fate"\n', ""),
    ("        --enable-gpl\n", "        --enable-gpl\n        --enable-nonfree\n        --enable-libngx\n        --enable-vulkan\n"),
])
edit("mpv.cmake", [
    ("GIT_REPOSITORY https://github.com/mpv-player/mpv.git", source("MPV")),
    ('GIT_CLONE_FLAGS "--filter=tree:0"\n', ""),
    ("-Dpdf-build=enabled", "-Dpdf-build=disabled"),
    # curl pulls in ngtcp2, which does not build against current OpenSSL;
    # mpv still plays network streams through FFmpeg
    ("        subrandr\n        libsixel\n        curl\n", "        subrandr\n        libsixel\n"),
    ("-Dlibcurl=enabled", "-Dlibcurl=disabled"),
])
path = os.path.join(packages, "mpv.cmake")
with open(path) as f:
    lines = [line for line in f if "mpv.pdf" not in line]
with open(path, "w") as f:
    f.writelines(lines)
