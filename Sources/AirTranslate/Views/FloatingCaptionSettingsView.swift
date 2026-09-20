import AppKit
import SwiftUI

struct FloatingCaptionSettingsView: View {
    @Bindable var session: TranslationSessionStore
    @State private var showsTypography = false
    @State private var confirmsReset = false
    @State private var isCaptionVisible = FloatingCaptionWindowController.isOpen

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            presetPicker
            FloatingCaptionStylePreview(session: session)
            GroupBox(CaptionStyleCopy.content) {
                VStack(alignment: .leading, spacing: 14) {
                    Picker(AppText.floatingDisplay, selection: $session.floatingCaptionDisplayMode) {
                        ForEach(session.availableFloatingCaptionDisplayModes) { Text($0.title).tag($0) }
                    }
                    .disabled(session.isTranscribeOnlyMode)
                    sizeControl
                    Picker(AppText.floatingLineCount, selection: $session.floatingCaptionLineCount) {
                        ForEach(FloatingCaptionLineCount.allCases) { Text($0.title).tag($0) }
                    }
                    Text(CaptionStyleCopy.lineHint).font(.caption).foregroundStyle(.secondary)
                    Picker(AppText.captionAlignment, selection: $session.floatingCaptionTextAlignment) {
                        ForEach(FloatingCaptionTextAlignment.allCases) { Text($0.title).tag($0) }
                    }
                    if session.floatingCaptionDisplayMode == .originalAndTranslation {
                        Toggle(CaptionStyleCopy.translationFirst, isOn: $session.floatingCaptionStyle.translationFirst)
                    }
                    Picker(AppText.captionStability, selection: $session.floatingCaptionStability) {
                        ForEach(FloatingCaptionStability.allCases) { Text($0.title).tag($0) }
                    }
                    .help(AppText.captionStabilityDescription)
                }
                .padding(8)
            }

            GroupBox {
                DisclosureGroup(CaptionStyleCopy.typography, isExpanded: $showsTypography) {
                    VStack(spacing: 14) {
                        Picker(CaptionStyleCopy.font, selection: $session.floatingCaptionStyle.fontFamily) {
                            ForEach(FloatingCaptionFontFamily.allCases) { Text($0.title).tag($0) }
                        }
                        Picker(CaptionStyleCopy.weight, selection: $session.floatingCaptionStyle.fontWeight) {
                            ForEach(FloatingCaptionFontWeight.allCases) { Text($0.title).tag($0) }
                        }
                        Picker(CaptionStyleCopy.spacing, selection: $session.floatingCaptionStyle.lineSpacing) {
                            ForEach(FloatingCaptionLineSpacing.allCases) { Text($0.title).tag($0) }
                        }
                        Picker(CaptionStyleCopy.effect, selection: $session.floatingCaptionStyle.textEffect) {
                            ForEach(FloatingCaptionTextEffect.allCases) { Text($0.title).tag($0) }
                        }
                        CaptionHexColorRow(title: AppText.floatingTextColor, hex: $session.floatingCaptionTextColorHex)
                    }
                    .padding(.top, 12)
                }
                .padding(8)
            }

