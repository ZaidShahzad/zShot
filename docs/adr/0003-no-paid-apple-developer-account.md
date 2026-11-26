# Free signing, no paid Apple Developer account

zShot is shipped as a free download from GitHub Releases without a paid Apple Developer account, so builds are not notarized. People who download it have to allow it once in System Settings > Privacy & Security, and the release notes explain how. For development, builds are signed with a self-signed certificate from Keychain so macOS keeps the Screen Recording permission between rebuilds instead of asking again every time.

## Considered Options

- Paid account with notarization: no warning on first open, but costs $99 a year. Rejected by the project owner.
