# Build mpv with DLSS Frame Generation and pack it.
#
#   make tbz       self-contained archive in $(OUTDIR), to be unpacked on /
#   make package   Arch package (install it with pacman -U)
#   make clean     remove the work and output directories
#
# The sources can be overridden, e.g. to build from local clones:
#   make tbz FFMPEG_REPO=file://$$HOME/FFmpeg MPV_REPO=file://$$HOME/mpv

WORKDIR ?= $(CURDIR)/_work
OUTDIR  ?= $(CURDIR)/_out
export FFMPEG_REPO FFMPEG_BRANCH MPV_REPO MPV_BRANCH DLSS_REPO

.PHONY: tbz package clean

# makepkg rewrites pkgver in the PKGBUILD it runs, so it gets a copy
package:
	mkdir -p "$(WORKDIR)" "$(OUTDIR)"
	cp PKGBUILD "$(WORKDIR)/"
	rm -f "$(WORKDIR)"/*.pkg.tar*
	cd "$(WORKDIR)" && \
	    BUILDDIR="$(WORKDIR)/build" SRCDEST="$(WORKDIR)/sources" PKGDEST="$(WORKDIR)" \
	    makepkg --force --cleanbuild
	cp "$(WORKDIR)"/*.pkg.tar* "$(OUTDIR)/"

tbz: package
	./make-tbz.sh "$(WORKDIR)"/*.pkg.tar* "$(OUTDIR)"

clean:
	rm -rf "$(WORKDIR)" "$(OUTDIR)"
