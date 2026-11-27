mpv with NVIDIA DLSS Frame Generation (Windows x86_64)

PERSONAL USE ONLY, DO NOT REDISTRIBUTE: GPL code (mpv, FFmpeg) linked with the
proprietary NVIDIA NGX SDK, plus NVIDIA's nvngx_dlssg.dll.

Unpack anywhere and drop a video on mpv-dlssg.bat.

  k    rotate: off, 2x, 3x, 4x, 5x, 6x, off
  h    NVIDIA video frame generation: medium 2x, high 2x, medium 4x, high 4x, medium 6x, off
  a    NVIDIA Super Resolution up to the screen size: off, for good sources, for compressed ones
  y    sharpness: off, 0.25, 0.5, 0.75, 1
  c    window size: 100%, 75%, 50%, 25% (also Alt+1 .. Alt+4)
  Ctrl+1 full screen, Ctrl+2 .. Ctrl+4 window at 75%, 50%, 25% of the screen
  f    full screen (also F11)
  q    quit (also Esc)

Hardware (only an RTX 5080 has been tried; the rest follows NVIDIA's requirements):

                          RTX 50    RTX 40    RTX 30/20    others
  k  DLSS Frame Gen.      up to 6x  2x        no           no
  h  NVIDIA video FG      yes       yes       no           no
  a  Super Resolution     yes       yes       yes          no
  y  sharpness            yes       yes       yes          yes

What the card cannot do is dimmed and its key does nothing. Needs NVIDIA driver
570.65 or newer.

This build has not been tested on real Windows yet.
