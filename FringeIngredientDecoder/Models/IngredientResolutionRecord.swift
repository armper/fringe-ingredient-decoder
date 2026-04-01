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
