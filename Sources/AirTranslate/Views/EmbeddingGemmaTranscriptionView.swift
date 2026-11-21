import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EmbeddingGemmaTranscriptionView: View {
    let isCaptureActive: Bool
    @State private var modelStore = EmbeddingGemmaModelStore()
    @State private var modelDirectory: URL?
    @State private var audioURL: URL?
    @State private var result: EmbeddingGemmaTranscriptionResult?
    @State private var errorMessage: String?
    @State private var status = ""
    @State private var progress = 0.0
    @State private var isWorking = false
    @State private var isCancelling = false
    @State private var operationID = UUID()
    @State private var operationTask: Task<Void, Never>?
    @State private var modelCheckLifecycle = EmbeddingGemmaModelCheckLifecycle()

    private var isSupported: Bool {
        #if canImport(CoreAI) && arch(arm64)
        if #available(macOS 27.0, *) { return true }
        #endif
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xs) {
            Text(EmbeddingGemmaCopy.title)
                .font(AirTranslateDesign.Typography.sectionLabel)
                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
            VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.sm) {
                Text(EmbeddingGemmaCopy.detail)
                Text(EmbeddingGemmaCopy.requirements)
                    .foregroundStyle(.secondary)
                if !isSupported {
                    Label(EmbeddingGemmaCopy.unsupported, systemImage: "info.circle")
                }
                if isCaptureActive {
                    Label(EmbeddingGemmaCopy.captureActive, systemImage: "pause.circle")
                }
                ViewThatFits(in: .horizontal) {
                    HStack { controls }
                    VStack(alignment: .leading) { controls }
                }
                .disabled(!isSupported || isWorking || isCaptureActive)
                if let audioURL {
                    Text(audioURL.lastPathComponent)
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("gemmaAudioFile")
                }
                if isWorking {
                    ProgressView(value: progress, total: 1)
                        .accessibilityLabel(status)
                    Button(EmbeddingGemmaCopy.cancel, action: cancel)
                        .disabled(isCancelling)
                        .accessibilityIdentifier("gemmaCancel")
                }
                if !status.isEmpty {
                    Text(status)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("gemmaStatus")
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AirTranslateDesign.Palette.warning)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("gemmaError")
                }
                if let result {
                    Text(EmbeddingGemmaCopy.measurements(duration: result.duration, elapsed: result.processingSeconds))
                        .foregroundStyle(.secondary)
                    if result.text.isEmpty {
                        Text(EmbeddingGemmaCopy.empty)
                    } else {
                        ScrollView {
                            Text(result.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(minHeight: 70, maxHeight: 190)
                        .background(AirTranslateDesign.Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("gemmaResult")
                        HStack {
                            Button(EmbeddingGemmaCopy.copyResult) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(result.text, forType: .string)
                            }
                            .accessibilityIdentifier("gemmaCopy")
                            Button(EmbeddingGemmaCopy.save) { save(result.text) }
                                .accessibilityIdentifier("gemmaSave")
                        }
                    }
                }
                Link(EmbeddingGemmaCopy.source, destination: URL(string: "https://huggingface.co/mlboydaisuke/EmbeddingGemma-2-Transcribe-CoreAI")!)
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .padding(AirTranslateDesign.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .airRaisedSurface()
        }
        .onAppear {
            modelCheckLifecycle.appear(isCaptureActive: isCaptureActive)
            checkModels()
        }
        .onDisappear {
            modelCheckLifecycle.disappear()
            cancel()
        }
        .onChange(of: isCaptureActive) { _, active in
            modelCheckLifecycle.captureChanged(isActive: active)
            if active {
                cancel()
            } else {
                checkModels()
            }
        }
    }

    @ViewBuilder private var controls: some View {
        if modelDirectory == nil {
            Button(EmbeddingGemmaCopy.download, action: download)
                .accessibilityIdentifier("gemmaDownload")
        }
        Button(EmbeddingGemmaCopy.choose, action: chooseAudio)
            .accessibilityIdentifier("gemmaChooseAudio")
        Button(EmbeddingGemmaCopy.start, action: transcribe)
            .disabled(modelDirectory == nil || audioURL == nil)
            .accessibilityIdentifier("gemmaTranscribe")
    }

    private func checkModels() {
        guard isSupported,
              modelCheckLifecycle.beginIfPossible(isWorking: isWorking) else { return }
        begin(status: EmbeddingGemmaCopy.checking) { token in
            defer { modelCheckLifecycle.finish() }
            let directory = try await modelStore.installedDirectory()
            guard !Task.isCancelled, operationID == token else { return }
            modelDirectory = directory
        }
    }

    private func begin(status nextStatus: String, work: @escaping @MainActor (UUID) async throws -> Void) {
        guard isSupported, !isWorking, !modelCheckLifecycle.isCaptureActive else { return }
        let token = UUID()
        operationID = token
        isWorking = true
        isCancelling = false
        progress = 0
        status = nextStatus
        errorMessage = nil
        operationTask = Task {
            do {
                try await work(token)
            } catch is CancellationError {
                // 사용자 취소 뒤 늦게 도착한 결과는 표시하지 않는다.
            } catch {
                if operationID == token, !Task.isCancelled { errorMessage = error.localizedDescription }
            }
            guard operationID == token else { return }
            isWorking = false
            isCancelling = false
            operationTask = nil
            status = modelDirectory == nil ? "" : EmbeddingGemmaCopy.ready
            // 캡처가 취소 완료보다 먼저 끝나도 예약된 설치 확인을 놓치지 않는다.
            checkModels()
        }
    }

    private func updateProgress(_ fraction: Double, token: UUID) {
        guard operationID == token, isWorking, !isCancelling else { return }
        progress = min(1, max(0, fraction))
    }

    private func download() {
        begin(status: EmbeddingGemmaCopy.downloading) { token in
            let directory = try await modelStore.install { fraction in
                Task { @MainActor in updateProgress(fraction, token: token) }
            }
            guard !Task.isCancelled, operationID == token else { return }
            modelDirectory = directory
        }
    }

    private func chooseAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        audioURL = url
        result = nil
        errorMessage = nil
    }

    private func transcribe() {
        guard let audioURL, let modelDirectory else { return }
        result = nil
        begin(status: EmbeddingGemmaCopy.working) { token in
            #if canImport(CoreAI) && arch(arm64)
            if #available(macOS 27.0, *) {
                let granted = audioURL.startAccessingSecurityScopedResource()
                defer { if granted { audioURL.stopAccessingSecurityScopedResource() } }
                let output = try await EmbeddingGemmaTranscriber.shared.transcribe(fileURL: audioURL, modelDirectory: modelDirectory) { fraction in
                    Task { @MainActor in updateProgress(fraction, token: token) }
                }
                guard !Task.isCancelled, operationID == token else { return }
                result = output
            }
            #endif
        }
    }

    private func cancel() {
        guard isWorking, !isCancelling else { return }
        isCancelling = true
        operationTask?.cancel()
        status = EmbeddingGemmaCopy.stopping
    }

    private func save(_ text: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = (audioURL?.deletingPathExtension().lastPathComponent ?? "transcript") + ".txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { errorMessage = error.localizedDescription }
    }
}
