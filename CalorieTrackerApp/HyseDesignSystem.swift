import SwiftUI

enum HyseColor {
    /// One non-adaptive brand token. UIKit asset tint and SwiftUI views use
    /// these exact sRGB components, so sheet transitions cannot swap variants.
    static let accent = Color(red: 0.055, green: 0.549, blue: 0.549)
    static let accentStrong = Color(red: 0.025, green: 0.39, blue: 0.39)
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.060, blue: 0.065, alpha: 1)
            : UIColor(red: 0.965, green: 0.970, blue: 0.975, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.085, green: 0.091, blue: 0.097, alpha: 1)
            : UIColor(red: 0.950, green: 0.950, blue: 0.950, alpha: 1)
    })
    static let elevatedSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.110, green: 0.117, blue: 0.123, alpha: 1)
            : UIColor(red: 0.995, green: 0.995, blue: 0.995, alpha: 1)
    })
    static let controlSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.135, green: 0.143, blue: 0.150, alpha: 1)
            : UIColor(red: 0.950, green: 0.950, blue: 0.950, alpha: 1)
    })
    static let border = Color.primary.opacity(0.10)
    // Decorative UI uses only the Hyse accent and neutral system surfaces.
    // Additional hues are reserved for states where color carries meaning.
    static let success = Color(red: 0.12, green: 0.54, blue: 0.32)
    static let warning = Color(red: 0.78, green: 0.48, blue: 0.08)
    static let danger = Color(red: 0.78, green: 0.20, blue: 0.23)
    static let streakFire = Color(red: 0.95, green: 0.18, blue: 0.08)
    static let streakEmber = Color(red: 1.00, green: 0.48, blue: 0.05)
    static let information = accent
}

/// Hyse's own panel silhouette: mostly calm and rectangular, with one precise
/// cut in the upper-right corner. The asymmetry is used for content panels,
/// while controls keep familiar native hit shapes.
struct HysePanelShape: Shape {
    var radius: CGFloat = HyseRadius.card
    var cut: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let c = min(cut, max(rect.width - r * 2, 0))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct HyseBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            HyseColor.background
            if !reduceTransparency {
                HyseFoodPattern(opacity: colorScheme == .dark ? 0.110 : 0.100)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct HyseNutritionBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            HyseColor.background
            if !reduceTransparency {
                HyseFoodPattern(opacity: colorScheme == .dark ? 0.120 : 0.110)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HyseFoodPattern: View {
    private struct Motif: Identifiable {
        let id: Int
        let symbol: String
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let rotation: Double
    }

    let opacity: Double
    private let motifs: [Motif] = [
        Motif(id: 0, symbol: "fork.knife", x: 0.08, y: 0.07, size: 32, rotation: -16),
        Motif(id: 1, symbol: "carrot", x: 0.54, y: 0.10, size: 36, rotation: 18),
        Motif(id: 2, symbol: "cup.and.saucer", x: 0.88, y: 0.16, size: 31, rotation: -10),
        Motif(id: 3, symbol: "takeoutbag.and.cup.and.straw", x: 0.25, y: 0.22, size: 35, rotation: 8),
        Motif(id: 4, symbol: "leaf", x: 0.69, y: 0.28, size: 37, rotation: 22),
        Motif(id: 5, symbol: "fish", x: 0.08, y: 0.35, size: 36, rotation: -7),
        Motif(id: 6, symbol: "birthday.cake", x: 0.45, y: 0.40, size: 32, rotation: -13),
        Motif(id: 7, symbol: "mug", x: 0.87, y: 0.43, size: 34, rotation: 12),
        Motif(id: 8, symbol: "fork.knife", x: 0.20, y: 0.52, size: 29, rotation: 14),
        Motif(id: 9, symbol: "carrot", x: 0.63, y: 0.55, size: 34, rotation: -20),
        Motif(id: 10, symbol: "takeoutbag.and.cup.and.straw", x: 0.92, y: 0.62, size: 32, rotation: -8),
        Motif(id: 11, symbol: "cup.and.saucer", x: 0.35, y: 0.67, size: 30, rotation: 11),
        Motif(id: 12, symbol: "fish", x: 0.72, y: 0.72, size: 35, rotation: 9),
        Motif(id: 13, symbol: "leaf", x: 0.08, y: 0.78, size: 36, rotation: -17),
        Motif(id: 14, symbol: "birthday.cake", x: 0.50, y: 0.84, size: 31, rotation: 8),
        Motif(id: 15, symbol: "mug", x: 0.89, y: 0.89, size: 33, rotation: -12),
        Motif(id: 16, symbol: "fork.knife", x: 0.23, y: 0.94, size: 29, rotation: -10),
        Motif(id: 17, symbol: "carrot", x: 0.66, y: 0.98, size: 33, rotation: 16)
    ]

    var body: some View {
        GeometryReader { proxy in
            ForEach(motifs) { motif in
                Image(systemName: motif.symbol)
                    .font(.system(size: motif.size, weight: .thin))
                    .foregroundStyle(Color.primary.opacity(opacity))
                    .rotationEffect(.degrees(motif.rotation))
                    .position(x: proxy.size.width * motif.x, y: proxy.size.height * motif.y)
            }
        }
    }
}

private struct HyseGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let radius: CGFloat
    var tint: Color? = nil
    var elevated = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    @ViewBuilder
    var body: some View {
        // Keep reusable cards calm and opaque. The system may provide Liquid
        // Glass for navigation chrome, but content surfaces should not all
        // become translucent panels.
        fallbackBody
    }

    private var fallbackBody: some View {
        // Opaque surfaces keep large lists readable and avoid stacking blur
        // layers across the app.
        shape
            .fill((elevated ? HyseColor.elevatedSurface : HyseColor.surface).opacity(surfaceOpacity))
            .overlay {
                if let tint {
                    shape.fill(tint.opacity(colorScheme == .dark ? 0.055 : 0.025))
                }
            }
        .overlay { shape.stroke(glassEdgeColor, lineWidth: 0.5) }
    }

    private var surfaceOpacity: Double {
        1
    }

    private var glassEdgeColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.08)
    }
}

