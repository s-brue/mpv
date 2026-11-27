#!/bin/sh
# Publish the PKGBUILD on the Arch User Repository. Only the recipe goes there:
# the AUR does not take binaries, and ours must not be redistributed.
#   usage: make-aur.sh prepare|publish
set -eu
here=$(dirname "$(realpath "$0")")
name=mpv-dlssg-git
dir=$(realpath -m "${AURDIR:-$here/_aur}")/$name
work=$(realpath -m "${WORKDIR:-$here/_work}")/aur
push_url=ssh://aur@aur.archlinux.org/$name.git

# what is published has to work for everybody: no local source overrides
unset FFMPEG_REPO FFMPEG_BRANCH MPV_REPO MPV_BRANCH DLSS_REPO
unset MODERNZ_REPO MODERNZ_BRANCH THUMBFAST_REPO THUMBFAST_BRANCH

prepare() {
    if [ ! -d "$dir/.git" ]; then
        # a package that does not exist yet clones as an empty repository
        git clone -q "https://aur.archlinux.org/$name.git" "$dir"
        git -C "$dir" remote set-url --push origin "$push_url"
        git -C "$dir" rev-parse -q --verify HEAD >/dev/null ||
            git -C "$dir" symbolic-ref HEAD refs/heads/master
    elif git -C "$dir" rev-parse -q --verify origin/master >/dev/null; then
        git -C "$dir" pull -q --rebase
    fi

    maintainer=${MAINTAINER:+# Maintainer: $MAINTAINER}
    if [ -z "$maintainer" ] && [ -f "$dir/PKGBUILD" ]; then
        maintainer=$(grep '^# Maintainer:' "$dir/PKGBUILD" || true)
    fi

    # makepkg fetches the sources and runs pkgver(), which rewrites the PKGBUILD
    mkdir -p "$work/sources"
    {
        [ -z "$maintainer" ] || printf '%s\n' "$maintainer"
        cat "$here/PKGBUILD"
    } > "$work/PKGBUILD"
    (cd "$work" &&
        BUILDDIR="$work/build" SRCDEST="$work/sources" makepkg --nobuild --nodeps)

    cp "$work/PKGBUILD" "$dir/PKGBUILD"
    (cd "$dir" && makepkg --printsrcinfo > .SRCINFO)
    # ignore everything else, so that nothing built can ever be added
    printf '%s\n' '*' '!.gitignore' '!PKGBUILD' '!.SRCINFO' > "$dir/.gitignore"

    git -C "$dir" add .gitignore PKGBUILD .SRCINFO
    if git -C "$dir" diff --cached --quiet; then
        echo "$dir is already up to date"
        return
    fi
    version=$(sed -n 's/^\tpkgver = //p' "$dir/.SRCINFO")
    git -C "$dir" commit -q -m "Update to $version"
    echo "committed $version in $dir, authored as (this will be public):"
    git -C "$dir" log -1 --format='  %an <%ae>'
    echo "review it with: git -C $dir show"
    echo "then upload it with: make aur-publish"
}

publish() {
    [ -d "$dir/.git" ] || { echo "run 'make aur' first" >&2; exit 1; }
    git -C "$dir" push origin master
}

case ${1:-} in
    prepare) prepare ;;
    publish) publish ;;
    *) echo "usage: $0 prepare|publish" >&2; exit 2 ;;
esac
