![AirTranslate hero](docs/assets/airtranslate-readme-hero.png)

# AirTranslate

适用于 macOS 的实时系统音频转写与翻译应用。

<p align="center">
  <a href="https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg"><img alt="Download AirTranslate.dmg" src="https://img.shields.io/badge/Download-AirTranslate.dmg-2EA44F?style=for-the-badge&logo=apple&logoColor=white"></a>
  <a href="https://github.com/himomohi/AirTranslate/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/himomohi/AirTranslate?style=for-the-badge&label=Latest"></a>
  <a href="https://himomohi.github.io/AirTranslate/"><img alt="Official guide site" src="https://img.shields.io/badge/Guide-Site-0A84FF?style=for-the-badge"></a>
</p>

<p align="center">
  <a href="https://himomohi.github.io/AirTranslate/">官方指南网站</a> ·
  <a href="#下载">下载</a> ·
  <a href="#环境要求">环境要求</a> ·
  <a href="#隐私与-api-key">隐私</a> ·
  <a href="README.md">English</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.ja.md">日本語</a> ·
  中文
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-0A84FF?style=flat-square&logo=apple">
  <img alt="Swift 6.2+" src="https://img.shields.io/badge/Swift-6.2%2B-F05138?style=flat-square&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License: Apache 2.0" src="https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square"></a>
</p>

AirTranslate 可以捕获 Mac 正在播放的音频，实时转写并翻译，也可以通过悬浮字幕窗口显示结果。它适用于会议、课程、视频、采访和直播等场景，避免通过外部麦克风转录造成的麻烦和音质损失。

