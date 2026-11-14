import SwiftUI

struct EditEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    @ObservedObject var calorieStore: CalorieStore
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var userSettings: UserSettingsStore
    let availableCalories: Double
    var entry: CalorieEntry
    var recipe: Recipe?
    var food: FoodItem?

    @State private var amountText: String
    @State private var amountMode: Int
    @State private var selectedPortionID: UUID?
    @State private var amountAdjustmentMode = 0
    @State private var nameText: String
    @State private var alertMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var showingCalorieGoalWarning = false
    @State private var calorieGoalOverage = 0
    @State private var selectedCategory: MealCategory
    @State private var quickKcalText: String
    @State private var quickCarbsText: String
    @State private var quickProteinText: String
    @State private var quickFatText: String
    @State private var quickSugarText: String
    @State private var quickFiberText: String
    @State private var quickSaturatedFatText: String
    @State private var quickSaltText: String
    @FocusState private var amountFocused: Bool

    init(calorieStore: CalorieStore, categoryStore: CategoryStore, userSettings: UserSettingsStore, availableCalories: Double, entry: CalorieEntry, recipe: Recipe? = nil, food: FoodItem? = nil) {
        self.calorieStore = calorieStore
        self.categoryStore = categoryStore
        self.userSettings = userSettings
        self.availableCalories = availableCalories
        self.entry = entry
        self.recipe = recipe
        self.food = food
        let matchedFoodPortion: FoodPortion?
        if let portionID = entry.portionID {
            matchedFoodPortion = food?.portions.first(where: { $0.id == portionID })
        } else {
            matchedFoodPortion = food?.defaultPortion
        }
        // The entry itself remains the source of truth when a food's portion
        // was changed or removed after the meal was logged.
        let validStoredPortionCount = entry.portionCount.flatMap { count in
            count.isFinite && count > 0 ? count : nil
        }
        let storedPortionSize = validStoredPortionCount.flatMap { count in
            entry.grams.isFinite && entry.grams > 0 ? entry.grams / count : nil
        }
        let portionSize = recipe?.gramsPerServing
            ?? matchedFoodPortion?.baseAmount(in: entry.unit)
            ?? storedPortionSize
        let usesPortions = (recipe != nil || validStoredPortionCount != nil) && (portionSize ?? 0) > 0
        let preferredUnit = entry.unit.isVolume ? userSettings.defaultLiquidUnit : userSettings.defaultFoodUnit
        let displayedAmount = entry.unit.converted(entry.grams, to: preferredUnit) ?? entry.grams
        _amountMode = State(initialValue: usesPortions ? 1 : 0)
        _selectedPortionID = State(initialValue: matchedFoodPortion?.id ?? entry.portionID)
        let calculatedPortionCount = entry.grams / (portionSize ?? 1)
        let initialPortionCount = calculatedPortionCount.isFinite && calculatedPortionCount > 0
            ? calculatedPortionCount : (validStoredPortionCount ?? 1)
        _amountText = State(initialValue: usesPortions ? Self.formatted(initialPortionCount) : Self.formatted(displayedAmount))
        _nameText = State(initialValue: entry.name)
        _quickKcalText = State(initialValue: Self.formatted(entry.kcal))
        _quickCarbsText = State(initialValue: Self.formatted(entry.carbs))
        _quickProteinText = State(initialValue: Self.formatted(entry.protein))
        _quickFatText = State(initialValue: Self.formatted(entry.fat))
        _quickSugarText = State(initialValue: Self.formatted(entry.sugar))
        _quickFiberText = State(initialValue: Self.formatted(entry.fiber))
        _quickSaturatedFatText = State(initialValue: Self.formatted(entry.saturatedFat))
        _quickSaltText = State(initialValue: Self.formatted(entry.salt))
        let initialCategory = categoryStore.categories.first(where: { $0.id == entry.categoryId })
            ?? categoryStore.categories.first(where: { $0.storageKey == (MealCategory.legacySystemKey(for: entry.categoryName) ?? entry.categoryName) })
            ?? categoryStore.categories.first
            ?? MealCategory(name: entry.categoryName, order: 0)
        _selectedCategory = State(initialValue: initialCategory)
    }

    private var selectedFoodPortion: FoodPortion? {
        guard let food else { return nil }
        if let portionID = selectedPortionID {
            return food.portions.first(where: { $0.id == portionID })
        }
        return food.defaultPortion
    }

    private var portionSize: Double? {
        if let recipe { return recipe.gramsPerServing }
        if let amount = selectedFoodPortion?.baseAmount(in: entry.unit) { return amount }
        if let count = entry.portionCount, count > 0 { return entry.grams / count }
        return nil
    }
    private var canUsePortions: Bool { (portionSize ?? 0) > 0 }
    private var isQuickEntry: Bool {
        food == nil && recipe == nil
            && entry.foodItemId == nil && entry.recipeId == nil
            && entry.globalFoodRecordID == nil
            && entry.userRecipeRecordID == nil && entry.globalRecipeRecordID == nil
    }
    private var displayUnit: FoodUnit { entry.unit.isVolume ? userSettings.defaultLiquidUnit : userSettings.defaultFoodUnit }
    private var unitLabel: String { displayUnit.rawValue }
    private var portionUnitLabel: String {
        let count = Self.decimal(amountText) ?? 0
        return abs(count - 1) < 0.000_001 ? t("ui.serving") : t("recipe_editor.servings")
    }
    private var originalAmountForMode: Double {
        if amountMode == 1, let portionSize, portionSize > 0 { return entry.grams / portionSize }
        return entry.unit.converted(entry.grams, to: displayUnit) ?? entry.grams
    }
    private var currentGrams: Double {
        guard let amount = Self.decimal(amountText), amount.isFinite, amount >= 0 else {
            return amountAdjustmentMode == 1 && !isQuickEntry ? entry.grams : 0
        }
        let entered = amountMode == 1
            ? amount * (portionSize ?? 1)
            : (displayUnit.converted(amount, to: entry.unit) ?? amount)
        let total = amountAdjustmentMode == 1 && !isQuickEntry ? entry.grams + entered : entered
        return total.isFinite ? total : 0
    }

    private var amountStep: Double { amountMode == 1 ? (recipe == nil ? 1 : 0.25) : 5 }

    private var amountStepperBinding: Binding<Double> {
        Binding(
            get: { max(Self.decimal(amountText) ?? 0, 0) },
            set: { amountText = Self.formatted(max($0, 0)) }
        )
    }

    private var amountStepUnit: String {
        amountMode == 1 ? portionUnitLabel : unitLabel
    }

    private var displayedCurrentAmount: Double {
        entry.unit.converted(currentGrams, to: displayUnit) ?? currentGrams
    }

    private var newKcal: Double {
        if isQuickEntry { return max(Self.decimal(quickKcalText) ?? 0, 0) }
        return (entry.kcalPer100g * currentGrams / 100.0).rounded(toPlaces: 1)
    }

    private var newSugarTotal: Double {
        ((entry.addedSugarPer100g + entry.fruitSugarPer100g) * currentGrams / 100.0).rounded(toPlaces: 1)
    }

    private var canSave: Bool {
        let canonicalUnit: FoodUnit = entry.unit.isVolume ? .milliliter : .gram
        let canonicalAmount = entry.unit.converted(currentGrams, to: canonicalUnit) ?? currentGrams
        let validBase = (Self.decimal(amountText) ?? 0) > 0
            && (isQuickEntry || FoodAmountLimit.accepts(canonicalAmount))
            && !nameText.trimmingCharacters(in: .whitespaces).isEmpty
        guard isQuickEntry else { return validBase }
        return validBase && Self.decimal(quickKcalText).map { $0 >= 0 } == true
    }

    var body: some View {
        NavigationStack {
            Form {
                entryInformationSection
                amountSection
                if isQuickEntry {
                    quickNutritionSection
                } else {
                    calculatedNutritionSection
                }
                if !isQuickEntry {
                    Section {
                        MicronutrientReadOnlyButton(
                            profile: calorieStore.entries.first(where: { $0.id == entry.id })?.micronutrients ?? entry.micronutrients,
                            amount: currentGrams,
                            unit: entry.unit
                        )
                    }
                }
                Section {
                    Button(t("ui.delete_entry"), role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
            .hyseForm()
            .navigationTitle("ui.edit_entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("app_tabs.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("recipe_editor.save") { saveChanges() }
                        .bold()
                        .disabled(!canSave)
                }
            }
            .alert(
                "ui.delete_entry_2",
                isPresented: $showingDeleteConfirmation,
            ) {
                Button("ui.delete_entry", role: .destructive) {
                    calorieStore.deleteEntry(id: entry.id)
                    dismiss()
                }
                Button("app_tabs.cancel", role: .cancel) {}
            } message: {
                Text("ui.entry_will_permanently_removed")
            }
            .alert("ui.notice", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
                Button(t("common.ok")) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
            .confirmationDialog(t("food_tracking.goal_warning_title"), isPresented: $showingCalorieGoalWarning, titleVisibility: .visible) {
                Button(t("food_tracking.log_anyway")) { saveChanges(confirmedOverGoal: true) }
                Button(t("app_tabs.cancel"), role: .cancel) {}
            } message: { Text(t("food_tracking.goal_warning_amount", calorieGoalOverage)) }
            .onChange(of: amountMode) { oldMode, newMode in
                guard oldMode != newMode, let amount = Self.decimal(amountText), let portionSize, portionSize > 0 else { return }
                if newMode == 1 {
                    let canonical = displayUnit.converted(amount, to: entry.unit) ?? amount
                    amountText = Self.formatted(canonical / portionSize)
                } else {
                    let canonical = amount * portionSize
                    amountText = Self.formatted(entry.unit.converted(canonical, to: displayUnit) ?? canonical)
                }
            }
            .onChange(of: selectedPortionID) { oldID, newID in
                guard amountMode == 1, let food, let count = Self.decimal(amountText) else { return }
                let storedSize = entry.portionCount.flatMap { $0 > 0 ? entry.grams / $0 : nil }
                let oldSize = food.portions.first(where: { $0.id == oldID })?.baseAmount(in: entry.unit) ?? storedSize
                let newSize = food.portions.first(where: { $0.id == newID })?.baseAmount(in: entry.unit)
                guard let oldSize, let newSize, oldSize > 0, newSize > 0 else { return }
                amountText = Self.formatted(count * oldSize / newSize)
            }
            .onChange(of: amountAdjustmentMode) { oldMode, newMode in
                guard oldMode != newMode else { return }
                if newMode == 1 {
                    amountText = ""
                } else {
                    let increment = Self.decimal(amountText) ?? 0
                    let total = originalAmountForMode + increment
                    amountText = Self.formatted(total.isFinite && total > 0 && total < 1_000_000_000 ? total : originalAmountForMode)
                }
            }
        }
        .hyseScreen()
    }

    private var entryInformationSection: some View {
        Section(t(recipe == nil ? "edit_entry.edit_food_entry" : "edit_entry.edit_recipe_entry")) {
            TextField(t("common.name"), text: $nameText)
                .textInputAutocapitalization(.words)
            Picker(t("edit_entry.meal"), selection: $selectedCategory) {
                ForEach(categoryStore.categories) { category in
                    Text(category.localizedName).tag(category)
                }
            }
        }
    }

    private var amountSection: some View {
        Section {
            if !isQuickEntry {
                Picker(t("edit_entry.amount_action"), selection: $amountAdjustmentMode) {
                    Text(t("edit_entry.replace_amount")).tag(0)
                    Text(t("edit_entry.add_amount")).tag(1)
                }
                .pickerStyle(.segmented)
            }
            if canUsePortions {
                Picker(t("ui.unit"), selection: $amountMode) {
                    Text(unitLabel).tag(0)
                    Text(t("ui.serving")).tag(1)
                }
                .pickerStyle(.segmented)
            }
            if amountMode == 1, let food,
               food.portions.count > 1 || (entry.portionID != nil
                   && !food.portions.contains(where: { $0.id == entry.portionID })) {
                Picker(t("food_portion.section"), selection: $selectedPortionID) {
                    if let storedID = entry.portionID,
                       !food.portions.contains(where: { $0.id == storedID }) {
                        Text(entry.portionName ?? t("ui.serving")).tag(Optional(storedID))
                    }
                    ForEach(food.portions.sorted { $0.sortOrder < $1.sortOrder }) { portion in
                        Text(portion.displayName(using: language)).tag(Optional(portion.id))
                    }
                }
            }

            LabeledContent(t("recipe_editor.amount")) {
                HStack(spacing: HyseSpacing.small) {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 88)
                        .font(.body.monospacedDigit())
                        .simultaneousGesture(TapGesture().onEnded { selectAmountText() })
                        .onChange(of: amountFocused) { _, isFocused in
                            if isFocused { selectAmountText() }
                        }
                    Text(amountMode == 1 ? portionUnitLabel : unitLabel)
                        .foregroundStyle(.secondary)
                }
            }

            Stepper(t("ui.quick_selection"), value: amountStepperBinding, in: 0...10_000, step: amountStep)

            if amountMode == 1, let portionSize {
                let displayedPortionSize = entry.unit.converted(portionSize, to: displayUnit) ?? portionSize
                Text(t("add_entry.one_serving_equals", Self.formatted(displayedPortionSize), unitLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(t(amountMode == 1 ? "recipe_editor.servings" : "edit_entry.eaten_amount"))
        } footer: {
            VStack(alignment: .leading, spacing: HyseSpacing.small) {
                if amountAdjustmentMode == 1, let increment = Self.decimal(amountText), increment > 0, canSave {
                    let total = amountMode == 1 ? currentGrams / (portionSize ?? 1) : displayedCurrentAmount
                    Text(t("edit_entry.addition_preview", Self.formatted(originalAmountForMode), Self.formatted(increment), Self.formatted(total), amountMode == 1 ? t("recipe_editor.servings") : unitLabel))
                }
                Text(t("edit_entry.recalculated_nutrition_1_2", Self.formatted(displayedCurrentAmount), unitLabel))
            }
        }
    }

    private func selectAmountText() {
        guard !amountText.isEmpty else { return }
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
    }

    private var calculatedNutritionSection: some View {
        Section(t("edit_entry.recalculated_nutrition_1_2", Self.formatted(displayedCurrentAmount), unitLabel)) {
            nutritionValueRow("quick_entry.calories", value: "\(Int(newKcal))", unit: "kcal")
            nutritionValueRow("quick_entry.carbohydrates", value: formattedNutrient(entry.carbsPer100g * currentGrams / 100.0), unit: "g")
            nutritionValueRow("quick_entry.protein", value: formattedNutrient(entry.proteinPer100g * currentGrams / 100.0), unit: "g")
            nutritionValueRow("quick_entry.fat", value: formattedNutrient(entry.fatPer100g * currentGrams / 100.0), unit: "g")
            nutritionValueRow("ui.total_sugar", value: formattedNutrient(newSugarTotal), unit: "g")
            nutritionValueRow("quick_entry.fibre", value: formattedNutrient(entry.fiberPer100g * currentGrams / 100.0), unit: "g")
            nutritionValueRow("ui.saturated_fat", value: formattedNutrient(entry.saturatedFatPer100g * currentGrams / 100.0), unit: "g")
            nutritionValueRow("quick_entry.salt", value: formattedNutrient(entry.saltPer100g * currentGrams / 100.0), unit: "g")
        }
    }

    private var quickNutritionSection: some View {
        Section {
            entryNutritionField("quick_entry.calories", unit: "kcal", text: $quickKcalText, prominent: true)
            entryNutritionField("quick_entry.carbohydrates", unit: "g", text: $quickCarbsText)
            entryNutritionField("quick_entry.protein", unit: "g", text: $quickProteinText)
            entryNutritionField("quick_entry.fat", unit: "g", text: $quickFatText)
            entryNutritionField("quick_entry.sugar", unit: "g", text: $quickSugarText)
            entryNutritionField("quick_entry.fibre", unit: "g", text: $quickFiberText)
            entryNutritionField("ui.saturated_fat", unit: "g", text: $quickSaturatedFatText)
            entryNutritionField("quick_entry.salt", unit: "g", text: $quickSaltText)
        } header: {
            Text(t("quick_entry.nutrition_complete_amount"))
        } footer: {
            Text(t("quick_entry.all_nutrition_values_apply_complete_amount"))
        }
    }

    private func entryNutritionField(_ title: String, unit: String, text: Binding<String>, prominent: Bool = false) -> some View {
        LabeledContent(t(title)) {
            HStack(spacing: HyseSpacing.small) {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 88)
                    .font(prominent ? .headline.monospacedDigit() : .body.monospacedDigit())
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }

    private func nutritionValueRow(_ title: String, value: String, unit: String) -> some View {
        LabeledContent(t(title)) {
            Text("\(value) \(unit)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var entryHeader: some View {
        HyseCard {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                HStack(spacing: HyseSpacing.medium) {
                    HyseIconBadge(icon: recipe == nil ? "fork.knife" : "book.closed.fill", color: .secondary, size: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t(recipe == nil ? "ui.single_food" : "app_tabs.recipe"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(nameText.isEmpty ? entry.name : nameText)
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                        if let brand = food?.brand, !brand.isEmpty {
                            Text(brand).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if let recipe, !recipe.displayDescription.isEmpty {
                    Text(recipe.displayDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let recipe, !recipe.filters.isEmpty {
                    RecipeFilterBadges(filters: recipe.filters)
                }

                HStack(spacing: HyseSpacing.small) {
                    summaryPill(icon: "scalemass.fill", title: "\(Self.formatted(displayedCurrentAmount)) \(unitLabel)")
                    summaryPill(icon: "flame.fill", title: "\(Int(newKcal)) kcal")
                }
            }
        }
    }

    private var detailsCard: some View {
        editorCard(icon: "pencil", title: t(recipe == nil ? "edit_entry.edit_food_entry" : "edit_entry.edit_recipe_entry")) {
            VStack(spacing: HyseSpacing.medium) {
                editorTextField(icon: "textformat", title: t("common.name"), text: $nameText)
                Divider()
                HStack(spacing: HyseSpacing.medium) {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("edit_entry.meal")).font(.caption).foregroundStyle(.secondary)
                        Text(selectedCategory.localizedName).font(.body.weight(.medium))
                    }
                    Spacer()
                    Picker(t("edit_entry.meal"), selection: $selectedCategory) {
                        ForEach(categoryStore.categories) { category in
                            Text(category.localizedName).tag(category)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var amountCard: some View {
        editorCard(
            icon: "scalemass.fill",
            title: t(amountMode == 1 ? "recipe_editor.servings" : "edit_entry.eaten_amount"),
            subtitle: t("edit_entry.recalculated_nutrition_1_2", Self.formatted(displayedCurrentAmount), unitLabel)
        ) {
            VStack(spacing: HyseSpacing.medium) {
                if canUsePortions {
                    HyseSegmentedControl(
                        items: [0, 1],
                        selection: $amountMode,
                        title: { $0 == 0 ? unitLabel : t("ui.serving") },
                        symbol: { $0 == 0 ? "scalemass" : "circle.grid.2x2.fill" },
                        tint: .primary
                    )
                }

                HStack(alignment: .bottom, spacing: HyseSpacing.small) {
                    TextField(t("recipe_editor.amount"), text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.leading)
                        .textFieldStyle(.plain)
                    Text(amountMode == 1 ? portionUnitLabel : unitLabel)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 5)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(newKcal))")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text("kcal")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, HyseSpacing.medium)
                .padding(.vertical, HyseSpacing.large)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border))

                HStack(spacing: HyseSpacing.small) {
                    Label(t("ui.quick_selection"), systemImage: "plusminus")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Text("± \(Self.formatted(amountStep)) \(amountStepUnit)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Stepper("", value: amountStepperBinding, in: 0...10_000, step: amountStep)
                        .labelsHidden()
                        .accessibilityLabel(t("ui.quick_selection"))
                }

                if amountMode == 1, let portionSize {
                    let displayedPortionSize = entry.unit.converted(portionSize, to: displayUnit) ?? portionSize
                    Text(t("add_entry.one_serving_equals", Self.formatted(displayedPortionSize), unitLabel))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var calculatedNutritionCard: some View {
        editorCard(
            icon: "chart.bar.xaxis",
            title: t("edit_entry.recalculated_nutrition_1_2", Self.formatted(displayedCurrentAmount), unitLabel),
            subtitle: t("edit_food.nutrition_per_100", entry.unit.rawValue)
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: HyseSpacing.small) {
                nutritionTile("quick_entry.calories", value: "\(Int(newKcal))", unit: "kcal", icon: "flame.fill")
                nutritionTile("quick_entry.carbohydrates", value: formattedNutrient(entry.carbsPer100g * currentGrams / 100.0), unit: "g", icon: "leaf.fill")
                nutritionTile("quick_entry.protein", value: formattedNutrient(entry.proteinPer100g * currentGrams / 100.0), unit: "g", icon: "figure.strengthtraining.traditional")
                nutritionTile("quick_entry.fat", value: formattedNutrient(entry.fatPer100g * currentGrams / 100.0), unit: "g", icon: "drop.fill")
                nutritionTile("ui.total_sugar", value: formattedNutrient(newSugarTotal), unit: "g", icon: "cube.fill")
                nutritionTile("quick_entry.fibre", value: formattedNutrient(entry.fiberPer100g * currentGrams / 100.0), unit: "g", icon: "leaf")
                nutritionTile("ui.saturated_fat", value: formattedNutrient(entry.saturatedFatPer100g * currentGrams / 100.0), unit: "g", icon: "circle.fill")
                nutritionTile("quick_entry.salt", value: formattedNutrient(entry.saltPer100g * currentGrams / 100.0), unit: "g", icon: "s.circle.fill")
            }
        }
    }

    private var quickNutritionCard: some View {
        editorCard(
            icon: "slider.horizontal.3",
            title: t("quick_entry.nutrition_complete_amount"),
            subtitle: t("quick_entry.all_nutrition_values_apply_complete_amount")
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: HyseSpacing.small) {
                quickNutritionField("quick_entry.calories", unit: "kcal", text: $quickKcalText)
                quickNutritionField("quick_entry.carbohydrates", unit: "g", text: $quickCarbsText)
                quickNutritionField("quick_entry.protein", unit: "g", text: $quickProteinText)
                quickNutritionField("quick_entry.fat", unit: "g", text: $quickFatText)
                quickNutritionField("quick_entry.sugar", unit: "g", text: $quickSugarText)
                quickNutritionField("quick_entry.fibre", unit: "g", text: $quickFiberText)
                quickNutritionField("ui.saturated_fat", unit: "g", text: $quickSaturatedFatText)
                quickNutritionField("quick_entry.salt", unit: "g", text: $quickSaltText)
            }
        }
    }

    private func editorCard<Content: View>(icon: String, title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HyseCard {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                HStack(alignment: .top, spacing: HyseSpacing.medium) {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        if let subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                content()
            }
        }
    }

    private func editorTextField(icon: String, title: String, text: Binding<String>) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
        }
        .padding(.horizontal, HyseSpacing.medium)
        .frame(minHeight: 46)
        .background(HyseColor.background.opacity(0.75), in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border))
    }

    private func summaryPill(icon: String, title: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, HyseSpacing.medium)
            .padding(.vertical, HyseSpacing.small)
            .background(Color.primary.opacity(0.07), in: Capsule())
    }

    private func nutritionTile(_ titleKey: String, value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            HStack(spacing: HyseSpacing.small) {
                Image(systemName: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(t(titleKey)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title3.weight(.bold)).monospacedDigit()
                Text(unit).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HyseSpacing.medium)
        .background(HyseColor.background.opacity(0.72), in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border))
    }

    private func formattedNutrient(_ value: Double) -> String {
        String(format: "%.1f", locale: language.locale, value.rounded(toPlaces: 1))
    }

    private func saveChanges(confirmedOverGoal: Bool = false) {
        let updatedGrams = currentGrams
        guard canSave else { return }

        if userSettings.enforceCalorieLimit {
            let currentOtherKcal = calorieStore.totalKcal(for: entry.date) - entry.kcal
            let newTotal = currentOtherKcal + newKcal
            let maximumAllowedCalories = userSettings.maximumAllowedCalories(availableCalories)
            if newTotal > maximumAllowedCalories {
                let remaining = maximumAllowedCalories - currentOtherKcal
                let formattedRemaining = String(format: "%.0f", max(0, remaining))
                alertMessage = t("edit_entry.only_calories_remaining", formattedRemaining)
                return
            }
        }
        if !userSettings.enforceCalorieLimit, !confirmedOverGoal,
           availableCalories > 0,
           calorieStore.totalKcal(for: entry.date) - entry.kcal + newKcal > availableCalories,
           newKcal > entry.kcal {
            calorieGoalOverage = (calorieStore.totalKcal(for: entry.date) - entry.kcal + newKcal - availableCalories).rounded(.up).safeIntValue
            showingCalorieGoalWarning = true
            return
        }

        var updatedEntry = entry
        updatedEntry.name = nameText.trimmingCharacters(in: .whitespaces)
        updatedEntry.grams = updatedGrams
        updatedEntry.categoryId = selectedCategory.id
        updatedEntry.categoryName = selectedCategory.storageKey
        if isQuickEntry {
            let factor = 100 / updatedGrams
            updatedEntry.kcalPer100g = max(Self.decimal(quickKcalText) ?? 0, 0) * factor
            updatedEntry.carbsPer100g = max(Self.decimal(quickCarbsText) ?? 0, 0) * factor
            updatedEntry.proteinPer100g = max(Self.decimal(quickProteinText) ?? 0, 0) * factor
            updatedEntry.fatPer100g = max(Self.decimal(quickFatText) ?? 0, 0) * factor
            updatedEntry.addedSugarPer100g = max(Self.decimal(quickSugarText) ?? 0, 0) * factor
            updatedEntry.fruitSugarPer100g = 0
            updatedEntry.fiberPer100g = max(Self.decimal(quickFiberText) ?? 0, 0) * factor
            updatedEntry.saturatedFatPer100g = max(Self.decimal(quickSaturatedFatText) ?? 0, 0) * factor
            updatedEntry.saltPer100g = max(Self.decimal(quickSaltText) ?? 0, 0) * factor
        }
        if amountMode == 1 {
            updatedEntry.portionCount = updatedGrams / (portionSize ?? 1)
            if food != nil {
                updatedEntry.portionID = selectedFoodPortion?.id ?? entry.portionID
                updatedEntry.portionName = selectedFoodPortion?.displayName(using: language) ?? entry.portionName
            }
        } else {
            updatedEntry.portionCount = nil
            if food != nil {
                updatedEntry.portionID = nil
                updatedEntry.portionName = nil
            }
        }
        guard calorieStore.updateEntry(updatedEntry) else {
            alertMessage = t("add_entry.local_save_failed")
            return
        }
        dismiss()
    }

    private func quickNutritionField(_ title: LocalizedStringKey, unit: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: HyseSpacing.small) {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .textFieldStyle(.plain)
                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(HyseSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyseColor.background.opacity(0.72), in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border))
    }

    private static func decimal(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "¼", with: "1/4")
            .replacingOccurrences(of: "½", with: "1/2")
            .replacingOccurrences(of: "¾", with: "3/4")
            .replacingOccurrences(of: "⅓", with: "1/3")
            .replacingOccurrences(of: "⅔", with: "2/3")
        if let slash = normalized.firstIndex(of: "/") {
            guard let numerator = Double(normalized[..<slash]), let denominator = Double(normalized[normalized.index(after: slash)...]), denominator != 0 else { return nil }
            return numerator / denominator
        }
        return Double(normalized)
    }

    private static func formatted(_ amount: Double) -> String {
        amount.rounded() == amount ? String(Int(amount)) : String(format: "%.2f", amount).replacingOccurrences(of: ".", with: ",")
    }
}
