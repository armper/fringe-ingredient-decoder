import Foundation
import SwiftData
import UIKit

@MainActor
final class DecoderStore: ObservableObject {
    enum CameraState: Equatable {
        case idle
        case ready
        case denied
        case unavailable
    }

    struct InlineNotice: Equatable {
        let text: String
    }

    @Published var manualText = ""
    @Published var isManualComposerExpanded = false
    @Published var isLookingUp = false
    @Published var activeResult: AnalyzedProduct?
    @Published var selectedIngredient: IngredientAnalysis?
    @Published var inlineNotice: InlineNotice?
    @Published var cameraState: CameraState = .idle
    @Published var preferenceProfile: PreferenceProfile
    @Published private(set) var favoriteKeys: Set<String>

    private let lookupService: any ProductLookupServing
    private let resolutionService: any IngredientResolutionServing
    private let analysisEngine: IngredientAnalysisEngine
    private let defaults: UserDefaults
    private var lastScannedCode: String?
    private var lastScanDate = Date.distantPast
    private var resolutionTask: Task<Void, Never>?
    private static let preferenceDefaultsKey = "decoder.preferenceProfile"
    private static let favoriteDefaultsKey = "decoder.favoriteKeys"

    init(
        defaults: UserDefaults = .standard,
        lookupService: any ProductLookupServing = OpenFoodFactsService(),
        analysisEngine: IngredientAnalysisEngine = IngredientAnalysisEngine(),
        resolutionService: (any IngredientResolutionServing)? = nil
    ) {
        self.defaults = defaults
        self.lookupService = lookupService
        self.analysisEngine = analysisEngine
        self.resolutionService = resolutionService ?? IngredientResolutionService(analysisEngine: analysisEngine)
        self.preferenceProfile = Self.loadPreferenceProfile(from: defaults)
        self.favoriteKeys = Set(defaults.stringArray(forKey: Self.favoriteDefaultsKey) ?? [])
    }

    var scannerEnabled: Bool {
        activeResult == nil && !isLookingUp && !isManualComposerExpanded
    }

    func prepareManualEntry(clearingNotice: Bool = true) {
        isManualComposerExpanded = true
        if clearingNotice {
            inlineNotice = nil
        }

        guard manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let clipboard = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !clipboard.isEmpty else { return }
        if clipboard.contains(",") || clipboard.contains(";") {
            manualText = clipboard
        }
    }

    func collapseManualEntry() {
        isManualComposerExpanded = false
    }

    func dismissResult() {
        resolutionTask?.cancel()
        resolutionTask = nil
        activeResult = nil
        selectedIngredient = nil
    }

    func reopen(_ record: RecentAnalysisRecord, modelContext: ModelContext) {
        if let analysis = try? record.decodedAnalysis() {
            present(rebuildAnalysis(from: analysis, modelContext: modelContext), modelContext: modelContext)
        }
    }

    func submitManualIngredients(modelContext: ModelContext) async {
        let trimmed = manualText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let baseResult = analysisEngine.analyze(
            title: "Custom Ingredients",
            ingredientsText: trimmed,
            source: .manual,
            domain: inferManualDomain(from: trimmed),
            preferences: preferenceProfile
        )

        present(applyingCachedResolutions(to: baseResult, modelContext: modelContext), modelContext: modelContext)
    }

    func handleScannedBarcode(_ code: String, modelContext: ModelContext) async {
        let now = Date()
        if code == lastScannedCode, now.timeIntervalSince(lastScanDate) < 2.5 {
            return
        }

        lastScannedCode = code
        lastScanDate = now
        isLookingUp = true
        inlineNotice = nil

        let outcome = await lookupService.lookup(barcode: code)
        isLookingUp = false

        switch outcome {
        case .found(let product):
            let baseAnalysis = analysisEngine.analyze(
                title: product.title,
                ingredientsText: product.ingredientsText,
                source: .barcode,
                domain: product.domain,
                barcode: product.barcode,
                imageURL: product.imageURL,
                preferences: preferenceProfile
            )
            present(applyingCachedResolutions(to: baseAnalysis, modelContext: modelContext), modelContext: modelContext)
        case .notFound:
            inlineNotice = InlineNotice(text: "No match. Paste ingredients instead.")
            prepareManualEntry(clearingNotice: false)
        case .unavailable:
            inlineNotice = InlineNotice(text: "Lookup unavailable. Paste ingredients instead.")
            prepareManualEntry(clearingNotice: false)
        }
    }

    func setPreference(_ key: PreferenceKey, enabled: Bool, modelContext: ModelContext) {
        var updated = preferenceProfile
        updated.set(key, enabled: enabled)
        preferenceProfile = updated
        persistPreferenceProfile()

        if let activeResult {
            let rebuilt = rebuildAnalysis(from: activeResult, modelContext: modelContext)
            self.activeResult = rebuilt
            save(rebuilt, in: modelContext)
            startResolutionIfNeeded(for: rebuilt, modelContext: modelContext)
        }
    }

    func isFavorite(_ analysis: AnalyzedProduct) -> Bool {
        favoriteKeys.contains(analysis.favoriteKey)
    }

    func setFavorite(_ analysis: AnalyzedProduct, isFavorite: Bool) {
        var updated = favoriteKeys
        if isFavorite {
            updated.insert(analysis.favoriteKey)
        } else {
            updated.remove(analysis.favoriteKey)
        }

        favoriteKeys = updated
        defaults.set(Array(updated).sorted(), forKey: Self.favoriteDefaultsKey)
    }

    func openAlternative(_ analysis: AnalyzedProduct, modelContext: ModelContext) {
        present(rebuildAnalysis(from: analysis, modelContext: modelContext), modelContext: modelContext)
    }

