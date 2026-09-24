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

AirTranslate **1.14.2/build1142** 可直接在主工作区右下角控件中选择各提供方的模型。模型选择器会区分实时翻译与原文转写。Gemini TTS 是单独的译文语音选项，仅用于文本翻译。实时提供方继续使用自己的原生音频。

请在设置 > API 密钥 > Qwen 中输入 **阿里云新加坡 API 密钥**。Qwen3.8 LiveTranslate 还需要工作空间 ID；Qwen Audio 3.1 Realtime Plus 和 Filetrans 仅使用密钥。密钥单独保存在 macOS Keychain 中，开始捕获后会将所选实时音频直接发送到阿里云新加坡。在设置 > 通用中，可选择默认模型 `qwen3.8-livetranslate-flash-realtime` 或 `qwen-audio-3.1-realtime-plus`。Qwen Audio 3.1 Realtime Plus 是接收 AirTranslate 翻译指令的全双工实时语音对话模型；Qwen3.8 LiveTranslate 是专用实时翻译模型。**语音输出为可选项，默认关闭**。请在 Model Studio 中查看当前 Qwen Audio 价格。

设置 > 通用中的 `qwen-audio-3.1-asr-flash-filetrans` 用于异步转写音频文件。**仅接受公开的 HTTPS 音频 URL**；QwenCloud 会从 URL 获取音频，此流程不会上传本地音频文件。请只分享你有权发送给提供方的音频。参见 [Qwen 设置与价格](docs/qwen-livetranslate.md)。真实账户认证、计费、翻译和转写质量及延迟尚未验证。

**反映 API 密钥状态的模式选择器**将没有密钥的提供方显示为灰色，并在每行提供设置入口。信息图标说明模型及其计费依据。**OpenAI 语音统一翻译与原文转写**，并保留语言和输出偏好。主界面选择器可选择 Apple、OpenAI、Gemini、Qwen 和 Nari 模型，并按实际功能显示说明；译文语音模型使用单独的选择器。

**悬浮字幕只显示文字**，不显示窗口背景、边框、工具栏、状态文字或悬停缩放控件。可在设置中调整五种文字样式、字体、颜色、宽度、行距、顺序及示例预览，通过主界面、菜单栏或 ⌘⇧C 切换显示。

**Qwen 停止前会等待最终字幕**。空的最终响应会撤回临时字幕，Qwen 记录仅保存已确认的结果，包括定期保存。Apple Mode 仍为默认模式，记录文件保存仍需主动启用。

**可以选择译文语音输出模型**。在设置或主工作区单独的译文语音选择器中选择 Apple 系统语音、Gemini 3.8 Flash TTS 或 Flash-Lite TTS。实时模式下也会保存此选择，但仅用于文本翻译；实时提供方继续使用自己的原生音频。Gemini TTS 会使用你的 Gemini 密钥，只将稳定的译文文本发送给 Google。

## 下载

当前公开最新版：**v1.14.1**。

