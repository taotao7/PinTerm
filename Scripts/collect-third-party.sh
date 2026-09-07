#!/bin/bash
set -euo pipefail
ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
LICENSES="$ROOT/Resources/Licenses"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
STAGE="$WORK/PinTerm-$VERSION-ThirdPartySources"
mkdir -p "$LICENSES" "$STAGE/sources" "$ROOT/dist"
: > "$LICENSES/SOURCES.tsv"
fetch() {
    curl --http1.1 --fail --location --silent --show-error --retry 3 --retry-all-errors --connect-timeout 20 --speed-limit 1024 --speed-time 30 "$1" -o "$2"
    test -s "$2"
}
license() {
    mkdir -p "$LICENSES/$(dirname "$1")"
    fetch "$2" "$LICENSES/$1"
    printf '%s\t%s\n' "$1" "$2" >> "$LICENSES/SOURCES.tsv"
}
archive() {
    fetch "$2" "$STAGE/sources/$1"
    tar -tzf "$STAGE/sources/$1" >/dev/null
    printf '%s\t%s\n' "$1" "$2" >> "$STAGE/SOURCES.tsv"
}
G=c4e16970a803b170e352432424f44192cb59f3ac
W=733ae3b29d447b6707cbfc00879027a076dfd0eb
RAW=https://raw.githubusercontent.com
archive "ghostty-$G.tar.gz" "https://codeload.github.com/ghostty-org/ghostty/legacy.tar.gz/$G"
archive "libghostty-spm-$W.tar.gz" "https://codeload.github.com/Lakr233/libghostty-spm/tar.gz/$W"
archive gettext-0.24.tar.gz https://deps.files.ghostty.org/gettext-0.24.tar.gz
archive z2d-7dbae85c81784dba9988320bf9543ed9a81350c8.tar.gz https://deps.files.ghostty.org/z2d-7dbae85c81784dba9988320bf9543ed9a81350c8.tar.gz
archive MSDisplayLink-2.2.0.tar.gz https://codeload.github.com/Lakr233/MSDisplayLink/tar.gz/87eb0af130744c8cbe2e31b6e1a5bcd659f1c220
license Ghostty/LICENSE "$RAW/ghostty-org/ghostty/$G/LICENSE"
license libghostty-spm/LICENSE "$RAW/Lakr233/libghostty-spm/$W/LICENSE"
license MSDisplayLink/LICENSE "$RAW/Lakr233/MSDisplayLink/87eb0af130744c8cbe2e31b6e1a5bcd659f1c220/LICENSE"
license bash-preexec/LICENSE.md "$RAW/Lakr233/libghostty-spm/$W/Sources/GhosttyTerminal/Resources/Ghostty/shell-integration/bash/LICENSE-bash-preexec.md"
license JetBrainsMono/OFL.txt "$RAW/JetBrains/JetBrainsMono/v2.304/OFL.txt"
fetch https://deps.files.ghostty.org/NerdFontsSymbolsOnly-3.4.0.tar.gz "$WORK/fonts.tar.gz"
mkdir "$WORK/fonts"
tar -xzf "$WORK/fonts.tar.gz" -C "$WORK/fonts"
mkdir -p "$LICENSES/NerdFontsSymbolsOnly"
cp "$(find "$WORK/fonts" -name LICENSE -type f | head -1)" "$LICENSES/NerdFontsSymbolsOnly/LICENSE"
printf '%s\t%s\n' NerdFontsSymbolsOnly/LICENSE https://deps.files.ghostty.org/NerdFontsSymbolsOnly-3.4.0.tar.gz >> "$LICENSES/SOURCES.tsv"
license NerdFontsSymbolsOnly/README.md "$RAW/ryanoasis/nerd-fonts/v3.4.0/readme.md"
license NerdFontsSymbolsOnly/glyphs/README.md "$RAW/ryanoasis/nerd-fonts/v3.4.0/src/glyphs/README.md"
for path in codicons/LICENSE.txt font-awesome/LICENSE.txt materialdesign/LICENSE octicons/LICENSE pomicons/LICENSE powerline-extra/LICENSE powerline-symbols/LICENSE.txt weather-icons/OFL.txt; do
    license "NerdFontsSymbolsOnly/glyphs/$path" "$RAW/ryanoasis/nerd-fonts/v3.4.0/src/glyphs/$path"
done
for path in LICENSE COPYING; do
    license "z2d/$path" "$RAW/vancluever/z2d/7dbae85c81784dba9988320bf9543ed9a81350c8/$path"
done
for path in LICENSE.md licenses/LICENSE_unicode licenses/LICENSE_Bjoern_Hoehrmann; do
    license "uucode/$path" "$RAW/jacobsandlund/uucode/2826a37a4562284fdacd8fa029d49509cc9bffcd/$path"
