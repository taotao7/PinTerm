# Rebuilding and relinking PinTerm 0.3.0

This is the source-based replacement route for the statically linked
Ghostty/gettext libraries. PinTerm's application source is MIT. You may modify,
debug, reverse engineer for debugging modifications, rebuild and relink it with
modified libraries for your own use; PinTerm adds no restriction against doing
so. Third-party source remains subject to its accompanying licenses.

## Inputs

Download the app source for tag `v0.3.0` and
`PinTerm-0.3.0-ThirdPartySources.tar.gz` from
<https://github.com/taotao7/PinTerm/releases/tag/v0.3.0>.
The latter contains these unmodified upstream archives, plus all wrapper patches:

- Ghostty `c4e16970a803b170e352432424f44192cb59f3ac`
- libghostty-spm `733ae3b29d447b6707cbfc00879027a076dfd0eb` (`1.5.20260906`)
- gettext `0.24` (including `gettext-runtime/intl`)
- z2d `7dbae85c81784dba9988320bf9543ed9a81350c8`
- MSDisplayLink `87eb0af130744c8cbe2e31b6e1a5bcd659f1c220` (`2.2.0`)

Verify the outer archive against the release checksum, then extract it and run
`shasum -a 256 -c SHA256SUMS` inside its top-level directory. All source download
URLs are recorded in its `SOURCES.tsv`. License checksums have their own manifest
inside `Licenses/`. This is not a fully offline toolchain bundle: Apple SDKs,
Zig and remaining dependencies are fetched separately using the supplied pinned
`build.zig.zon` manifests. Internet access is required for a fresh build.

## Tools and separate working directories

Use macOS with full Xcode, its command-line tools and macOS SDK, Swift 6 or newer,
Zig **0.16.0**, Git, zsh/bash, Perl, curl, tar, zip and the Apple `lipo`/`libtool`
tools. Select Xcode with `xcode-select` and accept its license. With Xcode 27,
install the Metal toolchain using `xcodebuild -downloadComponent MetalToolchain`.
The pinned wrapper CI uses Zig 0.16.0; do not follow its older prose mentioning
0.15.2. Check `zig version`, `swift --version`, and `xcodebuild -version`.

Do all the following in **new working copies**, not an installed app, Homebrew
Cellar, or the original release checkout. Example, from the extracted bundle:

```sh
mkdir -p ../pinterm-rebuild/{ghostty,libghostty-spm,gettext,z2d,MSDisplayLink}
WORK="$(cd ../pinterm-rebuild && pwd)"
tar -xzf sources/ghostty-c4e16970a803b170e352432424f44192cb59f3ac.tar.gz -C "$WORK/ghostty" --strip-components=1
tar -xzf sources/libghostty-spm-733ae3b29d447b6707cbfc00879027a076dfd0eb.tar.gz -C "$WORK/libghostty-spm" --strip-components=1
tar -xzf sources/gettext-0.24.tar.gz -C "$WORK/gettext" --strip-components=1
tar -xzf sources/z2d-7dbae85c81784dba9988320bf9543ed9a81350c8.tar.gz -C "$WORK/z2d" --strip-components=1
tar -xzf sources/MSDisplayLink-2.2.0.tar.gz -C "$WORK/MSDisplayLink" --strip-components=1
git clone --branch v0.3.0 https://github.com/taotao7/PinTerm.git "$WORK/PinTerm"
```

The archives include the wrapper's hidden `.root` marker. Keep it. Initialize
the Ghostty working tree with `git -C "$WORK/ghostty" init` so Git-based patch
application has a repository; do not pass `--ref` to the wrapper with this
tarball-derived source (there is no upstream Git history to check out).

## Rebuild the native library, with modifications if desired

First, an unmodified baseline can be built with:

```sh
"$WORK/libghostty-spm/build.sh" --platforms macos --source "$WORK/ghostty" --skip-tests
```

This automatically applies `Patches/ghostty/` using `Script/apply-patches.sh`,
fetches pinned Zig packages, builds both `aarch64-macos` and `x86_64-macos`, merges
them, and writes `libghostty-spm/BinaryTarget/GhosttyKit.xcframework` and
`libghostty-spm/build/GhosttyKit.xcframework.zip`. `--skip-tests` avoids the
wrapper's multi-platform test matrix when only macOS slices were requested; it
does not omit compilation. Native flags are in `Script/build-ghostty.sh`:
`ReleaseFast`, `app-runtime=none`, no executable, docs, Sentry, custom shaders or
inspector. `Script/build-platform.sh` defines the architecture matrix.

