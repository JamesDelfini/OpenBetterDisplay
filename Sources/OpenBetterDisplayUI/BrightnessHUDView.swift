import OpenBetterDisplayCore
import SwiftUI

/// Compact dark translucent HUD card showing an adjusted external Target Display's brightness.
public struct BrightnessHUDView: View {
    public static let cornerRadius: CGFloat = 16
    public static let preferredWidth: CGFloat = 264

    public let update: BrightnessHUDUpdate

    public init(update: BrightnessHUDUpdate) {
        self.update = update
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: update.symbolName)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 18, alignment: .center)

                Text(update.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text("\(update.brightnessPercentage)%")
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.84))
            }

            HStack(spacing: 9) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.80))
                    .frame(width: 18, alignment: .center)

                BrightnessHUDProgressBar(fraction: update.brightness)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(width: Self.preferredWidth)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.24))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(update.displayName) brightness")
        .accessibilityValue("\(update.brightnessPercentage)%")
    }
}

private struct BrightnessHUDProgressBar: View {
    let fraction: Double
    private let trackHeight: CGFloat = 6

    private var clampedFraction: CGFloat {
        CGFloat(max(0.0, min(1.0, fraction)))
    }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = max(trackHeight, geometry.size.width)
            let fillWidth = clampedFraction > 0 ? max(trackHeight, totalWidth * clampedFraction) : 0

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(height: trackHeight)

                if fillWidth > 0 {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.94))
                        .frame(width: min(totalWidth, fillWidth), height: trackHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 14)
        .animation(.easeOut(duration: 0.08), value: clampedFraction)
    }
}
