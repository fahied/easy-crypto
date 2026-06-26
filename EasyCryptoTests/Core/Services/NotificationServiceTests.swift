//
//  NotificationServiceTests.swift
//  EasyCryptoTests
//

import Testing
@testable import EasyCrypto

@Suite("Given the NotificationService variants")
struct NotificationServiceTests {

    @Test("When using noop, then it reports unauthorized and scheduling is a no-op")
    func noopBehavior() async {
        let service = NotificationService.noop

        #expect(await service.isAuthorized() == false)
        #expect(await service.requestAuthorization() == false)
        await service.scheduleAlert(LocalAlert(id: "x", title: "t", body: "b"))
    }

    @Test("When using preview, then it reports authorized")
    func previewBehavior() async {
        let service = NotificationService.preview

        #expect(await service.isAuthorized() == true)
        #expect(await service.requestAuthorization() == true)
    }
}
