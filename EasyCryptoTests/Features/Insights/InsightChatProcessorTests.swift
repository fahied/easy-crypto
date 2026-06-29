//
//  InsightChatProcessorTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
import SwiftData
@testable import EasyCrypto

@Suite("Given the Insight chat processor")
@MainActor
struct InsightChatProcessorTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Fake responder yielding canned cumulative snapshots; records captured input.
    private final class FakeChatResponder: InsightChatResponder {
        private(set) var capturedMessages: [String] = []
        private let chunks: [String]
        private let failure: Error?

        init(chunks: [String], failure: Error? = nil) {
            self.chunks = chunks
            self.failure = failure
        }

        func reply(to message: String) -> AsyncThrowingStream<String, Error> {
            capturedMessages.append(message)
            let chunks = chunks
            let failure = failure
            return AsyncThrowingStream { continuation in
                for chunk in chunks { continuation.yield(chunk) }
                if let failure {
                    continuation.finish(throwing: failure)
                } else {
                    continuation.finish()
                }
            }
        }
    }

    private struct ChatError: Error {}

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Trade.self, TradingInsight.self, InsightState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func settings(_ enabled: Bool) -> InsightSettingsStore {
        let defaults = UserDefaults(suiteName: "test-chat-\(UUID().uuidString)")!
        defaults.set(enabled, forKey: InsightSettingsStore.key)
        return .live(defaults: defaults)
    }

    private func makeProcessor(
        container: ModelContainer,
        responderFactory: @escaping (TradeSummary) -> any InsightChatResponder,
        enabled: Bool = true,
        availability: FoundationModelInsightEngine.Availability = .available
    ) -> InsightChatProcessor {
        let engine = FoundationModelInsightEngine(checkAvailability: { availability }, generate: { _, _ in [] })
        return InsightChatProcessor(
            modelContainer: container,
            summarizer: TradePatternSummarizer(fifo: .live),
            engine: engine,
            makeResponder: responderFactory,
            settings: settings(enabled),
            now: { self.now }
        )
    }

    private func insertTrade(_ context: ModelContext, id: Int64, asset: String) {
        context.insert(Trade(
            binanceTradeId: id, symbol: "\(asset)USDT", asset: asset,
            price: 100, quantity: 1, quoteQuantity: 100,
            commission: 0, commissionAsset: "USDT",
            timestamp: now, isBuyer: true, orderId: id
        ))
    }

    @Test("When a message is sent, then user + assistant messages appear and stream completes")
    func sendStreamsReply() async throws {
        let container = try makeContainer()
        let fake = FakeChatResponder(chunks: ["Hel", "Hello, your win rate is solid."])
        let processor = makeProcessor(container: container, responderFactory: { _ in fake })

        await processor.handle(.sendMessage("how am I doing?"))

        #expect(processor.state.messages.count == 2)
        #expect(processor.state.messages[0].role == .user)
        #expect(processor.state.messages[0].text == "how am I doing?")
        #expect(processor.state.messages[1].role == .assistant)
        #expect(processor.state.messages[1].text == "Hello, your win rate is solid.")  // final cumulative
        #expect(processor.state.isResponding == false)
        #expect(processor.state.inputText == "")
        #expect(fake.capturedMessages == ["how am I doing?"])
    }

    @Test("When the responder is built, then it is grounded in the trade summary only")
    func responderGroundedInSummary() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertTrade(context, id: 1, asset: "BTC")
        insertTrade(context, id: 2, asset: "ETH")
        try context.save()

        var capturedSummary: TradeSummary?
        let processor = makeProcessor(container: container, responderFactory: { summary in
            capturedSummary = summary
            return FakeChatResponder(chunks: ["ok"])
        })

        await processor.handle(.sendMessage("hi"))

        #expect(capturedSummary?.totalTrades == 2)
        #expect(capturedSummary?.symbolCount == 2)
    }

    @Test("When the feature is disabled, then sending does nothing")
    func disabledBlocksSend() async throws {
        let container = try makeContainer()
        let fake = FakeChatResponder(chunks: ["nope"])
        let processor = makeProcessor(container: container, responderFactory: { _ in fake }, enabled: false)

        await processor.handle(.sendMessage("hi"))

        #expect(processor.state.availability == .disabled)
        #expect(processor.state.messages.isEmpty)
        #expect(fake.capturedMessages.isEmpty)
    }

    @Test("When the model is unavailable, then sending is blocked")
    func unavailableBlocksSend() async throws {
        let container = try makeContainer()
        let fake = FakeChatResponder(chunks: ["nope"])
        let processor = makeProcessor(
            container: container,
            responderFactory: { _ in fake },
            availability: .unavailable(reason: "Apple Intelligence off")
        )

        await processor.handle(.sendMessage("hi"))

        #expect(processor.state.availability == .unavailable(reason: "Apple Intelligence off"))
        #expect(processor.state.messages.isEmpty)
        #expect(fake.capturedMessages.isEmpty)
    }

    @Test("When the reply fails before any text, then the placeholder is dropped and an error is set")
    func failureDropsEmptyPlaceholder() async throws {
        let container = try makeContainer()
        let fake = FakeChatResponder(chunks: [], failure: ChatError())
        let processor = makeProcessor(container: container, responderFactory: { _ in fake })

        await processor.handle(.sendMessage("hi"))

        #expect(processor.state.messages.count == 1)  // only the user message remains
        #expect(processor.state.messages.first?.role == .user)
        #expect(processor.state.error != nil)
        #expect(processor.state.isResponding == false)
    }

    @Test("When cleared, then messages reset")
    func clearResetsConversation() async throws {
        let container = try makeContainer()
        let processor = makeProcessor(container: container, responderFactory: { _ in FakeChatResponder(chunks: ["hi there"]) })

        await processor.handle(.sendMessage("hello"))
        #expect(processor.state.messages.count == 2)

        await processor.handle(.clear)
        #expect(processor.state.messages.isEmpty)
    }
}
