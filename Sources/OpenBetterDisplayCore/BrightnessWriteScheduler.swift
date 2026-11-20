import Foundation

@MainActor
public protocol BrightnessWriteScheduling: AnyObject {
    func now() -> TimeInterval
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyObject
    func cancel(_ token: AnyObject)
    func performWrite(
        _ work: @escaping @Sendable () -> BrightnessBackendUsed,
        completion: @escaping @MainActor (BrightnessBackendUsed) -> Void
    )
}

@MainActor
public final class MainQueueBrightnessWriteScheduler: BrightnessWriteScheduling {
    private let ddcQueue = DispatchQueue(
        label: "com.openbetterdisplay.ddc-brightness-write",
        qos: .userInitiated
    )

    public init() {}

    public func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    public func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyObject {
        let item = DispatchWorkItem {
            MainActor.assumeIsolated {
                action()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: item)
        return item
    }

    public func cancel(_ token: AnyObject) {
        (token as? DispatchWorkItem)?.cancel()
    }

    public func performWrite(
        _ work: @escaping @Sendable () -> BrightnessBackendUsed,
        completion: @escaping @MainActor (BrightnessBackendUsed) -> Void
    ) {
        ddcQueue.async {
            let backend = work()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion(backend)
                }
            }
        }
    }
}

@MainActor
public final class ImmediateBrightnessWriteScheduler: BrightnessWriteScheduling {
    public init() {}

    public func now() -> TimeInterval {
        0
    }

    public func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyObject {
        action()
        return NSObject()
    }

    public func cancel(_ token: AnyObject) {}

    public func performWrite(
        _ work: @escaping @Sendable () -> BrightnessBackendUsed,
        completion: @escaping @MainActor (BrightnessBackendUsed) -> Void
    ) {
        completion(work())
    }
}
