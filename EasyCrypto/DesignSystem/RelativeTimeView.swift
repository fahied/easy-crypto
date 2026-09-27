//
//  RelativeTimeView.swift
//  EasyCrypto
//
//  Auto-updating relative timestamp. Recomputes the relative string every 15 seconds
//  so labels like "2 min ago" tick forward without the parent view having to manage
//  a timer.

import SwiftUI
import Combine

struct RelativeTimeView: View {
    let timestamp: Date

    @State private var tick = 0
    private let tickInterval: TimeInterval = 15

    var body: some View {
        let absoluteTime = timestamp.formatted(date: .omitted, time: .standard)
        Text("Updated \(timestamp.formatted(.relative(presentation: .named))) (\(absoluteTime))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .onReceive(Timer.publish(every: tickInterval, on: .main, in: .common).autoconnect()) { _ in
                tick += 1
            }
    }
}

#Preview("Relative Time") {
    VStack(spacing: 16) {
        RelativeTimeView(timestamp: Date().addingTimeInterval(-30))
        RelativeTimeView(timestamp: Date().addingTimeInterval(-3600 * 2))
        RelativeTimeView(timestamp: Date().addingTimeInterval(-86400))
    }
    .padding()
    .preferredColorScheme(.dark)
}
