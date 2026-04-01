import SwiftUI

struct IngredientDetailView: View {
    let ingredient: IngredientAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RoundedRectangle(cornerRadius: 3)
                .fill(AppTheme.tertiaryText)
                .frame(width: 44, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            HStack(spacing: 12) {
                Circle()
                    .fill(AppTheme.categoryColor(ingredient.category))
                    .frame(width: 16, height: 16)

                Text(ingredient.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
            }

            HStack(spacing: 10) {
                DetailPill(text: ingredient.category.title, color: AppTheme.categoryColor(ingredient.category))
                DetailPill(text: ingredient.confidence.rawValue, color: .white.opacity(0.18))
            }

            VStack(alignment: .leading, spacing: 14) {
                Text(ingredient.detail.whatItIs)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                Text(ingredient.detail.purpose)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.background.ignoresSafeArea())
    }
}

private struct DetailPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.22), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.38)))
    }
}
