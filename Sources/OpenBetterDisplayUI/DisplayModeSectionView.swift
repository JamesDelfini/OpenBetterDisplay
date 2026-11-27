import OpenBetterDisplayCore
import SwiftUI

public struct DisplayModeSectionView: View {
    let display: DisplayState
    @ObservedObject var coordinator: DisplayCoordinator
    @State private var isHeaderHovering = false
    @State private var measuredContentHeight: CGFloat?

    private static let maxBrowserHeight: CGFloat = 240

    public init(display: DisplayState, coordinator: DisplayCoordinator) {
        self.display = display
        self.coordinator = coordinator
    }

    private var isExpanded: Bool {
        coordinator.expandedSection == .displayMode(display.displayID)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pillHeader

            if isExpanded {
                Divider()
                    .overlay(Color.white.opacity(0.09))
                    .padding(.horizontal, 8)

                browserList
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isExpanded ? 0.08 : (isHeaderHovering ? 0.10 : 0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(isExpanded ? 0.15 : 0.10),
                            lineWidth: 0.8
                        )
                )
        )
    }

    private var pillHeader: some View {
        Button {
            coordinator.toggleExpandedSection(.displayMode(display.displayID))
        } label: {
            HStack(spacing: 8) {
                modeIcon

                Text("Display Mode")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.90))

                Spacer(minLength: 6)

                Text(display.resolutionLabel.isEmpty ? "—" : display.resolutionLabel)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.66))

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 10)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHeaderHovering = hovering
        }
        .help("Select Display Mode for \(display.name)")
        .accessibilityLabel("Display Mode, \(display.resolutionLabel.isEmpty ? "unavailable" : display.resolutionLabel)")
    }

    private var modeIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
                .frame(width: 15, height: 12)

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
        }
        .frame(width: 18, height: 16, alignment: .center)
    }

    private var resolvedBrowserHeight: CGFloat {
        min(measuredContentHeight ?? estimatedListHeight, Self.maxBrowserHeight)
    }

    private var estimatedListHeight: CGFloat {
        let hasPinned = display.defaultMode != nil || display.nativeMode != nil
        let pinnedCount: Int
        if let defaultMode = display.defaultMode, let nativeMode = display.nativeMode {
            pinnedCount = defaultMode.modeID == nativeMode.modeID ? 1 : 2
        } else {
            pinnedCount = hasPinned ? 1 : 0
        }
        let sections = (hasPinned ? 1 : 0) + 1
        let totalRows = pinnedCount + max(1, display.availableModes.count)
        let rowHeights = CGFloat(totalRows) * 23.5
        let rowSpacing = CGFloat(max(0, totalRows - sections)) * 3.0
        let headerHeights = CGFloat(sections) * 18.0
        let dividerAndPadding: CGFloat = (hasPinned ? 15.0 : 0.0) + 16.0
        return ceil(rowHeights + rowSpacing + headerHeights + dividerAndPadding)
    }

    private var browserList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            modeListContent
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: DisplayModeListHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
                )
        }
        .frame(height: resolvedBrowserHeight)
        .onPreferenceChange(DisplayModeListHeightPreferenceKey.self) { height in
            if height > 0 {
                measuredContentHeight = height
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var modeListContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            let hasDefaultOrNative = display.defaultMode != nil || display.nativeMode != nil
            if hasDefaultOrNative {
                defaultAndNativeSection
            }

            if hasDefaultOrNative, !display.availableModes.isEmpty {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.vertical, 1)
            }

            safeModesSection
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var defaultAndNativeSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Default and native modes")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))
                .padding(.horizontal, 4)

            if let defaultMode = display.defaultMode,
                let nativeMode = display.nativeMode,
                defaultMode.modeID == nativeMode.modeID
            {
                DisplayModeRowView(
                    mode: defaultMode,
                    isSelected: defaultMode.modeID == display.currentModeID,
                    pinnedMarkers: [.defaultMode, .nativeMode]
                ) {
                    coordinator.selectDisplayMode(display.displayID, modeID: defaultMode.modeID)
                }
            } else {
                if let defaultMode = display.defaultMode {
                    DisplayModeRowView(
                        mode: defaultMode,
                        isSelected: defaultMode.modeID == display.currentModeID,
                        pinnedMarkers: [.defaultMode]
                    ) {
                        coordinator.selectDisplayMode(display.displayID, modeID: defaultMode.modeID)
                    }
                }
                if let nativeMode = display.nativeMode {
                    DisplayModeRowView(
                        mode: nativeMode,
                        isSelected: nativeMode.modeID == display.currentModeID,
                        pinnedMarkers: [.nativeMode]
                    ) {
                        coordinator.selectDisplayMode(display.displayID, modeID: nativeMode.modeID)
                    }
                }
            }
        }
    }

    private var safeModesSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Available modes")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))
                .padding(.horizontal, 4)

            if display.availableModes.isEmpty {
                Text("No safe 720p+ modes exposed")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.50))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            } else {
                ForEach(display.availableModes) { mode in
                    DisplayModeRowView(
                        mode: mode,
                        isSelected: mode.modeID == display.currentModeID,
                        pinnedMarkers: []
                    ) {
                        coordinator.selectDisplayMode(display.displayID, modeID: mode.modeID)
                    }
                }
            }
        }
    }
}

