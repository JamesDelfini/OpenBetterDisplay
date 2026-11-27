import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import IOKit.hid
import IOKit.hidsystem

public protocol AccessibilityPollingCancellable: AnyObject, Sendable {
    nonisolated func cancel()
}

@MainActor
public protocol AccessibilityPollingScheduling: AnyObject {
    func scheduleRepeating(
        interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> AccessibilityPollingCancellable
}

@MainActor
private final class DispatchAccessibilityPollingScheduler: AccessibilityPollingScheduling {
    private final class Token: AccessibilityPollingCancellable, @unchecked Sendable {
        private let lock = NSLock()
        private var source: DispatchSourceTimer?

        init(source: DispatchSourceTimer) {
            self.source = source
        }

        nonisolated func cancel() {
            lock.lock()
            let current = source
            source = nil
            lock.unlock()
            current?.cancel()
        }
    }

    func scheduleRepeating(
        interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> AccessibilityPollingCancellable {
        let clampedInterval = max(0.1, interval)
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(
            deadline: .now() + clampedInterval,
            repeating: clampedInterval,
            leeway: .milliseconds(250)
        )
        source.setEventHandler {
            MainActor.assumeIsolated {
                action()
            }
        }
        source.resume()
        return Token(source: source)
    }
}

@MainActor
public final class MacOSBrightnessHotkeyGateway: BrightnessHotkeyGateway {
    private typealias IOHIDEventSystemClientCreateFn =
        @convention(c) (CFAllocator?) -> Unmanaged<IOHIDEventSystemClient>?

    private enum HotKeyIdentifier: UInt32, CaseIterable {
        case decrease = 1
        case increase = 2
        case fineDecrease = 3
        case fineIncrease = 4

        var keyCode: UInt32 {
            switch self {
            case .decrease, .fineDecrease:
                return UInt32(kVK_F1)
            case .increase, .fineIncrease:
                return UInt32(kVK_F2)
            }
        }

        var modifiers: UInt32 {
            switch self {
            case .decrease, .increase:
                return 0
            case .fineDecrease, .fineIncrease:
                return UInt32(optionKey | shiftKey)
            }
        }

        var direction: BrightnessKeyDirection {
            switch self {
            case .decrease, .fineDecrease:
                return .decrease
            case .increase, .fineIncrease:
                return .increase
            }
        }

        var isFine: Bool {
            switch self {
            case .decrease, .increase:
                return false
            case .fineDecrease, .fineIncrease:
                return true
            }
        }
    }

    private static let hotKeySignature: OSType = 0x4F42_4448
    private static let fnStateNotificationName = Notification.Name("com.apple.keyboard.fnstatedidchange")
    private static let accessibilityAPINotificationName = Notification.Name("com.apple.accessibility.api")
    nonisolated public static let defaultAccessibilityPollingInterval: TimeInterval = 1.0
    private static let keyboardSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    private static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    public var onBrightnessKeyEvent: (@MainActor (BrightnessKeyEvent) -> Bool)?
    public var onCheckerStatusDidChange: (@MainActor () -> Void)?

    public var isAccessibilityPollingActive: Bool {
        accessibilityPollTask != nil
    }

    private let ioHIDEventSystemClientCreate: IOHIDEventSystemClientCreateFn?
    private let hudPresenter: BrightnessHUDPresenting?
    private let accessibilityTrustProvider: @MainActor () -> Bool
    private let accessibilityPollingScheduler: AccessibilityPollingScheduling
    private let accessibilityPollingInterval: TimeInterval
    private let distributedNotificationCenter: NotificationCenter
    private var currentPreferences = HotkeyPreferences()
    private var isStopped = false
    private var lastObservedAccessibilityTrusted: Bool?
    private nonisolated(unsafe) var mediaEventTap: CFMachPort?
    private nonisolated(unsafe) var mediaRunLoopSource: CFRunLoopSource?
    private var consumedMediaKeyCodes: Set<Int32> = []
    private nonisolated(unsafe) var carbonEventHandler: EventHandlerRef?
    private nonisolated(unsafe) var registeredHotKeyRefs: [EventHotKeyRef] = []
    private nonisolated(unsafe) var repeatDelayTimer: Timer?
    private nonisolated(unsafe) var repeatIntervalTimer: Timer?
    private var activeRepeatHotKey: HotKeyIdentifier?
    private nonisolated(unsafe) var accessibilityPollTask: AccessibilityPollingCancellable?
    private nonisolated(unsafe) var fnStateObserver: NSObjectProtocol?
    private nonisolated(unsafe) var accessibilityObserver: NSObjectProtocol?
    private nonisolated(unsafe) var appDidBecomeActiveObserver: NSObjectProtocol?

