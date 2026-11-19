import Foundation
import Combine

@MainActor
public final class DisplayCoordinator: ObservableObject {
    @Published public private(set) var displays: [DisplayState] = []

    private let driver: DisplayDriver

    public init(driver: DisplayDriver) {
        self.driver = driver
        refreshDisplays()
    }

    public func handleDisplayReconfiguration() {
        refreshDisplays()
    }

    public func refreshDisplays() {
        let online = driver.fetchOnlineDisplays()
        let sorted = online.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return lhs.isBuiltIn && !rhs.isBuiltIn
            }
            return lhs.displayID < rhs.displayID
        }

        displays = sorted.map { raw in
            let availableModes = Self.filterDisplayModes(for: raw)
            let resolvedCurrentModeID = Self.resolveCurrentModeID(for: raw, availableModes: availableModes)
            return DisplayState(
                displayID: raw.displayID,
                name: Self.humanReadableName(for: raw),
                isBuiltIn: raw.isBuiltIn,
                isMain: raw.isMain,
                symbolName: raw.isBuiltIn ? "laptopcomputer" : "display",
                availableModes: availableModes,
                currentModeID: resolvedCurrentModeID
            )
        }
    }

    public func previewResolution(_ displayID: UInt32, modeID: Int32) {
        guard let index = displays.firstIndex(where: { $0.displayID == displayID }) else {
            return
        }
        guard displays[index].availableModes.contains(where: { $0.modeID == modeID }) else {
            return
        }
        displays[index].previewModeID = modeID
    }

    public func previewResolution(_ displayID: UInt32, stepIndex: Int) {
        guard let index = displays.firstIndex(where: { $0.displayID == displayID }) else {
            return
        }
        let modes = displays[index].availableModes
        guard !modes.isEmpty else {
            return
        }
        let clampedIndex = max(0, min(modes.count - 1, stepIndex))
        displays[index].previewModeID = modes[clampedIndex].modeID
    }

    public func commitResolution(_ displayID: UInt32, modeID: Int32? = nil) {
        guard let index = displays.firstIndex(where: { $0.displayID == displayID }) else {
            return
        }
        let targetModeID = modeID ?? displays[index].previewModeID
        displays[index].previewModeID = nil

        guard let targetModeID else {
            return
        }
        if !displays[index].availableModes.isEmpty {
            guard displays[index].availableModes.contains(where: { $0.modeID == targetModeID }) else {
                return
            }
        }
        guard targetModeID != displays[index].currentModeID else {
            return
        }

        displays[index].currentModeID = targetModeID
        try? driver.setDisplayMode(displayID, modeID: targetModeID)
    }

    private static func resolveCurrentModeID(
        for raw: RawDisplayInfo,
        availableModes: [DisplayModeOption]
    ) -> Int32 {
        if availableModes.contains(where: { $0.modeID == raw.currentModeID }) {
            return raw.currentModeID
        }
        if let activeRaw = raw.modes.first(where: { $0.modeID == raw.currentModeID }),
           let matchingOption = availableModes.first(where: {
               $0.width == activeRaw.width && $0.height == activeRaw.height
           }) {
            return matchingOption.modeID
        }
        return availableModes.first(where: { $0.scalePercentage == 100 })?.modeID
            ?? availableModes.last?.modeID
            ?? raw.currentModeID
    }

    private static func filterDisplayModes(for raw: RawDisplayInfo) -> [DisplayModeOption] {
        let usableModes = raw.modes.filter {
            $0.isUsableForDesktopGUI && $0.width > 0 && $0.height > 0 && $0.pixelWidth > 0 && $0.pixelHeight > 0
        }
        guard !usableModes.isEmpty else {
            return []
        }

        let (nativePixelWidth, nativePixelHeight) = resolveNativePixelDimensions(for: raw, usableModes: usableModes)
        let nativeAspect = Double(nativePixelWidth) / Double(nativePixelHeight)

        let currentRefreshRate: Double = {
            if let active = raw.modes.first(where: { $0.modeID == raw.currentModeID }) {
                return active.refreshRate
            }
            return usableModes.first?.refreshRate ?? 60.0
        }()

        let aspectAndRateFiltered = usableModes.filter { mode in
            let aspect = Double(mode.width) / Double(mode.height)
            let matchesAspect = abs(aspect - nativeAspect) <= 0.025
            let matchesRefreshRate = abs(mode.refreshRate - currentRefreshRate) <= 0.5
            return matchesAspect && matchesRefreshRate
        }

        let candidatePool = aspectAndRateFiltered.isEmpty ? usableModes : aspectAndRateFiltered
        let hiDPICandidates = candidatePool.filter { $0.pixelWidth > $0.width }
        let preferredModes = hiDPICandidates.isEmpty ? candidatePool : hiDPICandidates

        var deduplicatedByResolution: [String: RawDisplayMode] = [:]
        for mode in preferredModes {
            let key = "\(mode.width)x\(mode.height)"
            if let existing = deduplicatedByResolution[key] {
                if mode.modeID == raw.currentModeID {
                    deduplicatedByResolution[key] = mode
                } else if existing.modeID != raw.currentModeID && mode.pixelWidth > existing.pixelWidth {
                    deduplicatedByResolution[key] = mode
                }
            } else {
                deduplicatedByResolution[key] = mode
            }
        }

        let sortedModes = deduplicatedByResolution.values.sorted { lhs, rhs in
            let lhsArea = lhs.width * lhs.height
            let rhsArea = rhs.width * rhs.height
            if lhsArea != rhsArea {
                return lhsArea < rhsArea
            }
            return lhs.width < rhs.width
        }

        return sortedModes.map { mode in
            let isHiDPI = mode.pixelWidth > mode.width
            let scalePercentage: Int
            if isHiDPI {
                scalePercentage = Int(((Double(mode.width) * 2.0) / Double(nativePixelWidth) * 100.0).rounded())
            } else {
                scalePercentage = Int(((Double(mode.width) / Double(nativePixelWidth)) * 100.0).rounded())
            }
            let label: String
            if isHiDPI && scalePercentage != 100 {
                label = "\(mode.width)x\(mode.height) · \(scalePercentage)%"
            } else {
                label = "\(mode.width)x\(mode.height)"
            }
            return DisplayModeOption(
                modeID: mode.modeID,
                width: mode.width,
                height: mode.height,
                pixelWidth: mode.pixelWidth,
                pixelHeight: mode.pixelHeight,
                refreshRate: mode.refreshRate,
                isHiDPI: isHiDPI,
                scalePercentage: scalePercentage,
                label: label
            )
        }
    }

    private static func resolveNativePixelDimensions(
        for raw: RawDisplayInfo,
        usableModes: [RawDisplayMode]
    ) -> (Int, Int) {
        let maxLogicalWidth = usableModes.map(\.width).max() ?? 0
        let oneXModes = usableModes.filter { $0.pixelWidth == $0.width && $0.pixelHeight == $0.height }
        if let highest1x = oneXModes.max(by: { ($0.width * $0.height) < ($1.width * $1.height) }),
           highest1x.pixelWidth >= maxLogicalWidth {
            return (highest1x.pixelWidth, highest1x.pixelHeight)
        }

        let twoXModes = usableModes.filter { $0.pixelWidth == $0.width * 2 && $0.pixelWidth >= 2560 }
        if let base2x = twoXModes.min(by: { ($0.pixelWidth * $0.pixelHeight) < ($1.pixelWidth * $1.pixelHeight) }) {
            return (base2x.pixelWidth, base2x.pixelHeight)
        }

        if let highest1x = oneXModes.max(by: { ($0.width * $0.height) < ($1.width * $1.height) }) {
            return (highest1x.pixelWidth, highest1x.pixelHeight)
        }

        if let active = usableModes.first(where: { $0.modeID == raw.currentModeID }) {
            return (active.pixelWidth, active.pixelHeight)
        }

        if let largest = usableModes.max(by: { ($0.pixelWidth * $0.pixelHeight) < ($1.pixelWidth * $1.pixelHeight) }) {
            return (largest.pixelWidth, largest.pixelHeight)
        }

        return (1920, 1080)
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
