//
//  InsightChatState.swift
//  EasyCrypto
//

import Foundation

struct InsightChatState: ViewState {
    var messages: [InsightChatMessage] = []
    var inputText: String = ""
    var isResponding: Bool = false
    var availability: InsightsAvailability = .ready
    var error: String?
}
