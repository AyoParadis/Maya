<div align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Maya AI Studio app icon" />

  # Maya AI Studio

  **AI screen recording editor for app demos, product videos, device mockups, App Store previews, and social launch clips.**

  Native macOS app that turns `.mp4` and `.mov` screen recordings into polished framed product videos, and turns product image sets into conversion-focused carousel videos and stills. Maya AI Studio adds AI-directed trim and zoom suggestions, local Piper voiceovers, carousel OCR, device mockups, timeline editing, social aspect ratios, and export tools for makers, designers, and app teams.

  Current release: **Maya AI Studio 2.0.2**

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
- Social ad carousel builder with local OCR, Piper voiceovers, and fast carousel exports.
- Transparent background video export tool for app and SaaS demos.

## Studio modes

Maya AI Studio has two top-level modes:

- **Video** keeps the existing screen-recording editor: device framing, timeline trim, zoom animation, AI Director, background styling, and `.mp4` or transparent `.mov` export.
- **Carousel** builds social image carousels from imported slides: choose layout and motion, generate/edit per-slide voiceovers, preview timing, check safe zones, and export videos, stills, or bundles.

## Local AI Narration

Video and Carousel modes include local narration powered by selectable AI voice engines. Write a voiceover script in Maya, choose Piper or Kokoro, pick a voice, generate a `.wav` file locally, and Maya includes that narration track in exported videos.

Maya installs each voice engine into its own local Python virtual environment in Application Support, then runs the selected engine from that environment:

```bash
python3 -m venv "Application Support/Maya AI Studio/PiperEnvironment"
"Application Support/Maya AI Studio/PiperEnvironment/bin/python" -m pip install --upgrade piper-tts
python3 -m venv "Application Support/Maya AI Studio/KokoroEnvironment"
"Application Support/Maya AI Studio/KokoroEnvironment/bin/python" -m pip install --upgrade "kokoro>=0.9.4" soundfile "misaki[en]"
```

The voiceover panel includes an engine picker, voice/reference picker, **Preview**, compact local storage usage, and a state-aware setup control. Missing engines show **Install selected engine**; installed engines keep daily controls visible and tuck refresh, generated voiceover removal, and engine asset deletion into a compact **More** menu; incompatible local environments show **Repair install**. Setup avoids changing the system Python installation, streams live package/download progress into the voiceover status area, and works around Homebrew's externally managed Python restrictions. After an engine installs or refreshes, Maya prepares cached previews for that engine's catalog voices so the Preview button responds quickly on later use.

Piper remains the fastest fallback and supports custom Piper voice IDs. Kokoro is the default AI voice engine and adds downloadable premium local voices such as `af_heart`, `af_bella`, and `am_adam`; on macOS it may also need `espeak-ng` available on the system path.

On first generation for a selected non-cached Piper voice, Maya downloads the matching Piper voice files into Application Support, then reuses them for later renders. The default engine is Kokoro with `af_heart`. Generated narration and voice previews stay local; narration is cached until it is replaced, removed, or the current video/carousel project changes.

Maya shows the selected engine's local asset size and total AI voice asset size in both Video and Carousel voiceover panels. The total includes engine Python environments, downloaded Piper voice models, and cached voice previews; it does not include generated project voiceover files. Use **Delete engine assets** to remove the selected engine's local environment, downloaded voice assets, and cached previews while keeping generated project voiceovers intact.

In Carousel mode, Maya can also generate slide-by-slide voiceovers with the selected engine. Choose **Generate slide voiceovers** to use each slide's planned text first, fall back to local Apple Vision OCR for imported image text, generate one clip per slide, place the clips on the carousel timeline, and automatically extend slide durations to fit the generated audio. The inspector keeps detected text copyable, lets users edit the spoken script, uses the local Codex CLI to clean OCR-damaged grammar and punctuation, and regenerates audio from the edited script without overwriting those manual fixes.

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

The **Carousel** mode is designed for Instagram, TikTok, Reels, Shorts, LinkedIn, and feed-oriented image creatives. Create one or more carousel projects, write a source brief, optionally import images by picker or drag-and-drop, choose a target aspect ratio, tune motion, generate slide voiceovers, and export the same creative as a motion video, still image set, or structured handoff bundle.

Carousel mode includes:

