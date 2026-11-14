import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import CoreTransferable
import Charts

enum WorkoutShareMuscles {
    static func counts(for workout: WorkoutLog) -> [String: Double] {
        let halveUnilateral = UserDefaults.standard.bool(forKey: TrainingSetStatistics.settingKey)
        return workout.exercises.reduce(into: [String: Double]()) { result, exercise in
            let completedSets = TrainingSetStatistics.count(exercise, halveUnilateral: halveUnilateral)
            guard completedSets > 0 else { return }
            let corrected = TrainingExercise.repairedMuscleAssignment(
                exerciseID: exercise.exerciseID,
                englishName: exercise.exerciseNameSnapshot,
                germanName: exercise.exerciseGermanNameSnapshot,
                type: exercise.exerciseTypeSnapshot,
                equipment: exercise.equipmentSnapshot,
                primary: exercise.primaryMusclesSnapshot,
                secondary: exercise.secondaryMusclesSnapshot
            )
            let regions = TrainingMuscleRegionMap.weightedRegions(
                primary: corrected?.primary ?? exercise.primaryMusclesSnapshot,
                secondary: corrected?.secondary ?? exercise.secondaryMusclesSnapshot
            )
            for (muscle, weight) in regions {
                result[muscle, default: 0] += completedSets * weight
            }
        }
    }
}

enum WorkoutShareBackground: String, CaseIterable, Identifiable {
    case transparent, light, dark
    var id: String { rawValue }
    var localizationKey: String { "training.share.background.\(rawValue)" }
}

private struct WorkoutShareImage: Transferable {
    let pngData: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { image in image.pngData }
    }
}

struct WorkoutShareSheet: UIViewControllerRepresentable {
    let imageData: Data
    let message: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let items: [Any]
        if let image = UIImage(data: imageData) {
            items = [image, message]
        } else {
            items = [message]
        }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct FriendWorkoutShareLoaderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var language: LanguageStore
    let workout: FriendWorkout
    @ObservedObject var social: TrainingSocialStore
    @ObservedObject var store: TrainingStore
    @State private var isLoading = true

    private var shareWorkout: WorkoutLog? {
        store.completedWorkouts.first {
            $0.remoteID == workout.id
                || $0.id.uuidString.caseInsensitiveCompare(workout.clientID ?? "") == .orderedSame
        } ?? social.detail(for: workout.id)?.snapshot
    }

    var body: some View {
        Group {
            if let shareWorkout {
                WorkoutShareComposer(
                    workout: shareWorkout,
                    muscleCounts: WorkoutShareMuscles.counts(for: shareWorkout),
                    store: store,
                    shareURLOverride: WorkoutShareLink.url(workoutID: workout.id, isGerman: language.isGerman),
                    ownerUsername: workout.username
                )
            } else {
                NavigationStack {
                    VStack(spacing: HyseSpacing.large) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.large)
                        } else {
                            Text(language.text("training.feed.details_unavailable"))
                                .multilineTextAlignment(.center)
                            ShareLink(item: WorkoutShareLink.url(workoutID: workout.id, isGerman: language.isGerman)) {
                                Label(language.text("training.share.share_link"), systemImage: "link")
                            }
                            .buttonStyle(HysePrimaryButtonStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(HyseBackdrop())
                    .navigationTitle(language.text("training.share.title"))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(language.text("app_tabs.cancel")) { dismiss() }
                        }
                    }
                }
            }
        }
        .task {
            if shareWorkout == nil {
                _ = await social.loadDetail(id: workout.id, auth: authManager, force: true)
            }
            isLoading = false
        }
    }
}

