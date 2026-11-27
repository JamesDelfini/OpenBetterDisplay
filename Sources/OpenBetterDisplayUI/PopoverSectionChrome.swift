import SwiftUI

struct CollapsibleSectionCard<Header: View, Content: View>: View {
    let isExpanded: Bool
    var headerSpacing: CGFloat = 8
    var headerHorizontalPadding: CGFloat = 10
    var headerVerticalPadding: CGFloat = 7
    let helpText: String
    let accessibilityLabel: String
    let onToggle: () -> Void
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content
    @State private var isHeaderHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: headerSpacing) {
                    header()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 10)
                }
                .padding(.horizontal, headerHorizontalPadding)
                .padding(.vertical, headerVerticalPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHeaderHovering = hovering
            }
            .help(helpText)
            .accessibilityLabel(accessibilityLabel)

            if isExpanded {
                Divider()
                    .overlay(Color.white.opacity(0.09))
                    .padding(.horizontal, 8)

                content()
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
}

struct SectionListHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func selectableRowBackground(
        isSelected: Bool,
        isHovering: Bool,
        isInteractive: Bool = true
    ) -> some View {
        let fillColor: Color =
            if isSelected {
                Color.accentColor.opacity(isHovering && isInteractive ? 0.34 : 0.24)
            } else {
                Color.white.opacity(isHovering && isInteractive ? 0.10 : 0.0)
            }

        return background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.45) : Color.clear,
                            lineWidth: 0.7
                        )
                )
        )
    }
}
