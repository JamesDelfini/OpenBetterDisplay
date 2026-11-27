import Foundation

public enum DisplayModeFilter {
    private static let knownAspectRatios: [(ratio: Double, key: AspectRatioFilterKey, tolerance: Double)] = [
        (5.0 / 4.0, AspectRatioFilterKey(5, 4), 0.015),
        (4.0 / 3.0, AspectRatioFilterKey(4, 3), 0.015),
        (3.0 / 2.0, AspectRatioFilterKey(3, 2), 0.015),
        (16.0 / 10.0, AspectRatioFilterKey(16, 10), 0.015),
        (16.0 / 9.0, AspectRatioFilterKey(16, 9), 0.015),
        (19.0 / 10.0, AspectRatioFilterKey(19, 10), 0.015),
        (24.0 / 10.0, AspectRatioFilterKey(24, 10), 0.015),
        (21.0 / 9.0, AspectRatioFilterKey(21, 9), 0.04),
        (32.0 / 9.0, AspectRatioFilterKey(32, 9), 0.02)
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
            let lhsVariable = normalizeVariableRefreshRate(
                isVariableRefreshRate: lhs.isVariableRefreshRate,
                minRefreshRate: lhs.minRefreshRate,
                maxRefreshRate: lhs.refreshRate
            )
            let rhsVariable = normalizeVariableRefreshRate(
                isVariableRefreshRate: rhs.isVariableRefreshRate,
                minRefreshRate: rhs.minRefreshRate,
                maxRefreshRate: rhs.refreshRate
            )
            if lhs.isProMotion != rhs.isProMotion {
                return lhs.isProMotion && !rhs.isProMotion
            }
            if lhsVariable.isVariableRefreshRate != rhsVariable.isVariableRefreshRate {
                return lhsVariable.isVariableRefreshRate && !rhsVariable.isVariableRefreshRate
            }
            if let lhsMin = lhsVariable.minRefreshRate,
                let rhsMin = rhsVariable.minRefreshRate,
                abs(lhsMin - rhsMin) > 0.01
            {
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
        context: DisplayModeContext,
        persistedCriteria: DisplayModeFilterCriteria?
    ) -> (filteredModes: [DisplayModeOption], filterState: DisplayModeFilterState) {
        let options = deriveFilterOptions(from: context.availableModes)
        let isCustomized = persistedCriteria != nil
        let rawCriteria: DisplayModeFilterCriteria
        if let persistedCriteria {
            rawCriteria = sanitizeCriteria(persistedCriteria, against: options)
        } else {
            rawCriteria = defaultFilterCriteria(context: context, options: options)
        }

        let filtered = applyCriteria(rawCriteria, to: context.availableModes)
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

        let sortedAspects = Set(availableModes.map(\.aspectRatioKey)).sorted()
        let sortedRefreshRates = Set(availableModes.compactMap(\.refreshRateKey)).sorted(by: >)
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
            if !criteria.aspectRatios.isEmpty, !criteria.aspectRatios.contains(mode.aspectRatioKey) {
                return false
            }
            if !criteria.refreshRates.isEmpty {
                guard let rateKey = mode.refreshRateKey, criteria.refreshRates.contains(rateKey) else {
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
        case .aspectRatio(let ratio):
            updateChipGroup(&next.aspectRatios, value: ratio, multiSelect: multiSelect)
        case .refreshRate(let rate):
            updateChipGroup(&next.refreshRates, value: rate, multiSelect: multiSelect)
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
            && mode.isVariableRefreshRate == record.isVariableRefreshRate
            && (!record.isProMotion || mode.isProMotion)
            && matchesMinRefreshRate(mode.minRefreshRate, record.minRefreshRate)
    }

    public static func fallbackModeOption(for record: FavoriteModeRecord) -> DisplayModeOption {
        makeModeOption(
            mode: RawDisplayMode(
                modeID: record.modeID,
                width: record.width,
                height: record.height,
                pixelWidth: record.pixelWidth,
                pixelHeight: record.pixelHeight,
                refreshRate: record.refreshRate,
                bitsPerSample: record.bitsPerSample,
                isVariableRefreshRate: record.isVariableRefreshRate,
                isProMotion: record.isProMotion,
                minRefreshRate: record.minRefreshRate
            )
        )
    }

    private static func matchesMinRefreshRate(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.some(let left), .some(let right)):
            return abs(left - right) <= 0.05
        default:
            return false
        }
    }

    public static func makeModeOption(mode: RawDisplayMode) -> DisplayModeOption {
        let isHiDPI = isHiDPIMode(mode)
        let isOneToOneNative = mode.isNative && mode.width == mode.pixelWidth && mode.height == mode.pixelHeight
        let bits = max(1, mode.bitsPerSample)
        let variableRate = normalizeVariableRefreshRate(
            isVariableRefreshRate: mode.isVariableRefreshRate || mode.isProMotion,
            minRefreshRate: mode.minRefreshRate,
            maxRefreshRate: mode.refreshRate
        )
        let isProMotion = mode.isProMotion && variableRate.isVariableRefreshRate
        let aspectKey = aspectRatioKey(width: mode.width, height: mode.height)
        let rateKey: RefreshRateFilterKey? =
            mode.refreshRate > 0.5
            ? RefreshRateFilterKey(
                isVariableRefreshRate: variableRate.isVariableRefreshRate,
                isProMotion: isProMotion,
                minRefreshRate: variableRate.minRefreshRate,
                maxRefreshRate: mode.refreshRate
            )
            : nil

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
            isVariableRefreshRate: variableRate.isVariableRefreshRate,
            isProMotion: isProMotion,
            minRefreshRate: variableRate.minRefreshRate,
            aspectRatioKey: aspectKey,
            refreshRateKey: rateKey,
            aspectRatioLabel: aspectKey.label,
            refreshRateLabel: formatShortRefreshRate(
                refreshRate: mode.refreshRate,
                isVariableRefreshRate: variableRate.isVariableRefreshRate,
                isProMotion: isProMotion,
                minRefreshRate: variableRate.minRefreshRate
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

        var grouped: [RefreshRateFilterKey: DisplayModeOption] = [:]
        for mode in matchingModes {
            let key =
                mode.refreshRateKey
                ?? RefreshRateFilterKey(
                    isVariableRefreshRate: mode.isVariableRefreshRate,
                    isProMotion: mode.isProMotion,
                    minRefreshRate: mode.minRefreshRate,
                    maxRefreshRate: mode.refreshRate
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
            if !lhs.isNTSC, lhs.isProMotion != rhs.isProMotion {
                return lhs.isProMotion && !rhs.isProMotion
            }
            if !lhs.isNTSC, lhs.isVariableRefreshRate != rhs.isVariableRefreshRate {
                return lhs.isVariableRefreshRate && !rhs.isVariableRefreshRate
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
        context: DisplayModeContext,
        options: DisplayModeFilterOptions
    ) -> DisplayModeFilterCriteria {
        guard !context.availableModes.isEmpty else {
            return .unrestricted
        }

        let nativeAspect = resolveNativeAspectRatio(context: context, options: options)
        let activeRefreshRate = resolveActiveRefreshRate(context: context, options: options)
        let activeColorDepth = resolveActiveColorDepth(context: context, options: options)
        let preferredScaling = resolvePreferredScalingTier(context: context, options: options)

        return DisplayModeFilterCriteria(
            aspectRatios: nativeAspect.map { [$0] } ?? [],
            refreshRates: activeRefreshRate.map { [$0] } ?? [],
            colorDepths: activeColorDepth.map { [$0] } ?? [],
            scalingTiers: preferredScaling.map { [$0] } ?? []
        )
    }

    private static func resolveNativeAspectRatio(
        context: DisplayModeContext,
        options: DisplayModeFilterOptions
    ) -> AspectRatioFilterKey? {
        if let nativeAspect = context.nativeMode?.aspectRatioKey, options.aspectRatios.contains(nativeAspect) {
            return nativeAspect
        }
        if let nativeFlagged = context.raw.modes.first(where: {
            $0.isNative && $0.isUsableForDesktopGUI && !$0.isStretched && $0.height >= 720
        }) {
            let key = aspectRatioKey(width: nativeFlagged.width, height: nativeFlagged.height)
            if options.aspectRatios.contains(key) {
                return key
            }
        }
        if let defaultAspect = context.defaultMode?.aspectRatioKey, options.aspectRatios.contains(defaultAspect) {
            return defaultAspect
        }
        if let currentAspect = context.currentModeOption?.aspectRatioKey, options.aspectRatios.contains(currentAspect) {
            return currentAspect
        }
        return options.aspectRatios.first
    }

    private static func resolveActiveRefreshRate(
        context: DisplayModeContext,
        options: DisplayModeFilterOptions
    ) -> RefreshRateFilterKey? {
        if let currentRate = context.currentModeOption?.refreshRateKey, options.refreshRates.contains(currentRate) {
            return currentRate
        }
        if let defaultRate = context.defaultMode?.refreshRateKey, options.refreshRates.contains(defaultRate) {
            return defaultRate
        }
        return options.refreshRates.first
    }

    private static func resolveActiveColorDepth(
        context: DisplayModeContext,
        options: DisplayModeFilterOptions
    ) -> Int? {
        if let currentDepth = context.currentModeOption?.bitsPerSample, options.colorDepths.contains(currentDepth) {
            return currentDepth
        }
        if let defaultDepth = context.defaultMode?.bitsPerSample, options.colorDepths.contains(defaultDepth) {
            return defaultDepth
        }
        return options.colorDepths.first
    }

    private static func resolvePreferredScalingTier(
        context: DisplayModeContext,
        options: DisplayModeFilterOptions
    ) -> DisplayModeScalingTier? {
        if let defaultMode = context.defaultMode, options.scalingTiers.contains(defaultMode.scalingTier) {
            return defaultMode.scalingTier
        }
        let nativePixelWidth =
            context.nativeMode?.pixelWidth
            ?? context.availableModes.filter { !$0.isHiDPI }.map(\.pixelWidth).max()
            ?? context.availableModes.map(\.pixelWidth).max()
            ?? 0
        let hiDPICount = context.availableModes.filter(\.isHiDPI).count
        let prefersHiDPI =
            (context.raw.isBuiltIn && nativePixelWidth >= 2560)
            || nativePixelWidth >= 3000
            || (context.currentModeOption?.isHiDPI == true && hiDPICount >= 2)
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

    static func aspectRatioKey(width: Int, height: Int) -> AspectRatioFilterKey {
        guard width > 0, height > 0 else {
            return AspectRatioFilterKey(0, 0)
        }
        let ratio = Double(width) / Double(height)

        for entry in knownAspectRatios {
            if abs(ratio - entry.ratio) <= entry.tolerance {
                return entry.key
            }
        }

        let divisor = gcd(width, height)
        let simplifiedW = width / divisor
        let simplifiedH = height / divisor
        if simplifiedH <= 20 {
            return AspectRatioFilterKey(simplifiedW, simplifiedH)
        }

        let tenths = Int((ratio * 100.0).rounded())
        if tenths % 10 == 0 {
            return AspectRatioFilterKey(tenths / 10, 10)
        }
        return AspectRatioFilterKey(widthTenths: tenths, heightTenths: 100)
    }

    static func normalizeVariableRefreshRate(
        isVariableRefreshRate: Bool,
        minRefreshRate: Double?,
        maxRefreshRate: Double
    ) -> (isVariableRefreshRate: Bool, minRefreshRate: Double?) {
        guard isVariableRefreshRate else {
            return (false, nil)
        }
        if let minRefreshRate,
            minRefreshRate > 0.5,
            minRefreshRate < maxRefreshRate - 0.5
        {
            return (true, minRefreshRate)
        }
        return (true, nil)
    }

    private static func makeRefreshRateOption(from mode: DisplayModeOption) -> RefreshRateOption {
        let variableRate = normalizeVariableRefreshRate(
            isVariableRefreshRate: mode.isVariableRefreshRate || mode.isProMotion,
            minRefreshRate: mode.minRefreshRate,
            maxRefreshRate: mode.refreshRate
        )
        let isProMotion = mode.isProMotion && variableRate.isVariableRefreshRate
        let isNTSC = isNTSCRefreshRate(mode.refreshRate, isVariableRefreshRate: variableRate.isVariableRefreshRate)
        let shortLabel =
            formatShortRefreshRate(
                refreshRate: mode.refreshRate,
                isVariableRefreshRate: variableRate.isVariableRefreshRate,
                isProMotion: isProMotion,
                minRefreshRate: variableRate.minRefreshRate
            ) ?? ""
        let label: String
        if isProMotion {
            label = "ProMotion (Variable)"
        } else if variableRate.isVariableRefreshRate {
            label = "\(shortLabel) (Variable)"
        } else {
            label = shortLabel
        }

        return RefreshRateOption(
            modeID: mode.modeID,
            refreshRate: mode.refreshRate,
            minRefreshRate: variableRate.minRefreshRate,
            isVariableRefreshRate: variableRate.isVariableRefreshRate,
            isProMotion: isProMotion,
            isNTSC: isNTSC,
            label: label,
            shortLabel: shortLabel
        )
    }

    private static func isNTSCRefreshRate(_ refreshRate: Double, isVariableRefreshRate: Bool) -> Bool {
        guard !isVariableRefreshRate, refreshRate > 0.5 else { return false }
        return abs(refreshRate - refreshRate.rounded()) >= 0.01
    }

    private static func formatShortRefreshRate(
        refreshRate: Double,
        isVariableRefreshRate: Bool,
        isProMotion: Bool = false,
        minRefreshRate: Double?
    ) -> String? {
        guard refreshRate > 0.5 else { return nil }
        let key = RefreshRateFilterKey(
            isVariableRefreshRate: isVariableRefreshRate,
            isProMotion: isProMotion,
            minRefreshRate: minRefreshRate,
            maxRefreshRate: refreshRate
        )
        if key.isProMotion {
            return key.label
        }
        if key.isVariableRefreshRate,
            key.minHundredths == nil,
            let maxNumber = RefreshRateFilterKey.formatRateNumber(hundredths: key.maxHundredths)
        {
            return "\(maxNumber)Hz"
        }
        return key.label
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
