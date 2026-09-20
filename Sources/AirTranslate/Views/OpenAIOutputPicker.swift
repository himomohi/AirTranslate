import SwiftUI

// 메인 콘솔과 설정이 같은 출력 선택·잠금·가격 정보를 사용한다.
struct OpenAIOutputPicker: View {
    @Bindable var session: TranslationSessionStore

    private var isLocked: Bool { session.isRunning || session.isStarting }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(LiveOutputMode.allCases) { mode in
                let isSelected = session.openAIOutputMode == mode
                let info = ProcessingModeInfo.information(for: .openAI, openAIOutputMode: mode)
                Button {
                    session.useOpenAIMode(mode)
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.textSecondary)
                        .frame(width: 38, height: 30)
                        .background(isSelected ? AirTranslateDesign.Palette.accentSoft : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isLocked)
                .airFocusRing(cornerRadius: 7)
                .help(isLocked ? AppText.lockedDuringSession : info.tooltip)
                .accessibilityLabel(mode.title)
                .accessibilityValue(isSelected ? AppText.openAIAudio : "")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("openAIOutput.\(mode.rawValue)")
            }
        }
        .padding(3)
        .background(AirTranslateDesign.Palette.raised, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(AppText.openAIAudio) · \(AppText.outputMode)")
    }
}
