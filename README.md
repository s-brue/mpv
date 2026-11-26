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
| [s-brue/mpv](https://github.com/s-brue/mpv/tree/dlssg) | enables the Vulkan extensions NVIDIA NGX needs, a few window and menu changes (below), plus the files in [`dlssg/`](dlssg) |

The interface is [ModernZ](https://github.com/Samillion/ModernZ), from the
[s-brue/ModernZ](https://github.com/s-brue/ModernZ/tree/dlssg) fork. The fork
uses green as its accent colour, hides the minimize, maximize and close symbols,
shows a single row (play, seekbar, `FG`, window size) in small windows, and
adds two buttons:

| Button | Left click | Right click |
|---|---|---|
| window, on the left | like the `c` key: window and video at 100%, 75%, 50%, 25% of the video size | back to 100% |
| `FG`, on the right | like the `k` key: off, 2x ... 6x; green while on | off |

The window and menu changes in mpv:

* on Wayland, borderless windows show resize cursors at their edges, and the
  edges take priority over the interface;
* on Wayland, the window does not go below 15% of the screen, however it is
  resized (`--window-min-screen`, 0 to disable);
* menus and lists stay readable in small windows (`min_scale` option of the
  context menu and the console);
* turning Frame Generation on or off keeps the window size;
* default keys: `Esc` quits, `F11` toggles full screen and `Alt+1` ... `Alt+4`
  set the window size (`Alt+2` no longer doubles it).

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

The [`dlssg/PKGBUILD`](dlssg/PKGBUILD) recipe downloads the forks and the
[NVIDIA DLSS SDK](https://github.com/NVIDIA/DLSS), builds them and installs
everything into `/opt/mpv-dlssg`. The system `mpv` and `ffmpeg` are not touched.

```sh
git clone --depth 1 --branch dlssg https://github.com/s-brue/mpv.git
cd mpv/dlssg
makepkg -si
```

The DLSS SDK is large: about 220 MB to download, 1.6 GB once checked out.

To build from local clones instead:

```sh
FFMPEG_REPO=file://$HOME/repos/FFmpeg MPV_REPO=file://$HOME/repos/mpv \
  MODERNZ_REPO=file://$HOME/repos/ModernZ makepkg -si
```

### A .tbz archive

`make tbz` builds the same package and turns it into a `.tbz` in `dlssg/_out`,
to be unpacked on `/` (its `opt/mpv-dlssg/INSTALL.txt` explains how). It takes
the same source overrides as above:

```sh
cd dlssg
make tbz
```

The archive contains proprietary NVIDIA software linked with GPL code: it is for
your own machines, **do not redistribute it** and do not upload it anywhere.

### Other distributions

Follow `build()` and `package()` in the [`PKGBUILD`](dlssg/PKGBUILD). In short:
configure FFmpeg with a private `--prefix`, `--enable-nonfree --enable-libngx`
and the `include` and `lib/Linux_x86_64` directories of the DLSS SDK in the
compiler and linker flags; build mpv against that FFmpeg.

At run time the filter needs the `libnvidia-ngx-dlssg.so.<version>` library of
the SDK. It looks for it in the directory of the program, then in its `ngx` and
`../lib/ngx` directories. If it is somewhere else, set `DLSSG_LIB_PATH` (or the
`libpath` option of the filter) to that directory.

## Publishing on the AUR

This is for whoever maintains the `mpv-dlssg-git` package. The AUR takes only the
recipe, so nothing built is ever uploaded: whoever installs the package compiles
it on their own machine.

```sh
cd dlssg
make aur-test     # build in a clean Arch container (needs Docker)
make aur          # write PKGBUILD and .SRCINFO into _aur/ and commit them
make aur-publish  # push that commit to the AUR
```

Publishing needs an AUR account with your SSH public key. The commit carries
your git name and address, and `MAINTAINER="Name <address>"` adds the maintainer
line to the `PKGBUILD`; all of that is public. The package builds what is on the
`dlssg` branches on GitHub, not your local clones, so push those first. Being a
`-git` package, it only needs `make aur` again when the recipe changes.

## Usage

```sh
mpv-dlssg video.mkv
```

| Key | Action |
|---|---|
| `k` | rotate: off, 2x, 3x, 4x, 5x, 6x, off |
| `c` | rotate the window size: 100%, 75%, 50%, 25% (needs ModernZ) |
| `Alt+1` ... `Alt+4` | window at 100%, 75%, 50%, 25% |
| `f` or `F11` | full screen |
| `Esc` or `q` | quit |

Factors the display cannot show are skipped.

Your usual mpv configuration is used, and the keys are changed like any other
mpv binding, in `input.conf`. There is also an on/off binding, `dlssg/toggle`,
with no key by default:

```
k    script-binding dlssg/cycle
T    script-binding dlssg/toggle
```

`mpv-dlssg` loads ModernZ unless your configuration already has an interface of
its own in `scripts/` (uosc, another OSC, or your own copy of ModernZ), or
`MPV_DLSSG_OSC=no` is set. It is configured as usual, in
`script-opts/modernz.conf`; its
[documentation](https://github.com/Samillion/ModernZ#customization) lists the
options. Thumbnails need [thumbfast](https://github.com/po5/thumbfast), which is
not included.

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
* HDR: on Linux, HDR10 (PQ, BT.2020) keeps 10 bits, its transfer function and
  metadata up to the display. It was tested with a clip converted from SDR, so
  the picture quality on real HDR material has not been judged. Dolby Vision,
  HDR10+ and HLG are untested.

## License

mpv keeps its [license](Copyright). The DLSS SDK is proprietary NVIDIA software
under its own license, and FFmpeg has to be built as `nonfree` to use it:
**the resulting binaries must not be redistributed.** Build them for yourself.
