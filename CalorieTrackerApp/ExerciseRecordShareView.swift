import SwiftUI
import UIKit

struct ExerciseRecordShareComposer: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @AppStorage("trainingWeightUnit_v1") private var weightUnitRaw = TrainingWeightUnit.kilograms.rawValue
    @AppStorage("trainingDistanceUnit_v1") private var distanceUnitRaw = TrainingDistanceUnit.kilometers.rawValue
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false

    let exercise: TrainingExercise
    let progress: ExerciseProgressSummary
    @ObservedObject var store: TrainingStore

    @State private var background = WorkoutShareBackground.dark
    @State private var imageData: Data?
    @State private var showingShareSheet = false
    @State private var didCopyText = false

    private var weightUnit: TrainingWeightUnit { TrainingWeightUnit(rawValue: weightUnitRaw) ?? .kilograms }
    private var distanceUnit: TrainingDistanceUnit { TrainingDistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers }
    private var exerciseName: String { exercise.displayName(isGerman: language.isGerman) }

    var body: some View {
        NavigationStack {
            ZStack {
                HyseBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: HyseSpacing.large) {
                        ZStack {
                            WorkoutTransparencyGrid()
                            if let imageData, let image = UIImage(data: imageData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                ProgressView().controlSize(.large)
                            }
                        }
                        .aspectRatio(4.0 / 5.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(HyseColor.border, lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.24), radius: 18, y: 10)

                        VStack(alignment: .leading, spacing: HyseSpacing.small) {
                            Text(language.text("training.share.background"))
                                .font(.headline)
                            Picker(language.text("training.share.background"), selection: $background) {
                                ForEach(WorkoutShareBackground.allCases) { option in
                                    Text(language.text(option.localizationKey)).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Text(shareCaption)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(HyseSpacing.medium)
                            .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))

                        HStack(spacing: HyseSpacing.medium) {
                            Button { showingShareSheet = true } label: {
                                Label(language.text("training.detail.share.share_image"), systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                            }
                            .buttonStyle(HysePrimaryButtonStyle())
                            .disabled(imageData == nil)

                            Button {
                                UIPasteboard.general.string = shareCaption
                                didCopyText = true
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                Task {
                                    try? await Task.sleep(for: .seconds(1.5))
                                    didCopyText = false
                                }
                            } label: {
                                Label(language.text(didCopyText ? "training.share.text_copied" : "training.share.copy_text"), systemImage: didCopyText ? "checkmark" : "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                            }
                            .buttonStyle(HyseSecondaryButtonStyle())
                        }
                    }
                    .padding(.horizontal, HyseSpacing.page)
                    .padding(.vertical, HyseSpacing.large)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(language.text("training.detail.share.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("app_tabs.cancel")) { dismiss() }
                }
            }
        }
        .task(id: renderID) {
            await Task.yield()
            renderImage()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let imageData {
                WorkoutShareSheet(imageData: imageData, message: shareCaption)
            }
        }
    }

    private var renderID: String {
        [background.rawValue, language.locale.identifier, weightUnit.rawValue, distanceUnit.rawValue].joined(separator: "|")
    }

    private var shareCaption: String {
        [
            language.text("training.detail.share.caption", [exerciseName, heroTitle, heroDetail.map { "\(heroValue) · \($0)" } ?? heroValue]),
            language.text("training.share.app_store_caption")
        ].joined(separator: "\n")
    }

    private var heroTitle: String {
        switch exercise.type {
        case .weightReps: language.text("training.detail.record_heaviest_weight")
        case .bodyweight, .repsOnly: language.text("training.detail.metric_repetitions")
        case .duration: language.text("training.detail.share.longest_set")
        case .distanceDuration:
            language.text(progress.bestPaceSecondsPerKilometer == nil ? "training.progress.metric.distance" : "training.progress.best_pace")
        }
    }

    private var heroValue: String {
        switch exercise.type {
        case .weightReps: return weight(progress.bestWeightKilograms)
        case .bodyweight, .repsOnly: return progress.bestRepetitions.formatted(.number.locale(language.locale))
        case .duration: return duration(bestSetDuration)
        case .distanceDuration:
            if let pace = progress.bestPaceSecondsPerKilometer { return paceText(pace) }
            return distance(progress.points.map(\.distanceMeters).max() ?? 0)
        }
    }

    private var heroDetail: String? {
        guard exercise.type == .weightReps, let repetitions = heaviestSetRepetitions else { return nil }
        return language.text("training.detail.share.weight_repetitions", [repetitions])
    }

    private var heaviestSetRepetitions: Int? {
        guard progress.bestWeightKilograms > 0 else { return nil }
        return store.completedWorkouts
            .flatMap(\.exercises)
            .filter { $0.exerciseID == exercise.id }
            .flatMap(\.sets)
            .filter { $0.completed && $0.weightKilograms == progress.bestWeightKilograms && $0.reps > 0 }
            .map(\.reps)
            .max()
    }

    private var supportingMetrics: [(title: String, value: String)] {
        switch exercise.type {
        case .weightReps:
            return [
                (language.text("training.detail.record_one_rep_max"), weight(progress.estimatedOneRepMaximum))
            ]
        case .bodyweight, .repsOnly:
            return [
                (language.text("training.progress.workouts"), "\(progress.workoutCount)"),
                (language.text("training.completed_sets"), TrainingSetStatistics.formatted(
                    store.completedWorkouts.flatMap(\.exercises)
                        .filter { $0.exerciseID == exercise.id }
                        .reduce(0.0) { $0 + TrainingSetStatistics.count($1, halveUnilateral: halveUnilateral) },
                    locale: language.locale
                ))
            ]
        case .duration:
            return [
                (language.text("training.progress.total_duration"), duration(progress.totalDurationSeconds)),
                (language.text("training.progress.workouts"), "\(progress.workoutCount)")
            ]
        case .distanceDuration:
            return [
                (language.text("training.progress.total_distance"), distance(progress.totalDistanceMeters)),
                (language.text("training.progress.workouts"), "\(progress.workoutCount)")
            ]
        }
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

    private func weight(_ kilograms: Double) -> String {
        "\(weightUnit.display(kilograms).formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))) \(weightUnit.rawValue)"
    }

    private func distance(_ meters: Double) -> String {
        "\(distanceUnit.display(meters).formatted(.number.precision(.fractionLength(0...2)).locale(language.locale))) \(distanceUnit.rawValue)"
    }

    private func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return total >= 3_600
            ? String(format: "%d:%02d:%02d", total / 3_600, total % 3_600 / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    private func paceText(_ secondsPerKilometer: Double) -> String {
        let seconds = max(0, Int((secondsPerKilometer * (distanceUnit == .miles ? 1.609_344 : 1)).rounded()))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60)) /\(distanceUnit.rawValue)"
    }

    private func renderImage() {
        imageData = nil
        let card = ExerciseRecordShareCard(
            exerciseName: exerciseName,
            equipment: language.text(exercise.equipment.localizationKey),
            eyebrow: language.text("training.detail.share.card_eyebrow"),
            heroTitle: heroTitle,
            heroValue: heroValue,
            heroDetail: heroDetail,
            metrics: supportingMetrics,
            callToAction: language.text("training.detail.share.card_cta"),
            background: background
        )
        .frame(width: 540, height: 675)
        .environment(\.locale, language.locale)
        .environment(\.colorScheme, background == .light ? .light : .dark)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        renderer.isOpaque = background != .transparent
        imageData = renderer.uiImage?.pngData()
    }
}

private struct ExerciseRecordShareCard: View {
    let exerciseName: String
    let equipment: String
    let eyebrow: String
    let heroTitle: String
    let heroValue: String
    let heroDetail: String?
    let metrics: [(title: String, value: String)]
    let callToAction: String
    let background: WorkoutShareBackground

    private var foreground: Color { background == .light ? Color(red: 0.04, green: 0.055, blue: 0.08) : .white }
    private var secondary: Color { foreground.opacity(0.68) }
    private var fill: Color {
        switch background {
        case .transparent: .clear
        case .light: Color(red: 0.96, green: 0.97, blue: 0.985)
        case .dark: Color(red: 0.018, green: 0.035, blue: 0.075)
        }
    }

    var body: some View {
        ZStack {
            fill
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("HYSE")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .tracking(2)
                    Spacer()
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(HyseColor.accent)
                }

                HStack(spacing: 16) {
                    Text(String(exerciseName.prefix(2)).uppercased())
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(HyseColor.accent)
                        .frame(width: 76, height: 76)
                        .background(HyseColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exerciseName)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                        Text(equipment)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(HyseColor.accent)
                    Text(heroTitle)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(secondary)
                    Text(heroValue)
                        .font(.system(size: 67, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.56)
                    if let heroDetail {
                        Text(heroDetail)
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .foregroundStyle(secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(foreground.opacity(0.065), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                HStack(spacing: 12) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(metric.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(metric.value)
                                .font(.title3.bold())
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(foreground.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(callToAction)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(HyseColor.accent)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(HyseConfiguration.serverHost)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HyseShareQRCode()
                }
            }
            .padding(38)
            .foregroundStyle(foreground)
            .shadow(color: background == .transparent ? .black.opacity(0.65) : .clear, radius: 2, y: 1)
        }
    }
}
