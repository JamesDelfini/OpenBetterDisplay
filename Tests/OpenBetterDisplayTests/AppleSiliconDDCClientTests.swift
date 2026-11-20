import Foundation
import XCTest
@testable import OpenBetterDisplayCore

final class AppleSiliconDDCClientTests: XCTestCase {
    func testTransientReadFailureUsesCooldownAndRecoversWithoutPoisoningCache() {
        let clock = TestClock(now: 100.0)
        let transport = FakeDDCTransport()
        let service = DDCResolvedService(
            handle: NSObject(),
            registryPath: "IOService:/dispext0/DCPAVServiceProxy",
            edid: nil
        )
        transport.servicesByDisplayID[20] = service
        transport.nextReadReplies = [nil] // Transient read failure (e.g., monitor waking from standby)

        let client = AppleSiliconDDCClient(
            transport: transport,
            now: { clock.now },
            noServiceCooldown: 5.0,
            transientFailureCooldown: 2.0
        )

        // Initial read fails transiently
        XCTAssertNil(client.readBrightness(for: 20))
        XCTAssertEqual(transport.resolveCallCount, 1)
        XCTAssertEqual(transport.readCallCount, 1)

        // Within cooldown: returns nil without hammering I2C bus
        clock.advance(by: 1.0)
        XCTAssertNil(client.readBrightness(for: 20))
        XCTAssertEqual(transport.readCallCount, 1)

        // After cooldown elapses: monitor is awake and read succeeds on the cached service
        clock.advance(by: 1.5)
        transport.nextReadReplies = [
            DDCProtocol.LuminanceReply(currentValue: 64, maxValue: 100, normalizedLevel: 0.64)
        ]
        let recovered = client.readBrightness(for: 20)
        XCTAssertEqual(recovered?.currentValue, 64)
        XCTAssertEqual(recovered?.maxValue, 100)
        XCTAssertEqual(recovered?.normalizedLevel ?? -1, 0.64, accuracy: 0.0001)
        XCTAssertEqual(transport.readCallCount, 2)
    }

    func testWriteStillAttemptsDDCWithDefaultMaxValue100AfterReadFailure() {
        let clock = TestClock(now: 50.0)
        let transport = FakeDDCTransport()
        let service = DDCResolvedService(
            handle: NSObject(),
            registryPath: "IOService:/dispext0/DCPAVServiceProxy",
            edid: nil
        )
        transport.servicesByDisplayID[20] = service
        transport.nextReadReplies = [nil]
        transport.nextWriteResults = [true]

        let client = AppleSiliconDDCClient(
            transport: transport,
            now: { clock.now },
            noServiceCooldown: 5.0,
            transientFailureCooldown: 2.0
        )

        // Read fails transiently (or monitor does not respond to DDC Read)
        XCTAssertNil(client.readBrightness(for: 20))

        // Immediately afterwards, writeBrightness still attempts DDC write using default maxValue = 100
        let wrote = client.writeBrightness(for: 20, level: 0.55)
        XCTAssertTrue(wrote)
        XCTAssertEqual(transport.writeCalls.count, 1)
        XCTAssertEqual(transport.writeCalls.first?.level ?? -1, 0.55, accuracy: 0.0001)
        XCTAssertEqual(transport.writeCalls.first?.maxValue, 100)
        // Must NOT gate the write on another read attempt
        XCTAssertEqual(transport.readCallCount, 1)
    }

    func testWriteFailureFallsBackDuringCooldownAndRecoversWhenMonitorResponds() {
        let clock = TestClock(now: 10.0)
        let transport = FakeDDCTransport()
        let service = DDCResolvedService(
            handle: NSObject(),
            registryPath: "IOService:/dispext0/DCPAVServiceProxy",
            edid: nil
        )
        transport.servicesByDisplayID[20] = service
        transport.nextWriteResults = [false]

        let client = AppleSiliconDDCClient(
            transport: transport,
            now: { clock.now },
            noServiceCooldown: 5.0,
            transientFailureCooldown: 2.0
        )

        // First write fails -> returns false so driver falls back to software gamma
        XCTAssertFalse(client.writeBrightness(for: 20, level: 0.40))
        XCTAssertEqual(transport.writeCalls.count, 1)

        // Rapid slider drag during cooldown returns false immediately without blocking on I2C
        clock.advance(by: 0.5)
        XCTAssertFalse(client.writeBrightness(for: 20, level: 0.45))
        XCTAssertEqual(transport.writeCalls.count, 1)

        // After cooldown elapses, write re-attempts and succeeds
        clock.advance(by: 2.0)
        transport.nextWriteResults = [true]
        XCTAssertTrue(client.writeBrightness(for: 20, level: 0.60))
        XCTAssertEqual(transport.writeCalls.count, 2)
        XCTAssertEqual(transport.writeCalls.last?.level ?? -1, 0.60, accuracy: 0.0001)
        XCTAssertEqual(transport.writeCalls.last?.maxValue, 100)
    }

