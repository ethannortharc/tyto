<img src="docs/icon.png" width="128" alt="Tyto icon">

# Tyto

**English** | [中文](README.zh-CN.md)

A floating meeting assistant for macOS. It turns what people say into live captions with translations underneath, writes replies to any line you click, and drafts ready-to-paste answers from a screenshot of Teams, Slack or an email. **It stays invisible when you share your screen.**

*Tyto* is the barn owl genus — owls that hunt in the dark by sound alone. The Chinese name 听译 means "listen and translate".

## Contents

- [What it does](#what-it-does)
- [Install](#install)
- [First run](#first-run)
- [Everyday use](#everyday-use)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Models and services](#models-and-services)
- [Four ways to transcribe](#four-ways-to-transcribe)
- [Screenshot replies](#screenshot-replies)
- [Privacy: what leaves your Mac](#privacy-what-leaves-your-mac)
- [Build from source](#build-from-source)
- [Self-test commands](#self-test-commands)
- [Project layout](#project-layout)
- [Known limitations](#known-limitations)
- [License](#license)

## What it does

- **Hidden from screen sharing**: no Tyto window shows up when you share your screen in Zoom, Teams, Google Meet or Lark: overlay, replies panel, prompter, settings, pop-ups and menus ([how this was verified](docs/share-check.md), in Chinese). When you share the whole screen, *Settings → General → Hide Dock and Menu Bar Icons While Listening* hides Tyto's icons too.
- **Two audio channels**: *remote* is the meeting app's sound (system audio), *local* is your microphone (you and anyone in the room). With cloud recognition, speakers are told apart as Speaker 1, 2, 3 — click a name to rename it "Me" or "Alice".
- **Original and translation side by side**: pick your main language; lines in other languages get a smaller, fainter translation underneath, toggled with one click. Numbers, dates, amounts, names and your own keywords are highlighted; questions get a tag.
- **One-click replies**: click a line, select several, or reply to "the latest". Replies use the meeting background and the skills you picked, in three parts: what they mean, what you can say, and a translation of your reply.
- **Replies panel**: every reply stays in a column beside the overlay (⌃⌥B), newest first; delete any of them, and they are saved with the session. Under a meeting reply Tyto adds *What you said*: what the local speaker named "Me" said after that line and before the other side moved on, tagged *Followed*, *Rephrased* or *No reply*. Those captions get a small icon that jumps to the reply, and the exported notes include the comparison.
- **Prompter**: notes you prepared before the meeting, in their own see-through window (⌃⌥N) that you can put anywhere, e.g. right under the camera. Markdown, HTML or plain text; edits to the file show up right away. The bar on top always shows which section you're in and opens the outline; ⌃⌥↑ / ⌃⌥↓ jump between sections. With *Follow* on, the notes scroll to and highlight the paragraph you're reading out. When the other side asks about something that has its own section, a hint shows up at the bottom and ⌃⌥J jumps there. Matching runs on your Mac and also uses the translation, so English speech finds Chinese notes.
- **Three sizes**: the full overlay; a caption bar with just the latest line or two (with translation on, the lower line is the translation; drag the bottom edge for more lines); and a button bar with a single row of buttons for screenshot replies. Switch in the ⋯ menu or with ⌃⌥M; each size remembers its own position.
- **Meeting records**: *Save to Meeting Records* in the ⋯ menu keeps the meeting, and new lines are saved as they come. *Clear, New Meeting* asks first if the meeting isn't saved. The *Meeting Records* page in Settings lets you search, read each meeting's transcript and replies, export Markdown, continue a meeting, or delete it.
- **Screenshot replies**: ⌃⌥S captures the frontmost app (say, a Teams chat), works out who is asking what, and writes three replies you can paste; the first is already on your clipboard.
- **Bring any model**: configure each provider once, then choose a model for replies, vision, translation and transcription. Supports Anthropic, OpenAI, OpenRouter, Gemini, DeepSeek, Tongyi Qwen, SiliconFlow, Groq, Soniox, AssemblyAI, ElevenLabs, Deepgram, local Ollama / LM Studio, and any OpenAI-compatible endpoint.
- **Looks**: macOS 26 Liquid Glass with three palettes; background from fully clear to deep; adjustable font size.

## Install

Requires **macOS 26** or later on Apple silicon.

1. Download the latest `Tyto-x.y.z.dmg` from [Releases](../../releases) and open it.
2. Drag `Tyto` onto `Applications`, then open it from Applications.

The app is notarized by Apple, so it opens normally. If you open it from somewhere else, Tyto offers to move itself to Applications.

- **Updates**: Tyto checks GitHub once a day, downloads new versions in the background, and installs them the next time you quit, never mid-meeting. *Settings → General* turns this off or checks now; it's also under the Tyto menu → *Check for Updates…*. Every update is verified with Tyto's signing key before it's installed.
- **Always there**: Tyto has a Dock icon and a menu bar icon (the ear). Closing the settings window, minimizing it, or the × on the overlay keeps Tyto running with its shortcuts; quit from the menu bar icon (or ⌘Q). Clicking the Dock icon brings a hidden overlay back. *Settings → General* can open Tyto at login, or hide the Dock icon to keep only the menu bar icon.

## First run

The settings window opens on first launch. The interface follows your system language (Chinese or English); switch it any time from the menu bar icon → *Language*, or on the *Appearance* page.

1. **Models & services**: add a provider and its key (OpenRouter is a good start: one key covers Claude, GPT and Gemini), then pick a model under *Uses → Reply*. To try captions and translation only, skip this — on-device recognition and translation need no key.
2. **Translation**: pick your main language. With Apple's on-device translation, click *Download* to install the language pair (if it's missing, the overlay says so and its *Download* button takes you there).
3. Press **⌃⌥L** to start listening. macOS asks for **System Audio Recording** (the meeting app) and **Microphone** (the room).
4. For screenshot replies, enable Tyto under *System Settings → Privacy & Security → Screen & System Audio Recording*, then reopen Tyto.

The *Permissions & About* page shows each permission's status with a button to the right System Settings pane.

## Everyday use

- **Before a meeting**: in *Session*, write a few lines of background (purpose, attendees, your role, terms) and keywords, and tick the skills to use. Replies take all of it into account.
- **During the meeting**: ⌃⌥L starts listening. Click a line to select it, then *Reply* or ⌃⌥R. If the overlay is in the way, ⌃⌥M switches to the caption bar or the button bar.
- **After the meeting**: *Save to Meeting Records* in the ⋯ menu, or just *Clear, New Meeting* (it asks if the meeting isn't saved). Past meetings are under *Meeting Records* in Settings.
- **Answering messages**: press ⌃⌥S in Teams / Slack / Mail; a few seconds later the reply is on your clipboard — ⌘V and send. Want it different? Type an instruction under the reply ("decline politely", "in Chinese") and *Regenerate*.
- **Appearance**: the palette icon on the overlay changes theme, text color, background and font size. Text color defaults to *Auto*: black text on light glass over white documents and web pages, white text over darker things like meeting video; you can also fix it to white or black. Captions come in two styles, *Avatar* and *Line* (Settings → Appearance). Drag the edges to resize; *Reset size and position* in the menu restores the default — about 38% of the screen height and 26% of its width, on the right, clear of the meeting video.

## Keyboard shortcuts

They work while the meeting app is in front.

| Shortcut | Action |
|---|---|
| ⌃⌥L | Start / stop listening |
| ⌃⌥R | Reply (to selected lines, or the latest) |
| ⌃⌥S | Screenshot reply (frontmost app, or whole screen if set) |
| ⌃⌥A | Screenshot reply: select an area |
| ⌃⌥T | Show / hide the overlay |
| ⌃⌥M | Overlay size: Full → Caption Bar → Button Bar |
| ⌃⌥B | Show / hide the replies panel |
| ⌃⌥N | Show / hide the prompter |
| ⌃⌥↑ / ⌃⌥↓ | Prompter: previous / next section (while it's open) |
| ⌃⌥J | Prompter: go to the section they just mentioned |
| ⌃⌥P | Click-through on / off (clicks go to the window below; hold ⌥ over the overlay to use it meanwhile) |
| ⌃⌥Q | Quit |

## Models and services

*Settings → Models & services* has two parts:

- **Providers**: click *Add*, pick a template, paste the key. Keys are kept in the macOS keychain.
- **Uses**: reply, vision, translation and transcription each pick *provider + model*. The ⌄ next to a model lists the provider's models, or type a name.

| Template | Used for |
|---|---|
| Anthropic | Replies, vision (Claude) |
| OpenAI | Replies, vision, transcription, audio models |
| OpenRouter | Replies, vision, audio models; hundreds of models behind one key |
| Google Gemini | Replies, vision, audio models |
| DeepSeek | Replies |
| Tongyi Qwen | Replies, vision |
| SiliconFlow | Replies, vision, transcription |
| Groq | Replies, transcription (very fast Whisper) |
| Ollama / LM Studio (local) | Replies, vision; nothing leaves your Mac |
| Soniox / AssemblyAI / ElevenLabs / Deepgram | Real-time transcription |
| Custom | Any OpenAI-compatible endpoint (company gateway, self-hosted Whisper…) |

## Four ways to transcribe

Choose on the *Listening* page:

| Method | Providers | Notes |
|---|---|---|
| Apple on-device | — | Free and offline. One language per channel, no speaker labels |
| Real-time service | Soniox, AssemblyAI, ElevenLabs, Deepgram | Words appear as people speak; best for meetings. All but ElevenLabs label speakers |
| Transcription API | OpenAI, Groq, SiliconFlow, self-hosted Whisper | Sends each sentence after a 0.7 s pause; a second or two behind |
| Audio model | OpenRouter, Gemini and other models that accept audio | Same; handles mixed languages |

### Comparing real-time services

`--compare-speech` plays one recording to several services at once, at real-time speed, and writes a report: error rate (overall, Chinese characters, English words), whether speakers were told apart, time to first text, time from the end of a sentence to its final text, and price per hour.

```sh
echo "$SONIOX_KEY" | Tyto --set-key soniox        # keys go to the keychain; same for assemblyai, elevenlabs
scripts/speech-sample.py /tmp/sample               # optional: a synthetic four-person meeting with its reference text
Tyto --compare-speech /tmp/sample/meeting.wav --reference /tmp/sample/meeting.txt \
     --providers soniox,assemblyai,elevenlabs,apple:en-US --out /tmp/compare
```

The reference is the correct text, one line per sentence; write each line as `Speaker: text` to score speakers. `provider:model` picks a model (for example `assemblyai:universal-3-5-pro`); `apple:en-US` adds the free on-device engine as a baseline. A real meeting recording tells you more than the synthetic sample.

If you use speakers instead of headphones, the microphone also hears the remote side. With *Remove echo* on, a local line that starts while the remote side is talking and repeats most of its words is dropped; replies that quote the other side are kept.

## Screenshot replies

**What to capture**: the frontmost app (default; Tyto names the app), the whole screen, or an area (⌃⌥A). An image already on the clipboard works too.

**How the screenshot is read**:

| Mode | Where the image goes | Best for |
|---|---|---|
| Image to the reply model (default) | The reply model's provider | Best accuracy |
| Vision model first | Stays on your Mac if the vision model is local | Privacy with layout understanding |
| On-device OCR only | Stays on your Mac | Text only; no download; 0.3 s |

**Local vision models** (via [Ollama](https://ollama.com), one-click download on the *Screenshot replies* page) — all run on a 16 GB laptop:

| Model | Size | Notes |
|---|---|---|
| Qwen3-VL 2B (recommended) | 1.9 GB | Reads text and understands chats and emails |
| GLM-OCR 0.9B | 1.8 GB | Pure text extraction; no understanding |
| Qwen3-VL 4B | 3.3 GB | More accurate |

Apple's built-in text recognition (Vision) needs no download and is always available.

**Advanced: Baidu Unlimited-OCR-2 (MLX, optional).** Open-sourced on 2026-10-26 under MIT: a ~3.3B mixture-of-experts model (~0.5B active) built for document parsing. It reads text more accurately than Apple's OCR (in testing it got "I need", question marks and em dashes right where Vision did not) and returns each block's position. It doesn't run on Ollama; start a small local server:

```bash
uv venv --python 3.12 ~/.tyto-ocr
uv pip install --python ~/.tyto-ocr/bin/python "git+https://github.com/shuuul/mlx-vlm.git@223c2980fe4b48bd73faeb9e5bb1f1eacafffb49"
~/.tyto-ocr/bin/python scripts/unlimited-ocr-server.py      # first run downloads the 4-bit model (~2.5 GB); port 18780
```

Then add a *Custom Endpoint* provider at `http://127.0.0.1:18780/v1`, use it for *Vision* with model `mlx-community/Unlimited-OCR-2-4bit`, and set screenshot replies to *Vision Model First*.

Measured on an M4 Pro: 1.4 s for a chat screenshot, about 5 s for a dense mixed Chinese/English page, about 2.8 GB of memory; a full screenshot reply (local reading plus a cloud reply) took about 5 s. An M1 Pro with 16 GB runs it, likely about half as fast. On a CPU-only Linux box the official code also runs (its Triton kernels are only used on NVIDIA GPUs), but it needs ~7 GB of RAM in bf16 and likely tens of seconds per screenshot — too slow during a meeting; on Linux with an NVIDIA GPU, the official SGLang setup is fastest.

## Privacy: what leaves your Mac

| Data | Where it goes |
|---|---|
| Meeting audio | Nowhere with Apple on-device recognition; to your chosen service with cloud recognition |
| Caption text | Nowhere with Apple translation; to your chosen model for replies and model translation |
| Prompter notes | Only read on your Mac; Follow and hints match words locally |
| Update checks | Once a day Tyto downloads `appcast.xml` from GitHub Releases; nothing about you or your Mac is sent |
| What's behind the overlay and prompter | With *Auto* text color, every 2.5 s that area is scaled to 16×16 to get its average brightness, on your Mac only, never saved; not read when the text color is fixed |
| Screenshots | Depends on the reading mode above; nowhere with a local model or OCR only |
| Keys | Only in this Mac's keychain |
| Transcripts | Only in `~/Library/Application Support/Tyto/sessions/` |

## Build from source

Requires Xcode 26 (Swift 6.2).

```bash
scripts/build-app.sh               # development build: build/Tyto.app (Apple Development signing)
open build/Tyto.app
scripts/build-app.sh ShareCheck    # screen-share check app: build/TytoShareCheck.app
scripts/release.sh notes.md        # release: Developer ID signing + notarization → dist/Tyto-<version>.dmg, .zip, appcast.xml
scripts/test-update.sh             # real auto-update run: an old build finds, verifies and installs a new one; a tampered one is refused
swift scripts/make-icon.swift owl icon.png && scripts/build-icon.sh icon.png   # redraw the app icon
```

Updates are signed with an EdDSA key kept outside the repository (`~/.config/tyto-release/sparkle-ed25519-private.key` by default; the public key is `SUPublicEDKey` in `Resources/Tyto-Info.plist`). Builds in `build/` don't update themselves.

macOS remembers permissions by code signature; signing with a fixed certificate keeps them across rebuilds.

## Self-test commands

Check each part without a meeting (arguments to `build/Tyto.app/Contents/MacOS/Tyto`):

| Argument | Checks |
|---|---|
| `--selftest-speech <audio> [--locale en-US]` | Transcribe a file with the configured method, then translate |
| `--selftest-reply` | Reply to a sample conversation with the reply model |
| `--selftest-screenshot <image> [--app name]` | The full screenshot-reply flow |
| `--selftest-capture frontWindow` | Capture the frontmost app and name it |
| `--selftest-models <provider id>` | List a provider's models |
| `--selftest-settings` | Print current settings (read only) |
| `--selftest-echo` / `--selftest-deepgram` | Echo rule; Deepgram message parsing |
| `--selftest-streaming` | AssemblyAI and ElevenLabs message parsing; scoring used by `--compare-speech` |
| `--compare-speech <audio> [--reference text] [--providers list] [--hints en,zh] [--out dir]` | Several real-time services on the same recording; see *Comparing real-time services* |
| `--render-preview <dir>` / `--render-settings <dir>` | Draw the overlay / settings pages to images (no screen capture) |
| `--selftest-glass <dir> [--light] [--auto]` | Real glass rendering (captures only Tyto's own windows); `--light` over a white page, `--auto` with the automatic text color |
| `--selftest-backdrop` | Auto text color: measure a white page and a meeting backdrop, check white vs. black |
| `--selftest-followup` | *What you said* after a suggested reply: which lines, followed / rephrased / no reply; which side the replies panel goes |
| `--selftest-sharing [folder]` | Screen sharing: puts the overlay, replies panel, prompter, a popover and an open menu on screen, captures the whole display like a meeting app, and checks none of them appear (plus a control that must appear) |
| `--selftest-records` | Meeting records: save, auto-update, clear, continue, relaunch, old files, delete, export (in a temporary folder, never your real records) |
| `--selftest-layouts [folder]` | The three overlay sizes: dimensions, line-by-line resizing, font size changes, where the replies panel goes, remembered positions; with a folder, on-screen screenshots too |
| `--selftest-prompter [folder]` | Prompter in a real window: outline, Follow, hints (English and Chinese notes), other people's HTML colors, reload on edit; with a folder, screenshots too |

Add `--settings-json '{...}'` to any of them to override settings without saving. The run log is at `~/Library/Logs/Tyto.log`.

## Project layout

```
Sources/Tyto/
  App/        launch, menus, Dock, global shortcuts, auto-update (Sparkle), move to Applications, open at login
  Audio/      system audio (Core Audio process tap), microphone, resampling
  Speech/     Apple SpeechAnalyzer, Soniox, AssemblyAI, ElevenLabs, Deepgram, pause-based chunking
  Translate/  Apple on-device translation, model translation
  Screenshot/ frontmost app / screen / area capture, on-device OCR
  LLM/        Claude / OpenAI-compatible / Ollama clients, model lists, prompts
  Model/      session, settings (providers + uses), skills
  Prompter/   prepared notes: Markdown → HTML, web view, Follow and hint matching
  UI/         overlay, themes, highlighting, settings window
  Dev/        self-tests, run log
Sources/ShareCheck/   screen-share check app
```

## Known limitations

- Remote audio is every app's sound except Tyto's — don't play music or videos during a meeting.
- Things macOS draws for Tyto can show in a screen share: the file chooser when opening prompter notes, permission and Keychain prompts, and Tyto's menus at the top of the screen while Tyto is the active app. Tyto's own windows, pop-ups and pull-down menus don't (`--selftest-sharing` checks this).
- Soniox, AssemblyAI, ElevenLabs and Deepgram follow their published protocols and pass against local mock servers, but haven't run through long real meetings yet.
- Hiding during a Google Meet share in Chrome hasn't been tested directly (Chrome uses the same ScreenCaptureKit path, which has been).

## License

MIT — see [LICENSE](LICENSE).

Tyto bundles [Sparkle](https://sparkle-project.org) (MIT) for updates and [swift-markdown](https://github.com/swiftlang/swift-markdown) (Apache 2.0) with [cmark-gfm](https://github.com/swiftlang/swift-cmark) (BSD-2) for the prompter; their licenses ship inside the app under `Contents/Resources/Licenses`.

© 2026 Ethan H.B. Zhou
