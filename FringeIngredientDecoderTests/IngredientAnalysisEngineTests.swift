import XCTest
import SwiftData
@testable import FringeIngredientDecoder

final class IngredientAnalysisEngineTests: XCTestCase {
    func testNestedIngredientsAreFlattened() {
        let engine = IngredientAnalysisEngine()

        let analysis = engine.analyze(
            title: "Test",
            ingredientsText: "Enriched flour (wheat flour, niacin, reduced iron), water, soy lecithin",
            source: .manual
        )

        XCTAssertEqual(analysis.ingredients.map(\.normalizedName), [
            "enriched flour", "wheat flour", "niacin", "reduced iron", "water", "soy lecithin"
        ])
    }

    func testHeuristicFlagsManyAdditives() {
        let engine = IngredientAnalysisEngine()

        let analysis = engine.analyze(
            title: "Drink",
            ingredientsText: "Water, citric acid, natural flavors, sodium benzoate, sucralose, red 40, xanthan gum",
            source: .manual
        )

        XCTAssertEqual(analysis.summary.badge, "Many Additives")
    }

    func testSimpleFormulaScoresHigherThanProcessedOne() {
        let engine = IngredientAnalysisEngine()

        let simple = engine.analyze(
            title: "Simple Bar",
            ingredientsText: "Dates, almonds, cocoa powder, sea salt",
            source: .manual,
            domain: .food
        )

        let processed = engine.analyze(
            title: "Processed Bar",
            ingredientsText: "Water, sugar, natural flavors, sodium benzoate, sucralose, red 40, xanthan gum",
            source: .manual,
            domain: .food
        )

        XCTAssertGreaterThan(simple.score, processed.score)
        XCTAssertEqual(simple.grade, .excellent)
        XCTAssertTrue([ProductGrade.poor, .bad].contains(processed.grade))
    }

    func testPreferenceAlertsMatchIngredients() {
        let engine = IngredientAnalysisEngine()
        var profile = PreferenceProfile.default
        profile.set(.gluten, enabled: true)
        profile.set(.lactose, enabled: true)

        let analysis = engine.analyze(
            title: "Snack",
            ingredientsText: "Whole wheat flour, whey, sugar",
            source: .manual,
            domain: .food,
            preferences: profile
        )

        XCTAssertEqual(analysis.alerts.map(\.key), [.gluten, .lactose])
    }

    func testGeneratedCatalogMatchesFoodColorAlias() {
        let engine = IngredientAnalysisEngine()

        let analysis = engine.analyze(
            title: "Candy",
            ingredientsText: "Sugar, FD&C Red No. 40, citric acid",
            source: .manual,
            domain: .food
        )

        let ingredient = analysis.ingredients.first { $0.normalizedName == "allura red" }
        XCTAssertEqual(ingredient?.category, .coloring)
        XCTAssertEqual(ingredient?.confidence, .high)
    }

    func testGeneratedCatalogMatchesBeautyPolymer() {
        let engine = IngredientAnalysisEngine()

        let analysis = engine.analyze(
            title: "Styler",
            ingredientsText: "Water, Acrylates/VA/Vinyl Neodecanoate Copolymer, Glycerin",
            source: .manual,
            domain: .beauty
        )

        let ingredient = analysis.ingredients.first { $0.normalizedName == "acrylates/va/vinyl neodecanoate copolymer" }
        XCTAssertEqual(ingredient?.category, .stabilizer)
        XCTAssertEqual(ingredient?.confidence, .high)
    }

    func testGeneratedCatalogMatchesCommonFoodBaseIngredient() {
        let engine = IngredientAnalysisEngine()

        let analysis = engine.analyze(
            title: "Bread",
            ingredientsText: "Whole wheat flour, water, salt",
            source: .manual,
            domain: .food
        )

        let ingredient = analysis.ingredients.first { $0.normalizedName == "whole wheat flour" }
        XCTAssertEqual(ingredient?.confidence, .high)
        XCTAssertEqual(ingredient?.category, .unknown)
    }

