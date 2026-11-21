# Utilipilled

Utilipilled is a macOS menu-bar app for small utilities. Its pills quiet alerts during calls, keep your Mac awake, manage the battery display, and customize Command-Tab. The menu also shows how far you are into Claude's weekly usage window.

## Install

Requires macOS 13 or later and an Apple silicon Mac. SwitcherMogged is an opt-in preview for macOS 26.

```sh
brew install --cask fbajosh/tools/utilipilled
open -a Utilipilled
```

You can also download the ZIP, unzip it, and drag `Utilipilled.app` into Applications. [Download the latest release](https://github.com/fbajosh/Utilipilled/releases/latest).

The release isn't notarized by Apple. If macOS blocks it, try opening the app, then look for **Open Anyway** in **System Settings → Privacy & Security**.

## Use the menu

Open Utilipilled and click its menu-bar icon. The icon stays visible while the app runs, and the app has no Dock icon. Use **Launch at login** to start it automatically, **About Utilipilled…** for the version and icon credits, and **Quit Utilipilled** to close it.

The icon switches to its active artwork when NotificationRot is suppressing alerts, CaffeinePilled or SwitcherMogged is enabled, or PowerYeeted is hiding a battery item.

### NotificationRot

NotificationRot is enabled by default. It mutes **system alert volume** while a camera is active and restores your previous setting about two seconds after the last camera stops. Notification banners and badges stay visible. Call and media volume are unchanged.

- **Disable** restores sounds and turns off automatic quieting.
- **Restore sounds for this camera session** restores alert volume and pauses quieting until all cameras are idle. If you raise alert volume yourself during a session, Utilipilled keeps your new setting for that session.
- **Scope: all system alerts…** opens macOS Sound settings.

Camera detection depends on the driver, so external and virtual cameras may behave differently. Screen sharing alone doesn't trigger quieting. Apps that play alerts as media can still make sound.

#### About NotificationRot

Finally, you can text people while you're on a meeting without that annoying chime. No longer do your coworkers know that you're talking behind their backs about that ridiculous thing they just said. Your face probably gave it away anyhow, but at least we don't have audio evidence.

And sure, you could just set up a focus mode. But when you accidentally miss a notification because of an overaggressive focus mode and blind trust in Apple's "notification prioritization", this repo will still be up and will still love you. And you will love it, because it only mutes the sounds of system notifications when your camera is detected as on. It doesn't block the pop-up, so you can still read the notification quietly, and it's all automatic.

### CaffeinePilled

Choose **Enable** to prevent idle display and system sleep. Use **Duration** to choose **30 min**, **12 hours**, **Until restart**, or **Indefinitely**. **Disable** ends the session.

Quitting releases sleep prevention. Relaunching resumes an unexpired timed session with its original deadline. **Until restart** resumes only during the same Mac boot; **Indefinitely** also resumes when Utilipilled opens after a reboot. Closing the lid, choosing Sleep, low-battery sleep, and screen-lock policies still take precedence.

### PowerYeeted

PowerYeeted frees up space in the macOS menu bar by hiding the battery percentage, battery icon, or both when the battery is at or above a level you choose. It brings them back automatically when the battery drops below that level.

With the default settings, choosing **Enable** hides the percentage at **90% or higher**, leaves the battery icon visible, and brings the percentage back at **89%**. You can check the live percentage anytime in PowerYeeted’s **Disable** row. A bolt means the battery is charging. A plug means the Mac is on external power and the battery is idle.

Set three independent options in the **Threshold** submenu:

| Option | Choices |
| --- | --- |
| Threshold | **100%**, **90%**, or **80%**. Hide at or above that level. |
| When to hide | **When charging** applies the threshold during active charging. **Always** applies it regardless of charging state. |
| What to hide | **Battery**, **Percentage**, or **Both**. |

PowerYeeted starts disabled, with **90%**, **Always**, and **Percentage** selected. Changing what it hides restores the old target's setting. Disabling or quitting restores your original battery display settings.

### SwitcherMogged (preview)

SwitcherMogged replaces Command-Tab so you can hide or deprioritize apps. It's disabled by default and requires macOS 26 on Apple silicon. Choose **Enable**, grant Accessibility if prompted, then choose **Enable** again.

Check apps under **Hide apps → Running** or **Not running**. Your choices persist across relaunches and while SwitcherMogged is disabled. The **Hide apps** row lists checked running apps in switcher order, most recently used first. If the list is too wide, it shows as many names as fit followed by **& N more**, or just the total if no names fit.

Use **Hide apps → Show hidden apps** to choose when checked apps appear:

| Setting | What happens |
| --- | --- |
| **Always** | Checked apps appear at the end from the start. Both groups keep their recent-use order. |
| **At end of first cycle** | Reveal checked apps when you finish cycling through the visible apps once. |
| **After start of second cycle** | Wrap back to the first group, then reveal checked apps on the next advance. |
| **At end of second cycle** | Reveal checked apps after two complete cycles. |
| **Never** (default) | Keep checked apps out of the switcher. |

Cycle counts reset when you release Command or cancel. Either direction counts, and reversing partway through a cycle backtracks. If every running app is checked, any mode that reveals them shows them immediately. If interception can't start or stops working, the native shortcut remains available. Some native behaviors are still being tested. [SwitcherMogged validation status](docs/SWITCHER_HIDER_VALIDATION.md).

### ClaudeMaxxing

ClaudeMaxxing is a weekly clock for pacing Claude usage. It shows the percentage of time elapsed in the usage window, rounded to a whole percent. It resets Wednesday at **16:00 UTC**. The reset is fixed in UTC, so the local time may shift with daylight saving.

## If alert sounds don't return

A separate helper attempts to restore alert volume if the app crashes. If alerts remain silent, reopen Utilipilled and choose **Quit Utilipilled**, or adjust **System Settings → Sound → Alert volume** manually.

You can also quit the app and retry recovery from Terminal:

```sh
/Applications/Utilipilled.app/Contents/MacOS/Utilipilled --recover
```

If both the app and helper are killed, reopening the app retries recovery.

## Privacy and permissions

The app does not capture camera frames, record audio, read Messages data, or connect to the network. SwitcherMogged requests Accessibility only when you explicitly enable it; unrelated keyboard input is not stored or logged. The other pills do not need Accessibility. The app does not request Camera, Microphone, Screen Recording, Full Disk Access, notification or administrator permissions. It doesn't even collect usage information, and it has no method to communicate anything back.

## Update or uninstall

To upgrade a Homebrew installation:

```sh
brew upgrade --cask fbajosh/tools/utilipilled
```

To uninstall, first disable **Launch at login**, then run:

```sh
brew uninstall --cask fbajosh/tools/utilipilled
```

Homebrew requests a normal quit for upgrades and removal so Utilipilled can restore the settings it manages. Recovery files are preserved. Resolve any reported recovery error before removing those files.

Existing `joshtools` installations migrate through the same Homebrew tap. Replace any old JoshTools Login Item with Utilipilled's login setting.

## Build from source

With full Xcode 26 or later installed and selected as the active developer tools:

```sh
./build.sh
./test.sh
open dist/Utilipilled.app
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for diagnostics and integration tests, and [RELEASING.md](RELEASING.md) for packaging, release signing, and stable signing for local previews.
