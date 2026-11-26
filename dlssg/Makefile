# Build mpv with DLSS Frame Generation and pack it.
#
#   make tbz       self-contained archive in $(OUTDIR), to be unpacked on /
#   make package   Arch package (install it with pacman -U)
#   make windows   .zip for Windows x86_64 in $(OUTDIR) (needs Docker and MSVC)
#   make clean     remove the work and output directories
#   make windows-installer  one setup .exe out of that .zip, for your own use
#                           (EXTRA_CONFIG=dir adds your own configuration)
#
# Arch User Repository (only the recipe is uploaded, never anything built):
#   make aur-test     build the package in a clean Arch container (needs Docker)
#   make aur          write PKGBUILD and .SRCINFO into $(AURDIR) and commit them
#   make aur-publish  push that commit to the AUR (needs an AUR account)
# MAINTAINER="Name <address>" adds the maintainer line; it is public.
#
# The sources can be overridden, e.g. to build from local clones:
#   make tbz FFMPEG_REPO=file://$$HOME/FFmpeg MPV_REPO=file://$$HOME/mpv
# (also MODERNZ_REPO, for the interface)

WORKDIR ?= $(CURDIR)/_work
OUTDIR  ?= $(CURDIR)/_out
export FFMPEG_REPO FFMPEG_BRANCH MPV_REPO MPV_BRANCH DLSS_REPO
export MODERNZ_REPO MODERNZ_BRANCH
AURDIR ?= $(CURDIR)/_aur
export WORKDIR OUTDIR MSVC AURDIR MAINTAINER EXTRA_CONFIG ZIP

.PHONY: tbz package windows windows-installer aur aur-test aur-publish clean

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

windows:
	./windows/build.sh

windows-installer:
	./windows/build-installer.sh

aur:
	./make-aur.sh prepare

aur-test:
	./test-package.sh

aur-publish:
	./make-aur.sh publish

clean:
	rm -rf "$(WORKDIR)" "$(OUTDIR)"
