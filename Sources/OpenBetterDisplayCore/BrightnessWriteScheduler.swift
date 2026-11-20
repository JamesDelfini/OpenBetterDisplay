import Foundation

@MainActor
public protocol BrightnessWriteCancellable: AnyObject {
    func cancel()
}

@MainActor
public protocol BrightnessWriteScheduling: AnyObject {
    func now() -> TimeInterval
    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> BrightnessWriteCancellable
    func performWrite(
        _ work: @escaping @Sendable () -> BrightnessBackendUsed,
        completion: @escaping @MainActor (BrightnessBackendUsed) -> Void
    )
}

@MainActor
public final class MainQueueBrightnessWriteScheduler: BrightnessWriteScheduling {
    private final class DispatchWorkItemToken: BrightnessWriteCancellable {
        private let workItem: DispatchWorkItem

        init(workItem: DispatchWorkItem) {
            self.workItem = workItem
        }

        func cancel() {
            workItem.cancel()
        }
    }

    private let ddcQueue = DispatchQueue(
        label: "com.openbetterdisplay.ddc-brightness-write",
        qos: .userInitiated
    )

    public init() {}

    public func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    public func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> BrightnessWriteCancellable {
        let item = DispatchWorkItem {
            MainActor.assumeIsolated {
                action()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: item)
        return DispatchWorkItemToken(workItem: item)
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
