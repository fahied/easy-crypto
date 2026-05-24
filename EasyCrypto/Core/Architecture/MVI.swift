//
//  MVI.swift
//  EasyCrypto
//

import Observation

// MARK: - Intent

/// Marker protocol for MVI intent types. Conforming types are typically enums.
protocol Intent: Sendable {}

// MARK: - ViewState

/// Marker protocol for MVI view state types. Conforming types are typically structs.
protocol ViewState {}

// MARK: - Processor

/// Base protocol for MVI processors.
///
/// Processors are `@Observable` classes that:
/// - Hold a single `state` property as the source of truth
/// - Accept intents via `send(_:)` (fire-and-forget, bridges sync → async)
/// - Handle intents in `handle(_:)` (async, performs side effects and updates state)
///
/// Concrete processors must be annotated with `@Observable`.
protocol Processor<State, Action>: AnyObject, Observable {
    associatedtype State: ViewState
    associatedtype Action: Intent

    var state: State { get set }

    /// Dispatches an intent for asynchronous handling.
    /// Default implementation creates a `Task` that calls `handle(_:)`.
    func send(_ intent: Action)

    /// Handles an intent asynchronously. Implement in concrete processors.
    func handle(_ intent: Action) async
}

extension Processor {
    func send(_ intent: Action) {
        Task { await handle(intent) }
    }
}