面向用户的产品介绍、安装指南和下载入口可在 [AirTranslate 官方指南网站](https://himomohi.github.io/AirTranslate/) 查看。

默认流程使用 Apple 框架。GPT Realtime、Gemini Live Translate 和 Meta Scribe 是可选 API 模式，只有在用户提供对应 API key 后才会启用。

## 为什么选择 AirTranslate

- **优先使用系统音频:** 通过 ScreenCaptureKit 直接捕获 Mac 播放音频。
- **易读的实时工作区:** 原文和译文并排显示。
- **悬浮字幕:** 可在其他应用上方显示字幕。
- **默认 Apple 流程:** 以 Apple Speech 和 Apple Translation 作为基础路径。
- **可选 API 模式:** 仅在需要时启用 OpenAI Realtime Translation、Gemini Live Translate 或 Meta Scribe。
- **Keychain 存储:** OpenAI、Gemini 和 Meta API key 由用户输入，并保存在 macOS Keychain。
- **纯文本历史:** 已保存记录是 Mac 上普通的 `.txt` 文件。

![AirTranslate demo](docs/assets/airtranslate-readme-demo.gif)

> "Turn any Mac audio into live captions and translation, right where you are watching."

## 1.7.1 主要更新

- **更稳定的悬浮翻译:** 在新译文就绪之前会保留上一句翻译，识别器每次修订句子时字幕不再整句重写或闪烁。
- **预留字幕高度:** 悬浮字幕保持固定块高度，并以整块淡入替换文本，因此原文行不会在文字变长时上下跳动或重新居中。
- **字幕稳定与对齐:** 可在设置和菜单栏选择字幕稳定（灵敏/均衡/稳定）和字幕对齐（居中/左）。左对齐会在行变长时保持起点固定。
- **演示质量模式:** 一键设置仅显示译文的两行观众字幕，并采用更稳定的分句时机。可添加演讲背景和术语表，以准确保留人名、品牌、缩写及首选译法。

完整内容请参阅 [AirTranslate 1.7.1 发布说明](https://github.com/himomohi/AirTranslate/releases/tag/v1.7.1)。

## 1.7.0 主要更新

- **Meta Scribe:** 可选 Muse Voice Transcribe 在现有翻译层之前加入实时转写、说话人标签和 25 种语言的语码转换。请在设置中提供 Meta API key；Apple 默认模式仍是本地优先默认路径。
- **Stage & Console:** 已移除设置侧边栏。实时字幕以回合块填满窗口，最新回合固定在底部控制台正上方，控制台提供开始/停止、音频源、语言路径、输出、语音和当前引擎。
- **共享 Air teal 设计系统:** 收听/暂停/停止颜色、分层表面和字幕字体层级现已同时应用于主窗口、设置、记录库、悬浮字幕和菜单栏的浅色与深色外观。
- **键盘焦点环:** 自定义控件使用强调色焦点环，开始按钮获得初始焦点，会话锁定的控件以单个锁定指示变暗，同时仍向辅助技术完整描述。
- **Apple 默认模式长时间滚动到新的回合块:** 已确认文本约 600 字或出现较长静音时，实时行会滚动到新的回合块，识别更新不再在主线程上重处理整段转写。已保存记录仍包含完整会话。
- **舞台不再空白:** 信息流用普通堆栈只渲染最近 12 个回合块，修复长会话或停止/开始后字幕消失的问题，并保持渲染成本恒定。

完整内容请参阅 [AirTranslate 1.7.0 发布说明](https://github.com/himomohi/AirTranslate/releases/tag/v1.7.0)。

## 1.6.2 主要更新

- **屏幕录制系统请求仅出现一次:** AirTranslate 只会在首次实际需要屏幕录制权限的尝试中打开 macOS 系统请求。之后若权限仍不可用，应用会引导到“隐私与安全性”设置，而不会反复打开系统请求。
- **仅保留一个准备使用的安装副本:** 旧版或签名不同的 AirTranslate 副本即使使用相同的 `dev.appcaster.AirTranslate` Bundle ID，也可能被 macOS TCC 视为不同的权限身份。请移除或归档其他副本，只保留实际要运行的安装版本。
- **明确 ad-hoc 更新边界:** 公开 DMG 和 ZIP 是 ad-hoc 签名构建，因此无法保证屏幕录制权限在更新之间稳定继承。新安装的构建可能需要在系统设置中重新确认。
- **移除隐藏设置的焦点循环:** 隐藏 Settings Scene 中的分段 `Picker` 在采集开始时不再切换为禁用状态。这个不可见的状态变化可能触发 AppKit 焦点导航和 AttributeGraph CPU 循环，使顶部 Gemini Live“开始”看起来卡住；现在启动流程可以正常继续。

完整内容请参阅 [AirTranslate 1.6.2 发布说明](https://github.com/himomohi/AirTranslate/releases/tag/v1.6.2)。

## 1.6.1 主要更新

- **Gemini Live 启动更可靠:** 顶部“开始”按钮现在会以所选 Gemini Live 模式开始采集。
- **避免采集控件的 CPU 循环:** 已锁定的分段控件会保留可见状态，但不会走 macOS 的禁用状态焦点路径，以避免启动时可能触发的 AttributeGraph CPU 循环。
- **可直接操作的启动恢复:** 启动失败不会以瞬时覆盖层消失，而是保留在主窗口中，并直接提供 API key 设置、macOS 隐私设置或重试操作。
- **面向当前构建的权限说明:** 权限帮助会识别当前已签名的 AirTranslate 构建。如果 macOS 未识别它，请只保留当前应用副本、仅刷新一次受影响的权限，然后退出并重新启动；常规更新无需重置 TCC。

完整内容请参阅 [AirTranslate 1.6.1 发布说明](https://github.com/himomohi/AirTranslate/releases/tag/v1.6.1)。

## 1.6.0 主要更新

- **Gemini 原文转写与自动语言检测:** 添加自己的 Gemini API key 后，可选择 **Gemini 3.5 Transcribe Live**，获得不翻译的原文字幕；Gemini 会在采集过程中自动检测口语。
- **更稳定的长时 Gemini 会话:** 处理 finished 状态、会话恢复、GoAway 重连建议、受限上下文压缩和 40ms 音频分块发送，增强长时间采集路径。
- **原文专用的响应式流程:** 在最小支持尺寸下，工作区和设置会重新排布而不隐藏控件；Apple、GPT 与 Gemini 转写模式都会一致地隐藏目标语言、译文和译文语音控件。

完整内容请参阅 [AirTranslate 1.6.0 发布说明](https://github.com/himomohi/AirTranslate/releases/tag/v1.6.0)。

## 1.5.1 主要更新

- **简洁一致的界面:** 主工作区、侧边栏、菜单栏、悬浮字幕、记录库和设置现在共享一套克制的间距、图标、表面、选中与悬停反馈体系。
- **更清晰的设置状态:** 各项权限会显示可获取的状态；无法直接读取时会引导用户前往系统设置确认。语言资源会显示下载进度、错误与重试状态，“关于”页面也会显示应用版本和构建号。
- **更可靠的设置控制:** 音量会跟随语音输出状态启用或停用，API key 仅通过会话存储的一条路径保存；启动时只检查 Keychain 中是否存在条目，不读取秘密数据或显示认证界面，悬浮字幕预览会与所选显示模式同步。
- **键盘与辅助功能:** 切换设置分区时会稳定保留选择状态，并提供更清晰的辅助功能标签与值，同时尊重“减弱动态效果”设置。

完整内容请参阅 [AirTranslate 1.5.1 发布说明](https://github.com/himomohi/AirTranslate/releases/tag/v1.5.1)。

## 1.5.0 主要更新

- **加强 Apple 默认模式生命周期:** Apple 默认模式仍是本地优先的默认路径；来自旧启动尝试的延迟授权响应、warm-up 和采集回调无法再改变新会话。
- **正确处理外部停止:** 即使在应用外停止 macOS 系统音频采集，应用也会保存记录、解除会话锁定，并允许重新开始。
- **不再静默丢失输入:** 语音输入 backpressure 不会再静默丢弃音频，而是以用户可见的受控停止处理。
- **可选 GPT 转写:** 仅在提供 OpenAI API key 时才可用 `gpt-live-transcribe` 生成原文字幕；它与 GPT 实时翻译是独立模式。

完整内容请参阅 [AirTranslate 1.5.0 发布说明](https://github.com/himomohi/AirTranslate/releases/tag/v1.5.0)。

## 1.4.2 主要更新

- **稳定请求麦克风权限:** 已签名的本地和发布构建现会嵌入 macOS 请求麦克风权限所需的 audio-input entitlement。
- **发布签名检查:** 在分发前，打包检查会验证 Hardened Runtime、发布/调试 entitlement 的分离，以及麦克风权限说明。

完整内容请参阅 [AirTranslate 1.4.2 发布说明](https://github.com/himomohi/AirTranslate/releases/tag/v1.4.2)。

## 1.4.1 主要更新

- **更稳定的译文语音:** Apple 默认模式会等流式译文到达稳定句子边界后再朗读。
- **最终文本仍会朗读:** 没有标点的最终译文会在翻译请求完成时立即语音输出。
- **减少重复尾句:** 短暂改写后恢复的句尾、近似重复的最终修订，以及短重复后缀不会再次朗读。
- **更干净的配音切换:** 启用译文语音时，不会重新朗读已经显示在屏幕上的译文。
- **保留合理重复:** 短暂防重放窗口过后，真实重复出现的短语仍可在同一会话中再次朗读。
- **聚焦回归测试:** 译文语音进度逻辑由专门的 AirTranslateCore 测试覆盖。

完整内容请参阅 [AirTranslate 1.4.1 发布说明](https://github.com/himomohi/AirTranslate/releases/tag/v1.4.1)。

## 核心功能

- 实时捕获 Mac 系统音频
- Apple Speech 转写
- Apple Translation 翻译
- 只显示原文的 Transcribe Only 模式
- 支持内置麦克风、蓝牙与 AirPods 麦克风输入
- 基于 OpenAI Realtime Translation 的 GPT 模式
- 用于原文字幕的可选 `gpt-live-transcribe` GPT 转写模式
- Gemini 3.5 Live Translate 模式，以及可自动检测口语的原文专用 Gemini 3.5 Transcribe Live 可选模式
- 在现有翻译层之前提供说话人标签和 25 种语言字幕的可选 Meta Scribe 模式
- 面向 API 翻译流的 LIVE 翻译模式
- Apple 默认模式的源语言自动检测已暂时停用，以改进语言切换稳定性
- 改进麦克风输入稳定性，降低重复片段/切换抖动
- 一键交换原文/译文语言
- 悬浮字幕窗口
- 基于 macOS 拼写建议的记录修正
- 可选译文语音输出
- 查看、编辑、删除和打开已保存记录文件夹
- 根据 Mac 语言设置自动选择英语、韩语、日语或简体中文界面

## 处理模式

AirTranslate 将快速选择和详细设置分开。

| 模式 | 适用场景 | 说明 |
| --- | --- | --- |
| Apple 默认模式 | 本地优先的转写和翻译 | 使用 Apple Speech 转写，并用 Apple Translation 翻译所选语言对。源语言自动检测已暂时停用，以改进语言切换稳定性。 |
| GPT 模式 | OpenAI Realtime 实时翻译 | 将音频直接流式发送到 OpenAI Realtime Translation。如果没有保存 API key，AirTranslate 会打开设置弹窗并聚焦 API key 输入框。 |
| GPT 转写 | OpenAI 原文字幕 | 在可选模式中提供 OpenAI API key 后，使用 `gpt-live-transcribe` 生成不含翻译的原文字幕。 |
| Gemini Live | Gemini 3.5 Live Translate 或原文转写 | Gemini 3.5 Live Translate 显示原文和译文；Gemini 3.5 Transcribe Live 仅显示自动检测口语后的原文字幕。两种模式都需要用户提供 Gemini API key。 |
| Meta Scribe | 带说话人标签的多语言字幕 | 使用 Muse Voice Transcribe 进行带说话人标签和 25 种语言语码转换的实时转写，再交给 AirTranslate 现有翻译层。需要 Meta API key。 |
| 仅转写 | 只需要原文字幕 | 不运行翻译，只保留原文记录。 |
| LIVE 翻译 | 需要模型直接生成译文流 | 使用所选 API 提供方的实时翻译模型直接生成翻译结果。 |

GPT、Gemini 和 Meta 模型细节、API key 输入、记录修正和语音输出都在齿轮设置窗口中管理。日常采集控制位于 Stage 下方的浮动控制台。

## 隐私与 API key

AirTranslate 不包含账户系统，也没有开发者运营的中继或后端服务器。这并不表示所有模式都离线：启用可选提供方模式后，所选功能需要的音频或文本会直接发送到对应的外部 API。

- Apple 默认模式使用 macOS 框架和 Apple 语言资源。
- 仅在启用 GPT 模式或可选 GPT 转写模式时，所需音频或文本才会使用用户的 OpenAI API key 直接发送到 OpenAI API。
- 仅在启用 Gemini Live Translate 或 Gemini 3.5 Transcribe Live 时，所需音频才会使用用户的 Gemini API key 直接发送到 Google Gemini API。
- 仅在启用 Meta Scribe 时，所需音频才会使用用户的 Meta API key 直接发送到 Meta 的 Muse Voice Transcribe API。
- OpenAI、Gemini 和 Meta API key 由用户提供并存储在 Keychain 中，绝不会硬编码、提交或包含在发布包中。
- API key 使用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 保存到 macOS Keychain。
- 已保存记录是用户 Mac 上的纯文本文件。

需要 API key 时，请打开 [OpenAI API key 页面](https://platform.openai.com/api-keys)、[Google AI Studio API key 页面](https://aistudio.google.com/app/apikey) 或 [Meta 开发者门户](https://dev.meta.ai)，创建 key 后粘贴到 AirTranslate 设置窗口。

## Apple 翻译语言包

Apple 默认模式使用 macOS 管理的翻译语言资源。使用新的语言对之前，请先下载所需的 Apple 翻译语言包。

1. 打开**系统设置**。
2. 前往**通用 > 语言与地区**。
3. 点击**翻译语言**。
4. 为要使用的源语言和目标语言分别点击**下载**。
5. 可选：如果希望 macOS 尽可能在 Mac 本机处理支持的翻译，请开启**设备端模式**。

如果所选语言对不可用或尚未下载，Apple 默认模式的翻译可能无法开始，或在 macOS 准备好所需语言资源之前显示不可用状态。

## 权限

AirTranslate 只请求捕获和转写流程需要的权限。

- 屏幕录制
- 系统音频录制
- 麦克风（仅在选择麦克风输入时）
- 语音识别

由于 ScreenCaptureKit 的系统音频捕获路径需要屏幕录制权限，因此应用会请求该权限。AirTranslate 不会把屏幕画面保存为录制文件。系统请求只会在首次实际需要权限的尝试中打开；之后若仍无法使用权限，应用会引导到“隐私与安全性”设置，而不会重复请求。

排查前，请移除或归档 Applications、Downloads、开发用 `dist` 文件夹及其他可启动位置中的旧 AirTranslate 副本。只保留准备使用的安装版本，启动该副本，并在**设置 > 关于**中确认版本。旧版或签名不同的副本即使具有相同的 `dev.appcaster.AirTranslate` Bundle ID，macOS 也可能将其保存为不同的 TCC 权限身份。

首次请求后，如果当前应用仍无法使用权限，请前往**系统设置 > 隐私与安全性 > 屏幕与系统音频录制**确认当前安装版本，然后退出并重新启动应用。通常无需重置 `tccutil`。公开 ad-hoc 签名构建不保证更新间的 TCC 权限继承，因此可能需要重新确认新安装的版本。

如果权限正确但 Gemini Live“开始”此前仍像是卡住，请在**设置 > 关于**中确认版本为 1.7.1 或更高。自 1.6.2 起，隐藏设置中的分段控件不会在启动时进入 AppKit 焦点导航/AttributeGraph 循环。

## 下载

最新开源构建可在 [GitHub Releases](https://github.com/himomohi/AirTranslate/releases/latest) 下载。DMG 是最简单的安装路径，ZIP 也会继续作为轻量压缩包提供。

- [下载 AirTranslate.dmg](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)
- [下载 AirTranslate-1.7.1.zip](https://github.com/himomohi/AirTranslate/releases/download/v1.7.1/AirTranslate-1.7.1.zip)
- [下载 AirTranslate.dmg.sha256](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg.sha256)
- [查看版本历史](Release/VERSION-HISTORY.md)

发布 DMG 和 ZIP 是面向开源分发的 ad-hoc 签名构建。此版本尚未完成 Apple notarization，因此首次启动时 macOS 可能显示“无法验证开发者”的警告。ad-hoc 签名也无法保证更新间的 TCC 权限继承。

1. 打开 DMG，并将 `AirTranslate.app` 拖入 Applications 文件夹。
2. 在 Applications 中 Control-点击或右键点击 `AirTranslate.app`。
3. 选择**打开**，然后在 macOS 警告对话框中再次选择**打开**。

下载后可用以下命令验证 DMG 校验和：

```bash
shasum -a 256 AirTranslate.dmg
cat AirTranslate.dmg.sha256
```

## 环境要求

- macOS 26.0 或更高版本
- Swift 6.2 或更高版本
- 支持系统音频捕获的 Mac
- 可使用 Apple Speech 和 Apple Translation 框架的环境
- 可选: GPT 模式或 GPT 转写需要 OpenAI API key
- 可选: Gemini Live 模式需要 Gemini API key
- 可选: Meta Scribe 模式需要 Meta API key

## 从源码构建

运行应用 bundle：

```bash
./script/build_and_run.sh
```

构建并验证启动：

```bash
./script/build_and_run.sh --verify
```

查看日志：

```bash
./script/build_and_run.sh --logs
```

开发时重置权限：

```bash
./script/build_and_run.sh --reset-permissions
```

SwiftPM 检查：

```bash
swift build
swift test
```

## 基本用法

1. 选择原文语言和译文语言。
2. 如需反向翻译，点击中间的语言交换按钮。
3. 在控制台中选择 Apple 默认模式、GPT 模式、Gemini Live 或 Meta Scribe。
4. 如果 API 模式提示需要 key，请在设置窗口中输入 OpenAI、Gemini 或 Meta API key。
5. 点击开始。
6. 在 Mac 上播放会议、课程、视频、采访或直播音频。
7. 在主工作区或悬浮字幕窗口查看原文和译文。
8. 点击停止后，当前记录会被保存。

## 已保存记录

已保存记录以纯文本文件保存：

```text
~/Library/Application Support/AirTranslate/Transcripts/*.txt
```

同时保存原文和译文时，AirTranslate 会分别写入 `_original.txt` 和 `_translation.txt` 文件，并在应用资料库 UI 中显示为一个组合项目。

## 项目结构

```text
Package.swift
Resources/
  AppIcon.png
  AppIcon.icns
Sources/AirTranslate/
  App/
  Models/
  Services/
  Support/
  Views/
Sources/AirTranslateCore/
Tests/
script/
  build_and_run.sh
docs/assets/
  airtranslate-readme-hero.png
```

## 关键实现区域

- `SystemAudioCapture`: 通过 ScreenCaptureKit 捕获 Mac 系统音频。
- `LiveSpeechTranscriber`: 通过 Apple Speech 流式转写。
- `AppleTranslationService`: 隔离 Apple Translation 翻译工作。
- `OpenAIRealtimeTranscriber`: 处理可选 OpenAI 实时翻译和转写事件。
- `GeminiLiveTranslationService`: 处理可选 Gemini Live Translate WebSocket 会话。
- `OpenAIAPIKeyStore` / `GeminiAPIKeyStore`: 将 API key 保存到 macOS Keychain。
- `TranslationSessionStore`: 协调捕获、记录状态、翻译、保存和语音输出。
- `SidebarView`: 提供语言、处理方式、会话和设置入口。
- `CaptionBoardView`: 显示实时记录、翻译、控制项和音频仪表。
- `TranscriptLibraryView`: 管理已保存记录。
- `FloatingCaptionWindowController`: 管理悬浮字幕窗口生命周期。

## 许可证

AirTranslate 基于 [Apache License 2.0](LICENSE) 发布。版权声明见 [NOTICE](NOTICE)。

AirTranslate 是独立的开源项目，不隶属于 Apple、OpenAI 或 Google，也未与其建立合作关系。
