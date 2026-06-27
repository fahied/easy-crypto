//
//  NotificationLogView.swift
//  EasyCrypto
//

import SwiftUI
import SwiftData

/// Lists every notification that has fired, newest first. Tapping a row opens
/// `NotificationLogDetailView` with the full notification details.
struct NotificationLogView: View {
    let processor: SettingsProcessor

    private var state: SettingsState { processor.state }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if state.notificationLog.isEmpty {
                    emptyState
                } else {
                    ForEach(state.notificationLog) { entry in
                        NavigationLink {
                            NotificationLogDetailView(entry: entry)
                        } label: {
                            NotificationLogRowView(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Notification Log")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await processor.handle(.loadNotificationLog)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No notifications yet")
                .font(.headline)
            Text("Price alerts you receive will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Row

private struct NotificationLogRowView: View {
    let entry: NotificationLogRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: NotificationLogFormat.icon(entry.direction))
                .font(.title3)
                .foregroundStyle(NotificationLogFormat.tint(entry.direction))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(entry.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(entry.firedAt, format: .relative(presentation: .numeric))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .glassCard()
    }
}

// MARK: - Detail

struct NotificationLogDetailView: View {
    let entry: NotificationLogRow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(entry.title, systemImage: NotificationLogFormat.icon(entry.direction))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(NotificationLogFormat.tint(entry.direction))
                    Text(entry.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                VStack(spacing: 0) {
                    detailRow("Asset", entry.asset)
                    Divider()
                    detailRow("Symbol", entry.symbol)
                    Divider()
                    detailRow("Type", NotificationLogFormat.label(entry.direction))
                    Divider()
                    detailRow(NotificationLogFormat.valueLabel(entry.direction), "\(Int(entry.value.rounded())) USDT")
                    Divider()
                    detailRow("Fired", entry.firedAt.formatted(date: .abbreviated, time: .shortened))
                }
                .glassCard()
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Notification")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Formatting

private enum NotificationLogFormat {
    static func icon(_ direction: String) -> String {
        switch direction {
        case "gain": "arrow.up.circle.fill"
        case "loss": "arrow.down.circle.fill"
        case "priceUp": "chart.line.uptrend.xyaxis"
        case "priceDown": "chart.line.downtrend.xyaxis"
        case "candleDrop": "chart.bar.xaxis.ascending.badge.clock"
        default: "bell.fill"
        }
    }

    static func tint(_ direction: String) -> Color {
        switch direction {
        case "gain", "priceUp": Theme.profit
        case "loss", "priceDown", "candleDrop": Theme.loss
        default: Theme.accent
        }
    }

    static func label(_ direction: String) -> String {
        switch direction {
        case "gain": "Profit up"
        case "loss": "Profit down"
        case "priceUp": "Price up"
        case "priceDown": "Price down"
        case "candleDrop": "Candle drop"
        default: direction
        }
    }

    /// Label for the numeric `value` field, which means P&L for the profit alerts
    /// and a price for the price/candle alerts.
    static func valueLabel(_ direction: String) -> String {
        switch direction {
        case "gain", "loss": "Unrealized P&L"
        default: "Price"
        }
    }
}

// MARK: - Previews

#Preview("Notification log") {
    let container = try! ModelContainer(
        for: NotificationLogEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    context.insert(NotificationLogEntry(
        symbol: "BTCUSDT", asset: "BTC", title: "BTC profit up",
        body: "BTC unrealized P&L is now 10000 USDT.", direction: "gain",
        value: 10000, firedAt: Date()
    ))
    context.insert(NotificationLogEntry(
        symbol: "ETHUSDT", asset: "ETH", title: "ETH price down 6.2%",
        body: "ETH price is now 2800 USDT.", direction: "priceDown",
        value: -340, firedAt: Date(timeIntervalSinceNow: -3600)
    ))
    try? context.save()

    let processor = SettingsProcessor(
        keychainService: KeychainService(save: { _, _ in }, load: { nil }, delete: { }),
        apiClient: .noop,
        modelContainer: container
    )
    return NavigationStack {
        NotificationLogView(processor: processor)
    }
    .preferredColorScheme(.dark)
}
