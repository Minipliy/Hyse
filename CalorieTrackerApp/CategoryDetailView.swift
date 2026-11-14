import SwiftUI

private enum MealBulkAction: String, Identifiable {
    case copy, move
    var id: String { rawValue }
    var symbol: String { self == .copy ? "doc.on.doc" : "arrow.right" }
    var titleKey: String { self == .copy ? "meal_actions.copy" : "meal_actions.move" }
}

private enum MealTransferResult {
    case completed
    case premiumRequired
    case failed(String)
}

struct CategoryDetailView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var premium: PremiumAccessStore
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    let category: MealCategory
    @ObservedObject var calorieStore: CalorieStore
    @ObservedObject var foodStore: FoodStore
    @ObservedObject var recipeStore: RecipeStore
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var frequencyStore: FrequencyStore
    @ObservedObject var userSettings: UserSettingsStore
    let availableCalories: Double
    let selectedDate: Date
    let showsActiveWorkoutBar: Bool
    let onSelectionModeChanged: (Bool) -> Void

    @State private var showingAddEntry = false
    @State private var entryToEdit: CalorieEntry?
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var bulkAction: MealBulkAction?
    @State private var showingDeleteConfirmation = false
    @State private var showingNutritionPremium = false
    @State private var showNutritionPremiumAfterTransferDismiss = false
    @State private var deletedEntries: [CalorieEntry] = []
    @State private var deletionUndoID: UUID?
    @State private var deletionUndoExpiresAt: Date?

    private var categoryEntries: [CalorieEntry] { calorieStore.entries(for: selectedDate, categoryId: category.id) }

    var body: some View {
        List {
            Section(t("category_detail.nutrition_overview_1", category.localizedName)) {
                VStack(spacing: 12) {
                    HStack {
                        Text(t("ui.total_calories")).font(.headline)
                        Spacer()
                        Text("\(formatted(calorieStore.totalKcal(for: selectedDate, categoryId: category.id))) kcal").font(.title3.bold()).foregroundStyle(HyseColor.accent)
                    }
                    Divider()
                    nutrientRow(title: t("quick_entry.carbohydrates"), value: calorieStore.totalCarbs(for: selectedDate, categoryId: category.id))
                    nutrientRow(title: t("category_detail.protein"), value: calorieStore.totalProtein(for: selectedDate, categoryId: category.id))
                    nutrientRow(title: t("quick_entry.fat"), value: calorieStore.totalFat(for: selectedDate, categoryId: category.id))
                }.padding(.vertical, 4)
            }
            .hyseGlassListRows(accent: HyseColor.accent)
            if !selecting {
                Section {
                    Button { showingAddEntry = true } label: { Label(t("category_detail.add_food_1", category.localizedName), systemImage: "plus.circle.fill").font(.headline) }
                }
                .hyseGlassListRows(accent: HyseColor.accent)
            }
            Section {
                if categoryEntries.isEmpty { Text(t("category_detail.no_foods_logged_1_yet", category.localizedName)).foregroundStyle(.secondary) }
                else { ForEach(categoryEntries) { entry in entryRow(entry) } }
            } header: {
                HStack {
                    Text(t("ui.today_s_entries"))
                    Spacer()
                    if selecting {
                        Text(t("meal_actions.selected_count", selection.count))
                            .foregroundStyle(HyseColor.accent)
                    }
                }
            }
            .hyseGlassListRows()
        }
        .listStyle(.insetGrouped).hyseForm().navigationTitle(category.localizedName)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? t("add_entry.done") : t("meal_actions.select")) {
                    selecting.toggle()
                    if !selecting { selection.removeAll() }
                }
                    .disabled(categoryEntries.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if !deletedEntries.isEmpty {
                    HyseUndoNotice(
                        title: deletedEntries.count == 1
                            ? t("meal_actions.deleted_single")
                            : t("meal_actions.deleted_count", deletedEntries.count),
                        detail: deletedEntries.count == 1 ? deletedEntries.first?.name : nil,
                        actionTitle: t("meal_actions.undo"),
                        action: undoDeletion
                    )
                    .padding(.vertical, HyseSpacing.medium)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if selecting { bulkBar }
                if showsActiveWorkoutBar {
                    Color.clear
                        .frame(height: 68 + HyseSpacing.medium + HyseSpacing.small)
                        .accessibilityHidden(true)
                }
            }
            .animation(HyseMotion.quick, value: deletionUndoID)
        }
        .onAppear { onSelectionModeChanged(selecting) }
        .onChange(of: selecting) { _, value in onSelectionModeChanged(value) }
        .onDisappear { onSelectionModeChanged(false) }
        .sheet(isPresented: $showingAddEntry) {
            AddEntryView(foodStore: foodStore, recipeStore: recipeStore, categoryStore: categoryStore, frequencyStore: frequencyStore, userSettings: userSettings, calorieStore: calorieStore, availableCalories: availableCalories, category: category, entryDate: selectedDate)
        }
        .sheet(item: $entryToEdit) { entry in
            EditEntryView(
                calorieStore: calorieStore,
                categoryStore: categoryStore,
                userSettings: userSettings,
                availableCalories: availableCalories,
                entry: entry,
                recipe: recipe(for: entry),
                food: entry.foodItemId.flatMap { foodStore.food(id: $0) }
            )
        }
        .sheet(item: $bulkAction, onDismiss: {
            guard showNutritionPremiumAfterTransferDismiss else { return }
            showNutritionPremiumAfterTransferDismiss = false
            showingNutritionPremium = true
        }) { action in
            EntryTransferSheet(categories: categoryStore.categories, initialCategory: category, initialDate: selectedDate, count: selection.count, action: action) { target, date in
                guard premium.hasNutrition || !isFutureDate(date) else {
                    showNutritionPremiumAfterTransferDismiss = true
                    return .premiumRequired
                }
                if action == .copy {
                    let didCopy = calorieStore.copyEntries(ids: selection, to: target, date: date)
                    if !didCopy {
                        return .failed(calorieStore.lastFoodTrackingRestriction?.message(using: language) ?? t("add_entry.local_save_failed"))
                    }
                } else {
                    calorieStore.moveEntries(ids: selection, to: target, date: date)
                }
                selection.removeAll()
                selecting = false
                return .completed
            }.environmentObject(language)
        }
        .sheet(isPresented: $showingNutritionPremium) {
            PremiumPaywallView(requestedArea: .nutrition)
        }
        .confirmationDialog(t("meal_actions.delete_title", selection.count), isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button(t("settings.delete"), role: .destructive) { deleteSelection() }
            Button(t("app_tabs.cancel"), role: .cancel) {}
        } message: { Text(t("meal_actions.delete_message")) }
        .onChange(of: categoryEntries.map(\.id)) { _, ids in
            selection.formIntersection(Set(ids))
            if ids.isEmpty { selecting = false }
        }
        .task(id: deletionUndoID) {
            guard let id = deletionUndoID, let expiresAt = deletionUndoExpiresAt else { return }
            try? await Task.sleep(for: .seconds(max(0, expiresAt.timeIntervalSinceNow)))
            guard !Task.isCancelled, deletionUndoID == id else { return }
            deletedEntries = []
            deletionUndoID = nil
            deletionUndoExpiresAt = nil
        }
    }

    private func entryRow(_ entry: CalorieEntry) -> some View {
        Button {
            if selecting {
                if selection.contains(entry.id) { selection.remove(entry.id) } else { selection.insert(entry.id) }
            } else { entryToEdit = entry }
        } label: {
            HStack(spacing: 12) {
                if selecting {
                    Image(systemName: selection.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selection.contains(entry.id) ? HyseColor.accent : .secondary)
                        .frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).fontWeight(.medium).foregroundStyle(.primary)
                    let displayUnit = entry.unit.isVolume ? userSettings.defaultLiquidUnit : userSettings.defaultFoodUnit
                    let displayAmount = entry.unit.converted(entry.grams, to: displayUnit) ?? entry.grams
                    Text("\(formattedAmount(displayAmount)) \(displayUnit.rawValue) · C \(formattedNutrition(entry.carbs)) g · P \(formattedNutrition(entry.protein)) g · F \(formattedNutrition(entry.fat)) g").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(formatted(entry.kcal)) kcal").fontWeight(.semibold).foregroundStyle(.primary)
                syncIndicator(for: entry.id)
            }
            .padding(.vertical, selecting ? 5 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !selecting {
                Button(role: .destructive) { delete(entry) } label: {
                    Label(t("settings.delete"), systemImage: "trash")
                }
            }
        }
        .accessibilityValue(selecting ? (selection.contains(entry.id) ? t("add_entry.selected") : t("add_entry.not_selected")) : "")
    }

    private func delete(_ entry: CalorieEntry) {
        deletedEntries.removeAll { $0.id == entry.id }
        deletedEntries.append(entry)
        deletionUndoExpiresAt = Date().addingTimeInterval(8)
        deletionUndoID = UUID()
        calorieStore.deleteEntry(id: entry.id)
    }

    private func undoDeletion() {
        calorieStore.restoreEntries(deletedEntries)
        deletedEntries = []
        deletionUndoID = nil
        deletionUndoExpiresAt = nil
    }

    private var bulkBar: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            HStack {
                Text(t("meal_actions.selected_count", selection.count))
                    .font(.headline)
                    .monospacedDigit()
                Spacer()
                Button(selection.count == categoryEntries.count ? t("meal_actions.clear_all") : t("meal_actions.select_all")) {
                    if selection.count == categoryEntries.count { selection.removeAll() }
                    else { selection = Set(categoryEntries.map(\.id)) }
                }
                .font(.subheadline.weight(.semibold))
                .disabled(categoryEntries.isEmpty)
            }
            HStack(spacing: HyseSpacing.small) {
                bulkActionButton(.copy)
                bulkActionButton(.move)
                Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                    Label(t("settings.delete"), systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(selection.isEmpty)
            }
        }
        .padding(.horizontal, HyseSpacing.page)
        .padding(.top, HyseSpacing.medium)
        .padding(.bottom, HyseSpacing.medium)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func bulkActionButton(_ action: MealBulkAction) -> some View {
        Button { bulkAction = action } label: {
            Label(t(action.titleKey), systemImage: action.symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(HyseColor.accent)
        .disabled(selection.isEmpty)
    }

    private func deleteSelection() {
        let removed = categoryEntries.filter { selection.contains($0.id) }
        guard !removed.isEmpty else { return }
        let removedIDs = Set(removed.map(\.id))
        deletedEntries.removeAll { removedIDs.contains($0.id) }
        deletedEntries.append(contentsOf: removed)
        deletionUndoExpiresAt = Date().addingTimeInterval(8)
        deletionUndoID = UUID()
        calorieStore.deleteEntries(ids: selection)
        selection.removeAll(); selecting = false
    }

    private func nutrientRow(title: String, value: Double) -> some View { HStack { Text(title); Spacer(); Text("\(value, specifier: "%.1f") g").fontWeight(.semibold) } }
    private func formatted(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", locale: language.locale, value) }
    private func formattedNutrition(_ value: Double) -> String { String(format: "%.1f", locale: language.locale, value) }
    private func formattedAmount(_ value: Double) -> String { formatted(value) }

    private func isFutureDate(_ date: Date) -> Bool {
        Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: Date())
    }

    private func recipe(for entry: CalorieEntry) -> Recipe? {
        let availableRecipes = recipeStore.recipes + recipeStore.globalRecipes
        if let recipeID = entry.recipeId,
           let recipe = availableRecipes.first(where: { $0.id == recipeID }) {
            return recipe
        }
        if let remoteID = entry.userRecipeRecordID,
           let recipe = recipeStore.recipes.first(where: { $0.remoteID == remoteID }) {
            return recipe
        }
        if let globalID = entry.globalRecipeRecordID {
            return recipeStore.globalRecipes.first {
                $0.globalRecordID == globalID || $0.remoteID == globalID
            }
        }
        return nil
    }

    @ViewBuilder private func syncIndicator(for entryID: UUID) -> some View {
        let status = calorieStore.syncStatus(for: entryID)
        let presentation: (String, Color, String) = switch status {
        case .local: ("iphone", .secondary, t("sync.local")); case .syncing: ("arrow.triangle.2.circlepath", HyseColor.accent, t("sync.syncing")); case .synced: ("checkmark.icloud", HyseColor.success, t("sync.synced")); case .pendingSync: ("icloud.slash", HyseColor.warning, t("sync.pending")); case .failed: ("exclamationmark.icloud", HyseColor.danger, t("sync.failed"))
        }
        Image(systemName: presentation.0).font(.caption).foregroundStyle(presentation.1).accessibilityLabel(presentation.2)
    }
}

private struct EntryTransferSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    let categories: [MealCategory]
    let initialCategory: MealCategory
    let initialDate: Date
    let count: Int
    let action: MealBulkAction
    let completion: (MealCategory, Date) -> MealTransferResult
    @State private var category: MealCategory
    @State private var date: Date
    @State private var errorMessage: String?

    init(categories: [MealCategory], initialCategory: MealCategory, initialDate: Date, count: Int, action: MealBulkAction, completion: @escaping (MealCategory, Date) -> MealTransferResult) {
        self.categories = categories
        self.initialCategory = initialCategory
        self.initialDate = initialDate
        self.count = count
        self.action = action
        self.completion = completion
        _category = State(initialValue: initialCategory)
        _date = State(initialValue: initialDate)
    }

    private var isSameDestination: Bool {
        action == .move && category.id == initialCategory.id && Calendar.current.isDate(date, inSameDayAs: initialDate)
    }

    private func confirmTransfer() {
        switch completion(category, date) {
        case .completed, .premiumRequired: dismiss()
        case .failed(let message): errorMessage = message
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(language.text("meal_actions.selection_heading")) {
                    LabeledContent(language.text("meal_actions.entries"), value: language.text("meal_actions.selected_count", [count]))
                    LabeledContent(language.text("meal_actions.from"), value: initialCategory.localizedName)
                    LabeledContent(language.text("meal_actions.date"), value: initialDate.formatted(.dateTime.day().month().year().locale(language.locale)))
                }
                Section {
                    Picker(language.text("meal_actions.to"), selection: $category) {
                        ForEach(categories) { Text($0.localizedName).tag($0) }
                    }
                    DatePicker(language.text("meal_actions.date"), selection: $date, displayedComponents: .date)
                } header: {
                    Text(language.text("meal_actions.destination_heading"))
                } footer: {
                    Text(language.text(isSameDestination ? "meal_actions.same_destination" : action == .copy ? "meal_actions.copy_hint" : "meal_actions.move_hint"))
                }
            }
            .hyseForm()
            .navigationTitle(language.text(action.titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(language.text("app_tabs.cancel")) { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: confirmTransfer) {
                    Label(language.text(action == .copy ? "meal_actions.confirm_copy" : "meal_actions.confirm_move"), systemImage: action.symbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HysePrimaryButtonStyle())
                .disabled(isSameDestination)
                .padding(.horizontal, HyseSpacing.page)
                .padding(.vertical, HyseSpacing.medium)
                .background(.regularMaterial)
            }
            .alert(language.text("ui.notice"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(language.text("common.ok"), role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }
}
