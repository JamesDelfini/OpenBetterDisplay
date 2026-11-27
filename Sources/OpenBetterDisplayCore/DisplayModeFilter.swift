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
            let lhsVRR = normalizeVRR(
                isVRR: lhs.isVRR,
                isProMotion: lhs.isProMotion,
                minRefreshRate: lhs.minRefreshRate,
                maxRefreshRate: lhs.refreshRate
            )
            let rhsVRR = normalizeVRR(
                isVRR: rhs.isVRR,
                isProMotion: rhs.isProMotion,
                minRefreshRate: rhs.minRefreshRate,
                maxRefreshRate: rhs.refreshRate
            )
            if lhsVRR.isVRR != rhsVRR.isVRR {
                return lhsVRR.isVRR && !rhsVRR.isVRR
            }
            if let lhsMin = lhsVRR.minRefreshRate, let rhsMin = rhsVRR.minRefreshRate, abs(lhsMin - rhsMin) > 0.01 {
                return lhsMin > rhsMin
            }
            if lhs.bitsPerSample != rhs.bitsPerSample {
                return lhs.bitsPerSample > rhs.bitsPerSample
            }
            return lhs.modeID < rhs.modeID
        }

        return sortedModes.map(makeModeOption(mode:))
    }

    public static func resolveFilteredModes(
        for raw: RawDisplayInfo,
        availableModes: [DisplayModeOption],
        defaultMode: DisplayModeOption?,
        nativeMode: DisplayModeOption?,
        currentModeOption: DisplayModeOption?,
        persistedCriteria: DisplayModeFilterCriteria?
    ) -> (filteredModes: [DisplayModeOption], filterState: DisplayModeFilterState) {
        let options = deriveFilterOptions(from: availableModes)
        let isCustomized = persistedCriteria != nil
        let rawCriteria: DisplayModeFilterCriteria
        if let persistedCriteria {
            rawCriteria = sanitizeCriteria(persistedCriteria, against: options)
        } else {
            rawCriteria = defaultFilterCriteria(
                for: raw,
                availableModes: availableModes,
                defaultMode: defaultMode,
                nativeMode: nativeMode,
                currentModeOption: currentModeOption,
                options: options
            )
        }

        let filtered = applyCriteria(rawCriteria, to: availableModes)
        let state = DisplayModeFilterState(
            availableOptions: options,
            activeCriteria: rawCriteria,
            isCustomized: isCustomized
        )
        return (filtered, state)
    }

    public static func deriveFilterOptions(from availableModes: [DisplayModeOption]) -> DisplayModeFilterOptions {
        guard !availableModes.isEmpty else {
            return DisplayModeFilterOptions()
        }

        var aspectRatiosByLabel: [String: Double] = [:]
        for mode in availableModes {
            if aspectRatiosByLabel[mode.aspectRatioLabel] == nil, mode.height > 0 {
                aspectRatiosByLabel[mode.aspectRatioLabel] = Double(mode.width) / Double(mode.height)
            }
        }
        let sortedAspects = aspectRatiosByLabel.keys.sorted { lhs, rhs in
            let lhsRatio = aspectRatiosByLabel[lhs] ?? 0
            let rhsRatio = aspectRatiosByLabel[rhs] ?? 0
            if abs(lhsRatio - rhsRatio) > 0.005 {
                return lhsRatio < rhsRatio
            }
            return lhs < rhs
        }

        struct RefreshSortKey {
            let maxRate: Double
            let isVariable: Bool
            let minRate: Double
        }
        var refreshKeysByLabel: [String: RefreshSortKey] = [:]
        for mode in availableModes {
            if let label = mode.refreshRateLabel, refreshKeysByLabel[label] == nil {
                refreshKeysByLabel[label] = RefreshSortKey(
                    maxRate: mode.refreshRate,
                    isVariable: mode.isVRR,
                    minRate: mode.minRefreshRate ?? mode.refreshRate
                )
            }
        }
        let sortedRefreshRates = refreshKeysByLabel.keys.sorted { lhs, rhs in
            guard let lhsKey = refreshKeysByLabel[lhs], let rhsKey = refreshKeysByLabel[rhs] else {
                return lhs < rhs
            }
            if abs(lhsKey.maxRate - rhsKey.maxRate) > 0.005 {
                return lhsKey.maxRate > rhsKey.maxRate
            }
            if lhsKey.isVariable != rhsKey.isVariable {
                return lhsKey.isVariable && !rhsKey.isVariable
            }
            if abs(lhsKey.minRate - rhsKey.minRate) > 0.005 {
                return lhsKey.minRate > rhsKey.minRate
            }
            return lhs > rhs
        }

        let sortedColorDepths = Set(availableModes.map(\.bitsPerSample)).sorted(by: >)
        let presentTiers = Set(availableModes.map(\.scalingTier))
        let sortedScaling = DisplayModeScalingTier.allCases.filter { presentTiers.contains($0) }

        return DisplayModeFilterOptions(
            aspectRatios: sortedAspects,
            refreshRates: sortedRefreshRates,
            colorDepths: sortedColorDepths,
            scalingTiers: sortedScaling
        )
    }

    public static func applyCriteria(
        _ criteria: DisplayModeFilterCriteria,
        to availableModes: [DisplayModeOption]
    ) -> [DisplayModeOption] {
        guard !criteria.isUnrestricted else {
            return availableModes
        }

        return availableModes.filter { mode in
            if !criteria.aspectRatios.isEmpty, !criteria.aspectRatios.contains(mode.aspectRatioLabel) {
                return false
            }
            if !criteria.refreshRates.isEmpty {
                guard let label = mode.refreshRateLabel, criteria.refreshRates.contains(label) else {
                    return false
                }
            }
            if !criteria.colorDepths.isEmpty, !criteria.colorDepths.contains(mode.bitsPerSample) {
                return false
            }
            if !criteria.scalingTiers.isEmpty, !criteria.scalingTiers.contains(mode.scalingTier) {
                return false
            }
            return true
        }
    }

    public static func updatedCriteria(
        from current: DisplayModeFilterCriteria,
        selecting chip: DisplayModeFilterChip,
        multiSelect: Bool
    ) -> DisplayModeFilterCriteria {
        var next = current
        switch chip {
        case .aspectRatio(let label):
            updateChipGroup(&next.aspectRatios, value: label, multiSelect: multiSelect)
        case .refreshRate(let label):
            updateChipGroup(&next.refreshRates, value: label, multiSelect: multiSelect)
        case .colorDepth(let bits):
            updateChipGroup(&next.colorDepths, value: bits, multiSelect: multiSelect)
        case .scaling(let tier):
            updateChipGroup(&next.scalingTiers, value: tier, multiSelect: multiSelect)
        }
        return next
    }

    private static func updateChipGroup<T: Hashable>(
        _ selection: inout Set<T>,
        value: T,
        multiSelect: Bool
    ) {
        if multiSelect {
            if selection.contains(value) {
                selection.remove(value)
            } else {
                selection.insert(value)
            }
        } else {
            selection = [value]
        }
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

    public static func resolveFavoriteModes(
        from records: [Int: FavoriteModeRecord],
        availableModes: [DisplayModeOption]
    ) -> [FavoriteModeSlot] {
        records.keys
            .filter { UserDefaultsFavoriteModesStore.validSlotRange.contains($0) }
            .sorted()
            .compactMap { slot in
                guard let record = records[slot] else { return nil }
                let resolved = resolveFavoriteMode(record: record, availableModes: availableModes)
                return FavoriteModeSlot(slot: slot, record: record, resolvedMode: resolved)
            }
    }

    public static func resolveFavoriteMode(
        record: FavoriteModeRecord,
        availableModes: [DisplayModeOption]
    ) -> DisplayModeOption? {
        if let exact = availableModes.first(where: {
            $0.modeID == record.modeID && matchesFavoriteRecord($0, record: record)
        }) {
            return exact
        }
        return availableModes.first(where: {
            matchesFavoriteRecord($0, record: record)
        })
    }

    public static func matchesFavoriteRecord(_ mode: DisplayModeOption, record: FavoriteModeRecord) -> Bool {
        mode.width == record.width
            && mode.height == record.height
            && mode.pixelWidth == record.pixelWidth
            && mode.pixelHeight == record.pixelHeight
            && abs(mode.refreshRate - record.refreshRate) <= 0.05
            && mode.bitsPerSample == record.bitsPerSample
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

    private static func sanitizeCriteria(
        _ criteria: DisplayModeFilterCriteria,
        against options: DisplayModeFilterOptions
    ) -> DisplayModeFilterCriteria {
        let validAspects = criteria.aspectRatios.intersection(options.aspectRatios)
        let validRates = criteria.refreshRates.intersection(options.refreshRates)
        let validDepths = criteria.colorDepths.intersection(options.colorDepths)
        let validScaling = criteria.scalingTiers.intersection(options.scalingTiers)
        return DisplayModeFilterCriteria(
            aspectRatios: validAspects,
            refreshRates: validRates,
            colorDepths: validDepths,
            scalingTiers: validScaling
        )
    }

    private static func defaultFilterCriteria(
        for raw: RawDisplayInfo,
        availableModes: [DisplayModeOption],
        defaultMode: DisplayModeOption?,
        nativeMode: DisplayModeOption?,
        currentModeOption: DisplayModeOption?,
        options: DisplayModeFilterOptions
    ) -> DisplayModeFilterCriteria {
        guard !availableModes.isEmpty else {
            return .unrestricted
        }

        let nativeAspect = resolveNativeAspectRatio(
            raw: raw,
            defaultMode: defaultMode,
            nativeMode: nativeMode,
            currentModeOption: currentModeOption,
            options: options
        )
        let activeRefreshRate = resolveActiveRefreshRate(
            defaultMode: defaultMode,
            currentModeOption: currentModeOption,
            options: options
        )
        let activeColorDepth = resolveActiveColorDepth(
            defaultMode: defaultMode,
            currentModeOption: currentModeOption,
            options: options
        )
        let preferredScaling = resolvePreferredScalingTier(
            raw: raw,
            availableModes: availableModes,
            defaultMode: defaultMode,
            nativeMode: nativeMode,
            currentModeOption: currentModeOption,
            options: options
        )

        return DisplayModeFilterCriteria(
            aspectRatios: nativeAspect.map { [$0] } ?? [],
            refreshRates: activeRefreshRate.map { [$0] } ?? [],
            colorDepths: activeColorDepth.map { [$0] } ?? [],
            scalingTiers: preferredScaling.map { [$0] } ?? []
        )
    }

    private static func resolveNativeAspectRatio(
        raw: RawDisplayInfo,
        defaultMode: DisplayModeOption?,
        nativeMode: DisplayModeOption?,
        currentModeOption: DisplayModeOption?,
        options: DisplayModeFilterOptions
    ) -> String? {
        if let nativeAspect = nativeMode?.aspectRatioLabel, options.aspectRatios.contains(nativeAspect) {
            return nativeAspect
        }
        if let nativeFlagged = raw.modes.first(where: { $0.isNative && $0.isUsableForDesktopGUI && !$0.isStretched && $0.height >= 720 }) {
            let label = formatAspectRatio(width: nativeFlagged.width, height: nativeFlagged.height)
            if options.aspectRatios.contains(label) {
                return label
            }
        }
        if let defaultAspect = defaultMode?.aspectRatioLabel, options.aspectRatios.contains(defaultAspect) {
            return defaultAspect
        }
        if let currentAspect = currentModeOption?.aspectRatioLabel, options.aspectRatios.contains(currentAspect) {
            return currentAspect
        }
        return options.aspectRatios.first
    }

    private static func resolveActiveRefreshRate(
        defaultMode: DisplayModeOption?,
        currentModeOption: DisplayModeOption?,
        options: DisplayModeFilterOptions
    ) -> String? {
        if let currentRate = currentModeOption?.refreshRateLabel, options.refreshRates.contains(currentRate) {
            return currentRate
        }
        if let defaultRate = defaultMode?.refreshRateLabel, options.refreshRates.contains(defaultRate) {
            return defaultRate
        }
        return options.refreshRates.first
    }

    private static func resolveActiveColorDepth(
        defaultMode: DisplayModeOption?,
        currentModeOption: DisplayModeOption?,
        options: DisplayModeFilterOptions
    ) -> Int? {
        if let currentDepth = currentModeOption?.bitsPerSample, options.colorDepths.contains(currentDepth) {
            return currentDepth
        }
        if let defaultDepth = defaultMode?.bitsPerSample, options.colorDepths.contains(defaultDepth) {
            return defaultDepth
        }
        return options.colorDepths.first
    }

    private static func resolvePreferredScalingTier(
        raw: RawDisplayInfo,
        availableModes: [DisplayModeOption],
        defaultMode: DisplayModeOption?,
        nativeMode: DisplayModeOption?,
        currentModeOption: DisplayModeOption?,
        options: DisplayModeFilterOptions
    ) -> DisplayModeScalingTier? {
        if let defaultMode, options.scalingTiers.contains(defaultMode.scalingTier) {
            return defaultMode.scalingTier
        }
        let nativePixelWidth =
            nativeMode?.pixelWidth
            ?? availableModes.filter { !$0.isHiDPI }.map(\.pixelWidth).max()
            ?? availableModes.map(\.pixelWidth).max()
            ?? 0
        let hiDPICount = availableModes.filter(\.isHiDPI).count
        let prefersHiDPI =
            (raw.isBuiltIn && nativePixelWidth >= 2560)
            || nativePixelWidth >= 3000
            || (currentModeOption?.isHiDPI == true && hiDPICount >= 2)
        if prefersHiDPI, options.scalingTiers.contains(.hiDPI) {
            return .hiDPI
        }
        if !prefersHiDPI, options.scalingTiers.contains(.loDPI) {
            return .loDPI
        }
        return options.scalingTiers.first
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
