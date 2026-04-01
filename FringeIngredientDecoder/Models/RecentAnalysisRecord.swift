import Foundation
import SwiftData

@Model
final class RecentAnalysisRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var sourceRaw: String
    var createdAt: Date
    var barcode: String?
    var snapshotData: Data

    init(analysis: AnalyzedProduct) throws {
        self.id = analysis.id
        self.title = analysis.title
        self.sourceRaw = analysis.source.rawValue
        self.createdAt = analysis.createdAt
        self.barcode = analysis.barcode
        self.snapshotData = try JSONEncoder().encode(analysis)
    }

    func update(from analysis: AnalyzedProduct) throws {
        title = analysis.title
        sourceRaw = analysis.source.rawValue
        createdAt = analysis.createdAt
        barcode = analysis.barcode
        snapshotData = try JSONEncoder().encode(analysis)
    }

    func decodedAnalysis() throws -> AnalyzedProduct {
        try JSONDecoder().decode(AnalyzedProduct.self, from: snapshotData)
    }
}
