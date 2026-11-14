import SwiftUI
import Charts
import Combine

enum TrainingChartRange: String, CaseIterable, Identifiable {
    case oneMonth, threeMonths, oneYear, allTime
    var id: String { rawValue }
    var localizationKey: String { "chart.range.\(rawValue)" }

    func includes(_ date: Date, relativeTo endDate: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard self != .allTime else { return true }
        let component: Calendar.Component = self == .oneYear ? .year : .month
        let amount = self == .oneMonth ? -1 : self == .threeMonths ? -3 : -1
        guard let start = calendar.date(byAdding: component, value: amount, to: endDate) else { return true }
        return date >= start && date <= endDate
    }
}

struct ExerciseMovementVisual: View {
    let exercise: TrainingExercise
    var height: CGFloat = 48

    private var isGerman: Bool {
        Locale.current.language.languageCode?.identifier == "de"
    }

    private func initialsVisual<S: InsettableShape>(shape: S) -> some View {
        ZStack {
            shape
                .fill(HyseColor.accent.opacity(height >= 120 ? 0.14 : 0.11))
            Text(exercise.initials(isGerman: isGerman))
                .font(.system(size: min(max(16, height * 0.34), 56), weight: .bold, design: .rounded))
                .foregroundStyle(HyseColor.accent)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .padding(height * 0.12)
        }
        .frame(width: height, height: height)
        .clipShape(shape)
        .overlay {
            shape.stroke(HyseColor.border.opacity(0.65), lineWidth: 0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(exercise.displayName(isGerman: isGerman))
    }

    @ViewBuilder
    var body: some View {
        if height >= 120 {
            initialsVisual(shape: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
        } else {
            // Compact exercise rows use a circular avatar. Keeping the fill
            // circular here prevents the old inner rectangle from leaving
            // empty corners when the caller also clips the view to a circle.
            initialsVisual(shape: Circle())
        }
    }
}

private struct ExercisePoseCanvas: View {
    let kind: ExerciseVisualKind
    let equipment: TrainingEquipment
    let phase: Double

    var body: some View {
        Canvas { context, size in
            let accent = Color.accentColor
            let body = Color.primary.opacity(0.88)
            let muted = Color.secondary.opacity(0.45)
            let w = size.width
            let h = size.height
            func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: w * x, y: h * y) }
            func line(_ points: [CGPoint], color: Color = body, width: CGFloat? = nil) {
                guard let first = points.first else { return }
                var path = Path(); path.move(to: first)
                for value in points.dropFirst() { path.addLine(to: value) }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width ?? max(2, min(w, h) * 0.055), lineCap: .round, lineJoin: .round))
            }
            func head(_ center: CGPoint, radius: CGFloat? = nil) {
                let r = radius ?? max(3, min(w, h) * 0.09)
                context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(body))
            }
            func joint(_ center: CGPoint) {
                let r = max(1.5, min(w, h) * 0.035)
                context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(accent))
            }
            func bar(_ a: CGPoint, _ b: CGPoint) {
                line([a, b], color: accent, width: max(2, min(w, h) * 0.045))
                let plate = max(3, min(w, h) * 0.075)
                for center in [a, b] {
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - plate / 2, y: center.y - plate, width: plate, height: plate * 2)), with: .color(accent), lineWidth: 2)
                }
            }

            let p = phase
            if equipment == .machine || equipment == .cable {
                line([point(0.13, 0.90), point(0.13, 0.12), point(0.87, 0.12), point(0.87, 0.90)], color: muted, width: max(1, min(w, h) * 0.025))
                line([point(0.10, 0.90), point(0.90, 0.90)], color: muted, width: max(1, min(w, h) * 0.025))
            } else if equipment == .bands {
                var band = Path()
                band.move(to: point(0.16, 0.88))
                band.addCurve(to: point(0.84, 0.88), control1: point(0.28, 0.72), control2: point(0.72, 0.72))
                context.stroke(band, with: .color(accent.opacity(0.65)), style: StrokeStyle(lineWidth: max(1.5, min(w, h) * 0.025), lineCap: .round))
            }
            switch kind {
            case .press:
                let shoulder = point(0.50, 0.38), hip = point(0.50, 0.64)
                let handY = 0.34 - 0.23 * p
                let leftHand = point(0.30, handY), rightHand = point(0.70, handY)
                head(point(0.50, 0.24)); line([shoulder, hip]); line([hip, point(0.38, 0.90)]); line([hip, point(0.62, 0.90)])
                line([shoulder, point(0.36, 0.46 - 0.12 * p), leftHand]); line([shoulder, point(0.64, 0.46 - 0.12 * p), rightHand]); bar(leftHand, rightHand)
                joint(shoulder)
            case .row:
                let hip = point(0.48, 0.58), shoulder = point(0.62, 0.38), knee = point(0.38, 0.72)
                let hand = point(0.48 - 0.18 * p, 0.49 + 0.13 * p)
                head(point(0.70, 0.28)); line([point(0.70, 0.31), shoulder, hip]); line([hip, knee, point(0.25, 0.91)]); line([hip, point(0.68, 0.88)])
                line([shoulder, point(0.56, 0.50), hand]); bar(point(hand.x, hand.y - 5), point(hand.x, hand.y + 5)); joint(shoulder)
            case .squat:
                let drop = 0.14 * p, shoulder = point(0.50, 0.34 + drop), hip = point(0.50, 0.57 + drop)
                head(point(0.50, 0.20 + drop)); line([shoulder, hip]); line([shoulder, point(0.31, 0.43 + drop), point(0.23, 0.34 + drop)]); line([shoulder, point(0.69, 0.43 + drop), point(0.77, 0.34 + drop)])
                line([hip, point(0.33, 0.72 + drop * 0.25), point(0.29, 0.93)]); line([hip, point(0.67, 0.72 + drop * 0.25), point(0.71, 0.93)]); bar(point(0.25, 0.32 + drop), point(0.75, 0.32 + drop)); joint(hip)
            case .hinge:
                let lean = 0.18 * p, hip = point(0.48, 0.58), shoulder = point(0.50 + lean, 0.34 + lean * 0.35)
                head(point(0.52 + lean, 0.20 + lean * 0.35)); line([shoulder, hip]); line([hip, point(0.38, 0.75), point(0.35, 0.93)]); line([hip, point(0.62, 0.75), point(0.65, 0.93)])
                let hand = point(0.58 + lean, 0.70 - 0.18 * p); line([shoulder, point(0.61 + lean, 0.51), hand]); bar(point(hand.x - w * 0.18, hand.y), point(hand.x + w * 0.18, hand.y)); joint(hip)
            case .pull:
                let rise = 0.14 * p, shoulder = point(0.50, 0.42 - rise), hip = point(0.50, 0.66 - rise)
                let leftHand = point(0.27, 0.10), rightHand = point(0.73, 0.10)
                line([point(0.20, 0.10), point(0.80, 0.10)], color: accent); head(point(0.50, 0.29 - rise)); line([shoulder, hip]); line([shoulder, point(0.36, 0.28 - rise * 0.5), leftHand]); line([shoulder, point(0.64, 0.28 - rise * 0.5), rightHand]); line([hip, point(0.42, 0.91 - rise)]); line([hip, point(0.58, 0.91 - rise)]); joint(shoulder)
            case .raise:
                let shoulder = point(0.50, 0.38), hip = point(0.50, 0.65), handY = 0.72 - 0.38 * p
                head(point(0.50, 0.23)); line([shoulder, hip]); line([hip, point(0.40, 0.92)]); line([hip, point(0.60, 0.92)]); line([shoulder, point(0.34, (0.40 + handY) / 2), point(0.20, handY)]); line([shoulder, point(0.66, (0.40 + handY) / 2), point(0.80, handY)]); joint(shoulder)
            case .curl:
                let shoulder = point(0.50, 0.37), hip = point(0.50, 0.65), handY = 0.72 - 0.29 * p
                head(point(0.50, 0.22)); line([shoulder, hip]); line([hip, point(0.40, 0.92)]); line([hip, point(0.60, 0.92)]); line([shoulder, point(0.35, 0.52), point(0.30, handY)]); line([shoulder, point(0.65, 0.52), point(0.70, handY)]); joint(point(0.35, 0.52)); joint(point(0.65, 0.52))
            case .core:
                let lift = 0.05 * p, shoulder = point(0.34, 0.52 - lift), hip = point(0.62, 0.58 - lift)
                head(point(0.22, 0.45 - lift)); line([shoulder, hip, point(0.86, 0.72)]); line([shoulder, point(0.28, 0.73), point(0.18, 0.74)]); line([hip, point(0.72, 0.74)]); joint(shoulder); line([point(0.12, 0.77), point(0.91, 0.77)], color: muted, width: 1)
            case .lunge:
                let drop = 0.11 * p, shoulder = point(0.50, 0.34 + drop), hip = point(0.50, 0.59 + drop)
                head(point(0.50, 0.20 + drop)); line([shoulder, hip]); line([shoulder, point(0.34, 0.63)]); line([shoulder, point(0.66, 0.63)]); line([hip, point(0.33, 0.70 + drop), point(0.20, 0.91)]); line([hip, point(0.67, 0.76), point(0.82, 0.91)]); joint(hip)
            case .run:
                let shoulder = point(0.50, 0.35), hip = point(0.50, 0.60)
                head(point(0.54, 0.20)); line([shoulder, hip]); line([shoulder, point(0.35 + 0.14 * p, 0.48), point(0.26 + 0.28 * p, 0.39)]); line([shoulder, point(0.65 - 0.14 * p, 0.49), point(0.74 - 0.28 * p, 0.62)]); line([hip, point(0.35 + 0.28 * p, 0.73), point(0.22 + 0.48 * p, 0.91)]); line([hip, point(0.65 - 0.28 * p, 0.75), point(0.78 - 0.48 * p, 0.91)]); joint(hip)
            case .cycle:
                let center = point(0.56, 0.69), radius = min(w, h) * 0.19
                context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(accent), lineWidth: 2)
                let hip = point(0.50, 0.49), shoulder = point(0.62, 0.31); head(point(0.68, 0.20)); line([shoulder, hip]); line([shoulder, point(0.78, 0.42)]); let angle = p * .pi * 2; let pedal = CGPoint(x: center.x + cos(angle) * radius * 0.55, y: center.y + sin(angle) * radius * 0.55); line([hip, point(0.50, 0.66), pedal]); joint(pedal)
            case .rowing:
                let slide = 0.17 * p, hip = point(0.42 + slide, 0.62), shoulder = point(0.52 + slide * 0.4, 0.40)
                head(point(0.57 + slide * 0.4, 0.27)); line([shoulder, hip]); line([hip, point(0.60 + slide, 0.73), point(0.76, 0.80)]); let hand = point(0.26 + slide * 1.3, 0.48); line([shoulder, hand]); line([hand, point(0.16, 0.48)], color: accent, width: 2); line([point(0.20, 0.82), point(0.86, 0.82)], color: muted, width: 2); joint(hip)
            case .jump:
                let lift = 0.12 * p, shoulder = point(0.50, 0.36 - lift), hip = point(0.50, 0.61 - lift)
                head(point(0.50, 0.21 - lift)); line([shoulder, hip]); line([shoulder, point(0.28, 0.25 - lift), point(0.20, 0.45 - lift)]); line([shoulder, point(0.72, 0.25 - lift), point(0.80, 0.45 - lift)]); line([hip, point(0.39, 0.75 - lift), point(0.32, 0.91 - lift)]); line([hip, point(0.61, 0.75 - lift), point(0.68, 0.91 - lift)]); joint(hip)
            case .kettlebell:
                let shoulder = point(0.50, 0.36), hip = point(0.50, 0.61), bellY = 0.76 - 0.53 * p
                head(point(0.50, 0.21)); line([shoulder, hip]); line([hip, point(0.38, 0.76), point(0.34, 0.93)]); line([hip, point(0.62, 0.76), point(0.66, 0.93)]); let bell = point(0.50, bellY); line([shoulder, bell]); context.fill(Path(ellipseIn: CGRect(x: bell.x - 7, y: bell.y - 6, width: 14, height: 14)), with: .color(accent)); joint(shoulder)
            case .generic:
                let shoulder = point(0.50, 0.37), hip = point(0.50, 0.64)
                head(point(0.50, 0.22)); line([shoulder, hip]); line([shoulder, point(0.30, 0.60)]); line([shoulder, point(0.70, 0.60)]); line([hip, point(0.39, 0.92)]); line([hip, point(0.61, 0.92)]); joint(shoulder); joint(hip)
            }
        }
    }
}