private struct HysePanelBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color?
    private let shape = HysePanelShape()

    private var glassEdgeColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.08)
    }

    @ViewBuilder
    var body: some View {
        fallbackBody
    }

    private var fallbackBody: some View {
        Group {
            shape.fill(HyseColor.elevatedSurface)
                .overlay {
                    shape.fill((tint ?? HyseColor.accent).opacity(tint == nil ? 0.012 : (colorScheme == .dark ? 0.045 : 0.025)))
                }
        }
        .overlay(shape.stroke(glassEdgeColor, lineWidth: 0.5))
    }
}

enum HyseSpacing {
    static let xSmall: CGFloat = 3
    static let small: CGFloat = 6
    static let medium: CGFloat = 10
    static let large: CGFloat = 12
    static let xLarge: CGFloat = 18
    static let page: CGFloat = 16
    static let section: CGFloat = 20
}

enum HyseRadius {
    static let small: CGFloat = 10
    static let control: CGFloat = 12
    static let card: CGFloat = 18
    static let sheet: CGFloat = 20
}

enum HyseMotion {
    static let quick = Animation.easeOut(duration: 0.18)
    static let standard = Animation.spring(response: 0.34, dampingFraction: 0.84)
}

enum HyseStatusStyle {
    case success, information, warning, error, offline

    var color: Color {
        switch self {
        case .success: HyseColor.success
        case .information: HyseColor.information
        case .warning: HyseColor.warning
        case .error: HyseColor.danger
        case .offline: .secondary
        }
    }

    var icon: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .information: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .offline: "icloud.slash.fill"
        }
    }
}