- Multiple in-memory carousel projects per session.
- Aspect presets for `9:16`, `4:5`, `1:1`, and `16:9`.
- Motion presets: **Still**, **Subtle Zoom**, **Punch Zoom**, **Pan**, and **Auto**.
- Editable per-slide voiceover text with copy, Codex cleanup, re-detect, and regenerate controls backed by local Apple Vision OCR.
- One-button slide voiceover generation that detects text from each carousel slide and places narration on the timeline.
- Safe-zone overlays for vertical video, feed portrait, and square carousel placements.

## What Maya AI Studio Adds

- AI Director for local-Codex edit planning, editable retries, plan version history, preview, and fallback generation.
- Carousel Creative Studio for imported image carousels, local OCR, editable per-slide voiceovers, safe-zone preview, and batch-friendly exports.
- Behavioral-science defaults for short social demos: early hook, dead-time removal, clear problem/action/result arc, soft attention cues, and outcome-focused endings.
- Calm AI zoom profiles, including **Barely There** motion for premium, understated product demos.
- A broader device catalog with iPhone Pro frames, MacBook Pro 14, generic phone, classic phone, Android-style phone, tablet, laptop, and no-frame modes.
- Canvas presets for square, vertical, portrait social, landscape, and widescreen exports.
- Generic and no-frame styling controls for corner radius, bezel width, bezel color, and shadows.
- Timeline editing with draggable clip trimming, independent clip timeline positioning, zoom blocks, edge resizing, and playhead snapping.
- Timeline volume controls for source recording audio and generated voiceover narration.
- Inline side-panel animation editing with live canvas updates.
- Local Piper narration generation in Video and Carousel modes for adding voiceover audio to exported videos.
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
- Adjust source recording audio and generated voiceover volume from the compact timeline toolbar.
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
- Generate local Piper voiceovers for every slide from visible text, OCR, or edited spoken scripts.
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
- Exported videos include device frame, background, shadows, trim, zoom animation, source audio volume, and optional Piper narration volume.
- In Carousel mode, export H.264 `.mp4` slideshow videos with optional project-level or per-slide Piper narration. Carousel video quality presets include **Draft** (very low quality, fastest timing checks), **Fast**, **Standard**, and **High**.
- Cancel active carousel video or bundle exports from the Export panel. Maya cancels the writer, removes incomplete output files, and reports stalled generated-frame exports with copyable diagnostics instead of leaving a 0-byte file.
- Export matching `.png` still image sets for carousel uploads.
- Export a bundle folder containing the video, still images, `carousel-brief.json`, `carousel-outline.json`, `slides.json`, `copy.txt`, and a handoff `README.txt`.

## Keyboard shortcuts

| Key | Action |
|---|---|
| <kbd>Space</kbd> | Play / pause |
| <kbd>M</kbd> | Mute / unmute source audio |
| <kbd>I</kbd> | Mark trim in |
| <kbd>O</kbd> | Mark trim out |
| <kbd>Delete</kbd> | Delete selected zoom event |
| <kbd>Command</kbd> + <kbd>D</kbd> | Duplicate selected zoom event |
| <kbd>Left</kbd> / <kbd>Right</kbd> | Scrub 0.25 s |
| <kbd>Shift</kbd> + <kbd>Left</kbd> / <kbd>Right</kbd> | Scrub 1 s |

## Tech stack

- SwiftUI and AppKit
- AVFoundation custom video composition
- AVAssetWriter generated-frame export for carousel videos, with concurrent video/audio writer inputs, cancel support, and stall detection
- Core Image and Metal compositing
- HEVC-with-alpha export support
- Swift Observation and async/await
- Sandboxed local video and image adoption for reliable preview and export access
- Local TTS integration for Piper and Kokoro through isolated Python environments
- Internal performance instrumentation with `os_signpost`, decoded image caching, and a Release benchmark mode

## Requirements

- macOS 26.2 or later
- Xcode 26.5 or later
- `.mp4` or `.mov` screen recording
- Images for Carousel mode, or a `.mp4`/`.mov` screen recording for Video mode
- Codex CLI installed and signed in for AI Director and carousel script cleanup
- A Codex account/subscription for local Codex CLI usage
- Optional: Local voice engines installed or refreshed through Maya's state-aware voice setup button for narration generation

## Releases

The latest installable Maya AI Studio release is **Maya AI Studio 2.0.2**:

