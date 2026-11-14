import SwiftUI
import Combine

nonisolated struct PlannedRecipe: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    let recipe: Recipe
    let servings: Double
    let categoryID: UUID
    let categoryName: String
    var loggedEntryID: UUID?

    init(id: UUID = UUID(), date: Date, recipe: Recipe, servings: Double, categoryID: UUID, categoryName: String) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.recipe = recipe
        self.servings = servings
        self.categoryID = categoryID
        self.categoryName = categoryName
    }
}

@MainActor
final class MealPlanStore: ObservableObject {
    @Published private(set) var items: [PlannedRecipe] = []
    @Published private(set) var checkedIngredients: Set<String> = []
    @Published private(set) var pendingGuestMergeCount = 0
    private var scope = "guest"
    private var pendingGuestItems: [PlannedRecipe] = []
    private var key: String { "hyse_meal_plan_\(scope)_v1" }
    private var checkedKey: String { "hyse_meal_plan_checked_\(scope)_v1" }
    private var handledGuestKey: String { "hyse_meal_plan_handled_guest_\(scope)_v1" }

    init() { load() }

    func activate(accountID: String?) {
        let next = accountID.map { "account_\($0)" } ?? "guest"
        guard scope != next else { return }
        scope = next
        load()
        if accountID != nil {
            let guest = UserDefaults.standard.data(forKey: "hyse_meal_plan_guest_v1")
                .flatMap { try? JSONDecoder().decode([PlannedRecipe].self, from: $0) } ?? []
            let handled = Set(UserDefaults.standard.stringArray(forKey: handledGuestKey) ?? [])
            pendingGuestItems = guest.filter { !handled.contains($0.id.uuidString) }
        } else {
            pendingGuestItems = []
        }
        pendingGuestMergeCount = pendingGuestItems.count
    }

    func resolveGuestMerge(shouldMerge: Bool) {
        guard scope != "guest", !pendingGuestItems.isEmpty else { return }
        if shouldMerge {
            let known = Set(items.map(\.id))
            items.append(contentsOf: pendingGuestItems.filter { !known.contains($0.id) })
            items.sort { $0.date < $1.date }
            save()
            let guestChecks = UserDefaults.standard.stringArray(forKey: "hyse_meal_plan_checked_guest_v1") ?? []
            checkedIngredients.formUnion(guestChecks)
            UserDefaults.standard.set(Array(checkedIngredients), forKey: checkedKey)
        }
        var handled = Set(UserDefaults.standard.stringArray(forKey: handledGuestKey) ?? [])
        handled.formUnion(pendingGuestItems.map { $0.id.uuidString })
        UserDefaults.standard.set(Array(handled), forKey: handledGuestKey)
        pendingGuestItems = []
        pendingGuestMergeCount = 0
    }

    func add(recipe: Recipe, date: Date, servings: Double, category: MealCategory) {
        guard servings.isFinite, servings > 0, servings <= 100 else { return }
        items.append(PlannedRecipe(date: date, recipe: recipe, servings: servings,
                                   categoryID: category.id, categoryName: category.storageKey))
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func items(for date: Date) -> [PlannedRecipe] {
        items.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func markLogged(_ id: UUID, entryID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].loggedEntryID = entryID
        save()
    }

    func toggleChecked(_ key: String) {
        if checkedIngredients.contains(key) { checkedIngredients.remove(key) }
        else { checkedIngredients.insert(key) }
        UserDefaults.standard.set(Array(checkedIngredients), forKey: checkedKey)
    }

    private func load() {
        items = (UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([PlannedRecipe].self, from: $0) } ?? [])
            .sorted { $0.date < $1.date }
        checkedIngredients = Set(UserDefaults.standard.stringArray(forKey: checkedKey) ?? [])
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: key)
    }
}