struct WorkoutShareComposer: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false
    @AppStorage("trainingWeightUnit_v1") private var weightUnitRaw = TrainingWeightUnit.kilograms.rawValue
    @AppStorage("trainingDistanceUnit_v1") private var distanceUnitRaw = TrainingDistanceUnit.kilometers.rawValue
    let workout: WorkoutLog
    let muscleCounts: [String: Double]
    @ObservedObject var store: TrainingStore
    var shareURLOverride: URL? = nil
    var ownerUsername: String? = nil
    @State private var background = WorkoutShareBackground.dark
    @State private var renderedImage: WorkoutShareImage?
    @State private var didCopyText = false
    @State private var showingShareSheet = false
    @State private var resolvedShareURL: URL?
    @State private var isCheckingShareLink = false
    @State private var hasCheckedShareLink = false

    private var weightUnit: TrainingWeightUnit { TrainingWeightUnit(rawValue: weightUnitRaw) ?? .kilograms }
    private var distanceUnit: TrainingDistanceUnit { TrainingDistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers }
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        NavigationStack {
            ZStack {
                HyseBackdrop()
                ScrollView {
                    VStack(spacing: HyseSpacing.large) {
                        ZStack {
                            WorkoutTransparencyGrid()
                            if let renderedImage, let image = UIImage(data: renderedImage.pngData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                ProgressView()
                                    .controlSize(.large)
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
                            Text(t("training.share.background"))
                                .font(.headline)
                            Picker(t("training.share.background"), selection: $background) {
                                ForEach(WorkoutShareBackground.allCases) { option in
                                    Text(t(option.localizationKey)).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        HStack(spacing: HyseSpacing.medium) {
                            if renderedImage != nil {
                                Button {
                                    showingShareSheet = true
                                } label: {
                                    Label(t(shareURL == nil ? "training.share.share_image_only" : "training.share.share_image"), systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 52)
                                }
                                .buttonStyle(HysePrimaryButtonStyle())
                                .disabled(isShareLinkPending)
                            } else {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                            }

                            Button {
                                UIPasteboard.general.string = shareText
                                didCopyText = true
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                Task {
                                    try? await Task.sleep(for: .seconds(1.5))
                                    didCopyText = false
                                }
                            } label: {
                                Label(
                                    t(didCopyText ? "training.share.text_copied" : "training.share.copy_text"),
                                    systemImage: didCopyText ? "checkmark" : "doc.on.doc"
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                            }
                            .buttonStyle(HyseSecondaryButtonStyle())
                            .disabled(isShareLinkPending)
                        }

                        if let shareURL {
                            ShareLink(item: shareURL) {
                                Label(t("training.share.share_link"), systemImage: "link")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                            }
                            .buttonStyle(HyseSecondaryButtonStyle())
                        } else if isShareLinkPending {
                            ProgressView(t("training.share.link_preparing"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if workout.visibility == "public" && !authManager.isLoggedIn {
                            Label(t("training.share.link_requires_account"), systemImage: "person.crop.circle.badge.exclamationmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if workout.visibility == "public" {
                            Button {
                                Task { await checkShareLink() }
                            } label: {
                                Label(t("training.share.link_retry"), systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(HyseSecondaryButtonStyle())
                            .disabled(isCheckingShareLink)
                        } else {
                            Label(t("training.share.link_requires_public"), systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, HyseSpacing.page)
                    .padding(.vertical, HyseSpacing.large)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(t("training.share.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("app_tabs.cancel")) { dismiss() }
                }
            }
        }
        .task(id: renderID) {
            await Task.yield()
            renderShareImage()
        }
        .task { await checkShareLink() }
        .sheet(isPresented: $showingShareSheet) {
            if let renderedImage {
                WorkoutShareSheet(imageData: renderedImage.pngData, message: shareCaption)
            }
        }
    }

    private var renderID: String {
        [background.rawValue, language.locale.identifier, weightUnit.rawValue, workout.updatedAt.description].joined(separator: "|")
    }

    private var shareURL: URL? {
        if let shareURLOverride { return shareURLOverride }
        return resolvedShareURL
    }

    private var isShareLinkPending: Bool {
        workout.visibility == "public" && shareURLOverride == nil && !hasCheckedShareLink
    }

    private func checkShareLink() async {
        guard workout.visibility == "public", shareURLOverride == nil else {
            hasCheckedShareLink = true
            return
        }
        guard !isCheckingShareLink else { return }
        isCheckingShareLink = true
        hasCheckedShareLink = false
        resolvedShareURL = nil
        defer {
            isCheckingShareLink = false
            hasCheckedShareLink = true
        }
        guard authManager.isLoggedIn else { return }
        await store.flushPendingSync()
        guard let current = store.completedWorkouts.first(where: { $0.id == workout.id }),
              current.visibility == "public",
              let detail = try? await TrainingSocialService.shared.workoutDetail(current.id.uuidString.lowercased()) else { return }
        resolvedShareURL = WorkoutShareLink.url(workoutID: detail.workout.id, isGerman: language.isGerman)
    }

    private var shareText: String {
        var lines = [workout.name, formattedDate]
        if let gymName = workout.gymName, !gymName.isEmpty {
            lines.append([gymName, workout.gymAddress].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
        }
        lines.append("")
        for exercise in workout.exercises where exercise.completedSetCount > 0 {
            lines.append(exerciseName(exercise))
            for (index, set) in exercise.sets.enumerated() where set.completed {
                lines.append("Set \(index + 1): \(setDescription(set, type: exercise.exerciseTypeSnapshot))")
            }
            lines.append("")
        }
        lines.append(t("training.share.app_store_caption"))
        lines.append("@hyseapp")
        if let shareURL { lines.append(shareURL.absoluteString) }
        return lines.joined(separator: "\n")
    }

    private var shareCaption: String {
        let intro = ownerUsername.map { t("training.share.friend_caption", "@\($0)", workout.name) }
            ?? t("training.share.caption", workout.name)
        var lines = [intro, t("training.share.app_store_caption")]
        if let shareURL { lines.append(shareURL.absoluteString) }
        return lines.joined(separator: "\n")
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: workout.completedAt ?? workout.startedAt)
    }

    private func exerciseName(_ exercise: WorkoutExerciseLog) -> String {
        language.isGerman && !exercise.exerciseGermanNameSnapshot.isEmpty
            ? exercise.exerciseGermanNameSnapshot
            : exercise.exerciseNameSnapshot
    }

    private func setDescription(_ set: TrainingSetLog, type: TrainingExerciseType) -> String {
        switch type {
        case .weightReps:
            let weight = weightUnit.display(set.weightKilograms).formatted(
                .number.precision(.fractionLength(0...1)).locale(language.locale)
            )
            return "\(weight) \(weightUnit.rawValue) × \(set.reps)"
        case .bodyweight, .repsOnly:
            return "\(set.reps) \(t("training.reps"))"
        case .duration:
            return shortDuration(set.durationSeconds)
        case .distanceDuration:
            let distance = distanceUnit.display(set.distanceMeters).formatted(
                .number.precision(.fractionLength(0...2)).locale(language.locale)
            )
            return "\(distance) \(distanceUnit.rawValue) · \(shortDuration(set.durationSeconds))"
        }
    }

    private func shortDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) s" }
        return "\(total / 60) min \(total % 60) s"
    }

    private var shareDuration: String {
        let totalMinutes = max(0, Int(workout.duration) / 60)
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }

    private func renderShareImage() {
        renderedImage = nil
        let completedExercises = workout.exercises.filter { $0.completedSetCount > 0 }
        let card = WorkoutShareCard(
            workout: workout,
            muscleCounts: muscleCounts,
            background: background,
            ownerUsername: ownerUsername,
            duration: shareDuration,
            volume: "\(weightUnit.display(workout.totalVolume).formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))) \(weightUnit.rawValue)",
            sets: TrainingSetStatistics.formatted(TrainingSetStatistics.count(workout, halveUnilateral: halveUnilateral), locale: language.locale),
            exercises: Array(completedExercises.prefix(4)).map { (exerciseName($0), TrainingSetStatistics.formatted(TrainingSetStatistics.count($0, halveUnilateral: halveUnilateral), locale: language.locale)) },
            hasMoreExercises: completedExercises.count > 4,
            durationTitle: t("training.duration"),
            volumeTitle: t("training.total_volume"),
            setsTitle: t("training.completed_sets"),
            exercisesTitle: t("training.share.exercises"),
            moreExercisesTitle: t("training.share.more_exercises"),
            callToAction: t("training.share.card_cta")
        )
        .frame(width: 540, height: 675)
        .environment(\.locale, language.locale)
        .environment(\.colorScheme, background == .light ? .light : .dark)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        renderer.isOpaque = background != .transparent
        guard let data = renderer.uiImage?.pngData() else { return }
        renderedImage = WorkoutShareImage(pngData: data)
    }
}

private struct WorkoutShareCard: View {
    let workout: WorkoutLog
    let muscleCounts: [String: Double]
    let background: WorkoutShareBackground
    let ownerUsername: String?
    let duration: String
    let volume: String
    let sets: String
    let exercises: [(name: String, count: String)]
    let hasMoreExercises: Bool
    let durationTitle: String
    let volumeTitle: String
    let setsTitle: String
    let exercisesTitle: String
    let moreExercisesTitle: String
    let callToAction: String

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
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.title.bold())
                        .foregroundStyle(HyseColor.accent)
                    Text("HYSE")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .tracking(2)
                    Spacer()
                    Text(ownerUsername.map { "@\($0)" } ?? "@hyseapp")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(secondary)
                }

                Text(workout.name)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                HStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(red: 0.015, green: 0.03, blue: 0.065))
                        DetailedTrainingMuscleBody(counts: muscleCounts)
                            .padding(12)
                    }
                    .frame(width: 230, height: 165)

                    VStack(spacing: 15) {
                        shareMetric(value: duration, title: durationTitle)
                        shareMetric(value: volume, title: volumeTitle)
                        shareMetric(value: sets, title: setsTitle)
                    }
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(exercisesTitle.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(secondary)
                    ForEach(Array(exercises.enumerated()), id: \.offset) { _, exercise in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(exercise.count)×")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(HyseColor.accent)
                            Text(exercise.name)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                    if hasMoreExercises {
                        Text(moreExercisesTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(callToAction)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(HyseColor.accent)
                        Text(HyseConfiguration.serverHost)
                        Text((workout.completedAt ?? workout.startedAt).formatted(.dateTime.day().month().year()))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HyseShareQRCode()
                }
            }
            .padding(38)
            .foregroundStyle(foreground)
            .shadow(color: background == .transparent ? .black.opacity(0.65) : .clear, radius: 2, y: 1)
        }
    }

    private func shareMetric(value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.66)
            Text(title)
                .font(.caption)
                .foregroundStyle(secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HyseShareQRCode: View {
    var body: some View {
        Image("HyseShareQRCode")
            .resizable()
            .interpolation(.none)
            .frame(width: 88, height: 88)
            .padding(7)
            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel("Hyse QR-Code")
    }
}

struct WorkoutTransparencyGrid: View {
    var body: some View {
        Canvas { context, size in
            let side: CGFloat = 18
            let columns = Int(ceil(size.width / side))
            let rows = Int(ceil(size.height / side))
            for row in 0..<rows {
                for column in 0..<columns {
                    let color = (row + column).isMultiple(of: 2)
                        ? Color.white.opacity(0.13)
                        : Color.black.opacity(0.12)
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)),
                        with: .color(color)
                    )
                }
            }
        }
        .background(HyseColor.elevatedSurface)
    }
}
