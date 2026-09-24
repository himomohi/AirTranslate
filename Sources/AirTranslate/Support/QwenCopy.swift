import Foundation

enum QwenCopy {
    static let title = "Qwen LiveTranslate"
    static let provider = "Alibaba Cloud · Qwen"
    static let detail = copy("Qwen3.8 live translation with automatic source detection and optional speech. Audio is sent to Alibaba Cloud in Singapore.", "입력 언어를 자동 감지하는 Qwen3.8 실시간 번역입니다. 음성 출력을 선택할 수 있으며, 오디오는 Alibaba Cloud 싱가포르로 전송됩니다.", "入力言語を自動検出するQwen3.8リアルタイム翻訳。音声出力を選択でき、音声はAlibaba Cloudのシンガポールに送信されます。", "Qwen3.8 实时翻译，自动检测源语言，可选语音输出。音频发送至阿里云新加坡。")
    static let modelLabel = copy("Realtime model", "실시간 모델", "リアルタイムモデル", "实时模型")
    static let modelDetail = copy("Choose the Qwen model used for live translation.", "실시간 번역에 사용할 Qwen 모델을 선택하세요.", "ライブ翻訳に使用するQwenモデルを選択してください。", "选择用于实时翻译的 Qwen 模型。")
    static func detail(for model: QwenTranslationModel) -> String {
        switch model {
        case .off, .liveTranslateFlashRealtime: detail
        case .audio31RealtimePlus:
            copy("Qwen documents Audio 3.1 Realtime Plus as a full-duplex voice-conversation model. AirTranslate gives it translation instructions and can use its spoken response. Audio is sent to Alibaba Cloud in Singapore.", "Qwen Audio 3.1 Realtime Plus는 양방향 실시간 음성 대화 모델입니다. AirTranslate가 번역 지시를 전달하고, 필요하면 모델의 음성 응답을 사용합니다. 오디오는 Alibaba Cloud 싱가포르로 전송됩니다.", "Qwen Audio 3.1 Realtime Plusは全二重のリアルタイム音声会話モデルです。AirTranslateが翻訳指示を渡し、必要に応じてモデルの音声応答を使用します。音声はAlibaba Cloudのシンガポールに送信されます。", "Qwen Audio 3.1 Realtime Plus 是全双工实时语音对话模型。AirTranslate 会向其提供翻译指令，并可使用模型的语音响应。音频会发送至阿里云新加坡。")
        }
    }
    static func price(for model: QwenTranslationModel) -> String {
        switch model {
        case .off, .liveTranslateFlashRealtime: price
        case .audio31RealtimePlus:
            copy("Usage-based QwenCloud pricing. Check the current Singapore rate in Model Studio.", "QwenCloud 사용량 기준 과금입니다. 현재 싱가포르 요금은 Model Studio에서 확인하세요.", "QwenCloudの使用量に応じた課金です。シンガポールの最新料金はModel Studioで確認してください。", "按 QwenCloud 使用量计费。请在 Model Studio 查看新加坡当前价格。")
        }
    }
    static let apiKeyRequired = copy("Add a Singapore API key in Settings → API Keys → Qwen.", "설정 → API 키 → Qwen에서 싱가포르 API 키를 입력해 주세요.", "設定 → APIキー → QwenでシンガポールのAPIキーを入力してください。", "请在设置 → API 密钥 → Qwen 中输入新加坡 API 密钥。")
    static let configurationRequired = copy("Add a Singapore API key and workspace ID in Settings → API Keys → Qwen.", "설정 → API 키 → Qwen에서 싱가포르 API 키와 워크스페이스 ID를 입력해 주세요.", "設定 → APIキー → QwenでシンガポールのAPIキーとワークスペースIDを入力してください。", "请在设置 → API 密钥 → Qwen 中输入新加坡 API 密钥和工作空间 ID。")
    static func configurationRequired(for model: QwenTranslationModel) -> String {
        guard model == .liveTranslateFlashRealtime else { return apiKeyRequired }
        return configurationRequired
    }
    static let workspaceLabel = copy("Workspace ID · Singapore", "워크스페이스 ID · 싱가포르", "ワークスペースID · シンガポール", "工作空间 ID · 新加坡")
    static let workspaceHint = copy("Required for Qwen3.8 LiveTranslate. Qwen Audio 3.1 Realtime Plus and Filetrans use the Singapore API key without this ID.", "Qwen3.8 LiveTranslate에 필요합니다. Qwen Audio 3.1 Realtime Plus와 Filetrans는 이 ID 없이 싱가포르 API 키를 사용합니다.", "Qwen3.8 LiveTranslateで必要です。Qwen Audio 3.1 Realtime PlusとFiletransはこのIDなしでシンガポールのAPIキーを使用します。", "Qwen3.8 LiveTranslate 需要此 ID。Qwen Audio 3.1 Realtime Plus 和 Filetrans 使用新加坡 API 密钥时无需此 ID。")
    static let keyInvalid = copy("Enter a valid Qwen API key.", "올바른 Qwen API 키를 입력해 주세요.", "有効なQwen APIキーを入力してください。", "请输入有效的 Qwen API 密钥。")
    static let connecting = copy("Connecting to Qwen LiveTranslate…", "Qwen LiveTranslate 연결 중…", "Qwen LiveTranslateに接続中…", "正在连接 Qwen LiveTranslate…")
    static let finishing = copy("Finishing Qwen translation…", "마지막 Qwen 번역을 받는 중…", "Qwenの最後の翻訳を受信中…", "正在接收最后的 Qwen 翻译…")
    static let reconnecting = copy("Reconnecting to Qwen…", "Qwen 다시 연결 중…", "Qwenに再接続中…", "正在重新连接 Qwen…")
    static let price = copy("Singapore · input $0.189/hour + translated text $20/1M tokens; speech output +$1.35/hour. Source transcript is free. Checked 2026-09-20.", "싱가포르 · 입력 $0.189/시간 + 번역문 $20/100만 토큰 · 음성 출력 추가 $1.35/시간. 원문 전사는 무료. 2026-09-20 확인.", "シンガポール · 入力 $0.189/時間 + 翻訳文 $20/100万トークン · 音声出力 +$1.35/時間。原文文字起こしは無料。2026-09-20確認。", "新加坡 · 输入 $0.189/小时 + 译文 $20/百万 token；语音输出另加 $1.35/小时。原文转写免费。2026-09-20 确认。")
    static let fileTranscriptionTitle = copy("Transcribe an audio file", "오디오 파일 전사", "音声ファイルを文字起こし", "转写音频文件")
    static let fileTranscriptionDetail = copy("Qwen Audio 3.1 ASR Flash Filetrans processes a publicly accessible audio URL asynchronously (up to 12 hours / 2 GB). The file URL is sent to QwenCloud; local files are not uploaded by AirTranslate.", "Qwen Audio 3.1 ASR Flash Filetrans가 공개된 오디오 URL을 비동기로 처리합니다(최대 12시간/2GB). 파일 URL은 QwenCloud에 전송되며 AirTranslate가 로컬 파일을 업로드하지 않습니다.", "Qwen Audio 3.1 ASR Flash Filetransは公開音声URLを非同期で処理します（最大12時間/2GB）。ファイルURLはQwenCloudへ送信され、AirTranslateがローカルファイルをアップロードすることはありません。", "Qwen Audio 3.1 ASR Flash Filetrans 异步处理可公开访问的音频 URL（最长 12 小时/2 GB）。文件 URL 会发送给 QwenCloud；AirTranslate 不会上传本地文件。")
    static let fileTranscriptionURLLabel = copy("Public HTTPS audio URL", "공개 HTTPS 오디오 URL", "公開HTTPS音声URL", "公开 HTTPS 音频 URL")
    static let fileTranscriptionURLPlaceholder = "https://example.com/audio.mp3"
    static let fileTranscriptionPrivacy = copy("QwenCloud fetches the file from this URL. Use a link you are allowed to share.", "QwenCloud가 이 URL에서 파일을 가져옵니다. 공유 권한이 있는 링크를 사용하세요.", "QwenCloudがこのURLからファイルを取得します。共有が許可されたリンクを使用してください。", "QwenCloud 会从此 URL 获取文件。请使用有权分享的链接。")
    static let fileTranscriptionStart = copy("Transcribe", "전사 시작", "文字起こし", "开始转写")
    static let fileTranscriptionCancel = copy("Stop waiting", "대기 중지", "待機を停止", "停止等待")
    static let fileTranscriptionCopy = copy("Copy transcript", "전사 복사", "文字起こしをコピー", "复制转写文本")
    static let fileTranscriptionWorking = copy("Submitting and waiting for QwenCloud…", "QwenCloud에 요청하고 결과를 기다리는 중…", "QwenCloudに送信して結果を待っています…", "正在提交到 QwenCloud 并等待结果…")
    static let fileTranscriptionInvalidURL = copy("Enter a public HTTPS audio URL without a username, password, or non-standard port.", "사용자 이름·비밀번호·별도 포트가 없는 공개 HTTPS 오디오 URL을 입력하세요.", "ユーザー名・パスワード・標準外ポートを含まない公開HTTPS音声URLを入力してください。", "请输入不含用户名、密码或非标准端口的公开 HTTPS 音频 URL。")
    static let fileTranscriptionUnavailable = copy("QwenCloud could not complete the file transcription. Check API key authorization, model access, quota, and service status.", "QwenCloud 파일 전사를 완료하지 못했습니다. API 키 권한·모델 접근 권한·할당량·서비스 상태를 확인하세요.", "QwenCloudのファイル文字起こしを完了できませんでした。APIキーの権限・モデルへのアクセス・利用枠・サービス状況を確認してください。", "QwenCloud 无法完成文件转写。请检查 API 密钥权限、模型访问权限、配额和服务状态。")
    static let fileTranscriptionInvalidResponse = copy("QwenCloud returned an unexpected file transcription response.", "QwenCloud가 예상하지 못한 파일 전사 응답을 반환했습니다.", "QwenCloudから予期しないファイル文字起こし応答が返されました。", "QwenCloud 返回了意外的文件转写响应。")
    static let fileTranscriptionFailed = copy("QwenCloud could not transcribe this audio file.", "QwenCloud에서 이 오디오 파일을 전사하지 못했습니다.", "QwenCloudはこの音声ファイルを文字起こしできませんでした。", "QwenCloud 无法转写此音频文件。")
    static let fileTranscriptionEmpty = copy("QwenCloud completed the task but returned no transcript.", "QwenCloud 작업은 완료됐지만 전사 결과가 비어 있습니다.", "QwenCloudの処理は完了しましたが、文字起こし結果は空です。", "QwenCloud 已完成任务，但没有返回转写文本。")
    static let fileTranscriptionTooLarge = copy("The transcript is too large to display in AirTranslate.", "전사 결과가 너무 커서 AirTranslate에서 표시할 수 없습니다.", "文字起こし結果が大きすぎてAirTranslateに表示できません。", "转写结果过大，无法在 AirTranslate 中显示。")
    static let fileTranscriptionTimeout = copy("QwenCloud has not completed this task yet. Try again later.", "QwenCloud 작업이 아직 끝나지 않았습니다. 잠시 후 다시 시도하세요.", "QwenCloudの処理はまだ完了していません。後でもう一度お試しください。", "QwenCloud 尚未完成此任务，请稍后重试。")
    private static func copy(_ en: String, _ ko: String, _ ja: String, _ zh: String) -> String {
        AppText.localized(english: en, korean: ko, japanese: ja, chineseSimplified: zh)
    }
}