done
license libxev/LICENSE "$RAW/mitchellh/libxev/9ce8e8e6ff89e583258a7f8e7adeeeaeae8611bf/LICENSE"
license zig-objc/LICENSE "$RAW/mitchellh/zig-objc/c8de82ff80281215ad92900866dab7103a8efa8b/LICENSE"
license zf/LICENSE "$RAW/natecraddock/zf/c35c421f84895193246db06c40683c1a30e616ef/LICENSE"
license libvaxis/LICENSE "$RAW/rockorager/libvaxis/1dbbe575dff4586fe51e3217aa5c3fecdcbb6089/LICENSE"
license oniguruma/COPYING "$RAW/kkos/oniguruma/v6.9.9/COPYING"
license highway/LICENSE "$RAW/google/highway/66486a10623fa0d72fe91260f96c892e41aceb06/LICENSE"
license simdutf/LICENSE-MIT "$RAW/simdutf/simdutf/v5.2.8/LICENSE-MIT"
fetch https://deps.files.ghostty.org/wuffs-7411f488fe2e2c205c3d3b3d28638b7356522930.tar.gz "$WORK/wuffs.tar.gz"
mkdir "$WORK/wuffs"
tar -xzf "$WORK/wuffs.tar.gz" -C "$WORK/wuffs"
mkdir -p "$LICENSES/wuffs"
cp "$(find "$WORK/wuffs" -name LICENSE -type f | head -1)" "$LICENSES/wuffs/LICENSE"
printf '%s\t%s\n' wuffs/LICENSE https://deps.files.ghostty.org/wuffs-7411f488fe2e2c205c3d3b3d28638b7356522930.tar.gz >> "$LICENSES/SOURCES.tsv"
license FreeType/FTL.TXT "$RAW/freetype/freetype/VER-2-13-2/docs/FTL.TXT"
license libpng/LICENSE "$RAW/pnggroup/libpng/v1.6.43/LICENSE"
license zlib/LICENSE "$RAW/madler/zlib/v1.3.1/LICENSE"
fetch https://ziglang.org/download/0.16.0/zig-0.16.0.tar.xz "$WORK/zig.tar.xz"
echo "43186959edc87d5c7a1be7b7d2a25efffd22ce5807c7af99067f86f99641bfdf  $WORK/zig.tar.xz" | shasum -a 256 -c -
mkdir -p "$LICENSES/Zig"
tar -xOJf "$WORK/zig.tar.xz" zig-0.16.0/LICENSE > "$LICENSES/Zig/LICENSE"
printf '%s\t%s\n' Zig/LICENSE https://ziglang.org/download/0.16.0/zig-0.16.0.tar.xz >> "$LICENSES/SOURCES.tsv"
mkdir -p "$LICENSES/gettext"
tar -xOf "$STAGE/sources/gettext-0.24.tar.gz" gettext-0.24/gettext-runtime/intl/COPYING.LIB > "$LICENSES/gettext/COPYING.LIB"
printf '%s\t%s\n' gettext/COPYING.LIB https://deps.files.ghostty.org/gettext-0.24.tar.gz >> "$LICENSES/SOURCES.tsv"
mkdir "$WORK/ghostty"
tar -xzf "$STAGE/sources/ghostty-$G.tar.gz" -C "$WORK/ghostty" --strip-components=1
# Preserve the embedded upstream license verbatim, not a retyped MIT template.
mkdir -p "$LICENSES/stb"
find "$WORK/ghostty" -name 'stb*.h' -type f | while read -r header; do
    sed -n '/ALTERNATIVE A - MIT License/,$p' "$header" > "$LICENSES/stb/$(basename "$header").LICENSE.txt"
    test -s "$LICENSES/stb/$(basename "$header").LICENSE.txt"
    printf '%s\t%s\n' "stb/$(basename "$header").LICENSE.txt" "$RAW/ghostty-org/ghostty/$G/${header#"$WORK/ghostty/"}" >> "$LICENSES/SOURCES.tsv"
done
test -n "$(find "$LICENSES/stb" -type f)"
find "$LICENSES" -type f ! -name SHA256SUMS -exec shasum -a 256 {} \; | sed "s|$LICENSES/||" | LC_ALL=C sort > "$LICENSES/SHA256SUMS"
cp "$ROOT/docs/REBUILDING.md" "$STAGE/REBUILDING.md"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/THIRD_PARTY_NOTICES.md"
cp -R "$LICENSES" "$STAGE/Licenses"
(cd "$STAGE" && shasum -a 256 sources/* > SHA256SUMS)
COPYFILE_DISABLE=1 tar -czf "$ROOT/dist/PinTerm-$VERSION-ThirdPartySources.tar.gz" -C "$WORK" "PinTerm-$VERSION-ThirdPartySources"
tar -tzf "$ROOT/dist/PinTerm-$VERSION-ThirdPartySources.tar.gz"
shasum -a 256 "$ROOT/dist/PinTerm-$VERSION-ThirdPartySources.tar.gz"
