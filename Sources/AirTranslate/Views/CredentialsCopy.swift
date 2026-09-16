import Foundation

enum CredentialsCopy {
    static let pageDetail = AppText.localized(english: "Manage your cloud providers in one place.", korean: "클라우드 서비스의 키를 한곳에서 관리합니다.", japanese: "クラウドサービスのキーをまとめて管理します。", chineseSimplified: "在一处管理云服务密钥。")
    static let providers = AppText.localized(english: "Providers", korean: "서비스", japanese: "サービス", chineseSimplified: "服务")
    static let saved = AppText.localized(english: "Saved", korean: "저장됨", japanese: "保存済み", chineseSimplified: "已保存")
    static let keyNeeded = AppText.localized(english: "Add key", korean: "키 필요", japanese: "キー未設定", chineseSimplified: "待添加密钥")
    static let setupNeeded = AppText.localized(english: "Setup needed", korean: "설정 필요", japanese: "要設定", chineseSimplified: "待配置")
    static let inUse = AppText.localized(english: "Selected", korean: "선택됨", japanese: "選択中", chineseSimplified: "已选择")
    static let keyLabel = AppText.localized(english: "API key", korean: "API 키", japanese: "APIキー", chineseSimplified: "API 密钥")
    static let pasteKey = AppText.localized(english: "Paste API key", korean: "API 키 붙여넣기", japanese: "APIキーを貼り付け", chineseSimplified: "粘贴 API 密钥")
    static let replaceKey = AppText.localized(english: "Paste a new key to replace", korean: "새 키를 붙여넣어 교체", japanese: "新しいキーを貼り付けて置換", chineseSimplified: "粘贴新密钥以替换")
    static let keyHint = AppText.localized(english: "Press Return to save. The existing key stays unchanged until you save.", korean: "Return 키로 저장합니다. 저장 전까지 기존 키는 유지됩니다.", japanese: "Returnで保存します。保存するまで既存のキーは変わりません。", chineseSimplified: "按 Return 保存。保存前原密钥保持不变。")
    static let removed = AppText.localized(english: "Key removed", korean: "키 삭제됨", japanese: "キーを削除しました", chineseSimplified: "密钥已删除")
    static let done = AppText.localized(english: "Done", korean: "완료", japanese: "完了", chineseSimplified: "完成")
    static let expanded = AppText.localized(english: "Expanded", korean: "펼쳐짐", japanese: "展開済み", chineseSimplified: "已展开")
    static let collapsed = AppText.localized(english: "Collapsed", korean: "접힘", japanese: "折りたたみ", chineseSimplified: "已折叠")
    static let keychain = AppText.localized(english: "Stored in this Mac’s Keychain", korean: "이 Mac의 키체인에 안전하게 보관", japanese: "このMacのキーチェーンに安全に保存", chineseSimplified: "安全保存在此 Mac 的钥匙串中")
    static let storageInfo = AppText.localized(english: "Key storage information", korean: "키 보관 정보", japanese: "キーの保存について", chineseSimplified: "密钥存储信息")
    static let savedDoesNotVerify = AppText.localized(english: "Saved means a key is stored on this Mac. The provider checks access when you start a session.", korean: "‘저장됨’은 이 Mac에 키가 있다는 뜻입니다. 서비스 이용 권한은 세션을 시작할 때 확인됩니다.", japanese: "「保存済み」はこのMacにキーがあることを示します。利用権限はセッション開始時に確認されます。", chineseSimplified: "“已保存”表示密钥存于此 Mac。服务访问权限会在开始会话时检查。")
    static let locked = AppText.localized(english: "Stop the session to edit keys.", korean: "세션을 중지하면 키를 변경할 수 있습니다.", japanese: "キーを変更するにはセッションを停止してください。", chineseSimplified: "停止会话后可修改密钥。")
    static let endpoint = AppText.localized(english: "Endpoint", korean: "엔드포인트", japanese: "エンドポイント", chineseSimplified: "终结点")
    static let endpointRequired = AppText.localized(english: "Enter your Azure Speech resource’s HTTPS endpoint.", korean: "Azure Speech 리소스의 HTTPS 주소를 입력하세요.", japanese: "Azure SpeechリソースのHTTPSアドレスを入力してください。", chineseSimplified: "请输入 Azure Speech 资源的 HTTPS 地址。")

    static func edit(_ name: String) -> String {
        AppText.localized(english: "Edit \(name) key", korean: "\(name) 키 편집", japanese: "\(name)キーを編集", chineseSimplified: "编辑 \(name) 密钥")
    }
    static func details(_ name: String) -> String {
        AppText.localized(english: "About \(name)", korean: "\(name) 정보", japanese: "\(name)について", chineseSimplified: "关于 \(name)")
    }
    static func console(_ name: String) -> String {
        AppText.localized(english: "Open \(name) key console", korean: "\(name) 키 발급 페이지 열기", japanese: "\(name)のキー管理ページを開く", chineseSimplified: "打开 \(name) 密钥管理页面")
    }
    static func save(_ name: String) -> String {
        AppText.localized(english: "Save \(name) key", korean: "\(name) 키 저장", japanese: "\(name)キーを保存", chineseSimplified: "保存 \(name) 密钥")
    }
    static func remove(_ name: String) -> String {
        AppText.localized(english: "Remove \(name) key", korean: "\(name) 키 삭제", japanese: "\(name)キーを削除", chineseSimplified: "删除 \(name) 密钥")
    }
    static func confirmRemoval(_ name: String) -> String {
        AppText.localized(english: "Remove the saved \(name) key from this Mac?", korean: "이 Mac에 저장된 \(name) 키를 삭제할까요?", japanese: "このMacに保存された\(name)キーを削除しますか？", chineseSimplified: "要删除保存在此 Mac 上的 \(name) 密钥吗？")
    }
    static func summary(saved: Int, total: Int) -> String {
        AppText.localized(english: "\(saved) of \(total) keys saved", korean: "\(total)개 중 \(saved)개 저장됨", japanese: "\(total)件中\(saved)件を保存済み", chineseSimplified: "已保存 \(saved)/\(total) 个密钥")
    }
}
