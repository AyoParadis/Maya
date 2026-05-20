# Agent Instructions

- Always use Biome for formatting code when the changed file type is supported by Biome.
- Always update the primary `README.md` on `main` for documentation and release changes; do not leave README updates only on feature or Codex branches.
- Before starting a new Playwright/browser automation session, close or reuse any existing Playwright sessions so duplicate browsers do not remain open.
- When Playwright/browser automation is no longer needed, close the Playwright session and any browser processes it started before ending the task.
