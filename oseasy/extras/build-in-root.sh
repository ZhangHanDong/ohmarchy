#!/bin/bash
# build-in-root.sh OUTDIR: the Oseasy extras that have to match the image, made
# inside a throwaway copy of its root (28-build-extras.sh):
#
#   ohmarchy-glfinish.so  glfinish.c, preloaded into Hyprland (see there)
#   pkgs/                 the Pinyin input method (fcitx5-chinese-addons) and the
#                         packages it needs beyond what the image has
#
# The image's package databases are older than the mirrors, which no longer
# carry those versions, so the packages are the mirror's current ones, with only
# the dependencies the image cannot satisfy. fcitx5 comes along to match the
# engine; fcitx5-qt stays as installed, since the mirror's is built for a newer
# Qt than the image has.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
out=${1:?usage: build-in-root.sh OUTDIR}
mkdir -p "$out/pkgs"

pacman -Sy --needed --noconfirm gcc >/dev/null
gcc -O2 -shared -fPIC -o "$out/ohmarchy-glfinish.so" "$here/glfinish.c"

pacman -Sw --noconfirm --cachedir "$out/pkgs" fcitx5-chinese-addons fcitx5 >/dev/null
ls "$out"/ohmarchy-glfinish.so "$out"/pkgs/*.pkg.tar.*