- [下载 AirTranslate.dmg](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)
- [下载 AirTranslate-1.14.2.zip](https://github.com/himomohi/AirTranslate/releases/download/v1.14.2/AirTranslate-1.14.2.zip)
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
- 只显示文字的悬浮字幕，以及设置中的五种样式、字体、颜色、宽度、行距、顺序、预览、保存和重置。
- 记录文件保存默认关闭。需要在 Application Support 中保存普通 `.txt` 文件时，请开启 **Save Transcript Files**。
- 英语、韩语、日语和简体中文应用语言。

## 引擎

| 引擎 | 作用 | 需要 |
| --- | --- | --- |
| Apple Mode | 默认本地优先转写与翻译。 | 无 |
| OpenAI 语音 | 在同一提供方内选择翻译或原文转写。通过输出图标切换 `gpt-realtime-translate` 与 `gpt-live-transcribe`，并在提示中查看模型和费用。 | OpenAI |
| Gemini Live | 按文档区分的实时翻译模型，或支持自动语音语言检测的原文转写模型。 | Gemini |
| Meta Scribe | 在 AirTranslate 翻译前生成带说话人标签的多语言转写。 | Meta |
| Azure MAI | 预览云端转写以 REST API 顺序处理 5 秒 WAV 分段，并与 Apple Translation 字幕配合。 | Azure Speech 密钥和终结点 |
| Nari STT | Nari Qwen3-ASR 原文转写，可使用麦克风或 Mac 音频。 | Nari |
| Grok STT | 使用 Grok Voice Transcribe 2.0 转写麦克风或 Mac 音频的原文。 | SpaceXAI (xAI) |
| Qwen LiveTranslate | Qwen3.8 是专用实时翻译模型。Qwen Audio 3.1 Realtime Plus 是接收 AirTranslate 翻译指令的全双工实时语音对话模型，并可返回语音。 | 阿里云新加坡 API 密钥；Qwen3.8 还需要工作空间 ID |

Qwen Audio 3.1 ASR Flash Filetrans 可在设置 > 通用中通过公开的 HTTPS 音频 URL 异步转写。QwenCloud 会从 URL 获取音频；此流程不上传本地音频文件。

Grok STT 自 1.10.0 起提供。首次选择会以原文转写开始，并使用你自己的 xAI API 密钥。设置、语言处理及验证范围请参阅 [Grok STT 说明](docs/grok-stt.md)。

Nari STT 是 1.9.0 的可选引擎。首次选择 Nari 会以原文转写开始；当源语言可用时，可通过 Apple Translation 翻译。Nari 当前 GA STT 模型 ID 为 qwen3-asr-fast 和 qwen3-asr；可用性、使用限制和付费额度条件以 Nari 提供方文档及账号状态为准，并记录在 [docs/nari-stt.md](docs/nari-stt.md)。

Nari 支持手动选择输入语言及自动检测语音语言，包括韩语。

新选择 Nari 时会使用需要 Nari 额度的 GA Fast 模型。已保存的 Free Public Beta 模型选择会保留，但无法启动，也不会自动切换到付费模型。请在设置 > 通用中查看计费提示，然后主动选择 GA 模型以重新启动 Nari STT。

## 悬浮字幕

悬浮字幕仅在画面上显示原文或译文文字。窗口背景、边框、工具栏、状态文字和缩放标记均不显示，悬停时也不会出现。没有字幕时不显示任何内容。请在设置、主界面或菜单栏中操作，使用 ⌘⇧C 显示或隐藏字幕。

提供日常、影院、讲座、高对比度和明亮画面五种文字样式，以及四种字体、字重、行距、阴影/描边、文字颜色、对齐、行数和译文置顶选项。预览可在明暗示例画面中显示实际18–72pt字号，也可在不录音的情况下显示示例字幕。在设置中调整宽度和置顶状态。已有外观偏好仍会恢复，但旧背景设置不会显示为窗口背景。

## API 密钥

API 密钥页面通过一个提供方列表管理 **OpenAI**、**Gemini**、**Meta**、**Azure**、**Nari** 和 **SpaceXAI (xAI)** · **Alibaba Cloud (Qwen)**。每行会显示配置/准备状态、提供方图标、密钥控制台链接，以及说明“已配置密钥并不代表提供方授权已验证”的信息弹窗。

密钥保存在 macOS 钥匙串中。AirTranslate 不包含账号系统、开发者运营的中继服务器，也不包含硬编码的提供方密钥。

Gemini 密钥由 Gemini Live 和可选的 Gemini 译文语音输出共用。选择 Gemini TTS 并不表示真实账号权限、计费、质量或延迟已经过验证。

## 隐私

- Apple Mode 使用 macOS 框架和 Apple 管理的语言资源。
- GPT、Gemini、Meta、Azure、Nari、Grok 和 Qwen 模式只会把所选功能需要的音频或文本，使用你的密钥直接发送给对应提供方。Gemini TTS 仅在你选择 Gemini 语音模型后发送稳定的译文文本。
- 只有开启文件保存后，已保存记录才会作为普通文本文件留在你的 Mac 上。
- 更长的提供方和存储说明见 [Release/PRIVACY-NOTICE.md](Release/PRIVACY-NOTICE.md)。

## 要求

- macOS 26.0 或更高版本
- 源码构建需要 Swift 6.2 或更高版本
- 支持系统音频捕获的 Mac
- 可使用 Apple Speech 和 Apple Translation 框架
- 可选：OpenAI、Gemini、Meta、Azure Speech、Nari、xAI 或阿里云 提供方密钥

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

AirTranslate 是独立开源项目，与 Apple、OpenAI、Google、Meta、Microsoft、Nari、SpaceXAI (xAI) 或阿里云没有关联。
