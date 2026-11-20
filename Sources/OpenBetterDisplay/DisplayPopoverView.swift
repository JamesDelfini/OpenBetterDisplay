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
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.14).opacity(0.88))
        )
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
            launchAtLogin = enabled
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
                ResolutionControlRow(display: display, coordinator: coordinator)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }
        }
    }

    private var headerPill: some View {
        HStack(spacing: 9) {
            Image(systemName: display.symbolName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 20, alignment: .center)

            Text(display.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)

            if display.isMain {
                MainDisplayBadge()
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.17),
                            Color.white.opacity(0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                )
        )
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

public struct SteppedResolutionSlider: View {
    let stepCount: Int
    let selectedIndex: Int
    let accessibilityValue: String
    let onPreviewStep: (Int) -> Void
    let onCommitStep: (Int) -> Void

    @State private var lastPreviewedIndex: Int?

    private let trackHeight: CGFloat = 5.5
    private let thumbDiameter: CGFloat = 18

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
        GeometryReader { geometry in
            let totalWidth = max(thumbDiameter, geometry.size.width)
            let usableWidth = max(1, totalWidth - thumbDiameter)
            let thumbRadius = thumbDiameter / 2
            let thumbCenterX = thumbRadius + usableWidth * progressFraction

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(height: trackHeight)

                if stepCount > 0 {
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
                    .onChanged { value in
                        guard isInteractive else { return }
                        let index = stepIndex(for: value.location.x, totalWidth: totalWidth)
                        if lastPreviewedIndex != index {
                            lastPreviewedIndex = index
                            onPreviewStep(index)
                        }
                    }
                    .onEnded { value in
                        guard isInteractive else { return }
                        let index = stepIndex(for: value.location.x, totalWidth: totalWidth)
                        lastPreviewedIndex = nil
                        onCommitStep(index)
                    }
            )
        }
        .frame(height: 20)
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

    private func stepIndex(for x: CGFloat, totalWidth: CGFloat) -> Int {
        guard stepCount > 1 else { return 0 }
        let thumbRadius = thumbDiameter / 2
        let usableWidth = max(1, totalWidth - thumbDiameter)
        let clampedX = min(max(x - thumbRadius, 0), usableWidth)
        let fraction = clampedX / usableWidth
        return Int((fraction * CGFloat(stepCount - 1)).rounded())
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
