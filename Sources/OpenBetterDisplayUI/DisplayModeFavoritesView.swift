import OpenBetterDisplayCore
import SwiftUI

public struct DisplayModeFavoritesView: View {
    let display: DisplayState
    @ObservedObject var coordinator: DisplayCoordinator

    public init(display: DisplayState, coordinator: DisplayCoordinator) {
        self.display = display
        self.coordinator = coordinator
    }

    private var isManaging: Bool {
        coordinator.managingFavoritesDisplayID == display.displayID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow

            if isManaging {
                managePanel
            }

            if display.favoriteModes.isEmpty {
                Text("No favorites added.")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.48))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            } else {
                ForEach(display.favoriteModes) { slotEntry in
                    favoriteRow(for: slotEntry)
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("Favorites:")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))

            Spacer(minLength: 6)

            Button {
                coordinator.toggleManageFavorites(for: display.displayID)
            } label: {
                HStack(spacing: 3) {
                    Text("Manage...")
                        .font(.system(size: 10.5, weight: .medium))
                    Image(systemName: isManaging ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(isManaging ? 0.94 : 0.74))
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(isManaging ? 0.16 : 0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.white.opacity(isManaging ? 0.28 : 0.14), lineWidth: 0.7)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Manage Favorite Modes (slots 1–5)")
            .accessibilityLabel(isManaging ? "Hide Favorite Mode manager" : "Manage Favorite Modes")
        }
        .padding(.horizontal, 4)
    }

    private var managePanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                ForEach(1...5, id: \.self) { slot in
                    let assigned = display.favoriteMode(forSlot: slot)
                    FavoriteSlotManageButton(
                        slot: slot,
                        assignedSlot: assigned,
                        currentResolutionLabel: display.currentModeOption?.resolutionLabel,
                        isCurrentMode: assigned?.resolvedMode?.modeID == display.currentModeID
                    ) {
                        if assigned != nil {
                            coordinator.clearFavoriteMode(display.displayID, slot: slot)
                        } else {
                            coordinator.assignCurrentModeToFavorite(display.displayID, slot: slot)
                        }
                    }
                }
            }

            Text(manageHelperText)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.11), lineWidth: 0.7)
                )
        )
    }

    private var manageHelperText: String {
        if let current = display.currentModeOption {
            return "Click empty slot to save \(current.resolutionLabel); filled to clear."
        }
        return "Click filled slot to clear."
    }

    @ViewBuilder
    private func favoriteRow(for slotEntry: FavoriteModeSlot) -> some View {
        let modeOption = slotEntry.resolvedMode ?? slotEntry.record.fallbackModeOption
        let isSelected = slotEntry.resolvedMode?.modeID == display.currentModeID

        DisplayModeRowView(
            mode: modeOption,
            isSelected: isSelected,
            pinnedMarkers: [],
            favoriteSlot: slotEntry.slot,
            isUnavailable: !slotEntry.isAvailable
        ) {
            coordinator.selectFavoriteMode(display.displayID, slot: slotEntry.slot)
        }
        .disabled(!slotEntry.isAvailable)
        .displayModeFavoriteContextMenu(
            display: display,
            modeID: modeOption.modeID,
            canAssign: slotEntry.isAvailable,
            coordinator: coordinator
        )
    }
}

private struct FavoriteSlotManageButton: View {
    let slot: Int
    let assignedSlot: FavoriteModeSlot?
    let currentResolutionLabel: String?
    let isCurrentMode: Bool
    let action: () -> Void
    @State private var isHovering = false

    private var isOccupied: Bool {
        assignedSlot != nil
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isOccupied ? "circle.fill" : "circle")
                    .font(.system(size: isOccupied ? 7 : 8, weight: .semibold))
                    .foregroundStyle(indicatorColor)

                Text("\(slot)")
                    .font(.system(size: 11, weight: isOccupied ? .semibold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(isOccupied ? 0.96 : 0.64))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 0.8)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isOccupied && currentResolutionLabel == nil)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(tooltipText)
        .accessibilityLabel(accessibilityText)
    }

    private var indicatorColor: Color {
        if isOccupied {
            return isCurrentMode ? Color.white.opacity(0.95) : Color.accentColor.opacity(0.95)
        }
        return Color.white.opacity(isHovering ? 0.65 : 0.38)
    }

    private var backgroundColor: Color {
        if isOccupied {
            return Color.accentColor.opacity(isHovering ? 0.38 : 0.25)
        }
        return Color.white.opacity(isHovering ? 0.11 : 0.05)
    }

    private var borderColor: Color {
        if isOccupied {
            return Color.accentColor.opacity(isCurrentMode ? 0.78 : 0.52)
        }
        return Color.white.opacity(isHovering ? 0.28 : 0.14)
    }

    private var tooltipText: String {
        if let assignedSlot {
            let summary = "\(assignedSlot.record.width)x\(assignedSlot.record.height)"
            return "Favorite \(slot): \(summary). Click to clear."
        }
        if let currentResolutionLabel {
            return "Assign current Display Mode (\(currentResolutionLabel)) to Favorite \(slot)"
        }
        return "Favorite \(slot) is empty"
    }

    private var accessibilityText: String {
        if let assignedSlot {
            return "Favorite slot \(slot), filled with \(assignedSlot.record.width) by \(assignedSlot.record.height)"
        }
        return "Favorite slot \(slot), empty"
    }
}

private struct DisplayModeFavoriteContextMenuModifier: ViewModifier {
    let display: DisplayState
    let modeID: Int32
    let canAssign: Bool
    @ObservedObject var coordinator: DisplayCoordinator

    func body(content: Content) -> some View {
        content.contextMenu {
            if canAssign {
                ForEach(1...5, id: \.self) { slot in
                    let assigned = display.favoriteMode(forSlot: slot)
                    let isAssignedToThisMode = assigned?.matches(modeID: modeID) ?? false

                    Button {
                        coordinator.assignFavoriteMode(display.displayID, modeID: modeID, slot: slot)
                    } label: {
                        Label(
                            assignLabel(for: slot, assigned: assigned, isSameMode: isAssignedToThisMode),
                            systemImage: isAssignedToThisMode
                                ? "checkmark"
                                : (assigned != nil ? "bookmark.fill" : "bookmark")
                        )
                    }
                }
            }

            if display.isFavorited(modeID: modeID) {
                if canAssign {
                    Divider()
                }
                Button(role: .destructive) {
                    coordinator.removeModeFromFavorites(display.displayID, modeID: modeID)
                } label: {
                    Label("Remove from Favorites", systemImage: "bookmark.slash")
                }
            }
        }
    }

    private func assignLabel(for slot: Int, assigned: FavoriteModeSlot?, isSameMode: Bool) -> String {
        if let assigned, !isSameMode {
            return "Assign to Favorite \(slot) (\(assigned.record.width)x\(assigned.record.height))"
        }
        return "Assign to Favorite \(slot)"
    }
}

extension View {
    func displayModeFavoriteContextMenu(
        display: DisplayState,
        modeID: Int32,
        canAssign: Bool = true,
        coordinator: DisplayCoordinator
    ) -> some View {
        modifier(
            DisplayModeFavoriteContextMenuModifier(
                display: display,
                modeID: modeID,
                canAssign: canAssign,
                coordinator: coordinator
            )
        )
    }
}
