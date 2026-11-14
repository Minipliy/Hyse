import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import CoreTransferable
import Charts
import Combine

struct WorkoutExerciseAdditionNotice: Identifiable {
    let id = UUID()
    let text: String
}

struct WorkoutExerciseAddedToast: View {
    let text: String

    var body: some View {
        HStack(spacing: HyseSpacing.small) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(HyseColor.accent)
            Text(text)
                .foregroundStyle(.primary)
        }
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HyseSpacing.medium)
            .padding(.vertical, HyseSpacing.small)
            .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous)
                    .stroke(HyseColor.accent.opacity(0.55))
            }
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .allowsHitTesting(false)
    }
}

struct ExerciseLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var premium: PremiumAccessStore
    @ObservedObject var store: TrainingStore
    let selectionMode: Bool
    var onAdded: ((UUID, String, Int) -> Void)? = nil
    var onSelection: (([TrainingExercise]) -> Void)? = nil
    @State private var query = ""
    @State private var equipment: TrainingEquipment?
    @State private var muscle: String?
    @State private var favoritesOnly = false
    @State private var recentOnly = false
    @State private var showingCreate = false
    @State private var showingTrainingPremium = false
    @State private var progressExercise: TrainingExercise?
    @State private var showingEquipmentFilter = false
    @State private var showingMuscleFilter = false
    @State private var addingExerciseID: UUID?
    @State private var selectedExerciseIDs: [UUID] = []
    @State private var addErrorMessage: String?
    private var customExerciseCreationRequiresPremium: Bool {
        let count = store.exercises.filter { $0.isCustom && !TrainingExercise.isRetiredImported($0) }.count
        return !premium.hasTraining && count >= TrainingStore.freeCustomExerciseLimit
    }
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var filtered: [TrainingExercise] {
        // The imported Hevy history can contain hundreds of sets. Build the
        // recent ranking once instead of rescanning that history from every
        // comparison performed by `sorted`.
        let recentIDs = store.recentlyUsedExerciseIDs
        let recent = Set(recentIDs)
        let recentRank = Dictionary(uniqueKeysWithValues: recentIDs.enumerated().map { ($0.element, $0.offset) })
        let isGerman = language.isGerman
        let displayNames = Dictionary(uniqueKeysWithValues: store.exercises.map { ($0.id, $0.displayName(isGerman: isGerman)) })
        let searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches: [(exercise: TrainingExercise, score: Int)] = store.exercises.compactMap { exercise in
            guard (!favoritesOnly || exercise.isFavorite),
                  (!recentOnly || recent.contains(exercise.id)),
                  (equipment == nil || exercise.equipment == equipment),
                  matchesSelectedMuscle(exercise),
                  let score = TrainingExerciseSearch.score(
                    exercise, query: searchQuery, isGerman: isGerman,
                    muscleName: { t("training.muscle.\($0)") }
                  ) else { return nil }
            return (exercise, score)
        }
        return matches.sorted { left, right in
            if !searchQuery.isEmpty && left.score != right.score { return left.score < right.score }
            let leftRecent = recentRank[left.exercise.id]
            let rightRecent = recentRank[right.exercise.id]
            if (selectionMode || recentOnly), leftRecent != rightRecent { return (leftRecent ?? .max) < (rightRecent ?? .max) }
            return displayNames[left.exercise.id, default: ""].localizedStandardCompare(displayNames[right.exercise.id, default: ""]) == .orderedAscending
        }.map { $0.exercise }
    }
    var body: some View {
        NavigationStack {
            List {
                if let addErrorMessage { HyseStatusBanner(title: nil, message: addErrorMessage, style: .error) }
                Section {
                    HyseSearchField(placeholder: t("training.exercise.search"), text: $query)
                    if selectionMode {
                        HStack(spacing: HyseSpacing.small) {
                            Button { showingEquipmentFilter = true } label: {
                                exerciseFilterControl(equipment.map { t($0.localizationKey) } ?? t("training.exercise_picker.all_equipment"), selected: equipment != nil, wide: true)
                            }
                            .buttonStyle(.plain)
                            Button { showingMuscleFilter = true } label: {
                                exerciseFilterControl(muscle.map(muscleFilterTitle) ?? t("training.exercise_picker.all_muscles"), selected: muscle != nil, wide: true)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: HyseSpacing.small) {
                                Button { favoritesOnly.toggle() } label: { exerciseFilterChip(t("training.favorites"), icon: favoritesOnly ? "star.fill" : "star", selected: favoritesOnly) }.buttonStyle(.plain)
                                Button { recentOnly.toggle() } label: { exerciseFilterChip(t("training.recently_used"), icon: recentOnly ? "clock.fill" : "clock", selected: recentOnly) }.buttonStyle(.plain)
                                equipmentMenu(wide: false)
                                muscleMenu(wide: false)
                            }
                        }
                    }
                    if favoritesOnly || recentOnly || equipment != nil || muscle != nil {
                        Button(t("training.filter.reset")) { favoritesOnly = false; recentOnly = false; equipment = nil; muscle = nil }.font(.caption)
                    }
                }
                if selectionMode, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let recentIDs = Set(store.recentlyUsedExerciseIDs)
                    let recent = filtered.filter { recentIDs.contains($0.id) }
                    let remaining = filtered.filter { !recentIDs.contains($0.id) }
                    if !recent.isEmpty {
                        Section(t("training.recently_used")) {
                            ForEach(recent) { exercise in exerciseSelectionRow(exercise) }
                        }
                    }
                    Section(t("training.exercises")) {
                        ForEach(remaining) { exercise in exerciseSelectionRow(exercise) }
                    }
                } else if selectionMode {
                    Section(t("training.exercises")) {
                        ForEach(filtered) { exercise in exerciseSelectionRow(exercise) }
                    }
                } else {
                    ForEach(filtered) { exercise in exerciseLibraryRow(exercise) }
                }
            }
            .hyseForm()
            .listStyle(.plain)
            .navigationTitle(t(selectionMode ? "training.exercise.add" : "training.exercises"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if selectionMode, !selectedExerciseIDs.isEmpty {
                    Button(action: addSelectedExercises) {
                        Text(selectedExerciseIDs.count == 1 ? t("training.exercise.add") : t("training.exercise.add_count", selectedExerciseIDs.count))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, HyseSpacing.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HyseColor.accent)
                    .disabled(addingExerciseID != nil)
                    .padding(.horizontal, HyseSpacing.page)
                    .padding(.top, HyseSpacing.medium)
                    .padding(.bottom, HyseSpacing.xLarge)
                    .background(HyseColor.elevatedSurface)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selectionMode ? t("app_tabs.cancel") : t("training.close")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if !customExerciseCreationRequiresPremium { showingCreate = true }
                        else { showingTrainingPremium = true }
                    } label: {
                        HStack(spacing: 5) {
                            Text(t("training.exercise.create"))
                            if customExerciseCreationRequiresPremium {
                                PremiumFeatureIcon(area: .training)
                            }
                        }
                    }
                        .accessibilityLabel(t("training.exercise.create"))
                }
            }
        }
        .sheet(isPresented: $showingCreate) { CreateExerciseView(store: store) }
        .sheet(isPresented: $showingEquipmentFilter) { equipmentFilterSheet }
        .sheet(isPresented: $showingMuscleFilter) { muscleFilterSheet }
        .sheet(isPresented: $showingTrainingPremium) { PremiumPaywallView(requestedArea: .training) }
        .sheet(item: $progressExercise) { exercise in NavigationStack { ExerciseProgressView(exercise: exercise, store: store) } }
    }

    @ViewBuilder private func exerciseSelectionRow(_ exercise: TrainingExercise) -> some View {
        let selected = selectedExerciseIDs.contains(exercise.id)
        HStack(spacing: HyseSpacing.medium) {
            Button { toggleSelection(exercise) } label: {
                HStack(spacing: HyseSpacing.medium) {
                    ZStack(alignment: .topTrailing) {
                        ExerciseMovementVisual(exercise: exercise, height: 42)
                            .frame(width: 48, height: 48)
                            .background(HyseColor.accent.opacity(0.11), in: Circle())
                            .clipShape(Circle())
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white, HyseColor.accent)
                                .background(Circle().fill(HyseColor.accent))
                                .offset(x: 3, y: -3)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise.displayName(isGerman: language.isGerman))
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(exercise.primaryMuscles.map { t("training.muscle.\($0)") }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { progressExercise = exercise } label: {
                Image(systemName: "info.circle.fill").font(.title3).foregroundStyle(.secondary).frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("common.info"))
        }
        .padding(.vertical, 3)
        .listRowBackground(selected ? HyseColor.accent.opacity(0.16) : Color.clear)
    }

    private func exerciseLibraryRow(_ exercise: TrainingExercise) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            Button { progressExercise = exercise } label: {
                HStack(spacing: HyseSpacing.medium) {
                    ExerciseMovementVisual(exercise: exercise, height: 38)
                        .frame(width: 44, height: 44)
                        .background(HyseColor.accent.opacity(0.11), in: Circle())
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise.displayName(isGerman: language.isGerman))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(t(exercise.equipment.localizationKey)) · \(exercise.primaryMuscles.map { t("training.muscle.\($0)") }.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chart.xyaxis.line").font(.subheadline.weight(.bold)).foregroundStyle(HyseColor.accent).frame(width: 34, height: 34).background(HyseColor.accent.opacity(0.10), in: Circle())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { store.toggleFavorite(exercise.id) } label: { Image(systemName: exercise.isFavorite ? "star.fill" : "star").foregroundStyle(exercise.isFavorite ? HyseColor.warning : .secondary).frame(width: 40, height: 40) }.buttonStyle(.plain).accessibilityLabel(t(exercise.isFavorite ? "training.favorite.remove" : "training.favorite.add"))
        }
        .padding(.vertical, 3)
        .hyseGlassListRows()
    }

    private func toggleSelection(_ exercise: TrainingExercise) {
        if let index = selectedExerciseIDs.firstIndex(of: exercise.id) {
            selectedExerciseIDs.remove(at: index)
        } else {
            selectedExerciseIDs.append(exercise.id)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func addSelectedExercises() {
        guard addingExerciseID == nil else { return }
        let byID = Dictionary(uniqueKeysWithValues: store.exercises.map { ($0.id, $0) })
        let exercises = selectedExerciseIDs.compactMap { byID[$0] }
        guard let first = exercises.first else { return }
        if let onSelection {
            onSelection(exercises)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
            return
        }
        addingExerciseID = first.id
        var lastPlacement: (UUID, String)?
        var addedCount = 0
        for exercise in exercises {
            if let placementID = store.addExercise(exercise) {
                lastPlacement = (placementID, exercise.displayName(isGerman: language.isGerman))
                addedCount += 1
            }
        }
        addingExerciseID = nil
        if let lastPlacement {
            onAdded?(lastPlacement.0, lastPlacement.1, addedCount)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } else {
            addErrorMessage = t("training.exercise.add_failed")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @ViewBuilder private func equipmentMenu(wide: Bool) -> some View {
        Menu {
            Button(t("training.filter.all")) { equipment = nil }
            ForEach(TrainingEquipment.allCases) { value in Button(t(value.localizationKey)) { equipment = value } }
        } label: {
            exerciseFilterControl(equipment.map { t($0.localizationKey) } ?? t("training.filter.all"), selected: equipment != nil, wide: wide)
        }
    }

    private func matchesSelectedMuscle(_ exercise: TrainingExercise) -> Bool {
        guard let muscle else { return true }
        let primary = Set(exercise.primaryMuscles)
        switch muscle {
        case "abs":
            return !primary.intersection(["abs", "core", "obliques"]).isEmpty
        case "shoulders":
            return !primary.intersection(["shoulders", "front_shoulders", "rear_shoulders", "lateral_shoulders"]).isEmpty
        case "traps":
            // Older imported and built-in shrug entries were stored as upper
            // back before the dedicated trapezius region existed.
            return !primary.intersection(["traps", "upper_back"]).isEmpty
        case "full_body":
            return primary.count >= 3
        case "other":
            return !primary.isEmpty && primary.allSatisfy { !TrainingPickerMuscleOption.standardMuscleIDs.contains($0) }
        default:
            return primary.contains(muscle)
        }
    }

    private func muscleFilterTitle(_ identifier: String) -> String {
        TrainingPickerMuscleOption.all.first(where: { $0.id == identifier })
            .map { t($0.titleKey) }
            ?? t("training.muscle.\(identifier)")
    }

    private var visibleMuscleSections: [TrainingPickerMuscleSection] {
        // Keep the complete anatomical overview stable. A group must not
        // disappear merely because the locally available catalogue currently
        // has no matching exercise (for example, a custom-only group).
        TrainingPickerMuscleSection.all
    }

    private var equipmentFilterSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: HyseSpacing.medium), count: 2), spacing: HyseSpacing.medium) {
                    ForEach(TrainingEquipment.allCases) { item in
                        Button {
                            equipment = item
                        } label: {
                            filterTile(
                                title: t(item.localizationKey),
                                selected: equipment == item,
                                icon: equipmentSymbol(for: item)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(HyseSpacing.page)
            }
            .navigationTitle(t("training.equipment"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                filterSheetFooter(
                    clear: { equipment = nil },
                    showResults: { showingEquipmentFilter = false }
                )
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var muscleFilterSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HyseSpacing.xLarge) {
                    ForEach(visibleMuscleSections) { section in
                        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                            Text(t(section.titleKey))
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: HyseSpacing.medium), count: 2), spacing: HyseSpacing.medium) {
                                ForEach(section.options) { option in
                                    Button {
                                        muscle = option.id
                                    } label: {
                                        filterTile(
                                            title: t(option.titleKey),
                                            selected: muscle == option.id,
                                            muscleIDs: option.muscleIDs
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(HyseSpacing.page)
            }
            .navigationTitle(t("training.exercise_picker.muscle_group"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                filterSheetFooter(
                    clear: { muscle = nil },
                    showResults: { showingMuscleFilter = false }
                )
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func filterSheetFooter(clear: @escaping () -> Void, showResults: @escaping () -> Void) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            Button(t("training.exercise_picker.clear_filters"), action: clear)
                .buttonStyle(.bordered)
                .tint(.secondary)
            Button(t("training.exercise_picker.show_results", filtered.count), action: showResults)
                .buttonStyle(.borderedProminent)
                .tint(HyseColor.accent)
                .frame(maxWidth: .infinity)
        }
        .font(.headline)
        .padding(.horizontal, HyseSpacing.page)
        .padding(.vertical, HyseSpacing.medium)
        .background(HyseColor.elevatedSurface)
    }

    @ViewBuilder private func filterTile(title: String, selected: Bool, icon: String? = nil, muscleIDs: [String] = []) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            ZStack {
                Circle().fill(.white)
                if let icon {
                    Image(systemName: icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(HyseColor.accent)
                } else if muscleIDs.isEmpty {
                    Image(systemName: "figure.stand")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    DetailedTrainingMuscleBody(counts: Dictionary(uniqueKeysWithValues: muscleIDs.map { ($0, 1.0) }))
                        .frame(width: 58, height: 58)
                        .scaleEffect(1.4)
                        .clipShape(Circle())
                }
            }
            .frame(width: 58, height: 58)
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HyseSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous)
                .stroke(selected ? HyseColor.accent : Color.clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
    }

    private func equipmentSymbol(for equipment: TrainingEquipment) -> String {
        switch equipment {
        case .barbell: "dumbbell.fill"
        case .dumbbell: "dumbbell"
        case .kettlebell: "circle.hexagongrid.fill"
        case .machine: "gearshape.2.fill"
        case .cable: "cable.connector.horizontal"
        case .bodyweight: "figure.stand"
        case .bands: "link"
        case .cardio: "figure.run"
        case .other: "ellipsis"
        }
    }

    @ViewBuilder private func muscleMenu(wide: Bool) -> some View {
        Menu {
            Button(t("training.filter.all_muscles")) { muscle = nil }
            ForEach(Array(Set(store.exercises.flatMap(\.primaryMuscles))).sorted(), id: \.self) { value in Button(t("training.muscle.\(value)")) { muscle = value } }
        } label: {
            exerciseFilterControl(muscle.map { t("training.muscle.\($0)") } ?? t("training.filter.all_muscles"), selected: muscle != nil, wide: wide)
        }
    }

    private func exerciseFilterControl(_ title: String, selected: Bool, wide: Bool) -> some View {
        HStack(spacing: HyseSpacing.small) {
            Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(selected ? HyseColor.accent : Color.primary)
        .padding(.horizontal, HyseSpacing.medium)
        .frame(maxWidth: wide ? .infinity : nil, minHeight: 44)
        .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(selected ? HyseColor.accent.opacity(0.55) : HyseColor.border))
    }

    private func exerciseFilterChip(_ title: String, icon: String, selected: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(selected ? HyseColor.accent : HyseColor.elevatedSurface, in: Capsule())
            .overlay(Capsule().stroke(selected ? Color.clear : HyseColor.border))
    }

}

private struct TrainingPickerMuscleOption: Identifiable {
    let id: String
    let titleKey: String
    let muscleIDs: [String]

    static let standardMuscleIDs: Set<String> = [
        "abs", "core", "obliques", "biceps", "chest", "lats", "neck", "upper_back", "back",
        "shoulders", "front_shoulders", "rear_shoulders", "lateral_shoulders", "traps", "triceps", "forearms",
        "abductors", "adductors", "hamstrings", "glutes", "quadriceps", "calves", "cardio"
    ]

    static let all: [TrainingPickerMuscleOption] = [
        .init(id: "abs", titleKey: "training.muscle.abs", muscleIDs: ["abs", "core", "obliques"]),
        .init(id: "biceps", titleKey: "training.muscle.biceps", muscleIDs: ["biceps"]),
        .init(id: "chest", titleKey: "training.muscle.chest", muscleIDs: ["chest"]),
        .init(id: "lats", titleKey: "training.muscle.lats", muscleIDs: ["lats"]),
        .init(id: "neck", titleKey: "training.muscle.neck", muscleIDs: ["neck"]),
        .init(id: "upper_back", titleKey: "training.muscle.upper_back", muscleIDs: ["upper_back"]),
        .init(id: "shoulders", titleKey: "training.muscle.shoulders", muscleIDs: ["shoulders", "front_shoulders", "rear_shoulders", "lateral_shoulders"]),
        .init(id: "traps", titleKey: "training.muscle.traps", muscleIDs: ["traps"]),
        .init(id: "triceps", titleKey: "training.muscle.triceps", muscleIDs: ["triceps"]),
        .init(id: "forearms", titleKey: "training.muscle.forearms", muscleIDs: ["forearms"]),
        .init(id: "back", titleKey: "training.muscle.lower_back", muscleIDs: ["back"]),
        .init(id: "abductors", titleKey: "training.muscle.abductors", muscleIDs: ["abductors"]),
        .init(id: "adductors", titleKey: "training.muscle.adductors", muscleIDs: ["adductors"]),
        .init(id: "hamstrings", titleKey: "training.muscle.hamstrings", muscleIDs: ["hamstrings"]),
        .init(id: "glutes", titleKey: "training.muscle.glutes", muscleIDs: ["glutes"]),
        .init(id: "quadriceps", titleKey: "training.muscle.quadriceps", muscleIDs: ["quadriceps"]),
        .init(id: "calves", titleKey: "training.muscle.calves", muscleIDs: ["calves"]),
        .init(id: "cardio", titleKey: "training.muscle.cardio", muscleIDs: ["cardio"]),
        .init(id: "full_body", titleKey: "training.muscle.full_body", muscleIDs: []),
        .init(id: "other", titleKey: "training.muscle.other", muscleIDs: [])
    ]
}

private struct TrainingPickerMuscleSection: Identifiable {
    let id: String
    let titleKey: String
    let options: [TrainingPickerMuscleOption]

    static let all: [TrainingPickerMuscleSection] = [
        .init(id: "upper", titleKey: "training.exercise_picker.upper_body", options: Array(TrainingPickerMuscleOption.all.prefix(11))),
        .init(id: "lower", titleKey: "training.exercise_picker.lower_body", options: Array(TrainingPickerMuscleOption.all.dropFirst(11).prefix(6))),
        .init(id: "other", titleKey: "training.exercise_picker.other", options: Array(TrainingPickerMuscleOption.all.dropFirst(17)))
    ]
}

private struct CreateExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var premium: PremiumAccessStore
    @ObservedObject var store: TrainingStore
    @State private var name = ""
    @State private var muscle = "chest"
    @State private var type = TrainingExerciseType.weightReps
    @State private var equipment = TrainingEquipment.other
    @State private var isUnilateral = false
    @State private var showingTrainingPremium = false
    @State private var showingDuplicateExercise = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(language.text("training.exercise.name"), text: $name)
                } footer: {
                    Text(language.text("training.exercise.private_hint"))
                }
                Picker(language.text("training.exercise.type"), selection: $type) {
                    ForEach(TrainingExerciseType.allCases) { Text(language.text($0.localizationKey)).tag($0) }
                }
                Picker(language.text("training.equipment"), selection: $equipment) {
                    ForEach(TrainingEquipment.allCases) { Text(language.text($0.localizationKey)).tag($0) }
                }
                Picker(language.text("training.primary_muscle"), selection: $muscle) {
                    ForEach(["chest", "back", "quadriceps", "hamstrings", "glutes", "shoulders", "biceps", "triceps", "core", "cardio"], id: \.self) {
                        Text(language.text("training.muscle.\($0)")).tag($0)
                    }
                }
                Section {
                    Picker(language.text("training.exercise.laterality"), selection: $isUnilateral) {
                        Text(language.text("training.exercise.bilateral")).tag(false)
                        Text(language.text("training.exercise.unilateral")).tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(language.text("training.exercise.laterality_explanation"))
                }
            }
            .navigationTitle(language.text("training.exercise.create"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("app_tabs.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("add_entry.done")) {
                        if TrainingExercise.matchingCatalogExercise(named: name, equipment: equipment, in: store.exercises) != nil {
                            showingDuplicateExercise = true
                            return
                        }
                        let added = store.addCustomExercise(
                            name: name,
                            type: type,
                            equipment: equipment,
                            primaryMuscle: muscle,
                            isUnilateral: isUnilateral,
                            imageData: nil
                        )
                        if added { dismiss() } else { showingTrainingPremium = true }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingTrainingPremium) { PremiumPaywallView(requestedArea: .training) }
        .alert(language.text("training.exercise.already_exists"), isPresented: $showingDuplicateExercise) {
            Button(language.text("add_entry.done"), role: .cancel) { }
        } message: {
            Text(language.text("training.exercise.already_exists_message"))
        }
    }
}

enum ImageSelectionError: Error {
    case unreadable
}

extension UIImage {
    func hyseCompressedJPEG(maxDimension: CGFloat = 720, maxBytes: Int = 650_000) -> Data? {
        let longestSide = max(size.width, size.height)
        guard longestSide > 0 else { return nil }
        let scale = min(1, maxDimension / longestSide)
        let targetSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIColor.systemBackground.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        for quality in stride(from: 0.82, through: 0.42, by: -0.08) {
            if let data = normalized.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
        }
        return normalized.jpegData(compressionQuality: 0.35)
    }
}

struct SuggestedRoutineBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var store: TrainingStore
    @State private var selectedProgram: SuggestedRoutineProgram?
    @State private var query = ""
    @State private var selectedStyle: SuggestedRoutineStyle?
    @State private var selectedEquipment: RoutineEquipmentFilter?

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    private var filteredPrograms: [SuggestedRoutineProgram] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return SuggestedRoutineProgram.library(isGerman: language.isGerman).filter { program in
            let matchesQuery = normalizedQuery.isEmpty
                || program.title.localizedStandardContains(normalizedQuery)
                || program.summary.localizedStandardContains(normalizedQuery)
                || program.routines.contains { routine in
                    routine.name.localizedStandardContains(normalizedQuery)
                        || routine.exercises.contains {
                            $0.exercise.displayName(isGerman: language.isGerman).localizedStandardContains(normalizedQuery)
                        }
                }
            let matchesStyle = selectedStyle.map { program.style == $0 } ?? true
            let matchesEquipment = selectedEquipment.map { $0.matches(program.equipment) } ?? true
            return matchesQuery && matchesStyle && matchesEquipment
        }
    }

    private func routineFilterLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: HyseSpacing.small) {
            Image(systemName: icon)
            Text(title).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.caption2.bold())
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, HyseSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HyseBackdrop()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: HyseSpacing.large) {
                        HStack {
                            VStack(alignment: .leading, spacing: HyseSpacing.small) {
                                Text(t("training.routines.suggested")).font(.largeTitle.bold())
                                Text(t("info.training.suggested_routines"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HyseInfoButton(
                                title: t("training.routines.suggested"),
                                message: t("info.training.suggested_routines")
                            )
                        }

                        HyseSearchField(placeholder: t("training.routines.search_suggestions"), text: $query)

                        HStack(spacing: HyseSpacing.small) {
                            Menu {
                                Button(t("training.routines.filter.all_styles")) { selectedStyle = nil }
                                ForEach(SuggestedRoutineStyle.allCases) { style in
                                    Button(t(style.localizationKey)) { selectedStyle = style }
                                }
                            } label: {
                                routineFilterLabel(
                                    selectedStyle.map { t($0.localizationKey) } ?? t("training.routines.filter.all_styles"),
                                    icon: "slider.horizontal.3"
                                )
                            }
                            Menu {
                                Button(t("training.routines.filter.all_equipment")) { selectedEquipment = nil }
                                ForEach(RoutineEquipmentFilter.allCases) { equipment in
                                    Button(t(equipment.localizationKey)) { selectedEquipment = equipment }
                                }
                            } label: {
                                routineFilterLabel(
                                    selectedEquipment.map { t($0.localizationKey) } ?? t("training.routines.filter.all_equipment"),
                                    icon: "dumbbell"
                                )
                            }
                        }

                        if filteredPrograms.isEmpty {
                            HyseCard {
                                HyseEmptyState(
                                    icon: "magnifyingglass",
                                    title: t("training.routines.no_results"),
                                    message: t("training.routines.no_results_message")
                                )
                            }
                        } else {
                            ForEach(filteredPrograms) { program in
                                Button { selectedProgram = program } label: {
                                    VStack(alignment: .leading, spacing: HyseSpacing.small) {
                                        HStack {
                                            HyseIconBadge(icon: program.style == .endurance ? "figure.run" : "sparkles", size: 38)
                                            Spacer()
                                            Text(t(program.style.localizationKey))
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(HyseColor.accent)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 5)
                                                .background(HyseColor.accent.opacity(0.10), in: Capsule())
                                        }
                                        Text(program.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(t("training.routines.program_summary", program.routines.count, program.daysPerWeek))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Label(t("training.routines.view_program"), systemImage: "arrow.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(HyseColor.accent)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(HyseSpacing.medium)
                                    .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous)
                                            .stroke(HyseColor.accent.opacity(0.16))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(HyseSpacing.page)
                }
            }
            .navigationTitle(t("training.routines.hyse_suggestions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("add_entry.done")) { dismiss() }
                }
            }
        }
        .sheet(item: $selectedProgram) { program in
            SuggestedRoutineProgramView(program: program, store: store)
                .environmentObject(language)
        }
    }
}

private struct SuggestedRoutineProgramView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var premium: PremiumAccessStore
    let program: SuggestedRoutineProgram
    @ObservedObject var store: TrainingStore
    @State private var addedCount: Int?
    @State private var showingTrainingPremium = false
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        NavigationStack {
            ZStack {
                HyseBackdrop()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: HyseSpacing.large) {
                        VStack(alignment: .leading, spacing: HyseSpacing.small) {
                            HyseIconBadge(icon: "sparkles", size: 48)
                            Text(program.title).font(.largeTitle.bold())
                            Text(program.summary).foregroundStyle(.secondary)
                            Label(t("training.routines.days_per_week", program.daysPerWeek), systemImage: "calendar")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(HyseColor.accent)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(program.routines) { routine in
                            HyseCard {
                                VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                                    HStack {
                                        Text(routine.name).font(.title3.bold())
                                        Spacer()
                                        Text(t("training.routine.exercise_count", routine.exercises.count)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    ForEach(Array(routine.exercises.enumerated()), id: \.element.id) { index, item in
                                        HStack(alignment: .top, spacing: HyseSpacing.small) {
                                            Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 20)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(item.exercise.displayName(isGerman: language.isGerman))
                                                    .font(.subheadline)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                    .layoutPriority(1)
                                                if !item.notes.isEmpty {
                                                    Text(item.notes).font(.caption2).foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer(minLength: HyseSpacing.small)
                                            Text(t("training.routines.sets_reps", item.sets.count, item.sets.first?.reps ?? 0)).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        if let addedCount {
                            HyseStatusBanner(
                                title: addedCount > 0 ? t("training.routines.added_title") : t("training.routines.already_added_title"),
                                message: addedCount > 0 ? t("training.routines.added_message", addedCount) : t("training.routines.already_added_message"),
                                style: .success
                            )
                        }

                        Button {
                            if premium.hasTraining || store.routines.count < TrainingStore.freeRoutineLimit {
                                addedCount = store.addSuggestedProgram(program)
                            } else {
                                showingTrainingPremium = true
                            }
                        } label: {
                            HStack(spacing: HyseSpacing.small) {
                                Label(t("training.routines.add_program"), systemImage: "plus.circle.fill")
                                if !premium.hasTraining && store.routines.count >= TrainingStore.freeRoutineLimit {
                                    PremiumFeatureIcon(area: .training)
                                }
                            }
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, HyseSpacing.medium)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HyseColor.accent)
                    }
                    .padding(HyseSpacing.page)
                }
            }
            .navigationTitle(t("training.routines.hyse_suggestions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("add_entry.done")) { dismiss() } } }
        }
        .sheet(isPresented: $showingTrainingPremium) { PremiumPaywallView(requestedArea: .training) }
    }
}

private enum RoutineProgressMetric: String, CaseIterable, Identifiable {
    case volume, repetitions, duration
    var id: String { rawValue }
    var localizationKey: String {
        switch self {
        case .volume: "training.total_volume"
        case .repetitions: "training.reps"
        case .duration: "training.duration"
        }
    }
}

struct RoutineDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var premium: PremiumAccessStore
    @ObservedObject var store: TrainingStore
    let routineID: UUID
    @AppStorage("trainingWeightUnit_v1") private var trainingWeightUnitRaw = TrainingWeightUnit.kilograms.rawValue
    @State private var metric = RoutineProgressMetric.volume
    @State private var range = TrainingChartRange.threeMonths
    @State private var selectedWorkoutDate: Date?
    @State private var showingEditor = false
    @State private var showingActiveWorkout = false
    @State private var openedActiveWorkoutFromBar = false
    @State private var showingDeleteConfirmation = false
    @State private var showingTrainingPremium = false
    @State private var showingRoutineShare = false
    @State private var sharedRoutineImageURL: URL?

    private var routine: WorkoutRoutine? { store.routines.first(where: { $0.id == routineID }) }
    private var weightUnit: TrainingWeightUnit { TrainingWeightUnit(rawValue: trainingWeightUnitRaw) ?? .kilograms }
    private var effectiveRange: TrainingChartRange {
        !premium.hasTraining && (range == .oneYear || range == .allTime) ? .threeMonths : range
    }
    private var workouts: [WorkoutLog] {
        guard let routine else { return [] }
        return store.completedWorkouts
            .filter {
                ($0.routineID == routine.id || ($0.routineID == nil && $0.name == routine.name))
                    && effectiveRange.includes($0.completedAt ?? $0.startedAt)
            }
            .sorted { ($0.completedAt ?? $0.startedAt) < ($1.completedAt ?? $1.startedAt) }
    }
    private var selectedWorkout: WorkoutLog? {
        guard let selectedWorkoutDate else { return nil }
        return workouts.min {
            abs(($0.completedAt ?? $0.startedAt).timeIntervalSince(selectedWorkoutDate))
                < abs(($1.completedAt ?? $1.startedAt).timeIntervalSince(selectedWorkoutDate))
        }
    }
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        ZStack {
            HyseBackdrop()
            if let routine {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: HyseSpacing.section) {
                        routineHeader(routine)
                        progressSection
                        exerciseSection(routine)
                    }
                    .padding(.horizontal, HyseSpacing.page)
                    .padding(.vertical, HyseSpacing.medium)
                    .padding(.bottom, HyseSpacing.section)
                }
            } else {
                HyseEmptyState(icon: "list.bullet.rectangle", title: t("training.routine.missing"), message: t("training.routine.missing_message"))
            }
        }
        .navigationTitle(t("training.routine.detail_title"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.hasResolvedPersistenceScope, let workout = store.activeWorkout {
                ActiveWorkoutBar(
                    workout: workout,
                    discard: { store.discardActiveWorkout() },
                    open: {
                        openedActiveWorkoutFromBar = true
                        showingActiveWorkout = true
                    }
                )
                .padding(.top, HyseSpacing.small)
                .padding(.bottom, HyseSpacing.medium)
            }
        }
        .toolbar {
            if let routine {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingRoutineShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Menu {
                        Button { showingEditor = true } label: { Label(t("training.routine.edit"), systemImage: "pencil") }
                        Button { store.duplicateRoutine(routine) } label: { Label(t("training.routine.duplicate"), systemImage: "plus.square.on.square") }
                        Button(role: .destructive) { showingDeleteConfirmation = true } label: { Label(t("training.routine.delete"), systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let routine { RoutineBuilderView(store: store, routine: routine) }
        }
        .sheet(isPresented: $showingRoutineShare) {
            RoutineShareView(store: store, routineID: routineID)
        }
        .sheet(isPresented: $showingTrainingPremium) { PremiumPaywallView(requestedArea: .training) }
        .fullScreenCover(isPresented: $showingActiveWorkout, onDismiss: { openedActiveWorkoutFromBar = false }) {
            ActiveWorkoutView(store: store, animateToLatestCompletedExercise: openedActiveWorkoutFromBar)
        }
        .alert(t("training.routine.delete_confirm_title"), isPresented: $showingDeleteConfirmation) {
            Button(t("app_tabs.cancel"), role: .cancel) {}
            Button(t("training.routine.delete"), role: .destructive) {
                store.deleteRoutine(routineID)
                dismiss()
            }
        } message: { Text(t("training.routine.delete_confirm_message")) }
        .onChange(of: metric) { _, _ in selectedWorkoutDate = nil }
        .onChange(of: range) { _, _ in selectedWorkoutDate = nil }
        .onChange(of: premium.hasTraining) { _, unlocked in
            if !unlocked && (range == .oneYear || range == .allTime) { range = .threeMonths }
        }
        .task(id: routine?.shareRecordID) {
            guard let id = routine?.shareRecordID else { sharedRoutineImageURL = nil; return }
            sharedRoutineImageURL = try? await RoutineShareService.shared.fetch(id: id).imageURL
        }
    }

    private func routineHeader(_ routine: WorkoutRoutine) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            let localPhoto = RecipeImageStore.data(for: routine.imageFileName) ?? routine.imageData
            if localPhoto != nil || sharedRoutineImageURL != nil {
                RoutinePhotoView(localData: localPhoto, remoteURL: sharedRoutineImageURL, height: 230)
            }
            VStack(alignment: .leading, spacing: HyseSpacing.small) {
                Text(routine.name)
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                if !routine.details.isEmpty { Text(routine.details).font(.subheadline).foregroundStyle(.secondary) }
                HStack(spacing: HyseSpacing.small) {
                    Label(t("training.routine.exercise_count", routine.exercises.count), systemImage: "list.number")
                    if !routine.folder.isEmpty {
                        Text("·")
                        Label(routine.folder, systemImage: "folder")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            Button {
                guard store.activeWorkout == nil else { showingActiveWorkout = true; return }
                _ = store.start(routine: routine)
                showingActiveWorkout = true
            } label: {
                Text(store.activeWorkout == nil ? t("training.routine.start") : t("training.active.resume"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(HyseColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var progressSection: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            HStack {
                if let highlightedWorkout = selectedWorkout ?? workouts.last {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metricText(highlightedWorkout))
                            .font(.title2.bold())
                            .monospacedDigit()
                        Text((highlightedWorkout.completedAt ?? highlightedWorkout.startedAt)
                            .formatted(.dateTime.day().month(.abbreviated).locale(language.locale)))
                            .font(.caption)
                            .foregroundStyle(HyseColor.accent)
                    }
                } else {
                    Text(t("training.routine.progress")).font(.title3.bold())
                }
                Spacer()
                Menu {
                    ForEach(TrainingChartRange.allCases) { value in
                        Button {
                            if !premium.hasTraining && (value == .oneYear || value == .allTime) {
                                showingTrainingPremium = true
                            } else {
                                range = value
                            }
                        } label: {
                            Label(t(value.localizationKey), systemImage:
                                value == effectiveRange ? "checkmark" :
                                !premium.hasTraining && (value == .oneYear || value == .allTime) ? "crown.fill" : "calendar")
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(t(effectiveRange.localizationKey))
                        Image(systemName: "chevron.down")
                            .font(.caption.bold())
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HyseColor.accent)
                }
            }
            if workouts.isEmpty {
                HyseEmptyState(icon: "chart.xyaxis.line", title: t("training.routine.no_history"), message: t("training.routine.no_history_message"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HyseSpacing.large)
            } else {
                Chart {
                    ForEach(workouts) { workout in
                        LineMark(
                            x: .value(t("training.progress.date"), workout.completedAt ?? workout.startedAt),
                            y: .value(t(metric.localizationKey), metricValue(workout))
                        )
                        .foregroundStyle(HyseColor.accent)
                        .interpolationMethod(.linear)
                        PointMark(
                            x: .value(t("training.progress.date"), workout.completedAt ?? workout.startedAt),
                            y: .value(t(metric.localizationKey), metricValue(workout))
                        )
                        .foregroundStyle(HyseColor.accent)
                    }
                    if let selectedWorkout {
                        RuleMark(x: .value(t("training.progress.date"), selectedWorkout.completedAt ?? selectedWorkout.startedAt))
                            .foregroundStyle(.secondary.opacity(0.55))
                    }
                }
                .frame(height: 180)
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine()
                        AxisTick()
                        if metric == .duration {
                            AxisValueLabel {
                                if let minutes = value.as(Double.self) {
                                    Text(routineDurationAxisText(minutes))
                                }
                            }
                        } else {
                            AxisValueLabel()
                        }
                    }
                }
                .chartXSelection(value: $selectedWorkoutDate)
            }
            HyseSegmentedControl(
                items: RoutineProgressMetric.allCases,
                selection: $metric,
                title: { t($0.localizationKey) },
                symbol: { _ in "" }
            )
        }
    }

    private func exerciseSection(_ routine: WorkoutRoutine) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            HStack {
                Text(t("training.exercises")).font(.title3.bold())
                Spacer()
                Button(t("training.routine.edit")) { showingEditor = true }
                    .font(.subheadline.weight(.semibold))
            }
            ForEach(Array(routine.exercises.enumerated()), id: \.element.id) { index, item in
                routineExercise(item)
                if index < routine.exercises.count - 1 {
                    Divider().padding(.vertical, HyseSpacing.small)
                }
            }
        }
    }

    private func routineExercise(_ item: RoutineExercise) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            NavigationLink {
                ExerciseProgressView(exercise: item.exercise, store: store)
            } label: {
                HStack(spacing: HyseSpacing.medium) {
                    ExerciseMovementVisual(exercise: item.exercise, height: 50)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.exercise.displayName(isGerman: language.isGerman))
                            .font(.headline)
                            .foregroundStyle(HyseColor.accent)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                        Text(item.exercise.primaryMuscles.map { t("training.muscle.\($0)") }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !item.notes.isEmpty {
                Text(item.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label(t("training.exercise.rest_seconds", item.restSeconds), systemImage: "stopwatch")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(HyseColor.accent)

            routineSetHeader(for: item.exercise)
            ForEach(Array(item.sets.enumerated()), id: \.element.id) { index, set in
                routineSetRow(number: index + 1, set: set, exercise: item.exercise)
            }
        }
    }

    private func routineSetHeader(for exercise: TrainingExercise) -> some View {
        HStack(spacing: HyseSpacing.small) {
            Text(t("training.routine.set_column"))
                .frame(width: 48, alignment: .leading)
            switch exercise.type {
            case .weightReps:
                Text(t("training.weight").uppercased(with: language.locale))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(t("training.reps").uppercased(with: language.locale))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case .bodyweight, .repsOnly:
                Text(t("training.reps").uppercased(with: language.locale))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case .duration:
                Text(t("training.duration").uppercased(with: language.locale))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case .distanceDuration:
                Text(t("training.distance").uppercased(with: language.locale))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(t("training.duration").uppercased(with: language.locale))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func routineSetRow(number: Int, set: TrainingSetLog, exercise: TrainingExercise) -> some View {
        HStack(spacing: HyseSpacing.small) {
            Text("\(number)")
                .frame(width: 48, alignment: .leading)
            switch exercise.type {
            case .weightReps:
                Text(plannedWeight(set.weightKilograms))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("\(set.reps)")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case .bodyweight, .repsOnly:
                Text("\(set.reps)")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case .duration:
                Text(durationText(set.durationSeconds))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            case .distanceDuration:
                Text(plannedDistance(set.distanceMeters))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(durationText(set.durationSeconds))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.body.weight(.medium))
        .monospacedDigit()
    }

    private func plannedWeight(_ kilograms: Double) -> String {
        guard kilograms > 0 else { return "–" }
        return "\(weightUnit.display(kilograms).formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))) \(weightUnit.rawValue)"
    }

    private func plannedDistance(_ meters: Double) -> String {
        guard meters > 0 else { return "–" }
        return "\((meters / 1_000).formatted(.number.precision(.fractionLength(0...2)).locale(language.locale))) km"
    }

    private func metricValue(_ workout: WorkoutLog) -> Double {
        switch metric {
        case .volume: weightUnit.display(workout.totalVolume)
        case .repetitions: Double(workout.totalReps)
        case .duration: workout.duration / 60
        }
    }

    private func metricText(_ workout: WorkoutLog) -> String {
        switch metric {
        case .volume: "\(metricValue(workout).formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))) \(weightUnit.rawValue)"
        case .repetitions: t("training.routine.repetition_count", workout.totalReps)
        case .duration: activeWorkoutDurationText(workout.duration)
        }
    }

    private func routineDurationAxisText(_ minutes: Double) -> String {
        let totalMinutes = max(0, Int(minutes.rounded()))
        return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
    }
}

struct RoutineCardDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedRoutineID: UUID?
    @Binding var previewOrder: [UUID]?
    @Binding var hoverTargetID: UUID?
    let store: TrainingStore

    func dropEntered(info: DropInfo) {
        guard let sourceID = draggedRoutineID, sourceID != targetID,
              hoverTargetID != targetID,
              var order = previewOrder,
              let sourceIndex = order.firstIndex(of: sourceID),
              let targetIndex = order.firstIndex(of: targetID) else { return }
        hoverTargetID = targetID
        order.remove(at: sourceIndex)
        order.insert(sourceID, at: targetIndex)
        withAnimation(.easeInOut(duration: 0.22)) { previewOrder = order }
        ExerciseReorderFeedback.moved()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard let order = previewOrder, draggedRoutineID != nil else { return false }
        store.setRoutineOrder(order)
        ExerciseReorderFeedback.dropped()
        draggedRoutineID = nil
        previewOrder = nil
        hoverTargetID = nil
        return true
    }
}

/// Accepts a release between cards and resets a preview when dragging leaves the list.
struct RoutineListDropDelegate: DropDelegate {
    @Binding var draggedRoutineID: UUID?
    @Binding var previewOrder: [UUID]?
    @Binding var hoverTargetID: UUID?
    let store: TrainingStore

    func dropExited(info: DropInfo) {
        draggedRoutineID = nil
        previewOrder = nil
        hoverTargetID = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedRoutineID = nil
            previewOrder = nil
            hoverTargetID = nil
        }
        guard draggedRoutineID != nil, let order = previewOrder else { return false }
        store.setRoutineOrder(order)
        ExerciseReorderFeedback.dropped()
        return true
    }
}

struct RoutineListView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var premium: PremiumAccessStore
    @ObservedObject var store: TrainingStore
    @State private var showingBuilder = false
    @State private var showingActiveWorkout = false
    @State private var openedActiveWorkoutFromBar = false
    @State private var showingTrainingPremium = false
    @State private var editingRoutine: WorkoutRoutine?
    @State private var deletingRoutine: WorkoutRoutine?
    @State private var query = ""
    @State private var equipmentFilter: RoutineEquipmentFilter?
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var routineCreationRequiresPremium: Bool {
        !premium.hasTraining && store.routines.count >= TrainingStore.freeRoutineLimit
    }
    private var filteredRoutines: [WorkoutRoutine] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.routines.filter { routine in
            let matchesQuery = trimmed.isEmpty
                || routine.name.localizedStandardContains(trimmed)
                || routine.details.localizedStandardContains(trimmed)
                || routine.exercises.contains { $0.exercise.displayName(isGerman: language.isGerman).localizedStandardContains(trimmed) }
            let equipment = Set(routine.exercises.map(\.exercise.equipment))
            return matchesQuery && (equipmentFilter.map { $0.matches(equipment) } ?? true)
        }
    }
    private var groupedRoutines: [(String, [WorkoutRoutine])] {
        let values = Dictionary(grouping: filteredRoutines) { $0.folder.isEmpty ? t("training.routine.no_folder") : $0.folder }
        return values.map { ($0.key, $0.value.sorted { ($0.plannedWeekday ?? 8, $0.name) < ($1.plannedWeekday ?? 8, $1.name) }) }.sorted { $0.0 < $1.0 }
    }
    var body: some View {
        List {
            Section {
                HyseSearchField(placeholder: t("training.routines.search"), text: $query)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                Menu {
                    Button(t("training.routines.filter.all_equipment")) { equipmentFilter = nil }
                    ForEach(RoutineEquipmentFilter.allCases) { value in
                        Button(t(value.localizationKey)) { equipmentFilter = value }
                    }
                } label: {
                    HStack {
                        Label(
                            equipmentFilter.map { t($0.localizationKey) } ?? t("training.routines.filter.all_equipment"),
                            systemImage: "slider.horizontal.3"
                        )
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption.bold())
                    }
                    .foregroundStyle(.primary)
                }
            }
            if store.routines.isEmpty {
                HyseEmptyState(icon: "list.bullet.rectangle", title: t("training.routines.empty.title"), message: t("training.routines.empty.message"), actionTitle: t("training.routine.create"), action: { showingBuilder = true })
            } else if filteredRoutines.isEmpty {
                HyseEmptyState(icon: "magnifyingglass", title: t("training.routines.no_results"), message: t("training.routines.no_results_message"))
            } else {
                ForEach(groupedRoutines, id: \.0) { folder, routines in
                    Section(folder) {
                        ForEach(routines) { routine in
                            HStack(spacing: HyseSpacing.medium) {
                                NavigationLink {
                                    RoutineDetailView(store: store, routineID: routine.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(routine.name).font(.headline).foregroundStyle(.primary)
                                        HStack(spacing: 8) {
                                            Text(t("training.routine.exercise_count", routine.exercises.count))
                                            if let weekday = routine.plannedWeekday { Text(t("training.routine.weekday.\(weekday)")) }
                                        }.font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Menu {
                                    Button(t("training.routine.start")) { _ = store.start(routine: routine) }
                                    Menu {
                                        Button(t("training.routine.no_planned_day")) { moveRoutine(routine, to: nil) }
                                        ForEach(1...7, id: \.self) { weekday in
                                            Button(t("training.routine.weekday.\(weekday)")) { moveRoutine(routine, to: weekday) }
                                        }
                                    } label: {
                                        Label(t("training.routine.move_day"), systemImage: "calendar")
                                    }
                                    Button(t("training.routine.edit")) { editingRoutine = routine }
                                    Button(t("training.routine.duplicate")) { store.duplicateRoutine(routine) }
                                    Button(t("training.routine.delete"), role: .destructive) { deletingRoutine = routine }
                                } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                            }
                        }
                    }
                }
            }
        }
        .hyseForm()
        .navigationTitle(t("training.routines"))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.hasResolvedPersistenceScope, let workout = store.activeWorkout {
                ActiveWorkoutBar(
                    workout: workout,
                    discard: { store.discardActiveWorkout() },
                    open: {
                        openedActiveWorkoutFromBar = true
                        showingActiveWorkout = true
                    }
                )
                .padding(.top, HyseSpacing.small)
                .padding(.bottom, HyseSpacing.medium)
            }
        }
        .toolbar {
            Button { presentRoutineBuilder() } label: {
                Image(systemName: "plus")
                    .overlay(alignment: .topTrailing) {
                        if routineCreationRequiresPremium {
                            PremiumFeatureIcon(area: .training).offset(x: 9, y: -8)
                        }
                    }
            }
            .accessibilityLabel(t("training.routine.create"))
        }
        .sheet(isPresented: $showingBuilder) { RoutineBuilderView(store: store) }
        .fullScreenCover(isPresented: $showingActiveWorkout, onDismiss: { openedActiveWorkoutFromBar = false }) {
            ActiveWorkoutView(store: store, animateToLatestCompletedExercise: openedActiveWorkoutFromBar)
        }
        .sheet(isPresented: $showingTrainingPremium) { PremiumPaywallView(requestedArea: .training) }
        .sheet(item: $editingRoutine) { RoutineBuilderView(store: store, routine: $0) }
        .alert(t("training.routine.delete_confirm_title"), isPresented: Binding(get: { deletingRoutine != nil }, set: { if !$0 { deletingRoutine = nil } })) {
            Button(t("app_tabs.cancel"), role: .cancel) { deletingRoutine = nil }
            Button(t("training.routine.delete"), role: .destructive) { if let deletingRoutine { store.deleteRoutine(deletingRoutine.id) }; deletingRoutine = nil }
        } message: { Text(t("training.routine.delete_confirm_message")) }
    }

    private func presentRoutineBuilder() {
        if routineCreationRequiresPremium {
            showingTrainingPremium = true
        } else {
            showingBuilder = true
        }
    }

    private func moveRoutine(_ routine: WorkoutRoutine, to weekday: Int?) {
        var updated = routine
        updated.plannedWeekday = weekday
        _ = store.saveRoutine(updated)
    }
}

struct WeeklyRoutinePlanView: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var store: TrainingStore
    let startRoutine: (WorkoutRoutine) -> Void
    @State private var weekOffset = 0
    @State private var selectedDay: Date?

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    private var calendar: Calendar { .autoupdatingCurrent }

    private var weekDays: [Date] {
        let reference = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date()
        let start = calendar.dateInterval(of: .weekOfYear, for: reference)?.start ?? calendar.startOfDay(for: reference)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekTitle: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        let format = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(language.locale)
        return "\(first.formatted(format)) – \(last.formatted(format))"
    }

    private var displayedDay: Date {
        if let selectedDay, let matchingDay = weekDays.first(where: { calendar.isDate($0, inSameDayAs: selectedDay) }) {
            return matchingDay
        }
        return weekDays.first(where: { calendar.isDateInToday($0) }) ?? weekDays[0]
    }

    private var displayedRoutines: [WorkoutRoutine] {
        store.routines(plannedFor: displayedDay)
    }

    private var displayedWorkouts: [WorkoutLog] {
        store.workouts(on: displayedDay)
    }

    private func hasTraining(on day: Date) -> Bool {
        !store.routines(plannedFor: day).isEmpty || !store.workouts(on: day).isEmpty
    }

    private func selectDay(_ day: Date) {
        withAnimation(HyseMotion.quick) { selectedDay = day }
    }

    private func scheduleWeekdayLabel(for day: Date) -> String {
        day.formatted(.dateTime.weekday(.narrow).locale(language.locale)).uppercased()
    }

    private func scheduleDayNumberLabel(for day: Date) -> String {
        day.formatted(.dateTime.day().locale(language.locale))
    }

    private func scheduleAccessibilityLabel(for day: Date) -> String {
        day.formatted(.dateTime.weekday(.wide).day().month().locale(language.locale))
    }

    private func scheduleDayButton(for day: Date) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: displayedDay)
        let trainingDay = hasTraining(on: day)
        let weekdayLabel = scheduleWeekdayLabel(for: day)
        let dayNumberLabel = scheduleDayNumberLabel(for: day)
        let accessibilityLabel = scheduleAccessibilityLabel(for: day)
        let dayBackground: Color = selected
            ? HyseColor.accent.opacity(0.13)
            : HyseColor.elevatedSurface
        let dayBorderColor: Color = selected
            ? HyseColor.accent.opacity(0.55)
            : HyseColor.border
        let dayBorderWidth: CGFloat = selected ? 1.2 : 0.8

        return Button { selectDay(day) } label: {
            VStack(spacing: HyseSpacing.xSmall) {
                Text(weekdayLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(selected ? HyseColor.accent : .secondary)
                Text(dayNumberLabel)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(selected ? HyseColor.accent : .primary)
                HStack(spacing: 4) {
                    Image(systemName: trainingDay ? "checkmark.circle.fill" : "circle")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(trainingDay ? HyseColor.accent : HyseColor.border)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 82)
            .padding(.vertical, HyseSpacing.small)
            .background(
                dayBackground,
                in: RoundedRectangle(cornerRadius: HyseRadius.small, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HyseRadius.small, style: .continuous)
                    .stroke(dayBorderColor, lineWidth: dayBorderWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(trainingDay ? t("training.schedule.training_day") : t("training.schedule.no_training"))
    }

    var body: some View {
        HyseCard(accent: HyseColor.accent) {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                HStack {
                    Label(t("training.schedule.title"), systemImage: "calendar")
                        .font(.title3.bold())
                    Spacer()
                    Button {
                        weekOffset -= 1
                        selectedDay = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("training.schedule.previous_week"))

                    Button {
                        weekOffset += 1
                        selectedDay = nil
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("training.schedule.next_week"))
                }

                Text(weekTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: HyseSpacing.xSmall) {
                    ForEach(weekDays, id: \.self) { day in
                        scheduleDayButton(for: day)
                    }
                }

                VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                    HStack(alignment: .top, spacing: HyseSpacing.medium) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(displayedDay.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(language.locale)))
                                .font(.headline)
                            Text(displayedRoutines.isEmpty
                                 ? (displayedWorkouts.isEmpty ? t("training.schedule.no_training") : t("training.schedule.completed"))
                                 : t("training.schedule.training_day"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(displayedRoutines.isEmpty && displayedWorkouts.isEmpty ? .secondary : HyseColor.accent)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: displayedRoutines.isEmpty && displayedWorkouts.isEmpty ? "moon.zzz" : "figure.strengthtraining.traditional")
                            .font(.title3)
                            .foregroundStyle(displayedRoutines.isEmpty && displayedWorkouts.isEmpty ? .secondary : HyseColor.accent)
                    }

                    if displayedRoutines.isEmpty {
                        Label(
                            displayedWorkouts.isEmpty ? t("training.schedule.no_routine") : t("training.schedule.completed"),
                            systemImage: displayedWorkouts.isEmpty ? "calendar.badge.minus" : "checkmark.circle.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(displayedWorkouts.isEmpty ? .secondary : HyseColor.success)
                    } else {
                        VStack(alignment: .leading, spacing: HyseSpacing.small) {
                            ForEach(displayedRoutines) { routine in
                                HStack(spacing: HyseSpacing.small) {
                                    NavigationLink {
                                        RoutineDetailView(store: store, routineID: routine.id)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(routine.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text(t("training.routine.exercise_count", routine.exercises.count))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)

                                    Button { startRoutine(routine) } label: {
                                        Image(systemName: "play.fill")
                                            .font(.caption.weight(.bold))
                                            .frame(width: 32, height: 32)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(HyseColor.accent)
                                    .disabled(store.activeWorkout != nil)
                                    .accessibilityLabel(t("training.routine.start"))
                                }
                                .padding(.horizontal, HyseSpacing.small)
                                .padding(.vertical, 7)
                                .background(HyseColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: HyseRadius.small, style: .continuous))
                            }
                        }
                    }
                }
                .padding(HyseSpacing.medium)
                .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous)
                        .stroke(HyseColor.border)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("training.schedule.title"))
    }
}

struct RoutineBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var premium: PremiumAccessStore
    @ObservedObject var store: TrainingStore
    @State private var draft: WorkoutRoutine
    @State private var isCreatingTrainingPlan: Bool
    @State private var showingExercisePicker = false
    @State private var showingExerciseOrder = false
    @State private var draggedExerciseID: UUID?
    @State private var reorderTargetExerciseID: UUID?
    @State private var draggedExerciseScreenY: CGFloat?
    @State private var exerciseNameScreenPositions: [UUID: CGFloat] = [:]
    @State private var showingTrainingPremium = false
    @State private var addedExerciseNotice: WorkoutExerciseAdditionNotice?
    @State private var pendingProgressGoals: [UUID: ExerciseProgressGoal]
    @State private var changedProgressGoalIDs = Set<UUID>()
    @Namespace private var exerciseOrderAnimation

    init(store: TrainingStore, routine: WorkoutRoutine? = nil) {
        self.store = store
        _draft = State(initialValue: routine ?? WorkoutRoutine(name: ""))
        _isCreatingTrainingPlan = State(initialValue: routine == nil && !store.routines.contains { !$0.folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        _pendingProgressGoals = State(initialValue: store.progressGoals)
    }

    private var existingTrainingPlans: [String] {
        Array(Set(store.routines.map { $0.folder.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var isCreatingRoutine: Bool {
        !store.routines.contains(where: { $0.id == draft.id })
    }

    private var routineSaveRequiresPremium: Bool {
        isCreatingRoutine && !premium.hasTraining && store.routines.count >= TrainingStore.freeRoutineLimit
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                routineBuilderHeader
                ZStack {
                    RoutineExerciseReorderList(
                        routine: $draft,
                        namespace: exerciseOrderAnimation,
                        isReordering: showingExerciseOrder,
                        draggedExerciseID: $draggedExerciseID,
                        reorderTargetExerciseID: $reorderTargetExerciseID,
                        draggedExerciseScreenY: draggedExerciseScreenY,
                        onDone: {
                            guard showingExerciseOrder else { return }
                            ExerciseReorderFeedback.dropped()
                            draggedExerciseID = nil
                            reorderTargetExerciseID = nil
                            draggedExerciseScreenY = nil
                            withAnimation(HyseMotion.quick) { showingExerciseOrder = false }
                        }
                    )
                    .opacity(showingExerciseOrder ? 1 : 0)
                    .allowsHitTesting(showingExerciseOrder)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            routineDetails
                            if draft.exercises.isEmpty {
                                HyseEmptyState(
                                    icon: "dumbbell",
                                    title: language.text("training.routine.empty_plan_title"),
                                    message: language.text("training.routine.empty_plan_message")
                                )
                                .padding(.horizontal, HyseSpacing.page)
                                .padding(.vertical, HyseSpacing.xLarge)
                            } else {
                                ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { index, item in
                                    RoutinePlanExerciseCard(
                                        item: exerciseBinding(for: item),
                                        canMoveUp: index > 0,
                                        canMoveDown: index < draft.exercises.count - 1,
                                        moveUp: { moveExercise(from: index, offset: -1) },
                                        moveDown: { moveExercise(from: index, offset: 1) },
                                        duplicate: { duplicateExercise(item.id) },
                                        remove: { draft.exercises.removeAll { $0.id == item.id } },
                                        progressGoal: pendingProgressGoals[item.exercise.id],
                                        setProgressGoal: { goal in
                                            pendingProgressGoals[item.exercise.id] = goal
                                            changedProgressGoalIDs.insert(item.exercise.id)
                                        },
                                        beginReorder: {
                                            draggedExerciseID = item.id
                                            reorderTargetExerciseID = nil
                                            draggedExerciseScreenY = exerciseNameScreenPositions[item.id]
                                            ExerciseReorderFeedback.pickedUp()
                                            withAnimation(HyseMotion.standard) { showingExerciseOrder = true }
                                            return NSItemProvider(object: item.id.uuidString as NSString)
                                        },
                                        namespace: exerciseOrderAnimation,
                                        isReordering: showingExerciseOrder
                                    )
                                }
                            }
                            Button { showingExercisePicker = true } label: {
                                Label(language.text("training.exercise.add"), systemImage: "plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(HysePrimaryButtonStyle())
                            .padding(.horizontal, HyseSpacing.page)
                            .padding(.top, HyseSpacing.large)
                            .padding(.bottom, HyseSpacing.xLarge)
                        }
                        .onPreferenceChange(ExerciseNamePositionPreferenceKey.self) { exerciseNameScreenPositions = $0 }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .opacity(showingExerciseOrder ? 0 : 1)
                    .allowsHitTesting(!showingExerciseOrder)
                }
            }
            .background(HyseBackdrop())
            .overlay(alignment: .bottom) {
                if let addedExerciseNotice {
                    WorkoutExerciseAddedToast(text: addedExerciseNotice.text)
                        .padding(.horizontal, HyseSpacing.page)
                        .padding(.bottom, HyseSpacing.large)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExerciseLibraryView(store: store, selectionMode: true) { selected in
                withAnimation(.easeOut(duration: 0.18)) {
                    draft.exercises.append(contentsOf: selected.map { RoutineExercise(exercise: $0) })
                    addedExerciseNotice = WorkoutExerciseAdditionNotice(
                        text: selected.count == 1
                            ? language.text("training.exercise.added", [selected[0].displayName(isGerman: language.isGerman)])
                            : language.text("training.exercise.add_count", [selected.count])
                    )
                }
            }
        }
        .sheet(isPresented: $showingTrainingPremium) { PremiumPaywallView(requestedArea: .training) }
        .task(id: addedExerciseNotice?.id) {
            guard addedExerciseNotice != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { addedExerciseNotice = nil }
        }
    }

    private func exerciseBinding(for exercise: RoutineExercise) -> Binding<RoutineExercise> {
        Binding(
            get: { draft.exercises.first(where: { $0.id == exercise.id }) ?? exercise },
            set: { updated in
                if let index = draft.exercises.firstIndex(where: { $0.id == exercise.id }) {
                    draft.exercises[index] = updated
                }
            }
        )
    }

    private var routineDetails: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            Text(language.text("training.routine.details"))
                .font(.title3.bold())
            TextField(language.text("training.routine.description"), text: $draft.details, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .font(.subheadline)
            Divider()
            trainingPlanField
            Divider()
            HStack(spacing: HyseSpacing.medium) {
                Image(systemName: "calendar")
                    .foregroundStyle(HyseColor.accent)
                    .frame(width: 24)
                Picker(language.text("training.routine.planned_day"), selection: Binding(
                    get: { draft.plannedWeekday ?? 0 },
                    set: { draft.plannedWeekday = $0 == 0 ? nil : $0 }
                )) {
                    Text(language.text("training.routine.no_planned_day")).tag(0)
                    ForEach(1...7, id: \.self) { Text(language.text("training.routine.weekday.\($0)")).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(HyseSpacing.page)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyseColor.surface)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var routineBuilderHeader: some View {
        VStack(spacing: HyseSpacing.medium) {
            HStack(spacing: HyseSpacing.medium) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.headline.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .background(HyseColor.elevatedSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.text("app_tabs.cancel"))

                TextField(language.text("training.routine.name"), text: $draft.name)
                    .font(.headline.weight(.bold))
                    .textFieldStyle(.plain)
                    .lineLimit(1)

                Button { saveDraft() } label: {
                    HStack(spacing: 5) {
                        Text(language.text("training.routine.save"))
                        if routineSaveRequiresPremium {
                            PremiumFeatureIcon(area: .training)
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 42)
                    .background(HyseColor.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)
            }

            HStack(spacing: 0) {
                routineMetric(
                    language.text("training.exercises"),
                    "\(draft.exercises.count)"
                )
                routineMetric(
                    language.text("training.monthly_report.metric.sets"),
                    "\(draft.exercises.reduce(0) { $0 + $1.sets.count })"
                )
                routineMetric(
                    language.text("training.routine.planned_day"),
                    plannedDaySummary
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, HyseSpacing.page)
        .padding(.top, HyseSpacing.small)
        .padding(.bottom, HyseSpacing.large)
        .background(HyseColor.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(HyseColor.border).frame(height: 1) }
    }

    private var plannedDaySummary: String {
        guard let weekday = draft.plannedWeekday else { return "–" }
        return language.text("training.routine.weekday.\(weekday)")
    }

    private func routineMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(HyseColor.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveDraft() {
        guard canSave else { return }
        if store.saveRoutine(draft) {
            let retainedExerciseIDs = Set(draft.exercises.map { $0.exercise.id })
            for exerciseID in changedProgressGoalIDs where retainedExerciseIDs.contains(exerciseID) {
                store.setProgressGoal(pendingProgressGoals[exerciseID], for: exerciseID)
            }
            dismiss()
        } else {
            showingTrainingPremium = true
        }
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.exercises.isEmpty
            && (!isCreatingTrainingPlan || !draft.folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func moveExercise(from index: Int, offset: Int) {
        let destination = index + offset
        guard draft.exercises.indices.contains(index), draft.exercises.indices.contains(destination) else { return }
        let value = draft.exercises.remove(at: index)
        draft.exercises.insert(value, at: destination)
    }

    private func duplicateExercise(_ id: UUID) {
        guard let index = draft.exercises.firstIndex(where: { $0.id == id }) else { return }
        var copy = draft.exercises[index]
        copy.id = UUID()
        copy.sets = copy.sets.map { set in var value = set; value.id = UUID(); return value }
        draft.exercises.insert(copy, at: index + 1)
    }

    private var trainingPlanField: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            Text(language.text("training.routine.folder"))
                .font(.subheadline.weight(.semibold))
            Menu {
                Button(language.text("training.routine.no_training_plan")) {
                    isCreatingTrainingPlan = false
                    draft.folder = ""
                }
                ForEach(existingTrainingPlans, id: \.self) { name in
                    Button(name) {
                        isCreatingTrainingPlan = false
                        draft.folder = name
                    }
                }
                Button(language.text("training.routine.create_training_plan"), systemImage: "plus") {
                    isCreatingTrainingPlan = true
                    draft.folder = ""
                }
            } label: {
                HStack(spacing: HyseSpacing.medium) {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(HyseColor.accent)
                        .frame(width: 24)
                    Text(isCreatingTrainingPlan
                         ? language.text("training.routine.create_training_plan")
                         : (draft.folder.isEmpty ? language.text("training.routine.no_training_plan") : draft.folder))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            if isCreatingTrainingPlan {
                TextField(language.text("training.routine.training_plan_name_placeholder"), text: $draft.folder)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .padding(.leading, 36)
            }
        }
    }

}

private struct RoutinePlanExerciseCard: View {
    @EnvironmentObject private var language: LanguageStore
    @AppStorage("trainingWeightUnit_v1") private var trainingWeightUnitRaw = TrainingWeightUnit.kilograms.rawValue
    @Binding var item: RoutineExercise
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let duplicate: () -> Void
    let remove: () -> Void
    let progressGoal: ExerciseProgressGoal?
    let setProgressGoal: (ExerciseProgressGoal?) -> Void
    let beginReorder: () -> NSItemProvider
    let namespace: Namespace.ID
    let isReordering: Bool
    @State private var showingActions = false
    @State private var showingProgressGoal = false
    @State private var openProgressGoalAfterActionsDismiss = false

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            HStack(spacing: HyseSpacing.medium) {
                ExerciseMovementVisual(exercise: item.exercise, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.exercise.displayName(isGerman: language.isGerman))
                        .font(.headline)
                        .foregroundStyle(HyseColor.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .matchedGeometryEffect(id: "routine-name-\(item.id)", in: namespace, anchor: .leading, isSource: !isReordering)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ExerciseNamePositionPreferenceKey.self,
                                    value: [item.id: geometry.frame(in: .global).midY]
                                )
                            }
                        }
                    Text(item.exercise.primaryMuscles.map { t("training.muscle.\($0)") }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onDrag(beginReorder)
                .accessibilityHint(t("training.routine.reorder_hint"))

                Button { showingActions = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .background(HyseColor.elevatedSurface, in: Circle())
                }
                .buttonStyle(.plain)
            }

            TextField(t("training.exercise.notes"), text: $item.notes, axis: .vertical)
                .fixedSize(horizontal: false, vertical: true)
                .font(.subheadline)
                .textFieldStyle(.plain)

            Menu {
                ForEach([0, 30, 60, 90, 120, 180, 240, 300, 600], id: \.self) { seconds in
                    Button(t("training.exercise.rest_seconds", seconds)) { item.restSeconds = seconds }
                }
            } label: {
                Label(t("training.exercise.rest_seconds", item.restSeconds), systemImage: "stopwatch")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HyseColor.accent)
            }

            VStack(spacing: HyseSpacing.small) {
                HStack(spacing: 8) {
                    Text(t("training.routine.set_column"))
                        .frame(width: 42)
                    targetHeadings
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                ForEach(Array(item.sets.enumerated()), id: \.element.id) { setIndex, set in
                    RoutinePlannedSetRow(
                        set: $item.sets[setIndex],
                        exerciseType: item.exercise.type,
                        number: setIndex + 1,
                        duplicate: { duplicateSet(set.id) },
                        remove: { item.sets.removeAll { $0.id == set.id } }
                    )
                }
            }

            Button { addSet() } label: {
                Label(t("training.set.add"), systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border))
            }
            .buttonStyle(.plain)
            .disabled(item.sets.count >= 20)
        }
        .padding(.horizontal, HyseSpacing.page)
        .padding(.vertical, HyseSpacing.large)
        .overlay(alignment: .bottom) { Divider() }
        .sheet(isPresented: $showingActions, onDismiss: {
            guard openProgressGoalAfterActionsDismiss else { return }
            openProgressGoalAfterActionsDismiss = false
            showingProgressGoal = true
        }) {
            WorkoutExerciseActionsSheet(
                exerciseName: item.exercise.displayName(isGerman: language.isGerman),
                isUnilateral: Binding(
                    get: { TrainingSetStatistics.isUnilateral(item.exercise) },
                    set: { item.exercise.isUnilateral = $0 }
                ),
                supportsProgressGoal: supportsProgressGoal,
                progressGoal: progressGoal,
                progressSuggestion: nil,
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                editProgressGoal: { openProgressGoalAfterActionsDismiss = true },
                moveUp: moveUp,
                moveDown: moveDown,
                duplicate: duplicate,
                remove: remove
            )
            .presentationDetents([.height(supportsProgressGoal ? 455 : 385)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(HyseColor.background)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showingProgressGoal) {
            ExerciseProgressGoalEditor(
                goal: progressGoal,
                weightUnit: TrainingWeightUnit(rawValue: trainingWeightUnitRaw) ?? .kilograms,
                usesWeight: item.exercise.type != .repsOnly,
                save: { setProgressGoal($0) },
                remove: { setProgressGoal(nil) }
            )
        }
    }

    private var supportsProgressGoal: Bool {
        item.exercise.type == .weightReps || item.exercise.type == .bodyweight || item.exercise.type == .repsOnly
    }

    @ViewBuilder private var targetHeadings: some View {
        switch item.exercise.type {
        case .weightReps:
            targetHeading(t("training.weight"))
            targetHeading(t("training.reps"))
        case .bodyweight:
            targetHeading(t("training.reps"))
            targetHeading(t("training.added_weight"))
        case .duration:
            targetHeading(t("training.duration"))
        case .distanceDuration:
            targetHeading(t("training.distance"))
            targetHeading(t("training.duration"))
        case .repsOnly:
            targetHeading(t("training.reps"))
        }
    }

    private func targetHeading(_ value: String) -> some View {
        Text(value).lineLimit(1).minimumScaleFactor(0.65).frame(maxWidth: .infinity)
    }

    private func addSet() {
        guard item.sets.count < 20 else { return }
        let last = item.sets.last
        var next = last.flatMap { hasEnteredValues($0) ? $0 : nil }
            ?? TrainingSetLog(type: last?.type ?? .normal)
        next.id = UUID()
        next.completed = false
        next.completedAt = nil
        next.personalRecordFlags = []
        item.sets.append(next)
    }

    private func duplicateSet(_ id: UUID) {
        guard item.sets.count < 20, let index = item.sets.firstIndex(where: { $0.id == id }) else { return }
        var copy = item.sets[index]
        copy.id = UUID()
        item.sets.insert(copy, at: index + 1)
    }

    private func hasEnteredValues(_ set: TrainingSetLog) -> Bool {
        set.weightKilograms != 0 || set.reps != 0 || set.durationSeconds != 0
            || set.distanceMeters != 0 || set.assistedKilograms != 0
    }
}

private struct RoutinePlannedSetRow: View {
    @EnvironmentObject private var language: LanguageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("trainingWeightUnit_v1") private var trainingWeightUnitRaw = TrainingWeightUnit.kilograms.rawValue
    @AppStorage("trainingDistanceUnit_v1") private var trainingDistanceUnitRaw = TrainingDistanceUnit.kilometers.rawValue
    @Binding var set: TrainingSetLog
    let exerciseType: TrainingExerciseType
    let number: Int
    let duplicate: () -> Void
    let remove: () -> Void
    @State private var showingSetTypePicker = false
    @State private var removeAfterPickerDismiss = false
    private var weightUnit: TrainingWeightUnit { TrainingWeightUnit(rawValue: trainingWeightUnitRaw) ?? .kilograms }
    private var distanceUnit: TrainingDistanceUnit { TrainingDistanceUnit(rawValue: trainingDistanceUnitRaw) ?? .kilometers }
    private var displayedWeight: Binding<Double> {
        Binding(get: { weightUnit.display(set.weightKilograms) }, set: { set.weightKilograms = weightUnit.kilograms($0) })
    }
    private var displayedDistance: Binding<Double> {
        Binding(get: { distanceUnit.display(set.distanceMeters) }, set: { set.distanceMeters = distanceUnit.meters($0) })
    }
    private var badgeTitle: String {
        switch set.type {
        case .normal: "\(number)"
        case .warmup: "W"
        case .dropSet: "D"
        case .failure: "F"
        case .superset: "S"
        }
    }
    private var badgeTint: Color {
        switch set.type {
        case .normal: .primary
        case .warmup: HyseColor.warning
        case .dropSet: HyseColor.information
        case .failure: HyseColor.danger
        case .superset: HyseColor.accent
        }
    }

    var body: some View {
        SetDeleteInteraction(
            content: rowContent.environmentObject(language),
            rowHeight: 46,
            deleteLabel: language.text("training.set.delete"),
            deleteActionTitle: language.text("settings.delete"),
            reduceMotion: reduceMotion,
            deletionRequested: false,
            onDelete: remove
        )
        .sheet(isPresented: $showingSetTypePicker, onDismiss: {
            guard removeAfterPickerDismiss else { return }
            removeAfterPickerDismiss = false
            remove()
        }) {
            TrainingSetTypePicker(
                number: number,
                selection: set.type,
                onSelect: { set.type = $0 },
                onDuplicate: duplicate,
                onDelete: { removeAfterPickerDismiss = true }
            )
            .presentationDetents([.height(560), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(HyseColor.background)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Button { showingSetTypePicker = true } label: {
                Text(badgeTitle)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(badgeTint)
                    .frame(width: 42, height: 46)
                    .background(badgeTint.opacity(0.14), in: RoundedRectangle(cornerRadius: HyseRadius.small, style: .continuous))
            }
            .accessibilityLabel("\(number), \(language.text(set.type.localizationKey))")
            targetInputs
        }
    }

    @ViewBuilder private var targetInputs: some View {
        switch exerciseType {
        case .weightReps:
            decimalField(language.text("training.weight"), value: displayedWeight, unit: weightUnit.rawValue)
            integerField(language.text("training.reps"), value: $set.reps)
        case .bodyweight:
            integerField(language.text("training.reps"), value: $set.reps)
            decimalField(language.text("training.added_weight"), value: displayedWeight, unit: weightUnit.rawValue)
        case .duration:
            durationField
        case .distanceDuration:
            decimalField(language.text("training.distance"), value: displayedDistance, unit: distanceUnit.rawValue)
            durationField
        case .repsOnly:
            integerField(language.text("training.reps"), value: $set.reps)
        }
    }

    private func decimalField(_ title: String, value: Binding<Double>, unit: String) -> some View {
        HStack(spacing: 3) {
            TextField(title, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border))
    }

    private func integerField(_ title: String, value: Binding<Int>) -> some View {
        TextField(title, value: value, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border))
    }

    private var durationField: some View {
        DurationInputField(
            seconds: $set.durationSeconds,
            label: language.text("training.duration"),
            disabled: false
        )
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border))
    }
}

/// Mirrors the focused order view used during an active workout. Keeping the
/// rows compact makes long-pressing a name and moving it several positions
/// practical, even when the routine's full exercise cards are tall.
private struct RoutineExerciseReorderList: View {
    @EnvironmentObject private var language: LanguageStore
    @Binding var routine: WorkoutRoutine
    let namespace: Namespace.ID
    let isReordering: Bool
    @Binding var draggedExerciseID: UUID?
    @Binding var reorderTargetExerciseID: UUID?
    let draggedExerciseScreenY: CGFloat?
    let onDone: () -> Void

    private let rowHeight: CGFloat = 66
    @State private var anchoredExerciseIndex: Int?
    @State private var scrollToTopRequest = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: HyseSpacing.small) {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .foregroundStyle(HyseColor.accent)
                Text(language.text("training.routine.reorder_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, HyseSpacing.page)
            .padding(.vertical, HyseSpacing.medium)
            .background(HyseColor.surface.opacity(0.88))
            .overlay(alignment: .bottom) { Rectangle().fill(HyseColor.border).frame(height: 1) }

            Label(language.text("training.routine.move_to_top"), systemImage: "arrow.up.to.line")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HyseColor.accent)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(HyseColor.accent.opacity(0.09))
                .contentShape(Rectangle())
                .onDrop(of: [.text], delegate: RoutineExerciseTopDropDelegate(
                    routine: $routine,
                    draggedExerciseID: $draggedExerciseID,
                    onMoveToTop: { scrollToTopRequest += 1 },
                    onDropCompleted: onDone
                ))

            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            Color.clear
                                .frame(height: topAnchoringSpacer(in: viewport))
                            ForEach(routine.exercises) { item in
                                reorderRow(item)
                                    .id(item.id)
                            }
                            Color.clear
                                .frame(height: bottomAnchoringSpacer(in: viewport))
                        }
                        .padding(.vertical, HyseSpacing.small)
                    }
                    .onChange(of: isReordering) { _, isReordering in
                        guard isReordering else {
                            anchoredExerciseIndex = nil
                            return
                        }
                        anchoredExerciseIndex = draggedExerciseID.flatMap { id in
                            routine.exercises.firstIndex(where: { $0.id == id })
                        }
                        alignDraggedExercise(proxy: proxy, viewport: viewport)
                    }
                    .onChange(of: draggedExerciseID) { _, id in
                        guard isReordering, let id else {
                            anchoredExerciseIndex = nil
                            return
                        }
                        if anchoredExerciseIndex == nil {
                            anchoredExerciseIndex = routine.exercises.firstIndex(where: { $0.id == id })
                        }
                        alignDraggedExercise(proxy: proxy, viewport: viewport)
                    }
                    .onChange(of: scrollToTopRequest) { _, _ in
                        guard let firstID = routine.exercises.first?.id else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(firstID, anchor: .top)
                        }
                    }
                }
            }
        }
        .onDrop(
            of: [.text],
            delegate: ExerciseReorderCompletionDropDelegate(onDropCompleted: onDone)
        )
    }

    private func reorderRow(_ item: RoutineExercise) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            ExerciseMovementVisual(exercise: item.exercise, height: 34)
                .frame(width: 42, height: 42)
                .background(HyseColor.accent.opacity(0.12), in: Circle())
                .clipShape(Circle())

            Text(item.exercise.displayName(isGerman: language.isGerman))
                .font(.body.weight(.semibold))
                .foregroundStyle(draggedExerciseID == item.id ? HyseColor.accent.opacity(0.55) : Color.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .matchedGeometryEffect(id: "routine-name-\(item.id)", in: namespace, anchor: .leading, isSource: isReordering)

            Image(systemName: "line.3.horizontal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
        .padding(.horizontal, HyseSpacing.page)
        .contentShape(Rectangle())
        .onDrag { dragProvider(for: item.id) }
        .accessibilityHint(language.text("training.routine.reorder_hint"))
        .onDrop(of: [.text], delegate: dropDelegate(for: item.id))
        .background(rowHighlight(for: item.id))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HyseColor.border.opacity(0.68))
                .frame(height: 1)
                .padding(.horizontal, HyseSpacing.page)
        }
    }

    private func dragProvider(for id: UUID) -> NSItemProvider {
        draggedExerciseID = id
        reorderTargetExerciseID = nil
        ExerciseReorderFeedback.pickedUp()
        return NSItemProvider(object: id.uuidString as NSString)
    }

    private func dropDelegate(for id: UUID) -> RoutineExerciseDropDelegate {
        RoutineExerciseDropDelegate(
            targetID: id,
            routine: $routine,
            draggedExerciseID: $draggedExerciseID,
            reorderTargetExerciseID: $reorderTargetExerciseID,
            onDropCompleted: onDone
        )
    }

    private func alignDraggedExercise(proxy: ScrollViewProxy, viewport: GeometryProxy) {
        guard isReordering,
              let id = draggedExerciseID,
              let screenY = draggedExerciseScreenY,
              viewport.size.height > 0 else { return }

        let frame = viewport.frame(in: .global)
        let verticalAnchor = min(max((screenY - frame.minY - rowHeight / 2) / max(frame.height - rowHeight, 1), 0), 1)
        DispatchQueue.main.async {
            guard isReordering, draggedExerciseID == id else { return }
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                proxy.scrollTo(id, anchor: UnitPoint(x: 0, y: verticalAnchor))
            }
        }
    }

    @ViewBuilder
    private func rowHighlight(for exerciseID: UUID) -> some View {
        if draggedExerciseID == exerciseID {
            HyseColor.accent.opacity(0.08)
        } else if reorderTargetExerciseID == exerciseID {
            HyseColor.accent.opacity(0.16)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(HyseColor.accent)
                        .frame(height: 3)
                        .padding(.horizontal, HyseSpacing.page)
                }
        } else {
            Color.clear
        }
    }

    private func topAnchoringSpacer(in viewport: GeometryProxy) -> CGFloat {
        guard isReordering,
              let screenY = draggedExerciseScreenY,
              let index = anchoredExerciseIndex else { return 0 }

        let desiredY = screenY - viewport.frame(in: .global).minY
        let rowCenterBeforeSpacer = HyseSpacing.small + CGFloat(index) * rowHeight + rowHeight / 2
        return max(0, desiredY - rowCenterBeforeSpacer)
    }

    private func bottomAnchoringSpacer(in viewport: GeometryProxy) -> CGFloat {
        guard isReordering,
              let screenY = draggedExerciseScreenY,
              let index = anchoredExerciseIndex else { return 0 }

        let desiredY = screenY - viewport.frame(in: .global).minY
        let topSpacer = topAnchoringSpacer(in: viewport)
        let sourceCenter = topSpacer + HyseSpacing.small + CGFloat(index) * rowHeight + rowHeight / 2
        let requiredScrollOffset = max(0, sourceCenter - desiredY)
        let contentHeight = topSpacer + HyseSpacing.small * 2 + CGFloat(routine.exercises.count) * rowHeight
        return max(0, viewport.size.height + requiredScrollOffset - contentHeight)
    }
}

/// Provides a reachable first position even when the first row starts above
/// the visible portion of the compact reorder list.
private struct RoutineExerciseTopDropDelegate: DropDelegate {
    @Binding var routine: WorkoutRoutine
    @Binding var draggedExerciseID: UUID?
    let onMoveToTop: () -> Void
    let onDropCompleted: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedExerciseID,
              let sourceIndex = routine.exercises.firstIndex(where: { $0.id == draggedID }) else { return }
        if sourceIndex > 0 {
            withAnimation(.easeInOut(duration: 0.2)) {
                let value = routine.exercises.remove(at: sourceIndex)
                routine.exercises.insert(value, at: 0)
            }
            ExerciseReorderFeedback.moved()
        }
        onMoveToTop()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onDropCompleted()
        return true
    }
}

/// Accepts a release in the gaps around routine rows.
private struct ExerciseReorderCompletionDropDelegate: DropDelegate {
    let onDropCompleted: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onDropCompleted()
        return true
    }
}

private struct RoutineExerciseDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var routine: WorkoutRoutine
    @Binding var draggedExerciseID: UUID?
    @Binding var reorderTargetExerciseID: UUID?
    let onDropCompleted: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedExerciseID,
              draggedID != targetID,
              let sourceIndex = routine.exercises.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = routine.exercises.firstIndex(where: { $0.id == targetID }) else { return }

        reorderTargetExerciseID = targetID
        withAnimation(.easeInOut(duration: 0.2)) {
            let value = routine.exercises.remove(at: sourceIndex)
            // Once the source is removed, inserting at targetIndex places a
            // downward drag after the hovered row and an upward drag before it.
            routine.exercises.insert(value, at: targetIndex)
        }
        ExerciseReorderFeedback.moved()
    }

    func dropExited(info: DropInfo) {
        if reorderTargetExerciseID == targetID {
            reorderTargetExerciseID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onDropCompleted()
        return true
    }
}
