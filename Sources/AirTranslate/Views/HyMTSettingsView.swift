import SwiftUI

struct HyMTSettingsView: View {
    @Bindable var session: TranslationSessionStore
    @State private var confirmsRemoval = false
    @State private var sample = "Hello. Thank you for joining today's meeting."
    @State private var result = ""
    @State private var task: Task<Void, Never>?
    @State private var translator = HyMTTranslationService()
    private var locked: Bool { session.isRunning || session.isStarting }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(HyMTCopy.detail).font(.callout).foregroundStyle(.secondary)
            Text(HyMTCopy.terminology).font(.callout.weight(.semibold))
            Text(HyMTCopy.terminologyDetail).font(.caption).foregroundStyle(.secondary)
            TerminologyChipEditor(
                text: $session.hyMTTerminologyText,
                isDisabled: locked || task != nil,
                accessibilityLabel: HyMTCopy.terminology,
                accessibilityHint: HyMTCopy.terminologyDetail,
                accessibilityIdentifier: "hyMTTerminologyEditor",
                editorHeight: 72
            )
            HStack {
                Text(HyMTCopy.model).font(.callout.weight(.semibold))
                Spacer()
                if session.isHyMTModelChecking {
                    ProgressView().controlSize(.small)
                    Text(HyMTCopy.checking)
                } else if session.isHyMTModelInstalled {
                    Label(HyMTCopy.ready, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            if session.isHyMTModelDownloading {
                ProgressView(value: session.hyMTDownloadProgress)
                    .accessibilityLabel(HyMTCopy.download)
                HStack {
                    Text(session.hyMTDownloadProgress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                    Spacer()
                    Button(HyMTCopy.cancel) { session.cancelHyMTModelDownload() }
                        .accessibilityIdentifier("hyMTCancelDownload")
                }
            } else {
                HStack {
                    if session.isHyMTModelInstalled {
                        Button(HyMTCopy.remove, role: .destructive) { confirmsRemoval = true }
                            .accessibilityIdentifier("hyMTRemoveModel")
                    } else {
                        Button(HyMTCopy.download) { session.downloadHyMTModel() }
                            .accessibilityIdentifier("hyMTDownloadModel")
                    }
                }
                .disabled(locked || session.isHyMTModelChecking || task != nil)
            }
            if let message = session.hyMTModelMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if session.isHyMTModelInstalled {
                Divider()
                Text(session.languageSummary).font(.caption).foregroundStyle(.secondary)
                TextField(HyMTCopy.previewInput, text: $sample, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .disabled(locked || task != nil)
                    .accessibilityIdentifier("hyMTPreviewInput")
                HStack {
                    Button(HyMTCopy.preview) { translateSample() }
                        .disabled(locked || task != nil || sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("hyMTPreviewTranslate")
                    if task != nil {
                        ProgressView().controlSize(.small)
                        Button(AppText.localized(english: "Cancel", korean: "취소", japanese: "中止", chineseSimplified: "取消")) {
                            task?.cancel()
                        }
                    }
                }
                if !result.isEmpty {
                    Text(result).textSelection(.enabled)
                        .accessibilityLabel("\(HyMTCopy.previewResult): \(result)")
                        .accessibilityIdentifier("hyMTPreviewResult")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(HyMTCopy.removeDetail, isPresented: $confirmsRemoval) {
            Button(HyMTCopy.remove, role: .destructive) { session.removeHyMTModel() }
        }
        .onAppear { session.refreshHyMTModel() }
        .onDisappear {
            task?.cancel()
            Task { await translator.unload() }
        }
        .onChange(of: locked) { _, isLocked in if isLocked { task?.cancel() } }
    }

    private func translateSample() {
        let text = sample
        let source = session.sourceLanguage
        let target = session.targetLanguage
        let options = HyMTTranslationOptions(terminology: HyMTTranslationOptions.parseTerminology(session.hyMTTerminologyText))
        result = ""
        task = Task { @MainActor in
            defer { task = nil }
            do {
                let translated = try await translator.translate(text, source: source, target: target, options: options) { partial in
                    guard !Task.isCancelled else { return }
                    result = partial
                }
                try Task.checkCancellation()
                result = translated
            } catch {
                if !Task.isCancelled { result = error.localizedDescription }
            }
            await translator.unload()
        }
    }
}