[Download Maya AI Studio 2.0.2](https://github.com/AyoParadis/Maya/releases/tag/v2.0.2)

### Maya AI Studio 2.0.2

- Tidies the shared AI Voiceover panel in Video and Carousel with a compact preview row, inline engine/storage status, and a **More** menu for secondary actions.
- Keeps refresh, generated voiceover removal, and engine asset deletion available without showing every button at once.
- Centralizes the default AI voice engine as Kokoro for new Video and Carousel projects.

### Maya AI Studio 2.0.1

- Adds AI voice storage reporting in Video and Carousel voiceover panels, including total local voice asset usage and selected-engine usage.
- Adds per-engine voice asset cleanup for installed engine files, downloaded voice models, and cached previews while keeping generated project voiceovers intact.
- Makes Kokoro the default AI voice engine for new Video and Carousel projects.
- Removes Chatterbox and F5-TTS from the selectable voice engines because their local preview paths could hang the app; Maya now ships the stable local Piper and Kokoro options.

### Maya AI Studio 2

- Makes Carousel the default mode and refocuses it around imported slides, motion, local OCR, and one-button AI voiceovers.
- Adds local AI voiceover generation in both Video and Carousel, including Piper and Kokoro engine selection, automatic setup, custom voice IDs, cached previews, and compact status/error handling.
- Adds carousel per-slide voiceovers that read visible slide text, fall back to local Apple Vision OCR, generate one audio clip per slide, align clips on the timeline, and extend slide durations to fit narration.
- Adds editable slide narration in the inspector: copy detected text, edit the spoken script, clean OCR-damaged grammar and punctuation through the local Codex CLI, and regenerate audio from the edited script.
- Improves carousel OCR cleanup with local preprocessing, artifact filtering, watermark/handle filtering, and cached OCR results.
- Rebuilds Carousel export around a reliable generated-frame `AVAssetWriter` pipeline with explicit phases, real progress, cancellation, partial-file cleanup, stalled-export diagnostics, and video quality presets from **Draft** through **High**.
- Reorganizes Carousel export controls so Video, Images, and Bundle appear as equal format choices, with active export progress shown only while work is running.
- Adds timeline voiceover blocks and action menus for cards, voiceovers, and motion, available from the ellipsis button or a trackpad secondary click/Control-click, while keeping drag-to-reorder behavior so attached audio moves with its slide.
- Cleans up the app chrome and sidebars with a native macOS split-view sidebar, shared Video/Carousel AI Voiceover components, collapsible tinted sections, cleaner spacing, and the Video/Carousel switch in the titlebar.
- Removes the old Carousel Director/draft/approval workflow so Carousel is simpler, faster, and local-first: imported images stay on device, OCR runs locally, and Codex is only used for optional script cleanup.

### Maya AI Studio 1.0.9

- Adds Carousel Creative Studio for image carousel projects with motion preview, safe-zone review, AI voiceover generation, and export to video, still images, or structured bundles.
- Moves the Video/Carousel switch into the macOS titlebar and cleans up the AI voiceover sidebars so the app uses less vertical space and hides technical cache details.
- Makes Piper preview caching automatic and keeps carousel slide voiceover generation responsive with cached OCR results and per-slide failure handling.
- Improves carousel voiceover cleanup with editable spoken scripts, copyable detected text, stronger local OCR preprocessing, and regenerate-from-edited-script behavior.
- Improves carousel export feedback and performance by moving video export work off the UI thread, showing export phases, reusing decoded slide images, reusing writer pixel buffers during frame generation, and pumping carousel video/audio writer inputs concurrently.
- Reorganizes Carousel export controls so Video, Images, and Bundle appear as equal format choices, with the large progress treatment reserved only for active exports.
- Adds Carousel video quality presets, including a very low quality Draft mode for quick tests, plus cancel support and stalled-export diagnostics.
- Updates carousel mode to match video mode's macOS header behavior, with the app title, build label, and a single working sidebar toggle in the titlebar.
- Reuses the video editor's canvas background and timeline chrome in carousel mode so empty canvases and carousel tracks stay readable and visually consistent.
- Adds carousel import, rendering, image adoption, narration, and export services for the carousel workflow.
- Keeps carousel editing local-first: imported images stay on device, OCR runs locally, and Codex is only used for optional script cleanup.

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

## Performance benchmarks

Maya includes a local Release benchmark harness for safe performance work:

```bash
scripts/performance-benchmark.sh
```

The script builds the Release app with signing disabled, runs the timeline drag regression check, then launches Maya with `--maya-performance-benchmark`. The benchmark prints wall-clock timings for Carousel Draft/Standard/High exports and available narration preview engines; video import/export, thumbnail, and poster paths are instrumented in-app with `os_signpost` because those AVFoundation paths should be measured from the normal app lifecycle rather than the headless benchmark launcher. Performance spans are emitted under the `com.dlmapps.MayaAIStudio` subsystem for Instruments.

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
