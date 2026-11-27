import CoreGraphics
import Foundation
import OpenBetterDisplayCore

@MainActor
final class FakeBrightnessHotkeyGateway: BrightnessHotkeyGateway {
    var onBrightnessKeyEvent: (@MainActor (BrightnessKeyEvent) -> Bool)?
    var onCheckerStatusDidChange: (@MainActor () -> Void)?

    var appliedPreferencesHistory: [HotkeyPreferences] = []
    var checkerStatus: KeyboardCheckerStatus
    var pointerLocation: CGPoint?
    var accessibilityPermissionRequestCount = 0
    var openKeyboardSettingsCount = 0
    var shownHUDBatches: [[BrightnessHUDUpdate]] = []
    var stopCount = 0

    init(
        checkerStatus: KeyboardCheckerStatus = KeyboardCheckerStatus(
            functionKeyMode: .mediaKeys,
            isAccessibilityTrusted: true
        ),
        pointerLocation: CGPoint? = nil
    ) {
        self.checkerStatus = checkerStatus
        self.pointerLocation = pointerLocation
    }

    func applyPreferences(_ preferences: HotkeyPreferences) {
        appliedPreferencesHistory.append(preferences)
    }

    func readCheckerStatus() -> KeyboardCheckerStatus {
        checkerStatus
    }

    func currentPointerLocation() -> CGPoint? {
        pointerLocation
    }

    func requestAccessibilityPermission() {
        accessibilityPermissionRequestCount += 1
    }

    func openKeyboardSettings() {
        openKeyboardSettingsCount += 1
    }

    func showBrightnessHUD(_ updates: [BrightnessHUDUpdate]) {
        shownHUDBatches.append(updates)
    }

    func stop() {
        stopCount += 1
    }

    @discardableResult
    func simulateKeyEvent(_ event: BrightnessKeyEvent) -> Bool {
        onBrightnessKeyEvent?(event) ?? false
    }

    func simulateCheckerStatusChange(_ newStatus: KeyboardCheckerStatus) {
        checkerStatus = newStatus
        onCheckerStatusDidChange?()
    }
}

@MainActor
final class FakeBrightnessHUDPresenter: BrightnessHUDPresenting {
    var shownBatches: [[BrightnessHUDUpdate]] = []
    var dismissAllCount = 0

    func showBrightnessHUD(_ updates: [BrightnessHUDUpdate]) {
        shownBatches.append(updates)
    }

    func dismissAllBrightnessHUDs() {
        dismissAllCount += 1
    }
}

final class InMemoryHotkeyPreferencesStore: HotkeyPreferencesPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var storedPreferences: HotkeyPreferences?

    init(initialPreferences: HotkeyPreferences? = nil) {
        self.storedPreferences = initialPreferences
    }

    func loadPreferences() -> HotkeyPreferences? {
        lock.lock()
        defer { lock.unlock() }
        return storedPreferences
    }

    func savePreferences(_ preferences: HotkeyPreferences) {
        lock.lock()
        defer { lock.unlock() }
        storedPreferences = preferences
    }
}
