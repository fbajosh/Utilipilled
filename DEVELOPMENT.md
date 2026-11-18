# Development

## Build and test

Install full Xcode 26 or later and select it as the active developer tools, then run:

```sh
./build.sh
./test.sh
```

The app bundle is written to `dist/Utilipilled.app`; build caches stay in `.build`. There are no package dependencies. The standalone Swift test runner does not require XCTest.

`Support/AppIcon.icon` is the editable Icon Composer source. The build compiles it into `Assets.car` for layered icons and an `AppIcon.icns` fallback for older macOS versions. Building the complete app requires Xcode's asset compiler; `./test.sh` also works with Command Line Tools alone. PR builds provide a preview app ZIP in Actions, retained for one day.

`Support/MenuBar.xcassets` contains the supplied, modified on/off SVG artwork. The same asset compiler bundles these as vector template images so AppKit can tint them for light and dark menu bars. The status item always opens the menu; only menu commands change pill state.

CaffeinePilled holds a `PreventUserIdleDisplaySleep` IOKit assertion while enabled. This also prevents idle system sleep. The pill saves the selected duration and active session. Timed sessions use both a native assertion timeout and a main-run-loop timer; relaunch retains the deadline. Until-restart sessions are tied to the kernel boot-session UUID. Normal exit releases the assertion, and macOS releases it if the process crashes. It does not write power preferences or simulate input.

Additional tests that do not change audio:

```sh
python3 Support/test_live_harness.py
python3 Support/test_update_cask.py
python3 Support/test_release_plan.py
python3 Support/check_guardian.py
```

`check_guardian.py` reads alert volume and checks the helper protocol without sending a valid volume-write command. It needs access to the macOS audio service.

## Diagnostics

Print camera activity and audio settings without changing them:

```sh
dist/Utilipilled.app/Contents/MacOS/Utilipilled --probe
```

## Live audio tests

Quit Utilipilled and set Alert volume above zero, then run:

```sh
python3 Support/check_live.py
```

This temporarily changes real system alert volume and exercises normal restoration, parent/helper crashes, user overrides, duplicate instances and interrupted writes. It refuses to run while another instance owns the production lock or unresolved recovery exists. Results are written to an ignored local `LIVE-VALIDATION.json`.

For a short exercise:

```sh
dist/Utilipilled.app/Contents/MacOS/Utilipilled --exercise-session 5
```

This simulates a five-second camera session using real alert-volume control. It does not open a camera.

## Recovery state

The camera pill retains `~/Library/Application Support/CameraQuiet/` for compatibility with earlier app names. `recovery.json` stores the previous alert volume; `instance.lock` and `guardian.lock` coordinate app/helper ownership.

Do not delete an unresolved recovery record or bypass an active lock. For a malformed record, set Alert volume manually, quit the app, move the malformed record aside, then reopen.

`--state-dir PATH` supplies an isolated directory for development. System alert volume remains shared across the login session: never run competing volume-controlling instances with different state directories.

Changes to an already-zero alert setting cannot be detected, and external changes cannot be made atomic with Apple's scripting interface. The explicit restore command handles manual overrides. Recovery may require a later launch or manual adjustment if both processes disappear or the audio service remains unavailable.

## Preview locally before pushing

With Utilipilled already installed in Applications, run:

```sh
./preview.sh
```

This rebuilds the current Swift source, reuses the installed app's compiled artwork, signs the preview, quits the installed app normally, replaces it, and reopens it. The previous app is retained under `.build/preview-backup-*`. It does not commit, push, tag, or publish anything. Future Homebrew upgrades can replace this local preview.

This path works with Command Line Tools alone for code and menu changes. To preview artwork changes, install full Xcode and use `./build.sh` to compile the icon assets. `./build.sh --preview` builds a preview in `dist` without installing it.

## PowerYeeted

IOKit power-source run-loop notifications trigger a serialized background update; there is no battery polling timer. Only the internal battery is considered. Charging means the battery's `Is Charging` value, including the distinction between charging and merely being plugged in.

The pill uses `defaults -currentHost` for Control Center's `BatteryShowPercentage` boolean and `Battery` icon setting (2 shown, 8 hidden on the verified target Mac). It compares effective visibility before writing. Original values, including absent keys, are saved before mutation and retained on failure. Disable and normal quit restore them; relaunch reuses pending recovery state. Other Control Center preferences are untouched.

`Support/check_percentage_hider.swift`, run by `test.sh`, tests thresholds, charging modes, target switching, write deduplication, original-setting restoration and write/restore failures using isolated preferences and fake native writes.


## SwitcherMogged

The native Swift/AppKit implementation lives in `Sources/Utilipilled/Pills/SwitcherHider`. It uses a process-owned session event tap without writing system shortcut preferences. Registry updates, icon loading and persistence run outside the keyboard callback; rendering and activation are deferred onto the main run loop. MRU and switching-session state are separate so excluded applications retain their activation history.

Preferences: `switcherHider.enabled` (false by default) and `switcherHider.excludedApps` (JSON-encoded records with bundle identifier, display name and last known URL). Application history remains in memory. Normal quit/sleep tears down interception while retaining the requested enabled preference; interception failures clear it. No watchdog is needed to undo saved shortcut state because none is changed.

`Support/check_switcher_hider.swift` exercises state, persistence and actual callback routing using synthetic in-process events, without installing a tap or changing user focus. Run it through `./test.sh`. See [the PRD](docs/SWITCHER_HIDER_PRD.md) and [validation status](docs/SWITCHER_HIDER_VALIDATION.md) before enabling the preview or making release claims. The macOS 13 package minimum is unchanged; the preview itself is gated to macOS 26 on Apple silicon.


Build the switcher-only lab with `Support/build_switcher_lab.sh` and open `.build/SwitcherHiderLab.app`. It has isolated preferences and an explicit semantic-event measurement export; it does not initialize the other utilities. Rebuilding the ad-hoc-signed lab may require renewing its Accessibility grant. `Support/check_switcher_integration.sh` performs read-only desktop integration checks with disposable preferences. Native startup ordering and App Exposé interfaces are isolated behind runtime checks in `NativeSwitcherServices.swift`; failure retains the native switcher. The operational pill requires a successful native startup-order seed.

The lab distinguishes API return values from observed frontmost activation. A refusal return is not proof of a failed switch. Its timestamp analyzer reports AppKit submission/workspace-notification latency, not physical input/display latency. See the validation document for the resource sampler, event-tap probe and remaining native-reference requirements.


## Pill display names

Menu names are NotificationRot (CameraQuiet implementation), CaffeinePilled (KeepAwake), PowerYeeted (PercentageHider), SwitcherMogged (SwitcherHider), and ClaudeMaxxing (ClaudeTarget). These are presentation names; preference keys, recovery directories, bundle identity, and implementation folders remain stable. App-level types and source organization use Pill/Pills terminology.