To modify gettext, edit the extracted `$WORK/gettext/gettext-runtime/intl/`
sources. In **the separate Ghostty copy**, inspect `pkg/libintl/build.zig.zon`
and replace the source dependency's `.url` and `.hash` fields with one
`.path = "../../../gettext"` field, preserving the dependency name and other
fields. This relative path is from `ghostty/pkg/libintl` to the extracted gettext
root. Ghostty's `pkg/libintl/build.zig` builds the runtime from those sources;
you do not replace it with a separately configured system gettext installation.

Likewise, for modified z2d change the `.z2d` entry in Ghostty's root
`build.zig.zon` from `.url`/`.hash` to `.path = "../z2d"`. Leave its other fields
intact. You can modify Ghostty itself in this copy too. Preserve/reapply the
wrapper patch stack, and review patch conflicts rather than discarding changes.
Keep modifications to MPL-covered files available under MPL when distributing.

For a modified build, force clean caches (the wrapper's stamp does not hash all
local dependency source edits), then repeat the native build:

```sh
GHOSTTY_FORCE_CLEAN=1 "$WORK/libghostty-spm/build.sh" --platforms macos --source "$WORK/ghostty" --skip-tests
```

## Make SwiftPM consume the rebuilt library and relink PinTerm

In the separate wrapper working copy:

```sh
cp "$WORK/libghostty-spm/Package.local.swift" "$WORK/libghostty-spm/Package.swift"
```

This changes `libghostty` from a remote ZIP/checksum binary target to the local
`BinaryTarget/GhosttyKit.xcframework`. Do not just change the remote checksum;
that would still download the original library.

In that wrapper's `Package.swift`, replace the MSDisplayLink remote `.package`
declaration with `.package(path: "../MSDisplayLink")` to use the supplied exact
Swift dependency. In the separate PinTerm `Package.swift`, replace its
libghostty-spm remote `.package` declaration with
`.package(path: "../libghostty-spm")`. Keep the directory name `libghostty-spm`
so `.product(name: "GhosttyTerminal", package: "libghostty-spm")` still resolves.
These are local development edits, not changes to the released manifests.

```sh
swift package --package-path "$WORK/PinTerm" reset
swift build --package-path "$WORK/PinTerm" -c release
swift test --package-path "$WORK/PinTerm"
bash "$WORK/PinTerm/Scripts/build-app.sh"
```

The last command packages the executable, Swift resource bundles, icon and
notices into `PinTerm/dist/PinTerm.app`, and signs it ad hoc. It adapts SwiftPM's
generated `resource_bundle_accessor.swift` to use `Bundle.main.resourceURL`
instead of `bundleURL`, then recompiles. This keeps resources in the signed
app's `Contents/Resources` rather than relying on the developer's build directory;
the dependency checkout is unchanged. Verify the packaged result with
`PinTerm.app/Contents/MacOS/PinTerm --verify-resources` (no shell is launched).
If Gatekeeper
requires a decision, use macOS's supported local-app approval flow. No original
developer signing key is required for a locally rebuilt app. Launch your new
copy rather than the Homebrew-installed binary. Verify a deliberate observable
library change and inspect the linked binary with `nm`; merely building a new
XCFramework without rebuilding PinTerm does not replace static code.

## Release verification status and distribution requirements

These commands were derived from the exact wrapper build scripts and manifests;
the full native rebuild and modified-library relink have **not** been executed
as part of collecting these materials. Application builds and tests use the
pinned upstream XCFramework; that does not establish bit-for-bit reproduction
of the native library. SDK/compiler differences can change output.
The release maintainer must publish
the app's complete MIT source at `v0.3.0` (including its build scripts), ship the
license directory in the app, and upload the third-party source archive alongside
the binary with equivalent download access. Keep sources available with the
binary; a link to upstream alone is not the supplied source artifact.

To regenerate the notices/source artifact in a release working copy, run
`bash Scripts/collect-third-party.sh`. It downloads only explicit public sources,
never user settings, logs, application state, local Git metadata or build caches.
