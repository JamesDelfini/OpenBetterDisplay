import Foundation

public enum DisplayModeFilter {
    private struct ResolutionKey: Hashable {
        let width: Int
        let height: Int
    }

    public static func filterModes(for raw: RawDisplayInfo) -> [DisplayModeOption] {
        let usableModes = usableDesktopModes(from: raw.modes)
        guard !usableModes.isEmpty else {
            return []
        }

        let (nativePixelWidth, nativePixelHeight) = resolveNativePixelDimensions(for: raw, usableModes: usableModes)
        let nativeAspect = Double(nativePixelWidth) / Double(nativePixelHeight)

        let aspectMatching = usableModes.filter { mode in
            let aspect = Double(mode.width) / Double(mode.height)
            return abs(aspect - nativeAspect) <= 0.025
        }
        let aspectFiltered = aspectMatching.isEmpty ? usableModes : aspectMatching

        let activeRawMode = raw.modes.first(where: { $0.modeID == raw.currentModeID })
        let candidatePool = filterByRefreshRate(
            aspectFiltered: aspectFiltered,
            activeRawMode: activeRawMode
        )

        let hiDPICandidates = candidatePool.filter { $0.pixelWidth > $0.width }
        let standardCandidates = candidatePool.filter { $0.pixelWidth <= $0.width }
        let isActiveModeHiDPI = activeRawMode.map { $0.pixelWidth > $0.width } ?? false
        let isRetinaOrHighDensityPanel =
            (raw.isBuiltIn && nativePixelWidth >= 2560)
            || nativePixelWidth >= 3000
            || (isActiveModeHiDPI && hiDPICandidates.count >= 2)

        let preferredModes: [RawDisplayMode]
        if !hiDPICandidates.isEmpty && (isRetinaOrHighDensityPanel || standardCandidates.isEmpty) {
            preferredModes = hiDPICandidates
        } else {
            preferredModes = standardCandidates.isEmpty ? candidatePool : standardCandidates
        }

        var deduplicatedByResolution: [ResolutionKey: RawDisplayMode] = [:]
        for mode in preferredModes {
            let key = ResolutionKey(width: mode.width, height: mode.height)
            if let existing = deduplicatedByResolution[key] {
                if mode.modeID == raw.currentModeID {
                    deduplicatedByResolution[key] = mode
                } else if existing.modeID != raw.currentModeID {
                    if mode.pixelWidth > existing.pixelWidth
                        || (mode.pixelWidth == existing.pixelWidth && mode.refreshRate > existing.refreshRate)
                    {
                        deduplicatedByResolution[key] = mode
                    }
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
            makeModeOption(mode: mode, nativePixelWidth: nativePixelWidth)
        }
    }

    public static func resolveCurrentModeOption(
        for raw: RawDisplayInfo,
        availableModes: [DisplayModeOption]
    ) -> DisplayModeOption? {
        if let matched = availableModes.first(where: { $0.modeID == raw.currentModeID }) {
            return matched
        }
        guard let activeRaw = raw.modes.first(where: { $0.modeID == raw.currentModeID }),
            activeRaw.width > 0, activeRaw.height > 0,
            activeRaw.pixelWidth > 0, activeRaw.pixelHeight > 0
        else {
            return nil
        }
        let usableModes = usableDesktopModes(from: raw.modes)
        let nativePixelWidth =
            usableModes.isEmpty
            ? activeRaw.pixelWidth
            : resolveNativePixelDimensions(for: raw, usableModes: usableModes).0
        return makeModeOption(mode: activeRaw, nativePixelWidth: nativePixelWidth)
    }

    public static func makeModeOption(
        mode: RawDisplayMode,
        nativePixelWidth: Int
    ) -> DisplayModeOption {
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

    private static func usableDesktopModes(from modes: [RawDisplayMode]) -> [RawDisplayMode] {
        modes.filter {
            $0.isUsableForDesktopGUI && $0.width > 0 && $0.height > 0 && $0.pixelWidth > 0 && $0.pixelHeight > 0
        }
    }

    private static func filterByRefreshRate(
        aspectFiltered: [RawDisplayMode],
        activeRawMode: RawDisplayMode?
    ) -> [RawDisplayMode] {
        if let activeRate = activeRawMode?.refreshRate {
            if activeRate <= 0.5 {
                let variableRateModes = aspectFiltered.filter { $0.refreshRate <= 0.5 }
                if variableRateModes.count >= 2 || variableRateModes.count == aspectFiltered.count {
                    return variableRateModes
                }
                return aspectFiltered
            }
            let matchingRateModes = aspectFiltered.filter { abs($0.refreshRate - activeRate) <= 0.5 }
            return matchingRateModes.isEmpty ? aspectFiltered : matchingRateModes
        }

        if aspectFiltered.allSatisfy({ $0.refreshRate <= 0.5 }) {
            return aspectFiltered
        }
        let maxRate = aspectFiltered.map(\.refreshRate).max() ?? 60.0
        let matchingRateModes = aspectFiltered.filter { abs($0.refreshRate - maxRate) <= 0.5 }
        return matchingRateModes.isEmpty ? aspectFiltered : matchingRateModes
    }

    private static func resolveNativePixelDimensions(
        for raw: RawDisplayInfo,
        usableModes: [RawDisplayMode]
    ) -> (Int, Int) {
        let nativeFlaggedModes = usableModes.filter(\.isNative)
        if let native1x = nativeFlaggedModes.first(where: { $0.pixelWidth == $0.width && $0.pixelHeight == $0.height }) {
            return (native1x.pixelWidth, native1x.pixelHeight)
        }
        if let nativeMode = nativeFlaggedModes.first {
            return (nativeMode.pixelWidth, nativeMode.pixelHeight)
        }

        let maxLogicalWidth = usableModes.map(\.width).max() ?? 0
        let oneXModes = usableModes.filter { $0.pixelWidth == $0.width && $0.pixelHeight == $0.height }
        if let active = usableModes.first(where: { $0.modeID == raw.currentModeID }) {
            let activeAspect = Double(active.width) / Double(active.height)
            let matchingActiveAspect1x =
                oneXModes
                .filter { abs((Double($0.width) / Double($0.height)) - activeAspect) <= 0.025 }
                .max(by: { ($0.width * $0.height) < ($1.width * $1.height) })
            if let matchingActiveAspect1x,
                Double(matchingActiveAspect1x.pixelWidth) >= Double(maxLogicalWidth) * 0.90
            {
                return (matchingActiveAspect1x.pixelWidth, matchingActiveAspect1x.pixelHeight)
            }
        }

        if let highest1x = oneXModes.max(by: { ($0.width * $0.height) < ($1.width * $1.height) }),
            highest1x.pixelWidth >= maxLogicalWidth
        {
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
}
