import SwiftUI

struct AppleTranslationSettingsView: View {
    @Bindable var session: TranslationSessionStore

    private var isLocked: Bool {
        session.isRunning || session.isStarting || !session.isUsingAppleTextTranslation
            || !session.supportsAppleTranslationOptions
    }

    var body: some View {
        SettingsGroup(title: AppleTranslationCopy.title) {
            if session.canUseAppleFastCaptions {
                SettingsControlRow(
                    title: AppleTranslationCopy.fastCaptions,
                    detail: AppleTranslationCopy.fastCaptionsDetail,
                    systemImage: "bolt",
                    detailLineLimit: nil
                ) {
                    Toggle(AppleTranslationCopy.fastCaptions, isOn: $session.appleFastCaptionsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(AirTranslateDesign.Palette.accent)
                        .disabled(session.isRunning || session.isStarting)
                        .accessibilityHint(AppleTranslationCopy.fastCaptionsDetail)
                        .accessibilityIdentifier("appleFastCaptionsToggle")
                }
            }

            SettingsControlRow(
                title: AppleTranslationCopy.quality,
                detail: AppleTranslationCopy.detail,
                systemImage: "character.bubble",
                detailLineLimit: nil
            ) {
                if session.isUsingAppleFastCaptions {
                    Text(AppleTranslationCopy.title(for: .realtime))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(AppleTranslationCopy.quality)
                        .accessibilityValue(AppleTranslationCopy.title(for: .realtime))
                } else {
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
                TerminologyChipEditor(
                    text: $session.appleProtectedTermsText,
                    isDisabled: isLocked,
                    accessibilityLabel: AppleTranslationCopy.protectedTerms,
                    accessibilityHint: AppleTranslationCopy.termsDetail,
                    accessibilityIdentifier: "appleProtectedTermsEditor",
                    editorHeight: 100
                )
                Text(AppleTranslationCopy.acceptedTerms(session.appleTranslationOptions.normalizedProtectedTerms.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("appleProtectedTermsCount")
            }
            .padding(.vertical, AirTranslateDesign.Spacing.sm)

            if session.isUsingAppleRealtimeFallback && session.appleTranslationOptions.quality == .highQuality {
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