    public init(
        hudPresenter: BrightnessHUDPresenting? = nil,
        accessibilityTrustProvider: (@MainActor () -> Bool)? = nil,
        accessibilityPollingScheduler: AccessibilityPollingScheduling? = nil,
        accessibilityPollingInterval: TimeInterval = MacOSBrightnessHotkeyGateway.defaultAccessibilityPollingInterval,
        distributedNotificationCenter: NotificationCenter = DistributedNotificationCenter.default()
    ) {
        let ioKit = DynamicLibrary(path: "/System/Library/Frameworks/IOKit.framework/IOKit")
        self.ioHIDEventSystemClientCreate = ioKit.symbol("IOHIDEventSystemClientCreate")
        self.hudPresenter = hudPresenter
        self.accessibilityTrustProvider = accessibilityTrustProvider ?? { AXIsProcessTrusted() }
        self.accessibilityPollingScheduler = accessibilityPollingScheduler ?? DispatchAccessibilityPollingScheduler()
        self.accessibilityPollingInterval = max(0.1, accessibilityPollingInterval)
        self.distributedNotificationCenter = distributedNotificationCenter
        startStatusObservers()
    }

    deinit {
        stopSystemCaptureAndObservers()
    }

    public func applyPreferences(_ preferences: HotkeyPreferences) {
        isStopped = false
        currentPreferences = preferences
        syncMediaEventTap()
        syncLiteralF1F2HotKeys()
    }

    public func readCheckerStatus() -> KeyboardCheckerStatus {
        let isTrusted = accessibilityTrustProvider()
        syncMediaEventTap(isAccessibilityTrusted: isTrusted)

        return KeyboardCheckerStatus(
            functionKeyMode: readFunctionKeyMode(),
            isAccessibilityTrusted: isTrusted,
            isMediaKeyCaptureActive: mediaEventTap != nil,
            isLiteralF1F2Active: !registeredHotKeyRefs.isEmpty
        )
    }

    public func currentPointerLocation() -> CGPoint? {
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return BrightnessKeyEventParser.convertAppKitPointerToCoreGraphics(
            NSEvent.mouseLocation,
            mainDisplayHeight: mainHeight
        )
    }

    public func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        if !isTrusted, let url = Self.accessibilitySettingsURL {
            NSWorkspace.shared.open(url)
        }
        syncMediaEventTap(isAccessibilityTrusted: isTrusted)
    }

    public func openKeyboardSettings() {
        guard let url = Self.keyboardSettingsURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    public func showBrightnessHUD(_ updates: [BrightnessHUDUpdate]) {
        guard !updates.isEmpty else { return }
        hudPresenter?.showBrightnessHUD(updates)
    }

    public func stop() {
        isStopped = true
        stopSystemCaptureAndObservers()
        hudPresenter?.dismissAllBrightnessHUDs()
    }

    nonisolated private func stopSystemCaptureAndObservers() {
        accessibilityPollTask?.cancel()
        accessibilityPollTask = nil
        stopRepeatTimers()
        unregisterLiteralHotKeys()
        stopMediaEventTap()

        if let fnStateObserver {
            distributedNotificationCenter.removeObserver(fnStateObserver)
            self.fnStateObserver = nil
        }
        if let accessibilityObserver {
            distributedNotificationCenter.removeObserver(accessibilityObserver)
            self.accessibilityObserver = nil
        }
        if let appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
            self.appDidBecomeActiveObserver = nil
        }
    }

    // MARK: - Function Key Mode Checker & Observers

    private func startStatusObservers() {
        fnStateObserver = distributedNotificationCenter.addObserver(
            forName: Self.fnStateNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isStopped else { return }
                self.onCheckerStatusDidChange?()
            }
        }