struct ExerciseProgressView: View {
    @EnvironmentObject private var language: LanguageStore
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false
    @EnvironmentObject private var premium: PremiumAccessStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("trainingWeightUnit_v1") private var trainingWeightUnitRaw = TrainingWeightUnit.kilograms.rawValue
    @AppStorage("trainingDistanceUnit_v1") private var trainingDistanceUnitRaw = TrainingDistanceUnit.kilometers.rawValue
    let exercise: TrainingExercise
    @ObservedObject var store: TrainingStore
    @State private var metric = ProgressMetric.estimatedOneRepMaximum
    @State private var range = TrainingChartRange.threeMonths
    @State private var selectedProgressDate: Date?
    @State private var selectedTab = DetailTab.summary
    @Namespace private var detailTabIndicator
    @State private var recordsExpanded = true
    @State private var cachedProgress: ExerciseProgressSummary
    @State private var chartPoints: [ExerciseChartPoint]
    @State private var showingTrainingPremium = false
    @State private var showingRecordShare = false

    private enum DetailTab: String, CaseIterable {
        case summary, history, howTo
    }

    private struct ExerciseChartPoint: Identifiable {
        let id: String
        let date: Date
        let periodEnd: Date?
        let sampleCount: Int
        let bestWeightKilograms: Double
        let bestRepetitions: Double
        let bestSetVolume: Double
        let estimatedOneRepMaximum: Double
        let distanceMeters: Double
        let durationSeconds: Double
        let paceSecondsPerKilometer: Double?
    }

