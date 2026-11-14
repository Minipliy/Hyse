import SwiftUI

struct QuickEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var calorieStore: CalorieStore
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var userSettings: UserSettingsStore
    @State private var category: MealCategory
    @State private var name = ""
    @State private var amount: String
    @State private var kcal = ""
    @State private var carbs = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var sugar = ""
    @State private var fiber = ""
    @State private var saturatedFat = ""
    @State private var salt = ""
    @State private var date: Date
    @State private var alertMessage: String?
    @State private var showingCalorieGoalWarning = false
    @State private var calorieGoalOverage = 0
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    init(calorieStore: CalorieStore, categoryStore: CategoryStore, userSettings: UserSettingsStore, initialCategory: MealCategory, entryDate: Date) {
        self.calorieStore = calorieStore
        self.categoryStore = categoryStore
        self.userSettings = userSettings
        _category = State(initialValue: initialCategory)
        _date = State(initialValue: entryDate)
        let displayed = FoodUnit.gram.converted(100, to: userSettings.defaultFoodUnit) ?? 100
        _amount = State(initialValue: displayed.rounded() == displayed ? String(Int(displayed)) : String(format: "%.2f", displayed))
    }
    private func value(_ text: String) -> Double? { Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
    private var enteredAmount: Double { max(value(amount) ?? 0, 0) }
    private var enteredGrams: Double { userSettings.defaultFoodUnit.converted(enteredAmount, to: .gram) ?? 0 }
    private var canSave: Bool { enteredAmount > 0 && (value(kcal) ?? -1) >= 0 }
    private func per100(_ text: String) -> Double { enteredGrams > 0 ? (value(text) ?? 0) * 100 / enteredGrams : 0 }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(t("quick_entry.name")) {
                        TextField(t("quick_entry.e_g_snack"), text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker(t("edit_entry.meal"), selection: $category) {
                        ForEach(categoryStore.categories) { Text($0.localizedName).tag($0) }
                    }
                    DatePicker(t("quick_entry.date_time"), selection: $date)
                    field(t("quick_entry.amount_serving"), userSettings.defaultFoodUnit.rawValue, $amount)
                } header: {
                    Text(t("quick_entry.entry"))
                } footer: {
                    Text(t("quick_entry.all_nutrition_values_apply_complete_amount"))
                }
                Section(t("quick_entry.nutrition_complete_amount")) {
                    field(t("quick_entry.calories"), "kcal", $kcal)
                    field(t("quick_entry.carbohydrates"), "g", $carbs)
                    field(t("quick_entry.protein"), "g", $protein)
                    field(t("quick_entry.fat"), "g", $fat)
                    field(t("quick_entry.sugar"), "g", $sugar)
                    field(t("quick_entry.fibre"), "g", $fiber)
                    field(t("quick_entry.saturated_fat"), "g", $saturatedFat)
                    field(t("quick_entry.salt"), "g", $salt)
                }
                Section {
                    Label(t("quick_entry.stays_personal_never_published_global_foods"), systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .hyseForm()
            .navigationTitle(t("app_tabs.quick_entry"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("app_tabs.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("quick_entry.log")) { save() }
                        .bold()
                        .disabled(!canSave)
                }
            }
            .hyseAlert(
                isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } }),
                title: t("ui.notice"),
                message: alertMessage ?? "",
                buttonTitle: t("common.ok")
            )
            .confirmationDialog(t("food_tracking.goal_warning_title"), isPresented: $showingCalorieGoalWarning, titleVisibility: .visible) {
                Button(t("food_tracking.log_anyway")) { save(confirmedOverGoal: true) }
                Button(t("app_tabs.cancel"), role: .cancel) {}
            } message: { Text(t("food_tracking.goal_warning_amount", calorieGoalOverage)) }
        }
        .hyseScreen()
    }
    private func field(_ title: String, _ unit: String, _ text: Binding<String>) -> some View { LabeledContent(title) { HStack(spacing: 5) { TextField("0", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 88); Text(unit).foregroundStyle(.secondary) } } }
    private func save(confirmedOverGoal: Bool = false) {
        guard canSave, enteredGrams > 0 else { return }
        if let restriction = calorieStore.trackingRestriction(for: date) {
            alertMessage = restriction.message(using: language)
            return
        }
        if category.enforceLimit,
           let allowance = calorieStore.calorieAllowance(for: date),
           let limit = category.limit(for: allowance),
           calorieStore.totalKcal(for: date, categoryId: category.id) + (value(kcal) ?? 0) > limit {
            alertMessage = t("add_entry.meal_limit_exceeded", category.localizedName, Int(limit))
            return
        }
        if !userSettings.enforceCalorieLimit, !confirmedOverGoal,
           let allowance = calorieStore.calorieAllowance(for: date),
           allowance > 0,
           calorieStore.totalKcal(for: date) + (value(kcal) ?? 0) > allowance {
            calorieGoalOverage = (calorieStore.totalKcal(for: date) + (value(kcal) ?? 0) - allowance).rounded(.up).safeIntValue
            showingCalorieGoalWarning = true
            return
        }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let didAdd = calorieStore.addEntry(CalorieEntry(
            name: clean.isEmpty ? t("app_tabs.quick_entry") : clean,
            grams: enteredGrams,
            categoryId: category.id,
            categoryName: category.storageKey,
            unit: .gram,
            kcalPer100g: per100(kcal),
            carbsPer100g: per100(carbs),
            proteinPer100g: per100(protein),
            fatPer100g: per100(fat),
            addedSugarPer100g: per100(sugar),
            fiberPer100g: per100(fiber),
            saturatedFatPer100g: per100(saturatedFat),
            saltPer100g: per100(salt),
            date: date
        ))
        if didAdd {
            dismiss()
        } else if let restriction = calorieStore.lastFoodTrackingRestriction {
            alertMessage = restriction.message(using: language)
        } else if calorieStore.lastLocalSaveFailed {
            alertMessage = t("add_entry.local_save_failed")
        }
    }
}
