![mpv logo](https://raw.githubusercontent.com/mpv-player/mpv.io/master/source/images/mpv-logo-128.png)

# mpv with DLSS Frame Generation

This is a fork of [mpv](https://github.com/mpv-player/mpv) that multiplies the
frame rate of videos (2x to 6x) with NVIDIA DLSS Frame Generation on Linux.

For everything about mpv itself (usage, system requirements, compilation
options, licensing, bug reporting) see the
**[README of the original project](https://github.com/mpv-player/mpv/blob/master/README.md)**.
Do not report problems with this fork to the mpv developers.

## What is changed

It takes two forks, both on their `dlssg` branch:

| Repository | Change |
|---|---|
| [s-brue/FFmpeg](https://github.com/s-brue/FFmpeg/tree/dlssg) | new `dlssg_vulkan` filter, which does the work |
| [s-brue/mpv](https://github.com/s-brue/mpv/tree/dlssg) | enables the Vulkan extensions NVIDIA NGX needs, plus the files in [`dlssg/`](dlssg) |

DLSS Frame Generation is meant for games, so what a game engine would provide is
substituted: motion vectors come from NVIDIA hardware optical flow (cleaned up
with a forward/backward check, hole filling and a median filter), depth is
constant and the camera is fixed.

## Requirements

* GeForce RTX 50 series for up to 6x. RTX 40 series should be limited to 2x
  (untested).
* A recent proprietary NVIDIA driver (developed with 620.73.04).
* Vulkan hardware decoding of the video you play.

## Installation (Arch Linux)

The [`dlssg/PKGBUILD`](dlssg/PKGBUILD) recipe downloads both forks and the
[NVIDIA DLSS SDK](https://github.com/NVIDIA/DLSS), builds them and installs
everything into `/opt/mpv-dlssg`. The system `mpv` and `ffmpeg` are not touched.

```sh
git clone --depth 1 --branch dlssg https://github.com/s-brue/mpv.git
cd mpv/dlssg
makepkg -si
```

The DLSS SDK is large (about 1.6 GB).

To build from local clones instead:

```sh
FFMPEG_REPO=file://$HOME/repos/FFmpeg MPV_REPO=file://$HOME/repos/mpv makepkg -si
```

### Other distributions

Follow `build()` and `package()` in the [`PKGBUILD`](dlssg/PKGBUILD). In short:
configure FFmpeg with a private `--prefix`, `--enable-nonfree --enable-libngx`
and the `include` and `lib/Linux_x86_64` directories of the DLSS SDK in the
compiler and linker flags; build mpv against that FFmpeg; run it with
`DLSSG_LIB_PATH` pointing to the directory that holds
`libnvidia-ngx-dlssg.so`.

## Usage

```sh
mpv-dlssg video.mkv
```

| Key | Action |
|---|---|
| `n` | rotate: off, 2x, 3x, 4x, 5x, 6x, off |
| `F7` | toggle DLSS-G at the last factor used (at first, the highest possible) |

Factors the display cannot show are skipped.

Your usual mpv configuration is used, and the keys are changed like any other
mpv binding, in `input.conf`:

```
n    script-binding dlssg/cycle
F7   script-binding dlssg/toggle
```

The filter can also be given directly, and it takes
[options](https://github.com/s-brue/FFmpeg/blob/dlssg/doc/filters.texi)
(search for `dlssg_vulkan`):

```sh
mpv-dlssg --hwdec=vulkan --vf=dlssg_vulkan=factor=4 video.mkv
```

## Limitations

* Quality: in a hold-out test on one film, DLSS-G did clearly better than
  FFmpeg's `fruc_vulkan`, but below the RIFE neural interpolator
  (VMAF 62.7 against 68.4, at 2x). Expect artifacts around occlusions.
* 6x has been tested for performance (3840x1606 at 144 fps on an RTX 5080 with
  no dropped frames), not evaluated for quality.
* Software decoded video is not supported.
* HDR video is untested.

## License

mpv keeps its [license](Copyright). The DLSS SDK is proprietary NVIDIA software
under its own license, and FFmpeg has to be built as `nonfree` to use it:
**the resulting binaries must not be redistributed.** Build them for yourself.