    private enum ProgressMetric: String, CaseIterable, Identifiable {
        case estimatedOneRepMaximum, weight, repetitions, volume, pace, distance, duration
        var id: String { rawValue }
        var localizationKey: String { "training.progress.metric.\(rawValue)" }
    }

    private var weightUnit: TrainingWeightUnit { TrainingWeightUnit(rawValue: trainingWeightUnitRaw) ?? .kilograms }
    private var distanceUnit: TrainingDistanceUnit { TrainingDistanceUnit(rawValue: trainingDistanceUnitRaw) ?? .kilometers }
    private var availableMetrics: [ProgressMetric] {
        switch exercise.type {
        case .weightReps: [.estimatedOneRepMaximum, .weight, .repetitions, .volume]
        case .bodyweight: progress.bestWeightKilograms > 0 ? [.repetitions, .weight, .volume] : [.repetitions]
        case .repsOnly: [.repetitions]
        case .duration: [.duration]
        case .distanceDuration: [.duration, .distance, .pace]
        }
    }
    private var weightUnitSelection: Binding<TrainingWeightUnit> {
        Binding(
            get: { weightUnit },
            set: { trainingWeightUnitRaw = $0.rawValue }
        )
    }
    private var distanceUnitSelection: Binding<TrainingDistanceUnit> {
        Binding(get: { distanceUnit }, set: { trainingDistanceUnitRaw = $0.rawValue })
    }
    private var rangeSelection: Binding<TrainingChartRange> {
        Binding(
            get: { range },
            set: { value in
                if (value == .oneYear || value == .allTime) && !premium.hasTraining {
                    showingTrainingPremium = true
                } else {
                    range = value
                }
            }
        )
    }
    init(exercise: TrainingExercise, store: TrainingStore) {
        self.exercise = exercise
        self.store = store
        let summary = store.exerciseProgress(exerciseID: exercise.id)
        let initialMetric: ProgressMetric
        switch exercise.type {
        case .weightReps: initialMetric = .weight
        case .bodyweight, .repsOnly: initialMetric = .repetitions
        case .duration, .distanceDuration: initialMetric = .duration
        }
        _metric = State(initialValue: initialMetric)
        _cachedProgress = State(initialValue: summary)
        _chartPoints = State(initialValue: Self.makeChartPoints(from: summary.points, range: .threeMonths))
    }

    private var progress: ExerciseProgressSummary { cachedProgress }
    private var selectedPoint: ExerciseChartPoint? {
        guard let selectedProgressDate else { return nil }
        return chartPoints.min {
            abs($0.date.timeIntervalSince(selectedProgressDate)) < abs($1.date.timeIntervalSince(selectedProgressDate))
        }
    }

