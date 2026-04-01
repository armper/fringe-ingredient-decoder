import SwiftUI

enum AppTheme {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.04, blue: 0.05),
            Color(red: 0.07, green: 0.09, blue: 0.10),
            Color(red: 0.12, green: 0.17, blue: 0.15)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let scannerShade = LinearGradient(
        colors: [.black.opacity(0.62), .clear, .black.opacity(0.78)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let panelFill = Color.white.opacity(0.08)
    static let elevatedFill = Color.white.opacity(0.12)
    static let border = Color.white.opacity(0.12)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.66)
    static let tertiaryText = Color.white.opacity(0.42)

    static func summaryColor(_ tone: SummaryTone) -> Color {
        switch tone {
        case .simple:
            return Color(red: 0.42, green: 0.93, blue: 0.67)
        case .balanced:
            return Color(red: 0.87, green: 0.83, blue: 0.45)
        case .additives:
            return Color(red: 1.0, green: 0.61, blue: 0.28)
        case .processed:
            return Color(red: 0.98, green: 0.40, blue: 0.33)
        case .unclear:
            return Color(red: 0.63, green: 0.69, blue: 0.78)
        }
    }

    static func scoreAccent(_ grade: ProductGrade) -> Color {
        switch grade {
        case .excellent:
            return Color(red: 0.37, green: 0.92, blue: 0.64)
        case .good:
            return Color(red: 0.58, green: 0.90, blue: 0.43)
        case .fair:
            return Color(red: 0.97, green: 0.82, blue: 0.35)
        case .poor:
            return Color(red: 0.99, green: 0.57, blue: 0.28)
        case .bad:
            return Color(red: 0.98, green: 0.35, blue: 0.31)
        case .unclear:
            return Color(red: 0.63, green: 0.69, blue: 0.78)
        }
    }

    static func categoryColor(_ category: IngredientCategory) -> Color {
        switch category {
        case .additive:
            return Color(red: 0.92, green: 0.73, blue: 0.31)
        case .preservative:
            return Color(red: 1.0, green: 0.59, blue: 0.29)
        case .sweetener:
            return Color(red: 0.47, green: 0.88, blue: 0.63)
        case .coloring:
            return Color(red: 1.0, green: 0.42, blue: 0.57)
        case .emulsifier:
            return Color(red: 0.41, green: 0.72, blue: 0.94)
        case .stabilizer:
            return Color(red: 0.34, green: 0.84, blue: 0.87)
        case .fragrance:
            return Color(red: 0.85, green: 0.58, blue: 0.94)
        case .solvent:
            return Color(red: 0.71, green: 0.75, blue: 0.83)
        case .surfactant:
            return Color(red: 0.44, green: 0.84, blue: 0.78)
        case .unknown:
            return Color(red: 0.54, green: 0.59, blue: 0.67)
        }
    }

    static func categoryIcon(_ category: IngredientCategory) -> String {
        switch category {
        case .additive:
            return "sparkles"
        case .preservative:
            return "shield.lefthalf.filled"
        case .sweetener:
            return "drop.fill"
        case .coloring:
            return "paintpalette.fill"
        case .emulsifier:
            return "circle.lefthalf.filled"
        case .stabilizer:
            return "waveform.path.ecg.rectangle"
        case .fragrance:
            return "leaf.fill"
        case .solvent:
            return "flask.fill"
        case .surfactant:
            return "bubbles.and.sparkles.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }
}

extension View {
    func decoderPanelStyle(cornerRadius: CGFloat = 28) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.panelFill)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.border)
            )
    }
}
