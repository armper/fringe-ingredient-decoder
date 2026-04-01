import SwiftUI

struct ResultView: View {
    let analysis: AnalyzedProduct
    @Binding var favorite: Bool
    let preferenceProfile: PreferenceProfile
    let onOpenAlternative: (AnalyzedProduct) -> Void
    let onDismiss: () -> Void

    @State private var selectedIngredient: IngredientAnalysis?
    @State private var alternatives: [AnalyzedProduct] = []
    @State private var loadingAlternatives = false

    private let lookupService = OpenFoodFactsService()
    private let analysisEngine = IngredientAnalysisEngine()

    var body: some View {
        ZStack(alignment: .top) {
            AppTheme.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    hero

                    if !analysis.alerts.isEmpty {
                        alertsSection
                    }

                    if !analysis.negatives.isEmpty || !analysis.positives.isEmpty {
                        breakdownSection
                    }

                    if shouldShowAlternatives {
                        alternativesSection
                    }

                    ingredientSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
        }
        .sheet(item: $selectedIngredient) { ingredient in
            IngredientDetailView(ingredient: ingredient)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
        }
        .task(id: analysis.id) {
            await loadAlternatives()
        }
    }

    private var header: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.elevatedFill, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            if let barcode = analysis.barcode {
                Text(barcode)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.elevatedFill, in: Capsule())
            }

            Button {
                favorite.toggle()
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(favorite ? AppTheme.summaryColor(.simple) : AppTheme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.elevatedFill, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 16) {
            productArtwork

            VStack(alignment: .leading, spacing: 12) {
                Text(analysis.domain.title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)

                Text(analysis.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(analysis.grade.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.scoreAccent(analysis.grade))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppTheme.scoreAccent(analysis.grade).opacity(0.16), in: Capsule())
                        .overlay(Capsule().strokeBorder(AppTheme.scoreAccent(analysis.grade).opacity(0.34)))

                    Text(analysis.summary.badge)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(analysis.subtitle)
                    Text(analysis.summary.note)
                }
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 0)

            ScoreBlock(score: analysis.score, grade: analysis.grade)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .decoderPanelStyle(cornerRadius: 32)
    }

    private var productArtwork: some View {
        Group {
            if let imageURL = analysis.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackArtwork
                    }
                }
            } else {
                fallbackArtwork
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(AppTheme.elevatedFill)
            .overlay(
                Image(systemName: analysis.domain == .beauty ? "sparkles.rectangle.stack.fill" : "barcode.viewfinder")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            )
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Alerts")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(analysis.alerts) { alert in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(alert.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)

                            Text(alert.note)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AppTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
        }
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !analysis.negatives.isEmpty {
                signalGroup(title: "Watch", items: analysis.negatives, accent: AppTheme.summaryColor(.processed))
            }

            if !analysis.positives.isEmpty {
                signalGroup(title: "Good", items: analysis.positives, accent: AppTheme.summaryColor(.simple))
            }
        }
    }

    private func signalGroup(title: String, items: [ProductSignal], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            VStack(spacing: 10) {
                ForEach(items) { item in
                    HStack(spacing: 14) {
                        Circle()
                            .fill(accent)
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)

                            Text(item.detail)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                        Spacer()

                        if let emphasis = item.emphasis {
                            Text(emphasis)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(AppTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(AppTheme.border)
                    )
                }
            }
        }
    }

    private var shouldShowAlternatives: Bool {
        analysis.domain != .custom && analysis.score < 70
    }

    private var alternativesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try These Instead")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            if loadingAlternatives && alternatives.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(AppTheme.primaryText)

                    Text("Looking for better public matches")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else if alternatives.isEmpty {
                Text("No stronger public matches came back yet.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(alternatives) { alternative in
                        Button {
                            onOpenAlternative(alternative)
                        } label: {
                            HStack(spacing: 14) {
                                Group {
                                    if let imageURL = alternative.imageURL, let url = URL(string: imageURL) {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                            default:
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .fill(AppTheme.elevatedFill)
                                            }
                                        }
                                    } else {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(AppTheme.elevatedFill)
                                    }
                                }
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(alternative.title)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AppTheme.primaryText)
                                        .lineLimit(2)

                                    Text(alternative.grade.title)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.secondaryText)
                                }

                                Spacer()

                                ScoreChip(score: alternative.score, grade: alternative.grade)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(AppTheme.border)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var ingredientSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if analysis.ingredients.isEmpty {
                Text("No ingredient list came through. A pasted label usually gives a better decode.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .decoderPanelStyle(cornerRadius: 28)
            } else {
                ForEach(analysis.ingredients) { ingredient in
                    Button {
                        selectedIngredient = ingredient
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.categoryColor(ingredient.category).opacity(0.18))
                                    .frame(width: 34, height: 34)

                                Image(systemName: AppTheme.categoryIcon(ingredient.category))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.categoryColor(ingredient.category))
                            }

                            Text(ingredient.name)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(AppTheme.tertiaryText)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(AppTheme.border)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadAlternatives() async {
        guard shouldShowAlternatives else {
            alternatives = []
            return
        }

        loadingAlternatives = true
        defer { loadingAlternatives = false }

        let query = searchQuery(from: analysis.title)
        guard !query.isEmpty else {
            alternatives = []
            return
        }

        let matches = await lookupService.search(query: query, domain: analysis.domain, limit: 16)
        let candidates = matches
            .filter { $0.barcode != analysis.barcode }
            .filter { !$0.ingredientsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map {
                analysisEngine.analyze(
                    title: $0.title,
                    ingredientsText: $0.ingredientsText,
                    source: .barcode,
                    domain: $0.domain,
                    barcode: $0.barcode,
                    imageURL: $0.imageURL,
                    preferences: preferenceProfile
                )
            }
            .filter { $0.favoriteKey != analysis.favoriteKey }
            .filter { $0.score >= analysis.score + 8 }
            .sorted {
                if $0.score == $1.score {
                    return $0.ingredients.count < $1.ingredients.count
                }
                return $0.score > $1.score
            }

        var seen = Set<String>()
        alternatives = candidates.filter { seen.insert($0.favoriteKey).inserted }.prefix(3).map { $0 }
    }

    private func searchQuery(from title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: #"[^A-Za-z0-9 ]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let words = cleaned
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 }

        return words.prefix(3).joined(separator: " ")
    }
}

private struct ScoreBlock: View {
    let score: Int
    let grade: ProductGrade

    var body: some View {
        VStack(spacing: 4) {
            Text("\(score)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.scoreAccent(grade))

            Text("/100")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            Text(grade.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
        }
        .frame(width: 92, height: 92)
        .background(AppTheme.scoreAccent(grade).opacity(0.14), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(AppTheme.scoreAccent(grade).opacity(0.28))
        )
    }
}
