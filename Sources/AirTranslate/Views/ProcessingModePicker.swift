import SwiftUI

struct ProcessingModePicker: View {
    @Bindable var session: TranslationSessionStore
    @Environment(\.openSettings) private var openSettings
    @State private var isPresented = false

    private var currentEngine: ProcessingEngine { .current(for: session) }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                AirChip(text: currentEngine.title, systemImage: "cpu",
                        tint: AirTranslateDesign.Palette.textSecondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .airFocusRing(cornerRadius: 12)
        .help(ModePickerCopy.chooseMode)
        .accessibilityLabel(ModePickerCopy.chooseMode)
        .accessibilityValue(currentEngine.title)
        .accessibilityIdentifier("processingModePicker")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(ModePickerCopy.chooseMode)
                        .font(.headline)
                    Spacer()
                    if session.isRunning || session.isStarting {
                        InlineHelpIcon(symbol: "lock.fill", help: AppText.lockedDuringSession)
                            .accessibilityIdentifier("processingModeLockInfo")
                    }
                    InlineHelpIcon(symbol: "dollarsign.circle", help: ProcessingModeInfo.pricingNote)
                        .accessibilityIdentifier("processingModePricingInfo")
                }
                .padding(.leading, 10)
                .padding(.trailing, 5)
                ForEach(ProcessingEngine.allCases) { engine in
                    ProcessingModeRow(
                        engine: engine,
                        information: engine.information(in: session),
                        isSelected: engine == currentEngine,
                        hasKey: engine.hasRequiredKey(in: session),
                        canSelect: engine.canSelect(in: session),
                        select: {
                            guard engine.select(in: session) else { return }
                            isPresented = false
                        },
                        settings: {
                            engine.requestSettings(in: session)
                            isPresented = false
                            openSettings()
                        }
                    )
                }
            }
            .padding(10)
            .frame(width: 330)
            .background(AirTranslateDesign.Palette.raised)
        }
    }
}

private struct ProcessingModeRow: View {
    let engine: ProcessingEngine
    let information: ProcessingModeInfo
    let isSelected: Bool
    let hasKey: Bool
    let canSelect: Bool
    let select: () -> Void
    let settings: () -> Void
    @State private var isHovered = false

    private var status: String {
        if !hasKey { return ModePickerCopy.keyRequired }
        return engine == .apple ? ModePickerCopy.noKeyRequired : ModePickerCopy.keySaved
    }

    var body: some View {
        HStack(spacing: 4) {
            // 키 없는 선택 버튼 바깥에 도움말을 두고 설정 아이콘과 영역을 분리한다.
            HStack(spacing: 0) {
                Button(action: select) {
                    HStack(spacing: 10) {
                        Image(systemName: isSelected ? "checkmark" : (engine.credentialProvider?.symbol ?? "cpu"))
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 20)
                        Text(engine.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(canSelect ? AirTranslateDesign.Palette.textPrimary : AirTranslateDesign.Palette.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ModeSelectionButtonStyle())
                .disabled(!canSelect)
                .airFocusRing(cornerRadius: 8)
                .accessibilityLabel(engine.title)
                .accessibilityHint(information.tooltip)
                .accessibilityValue(isSelected ? "\(ModePickerCopy.selected), \(status)" : status)
                .accessibilityIdentifier("processingMode.\(engine.rawValue)")
            }
            .help(information.tooltip)

            InlineHelpIcon(
                symbol: engine == .apple ? "desktopcomputer" : (hasKey ? "checkmark.circle.fill" : "key"),
                help: "\(engine.title) · \(status)",
                tint: hasKey ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.textSecondary
            )
            .accessibilityIdentifier("processingModeKeyStatus.\(engine.rawValue)")

            InlineHelpIcon(symbol: "info.circle", help: information.tooltip)
                .accessibilityIdentifier("processingModeInfo.\(engine.rawValue)")

            Button(action: settings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .airFocusRing(cornerRadius: 8)
            .help("\(engine.title) · \(AppText.translationSettings)")
            .accessibilityLabel("\(engine.title) · \(AppText.translationSettings)")
            .accessibilityIdentifier("processingModeSettings.\(engine.rawValue)")
            .padding(.trailing, 5)
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? AirTranslateDesign.Palette.accent.opacity(0.12)
                      : (isHovered ? AirTranslateDesign.Palette.textSecondary.opacity(0.08) : Color.clear))
        }
        .onHover { isHovered = $0 }
    }
}

// 비활성 상태는 회색으로 구분하되 기본 plain 스타일의 추가 감광은 피한다.
private struct ModeSelectionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private enum ModePickerCopy {
    static let chooseMode = AppText.localized(english: "Choose Mode", korean: "모드 선택", japanese: "モードを選択", chineseSimplified: "选择模式")
    static let keyRequired = AppText.localized(english: "API key required", korean: "API 키 필요", japanese: "APIキーが必要", chineseSimplified: "需要 API 密钥")
    static let keySaved = AppText.localized(english: "API key saved", korean: "API 키 저장됨", japanese: "APIキー保存済み", chineseSimplified: "API 密钥已保存")
    static let noKeyRequired = AppText.localized(english: "No API key needed", korean: "API 키 없이 사용", japanese: "APIキー不要", chineseSimplified: "无需 API 密钥")
    static let selected = AppText.localized(english: "Selected", korean: "선택됨", japanese: "選択中", chineseSimplified: "已选择")
}
