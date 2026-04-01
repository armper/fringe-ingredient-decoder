import Foundation

struct IngredientAnalysisEngine {
    private let parser = IngredientParser()
    private let knowledgeBase = IngredientKnowledgeBase()

    func analyze(
        title: String,
        ingredientsText: String,
        source: AnalysisSource,
        domain: ProductDomain = .custom,
        barcode: String? = nil,
        imageURL: String? = nil,
        preferences: PreferenceProfile = .default,
        scoreInputs: ProductScoreInputs? = nil,
        id: UUID = UUID(),
        createdAt: Date = .now,
        resolvedIngredients: [String: ResolvedIngredient] = [:]
    ) -> AnalyzedProduct {
        let ingredientNames = parser.parse(ingredientsText)
        let ingredients = ingredientNames.map { knowledgeBase.describe($0, resolvedIngredients: resolvedIngredients) }
        let scorecard = makeScorecard(for: ingredients, domain: domain, scoreInputs: scoreInputs)
        let alerts = makeAlerts(for: ingredients, preferences: preferences)
        let summary = makeSummary(
            for: ingredients,
            grade: scorecard.grade,
            score: scorecard.score,
            domain: domain
        )

        return AnalyzedProduct(
            id: id,
            title: title,
            source: source,
            domain: domain,
            ingredientsText: ingredientsText,
            ingredients: ingredients,
            summary: summary,
            grade: scorecard.grade,
            score: scorecard.score,
            positives: scorecard.positives,
            negatives: scorecard.negatives,
            alerts: alerts,
            barcode: barcode,
            imageURL: imageURL,
            scoreInputs: scoreInputs,
            createdAt: createdAt
        )
    }

    func makeResolvedIngredient(
        originalName: String,
        originalNormalizedName: String,
        suggestedName: String,
        source: IngredientResolutionSource
    ) -> ResolvedIngredient? {
        let match = knowledgeBase.describe(suggestedName)
        guard match.confidence != .low else { return nil }

        return ResolvedIngredient(
            canonicalName: match.name,
            normalizedName: originalNormalizedName,
            category: match.category,
            confidence: match.confidence,
            whatItIs: match.detail.whatItIs,
            purpose: match.detail.purpose,
            source: source,
            updatedAt: .now
        )
    }

    func makeHeuristicResolvedIngredient(
        originalNormalizedName: String,
        suggestedName: String,
        source: IngredientResolutionSource
    ) -> ResolvedIngredient? {
        knowledgeBase.makeHeuristicResolvedIngredient(
            originalNormalizedName: originalNormalizedName,
            suggestedName: suggestedName,
            source: source
        )
    }

    func normalize(_ text: String) -> String {
        knowledgeBase.normalize(text)
    }

    func displayName(forNormalizedName normalizedName: String) -> String {
        knowledgeBase.displayName(forNormalizedName: normalizedName)
    }

    private func makeSummary(
        for ingredients: [IngredientAnalysis],
        grade: ProductGrade,
        score: Int,
        domain: ProductDomain
    ) -> ProductSummary {
        guard !ingredients.isEmpty else {
            return ProductSummary(
                badge: "Need More Data",
                note: "Paste a fuller list to decode more.",
                tone: .unclear
            )
        }

        switch grade {
        case .excellent:
            return ProductSummary(
                badge: "Mostly Simple",
                note: domain == .beauty ? "Short formula with fewer obvious watchouts." : "Short label with fewer obvious additives.",
                tone: .simple
            )
        case .good:
            return ProductSummary(
                badge: "Good Overall",
                note: domain == .beauty ? "Mostly straightforward ingredients with a few helpers." : "Mostly familiar ingredients with a lighter additive load.",
                tone: .simple
            )
        case .fair:
            return ProductSummary(
                badge: "Mixed Bag",
                note: "A blend of familiar ingredients and more processed helpers.",
                tone: .balanced
            )
        case .poor:
            return ProductSummary(
                badge: "Many Additives",
                note: "Several ingredients look engineered for flavor, texture, or shelf life.",
                tone: .additives
            )
        case .bad:
            return ProductSummary(
                badge: "Highly Processed",
                note: "This label stacks up multiple stronger processing signals.",
                tone: .processed
            )
        case .unclear:
            return ProductSummary(
                badge: "Hard To Decode",
                note: score < 30 ? "The label is sparse or hard to match cleanly." : "Some ingredients still need better label data.",
                tone: .unclear
            )
        }
    }

