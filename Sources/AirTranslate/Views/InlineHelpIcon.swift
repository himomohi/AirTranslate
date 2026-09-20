import SwiftUI

// 반복되는 보조 설명은 아이콘으로 표시하고 도움말·접근성 이름에 의미를 보존한다.
struct InlineHelpIcon: View {
    let symbol: String
    let help: String
    var tint: Color = AirTranslateDesign.Palette.textSecondary

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 24, height: 30)
            .contentShape(Rectangle())
            .help(help)
            .accessibilityLabel(help)
            .accessibilityRemoveTraits(.isSelected)
    }
}
