# README media inventory

All assets target both READMEs. Reviewed locally; not uploaded.

| Asset | Dimensions | Bytes | Raw master under `capture/readme-2026-10/` | QA |
|---|---|---:|---|---|
| [meeting.png](../docs/media/readme-2026-10/meeting.png) | 1920 × 1440 | 1,396,519 | `native/meeting.png` | Passed |
| [prompter.png](../docs/media/readme-2026-10/prompter.png) | 1200 × 1440 | 885,231 | `prompter/prompter-dark-obsidian.png` | Passed |
| [screenshot-replies.png](../docs/media/readme-2026-10/screenshot-replies.png) | 1040 × 1080 | 538,072 | `native-take2/screenshot-replies.png` | Passed |

## Verification

- Each final PNG was opened and inspected. All windows and synthetic content are readable; no desktop, private conversation, token, or unrelated app appears.
- Export strips metadata and uses lossless PNG compression. Native glass and control rendering are retained.
- Both README previews load all four images (logo plus three screenshots), with no horizontal overflow at a 1,100 px browser viewport.
- Image descriptions are present in the Markdown/HTML source. The app’s own Markdown-to-HTML helper drops Markdown image alt text in its temporary preview; source alt text was checked separately.
- 70 relative document/image links and heading anchors resolve. Both repositories pass `git diff --check`.
- No video/audio files were produced. These images document synthetic sample states, not live transcription accuracy or model latency.

## Capture log

- Product: Tyto 0.6.0, source `7bba43a`; Xcode/Swift release build succeeded.
- Capture: ScreenCaptureKit, explicit window allowlist, cursor excluded. Meeting: 960 × 720 points. Reply panel: 520 × 540 points. Prompter: 600 × 720 points. PNGs are exported at 2×.
- Native take 1 supplies the meeting image; native take 2 reduces empty space around screenshot replies. Its meeting image was rejected because the pointer hovered another caption.
- The existing prompter and layout self-tests passed. Prompter source is the dark screenshot from the built-in sample-note test.
- Capture-only source is in `source/readme-2026-10/`; temporary builds, raw takes, and rendered README previews are ignored.

## Retrospective

- Prefer native window capture for SwiftUI controls; the existing ImageRenderer preview shows an unsupported text-field placeholder.
- Check pointer hover states even when the cursor itself is excluded.
- Keep stills when they communicate the workflow; no motion is needed for these three states.
- Sturnus media was deferred at the user’s request. Its README changes contain no new screenshots or video.
