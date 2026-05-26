import SwiftUI

struct SettingsInlineGroup<Content: View>: View {
    let systemImage: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.055), lineWidth: 1)
        }
    }
}

struct SettingsCompactToggleRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 18, height: 18)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .accessibilityLabel(title)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SettingsCompactInfoRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SettingsCompactMenuRow<MenuContent: View>: View {
    let title: String
    let systemImage: String
    let value: String
    @ViewBuilder let menuContent: MenuContent

    var body: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 6)

                Text(value)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

struct SettingsProviderPickerRow: View {
    let title: String
    @Binding var selection: OpenAIProvider

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cloud.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 6)

            Picker("", selection: $selection) {
                ForEach(OpenAIProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SettingsSegmentedPickerRow<Selection: Hashable, PickerContent: View>: View {
    let title: String
    let systemImage: String
    @Binding var selection: Selection
    @ViewBuilder let pickerContent: PickerContent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Picker(title, selection: $selection) {
                pickerContent
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel(title)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SettingsStepperRow: View {
    let title: String
    let systemImage: String
    let valueText: String
    @Binding var value: Double

    var body: some View {
        Stepper(value: $value, in: 1...15, step: 0.5) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 6)

                Text(valueText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SettingsAPIKeyRow: View {
    @Binding var apiKey: String
    @Binding var shouldFocusAPIKey: Bool
    @FocusState private var isAPIKeyFocused: Bool
    let hasAPIKey: Bool
    let notice: String?
    let save: () -> Void
    let remove: () -> Void

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(hasAPIKey ? Color.green : Color.secondary)
                    .frame(width: 16)

                SecureField(AppText.openAIAPIKeyPlaceholder, text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .focused($isAPIKeyFocused)
                    .frame(minWidth: 0, maxWidth: .infinity)

                Button { save() } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(trimmedAPIKey.isEmpty)
                .help(AppText.saveOpenAIAPIKey)
                .accessibilityLabel(AppText.saveOpenAIAPIKey)

                Button { remove() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(!hasAPIKey)
                .help(AppText.removeOpenAIAPIKey)
                .accessibilityLabel(AppText.removeOpenAIAPIKey)
            }

            if let notice, !hasAPIKey {
                SettingsNoticeText(notice)
            }

            Text(hasAPIKey ? AppText.openAIAPIKeyConfigured : AppText.openAIAPIKeyNotConfigured)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(hasAPIKey ? Color.green : Color.secondary)
                .padding(.leading, 24)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear { focusAPIKeyIfNeeded() }
        .onChange(of: shouldFocusAPIKey) { _, _ in focusAPIKeyIfNeeded() }
    }

    private func focusAPIKeyIfNeeded() {
        guard shouldFocusAPIKey else { return }
        Task { @MainActor in
            isAPIKeyFocused = true
            shouldFocusAPIKey = false
        }
    }
}

struct SettingsAzureConfigRow: View {
    @Binding var endpoint: String
    @Binding var apiKey: String
    @Binding var shouldFocusAPIKey: Bool
    @FocusState private var isAPIKeyFocused: Bool
    let hasConfig: Bool
    let notice: String?
    let save: () -> Void
    let remove: () -> Void

    private var trimmedEndpoint: String {
        endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(hasConfig ? Color.green : Color.secondary)
                    .frame(width: 16)

                TextField(AppText.azureOpenAIEndpointPlaceholder, text: $endpoint)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .textContentType(.URL)
                    .autocorrectionDisabled(true)
                    .frame(minWidth: 0, maxWidth: .infinity)
            }

            Text(AppText.azureOpenAIEndpointFormatHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 24)

            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(hasConfig ? Color.green : Color.secondary)
                    .frame(width: 16)

                SecureField(AppText.azureOpenAIAPIKeyPlaceholder, text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .focused($isAPIKeyFocused)
                    .frame(minWidth: 0, maxWidth: .infinity)

                Button { save() } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(trimmedAPIKey.isEmpty || trimmedEndpoint.isEmpty)
                .help(AppText.saveAzureOpenAIConfig)
                .accessibilityLabel(AppText.saveAzureOpenAIConfig)

                Button { remove() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(!hasConfig)
                .help(AppText.removeAzureOpenAIConfig)
                .accessibilityLabel(AppText.removeAzureOpenAIConfig)
            }

            if let notice, !hasConfig {
                SettingsNoticeText(notice)
            }

            Text(hasConfig ? AppText.azureOpenAIConfigConfigured : AppText.azureOpenAIConfigNotConfigured)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(hasConfig ? Color.green : Color.secondary)
                .padding(.leading, 24)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear { focusAPIKeyIfNeeded() }
        .onChange(of: shouldFocusAPIKey) { _, _ in focusAPIKeyIfNeeded() }
    }

    private func focusAPIKeyIfNeeded() {
        guard shouldFocusAPIKey else { return }
        Task { @MainActor in
            isAPIKeyFocused = true
            shouldFocusAPIKey = false
        }
    }
}

struct SettingsAssetAvailabilityRow: View {
    let title: String
    let availability: ModelAvailability
    let download: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(availability.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if availability.state == .checking || availability.state == .downloading {
                ProgressView()
                    .controlSize(.small)
            } else if availability.state.canDownload {
                Button(AppText.download) { download() }
                    .controlSize(.small)
            } else {
                Text(availability.state.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(availability.detail)
    }

    private var symbolName: String {
        switch availability.state {
        case .checking:
            "clock"
        case .installed:
            "checkmark.seal.fill"
        case .downloadRequired, .downloading:
            "arrow.down.circle.fill"
        case .unsupported, .unavailable, .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch availability.state {
        case .checking:
            .secondary
        case .installed:
            .green
        case .downloadRequired, .downloading:
            .orange
        case .unsupported, .unavailable, .failed:
            .red
        }
    }
}

struct SettingsAdvancedDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ModelNameOverrideField: View {
    let title: String
    let systemImage: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .help(title)
                .accessibilityLabel(title)

            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .autocorrectionDisabled(true)
                .frame(minWidth: 0, maxWidth: .infinity)
        }
    }
}

/// Azure-only advanced overrides for the OpenAI Realtime section.
/// Renders nothing when the active provider is OpenAI.
struct OpenAIAdvancedOverridesView: View {
    @Bindable var session: TranslationSessionStore

    var body: some View {
        if session.openAIProvider == .azure {
            let transcriptionPlaceholder = session.openAITranscriptionModel.isEnabled
                ? session.openAITranscriptionModel.rawValue
                : OpenAIRealtimeTranscriptionModel.gptRealtimeWhisper.rawValue
            let translationPlaceholder = session.openAITranslationModel.isEnabled
                ? session.openAITranslationModel.apiModelID
                : OpenAIRealtimeTranslationModel.gptRealtimeTranslate.apiModelID

            SettingsAdvancedDisclosure(title: AppText.advancedSection) {
                VStack(alignment: .leading, spacing: 6) {
                    ModelNameOverrideField(
                        title: AppText.customTranscriptionModelName,
                        systemImage: "waveform.circle.fill",
                        placeholder: transcriptionPlaceholder,
                        text: $session.customAzureTranscriptionModelName
                    )
                    ModelNameOverrideField(
                        title: AppText.customTranslationModelName,
                        systemImage: "globe",
                        placeholder: translationPlaceholder,
                        text: $session.customAzureTranslationModelName
                    )

                    Text(AppText.customModelNameFootnote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SettingsNoticeText: View {
    let notice: String

    init(_ notice: String) {
        self.notice = notice
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.orange)

            Text(notice)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 24)
    }
}
