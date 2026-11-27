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

            HotkeysSectionView(coordinator: coordinator)
                .padding(.bottom, 2)

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

                Toggle(
                    "",
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            setLaunchAtLogin(newValue)
                        }
                    )
                )
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
