# Visual Coach Agent

A persistent, local AI coach for macOS that understands the current screen and
visually guides you — arrows, rings, highlights, and step labels drawn on a
click-through overlay — without switching to a chat app.

- **Version:** 1.0.1 (build 11)
- **Platform:** macOS 14+
- **Bundle ID:** `local.codex.visualcoach.agent`

By default everything runs on your Mac: screenshots stay local, requests go
only to a local [Ollama](https://ollama.com) server, and no accounts or API
keys are needed. An optional, off-by-default Claude API backend adds
persistent conversation context — see "Claude backend" below.

## Hotkeys

| Shortcut | Action |
| --- | --- |
| ⌃⌥Space | Analyze the screen under the pointer and show guidance |
| ⌃⌥D | Draw & Ask — mark a region, then ask about it |
| ⌃⌥H | Hide guidance |

The menu-bar item (✨) offers the same actions plus **Ask a Question…** (for
when automatic inference is wrong) and **Clear Learned Context**.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`)
- Ollama running locally with a multimodal model:

  ```sh
  ollama pull gemma4
  ollama serve   # if not already running
  ```

  The model name and endpoint are constants at the top of
  `Sources/VCOllamaClient.m` (`gemma4` @ `http://127.0.0.1:11434/api/chat`).
  Swap in any multimodal Ollama model you have pulled.

## Build & run

```sh
make        # builds build/VisualCoach.app (ad-hoc signed)
make run    # builds and launches
```

On first use, grant **Screen Recording** permission when macOS prompts
(System Settings → Privacy & Security → Screen Recording), then relaunch.

## How it works

1. A Carbon global hotkey triggers a capture of the display under the mouse
   pointer via ScreenCaptureKit, along with the foreground app name and window
   title. The clean screenshot is taken *before* any drawing or progress
   overlays appear.
2. Apple Vision OCR extracts visible text with normalized coordinates.
3. The screenshot, metadata, OCR text (clearly delimited as **untrusted** to
   reduce prompt injection), any prior coaching for the same window, and your
   question are sent to local Ollama with structured-JSON output requested.
4. The response is validated: out-of-range coordinates are discarded, OCR
   coordinates replace model coordinates when the label matches visible text,
   and text-based annotations OCR cannot verify are not displayed.
5. Guidance renders on a transparent, always-on-top, click-through overlay:
   curved arrows, numbered action labels, target rings, highlighted regions,
   and context/goal cards. The app never clicks, drags, or types for you.

### Draw & Ask

⌃⌥D opens a full-screen drawing canvas. Circle, underline, point, or draw a
question mark over anything; press **Return** (or click **Ask About Mark**)
and type your question. The normalized bounds of the marked region are sent
with the question. **Escape** or **Cancel** exits.

### Claude backend (optional)

By default everything runs locally through Ollama. Enabling **Use Claude
(Cloud)** in the menu switches coaching to the Claude API
(`claude-opus-4-8`) with two upgrades:

- **Persistent conversation context** — each coaching exchange for a window
  is kept as real conversation history (up to six exchanges per window,
  stored locally) and replayed on the next trigger, so follow-ups remember
  what was already discussed.
- **Schema-enforced output** — structured outputs guarantee the guidance
  JSON is always valid.

Set your key via **Set Claude API Key…** (stored in the macOS Keychain;
`ANTHROPIC_API_KEY` in the environment also works when launching from a
terminal). **Privacy trade-off:** with this backend enabled, screenshots are
sent to `api.anthropic.com` instead of staying on the Mac. It is off by
default; note that this is a conversation with the Claude API — it does not
connect to or inherit history from the Claude app or claude.ai.

### Memory

Up to six coaching results are kept per foreground window context (app +
window title, so unrelated browser tabs don't share context), persisted in
`NSUserDefaults`. Erase them anytime with **Clear Learned Context**.

## Project layout

```
Sources/
  main.m                    App entry point
  VCAppDelegate.*           Menu-bar item and action wiring
  VCHotkeyManager.*         Carbon global hotkeys
  VCScreenCapture.*         ScreenCaptureKit capture + window metadata
  VCOCRService.*            Vision OCR
  VCOllamaClient.*          Local Ollama /api/chat client
  VCCoachingResult.*        Response parsing, validation, OCR grounding
  VCOverlayController.*     Click-through guidance overlay
  VCDrawCanvasController.*  Draw & Ask canvas
  VCMemoryStore.*           Per-window coaching memory (NSUserDefaults)
  VCCoachEngine.*           Pipeline orchestration
Resources/Info.plist
Makefile
```

## Current limitations

- Screenshot-on-trigger, not continuous monitoring.
- Icon-only targets are harder to ground because OCR requires text.
- Model accuracy and latency depend on the local model and hardware.
- Memory is lightweight summaries, not a semantic vector database.
- No automatic clicking, dragging, or keyboard control.
- No launch-at-login support yet.
- Ad-hoc signed; not notarized for public distribution.
- Drawing is sent to the model as a marked region, not the original stroke
  geometry.