struct HyseCard<Content: View>: View {
    let accent: Color?
    let content: Content
    init(accent: Color? = nil, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }
    var body: some View {
        content
            .padding(HyseSpacing.large)
            .background {
                HysePanelBackground(tint: accent)
                    .overlay(alignment: .leading) {
                        if let accent {
                            Capsule()
                                .fill(accent)
                                .frame(width: 3)
                                .padding(.vertical, HyseSpacing.medium)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .overlay {
                HysePanelShape()
                    .stroke(HyseColor.border).allowsHitTesting(false)
            }
    }
}

/// Shared lead card for food and entry editors. Keeping the same visual
/// hierarchy across create, edit and logging flows makes their next action
/// immediately clear without adding another navigation layer.
struct HyseEditorHero: View {
    let icon: String
    let title: String
    let headline: String
    var detail: String? = nil
    var accent: Color = HyseColor.accent

    var body: some View {
        HyseCard(accent: accent) {
            HStack(alignment: .center, spacing: HyseSpacing.medium) {
                HyseIconBadge(icon: icon, color: accent, size: 46)
                VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(headline)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct HyseIconBadge: View {
    let icon: String
    var color: Color = HyseColor.accent
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.40, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background {
                HysePanelShape(radius: size * 0.24, cut: size * 0.25)
                    .fill(color.opacity(0.14))
                    .overlay(HysePanelShape(radius: size * 0.24, cut: size * 0.25).stroke(color.opacity(0.24), lineWidth: 0.75))
            }
            .accessibilityHidden(true)
    }
}

struct HyseSectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var color: Color = HyseColor.accent
    var infoTitle: String? = nil
    var infoMessage: String? = nil

    var body: some View {
        HStack(spacing: HyseSpacing.medium) {
            if let icon { HyseIconBadge(icon: icon, color: color, size: 34) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let infoTitle, let infoMessage {
                HyseInfoButton(title: infoTitle, message: infoMessage, tint: color)
            }
        }
    }
}

/// A single, consistent explanation affordance used throughout Hyse. It stays
/// attached to its source as a popover instead of navigating away or replacing
/// the current screen with a generic alert.
struct HyseInfoButton: View {
    let title: String
    let message: String
    var tint: Color = HyseColor.accent
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.10), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(message)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                HStack(alignment: .top, spacing: HyseSpacing.medium) {
                    HyseIconBadge(icon: "info.circle.fill", color: tint, size: 36)
                    Text(title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(HyseSpacing.large)
            .frame(idealWidth: 320, maxWidth: 360, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }
}

private struct HyseAlertModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let icon: String
    let tint: Color
    let buttonTitle: String
    let onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        ZStack {
            content

            if isPresented {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: HyseSpacing.large) {
                    HyseIconBadge(icon: icon, color: tint, size: 54)

                    VStack(spacing: HyseSpacing.small) {
                        Text(title)
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.center)

                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        isPresented = false
                        onDismiss?()
                    } label: {
                        Text(buttonTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(tint, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(HyseSpacing.xLarge)
                .frame(maxWidth: 360)
                .background {
                    RoundedRectangle(cornerRadius: HyseRadius.sheet, style: .continuous)
                        .fill(HyseColor.elevatedSurface)
                        .overlay {
                            RoundedRectangle(cornerRadius: HyseRadius.sheet, style: .continuous)
                                .fill(tint.opacity(0.055))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: HyseRadius.sheet, style: .continuous)
                                .stroke(Color.white.opacity(0.32), lineWidth: 0.8)
                        }
                        .shadow(color: .black.opacity(0.24), radius: 28, y: 14)
                }
                .padding(.horizontal, HyseSpacing.page)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : HyseMotion.quick, value: isPresented)
    }
}

struct HyseProgressBar: View {
    let value: Double
    let total: Double
    let colors: [Color]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(HyseColor.border.opacity(0.85))
                Capsule()
                    .fill(colors.first ?? HyseColor.accent)
                    .frame(width: proxy.size.width * min(max(value / max(total, 1), 0), 1))
            }
        }
        .frame(height: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int(min(max(value / max(total, 1), 0), 1) * 100)) percent")
    }
}

struct HyseSegmentedControl<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let symbol: (Item) -> String
    var tint: Color = HyseColor.accent
    @GestureState private var draggedCenterX: CGFloat?

    private let spacing: CGFloat = 5
    private let outerPadding: CGFloat = 4
    private let controlHeight: CGFloat = 46
    private let segmentHeight: CGFloat = 38

    @ViewBuilder
    var body: some View {
        fallbackBody
    }

    private var fallbackBody: some View {
        GeometryReader { proxy in
            let metrics = segmentMetrics(width: proxy.size.width)
            ZStack(alignment: .leading) {
                HyseGlassBackground(radius: 11, tint: tint)
                    .frame(width: metrics.segmentWidth, height: segmentHeight)
                    .offset(x: bubbleLeadingX(metrics: metrics))
                    .allowsHitTesting(false)
                segmentLabels
                    .padding(.horizontal, outerPadding)
            }
            .contentShape(RoundedRectangle(cornerRadius: HyseRadius.control + 3, style: .continuous))
            .simultaneousGesture(selectionDrag(width: proxy.size.width))
            .background { HyseGlassBackground(radius: HyseRadius.control + 3) }
            .overlay(RoundedRectangle(cornerRadius: HyseRadius.control + 3, style: .continuous).stroke(HyseColor.border).allowsHitTesting(false))
        }
        .frame(height: controlHeight)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var segmentLabels: some View {
        HStack(spacing: spacing) {
            ForEach(items, id: \.self) { item in
                Button {
                    withAnimation(HyseMotion.standard) {
                        selection = item
                    }
                } label: {
                    segmentLabel(item, selected: selection == item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func segmentLabel(_ item: Item, selected: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol(item)).font(.caption.weight(.bold))
            Text(title(item)).font(.caption.weight(.bold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 38)
        .foregroundStyle(selected ? tint : Color.secondary)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private struct SegmentMetrics {
        let segmentWidth: CGFloat
        let firstCenterX: CGFloat
        let stride: CGFloat
    }

    private func segmentMetrics(width: CGFloat) -> SegmentMetrics {
        let count = max(items.count, 1)
        let contentWidth = max(0, width - outerPadding * 2)
        let segmentWidth = max(0, (contentWidth - spacing * CGFloat(count - 1)) / CGFloat(count))
        return SegmentMetrics(
            segmentWidth: segmentWidth,
            firstCenterX: outerPadding + segmentWidth / 2,
            stride: segmentWidth + spacing
        )
    }

    private func bubbleLeadingX(metrics: SegmentMetrics) -> CGFloat {
        let index = CGFloat(items.firstIndex(of: selection) ?? 0)
        let restingCenter = metrics.firstCenterX + index * metrics.stride
        return (draggedCenterX ?? restingCenter) - metrics.segmentWidth / 2
    }

    private func selectionDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($draggedCenterX) { value, state, _ in
                guard !items.isEmpty else { return }
                let metrics = segmentMetrics(width: width)
                let lastCenter = metrics.firstCenterX + CGFloat(items.count - 1) * metrics.stride
                state = min(max(value.location.x, metrics.firstCenterX), lastCenter)
            }
            .onChanged { value in
                guard !items.isEmpty else { return }
                let metrics = segmentMetrics(width: width)
                let lastCenter = metrics.firstCenterX + CGFloat(items.count - 1) * metrics.stride
                let center = min(max(value.location.x, metrics.firstCenterX), lastCenter)
                let rawIndex = (center - metrics.firstCenterX) / max(metrics.stride, 1)
                let index = min(max(Int(rawIndex.rounded()), 0), items.count - 1)
                if selection != items[index] { selection = items[index] }
            }
            .onEnded { value in
                guard !items.isEmpty else { return }
                let metrics = segmentMetrics(width: width)
                let lastCenter = metrics.firstCenterX + CGFloat(items.count - 1) * metrics.stride
                let center = min(max(value.location.x, metrics.firstCenterX), lastCenter)
                let rawIndex = (center - metrics.firstCenterX) / max(metrics.stride, 1)
                let index = min(max(Int(rawIndex.rounded()), 0), items.count - 1)
                withAnimation(HyseMotion.standard) {
                    selection = items[index]
                }
            }
    }
}

struct HyseStatusBanner: View {
    let title: String?
    let message: String
    let style: HyseStatusStyle
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: HyseSpacing.medium) {
            Image(systemName: style.icon).font(.title3).foregroundStyle(style.color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                if let title { Text(title).font(.subheadline.weight(.semibold)) }
                Text(message).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action).font(.footnote.weight(.semibold)).padding(.top, HyseSpacing.xSmall)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(HyseSpacing.medium)
        .background(style.color.opacity(0.10), in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(style.color.opacity(0.18)).allowsHitTesting(false))
        .accessibilityElement(children: .combine)
    }
}

struct HyseSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: HyseSpacing.small) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(placeholder, text: $text).textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, HyseSpacing.medium).frame(minHeight: 44)
        .background { HyseGlassBackground(radius: HyseRadius.control) }
        .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border).allowsHitTesting(false))
    }
}

struct HyseEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: HyseSpacing.medium) {
            Image(systemName: icon).font(.system(size: 30, weight: .semibold)).foregroundStyle(HyseColor.accent)
                .padding(HyseSpacing.medium).background(HyseColor.accent.opacity(0.10), in: Circle())
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(HysePrimaryButtonStyle()) }
        }
        .frame(maxWidth: .infinity).padding(HyseSpacing.large)
    }
}

