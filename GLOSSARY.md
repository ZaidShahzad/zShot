# zShot

zShot is a macOS menu bar app for taking, marking up, and saving screenshots, built to feel instant.

## Capturing

**Screenshot mode**:
The full-screen state zShot enters when the **Capture hotkey** is pressed, where the user picks what to capture and draws on it.
_Avoid_: Capture mode, overlay, editor

**Capture hotkey**:
The global key combination that enters **Screenshot mode** (Cmd+Shift+S by default).
_Avoid_: Shortcut, trigger

**Selection**:
The part of the screen the user has chosen in **Screenshot mode**: a dragged area, a clicked window, or a whole display.
_Avoid_: Region, crop, frame

**Screenshot**:
The finished image of a **Selection** with its **Annotations**, saved to disk and copied to the clipboard.
_Avoid_: Capture, snap, shot, image

## Marking up

**Annotation**:
One mark drawn on a **Selection** with a **Tool**, such as a single arrow or one pen stroke.
_Avoid_: Drawing, shape, markup, layer

**Tool**:
A kind of **Annotation** the user can draw: arrow, line, pen, rectangle, or circle.
_Avoid_: Brush, mode

## After capturing

**Thumbnail**:
The small preview of the latest **Screenshot** that appears in a screen corner for a few seconds and can be dragged into other apps.
_Avoid_: Preview, toast, popup
