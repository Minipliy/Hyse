import SwiftUI

struct ExerciseProgressGoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    let goal: ExerciseProgressGoal?
    let weightUnit: TrainingWeightUnit
    let usesWeight: Bool
    let save: (ExerciseProgressGoal) -> Void
    let remove: () -> Void
    @State private var minimumRepetitions: Int
    @State private var maximumRepetitions: Int
    @State private var incrementText: String
    @State private var shouldIncreaseWeight: Bool
    @FocusState private var incrementFocused: Bool

    init(goal: ExerciseProgressGoal?, weightUnit: TrainingWeightUnit, usesWeight: Bool, save: @escaping (ExerciseProgressGoal) -> Void, remove: @escaping () -> Void) {
        self.goal = goal
        self.weightUnit = weightUnit
        self.usesWeight = usesWeight
        self.save = save
        self.remove = remove
        _minimumRepetitions = State(initialValue: goal?.minimumRepetitions ?? 8)
        _maximumRepetitions = State(initialValue: goal?.maximumRepetitions ?? 10)
        _incrementText = State(initialValue: weightUnit.display(goal?.weightIncrementKilograms ?? 2.5).formatted(.number.precision(.fractionLength(0...2))))
        _shouldIncreaseWeight = State(initialValue: (goal?.weightIncrementKilograms ?? 2.5) > 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(language.text("training.progress.preview"), systemImage: "target")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HyseColor.accent)
                        Text(language.text("training.progress.range", [minimumRepetitions, maximumRepetitions]))
                            .font(.title3.bold())
                        if let stepPreview {
                            Text(stepPreview).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .listRowBackground(HyseColor.accent.opacity(0.08))
                Section {
                    Stepper(value: $minimumRepetitions, in: 1...30) {
                        LabeledContent(language.text("training.progress.min_reps"), value: "\(minimumRepetitions)")
                    }
                    Stepper(value: $maximumRepetitions, in: minimumRepetitions...40) {
                        LabeledContent(language.text("training.progress.max_reps"), value: "\(maximumRepetitions)")
                    }
                } footer: {
                    Text(language.text("training.progress.explanation"))
                }
                if usesWeight {
                    Section {
                        Toggle(language.text("training.progress.increase_weight"), isOn: $shouldIncreaseWeight)
                        LabeledContent(language.text("training.progress.weight_step")) {
                            TextField("2.5", text: $incrementText)
                                .keyboardType(.decimalPad)
                                .focused($incrementFocused)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                            Text(weightUnit.rawValue).foregroundStyle(.secondary)
                        }
                        .disabled(!shouldIncreaseWeight)
                    } header: {
                        Text(language.text("training.progress.weight_step"))
                    } footer: {
                        if shouldIncreaseWeight && !incrementIsValid {
                            Text(language.text("training.progress.invalid_step"))
                                .foregroundStyle(HyseColor.warning)
                        }
                    }
                }
                if goal != nil {
                    Section {
                        Button(role: .destructive) {
                            remove()
                            dismiss()
                        } label: { Label(language.text("training.progress.remove"), systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(language.text("training.progress.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("app_tabs.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("training.progress.save")) {
                        save(ExerciseProgressGoal(
                            minimumRepetitions: minimumRepetitions,
                            maximumRepetitions: maximumRepetitions,
                            weightIncrementKilograms: usesWeight && shouldIncreaseWeight ? weightUnit.kilograms(incrementValue) : 0
                        ))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(usesWeight && shouldIncreaseWeight && !incrementIsValid)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(language.text("add_entry.done")) { incrementFocused = false }
                }
            }
            .onChange(of: minimumRepetitions) { _, value in
                maximumRepetitions = max(value, maximumRepetitions)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var incrementValue: Double {
        Double(incrementText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var incrementIsValid: Bool {
        let value = incrementValue
        return value.isFinite && value > 0 && value <= 50
    }
    private var stepPreview: String? {
        guard usesWeight && shouldIncreaseWeight else { return language.text("training.progress.no_step") }
        guard incrementIsValid else { return nil }
        return language.text("training.progress.preview_increment", [
            incrementValue.formatted(.number.precision(.fractionLength(0...2)).locale(language.locale)),
            weightUnit.rawValue
        ])
    }
}
