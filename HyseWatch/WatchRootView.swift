import SwiftUI

private let hyseTeal = Color(red: 0.05, green: 0.64, blue: 0.61)

struct WatchRootView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityStore

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    QuickNutritionView()
                } label: {
                    WatchFeatureLabel(
                        icon: "bolt.fill",
                        title: "Schneller Eintrag",
                        subtitle: "Kalorien & Makros"
                    )
                }

                NavigationLink {
                    ActiveWorkoutView()
                } label: {
                    WatchFeatureLabel(
                        icon: "dumbbell.fill",
                        title: connectivity.workout?.name ?? "Training",
                        subtitle: connectivity.workout == nil ? "Kein aktives Workout" : "Live verbunden"
                    )
                }
            }
            .listStyle(.carousel)
            .navigationTitle("Hyse")
            .task { connectivity.requestLatestState() }
        }
        .tint(hyseTeal)
    }
}

private struct WatchFeatureLabel: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(hyseTeal)
                .frame(width: 30, height: 30)
                .background(hyseTeal.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct QuickNutritionView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityStore
    @State private var calories = 0.0
    @State private var carbs = 0.0
    @State private var protein = 0.0
    @State private var fat = 0.0

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                WatchValueStepper(title: "Kalorien", unit: "kcal", value: $calories, step: 10, icon: "flame.fill")
                WatchValueStepper(title: "Kohlenhydrate", unit: "g", value: $carbs, step: 1, icon: "leaf.fill")
                WatchValueStepper(title: "Protein", unit: "g", value: $protein, step: 1, icon: "figure.strengthtraining.traditional")
                WatchValueStepper(title: "Fett", unit: "g", value: $fat, step: 1, icon: "drop.fill")

                Button {
                    connectivity.addQuickNutrition(calories: calories, carbs: carbs, protein: protein, fat: fat)
                } label: {
                    Label(buttonTitle, systemImage: buttonIcon)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(hyseTeal)
                .disabled(calories <= 0 || connectivity.deliveryState == .sending)
            }
            .padding(.horizontal, 3)
        }
        .navigationTitle("Eintrag")
        .onChange(of: connectivity.deliveryState) { _, state in
            guard state == .saved || state == .queued else { return }
            calories = 0; carbs = 0; protein = 0; fat = 0
        }
    }

    private var buttonTitle: String {
        switch connectivity.deliveryState {
        case .sending: "Sende …"
        case .saved: "Gespeichert"
        case .queued: "Wird synchronisiert"
        case .failed: "Erneut versuchen"
        case .idle: "Hinzufügen"
        }
    }

    private var buttonIcon: String {
        switch connectivity.deliveryState {
        case .saved: "checkmark"
        case .queued: "iphone.and.arrow.forward"
        case .failed: "exclamationmark.arrow.triangle.2.circlepath"
        default: "plus"
        }
    }
}

private struct WatchValueStepper: View {
    let title: String
    let unit: String
    @Binding var value: Double
    let step: Double
    let icon: String

