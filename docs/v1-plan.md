# zShot v1 plan

The first version does a few things and does them instantly. Words in bold are defined in [GLOSSARY.md](../GLOSSARY.md). Why things are built this way is in [docs/adr](./adr).

## Speed targets

These are requirements, and they get measured on a real Mac:

- **Capture hotkey** to crosshair on screen: under 50 ms
- Finishing a **Screenshot** to it being on the clipboard: under 100 ms
- Idle: about 0% CPU and under 50 MB of memory

## Taking a Screenshot

1. Press Cmd+Shift+S (either Shift) to enter **Screenshot mode**.
2. Pick a **Selection**:
   - Drag to select an area. It can span more than one display.
   - Hover over a window to highlight it, and click to select it.
   - Press F to select the whole display under the mouse.
3. A toolbar appears next to the **Selection**. Draw **Annotations** on it.
4. Press Cmd+C or Enter to finish. The **Screenshot** is saved and copied.
5. Press Esc at any time to leave without saving.

Captures are taken at full Retina resolution.

## Drawing

- **Tools**: arrow (A), line (L), pen (P), rectangle (R), circle (O). Nothing else in v1.
- A few preset colors, red by default, and 3 line thicknesses.
- Hold Shift for straight lines, perfect squares, and perfect circles.
- Cmd+Z undoes the last **Annotation**. When none are left, Cmd+Z leaves **Screenshot mode**.
- Cmd+Shift+Z redoes.

## Saving

- Every **Screenshot** is saved right away as a PNG to `~/Pictures/zShot` and copied to the clipboard. Both are on by default and can be turned off in settings.
- File names look like `zShot 2026-11-26 at 16.23.05.png`.
- A **Thumbnail** shows in a screen corner for about 5 seconds. Drag it into another app, or click it to show the file in Finder.

## The app

- Starts at login, lives in the menu bar, and has no Dock icon.
- A small settings window: Capture hotkey, save folder, save and copy on or off, start at login.
- Requires macOS 14 or newer.
- Shipped as a free download from GitHub Releases (see ADR 0003).

## Not in v1

Text, blur, crop after capture, scrolling capture, OCR, screen recording, pinning a Screenshot to the screen, and cloud upload.

## Building and testing

zShot is built, run, and timed against the speed targets on a Mac before each change is shared. There is no CI build.
