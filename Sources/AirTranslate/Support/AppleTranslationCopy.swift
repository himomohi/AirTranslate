import Foundation

enum AppleTranslationCopy {
    static var termsFallback: String { AppText.localized(english: "Apple did not preserve a registered term. The affected segment was kept in its original language.", korean: "Apple이 등록 용어를 보존하지 않아 해당 구간을 원문으로 유지했습니다.", japanese: "Apple が登録用語を保持しなかったため、該当部分は原文を維持しました。", chineseSimplified: "Apple 未保留注册术语，相关片段已保留原文。") }
    static var termsFallbackHelp: String { AppText.localized(english: "If Apple changes a protected term, the whole affected segment stays in its original language. Remove the term to allow full translation.", korean: "Apple이 용어를 바꾸면 해당 구간 전체를 원문으로 유지합니다. 전체 번역이 필요하면 해당 용어를 목록에서 지우세요.", japanese: "Apple が用語を変更した場合、該当部分全体を原文のまま保持します。すべて翻訳するには該当用語を削除してください。", chineseSimplified: "如果 Apple 更改术语，相关片段将全部保留原文。如需完整翻译，请从列表中移除该术语。") }
    static var fallbackTitle: String { AppText.localized(english: "Realtime fallback", korean: "실시간으로 복귀", japanese: "リアルタイムに復帰", chineseSimplified: "已回退到实时") }
    static var fallbackDetail: String { AppText.localized(english: "The quality-first model failed for this language pair. Realtime translation will be used until the app restarts. Protected terms still apply.", korean: "이 언어쌍의 품질 우선 모델이 실패해 앱을 다시 실행할 때까지 실시간 번역을 사용합니다. 등록한 용어는 계속 보존합니다.", japanese: "この言語ペアの品質優先モデルが失敗したため、アプリを再起動するまでリアルタイム翻訳を使用します。登録した用語は引き続き保持します。", chineseSimplified: "此语言对的质量优先模型失败，将使用实时翻译，直到重新启动应用。已注册的术语仍会保留。") }
    static var title: String { AppText.localized(english: "Apple translation", korean: "Apple 번역", japanese: "Apple 翻訳", chineseSimplified: "Apple 翻译") }
    static var quality: String { AppText.localized(english: "Translation quality", korean: "번역 품질", japanese: "翻訳品質", chineseSimplified: "翻译质量") }
    static var detail: String { AppText.localized(english: "Realtime favors speed and lower power use. Quality first uses Apple Intelligence when available and may take longer; otherwise Apple uses traditional translation. Applies only to Apple text translation.", korean: "실시간은 빠른 응답과 낮은 전력 사용을 우선합니다. 품질 우선은 사용 가능한 Apple Intelligence를 활용하며 더 오래 걸릴 수 있습니다. 사용할 수 없으면 Apple이 기존 번역 모델로 처리합니다. Apple 텍스트 번역에만 적용됩니다.", japanese: "リアルタイムは速度と省電力を優先します。品質優先は利用可能な Apple Intelligence を使用するため時間がかかる場合があります。利用できない場合は従来の翻訳を使用します。Apple のテキスト翻訳に適用されます。", chineseSimplified: "实时模式优先考虑速度和低功耗。质量优先使用可用的 Apple Intelligence，可能耗时更长；不可用时使用传统翻译。仅适用于 Apple 文本翻译。") }
    static func title(for quality: AppleTranslationQuality) -> String {
        switch quality {
        case .realtime: AppText.localized(english: "Realtime", korean: "실시간", japanese: "リアルタイム", chineseSimplified: "实时")
        case .highQuality: AppText.localized(english: "Quality first", korean: "품질 우선", japanese: "品質優先", chineseSimplified: "质量优先")
        }
    }
    static var protectedTerms: String { AppText.localized(english: "Keep these terms unchanged", korean: "번역하지 않을 용어", japanese: "翻訳しない用語", chineseSimplified: "不翻译的术语") }
    static var termsDetail: String { AppText.localized(english: "Enter one product name or technical term per line. Matching text keeps its original spelling. Up to 100 unique terms, 80 characters each, 8,000 characters total. Longer terms are excluded. This does not correct speech recognition.", korean: "제품명·전문 용어를 한 줄에 하나씩 입력하세요. 일치하는 부분은 원래 표기를 유지합니다. 중복을 제외한 최대 100개, 용어당 80자, 전체 8,000자까지이며 긴 용어는 제외됩니다. 음성 인식 오류를 교정하는 기능은 아닙니다.", japanese: "製品名や専門用語を1行に1つ入力します。一致部分の元の表記を保持します。重複を除き100件、各80文字、全体8,000文字まで。長い用語は除外されます。音声認識の誤りは修正しません。", chineseSimplified: "每行输入一个产品名或专业术语，匹配部分保留原始拼写。去重后最多100项，每项80字，总计8,000字。超长术语会被排除。此功能不修正语音识别错误。") }
    static func acceptedTerms(_ count: Int) -> String { AppText.localized(english: "\(count) terms registered", korean: "\(count)개 용어 등록", japanese: "\(count)件の用語を登録", chineseSimplified: "已注册\(count)个术语") }
    static var requiresRecentOS: String { AppText.localized(english: "Quality selection and protected terms require macOS 26.4 or later. Realtime translation remains available.", korean: "품질 선택과 용어 보존은 macOS 26.4 이상에서 사용할 수 있습니다. 기존 실시간 번역은 계속 사용할 수 있습니다.", japanese: "品質選択と用語保持は macOS 26.4 以降で利用できます。従来のリアルタイム翻訳は利用可能です。", chineseSimplified: "质量选择和术语保留需要 macOS 26.4 或更高版本。传统实时翻译仍可使用。") }
    static var appleOnly: String { AppText.localized(english: "Select a mode that uses Apple text translation to edit these options.", korean: "Apple 텍스트 번역을 사용하는 모드에서 변경할 수 있습니다.", japanese: "Apple のテキスト翻訳を使用するモードで変更できます。", chineseSimplified: "使用 Apple 文本翻译的模式下可更改这些选项。") }
}