        accessibilityObserver = distributedNotificationCenter.addObserver(
            forName: Self.accessibilityAPINotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reconcileAccessibilityState(alwaysNotify: true)
            }
        }

        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reconcileAccessibilityState(alwaysNotify: true)
            }
        }
    }

    private func reconcileAccessibilityState(alwaysNotify: Bool) {
        guard !isStopped else { return }
        let isTrusted = accessibilityTrustProvider()
        let previousTrusted = lastObservedAccessibilityTrusted
        lastObservedAccessibilityTrusted = isTrusted
        syncMediaEventTap(isAccessibilityTrusted: isTrusted)
        if alwaysNotify || previousTrusted != isTrusted {
            onCheckerStatusDidChange?()
        }
    }

    private func syncAccessibilityPollingTimer(isAccessibilityTrusted: Bool) {
        let shouldPoll = !isStopped && currentPreferences.isMediaKeysEnabled && !isAccessibilityTrusted
        if shouldPoll {
            if accessibilityPollTask == nil {
                lastObservedAccessibilityTrusted = false
                accessibilityPollTask = accessibilityPollingScheduler.scheduleRepeating(
                    interval: accessibilityPollingInterval
                ) { [weak self] in
                    self?.reconcileAccessibilityState(alwaysNotify: false)
                }
            }
        } else {
            accessibilityPollTask?.cancel()
            accessibilityPollTask = nil
        }
    }

    private func readFunctionKeyMode() -> FunctionKeyMode {
        var hidMode: Int?
        if let ioHIDEventSystemClientCreate,
            let client = ioHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue(),
            let value = IOHIDEventSystemClientCopyProperty(client, "HIDFKeyMode" as CFString) as? NSNumber
        {
            hidMode = value.intValue
        }

        let cfPrefFnState =
            CFPreferencesCopyAppValue("com.apple.keyboard.fnState" as CFString, kCFPreferencesAnyApplication) as? Bool
        return BrightnessKeyEventParser.resolveFunctionKeyMode(
            hidFKeyMode: hidMode,
            cfPreferenceFnState: cfPrefFnState
        )
    }

    // MARK: - Media Key CGEventTap

    private func syncMediaEventTap(isAccessibilityTrusted: Bool? = nil) {
        let trusted = isAccessibilityTrusted ?? accessibilityTrustProvider()
        lastObservedAccessibilityTrusted = trusted
        syncAccessibilityPollingTimer(isAccessibilityTrusted: trusted)

        guard !isStopped, currentPreferences.isMediaKeysEnabled, trusted else {
            stopMediaEventTap()
            return
        }

        // Never invoke CGEventTapCreate unless Accessibility is already trusted, so launch never triggers TCC prompts.
        guard AXIsProcessTrusted() else {
            return
        }

        if let existingTap = mediaEventTap {
            CGEvent.tapEnable(tap: existingTap, enable: true)
            return
        }

        let eventMask = CGEventMask(1 << NX_SYSDEFINED)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: Self.mediaEventTapCallback,
                userInfo: userInfo
            )
        else {
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        mediaEventTap = tap
        mediaRunLoopSource = source
    }

    nonisolated private func stopMediaEventTap() {
        if let source = mediaRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            mediaRunLoopSource = nil
        }
        if let tap = mediaEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            mediaEventTap = nil
        }
    }

    nonisolated private static let mediaEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let gateway = Unmanaged<MacOSBrightnessHotkeyGateway>.fromOpaque(userInfo).takeUnretainedValue()
        return MainActor.assumeIsolated {
            gateway.handleMediaTapEvent(type: type, event: event)
        }
    }

    private func handleMediaTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let mediaEventTap {
                CGEvent.tapEnable(tap: mediaEventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event),
            nsEvent.type == .systemDefined,
            nsEvent.subtype.rawValue == Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS)
        else {
            return Unmanaged.passUnretained(event)
        }

        let isFine = nsEvent.modifierFlags.intersection([.option, .shift]) == [.option, .shift]
        guard
            let parsed = BrightnessKeyEventParser.parseMediaKeyData(
                data1: nsEvent.data1,
                isFineModifierActive: isFine,
                pointerLocation: currentPointerLocation()
            )
        else {
            return Unmanaged.passUnretained(event)
        }

        if parsed.isKeyDown {
            let shouldConsume = onBrightnessKeyEvent?(parsed.event) ?? false
            if shouldConsume {
                consumedMediaKeyCodes.insert(parsed.keyCode)
                return nil
            }
            consumedMediaKeyCodes.remove(parsed.keyCode)
            return Unmanaged.passUnretained(event)
        }

        if parsed.isKeyUp, consumedMediaKeyCodes.remove(parsed.keyCode) != nil {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Opt-in Carbon Literal F1 / F2

    private func syncLiteralF1F2HotKeys() {
        guard currentPreferences.isLiteralF1F2Enabled else {
            stopRepeatTimers()
            activeRepeatHotKey = nil
            unregisterLiteralHotKeys()
            return
        }

        guard registeredHotKeyRefs.isEmpty else {
            return
        }

        let eventSpecs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        var handlerRef: EventHandlerRef?
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.carbonHotKeyHandler,
            eventSpecs.count,
            eventSpecs,
            userInfo,
            &handlerRef
        )
        guard handlerStatus == noErr, let handlerRef else {
            return
        }
        carbonEventHandler = handlerRef

        for identifier in HotKeyIdentifier.allCases {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: identifier.rawValue)
            let status = RegisterEventHotKey(
                identifier.keyCode,
                identifier.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr, let hotKeyRef {
                registeredHotKeyRefs.append(hotKeyRef)
            }
        }

        if registeredHotKeyRefs.isEmpty {
            unregisterLiteralHotKeys()
        }
    }

    nonisolated private func unregisterLiteralHotKeys() {
        for hotKeyRef in registeredHotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        registeredHotKeyRefs.removeAll()

        if let carbonEventHandler {
            RemoveEventHandler(carbonEventHandler)
            self.carbonEventHandler = nil
        }
    }

    nonisolated private static let carbonHotKeyHandler: EventHandlerUPP = { _, event, userInfo in
        guard let event, let userInfo else {
            return OSStatus(eventNotHandledErr)
        }
        let gateway = Unmanaged<MacOSBrightnessHotkeyGateway>.fromOpaque(userInfo).takeUnretainedValue()
        return MainActor.assumeIsolated {
            gateway.handleCarbonHotKeyEvent(event)
        }
    }

    private func handleCarbonHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let paramErr = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard paramErr == noErr,
            hotKeyID.signature == Self.hotKeySignature,
            let identifier = HotKeyIdentifier(rawValue: hotKeyID.id)
        else {
            return OSStatus(eventNotHandledErr)
        }

        let eventKind = GetEventKind(event)
        if eventKind == UInt32(kEventHotKeyPressed) {
            stopRepeatTimers()
            activeRepeatHotKey = identifier
            dispatchCarbonStep(identifier)
            scheduleCarbonHoldRepeat(for: identifier)
            return noErr
        }
        if eventKind == UInt32(kEventHotKeyReleased) {
            if activeRepeatHotKey == identifier {
                stopRepeatTimers()
                activeRepeatHotKey = nil
            }
            return noErr
        }

        return OSStatus(eventNotHandledErr)
    }

    private func dispatchCarbonStep(_ identifier: HotKeyIdentifier) {
        let keyEvent = BrightnessKeyEvent(
            direction: identifier.direction,
            source: .literalFunctionKey,
            isFine: identifier.isFine,
            pointerLocation: currentPointerLocation()
        )
        _ = onBrightnessKeyEvent?(keyEvent)
    }

    private func scheduleCarbonHoldRepeat(for identifier: HotKeyIdentifier) {
        let initialDelay = NSEvent.keyRepeatDelay > 0 ? NSEvent.keyRepeatDelay : 0.4
        let repeatInterval = NSEvent.keyRepeatInterval > 0 ? NSEvent.keyRepeatInterval : 0.08

        let delayTimer = Timer(timeInterval: initialDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.activeRepeatHotKey == identifier else {
                    return
                }
                self.dispatchCarbonStep(identifier)

                let intervalTimer = Timer(timeInterval: repeatInterval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.activeRepeatHotKey == identifier else {
                            return
                        }
                        self.dispatchCarbonStep(identifier)
                    }
                }
                RunLoop.main.add(intervalTimer, forMode: .common)
                self.repeatIntervalTimer = intervalTimer
            }
        }
        RunLoop.main.add(delayTimer, forMode: .common)
        repeatDelayTimer = delayTimer
    }

    nonisolated private func stopRepeatTimers() {
        repeatDelayTimer?.invalidate()
        repeatDelayTimer = nil
        repeatIntervalTimer?.invalidate()
        repeatIntervalTimer = nil
    }
}
