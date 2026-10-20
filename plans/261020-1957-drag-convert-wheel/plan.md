# Drag & Convert wheel (inspired by Tangerine)

Status: done (v1.3.0) · Mode: `--port` (product site, no source repo — behaviour ported, code written for Snapwise)

## Source manifest
- https://tangerineformac.com (marketing page only; no code available). Feature facts taken from the page.
- Core idea: drag a file, tap a modifier → radial wheel. ⇧ = convert formats, ⌘ = file tools, ⌃ = file actions.
  Wheel stays after key release until drop / cancel; keys configurable. Everything offline.

## Dependency matrix
| Source component | Local equivalent | Status |
| --- | --- | --- |
| Global drag + modifier detection | NSEvent global monitors (already used by snapping, Accessibility granted) | NEW `FileDragMonitor` |
| Radial wheel UI, drop targets | OverlayPanel (Toast.swift) | NEW `ConvertWheel` |
| 275 conversions (bundled engines) | ImageIO, AVFoundation, AppKit text, PDFKit, /usr/bin/ditto,tar | NEW `FileConverters` (subset) |
| Tools (compress, crop, trim, split, merge) | Annotate editor, video editor, OCR, PDFKit | NEW `FileTools`, reuse editors |
| Actions (AirDrop, Float, Copy, Move, Copy Path, Terminal) | PinWindowController, Output.copy | NEW `FileActions` |
| Settings | SettingsWindow tabs | NEW "Convert" tab |

## Decision matrix
| Decision | Tangerine | Snapwise | Recommendation |
| --- | --- | --- | --- |
| Engines | bundled (ffmpeg-like, office) | system frameworks only | system only: no binary deps, keeps app small; skip MP3/WebP/Opus/XLSX/PPTX output |
| Output | next to source | next to source, unique name | same |
| Trigger | drag + modifier tap | same + "Convert Files…" menu/hotkey (click mode) | both |
| Allowance / paywall | yes | none | none |
| Platform | Apple silicon, macOS 13 | universal, macOS 15 | keep ours |

## Challenge (risks)
1. Global flagsChanged during a Finder drag may not reach us → also poll `pressedMouseButtons` + drag pasteboard changeCount; verified by test.
2. Wheel steals drop from Finder target → wheel only appears after explicit tap; Esc/drag end hides it.
3. Conflicts with snapping modifier gestures → wheel only when a *file* drag is active (drag pasteboard changed since mouse down).
4. Long conversions block UI → run off main thread, progress toast, errors toasted.
5. Overwriting user files → never overwrite; `name 2.ext` style unique URLs.

## Acceptance
- Dragging a file and tapping ⇧/⌘/⌃ shows the matching wheel at the pointer; dropping on a bubble produces the output next to the file.
- Tapping another modifier switches the wheel; Esc or ending the drag elsewhere closes it.
- "Convert Files…" (menu + hotkey) opens the same wheel for chosen files, clickable.
- Unit tests for catalog/ naming; build + tests pass; release.

## Rollback
Feature is isolated in `Sources/Snapwise/Convert/` + one settings tab + pref `convertEnabled` (off = no monitors).