struct HysePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(.white)
            .background(HyseColor.accent.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct HyseSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(HyseColor.accentStrong)
            .background { HyseGlassBackground(radius: HyseRadius.control, tint: HyseColor.accent) }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border).allowsHitTesting(false))
    }
}

struct HyseIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold)).frame(width: 44, height: 44)
            .background { HyseGlassBackground(radius: 22, tint: HyseColor.accent) }
            .opacity(configuration.isPressed ? 0.65 : 1)
            .contentShape(Circle())
    }
}

struct HyseLiftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.025 : 0)
    }
}

private struct HyseScreenModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        toolbarSurface(
            content
            .tint(HyseColor.accent)
            .background(HyseBackdrop())
        )
            .transaction { transaction in if reduceMotion { transaction.animation = nil } }
    }

    @ViewBuilder
    private func toolbarSurface<ContentView: View>(_ content: ContentView) -> some View {
        if #available(iOS 26.0, *) {
            // iOS now supplies the native Liquid Glass chrome. Adding another
            // material layer here makes navigation and tab bars look cloudy.
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(.visible, for: .tabBar)
        } else {
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(HyseColor.surface, for: .navigationBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(HyseColor.surface, for: .tabBar)
        }
    }
}

private struct HyseGlassSurfaceModifier: ViewModifier {
    let radius: CGFloat
    let tint: Color?
    func body(content: Content) -> some View {
        content
            .background { HyseGlassBackground(radius: radius, tint: tint, elevated: true) }
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(HyseColor.border).allowsHitTesting(false))
    }
}

