<p align="center">
  <img src="docs/assets/airtranslate-readme-hero.png" alt="AirTranslate" width="720">
</p>

# AirTranslate

面向会议、视频、课程、访谈和直播的 Mac 音频实时字幕与翻译应用。

<p align="center">
  <a href="https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg"><img alt="Download AirTranslate.dmg" src="https://img.shields.io/badge/Download-AirTranslate.dmg-2EA44F?style=for-the-badge&logo=apple&logoColor=white"></a>
  <a href="https://github.com/himomohi/AirTranslate/releases/latest"><img alt="Latest public release" src="https://img.shields.io/github/v/release/himomohi/AirTranslate?style=for-the-badge&label=Latest"></a>
  <a href="LICENSE"><img alt="License: Apache 2.0" src="https://img.shields.io/badge/License-Apache%202.0-blue?style=for-the-badge"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.ja.md">日本語</a> ·
  中文 ·
  <a href="CHANGELOG.md">更新日志</a> ·
  <a href="docs/GETTING-STARTED.md">入门指南</a>
</p>

AirTranslate 会捕获 Mac 正在播放的音频，实时转写；当你选择翻译流程时，它会进行翻译，并可将字幕悬浮在其他应用上方。Apple Mode 仍然是默认的本地优先流程。云端引擎为可选项，配置对应提供方密钥后即可使用。

AirTranslate **1.10.0/build1100** 新增 **Grok STT**，使用 Grok Voice Transcribe 2.0 转写麦克风或 Mac 音频。

在**设置 > API 密钥 > SpaceXAI (xAI)**中保存自己的密钥，然后在常规设置中选择 **Grok STT**。密钥单独保存在 macOS Keychain 中，开始捕获时音频会直接发送到 xAI。提供方的费用和账户限制适用。

Grok 默认以**仅原文字幕和自动识别语音语言**开始。Apple Mode 仍为默认模式，可另行启用 Apple Translation 翻译。尚未使用真实 xAI 账户验证认证、转写准确度和延迟。

最终响应不会重复添加已确认的语句，也支持无空格连接的日语。保存文件会排除临时字幕和翻译状态提示。切换到其他引擎后会清除 Grok 密钥缺失提示。

悬浮字幕支持双向调整大小、hover 移动和缩放提示、自定义字号、文本颜色、背景颜色和背景透明度、偏好保存和重置。

文字和背景颜色也可通过直接输入 **#RRGGBB 颜色代码** 并使用键盘应用。

## 下载

当前公开最新版：**v1.10.0**。

