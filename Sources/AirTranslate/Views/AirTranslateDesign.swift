import AppKit
import SwiftUI

enum AirTranslateDesign {
    enum Palette {
        static let accent = dynamicColor(light: 0x1F9AA8, dark: 0x38C2CF)
        static let accentBright = dynamicColor(light: 0x38A9B5, dark: 0x54CFDA)
        static let accentSoft = dynamicColor(light: 0xDDEFF1, dark: 0x183A3F)
        static let live = dynamicColor(light: 0x1E9E5A, dark: 0x3DD37F)
        static let liveSoft = dynamicColor(light: 0xE3F4EA, dark: 0x17372A)
        static let paused = dynamicColor(light: 0xC98A00, dark: 0xF2B53D)
        static let pausedSoft = dynamicColor(light: 0xF8EED6, dark: 0x3B3018)
        static let pausedFill = paused.opacity(0.14)
        static let danger = dynamicColor(light: 0xD5473B, dark: 0xFF6B5E)
        static let dangerSoft = dynamicColor(light: 0xF9E7E5, dark: 0x40211F)
        static let dangerFill = danger.opacity(0.14)
        static let warning = dynamicColor(light: 0xB97600, dark: 0xF2B53D)
        static let canvas = dynamicColor(light: 0xF4F5F7, dark: 0x121417)
        static let raised = dynamicColor(light: 0xFFFFFF, dark: 0x1B1E23)
        static let raisedHover = dynamicColor(light: 0xF8FAFB, dark: 0x22262C)
        static let settledCard = dynamicColor(light: 0xFFFFFF, dark: 0x16191E)
        static let hairline = dynamicColor(light: 0xE5E7EA, dark: 0x2B3037)
        static let hairlineStrong = dynamicColor(light: 0xD4D8DD, dark: 0x3A414A)
        static let textPrimary = Color(nsColor: .labelColor)
        static let textSecondary = Color(nsColor: .secondaryLabelColor)
        static let textTertiary = Color(nsColor: .tertiaryLabelColor)
        static let onAccent = dynamicColor(light: 0xFFFFFF, dark: 0x07191B)
        static let shadow = dynamicColor(light: 0x000000, dark: 0x000000)
        static let topHighlight = dynamicColor(light: 0xFFFFFF, dark: 0xFFFFFF)
        static let floatingScrimTop = dynamicColor(light: 0x172126, dark: 0x080B0D)
        static let floatingScrimBottom = dynamicColor(light: 0x0C1114, dark: 0x020405)
        static let floatingTextPrimary = Color.white
        static let floatingTextSecondary = Color.white.opacity(0.82)
        static let floatingOutline = Color.white.opacity(0.12)
        static let floatingShadow = Color.black.opacity(0.72)
        static let transparent = Color.clear
        static let maskOpaque = Color.black

        private static func dynamicColor(light: UInt32, dark: UInt32) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return nsColor(hex: isDark ? dark : light)
            })
        }

        private static func nsColor(hex: UInt32) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }

    enum Typography {
        static let captionTranslation = Font.system(size: 22, weight: .medium)
        static let captionOriginal = Font.system(size: 15, weight: .regular)
        static let stageTitle = Font.system(size: 17, weight: .semibold)
        static let label = Font.system(size: 13, weight: .medium)
        static let meta = Font.system(size: 12, weight: .regular)
        static let sectionLabel = Font.system(size: 11, weight: .semibold)
        static let consolePrimary = Font.system(size: 15, weight: .semibold)
        static let settingsTitle = Font.system(size: 22, weight: .semibold)
        static let libraryRowTitle = Font.system(size: 15, weight: .medium)
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let control: CGFloat = 8
        static let surface: CGFloat = 12
        static let console: CGFloat = 18
    }

    enum Elevation {
        static let floatingRadius: CGFloat = 24
        static let floatingY: CGFloat = 8
        static let floatingOpacity: Double = 0.16
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.14)
        static let state = Animation.spring(response: 0.28, dampingFraction: 0.86)
        static let enter = Animation.easeOut(duration: 0.22)
    }

    static let mainWindowMinimumWidth: CGFloat = 900
    static let mainWindowMinimumHeight: CGFloat = 560
    static let settingsWindowMinimumWidth: CGFloat = 900
    static let settingsWindowMinimumHeight: CGFloat = 650
    static let libraryMinimumWidth: CGFloat = 820
    static let libraryIdealWidth: CGFloat = 960
    static let libraryMinimumHeight: CGFloat = 520
    static let libraryIdealHeight: CGFloat = 620
    static let sidebarMinimum: CGFloat = 260
    static let sidebarIdeal: CGFloat = 280
    static let sidebarMaximum: CGFloat = 300
    static let settingsSidebarMinimum: CGFloat = 220
    static let settingsSidebarIdeal: CGFloat = 240
    static let settingsSidebarMaximum: CGFloat = 260
    static let settingsDetailMaximum: CGFloat = 760
    static let transcriptPairBreakpoint: CGFloat = 620
    static let settingsRowBreakpoint: CGFloat = 680
    static let libraryEditorBreakpoint: CGFloat = 620
    static let transcriptPaneMinimum: CGFloat = 280
    static let workspacePadding: CGFloat = Spacing.lg
    static let sectionSpacing: CGFloat = Spacing.md
    static let rowSpacing: CGFloat = Spacing.xs
    static let controlRadius: CGFloat = Radius.control
    static let surfaceRadius: CGFloat = Radius.surface
    static let iconSmall: CGFloat = 13
    static let iconRegular: CGFloat = 16
    static let iconLarge: CGFloat = 20
    static let separator = Palette.hairline
    static let quietFill = Palette.raisedHover
    static let selectedFill = Palette.accentSoft
}