    private func makeScorecard(for ingredients: [IngredientAnalysis], domain: ProductDomain, scoreInputs: ProductScoreInputs?) -> Scorecard {
        guard !ingredients.isEmpty else {
            return Scorecard(
                score: 24,
                grade: .unclear,
                positives: [],
                negatives: [
                    ProductSignal(title: "Need a full label", detail: "The ingredient list is missing or too short to score well.", emphasis: nil)
                ]
            )
        }

        let additiveCategories: Set<IngredientCategory> = [
            .additive, .preservative, .sweetener, .coloring, .emulsifier, .stabilizer, .fragrance, .solvent, .surfactant
        ]
        let categoryCounts = Dictionary(grouping: ingredients, by: \.category).mapValues(\.count)
        let additiveCount = ingredients.filter { additiveCategories.contains($0.category) }.count
        let unknownCount = categoryCounts[.unknown, default: 0]
        let processedSignals = ingredients.filter {
            [.preservative, .sweetener, .coloring, .emulsifier, .stabilizer, .surfactant, .solvent, .fragrance].contains($0.category)
        }.count
        let lowConfidenceCount = ingredients.filter { $0.confidence == .low }.count

        var score = 100.0
        for (index, ingredient) in ingredients.enumerated() {
            score -= Double(weight(for: ingredient.category, domain: domain)) * positionWeight(for: index)
        }

        score -= Double(min(max(0, ingredients.count - 6) * 2, 18))
        score -= Double(min(lowConfidenceCount * 2, 8))

        if ingredients.count <= 6 {
            score += 10
        } else if ingredients.count <= 9 {
            score += 4
        }

        if additiveCount == 0 {
            score += 8
        } else if additiveCount == 1 {
            score += 4
        }

        if processedSignals == 0 {
            score += 6
        } else if processedSignals <= 2 {
            score += 2
        }

        if domain == .beauty && categoryCounts[.fragrance, default: 0] == 0 {
            score += 4
        }

        if unknownCount >= max(4, ingredients.count / 2) {
            score -= 6
        }

        if domain == .food, let scoreInputs, scoreInputs.hasSignals {
            let ingredientScore = Int(max(1, min(100, score.rounded())))
            score = Double(blendedFoodScore(
                ingredientScore: ingredientScore,
                parsedAdditiveCount: additiveCount,
                scoreInputs: scoreInputs
            ))
        }

        let finalScore = Int(max(1, min(100, score.rounded())))

        let grade: ProductGrade
        switch finalScore {
        case 85...:
            grade = .excellent
        case 70...84:
            grade = .good
        case 55...69:
            grade = .fair
        case 35...54:
            grade = .poor
        case 1...34:
            grade = .bad
        default:
            grade = .unclear
        }

        var positives: [ProductSignal] = []
        var negatives: [ProductSignal] = []
        var productLevelPositives: [ProductSignal] = []
        var productLevelNegatives: [ProductSignal] = []

        if ingredients.count <= 6 {
            positives.append(ProductSignal(title: "Short list", detail: "Only \(ingredients.count) ingredients show up.", emphasis: "\(ingredients.count)"))
        }

        if additiveCount <= 1 {
            positives.append(
                ProductSignal(
                    title: additiveCount == 0 ? "Few additives" : "Lighter additive load",
                    detail: additiveCount == 0 ? "No obvious functional additives were spotted." : "Only one obvious additive helper was spotted.",
                    emphasis: additiveCount == 0 ? "0" : "1"
                )
            )
        }

        if processedSignals <= 2 {
            positives.append(
                ProductSignal(
                    title: "Lower processing load",
                    detail: "Most ingredients look closer to the product's base ingredients.",
                    emphasis: nil
                )
            )
        }

        if domain == .beauty && categoryCounts[.fragrance, default: 0] == 0 {
            positives.append(
                ProductSignal(
                    title: "No fragrance spotted",
                    detail: "The label does not show an obvious fragrance blend.",
                    emphasis: nil
                )
            )
        }

        if additiveCount >= 3 {
            negatives.append(
                ProductSignal(
                    title: "Functional additives",
                    detail: "Multiple ingredients appear to support flavor, texture, or shelf life.",
                    emphasis: "\(additiveCount)"
                )
            )
        }

        if let count = categoryCounts[.sweetener], count > 0 {
            negatives.append(ProductSignal(title: "Sweeteners", detail: "Sweetener-style ingredients are present.", emphasis: "\(count)"))
        }

        if let count = categoryCounts[.coloring], count > 0 {
            negatives.append(ProductSignal(title: "Colorings", detail: "Color additives are listed on the label.", emphasis: "\(count)"))
        }

        if let count = categoryCounts[.preservative], count > 0 {
            negatives.append(ProductSignal(title: "Preservatives", detail: "Shelf-life helpers are present.", emphasis: "\(count)"))
        }

        if let count = categoryCounts[.fragrance], count > 0 {
            negatives.append(ProductSignal(title: "Fragrance", detail: "A grouped scent blend appears in the formula.", emphasis: "\(count)"))
        }

        if let count = categoryCounts[.surfactant], count > 1 {
            negatives.append(ProductSignal(title: "Cleansing agents", detail: "Several surfactant ingredients show up.", emphasis: "\(count)"))
        }

        if unknownCount >= max(3, ingredients.count / 2) {
            negatives.append(ProductSignal(title: "Harder to decode", detail: "Many names are still hard to match confidently.", emphasis: "\(unknownCount)"))
        }

        if ingredients.count >= 12 {
            negatives.append(ProductSignal(title: "Longer list", detail: "A longer label can point to a more engineered formula.", emphasis: "\(ingredients.count)"))
        }

        if domain == .food, let scoreInputs {
            if let nutritionGrade = scoreInputs.nutritionGrade?.uppercased() {
                if ["A", "B"].contains(nutritionGrade) {
                    productLevelPositives.append(
                        ProductSignal(
                            title: "Nutrition profile",
                            detail: "Open Food Facts nutrition grade lands on the stronger side.",
                            emphasis: nutritionGrade
                        )
                    )
                } else if ["D", "E"].contains(nutritionGrade) {
                    productLevelNegatives.append(
                        ProductSignal(
                            title: "Nutrition profile",
                            detail: "Open Food Facts nutrition grade lands on the weaker side.",
                            emphasis: nutritionGrade
                        )
                    )
                }
            }

            if let novaGroup = scoreInputs.novaGroup {
                if novaGroup <= 2 {
                    productLevelPositives.append(
                        ProductSignal(
                            title: "Less processed",
                            detail: "Open Food Facts processing group is closer to minimally processed.",
                            emphasis: "NOVA \(novaGroup)"
                        )
                    )
                } else if novaGroup >= 4 {
                    productLevelNegatives.append(
                        ProductSignal(
                            title: "Ultra-processed signals",
                            detail: "Open Food Facts flags this product in the highest processing group.",
                            emphasis: "NOVA \(novaGroup)"
                        )
                    )
                }
            }

            if let remoteAdditives = scoreInputs.additiveCount, remoteAdditives >= 4 {
                productLevelNegatives.append(
                    ProductSignal(
                        title: "Database additives",
                        detail: "Open Food Facts lists several additives for this product.",
                        emphasis: "\(remoteAdditives)"
                    )
                )
            }
        }

        positives = productLevelPositives + positives
        negatives = productLevelNegatives + negatives

        return Scorecard(
            score: finalScore,
            grade: grade,
            positives: Array(positives.prefix(3)),
            negatives: Array(negatives.prefix(4))
        )
    }

