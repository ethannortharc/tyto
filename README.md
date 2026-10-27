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
- **关键字高亮**：数字、日期、金额（金色）、人名地名机构（蓝色）自动高亮；会话里设的关键词用粉色底标出；提问的句子打上「提问」标记。全在本机算。
- **截屏回复**：⌃⌥S 直接截最前面的 App 窗口（比如 Teams 的聊天、一封邮件），也可以设成截整个屏幕；⌃⌥A 框选一块。Tyto 会认出截的是哪个 App。读懂截图有三种方式：
  - 图片直接给回复模型（默认，最准）；
  - 先用看图模型读图：看图模型把截图整理成文字，再交给回复模型。看图模型选 Ollama 本机模型，截图就不出这台 Mac；
  - 只用本机 OCR（系统自带的文字识别，免下载、不联网）。

  结果是一句场景说明 + 三个能直接粘贴的回复（推荐、换个取向、婉拒或推迟），第一个自动进剪贴板，⌘V 就能发；可以补一句"想怎么回"再重新生成。也可以用剪贴板里已有的图片。
- **本机看图模型**：设置里列出推荐的小模型（Qwen3-VL 2B 1.9 GB、GLM-OCR 0.9B 1.8 GB、Qwen3-VL 4B 3.3 GB），通过 Ollama 一键下载，带进度。系统自带的文字识别不用下载。
- **模型统一配置**：服务商只配一次（地址、key），回复、看图、翻译、语音识别四个用途都从里面选"服务商 + 模型"，模型可以从服务商读列表。内置模板：Anthropic、OpenAI、OpenRouter、Google Gemini、DeepSeek、通义千问、硅基流动、Groq、Ollama 本机、LM Studio 本机、Soniox、Deepgram，以及任意 OpenAI 兼容的自定义接口。
- **外观**：macOS 26 的玻璃材质，三套配色（曜石、极光、香槟）；底色浓度最左边完全透明（只剩文字），往右先出现玻璃、再加深底色，调淡时文字自动加阴影；字号可调。悬浮窗顶部的调色盘图标随时改，设置里有实时预览。
- **设置窗口**：系统设置风格，左侧图标分页——会议（会话、技能）、功能（听写、翻译、截屏回复）、设置（模型与服务、外观、快捷键、权限与关于），权限页显示每项权限的状态，一键打开对应的系统设置。
- **模型可以换**：

  | 用途 | 可选 |
  |---|---|
  | 语音识别 | Apple 本机（免费、不联网）；实时识别服务 Soniox、Deepgram（边说边出字，分得出说话人）；语音转写接口（OpenAI、Groq、硅基流动、自建 Whisper：按停顿一句一句传）；让能听音频的模型听写（OpenRouter、Gemini） |
  | 翻译 | Apple 本机（免费、不联网）；任意大模型 |
  | 回复建议 | 任意大模型（Claude、GPT、Gemini、DeepSeek、通义、OpenRouter 上的模型、本机 Ollama / LM Studio） |
  | 截屏看图 | 任意能看图的模型；本机推荐 Qwen3-VL 2B（1.9 GB）或 GLM-OCR（1.8 GB），16 GB 内存的笔记本也跑得动 |

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
| 屏幕录制 | 第一次用 ⌃⌥S / ⌃⌥A 截图 | 截屏回复（用剪贴板里的图片不需要） |

大模型和 Soniox 的 API key 在「模型与服务」里填，存在钥匙串里。

## 快捷键

| 快捷键 | 作用 |
|---|---|
| ⌃⌥L | 开始 / 停止听 |
| ⌃⌥T | 显示 / 隐藏悬浮窗 |
| ⌃⌥R | 回复（有选中的句子就回复选中的，否则回复最近的话） |
| ⌃⌥S | 截屏回复：截最前面的 App（设置里可以改成整个屏幕） |
| ⌃⌥A | 截屏回复：框选一块 |
| ⌃⌥P | 点击穿透（悬浮窗不挡鼠标）开 / 关 |
| ⌃⌥Q | 退出（悬浮窗右上角的 × 也是退出） |

## 自测（不用开会）

