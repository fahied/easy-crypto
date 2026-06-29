//
//  InsightChatView.swift
//  EasyCrypto
//

import SwiftUI
import SwiftData

struct InsightChatView: View {
    @State var processor: InsightChatProcessor

    private var state: InsightChatState { processor.state }

    var body: some View {
        VStack(spacing: 0) {
            switch state.availability {
            case .disabled:
                statusView(
                    icon: "sparkles.slash",
                    title: "Insights are turned off",
                    message: "Enable AI insights in Settings to chat about your trading."
                )
            case .unavailable(let reason):
                statusView(
                    icon: "exclamationmark.triangle",
                    title: "On-device AI unavailable",
                    message: reason
                )
            case .ready:
                conversation
                inputBar
            }
        }
        .task {
            await processor.handle(.start)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { processor.send(.clear) }
                    .disabled(state.messages.isEmpty || state.isResponding)
            }
        }
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if state.messages.isEmpty {
                        emptyPrompt
                    }
                    ForEach(state.messages) { message in
                        bubble(message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
            .onChange(of: state.messages.last?.text) { _, _ in
                if let last = state.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: InsightChatMessage) -> some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 40) }
            Group {
                if message.text.isEmpty && message.role == .assistant {
                    typingIndicator
                } else {
                    Text(message.text)
                        .font(.callout)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isUser ? Theme.accent.opacity(0.18) : Color.secondary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
            )
            .foregroundStyle(isUser ? Color.primary : .primary)
            if !isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ProgressView().controlSize(.small)
            Text("Thinking…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask about your trading")
                .font(.headline)
            Text("e.g. \"What's my biggest risk?\" or \"How can I improve my win rate?\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label("Answers are generated on your device.", systemImage: "lock.shield")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(spacing: 4) {
            if let error = state.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.loss)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            HStack(spacing: 8) {
                TextField("Ask a question…", text: Binding(
                    get: { state.inputText },
                    set: { processor.state.inputText = $0 }
                ), axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .tint(Theme.accent)
                .disabled(!canSend)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var canSend: Bool {
        !state.isResponding
            && !state.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        processor.send(.sendMessage(state.inputText))
    }

    // MARK: - Status

    @ViewBuilder
    private func statusView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview("Insight chat") {
    final class StubResponder: InsightChatResponder {
        func reply(to message: String) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield("Your trading is concentrated in BTC.")
                continuation.yield("Your trading is concentrated in BTC. Consider diversifying.")
                continuation.finish()
            }
        }
    }

    let container = try! ModelContainer(
        for: Trade.self, TradingInsight.self, InsightState.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let engine = FoundationModelInsightEngine(checkAvailability: { .available }, generate: { _, _ in [] })

    return NavigationStack {
        InsightChatView(
            processor: InsightChatProcessor(
                modelContainer: container,
                summarizer: TradePatternSummarizer(fifo: .live),
                engine: engine,
                makeResponder: { _ in StubResponder() },
                settings: .live(defaults: UserDefaults(suiteName: "preview-chat")!)
            )
        )
        .navigationTitle("Ask AI")
    }
    .preferredColorScheme(.dark)
}
