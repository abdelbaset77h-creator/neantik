# Building the unlimited-profiles NeAntik

This checkout contains one change versus upstream `AffPapa/neantik`
(commit `7a18cad`): profile limits raised so accounts/profiles are
practically unlimited.

## What was changed

| Limit | Upstream | Here |
| --- | --- | --- |
| Stored profiles (`ProfileStorageLimits.maximumProfileCount`) | 10,000 | 1,000,000 |
| Bulk proxy import per run (`BulkProxyImportParser.maximumEntries`) | 100 | 10,000 |
| Proxy-list input size (`maximumInputBytes`) | 512 KiB | 16 MiB |

The fingerprint-seed space (~195M unique seeds over 11 device tuples)
is far above the new 1M storage cap, so nothing else gates creation.
`ProfileStore` now takes an injectable `maximumProfileCount` so tests
can exercise the capacity path quickly; production builds keep the
1,000,000 default.

Repeat a 10,000-profile bulk import as many times as needed — the
storage cap is the only ceiling.

## Where installers can be built

NeAntik is macOS 14+ / Apple Silicon only. The manager is SwiftUI and
the bundled Chromium runtime is built for macOS ARM64. There is no
Windows/Linux code in this project; a Windows build would be a port,
not a build.

### macOS DMG/ZIP (real release)

On an Apple Silicon Mac (M1–M4), macOS 14+, Xcode 16 with the Metal
toolchain, ~120 GB free disk:

1. Copy or clone this checkout to that machine.
2. Build the patched Chromium runtime (6–12 h, one time):

   ```sh
   scripts/build-runtime.sh /absolute/path/to/neantik-chromium-152
   ```

3. For a signed + notarized public-style release you need an Apple
   Developer ID ($99/yr) and a provisioning profile allowing Keychain
   Sharing for `app.neantik.desktop`:

   ```sh
   NEANTIK_PROVISIONING_PROFILE=/absolute/path/to/profile.provisionprofile \
     ./Release-NeAntik.command
   ```

   Output: `dist/NeAntik-<version>-arm64-notarized.zip` and `.dmg`.

4. For personal use without an Apple Developer account, build the
   isolated development app instead (unsigned; right-click → Open on
   first launch):

   ```sh
   ./Develop-NeAntik.command
   ```

### Windows

Not possible from this codebase. The manager would have to be
rewritten (e.g. WinUI 3 / Qt) and the Chromium patchset rebuilt for
Windows — a separate product effort. The upstream README explicitly
lists Windows as out of scope.
