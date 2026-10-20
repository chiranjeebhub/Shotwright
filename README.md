# Shotwright

A native macOS screenshot app in the spirit of CleanShot X. It lives in the menu bar and covers the everyday flow: capture, a floating thumbnail, a quick annotation, then share.

Requires **macOS 14 Sonoma or later** and **Xcode 15 or later**.

## Features (v0.1)

| | |
|---|---|
| **Capture** | Area (with frozen screen, magnifier loupe, size badge, ⇧ square, ⌥ from center), window (Space to toggle, clean capture without overlapping windows), fullscreen, previous area |
| **Scrolling capture** | Select an area or window (Space), then scroll: frames are stitched into one tall image, with sticky headers and footers kept once. Live preview beside the area, Return to finish, Esc to cancel |
| **Capture text (OCR)** | Select an area and the recognised text goes to the clipboard (on-device Vision) |
| **Quick Access overlay** | Thumbnails stack bottom-left. Hover for Copy / Save, Close, Pin, Annotate. Double-click to annotate, drag into any app, right-click for more |
| **Record screen / GIF** | Drag an area, click for full screen, or Space for a window. A bar under the area picks MP4 or GIF and cursor on/off, then shows a timer with Pause, Stop and Discard. Finished recordings land in Quick Access: Copy (the file, or GIF data), Save, Play, drag into any app |
| **Pin to screen** | Keeps a capture floating above everything. Drag to move, scroll to resize, double-click or Esc to close |
| **Annotation editor** | Select/move, crop, arrow, rectangle, ellipse, line, pen, highlighter, text, numbered counters, pixelate. Colours, size, undo/redo, zoom, Copy / Save / Save As |
| **Menu bar menu** | All actions with icons and shortcuts, plus your recent captures |
| **Settings** | Save folder, PNG/JPEG/HEIC, Retina export, after-capture actions, shutter sound, start at login, cursor |

### Default shortcuts

| Action | Shortcut |
|---|---|
| Capture Area | ⌥⇧4 |
| Capture Window | ⌥⇧5 |
| Capture Fullscreen | ⌥⇧3 |
| Capture Previous Area | ⌥⇧6 |
| Capture Text (OCR) | ⌥⇧2 |
| Record Screen / GIF (again to stop) | ⌥⇧7 |
| Scrolling Capture | ⌥⇧8 |

They use ⌥⇧ so they don't clash with macOS's built-in ⌘⇧3/4/5.

### Planned

Audio in recordings, auto-scroll for scrolling capture, cloud upload with share links, custom shortcuts, capture history window.

## Build and run

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen), so there's no `.xcodeproj` to merge.

```sh
brew install xcodegen
xcodegen generate
open Shotwright.xcodeproj
```

In Xcode, pick your team under *Signing & Capabilities* (a free personal team works), then ⌘R.

On first launch macOS asks for **Screen & System Audio Recording** permission. Grant it in System Settings, then quit and reopen Shotwright. The app runs from the menu bar (no Dock icon) and shows in the Dock only while an editor window is open.

Command-line build (this is also how changes are verified; there is no CI):

```sh
xcodegen generate
xcodebuild -project Shotwright.xcodeproj -scheme Shotwright -configuration Debug build
```

## Code layout

```
Shotwright/
  App/        App entry, menu bar dropdown, CaptureCoordinator (routes every capture)
  Capture/    Capture model and ScreenCaptureKit wrapper
  Overlay/    Area/window selection overlay, Quick Access thumbnails, pinned images
  Recording/  Screen recorder (SCStream + AVAssetWriter), GIF export, recording bar and result card
  Editor/     Annotation model, renderer, editor model/view/window
  ScrollingCapture/  Scrolling capture session, HUD and frame stitcher
  Services/   Hotkeys (Carbon), permissions, settings, clipboard, export, OCR, sound, toast
  Settings/   Settings window
```

Built with Swift, SwiftUI + AppKit, ScreenCaptureKit (`SCScreenshotManager`), Vision and Core Image.
