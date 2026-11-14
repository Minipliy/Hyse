import SwiftUI

private struct LocalFoodDraft: Identifiable {
    let id: UUID
    let entryID: UUID
    var food: FoodItem
    var amount: String
    var confidence: Double
    var evidence: String

    init(match: LocalFoodAnalysisMatch, displayUnit: FoodUnit, locale: Locale) {
        id = match.id
        entryID = UUID()
        food = match.food
        let displayed = match.food.unit.converted(match.baseAmount, to: displayUnit) ?? match.baseAmount
        amount = Self.formatted(displayed, locale: locale)
        confidence = match.confidence
        evidence = match.evidence
    }

    init(food: FoodItem, amount: Double, displayUnit: FoodUnit, locale: Locale) {
        id = UUID()
        entryID = UUID()
        self.food = food
        let displayed = food.unit.converted(amount, to: displayUnit) ?? amount
        self.amount = Self.formatted(displayed, locale: locale)
        confidence = 1
        evidence = ""
    }

    private static func formatted(_ value: Double, locale: Locale) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", locale: locale, value)
    }
}

struct LocalFoodAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var foodStore: FoodStore
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var calorieStore: CalorieStore
    @ObservedObject var accountData: AccountDataStore
    @ObservedObject var frequencyStore: FrequencyStore
    @ObservedObject var userSettings: UserSettingsStore
    let availableCalories: Double
    let initialCategory: MealCategory
    let entryDate: Date
    var onSaved: () -> Void

    @State private var text = ""
    @State private var category: MealCategory
    @State private var drafts: [LocalFoodDraft] = []
    @State private var isAnalyzing = false
    @State private var isSaving = false
    @State private var manualQuery = ""
    @State private var message: String?
    @State private var showingCalorieGoalWarning = false
    @State private var calorieGoalOverage = 0

    init(
        foodStore: FoodStore,
        categoryStore: CategoryStore,
        calorieStore: CalorieStore,
        accountData: AccountDataStore,
        frequencyStore: FrequencyStore,
        userSettings: UserSettingsStore,
        availableCalories: Double,
        initialCategory: MealCategory,
        entryDate: Date,
        onSaved: @escaping () -> Void
    ) {
        self.foodStore = foodStore
        self.categoryStore = categoryStore
        self.calorieStore = calorieStore
        self.accountData = accountData
        self.frequencyStore = frequencyStore
        self.userSettings = userSettings
        self.availableCalories = availableCalories
        self.initialCategory = initialCategory
        self.entryDate = entryDate
        self.onSaved = onSaved
        _category = State(initialValue: initialCategory)
    }

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        NavigationStack {
            ZStack {
                HyseBackdrop()
                ScrollView {
                    VStack(spacing: HyseSpacing.medium) {
                        privacyBanner
                        inputCard
                        if isAnalyzing { analyzingCard }
                        if !drafts.isEmpty { resultCard }
                        addFoodCard
                    }
                    .padding(HyseSpacing.page)
                    .padding(.bottom, 90)
                }
            }
            .navigationTitle(t("food_ai.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("app_tabs.cancel")) { dismiss() }.disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !drafts.isEmpty {
                    Button(action: { save() }) {
                        HStack {
                            if isSaving { ProgressView().tint(.white) }
                            Text(t("food_ai.add_items", drafts.count)).fontWeight(.bold)
                            Spacer()
                            Text("\(Int(totalNutrients.kcal.rounded())) kcal").monospacedDigit()
                        }
                        .padding(.horizontal, HyseSpacing.large)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(.white)
                        .background(HyseColor.accent, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || validDrafts.count != drafts.count)
                    .padding(.horizontal, HyseSpacing.page)
                    .padding(.top, HyseSpacing.medium)
                    .padding(.bottom, HyseSpacing.xLarge)
                    .background(HyseColor.surface)
                }
            }
            .hyseAlert(isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            ), title: t("ui.notice"), message: message ?? "", buttonTitle: t("common.ok"))
            .confirmationDialog(t("food_tracking.goal_warning_title"), isPresented: $showingCalorieGoalWarning, titleVisibility: .visible) {
                Button(t("food_tracking.log_anyway")) { save(confirmedOverGoal: true) }
                Button(t("app_tabs.cancel"), role: .cancel) {}
            } message: { Text(t("food_tracking.goal_warning_amount", calorieGoalOverage)) }
            .task(id: manualQuery) { await foodStore.hydrateGlobalSearch(for: manualQuery) }
        }
    }

    private var privacyBanner: some View {
        HStack(alignment: .top, spacing: HyseSpacing.small) {
            Image(systemName: "hand.raised.fill").foregroundStyle(HyseColor.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(t("food_ai.local_title")).font(.subheadline.weight(.semibold))
                Text(t("food_ai.local_message")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(HyseSpacing.medium)
        .hyseGlassSurface(radius: HyseRadius.control)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            Text(t("food_ai.text_prompt")).font(.headline)
            TextEditor(text: $text)
                .frame(minHeight: 108)
                .padding(HyseSpacing.small)
                .scrollContentBackground(.hidden)
                .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border))
            Text(t("food_ai.text_example")).font(.caption).foregroundStyle(.secondary)
            Button(action: analyzeText) {
                Label(t("food_ai.analyze_text"), systemImage: "text.magnifyingglass")
                    .fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(HyseColor.accent)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzing)
            Text(t("food_ai.stays_on_device")).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(HyseSpacing.medium)
        .hyseGlassSurface(radius: HyseRadius.card)
    }

    private var analyzingCard: some View {
        HStack(spacing: HyseSpacing.medium) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text(t("food_ai.analyzing")).font(.headline)
                Text(t("food_ai.stays_on_device"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(HyseSpacing.medium)
        .hyseGlassSurface(radius: HyseRadius.control)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("food_ai.estimate")).font(.headline)
                    Text(t("food_ai.review_hint")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(categoryStore.categories) { value in
                        Button(value.localizedName) { category = value }
                    }
                } label: {
                    Label(category.localizedName, systemImage: "fork.knife").font(.caption.weight(.semibold))
                }
            }

            ForEach($drafts) { $draft in
                VStack(spacing: HyseSpacing.small) {
                    HStack(alignment: .top, spacing: HyseSpacing.small) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(draft.food.displayName(using: language)).font(.subheadline.weight(.semibold))
                            if !draft.evidence.isEmpty {
                                Text(t("food_ai.detected_as", draft.evidence)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        TextField("100", text: $draft.amount)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 70)
                        Text(displayUnit(for: draft.food).rawValue).foregroundStyle(.secondary)
                        Button(role: .destructive) { drafts.removeAll { $0.id == draft.id } } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain).accessibilityLabel(t("settings.delete"))
                    }
                    HStack {
                        ProgressView(value: draft.confidence).tint(confidenceColor(draft.confidence))
                        Text(confidenceLabel(draft.confidence)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if draft.id != drafts.last?.id { Divider() }
            }

            Divider()
            HStack(spacing: HyseSpacing.medium) {
                nutrientValue(t("nutrition.calories"), "\(Int(totalNutrients.kcal.rounded())) kcal")
                nutrientValue(t("ui.carbs"), "\(totalNutrients.carbs.formatted(.number.precision(.fractionLength(0...1)))) g")
                nutrientValue(t("ui.protein"), "\(totalNutrients.protein.formatted(.number.precision(.fractionLength(0...1)))) g")
                nutrientValue(t("ui.fat"), "\(totalNutrients.fat.formatted(.number.precision(.fractionLength(0...1)))) g")
            }
        }
        .padding(HyseSpacing.medium)
        .hyseGlassSurface(radius: HyseRadius.card)
    }

    private var addFoodCard: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            Label(t("food_ai.add_or_correct"), systemImage: "magnifyingglass").font(.headline)
            TextField(t("add_entry.search_food"), text: $manualQuery)
                .padding(.horizontal, HyseSpacing.medium).frame(minHeight: 44)
                .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border))
            if !manualQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ForEach(foodStore.searchFoods(query: manualQuery).prefix(5)) { food in
                    Button { add(food); manualQuery = "" } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.displayName(using: language)).foregroundStyle(.primary)
                                Text("\(Int(food.kcalPerNutritionReference.rounded())) kcal / \(food.unit.nutritionReferenceLabel)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(HyseColor.accent)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(HyseSpacing.medium)
        .hyseGlassSurface(radius: HyseRadius.card)
    }

    private func nutrientValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var validDrafts: [(LocalFoodDraft, Double)] {
        drafts.compactMap { draft in
            guard let displayed = Double(draft.amount.replacingOccurrences(of: ",", with: ".")), displayed > 0,
                  let canonical = displayUnit(for: draft.food).converted(displayed, to: draft.food.unit) else { return nil }
            return (draft, canonical)
        }
    }

    private var totalNutrients: CalculatedNutrients {
        validDrafts.reduce(CalculatedNutrients(kcal: 0, carbs: 0, protein: 0, fat: 0, sugar: 0, fiber: 0, saturatedFat: 0, salt: 0)) { total, value in
            let current = value.0.food.calculatedValues(forGrams: value.1)
            return CalculatedNutrients(
                kcal: total.kcal + current.kcal, carbs: total.carbs + current.carbs,
                protein: total.protein + current.protein, fat: total.fat + current.fat,
                sugar: total.sugar + current.sugar, fiber: total.fiber + current.fiber,
                saturatedFat: total.saturatedFat + current.saturatedFat, salt: total.salt + current.salt
            )
        }
    }

    private func analyzeText() {
        isAnalyzing = true
        let input = text
        let foods = foodStore.availableFoods
        Task {
            let localMatches = await LocalFoodAnalyzer.shared.analyzeText(input, foods: foods)
            apply(localMatches)
        }
    }

    private func apply(_ matches: [LocalFoodAnalysisMatch]) {
        isAnalyzing = false
        drafts = matches.map { match in
            LocalFoodDraft(match: match, displayUnit: displayUnit(for: match.food), locale: language.locale)
        }
        if drafts.isEmpty { message = t("food_ai.no_match") }
    }

    private func add(_ food: FoodItem) {
        let amount = food.defaultPortionBaseAmount ?? 100
        drafts.append(LocalFoodDraft(food: food, amount: amount, displayUnit: displayUnit(for: food), locale: language.locale))
    }

    private func displayUnit(for food: FoodItem) -> FoodUnit {
        food.unit.isVolume ? userSettings.defaultLiquidUnit : userSettings.defaultFoodUnit
    }

    private func confidenceColor(_ value: Double) -> Color {
        value >= 0.72 ? HyseColor.accent : (value >= 0.45 ? .orange : .red)
    }

    private func confidenceLabel(_ value: Double) -> String {
        if value >= 0.72 { return t("food_ai.confidence_high") }
        if value >= 0.45 { return t("food_ai.confidence_medium") }
        return t("food_ai.confidence_low")
    }

    private func save(confirmedOverGoal: Bool = false) {
        guard !isSaving, validDrafts.count == drafts.count, !drafts.isEmpty else { return }
        if let restriction = calorieStore.trackingRestriction(for: entryDate) {
            message = restriction.message(using: language)
            return
        }
        let nutrients = totalNutrients
        let selectedDayAllowance = calorieStore.calorieAllowance(for: entryDate) ?? availableCalories
        if userSettings.enforceCalorieLimit && calorieStore.totalKcal(for: entryDate) + nutrients.kcal > userSettings.maximumAllowedCalories(selectedDayAllowance) {
            message = t("add_entry.daily_limit_exceeded")
            return
        }
        let categoryCurrent = calorieStore.totalKcal(for: entryDate, categoryId: category.id)
        if category.enforceLimit, let limit = category.limit(for: selectedDayAllowance), categoryCurrent + nutrients.kcal > limit {
            message = t("add_entry.meal_limit_exceeded", category.localizedName, Int(limit))
            return
        }
        if !userSettings.enforceCalorieLimit, !confirmedOverGoal,
           selectedDayAllowance > 0,
           calorieStore.totalKcal(for: entryDate) + nutrients.kcal > selectedDayAllowance {
            calorieGoalOverage = (calorieStore.totalKcal(for: entryDate) + nutrients.kcal - selectedDayAllowance).rounded(.up).safeIntValue
            showingCalorieGoalWarning = true
            return
        }
        isSaving = true
        let timestamp = entryTimestamp
        let entries = validDrafts.map { draft, canonicalAmount in
            CalorieEntry(
                id: draft.entryID, foodItemId: draft.food.id, globalFoodRecordID: draft.food.globalRecordID,
                name: draft.food.name, grams: canonicalAmount, categoryId: category.id, categoryName: category.storageKey,
                unit: draft.food.unit, kcalPer100g: draft.food.kcalPer100g, carbsPer100g: draft.food.carbsPer100g,
                proteinPer100g: draft.food.proteinPer100g, fatPer100g: draft.food.fatPer100g,
                addedSugarPer100g: draft.food.isFruit ? 0 : draft.food.sugarPer100g,
                fruitSugarPer100g: draft.food.isFruit ? draft.food.sugarPer100g : 0,
                fiberPer100g: draft.food.fiberPer100g, saturatedFatPer100g: draft.food.saturatedFatPer100g,
                saltPer100g: draft.food.saltPer100g, micronutrients: draft.food.micronutrients, date: timestamp
            )
        }
        guard calorieStore.addEntries(entries) else {
            isSaving = false
            if let restriction = calorieStore.lastFoodTrackingRestriction {
                message = restriction.message(using: language)
            } else if calorieStore.lastLocalSaveFailed {
                message = t("add_entry.local_save_failed")
            } else {
                message = t("food_ai.save_failed")
            }
            return
        }
        validDrafts.forEach { draft, amount in
            frequencyStore.recordUsage(food: draft.food, categoryId: category.id)
            accountData.recordUsage(food: draft.food, amount: amount, mealKey: category.storageKey, usedAt: timestamp)
        }
        dismiss()
        onSaved()
    }

    private var entryTimestamp: Date {
        let calendar = Calendar.current
        let now = Date()
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: entryDate) ?? entryDate
    }
}
