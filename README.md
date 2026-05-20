<div align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Maya AI Studio app icon" />

  # Maya AI Studio

  **AI screen recording editor for app demos, product videos, device mockups, App Store previews, and social launch clips.**

  Native macOS app that turns `.mp4` and `.mov` screen recordings into polished framed product videos. Maya AI Studio adds AI-directed trim and zoom suggestions, device mockups, timeline editing, social aspect ratios, and transparent video export for makers, designers, and app teams.

  Current release: **Maya AI Studio 1.0.8**

  ![Maya AI Studio screenshot](docs/screenshot.png)
</div>

---

## Maya AI Studio

Maya AI Studio is a standalone product and release line. It is a macOS screen recording editor for makers, designers, and app teams who need to turn raw product recordings into launch videos, App Store preview assets, social clips, demo videos, transparent overlays, and device mockup videos without moving through a heavy video editor.

The built app is named **Maya AI Studio**, uses the bundle identifier `com.dlmapps.MayaAIStudio`, and follows the Maya AI Studio release line. Some internal paths still use the original `Maya` name, including the source folder, Xcode project, and target. That is deliberate: the public product name changed while the project layout stayed stable.

## Quick answer

Maya AI Studio is an AI-assisted Mac app for creating product demo videos from screen recordings. It helps you trim a recording, place it inside iPhone, Android, tablet, laptop, MacBook, or no-frame mockups, add subtle zoom animations, choose social-ready canvas sizes, and export polished `.mp4` or transparent `.mov` videos.

Use Maya AI Studio when you are searching for a:

- Screen recording editor for product videos.
- Product demo video maker for macOS.
- App Store preview video creator.
- Device mockup video generator for app demos.
- Social media launch video tool for software products.
- AI-assisted video editor that uses a local Codex CLI workflow.
- Transparent background video export tool for app and SaaS demos.

## AI Director

AI Director is the main new workflow in Maya AI Studio. Load a recording, choose **Create video**, and Maya builds a local analysis bundle, asks your installed Codex CLI for an edit plan, validates it, applies trim and zoom edits, and starts an in-app preview. You can adjust the direction controls, add revision notes, retry, compare plan versions, apply older or newer versions, and export only when you are happy with the result.

AI Director is intentionally non-destructive in v1. It only changes the selected trim range and zoom segments. Canvas, device frame, background, shadows, styling, and export settings remain under your control.

### Local Codex requirement

AI Director uses your **local Codex CLI**. Maya sends sampled frames and project metadata to the locally installed `codex` command, and usage is tied to your local Codex login or subscription. Maya does not ask for API keys, does not use a Maya-hosted AI service, and does not upload the full video file from the app.

Install and sign in before using AI Director:

```bash
codex login
```

If Codex is unavailable or the generated plan fails validation, Maya shows an actionable error and can offer a local heuristic fallback so you can still create a draft edit.

## What Maya AI Studio Adds

- AI Director for local-Codex edit planning, editable retries, plan version history, preview, and fallback generation.
- Behavioral-science defaults for short social demos: early hook, dead-time removal, clear problem/action/result arc, soft attention cues, and outcome-focused endings.
- Calm AI zoom profiles, including **Barely There** motion for premium, understated product demos.
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

### AI-assisted editing

- Generate a social-demo edit plan through the local Codex CLI.
- Review rationale, hook score, clarity score, pacing score, trim range, zoom count, and warnings.
- Refine with target length, pacing, zoom intensity, opening hook strength, ending emphasis, and revision notes.
- Retry without losing prior versions, compare generated plans, and apply the version that fits best.
- Keep AI output constrained to trim and zoom edits, with safety clamping for calm/subtle motion.

### Common use cases

- Turn a raw app screen recording into a launch video.
- Make an App Store preview, Product Hunt demo, landing-page video, or social ad creative.
- Frame a mobile app recording in realistic iPhone-style mockups.
- Create SaaS and web-app demos with laptop, tablet, phone, or no-frame layouts.
- Add zoom emphasis to important UI moments without hand-keyframing every movement.
- Export transparent HEVC overlays for motion graphics, websites, or video editors.

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
- Codex CLI installed and signed in for AI Director generation
- A Codex account/subscription for local Codex CLI usage

## Releases

The latest installable Maya AI Studio release is **Maya AI Studio 1.0.8**:

[Download Maya AI Studio 1.0.8](https://github.com/AyoParadis/Maya/releases/tag/v1.0.8)

### Maya AI Studio 1.0.8

- Fixes zoom block dragging and resizing in the animation timeline so blocks track the pointer smoothly instead of jumping backward during a drag.
- Uses a stable timeline-track coordinate space for live drag gestures, avoiding feedback from measuring movement inside the block that is currently being repositioned.
- Expands the timeline drag regression check so future changes fail fast if animation block gestures return to moving local coordinates.

Release artifacts are ad-hoc signed when built locally on this machine because the configured Mac Development certificate is not installed here.

## Build and run

```bash
git clone https://github.com/AyoParadis/Maya.git
cd Maya
open Maya.xcodeproj
```

Run the `Maya` target in Xcode. The built app is named **Maya AI Studio**.

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

Maya AI Studio is maintained as a standalone app. The repository keeps an upstream connection to [ronaldo-avalos/Maya](https://github.com/ronaldo-avalos/Maya) only so useful upstream commits can be reviewed and pulled in when they fit Maya AI Studio's direction.

## License

MIT. See [LICENSE](LICENSE).
