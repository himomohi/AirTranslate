<p align="center">
  <img src="docs/assets/airtranslate-readme-hero.png" alt="AirTranslate" width="720">
</p>

# AirTranslate

会議、動画、講義、インタビュー、配信向けのMac音声ライブ字幕と翻訳アプリ。

<p align="center">
  <a href="https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg"><img alt="Download AirTranslate.dmg" src="https://img.shields.io/badge/Download-AirTranslate.dmg-2EA44F?style=for-the-badge&logo=apple&logoColor=white"></a>
  <a href="https://github.com/himomohi/AirTranslate/releases/latest"><img alt="Latest public release" src="https://img.shields.io/github/v/release/himomohi/AirTranslate?style=for-the-badge&label=Latest"></a>
  <a href="LICENSE"><img alt="License: Apache 2.0" src="https://img.shields.io/badge/License-Apache%202.0-blue?style=for-the-badge"></a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.ko.md">한국어</a> ·
  日本語 ·
  <a href="README.zh-CN.md">中文</a> ·
  <a href="CHANGELOG.md">変更履歴</a> ·
  <a href="docs/GETTING-STARTED.md">はじめに</a>
</p>

AirTranslateはMacで再生中の音声を取り込み、ライブで文字起こしし、翻訳ワークフローを選んだ場合は翻訳し、必要に応じて他のアプリの上にフローティング字幕を表示します。Apple Modeは引き続きローカル優先の標準ワークフローです。クラウドエンジンは任意で、対応するプロバイダーキーを設定すると利用できます。

## 1.18.1 パッケージングの修正

AirTranslate **1.18.1 / ビルド 1181** では、DMG と ZIP に同梱した llama.cpp フレームワークからビルド環境のソースコードの絶対パスを除去しました。アプリの機能と macOS の動作要件は 1.18.0 と同じです。

