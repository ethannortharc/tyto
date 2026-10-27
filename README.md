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

- **Hidden from screen sharing**: the overlay and settings window don't appear when you share your screen in Zoom, Teams, Google Meet or Lark ([how this was verified](docs/share-check.md), in Chinese).
- **Two audio channels**: *remote* is the meeting app's sound (system audio), *local* is your microphone (you and anyone in the room). With cloud recognition, speakers are told apart as Speaker 1, 2, 3 — click a name to rename it "Me" or "Alice".
- **Original and translation side by side**: pick your main language; lines in other languages get a smaller, fainter translation underneath, toggled with one click. Numbers, dates, amounts, names and your own keywords are highlighted; questions get a tag.
- **One-click replies**: click a line, select several, or reply to "the latest". Replies use the meeting background and the skills you picked, in three parts: what they mean, what you can say, and a translation of your reply.
- **Replies panel**: every reply stays in a column beside the overlay (⌃⌥B), newest first; delete any of them, and they are saved with the session. Under a meeting reply Tyto adds *What you said*: what the local speaker named "Me" said after that line and before the other side moved on, tagged *Followed*, *Rephrased* or *No reply*. Those captions get a small icon that jumps to the reply, and the exported notes include the comparison.
- **Screenshot replies**: ⌃⌥S captures the frontmost app (say, a Teams chat), works out who is asking what, and writes three replies you can paste; the first is already on your clipboard.
- **Bring any model**: configure each provider once, then choose a model for replies, vision, translation and transcription. Supports Anthropic, OpenAI, OpenRouter, Gemini, DeepSeek, Tongyi Qwen, SiliconFlow, Groq, Soniox, Deepgram, local Ollama / LM Studio, and any OpenAI-compatible endpoint.
- **Looks**: macOS 26 Liquid Glass with three palettes; background from fully clear to deep; adjustable font size.

## Install

Requires **macOS 26** or later on Apple silicon.

1. Download the latest `Tyto-x.y.z.zip` from [Releases](../../releases) and unzip it.
2. Move `Tyto.app` to Applications and open it.

The app is notarized by Apple, so it opens normally. Tyto has no Dock icon — look for the ear in the menu bar.

## First run

The settings window opens on first launch. The interface follows your system language (Chinese or English); switch it any time from the menu bar icon → *Language*, or on the *Appearance* page.

1. **Models & services**: add a provider and its key (OpenRouter is a good start: one key covers Claude, GPT and Gemini), then pick a model under *Uses → Reply*. To try captions and translation only, skip this — on-device recognition and translation need no key.
2. **Translation**: pick your main language. With Apple's on-device translation, click *Download* to install the language pair (if it's missing, the overlay says so and its *Download* button takes you there).
3. Press **⌃⌥L** to start listening. macOS asks for **System Audio Recording** (the meeting app) and **Microphone** (the room).
4. For screenshot replies, enable Tyto under *System Settings → Privacy & Security → Screen & System Audio Recording*, then reopen Tyto.

The *Permissions & About* page shows each permission's status with a button to the right System Settings pane.

## Everyday use

- **Before a meeting**: in *Session*, write a few lines of background (purpose, attendees, your role, terms) and keywords, and tick the skills to use. Replies take all of it into account.
- **During the meeting**: ⌃⌥L starts listening. Click a line to select it, then *Reply* or ⌃⌥R.
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
| ⌃⌥B | Show / hide the replies panel |
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
| Soniox / Deepgram | Real-time transcription |
| Custom | Any OpenAI-compatible endpoint (company gateway, self-hosted Whisper…) |

## Four ways to transcribe

Choose on the *Listening* page:

| Method | Providers | Notes |
|---|---|---|
| Apple on-device | — | Free and offline. One language per channel, no speaker labels |
| Real-time service | Soniox, Deepgram | Words appear as people speak; speaker labels; best for meetings |
| Transcription API | OpenAI, Groq, SiliconFlow, self-hosted Whisper | Sends each sentence after a 0.7 s pause; a second or two behind |
| Audio model | OpenRouter, Gemini and other models that accept audio | Same; handles mixed languages |

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
| What's behind the overlay | With *Auto* text color, every 2.5 s that area is scaled to 16×16 to get its average brightness, on your Mac only, never saved; not read when the text color is fixed |
| Screenshots | Depends on the reading mode above; nowhere with a local model or OCR only |
| Keys | Only in this Mac's keychain |
| Transcripts | Only in `~/Library/Application Support/Tyto/sessions/` |

## Build from source

Requires Xcode 26 (Swift 6.2).

```bash
scripts/build-app.sh               # development build: build/Tyto.app (Apple Development signing)
open build/Tyto.app
scripts/build-app.sh ShareCheck    # screen-share check app: build/TytoShareCheck.app
scripts/release.sh                 # release: Developer ID signing + notarization → dist/Tyto-<version>.zip
```

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
| `--render-preview <dir>` / `--render-settings <dir>` | Draw the overlay / settings pages to images (no screen capture) |
| `--selftest-glass <dir> [--light] [--auto]` | Real glass rendering (captures only Tyto's own windows); `--light` over a white page, `--auto` with the automatic text color |
| `--selftest-backdrop` | Auto text color: measure a white page and a meeting backdrop, check white vs. black |
| `--selftest-followup` | *What you said* after a suggested reply: which lines, followed / rephrased / no reply; which side the replies panel goes |

Add `--settings-json '{...}'` to any of them to override settings without saving. The run log is at `~/Library/Logs/Tyto.log`.

## Project layout

```
Sources/Tyto/
  App/        launch, menu bar, global shortcuts
  Audio/      system audio (Core Audio process tap), microphone, resampling
  Speech/     Apple SpeechAnalyzer, Soniox, Deepgram, pause-based chunking
  Translate/  Apple on-device translation, model translation
  Screenshot/ frontmost app / screen / area capture, on-device OCR
  LLM/        Claude / OpenAI-compatible / Ollama clients, model lists, prompts
  Model/      session, settings (providers + uses), skills
  UI/         overlay, themes, highlighting, settings window
  Dev/        self-tests, run log
Sources/ShareCheck/   screen-share check app
```

## Known limitations

- Remote audio is every app's sound except Tyto's — don't play music or videos during a meeting.
- Pull-down menus on the overlay are drawn by the system and may show briefly in a screen share while open.
- Soniox and Deepgram follow their published protocols but haven't run through long real meetings yet.
- Hiding during a Google Meet share in Chrome hasn't been tested directly (Chrome uses the same ScreenCaptureKit path, which has been).

## License

MIT — see [LICENSE](LICENSE).

© 2026 Ethan H.B. Zhou
