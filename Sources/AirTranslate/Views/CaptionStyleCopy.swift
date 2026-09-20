import Foundation

enum CaptionStyleCopy {
    static func text(_ english: String, _ korean: String, _ japanese: String, _ chinese: String) -> String {
        AppText.localized(english: english, korean: korean, japanese: japanese, chineseSimplified: chinese)
    }
    static var presets: String { text("Choose a style", "스타일 고르기", "スタイルを選ぶ", "选择样式") }
    static var on: String { text("On", "켜짐", "オン", "开启") }
    static var off: String { text("Off", "꺼짐", "オフ", "关闭") }
    static var presetHint: String { text("Styles change appearance only. Your audio and language choices stay the same.", "스타일은 모양만 바꿉니다. 오디오와 언어 설정은 유지됩니다.", "見た目だけを変更します。音声と言語の設定は維持されます。", "样式只改变外观，保留音频与语言设置。") }
    static var custom: String { text("Custom", "사용자 설정", "カスタム", "自定义") }
    static var preview: String { text("Preview", "미리보기", "プレビュー", "预览") }
    static var sample: String { text("Sample captions · No recording", "샘플 자막 · 녹음 안 함", "サンプル字幕・録音なし", "示例字幕 · 不录音") }
    static var previewHint: String { text("Actual text size. Scroll inside for long captions, or preview in the window without recording.", "실제 글자 크기입니다. 긴 내용은 안에서 스크롤하거나 녹음 없이 자막 창에서 확인하세요.", "実際の文字サイズです。長い字幕は中をスクロールするか、録音せずに字幕ウインドウで確認できます。", "实际字号。长字幕可在预览内滚动，也可在不录音的情况下打开字幕窗口。") }
    static var previewWindow: String { text("Preview in caption window", "자막 창에서 미리보기", "字幕ウインドウで確認", "在字幕窗口中预览") }
    static var openWindow: String { text("Show captions", "자막 표시", "字幕を表示", "显示字幕") }
    static var closeWindow: String { text("Hide captions", "자막 숨기기", "字幕を非表示", "隐藏字幕") }
    static var toggleCaptions: String { text("Show or hide captions", "자막 표시/숨기기", "字幕の表示切替", "显示或隐藏字幕") }
    static var width: String { text("Caption width", "자막 가로 폭", "字幕の幅", "字幕宽度") }
    static var captionOnlyHint: String { text("Only captions appear over your content. Adjust them here; the overlay has no background, controls, or status text.", "화면 위에는 자막만 표시됩니다. 배경·버튼·상태 표시는 없으며 자막은 이 설정에서 조절합니다.", "画面には字幕だけを重ねます。背景・操作ボタン・状態表示はなく、ここで調整します。", "画面上仅显示字幕，没有背景、按钮或状态文字。请在此调整字幕。") }
    static var listening: String { text("Listening", "듣는 중", "聞き取り中", "正在聆听") }
    static var paused: String { text("Paused", "일시정지됨", "一時停止中", "已暂停") }
    static var settings: String { text("Caption settings", "자막 설정", "字幕設定", "字幕设置") }
    static var content: String { text("Content and reading", "표시와 읽기", "表示と読みやすさ", "内容与阅读") }
    static var typography: String { text("Text details", "글자 세부 설정", "文字の詳細", "文字详情") }
    static var surface: String { text("Colors and background", "색상과 배경", "色と背景", "颜色与背景") }
    static var window: String { text("Placement", "배치", "配置", "位置") }
    static var font: String { text("Font", "글꼴", "フォント", "字体") }
    static var weight: String { text("Weight", "글자 굵기", "文字の太さ", "字重") }
    static var spacing: String { text("Line spacing", "줄 간격", "行間", "行距") }
    static var effect: String { text("Text effect", "글자 효과", "文字効果", "文字效果") }
    static var corners: String { text("Background shape", "배경 모서리", "背景の形", "背景形状") }
    static var translationFirst: String { text("Translation above original", "번역을 원문 위에 표시", "翻訳を原文の上に表示", "译文显示在原文上方") }
    static var keepOnTop: String { text("Keep above other windows", "다른 창 위에 표시", "ほかのウインドウの上に表示", "置于其他窗口上方") }
    static var resetStyle: String { text("Reset style", "스타일 초기화", "スタイルをリセット", "重置样式") }
    static var resetStyleHint: String { text("Reset text, colors, alignment and reading stability? Audio and languages are unchanged.", "글자·색상·정렬·표시 안정성을 기본값으로 되돌립니다. 오디오와 언어는 유지됩니다.", "文字・色・配置・表示の安定性を初期値に戻します。音声と言語は維持されます。", "重置文字、颜色、对齐和显示稳定性。保留音频与语言。") }
    static var cancel: String { text("Cancel", "취소", "キャンセル", "取消") }
    static var lightScene: String { text("Light scene", "밝은 화면", "明るい画面", "明亮画面") }
    static var darkScene: String { text("Dark scene", "어두운 화면", "暗い画面", "深色画面") }
    static var scene: String { text("Preview background", "미리보기 배경", "プレビュー背景", "预览背景") }
    static var size: String { text("Text size", "글자 크기", "文字サイズ", "字号") }
    static var smaller: String { text("Smaller captions", "자막 글자 작게", "字幕を小さく", "缩小字幕") }
    static var larger: String { text("Larger captions", "자막 글자 크게", "字幕を大きく", "放大字幕") }
    static var lineHint: String { text("Maximum per language. Short windows show fewer lines to keep text readable.", "언어별 최대 줄 수입니다. 창이 작으면 읽을 수 있는 줄 수로 조정됩니다.", "言語ごとの最大行数です。小さいウインドウでは行数を減らします。", "每种语言的最大行数。窗口较小时会减少行数以保持可读性。") }
    static var opacityHint: String { text("Only the background fades; text stays opaque.", "배경만 투명해지고 글자는 선명하게 유지됩니다.", "背景だけが透明になり、文字はくっきり表示されます。", "仅背景变透明，文字保持清晰。") }
    static var reducedTransparency: String { text("Reduce Transparency is on: the preview and caption window use a solid background.", "투명도 줄이기가 켜져 있어 미리보기와 자막 창에 불투명 배경을 사용합니다.", "透明度を下げる設定により、字幕の背景を不透明にしています。", "已开启降低透明度，字幕使用不透明背景。") }
    static var invalidColor: String { text("Enter six hexadecimal digits, such as #FFFFFF.", "#FFFFFF처럼 6자리 색상 코드를 입력하세요.", "#FFFFFFのように6桁で入力してください。", "请输入 #FFFFFF 这样的六位颜色代码。") }
    static var sampleOriginal: String { "Make room for the words that matter. Read at your own pace, wherever you listen." }
    static var sampleTranslation: String { text("Make room for the words that matter. Read at your own pace, wherever you listen.", "중요한 말에 집중하세요. 어디서 듣든, 나에게 편한 속도로 읽을 수 있습니다.", "大切な言葉に集中しましょう。どこで聞いていても、自分のペースで読めます。", "专注于重要的话语。无论在哪里聆听，都能按自己的节奏阅读。") }
}