    func testExactCuratedEntriesOverrideResolvedCache() {
        let engine = IngredientAnalysisEngine()
        let cached = ResolvedIngredient(
            canonicalName: "Water Additive",
            normalizedName: "water",
            category: .additive,
            confidence: .high,
            whatItIs: "A fake additive.",
            purpose: "This should never win over the local exact match.",
            source: .openFoodFacts,
            updatedAt: .now
        )

        let analysis = engine.analyze(
            title: "Water Test",
            ingredientsText: "Water",
            source: .manual,
            resolvedIngredients: ["water": cached]
        )

        XCTAssertEqual(analysis.ingredients.first?.name, "Water")
        XCTAssertEqual(analysis.ingredients.first?.category, .unknown)
        XCTAssertEqual(analysis.ingredients.first?.confidence, .high)
    }

    func testResolvedCacheWinsBeforeHeuristicFallback() {
        let engine = IngredientAnalysisEngine()
        let cached = ResolvedIngredient(
            canonicalName: "Mystery Polymer",
            normalizedName: "mystery polymer",
            category: .stabilizer,
            confidence: .high,
            whatItIs: "A film-forming polymer.",
            purpose: "It helps hold texture and structure.",
            source: .openBeautyFacts,
            updatedAt: .now
        )

        let analysis = engine.analyze(
            title: "Styler",
            ingredientsText: "Mystery Polymer",
            source: .manual,
            domain: .beauty,
            resolvedIngredients: ["mystery polymer": cached]
        )

        XCTAssertEqual(analysis.ingredients.first?.category, .stabilizer)
        XCTAssertEqual(analysis.ingredients.first?.confidence, .high)
        XCTAssertEqual(analysis.ingredients.first?.detail.whatItIs, "A film-forming polymer.")
    }
}

final class IngredientResolutionServiceTests: XCTestCase {
    func testResolveUnknownsUsesFoodSuggestionMatch() async {
        let engine = IngredientAnalysisEngine()
        let suggestionService = MockSuggestionService(results: [
            "red color 40": "Red 40"
        ])
        let service = IngredientResolutionService(suggestionService: suggestionService, analysisEngine: engine)

        let resolved = await service.resolveUnknowns(
            ingredients: [
                IngredientAnalysis(
                    name: "Red Color 40",
                    normalizedName: "red color 40",
                    category: .unknown,
                    confidence: .low,
                    detail: IngredientDetail(
                        whatItIs: "Unknown",
                        purpose: "Unknown"
                    )
                )
            ],
            domain: .food
        )

        XCTAssertEqual(suggestionService.receivedQueries, ["Red Color 40"])
        XCTAssertEqual(resolved.first?.category, .coloring)
        XCTAssertEqual(resolved.first?.confidence, .high)
        XCTAssertEqual(resolved.first?.source, .openFoodFacts)
        XCTAssertEqual(resolved.first?.canonicalName, "Red 40")
    }

    func testResolveUnknownsUsesBeautySuggestionMatch() async {
        let engine = IngredientAnalysisEngine()
        let suggestionService = MockSuggestionService(results: [
            "mystery inci polymer": "Acrylates/VA/Vinyl Neodecanoate Copolymer"
        ])
        let service = IngredientResolutionService(suggestionService: suggestionService, analysisEngine: engine)

        let resolved = await service.resolveUnknowns(
            ingredients: [
                IngredientAnalysis(
                    name: "Mystery INCI Polymer",
                    normalizedName: "mystery inci polymer",
                    category: .unknown,
                    confidence: .low,
                    detail: IngredientDetail(
                        whatItIs: "Unknown",
                        purpose: "Unknown"
                    )
                )
            ],
            domain: .beauty
        )

        XCTAssertEqual(resolved.first?.category, .stabilizer)
        XCTAssertEqual(resolved.first?.confidence, .high)
        XCTAssertEqual(resolved.first?.source, .openBeautyFacts)
    }