    private func positionWeight(for index: Int) -> Double {
        switch index {
        case 0...2:
            return 1.35
        case 3...6:
            return 1.0
        default:
            return 0.72
        }
    }

    private func blendedFoodScore(ingredientScore: Int, parsedAdditiveCount: Int, scoreInputs: ProductScoreInputs) -> Int {
        let nutritionScore = scoreInputs.nutritionGrade.flatMap(foodNutritionScore(for:))
        let processingScore = foodProcessingAdditiveScore(
            novaGroup: scoreInputs.novaGroup,
            additiveCount: scoreInputs.additiveCount ?? parsedAdditiveCount
        )

        let blended: Double
        switch (nutritionScore, processingScore) {
        case let (.some(nutritionScore), .some(processingScore)):
            blended =
                (Double(nutritionScore) * 0.45) +
                (Double(processingScore) * 0.25) +
                (Double(ingredientScore) * 0.30)
        case let (.some(nutritionScore), .none):
            blended =
                (Double(nutritionScore) * 0.55) +
                (Double(ingredientScore) * 0.45)
        case let (.none, .some(processingScore)):
            blended =
                (Double(processingScore) * 0.40) +
                (Double(ingredientScore) * 0.60)
        case (.none, .none):
            blended = Double(ingredientScore)
        }

        return Int(max(1, min(100, blended.rounded())))
    }

    private func foodNutritionScore(for grade: String) -> Int? {
        switch grade.lowercased() {
        case "a":
            return 96
        case "b":
            return 82
        case "c":
            return 64
        case "d":
            return 41
        case "e":
            return 18
        default:
            return nil
        }
    }

    private func foodProcessingScore(for novaGroup: Int) -> Int {
        switch novaGroup {
        case 1:
            return 94
        case 2:
            return 78
        case 3:
            return 52
        case 4:
            return 22
        default:
            return 50
        }
    }

    private func foodProcessingAdditiveScore(novaGroup: Int?, additiveCount: Int?) -> Int? {
        guard novaGroup != nil || additiveCount != nil else { return nil }

        var score = novaGroup.map(foodProcessingScore(for:)) ?? 66

        if let additiveCount {
            switch additiveCount {
            case ...0:
                score += 10
            case 1:
                score += 4
            case 2:
                break
            case 3:
                score -= 6
            case 4...5:
                score -= 12
            default:
                score -= 18
            }
        }

        if let novaGroup, novaGroup >= 4, (additiveCount ?? 0) >= 4 {
            score -= 8
        }

        return max(1, min(100, score))
    }

    private func makeAlerts(for ingredients: [IngredientAnalysis], preferences: PreferenceProfile) -> [PreferenceAlert] {
        guard !preferences.enabledKeys.isEmpty else { return [] }

        let rules: [(PreferenceKey, [String])] = [
            (.gluten, ["wheat", "barley", "rye", "malt", "semolina", "durum", "spelt", "triticale", "farro"]),
            (.lactose, ["milk", "whey", "lactose", "casein", "cream", "butter", "cheese", "yogurt"]),
            (.palmOil, ["palm oil", "palm kernel", "palmolein", "palmitate"]),
            (.animalDerived, ["gelatin", "collagen", "carmine", "shellac", "lanolin", "fish oil", "anchovy", "chicken fat", "beef fat", "tallow", "beeswax", "honey"]),
            (.fragrance, ["fragrance", "parfum", "perfume"])
        ]

        return rules.compactMap { key, keywords in
            guard preferences.isEnabled(key) else { return nil }

            let matches = ingredients.compactMap { ingredient in
                if keywords.contains(where: ingredient.normalizedName.contains) {
                    return ingredient.name
                }
                if key == .fragrance, ingredient.category == .fragrance {
                    return ingredient.name
                }
                return nil
            }

            let uniqueMatches = Array(NSOrderedSet(array: matches)) as? [String] ?? matches
            guard !uniqueMatches.isEmpty else { return nil }
            return PreferenceAlert(key: key, matches: uniqueMatches)
        }
    }

    private func weight(for category: IngredientCategory, domain: ProductDomain) -> Int {
        switch (domain, category) {
        case (_, .unknown):
            return 2
        case (.beauty, .fragrance):
            return 15
        case (.beauty, .surfactant):
            return 10
        case (.beauty, .solvent):
            return 9
        case (.beauty, .preservative):
            return 8
        case (.beauty, .coloring):
            return 6
        case (.beauty, .sweetener):
            return 5
        case (.beauty, .additive):
            return 5
        case (.beauty, .emulsifier):
            return 6
        case (.beauty, .stabilizer):
            return 5
        case (_, .additive):
            return 6
        case (_, .preservative):
            return 9
        case (_, .sweetener):
            return 12
        case (_, .coloring):
            return 14
        case (_, .emulsifier):
            return 7
        case (_, .stabilizer):
            return 6
        case (_, .fragrance):
            return 16
        case (_, .solvent):
            return 8
        case (_, .surfactant):
            return 10
        }
    }
}

private struct Scorecard {
    let score: Int
    let grade: ProductGrade
    let positives: [ProductSignal]
    let negatives: [ProductSignal]
}

