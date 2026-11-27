# Build and run zShot

zShot builds with Swift Package Manager on a Mac. You need macOS 14 or newer and either Xcode or the Command Line Tools (`xcode-select --install`).

## Build and test

Run these from the repository root:

```sh
swift build
./scripts/test.sh
```

`scripts/test.sh` runs `swift test`. With only the Command Line Tools installed, SwiftPM can't find the Swift Testing framework on its own, so the script adds its path. Arguments pass through to `swift test`, for example `./scripts/test.sh --filter ScreenshotSession`.

## Make the app

`scripts/build-app.sh` builds a release binary and wraps it in `build/zShot.app`:

```sh
./scripts/build-app.sh
open build/zShot.app
```

Pass `debug` as the first argument for a debug build.

zShot appears in the menu bar. It has no Dock icon and no window until you open Settings.

## Keep the Screen Recording permission between rebuilds

macOS ties the Screen Recording permission to the app's code signature. An ad-hoc signature changes on every build, so macOS asks again after each rebuild. To avoid that, create a self-signed signing certificate once:

```sh
./scripts/make-dev-cert.sh
```

The script adds a certificate named `zShot Development` to your login keychain. `build-app.sh` signs with it when it exists and falls back to an ad-hoc signature when it does not. To use a different certificate, set `ZSHOT_SIGN_IDENTITY` to its name.

## Grant permissions

The first time you press the Capture hotkey, macOS asks for Screen Recording permission. Turn on zShot in System Settings > Privacy & Security > Screen & System Audio Recording, then quit and reopen zShot.

zShot does not need the Accessibility permission.

## Check the speed targets

zShot logs how long the hot paths take. Stream the log in a terminal while you take Screenshots:

```sh
log stream --level info --predicate 'subsystem == "io.github.zaidshahzad.zshot"'
```

Each Screenshot logs two lines:

- `hotkey→shown`: time from the Capture hotkey to the Screenshot mode windows on screen. The target is under 50 ms.
- `finish→clipboard`: time from Cmd+C or Enter to the PNG on the clipboard. The target is under 100 ms.

To check idle cost, leave zShot running and watch its CPU and memory in Activity Monitor. The targets are about 0% CPU and under 50 MB.

## Install a downloaded build

Release builds are not notarized (see [ADR 0003](adr/0003-no-paid-apple-developer-account.md)). The first time you open a downloaded copy, macOS blocks it. Open System Settings > Privacy & Security, find the message about zShot, and click Open Anyway.
