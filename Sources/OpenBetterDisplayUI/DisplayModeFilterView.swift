import AppKit
import OpenBetterDisplayCore
import SwiftUI

public struct DisplayModeFilterView: View {
    let displayID: UInt32
    let filterState: DisplayModeFilterState
    @ObservedObject var coordinator: DisplayCoordinator

    public init(
        displayID: UInt32,
        filterState: DisplayModeFilterState,
        coordinator: DisplayCoordinator
    ) {
        self.displayID = displayID
        self.filterState = filterState
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !filterState.availableOptions.aspectRatios.isEmpty {
                chipGroupRow(title: "Aspect") {
                    ForEach(filterState.availableOptions.aspectRatios, id: \.self) { ratio in
                        chipButton(
                            label: ratio.label,
                            chip: .aspectRatio(ratio),
                            accessibilityLabel: "Aspect ratio \(ratio.label)"
                        )
                    }
                }
            }

            if !filterState.availableOptions.refreshRates.isEmpty {
                chipGroupRow(title: "Rate") {
                    ForEach(filterState.availableOptions.refreshRates, id: \.self) { rate in
                        chipButton(
                            label: rate.label,
                            chip: .refreshRate(rate),
                            accessibilityLabel: "Refresh rate \(rate.label)"
                        )
                    }
                }
            }

            if !filterState.availableOptions.colorDepths.isEmpty {
                chipGroupRow(title: "Depth") {
                    ForEach(filterState.availableOptions.colorDepths, id: \.self) { depth in
                        let label = "\(depth)bit"
                        chipButton(
                            label: label,
                            chip: .colorDepth(depth),
                            accessibilityLabel: "Color depth \(label)"
                        )
                    }
                }
            }

            if !filterState.availableOptions.scalingTiers.isEmpty {
                chipGroupRow(title: "Scale") {
                    ForEach(filterState.availableOptions.scalingTiers, id: \.self) { tier in
                        let label = tier == .hiDPI ? "✦ HiDPI" : "LoDPI"
                        chipButton(
                            label: label,
                            chip: .scaling(tier),
                            accessibilityLabel: tier.label
                        )
                    }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            actionBar
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
                )
        )
    }

    private func chipGroupRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.50))
                .frame(width: 38, alignment: .leading)
                .padding(.top, 3)

            FilterChipFlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chipButton(
        label: String,
        chip: DisplayModeFilterChip,
        accessibilityLabel: String
    ) -> some View {
        FilterChipButton(
            label: label,
            isSelected: filterState.isChipSelected(chip),
            accessibilityLabel: accessibilityLabel
        ) {
            let isMultiSelect = NSEvent.modifierFlags.contains(.shift)
            coordinator.selectDisplayModeFilterChip(
                displayID,
                chip: chip,
                multiSelect: isMultiSelect
            )
        }
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            Text("⇧ Multi-select")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)

            Spacer(minLength: 4)

            FilterActionButton(
                title: "Show All",
                isHighlighted: filterState.isShowingAll,
                isEnabled: true
            ) {
                coordinator.showAllDisplayModes(displayID)
            }

            FilterActionButton(
                title: "Reset Default",
                isHighlighted: false,
                isEnabled: filterState.isCustomized
            ) {
                coordinator.resetDisplayModeFilter(displayID)
            }
        }
    }
}

private struct FilterChipButton: View {
    let label: String
    let isSelected: Bool
    let accessibilityLabel: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(isSelected ? 0.96 : 0.74))
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(borderColor, lineWidth: 0.7)
                        )
                )
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help("Click to filter by \(accessibilityLabel); ⇧ Shift+click to multi-select")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Unselected")
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(isHovering ? 0.42 : 0.32)
        }
        return Color.white.opacity(isHovering ? 0.14 : 0.08)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.75)
        }
        return Color.white.opacity(isHovering ? 0.22 : 0.12)
    }
}

private struct FilterActionButton: View {
    let title: String
    let isHighlighted: Bool
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(isEnabled ? (isHighlighted ? 0.96 : 0.84) : 0.38))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(borderColor, lineWidth: 0.7)
                        )
                )
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return Color.white.opacity(0.04)
        }
        if isHighlighted {
            return Color.accentColor.opacity(isHovering ? 0.40 : 0.30)
        }
        return Color.white.opacity(isHovering ? 0.16 : 0.09)
    }

    private var borderColor: Color {
        if !isEnabled {
            return Color.white.opacity(0.08)
        }
        if isHighlighted {
            return Color.accentColor.opacity(0.70)
        }
        return Color.white.opacity(isHovering ? 0.24 : 0.14)
    }
}

private struct FilterChipFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 4
    var verticalSpacing: CGFloat = 4

    private struct Row {
        var items: [(subview: LayoutSubview, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let totalHeight =
            rows.reduce(CGFloat(0)) { $0 + $1.height }
            + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        let widestRow = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widestRow, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var currentY = bounds.minY
        for row in rows {
            var currentX = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: currentX, y: currentY),
                    proposal: ProposedViewSize(item.size)
                )
                currentX += item.size.width + horizontalSpacing
            }
            currentY += row.height + verticalSpacing
        }
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth =
                currentRow.items.isEmpty
                ? size.width
                : currentRow.width + horizontalSpacing + size.width
            if !currentRow.items.isEmpty, proposedWidth > maxWidth {
                rows.append(currentRow)
                currentRow = Row(
                    items: [(subview, size)],
                    width: size.width,
                    height: size.height
                )
            } else {
                currentRow.items.append((subview, size))
                currentRow.width = proposedWidth
                currentRow.height = max(currentRow.height, size.height)
            }
        }

        if !currentRow.items.isEmpty {
            rows.append(currentRow)
        }
        return rows
    }
}
