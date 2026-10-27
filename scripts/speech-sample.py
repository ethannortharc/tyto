#!/usr/bin/env python3
"""用系统语音合成一段四个人的会议录音（英文、中文、中英混说），给 Tyto --compare-speech 用。

    scripts/speech-sample.py <输出文件夹>

生成 meeting.wav（16 kHz 单声道）和 meeting.txt（参考稿，每行「说话人: 文字」）。
合成的声音比真人干净，只适合先看各家大致的差别；要看真实效果，换成一段真实会议录音和它的正确文字。
"""
import os
import subprocess
import sys
import tempfile
import wave

RATE = 16000

# (说话人, macOS 声音, 文字, 说完后停多久秒)
LINES = [
    ("Sarah", "Samantha", "Good morning everyone. Let's start with the launch timeline for the new dashboard.", 1.2),
    ("Daniel", "Daniel", "Sure. The backend work is mostly done, but we're still waiting on the security review.", 1.0),
    ("婷婷", "Tingting", "我这边前端基本做完了，就是 login 页面还有几个 bug 要修。", 0.8),
    ("Sarah", "Samantha", "Do you think you can finish those before Friday?", 0.7),
    ("婷婷", "Tingting", "应该可以，不过我需要 Daniel 那边先把 API 的文档发给我。", 1.1),
    ("Daniel", "Daniel", "No problem, I'll send the documentation right after this meeting.", 1.5),
    ("小周", "Eddy (Chinese (China mainland))", "我补充一下，测试环境下周一才能准备好，所以 QA 可能要往后推两天。", 1.0),
    ("Sarah", "Samantha", "That's fine. Can we still keep the demo with the customer next Wednesday?", 0.9),
    ("小周", "Eddy (Chinese (China mainland))", "可以的，demo 用 staging 环境就行，不影响。", 1.6),
    ("Daniel", "Daniel", "One more thing, the marketing team asked whether we can add a dark mode option.", 1.0),
    ("婷婷", "Tingting", "dark mode 的话工作量不大，但是要和设计师再确认一下颜色。", 1.2),
    ("Sarah", "Samantha", "Okay, let's put it on the list for the next sprint. Thanks everyone, that's all for today.", 0.5),
]


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    frames = bytearray(b"\x00\x00" * RATE)  # 开头一秒静音
    with tempfile.TemporaryDirectory() as tmp:
        for index, (_, voice, text, pause) in enumerate(LINES):
            path = os.path.join(tmp, f"{index}.wav")
            subprocess.run(["say", "-v", voice, "--file-format=WAVE", f"--data-format=LEI16@{RATE}", "-o", path, text], check=True)
            with wave.open(path) as clip:
                assert clip.getframerate() == RATE and clip.getnchannels() == 1 and clip.getsampwidth() == 2
                frames += clip.readframes(clip.getnframes())
            frames += b"\x00\x00" * int(RATE * pause)
    with wave.open(os.path.join(out, "meeting.wav"), "wb") as result:
        result.setnchannels(1)
        result.setsampwidth(2)
        result.setframerate(RATE)
        result.writeframes(bytes(frames))
    with open(os.path.join(out, "meeting.txt"), "w", encoding="utf-8") as reference:
        reference.write("".join(f"{speaker}: {text}\n" for speaker, _, text, _ in LINES))
    print(f"{out}/meeting.wav（{len(frames) / 2 / RATE:.0f} 秒）和 meeting.txt")


if __name__ == "__main__":
    main()
