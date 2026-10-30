# Development

## Build and test

Install full Xcode 26 or later and select it as the active developer tools, then run:

```sh
./build.sh
./test.sh
```

The app bundle is written to `dist/Utilipilled.app`; build caches stay in `.build`. There are no package dependencies. The standalone Swift test runner does not require XCTest.

`Support/AppIcon.icon` is the editable Icon Composer source. The build compiles it into `Assets.car` for layered icons and an `AppIcon.icns` fallback for older macOS versions. Building the complete app requires Xcode's asset compiler; `./test.sh` also works with Command Line Tools alone. PR builds provide a preview app ZIP in Actions, retained for one day.

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

The camera module retains `~/Library/Application Support/CameraQuiet/` for compatibility with earlier app names. `recovery.json` stores the previous alert volume; `instance.lock` and `guardian.lock` coordinate app/helper ownership.

Do not delete an unresolved recovery record or bypass an active lock. For a malformed record, set Alert volume manually, quit the app, move the malformed record aside, then reopen.

`--state-dir PATH` supplies an isolated directory for development. System alert volume remains shared across the login session: never run competing volume-controlling instances with different state directories.

Changes to an already-zero alert setting cannot be detected, and external changes cannot be made atomic with Apple's scripting interface. The explicit restore command handles manual overrides. Recovery may require a later launch or manual adjustment if both processes disappear or the audio service remains unavailable.