    func testResolveUnknownsDeduplicatesQueriesByNormalizedName() async {
        let engine = IngredientAnalysisEngine()
        let suggestionService = MockSuggestionService(results: [
            "mystery polymer": "Acrylates/VA/Vinyl Neodecanoate Copolymer"
        ])
        let service = IngredientResolutionService(suggestionService: suggestionService, analysisEngine: engine)

        let ingredients = [
            IngredientAnalysis(
                name: "Mystery Polymer",
                normalizedName: "mystery polymer",
                category: .unknown,
                confidence: .low,
                detail: IngredientDetail(whatItIs: "Unknown", purpose: "Unknown")
            ),
            IngredientAnalysis(
                name: "Mystery Polymer",
                normalizedName: "mystery polymer",
                category: .unknown,
                confidence: .low,
                detail: IngredientDetail(whatItIs: "Unknown", purpose: "Unknown")
            )
        ]

        let resolved = await service.resolveUnknowns(ingredients: ingredients, domain: .beauty)

        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(suggestionService.receivedQueries, ["Mystery Polymer"])
    }

    func testResolveUnknownsCapsRemoteRequestsAtTenIngredients() async {
        let engine = IngredientAnalysisEngine()
        let suggestionService = MockSuggestionService(results: [:])
        let service = IngredientResolutionService(suggestionService: suggestionService, analysisEngine: engine)
        let ingredients = (0 ..< 12).map { index in
            IngredientAnalysis(
                name: "Unknown \(index)",
                normalizedName: "unknown \(index)",
                category: .unknown,
                confidence: .low,
                detail: IngredientDetail(whatItIs: "Unknown", purpose: "Unknown")
            )
        }

        _ = await service.resolveUnknowns(ingredients: ingredients, domain: .food)

        XCTAssertEqual(suggestionService.receivedQueries.count, 10)
    }
}

final class OpenFoodFactsServiceTests: XCTestCase {
    func testMakeRemoteProductUsesFallbackBarcodeAndEnglishIngredients() {
        let service = OpenFoodFactsService()

        let remote = service.makeRemoteProduct(
            from: [
                "product_name": "Granola",
                "ingredients_text_en": "oats, almonds, sea salt",
                "image_front_small_url": "https://example.com/granola.jpg"
            ],
            fallbackBarcode: "1234567890123",
            domain: .food
        )

        XCTAssertEqual(remote?.title, "Granola")
        XCTAssertEqual(remote?.barcode, "1234567890123")
        XCTAssertEqual(remote?.ingredientsText, "oats, almonds, sea salt")
        XCTAssertEqual(remote?.domain, .food)
    }

    func testMakeRemoteProductFallsBackToIngredientsArray() {
        let service = OpenFoodFactsService()

        let remote = service.makeRemoteProduct(
            from: [
                "product_name_en": "Moisturizer",
                "code": "0099887766",
                "ingredients": [
                    ["text": "water"],
                    ["text": "glycerin"],
                    ["text": "parfum"]
                ]
            ],
            fallbackBarcode: nil,
            domain: .beauty
        )

        XCTAssertEqual(remote?.ingredientsText, "water, glycerin, parfum")
        XCTAssertEqual(remote?.domain, .beauty)
    }
}

