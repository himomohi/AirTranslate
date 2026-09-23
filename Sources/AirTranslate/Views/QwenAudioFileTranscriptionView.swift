import AppKit
import SwiftUI

struct QwenAudioFileTranscriptionView: View {
    let hasAPIKey: Bool
    private let service: QwenAudioFileTranscriptionService
    @State private var fileURL = ""
    @State private var transcript = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var task: Task<Void, Never>?

    init(hasAPIKey: Bool, service: QwenAudioFileTranscriptionService = QwenAudioFileTranscriptionService()) {
        self.hasAPIKey = hasAPIKey
        self.service = service
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xs) {
            Text(QwenCopy.fileTranscriptionTitle)
                .font(AirTranslateDesign.Typography.sectionLabel)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)

            VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.sm) {
            Text(QwenCopy.fileTranscriptionDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(QwenCopy.fileTranscriptionURLPlaceholder, text: $fileURL)
                .textFieldStyle(.roundedBorder)
                .disabled(isWorking)
                .accessibilityLabel(QwenCopy.fileTranscriptionURLLabel)
                .accessibilityIdentifier("qwenFileTranscriptionURL")

            Text(QwenCopy.fileTranscriptionPrivacy)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(QwenCopy.fileTranscriptionWorking)
                    Text(QwenCopy.fileTranscriptionWorking)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(QwenCopy.fileTranscriptionCancel, action: cancel)
                        .accessibilityIdentifier("qwenFileTranscriptionCancel")
                } else {
                    Button(QwenCopy.fileTranscriptionStart, action: start)
                        .disabled(!hasAPIKey)
                        .accessibilityIdentifier("qwenFileTranscriptionStart")
                    Spacer()
                    if !hasAPIKey {
                        Label(QwenCopy.apiKeyRequired, systemImage: "key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AirTranslateDesign.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("qwenFileTranscriptionError")
            }

            if !transcript.isEmpty {
                ScrollView {
                    Text(transcript)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 190)
                .background(AirTranslateDesign.Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("qwenFileTranscriptionResult")

                HStack {
                    Spacer()
                    Button(QwenCopy.fileTranscriptionCopy, action: copyTranscript)
                        .accessibilityIdentifier("qwenFileTranscriptionCopy")
                }
            }
            }
            .padding(.horizontal, AirTranslateDesign.Spacing.md)
            .padding(.vertical, AirTranslateDesign.Spacing.xxs)
            .airRaisedSurface()
        }
    }

    private func start() {
        guard !isWorking, hasAPIKey else { return }
        transcript = ""
        errorMessage = nil
        isWorking = true
        task = Task {
            do {
                transcript = try await service.transcribe(fileURL: fileURL)
            } catch is CancellationError {
                // Cancellation is initiated by the user.
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
            task = nil
        }
    }

    private func cancel() {
        task?.cancel()
    }

    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }
}