struct MealPlanAddView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var plan: MealPlanStore
    @ObservedObject var categories: CategoryStore
    let recipe: Recipe
    @State private var date: Date
    @State private var servings = 1.0
    @State private var categoryID: UUID?
    private func t(_ key: String) -> String { language.text(key) }

    init(plan: MealPlanStore, categories: CategoryStore, recipe: Recipe, initialDate: Date = Date()) {
        self.plan = plan
        self.categories = categories
        self.recipe = recipe
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(recipe.name).font(.headline)
                    DatePicker(t("meal_plan.date"), selection: $date, displayedComponents: .date)
                    Stepper(value: $servings, in: 0.5...20, step: 0.5) {
                        LabeledContent(t("meal_plan.servings"), value: servings.formatted(.number.precision(.fractionLength(0...1))))
                    }
                    Picker(t("meal_plan.meal"), selection: $categoryID) {
                        ForEach(categories.categories) { category in
                            Text(category.localizedName).tag(Optional(category.id))
                        }
                    }
                }
            }
            .navigationTitle(t("meal_plan.add"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("app_tabs.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("meal_plan.add")) {
                        guard let category = categories.categories.first(where: { $0.id == categoryID }) ?? categories.categories.first else { return }
                        plan.add(recipe: recipe, date: date, servings: servings, category: category)
                        dismiss()
                    }
                    .disabled(categories.categories.isEmpty)
                }
            }
            .onAppear { categoryID = categoryID ?? categories.categories.first?.id }
        }
    }
}

