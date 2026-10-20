# Glimpse

A native macOS screenshot app in the spirit of CleanShot X. It lives in the menu bar and covers the everyday flow: capture, a floating thumbnail, a quick annotation, then share.

Requires **macOS 14 Sonoma or later** and **Xcode 15 or later**.

## Features (v0.1)

| | |
|---|---|
| **Capture** | Area (with frozen screen, magnifier loupe, size badge, ⇧ square, ⌥ from center), window (Space to toggle, clean capture without overlapping windows), fullscreen, previous area |
| **Capture text (OCR)** | Select an area and the recognised text goes to the clipboard (on-device Vision) |
| **Quick Access overlay** | Thumbnails stack bottom-left. Hover for Copy / Save, Close, Pin, Annotate. Double-click to annotate, drag into any app, right-click for more |
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

They use ⌥⇧ so they don't clash with macOS's built-in ⌘⇧3/4/5.

### Planned

Scrolling capture, screen recording / GIF, cloud upload with share links, custom shortcuts, capture history window.

## Build and run

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen), so there's no `.xcodeproj` to merge.

```sh
brew install xcodegen
xcodegen generate
open Glimpse.xcodeproj
```

In Xcode, pick your team under *Signing & Capabilities* (a free personal team works), then ⌘R.

On first launch macOS asks for **Screen & System Audio Recording** permission. Grant it in System Settings, then quit and reopen Glimpse. The app runs from the menu bar (no Dock icon) and shows in the Dock only while an editor window is open.

Command-line build (this is also how changes are verified; there is no CI):

```sh
xcodegen generate
xcodebuild -project Glimpse.xcodeproj -scheme Glimpse -configuration Debug build
```

## Code layout

```
Glimpse/
  App/        App entry, menu bar dropdown, CaptureCoordinator (routes every capture)
  Capture/    Capture model and ScreenCaptureKit wrapper
  Overlay/    Area/window selection overlay, Quick Access thumbnails, pinned images
  Editor/     Annotation model, renderer, editor model/view/window
  Services/   Hotkeys (Carbon), permissions, settings, clipboard, export, OCR, sound, toast
  Settings/   Settings window
```

Built with Swift, SwiftUI + AppKit, ScreenCaptureKit (`SCScreenshotManager`), Vision and Core Image.
