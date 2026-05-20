<div align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Maya Studio app icon" />

  # Maya Studio

  **Turn screen recordings into polished framed product videos with trimming, zoom animations, device mockups, and social-ready exports.**

  Native macOS editor for turning screen recordings into framed, animated marketing clips with zoom moments, trim controls, preset previews, and transparent or social-ready exports.

  Current release: **Maya Studio 1.0.6**

  ![Maya Studio screenshot](docs/screenshot.png)
</div>

---

## Maya Studio

Maya Studio is its own product and release line. It is designed for makers, designers, and app teams who need to turn raw screen recordings into launch videos, App Store assets, social clips, demos, and transparent overlays without moving through a heavy video editor.

The built app is named **Maya Studio**, uses the bundle identifier `com.dlmapps.MayaStudio`, and follows the Maya Studio release line. Some internal paths still use the original `Maya` name, including the source folder, Xcode project, and target. That is deliberate: the public product name changed while the project layout stayed stable.

## What Maya Studio Adds

- A broader device catalog with iPhone Pro frames, MacBook Pro 14, generic phone, classic phone, Android-style phone, tablet, laptop, and no-frame modes.
- Canvas presets for square, vertical, portrait social, landscape, and widescreen exports.
- Generic and no-frame styling controls for corner radius, bezel width, bezel color, and shadows.
- Timeline editing with draggable clip trimming, independent clip timeline positioning, zoom blocks, edge resizing, and playhead snapping.
- Inline side-panel animation editing with live canvas updates.
- Bundled animation preset preview videos.
- Social-ready `.mp4` export and transparent HEVC-with-alpha `.mov` export.

## Features

### Device framing

- Drop in an iPhone, iPad, MacBook, Android, or app demo recording.
- Choose physical frames where available, or use configurable drawn frames for brand-agnostic mockups.
- Scale and reposition the device directly on the canvas.
- Add shadows, solid colors, gradients, image backgrounds, blurred-video backgrounds, or transparent backgrounds.

### Timeline and motion

- Trim the clip with draggable in/out handles.
- Move the clip along the timeline without changing the selected source range.
- Add zoom segments from the track or toolbar.
- Drag zoom blocks to move them and drag their edges to resize them.
- Snap animation timing to quarter-second marks and the playhead.
- Tune scale, focus, duration, easing, and zoom-in/out timing from the side editor.

### Export

- Export social-ready `.mp4` files using the selected canvas aspect.
- Export transparent `.mov` files with HEVC alpha when the background is set to none.
- Exported videos include device frame, background, shadows, trim, and zoom animation.

## Keyboard shortcuts

| Key | Action |
|---|---|
| <kbd>Space</kbd> | Play / pause |
| <kbd>M</kbd> | Mute / unmute |
| <kbd>I</kbd> | Mark trim in |
| <kbd>O</kbd> | Mark trim out |
| <kbd>Delete</kbd> | Delete selected zoom event |
| <kbd>Command</kbd> + <kbd>D</kbd> | Duplicate selected zoom event |
| <kbd>Left</kbd> / <kbd>Right</kbd> | Scrub 0.25 s |
| <kbd>Shift</kbd> + <kbd>Left</kbd> / <kbd>Right</kbd> | Scrub 1 s |

## Tech stack

- SwiftUI and AppKit
- AVFoundation custom video composition
- Core Image and Metal compositing
- HEVC-with-alpha export support
- Swift Observation and async/await
- Sandboxed local video adoption for reliable preview and export access

## Requirements

- macOS 26.2 or later
- Xcode 26.5 or later
- `.mp4` or `.mov` screen recording

## Releases

The latest installable Maya Studio release is **Maya Studio 1.0.6**:

[Download Maya Studio 1.0.6](https://github.com/AyoParadis/Maya/releases/tag/v1.0.6)

Release artifacts are ad-hoc signed when built locally on this machine because the configured Mac Development certificate is not installed here.

## Build and run

```bash
git clone https://github.com/AyoParadis/Maya.git
cd Maya
open Maya.xcodeproj
```

Run the `Maya` target in Xcode. The built app is named **Maya Studio**.

## Code map

```text
Maya/
├── MayaApp.swift                 App entry
├── ContentView.swift             Root view
├── Models/                       Project state, device catalog, canvas sizes, animation specs
├── Services/                     Export, compositing, thumbnails, animation sampling
├── Views/                        Editor, canvas, sidebar, timeline, animation editor
├── Views/Timeline/               Ruler, clip trimming, thumbnails, zoom animation track
├── Resources/PresetPreviews/     Bundled preset preview videos
└── Assets.xcassets/              App icon and device frame assets
```

## Origins

Maya Studio began as a fork of [ronaldo-avalos/Maya](https://github.com/ronaldo-avalos/Maya). This project now follows its own product direction and release cadence, while keeping attribution to the original project history.

## License

MIT. See [LICENSE](LICENSE).
