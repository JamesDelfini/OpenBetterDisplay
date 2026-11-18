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
        VStack(alignment: .leading, spacing: 8) {
            headerPill
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
