import Foundation

public enum DisplayModeFilter {
    private static let knownAspectRatios: [(ratio: Double, label: String, tolerance: Double)] = [
        (5.0 / 4.0, "5:4", 0.015),
        (4.0 / 3.0, "4:3", 0.015),
        (3.0 / 2.0, "3:2", 0.015),
        (16.0 / 10.0, "16:10", 0.015),
        (16.0 / 9.0, "16:9", 0.015),
        (19.0 / 10.0, "19:10", 0.015),
        (24.0 / 10.0, "24:10", 0.015),
        (21.0 / 9.0, "21:9", 0.04),
        (32.0 / 9.0, "32:9", 0.02)
    ]

    public static func filterModes(for raw: RawDisplayInfo) -> [DisplayModeOption] {
        let safeModes = safeDesktopModes(from: raw.modes)
        guard !safeModes.isEmpty else {
            return []
        }

        var uniqueByID: [Int32: RawDisplayMode] = [:]
        for mode in safeModes where uniqueByID[mode.modeID] == nil {
            uniqueByID[mode.modeID] = mode
        }

        let sortedModes = uniqueByID.values.sorted { lhs, rhs in
            let lhsArea = lhs.width * lhs.height
            let rhsArea = rhs.width * rhs.height
            if lhsArea != rhsArea {
                return lhsArea > rhsArea
            }
            if lhs.width != rhs.width {
                return lhs.width > rhs.width
            }
            let lhsHiDPI = isHiDPIMode(lhs)
            let rhsHiDPI = isHiDPIMode(rhs)
            if lhsHiDPI != rhsHiDPI {
                return lhsHiDPI && !rhsHiDPI
            }
            if abs(lhs.refreshRate - rhs.refreshRate) > 0.01 {
                return lhs.refreshRate > rhs.refreshRate
            }
            if lhs.bitsPerSample != rhs.bitsPerSample {
                return lhs.bitsPerSample > rhs.bitsPerSample
            }
            return lhs.modeID < rhs.modeID
        }

        return sortedModes.map(makeModeOption(mode:))
    }

    public static func resolveDefaultMode(
        for raw: RawDisplayInfo,
        availableModes: [DisplayModeOption]
    ) -> DisplayModeOption? {
        let activeRate = raw.modes.first(where: { $0.modeID == raw.currentModeID })?.refreshRate
        return bestCandidate(
            in: availableModes.filter(\.isDefault),
            preferredRefreshRate: activeRate
        )
    }

    public static func resolveNativeMode(
        for raw: RawDisplayInfo,
        availableModes: [DisplayModeOption]
    ) -> DisplayModeOption? {
        let activeRate = raw.modes.first(where: { $0.modeID == raw.currentModeID })?.refreshRate
        return bestCandidate(
            in: availableModes.filter(\.isNative),
            preferredRefreshRate: activeRate
        )
    }

    public static func resolveCurrentModeOption(
        for raw: RawDisplayInfo,
        availableModes: [DisplayModeOption]
    ) -> DisplayModeOption? {
        if let matched = availableModes.first(where: { $0.modeID == raw.currentModeID }) {
            return matched
        }
        guard let activeRaw = raw.modes.first(where: { $0.modeID == raw.currentModeID }),
            activeRaw.width > 0,
            activeRaw.height > 0,
            activeRaw.pixelWidth > 0,
            activeRaw.pixelHeight > 0
        else {
            return nil
        }
        return makeModeOption(mode: activeRaw)
    }

    public static func makeModeOption(mode: RawDisplayMode) -> DisplayModeOption {
        let isHiDPI = isHiDPIMode(mode)
        let isOneToOneNative = mode.isNative && mode.width == mode.pixelWidth && mode.height == mode.pixelHeight
        let bits = max(1, mode.bitsPerSample)
        return DisplayModeOption(
            modeID: mode.modeID,
            width: mode.width,
            height: mode.height,
            pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight,
            refreshRate: mode.refreshRate,
            bitsPerSample: bits,
            isHiDPI: isHiDPI,
            isDefault: mode.isDefault,
            isNative: isOneToOneNative,
            aspectRatioLabel: formatAspectRatio(width: mode.width, height: mode.height),
            refreshRateLabel: formatRefreshRate(mode.refreshRate),
            colorDepthLabel: "\(bits)bit",
            resolutionLabel: "\(mode.width)x\(mode.height)"
        )
    }

    private static func safeDesktopModes(from modes: [RawDisplayMode]) -> [RawDisplayMode] {
        modes.filter {
            $0.isUsableForDesktopGUI
                && !$0.isStretched
                && $0.width >= 720
                && $0.height >= 720
                && $0.pixelWidth > 0
                && $0.pixelHeight > 0
        }
    }

    private static func isHiDPIMode(_ mode: RawDisplayMode) -> Bool {
        mode.pixelWidth > mode.width || mode.pixelHeight > mode.height
    }

    private static func bestCandidate(
        in candidates: [DisplayModeOption],
        preferredRefreshRate: Double?
    ) -> DisplayModeOption? {
        candidates.max { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return !lhs.isDefault && rhs.isDefault
            }
            if let preferredRefreshRate, preferredRefreshRate > 0.5 {
                let lhsMatches = abs(lhs.refreshRate - preferredRefreshRate) <= 0.5
                let rhsMatches = abs(rhs.refreshRate - preferredRefreshRate) <= 0.5
                if lhsMatches != rhsMatches {
                    return !lhsMatches && rhsMatches
                }
            }
            if abs(lhs.refreshRate - rhs.refreshRate) > 0.01 {
                return lhs.refreshRate < rhs.refreshRate
            }
            if lhs.bitsPerSample != rhs.bitsPerSample {
                return lhs.bitsPerSample < rhs.bitsPerSample
            }
            return lhs.modeID > rhs.modeID
        }
    }

    private static func formatAspectRatio(width: Int, height: Int) -> String {
        guard width > 0, height > 0 else { return "—" }
        let ratio = Double(width) / Double(height)

        for entry in knownAspectRatios {
            if abs(ratio - entry.ratio) <= entry.tolerance {
                return entry.label
            }
        }

        let divisor = gcd(width, height)
        let simplifiedW = width / divisor
        let simplifiedH = height / divisor
        if simplifiedH <= 20 {
            return "\(simplifiedW):\(simplifiedH)"
        }

        let tenths = Int((ratio * 100.0).rounded())
        if tenths % 10 == 0 {
            return "\(tenths / 10):10"
        }
        return "\(tenths / 10).\(tenths % 10):10"
    }

    private static func formatRefreshRate(_ refreshRate: Double) -> String? {
        guard refreshRate > 0.5 else { return nil }
        let rounded = refreshRate.rounded()
        if abs(refreshRate - rounded) < 0.05 {
            return "\(Int(rounded))Hz"
        }
        return String(format: "%.2fHz", refreshRate)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a)
        var y = abs(b)
        while y != 0 {
            let remainder = x % y
            x = y
            y = remainder
        }
        return max(1, x)
    }
}
