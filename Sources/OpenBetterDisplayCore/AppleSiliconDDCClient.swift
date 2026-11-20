import CoreGraphics
import Foundation
import IOKit

public struct DDCResolvedService: @unchecked Sendable {
    public let handle: AnyObject
    public let registryPath: String
    public let edid: DDCProtocol.ParsedEDID?

    public init(handle: AnyObject, registryPath: String, edid: DDCProtocol.ParsedEDID?) {
        self.handle = handle
        self.registryPath = registryPath
        self.edid = edid
    }
}

public protocol DDCTransport: Sendable {
    func resolveService(
        for displayID: UInt32,
        excludingClaimedPaths: Set<String>
    ) -> DDCResolvedService?
    func readLuminance(from service: AnyObject) -> DDCProtocol.LuminanceReply?
    func writeLuminance(to service: AnyObject, level: Double, maxValue: Int) -> Bool
}

public final class AppleSiliconDDCClient: @unchecked Sendable {
    public static let defaultMaxValue = 100

    private enum DisplayDDCState {
        case serviceAvailable(
            service: DDCResolvedService,
            maxValue: Int?,
            readRetryAfter: TimeInterval?,
            writeRetryAfter: TimeInterval?
        )
        case noService(retryAfter: TimeInterval)
    }

    private struct ResolvedServiceState {
        let service: DDCResolvedService
        let maxValue: Int?
        let readRetryAfter: TimeInterval?
        let writeRetryAfter: TimeInterval?
    }

    private let transport: DDCTransport
    private let now: @Sendable () -> TimeInterval
    private let noServiceCooldown: TimeInterval
    private let transientFailureCooldown: TimeInterval
    private let stateLock = NSLock()
    private var states: [UInt32: DisplayDDCState] = [:]

    public init(
        transport: DDCTransport,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        noServiceCooldown: TimeInterval = 5.0,
        transientFailureCooldown: TimeInterval = 2.0
    ) {
        self.transport = transport
        self.now = now
        self.noServiceCooldown = max(0, noServiceCooldown)
        self.transientFailureCooldown = max(0, transientFailureCooldown)
    }

    public func readBrightness(for displayID: UInt32) -> DDCProtocol.LuminanceReply? {
        stateLock.lock()
        defer { stateLock.unlock() }

        let currentTime = now()
        guard let resolved = resolveOrGetServiceLocked(for: displayID, currentTime: currentTime) else {
            return nil
        }

        if let readRetryAfter = resolved.readRetryAfter, currentTime < readRetryAfter {
            return nil
        }

        if let reply = transport.readLuminance(from: resolved.service.handle) {
            states[displayID] = .serviceAvailable(
                service: resolved.service,
                maxValue: reply.maxValue,
                readRetryAfter: nil,
                writeRetryAfter: nil
            )
            return reply
        }

        states[displayID] = .serviceAvailable(
            service: resolved.service,
            maxValue: resolved.maxValue,
            readRetryAfter: currentTime + transientFailureCooldown,
            writeRetryAfter: resolved.writeRetryAfter
        )
        return nil
    }

    public func writeBrightness(for displayID: UInt32, level: Double) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        let currentTime = now()
        guard let resolved = resolveOrGetServiceLocked(for: displayID, currentTime: currentTime) else {
            return false
        }

        if let writeRetryAfter = resolved.writeRetryAfter, currentTime < writeRetryAfter {
            return false
        }

        let effectiveMaxValue = resolved.maxValue ?? Self.defaultMaxValue
        if transport.writeLuminance(to: resolved.service.handle, level: level, maxValue: effectiveMaxValue) {
            states[displayID] = .serviceAvailable(
                service: resolved.service,
                maxValue: resolved.maxValue,
                readRetryAfter: resolved.readRetryAfter,
                writeRetryAfter: nil
            )
            return true
        }

        let claimedPaths = claimedRegistryPathsLocked(excluding: displayID)
        if let fresh = transport.resolveService(for: displayID, excludingClaimedPaths: claimedPaths) {
            if fresh.registryPath != resolved.service.registryPath,
               transport.writeLuminance(to: fresh.handle, level: level, maxValue: Self.defaultMaxValue) {
                states[displayID] = .serviceAvailable(
                    service: fresh,
                    maxValue: nil,
                    readRetryAfter: nil,
                    writeRetryAfter: nil
                )
                return true
            }
            states[displayID] = .serviceAvailable(
                service: fresh,
                maxValue: resolved.maxValue,
                readRetryAfter: resolved.readRetryAfter,
                writeRetryAfter: currentTime + transientFailureCooldown
            )
        } else {
            states[displayID] = .noService(retryAfter: currentTime + noServiceCooldown)
        }