@MainActor
final class DecoderStoreTests: XCTestCase {
    func testSuccessfulBarcodeLookupSetsActiveResultAndPersistsRecord() async throws {
        let defaults = makeIsolatedDefaults()
        let container = try makeContainer()
        let context = ModelContext(container)
        let lookup = MockLookupService(outcomes: [
            .found(
                RemoteProduct(
                    title: "Test Cookies",
                    ingredientsText: "Wheat flour, sugar, palm oil",
                    barcode: "1234567890123",
                    imageURL: nil,
                    domain: .food
                )
            )
        ])
        let store = DecoderStore(defaults: defaults, lookupService: lookup)

        await store.handleScannedBarcode("1234567890123", modelContext: context)

        let result = try XCTUnwrap(store.activeResult)
        XCTAssertEqual(result.title, "Test Cookies")
        XCTAssertEqual(result.barcode, "1234567890123")
        XCTAssertFalse(store.isLookingUp)
        XCTAssertNil(store.inlineNotice)

        let records = try context.fetch(FetchDescriptor<RecentAnalysisRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(lookup.receivedBarcodes, ["1234567890123"])
    }

    func testBarcodeLookupNotFoundShowsInlineFallback() async throws {
        let defaults = makeIsolatedDefaults()
        let container = try makeContainer()
        let context = ModelContext(container)
        let lookup = MockLookupService(outcomes: [.notFound])
        let store = DecoderStore(defaults: defaults, lookupService: lookup)
        UIPasteboard.general.string = nil

        await store.handleScannedBarcode("0000000000000", modelContext: context)

        XCTAssertNil(store.activeResult)
        XCTAssertEqual(store.inlineNotice?.text, "No match. Paste ingredients instead.")
        XCTAssertTrue(store.isManualComposerExpanded)
        XCTAssertFalse(store.isLookingUp)

        let records = try context.fetch(FetchDescriptor<RecentAnalysisRecord>())
        XCTAssertEqual(records.count, 0)
        XCTAssertEqual(lookup.receivedBarcodes, ["0000000000000"])
    }

    func testDuplicateBarcodeWithinThrottleWindowSkipsSecondLookup() async throws {
        let defaults = makeIsolatedDefaults()
        let container = try makeContainer()
        let context = ModelContext(container)
        let lookup = MockLookupService(outcomes: [
            .found(
                RemoteProduct(
                    title: "Soda",
                    ingredientsText: "Water, sugar, flavor",
                    barcode: "5555555555555",
                    imageURL: nil,
                    domain: .food
                )
            ),
            .notFound
        ])
        let store = DecoderStore(defaults: defaults, lookupService: lookup)

        await store.handleScannedBarcode("5555555555555", modelContext: context)
        await store.handleScannedBarcode("5555555555555", modelContext: context)

        XCTAssertEqual(lookup.receivedBarcodes, ["5555555555555"])

        let records = try context.fetch(FetchDescriptor<RecentAnalysisRecord>())
        XCTAssertEqual(records.count, 1)
    }

    func testBarcodeLookupUnavailableShowsFallbackNotice() async throws {
        let defaults = makeIsolatedDefaults()
        let container = try makeContainer()
        let context = ModelContext(container)
        let lookup = MockLookupService(outcomes: [.unavailable])
        let store = DecoderStore(defaults: defaults, lookupService: lookup)
        UIPasteboard.general.string = nil

        await store.handleScannedBarcode("1111111111111", modelContext: context)

        XCTAssertEqual(store.inlineNotice?.text, "Lookup unavailable. Paste ingredients instead.")
        XCTAssertTrue(store.isManualComposerExpanded)
        XCTAssertNil(store.activeResult)
    }

    func testManualSubmissionPersistsRecordAndInfersBeautyDomain() async throws {
        let defaults = makeIsolatedDefaults()
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = DecoderStore(defaults: defaults)
        store.manualText = "Water, glycerin, parfum"

        await store.submitManualIngredients(modelContext: context)

        let activeResult = try XCTUnwrap(store.activeResult)
        XCTAssertEqual(activeResult.domain, .beauty)
        XCTAssertEqual(activeResult.source, .manual)

        let records = try context.fetch(FetchDescriptor<RecentAnalysisRecord>())
        XCTAssertEqual(records.count, 1)
    }

    func testReopenRebuildsAlertsWithCurrentPreferences() async throws {
        let defaults = makeIsolatedDefaults()
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = DecoderStore(defaults: defaults)
        let engine = IngredientAnalysisEngine()

        let analysis = engine.analyze(
            title: "Bread",
            ingredientsText: "Whole wheat flour, sugar",
            source: .manual,
            domain: .food
        )
        let record = try RecentAnalysisRecord(analysis: analysis)
        context.insert(record)
        try context.save()

        store.setPreference(.gluten, enabled: true, modelContext: context)
        store.reopen(record, modelContext: context)

        XCTAssertEqual(store.activeResult?.alerts.map(\.key), [.gluten])
    }

    func testFavoriteTogglePersistsAcrossStoreInstances() {
        let defaults = makeIsolatedDefaults()
        let engine = IngredientAnalysisEngine()
        let analysis = engine.analyze(
            title: "Bar",
            ingredientsText: "Dates, almonds",
            source: .manual,
            domain: .food
        )

        let firstStore = DecoderStore(defaults: defaults)
        firstStore.setFavorite(analysis, isFavorite: true)
        XCTAssertTrue(firstStore.isFavorite(analysis))

        let secondStore = DecoderStore(defaults: defaults)
        XCTAssertTrue(secondStore.isFavorite(analysis))
    }

    func testManualComposerDisablesScanner() {
        let store = DecoderStore(defaults: makeIsolatedDefaults())

        XCTAssertTrue(store.scannerEnabled)
        store.prepareManualEntry()
        XCTAssertFalse(store.scannerEnabled)
    }

    func testManualSubmissionsTrimHistoryToTwentyRecords() async throws {
        let defaults = makeIsolatedDefaults()
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = DecoderStore(defaults: defaults)

        for index in 0 ..< 22 {
            store.manualText = "Water, sugar, flavor \(index)"
            await store.submitManualIngredients(modelContext: context)
        }

        let records = try context.fetch(FetchDescriptor<RecentAnalysisRecord>())
        XCTAssertEqual(records.count, 20)
    }

    func testBackgroundResolutionUpdatesActiveResultSilently() async throws {
        let defaults = makeIsolatedDefaults()
        let container = try makeContainer()
        let context = ModelContext(container)
        let lookup = MockLookupService(outcomes: [
            .found(
                RemoteProduct(
                    title: "Styler",
                    ingredientsText: "Water, Mystery Polymer",
                    barcode: "2222222222222",
                    imageURL: nil,
                    domain: .beauty
                )
            )
        ])
        let resolution = MockResolutionService(
            resolvedIngredients: [
                ResolvedIngredient(
                    canonicalName: "Mystery Polymer",
                    normalizedName: "mystery polymer",
                    category: .stabilizer,
                    confidence: .high,
                    whatItIs: "A film-forming polymer.",
                    purpose: "It helps hold texture and structure.",
                    source: .openBeautyFacts,
                    updatedAt: .now
                )
            ],
            delayNanoseconds: 120_000_000
        )
        let store = DecoderStore(defaults: defaults, lookupService: lookup, resolutionService: resolution)

        await store.handleScannedBarcode("2222222222222", modelContext: context)

        XCTAssertEqual(store.activeResult?.ingredients.last?.category, .unknown)
        XCTAssertEqual(store.activeResult?.id.uuidString.isEmpty, false)

        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(store.activeResult?.ingredients.last?.category, .stabilizer)
        XCTAssertEqual(store.activeResult?.ingredients.last?.confidence, .high)

        let cached = try context.fetch(FetchDescriptor<IngredientResolutionRecord>())
        XCTAssertEqual(cached.count, 1)

        let records = try context.fetch(FetchDescriptor<RecentAnalysisRecord>())
        XCTAssertEqual(records.count, 1)
        let persisted = try XCTUnwrap(records.first?.decodedAnalysis())
        XCTAssertEqual(persisted.ingredients.last?.category, .stabilizer)
    }

    func testCachedResolutionSurvivesStoreRecreationAndReopen() async throws {
        let defaults = makeIsolatedDefaults()
        let container = try makeContainer()
        let context = ModelContext(container)
        let lookup = MockLookupService(outcomes: [
            .found(
                RemoteProduct(
                    title: "Styler",
                    ingredientsText: "Water, Mystery Polymer",
                    barcode: "3333333333333",
                    imageURL: nil,
                    domain: .beauty
                )
            )
        ])
        let firstResolution = MockResolutionService(
            resolvedIngredients: [
                ResolvedIngredient(
                    canonicalName: "Mystery Polymer",
                    normalizedName: "mystery polymer",
                    category: .stabilizer,
                    confidence: .high,
                    whatItIs: "A film-forming polymer.",
                    purpose: "It helps hold texture and structure.",
                    source: .openBeautyFacts,
                    updatedAt: .now
                )
            ],
            delayNanoseconds: 50_000_000
        )
        let firstStore = DecoderStore(defaults: defaults, lookupService: lookup, resolutionService: firstResolution)

        await firstStore.handleScannedBarcode("3333333333333", modelContext: context)
        try await Task.sleep(nanoseconds: 180_000_000)

        let record = try XCTUnwrap(context.fetch(FetchDescriptor<RecentAnalysisRecord>()).first)

        let secondResolution = MockResolutionService(resolvedIngredients: [])
        let secondStore = DecoderStore(defaults: defaults, resolutionService: secondResolution)
        secondStore.reopen(record, modelContext: context)

        XCTAssertEqual(secondStore.activeResult?.ingredients.last?.category, .stabilizer)
        XCTAssertEqual(secondStore.activeResult?.ingredients.last?.confidence, .high)
        XCTAssertEqual(secondResolution.invocations, 0)
    }

    func testResolutionFailureLeavesInitialResultUsable() async throws {
        let defaults = makeIsolatedDefaults()
        let container = try makeContainer()
        let context = ModelContext(container)
        let lookup = MockLookupService(outcomes: [
            .found(
                RemoteProduct(
                    title: "Snack",
                    ingredientsText: "Water, Mystery Polymer",
                    barcode: "4444444444444",
                    imageURL: nil,
                    domain: .food
                )
            )
        ])
        let resolution = MockResolutionService(resolvedIngredients: [], delayNanoseconds: 50_000_000)
        let store = DecoderStore(defaults: defaults, lookupService: lookup, resolutionService: resolution)

        await store.handleScannedBarcode("4444444444444", modelContext: context)
        let initialCategory = store.activeResult?.ingredients.last?.category
        let initialDetail = store.activeResult?.ingredients.last?.detail.whatItIs

        try await Task.sleep(nanoseconds: 160_000_000)

        XCTAssertEqual(initialCategory, .unknown)
        XCTAssertEqual(store.activeResult?.ingredients.last?.category, .unknown)
        XCTAssertEqual(store.activeResult?.ingredients.last?.detail.whatItIs, initialDetail)
        XCTAssertEqual(resolution.invocations, 1)
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: RecentAnalysisRecord.self, IngredientResolutionRecord.self, configurations: configuration)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "FringeIngredientDecoderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class MockLookupService: ProductLookupServing {
    private let outcomes: [LookupOutcome]
    private(set) var receivedBarcodes: [String] = []

    init(outcomes: [LookupOutcome]) {
        self.outcomes = outcomes
    }

    func lookup(barcode: String) async -> LookupOutcome {
        receivedBarcodes.append(barcode)
        let index = receivedBarcodes.count - 1
        if index < outcomes.count {
            return outcomes[index]
        }
        return outcomes.last ?? .notFound
    }
}

private final class MockSuggestionService: IngredientSuggestionServing {
    let results: [String: String]
    private(set) var receivedQueries: [String] = []

    init(results: [String: String]) {
        self.results = results
    }

    func fetchSuggestion(for query: String, domain: ProductDomain) async throws -> String? {
        receivedQueries.append(query)
        return results[query.lowercased()]
    }
}

@MainActor
private final class MockResolutionService: IngredientResolutionServing {
    let resolvedIngredients: [ResolvedIngredient]
    let delayNanoseconds: UInt64
    private(set) var invocations = 0

    init(resolvedIngredients: [ResolvedIngredient], delayNanoseconds: UInt64 = 0) {
        self.resolvedIngredients = resolvedIngredients
        self.delayNanoseconds = delayNanoseconds
    }

    func resolveUnknowns(ingredients: [IngredientAnalysis], domain: ProductDomain) async -> [ResolvedIngredient] {
        invocations += 1
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return resolvedIngredients
    }
}
