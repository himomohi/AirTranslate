import SwiftUI

/// 공급자마다 같은 키 편집·피드백·삭제 흐름을 사용한다. 저장된 키는 읽어 오지 않는다.
struct ProviderCredentialRow<Configuration: View>: View {
    let name: String
    let symbol: String
    let model: String
    let detail: String
    let consoleURL: URL
    let hasKey: Bool
    let needsConfiguration: Bool
    let isCurrent: Bool
    let isLocked: Bool
    @Binding var isExpanded: Bool
    let saveKey: (String) throws -> Void
    let removeKey: () throws -> Void
    @ViewBuilder let configuration: Configuration

    @State private var draft = ""
    @State private var feedback: String?
    @State private var hasError = false
    @State private var showsRemovalConfirmation = false
    @State private var showsDetails = false
    @FocusState private var isKeyFocused: Bool

    private var status: String {
        if needsConfiguration { return CredentialsCopy.setupNeeded }
        return hasKey ? CredentialsCopy.saved : CredentialsCopy.keyNeeded
    }

    private var statusSymbol: String {
        if needsConfiguration { return "exclamationmark.circle" }
        return hasKey ? "checkmark.circle.fill" : "key"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: symbol)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(AirTranslateDesign.Palette.accent)
                            .frame(width: 34, height: 34)
                            .background(AirTranslateDesign.Palette.accentSoft, in: RoundedRectangle(cornerRadius: 9))
                            .accessibilityHidden(true)
                        Text(name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 4)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(CredentialsCopy.edit(name))
                .accessibilityLabel(CredentialsCopy.edit(name))
                .accessibilityValue("\(isCurrent ? CredentialsCopy.inUse + ", " : "")\(status), \(isExpanded ? CredentialsCopy.expanded : CredentialsCopy.collapsed)")

                if isCurrent {
                    InlineHelpIcon(symbol: "checkmark.seal.fill", help: "\(name) · \(CredentialsCopy.inUse)",
                                   tint: AirTranslateDesign.Palette.accent)
                }
                InlineHelpIcon(symbol: statusSymbol, help: "\(name) · \(status)",
                               tint: hasKey && !needsConfiguration ? AirTranslateDesign.Palette.live : AirTranslateDesign.Palette.textSecondary)

                Button { showsDetails.toggle() } label: {
                    Image(systemName: "info.circle")
                        .frame(width: 28, height: 30)
                }
                .buttonStyle(.borderless)
                .help(CredentialsCopy.details(name))
                .accessibilityLabel(CredentialsCopy.details(name))
                .popover(isPresented: $showsDetails, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(name).font(.headline)
                        Text(model).font(.callout.weight(.medium)).textSelection(.enabled)
                        Text(detail).font(.callout).foregroundStyle(.secondary)
                        Text(CredentialsCopy.savedDoesNotVerify).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Spacer()
                            Button(CredentialsCopy.done) { showsDetails = false }
                                .keyboardShortcut(.cancelAction)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(20)
                    .frame(width: 340)
                }

                Link(destination: consoleURL) {
                    Image(systemName: "arrow.up.right.square")
                        .frame(width: 28, height: 30)
                }
                .buttonStyle(.borderless)
                .help(CredentialsCopy.console(name))
                .accessibilityLabel(CredentialsCopy.console(name))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "key.horizontal")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        SecureField(hasKey ? CredentialsCopy.replaceKey : CredentialsCopy.pasteKey, text: $draft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .focused($isKeyFocused)
                            .onSubmit(save)
                            .accessibilityLabel("\(name) \(CredentialsCopy.keyLabel)")
                            .accessibilityHint(CredentialsCopy.keyHint)
                            .disabled(isLocked)
                            .task {
                                // 펼쳐진 입력이 화면에 연결된 다음 포커스를 이동한다.
                                await Task.yield()
                                if isExpanded && !isLocked { isKeyFocused = true }
                            }
                        Button(action: save) {
                            Image(systemName: "square.and.arrow.down")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLocked || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help(CredentialsCopy.save(name))
                        .accessibilityLabel(CredentialsCopy.save(name))

                        Button { showsRemovalConfirmation = true } label: {
                            Image(systemName: "trash")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLocked || !hasKey)
                        .help(CredentialsCopy.remove(name))
                        .accessibilityLabel(CredentialsCopy.remove(name))
                        .confirmationDialog(
                            CredentialsCopy.confirmRemoval(name),
                            isPresented: $showsRemovalConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button(CredentialsCopy.remove(name), role: .destructive, action: remove)
                            Button(AppText.cancel, role: .cancel) {}
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 6)
                    .padding(.vertical, 4)
                    .background(AirTranslateDesign.Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isKeyFocused ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.hairlineStrong)
                    }

                    configuration

                    if let feedback {
                        Label(feedback, systemImage: hasError ? "exclamationmark.circle.fill" : "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(hasError ? AirTranslateDesign.Palette.danger : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 16)
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { isKeyFocused = false }
        }
        .onChange(of: isLocked) { _, locked in
            if locked { showsRemovalConfirmation = false }
        }
        .onDisappear {
            draft = ""
            feedback = nil
        }
    }

    private func save() {
        guard !isLocked else { return }
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try saveKey(key)
            draft = ""
            hasError = false
            feedback = CredentialsCopy.saved
        } catch {
            hasError = true
            feedback = error.localizedDescription
        }
    }

    private func remove() {
        guard !isLocked, hasKey else { return }
        do {
            try removeKey()
            draft = ""
            hasError = false
            feedback = CredentialsCopy.removed
        } catch {
            hasError = true
            feedback = error.localizedDescription
        }
    }
}