        return false
    }

    public func readEDIDProductName(for displayID: UInt32) -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }

        let currentTime = now()
        guard let resolved = resolveOrGetServiceLocked(for: displayID, currentTime: currentTime),
              let name = resolved.service.edid?.productName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }
        return name
    }

    public func invalidate(displayID: UInt32) {
        stateLock.lock()
        states.removeValue(forKey: displayID)
        stateLock.unlock()
    }

    public func pruneDisplays(keeping activeDisplayIDs: Set<UInt32>) {
        stateLock.lock()
        states = states.filter { activeDisplayIDs.contains($0.key) }
        stateLock.unlock()
    }

    private func resolveOrGetServiceLocked(
        for displayID: UInt32,
        currentTime: TimeInterval
    ) -> ResolvedServiceState? {
        if let cached = states[displayID] {
            switch cached {
            case .serviceAvailable(let service, let maxValue, let readRetryAfter, let writeRetryAfter):
                return ResolvedServiceState(
                    service: service,
                    maxValue: maxValue,
                    readRetryAfter: readRetryAfter,
                    writeRetryAfter: writeRetryAfter
                )
            case .noService(let retryAfter):
                if currentTime < retryAfter {
                    return nil
                }
            }
        }

        let claimedPaths = claimedRegistryPathsLocked(excluding: displayID)
        guard let resolved = transport.resolveService(for: displayID, excludingClaimedPaths: claimedPaths) else {
            states[displayID] = .noService(retryAfter: currentTime + noServiceCooldown)
            return nil
        }

        states[displayID] = .serviceAvailable(
            service: resolved,
            maxValue: nil,
            readRetryAfter: nil,
            writeRetryAfter: nil
        )
        return ResolvedServiceState(
            service: resolved,
            maxValue: nil,
            readRetryAfter: nil,
            writeRetryAfter: nil
        )
    }

    private func claimedRegistryPathsLocked(excluding displayID: UInt32) -> Set<String> {
        Set(states.compactMap { entryDisplayID, state in
            guard entryDisplayID != displayID else { return nil }
            if case .serviceAvailable(let service, _, _, _) = state {
                return service.registryPath
            }
            return nil
        })
    }
}

internal final class IOAVServiceDDCTransport: DDCTransport, @unchecked Sendable {
    private static let ioAVServiceLocationEmbedded: UInt32 = 1

    private typealias IOAVServiceCreateWithServiceFn = @convention(c) (
        CFAllocator?,
        io_service_t
    ) -> Unmanaged<CFTypeRef>?

    private typealias IOAVServiceReadI2CFn = @convention(c) (
        CFTypeRef,
        UInt32,
        UInt32,
        UnsafeMutableRawPointer,
        UInt32
    ) -> IOReturn

    private typealias IOAVServiceWriteI2CFn = @convention(c) (
        CFTypeRef,
        UInt32,
        UInt32,
        UnsafeRawPointer,
        UInt32
    ) -> IOReturn

    private typealias IOAVServiceCopyEDIDFn = @convention(c) (
        CFTypeRef,
        UnsafeMutablePointer<Unmanaged<CFData>?>
    ) -> IOReturn

    private typealias IOAVServiceGetLocationFn = @convention(c) (
        CFTypeRef
    ) -> UInt32

    private let ioAVServiceCreateWithService: IOAVServiceCreateWithServiceFn?
    private let ioAVServiceReadI2C: IOAVServiceReadI2CFn?
    private let ioAVServiceWriteI2C: IOAVServiceWriteI2CFn?
    private let ioAVServiceCopyEDID: IOAVServiceCopyEDIDFn?
    private let ioAVServiceGetLocation: IOAVServiceGetLocationFn?

    private let matchTargetProvider: @Sendable (CGDirectDisplayID) -> DDCProtocol.DisplayMatchTarget
    private let externalDisplayCountProvider: @Sendable () -> Int

    init(
        matchTargetProvider: @escaping @Sendable (CGDirectDisplayID) -> DDCProtocol.DisplayMatchTarget,
        externalDisplayCountProvider: @escaping @Sendable () -> Int
    ) {
        self.matchTargetProvider = matchTargetProvider
        self.externalDisplayCountProvider = externalDisplayCountProvider

        let ioKit = DynamicLibrary(path: "/System/Library/Frameworks/IOKit.framework/IOKit")
        self.ioAVServiceCreateWithService = ioKit.symbol("IOAVServiceCreateWithService")
        self.ioAVServiceReadI2C = ioKit.symbol("IOAVServiceReadI2C")
        self.ioAVServiceWriteI2C = ioKit.symbol("IOAVServiceWriteI2C")
        self.ioAVServiceCopyEDID = ioKit.symbol("IOAVServiceCopyEDID")
        self.ioAVServiceGetLocation = ioKit.symbol("IOAVServiceGetLocation")
    }