private struct AirTranslateSurfaceModifier: ViewModifier {
    let isEmphasized: Bool

    func body(content: Content) -> some View {
        content
            .background(
                isEmphasized ? AirTranslateDesign.Palette.accentSoft : AirTranslateDesign.Palette.raised,
                in: RoundedRectangle(cornerRadius: AirTranslateDesign.surfaceRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AirTranslateDesign.surfaceRadius, style: .continuous)
                    .strokeBorder(AirTranslateDesign.Palette.hairline)
            }
    }
}

extension View {
    func airTranslateSurface(isEmphasized: Bool = false) -> some View {
        modifier(AirTranslateSurfaceModifier(isEmphasized: isEmphasized))
    }

    func airTranslateInteractiveSurface(
        isSelected: Bool = false,
        tint: Color = AirTranslateDesign.Palette.accent
    ) -> some View {
        modifier(AirTranslateInteractiveSurfaceModifier(isSelected: isSelected, tint: tint))
    }
}

private struct AirTranslateInteractiveSurfaceModifier: ViewModifier {
    let isSelected: Bool
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: AirTranslateDesign.controlRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AirTranslateDesign.controlRadius, style: .continuous)
                    .strokeBorder(borderColor)
            }
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : AirTranslateDesign.Motion.quick, value: isHovering)
    }

    private var backgroundColor: Color {
        if isSelected {
            return AirTranslateDesign.Palette.accentSoft
        }
        return isHovering ? AirTranslateDesign.Palette.raisedHover : Color.clear
    }

    private var borderColor: Color {
        if isSelected {
            return tint
        }
        return isHovering ? AirTranslateDesign.Palette.hairlineStrong : .clear
    }
}

struct AirTranslatePressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduceMotion ? nil : AirTranslateDesign.Motion.quick, value: configuration.isPressed)
    }
}

private struct AirStageBlockModifier: ViewModifier {
    let isLive: Bool

    func body(content: Content) -> some View {
        content
            .padding(AirTranslateDesign.Spacing.md)
            .background(
                isLive ? AirTranslateDesign.Palette.raised : AirTranslateDesign.Palette.settledCard.opacity(0.75),
                in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.surface, style: .continuous)
            )
            .overlay(alignment: .leading) {
                if isLive {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(AirTranslateDesign.Palette.accent)
                        .frame(width: 3)
                        .padding(.vertical, AirTranslateDesign.Spacing.sm)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.surface, style: .continuous)
                    .strokeBorder(
                        isLive
                            ? AirTranslateDesign.Palette.accent.opacity(0.32)
                            : AirTranslateDesign.Palette.hairline.opacity(0.65)
                    )
            }
    }
}

private struct AirConsoleSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.console, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.console, style: .continuous)
                    .strokeBorder(AirTranslateDesign.Palette.hairlineStrong)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AirTranslateDesign.Palette.topHighlight)
                    .frame(height: 1)
                    .opacity(0.08)
                    .clipShape(RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.console, style: .continuous))
            }
            .shadow(
                color: AirTranslateDesign.Palette.shadow.opacity(AirTranslateDesign.Elevation.floatingOpacity),
                radius: AirTranslateDesign.Elevation.floatingRadius,
                y: AirTranslateDesign.Elevation.floatingY
            )
    }
}

private struct AirRaisedSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                AirTranslateDesign.Palette.raised,
                in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.surface, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.surface, style: .continuous)
                    .strokeBorder(AirTranslateDesign.Palette.hairline)
            }
    }
}

