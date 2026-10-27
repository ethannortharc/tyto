# Tyto 听译

开会用的 macOS 桌面工具。透明悬浮窗永远在最前面，共享屏幕时对方看不见；把会议里的话实时转成文字，原文、译文对照显示；点一下就能针对某几句话生成回复建议。

Tyto 是仓鸮属的拉丁名——仓鸮在黑暗里只靠听声音就能定位。

## 能做什么

- **悬浮窗**：半透明，层级在普通窗口之上，盖得住全屏的会议软件；共享整个屏幕时对方看不见（验证见 `docs/share-check.md`）。本 app 的所有窗口（包括"会话与设置"）都不会被共享出去。
- **两路声音**：
  - 远端：会议软件里传来的声音（录系统声音）。
  - 本地：麦克风收到的声音，也就是你和会议室里其他人。默认自动选麦克风：跟系统默认走，但默认输入是 BlackHole 这类虚拟声卡时，改用第一个真实的麦克风；也可以在「模型与服务」里指定。
  字幕里标出每句来自哪一路；用云端识别时，同一路里还会分出说话人 1、2……。点说话人标签可以改名，比如改成「我」。
- **原文 / 译文对照**：每句话下面是译文，悬浮窗顶部的「翻译」一键开关。
- **回复建议**：点一句或多选几句，再点「回复」；或者直接「回复最近的话」。回复会结合这场会议的背景和勾选的技能，分三段：对方的意思、建议回复（可以直接说出口）、中文对照。
- **会话**：会议名称、背景、技能、说话人名字；记录自动保存，可以导出 Markdown。
- **模型可以换**：

  | 用途 | 可选 |
  |---|---|
  | 语音识别 | Apple 本机（免费、不联网、不区分说话人）；Soniox 云端（区分说话人、多语言自动识别） |
  | 翻译 | Apple 本机（免费、不联网）；大模型 |
  | 回复建议 | Anthropic Claude；OpenAI 兼容接口（OpenAI、DeepSeek、通义、Gemini、OpenRouter、Ollama…） |

## 运行

要求 macOS 26。

```bash
scripts/build-app.sh      # 得到 build/Tyto.app
open build/Tyto.app
```

菜单栏会出现一个耳朵图标，屏幕右下方出现悬浮窗。第一次启动会打开「会话与设置」。

第一次用要给的权限：

| 权限 | 什么时候问 | 用来 |
|---|---|---|
| 录制系统声音 | 第一次开始听 | 远端（会议软件里的声音） |
| 麦克风 | 第一次开始听 | 本地（会议室里的声音） |
| 识别模型下载 | 本机识别第一次用某种语言时自动下载 | 本机语音识别 |
| 翻译语言下载 | 在「模型与服务 → 翻译」里点「下载本机翻译语言」 | 本机翻译 |

大模型和 Soniox 的 API key 在「模型与服务」里填，存在钥匙串里。

## 快捷键

| 快捷键 | 作用 |
|---|---|
| ⌃⌥L | 开始 / 停止听 |
| ⌃⌥T | 显示 / 隐藏悬浮窗 |
| ⌃⌥R | 回复（有选中的句子就回复选中的，否则回复最近的话） |
| ⌃⌥P | 点击穿透（悬浮窗不挡鼠标）开 / 关 |

## 自测（不用开会）

```bash
# 本机识别 + 本机翻译：拿一段音频文件过一遍
say -o /tmp/test.aiff "Could we move the launch to the second week of December?"
build/Tyto.app/Contents/MacOS/Tyto --selftest-speech /tmp/test.aiff --locale en-US --target zh-Hans

# 去回声的判断：回声要去掉，复述、插话要保留
build/Tyto.app/Contents/MacOS/Tyto --selftest-echo

# 用设置里的大模型，对一段示例对话生成回复
build/Tyto.app/Contents/MacOS/Tyto --selftest-reply

# 启动后直接开始听
open build/Tyto.app --args --start
```

运行日志在 `~/Library/Logs/Tyto.log`：每一路有没有启动、有没有收到声音、识别出的每一句、出的错。

## 数据放在哪

| 内容 | 位置 |
|---|---|
| 设置 | `defaults read com.giomni.tyto` |
| API key | 钥匙串，服务名 `com.giomni.tyto` |
| 技能 | `~/Library/Application Support/Tyto/skills/*.md` |
| 会话记录 | `~/Library/Application Support/Tyto/sessions/`（`current.json` 是当前这场） |

## 代码结构

```
Sources/Tyto/
  App/        启动、菜单栏、全局快捷键
  Audio/      系统声音（Core Audio 进程音频捕获）、麦克风、重采样到 16kHz
  Speech/     识别引擎：Apple SpeechAnalyzer、Soniox WebSocket
  Translate/  Apple 本机翻译、大模型翻译
  LLM/        Claude / OpenAI 兼容接口（流式）、回复提示词
  Model/      会话（分句、翻译、回复、保存）、设置、技能
  UI/         悬浮窗、会话与设置窗口
  Dev/        自测、运行日志
Sources/ShareCheck/   共享屏幕验证程序（scripts/build-app.sh ShareCheck）
```

## 还没做 / 已知限制

- 模型还没定，现在默认 Apple 本机识别 + Apple 本机翻译 + Claude Opus 5.5（effort low）。
- Soniox 云端识别按官方协议写好了，还没用真的 key 测过。
- 本机识别不区分说话人，一路只认一种语言（在设置里分别指定远端、本地的语言）。
- 远端录的是除 Tyto 以外所有 app 的声音，开会时别放音乐和视频。
- 悬浮窗里的下拉菜单是系统画的，共享屏幕时可能被看到（只在弹出的那一下）。
- 用外放开会时，麦克风也会收到对方的声音。这部分按文字去重：本地某句是在远端说话的同时开始的、并且七成以上的词和远端一样，就当回声去掉。复述对方的话回答（在对方说完之后）不受影响。戴耳机最稳。

© 2026 Ethan H.B. Zhou