private struct IngredientParser {
    func parse(_ raw: String) -> [String] {
        let cleaned = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "Ingredients:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Contains:", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return [] }

        var seen = Set<String>()
        var output: [String] = []

        func appendUnique(_ token: String) {
            let trimmed = token
                .replacingOccurrences(of: #"(?i)\bless than \d+% of\b"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)\bcontains one or more of the following\b"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\b\d+(\.\d+)?%\b"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " .:"))

            guard trimmed.count > 1 else { return }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return }
            output.append(trimmed)
        }

        func collect(from segment: String) {
            let topLevel = split(segment)
            for part in topLevel {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                if let openIndex = trimmed.firstIndex(of: "("), trimmed.last == ")" {
                    let base = String(trimmed[..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                    appendUnique(base)

                    let innerStart = trimmed.index(after: openIndex)
                    let inner = String(trimmed[innerStart ..< trimmed.index(before: trimmed.endIndex)])
                    collect(from: inner)
                } else {
                    appendUnique(trimmed)
                }
            }
        }

        collect(from: cleaned)
        return output
    }

    private func split(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0

        for character in text {
            switch character {
            case "(", "[":
                depth += 1
                current.append(character)
            case ")", "]":
                depth = max(0, depth - 1)
                current.append(character)
            case ",", ";":
                if depth == 0 {
                    parts.append(current)
                    current = ""
                } else {
                    current.append(character)
                }
            default:
                current.append(character)
            }
        }

        if !current.isEmpty {
            parts.append(current)
        }

        return parts
    }
}

private struct IngredientKnowledgeBase {
    private struct Entry {
        let category: IngredientCategory
        let detail: IngredientDetail
    }

    private struct SearchCandidate {
        let searchKey: String
        let canonicalKey: String
    }

    private struct CatalogFile: Decodable {
        struct CatalogEntry: Decodable {
            let category: IngredientCategory
            let whatItIs: String
            let purpose: String
        }

        let aliases: [String: String]
        let entries: [String: CatalogEntry]
    }

    private final class BundleMarker {}

    private static let generatedCatalog = loadGeneratedCatalog()
    private static let mergedAliases = generatedCatalog.aliases.merging(manualAliases) { _, manual in manual }
    private static let mergedEntries = generatedCatalog.entries.merging(manualEntries) { _, manual in manual }

    private let aliases = Self.mergedAliases

    private let entries = Self.mergedEntries

    private let tokenIndex = Self.makeTokenIndex()

    private static func makeTokenIndex() -> [String: [SearchCandidate]] {
        var index: [String: [SearchCandidate]] = [:]
        let candidates = manualEntries.keys.map { SearchCandidate(searchKey: $0, canonicalKey: $0) } +
            Self.generatedCatalog.entries.keys.map { SearchCandidate(searchKey: $0, canonicalKey: $0) } +
            mergedAliases.map { SearchCandidate(searchKey: $0.key, canonicalKey: $0.value) }

        var seen = Set<String>()
        for candidate in candidates {
            let dedupeKey = "\(candidate.searchKey)|\(candidate.canonicalKey)"
            guard seen.insert(dedupeKey).inserted else { continue }

            for token in significantTokens(in: candidate.searchKey) where token.count >= 3 {
                index[token, default: []].append(candidate)
            }
        }

        return index
    }

    private static let manualAliases: [String: String] = [
        "parfum": "fragrance",
        "natural flavour": "natural flavors",
        "natural flavourings": "natural flavors",
        "artificial flavour": "artificial flavors",
        "artificial flavourings": "artificial flavors",
        "sls": "sodium lauryl sulfate",
        "sles": "sodium laureth sulfate",
        "msg": "monosodium glutamate",
        "monoglycerides": "mono and diglycerides of fatty acids",
        "diglycerides": "mono and diglycerides of fatty acids",
        "mixed tocopherols": "tocopherol",
        "tocopherols": "tocopherol",
        "fd and c red no 40": "red 40",
        "fd and c red 40": "red 40",
        "red #40": "red 40",
        "red color 40": "red 40",
        "red no 40": "red 40",
        "fd and c yellow no 5": "yellow 5",
        "fd and c yellow 5": "yellow 5",
        "yellow #5": "yellow 5",
        "yellow color 5": "yellow 5",
        "yellow no 5": "yellow 5",
        "fd and c yellow no 6": "yellow 6",
        "fd and c yellow 6": "yellow 6",
        "yellow #6": "yellow 6",
        "yellow color 6": "yellow 6",
        "yellow no 6": "yellow 6",
        "fd and c blue no 1": "blue 1",
        "fd and c blue 1": "blue 1",
        "blue #1": "blue 1",
        "blue color 1": "blue 1",
        "blue no 1": "blue 1"
    ]