    func resolveService(
        for displayID: UInt32,
        excludingClaimedPaths claimedPaths: Set<String>
    ) -> DDCResolvedService? {
        guard CGDisplayIsBuiltin(displayID) == 0,
              let ioAVServiceCreateWithService else {
            return nil
        }

        let target = matchTargetProvider(displayID)

        var iterator: io_iterator_t = 0
        let matchResult = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("DCPAVServiceProxy"),
            &iterator
        )
        guard matchResult == kIOReturnSuccess, iterator != 0 else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var candidates: [(resolved: DDCResolvedService, candidate: DDCProtocol.DDCServiceCandidate)] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            if let location = readStringProperty("Location", from: service),
               location == "Embedded" {
                continue
            }

            guard let unmanagedAVService = ioAVServiceCreateWithService(kCFAllocatorDefault, service) else {
                continue
            }
            let avService: CFTypeRef = unmanagedAVService.takeRetainedValue()

            if let ioAVServiceGetLocation,
               ioAVServiceGetLocation(avService) == Self.ioAVServiceLocationEmbedded {
                continue
            }

            let registryPath = readRegistryPath(for: service)
            var parsedEDID: DDCProtocol.ParsedEDID?
            if let ioAVServiceCopyEDID {
                var unmanagedEDID: Unmanaged<CFData>?
                if ioAVServiceCopyEDID(avService, &unmanagedEDID) == kIOReturnSuccess,
                   let edidData = unmanagedEDID?.takeRetainedValue() as Data? {
                    parsedEDID = DDCProtocol.parseEDID(edidData)
                }
            }

            let resolved = DDCResolvedService(
                handle: avService,
                registryPath: registryPath,
                edid: parsedEDID
            )
            let candidate = DDCProtocol.DDCServiceCandidate(
                registryPath: registryPath,
                edid: parsedEDID
            )
            candidates.append((resolved: resolved, candidate: candidate))
        }

        guard !candidates.isEmpty else { return nil }

        let scored = candidates.compactMap { item -> (resolved: DDCResolvedService, score: Int, isClaimed: Bool)? in
            guard let score = DDCProtocol.matchScore(target: target, candidate: item.candidate) else {
                return nil
            }
            return (
                resolved: item.resolved,
                score: score,
                isClaimed: claimedPaths.contains(item.resolved.registryPath)
            )
        }

        if let best = scored.max(by: { lhs, rhs in
            if lhs.isClaimed != rhs.isClaimed {
                return lhs.isClaimed && !rhs.isClaimed
            }
            return lhs.score < rhs.score
        }) {
            return best.resolved
        }

        let externalDisplayCount = externalDisplayCountProvider()
        let unclaimedCandidates = candidates.filter { !claimedPaths.contains($0.resolved.registryPath) }
        if externalDisplayCount == 1, unclaimedCandidates.count == 1, let only = unclaimedCandidates.first {
            return only.resolved
        }

        return nil
    }

    func readLuminance(from service: AnyObject) -> DDCProtocol.LuminanceReply? {
        guard let ioAVServiceReadI2C else { return nil }

        let request = DDCProtocol.makeGetLuminancePacket()
        var reply = [UInt8](repeating: 0, count: 11)

        for attempt in 0..<3 {
            guard writePacketWithRetry(avService: service, packet: request) else {
                if attempt < 2 {
                    usleep(20_000)
                }
                continue
            }

            usleep(45_000)
            for idx in reply.indices {
                reply[idx] = 0
            }

            let readStatus = ioAVServiceReadI2C(
                service,
                DDCProtocol.chipAddress,
                DDCProtocol.readDataAddress,
                &reply,
                UInt32(reply.count)
            )
            if readStatus == kIOReturnSuccess,
               let parsed = DDCProtocol.parseLuminanceReply(reply) {
                return parsed
            }

            if attempt < 2 {
                usleep(20_000)
            }
        }

        return nil
    }

    func writeLuminance(to service: AnyObject, level: Double, maxValue: Int) -> Bool {
        let packet = DDCProtocol.makeSetLuminancePacket(level: level, maxValue: maxValue)
        return writePacketWithRetry(avService: service, packet: packet)
    }

    private func writePacketWithRetry(avService: CFTypeRef, packet: [UInt8]) -> Bool {
        guard let ioAVServiceWriteI2C else { return false }

        var mutablePacket = packet
        var writeSucceeded = false
        for cycle in 0..<2 {
            let status = ioAVServiceWriteI2C(
                avService,
                DDCProtocol.chipAddress,
                DDCProtocol.writeDataAddress,
                &mutablePacket,
                UInt32(mutablePacket.count)
            )
            if status == kIOReturnSuccess {
                writeSucceeded = true
            }
            if cycle == 0 {
                usleep(10_000)
            }
        }
        return writeSucceeded
    }

    private func readStringProperty(_ key: String, from entry: io_registry_entry_t) -> String? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String
    }

    private func readRegistryPath(for entry: io_registry_entry_t) -> String {
        var pathBuffer = [CChar](repeating: 0, count: 512)
        let status = IORegistryEntryGetPath(entry, kIOServicePlane, &pathBuffer)
        guard status == kIOReturnSuccess else { return "" }
        return String(cString: pathBuffer)
    }
}