    private func present(_ analysis: AnalyzedProduct, modelContext: ModelContext) {
        resolutionTask?.cancel()
        resolutionTask = nil
        activeResult = analysis
        inlineNotice = nil
        save(analysis, in: modelContext)
        startResolutionIfNeeded(for: analysis, modelContext: modelContext)
    }

    private func save(_ analysis: AnalyzedProduct, in modelContext: ModelContext) {
        do {
            let allRecords = try modelContext.fetch(FetchDescriptor<RecentAnalysisRecord>())
            if let existing = allRecords.first(where: { $0.id == analysis.id }) {
                try existing.update(from: analysis)
            } else {
                let record = try RecentAnalysisRecord(analysis: analysis)
                modelContext.insert(record)
            }

            try modelContext.save()

            let descriptor = FetchDescriptor<RecentAnalysisRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            let all = try modelContext.fetch(descriptor)
            for stale in all.dropFirst(20) {
                modelContext.delete(stale)
            }

            if all.count > 20 {
                try modelContext.save()
            }
        } catch {
            inlineNotice = InlineNotice(text: "Local save failed. Scan still works.")
        }
    }

    private func rebuildAnalysis(from analysis: AnalyzedProduct, modelContext: ModelContext) -> AnalyzedProduct {
        let baseAnalysis = analysisEngine.analyze(
            title: analysis.title,
            ingredientsText: analysis.ingredientsText,
            source: analysis.source,
            domain: analysis.domain,
            barcode: analysis.barcode,
            imageURL: analysis.imageURL,
            preferences: preferenceProfile,
            id: analysis.id,
            createdAt: analysis.createdAt
        )

        return applyingCachedResolutions(to: baseAnalysis, modelContext: modelContext)
    }

    private func applyingCachedResolutions(to analysis: AnalyzedProduct, modelContext: ModelContext) -> AnalyzedProduct {
        let resolvedIngredients = cachedResolutionMap(for: analysis.ingredients, in: modelContext)
        guard !resolvedIngredients.isEmpty else { return analysis }

        return analysisEngine.analyze(
            title: analysis.title,
            ingredientsText: analysis.ingredientsText,
            source: analysis.source,
            domain: analysis.domain,
            barcode: analysis.barcode,
            imageURL: analysis.imageURL,
            preferences: preferenceProfile,
            id: analysis.id,
            createdAt: analysis.createdAt,
            resolvedIngredients: resolvedIngredients
        )
    }

    private func startResolutionIfNeeded(for analysis: AnalyzedProduct, modelContext: ModelContext) {
        guard analysis.ingredients.contains(where: { shouldResolveIngredient($0) }) else { return }

        let resultID = analysis.id
        resolutionTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let resolvedIngredients = await self.resolutionService.resolveUnknowns(
                ingredients: analysis.ingredients,
                domain: analysis.domain
            )

            guard !Task.isCancelled, !resolvedIngredients.isEmpty else { return }

            self.persistResolvedIngredients(resolvedIngredients, in: modelContext)

            guard let activeResult = self.activeResult, activeResult.id == resultID else { return }
            let refreshed = self.rebuildAnalysis(from: activeResult, modelContext: modelContext)
            guard refreshed != activeResult else { return }

            self.activeResult = refreshed
            self.save(refreshed, in: modelContext)
        }
    }

    private func shouldResolveIngredient(_ ingredient: IngredientAnalysis) -> Bool {
        ingredient.confidence == .low || (ingredient.category == .unknown && ingredient.confidence != .high)
    }

    private func cachedResolutionMap(for ingredients: [IngredientAnalysis], in modelContext: ModelContext) -> [String: ResolvedIngredient] {
        guard let records = try? modelContext.fetch(FetchDescriptor<IngredientResolutionRecord>()), !records.isEmpty else {
            return [:]
        }

        let wanted = Set(ingredients.map(\.normalizedName))
        return records.reduce(into: [:]) { partialResult, record in
            guard wanted.contains(record.normalizedName), let resolved = record.decodedResolvedIngredient() else { return }
            partialResult[record.normalizedName] = resolved
        }
    }

    private func persistResolvedIngredients(_ ingredients: [ResolvedIngredient], in modelContext: ModelContext) {
        guard !ingredients.isEmpty else { return }
        guard let records = try? modelContext.fetch(FetchDescriptor<IngredientResolutionRecord>()) else { return }

        var recordsByName: [String: IngredientResolutionRecord] = [:]
        for record in records {
            recordsByName[record.normalizedName] = record
        }

        for ingredient in ingredients {
            if let existing = recordsByName[ingredient.normalizedName] {
                existing.update(from: ingredient)
            } else {
                modelContext.insert(IngredientResolutionRecord(resolvedIngredient: ingredient))
            }
        }

        try? modelContext.save()
    }

    private func inferManualDomain(from ingredientsText: String) -> ProductDomain {
        let lowercased = ingredientsText.lowercased()
        let beautySignals = [
            "parfum", "fragrance", "propylene glycol", "sodium laureth sulfate",
            "sodium lauryl sulfate", "dimethicone", "ceteareth", "peg-", "isododecane"
        ]

        if beautySignals.contains(where: lowercased.contains) {
            return .beauty
        }

        return .custom
    }

    private func persistPreferenceProfile() {
        guard let data = try? JSONEncoder().encode(preferenceProfile) else { return }
        defaults.set(data, forKey: Self.preferenceDefaultsKey)
    }

    private static func loadPreferenceProfile(from defaults: UserDefaults) -> PreferenceProfile {
        guard
            let data = defaults.data(forKey: Self.preferenceDefaultsKey),
            let profile = try? JSONDecoder().decode(PreferenceProfile.self, from: data)
        else {
            return .default
        }

        return profile
    }
}
