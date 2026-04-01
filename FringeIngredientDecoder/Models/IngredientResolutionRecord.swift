import Foundation
import SwiftData

enum IngredientResolutionSource: String, Codable {
    case openFoodFacts
    case openBeautyFacts
}

struct ResolvedIngredient: Codable, Hashable {
    let canonicalName: String
    let normalizedName: String
    let category: IngredientCategory
    let confidence: IngredientConfidence
    let whatItIs: String
    let purpose: String
    let source: IngredientResolutionSource
    let updatedAt: Date

    var detail: IngredientDetail {
        IngredientDetail(whatItIs: whatItIs, purpose: purpose)
    }

    func makeAnalysis() -> IngredientAnalysis {
        IngredientAnalysis(
            name: canonicalName,
            normalizedName: normalizedName,
            category: category,
            confidence: confidence,
            detail: detail
        )
    }
}

@Model
final class IngredientResolutionRecord {
    @Attribute(.unique) var normalizedName: String
    var canonicalName: String
    var categoryRaw: String
    var confidenceRaw: String
    var whatItIs: String
    var purpose: String
    var sourceRaw: String
    var updatedAt: Date

    init(resolvedIngredient: ResolvedIngredient) {
        self.normalizedName = resolvedIngredient.normalizedName
        self.canonicalName = resolvedIngredient.canonicalName
        self.categoryRaw = resolvedIngredient.category.rawValue
        self.confidenceRaw = resolvedIngredient.confidence.rawValue
        self.whatItIs = resolvedIngredient.whatItIs
        self.purpose = resolvedIngredient.purpose
        self.sourceRaw = resolvedIngredient.source.rawValue
        self.updatedAt = resolvedIngredient.updatedAt
    }

    func update(from resolvedIngredient: ResolvedIngredient) {
        canonicalName = resolvedIngredient.canonicalName
        categoryRaw = resolvedIngredient.category.rawValue
        confidenceRaw = resolvedIngredient.confidence.rawValue
        whatItIs = resolvedIngredient.whatItIs
        purpose = resolvedIngredient.purpose
        sourceRaw = resolvedIngredient.source.rawValue
        updatedAt = resolvedIngredient.updatedAt
    }

    func decodedResolvedIngredient() -> ResolvedIngredient? {
        guard
            let category = IngredientCategory(rawValue: categoryRaw),
            let confidence = IngredientConfidence(rawValue: confidenceRaw),
            let source = IngredientResolutionSource(rawValue: sourceRaw)
        else {
            return nil
        }

        return ResolvedIngredient(
            canonicalName: canonicalName,
            normalizedName: normalizedName,
            category: category,
            confidence: confidence,
            whatItIs: whatItIs,
            purpose: purpose,
            source: source,
            updatedAt: updatedAt
        )
    }
}

@Model
final class UnmatchedIngredientRecord {
    @Attribute(.unique) var key: String
    var normalizedName: String
    var displayName: String
    var domainRaw: String
    var lastSourceRaw: String
    var lastConfidenceRaw: String
    var sampleTitle: String
    var hitCount: Int
    var firstSeenAt: Date
    var lastSeenAt: Date

    init(
        normalizedName: String,
        displayName: String,
        domain: ProductDomain,
        source: AnalysisSource,
        confidence: IngredientConfidence,
        sampleTitle: String,
        seenAt: Date = .now
    ) {
        self.key = Self.makeKey(normalizedName: normalizedName, domain: domain)
        self.normalizedName = normalizedName
        self.displayName = displayName
        self.domainRaw = domain.rawValue
        self.lastSourceRaw = source.rawValue
        self.lastConfidenceRaw = confidence.rawValue
        self.sampleTitle = sampleTitle
        self.hitCount = 1
        self.firstSeenAt = seenAt
        self.lastSeenAt = seenAt
    }

    func registerHit(displayName: String, source: AnalysisSource, confidence: IngredientConfidence, sampleTitle: String, seenAt: Date = .now) {
        self.displayName = displayName
        self.lastSourceRaw = source.rawValue
        self.lastConfidenceRaw = confidence.rawValue
        self.sampleTitle = sampleTitle
        self.hitCount += 1
        self.lastSeenAt = seenAt
    }

    var domain: ProductDomain? {
        ProductDomain(rawValue: domainRaw)
    }

    static func makeKey(normalizedName: String, domain: ProductDomain) -> String {
        "\(domain.rawValue)|\(normalizedName)"
    }
}
