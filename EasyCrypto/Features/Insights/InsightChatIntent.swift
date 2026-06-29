//
//  InsightChatIntent.swift
//  EasyCrypto
//

import Foundation

enum InsightChatIntent: Intent {
    /// Prepare the chat: resolve availability before the first message.
    case start
    /// Send a user message and stream the assistant's reply.
    case sendMessage(String)
    /// Clear the conversation and start a fresh session.
    case clear
}
