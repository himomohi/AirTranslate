import Foundation

enum HyMTCopy {
    static let title = "Hy-MT2"
    static let model = "Hy-MT2 1.8B · Q4_K_M"
    static var detail: String { copy("Apple speech recognition + local Hy-MT2 translation. Download once (1.13 GB); no API key or server required.", "Apple 음성 인식 + 로컬 Hy-MT2 번역. 모델을 한 번 다운로드하면(1.13GB) API 키나 서버 없이 사용할 수 있습니다.", "Apple音声認識 + ローカルHy-MT2翻訳。モデルを一度ダウンロードすると（1.13 GB）、APIキーやサーバーは不要です。", "Apple 语音识别 + 本地 Hy-MT2 翻译。一次下载模型（1.13 GB）后，无需 API 密钥或服务器。") }
    static var price: String { copy("On-device · no API usage fee", "기기 내 실행 · API 사용료 없음", "デバイス内実行 · API利用料なし", "设备端运行 · 无 API 使用费") }
    static var download: String { copy("Download model (1.13 GB)", "모델 다운로드 (1.13GB)", "モデルをダウンロード（1.13 GB）", "下载模型（1.13 GB）") }
    static var cancel: String { copy("Cancel download", "다운로드 취소", "ダウンロードを中止", "取消下载") }
    static var remove: String { copy("Delete downloaded model", "다운로드한 모델 삭제", "ダウンロードしたモデルを削除", "删除已下载的模型") }
    static var removeDetail: String { copy("Delete only the Hy-MT2 model downloaded by AirTranslate? You can download it again.", "AirTranslate가 다운로드한 Hy-MT2 모델을 삭제합니다. 나중에 다시 다운로드할 수 있습니다.", "AirTranslateがダウンロードしたHy-MT2モデルを削除します。再ダウンロードできます。", "删除 AirTranslate 下载的 Hy-MT2 模型，可再次下载。") }
    static var ready: String { copy("Model ready · runs on this Mac", "모델 준비됨 · 이 Mac에서 실행", "モデル準備完了 · このMacで実行", "模型已就绪 · 在此 Mac 上运行") }
    static var checking: String { copy("Verifying model…", "모델 검증 중…", "モデルを検証中…", "正在验证模型…") }
    static var required: String { copy("Download the Hy-MT2 model in Settings → General before starting.", "설정 → 일반에서 Hy-MT2 모델을 먼저 다운로드해 주세요.", "設定 → 一般でHy-MT2モデルをダウンロードしてください。", "请先在设置 → 通用中下载 Hy-MT2 模型。") }
    static var preview: String { copy("Test local translation", "로컬 번역 확인", "ローカル翻訳を確認", "测试本地翻译") }
    static var previewInput: String { copy("Text to translate", "번역할 문장", "翻訳する文章", "要翻译的文本") }
    static var previewResult: String { copy("Translation result", "번역 결과", "翻訳結果", "翻译结果") }
    static var terminology: String { copy("Names and terminology", "이름·전문 용어", "名前・専門用語", "名称与术语") }
    static var terminologyDetail: String { copy("Optional: one canonical name per line, up to 32. Recent captions provide context. For registered names containing acronyms, matching English phonetic spellings are normalized only in the translation input. Apple transcription text is preserved; check the result.", "정확한 이름을 한 줄에 하나씩 최대 32개 입력하세요. 앞선 자막도 문맥으로 참고합니다. 약어가 포함된 등록 용어는 발음 형태가 일치하는 영어 인식 표기를 번역 입력에서만 정리합니다. Apple 인식 원문은 보존하며 결과 확인이 필요합니다.", "正しい名称を1行に1つ、最大32個入力します。直前の字幕も文脈として参照します。略語を含む登録名は英語の発音表記が一致する場合に翻訳入力のみ整えます。Appleの認識原文は保持されます。結果をご確認ください。", "可选：每行一个规范名称，最多32个，并参考近期字幕。对于包含缩写的已登记名称，仅在翻译输入中规范发音形式匹配的英文识别文本。保留Apple识别原文，请核对结果。") }
    static func copy(_ en: String, _ ko: String, _ ja: String, _ zh: String) -> String {
        AppText.localized(english: en, korean: ko, japanese: ja, chineseSimplified: zh)
    }
}