- [下载 AirTranslate.dmg](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)
- [下载 AirTranslate-1.10.0.zip](https://github.com/himomohi/AirTranslate/releases/download/v1.10.0/AirTranslate-1.10.0.zip)
- [下载 AirTranslate.dmg.sha256](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg.sha256)
- [查看版本历史](Release/VERSION-HISTORY.md)

开源 DMG 和 ZIP 使用 ad-hoc 签名，尚未经过 Apple 公证。若首次启动被阻止，请参阅[安装指南](docs/GETTING-STARTED.md)。可用以下命令检查 DMG 哈希：

```bash
shasum -a 256 AirTranslate.dmg
cat AirTranslate.dmg.sha256
```

## 真实应用

![AirTranslate workspace](docs/assets/airtranslate-workspace.jpg)

开始采集前的 AirTranslate 工作区（韩语 UI）。

AirTranslate 会在一个工作区中保留原文转写和译文，也可以在使用其他应用观看或收听时显示悬浮字幕。

<details>
<summary>API 密钥页面</summary>

![AirTranslate API Keys](docs/assets/airtranslate-api-keys.jpg)

</details>

## 3 步开始

1. 安装应用，启动你实际要使用的那一份副本，并在 macOS 请求时允许屏幕录制和系统音频录制权限。
2. 选择源语言和目标语言，然后在控制台选择 Apple Mode 或可选引擎。
3. 点击 **Start**，播放 Mac 音频或选择麦克风输入，并在主工作区或悬浮字幕窗口中阅读。

API 驱动的引擎在 **Settings > API Keys** 中配置密钥后即可使用。“已配置密钥”表示 AirTranslate 有本地提供方设置；服务访问权限会在开始会话时检查。

## 核心功能

- 通过 ScreenCaptureKit 捕获系统音频，并支持内置、Bluetooth、AirPods 麦克风输入。
- 以 Apple Speech 转写和 Apple Translation 翻译作为默认本地优先路径。
- 无需翻译时可使用只显示原文字幕的转写模式。
- 悬浮字幕、已保存记录库、可选译文朗读和一键切换语言方向。
- 悬浮字幕窗口双向调整大小、移动和缩放提示、自定义字号、文本颜色、背景颜色、不影响文字的背景透明度、偏好保存和重置。
- 记录文件保存默认关闭。需要在 Application Support 中保存普通 `.txt` 文件时，请开启 **Save Transcript Files**。
- 英语、韩语、日语和简体中文应用语言。

## 引擎

| 引擎 | 作用 | 需要 |
| --- | --- | --- |
| Apple Mode | 默认本地优先转写与翻译。 | 无 |
| GPT Mode | 通过 OpenAI Realtime 输出实时译文。 | OpenAI |
| GPT Transcription | 通过 OpenAI 生成原文字幕。 | OpenAI |
| Gemini Live | Gemini 实时翻译，或带自动口语检测的原文转写。 | Gemini |
| Meta Scribe | 在 AirTranslate 翻译前生成带说话人标签的多语言转写。 | Meta |
| Azure MAI | 与 Apple Translation 字幕配合使用的预览云端转写。 | Azure Speech 密钥和终结点 |
| Nari STT | 1.9.0 源码中准备的 Nari Qwen3-ASR 原文转写，可使用麦克风或 Mac 音频。 | Nari |
| Grok STT | 使用 Grok Voice Transcribe 2.0 转写麦克风或 Mac 音频的原文。 | SpaceXAI (xAI) |

Grok STT 自 1.10.0 起提供。首次选择会以原文转写开始，并使用你自己的 xAI API 密钥。设置、语言处理及验证范围请参阅 [Grok STT 说明](docs/grok-stt.md)。

Nari STT 是 1.9.0 的可选引擎。首次选择 Nari 会以原文转写开始；当源语言可用时，可通过 Apple Translation 翻译。Nari 当前 GA STT 模型 ID 为 qwen3-asr-fast 和 qwen3-asr；可用性、使用限制和付费额度条件以 Nari 提供方文档及账号状态为准，并记录在 [docs/nari-stt.md](docs/nari-stt.md)。

Nari 支持手动选择输入语言及自动检测语音语言，包括韩语。

新选择 Nari 时会使用需要 Nari 额度的 GA Fast 模型。已保存的 Free Public Beta 模型选择会保留，但无法启动，也不会自动切换到付费模型。请在设置 > 通用中查看计费提示，然后主动选择 GA 模型以重新启动 Nari STT。

## 悬浮字幕

悬浮字幕窗口可同时调整宽度和高度，并在 hover 状态显示移动和缩放提示。字幕样式在现有预设字号之外支持自定义字号、文本颜色、背景颜色、不影响文字的背景透明度、偏好保存和重置。Caption Stability 仍作为独立设置保留。

## API 密钥

API 密钥页面通过一个提供方列表管理 **OpenAI**、**Gemini**、**Meta**、**Azure**、**Nari** 和 **SpaceXAI (xAI)**。每行会显示配置/准备状态、提供方图标、密钥控制台链接，以及说明“已配置密钥并不代表提供方授权已验证”的信息弹窗。

密钥保存在 macOS 钥匙串中。AirTranslate 不包含账号系统、开发者运营的中继服务器，也不包含硬编码的提供方密钥。

## 隐私

- Apple Mode 使用 macOS 框架和 Apple 管理的语言资源。
- GPT、Gemini、Meta、Azure、Nari 和 Grok 模式只会把所选功能需要的音频或文本，使用你的密钥直接发送给对应提供方。
- 只有开启文件保存后，已保存记录才会作为普通文本文件留在你的 Mac 上。
- 更长的提供方和存储说明见 [Release/PRIVACY-NOTICE.md](Release/PRIVACY-NOTICE.md)。

## 要求

- macOS 26.0 或更高版本
- 源码构建需要 Swift 6.2 或更高版本
- 支持系统音频捕获的 Mac
- 可使用 Apple Speech 和 Apple Translation 框架
- 可选：OpenAI、Gemini、Meta、Azure Speech、Nari 或 xAI 提供方密钥

## 文档

- [Getting Started](docs/GETTING-STARTED.md)
- [Development](docs/DEVELOPMENT.md)
- [Nari STT notes](docs/nari-stt.md)
- [更新日志](CHANGELOG.md)
- [版本历史](Release/VERSION-HISTORY.md)

<details>
<summary>从源码构建</summary>

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
swift test
```

更多命令见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

</details>

## 贡献

面向用户的发布历史保存在 [CHANGELOG.md](CHANGELOG.md)。README 应说明当前产品、下载路径和提供方边界，而不是重复所有过去的发布说明。

## 许可证

AirTranslate 以 [Apache License 2.0](LICENSE) 发布。版权归属见 [NOTICE](NOTICE)。

AirTranslate 是独立开源项目，与 Apple、OpenAI、Google、Meta、Microsoft、Nari 或 SpaceXAI (xAI) 没有关联。