private struct HyseFormModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(HyseBackdrop())
            .listSectionSpacing(HyseSpacing.medium)
            .listRowSpacing(5)
            .listRowSeparatorTint(HyseColor.border)
            .environment(\.defaultMinListRowHeight, 40)
            .environment(\.defaultMinListHeaderHeight, 24)
    }
}

extension View {
    func hyseScreen() -> some View { modifier(HyseScreenModifier()) }
    func hyseForm() -> some View { modifier(HyseFormModifier()) }
    func hyseField() -> some View {
        padding(.horizontal, HyseSpacing.medium).frame(minHeight: 44)
            .background { HyseGlassBackground(radius: HyseRadius.control) }
            .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border).allowsHitTesting(false))
    }
    func hyseGlassSurface(radius: CGFloat = HyseRadius.card, tint: Color? = nil) -> some View {
        modifier(HyseGlassSurfaceModifier(radius: radius, tint: tint))
    }
    func hyseGlassListRows(accent: Color? = nil) -> some View {
        listRowBackground(HyseGlassBackground(radius: HyseRadius.control, tint: accent))
        .listRowSeparatorTint(HyseColor.border)
    }
    func hyseAlert(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        icon: String = "exclamationmark.triangle.fill",
        tint: Color = HyseColor.warning,
        buttonTitle: String,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(HyseAlertModifier(
            isPresented: isPresented,
            title: title,
            message: message,
            icon: icon,
            tint: tint,
            buttonTitle: buttonTitle,
            onDismiss: onDismiss
        ))
    }
}