    var body: some View {
        Stepper(value: $value, in: 0...9999, step: step) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(hyseTeal)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Text("\(value, specifier: step < 1 ? "%.1f" : "%.0f") \(unit)")
                        .font(.headline.monospacedDigit())
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct ActiveWorkoutView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityStore
    @EnvironmentObject private var workoutHealth: WatchWorkoutHealthManager

    var body: some View {
        Group {
            if let workout = connectivity.workout {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.name).font(.headline).lineLimit(2)
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Label(elapsed(workout, at: context.date), systemImage: workout.paused ? "pause.fill" : "timer")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(hyseTeal)
                            }
                            Label("Satz antippen und Werte ändern", systemImage: "hand.tap.fill")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            if workoutHealth.isRecording {
                                HStack(spacing: 12) {
                                    liveMetric(
                                        icon: "heart.fill",
                                        value: workoutHealth.heartRate > 0 ? "\(Int(workoutHealth.heartRate.rounded()))" : "–",
                                        unit: "BPM"
                                    )
                                    liveMetric(
                                        icon: "flame.fill",
                                        value: "\(Int(workoutHealth.activeCalories.rounded()))",
                                        unit: "kcal"
                                    )
                                }
                                .padding(.top, 3)
                            }
                            if let error = workoutHealth.errorMessage {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    ForEach(workout.exercises) { exercise in
                        Section(exercise.name) {
                            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                            NavigationLink {
                                    WatchSetEditor(
                                        workoutID: workout.id,
                                        exerciseID: exercise.id,
                                        initialSet: set,
                                        number: index + 1,
                                        exerciseType: exercise.type
                                    )
                            } label: {
                                    WatchEditableSetRow(
                                        number: index + 1,
                                        set: set,
                                        exerciseType: exercise.type
                                    )
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Kein aktives Training",
                    systemImage: "iphone.and.arrow.forward",
                    description: Text("Starte auf dem iPhone ein Workout. Es erscheint automatisch hier.")
                )
            }
        }
        .navigationTitle("Training")
        .task { connectivity.requestLatestState() }
    }

    private func elapsed(_ workout: WatchWorkout, at date: Date) -> String {
        let additional = workout.paused ? 0 : max(0, date.timeIntervalSince(workout.snapshotAt))
        let seconds = max(0, Int(workout.elapsedSeconds + additional))
        return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private func liveMetric(icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(hyseTeal)
            Text(value).font(.caption.bold().monospacedDigit())
            Text(unit).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

private struct WatchEditableSetRow: View {
    let number: Int
    let set: WatchSet
    let exerciseType: String

    var body: some View {
        HStack(spacing: 7) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(set.completed ? .white : .secondary)
                .frame(width: 27, height: 27)
                .background(set.completed ? hyseTeal : Color.white.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if exerciseType == "duration" {
                        valueColumn(title: "Zeit", value: durationText(set.durationSeconds))
                    } else if exerciseType == "distance_duration" {
                        valueColumn(title: "Distanz", value: distanceText(set.distanceMeters))
                        valueColumn(title: "Zeit", value: durationText(set.durationSeconds))
                    } else if exerciseType == "reps_only" {
                        valueColumn(title: "Wdh.", value: "\(set.reps)")
                    } else {
                        valueColumn(
                            title: "Gewicht",
                            value: "\(set.weight.formatted(.number.precision(.fractionLength(1)))) kg"
                        )
                        valueColumn(title: "Wdh.", value: "\(set.reps)")
                    }
                }
                Text(set.completed ? "Abgeschlossen" : "Zum Ändern antippen")
                    .font(.caption2)
                    .foregroundStyle(set.completed ? hyseTeal : .secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(hyseTeal)
        }
        .padding(.vertical, 2)
    }

    private func valueColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold).monospacedDigit())
        }
    }

    private func durationText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private func distanceText(_ meters: Double) -> String {
        meters >= 1_000 ? "\((meters / 1_000).formatted(.number.precision(.fractionLength(1)))) km" : "\(Int(meters.rounded())) m"
    }
}

private struct WatchSetEditor: View {
    @EnvironmentObject private var connectivity: WatchConnectivityStore
    @Environment(\.dismiss) private var dismiss
    let workoutID: UUID
    let exerciseID: UUID
    let number: Int
    let exerciseType: String
    @State private var set: WatchSet

    init(workoutID: UUID, exerciseID: UUID, initialSet: WatchSet, number: Int, exerciseType: String) {
        self.workoutID = workoutID
        self.exerciseID = exerciseID
        self.number = number
        self.exerciseType = exerciseType
        _set = State(initialValue: initialSet)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Satz \(number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("Mit − und + einstellen")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if exerciseType == "duration" {
                    WatchEditingStepper(title: "Zeit", value: $set.durationSeconds, range: 0...86_400, step: 5, unit: "Sek.")
                } else if exerciseType == "distance_duration" {
                    WatchEditingStepper(title: "Distanz", value: $set.distanceMeters, range: 0...1_000_000, step: 100, unit: "m")
                    WatchEditingStepper(title: "Zeit", value: $set.durationSeconds, range: 0...86_400, step: 5, unit: "Sek.")
                } else if exerciseType != "reps_only" {
                    WatchEditingStepper(title: "Gewicht", value: $set.weight, range: 0...999, step: 0.5, unit: "kg")
                }
                if exerciseType == "weight_reps" || exerciseType == "bodyweight" || exerciseType == "reps_only" {
                    WatchEditingStepper(
                        title: "Wiederholungen",
                        value: Binding(
                            get: { Double(set.reps) },
                            set: { set.reps = max(0, Int($0.rounded())) }
                        ),
                        range: 0...999,
                        step: 1,
                        unit: "Wdh."
                    )
                }

                Button {
                    set.completed.toggle()
                    connectivity.updateSet(workoutID: workoutID, exerciseID: exerciseID, set: set)
                    dismiss()
                } label: {
                    Label(set.completed ? "Wieder öffnen" : "Satz abschließen", systemImage: set.completed ? "arrow.uturn.backward" : "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(set.completed ? .gray : hyseTeal)
                .disabled(!set.completed && !isValid)

                Button("Änderungen speichern") {
                    connectivity.updateSet(workoutID: workoutID, exerciseID: exerciseID, set: set)
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Bearbeiten")
    }

    private var isValid: Bool {
        switch exerciseType {
        case "duration": return set.durationSeconds > 0
        case "distance_duration": return set.distanceMeters > 0 && set.durationSeconds > 0
        default: return set.reps > 0
        }
    }
}

private struct WatchEditingStepper: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text("\(value, specifier: step < 1 ? "%.1f" : "%.0f") \(unit)")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(hyseTeal)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
    }
}