    private static let manualEntries: [String: Entry] = [
        "water": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "A base ingredient used to dissolve or carry other ingredients.", purpose: "It usually acts as the main liquid in the formula.")),
        "sugar": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "A familiar sweetener.", purpose: "It adds sweetness and sometimes texture.")),
        "salt": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "A common mineral ingredient.", purpose: "It adds flavor and can help with preservation.")),
        "niacin": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "A vitamin also known as vitamin B3.", purpose: "It can be added as a nutrient or enrichment ingredient.")),
        "citric acid": Entry(category: .additive, detail: IngredientDetail(whatItIs: "An acid found naturally in citrus and also made for food production.", purpose: "It adjusts tartness and helps keep flavor stable.")),
        "natural flavors": Entry(category: .additive, detail: IngredientDetail(whatItIs: "A flavor blend sourced from natural raw materials.", purpose: "It boosts taste or aroma without listing each component.")),
        "artificial flavors": Entry(category: .additive, detail: IngredientDetail(whatItIs: "A lab-created flavor blend.", purpose: "It gives a product a specific taste profile.")),
        "monosodium glutamate": Entry(category: .additive, detail: IngredientDetail(whatItIs: "A flavor enhancer also known as MSG.", purpose: "It intensifies savory taste.")),
        "sodium benzoate": Entry(category: .preservative, detail: IngredientDetail(whatItIs: "A common preservative.", purpose: "It helps keep products shelf-stable for longer.")),
        "potassium sorbate": Entry(category: .preservative, detail: IngredientDetail(whatItIs: "A common preservative.", purpose: "It helps slow mold and yeast growth.")),
        "calcium propionate": Entry(category: .preservative, detail: IngredientDetail(whatItIs: "A preservative often used in baked goods.", purpose: "It helps products last longer without visible spoilage.")),
        "phenoxyethanol": Entry(category: .preservative, detail: IngredientDetail(whatItIs: "A preservative used in many beauty products.", purpose: "It helps stop microbial growth in the formula.")),
        "bht": Entry(category: .preservative, detail: IngredientDetail(whatItIs: "A synthetic preservative and antioxidant.", purpose: "It helps keep oils from breaking down.")),
        "sucralose": Entry(category: .sweetener, detail: IngredientDetail(whatItIs: "A high-intensity sweetener.", purpose: "It adds sweetness with very little volume.")),
        "aspartame": Entry(category: .sweetener, detail: IngredientDetail(whatItIs: "A high-intensity sweetener.", purpose: "It adds sweetness in small amounts.")),
        "acesulfame potassium": Entry(category: .sweetener, detail: IngredientDetail(whatItIs: "A high-intensity sweetener also called Ace-K.", purpose: "It is often paired with other sweeteners.")),
        "stevia": Entry(category: .sweetener, detail: IngredientDetail(whatItIs: "A plant-derived sweetener.", purpose: "It adds sweetness without much bulk.")),
        "corn syrup": Entry(category: .sweetener, detail: IngredientDetail(whatItIs: "A syrup sweetener made from corn starch.", purpose: "It adds sweetness and body.")),
        "caramel color": Entry(category: .coloring, detail: IngredientDetail(whatItIs: "A color additive made from heated sugars.", purpose: "It darkens foods and drinks.")),
        "red 40": Entry(category: .coloring, detail: IngredientDetail(whatItIs: "A synthetic color additive.", purpose: "It creates bright red or orange tones.")),
        "yellow 5": Entry(category: .coloring, detail: IngredientDetail(whatItIs: "A synthetic yellow color additive.", purpose: "It brightens the product's appearance.")),
        "yellow 6": Entry(category: .coloring, detail: IngredientDetail(whatItIs: "A synthetic orange-yellow color additive.", purpose: "It shifts the product toward a warmer color.")),
        "blue 1": Entry(category: .coloring, detail: IngredientDetail(whatItIs: "A synthetic blue color additive.", purpose: "It changes or balances the final color.")),
        "soy lecithin": Entry(category: .emulsifier, detail: IngredientDetail(whatItIs: "An emulsifier often sourced from soy.", purpose: "It helps ingredients stay mixed instead of separating.")),
        "sunflower lecithin": Entry(category: .emulsifier, detail: IngredientDetail(whatItIs: "An emulsifier sourced from sunflower.", purpose: "It helps ingredients stay mixed instead of separating.")),
        "lecithin": Entry(category: .emulsifier, detail: IngredientDetail(whatItIs: "An emulsifier from plant or egg sources.", purpose: "It helps oil and water stay blended.")),
        "mono and diglycerides": Entry(category: .emulsifier, detail: IngredientDetail(whatItIs: "Fat-derived emulsifiers.", purpose: "They improve texture and keep ingredients evenly mixed.")),
        "peg-30 stearate": Entry(category: .emulsifier, detail: IngredientDetail(whatItIs: "A PEG-based emulsifier.", purpose: "It helps oil and water stay blended in the formula.")),
        "ceteareth-20": Entry(category: .emulsifier, detail: IngredientDetail(whatItIs: "An emulsifier used in personal care products.", purpose: "It helps the formula stay smooth and uniform.")),
        "xanthan gum": Entry(category: .stabilizer, detail: IngredientDetail(whatItIs: "A thickening and stabilizing gum.", purpose: "It helps products stay smooth and evenly textured.")),
        "guar gum": Entry(category: .stabilizer, detail: IngredientDetail(whatItIs: "A plant-based thickener.", purpose: "It adds body and helps suspend ingredients.")),
        "carrageenan": Entry(category: .stabilizer, detail: IngredientDetail(whatItIs: "A seaweed-derived thickener.", purpose: "It improves texture and keeps products uniform.")),
        "cellulose gum": Entry(category: .stabilizer, detail: IngredientDetail(whatItIs: "A cellulose-based thickener.", purpose: "It keeps texture consistent.")),
        "dimethicone": Entry(category: .stabilizer, detail: IngredientDetail(whatItIs: "A silicone used in beauty formulas.", purpose: "It smooths texture and helps products glide on.")),
        "fragrance": Entry(category: .fragrance, detail: IngredientDetail(whatItIs: "A grouped scent blend.", purpose: "It gives the product a particular smell.")),
        "propylene glycol": Entry(category: .solvent, detail: IngredientDetail(whatItIs: "A liquid carrier used in many formulas.", purpose: "It helps dissolve and distribute other ingredients.")),
        "ethanol": Entry(category: .solvent, detail: IngredientDetail(whatItIs: "Alcohol used as a carrier or solvent.", purpose: "It helps other ingredients spread or evaporate quickly.")),
        "isododecane": Entry(category: .solvent, detail: IngredientDetail(whatItIs: "A lightweight solvent used in beauty products.", purpose: "It helps the formula spread evenly and dry down.")),
        "sodium laureth sulfate": Entry(category: .surfactant, detail: IngredientDetail(whatItIs: "A cleansing surfactant.", purpose: "It helps water lift oil and debris.")),
        "sodium lauryl sulfate": Entry(category: .surfactant, detail: IngredientDetail(whatItIs: "A strong cleansing surfactant.", purpose: "It helps create foam and wash away oil.")),
        "cocamidopropyl betaine": Entry(category: .surfactant, detail: IngredientDetail(whatItIs: "A milder surfactant often paired with stronger cleansers.", purpose: "It boosts foam and makes formulas feel gentler.")),
        "glycerin": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "A common humectant.", purpose: "It helps hold onto moisture.")),
        "vaseline": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "A petroleum jelly ingredient.", purpose: "It helps seal in moisture and soften the feel of the product.")),
        "enriched flour": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "Refined flour with vitamins or minerals added back.", purpose: "It acts as the main grain base.")),
        "whole wheat flour": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "A whole grain flour ingredient.", purpose: "It acts as a grain base and adds structure.")),
        "wheat flour": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "A grain flour ingredient.", purpose: "It forms the main body of the product.")),
        "palm oil": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "A vegetable oil commonly used in packaged foods.", purpose: "It adds richness and shelf stability.")),
        "whey": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "A milk-derived ingredient.", purpose: "It can add protein, flavor, or dairy solids.")),
        "casein": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "A milk-derived protein.", purpose: "It adds protein and structure.")),
        "lactose": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "A milk sugar.", purpose: "It adds dairy-derived sweetness and solids.")),
        "gelatin": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "An animal-derived gelling ingredient.", purpose: "It helps products set and hold shape.")),
        "honey": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "A bee-derived sweet ingredient.", purpose: "It adds sweetness and flavor.")),
        "beeswax": Entry(category: .unknown, detail: IngredientDetail(whatItIs: "A wax made by bees.", purpose: "It thickens formulas and creates structure.")),
        "mixed tocopherols": Entry(category: .preservative, detail: IngredientDetail(whatItIs: "Vitamin E compounds used in packaged foods.", purpose: "They help slow oxidation and keep the product fresher.")),
        "tocopherol": Entry(category: .preservative, detail: IngredientDetail(whatItIs: "A vitamin E compound used in formulas.", purpose: "It helps slow oxidation and keep oils stable."))
    ]

    private static func loadGeneratedCatalog() -> (aliases: [String: String], entries: [String: Entry]) {
        let bundles = [Bundle.main, Bundle(for: BundleMarker.self)] + Bundle.allBundles + Bundle.allFrameworks
        let catalogURL = bundles
            .compactMap { $0.url(forResource: "IngredientCatalog", withExtension: "json") }
            .first

        guard
            let catalogURL,
            let data = try? Data(contentsOf: catalogURL),
            let decoded = try? JSONDecoder().decode(CatalogFile.self, from: data)
        else {
            return ([:], [:])
        }

        let generatedEntries = decoded.entries.reduce(into: [String: Entry]()) { partialResult, item in
            partialResult[item.key] = Entry(
                category: item.value.category,
                detail: IngredientDetail(
                    whatItIs: item.value.whatItIs,
                    purpose: item.value.purpose
                )
            )
        }

        return (decoded.aliases, generatedEntries)
    }

    func describe(_ rawName: String, resolvedIngredients: [String: ResolvedIngredient] = [:]) -> IngredientAnalysis {
        let normalized = normalize(rawName)

        if let entry = entries[normalized] {
            return IngredientAnalysis(
                name: displayName(from: rawName),
                normalizedName: normalized,
                category: entry.category,
                confidence: .high,
                detail: entry.detail
            )
        }

        if let canonical = aliases[normalized], let entry = entries[canonical] {
            return IngredientAnalysis(
                name: displayName(from: rawName),
                normalizedName: canonical,
                category: entry.category,
                confidence: .high,
                detail: entry.detail
            )
        }

        for variant in normalizedVariants(for: normalized) {
            if let entry = entries[variant] {
                return IngredientAnalysis(
                    name: displayName(from: rawName),
                    normalizedName: variant,
                    category: entry.category,
                    confidence: .high,
                    detail: entry.detail
                )
            }

            if let canonical = aliases[variant], let entry = entries[canonical] {
                return IngredientAnalysis(
                    name: displayName(from: rawName),
                    normalizedName: canonical,
                    category: entry.category,
                    confidence: .high,
                    detail: entry.detail
                )
            }
        }

        if let resolved = resolvedIngredients[normalized] {
            return IngredientAnalysis(
                name: resolved.canonicalName,
                normalizedName: normalized,
                category: resolved.category,
                confidence: resolved.confidence,
                detail: resolved.detail
            )
        }

        if let fuzzyMatch = fuzzyMatch(for: normalized) {
            return IngredientAnalysis(
                name: displayName(from: rawName),
                normalizedName: fuzzyMatch.canonicalKey,
                category: fuzzyMatch.entry.category,
                confidence: fuzzyMatch.confidence,
                detail: fuzzyMatch.entry.detail
            )
        }

        if normalized.range(of: #"^e ?\d{3}[a-z]?$"#, options: .regularExpression) != nil {
            return IngredientAnalysis(
                name: displayName(from: rawName),
                normalizedName: normalized,
                category: .additive,
                confidence: .medium,
                detail: IngredientDetail(
                    whatItIs: "An additive code used on ingredient labels.",
                    purpose: "It points to a standardized ingredient, often for color, preservation, or texture."
                )
            )
        }

        let inferred = inferEntry(for: normalized)
        return IngredientAnalysis(
            name: displayName(from: rawName),
            normalizedName: normalized,
            category: inferred.category,
            confidence: inferred.confidence,
            detail: inferred.detail
        )
    }

    private func inferEntry(for normalized: String) -> (category: IngredientCategory, confidence: IngredientConfidence, detail: IngredientDetail) {
        let keywordRules: [(IngredientCategory, [String], IngredientDetail)] = [
            (.preservative, ["benzoate", "sorbate", "nitrite", "nitrate", "propionate", "phenoxyethanol", "tocopherol", "paraben", "dehydroacetic"], IngredientDetail(whatItIs: "A preservative-style ingredient.", purpose: "It likely helps the product last longer on the shelf.")),
            (.sweetener, ["sucralose", "aspartame", "saccharin", "stevia", "syrup"], IngredientDetail(whatItIs: "A sweetener-style ingredient.", purpose: "It likely increases sweetness or rounds out flavor.")),
            (.coloring, ["color", "red ", "yellow ", "blue ", "green ", "orange ", "lake", "ci "], IngredientDetail(whatItIs: "A color additive.", purpose: "It changes or standardizes the product's appearance.")),
            (.emulsifier, ["lecithin", "diglyceride", "polysorbate", "peg-", "ceteareth", "polyglyceryl", "sorbitan"], IngredientDetail(whatItIs: "An emulsifier.", purpose: "It helps ingredients stay evenly mixed.")),
            (.stabilizer, ["gum", "carrageenan", "cellulose", "dimethicone", "copolymer", "crosspolymer", "carbomer", "acrylates", "polymer"], IngredientDetail(whatItIs: "A stabilizer or texture-building ingredient.", purpose: "It helps control texture, suspension, or film formation.")),
            (.fragrance, ["fragrance", "parfum", "perfume"], IngredientDetail(whatItIs: "A scent blend.", purpose: "It shapes the smell of the product.")),
            (.solvent, ["glycol", "alcohol", "isododecane", "hexanediol"], IngredientDetail(whatItIs: "A carrier or solvent.", purpose: "It helps dissolve or spread other ingredients.")),
            (.surfactant, ["sulfate", "betaine", "glucoside", "sarcosinate", "isethionate", "taurate"], IngredientDetail(whatItIs: "A surfactant.", purpose: "It helps water mix with oils and lift residue.")),
            (.additive, ["flavor", "flavour", "acid", "extract"], IngredientDetail(whatItIs: "A functional additive.", purpose: "It likely supports taste, tartness, or stability."))
        ]

        for (category, keywords, detail) in keywordRules {
            if keywords.contains(where: normalized.contains) {
                return (category, .medium, detail)
            }
        }

        return (
            .unknown,
            .low,
            IngredientDetail(
                whatItIs: "An ingredient without a clear local match.",
                purpose: "It may be a base ingredient, a brand-specific term, or a grouped label."
            )
        )
    }

    private func normalizedVariants(for normalized: String) -> [String] {
        var variants: [String] = []

        func append(_ value: String) {
            let cleaned = normalize(value)
            guard !cleaned.isEmpty, cleaned != normalized, !variants.contains(cleaned) else { return }
            variants.append(cleaned)
        }

        append(normalized.replacingOccurrences(of: " colour ", with: " color "))
        append(normalized.replacingOccurrences(of: " flavourings", with: " flavors"))
        append(normalized.replacingOccurrences(of: " flavouring", with: " flavor"))
        append(normalized.replacingOccurrences(of: " flavour ", with: " flavor "))
        append(normalized.replacingOccurrences(of: " colour ", with: " "))
        append(normalized.replacingOccurrences(of: " color ", with: " "))

        if normalized.hasPrefix("mixed ") {
            append(String(normalized.dropFirst("mixed ".count)))
        }

        if normalized.hasSuffix("s"), normalized.count > 5 {
            append(String(normalized.dropLast()))
        }

        if normalized == "monoglycerides" || normalized == "diglycerides" {
            append("mono and diglycerides of fatty acids")
        }

        if normalized == "tocopherols" {
            append("tocopherol")
        }

        let colorPatterns = [
            (#"fd and c (red|yellow|blue|green) no ?(\d+)"#, "$1 $2"),
            (#"(red|yellow|blue|green|orange) color ?(\d+)"#, "$1 $2"),
            (#"(red|yellow|blue|green|orange) no ?(\d+)"#, "$1 $2"),
            (#"(red|yellow|blue|green|orange) # ?(\d+)"#, "$1 $2"),
        ]

        for (pattern, template) in colorPatterns {
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            let regex = try? NSRegularExpression(pattern: pattern)
            let replaced = regex?.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: template)
            if let replaced {
                append(replaced)
            }
        }

        return variants
    }

    private func fuzzyMatch(for normalized: String) -> (canonicalKey: String, entry: Entry, confidence: IngredientConfidence)? {
        let tokens = significantTokens(in: normalized)
        guard !tokens.isEmpty else { return nil }

        var candidatesByKey: [String: SearchCandidate] = [:]
        let sortedTokens = tokens.sorted { lhs, rhs in
            let lhsCount = tokenIndex[lhs]?.count ?? .max
            let rhsCount = tokenIndex[rhs]?.count ?? .max
            if lhsCount == rhsCount {
                return lhs.count > rhs.count
            }
            return lhsCount < rhsCount
        }

        for token in sortedTokens.prefix(4) {
            for candidate in tokenIndex[token, default: []] {
                candidatesByKey["\(candidate.searchKey)|\(candidate.canonicalKey)"] = candidate
                if candidatesByKey.count >= 220 {
                    break
                }
            }
            if candidatesByKey.count >= 220 {
                break
            }
        }

        var best: (candidate: SearchCandidate, score: Double)?
        for candidate in candidatesByKey.values {
            guard let entry = entries[candidate.canonicalKey] else { continue }
            var score = similarityScore(lhs: normalized, rhs: candidate.searchKey)

            if entry.category != .unknown {
                score += 0.04
            }

            if best == nil || score > best!.score {
                best = (candidate, score)
            }
        }

        guard let best, let entry = entries[best.candidate.canonicalKey] else { return nil }
        guard best.score >= 0.74 else { return nil }

        let confidence: IngredientConfidence = best.score >= 0.9 ? .high : .medium
        return (best.candidate.canonicalKey, entry, confidence)
    }

    private func similarityScore(lhs: String, rhs: String) -> Double {
        if lhs == rhs {
            return 1
        }

        let lhsTokens = Set(significantTokens(in: lhs))
        let rhsTokens = Set(significantTokens(in: rhs))
        let tokenDenominator = Double(Swift.max(Swift.max(lhsTokens.count, rhsTokens.count), 1))
        let overlap = Double(lhsTokens.intersection(rhsTokens).count) / tokenDenominator

        var score = overlap * 0.68
        score += diceCoefficient(lhs, rhs) * 0.28

        if lhs.contains(rhs) || rhs.contains(lhs) {
            score += 0.08
        }

        if !lhsTokens.isEmpty, lhsTokens.isSubset(of: rhsTokens) || rhsTokens.isSubset(of: lhsTokens) {
            score += 0.08
        }

        let lhsDigits = lhs.filter(\.isNumber)
        let rhsDigits = rhs.filter(\.isNumber)
        if !lhsDigits.isEmpty && lhsDigits == rhsDigits {
            score += 0.08
        } else if lhsDigits != rhsDigits {
            score -= 0.06
        }

        return score
    }

    func normalize(_ text: String) -> String {
        var normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        normalized = normalized.replacingOccurrences(of: "&", with: " and ")
        normalized = normalized.replacingOccurrences(of: #"[\*\.\u{00AE}\u{2122}]"#, with: " ", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: "#", with: " ")
        normalized = normalized.replacingOccurrences(of: #"(?i)\bno\.?\b"#, with: " ", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?i)\bnos\.?\b"#, with: " ", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?i)\bnumber\b"#, with: " ", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?i)\bfd\s*and\s*c\b"#, with: " ", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?i)\bfd\s*&\s*c\b"#, with: " ", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?i)\borganic\b"#, with: "", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(?i)\band/or\b"#, with: " ", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"\s*/\s*"#, with: "/", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"\s*-\s*"#, with: "-", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"[^a-z0-9/\+\- ]+"#, with: " ", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: " -/"))
    }

    func makeHeuristicResolvedIngredient(
        originalNormalizedName: String,
        suggestedName: String,
        source: IngredientResolutionSource
    ) -> ResolvedIngredient? {
        let normalizedSuggestion = normalize(suggestedName)
        guard !normalizedSuggestion.isEmpty else { return nil }

        let inferred = inferEntry(for: normalizedSuggestion)
        guard inferred.category != .unknown || normalizedSuggestion != originalNormalizedName else { return nil }

        let confidence: IngredientConfidence = inferred.category == .unknown ? .low : .medium
        let detail = inferred.category == .unknown
            ? IngredientDetail(
                whatItIs: "A standardized ingredient name matched from a public ingredient taxonomy.",
                purpose: "Local classification is still limited, but this name is more specific than the original label match."
            )
            : inferred.detail

        return ResolvedIngredient(
            canonicalName: displayName(forNormalizedName: normalizedSuggestion),
            normalizedName: originalNormalizedName,
            category: inferred.category,
            confidence: confidence,
            whatItIs: detail.whatItIs,
            purpose: detail.purpose,
            source: source,
            updatedAt: .now
        )
    }

    func displayName(forNormalizedName normalizedName: String) -> String {
        normalizedName
            .split(separator: " ")
            .map { word in
                let original = String(word)
                let lettersOnly = original.replacingOccurrences(of: #"[^A-Za-z]+"#, with: "", options: .regularExpression)
                if !lettersOnly.isEmpty, lettersOnly.count <= 3, lettersOnly == lettersOnly.uppercased() {
                    return original.uppercased()
                }
                let lower = original.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    private func displayName(from raw: String) -> String {
        raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
            ? raw
            : displayName(forNormalizedName: normalize(raw))
    }

    private static func significantTokens(in normalized: String) -> [String] {
        let stopWords: Set<String> = ["and", "or", "of", "the", "with", "from", "to", "for", "no"]
        return normalized
            .split(whereSeparator: { $0 == " " || $0 == "/" || $0 == "-" || $0 == "+" })
            .map(String.init)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
    }

    private func significantTokens(in normalized: String) -> [String] {
        Self.significantTokens(in: normalized)
    }

    private func diceCoefficient(_ lhs: String, _ rhs: String) -> Double {
        let lhsBigrams = bigrams(for: lhs)
        let rhsBigrams = bigrams(for: rhs)

        guard !lhsBigrams.isEmpty, !rhsBigrams.isEmpty else { return 0 }

        let overlap = lhsBigrams.intersection(rhsBigrams).count
        return (2 * Double(overlap)) / Double(lhsBigrams.count + rhsBigrams.count)
    }

    private func bigrams(for text: String) -> Set<String> {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 2 else { return [compact] }
        let characters = Array(compact)
        return Set((0 ..< (characters.count - 1)).map { index in
            String(characters[index ... index + 1])
        })
    }
}