            GroupBox(CaptionStyleCopy.window) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(CaptionStyleCopy.captionOnlyHint).font(.caption).foregroundStyle(.secondary)
                    Toggle(CaptionStyleCopy.keepOnTop, isOn: $session.keepsFloatingCaptionAboveOtherWindows)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(CaptionStyleCopy.width)
                            Spacer()
                            Text("\(Int(captionWidth.wrappedValue)) pt").monospacedDigit()
                        }
                        Slider(value: captionWidth, in: 420...maximumCaptionWidth, step: 10)
                            .disabled(!isCaptionVisible)
                            .accessibilityLabel(CaptionStyleCopy.width)
                            .accessibilityValue("\(Int(captionWidth.wrappedValue)) pt")
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack { windowActions }
                        VStack(alignment: .leading) { windowActions }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            Button(CaptionStyleCopy.resetStyle) { confirmsReset = true }
                .confirmationDialog(CaptionStyleCopy.resetStyleHint, isPresented: $confirmsReset, titleVisibility: .visible) {
                    Button(CaptionStyleCopy.resetStyle) { session.resetFloatingCaptionAppearance() }
                    Button(CaptionStyleCopy.cancel, role: .cancel) {}
                }
        }
        .onAppear { isCaptionVisible = FloatingCaptionWindowController.isOpen }
        .onReceive(NotificationCenter.default.publisher(for: FloatingCaptionWindowController.visibilityDidChangeNotification)) { _ in
            isCaptionVisible = FloatingCaptionWindowController.isOpen
        }
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(CaptionStyleCopy.presets).font(.headline)
                Spacer()
                Text(session.selectedFloatingCaptionPreset?.title ?? CaptionStyleCopy.custom)
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 102), spacing: 8)], spacing: 8) {
                ForEach(FloatingCaptionPreset.allCases) { preset in
                    CaptionPresetButton(preset: preset, isSelected: session.selectedFloatingCaptionPreset == preset) {
                        session.applyFloatingCaptionPreset(preset)
                    }
                }
            }
            Text(CaptionStyleCopy.presetHint).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var sizeControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(CaptionStyleCopy.size)
                Spacer()
                Stepper(value: pointSize, in: 18...72, step: 1) {
                    Text("\(Int(session.floatingCaptionPrimaryPointSize)) pt").monospacedDigit()
                }
                .fixedSize()
                .accessibilityLabel(CaptionStyleCopy.size)
                .accessibilityValue("\(Int(session.floatingCaptionPrimaryPointSize)) pt")
            }
            Slider(value: pointSize, in: 18...72, step: 1)
                .accessibilityLabel(CaptionStyleCopy.size)
                .accessibilityValue("\(Int(session.floatingCaptionPrimaryPointSize)) pt")
        }
    }

    private var pointSize: Binding<Double> {
        Binding(get: { Double(session.floatingCaptionPrimaryPointSize) }, set: { session.floatingCaptionCustomPointSize = CGFloat($0) })
    }

    @ViewBuilder private var windowActions: some View {
        Button(isCaptionVisible ? CaptionStyleCopy.closeWindow : CaptionStyleCopy.openWindow) {
            FloatingCaptionWindowController.toggle(session: session)
        }
        Button(AppText.resetFloatingCaptionSize) { FloatingCaptionWindowController.resetSize() }
    }

    private var maximumCaptionWidth: Double {
        Double(FloatingCaptionWindowController.maximumWindowSize(for: NSScreen.main).width)
    }

    private var captionWidth: Binding<Double> {
        Binding(get: {
            let measured = session.floatingCaptionMeasuredTextWidth
            let width = measured > 0 ? measured + AirTranslateDesign.Spacing.lg * 2 : FloatingCaptionWindowController.defaultWindowSize.width
            return min(maximumCaptionWidth, max(420, Double(width)))
        }, set: { FloatingCaptionWindowController.setWidth(CGFloat($0)) })
    }
}

