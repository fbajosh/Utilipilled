# Utilipilled

Utilipilled is a macOS menu-bar app for small utilities. Its first module, **Camera Quiet**, silences alert sounds while a camera is in use and restores them afterward.

Notification banners and badges stay visible. Call and media volume are unchanged. Camera Quiet controls **system alert volume**, so alerts from other apps are silenced too; sounds played as ordinary media may still be audible.

## About Camera Quiet

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

Open Utilipilled once. Camera Quiet is enabled by default and runs in the background.

- The menu-bar icon appears during camera use and hides when all cameras are idle. There is no Dock icon.
- **To find the menu while it's hidden, reopen Utilipilled from Applications or Spotlight.** The icon appears temporarily and the menu opens.
- A crossed-out bell means alert sounds are being suppressed. Allow about two seconds for sounds to return after the last camera stops.

The menu lets you:

- Toggle **Automatic quiet**. Turning it off restores sounds.
- **Restore sounds for this camera session**, restoring your previous setting and pausing suppression until all cameras become idle.
- Enable **Show icon while camera is idle** for easier access.
- Enable **Launch at login** to start automatically.
- **Quit Utilipilled and restore sounds**.

If you manually raise Alert volume during a camera session, Utilipilled keeps your new setting for that session. Use the menu's restore command for an explicit override.

## If sounds don't return

A separate helper attempts to restore alert volume if the app crashes. If alerts remain silent:

1. Reopen Utilipilled, then choose **Quit Utilipilled and restore sounds**.
2. Or adjust **System Settings → Sound → Alert volume** manually.

You can also quit the app and retry recovery from Terminal:

```sh
/Applications/Utilipilled.app/Contents/MacOS/Utilipilled --recover
```

If both the app and helper are killed, reopening the app retries recovery. An error keeps the menu-bar icon visible.

## Limitations and privacy

Camera detection depends on the device driver. External or virtual cameras may report activity differently; screen sharing alone does not trigger quieting. Test the cameras, notification tones and audio routes you use, since some sounds bypass system alert volume.

The app does not capture camera frames, record audio, read Messages data, or connect to the network. It does not request Camera, Microphone, Accessibility, Screen Recording, Full Disk Access, notification or administrator permissions. It doesn't even collect usage information, and it has no method to communicate anything back.

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
