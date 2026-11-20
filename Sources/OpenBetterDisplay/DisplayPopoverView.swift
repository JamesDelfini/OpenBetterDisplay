import AppKit
import OpenBetterDisplayCore
import ServiceManagement
import SwiftUI

public struct DisplayPopoverView: View {
    @ObservedObject var coordinator: DisplayCoordinator
    @State private var launchAtLogin: Bool = Self.readLaunchAtLoginStatus()

    public init(coordinator: DisplayCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if coordinator.displays.isEmpty {
                emptyStateView
            } else {
                ForEach(coordinator.displays) { display in
                    DisplayCardView(display: display, coordinator: coordinator)
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.12))
                .padding(.vertical, 2)

            footerSection
        }
        .padding(12)
        .frame(width: 320)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.20))
        .preferredColorScheme(.dark)
        .onAppear {
            launchAtLogin = Self.readLaunchAtLoginStatus()
        }
    }

    private var emptyStateView: some View {
        HStack(spacing: 10) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text("No connected displays detected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if coordinator.hasDisconnectedDisplays {
                ReconnectAllDisplaysButton {
                    coordinator.reconnectAllDisplays()
                }
                .padding(.bottom, 4)
            }

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 22, height: 22)
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                }

                Text("Launch at Login")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer()

                Toggle("", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        setLaunchAtLogin(newValue)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 22, height: 22)
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.88))
                    }

                    Text("Quit OpenBetterDisplay")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.92))

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private static func readLaunchAtLoginStatus() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = Self.readLaunchAtLoginStatus()
        } catch {
            launchAtLogin = Self.readLaunchAtLoginStatus()
        }
    }
}

public struct DisplayCardView: View {
    let display: DisplayState
    @ObservedObject var coordinator: DisplayCoordinator

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerPill

