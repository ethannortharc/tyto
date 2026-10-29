# README media · October 2026

## Brief and product context

Show how Tyto 0.6.0 turns a bilingual meeting into readable captions and a reply,
then show prepared notes and screenshot replies. Audience: people evaluating the
macOS app on its English or Chinese README. Base source: `7bba43a`.

Only synthetic Northwind/Acme conversations and built-in sample notes are used.
No microphone, meeting app, model service, private transcript, or real chat is used.
The source build adds a documentation-only capture entry point in an ignored copy;
the production app sources are unchanged. No external publication is part of this run.

## Shot list

| Shot | Action and expected result | Hold | Source |
|---|---|---|---|
| Meeting | Show built-in bilingual captions, selected question, and its sample reply in the native overlay and sidecar | 2 s | `<take>/meeting.png` |
| Screenshot replies | Show three sample responses in the native sidecar | 2 s | `<take>/screenshot-replies.png` |
| Prompter | Run the built-in prompter test; capture section navigation, a highlighted paragraph, and the next-section hint | Built-in timing | `prompter/prompter-dark-obsidian.png` |

## Reproduction

Run from the repository root on an unlocked macOS 26 desktop with Xcode 26,
the app's existing Screen Recording permission, and the signing identity used by
`scripts/build-app.sh`. The display must fit a 960 × 720 point stage.

1. **Deterministic:** `python3 .demo-studio/source/readme-2026-10/capture.py`.
   It copies the source into `.demo-studio/_production/readme-*`, adds only the
   capture harness, builds it, and captures an explicit allowlist of Tyto windows.
   It does not capture the desktop or other apps. It exits if a required window is absent.
2. **Deterministic:** `scripts/build-app.sh`, then
   `build/Tyto.app/Contents/MacOS/Tyto --selftest-prompter .demo-studio/capture/readme-2026-10/prompter --settings-json '{"language":"zh"}'`.
3. **Checkpoint:** inspect every lossless PNG at full size and at README width.
   Reject missing windows, unsupported control rendering, clipped key content, or
   unrelated UI. Keep the pointer outside the stage so hovering does not highlight
   an extra caption. The original `--render-preview` result is not the final source:
   ImageRenderer cannot render the native instruction text field correctly.
4. **Deterministic:** export with `bash .demo-studio/source/readme-2026-10/export.sh <take-directory>`.
   A second argument optionally selects a different take for the meeting image.
5. **Checkpoint:** inspect the exported images and verify README image paths.

Raw masters remain unchanged in `.demo-studio/capture/readme-2026-10/` (ignored).
Final assets live in `docs/media/readme-2026-10/`. No audio or video is recorded.
If permission is missing, stop capture without changing privacy permissions.
