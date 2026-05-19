<div align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Maya Studio app icon" />

  # Maya Studio

  **A diverged fork of Maya, released as Maya Studio, for polished product videos, richer device framing, timeline trimming, and App Store / social exports.**

  Native macOS editor for turning screen recordings into framed, animated marketing clips with zoom moments, trim controls, preset previews, and transparent or social-ready exports.

  Current release: **Maya Studio 1.0.5**

  ![Maya Studio screenshot](docs/screenshot.png)
</div>

---

## About This Fork

This repository started from [ronaldo-avalos/Maya](https://github.com/ronaldo-avalos/Maya), but this version has intentionally diverged. The app is now user-facing as **Maya Studio** and ships under the bundle identifier `com.dlmapps.MayaStudio`.

Some internal paths still use the original `Maya` name, including the source folder, Xcode project, and target. That is deliberate: the product name, display name, export naming, bundle identifier, and README identify this fork as **Maya Studio**, while the project layout stays stable to avoid unnecessary churn.

## How Maya Studio Deviates From Upstream

Maya Studio keeps the original Maya foundation, then adds a more opinionated product-video workflow:

| Area | Upstream Maya | Maya Studio |
|---|---|---|
| App identity | Maya | Maya Studio |
| Bundle ID | `com.dlmapps.Maya` | `com.dlmapps.MayaStudio` |
| Release line | Original upstream releases | Fork release line, currently `v1.0.5` |
| Minimum macOS | Upstream project target | macOS 26.2+ so the app launches on this Mac |
| Device framing | iPhone-focused physical frames | iPhone Pro frames, MacBook Pro 14, generic phone, classic phone, Android-style phone, tablet, laptop, and no-frame modes |
| Canvas workflow | Basic framed recording exports | Square, vertical, portrait social, landscape, and widescreen export presets |
| Generic/no-frame controls | Limited | Corner radius, bezel width, bezel color, and shadows |
| Timeline | Zoom animation timeline | Zoom timeline plus draggable clip trimming and independent clip timeline positioning |
| Animation editing | Modal/sheet-driven editing | Inline side-panel editing with live canvas updates |
| Presets | Text preset choices | Bundled animation preset preview videos |
| Export focus | Framed video export | Social-ready MP4 plus transparent HEVC-with-alpha MOV export |

The merge from upstream was selective. Maya Studio includes upstream's useful trim, timeline, preset preview, MacBook frame, and export improvements, while preserving this fork's expanded device catalog and shared wide-frame fitting behavior.

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

The latest installable app for this fork is **Maya Studio 1.0.5**:

[Download Maya Studio 1.0.5](https://github.com/AyoParadis/Maya/releases/tag/v1.0.5)

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

## Upstream

Maya Studio is derived from [ronaldo-avalos/Maya](https://github.com/ronaldo-avalos/Maya). Upstream remains the source for the original app direction; this fork carries additional editor, device, canvas, timeline, naming, and export workflow changes.

## License

MIT. See [LICENSE](LICENSE).
