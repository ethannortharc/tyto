# Tyto 听译

开会用的 macOS 桌面工具：透明悬浮窗，共享屏幕时对方看不见；把对方说的话实时转成文字，可以开关翻译，并对对方的提问给出回复建议。语音识别和大模型都可以配置。

Tyto 是仓鸮属的拉丁名——仓鸮在黑暗里只靠听声音就能定位。

## 现状

第一步：验证"共享屏幕时悬浮窗不被看见"在 Zoom、Teams、Google Meet 上是否成立。

```bash
scripts/build-app.sh            # 编译验证程序，得到 build/TytoShareCheck.app
open build/TytoShareCheck.app
```

测试步骤和结果记录见 `docs/share-check.md`。

© 2026 Ethan H.B. Zhou