    func testDistinguishesNoIOAVServiceFromTransientI2CFailureAndReprobesAfterCooldown() {
        let clock = TestClock(now: 0.0)
        let transport = FakeDDCTransport()
        let client = AppleSiliconDDCClient(
            transport: transport,
            now: { clock.now },
            noServiceCooldown: 5.0,
            transientFailureCooldown: 2.0
        )

        XCTAssertNil(client.readBrightness(for: 30))
        XCTAssertEqual(transport.resolveCallCount, 1)
        XCTAssertEqual(transport.readCallCount, 0)

        // During noServiceCooldown, neither read nor write hammers IORegistry
        clock.advance(by: 2.0)
        XCTAssertFalse(client.writeBrightness(for: 30, level: 0.50))
        XCTAssertEqual(transport.resolveCallCount, 1)
        XCTAssertEqual(transport.writeCalls.count, 0)

        // After noServiceCooldown elapses, client re-probes and binds when service appears
        clock.advance(by: 3.5)
        transport.servicesByDisplayID[30] = DDCResolvedService(
            handle: NSObject(),
            registryPath: "IOService:/dispext1/DCPAVServiceProxy",
            edid: nil
        )
        transport.nextWriteResults = [true]

        XCTAssertTrue(client.writeBrightness(for: 30, level: 0.70))
        XCTAssertEqual(transport.resolveCallCount, 2)
        XCTAssertEqual(transport.writeCalls.count, 1)
    }

    func testSubsequentWritesUseMaxValueLearnedFromSuccessfulRead() {
        let transport = FakeDDCTransport()
        transport.servicesByDisplayID[20] = DDCResolvedService(
            handle: NSObject(),
            registryPath: "IOService:/dispext0/DCPAVServiceProxy",
            edid: nil
        )
        transport.nextReadReplies = [
            DDCProtocol.LuminanceReply(currentValue: 512, maxValue: 1023, normalizedLevel: 512.0 / 1023.0)
        ]
        transport.nextWriteResults = [true]

        let client = AppleSiliconDDCClient(transport: transport)
        let reading = client.readBrightness(for: 20)
        XCTAssertEqual(reading?.maxValue, 1023)

        XCTAssertTrue(client.writeBrightness(for: 20, level: 0.50))
        XCTAssertEqual(transport.writeCalls.count, 1)
        XCTAssertEqual(transport.writeCalls.first?.maxValue, 1023)
    }

    func testInvalidatingDisplayClearsCooldownAndForcesFreshServiceResolution() {
        let clock = TestClock(now: 0.0)
        let transport = FakeDDCTransport()
        let client = AppleSiliconDDCClient(
            transport: transport,
            now: { clock.now },
            noServiceCooldown: 5.0,
            transientFailureCooldown: 2.0
        )

        XCTAssertNil(client.readBrightness(for: 20))
        XCTAssertEqual(transport.resolveCallCount, 1)

        // Display re-enabled/hotplugged -> invalidate clears cooldown immediately
        client.invalidate(displayID: 20)
        transport.servicesByDisplayID[20] = DDCResolvedService(
            handle: NSObject(),
            registryPath: "IOService:/dispext0/DCPAVServiceProxy",
            edid: nil
        )
        transport.nextReadReplies = [
            DDCProtocol.LuminanceReply(currentValue: 80, maxValue: 100, normalizedLevel: 0.80)
        ]

        clock.advance(by: 0.1)
        let reply = client.readBrightness(for: 20)
        XCTAssertEqual(reply?.currentValue, 80)
        XCTAssertEqual(transport.resolveCallCount, 2)
    }
}

private final class TestClock: @unchecked Sendable {
    var now: TimeInterval

    init(now: TimeInterval) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now += interval
    }
}

private final class FakeDDCTransport: DDCTransport, @unchecked Sendable {
    var servicesByDisplayID: [UInt32: DDCResolvedService] = [:]
    var nextReadReplies: [DDCProtocol.LuminanceReply?] = []
    var nextWriteResults: [Bool] = []
    var resolveCallCount = 0
    var readCallCount = 0
    var writeCalls: [(level: Double, maxValue: Int)] = []

    func resolveService(
        for displayID: UInt32,
        excludingClaimedPaths: Set<String>
    ) -> DDCResolvedService? {
        resolveCallCount += 1
        guard let service = servicesByDisplayID[displayID],
              !excludingClaimedPaths.contains(service.registryPath) else {
            return nil
        }
        return service
    }

    func readLuminance(from service: AnyObject) -> DDCProtocol.LuminanceReply? {
        readCallCount += 1
        if !nextReadReplies.isEmpty {
            return nextReadReplies.removeFirst()
        }
        return nil
    }

    func writeLuminance(to service: AnyObject, level: Double, maxValue: Int) -> Bool {
        writeCalls.append((level: level, maxValue: maxValue))
        if !nextWriteResults.isEmpty {
            return nextWriteResults.removeFirst()
        }
        return false
    }
}
