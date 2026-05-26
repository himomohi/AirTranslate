import SwiftUI

extension OpenAIRealtimeTranslationModel {
    /// Single source of truth for which translation models are user-selectable per provider.
    /// Azure routes both `.gptRealtimeTranslate` and `.gptRealtimeTranslateOnly` through identical
    /// API calls, so the "translation only" duplicate is hidden there.
    static func availableCases(for provider: OpenAIProvider) -> [OpenAIRealtimeTranslationModel] {
        switch provider {
        case .azure:
            return allCases.filter { $0 != .gptRealtimeTranslateOnly }
        case .openAI:
            return allCases
        }
    }
}

/// Reusable trio of pickers (Provider, Transcription model, Translation model) shared by
/// SettingsView and the in-session ConfigurationSheetView so the two stay in lockstep.
struct OpenAIRealtimeModelPickers: View {
    @Bindable var session: TranslationSessionStore
    var onProviderChange: ((OpenAIProvider) -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            SettingsProviderPickerRow(
                title: AppText.openAIProvider,
                selection: Binding(
                    get: { session.openAIProvider },
                    set: { newValue in
                        session.openAIProvider = newValue
                        onProviderChange?(newValue)
                    }
                )
            )

            if session.openAITranslationModel.usesRealtimeAudioTranslation {
                SettingsCompactInfoRow(
                    title: AppText.gptTranscriptionLockedByRealtimeTitle,
                    detail: AppText.gptTranscriptionLockedByRealtimeDetail,
                    systemImage: "waveform.circle.fill"
                )
            } else {
                SettingsCompactMenuRow(
                    title: AppText.gptTranscriptionModel,
                    systemImage: "waveform.circle.fill",
                    value: session.openAITranscriptionModel.title
                ) {
                    ForEach(OpenAIRealtimeTranscriptionModel.allCases) { model in
                        Button(model.title) {
                            session.openAITranscriptionModel = model
                        }
                    }
                }
            }

            SettingsCompactMenuRow(
                title: AppText.gptTranslationModel,
                systemImage: "globe",
                value: session.openAITranslationModel.title
            ) {
                ForEach(OpenAIRealtimeTranslationModel.availableCases(for: session.openAIProvider)) { model in
                    Button(model.title) {
                        session.openAITranslationModel = model
                    }
                }
            }
        }
    }
}
