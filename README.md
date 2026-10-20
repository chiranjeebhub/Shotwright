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

To build, sign, install to `/Applications` and relaunch in one step:

```sh
scripts/install.sh
```

It signs with your Apple Development certificate (or a self-signed "Shotwright Local Signing" certificate it creates once). Always install this way rather than with an unsigned build: macOS ties the Screen Recording permission to the code signature, and an unsigned build gets a new one on every rebuild, which makes macOS ask for the permission again even while it is switched on.

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

## Releasing

`project.yml` defines two builds of the same app (bundle ID `com.shotwright.app`):

| Scheme | For | Differences |
|---|---|---|
| `Shotwright` | Direct download (DMG) and `scripts/install.sh` | Not sandboxed, updates itself with [Sparkle](https://sparkle-project.org) |
| `Shotwright-AppStore` | Mac App Store | App Sandbox, no Sparkle |

In the sandboxed build the first save asks which folder to use (Desktop preselected) and remembers it as a security-scoped bookmark.

Both need a paid Apple Developer Program team; pass its Team ID as `SHOTWRIGHT_TEAM_ID`. Bump `MARKETING_VERSION` in `project.yml` for each release; the build number is the UTC time of the archive.

### Direct download

```sh
SHOTWRIGHT_TEAM_ID=XXXXXXXXXX scripts/release-direct.sh
```

Archives with your Developer ID Application certificate, notarizes and staples the app and the DMG, writes `dist/Shotwright-<version>.dmg`, and adds an entry to `appcast.xml`. Publish by attaching the DMG to a GitHub release tagged `v<version>` and pushing `appcast.xml`; installed copies read the feed from `main`.

One-time setup: a Developer ID Application certificate (Xcode > Settings > Accounts > Manage Certificates), notarization credentials (`xcrun notarytool store-credentials shotwright-notary --apple-id <you> --team-id <team>`), and a Sparkle key (`generate_keys` from the Sparkle package; the public key goes in `SPARKLE_PUBLIC_KEY` in `project.yml`, the private key stays in your keychain).

### Mac App Store

```sh
SHOTWRIGHT_TEAM_ID=XXXXXXXXXX scripts/release-appstore.sh            # export build/AppStore/Shotwright.pkg
SHOTWRIGHT_TEAM_ID=XXXXXXXXXX scripts/release-appstore.sh --upload   # upload to App Store Connect
```

Needs the App Store Connect app record for `com.shotwright.app`.