            if display.isEnabled {
                displayControls
            }
        }
    }

    private var isExpanded: Bool {
        coordinator.expandedDisplayID == display.displayID
    }

    @ViewBuilder
    private var displayControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            BrightnessControlRow(display: display, coordinator: coordinator)
            ResolutionControlRow(display: display, coordinator: coordinator)

            DisplayDisclosureChevron(isExpanded: isExpanded, displayName: display.name) {
                coordinator.toggleExpandedDisplay(display.displayID)
            }

            if isExpanded {
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

public struct ResolutionControlRow: View {
    let display: DisplayState
    @ObservedObject var coordinator: DisplayCoordinator

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Resolution")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.68))

                Spacer(minLength: 8)

                resolutionMenu
            }

            HStack(spacing: 10) {
                resolutionIcon

                SteppedResolutionSlider(
                    stepCount: display.availableModes.count,
                    selectedIndex: display.activeOrPreviewModeIndex ?? max(0, display.availableModes.count - 1),
                    accessibilityValue: display.resolutionLabel,
                    onPreviewStep: { stepIndex in
                        coordinator.previewResolution(display.displayID, stepIndex: stepIndex)
                    },
                    onCommitStep: { stepIndex in
                        coordinator.previewResolution(display.displayID, stepIndex: stepIndex)
                        coordinator.commitResolution(display.displayID)
                    }
                )
            }
        }
    }

    private var resolutionMenu: some View {
        Menu {
            ForEach(display.availableModes) { mode in
                Button {
                    coordinator.commitResolution(display.displayID, modeID: mode.modeID)
                } label: {
                    if mode.modeID == display.currentModeID {
                        Label(mode.label, systemImage: "checkmark")
                    } else {
                        Text(mode.label)
                    }
                }
            }
        } label: {
            Text(display.resolutionLabel.isEmpty ? "—" : display.resolutionLabel)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(
                    display.previewModeID != nil
                        ? Color.white.opacity(0.95)
                        : Color.white.opacity(0.76)
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(display.availableModes.isEmpty)
        .help("Select Display Resolution")
    }

    private var resolutionIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
                .frame(width: 16, height: 13)

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
        }
        .frame(width: 20, height: 18, alignment: .center)
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

public struct SteppedResolutionSlider: View {
    let stepCount: Int
    let selectedIndex: Int
    let accessibilityValue: String
    let onPreviewStep: (Int) -> Void
    let onCommitStep: (Int) -> Void

    @State private var lastPreviewedIndex: Int?

    private var isInteractive: Bool {
        stepCount > 1
    }

    private var clampedIndex: Int {
        guard stepCount > 0 else { return 0 }
        return min(max(0, selectedIndex), stepCount - 1)
    }

    private var progressFraction: CGFloat {
        guard stepCount > 0 else { return 0 }
        guard stepCount > 1 else { return 1 }
        return CGFloat(clampedIndex) / CGFloat(stepCount - 1)
    }

    public var body: some View {
        HUDSlider(
            fraction: progressFraction,
            showsFillAndThumb: stepCount > 0,
            isInteractive: isInteractive,
            onDragChanged: { fraction in
                let index = stepIndex(for: fraction)
                if lastPreviewedIndex != index {
                    lastPreviewedIndex = index
                    onPreviewStep(index)
                }
            },
            onDragEnded: { fraction in
                let index = stepIndex(for: fraction)
                lastPreviewedIndex = nil
                onCommitStep(index)
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Resolution")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard isInteractive else { return }
            switch direction {
            case .increment:
                let next = min(stepCount - 1, clampedIndex + 1)
                onCommitStep(next)
            case .decrement:
                let previous = max(0, clampedIndex - 1)
                onCommitStep(previous)
            @unknown default:
                break
            }
        }
    }

    private func stepIndex(for fraction: CGFloat) -> Int {
        guard stepCount > 1 else { return 0 }
        return Int((fraction * CGFloat(stepCount - 1)).rounded())
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
                   nextValue == 0.0 || nextValue == 1.0 || abs(nextValue - value) > 0.0005 {
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

public struct MainDisplayBadge: View {
    public init() {}

    public var body: some View {
        Text("M")
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.15))
            .frame(width: 16, height: 16)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.62))
            )
            .help("Main Display")
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

public struct DisplayPowerToggle: View {
    let isOn: Bool
    let isDisabled: Bool
    let tooltip: String
    let accessibilityLabel: String
    let onToggle: () -> Void

    public init(
        isOn: Bool,
        isDisabled: Bool,
        tooltip: String,
        accessibilityLabel: String,
        onToggle: @escaping () -> Void
    ) {
        self.isOn = isOn
        self.isDisabled = isDisabled
        self.tooltip = tooltip
        self.accessibilityLabel = accessibilityLabel
        self.onToggle = onToggle
    }

    public var body: some View {
        ZStack {
            Button(action: onToggle) {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule(style: .continuous)
                        .fill(trackColor)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(isDisabled ? 0.08 : 0.16), lineWidth: 0.7)
                        )
                        .frame(width: 38, height: 20)

                    Capsule(style: .continuous)
                        .fill(thumbColor)
                        .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.8)
                        .frame(width: 20, height: 16)
                        .padding(2)
                }
                .animation(.easeInOut(duration: 0.16), value: isOn)
                .opacity(isDisabled ? 0.45 : 1.0)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isOn ? "On" : "Off")
        }
        .help(tooltip)
    }

    private var trackColor: Color {
        if isOn {
            return isDisabled
                ? Color(red: 0.25, green: 0.30, blue: 0.40)
                : Color(red: 0.23, green: 0.35, blue: 0.56)
        }
        return Color.white.opacity(0.10)
    }

    private var thumbColor: Color {
        isOn ? Color.white.opacity(0.84) : Color.white.opacity(0.62)
    }
}

public struct ReconnectAllDisplaysButton: View {
    let action: () -> Void
    @State private var isHovering = false

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                Text("Reconnect All Displays")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(isHovering ? 0.38 : 0.26))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.48), lineWidth: 0.8)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help("Re-enable every display that is currently turned off")
    }
}
