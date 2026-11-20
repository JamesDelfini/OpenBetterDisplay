import AppKit
import CoreGraphics
import Foundation

@MainActor
public final class DisplayReconfigurationObserver {
    private let onReconfigure: @MainActor () -> Void
    private nonisolated(unsafe) var notificationObserver: NSObjectProtocol?
    private nonisolated(unsafe) var isRegisteredCallback = false

    public init(onReconfigure: @escaping @MainActor () -> Void) {
        self.onReconfigure = onReconfigure
        start()
    }

    deinit {
        stop()
    }

    public func start() {
        guard !isRegisteredCallback else { return }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(Self.reconfigurationCallback, pointer)
        isRegisteredCallback = true

        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onReconfigure()
            }
        }
    }

    nonisolated public func stop() {
        if isRegisteredCallback {
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            CGDisplayRemoveReconfigurationCallback(Self.reconfigurationCallback, pointer)
            isRegisteredCallback = false
        }
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
            self.notificationObserver = nil
        }
    }

    nonisolated private static let reconfigurationCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
        let observer = Unmanaged<DisplayReconfigurationObserver>.fromOpaque(userInfo).takeUnretainedValue()
        Task { @MainActor in
            observer.onReconfigure()
        }
    }
}