[リリースノート](Release/GITHUB-RELEASE-1.18.1.md) · [AirTranslate 1.18.1 リリース](https://github.com/himomohi/AirTranslate/releases/tag/v1.18.1)。

AirTranslate **1.18.0/build1180** は、オプションのローカル **Hy-MT2 1.8B 翻訳**、低遅延な **Focus Stage 単一フィード UI**、**アダプティブなダークグラス背景とホバーミニ HUD を備えたフローティング字幕**、**カテゴリ別エンジンハブ**、**2×2 コントロールセンター風メニューバー**、**検索・絞り込み・Markdown/TXT 書き出し対応の履歴ライブラリ**、**用語チップエディター**を追加します。Apple モードは引き続き既定のローカル優先フローです。

## 1.18.0 の新機能: ローカル Hy-MT2 翻訳 · Focus Stage UI · 字幕 HUD

- **オプションのローカル Hy-MT2 1.8B 翻訳:** エンジンハブで **Hy-MT2** を選び、**設定 > 一般** から検証済みの Q4_K_M モデル（1.13 GB）をダウンロードすると、API キーや外部サーバーなしで Mac 上で翻訳できます。ダウンロード進捗・中止・削除・翻訳プレビュー確認、名前・専門用語チップ、直前の完了字幕文脈、停止時の最大 25 秒ドレイン（未完了断片を保存しない）に対応します。[設定と制限](docs/hymt-local-translation.md)。
- **Focus Stage メイン画面と低遅延レンダリング:** 言語ペア選択・入れ替えを上部のステージヘッダーに統合し、900pt 既定幅（840pt 以上）でも下部のグラスコンソールが折り畳まれません。繰り返しの見出しを省いたタイムスタンプ付きターンカードとライブアクセントバーを採用し、音声レベル表示（`SessionAudioWaveform`）を分離してライブ更新時の再描画負荷を抑えました。
- **カテゴリ別エンジン・音声ハブ:** `すべて / オンデバイス / クラウド` フィルターでオンデバイス、クラウドリアルタイム翻訳、クラウド文字起こし＋ローカル翻訳を整理し、モデル・音声・API キー管理へ直接移動できます。
- **アダプティブフローティング字幕とホバーミニ HUD:** `フロストダーク`（既定）、`シネマダーク`、`透明` の背景スタイルで明るいスライドや動画の上でも高い視認性を保ち、ホバーで一時停止・コピー・表示モード切替・文字サイズ（`A-`/`A+`）・背景切替・閉じるを操作できます。
- **メニューバー刷新・履歴検索/書き出し・用語チップ:** メニューバーを `PC音声 / マイク` 切替付きの 2×2 タイルに再編し、保存済み記録では検索・絞り込み・Markdown（`.md`）/テキスト（`.txt`）書き出し、設定では用語チップエディターと API キー数バッジを追加しました。
- **安定性修正:** Azure MAI のキャプチャメニュー停止時のドレインと暫定文除外、EmbeddingGemma のライブ終了後モデル再確認および読取不可音声の復旧案内を改善しました。

[リリースノート](Release/GITHUB-RELEASE-1.18.0.md) · [AirTranslate 1.18.0 リリース](https://github.com/himomohi/AirTranslate/releases/tag/v1.18.0)。

## 英語ファイルのローカル文字起こし（1.17.0 から）

- **任意のファイル文字起こし:** 設定 > 一般 > EmbeddingGemma 2 ファイル文字起こし（実験）で利用できます。Apple Silicon・macOS 27 以降が必要です。アプリ全体の最小要件は引き続き macOS 26 です。英語音声のみ、最大60分／2 GB。ライブ字幕とは独立し、句読点・大文字小文字の復元、音声の翻訳、話者識別には対応しません。
- **仕組み:** 固定した音声エンコーダーが時系列の表現を作り、学習済み reader が英単語の埋め込みに対応させ、各時点で単語または blank を選びます。CTC デコードが連続する重複と blank を整理して文字列を作ります。元の実験のコード・reader 重みは非公開のため、独立した公開再現の reader v2 を使用します。
- **明示的なモデルダウンロードと整合性:** モデルをダウンロードを押した場合にだけ、固定した Hugging Face revision から約935 MBを取得します。インストール完了前にファイルサイズと SHA-256 を確認します。インストールには2 GiB以上の空き容量が必要で、ローカルコンパイルにも容量を使用します。API キーは不要で、音声・文字起こし結果はアップロードしません。
- **使い方と書き出し:** ライブキャプチャを停止し、モデルを取得して英語音声を選択し、ローカル文字起こしを実行します。進捗とキャンセルを提供し、結果のコピーや UTF-8 テキスト保存が可能です。キャンセルすると実行中のモデル処理が終わった後に結果を破棄します。今回の音声の長さと、デコード・モデル読み込みを含む処理時間を表示します。
- **実験的な精度と速度:** 訛り、雑音、固有名詞、固定語彙にない語で結果が変わります。初回のモデル読み込みには時間がかかる場合があります。元の実験の1時間を約13秒で処理するという主張は、AirTranslate の性能保証ではありません。

[手法・設定・制限](docs/embeddinggemma-transcription.md) · [AirTranslate 1.17.0 リリース](https://github.com/himomohi/AirTranslate/releases/tag/v1.17.0)。

## 継続して利用できる字幕・翻訳の改善

**1.16.0 で導入した改善**を引き続き利用できます。文字起こしの安定性、重複翻訳の処理、字幕の読みやすさ、Apple 翻訳オプション、任意の Jev 候補選択、フローティング専用のウィンドウ操作を含みます。以下は継続提供する機能であり、1.17.0 の新規修正ではありません。

- **フローティング専用の開始と操作:** 待機中はキャプチャを開始し、一時停止中は再開して、実行状態になってからメイン画面を最小化します。開始に失敗した場合はメイン操作画面を維持します。メニューバーとアプリメニューからも開始・停止、一時停止・再開できます。
- **直前の字幕表示:** 現在の字幕とともに直前の字幕を1ブロック、最大2行で8秒間表示します。「視差効果を減らす」に対応します。
- **フローティング字幕の描画:** 現在の字幕の位置を保ち、更新のたびに繰り返すフェードをなくしました。サイズを制限したレイアウトを再利用し、蓄積した文字起こし全体の反復処理を避けます。メイン画面の最小化中は表示処理を省き、音声認識と翻訳は継続します。
- **Apple 文字起こしと翻訳の処理:** 周辺の認識文脈を保持し、個別の最終テキスト通知がなくても Apple が確定した区間を次の発話への移行時に保持します。この移行で前の文が欠落したり重複したりする問題を防ぎます。
- **重複翻訳の削減:** 暫定テキストと確定テキストが同じ場合は進行中の翻訳を再利用し、同じ結果を二重に反映しません。
- **確定字幕と新しいセッションの保護:** 修正された確定文が古い暫定翻訳に優先します。停止済みセッションから遅れて届く結果やエラーは新しいセッションを上書きせず、別の発話で同じ表現を繰り返しても順序を保持します。
- **短い文字起こしの処理:** 変化する短い句は最後のテキスト変更後に落ち着くまで待ち、十分な文脈があれば早めに翻訳します。句読点だけの結果は翻訳しません。
- **過去の字幕と読む位置の保持:** 過去の字幕を読む間は自動スクロールを止め、最新の字幕に戻ると追従を再開します。メイン画面を最小化したり隠したりしても読んでいた位置を保持します。
- **閉じた字幕の処理削減:** フローティング字幕を閉じると表示用タイマーとレイアウト処理を止め、文字起こしと翻訳は継続します。
- **フローティング字幕の再表示:** 再翻訳せずに最新のテキストを復元し、暫定原文の重複を防ぎます。原文が修正された場合、古い訳文が保持時間を超えて残らないようにします。
- **メイン画面の復元:** フローティング専用モードが最小化した画面だけを復元し、最小化の途中で字幕を閉じる場合にも対応します。ユーザーが先に最小化した画面は区別します。
- **キャプチャ状態とメニュー操作:** メイン画面・メニューバー・キーボードで準備・終了処理・再接続の状態と利用可能な操作を統一しました。字幕の表示モードと文字サイズの操作もメニュー間で共通化しました。
- **実験的な Jev 候補選択:** 初期状態はオフです。Apple の文字起こしと翻訳を併用する際、確定した認識候補から翻訳するテキストを選べます。有効にすると、候補テキストと直前の最大6区間の文字起こし（1,000 UTF-8 バイト）を、Keychain に保存したユーザーのキーで TypeSafe に直接送信します。API 使用量と1リクエストあたり最大1.2秒の応答待機が加わります。候補なし・不確実・エラー・時間切れでは原文を保持し、精度向上は保証しません。[設定とデータ処理](docs/apple-translation-options.md)。
- **Apple 翻訳品質と用語保持:** macOS 26.4 以降でリアルタイム（標準）または品質優先を選び、表記を保持する用語を登録できます。品質優先は時間がかかる場合があり、Apple のモデルの利用可否に依存します。失敗した言語ペアはアプリの再起動までリアルタイム翻訳に戻ります。登録用語が変更された場合、該当区間を原文のまま保持します。Apple のテキスト翻訳に適用されます。
- **macOS 27 の音声入力互換性:** 既存の16 kHz モノラル経路を維持しつつ、異なる PCM 入力形式を Apple 音声認識に合わせて変換します。
- **ソースのビルド要件:** macOS 27 SDK を含む Xcode 27 と Swift 6.4 以降が必要です。配布アプリは引き続き macOS 26 以降で動作します。

設定 > APIキー > Qwenに **Alibaba CloudシンガポールのAPIキー** を入力してください。Qwen3.8 LiveTranslateにはワークスペースIDも必要ですが、Qwen Audio 3.1 Realtime PlusとFiletransはキーだけで利用できます。キーはmacOS Keychainの専用項目に保存し、キャプチャ開始時に選択したリアルタイム音声をAlibaba Cloudシンガポールへ直接送信します。設定 > 一般で既定の `qwen3.8-livetranslate-flash-realtime` または `qwen-audio-3.1-realtime-plus` を選べます。Qwen Audio 3.1 Realtime PlusはAirTranslateから翻訳指示を受ける全二重のリアルタイム音声会話モデルです。Qwen3.8 LiveTranslateは専用のリアルタイム翻訳モデルです。**音声出力は任意で、初期状態ではオフです**。Qwen Audioの料金はModel Studioで確認してください。

設定 > 一般の `qwen-audio-3.1-asr-flash-filetrans` は非同期の音声ファイル文字起こしです。**公開HTTPS音声URLのみ利用できます**。QwenCloudがURLから音声を取得し、この機能はローカルファイルをアップロードしません。送信する権利のある音声だけを共有してください。[Qwenの設定と料金](docs/qwen-livetranslate.md)をご覧ください。実アカウントの認証・課金・翻訳と文字起こしの品質・遅延は未検証です。

**カテゴリ別エンジン・音声ハブ**は `すべて / オンデバイス / クラウド` フィルターを備え、キーのないクラウドプロバイダーを区別しつつ設定・API キー画面へ直接案内します。情報アイコンでモデルと料金基準を確認できます。**OpenAI 音声は翻訳と原文文字起こしを統合**し、言語・出力設定を維持したまま翻訳音声モデルを別セレクターで選べます。

**アダプティブフローティング字幕**は `フロストダーク`（既定）、`シネマダーク`、`透明` の背景スタイルとホバーミニ HUD（一時停止・コピー・表示モード切替・`A-`/`A+`・背景切替・閉じる）を提供します。5種類の文字スタイル、フォント・色・幅・行間・順序・サンプルプレビューは設定で調整し、メイン画面・メニューバー・⌘⇧Cで表示を切り替えます。

**Qwenは停止前に最終字幕の受信を待ちます**。空の最終応答は暫定字幕を取り消し、定期保存を含むQwenの記録には確定結果だけを保存します。Apple Modeを標準とし、記録ファイル保存は任意のままです。

**翻訳音声出力モデルを選択できます**。設定またはメイン画面の別の翻訳音声選択欄でAppleシステム音声、Gemini 3.8 Flash TTS、Flash-Lite TTS、MAI Voice 2.1、Flashを選びます。リアルタイムモードでも選択は保存されますが、テキスト翻訳でのみ使用されます。リアルタイムプロバイダーは引き続き独自の音声を使用します。Gemini TTSは安定した翻訳テキストだけをGoogleへ送信します。

## ダウンロード

現在の公開最新版: **v1.18.1**。

- [AirTranslate.dmgをダウンロード](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg)
- [AirTranslate-1.18.1.zipをダウンロード](https://github.com/himomohi/AirTranslate/releases/download/v1.18.1/AirTranslate-1.18.1.zip)
- [AirTranslate.dmg.sha256をダウンロード](https://github.com/himomohi/AirTranslate/releases/latest/download/AirTranslate.dmg.sha256)
- [AirTranslate 1.18.1 リリースノート](https://github.com/himomohi/AirTranslate/releases/tag/v1.18.1)
- [AirTranslate 1.18.0 リリースノート](https://github.com/himomohi/AirTranslate/releases/tag/v1.18.0)
- [バージョン履歴を見る](Release/VERSION-HISTORY.md)

オープンソースのDMGとZIPはad-hoc署名で、Appleの公証を受けていません。初回起動がブロックされた場合は[インストールガイド](docs/GETTING-STARTED.md)を確認してください。DMGのハッシュは次のように確認できます。

```bash
shasum -a 256 AirTranslate.dmg
cat AirTranslate.dmg.sha256
```


## 実際のアプリ

![AirTranslate workspace](docs/assets/airtranslate-workspace.jpg)

キャプチャ開始前のAirTranslateワークスペースです（韓国語UI）。

AirTranslateは原文の文字起こしと翻訳文を1つのワークスペースに保ち、別のアプリで視聴または作業している間はフローティング字幕で表示できます。

## 3ステップで開始

1. アプリをインストールし、実際に使うコピーを起動して、macOSが求める画面収録とシステムオーディオ録音の権限を許可します。
2. 原文言語と翻訳言語を選び、コンソールからApple Modeまたは任意のエンジンを選択します。
3. **Start**を押し、Macの音声を再生するかマイク入力を選び、メインワークスペースまたはフローティング字幕で読みます。

API連携エンジンは、**Settings > API Keys**でキーを設定すると利用できます。キー設定済みとはAirTranslateにローカルのプロバイダー設定があるという意味で、プロバイダーのアクセス権はセッション開始時に確認されます。

## 主な機能

- ScreenCaptureKitによるシステムオーディオ取り込みと、内蔵、Bluetooth、AirPodsマイク入力。
- ローカル優先の標準経路であるApple Speech文字起こしとApple Translation翻訳。
- 翻訳なしで原文字幕だけを見る文字起こし専用モード。
- フローティング字幕、保存済み記録ライブラリ、任意の翻訳音声、ワンクリック言語入れ替え。
- 文字だけのフローティング字幕と、設定での5スタイル・フォント・色・幅・行間・順序・プレビュー・保存・リセット。
- 記録ファイル保存はデフォルトでオフです。Application Supportに通常の`.txt`ファイルを残す場合は**Save Transcript Files**を有効にします。
- 英語、韓国語、日本語、簡体字中国語のアプリ言語。

## エンジン

| エンジン | 役割 | 必要なもの |
| --- | --- | --- |
| Apple Mode | 標準のローカル優先文字起こしと翻訳です。 | なし |
| OpenAI 音声 | 1つのプロバイダー内で翻訳または原文文字起こしを選びます。出力アイコンで `gpt-realtime-translate`・`gpt-live-transcribe` を切り替え、ツールチップでモデルと料金を確認できます。 | OpenAI |
| Gemini Live | 文書化されたリアルタイム翻訳モデル、または音声言語を自動検出する原文文字起こしモデルを選択できます。 | Gemini |
| Meta Scribe | AirTranslate翻訳の前段にある、話者ラベル付き多言語文字起こしです。 | Meta |
| Azure MAI | 5 秒 REST チャンクの MAI-Transcribe-2、または中間字幕付き MAI-Transcribe-2-Streaming と Apple 翻訳。 | リソースキーとエンドポイント。ストリーミングには Foundry デプロイ名も必要 |
| Nari STT | Nari Qwen3-ASR原文文字起こしです。マイクまたはMac音声を使えます。 | Nari |
| Grok STT | マイクまたはMac音声をGrok Voice Transcribe 2.0で原文に文字起こしします。 | SpaceXAI (xAI) |
| Qwen LiveTranslate | Qwen3.8は専用のリアルタイム翻訳モデルです。Qwen Audio 3.1 Realtime PlusはAirTranslateから翻訳指示を受ける全二重音声会話モデルで、音声応答を返せます。 | Alibaba CloudシンガポールのAPIキー。Qwen3.8にはワークスペースIDも必要 |

Qwen Audio 3.1 ASR Flash Filetransは、設定 > 一般で公開HTTPS音声URLから非同期で文字起こしします。QwenCloudがURLから音声を取得し、この機能はローカル音声ファイルをアップロードしません。

Grok STTは1.10.0から含まれます。初回選択は原文文字起こしで、自分のxAI APIキーを使用します。設定、言語処理、検証範囲は[Grok STTの説明](docs/grok-stt.md)をご確認ください。

Nari STTは1.9.0の任意エンジンです。Nariの初回選択は原文文字起こしとして開始し、原文言語が利用できる場合はApple Translationで翻訳できます。Nariの現在のGA STTモデルIDはqwen3-asr-fastとqwen3-asrで、利用可否、利用制限、有料クレジット条件はNariのプロバイダー文書とアカウント状態に従います。詳細は[docs/nari-stt.md](docs/nari-stt.md)にまとめています。

Nariは韓国語を含む入力言語の手動選択と音声言語の自動検出に対応します。

Nariを新しく選択すると、Nariクレジットが必要なGA Fastモデルを使用します。保存済みのFree Public Betaモデルの選択は保持して開始をブロックし、有料モデルへ自動移行しません。設定 > 一般で課金の案内を確認し、GAモデルを明示的に選択するとNari STTを再開できます。

## フローティング字幕

フローティング字幕は、画面に原文・翻訳の文字だけを重ねます。背景・枠・ツールバー・状態表示・サイズ変更の印は、ポインタを重ねても表示しません。字幕がないときは何も表示しません。設定・メイン画面・メニューバーで操作し、⌘⇧Cで字幕の表示を切り替えます。

標準・映画・講義・高コントラスト・明るい画面用の5つの文字スタイル、4種類のフォント、太さ・行間・影/縁取り・文字色・配置・行数・翻訳を上に表示する設定を用意しています。明暗のサンプル画面で実際の18–72ptサイズを確認し、録音せずにサンプル字幕を表示できます。幅と最前面表示は設定で変更します。既存の外観設定は復元しますが、以前の背景設定が残っていてもウインドウ背景は表示しません。

## Microsoft MAI 音声 (1.15.0)

Azure MAI で **MAI-Transcribe-2-Streaming** を選ぶと中間の原文字幕を表示します。API キー設定に Microsoft Foundry リソースのエンドポイント（`https://<resource>.services.ai.azure.com`）、同じリソースのキーとデプロイ名を入力してください。3 秒ごと、および一時停止・停止時に音声を確定し、確定テキストを Apple で翻訳します。従来の 5 秒単位の MAI-Transcribe-2 も選択できます。

翻訳音声出力で **MAI-Voice-2.1** または **MAI-Voice-2.1-Flash** を選び、**OpenRouter** キーを保存してください。翻訳先の言語と公開音声一覧に合う音声を使用します。韓国語に対応していますが、日本語は現在対応していません。音声生成には翻訳テキストのみを送信し、プロバイダー利用料金は別途発生します。[設定案内](docs/microsoft-mai-audio.md)。

Azure キャプチャの停止時は、制限時間内で最後の確定翻訳を待ちます。空の Azure 最終結果は、メイン画面とフローティング字幕の仮テキストを消去します。

## APIキー

APIキー画面は、**OpenAI**、**Gemini**、**Meta**、**Azure**、**Nari**、**SpaceXAI (xAI)** · **Alibaba Cloud (Qwen)** · **OpenRouter** · **TypeSafe (Jev)**を1つのプロバイダー一覧で管理します。各行には、設定/準備状態、プロバイダーアイコン、キー管理コンソールへのリンク、設定済みキーがプロバイダー権限の検証を意味しないことを説明する情報ポップオーバーが表示されます。

キーはmacOS Keychainに保存されます。AirTranslateにはアカウントシステム、開発者運用の中継サーバー、ハードコードされたプロバイダーキーは含まれていません。

GeminiキーはGemini Liveと任意のGemini翻訳音声出力で共有します。Gemini TTSを選択しても、実アカウントの権限、課金、品質、遅延が検証済みであることは意味しません。

## プライバシー

- EmbeddingGemma 2 ファイル文字起こしは要求時のみモデルをダウンロードし、音声と結果をアップロードせず端末内で処理します。
- Apple ModeはmacOSフレームワークとApple管理の言語アセットを使います。
- GPT、Gemini、Meta、Azure、Nari、Grok、Qwenモードは、選択した機能に必要な音声またはテキストだけを、ユーザーのキーで該当プロバイダーへ直接送信します。Gemini TTSはユーザーがGemini音声モデルを選んだ後、安定した翻訳テキストだけを送信します。
- 保存済み記録は、ファイル保存を有効にした場合にだけMac上の通常のテキストファイルとして残ります。
- より詳しいプロバイダーと保存の説明は[Release/PRIVACY-NOTICE.md](Release/PRIVACY-NOTICE.md)を参照してください。

## 必要条件

- macOS 26.0以降
- 任意の EmbeddingGemma 2 ファイル文字起こし: Apple Silicon・macOS 27 以降
- ソースビルド用Swift 6.4以降
- システムオーディオ取り込みに対応したMac
- Apple SpeechとApple Translationフレームワークが利用できる環境
- 任意: OpenAI、Gemini、Meta、Azure Speech、Nari、xAI、Alibaba Cloudのプロバイダーキー

## ドキュメント

- [Getting Started](docs/GETTING-STARTED.md)
- [Development](docs/DEVELOPMENT.md)
- [Nari STT notes](docs/nari-stt.md)
- [EmbeddingGemma 2 の手法とファイル文字起こし](docs/embeddinggemma-transcription.md)
- [変更履歴](CHANGELOG.md)
- [バージョン履歴](Release/VERSION-HISTORY.md)

<details>
<summary>ソースからビルド</summary>

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
swift test
```

その他のコマンドは[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)にあります。

</details>

## コントリビュート

ユーザー向けのリリース履歴は[CHANGELOG.md](CHANGELOG.md)に保管します。READMEは過去のリリースノートを繰り返すのではなく、現在の製品、ダウンロード経路、プロバイダー境界を説明します。

## ライセンス

AirTranslateは[Apache License 2.0](LICENSE)で公開されています。著作権表記は[NOTICE](NOTICE)にあります。

AirTranslateは独立したオープンソースプロジェクトであり、Apple、OpenAI、Google、Meta、Microsoft、Nari、SpaceXAI (xAI)、Alibaba Cloudとは提携していません。
