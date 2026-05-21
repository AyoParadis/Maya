<div align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Maya AI Studio app icon" />

  # Maya AI Studio

  **AI screen recording editor for app demos, product videos, device mockups, App Store previews, and social launch clips.**

  Native macOS app that turns `.mp4` and `.mov` screen recordings into polished framed product videos, and turns product image sets into conversion-focused carousel videos and stills. Maya AI Studio adds AI-directed trim and zoom suggestions, carousel planning, device mockups, timeline editing, social aspect ratios, and export tools for makers, designers, and app teams.

  Current release: **Maya AI Studio 1.0.9**

  ![Maya AI Studio screenshot](docs/screenshot.png)
</div>

---

## Maya AI Studio

Maya AI Studio is a standalone product and release line. It is a macOS creative editor for makers, designers, and app teams who need to turn raw product recordings into launch videos, App Store preview assets, social clips, demo videos, transparent overlays, carousel ads, and device mockup videos without moving through a heavy video editor.

The built app is named **Maya AI Studio**, uses the bundle identifier `com.dlmapps.MayaAIStudio`, and follows the Maya AI Studio release line. Some internal paths still use the original `Maya` name, including the source folder, Xcode project, and target. That is deliberate: the public product name changed while the project layout stayed stable.

## Quick answer

Maya AI Studio is an AI-assisted Mac app for creating product demo videos from screen recordings and carousel creatives from images. It helps you trim a recording, place it inside iPhone, Android, tablet, laptop, MacBook, or no-frame mockups, add subtle zoom animations, choose social-ready canvas sizes, build image carousels, and export polished `.mp4`, transparent `.mov`, still image sets, or carousel bundles.

Use Maya AI Studio when you are searching for a:

- Screen recording editor for product videos.
- Product demo video maker for macOS.
- App Store preview video creator.
- Device mockup video generator for app demos.
- Social media launch video tool for software products.
- AI-assisted video editor that uses a local Codex CLI workflow.
- Carousel video maker for Instagram, TikTok, Reels, Shorts, and feed creatives.
- Social ad carousel builder with local-Codex planning and creative scoring.
- Transparent background video export tool for app and SaaS demos.

## Studio modes

Maya AI Studio has two top-level modes:

- **Video** keeps the existing screen-recording editor: device framing, timeline trim, zoom animation, AI Director, background styling, and `.mp4` or transparent `.mov` export.
- **Carousel** builds social image carousels through a guided pipeline: write a brief, create a local-Codex outline, draft and approve one slide at a time, preview motion, check safe zones, and export approved videos, stills, or bundles.

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

## Carousel Creative Studio

The **Carousel** mode is designed for Instagram, TikTok, Reels, Shorts, LinkedIn, and feed-oriented image creatives. Create one or more carousel projects, write a source brief, optionally import images by picker or drag-and-drop, choose a target aspect ratio, select a conversion formula, draft slides one at a time, approve the finished sequence, and export the same creative as a motion video, still image set, or structured handoff bundle.

Carousel mode includes:

- Multiple in-memory carousel projects per session.
- Aspect presets for `9:16`, `4:5`, `1:1`, and `16:9`.
- Motion presets: **Still**, **Subtle Zoom**, **Punch Zoom**, **Pan**, and **Auto**.
- Built-in carousel formulas such as problem/benefit/proof/CTA, before/after/offer, feature-led, app walkthrough, promo/urgency, myth/truth/framework, and checklist/save CTA.
- A sequential approval pipeline: create outline, draft active slide, regenerate selected slide, approve, and move to the next slide.
- Safe-zone overlays for vertical video, feed portrait, and square carousel placements.

### Carousel Director

Carousel Director mirrors the local Codex workflow used by AI Director, but keeps carousel requests intentionally small. Maya writes a run bundle with the brief, compact slide metadata, a JSON schema, and a prompt, then asks the installed `codex` command to generate strict carousel outline or slide-draft JSON. Imported images stay local to rendering and export; carousel Codex runs only receive whether a slide has an image, not the image itself.

Generated carousel outlines define slide roles, ordering, concise copy direction, visual prompts, motion, timing, focal-point hints, and warnings from the local Codex run. Slide drafts are generated one at a time and must be approved before they are treated as export-ready. V1 does **not** generate new image assets; it uses imported images or a simple composed background while storing visual prompts for future image-generation workflows. Plans do **not** delete imported images. If Codex is unavailable, Maya applies a deterministic fallback outline or slide draft based on the selected formula and current card order.

## What Maya AI Studio Adds

