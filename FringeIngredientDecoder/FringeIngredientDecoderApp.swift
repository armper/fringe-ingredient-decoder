import SwiftData
import SwiftUI

@main
struct FringeIngredientDecoderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [RecentAnalysisRecord.self, IngredientResolutionRecord.self, UnmatchedIngredientRecord.self])
    }
}
