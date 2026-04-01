import Foundation

protocol IngredientResolutionServing {
    func resolveUnknowns(ingredients: [IngredientAnalysis], domain: ProductDomain) async -> [ResolvedIngredient]
}

protocol IngredientSuggestionServing {
    func fetchSuggestion(for query: String, domain: ProductDomain) async throws -> String?
}

struct IngredientResolutionService: IngredientResolutionServing {
    private let suggestionService: any IngredientSuggestionServing
    private let analysisEngine: IngredientAnalysisEngine

    init(
        suggestionService: any IngredientSuggestionServing = IngredientSuggestionAPI(),
        analysisEngine: IngredientAnalysisEngine = IngredientAnalysisEngine()
    ) {
        self.suggestionService = suggestionService
        self.analysisEngine = analysisEngine
    }

    func resolveUnknowns(ingredients: [IngredientAnalysis], domain: ProductDomain) async -> [ResolvedIngredient] {
        let candidates = Array(
            Dictionary(
                grouping: ingredients.filter { ingredient in
                    ingredient.confidence == .low || (ingredient.category == .unknown && ingredient.confidence != .high)
                }
            ) { $0.normalizedName }
            .compactMap { $0.value.first }
            .prefix(10)
        )

        var resolved: [ResolvedIngredient] = []
        for ingredient in candidates {
            do {
                guard let suggestion = try await suggestionService.fetchSuggestion(for: ingredient.name, domain: domain) else {
                    continue
                }

                if let match = analysisEngine.makeResolvedIngredient(
                    originalName: ingredient.name,
                    originalNormalizedName: ingredient.normalizedName,
                    suggestedName: suggestion,
                    source: source(for: domain)
                ) {
                    resolved.append(match)
                }
            } catch {
                continue
            }
        }

        return resolved
    }

    private func source(for domain: ProductDomain) -> IngredientResolutionSource {
        switch domain {
        case .beauty:
            return .openBeautyFacts
        case .food, .custom:
            return .openFoodFacts
        }
    }
}

private struct IngredientSuggestionAPI: IngredientSuggestionServing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSuggestion(for query: String, domain: ProductDomain) async throws -> String? {
        let resolvedDomain: ProductDomain = domain == .beauty ? .beauty : .food
        guard var components = URLComponents(string: "\(baseURL(for: resolvedDomain))/api/v3/taxonomy_suggestions") else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "tagtype", value: "ingredients"),
            URLQueryItem(name: "lc", value: "en"),
            URLQueryItem(name: "string", value: query),
            URLQueryItem(name: "get_synonyms", value: "1"),
        ]

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("FringeIngredientDecoder/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(TaxonomySuggestionResponse.self, from: data)
        guard let firstSuggestion = decoded.suggestions.first?.trimmingCharacters(in: .whitespacesAndNewlines), !firstSuggestion.isEmpty else {
            return nil
        }

        if let synonym = decoded.matchedSynonyms?[firstSuggestion]?.trimmingCharacters(in: .whitespacesAndNewlines), !synonym.isEmpty {
            return synonym
        }

        return firstSuggestion
    }

    private func baseURL(for domain: ProductDomain) -> String {
        switch domain {
        case .beauty:
            return "https://world.openbeautyfacts.org"
        case .food, .custom:
            return "https://world.openfoodfacts.org"
        }
    }
}

private struct TaxonomySuggestionResponse: Decodable {
    let suggestions: [String]
    let matchedSynonyms: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case suggestions
        case matchedSynonyms = "matched_synonyms"
    }
}
