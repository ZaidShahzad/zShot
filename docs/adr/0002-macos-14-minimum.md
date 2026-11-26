# macOS 14 (Sonoma) is the oldest supported version

ScreenCaptureKit's still-image API (`SCScreenshotManager`) arrived in macOS 14 and is the fastest supported way to capture the screen. Supporting older systems would mean keeping a second, slower capture path built on deprecated APIs, so zShot requires macOS 14 or newer.
