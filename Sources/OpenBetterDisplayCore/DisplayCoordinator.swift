import Foundation
import Combine

@MainActor
public final class DisplayCoordinator: ObservableObject {
    @Published public private(set) var displays: [DisplayState] = []

    private let driver: DisplayDriver
    private var lastKnownRawDisplays: [UInt32: RawDisplayInfo] = [:]
    private var disconnectedDisplays: [UInt32: RawDisplayInfo] = [:]

    public var hasDisconnectedDisplays: Bool {
        displays.contains(where: { !$0.isEnabled })
    }

    public init(driver: DisplayDriver) {
        self.driver = driver
        refreshDisplays()
    }

    public func canToggleOff(_ displayID: UInt32) -> Bool {
        guard let display = displays.first(where: { $0.displayID == displayID }) else {
            return false
        }
        return display.canToggleOff
    }

    public func toggleLockReason(for displayID: UInt32) -> DisplayToggleLockReason? {
        guard let display = displays.first(where: { $0.displayID == displayID }),
              display.isEnabled,
              !display.canToggleOff else {
            return nil
        }
        let activeCount = displays.filter(\.isEnabled).count
        if activeCount <= 1 {
            return .lastActiveDisplay
        }
        if display.isMain {
            return .mainDisplay
        }
        return nil
    }

    public func toggleDisplayEnabled(_ displayID: UInt32) {
        guard let display = displays.first(where: { $0.displayID == displayID }) else {
            return
        }
        setDisplayEnabled(displayID, enabled: !display.isEnabled)
    }

    public func setDisplayEnabled(_ displayID: UInt32, enabled: Bool) {
        guard let display = displays.first(where: { $0.displayID == displayID }) else {
            return
        }

        if enabled {
            guard !display.isEnabled else { return }
            do {
                try driver.setDisplayEnabled(displayID, enabled: true)
                disconnectedDisplays.removeValue(forKey: displayID)
                refreshDisplays()
            } catch {
                return
            }
        } else {
            guard display.isEnabled, canToggleOff(displayID) else { return }
            let rawToCache = lastKnownRawDisplays[displayID] ?? RawDisplayInfo(
                displayID: display.displayID,
                name: display.name,
                isBuiltIn: display.isBuiltIn,
                isMain: false,
                isActive: false
            )
            do {
                try driver.setDisplayEnabled(displayID, enabled: false)
                var cached = rawToCache
                cached.isActive = false
                cached.isMain = false
                disconnectedDisplays[displayID] = cached
                refreshDisplays()
            } catch {
                return
            }
        }
    }

    public func handleDisplayReconfiguration() {
        refreshDisplays()
    }

    public func setMainDisplay(_ displayID: UInt32) {
        guard let target = displays.first(where: { $0.displayID == displayID }),
              target.isEnabled,
              !target.isMain else {
            return
        }
        do {
            try driver.setMainDisplay(displayID)
            for id in disconnectedDisplays.keys {
                disconnectedDisplays[id]?.isMain = false
            }
            refreshDisplays()
        } catch {
            return
        }
    }

    public func reconnectAllDisplays() {
        let disabledIDs = Set(displays.filter { !$0.isEnabled }.map(\.displayID))
            .union(disconnectedDisplays.keys)
            .sorted()
        guard !disabledIDs.isEmpty else { return }

        for id in disabledIDs {
            do {
                try driver.setDisplayEnabled(id, enabled: true)
                disconnectedDisplays.removeValue(forKey: id)
            } catch {
                continue
            }
        }
        refreshDisplays()
    }

    /// Lifecycle hook: the Mac woke from sleep — bring every turned-off display back.
    public func handleSystemWake() {
        reconnectAllDisplays()
    }

    /// Lifecycle hook: app is terminating — re-enable all disconnected displays and restore gamma.
    public func handleAppWillTerminate() {
        reconnectAllDisplays()
        driver.resetSoftwareGamma()
    }

    public func refreshDisplays() {
        let online = driver.fetchOnlineDisplays()
        var mergedByID: [UInt32: RawDisplayInfo] = [:]

        for raw in online {
            if raw.isActive || lastKnownRawDisplays[raw.displayID] == nil {
                lastKnownRawDisplays[raw.displayID] = raw
            }
            if let existingCached = disconnectedDisplays[raw.displayID] {
                if raw.isActive {
                    disconnectedDisplays.removeValue(forKey: raw.displayID)
                    mergedByID[raw.displayID] = raw
                } else {
                    mergedByID[raw.displayID] = existingCached
                }
            } else {
                mergedByID[raw.displayID] = raw
            }
        }

        for (id, cachedRaw) in disconnectedDisplays where mergedByID[id] == nil {
            mergedByID[id] = cachedRaw
        }

        let sorted = mergedByID.values.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return lhs.isBuiltIn && !rhs.isBuiltIn
            }
            return lhs.displayID < rhs.displayID
        }

        let enabledCount = sorted.filter { raw in
            disconnectedDisplays[raw.displayID] == nil && raw.isActive
        }.count

        displays = sorted.map { raw in
            let isEnabled = disconnectedDisplays[raw.displayID] == nil && raw.isActive
            let isMain = isEnabled && raw.isMain
            let canToggleOff = isEnabled && !isMain && enabledCount > 1

            return DisplayState(
                displayID: raw.displayID,
                name: Self.humanReadableName(for: raw),
                isBuiltIn: raw.isBuiltIn,
                isMain: isMain,
                isEnabled: isEnabled,
                canToggleOff: canToggleOff,
                symbolName: raw.isBuiltIn ? "laptopcomputer" : "display"
            )
        }
    }

    private static func humanReadableName(for raw: RawDisplayInfo) -> String {
        let trimmed = raw.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isBuiltIn {
            let genericBuiltInNames: Set<String> = [
                "",
                "Color LCD",
                "Built-in Retina Display",
                "Built-in Liquid Retina Display",
                "Built-in Liquid Retina XDR Display",
                "Liquid Retina XDR Display",
                "Liquid Retina Display"
            ]
            if genericBuiltInNames.contains(trimmed) {
                return "Built-in Display"
            }
            return trimmed
        }
        if !trimmed.isEmpty {
            return trimmed
        }
        if raw.vendorID != 0 || raw.modelID != 0 {
            return String(format: "External Display (%04X:%04X)", raw.vendorID, raw.modelID)
        }
        return "External Display"
    }
}