    var body: some View {
        ZStack {
            HyseColor.background.ignoresSafeArea()
            VStack(spacing: 0) {
                detailHeader
                summaryIdentity
                detailTabs
                Group {
                    switch selectedTab {
                    case .summary: summaryContent
                    case .history: historyContent
                    case .howTo: howToContent
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: range) { _, _ in
            selectedProgressDate = nil
            chartPoints = Self.makeChartPoints(from: cachedProgress.points, range: range)
        }
        .onChange(of: metric) { _, _ in selectedProgressDate = nil }
        .onReceive(store.$workouts) { _ in refreshProgress() }
        .onReceive(store.$completedWorkouts) { _ in refreshProgress() }
        .sheet(isPresented: $showingTrainingPremium) { PremiumPaywallView(requestedArea: .training) }
        .sheet(isPresented: $showingRecordShare) {
            ExerciseRecordShareComposer(exercise: exercise, progress: progress, store: store)
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(HyseColor.controlSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text("ui.back"))

            Spacer(minLength: 0)
            Text(language.text("training.exercises"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)

            Button { showingRecordShare = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(HyseColor.controlSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(progress.completedSetCount == 0)
            .accessibilityLabel(language.text("training.detail.share.title"))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var detailTabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                detailTab(.summary, title: language.text("training.detail.summary"))
                detailTab(.history, title: language.text("training.detail.history"))
                detailTab(.howTo, title: language.text("training.detail.how_to"))
            }
            Rectangle()
                .fill(HyseColor.border)
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func detailTab(_ tab: DetailTab, title: String) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab } } label: {
            Text(title)
                .font(.system(size: 15, weight: tab == selectedTab ? .semibold : .medium))
                .foregroundStyle(tab == selectedTab ? Color.primary : Color.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    if tab == selectedTab {
                        Capsule()
                            .fill(HyseColor.accent)
                            .frame(width: 36, height: 3)
                            .matchedGeometryEffect(id: "exercise-detail-tab", in: detailTabIndicator)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == selectedTab ? .isSelected : [])
    }

    private var summaryContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                summaryChart
                recordsSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private var summaryIdentity: some View {
        HStack(alignment: .center, spacing: 12) {
            ExerciseMovementVisual(exercise: exercise, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.displayName(isGerman: language.isGerman))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(language.text(exercise.equipment.localizationKey))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HyseColor.accent)
                if !exercise.primaryMuscles.isEmpty {
                    Text(muscles(exercise.primaryMuscles))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var summaryChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(detailMetricTitle(metric))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(selectedPoint.map(pointSummary) ?? detailLatestValue)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    if let selectedPoint {
                        Text(periodLabel(selectedPoint))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let date = progress.points.last?.date {
                        Text(date.formatted(.dateTime.month(.abbreviated).day().locale(language.locale)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Menu {
                    ForEach(TrainingChartRange.allCases) { item in
                        Button(language.text(item.localizationKey)) { rangeSelection.wrappedValue = item }
                    }
                } label: {
                    Label(detailRangeTitle, systemImage: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HyseColor.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(HyseColor.accent.opacity(0.10), in: Capsule())
                }
            }

            if chartPoints.isEmpty {
                Text(language.text("training.progress.empty.message"))
                    .font(.subheadline)
                    .foregroundStyle(Color.primary.opacity(0.58))
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .center)
            } else {
                detailChart
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(availableMetrics) { item in
                        Button { metric = item } label: {
                            Text(detailMetricTitle(item))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(metric == item ? .white : Color.primary.opacity(0.78))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(metric == item ? HyseColor.accent : Color.primary.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(16)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous).stroke(HyseColor.border))
    }

    private var detailChart: some View {
        Chart {
            ForEach(chartPoints) { point in
                LineMark(x: .value(language.text("training.progress.date"), point.date), y: .value(language.text(metric.localizationKey), value(point)))
                    .foregroundStyle(HyseColor.accent)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
                PointMark(x: .value(language.text("training.progress.date"), point.date), y: .value(language.text(metric.localizationKey), value(point)))
                    .foregroundStyle(HyseColor.accent)
                    .symbolSize(52)
            }
            if let selectedPoint {
                RuleMark(x: .value(language.text("training.progress.date"), selectedPoint.date))
                    .foregroundStyle(HyseColor.accent.opacity(0.55))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        chartSelectionLabel(value: pointSummary(selectedPoint), point: selectedPoint)
                    }
                PointMark(x: .value(language.text("training.progress.date"), selectedPoint.date), y: .value(language.text(metric.localizationKey), value(selectedPoint)))
                    .foregroundStyle(.primary)
                    .symbolSize(75)
            }
        }
        .modifier(ExerciseWeightChartScale(domain: weightChartDomain))
        .frame(height: 170)
        .chartPlotStyle { plot in plot.background(HyseColor.surface) }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.12))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.month(.abbreviated).day().locale(language.locale)))
                            .foregroundStyle(Color.primary.opacity(0.55))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.12))
                AxisValueLabel {
                    if let numeric = value.as(Double.self) {
                        Text(chartAxisLabel(numeric))
                            .foregroundStyle(Color.primary.opacity(0.55))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                selectChartPoint(at: gesture.location, proxy: proxy, geometry: geometry)
                            }
                    )
            }
        }
        .accessibilityLabel(language.text("training.progress.chart_accessibility", [exercise.displayName(isGerman: language.isGerman)]))
    }

    private func selectChartPoint(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let relativeX = location.x - frame.minX
        guard relativeX >= 0, relativeX <= frame.width,
              let date = proxy.value(atX: relativeX, as: Date.self),
              let point = chartPoints.min(by: {
                  abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
              }) else { return }
        selectedProgressDate = point.date
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(language.text("training.detail.personal_records"), systemImage: "medal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HyseColor.accent)
            }
            .padding(.bottom, 6)
            ForEach(detailRecords, id: \.title) { record in
                recordRow(title: record.title, value: record.value)
            }
            if !repRecords.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { recordsExpanded.toggle() }
                } label: {
                    HStack {
                        Text(language.text("training.detail.set_records"))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: recordsExpanded ? "chevron.up" : "chevron.down")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                }
                .buttonStyle(.plain)
            }
            if recordsExpanded && !repRecords.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text(language.text("training.detail.repetitions"))
                        Spacer()
                        Text(language.text("training.detail.best_performance"))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                    ForEach(repRecords, id: \.repetitions) { record in
                        HStack {
                            Text("\(record.repetitions)")
                            Spacer()
                            Text(weight(record.weightKilograms)).foregroundStyle(.primary)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 9)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.13)).frame(height: 1) }
                    }
                }
            }
        }
        .padding(16)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous).stroke(HyseColor.border))
    }

    private func recordRow(title: String, value: String) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(HyseColor.accent)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.13)).frame(height: 1) }
    }

    private var historyContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 10) {
                if historyEntries.isEmpty {
                    Text(language.text("training.progress.empty.message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 130)
                } else {
                    ForEach(historyEntries) { entry in
                        historyEntry(entry)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func historyEntry(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.workout.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.date.formatted(.dateTime.day().month(.abbreviated).year().locale(language.locale)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(HyseColor.accent)
            }
            Divider()
            ForEach(Array(entry.exercise.sets.filter(\.completed).enumerated()), id: \.element.id) { index, set in
                HStack {
                    Text("\(index + 1)")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .leading)
                    Spacer()
                    Text(setSummary(set))
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous).stroke(HyseColor.border))
    }

    private var howToContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(howToSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(HyseColor.accent)
                                .frame(width: 26, height: 26)
                                .background(HyseColor.accent.opacity(0.12), in: Circle())
                            Text(step)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 3)
                        }
                        .padding(.vertical, 10)
                        if index < howToSteps.count - 1 { Divider().padding(.leading, 38) }
                    }
                }
                .foregroundStyle(.primary)
                .padding(16)
                .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous).stroke(HyseColor.border))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private struct HistoryEntry: Identifiable {
        let id: UUID
        let workout: WorkoutLog
        let exercise: WorkoutExerciseLog
        let date: Date
    }

    private struct DetailRecord {
        let title: String
        let value: String
    }

    private struct RepRecord {
        let repetitions: Int
        let weightKilograms: Double
    }

    private var detailLatestValue: String {
        guard let point = progress.points.last else { return "–" }
        switch metric {
        case .estimatedOneRepMaximum: return weight(point.estimatedOneRepMaximum)
        case .weight: return weight(point.bestWeightKilograms)
        case .repetitions: return "\(point.bestRepetitions) \(language.text("training.detail.repetitions"))"
        case .volume: return weight(point.bestSetVolume)
        case .pace: return pace(point.paceSecondsPerKilometer)
        case .distance: return distance(point.distanceMeters)
        case .duration: return formattedDuration(point.durationSeconds)
        }
    }

    private var detailRangeTitle: String {
        switch range {
        case .oneMonth: return language.text("training.detail.range_one_month")
        case .threeMonths: return language.text("training.detail.range_three_months")
        case .oneYear: return language.text("training.detail.range_one_year")
        case .allTime: return language.text("training.detail.range_all_time")
        }
    }

    private func muscles(_ values: [String]) -> String {
        values.map { language.text("training.muscle.\($0)") }.joined(separator: ", ")
    }

    private func detailMetricTitle(_ value: ProgressMetric) -> String {
        switch value {
        case .estimatedOneRepMaximum: return language.text("training.detail.metric_one_rep_max")
        case .weight: return language.text("training.detail.metric_heaviest_weight")
        case .repetitions: return language.text("training.detail.metric_repetitions")
        case .volume: return language.text("training.detail.metric_set_volume")
        case .pace: return language.text("training.progress.metric.pace")
        case .distance: return language.text("training.progress.metric.distance")
        case .duration: return language.text("training.progress.metric.duration")
        }
    }

    private var detailRecords: [DetailRecord] {
        switch exercise.type {
        case .distanceDuration:
            return [
                DetailRecord(title: language.text("training.progress.best_pace"), value: pace(progress.bestPaceSecondsPerKilometer)),
                DetailRecord(title: language.text("training.progress.total_distance"), value: distance(progress.totalDistanceMeters)),
                DetailRecord(title: language.text("training.progress.total_duration"), value: formattedDuration(progress.totalDurationSeconds)),
                DetailRecord(title: language.text("training.progress.workouts"), value: "\(progress.workoutCount)")
            ]
        case .duration:
            return [
                DetailRecord(title: language.text("training.detail.share.longest_set"), value: formattedDuration(bestSetDuration)),
                DetailRecord(title: language.text("training.progress.total_duration"), value: formattedDuration(progress.totalDurationSeconds)),
                DetailRecord(title: language.text("training.progress.workouts"), value: "\(progress.workoutCount)"),
                DetailRecord(title: language.text("training.completed_sets"), value: adjustedSetCount)
            ]
        case .bodyweight, .repsOnly:
            return [
                DetailRecord(title: language.text("training.progress.best_reps"), value: "\(progress.bestRepetitions)"),
                DetailRecord(title: language.text("training.progress.workouts"), value: "\(progress.workoutCount)"),
                DetailRecord(title: language.text("training.completed_sets"), value: adjustedSetCount)
            ]
        case .weightReps:
            return [
                DetailRecord(title: language.text("training.detail.record_heaviest_weight"), value: weight(progress.bestWeightKilograms)),
                DetailRecord(title: language.text("training.detail.record_one_rep_max"), value: weight(progress.estimatedOneRepMaximum)),
                DetailRecord(title: language.text("training.detail.record_set_volume"), value: weight(progress.bestSetVolume)),
                DetailRecord(title: language.text("training.detail.record_session_volume"), value: weight(bestSessionVolume))
            ]
        }
    }

    private var adjustedSetCount: String {
        let count = store.completedWorkouts.flatMap(\.exercises)
            .filter { $0.exerciseID == exercise.id }
            .reduce(0.0) { $0 + TrainingSetStatistics.count($1, halveUnilateral: halveUnilateral) }
        return TrainingSetStatistics.formatted(count, locale: language.locale)
    }

    private var bestSetDuration: Double {
        store.completedWorkouts
            .flatMap(\.exercises)
            .filter { $0.exerciseID == exercise.id }
            .flatMap(\.sets)
            .filter(\.completed)
            .map(\.durationSeconds)
            .max() ?? 0
    }

    private var bestSessionVolume: Double {
        store.completedWorkouts.compactMap { workout in
            let sets = workout.exercises
                .filter { $0.exerciseID == exercise.id }
                .flatMap(\.sets)
                .filter(\.completed)
            guard !sets.isEmpty else { return nil }
            return sets.reduce(0) { $0 + $1.volume }
        }.max() ?? 0
    }

    private var repRecords: [RepRecord] {
        let grouped = store.completedWorkouts
            .flatMap(\.exercises)
            .filter { $0.exerciseID == exercise.id }
            .flatMap(\.sets)
            .filter { $0.completed && $0.reps > 0 && $0.weightKilograms > 0 }
            .reduce(into: [Int: Double]()) { result, set in
                result[set.reps] = max(result[set.reps, default: 0], set.weightKilograms)
            }
        return grouped.keys.sorted().map { RepRecord(repetitions: $0, weightKilograms: grouped[$0] ?? 0) }
    }

    private var historyEntries: [HistoryEntry] {
        store.completedWorkouts
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
            .compactMap { workout in
                guard let loggedExercise = workout.exercises.first(where: { $0.exerciseID == exercise.id }),
                      loggedExercise.sets.contains(where: \.completed) else { return nil }
                return HistoryEntry(
                    id: workout.id,
                    workout: workout,
                    exercise: loggedExercise,
                    date: workout.completedAt ?? workout.startedAt
                )
            }
    }

    private var howToSteps: [String] {
        let guideSentences = exercise.executionGuide(isGerman: language.isGerman)
            .split(whereSeparator: { $0 == "." })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) + "." }
        var steps = guideSentences
        steps.append(language.text(exercise.visualKind.techniqueKey))
        steps.append(language.text("training.detail.step.return_controlled"))
        return Array(steps.prefix(6))
    }

    private func setSummary(_ set: TrainingSetLog) -> String {
        switch exercise.type {
        case .weightReps:
            return "\(weight(set.weightKilograms)) × \(set.reps)"
        case .bodyweight, .repsOnly:
            return "\(set.reps) \(language.text("training.detail.repetitions"))"
        case .duration:
            return formattedDuration(set.durationSeconds)
        case .distanceDuration:
            return "\(distance(set.distanceMeters)) × \(formattedDuration(set.durationSeconds))"
        }
    }

    private func metricCard(_ key: String, value: String, icon: String) -> some View {
        HyseCard {
            VStack(spacing: 5) {
                Image(systemName: icon).foregroundStyle(HyseColor.accent)
                Text(value).font(.title3.bold()).monospacedDigit()
                Text(language.text(key)).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity)
        }
    }

    private func value(_ point: ExerciseChartPoint) -> Double {
        switch metric {
        case .estimatedOneRepMaximum: weightUnit.display(point.estimatedOneRepMaximum)
        case .weight: weightUnit.display(point.bestWeightKilograms)
        case .repetitions: point.bestRepetitions
        case .volume: weightUnit.display(point.bestSetVolume)
        case .pace: displayedPaceSeconds(point.paceSecondsPerKilometer) ?? 0
        case .distance: distanceUnit.display(point.distanceMeters)
        case .duration: point.durationSeconds / 60
        }
    }

    /// Strength metrics should emphasize actual progress instead of spending
    /// most of the chart on an unused range down to zero. The padding is based
    /// on the visible, already aggregated points and therefore follows the
    /// selected time range and kg/lb unit automatically.
    private var weightChartDomain: ClosedRange<Double>? {
        switch metric {
        case .estimatedOneRepMaximum, .weight, .volume:
            let values = chartPoints.map(value).filter { $0.isFinite && $0 > 0 }
            guard let minimum = values.min(), let maximum = values.max() else { return nil }
            let lower = minimum * 0.9
            let upper = maximum * 1.1
            guard upper > lower else {
                let padding = max(abs(maximum) * 0.1, 1)
                return (minimum - padding)...(maximum + padding)
            }
            return lower...upper
        case .repetitions, .pace, .distance, .duration:
            return nil
        }
    }

    private func weight(_ kilograms: Double) -> String {
        "\(weightUnit.display(kilograms).formatted(.number.precision(.fractionLength(0...1)))) \(weightUnit.rawValue)"
    }

    private func pointSummary(_ point: ExerciseChartPoint) -> String {
        switch metric {
        case .estimatedOneRepMaximum: return weight(point.estimatedOneRepMaximum)
        case .weight: return weight(point.bestWeightKilograms)
        case .repetitions: return point.bestRepetitions.formatted(.number.precision(.fractionLength(point.sampleCount > 1 ? 1 : 0)))
        case .volume: return weight(point.bestSetVolume)
        case .pace: return pace(point.paceSecondsPerKilometer)
        case .distance: return distance(point.distanceMeters)
        case .duration: return formattedDuration(point.durationSeconds)
        }
    }

    private func historyPointSummary(_ point: ExerciseProgressPoint) -> String {
        switch metric {
        case .estimatedOneRepMaximum: return weight(point.estimatedOneRepMaximum)
        case .weight: return weight(point.bestWeightKilograms)
        case .repetitions: return "\(point.bestRepetitions)"
        case .volume: return weight(point.bestSetVolume)
        case .pace: return pace(point.paceSecondsPerKilometer)
        case .distance: return distance(point.distanceMeters)
        case .duration: return formattedDuration(point.durationSeconds)
        }
    }

    private func displayedPaceSeconds(_ secondsPerKilometer: Double?) -> Double? {
        secondsPerKilometer.map { distanceUnit == .kilometers ? $0 : $0 * 1.609_344 }
    }

    private func pace(_ secondsPerKilometer: Double?) -> String {
        guard let seconds = displayedPaceSeconds(secondsPerKilometer), seconds.isFinite, seconds > 0 else { return "–" }
        return "\(paceLabel(displayedSeconds: seconds)) /\(distanceUnit.rawValue)"
    }

    private func paceLabel(displayedSeconds: Double) -> String {
        let rounded = max(0, Int(displayedSeconds.rounded()))
        return "\(rounded / 60):\(String(format: "%02d", rounded % 60))"
    }

    private func chartAxisLabel(_ value: Double) -> String {
        switch metric {
        case .pace: paceLabel(displayedSeconds: value)
        case .duration: formattedDuration(value * 60)
        default: value.formatted(.number.precision(.fractionLength(0...1)))
        }
    }

    private func distance(_ meters: Double) -> String {
        "\(distanceUnit.display(meters).formatted(.number.precision(.fractionLength(0...2)))) \(distanceUnit.rawValue)"
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainingSeconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            : String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func chartSelectionLabel(value: String, point: ExerciseChartPoint) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.weight(.bold)).monospacedDigit()
            Text(periodLabel(point)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(HyseColor.border))
    }

    private func periodLabel(_ point: ExerciseChartPoint) -> String {
        guard let end = point.periodEnd else {
            return point.date.formatted(.dateTime.day().month().year().locale(language.locale))
        }
        let startText = point.date.formatted(.dateTime.day().month(.abbreviated).locale(language.locale))
        let endText = end.formatted(.dateTime.day().month(.abbreviated).year().locale(language.locale))
        return "\(startText) – \(endText)"
    }

    private func refreshProgress() {
        let summary = store.exerciseProgress(exerciseID: exercise.id)
        cachedProgress = summary
        chartPoints = Self.makeChartPoints(from: summary.points, range: range)
        selectedProgressDate = nil
    }

    private static func makeChartPoints(from points: [ExerciseProgressPoint], range: TrainingChartRange, calendar: Calendar = .autoupdatingCurrent) -> [ExerciseChartPoint] {
        let filtered = points.filter { range.includes($0.date) }
        guard range != .oneMonth && range != .threeMonths else {
            return filtered.sorted { $0.date < $1.date }.map {
                ExerciseChartPoint(
                    id: $0.id.uuidString,
                    date: $0.date,
                    periodEnd: nil,
                    sampleCount: 1,
                    bestWeightKilograms: $0.bestWeightKilograms,
                    bestRepetitions: Double($0.bestRepetitions),
                    bestSetVolume: $0.bestSetVolume,
                    estimatedOneRepMaximum: $0.estimatedOneRepMaximum,
                    distanceMeters: $0.distanceMeters,
                    durationSeconds: $0.durationSeconds,
                    paceSecondsPerKilometer: $0.paceSecondsPerKilometer
                )
            }
        }

        let component: Calendar.Component = range == .allTime ? .month : .weekOfYear
        let grouped = Dictionary(grouping: filtered) { point in
            calendar.dateInterval(of: component, for: point.date)?.start ?? calendar.startOfDay(for: point.date)
        }
        return grouped.keys.sorted().compactMap { start in
            guard let values = grouped[start], !values.isEmpty else { return nil }
            let interval = calendar.dateInterval(of: component, for: start)
            let end = interval?.end.addingTimeInterval(-1)
            let count = Double(values.count)
            return ExerciseChartPoint(
                id: "\(component)-\(start.timeIntervalSinceReferenceDate)",
                date: start,
                periodEnd: end,
                sampleCount: values.count,
                bestWeightKilograms: values.reduce(0) { $0 + $1.bestWeightKilograms } / count,
                bestRepetitions: values.reduce(0) { $0 + Double($1.bestRepetitions) } / count,
                bestSetVolume: values.reduce(0) { $0 + $1.bestSetVolume } / count,
                estimatedOneRepMaximum: values.reduce(0) { $0 + $1.estimatedOneRepMaximum } / count,
                distanceMeters: values.reduce(0) { $0 + $1.distanceMeters } / count,
                durationSeconds: values.reduce(0) { $0 + $1.durationSeconds } / count,
                paceSecondsPerKilometer: {
                    let paces = values.compactMap(\.paceSecondsPerKilometer)
                    return paces.isEmpty ? nil : paces.reduce(0, +) / Double(paces.count)
                }()
            )
        }
    }

    private func rangeSymbol(_ range: TrainingChartRange) -> String {
        switch range {
        case .oneMonth: "calendar"
        case .threeMonths: "calendar.badge.clock"
        case .oneYear: "calendar.circle"
        case .allTime: "infinity"
        }
    }
}