private struct CaptionPresetButton: View {
    let preset: FloatingCaptionPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Aa").font(.system(size: 23, weight: preset.style.fontWeight.primary, design: preset.style.fontFamily.design))
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                }
                Text(preset.title).font(.caption.weight(.semibold)).lineLimit(2)
            }
            .foregroundStyle(FloatingCaptionAppearance.color(hex: preset.textColorHex, fallback: "#FFFFFF"))
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(FloatingCaptionAppearance.color(hex: preset.previewSceneHex, fallback: "#05080A"), in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 3 : 1) }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(preset.detail)
        .accessibilityLabel(preset.title)
        .accessibilityValue(isSelected ? AppText.localized(english: "Selected", korean: "선택됨", japanese: "選択中", chineseSimplified: "已选择") : "")
        .accessibilityHint(preset.detail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FloatingCaptionStylePreview: View {
    let session: TranslationSessionStore
    @State private var lightScene = false
    @State private var textWidth: CGFloat = 500

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(CaptionStyleCopy.preview).font(.headline)
                Spacer()
                Picker(CaptionStyleCopy.scene, selection: $lightScene) {
                    Text(CaptionStyleCopy.darkScene).tag(false)
                    Text(CaptionStyleCopy.lightScene).tag(true)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            ScrollView {
                VStack(spacing: FloatingCaptionAppearance.captionBlockSpacing) {
                    if session.floatingCaptionStyle.translationFirst { translatedText }
                    if session.floatingCaptionDisplayMode != .translation {
                        sampleText(CaptionStyleCopy.sampleOriginal, primary: session.floatingCaptionDisplayMode == .original)
                    }
                    if !session.floatingCaptionStyle.translationFirst { translatedText }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .padding(18)
                .onGeometryChange(for: CGFloat.self) { max(1, $0.size.width - 68) } action: { textWidth = $0 }
            }
            .frame(height: previewHeight)
            .background(LinearGradient(colors: lightScene ? [.white, Color(white: 0.75)] : [Color(white: 0.08), Color(white: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.25)) }
            Text(CaptionStyleCopy.previewHint)
                .font(.caption).foregroundStyle(.secondary)
            Button {
                FloatingCaptionWindowController.open(session: session, preview: true)
            } label: {
                Label(CaptionStyleCopy.previewWindow, systemImage: "rectangle.on.rectangle")
            }
            .disabled(session.isRunning || session.isStarting)
        }
    }

    @ViewBuilder private var translatedText: some View {
        if session.floatingCaptionDisplayMode != .original {
            sampleText(CaptionStyleCopy.sampleTranslation, primary: true)
        }
    }

    private func sampleText(_ text: String, primary: Bool) -> some View {
        Text(formattedSample(text, primary: primary))
            .font(primary ? session.floatingCaptionPrimaryFont : session.floatingCaptionSecondaryFont)
            .foregroundStyle(session.floatingCaptionTextColor.opacity(primary ? 1 : 0.82))
            .lineSpacing(session.floatingCaptionStyle.lineSpacing.points)
            .multilineTextAlignment(session.floatingCaptionTextAlignment.textAlignment)
            .frame(maxWidth: .infinity, alignment: session.floatingCaptionTextAlignment.frameAlignment(vertical: .center))
            .fixedSize(horizontal: false, vertical: true)
            .modifier(CaptionTextEffectModifier(effect: session.floatingCaptionStyle.textEffect))
    }

    private func formattedSample(_ text: String, primary: Bool) -> String {
        let size = primary ? session.floatingCaptionPrimaryPointSize : session.floatingCaptionSecondaryPointSize
        return text.floatingCaptionTail(maxLines: session.floatingCaptionLineCount.rawValue, availableWidth: textWidth, font: session.floatingCaptionStyle.nativeFont(size: size, primary: primary))
    }

    private var previewHeight: CGFloat {
        var height: CGFloat = 68
        if session.floatingCaptionDisplayMode != .translation {
            let primary = session.floatingCaptionDisplayMode == .original
            let lines = formattedSample(CaptionStyleCopy.sampleOriginal, primary: primary).components(separatedBy: "\n").count
            height += FloatingCaptionAppearance.blockHeight(lineHeight: primary ? session.floatingCaptionPrimaryLineHeight : session.floatingCaptionSecondaryLineHeight, lineCount: lines, lineSpacing: session.floatingCaptionStyle.lineSpacing.points)
        }
        if session.floatingCaptionDisplayMode != .original {
            let lines = formattedSample(CaptionStyleCopy.sampleTranslation, primary: true).components(separatedBy: "\n").count
            height += FloatingCaptionAppearance.blockHeight(lineHeight: session.floatingCaptionPrimaryLineHeight, lineCount: lines, lineSpacing: session.floatingCaptionStyle.lineSpacing.points)
        }
        if session.floatingCaptionDisplayMode == .originalAndTranslation {
            height += FloatingCaptionAppearance.captionBlockSpacing
        }
        return min(320, max(140, height))
    }
}

struct CaptionTextEffectModifier: ViewModifier {
    let effect: FloatingCaptionTextEffect
    func body(content: Content) -> some View {
        content
            .shadow(color: effect == .none ? .clear : .black.opacity(0.85), radius: effect == .outline ? 1 : 8, x: 0, y: effect == .outline ? 0 : 2)
            .shadow(color: effect == .outline ? .black : .clear, radius: 0, x: 1, y: 0)
            .shadow(color: effect == .outline ? .black : .clear, radius: 0, x: -1, y: 0)
            .shadow(color: effect == .outline ? .black : .clear, radius: 0, x: 0, y: 1)
            .shadow(color: effect == .outline ? .black : .clear, radius: 0, x: 0, y: -1)
    }
}

private struct CaptionHexColorRow: View {
    let title: String
    @Binding var hex: String
    @State private var draft = ""

    private var normalized: String? {
        FloatingCaptionAppearance.nsColor(hex: draft).flatMap(FloatingCaptionAppearance.hexString)
    }
    private var color: Binding<Color> {
        Binding(get: { FloatingCaptionAppearance.color(hex: hex, fallback: "#FFFFFF") }, set: {
            if let value = FloatingCaptionAppearance.hexString(from: NSColor($0)) { hex = value }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack { Text(title); Spacer(); editor }
                VStack(alignment: .leading) { Text(title); editor }
            }
            if normalized == nil, !draft.isEmpty {
                Text(CaptionStyleCopy.invalidColor).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { draft = hex }
        .onChange(of: hex) { _, value in draft = value }
    }
    private var editor: some View {
        HStack {
            ColorPicker(title, selection: color, supportsOpacity: false).labelsHidden().accessibilityLabel(title)
            TextField("#RRGGBB", text: $draft)
                .font(.system(.body, design: .monospaced)).textFieldStyle(.roundedBorder).frame(width: 96)
                .accessibilityLabel("\(title) \(AppText.floatingColorCode)").onSubmit(apply)
            Button(AppText.applyFloatingColor, action: apply).disabled(normalized == nil || normalized == hex)
                .accessibilityLabel("\(title) \(AppText.applyFloatingColor)")
        }
    }
    private func apply() {
        guard let normalized else { return }
        hex = normalized
        draft = normalized
    }
}
