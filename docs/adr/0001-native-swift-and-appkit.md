# Native Swift and AppKit, no web runtime

zShot's whole reason to exist is feeling instant, so it is written in Swift on AppKit, with ScreenCaptureKit for grabbing pixels. Electron and Tauri were rejected because they put a browser engine or web view between the hotkey and the screen, which adds startup time, memory, and frame latency you can feel. SwiftUI is allowed only for windows where speed does not matter, such as settings.

## Consequences

- zShot is macOS only. Other platforms would be separate apps, not a port.
- It can only be built and run on a Mac.
