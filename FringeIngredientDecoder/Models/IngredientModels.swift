import Foundation

enum AnalysisSource: String, Codable {
    case barcode
    case manual
}

enum ProductDomain: String, Codable {
    case food
    case beauty
    case custom

    var title: String {
        switch self {
        case .food:
            return "Food"
        case .beauty:
            return "Beauty"
        case .custom:
            return "Custom"
        }
    }
}

enum ProductGrade: String, Codable {
    case excellent
    case good
    case fair
    case poor
    case bad
    case unclear

    var title: String {
        rawValue.capitalized
    }
}

enum IngredientCategory: String, Codable, CaseIterable {
    case additive
    case preservative
    case sweetener
    case coloring
    case emulsifier
    case stabilizer
    case fragrance
    case solvent
    case surfactant
    case unknown

    var title: String {
        rawValue.capitalized
    }
}

enum IngredientConfidence: String, Codable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

enum SummaryTone: String, Codable {
    case simple
    case balanced
    case additives
    case processed
    case unclear
}

enum PreferenceKey: String, Codable, CaseIterable, Identifiable {
    case gluten
    case lactose
    case palmOil
    case animalDerived
    case fragrance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gluten:
            return "Gluten"
        case .lactose:
            return "Lactose"
        case .palmOil:
            return "Palm oil"
        case .animalDerived:
            return "Animal-derived"
        case .fragrance:
            return "Fragrance"
        }
    }

    var icon: String {
        switch self {
        case .gluten:
            return "leaf.circle"
        case .lactose:
            return "drop.circle"
        case .palmOil:
            return "tree"
        case .animalDerived:
            return "pawprint.circle"
        case .fragrance:
            return "sparkles"
        }
    }
}

struct PreferenceProfile: Codable, Hashable {
    var gluten = false
    var lactose = false
    var palmOil = false
    var animalDerived = false
    var fragrance = false

    static let `default` = PreferenceProfile()

    func isEnabled(_ key: PreferenceKey) -> Bool {
        switch key {
        case .gluten:
            return gluten
        case .lactose:
            return lactose
        case .palmOil:
            return palmOil
        case .animalDerived:
            return animalDerived
        case .fragrance:
            return fragrance
        }
    }

    mutating func set(_ key: PreferenceKey, enabled: Bool) {
        switch key {
        case .gluten:
            gluten = enabled
        case .lactose:
            lactose = enabled
        case .palmOil:
            palmOil = enabled
        case .animalDerived:
            animalDerived = enabled
        case .fragrance:
            fragrance = enabled
        }
    }

    var enabledKeys: [PreferenceKey] {
        PreferenceKey.allCases.filter(isEnabled)
    }
}

struct ProductSummary: Codable, Hashable {
    let badge: String
    let note: String
    let tone: SummaryTone
}

struct ProductSignal: Identifiable, Codable, Hashable {
    let title: String
    let detail: String
    let emphasis: String?

    var id: String { "\(title)|\(detail)|\(emphasis ?? "")" }
}

struct PreferenceAlert: Identifiable, Codable, Hashable {
    let key: PreferenceKey
    let matches: [String]

    var id: String { key.rawValue }

    var title: String {
        "\(key.title) alert"
    }

    var note: String {
        matches.prefix(2).joined(separator: ", ")
    }
}

struct IngredientDetail: Codable, Hashable {
    let whatItIs: String
    let purpose: String
}

struct IngredientAnalysis: Identifiable, Codable, Hashable {
    let name: String
    let normalizedName: String
    let category: IngredientCategory
    let confidence: IngredientConfidence
    let detail: IngredientDetail

    var id: String { normalizedName }
}

struct AnalyzedProduct: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let source: AnalysisSource
    let domain: ProductDomain
    let ingredientsText: String
    let ingredients: [IngredientAnalysis]
    let summary: ProductSummary
    let grade: ProductGrade
    let score: Int
    let positives: [ProductSignal]
    let negatives: [ProductSignal]
    let alerts: [PreferenceAlert]
    let barcode: String?
    let imageURL: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        source: AnalysisSource,
        domain: ProductDomain,
        ingredientsText: String,
        ingredients: [IngredientAnalysis],
        summary: ProductSummary,
        grade: ProductGrade,
        score: Int,
        positives: [ProductSignal],
        negatives: [ProductSignal],
        alerts: [PreferenceAlert],
        barcode: String? = nil,
        imageURL: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.domain = domain
        self.ingredientsText = ingredientsText
        self.ingredients = ingredients
        self.summary = summary
        self.grade = grade
        self.score = score
        self.positives = positives
        self.negatives = negatives
        self.alerts = alerts
        self.barcode = barcode
        self.imageURL = imageURL
        self.createdAt = createdAt
    }

    var subtitle: String {
        let additiveCategories: Set<IngredientCategory> = [
            .additive, .preservative, .sweetener, .coloring, .emulsifier, .stabilizer, .fragrance, .solvent, .surfactant
        ]
        let additiveCount = ingredients.filter { additiveCategories.contains($0.category) }.count
        return "\(ingredients.count) ingredients · \(additiveCount) additives"
    }

    var favoriteKey: String {
        if let barcode, !barcode.isEmpty {
            return "barcode:\(barcode)"
        }

        let ingredientKey = ingredients
            .map(\.normalizedName)
            .joined(separator: "|")
        return "manual:\(title.lowercased())|\(ingredientKey)"
    }
}

