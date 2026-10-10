# Snapwise

Native macOS menu-bar app that combines screenshots and screen recordings (modelled on CleanShot X) with window
snapping (modelled on BetterSnapTool). Formerly named Lumshot; the bundle identifier is unchanged so permissions,
settings and shortcuts carry over.
Swift (AppKit + SwiftUI), ScreenCaptureKit, AVFoundation, Vision. No third-party dependencies.

Website with an intro video: https://capizerbino.github.io/snapwise/ ([Tiếng Việt](https://capizerbino.github.io/snapwise/vi/)).
The video is rendered from `docs/promo/index.html` with `node scripts/render-promo-video.mjs`.

## Requirements

- macOS 15 or later, Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — the `.xcodeproj` is generated, not committed

## Build and run

```bash
./build.sh            # Debug build, prints errors + status
./build.sh Release    # optimized build (use this one day to day: scroll stitching is much faster)
open .derived/Build/Products/Release/Snapwise.app
```

Tests:

```bash
xcodegen generate
xcodebuild -project Snapwise.xcodeproj -scheme Snapwise -derivedDataPath .derived test
```

Signing is set in `project.yml` (`DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY`). A stable signing identity matters:
macOS ties the Screen Recording permission to it, so ad-hoc builds lose the permission on every rebuild.

## Permissions

| Permission | Needed for | Where |
|---|---|---|
| Screen & System Audio Recording | every capture | prompted at first launch; relaunch after granting |
| Accessibility | window snapping, keystroke display, auto-scroll | prompted when the feature is first used |
| Camera / Microphone | camera overlay, mic audio | prompted when the feature is first used |

## Features

**Capture** — area, window, fullscreen, previous area, self-timer, All-In-One (one shortcut, resizable selection
with size fields and aspect lock, remembers the last selection). Crosshair, magnifier, freeze screen, cursor
capture, hide desktop icons. Window shots on transparent, wallpaper, solid or gradient backgrounds with shadow and padding.

**Scrolling capture** — vertical and horizontal, manual or auto-scroll; sticky headers/footers are kept once.

**Recording** — MP4 (H.264) or GIF of an area, window or full screen; FPS, quality and Retina options; computer
audio and microphone; pause/resume; countdown; menu-bar timer (click to stop, right-click for pause/discard);
click highlights, keystroke display, camera bubble.

**Video editor** — trim, landscape/square/vertical canvas, gradient backgrounds with padding and rounded corners,
auto-zoom on recorded clicks, mute, resolution, export to MP4 or GIF. The preview uses the export pipeline.

**Annotate** — arrow (4 styles), rectangle, filled rectangle, ellipse, line, pencil (smoothed), highlighter,
text (7 styles), counter, blur (pixelate / smooth / secure), spotlight, crop (aspect presets), rotate, flip,
resize, combine images by drag-and-drop or paste, saved color palette, undo/redo, editable `.snapwise` project files.
Background tool: 20 gradients, solid color or custom image, padding, corners, shadow, aspect ratio, alignment,
presets, Auto Balance.

**Quick Access Overlay** — thumbnail stack with copy, save, annotate, pin, drag-out as file, swipe to dismiss,
auto-close, restore recently closed, temporarily hide.

**Pin** — float a screenshot above all windows; scroll to resize, ⌥-scroll for opacity, arrow keys to nudge,
lock mode (click-through).

**OCR** — copy text from any area (on-device, automatic language detection); also reads QR codes and barcodes.

**History** — filter by type, restore, copy, save, delete; configurable retention.

