import SwiftUI

enum FloatingCaptionTextAlignment: String, CaseIterable, Identifiable {
    case leading
    case center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leading:
            AppText.textAlignmentLeading
        case .center:
            AppText.textAlignmentCenter
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading:
            .leading
        case .center:
            .center
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading:
            .leading
        case .center:
            .center
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading:
            .leading
        case .center:
            .center
        }
    }
}
