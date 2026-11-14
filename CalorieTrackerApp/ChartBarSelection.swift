import Charts
import SwiftUI

/// Hit-tests the visible bar instead of choosing the nearest date anywhere in
/// the plot. ChartProxy coordinates are relative to its plot frame.
enum ChartBarSelection {
    static func date(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        bars: [(date: Date, value: Double)],
        unit: Calendar.Component
    ) -> Date? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let plot = geometry[plotFrame]
        let x = location.x - plot.minX
        let y = location.y - plot.minY
        guard x >= 0, x <= plot.width, y >= 0, y <= plot.height,
              let zeroY = proxy.position(forY: 0.0) else { return nil }

        for bar in bars where bar.value > 0 {
            guard let barY = proxy.position(forY: bar.value),
                  let xRange = xRange(for: bar.date, unit: unit, proxy: proxy, plotWidth: plot.width, count: bars.count) else { continue }
            let inset = min(6, (xRange.upperBound - xRange.lowerBound) * 0.12)
            let bottom = max(zeroY, barY)
            let top = min(zeroY, barY)
            let hitTop = min(top, bottom - 24)
            if x >= xRange.lowerBound + inset, x <= xRange.upperBound - inset,
               y >= hitTop - 3, y <= bottom + 3 {
                return bar.date
            }
        }
        return nil
    }

    private static func xRange(
        for date: Date,
        unit: Calendar.Component,
        proxy: ChartProxy,
        plotWidth: CGFloat,
        count: Int
    ) -> ClosedRange<CGFloat>? {
        if let range = proxy.positionRange(forX: date), range.upperBound - range.lowerBound > 2 {
            return range
        }
        if let interval = Calendar.current.dateInterval(of: unit, for: date),
           let start = proxy.position(forX: interval.start),
           let end = proxy.position(forX: interval.end), abs(end - start) > 2 {
            return min(start, end)...max(start, end)
        }
        guard let center = proxy.position(forX: date), count > 0 else { return nil }
        let halfWidth = plotWidth / CGFloat(count) / 2
        return (center - halfWidth)...(center + halfWidth)
    }
}