**Window snapping** — drag a window to a screen edge (half / maximize) or corner (quarter) with a frosted live
preview; Esc cancels; edges shared by two displays need a short pause. Keyboard shortcuts and menu items for halves,
quarters, thirds, two-thirds, maximize, center, next/previous display and restore; pressing a half shortcut again
cycles ½ → ⅔ → ⅓ and Maximize twice restores. Previous size comes back when a snapped window is dragged away.
Custom snap areas are drawn on a miniature screen and appear as drop zones while dragging. Right-/middle-click
actions on the close, minimize and zoom buttons; hold a modifier to move or resize the window under the pointer;
configurable gap; excluded apps. macOS's own edge tiling conflicts with drag snapping, so Snapwise asks once
whether to turn it off (Settings › Snapping shows the state).

## Default shortcuts

All are editable in Settings › Shortcuts (also reachable from the menu: Customize Shortcuts…). Click a field and
press the keys; assigning a combination that another action uses moves it. "Use ⌘⇧3 / ⌘⇧4 / ⌘⇧5" applies the
macOS-style set — turn off macOS's own screenshot shortcuts in Keyboard Settings first, or the system keeps them.

| Shortcut | Action |
|---|---|
| ⌃⇧1 | All-In-One |
| ⌃⇧2 | Capture text (OCR) |
| ⌃⇧3 | Capture fullscreen |
| ⌃⇧4 | Capture area |
| ⌃⇧5 | Capture window |
| ⌃⇧6 | Scrolling capture |
| ⌃⇧7 | Record video (press again to stop) |
| ⌃⇧8 | Record GIF |
| ⌃⌥← / → / ↑ / ↓ | Snap left / right / top / bottom half |
| ⌃⌥U / I / J / K | Snap top-left / top-right / bottom-left / bottom-right quarter |
| ⌃⌥↩ / C | Maximize / center |
| ⌃⌥D / F / G | Left / center / right third |
| ⌃⌥E / T | Left / right two thirds |
| ⌃⌥⌘← / → | Move to previous / next display |
| ⌃⌥⌫ | Restore the size from before snapping |

While selecting: Space switches between area and window, F or Return captures the full screen, Esc cancels,
Shift constrains to a square.

## URL scheme

```
snapwise://capture-area            snapwise://capture-fullscreen     snapwise://capture-window
snapwise://capture-previous-area   snapwise://self-timer             snapwise://scrolling-capture
snapwise://all-in-one              snapwise://record-screen          snapwise://record-gif
snapwise://capture-text            snapwise://open-history           snapwise://restore-recently-closed
snapwise://open-annotate?filepath=/path/to/image.png                snapwise://pin?filepath=/path/to/image.png
snapwise://toggle-desktop-icons    snapwise://hide-desktop-icons     snapwise://show-desktop-icons
snapwise://open-settings
snapwise://snap-left-half   snapwise://snap-top-right   snapwise://snap-maximize   snapwise://snap-restore   (any `snap-<position>`)
snapwise://capture-area?x=100&y=100&width=800&height=600    (also capture-text, record-screen, record-gif, scrolling-capture)
```

## Not included

- **Cloud** (upload links, comments, teams, transcription): CleanShot Cloud is a hosted service, not app code.
- **Do Not Disturb while recording**: macOS has no public API to switch Focus on.
- **Video editor cursor smoothing, custom cursor rendering and motion blur.**
- Highlighter text-size detection and pixelate randomization.
- From BetterSnapTool: title bar double-click actions, per-app snap sizes, shortcuts for custom snap areas.

## Layout

```
Sources/Snapwise/
  App/          entry point, menu bar, hotkeys, preferences, URL scheme
  Capture/      ScreenCaptureKit service, selection overlay, capture flows, OCR, desktop icons
  Scrolling/    frame stitcher and scrolling session
  PostCapture/  history, quick access overlay, pin windows
  Annotate/     editor model, renderer, canvas, toolbar, background tool, project files
  Recording/    recorder, overlays, GIF export, video editor
  Snapping/     snap positions and geometry, Accessibility window control, drag / modifier / title bar monitors
  Settings/     settings window, shortcut recorder
  Support/      geometry, image export, gradients, overlay panel
Tests/SnapwiseTests/
```

## License

MIT — see [LICENSE](LICENSE).
