# Update publishing

Dock Enhanced embeds the pinned Sparkle 2.10.0 framework and uses an app-owned English/Chinese user driver. Sparkle handles version selection, stable channels, scheduling, download verification, replacement, and relaunch. Update downloads start only after the user chooses Download and Update.

## Identities

Two independent signing identities are required:

- The persistent self-signed code-signing certificate/private key keeps the application's designated requirement stable.
- The persistent Ed25519 key authenticates the update feed and archives. `updates/config.json` contains only its public key and the HTTPS feed URL. Never put a private key in this file.

Private files are stored outside the repository under `~/Library/Application Support/Dock Enhanced/Signing/` (or `DOCK_ENHANCED_SIGNING_DIR`). Back up this directory privately. The update key also lives in the login keychain under the account `dev.yifeng.DockEnhanced.updates`. A lost key is not safely replaced by generating a new one for existing clients.

For an independent fork, use your own release repository, feed URL, and update key. Do not ship a fork that points at the upstream feed while implying it receives your own releases.

## Initial setup

Resolve the Swift package to obtain Sparkle's pinned release tools:

```sh
swift package resolve
python3 scripts/setup-signing.py
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account dev.yifeng.DockEnhanced.updates
```

If creating your own update channel, copy the resulting public key into `updates/config.json` and set your feed URL/repository. Export the private update key once using `generate_keys --account <account> -x <private-file>` into the private signing directory as `sparkle-update-private-key`, with owner-only file permissions. Never overwrite a good backup casually. Later builds must reuse both identities.

## Release order

1. Set the marketing version and strictly increasing build number in `scripts/build-app.sh`.
2. Run `scripts/build-dmg.sh`. It compiles, copies the framework with symlinks and upstream nested signatures intact, includes its license, and signs the outer app with the fixed local identity. The host does not enable Hardened Runtime/library validation; do not add it without rechecking framework loading and helper signing.
3. Run `python3 scripts/prepare-update.py dist/Dock-Enhanced-VERSION-macOS-arm64.dmg`. It rejects nonnumeric prerelease versions, signs the archive and feed with Sparkle's official tool, and copies the final signed XML into `updates/appcast.xml`. Move an older `dist/appcast` staging directory aside first.
4. Test the new archive, signed feed, old-to-new replacement/relaunch, and a rejected bad signature with isolated fixture apps. Do not test against a user's installed app or reset their privacy permissions. Use an ordinary writable application location. The app only starts its updater when installed in `/Applications` or `~/Applications`. A test in Documents stalled during replacement; its exact underlying cause is unconfirmed, so this is not counted as a passed installation scenario.
5. Commit the code/config/documentation, create a GitHub Release draft for the version, and upload the exact DMG and checksum that were signed. Publish the Release before publishing the new feed so clients cannot see an unavailable archive.
6. Publish the signed `updates/appcast.xml` to the configured HTTPS URL. Do not edit it after signing. Check that its archive URL is downloadable, metadata matches the bundle, and signatures validate. GitHub raw content may be cached briefly.

`SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` are enabled. Checksums are for manual download verification; they do not replace EdDSA authentication. No system profile, usage analytics, window titles, keyboard input, or thumbnails are sent. GitHub/CDN servers necessarily receive the normal network request and source IP.

## Bootstrap and compatibility

Versions through 0.6.6 have no updater. Users must manually install 0.6.7 once; subsequent updater-enabled releases can install in the application. Current official archives are arm64, macOS 14+. Sparkle filters build numbers, system compatibility, hardware requirements, and skipped versions; the app allows only the stable default channel.

The updater preserves the application identity used since 0.6.5. It does not grant Developer ID trust or Apple notarization. Privileged installer prompts follow macOS language and authorization policy even when the app's own update UI uses another language. Changes in OS policy, certificate identity, or user permission settings can still require consent.

## Checks

```sh
swift run --build-system native DockEnhanced --check-application-updates
swift run --build-system native DockEnhanced --check-localization
swift run --build-system native DockEnhanced --check-preview-settings
swift run --build-system native DockCoreChecks
```

The update UI check uses isolated preferences and controlled callbacks. Real install verification also requires a properly launched app/CLI bundle; launching a bare CLI from a noninteractive shell may fail at Authorization Services before reaching signature validation. Signature failures must be verified in full download/install mode, not metadata-only probe mode.
