import SwiftUI

struct AppleTranslationSettingsView: View {
    @Bindable var session: TranslationSessionStore

    private var isLocked: Bool {
        session.isRunning || session.isStarting || !session.isUsingAppleTextTranslation
            || !session.supportsAppleTranslationOptions
    }

    var body: some View {
        SettingsGroup(title: AppleTranslationCopy.title) {
            SettingsControlRow(
                title: AppleTranslationCopy.quality,
                detail: AppleTranslationCopy.detail,
                systemImage: "character.bubble",
                detailLineLimit: nil
            ) {
                Picker(AppleTranslationCopy.quality, selection: $session.appleTranslationQuality) {
                    ForEach(AppleTranslationQuality.allCases, id: \.self) { quality in
                        Text(AppleTranslationCopy.title(for: quality)).tag(quality)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 160)
                .disabled(isLocked)
                .accessibilityLabel(AppleTranslationCopy.quality)
                .accessibilityValue(AppleTranslationCopy.title(for: session.appleTranslationQuality))
                .accessibilityHint(AppleTranslationCopy.detail)
                .accessibilityIdentifier("appleTranslationQualityPicker")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppleTranslationCopy.protectedTerms)
                    .font(.headline)
                Text(AppleTranslationCopy.termsDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AppleTranslationCopy.termsFallbackHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $session.appleProtectedTermsText)
                    .font(.body)
                    .frame(height: 110)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.25)))
                    .disabled(isLocked)
                    .accessibilityLabel(AppleTranslationCopy.protectedTerms)
                    .accessibilityHint(AppleTranslationCopy.termsDetail)
                    .accessibilityIdentifier("appleProtectedTermsEditor")
                Text(AppleTranslationCopy.acceptedTerms(session.appleTranslationOptions.normalizedProtectedTerms.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("appleProtectedTermsCount")
            }
            .padding(.vertical, AirTranslateDesign.Spacing.sm)

            if session.isUsingAppleRealtimeFallback && session.appleTranslationQuality == .highQuality {
                SettingsNoticeRow(text: AppleTranslationCopy.fallbackDetail, systemImage: "info.circle")
            }
            if session.didKeepOriginalForAppleProtectedTerms {
                SettingsNoticeRow(text: AppleTranslationCopy.termsFallback, systemImage: "info.circle")
            }
            if !session.supportsAppleTranslationOptions {
                SettingsNoticeRow(text: AppleTranslationCopy.requiresRecentOS, systemImage: "info.circle")
            } else if session.isRunning || session.isStarting {
                SettingsNoticeRow(text: SettingsCopy.captureRunningDisabledReason, systemImage: "pause.circle")
            } else if !session.isUsingAppleTextTranslation {
                SettingsNoticeRow(text: AppleTranslationCopy.appleOnly, systemImage: "info.circle")
            }
        }
    }
}