struct MealPlanView: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var plan: MealPlanStore
    @ObservedObject var recipes: RecipeStore
    @ObservedObject var categories: CategoryStore
    @ObservedObject var calories: CalorieStore
    @State private var weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    @State private var selectedRecipe: Recipe?
    @State private var showingRecipePicker = false
    @State private var recipeSearch = ""
    @State private var message: String?
    private func t(_ key: String) -> String { language.text(key) }

    private var weekDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var shoppingItems: [(key: String, name: String, amount: Double, unit: FoodUnit)] {
        var grouped: [String: (name: String, amount: Double, unit: FoodUnit)] = [:]
        for item in plan.items where weekDays.contains(where: { Calendar.current.isDate($0, inSameDayAs: item.date) }) {
            let multiplier = item.servings / max(item.recipe.servings, 0.0001)
            for ingredient in item.recipe.ingredients {
                let key = "\(ingredient.food.id.uuidString)|\(ingredient.unit.rawValue)"
                let existing = grouped[key]
                grouped[key] = (ingredient.food.displayName(using: language), (existing?.amount ?? 0) + ingredient.grams * multiplier, ingredient.unit)
            }
        }
        return grouped.map { (key: $0.key, name: $0.value.name, amount: $0.value.amount, unit: $0.value.unit) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var availableRecipes: [Recipe] {
        let all = recipes.recipes + recipes.globalRecipes
        return Array(all.lazy.filter {
            recipeSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(recipeSearch)
        }.prefix(100))
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(weekLabel).font(.headline).monospacedDigit()
                    Spacer()
                    Button { shiftWeek(1) } label: { Image(systemName: "chevron.right") }
                }
            }
            ForEach(weekDays, id: \.self) { day in
                Section(day.formatted(.dateTime.weekday(.wide).day().month().locale(language.locale))) {
                    let entries = plan.items(for: day)
                    if entries.isEmpty {
                        Text(t("meal_plan.empty_day")).foregroundStyle(.secondary)
                    }
                    ForEach(entries) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.recipe.name).font(.subheadline.weight(.semibold))
                                Text("\(item.servings.formatted(.number.precision(.fractionLength(0...1)))) × \(categories.categories.first(where: { $0.id == item.categoryID })?.localizedName ?? item.categoryName)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let entryID = item.loggedEntryID, calories.entries.contains(where: { $0.id == entryID }) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(HyseColor.success)
                            } else if day <= Calendar.current.startOfDay(for: Date()) {
                                Button(t("meal_plan.log")) { log(item) }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .swipeActions { Button(role: .destructive) { plan.remove(item.id) } label: { Label(t("settings.delete"), systemImage: "trash") } }
                    }
                }
            }
            Section(t("meal_plan.shopping_list")) {
                if shoppingItems.isEmpty { Text(t("meal_plan.empty_shopping")).foregroundStyle(.secondary) }
                ForEach(shoppingItems, id: \.key) { ingredient in
                    Button { plan.toggleChecked(shoppingCheckKey(ingredient.key)) } label: {
                        HStack {
                            Image(systemName: plan.checkedIngredients.contains(shoppingCheckKey(ingredient.key)) ? "checkmark.circle.fill" : "circle")
                            Text(ingredient.name)
                            Spacer()
                            Text("\(Int(ingredient.amount.rounded())) \(ingredient.unit.rawValue)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle(t("meal_plan.title"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button { showingRecipePicker = true } label: { Label(t("meal_plan.add"), systemImage: "plus") } } }
        .sheet(isPresented: $showingRecipePicker) {
            NavigationStack {
                List(availableRecipes) { recipe in
                    Button(recipe.name) {
                        showingRecipePicker = false
                        DispatchQueue.main.async { selectedRecipe = recipe }
                    }
                }
                .searchable(text: $recipeSearch, prompt: t("recipes.search_recipes"))
                .navigationTitle(t("meal_plan.choose_recipe"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("app_tabs.cancel")) { showingRecipePicker = false } } }
            }
        }
        .sheet(item: $selectedRecipe) { recipe in
            MealPlanAddView(plan: plan, categories: categories, recipe: recipe,
                            initialDate: Calendar.current.isDate(weekStart, equalTo: Date(), toGranularity: .weekOfYear) ? Date() : weekStart)
        }
        .alert(t("meal_plan.title"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(t("common.ok")) { message = nil }
        } message: { Text(message ?? "") }
    }

    private var weekLabel: String {
        guard let end = weekDays.last else { return "" }
        return "\(weekStart.formatted(.dateTime.day().month(.abbreviated).locale(language.locale))) – \(end.formatted(.dateTime.day().month(.abbreviated).locale(language.locale)))"
    }
    private func shiftWeek(_ offset: Int) {
        weekStart = Calendar.current.date(byAdding: .weekOfYear, value: offset, to: weekStart) ?? weekStart
    }
    private func shoppingCheckKey(_ ingredientKey: String) -> String {
        "\(StreakTracker.dayKey(for: weekStart, calendar: .current))|\(ingredientKey)"
    }

    private func log(_ item: PlannedRecipe) {
        guard let category = categories.categories.first(where: { $0.id == item.categoryID })
                ?? categories.categories.first(where: { $0.storageKey == item.categoryName })
                ?? categories.categories.first else { return }
        let recipe = item.recipe
        let grams = recipe.gramsPerServing * item.servings
        let nutrients = recipe.nutrientsPer100g
        let addedSugar = recipe.ingredients.reduce(0.0) { $0 + ($1.food.isFruit ? 0 : $1.food.sugarPer100g * $1.grams / 100) } / recipe.totalGrams * 100
        let fruitSugar = recipe.ingredients.reduce(0.0) { $0 + ($1.food.isFruit ? $1.food.sugarPer100g * $1.grams / 100 : 0) } / recipe.totalGrams * 100
        let entry = CalorieEntry(
            recipeId: recipe.id,
            userRecipeRecordID: recipe.origin == .personal ? recipe.remoteID : nil,
            globalRecipeRecordID: recipe.origin == .global ? (recipe.globalRecordID ?? recipe.remoteID) : recipe.globalRecordID,
            name: recipe.name, grams: grams, categoryId: category.id, categoryName: category.storageKey,
            unit: .gram, kcalPer100g: nutrients.kcal, carbsPer100g: nutrients.carbs,
            proteinPer100g: nutrients.protein, fatPer100g: nutrients.fat,
            addedSugarPer100g: addedSugar, fruitSugarPer100g: fruitSugar,
            fiberPer100g: nutrients.fiber, saturatedFatPer100g: nutrients.saturatedFat,
            saltPer100g: nutrients.salt, date: item.date
        )
        if calories.addEntry(entry) { plan.markLogged(item.id, entryID: entry.id) }
        else { message = calories.lastFoodTrackingRestriction?.message(using: language) ?? t("meal_plan.log_failed") }
    }
}
