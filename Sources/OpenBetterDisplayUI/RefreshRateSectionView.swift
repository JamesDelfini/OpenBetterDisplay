import OpenBetterDisplayCore
import SwiftUI

public struct RefreshRateSectionView: View {
    let display: DisplayState
    @ObservedObject var coordinator: DisplayCoordinator
    @State private var measuredContentHeight: CGFloat?

    private static let maxListHeight: CGFloat = 200

    public init(display: DisplayState, coordinator: DisplayCoordinator) {
        self.display = display
        self.coordinator = coordinator
    }

    private var isExpanded: Bool {
        coordinator.expandedSection == .refreshRate(display.displayID)
    }

    public var body: some View {
        CollapsibleSectionCard(
            isExpanded: isExpanded,
            helpText: "Select Refresh Rate for \(display.name)",
            accessibilityLabel: "Refresh Rate, \(display.refreshRateLabel.isEmpty ? "unavailable" : display.refreshRateLabel)"
        ) {
            coordinator.toggleExpandedSection(.refreshRate(display.displayID))
        } header: {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 18, height: 16, alignment: .center)

            Text("Refresh Rate")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.90))

            Spacer(minLength: 6)

            Text(display.refreshRateLabel.isEmpty ? "—" : display.refreshRateLabel)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.66))
        } content: {
            rateList
        }
    }

    private var resolvedListHeight: CGFloat {
        min(measuredContentHeight ?? estimatedListHeight, Self.maxListHeight)
    }

    private var estimatedListHeight: CGFloat {
        let options = display.refreshRateOptions
        let primaryCount = options.filter { !$0.isNTSC }.count
        let ntscCount = options.filter(\.isNTSC).count
        let totalRows = max(1, primaryCount + ntscCount)
        let rowHeights = CGFloat(totalRows) * 23.0
        let rowSpacing = CGFloat(max(0, totalRows - 1)) * 3.0
        let ntscChrome: CGFloat = ntscCount > 0 ? (primaryCount > 0 ? 34.0 : 20.0) : 0.0
        return ceil(rowHeights + rowSpacing + ntscChrome + 16.0)
    }

    @ViewBuilder
    private var rateList: some View {
        if display.refreshRateOptions.count <= 7 {
            rateListContent
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                rateListContent
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: SectionListHeightPreferenceKey.self,
                                value: geometry.size.height
                            )
                        }
                    )
            }
            .frame(height: resolvedListHeight)
            .onPreferenceChange(SectionListHeightPreferenceKey.self) { height in
                if height > 0 {
                    measuredContentHeight = height
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private var rateListContent: some View {
        let options = display.refreshRateOptions
        let primaryOptions = options.filter { !$0.isNTSC }
        let ntscOptions = options.filter(\.isNTSC)

        VStack(alignment: .leading, spacing: 6) {
            if options.isEmpty {
                Text("No refresh rates exposed")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.50))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            } else {
                if !primaryOptions.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(primaryOptions) { option in
                            RefreshRateRowView(
                                option: option,
                                isSelected: option.modeID == display.currentModeID
                            ) {
                                coordinator.selectRefreshRate(display.displayID, modeID: option.modeID)
                            }
                        }
                    }
                }

                if !ntscOptions.isEmpty {
                    if !primaryOptions.isEmpty {
                        Divider()
                            .overlay(Color.white.opacity(0.08))
                            .padding(.vertical, 1)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("NTSC Refresh Rates")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.54))
                            .padding(.horizontal, 4)

                        ForEach(ntscOptions) { option in
                            RefreshRateRowView(
                                option: option,
                                isSelected: option.modeID == display.currentModeID
                            ) {
                                coordinator.selectRefreshRate(display.displayID, modeID: option.modeID)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

private struct RefreshRateRowView: View {
    let option: RefreshRateOption
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 11, alignment: .center)

                Text(option.label)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(isSelected ? 0.98 : 0.88))
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .selectableRowBackground(isSelected: isSelected, isHovering: isHovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
