import SwiftUI

/// Kleiner kreisförmiger Fortschrittsring, ähnlich dem Home-Screen-Widget,
/// zur Visualisierung des Kategorie-Fortschritts in der Mahlzeiten-Liste.
struct CategoryProgressRing: View {
    /// Fortschritt von 0.0 bis 1.0 (wird intern geclamped)
    let progress: Double
    let color: Color
    var isOverLimit: Bool = false
    var lineWidth: CGFloat = 4.5
    var size: CGFloat = 38

    private var clamped: Double { min(max(progress, 0), 1) }
    private var ringColor: Color { isOverLimit ? HyseColor.danger : color }

    var body: some View {
        ZStack {
            Circle()
                .fill(ringColor.opacity(0.14))

            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.35), value: clamped)

            Text("\(Int(clamped * 100))%")
                .font(.system(size: size * 0.27, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .minimumScaleFactor(0.7)
        }
        .frame(width: size, height: size)
    }
}
