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
        let vrr = normalizeVRR(
            isVRR: mode.isVRR,
            isProMotion: mode.isProMotion,
            minRefreshRate: mode.minRefreshRate,
            maxRefreshRate: mode.refreshRate
        )
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
            isVRR: vrr.isVRR,
            isProMotion: vrr.isProMotion,
            minRefreshRate: vrr.minRefreshRate,
            aspectRatioLabel: formatAspectRatio(width: mode.width, height: mode.height),
            refreshRateLabel: formatShortRefreshRate(
                refreshRate: mode.refreshRate,
                isVRR: vrr.isVRR,
                minRefreshRate: vrr.minRefreshRate
            ),
            colorDepthLabel: "\(bits)bit",
            resolutionLabel: "\(mode.width)x\(mode.height)"
        )
    }

    public static func refreshRateOptions(
        for activeMode: DisplayModeOption?,
        in availableModes: [DisplayModeOption]
    ) -> [RefreshRateOption] {
        guard let activeMode else { return [] }

        let matchingModes = availableModes.filter { mode in
            mode.width == activeMode.width
                && mode.height == activeMode.height
                && mode.isHiDPI == activeMode.isHiDPI
                && mode.refreshRate > 0.5
        }
        guard !matchingModes.isEmpty else { return [] }

        var grouped: [RefreshRateBucketKey: DisplayModeOption] = [:]
        for mode in matchingModes {
            let vrr = normalizeVRR(
                isVRR: mode.isVRR,
                isProMotion: mode.isProMotion,
                minRefreshRate: mode.minRefreshRate,
                maxRefreshRate: mode.refreshRate
            )
            let key = RefreshRateBucketKey(
                isVRR: vrr.isVRR,
                minHzHundredths: vrr.minRefreshRate.map { Int(($0 * 100.0).rounded()) },
                maxHzHundredths: Int((mode.refreshRate * 100.0).rounded())
            )
            if let existing = grouped[key] {
                if isPreferredRefreshRateCandidate(mode, over: existing, activeMode: activeMode) {
                    grouped[key] = mode
                }
            } else {
                grouped[key] = mode
            }
        }

        var options = grouped.values.map(makeRefreshRateOption(from:))
        options.sort { lhs, rhs in
            if lhs.isNTSC != rhs.isNTSC {
                return !lhs.isNTSC && rhs.isNTSC
            }
            if !lhs.isNTSC, lhs.isVRR != rhs.isVRR {
                return lhs.isVRR && !rhs.isVRR
            }
            if abs(lhs.refreshRate - rhs.refreshRate) > 0.005 {
                return lhs.refreshRate > rhs.refreshRate
            }
            let lhsMin = lhs.minRefreshRate ?? 0
            let rhsMin = rhs.minRefreshRate ?? 0
            if abs(lhsMin - rhsMin) > 0.005 {
                return lhsMin > rhsMin
            }
            return lhs.modeID < rhs.modeID
        }
        return options
    }

    private struct RefreshRateBucketKey: Hashable {
        let isVRR: Bool
        let minHzHundredths: Int?
        let maxHzHundredths: Int
    }

    private static func isPreferredRefreshRateCandidate(
        _ candidate: DisplayModeOption,
        over current: DisplayModeOption,
        activeMode: DisplayModeOption
    ) -> Bool {
        if candidate.modeID == activeMode.modeID {
            return true
        }
        if current.modeID == activeMode.modeID {
            return false
        }
        let candidateMatchesBits = candidate.bitsPerSample == activeMode.bitsPerSample
        let currentMatchesBits = current.bitsPerSample == activeMode.bitsPerSample
        if candidateMatchesBits != currentMatchesBits {
            return candidateMatchesBits
        }
        if candidate.bitsPerSample != current.bitsPerSample {
            return candidate.bitsPerSample > current.bitsPerSample
        }
        if candidate.isDefault != current.isDefault {
            return candidate.isDefault
        }
        if candidate.isNative != current.isNative {
            return candidate.isNative
        }
        return candidate.modeID < current.modeID
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

    static func normalizeVRR(
        isVRR: Bool,
        isProMotion: Bool,
        minRefreshRate: Double?,
        maxRefreshRate: Double
    ) -> (isVRR: Bool, isProMotion: Bool, minRefreshRate: Double?) {
        let effectiveIsVRR = isVRR || isProMotion
        guard effectiveIsVRR else {
            return (false, false, nil)
        }
        if let minRefreshRate,
            minRefreshRate > 0.5,
            minRefreshRate < maxRefreshRate - 0.5
        {
            return (true, isProMotion, minRefreshRate)
        }
        if isProMotion, maxRefreshRate > 24.5 {
            return (true, true, 24.0)
        }
        return (true, isProMotion, nil)
    }

    private static func makeRefreshRateOption(from mode: DisplayModeOption) -> RefreshRateOption {
        let vrr = normalizeVRR(
            isVRR: mode.isVRR,
            isProMotion: mode.isProMotion,
            minRefreshRate: mode.minRefreshRate,
            maxRefreshRate: mode.refreshRate
        )
        let isNTSC = isNTSCRefreshRate(mode.refreshRate, isVRR: vrr.isVRR)
        let shortLabel =
            formatShortRefreshRate(
                refreshRate: mode.refreshRate,
                isVRR: vrr.isVRR,
                minRefreshRate: vrr.minRefreshRate
            ) ?? ""
        let label = vrr.isVRR ? "\(shortLabel) (Variable)" : shortLabel

        return RefreshRateOption(
            modeID: mode.modeID,
            refreshRate: mode.refreshRate,
            minRefreshRate: vrr.minRefreshRate,
            isVRR: vrr.isVRR,
            isProMotion: vrr.isProMotion,
            isNTSC: isNTSC,
            label: label,
            shortLabel: shortLabel
        )
    }

    private static func isNTSCRefreshRate(_ refreshRate: Double, isVRR: Bool) -> Bool {
        guard !isVRR, refreshRate > 0.5 else { return false }
        return abs(refreshRate - refreshRate.rounded()) >= 0.01
    }

    private static func formatShortRefreshRate(
        refreshRate: Double,
        isVRR: Bool,
        minRefreshRate: Double?
    ) -> String? {
        guard let maxNumber = formatRateNumber(refreshRate) else { return nil }
        if isVRR,
            let minRefreshRate,
            minRefreshRate < refreshRate - 0.5,
            let minNumber = formatRateNumber(minRefreshRate)
        {
            return "\(minNumber)–\(maxNumber)Hz"
        }
        return "\(maxNumber)Hz"
    }

    private static func formatRateNumber(_ refreshRate: Double) -> String? {
        guard refreshRate > 0.5 else { return nil }
        let rounded = refreshRate.rounded()
        if abs(refreshRate - rounded) < 0.01 {
            return "\(Int(rounded))"
        }
        return String(format: "%.2f", refreshRate)
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
