import OpenBetterDisplayCore
import SwiftUI

public struct HotkeysSectionView: View {
    @ObservedObject var coordinator: DisplayCoordinator
    @State private var isHeaderHovering = false

    public init(coordinator: DisplayCoordinator) {
        self.coordinator = coordinator
    }

    private var isExpanded: Bool {
        coordinator.expandedSection == .hotkeys
    }

    private var preferences: HotkeyPreferences {
        coordinator.hotkeyPreferences
    }

    private var checkerStatus: KeyboardCheckerStatus {
        coordinator.keyboardCheckerStatus
    }

    private var needsAccessibilityWarning: Bool {
        preferences.isMediaKeysEnabled && !checkerStatus.isAccessibilityTrusted
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerButton

            if isExpanded {
                Divider()
                    .overlay(Color.white.opacity(0.09))
                    .padding(.horizontal, 8)

                expandedContent
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

    private var headerButton: some View {
        Button {
            coordinator.toggleExpandedSection(.hotkeys)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 22, height: 22)
                    Image(systemName: "keyboard")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                }

                Text("Hotkeys")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer(minLength: 6)

                if needsAccessibilityWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.orange.opacity(0.92))
                        .help("Accessibility permission needed for ☀️- / ☀️+ on external displays")
                }

                Text(preferences.targetMode.compactLabel)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 10)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHeaderHovering = hovering
        }
        .help("Configure Brightness Hotkeys, Target Display, and Fn-key checker")
        .accessibilityLabel("Hotkeys, Target Display \(preferences.targetMode.label)")
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            targetDisplaySection

            Divider()
                .overlay(Color.white.opacity(0.08))

            triggersSection

            Divider()
                .overlay(Color.white.opacity(0.08))

            checkerSection
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
    }

    private var targetDisplaySection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Target Display")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))
                .padding(.horizontal, 3)

            ForEach(HotkeyTargetMode.allCases, id: \.self) { mode in
                TargetModeRowView(
                    title: mode.label,
                    isSelected: preferences.targetMode == mode
                ) {
                    coordinator.setHotkeyTargetMode(mode)
                }
            }
        }
    }

    private var triggersSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Brightness Hotkeys")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.54))

                Spacer()

                Text("1/16 step · ⌥⇧ 1/64")
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 3)

            HotkeyToggleRowView(
                title: "Media Keys (☀️- / ☀️+)",
                isOn: Binding(
                    get: { preferences.isMediaKeysEnabled },
                    set: { coordinator.setMediaKeysEnabled($0) }
                )
            )

            HotkeyToggleRowView(
                title: "Bind literal F1 / F2",
                isOn: Binding(
                    get: { preferences.isLiteralF1F2Enabled },
                    set: { coordinator.setLiteralF1F2Enabled($0) }
                )
            )
        }
    }

    private var checkerSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Keyboard & Permission Checker")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))
                .padding(.horizontal, 3)

            CheckerCardView(
                iconName: fnModeIconName,
                iconColor: fnModeIconColor,
                title: fnModeTitle,
                detail: fnModeDetail,
                buttonTitle: "Open Keyboard Settings…"
            ) {
                coordinator.openKeyboardSettings()
            }

            CheckerCardView(
                iconName: checkerStatus.isAccessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                iconColor: checkerStatus.isAccessibilityTrusted ? Color.green.opacity(0.90) : Color.orange.opacity(0.92),
                title: checkerStatus.isAccessibilityTrusted ? "Accessibility: Granted" : "Accessibility: Not Granted",
                detail: accessibilityDetail,
                buttonTitle: checkerStatus.isAccessibilityTrusted ? nil : "Enable Accessibility…"
            ) {
                coordinator.requestAccessibilityPermission()
            }
        }
    }

    private var fnModeIconName: String {
        switch checkerStatus.functionKeyMode {
        case .mediaKeys:
            return "sun.max.fill"
        case .standardFunctionKeys:
            return "fn"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var fnModeIconColor: Color {
        switch checkerStatus.functionKeyMode {
        case .mediaKeys:
            return Color.white.opacity(0.84)
        case .standardFunctionKeys:
            return Color.accentColor.opacity(0.92)
        case .unknown:
            return Color.white.opacity(0.58)
        }
    }

    private var fnModeTitle: String {
        switch checkerStatus.functionKeyMode {
        case .mediaKeys:
            return "Fn Mode: Top-row media keys"
        case .standardFunctionKeys:
            return "Fn Mode: Standard F1–F12 keys"
        case .unknown:
            return "Fn Mode: Unavailable"
        }
    }

    private var fnModeDetail: String {
        switch checkerStatus.functionKeyMode {
        case .mediaKeys:
            return "☀️- / ☀️+ works directly; hold Fn for F1 / F2."
        case .standardFunctionKeys:
            return "Use Fn+F1/F2 for ☀️, or bind literal F1 / F2."
        case .unknown:
            return "Verify top-row key mode in Keyboard Settings."
        }
    }

    private var accessibilityDetail: String {
        if checkerStatus.isAccessibilityTrusted {
            return preferences.isMediaKeysEnabled
                ? "☀️- / ☀️+ active for external displays."
                : "Granted. Enable Media Keys for ☀️- / ☀️+."
        }
        return "Required to intercept ☀️- / ☀️+ on external displays."
    }
}

private struct TargetModeRowView: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 11, alignment: .center)

                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isSelected ? 0.96 : 0.84))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(isHovering ? 0.34 : 0.24)
                            : Color.white.opacity(isHovering ? 0.10 : 0.0)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 0.7)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct HotkeyToggleRowView: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)

            Spacer(minLength: 6)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Color.accentColor)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}

private struct CheckerCardView: View {
    let iconName: String
    let iconColor: Color
    let title: String
    let detail: String
    let buttonTitle: String?
    let action: () -> Void
    @State private var isHoveringButton = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 14, alignment: .center)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.90))
                    .lineLimit(1)

                Spacer()
            }

            Text(detail)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            if let buttonTitle {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor.opacity(isHoveringButton ? 0.40 : 0.26))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.accentColor.opacity(0.48), lineWidth: 0.7)
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringButton = hovering
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7)
                )
        )
    }
}
