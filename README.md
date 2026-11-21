# Utilipilled

Utilipilled is a macOS menu-bar app for small utilities. **NotificationRot** silences alert sounds while a camera is in use and restores them afterward. **CaffeinePilled** keeps the screen and Mac awake until you turn it off or quit.

Notification banners and badges stay visible. Call and media volume are unchanged. NotificationRot controls **system alert volume**, so alerts from other apps are silenced too; sounds played as ordinary media may still be audible.

## About NotificationRot

Finally, you can text people while you're on a meeting without that annoying chime. No longer do your coworkers know that you're talking behind their backs about that ridiculous thing they just said. Your face probably gave it away anyhow, but at least we don't have audio evidence. 

And sure, you could just set up a focus mode. But when you accidentally miss a notification because of an overaggressive focus mode and blind trust in Apple's "notification prioritization", this repo will still be up and will still love you. And you will love it, because it only mutes the sounds of system notifications when your camera is detected as on. It doesn't block the pop-up, so you can still read the notification quietly, and it's all automatic. 

## Install

Requires macOS 13 or later. Downloads support Apple silicon; Intel builds are unverified.

```sh
brew install --cask fbajosh/tools/utilipilled
open -a Utilipilled
```

Or download the ZIP from [Releases](https://github.com/fbajosh/Utilipilled/releases/latest), unzip it, and drag Utilipilled.app into Applications.

The current release isn't notarized by Apple. If macOS blocks it, attempt to open the app, then use **System Settings → Privacy & Security → Open Anyway**, if offered.

## Use

Open Utilipilled once. NotificationRot is enabled by default and runs in the background.

- The menu-bar icon stays visible. Clicking it opens the menu; it does not toggle either pill. There is no Dock icon.
- The **on** artwork appears while CaffeinePilled or SwitcherMogged is enabled, NotificationRot is suppressing alert sounds, or PowerYeeted is hiding a battery item. The menu shows each pill's status.
- Allow about two seconds for alert sounds to return after the last camera stops.

The menu groups NotificationRot, CaffeinePilled, PowerYeeted, SwitcherMogged, and app settings under section headings. **Scope: all system alerts…** opens macOS Sound settings.

The menu lets you:

- Use **Enable / Disable** under **CaffeinePilled**, then choose **Duration**: 30 min, 12 hours, Until restart, or Indefinitely.
- Use **Enable / Disable** under **NotificationRot**. Disabling it restores sounds.
- **Restore sounds for this camera session**, restoring your previous setting and pausing suppression until all cameras become idle.
- Enable **Launch at login** to start automatically.
- Open **About Utilipilled…** for version information and icon credits.
- **Quit Utilipilled**.

If you manually raise Alert volume during a camera session, Utilipilled keeps your new setting for that session. Use the menu's restore command for an explicit override.

Timed sessions retain their original deadline when you relaunch the app. **Until restart** resumes on relaunch during the same Mac boot; **Indefinitely** also resumes after a Mac restart when Utilipilled launches. Quitting releases sleep prevention; reopening resumes an unexpired session. Disabling CaffeinePilled cancels the session.

CaffeinePilled prevents idle display and system sleep without changing your saved sleep settings. Normal sleep behavior returns when you turn it off, quit, or the app crashes. Closing the lid, choosing Sleep manually, and low-battery sleep still take precedence. It does not simulate mouse activity or override screen-lock policies.

## PowerYeeted

While enabled, the **Disable** row shows the battery percentage. A bolt indicates active charging, and a plug indicates external power while charging is paused.

Choose **Enable** in the PowerYeeted section to control the native battery display. Its Threshold submenu has three independent choices:

- **100%, 90%, or 80%:** hide at or above the selected level.
- **When charging or Always:** apply the threshold only during actual charging, or regardless of charging state.
- **Battery, Percentage, or Both:** choose which native menu-bar items to hide.

Defaults are Disabled, 90%, Always, and Percentage. The icon stays inactive for this pill unless it is actually hiding something. Battery changes are handled through system notifications. Switching targets restores the setting no longer controlled; disabling or quitting restores your original settings. Settings and recovery state survive relaunches.

## SwitcherMogged (development preview)

**SwitcherMogged → Hide apps** lets you choose applications to hide or deprioritize in the replacement Command-Tab switcher. Checkmarks identify those apps. The submenu has three labeled sections: **Running**, **Not running**, and **Show hidden apps**. Exclusions can be edited while disabled and survive relaunches. Messages and third-party apps use the same bundle-identifier preferences; their files and activation policies are untouched.

**Show hidden apps** offers **Always**, **At end of first cycle**, **After start of second cycle**, **At end of second cycle**, and **Never** (the default). **Always** shows every running app immediately, with your primary apps first and the checked apps grouped at the end. Each group retains its recent-use order, so even a recently used checked app cannot get between your primary apps. A quick switch from a checked app returns to the primary group. **After start of second cycle** wraps selection back normally at the end of the first cycle and reveals hidden apps on the following advancement. The two end-of-cycle choices reveal immediately at their respective boundaries. Hidden apps appear after the visible group, and selection enters the revealed group. For the cycle-based choices, releasing Command or cancelling hides them again and resets the count. Completed cycles count in either direction; reversing partway through a cycle backtracks. The setting survives relaunches. If every running app is hidden, a configured reveal opens the hidden group immediately because there is no visible cycle to traverse.

The Hide apps row lists running checked apps in the same recent-use order as the switcher. If the full list is too wide, it shows as many leading names as fit with an “& N more” count. If even the first name and count are too wide, it shows only the total. The summary counts running apps only.

The pill is **disabled by default**. The preview supports macOS 26 on Apple silicon. Choose **Enable**, grant Accessibility if requested, then choose **Enable** again. Disabling keeps exclusions. An unavailable or failed keyboard interceptor leaves the native shortcut available, with no saved macOS shortcut changes.

SwitcherMogged is an **opt-in preview**: broader native behavior and performance parity remain unverified. Startup ordering, window overview, Option-release reopening, file/URL drops and spring loading are implemented, with broader native-behavior and failure-recovery testing still pending. The live feasibility test on the target Mac showed only the replacement switcher. See [validation status and release blockers](docs/SWITCHER_HIDER_VALIDATION.md).

## ClaudeMaxxing

**ClaudeMaxxing** is a read-only weekly usage target, rounded to a whole percent. It resets to 0% every Wednesday at 16:00 UTC (11am at fixed UTC-5), independent of your timezone and daylight savings.

## If sounds don't return

A separate helper attempts to restore alert volume if the app crashes. If alerts remain silent:

1. Reopen Utilipilled, then choose **Quit Utilipilled**.
2. Or adjust **System Settings → Sound → Alert volume** manually.

You can also quit the app and retry recovery from Terminal:

```sh
/Applications/Utilipilled.app/Contents/MacOS/Utilipilled --recover
```

If both the app and helper are killed, reopening the app retries recovery. An error keeps the menu-bar icon visible.

## Limitations and privacy

Camera detection depends on the device driver. External or virtual cameras may report activity differently; screen sharing alone does not trigger quieting. Test the cameras, notification tones and audio routes you use, since some sounds bypass system alert volume.

The app does not capture camera frames, record audio, read Messages data, or connect to the network. SwitcherMogged requests Accessibility only when you explicitly enable it; unrelated keyboard input is not stored or logged. The other pills do not need Accessibility. The app does not request Camera, Microphone, Screen Recording, Full Disk Access, notification or administrator permissions. It doesn't even collect usage information, and it has no method to communicate anything back.

## Update or uninstall

```sh
brew upgrade --cask fbajosh/tools/utilipilled
```

```sh
brew uninstall --cask fbajosh/tools/utilipilled
```

Disable **Launch at login** before uninstalling. Upgrades and removal request a normal quit so sounds can be restored. Recovery files are preserved; resolve any reported recovery error before removing them.

Existing `joshtools` installations migrate through the same Homebrew tap. Replace any old JoshTools Login Item with Utilipilled's login setting.

## Build from source

With full Xcode 26 or later installed and selected as the active developer tools:

```sh
./build.sh
./test.sh
open dist/Utilipilled.app
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for diagnostics and integration tests, and [RELEASING.md](RELEASING.md) for packaging and signing.