private struct AirFocusRingModifier: ViewModifier {
    let cornerRadius: CGFloat
    let externalFocus: FocusState<Bool>.Binding?
    @FocusState private var internalFocus: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let externalFocus {
            focusRing(
                content.focused(externalFocus),
                isFocused: externalFocus.wrappedValue
            )
        } else {
            focusRing(
                content.focused($internalFocus),
                isFocused: internalFocus
            )
        }
    }

    private func focusRing<FocusedContent: View>(
        _ content: FocusedContent,
        isFocused: Bool
    ) -> some View {
        content
            .focusEffectDisabled()
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous)
                        .stroke(AirTranslateDesign.Palette.accent, lineWidth: 2)
                        .padding(-2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

extension View {
    func airStageBlock(isLive: Bool) -> some View {
        modifier(AirStageBlockModifier(isLive: isLive))
    }

    func airConsoleSurface() -> some View {
        modifier(AirConsoleSurfaceModifier())
    }

    func airRaisedSurface() -> some View {
        modifier(AirRaisedSurfaceModifier())
    }

    func airFocusRing(
        cornerRadius: CGFloat = AirTranslateDesign.Radius.control,
        focus: FocusState<Bool>.Binding? = nil
    ) -> some View {
        modifier(AirFocusRingModifier(cornerRadius: cornerRadius, externalFocus: focus))
    }
}

enum AirPillButtonKind {
    case start
    case stop
    case paused
}

struct AirPillButtonStyle: ButtonStyle {
    let kind: AirPillButtonKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AirTranslateDesign.Typography.consolePrimary)
            .foregroundStyle(foreground)
            .padding(.horizontal, AirTranslateDesign.Spacing.md)
            .frame(minWidth: 112, minHeight: 40)
            .background(background, in: Capsule())
            .overlay {
                Capsule().strokeBorder(border, lineWidth: 1)
            }
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.975 : 1))
            .animation(reduceMotion ? nil : AirTranslateDesign.Motion.quick, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .start: AirTranslateDesign.Palette.onAccent
        case .stop: AirTranslateDesign.Palette.danger
        case .paused: AirTranslateDesign.Palette.paused
        }
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .start:
            AnyShapeStyle(
                LinearGradient(
                    colors: [AirTranslateDesign.Palette.accent, AirTranslateDesign.Palette.accentBright],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .stop:
            AnyShapeStyle(AirTranslateDesign.Palette.dangerFill)
        case .paused:
            AnyShapeStyle(AirTranslateDesign.Palette.pausedFill)
        }
    }

    private var border: Color {
        switch kind {
        case .start: AirTranslateDesign.Palette.accent
        case .stop: AirTranslateDesign.Palette.danger
        case .paused: AirTranslateDesign.Palette.paused
        }
    }
}

struct AirChip: View {
    let text: String
    var systemImage: String?
    var tint = AirTranslateDesign.Palette.accent

    var body: some View {
        Group {
            if let systemImage {
                Label(text, systemImage: systemImage)
            } else {
                Text(text)
            }
        }
        .font(AirTranslateDesign.Typography.meta.weight(.semibold))
        .foregroundStyle(tint)
        .lineLimit(1)
        .padding(.horizontal, AirTranslateDesign.Spacing.xs)
        .padding(.vertical, AirTranslateDesign.Spacing.xxs)
        .background(AirTranslateDesign.Palette.raisedHover, in: Capsule())
        .overlay { Capsule().strokeBorder(AirTranslateDesign.Palette.hairline) }
    }
}

/// A secondary console button with an icon and a short label, the size of `AirIconButton`.
struct AirChipButtonStyle: ButtonStyle {
    var isActive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isActive ? AirTranslateDesign.Palette.danger : AirTranslateDesign.Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                isActive ? AirTranslateDesign.Palette.dangerFill
                    : configuration.isPressed ? AirTranslateDesign.Palette.accentSoft : AirTranslateDesign.Palette.raisedHover,
                in: Capsule()
            )
            .overlay { Capsule().strokeBorder(AirTranslateDesign.Palette.hairline) }
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .animation(reduceMotion ? nil : AirTranslateDesign.Motion.quick, value: configuration.isPressed)
    }
}

struct AirIconButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: AirTranslateDesign.iconRegular, weight: .semibold))
            .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
            .frame(width: 36, height: 36)
            .background(
                configuration.isPressed ? AirTranslateDesign.Palette.accentSoft : AirTranslateDesign.Palette.raisedHover,
                in: Circle()
            )
            .overlay { Circle().strokeBorder(AirTranslateDesign.Palette.hairline) }
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.94 : 1))
            .animation(reduceMotion ? nil : AirTranslateDesign.Motion.quick, value: configuration.isPressed)
    }
}
