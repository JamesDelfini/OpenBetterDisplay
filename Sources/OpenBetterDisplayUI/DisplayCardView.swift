import OpenBetterDisplayCore
import SwiftUI

public struct DisplayCardView: View {
    let display: DisplayState
    @ObservedObject var coordinator: DisplayCoordinator

    public init(display: DisplayState, coordinator: DisplayCoordinator) {
        self.display = display
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerPill

            if display.isEnabled {
                displayControls
            }
        }
    }

    private var isMainDisplayDrawerExpanded: Bool {
        coordinator.expandedSection == .mainDisplay(display.displayID)
    }

    @ViewBuilder
    private var displayControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            BrightnessControlRow(display: display, coordinator: coordinator)
            DisplayModeSectionView(display: display, coordinator: coordinator)
            RefreshRateSectionView(display: display, coordinator: coordinator)

            DisplayDisclosureChevron(isExpanded: isMainDisplayDrawerExpanded, displayName: display.name) {
                coordinator.toggleExpandedSection(.mainDisplay(display.displayID))
            }

            if isMainDisplayDrawerExpanded {
                MainDisplayDrawerRow(display: display) {
                    coordinator.setMainDisplay(display.displayID)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
    }

    private var toggleLockReason: DisplayToggleLockReason? {
        coordinator.toggleLockReason(for: display.displayID)
    }

    private var toggleTooltip: String {
        if let lockReason = toggleLockReason {
            return lockReason.tooltip
        }
        return display.isEnabled
            ? "Turn off \(display.name)"
            : "Turn on \(display.name)"
    }

    private var headerPill: some View {
        HStack(spacing: 9) {
            Image(systemName: display.symbolName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(display.isEnabled ? 0.92 : 0.45))
                .frame(width: 20, alignment: .center)

            Text(display.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(display.isEnabled ? 0.95 : 0.50))
                .lineLimit(1)

            if display.isMain {
                MainDisplayBadge()
            }

            Spacer(minLength: 8)

            DisplayPowerToggle(
                isOn: display.isEnabled,
                isDisabled: toggleLockReason != nil,
                tooltip: toggleTooltip,
                accessibilityLabel: "\(display.name) power"
            ) {
                coordinator.toggleDisplayEnabled(display.displayID)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: display.isEnabled
                            ? [
                                Color.white.opacity(0.17),
                                Color.white.opacity(0.10)
                            ]
                            : [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.05)
                            ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(display.isEnabled ? 0.14 : 0.08),
                            lineWidth: 0.8
                        )
                )
        )
    }
}

public struct BrightnessControlRow: View {
    let display: DisplayState
    @ObservedObject var coordinator: DisplayCoordinator

    public init(display: DisplayState, coordinator: DisplayCoordinator) {
        self.display = display
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Brightness")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.68))

                Spacer(minLength: 8)

                Text("\(display.brightnessPercentage)%")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.76))
            }

            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 20, height: 18, alignment: .center)

                HUDBrightnessSlider(
                    value: Binding(
                        get: { display.brightness },
                        set: { newLevel in
                            coordinator.setBrightness(display.displayID, level: newLevel)
                        }
                    ),
                    percentage: display.brightnessPercentage
                )
            }
        }
    }
}

private struct HUDSlider: View {
    let fraction: CGFloat
    let showsFillAndThumb: Bool
    let isInteractive: Bool
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: ((CGFloat) -> Void)?

    private let trackHeight: CGFloat = 5.5
    private let thumbDiameter: CGFloat = 18

    init(
        fraction: CGFloat,
        showsFillAndThumb: Bool = true,
        isInteractive: Bool = true,
        onDragChanged: @escaping (CGFloat) -> Void,
        onDragEnded: ((CGFloat) -> Void)? = nil
    ) {
        self.fraction = min(max(0, fraction), 1)
        self.showsFillAndThumb = showsFillAndThumb
        self.isInteractive = isInteractive
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
    }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = max(thumbDiameter, geometry.size.width)
            let usableWidth = max(1, totalWidth - thumbDiameter)
            let thumbRadius = thumbDiameter / 2
            let thumbCenterX = thumbRadius + usableWidth * fraction

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(height: trackHeight)

                if showsFillAndThumb {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(isInteractive ? 0.92 : 0.72))
                        .frame(width: max(trackHeight, thumbCenterX), height: trackHeight)

                    Circle()
                        .fill(Color.white.opacity(isInteractive ? 0.96 : 0.78))
                        .frame(width: thumbDiameter, height: thumbDiameter)
                        .shadow(color: Color.black.opacity(0.32), radius: 2, x: 0, y: 1)
                        .offset(x: thumbCenterX - thumbRadius)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isInteractive else { return }
                        onDragChanged(normalizedFraction(for: gesture.location.x, usableWidth: usableWidth))
                    }
                    .onEnded { gesture in
                        guard isInteractive, let onDragEnded else { return }
                        onDragEnded(normalizedFraction(for: gesture.location.x, usableWidth: usableWidth))
                    }
            )
        }
        .frame(height: 20)
    }

    private func normalizedFraction(for x: CGFloat, usableWidth: CGFloat) -> CGFloat {
        let thumbRadius = thumbDiameter / 2
        let clampedX = min(max(x - thumbRadius, 0), usableWidth)
        return clampedX / usableWidth
    }
}

private struct HUDBrightnessSlider: View {
    @Binding var value: Double
    let percentage: Int

    var body: some View {
        HUDSlider(
            fraction: CGFloat(max(0.0, min(1.0, value))),
            onDragChanged: { fraction in
                let nextValue = Double(fraction)
                if nextValue != value,
                    nextValue == 0.0 || nextValue == 1.0 || abs(nextValue - value) > 0.0005
                {
                    value = nextValue
                }
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(percentage)%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(1.0, value + 0.05)
            case .decrement:
                value = max(0.0, value - 0.05)
            @unknown default:
                break
            }
        }
    }
}

private struct DisplayDisclosureChevron: View {
    let isExpanded: Bool
    let displayName: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(isHovering ? 0.85 : 0.48))
                Spacer()
            }
            .frame(height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(isExpanded ? "Hide actions for \(displayName)" : "Show actions for \(displayName)")
        .accessibilityLabel(isExpanded ? "Collapse \(displayName) actions" : "Expand \(displayName) actions")
    }
}

private struct MainDisplayDrawerRow: View {
    let display: DisplayState
    let onSetAsMain: () -> Void
    @State private var isHovering = false

    var body: some View {
        if display.isMain {
            rowContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(display.name) is the Main Display")
        } else {
            Button(action: onSetAsMain) {
                rowContent
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(isHovering ? 0.10 : 0.0))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovering = hovering
            }
            .help("Set \(display.name) as Main Display")
            .accessibilityLabel("Set \(display.name) as Main Display")
        }
    }

    private var rowContent: some View {
        let isMain = display.isMain
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        isMain
                            ? Color.white.opacity(0.92)
                            : Color.white.opacity(isHovering ? 0.14 : 0.08)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isMain
                                    ? Color.white.opacity(0.95)
                                    : Color.white.opacity(isHovering ? 0.36 : 0.22),
                                lineWidth: 0.8
                            )
                    )
                    .frame(width: 22, height: 22)

                Text("M")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        isMain
                            ? Color(red: 0.10, green: 0.11, blue: 0.14)
                            : Color.white.opacity(isHovering ? 0.72 : 0.45)
                    )
            }

            Text(isMain ? "Main Display" : "Set as Main Display")
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(
                    isMain
                        ? Color.white.opacity(0.95)
                        : Color.white.opacity(isHovering ? 0.96 : 0.84)
                )

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }
}
