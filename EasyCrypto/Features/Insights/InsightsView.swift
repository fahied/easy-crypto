//
//  InsightsView.swift
//  EasyCrypto
//

import SwiftUI
import SwiftData

struct InsightsView: View {
    @State var processor: InsightsProcessor
    let makeChatProcessor: () -> InsightChatProcessor

    @State private var showingChat = false

    private var state: InsightsState { processor.state }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                headerCard

                switch state.availability {
                case .disabled:
                    messageCard(
                        icon: "sparkles.slash",
                        title: "Insights are turned off",
                        message: "Enable AI insights in Settings to analyze your trading patterns on device."
                    )
                case .unavailable(let reason):
                    messageCard(
                        icon: "exclamationmark.triangle",
                        title: "On-device AI unavailable",
                        message: reason
                    )
                case .ready:
                    if state.items.isEmpty {
                        messageCard(
                            icon: "wand.and.stars",
                            title: "No insights yet",
                            message: "Tap Analyze to generate suggestions from your trade history — all on your device."
                        )
                    } else {
                        ForEach(state.items) { item in
                            insightCard(item)
                        }
                    }
                }

                onDeviceFooter
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .task {
            await processor.handle(.load)
        }
        .sheet(isPresented: $showingChat) {
            NavigationStack {
                InsightChatView(processor: makeChatProcessor())
                    .navigationTitle("Ask AI")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Insights", systemImage: "brain.head.profile")
                .font(.headline)

            Text("Private, on-device analysis of your trading patterns.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let lastGeneratedAt = state.lastGeneratedAt {
                Text("Last updated \(lastGeneratedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                processor.send(.refresh)
            } label: {
                HStack {
                    if state.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(state.isLoading ? "Analyzing…" : "Analyze")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(state.isLoading || state.availability == .disabled)

            Button {
                showingChat = true
            } label: {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("Ask a question")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .disabled(state.availability == .disabled)

            if let error = state.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.loss)
            }
        }
        .glassCard()
    }

    // MARK: - Insight card

    @ViewBuilder
    private func insightCard(_ item: InsightItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon(for: item.category))
                    .foregroundStyle(color(for: item.severity))
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let symbol = item.symbol {
                    Text(symbol)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.15), in: Capsule())
                }
            }

            Text(item.body)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(item.category.rawValue.capitalized)
                .font(.caption2)
                .foregroundStyle(color(for: item.severity))
        }
        .glassCard()
    }

    // MARK: - Message card

    @ViewBuilder
    private func messageCard(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassCard()
    }

    private var onDeviceFooter: some View {
        Label("Processed on device — your trades never leave your iPhone.", systemImage: "lock.shield")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    // MARK: - Styling helpers

    private func icon(for category: InsightCategory) -> String {
        switch category {
        case .concentration: "chart.pie"
        case .performance: "chart.line.uptrend.xyaxis"
        case .behavior: "person.crop.circle.badge.questionmark"
        case .risk: "exclamationmark.shield"
        }
    }

    private func color(for severity: InsightSeverity) -> Color {
        switch severity {
        case .critical: Theme.loss
        case .warning: Theme.accent
        case .info: Theme.profit
        }
    }
}

// MARK: - Preview

#Preview("Insights") {
    let container = try! ModelContainer(
        for: Trade.self, TradingInsight.self, InsightState.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    context.insert(TradingInsight(
        title: "BTC concentration is high",
        body: "Most of your trades are in BTCUSDT. Consider diversifying to reduce single-asset risk.",
        category: "concentration",
        severity: "warning",
        symbol: "BTCUSDT"
    ))
    context.insert(TradingInsight(
        title: "Healthy win rate",
        body: "Your recent sells have mostly closed in profit. Keep following your strategy.",
        category: "performance",
        severity: "info",
        symbol: nil
    ))
    try? context.save()

    let engine = FoundationModelInsightEngine(
        checkAvailability: { .available },
        generate: { _, _ in [] }
    )

    return NavigationStack {
        InsightsView(
            processor: InsightsProcessor(
                modelContainer: container,
                summarizer: TradePatternSummarizer(fifo: .live),
                engine: engine,
                settings: .live(defaults: UserDefaults(suiteName: "preview-insights")!)
            ),
            makeChatProcessor: {
                InsightChatProcessor(
                    modelContainer: container,
                    summarizer: TradePatternSummarizer(fifo: .live),
                    engine: engine,
                    settings: .live(defaults: UserDefaults(suiteName: "preview-insights")!)
                )
            }
        )
        .navigationTitle("Insights")
    }
    .preferredColorScheme(.dark)
}