- AI Director for local-Codex edit planning, editable retries, plan version history, preview, and fallback generation.
- Carousel Creative Studio for brief-to-carousel pipelines, local-Codex outlining, per-slide drafting and approval, safe-zone preview, and batch-friendly exports.
- Behavioral-science defaults for short social demos: early hook, dead-time removal, clear problem/action/result arc, soft attention cues, and outcome-focused endings.
- Calm AI zoom profiles, including **Barely There** motion for premium, understated product demos.
- A broader device catalog with iPhone Pro frames, MacBook Pro 14, generic phone, classic phone, Android-style phone, tablet, laptop, and no-frame modes.
- Canvas presets for square, vertical, portrait social, landscape, and widescreen exports.
- Generic and no-frame styling controls for corner radius, bezel width, bezel color, and shadows.
- Timeline editing with draggable clip trimming, independent clip timeline positioning, zoom blocks, edge resizing, and playhead snapping.
- Inline side-panel animation editing with live canvas updates.
- Bundled animation preset preview videos.
- Social-ready `.mp4` export and transparent HEVC-with-alpha `.mov` export.
- Carousel `.mp4`, still image set, and export bundle output for social/ad handoff workflows.

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
- Review rationale, trim range, zoom count, and warnings.
- Refine with target length, pacing, zoom intensity, opening hook strength, ending emphasis, and revision notes.
- Retry without losing prior versions, compare generated plans, and apply the version that fits best.
- Keep AI output constrained to trim and zoom edits, with safety clamping for calm/subtle motion.

### Carousel creation

- Import product screenshots, app screens, launch graphics, or ad image sets.
- Start from text content only and add final images when they are ready.
- Manage multiple carousel projects in one session.
- Drag thumbnails to reorder the story.
- Edit per-card role, badge, headline, subtitle, CTA, visual prompt, duration, and motion.
- Generate a local-Codex outline that plans slide order, roles, copy direction, visual prompts, motion, CTA placement, and creative warnings.
- Draft, regenerate, and approve slides one at a time so finished slides stay locked while the next slide is created.
- Preview still, zoom, punch, pan, or auto-selected motion before export.

### Common use cases

- Turn a raw app screen recording into a launch video.
- Make an App Store preview, Product Hunt demo, landing-page video, or social ad creative.
- Frame a mobile app recording in realistic iPhone-style mockups.
- Create SaaS and web-app demos with laptop, tablet, phone, or no-frame layouts.
- Add zoom emphasis to important UI moments without hand-keyframing every movement.
- Export transparent HEVC overlays for motion graphics, websites, or video editors.
- Turn app screenshots into Instagram/TikTok-style carousel videos.
- Produce still carousel image sets and copy handoff bundles for social ad workflows.

### Export

- Export social-ready `.mp4` files using the selected canvas aspect.
- Export transparent `.mov` files with HEVC alpha when the background is set to none.
- Exported videos include device frame, background, shadows, trim, and zoom animation.
- In Carousel mode, export H.264 `.mp4` slideshow videos at 30 FPS.
- Export matching `.png` still image sets for carousel uploads.
- Export a bundle folder containing the video, still images, `carousel-brief.json`, `carousel-outline.json`, `slides.json`, `copy.txt`, and a handoff `README.txt`.

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
- AVAssetWriter image-sequence export for carousel videos
- Core Image and Metal compositing
- HEVC-with-alpha export support
- Swift Observation and async/await
- Sandboxed local video and image adoption for reliable preview and export access

## Requirements

- macOS 26.2 or later
- Xcode 26.5 or later
- `.mp4` or `.mov` screen recording
- Images for Carousel mode, or a `.mp4`/`.mov` screen recording for Video mode
- Codex CLI installed and signed in for AI Director and Carousel Director generation
- A Codex account/subscription for local Codex CLI usage

## Releases

The latest installable Maya AI Studio release is **Maya AI Studio 1.0.9**:

[Download Maya AI Studio 1.0.9](https://github.com/AyoParadis/Maya/releases/tag/v1.0.9)

### Maya AI Studio 1.0.9

- Adds Carousel Creative Studio for image carousel projects with local-Codex outlining, per-slide drafting, approval, motion preview, safe-zone review, and export to video, still images, or structured bundles.
- Updates carousel mode to match video mode's macOS header behavior, with the app title, build label, and a single working sidebar toggle in the titlebar.
- Reuses the video editor's canvas background and timeline chrome in carousel mode so empty canvases and carousel tracks stay readable and visually consistent.
- Adds carousel import, rendering, image adoption, AI planning, and export services for the new carousel workflow.
- Keeps carousel editing local-first: imported images stay on device, and Carousel Director only sends compact slide metadata to the user's local Codex CLI workflow.

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
├── ContentView.swift             Root mode switcher
├── Models/                       Video and carousel state, device catalog, canvas sizes, animation specs
├── Services/                     Video/carousel export, AI bridges, compositing, thumbnails, animation sampling
├── Views/                        Video editor, carousel studio, canvas, sidebar, timeline, animation editor
├── Views/Timeline/               Ruler, clip trimming, thumbnails, zoom animation track
├── Resources/PresetPreviews/     Bundled preset preview videos
└── Assets.xcassets/              App icon and device frame assets
```

## Upstream

Maya AI Studio is maintained as a standalone app. The repository keeps an upstream connection to [ronaldo-avalos/Maya](https://github.com/ronaldo-avalos/Maya) only so useful upstream commits can be reviewed and pulled in when they fit Maya AI Studio's direction.

## License

MIT. See [LICENSE](LICENSE).