struct RemoteProduct {
    let title: String
    let ingredientsText: String
    let barcode: String
    let imageURL: String?
    let domain: ProductDomain
}

enum LookupOutcome {
    case found(RemoteProduct)
    case notFound
    case unavailable
}

enum StorePreviewScenario: String {
    case live
    case home
    case result
    case detail

    static var current: StorePreviewScenario {
        let environment = ProcessInfo.processInfo.environment
        if let value = environment["FID_SCREENSHOT_SCENE"], let scenario = StorePreviewScenario(rawValue: value) {
            return scenario
        }
        return .live
    }
}

enum PreviewContent {
    static let sampleProduct = AnalyzedProduct(
        title: "Fringe Oat Bar",
        source: .barcode,
        domain: .food,
        ingredientsText: "Whole grain oats, chicory root fiber, almond butter, glycerin, natural flavors, citric acid, sunflower lecithin, sea salt, mixed tocopherols",
        ingredients: [
            IngredientAnalysis(
                name: "Whole Grain Oats",
                normalizedName: "whole grain oats",
                category: .unknown,
                confidence: .medium,
                detail: IngredientDetail(
                    whatItIs: "A whole-grain base ingredient.",
                    purpose: "It provides the main body and texture."
                )
            ),
            IngredientAnalysis(
                name: "Chicory Root Fiber",
                normalizedName: "chicory root fiber",
                category: .stabilizer,
                confidence: .medium,
                detail: IngredientDetail(
                    whatItIs: "A plant fiber used in packaged foods.",
                    purpose: "It adds bulk and helps texture."
                )
            ),
            IngredientAnalysis(
                name: "Almond Butter",
                normalizedName: "almond butter",
                category: .unknown,
                confidence: .medium,
                detail: IngredientDetail(
                    whatItIs: "Ground almonds made into a paste.",
                    purpose: "It adds fat, flavor, and body."
                )
            ),
            IngredientAnalysis(
                name: "Glycerin",
                normalizedName: "glycerin",
                category: .unknown,
                confidence: .high,
                detail: IngredientDetail(
                    whatItIs: "A common humectant.",
                    purpose: "It helps hold onto moisture."
                )
            ),
            IngredientAnalysis(
                name: "Natural Flavors",
                normalizedName: "natural flavors",
                category: .additive,
                confidence: .high,
                detail: IngredientDetail(
                    whatItIs: "A flavor blend sourced from natural raw materials.",
                    purpose: "It boosts taste without listing each component."
                )
            ),
            IngredientAnalysis(
                name: "Citric Acid",
                normalizedName: "citric acid",
                category: .additive,
                confidence: .high,
                detail: IngredientDetail(
                    whatItIs: "An acid found naturally in citrus and also made for food production.",
                    purpose: "It adjusts tartness and helps keep flavor stable."
                )
            ),
            IngredientAnalysis(
                name: "Sunflower Lecithin",
                normalizedName: "sunflower lecithin",
                category: .emulsifier,
                confidence: .medium,
                detail: IngredientDetail(
                    whatItIs: "An emulsifier sourced from sunflower.",
                    purpose: "It helps ingredients stay mixed instead of separating."
                )
            ),
            IngredientAnalysis(
                name: "Sea Salt",
                normalizedName: "sea salt",
                category: .unknown,
                confidence: .medium,
                detail: IngredientDetail(
                    whatItIs: "A familiar mineral ingredient.",
                    purpose: "It sharpens flavor."
                )
            ),
            IngredientAnalysis(
                name: "Mixed Tocopherols",
                normalizedName: "mixed tocopherols",
                category: .preservative,
                confidence: .medium,
                detail: IngredientDetail(
                    whatItIs: "Vitamin E compounds used in packaged foods.",
                    purpose: "They help slow oxidation and keep the product fresher."
                )
            )
        ],
        summary: ProductSummary(
            badge: "Many Additives",
            note: "Several ingredients look engineered for flavor or stability.",
            tone: .additives
        ),
        grade: .fair,
        score: 58,
        positives: [
            ProductSignal(title: "Shorter list", detail: "Nine ingredients overall.", emphasis: "9"),
            ProductSignal(title: "Whole-food base", detail: "Oats and almond butter lead the label.", emphasis: nil)
        ],
        negatives: [
            ProductSignal(title: "Functional additives", detail: "Flavor and texture helpers show up several times.", emphasis: "4"),
            ProductSignal(title: "Shelf-life support", detail: "Preservative-style ingredients are present.", emphasis: "1")
        ],
        alerts: [],
        barcode: "0852394001124",
        imageURL: nil
    )

    static let detailIngredient = IngredientAnalysis(
        name: "Sunflower Lecithin",
        normalizedName: "sunflower lecithin",
        category: .emulsifier,
        confidence: .medium,
        detail: IngredientDetail(
            whatItIs: "An emulsifier sourced from sunflower.",
            purpose: "It helps oil and water stay blended so the texture feels even."
        )
    )
}
