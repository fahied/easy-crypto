//
//  ProcessorTests.swift
//  EasyCryptoTests
//

import Testing
import Foundation
import Observation
@testable import EasyCrypto

// MARK: - Test Fixtures

enum CounterIntent: Intent {
    case increment
    case decrement
    case reset
    case setError(String)
    case clearError
}

struct CounterState: ViewState {
    var count: Int = 0
    var error: String?
}

@Observable
class CounterProcessor: Processor {
    var state = CounterState()

    func handle(_ intent: CounterIntent) async {
        switch intent {
        case .increment:
            state.count += 1
        case .decrement:
            state.count -= 1
        case .reset:
            state.count = 0
            state.error = nil
        case .setError(let message):
            state.error = message
        case .clearError:
            state.error = nil
        }
    }
}

// MARK: - Tests

@Suite("Given a Processor with initial state")
struct ProcessorInitTests {

    @Test("Then state has default values")
    func initialState() {
        let processor = CounterProcessor()
        #expect(processor.state.count == 0)
        #expect(processor.state.error == nil)
    }
}

@Suite("Given a Processor handling intents directly")
struct IntentHandlingTests {

    @Test("When handling increment, then count increases by 1")
    func increment() async {
        let processor = CounterProcessor()
        await processor.handle(.increment)
        #expect(processor.state.count == 1)
    }

    @Test("When handling decrement, then count decreases by 1")
    func decrement() async {
        let processor = CounterProcessor()
        await processor.handle(.decrement)
        #expect(processor.state.count == -1)
    }

    @Test("When handling reset after mutations, then count returns to zero and error clears")
    func reset() async {
        let processor = CounterProcessor()
        await processor.handle(.increment)
        await processor.handle(.increment)
        await processor.handle(.setError("oops"))
        await processor.handle(.reset)
        #expect(processor.state.count == 0)
        #expect(processor.state.error == nil)
    }

    @Test("When handling setError, then error is populated")
    func setError() async {
        let processor = CounterProcessor()
        await processor.handle(.setError("something failed"))
        #expect(processor.state.error == "something failed")
    }

    @Test("When handling clearError, then error becomes nil")
    func clearError() async {
        let processor = CounterProcessor()
        await processor.handle(.setError("err"))
        await processor.handle(.clearError)
        #expect(processor.state.error == nil)
    }

    @Test("When handling multiple intents sequentially, then state accumulates correctly")
    func multipleSequential() async {
        let processor = CounterProcessor()
        await processor.handle(.increment)
        await processor.handle(.increment)
        await processor.handle(.increment)
        await processor.handle(.decrement)
        #expect(processor.state.count == 2)
    }
}

@Suite("Given the Processor send method")
struct SendDispatchTests {

    @Test("When send is called, then intent is handled asynchronously")
    func sendDispatches() async throws {
        let processor = CounterProcessor()
        processor.send(.increment)
        try await Task.sleep(for: .milliseconds(50))
        #expect(processor.state.count == 1)
    }

    @Test("When send is called multiple times, then all intents are processed")
    func sendMultiple() async throws {
        let processor = CounterProcessor()
        processor.send(.increment)
        processor.send(.increment)
        processor.send(.decrement)
        try await Task.sleep(for: .milliseconds(100))
        #expect(processor.state.count == 1)
    }
}

@Suite("Given protocol conformance")
struct ProtocolConformanceTests {

    @Test("Then processor conforms to Observable")
    func observableConformance() {
        let processor = CounterProcessor()
        let _: any Observable = processor
        #expect(true)
    }

    @Test("Then processor conforms to Processor protocol with correct associated types")
    func processorConformance() {
        let processor = CounterProcessor()
        let _: any Processor<CounterState, CounterIntent> = processor
        #expect(true)
    }

    @Test("Then intent conforms to Sendable")
    func intentSendable() {
        let intent: any Sendable = CounterIntent.increment
        _ = intent
        #expect(true)
    }
}
