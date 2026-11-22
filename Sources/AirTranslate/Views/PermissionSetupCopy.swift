enum PermissionSetupCopy {
    static let title = AppText.localized(
        english: "Permissions for Current Mode", korean: "현재 모드에 필요한 권한",
        japanese: "現在のモードに必要な権限", chineseSimplified: "当前模式所需权限"
    )
    static let start = AppText.localized(
        english: "Set Up Permissions", korean: "권한 설정 시작",
        japanese: "権限設定を開始", chineseSimplified: "开始设置权限"
    )
    static let ready = AppText.localized(
        english: "Required permissions are ready", korean: "필요한 권한을 모두 확인했습니다",
        japanese: "必要な権限を確認しました", chineseSimplified: "所需权限均已就绪"
    )
    static let instruction = AppText.localized(
        english: "Respond to the macOS prompts as they appear.", korean: "macOS 승인 창이 나타나면 허용 여부를 선택하세요.",
        japanese: "macOS の確認画面が表示されたら選択してください。", chineseSimplified: "macOS 弹出提示时，请选择是否允许。"
    )
    static let screenInstruction = AppText.localized(
        english: "Allow AirTranslate under Screen & System Audio Recording. If macOS asks, quit and reopen AirTranslate.",
        korean: "‘화면 및 시스템 오디오 기록’에서 AirTranslate를 허용하세요. macOS가 요청하면 앱을 종료한 뒤 다시 여세요.",
        japanese: "「画面とシステムオーディオ録音」で AirTranslate を許可してください。macOS に求められたらアプリを開き直してください。",
        chineseSimplified: "请在“屏幕与系统音频录制”中允许 AirTranslate。若 macOS 提示，请退出并重新打开应用。"
    )

    static func checking(_ permission: String) -> String {
        AppText.localized(
            english: "Checking \(permission)…", korean: "\(permission) 권한 확인 중…",
            japanese: "\(permission)の権限を確認中…", chineseSimplified: "正在检查\(permission)权限…"
        )
    }

    static func resumeInstruction(_ permission: String) -> String {
        AppText.localized(
            english: "Allow \(permission) in System Settings, then return to AirTranslate to continue.",
            korean: "시스템 설정에서 \(permission) 권한을 허용한 뒤 AirTranslate로 돌아오면 이어서 진행합니다.",
            japanese: "システム設定で\(permission)を許可し、AirTranslate に戻ると続行します。",
            chineseSimplified: "请在系统设置中允许\(permission)，然后返回 AirTranslate 继续。"
        )
    }

    static func restricted(_ permission: String) -> String {
        AppText.localized(
            english: "Access to \(permission) is restricted by macOS.",
            korean: "macOS에서 \(permission) 권한을 제한하고 있습니다.",
            japanese: "macOS が\(permission)へのアクセスを制限しています。",
            chineseSimplified: "macOS 限制了\(permission)权限。"
        )
    }
}