private struct ExerciseWeightChartScale: ViewModifier {
    let domain: ClosedRange<Double>?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let domain {
            content.chartYScale(domain: domain)
        } else {
            content
        }
    }
}

struct TrainingCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var store: TrainingStore
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()

    private var calendar: Calendar {
        var value = Calendar.autoupdatingCurrent
        value.locale = language.locale
        return value
    }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year().locale(language.locale))
    }

    private var monthDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let leading = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let dates = dayRange.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }
        return Array(repeating: nil, count: leading) + dates.map(Optional.some)
    }

    private var monthWorkouts: [Date: [WorkoutLog]] {
        Dictionary(grouping: store.completedWorkouts) { workout in
            calendar.startOfDay(for: workout.completedAt ?? workout.startedAt)
        }
    }

    private var trainedDaysThisMonth: Int {
        let days = Set(monthWorkouts.keys.filter { calendar.isDate($0, equalTo: displayedMonth, toGranularity: .month) })
        return days.count
    }

    private var restDaysThisMonth: Int {
        let dayCount = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 0
        return max(0, dayCount - trainedDaysThisMonth)
    }

    var body: some View {
        ZStack {
            HyseBackdrop()
            ScrollView {
                VStack(spacing: 0) {
                    calendarHeader
                    HStack(spacing: 0) {
                        calendarSummary(icon: "flame.fill", value: "\(store.statistics.currentStreak)", title: language.isGerman ? "Wochen-Serie" : "week streak", color: .orange)
                        calendarSummary(icon: "moon.fill", value: "\(restDaysThisMonth)", title: language.isGerman ? "Ruhetage" : "rest days", color: .blue)
                    }
                    .frame(maxWidth: .infinity)
                    .background(HyseColor.surface)

                    weekdayHeader
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                        ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                            if let date {
                                calendarDayCell(date)
                            } else {
                                Color.clear.frame(minHeight: 74)
                            }
                        }
                    }
                    .padding(.horizontal, HyseSpacing.small)

                    if !selectedDayWorkouts.isEmpty {
                        selectedDaySection
                    }
                }
                .padding(.bottom, 36)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var calendarHeader: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(HyseColor.controlSurface, in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button(language.isGerman ? "Vorheriger Monat" : "Previous month") { shiftMonth(by: -1) }
                Button(language.isGerman ? "Aktueller Monat" : "Current month") { displayedMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date() }
                Button(language.isGerman ? "Nächster Monat" : "Next month") { shiftMonth(by: 1) }
            } label: {
                HStack(spacing: HyseSpacing.small) {
                    Text(monthTitle).font(.title2.weight(.medium))
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                }
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: HyseSpacing.medium) {
                Image(systemName: "square.and.arrow.up")
                Image(systemName: "slider.horizontal.3")
            }
            .font(.title3.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, HyseSpacing.large)
            .frame(height: 44)
            .background(HyseColor.controlSurface, in: Capsule())
        }
        .padding(.horizontal, HyseSpacing.page)
        .padding(.top, HyseSpacing.large)
        .padding(.bottom, HyseSpacing.medium)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                Text(weekdayName(offset))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, HyseSpacing.medium)
        .background(HyseColor.surface)
    }

    private func weekdayName(_ offset: Int) -> String {
        let symbols = calendar.veryShortWeekdaySymbols
        let index = (calendar.firstWeekday - 1 + offset) % symbols.count
        return symbols[index]
    }

    private func calendarSummary(icon: String, value: String, title: String, color: Color) -> some View {
        HStack(spacing: HyseSpacing.small) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.headline)
            Text(title).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HyseSpacing.medium)
    }

    @ViewBuilder
    private func calendarDayCell(_ date: Date) -> some View {
        let dayWorkouts = monthWorkouts[calendar.startOfDay(for: date)] ?? []
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        Button { selectedDate = date } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.body.weight(dayWorkouts.isEmpty ? .regular : .medium))
                    .foregroundStyle(dayWorkouts.isEmpty ? Color.primary : Color.white)
                    .frame(width: 34, height: 34)
                    .background(dayWorkouts.isEmpty ? Color.clear : Color(uiColor: .systemBlue), in: Circle())
                    .overlay { if isToday && dayWorkouts.isEmpty { Circle().stroke(Color(uiColor: .systemBlue), lineWidth: 1.5) } }
                    .frame(maxWidth: .infinity, alignment: .center)

                if let workout = dayWorkouts.first {
                    Text(workout.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let location = workoutLocation(workout) {
                        Text(location)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if dayWorkouts.count > 1 {
                        Text("+\(dayWorkouts.count - 1)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(HyseColor.accent)
                    }
                }
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .top)
            .overlay(alignment: .bottom) { Divider().opacity(0.65) }
            .background(isSelected ? HyseColor.surface : .clear)
        }
        .buttonStyle(.plain)
    }

    private var selectedDayWorkouts: [WorkoutLog] {
        monthWorkouts[calendar.startOfDay(for: selectedDate)] ?? []
    }

    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(language.locale)))
                .font(.headline)
            ForEach(selectedDayWorkouts) { workout in
                NavigationLink { WorkoutSummaryView(workout: workout, store: store) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workout.name).font(.body.weight(.semibold))
                        if let location = workoutLocation(workout) {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(HyseSpacing.medium)
                    .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, HyseSpacing.page)
        .padding(.top, HyseSpacing.large)
    }

    private func shiftMonth(by offset: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) ?? displayedMonth
    }

    private func workoutLocation(_ workout: WorkoutLog) -> String? {
        let parts = [workout.gymName, workout.gymAddress]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct TrainingStatisticsDetails: View {
    @EnvironmentObject private var language: LanguageStore
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false
    @AppStorage("trainingWeightUnit_v1") private var trainingWeightUnitRaw = TrainingWeightUnit.kilograms.rawValue
    @ObservedObject var store: TrainingStore
    @Binding var exerciseSearchQuery: String

    private var weightUnit: TrainingWeightUnit { TrainingWeightUnit(rawValue: trainingWeightUnitRaw) ?? .kilograms }
    private var maximumSets: Double { max(1, store.muscleDistribution.map(\.completedSets).max() ?? 1) }
    private var trainedExercises: [TrainingExercise] {
        let trained = store.exercises.filter { store.exerciseProgress(exerciseID: $0.id).completedSetCount > 0 }
        let query = exerciseSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return trained }
        return trained.filter { exercise in
            exercise.displayName(isGerman: language.isGerman).localizedStandardContains(query)
                || exercise.englishName.localizedStandardContains(query)
                || exercise.germanName.localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.xLarge) {
            if !store.muscleDistribution.isEmpty {
                VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                    HyseSectionHeading(title: language.text("training.statistics.muscle_distribution"), icon: "figure.arms.open")
                    HyseCard {
                        VStack(spacing: HyseSpacing.medium) {
                            ForEach(Array(store.muscleDistribution.prefix(8).enumerated()), id: \.element.id) { index, item in
                                VStack(alignment: .leading, spacing: HyseSpacing.small) {
                                    HStack {
                                        Text(language.text("training.muscle.\(item.muscle)"))
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(language.text("training.statistics.set_count", [TrainingSetStatistics.formatted(item.completedSets, locale: language.locale)]))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    HyseProgressBar(value: item.completedSets, total: maximumSets, colors: [HyseColor.accent])
                                }
                                if index < min(store.muscleDistribution.count, 8) - 1 { Divider() }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                HyseSectionHeading(
                    title: language.text("training.statistics.exercise_progress"),
                    subtitle: language.text("training.statistics.exercise_progress_subtitle"),
                    icon: "dumbbell.fill"
                )
                HyseSearchField(placeholder: language.text("training.statistics.exercise_search"), text: $exerciseSearchQuery)
                if trainedExercises.isEmpty {
                    HyseCard {
                        HyseEmptyState(
                            icon: "chart.xyaxis.line",
                            title: language.text(exerciseSearchQuery.isEmpty ? "training.statistics.no_data" : "training.statistics.exercise_search_empty"),
                            message: language.text("training.progress.empty.message")
                        )
                    }
                } else {
                    LazyVStack(spacing: HyseSpacing.medium) {
                        ForEach(trainedExercises) { exercise in
                            NavigationLink { ExerciseProgressView(exercise: exercise, store: store) } label: {
                                let progress = store.exerciseProgress(exerciseID: exercise.id)
                                HStack(spacing: HyseSpacing.medium) {
                                    ExerciseMovementVisual(exercise: exercise, height: 36)
                                        .frame(width: 42, height: 42)
                                        .background(HyseColor.accent.opacity(0.10), in: Circle())
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(exercise.displayName(isGerman: language.isGerman))
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .layoutPriority(1)
                                        Text(exerciseSummary(exercise, progress: progress))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(HyseColor.accent)
                                }
                                .padding(HyseSpacing.large)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .hyseGlassSurface(radius: HyseRadius.card)
                        }
                    }
                }
            }
        }
    }

    private func weight(_ kilograms: Double) -> String {
        "\(weightUnit.display(kilograms).formatted(.number.precision(.fractionLength(0...1)))) \(weightUnit.rawValue)"
    }

    private func exerciseSummary(_ exercise: TrainingExercise, progress: ExerciseProgressSummary) -> String {
        let sets = TrainingSetStatistics.formatted(
            store.completedWorkouts.flatMap(\.exercises)
                .filter { $0.exerciseID == exercise.id }
                .reduce(0.0) { $0 + TrainingSetStatistics.count($1, halveUnilateral: halveUnilateral) },
            locale: language.locale
        )
        return switch exercise.type {
        case .weightReps:
            language.text("training.statistics.exercise_summary", [progress.workoutCount, sets, weight(progress.estimatedOneRepMaximum)])
        case .bodyweight, .repsOnly:
            language.text("training.statistics.exercise_summary_repetitions", [progress.workoutCount, sets, progress.bestRepetitions])
        case .duration, .distanceDuration:
            language.text("training.statistics.exercise_summary_duration", [progress.workoutCount, sets, duration(progress.totalDurationSeconds)])
        }
    }

    private func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return total >= 3_600
            ? String(format: "%d:%02d:%02d", total / 3_600, total % 3_600 / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
