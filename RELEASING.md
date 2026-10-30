# Releasing Utilipilled

Homebrew distribution uses [fbajosh/homebrew-tools](https://github.com/fbajosh/homebrew-tools), with downloads hosted as immutable versioned [GitHub release assets](https://github.com/fbajosh/Utilipilled/releases). The initial cask supports Apple silicon and macOS 13 or later.

## Publish with GitHub Actions (free)

Pull requests run the automated tests and build the app. When a PR merges into `main`, a newer app version automatically creates its tag, publishes the release, and updates Homebrew after the tests and package checks pass.

1. Set `CFBundleShortVersionString` to the new stable version and increment `CFBundleVersion` in `Support/Info.plist` as part of the PR.
2. Merge the reviewed PR and follow **Build and release** in the Actions tab. No Terminal commands or manual tags are needed.

Merges with the same version as the latest release run checks without publishing. Older versions are rejected. Manual version-tag pushes still work, with the same source and version checks. An existing tag must identify the exact checked commit; it is never moved.

The workflow tests and builds on a standard Apple silicon macOS runner, verifies the packaged signature, architecture, icon, license, metadata and checksum, then creates the tag and publishes the ZIP and checksum to GitHub Releases in the same run. Release notes include the merged changes and state that the build is ad-hoc signed and not notarized.

After publication, a separate job updates the version and checksum in the Homebrew tap. It refuses downgrades or changed bytes for an existing version. Standard runners are free for this public repository. Preview app packages from PR builds are retained in Actions for one day; no Actions caches are used.

### Homebrew access

The `HOMEBREW_TAP_SSH_KEY` Actions secret in this repository holds a dedicated SSH private key. Its public key must be registered as a write-enabled deploy key on `fbajosh/homebrew-tools`. It grants access to that tap only and is used exclusively by the Homebrew update job, after the release succeeds. The app build and pull-request checks do not receive it.

To replace it, generate a dedicated Ed25519 key, add its public key in the tap's **Settings > Deploy keys** with write access, and save the private key as `HOMEBREW_TAP_SSH_KEY` under this repository's **Settings > Secrets and variables > Actions**. Remove the old deploy key after the replacement works. Never commit the private key or reuse a personal SSH key.

### Failed runs

Use **Re-run failed jobs** in Actions. If only Homebrew failed, this retries that update using the original published checksum. Published release assets are never overwritten. If publication left an unpublished draft, inspect and delete only that draft before retrying the failed release job; keep the version tag. For a manual Homebrew repair, copy the version and checksum from the published release into `Casks/utilipilled.rb` in the tap.

Test the built app on a real Mac before merging a version bump when changing camera detection, alert control, login or recovery. The automated build does not exercise physical camera sessions or real alert-volume changes.

## Build and publish manually

For a manual release, disable **Build and release** in Actions before merging the version bump or pushing the tag, and re-enable it afterward. This also applies to Developer ID signed releases; the automated path currently builds ad-hoc signed releases.

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