private enum DisplayModePinnedMarker: Hashable {
    case defaultMode
    case nativeMode

    var symbol: String {
        switch self {
        case .defaultMode:
            return "★"
        case .nativeMode:
            return "≡"
        }
    }

    var helpText: String {
        switch self {
        case .defaultMode:
            return "Default Mode"
        case .nativeMode:
            return "Native Mode"
        }
    }
}

private struct DisplayModeRowView: View {
    let mode: DisplayModeOption
    let isSelected: Bool
    let pinnedMarkers: [DisplayModePinnedMarker]
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 10, alignment: .center)

                ForEach(pinnedMarkers, id: \.self) { marker in
                    Text(marker.symbol)
                        .font(.system(size: marker == .nativeMode ? 11 : 9.5, weight: .bold))
                        .foregroundStyle(marker == .defaultMode ? Color.yellow.opacity(0.88) : Color.white.opacity(0.82))
                        .frame(width: 10, alignment: .center)
                        .help(marker.helpText)
                }

                Text(mode.resolutionLabel)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(isSelected ? 0.98 : 0.88))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 2)

                HStack(spacing: 2.5) {
                    if mode.isHiDPI {
                        DisplayModeBadgeView(
                            text: "✦",
                            isEmphasized: true,
                            helpText: "HiDPI"
                        )
                    }

                    DisplayModeBadgeView(text: mode.aspectRatioLabel)

                    if let refreshRateLabel = mode.refreshRateLabel {
                        DisplayModeBadgeView(text: refreshRateLabel)
                    }

                    DisplayModeBadgeView(
                        text: mode.colorDepthLabel,
                        isEmphasized: mode.bitsPerSample >= 10
                    )
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor.opacity(0.45) : Color.clear,
                                lineWidth: 0.7
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(isHovering ? 0.34 : 0.24)
        }
        return Color.white.opacity(isHovering ? 0.10 : 0.0)
    }
}

private struct DisplayModeBadgeView: View {
    let text: String
    var isEmphasized: Bool = false
    var helpText: String?

    var body: some View {
        let badge = Text(text)
            .font(.system(size: 9, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(isEmphasized ? Color.white.opacity(0.92) : Color.white.opacity(0.70))
            .padding(.horizontal, 3)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isEmphasized ? Color.accentColor.opacity(0.24) : Color.white.opacity(0.09))
            )
            .lineLimit(1)

        if let helpText {
            badge.help(helpText)
        } else {
            badge
        }
    }
}

private struct DisplayModeListHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
