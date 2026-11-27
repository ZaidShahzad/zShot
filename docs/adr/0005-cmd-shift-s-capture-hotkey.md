# Cmd+Shift+S is the Capture hotkey, taking it over from apps

The default Capture hotkey is Cmd+Shift+S, the project owner's long-standing habit. Many apps use Cmd+Shift+S for "Save As", and a global hotkey takes it over in every app. Listening for left Shift only would have kept right Shift free for apps, but that needs the Accessibility permission and a keyboard event tap, so zShot uses the standard hotkey API and accepts the takeover. The hotkey can be changed in settings.

## Considered Options

- Cmd+Shift+1: free in macOS, but not the owner's habit.
- Cmd+Shift+3/4/5: already used by macOS's built-in screenshots.
