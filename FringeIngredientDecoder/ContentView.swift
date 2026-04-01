import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecentAnalysisRecord.createdAt, order: .reverse) private var recentRecords: [RecentAnalysisRecord]
    @StateObject private var store = DecoderStore()
    @FocusState private var manualInputFocused: Bool
    @State private var preferencesPresented = false
    @State private var isScannerPresented = false

    var body: some View {
        switch StorePreviewScenario.current {
        case .live:
            liveBody
        case .home:
            liveBody
                .onAppear {
                    store.cameraState = .unavailable
                    store.dismissResult()
                    store.collapseManualEntry()
                    isScannerPresented = false
                }
        case .result:
            ResultView(
                analysis: PreviewContent.sampleProduct,
                favorite: .constant(false),
                preferenceProfile: .default,
                onOpenAlternative: { _ in },
                onDismiss: {}
            )
        case .detail:
            IngredientDetailView(ingredient: PreviewContent.detailIngredient)
        }
    }

    private var liveBody: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if isScannerPresented {
                BarcodeScannerView(
                    isRunning: scannerIsRunning,
                    onCodeDetected: { code in
                        Task {
                            await store.handleScannedBarcode(code, modelContext: modelContext)
                        }
                    },
                    onStateChanged: { state in
                        store.cameraState = state
                    }
                )
                .ignoresSafeArea()

                AppTheme.scannerShade.ignoresSafeArea()
            } else {
                launchBackdrop
            }

            VStack(spacing: 0) {
                header
                Spacer()
                primaryStage
                Spacer()
                bottomPanel
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if store.isLookingUp {
                lookupOverlay
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { store.activeResult != nil },
            set: { isPresented in
                if !isPresented {
                    store.dismissResult()
                }
            }
        )) {
            if let analysis = store.activeResult {
                ResultView(
                    analysis: analysis,
                    favorite: Binding(
                        get: { store.isFavorite(analysis) },
                        set: { store.setFavorite(analysis, isFavorite: $0) }
                    ),
                    preferenceProfile: store.preferenceProfile,
                    onOpenAlternative: { alternative in
                        store.openAlternative(alternative, modelContext: modelContext)
                    },
                    onDismiss: {
                        store.dismissResult()
                    }
                )
            }
        }
        .sheet(isPresented: $preferencesPresented) {
            PreferenceSheet(
                profile: store.preferenceProfile,
                onToggle: { key, enabled in
                    store.setPreference(key, enabled: enabled, modelContext: modelContext)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
        .onChange(of: store.isManualComposerExpanded) { _, isExpanded in
            manualInputFocused = isExpanded
        }
    }

    private var launchBackdrop: some View {
        ZStack {
            Circle()
                .fill(AppTheme.summaryColor(.simple).opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 36)
                .offset(x: -110, y: -180)

            Circle()
                .fill(AppTheme.scoreAccent(.fair).opacity(0.14))
                .frame(width: 220, height: 220)
                .blur(radius: 34)
                .offset(x: 120, y: -40)

            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 300, height: 300)
                .blur(radius: 52)
                .offset(x: 100, y: 240)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Fringe Ingredient Decoder")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                if let notice = store.inlineNotice {
                    Text(notice.text)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    Text(headerSubtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }

            Spacer(minLength: 0)

            Button {
                preferencesPresented = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(width: 46, height: 46)
                        .background(AppTheme.elevatedFill, in: Circle())

                    if !store.preferenceProfile.enabledKeys.isEmpty {
                        Text("\(store.preferenceProfile.enabledKeys.count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(AppTheme.summaryColor(.simple), in: Capsule())
                            .offset(x: 6, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryStage: some View {
        Group {
            if isScannerPresented {
                scannerFrame
            } else {
                scanLauncher
            }
        }
    }

    private var scannerFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), style: StrokeStyle(lineWidth: 1.2, dash: [12, 10]))
                .frame(maxWidth: 320, maxHeight: 220)

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.clear)
                .frame(width: 320, height: 220)
                .overlay(alignment: .topLeading) { corner }
                .overlay(alignment: .topTrailing) { corner.rotationEffect(.degrees(90)) }
                .overlay(alignment: .bottomLeading) { corner.rotationEffect(.degrees(-90)) }
                .overlay(alignment: .bottomTrailing) { corner.rotationEffect(.degrees(180)) }
        }
        .accessibilityHidden(true)
    }

    private var scanLauncher: some View {
        Button {
            isScannerPresented = true
        } label: {
            VStack(spacing: 18) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(width: 86, height: 86)
                    .background(AppTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                VStack(spacing: 8) {
                    Text("Scan barcode")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("Food or beauty. Paste works too.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 34)
            .decoderPanelStyle(cornerRadius: 34)
        }
        .buttonStyle(.plain)
    }

    private var corner: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 34))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 34, y: 0))
        }
        .stroke(AppTheme.primaryText.opacity(0.92), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        .frame(width: 34, height: 34)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !favoriteAnalyses.isEmpty {
                analysisStrip(title: "Favorites", analyses: favoriteAnalyses)
            }

            if !topRatedAnalyses.isEmpty {
                analysisStrip(title: "Top picks", analyses: topRatedAnalyses)
            }

            if !recentAnalyses.isEmpty {
                analysisStrip(title: "Recent", analyses: Array(recentAnalyses.prefix(8)), showsRelativeDate: true)
            }

            if store.isManualComposerExpanded {
                manualComposer
            } else {
                Button {
                    store.prepareManualEntry()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.primaryText)

                        Text(clipboardLabel)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)

                        Spacer()

                        Image(systemName: "chevron.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .decoderPanelStyle(cornerRadius: 30)
    }

    private func analysisStrip(title: String, analyses: [AnalyzedProduct], showsRelativeDate: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(analyses, id: \.favoriteKey) { analysis in
                        Button {
                            store.openAlternative(analysis, modelContext: modelContext)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    ScoreChip(score: analysis.score, grade: analysis.grade)

                                    if store.isFavorite(analysis) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(AppTheme.summaryColor(.simple))
                                    }

                                    Spacer(minLength: 0)
                                }

                                Text(analysis.title)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.primaryText)
                                    .lineLimit(2)

                                Text(showsRelativeDate ? relativeDate(analysis.createdAt) : analysis.grade.title)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(width: 168, alignment: .leading)
                            .background(AppTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var manualComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $store.manualText)
                .focused($manualInputFocused)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 118)
                .background(AppTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(AppTheme.border)
                )

            HStack(spacing: 12) {
                Button("Close") {
                    store.collapseManualEntry()
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

                Spacer()

                Button {
                    Task {
                        await store.submitManualIngredients(modelContext: modelContext)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.right.circle.fill")
                        Text("Decode")
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(AppTheme.summaryColor(.simple), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var lookupOverlay: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .tint(AppTheme.primaryText)
                    .scaleEffect(1.3)

                Text("Looking up product")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .decoderPanelStyle(cornerRadius: 26)
        }
    }

    private var recentAnalyses: [AnalyzedProduct] {
        recentRecords.compactMap { try? $0.decodedAnalysis() }
    }

    private var favoriteAnalyses: [AnalyzedProduct] {
        Array(uniqueAnalyses(from: recentAnalyses.filter { store.isFavorite($0) }).prefix(6))
    }

    private var topRatedAnalyses: [AnalyzedProduct] {
        Array(
            uniqueAnalyses(from: recentAnalyses)
                .sorted { lhs, rhs in
                    if lhs.score == rhs.score {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return lhs.score > rhs.score
                }
                .prefix(6)
        )
    }

    private func uniqueAnalyses(from analyses: [AnalyzedProduct]) -> [AnalyzedProduct] {
        var seen = Set<String>()
        return analyses.filter { analysis in
            seen.insert(analysis.favoriteKey).inserted
        }
    }

    private var headerSubtitle: String {
        switch store.cameraState {
        case .ready:
            return "Scan food or beauty barcodes. One tap to paste."
        case .denied:
            return "Camera off. Paste ingredients instead."
        case .unavailable:
            return isScannerPresented ? "Camera unavailable. Paste ingredients instead." : "Scan when you want. Paste anytime."
        case .idle:
            return isScannerPresented ? "Scan food or beauty barcodes. One tap to paste." : "Start with a scan or paste ingredients."
        }
    }

    private var scannerIsRunning: Bool {
        isScannerPresented && store.scannerEnabled
    }

    private var clipboardLabel: String {
        UIPasteboard.general.hasStrings ? "Paste ingredients" : "Type ingredients"
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [RecentAnalysisRecord.self, IngredientResolutionRecord.self], inMemory: true)
}

struct ScoreChip: View {
    let score: Int
    let grade: ProductGrade

    var body: some View {
        Text("\(score)")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.scoreAccent(grade))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(AppTheme.scoreAccent(grade).opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(AppTheme.scoreAccent(grade).opacity(0.35)))
    }
}

private struct PreferenceSheet: View {
    let profile: PreferenceProfile
    let onToggle: (PreferenceKey, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 3)
                .fill(AppTheme.tertiaryText)
                .frame(width: 44, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            Text("Alerts")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            Text("Flag ingredients you shop around most often.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            VStack(spacing: 10) {
                ForEach(PreferenceKey.allCases) { key in
                    Toggle(isOn: Binding(
                        get: { profile.isEnabled(key) },
                        set: { onToggle(key, $0) }
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: key.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.primaryText)
                                .frame(width: 28)

                            Text(key.title)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                        }
                    }
                    .tint(AppTheme.summaryColor(.simple))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(AppTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.background.ignoresSafeArea())
    }
}
