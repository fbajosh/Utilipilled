# Releasing Utilipilled

Homebrew distribution uses [fbajosh/homebrew-tools](https://github.com/fbajosh/homebrew-tools), with downloads hosted as immutable versioned [GitHub release assets](https://github.com/fbajosh/Utilipilled/releases). The initial cask supports Apple silicon and macOS 13 or later.

## Build a personal-use release (free)

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Support/Info.plist` for each new published version.
2. Run `./test.sh`, then `./release.sh` on an Apple silicon Mac.
3. Verify the resulting ZIP contains `Utilipilled.app`, the expected version/architecture, and `Contents/Resources/LICENSE`. The checksum file sits beside the ZIP under `dist/`.
4. Commit the source and push it before tagging. Tag the exact source commit (`v<version>`), push that tag, and publish a GitHub release with the app ZIP and its `.sha256` file. Attach release notes stating whether the build is notarized. Do not replace existing versioned assets.
5. Update `version` and `sha256` in the tap's `Casks/utilipilled.rb`. Its URL derives the release tag and versioned filename from that version. Commit and push the tap update.
6. Test `brew install --cask fbajosh/tools/utilipilled` (or `brew upgrade --cask fbajosh/tools/utilipilled` for an existing installation). Open the app, test a camera session, and verify that quit restores alert volume. Test uninstallation when it will not disrupt an installed user's session.

The default build uses an ad-hoc signature. A downloaded copy may be blocked until the user approves it through macOS Privacy & Security. The cask does not remove quarantine, alter Gatekeeper settings, or claim the app is notarized. It is a personal tap, not a submission to Homebrew's official catalog. A failed Gatekeeper audit is expected until a Developer ID signed and notarized build is released.

The cask's `uninstall quit:` requests the app's standard quit path during removal, upgrade and reinstall. The camera module completes restoration before replying. The recovery directory is intentionally excluded from `zap`, and startup at login stays opt-in. If the app cannot quit or restore, resolve that error first; a Brew quit request alone is not an independent guarantee that a damaged app has recovered.

## Optional Developer ID signing and notarization

Apple's Developer Program supplies Developer ID certificates and notarization access. Membership is paid; it is not required for the personal-use path above. See [Apple's program details](https://developer.apple.com/programs/) and [notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

After enrolling, install your **Developer ID Application** certificate and its private key into your own Keychain using Apple's tools. Store notarization credentials with `xcrun notarytool store-credentials` interactively; never put passwords, private keys or tokens in this repository or a release asset.

Run in a shell where the certificate is available:

```sh
export JOSHTOOLS_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export JOSHTOOLS_NOTARY_PROFILE='your-keychain-profile'
./release.sh
```

`build.sh` enables hardened runtime and a secure timestamp for a non-ad-hoc identity. `release.sh` submits the ZIP to Apple, waits for acceptance, staples and validates the ticket, then repackages and checksums the stapled app. A failed command stops the release script. An ad-hoc identity with a notarization profile is rejected before building. Signing without a notary profile does not by itself imply notarization.

Before publishing a signed release, verify with `codesign --verify --strict` and `spctl --assess --type execute`, then test the downloaded/quarantined app, camera quieting, its child watchdog, login registration, upgrade and recovery. Verify the signed and notarized distribution before publishing it.

## Intel builds

`release.sh` names the archive for the native binary architecture. The app's source can be built on Intel, but the first cask deliberately declares `depends_on arch: :arm64`. Validate an Intel build and its runtime behavior before adding architecture-specific URLs/checksums to the cask.
