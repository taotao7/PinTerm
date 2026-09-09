# PinTerm 0.4.2 — third-party notices

PinTerm's own application source is MIT licensed; see the top-level LICENSE at
<https://github.com/taotao7/PinTerm/tree/v0.4.2>. Third-party components retain
their own copyrights and terms. The full texts are in `Resources/Licenses/`
(in the app: `PinTerm.app/Contents/Resources/Licenses/`). `SOURCES.tsv` records
the authoritative retrieval URLs and `SHA256SUMS` identifies the supplied files.

This inventory conservatively includes native dependencies that may have been
removed by static linking; inclusion is not a claim that every component is
present in the executable. The executable contains GNU gettext/libintl symbols:
its LGPL obligations must not be dismissed merely because the Swift wrapper and
Ghostty are MIT licensed.

## Components and full texts

| Component / release or revision | License files under `Resources/Licenses/` |
| --- | --- |
| Ghostty `c4e16970a803b170e352432424f44192cb59f3ac` | `Ghostty/LICENSE` (MIT) |
| libghostty-spm `1.5.20260906`, `733ae3b29d447b6707cbfc00879027a076dfd0eb` | `libghostty-spm/LICENSE` (MIT; includes wrapper shell integration) |
| MSDisplayLink `2.2.0`, `87eb0af130744c8cbe2e31b6e1a5bcd659f1c220` | `MSDisplayLink/LICENSE` (MIT) |
| bash-preexec (as bundled by that wrapper) | `bash-preexec/LICENSE.md` (MIT; also alongside the bundled script) |
| JetBrains Mono `2.304` | `JetBrainsMono/OFL.txt` (SIL OFL 1.1) |
| Nerd Fonts Symbols Only `3.4.0` | `NerdFontsSymbolsOnly/LICENSE`; `NerdFontsSymbolsOnly/glyphs/README.md` and the eight glyph-source licenses below |
| z2d `7dbae85c81784dba9988320bf9543ed9a81350c8` | `z2d/LICENSE`, `z2d/COPYING` (MPL 2.0) |
| uucode `2826a37a4562284fdacd8fa029d49509cc9bffcd` | `uucode/LICENSE.md`, `uucode/licenses/LICENSE_unicode`, `uucode/licenses/LICENSE_Bjoern_Hoehrmann` |
| libxev `9ce8e8e6ff89e583258a7f8e7adeeeaeae8611bf` | `libxev/LICENSE` (MIT) |
| zig-objc `c8de82ff80281215ad92900866dab7103a8efa8b` | `zig-objc/LICENSE` (MIT) |
| zf `c35c421f84895193246db06c40683c1a30e616ef` | `zf/LICENSE` (MIT) |
| libvaxis `1dbbe575dff4586fe51e3217aa5c3fecdcbb6089` | `libvaxis/LICENSE` (MIT) |
| Oniguruma `6.9.9` | `oniguruma/COPYING` (BSD) |
| Highway `66486a10623fa0d72fe91260f96c892e41aceb06` | `highway/LICENSE` |
| simdutf `5.2.8` | `simdutf/LICENSE-MIT` (MIT option) |
| Wuffs `7411f488fe2e2c205c3d3b3d28638b7356522930` | `wuffs/LICENSE` |
| stb headers bundled in pinned Ghostty | `stb/*.LICENSE.txt` (verbatim embedded terms; MIT option) |
| FreeType `2.13.2` | `FreeType/FTL.TXT` (FreeType License option) |
| libpng `1.6.43` | `libpng/LICENSE` |
| zlib `1.3.1` | `zlib/LICENSE` |
| Zig `0.16.0` | `Zig/LICENSE` (compiler/runtime notices) |
| GNU gettext `0.24`, libintl runtime | `gettext/COPYING.LIB` (GNU LGPL 2.1 or later) |

**FreeType acknowledgment:** Portions of this software are copyright © 2023
The FreeType Project (www.freetype.org). All rights reserved.

Nerd Fonts glyph-source attribution is preserved in
`NerdFontsSymbolsOnly/glyphs/README.md` (upstream's glyph-set/source table), with
full files under `NerdFontsSymbolsOnly/glyphs/`:
`codicons/LICENSE.txt`, `font-awesome/LICENSE.txt`, `materialdesign/LICENSE`,
`octicons/LICENSE`, `pomicons/LICENSE`, `powerline-extra/LICENSE`,
`powerline-symbols/LICENSE.txt`, and `weather-icons/OFL.txt`.
These include font, artwork and attribution terms distinct from software MIT
terms. The original font names and copyright notices are preserved; modified
fonts must follow the applicable reserved-name and other license conditions.

## Source availability and relinking

The release at <https://github.com/taotao7/PinTerm/releases/tag/v0.4.2> supplies
`PinTerm-0.4.2-ThirdPartySources.tar.gz` alongside the binary. It contains the
exact Ghostty and wrapper source archives (including wrapper patches and build
scripts), GNU gettext 0.24, z2d's MPL-covered source, MSDisplayLink, these notices,
full license texts, source URLs/checksums, and rebuilding instructions.
PinTerm's MIT application source is available at the same release tag.

Source is supplied so recipients can rebuild and relink PinTerm with modified
libraries, including gettext/libintl, for their own use. PinTerm imposes no
anti-debugging or reverse-engineering restrictions on that work. The application
source and wrapper can be recompiled, rather than relying on replacement of a
statically linked library in the distributed executable. See
[`docs/REBUILDING.md`](docs/REBUILDING.md) for the local SwiftPM replacement and
native build procedure. z2d source and any modifications to MPL-covered files
remain available under MPL 2.0, not relicensed as MIT.

The source bundle includes upstream files not installed in PinTerm (including
upstream shell integrations with their own licenses); those files retain the
notices in their source archives. PinTerm uses the wrapper's MIT shell-integration
rewrites, not Ghostty's upstream GPL shell-integration files.

Both the source asset and MIT application source are distributed with this
release. The native source rebuild instructions are documented separately from
the application's build/test verification; see their verification status in
`docs/REBUILDING.md`.