```bash
# 本机识别 + 本机翻译：拿一段音频文件过一遍
say -o /tmp/test.aiff "Could we move the launch to the second week of December?"
build/Tyto.app/Contents/MacOS/Tyto --selftest-speech /tmp/test.aiff --locale en-US --target zh-Hans

# 去回声的判断：回声要去掉，复述、插话要保留
build/Tyto.app/Contents/MacOS/Tyto --selftest-echo

# 用设置里的大模型，对一段示例对话生成回复
build/Tyto.app/Contents/MacOS/Tyto --selftest-reply

# 截屏回复：本机 OCR + 大模型（--instruction 补充要求）
build/Tyto.app/Contents/MacOS/Tyto --selftest-screenshot chat.png --instruction "婉拒"

# 截图并认出是哪个 App（frontWindow / screen）
build/Tyto.app/Contents/MacOS/Tyto --selftest-capture frontWindow --out /tmp/front.png

# 对着一个地址测：三家服务商读模型列表、Ollama 检测和下载
build/Tyto.app/Contents/MacOS/Tyto --selftest-providers http://127.0.0.1:11434

# 读出现在的设置（老版本的设置会被换算），只看不写
build/Tyto.app/Contents/MacOS/Tyto --selftest-settings

# Deepgram 返回消息的解析（说话人拆分、断句）
build/Tyto.app/Contents/MacOS/Tyto --selftest-deepgram

# 以上自测都可以临时改设置（不写回），比如用语音转写接口识别一个文件：
#   --settings-json '{"speechMethod":"transcription","speechSlot":{"providerID":"groq","model":"whisper-large-v3-turbo"}}'

# 用示例数据把悬浮窗画成图片（三套主题 + 截屏回复），不截屏
build/Tyto.app/Contents/MacOS/Tyto --render-preview /tmp/tyto-preview

# 设置窗口每一页画成图片（窗口建在屏幕外）
build/Tyto.app/Contents/MacOS/Tyto --render-settings /tmp/tyto-settings

# 真实玻璃效果：悬浮窗盖在模拟会议画面上，只截这两个窗口（要屏幕录制权限）
build/Tyto.app/Contents/MacOS/Tyto --selftest-glass /tmp/tyto-glass

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
  Speech/     识别引擎：Apple SpeechAnalyzer、Soniox、Deepgram（WebSocket）、按停顿切句上传（转写接口 / 听写模型）
  Translate/  Apple 本机翻译、大模型翻译
  Screenshot/ 截前台 App / 整屏 / 框选（认出来源 App）、剪贴板图片、本机 OCR（Apple Vision）
  LLM/        Claude / OpenAI 兼容 / Ollama（流式、可带图片）、读模型列表、Ollama 下载、各种提示词、回复分段
  Model/      会话（分句、翻译、回复、保存）、设置（服务商 + 用途）、技能
  UI/         悬浮窗、主题、关键字高亮、会话与设置窗口
  Dev/        自测、运行日志
Sources/ShareCheck/   共享屏幕验证程序（scripts/build-app.sh ShareCheck）
```

## 还没做 / 已知限制

- 模型还没定，现在默认 Apple 本机识别 + Apple 本机翻译 + Claude Opus 5.5（effort low）。
- Soniox、Deepgram 按官方协议写好了（解析用 Deepgram 的标准消息测过），还没用真的 key 连过。
- 语音转写接口和听写模型要等一句说完（停顿 0.7 秒）才出字，比实时识别慢一两秒。
- 本机识别不区分说话人，一路只认一种语言（在设置里分别指定远端、本地的语言）。
- 远端录的是除 Tyto 以外所有 app 的声音，开会时别放音乐和视频。
- 悬浮窗里的下拉菜单是系统画的，共享屏幕时可能被看到（只在弹出的那一下）。
- 截屏回复默认把图片发给回复模型；在意隐私时选「先用看图模型读图」并用 Ollama 本机模型，或者「只用本机 OCR」。本机看图模型要先装 Ollama（ollama.com）。
- 本机 OCR 的快速模式不认中文，只能用准确模式（实测 M4 Pro：聊天窗口大小约 0.3 秒，整个 5K 屏约 0.6 秒，峰值内存约 250～350MB）。
- 用外放开会时，麦克风也会收到对方的声音。这部分按文字去重：本地某句是在远端说话的同时开始的、并且七成以上的词和远端一样，就当回声去掉。复述对方的话回答（在对方说完之后）不受影响。戴耳机最稳。

© 2026 Ethan H.B. Zhou
