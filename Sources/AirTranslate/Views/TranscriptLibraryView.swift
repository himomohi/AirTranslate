import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum DraftEditorField: Hashable {
    case source
    case translation
}

private enum TranscriptLibraryFilter: String, CaseIterable, Identifiable {
    case all, bilingual, sourceOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: AppText.localized(english: "All", korean: "전체", japanese: "すべて", chineseSimplified: "全部")
        case .bilingual: AppText.originalAndTranslation
        case .sourceOnly: AppText.original
        }
    }
}

struct TranscriptLibraryView: View {
    @Bindable var session: TranslationSessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedDraftEditor: DraftEditorField?
    @State private var draftEditorTextViews: [DraftEditorField: NSTextView] = [:]
    @State private var isDeleteSelectedConfirmationPresented = false
    @State private var isDeleteAllConfirmationPresented = false
    @State private var isCopyFeedbackVisible = false
    @State private var copyFeedbackToken = 0
    @State private var searchQuery = ""
    @State private var filter: TranscriptLibraryFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, AirTranslateDesign.Spacing.lg)
                .padding(.vertical, AirTranslateDesign.Spacing.md)

            Rectangle()
                .fill(AirTranslateDesign.Palette.hairline)
                .frame(height: 1)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: AirTranslateDesign.libraryMinimumWidth,
            idealWidth: AirTranslateDesign.libraryIdealWidth,
            minHeight: AirTranslateDesign.libraryMinimumHeight,
            idealHeight: AirTranslateDesign.libraryIdealHeight
        )
        .tint(AirTranslateDesign.Palette.accent)
        .background(AirTranslateDesign.Palette.canvas)
        .confirmationDialog(
            AppText.deleteSavedTranscriptConfirmation,
            isPresented: $isDeleteSelectedConfirmationPresented
        ) {
            Button(AppText.deleteSavedTranscript, role: .destructive) {
                session.deleteSelectedTranscript()
            }
            Button(AppText.cancel, role: .cancel) {}
        }
        .confirmationDialog(
            AppText.deleteAllSavedTranscriptsConfirmation,
            isPresented: $isDeleteAllConfirmationPresented
        ) {
            Button(AppText.deleteAllSavedTranscripts, role: .destructive) {
                session.deleteAllSavedTranscripts()
            }
            Button(AppText.cancel, role: .cancel) {}
        }
        .onAppear {
            ensureSelection()
        }
        .onChange(of: session.savedTranscripts.count) { _, _ in
            ensureSelection()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.sm) {
            HStack(spacing: AirTranslateDesign.Spacing.sm) {
                Image(systemName: "tray.full")
                    .font(.system(size: AirTranslateDesign.iconRegular, weight: .semibold))
                    .foregroundStyle(AirTranslateDesign.Palette.accent)
                    .frame(width: 40, height: 40)
                    .background(
                        AirTranslateDesign.Palette.accentSoft,
                        in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xxs) {
                    Text(AppText.savedTranscripts)
                        .font(AirTranslateDesign.Typography.stageTitle)
                        .foregroundStyle(AirTranslateDesign.Palette.textPrimary)

                    Text(AppText.transcriptPersistenceDescription)
                        .font(AirTranslateDesign.Typography.meta)
                        .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Button(AppText.close) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: AirTranslateDesign.Spacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AirTranslateDesign.Palette.textTertiary)
                        .font(.system(size: 12, weight: .medium))
                    TextField(
                        AppText.localized(english: "Search transcripts...", korean: "기록 검색...", japanese: "記録を検索...", chineseSimplified: "搜索记录..."),
                        text: $searchQuery
                    )
                    .textFieldStyle(.plain)
                    .font(AirTranslateDesign.Typography.label)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AirTranslateDesign.Palette.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: 300)
                .background(AirTranslateDesign.Palette.raised, in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous).strokeBorder(AirTranslateDesign.Palette.hairline) }

                Picker("", selection: $filter) {
                    ForEach(TranscriptLibraryFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer(minLength: 8)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AirTranslateDesign.Spacing.sm) {
                    contentModeControl
                    Spacer(minLength: 12)
                    libraryActions
                }

                VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.sm) {
                    contentModeControl
                    libraryActions
                }
            }
        }
    }

    private var contentModeControl: some View {
        HStack(spacing: 8) {
            Text(AppText.savedTranscriptContent)
                .font(AirTranslateDesign.Typography.sectionLabel)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                .fixedSize()

            if session.isTranscribeOnlyMode {
                Text(session.effectiveSavedTranscriptContentMode.title)
                    .font(AirTranslateDesign.Typography.label)
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
            } else {
                Picker(AppText.savedTranscriptContent, selection: $session.savedTranscriptContentMode) {
                    ForEach(session.availableSavedTranscriptContentModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .tint(AirTranslateDesign.Palette.accent)
                .fixedSize()
            }
        }
    }

    private var libraryActions: some View {
        HStack(spacing: 8) {
            Menu {
                Button(AppText.localized(english: "Export as Markdown (.md)", korean: "Markdown (.md)로 내보내기", japanese: "Markdown (.md) で書き出す", chineseSimplified: "导出为 Markdown (.md)")) {
                    exportSelectedTranscript(asMarkdown: true)
                }
                Button(AppText.localized(english: "Export as Plain Text (.txt)", korean: "텍스트 (.txt)로 내보내기", japanese: "テキスト (.txt) で書き出す", chineseSimplified: "导出为纯文本 (.txt)")) {
                    exportSelectedTranscript(asMarkdown: false)
                }
            } label: {
                Label(
                    AppText.localized(english: "Export", korean: "내보내기", japanese: "書き出し", chineseSimplified: "导出"),
                    systemImage: "square.and.arrow.up"
                )
            }
            .fixedSize()
            .disabled(session.selectedSavedTranscript == nil || !canCopyDraft)

            Button {
                session.openTranscriptsFolder()
            } label: {
                Label(AppText.openSaveFolder, systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .tint(AirTranslateDesign.Palette.accent)
            .fixedSize()

            Button(role: .destructive) {
                isDeleteAllConfirmationPresented = true
            } label: {
                Label(AppText.deleteAllSavedTranscripts, systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(AirTranslateDesign.Palette.danger)
            .fixedSize()
            .disabled(session.savedTranscripts.isEmpty)
            .help(AppText.deleteAllSavedTranscriptsHelp)
        }
    }

    private var filteredTranscripts: [SavedTranscript] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return session.savedTranscripts.filter { item in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .bilingual: item.isOriginalAndTranslation
            case .sourceOnly: !item.isOriginalAndTranslation
            }
            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            return item.title.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private var content: some View {
        if session.savedTranscripts.isEmpty {
            VStack(spacing: AirTranslateDesign.Spacing.md) {
                AudioLevelWaveform(
                    level: nil,
                    date: .distantPast,
                    barCount: 11,
                    width: 92,
                    height: 30,
                    barWidth: 4,
                    barSpacing: 4,
                    tint: AirTranslateDesign.Palette.accent
                )

                Text(AppText.savedEmpty)
                    .font(AirTranslateDesign.Typography.stageTitle)
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)

                Text(AppText.transcriptPersistenceDescription)
                    .font(AirTranslateDesign.Typography.meta)
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            .padding(AirTranslateDesign.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                transcriptList
                    .frame(width: 260)

                Rectangle()
                    .fill(AirTranslateDesign.Palette.hairline)
                    .frame(width: 1)

                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var transcriptList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xxs) {
                ForEach(filteredTranscripts) { transcript in
                    Button {
                        session.selectSavedTranscript(transcript.id)
                    } label: {
                        TranscriptLibraryRow(
                            transcript: transcript,
                            isSelected: session.selectedSavedTranscriptID == transcript.id
                        )
                        .contentShape(RoundedRectangle(cornerRadius: AirTranslateDesign.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AirTranslateDesign.Spacing.xs)
        }
        .background(AirTranslateDesign.Palette.canvas)
    }

    @ViewBuilder
    private var editor: some View {
        if let selectedTranscript = session.selectedSavedTranscript {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(AppText.editSaved)
                        .font(AirTranslateDesign.Typography.stageTitle)
                        .foregroundStyle(AirTranslateDesign.Palette.textPrimary)

                    Spacer(minLength: 0)

                    Button {
                        session.polishSelectedTranscriptDraftWithFoundationModel()
                    } label: {
                        if session.isFoundationTranscriptCleanupRunning {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 28, height: 28)
                        } else {
                            Label(AppText.foundationModelCleanupShort, systemImage: "wand.and.stars")
                                .font(AirTranslateDesign.Typography.meta.weight(.semibold))
                        }
                    }
                    .disabled(!canCopyDraft || session.isFoundationTranscriptCleanupRunning)
                    .help(AppText.foundationModelCleanupHelp)
                    .accessibilityLabel(AppText.foundationModelCleanup)

                    Button {
                        if copyDraftText() {
                            showCopyFeedback()
                        }
                    } label: {
                        Image(systemName: isCopyFeedbackVisible ? "checkmark" : "clipboard")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isCopyFeedbackVisible ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.textSecondary)
                            .frame(width: 26, height: 26)
                            .airTranslateInteractiveSurface(isSelected: isCopyFeedbackVisible)
                    }
                    .buttonStyle(AirTranslatePressButtonStyle())
                    .help(isCopyFeedbackVisible ? AppText.copied : AppText.copy)
                    .accessibilityLabel(AppText.copy)
                    .disabled(!canCopyDraft)
                }

                draftEditor(for: selectedTranscript)

                HStack {
                    Button {
                        session.saveSelectedTranscriptEdits()
                    } label: {
                        Label(AppText.saveEdits, systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AirTranslateDesign.Palette.accent)
                    .keyboardShortcut("s", modifiers: [.command])

                    Spacer(minLength: 0)

                    Button(role: .destructive) {
                        isDeleteSelectedConfirmationPresented = true
                    } label: {
                        Label(AppText.deleteSavedTranscript, systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(AirTranslateDesign.Palette.danger)
                }
            }
            .padding(AirTranslateDesign.Spacing.md)
            .airRaisedSurface()
            .padding(AirTranslateDesign.Spacing.md)
        } else {
            ContentUnavailableView(AppText.noSavedTranscriptSelected, systemImage: "doc.text")
        }
    }

    @ViewBuilder
    private func draftEditor(for transcript: SavedTranscript) -> some View {
        if transcript.isOriginalAndTranslation {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    sourceEditorPane
                    translationEditorPane
                }
                .frame(minWidth: AirTranslateDesign.libraryEditorBreakpoint)

                VStack(alignment: .leading, spacing: 12) {
                    sourceEditorPane
                    translationEditorPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            draftEditorPane(
                title: AppText.original,
                text: $session.savedDraftSourceText,
                field: .source
            )
        }
    }

    private var sourceEditorPane: some View {
        draftEditorPane(
            title: AppText.original,
            text: $session.savedDraftSourceText,
            field: .source
        )
    }

    private var translationEditorPane: some View {
        draftEditorPane(
            title: AppText.translation,
            text: $session.savedDraftTranslationText,
            field: .translation
        )
    }

    private func draftEditorPane(
        title: String,
        text: Binding<String>,
        field: DraftEditorField
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(AirTranslateDesign.Typography.sectionLabel)
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)

                Spacer(minLength: 0)

                writingToolsButton(for: field)
                    .disabled(!hasDraftText(for: field))
            }

            WritingToolsTextEditor(
                text: text,
                field: field,
                focusedField: $focusedDraftEditor
            ) { field, textView in
                draftEditorTextViews[field] = textView
            }
            .background(AirTranslateDesign.Palette.canvas, in: RoundedRectangle(cornerRadius: AirTranslateDesign.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AirTranslateDesign.controlRadius, style: .continuous)
                    .strokeBorder(AirTranslateDesign.Palette.hairline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func writingToolsButton(for field: DraftEditorField) -> some View {
        Button {
            showWritingTools(for: field)
        } label: {
            Image(systemName: "pencil.and.outline")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                .frame(width: 26, height: 26)
                .airTranslateInteractiveSurface()
        }
        .buttonStyle(AirTranslatePressButtonStyle())
        .help(AppText.appleIntelligenceWritingTools)
        .accessibilityLabel(AppText.appleIntelligenceWritingTools)
    }

    private func exportSelectedTranscript(asMarkdown: Bool) {
        guard let selected = session.selectedSavedTranscript else { return }
        let sourceText = session.savedDraftSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translatedText = session.savedDraftTranslationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let content: String
        if asMarkdown {
            var lines = ["# \(selected.title)", ""]
            if !sourceText.isEmpty {
                lines.append("## \(AppText.original)")
                lines.append(sourceText)
                lines.append("")
            }
            if selected.isOriginalAndTranslation && !translatedText.isEmpty {
                lines.append("## \(AppText.translation)")
                lines.append(translatedText)
                lines.append("")
            }
            content = lines.joined(separator: "\n")
        } else {
            if selected.isOriginalAndTranslation && !translatedText.isEmpty {
                content = "\(AppText.original)\n\(sourceText)\n\n\(AppText.translation)\n\(translatedText)\n"
            } else {
                content = sourceText + "\n"
            }
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [asMarkdown ? (UTType(filenameExtension: "md") ?? .plainText) : .plainText]
        let baseName = selected.title.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(baseName).\(asMarkdown ? "md" : "txt")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private var canCopyDraft: Bool {
        hasDraftText(for: .source) || hasDraftText(for: .translation)
    }

    private func hasDraftText(for field: DraftEditorField) -> Bool {
        let text = switch field {
        case .source:
            session.savedDraftSourceText
        case .translation:
            session.savedDraftTranslationText
        }
        return text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
    }

    private func copyDraftText() -> Bool {
        let sourceText = session.savedDraftSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translatedText = session.savedDraftTranslationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let copiedText: String

        if session.selectedSavedTranscript?.isOriginalAndTranslation == true, !translatedText.isEmpty {
            copiedText = "\(AppText.original)\n\(sourceText)\n\n\(AppText.translation)\n\(translatedText)"
        } else {
            copiedText = sourceText
        }

        guard !copiedText.isEmpty else { return false }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copiedText, forType: .string)
        return true
    }

    private func showWritingTools(for field: DraftEditorField) {
        focusedDraftEditor = field
        DispatchQueue.main.async {
            guard let textView = draftEditorTextViews[field] else { return }
            textView.window?.makeFirstResponder(textView)
            NSApp.sendAction(#selector(NSResponder.showWritingTools(_:)), to: textView, from: nil)
        }
    }

    private func showCopyFeedback() {
        copyFeedbackToken += 1
        let token = copyFeedbackToken

        withAnimation(reduceMotion ? nil : AirTranslateDesign.Motion.quick) {
            isCopyFeedbackVisible = true
        }

        Task {
            try? await Task.sleep(for: .milliseconds(900))
            await MainActor.run {
                guard token == copyFeedbackToken else { return }

                withAnimation(reduceMotion ? nil : AirTranslateDesign.Motion.quick) {
                    isCopyFeedbackVisible = false
                }
            }
        }
    }

    private func ensureSelection() {
        if let selectedSavedTranscriptID = session.selectedSavedTranscriptID,
           session.savedTranscripts.contains(where: { $0.id == selectedSavedTranscriptID }) {
            return
        }

        if let firstTranscript = session.savedTranscripts.first {
            session.selectSavedTranscript(firstTranscript.id)
        }
    }
}

private struct WritingToolsTextEditor: NSViewRepresentable {
    @Binding var text: String
    let field: DraftEditorField
    @Binding var focusedField: DraftEditorField?
    let onTextViewResolved: (DraftEditorField, NSTextView?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.writingToolsBehavior = .complete
        textView.allowedWritingToolsResultOptions = .plainText

        scrollView.documentView = textView
        context.coordinator.textView = textView
        DispatchQueue.main.async {
            onTextViewResolved(field, textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            textView.string = text
        }

        if focusedField == field, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        DispatchQueue.main.async {
            onTextViewResolved(field, textView)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            coordinator.parent.onTextViewResolved(coordinator.parent.field, nil)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WritingToolsTextEditor
        weak var textView: NSTextView?

        init(_ parent: WritingToolsTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

private struct TranscriptLibraryRow: View {
    let transcript: SavedTranscript
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: transcript.isOriginalAndTranslation ? "doc.on.doc.fill" : (isSelected ? "doc.text.fill" : "doc.text"))
                .foregroundStyle(isSelected ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.textSecondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(transcript.title)
                    .font(AirTranslateDesign.Typography.libraryRowTitle)
                    .lineLimit(2)
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)

                HStack(spacing: 5) {
                    if transcript.isOriginalAndTranslation {
                        Text(AppText.originalAndTranslation)
                    }

                    Text(transcript.updatedAt, style: .date)
                }
                .font(AirTranslateDesign.Typography.meta)
                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AirTranslateDesign.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(
            isSelected ? AirTranslateDesign.Palette.accentSoft : AirTranslateDesign.Palette.transparent,
            in: RoundedRectangle(cornerRadius: AirTranslateDesign.controlRadius, style: .continuous)
        )
    }
}
