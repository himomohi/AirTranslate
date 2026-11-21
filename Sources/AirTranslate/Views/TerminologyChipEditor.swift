import SwiftUI

struct TerminologyChipEditor: View {
    @Binding var text: String
    let isDisabled: Bool
    let accessibilityLabel: String
    let accessibilityHint: String?
    let accessibilityIdentifier: String
    var editorHeight: CGFloat = 96

    @State private var newTermDraft = ""
    @State private var showsRawEditor = false

    private var terms: [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xs) {
            HStack(spacing: AirTranslateDesign.Spacing.xs) {
                TextField(
                    AppText.localized(
                        english: "Add term and press Return...",
                        korean: "용어 입력 후 Return...",
                        japanese: "用語を入力して Return...",
                        chineseSimplified: "输入术语并按 Return..."
                    ),
                    text: $newTermDraft
                )
                .textFieldStyle(.roundedBorder)
                .disabled(isDisabled)
                .onSubmit(addTerm)

                Button {
                    addTerm()
                } label: {
                    Label(
                        AppText.localized(english: "Add", korean: "추가", japanese: "追加", chineseSimplified: "添加"),
                        systemImage: "plus"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isDisabled || newTermDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    showsRawEditor.toggle()
                } label: {
                    Text(
                        showsRawEditor
                            ? AppText.localized(english: "Chips", korean: "칩 보기", japanese: "チップ", chineseSimplified: "标签视图")
                            : AppText.localized(english: "Edit list", korean: "직접 편집", japanese: "直接編集", chineseSimplified: "直接编辑")
                    )
                    .font(AirTranslateDesign.Typography.meta)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AirTranslateDesign.Palette.accent)
            }

            if showsRawEditor {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(height: editorHeight)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(AirTranslateDesign.Palette.canvas, in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous)
                            .strokeBorder(AirTranslateDesign.Palette.hairline)
                    }
                    .disabled(isDisabled)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityHint(accessibilityHint ?? "")
                    .accessibilityIdentifier(accessibilityIdentifier)
            } else {
                VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xs) {
                    if terms.isEmpty {
                        Text(
                            AppText.localized(
                                english: "No protected terms yet. Add product names or technical terms above.",
                                korean: "등록된 용어가 없습니다. 위 입력창에서 제품명이나 전문 용어를 추가하세요.",
                                japanese: "登録された用語はありません。上の入力欄から追加してください。",
                                chineseSimplified: "暂无保留术语，请在上方添加产品名或专业词汇。"
                            )
                        )
                        .font(AirTranslateDesign.Typography.meta)
                        .foregroundStyle(AirTranslateDesign.Palette.textTertiary)
                        .padding(.vertical, 6)
                    } else {
                        ChipFlowLayout(spacing: 6) {
                            ForEach(Array(terms.enumerated()), id: \.offset) { index, term in
                                HStack(spacing: 5) {
                                    Text(term)
                                        .font(AirTranslateDesign.Typography.meta.weight(.medium))
                                        .foregroundStyle(AirTranslateDesign.Palette.accentBright)
                                        .lineLimit(1)

                                    if !isDisabled {
                                        Button {
                                            removeTerm(at: index)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(AppText.delete) \(term)")
                                    }
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(AirTranslateDesign.Palette.accentSoft, in: Capsule())
                                .overlay {
                                    Capsule().strokeBorder(AirTranslateDesign.Palette.accent.opacity(0.35))
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                .background(AirTranslateDesign.Palette.canvas, in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous)
                        .strokeBorder(AirTranslateDesign.Palette.hairline)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(accessibilityHint ?? "")
                .accessibilityIdentifier(accessibilityIdentifier)
            }
        }
    }

    private func addTerm() {
        guard !isDisabled else { return }
        let trimmed = newTermDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = terms
        if !updated.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            updated.append(trimmed)
            text = updated.joined(separator: "\n")
        }
        newTermDraft = ""
    }

    private func removeTerm(at index: Int) {
        guard !isDisabled else { return }
        var updated = terms
        guard updated.indices.contains(index) else { return }
        updated.remove(at: index)
        text = updated.joined(separator: "\n")
    }
}

private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 480
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
